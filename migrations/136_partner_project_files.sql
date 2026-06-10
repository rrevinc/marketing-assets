-- ============================================================
-- 136 — CAD collaboration: partner-shareable projects + files
--
-- Extends the projects module so RREV can share specific
-- engineering projects with partner manufacturers. Files (STEP
-- CAD, PDF drawings, deliverables, references) get version
-- history, and partner Managers can both download and upload
-- new revisions.
--
-- Same gating pattern as the BOM partner work (migrations 128,
-- 130, 133):
--   - Per-project assigned_manufacturer_id + is_partner_shared
--   - Partner SELECT gated by share + manufacturer membership
--   - Partner INSERT/UPDATE on revisions + comments by Manager
--     role only
--   - Employees keep their existing access; nothing taken away
-- ============================================================

begin;

-- ── 1. Extend projects ──────────────────────────────────────
alter table public.projects
  add column if not exists assigned_manufacturer_id uuid
    references public.manufacturers(id) on delete set null;
alter table public.projects
  add column if not exists is_partner_shared boolean not null default false;

create index if not exists idx_projects_assigned_manufacturer
  on public.projects(assigned_manufacturer_id)
  where assigned_manufacturer_id is not null;

-- ── 2. project_files ────────────────────────────────────────
create table if not exists public.project_files (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  task_id uuid references public.project_tasks(id) on delete set null,
  name text not null,
  category text not null default 'other'
    check (category in ('cad', 'drawing', 'deliverable', 'reference', 'other')),
  description text,
  -- "Current" revision fields are duplicated from the latest
  -- project_file_revisions row for fast listing. Updated by
  -- trigger whenever a new revision lands.
  current_revision_label text,
  current_storage_path text,
  current_file_name text,
  current_mime_type text,
  current_file_size bigint,
  uploaded_by uuid references public.profiles(id),
  uploaded_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_project_files_project on public.project_files(project_id);
create index if not exists idx_project_files_task on public.project_files(task_id);
create index if not exists idx_project_files_category on public.project_files(project_id, category);

create trigger update_project_files_updated_at
  before update on public.project_files
  for each row execute procedure public.update_updated_at();

-- ── 3. project_file_revisions ───────────────────────────────
create table if not exists public.project_file_revisions (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references public.project_files(id) on delete cascade,
  revision_label text not null,  -- "Rev A", "v1.2", "Final"
  storage_path text not null,
  file_name text not null,
  mime_type text,
  file_size bigint,
  notes text,
  uploaded_by uuid references public.profiles(id),
  uploaded_at timestamptz not null default now()
);

create index if not exists idx_project_file_revisions_file
  on public.project_file_revisions(file_id, uploaded_at desc);

-- Trigger: on new revision insert, point the parent file's
-- current_* fields at the newest revision.
create or replace function public.refresh_project_file_current_revision()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.project_files
  set current_revision_label = new.revision_label,
      current_storage_path = new.storage_path,
      current_file_name = new.file_name,
      current_mime_type = new.mime_type,
      current_file_size = new.file_size,
      updated_at = now()
  where id = new.file_id;
  return new;
end;
$$;

drop trigger if exists trg_refresh_project_file_current_revision on public.project_file_revisions;
create trigger trg_refresh_project_file_current_revision
  after insert on public.project_file_revisions
  for each row execute procedure public.refresh_project_file_current_revision();

-- ── 4. project_file_comments ────────────────────────────────
create table if not exists public.project_file_comments (
  id uuid primary key default gen_random_uuid(),
  file_id uuid not null references public.project_files(id) on delete cascade,
  body text not null,
  author_id uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_project_file_comments_file
  on public.project_file_comments(file_id, created_at desc);

-- ── 5. Enable RLS ───────────────────────────────────────────
alter table public.project_files enable row level security;
alter table public.project_file_revisions enable row level security;
alter table public.project_file_comments enable row level security;

-- ── 6. RLS — Employees ──────────────────────────────────────
drop policy if exists "Employees manage project files" on public.project_files;
create policy "Employees manage project files"
  on public.project_files for all
  using (public.is_employee())
  with check (public.is_employee());

drop policy if exists "Employees manage project file revisions" on public.project_file_revisions;
create policy "Employees manage project file revisions"
  on public.project_file_revisions for all
  using (public.is_employee())
  with check (public.is_employee());

drop policy if exists "Employees manage project file comments" on public.project_file_comments;
create policy "Employees manage project file comments"
  on public.project_file_comments for all
  using (public.is_employee())
  with check (public.is_employee());

-- ── 7. RLS — Partners (Projects: SELECT only) ───────────────
-- Partner SELECT on the parent project IF it's shared with their
-- manufacturer. Required for project_files RLS below to be
-- meaningful for partners.
drop policy if exists "Partners view shared projects" on public.projects;
create policy "Partners view shared projects"
  on public.projects for select
  using (
    is_partner_shared = true
    and assigned_manufacturer_id is not null
    and public.has_manufacturer_access(assigned_manufacturer_id)
  );

drop policy if exists "Partners view shared project stages" on public.project_stages;
create policy "Partners view shared project stages"
  on public.project_stages for select
  using (
    exists (
      select 1 from public.projects p
      where p.id = project_stages.project_id
        and p.is_partner_shared = true
        and p.assigned_manufacturer_id is not null
        and public.has_manufacturer_access(p.assigned_manufacturer_id)
    )
  );

drop policy if exists "Partners view shared project tasks" on public.project_tasks;
create policy "Partners view shared project tasks"
  on public.project_tasks for select
  using (
    exists (
      select 1 from public.projects p
      where p.id = project_tasks.project_id
        and p.is_partner_shared = true
        and p.assigned_manufacturer_id is not null
        and public.has_manufacturer_access(p.assigned_manufacturer_id)
    )
  );

drop policy if exists "Partners view shared project milestones" on public.project_milestones;
create policy "Partners view shared project milestones"
  on public.project_milestones for select
  using (
    exists (
      select 1 from public.projects p
      where p.id = project_milestones.project_id
        and p.is_partner_shared = true
        and p.assigned_manufacturer_id is not null
        and public.has_manufacturer_access(p.assigned_manufacturer_id)
    )
  );

-- ── 8. RLS — Partners (Files) ───────────────────────────────
-- SELECT: any active member of the assigned manufacturer on
-- a shared project can see files.
drop policy if exists "Partners view shared project files" on public.project_files;
create policy "Partners view shared project files"
  on public.project_files for select
  using (
    exists (
      select 1 from public.projects p
      where p.id = project_files.project_id
        and p.is_partner_shared = true
        and p.assigned_manufacturer_id is not null
        and public.has_manufacturer_access(p.assigned_manufacturer_id)
    )
  );

-- Same for revisions
drop policy if exists "Partners view shared project file revisions" on public.project_file_revisions;
create policy "Partners view shared project file revisions"
  on public.project_file_revisions for select
  using (
    exists (
      select 1 from public.project_files pf
      join public.projects p on p.id = pf.project_id
      where pf.id = project_file_revisions.file_id
        and p.is_partner_shared = true
        and p.assigned_manufacturer_id is not null
        and public.has_manufacturer_access(p.assigned_manufacturer_id)
    )
  );

-- Same for comments
drop policy if exists "Partners view shared project file comments" on public.project_file_comments;
create policy "Partners view shared project file comments"
  on public.project_file_comments for select
  using (
    exists (
      select 1 from public.project_files pf
      join public.projects p on p.id = pf.project_id
      where pf.id = project_file_comments.file_id
        and p.is_partner_shared = true
        and p.assigned_manufacturer_id is not null
        and public.has_manufacturer_access(p.assigned_manufacturer_id)
    )
  );

-- ── 9. RLS — Partner WRITE (Manager only) ───────────────────
-- Partners cannot create new top-level files (RREV decides what
-- belongs in the project). But Managers CAN upload new
-- revisions of an existing file + post comments.
drop policy if exists "Partner managers upload new project file revisions" on public.project_file_revisions;
create policy "Partner managers upload new project file revisions"
  on public.project_file_revisions for insert
  with check (
    uploaded_by = auth.uid()
    and exists (
      select 1 from public.project_files pf
      join public.projects p on p.id = pf.project_id
      where pf.id = project_file_revisions.file_id
        and p.is_partner_shared = true
        and p.assigned_manufacturer_id is not null
        and public.has_manufacturer_role(
          p.assigned_manufacturer_id,
          array['manager']
        )
    )
  );

drop policy if exists "Partners post comments on shared project files" on public.project_file_comments;
create policy "Partners post comments on shared project files"
  on public.project_file_comments for insert
  with check (
    author_id = auth.uid()
    and exists (
      select 1 from public.project_files pf
      join public.projects p on p.id = pf.project_id
      where pf.id = project_file_comments.file_id
        and p.is_partner_shared = true
        and p.assigned_manufacturer_id is not null
        and public.has_manufacturer_access(p.assigned_manufacturer_id)
    )
  );

-- ── 10. Realtime ────────────────────────────────────────────
alter publication supabase_realtime add table public.project_files;
alter publication supabase_realtime add table public.project_file_revisions;
alter publication supabase_realtime add table public.project_file_comments;

commit;
