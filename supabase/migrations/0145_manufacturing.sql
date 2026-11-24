-- Manufacturing and materials planning (MRP). A bill of materials (BOM) says what one batch of a made item consumes; a
-- production order makes a quantity: completing it takes the components out of the warehouse at their average cost and puts
-- the finished item in at that cost plus the batch's extra cost (labour / overhead, company policy). Inventory moves from
-- component to finished goods inside 1300, so only the extra cost is posted: Dr 1300 / Cr 5190 «تكاليف تصنيع محمّلة».
-- The plan (mrp_plan): demand = open sales orders not yet delivered + components open production orders will use + the reorder
-- level; supply = stock on hand + open purchase
-- orders not yet received + open production orders; what is missing is to be made (it has a BOM — its components are then
-- needed in turn, every level) or bought. Part of the stock module (permission 'stock'; buying suggestions also for 'purch').

create table if not exists public.boms (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  item_id uuid not null references public.items(id) on delete cascade,
  output_qty numeric(14,3) not null default 1 check (output_qty > 0),
  extra_cost numeric(14,2) not null default 0 check (extra_cost >= 0),
  note text check (note is null or length(note) <= 500),
  updated_at timestamptz not null default now(),
  unique (company_id, item_id)
);
create table if not exists public.bom_lines (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  bom_id uuid not null references public.boms(id) on delete cascade,
  item_id uuid not null references public.items(id),
  qty numeric(14,4) not null check (qty > 0),
  scrap_pct numeric(5,2) not null default 0 check (scrap_pct between 0 and 90)
);
create index if not exists bom_lines_bom on public.bom_lines(bom_id);
create index if not exists bom_lines_item on public.bom_lines(item_id);
create index if not exists bom_lines_company on public.bom_lines(company_id);
create index if not exists boms_item on public.boms(item_id);

create table if not exists public.production_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  item_id uuid not null references public.items(id),
  qty numeric(14,3) not null check (qty > 0),
  warehouse_id uuid references public.warehouses(id),
  planned_date date not null default current_date,
  status text not null default 'open' check (status in ('open','done','cancelled')),
  done_on date, material_cost numeric(14,2), extra_cost numeric(14,2), total_cost numeric(14,2), entry_id uuid references public.journal_entries(id),
  note text check (note is null or length(note) <= 500),
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  unique (company_id, no)
);
create index if not exists production_orders_open on public.production_orders(company_id, status);
create index if not exists production_orders_item on public.production_orders(item_id);
create index if not exists production_orders_wh on public.production_orders(warehouse_id);
create index if not exists production_orders_entry on public.production_orders(entry_id);

