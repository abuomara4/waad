-- Purchase cycle: purchase request (employee, through the approval route) → purchase order → goods receipt → supplier bill.
--  * The purchase request is a normal employee request (kind 'purchase'): default route direct manager → finance → general
--    manager, editable in «مسارات الاعتماد». Its lines are free text with an estimated price.
--  * The purchase order (PO-) is raised by purchasing (finance permission «purch»), from an approved request or directly.
--    Each line is a stock/service item or an expense account.
--  * The goods receipt (GRN-) brings stock in at the PO price: Dr 1300 inventory / Cr 2150 goods received not invoiced,
--    so received goods can be sold before the supplier's invoice arrives.
--  * The supplier bill from the PO is matched three ways: a stock line can be billed only up to what was received;
--    service and expense lines up to what was ordered. The bill clears 2150 (stock lines), debits the expense
--    (service/expense lines) and the input VAT, and credits the supplier. Bill price = PO price.
--  * Voiding a PO bill gives the billed quantities back; voiding a receipt takes the stock out again (only if it is
--    still on hand and was not billed beyond what remains received).

-- ---------- purchase request as an employee request ----------
alter table public.requests drop constraint requests_kind_check;
alter table public.requests add constraint requests_kind_check
  check (kind in ('leave','permit','cert','advance','resign','settle','expense','update','punch','ticket','visa','purchase'));

create or replace function public.default_route(p_kind text) returns text[] language sql immutable as $$
  select case p_kind
    when 'leave' then array['m','p','h','g'] when 'permit' then array['m','p'] when 'cert' then array['p'] when 'punch' then array['m','p']
    when 'advance' then array['m','p','h','f','g'] when 'resign' then array['m','p','h','g','f']
    when 'settle' then array['p','h','f','g'] when 'expense' then array['m','f','g']
    when 'ticket' then array['m','p','h','f'] when 'visa' then array['m','p','h']
    when 'purchase' then array['m','f','g']
    else array['p'] end
$$;

create or replace function public.workflow_set(p_company uuid, p_kind text, p_route text[]) returns text[]
language plpgsql security definer set search_path = public as $$
declare rt text[];
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if p_kind not in ('leave','permit','cert','advance','resign','settle','expense','update','punch','ticket','visa','purchase') then raise exception 'نوع طلب غير معروف'; end if;
  if p_route is null then delete from public.workflows where company_id = p_company and kind = p_kind; return public.default_route(p_kind); end if;
  rt := array(select s from unnest(array['m','p','h','f','g']) with ordinality x(s, i) where s = any(p_route) order by i);
  if cardinality(rt) = 0 then raise exception 'اختر مرحلة اعتماد واحدة على الأقل'; end if;
  if p_kind in ('ticket','advance','expense','settle','purchase') and not ('f' = any(rt)) then raise exception 'هذا الطلب يصرف مبلغاً فلا بد أن يمر على المالية'; end if;
  insert into public.workflows(company_id, kind, route) values (p_company, p_kind, rt)
    on conflict (company_id, kind) do update set route = excluded.route;
  return rt;
end $$;

-- validates and normalises a purchase request on insert: payload.lines = [{desc, qty, price}], amount = estimated total
create or replace function public.purchase_request_check() returns trigger
language plpgsql security definer set search_path = public as $$
declare l jsonb; ls jsonb := '[]'; tot numeric := 0; q numeric; p numeric; d text;
begin
  if new.kind <> 'purchase' then return new; end if;
  if jsonb_typeof(new.payload->'lines') <> 'array' or jsonb_array_length(new.payload->'lines') = 0 then raise exception 'أضف بنداً واحداً على الأقل'; end if;
  if jsonb_array_length(new.payload->'lines') > 30 then raise exception 'حتى 30 بنداً في الطلب'; end if;
  for l in select * from jsonb_array_elements(new.payload->'lines') loop
    d := trim(coalesce(l->>'desc', '')); q := nullif(l->>'qty', '')::numeric; p := coalesce(nullif(l->>'price', '')::numeric, 0);
    if length(d) < 2 then raise exception 'اكتب وصف البند'; end if;
    if q is null or q <= 0 then raise exception 'الكمية أكبر من صفر'; end if;
    if p < 0 then raise exception 'السعر التقديري لا يكون سالباً'; end if;
    ls := ls || jsonb_build_object('desc', left(d, 200), 'qty', q, 'price', round(p, 2));
    tot := tot + round(q * round(p, 2), 2);
  end loop;
  if new.from_date is not null and new.from_date < current_date then raise exception 'تاريخ الحاجة لا يكون قبل اليوم'; end if;
  new.payload := jsonb_build_object('lines', ls); new.amount := tot; new.to_date := new.from_date;
  return new;
