-- Weekly summary e-mail for the owner (sent by the notify job on Sunday or Monday, Riyadh time): last week's sales,
-- collections, payments, cash and bank balance, attendance, approvals waiting, overdue invoices and contracts ending.
-- Read by the server job only; the owner turns it off in company settings.
alter table public.companies add column if not exists weekly_report boolean not null default true;
alter table public.companies add column if not exists weekly_report_sent text check (weekly_report_sent is null or weekly_report_sent ~ '^\d{4}-\d{2}-\d{2}$');

-- p_from = the Sunday that starts the week (Sunday to Saturday)
create or replace function public.weekly_report(p_company uuid, p_from date) returns jsonb
language sql stable security definer set search_path = public as $$
  with w as (select p_from a, p_from + 7 b, public.riyadh_today() t)
  select jsonb_build_object(
    'from', (select a from w), 'to', (select b - 1 from w),
    'sales_n', (select count(*) from public.sales_invoices s, w where s.company_id = p_company and s.status = 'posted' and not s.is_opening and s.date >= w.a and s.date < w.b),
    'sales', (select coalesce(sum(s.total), 0) from public.sales_invoices s, w where s.company_id = p_company and s.status = 'posted' and not s.is_opening and s.date >= w.a and s.date < w.b),
    'collected', (select coalesce(sum(p.amount), 0) from public.payments p, w where p.company_id = p_company and p.direction = 'in' and p.date >= w.a and p.date < w.b),
    'paid_out', (select coalesce(sum(p.amount), 0) from public.payments p, w where p.company_id = p_company and p.direction = 'out' and p.date >= w.a and p.date < w.b),
    'cash', (select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l where l.company_id = p_company and (l.account_code like '111%' or l.account_code like '112%')),
    'overdue_n', (select count(*) from public.sales_invoices s, w where s.company_id = p_company and s.status = 'posted' and s.due_date < w.t and s.total - public.paid_on(s.id) > 0.005),
    'overdue', (select coalesce(sum(s.total - public.paid_on(s.id)), 0) from public.sales_invoices s, w where s.company_id = p_company and s.status = 'posted' and s.due_date < w.t and s.total - public.paid_on(s.id) > 0.005),
    'late', (select count(*) from public.attendance a, w where a.company_id = p_company and a.day >= w.a and a.day < w.b and a.late_min > 0),
    'present_days', (select count(*) from public.attendance a, w where a.company_id = p_company and a.day >= w.a and a.day < w.b and a.check_in is not null),
    'on_leave', (select count(distinct q.employee_id) from public.requests q, w where q.company_id = p_company and q.kind = 'leave' and q.status = 'approved' and q.from_date < w.b and q.to_date >= w.a),
    'joined', (select count(*) from public.employees e, w where e.company_id = p_company and e.hire_date >= w.a and e.hire_date < w.b),
    'left', (select count(*) from public.employees e, w where e.company_id = p_company and e.end_date >= w.a and e.end_date < w.b),
    'pending', (select count(*) from public.requests q where q.company_id = p_company and q.status = 'pending'),
    'contracts_due', (select count(*) from public.agreements g, w where g.company_id = p_company and g.status = 'active' and g.end_date is not null and g.end_date <= w.t + greatest(g.notice_days, 7)),
    'expiring', (select count(*) from public.employee_documents d join public.employees e on e.id = d.employee_id, w
                 where e.company_id = p_company and e.end_date is null and d.expiry_date between w.t and w.t + 30)
  )
$$;

-- companies whose owner gets last week's summary now (Sunday or Monday, once per week)
create or replace function public.weekly_report_due() returns table(company_id uuid, name text, email text, week_from date)
language sql stable security definer set search_path = public as $$
  with d as (select public.riyadh_today() t, (public.riyadh_today() - extract(dow from public.riyadh_today())::int - 7) wk)
  select c.id, c.name, (select u.email from public.members mm join auth.users u on u.id = mm.user_id where mm.company_id = c.id and mm.role = 'owner' limit 1), d.wk
  from public.companies c join public.company_subscriptions s on s.company_id = c.id, d
  where c.weekly_report and s.status in ('trial','active')
    and extract(dow from d.t) in (0, 1)
    and c.weekly_report_sent is distinct from to_char(d.wk, 'YYYY-MM-DD')
  limit 200
$$;

revoke all on function public.weekly_report(uuid, date), public.weekly_report_due() from public, anon, authenticated;
grant execute on function public.weekly_report(uuid, date), public.weekly_report_due() to service_role;
notify pgrst, 'reload schema';
