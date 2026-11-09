-- Waad ERP — 0002 HR: employees, leave policy, approval workflow, payroll, end of service
-- Legal rules mirror docs/RULES.md and are NOT legally verified. Review with a Saudi labor-law specialist.

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null,
  unique (company_id, name)
);

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  emp_no text not null,
  full_name text not null check (length(trim(full_name)) >= 3),
  national_id text check (national_id is null or national_id ~ '^[12][0-9]{9}$'),
  is_saudi boolean not null default true,
  gender text not null default 'm' check (gender in ('m','f')),
  job_title text,
  department_id uuid references public.departments(id) on delete set null,
  manager_id uuid references public.employees(id) on delete set null,
  hire_date date not null,
  end_date date,
  end_reason text,
  gosi_new boolean,           -- GOSI regime: true = first registered on/after 2024-07-03; null = derive from hire_date
  basic numeric(12,2) not null check (basic >= 0),
  housing numeric(12,2) not null default 0 check (housing >= 0),
  transport numeric(12,2) not null default 0 check (transport >= 0),
  iban text check (iban is null or iban ~ '^SA[0-9]{22}$'),
  phone text,
  email text,
  created_at timestamptz not null default now(),
  unique (company_id, emp_no),
  check (end_date is null or end_date >= hire_date),
  check (manager_id is null or manager_id <> id)
);
create index on public.employees(company_id);
create index on public.employees(manager_id);
alter table public.members add constraint members_employee_fk foreign key (employee_id) references public.employees(id) on delete set null;

create or replace function public.gross_wage(e public.employees) returns numeric language sql immutable as $$
  select e.basic + e.housing + e.transport
$$;

-- ---------- leave policy (global reference data) ----------
create table public.leave_types (
  code text primary key,
  name_ar text not null,
  name_en text not null,
  article text,
  max_days int,
  min_days int,
  gender text check (gender in ('m','f')),
  min_service_years numeric,
  once_in_service boolean not null default false,
  notice_days int,
  paid_note text
);
insert into public.leave_types(code,name_ar,name_en,article,max_days,min_days,gender,min_service_years,once_in_service,notice_days,paid_note) values
 ('annual','إجازة سنوية','Annual leave','م109',null,null,null,null,false,null,'كامل'),
 ('sick','إجازة مرضية','Sick leave','م117',120,null,null,null,false,null,'30 يوماً كامل، 60 يوماً 75%، 30 يوماً بدون أجر'),
 ('marriage','إجازة زواج','Marriage leave','م113',5,null,null,null,false,null,'كامل'),
 ('birth','إجازة مولود (للأب)','Paternity leave','م113',3,null,'m',null,false,null,'كامل'),
 ('death','إجازة وفاة قريب من الدرجة الأولى','Bereavement (1st degree)','م113',5,null,null,null,false,null,'كامل'),
 ('death2','إجازة وفاة أخ/أخت','Bereavement (sibling)','م113',3,null,null,null,false,null,'كامل'),
 ('maternity','إجازة وضع','Maternity leave','م151',84,null,'f',null,false,null,'كامل'),
 ('iddah','إجازة عدة (مسلمة)','Iddah leave (Muslim)','م160',130,null,'f',null,false,null,'كامل — لا تقل عن 4 أشهر و10 أيام'),
 ('iddahn','إجازة وفاة الزوج (غير مسلمة)','Widow leave (non-Muslim)','م160',15,null,'f',null,false,null,'كامل'),
 ('newbornd','إجازة مولود من ذوي الإعاقة','Leave for a newborn with a disability','م151',30,null,'f',null,false,null,'شهر كامل بعد إجازة الوضع، ويجوز شهر إضافي بدون أجر'),
 ('hajj','إجازة حج','Hajj leave','م114',15,10,null,2,true,null,'كامل'),
 ('exam','إجازة اختبارات','Exam leave','م115',null,null,null,null,false,15,'كامل'),
 ('unpaid','إجازة بدون راتب','Unpaid leave','م116',null,null,null,null,false,null,'بدون أجر');

