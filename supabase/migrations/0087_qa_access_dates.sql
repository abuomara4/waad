-- Waad ERP — 0087 fixes from the full QA report (urgent part)
-- 1. Dates: every "not in the future" check used current_date, which is the server's UTC date. Between midnight and 3 am in
--    Riyadh the browser's today is one day ahead and invoices, vouchers, orders, transfers… were refused. The database's
--    own time zone is now Riyadh, so current_date is the Saudi date everywhere (new connections pick it up).
-- 2. An employee whose service has ended can no longer use the system: his membership stops counting the day after his
--    last day (the owner's own membership never stops). my_ended() lets the app tell him so instead of offering a new company.
-- 3. Accountant permissions: personal permissions set for one person (from «المستخدمون ← الصلاحيات») now REPLACE the
--    defaults of the accountant/storekeeper role instead of adding to them — a sales rep given «sales» only no longer
--    also sees purchases, journal entries and stock costs.

do $$ begin execute format('alter database %I set timezone to %L', current_database(), 'Asia/Riyadh'); end $$;
set timezone to 'Asia/Riyadh';

-- is this membership still live? (an employee past his end date is not; the owner always is)
create or replace function public.member_live(p_emp uuid, p_role text) returns boolean
language sql stable security definer set search_path = public as $$
  select p_role = 'owner' or p_emp is null
      or not exists(select 1 from public.employees e where e.id = p_emp and e.end_date is not null and e.end_date < public.riyadh_today())
$$;
revoke all on function public.member_live(uuid, text) from public, anon;
grant execute on function public.member_live(uuid, text) to authenticated;

create or replace function public.my_role(p_company uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from public.members m where company_id = p_company and user_id = auth.uid() and public.aal_ok() and public.member_live(m.employee_id, m.role)
$$;
create or replace function public.is_member(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.members m where company_id = p_company and user_id = auth.uid() and public.member_live(m.employee_id, m.role)) and public.aal_ok()
$$;
create or replace function public.my_employee(p_company uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select employee_id from public.members m where company_id = p_company and user_id = auth.uid() and public.aal_ok() and public.member_live(m.employee_id, m.role)
$$;
create or replace function public.has_role(p_company uuid, p_roles text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.members m where company_id = p_company and user_id = auth.uid() and (role = any(p_roles) or extra_roles && p_roles)
                and public.member_live(m.employee_id, m.role))
     and public.aal_ok()
$$;
create or replace function public.fin_can(p_company uuid, p_perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.aal_ok() and public.module_on(p_company, public.perm_module(p_perm))
     and exists(select 1 from public.members m where m.company_id = p_company and m.user_id = auth.uid() and public.member_live(m.employee_id, m.role) and (
    m.role in ('owner','admin','finance') or m.extra_roles && array['admin','finance']
    or ((m.role in ('accountant','storekeeper') or m.extra_roles && array['accountant','storekeeper']) and (
         case when exists(select 1 from public.member_perms x where x.company_id = p_company and x.user_id = m.user_id)
              then exists(select 1 from public.member_perms x where x.company_id = p_company and x.user_id = m.user_id and x.perm = p_perm)
              else exists(select 1 from public.finance_permissions f where f.company_id = p_company and f.perm = p_perm
                          and (f.role = m.role or f.role = any(m.extra_roles))) end))))
$$;

drop function if exists public.my_companies();
create function public.my_companies()
returns table(company_id uuid, name text, role text, employee_id uuid, code text, must_change_password boolean, roles text[], perms text[])
language sql stable security definer set search_path = public as $$
  select c.id, c.name, m.role, m.employee_id, c.code, m.must_change_password, array[m.role] || m.extra_roles,
         array(select x.perm from public.member_perms x where x.company_id = m.company_id and x.user_id = m.user_id order by 1)
  from public.members m join public.companies c on c.id = m.company_id
  where m.user_id = auth.uid() and public.member_live(m.employee_id, m.role) order by m.created_at
$$;
revoke all on function public.my_companies() from public, anon;
grant execute on function public.my_companies() to authenticated;

-- signed in but every membership has ended: the app shows «انتهت خدمتك» instead of «create a company»
create or replace function public.my_ended() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.members m where m.user_id = auth.uid() and not public.member_live(m.employee_id, m.role))
     and not exists(select 1 from public.members m where m.user_id = auth.uid() and public.member_live(m.employee_id, m.role))
$$;
revoke all on function public.my_ended() from public, anon;
grant execute on function public.my_ended() to authenticated;
