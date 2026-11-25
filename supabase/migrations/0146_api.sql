-- Waad API v1 (read-only): another system (an e-commerce store, a BI tool, an accounting or HR system) reads the company's data
-- with an API key. The owner or an admin creates a key with scopes (hr, sales, purch, stock, finance) and an expiry; the key is
-- shown once and only its SHA-256 hash is kept; it can be revoked. Calls go to the public REST endpoint as an RPC
-- (POST /rest/v1/rpc/api_get with the public anon key) — no extra server. Each key may make 1,000 calls an hour; every call
-- updates its «last used». A key reads only its company, only its scopes, only modules the subscription has, and only while the
-- subscription is live. Employee data exposed is the work profile only (no salary, IBAN, ID or contact details).

create table if not exists public.api_keys (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null check (length(btrim(name)) between 2 and 80),
  prefix text not null,
  key_hash text not null unique,
  scopes text[] not null check (scopes <@ array['hr','sales','purch','stock','finance'] and cardinality(scopes) > 0),
  expires_at timestamptz,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  last_used_at timestamptz, uses bigint not null default 0, revoked_at timestamptz
);
create index if not exists api_keys_company on public.api_keys(company_id);
alter table public.api_keys enable row level security;
drop policy if exists api_keys_read on public.api_keys;
create policy api_keys_read on public.api_keys for select using (public.has_role(company_id, array['owner','admin']));
revoke all on public.api_keys from anon, authenticated;
grant select (id, company_id, name, prefix, scopes, expires_at, created_by, created_at, last_used_at, uses, revoked_at) on public.api_keys to authenticated;

create table if not exists public.api_usage (
  key_id uuid not null references public.api_keys(id) on delete cascade,
  hour timestamptz not null,
  n int not null default 0,
  primary key (key_id, hour)
);
alter table public.api_usage enable row level security;
revoke all on public.api_usage from anon, authenticated;

-- a new key: returned once, never stored in clear
create or replace function public.api_key_create(p_company uuid, p_name text, p_scopes text[], p_days int default 365) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k text := 'waad_' || replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''); id_ uuid;
begin
  if not (public.aal_ok() and public.has_role(p_company, array['owner','admin'])) then raise exception 'مفاتيح الربط لمالك المنشأة أو مديرها' using errcode = '42501'; end if;
  if p_scopes is null or cardinality(p_scopes) = 0 or not (p_scopes <@ array['hr','sales','purch','stock','finance']) then raise exception 'اختر صلاحية واحدة على الأقل'; end if;
  if p_days is not null and (p_days < 1 or p_days > 730) then raise exception 'مدة المفتاح بين يوم وسنتين'; end if;
  if (select count(*) from public.api_keys where company_id = p_company and revoked_at is null and (expires_at is null or expires_at > now())) >= 10 then
    raise exception 'الحد الأعلى 10 مفاتيح فعّالة'; end if;
  insert into public.api_keys(company_id, name, prefix, key_hash, scopes, expires_at)
  values (p_company, btrim(p_name), left(k, 12), encode(sha256(convert_to(k, 'UTF8')), 'hex'), (select array_agg(distinct s order by s) from unnest(p_scopes) s),
          case when p_days is null then null else now() + make_interval(days => p_days) end)
  returning id into id_;
  return jsonb_build_object('id', id_, 'key', k);
end $$;