create or replace function public.annual_entitlement(p_hire date, p_as_of date) returns int language sql immutable as $$
  select case when (p_as_of - p_hire) / 365.0 >= 5 then 30 else 21 end
$$;

-- ---------- approval workflow ----------
-- step codes: m = direct manager, p = HR, f = finance, g = general manager (owner)
create table public.workflows (
  company_id uuid not null references public.companies(id) on delete cascade,
  kind text not null,
  route text[] not null check (route <@ array['m','p','f','g']),
  primary key (company_id, kind)
);

create table public.requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  kind text not null check (kind in ('leave','permit','cert','advance','resign','settle','expense','update')),
  sub text,
  from_date date,
  to_date date,
  days int,
  amount numeric(12,2),
  payload jsonb not null default '{}',
  note text,
  route text[] not null default '{}',
  step int not null default 0,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
create index on public.requests(company_id, status);
create index on public.requests(employee_id);

create table public.request_actions (
  id bigint generated always as identity primary key,
  request_id uuid not null references public.requests(id) on delete cascade,
  actor uuid,
  actor_step text,
  action text not null check (action in ('submitted','approved','rejected','cancelled')),
  note text,
  at timestamptz not null default now()
);
create trigger request_actions_immutable before update or delete on public.request_actions for each row execute function public.block_change();

create or replace function public.default_route(p_kind text) returns text[] language sql immutable as $$
  select case p_kind
    when 'leave' then array['m','p','g'] when 'permit' then array['m','p'] when 'cert' then array['p']
    when 'advance' then array['m','p','f','g'] when 'resign' then array['m','p','g','f']
    when 'settle' then array['p','f','g'] when 'expense' then array['m','f','g'] else array['p'] end
$$;

create or replace function public.step_label(p text) returns text language sql immutable as $$
  select case p when 'm' then 'المدير المباشر' when 'p' then 'الموارد البشرية' when 'f' then 'المالية' when 'g' then 'المدير العام' end
$$;

