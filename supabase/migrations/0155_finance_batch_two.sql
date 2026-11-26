-- Waad ERP — 0155 second free batch, sales and finance (owner's request, 2026-11-26):
-- 13. the customer accepts or rejects a quotation from a private link; an accepted one becomes a sales order at once;
-- 14. landed costs: freight, customs and other costs of an import spread on the items of its purchase bills (by value or
--     quantity); the part still in stock raises the stock value (average cost), the part already sold goes to cost of sales;
-- 15. deferred revenue: an amount invoiced in advance (a yearly contract) is moved to 2180 and recognised month by month;
-- 16. supplier payment run: several bills paid at once from one bank / safe account, kept as a batch (bank file in the app);
-- 17. withholding tax on payments to non-residents, rates from ZATCA's «General Guideline for Withholding Tax» (May 2026,
--     section 3, Art. 68 of the Income Tax Law / Art. 63 of its Implementing Regulations): management fees 20%; royalties
--     15%; dividends, rent, loan charges, insurance / reinsurance, technical and consulting services, air tickets or air /
--     sea freight, international telecommunications 5%; land transport within the Kingdom 15%; any other payment 15%.
--     The withheld tax (Cr 2360) is paid to ZATCA within the first 10 days of the following month (guideline section 5).

alter table public.journal_entries drop constraint if exists journal_entries_source_check;
alter table public.journal_entries add constraint journal_entries_source_check check (source in ('manual','reversal','sales','purchase','receipt','payment',
  'stock','payroll','payroll_pay','advance','expense','opening','sales_return','purchase_return','asset','depreciation','cheque','closing','petty','trip','vehicle',
  'prepaid','bank','loan','guarantee','zakat','project','pos','production','landed','deferred','wht'));
alter table public.stock_moves drop constraint if exists stock_moves_source_check;
alter table public.stock_moves add constraint stock_moves_source_check check (source in ('purchase','sale','adjust','void','return','transfer','count','production','landed'));
-- a landed-cost move changes value only
alter table public.stock_moves drop constraint if exists stock_moves_qty_check;
alter table public.stock_moves add constraint stock_moves_qty_check check (qty <> 0 or source = 'landed');

create or replace function public.ensure_fin3_accounts(p_company uuid) returns void language sql security definer set search_path = public as $$
  insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header) values
    (p_company, '2180', 'إيرادات مؤجلة', 'Deferred revenue', 'liab', '2000', false),
    (p_company, '2360', 'ضريبة الاستقطاع المستحقة', 'Withholding tax payable', 'liab', '2000', false)
  on conflict do nothing;
$$;

-- ---------------- 13. quotation acceptance by link ----------------
alter table public.sales_orders add column if not exists accept_token text unique,
  add column if not exists decided_by_name text, add column if not exists decided_at timestamptz, add column if not exists decided_online boolean not null default false;
create or replace function public.quote_convert(p_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare o public.sales_orders; nid uuid;
begin
  select * into o from public.sales_orders where id = p_id and kind = 'quote' for update;
  insert into public.sales_orders(company_id, kind, no, date, party_id, quote_id, subtotal, discount, vat, total, note, terms)
  values (o.company_id, 'order', public.next_doc_no(o.company_id, 'SO'), current_date, o.party_id, o.id, o.subtotal, o.discount, o.vat, o.total, o.note, o.terms)
  returning id into nid;
  insert into public.sales_order_lines(order_id, item_id, description, qty, unit_price, disc_pct, net_price, vat_rate, amount, vat)
  select nid, item_id, description, qty, unit_price, disc_pct, net_price, vat_rate, amount, vat from public.sales_order_lines where order_id = p_id order by id;
  update public.sales_orders set status = 'converted', updated_at = now() where id = p_id;
  return nid;
end $$;
create or replace function public.quote_link_get(p_id uuid) returns text
language plpgsql security definer set search_path = public as $$
declare o public.sales_orders; t text;
begin
  select * into o from public.sales_orders where id = p_id and kind = 'quote';
  if not found then raise exception 'العرض غير موجود'; end if;
  perform public.require_fin(o.company_id, 'sales');
  if o.accept_token is not null then return o.accept_token; end if;
  t := encode(gen_random_bytes(32), 'hex');
  update public.sales_orders set accept_token = t where id = p_id;
  return t;
end $$;
-- anon: the customer's page
create or replace function public.quote_view(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o public.sales_orders; c public.companies;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return null; end if;
  select * into o from public.sales_orders where accept_token = p_token and kind = 'quote';
  if not found then return null; end if;
  select * into c from public.companies where id = o.company_id;
  return jsonb_build_object('company', c.name, 'logo', c.logo, 'vat_no', c.vat_no, 'no', o.no, 'date', o.date, 'valid_until', o.valid_until,
    'customer', (select name from public.parties where id = o.party_id), 'subtotal', o.subtotal, 'discount', o.discount, 'vat', o.vat, 'total', o.total,
    'terms', o.terms, 'note', o.note, 'status', o.status, 'expired', o.valid_until < current_date, 'decided_by', o.decided_by_name, 'decided_at', o.decided_at,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('item', coalesce(l.description, i.name), 'qty', l.qty, 'price', l.unit_price, 'disc', l.disc_pct, 'vat', l.vat_rate, 'amount', l.amount) order by l.id)
                  from public.sales_order_lines l join public.items i on i.id = l.item_id where l.order_id = o.id), '[]'));
