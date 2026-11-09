-- Waad ERP — 0049: customer/supplier statement, item master fields + import, candidate CV,
-- terms & privacy acceptance, two-step verification (MFA) enforced in the database, client error log.

-- ================= customer / supplier statement =================
-- Customer: invoices are debits, receipts and credit notes credits; balance = what the customer owes us.
-- Supplier: bills are credits, payments and debit notes debits; balance = what we owe the supplier.
create or replace function public.party_statement(p_party uuid, p_from date, p_to date)
returns table(d date, kind text, no text, ref text, debit numeric, credit numeric, balance numeric, doc_id uuid)
language plpgsql stable security definer set search_path = public as $$
declare p public.parties; cust boolean; ob numeric;
begin
  select * into p from public.parties where id = p_party;
  if not found then raise exception 'الطرف غير موجود'; end if;
  perform public.require_fin(p.company_id, case p.kind when 'customer' then 'sales' else 'purch' end);
  if p_from is null or p_to is null or p_to < p_from then raise exception 'حدد الفترة'; end if;
  cust := p.kind = 'customer';
  return query
  with mv as (
    select i.date dd, case when i.is_opening then 'opening' else 'invoice' end k, i.no n, coalesce(i.note, '') r, i.total dr, 0::numeric cr, i.id x, i.created_at t
      from public.sales_invoices i where cust and i.party_id = p.id and i.status <> 'void'
    union all
    select b.date, case when b.is_opening then 'opening' else 'bill' end, b.no, coalesce(b.supplier_ref, ''), 0, b.total, b.id, b.created_at
      from public.purchase_bills b where not cust and b.party_id = p.id and b.status <> 'void'
    union all
    select y.date, case when y.direction = 'in' then 'receipt' else 'payment' end, y.no, coalesce(y.note, ''),
           case when y.direction = 'out' then y.amount else 0 end, case when y.direction = 'in' then y.amount else 0 end, y.id, y.created_at
      from public.payments y where y.party_id = p.id
    union all
    select c.date, case when c.kind = 'sales' then 'credit_note' else 'debit_note' end, c.no, c.reason,
           case when c.kind = 'purchase' then c.total else 0 end, case when c.kind = 'sales' then c.total else 0 end, c.id, c.created_at
      from public.credit_notes c where c.party_id = p.id),
  sgn as (select *, case when cust then dr - cr else cr - dr end s from mv)
  select p_from, 'opening_balance'::text, null::text, null::text,
         case when cust then greatest(o.v, 0) else greatest(-o.v, 0) end, case when cust then greatest(-o.v, 0) else greatest(o.v, 0) end, o.v, null::uuid
    from (select coalesce(sum(s), 0) v from sgn where dd < p_from) o
  union all
  select * from (
    select x.dd, x.k, x.n, x.r, x.dr, x.cr,
           (select coalesce(sum(s), 0) from sgn where dd < p_from) + sum(x.s) over (order by x.dd, x.t, x.n rows unbounded preceding), x.x
      from sgn x where x.dd between p_from and p_to order by x.dd, x.t, x.n) z;
end $$;

-- ================= items: barcode, category, purchase price, VAT rate, active =================
alter table public.items
  add column if not exists barcode text,
  add column if not exists category text,
  add column if not exists purchase_price numeric(12,2),
  add column if not exists vat_rate numeric(5,2) not null default 15,
  add column if not exists active boolean not null default true;
alter table public.items drop constraint if exists items_vat_rate_check;
alter table public.items add constraint items_vat_rate_check check (vat_rate in (0, 15));
alter table public.items drop constraint if exists items_purchase_price_check;
alter table public.items add constraint items_purchase_price_check check (purchase_price is null or purchase_price >= 0);
create unique index if not exists items_barcode_uq on public.items(company_id, barcode) where barcode is not null;

create or replace function public.item_profile_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  new.code := trim(new.code);
  new.barcode := nullif(replace(trim(coalesce(new.barcode, '')), ' ', ''), '');
  new.category := nullif(trim(coalesce(new.category, '')), '');
  if new.barcode !~ '^[0-9A-Za-z-]{4,32}$' then raise exception 'الباركود من 4 إلى 32 حرفاً أو رقماً'; end if;
  return new;
end $$;
drop trigger if exists items_profile_guard on public.items;
create trigger items_profile_guard before insert or update on public.items for each row execute function public.item_profile_guard();

create or replace function public.item_active_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.item_id is not null and exists(select 1 from public.items where id = new.item_id and not active) then
    raise exception 'الصنف موقوف — فعّله من بطاقته أولاً';
  end if;
  return new;
