-- Sales reps, a 360 file per rep. The rep is an employee: the account manager of a customer (parties.sales_rep_id) and the rep
-- of each quotation / order and invoice (sales_rep_id). A new document takes the customer's rep, else the person who makes it
-- when he holds the sales role. Monthly targets per rep (sales_targets, net sales before VAT) with an optional commission
-- rate — company policy, shown as an estimate only (nothing is posted to payroll). Who sees: management and sales staff with
-- the sales permission see every rep (within their branches); a rep sees his own file.

alter table public.parties add column if not exists sales_rep_id uuid references public.employees(id) on delete set null;
alter table public.sales_invoices add column if not exists sales_rep_id uuid references public.employees(id) on delete set null;
alter table public.sales_orders add column if not exists sales_rep_id uuid references public.employees(id) on delete set null;
create index if not exists parties_sales_rep on public.parties(sales_rep_id) where sales_rep_id is not null;
create index if not exists sales_invoices_rep on public.sales_invoices(company_id, sales_rep_id, date);
create index if not exists sales_orders_rep on public.sales_orders(company_id, sales_rep_id);

-- the rep belongs to the company; a new document gets the customer's rep, else its maker when he is a sales person
create or replace function public.sales_rep_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare m public.members;
begin
  if tg_op = 'INSERT' and new.sales_rep_id is null and tg_table_name <> 'parties' then
    select p.sales_rep_id into new.sales_rep_id from public.parties p where p.id = new.party_id;
    if new.sales_rep_id is null then
      select * into m from public.members x where x.company_id = new.company_id and x.user_id = auth.uid();
      if found and m.employee_id is not null and (m.role = 'sales' or 'sales' = any(m.extra_roles)) then new.sales_rep_id := m.employee_id; end if;
    end if;
  end if;
  if new.sales_rep_id is not null and not exists(select 1 from public.employees e where e.id = new.sales_rep_id and e.company_id = new.company_id) then
    raise exception 'المندوب ليس من موظفي المنشأة';
  end if;
  return new;
end $$;
do $$ declare t text;
begin
  foreach t in array array['parties','sales_invoices','sales_orders'] loop
    execute format('drop trigger if exists sales_rep_guard on public.%I', t);
    execute format('create trigger sales_rep_guard before insert or update of sales_rep_id on public.%I for each row execute function public.sales_rep_guard()', t);
  end loop;
end $$;

create table if not exists public.sales_targets (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  month date not null check (extract(day from month) = 1),
  amount numeric(14,2) not null check (amount > 0),
  commission_pct numeric(5,2) check (commission_pct is null or commission_pct between 0 and 100),
  set_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  unique (company_id, employee_id, month)
);
create index if not exists sales_targets_emp on public.sales_targets(employee_id);
alter table public.sales_targets enable row level security;
drop policy if exists sales_targets_read on public.sales_targets;
create policy sales_targets_read on public.sales_targets for select
  using (public.fin_can(company_id, 'sales') or coalesce(employee_id = public.my_employee(company_id), false));
drop policy if exists branch_scope on public.sales_targets;
create policy branch_scope on public.sales_targets as restrictive for all using (public.emp_branch_ok(company_id, employee_id)) with check (public.emp_branch_ok(company_id, employee_id));
revoke all on public.sales_targets from anon, authenticated;
grant select on public.sales_targets to authenticated;