end $$;
create trigger purchase_request_check before insert on public.requests for each row when (new.kind = 'purchase') execute function public.purchase_request_check();

-- ---------- purchase orders ----------
create table public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  date date not null,
  expected_date date,
  party_id uuid not null references public.parties(id),
  request_id uuid references public.requests(id) on delete set null,
  status text not null default 'open' check (status in ('open','closed','cancelled')),
  subtotal numeric(14,2) not null default 0, vat numeric(14,2) not null default 0, total numeric(14,2) not null default 0,
  note text, terms text, reason text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (company_id, no),
  check (expected_date is null or expected_date >= date)
);
create index on public.purchase_orders(company_id, date desc);
create unique index purchase_orders_request on public.purchase_orders(request_id) where request_id is not null and status <> 'cancelled';
create table public.purchase_order_lines (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.purchase_orders(id) on delete cascade,
  item_id uuid references public.items(id),
  account_code text,
  description text,
  qty numeric(14,3) not null check (qty > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  vat_rate numeric(5,2) not null default 15 check (vat_rate in (0,15)),
  amount numeric(14,2) not null, vat numeric(14,2) not null,
  received numeric(14,3) not null default 0 check (received >= 0 and received <= qty),
  billed numeric(14,3) not null default 0 check (billed >= 0 and billed <= qty),
  check ((item_id is null) <> (account_code is null))
);
create index on public.purchase_order_lines(order_id);

alter table public.purchase_bills add column order_id uuid references public.purchase_orders(id);
alter table public.purchase_bill_lines add column order_line bigint references public.purchase_order_lines(id);
create index on public.purchase_bills(order_id);

create table public.goods_receipts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  order_id uuid not null references public.purchase_orders(id),
  party_id uuid not null references public.parties(id),
  date date not null,
  status text not null default 'posted' check (status in ('posted','void')),
  supplier_doc text, note text, void_reason text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  unique (company_id, no)
);
create index on public.goods_receipts(order_id);
create table public.goods_receipt_lines (
  id bigint generated always as identity primary key,
  receipt_id uuid not null references public.goods_receipts(id) on delete cascade,
  order_line bigint not null references public.purchase_order_lines(id),
  item_id uuid not null references public.items(id),
  qty numeric(14,3) not null check (qty > 0),
  value numeric(14,2) not null default 0
);
create index on public.goods_receipt_lines(receipt_id);

-- ---------- helpers ----------
create or replace function public.ensure_grni(p_company uuid) returns void
language sql security definer set search_path = public as $$
  insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header)
  values (p_company, '2150', 'بضاعة مستلمة لم تصل فاتورتها', 'Goods received not invoiced', 'liab', '2000', false) on conflict do nothing
$$;
select public.ensure_grni(id) from public.companies;

