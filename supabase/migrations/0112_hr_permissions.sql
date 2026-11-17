-- 0112 — every permission is set by HR (owner's decision, 2026-11-17):
-- * HR joins the owner, the system admin and the finance manager: they always have every permission, fixed;
-- * eight HR-section permissions HR can give any other job (department manager, accountant, storekeeper, employee):
--     view: hr_emp employee files, documents, contracts · hr_att attendance and the leave calendar · hr_pay payroll runs ·
--           hr_disc penalties and performance reviews
--     manage: hr_recruit recruitment · hr_train training · hr_ann announcements and surveys · hr_cdocs company documents and vehicles
--   granted the same way as the finance ones (finance_permissions per job, member_perms per person) and checked by fin_can;
-- * the HR manager may name a deputy (companies.perm_deputy) who also sets the job permissions;
-- * the finance manager no longer sets them (HR does).
-- Read access is added as extra permissive policies next to the existing ones; the view functions below are their latest
-- definitions with the role check widened by «or public.fin_can(<company>, '<perm>')».

alter table public.finance_permissions drop constraint if exists finance_permissions_perm_check;
alter table public.finance_permissions add constraint finance_permissions_perm_check check (perm = any(array['dash', 'sales', 'purch', 'stock', 'stockadj', 'items', 'void', 'je', 'jepost', 'ledger', 'reports', 'vat', 'coa', 'payroll', 'settings', 'mkt', 'proj', 'hr_emp', 'hr_att', 'hr_pay', 'hr_disc', 'hr_recruit', 'hr_train', 'hr_ann', 'hr_cdocs']));
alter table public.member_perms drop constraint if exists member_perms_perm_check;
alter table public.member_perms add constraint member_perms_perm_check check (perm = any(array['dash', 'sales', 'purch', 'stock', 'stockadj', 'items', 'void', 'je', 'jepost', 'ledger', 'reports', 'vat', 'coa', 'payroll', 'settings', 'mkt', 'proj', 'hr_emp', 'hr_att', 'hr_pay', 'hr_disc', 'hr_recruit', 'hr_train', 'hr_ann', 'hr_cdocs']));
alter table public.finance_permissions drop constraint if exists finance_permissions_role_check;
delete from public.finance_permissions where role = 'hr';
alter table public.finance_permissions add constraint finance_permissions_role_check check (role in ('accountant','storekeeper','manager','employee'));
alter table public.companies add column if not exists perm_deputy uuid references auth.users(id) on delete set null;

create or replace function public.perm_module(p_perm text) returns text language sql immutable as $$
  select case when p_perm in ('sales','mkt') then 'sales' when p_perm = 'purch' then 'purch'
              when p_perm in ('stock','stockadj','items') then 'stock' when p_perm = 'payroll' or p_perm like 'hr\_%' then 'hr' when p_perm = 'proj' then 'proj' else 'finance' end
$$;

create or replace function public.fin_can(p_company uuid, p_perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.aal_ok() and public.module_on(p_company, public.perm_module(p_perm))
     and exists(select 1 from public.members m where m.company_id = p_company and m.user_id = auth.uid() and public.member_live(m.employee_id, m.role) and (
    m.role in ('owner','admin','finance','hr') or m.extra_roles && array['admin','finance','hr']
    or (case when exists(select 1 from public.member_perms x where x.company_id = p_company and x.user_id = m.user_id)
             then exists(select 1 from public.member_perms x where x.company_id = p_company and x.user_id = m.user_id and x.perm = p_perm)
             else exists(select 1 from public.finance_permissions f where f.company_id = p_company and f.perm = p_perm
                         and (f.role = m.role or f.role = any(m.extra_roles))) end)))
$$;

-- who sets the job permissions: the owner, the system admin, HR, and the HR manager's deputy
create or replace function public.perm_setter(p_company uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.has_role(p_company, array['owner','admin','hr']) or exists(select 1 from public.companies c where c.id = p_company and c.perm_deputy = auth.uid() and public.is_member(p_company))
$$;
create or replace function public.set_finance_permission(p_company uuid, p_role text, p_perm text, p_allowed boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.perm_setter(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_role not in ('accountant','storekeeper','manager','employee') then raise exception 'صلاحيات المالك ومدير النظام والمدير المالي والموارد البشرية ثابتة'; end if;
  if p_allowed then insert into public.finance_permissions values (p_company, p_role, p_perm) on conflict do nothing;
  else delete from public.finance_permissions where company_id = p_company and role = p_role and perm = p_perm; end if;
end $$;
create or replace function public.perm_deputy_set(p_company uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if p_user is not null and not exists(select 1 from public.members m where m.company_id = p_company and m.user_id = p_user) then raise exception 'المستخدم ليس من المنشأة'; end if;
  update public.companies set perm_deputy = p_user where id = p_company;
end $$;

-- ---------------- read access by permission (extra permissive policies) ----------------
drop policy if exists employees_hr_emp on public.employees;
create policy employees_hr_emp on public.employees for select using (public.fin_can(company_id, 'hr_emp'));
drop policy if exists employee_documents_hr_emp on public.employee_documents;
create policy employee_documents_hr_emp on public.employee_documents for select using (public.fin_can(company_id, 'hr_emp'));
drop policy if exists document_files_hr_emp on public.document_files;
create policy document_files_hr_emp on public.document_files for select using (public.fin_can(company_id, 'hr_emp'));
drop policy if exists contracts_hr_emp on public.contracts;
create policy contracts_hr_emp on public.contracts for select using (public.fin_can(company_id, 'hr_emp'));
drop policy if exists contract_files_hr_emp on public.contract_files;
create policy contract_files_hr_emp on public.contract_files for select using (public.fin_can(company_id, 'hr_emp'));
drop policy if exists employee_allowances_hr_emp on public.employee_allowances;
create policy employee_allowances_hr_emp on public.employee_allowances for select using (public.fin_can(company_id, 'hr_emp'));
drop policy if exists salary_history_hr_emp on public.salary_history;
create policy salary_history_hr_emp on public.salary_history for select using (public.fin_can(company_id, 'hr_emp'));
drop policy if exists custody_items_hr_emp on public.custody_items;
create policy custody_items_hr_emp on public.custody_items for select using (public.fin_can(company_id, 'hr_emp'));
drop policy if exists insurance_members_hr_emp on public.insurance_members;
create policy insurance_members_hr_emp on public.insurance_members for select using (public.fin_can(company_id, 'hr_emp'));
drop policy if exists attendance_hr_att on public.attendance;
create policy attendance_hr_att on public.attendance for select using (public.fin_can(company_id, 'hr_att'));
drop policy if exists shift_roster_hr_att on public.shift_roster;
create policy shift_roster_hr_att on public.shift_roster for select using (public.fin_can(company_id, 'hr_att'));
drop policy if exists requests_hr_att on public.requests;
create policy requests_hr_att on public.requests for select using (public.fin_can(company_id, 'hr_att') and (kind = 'leave'));
drop policy if exists payroll_runs_hr_pay on public.payroll_runs;
create policy payroll_runs_hr_pay on public.payroll_runs for select using (public.fin_can(company_id, 'hr_pay'));
drop policy if exists penalties_hr_disc on public.penalties;
create policy penalties_hr_disc on public.penalties for select using (public.fin_can(company_id, 'hr_disc'));
drop policy if exists reviews_hr_disc on public.reviews;
create policy reviews_hr_disc on public.reviews for select using (public.fin_can(company_id, 'hr_disc'));
drop policy if exists review_cycles_hr_disc on public.review_cycles;
create policy review_cycles_hr_disc on public.review_cycles for select using (public.fin_can(company_id, 'hr_disc'));
alter policy jo_all on public.job_openings using ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text]) OR public.fin_can(company_id, 'hr_recruit'))) with check (((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text]) OR public.fin_can(company_id, 'hr_recruit')) AND ((department_id IS NULL) OR (EXISTS ( SELECT 1
   FROM departments d
  WHERE ((d.id = job_openings.department_id) AND (d.company_id = job_openings.company_id)))))));
