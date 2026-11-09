-- Finance, part 2: cheques (incoming / outgoing, due dates, clearing, bounce), foreign currencies on invoices and bills
-- with realised exchange differences, opening balances import, year-end closing to retained earnings, petty cash funds.

alter table public.journal_entries drop constraint journal_entries_source_check;
alter table public.journal_entries add constraint journal_entries_source_check check (source in
  ('manual','reversal','sales','purchase','receipt','payment','stock','payroll','payroll_pay','advance','expense','opening','sales_return','purchase_return',
   'asset','depreciation','cheque','closing','petty'));

-- period guard: the year-end closing (and its reversal) may be dated on a day that is already locked
create or replace function public.period_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare lk date;
begin
  select books_closed_through into lk from public.companies where id = new.company_id;
  if lk is not null and new.date <= lk then
    if tg_table_name = 'journal_entries' and current_setting('waad.closing', true) = '1' and new.source in ('closing','reversal') then return new; end if;
    raise exception 'الفترة مقفلة حتى % — لا تُسجل حركات بتاريخ قبلها', lk;
  end if;
  return new;
end $$;

-- ================= extra accounts (created when first needed) =================
create or replace function public.ensure_fin2_accounts(p_company uuid) returns void
language sql security definer set search_path = public as $$
  insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header) values
    (p_company, '1150', 'شيكات برسم التحصيل', 'Cheques under collection', 'asset', '1000', false),
    (p_company, '2160', 'شيكات صادرة مؤجلة الدفع', 'Post-dated cheques issued', 'liab', '2000', false),
    (p_company, '3900', 'أرصدة افتتاحية', 'Opening balances', 'equity', '3000', false),
    (p_company, '4950', 'أرباح فروقات العملة', 'Foreign exchange gains', 'rev', '4000', false),
    (p_company, '5950', 'خسائر فروقات العملة', 'Foreign exchange losses', 'exp', '5000', false)
  on conflict do nothing
$$;
select public.ensure_fin2_accounts(id) from public.companies;

-- ================= CHEQUES =================
create table public.cheques (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  direction text not null check (direction in ('in','out')),
  party_id uuid not null references public.parties(id),
  invoice_id uuid references public.sales_invoices(id),
  bill_id uuid references public.purchase_bills(id),
  cheque_no text not null check (length(trim(cheque_no)) between 1 and 30),
  bank text,
  amount numeric(14,2) not null check (amount > 0),
  issue_date date not null,          -- received from the customer / handed to the supplier
  due_date date not null,            -- the date written on the cheque
  status text not null default 'open' check (status in ('open','cleared','bounced','cancelled')),
  payment_id uuid,                   -- the receipt / payment voucher while the cheque counts as paid
  bank_account text,                 -- where it was cleared
  closed_on date, reason text, note text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  unique (company_id, no),
  check (due_date >= issue_date)
);
create index on public.cheques(company_id, status, due_date);