end $$;
create or replace function public.quote_respond(p_token text, p_accept boolean, p_name text, p_note text) returns text
language plpgsql security definer set search_path = public as $$
declare o public.sales_orders; nid uuid;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then raise exception 'رابط غير صحيح'; end if;
  select * into o from public.sales_orders where accept_token = p_token and kind = 'quote' for update;
  if not found then raise exception 'رابط غير صحيح'; end if;
  if o.status <> 'open' then raise exception 'تم الرد على هذا العرض'; end if;
  if o.valid_until < current_date then raise exception 'انتهت صلاحية العرض — تواصل مع الشركة'; end if;
  if length(btrim(coalesce(p_name, ''))) < 3 then raise exception 'اكتب اسمك'; end if;
  if not coalesce(p_accept, false) and length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'اكتب سبب الرفض'; end if;
  update public.sales_orders set status = case when p_accept then 'accepted' else 'rejected' end, reason = case when p_accept then reason else left(btrim(p_note), 500) end,
    note = case when p_accept and nullif(btrim(p_note), '') is not null then coalesce(note || E'\n', '') || 'ملاحظة العميل: ' || left(btrim(p_note), 500) else note end,
    decided_by_name = left(btrim(p_name), 120), decided_at = now(), decided_online = true, updated_at = now() where id = o.id;
  if p_accept then nid := public.quote_convert(o.id); return (select no from public.sales_orders where id = nid); end if;
  return 'rejected';
end $$;

-- ---------------- 14. landed costs ----------------
create table if not exists public.landed_costs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  date date not null,
  bill_ids uuid[] not null,
  method text not null default 'value' check (method in ('value','qty')),
  costs jsonb not null,                              -- [{type: freight|customs|insurance|clearing|other, amount, note}]
  total numeric(14,2) not null check (total > 0),
  account_code text not null,                        -- paid from (safe / bank)
  to_stock numeric(14,2) not null default 0, to_cogs numeric(14,2) not null default 0,
  allocation jsonb not null default '[]',
  entry_id uuid references public.journal_entries(id) on delete set null,
  note text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  unique (company_id, no)
);
create index if not exists landed_costs_entry on public.landed_costs(entry_id);
alter table public.landed_costs enable row level security;
revoke all on public.landed_costs from anon, authenticated;
grant select on public.landed_costs to authenticated;
drop policy if exists landed_read on public.landed_costs;
create policy landed_read on public.landed_costs for select using (public.fin_can(company_id, 'purch') or public.fin_can(company_id, 'stock'));