alter policy cand_all on public.candidates using ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text]) OR public.fin_can(company_id, 'hr_recruit'))) with check (((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text]) OR public.fin_can(company_id, 'hr_recruit')) AND (EXISTS ( SELECT 1
   FROM job_openings o
  WHERE ((o.id = candidates.opening_id) AND (o.company_id = candidates.company_id))))));
alter policy cand_files_all on public.candidate_files using ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text]) OR public.fin_can(company_id, 'hr_recruit'))) with check (((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text]) OR public.fin_can(company_id, 'hr_recruit')) AND (EXISTS ( SELECT 1
   FROM candidates c
  WHERE ((c.id = candidate_files.candidate_id) AND (c.company_id = candidate_files.company_id))))));
alter policy tr_write on public.trainings using ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text]) OR public.fin_can(company_id, 'hr_train'))) with check ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text]) OR public.fin_can(company_id, 'hr_train')));
alter policy ta_write on public.training_attendees using ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text]) OR public.fin_can(company_id, 'hr_train'))) with check (((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text]) OR public.fin_can(company_id, 'hr_train')) AND (training_company(training_id) = company_id) AND (EXISTS ( SELECT 1
   FROM employees e
  WHERE ((e.id = training_attendees.employee_id) AND (e.company_id = training_attendees.company_id))))));
