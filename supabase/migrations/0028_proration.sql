-- Pay for part of a month (30-day month): joiners, leavers, and wage or allowance changes that take effect mid-month.
--  * The month is 30 slots; slot k is day k (the 31st is not paid separately; the last days of February count up to 30).
--  * For each slot the employee is paid 1/30 of the wage in force that day (salary history) plus the extra allowances
--    active that day. Daily rates for absence, lateness and overtime use the wage in force on the last day worked.
--  * GOSI stays on the wage registered at month end (unchanged).

alter table public.salary_history add column wage_change boolean not null default true;
update public.salary_history set wage_change = false where reason like 'إضافة بدل: %' or reason like 'إيقاف بدل: %' or reason like 'تعديل بدل: %';
alter table public.payroll_lines add column paid_days int not null default 30 check (paid_days between 0 and 30);

create or replace function public.salary_log(p_emp uuid, p_effective date, p_reason text, p_wage boolean default true) returns void
language plpgsql security definer set search_path = public as $$
declare e public.employees; a numeric; pg numeric;
begin
  select * into e from public.employees where id = p_emp;
  a := public.emp_allow(p_emp, greatest(p_effective, current_date));
  select gross into pg from public.salary_history where employee_id = p_emp order by created_at desc, id desc limit 1;
  insert into public.salary_history(company_id, employee_id, effective_on, basic, housing, transport, allowances, gross, prev_gross, reason, wage_change)
  values (e.company_id, p_emp, p_effective, e.basic, e.housing, e.transport, a, e.basic + e.housing + e.transport + a, pg, nullif(trim(p_reason), ''), p_wage);
end $$;
drop function public.salary_log(uuid, date, text);

-- the allowance log rows do not carry a wage change (their basic/housing/transport are only a snapshot)
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
    perform public.salary_log(p_emp, case when p_end is not null and (p_id is null or a.end_on is distinct from p_end) then p_end + 1 else p_start end, why, false);
  end if;
  perform public.payroll_recalc_emp(p_emp);
  return rid;
end $$;

-- the wage earned in a month (internal)
create or replace function public.wage_month(p_emp uuid, p_ms date, p_me date)
returns table(days int, basic numeric, housing numeric, transport numeric, allowances numeric, rate_basic numeric, rate_housing numeric, rate_gross numeric)
language sql stable set search_path = public as $$
  with e as (select * from public.employees where id = p_emp),
  s as (select k, least(p_ms + (k - 1), p_me) d from generate_series(1, 30) k),
  w as (select s.k, coalesce(h.basic, e.basic) b, coalesce(h.housing, e.housing) hs, coalesce(h.transport, e.transport) t, public.emp_allow(p_emp, s.d) a
          from s cross join e
          left join lateral (select x.basic, x.housing, x.transport from public.salary_history x
                              where x.employee_id = p_emp and x.wage_change and x.effective_on <= s.d
                              order by x.effective_on desc, x.created_at desc, x.id desc limit 1) h on true
         where e.hire_date <= s.d and (e.end_date is null or e.end_date >= s.d)),
  l as (select * from w order by k desc limit 1)
  select count(*)::int, round(coalesce(sum(w.b), 0) / 30, 2), round(coalesce(sum(w.hs), 0) / 30, 2), round(coalesce(sum(w.t), 0) / 30, 2), round(coalesce(sum(w.a), 0) / 30, 2),
         coalesce((select b from l), (select basic from e)), coalesce((select hs from l), (select housing from e)),
         coalesce((select b + hs + t + a from l), (select basic + housing + transport from e) + public.emp_allow(p_emp, p_me))
    from w
$$;

