-- ============================================================
-- 127 — Allow record_type='team_direct' on customer_communications
--
-- A "Direct to RREV Team" channel that's available to every user
-- (customer, partner, supplier) regardless of whether they have
-- any builds/orders/etc. Lets a fresh sign-up or a partner with
-- no active package just say hi.
--
-- record_id on a team_direct row is the user's own profile id —
-- the conversation is conceptually "between this person and the
-- RREV team", and the RREV staff inbox can route it to the
-- "Team Resilient" admin profile by convention.
-- ============================================================

begin;

alter table public.customer_communications
  drop constraint if exists customer_communications_record_type_check;

alter table public.customer_communications
  add constraint customer_communications_record_type_check
    check (record_type in (
      'order',
      'quotation',
      'service_request',
      'warranty_claim',
      'build_configuration',
      'lead',
      'team_direct'
    ));

comment on column public.customer_communications.record_type is
  'Source record this conversation is attached to. One of: order, quotation, '
  'service_request, warranty_claim, build_configuration, lead, team_direct. '
  'team_direct is a fallback "DM the RREV team" channel for users with no '
  'other records yet — see migration 127.';

commit;