alter policy tplan_write on public.training_plans using ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text]) OR public.fin_can(company_id, 'hr_train'))) with check ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text]) OR public.fin_can(company_id, 'hr_train')));
alter policy ca_write on public.company_announcements using ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text]) OR public.fin_can(company_id, 'hr_ann'))) with check ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text]) OR public.fin_can(company_id, 'hr_ann')));
alter policy sv_write on public.surveys using ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text]) OR public.fin_can(company_id, 'hr_ann'))) with check ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text]) OR public.fin_can(company_id, 'hr_ann')));
alter policy company_documents_all on public.company_documents using ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text, 'finance'::text]) OR public.fin_can(company_id, 'hr_cdocs'))) with check ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text, 'finance'::text]) OR public.fin_can(company_id, 'hr_cdocs')));
alter policy company_document_files_all on public.company_document_files using ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text, 'finance'::text]) OR public.fin_can(company_id, 'hr_cdocs'))) with check ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text, 'finance'::text]) OR public.fin_can(company_id, 'hr_cdocs')));
alter policy vehicles_all on public.vehicles using ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text, 'finance'::text]) OR public.fin_can(company_id, 'hr_cdocs'))) with check ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text, 'finance'::text]) OR public.fin_can(company_id, 'hr_cdocs')));
alter policy vehicle_files_all on public.vehicle_files using ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text, 'finance'::text]) OR public.fin_can(company_id, 'hr_cdocs'))) with check ((has_role(company_id, ARRAY['owner'::text, 'admin'::text, 'hr'::text, 'finance'::text]) OR public.fin_can(company_id, 'hr_cdocs')));
drop policy if exists headcount_plans_hr_recruit on public.headcount_plans;
create policy headcount_plans_hr_recruit on public.headcount_plans for select using (public.fin_can(company_id, 'hr_recruit'));
drop policy if exists announcement_reads_hr_ann on public.announcement_reads;
create policy announcement_reads_hr_ann on public.announcement_reads for select using (public.fin_can(company_id, 'hr_ann'));
drop policy if exists trainings_hr_train on public.trainings;
create policy trainings_hr_train on public.trainings for select using (public.fin_can(company_id, 'hr_train'));
drop policy if exists training_attendees_hr_train on public.training_attendees;
create policy training_attendees_hr_train on public.training_attendees for select using (public.fin_can(company_id, 'hr_train'));
drop policy if exists training_plans_hr_train on public.training_plans;
create policy training_plans_hr_train on public.training_plans for select using (public.fin_can(company_id, 'hr_train'));
drop policy if exists company_announcements_hr_ann on public.company_announcements;
create policy company_announcements_hr_ann on public.company_announcements for select using (public.fin_can(company_id, 'hr_ann'));

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
  if not (coalesce(e.id = public.my_employee(e.company_id), false) or (public.has_role(e.company_id, array['owner','admin','hr','finance']) or public.fin_can(e.company_id, 'hr_emp'))
          or coalesce(e.manager_id = public.my_employee(e.company_id), false)) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  while ex <> prev loop
    prev := ex; fin := e.probation_end + ex;
    select count(*) into ex from generate_series(e.hire_date, fin, interval '1 day') g
     where exists(select 1 from public.holidays h where h.company_id = e.company_id and h.day = g::date)
        or exists(select 1 from public.requests q where q.employee_id = e.id and q.kind = 'leave' and q.sub = 'sick' and q.status = 'approved' and g::date between q.from_date and q.to_date);
  end loop;
  return e.probation_end + ex;
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
  with act as (select * from public.employees e where e.company_id = p_company and (e.end_date is null or e.end_date >= td)),
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