end $$;
drop trigger if exists sales_invoice_lines_item_active on public.sales_invoice_lines;
create trigger sales_invoice_lines_item_active before insert on public.sales_invoice_lines for each row execute function public.item_active_guard();
drop trigger if exists purchase_bill_lines_item_active on public.purchase_bill_lines;
create trigger purchase_bill_lines_item_active before insert on public.purchase_bill_lines for each row execute function public.item_active_guard();
drop trigger if exists sales_order_lines_item_active on public.sales_order_lines;
create trigger sales_order_lines_item_active before insert on public.sales_order_lines for each row execute function public.item_active_guard();
drop trigger if exists purchase_order_lines_item_active on public.purchase_order_lines;
create trigger purchase_order_lines_item_active before insert on public.purchase_order_lines for each row execute function public.item_active_guard();

-- import items from Excel: new codes are added, existing codes updated from the filled cells only
create or replace function public.import_items(p_company uuid, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; ln text; cd text; it public.items; added int := 0; updated int := 0; seen text[] := '{}'; t text; v text;
begin
  perform public.require_fin(p_company, 'items');
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'الملف لا يحتوي أصنافاً'; end if;
  if jsonb_array_length(p_rows) > 3000 then raise exception 'الحد الأقصى 3000 سطر في الملف الواحد'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    ln := 'السطر ' || coalesce(r->>'_row', '?') || ': ';
    cd := trim(coalesce(r->>'code', ''));
    if cd = '' then raise exception '%رمز الصنف مطلوب', ln; end if;
    if cd = any(seen) then raise exception '%الرمز «%» مكرر في الملف', ln, cd; end if;
    seen := seen || cd;
    begin
      select * into it from public.items where company_id = p_company and code = cd;
      if not found then
        if length(trim(coalesce(r->>'name', ''))) < 2 then raise exception 'اسم الصنف مطلوب للصنف الجديد'; end if;
        t := case lower(trim(coalesce(r->>'type', ''))) when '' then 'stock' when 'stock' then 'stock' when 'مخزني' then 'stock'
             when 'service' then 'service' when 'خدمة' then 'service' else null end;
        if t is null then raise exception 'النوع: مخزني أو خدمة'; end if;
        insert into public.items(company_id, code, name, type) values (p_company, cd, trim(r->>'name'), t) returning * into it; added := added + 1;
      else updated := updated + 1; end if;
      update public.items set
        name = coalesce(nullif(trim(r->>'name'), ''), name),
        name_en = coalesce(nullif(trim(r->>'name_en'), ''), name_en),
        unit = coalesce(nullif(trim(r->>'unit'), ''), unit),
        barcode = coalesce(nullif(trim(r->>'barcode'), ''), barcode),
        category = coalesce(nullif(trim(r->>'category'), ''), category),
        sale_price = coalesce(nullif(trim(r->>'sale_price'), '')::numeric, sale_price),
        purchase_price = coalesce(nullif(trim(r->>'purchase_price'), '')::numeric, purchase_price),
        vat_rate = coalesce(nullif(replace(trim(r->>'vat_rate'), '%', ''), '')::numeric, vat_rate),
        reorder_level = coalesce(nullif(trim(r->>'reorder_level'), '')::numeric, reorder_level)
      where id = it.id;
    exception
      when unique_violation then raise exception '%الباركود مستخدم لصنف آخر', ln;
      when check_violation then raise exception '%تحقق من الأسعار (أرقام موجبة) ونسبة الضريبة (0 أو 15)', ln;
      when invalid_text_representation then raise exception '%الأسعار والكميات أرقام فقط', ln;
      when raise_exception then raise exception '%', ln || sqlerrm;
    end;
  end loop;
  return jsonb_build_object('added', added, 'updated', updated);
end $$;

-- ================= candidate CV / documents =================
create table if not exists public.candidate_files (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  candidate_id uuid not null references public.candidates(id) on delete cascade,
  file_name text not null check (length(file_name) between 1 and 200),
  mime text not null check (mime in ('application/pdf','image/jpeg','image/png','image/webp',
    'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document')),
  size int not null check (size between 1 and 3145728),
  data text not null,
  uploaded_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists candidate_files_cand on public.candidate_files(candidate_id);
alter table public.candidate_files enable row level security;
drop policy if exists cand_files_all on public.candidate_files;
create policy cand_files_all on public.candidate_files for all using (public.has_role(company_id, array['owner','admin','hr']))
  with check (public.has_role(company_id, array['owner','admin','hr'])
              and exists(select 1 from public.candidates c where c.id = candidate_id and c.company_id = candidate_files.company_id));
revoke all on public.candidate_files from anon;
grant select, insert, delete on public.candidate_files to authenticated;

-- ================= terms & privacy acceptance =================
create table if not exists public.terms_acceptance (
  user_id uuid not null references auth.users(id) on delete cascade,
  version text not null,
  at timestamptz not null default now(),
  primary key (user_id, version)
);
alter table public.terms_acceptance enable row level security;
drop policy if exists terms_own on public.terms_acceptance;
create policy terms_own on public.terms_acceptance for select using (user_id = auth.uid());
revoke all on public.terms_acceptance from anon, authenticated;
grant select on public.terms_acceptance to authenticated;
create or replace function public.accept_terms(p_version text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'سجّل الدخول أولاً' using errcode = '42501'; end if;
  if p_version !~ '^[0-9]{4}-[0-9]{2}$' then raise exception 'إصدار غير معروف'; end if;
  insert into public.terms_acceptance(user_id, version) values (auth.uid(), p_version) on conflict do nothing;
end $$;

-- ================= two-step verification (TOTP) =================
-- Once a user has a verified authenticator, a password-only session (aal1) no longer counts as a member:
-- every role check below also asks for aal2. Users without an authenticator are unaffected.
create or replace function public.aal_ok() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(auth.jwt()->>'aal', 'aal1') = 'aal2'
      or not exists(select 1 from auth.mfa_factors f where f.user_id = auth.uid() and f.status = 'verified')
$$;
create or replace function public.my_role(p_company uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from public.members where company_id = p_company and user_id = auth.uid() and public.aal_ok()
$$;
create or replace function public.is_member(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.members where company_id = p_company and user_id = auth.uid()) and public.aal_ok()
$$;
create or replace function public.my_employee(p_company uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select employee_id from public.members where company_id = p_company and user_id = auth.uid() and public.aal_ok()
$$;
create or replace function public.has_role(p_company uuid, p_roles text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.members where company_id = p_company and user_id = auth.uid() and (role = any(p_roles) or extra_roles && p_roles))
     and public.aal_ok()
$$;
create or replace function public.fin_can(p_company uuid, p_perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.aal_ok() and exists(select 1 from public.members m where m.company_id = p_company and m.user_id = auth.uid() and (
    m.role in ('owner','admin','finance') or m.extra_roles && array['admin','finance']
    or ((m.role in ('accountant','storekeeper') or m.extra_roles && array['accountant','storekeeper']) and (
         exists(select 1 from public.finance_permissions f where f.company_id = p_company and f.perm = p_perm
                and (f.role = m.role or f.role = any(m.extra_roles)))
      or exists(select 1 from public.member_perms x where x.company_id = p_company and x.user_id = m.user_id and x.perm = p_perm)))))
$$;
-- for the app: does this account have an authenticator, and is this session verified with it?
create or replace function public.mfa_state() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('enrolled', exists(select 1 from auth.mfa_factors f where f.user_id = auth.uid() and f.status = 'verified'),
                            'aal', coalesce(auth.jwt()->>'aal', 'aal1'))
$$;

-- ================= client error log (no personal data: message, place, browser) =================
create table if not exists public.client_errors (
  id bigint generated always as identity primary key,
  company_id uuid references public.companies(id) on delete cascade,
  user_id uuid default auth.uid(),
  message text not null,
  source text,
  route text,
  agent text,
  at timestamptz not null default now()
);
create index if not exists client_errors_at on public.client_errors(at);
alter table public.client_errors enable row level security;
revoke all on public.client_errors from anon, authenticated;
create or replace function public.log_client_error(p_company uuid, p_message text, p_source text, p_route text, p_agent text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  -- at most 30 reports per user per hour; the log keeps 30 days
  if (select count(*) from public.client_errors where user_id = auth.uid() and at > now() - interval '1 hour') >= 30 then return; end if;
  delete from public.client_errors where at < now() - interval '30 days';
  insert into public.client_errors(company_id, message, source, route, agent)
  values (case when public.is_member(p_company) then p_company end, left(coalesce(p_message, ''), 500), left(p_source, 300),
          left(regexp_replace(coalesce(p_route, ''), '[0-9a-f]{8}-[0-9a-f-]{27}', ':id', 'g'), 120), left(p_agent, 200));
end $$;

-- health check for the uptime monitor (also keeps the free project from pausing): no data, just "ok"
create or replace function public.ping() returns text language sql stable as $$ select 'ok'::text $$;
revoke all on function public.ping() from public;
grant execute on function public.ping() to anon, authenticated;

revoke all on function public.party_statement(uuid, date, date), public.import_items(uuid, jsonb), public.accept_terms(text),
  public.mfa_state(), public.log_client_error(uuid, text, text, text, text) from public, anon;
grant execute on function public.party_statement(uuid, date, date), public.import_items(uuid, jsonb), public.accept_terms(text),
  public.mfa_state(), public.log_client_error(uuid, text, text, text, text) to authenticated;
revoke all on function public.item_profile_guard(), public.item_active_guard() from public, anon, authenticated;
revoke all on function public.aal_ok() from public, anon;
grant execute on function public.aal_ok() to authenticated;
notify pgrst, 'reload schema';
