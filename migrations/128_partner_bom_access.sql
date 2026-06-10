-- ============================================================
-- 128 — Partner-accessible BOMs.
--
-- Lets a manufacturer partner see and (Manager role only) edit
-- the BOMs assigned to them, same role-gating pattern as
-- mo_qc_checklists and build_progress_items.
--
-- - boms.assigned_manufacturer_id — explicit assignment
-- - Partners SELECT BOMs they're assigned to
-- - Manager-role partners INSERT/UPDATE/DELETE bom_lines on
--   assigned BOMs; Operator and QC can view only
-- - Employees keep their existing read/write access unchanged
-- ============================================================

begin;

alter table public.boms
  add column if not exists assigned_manufacturer_id uuid
    references public.manufacturers(id) on delete set null;

create index if not exists idx_boms_assigned_manufacturer
  on public.boms(assigned_manufacturer_id);

-- ── Partner SELECT on boms ───────────────────────────────────
drop policy if exists "Assigned manufacturers can view assigned BOMs" on public.boms;
create policy "Assigned manufacturers can view assigned BOMs"
  on public.boms for select
  using (
    assigned_manufacturer_id is not null
    and public.has_manufacturer_access(assigned_manufacturer_id)
  );

-- ── Partner SELECT on bom_lines (via parent BOM) ─────────────
drop policy if exists "Assigned manufacturers can view assigned BOM lines" on public.bom_lines;
create policy "Assigned manufacturers can view assigned BOM lines"
  on public.bom_lines for select
  using (
    exists (
      select 1
      from public.boms b
      where b.id = bom_lines.bom_id
        and b.assigned_manufacturer_id is not null
        and public.has_manufacturer_access(b.assigned_manufacturer_id)
    )
  );

-- ── Partner INSERT bom_lines: manager only ────────────────────
drop policy if exists "Assigned manufacturer managers can insert BOM lines" on public.bom_lines;
create policy "Assigned manufacturer managers can insert BOM lines"
  on public.bom_lines for insert
  with check (
    exists (
      select 1
      from public.boms b
      where b.id = bom_lines.bom_id
        and b.assigned_manufacturer_id is not null
        and public.has_manufacturer_role(
          b.assigned_manufacturer_id,
          array['manager']
        )
    )
  );

-- ── Partner UPDATE bom_lines: manager only ────────────────────
drop policy if exists "Assigned manufacturer managers can update BOM lines" on public.bom_lines;
create policy "Assigned manufacturer managers can update BOM lines"
  on public.bom_lines for update
  using (
    exists (
      select 1
      from public.boms b
      where b.id = bom_lines.bom_id
        and b.assigned_manufacturer_id is not null
        and public.has_manufacturer_role(
          b.assigned_manufacturer_id,
          array['manager']
        )
    )
  )
  with check (
    exists (
      select 1
      from public.boms b
      where b.id = bom_lines.bom_id
        and b.assigned_manufacturer_id is not null
        and public.has_manufacturer_role(
          b.assigned_manufacturer_id,
          array['manager']
        )
    )
  );

-- ── Partner DELETE bom_lines: manager only ────────────────────
drop policy if exists "Assigned manufacturer managers can delete BOM lines" on public.bom_lines;
create policy "Assigned manufacturer managers can delete BOM lines"
  on public.bom_lines for delete
  using (
    exists (
      select 1
      from public.boms b
      where b.id = bom_lines.bom_id
        and b.assigned_manufacturer_id is not null
        and public.has_manufacturer_role(
          b.assigned_manufacturer_id,
          array['manager']
        )
    )
  );

-- ── Partner UPDATE boms: manager only (assigned_manufacturer_id
--    is read-only for partners — only RREV can reassign) ──────
drop policy if exists "Assigned manufacturer managers can update BOM meta" on public.boms;
create policy "Assigned manufacturer managers can update BOM meta"
  on public.boms for update
  using (
    assigned_manufacturer_id is not null
    and public.has_manufacturer_role(
      assigned_manufacturer_id,
      array['manager']
    )
  )
  with check (
    assigned_manufacturer_id is not null
    and public.has_manufacturer_role(
      assigned_manufacturer_id,
      array['manager']
    )
  );

-- Guard trigger: partners can edit notes + name but cannot reassign
-- the BOM to a different manufacturer or change its product.
create or replace function public.guard_partner_bom_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_employee() or public.is_admin() then
    return new;
  end if;

  if new.assigned_manufacturer_id is distinct from old.assigned_manufacturer_id
     or new.product_id is distinct from old.product_id then
    raise exception 'Partners cannot reassign a BOM to a different manufacturer or product';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_partner_bom_update on public.boms;
create trigger trg_guard_partner_bom_update
  before update on public.boms
  for each row execute procedure public.guard_partner_bom_update();

commit;