CREATE OR REPLACE FUNCTION public.probation_ends(p_company uuid)
 RETURNS TABLE(employee_id uuid, probation_end date, effective_end date)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select e.id, e.probation_end, public.probation_effective_end(e.id) from public.employees e
   where e.company_id = p_company and e.probation_end is not null and (public.has_role(p_company, array['owner','admin','hr','finance']) or public.fin_can(p_company, 'hr_emp'))
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
  if not (p_emp = public.my_employee(e.company_id) or (public.has_role(e.company_id, array['owner','admin','hr','finance']) or public.fin_can(e.company_id, 'hr_emp'))
          or e.manager_id = public.my_employee(e.company_id)) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  select * into x from public.annual_leave_raw(e, p_as_of);
  return query select round(x.accrued, 2), x.taken, round(x.accrued - x.taken, 2);
end $function$;

CREATE OR REPLACE FUNCTION public.comp_balance(p_emp uuid)
 RETURNS TABLE(earned_hours numeric, used_hours numeric, balance_hours numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with e as (select * from public.employees where id = p_emp
             and ((public.has_role(company_id, array['owner','admin','hr','finance']) or public.fin_can(company_id, 'hr_emp')) or id = public.my_employee(company_id) or manager_id = public.my_employee(company_id)))
  select coalesce((select sum(hours) from public.comp_credits c where c.employee_id = e.id), 0),
         coalesce((select sum(days) * 8 from public.requests q where q.employee_id = e.id and q.kind = 'leave' and q.sub = 'comp' and q.status in ('pending','approved')), 0),
         coalesce((select sum(hours) from public.comp_credits c where c.employee_id = e.id), 0)
           - coalesce((select sum(days) * 8 from public.requests q where q.employee_id = e.id and q.kind = 'leave' and q.sub = 'comp' and q.status in ('pending','approved')), 0)
  from e
$function$;

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
      and (hr or e.id = me or e.manager_id = me)),
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
   where l.run_id = p_run
   order by e.emp_no;
end $function$;

CREATE OR REPLACE FUNCTION public.can_see_payline(p_run uuid, p_emp uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(select 1 from public.payroll_runs r where r.id = p_run and (
    (public.has_role(r.company_id, array['owner','admin','hr','finance']) or public.fin_can(r.company_id, 'hr_pay'))
    or (p_emp = public.my_employee(r.company_id) and r.status <> 'draft')))
$function$;

CREATE OR REPLACE FUNCTION public.pen_preview(p_emp uuid, p_code text, p_on date)
 RETURNS TABLE(step integer, action text, daily_wage numeric, fine numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c uuid;
begin
  select company_id into c from public.employees where id = p_emp;
  if not (public.has_role(c, array['owner','admin','hr']) or public.fin_can(c, 'hr_disc')) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query select * from public.pen_calc(p_emp, p_code, p_on);
end $function$;

CREATE OR REPLACE FUNCTION public.survey_results(p_survey uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.surveys; n int;
begin
  select * into s from public.surveys where id = p_survey;
  if s.id is null or not (public.has_role(s.company_id, array['owner','admin','hr']) or public.fin_can(s.company_id, 'hr_ann')) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  select count(*) into n from public.survey_responses where survey_id = p_survey;
  if s.anonymous and n < 3 then return jsonb_build_object('n', n, 'hidden', true, 'answers', '[]'::jsonb); end if;
  return jsonb_build_object('n', n, 'hidden', false, 'answers', coalesce((select jsonb_agg(r.answers order by r.created_at) from public.survey_responses r where r.survey_id = p_survey), '[]'::jsonb),
    'who', case when s.anonymous then '[]'::jsonb else coalesce((select jsonb_agg(e.full_name order by r.created_at) from public.survey_responses r
      left join public.members m on m.user_id = r.respondent and m.company_id = s.company_id left join public.employees e on e.id = m.employee_id where r.survey_id = p_survey), '[]'::jsonb) end);
end $function$;

revoke all on function public.perm_setter(uuid) from public, anon;
grant execute on function public.perm_setter(uuid) to authenticated;
revoke all on function public.perm_deputy_set(uuid, uuid) from public, anon;
grant execute on function public.perm_deputy_set(uuid, uuid) to authenticated;
