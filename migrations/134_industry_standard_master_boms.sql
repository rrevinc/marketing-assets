-- ============================================================
-- 134 — Industry-standard master BOMs for the five models.
--
-- Drafts (and the user approved) a 14-category, ~153-component
-- structure based on industry-standard travel-trailer RV
-- engineering, with per-model variation. Propane (cat 14 in
-- the draft) is dropped — RREV is diesel + electric.
--
-- This migration:
--   1. Seeds 14 product_categories with stable sort_order.
--   2. Ensures every component product exists with the right
--      SKU + category + unit, idempotently.
--   3. Clears every existing line on the five master BOMs and
--      seeds fresh per-model BOMs:
--        Outland Edition V1 — compact trailer, single axle
--        Baja Edition V1    — medium trailer, dual axle
--        Titan Edition V1   — large trailer, dual axle, big tanks
--        EXP Series V1      — vehicle, skips chassis (cat 1)
--        HD Series V1       — vehicle 6x6, EXP + heavy-duty kit
--
-- Idempotent — re-running is safe.
-- ============================================================

begin;

-- ── 0. Helpers ────────────────────────────────────────────────
create or replace function _ensure_p(p_name text, p_sku text, p_cat_id uuid, p_unit text)
returns uuid language plpgsql as $$
declare v_id uuid;
begin
  if p_sku is not null then
    select id into v_id from public.products where sku = p_sku limit 1;
  end if;
  if v_id is null then
    select id into v_id from public.products where name = p_name and is_active limit 1;
  end if;
  if v_id is null then
    insert into public.products(name, sku, category_id, unit, is_active, type)
    values (p_name, p_sku, p_cat_id, coalesce(p_unit, 'unit'), true, 'product')
    returning id into v_id;
  else
    update public.products set category_id = coalesce(category_id, p_cat_id) where id = v_id;
  end if;
  return v_id;
end;
$$;

create or replace function _add(p_bom uuid, p_prod uuid, p_qty numeric, p_unit text, p_notes text)
returns void language plpgsql as $$
begin
  if p_bom is null or p_prod is null then return; end if;
  insert into public.bom_lines(bom_id, product_id, quantity, unit, notes, sort_order)
  values (
    p_bom, p_prod, p_qty, coalesce(p_unit, 'unit'), p_notes,
    coalesce((select max(sort_order) from public.bom_lines where bom_id = p_bom), -1) + 1
  );
end;
$$;

-- ── 1. Categories ─────────────────────────────────────────────
insert into public.product_categories (name, sort_order)
values
  ('Chassis & Frame', 101),
  ('Body Structure', 102),
  ('Windows & Doors', 103),
  ('Electrical 24V', 104),
  ('Plumbing & Water', 105),
  ('HVAC & Heating', 106),
  ('Kitchen', 107),
  ('Bathroom', 108),
  ('Sleeping & Seating', 109),
  ('Flooring & Finish', 110),
  ('Exterior Accessories', 111),
  ('Connectivity & Electronics', 112),
  ('Safety & Detection', 113),
  ('Hardware & Fasteners', 114)
on conflict do nothing;

-- ── 2. Main block ─────────────────────────────────────────────
do $$
declare
  cat_chassis     uuid;
  cat_body        uuid;
  cat_windows     uuid;
  cat_elec        uuid;
  cat_plumb       uuid;
  cat_hvac        uuid;
  cat_kitchen     uuid;
  cat_bath        uuid;
  cat_sleep       uuid;
  cat_floor       uuid;
  cat_ext         uuid;
  cat_conn        uuid;
  cat_safe        uuid;
  cat_hw          uuid;
  bom_o uuid; bom_b uuid; bom_t uuid; bom_e uuid; bom_h uuid;
  p uuid;