-- receive a customer cheque / issue a supplier cheque: the party is settled now, the money moves on clearing
create or replace function public.cheque_save(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare dir text := p_doc->>'direction'; pid uuid := nullif(p_doc->>'party','')::uuid; amt numeric := round((p_doc->>'amount')::numeric, 2);
  d date := coalesce(nullif(p_doc->>'issue_date','')::date, current_date); due date := coalesce(nullif(p_doc->>'due_date','')::date, d);
  inv uuid := nullif(p_doc->>'invoice','')::uuid; bil uuid := nullif(p_doc->>'bill','')::uuid;
  tot numeric; ddate date; dparty uuid; pno text; payid uuid; cid uuid; hold text;
begin
  if dir not in ('in','out') then raise exception 'نوع الشيك غير صالح'; end if;
  perform public.require_fin(p_company, case dir when 'in' then 'sales' else 'purch' end);
  perform public.ensure_fin2_accounts(p_company);
  if amt is null or amt <= 0 then raise exception 'أدخل مبلغاً أكبر من صفر'; end if;
  if d > current_date then raise exception 'تاريخ الاستلام أو الإصدار لا يكون في المستقبل'; end if;
  if due < d then raise exception 'تاريخ استحقاق الشيك قبل تاريخ استلامه'; end if;
  if length(trim(coalesce(p_doc->>'cheque_no',''))) = 0 then raise exception 'أدخل رقم الشيك'; end if;
  if not exists(select 1 from public.parties where id = pid and company_id = p_company and kind = case dir when 'in' then 'customer' else 'supplier' end) then
    raise exception 'الطرف غير صالح'; end if;
  if dir = 'in' and bil is not null or dir = 'out' and inv is not null then raise exception 'المستند لا يطابق نوع الشيك'; end if;
  if coalesce(inv, bil) is not null then
    if inv is not null then select total, date, party_id into tot, ddate, dparty from public.sales_invoices where id = inv and company_id = p_company and status = 'posted';
    else select total, date, party_id into tot, ddate, dparty from public.purchase_bills where id = bil and company_id = p_company and status = 'posted'; end if;
    if tot is null then raise exception 'المستند غير موجود أو ملغى'; end if;
    if dparty <> pid then raise exception 'المستند لا يخص هذا الطرف'; end if;
    if d < ddate then raise exception 'تاريخ الشيك قبل تاريخ الفاتورة'; end if;
    if amt > tot - public.paid_on(coalesce(inv, bil)) + 0.001 then raise exception 'المبلغ أكبر من المتبقي (%)', tot - public.paid_on(coalesce(inv, bil)); end if;
  end if;
  hold := case dir when 'in' then '1150' else '2160' end;
  pno := public.next_doc_no(p_company, case dir when 'in' then 'RV' else 'PV' end);
  insert into public.payments(company_id, no, direction, party_id, invoice_id, bill_id, date, amount, account_code, note)
  values (p_company, pno, dir, pid, inv, bil, d, amt, hold, 'شيك رقم ' || trim(p_doc->>'cheque_no')) returning id into payid;
  insert into public.cheques(company_id, no, direction, party_id, invoice_id, bill_id, cheque_no, bank, amount, issue_date, due_date, payment_id, note)
  values (p_company, public.next_doc_no(p_company, case dir when 'in' then 'CHI' else 'CHO' end), dir, pid, inv, bil, trim(p_doc->>'cheque_no'),
          nullif(trim(p_doc->>'bank'),''), amt, d, due, payid, nullif(trim(p_doc->>'note'),'')) returning id into cid;
  perform public.post_journal(p_company, d, case dir when 'in' then 'شيك وارد ' else 'شيك صادر ' end || trim(p_doc->>'cheque_no') || ' — ' || pno,
    case dir when 'in' then 'receipt' else 'payment' end, payid,
    case dir when 'in' then jsonb_build_array(jsonb_build_object('a','1150','d',amt), jsonb_build_object('a','1200','c',amt))
             else jsonb_build_array(jsonb_build_object('a','2100','d',amt), jsonb_build_object('a','2160','c',amt)) end);
  return cid;
end $$;

-- the bank collected / paid the cheque
create or replace function public.cheque_clear(p_id uuid, p_date date, p_account text) returns void
language plpgsql security definer set search_path = public as $$
declare c public.cheques;
begin
  select * into c from public.cheques where id = p_id for update;
  if not found then raise exception 'الشيك غير موجود'; end if;
  perform public.require_fin(c.company_id, case c.direction when 'in' then 'sales' else 'purch' end);
  if c.status <> 'open' then raise exception 'الشيك ليس قائماً'; end if;
  if p_date is null or p_date > current_date or p_date < c.issue_date then raise exception 'تاريخ الصرف غير صحيح'; end if;
  if not exists(select 1 from public.accounts where company_id = c.company_id and code = p_account and parent_code = '1100' and not is_header) then raise exception 'اختر حساب البنك'; end if;
  perform public.post_journal(c.company_id, p_date, case c.direction when 'in' then 'تحصيل شيك ' else 'صرف شيك ' end || c.cheque_no || ' — ' || c.no, 'cheque', c.id,
    case c.direction when 'in' then jsonb_build_array(jsonb_build_object('a', p_account, 'd', c.amount), jsonb_build_object('a','1150','c', c.amount))
                     else jsonb_build_array(jsonb_build_object('a','2160','d', c.amount), jsonb_build_object('a', p_account, 'c', c.amount)) end);
  update public.cheques set status = 'cleared', bank_account = p_account, closed_on = p_date where id = p_id;
end $$;

-- a customer cheque bounced (before or after it was deposited) / an issued cheque was cancelled before payment:
-- the party owes again (the voucher is removed so the invoice is open again)
create or replace function public.cheque_return(p_id uuid, p_date date, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare c public.cheques; lines jsonb;
begin
  select * into c from public.cheques where id = p_id for update;
  if not found then raise exception 'الشيك غير موجود'; end if;
  perform public.require_fin(c.company_id, case c.direction when 'in' then 'sales' else 'purch' end);
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'اكتب السبب'; end if;
  if p_date is null or p_date > current_date or p_date < c.issue_date then raise exception 'التاريخ غير صحيح'; end if;
  if c.direction = 'in' then
    if c.status not in ('open','cleared') then raise exception 'الشيك مرتجع أو ملغى مسبقاً'; end if;
    lines := jsonb_build_array(jsonb_build_object('a','1200','d', c.amount),
                               jsonb_build_object('a', case c.status when 'open' then '1150' else c.bank_account end, 'c', c.amount));
  else
    if c.status <> 'open' then raise exception 'لا يُلغى إلا شيك لم يُصرف بعد'; end if;
    lines := jsonb_build_array(jsonb_build_object('a','2160','d', c.amount), jsonb_build_object('a','2100','c', c.amount));
  end if;
  perform public.post_journal(c.company_id, p_date, case c.direction when 'in' then 'شيك مرتجع ' else 'إلغاء شيك ' end || c.cheque_no || ' — ' || trim(p_reason), 'cheque', c.id, lines);
  delete from public.payments where id = c.payment_id;
  update public.cheques set status = case c.direction when 'in' then 'bounced' else 'cancelled' end, closed_on = p_date, reason = trim(p_reason), payment_id = null where id = p_id;
end $$;

-- ================= FOREIGN CURRENCIES =================
create table public.currencies (
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null check (code ~ '^[A-Z]{3}$' and code <> 'SAR'),
  name text not null, name_en text,
  rate numeric(14,6) not null check (rate > 0),     -- riyals per one unit
  updated_at timestamptz not null default now(),
  primary key (company_id, code)
);
alter table public.sales_invoices add column currency text, add column fx_rate numeric(14,6), add column fx_total numeric(14,2);
alter table public.purchase_bills add column currency text, add column fx_rate numeric(14,6), add column fx_total numeric(14,2);
alter table public.payments add column currency text, add column fx_amount numeric(14,2), add column fx_rate numeric(14,6);

create or replace function public.currency_save(p_company uuid, p_code text, p_name text, p_name_en text, p_rate numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'coa');
  if upper(trim(coalesce(p_code,''))) !~ '^[A-Z]{3}$' then raise exception 'رمز العملة ثلاثة أحرف إنجليزية (مثل USD)'; end if;
  if upper(trim(p_code)) = 'SAR' then raise exception 'الريال هو العملة الأساسية'; end if;
  if coalesce(p_rate, 0) <= 0 then raise exception 'أدخل سعر صرف أكبر من صفر'; end if;
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'اكتب اسم العملة'; end if;
  insert into public.currencies(company_id, code, name, name_en, rate) values (p_company, upper(trim(p_code)), trim(p_name), nullif(trim(p_name_en),''), p_rate)
  on conflict (company_id, code) do update set name = excluded.name, name_en = excluded.name_en, rate = excluded.rate, updated_at = now();
end $$;

-- convert a document entered in a foreign currency into riyals (prices × rate); returns the doc and the foreign total
create or replace function public.fx_convert(p_company uuid, p_doc jsonb, out doc jsonb, out cur text, out rate numeric, out fxt numeric)
language plpgsql stable security definer set search_path = public as $$
declare l jsonb; ls jsonb := '[]'; a numeric;
begin
  doc := p_doc; cur := upper(nullif(trim(p_doc->>'currency'), '')); rate := null; fxt := null;
  if cur is null or cur = 'SAR' then cur := null; return; end if;
  if not exists(select 1 from public.currencies where company_id = p_company and code = cur) then raise exception 'العملة % غير معرّفة', cur; end if;
  rate := coalesce(nullif(p_doc->>'fx_rate','')::numeric, (select c.rate from public.currencies c where c.company_id = p_company and c.code = cur));
  if rate is null or rate <= 0 then raise exception 'أدخل سعر صرف أكبر من صفر'; end if;
  fxt := 0;
  for l in select * from jsonb_array_elements(p_doc->'lines') loop
    a := round(coalesce((l->>'qty')::numeric, 1) * round((l->>'price')::numeric, 2), 2);
    fxt := fxt + a + round(a * coalesce((l->>'vat')::numeric, 15) / 100, 2);
    ls := ls || jsonb_build_array(l || jsonb_build_object('price', round((l->>'price')::numeric * rate, 2)));
  end loop;
  doc := p_doc || jsonb_build_object('lines', ls);
end $$;

create or replace function public.post_sales_invoice_wh(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare iid uuid; c uuid; f record;
begin
  select * into f from public.fx_convert(p_company, p_doc);
  perform public.wh_use(p_company, p_doc->>'warehouse'); c := public.cc_use(p_company, p_doc->>'cost_center');
  iid := public.post_sales_invoice(p_company, f.doc);
  update public.sales_invoices set cost_center_id = c, currency = f.cur, fx_rate = f.rate, fx_total = f.fxt where id = iid;
  return iid;
end $$;
create or replace function public.post_purchase_bill_wh(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare bid uuid; c uuid; f record;
begin
  select * into f from public.fx_convert(p_company, p_doc);
  perform public.wh_use(p_company, p_doc->>'warehouse'); c := public.cc_use(p_company, p_doc->>'cost_center');
  bid := public.post_purchase_bill(p_company, f.doc);
  update public.purchase_bills set cost_center_id = c, currency = f.cur, fx_rate = f.rate, fx_total = f.fxt where id = bid;
  return bid;
end $$;

-- pay / collect a foreign-currency document: the party is settled at the document rate, the bank at today's rate,
-- the difference is a realised exchange gain (4950) or loss (5950)
create or replace function public.record_payment_fx(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare dir text := p_doc->>'direction'; doc uuid := coalesce(nullif(p_doc->>'invoice',''), nullif(p_doc->>'bill',''))::uuid;
  d date := coalesce(nullif(p_doc->>'date','')::date, current_date); acc text := coalesce(p_doc->>'account','1120');
  fa numeric := round((p_doc->>'fx_amount')::numeric, 2); r numeric := (p_doc->>'fx_rate')::numeric;
  tot numeric; fxt numeric; cur text; ddate date; pid uuid; rem numeric; fxrem numeric; settle numeric; cash numeric; diff numeric; no text; payid uuid; lines jsonb;
begin
  if dir not in ('in','out') then raise exception 'نوع السند غير صالح'; end if;
  perform public.require_fin(p_company, case dir when 'in' then 'sales' else 'purch' end);
  perform public.ensure_fin2_accounts(p_company);
  if dir = 'in' then select total, fx_total, currency, date, party_id into tot, fxt, cur, ddate, pid from public.sales_invoices where id = doc and company_id = p_company and status = 'posted';
  else select total, fx_total, currency, date, party_id into tot, fxt, cur, ddate, pid from public.purchase_bills where id = doc and company_id = p_company and status = 'posted'; end if;
  if tot is null then raise exception 'المستند غير موجود أو ملغى'; end if;
  if cur is null then raise exception 'المستند بالريال — استخدم سند القبض أو الصرف العادي'; end if;
  if coalesce(fa, 0) <= 0 then raise exception 'أدخل المبلغ بالعملة'; end if;
  if coalesce(r, 0) <= 0 then raise exception 'أدخل سعر صرف أكبر من صفر'; end if;
  if d > current_date or d < ddate then raise exception 'تاريخ السند غير صحيح'; end if;
  if acc not in (select code from public.accounts where company_id = p_company and parent_code = '1100' and not is_header) then raise exception 'اختر الصندوق أو البنك'; end if;
  rem := tot - public.paid_on(doc);
  fxrem := round(fxt * rem / tot, 2);
  if fa > fxrem + 0.004 then raise exception 'المبلغ أكبر من المتبقي (% %)', fxrem, cur; end if;
  settle := case when fa >= fxrem - 0.004 then rem else round(fa * tot / fxt, 2) end;
  cash := round(fa * r, 2); diff := cash - settle;
  if dir = 'out' and cash > public.account_balance(p_company, acc, d) then raise exception 'الرصيد المتاح %', public.account_balance(p_company, acc, d); end if;
  no := public.next_doc_no(p_company, case dir when 'in' then 'RV' else 'PV' end);
  insert into public.payments(company_id, no, direction, party_id, invoice_id, bill_id, date, amount, account_code, note, currency, fx_amount, fx_rate)
  values (p_company, no, dir, pid, case dir when 'in' then doc end, case dir when 'out' then doc end, d, settle, acc, p_doc->>'note', cur, fa, r) returning id into payid;
  if dir = 'in' then
    lines := jsonb_build_array(jsonb_build_object('a', acc, 'd', cash), jsonb_build_object('a','1200','c', settle));
    if diff > 0 then lines := lines || jsonb_build_array(jsonb_build_object('a','4950','c', diff));
    elsif diff < 0 then lines := lines || jsonb_build_array(jsonb_build_object('a','5950','d', -diff)); end if;
  else
    lines := jsonb_build_array(jsonb_build_object('a','2100','d', settle), jsonb_build_object('a', acc, 'c', cash));
    if diff > 0 then lines := lines || jsonb_build_array(jsonb_build_object('a','5950','d', diff));
    elsif diff < 0 then lines := lines || jsonb_build_array(jsonb_build_object('a','4950','c', -diff)); end if;
  end if;
  perform public.post_journal(p_company, d, case dir when 'in' then 'سند قبض ' else 'سند صرف ' end || no || ' — ' || fa || ' ' || cur || ' × ' || r,
    case dir when 'in' then 'receipt' else 'payment' end, payid, lines);
  return payid;
end $$;

-- ================= OPENING BALANCES =================
create table public.opening_batches (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  date date not null,
  entry_id uuid references public.journal_entries(id),
  status text not null default 'posted' check (status in ('posted','undone')),
  summary jsonb,
  created_by uuid default auth.uid(), created_at timestamptz not null default now()
);
create unique index opening_one_posted on public.opening_batches(company_id) where status = 'posted';
alter table public.sales_invoices add column is_opening boolean not null default false;
alter table public.purchase_bills add column is_opening boolean not null default false;

-- opening invoices / bills carry no lines and cannot be voided like ordinary documents
create or replace function public.opening_doc_guard() returns trigger language plpgsql as $$
begin
  if old.is_opening and new.status = 'void' and coalesce(current_setting('waad.opening_undo', true), '') <> '1' then
    raise exception 'هذا رصيد افتتاحي — لا يُلغى كفاتورة (استخدم «إلغاء الأرصدة الافتتاحية» أو قيداً يدوياً)';
  end if;
  return new;
end $$;
create trigger si_opening_guard before update on public.sales_invoices for each row execute function public.opening_doc_guard();
create trigger pb_opening_guard before update on public.purchase_bills for each row execute function public.opening_doc_guard();

-- rows: [{t:'acc', a, d, c} | {t:'cust'|'supp', name, amount, due, ref} | {t:'item', code, qty, cost, expiry}]
-- the difference (if any) goes to 3900 only when p_to_equity is true
create or replace function public.opening_post(p_company uuid, p_date date, p_rows jsonb, p_to_equity boolean default false) returns uuid
language plpgsql security definer set search_path = public as $$
declare bid uuid := gen_random_uuid(); r jsonb; jl jsonb := '[]'; ar numeric := 0; ap numeric := 0; inv numeric := 0; dsum numeric := 0; csum numeric := 0;
  pid uuid; it public.items; q numeric; v numeric; w uuid; acc public.accounts; amt numeric; diff numeric; n_acc int := 0; n_c int := 0; n_s int := 0; n_i int := 0; eid uuid;
  first_entry date;
begin
  perform public.require_role(p_company, array['owner','admin','finance']);
  perform public.ensure_fin2_accounts(p_company);
  if p_date is null or p_date > current_date then raise exception 'تاريخ الأرصدة الافتتاحية لا يكون في المستقبل'; end if;
  if exists(select 1 from public.opening_batches where company_id = p_company and status = 'posted') then raise exception 'الأرصدة الافتتاحية مُدخلة مسبقاً — ألغِها أولاً لإعادة الاستيراد'; end if;
  select min(date) into first_entry from public.journal_entries j where j.company_id = p_company and j.source <> 'opening'
    and not exists(select 1 from public.opening_batches ob where ob.id = j.source_id);
  if first_entry is not null and p_date >= first_entry then raise exception 'تاريخ الأرصدة الافتتاحية يجب أن يسبق أول قيد في الدفاتر (%)', first_entry; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'الملف فارغ'; end if;
  w := public.wh_use(p_company, null);
  for r in select * from jsonb_array_elements(p_rows) loop
    case r->>'t'
    when 'acc' then
      select * into acc from public.accounts where company_id = p_company and code = trim(r->>'a');
      if not found or acc.is_header then raise exception 'الحساب % غير موجود أو رئيسي', r->>'a'; end if;
      if acc.code in ('1200','2100','1300') then raise exception 'رصيد الحساب % يُدخل تفصيلاً (عملاء/موردين/أصناف) لا كرقم واحد', acc.code; end if;
      if acc.type in ('rev','exp') then raise exception 'الحساب % حساب إيرادات أو مصروفات — الأرصدة الافتتاحية للميزانية فقط', acc.code; end if;
      if coalesce((r->>'d')::numeric,0) < 0 or coalesce((r->>'c')::numeric,0) < 0 then raise exception 'مبالغ سالبة في الحساب %', acc.code; end if;
      jl := jl || jsonb_build_array(jsonb_build_object('a', acc.code, 'd', round(coalesce((r->>'d')::numeric,0),2), 'c', round(coalesce((r->>'c')::numeric,0),2)));
      dsum := dsum + round(coalesce((r->>'d')::numeric,0),2); csum := csum + round(coalesce((r->>'c')::numeric,0),2); n_acc := n_acc + 1;
    when 'cust', 'supp' then
      amt := round((r->>'amount')::numeric, 2);
      if coalesce(amt, 0) <= 0 then raise exception 'رصيد «%» يجب أن يكون أكبر من صفر', r->>'name'; end if;
      if length(trim(coalesce(r->>'name',''))) < 2 then raise exception 'اسم الطرف مطلوب'; end if;
      select id into pid from public.parties where company_id = p_company and kind = case r->>'t' when 'cust' then 'customer' else 'supplier' end and name = trim(r->>'name') limit 1;
      if pid is null then
        insert into public.parties(company_id, kind, name) values (p_company, case r->>'t' when 'cust' then 'customer' else 'supplier' end, trim(r->>'name')) returning id into pid;
      end if;
      if r->>'t' = 'cust' then
        insert into public.sales_invoices(company_id, no, date, due_date, party_id, subtotal, vat, total, note, is_opening)
        values (p_company, public.next_doc_no(p_company, 'OBC'), p_date, coalesce(nullif(r->>'due','')::date, p_date), pid, amt, 0, amt,
                'رصيد افتتاحي' || coalesce(' — ' || nullif(trim(r->>'ref'),''), ''), true);
        ar := ar + amt; n_c := n_c + 1;
      else
        insert into public.purchase_bills(company_id, no, date, due_date, party_id, subtotal, vat, total, note, is_opening)
        values (p_company, public.next_doc_no(p_company, 'OBS'), p_date, coalesce(nullif(r->>'due','')::date, p_date), pid, amt, 0, amt,
                'رصيد افتتاحي' || coalesce(' — ' || nullif(trim(r->>'ref'),''), ''), true);
        ap := ap + amt; n_s := n_s + 1;
      end if;
    when 'item' then
      select * into it from public.items where company_id = p_company and code = trim(r->>'code') and type = 'stock';
      if not found then raise exception 'الصنف % غير موجود أو ليس مخزنياً', r->>'code'; end if;
      q := (r->>'qty')::numeric; v := round(q * (r->>'cost')::numeric, 2);
      if coalesce(q, 0) <= 0 or coalesce((r->>'cost')::numeric, -1) < 0 then raise exception 'كمية أو تكلفة الصنف % غير صحيحة', it.code; end if;
      if it.track_expiry and nullif(r->>'expiry','') is null then raise exception 'أدخل تاريخ صلاحية الصنف %', it.code; end if;
      insert into public.stock_moves(company_id, item_id, warehouse_id, date, qty, value, source, source_id, expiry, note)
      values (p_company, it.id, w, p_date, q, v, 'adjust', bid, nullif(r->>'expiry','')::date, 'رصيد افتتاحي');
      inv := inv + v; n_i := n_i + 1;
    else raise exception 'نوع سطر غير معروف: %', r->>'t';
    end case;
  end loop;
  if ar > 0 then jl := jl || jsonb_build_array(jsonb_build_object('a','1200','d', ar)); dsum := dsum + ar; end if;
  if ap > 0 then jl := jl || jsonb_build_array(jsonb_build_object('a','2100','c', ap)); csum := csum + ap; end if;
  if inv > 0 then jl := jl || jsonb_build_array(jsonb_build_object('a','1300','d', inv)); dsum := dsum + inv; end if;
  diff := dsum - csum;
  if abs(diff) >= 0.005 then
    if not p_to_equity then raise exception 'الأرصدة غير متوازنة: المدين % والدائن % (الفرق %)', dsum, csum, diff; end if;
    jl := jl || jsonb_build_array(case when diff > 0 then jsonb_build_object('a','3900','c', diff) else jsonb_build_object('a','3900','d', -diff) end);
  end if;
  eid := public.post_journal(p_company, p_date, 'الأرصدة الافتتاحية', 'opening', bid, jl);
  insert into public.opening_batches(id, company_id, date, entry_id, summary)
  values (bid, p_company, p_date, eid, jsonb_build_object('accounts', n_acc, 'customers', n_c, 'suppliers', n_s, 'items', n_i, 'ar', ar, 'ap', ap, 'stock', inv, 'debit', dsum, 'credit', csum, 'to_equity', diff));
  return bid;
end $$;

-- undo is allowed only while nothing else has been recorded (everything is reversed, nothing is deleted)
create or replace function public.opening_undo(p_company uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b public.opening_batches; m record;
begin
  perform public.require_role(p_company, array['owner','admin','finance']);
  select * into b from public.opening_batches where company_id = p_company and status = 'posted' for update;
  if not found then raise exception 'لا توجد أرصدة افتتاحية'; end if;
  if exists(select 1 from public.journal_entries j where j.company_id = p_company and j.source <> 'opening' and not exists(select 1 from public.opening_batches ob where ob.id = j.source_id)) then
    raise exception 'سُجّلت عمليات بعد الأرصدة الافتتاحية — صحّحها بقيد يدوي بدل الإلغاء'; end if;
  perform public.post_journal(p_company, b.date, 'إلغاء الأرصدة الافتتاحية', 'reversal', b.id,
    (select jsonb_agg(jsonb_build_object('a', account_code, 'd', credit, 'c', debit)) from public.journal_lines where entry_id = b.entry_id), b.entry_id);
  for m in select * from public.stock_moves where source_id = b.id and qty > 0 loop
    insert into public.stock_moves(company_id, item_id, warehouse_id, date, qty, value, source, source_id, note)
    values (p_company, m.item_id, m.warehouse_id, b.date, -m.qty, -m.value, 'adjust', b.id, 'إلغاء رصيد افتتاحي');
  end loop;
  perform set_config('waad.opening_undo', '1', true);
  update public.sales_invoices set status = 'void' where company_id = p_company and is_opening and status = 'posted';
  update public.purchase_bills set status = 'void' where company_id = p_company and is_opening and status = 'posted';
  perform set_config('waad.opening_undo', '', true);
  update public.opening_batches set status = 'undone' where id = b.id;
end $$;

-- ================= YEAR-END CLOSING =================
create table public.fiscal_closings (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  year_start date not null, year_end date not null,
  entry_id uuid references public.journal_entries(id),
  net_profit numeric(14,2) not null,
  status text not null default 'closed' check (status in ('closed','reopened')),
  reason text, closed_by uuid default auth.uid(), at timestamptz not null default now()
);
create unique index fiscal_closings_one on public.fiscal_closings(company_id, year_end) where status = 'closed';

-- moves the year's revenue and expenses into retained earnings (3200) and locks the books through the year end
create or replace function public.year_close(p_company uuid, p_year_end date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare last date; ys date; jl jsonb; net numeric; eid uuid; lk date;
begin
  perform public.require_role(p_company, array['owner','admin','finance']);
  if p_year_end is null or p_year_end >= current_date then raise exception 'نهاية السنة المالية يجب أن تكون قبل اليوم'; end if;
  select max(year_end) into last from public.fiscal_closings where company_id = p_company and status = 'closed';
  if last is not null and p_year_end <= last then raise exception 'السنة المنتهية في % مقفلة مسبقاً', last; end if;
  ys := coalesce(last + 1, (select min(date) from public.journal_entries where company_id = p_company), p_year_end);
  if last is not null and p_year_end > (last + interval '1 year')::date then raise exception 'أقفل السنوات بالترتيب — السنة التالية تنتهي في %', (last + interval '1 year')::date; end if;
  select jsonb_agg(jsonb_build_object('a', x.code, 'd', greatest(x.bal, 0), 'c', greatest(-x.bal, 0))), coalesce(sum(x.bal), 0) into jl, net
  from (select l.account_code code, sum(l.credit - l.debit) bal from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
          join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
        where l.company_id = p_company and a.type in ('rev','exp') and e.date between ys and p_year_end and e.source <> 'closing'
        group by l.account_code having sum(l.credit - l.debit) <> 0) x;
  if jl is null then raise exception 'لا توجد إيرادات أو مصروفات في هذه السنة'; end if;
  jl := jl || jsonb_build_array(case when net >= 0 then jsonb_build_object('a','3200','c', net) else jsonb_build_object('a','3200','d', -net) end);
  perform set_config('waad.closing', '1', true);
  eid := public.post_journal(p_company, p_year_end, 'إقفال السنة المالية ' || ys || ' — ' || p_year_end, 'closing', null, jl);
  perform set_config('waad.closing', '', true);
  insert into public.fiscal_closings(company_id, year_start, year_end, entry_id, net_profit) values (p_company, ys, p_year_end, eid, net);
  select books_closed_through into lk from public.companies where id = p_company;
  if lk is null or lk < p_year_end then
    update public.companies set books_closed_through = p_year_end where id = p_company;
    insert into public.period_locks(company_id, action, through, previous, reason) values (p_company, 'close', p_year_end, lk, 'إقفال السنة المالية');
  end if;
  return jsonb_build_object('year_start', ys, 'year_end', p_year_end, 'net_profit', net);
end $$;

-- owner only: reverses the latest closing entry (the period lock stays; reopen the period separately to post corrections)
create or replace function public.year_reopen(p_company uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare f public.fiscal_closings;
begin
  perform public.require_role(p_company, array['owner']);
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'اكتب سبب إعادة فتح السنة'; end if;
  select * into f from public.fiscal_closings where company_id = p_company and status = 'closed' order by year_end desc limit 1 for update;
  if not found then raise exception 'لا توجد سنة مقفلة'; end if;
  perform set_config('waad.closing', '1', true);
  perform public.post_journal(p_company, f.year_end, 'إعادة فتح السنة المالية — ' || trim(p_reason), 'reversal', null,
    (select jsonb_agg(jsonb_build_object('a', account_code, 'd', credit, 'c', debit)) from public.journal_lines where entry_id = f.entry_id), f.entry_id);
  perform set_config('waad.closing', '', true);
  update public.fiscal_closings set status = 'reopened', reason = trim(p_reason) where id = f.id;
end $$;

-- reports ignore the closing entry and its reversal (so a closed year still shows its profit)
create or replace function public.is_closing_entry(p_entry uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.journal_entries e where e.id = p_entry and (e.source = 'closing'
    or (e.source = 'reversal' and exists(select 1 from public.journal_entries o where o.id = e.reverses and o.source = 'closing'))))
$$;

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
    where l.company_id = p_company and e.date between p_from and p_to and a.type in ('rev','exp') and not public.is_closing_entry(e.id)
    group by a.code, a.name, a.type having sum(l.credit - l.debit) <> 0)
  select case when b.type = 'rev' then 'revenue' when b.code = '5100' then 'cogs' else 'expense' end, b.code, b.name,
         case when b.type = 'rev' then b.cr else -b.cr end from b
  union all
  select 'net_profit', null, 'صافي الربح', coalesce(sum(b.cr),0) from b
  order by 1 desc, 2;
end $$;

create or replace function public.cc_report(p_company uuid, p_from date, p_to date)
returns table(cost_center_id uuid, revenue numeric, expense numeric, profit numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'reports');
  return query
  select l.cost_center_id, coalesce(sum(l.credit - l.debit) filter (where a.type = 'rev'), 0)::numeric, coalesce(sum(l.debit - l.credit) filter (where a.type = 'exp'), 0)::numeric,
         (coalesce(sum(l.credit - l.debit) filter (where a.type = 'rev'), 0) - coalesce(sum(l.debit - l.credit) filter (where a.type = 'exp'), 0))::numeric
  from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
  where l.company_id = p_company and e.date between p_from and p_to and a.type in ('rev','exp') and not public.is_closing_entry(e.id)
  group by l.cost_center_id order by l.cost_center_id nulls last;
end $$;

create or replace function public.budget_report(p_company uuid, p_year int, p_cc uuid, p_to_month int)
returns table(code text, name text, type text, budget numeric, actual numeric, variance numeric)
language plpgsql stable security definer set search_path = public as $$
declare tm int := least(greatest(coalesce(p_to_month, 12), 1), 12);
begin
  perform public.require_fin(p_company, 'reports');
  return query
  with b as (select bu.account_code, (select sum(v) from unnest(bu.months[1:tm]) v) amt from public.budgets bu
             where bu.company_id = p_company and bu.year = p_year and bu.cost_center_id is not distinct from p_cc),
       ac as (select l.account_code, sum(case when a.type = 'rev' then l.credit - l.debit else l.debit - l.credit end) amt
              from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
              where l.company_id = p_company and a.type in ('rev','exp') and e.date between make_date(p_year, 1, 1) and (make_date(p_year, tm, 1) + interval '1 month' - interval '1 day')::date
                and (p_cc is null or l.cost_center_id = p_cc) and not public.is_closing_entry(e.id) group by l.account_code)
  select a.code, a.name, a.type, coalesce(b.amt, 0)::numeric, coalesce(ac.amt, 0)::numeric,
         (case when a.type = 'rev' then coalesce(ac.amt, 0) - coalesce(b.amt, 0) else coalesce(b.amt, 0) - coalesce(ac.amt, 0) end)::numeric
  from public.accounts a left join b on b.account_code = a.code left join ac on ac.account_code = a.code
  where a.company_id = p_company and a.type in ('rev','exp') and not a.is_header and (b.amt is not null or ac.amt is not null)
  order by a.code;
end $$;

create or replace function public.an_pl(p_company uuid, p_from date, p_to date)
returns table(revenue numeric, expenses numeric, cogs numeric, payroll numeric)
language sql stable security definer set search_path = public as $$
  select coalesce(sum(l.credit - l.debit) filter (where a.type = 'rev'), 0),
         coalesce(sum(l.debit - l.credit) filter (where a.type = 'exp'), 0),
         coalesce(sum(l.debit - l.credit) filter (where a.code = '5100'), 0),
         coalesce(sum(l.debit - l.credit) filter (where a.code in ('5200','5210')), 0)
    from public.journal_lines l join public.journal_entries j on j.id = l.entry_id
    join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
   where l.company_id = p_company and j.date between p_from and p_to and not public.is_closing_entry(j.id)
$$;

-- analytics: the expense breakdown ignores the closing entry too
create or replace function public.company_analytics(p_company uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r jsonb := jsonb_build_object('from', p_from, 'to', p_to);
  len int; pf date; pt date; cur record; prv record; me uuid := public.my_employee(p_company);
  exec boolean; fin boolean; hr boolean; ms date; hc_now int; hc_prev int;
begin
  if not public.is_member(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception 'حدد الفترة'; end if;
  if p_to - p_from > 731 then raise exception 'الفترة لا تزيد على سنتين'; end if;
  len := p_to - p_from + 1; pt := p_from - 1; pf := pt - len + 1;
  r := r || jsonb_build_object('prev_from', pf, 'prev_to', pt);
  exec := public.has_role(p_company, array['owner','admin','finance']);
  fin := public.fin_can(p_company, 'reports');
  hr := public.has_role(p_company, array['owner','admin','hr']);

  -- ---------- executive ----------
  if exec or fin then
    select * into cur from public.an_pl(p_company, p_from, p_to);
    select * into prv from public.an_pl(p_company, pf, pt);
    select count(*) into hc_now from public.employees where company_id = p_company and hire_date <= p_to and (end_date is null or end_date >= p_to);
    r := r || jsonb_build_object('exec', jsonb_build_object(
      'revenue', cur.revenue, 'revenue_prev', prv.revenue, 'expenses', cur.expenses, 'expenses_prev', prv.expenses,
      'profit', cur.revenue - cur.expenses, 'profit_prev', prv.revenue - prv.expenses,
      'margin', case when cur.revenue > 0 then round((cur.revenue - cur.expenses) / cur.revenue * 100, 1) end,
      'gross_margin', case when cur.revenue > 0 then round((cur.revenue - cur.cogs) / cur.revenue * 100, 1) end,
      'payroll', cur.payroll, 'payroll_prev', prv.payroll,
      'payroll_ratio', case when cur.revenue > 0 then round(cur.payroll / cur.revenue * 100, 1) end,
      'cash', public.an_balance(p_company, array['1110','1120'], p_to), 'cash_prev', public.an_balance(p_company, array['1110','1120'], pt),
      'ar', public.an_balance(p_company, array['1200'], p_to), 'ap', -public.an_balance(p_company, array['2100'], p_to),
      'inventory', public.an_balance(p_company, array['1300'], p_to),
      'headcount', hc_now, 'rev_per_emp', case when hc_now > 0 then round(cur.revenue / hc_now, 2) end,
      'months', coalesce((select jsonb_agg(jsonb_build_object('m', to_char(m, 'YYYY-MM'), 'revenue', p.revenue, 'expenses', p.expenses, 'profit', p.revenue - p.expenses) order by m)
          from generate_series(date_trunc('month', p_from), date_trunc('month', p_to), interval '1 month') m
          cross join lateral public.an_pl(p_company, greatest(m::date, p_from), least((m + interval '1 month - 1 day')::date, p_to)) p), '[]')));
  end if;

  -- ---------- finance ----------
  if fin then
    r := r || jsonb_build_object('finance', jsonb_build_object(
      'expense_accounts', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'name', name, 'name_en', name_en, 'amount', amt) order by amt desc) from (
          select a.code, a.name, a.name_en, sum(l.debit - l.credit) amt from public.journal_lines l join public.journal_entries j on j.id = l.entry_id
            join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
           where l.company_id = p_company and a.type = 'exp' and j.date between p_from and p_to and not public.is_closing_entry(j.id) group by 1, 2, 3 having sum(l.debit - l.credit) <> 0) q), '[]'),
      'cash_flow', coalesce((select jsonb_agg(jsonb_build_object('m', m, 'in', i, 'out', o) order by m) from (
          select to_char(j.date, 'YYYY-MM') m, sum(l.debit) i, sum(l.credit) o from public.journal_lines l join public.journal_entries j on j.id = l.entry_id
           where l.company_id = p_company and l.account_code in ('1110','1120') and j.date between p_from and p_to group by 1) q), '[]'),
      'ar_aging', (select jsonb_build_object('d30', coalesce(sum(o) filter (where age <= 30), 0), 'd60', coalesce(sum(o) filter (where age between 31 and 60), 0),
                    'd90', coalesce(sum(o) filter (where age between 61 and 90), 0), 'over', coalesce(sum(o) filter (where age > 90), 0))
          from (select public.an_open(s.id, s.total) o, p_to - s.due_date age from public.sales_invoices s where s.company_id = p_company and s.status = 'posted' and s.date <= p_to) q where o > 0),
      'ap_aging', (select jsonb_build_object('d30', coalesce(sum(o) filter (where age <= 30), 0), 'd60', coalesce(sum(o) filter (where age between 31 and 60), 0),
                    'd90', coalesce(sum(o) filter (where age between 61 and 90), 0), 'over', coalesce(sum(o) filter (where age > 90), 0))
          from (select public.an_open(b.id, b.total) o, p_to - b.due_date age from public.purchase_bills b where b.company_id = p_company and b.status = 'posted' and b.date <= p_to) q where o > 0),
      'vat', (select jsonb_build_object('output', coalesce(sum(l.credit - l.debit) filter (where l.account_code = '2200'), 0), 'input', coalesce(sum(l.debit - l.credit) filter (where l.account_code = '1400'), 0))
          from public.journal_lines l join public.journal_entries j on j.id = l.entry_id where l.company_id = p_company and j.date between p_from and p_to)));
  end if;

  -- ---------- sales ----------
  if public.fin_can(p_company, 'sales') then
    r := r || jsonb_build_object('sales', jsonb_build_object(
      'total', (select coalesce(sum(subtotal), 0) from public.sales_invoices where company_id = p_company and status = 'posted' and date between p_from and p_to),
      'total_prev', (select coalesce(sum(subtotal), 0) from public.sales_invoices where company_id = p_company and status = 'posted' and date between pf and pt),
      'count', (select count(*) from public.sales_invoices where company_id = p_company and status = 'posted' and date between p_from and p_to),
      'returns', (select coalesce(sum(subtotal), 0) from public.credit_notes where company_id = p_company and kind = 'sales' and date between p_from and p_to),
      'collected', (select coalesce(sum(amount), 0) from public.payments where company_id = p_company and direction = 'in' and date between p_from and p_to),
      'months', coalesce((select jsonb_agg(jsonb_build_object('m', m, 'total', t, 'n', n) order by m) from (select to_char(date, 'YYYY-MM') m, sum(subtotal) t, count(*) n
          from public.sales_invoices where company_id = p_company and status = 'posted' and date between p_from and p_to group by 1) q), '[]'),
      'customers', coalesce((select jsonb_agg(jsonb_build_object('name', p.name, 'name_en', p.name_en, 'total', q.t, 'n', q.n) order by q.t desc) from (
          select party_id, sum(subtotal) t, count(*) n from public.sales_invoices where company_id = p_company and status = 'posted' and date between p_from and p_to
           group by 1 order by 2 desc limit 10) q join public.parties p on p.id = q.party_id), '[]'),
      'items', coalesce((select jsonb_agg(jsonb_build_object('name', i.name, 'name_en', i.name_en, 'qty', q.qty, 'total', q.t) order by q.t desc) from (
          select l.item_id, sum(l.qty) qty, sum(l.qty * l.unit_price) t from public.sales_invoice_lines l join public.sales_invoices s on s.id = l.invoice_id
           where s.company_id = p_company and s.status = 'posted' and s.date between p_from and p_to group by 1 order by 3 desc limit 10) q join public.items i on i.id = q.item_id), '[]')));
  end if;

  -- ---------- purchasing and stock ----------
  if public.fin_can(p_company, 'purch') or public.fin_can(p_company, 'stock') then
    r := r || jsonb_build_object('supply', jsonb_build_object(
      'purchases', (select coalesce(sum(subtotal), 0) from public.purchase_bills where company_id = p_company and status = 'posted' and date between p_from and p_to),
      'purchases_prev', (select coalesce(sum(subtotal), 0) from public.purchase_bills where company_id = p_company and status = 'posted' and date between pf and pt),
      'paid', (select coalesce(sum(amount), 0) from public.payments where company_id = p_company and direction = 'out' and date between p_from and p_to),
      'months', coalesce((select jsonb_agg(jsonb_build_object('m', m, 'total', t) order by m) from (select to_char(date, 'YYYY-MM') m, sum(subtotal) t
          from public.purchase_bills where company_id = p_company and status = 'posted' and date between p_from and p_to group by 1) q), '[]'),
      'suppliers', coalesce((select jsonb_agg(jsonb_build_object('name', p.name, 'name_en', p.name_en, 'total', q.t, 'n', q.n) order by q.t desc) from (
          select party_id, sum(subtotal) t, count(*) n from public.purchase_bills where company_id = p_company and status = 'posted' and date between p_from and p_to
           group by 1 order by 2 desc limit 10) q join public.parties p on p.id = q.party_id), '[]'),
      'stock_value', (select coalesce(sum(value), 0) from public.stock_moves where company_id = p_company and date <= p_to),
      'low_stock', coalesce((select jsonb_agg(jsonb_build_object('code', i.code, 'name', i.name, 'name_en', i.name_en, 'qty', q.qty, 'reorder', i.reorder_level) order by q.qty) from public.items i
          cross join lateral (select coalesce(sum(m.qty), 0) qty from public.stock_moves m where m.item_id = i.id) q
         where i.company_id = p_company and i.type = 'stock' and i.reorder_level > 0 and q.qty <= i.reorder_level), '[]'),
      'slow', coalesce((select jsonb_agg(jsonb_build_object('code', i.code, 'name', i.name, 'name_en', i.name_en, 'qty', q.qty, 'value', q.v) order by q.v desc) from public.items i
          cross join lateral (select coalesce(sum(m.qty), 0) qty, coalesce(sum(m.value), 0) v from public.stock_moves m where m.item_id = i.id) q
         where i.company_id = p_company and i.type = 'stock' and q.qty > 0
           and not exists(select 1 from public.stock_moves m where m.item_id = i.id and m.source = 'sale' and m.date between p_from and p_to)), '[]')));
  end if;

  -- ---------- HR ----------
  if hr or exec then
    select count(*) into hc_prev from public.employees where company_id = p_company and hire_date <= pt and (end_date is null or end_date >= pt);
    select count(*) into hc_now from public.employees where company_id = p_company and hire_date <= p_to and (end_date is null or end_date >= p_to);
    r := r || jsonb_build_object('hr', jsonb_build_object(
      'headcount', hc_now, 'headcount_start', hc_prev,
      'joiners', (select count(*) from public.employees where company_id = p_company and hire_date between p_from and p_to),
      'leavers', (select count(*) from public.employees where company_id = p_company and end_date between p_from and p_to),
      'leavers_by_reason', coalesce((select jsonb_object_agg(coalesce(end_reason, 'other'), n) from (select end_reason, count(*) n from public.employees
          where company_id = p_company and end_date between p_from and p_to group by 1) q), '{}'),
      'turnover', case when hc_now + hc_prev > 0 then round((select count(*) from public.employees where company_id = p_company and end_date between p_from and p_to)::numeric
          / ((hc_now + hc_prev) / 2.0) * 100, 1) else 0 end,
      'saudi', (select count(*) from public.employees where company_id = p_company and is_saudi and hire_date <= p_to and (end_date is null or end_date >= p_to)),
      'female', (select count(*) from public.employees where company_id = p_company and gender = 'f' and hire_date <= p_to and (end_date is null or end_date >= p_to)),
      'tenure', (select round(avg((p_to - hire_date) / 365.0), 1) from public.employees where company_id = p_company and hire_date <= p_to and (end_date is null or end_date >= p_to)),
      'leave_days', coalesce((select jsonb_object_agg(sub, d) from (select q.sub, sum(greatest(0, least(q.to_date, p_to) - greatest(q.from_date, p_from) + 1)) d from public.requests q
          where q.company_id = p_company and q.kind = 'leave' and q.status = 'approved' and q.from_date <= p_to and q.to_date >= p_from group by 1) q), '{}'),
      'absent_days', (select coalesce(sum(l.att_absent_days + l.absence_days), 0) from public.payroll_lines l join public.payroll_runs pr on pr.id = l.run_id
          where pr.company_id = p_company and make_date(pr.year, pr.month, 1) between date_trunc('month', p_from) and p_to),
      'late_hours', (select round(coalesce(sum(late_min), 0) / 60.0, 1) from public.attendance where company_id = p_company and day between p_from and p_to),
      'ot_hours', (select round(coalesce(sum(ot_min), 0) / 60.0, 1) from public.attendance where company_id = p_company and day between p_from and p_to)
          + (select coalesce(sum(l.overtime_hours), 0) from public.payroll_lines l join public.payroll_runs pr on pr.id = l.run_id
              where pr.company_id = p_company and make_date(pr.year, pr.month, 1) between date_trunc('month', p_from) and p_to),
      'payroll', (select jsonb_build_object('gross', coalesce(sum(l.gross + l.arrears + l.overtime + l.bonus), 0), 'net', coalesce(sum(l.net), 0),
                    'employer_gosi', coalesce(sum(l.employer_gosi), 0), 'overtime', coalesce(sum(l.overtime), 0), 'deductions', coalesce(sum(l.gross + l.arrears + l.overtime + l.bonus - l.net), 0))
          from public.payroll_lines l join public.payroll_runs pr on pr.id = l.run_id
         where pr.company_id = p_company and make_date(pr.year, pr.month, 1) between date_trunc('month', p_from) and p_to)));
    -- departments
    r := r || jsonb_build_object('departments', coalesce((select jsonb_agg(x order by x->>'name') from (
      select jsonb_build_object('name', coalesce(d.name, '—'), 'name_en', d.name_en,
        'headcount', count(*) filter (where e.hire_date <= p_to and (e.end_date is null or e.end_date >= p_to)),
        'saudi', count(*) filter (where e.is_saudi and e.hire_date <= p_to and (e.end_date is null or e.end_date >= p_to)),
        'leavers', count(*) filter (where e.end_date between p_from and p_to),
        'avg_wage', round(avg(e.basic + e.housing + e.transport) filter (where e.hire_date <= p_to and (e.end_date is null or e.end_date >= p_to)), 2),
        'cost', coalesce(sum((select sum(l.gross + l.arrears + l.overtime + l.bonus + l.employer_gosi) from public.payroll_lines l join public.payroll_runs pr on pr.id = l.run_id
              where l.employee_id = e.id and make_date(pr.year, pr.month, 1) between date_trunc('month', p_from) and p_to)), 0),
        'absent_days', coalesce(sum((select sum(l.att_absent_days + l.absence_days) from public.payroll_lines l join public.payroll_runs pr on pr.id = l.run_id
              where l.employee_id = e.id and make_date(pr.year, pr.month, 1) between date_trunc('month', p_from) and p_to)), 0),
        'late_hours', round(coalesce(sum((select sum(a.late_min) from public.attendance a where a.employee_id = e.id and a.day between p_from and p_to)), 0) / 60.0, 1),
        'ot_hours', round(coalesce(sum((select sum(a.ot_min) from public.attendance a where a.employee_id = e.id and a.day between p_from and p_to)), 0) / 60.0, 1),
        'leave_days', coalesce(sum((select sum(greatest(0, least(q.to_date, p_to) - greatest(q.from_date, p_from) + 1)) from public.requests q
              where q.employee_id = e.id and q.kind = 'leave' and q.status = 'approved' and q.from_date <= p_to and q.to_date >= p_from)), 0)) x
      from public.employees e left join public.departments d on d.id = e.department_id
     where e.company_id = p_company and e.hire_date <= p_to and (e.end_date is null or e.end_date >= p_from)
     group by d.id, d.name, d.name_en) q), '[]'));
  end if;

  -- ---------- a manager's own team ----------
  if me is not null and exists(select 1 from public.employees where company_id = p_company and manager_id = me) then
    r := r || jsonb_build_object('team', coalesce((select jsonb_agg(jsonb_build_object('name', e.full_name, 'name_en', e.full_name_en,
        'present', (select count(*) from public.attendance a where a.employee_id = e.id and a.day between p_from and p_to),
        'late_hours', (select round(coalesce(sum(a.late_min), 0) / 60.0, 1) from public.attendance a where a.employee_id = e.id and a.day between p_from and p_to),
        'ot_hours', (select round(coalesce(sum(a.ot_min), 0) / 60.0, 1) from public.attendance a where a.employee_id = e.id and a.day between p_from and p_to),
        'leave_days', (select coalesce(sum(greatest(0, least(q.to_date, p_to) - greatest(q.from_date, p_from) + 1)), 0) from public.requests q
            where q.employee_id = e.id and q.kind = 'leave' and q.status = 'approved' and q.from_date <= p_to and q.to_date >= p_from),
        'pending', (select count(*) from public.requests q where q.employee_id = e.id and q.status = 'pending')) order by e.full_name)
      from public.employees e where e.company_id = p_company and e.manager_id = me and (e.end_date is null or e.end_date >= p_from)), '[]'));
  end if;
  return r;
end $$;

-- ================= PETTY CASH =================
create table public.petty_funds (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id),
  account_code text not null,
  ceiling numeric(14,2) not null check (ceiling > 0),
  status text not null default 'active' check (status in ('active','closed')),
  opened_on date not null, closed_on date, note text,
  created_at timestamptz not null default now(),
  foreign key (company_id, account_code) references public.accounts(company_id, code)
);
create unique index petty_one_active on public.petty_funds(company_id, employee_id) where status = 'active';

create table public.petty_claims (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  fund_id uuid not null references public.petty_funds(id),
  no text not null,
  date date not null,
  lines jsonb not null,                 -- [{a, desc, amount, vat, ref, vat_no}]
  amount numeric(14,2) not null, vat numeric(14,2) not null, total numeric(14,2) not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  entry_id uuid references public.journal_entries(id),
  decided_by uuid, decided_at timestamptz, reason text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  unique (company_id, no)
);

create or replace function public.petty_balance(p_fund uuid) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum(l.debit - l.credit), 0) from public.petty_funds f join public.journal_lines l on l.company_id = f.company_id and l.account_code = f.account_code where f.id = p_fund
$$;

-- open a fund: a cash account of its own (under 1100) funded from the bank or the main safe
create or replace function public.petty_open(p_company uuid, p_employee uuid, p_amount numeric, p_from text, p_ceiling numeric, p_date date default current_date) returns uuid
language plpgsql security definer set search_path = public as $$
declare e public.employees; acode text; fid uuid; amt numeric := round(p_amount, 2);
begin
  perform public.require_fin(p_company, 'je');
  select * into e from public.employees where id = p_employee and company_id = p_company;
  if not found then raise exception 'الموظف غير موجود'; end if;
  if exists(select 1 from public.petty_funds where company_id = p_company and employee_id = p_employee and status = 'active') then raise exception 'للموظف عهدة نقدية قائمة'; end if;
  if coalesce(amt, 0) <= 0 then raise exception 'أدخل مبلغ العهدة'; end if;
  if coalesce(p_ceiling, amt) < amt then raise exception 'المبلغ أكبر من سقف العهدة'; end if;
  if p_date is null or p_date > current_date then raise exception 'التاريخ غير صحيح'; end if;
  if not exists(select 1 from public.accounts where company_id = p_company and code = p_from and parent_code = '1100' and not is_header) then raise exception 'اختر الصندوق أو البنك'; end if;
  if amt > public.account_balance(p_company, p_from, p_date) then raise exception 'الرصيد المتاح %', public.account_balance(p_company, p_from, p_date); end if;
  select min(c)::text into acode from generate_series(1131, 1199) c where not exists(select 1 from public.accounts a where a.company_id = p_company and a.code = c::text);
  if acode is null then raise exception 'لا توجد أرقام حسابات متاحة للعهد'; end if;
  insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header)
  values (p_company, acode, 'عهدة نقدية — ' || e.full_name, 'Petty cash — ' || coalesce(e.full_name_en, e.full_name), 'asset', '1100', false);
  insert into public.petty_funds(company_id, employee_id, account_code, ceiling, opened_on) values (p_company, p_employee, acode, coalesce(p_ceiling, amt), p_date) returning id into fid;
  perform public.post_journal(p_company, p_date, 'صرف عهدة نقدية — ' || e.full_name, 'petty', fid,
    jsonb_build_array(jsonb_build_object('a', acode, 'd', amt), jsonb_build_object('a', p_from, 'c', amt)));
  return fid;
end $$;

create or replace function public.petty_topup(p_fund uuid, p_amount numeric, p_from text, p_date date default current_date) returns void
language plpgsql security definer set search_path = public as $$
declare f public.petty_funds; amt numeric := round(p_amount, 2);
begin
  select * into f from public.petty_funds where id = p_fund for update;
  if not found then raise exception 'العهدة غير موجودة'; end if;
  perform public.require_fin(f.company_id, 'je');
  if f.status <> 'active' then raise exception 'العهدة مقفلة'; end if;
  if coalesce(amt, 0) <= 0 then raise exception 'أدخل المبلغ'; end if;
  if p_date is null or p_date > current_date then raise exception 'التاريخ غير صحيح'; end if;
  if public.petty_balance(p_fund) + amt > f.ceiling + 0.004 then raise exception 'تتجاوز العهدة سقفها (%) — المتاح للتعزيز %', f.ceiling, f.ceiling - public.petty_balance(p_fund); end if;
  if not exists(select 1 from public.accounts where company_id = f.company_id and code = p_from and parent_code = '1100' and not is_header and code <> f.account_code) then raise exception 'اختر الصندوق أو البنك'; end if;
  if amt > public.account_balance(f.company_id, p_from, p_date) then raise exception 'الرصيد المتاح %', public.account_balance(f.company_id, p_from, p_date); end if;
  perform public.post_journal(f.company_id, p_date, 'تعزيز عهدة نقدية', 'petty', f.id,
    jsonb_build_array(jsonb_build_object('a', f.account_code, 'd', amt), jsonb_build_object('a', p_from, 'c', amt)));
end $$;

-- the employee (or finance on his behalf) submits what was spent; finance approves → expenses + input VAT, credit the fund
create or replace function public.petty_claim_submit(p_fund uuid, p_date date, p_lines jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare f public.petty_funds; l jsonb; ls jsonb := '[]'; a numeric; v numeric; sa numeric := 0; sv numeric := 0; cid uuid; fin boolean;
begin
  select * into f from public.petty_funds where id = p_fund;
  if not found then raise exception 'العهدة غير موجودة'; end if;
  fin := public.fin_can(f.company_id, 'je');
  if not fin and public.my_employee(f.company_id) is distinct from f.employee_id then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if f.status <> 'active' then raise exception 'العهدة مقفلة'; end if;
  if p_date is null or p_date > current_date or p_date < f.opened_on then raise exception 'التاريخ غير صحيح'; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'أضف بنداً واحداً على الأقل'; end if;
  for l in select * from jsonb_array_elements(p_lines) loop
    a := round((l->>'amount')::numeric, 2);
    if coalesce(a, 0) <= 0 then raise exception 'مبلغ البند يجب أن يكون أكبر من صفر'; end if;
    if length(trim(coalesce(l->>'desc',''))) < 2 then raise exception 'اكتب وصف كل بند'; end if;
    if not exists(select 1 from public.accounts where company_id = f.company_id and code = l->>'a' and type = 'exp' and not is_header) then raise exception 'اختر حساب مصروف لكل بند'; end if;
    v := round(coalesce((l->>'vat')::numeric, 0), 2);
    if v < 0 or v > round(a * 0.15, 2) + 0.01 then raise exception 'ضريبة البند لا تتجاوز 15%% من مبلغه'; end if;
    if v > 0 and coalesce(l->>'vat_no','') !~ '^3[0-9]{13}3$' then raise exception 'لاسترداد الضريبة أدخل الرقم الضريبي للمورد (15 رقماً)'; end if;
    ls := ls || jsonb_build_array(jsonb_build_object('a', l->>'a', 'desc', trim(l->>'desc'), 'amount', a, 'vat', v, 'ref', nullif(trim(l->>'ref'),''), 'vat_no', nullif(trim(l->>'vat_no'),'')));
    sa := sa + a; sv := sv + v;
  end loop;
  insert into public.petty_claims(company_id, fund_id, no, date, lines, amount, vat, total)
  values (f.company_id, f.id, public.next_doc_no(f.company_id, 'PCC'), p_date, ls, sa, sv, sa + sv) returning id into cid;
  return cid;
end $$;

create or replace function public.petty_claim_decide(p_id uuid, p_approve boolean, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare c public.petty_claims; f public.petty_funds; jl jsonb; eid uuid; emp text;
begin
  select * into c from public.petty_claims where id = p_id for update;
  if not found then raise exception 'التسوية غير موجودة'; end if;
  perform public.require_fin(c.company_id, 'je');
  if c.status <> 'pending' then raise exception 'تمت معالجة هذه التسوية'; end if;
  select * into f from public.petty_funds where id = c.fund_id;
  if not p_approve then
    if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'اكتب سبب الرفض'; end if;
    update public.petty_claims set status = 'rejected', reason = trim(p_reason), decided_by = auth.uid(), decided_at = now() where id = p_id;
    return;
  end if;
  if c.total > public.petty_balance(f.id) + 0.004 then raise exception 'المصروف (%) أكبر من رصيد العهدة (%) — عزّز العهدة أولاً', c.total, public.petty_balance(f.id); end if;
  select full_name into emp from public.employees where id = f.employee_id;
  select jsonb_agg(jsonb_build_object('a', x.a, 'd', x.s)) into jl from (select l->>'a' a, sum((l->>'amount')::numeric) s from jsonb_array_elements(c.lines) l group by 1) x;
  if c.vat > 0 then jl := jl || jsonb_build_array(jsonb_build_object('a','1400','d', c.vat)); end if;
  jl := jl || jsonb_build_array(jsonb_build_object('a', f.account_code, 'c', c.total));
  eid := public.post_journal(c.company_id, c.date, 'تسوية عهدة ' || c.no || ' — ' || emp, 'petty', c.id, jl);
  update public.petty_claims set status = 'approved', entry_id = eid, decided_by = auth.uid(), decided_at = now() where id = p_id;
end $$;

-- close a fund: what is left goes back to the safe / bank
create or replace function public.petty_close(p_fund uuid, p_to text, p_date date default current_date) returns void
language plpgsql security definer set search_path = public as $$
declare f public.petty_funds; bal numeric;
begin
  select * into f from public.petty_funds where id = p_fund for update;
  if not found then raise exception 'العهدة غير موجودة'; end if;
  perform public.require_fin(f.company_id, 'je');
  if f.status <> 'active' then raise exception 'العهدة مقفلة مسبقاً'; end if;
  if exists(select 1 from public.petty_claims where fund_id = p_fund and status = 'pending') then raise exception 'توجد تسويات معلقة — اعتمدها أو ارفضها أولاً'; end if;
  if p_date is null or p_date > current_date then raise exception 'التاريخ غير صحيح'; end if;
  bal := public.petty_balance(p_fund);
  if bal > 0 then
    if not exists(select 1 from public.accounts where company_id = f.company_id and code = p_to and parent_code = '1100' and not is_header and code <> f.account_code) then raise exception 'اختر الصندوق أو البنك'; end if;
    perform public.post_journal(f.company_id, p_date, 'إقفال عهدة نقدية — إعادة الرصيد', 'petty', f.id,
      jsonb_build_array(jsonb_build_object('a', p_to, 'd', bal), jsonb_build_object('a', f.account_code, 'c', bal)));
  end if;
  update public.petty_funds set status = 'closed', closed_on = p_date where id = p_fund;
end $$;

-- the employee's own fund(s) with balance (employee self-service)
create or replace function public.petty_mine(p_company uuid) returns table(id uuid, account_code text, ceiling numeric, status text, opened_on date, balance numeric, pending numeric)
language sql stable security definer set search_path = public as $$
  select f.id, f.account_code, f.ceiling, f.status, f.opened_on, public.petty_balance(f.id),
         coalesce((select sum(total) from public.petty_claims c where c.fund_id = f.id and c.status = 'pending'), 0)
  from public.petty_funds f where f.company_id = p_company and f.employee_id = public.my_employee(p_company) order by f.opened_on desc
$$;
-- all funds with balances (finance)
create or replace function public.petty_list(p_company uuid) returns table(id uuid, employee_id uuid, account_code text, ceiling numeric, status text, opened_on date, closed_on date, balance numeric, pending numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'je');
  return query select f.id, f.employee_id, f.account_code, f.ceiling, f.status, f.opened_on, f.closed_on, public.petty_balance(f.id),
         coalesce((select sum(total) from public.petty_claims c where c.fund_id = f.id and c.status = 'pending'), 0)::numeric
  from public.petty_funds f where f.company_id = p_company order by f.status, f.opened_on desc;
end $$;
-- expense accounts list for the employee's claim form (employees cannot read the chart of accounts)
create or replace function public.petty_accounts(p_company uuid) returns table(code text, name text, name_en text)
language sql stable security definer set search_path = public as $$
  select a.code, a.name, a.name_en from public.accounts a where a.company_id = p_company and a.type = 'exp' and not a.is_header and a.code not in ('5100','5600','5700','5950')
    and (public.fin(p_company) or exists(select 1 from public.petty_funds f where f.company_id = p_company and f.employee_id = public.my_employee(p_company) and f.status = 'active'))
  order by a.code
$$;

-- ================= security =================
alter table public.cheques enable row level security;
alter table public.currencies enable row level security;
alter table public.opening_batches enable row level security;
alter table public.fiscal_closings enable row level security;
alter table public.petty_funds enable row level security;
alter table public.petty_claims enable row level security;
create policy ch_read on public.cheques for select using (public.fin_can(company_id, case direction when 'in' then 'sales' else 'purch' end));
create policy cu_read on public.currencies for select using (public.fin(company_id));
create policy ob_read on public.opening_batches for select using (public.has_role(company_id, array['owner','admin','finance']));
create policy fc_read on public.fiscal_closings for select using (public.fin_can(company_id, 'reports') or public.has_role(company_id, array['owner','admin','finance']));
create policy pf_read on public.petty_funds for select using (public.fin_can(company_id, 'je') or employee_id = public.my_employee(company_id));
create policy pc_read on public.petty_claims for select using (public.fin_can(company_id, 'je')
  or exists(select 1 from public.petty_funds f where f.id = fund_id and f.employee_id = public.my_employee(petty_claims.company_id)));
create trigger audit_cheques after insert or update on public.cheques for each row execute function public.audit_trigger();
create trigger audit_currencies after insert or update on public.currencies for each row execute function public.audit_trigger();
create trigger audit_opening_batches after insert or update on public.opening_batches for each row execute function public.audit_trigger();
create trigger audit_fiscal_closings after insert or update on public.fiscal_closings for each row execute function public.audit_trigger();
create trigger audit_petty_funds after insert or update on public.petty_funds for each row execute function public.audit_trigger();
create trigger audit_petty_claims after insert or update on public.petty_claims for each row execute function public.audit_trigger();

revoke all on public.cheques, public.currencies, public.opening_batches, public.fiscal_closings, public.petty_funds, public.petty_claims from anon;
revoke insert, update, delete on public.cheques, public.currencies, public.opening_batches, public.fiscal_closings, public.petty_funds, public.petty_claims from authenticated;
grant select on public.cheques, public.currencies, public.opening_batches, public.fiscal_closings, public.petty_funds, public.petty_claims to authenticated;

revoke all on function public.ensure_fin2_accounts(uuid), public.cheque_save(uuid, jsonb), public.cheque_clear(uuid, date, text), public.cheque_return(uuid, date, text),
  public.currency_save(uuid, text, text, text, numeric), public.fx_convert(uuid, jsonb), public.post_sales_invoice_wh(uuid, jsonb), public.post_purchase_bill_wh(uuid, jsonb),
  public.record_payment_fx(uuid, jsonb), public.opening_doc_guard(), public.opening_post(uuid, date, jsonb, boolean), public.opening_undo(uuid),
  public.year_close(uuid, date), public.year_reopen(uuid, text), public.is_closing_entry(uuid), public.petty_balance(uuid),
  public.petty_open(uuid, uuid, numeric, text, numeric, date), public.petty_topup(uuid, numeric, text, date), public.petty_claim_submit(uuid, date, jsonb),
  public.petty_claim_decide(uuid, boolean, text), public.petty_close(uuid, text, date), public.petty_mine(uuid), public.petty_list(uuid), public.petty_accounts(uuid)
  from public, anon, authenticated;
grant execute on function public.cheque_save(uuid, jsonb), public.cheque_clear(uuid, date, text), public.cheque_return(uuid, date, text),
  public.currency_save(uuid, text, text, text, numeric), public.post_sales_invoice_wh(uuid, jsonb), public.post_purchase_bill_wh(uuid, jsonb),
  public.record_payment_fx(uuid, jsonb), public.opening_post(uuid, date, jsonb, boolean), public.opening_undo(uuid),
  public.year_close(uuid, date), public.year_reopen(uuid, text),
  public.petty_open(uuid, uuid, numeric, text, numeric, date), public.petty_topup(uuid, numeric, text, date), public.petty_claim_submit(uuid, date, jsonb),
  public.petty_claim_decide(uuid, boolean, text), public.petty_close(uuid, text, date), public.petty_mine(uuid), public.petty_list(uuid), public.petty_accounts(uuid)
  to authenticated;
