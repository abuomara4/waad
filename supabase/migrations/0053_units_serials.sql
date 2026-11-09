-- Waad ERP — 0053 inventory: extra units per item (carton = 24 pieces, each may have its own barcode) and serial numbers.
-- Quantities stay in the item's base unit everywhere; the screen converts. Serial-tracked items need one serial per piece
-- on goods receipt (in) and on sales invoice / delivery note (out); voiding the document reverses its serials.

create table if not exists public.item_units (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  item_id uuid not null references public.items(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 30),
  name_en text,
  factor numeric(14,4) not null check (factor > 0 and factor <> 1),
  barcode text,
  unique (item_id, name)
);
create unique index if not exists item_units_barcode_uq on public.item_units(company_id, barcode) where barcode is not null;
alter table public.item_units enable row level security;
drop policy if exists iu_read on public.item_units;
create policy iu_read on public.item_units for select using (public.fin_can(company_id, 'stock') or public.fin_can(company_id, 'sales') or public.fin_can(company_id, 'purch'));
drop policy if exists iu_write on public.item_units;
create policy iu_write on public.item_units for all using (public.fin_can(company_id, 'items'))
  with check (public.fin_can(company_id, 'items') and exists(select 1 from public.items i where i.id = item_id and i.company_id = item_units.company_id));
revoke all on public.item_units from anon;
grant select, insert, update, delete on public.item_units to authenticated;

create or replace function public.item_unit_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  new.name := trim(new.name);
  new.barcode := nullif(replace(trim(coalesce(new.barcode, '')), ' ', ''), '');
  if new.barcode is not null and exists(select 1 from public.items where company_id = new.company_id and barcode = new.barcode) then
    raise exception 'الباركود مستخدم لصنف آخر'; end if;
  return new;
end $$;
drop trigger if exists item_units_guard on public.item_units;
create trigger item_units_guard before insert or update on public.item_units for each row execute function public.item_unit_guard();

-- ---------- serial numbers ----------
alter table public.items add column if not exists track_serial boolean not null default false;
create table if not exists public.item_serials (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  item_id uuid not null references public.items(id),
  serial text not null check (length(serial) between 1 and 60),
  status text not null default 'in_stock' check (status in ('in_stock','sold')),
  warehouse_id uuid references public.warehouses(id),
  in_kind text, in_id uuid, in_date date,
  out_kind text, out_id uuid, out_date date,
  created_at timestamptz not null default now(),
  unique (item_id, serial)
);
create index if not exists item_serials_item on public.item_serials(company_id, item_id, status);
alter table public.item_serials enable row level security;
drop policy if exists isn_read on public.item_serials;
create policy isn_read on public.item_serials for select using (public.fin_can(company_id, 'stock') or public.fin_can(company_id, 'sales') or public.fin_can(company_id, 'purch'));
revoke all on public.item_serials from anon, authenticated;
grant select on public.item_serials to authenticated;

create or replace function public.sn_list(p jsonb) returns text[] language sql immutable as $$
  select coalesce(array_agg(distinct trim(x)) filter (where trim(x) <> ''), '{}') from jsonb_array_elements_text(coalesce(p, '[]')) x
$$;
-- take serials out of stock for a document; every tracked item line must carry exactly qty serials
create or replace function public.sn_out(p_company uuid, p_item uuid, p_qty numeric, p_serials jsonb, p_kind text, p_id uuid, p_date date) returns void
language plpgsql security definer set search_path = public as $$
declare it public.items; s text[] := public.sn_list(p_serials); bad text;
begin
  select * into it from public.items where id = p_item;
  if not it.track_serial then return; end if;
  if cardinality(s) <> p_qty then raise exception 'الصنف «%» يحتاج % رقماً تسلسلياً (أُدخل %)', it.name, p_qty, cardinality(s); end if;
  select string_agg(x, '، ') into bad from unnest(s) x
   where not exists(select 1 from public.item_serials where company_id = p_company and item_id = p_item and serial = x and status = 'in_stock');
  if bad is not null then raise exception 'أرقام تسلسلية غير متوفرة في المخزون للصنف «%»: %', it.name, bad; end if;
  update public.item_serials set status = 'sold', out_kind = p_kind, out_id = p_id, out_date = p_date
   where company_id = p_company and item_id = p_item and serial = any(s);
end $$;
create or replace function public.sn_in(p_company uuid, p_item uuid, p_qty numeric, p_serials jsonb, p_wh uuid, p_kind text, p_id uuid, p_date date) returns void
language plpgsql security definer set search_path = public as $$
declare it public.items; s text[] := public.sn_list(p_serials); dup text;
begin
  select * into it from public.items where id = p_item;
  if not it.track_serial then return; end if;
  if cardinality(s) <> p_qty then raise exception 'الصنف «%» يحتاج % رقماً تسلسلياً (أُدخل %)', it.name, p_qty, cardinality(s); end if;
  select string_agg(x, '، ') into dup from unnest(s) x where exists(select 1 from public.item_serials where item_id = p_item and serial = x);
  if dup is not null then raise exception 'أرقام تسلسلية مسجلة من قبل للصنف «%»: %', it.name, dup; end if;
  insert into public.item_serials(company_id, item_id, serial, warehouse_id, in_kind, in_id, in_date)
  select p_company, p_item, x, p_wh, p_kind, p_id, p_date from unnest(s) x;
end $$;

