-- ============================================================
-- 132 — Revert the Demo Partner → Weihai Huigao membership
--        and give Demo Partner Manufacturing its OWN copies
--        of the master BOMs for testing.
--
-- Why: migration 131 added partner.demo@rrev.app as a Manager
-- at Weihai Huigao for quick testing. Weihai Huigao is a real
-- production partner — they shouldn't have demo / test accounts
-- on the membership list. Better to give Demo Partner
-- Manufacturing its own clones of the 5 master BOMs so the
-- demo account can play without touching anything real.
--
-- This migration:
--   1. Removes the demo membership at Weihai Huigao
--   2. Clones each master BOM ("<Model> Edition V1" assigned to
--      Weihai Huigao) as "<Model> Edition V1 (Demo)" and assigns
--      the copy to Demo Partner Manufacturing, including all
--      bom_lines and their supplier/price/notes data
--
-- Idempotent — re-running this migration is a no-op.
-- ============================================================

begin;

-- ── 1. Revert demo membership at Weihai Huigao ──────────────
do $$
declare
  v_huigao uuid;
  v_demo_user uuid;
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
    delete from public.manufacturer_memberships
    where manufacturer_id = v_huigao
      and user_id = v_demo_user;
  end if;
end $$;

-- ── 2. Clone Weihai Huigao master BOMs → Demo Partner ───────
do $$
declare
  v_huigao uuid;
  v_demo_mfr uuid;
  v_bom record;
  v_clone_id uuid;
begin
  select id into v_huigao
  from public.manufacturers
  where name ilike '%huigao%' and name ilike '%weihai%'
  limit 1;

  select id into v_demo_mfr
  from public.manufacturers
  where name ilike '%demo partner%'
  limit 1;

  if v_huigao is null or v_demo_mfr is null then
    raise notice 'Source / destination manufacturer not found — skipping clones.';
    return;
  end if;

  -- For each master BOM currently assigned to Weihai Huigao
  for v_bom in
    select id, product_id, name, version, notes
    from public.boms
    where assigned_manufacturer_id = v_huigao
      and is_active = true
  loop
    -- Skip if a demo copy already exists (idempotency)
    select id into v_clone_id
    from public.boms
    where assigned_manufacturer_id = v_demo_mfr
      and product_id = v_bom.product_id
      and name = v_bom.name || ' (Demo)';

    if v_clone_id is null then
      -- Create the demo copy
      insert into public.boms (product_id, name, version, is_active, notes, assigned_manufacturer_id)
      values (
        v_bom.product_id,
        v_bom.name || ' (Demo)',
        v_bom.version,
        true,
        coalesce(v_bom.notes, '') ||
          E'\n\n[Demo copy — for partner.demo@rrev.app testing. Not synced to the source BOM.]',
        v_demo_mfr
      )
      returning id into v_clone_id;

      -- Copy all bom_lines including supplier / price / notes
      insert into public.bom_lines (
        bom_id, product_id, quantity, unit, notes, sort_order,
        supplier_id, supplier_name, avg_unit_price, price_currency
      )
      select
        v_clone_id, product_id, quantity, unit, notes, sort_order,
        supplier_id, supplier_name, avg_unit_price, price_currency
      from public.bom_lines
      where bom_id = v_bom.id;
    end if;
  end loop;
end $$;

commit;
