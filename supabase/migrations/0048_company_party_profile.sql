-- Waad ERP — 0048 company & party profile: official numbers, Saudi national address, contact, bank,
-- customer payment terms + credit limit, inactive parties, and import of customers/suppliers from Excel.
-- The national address (building, street, district, city, postal code, additional no.) is what ZATCA expects
-- for the seller on every tax invoice and for the buyer on a standard (B2B) tax invoice.

alter table public.companies
  add column if not exists unified_no text,
  add column if not exists mhrsd_no text,
  add column if not exists gosi_no text,
  add column if not exists bld_no text,
  add column if not exists street text,
  add column if not exists district text,
  add column if not exists city text,
  add column if not exists postal_code text,
  add column if not exists add_no text,
  add column if not exists short_address text,
  add column if not exists phone text,
  add column if not exists email text,
  add column if not exists iban text;

alter table public.parties
  add column if not exists country text not null default 'SA',
  add column if not exists bld_no text,
  add column if not exists street text,
  add column if not exists district text,
  add column if not exists postal_code text,
  add column if not exists add_no text,
  add column if not exists short_address text,
  add column if not exists email text,
  add column if not exists contact_name text,
  add column if not exists iban text,
  add column if not exists terms_days int,
  add column if not exists credit_limit numeric(14,2),
  add column if not exists active boolean not null default true,
  add column if not exists note text;
-- the old check only accepted Saudi mobiles; foreign suppliers have other numbers (validated in the guard below)
alter table public.parties drop constraint if exists parties_phone_check;

-- shared normalisation + validation of the address/contact block (companies and parties)
create or replace function public.addr_clean(r jsonb, p_saudi boolean) returns jsonb
language plpgsql immutable set search_path = public as $$
declare o jsonb := r; v text;
begin
  foreach v in array array['bld_no','street','district','city','postal_code','add_no','short_address','phone','email','iban'] loop
    o := jsonb_set(o, array[v], coalesce(to_jsonb(nullif(trim(coalesce(r->>v, '')), '')), 'null'::jsonb));
  end loop;
  o := jsonb_set(o, '{short_address}', coalesce(to_jsonb(nullif(upper(replace(coalesce(o->>'short_address', ''), ' ', '')), '')), 'null'::jsonb));
  o := jsonb_set(o, '{iban}', coalesce(to_jsonb(nullif(upper(replace(coalesce(o->>'iban', ''), ' ', '')), '')), 'null'::jsonb));
  o := jsonb_set(o, '{email}', coalesce(to_jsonb(nullif(lower(coalesce(o->>'email', '')), '')), 'null'::jsonb));
  o := jsonb_set(o, '{phone}', coalesce(to_jsonb(nullif(replace(replace(coalesce(o->>'phone', ''), ' ', ''), '-', ''), '')), 'null'::jsonb));
  if p_saudi then
    if o->>'bld_no' !~ '^[0-9]{4}$' then raise exception 'رقم المبنى 4 أرقام'; end if;
    if o->>'postal_code' !~ '^[0-9]{5}$' then raise exception 'الرمز البريدي 5 أرقام'; end if;
    if o->>'add_no' !~ '^[0-9]{4}$' then raise exception 'الرقم الإضافي 4 أرقام'; end if;
    if o->>'short_address' !~ '^[A-Z]{4}[0-9]{4}$' then raise exception 'العنوان المختصر 4 حروف و4 أرقام مثل RRRD2929'; end if;
    if o->>'iban' !~ '^SA[0-9]{22}$' then raise exception 'الآيبان السعودي يبدأ بـ SA ويليه 22 رقماً'; end if;
  end if;
  if o->>'email' !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'البريد الإلكتروني غير صحيح'; end if;
  if o->>'phone' !~ '^\+?[0-9]{7,15}$' then raise exception 'رقم الهاتف أرقام فقط'; end if;
  return o;
end $$;

create or replace function public.company_profile_guard() returns trigger
language plpgsql set search_path = public as $$
declare o jsonb;
begin
  o := public.addr_clean(to_jsonb(new), true);
  new.bld_no := o->>'bld_no'; new.street := o->>'street'; new.district := o->>'district'; new.city := o->>'city';
  new.postal_code := o->>'postal_code'; new.add_no := o->>'add_no'; new.short_address := o->>'short_address';
  new.phone := o->>'phone'; new.email := o->>'email'; new.iban := o->>'iban';
  new.unified_no := nullif(trim(coalesce(new.unified_no, '')), '');
  new.mhrsd_no := nullif(replace(trim(coalesce(new.mhrsd_no, '')), ' ', ''), '');
  new.gosi_no := nullif(trim(coalesce(new.gosi_no, '')), '');
  if new.unified_no !~ '^7[0-9]{9}$' then raise exception 'الرقم الموحد للمنشأة 10 أرقام يبدأ بـ 7'; end if;
  if new.mhrsd_no !~ '^[0-9]{1,3}-?[0-9]{1,10}$' then raise exception 'رقم المنشأة في وزارة الموارد البشرية مثل 1-123456'; end if;
  if new.gosi_no !~ '^[0-9]{5,12}$' then raise exception 'رقم المنشأة في التأمينات أرقام فقط'; end if;
  -- the free-text address used by letters is rebuilt from the national address once it is filled in
  if new.city is not null and (new.street is not null or new.district is not null) then
    new.address := public.addr_text(o);
  end if;
  return new;