-- set (or clear with p_amount null) a rep's target for a month: management or sales staff, never one's own
create or replace function public.sales_target_set(p_company uuid, p_emp uuid, p_month date, p_amount numeric, p_pct numeric default null) returns void
language plpgsql security definer set search_path = public as $$
declare mo date := date_trunc('month', p_month)::date;
begin
  if not public.fin_can(p_company, 'sales') then raise exception 'تحديد الأهداف لإدارة المبيعات' using errcode = '42501'; end if;
  if coalesce(p_emp = public.my_employee(p_company), false) and not public.has_role(p_company, array['owner']) then raise exception 'لا تحدد هدفك بنفسك' using errcode = '42501'; end if;
  if not exists(select 1 from public.employees where id = p_emp and company_id = p_company) or not public.emp_branch_ok(p_company, p_emp) then raise exception 'الموظف غير موجود'; end if;
  if p_amount is null then delete from public.sales_targets where company_id = p_company and employee_id = p_emp and month = mo; return; end if;
  if p_amount <= 0 then raise exception 'الهدف أكبر من صفر'; end if;
  if p_pct is not null and (p_pct < 0 or p_pct > 100) then raise exception 'نسبة العمولة بين 0 و 100'; end if;
  insert into public.sales_targets(company_id, employee_id, month, amount, commission_pct) values (p_company, p_emp, mo, round(p_amount, 2), p_pct)
  on conflict (company_id, employee_id, month) do update set amount = excluded.amount, commission_pct = excluded.commission_pct, set_by = auth.uid(), updated_at = now();
end $$;

-- a rep's net sales (before VAT, after returns on his invoices) for a period
create or replace function public.rep_net_sales(p_company uuid, p_emp uuid, p_from date, p_to date) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select sum(s.subtotal) from public.sales_invoices s where s.company_id = p_company and s.sales_rep_id = p_emp and s.status = 'posted'
                     and not s.is_opening and s.date between p_from and p_to), 0)
       - coalesce((select sum(n.subtotal) from public.credit_notes n join public.sales_invoices s on s.id = n.doc_id
                    where n.company_id = p_company and n.kind = 'sales' and s.sales_rep_id = p_emp and n.date between p_from and p_to), 0)
$$;

