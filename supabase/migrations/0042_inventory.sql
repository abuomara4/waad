-- Inventory: warehouses, transfers, stock counts, batches with expiry dates, reorder suggestions.
--  * Valuation stays company-wide moving average (one cost per item); quantities are tracked per warehouse.
--  * Every stock move carries a warehouse. It is chosen by the document (sales invoice, bill, order, receipt, transfer,
--    count, adjustment) or resolved: returns and voids go back to the warehouse of the original move; otherwise the
--    company's default warehouse. A move can never take a warehouse below zero.
--  * Items flagged «تتبع الصلاحية» keep batches (batch no. + expiry). Receipts record them; issues consume the
--    earliest expiry first (FEFO); transfers carry the batches across.
--  * Stock count (STC-): a sheet per warehouse with the system quantity; posting books the differences
--    (Dr/Cr 1300 inventory vs 5600 stock differences) at average cost.

-- ---------- warehouses ----------
create table public.warehouses (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null check (code ~ '^[A-Za-z0-9_-]{1,12}$'),
  name text not null check (length(trim(name)) >= 2),
  name_en text,
  is_default boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (company_id, code)
);
create unique index warehouses_default on public.warehouses(company_id) where is_default;

create or replace function public.wh_default(p_company uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare w uuid;
begin
  select id into w from public.warehouses where company_id = p_company and is_default;
  if w is null then
    insert into public.warehouses(company_id, code, name, name_en, is_default) values (p_company, 'MAIN', 'المستودع الرئيسي', 'Main warehouse', true)
    on conflict (company_id, code) do update set is_default = true returning id into w;
  end if;
  return w;
end $$;
select public.wh_default(id) from public.companies;

-- the warehouse chosen for this transaction (set by the *_wh wrappers); validated against the company
create or replace function public.wh_use(p_company uuid, p_wh text) returns uuid
language plpgsql security definer set search_path = public as $$
declare w uuid := nullif(p_wh, '')::uuid;
begin
  if w is not null and not exists(select 1 from public.warehouses where id = w and company_id = p_company and active) then
    raise exception 'المستودع غير موجود أو موقوف'; end if;
  perform set_config('waad.wh', coalesce(w::text, ''), true);
  return coalesce(w, public.wh_default(p_company));
end $$;
create or replace function public.wh_cfg(p_company uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select coalesce((select id from public.warehouses where id = nullif(current_setting('waad.wh', true), '')::uuid and company_id = p_company),
                  (select id from public.warehouses where company_id = p_company and is_default))
$$;
create or replace function public.wh_qty(p_item uuid, p_wh uuid) returns numeric
language plpgsql stable security definer set search_path = public as $$
begin return (select coalesce(sum(qty), 0) from public.stock_moves where item_id = p_item and warehouse_id = p_wh); end $$;

-- ---------- columns on existing tables ----------
alter table public.items add column track_expiry boolean not null default false,
  add column reorder_qty numeric(12,3) not null default 0 check (reorder_qty >= 0);
alter table public.stock_moves add column warehouse_id uuid references public.warehouses(id),
  add column batch text, add column expiry date;
alter table public.stock_moves drop constraint stock_moves_source_check;
alter table public.stock_moves add constraint stock_moves_source_check check (source in ('purchase','sale','adjust','void','return','transfer','count'));
alter table public.sales_invoices add column warehouse_id uuid references public.warehouses(id);
alter table public.purchase_bills add column warehouse_id uuid references public.warehouses(id);
alter table public.sales_orders add column warehouse_id uuid references public.warehouses(id);
alter table public.purchase_orders add column warehouse_id uuid references public.warehouses(id);
alter table public.delivery_notes add column warehouse_id uuid references public.warehouses(id);
alter table public.goods_receipts add column warehouse_id uuid references public.warehouses(id);
alter table public.goods_receipt_lines add column batch text, add column expiry date;

-- backfill: everything so far happened in the default warehouse (stock_moves is append-only: lift the guard for this one update)
alter table public.stock_moves disable trigger sm_immutable;
update public.stock_moves m set warehouse_id = public.wh_default(m.company_id) where warehouse_id is null;
alter table public.stock_moves enable trigger sm_immutable;
update public.sales_invoices set warehouse_id = public.wh_default(company_id) where warehouse_id is null;
update public.purchase_bills set warehouse_id = public.wh_default(company_id) where warehouse_id is null;
update public.sales_orders set warehouse_id = public.wh_default(company_id) where warehouse_id is null;
update public.purchase_orders set warehouse_id = public.wh_default(company_id) where warehouse_id is null;
update public.delivery_notes d set warehouse_id = (select warehouse_id from public.sales_orders o where o.id = d.order_id) where warehouse_id is null;
update public.goods_receipts g set warehouse_id = (select warehouse_id from public.purchase_orders o where o.id = g.order_id) where warehouse_id is null;
create index on public.stock_moves(item_id, warehouse_id);

-- documents take the transaction's warehouse (or keep theirs / inherit from the quote)
create or replace function public.doc_wh() returns trigger
language plpgsql security definer set search_path = public as $$
declare cfg uuid := nullif(current_setting('waad.wh', true), '')::uuid;
begin
  if cfg is not null and exists(select 1 from public.warehouses where id = cfg and company_id = new.company_id) then new.warehouse_id := cfg;
  elsif new.warehouse_id is null then
    if tg_table_name = 'sales_orders' then
      if new.quote_id is not null then select warehouse_id into new.warehouse_id from public.sales_orders where id = new.quote_id; end if;
    end if;
    new.warehouse_id := coalesce(new.warehouse_id, public.wh_default(new.company_id));
  end if;
  return new;
end $$;
create trigger sales_invoices_wh before insert on public.sales_invoices for each row execute function public.doc_wh();
create trigger purchase_bills_wh before insert on public.purchase_bills for each row execute function public.doc_wh();
create trigger sales_orders_wh before insert or update on public.sales_orders for each row execute function public.doc_wh();
create trigger purchase_orders_wh before insert or update on public.purchase_orders for each row execute function public.doc_wh();

-- ---------- batches ----------
create table public.stock_batches (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  item_id uuid not null references public.items(id),
  warehouse_id uuid not null references public.warehouses(id),
  batch text not null default '',
  expiry date,
  qty numeric(14,3) not null default 0
);
create unique index stock_batches_key on public.stock_batches(item_id, warehouse_id, batch, coalesce(expiry, '9999-12-31'::date));

-- resolve the warehouse of every move and keep warehouses from going negative
create or replace function public.sm_before() returns trigger
language plpgsql security definer set search_path = public as $$
declare w uuid; b text; x date; nm text; whn text;
begin
  if new.warehouse_id is null then
    if new.source = 'sale' then select warehouse_id into w from public.sales_invoices where id = new.source_id;
    elsif new.source = 'purchase' then select warehouse_id into w from public.purchase_bills where id = new.source_id;
    elsif new.source = 'return' then
      select coalesce(si.warehouse_id, pb.warehouse_id) into w from public.credit_notes cn
        left join public.sales_invoices si on si.id = cn.doc_id left join public.purchase_bills pb on pb.id = cn.doc_id where cn.id = new.source_id;
    elsif new.source = 'void' then
      select m.warehouse_id, m.batch, m.expiry into w, b, x from public.stock_moves m
       where m.source_id = new.source_id and m.item_id = new.item_id and m.source <> 'void' and sign(m.qty) = -sign(new.qty) order by m.id desc limit 1;
      new.batch := coalesce(new.batch, b); new.expiry := coalesce(new.expiry, x);
    end if;
    new.warehouse_id := coalesce(w, public.wh_cfg(new.company_id), public.wh_default(new.company_id));
  end if;
  if new.qty < 0 and public.wh_qty(new.item_id, new.warehouse_id) + new.qty < -0.0005 then
    select name into nm from public.items where id = new.item_id; select name into whn from public.warehouses where id = new.warehouse_id;
    raise exception 'الكمية المتوفرة من «%» في «%» % فقط', nm, whn, public.wh_qty(new.item_id, new.warehouse_id);
  end if;
  return new;
end $$;
create trigger sm_before before insert on public.stock_moves for each row execute function public.sm_before();

-- batches: receipts add to their batch, issues take the named batch first then the earliest expiry
create or replace function public.sm_batches() returns trigger
language plpgsql security definer set search_path = public as $$
declare left_q numeric; r record; take numeric;
begin
  if not exists(select 1 from public.items where id = new.item_id and track_expiry) then return null; end if;
  if new.qty > 0 then
    insert into public.stock_batches(company_id, item_id, warehouse_id, batch, expiry, qty)
    values (new.company_id, new.item_id, new.warehouse_id, coalesce(new.batch, ''), new.expiry, new.qty)
    on conflict (item_id, warehouse_id, batch, coalesce(expiry, '9999-12-31'::date)) do update set qty = stock_batches.qty + excluded.qty;
  else
    left_q := -new.qty;
    for r in select * from public.stock_batches where item_id = new.item_id and warehouse_id = new.warehouse_id and qty > 0
             order by (new.batch is not null and batch = new.batch and expiry is not distinct from coalesce(new.expiry, expiry)) desc, expiry nulls last, id loop
      exit when left_q <= 0;
      take := least(r.qty, left_q);
      update public.stock_batches set qty = qty - take where id = r.id;
      left_q := left_q - take;
    end loop;
  end if;
  return null;
end $$;
create trigger sm_batches after insert on public.stock_moves for each row execute function public.sm_batches();

-- ---------- sales and purchase cycles become warehouse-aware ----------
create or replace function public.delivered_uninvoiced_wh(p_item uuid, p_wh uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(greatest(l.delivered - l.invoiced, 0)), 0)
  from public.sales_order_lines l join public.sales_orders o on o.id = l.order_id
  where l.item_id = p_item and o.kind = 'order' and o.status <> 'cancelled' and o.warehouse_id = p_wh
$$;
revoke all on function public.delivered_uninvoiced_wh(uuid, uuid) from public, anon, authenticated;

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
  insert into public.delivery_notes(company_id, no, order_id, party_id, date, received_by, note, warehouse_id)
  values (o.company_id, public.next_doc_no(o.company_id, 'DN'), o.id, o.party_id, d, nullif(trim(p_doc->>'received_by'), ''), nullif(trim(p_doc->>'note'), ''), o.warehouse_id)
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
      -- on hand in the order's warehouse = book qty − delivered-not-invoiced; this line's invoiced-not-delivered qty is reserved for it
      if q > public.wh_qty(it.id, o.warehouse_id) - public.delivered_uninvoiced_wh(it.id, o.warehouse_id) + greatest(ol.invoiced - ol.delivered, 0) then
        raise exception 'الكمية المتوفرة من «%» لا تكفي', it.name; end if;
    end if;
    insert into public.delivery_note_lines(note_id, order_line, item_id, qty) values (nid, ol.id, ol.item_id, q);
    update public.sales_order_lines set delivered = delivered + q where id = ol.id;
  end loop;
  return nid;
end $$;

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
  perform public.wh_use(o.company_id, o.warehouse_id::text);
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

-- receipts go to the PO's warehouse (or the one chosen) and record batch / expiry per line
create or replace function public.grn_post(p_order uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare o public.purchase_orders; l jsonb; ol public.purchase_order_lines; it public.items; q numeric; v numeric; gid uuid; tot numeric := 0;
  d date := coalesce((p_doc->>'date')::date, current_date); w uuid; bt text; ex date;
begin
  select * into o from public.purchase_orders where id = p_order for update;
  if not found then raise exception 'الأمر غير موجود'; end if;
  if not (public.fin_can(o.company_id, 'purch') or public.fin_can(o.company_id, 'stock')) then
    raise exception 'غير مصرح: تحتاج صلاحية المشتريات أو المخزون' using errcode = '42501'; end if;
  if o.status <> 'open' then raise exception 'الأمر ليس مفتوحاً'; end if;
  w := public.wh_use(o.company_id, coalesce(nullif(p_doc->>'warehouse', ''), o.warehouse_id::text));
  if d > current_date or d < o.date then raise exception 'تاريخ الاستلام بين تاريخ الأمر واليوم'; end if;
  if not exists(select 1 from jsonb_array_elements(coalesce(p_doc->'lines', '[]')) x where (x->>'qty')::numeric > 0) then raise exception 'أدخل كمية مستلمة لبند واحد على الأقل'; end if;
  insert into public.goods_receipts(company_id, no, order_id, party_id, date, supplier_doc, note, warehouse_id)
  values (o.company_id, public.next_doc_no(o.company_id, 'GRN'), o.id, o.party_id, d, nullif(trim(p_doc->>'supplier_doc'), ''), nullif(trim(p_doc->>'note'), ''), w)
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
    v := 0; bt := nullif(trim(l->>'batch'), ''); ex := nullif(l->>'expiry', '')::date;
    if it.track_expiry and ex is null then raise exception 'أدخل تاريخ الصلاحية لـ «%»', it.name; end if;
    if ex is not null and ex < d then raise exception 'تاريخ صلاحية «%» منتهٍ', it.name; end if;
    if it.type = 'stock' then
      v := round(q * ol.unit_price, 2);
      insert into public.stock_moves(company_id, item_id, warehouse_id, date, qty, value, source, source_id, batch, expiry, note) values (o.company_id, it.id, w, d, q, v, 'purchase', gid, bt, ex, 'استلام ' || o.no);
      tot := tot + v;
    end if;
    insert into public.goods_receipt_lines(receipt_id, order_line, item_id, qty, value, batch, expiry) values (gid, ol.id, ol.item_id, q, v, bt, ex);
    update public.purchase_order_lines set received = received + q where id = ol.id;
  end loop;
  if tot > 0 then
    perform public.ensure_grni(o.company_id);
    perform public.post_journal(o.company_id, d, 'استلام بضاعة — أمر شراء ' || o.no, 'purchase', gid,
      jsonb_build_array(jsonb_build_object('a','1300','d',tot), jsonb_build_object('a','2150','c',tot)));
  end if;
  return gid;
end $$;

-- ---------- warehouses management ----------
create or replace function public.warehouse_save(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare wid uuid := nullif(p_doc->>'id', '')::uuid; act boolean := coalesce((p_doc->>'active')::boolean, true);
begin
  perform public.require_fin(p_company, 'items');
  if wid is null then
    insert into public.warehouses(company_id, code, name, name_en) values (p_company, upper(trim(p_doc->>'code')), trim(p_doc->>'name'), nullif(trim(p_doc->>'name_en'), ''))
    returning id into wid;
  else
    if not exists(select 1 from public.warehouses where id = wid and company_id = p_company) then raise exception 'المستودع غير موجود'; end if;
    if not act and exists(select 1 from public.warehouses where id = wid and is_default) then raise exception 'لا يُوقف المستودع الافتراضي'; end if;
    if not act and exists(select 1 from public.stock_moves where warehouse_id = wid group by item_id having abs(sum(qty)) > 0.0005) then
      raise exception 'لا يُوقف مستودع فيه رصيد — حوّل الكميات أولاً'; end if;
    update public.warehouses set code = upper(trim(p_doc->>'code')), name = trim(p_doc->>'name'), name_en = nullif(trim(p_doc->>'name_en'), ''), active = act where id = wid;
  end if;
  return wid;
exception when unique_violation then raise exception 'رمز المستودع مستخدم';
end $$;

create or replace function public.warehouse_set_default(p_company uuid, p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'items');
  if not exists(select 1 from public.warehouses where id = p_id and company_id = p_company and active) then raise exception 'المستودع غير موجود أو موقوف'; end if;
  update public.warehouses set is_default = false where company_id = p_company and is_default;
  update public.warehouses set is_default = true where id = p_id;
end $$;

-- quantities per item and warehouse (value at the company average cost)
create or replace function public.stock_levels(p_company uuid)
returns table(item_id uuid, warehouse_id uuid, qty numeric, value numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.fin_can(p_company, 'stock') or public.fin_can(p_company, 'sales') or public.fin_can(p_company, 'purch')) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query
  select m.item_id, m.warehouse_id, sum(m.qty)::numeric, round(sum(m.qty) * (select s.avg_cost from public.stock_state(m.item_id) s), 2)
  from public.stock_moves m where m.company_id = p_company group by m.item_id, m.warehouse_id having abs(sum(m.qty)) > 0.0005;
end $$;

-- ---------- transfers ----------
create table public.stock_transfers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  date date not null,
  from_wh uuid not null references public.warehouses(id),
  to_wh uuid not null references public.warehouses(id),
  note text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  unique (company_id, no),
  check (from_wh <> to_wh)
);
create table public.stock_transfer_lines (
  id bigint generated always as identity primary key,
  transfer_id uuid not null references public.stock_transfers(id) on delete cascade,
  item_id uuid not null references public.items(id),
  qty numeric(14,3) not null check (qty > 0)
);

-- p_doc = {"from","to","date","note","lines":[{"item","qty"}]}
create or replace function public.stock_transfer(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare fw uuid := (p_doc->>'from')::uuid; tw uuid := (p_doc->>'to')::uuid; d date := coalesce((p_doc->>'date')::date, current_date);
  tid uuid; l jsonb; it public.items; q numeric; st record; v numeric; r record; take numeric; left_q numeric;
begin
  perform public.require_fin(p_company, 'stock');
  if fw is null or tw is null or fw = tw then raise exception 'اختر مستودعين مختلفين'; end if;
  if (select count(*) from public.warehouses where id in (fw, tw) and company_id = p_company and active) <> 2 then raise exception 'المستودع غير موجود أو موقوف'; end if;
  if d > current_date then raise exception 'التاريخ لا يكون في المستقبل'; end if;
  if jsonb_array_length(coalesce(p_doc->'lines', '[]')) = 0 then raise exception 'أضف بنداً واحداً على الأقل'; end if;
  insert into public.stock_transfers(company_id, no, date, from_wh, to_wh, note)
  values (p_company, public.next_doc_no(p_company, 'TRF'), d, fw, tw, nullif(trim(p_doc->>'note'), '')) returning id into tid;
  for l in select * from jsonb_array_elements(p_doc->'lines') loop
    q := (l->>'qty')::numeric;
    if q is null or q <= 0 then raise exception 'الكمية أكبر من صفر'; end if;
    select * into it from public.items where id = (l->>'item')::uuid and company_id = p_company and type = 'stock';
    if not found then raise exception 'الصنف غير موجود أو ليس مخزنياً'; end if;
    select * into st from public.stock_state(it.id);
    insert into public.stock_transfer_lines(transfer_id, item_id, qty) values (tid, it.id, q);
    if it.track_expiry then
      -- move batch by batch (earliest expiry first) so the batches arrive intact
      left_q := q;
      for r in select * from public.stock_batches where item_id = it.id and warehouse_id = fw and qty > 0 order by expiry nulls last, id loop
        exit when left_q <= 0;
        take := least(r.qty, left_q); v := round(take * st.avg_cost, 2);
        insert into public.stock_moves(company_id, item_id, warehouse_id, date, qty, value, source, source_id, batch, expiry, note) values (p_company, it.id, fw, d, -take, -v, 'transfer', tid, r.batch, r.expiry, 'تحويل');
        insert into public.stock_moves(company_id, item_id, warehouse_id, date, qty, value, source, source_id, batch, expiry, note) values (p_company, it.id, tw, d, take, v, 'transfer', tid, r.batch, r.expiry, 'تحويل');
        left_q := left_q - take;
      end loop;
      if left_q > 0 then
        v := round(left_q * st.avg_cost, 2);
        insert into public.stock_moves(company_id, item_id, warehouse_id, date, qty, value, source, source_id, note) values (p_company, it.id, fw, d, -left_q, -v, 'transfer', tid, 'تحويل');
        insert into public.stock_moves(company_id, item_id, warehouse_id, date, qty, value, source, source_id, note) values (p_company, it.id, tw, d, left_q, v, 'transfer', tid, 'تحويل');
      end if;
    else
      v := round(q * st.avg_cost, 2);
      insert into public.stock_moves(company_id, item_id, warehouse_id, date, qty, value, source, source_id, note) values (p_company, it.id, fw, d, -q, -v, 'transfer', tid, 'تحويل');
      insert into public.stock_moves(company_id, item_id, warehouse_id, date, qty, value, source, source_id, note) values (p_company, it.id, tw, d, q, v, 'transfer', tid, 'تحويل');
    end if;
  end loop;
  return tid;
end $$;

-- ---------- stock counts ----------
create table public.stock_counts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  warehouse_id uuid not null references public.warehouses(id),
  date date not null,
  status text not null default 'draft' check (status in ('draft','posted','cancelled')),
  note text, gain numeric(14,2) not null default 0, loss numeric(14,2) not null default 0,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(), posted_at timestamptz,
  unique (company_id, no)
);
create table public.stock_count_lines (
  id bigint generated always as identity primary key,
  count_id uuid not null references public.stock_counts(id) on delete cascade,
  item_id uuid not null references public.items(id),
  system_qty numeric(14,3) not null,
  counted numeric(14,3) check (counted is null or counted >= 0),
  posted_qty numeric(14,3),
  diff numeric(14,3),
  value numeric(14,2),
  batch text, expiry date,
  unique (count_id, item_id)
);

-- opens a count sheet with every stock item and its quantity in the warehouse now
create or replace function public.count_open(p_company uuid, p_wh uuid, p_note text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  perform public.require_fin(p_company, 'stockadj');
  if not exists(select 1 from public.warehouses where id = p_wh and company_id = p_company and active) then raise exception 'المستودع غير موجود أو موقوف'; end if;
  if exists(select 1 from public.stock_counts where warehouse_id = p_wh and status = 'draft') then raise exception 'يوجد جرد مفتوح لهذا المستودع'; end if;
  insert into public.stock_counts(company_id, no, warehouse_id, date, note) values (p_company, public.next_doc_no(p_company, 'STC'), p_wh, current_date, nullif(trim(p_note), ''))
  returning id into cid;
  insert into public.stock_count_lines(count_id, item_id, system_qty)
  select cid, i.id, public.wh_qty(i.id, p_wh) from public.items i where i.company_id = p_company and i.type = 'stock' order by i.code;
  return cid;
end $$;

-- p_lines = [{"id": <line id>, "counted": n|null, "batch", "expiry"}]
create or replace function public.count_save(p_id uuid, p_lines jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare c public.stock_counts; l jsonb;
begin
  select * into c from public.stock_counts where id = p_id for update;
  if not found then raise exception 'الجرد غير موجود'; end if;
  perform public.require_fin(c.company_id, 'stockadj');
  if c.status <> 'draft' then raise exception 'الجرد مرحّل أو ملغى'; end if;
  for l in select * from jsonb_array_elements(coalesce(p_lines, '[]')) loop
    if nullif(l->>'counted', '') is not null and (l->>'counted')::numeric < 0 then raise exception 'الكمية لا تكون سالبة'; end if;
    update public.stock_count_lines set counted = nullif(l->>'counted', '')::numeric, batch = nullif(trim(l->>'batch'), ''), expiry = nullif(l->>'expiry', '')::date
    where id = (l->>'id')::bigint and count_id = p_id;
  end loop;
end $$;

-- books the differences against the quantity in the warehouse at posting time
create or replace function public.count_post(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.stock_counts; l record; cur numeric; df numeric; st record; v numeric; g numeric := 0; lo numeric := 0; n int := 0; wn text;
begin
  select * into c from public.stock_counts where id = p_id for update;
  if not found then raise exception 'الجرد غير موجود'; end if;
  perform public.require_fin(c.company_id, 'stockadj');
  if c.status <> 'draft' then raise exception 'الجرد مرحّل أو ملغى'; end if;
  if not exists(select 1 from public.stock_count_lines where count_id = p_id and counted is not null) then raise exception 'أدخل الكمية المعدودة لصنف واحد على الأقل'; end if;
  select name into wn from public.warehouses where id = c.warehouse_id;
  for l in select cl.*, i.name, i.track_expiry from public.stock_count_lines cl join public.items i on i.id = cl.item_id where cl.count_id = p_id and cl.counted is not null loop
    cur := public.wh_qty(l.item_id, c.warehouse_id); df := l.counted - cur;
    if l.track_expiry and df > 0 and l.expiry is null then raise exception 'أدخل تاريخ الصلاحية للزيادة في «%»', l.name; end if;
    v := 0;
    if df <> 0 then
      select * into st from public.stock_state(l.item_id);
      v := case when st.qty + df = 0 then -st.value else round(df * st.avg_cost, 2) end;
      insert into public.stock_moves(company_id, item_id, warehouse_id, date, qty, value, source, source_id, batch, expiry, note)
      values (c.company_id, l.item_id, c.warehouse_id, current_date, df, v, 'count', p_id, case when df > 0 then l.batch end, case when df > 0 then l.expiry end, 'جرد ' || c.no);
      if v > 0 then g := g + v; else lo := lo - v; end if; n := n + 1;
    end if;
    update public.stock_count_lines set posted_qty = cur, diff = df, value = v where id = l.id;
  end loop;
  if g + lo > 0 then
    perform public.post_journal(c.company_id, current_date, 'جرد ' || c.no || ' — ' || wn, 'stock', p_id, jsonb_build_array(
      jsonb_build_object('a','1300','d',g), jsonb_build_object('a','5600','c',g), jsonb_build_object('a','5600','d',lo), jsonb_build_object('a','1300','c',lo)));
  end if;
  update public.stock_counts set status = 'posted', gain = g, loss = lo, posted_at = now() where id = p_id;
  return jsonb_build_object('lines', n, 'gain', g, 'loss', lo);
end $$;

create or replace function public.count_cancel(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c public.stock_counts;
begin
  select * into c from public.stock_counts where id = p_id for update;
  if not found then raise exception 'الجرد غير موجود'; end if;
  perform public.require_fin(c.company_id, 'stockadj');
  if c.status <> 'draft' then raise exception 'الجرد مرحّل أو ملغى'; end if;
  update public.stock_counts set status = 'cancelled' where id = p_id;
end $$;

-- ---------- adjustment in a chosen warehouse ----------
drop function public.stock_adjust(uuid, uuid, date, numeric, numeric, text);
create or replace function public.stock_adjust(p_company uuid, p_item uuid, p_date date, p_qty numeric, p_unit_cost numeric, p_reason text, p_warehouse uuid default null, p_expiry date default null)
returns void language plpgsql security definer set search_path = public as $$
declare it public.items; st record; v numeric; aid uuid := gen_random_uuid(); w uuid;
begin
  perform public.require_fin(p_company, 'stockadj');
  select * into it from public.items where id = p_item and company_id = p_company and type = 'stock';
  if not found then raise exception 'الصنف غير موجود أو ليس مخزنياً'; end if;
  if coalesce(p_qty,0) = 0 then raise exception 'أدخل كمية التسوية'; end if;
  if p_date > current_date then raise exception 'التاريخ لا يكون في المستقبل'; end if;
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'اكتب سبب التسوية'; end if;
  w := public.wh_use(p_company, p_warehouse::text);
  if it.track_expiry and p_qty > 0 and p_expiry is null then raise exception 'أدخل تاريخ الصلاحية'; end if;
  select * into st from public.stock_state(p_item);
  if p_qty < 0 and public.wh_qty(p_item, w) + p_qty < 0 then raise exception 'العجز أكبر من الرصيد المتوفر في المستودع (%)', public.wh_qty(p_item, w); end if;
  v := case when p_qty > 0 then round(p_qty * coalesce(p_unit_cost, st.avg_cost), 2)
            when st.qty + p_qty = 0 then -st.value else round(p_qty * st.avg_cost, 2) end;
  insert into public.stock_moves(company_id, item_id, warehouse_id, date, qty, value, source, source_id, expiry, note) values (p_company, p_item, w, p_date, p_qty, v, 'adjust', aid, case when p_qty > 0 then p_expiry end, trim(p_reason));
  perform public.post_journal(p_company, p_date, 'تسوية مخزون — ' || it.name, 'stock', aid,
    case when v >= 0 then jsonb_build_array(jsonb_build_object('a','1300','d',v), jsonb_build_object('a','5600','c',v))
         else jsonb_build_array(jsonb_build_object('a','5600','d',-v), jsonb_build_object('a','1300','c',-v)) end);
end $$;

-- ---------- warehouse-aware wrappers for the existing posting RPCs ----------
create or replace function public.post_sales_invoice_wh(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
begin perform public.wh_use(p_company, p_doc->>'warehouse'); return public.post_sales_invoice(p_company, p_doc); end $$;
create or replace function public.post_purchase_bill_wh(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
begin perform public.wh_use(p_company, p_doc->>'warehouse'); return public.post_purchase_bill(p_company, p_doc); end $$;
create or replace function public.sales_doc_save_wh(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
begin perform public.wh_use(p_company, p_doc->>'warehouse'); return public.sales_doc_save(p_company, p_doc); end $$;
create or replace function public.po_save_wh(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
begin perform public.wh_use(p_company, p_doc->>'warehouse'); return public.po_save(p_company, p_doc); end $$;

-- ---------- expiry and reorder reports ----------
create or replace function public.expiry_list(p_company uuid, p_days int default 60)
returns table(item_id uuid, warehouse_id uuid, batch text, expiry date, qty numeric, days_left int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.fin_can(p_company, 'stock') or public.fin_can(p_company, 'sales')) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query select b.item_id, b.warehouse_id, b.batch, b.expiry, b.qty, (b.expiry - current_date)::int
  from public.stock_batches b where b.company_id = p_company and b.qty > 0.0005 and b.expiry is not null and b.expiry <= current_date + coalesce(p_days, 60)
  order by b.expiry, b.item_id;
end $$;

create or replace function public.reorder_list(p_company uuid)
returns table(item_id uuid, on_hand numeric, on_order numeric, reorder_level numeric, suggested numeric, last_supplier uuid, last_price numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.fin_can(p_company, 'stock') or public.fin_can(p_company, 'purch')) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query
  with oh as (select m.item_id, sum(m.qty) q from public.stock_moves m where m.company_id = p_company group by m.item_id),
       oo as (select l.item_id, sum(l.qty - l.received) q from public.purchase_order_lines l join public.purchase_orders o on o.id = l.order_id
              where o.company_id = p_company and o.status = 'open' and l.item_id is not null group by l.item_id),
       lp as (select distinct on (bl.item_id) bl.item_id, b.party_id, bl.unit_price from public.purchase_bill_lines bl join public.purchase_bills b on b.id = bl.bill_id
              where b.company_id = p_company and b.status = 'posted' and bl.item_id is not null order by bl.item_id, b.date desc, b.created_at desc)
  select i.id, coalesce(oh.q, 0)::numeric, coalesce(oo.q, 0)::numeric, i.reorder_level,
         greatest(i.reorder_qty, i.reorder_level * 2 - coalesce(oh.q, 0) - coalesce(oo.q, 0), 1)::numeric, lp.party_id, lp.unit_price
  from public.items i left join oh on oh.item_id = i.id left join oo on oo.item_id = i.id left join lp on lp.item_id = i.id
  where i.company_id = p_company and i.type = 'stock' and i.reorder_level > 0 and coalesce(oh.q, 0) + coalesce(oo.q, 0) <= i.reorder_level
  order by i.code;
end $$;

-- ---------- RLS, audit, grants ----------
alter table public.warehouses enable row level security;
alter table public.stock_batches enable row level security;
alter table public.stock_transfers enable row level security;
alter table public.stock_transfer_lines enable row level security;
alter table public.stock_counts enable row level security;
alter table public.stock_count_lines enable row level security;
create policy wh_read on public.warehouses for select using (public.fin(company_id));
create policy sb_read on public.stock_batches for select using (public.fin_can(company_id, 'stock') or public.fin_can(company_id, 'sales'));
create policy st_read on public.stock_transfers for select using (public.fin_can(company_id, 'stock'));
create policy stl_read on public.stock_transfer_lines for select using (exists(select 1 from public.stock_transfers t where t.id = transfer_id));
create policy sc_read on public.stock_counts for select using (public.fin_can(company_id, 'stock') or public.fin_can(company_id, 'stockadj'));
create policy scl_read on public.stock_count_lines for select using (exists(select 1 from public.stock_counts c where c.id = count_id));
create trigger audit_warehouses after insert or update on public.warehouses for each row execute function public.audit_trigger();
create trigger audit_stock_transfers after insert on public.stock_transfers for each row execute function public.audit_trigger();
create trigger audit_stock_counts after insert or update on public.stock_counts for each row execute function public.audit_trigger();
create trigger stl_immutable before update or delete on public.stock_transfer_lines for each row execute function public.block_change();

revoke all on public.warehouses, public.stock_batches, public.stock_transfers, public.stock_transfer_lines, public.stock_counts, public.stock_count_lines from anon;
revoke insert, update, delete on public.warehouses, public.stock_batches, public.stock_transfers, public.stock_transfer_lines, public.stock_counts, public.stock_count_lines from authenticated;
grant select on public.warehouses, public.stock_batches, public.stock_transfers, public.stock_transfer_lines, public.stock_counts, public.stock_count_lines to authenticated;

revoke all on function public.wh_default(uuid), public.wh_use(uuid, text), public.wh_cfg(uuid), public.wh_qty(uuid, uuid), public.doc_wh(), public.sm_before(), public.sm_batches(),
  public.warehouse_save(uuid, jsonb), public.warehouse_set_default(uuid, uuid), public.stock_levels(uuid), public.stock_transfer(uuid, jsonb),
  public.count_open(uuid, uuid, text), public.count_save(uuid, jsonb), public.count_post(uuid), public.count_cancel(uuid),
  public.stock_adjust(uuid, uuid, date, numeric, numeric, text, uuid, date), public.post_sales_invoice_wh(uuid, jsonb), public.post_purchase_bill_wh(uuid, jsonb),
  public.sales_doc_save_wh(uuid, jsonb), public.po_save_wh(uuid, jsonb), public.expiry_list(uuid, int), public.reorder_list(uuid) from public, anon, authenticated;
grant execute on function public.warehouse_save(uuid, jsonb), public.warehouse_set_default(uuid, uuid), public.stock_levels(uuid), public.stock_transfer(uuid, jsonb),
  public.count_open(uuid, uuid, text), public.count_save(uuid, jsonb), public.count_post(uuid), public.count_cancel(uuid),
  public.stock_adjust(uuid, uuid, date, numeric, numeric, text, uuid, date), public.post_sales_invoice_wh(uuid, jsonb), public.post_purchase_bill_wh(uuid, jsonb),
  public.sales_doc_save_wh(uuid, jsonb), public.po_save_wh(uuid, jsonb), public.expiry_list(uuid, int), public.reorder_list(uuid) to authenticated;
