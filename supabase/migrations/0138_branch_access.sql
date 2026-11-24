-- Branches part 3: access by branch (SAP authorisation by organisational level). A member's allowed branches are
-- members.branches (empty = every branch, as before). The owner, admins, HR and finance always see every branch (owner's
-- decision 0112: those roles hold everything). Restricted users — branch managers, accountants, storekeepers, sales and
-- purchasing staff, employees holding HR permissions — see only their branches' staff and documents: restrictive policies on
-- the tables, and the HR view functions filter by the employee's branch. One's own record is always visible.
alter table public.members add column if not exists branches uuid[];

-- the branches a signed-in member is limited to: null = no limit; an outsider gets an empty list (matches nothing)
create or replace function public.branch_scope(p_company uuid) returns uuid[]
language sql stable security definer set search_path = public as $$
  select case when not public.is_member(p_company) then '{}'::uuid[]   -- an outsider: a list matching nothing
              when public.has_role(p_company, array['owner','admin','hr','finance']) then null
              else (select nullif(m.branches, '{}') from public.members m where m.company_id = p_company and m.user_id = auth.uid()) end
$$;
create or replace function public.branch_ok(p_company uuid, p_branch uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.branch_scope(p_company) is null or coalesce(p_branch = any(public.branch_scope(p_company)), false)
$$;
create or replace function public.emp_branch_ok(p_company uuid, p_emp uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(p_emp = public.my_employee(p_company), false)
      or public.branch_ok(p_company, (select e.branch_id from public.employees e where e.id = p_emp and e.company_id = p_company))
$$;

-- restrictive policies: they narrow every existing permission, never widen one
drop policy if exists branch_scope on public.employees;
create policy branch_scope on public.employees as restrictive for all using (public.emp_branch_ok(company_id, id)) with check (public.emp_branch_ok(company_id, id) or public.branch_scope(company_id) is null);
drop policy if exists branch_scope on public.attendance;
create policy branch_scope on public.attendance as restrictive for all using (public.emp_branch_ok(company_id, employee_id)) with check (public.emp_branch_ok(company_id, employee_id));
drop policy if exists branch_scope on public.requests;
create policy branch_scope on public.requests as restrictive for all using (public.emp_branch_ok(company_id, employee_id)) with check (public.emp_branch_ok(company_id, employee_id));
drop policy if exists branch_scope on public.employee_documents;
create policy branch_scope on public.employee_documents as restrictive for all using (public.emp_branch_ok(company_id, employee_id)) with check (public.emp_branch_ok(company_id, employee_id));
drop policy if exists branch_scope on public.contracts;
create policy branch_scope on public.contracts as restrictive for all using (public.emp_branch_ok(company_id, employee_id)) with check (public.emp_branch_ok(company_id, employee_id));
drop policy if exists branch_scope on public.salary_history;
create policy branch_scope on public.salary_history as restrictive for all using (public.emp_branch_ok(company_id, employee_id)) with check (public.emp_branch_ok(company_id, employee_id));
drop policy if exists branch_scope on public.employee_allowances;
create policy branch_scope on public.employee_allowances as restrictive for all using (public.emp_branch_ok(company_id, employee_id)) with check (public.emp_branch_ok(company_id, employee_id));
drop policy if exists branch_scope on public.custody_items;
create policy branch_scope on public.custody_items as restrictive for all using (public.emp_branch_ok(company_id, employee_id)) with check (public.emp_branch_ok(company_id, employee_id));
drop policy if exists branch_scope on public.insurance_members;
create policy branch_scope on public.insurance_members as restrictive for all using (public.emp_branch_ok(company_id, employee_id)) with check (public.emp_branch_ok(company_id, employee_id));
drop policy if exists branch_scope on public.penalties;
create policy branch_scope on public.penalties as restrictive for all using (public.emp_branch_ok(company_id, employee_id)) with check (public.emp_branch_ok(company_id, employee_id));
drop policy if exists branch_scope on public.reviews;
create policy branch_scope on public.reviews as restrictive for all using (public.emp_branch_ok(company_id, employee_id)) with check (public.emp_branch_ok(company_id, employee_id));
drop policy if exists branch_scope on public.shift_roster;
create policy branch_scope on public.shift_roster as restrictive for all using (public.emp_branch_ok(company_id, employee_id)) with check (public.emp_branch_ok(company_id, employee_id));
drop policy if exists branch_scope on public.sales_invoices;
create policy branch_scope on public.sales_invoices as restrictive for all using (public.branch_ok(company_id, branch_id)) with check (public.branch_ok(company_id, branch_id));
drop policy if exists branch_scope on public.purchase_bills;
create policy branch_scope on public.purchase_bills as restrictive for all using (public.branch_ok(company_id, branch_id)) with check (public.branch_ok(company_id, branch_id));
drop policy if exists branch_scope on public.payments;
create policy branch_scope on public.payments as restrictive for all using (public.branch_ok(company_id, branch_id)) with check (public.branch_ok(company_id, branch_id));
drop policy if exists branch_scope on public.sales_orders;
create policy branch_scope on public.sales_orders as restrictive for all using (public.branch_ok(company_id, branch_id)) with check (public.branch_ok(company_id, branch_id));
drop policy if exists branch_scope on public.purchase_orders;
create policy branch_scope on public.purchase_orders as restrictive for all using (public.branch_ok(company_id, branch_id)) with check (public.branch_ok(company_id, branch_id));
drop policy if exists branch_scope on public.warehouses;
create policy branch_scope on public.warehouses as restrictive for all using (public.branch_ok(company_id, branch_id)) with check (public.branch_ok(company_id, branch_id));

-- a member's allowed branches (owner / admin / HR); the default branch stays inside them
create or replace function public.member_branches_set(p_company uuid, p_user uuid, p_branches uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare b uuid[] := nullif(array(select distinct x from unnest(coalesce(p_branches, '{}')) x where x is not null), '{}');
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if b is not null and exists(select 1 from unnest(b) x where not exists(select 1 from public.branches r where r.id = x and r.company_id = p_company)) then
    raise exception 'الفرع لا يخص هذه المنشأة'; end if;
  update public.members set branches = b, branch_id = case when b is not null and (branch_id is null or not branch_id = any(b)) then b[1] else branch_id end
   where company_id = p_company and user_id = p_user;
  if not found then raise exception 'المستخدم غير موجود'; end if;
end $$;

-- the HR view functions filter by branch
CREATE OR REPLACE FUNCTION public.att_sheet(p_company uuid, p_from date, p_to date, p_emp uuid DEFAULT NULL::uuid)
 RETURNS TABLE(employee_id uuid, day date, status text, leave_sub text, att_id uuid, check_in timestamp with time zone, check_out timestamp with time zone, late_min integer, early_min integer, worked_min integer, extra_min integer, ot_min integer, source text, note text, permit_min integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.companies; me uuid := public.my_employee(p_company); hr boolean := (public.has_role(p_company, array['owner','admin','hr','finance']) or public.fin_can(p_company, 'hr_att')); td date := public.riyadh_today();
begin
  if not public.is_member(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_to < p_from or p_to - p_from > 62 then raise exception 'الفترة من يوم إلى 62 يوماً'; end if;
  select * into c from public.companies where id = p_company;
  return query
  with emps as (
    select e.* from public.employees e where e.company_id = p_company and not e.att_exempt
      and (p_emp is null or e.id = p_emp)
      and (hr or e.id = me or e.manager_id = me) and public.emp_branch_ok(p_company, e.id)),
  days as (select g::date d from generate_series(p_from, least(p_to, td), interval '1 day') g)
  select e.id, dd.d,
    case
      when a.id is not null then case when a.check_out is null then case when dd.d >= td - 1 and a.check_in > now() - interval '20 hours' then 'open' else 'nocheckout' end
                                       when a.late_min > 0 then 'late' else 'present' end
      when dd.d < e.hire_date or (e.end_date is not null and dd.d > e.end_date) then 'na'
      when h.day is not null then 'holiday'
      when lv.sub is not null then 'leave'
      when not public.is_workday(e.id, dd.d) then 'off'
      when not c.att_enabled or c.att_start is null or dd.d < c.att_start then 'na'
      when dd.d = td then 'pending'
      else 'absent' end,
    lv.sub, a.id, a.check_in, a.check_out, a.late_min, a.early_min, a.worked_min, a.extra_min, a.ot_min, a.source, a.note, a.permit_min
  from emps e cross join days dd
  left join public.attendance a on a.employee_id = e.id and a.day = dd.d
  left join public.holidays h on h.company_id = p_company and h.day = dd.d
  left join lateral (select q.sub from public.requests q where q.employee_id = e.id and q.kind = 'leave' and q.status = 'approved'
                     and dd.d between q.from_date and q.to_date limit 1) lv on true
  left join lateral (select * from public.employee_shift_on(e.id, dd.d)) s on true
  where dd.d >= e.hire_date - 0 or a.id is not null
  order by e.emp_no, dd.d;
end $function$;

CREATE OR REPLACE FUNCTION public.doc_alerts(p_company uuid, p_within integer DEFAULT 90)
 RETURNS TABLE(employee_id uuid, kind text, ref_id uuid, label text, ref_no text, due date, days_left integer, level text, note text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare td date := (now() at time zone 'Asia/Riyadh')::date;
begin
  if not (public.has_role(p_company, array['owner','admin','hr']) or public.fin_can(p_company, 'hr_emp')) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query
  with act as (select * from public.employees e where e.company_id = p_company and (e.end_date is null or e.end_date >= td) and public.emp_branch_ok(p_company, e.id)),
  docs as (
    select d.employee_id, 'doc'::text kind, d.id ref_id, d.doc_type label, d.doc_no ref_no, d.expiry_date due, null::text note
    from public.employee_documents d join act on act.id = d.employee_id
    where d.expiry_date is not null and d.expiry_date <= td + p_within
      and not exists(select 1 from public.employee_documents n where n.employee_id = d.employee_id and n.doc_type = d.doc_type and n.doc_type <> 'other'
                     and n.expiry_date > d.expiry_date)),
  con as (
    select c.employee_id, 'contract'::text kind, c.id ref_id, 'contract'::text label, null::text ref_no, c.end_date due,
      case when not act.is_saudi then 'م37: إذا استمر العمل بعد انتهائه عُدّ متجدداً لمدة مماثلة'
           when (c.renewal_no >= 3 or c.end_date >= c.first_start + interval '4 years' - interval '1 day') then 'م55/2: الاستمرار بعده يحوّله إلى غير محدد المدة'
           when c.renewal_clause then 'يتجدد تلقائياً للمدة المتفق عليها — م55/2'
           else 'م55/1: الاستمرار بعده يجعله غير محدد المدة' end note
    from public.contracts c join act on act.id = c.employee_id
    where c.status = 'active' and c.contract_type = 'fixed' and c.end_date <= td + p_within),
  miss as (
    select act.id employee_id, 'missing'::text kind, null::uuid ref_id, t.k label, null::text ref_no, null::date due, null::text note
    from act cross join (values ('iqama'), ('work_permit')) t(k)
    where not act.is_saudi and not exists(select 1 from public.employee_documents d where d.employee_id = act.id and d.doc_type = t.k)
    union all
    select act.id, 'missing'::text, null::uuid, 'contract'::text, null::text, null::date, null::text from act
    where not exists(select 1 from public.contracts c where c.employee_id = act.id and c.status = 'active')),
  -- statutory dates HR must act on: the end of probation (Reg. Art. 19: extended by holidays and sick days)
  prob as (
    select act.id employee_id, 'probation'::text kind, null::uuid ref_id, 'probation'::text label, null::text ref_no, pe.d due,
           'م53: قرّر التثبيت أو الإنهاء قبل نهايتها'::text note
    from act cross join lateral (select public.probation_effective_end(act.id) d) pe
    where act.probation_end is not null and pe.d between td and td + p_within),
  -- five years of service: annual leave becomes 30 days (Art. 109) and end-of-service a full month per year after (Art. 84)
  svc as (
    select act.id employee_id, 'service5'::text kind, null::uuid ref_id, 'service5'::text label, null::text ref_no, (act.hire_date + interval '5 years')::date due,
           'م109: تصبح الإجازة السنوية 30 يوماً — م84: أجر شهر عن كل سنة بعد الخمس'::text note
    from act where (act.hire_date + interval '5 years')::date between td and td + p_within)
  select x.employee_id, x.kind, x.ref_id, x.label, x.ref_no, x.due, (x.due - td)::int,
    case when x.due is null then 'missing' when x.due < td then 'expired' when x.due <= td + 30 then 'd30' when x.due <= td + 60 then 'd60' else 'd90' end,
    x.note
  from (select * from docs union all select * from con union all select * from miss union all select * from prob union all select * from svc) x
  order by x.due nulls last, x.employee_id;
end $function$;

CREATE OR REPLACE FUNCTION public.gosi_report(p_run uuid)
 RETURNS TABLE(employee_id uuid, is_saudi boolean, new_regime boolean, base numeric, employee_share numeric, employer_share numeric, prev_base numeric, status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.payroll_runs; ms date; me date; pms date; pme date; pr uuid;
begin
  select * into r from public.payroll_runs where id = p_run;
  if not found then raise exception 'المسير غير موجود'; end if;
  if not (public.has_role(r.company_id, array['owner','admin','hr','finance']) or public.fin_can(r.company_id, 'hr_pay')) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  ms := make_date(r.year, r.month, 1); me := (ms + interval '1 month - 1 day')::date;
  pms := (ms - interval '1 month')::date; pme := ms - 1;
  select id into pr from public.payroll_runs where company_id = r.company_id and year = extract(year from pms)::int and month = extract(month from pms)::int;
  return query
  select l.employee_id, e.is_saudi, public.gosi_is_new(e.gosi_new, e.hire_date),
         public.gosi_base(w.rate_basic, w.rate_housing), l.gosi, l.employer_gosi,
         case when pr is not null and exists(select 1 from public.payroll_lines x where x.run_id = pr and x.employee_id = l.employee_id)
              then (select public.gosi_base(p.rate_basic, p.rate_housing) from public.wage_month(l.employee_id, pms, pme) p) end,
         case when e.end_date between ms and me then 'left'
              when e.hire_date between ms and me or (pr is not null and not exists(select 1 from public.payroll_lines x where x.run_id = pr and x.employee_id = l.employee_id)) then 'new'
              else '' end
    from public.payroll_lines l join public.employees e on e.id = l.employee_id
    cross join lateral (select * from public.wage_month(l.employee_id, ms, me)) w
   where l.run_id = p_run and public.emp_branch_ok(r.company_id, l.employee_id)
   order by e.emp_no;
end $function$;

CREATE OR REPLACE FUNCTION public.can_see_payline(p_run uuid, p_emp uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(select 1 from public.payroll_runs r where r.id = p_run and (
    ((public.has_role(r.company_id, array['owner','admin','hr','finance']) or public.fin_can(r.company_id, 'hr_pay')) and public.emp_branch_ok(r.company_id, p_emp))
    or (p_emp = public.my_employee(r.company_id) and r.status <> 'draft')))
$function$;

CREATE OR REPLACE FUNCTION public.probation_ends(p_company uuid)
 RETURNS TABLE(employee_id uuid, probation_end date, effective_end date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select e.id, e.probation_end, public.probation_effective_end(e.id) from public.employees e
   where e.company_id = p_company and e.probation_end is not null and public.emp_branch_ok(p_company, e.id) and (public.has_role(p_company, array['owner','admin','hr','finance']) or public.fin_can(p_company, 'hr_emp'))
$function$;

CREATE OR REPLACE FUNCTION public.annual_leave_balance(p_emp uuid, p_as_of date DEFAULT CURRENT_DATE)
 RETURNS TABLE(accrued numeric, taken numeric, balance numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.employees; x record;
begin
  select * into e from public.employees where id = p_emp;
  if not found then return; end if;
  if not coalesce((p_emp = public.my_employee(e.company_id) or (public.has_role(e.company_id, array['owner','admin','hr','finance']) or (public.fin_can(e.company_id, 'hr_emp') and public.emp_branch_ok(e.company_id, e.id)))
          or e.manager_id = public.my_employee(e.company_id)), false) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  select * into x from public.annual_leave_raw(e, p_as_of);
  return query select round(x.accrued, 2), x.taken, round(x.accrued - x.taken, 2);
end $function$;

CREATE OR REPLACE FUNCTION public.probation_effective_end(p_emp uuid)
 RETURNS date
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.employees; ex int := 0; prev int := -1; fin date;
begin
  select * into e from public.employees where id = p_emp;
  if e.probation_end is null then return null; end if;
  if not (coalesce(e.id = public.my_employee(e.company_id), false) or (public.has_role(e.company_id, array['owner','admin','hr','finance']) or (public.fin_can(e.company_id, 'hr_emp') and public.emp_branch_ok(e.company_id, e.id)))
          or coalesce(e.manager_id = public.my_employee(e.company_id), false)) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  while ex <> prev loop
    prev := ex; fin := e.probation_end + ex;
    select count(*) into ex from generate_series(e.hire_date, fin, interval '1 day') g
     where exists(select 1 from public.holidays h where h.company_id = e.company_id and h.day = g::date)
        or exists(select 1 from public.requests q where q.employee_id = e.id and q.kind = 'leave' and q.sub = 'sick' and q.status = 'approved' and g::date between q.from_date and q.to_date);
  end loop;
  return e.probation_end + ex;
end $function$;

CREATE OR REPLACE FUNCTION public.comp_balance(p_emp uuid)
 RETURNS TABLE(earned_hours numeric, used_hours numeric, balance_hours numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with e as (select * from public.employees where id = p_emp
             and ((public.has_role(company_id, array['owner','admin','hr','finance']) or (public.fin_can(company_id, 'hr_emp') and public.emp_branch_ok(company_id, id))) or id = public.my_employee(company_id) or manager_id = public.my_employee(company_id)))
  select coalesce((select sum(hours) from public.comp_credits c where c.employee_id = e.id), 0),
         coalesce((select sum(days) * 8 from public.requests q where q.employee_id = e.id and q.kind = 'leave' and q.sub = 'comp' and q.status in ('pending','approved')), 0),
         coalesce((select sum(hours) from public.comp_credits c where c.employee_id = e.id), 0)
           - coalesce((select sum(days) * 8 from public.requests q where q.employee_id = e.id and q.kind = 'leave' and q.sub = 'comp' and q.status in ('pending','approved')), 0)
  from e
$function$;

revoke all on function public.branch_scope(uuid), public.branch_ok(uuid, uuid), public.emp_branch_ok(uuid, uuid) from public, anon;
grant execute on function public.branch_scope(uuid), public.branch_ok(uuid, uuid), public.emp_branch_ok(uuid, uuid) to authenticated;
revoke all on function public.member_branches_set(uuid, uuid, uuid[]) from public, anon;
grant execute on function public.member_branches_set(uuid, uuid, uuid[]) to authenticated;
notify pgrst, 'reload schema';
