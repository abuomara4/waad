-- Sales cycle: quotation → sales order → delivery note → tax invoice.
--  * A quotation (QT-) and a sales order (SO-) share one table; a quote converts once into an order.
--  * Line discount % gives a net unit price (rounded to halalas); the invoice is posted at that net price,
--    so the order amount and the invoice amount are the same number.
--  * The delivery note (DN-) records what physically left with the customer and checks stock on hand
--    (less what was delivered but not yet invoiced). Stock and cost of sales still move at invoicing,
--    as before, so the ledger has one source of truth.
--  * Invoicing an order posts through post_sales_invoice (VAT, COGS, journal unchanged); voiding that
--    invoice gives the quantities back to the order.

create table public.sales_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  kind text not null check (kind in ('quote','order')),
  no text not null,
  date date not null,
  valid_until date,
  party_id uuid not null references public.parties(id),
  status text not null default 'open',
  quote_id uuid references public.sales_orders(id),
  subtotal numeric(14,2) not null default 0, discount numeric(14,2) not null default 0,
  vat numeric(14,2) not null default 0, total numeric(14,2) not null default 0,
  note text, terms text, reason text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (company_id, no),
  check (kind = 'order' or (valid_until is not null and valid_until >= date)),
  check ((kind = 'quote' and status in ('open','accepted','rejected','converted')) or (kind = 'order' and status in ('open','closed','cancelled')))
);
create index on public.sales_orders(company_id, kind, date desc);
create table public.sales_order_lines (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.sales_orders(id) on delete cascade,
  item_id uuid not null references public.items(id),
  description text,
  qty numeric(14,3) not null check (qty > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  disc_pct numeric(5,2) not null default 0 check (disc_pct between 0 and 100),
  net_price numeric(12,2) not null,
  vat_rate numeric(5,2) not null default 15 check (vat_rate in (0,15)),
  amount numeric(14,2) not null, vat numeric(14,2) not null,
  delivered numeric(14,3) not null default 0 check (delivered >= 0 and delivered <= qty),
  invoiced numeric(14,3) not null default 0 check (invoiced >= 0 and invoiced <= qty)
);
create index on public.sales_order_lines(order_id);
create index on public.sales_order_lines(item_id);

alter table public.sales_invoices add column order_id uuid references public.sales_orders(id);
alter table public.sales_invoice_lines add column order_line bigint references public.sales_order_lines(id);
create index on public.sales_invoices(order_id);

create table public.delivery_notes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  order_id uuid not null references public.sales_orders(id),
  party_id uuid not null references public.parties(id),
  date date not null,
  status text not null default 'posted' check (status in ('posted','void')),
  received_by text, note text, void_reason text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  unique (company_id, no)
);
create index on public.delivery_notes(order_id);
create table public.delivery_note_lines (
  id bigint generated always as identity primary key,
  note_id uuid not null references public.delivery_notes(id) on delete cascade,
  order_line bigint not null references public.sales_order_lines(id),
  item_id uuid not null references public.items(id),
  qty numeric(14,3) not null check (qty > 0)
);
create index on public.delivery_note_lines(note_id);

-- ---------- helpers ----------
-- quantity of an item delivered to customers but not yet invoiced (still in stock_moves, already gone physically)
create or replace function public.delivered_uninvoiced(p_item uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(greatest(l.delivered - l.invoiced, 0)), 0)
  from public.sales_order_lines l join public.sales_orders o on o.id = l.order_id
  where l.item_id = p_item and o.kind = 'order' and o.status <> 'cancelled'
$$;

