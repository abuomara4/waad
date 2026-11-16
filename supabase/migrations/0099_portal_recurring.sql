-- Waad ERP — 0099 customer portal and recurring invoices
-- * Portal: a private link per customer (a long random token) opens, without signing in, that customer's posted invoices
--   with their lines, what was paid and what remains, ready to print. Sales staff create or revoke the link.
-- * Recurring invoices: a template (customer, lines, every N months, next date); when due, a sales user issues it with
--   one click and the next date moves on. Issuing goes through the normal invoice posting (stock, VAT, journal, ZATCA).

create table if not exists public.portal_links (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  party_id uuid not null references public.parties(id) on delete cascade,
  token text not null unique default (replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);
create index if not exists portal_links_party on public.portal_links(company_id, party_id);
alter table public.portal_links enable row level security;
revoke all on public.portal_links from anon, authenticated;
grant select on public.portal_links to authenticated;
drop policy if exists portal_read on public.portal_links;
create policy portal_read on public.portal_links for select using (public.fin_can(company_id, 'sales'));

-- the customer's live link (created on first use)
create or replace function public.portal_link_get(p_party uuid) returns text
language plpgsql security definer set search_path = public as $$
declare p public.parties; t text;
begin
  select * into p from public.parties where id = p_party;
  if not found or p.kind <> 'customer' then raise exception 'العميل غير موجود'; end if;
  perform public.require_fin(p.company_id, 'sales');
  select token into t from public.portal_links where party_id = p_party and revoked_at is null order by created_at desc limit 1;
  if t is null then insert into public.portal_links(company_id, party_id) values (p.company_id, p_party) returning token into t; end if;
  return t;
end $$;
-- stop the current link (a new one can be made afterwards)
create or replace function public.portal_link_revoke(p_party uuid) returns void
language plpgsql security definer set search_path = public as $$
declare p public.parties;
begin
  select * into p from public.parties where id = p_party;
  if not found then raise exception 'العميل غير موجود'; end if;
  perform public.require_fin(p.company_id, 'sales');
  update public.portal_links set revoked_at = now() where party_id = p_party and revoked_at is null;
end $$;

-- what the link shows (no sign-in): the company's letterhead data, the customer's name, its invoices
create or replace function public.portal_view(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l public.portal_links; c public.companies; p public.parties;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return null; end if;
  select * into l from public.portal_links where token = p_token and revoked_at is null;
  if not found then return null; end if;
  select * into c from public.companies where id = l.company_id;
  select * into p from public.parties where id = l.party_id;
  return jsonb_build_object(
    'company', jsonb_build_object('name', c.name, 'name_en', c.name_en, 'vat_no', c.vat_no, 'cr_no', c.cr_no, 'address', c.address, 'logo', c.logo),
    'party', jsonb_build_object('name', p.name, 'vat_no', p.vat_no),
    'invoices', coalesce((select jsonb_agg(x order by (x->>'date') desc, x->>'no' desc) from (
      select jsonb_build_object('id', i.id, 'no', i.no, 'date', i.date, 'due_date', i.due_date, 'subtotal', i.subtotal, 'vat', i.vat, 'total', i.total,
        'paid', coalesce((select sum(amount) from public.payments where invoice_id = i.id), 0),
        'credit', coalesce((select sum(total) from public.credit_notes cn where cn.doc_id = i.id and cn.kind = 'sales'), 0),
        'lines', coalesce((select jsonb_agg(jsonb_build_object('item', it.name, 'qty', li.qty, 'price', li.unit_price, 'vat_rate', li.vat_rate, 'amount', li.amount, 'vat', li.vat) order by li.id)
                           from public.sales_invoice_lines li join public.items it on it.id = li.item_id where li.invoice_id = i.id), '[]')) x
        from public.sales_invoices i
       where i.company_id = c.id and i.party_id = p.id and i.status = 'posted' and not coalesce(i.is_opening, false)
       order by i.date desc limit 60) q), '[]'));
end $$;
revoke all on function public.portal_link_get(uuid), public.portal_link_revoke(uuid), public.portal_view(text) from public;
grant execute on function public.portal_link_get(uuid), public.portal_link_revoke(uuid) to authenticated;
grant execute on function public.portal_view(text) to anon, authenticated;

-- ---------- recurring invoices ----------
create table if not exists public.recurring_invoices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  party_id uuid not null references public.parties(id) on delete cascade,
  title text not null check (length(trim(title)) between 2 and 120),
  lines jsonb not null check (jsonb_typeof(lines) = 'array' and jsonb_array_length(lines) between 1 and 50),
  every_months int not null default 1 check (every_months between 1 and 12),
  next_date date not null,
  end_date date,
  active boolean not null default true,
  last_invoice_id uuid references public.sales_invoices(id) on delete set null,
  issued_count int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists recurring_due on public.recurring_invoices(company_id, active, next_date);
alter table public.recurring_invoices enable row level security;
revoke all on public.recurring_invoices from anon;
grant select, insert, update, delete on public.recurring_invoices to authenticated;
drop policy if exists recurring_all on public.recurring_invoices;
create policy recurring_all on public.recurring_invoices for all using (public.fin_can(company_id, 'sales')) with check (public.fin_can(company_id, 'sales')
  and exists(select 1 from public.parties p where p.id = party_id and p.company_id = recurring_invoices.company_id and p.kind = 'customer'));

-- issue one due recurring invoice (dated its due date, or today if later) and move to the next period
create or replace function public.recurring_issue(p_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare r public.recurring_invoices; inv uuid; d date;
begin
  select * into r from public.recurring_invoices where id = p_id for update;
  if not found then raise exception 'الفاتورة المتكررة غير موجودة'; end if;
  perform public.require_fin(r.company_id, 'sales');
  if not r.active then raise exception 'الفاتورة المتكررة موقوفة'; end if;
  if r.next_date > public.riyadh_today() then raise exception 'لم يحن موعدها بعد'; end if;
  d := public.riyadh_today();
  inv := public.post_sales_invoice_sn(r.company_id, jsonb_build_object('party', r.party_id, 'date', d, 'note', r.title, 'lines', r.lines));
  update public.recurring_invoices set last_invoice_id = inv, issued_count = issued_count + 1,
    next_date = (next_date + make_interval(months => every_months))::date,
    active = case when end_date is not null and (next_date + make_interval(months => every_months))::date > end_date then false else true end
   where id = p_id;
  return inv;
end $$;
revoke all on function public.recurring_issue(uuid) from public, anon;
grant execute on function public.recurring_issue(uuid) to authenticated;
