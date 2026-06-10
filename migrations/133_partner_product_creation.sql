-- ============================================================
-- 133 — Let partner Managers create products inline.
--
-- Partners building BOMs often source components that aren't
-- in the RREV master catalog yet (Chinese local suppliers, new
-- sub-assemblies, etc). This migration:
--
--   1. Adds attribution columns to products so RREV can see
--      which products came from a partner and review them.
--   2. RLS: manufacturer members can SELECT active products
--      (required so the BOM editor's typeahead actually returns
--      results for non-employee users).
--   3. RLS: Manager role at any manufacturer can INSERT new
--      products, with their manufacturer_id stamped on the row
--      so audit / review is trivial.
-- ============================================================

begin;

alter table public.products
  add column if not exists created_by_user uuid
    references public.profiles(id) on delete set null;
alter table public.products
  add column if not exists created_by_manufacturer_id uuid
    references public.manufacturers(id) on delete set null;

create index if not exists idx_products_created_by_partner
  on public.products(created_by_manufacturer_id)
  where created_by_manufacturer_id is not null;

comment on column public.products.created_by_user is
  'When set, identifies the user who created this product inline via the BOM editor. NULL for products created in /erp/manufacturing or via seed migrations.';
comment on column public.products.created_by_manufacturer_id is
  'When set, identifies the manufacturer whose Manager-role member created this product inline. Lets RREV review and curate the partner-added catalog.';

-- ── Partner SELECT on products ────────────────────────────────
-- Any active member of any manufacturer can read active products
-- (needed so the typeahead in PartnerBomLineEditor works).
drop policy if exists "Manufacturer members can view active products" on public.products;
create policy "Manufacturer members can view active products"
  on public.products for select
  using (
    is_active = true
    and exists (
      select 1 from public.manufacturer_memberships mm
      where mm.user_id = auth.uid()
        and mm.is_active = true
    )
  );

-- ── Partner INSERT on products ────────────────────────────────
-- Manager role at any manufacturer can insert; the new row MUST
-- carry that manufacturer's id on created_by_manufacturer_id so
-- partner additions are clearly tagged for review.
drop policy if exists "Manufacturer managers can insert products" on public.products;
create policy "Manufacturer managers can insert products"
  on public.products for insert
  with check (
    created_by_manufacturer_id is not null
    and public.has_manufacturer_role(
      created_by_manufacturer_id,
      array['manager']
    )
  );

commit;