-- p_doc = {date, bills: [uuid], method, account, costs: [{type, amount, note}], note}
create or replace function public.landed_post(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare d date := coalesce(nullif(p_doc->>'date', '')::date, current_date); acc text := coalesce(p_doc->>'account', '1120'); m text := coalesce(p_doc->>'method', 'value');
  bills uuid[]; tot numeric; base numeric; x record; share numeric; left_amt numeric; n int; i int := 0; onh numeric; f numeric; stk numeric := 0; cogs numeric := 0;
  alloc jsonb := '[]'; lid uuid := gen_random_uuid(); no text; jid uuid; wh uuid;
begin
  perform public.require_fin(p_company, 'purch');
  bills := array(select jsonb_array_elements_text(coalesce(p_doc->'bills', '[]'))::uuid);
  if cardinality(bills) = 0 then raise exception 'اختر فاتورة شراء واحدة على الأقل'; end if;
  if exists(select 1 from unnest(bills) b where not exists(select 1 from public.purchase_bills p where p.id = b and p.company_id = p_company and p.status = 'posted')) then
    raise exception 'فاتورة الشراء غير موجودة أو ملغاة'; end if;
  if m not in ('value','qty') then raise exception 'طريقة التوزيع غير معروفة'; end if;
  if acc not in (select code from public.accounts where company_id = p_company and parent_code = '1100' and not is_header) then raise exception 'اختر الصندوق أو البنك'; end if;
  if d > current_date then raise exception 'التاريخ لا يكون في المستقبل'; end if;
  select round(coalesce(sum((c->>'amount')::numeric), 0), 2) into tot from jsonb_array_elements(coalesce(p_doc->'costs', '[]')) c;
  if exists(select 1 from jsonb_array_elements(coalesce(p_doc->'costs', '[]')) c where coalesce((c->>'amount')::numeric, 0) <= 0 or c->>'type' not in ('freight','customs','insurance','clearing','other')) then
    raise exception 'لكل تكلفة نوع ومبلغ أكبر من صفر'; end if;
  if tot <= 0 then raise exception 'أدخل التكاليف'; end if;
  if tot > public.account_balance(p_company, acc, d) then raise exception 'الرصيد المتاح %', public.account_balance(p_company, acc, d); end if;
  -- the stock items of those bills, added up per item
  select coalesce(sum(case m when 'value' then a else q end), 0), count(*) into base, n from (
    select l.item_id, sum(l.amount) a, sum(l.qty) q
      from public.purchase_bill_lines l join public.items it on it.id = l.item_id and it.type = 'stock' where l.bill_id = any(bills) group by l.item_id) t;
  if n = 0 or base <= 0 then raise exception 'لا توجد أصناف مخزنية في الفواتير المختارة'; end if;
  left_amt := tot;
  for x in select l.item_id, sum(l.amount) a, sum(l.qty) q, (select name from public.items where id = l.item_id) nm
             from public.purchase_bill_lines l join public.items it on it.id = l.item_id and it.type = 'stock' where l.bill_id = any(bills) group by l.item_id order by l.item_id loop
    i := i + 1;
    share := case when i = n then left_amt else round(tot * (case m when 'value' then x.a else x.q end) / base, 2) end;
    left_amt := left_amt - share;
    onh := greatest((public.stock_state(x.item_id)).qty, 0);
    f := least(1, onh / nullif(x.q, 0));
    stk := stk + round(share * coalesce(f, 0), 2);
    alloc := alloc || jsonb_build_array(jsonb_build_object('item', x.item_id, 'name', x.nm, 'qty', x.q, 'value', x.a, 'share', share, 'stock', round(share * coalesce(f, 0), 2), 'cogs', share - round(share * coalesce(f, 0), 2)));
    if round(share * coalesce(f, 0), 2) <> 0 then
      select warehouse_id into wh from public.stock_moves where item_id = x.item_id and source = 'purchase' and source_id = any(bills) order by id desc limit 1;
      insert into public.stock_moves(company_id, item_id, date, qty, value, source, source_id, note, warehouse_id) values (p_company, x.item_id, d, 0, round(share * coalesce(f, 0), 2), 'landed', lid, 'تكاليف محمّلة', wh);
    end if;
  end loop;
  cogs := tot - stk;
  no := public.next_doc_no(p_company, 'LC');
  jid := public.post_journal(p_company, d, 'تكاليف محمّلة ' || no, 'landed', lid,
    (case when stk > 0 then jsonb_build_array(jsonb_build_object('a', '1300', 'd', stk)) else '[]'::jsonb end)
    || (case when cogs > 0 then jsonb_build_array(jsonb_build_object('a', '5100', 'd', cogs)) else '[]'::jsonb end)
    || jsonb_build_array(jsonb_build_object('a', acc, 'c', tot)));
  insert into public.landed_costs(id, company_id, no, date, bill_ids, method, costs, total, account_code, to_stock, to_cogs, allocation, entry_id, note)
  values (lid, p_company, no, d, bills, m, p_doc->'costs', tot, acc, stk, cogs, alloc, jid, nullif(btrim(p_doc->>'note'), ''));
  return lid;
end $$;

-- ---------------- 15. deferred revenue ----------------
create table if not exists public.deferred_schedules (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null check (length(btrim(name)) between 2 and 120),
  invoice_id uuid references public.sales_invoices(id) on delete set null,
  revenue_account text not null,
  deferred_account text not null default '2180',
  cost_center_id uuid references public.cost_centers(id) on delete set null,
  total numeric(14,2) not null check (total > 0),
  start_month date not null check (extract(day from start_month) = 1),
  months int not null check (months between 2 and 120),
  defer_entry uuid references public.journal_entries(id) on delete set null,
  status text not null default 'active' check (status in ('active','done','stopped')),
  created_by uuid default auth.uid(), created_at timestamptz not null default now()
);
create index if not exists deferred_schedules_company on public.deferred_schedules(company_id);
create index if not exists deferred_schedules_inv on public.deferred_schedules(invoice_id);
create index if not exists deferred_schedules_cc on public.deferred_schedules(cost_center_id);
create index if not exists deferred_schedules_entry on public.deferred_schedules(defer_entry);
create table if not exists public.deferred_postings (
  schedule_id uuid not null references public.deferred_schedules(id) on delete cascade,
  period date not null,
  amount numeric(14,2) not null,
  entry_id uuid references public.journal_entries(id) on delete set null,
  primary key (schedule_id, period)
);
create index if not exists deferred_postings_entry on public.deferred_postings(entry_id);
alter table public.deferred_schedules enable row level security;
alter table public.deferred_postings enable row level security;
revoke all on public.deferred_schedules, public.deferred_postings from anon, authenticated;
grant select on public.deferred_schedules, public.deferred_postings to authenticated;
drop policy if exists deferred_read on public.deferred_schedules;
create policy deferred_read on public.deferred_schedules for select using (public.fin_can(company_id, 'je'));
drop policy if exists deferred_post_read on public.deferred_postings;
create policy deferred_post_read on public.deferred_postings for select using (exists(select 1 from public.deferred_schedules s where s.id = schedule_id and public.fin_can(s.company_id, 'je')));

-- the amount already booked as revenue (by the invoice) moves to 2180 on the start, then comes back month by month
create or replace function public.deferred_create(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare sid uuid; inv public.sales_invoices; amt numeric := round((p_doc->>'amount')::numeric, 2); st date := date_trunc('month', (p_doc->>'start')::date)::date; jid uuid; ra text := p_doc->>'revenue';
begin
  perform public.require_fin(p_company, 'jepost');
  perform public.ensure_fin3_accounts(p_company);
  if not exists(select 1 from public.accounts where company_id = p_company and code = ra and type = 'rev' and not is_header) then raise exception 'اختر حساب الإيراد'; end if;
  if coalesce(amt, 0) <= 0 then raise exception 'أدخل المبلغ'; end if;
  if coalesce((p_doc->>'months')::int, 0) not between 2 and 120 then raise exception 'عدد الأشهر من 2 إلى 120'; end if;
  if st is null then raise exception 'حدد شهر البداية'; end if;
  if nullif(p_doc->>'invoice', '') is not null then
    select * into inv from public.sales_invoices where id = (p_doc->>'invoice')::uuid and company_id = p_company and status = 'posted';
    if not found then raise exception 'الفاتورة غير موجودة'; end if;
    if amt > inv.subtotal then raise exception 'المبلغ أكبر من قيمة الفاتورة قبل الضريبة (%)', inv.subtotal; end if;
  end if;
  insert into public.deferred_schedules(company_id, name, invoice_id, revenue_account, cost_center_id, total, start_month, months)
  values (p_company, btrim(p_doc->>'name'), inv.id, ra, nullif(p_doc->>'cc', '')::uuid, amt, st, (p_doc->>'months')::int) returning id into sid;
  jid := public.post_journal(p_company, greatest(coalesce(inv.date, st), st), 'إيراد مؤجل — ' || btrim(p_doc->>'name'), 'deferred', sid,
    jsonb_build_array(jsonb_build_object('a', ra, 'd', amt, 'cc', nullif(p_doc->>'cc', '')::uuid), jsonb_build_object('a', '2180', 'c', amt)));
  update public.deferred_schedules set defer_entry = jid where id = sid;
  return sid;
end $$;
-- recognises every month due up to p_through; the last month takes the rounding difference
create or replace function public.deferred_run(p_company uuid, p_through date) returns int
language plpgsql security definer set search_path = public as $$
declare s public.deferred_schedules; i int; per date; amt numeric; jid uuid; n int := 0; done numeric;
begin
  perform public.require_fin(p_company, 'jepost');
  for s in select * from public.deferred_schedules where company_id = p_company and status = 'active' order by start_month loop
    for i in 0 .. s.months - 1 loop
      per := (s.start_month + make_interval(months => i))::date;
      exit when per > date_trunc('month', p_through)::date;
      continue when exists(select 1 from public.deferred_postings where schedule_id = s.id and period = per);
      select coalesce(sum(amount), 0) into done from public.deferred_postings where schedule_id = s.id;
      amt := case when i = s.months - 1 then s.total - done else round(s.total / s.months, 2) end;
      jid := public.post_journal(p_company, (per + interval '1 month - 1 day')::date, s.name || ' — ' || to_char(per, 'YYYY-MM'), 'deferred', s.id,
        jsonb_build_array(jsonb_build_object('a', s.deferred_account, 'd', amt), jsonb_build_object('a', s.revenue_account, 'c', amt, 'cc', s.cost_center_id)));
      insert into public.deferred_postings(schedule_id, period, amount, entry_id) values (s.id, per, amt, jid);
      n := n + 1;
    end loop;
    if (select count(*) from public.deferred_postings where schedule_id = s.id) >= s.months then update public.deferred_schedules set status = 'done' where id = s.id; end if;
  end loop;
  return n;
end $$;
create or replace function public.deferred_stop(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s public.deferred_schedules;
begin
  select * into s from public.deferred_schedules where id = p_id;
  if not found then raise exception 'الجدول غير موجود'; end if;
  perform public.require_fin(s.company_id, 'jepost');
  update public.deferred_schedules set status = 'stopped' where id = p_id and status = 'active';
end $$;

-- ---------------- 16. supplier payment run ----------------
create table if not exists public.payment_batches (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  date date not null,
  account_code text not null,
  total numeric(14,2) not null,
  n int not null,
  note text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  unique (company_id, no)
);
alter table public.payments add column if not exists batch_id uuid references public.payment_batches(id) on delete set null;
create index if not exists payments_batch on public.payments(batch_id);
alter table public.payment_batches enable row level security;
revoke all on public.payment_batches from anon, authenticated;
grant select on public.payment_batches to authenticated;
drop policy if exists pbatch_read on public.payment_batches;
create policy pbatch_read on public.payment_batches for select using (public.fin_can(company_id, 'purch'));
-- p_doc = {date, account, note, items: [{bill, amount}]}; all or nothing
create or replace function public.payment_batch(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare d date := coalesce(nullif(p_doc->>'date', '')::date, current_date); acc text := coalesce(p_doc->>'account', '1120'); x jsonb; b public.purchase_bills; tot numeric := 0; cnt int := 0; bid uuid; pid uuid;
begin
  perform public.require_fin(p_company, 'purch');
  if jsonb_array_length(coalesce(p_doc->'items', '[]')) = 0 then raise exception 'اختر فاتورة واحدة على الأقل'; end if;
  select coalesce(sum((i->>'amount')::numeric), 0) into tot from jsonb_array_elements(p_doc->'items') i;
  if tot > public.account_balance(p_company, acc, d) then raise exception 'الرصيد المتاح %', public.account_balance(p_company, acc, d); end if;
  insert into public.payment_batches(company_id, no, date, account_code, total, n, note) values (p_company, public.next_doc_no(p_company, 'PB'), d, acc, round(tot, 2), 0, nullif(btrim(p_doc->>'note'), '')) returning id into bid;
  for x in select * from jsonb_array_elements(p_doc->'items') loop
    select * into b from public.purchase_bills where id = (x->>'bill')::uuid and company_id = p_company;
    if not found then raise exception 'فاتورة الشراء غير موجودة'; end if;
    pid := public.record_payment(p_company, jsonb_build_object('direction', 'out', 'party', b.party_id, 'bill', b.id, 'amount', x->>'amount', 'date', d, 'account', acc,
             'note', coalesce(nullif(btrim(p_doc->>'note'), ''), 'دفعة سداد جماعية')));
    update public.payments set batch_id = bid where id = pid;
    cnt := cnt + 1;
  end loop;
  update public.payment_batches set n = cnt where id = bid;
  return bid;
end $$;

-- ---------------- 17. withholding tax ----------------
-- pure: the ZATCA rate by payment type (guideline section 3)
create or replace function public.wht_rate(p_type text) returns numeric language sql immutable as $$
  select case p_type when 'management' then 20 when 'royalty' then 15 when 'dividends' then 5 when 'rent' then 5 when 'loan' then 5 when 'insurance' then 5
    when 'technical' then 5 when 'air' then 5 when 'telecom' then 5 when 'land_transport' then 15 when 'other' then 15 end
$$;
alter table public.parties add column if not exists wht_type text check (wht_type is null or wht_type in ('management','royalty','dividends','rent','loan','insurance','technical','air','telecom','land_transport','other'));
create table if not exists public.wht_records (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  party_id uuid not null references public.parties(id),
  bill_id uuid references public.purchase_bills(id) on delete set null,
  payment_id uuid references public.payments(id) on delete set null,
  tax_payment_id uuid references public.payments(id) on delete set null,
  date date not null,
  wht_type text not null,
  rate numeric(5,2) not null,
  gross numeric(14,2) not null check (gross > 0),
  tax numeric(14,2) not null check (tax >= 0),
  remitted_at date, remit_entry uuid references public.journal_entries(id) on delete set null,
  created_by uuid default auth.uid(), created_at timestamptz not null default now()
);
create index if not exists wht_records_company on public.wht_records(company_id, date);
create index if not exists wht_records_party on public.wht_records(party_id);
create index if not exists wht_records_bill on public.wht_records(bill_id);
create index if not exists wht_records_pay on public.wht_records(payment_id);
create index if not exists wht_records_tpay on public.wht_records(tax_payment_id);
create index if not exists wht_records_entry on public.wht_records(remit_entry);
alter table public.wht_records enable row level security;
revoke all on public.wht_records from anon, authenticated;
grant select on public.wht_records to authenticated;
drop policy if exists wht_read on public.wht_records;
create policy wht_read on public.wht_records for select using (public.fin_can(company_id, 'purch') or public.fin_can(company_id, 'je'));
-- pays a bill to a non-resident: the supplier gets the gross less the tax; the tax stays in 2360 until paid to ZATCA
create or replace function public.wht_pay(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare b public.purchase_bills; tp text := p_doc->>'type'; r numeric := public.wht_rate(p_doc->>'type'); g numeric := round((p_doc->>'gross')::numeric, 2);
  d date := coalesce(nullif(p_doc->>'date', '')::date, current_date); acc text := coalesce(p_doc->>'account', '1120'); tax numeric; net numeric; pid uuid; tid uuid; no text; wid uuid;
begin
  perform public.require_fin(p_company, 'purch');
  perform public.ensure_fin3_accounts(p_company);
  if r is null then raise exception 'اختر نوع الدفعة'; end if;
  select * into b from public.purchase_bills where id = (p_doc->>'bill')::uuid and company_id = p_company and status = 'posted';
  if not found then raise exception 'فاتورة الشراء غير موجودة أو ملغاة'; end if;
  if coalesce(g, 0) <= 0 then raise exception 'أدخل المبلغ'; end if;
  if g > b.total - public.paid_on(b.id) + 0.001 then raise exception 'المبلغ أكبر من المتبقي (%)', b.total - public.paid_on(b.id); end if;
  tax := round(g * r / 100, 2); net := g - tax;
  pid := public.record_payment(p_company, jsonb_build_object('direction', 'out', 'party', b.party_id, 'bill', b.id, 'amount', net, 'date', d, 'account', acc,
           'note', 'بعد ضريبة الاستقطاع ' || r || '%'));
  if tax > 0 then
    no := public.next_doc_no(p_company, 'PV');
    insert into public.payments(company_id, no, direction, party_id, bill_id, date, amount, account_code, note)
    values (p_company, no, 'out', b.party_id, b.id, d, tax, '2360', 'ضريبة استقطاع ' || r || '% محجوزة لهيئة الزكاة والضريبة والجمارك') returning id into tid;
    perform public.post_journal(p_company, d, 'ضريبة استقطاع ' || no, 'wht', tid,
      jsonb_build_array(jsonb_build_object('a', '2100', 'd', tax), jsonb_build_object('a', '2360', 'c', tax)));
  end if;
  insert into public.wht_records(company_id, party_id, bill_id, payment_id, tax_payment_id, date, wht_type, rate, gross, tax)
  values (p_company, b.party_id, b.id, pid, tid, d, tp, r, g, tax) returning id into wid;
  if nullif(p_doc->>'remember', '') is not null and (p_doc->>'remember')::boolean then update public.parties set wht_type = tp where id = b.party_id; end if;
  return wid;
end $$;
-- the month's statement: what was withheld, from whom, and when it is due (the 10th of the next month)
create or replace function public.wht_month(p_company uuid, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ms date := date_trunc('month', p_month)::date;
begin
  if not (public.fin_can(p_company, 'purch') or public.fin_can(p_company, 'je')) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return jsonb_build_object('month', ms, 'due', (ms + interval '1 month')::date + 9,
    'tax', coalesce((select sum(tax) from public.wht_records where company_id = p_company and date_trunc('month', date) = ms), 0),
    'remitted', coalesce((select sum(tax) from public.wht_records where company_id = p_company and date_trunc('month', date) = ms and remitted_at is not null), 0),
    'rows', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'date', w.date, 'party', p.name, 'country', p.country, 'type', w.wht_type, 'rate', w.rate, 'gross', w.gross, 'tax', w.tax,
              'bill', (select coalesce(nullif(x.supplier_ref, ''), x.no) from public.purchase_bills x where x.id = w.bill_id), 'remitted_at', w.remitted_at) order by w.date)
       from public.wht_records w join public.parties p on p.id = w.party_id where w.company_id = p_company and date_trunc('month', w.date) = ms), '[]'));
end $$;
-- paying the month's withheld tax to ZATCA: Dr 2360 / Cr safe or bank
create or replace function public.wht_remit(p_company uuid, p_month date, p_account text, p_date date) returns numeric
language plpgsql security definer set search_path = public as $$
declare ms date := date_trunc('month', p_month)::date; amt numeric; jid uuid; d date := coalesce(p_date, current_date);
begin
  perform public.require_fin(p_company, 'purch');
  if p_account not in (select code from public.accounts where company_id = p_company and parent_code = '1100' and not is_header) then raise exception 'اختر الصندوق أو البنك'; end if;
  select coalesce(sum(tax), 0) into amt from public.wht_records where company_id = p_company and date_trunc('month', date) = ms and remitted_at is null;
  if amt <= 0 then raise exception 'لا توجد ضريبة استقطاع غير مسددة لهذا الشهر'; end if;
  if amt > public.account_balance(p_company, p_account, d) then raise exception 'الرصيد المتاح %', public.account_balance(p_company, p_account, d); end if;
  jid := public.post_journal(p_company, d, 'سداد ضريبة الاستقطاع لشهر ' || to_char(ms, 'YYYY-MM'), 'wht', null,
    jsonb_build_array(jsonb_build_object('a', '2360', 'd', amt), jsonb_build_object('a', p_account, 'c', amt)));
  update public.wht_records set remitted_at = d, remit_entry = jid where company_id = p_company and date_trunc('month', date) = ms and remitted_at is null;
  return amt;
end $$;

revoke all on function public.ensure_fin3_accounts(uuid), public.quote_convert(uuid) from public, anon, authenticated;
revoke all on function public.quote_link_get(uuid), public.landed_post(uuid, jsonb), public.deferred_create(uuid, jsonb), public.deferred_run(uuid, date), public.deferred_stop(uuid),
  public.payment_batch(uuid, jsonb), public.wht_pay(uuid, jsonb), public.wht_month(uuid, date), public.wht_remit(uuid, date, text, date), public.wht_rate(text) from public, anon;
grant execute on function public.quote_link_get(uuid), public.landed_post(uuid, jsonb), public.deferred_create(uuid, jsonb), public.deferred_run(uuid, date), public.deferred_stop(uuid),
  public.payment_batch(uuid, jsonb), public.wht_pay(uuid, jsonb), public.wht_month(uuid, date), public.wht_remit(uuid, date, text, date), public.wht_rate(text) to authenticated;
revoke all on function public.quote_view(text), public.quote_respond(text, boolean, text, text) from public;
grant execute on function public.quote_view(text), public.quote_respond(text, boolean, text, text) to anon, authenticated;
notify pgrst, 'reload schema';
