-- ============================================================
-- 130 — BOM line: supplier, avg price, and photo attachments
--
-- Adds three things to make BOM lines actually useful for
-- procurement:
--
--   1. Supplier name + optional FK to public.suppliers
--   2. Average unit price (numeric, with currency)
--   3. Photo attachments — new bom_line_media table mirroring
--      the build_progress_media pattern
--
-- All editable by partner Managers on assigned BOMs (RLS reuses
-- the policies from migration 128).
-- ============================================================

begin;

-- ── 1. New columns on bom_lines ──────────────────────────────
alter table public.bom_lines
  add column if not exists supplier_id uuid
    references public.suppliers(id) on delete set null;
alter table public.bom_lines
  add column if not exists supplier_name text;
alter table public.bom_lines
  add column if not exists avg_unit_price numeric(12,2);
alter table public.bom_lines
  add column if not exists price_currency text not null default 'USD';

create index if not exists idx_bom_lines_supplier on public.bom_lines(supplier_id);

-- ── 2. New media table for line photos ───────────────────────
create table if not exists public.bom_line_media (
  id uuid default gen_random_uuid() primary key,
  bom_line_id uuid not null references public.bom_lines(id) on delete cascade,
  storage_path text not null,
  file_name text not null,
  mime_type text,
  file_size bigint,
  media_type text not null default 'photo' check (media_type in ('photo', 'video', 'file')),
  caption text,
  uploaded_by uuid references public.profiles(id),
  uploaded_at timestamptz not null default now()
);

create index if not exists idx_bom_line_media_line on public.bom_line_media(bom_line_id);

alter table public.bom_line_media enable row level security;

-- ── 3. RLS — gated by parent BOM access ──────────────────────
-- Employees can see + manage everything
drop policy if exists "Employees can manage BOM line media" on public.bom_line_media;
create policy "Employees can manage BOM line media"
  on public.bom_line_media for all
  using (public.is_employee())
  with check (public.is_employee());

-- Partners can SELECT line media for any BOM line they can SELECT
drop policy if exists "Assigned manufacturers can view BOM line media" on public.bom_line_media;
create policy "Assigned manufacturers can view BOM line media"
  on public.bom_line_media for select
  using (
    exists (
      select 1
      from public.bom_lines bl
      join public.boms b on b.id = bl.bom_id
      where bl.id = bom_line_media.bom_line_id
        and b.assigned_manufacturer_id is not null
        and public.has_manufacturer_access(b.assigned_manufacturer_id)
    )
  );

-- Only Managers at the assigned manufacturer can INSERT line media
drop policy if exists "Assigned manufacturer managers can insert BOM line media" on public.bom_line_media;
create policy "Assigned manufacturer managers can insert BOM line media"
  on public.bom_line_media for insert
  with check (
    exists (
      select 1
      from public.bom_lines bl
      join public.boms b on b.id = bl.bom_id
      where bl.id = bom_line_media.bom_line_id
        and b.assigned_manufacturer_id is not null
        and public.has_manufacturer_role(
          b.assigned_manufacturer_id,
          array['manager']
        )
    )
  );

-- Same for DELETE
drop policy if exists "Assigned manufacturer managers can delete BOM line media" on public.bom_line_media;
create policy "Assigned manufacturer managers can delete BOM line media"
  on public.bom_line_media for delete
  using (
    exists (
      select 1
      from public.bom_lines bl
      join public.boms b on b.id = bl.bom_id
      where bl.id = bom_line_media.bom_line_id
        and b.assigned_manufacturer_id is not null
        and public.has_manufacturer_role(
          b.assigned_manufacturer_id,
          array['manager']
        )
    )
  );

commit;