create or replace function public.api_key_revoke(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c uuid;
begin
  select company_id into c from public.api_keys where id = p_id;
  if c is null or not (public.aal_ok() and public.has_role(c, array['owner','admin'])) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  update public.api_keys set revoked_at = coalesce(revoked_at, now()) where id = p_id;
end $$;

-- the read endpoint. p_resource: employees, departments, customers, suppliers, items, sales_invoices, purchase_bills, payments,
-- accounts, trial_balance. p_since: only rows created (or changed, where the table keeps it) after it; p_limit ≤ 500.
create or replace function public.api_get(p_key text, p_resource text, p_since timestamptz default null, p_limit int default 100, p_offset int default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k public.api_keys; c uuid; need text; md text; lim int := least(greatest(coalesce(p_limit, 100), 1), 500); off int := greatest(coalesce(p_offset, 0), 0);
  n int; rows jsonb; since timestamptz := coalesce(p_since, '-infinity');
begin
  select * into k from public.api_keys where key_hash = encode(sha256(convert_to(coalesce(p_key, ''), 'UTF8')), 'hex');
  if not found or k.revoked_at is not null or (k.expires_at is not null and k.expires_at <= now()) then raise exception 'مفتاح الربط غير صالح' using errcode = '28000'; end if;
  c := k.company_id;
  need := case p_resource when 'employees' then 'hr' when 'departments' then 'hr' when 'customers' then 'sales' when 'sales_invoices' then 'sales'
            when 'suppliers' then 'purch' when 'purchase_bills' then 'purch' when 'items' then 'stock' when 'payments' then 'finance'
            when 'accounts' then 'finance' when 'trial_balance' then 'finance' end;
  if need is null then raise exception 'المورد غير معروف: %', p_resource using errcode = '22023'; end if;
  if not need = any(k.scopes) then raise exception 'المفتاح لا يملك صلاحية «%»', need using errcode = '42501'; end if;
  md := case need when 'hr' then 'hr' when 'sales' then 'sales' when 'purch' then 'purch' when 'stock' then 'stock' else 'finance' end;
  if not public.module_on(c, md) or not exists(select 1 from public.company_subscriptions s where s.company_id = c and s.status in ('active','trial')) then
    raise exception 'الاشتراك أو القسم غير مفعّل' using errcode = '42501'; end if;
  insert into public.api_usage(key_id, hour, n) values (k.id, date_trunc('hour', now()), 1)
  on conflict (key_id, hour) do update set n = api_usage.n + 1 returning api_usage.n into n;
  if n > 1000 then raise exception 'تجاوزت 1000 طلب في الساعة' using errcode = '53400'; end if;
  update public.api_keys set last_used_at = now(), uses = uses + 1 where id = k.id;

  if p_resource = 'employees' then
    select coalesce(jsonb_agg(x), '[]') into rows from (select e.id, e.emp_no, e.full_name, e.job_title, e.department_id, (select d.name from public.departments d where d.id = e.department_id) department,
        e.hire_date, e.end_date, (select b.code from public.branches b where b.id = e.branch_id) branch, e.manager_id, e.created_at
      from public.employees e where e.company_id = c and e.created_at > since order by e.created_at, e.id limit lim offset off) x;
  elsif p_resource = 'departments' then
    select coalesce(jsonb_agg(x), '[]') into rows from (select d.id, d.name from public.departments d where d.company_id = c order by d.name, d.id limit lim offset off) x;
  elsif p_resource in ('customers','suppliers') then
    select coalesce(jsonb_agg(x), '[]') into rows from (select p.id, p.name, p.name_en, p.vat_no, p.cr_no, p.phone, p.email, p.city, p.country, p.created_at
      from public.parties p where p.company_id = c and p.kind = case p_resource when 'customers' then 'customer' else 'supplier' end and p.created_at > since order by p.created_at, p.id limit lim offset off) x;
  elsif p_resource = 'items' then
    select coalesce(jsonb_agg(x), '[]') into rows from (select i.id, i.code, i.name, i.name_en, i.type, i.unit, i.barcode, i.sale_price, i.vat_rate, i.active,
        case when i.type = 'stock' then (public.stock_state(i.id)).qty end on_hand, i.created_at
      from public.items i where i.company_id = c and i.created_at > since order by i.created_at, i.id limit lim offset off) x;
  elsif p_resource = 'sales_invoices' then
    select coalesce(jsonb_agg(x), '[]') into rows from (select s.id, s.no, s.date, s.due_date, s.party_id, s.doc_type, s.subtotal, s.vat, s.total, s.status, s.created_at,
        (select coalesce(jsonb_agg(jsonb_build_object('item_id', l.item_id, 'qty', l.qty, 'unit_price', l.unit_price, 'vat_rate', l.vat_rate) order by l.id), '[]') from public.sales_invoice_lines l where l.invoice_id = s.id) lines
      from public.sales_invoices s where s.company_id = c and s.created_at > since order by s.created_at, s.id limit lim offset off) x;
  elsif p_resource = 'purchase_bills' then
    select coalesce(jsonb_agg(x), '[]') into rows from (select b.id, b.no, b.supplier_ref, b.date, b.due_date, b.party_id, b.subtotal, b.vat, b.total, b.status, b.created_at
      from public.purchase_bills b where b.company_id = c and b.created_at > since order by b.created_at, b.id limit lim offset off) x;
  elsif p_resource = 'payments' then
    select coalesce(jsonb_agg(x), '[]') into rows from (select y.id, y.no, y.direction, y.party_id, y.invoice_id, y.bill_id, y.date, y.amount, y.account_code, y.created_at
      from public.payments y where y.company_id = c and y.created_at > since order by y.created_at, y.id limit lim offset off) x;
  elsif p_resource = 'accounts' then
    select coalesce(jsonb_agg(x), '[]') into rows from (select a.code, a.name, a.name_en, a.type, a.parent_code, a.is_header from public.accounts a where a.company_id = c order by a.code limit lim offset off) x;
  else   -- trial_balance at today
    select coalesce(jsonb_agg(x), '[]') into rows from (select l.account_code code, sum(l.debit) debit, sum(l.credit) credit, sum(l.debit - l.credit) balance
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id where l.company_id = c and e.date <= current_date
      group by l.account_code having sum(l.debit - l.credit) <> 0 order by l.account_code limit lim offset off) x;
  end if;
  return jsonb_build_object('resource', p_resource, 'count', jsonb_array_length(rows), 'limit', lim, 'offset', off,
    'next_offset', case when jsonb_array_length(rows) = lim then off + lim end, 'data', rows);
end $$;

revoke all on function public.api_key_create(uuid, text, text[], int), public.api_key_revoke(uuid), public.api_get(text, text, timestamptz, int, int) from public, anon;
grant execute on function public.api_key_create(uuid, text, text[], int), public.api_key_revoke(uuid) to authenticated;
grant execute on function public.api_get(text, text, timestamptz, int, int) to anon, authenticated;
notify pgrst, 'reload schema';