create or replace function public.payroll_line_recalc(p_run uuid, p_emp uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; e public.employees; ms date; me date; ab numeric; l public.payroll_lines; g numeric; gp numeric; sk record; adv_sched numeric; room numeric;
        am record; deduct_late boolean; cap numeric; pen record; take numeric; pen_total numeric := 0; wm record;
begin
  select * into r from public.payroll_runs where id = p_run;
  select * into e from public.employees where id = p_emp;
  select * into l from public.payroll_lines where run_id = p_run and employee_id = p_emp;
  select att_deduct_late into deduct_late from public.companies where id = r.company_id;
  ms := make_date(r.year, r.month, 1); me := (ms + interval '1 month - 1 day')::date;
  select * into wm from public.wage_month(p_emp, ms, me);
  g := wm.rate_gross;                                              -- daily rates: the wage in force on the last day worked
  gp := wm.basic + wm.housing + wm.transport + wm.allowances;     -- what is earned this month (Art. 2: allowances are wage)
  select coalesce(sum(greatest(0, least(to_date, me, coalesce(e.end_date, me)) - greatest(from_date, ms, e.hire_date) + 1)), 0) into ab
  from public.requests where employee_id = p_emp and kind = 'leave' and sub = 'unpaid' and status = 'approved' and from_date <= me and to_date >= ms;
  ab := least(ab, wm.days);
  select * into sk from public.sick_deduction(p_emp, ms, me, g / 30);
  select * into am from public.att_month(p_emp, ms, me);
  update public.payroll_lines set
    basic = wm.basic, housing = wm.housing, transport = wm.transport, allowances = wm.allowances, gross = gp, paid_days = wm.days,
    gosi = public.gosi_employee(e.is_saudi, wm.rate_basic, wm.rate_housing, public.gosi_is_new(e.gosi_new, e.hire_date), me),
    employer_gosi = public.gosi_employer(e.is_saudi, wm.rate_basic, wm.rate_housing, public.gosi_is_new(e.gosi_new, e.hire_date), me),
    absence_days = ab, absence = round(g / 30 * ab, 2),
    sick_days = sk.days, sick_deduction = sk.amount,
    att_absent_days = am.absent_days, att_absence = round(g / 30 * am.absent_days, 2),
    late_min = am.late_min, late_deduction = case when deduct_late then round(g / 30 / 8 / 60 * am.late_min, 2) else 0 end,
    att_ot_hours = round(am.ot_min / 60.0, 2),
    overtime = round((g / 30 / 8 + 0.5 * wm.rate_basic / 30 / 8) * (l.overtime_hours + round(am.ot_min / 60.0, 2)), 2)  -- Art. 107
  where run_id = p_run and employee_id = p_emp;
  select * into l from public.payroll_lines where run_id = p_run and employee_id = p_emp;
  -- disciplinary fines (Art. 70/92 caps: five days' wage per month, half the wage due)
  delete from public.penalty_deductions d using public.penalties p where d.run_id = p_run and p.id = d.penalty_id and p.employee_id = p_emp;
  cap := greatest(0, least(round(g / 30 * 5, 2) - l.deductions, round(gp * 0.5, 2) - l.gosi - l.deductions - l.damages));
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
  room := greatest(0, round(gp * 0.5, 2) - l.gosi - l.deductions - l.damages - pen_total);
  update public.payroll_lines set advance = least(adv_sched, round(gp * 0.10, 2), room) where run_id = p_run and employee_id = p_emp;
  if adv_sched > least(adv_sched, round(gp * 0.10, 2), room) then
    with x as (select d.request_id, d.amount, sum(d.amount) over (order by d.request_id) running from public.advance_deductions d
               join public.requests q on q.id = d.request_id where d.run_id = p_run and q.employee_id = p_emp)
    update public.advance_deductions ad set amount = greatest(0, least(x.amount, least(adv_sched, round(gp * 0.10, 2), room) - (x.running - x.amount)))
      from x where ad.run_id = p_run and ad.request_id = x.request_id;
    delete from public.advance_deductions where run_id = p_run and amount <= 0;
  end if;
  update public.payroll_lines set net = gross + overtime + bonus - gosi - absence - att_absence - late_deduction - sick_deduction - deductions - penalty_fine - damages - advance
   where run_id = p_run and employee_id = p_emp;
end $$;

-- refresh draft payrolls with the new rules
select public.payroll_line_recalc(l.run_id, l.employee_id) from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id where r.status = 'draft';

revoke all on function public.wage_month(uuid, date, date), public.salary_log(uuid, date, text, boolean) from public, anon, authenticated;
notify pgrst, 'reload schema';
