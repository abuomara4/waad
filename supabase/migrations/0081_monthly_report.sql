-- Waad ERP — 0081 the monthly summary e-mail to each company's owner (sent by the notify job on the 1st–3rd of the month).
-- One e-mail per company and month: last month's sales, collections, purchases, payroll, overdue invoices, staff, documents
-- about to expire, requests waiting for approval and ZATCA problems. The owner can switch it off in the company settings.

alter table public.companies add column if not exists monthly_report boolean not null default true;
alter table public.companies add column if not exists monthly_report_sent text check (monthly_report_sent is null or monthly_report_sent ~ '^\d{4}-\d{2}$');

-- the figures of one company for the month starting p_month (service role only)
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
    'zatca_bad', (select count(*) from public.zatca_docs z where z.company_id = p_company and z.status in ('rejected','error'))
  )
$$;

-- companies whose report for last month is due (1st–3rd of the month, Riyadh), with the owner's e-mail
create or replace function public.monthly_report_due() returns table(company_id uuid, name text, email text, month text)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, (select u.email from public.members mm join auth.users u on u.id = mm.user_id where mm.company_id = c.id and mm.role = 'owner' limit 1),
         to_char(date_trunc('month', (now() at time zone 'Asia/Riyadh')::date) - interval '1 month', 'YYYY-MM')
  from public.companies c join public.company_subscriptions s on s.company_id = c.id
  where c.monthly_report and s.status in ('trial','active')
    and extract(day from (now() at time zone 'Asia/Riyadh')) between 1 and 3
    and c.monthly_report_sent is distinct from to_char(date_trunc('month', (now() at time zone 'Asia/Riyadh')::date) - interval '1 month', 'YYYY-MM')
  limit 200
$$;

revoke all on function public.monthly_report(uuid, date), public.monthly_report_due() from public, anon, authenticated;
grant execute on function public.monthly_report(uuid, date), public.monthly_report_due() to service_role;
