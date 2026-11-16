-- Waad ERP — 0088 fixes from the full QA report (figures)
-- * analytics: a period of whole months is compared with the same whole months before it (Nov 1–30 ↔ Oct 1–31).
-- * HR dashboard turnover: the average headcount counts only the months the company had staff, so a new company's first
--   leavers no longer give 342%; the number of months used is returned (turnover_months).

create or replace function public.company_analytics(p_company uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r jsonb := jsonb_build_object('from', p_from, 'to', p_to);
  len int; pf date; pt date; cur record; prv record; me uuid := public.my_employee(p_company);
  exec boolean; fin boolean; hr boolean; ms date; hc_now int; hc_prev int;
begin
  if not public.is_member(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception 'حدد الفترة'; end if;
  if p_to - p_from > 731 then raise exception 'الفترة لا تزيد على سنتين'; end if;
  len := p_to - p_from + 1; pt := p_from - 1; pf := pt - len + 1;
  -- whole calendar months (this month, a quarter, a year…) compare with the same number of whole months before:
  -- November 1–30 compares with October 1–31, not with October 2–31
  if extract(day from p_from) = 1 and p_to = (date_trunc('month', p_to) + interval '1 month - 1 day')::date then
    pf := (p_from - make_interval(months => ((extract(year from p_to) * 12 + extract(month from p_to)) - (extract(year from p_from) * 12 + extract(month from p_from)) + 1)::int))::date;
  end if;
  r := r || jsonb_build_object('prev_from', pf, 'prev_to', pt);
  exec := public.has_role(p_company, array['owner','admin','finance']);
  fin := public.fin_can(p_company, 'reports');
  hr := public.has_role(p_company, array['owner','admin','hr']);

  -- ---------- executive ----------
  if exec or fin then
    select * into cur from public.an_pl(p_company, p_from, p_to);
    select * into prv from public.an_pl(p_company, pf, pt);
    select count(*) into hc_now from public.employees where company_id = p_company and hire_date <= p_to and (end_date is null or end_date >= p_to);
    r := r || jsonb_build_object('exec', jsonb_build_object(
      'revenue', cur.revenue, 'revenue_prev', prv.revenue, 'expenses', cur.expenses, 'expenses_prev', prv.expenses,
      'profit', cur.revenue - cur.expenses, 'profit_prev', prv.revenue - prv.expenses,
      'margin', case when cur.revenue > 0 then round((cur.revenue - cur.expenses) / cur.revenue * 100, 1) end,
      'gross_margin', case when cur.revenue > 0 then round((cur.revenue - cur.cogs) / cur.revenue * 100, 1) end,
      'payroll', cur.payroll, 'payroll_prev', prv.payroll,
      'payroll_ratio', case when cur.revenue > 0 then round(cur.payroll / cur.revenue * 100, 1) end,
      'cash', public.an_balance(p_company, array['1110','1120'], p_to), 'cash_prev', public.an_balance(p_company, array['1110','1120'], pt),
      'ar', public.an_balance(p_company, array['1200'], p_to), 'ap', -public.an_balance(p_company, array['2100'], p_to),
      'inventory', public.an_balance(p_company, array['1300'], p_to),
      'headcount', hc_now, 'rev_per_emp', case when hc_now > 0 then round(cur.revenue / hc_now, 2) end,
      'months', coalesce((select jsonb_agg(jsonb_build_object('m', to_char(m, 'YYYY-MM'), 'revenue', p.revenue, 'expenses', p.expenses, 'profit', p.revenue - p.expenses) order by m)
          from generate_series(date_trunc('month', p_from), date_trunc('month', p_to), interval '1 month') m
          cross join lateral public.an_pl(p_company, greatest(m::date, p_from), least((m + interval '1 month - 1 day')::date, p_to)) p), '[]')));
  end if;

  -- ---------- finance ----------
  if fin then
    r := r || jsonb_build_object('finance', jsonb_build_object(
      'expense_accounts', coalesce((select jsonb_agg(jsonb_build_object('code', code, 'name', name, 'name_en', name_en, 'amount', amt) order by amt desc) from (
          select a.code, a.name, a.name_en, sum(l.debit - l.credit) amt from public.journal_lines l join public.journal_entries j on j.id = l.entry_id
            join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
           where l.company_id = p_company and a.type = 'exp' and j.date between p_from and p_to and not public.is_closing_entry(j.id) group by 1, 2, 3 having sum(l.debit - l.credit) <> 0) q), '[]'),
      'cash_flow', coalesce((select jsonb_agg(jsonb_build_object('m', m, 'in', i, 'out', o) order by m) from (
          select to_char(j.date, 'YYYY-MM') m, sum(l.debit) i, sum(l.credit) o from public.journal_lines l join public.journal_entries j on j.id = l.entry_id
           where l.company_id = p_company and l.account_code in ('1110','1120') and j.date between p_from and p_to group by 1) q), '[]'),
      'ar_aging', (select jsonb_build_object('d30', coalesce(sum(o) filter (where age <= 30), 0), 'd60', coalesce(sum(o) filter (where age between 31 and 60), 0),
                    'd90', coalesce(sum(o) filter (where age between 61 and 90), 0), 'over', coalesce(sum(o) filter (where age > 90), 0))
          from (select public.an_open(s.id, s.total) o, p_to - s.due_date age from public.sales_invoices s where s.company_id = p_company and s.status = 'posted' and s.date <= p_to) q where o > 0),
      'ap_aging', (select jsonb_build_object('d30', coalesce(sum(o) filter (where age <= 30), 0), 'd60', coalesce(sum(o) filter (where age between 31 and 60), 0),
                    'd90', coalesce(sum(o) filter (where age between 61 and 90), 0), 'over', coalesce(sum(o) filter (where age > 90), 0))
          from (select public.an_open(b.id, b.total) o, p_to - b.due_date age from public.purchase_bills b where b.company_id = p_company and b.status = 'posted' and b.date <= p_to) q where o > 0),
      'vat', (select jsonb_build_object('output', coalesce(sum(l.credit - l.debit) filter (where l.account_code = '2200'), 0), 'input', coalesce(sum(l.debit - l.credit) filter (where l.account_code = '1400'), 0))
          from public.journal_lines l join public.journal_entries j on j.id = l.entry_id where l.company_id = p_company and j.date between p_from and p_to)));
  end if;

  -- ---------- sales ----------
  if public.fin_can(p_company, 'sales') then
    r := r || jsonb_build_object('sales', jsonb_build_object(
      'total', (select coalesce(sum(subtotal), 0) from public.sales_invoices where company_id = p_company and status = 'posted' and date between p_from and p_to),
      'total_prev', (select coalesce(sum(subtotal), 0) from public.sales_invoices where company_id = p_company and status = 'posted' and date between pf and pt),
      'count', (select count(*) from public.sales_invoices where company_id = p_company and status = 'posted' and date between p_from and p_to),
      'returns', (select coalesce(sum(subtotal), 0) from public.credit_notes where company_id = p_company and kind = 'sales' and date between p_from and p_to),
      'collected', (select coalesce(sum(amount), 0) from public.payments where company_id = p_company and direction = 'in' and date between p_from and p_to),
      'months', coalesce((select jsonb_agg(jsonb_build_object('m', m, 'total', t, 'n', n) order by m) from (select to_char(date, 'YYYY-MM') m, sum(subtotal) t, count(*) n
          from public.sales_invoices where company_id = p_company and status = 'posted' and date between p_from and p_to group by 1) q), '[]'),
      'customers', coalesce((select jsonb_agg(jsonb_build_object('name', p.name, 'name_en', p.name_en, 'total', q.t, 'n', q.n) order by q.t desc) from (
          select party_id, sum(subtotal) t, count(*) n from public.sales_invoices where company_id = p_company and status = 'posted' and date between p_from and p_to
           group by 1 order by 2 desc limit 10) q join public.parties p on p.id = q.party_id), '[]'),
      'items', coalesce((select jsonb_agg(jsonb_build_object('name', i.name, 'name_en', i.name_en, 'qty', q.qty, 'total', q.t) order by q.t desc) from (
          select l.item_id, sum(l.qty) qty, sum(l.qty * l.unit_price) t from public.sales_invoice_lines l join public.sales_invoices s on s.id = l.invoice_id
           where s.company_id = p_company and s.status = 'posted' and s.date between p_from and p_to group by 1 order by 3 desc limit 10) q join public.items i on i.id = q.item_id), '[]')));
  end if;

  -- ---------- purchasing and stock ----------
  if public.fin_can(p_company, 'purch') or public.fin_can(p_company, 'stock') then
    r := r || jsonb_build_object('supply', jsonb_build_object(
      'purchases', (select coalesce(sum(subtotal), 0) from public.purchase_bills where company_id = p_company and status = 'posted' and date between p_from and p_to),
      'purchases_prev', (select coalesce(sum(subtotal), 0) from public.purchase_bills where company_id = p_company and status = 'posted' and date between pf and pt),
      'paid', (select coalesce(sum(amount), 0) from public.payments where company_id = p_company and direction = 'out' and date between p_from and p_to),
      'months', coalesce((select jsonb_agg(jsonb_build_object('m', m, 'total', t) order by m) from (select to_char(date, 'YYYY-MM') m, sum(subtotal) t
          from public.purchase_bills where company_id = p_company and status = 'posted' and date between p_from and p_to group by 1) q), '[]'),
      'suppliers', coalesce((select jsonb_agg(jsonb_build_object('name', p.name, 'name_en', p.name_en, 'total', q.t, 'n', q.n) order by q.t desc) from (
          select party_id, sum(subtotal) t, count(*) n from public.purchase_bills where company_id = p_company and status = 'posted' and date between p_from and p_to
           group by 1 order by 2 desc limit 10) q join public.parties p on p.id = q.party_id), '[]'),
      'stock_value', (select coalesce(sum(value), 0) from public.stock_moves where company_id = p_company and date <= p_to),
      'low_stock', coalesce((select jsonb_agg(jsonb_build_object('code', i.code, 'name', i.name, 'name_en', i.name_en, 'qty', q.qty, 'reorder', i.reorder_level) order by q.qty) from public.items i
          cross join lateral (select coalesce(sum(m.qty), 0) qty from public.stock_moves m where m.item_id = i.id) q
         where i.company_id = p_company and i.type = 'stock' and i.reorder_level > 0 and q.qty <= i.reorder_level), '[]'),
      'slow', coalesce((select jsonb_agg(jsonb_build_object('code', i.code, 'name', i.name, 'name_en', i.name_en, 'qty', q.qty, 'value', q.v) order by q.v desc) from public.items i
          cross join lateral (select coalesce(sum(m.qty), 0) qty, coalesce(sum(m.value), 0) v from public.stock_moves m where m.item_id = i.id) q
         where i.company_id = p_company and i.type = 'stock' and q.qty > 0
           and not exists(select 1 from public.stock_moves m where m.item_id = i.id and m.source = 'sale' and m.date between p_from and p_to)), '[]')));
  end if;

  -- ---------- HR ----------
  if hr or exec then
    select count(*) into hc_prev from public.employees where company_id = p_company and hire_date <= pt and (end_date is null or end_date >= pt);
    select count(*) into hc_now from public.employees where company_id = p_company and hire_date <= p_to and (end_date is null or end_date >= p_to);
    r := r || jsonb_build_object('hr', jsonb_build_object(
      'headcount', hc_now, 'headcount_start', hc_prev,
      'joiners', (select count(*) from public.employees where company_id = p_company and hire_date between p_from and p_to),
      'leavers', (select count(*) from public.employees where company_id = p_company and end_date between p_from and p_to),
      'leavers_by_reason', coalesce((select jsonb_object_agg(coalesce(end_reason, 'other'), n) from (select end_reason, count(*) n from public.employees
          where company_id = p_company and end_date between p_from and p_to group by 1) q), '{}'),
      'turnover', case when hc_now + hc_prev > 0 then round((select count(*) from public.employees where company_id = p_company and end_date between p_from and p_to)::numeric
          / ((hc_now + hc_prev) / 2.0) * 100, 1) else 0 end,
      'saudi', (select count(*) from public.employees where company_id = p_company and is_saudi and hire_date <= p_to and (end_date is null or end_date >= p_to)),
      'female', (select count(*) from public.employees where company_id = p_company and gender = 'f' and hire_date <= p_to and (end_date is null or end_date >= p_to)),
      'tenure', (select round(avg((p_to - hire_date) / 365.0), 1) from public.employees where company_id = p_company and hire_date <= p_to and (end_date is null or end_date >= p_to)),
      'leave_days', coalesce((select jsonb_object_agg(sub, d) from (select q.sub, sum(greatest(0, least(q.to_date, p_to) - greatest(q.from_date, p_from) + 1)) d from public.requests q
          where q.company_id = p_company and q.kind = 'leave' and q.status = 'approved' and q.from_date <= p_to and q.to_date >= p_from group by 1) q), '{}'),
      'absent_days', (select coalesce(sum(l.att_absent_days + l.absence_days), 0) from public.payroll_lines l join public.payroll_runs pr on pr.id = l.run_id
          where pr.company_id = p_company and make_date(pr.year, pr.month, 1) between date_trunc('month', p_from) and p_to),
      'late_hours', (select round(coalesce(sum(late_min), 0) / 60.0, 1) from public.attendance where company_id = p_company and day between p_from and p_to),
      'ot_hours', (select round(coalesce(sum(ot_min), 0) / 60.0, 1) from public.attendance where company_id = p_company and day between p_from and p_to)
          + (select coalesce(sum(l.overtime_hours), 0) from public.payroll_lines l join public.payroll_runs pr on pr.id = l.run_id
              where pr.company_id = p_company and make_date(pr.year, pr.month, 1) between date_trunc('month', p_from) and p_to),
      'payroll', (select jsonb_build_object('gross', coalesce(sum(l.gross + l.arrears + l.overtime + l.bonus), 0), 'net', coalesce(sum(l.net), 0),
                    'employer_gosi', coalesce(sum(l.employer_gosi), 0), 'overtime', coalesce(sum(l.overtime), 0), 'deductions', coalesce(sum(l.gross + l.arrears + l.overtime + l.bonus - l.net), 0))
          from public.payroll_lines l join public.payroll_runs pr on pr.id = l.run_id
         where pr.company_id = p_company and make_date(pr.year, pr.month, 1) between date_trunc('month', p_from) and p_to)));
    -- departments
    r := r || jsonb_build_object('departments', coalesce((select jsonb_agg(x order by x->>'name') from (
      select jsonb_build_object('name', coalesce(d.name, '—'), 'name_en', d.name_en,
        'headcount', count(*) filter (where e.hire_date <= p_to and (e.end_date is null or e.end_date >= p_to)),
        'saudi', count(*) filter (where e.is_saudi and e.hire_date <= p_to and (e.end_date is null or e.end_date >= p_to)),
        'leavers', count(*) filter (where e.end_date between p_from and p_to),
        'avg_wage', round(avg(e.basic + e.housing + e.transport) filter (where e.hire_date <= p_to and (e.end_date is null or e.end_date >= p_to)), 2),
        'cost', coalesce(sum((select sum(l.gross + l.arrears + l.overtime + l.bonus + l.employer_gosi) from public.payroll_lines l join public.payroll_runs pr on pr.id = l.run_id
              where l.employee_id = e.id and make_date(pr.year, pr.month, 1) between date_trunc('month', p_from) and p_to)), 0),
        'absent_days', coalesce(sum((select sum(l.att_absent_days + l.absence_days) from public.payroll_lines l join public.payroll_runs pr on pr.id = l.run_id
              where l.employee_id = e.id and make_date(pr.year, pr.month, 1) between date_trunc('month', p_from) and p_to)), 0),
        'late_hours', round(coalesce(sum((select sum(a.late_min) from public.attendance a where a.employee_id = e.id and a.day between p_from and p_to)), 0) / 60.0, 1),
        'ot_hours', round(coalesce(sum((select sum(a.ot_min) from public.attendance a where a.employee_id = e.id and a.day between p_from and p_to)), 0) / 60.0, 1),
        'leave_days', coalesce(sum((select sum(greatest(0, least(q.to_date, p_to) - greatest(q.from_date, p_from) + 1)) from public.requests q
              where q.employee_id = e.id and q.kind = 'leave' and q.status = 'approved' and q.from_date <= p_to and q.to_date >= p_from)), 0)) x
      from public.employees e left join public.departments d on d.id = e.department_id
     where e.company_id = p_company and e.hire_date <= p_to and (e.end_date is null or e.end_date >= p_from)
     group by d.id, d.name, d.name_en) q), '[]'));
  end if;

  -- ---------- a manager's own team ----------
  if me is not null and exists(select 1 from public.employees where company_id = p_company and manager_id = me) then
    r := r || jsonb_build_object('team', coalesce((select jsonb_agg(jsonb_build_object('name', e.full_name, 'name_en', e.full_name_en,
        'present', (select count(*) from public.attendance a where a.employee_id = e.id and a.day between p_from and p_to),
        'late_hours', (select round(coalesce(sum(a.late_min), 0) / 60.0, 1) from public.attendance a where a.employee_id = e.id and a.day between p_from and p_to),
        'ot_hours', (select round(coalesce(sum(a.ot_min), 0) / 60.0, 1) from public.attendance a where a.employee_id = e.id and a.day between p_from and p_to),
        'leave_days', (select coalesce(sum(greatest(0, least(q.to_date, p_to) - greatest(q.from_date, p_from) + 1)), 0) from public.requests q
            where q.employee_id = e.id and q.kind = 'leave' and q.status = 'approved' and q.from_date <= p_to and q.to_date >= p_from),
        'pending', (select count(*) from public.requests q where q.employee_id = e.id and q.status = 'pending')) order by e.full_name)
      from public.employees e where e.company_id = p_company and e.manager_id = me and (e.end_date is null or e.end_date >= p_from)), '[]'));
  end if;
  return r;
end $$;

create or replace function public.hr_dashboard(p_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare td date := public.riyadh_today(); r jsonb := '{}'; m date; hc int; j int; l int; avg_hc numeric := 0; leavers12 int := 0; nm int := 0; months jsonb := '[]';
begin
  if not public.has_role(p_company, array['owner','admin','hr','finance']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  -- people
  select jsonb_build_object('active', count(*), 'saudi', count(*) filter (where is_saudi), 'female', count(*) filter (where gender = 'f'),
           'probation', count(*) filter (where probation_end >= td), 'avg_wage', round(coalesce(avg(basic + housing + transport), 0), 2))
    into r from public.employees where company_id = p_company and hire_date <= td and (end_date is null or end_date >= td);
  r := r || jsonb_build_object('by_dept', coalesce((select jsonb_agg(jsonb_build_object('name', coalesce(d.name, '—'), 'name_en', d.name_en, 'n', x.n) order by x.n desc)
           from (select department_id, count(*) n from public.employees where company_id = p_company and hire_date <= td and (end_date is null or end_date >= td) group by 1) x
           left join public.departments d on d.id = x.department_id), '[]'));
  -- 12 months: joiners, leavers, headcount at month end
  for i in reverse 11..0 loop
    m := (date_trunc('month', td) - make_interval(months => i))::date;
    select count(*) filter (where hire_date between m and (m + interval '1 month - 1 day')::date),
           count(*) filter (where end_date between m and (m + interval '1 month - 1 day')::date),
           count(*) filter (where hire_date <= (m + interval '1 month - 1 day')::date and (end_date is null or end_date > (m + interval '1 month - 1 day')::date))
      into j, l, hc from public.employees where company_id = p_company;
    months := months || jsonb_build_object('m', to_char(m, 'YYYY-MM'), 'joins', j, 'leaves', l, 'hc', hc);
    if hc > 0 or l > 0 then avg_hc := avg_hc + hc; nm := nm + 1; end if; leavers12 := leavers12 + l;
  end loop;
  r := r || jsonb_build_object('months', months, 'turnover', case when avg_hc > 0 then round(leavers12 / (avg_hc / nm) * 100, 1) else 0 end, 'turnover_months', nm);
  -- today's attendance
  r := r || jsonb_build_object('today', (select jsonb_build_object('expected', count(*) filter (where s.status <> 'off' and s.status <> 'holiday' and s.status <> 'leave' and s.status <> 'na'),
           'present', count(*) filter (where s.status in ('present','late','open','nocheckout')), 'late', count(*) filter (where s.status = 'late'),
           'leave', count(*) filter (where s.status = 'leave'))
         from public.att_sheet(p_company, td, td) s));
  -- requests waiting
  r := r || jsonb_build_object('pending', coalesce((select jsonb_object_agg(kind, n) from (select kind, count(*) n from public.requests where company_id = p_company and status = 'pending' group by 1) x), '{}'));
  -- payroll cost of the last 6 payrolls
  r := r || jsonb_build_object('payroll', coalesce((select jsonb_agg(x order by x->>'p') from (
           select jsonb_build_object('p', pr.year || '-' || lpad(pr.month::text, 2, '0'), 'status', pr.status,
                  'gross', sum(pl.gross + pl.arrears + pl.overtime + pl.bonus), 'net', sum(pl.net), 'employer_gosi', sum(pl.employer_gosi), 'n', count(*)) x
             from public.payroll_runs pr join public.payroll_lines pl on pl.run_id = pr.id
            where pr.company_id = p_company group by pr.id order by pr.year desc, pr.month desc limit 6) q), '[]'));
  -- what needs attention
  r := r || jsonb_build_object(
    'docs30', case when public.has_role(p_company, array['owner','admin','hr']) then (select count(*) from public.doc_alerts(p_company, 30) a where a.level in ('expired','d30')) end,
    'leave_high', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.full_name, 'name_en', e.full_name_en, 'days', b.balance) order by b.balance desc)
        from public.employees e cross join lateral public.annual_leave_balance(e.id, td) b
       where e.company_id = p_company and (e.end_date is null or e.end_date >= td) and b.balance > 30), '[]'),
    'ot_near_cap', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.full_name, 'name_en', e.full_name_en, 'hours', round(h, 1)) order by h desc)
        from public.employees e cross join lateral (select public.ot_year_hours(e.id, extract(year from td)::int) h) x
       where e.company_id = p_company and (e.end_date is null or e.end_date >= td) and h >= 600), '[]'),
    'comp_expiring', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.full_name, 'name_en', e.full_name_en, 'hours', b.balance_hours, 'use_by', c.use_by))
        from public.employees e cross join lateral public.comp_balance(e.id) b
        cross join lateral (select min(use_by) use_by from public.comp_credits cc where cc.employee_id = e.id and cc.use_by >= td) c
       where e.company_id = p_company and (e.end_date is null or e.end_date >= td) and b.balance_hours > 0 and c.use_by <= td + 14), '[]'),
    'clearance_open', (select count(*) from public.employees e where e.company_id = p_company and e.end_date between td - 90 and td + 30
        and ((select count(*) from public.clearance_marks k where k.employee_id = e.id) < 4 or exists(select 1 from public.custody_items ci where ci.employee_id = e.id and ci.status = 'held'))),
    'policies_unacked', (select count(*) from public.policies p cross join public.employees e
        where p.company_id = p_company and p.active and e.company_id = p_company and (e.end_date is null or e.end_date >= td)
          and not exists(select 1 from public.policy_acks a where a.policy_id = p.id and a.employee_id = e.id)));
  return r;
end $$;