-- wrappers used by the screens: same documents, plus serials per line
create or replace function public.grn_post_sn(p_order uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare gid uuid; g public.goods_receipts; l jsonb; ol public.purchase_order_lines;
begin
  gid := public.grn_post(p_order, p_doc);
  select * into g from public.goods_receipts where id = gid;
  for l in select * from jsonb_array_elements(p_doc->'lines') loop
    continue when coalesce((l->>'qty')::numeric, 0) = 0;
    select * into ol from public.purchase_order_lines where id = (l->>'line')::bigint;
    if ol.item_id is not null then perform public.sn_in(g.company_id, ol.item_id, (l->>'qty')::numeric, l->'serials', g.warehouse_id, 'grn', gid, g.date); end if;
  end loop;
  return gid;
end $$;
create or replace function public.delivery_post_sn(p_order uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare nid uuid; n public.delivery_notes; l jsonb; ol public.sales_order_lines;
begin
  nid := public.delivery_post(p_order, p_doc);
  select * into n from public.delivery_notes where id = nid;
  for l in select * from jsonb_array_elements(p_doc->'lines') loop
    continue when coalesce((l->>'qty')::numeric, 0) = 0;
    select * into ol from public.sales_order_lines where id = (l->>'line')::bigint;
    perform public.sn_out(n.company_id, ol.item_id, (l->>'qty')::numeric, l->'serials', 'delivery', nid, n.date);
  end loop;
  return nid;
end $$;
create or replace function public.post_sales_invoice_sn(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare iid uuid; d date; l jsonb; it public.items;
begin
  iid := public.post_sales_invoice_wh(p_company, p_doc);
  select date into d from public.sales_invoices where id = iid;
  for l in select x from jsonb_array_elements(p_doc->'lines') x loop
    continue when nullif(l->>'item', '') is null;
    select * into it from public.items where id = (l->>'item')::uuid;
    if it.type = 'stock' then perform public.sn_out(p_company, it.id, (l->>'qty')::numeric, l->'serials', 'invoice', iid, d); end if;
  end loop;
  return iid;
end $$;

-- voiding a document gives its serials back (a receipt whose serials were already sold cannot be voided)
create or replace function public.sn_void() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'void' and old.status <> 'void' then
    if tg_table_name = 'goods_receipts' then
      if exists(select 1 from public.item_serials where in_kind = 'grn' and in_id = new.id and status = 'sold') then
        raise exception 'بيعت أرقام تسلسلية من هذا الاستلام — لا يُلغى'; end if;
      delete from public.item_serials where in_kind = 'grn' and in_id = new.id;
    else
      update public.item_serials set status = 'in_stock', out_kind = null, out_id = null, out_date = null
       where out_id = new.id and out_kind = case tg_table_name when 'delivery_notes' then 'delivery' else 'invoice' end;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists goods_receipts_sn on public.goods_receipts;
create trigger goods_receipts_sn after update of status on public.goods_receipts for each row execute function public.sn_void();
drop trigger if exists delivery_notes_sn on public.delivery_notes;
create trigger delivery_notes_sn after update of status on public.delivery_notes for each row execute function public.sn_void();
drop trigger if exists sales_invoices_sn on public.sales_invoices;
create trigger sales_invoices_sn after update of status on public.sales_invoices for each row execute function public.sn_void();

-- where is serial X? (search by serial across items)
create or replace function public.serial_find(p_company uuid, p_serial text)
returns table(item_id uuid, serial text, status text, warehouse_id uuid, in_kind text, in_id uuid, in_date date, out_kind text, out_id uuid, out_date date)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.fin_can(p_company, 'stock') or public.fin_can(p_company, 'sales') or public.fin_can(p_company, 'purch')) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query select s.item_id, s.serial, s.status, s.warehouse_id, s.in_kind, s.in_id, s.in_date, s.out_kind, s.out_id, s.out_date
    from public.item_serials s where s.company_id = p_company and s.serial ilike '%' || trim(p_serial) || '%' order by s.serial limit 50;
end $$;

-- a serial-tracked item can only be switched on/off while it has no stock
create or replace function public.item_serial_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if tg_op = 'UPDATE' and new.track_serial is distinct from old.track_serial and exists(select 1 from public.stock_moves where item_id = new.id) then
    raise exception 'لا يتغير تتبع الأرقام التسلسلية بعد وجود حركة مخزون للصنف'; end if;
  if new.track_serial and new.type <> 'stock' then raise exception 'الأرقام التسلسلية للأصناف المخزنية فقط'; end if;
  return new;
end $$;
drop trigger if exists items_serial_guard on public.items;
create trigger items_serial_guard before insert or update of track_serial on public.items for each row execute function public.item_serial_guard();

revoke all on function public.item_unit_guard(), public.sn_void(), public.item_serial_guard(),
  public.sn_out(uuid, uuid, numeric, jsonb, text, uuid, date), public.sn_in(uuid, uuid, numeric, jsonb, uuid, text, uuid, date) from public, anon, authenticated;
revoke all on function public.grn_post_sn(uuid, jsonb), public.delivery_post_sn(uuid, jsonb), public.post_sales_invoice_sn(uuid, jsonb),
  public.serial_find(uuid, text), public.sn_list(jsonb) from public, anon;
grant execute on function public.grn_post_sn(uuid, jsonb), public.delivery_post_sn(uuid, jsonb), public.post_sales_invoice_sn(uuid, jsonb),
  public.serial_find(uuid, text), public.sn_list(jsonb) to authenticated;
notify pgrst, 'reload schema';