do $$ declare t text;
begin
  foreach t in array array['boms','bom_lines','production_orders'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I_read on public.%I', t, t);
    execute format('create policy %I_read on public.%I for select using (public.fin_can(company_id, ''stock'') or public.fin_can(company_id, ''purch''))', t, t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

alter table public.stock_moves drop constraint if exists stock_moves_source_check;
alter table public.stock_moves add constraint stock_moves_source_check check (source in ('purchase','sale','adjust','void','return','transfer','count','production'));
alter table public.journal_entries drop constraint if exists journal_entries_source_check;
alter table public.journal_entries add constraint journal_entries_source_check check (source in ('manual','reversal','sales','purchase','receipt','payment',
  'stock','payroll','payroll_pay','advance','expense','opening','sales_return','purchase_return','asset','depreciation','cheque','closing','petty','trip','vehicle',
  'prepaid','bank','loan','guarantee','zakat','project','pos','production'));

-- save the BOM of an item (replaces its lines). p = {output_qty, extra_cost, note, lines:[{item, qty, scrap}]}. Components are
-- stock items of the company, not the item itself, and never lead back to it (no loops at any level).
create or replace function public.bom_save(p_company uuid, p_item uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare bid uuid; l jsonb; it public.items; ci public.items; n int := 0;
begin
  perform public.require_fin(p_company, 'stock');
  select * into it from public.items where id = p_item and company_id = p_company;
  if not found or it.type <> 'stock' then raise exception 'الصنف المصنّع يكون صنفا مخزنيا'; end if;
  if it.track_serial then raise exception 'الأصناف ذات الأرقام التسلسلية لا تُصنّع هنا بعد'; end if;
  if coalesce((p->>'output_qty')::numeric, 1) <= 0 then raise exception 'كمية الإنتاج أكبر من صفر'; end if;
  insert into public.boms(company_id, item_id, output_qty, extra_cost, note) values (p_company, p_item, coalesce((p->>'output_qty')::numeric, 1), coalesce((p->>'extra_cost')::numeric, 0), nullif(btrim(coalesce(p->>'note', '')), ''))
  on conflict (company_id, item_id) do update set output_qty = excluded.output_qty, extra_cost = excluded.extra_cost, note = excluded.note, updated_at = now()
  returning id into bid;
  delete from public.bom_lines where bom_id = bid;
  for l in select x from jsonb_array_elements(coalesce(p->'lines', '[]')) x loop
    select * into ci from public.items where id = nullif(l->>'item', '')::uuid and company_id = p_company;
    if not found or ci.type <> 'stock' then raise exception 'المكوّن يكون صنفا مخزنيا من أصناف المنشأة'; end if;
    if ci.id = p_item then raise exception 'الصنف لا يكون مكوّنا لنفسه'; end if;
    if ci.track_serial or ci.track_expiry then raise exception 'المكوّن «%» يتتبع أرقاما تسلسلية أو تواريخ صلاحية — لا يُستهلك في التصنيع هنا بعد', ci.name; end if;
    if coalesce((l->>'qty')::numeric, 0) <= 0 then raise exception 'كمية المكوّن أكبر من صفر'; end if;
    insert into public.bom_lines(company_id, bom_id, item_id, qty, scrap_pct) values (p_company, bid, ci.id, (l->>'qty')::numeric, coalesce((l->>'scrap')::numeric, 0));
    n := n + 1;
  end loop;
  if n = 0 then raise exception 'أضف مكوّنا واحدا على الأقل'; end if;
  -- no loop: the item must not appear among the components of its components, at any depth
  if exists(with recursive r(item) as (select bl.item_id from public.bom_lines bl where bl.bom_id = bid
              union select bl.item_id from r join public.boms b on b.item_id = r.item and b.company_id = p_company join public.bom_lines bl on bl.bom_id = b.id)
            select 1 from r where r.item = p_item) then
    raise exception 'المكوّنات تعود إلى الصنف نفسه (حلقة)'; end if;
  return bid;
end $$;

create or replace function public.bom_delete(p_company uuid, p_item uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'stock');
  if exists(select 1 from public.production_orders where company_id = p_company and item_id = p_item and status = 'open') then raise exception 'للصنف أوامر إنتاج مفتوحة'; end if;
  delete from public.boms where company_id = p_company and item_id = p_item;
end $$;

-- a production order (open); p = {item, qty, warehouse, date, note}
create or replace function public.mo_save(p_company uuid, p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare id_ uuid; it uuid := nullif(p->>'item', '')::uuid; q numeric := (p->>'qty')::numeric;
begin
  perform public.require_fin(p_company, 'stock');
  if not exists(select 1 from public.boms where company_id = p_company and item_id = it) then raise exception 'عرّف مكوّنات الصنف أولا'; end if;
  if q is null or q <= 0 then raise exception 'أدخل الكمية'; end if;
  insert into public.production_orders(company_id, no, item_id, qty, warehouse_id, planned_date, note)
  values (p_company, public.next_doc_no(p_company, 'MO'), it, q, public.wh_use(p_company, p->>'warehouse'), coalesce(nullif(p->>'date', '')::date, current_date), nullif(btrim(coalesce(p->>'note', '')), ''))
  returning id into id_;
  return id_;
end $$;

create or replace function public.mo_cancel(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare o public.production_orders;
begin
  select * into o from public.production_orders where id = p_id for update;
  if not found then raise exception 'أمر الإنتاج غير موجود'; end if;
  perform public.require_fin(o.company_id, 'stock');
  if o.status <> 'open' then raise exception 'أمر الإنتاج ليس مفتوحا'; end if;
  update public.production_orders set status = 'cancelled' where id = p_id;
end $$;

-- what completing an order would take: each component, the quantity (with scrap) and what the warehouse holds
create or replace function public.mo_needs(p_id uuid) returns table(item_id uuid, code text, name text, unit text, need numeric, available numeric, avg_cost numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare o public.production_orders; b public.boms;
begin
  select * into o from public.production_orders where id = p_id;
  if not found or not (public.fin_can(o.company_id, 'stock') or public.fin_can(o.company_id, 'purch')) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  select * into b from public.boms where company_id = o.company_id and item_id = o.item_id;
  return query select i.id, i.code, i.name, i.unit, round(l.qty * o.qty / b.output_qty * (1 + l.scrap_pct / 100), 3),
    public.wh_qty(i.id, o.warehouse_id), round((public.stock_state(i.id)).avg_cost, 4)
    from public.bom_lines l join public.items i on i.id = l.item_id where l.bom_id = b.id order by i.name;
end $$;

-- complete: components out at average cost, the finished item in at that cost + the extra cost of the batches
create or replace function public.mo_complete(p_id uuid, p_date date default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare o public.production_orders; b public.boms; r record; st record; v numeric; mat numeric := 0; ext numeric; d date := coalesce(p_date, current_date); eid uuid; it public.items;
begin
  select * into o from public.production_orders where id = p_id for update;
  if not found then raise exception 'أمر الإنتاج غير موجود'; end if;
  perform public.require_fin(o.company_id, 'stock');
  if o.status <> 'open' then raise exception 'أمر الإنتاج ليس مفتوحا'; end if;
  if d > current_date then raise exception 'التاريخ لا يكون في المستقبل'; end if;
  select * into b from public.boms where company_id = o.company_id and item_id = o.item_id;
  if not found then raise exception 'عرّف مكوّنات الصنف أولا'; end if;
  select * into it from public.items where id = o.item_id;
  for r in select * from public.mo_needs(p_id) loop
    if r.available < r.need then raise exception 'الكمية المتوفرة من «%» في المستودع % والمطلوب %', r.name, r.available, r.need; end if;
    select * into st from public.stock_state(r.item_id);
    v := case when st.qty = r.need then st.value else round(r.need * st.avg_cost, 2) end;
    insert into public.stock_moves(company_id, item_id, warehouse_id, date, qty, value, source, source_id, note)
    values (o.company_id, r.item_id, o.warehouse_id, d, -r.need, -v, 'production', o.id, 'صرف لأمر الإنتاج ' || o.no);
    mat := mat + v;
  end loop;
  ext := round(b.extra_cost * o.qty / b.output_qty, 2);
  insert into public.stock_moves(company_id, item_id, warehouse_id, date, qty, value, source, source_id, note)
  values (o.company_id, o.item_id, o.warehouse_id, d, o.qty, mat + ext, 'production', o.id, 'إنتاج — أمر ' || o.no);
  if ext > 0 then
    insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header)
    select o.company_id, '5190', 'تكاليف تصنيع محمّلة', 'Manufacturing costs absorbed', 'exp', '5000', false
     where not exists(select 1 from public.accounts where company_id = o.company_id and code = '5190');
    eid := public.post_journal(o.company_id, d, 'تكاليف تصنيع محمّلة — أمر ' || o.no || ' — ' || it.name, 'production', o.id,
      jsonb_build_array(jsonb_build_object('a', '1300', 'd', ext), jsonb_build_object('a', '5190', 'c', ext)));
  end if;
  update public.production_orders set status = 'done', done_on = d, material_cost = mat, extra_cost = ext, total_cost = mat + ext, entry_id = eid where id = p_id;
  return jsonb_build_object('material', mat, 'extra', ext, 'total', mat + ext, 'unit_cost', round((mat + ext) / o.qty, 4));
end $$;

-- the materials plan: for every stock item, demand against supply, what is missing, and whether to make or buy it
create or replace function public.mrp_plan(p_company uuid)
returns table(item_id uuid, code text, name text, unit text, make boolean, on_hand numeric, demand numeric, dependent numeric, reorder_level numeric,
              incoming numeric, net numeric, suggest numeric, reorder_qty numeric, supplier_hint uuid)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare st jsonb; pl jsonb := '{}'; dp jsonb := '{}'; pass int;
begin
  if not (public.fin_can(p_company, 'stock') or public.fin_can(p_company, 'purch')) then raise exception 'خطة المواد لصلاحية المخزون أو المشتريات' using errcode = '42501'; end if;
  select coalesce(jsonb_object_agg(i.id::text, jsonb_build_object(
    'onh', coalesce((select sum(m.qty) from public.stock_moves m where m.item_id = i.id), 0),
    'dem', coalesce((select sum(l.qty - greatest(l.delivered, l.invoiced)) from public.sales_order_lines l join public.sales_orders o on o.id = l.order_id
                      where o.company_id = p_company and o.kind = 'order' and o.status = 'open' and l.item_id = i.id), 0),
    -- components open production orders will consume
    'mon', coalesce((select sum(bl.qty * p.qty / b.output_qty * (1 + bl.scrap_pct / 100)) from public.production_orders p join public.boms b on b.company_id = p.company_id and b.item_id = p.item_id
                      join public.bom_lines bl on bl.bom_id = b.id where p.company_id = p_company and p.status = 'open' and bl.item_id = i.id), 0),
    'rl', coalesce(i.reorder_level, 0),
    'inc', coalesce((select sum(l.qty - l.received) from public.purchase_order_lines l join public.purchase_orders o on o.id = l.order_id
                      where o.company_id = p_company and o.status = 'open' and l.item_id = i.id), 0)
         + coalesce((select sum(p.qty) from public.production_orders p where p.company_id = p_company and p.item_id = i.id and p.status = 'open'), 0),
    'mk', exists(select 1 from public.boms b where b.company_id = p_company and b.item_id = i.id))), '{}')
    into st from public.items i where i.company_id = p_company and i.type = 'stock' and coalesce(i.active, true);
  -- planned production of made items creates demand for their components, level by level (BOMs have no loops)
  for pass in 1..12 loop
    select coalesce(jsonb_object_agg(e.k, greatest(0, (e.v->>'dem')::numeric + (e.v->>'mon')::numeric + coalesce((dp->>e.k)::numeric, 0) + (e.v->>'rl')::numeric - (e.v->>'onh')::numeric - (e.v->>'inc')::numeric)), '{}')
      into pl from jsonb_each(st) e(k, v) where (e.v->>'mk')::boolean;
    select coalesce(jsonb_object_agg(x.cid, x.s), '{}') into dp from (
      select bl.item_id::text cid, sum((pl->>b.item_id::text)::numeric * bl.qty / b.output_qty * (1 + bl.scrap_pct / 100)) s
        from public.bom_lines bl join public.boms b on b.id = bl.bom_id where b.company_id = p_company and pl ? b.item_id::text group by bl.item_id) x;
  end loop;
  return query
  with t as (select e.k::uuid id, (e.v->>'mk')::boolean mk, (e.v->>'onh')::numeric onh, (e.v->>'dem')::numeric dem, coalesce((dp->>e.k)::numeric, 0) + (e.v->>'mon')::numeric dep,
                    (e.v->>'rl')::numeric rl, (e.v->>'inc')::numeric inc from jsonb_each(st) e(k, v))
  select i.id, i.code, i.name, i.unit, t.mk, t.onh, t.dem, round(t.dep, 3), t.rl, t.inc,
         round(greatest(0, t.dem + t.dep + t.rl - t.onh - t.inc), 3),
         case when t.mk then round(greatest(0, t.dem + t.dep + t.rl - t.onh - t.inc), 3)
              else greatest(round(greatest(0, t.dem + t.dep + t.rl - t.onh - t.inc), 3), coalesce(i.reorder_qty, 0)) end,
         i.reorder_qty,
         (select o.party_id from public.purchase_order_lines l join public.purchase_orders o on o.id = l.order_id
           where o.company_id = p_company and l.item_id = i.id and o.status <> 'cancelled' order by o.date desc limit 1)
    from t join public.items i on i.id = t.id
   where t.dem + t.dep + t.rl - t.onh - t.inc > 0.0005
   order by t.mk desc, i.name;
end $$;

revoke all on function public.bom_save(uuid, uuid, jsonb), public.bom_delete(uuid, uuid), public.mo_save(uuid, jsonb), public.mo_cancel(uuid), public.mo_needs(uuid),
  public.mo_complete(uuid, date), public.mrp_plan(uuid) from public, anon;
grant execute on function public.bom_save(uuid, uuid, jsonb), public.bom_delete(uuid, uuid), public.mo_save(uuid, jsonb), public.mo_cancel(uuid), public.mo_needs(uuid),
  public.mo_complete(uuid, date), public.mrp_plan(uuid) to authenticated;
notify pgrst, 'reload schema';