-- lines [{item|account, qty, price, vat, desc}] → PO lines and totals
create or replace function public.po_fill_lines(p_id uuid, p_company uuid, p_lines jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare l jsonb; it public.items; q numeric; pr numeric; vr numeric; amt numeric; vt numeric; acc text; sub numeric := 0; v_vat numeric := 0;
begin
  if jsonb_array_length(coalesce(p_lines, '[]')) = 0 then raise exception 'أضف بنداً واحداً على الأقل'; end if;
  delete from public.purchase_order_lines where order_id = p_id;
  for l in select * from jsonb_array_elements(p_lines) loop
    q := (l->>'qty')::numeric; pr := round((l->>'price')::numeric, 2); vr := coalesce((l->>'vat')::numeric, 15);
    if q is null or q <= 0 then raise exception 'الكمية أكبر من صفر'; end if;
    if pr is null or pr < 0 then raise exception 'أدخل السعر'; end if;
    if vr not in (0, 15) then raise exception 'نسبة الضريبة 15%% أو 0%%'; end if;
    amt := round(q * pr, 2); vt := round(amt * vr / 100, 2);
    if nullif(l->>'item', '') is not null then
      select * into it from public.items where id = (l->>'item')::uuid and company_id = p_company;
      if not found then raise exception 'صنف غير موجود'; end if;
      insert into public.purchase_order_lines(order_id, item_id, description, qty, unit_price, vat_rate, amount, vat)
      values (p_id, it.id, nullif(trim(l->>'desc'), ''), q, pr, vr, amt, vt);
    else
      acc := l->>'account';
      if not exists(select 1 from public.accounts where company_id = p_company and code = acc and not is_header and type in ('exp','asset')
                    and acc not in ('1100','1110','1120','1200','1300','1400') and coalesce(parent_code, '') <> '1100') then
        raise exception 'اختر صنفاً أو حساب مصروف صالحاً'; end if;
      insert into public.purchase_order_lines(order_id, account_code, description, qty, unit_price, vat_rate, amount, vat)
      values (p_id, acc, nullif(trim(l->>'desc'), ''), q, pr, vr, amt, vt);
    end if;
    sub := sub + amt; v_vat := v_vat + vt;
  end loop;
  update public.purchase_orders set subtotal = sub, vat = v_vat, total = sub + v_vat, updated_at = now() where id = p_id;
end $$;

-- p_doc = {"id"?, "party", "date", "expected", "request"?, "note", "terms", "lines":[...]}
create or replace function public.po_save(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare pid uuid := (p_doc->>'party')::uuid; d date := coalesce((p_doc->>'date')::date, current_date); ex date := nullif(p_doc->>'expected', '')::date;
  oid uuid := nullif(p_doc->>'id', '')::uuid; rq uuid := nullif(p_doc->>'request', '')::uuid; o public.purchase_orders;
begin
  perform public.require_fin(p_company, 'purch');
  if not exists(select 1 from public.parties where id = pid and company_id = p_company and kind = 'supplier') then raise exception 'اختر المورد'; end if;
  if d > current_date then raise exception 'التاريخ لا يكون في المستقبل'; end if;
  if ex is not null and ex < d then raise exception 'تاريخ التوريد المتوقع بعد تاريخ الأمر'; end if;
  if rq is not null then
    if not exists(select 1 from public.requests where id = rq and company_id = p_company and kind = 'purchase' and status = 'approved') then
      raise exception 'طلب الشراء غير معتمد'; end if;
    if exists(select 1 from public.purchase_orders where request_id = rq and status <> 'cancelled' and id is distinct from oid) then
      raise exception 'صدر أمر شراء لهذا الطلب من قبل'; end if;
  end if;
  if oid is null then
    insert into public.purchase_orders(company_id, no, date, expected_date, party_id, request_id, note, terms)
    values (p_company, public.next_doc_no(p_company, 'PO'), d, ex, pid, rq, nullif(trim(p_doc->>'note'), ''), nullif(trim(p_doc->>'terms'), ''))
    returning id into oid;
  else
    select * into o from public.purchase_orders where id = oid and company_id = p_company for update;
    if not found then raise exception 'الأمر غير موجود'; end if;
    if o.status <> 'open' then raise exception 'لا يُعدَّل إلا الأمر المفتوح'; end if;
    if exists(select 1 from public.purchase_order_lines where order_id = oid and (received > 0 or billed > 0)) then raise exception 'لا يُعدَّل أمر بدأ استلامه أو فوترته'; end if;
    update public.purchase_orders set date = d, expected_date = ex, party_id = pid, request_id = rq,
      note = nullif(trim(p_doc->>'note'), ''), terms = nullif(trim(p_doc->>'terms'), '') where id = oid;
  end if;
  perform public.po_fill_lines(oid, p_company, p_doc->'lines');
  return oid;
end $$;

create or replace function public.po_cancel(p_id uuid, p_reason text) returns text
language plpgsql security definer set search_path = public as $$
declare o public.purchase_orders; st text;
begin
  select * into o from public.purchase_orders where id = p_id for update;
  if not found then raise exception 'الأمر غير موجود'; end if;
  perform public.require_fin(o.company_id, 'purch');
  if o.status <> 'open' then raise exception 'الأمر ليس مفتوحاً'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'اكتب السبب'; end if;
  st := case when exists(select 1 from public.purchase_order_lines where order_id = p_id and (received > 0 or billed > 0)) then 'closed' else 'cancelled' end;
  update public.purchase_orders set status = st, reason = trim(p_reason), updated_at = now() where id = p_id;
  return st;
end $$;

-- ---------- goods receipt ----------
-- p_doc = {"date", "supplier_doc", "note", "lines":[{"line","qty"}]}
create or replace function public.grn_post(p_order uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare o public.purchase_orders; l jsonb; ol public.purchase_order_lines; it public.items; q numeric; v numeric; gid uuid; tot numeric := 0;
  d date := coalesce((p_doc->>'date')::date, current_date);
begin
  select * into o from public.purchase_orders where id = p_order for update;
  if not found then raise exception 'الأمر غير موجود'; end if;
  if not (public.fin_can(o.company_id, 'purch') or public.fin_can(o.company_id, 'stock')) then
    raise exception 'غير مصرح: تحتاج صلاحية المشتريات أو المخزون' using errcode = '42501'; end if;
  if o.status <> 'open' then raise exception 'الأمر ليس مفتوحاً'; end if;
  if d > current_date or d < o.date then raise exception 'تاريخ الاستلام بين تاريخ الأمر واليوم'; end if;
  if not exists(select 1 from jsonb_array_elements(coalesce(p_doc->'lines', '[]')) x where (x->>'qty')::numeric > 0) then raise exception 'أدخل كمية مستلمة لبند واحد على الأقل'; end if;
  insert into public.goods_receipts(company_id, no, order_id, party_id, date, supplier_doc, note)
  values (o.company_id, public.next_doc_no(o.company_id, 'GRN'), o.id, o.party_id, d, nullif(trim(p_doc->>'supplier_doc'), ''), nullif(trim(p_doc->>'note'), ''))
  returning id into gid;
  for l in select * from jsonb_array_elements(p_doc->'lines') loop
    q := (l->>'qty')::numeric;
    continue when q is null or q = 0;
    if q < 0 then raise exception 'الكمية لا تكون سالبة'; end if;
    select * into ol from public.purchase_order_lines where id = (l->>'line')::bigint and order_id = o.id for update;
    if not found then raise exception 'بند غير موجود في الأمر'; end if;
    if ol.item_id is null then raise exception 'بنود الحسابات لا تُستلم، تُفوتر مباشرة'; end if;
    select * into it from public.items where id = ol.item_id;
    if ol.received + q > ol.qty then raise exception 'المتبقي للاستلام من «%» % فقط', it.name, ol.qty - ol.received; end if;
    v := 0;
    if it.type = 'stock' then
      v := round(q * ol.unit_price, 2);
      insert into public.stock_moves(company_id, item_id, date, qty, value, source, source_id, note) values (o.company_id, it.id, d, q, v, 'purchase', gid, 'استلام ' || o.no);
      tot := tot + v;
    end if;
    insert into public.goods_receipt_lines(receipt_id, order_line, item_id, qty, value) values (gid, ol.id, ol.item_id, q, v);
    update public.purchase_order_lines set received = received + q where id = ol.id;
  end loop;
  if tot > 0 then
    perform public.ensure_grni(o.company_id);
    perform public.post_journal(o.company_id, d, 'استلام بضاعة — أمر شراء ' || o.no, 'purchase', gid,
      jsonb_build_array(jsonb_build_object('a','1300','d',tot), jsonb_build_object('a','2150','c',tot)));
  end if;
  return gid;
end $$;

create or replace function public.grn_void(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare g public.goods_receipts; x record; st record;
begin
  select * into g from public.goods_receipts where id = p_id for update;
  if not found then raise exception 'الاستلام غير موجود'; end if;
  if not (public.fin_can(g.company_id, 'purch') or public.fin_can(g.company_id, 'stock')) then
    raise exception 'غير مصرح: تحتاج صلاحية المشتريات أو المخزون' using errcode = '42501'; end if;
  if g.status = 'void' then raise exception 'الاستلام ملغى مسبقاً'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'اكتب سبب الإلغاء'; end if;
  for x in select gl.order_line, gl.item_id, sum(gl.qty) qty, sum(gl.value) value, i.type, i.name, ol.received, ol.billed
           from public.goods_receipt_lines gl join public.items i on i.id = gl.item_id join public.purchase_order_lines ol on ol.id = gl.order_line
           where gl.receipt_id = p_id group by gl.order_line, gl.item_id, i.type, i.name, ol.received, ol.billed loop
    if x.type = 'stock' and x.received - x.qty < x.billed then raise exception 'لا يُلغى: فُوترت كمية من «%» على هذا الاستلام', x.name; end if;
    if x.type = 'stock' then
      select * into st from public.stock_state(x.item_id);
      if st.qty < x.qty then raise exception 'لا يُلغى: جزء من كمية «%» صُرف أو بيع', x.name; end if;
      insert into public.stock_moves(company_id, item_id, date, qty, value, source, source_id, note) values (g.company_id, x.item_id, current_date, -x.qty, -x.value, 'void', p_id, p_reason);
    end if;
    update public.purchase_order_lines set received = received - x.qty where id = x.order_line;
  end loop;
  perform public.reverse_source(g.company_id, p_id, current_date, 'إلغاء استلام بضاعة');
  update public.goods_receipts set status = 'void', void_reason = trim(p_reason) where id = p_id;
end $$;

-- ---------- supplier bill from the order (three-way match) ----------
-- p_doc = {"ref", "date", "due", "lines":[{"line","qty"}]}  (lines omitted → everything billable)
create or replace function public.po_bill(p_order uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare o public.purchase_orders; l jsonb; ol public.purchase_order_lines; it public.items; q numeric; cap numeric; amt numeric; vt numeric; acc text;
  bid uuid; no text; sub numeric := 0; v_vat numeric := 0; dr jsonb := '{}'; jl jsonb := '[]'; k text; n int := 0;
  d date := coalesce((p_doc->>'date')::date, current_date); ref text := nullif(trim(p_doc->>'ref'), '');
begin
  select * into o from public.purchase_orders where id = p_order for update;
  if not found then raise exception 'الأمر غير موجود'; end if;
  perform public.require_fin(o.company_id, 'purch');
  if o.status <> 'open' then raise exception 'الأمر ليس مفتوحاً'; end if;
  if d > current_date then raise exception 'تاريخ الفاتورة لا يكون في المستقبل'; end if;
  if (p_doc->>'due') is not null and (p_doc->>'due')::date < d then raise exception 'تاريخ الاستحقاق قبل تاريخ الفاتورة'; end if;
  if ref is not null and exists(select 1 from public.purchase_bills where company_id = o.company_id and party_id = o.party_id and supplier_ref = ref and status = 'posted') then
    raise exception 'رقم فاتورة المورد مسجّل مسبقاً'; end if;
  no := public.next_doc_no(o.company_id, 'BIL');
  insert into public.purchase_bills(company_id, no, supplier_ref, date, due_date, party_id, subtotal, vat, total, note, order_id)
  values (o.company_id, no, ref, d, coalesce((p_doc->>'due')::date, d), o.party_id, 0, 0, 0, 'أمر شراء ' || o.no, o.id) returning id into bid;
  for ol in select * from public.purchase_order_lines where order_id = o.id order by id for update loop
    if p_doc ? 'lines' then
      l := null; select x.value into l from jsonb_array_elements(p_doc->'lines') x where (x.value->>'line')::bigint = ol.id limit 1;
      q := case when l is null then 0 else (l->>'qty')::numeric end;
    else q := null; end if;
    it := null; if ol.item_id is not null then select * into it from public.items where id = ol.item_id; end if;
    -- three-way match: stock lines up to what was received, others up to what was ordered
    cap := case when it.type = 'stock' then ol.received - ol.billed else ol.qty - ol.billed end;
    q := coalesce(q, greatest(cap, 0));
    continue when q = 0;
    if q < 0 then raise exception 'الكمية لا تكون سالبة'; end if;
    if q > cap then raise exception '«%»: الكمية القابلة للفوترة % (%)', coalesce(it.name, ol.account_code), greatest(cap, 0),
      case when it.type = 'stock' then 'المستلم ناقص المفوتر' else 'المطلوب ناقص المفوتر' end; end if;
    amt := case when q = ol.qty then ol.amount else round(q * ol.unit_price, 2) end; vt := round(amt * ol.vat_rate / 100, 2);
    acc := case when it.type = 'stock' then '2150' when it.id is not null then '5500' else ol.account_code end;
    insert into public.purchase_bill_lines(bill_id, item_id, account_code, qty, unit_price, vat_rate, amount, vat, order_line)
    values (bid, ol.item_id, case when ol.item_id is null then ol.account_code end, q, ol.unit_price, ol.vat_rate, amt, vt, ol.id);
    update public.purchase_order_lines set billed = billed + q where id = ol.id;
    dr := jsonb_set(dr, array[acc], to_jsonb(coalesce((dr->>acc)::numeric, 0) + amt));
    sub := sub + amt; v_vat := v_vat + vt; n := n + 1;
  end loop;
  if n = 0 then raise exception 'لا يوجد ما يُفوتر — استلم البضاعة أولاً'; end if;
  update public.purchase_bills set subtotal = sub, vat = v_vat, total = sub + v_vat where id = bid;
  for k in select jsonb_object_keys(dr) loop jl := jl || jsonb_build_array(jsonb_build_object('a', k, 'd', (dr->>k)::numeric)); end loop;
  jl := jl || jsonb_build_array(jsonb_build_object('a','1400','d',v_vat), jsonb_build_object('a','2100','c',sub + v_vat));
  perform public.ensure_grni(o.company_id);
  perform public.post_journal(o.company_id, d, 'فاتورة مشتريات ' || no || ' — أمر ' || o.no, 'purchase', bid, jl);
  if not exists(select 1 from public.purchase_order_lines where order_id = o.id and billed < qty) then
    update public.purchase_orders set status = 'closed', updated_at = now() where id = o.id; end if;
  return bid;
end $$;

-- voiding a PO bill gives the billed quantities back (and reopens an order it had closed)
create or replace function public.po_bill_void() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'void' and old.status <> 'void' and new.order_id is not null then
    update public.purchase_order_lines ol set billed = greatest(ol.billed - x.qty, 0)
    from (select order_line, sum(qty) qty from public.purchase_bill_lines where bill_id = new.id and order_line is not null group by order_line) x where ol.id = x.order_line;
    update public.purchase_orders set status = 'open', updated_at = now() where id = new.order_id and status = 'closed' and reason is null;
  end if;
  return new;
end $$;
create trigger po_bill_void after update of status on public.purchase_bills for each row execute function public.po_bill_void();

-- approved purchase requests for the purchasing team (they may not be HR, so they cannot read requests directly)
create or replace function public.purchase_requests(p_company uuid)
returns table(id uuid, created_at timestamptz, needed_by date, employee text, employee_en text, dept text, amount numeric, lines jsonb, note text, po_id uuid, po_no text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'purch');
  return query
  select r.id, r.created_at, r.from_date, e.full_name, e.full_name_en, dp.name, r.amount, r.payload->'lines', r.note, po.id, po.no
  from public.requests r join public.employees e on e.id = r.employee_id
  left join public.departments dp on dp.id = e.department_id
  left join public.purchase_orders po on po.request_id = r.id and po.status <> 'cancelled'
  where r.company_id = p_company and r.kind = 'purchase' and r.status = 'approved'
  order by (po.id is null) desc, r.created_at desc;
end $$;

-- ---------- audit, RLS, grants ----------
create trigger audit_purchase_orders after insert or update on public.purchase_orders for each row execute function public.audit_trigger();
create trigger audit_goods_receipts after insert or update on public.goods_receipts for each row execute function public.audit_trigger();
create trigger grl_immutable before update or delete on public.goods_receipt_lines for each row execute function public.block_change();

alter table public.purchase_orders enable row level security;
alter table public.purchase_order_lines enable row level security;
alter table public.goods_receipts enable row level security;
alter table public.goods_receipt_lines enable row level security;
create policy po_read on public.purchase_orders for select using (public.fin_can(company_id, 'purch') or public.fin_can(company_id, 'stock'));
create policy pol_read on public.purchase_order_lines for select using (exists(select 1 from public.purchase_orders o where o.id = order_id));
create policy grn_read on public.goods_receipts for select using (public.fin_can(company_id, 'purch') or public.fin_can(company_id, 'stock'));
create policy grnl_read on public.goods_receipt_lines for select using (exists(select 1 from public.goods_receipts g where g.id = receipt_id));

revoke all on public.purchase_orders, public.purchase_order_lines, public.goods_receipts, public.goods_receipt_lines from anon;
revoke insert, update, delete on public.purchase_orders, public.purchase_order_lines, public.goods_receipts, public.goods_receipt_lines from authenticated;
grant select on public.purchase_orders, public.purchase_order_lines, public.goods_receipts, public.goods_receipt_lines to authenticated;

revoke all on function public.purchase_request_check(), public.ensure_grni(uuid), public.po_fill_lines(uuid, uuid, jsonb), public.po_bill_void(),
  public.po_save(uuid, jsonb), public.po_cancel(uuid, text), public.grn_post(uuid, jsonb), public.grn_void(uuid, text), public.po_bill(uuid, jsonb),
  public.purchase_requests(uuid), public.workflow_set(uuid, text, text[]), public.default_route(text) from public, anon, authenticated;
grant execute on function public.po_save(uuid, jsonb), public.po_cancel(uuid, text), public.grn_post(uuid, jsonb), public.grn_void(uuid, text),
  public.po_bill(uuid, jsonb), public.purchase_requests(uuid), public.workflow_set(uuid, text, text[]), public.default_route(text) to authenticated;
