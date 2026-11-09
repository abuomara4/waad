-- Payroll cutoff day (optional, per company). With a cutoff of 21:
--  * the October payroll counts attendance, absence, lateness, overtime, unpaid and sick leave from 21 Sep to 20 Oct;
--  * someone who joins on or after 21 Oct is left out of the October payroll and paid those October days in November,
--    as "previous month's dues", together with the full November wage.
--  * leavers are not held back: their last payroll counts up to their last day.
-- The period of each approved payroll is frozen, so switching the cutoff on or off later never counts a day twice or skips it.

alter table public.companies add column payroll_cutoff int check (payroll_cutoff between 2 and 28);
alter table public.payroll_runs add column att_from date, add column att_to date;
update public.payroll_runs set att_from = make_date(year, month, 1), att_to = (make_date(year, month, 1) + interval '1 month - 1 day')::date where status <> 'draft';
alter table public.payroll_lines add column arrears numeric(12,2) not null default 0, add column arrears_days int not null default 0;

-- the attendance period of a month's payroll
create or replace function public.payroll_period(p_company uuid, p_year int, p_month int)
returns table(ps date, pe date) language plpgsql stable security definer set search_path = public as $$
declare cut int; r public.payroll_runs; pr public.payroll_runs; ms date := make_date(p_year, p_month, 1); pms date;
begin
  select * into r from public.payroll_runs where company_id = p_company and year = p_year and month = p_month;
  if r.status <> 'draft' and r.att_from is not null then return query select r.att_from, r.att_to; return; end if;   -- frozen at approval
  select payroll_cutoff into cut from public.companies where id = p_company;
  pms := (ms - interval '1 month')::date;
  select * into pr from public.payroll_runs where company_id = p_company and year = extract(year from pms)::int and month = extract(month from pms)::int;
  return query select coalesce(case when pr.status <> 'draft' then pr.att_to + 1 end, case when cut is null then ms else make_date(extract(year from pms)::int, extract(month from pms)::int, cut) end),
                      case when cut is null then (ms + interval '1 month - 1 day')::date else make_date(p_year, p_month, cut - 1) end;
end $$;

create or replace function public.payroll_cutoff_set(p_company uuid, p_day int) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if p_day is not null and (p_day < 2 or p_day > 28) then raise exception 'يوم الإقفال بين 2 و28'; end if;
  update public.companies set payroll_cutoff = p_day where id = p_company;
  perform public.payroll_prepare(p_company, r.year, r.month, r.pay_date) from public.payroll_runs r where r.company_id = p_company and r.status = 'draft';
end $$;

