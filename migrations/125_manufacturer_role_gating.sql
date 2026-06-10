-- ============================================================
-- 125 — Make manufacturer_memberships.role actually matter.
--
-- Until now, the three partner roles (manager / operator / qc)
-- were stored on manufacturer_memberships but every RLS check
-- used has_manufacturer_access() — which is role-agnostic.
-- All three could do everything.
--
-- This migration enforces a real division of labour:
--
--   MANAGER  — partner-side lead. Can do everything an operator
--              and a QC can do. Future hooks for inviting other
--              team members at their company live in app code.
--
--   OPERATOR — line worker. Updates progress %, status, posts
--              progress notes. Cannot submit QC checks.
--
--   QC       — quality inspector. Marks checklist items
--              pass/fail/na and submits partner QC submissions.
--              Cannot edit progress / status / progress notes.
--
-- All three still SEE everything for their manufacturer — gating
-- is on WRITES only.
-- ============================================================

begin;

-- ── 1. Role-aware membership check ───────────────────────────
create or replace function public.has_manufacturer_role(
  p_manufacturer_id uuid,
  p_allowed_roles text[]
)
returns boolean as $$
  select exists (
    select 1
    from public.manufacturer_memberships mm
    where mm.manufacturer_id = p_manufacturer_id
      and mm.user_id = auth.uid()
      and mm.is_active = true
      and mm.role = any(p_allowed_roles)
  );
$$ language sql stable security definer set search_path = public;

comment on function public.has_manufacturer_role(uuid, text[]) is
  'Returns true if the current auth.uid() has an active manufacturer_memberships row with one of the listed roles.';

-- ── 2. build_progress_items — manager + operator can update ──
--
-- The guard trigger from migration 046 already blocks partners
-- from changing structural columns (name/sort/etc). We extend it
-- to block QC entirely.

create or replace function public.guard_partner_build_progress_item_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Employees / admins bypass — same as before.
  if public.is_employee() or public.is_admin() then
    return new;
  end if;

  -- Must be an assigned partner.
  if old.assigned_manufacturer_id is null
     or not public.has_manufacturer_access(old.assigned_manufacturer_id)
  then
    raise exception 'Not authorized to update this build progress item';
  end if;

  -- Only manager + operator can write progress updates.
  -- QC users get a clear, user-facing message.
  if not public.has_manufacturer_role(
    old.assigned_manufacturer_id,
    array['manager', 'operator']
  ) then
    raise exception 'Your manufacturer role (QC) cannot update production progress. Ask a Manager or Operator to log this update.';
  end if;

  -- Existing structural-write protection.
  if new.name is distinct from old.name
     or new.sort_order is distinct from old.sort_order
     or new.weight is distinct from old.weight
     or new.customer_visible is distinct from old.customer_visible
     or new.is_custom is distinct from old.is_custom
     or new.build_id is distinct from old.build_id
     or new.item_code is distinct from old.item_code
     or new.assigned_manufacturer_id is distinct from old.assigned_manufacturer_id
  then
    raise exception 'Partners can only update status, progress, and notes';
  end if;

  return new;
end;
$$;

-- ── 3. build_progress_notes — manager + operator can insert ──
-- (QC blocked from posting progress-related notes; their channel
-- is the QC submissions table below.)

drop policy if exists "Assigned manufacturers can insert notes on assigned build progress items" on public.build_progress_notes;
create policy "Assigned manufacturers can insert notes on assigned build progress items"
  on public.build_progress_notes for insert
  with check (
    created_by = auth.uid()
    and visibility in ('customer', 'both')
    and exists (
      select 1
      from public.build_progress_items bpi
      where bpi.id = build_progress_notes.item_id
        and bpi.build_id = build_progress_notes.build_id
        and bpi.assigned_manufacturer_id is not null
        and public.has_manufacturer_role(
          bpi.assigned_manufacturer_id,
          array['manager', 'operator']
        )
    )
  );

