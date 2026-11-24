-- Branches part 2: the numbers of every branch for a period, side by side (owner, admin, finance with reports).
-- Sales, collections and purchases come from the documents' branch; payroll and headcount from the employees' branch;
-- revenue, expenses and profit from the books through the branch's cost centre. Documents without a branch show as «بلا فرع».
create or replace function public.branch_summary(p_company uuid, p_from date, p_to date)
returns table(branch_id uuid, code text, name text, name_en text, sales numeric, sales_n bigint, collected numeric, purchases numeric,
              payroll numeric, headcount bigint, revenue numeric, expense numeric, profit numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'reports');
  if p_from is null or p_to is null or p_to < p_from then raise exception 'تحقق من التواريخ'; end if;
  return query
  with b as (select x.id, x.code, x.name, x.name_en, x.cost_center_id, x.is_main from public.branches x where x.company_id = p_company
             union all select null::uuid, '—', 'بلا فرع', 'No branch', null::uuid, false),
  gl as (select l.cost_center_id cc, sum(l.credit - l.debit) filter (where a.type = 'rev') rev, sum(l.debit - l.credit) filter (where a.type = 'exp') exp
           from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
          where l.company_id = p_company and e.date between p_from and p_to and a.type in ('rev','exp') group by l.cost_center_id)
  select b.id, b.code, b.name, b.name_en,
    coalesce((select sum(s.total) from public.sales_invoices s where s.company_id = p_company and s.status = 'posted' and not s.is_opening and s.date between p_from and p_to and s.branch_id is not distinct from b.id), 0),
    (select count(*) from public.sales_invoices s where s.company_id = p_company and s.status = 'posted' and not s.is_opening and s.date between p_from and p_to and s.branch_id is not distinct from b.id),
    coalesce((select sum(p.amount) from public.payments p where p.company_id = p_company and p.direction = 'in' and p.date between p_from and p_to and p.branch_id is not distinct from b.id), 0),
    coalesce((select sum(x.total) from public.purchase_bills x where x.company_id = p_company and x.status = 'posted' and not x.is_opening and x.date between p_from and p_to and x.branch_id is not distinct from b.id), 0),
    coalesce((select sum(l.gross + l.employer_gosi) from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id join public.employees e on e.id = l.employee_id
               where r.company_id = p_company and make_date(r.year, r.month, 1) between date_trunc('month', p_from)::date and p_to and e.branch_id is not distinct from b.id), 0),
    (select count(*) from public.employees e where e.company_id = p_company and e.hire_date <= p_to and (e.end_date is null or e.end_date >= p_to) and e.branch_id is not distinct from b.id),
    coalesce((select g.rev from gl g where g.cc is not distinct from b.cost_center_id and (b.id is not null or g.cc is null)), 0),
    coalesce((select g.exp from gl g where g.cc is not distinct from b.cost_center_id and (b.id is not null or g.cc is null)), 0),
    coalesce((select g.rev from gl g where g.cc is not distinct from b.cost_center_id and (b.id is not null or g.cc is null)), 0) - coalesce((select g.exp from gl g where g.cc is not distinct from b.cost_center_id and (b.id is not null or g.cc is null)), 0)
  from b order by b.is_main desc, b.id is null, b.code;
end $$;
revoke all on function public.branch_summary(uuid, date, date) from public, anon;
grant execute on function public.branch_summary(uuid, date, date) to authenticated;
notify pgrst, 'reload schema';
