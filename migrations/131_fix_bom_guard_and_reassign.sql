-- ============================================================
-- 131 — Fix BOM guard trigger + re-run model BOM assignments
--
-- Migration 129 hit:
--   ERROR: Partners cannot reassign a BOM to a different
--   manufacturer or product
--   CONTEXT: PL/pgSQL function guard_partner_bom_update() line 9
--
-- Why: guard_partner_bom_update() (from migration 128) only
-- bypassed when public.is_employee() or public.is_admin() —
-- both return false when there's no auth.uid() (which is the
-- case for Supabase Studio SQL Editor + cron / service-role
-- callers). Result: the trigger fired on the BOM-assignment
-- UPDATE statements inside migration 129 and rejected them.
--
-- Fix: bypass when auth.uid() is null (system context) as well.
--
-- After the trigger is fixed, the assignments from 129 are
-- re-run idempotently and Demo Partner Manager (the partner.demo
-- account) is added as a Manager at Weihai Huigao so they can
-- log in and test the BOM editor.
-- ============================================================

begin;

-- ── 1. Trigger fix ──────────────────────────────────────────
create or replace function public.guard_partner_bom_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- System / employee / admin contexts bypass entirely.
  if auth.uid() is null
     or public.is_employee()
     or public.is_admin() then
    return new;
  end if;

  if new.assigned_manufacturer_id is distinct from old.assigned_manufacturer_id
     or new.product_id is distinct from old.product_id then
    raise exception 'Partners cannot reassign a BOM to a different manufacturer or product';
  end if;
  return new;
end;
$$;

-- ── 2. Re-run the 129 assignments (now that the guard allows
--      service-role / Studio contexts through) ──────────────
do $$
declare
  v_huigao uuid;
  v_product_outland uuid;
  v_product_baja uuid;
  v_product_titan uuid;
  v_product_exp uuid;
  v_product_hd uuid;
  v_bom_id uuid;
begin
  select id into v_huigao
  from public.manufacturers
  where name ilike '%huigao%' and name ilike '%weihai%'
  limit 1;

  if v_huigao is null then
    raise notice 'Weihai Huigao manufacturer not found — skipping BOM assignment.';
    return;
  end if;

  select id into v_product_outland from public.products
    where name = 'RREV Outland Edition' and is_active = true
    order by created_at asc limit 1;
  select id into v_product_baja from public.products
    where name = 'RREV Baja Edition (Non-Bunk)' and is_active = true
    order by created_at asc limit 1;
  select id into v_product_titan from public.products
    where name = 'RREV Titan Edition (Non-Bunk)' and is_active = true
    order by created_at asc limit 1;
  select id into v_product_exp from public.products
    where name = 'RREV EXP Series' and is_active = true
    order by created_at asc limit 1;
  select id into v_product_hd from public.products
    where name = 'RREV HD SERIES' and is_active = true
    order by created_at asc limit 1;

  -- Outland Edition V1
  if v_product_outland is not null then
    select id into v_bom_id from public.boms
    where product_id = v_product_outland and name = 'Outland Edition V1';
    if v_bom_id is not null then
      update public.boms set assigned_manufacturer_id = v_huigao where id = v_bom_id;
    end if;
  end if;

  -- Baja Edition V1
  if v_product_baja is not null then
    select id into v_bom_id from public.boms
    where product_id = v_product_baja and name = 'Baja Edition V1';
    if v_bom_id is not null then
      update public.boms set assigned_manufacturer_id = v_huigao where id = v_bom_id;
    end if;
  end if;

  -- Titan Edition V1 / Titan Standard BOM
  if v_product_titan is not null then
    select id into v_bom_id from public.boms
    where product_id = v_product_titan
      and (name = 'Titan Edition V1' or name = 'Titan Standard BOM')
    order by version desc limit 1;
    if v_bom_id is not null then
      update public.boms set assigned_manufacturer_id = v_huigao where id = v_bom_id;
    end if;
  end if;

  -- EXP Series V1
  if v_product_exp is not null then
    select id into v_bom_id from public.boms
    where product_id = v_product_exp and name = 'EXP Series V1';
    if v_bom_id is not null then
      update public.boms set assigned_manufacturer_id = v_huigao where id = v_bom_id;
    end if;
  end if;

  -- HD Series V1
  if v_product_hd is not null then
    select id into v_bom_id from public.boms
    where product_id = v_product_hd and name = 'HD Series V1';
    if v_bom_id is not null then
      update public.boms set assigned_manufacturer_id = v_huigao where id = v_bom_id;
    end if;
  end if;
end $$;

-- ── 3. Grant Demo Partner Manager access to Weihai Huigao's
--      BOMs so the partner.demo@rrev.app account can log in
--      and test the editor end-to-end.
do $$
declare
  v_huigao uuid;
  v_demo_user uuid;
  v_existing uuid;
begin
  select id into v_huigao
  from public.manufacturers
  where name ilike '%huigao%' and name ilike '%weihai%'
  limit 1;

  select id into v_demo_user
  from public.profiles
  where email = 'partner.demo@rrev.app'
  limit 1;

  if v_huigao is not null and v_demo_user is not null then
    select id into v_existing
    from public.manufacturer_memberships
    where manufacturer_id = v_huigao
      and user_id = v_demo_user;

    if v_existing is null then
      insert into public.manufacturer_memberships (manufacturer_id, user_id, role, is_active)
      values (v_huigao, v_demo_user, 'manager', true);
    else
      update public.manufacturer_memberships
      set role = 'manager', is_active = true
      where id = v_existing;
    end if;
  end if;
end $$;

commit;