end $$;

create or replace function public.addr_text(o jsonb) returns text language sql immutable as $$
  select nullif(concat_ws('، ',
    case when o->>'bld_no' is not null then 'مبنى ' || (o->>'bld_no') end,
    o->>'street',
    case when o->>'district' is not null then 'حي ' || (o->>'district') end,
    o->>'city',
    case when o->>'postal_code' is not null then 'الرمز البريدي ' || (o->>'postal_code') end,
    case when o->>'add_no' is not null then 'الرقم الإضافي ' || (o->>'add_no') end), '')
$$;
drop trigger if exists companies_profile_guard on public.companies;
create trigger companies_profile_guard before insert or update on public.companies for each row execute function public.company_profile_guard();

create or replace function public.party_profile_guard() returns trigger
language plpgsql set search_path = public as $$
declare o jsonb;
begin
  new.country := upper(coalesce(nullif(trim(new.country), ''), 'SA'));
  if new.country !~ '^[A-Z]{2}$' then raise exception 'رمز الدولة حرفان مثل SA'; end if;
  o := public.addr_clean(to_jsonb(new), new.country = 'SA');
  new.bld_no := o->>'bld_no'; new.street := o->>'street'; new.district := o->>'district'; new.city := o->>'city';
  new.postal_code := o->>'postal_code'; new.add_no := o->>'add_no'; new.short_address := o->>'short_address';
  new.phone := o->>'phone'; new.email := o->>'email'; new.iban := o->>'iban';
  new.contact_name := nullif(trim(coalesce(new.contact_name, '')), '');
  new.note := nullif(trim(coalesce(new.note, '')), '');
  if new.country <> 'SA' and new.vat_no is not null then raise exception 'الرقم الضريبي السعودي للجهات داخل المملكة فقط'; end if;
  if new.terms_days is not null and (new.terms_days < 0 or new.terms_days > 365) then raise exception 'مدة السداد بين 0 و365 يوماً'; end if;
  if new.credit_limit is not null and new.credit_limit < 0 then raise exception 'حد الائتمان لا يكون سالباً'; end if;
  if new.kind = 'supplier' then new.credit_limit := null; end if;
  return new;
end $$;
drop trigger if exists parties_profile_guard on public.parties;
create trigger parties_profile_guard before insert or update on public.parties for each row execute function public.party_profile_guard();

-- ---------- customer balance (open invoices − unallocated receipts) ----------
create or replace function public.party_balance(p_party uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select sum(i.total - public.paid_on(i.id)) from public.sales_invoices i where i.party_id = p_party and i.status = 'posted'), 0)
       + coalesce((select sum(b.total - public.paid_on(b.id)) from public.purchase_bills b where b.party_id = p_party and b.status = 'posted'), 0)
       - coalesce((select sum(y.amount) from public.payments y where y.party_id = p_party and y.invoice_id is null and y.bill_id is null), 0)
$$;
create or replace function public.party_credit(p_party uuid)
returns table(balance numeric, credit_limit numeric, terms_days int, active boolean)
language plpgsql stable security definer set search_path = public as $$
declare p public.parties;
begin
  select * into p from public.parties where id = p_party;
  if not found then return; end if;
  perform public.require_fin(p.company_id, case p.kind when 'customer' then 'sales' else 'purch' end);
  return query select round(public.party_balance(p.id), 2), p.credit_limit, p.terms_days, p.active;
end $$;

-- no new documents for an inactive customer/supplier
create or replace function public.party_active_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_table_name in ('sales_invoices','purchase_bills') then
    if coalesce((to_jsonb(new)->>'is_opening')::boolean, false) then return new; end if;
  end if;
  if exists(select 1 from public.parties where id = new.party_id and not active) then
    raise exception 'هذا الطرف موقوف — فعّله من بطاقته أولاً';
  end if;
  return new;
end $$;
drop trigger if exists sales_invoices_party_active on public.sales_invoices;
create trigger sales_invoices_party_active before insert on public.sales_invoices for each row execute function public.party_active_guard();
drop trigger if exists purchase_bills_party_active on public.purchase_bills;
create trigger purchase_bills_party_active before insert on public.purchase_bills for each row execute function public.party_active_guard();
drop trigger if exists sales_orders_party_active on public.sales_orders;
create trigger sales_orders_party_active before insert on public.sales_orders for each row execute function public.party_active_guard();
drop trigger if exists purchase_orders_party_active on public.purchase_orders;
create trigger purchase_orders_party_active before insert on public.purchase_orders for each row execute function public.party_active_guard();