-- can the current user act on step p of a request?
create or replace function public.can_act(r public.requests, p text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.my_employee(r.company_id);
begin
  if me is not null and me = r.employee_id then return false; end if;   -- nobody approves their own request
  return case p
    when 'm' then exists(select 1 from public.employees e where e.id = r.employee_id and e.manager_id = me and me is not null)
    when 'p' then public.has_role(r.company_id, array['hr','admin'])
    when 'f' then public.has_role(r.company_id, array['finance'])
    when 'g' then public.has_role(r.company_id, array['owner'])
    else false end;
end $$;

create or replace function public.days_between(a date, b date) returns int language sql immutable as $$ select (b - a) + 1 $$;

-- Art. 117: the sick-leave year starts at the first sick day and runs 12 months (not the calendar year).
create or replace function public.sick_days_used(p_emp uuid, p_at date) returns int
language plpgsql stable security definer set search_path = public as $$
declare r record; ws date; used int := 0;
begin
  for r in select from_date, days from public.requests where employee_id = p_emp and kind = 'leave' and sub = 'sick'
           and status in ('pending','approved') and from_date < p_at order by from_date loop
    if ws is null or r.from_date >= (ws + interval '1 year')::date then ws := r.from_date; used := 0; end if;
    used := used + r.days;
  end loop;
  if ws is not null and p_at >= (ws + interval '1 year')::date then used := 0; end if;
  return used;
end $$;

create or replace function public.submit_request(
  p_company uuid, p_kind text, p_sub text default null, p_from date default null, p_to date default null,
  p_amount numeric default null, p_payload jsonb default '{}', p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := public.my_employee(p_company);
  e public.employees; lt public.leave_types; d int; used int; rt text[]; rid uuid; owner_emp uuid;
begin
  if me is null then raise exception 'حسابك غير مربوط بسجل موظف' using errcode = '42501'; end if;
  select * into e from public.employees where id = me;
  if e.end_date is not null and e.end_date < current_date then raise exception 'انتهت خدمتك'; end if;

  if p_kind = 'leave' then
    select * into lt from public.leave_types where code = p_sub;
    if not found then raise exception 'نوع إجازة غير معروف'; end if;
    if p_from is null or p_to is null then raise exception 'حدد تاريخ البداية والنهاية'; end if;
    if p_to < p_from then raise exception 'تاريخ النهاية قبل البداية'; end if;
    d := public.days_between(p_from, p_to);
    if exists(select 1 from public.requests where employee_id = me and kind = 'leave' and status in ('pending','approved')
              and p_from <= to_date and p_to >= from_date) then
      raise exception 'الفترة تتداخل مع إجازة سابقة'; end if;
    if lt.gender is not null and lt.gender <> e.gender then raise exception 'هذه الإجازة لا تنطبق عليك'; end if;
    if lt.max_days is not null and d > lt.max_days and lt.code <> 'sick' then raise exception 'الحد الأقصى لهذه الإجازة % يوماً', lt.max_days; end if;
    if lt.min_days is not null and d < lt.min_days then raise exception 'أقل مدة لهذه الإجازة % أيام', lt.min_days; end if;
    if lt.min_service_years is not null and (current_date - e.hire_date) / 365.0 < lt.min_service_years then
      raise exception 'تُمنح هذه الإجازة بعد % سنة خدمة', lt.min_service_years; end if;
    if lt.once_in_service and exists(select 1 from public.requests where employee_id = me and kind='leave' and sub = lt.code and status in ('pending','approved')) then
      raise exception 'هذه الإجازة تُمنح مرة واحدة خلال الخدمة'; end if;
    if lt.notice_days is not null and (p_from - current_date) < lt.notice_days then
      raise exception 'قدّم الطلب قبل % يوماً على الأقل', lt.notice_days; end if;
    if lt.code = 'sick' then
      used := public.sick_days_used(me, p_from);
      if used + d > 120 then raise exception 'تتجاوز 120 يوماً مرضية خلال سنة الإجازة المرضية (المستخدم %)', used; end if;
    end if;
    if lt.code = 'annual' then
      select coalesce(sum(days),0) into used from public.requests where employee_id = me and kind='leave' and sub='annual' and status in ('pending','approved');
      if d > public.annual_entitlement(e.hire_date, current_date) - used then
        raise exception 'رصيدك المتبقي % يوم', public.annual_entitlement(e.hire_date, current_date) - used; end if;
    end if;
  elsif p_kind = 'permit' then
    if coalesce((p_payload->>'hours')::numeric, 0) <= 0 or (p_payload->>'hours')::numeric > 4 then
      raise exception 'الاستئذان من دقائق حتى 4 ساعات'; end if;
  elsif p_kind in ('advance','expense') then
    if coalesce(p_amount,0) <= 0 then raise exception 'أدخل المبلغ'; end if;
    if p_kind = 'advance' and p_amount > e.basic then raise exception 'السلفة لا تزيد على الراتب الأساسي (%)', e.basic; end if;
    if p_kind = 'advance' and coalesce((p_payload->>'inst')::int, 1) not between 1 and 12 then raise exception 'عدد الأقساط من 1 إلى 12'; end if;
  elsif p_kind = 'resign' then
    if p_to is null or p_to < current_date then raise exception 'حدد آخر يوم عمل'; end if;
  end if;

  select route into rt from public.workflows where company_id = p_company and kind = p_kind;
  rt := coalesce(rt, public.default_route(p_kind));
  select m.employee_id into owner_emp from public.members m where m.company_id = p_company and m.role = 'owner' limit 1;
  -- drop steps that do not apply
  if e.manager_id is null then rt := array_remove(rt, 'm'); end if;
  if me = owner_emp or (e.manager_id = owner_emp and 'm' = any(rt)) then rt := array_remove(rt, 'g'); end if;

  insert into public.requests(company_id, employee_id, kind, sub, from_date, to_date, days, amount, payload, note, route, step, status)
  values (p_company, me, p_kind, p_sub, p_from, p_to, d, p_amount, coalesce(p_payload,'{}'), nullif(trim(p_note),''), rt, 0,
          case when cardinality(rt) = 0 then 'approved' else 'pending' end)
  returning id into rid;
  insert into public.request_actions(request_id, actor, action) values (rid, auth.uid(), 'submitted');
  return rid;
end $$;

create or replace function public.decide_request(p_id uuid, p_approve boolean, p_note text default null)
returns text language plpgsql security definer set search_path = public as $$
declare r public.requests; cur text; nxt int;
begin
  select * into r from public.requests where id = p_id for update;
  if not found then raise exception 'الطلب غير موجود'; end if;
  if r.status <> 'pending' then raise exception 'الطلب ليس بانتظار قرار'; end if;
  cur := r.route[r.step + 1];
  if not public.can_act(r, cur) then raise exception 'غير مصرح لك باعتماد هذه المرحلة (%)', public.step_label(cur) using errcode = '42501'; end if;
  if not p_approve then
    if coalesce(length(trim(p_note)),0) < 3 then raise exception 'اكتب سبب الرفض'; end if;
    update public.requests set status = 'rejected', decided_at = now() where id = p_id;
    insert into public.request_actions(request_id, actor, actor_step, action, note) values (p_id, auth.uid(), cur, 'rejected', trim(p_note));
    return 'rejected';
  end if;
  nxt := r.step + 1;
  insert into public.request_actions(request_id, actor, actor_step, action, note) values (p_id, auth.uid(), cur, 'approved', nullif(trim(p_note),''));
  if nxt >= cardinality(r.route) then
    update public.requests set step = nxt, status = 'approved', decided_at = now() where id = p_id;
    perform public.on_request_approved(p_id);
    return 'approved';
  end if;
  update public.requests set step = nxt where id = p_id;
  return 'next:' || r.route[nxt + 1];
end $$;

create or replace function public.cancel_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.requests;
begin
  select * into r from public.requests where id = p_id for update;
  if not found or r.employee_id is distinct from public.my_employee(r.company_id) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if r.status <> 'pending' then raise exception 'لا يمكن إلغاء طلب تم البت فيه'; end if;
  update public.requests set status = 'cancelled', decided_at = now() where id = p_id;
  insert into public.request_actions(request_id, actor, action) values (p_id, auth.uid(), 'cancelled');
end $$;

-- side effects of final approval (accounting + employee status)
create or replace function public.on_request_approved(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.requests; nm text;
begin
  select * into r from public.requests where id = p_id;
  select full_name into nm from public.employees where id = r.employee_id;
  if r.kind = 'advance' then
    perform public.post_journal(r.company_id, current_date, 'سلفة — ' || nm, 'advance', r.id,
      jsonb_build_array(jsonb_build_object('a','1500','d',r.amount), jsonb_build_object('a','1120','c',r.amount)));
  elsif r.kind = 'expense' then
    perform public.post_journal(r.company_id, current_date, 'مطالبة مصروفات — ' || nm, 'expense', r.id,
      jsonb_build_array(jsonb_build_object('a','5500','d',r.amount), jsonb_build_object('a','1120','c',r.amount)));
  elsif r.kind = 'resign' then
    update public.employees set end_date = r.to_date, end_reason = 'resign' where id = r.employee_id;
  end if;
end $$;

-- ---------- GOSI & end of service (pure functions) ----------
-- GOSI (verified against secondary sources, Oct 2026 — confirm with GOSI before production):
--  * contributory wage = basic + housing, min 1,500, max 45,000
--  * old regime (registered before 2024-07-03): employee 9% annuity + 0.75% SANED; employer 9% + 0.75% + 2% hazards
--  * new regime: annuity rises 0.5% for each side on 3 July 2025, 2026, 2027, 2028 (max 11%)
--  * non-Saudis: employer 2% occupational hazards only
create or replace function public.gosi_is_new(p_flag boolean, p_hire date) returns boolean language sql immutable as $$
  select coalesce(p_flag, p_hire >= date '2024-07-03')
$$;
create or replace function public.gosi_annuity(p_new boolean, p_as_of date) returns numeric language sql immutable as $$
  select case when not p_new then 9 else 9 + 0.5 * (
    (p_as_of >= date '2025-07-03')::int + (p_as_of >= date '2026-07-03')::int + (p_as_of >= date '2027-07-03')::int + (p_as_of >= date '2028-07-03')::int) end
$$;
create or replace function public.gosi_rate(p_new boolean, p_as_of date) returns numeric language sql immutable as $$
  select public.gosi_annuity(p_new, p_as_of) + 0.75
$$;
create or replace function public.gosi_base(p_basic numeric, p_housing numeric) returns numeric language sql immutable as $$
  select least(greatest(p_basic + p_housing, 1500), 45000)
$$;
create or replace function public.gosi_employee(p_saudi boolean, p_basic numeric, p_housing numeric, p_new boolean, p_as_of date)
returns numeric language sql immutable as $$
  select case when p_saudi then round(public.gosi_base(p_basic, p_housing) * public.gosi_rate(p_new, p_as_of) / 100, 2) else 0 end
$$;
create or replace function public.gosi_employer(p_saudi boolean, p_basic numeric, p_housing numeric, p_new boolean, p_as_of date)
returns numeric language sql immutable as $$
  select round(public.gosi_base(p_basic, p_housing) * case when p_saudi then public.gosi_annuity(p_new, p_as_of) + 0.75 + 2 else 2 end / 100, 2)
$$;

-- End of service, Labor Law Art. 84/85/87/80. Reason keys match the prototype.
create or replace function public.eos_fraction(p_reason text, p_years numeric) returns numeric language sql immutable as $$
  select case
    when p_reason = 'art80' then 0
    when p_reason = 'resign' then case when p_years < 2 then 0 when p_years < 5 then 1.0/3 when p_years < 10 then 2.0/3 else 1 end
    when p_reason in ('agree','expiry','employer','noreason','art81','resignw','resignfm','force','ret','disab','death') then 1
    else null end
$$;
create or replace function public.eos_calc(p_wage numeric, p_start date, p_end date, p_reason text, p_unused_leave numeric default 0)
returns table(years numeric, full_award numeric, fraction numeric, award numeric, leave_pay numeric, total numeric)
language plpgsql immutable as $$
declare y numeric; f numeric; fa numeric;
begin
  if p_end < p_start then raise exception 'نهاية الخدمة قبل بدايتها'; end if;
  f := public.eos_fraction(p_reason, 0);
  if f is null then raise exception 'سبب انتهاء خدمة غير معروف: %', p_reason; end if;
  y := ((p_end - p_start) + 1) / 365.0;
  fa := case when y <= 5 then p_wage / 2 * y else p_wage / 2 * 5 + p_wage * (y - 5) end;
  f := public.eos_fraction(p_reason, y);
  return query select round(y, 4), round(fa, 2), round(f, 4), round(fa * f, 0), round(p_wage / 30 * coalesce(p_unused_leave,0), 0),
                      round(fa * f, 0) + round(p_wage / 30 * coalesce(p_unused_leave,0), 0);
end $$;

-- ---------- payroll ----------
create table public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  year int not null check (year between 2020 and 2100),
  month int not null check (month between 1 and 12),
  pay_date date,
  status text not null default 'draft' check (status in ('draft','approved','paid')),
  approved_by uuid, approved_at timestamptz, paid_at timestamptz,
  unique (company_id, year, month)
);
create table public.payroll_lines (
  run_id uuid not null references public.payroll_runs(id) on delete cascade,
  employee_id uuid not null references public.employees(id),
  basic numeric(12,2) not null, housing numeric(12,2) not null, transport numeric(12,2) not null,
  gross numeric(12,2) not null,
  gosi numeric(12,2) not null default 0,
  employer_gosi numeric(12,2) not null default 0,
  absence_days numeric(6,2) not null default 0,
  absence numeric(12,2) not null default 0,
  overtime_hours numeric(6,2) not null default 0 check (overtime_hours >= 0),
  overtime numeric(12,2) not null default 0,
  bonus numeric(12,2) not null default 0 check (bonus >= 0),
  deductions numeric(12,2) not null default 0 check (deductions >= 0),
  advance numeric(12,2) not null default 0 check (advance >= 0),
  net numeric(12,2) not null,
  primary key (run_id, employee_id)
);

-- advance installments deducted per payroll run (one row per advance per run)
create table public.advance_deductions (
  run_id uuid not null references public.payroll_runs(id) on delete cascade,
  request_id uuid not null references public.requests(id),
  amount numeric(12,2) not null check (amount > 0),
  primary key (run_id, request_id)
);
create or replace function public.advance_remaining(p_req uuid) returns numeric language sql stable security definer set search_path = public as $$
  select r.amount - coalesce((select sum(amount) from public.advance_deductions where request_id = p_req),0) from public.requests r where r.id = p_req
$$;

create or replace function public.payroll_line_recalc(p_run uuid, p_emp uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; e public.employees; ms date; me date; ab numeric; l public.payroll_lines;
begin
  select * into r from public.payroll_runs where id = p_run;
  select * into e from public.employees where id = p_emp;
  select * into l from public.payroll_lines where run_id = p_run and employee_id = p_emp;
  ms := make_date(r.year, r.month, 1); me := (ms + interval '1 month - 1 day')::date;
  -- unpaid leave days inside the month
  select coalesce(sum(greatest(0, least(to_date, me) - greatest(from_date, ms) + 1)), 0) into ab
  from public.requests where employee_id = p_emp and kind = 'leave' and sub = 'unpaid' and status = 'approved' and from_date <= me and to_date >= ms;
  update public.payroll_lines set
    basic = e.basic, housing = e.housing, transport = e.transport, gross = e.basic + e.housing + e.transport,
    gosi = public.gosi_employee(e.is_saudi, e.basic, e.housing, public.gosi_is_new(e.gosi_new, e.hire_date), me),
    employer_gosi = public.gosi_employer(e.is_saudi, e.basic, e.housing, public.gosi_is_new(e.gosi_new, e.hire_date), me),
    absence_days = ab, absence = round((e.basic + e.housing + e.transport) / 30 * ab, 2),
    overtime = round(((e.basic + e.housing + e.transport) / 30 / 8 + 0.5 * e.basic / 30 / 8) * l.overtime_hours, 2)  -- Art. 107
  where run_id = p_run and employee_id = p_emp;
  update public.payroll_lines set advance = coalesce((select sum(d.amount) from public.advance_deductions d join public.requests q on q.id = d.request_id
                                                      where d.run_id = p_run and q.employee_id = p_emp),0)
   where run_id = p_run and employee_id = p_emp;
  update public.payroll_lines set net = gross + overtime + bonus - gosi - absence - deductions - advance where run_id = p_run and employee_id = p_emp;
end $$;

create or replace function public.payroll_prepare(p_company uuid, p_year int, p_month int, p_pay_date date default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare rid uuid; ms date := make_date(p_year, p_month, 1); me date := (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date; e record;
begin
  perform public.require_role(p_company, array['hr','admin','owner']);
  select id into rid from public.payroll_runs where company_id = p_company and year = p_year and month = p_month;
  if rid is null then
    insert into public.payroll_runs(company_id, year, month, pay_date) values (p_company, p_year, p_month, p_pay_date) returning id into rid;
  elsif (select status from public.payroll_runs where id = rid) <> 'draft' then
    raise exception 'المسير معتمد ولا يمكن تعديله';
  end if;
  delete from public.payroll_lines pl where pl.run_id = rid and not exists(
    select 1 from public.employees x where x.id = pl.employee_id and x.hire_date <= me and (x.end_date is null or x.end_date >= ms));
  for e in select id from public.employees where company_id = p_company and hire_date <= me and (end_date is null or end_date >= ms) loop
    insert into public.payroll_lines(run_id, employee_id, basic, housing, transport, gross, net) values (rid, e.id, 0,0,0,0,0) on conflict do nothing;
    -- next installment of each approved advance with a balance (once per run)
    insert into public.advance_deductions(run_id, request_id, amount)
    select rid, q.id, least(public.advance_remaining(q.id), round(q.amount / greatest(coalesce((q.payload->>'inst')::int,1),1), 2))
    from public.requests q
    where q.employee_id = e.id and q.kind = 'advance' and q.status = 'approved' and public.advance_remaining(q.id) > 0
      and not exists(select 1 from public.advance_deductions x where x.run_id = rid and x.request_id = q.id)
    on conflict do nothing;
    perform public.payroll_line_recalc(rid, e.id);
  end loop;
  return rid;
end $$;

create or replace function public.payroll_adjust(p_run uuid, p_emp uuid, p_ot_hours numeric, p_bonus numeric, p_deductions numeric)
returns void language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs;
begin
  select * into r from public.payroll_runs where id = p_run;
  perform public.require_role(r.company_id, array['hr','admin','owner']);
  if r.status <> 'draft' then raise exception 'المسير معتمد ولا يمكن تعديله'; end if;
  update public.payroll_lines set overtime_hours = coalesce(p_ot_hours,0), bonus = coalesce(p_bonus,0), deductions = coalesce(p_deductions,0)
   where run_id = p_run and employee_id = p_emp;
  if not found then raise exception 'الموظف غير موجود في المسير'; end if;
  perform public.payroll_line_recalc(p_run, p_emp);
end $$;

create or replace function public.payroll_approve(p_run uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; t record; me date; je uuid;
begin
  select * into r from public.payroll_runs where id = p_run for update;
  perform public.require_role(r.company_id, array['owner','finance']);
  if r.status <> 'draft' then raise exception 'المسير معتمد مسبقاً'; end if;
  select coalesce(sum(gross + overtime + bonus - absence - deductions),0) ex, coalesce(sum(gosi),0) g, coalesce(sum(employer_gosi),0) eg, coalesce(sum(advance),0) adv, coalesce(sum(net),0) n, count(*) c
    into t from public.payroll_lines where run_id = p_run;
  if t.c = 0 then raise exception 'المسير فارغ'; end if;
  me := (make_date(r.year, r.month, 1) + interval '1 month - 1 day')::date;
  je := public.post_journal(r.company_id, me, 'استحقاق رواتب ' || lpad(r.month::text,2,'0') || '/' || r.year, 'payroll', r.id,
    jsonb_build_array(jsonb_build_object('a','5200','d',t.ex), jsonb_build_object('a','5210','d',t.eg),
                      jsonb_build_object('a','2400','c',t.g + t.eg), jsonb_build_object('a','1500','c',t.adv), jsonb_build_object('a','2300','c',t.n)));
  update public.payroll_runs set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_run;
  return je;
end $$;

create or replace function public.payroll_mark_paid(p_run uuid, p_account text default '1120') returns uuid
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; n numeric; je uuid;
begin
  select * into r from public.payroll_runs where id = p_run for update;
  perform public.require_role(r.company_id, array['owner','finance']);
  if r.status <> 'approved' then raise exception 'اعتمد المسير قبل الصرف'; end if;
  select coalesce(sum(net),0) into n from public.payroll_lines where run_id = p_run;
  je := public.post_journal(r.company_id, coalesce(r.pay_date, current_date), 'صرف رواتب ' || lpad(r.month::text,2,'0') || '/' || r.year, 'payroll_pay', r.id,
    jsonb_build_array(jsonb_build_object('a','2300','d',n), jsonb_build_object('a',p_account,'c',n)));
  update public.payroll_runs set status = 'paid', paid_at = now() where id = p_run;
  return je;
end $$;

-- ---------- custody (عهد) ----------
create table public.custody (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id),
  item text not null check (length(trim(item)) >= 3),
  serial text,
  value numeric(12,2) not null default 0 check (value >= 0),
  issued date not null,
  returned date,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check (returned is null or returned >= issued)
);
create unique index custody_open_serial on public.custody(company_id, serial) where returned is null and serial is not null;

-- ---------- audit & RLS ----------
create trigger audit_employees after insert or update or delete on public.employees for each row execute function public.audit_trigger();
create trigger audit_requests after insert or update or delete on public.requests for each row execute function public.audit_trigger();
create trigger audit_payroll_runs after insert or update or delete on public.payroll_runs for each row execute function public.audit_trigger();
create trigger audit_custody after insert or update or delete on public.custody for each row execute function public.audit_trigger();

alter table public.departments enable row level security;
alter table public.employees enable row level security;
alter table public.leave_types enable row level security;
alter table public.workflows enable row level security;
alter table public.requests enable row level security;
alter table public.request_actions enable row level security;
alter table public.payroll_runs enable row level security;
alter table public.payroll_lines enable row level security;
alter table public.advance_deductions enable row level security;
alter table public.custody enable row level security;
create policy ad_read on public.advance_deductions for select using (exists(select 1 from public.payroll_runs r where r.id = run_id and public.has_role(r.company_id, array['owner','admin','hr','finance'])));
create policy cust_read on public.custody for select using (public.has_role(company_id, array['owner','admin','hr']) or employee_id = public.my_employee(company_id));
create policy cust_write on public.custody for all using (public.has_role(company_id, array['owner','admin','hr'])) with check (public.has_role(company_id, array['owner','admin','hr']));

create policy dept_read on public.departments for select using (public.is_member(company_id));
create policy dept_write on public.departments for all using (public.has_role(company_id, array['owner','admin','hr'])) with check (public.has_role(company_id, array['owner','admin','hr']));

create policy emp_read on public.employees for select using (
  public.has_role(company_id, array['owner','admin','hr','finance'])
  or id = public.my_employee(company_id)
  or manager_id = public.my_employee(company_id));
create policy emp_write on public.employees for all using (public.has_role(company_id, array['owner','admin','hr'])) with check (public.has_role(company_id, array['owner','admin','hr']));

create policy lt_read on public.leave_types for select using (auth.uid() is not null);

create policy wf_read on public.workflows for select using (public.is_member(company_id));
create policy wf_write on public.workflows for all using (public.has_role(company_id, array['owner','admin','hr'])) with check (public.has_role(company_id, array['owner','admin','hr']));

-- requests: visible to the requester, their manager, and HR/finance/owner. Writes only through RPCs.
create policy req_read on public.requests for select using (
  public.has_role(company_id, array['owner','admin','hr','finance'])
  or employee_id = public.my_employee(company_id)
  or exists(select 1 from public.employees e where e.id = requests.employee_id and e.manager_id = public.my_employee(requests.company_id)));
create policy ra_read on public.request_actions for select using (exists(select 1 from public.requests r where r.id = request_id));

create policy pr_read on public.payroll_runs for select using (public.has_role(company_id, array['owner','admin','hr','finance']));
create or replace function public.can_see_payline(p_run uuid, p_emp uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.payroll_runs r where r.id = p_run and (
    public.has_role(r.company_id, array['owner','admin','hr','finance'])
    or (p_emp = public.my_employee(r.company_id) and r.status <> 'draft')))
$$;
create policy pl_read on public.payroll_lines for select using (public.can_see_payline(run_id, employee_id));
-- employees see their own approved payroll runs (for payslips)
create policy pr_read_own on public.payroll_runs for select using (status <> 'draft' and exists(
  select 1 from public.payroll_lines l where l.run_id = payroll_runs.id and l.employee_id = public.my_employee(payroll_runs.company_id)));