-- builds the lines of a quote/order from [{item, qty, price, disc, vat, desc}] and refreshes the totals
create or replace function public.so_fill_lines(p_id uuid, p_company uuid, p_lines jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare l jsonb; it public.items; q numeric; pr numeric; dc numeric; vr numeric; np numeric; amt numeric; vt numeric;
  sub numeric := 0; disc numeric := 0; v_vat numeric := 0;
begin
  if jsonb_array_length(coalesce(p_lines, '[]')) = 0 then raise exception 'أضف بنداً واحداً على الأقل'; end if;
  delete from public.sales_order_lines where order_id = p_id;
  for l in select * from jsonb_array_elements(p_lines) loop
    select * into it from public.items where id = (l->>'item')::uuid and company_id = p_company;
    if not found then raise exception 'صنف غير موجود'; end if;
    q := (l->>'qty')::numeric; pr := round((l->>'price')::numeric, 2); dc := coalesce((l->>'disc')::numeric, 0); vr := coalesce((l->>'vat')::numeric, 15);
    if q is null or q <= 0 then raise exception 'الكمية أكبر من صفر'; end if;
    if pr is null or pr < 0 then raise exception 'أدخل السعر'; end if;
    if dc < 0 or dc > 100 then raise exception 'نسبة الخصم بين 0 و 100'; end if;
    if vr not in (0, 15) then raise exception 'نسبة الضريبة 15%% أو 0%%'; end if;
    np := round(pr * (1 - dc / 100), 2); amt := round(q * np, 2); vt := round(amt * vr / 100, 2);
    insert into public.sales_order_lines(order_id, item_id, description, qty, unit_price, disc_pct, net_price, vat_rate, amount, vat)
    values (p_id, it.id, nullif(trim(l->>'desc'), ''), q, pr, dc, np, vr, amt, vt);
    sub := sub + amt; disc := disc + round(q * pr, 2) - amt; v_vat := v_vat + vt;
  end loop;
  update public.sales_orders set subtotal = sub, discount = disc, vat = v_vat, total = sub + v_vat, updated_at = now() where id = p_id;
end $$;

-- ---------- quotations & orders ----------
-- p_doc = {"id"?, "kind":"quote"|"order", "party", "date", "valid_until", "note", "terms", "lines":[{"item","qty","price","disc","vat","desc"}]}
create or replace function public.sales_doc_save(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare k text := p_doc->>'kind'; sid uuid := nullif(p_doc->>'id', '')::uuid; o public.sales_orders;
  d date := coalesce((p_doc->>'date')::date, current_date); vu date := (p_doc->>'valid_until')::date; pid uuid := (p_doc->>'party')::uuid;
begin
  perform public.require_fin(p_company, 'sales');
  if k not in ('quote','order') then raise exception 'نوع المستند غير صحيح'; end if;
  if not exists(select 1 from public.parties where id = pid and company_id = p_company and kind = 'customer') then raise exception 'اختر العميل'; end if;
  if d > current_date then raise exception 'التاريخ لا يكون في المستقبل'; end if;
  if k = 'quote' and (vu is null or vu < d) then raise exception 'تاريخ انتهاء العرض بعد تاريخه'; end if;
  if sid is null then
    insert into public.sales_orders(company_id, kind, no, date, valid_until, party_id, note, terms)
    values (p_company, k, public.next_doc_no(p_company, case k when 'quote' then 'QT' else 'SO' end), d, case k when 'quote' then vu end, pid,
            nullif(trim(p_doc->>'note'), ''), nullif(trim(p_doc->>'terms'), '')) returning id into sid;
  else
    select * into o from public.sales_orders where id = sid and company_id = p_company for update;
    if not found or o.kind <> k then raise exception 'المستند غير موجود'; end if;
    if o.status <> 'open' then raise exception 'لا يُعدَّل إلا المستند المفتوح'; end if;
    if exists(select 1 from public.sales_order_lines where order_id = sid and (delivered > 0 or invoiced > 0)) then raise exception 'لا يُعدَّل أمر بدأ تسليمه أو فوترته'; end if;
    update public.sales_orders set date = d, valid_until = case k when 'quote' then vu end, party_id = pid,
      note = nullif(trim(p_doc->>'note'), ''), terms = nullif(trim(p_doc->>'terms'), '') where id = sid;
  end if;
  perform public.so_fill_lines(sid, p_company, p_doc->'lines');
  return sid;
end $$;

create or replace function public.quote_decide(p_id uuid, p_accept boolean, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
declare o public.sales_orders;
begin
  select * into o from public.sales_orders where id = p_id and kind = 'quote' for update;
  if not found then raise exception 'العرض غير موجود'; end if;
  perform public.require_fin(o.company_id, 'sales');
  if o.status <> 'open' then raise exception 'العرض ليس مفتوحاً'; end if;
  if not p_accept and length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'اكتب سبب الرفض'; end if;
  update public.sales_orders set status = case when p_accept then 'accepted' else 'rejected' end, reason = nullif(trim(p_reason), ''), updated_at = now() where id = p_id;
end $$;

create or replace function public.quote_to_order(p_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare o public.sales_orders; nid uuid;
begin
  select * into o from public.sales_orders where id = p_id and kind = 'quote' for update;
  if not found then raise exception 'العرض غير موجود'; end if;
  perform public.require_fin(o.company_id, 'sales');
  if o.status not in ('open','accepted') then raise exception 'لا يُحوَّل إلا عرض مفتوح أو مقبول'; end if;
  if o.valid_until < current_date then raise exception 'انتهت صلاحية العرض، عدّل تاريخ الانتهاء أولاً'; end if;
  insert into public.sales_orders(company_id, kind, no, date, party_id, quote_id, subtotal, discount, vat, total, note, terms)
  values (o.company_id, 'order', public.next_doc_no(o.company_id, 'SO'), current_date, o.party_id, o.id, o.subtotal, o.discount, o.vat, o.total, o.note, o.terms)
  returning id into nid;
  insert into public.sales_order_lines(order_id, item_id, description, qty, unit_price, disc_pct, net_price, vat_rate, amount, vat)
  select nid, item_id, description, qty, unit_price, disc_pct, net_price, vat_rate, amount, vat from public.sales_order_lines where order_id = p_id order by id;
  update public.sales_orders set status = 'converted', updated_at = now() where id = p_id;
  return nid;
end $$;

-- nothing delivered or invoiced → cancelled; otherwise the remainder is closed (what was done stays)
create or replace function public.order_cancel(p_id uuid, p_reason text) returns text
language plpgsql security definer set search_path = public as $$
declare o public.sales_orders; st text;
begin
  select * into o from public.sales_orders where id = p_id and kind = 'order' for update;
  if not found then raise exception 'الأمر غير موجود'; end if;
  perform public.require_fin(o.company_id, 'sales');
  if o.status <> 'open' then raise exception 'الأمر ليس مفتوحاً'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'اكتب السبب'; end if;
  st := case when exists(select 1 from public.sales_order_lines where order_id = p_id and (delivered > 0 or invoiced > 0)) then 'closed' else 'cancelled' end;
  update public.sales_orders set status = st, reason = trim(p_reason), updated_at = now() where id = p_id;
  return st;
end $$;

-- ---------- delivery notes ----------
-- p_doc = {"date", "received_by", "note", "lines":[{"line":<order line id>,"qty"}]}
create or replace function public.delivery_post(p_order uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare o public.sales_orders; l jsonb; ol public.sales_order_lines; it public.items; st record; q numeric; nid uuid;
  d date := coalesce((p_doc->>'date')::date, current_date);
begin
  select * into o from public.sales_orders where id = p_order and kind = 'order' for update;
  if not found then raise exception 'الأمر غير موجود'; end if;
  if not (public.fin_can(o.company_id, 'sales') or public.fin_can(o.company_id, 'stock')) then
    raise exception 'غير مصرح: تحتاج صلاحية المبيعات أو المخزون' using errcode = '42501'; end if;
  -- a fully invoiced order (closed without a reason) can still have goods to hand over
  if not (o.status = 'open' or (o.status = 'closed' and o.reason is null)) then raise exception 'الأمر ليس مفتوحاً'; end if;
  if d > current_date or d < o.date then raise exception 'تاريخ التسليم بين تاريخ الأمر واليوم'; end if;
  if not exists(select 1 from jsonb_array_elements(coalesce(p_doc->'lines', '[]')) x where (x->>'qty')::numeric > 0) then raise exception 'أدخل كمية تسليم لبند واحد على الأقل'; end if;
  insert into public.delivery_notes(company_id, no, order_id, party_id, date, received_by, note)
  values (o.company_id, public.next_doc_no(o.company_id, 'DN'), o.id, o.party_id, d, nullif(trim(p_doc->>'received_by'), ''), nullif(trim(p_doc->>'note'), ''))
  returning id into nid;
  for l in select * from jsonb_array_elements(p_doc->'lines') loop
    q := (l->>'qty')::numeric;
    continue when q is null or q = 0;
    if q < 0 then raise exception 'الكمية لا تكون سالبة'; end if;
    select * into ol from public.sales_order_lines where id = (l->>'line')::bigint and order_id = o.id for update;
    if not found then raise exception 'بند غير موجود في الأمر'; end if;
    select * into it from public.items where id = ol.item_id;
    if ol.delivered + q > ol.qty then raise exception 'المتبقي للتسليم من «%» % فقط', it.name, ol.qty - ol.delivered; end if;
    if it.type = 'stock' then
      select * into st from public.stock_state(it.id);
      -- on hand physically = book qty − delivered-not-invoiced; this line's invoiced-not-delivered qty is already off the books but reserved for it
      if q > st.qty - public.delivered_uninvoiced(it.id) + greatest(ol.invoiced - ol.delivered, 0) then
        raise exception 'الكمية المتوفرة من «%» لا تكفي', it.name; end if;
    end if;
    insert into public.delivery_note_lines(note_id, order_line, item_id, qty) values (nid, ol.id, ol.item_id, q);
    update public.sales_order_lines set delivered = delivered + q where id = ol.id;
  end loop;
  return nid;
end $$;

create or replace function public.delivery_void(p_id uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare n public.delivery_notes;
begin
  select * into n from public.delivery_notes where id = p_id for update;
  if not found then raise exception 'الإشعار غير موجود'; end if;
  if not (public.fin_can(n.company_id, 'sales') or public.fin_can(n.company_id, 'stock')) then
    raise exception 'غير مصرح: تحتاج صلاحية المبيعات أو المخزون' using errcode = '42501'; end if;
  if n.status = 'void' then raise exception 'الإشعار ملغى مسبقاً'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'اكتب سبب الإلغاء'; end if;
  update public.sales_order_lines ol set delivered = ol.delivered - x.qty
  from (select order_line, sum(qty) qty from public.delivery_note_lines where note_id = p_id group by order_line) x where ol.id = x.order_line;
  update public.delivery_notes set status = 'void', void_reason = trim(p_reason) where id = p_id;
end $$;

-- ---------- invoicing an order ----------
-- p_doc = {"date", "due", "lines":[{"line","qty"}]}  (lines omitted → everything not yet invoiced)
create or replace function public.order_invoice(p_order uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare o public.sales_orders; l jsonb; ol public.sales_order_lines; q numeric; inv jsonb := '[]'; map jsonb := '[]'; iid uuid;
begin
  select * into o from public.sales_orders where id = p_order and kind = 'order' for update;
  if not found then raise exception 'الأمر غير موجود'; end if;
  perform public.require_fin(o.company_id, 'sales');
  if o.status <> 'open' then raise exception 'الأمر ليس مفتوحاً'; end if;
  for l in select case when p_doc ? 'lines' then x else jsonb_build_object('line', s.id, 'qty', s.qty - s.invoiced) end
           from public.sales_order_lines s left join jsonb_array_elements(case when p_doc ? 'lines' then p_doc->'lines' else '[]' end) x on (x->>'line')::bigint = s.id
           where s.order_id = o.id and (case when p_doc ? 'lines' then x is not null else s.qty > s.invoiced end) order by s.id loop
    q := (l->>'qty')::numeric;
    continue when q is null or q = 0;
    if q < 0 then raise exception 'الكمية لا تكون سالبة'; end if;
    select * into ol from public.sales_order_lines where id = (l->>'line')::bigint and order_id = o.id for update;
    if ol.invoiced + q > ol.qty then raise exception 'المتبقي للفوترة في أحد البنود % فقط', ol.qty - ol.invoiced; end if;
    inv := inv || jsonb_build_object('item', ol.item_id, 'qty', q, 'price', ol.net_price, 'vat', ol.vat_rate);
    map := map || jsonb_build_object('line', ol.id, 'qty', q);
  end loop;
  if jsonb_array_length(inv) = 0 then raise exception 'لا يوجد ما يُفوتر'; end if;
  iid := public.post_sales_invoice(o.company_id, jsonb_build_object('party', o.party_id, 'date', coalesce(p_doc->>'date', current_date::text),
    'due', p_doc->>'due', 'note', 'أمر بيع ' || o.no, 'lines', inv));
  -- post_sales_invoice writes its lines in the order given: tie each back to its order line
  update public.sales_invoice_lines il set order_line = m.line
  from (select id, row_number() over (order by id) rn from public.sales_invoice_lines where invoice_id = iid) a,
       (select (x->>'line')::bigint line, ord rn from jsonb_array_elements(map) with ordinality t(x, ord)) m
  where il.id = a.id and a.rn = m.rn;
  update public.sales_order_lines s set invoiced = s.invoiced + (x->>'qty')::numeric from jsonb_array_elements(map) x where s.id = (x->>'line')::bigint;
  update public.sales_invoices set order_id = o.id where id = iid;
  if not exists(select 1 from public.sales_order_lines where order_id = o.id and invoiced < qty) then
    update public.sales_orders set status = 'closed', updated_at = now() where id = o.id; end if;
  return iid;
end $$;

-- voiding an invoice raised from an order gives the quantities back (and reopens an order it had closed)
create or replace function public.so_invoice_void() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'void' and old.status <> 'void' and new.order_id is not null then
    update public.sales_order_lines ol set invoiced = greatest(ol.invoiced - x.qty, 0)
    from (select order_line, sum(qty) qty from public.sales_invoice_lines where invoice_id = new.id and order_line is not null group by order_line) x where ol.id = x.order_line;
    update public.sales_orders set status = 'open', updated_at = now() where id = new.order_id and status = 'closed' and reason is null;
  end if;
  return new;
end $$;
create trigger so_invoice_void after update of status on public.sales_invoices for each row execute function public.so_invoice_void();

-- ---------- audit, RLS, grants ----------
create trigger audit_sales_orders after insert or update on public.sales_orders for each row execute function public.audit_trigger();
create trigger audit_delivery_notes after insert or update on public.delivery_notes for each row execute function public.audit_trigger();
create trigger dnl_immutable before update or delete on public.delivery_note_lines for each row execute function public.block_change();

alter table public.sales_orders enable row level security;
alter table public.sales_order_lines enable row level security;
alter table public.delivery_notes enable row level security;
alter table public.delivery_note_lines enable row level security;
create policy so_read on public.sales_orders for select using (public.fin_can(company_id, 'sales') or (kind = 'order' and public.fin_can(company_id, 'stock')));
create policy sol_read on public.sales_order_lines for select using (exists(select 1 from public.sales_orders o where o.id = order_id));
create policy dn_read on public.delivery_notes for select using (public.fin_can(company_id, 'sales') or public.fin_can(company_id, 'stock'));
create policy dnl_read on public.delivery_note_lines for select using (exists(select 1 from public.delivery_notes n where n.id = note_id));

revoke all on public.sales_orders, public.sales_order_lines, public.delivery_notes, public.delivery_note_lines from anon;
revoke insert, update, delete on public.sales_orders, public.sales_order_lines, public.delivery_notes, public.delivery_note_lines from authenticated;
grant select on public.sales_orders, public.sales_order_lines, public.delivery_notes, public.delivery_note_lines to authenticated;

revoke all on function public.delivered_uninvoiced(uuid), public.so_fill_lines(uuid, uuid, jsonb), public.so_invoice_void(),
  public.sales_doc_save(uuid, jsonb), public.quote_decide(uuid, boolean, text), public.quote_to_order(uuid), public.order_cancel(uuid, text),
  public.delivery_post(uuid, jsonb), public.delivery_void(uuid, text), public.order_invoice(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.sales_doc_save(uuid, jsonb), public.quote_decide(uuid, boolean, text), public.quote_to_order(uuid), public.order_cancel(uuid, text),
  public.delivery_post(uuid, jsonb), public.delivery_void(uuid, text), public.order_invoice(uuid, jsonb) to authenticated;
