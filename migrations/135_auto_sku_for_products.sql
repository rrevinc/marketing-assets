-- ============================================================
-- 135 — Auto-assign SKUs to products that lack them.
--
-- Audit at the time of writing:
--   347 active products total
--   215 already have SKUs (62%)
--   132 don't — but only 7 of those are actually referenced
--   in any bom_lines. The rest are stale catalog items.
--
-- This migration:
--
--   1. Adds a BEFORE-INSERT trigger that auto-generates a SKU
--      ('RREV-AUTO-NNNNN') for any new product where the caller
--      didn't supply one. Partners creating components inline
--      via /api/products will now always get a clean SKU.
--
--   2. Backfills SKUs for every active, BOM-referenced product
--      that's currently missing one, using 'RREV-LEGACY-NNNNN'.
--      Stale unused products are left alone — they can be
--      cleaned up separately.
--
-- Sequence starts at 10000 to leave room for the curated
-- RV-XX-NNN SKUs added in migration 134.
-- ============================================================

begin;

create sequence if not exists public.product_auto_sku_seq start with 10000 minvalue 10000;

-- ── 1. Trigger: auto-fill SKU on INSERT when missing ─────────
create or replace function public.set_product_sku_if_missing()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.sku is null or trim(new.sku) = '' then
    new.sku := 'RREV-AUTO-' || lpad(nextval('public.product_auto_sku_seq')::text, 5, '0');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_product_sku on public.products;
create trigger trg_set_product_sku
  before insert on public.products
  for each row execute procedure public.set_product_sku_if_missing();

-- ── 2. Backfill: BOM-referenced products without SKU ─────────
-- We only touch products that are (a) active AND (b) actually
-- used in at least one bom_line. Stale orphans are left alone
-- — they're better dropped via a catalog cleanup pass.
update public.products
set sku = 'RREV-LEGACY-' || lpad(nextval('public.product_auto_sku_seq')::text, 5, '0')
where (sku is null or trim(sku) = '')
  and is_active = true
  and id in (select distinct product_id from public.bom_lines);

commit;