-- the leaderboard: everyone who is a rep in the period (an invoice, a target, a customer, an open opportunity)
create or replace function public.rep_list(p_company uuid, p_from date, p_to date)
returns table(employee_id uuid, emp_no text, name text, sales numeric, invoices bigint, collected numeric, target numeric, achievement numeric,
              customers bigint, open_leads bigint, pipeline numeric, won bigint, lost bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not public.fin_can(p_company, 'sales') then raise exception 'أداء المندوبين لإدارة المبيعات' using errcode = '42501'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception 'تحقق من التواريخ'; end if;
  return query
  with lu as (select l.*, m.employee_id emp from public.crm_leads l left join public.members m on m.company_id = l.company_id and m.user_id = l.owner_id where l.company_id = p_company),
  reps as (select s.sales_rep_id id from public.sales_invoices s where s.company_id = p_company and s.sales_rep_id is not null and s.date between p_from and p_to
           union select t.employee_id from public.sales_targets t where t.company_id = p_company and t.month between date_trunc('month', p_from)::date and p_to
           union select p.sales_rep_id from public.parties p where p.company_id = p_company and p.sales_rep_id is not null
           union select lu.emp from lu where lu.emp is not null and lu.stage not in ('won','lost')),
  t as (select r.id, public.rep_net_sales(p_company, r.id, p_from, p_to) net,
               (select coalesce(sum(x.amount), 0) from public.sales_targets x where x.company_id = p_company and x.employee_id = r.id and x.month between date_trunc('month', p_from)::date and p_to) tgt
          from reps r where r.id is not null)
  select e.id, e.emp_no, e.full_name, t.net,
    (select count(*) from public.sales_invoices s where s.company_id = p_company and s.sales_rep_id = e.id and s.status = 'posted' and not s.is_opening and s.date between p_from and p_to),
    coalesce((select sum(y.amount) from public.payments y left join public.sales_invoices s on s.id = y.invoice_id join public.parties p on p.id = y.party_id
               where y.company_id = p_company and y.direction = 'in' and y.date between p_from and p_to
                 and (s.sales_rep_id = e.id or (y.invoice_id is null and p.sales_rep_id = e.id))), 0),
    t.tgt, case when t.tgt > 0 then round(100 * t.net / t.tgt, 1) end,
    (select count(*) from public.parties p where p.company_id = p_company and p.sales_rep_id = e.id and p.kind = 'customer'),
    (select count(*) from lu where lu.emp = e.id and lu.stage not in ('won','lost')),
    coalesce((select sum(lu.value * coalesce(lu.probability, 50) / 100.0) from lu where lu.emp = e.id and lu.stage not in ('won','lost')), 0),
    (select count(*) from lu where lu.emp = e.id and lu.stage = 'won' and lu.closed_at::date between p_from and p_to),
    (select count(*) from lu where lu.emp = e.id and lu.stage = 'lost' and lu.closed_at::date between p_from and p_to)
  from t join public.employees e on e.id = t.id
  where public.emp_branch_ok(p_company, e.id)
  order by t.net desc, e.full_name;
end $$;

-- one rep's file for a period
create or replace function public.rep_360(p_company uuid, p_emp uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; net numeric; tgt numeric; pct numeric; m date; trend jsonb := '[]'; s_from date;
begin
  if not (public.fin_can(p_company, 'sales') or coalesce(p_emp = public.my_employee(p_company), false)) then raise exception 'ملف المندوب لإدارة المبيعات أو المندوب نفسه' using errcode = '42501'; end if;
  select * into e from public.employees where id = p_emp and company_id = p_company;
  if not found or not public.emp_branch_ok(p_company, p_emp) then raise exception 'الموظف غير موجود'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception 'تحقق من التواريخ'; end if;
  net := public.rep_net_sales(p_company, p_emp, p_from, p_to);
  select coalesce(sum(amount), 0), max(commission_pct) into tgt, pct from public.sales_targets
   where company_id = p_company and employee_id = p_emp and month between date_trunc('month', p_from)::date and p_to;
  -- the last 12 months up to p_to: net sales against target
  s_from := (date_trunc('month', p_to) - interval '11 months')::date;
  for m in select generate_series(s_from, date_trunc('month', p_to)::date, interval '1 month')::date loop
    trend := trend || jsonb_build_object('month', to_char(m, 'YYYY-MM'), 'sales', public.rep_net_sales(p_company, p_emp, m, (m + interval '1 month - 1 day')::date),
      'target', coalesce((select amount from public.sales_targets where company_id = p_company and employee_id = p_emp and month = m), 0));
  end loop;
  return jsonb_build_object(
    'employee', jsonb_build_object('id', e.id, 'name', e.full_name, 'emp_no', e.emp_no, 'job', e.job_title, 'hire_date', e.hire_date),
    'sales', net, 'target', tgt, 'achievement', case when tgt > 0 then round(100 * net / tgt, 1) end,
    'commission_pct', pct, 'commission_est', case when pct is not null then round(net * pct / 100, 2) end,
    'invoices', (select count(*) from public.sales_invoices s where s.company_id = p_company and s.sales_rep_id = p_emp and s.status = 'posted' and not s.is_opening and s.date between p_from and p_to),
    'gross', coalesce((select sum(s.total) from public.sales_invoices s where s.company_id = p_company and s.sales_rep_id = p_emp and s.status = 'posted' and not s.is_opening and s.date between p_from and p_to), 0),
    'returns', coalesce((select sum(n.subtotal) from public.credit_notes n join public.sales_invoices s on s.id = n.doc_id where n.company_id = p_company and n.kind = 'sales' and s.sales_rep_id = p_emp and n.date between p_from and p_to), 0),
    'collected', coalesce((select sum(y.amount) from public.payments y left join public.sales_invoices s on s.id = y.invoice_id join public.parties p on p.id = y.party_id
                            where y.company_id = p_company and y.direction = 'in' and y.date between p_from and p_to
                              and (s.sales_rep_id = p_emp or (y.invoice_id is null and p.sales_rep_id = p_emp))), 0),
    -- still owed on his invoices (all dates): total − payments on the invoice − returns on it
    'open', coalesce((select sum(greatest(s.total - coalesce((select sum(y.amount) from public.payments y where y.invoice_id = s.id), 0)
                                     - coalesce((select sum(n.total) from public.credit_notes n where n.doc_id = s.id and n.kind = 'sales'), 0), 0))
                        from public.sales_invoices s where s.company_id = p_company and s.sales_rep_id = p_emp and s.status = 'posted'), 0),
    'overdue', coalesce((select sum(greatest(s.total - coalesce((select sum(y.amount) from public.payments y where y.invoice_id = s.id), 0)
                                     - coalesce((select sum(n.total) from public.credit_notes n where n.doc_id = s.id and n.kind = 'sales'), 0), 0))
                        from public.sales_invoices s where s.company_id = p_company and s.sales_rep_id = p_emp and s.status = 'posted' and s.due_date < current_date), 0),
    'quotes', (select count(*) from public.sales_orders o where o.company_id = p_company and o.sales_rep_id = p_emp and o.created_at::date between p_from and p_to),
    'quotes_won', (select count(*) from public.sales_orders o where o.company_id = p_company and o.sales_rep_id = p_emp and o.created_at::date between p_from and p_to
                     and exists(select 1 from public.sales_invoices s where s.order_id = o.id and s.status = 'posted')),
    'customers', (select count(*) from public.parties p where p.company_id = p_company and p.sales_rep_id = p_emp and p.kind = 'customer'),
    'trend', trend,
    'top_customers', coalesce((select jsonb_agg(z order by z.sales desc) from (
        select p.id, p.name, sum(s.subtotal) sales, count(*) n from public.sales_invoices s join public.parties p on p.id = s.party_id
         where s.company_id = p_company and s.sales_rep_id = p_emp and s.status = 'posted' and not s.is_opening and s.date between p_from and p_to
         group by p.id, p.name order by sum(s.subtotal) desc limit 8) z), '[]'),
    'leads', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'no', l.no, 'title', l.title, 'stage', l.stage, 'value', l.value, 'probability', l.probability,
                         'expected_close', l.expected_close) order by l.expected_close nulls last)
                        from public.crm_leads l join public.members mm on mm.company_id = l.company_id and mm.user_id = l.owner_id
                       where l.company_id = p_company and mm.employee_id = p_emp and l.stage not in ('won','lost')), '[]'),
    'won', (select count(*) from public.crm_leads l join public.members mm on mm.company_id = l.company_id and mm.user_id = l.owner_id
             where l.company_id = p_company and mm.employee_id = p_emp and l.stage = 'won' and l.closed_at::date between p_from and p_to),
    'lost', (select count(*) from public.crm_leads l join public.members mm on mm.company_id = l.company_id and mm.user_id = l.owner_id
             where l.company_id = p_company and mm.employee_id = p_emp and l.stage = 'lost' and l.closed_at::date between p_from and p_to),
    'activities_done', (select count(*) from public.crm_activities a join public.members mm on mm.company_id = a.company_id and mm.user_id = a.user_id
                         where a.company_id = p_company and mm.employee_id = p_emp and a.done and a.done_at::date between p_from and p_to),
    'activities_late', (select count(*) from public.crm_activities a join public.members mm on mm.company_id = a.company_id and mm.user_id = a.user_id
                         where a.company_id = p_company and mm.employee_id = p_emp and not a.done and a.due_at < now()),
    'recent', coalesce((select jsonb_agg(z order by z.date desc, z.no desc) from (
        select s.id, s.no, s.date, s.total, p.name party from public.sales_invoices s join public.parties p on p.id = s.party_id
         where s.company_id = p_company and s.sales_rep_id = p_emp and s.status = 'posted' and not s.is_opening order by s.date desc, s.no desc limit 10) z), '[]'));
end $$;

revoke all on function public.sales_rep_guard(), public.rep_net_sales(uuid, uuid, date, date) from public, anon, authenticated;
revoke all on function public.sales_target_set(uuid, uuid, date, numeric, numeric), public.rep_list(uuid, date, date), public.rep_360(uuid, uuid, date, date) from public, anon;
grant execute on function public.sales_target_set(uuid, uuid, date, numeric, numeric), public.rep_list(uuid, date, date), public.rep_360(uuid, uuid, date, date) to authenticated;
notify pgrst, 'reload schema';
