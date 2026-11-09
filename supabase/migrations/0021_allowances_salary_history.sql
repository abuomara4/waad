-- Extra fixed allowances (beyond housing and transport) and a salary history.
--  * Allowances paid regularly are part of the actual wage (Art. 2), so they count in payroll, overtime, absence,
--    end-of-service and fines; the GOSI basis stays basic + housing.
--  * Every change to basic, housing, transport or the allowances is logged with its reason and effective date.

create table public.employee_allowances (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  name_en text,
  amount numeric(12,2) not null check (amount > 0),
  start_on date not null default current_date,
  end_on date,
  note text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check (end_on is null or end_on >= start_on)
);
create index on public.employee_allowances(employee_id);

create table public.salary_history (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  effective_on date not null,
  basic numeric(12,2) not null, housing numeric(12,2) not null, transport numeric(12,2) not null,
  allowances numeric(12,2) not null default 0,
  gross numeric(12,2) not null,
  prev_gross numeric(12,2),
  reason text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index on public.salary_history(employee_id, created_at);

-- sum of the extra allowances active on a date (internal: called from security-definer functions only)
create or replace function public.emp_allow(p_emp uuid, p_on date) returns numeric
language sql stable set search_path = public as $$
  select coalesce(sum(amount), 0) from public.employee_allowances
   where employee_id = p_emp and start_on <= p_on and (end_on is null or end_on >= p_on)
$$;

create or replace function public.gross_wage(e public.employees) returns numeric language sql stable set search_path = public as $$
  select e.basic + e.housing + e.transport + public.emp_allow(e.id, current_date)
$$;

alter table public.payroll_lines add column allowances numeric(12,2) not null default 0;

-- writes a history row with the current figures
create or replace function public.salary_log(p_emp uuid, p_effective date, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare e public.employees; a numeric; pg numeric;
begin
  select * into e from public.employees where id = p_emp;
  a := public.emp_allow(p_emp, greatest(p_effective, current_date));
  select gross into pg from public.salary_history where employee_id = p_emp order by created_at desc, id desc limit 1;
  insert into public.salary_history(company_id, employee_id, effective_on, basic, housing, transport, allowances, gross, prev_gross, reason)
  values (e.company_id, p_emp, p_effective, e.basic, e.housing, e.transport, a, e.basic + e.housing + e.transport + a, pg, nullif(trim(p_reason), ''));
end $$;

create or replace function public.salary_trg() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform public.salary_log(new.id, new.hire_date, 'الأجر عند التعيين');
  elsif (new.basic, new.housing, new.transport) is distinct from (old.basic, old.housing, old.transport) then
    perform public.salary_log(new.id, coalesce(nullif(current_setting('waad.sal_on', true), '')::date, current_date),
                              coalesce(nullif(current_setting('waad.sal_reason', true), ''), 'تعديل من ملف الموظف'));
  end if;
  return null;
end $$;
create trigger salary_history_trg after insert or update of basic, housing, transport on public.employees for each row execute function public.salary_trg();

-- recalculates the employee's lines in draft payrolls
create or replace function public.payroll_recalc_emp(p_emp uuid) returns void
language sql security definer set search_path = public as $$
  select public.payroll_line_recalc(l.run_id, l.employee_id) from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id
   where r.status = 'draft' and l.employee_id = p_emp
$$;

-- salary change with a reason; a reduction needs the worker's written consent (the wage is a term of the contract)
create or replace function public.salary_change(p_emp uuid, p_basic numeric, p_housing numeric, p_transport numeric, p_effective date, p_reason text, p_consent boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare e public.employees;
begin
  select * into e from public.employees where id = p_emp for update;
  if not found then raise exception 'الموظف غير موجود'; end if;
  perform public.require_role(e.company_id, array['owner','admin','hr']);
  if coalesce(p_basic, -1) < 0 or coalesce(p_housing, -1) < 0 or coalesce(p_transport, -1) < 0 then raise exception 'أدخل مبالغ الأجر'; end if;
  if (p_basic, p_housing, p_transport) = (e.basic, e.housing, e.transport) then raise exception 'لم يتغير الأجر'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'اكتب سبب التعديل (ترقية، علاوة سنوية، تعديل عقد...)'; end if;
  if p_effective is null or p_effective > current_date then raise exception 'تاريخ السريان اليوم أو قبله — سجّل التعديل المستقبلي في يومه'; end if;
  if p_effective < e.hire_date then raise exception 'تاريخ السريان قبل تاريخ التعيين'; end if;
  if (p_basic < e.basic or p_basic + p_housing + p_transport < e.basic + e.housing + e.transport) and not coalesce(p_consent, false) then
    raise exception 'تخفيض الأجر تعديل لشرط في العقد — يلزم موافقة العامل الكتابية'; end if;
  perform set_config('waad.sal_reason', trim(p_reason), true);
  perform set_config('waad.sal_on', p_effective::text, true);
  update public.employees set basic = p_basic, housing = p_housing, transport = p_transport where id = p_emp;
  perform set_config('waad.sal_reason', '', true);
  perform set_config('waad.sal_on', '', true);
  perform public.payroll_recalc_emp(p_emp);
end $$;

-- add an allowance, or change/stop an existing one (allowances are never deleted, only ended)
create or replace function public.allowance_save(p_id uuid, p_emp uuid, p_name text, p_name_en text, p_amount numeric, p_start date, p_end date, p_note text)
returns uuid language plpgsql security definer set search_path = public as $$
declare e public.employees; a public.employee_allowances; rid uuid := p_id; why text;
begin
  if p_id is not null then
    select * into a from public.employee_allowances where id = p_id for update;
    if not found then raise exception 'البدل غير موجود'; end if;
    p_emp := a.employee_id;
  end if;
  select * into e from public.employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود'; end if;
  perform public.require_role(e.company_id, array['owner','admin','hr']);
  if length(trim(coalesce(p_name, ''))) = 0 then raise exception 'اكتب اسم البدل'; end if;
  if coalesce(p_amount, 0) <= 0 then raise exception 'مبلغ البدل الشهري أكبر من صفر'; end if;
  if p_start is null then raise exception 'حدد تاريخ بداية البدل'; end if;
  if p_end is not null and p_end < p_start then raise exception 'نهاية البدل قبل بدايته'; end if;
  if p_id is null then
    insert into public.employee_allowances(company_id, employee_id, name, name_en, amount, start_on, end_on, note)
    values (e.company_id, p_emp, trim(p_name), nullif(trim(p_name_en), ''), p_amount, p_start, p_end, nullif(trim(p_note), '')) returning id into rid;
    why := 'إضافة بدل: ' || trim(p_name);
  else
    update public.employee_allowances set name = trim(p_name), name_en = nullif(trim(p_name_en), ''), amount = p_amount, start_on = p_start, end_on = p_end, note = nullif(trim(p_note), '')
     where id = p_id;
    why := case when p_end is not null and a.end_on is null then 'إيقاف بدل: ' else 'تعديل بدل: ' end || trim(p_name);
  end if;
  if p_id is null or (p_amount, p_start, p_end) is distinct from (a.amount, a.start_on, a.end_on) then
    perform public.salary_log(p_emp, case when p_end is not null and (p_id is null or a.end_on is distinct from p_end) then p_end + 1 else p_start end, why);
  end if;
  perform public.payroll_recalc_emp(p_emp);
  return rid;
end $$;

create or replace function public.payroll_line_recalc(p_run uuid, p_emp uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; e public.employees; ms date; me date; ab numeric; l public.payroll_lines; g numeric; sk record; adv_sched numeric; room numeric;
        am record; deduct_late boolean; cap numeric; pen record; take numeric; pen_total numeric := 0; alw numeric;
begin
  select * into r from public.payroll_runs where id = p_run;
  select * into e from public.employees where id = p_emp;
  select * into l from public.payroll_lines where run_id = p_run and employee_id = p_emp;
  select att_deduct_late into deduct_late from public.companies where id = r.company_id;
  ms := make_date(r.year, r.month, 1); me := (ms + interval '1 month - 1 day')::date;
  alw := public.emp_allow(p_emp, me);   -- fixed extra allowances active at the month end are part of the actual wage (Art. 2)
  g := e.basic + e.housing + e.transport + alw;
  select coalesce(sum(greatest(0, least(to_date, me) - greatest(from_date, ms) + 1)), 0) into ab
  from public.requests where employee_id = p_emp and kind = 'leave' and sub = 'unpaid' and status = 'approved' and from_date <= me and to_date >= ms;
  select * into sk from public.sick_deduction(p_emp, ms, me, g / 30);
  select * into am from public.att_month(p_emp, ms, me);
  update public.payroll_lines set
    basic = e.basic, housing = e.housing, transport = e.transport, allowances = alw, gross = g,
    gosi = public.gosi_employee(e.is_saudi, e.basic, e.housing, public.gosi_is_new(e.gosi_new, e.hire_date), me),
    employer_gosi = public.gosi_employer(e.is_saudi, e.basic, e.housing, public.gosi_is_new(e.gosi_new, e.hire_date), me),
    absence_days = ab, absence = round(g / 30 * ab, 2),
    sick_days = sk.days, sick_deduction = sk.amount,
    att_absent_days = am.absent_days, att_absence = round(g / 30 * am.absent_days, 2),
    late_min = am.late_min, late_deduction = case when deduct_late then round(g / 30 / 8 / 60 * am.late_min, 2) else 0 end,
    att_ot_hours = round(am.ot_min / 60.0, 2),
    overtime = round((g / 30 / 8 + 0.5 * e.basic / 30 / 8) * (l.overtime_hours + round(am.ot_min / 60.0, 2)), 2)  -- Art. 107
  where run_id = p_run and employee_id = p_emp;
  select * into l from public.payroll_lines where run_id = p_run and employee_id = p_emp;
  -- disciplinary fines
  delete from public.penalty_deductions d using public.penalties p where d.run_id = p_run and p.id = d.penalty_id and p.employee_id = p_emp;
  cap := greatest(0, least(round(g / 30 * 5, 2) - l.deductions, round(g * 0.5, 2) - l.gosi - l.deductions - l.damages));
  for pen in select p.id, p.fine - coalesce((select sum(x.amount) from public.penalty_deductions x join public.payroll_runs rr on rr.id = x.run_id
                                                 where x.penalty_id = p.id and rr.status = 'approved'), 0) due
               from public.penalties p where p.employee_id = p_emp and p.status = 'applied' and p.fine > 0 and p.notified_on <= me
               order by p.notified_on, p.created_at loop
    exit when cap <= 0;
    take := least(pen.due, cap);
    if take > 0 then insert into public.penalty_deductions(run_id, penalty_id, amount) values (p_run, pen.id, take); cap := cap - take; pen_total := pen_total + take; end if;
  end loop;
  update public.payroll_lines set penalty_fine = pen_total where run_id = p_run and employee_id = p_emp;
  select coalesce(sum(d.amount),0) into adv_sched from public.advance_deductions d join public.requests q on q.id = d.request_id
   where d.run_id = p_run and q.employee_id = p_emp;
  room := greatest(0, round(g * 0.5, 2) - l.gosi - l.deductions - l.damages - pen_total);
  update public.payroll_lines set advance = least(adv_sched, round(g * 0.10, 2), room) where run_id = p_run and employee_id = p_emp;
  if adv_sched > least(adv_sched, round(g * 0.10, 2), room) then
    with x as (select d.request_id, d.amount, sum(d.amount) over (order by d.request_id) running from public.advance_deductions d
               join public.requests q on q.id = d.request_id where d.run_id = p_run and q.employee_id = p_emp)
    update public.advance_deductions ad set amount = greatest(0, least(x.amount, least(adv_sched, round(g * 0.10, 2), room) - (x.running - x.amount)))
      from x where ad.run_id = p_run and ad.request_id = x.request_id;
    delete from public.advance_deductions where run_id = p_run and amount <= 0;
  end if;
  update public.payroll_lines set net = gross + overtime + bonus - gosi - absence - att_absence - late_deduction - sick_deduction - deductions - penalty_fine - damages - advance
   where run_id = p_run and employee_id = p_emp;
end $$;

create or replace function public.eos_for_employee(p_emp uuid, p_end date, p_reason text, p_contract_end date default null)
returns table(wage numeric, service_days int, excluded_days int, years numeric, full_award numeric, fraction numeric, award numeric,
              leave_days numeric, leave_pay numeric, compensation numeric, total numeric)
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; w numeric; ex int := 0; sd int; y numeric; fa numeric; f numeric; lb numeric; comp numeric := 0; r record;
begin
  select * into e from public.employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود'; end if;
  perform public.require_role(e.company_id, array['owner','admin','hr','finance']);
  if p_end < e.hire_date then raise exception 'نهاية الخدمة قبل بدايتها'; end if;
  if public.eos_fraction(p_reason, 0) is null then raise exception 'سبب انتهاء خدمة غير معروف: %', p_reason; end if;
  w := public.gross_wage(e);                       -- Art. 84: last wage
  for r in select from_date, least(to_date, p_end) t from public.requests where employee_id = p_emp and kind = 'leave' and sub = 'unpaid' and status = 'approved' and from_date <= p_end loop
    ex := ex + greatest(0, (r.t - r.from_date + 1) - 20);      -- Art. 116: suspended beyond 20 days
  end loop;
  sd := (p_end - e.hire_date + 1) - ex;
  y := sd / 365.0;
  fa := case when y <= 5 then w / 2 * y else w / 2 * 5 + w * (y - 5) end;
  f := public.eos_fraction(p_reason, y);
  select greatest(0, b.balance) into lb from public.annual_leave_balance(p_emp, p_end) b;  -- Art. 111
  if p_reason = 'noreason' then                                  -- Art. 77
    comp := case when p_contract_end is null then greatest(w / 30 * 15 * y, w * 2)
                 else greatest(w / 30 * greatest(p_contract_end - p_end, 0), w * 2) end;
  end if;
  return query select w, sd, ex, round(y, 4), round(fa, 2), round(f, 4), round(fa * f, 2), coalesce(lb, 0), round(w / 30 * coalesce(lb, 0), 2),
                      round(comp, 2), round(fa * f, 2) + round(w / 30 * coalesce(lb, 0), 2) + round(comp, 2);
end $$;

create or replace function public.pen_calc(p_emp uuid, p_code text, p_on date, p_self uuid default null)
returns table(step int, action text, daily_wage numeric, fine numeric)
language plpgsql stable security definer set search_path = public as $$
declare v public.violation_types; e public.employees; base text; s int; a text; dw numeric;
begin
  select * into v from public.violation_types where code = p_code;
  if not found then raise exception 'المخالفة غير موجودة في جدول المخالفات — م67'; end if;
  select * into e from public.employees where id = p_emp;
  select penalty_base into base from public.companies where id = e.company_id;
  s := public.pen_step(p_emp, p_code, p_on, p_self);
  a := v.steps[s];
  while a = '-' and s > 1 loop s := s - 1; a := v.steps[s]; end loop;   -- no further step: keep the last one
  dw := round(case when base = 'basic' then e.basic else public.gross_wage(e) end / 30, 2);
  return query select s, a, dw,
    least(round(dw * 5, 2),   -- Art. 70: a fine for one violation never exceeds five days' wage
      case when a ~ '^p[0-9]+$' then round(dw * substr(a, 2)::numeric / 100, 2)
           when a ~ '^d[0-9]+$' then round(dw * substr(a, 2)::numeric, 2) else 0 end);
end $$;

create or replace function public.submit_request(
  p_company uuid, p_kind text, p_sub text default null, p_from date default null, p_to date default null,
  p_amount numeric default null, p_payload jsonb default '{}', p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := public.my_employee(p_company);
  e public.employees; lt public.leave_types; d int; used int; rt text[]; rid uuid; owner_emp uuid; k text; ev date; bal numeric; g numeric; minst int;
begin
  if me is null then raise exception 'حسابك غير مربوط بسجل موظف' using errcode = '42501'; end if;
  select * into e from public.employees where id = me;
  if e.end_date is not null and e.end_date < current_date then raise exception 'انتهت خدمتك'; end if;
  g := public.gross_wage(e);

  if p_kind = 'leave' then
    select * into lt from public.leave_types where code = p_sub;
    if not found then raise exception 'نوع إجازة غير معروف'; end if;
    if p_from is null or p_to is null then raise exception 'حدد تاريخ البداية والنهاية'; end if;
    if p_to < p_from then raise exception 'تاريخ النهاية قبل البداية'; end if;
    d := public.days_between(p_from, p_to);
    -- Reg. Art. 24(2): official holidays inside annual leave are not counted (the leave is extended by them)
    if p_sub = 'annual' then d := d - public.holidays_in(p_company, p_from, p_to); end if;
    if d <= 0 then raise exception 'الفترة كلها عطل رسمية'; end if;
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
    -- Art. 113/160: counted from the event date
    if lt.code in ('marriage','death','death2','birth','iddah','iddahn') then
      ev := nullif(p_payload->>'event_date','')::date;
      if ev is null then raise exception 'أدخل تاريخ الواقعة (الزواج/الوفاة/الولادة)'; end if;
      if ev > current_date + 30 then raise exception 'تاريخ الواقعة غير صحيح'; end if;
      if p_from < ev then raise exception 'تبدأ الإجازة من تاريخ الواقعة أو بعده'; end if;
      if lt.code = 'birth' and p_to > ev + 6 then raise exception 'إجازة المولود تؤخذ خلال 7 أيام من تاريخ الولادة — م113'; end if;
      if lt.code in ('marriage','death','death2') and p_to > ev + lt.max_days - 1 then
        raise exception 'تُحتسب هذه الإجازة من تاريخ الواقعة، فتنتهي في % — م113', ev + lt.max_days - 1; end if;
      if lt.code in ('iddah','iddahn') and p_from <> ev then raise exception 'تبدأ إجازة العدة من تاريخ الوفاة — م160'; end if;
    end if;
    if lt.code = 'sick' then
      used := public.sick_days_used(me, p_from);
      if used + d > 120 then raise exception 'تتجاوز 120 يوماً مرضية خلال سنة الإجازة المرضية (المستخدم %)', used; end if;
    end if;
    if lt.code = 'annual' then   -- Art. 109: accrued balance
      select coalesce(sum(days),0) into used from public.requests where employee_id = me and kind='leave' and sub='annual' and status in ('pending','approved');
      bal := floor(public.annual_leave_accrued(e.hire_date, p_to) - used);
      if d > bal then raise exception 'رصيدك المستحق حتى نهاية الإجازة % يوماً', greatest(bal, 0); end if;
    end if;
    -- Art. 115: exam leave — paid for an approved course (first attempt), unpaid for a repeated year, and from the
    -- annual balance (or unpaid when there is none) when the employer did not approve the enrolment
    if lt.code = 'exam' then
      if coalesce(p_payload->>'exam_mode', '') not in ('approved','repeat','own') then
        raise exception 'حدد حالة الدراسة: بموافقة المنشأة، أو سنة معادة، أو بدون موافقة المنشأة — م115'; end if;
      if p_payload->>'exam_mode' = 'repeat' then p_sub := 'unpaid';
      elsif p_payload->>'exam_mode' = 'own' then
        select coalesce(sum(days),0) into used from public.requests where employee_id = me and kind='leave' and sub='annual' and status in ('pending','approved');
        bal := floor(public.annual_leave_accrued(e.hire_date, p_to) - used);
        p_sub := case when bal >= d then 'annual' else 'unpaid' end;
      end if;
      p_payload := coalesce(p_payload, '{}'::jsonb) || jsonb_build_object('exam', true);
    end if;
    -- Reg. Art. 22-bis: compensatory leave is taken from the hours earned for overtime (8 hours a day)
    if lt.code = 'comp' then
      select balance_hours into bal from public.comp_balance(me);
      if d * 8 > coalesce(bal, 0) then raise exception 'رصيد الإجازة التعويضية % ساعة (% يوم)', coalesce(bal, 0), floor(coalesce(bal, 0) / 8); end if;
    end if;
  elsif p_kind = 'permit' then
    if coalesce((p_payload->>'hours')::numeric, 0) <= 0 or (p_payload->>'hours')::numeric > 4 then
      raise exception 'الاستئذان من دقائق حتى 4 ساعات'; end if;
  elsif p_kind in ('advance','expense') then
    if coalesce(p_amount,0) <= 0 then raise exception 'أدخل المبلغ'; end if;
    if p_kind = 'advance' then
      if p_amount > e.basic then raise exception 'السلفة لا تزيد على الراتب الأساسي (%)', e.basic; end if;
      minst := ceil(p_amount / (g * 0.10));
      if coalesce((p_payload->>'inst')::int, 1) < minst then
        raise exception 'القسط الشهري لا يزيد على 10%% من الأجر (% ريال) — اختر % أقساط على الأقل (م92)', round(g * 0.10, 2), minst; end if;
      if coalesce((p_payload->>'inst')::int, 1) > 24 then raise exception 'عدد الأقساط حتى 24'; end if;
    end if;
  elsif p_kind = 'resign' then   -- Art. 79-bis: no deferred date; ends on acceptance
    if p_to is not null and p_to > current_date then raise exception 'لا يصح تحديد تاريخ مؤجل للاستقالة — م79 مكرر'; end if;
    if exists(select 1 from public.requests where employee_id = me and kind = 'resign' and status = 'pending') then
      raise exception 'لديك طلب استقالة قيد المعالجة'; end if;
    p_from := current_date; p_to := null;
  elsif p_kind = 'update' then
    if p_payload is null or p_payload = '{}'::jsonb then raise exception 'حدد البيانات المطلوب تعديلها'; end if;
    for k in select jsonb_object_keys(p_payload) loop
      if not (k = any(public.update_request_fields())) then raise exception 'لا يمكن طلب تعديل الحقل «%»', k; end if;
    end loop;
    if p_payload ? 'iban' and coalesce(p_payload->>'iban','') !~ '^SA[0-9]{22}$' then raise exception 'الآيبان يبدأ بـ SA ويليه 22 رقماً'; end if;
    if p_payload ? 'email' and coalesce(p_payload->>'email','') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'البريد الإلكتروني غير صحيح'; end if;
    if p_payload ? 'phone' and coalesce(p_payload->>'phone','') !~ '^(05[0-9]{8}|\+9665[0-9]{8})$' then raise exception 'رقم الجوال بصيغة 05XXXXXXXX'; end if;
    if exists(select 1 from public.requests where employee_id = me and kind = 'update' and status = 'pending') then
      raise exception 'لديك طلب تعديل بيانات قيد المراجعة'; end if;
  end if;

  select route into rt from public.workflows where company_id = p_company and kind = p_kind;
  rt := coalesce(rt, public.default_route(p_kind));
  select m.employee_id into owner_emp from public.members m where m.company_id = p_company and m.role = 'owner' limit 1;
  if e.manager_id is null then rt := array_remove(rt, 'm'); end if;
  if me = owner_emp or (e.manager_id = owner_emp and 'm' = any(rt)) then rt := array_remove(rt, 'g'); end if;

  insert into public.requests(company_id, employee_id, kind, sub, from_date, to_date, days, amount, payload, note, route, step, status)
  values (p_company, me, p_kind, p_sub, p_from, p_to, d, p_amount, coalesce(p_payload,'{}'), nullif(trim(p_note),''), rt, 0,
          case when cardinality(rt) = 0 then 'approved' else 'pending' end)
  returning id into rid;
  insert into public.request_actions(request_id, actor, action) values (rid, auth.uid(), 'submitted');
  if cardinality(rt) = 0 then perform public.on_request_approved(rid); end if;
  return rid;
end $$;

create or replace function public.issue_letter(p_emp uuid, p_kind text, p_lang text default 'ar', p_to text default null,
  p_salary boolean default true, p_nat text default null, p_request uuid default null, p_en jsonb default null)
returns public.letters language plpgsql security definer set search_path = public as $$
declare e public.employees; c public.companies; r public.requests; hr boolean; td date := (now() at time zone 'Asia/Riyadh')::date;
  dept text; l public.letters; v_sal boolean := coalesce(p_salary, true);
begin
  select * into e from public.employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود'; end if;
  hr := public.has_role(e.company_id, array['owner','admin','hr']);
  if not hr then
    -- an employee prints own salary certificate only against an approved request
    if e.id is distinct from public.my_employee(e.company_id) or p_kind <> 'salary' then raise exception 'غير مصرح' using errcode = '42501'; end if;
    select * into r from public.requests where id = p_request and employee_id = e.id and kind = 'cert' and status = 'approved';
    if not found then raise exception 'يصدر الخطاب بعد اعتماد طلب التعريف بالراتب'; end if;
  elsif p_request is not null then
    select * into r from public.requests where id = p_request and employee_id = e.id and kind = 'cert';
    if not found then raise exception 'الطلب لا يخص هذا الموظف'; end if;
  end if;
  if p_kind not in ('salary','service') then raise exception 'نوع الخطاب غير معروف'; end if;
  if coalesce(p_lang, 'ar') not in ('ar','en') then raise exception 'لغة الخطاب غير معروفة'; end if;
  if p_kind = 'salary' and e.end_date is not null and e.end_date < td then
    raise exception 'الموظف ليس على رأس العمل — أصدر له شهادة خدمة'; end if;
  if p_kind = 'service' then
    if e.end_date is null then raise exception 'شهادة الخدمة تصدر عند انتهاء العلاقة التعاقدية — سجّل تاريخ نهاية الخدمة أولاً (م64)'; end if;
    if e.end_date > td then raise exception 'تصدر شهادة الخدمة في آخر يوم عمل أو بعده (م64)'; end if;
    v_sal := true;   -- Art. 64: the last wage is a required part of the certificate
  end if;
  if r.id is not null and exists(select 1 from public.letters where request_id = r.id and lang = coalesce(p_lang, 'ar')) then
    raise exception 'صدر خطاب لهذا الطلب بهذه اللغة — اطبعه من سجل الخطابات'; end if;
  select * into c from public.companies where id = e.company_id;
  select name into dept from public.departments where id = e.department_id;
  insert into public.letters(company_id, employee_id, kind, lang, ref_no, addressee, with_salary, request_id, data)
  values (e.company_id, e.id, p_kind, coalesce(p_lang, 'ar'), public.next_doc_no(e.company_id, 'LTR'), nullif(trim(p_to), ''), v_sal, r.id,
    jsonb_build_object(
      'company', jsonb_build_object('name', c.name, 'cr_no', c.cr_no, 'vat_no', c.vat_no, 'address', c.address),
      'employee', jsonb_build_object('full_name', e.full_name, 'emp_no', e.emp_no, 'gender', e.gender, 'is_saudi', e.is_saudi,
        'nationality', coalesce(nullif(trim(p_nat), ''), case when e.is_saudi then 'سعودي' end), 'national_id', e.national_id,
        'job_title', e.job_title, 'department', dept, 'hire_date', e.hire_date, 'end_date', case when p_kind = 'service' then e.end_date end),
      'wage', case when v_sal then jsonb_build_object('basic', e.basic, 'housing', e.housing, 'transport', e.transport, 'other', public.emp_allow(e.id, current_date), 'gross', public.gross_wage(e)) end,
      'en', jsonb_strip_nulls(jsonb_build_object('name', coalesce(nullif(trim(p_en->>'name'), ''), e.full_name_en), 'job', coalesce(nullif(trim(p_en->>'job'), ''), e.job_title_en),
        'company', coalesce(nullif(trim(p_en->>'company'), ''), c.name_en))),
      'date', td))
  returning * into l;
  return l;
end $$;

-- opening history for employees that already exist
insert into public.salary_history(company_id, employee_id, effective_on, basic, housing, transport, allowances, gross, reason, created_by)
select company_id, id, hire_date, basic, housing, transport, 0, basic + housing + transport, 'الأجر عند بدء التسجيل', null from public.employees e
 where not exists(select 1 from public.salary_history h where h.employee_id = e.id);

create trigger audit_employee_allowances after insert or update or delete on public.employee_allowances for each row execute function public.audit_trigger();
alter table public.employee_allowances enable row level security;
alter table public.salary_history enable row level security;
create policy ea_read on public.employee_allowances for select using (public.has_role(company_id, array['owner','admin','hr','finance']) or employee_id = public.my_employee(company_id));
create policy sh_read on public.salary_history for select using (public.has_role(company_id, array['owner','admin','hr','finance']) or employee_id = public.my_employee(company_id));
revoke all on public.employee_allowances, public.salary_history from anon;
grant select on public.employee_allowances, public.salary_history to authenticated;
revoke insert, update, delete on public.employee_allowances, public.salary_history from authenticated;
revoke all on function public.emp_allow(uuid, date), public.salary_log(uuid, date, text), public.salary_trg(), public.payroll_recalc_emp(uuid) from public, anon, authenticated;
revoke all on function public.salary_change(uuid, numeric, numeric, numeric, date, text, boolean), public.allowance_save(uuid, uuid, text, text, numeric, date, date, text) from public, anon;
grant execute on function public.salary_change(uuid, numeric, numeric, numeric, date, text, boolean), public.allowance_save(uuid, uuid, text, text, numeric, date, date, text) to authenticated;
notify pgrst, 'reload schema';
