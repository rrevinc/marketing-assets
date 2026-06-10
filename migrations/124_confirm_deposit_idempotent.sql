-- ============================================================
-- 124 — confirm_build_deposit: reuse existing order if one
--        already exists from the quote→order conversion.
--
-- BUG:
--   The previous version of public.confirm_build_deposit (in
--   migration 015) ALWAYS inserted a new row into public.orders,
--   regardless of whether the build already had an order_id or
--   whether the linked quotation already had a sale_order_id.
--
--   Path that triggered the duplicate:
--     1. Staff hits "Confirm Order" on a quotation → creates an
--        order from quotation_lines (e.g. RRV-00024) and sets
--        quotation.sale_order_id.
--     2. Staff later hits "Confirm Deposit" on the build → this
--        RPC fires and creates ANOTHER order (RRV-00025), then
--        overwrites quotation.sale_order_id to point at the new
--        one — leaving the first order orphaned.
--
-- FIX:
--   Resolve any pre-existing order linkage BEFORE inserting:
--     a. build_configurations.order_id
--     b. quotations.sale_order_id (via build.quotation_id)
--   If found, REUSE that order:
--     - update its deposit_amount, status, total
--     - skip the orders INSERT
--     - skip order_options INSERT (lines already came from quote)
--     - skip deposit-invoice INSERT if one already exists for it
--   If no existing order is found, behave as before.
--
--   In all cases the rest of the flow (MO, build status, timeline,
--   quotation backlink) runs the same way.
-- ============================================================

create or replace function public.confirm_build_deposit(build_id uuid, confirmed_by uuid default null)
returns uuid as $$
declare
  build_rec public.build_configurations%rowtype;
  resolved_order_id uuid;
  reused boolean := false;
  new_mo_id uuid;
  product_rec record;
  existing_invoice uuid;
  existing_mo uuid;
begin
  -- Load the build
  select * into build_rec from public.build_configurations where id = build_id;
  if not found then
    raise exception 'Build configuration not found';
  end if;
  if build_rec.status not in ('submitted', 'quoted') then
    raise exception 'Build must be in submitted or quoted status (got %)', build_rec.status;
  end if;

  -- ── 1. Resolve any pre-existing order ────────────────────────
  -- Direct link on the build first.
  resolved_order_id := build_rec.order_id;

  -- Else look at the linked quotation's sale_order_id.
  if resolved_order_id is null and build_rec.quotation_id is not null then
    select sale_order_id into resolved_order_id
    from public.quotations
    where id = build_rec.quotation_id;
  end if;

  -- Verify the resolved order actually exists (defensive — the link
  -- could be stale if an order was hard-deleted).
  if resolved_order_id is not null then
    perform 1 from public.orders where id = resolved_order_id;
    if not found then
      resolved_order_id := null;
    end if;
  end if;

  -- ── 2. Either reuse or create ────────────────────────────────
  if resolved_order_id is not null then
    reused := true;

    -- Bring the existing order up to date with the build's pricing
    -- and confirm it. Don't downgrade a more-advanced status.
    update public.orders set
      status = case
        when status in ('draft', 'pending') then 'confirmed'
        else status
      end,
      model = coalesce(model, build_rec.model_name),
      model_variant = coalesce(model_variant, build_rec.model_variant),
      base_price = coalesce(base_price, build_rec.base_price),
      total_price = coalesce(total_price, build_rec.total_price),
      deposit_amount = coalesce(nullif(deposit_amount, 0), build_rec.deposit_amount),
      updated_at = now()
    where id = resolved_order_id;
  else
    -- No existing order — original behavior.
    insert into public.orders (
      customer_id, status, model, model_variant,
      base_price, total_price, deposit_amount,
      notes, order_number
    )
    values (
      build_rec.customer_id,
      'confirmed',
      build_rec.model_name,
      build_rec.model_variant,
      build_rec.base_price,
      build_rec.total_price,
      build_rec.deposit_amount,
      'Created from build configuration ' || build_rec.config_number,
      ''
    )
    returning id into resolved_order_id;

    -- Order timeline entry
    insert into public.order_timeline (order_id, status, note, created_by)
    values (resolved_order_id, 'confirmed',
            'Order created from build configuration ' || build_rec.config_number,
            confirmed_by);

    -- Hydrate order_options from selected_options JSON (only when we
    -- created the order — reused orders already have lines/options
    -- from the quote conversion).
    insert into public.order_options (order_id, category, option_name, price)
    select resolved_order_id, opt->>'category', opt->>'option', (opt->>'price')::numeric
    from jsonb_array_elements(build_rec.selected_options) as opt
    where opt->>'option' is not null and opt->>'option' != '';
  end if;

  -- ── 3. Manufacturing order (idempotent — skip if one exists) ──
  select id into existing_mo
  from public.manufacturing_orders
  where sale_order_id = resolved_order_id
  limit 1;

  if existing_mo is null then
    select id into product_rec from public.products
    where name ilike '%' || build_rec.model_name || '%' and is_active = true
    limit 1;

    if product_rec.id is not null then
      insert into public.manufacturing_orders (
        product_id, quantity, status, priority,
        sale_order_id, notes, mo_number, created_by
      )
      values (
        product_rec.id, 1, 'draft', 'normal',
        resolved_order_id,
        'Auto-created from build configuration ' || build_rec.config_number,
        '',
        confirmed_by
      )
      returning id into new_mo_id;
    end if;
  else
    new_mo_id := existing_mo;
  end if;

  -- ── 4. Quotation backlink (always set so reused order survives) ──
  if build_rec.quotation_id is not null then
    update public.quotations
    set status = 'confirmed', sale_order_id = resolved_order_id
    where id = build_rec.quotation_id;
  end if;

  -- ── 5. Deposit invoice (only if one doesn't already exist) ────
  select id into existing_invoice
  from public.invoices
  where order_id = resolved_order_id
    and (description ilike 'Deposit%' or invoice_number ilike 'DEP-%')
  limit 1;

  if existing_invoice is null then
    insert into public.invoices (
      order_id, invoice_number, description,
      amount, status, due_date
    )
    values (
      resolved_order_id,
      'DEP-' || substring(build_rec.config_number from 5),
      'Deposit for ' || build_rec.model_name || ' build ' || build_rec.config_number,
      build_rec.deposit_amount,
      'pending',
      (now() + interval '7 days')::date
    );
  end if;

  -- ── 6. Build status + links + timeline ────────────────────────
  update public.build_configurations set
    status = 'deposit_paid',
    order_id = resolved_order_id,
    manufacturing_order_id = coalesce(new_mo_id, manufacturing_order_id),
    updated_at = now()
  where id = build_id;

  insert into public.build_timeline (build_id, status, note, created_by)
  values (
    build_id,
    'deposit_paid',
    case when reused
         then 'Deposit confirmed. Linked to existing sales order.'
         else 'Deposit confirmed. Sales order and manufacturing order created.'
    end,
    confirmed_by
  );

  return resolved_order_id;
end;
$$ language plpgsql security definer;

comment on function public.confirm_build_deposit(uuid, uuid) is
  'Idempotent: reuses an existing order from build.order_id or quotation.sale_order_id instead of creating a duplicate. See migration 124.';
