-- Company groups, phase 2 (docs/MULTI_ENTITY_DESIGN.md): the group's numbers side by side and its consolidated statements.
-- Every company keeps its own books; the statements here add them up by account code (the default chart is the same in every
-- company; an account a company added itself shows on its own line). Transactions between the group's companies are NOT
-- eliminated yet — that is phase 3 — and the screens say so. Who may read: the group's owner, while holding owner / admin /
-- finance in EVERY company of the group (a company the owner gave away is never read through the group).

create or replace function public.group_can(p_group uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.company_groups g where g.id = p_group and g.owner = auth.uid())
     and not exists(select 1 from public.companies c where c.group_id = p_group and not public.has_role(c.id, array['owner','admin','finance']))
$$;
create or replace function public.group_need(p_group uuid) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not coalesce(public.group_can(p_group), false) then raise exception 'تقارير المجموعة لمالك المجموعة فقط' using errcode = '42501'; end if;
end $$;

-- each company of the group for a period: sales, collections, purchases, payroll, headcount, revenue / expense / profit from
-- the books, and cash + bank (1110, 1120) at the end of the period
create or replace function public.group_summary(p_group uuid, p_from date, p_to date)
returns table(company_id uuid, name text, sales numeric, sales_n bigint, collected numeric, purchases numeric, payroll numeric,
              headcount bigint, revenue numeric, expense numeric, profit numeric, cash numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.group_need(p_group);
  if p_from is null or p_to is null or p_to < p_from then raise exception 'تحقق من التواريخ'; end if;
  return query
  with gl as (select l.company_id cid, sum(l.credit - l.debit) filter (where a.type = 'rev') rev, sum(l.debit - l.credit) filter (where a.type = 'exp') exp
                from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
                join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
                join public.companies c on c.id = l.company_id and c.group_id = p_group
               where e.date between p_from and p_to and a.type in ('rev','exp') and not public.is_closing_entry(e.id) group by l.company_id)
  select c.id, c.name,
    coalesce((select sum(s.total) from public.sales_invoices s where s.company_id = c.id and s.status = 'posted' and not s.is_opening and s.date between p_from and p_to), 0),
    (select count(*) from public.sales_invoices s where s.company_id = c.id and s.status = 'posted' and not s.is_opening and s.date between p_from and p_to),
    coalesce((select sum(p.amount) from public.payments p where p.company_id = c.id and p.direction = 'in' and p.date between p_from and p_to), 0),
    coalesce((select sum(x.total) from public.purchase_bills x where x.company_id = c.id and x.status = 'posted' and not x.is_opening and x.date between p_from and p_to), 0),
    coalesce((select sum(pl.gross + pl.employer_gosi) from public.payroll_lines pl join public.payroll_runs r on r.id = pl.run_id
               where r.company_id = c.id and make_date(r.year, r.month, 1) between date_trunc('month', p_from)::date and p_to), 0),
    (select count(*) from public.employees e where e.company_id = c.id and e.hire_date <= p_to and (e.end_date is null or e.end_date >= p_to)),
    coalesce((select g.rev from gl g where g.cid = c.id), 0),
    coalesce((select g.exp from gl g where g.cid = c.id), 0),
    coalesce((select g.rev from gl g where g.cid = c.id), 0) - coalesce((select g.exp from gl g where g.cid = c.id), 0),
    coalesce((select sum(l.debit - l.credit) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
               where l.company_id = c.id and l.account_code in ('1110','1120') and e.date <= p_to), 0)
  from public.companies c where c.group_id = p_group order by c.created_at;
end $$;

-- the account names of the group: the first company's name for each code
create or replace function public.group_account_names(p_group uuid) returns table(code text, name text)
language sql stable security definer set search_path = public as $$
  select distinct on (a.code) a.code, a.name from public.accounts a join public.companies c on c.id = a.company_id
   where c.group_id = p_group order by a.code, c.created_at
$$;

-- consolidated income statement (same sections as income_statement); by_company = {company id: amount}
create or replace function public.group_income_statement(p_group uuid, p_from date, p_to date)
returns table(section text, code text, name text, amount numeric, by_company jsonb)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.group_need(p_group);
  return query
  with b as (
    select a.code, a.type, l.company_id cid, sum(l.credit - l.debit) cr
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
      join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
      join public.companies c on c.id = l.company_id and c.group_id = p_group
     where e.date between p_from and p_to and a.type in ('rev','exp') and not public.is_closing_entry(e.id)
     group by a.code, a.type, l.company_id),
  t as (select b.code, b.type, sum(b.cr) cr, jsonb_object_agg(b.cid, case when b.type = 'rev' then b.cr else -b.cr end) byc
          from b group by b.code, b.type having bool_or(b.cr <> 0))
  select case when t.type = 'rev' then 'revenue' when t.code = '5100' then 'cogs' else 'expense' end, t.code, n.name,
         case when t.type = 'rev' then t.cr else -t.cr end, t.byc
    from t join public.group_account_names(p_group) n on n.code = t.code
  union all
  select 'net_profit', null, 'صافي الربح', coalesce((select sum(b.cr) from b), 0),
         coalesce((select jsonb_object_agg(z.cid, z.s) from (select b.cid, sum(b.cr) s from b group by b.cid) z), '{}')
  order by 1 desc, 2;
end $$;

-- consolidated balance sheet at a date (same sections as balance_sheet)
create or replace function public.group_balance_sheet(p_group uuid, p_as_of date)
returns table(section text, code text, name text, amount numeric, by_company jsonb)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.group_need(p_group);
  return query
  with b as (
    select a.code, a.type, l.company_id cid, sum(l.debit - l.credit) dr
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
      join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
      join public.companies c on c.id = l.company_id and c.group_id = p_group
     where e.date <= p_as_of group by a.code, a.type, l.company_id),
  t as (select b.code, b.type, sum(b.dr) dr, jsonb_object_agg(b.cid, case when b.type = 'asset' then b.dr else -b.dr end) byc
          from b where b.type in ('asset','liab','equity') group by b.code, b.type having bool_or(b.dr <> 0))
  select t.type, t.code, n.name, case when t.type = 'asset' then t.dr else -t.dr end, t.byc
    from t join public.group_account_names(p_group) n on n.code = t.code
  union all
  select 'equity', null, 'أرباح (خسائر) الفترة غير المقفلة', coalesce((select -sum(b.dr) from b where b.type in ('rev','exp')), 0),
         coalesce((select jsonb_object_agg(z.cid, z.s) from (select b.cid, -sum(b.dr) s from b where b.type in ('rev','exp') group by b.cid) z), '{}')
  order by 1, 2 nulls last;
end $$;

-- consolidated trial balance at a date; by_company = each company's net debit (+) / credit (−)
create or replace function public.group_trial_balance(p_group uuid, p_as_of date)
returns table(code text, name text, debit numeric, credit numeric, by_company jsonb)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.group_need(p_group);
  return query
  with b as (
    select l.account_code code, l.company_id cid, sum(l.debit - l.credit) dr
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
      join public.companies c on c.id = l.company_id and c.group_id = p_group
     where e.date <= p_as_of group by l.account_code, l.company_id)
  select b.code, n.name, greatest(sum(b.dr), 0)::numeric, greatest(-sum(b.dr), 0)::numeric, jsonb_object_agg(b.cid, b.dr)
    from b join public.group_account_names(p_group) n on n.code = b.code
   group by b.code, n.name having sum(b.dr) <> 0 or bool_or(b.dr <> 0) order by b.code;
end $$;

revoke all on function public.group_account_names(uuid) from public, anon, authenticated;
revoke all on function public.group_can(uuid), public.group_need(uuid), public.group_summary(uuid, date, date), public.group_income_statement(uuid, date, date),
  public.group_balance_sheet(uuid, date), public.group_trial_balance(uuid, date) from public, anon;
grant execute on function public.group_can(uuid), public.group_need(uuid), public.group_summary(uuid, date, date), public.group_income_statement(uuid, date, date),
  public.group_balance_sheet(uuid, date), public.group_trial_balance(uuid, date) to authenticated;
notify pgrst, 'reload schema';
