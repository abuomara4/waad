-- Waad ERP — 0153 the first free batch from the comparison with the big systems (owner's request, 2026-11-26):
--  1. receipts on spend requests: the files of an expense claim / trip / purchase / ticket / overtime / remote request are
--     seen by finance and the employee's direct manager too (leave documents stay HR-only: medical data);
--  2. bulk approval: client only (decide_request per request);
--  3. reminding customers of overdue invoices: overdue_customers + dunning_log (who was reminded, when, how);
--  4. price lists and quantity discounts: price_lists / price_list_rules, parties.price_list_id, one default list;
--  5. overtime approved in advance into the payroll of a company without attendance (payroll_ot_requests / payroll_ot_fill);
--  6. probation evaluation before its end (Art. 53: up to 180 days): the manager recommends, HR decides;
--  7. shift swap between two employees: the colleague accepts, the manager or HR approves, the roster changes for that day.

-- ---------------- 1. receipts ----------------
create or replace function public.request_files_can(p_req uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.requests q join public.employees e on e.id = q.employee_id
     where q.id = p_req and q.kind <> 'leave'
       and (public.has_role(q.company_id, array['owner','admin','hr','finance']) or public.fin_can(q.company_id, 'je')
            or coalesce(e.manager_id = public.my_employee(q.company_id), false) or coalesce(public.can_act(q, q.route[q.step + 1]), false)))
$$;
drop policy if exists ra_spend_read on public.request_attachments;
create policy ra_spend_read on public.request_attachments for select using (public.request_files_can(request_id));

-- ---------------- 3. overdue customers ----------------
create table if not exists public.dunning_log (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  party_id uuid not null references public.parties(id) on delete cascade,
  channel text not null check (channel in ('whatsapp','email','copy','print')),
  amount numeric(14,2) not null default 0,
  invoices int not null default 0,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists dunning_log_party on public.dunning_log(company_id, party_id, created_at desc);
create index if not exists dunning_log_party_fk on public.dunning_log(party_id);
alter table public.dunning_log enable row level security;
revoke all on public.dunning_log from anon, authenticated;
grant select on public.dunning_log to authenticated;
drop policy if exists dunning_read on public.dunning_log;
create policy dunning_read on public.dunning_log for select using (public.fin_can(company_id, 'sales'));

create or replace function public.overdue_customers(p_company uuid, p_as_of date default current_date)
returns table(party_id uuid, name text, contact text, phone text, email text, n int, overdue numeric, oldest date, max_days int, last_at timestamptz, last_channel text, times int, invoices jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'sales');
  return query
  with docs as (
    select i.party_id pid, i.id, i.no, i.date, i.due_date, i.total, i.total - public.paid_on(i.id) rem
      from public.sales_invoices i
     where i.company_id = p_company and i.status = 'posted' and i.due_date < p_as_of and public.branch_ok(p_company, i.branch_id)),
  od as (select * from docs where rem > 0.009)
  select p.id, p.name, p.contact_name, p.phone, p.email, count(*)::int, round(sum(od.rem), 2), min(od.due_date), (p_as_of - min(od.due_date))::int,
         (select max(d.created_at) from public.dunning_log d where d.party_id = p.id),
         (select d.channel from public.dunning_log d where d.party_id = p.id order by d.created_at desc limit 1),
         (select count(*)::int from public.dunning_log d where d.party_id = p.id and d.created_at > now() - interval '90 days'),
         jsonb_agg(jsonb_build_object('id', od.id, 'no', od.no, 'date', od.date, 'due', od.due_date, 'total', od.total, 'rem', round(od.rem, 2), 'days', p_as_of - od.due_date) order by od.due_date)
    from od join public.parties p on p.id = od.pid
   group by p.id, p.name, p.contact_name, p.phone, p.email
   order by sum(od.rem) desc;
end $$;

create or replace function public.dunning_note(p_company uuid, p_party uuid, p_channel text, p_amount numeric, p_invoices int) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'sales');
  if not exists(select 1 from public.parties where id = p_party and company_id = p_company and kind = 'customer') then raise exception 'العميل غير موجود'; end if;
  if p_channel not in ('whatsapp','email','copy','print') then raise exception 'طريقة غير معروفة'; end if;
  insert into public.dunning_log(company_id, party_id, channel, amount, invoices) values (p_company, p_party, p_channel, coalesce(p_amount, 0), coalesce(p_invoices, 0));
end $$;

-- ---------------- 4. price lists ----------------
create table if not exists public.price_lists (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null check (length(trim(name)) between 2 and 80),
  name_en text,
  discount_pct numeric(5,2) not null default 0 check (discount_pct between 0 and 100),   -- on every item without its own rule
  is_default boolean not null default false,       -- for customers without a list of their own
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (company_id, name)
);
create unique index if not exists price_lists_one_default on public.price_lists(company_id) where is_default and active;
create table if not exists public.price_list_rules (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  list_id uuid not null references public.price_lists(id) on delete cascade,
  item_id uuid not null references public.items(id) on delete cascade,
  min_qty numeric(14,3) not null default 1 check (min_qty > 0),
  price numeric(14,2) check (price is null or price >= 0),
  discount_pct numeric(5,2) check (discount_pct is null or discount_pct between 0 and 100),
  check ((price is null) <> (discount_pct is null)),
  unique (list_id, item_id, min_qty)
);
create index if not exists price_list_rules_company on public.price_list_rules(company_id);
create index if not exists price_list_rules_item on public.price_list_rules(item_id);
alter table public.parties add column if not exists price_list_id uuid references public.price_lists(id) on delete set null;
create index if not exists parties_price_list on public.parties(price_list_id);
alter table public.price_lists enable row level security;
alter table public.price_list_rules enable row level security;
revoke all on public.price_lists, public.price_list_rules from anon, authenticated;
grant select on public.price_lists, public.price_list_rules to authenticated;
drop policy if exists pl_read on public.price_lists;
create policy pl_read on public.price_lists for select using (public.fin_can(company_id, 'sales'));
drop policy if exists plr_read on public.price_list_rules;
create policy plr_read on public.price_list_rules for select using (public.fin_can(company_id, 'sales'));
-- a customer's list must be the company's own
create or replace function public.parties_price_list_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.price_list_id is not null and not exists(select 1 from public.price_lists l where l.id = new.price_list_id and l.company_id = new.company_id) then
    raise exception 'قائمة الأسعار ليست من المنشأة'; end if;
  return new;
end $$;
drop trigger if exists parties_price_list_guard on public.parties;
create trigger parties_price_list_guard before insert or update of price_list_id on public.parties for each row execute function public.parties_price_list_guard();

-- save a list with its rules: p_rules = [{item, min_qty, price | discount_pct}]
create or replace function public.price_list_save(p_company uuid, p_id uuid, p_name text, p_name_en text, p_discount numeric, p_default boolean, p_active boolean, p_rules jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid := p_id; r jsonb;
begin
  if not (public.has_role(p_company, array['owner','admin','finance']) or public.fin_can(p_company, 'sales')) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  perform public.require_fin(p_company, 'sales');
  if coalesce(p_discount, 0) < 0 or coalesce(p_discount, 0) > 100 then raise exception 'نسبة الخصم بين 0 و100'; end if;
  if coalesce(p_default, false) then update public.price_lists set is_default = false where company_id = p_company and id is distinct from v; end if;
  if v is null then
    insert into public.price_lists(company_id, name, name_en, discount_pct, is_default, active)
    values (p_company, btrim(p_name), nullif(btrim(coalesce(p_name_en, '')), ''), coalesce(p_discount, 0), coalesce(p_default, false), coalesce(p_active, true)) returning id into v;
  else
    update public.price_lists set name = btrim(p_name), name_en = nullif(btrim(coalesce(p_name_en, '')), ''), discount_pct = coalesce(p_discount, 0),
      is_default = coalesce(p_default, false), active = coalesce(p_active, true) where id = v and company_id = p_company;
    if not found then raise exception 'القائمة غير موجودة'; end if;
  end if;
  delete from public.price_list_rules where list_id = v;
  for r in select * from jsonb_array_elements(coalesce(p_rules, '[]')) loop
    if not exists(select 1 from public.items where id = (r->>'item')::uuid and company_id = p_company) then raise exception 'الصنف ليس من المنشأة'; end if;
    if (nullif(r->>'price', '') is null) = (nullif(r->>'discount_pct', '') is null) then raise exception 'لكل بند سعر أو نسبة خصم'; end if;
    insert into public.price_list_rules(company_id, list_id, item_id, min_qty, price, discount_pct)
    values (p_company, v, (r->>'item')::uuid, coalesce(nullif(r->>'min_qty', '')::numeric, 1), nullif(r->>'price', '')::numeric, nullif(r->>'discount_pct', '')::numeric)
    on conflict (list_id, item_id, min_qty) do update set price = excluded.price, discount_pct = excluded.discount_pct;
  end loop;
  return v;
end $$;
create or replace function public.price_list_delete(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c uuid;
begin
  select company_id into c from public.price_lists where id = p_id;
  if c is null then raise exception 'القائمة غير موجودة'; end if;
  perform public.require_fin(c, 'sales');
  delete from public.price_lists where id = p_id;
end $$;
-- the price of an item for a customer and a quantity (pure rule: the rule with the highest min_qty reached wins;
-- an item without a rule takes the list's discount; no list → the item's sale price)
create or replace function public.list_price(p_party uuid, p_item uuid, p_qty numeric) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare it public.items; l public.price_lists; ru public.price_list_rules; pl uuid;
begin
  select * into it from public.items where id = p_item;
  if not found then return null; end if;
  perform public.require_fin(it.company_id, 'sales');
  select price_list_id into pl from public.parties where id = p_party and company_id = it.company_id;
  select * into l from public.price_lists where active and company_id = it.company_id and (id = pl or (pl is null and is_default)) order by (id = pl) desc limit 1;
  if l.id is null then return it.sale_price; end if;
  select * into ru from public.price_list_rules where list_id = l.id and item_id = p_item and min_qty <= coalesce(p_qty, 1) order by min_qty desc limit 1;
  if ru.id is not null then return coalesce(ru.price, round(coalesce(it.sale_price, 0) * (1 - ru.discount_pct / 100), 2)); end if;
  return round(coalesce(it.sale_price, 0) * (1 - l.discount_pct / 100), 2);
end $$;

-- ---------------- 5. overtime asked in advance → payroll (companies without attendance) ----------------
create or replace function public.payroll_ot_requests(p_run uuid) returns table(employee_id uuid, hours numeric, line_hours numeric)
language plpgsql stable security definer set search_path = public as $$
declare r public.payroll_runs; pp record;
begin
  select * into r from public.payroll_runs where id = p_run;
  if not found then raise exception 'المسير غير موجود'; end if;
  perform public.require_role(r.company_id, array['owner','admin','hr','finance']);
  select * into pp from public.payroll_period(r.company_id, r.year, r.month);
  return query
  select q.employee_id, sum((q.payload->>'hours')::numeric), max(l.overtime_hours)
    from public.requests q join public.payroll_lines l on l.run_id = p_run and l.employee_id = q.employee_id
   where q.company_id = r.company_id and q.kind = 'overtime' and q.status = 'approved' and q.from_date between pp.ps and pp.pe
   group by q.employee_id;
end $$;
-- copies them into the lines (only where the line has fewer hours); with attendance on they already count through it
create or replace function public.payroll_ot_fill(p_run uuid) returns int
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; x record; n int := 0;
begin
  select * into r from public.payroll_runs where id = p_run;
  if not found then raise exception 'المسير غير موجود'; end if;
  perform public.require_role(r.company_id, array['hr','admin','owner']);
  if r.status <> 'draft' then raise exception 'المسير معتمد ولا يمكن تعديله'; end if;
  if (select att_enabled from public.companies where id = r.company_id) then raise exception 'الحضور مفعّل: الإضافي المعتمد مسبقا يُحتسب من سجل الحضور'; end if;
  for x in select * from public.payroll_ot_requests(p_run) loop
    if x.hours > coalesce(x.line_hours, 0) then
      perform public.ot_cap_check(x.employee_id, r.year, x.hours - coalesce(x.line_hours, 0));
      update public.payroll_lines set overtime_hours = x.hours where run_id = p_run and employee_id = x.employee_id;
      perform public.payroll_line_recalc(p_run, x.employee_id);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

-- ---------------- 6. probation evaluation ----------------
create table if not exists public.probation_reviews (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  probation_end date not null,
  ratings jsonb not null default '{}',             -- {quality, commitment, teamwork, learning, conduct}: 1–5
  score numeric(3,1),
  strengths text, improve text,
  recommendation text not null check (recommendation in ('confirm','extend','end')),
  extend_days int check (extend_days is null or extend_days between 1 and 179),
  by_user uuid default auth.uid(), by_name text,
  status text not null default 'recommended' check (status in ('recommended','final')),
  decision text check (decision in ('confirm','extend','end')),
  decision_note text, decided_by uuid, decided_at timestamptz,
  created_at timestamptz not null default now(),
  unique (employee_id, probation_end)
);
create index if not exists probation_reviews_company on public.probation_reviews(company_id);
alter table public.probation_reviews enable row level security;
revoke all on public.probation_reviews from anon, authenticated;
grant select on public.probation_reviews to authenticated;
create or replace function public.probation_can(p_company uuid, p_emp uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.emp_branch_ok(p_company, p_emp) and (public.has_role(p_company, array['owner','admin','hr']) or public.fin_can(p_company, 'hr_emp')
     or coalesce((select e.manager_id = public.my_employee(p_company) from public.employees e where e.id = p_emp and e.company_id = p_company), false))
$$;
drop policy if exists probation_read on public.probation_reviews;
create policy probation_read on public.probation_reviews for select using (public.probation_can(company_id, employee_id));

-- the people whose probation ends within 30 days (or ended in the last 15) that I evaluate or decide
create or replace function public.probation_due(p_company uuid) returns table(employee_id uuid, name text, emp_no text, job text, manager text, hire_date date,
  probation_end date, effective_end date, days_left int, review jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_member(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query
  select e.id, e.full_name, e.emp_no, e.job_title, (select m.full_name from public.employees m where m.id = e.manager_id), e.hire_date, e.probation_end, x.d, (x.d - current_date)::int,
         (select to_jsonb(v) - 'by_user' - 'decided_by' from public.probation_reviews v where v.employee_id = e.id and v.probation_end = e.probation_end)
    from public.employees e cross join lateral (select public.probation_effective_end(e.id) d) x
   where e.company_id = p_company and e.probation_end is not null and (e.end_date is null or e.end_date >= current_date)
     and x.d between current_date - 15 and current_date + 30 and public.probation_can(p_company, e.id)
   order by x.d;
end $$;

create or replace function public.probation_review_save(p_company uuid, p_emp uuid, p_ratings jsonb, p_strengths text, p_improve text, p_rec text, p_extend_days int) returns uuid
language plpgsql security definer set search_path = public as $$
declare e public.employees; v uuid; k text; s numeric := 0; n int := 0; me uuid := public.my_employee(p_company);
begin
  select * into e from public.employees where id = p_emp and company_id = p_company;
  if not found or e.probation_end is null then raise exception 'الموظف ليس في فترة تجربة'; end if;
  if not public.probation_can(p_company, p_emp) or e.id = me then raise exception 'يقيّم فترة التجربة المدير المباشر أو الموارد البشرية' using errcode = '42501'; end if;
  if p_rec not in ('confirm','extend','end') then raise exception 'اختر التوصية'; end if;
  for k in select jsonb_object_keys(coalesce(p_ratings, '{}')) loop
    if k not in ('quality','commitment','teamwork','learning','conduct') or coalesce((p_ratings->>k)::int, 0) not between 1 and 5 then raise exception 'التقييم من 1 إلى 5'; end if;
    s := s + (p_ratings->>k)::int; n := n + 1;
  end loop;
  if n = 0 then raise exception 'قيّم البنود من 1 إلى 5'; end if;
  if p_rec = 'extend' and (p_extend_days is null or p_extend_days < 1) then raise exception 'حدد أيام التمديد'; end if;
  if p_rec = 'extend' and e.probation_end + p_extend_days - e.hire_date + 1 > 180 then
    raise exception 'فترة التجربة كلها لا تزيد على 180 يوما — م53 (المتاح % يوما)', greatest(0, 180 - (e.probation_end - e.hire_date + 1)); end if;
  if exists(select 1 from public.probation_reviews where employee_id = p_emp and probation_end = e.probation_end and status = 'final') then raise exception 'صدر قرار فترة التجربة'; end if;
  insert into public.probation_reviews(company_id, employee_id, probation_end, ratings, score, strengths, improve, recommendation, extend_days, by_name)
  values (p_company, p_emp, e.probation_end, p_ratings, round(s / n, 1), nullif(btrim(p_strengths), ''), nullif(btrim(p_improve), ''), p_rec, case when p_rec = 'extend' then p_extend_days end,
          coalesce((select full_name from public.employees where id = me), (select email from auth.users where id = auth.uid())))
  on conflict (employee_id, probation_end) do update set ratings = excluded.ratings, score = excluded.score, strengths = excluded.strengths, improve = excluded.improve,
     recommendation = excluded.recommendation, extend_days = excluded.extend_days, by_user = auth.uid(), by_name = excluded.by_name, created_at = now()
  returning id into v;
  return v;
end $$;

-- HR decides: confirm (the probation ends today if it was still running), extend (total up to 180 days, Art. 53), or end
-- (recorded; the contract itself is ended from the employee file / end of service, where Arts. 53–54 are shown)
create or replace function public.probation_decide(p_company uuid, p_emp uuid, p_decision text, p_extend_days int, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare e public.employees; v public.probation_reviews;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  select * into e from public.employees where id = p_emp and company_id = p_company;
  if not found or e.probation_end is null then raise exception 'الموظف ليس في فترة تجربة'; end if;
  if not public.emp_branch_ok(p_company, p_emp) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_decision not in ('confirm','extend','end') then raise exception 'اختر القرار'; end if;
  select * into v from public.probation_reviews where employee_id = p_emp and probation_end = e.probation_end;
  if v.status = 'final' then raise exception 'صدر قرار فترة التجربة'; end if;
  if p_decision = 'extend' then
    if p_extend_days is null or p_extend_days < 1 then raise exception 'حدد أيام التمديد'; end if;
    if e.probation_end + p_extend_days - e.hire_date + 1 > 180 then
      raise exception 'فترة التجربة كلها لا تزيد على 180 يوما — م53 (المتاح % يوما)', greatest(0, 180 - (e.probation_end - e.hire_date + 1)); end if;
  end if;
  if v.id is null then
    insert into public.probation_reviews(company_id, employee_id, probation_end, recommendation, by_name)
    values (p_company, p_emp, e.probation_end, p_decision, (select email from auth.users where id = auth.uid())) returning * into v;
  end if;
  update public.probation_reviews set status = 'final', decision = p_decision, decision_note = nullif(btrim(p_note), ''), decided_by = auth.uid(), decided_at = now(),
         extend_days = case when p_decision = 'extend' then p_extend_days else extend_days end where id = v.id;
  if p_decision = 'extend' then update public.employees set probation_end = e.probation_end + p_extend_days where id = p_emp;
  elsif p_decision = 'confirm' and e.probation_end > current_date then update public.employees set probation_end = current_date where id = p_emp; end if;
end $$;

-- ---------------- 7. shift swaps ----------------
create table if not exists public.shift_swaps (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  from_emp uuid not null references public.employees(id) on delete cascade,
  to_emp uuid not null references public.employees(id) on delete cascade,
  day date not null,
  from_shift uuid references public.shifts(id) on delete set null, from_off boolean not null default false,
  to_shift uuid references public.shifts(id) on delete set null, to_off boolean not null default false,
  note text,
  status text not null default 'asked' check (status in ('asked','accepted','declined','approved','rejected','cancelled')),
  answered_at timestamptz, decided_by uuid, decided_at timestamptz, decide_note text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  check (from_emp <> to_emp)
);
create index if not exists shift_swaps_company on public.shift_swaps(company_id, day);
create index if not exists shift_swaps_from on public.shift_swaps(from_emp);
create index if not exists shift_swaps_to on public.shift_swaps(to_emp);
create index if not exists shift_swaps_fs on public.shift_swaps(from_shift);
create index if not exists shift_swaps_ts on public.shift_swaps(to_shift);
alter table public.shift_swaps enable row level security;
revoke all on public.shift_swaps from anon, authenticated;
grant select on public.shift_swaps to authenticated;
create or replace function public.swap_can_decide(s public.shift_swaps) returns boolean
language sql stable security definer set search_path = public as $$
  select public.emp_branch_ok(s.company_id, s.from_emp) and coalesce(public.my_employee(s.company_id) not in (s.from_emp, s.to_emp), true)
     and (public.has_role(s.company_id, array['owner','admin','hr'])
          or coalesce((select e.manager_id = public.my_employee(s.company_id) from public.employees e where e.id = s.from_emp), false))
$$;
drop policy if exists swaps_read on public.shift_swaps;
create policy swaps_read on public.shift_swaps for select using (
  public.my_employee(company_id) in (from_emp, to_emp) or public.has_role(company_id, array['owner','admin','hr'])
  or exists(select 1 from public.employees e where e.id in (from_emp, to_emp) and e.manager_id = public.my_employee(company_id)));

-- what an employee works on a day: a shift, or off
create or replace function public.day_shift(p_emp uuid, p_day date) returns uuid
language sql stable security definer set search_path = public as $$
  select case when public.is_workday(p_emp, p_day) then (public.employee_shift_on(p_emp, p_day)).id end
$$;

create or replace function public.swap_ask(p_company uuid, p_with uuid, p_day date, p_note text) returns uuid
language plpgsql security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company); w public.employees; s1 uuid; s2 uuid; v uuid;
begin
  if me is null then raise exception 'حسابك غير مربوط بسجل موظف' using errcode = '42501'; end if;
  select * into w from public.employees where id = p_with and company_id = p_company and (end_date is null or end_date >= p_day);
  if not found or p_with = me then raise exception 'اختر زميلا من المنشأة'; end if;
  if p_day is null or p_day < public.riyadh_today() or p_day > public.riyadh_today() + 60 then raise exception 'يوم التبديل من اليوم حتى 60 يوما قادمة'; end if;
  if exists(select 1 from public.attendance where employee_id in (me, p_with) and day = p_day) then raise exception 'سُجّل حضور في هذا اليوم'; end if;
  s1 := public.day_shift(me, p_day); s2 := public.day_shift(p_with, p_day);
  if s1 is not distinct from s2 then raise exception 'ورديتكما متطابقة في هذا اليوم'; end if;
  if exists(select 1 from public.shift_swaps where day = p_day and status in ('asked','accepted') and (from_emp in (me, p_with) or to_emp in (me, p_with))) then
    raise exception 'يوجد طلب تبديل مفتوح لهذا اليوم'; end if;
  insert into public.shift_swaps(company_id, from_emp, to_emp, day, from_shift, from_off, to_shift, to_off, note)
  values (p_company, me, p_with, p_day, s1, s1 is null, s2, s2 is null, nullif(btrim(p_note), '')) returning id into v;
  return v;
end $$;
create or replace function public.swap_answer(p_id uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare s public.shift_swaps;
begin
  select * into s from public.shift_swaps where id = p_id for update;
  if not found or s.to_emp is distinct from public.my_employee(s.company_id) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if s.status <> 'asked' then raise exception 'الطلب ليس بانتظار ردك'; end if;
  update public.shift_swaps set status = case when p_accept then 'accepted' else 'declined' end, answered_at = now() where id = p_id;
end $$;
create or replace function public.swap_cancel(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s public.shift_swaps;
begin
  select * into s from public.shift_swaps where id = p_id for update;
  if not found or s.from_emp is distinct from public.my_employee(s.company_id) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if s.status not in ('asked','accepted') then raise exception 'لا يمكن إلغاء طلب تم البت فيه'; end if;
  update public.shift_swaps set status = 'cancelled' where id = p_id;
end $$;
create or replace function public.swap_decide(p_id uuid, p_approve boolean, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare s public.shift_swaps;
begin
  select * into s from public.shift_swaps where id = p_id for update;
  if not found or not public.swap_can_decide(s) then raise exception 'يعتمد التبديل مدير الموظف أو الموارد البشرية' using errcode = '42501'; end if;
  if s.status <> 'accepted' then raise exception 'الطلب لم يوافق عليه الزميل بعد'; end if;
  if not p_approve then
    if coalesce(length(btrim(p_note)), 0) < 2 then raise exception 'اكتب سبب الرفض'; end if;
    update public.shift_swaps set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decide_note = btrim(p_note) where id = p_id; return;
  end if;
  if s.day < public.riyadh_today() then raise exception 'مضى يوم التبديل'; end if;
  if exists(select 1 from public.attendance where employee_id in (s.from_emp, s.to_emp) and day = s.day) then raise exception 'سُجّل حضور في هذا اليوم'; end if;
  if public.day_shift(s.from_emp, s.day) is distinct from s.from_shift or public.day_shift(s.to_emp, s.day) is distinct from s.to_shift then
    raise exception 'تغيّرت الوردية بعد الطلب — اطلب التبديل من جديد'; end if;
  insert into public.shift_roster(company_id, employee_id, day, shift_id, off) values (s.company_id, s.from_emp, s.day, s.to_shift, s.to_shift is null)
    on conflict (employee_id, day) do update set shift_id = excluded.shift_id, off = excluded.off;
  insert into public.shift_roster(company_id, employee_id, day, shift_id, off) values (s.company_id, s.to_emp, s.day, s.from_shift, s.from_shift is null)
    on conflict (employee_id, day) do update set shift_id = excluded.shift_id, off = excluded.off;
  update public.shift_swaps set status = 'approved', decided_by = auth.uid(), decided_at = now(), decide_note = nullif(btrim(p_note), '') where id = p_id;
end $$;
-- the list of the page: mine, asked of me, and those I decide (names and shift names included)
create or replace function public.swaps_list(p_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company);
begin
  if not public.is_member(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'day', s.day, 'status', s.status, 'note', s.note, 'decide_note', s.decide_note,
      'from_emp', s.from_emp, 'to_emp', s.to_emp, 'from_name', a.full_name, 'to_name', b.full_name,
      'from_shift', (select name from public.shifts where id = s.from_shift), 'to_shift', (select name from public.shifts where id = s.to_shift),
      'mine', s.from_emp = me, 'asked_me', s.to_emp = me and s.status = 'asked', 'can_decide', s.status = 'accepted' and public.swap_can_decide(s)) order by s.day desc, s.created_at desc)
    from public.shift_swaps s join public.employees a on a.id = s.from_emp join public.employees b on b.id = s.to_emp
   where s.company_id = p_company and s.created_at > now() - interval '120 days'
     and (me in (s.from_emp, s.to_emp) or public.swap_can_decide(s))), '[]');
end $$;
-- colleagues one can ask (names only)
create or replace function public.swap_colleagues(p_company uuid) returns table(id uuid, name text, department text)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company);
begin
  if me is null then raise exception 'حسابك غير مربوط بسجل موظف' using errcode = '42501'; end if;
  return query select e.id, e.full_name, (select d.name from public.departments d where d.id = e.department_id)
    from public.employees e where e.company_id = p_company and e.id <> me and (e.end_date is null or e.end_date >= current_date) and not e.att_exempt
   order by (e.department_id is not distinct from (select department_id from public.employees where id = me)) desc, e.full_name;
end $$;

revoke all on function public.swap_can_decide(public.shift_swaps), public.day_shift(uuid, date), public.parties_price_list_guard() from public, anon, authenticated;
-- used inside row policies, so signed-in users run them (they only answer true / false)
revoke all on function public.request_files_can(uuid), public.probation_can(uuid, uuid) from public, anon;
grant execute on function public.request_files_can(uuid), public.probation_can(uuid, uuid) to authenticated;
revoke all on function public.overdue_customers(uuid, date), public.dunning_note(uuid, uuid, text, numeric, int),
  public.price_list_save(uuid, uuid, text, text, numeric, boolean, boolean, jsonb), public.price_list_delete(uuid), public.list_price(uuid, uuid, numeric),
  public.payroll_ot_requests(uuid), public.payroll_ot_fill(uuid), public.probation_due(uuid),
  public.probation_review_save(uuid, uuid, jsonb, text, text, text, int), public.probation_decide(uuid, uuid, text, int, text),
  public.swap_ask(uuid, uuid, date, text), public.swap_answer(uuid, boolean), public.swap_cancel(uuid), public.swap_decide(uuid, boolean, text),
  public.swaps_list(uuid), public.swap_colleagues(uuid) from public, anon;
grant execute on function public.overdue_customers(uuid, date), public.dunning_note(uuid, uuid, text, numeric, int),
  public.price_list_save(uuid, uuid, text, text, numeric, boolean, boolean, jsonb), public.price_list_delete(uuid), public.list_price(uuid, uuid, numeric),
  public.payroll_ot_requests(uuid), public.payroll_ot_fill(uuid), public.probation_due(uuid),
  public.probation_review_save(uuid, uuid, jsonb, text, text, text, int), public.probation_decide(uuid, uuid, text, int, text),
  public.swap_ask(uuid, uuid, date, text), public.swap_answer(uuid, boolean), public.swap_cancel(uuid), public.swap_decide(uuid, boolean, text),
  public.swaps_list(uuid), public.swap_colleagues(uuid) to authenticated;
notify pgrst, 'reload schema';
