-- Employee 360: one page with the employee's work profile, pay, contract, attendance of the last 30 days, leave balance,
-- requests, penalties, reviews, custody and documents. Who sees it: HR and management (and holders of «hr_emp»), the employee
-- himself, and his direct manager. Pay (salary, payslips) only for HR / owner / admin / finance, «hr_pay» holders and the
-- employee himself — never the manager. Penalties: HR and the employee. Limited users stay inside their branches.

create or replace function public.employee_360(p_company uuid, p_emp uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; me uuid := public.my_employee(p_company); hr boolean; self boolean; mgr boolean; pay boolean; bal numeric; d0 date := current_date - 30;
begin
  select * into e from public.employees where id = p_emp and company_id = p_company;
  if not found then raise exception 'الموظف غير موجود'; end if;
  self := coalesce(e.id = me, false);
  mgr := coalesce(e.manager_id = me, false);
  hr := public.has_role(p_company, array['owner','admin','hr']) or public.fin_can(p_company, 'hr_emp');
  if not (self or mgr or hr) or not public.emp_branch_ok(p_company, e.id) then raise exception 'ملف الموظف للموارد البشرية أو الموظف نفسه أو مديره' using errcode = '42501'; end if;
  pay := self or public.has_role(p_company, array['owner','admin','hr','finance']) or public.fin_can(p_company, 'hr_pay');
  begin select x.balance into bal from public.annual_leave_balance(e.id) x; exception when others then bal := null; end;
  return jsonb_build_object(
    'profile', jsonb_build_object('id', e.id, 'emp_no', e.emp_no, 'name', e.full_name, 'name_en', e.full_name_en, 'job', e.job_title, 'job_en', e.job_title_en,
      'department', (select d.name from public.departments d where d.id = e.department_id),
      'manager', (select jsonb_build_object('id', m.id, 'name', m.full_name) from public.employees m where m.id = e.manager_id),
      'hire_date', e.hire_date, 'end_date', e.end_date, 'probation_end', e.probation_end, 'nationality', e.nationality, 'is_saudi', e.is_saudi,
      'years', round(((coalesce(e.end_date, current_date) - e.hire_date) / 365.25)::numeric, 1),
      'branch', (select b.code || ' — ' || b.name from public.branches b where b.id = e.branch_id),
      'phone', case when hr or self then e.phone end, 'email', case when hr or self then e.email end,
      'team', (select count(*) from public.employees t where t.manager_id = e.id and t.end_date is null)),
    'can', jsonb_build_object('hr', hr, 'pay', pay, 'self', self),
    'pay', case when pay then jsonb_build_object('basic', e.basic, 'housing', e.housing, 'transport', e.transport,
      'allowances', coalesce((select sum(a.amount) from public.employee_allowances a where a.employee_id = e.id and (a.start_on is null or a.start_on <= current_date) and (a.end_on is null or a.end_on >= current_date)), 0),
      'slips', coalesce((select jsonb_agg(z order by z.year desc, z.month desc) from (select r.year, r.month, r.status, l.gross, l.deductions, l.net from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id
                  where l.employee_id = e.id order by r.year desc, r.month desc limit 6) z), '[]')) end,
    'contract', (select jsonb_build_object('type', c.contract_type, 'start', c.start_date, 'end', c.end_date, 'status', c.status, 'renewals', c.renewal_no)
                   from public.contracts c where c.employee_id = e.id order by c.start_date desc limit 1),
    'attendance', (select jsonb_build_object('days', count(*) filter (where a.check_in is not null), 'late_days', count(*) filter (where a.late_min > 0),
                     'late_min', coalesce(sum(a.late_min), 0), 'ot_hours', round(coalesce(sum(a.ot_min), 0) / 60.0, 1), 'worked_hours', round(coalesce(sum(a.worked_min), 0) / 60.0, 1))
                   from public.attendance a where a.employee_id = e.id and a.day >= d0),
    'leave_balance', bal,
    'requests', coalesce((select jsonb_agg(z order by z.created_at desc) from (select r.id, r.kind, r.sub, r.from_date, r.to_date, r.days, r.amount, r.status, r.created_at
                  from public.requests r where r.employee_id = e.id order by r.created_at desc limit 10) z), '[]'),
    'penalties', case when hr or self then coalesce((select jsonb_agg(z order by z.occurred_on desc) from (select p.occurred_on, p.action, p.fine, p.status, p.description
                  from public.penalties p where p.employee_id = e.id order by p.occurred_on desc limit 10) z), '[]') end,
    'reviews', coalesce((select jsonb_agg(z order by z.created_at desc) from (select v.overall, v.status, v.created_at, (select c.name from public.review_cycles c where c.id = v.cycle_id) cycle
                  from public.reviews v where v.employee_id = e.id order by v.created_at desc limit 3) z), '[]'),
    'custody', coalesce((select jsonb_agg(jsonb_build_object('name', c.name, 'serial', c.serial, 'value', c.value, 'issued_on', c.issued_on) order by c.issued_on)
                  from public.custody_items c where c.employee_id = e.id and c.status = 'held'), '[]'),
    'documents', coalesce((select jsonb_agg(jsonb_build_object('type', d.doc_type, 'title', d.title, 'no', d.doc_no, 'expiry', d.expiry_date) order by d.expiry_date nulls last)
                  from public.employee_documents d where d.employee_id = e.id), '[]'));
end $$;

revoke all on function public.employee_360(uuid, uuid) from public, anon;
grant execute on function public.employee_360(uuid, uuid) to authenticated;
notify pgrst, 'reload schema';