-- who is in a month's payroll: joiners after the period end wait for next month; leavers stay until their last day
create or replace function public.payroll_prepare(p_company uuid, p_year int, p_month int, p_pay_date date default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare rid uuid; ms date := make_date(p_year, p_month, 1); me date := (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date; e record; ps date; pe date;
begin
  perform public.require_role(p_company, array['hr','admin','owner']);
  select id into rid from public.payroll_runs where company_id = p_company and year = p_year and month = p_month;
  if rid is null then
    insert into public.payroll_runs(company_id, year, month, pay_date) values (p_company, p_year, p_month, p_pay_date) returning id into rid;
  elsif (select status from public.payroll_runs where id = rid) <> 'draft' then
    raise exception 'المسير معتمد ولا يمكن تعديله';
  end if;
  select x.ps, least(x.pe, me) into ps, pe from public.payroll_period(p_company, p_year, p_month) x;
  update public.payroll_runs set att_from = ps, att_to = pe where id = rid;   -- shown on the draft; recomputed on every preparation
  delete from public.payroll_lines pl where pl.run_id = rid and not exists(
    select 1 from public.employees x where x.id = pl.employee_id and x.hire_date <= pe and (x.end_date is null or x.end_date >= ms));
  for e in select id from public.employees where company_id = p_company and hire_date <= pe and (end_date is null or end_date >= ms) loop
    insert into public.payroll_lines(run_id, employee_id, basic, housing, transport, gross, net) values (rid, e.id, 0,0,0,0,0) on conflict do nothing;
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

create or replace function public.payroll_line_recalc(p_run uuid, p_emp uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; e public.employees; ms date; me date; ab numeric; l public.payroll_lines; g numeric; gp numeric; sk record; adv_sched numeric; room numeric;
        am record; deduct_late boolean; cap numeric; pen record; take numeric; pen_total numeric := 0; wm record; pp record; vps date; vpe date;
        pms date; pme date; pr public.payroll_runs; arr numeric := 0; arr_days int := 0; wp record;
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
  select coalesce(sum(greatest(0, least(to_date, vpe, coalesce(e.end_date, vpe)) - greatest(from_date, vps, e.hire_date) + 1)), 0) into ab
  from public.requests where employee_id = p_emp and kind = 'leave' and sub = 'unpaid' and status = 'approved' and from_date <= vpe and to_date >= vps;
  select * into sk from public.sick_deduction(p_emp, vps, vpe, g / 30);
  select * into am from public.att_month(p_emp, vps, vpe);
  update public.payroll_lines set
    basic = wm.basic, housing = wm.housing, transport = wm.transport, allowances = wm.allowances, gross = gp, paid_days = wm.days,
    arrears = arr, arrears_days = arr_days,
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

-- approval: the previous month's dues are part of the wage expense, and the period is frozen
create or replace function public.payroll_approve(p_run uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; t record; me date; je uuid; pp record;
begin
  select * into r from public.payroll_runs where id = p_run for update;
  perform public.require_role(r.company_id, array['owner','finance']);
  if r.status <> 'draft' then raise exception 'المسير معتمد مسبقاً'; end if;
  select coalesce(sum(gross + arrears + overtime + bonus - absence - att_absence - late_deduction - sick_deduction - damages),0) ex, coalesce(sum(gosi),0) g, coalesce(sum(employer_gosi),0) eg,
         coalesce(sum(advance),0) adv, coalesce(sum(net),0) n, coalesce(sum(deductions + penalty_fine),0) fines, count(*) c
    into t from public.payroll_lines where run_id = p_run;
  if t.c = 0 then raise exception 'المسير فارغ'; end if;
  insert into public.accounts(company_id, code, name, type, parent_code, is_header)
  values (r.company_id, '2450', 'غرامات العاملين — لصالح العمال (م73)', 'liab', '2000', false) on conflict do nothing;
  me := (make_date(r.year, r.month, 1) + interval '1 month - 1 day')::date;
  je := public.post_journal(r.company_id, me, 'استحقاق رواتب ' || lpad(r.month::text,2,'0') || '/' || r.year, 'payroll', r.id,
    jsonb_build_array(jsonb_build_object('a','5200','d',t.ex), jsonb_build_object('a','5210','d',t.eg),
                      jsonb_build_object('a','2400','c',t.g + t.eg), jsonb_build_object('a','1500','c',t.adv),
                      jsonb_build_object('a','2450','c',t.fines), jsonb_build_object('a','2300','c',t.n)));
  select * into pp from public.payroll_period(r.company_id, r.year, r.month);
  update public.payroll_runs set status = 'approved', approved_by = auth.uid(), approved_at = now(), att_from = pp.ps, att_to = least(pp.pe, me) where id = p_run;
  return je;
end $$;

-- refresh draft payrolls
select public.payroll_line_recalc(l.run_id, l.employee_id) from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id where r.status = 'draft';

revoke all on function public.payroll_period(uuid, int, int) from public, anon, authenticated;
revoke all on function public.payroll_cutoff_set(uuid, int) from public, anon;
grant execute on function public.payroll_cutoff_set(uuid, int) to authenticated;
notify pgrst, 'reload schema';
