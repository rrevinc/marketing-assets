-- ============================================================
-- 126 — Moderation queue for partner-posted progress updates.
--
-- Before this migration, anything a partner manufacturer posted
-- to build_progress_notes or build_progress_media was visible to
-- the customer the moment RLS allowed it. We want a checkpoint:
-- RREV staff review → approve / edit / reject → only then does
-- the customer see it.
--
-- Notes from RREV staff bypass the queue (auto-approved). Notes
-- from partners default to 'pending'. Customer RLS now requires
-- 'approved'. Existing rows are backfilled to 'approved' so we
-- don't hide anything that's already in production.
-- ============================================================

begin;

-- ── 1. Schema — moderation_status on both tables ─────────────

alter table public.build_progress_notes
  add column if not exists moderation_status text not null default 'approved'
    check (moderation_status in ('pending', 'approved', 'rejected'));

alter table public.build_progress_notes
  add column if not exists moderated_by uuid references public.profiles(id) on delete set null;

alter table public.build_progress_notes
  add column if not exists moderated_at timestamptz;

alter table public.build_progress_notes
  add column if not exists moderation_reason text;

alter table public.build_progress_media
  add column if not exists moderation_status text not null default 'approved'
    check (moderation_status in ('pending', 'approved', 'rejected'));

alter table public.build_progress_media
  add column if not exists moderated_by uuid references public.profiles(id) on delete set null;

alter table public.build_progress_media
  add column if not exists moderated_at timestamptz;

alter table public.build_progress_media
  add column if not exists moderation_reason text;

create index if not exists idx_build_progress_notes_moderation
  on public.build_progress_notes(build_id, moderation_status);
create index if not exists idx_build_progress_media_moderation
  on public.build_progress_media(build_id, moderation_status);

-- ── 2. Helper to detect partner-posted inserts ───────────────
create or replace function public.is_manufacturer_user(p_user uuid)
returns boolean as $$
  select exists (
    select 1 from public.profiles p
    where p.id = p_user
      and p.role = 'manufacturer'
  );
$$ language sql stable security definer set search_path = public;

-- ── 3. INSERT-time triggers normalize moderation_status ──────
-- Employees & admins → always 'approved' (their own posts bypass
-- the queue). Anyone else (manufacturer / customer) → 'pending'.
-- Existing 'rejected'/'approved' from explicit admin actions
-- pass through unchanged.

create or replace function public.set_moderation_status_on_progress_note()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.moderation_status is null or new.moderation_status = '' then
    new.moderation_status := 'approved';
  end if;

  if public.is_employee() or public.is_admin() then
    new.moderation_status := 'approved';
    new.moderated_by := coalesce(new.moderated_by, auth.uid());
    new.moderated_at := coalesce(new.moderated_at, now());
  elsif new.created_by is not null and public.is_manufacturer_user(new.created_by) then
    new.moderation_status := 'pending';
    new.moderated_by := null;
    new.moderated_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_moderation_status_progress_note on public.build_progress_notes;
create trigger trg_set_moderation_status_progress_note
  before insert on public.build_progress_notes
  for each row execute procedure public.set_moderation_status_on_progress_note();

create or replace function public.set_moderation_status_on_progress_media()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.moderation_status is null or new.moderation_status = '' then
    new.moderation_status := 'approved';
  end if;

  if public.is_employee() or public.is_admin() then
    new.moderation_status := 'approved';
    new.moderated_by := coalesce(new.moderated_by, auth.uid());
    new.moderated_at := coalesce(new.moderated_at, now());
  elsif new.uploaded_by is not null and public.is_manufacturer_user(new.uploaded_by) then
    new.moderation_status := 'pending';
    new.moderated_by := null;
    new.moderated_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_moderation_status_progress_media on public.build_progress_media;
create trigger trg_set_moderation_status_progress_media
  before insert on public.build_progress_media
  for each row execute procedure public.set_moderation_status_on_progress_media();

-- ── 4. UPDATE-time guards: stamp moderator on transition ──────

create or replace function public.touch_moderation_audit_progress_note()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.moderation_status is distinct from old.moderation_status then
    new.moderated_by := coalesce(new.moderated_by, auth.uid());
    new.moderated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_touch_moderation_progress_note on public.build_progress_notes;
create trigger trg_touch_moderation_progress_note
  before update on public.build_progress_notes
  for each row execute procedure public.touch_moderation_audit_progress_note();

create or replace function public.touch_moderation_audit_progress_media()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.moderation_status is distinct from old.moderation_status then
    new.moderated_by := coalesce(new.moderated_by, auth.uid());
    new.moderated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_touch_moderation_progress_media on public.build_progress_media;
create trigger trg_touch_moderation_progress_media
  before update on public.build_progress_media
  for each row execute procedure public.touch_moderation_audit_progress_media();

-- ── 5. Customer-facing RLS: only 'approved' rows ─────────────

drop policy if exists "Customers can view own build progress notes" on public.build_progress_notes;
create policy "Customers can view own build progress notes"
  on public.build_progress_notes for select
  using (
    moderation_status = 'approved'
    and visibility in ('customer', 'both')
    and exists (
      select 1
      from public.build_configurations bc
      where bc.id = build_progress_notes.build_id
        and bc.customer_id = auth.uid()
    )
  );

drop policy if exists "Customers can view own build progress media" on public.build_progress_media;
create policy "Customers can view own build progress media"
  on public.build_progress_media for select
  using (
    moderation_status = 'approved'
    and visibility in ('customer', 'both')
    and exists (
      select 1
      from public.build_configurations bc
      where bc.id = build_progress_media.build_id
        and bc.customer_id = auth.uid()
    )
  );

-- (Employees + assigned partners keep their existing read access.
--  Their policies don't reference moderation_status, so they see
--  everything regardless of state.)

-- ── 6. Backfill: anything already in the table is approved ───
-- The column default keeps new rows safe; this catches anything
-- that was inserted BEFORE this migration ran (in case the
-- defaults weren't applied for some path).
update public.build_progress_notes
   set moderation_status = 'approved'
 where moderation_status is null
    or moderation_status = '';

update public.build_progress_media
   set moderation_status = 'approved'
 where moderation_status is null
    or moderation_status = '';

commit;
