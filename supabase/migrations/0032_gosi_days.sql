-- Per the regulations:
--  * GOSI contributions are due for the days worked in the establishment (GOSI, from 1 Feb 2022): the monthly
--    contribution x days / 30 — for joiners and leavers mid-month, and for the previous month's days paid as dues.
--  * A wage is due for every day worked: someone who joins on the 31st is paid one day (1/30).

create or replace function public.wage_month(p_emp uuid, p_ms date, p_me date)
returns table(days int, basic numeric, housing numeric, transport numeric, allowances numeric, rate_basic numeric, rate_housing numeric, rate_gross numeric)
language sql stable set search_path = public as $$
  with e as (select * from public.employees where id = p_emp),
  -- slot 30 also covers the 31st, so someone who joins on the 31st is paid one day
  s0 as (select k, least(p_ms + (k - 1), p_me) d from generate_series(1, 30) k),
  s as (select s0.k, case when s0.k = 30 and s0.d < p_me and not exists(select 1 from e where e.hire_date <= s0.d) then p_me else s0.d end d from s0),
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
        am record; deduct_late boolean; cap numeric; pen record; take numeric; pen_total numeric := 0; wm record; pp record; vps date; vpe date;
        pms date; pme date; pr public.payroll_runs; arr numeric := 0; arr_days int := 0; wp record; gnew boolean; ge numeric := 0; gr numeric := 0;
begin
  select * into r from public.payroll_runs where id = p_run;
  select * into e from public.employees where id = p_emp;
  select * into l from public.payroll_lines where run_id = p_run and employee_id = p_emp;
  select att_deduct_late into deduct_late from public.companies where id = r.company_id;
  ms := make_date(r.year, r.month, 1); me := (ms + interval '1 month - 1 day')::date;
  select * into pp from public.payroll_period(r.company_id, r.year, r.month);
  vps := pp.ps;                                                    -- attendance / leave period of this payroll
  vpe := case when e.end_date between ms and me then me else least(pp.pe, me) end;   -- a leaver's last payroll runs to the last day
  select * into wm from public.wage_month(p_emp, ms, me);
  g := wm.rate_gross;                                              -- daily rates: the wage in force on the last day worked
  gp := wm.basic + wm.housing + wm.transport + wm.allowances;     -- what is earned this month (Art. 2: allowances are wage)
  -- previous month's days of someone who was not in last month's (closed) payroll: a joiner after the cutoff
  pms := (ms - interval '1 month')::date; pme := ms - 1;
  select * into pr from public.payroll_runs where company_id = r.company_id and year = extract(year from pms)::int and month = extract(month from pms)::int;
  if e.hire_date between pms and pme and pr.id is not null and pr.status <> 'draft'
     and not exists(select 1 from public.payroll_lines x where x.run_id = pr.id and x.employee_id = p_emp) then
    select * into wp from public.wage_month(p_emp, pms, pme);
    arr := wp.basic + wp.housing + wp.transport + wp.allowances; arr_days := wp.days;
  end if;
  -- GOSI by the days worked in the month (since Feb 2022), plus the previous month's days paid as dues
  gnew := public.gosi_is_new(e.gosi_new, e.hire_date);
  ge := round(public.gosi_employee(e.is_saudi, wm.rate_basic, wm.rate_housing, gnew, me) * wm.days / 30.0, 2);
  gr := round(public.gosi_employer(e.is_saudi, wm.rate_basic, wm.rate_housing, gnew, me) * wm.days / 30.0, 2);
  if arr_days > 0 then
    ge := ge + round(public.gosi_employee(e.is_saudi, wp.rate_basic, wp.rate_housing, gnew, pme) * arr_days / 30.0, 2);
    gr := gr + round(public.gosi_employer(e.is_saudi, wp.rate_basic, wp.rate_housing, gnew, pme) * arr_days / 30.0, 2);
  end if;
  select coalesce(sum(greatest(0, least(to_date, vpe, coalesce(e.end_date, vpe)) - greatest(from_date, vps, e.hire_date) + 1)), 0) into ab
  from public.requests where employee_id = p_emp and kind = 'leave' and sub = 'unpaid' and status = 'approved' and from_date <= vpe and to_date >= vps;
  select * into sk from public.sick_deduction(p_emp, vps, vpe, g / 30);
  select * into am from public.att_month(p_emp, vps, vpe);
  update public.payroll_lines set
    basic = wm.basic, housing = wm.housing, transport = wm.transport, allowances = wm.allowances, gross = gp, paid_days = wm.days,
    arrears = arr, arrears_days = arr_days,
    gosi = ge, employer_gosi = gr,
    absence_days = ab, absence = round(g / 30 * ab, 2),
    sick_days = sk.days, sick_deduction = sk.amount,
    att_absent_days = am.absent_days, att_absence = round(g / 30 * am.absent_days, 2),
    late_min = am.late_min, late_deduction = case when deduct_late then round(g / 30 / 8 / 60 * am.late_min, 2) else 0 end,
    att_ot_hours = round(am.ot_min / 60.0, 2),
    overtime = round((g / 30 / 8 + 0.5 * wm.rate_basic / 30 / 8) * (l.overtime_hours + round(am.ot_min / 60.0, 2)), 2)  -- Art. 107
  where run_id = p_run and employee_id = p_emp;
  select * into l from public.payroll_lines where run_id = p_run and employee_id = p_emp;
  gp := gp + arr;                                                  -- the caps below apply to all the wage due in this payroll
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
  update public.payroll_lines set net = gross + arrears + overtime + bonus - gosi - absence - att_absence - late_deduction - sick_deduction - deductions - penalty_fine - damages - advance
   where run_id = p_run and employee_id = p_emp;
end $$;

select public.payroll_line_recalc(l.run_id, l.employee_id) from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id where r.status = 'draft';
revoke all on function public.wage_month(uuid, date, date) from public, anon, authenticated;
notify pgrst, 'reload schema';
