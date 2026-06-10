-- ============================================================
-- 129 — Seed master BOMs for the five RREV models.
--
-- After migration 128 added boms.assigned_manufacturer_id, we
-- need a master BOM per model so partners have something to
-- populate. Existing BOMs (Baja Edition V1 from migration 074
-- and the Titan Standard BOM) are reused — we only insert what
-- doesn't already exist.
--
-- Outland, EXP Series, HD Series get fresh empty BOMs.
-- Baja BOM is reassigned to Weihai Huigao manufacturer so the
-- newly-created partner managers can edit it.
--
-- Each block is idempotent: re-running this migration is a no-op.
-- ============================================================

begin;

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
  -- Weihai Huigao manufacturer (created earlier this session).
  select id into v_huigao
  from public.manufacturers
  where name ilike '%huigao%' and name ilike '%weihai%'
  limit 1;

  -- Match each model to its canonical "Non-Bunk" / primary product.
  -- Uses LIMIT 1 because some product names have duplicate rows.
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

  -- ── Outland Edition V1 ────────────────────────────────────────
  if v_product_outland is not null then
    select id into v_bom_id from public.boms
    where product_id = v_product_outland and name = 'Outland Edition V1';
    if v_bom_id is null then
      insert into public.boms (product_id, name, version, is_active, notes, assigned_manufacturer_id)
      values (v_product_outland, 'Outland Edition V1', 1, true,
              'Master BOM for the Outland Edition. Partner-editable.',
              v_huigao)
      returning id into v_bom_id;
    elsif v_huigao is not null then
      update public.boms set assigned_manufacturer_id = v_huigao
      where id = v_bom_id and assigned_manufacturer_id is distinct from v_huigao;
    end if;
  end if;

  -- ── Baja Edition V1 (already exists from migration 074) ───────
  if v_product_baja is not null then
    select id into v_bom_id from public.boms
    where product_id = v_product_baja and name = 'Baja Edition V1';
    if v_bom_id is null then
      insert into public.boms (product_id, name, version, is_active, notes, assigned_manufacturer_id)
      values (v_product_baja, 'Baja Edition V1', 1, true,
              'Master BOM for the Baja Edition.',
              v_huigao)
      returning id into v_bom_id;
    elsif v_huigao is not null then
      update public.boms set assigned_manufacturer_id = v_huigao
      where id = v_bom_id and assigned_manufacturer_id is distinct from v_huigao;
    end if;
  end if;

  -- ── Titan Standard BOM (already exists; just ensure assignment) ─
  if v_product_titan is not null then
    select id into v_bom_id from public.boms
    where product_id = v_product_titan
      and (name = 'Titan Standard BOM' or name = 'Titan Edition V1')
    order by version desc limit 1;
    if v_bom_id is null then
      insert into public.boms (product_id, name, version, is_active, notes, assigned_manufacturer_id)
      values (v_product_titan, 'Titan Edition V1', 1, true,
              'Master BOM for the Titan Edition. Partner-editable.',
              v_huigao)
      returning id into v_bom_id;
    elsif v_huigao is not null then
      update public.boms set assigned_manufacturer_id = v_huigao
      where id = v_bom_id and assigned_manufacturer_id is distinct from v_huigao;
    end if;
  end if;

  -- ── EXP Series V1 ─────────────────────────────────────────────
  if v_product_exp is not null then
    select id into v_bom_id from public.boms
    where product_id = v_product_exp and name = 'EXP Series V1';
    if v_bom_id is null then
      insert into public.boms (product_id, name, version, is_active, notes, assigned_manufacturer_id)
      values (v_product_exp, 'EXP Series V1', 1, true,
              'Master BOM for the EXP Series. Partner-editable.',
              v_huigao)
      returning id into v_bom_id;
    elsif v_huigao is not null then
      update public.boms set assigned_manufacturer_id = v_huigao
      where id = v_bom_id and assigned_manufacturer_id is distinct from v_huigao;
    end if;
  end if;

  -- ── HD Series V1 ──────────────────────────────────────────────
  if v_product_hd is not null then
    select id into v_bom_id from public.boms
    where product_id = v_product_hd and name = 'HD Series V1';
    if v_bom_id is null then
      insert into public.boms (product_id, name, version, is_active, notes, assigned_manufacturer_id)
      values (v_product_hd, 'HD Series V1', 1, true,
              'Master BOM for the HD Series. Partner-editable.',
              v_huigao)
      returning id into v_bom_id;
    elsif v_huigao is not null then
      update public.boms set assigned_manufacturer_id = v_huigao
      where id = v_bom_id and assigned_manufacturer_id is distinct from v_huigao;
    end if;
  end if;
end $$;

commit;
