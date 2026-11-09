-- Waad ERP — 0003 finance: chart of accounts, immutable double-entry ledger, sales, purchasing, inventory, VAT, reports
-- Posted documents are never edited: they are voided by a reversing entry.

create table public.accounts (
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null check (code ~ '^[0-9]{4}$'),
  name text not null,
  type text not null check (type in ('asset','liab','equity','rev','exp')),
  parent_code text,
  is_header boolean not null default false,
  primary key (company_id, code)
);

-- finance sub-roles: 'finance' (finance manager) has everything; accountant & storekeeper get configurable permissions
create table public.finance_permissions (
  company_id uuid not null references public.companies(id) on delete cascade,
  role text not null check (role in ('accountant','storekeeper')),
  perm text not null check (perm in ('dash','sales','purch','stock','stockadj','items','void','je','jepost','ledger','reports','vat','coa','payroll','settings')),
  primary key (company_id, role, perm)
);

create or replace function public.fin_can(p_company uuid, p_perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.members m where m.company_id = p_company and m.user_id = auth.uid() and (
    m.role in ('owner','admin','finance')
    or (m.role in ('accountant','storekeeper') and exists(select 1 from public.finance_permissions f where f.company_id = p_company and f.role = m.role and f.perm = p_perm))))
$$;

create or replace function public.require_fin(p_company uuid, p_perm text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.fin_can(p_company, p_perm) then
    raise exception 'غير مصرح: تحتاج صلاحية «%» في المالية', p_perm using errcode = '42501';
  end if;
end $$;

create or replace function public.set_finance_permission(p_company uuid, p_role text, p_perm text, p_allowed boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'settings');
  if p_role not in ('accountant','storekeeper') then raise exception 'صلاحيات المدير المالي ثابتة'; end if;
  if p_allowed then insert into public.finance_permissions values (p_company, p_role, p_perm) on conflict do nothing;
  else delete from public.finance_permissions where company_id = p_company and role = p_role and perm = p_perm; end if;
end $$;

create or replace function public.seed_company(p_company uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.accounts(company_id, code, name, type, parent_code, is_header) values
  (p_company,'1000','الأصول','asset',null,true),(p_company,'1100','النقدية والبنوك','asset','1000',true),
  (p_company,'1110','الصندوق','asset','1100',false),(p_company,'1120','البنك','asset','1100',false),
  (p_company,'1200','العملاء (ذمم مدينة)','asset','1000',false),(p_company,'1300','المخزون','asset','1000',false),
  (p_company,'1400','ضريبة القيمة المضافة — مدخلات','asset','1000',false),(p_company,'1500','سلف الموظفين','asset','1000',false),
  (p_company,'1600','مصروفات مدفوعة مقدماً','asset','1000',false),(p_company,'1700','الأصول الثابتة','asset','1000',false),
  (p_company,'2000','الخصوم','liab',null,true),(p_company,'2100','الموردون (ذمم دائنة)','liab','2000',false),
  (p_company,'2200','ضريبة القيمة المضافة — مخرجات','liab','2000',false),(p_company,'2300','رواتب مستحقة','liab','2000',false),
  (p_company,'2400','التأمينات الاجتماعية المستحقة','liab','2000',false),(p_company,'2500','مخصص مكافأة نهاية الخدمة','liab','2000',false),
  (p_company,'3000','حقوق الملكية','equity',null,true),(p_company,'3100','رأس المال','equity','3000',false),
  (p_company,'3200','الأرباح المبقاة','equity','3000',false),
  (p_company,'4000','الإيرادات','rev',null,true),(p_company,'4100','إيرادات المبيعات','rev','4000',false),
  (p_company,'4200','إيرادات الخدمات','rev','4000',false),(p_company,'4900','إيرادات أخرى','rev','4000',false),
  (p_company,'5000','المصروفات','exp',null,true),(p_company,'5100','تكلفة البضاعة المباعة','exp','5000',false),
  (p_company,'5200','الرواتب والأجور','exp','5000',false),(p_company,'5210','حصة المنشأة في التأمينات الاجتماعية','exp','5000',false),(p_company,'5300','الإيجار','exp','5000',false),
  (p_company,'5400','المرافق والاتصالات','exp','5000',false),(p_company,'5500','مصروفات إدارية وعمومية','exp','5000',false),
  (p_company,'5600','فروقات المخزون','exp','5000',false),(p_company,'5900','مصروفات أخرى','exp','5000',false)
  on conflict do nothing;
  insert into public.finance_permissions(company_id, role, perm)
  select p_company, r, p from (values ('accountant','sales'),('accountant','purch'),('accountant','stock'),('accountant','items'),('accountant','je'),
                                      ('storekeeper','stock'),('storekeeper','stockadj'),('storekeeper','items')) v(r,p)
  on conflict do nothing;
end $$;

create or replace function public.add_account(p_company uuid, p_code text, p_name text, p_parent text) returns void
language plpgsql security definer set search_path = public as $$
declare pa public.accounts;
begin
  perform public.require_fin(p_company, 'coa');
  select * into pa from public.accounts where company_id = p_company and code = p_parent and is_header;
  if not found then raise exception 'الحساب الرئيسي غير موجود'; end if;
  if left(p_code,1) <> left(p_parent,1) then raise exception 'رقم الحساب يبدأ بالرقم %', left(p_parent,1); end if;
  insert into public.accounts(company_id, code, name, type, parent_code) values (p_company, p_code, trim(p_name), pa.type, p_parent);
end $$;

-- ---------- ledger ----------
create table public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  date date not null,
  memo text not null,
  source text not null check (source in ('manual','reversal','sales','purchase','receipt','payment','stock','payroll','payroll_pay','advance','expense','opening','sales_return','purchase_return')),
  source_id uuid,
  reverses uuid references public.journal_entries(id),
  posted_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (company_id, no)
);
create index on public.journal_entries(company_id, date);
create index on public.journal_entries(source_id);

create table public.journal_lines (
  id bigint generated always as identity primary key,
  entry_id uuid not null references public.journal_entries(id) on delete cascade,
  company_id uuid not null,
  account_code text not null,
  debit numeric(14,2) not null default 0 check (debit >= 0),
  credit numeric(14,2) not null default 0 check (credit >= 0),
  check ((debit = 0) <> (credit = 0)),
  foreign key (company_id, account_code) references public.accounts(company_id, code)
);
create index on public.journal_lines(company_id, account_code);

create trigger je_immutable before update or delete on public.journal_entries for each row execute function public.block_change();
create trigger jl_immutable before update or delete on public.journal_lines for each row execute function public.block_change();

create or replace function public.check_entry_balanced() returns trigger language plpgsql security definer set search_path = public as $$
declare d numeric; c numeric; n int;
begin
  select coalesce(sum(debit),0), coalesce(sum(credit),0), count(*) into d, c, n from public.journal_lines where entry_id = new.entry_id;
  if n < 2 or d <> c then raise exception 'قيد غير متوازن (مدين % / دائن %)', d, c; end if;
  return null;
end $$;
create constraint trigger jl_balanced after insert on public.journal_lines deferrable initially deferred
  for each row execute function public.check_entry_balanced();

-- internal: post an entry. p_lines = [{"a":"1120","d":100},{"a":"3100","c":100}, ...]; zero lines are dropped.
create or replace function public.post_journal(p_company uuid, p_date date, p_memo text, p_source text, p_source_id uuid, p_lines jsonb, p_reverses uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare jid uuid; l jsonb; d numeric := 0; c numeric := 0; n int := 0; pre text;
begin
  for l in select * from jsonb_array_elements(p_lines) loop
    if round(coalesce((l->>'d')::numeric,0),2) = 0 and round(coalesce((l->>'c')::numeric,0),2) = 0 then continue; end if;
    if not exists(select 1 from public.accounts where company_id = p_company and code = l->>'a' and not is_header) then
      raise exception 'الحساب % غير موجود أو رئيسي', l->>'a'; end if;
    d := d + round(coalesce((l->>'d')::numeric,0),2); c := c + round(coalesce((l->>'c')::numeric,0),2); n := n + 1;
  end loop;
  if n < 2 or d <> c then raise exception 'قيد غير متوازن (مدين % / دائن %)', d, c; end if;
  pre := case p_source when 'manual' then 'JV' when 'reversal' then 'RJ' when 'opening' then 'OB' else 'AJ' end;
  insert into public.journal_entries(company_id, no, date, memo, source, source_id, reverses)
  values (p_company, public.next_doc_no(p_company, pre), p_date, p_memo, p_source, p_source_id, p_reverses) returning id into jid;
  insert into public.journal_lines(entry_id, company_id, account_code, debit, credit)
  select jid, p_company, x->>'a', round(coalesce((x->>'d')::numeric,0),2), round(coalesce((x->>'c')::numeric,0),2)
  from jsonb_array_elements(p_lines) x
  where round(coalesce((x->>'d')::numeric,0),2) <> 0 or round(coalesce((x->>'c')::numeric,0),2) <> 0;
  return jid;
end $$;

-- internal: reverse every entry linked to a source document
create or replace function public.reverse_source(p_company uuid, p_source_id uuid, p_date date, p_memo text) returns void
language plpgsql security definer set search_path = public as $$
declare j record;
begin
  for j in select * from public.journal_entries where company_id = p_company and source_id = p_source_id and reverses is null
           and not exists(select 1 from public.journal_entries r where r.reverses = journal_entries.id) loop
    perform public.post_journal(p_company, p_date, p_memo || ' — ' || j.no, 'reversal', p_source_id,
      (select jsonb_agg(jsonb_build_object('a', account_code, 'd', credit, 'c', debit)) from public.journal_lines where entry_id = j.id), j.id);
  end loop;
end $$;

create or replace function public.post_manual_journal(p_company uuid, p_date date, p_memo text, p_lines jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'jepost');
  if length(trim(coalesce(p_memo,''))) < 3 then raise exception 'اكتب بيان القيد'; end if;
  return public.post_journal(p_company, p_date, trim(p_memo), 'manual', null, p_lines);
end $$;

create or replace function public.reverse_journal(p_entry uuid, p_date date default current_date) returns uuid
language plpgsql security definer set search_path = public as $$
declare j public.journal_entries;
begin
  select * into j from public.journal_entries where id = p_entry;
  if not found then raise exception 'القيد غير موجود'; end if;
  perform public.require_fin(j.company_id, 'jepost');
  if j.source <> 'manual' then raise exception 'القيود الآلية تُعكس بإلغاء مستندها'; end if;
  if exists(select 1 from public.journal_entries where reverses = p_entry) then raise exception 'القيد معكوس مسبقاً'; end if;
  return public.post_journal(j.company_id, p_date, 'عكس ' || j.no || ' — ' || j.memo, 'reversal', null,
    (select jsonb_agg(jsonb_build_object('a', account_code, 'd', credit, 'c', debit)) from public.journal_lines where entry_id = p_entry), p_entry);
end $$;

-- ---------- parties & items ----------
create table public.parties (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  kind text not null check (kind in ('customer','supplier')),
  name text not null check (length(trim(name)) >= 3),
  vat_no text check (vat_no is null or vat_no ~ '^3[0-9]{13}3$'),
  cr_no text check (cr_no is null or cr_no ~ '^[0-9]{10}$'),
  phone text check (phone is null or phone ~ '^(05[0-9]{8}|\+9665[0-9]{8})$'),
  city text,
  created_at timestamptz not null default now(),
  unique (company_id, kind, name)
);

create table public.items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null,
  name text not null,
  type text not null check (type in ('stock','service')),
  unit text,
  sale_price numeric(12,2) not null default 0 check (sale_price >= 0),
  reorder_level numeric(12,3) not null default 0 check (reorder_level >= 0),
  created_at timestamptz not null default now(),
  unique (company_id, code)
);

create table public.stock_moves (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  item_id uuid not null references public.items(id),
  date date not null,
  qty numeric(14,3) not null check (qty <> 0),
  value numeric(14,2) not null,
  source text not null check (source in ('purchase','sale','adjust','void','return')),
  source_id uuid,
  note text,
  created_at timestamptz not null default now()
);
create index on public.stock_moves(company_id, item_id);
create trigger sm_immutable before update or delete on public.stock_moves for each row execute function public.block_change();

create or replace function public.stock_state(p_item uuid, out qty numeric, out value numeric, out avg_cost numeric)
language sql stable security definer set search_path = public as $$
  select coalesce(sum(qty),0), coalesce(sum(value),0), case when coalesce(sum(qty),0) > 0 then sum(value)/sum(qty) else 0 end
  from public.stock_moves where item_id = p_item
$$;

-- ---------- sales & purchasing documents ----------
create table public.sales_invoices (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null, date date not null, due_date date not null,
  party_id uuid not null references public.parties(id),
  subtotal numeric(14,2) not null, vat numeric(14,2) not null, total numeric(14,2) not null,
  status text not null default 'posted' check (status in ('posted','void')),
  note text, created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  unique (company_id, no)
);
create table public.sales_invoice_lines (
  id bigint generated always as identity primary key,
  invoice_id uuid not null references public.sales_invoices(id) on delete cascade,
  item_id uuid not null references public.items(id),
  qty numeric(14,3) not null check (qty > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  vat_rate numeric(5,2) not null default 15 check (vat_rate in (0,15)),
  amount numeric(14,2) not null, vat numeric(14,2) not null, cost numeric(14,2) not null default 0
);
create table public.purchase_bills (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null, supplier_ref text, date date not null, due_date date not null,
  party_id uuid not null references public.parties(id),
  subtotal numeric(14,2) not null, vat numeric(14,2) not null, total numeric(14,2) not null,
  status text not null default 'posted' check (status in ('posted','void')),
  note text, created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  unique (company_id, no)
);
create unique index purchase_bills_ref on public.purchase_bills(company_id, party_id, supplier_ref) where supplier_ref is not null and status = 'posted';
create table public.purchase_bill_lines (
  id bigint generated always as identity primary key,
  bill_id uuid not null references public.purchase_bills(id) on delete cascade,
  item_id uuid references public.items(id),
  account_code text,
  qty numeric(14,3) not null check (qty > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  vat_rate numeric(5,2) not null default 15 check (vat_rate in (0,15)),
  amount numeric(14,2) not null, vat numeric(14,2) not null,
  check ((item_id is null) <> (account_code is null))
);
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  direction text not null check (direction in ('in','out')),
  party_id uuid not null references public.parties(id),
  invoice_id uuid references public.sales_invoices(id),
  bill_id uuid references public.purchase_bills(id),
  date date not null,
  amount numeric(14,2) not null check (amount > 0),
  account_code text not null,
  note text, created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  unique (company_id, no),
  check (not (invoice_id is not null and bill_id is not null))
);

create or replace function public.paid_on(p_doc uuid) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(amount),0) from public.payments where invoice_id = p_doc or bill_id = p_doc
$$;

create or replace function public.post_sales_invoice(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  iid uuid; l jsonb; it public.items; st record; q numeric; pr numeric; vr numeric; amt numeric; vt numeric; cst numeric;
  sub numeric := 0; v_vat numeric := 0; cogs numeric := 0; rev_goods numeric := 0; rev_svc numeric := 0;
  d date := coalesce((p_doc->>'date')::date, current_date); pid uuid := (p_doc->>'party')::uuid; no text;
begin
  perform public.require_fin(p_company, 'sales');
  if not exists(select 1 from public.parties where id = pid and company_id = p_company and kind = 'customer') then raise exception 'اختر العميل'; end if;
  if d > current_date then raise exception 'تاريخ الفاتورة لا يكون في المستقبل'; end if;
  if (p_doc->>'due') is not null and (p_doc->>'due')::date < d then raise exception 'تاريخ الاستحقاق قبل تاريخ الفاتورة'; end if;
  if jsonb_array_length(coalesce(p_doc->'lines','[]')) = 0 then raise exception 'أضف بنداً واحداً على الأقل'; end if;
  -- stock availability per item (aggregated across lines)
  for l in select jsonb_build_object('item', x->>'item', 'qty', sum((x->>'qty')::numeric)) from jsonb_array_elements(p_doc->'lines') x group by x->>'item' loop
    select * into it from public.items where id = (l->>'item')::uuid and company_id = p_company;
    if not found then raise exception 'صنف غير موجود'; end if;
    if it.type = 'stock' then
      select * into st from public.stock_state(it.id);
      if (l->>'qty')::numeric > st.qty then raise exception 'الكمية المتوفرة من «%» % فقط', it.name, st.qty; end if;
    end if;
  end loop;
  no := public.next_doc_no(p_company, 'INV');
  insert into public.sales_invoices(company_id, no, date, due_date, party_id, subtotal, vat, total, note)
  values (p_company, no, d, coalesce((p_doc->>'due')::date, d), pid, 0, 0, 0, p_doc->>'note') returning id into iid;
  for l in select * from jsonb_array_elements(p_doc->'lines') loop
    select * into it from public.items where id = (l->>'item')::uuid;
    q := (l->>'qty')::numeric; pr := round((l->>'price')::numeric, 2); vr := coalesce((l->>'vat')::numeric, 15);
    if q is null or q <= 0 then raise exception 'الكمية أكبر من صفر'; end if;
    if pr is null or pr < 0 then raise exception 'أدخل السعر'; end if;
    amt := round(q * pr, 2); vt := round(amt * vr / 100, 2); cst := 0;
    if it.type = 'stock' then
      select * into st from public.stock_state(it.id);
      cst := case when st.qty = q then st.value else round(st.avg_cost * q, 2) end;
      insert into public.stock_moves(company_id, item_id, date, qty, value, source, source_id) values (p_company, it.id, d, -q, -cst, 'sale', iid);
      rev_goods := rev_goods + amt;
    else rev_svc := rev_svc + amt; end if;
    insert into public.sales_invoice_lines(invoice_id, item_id, qty, unit_price, vat_rate, amount, vat, cost) values (iid, it.id, q, pr, vr, amt, vt, cst);
    sub := sub + amt; v_vat := v_vat + vt; cogs := cogs + cst;
  end loop;
  update public.sales_invoices set subtotal = sub, vat = v_vat, total = sub + v_vat where id = iid;
  perform public.post_journal(p_company, d, 'فاتورة مبيعات ' || no, 'sales', iid, jsonb_build_array(
    jsonb_build_object('a','1200','d',sub + v_vat), jsonb_build_object('a','4100','c',rev_goods), jsonb_build_object('a','4200','c',rev_svc),
    jsonb_build_object('a','2200','c',v_vat), jsonb_build_object('a','5100','d',cogs), jsonb_build_object('a','1300','c',cogs)));
  return iid;
end $$;

create or replace function public.post_purchase_bill(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  bid uuid; l jsonb; it public.items; q numeric; pr numeric; vr numeric; amt numeric; vt numeric; acc text;
  sub numeric := 0; v_vat numeric := 0; dr jsonb := '{}'; lines jsonb := '[]'; k text;
  d date := coalesce((p_doc->>'date')::date, current_date); pid uuid := (p_doc->>'party')::uuid; no text; ref text := nullif(trim(p_doc->>'ref'),'');
begin
  perform public.require_fin(p_company, 'purch');
  if not exists(select 1 from public.parties where id = pid and company_id = p_company and kind = 'supplier') then raise exception 'اختر المورد'; end if;
  if d > current_date then raise exception 'تاريخ الفاتورة لا يكون في المستقبل'; end if;
  if ref is not null and exists(select 1 from public.purchase_bills where company_id = p_company and party_id = pid and supplier_ref = ref and status = 'posted') then
    raise exception 'رقم فاتورة المورد مسجّل مسبقاً'; end if;
  if jsonb_array_length(coalesce(p_doc->'lines','[]')) = 0 then raise exception 'أضف بنداً واحداً على الأقل'; end if;
  no := public.next_doc_no(p_company, 'BIL');
  insert into public.purchase_bills(company_id, no, supplier_ref, date, due_date, party_id, subtotal, vat, total, note)
  values (p_company, no, ref, d, coalesce((p_doc->>'due')::date, d), pid, 0, 0, 0, p_doc->>'note') returning id into bid;
  for l in select * from jsonb_array_elements(p_doc->'lines') loop
    q := (l->>'qty')::numeric; pr := round((l->>'price')::numeric, 2); vr := coalesce((l->>'vat')::numeric, 15);
    if q is null or q <= 0 then raise exception 'الكمية أكبر من صفر'; end if;
    if pr is null or pr < 0 then raise exception 'أدخل السعر'; end if;
    amt := round(q * pr, 2); vt := round(amt * vr / 100, 2);
    if l ? 'item' then
      select * into it from public.items where id = (l->>'item')::uuid and company_id = p_company;
      if not found then raise exception 'صنف غير موجود'; end if;
      acc := case when it.type = 'stock' then '1300' else '5500' end;
      if it.type = 'stock' then
        insert into public.stock_moves(company_id, item_id, date, qty, value, source, source_id) values (p_company, it.id, d, q, amt, 'purchase', bid);
      end if;
      insert into public.purchase_bill_lines(bill_id, item_id, qty, unit_price, vat_rate, amount, vat) values (bid, it.id, q, pr, vr, amt, vt);
    else
      acc := l->>'account';
      if not exists(select 1 from public.accounts where company_id = p_company and code = acc and not is_header and type in ('exp','asset') and acc not in ('1100','1110','1120','1200','1300','1400')) then
        raise exception 'حساب المصروف غير صالح: %', acc; end if;
      insert into public.purchase_bill_lines(bill_id, account_code, qty, unit_price, vat_rate, amount, vat) values (bid, acc, q, pr, vr, amt, vt);
    end if;
    dr := jsonb_set(dr, array[acc], to_jsonb(coalesce((dr->>acc)::numeric,0) + amt));
    sub := sub + amt; v_vat := v_vat + vt;
  end loop;
  update public.purchase_bills set subtotal = sub, vat = v_vat, total = sub + v_vat where id = bid;
  for k in select jsonb_object_keys(dr) loop lines := lines || jsonb_build_array(jsonb_build_object('a',k,'d',(dr->>k)::numeric)); end loop;
  lines := lines || jsonb_build_array(jsonb_build_object('a','1400','d',v_vat), jsonb_build_object('a','2100','c',sub + v_vat));
  perform public.post_journal(p_company, d, 'فاتورة مشتريات ' || no, 'purchase', bid, lines);
  return bid;
end $$;

create or replace function public.account_balance(p_company uuid, p_code text, p_as_of date) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(l.debit - l.credit),0) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
  where l.company_id = p_company and l.account_code = p_code and e.date <= p_as_of
$$;

create or replace function public.record_payment(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  dir text := p_doc->>'direction'; pid uuid := (p_doc->>'party')::uuid; amt numeric := round((p_doc->>'amount')::numeric, 2);
  d date := coalesce((p_doc->>'date')::date, current_date); acc text := coalesce(p_doc->>'account','1120');
  inv uuid := nullif(p_doc->>'invoice','')::uuid; bil uuid := nullif(p_doc->>'bill','')::uuid;
  tot numeric; ddate date; dparty uuid; pid2 uuid; no text;
begin
  perform public.require_fin(p_company, case dir when 'in' then 'sales' else 'purch' end);
  if dir not in ('in','out') then raise exception 'نوع السند غير صالح'; end if;
  if amt is null or amt <= 0 then raise exception 'أدخل مبلغاً أكبر من صفر'; end if;
  if d > current_date then raise exception 'تاريخ السند لا يكون في المستقبل'; end if;
  if acc not in (select code from public.accounts where company_id = p_company and parent_code = '1100' and not is_header) then raise exception 'اختر الصندوق أو البنك'; end if;
  if not exists(select 1 from public.parties where id = pid and company_id = p_company and kind = case dir when 'in' then 'customer' else 'supplier' end) then
    raise exception 'الطرف غير صالح'; end if;
  if dir = 'in' and bil is not null or dir = 'out' and inv is not null then raise exception 'المستند لا يطابق نوع السند'; end if;
  if coalesce(inv, bil) is not null then
    if inv is not null then select total, date, party_id into tot, ddate, dparty from public.sales_invoices where id = inv and company_id = p_company and status = 'posted';
    else select total, date, party_id into tot, ddate, dparty from public.purchase_bills where id = bil and company_id = p_company and status = 'posted'; end if;
    if tot is null then raise exception 'المستند غير موجود أو ملغى'; end if;
    if dparty <> pid then raise exception 'المستند لا يخص هذا الطرف'; end if;
    if d < ddate then raise exception 'تاريخ السند قبل تاريخ الفاتورة'; end if;
    if amt > tot - public.paid_on(coalesce(inv,bil)) + 0.001 then raise exception 'المبلغ أكبر من المتبقي (%)', tot - public.paid_on(coalesce(inv,bil)); end if;
  end if;
  if dir = 'out' and amt > public.account_balance(p_company, acc, d) then raise exception 'الرصيد المتاح %', public.account_balance(p_company, acc, d); end if;
  no := public.next_doc_no(p_company, case dir when 'in' then 'RV' else 'PV' end);
  insert into public.payments(company_id, no, direction, party_id, invoice_id, bill_id, date, amount, account_code, note)
  values (p_company, no, dir, pid, inv, bil, d, amt, acc, p_doc->>'note') returning id into pid2;
  perform public.post_journal(p_company, d, case dir when 'in' then 'سند قبض ' else 'سند صرف ' end || no, case dir when 'in' then 'receipt' else 'payment' end, pid2,
    case dir when 'in' then jsonb_build_array(jsonb_build_object('a',acc,'d',amt), jsonb_build_object('a','1200','c',amt))
             else jsonb_build_array(jsonb_build_object('a','2100','d',amt), jsonb_build_object('a',acc,'c',amt)) end);
  return pid2;
end $$;

create or replace function public.void_sales_invoice(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare s public.sales_invoices; m record;
begin
  select * into s from public.sales_invoices where id = p_id for update;
  if not found then raise exception 'الفاتورة غير موجودة'; end if;
  perform public.require_fin(s.company_id, 'void');
  if s.status = 'void' then raise exception 'الفاتورة ملغاة مسبقاً'; end if;
  if public.paid_on(p_id) > 0 then raise exception 'لا يمكن إلغاء فاتورة عليها سداد'; end if;
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'اكتب سبب الإلغاء'; end if;
  for m in select * from public.stock_moves where source_id = p_id and source = 'sale' loop
    insert into public.stock_moves(company_id, item_id, date, qty, value, source, source_id, note) values (m.company_id, m.item_id, current_date, -m.qty, -m.value, 'void', p_id, p_reason);
  end loop;
  perform public.reverse_source(s.company_id, p_id, current_date, 'إلغاء فاتورة مبيعات');
  update public.sales_invoices set status = 'void', note = coalesce(note || ' — ','') || 'سبب الإلغاء: ' || trim(p_reason) where id = p_id;
end $$;

create or replace function public.void_purchase_bill(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare b public.purchase_bills; m record; st record;
begin
  select * into b from public.purchase_bills where id = p_id for update;
  if not found then raise exception 'الفاتورة غير موجودة'; end if;
  perform public.require_fin(b.company_id, 'void');
  if b.status = 'void' then raise exception 'الفاتورة ملغاة مسبقاً'; end if;
  if public.paid_on(p_id) > 0 then raise exception 'لا يمكن إلغاء فاتورة عليها سداد'; end if;
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'اكتب سبب الإلغاء'; end if;
  for m in select * from public.stock_moves where source_id = p_id and source = 'purchase' loop
    select * into st from public.stock_state(m.item_id);
    if st.qty < m.qty then raise exception 'لا يمكن الإلغاء: جزء من الكمية بيع'; end if;
    insert into public.stock_moves(company_id, item_id, date, qty, value, source, source_id, note) values (m.company_id, m.item_id, current_date, -m.qty, -m.value, 'void', p_id, p_reason);
  end loop;
  perform public.reverse_source(b.company_id, p_id, current_date, 'إلغاء فاتورة مشتريات');
  update public.purchase_bills set status = 'void', note = coalesce(note || ' — ','') || 'سبب الإلغاء: ' || trim(p_reason) where id = p_id;
end $$;

-- ---------- credit notes (sales returns) & purchase returns ----------
create table public.credit_notes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  kind text not null check (kind in ('sales','purchase')),
  doc_id uuid not null,
  party_id uuid not null references public.parties(id),
  date date not null,
  reason text not null check (length(trim(reason)) >= 3),
  subtotal numeric(14,2) not null, vat numeric(14,2) not null, total numeric(14,2) not null,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  unique (company_id, no)
);
create index on public.credit_notes(doc_id);
create table public.credit_note_lines (
  id bigint generated always as identity primary key,
  note_id uuid not null references public.credit_notes(id) on delete cascade,
  src_line bigint not null,
  item_id uuid references public.items(id),
  account_code text,
  qty numeric(14,3) not null check (qty > 0),
  unit_price numeric(12,2) not null,
  vat_rate numeric(5,2) not null,
  amount numeric(14,2) not null, vat numeric(14,2) not null, cost numeric(14,2) not null default 0
);
create or replace function public.cn_guard() returns trigger language plpgsql as $$
begin
  -- the only allowed update is the one-time totals fill inside post_credit_note
  if tg_op = 'UPDATE' and old.total = 0 and old.subtotal = 0 and old.vat = 0
     and (new.id, new.company_id, new.no, new.kind, new.doc_id, new.party_id, new.date, new.reason) = (old.id, old.company_id, old.no, old.kind, old.doc_id, old.party_id, old.date, old.reason) then
    return new;
  end if;
  raise exception 'credit_notes records are append-only and cannot be modified' using errcode = '42501';
end $$;
create trigger cn_immutable before update or delete on public.credit_notes for each row execute function public.cn_guard();
create trigger cnl_immutable before update or delete on public.credit_note_lines for each row execute function public.block_change();

-- settled amount = payments + credit/debit notes against the document
create or replace function public.paid_on(p_doc uuid) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select sum(amount) from public.payments where invoice_id = p_doc or bill_id = p_doc),0)
       + coalesce((select sum(total) from public.credit_notes where doc_id = p_doc),0)
$$;

-- p_doc = {"kind":"sales"|"purchase","doc":<invoice/bill id>,"date":"YYYY-MM-DD","reason":"...","lines":[{"line":<source line id>,"qty":n}]}
create or replace function public.post_credit_note(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  k text := p_doc->>'kind'; did uuid := (p_doc->>'doc')::uuid; d date := coalesce((p_doc->>'date')::date, current_date);
  rsn text := trim(coalesce(p_doc->>'reason','')); nid uuid; no text; l jsonb; q numeric; used numeric;
  src record; ddate date; pid uuid; st text; amt numeric; vt numeric; cst numeric; it public.items; ss record;
  sub numeric := 0; v_vat numeric := 0; cogs numeric := 0; acc jsonb := '{}'; lines jsonb := '[]'; a text; stock_out numeric := 0;
begin
  perform public.require_fin(p_company, 'void');
  if k not in ('sales','purchase') then raise exception 'نوع الإشعار غير صالح'; end if;
  if length(rsn) < 3 then raise exception 'اكتب سبب الإشعار'; end if;
  if k = 'sales' then select date, party_id, status into ddate, pid, st from public.sales_invoices where id = did and company_id = p_company;
  else select date, party_id, status into ddate, pid, st from public.purchase_bills where id = did and company_id = p_company; end if;
  if ddate is null then raise exception 'المستند غير موجود'; end if;
  if st <> 'posted' then raise exception 'المستند ملغى'; end if;
  if d < ddate then raise exception 'التاريخ قبل تاريخ الفاتورة'; end if;
  if d > current_date then raise exception 'التاريخ لا يكون في المستقبل'; end if;
  if jsonb_array_length(coalesce(p_doc->'lines','[]')) = 0 then raise exception 'أدخل كمية مرتجع لبند واحد على الأقل'; end if;
  no := public.next_doc_no(p_company, case k when 'sales' then 'CN' else 'DN' end);
  insert into public.credit_notes(company_id, no, kind, doc_id, party_id, date, reason, subtotal, vat, total)
  values (p_company, no, k, did, pid, d, rsn, 0, 0, 0) returning id into nid;
  for l in select * from jsonb_array_elements(p_doc->'lines') loop
    q := (l->>'qty')::numeric;
    if q is null or q <= 0 then raise exception 'الكمية أكبر من صفر'; end if;
    if k = 'sales' then
      select id, item_id, null::text account_code, qty, unit_price, vat_rate, cost into src from public.sales_invoice_lines where id = (l->>'line')::bigint and invoice_id = did;
    else
      select id, item_id, account_code, qty, unit_price, vat_rate, 0::numeric cost into src from public.purchase_bill_lines where id = (l->>'line')::bigint and bill_id = did;
    end if;
    if not found then raise exception 'بند غير موجود في الفاتورة'; end if;
    select coalesce(sum(cl.qty),0) into used from public.credit_note_lines cl join public.credit_notes n on n.id = cl.note_id where n.doc_id = did and cl.src_line = src.id;
    if q > src.qty - used then raise exception 'كمية المرتجع أكبر من المتاح (%)', src.qty - used; end if;
    amt := round(q * src.unit_price, 2); vt := round(amt * src.vat_rate / 100, 2); cst := 0;
    if src.item_id is not null then select * into it from public.items where id = src.item_id; end if;
    if k = 'sales' then
      a := case when it.type = 'service' then '4200' else '4100' end;
      if it.type = 'stock' then
        cst := round(src.cost / src.qty * q, 2);
        insert into public.stock_moves(company_id, item_id, date, qty, value, source, source_id, note) values (p_company, it.id, d, q, cst, 'return', nid, rsn);
        cogs := cogs + cst;
      end if;
    else
      if src.item_id is null then a := src.account_code;
      elsif it.type = 'stock' then
        a := '1300';
        select * into ss from public.stock_state(it.id);
        if ss.qty < q then raise exception 'الكمية المتوفرة من «%» % فقط', it.name, ss.qty; end if;
        insert into public.stock_moves(company_id, item_id, date, qty, value, source, source_id, note) values (p_company, it.id, d, -q, -amt, 'return', nid, rsn);
      else a := '5500'; end if;
    end if;
    insert into public.credit_note_lines(note_id, src_line, item_id, account_code, qty, unit_price, vat_rate, amount, vat, cost)
    values (nid, src.id, src.item_id, src.account_code, q, src.unit_price, src.vat_rate, amt, vt, cst);
    acc := jsonb_set(acc, array[a], to_jsonb(coalesce((acc->>a)::numeric,0) + amt));
    sub := sub + amt; v_vat := v_vat + vt;
    it := null;
  end loop;
  update public.credit_notes set subtotal = sub, vat = v_vat, total = sub + v_vat where id = nid;
  if k = 'sales' then
    for a in select jsonb_object_keys(acc) loop lines := lines || jsonb_build_array(jsonb_build_object('a',a,'d',(acc->>a)::numeric)); end loop;
    lines := lines || jsonb_build_array(jsonb_build_object('a','2200','d',v_vat), jsonb_build_object('a','1200','c',sub + v_vat),
                                       jsonb_build_object('a','1300','d',cogs), jsonb_build_object('a','5100','c',cogs));
    perform public.post_journal(p_company, d, 'إشعار دائن ' || no, 'sales_return', nid, lines);
  else
    lines := jsonb_build_array(jsonb_build_object('a','2100','d',sub + v_vat), jsonb_build_object('a','1400','c',v_vat));
    for a in select jsonb_object_keys(acc) loop lines := lines || jsonb_build_array(jsonb_build_object('a',a,'c',(acc->>a)::numeric)); end loop;
    perform public.post_journal(p_company, d, 'مرتجع مشتريات ' || no, 'purchase_return', nid, lines);
  end if;
  return nid;
end $$;

create or replace function public.stock_adjust(p_company uuid, p_item uuid, p_date date, p_qty numeric, p_unit_cost numeric, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare it public.items; st record; v numeric; aid uuid := gen_random_uuid();
begin
  perform public.require_fin(p_company, 'stockadj');
  select * into it from public.items where id = p_item and company_id = p_company and type = 'stock';
  if not found then raise exception 'الصنف غير موجود أو ليس مخزنياً'; end if;
  if coalesce(p_qty,0) = 0 then raise exception 'أدخل كمية التسوية'; end if;
  if p_date > current_date then raise exception 'التاريخ لا يكون في المستقبل'; end if;
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'اكتب سبب التسوية'; end if;
  select * into st from public.stock_state(p_item);
  if p_qty < 0 and st.qty + p_qty < 0 then raise exception 'العجز أكبر من الرصيد المتوفر (%)', st.qty; end if;
  v := case when p_qty > 0 then round(p_qty * coalesce(p_unit_cost, st.avg_cost), 2)
            when st.qty + p_qty = 0 then -st.value else round(p_qty * st.avg_cost, 2) end;
  insert into public.stock_moves(company_id, item_id, date, qty, value, source, source_id, note) values (p_company, p_item, p_date, p_qty, v, 'adjust', aid, trim(p_reason));
  perform public.post_journal(p_company, p_date, 'تسوية مخزون — ' || it.name, 'stock', aid,
    case when v >= 0 then jsonb_build_array(jsonb_build_object('a','1300','d',v), jsonb_build_object('a','5600','c',v))
         else jsonb_build_array(jsonb_build_object('a','5600','d',-v), jsonb_build_object('a','1300','c',-v)) end);
end $$;

-- ---------- reports (finance roles only) ----------
create or replace function public.trial_balance(p_company uuid, p_as_of date)
returns table(code text, name text, debit numeric, credit numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'reports');
  return query
  select a.code, a.name, greatest(sum(l.debit - l.credit), 0)::numeric, greatest(sum(l.credit - l.debit), 0)::numeric
  from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
  join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
  where l.company_id = p_company and e.date <= p_as_of
  group by a.code, a.name having sum(l.debit - l.credit) <> 0 order by a.code;
end $$;

create or replace function public.income_statement(p_company uuid, p_from date, p_to date)
returns table(section text, code text, name text, amount numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'reports');
  return query
  with b as (
    select a.code, a.name, a.type, sum(l.credit - l.debit) cr
    from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
    join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
    where l.company_id = p_company and e.date between p_from and p_to and a.type in ('rev','exp')
    group by a.code, a.name, a.type having sum(l.credit - l.debit) <> 0)
  select case when b.type = 'rev' then 'revenue' when b.code = '5100' then 'cogs' else 'expense' end, b.code, b.name,
         case when b.type = 'rev' then b.cr else -b.cr end from b
  union all
  select 'net_profit', null, 'صافي الربح', coalesce(sum(b.cr),0) from b
  order by 1 desc, 2;
end $$;

create or replace function public.balance_sheet(p_company uuid, p_as_of date)
returns table(section text, code text, name text, amount numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'reports');
  return query
  with b as (
    select a.code, a.name, a.type, sum(l.debit - l.credit) dr
    from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
    join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
    where l.company_id = p_company and e.date <= p_as_of
    group by a.code, a.name, a.type)
  select b.type, b.code, b.name, case when b.type = 'asset' then b.dr else -b.dr end from b where b.type in ('asset','liab','equity') and b.dr <> 0
  union all
  select 'equity', null, 'أرباح (خسائر) الفترة غير المقفلة', coalesce(-sum(b.dr) filter (where b.type in ('rev','exp')), 0) from b
  order by 1, 2 nulls last;
end $$;

create or replace function public.vat_summary(p_company uuid, p_from date, p_to date)
returns table(sales_taxable numeric, sales_zero numeric, output_vat numeric, purchases_taxable numeric, purchases_zero numeric, input_vat numeric, net_vat numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'vat');
  return query
  with s as (select coalesce(sum(l.amount) filter (where l.vat_rate > 0),0) t, coalesce(sum(l.amount) filter (where l.vat_rate = 0),0) z, coalesce(sum(l.vat),0) v
             from public.sales_invoice_lines l join public.sales_invoices i on i.id = l.invoice_id
             where i.company_id = p_company and i.status = 'posted' and i.date between p_from and p_to),
       p as (select coalesce(sum(l.amount) filter (where l.vat_rate > 0),0) t, coalesce(sum(l.amount) filter (where l.vat_rate = 0),0) z, coalesce(sum(l.vat),0) v
             from public.purchase_bill_lines l join public.purchase_bills b on b.id = l.bill_id
             where b.company_id = p_company and b.status = 'posted' and b.date between p_from and p_to)
       , cs as (select coalesce(sum(l.amount) filter (where l.vat_rate > 0),0) t, coalesce(sum(l.amount) filter (where l.vat_rate = 0),0) z, coalesce(sum(l.vat),0) v
             from public.credit_note_lines l join public.credit_notes n on n.id = l.note_id
             where n.company_id = p_company and n.kind = 'sales' and n.date between p_from and p_to),
       cp as (select coalesce(sum(l.amount) filter (where l.vat_rate > 0),0) t, coalesce(sum(l.amount) filter (where l.vat_rate = 0),0) z, coalesce(sum(l.vat),0) v
             from public.credit_note_lines l join public.credit_notes n on n.id = l.note_id
             where n.company_id = p_company and n.kind = 'purchase' and n.date between p_from and p_to)
  select s.t - cs.t, s.z - cs.z, s.v - cs.v, p.t - cp.t, p.z - cp.z, p.v - cp.v, (s.v - cs.v) - (p.v - cp.v) from s, p, cs, cp;
end $$;

create or replace function public.account_ledger(p_company uuid, p_code text, p_from date, p_to date)
returns table(date date, no text, memo text, debit numeric, credit numeric, balance numeric)
language plpgsql stable security definer set search_path = public as $$
declare sgn int;
begin
  perform public.require_fin(p_company, 'ledger');
  select case when type in ('asset','exp') then 1 else -1 end into sgn from public.accounts where company_id = p_company and code = p_code;
  return query
  with op as (select coalesce(sum(l.debit - l.credit),0) * sgn v from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
              where l.company_id = p_company and l.account_code = p_code and e.date < p_from),
       mv as (select e.date, e.no, e.memo, l.debit, l.credit, e.created_at, l.id from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
              where l.company_id = p_company and l.account_code = p_code and e.date between p_from and p_to)
  select x.date, x.no, x.memo, x.debit, x.credit, x.balance from (
    select null::date date, null::text no, 'رصيد أول المدة'::text memo, null::numeric debit, null::numeric credit, (select v from op) balance, 0 k, null::timestamptz ts, 0::bigint lid
    union all
    select mv.date, mv.no, mv.memo, mv.debit, mv.credit,
           (select v from op) + sum((mv.debit - mv.credit) * sgn) over (order by mv.date, mv.created_at, mv.id), 1, mv.created_at, mv.id
    from mv) x
  order by x.k, x.date, x.ts, x.lid;
end $$;

-- receivables / payables aging as of a date (buckets by days past due)
create or replace function public.aging(p_company uuid, p_kind text, p_as_of date)
returns table(party_id uuid, party text, not_due numeric, d1_30 numeric, d31_60 numeric, d61_90 numeric, d90_plus numeric, unallocated numeric, net numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, case p_kind when 'sales' then 'sales' else 'purch' end);
  return query
  with docs as (
    select i.party_id pid, i.due_date due, i.total - public.paid_on(i.id) rem from public.sales_invoices i
     where p_kind = 'sales' and i.company_id = p_company and i.status = 'posted' and i.date <= p_as_of
    union all
    select b.party_id, b.due_date, b.total - public.paid_on(b.id) from public.purchase_bills b
     where p_kind = 'purchase' and b.company_id = p_company and b.status = 'posted' and b.date <= p_as_of),
  un as (
    select y.party_id pid, sum(y.amount) amt from public.payments y
     where y.company_id = p_company and y.invoice_id is null and y.bill_id is null and y.date <= p_as_of
       and y.direction = case p_kind when 'sales' then 'in' else 'out' end group by y.party_id),
  agg as (
    select d.pid,
      sum(d.rem) filter (where d.rem > 0 and p_as_of - d.due <= 0) nd,
      sum(d.rem) filter (where d.rem > 0 and p_as_of - d.due between 1 and 30) a1,
      sum(d.rem) filter (where d.rem > 0 and p_as_of - d.due between 31 and 60) a2,
      sum(d.rem) filter (where d.rem > 0 and p_as_of - d.due between 61 and 90) a3,
      sum(d.rem) filter (where d.rem > 0 and p_as_of - d.due > 90) a4,
      -sum(d.rem) filter (where d.rem < 0) cr
    from docs d group by d.pid)
  select p.id, p.name, coalesce(a.nd,0), coalesce(a.a1,0), coalesce(a.a2,0), coalesce(a.a3,0), coalesce(a.a4,0),
         coalesce(a.cr,0) + coalesce(u.amt,0),
         coalesce(a.nd,0)+coalesce(a.a1,0)+coalesce(a.a2,0)+coalesce(a.a3,0)+coalesce(a.a4,0) - coalesce(a.cr,0) - coalesce(u.amt,0)
  from public.parties p left join agg a on a.pid = p.id left join un u on u.pid = p.id
  where p.company_id = p_company and p.kind = case p_kind when 'sales' then 'customer' else 'supplier' end
    and (a.pid is not null or u.pid is not null)
  order by 9 desc;
end $$;

-- ---------- audit & RLS ----------
create trigger audit_accounts after insert or update or delete on public.accounts for each row execute function public.audit_trigger();
create trigger audit_parties after insert or update or delete on public.parties for each row execute function public.audit_trigger();
create trigger audit_items after insert or update or delete on public.items for each row execute function public.audit_trigger();
create trigger audit_sales after insert or update on public.sales_invoices for each row execute function public.audit_trigger();
create trigger audit_bills after insert or update on public.purchase_bills for each row execute function public.audit_trigger();
create trigger audit_payments after insert or update or delete on public.payments for each row execute function public.audit_trigger();
create trigger audit_credit_notes after insert on public.credit_notes for each row execute function public.audit_trigger();
create trigger audit_je after insert on public.journal_entries for each row execute function public.audit_trigger();

do $$ declare t text; begin
  foreach t in array array['accounts','journal_entries','journal_lines','parties','items','stock_moves','sales_invoices','sales_invoice_lines','purchase_bills','purchase_bill_lines','payments'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

create or replace function public.fin(p_company uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.has_role(p_company, array['owner','admin','finance','accountant','storekeeper'])
$$;
create or replace function public.je_visible(p_entry uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.journal_entries e where e.id = p_entry and public.fin_can(e.company_id, 'je')
    and (e.source not in ('payroll','payroll_pay','advance','expense') or public.fin_can(e.company_id, 'payroll')))
$$;
alter table public.finance_permissions enable row level security;
create policy fp_read on public.finance_permissions for select using (public.fin(company_id));
create policy acc_read on public.accounts for select using (public.fin(company_id));
create policy je_read on public.journal_entries for select using (public.je_visible(id));
create policy jl_read on public.journal_lines for select using (public.je_visible(entry_id));
create policy party_read on public.parties for select using (public.fin_can(company_id, case kind when 'customer' then 'sales' else 'purch' end));
create policy party_write on public.parties for insert with check (public.fin_can(company_id, case kind when 'customer' then 'sales' else 'purch' end));
create policy party_update on public.parties for update using (public.fin_can(company_id, case kind when 'customer' then 'sales' else 'purch' end)) with check (public.fin_can(company_id, case kind when 'customer' then 'sales' else 'purch' end));
create policy item_read on public.items for select using (public.fin_can(company_id, 'stock') or public.fin_can(company_id, 'sales') or public.fin_can(company_id, 'purch'));
create policy item_write on public.items for insert with check (public.fin_can(company_id, 'items'));
create policy item_update on public.items for update using (public.fin_can(company_id, 'items')) with check (public.fin_can(company_id, 'items'));
create policy sm_read on public.stock_moves for select using (public.fin_can(company_id, 'stock'));
create policy si_read on public.sales_invoices for select using (public.fin_can(company_id, 'sales'));
create policy pb_read on public.purchase_bills for select using (public.fin_can(company_id, 'purch'));
alter table public.credit_notes enable row level security;
alter table public.credit_note_lines enable row level security;
create policy cn_read on public.credit_notes for select using (public.fin_can(company_id, case kind when 'sales' then 'sales' else 'purch' end));
create policy cnl_read on public.credit_note_lines for select using (exists(select 1 from public.credit_notes n where n.id = note_id));
create policy pay_read on public.payments for select using (public.fin_can(company_id, case direction when 'in' then 'sales' else 'purch' end));
create policy sil_read on public.sales_invoice_lines for select using (exists(select 1 from public.sales_invoices i where i.id = invoice_id));
create policy pbl_read on public.purchase_bill_lines for select using (exists(select 1 from public.purchase_bills b where b.id = bill_id));
-- documents, ledger and stock are written only through the security-definer RPCs above.