begin
  -- Resolve categories
  select id into cat_chassis from public.product_categories where name = 'Chassis & Frame';
  select id into cat_body    from public.product_categories where name = 'Body Structure';
  select id into cat_windows from public.product_categories where name = 'Windows & Doors';
  select id into cat_elec    from public.product_categories where name = 'Electrical 24V';
  select id into cat_plumb   from public.product_categories where name = 'Plumbing & Water';
  select id into cat_hvac    from public.product_categories where name = 'HVAC & Heating';
  select id into cat_kitchen from public.product_categories where name = 'Kitchen';
  select id into cat_bath    from public.product_categories where name = 'Bathroom';
  select id into cat_sleep   from public.product_categories where name = 'Sleeping & Seating';
  select id into cat_floor   from public.product_categories where name = 'Flooring & Finish';
  select id into cat_ext     from public.product_categories where name = 'Exterior Accessories';
  select id into cat_conn    from public.product_categories where name = 'Connectivity & Electronics';
  select id into cat_safe    from public.product_categories where name = 'Safety & Detection';
  select id into cat_hw      from public.product_categories where name = 'Hardware & Fasteners';

  -- Resolve BOMs (only the five master "<Model> V1" ones; not the (Demo) clones)
  select id into bom_o from public.boms where name = 'Outland Edition V1' limit 1;
  select id into bom_b from public.boms where name = 'Baja Edition V1'    limit 1;
  select id into bom_t from public.boms where name = 'Titan Edition V1'   limit 1;
  select id into bom_e from public.boms where name = 'EXP Series V1'      limit 1;
  select id into bom_h from public.boms where name = 'HD Series V1'       limit 1;

  -- Clear existing lines on the master BOMs
  delete from public.bom_lines where bom_id in (bom_o, bom_b, bom_t, bom_e, bom_h);

  -- ───────────────────────────────────────────────────────────
  -- CATEGORY 1: CHASSIS & FRAME (trailers only — EXP/HD skip)
  -- ───────────────────────────────────────────────────────────
  p := _ensure_p('Steel main chassis rails', 'RV-CH-001', cat_chassis, 'set');
    perform _add(bom_o, p, 1, 'set', 'Single axle config');
    perform _add(bom_b, p, 1, 'set', 'Dual axle config');
    perform _add(bom_t, p, 1, 'set', 'Dual axle reinforced');
  p := _ensure_p('Chassis cross members', 'RV-CH-002', cat_chassis, 'each');
    perform _add(bom_o, p, 4, 'each', null);
    perform _add(bom_b, p, 6, 'each', null);
    perform _add(bom_t, p, 7, 'each', null);
  p := _ensure_p('A-frame tongue tube', 'RV-CH-003', cat_chassis, 'each');
    perform _add(bom_o, p, 1, 'each', null);
    perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null);
  p := _ensure_p('Cruisemaster DO45+ off-road coupler', 'RV-CH-004', cat_chassis, 'each');
    perform _add(bom_o, p, 1, 'each', null);
    perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null);
  p := _ensure_p('Safety chains', 'RV-CH-005', cat_chassis, 'each');
    perform _add(bom_o, p, 2, 'each', null);
    perform _add(bom_b, p, 2, 'each', null);
    perform _add(bom_t, p, 2, 'each', null);
  p := _ensure_p('Breakaway switch with battery', 'RV-CH-006', cat_chassis, 'each');
    perform _add(bom_o, p, 1, 'each', null);
    perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null);
  p := _ensure_p('Tongue jack (5000 lb)', 'RV-CH-007', cat_chassis, 'each');
    perform _add(bom_o, p, 1, 'each', null);
    perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null);
  p := _ensure_p('Corner stabilizer jack', 'RV-CH-008', cat_chassis, 'each');
    perform _add(bom_o, p, 4, 'each', null);
    perform _add(bom_b, p, 4, 'each', null);
    perform _add(bom_t, p, 4, 'each', null);
  p := _ensure_p('Torsion axle', 'RV-CH-009', cat_chassis, 'each');
    perform _add(bom_o, p, 1, 'each', '3500 lb single');
    perform _add(bom_b, p, 2, 'each', '5200 lb dual');
    perform _add(bom_t, p, 2, 'each', '7000 lb dual');
  p := _ensure_p('Suspension equalizer', 'RV-CH-010', cat_chassis, 'each');
    perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null);
  p := _ensure_p('Heavy-duty shock absorber', 'RV-CH-011', cat_chassis, 'each');
    perform _add(bom_o, p, 2, 'each', null);
    perform _add(bom_b, p, 4, 'each', null);
    perform _add(bom_t, p, 4, 'each', null);
  p := _ensure_p('Method matte-black wheel 16"', 'RV-CH-012', cat_chassis, 'each');
    perform _add(bom_o, p, 3, 'each', '2 + 1 spare');
    perform _add(bom_b, p, 5, 'each', '4 + 1 spare');
    perform _add(bom_t, p, 5, 'each', '4 + 1 spare');
  p := _ensure_p('Mickey Thompson Baja A/T tire 33"', 'RV-CH-013', cat_chassis, 'each');
    perform _add(bom_o, p, 3, 'each', '2 + 1 spare');
    perform _add(bom_b, p, 5, 'each', '4 + 1 spare');
    perform _add(bom_t, p, 5, 'each', '4 + 1 spare');
  p := _ensure_p('Spare tire carrier (rear-mount)', 'RV-CH-014', cat_chassis, 'each');
    perform _add(bom_o, p, 1, 'each', null);
    perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null);
  p := _ensure_p('Heavy-duty aluminum rock sliders', 'RV-CH-015', cat_chassis, 'pair');
    perform _add(bom_o, p, 1, 'pair', null);
    perform _add(bom_b, p, 1, 'pair', null);
    perform _add(bom_t, p, 1, 'pair', null);
  p := _ensure_p('Underbody armor plating', 'RV-CH-016', cat_chassis, 'set');
    perform _add(bom_o, p, 1, 'set', null);
    perform _add(bom_b, p, 1, 'set', null);
    perform _add(bom_t, p, 1, 'set', null);

  -- ───────────────────────────────────────────────────────────
  -- CATEGORY 2: BODY STRUCTURE (all 5 models)
  -- ───────────────────────────────────────────────────────────
  p := _ensure_p('Aluminum side panel', 'RV-BD-001', cat_body, 'each');
    perform _add(bom_o, p, 2, 'each', null); perform _add(bom_b, p, 2, 'each', null);
    perform _add(bom_t, p, 2, 'each', null); perform _add(bom_e, p, 2, 'each', 'Habitat box panel'); perform _add(bom_h, p, 2, 'each', 'Habitat box panel');
  p := _ensure_p('One-piece aluminum roof panel', 'RV-BD-002', cat_body, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Aluminum tube wall framing', 'RV-BD-003', cat_body, 'm');
    perform _add(bom_o, p, 32, 'm', null); perform _add(bom_b, p, 48, 'm', null);
    perform _add(bom_t, p, 56, 'm', null); perform _add(bom_e, p, 50, 'm', null); perform _add(bom_h, p, 58, 'm', null);
  p := _ensure_p('Closed-cell foam insulation panel', 'RV-BD-004', cat_body, 'm2');
    perform _add(bom_o, p, 28, 'm2', 'R-13'); perform _add(bom_b, p, 38, 'm2', 'R-13');
    perform _add(bom_t, p, 46, 'm2', 'R-13'); perform _add(bom_e, p, 42, 'm2', 'R-15'); perform _add(bom_h, p, 50, 'm2', 'R-15');
  p := _ensure_p('Marine-grade Azdel subfloor panel', 'RV-BD-005', cat_body, 'm2');
    perform _add(bom_o, p, 12, 'm2', null); perform _add(bom_b, p, 18, 'm2', null);
    perform _add(bom_t, p, 22, 'm2', null); perform _add(bom_e, p, 20, 'm2', null); perform _add(bom_h, p, 24, 'm2', null);
  p := _ensure_p('Interior Azdel wall panel', 'RV-BD-006', cat_body, 'm2');
    perform _add(bom_o, p, 18, 'm2', null); perform _add(bom_b, p, 26, 'm2', null);
    perform _add(bom_t, p, 32, 'm2', null); perform _add(bom_e, p, 28, 'm2', null); perform _add(bom_h, p, 34, 'm2', null);
  p := _ensure_p('Exterior corner cap (molded)', 'RV-BD-007', cat_body, 'each');
    perform _add(bom_o, p, 4, 'each', null); perform _add(bom_b, p, 4, 'each', null);
    perform _add(bom_t, p, 4, 'each', null); perform _add(bom_e, p, 4, 'each', null); perform _add(bom_h, p, 4, 'each', null);
  p := _ensure_p('Front nose cap (molded composite)', 'RV-BD-008', cat_body, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null);
  p := _ensure_p('Rear cowling with AC integration', 'RV-BD-009', cat_body, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null);
  p := _ensure_p('Composite wheel well', 'RV-BD-010', cat_body, 'each');
    perform _add(bom_o, p, 2, 'each', null); perform _add(bom_b, p, 4, 'each', null); perform _add(bom_t, p, 4, 'each', null);
  p := _ensure_p('Aluminum trim molding', 'RV-BD-011', cat_body, 'm');
    perform _add(bom_o, p, 14, 'm', null); perform _add(bom_b, p, 18, 'm', null);
    perform _add(bom_t, p, 22, 'm', null); perform _add(bom_e, p, 20, 'm', null); perform _add(bom_h, p, 22, 'm', null);
  p := _ensure_p('Roof-to-wall sealant kit', 'RV-BD-012', cat_body, 'kit');
    perform _add(bom_o, p, 1, 'kit', null); perform _add(bom_b, p, 1, 'kit', null);
    perform _add(bom_t, p, 1, 'kit', null); perform _add(bom_e, p, 1, 'kit', null); perform _add(bom_h, p, 1, 'kit', null);

  -- ───────────────────────────────────────────────────────────
  -- CATEGORY 3: WINDOWS & DOORS (all 5)
  -- ───────────────────────────────────────────────────────────
  p := _ensure_p('Expedition entry door (peek window + screen)', 'RV-WD-001', cat_windows, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Door seal / weatherstrip', 'RV-WD-002', cat_windows, 'set');
    perform _add(bom_o, p, 1, 'set', null); perform _add(bom_b, p, 1, 'set', null);
    perform _add(bom_t, p, 1, 'set', null); perform _add(bom_e, p, 1, 'set', null); perform _add(bom_h, p, 1, 'set', null);
  p := _ensure_p('Door handle with cylinder lock', 'RV-WD-003', cat_windows, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Fold-down entry step', 'RV-WD-004', cat_windows, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Side window (single hung)', 'RV-WD-005', cat_windows, 'each');
    perform _add(bom_o, p, 3, 'each', null); perform _add(bom_b, p, 4, 'each', null);
    perform _add(bom_t, p, 5, 'each', null); perform _add(bom_e, p, 4, 'each', null); perform _add(bom_h, p, 4, 'each', null);
  p := _ensure_p('Safari hatch (over bed)', 'RV-WD-006', cat_windows, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Safari hatch (over dinette)', 'RV-WD-007', cat_windows, 'each');
    perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null);
    perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('MaxxAir roof vent fan', 'RV-WD-008', cat_windows, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 2, 'each', null); perform _add(bom_e, p, 2, 'each', null); perform _add(bom_h, p, 2, 'each', null);
  p := _ensure_p('Window screen', 'RV-WD-009', cat_windows, 'each');
    perform _add(bom_o, p, 3, 'each', null); perform _add(bom_b, p, 4, 'each', null);
    perform _add(bom_t, p, 5, 'each', null); perform _add(bom_e, p, 4, 'each', null); perform _add(bom_h, p, 4, 'each', null);

  -- ───────────────────────────────────────────────────────────
  -- CATEGORY 4: ELECTRICAL 24V (all 5)
  -- ───────────────────────────────────────────────────────────
  p := _ensure_p('LiFePO4 battery 24V 280AH', 'RV-EL-001', cat_elec, 'each');
    perform _add(bom_o, p, 1, 'each', null);
  p := _ensure_p('LiFePO4 battery 24V 560AH', 'RV-EL-002', cat_elec, 'each');
    perform _add(bom_b, p, 1, 'each', null);
  p := _ensure_p('LiFePO4 battery 24V 800AH', 'RV-EL-003', cat_elec, 'each');
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Victron BMV-712 battery monitor', 'RV-EL-004', cat_elec, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Victron MultiPlus II 24/3000VA inverter/charger', 'RV-EL-005', cat_elec, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Victron SmartSolar MPPT 150/85', 'RV-EL-006', cat_elec, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Solar panel 450W', 'RV-EL-007', cat_elec, 'each');
    perform _add(bom_o, p, 3, 'each', '1350W total'); perform _add(bom_b, p, 4, 'each', '1800W total');
    perform _add(bom_t, p, 4, 'each', '1800W total'); perform _add(bom_e, p, 4, 'each', '1800W total'); perform _add(bom_h, p, 4, 'each', '1800W total');
  p := _ensure_p('Roof solar combiner box', 'RV-EL-008', cat_elec, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('120V AC distribution panel', 'RV-EL-009', cat_elec, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('24V DC distribution panel', 'RV-EL-010', cat_elec, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('ANL fuse block 300A', 'RV-EL-011', cat_elec, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Class-T fuse 400A', 'RV-EL-012', cat_elec, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Battery shunt 500A', 'RV-EL-013', cat_elec, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Battery cable 4/0 AWG (per ft)', 'RV-EL-014', cat_elec, 'ft');
    perform _add(bom_o, p, 12, 'ft', null); perform _add(bom_b, p, 16, 'ft', null);
    perform _add(bom_t, p, 20, 'ft', null); perform _add(bom_e, p, 20, 'ft', null); perform _add(bom_h, p, 24, 'ft', null);
  p := _ensure_p('Branch wiring 12/24V (per ft)', 'RV-EL-015', cat_elec, 'ft');
    perform _add(bom_o, p, 250, 'ft', null); perform _add(bom_b, p, 350, 'ft', null);
    perform _add(bom_t, p, 420, 'ft', null); perform _add(bom_e, p, 380, 'ft', null); perform _add(bom_h, p, 450, 'ft', null);
  p := _ensure_p('30A shore power inlet', 'RV-EL-016', cat_elec, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Generator/shore transfer switch', 'RV-EL-017', cat_elec, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('LED marker / running light', 'RV-EL-018', cat_elec, 'each');
    perform _add(bom_o, p, 6, 'each', null); perform _add(bom_b, p, 8, 'each', null);
    perform _add(bom_t, p, 10, 'each', null); perform _add(bom_e, p, 10, 'each', null); perform _add(bom_h, p, 12, 'each', null);
  p := _ensure_p('Interior LED puck light', 'RV-EL-019', cat_elec, 'each');
    perform _add(bom_o, p, 8, 'each', null); perform _add(bom_b, p, 12, 'each', null);
    perform _add(bom_t, p, 14, 'each', null); perform _add(bom_e, p, 12, 'each', null); perform _add(bom_h, p, 14, 'each', null);
  p := _ensure_p('Exterior porch / awning LED light', 'RV-EL-020', cat_elec, 'each');
    perform _add(bom_o, p, 2, 'each', null); perform _add(bom_b, p, 2, 'each', null);
    perform _add(bom_t, p, 3, 'each', null); perform _add(bom_e, p, 3, 'each', null); perform _add(bom_h, p, 3, 'each', null);
  p := _ensure_p('Backup / reverse LED light', 'RV-EL-021', cat_elec, 'each');
    perform _add(bom_o, p, 2, 'each', null); perform _add(bom_b, p, 2, 'each', null);
    perform _add(bom_t, p, 2, 'each', null); perform _add(bom_e, p, 2, 'each', null); perform _add(bom_h, p, 2, 'each', null);

  -- ───────────────────────────────────────────────────────────
  -- CATEGORY 5: PLUMBING & WATER (all 5)
  -- ───────────────────────────────────────────────────────────
  p := _ensure_p('Fresh water tank 40 gal', 'RV-PL-001', cat_plumb, 'each');
    perform _add(bom_o, p, 1, 'each', null);
  p := _ensure_p('Fresh water tank 50 gal', 'RV-PL-002', cat_plumb, 'each');
    perform _add(bom_b, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null);
  p := _ensure_p('Fresh water tank 60 gal', 'RV-PL-003', cat_plumb, 'each');
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Grey water tank 30 gal', 'RV-PL-004', cat_plumb, 'each');
    perform _add(bom_o, p, 1, 'each', null);
  p := _ensure_p('Grey water tank 40 gal', 'RV-PL-005', cat_plumb, 'each');
    perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null);
    perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Black water tank 20 gal', 'RV-PL-006', cat_plumb, 'each');
    perform _add(bom_o, p, 1, 'each', null);
  p := _ensure_p('Black water tank 30 gal', 'RV-PL-007', cat_plumb, 'each');
    perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null);
    perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Shurflo 24V variable-speed water pump', 'RV-PL-008', cat_plumb, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Diesel hot water heater', 'RV-PL-009', cat_plumb, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Kitchen sink faucet (single lever)', 'RV-PL-010', cat_plumb, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Bathroom sink faucet', 'RV-PL-011', cat_plumb, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Shower head with diverter valve', 'RV-PL-012', cat_plumb, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Cassette toilet', 'RV-PL-013', cat_plumb, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Carbon + sediment water filter housing', 'RV-PL-014', cat_plumb, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('PEX tubing (per ft)', 'RV-PL-015', cat_plumb, 'ft');
    perform _add(bom_o, p, 90, 'ft', null); perform _add(bom_b, p, 120, 'ft', null);
    perform _add(bom_t, p, 140, 'ft', null); perform _add(bom_e, p, 120, 'ft', null); perform _add(bom_h, p, 140, 'ft', null);
  p := _ensure_p('PEX fittings + clamps kit', 'RV-PL-016', cat_plumb, 'kit');
    perform _add(bom_o, p, 1, 'kit', null); perform _add(bom_b, p, 1, 'kit', null);
    perform _add(bom_t, p, 1, 'kit', null); perform _add(bom_e, p, 1, 'kit', null); perform _add(bom_h, p, 1, 'kit', null);

  -- ───────────────────────────────────────────────────────────
  -- CATEGORY 6: HVAC & HEATING (all 5)
  -- ───────────────────────────────────────────────────────────
  p := _ensure_p('Webasto/Espar diesel air heater 5kW', 'RV-HV-001', cat_hvac, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('24V DC rooftop A/C 13.5K BTU', 'RV-HV-002', cat_hvac, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Air duct (per ft)', 'RV-HV-003', cat_hvac, 'ft');
    perform _add(bom_o, p, 16, 'ft', null); perform _add(bom_b, p, 22, 'ft', null);
    perform _add(bom_t, p, 28, 'ft', null); perform _add(bom_e, p, 24, 'ft', null); perform _add(bom_h, p, 28, 'ft', null);
  p := _ensure_p('Floor register', 'RV-HV-004', cat_hvac, 'each');
    perform _add(bom_o, p, 3, 'each', null); perform _add(bom_b, p, 4, 'each', null);
    perform _add(bom_t, p, 5, 'each', null); perform _add(bom_e, p, 4, 'each', null); perform _add(bom_h, p, 5, 'each', null);
  p := _ensure_p('Digital thermostat', 'RV-HV-005', cat_hvac, 'each');
    perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null);
    perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Insulated heater hose kit', 'RV-HV-006', cat_hvac, 'kit');
    perform _add(bom_o, p, 1, 'kit', null); perform _add(bom_b, p, 1, 'kit', null);
    perform _add(bom_t, p, 1, 'kit', null); perform _add(bom_e, p, 1, 'kit', null); perform _add(bom_h, p, 1, 'kit', null);

  -- ───────────────────────────────────────────────────────────
  -- CATEGORY 7: KITCHEN (all 5)
  -- ───────────────────────────────────────────────────────────
  p := _ensure_p('Solid-surface kitchen countertop', 'RV-KT-001', cat_kitchen, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Stainless single-bowl sink', 'RV-KT-002', cat_kitchen, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('12V/24V compressor fridge 8 cu ft', 'RV-KT-003', cat_kitchen, 'each'); perform _add(bom_o, p, 1, 'each', null);
  p := _ensure_p('12V/24V compressor fridge 10 cu ft', 'RV-KT-004', cat_kitchen, 'each'); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null);
  p := _ensure_p('12V/24V compressor fridge 12 cu ft', 'RV-KT-005', cat_kitchen, 'each'); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Induction 2-burner cooktop', 'RV-KT-006', cat_kitchen, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Inverter microwave 0.8 cu ft', 'RV-KT-007', cat_kitchen, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Upper cabinet box', 'RV-KT-008', cat_kitchen, 'each'); perform _add(bom_o, p, 3, 'each', null); perform _add(bom_b, p, 4, 'each', null); perform _add(bom_t, p, 5, 'each', null); perform _add(bom_e, p, 4, 'each', null); perform _add(bom_h, p, 4, 'each', null);
  p := _ensure_p('Base cabinet box', 'RV-KT-009', cat_kitchen, 'each'); perform _add(bom_o, p, 2, 'each', null); perform _add(bom_b, p, 3, 'each', null); perform _add(bom_t, p, 4, 'each', null); perform _add(bom_e, p, 3, 'each', null); perform _add(bom_h, p, 3, 'each', null);
  p := _ensure_p('Soft-close drawer slide pair', 'RV-KT-010', cat_kitchen, 'pair'); perform _add(bom_o, p, 4, 'pair', null); perform _add(bom_b, p, 6, 'pair', null); perform _add(bom_t, p, 8, 'pair', null); perform _add(bom_e, p, 6, 'pair', null); perform _add(bom_h, p, 6, 'pair', null);
  p := _ensure_p('Pantry shelving (set)', 'RV-KT-011', cat_kitchen, 'set'); perform _add(bom_o, p, 1, 'set', null); perform _add(bom_b, p, 1, 'set', null); perform _add(bom_t, p, 1, 'set', null); perform _add(bom_e, p, 1, 'set', null); perform _add(bom_h, p, 1, 'set', null);
  p := _ensure_p('Backsplash panel', 'RV-KT-012', cat_kitchen, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);

  -- ───────────────────────────────────────────────────────────
  -- CATEGORY 8: BATHROOM (all 5)
  -- ───────────────────────────────────────────────────────────
  p := _ensure_p('Fiberglass shower pan', 'RV-BA-001', cat_bath, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Shower wall panel', 'RV-BA-002', cat_bath, 'each'); perform _add(bom_o, p, 3, 'each', null); perform _add(bom_b, p, 3, 'each', null); perform _add(bom_t, p, 3, 'each', null); perform _add(bom_e, p, 3, 'each', null); perform _add(bom_h, p, 3, 'each', null);
  p := _ensure_p('Sliding shower door', 'RV-BA-003', cat_bath, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Vanity cabinet', 'RV-BA-004', cat_bath, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Vanity sink basin', 'RV-BA-005', cat_bath, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Medicine cabinet with mirror', 'RV-BA-006', cat_bath, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Bathroom exhaust fan', 'RV-BA-007', cat_bath, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Towel rail', 'RV-BA-008', cat_bath, 'each'); perform _add(bom_o, p, 2, 'each', null); perform _add(bom_b, p, 2, 'each', null); perform _add(bom_t, p, 2, 'each', null); perform _add(bom_e, p, 2, 'each', null); perform _add(bom_h, p, 2, 'each', null);

  -- ───────────────────────────────────────────────────────────
  -- CATEGORY 9: SLEEPING & SEATING (all 5)
  -- ───────────────────────────────────────────────────────────
  p := _ensure_p('Bed platform with slats', 'RV-SL-001', cat_sleep, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Memory-foam mattress queen', 'RV-SL-002', cat_sleep, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Dinette frame', 'RV-SL-003', cat_sleep, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Dinette cushion set (foam + upholstery)', 'RV-SL-004', cat_sleep, 'set'); perform _add(bom_o, p, 1, 'set', null); perform _add(bom_b, p, 1, 'set', null); perform _add(bom_t, p, 1, 'set', null); perform _add(bom_e, p, 1, 'set', null); perform _add(bom_h, p, 1, 'set', null);
  p := _ensure_p('Drop-down dinette table', 'RV-SL-005', cat_sleep, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Under-seat storage drawer', 'RV-SL-006', cat_sleep, 'each'); perform _add(bom_o, p, 2, 'each', null); perform _add(bom_b, p, 2, 'each', null); perform _add(bom_t, p, 3, 'each', null); perform _add(bom_e, p, 2, 'each', null); perform _add(bom_h, p, 2, 'each', null);
  p := _ensure_p('Day/night blackout shade', 'RV-SL-007', cat_sleep, 'each'); perform _add(bom_o, p, 3, 'each', null); perform _add(bom_b, p, 4, 'each', null); perform _add(bom_t, p, 5, 'each', null); perform _add(bom_e, p, 4, 'each', null); perform _add(bom_h, p, 4, 'each', null);
  p := _ensure_p('Curtain rail', 'RV-SL-008', cat_sleep, 'each'); perform _add(bom_o, p, 2, 'each', null); perform _add(bom_b, p, 2, 'each', null); perform _add(bom_t, p, 3, 'each', null); perform _add(bom_e, p, 2, 'each', null); perform _add(bom_h, p, 2, 'each', null);
  p := _ensure_p('Throw pillow set', 'RV-SL-009', cat_sleep, 'set'); perform _add(bom_o, p, 1, 'set', null); perform _add(bom_b, p, 1, 'set', null); perform _add(bom_t, p, 1, 'set', null); perform _add(bom_e, p, 1, 'set', null); perform _add(bom_h, p, 1, 'set', null);

  -- ───────────────────────────────────────────────────────────
  -- CATEGORY 10: FLOORING & FINISH (all 5)
  -- ───────────────────────────────────────────────────────────
  p := _ensure_p('Luxury vinyl plank flooring', 'RV-FL-001', cat_floor, 'm2'); perform _add(bom_o, p, 11, 'm2', null); perform _add(bom_b, p, 16, 'm2', null); perform _add(bom_t, p, 20, 'm2', null); perform _add(bom_e, p, 18, 'm2', null); perform _add(bom_h, p, 22, 'm2', null);
  p := _ensure_p('Flooring underlayment', 'RV-FL-002', cat_floor, 'm2'); perform _add(bom_o, p, 11, 'm2', null); perform _add(bom_b, p, 16, 'm2', null); perform _add(bom_t, p, 20, 'm2', null); perform _add(bom_e, p, 18, 'm2', null); perform _add(bom_h, p, 22, 'm2', null);
  p := _ensure_p('Wall trim molding (per ft)', 'RV-FL-003', cat_floor, 'ft'); perform _add(bom_o, p, 80, 'ft', null); perform _add(bom_b, p, 110, 'ft', null); perform _add(bom_t, p, 130, 'ft', null); perform _add(bom_e, p, 120, 'ft', null); perform _add(bom_h, p, 130, 'ft', null);
  p := _ensure_p('Crown trim (per ft)', 'RV-FL-004', cat_floor, 'ft'); perform _add(bom_o, p, 40, 'ft', null); perform _add(bom_b, p, 55, 'ft', null); perform _add(bom_t, p, 65, 'ft', null); perform _add(bom_e, p, 60, 'ft', null); perform _add(bom_h, p, 65, 'ft', null);
  p := _ensure_p('Ceiling panel', 'RV-FL-005', cat_floor, 'each'); perform _add(bom_o, p, 4, 'each', null); perform _add(bom_b, p, 6, 'each', null); perform _add(bom_t, p, 7, 'each', null); perform _add(bom_e, p, 6, 'each', null); perform _add(bom_h, p, 7, 'each', null);
  p := _ensure_p('Threshold strip', 'RV-FL-006', cat_floor, 'each'); perform _add(bom_o, p, 2, 'each', null); perform _add(bom_b, p, 2, 'each', null); perform _add(bom_t, p, 2, 'each', null); perform _add(bom_e, p, 2, 'each', null); perform _add(bom_h, p, 2, 'each', null);

  -- ───────────────────────────────────────────────────────────
  -- CATEGORY 11: EXTERIOR ACCESSORIES (all 5)
  -- ───────────────────────────────────────────────────────────
  p := _ensure_p('A2 electric legless awning 12 ft', 'RV-EX-001', cat_ext, 'each'); perform _add(bom_o, p, 1, 'each', null);
  p := _ensure_p('A2 electric legless awning 14 ft', 'RV-EX-002', cat_ext, 'each'); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null);
  p := _ensure_p('A2 electric legless awning 15 ft', 'RV-EX-003', cat_ext, 'each'); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Aluminum roof rack rail', 'RV-EX-004', cat_ext, 'each'); perform _add(bom_o, p, 2, 'each', null); perform _add(bom_b, p, 2, 'each', null); perform _add(bom_t, p, 2, 'each', null); perform _add(bom_e, p, 2, 'each', null); perform _add(bom_h, p, 2, 'each', null);
  p := _ensure_p('Roof rack crossbar', 'RV-EX-005', cat_ext, 'each'); perform _add(bom_o, p, 3, 'each', null); perform _add(bom_b, p, 4, 'each', null); perform _add(bom_t, p, 5, 'each', null); perform _add(bom_e, p, 4, 'each', null); perform _add(bom_h, p, 5, 'each', null);
  p := _ensure_p('Solar mounting bracket set', 'RV-EX-006', cat_ext, 'set'); perform _add(bom_o, p, 1, 'set', null); perform _add(bom_b, p, 1, 'set', null); perform _add(bom_t, p, 1, 'set', null); perform _add(bom_e, p, 1, 'set', null); perform _add(bom_h, p, 1, 'set', null);
  p := _ensure_p('Rear deployable ladder', 'RV-EX-007', cat_ext, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('External shower spigot', 'RV-EX-008', cat_ext, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('External hose reel', 'RV-EX-009', cat_ext, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Front storage box (tongue)', 'RV-EX-010', cat_ext, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null);
  p := _ensure_p('Rear storage box with Molle panel', 'RV-EX-011', cat_ext, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Mud flap', 'RV-EX-012', cat_ext, 'each'); perform _add(bom_o, p, 2, 'each', null); perform _add(bom_b, p, 2, 'each', null); perform _add(bom_t, p, 2, 'each', null); perform _add(bom_e, p, 2, 'each', null); perform _add(bom_h, p, 2, 'each', null);

  -- ───────────────────────────────────────────────────────────
  -- CATEGORY 12: CONNECTIVITY & ELECTRONICS (all 5)
  -- ───────────────────────────────────────────────────────────
  p := _ensure_p('Pepwave Max BR1 Pro 5G router', 'RV-CN-001', cat_conn, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('5G antenna kit', 'RV-CN-002', cat_conn, 'kit'); perform _add(bom_o, p, 1, 'kit', null); perform _add(bom_b, p, 1, 'kit', null); perform _add(bom_t, p, 1, 'kit', null); perform _add(bom_e, p, 1, 'kit', null); perform _add(bom_h, p, 1, 'kit', null);
  p := _ensure_p('Starlink dish with mount', 'RV-CN-003', cat_conn, 'kit'); perform _add(bom_o, p, 1, 'kit', null); perform _add(bom_b, p, 1, 'kit', null); perform _add(bom_t, p, 1, 'kit', null); perform _add(bom_e, p, 1, 'kit', null); perform _add(bom_h, p, 1, 'kit', null);
  p := _ensure_p('Indoor WiFi access point', 'RV-CN-004', cat_conn, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('4-camera security system with DVR', 'RV-CN-005', cat_conn, 'kit'); perform _add(bom_o, p, 1, 'kit', null); perform _add(bom_b, p, 1, 'kit', null); perform _add(bom_t, p, 1, 'kit', null); perform _add(bom_e, p, 1, 'kit', null); perform _add(bom_h, p, 1, 'kit', null);
  p := _ensure_p('Backup camera + display', 'RV-CN-006', cat_conn, 'kit'); perform _add(bom_o, p, 1, 'kit', null); perform _add(bom_b, p, 1, 'kit', null); perform _add(bom_t, p, 1, 'kit', null); perform _add(bom_e, p, 1, 'kit', null); perform _add(bom_h, p, 1, 'kit', null);
  p := _ensure_p('TV wall mount (articulating)', 'RV-CN-007', cat_conn, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Soundbar / stereo system', 'RV-CN-008', cat_conn, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Cellular signal booster', 'RV-CN-009', cat_conn, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Touchscreen smart-hub control panel', 'RV-CN-010', cat_conn, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);

  -- ───────────────────────────────────────────────────────────
  -- CATEGORY 13: SAFETY & DETECTION (all 5)
  -- ───────────────────────────────────────────────────────────
  p := _ensure_p('Smoke detector', 'RV-SF-001', cat_safe, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 2, 'each', null); perform _add(bom_e, p, 2, 'each', null); perform _add(bom_h, p, 2, 'each', null);
  p := _ensure_p('CO detector', 'RV-SF-002', cat_safe, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('Fire extinguisher 5 lb ABC', 'RV-SF-003', cat_safe, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 2, 'each', null); perform _add(bom_e, p, 2, 'each', null); perform _add(bom_h, p, 2, 'each', null);
  p := _ensure_p('First aid kit (RV-grade)', 'RV-SF-004', cat_safe, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);
  p := _ensure_p('TPMS 4-tire system', 'RV-SF-005', cat_safe, 'kit'); perform _add(bom_o, p, 1, 'kit', null); perform _add(bom_b, p, 1, 'kit', null); perform _add(bom_t, p, 1, 'kit', null);
  p := _ensure_p('Emergency exit window decal', 'RV-SF-006', cat_safe, 'each'); perform _add(bom_o, p, 1, 'each', null); perform _add(bom_b, p, 1, 'each', null); perform _add(bom_t, p, 1, 'each', null); perform _add(bom_e, p, 1, 'each', null); perform _add(bom_h, p, 1, 'each', null);

  -- ───────────────────────────────────────────────────────────
  -- CATEGORY 14: HARDWARE & FASTENERS (all 5)
  -- ───────────────────────────────────────────────────────────
  p := _ensure_p('Stainless bolt assortment M8/M10', 'RV-HW-001', cat_hw, 'kit'); perform _add(bom_o, p, 1, 'kit', null); perform _add(bom_b, p, 1, 'kit', null); perform _add(bom_t, p, 1, 'kit', null); perform _add(bom_e, p, 1, 'kit', null); perform _add(bom_h, p, 1, 'kit', null);
  p := _ensure_p('Stainless nut + washer kit', 'RV-HW-002', cat_hw, 'kit'); perform _add(bom_o, p, 1, 'kit', null); perform _add(bom_b, p, 1, 'kit', null); perform _add(bom_t, p, 1, 'kit', null); perform _add(bom_e, p, 1, 'kit', null); perform _add(bom_h, p, 1, 'kit', null);
  p := _ensure_p('Self-tapping screw assortment', 'RV-HW-003', cat_hw, 'kit'); perform _add(bom_o, p, 1, 'kit', null); perform _add(bom_b, p, 1, 'kit', null); perform _add(bom_t, p, 1, 'kit', null); perform _add(bom_e, p, 1, 'kit', null); perform _add(bom_h, p, 1, 'kit', null);
  p := _ensure_p('Mounting bracket assortment', 'RV-HW-004', cat_hw, 'kit'); perform _add(bom_o, p, 1, 'kit', null); perform _add(bom_b, p, 1, 'kit', null); perform _add(bom_t, p, 1, 'kit', null); perform _add(bom_e, p, 1, 'kit', null); perform _add(bom_h, p, 1, 'kit', null);
  p := _ensure_p('Sikaflex adhesive sealant 300ml', 'RV-HW-005', cat_hw, 'tube'); perform _add(bom_o, p, 6, 'tube', null); perform _add(bom_b, p, 8, 'tube', null); perform _add(bom_t, p, 10, 'tube', null); perform _add(bom_e, p, 8, 'tube', null); perform _add(bom_h, p, 10, 'tube', null);
  p := _ensure_p('Butyl tape (per roll)', 'RV-HW-006', cat_hw, 'roll'); perform _add(bom_o, p, 4, 'roll', null); perform _add(bom_b, p, 6, 'roll', null); perform _add(bom_t, p, 8, 'roll', null); perform _add(bom_e, p, 6, 'roll', null); perform _add(bom_h, p, 8, 'roll', null);
  p := _ensure_p('Wire management kit (zip ties + conduit)', 'RV-HW-007', cat_hw, 'kit'); perform _add(bom_o, p, 1, 'kit', null); perform _add(bom_b, p, 1, 'kit', null); perform _add(bom_t, p, 1, 'kit', null); perform _add(bom_e, p, 1, 'kit', null); perform _add(bom_h, p, 1, 'kit', null);
  p := _ensure_p('Threadlocker (Loctite blue)', 'RV-HW-008', cat_hw, 'tube'); perform _add(bom_o, p, 1, 'tube', null); perform _add(bom_b, p, 1, 'tube', null); perform _add(bom_t, p, 1, 'tube', null); perform _add(bom_e, p, 1, 'tube', null); perform _add(bom_h, p, 1, 'tube', null);
end $$;

-- ── 3. Drop helpers ───────────────────────────────────────────
drop function if exists _ensure_p(text, text, uuid, text);
drop function if exists _add(uuid, uuid, numeric, text, text);

commit;
