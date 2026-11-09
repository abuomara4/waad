-- Waad ERP — 0052 purchasing: request for quotations from several suppliers, side-by-side comparison, award → purchase order;
-- supplier ratings (quality, delivery, price, service) and a scorecard with on-time delivery from goods receipts.

create table if not exists public.rfqs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  date date not null default current_date,
  reply_by date,
  title text not null check (length(trim(title)) >= 3),
  request_id uuid references public.requests(id),
  status text not null default 'open' check (status in ('open','awarded','cancelled')),
  awarded_quote uuid,
  po_id uuid references public.purchase_orders(id),
  note text,
  reason text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (company_id, no)
);
create table if not exists public.rfq_lines (
  id uuid primary key default gen_random_uuid(),
  rfq_id uuid not null references public.rfqs(id) on delete cascade,
  item_id uuid references public.items(id),
  account_code text,
  description text,
  qty numeric(14,3) not null check (qty > 0),
  check (item_id is not null or account_code is not null)
);
create table if not exists public.rfq_quotes (
  id uuid primary key default gen_random_uuid(),
  rfq_id uuid not null references public.rfqs(id) on delete cascade,
  party_id uuid not null references public.parties(id),
  received_on date not null default current_date,
  valid_until date,
  delivery_days int check (delivery_days is null or delivery_days between 0 and 365),
  terms text,
  note text,
  subtotal numeric(14,2) not null default 0,
  vat numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  unique (rfq_id, party_id)
);
create table if not exists public.rfq_quote_lines (
  quote_id uuid not null references public.rfq_quotes(id) on delete cascade,
  line_id uuid not null references public.rfq_lines(id) on delete cascade,
  unit_price numeric(14,2) not null check (unit_price >= 0),
  vat_rate numeric(5,2) not null default 15 check (vat_rate in (0, 15)),
  primary key (quote_id, line_id)
);
alter table public.rfqs drop constraint if exists rfqs_awarded_quote_fkey;
alter table public.rfqs add constraint rfqs_awarded_quote_fkey foreign key (awarded_quote) references public.rfq_quotes(id);