-- ── 4. mo_qc_checklists — manager + QC can update ────────────

drop policy if exists "Assigned manufacturers can update assigned mo qc checklists" on public.mo_qc_checklists;
create policy "Assigned manufacturers can update assigned mo qc checklists"
  on public.mo_qc_checklists for update
  using (
    assigned_manufacturer_id is not null
    and public.has_manufacturer_role(
      assigned_manufacturer_id,
      array['manager', 'qc']
    )
  )
  with check (
    assigned_manufacturer_id is not null
    and public.has_manufacturer_role(
      assigned_manufacturer_id,
      array['manager', 'qc']
    )
  );

-- ── 5. mo_qc_checklist_items — manager + QC can update ───────

drop policy if exists "Assigned manufacturers can update assigned mo qc checklist items" on public.mo_qc_checklist_items;
create policy "Assigned manufacturers can update assigned mo qc checklist items"
  on public.mo_qc_checklist_items for update
  using (
    exists (
      select 1
      from public.mo_qc_checklists c
      where c.id = mo_qc_checklist_items.checklist_id
        and c.assigned_manufacturer_id is not null
        and public.has_manufacturer_role(
          c.assigned_manufacturer_id,
          array['manager', 'qc']
        )
    )
  )
  with check (
    exists (
      select 1
      from public.mo_qc_checklists c
      where c.id = mo_qc_checklist_items.checklist_id
        and c.assigned_manufacturer_id is not null
        and public.has_manufacturer_role(
          c.assigned_manufacturer_id,
          array['manager', 'qc']
        )
    )
  );

-- ── 6. mo_partner_qc_submissions — manager + QC can insert ───

drop policy if exists "Employees or assigned manufacturer can insert partner qc submissions" on public.mo_partner_qc_submissions;
create policy "Employees or assigned manufacturer can insert partner qc submissions"
  on public.mo_partner_qc_submissions for insert
  with check (
    submitted_by = auth.uid()
    and (
      public.is_employee()
      or exists (
        select 1
        from public.mo_partner_packages p
        where p.id = package_id
          and public.has_manufacturer_role(
            p.manufacturer_id,
            array['manager', 'qc']
          )
      )
    )
  );

-- ── 7. mo_partner_package_updates — split by update_type ─────
-- 'qc' updates require manager+qc; everything else requires
-- manager+operator. Employees still unrestricted.

drop policy if exists "Employees or assigned manufacturer can insert partner package updates" on public.mo_partner_package_updates;
create policy "Employees or assigned manufacturer can insert partner package updates"
  on public.mo_partner_package_updates for insert
  with check (
    author_id = auth.uid()
    and (
      public.is_employee()
      or (
        update_type = 'qc'
        and exists (
          select 1
          from public.mo_partner_packages p
          where p.id = package_id
            and public.has_manufacturer_role(
              p.manufacturer_id,
              array['manager', 'qc']
            )
        )
      )
      or (
        update_type <> 'qc'
        and exists (
          select 1
          from public.mo_partner_packages p
          where p.id = package_id
            and public.has_manufacturer_role(
              p.manufacturer_id,
              array['manager', 'operator']
            )
        )
      )
    )
  );

-- ── 8. mo_partner_packages — only manager + operator can update ──
-- (Direct progress/status updates on the package. QC works through
--  the submissions + checklist tables.)

drop policy if exists "Employees or assigned manufacturer can update partner packages" on public.mo_partner_packages;
create policy "Employees or assigned manufacturer can update partner packages"
  on public.mo_partner_packages for update
  using (
    public.is_employee()
    or public.has_manufacturer_role(
      manufacturer_id,
      array['manager', 'operator']
    )
  )
  with check (
    public.is_employee()
    or public.has_manufacturer_role(
      manufacturer_id,
      array['manager', 'operator']
    )
  );

commit;
