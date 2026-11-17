-- 0110 — the owner's monthly e-mail also reports: survey answers and careers-page applicants in the month, new hires
-- (last 120 days) still missing a contract, an IBAN or (non-Saudis) an iqama, and position requests waiting for approval.
create or replace function public.monthly_report(p_company uuid, p_month date) returns jsonb
language sql stable security definer set search_path = public as $$
  with m as (select date_trunc('month', p_month)::date a, (date_trunc('month', p_month) + interval '1 month')::date b, (now() at time zone 'Asia/Riyadh')::date t)
  select jsonb_build_object(
    'month', to_char((select a from m), 'YYYY-MM'),
    'sales_n', (select count(*) from public.sales_invoices s, m where s.company_id = p_company and s.status = 'posted' and not s.is_opening and s.date >= m.a and s.date < m.b),
    'sales', (select coalesce(sum(s.total), 0) from public.sales_invoices s, m where s.company_id = p_company and s.status = 'posted' and not s.is_opening and s.date >= m.a and s.date < m.b),
    'collected', (select coalesce(sum(p.amount), 0) from public.payments p, m where p.company_id = p_company and p.direction = 'in' and p.date >= m.a and p.date < m.b),
    'purchases', (select coalesce(sum(b.total), 0) from public.purchase_bills b, m where b.company_id = p_company and b.status = 'posted' and not b.is_opening and b.date >= m.a and b.date < m.b),
    'paid_out', (select coalesce(sum(p.amount), 0) from public.payments p, m where p.company_id = p_company and p.direction = 'out' and p.date >= m.a and p.date < m.b),
    'payroll', (select jsonb_build_object('status', r.status, 'net', coalesce((select sum(l.net) from public.payroll_lines l where l.run_id = r.id), 0), 'n', (select count(*) from public.payroll_lines l where l.run_id = r.id))
                from public.payroll_runs r, m where r.company_id = p_company and r.year = extract(year from m.a) and r.month = extract(month from m.a)),
    'overdue_n', (select count(*) from public.sales_invoices s, m where s.company_id = p_company and s.status = 'posted' and s.due_date < m.t and s.total - public.paid_on(s.id) > 0.005),
    'overdue', (select coalesce(sum(s.total - public.paid_on(s.id)), 0) from public.sales_invoices s, m where s.company_id = p_company and s.status = 'posted' and s.due_date < m.t and s.total - public.paid_on(s.id) > 0.005),
    'staff', (select count(*) from public.employees e, m where e.company_id = p_company and e.hire_date < m.b and (e.end_date is null or e.end_date >= m.b)),
    'joined', (select count(*) from public.employees e, m where e.company_id = p_company and e.hire_date >= m.a and e.hire_date < m.b),
    'left', (select count(*) from public.employees e, m where e.company_id = p_company and e.end_date >= m.a and e.end_date < m.b),
    'expiring', (select count(*) from public.employee_documents d join public.employees e on e.id = d.employee_id, m
                 where e.company_id = p_company and e.end_date is null and d.expiry_date between m.t and m.t + 30),
    'pending', (select count(*) from public.requests q where q.company_id = p_company and q.status = 'pending'),
    'zatca_bad', (select count(*) from public.zatca_docs z where z.company_id = p_company and z.status in ('rejected','error')),
    'survey_answers', (select count(*) from public.survey_responses r, m where r.company_id = p_company and r.created_at >= m.a and r.created_at < m.b),
    'applicants', (select count(*) from public.candidates c, m where c.company_id = p_company and c.source = 'careers' and c.created_at >= m.a and c.created_at < m.b),
    'onb_missing', (select count(*) from public.employees e, m where e.company_id = p_company and e.hire_date >= m.t - 120 and (e.end_date is null or e.end_date >= m.t)
                    and (e.iban is null or not exists(select 1 from public.contracts k where k.employee_id = e.id and k.status = 'active')
                         or (not e.is_saudi and not exists(select 1 from public.employee_documents d where d.employee_id = e.id and d.doc_type = 'iqama')))),
    'hc_pending', (select count(*) from public.headcount_plans h where h.company_id = p_company and h.status in ('submitted','hr_ok'))
  )
$$;
revoke all on function public.monthly_report(uuid, date) from public, anon, authenticated;
grant execute on function public.monthly_report(uuid, date) to service_role;