create table if not exists public.supplier_ratings (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  party_id uuid not null references public.parties(id),
  po_id uuid references public.purchase_orders(id),
  date date not null default current_date,
  quality int not null check (quality between 1 and 5),
  delivery int not null check (delivery between 1 and 5),
  price int not null check (price between 1 and 5),
  service int not null check (service between 1 and 5),
  note text,
  rated_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists supplier_ratings_party on public.supplier_ratings(party_id);

alter table public.rfqs enable row level security;
alter table public.rfq_lines enable row level security;
alter table public.rfq_quotes enable row level security;
alter table public.rfq_quote_lines enable row level security;
alter table public.supplier_ratings enable row level security;
drop policy if exists rfq_read on public.rfqs;
create policy rfq_read on public.rfqs for select using (public.fin_can(company_id, 'purch'));
drop policy if exists rfql_read on public.rfq_lines;
create policy rfql_read on public.rfq_lines for select using (exists(select 1 from public.rfqs r where r.id = rfq_id and public.fin_can(r.company_id, 'purch')));
drop policy if exists rfqq_read on public.rfq_quotes;
create policy rfqq_read on public.rfq_quotes for select using (exists(select 1 from public.rfqs r where r.id = rfq_id and public.fin_can(r.company_id, 'purch')));
drop policy if exists rfqql_read on public.rfq_quote_lines;
create policy rfqql_read on public.rfq_quote_lines for select using (exists(select 1 from public.rfq_quotes q join public.rfqs r on r.id = q.rfq_id where q.id = quote_id and public.fin_can(r.company_id, 'purch')));
drop policy if exists srate_read on public.supplier_ratings;
create policy srate_read on public.supplier_ratings for select using (public.fin_can(company_id, 'purch'));
drop policy if exists srate_write on public.supplier_ratings;
create policy srate_write on public.supplier_ratings for insert with check (public.fin_can(company_id, 'purch')
  and exists(select 1 from public.parties p where p.id = party_id and p.company_id = supplier_ratings.company_id and p.kind = 'supplier')
  and (po_id is null or exists(select 1 from public.purchase_orders o where o.id = po_id and o.party_id = supplier_ratings.party_id)));
revoke all on public.rfqs, public.rfq_lines, public.rfq_quotes, public.rfq_quote_lines, public.supplier_ratings from anon;
grant select on public.rfqs, public.rfq_lines, public.rfq_quotes, public.rfq_quote_lines to authenticated;
grant select, insert on public.supplier_ratings to authenticated;
drop trigger if exists audit_rfqs on public.rfqs;
create trigger audit_rfqs after insert or update on public.rfqs for each row execute function public.audit_trigger();
drop trigger if exists audit_supplier_ratings on public.supplier_ratings;
create trigger audit_supplier_ratings after insert on public.supplier_ratings for each row execute function public.audit_trigger();

-- p_doc = {"id"?, "title", "date", "reply_by", "request"?, "note", "lines":[{"item"|"account", "desc", "qty"}]}
create or replace function public.rfq_save(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare rid uuid := nullif(p_doc->>'id', '')::uuid; r public.rfqs; l jsonb; q numeric; rq uuid := nullif(p_doc->>'request', '')::uuid;
begin
  perform public.require_fin(p_company, 'purch');
  if length(trim(coalesce(p_doc->>'title', ''))) < 3 then raise exception 'اكتب عنوان الطلب'; end if;
  if jsonb_array_length(coalesce(p_doc->'lines', '[]')) = 0 then raise exception 'أضف بنداً واحداً على الأقل'; end if;
  if (p_doc->>'reply_by') is not null and (p_doc->>'reply_by')::date < coalesce((p_doc->>'date')::date, current_date) then raise exception 'آخر موعد للرد بعد تاريخ الطلب'; end if;
  if rq is not null and not exists(select 1 from public.requests where id = rq and company_id = p_company and kind = 'purchase' and status = 'approved') then
    raise exception 'طلب الشراء غير معتمد'; end if;
  if rid is null then
    insert into public.rfqs(company_id, no, date, reply_by, title, request_id, note)
    values (p_company, public.next_doc_no(p_company, 'RFQ'), coalesce((p_doc->>'date')::date, current_date), nullif(p_doc->>'reply_by', '')::date,
            trim(p_doc->>'title'), rq, nullif(trim(p_doc->>'note'), '')) returning id into rid;
  else
    select * into r from public.rfqs where id = rid and company_id = p_company for update;
    if not found then raise exception 'الطلب غير موجود'; end if;
    if r.status <> 'open' then raise exception 'لا يُعدَّل إلا الطلب المفتوح'; end if;
    if exists(select 1 from public.rfq_quotes where rfq_id = rid) then raise exception 'وصلت عروض على هذا الطلب — لا تُعدَّل بنوده'; end if;
    update public.rfqs set date = coalesce((p_doc->>'date')::date, date), reply_by = nullif(p_doc->>'reply_by', '')::date, title = trim(p_doc->>'title'),
      request_id = rq, note = nullif(trim(p_doc->>'note'), '') where id = rid;
    delete from public.rfq_lines where rfq_id = rid;
  end if;
  for l in select * from jsonb_array_elements(p_doc->'lines') loop
    q := (l->>'qty')::numeric;
    if q is null or q <= 0 then raise exception 'الكمية أكبر من صفر'; end if;
    if nullif(l->>'item', '') is not null then
      if not exists(select 1 from public.items where id = (l->>'item')::uuid and company_id = p_company) then raise exception 'صنف غير موجود'; end if;
      insert into public.rfq_lines(rfq_id, item_id, description, qty) values (rid, (l->>'item')::uuid, nullif(trim(l->>'desc'), ''), q);
    else
      if not exists(select 1 from public.accounts where company_id = p_company and code = l->>'account' and not is_header and type in ('exp','asset')) then
        raise exception 'اختر صنفاً أو حساب مصروف صالحاً'; end if;
      insert into public.rfq_lines(rfq_id, account_code, description, qty) values (rid, l->>'account', nullif(trim(l->>'desc'), ''), q);
    end if;
  end loop;
  return rid;
end $$;

-- a supplier's reply: p_doc = {"party", "received_on", "valid_until", "delivery_days", "terms", "note", "prices":[{"line","price","vat"}]}
create or replace function public.rfq_quote_save(p_rfq uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare r public.rfqs; qid uuid; pid uuid := (p_doc->>'party')::uuid; l public.rfq_lines; pr jsonb; sub numeric := 0; v numeric := 0; a numeric; vr numeric;
begin
  select * into r from public.rfqs where id = p_rfq for update;
  if not found then raise exception 'الطلب غير موجود'; end if;
  perform public.require_fin(r.company_id, 'purch');
  if r.status <> 'open' then raise exception 'الطلب ليس مفتوحاً'; end if;
  if not exists(select 1 from public.parties where id = pid and company_id = r.company_id and kind = 'supplier' and active) then raise exception 'اختر المورد'; end if;
  insert into public.rfq_quotes(rfq_id, party_id, received_on, valid_until, delivery_days, terms, note)
  values (p_rfq, pid, coalesce((p_doc->>'received_on')::date, current_date), nullif(p_doc->>'valid_until', '')::date, nullif(p_doc->>'delivery_days', '')::int,
          nullif(trim(p_doc->>'terms'), ''), nullif(trim(p_doc->>'note'), ''))
  on conflict (rfq_id, party_id) do update set received_on = excluded.received_on, valid_until = excluded.valid_until, delivery_days = excluded.delivery_days,
    terms = excluded.terms, note = excluded.note
  returning id into qid;
  delete from public.rfq_quote_lines where quote_id = qid;
  for l in select * from public.rfq_lines where rfq_id = p_rfq loop
    select x into pr from jsonb_array_elements(coalesce(p_doc->'prices', '[]')) x where x->>'line' = l.id::text;
    if pr is null or nullif(pr->>'price', '') is null then raise exception 'أدخل سعر كل بند في عرض المورد'; end if;
    vr := coalesce((pr->>'vat')::numeric, 15);
    insert into public.rfq_quote_lines(quote_id, line_id, unit_price, vat_rate) values (qid, l.id, round((pr->>'price')::numeric, 2), vr);
    a := round(l.qty * round((pr->>'price')::numeric, 2), 2); sub := sub + a; v := v + round(a * vr / 100, 2);
  end loop;
  update public.rfq_quotes set subtotal = sub, vat = v, total = sub + v where id = qid;
  return qid;
end $$;

-- award one supplier's offer: creates the purchase order at the offered prices
create or replace function public.rfq_award(p_quote uuid, p_expected date default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare q public.rfq_quotes; r public.rfqs; po uuid;
begin
  select * into q from public.rfq_quotes where id = p_quote;
  if not found then raise exception 'العرض غير موجود'; end if;
  select * into r from public.rfqs where id = q.rfq_id for update;
  perform public.require_fin(r.company_id, 'purch');
  if r.status <> 'open' then raise exception 'الطلب ليس مفتوحاً'; end if;
  po := public.po_save(r.company_id, jsonb_build_object('party', q.party_id, 'date', current_date,
    'expected', coalesce(p_expected, case when q.delivery_days is not null then current_date + q.delivery_days end),
    'request', r.request_id, 'note', 'من طلب عروض الأسعار ' || r.no, 'terms', q.terms,
    'lines', (select jsonb_agg(jsonb_build_object('item', l.item_id, 'account', l.account_code, 'desc', l.description, 'qty', l.qty,
                                                'price', ql.unit_price, 'vat', ql.vat_rate) order by l.id)
                from public.rfq_lines l join public.rfq_quote_lines ql on ql.line_id = l.id and ql.quote_id = q.id)));
  update public.rfqs set status = 'awarded', awarded_quote = q.id, po_id = po where id = r.id;
  return po;
end $$;

create or replace function public.rfq_cancel(p_rfq uuid, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.rfqs;
begin
  select * into r from public.rfqs where id = p_rfq for update;
  if not found then raise exception 'الطلب غير موجود'; end if;
  perform public.require_fin(r.company_id, 'purch');
  if r.status <> 'open' then raise exception 'الطلب ليس مفتوحاً'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'اكتب السبب'; end if;
  update public.rfqs set status = 'cancelled', reason = trim(p_reason) where id = p_rfq;
end $$;

-- supplier scorecard: ratings average and on-time delivery (first receipt on or before the expected date)
create or replace function public.supplier_scorecard(p_company uuid)
returns table(party_id uuid, ratings int, quality numeric, delivery numeric, price numeric, service numeric, overall numeric,
              orders int, on_time_pct numeric, quotes int, awards int)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'purch');
  return query
  with rt as (select s.party_id pid, count(*)::int n, round(avg(s.quality), 1) qa, round(avg(s.delivery), 1) de, round(avg(s.price), 1) pr, round(avg(s.service), 1) se,
                     round(avg((s.quality + s.delivery + s.price + s.service) / 4.0), 1) ov
                from public.supplier_ratings s where s.company_id = p_company group by s.party_id),
       od as (select o.party_id pid, count(*)::int n,
                     round(100.0 * count(*) filter (where o.expected_date is not null and fr.d <= o.expected_date)
                           / nullif(count(*) filter (where o.expected_date is not null and fr.d is not null), 0), 0) ot
                from public.purchase_orders o
                left join lateral (select min(g.date) d from public.goods_receipts g where g.order_id = o.id and g.status = 'posted') fr on true
               where o.company_id = p_company and o.status <> 'cancelled' group by o.party_id),
       qs as (select q.party_id pid, count(*)::int n, count(*) filter (where r.awarded_quote = q.id)::int w
                from public.rfq_quotes q join public.rfqs r on r.id = q.rfq_id where r.company_id = p_company group by q.party_id)
  select p.id, coalesce(rt.n, 0), rt.qa, rt.de, rt.pr, rt.se, rt.ov, coalesce(od.n, 0), od.ot, coalesce(qs.n, 0), coalesce(qs.w, 0)
    from public.parties p left join rt on rt.pid = p.id left join od on od.pid = p.id left join qs on qs.pid = p.id
   where p.company_id = p_company and p.kind = 'supplier';
end $$;

revoke all on function public.rfq_save(uuid, jsonb), public.rfq_quote_save(uuid, jsonb), public.rfq_award(uuid, date), public.rfq_cancel(uuid, text),
  public.supplier_scorecard(uuid) from public, anon;
grant execute on function public.rfq_save(uuid, jsonb), public.rfq_quote_save(uuid, jsonb), public.rfq_award(uuid, date), public.rfq_cancel(uuid, text),
  public.supplier_scorecard(uuid) to authenticated;
notify pgrst, 'reload schema';