-- credit limit: checked once the invoice total is set (posting inserts the header, then the totals).
-- Owner, admin and finance manager may exceed it knowingly (the screen asks them first); others are stopped.
create or replace function public.credit_limit_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare lim numeric; bal numeric;
begin
  if new.is_opening or new.status <> 'posted' or new.total <= coalesce(old.total, 0) then return new; end if;
  select credit_limit into lim from public.parties where id = new.party_id;
  if lim is null then return new; end if;
  if public.has_role(new.company_id, array['owner','admin','finance']) then return new; end if;
  bal := public.party_balance(new.party_id);
  if bal > lim then
    raise exception 'تجاوز حد الائتمان للعميل: الرصيد بعد الفاتورة % والحد % — يعتمدها المدير المالي أو المالك', round(bal, 2), round(lim, 2);
  end if;
  return new;
end $$;
drop trigger if exists sales_invoices_credit_limit on public.sales_invoices;
create trigger sales_invoices_credit_limit after update of total on public.sales_invoices for each row execute function public.credit_limit_guard();

-- ---------- import customers / suppliers from Excel (add new, update existing by name) ----------
create or replace function public.import_parties(p_company uuid, p_kind text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; ln text; nm text; p public.parties; added int := 0; updated int := 0; seen text[] := '{}';
  f text; v text; cols text[] := array['name_en','vat_no','cr_no','phone','email','contact_name','country','city','district','street','bld_no','postal_code','add_no','short_address','iban','note'];
begin
  if p_kind not in ('customer','supplier') then raise exception 'نوع غير معروف'; end if;
  perform public.require_fin(p_company, case p_kind when 'customer' then 'sales' else 'purch' end);
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'الملف لا يحتوي أسماء'; end if;
  if jsonb_array_length(p_rows) > 3000 then raise exception 'الحد الأقصى 3000 سطر في الملف الواحد'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    ln := 'السطر ' || coalesce(r->>'_row', '?') || ': ';
    nm := regexp_replace(trim(coalesce(r->>'name', '')), '\s+', ' ', 'g');
    if length(nm) < 3 then raise exception '%الاسم مطلوب (3 أحرف على الأقل)', ln; end if;
    if nm = any(seen) then raise exception '%الاسم «%» مكرر في الملف', ln, nm; end if;
    seen := seen || nm;
    begin
      select * into p from public.parties where company_id = p_company and kind = p_kind and name = nm;
      if not found then
        insert into public.parties(company_id, kind, name) values (p_company, p_kind, nm) returning * into p; added := added + 1;
      else updated := updated + 1; end if;
      p := jsonb_populate_record(p, (select coalesce(jsonb_object_agg(k, nullif(trim(r->>k), '')), '{}') from unnest(cols) k where nullif(trim(coalesce(r->>k, '')), '') is not null));
      if nullif(trim(coalesce(r->>'terms_days', '')), '') is not null then p.terms_days := (r->>'terms_days')::int; end if;
      if nullif(trim(coalesce(r->>'credit_limit', '')), '') is not null then p.credit_limit := (r->>'credit_limit')::numeric; end if;
      update public.parties set name_en = p.name_en, vat_no = p.vat_no, cr_no = p.cr_no, phone = p.phone, email = p.email, contact_name = p.contact_name,
        country = p.country, city = p.city, district = p.district, street = p.street, bld_no = p.bld_no, postal_code = p.postal_code, add_no = p.add_no,
        short_address = p.short_address, iban = p.iban, note = p.note, terms_days = p.terms_days, credit_limit = p.credit_limit where id = p.id;
    exception
      when check_violation then raise exception '%تحقق من الرقم الضريبي (15 رقماً يبدأ وينتهي بـ 3) والسجل التجاري (10 أرقام) والجوال (05XXXXXXXX)', ln;
      when invalid_text_representation then raise exception '%مدة السداد وحد الائتمان أرقام فقط', ln;
      when raise_exception then raise exception '%', ln || sqlerrm;
    end;
  end loop;
  return jsonb_build_object('added', added, 'updated', updated);
end $$;

revoke all on function public.addr_clean(jsonb, boolean), public.addr_text(jsonb) from public, anon;
grant execute on function public.addr_clean(jsonb, boolean), public.addr_text(jsonb) to authenticated;
revoke all on function public.party_balance(uuid),
  public.party_active_guard(), public.credit_limit_guard(), public.company_profile_guard(), public.party_profile_guard() from public, anon, authenticated;
revoke all on function public.party_credit(uuid), public.import_parties(uuid, text, jsonb) from public, anon;
grant execute on function public.party_credit(uuid), public.import_parties(uuid, text, jsonb) to authenticated;
notify pgrst, 'reload schema';
