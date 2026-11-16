-- Waad ERP — 0090 separate job roles and a purchasing step (QA report, second batch)
-- * Two new personal permissions for the accountant/storekeeper role: «mkt» (marketing, campaigns and CRM opportunities)
--   and «proj» (projects and timesheets). Together with the per-person permissions that REPLACE the role defaults (0087),
--   the quick templates now give real separate jobs: sales rep, purchasing officer, marketing, projects — each sees only
--   its own screens.
-- * A new approval step «b» = purchasing officer (anyone who holds the purchasing permission), which the owner/HR can
--   add to any request route from «مسارات الاعتماد», e.g. purchase requests: manager → purchasing → finance → GM.

alter table public.member_perms drop constraint if exists member_perms_perm_check;
alter table public.member_perms add constraint member_perms_perm_check check (perm in
  ('dash','sales','purch','stock','stockadj','items','void','je','jepost','ledger','reports','vat','coa','payroll','settings','mkt','proj'));
alter table public.finance_permissions drop constraint if exists finance_permissions_perm_check;
alter table public.finance_permissions add constraint finance_permissions_perm_check check (perm in
  ('dash','sales','purch','stock','stockadj','items','void','je','jepost','ledger','reports','vat','coa','payroll','settings','mkt','proj'));

create or replace function public.perm_module(p_perm text) returns text language sql immutable as $$
  select case when p_perm in ('sales','mkt') then 'sales' when p_perm = 'purch' then 'purch'
              when p_perm in ('stock','stockadj','items') then 'stock' when p_perm = 'payroll' then 'hr' when p_perm = 'proj' then 'proj' else 'finance' end
$$;

-- CRM and marketing: the sales permission as before, or the marketing one
drop policy if exists crm_leads_all on public.crm_leads;
create policy crm_leads_all on public.crm_leads for all using (public.fin_can(company_id, 'sales') or public.fin_can(company_id, 'mkt'))
  with check (public.fin_can(company_id, 'sales') or public.fin_can(company_id, 'mkt'));
drop policy if exists crm_act_all on public.crm_activities;
create policy crm_act_all on public.crm_activities for all using (public.fin_can(company_id, 'sales') or public.fin_can(company_id, 'mkt'))
  with check (public.fin_can(company_id, 'sales') or public.fin_can(company_id, 'mkt'));
drop policy if exists campaign_all on public.marketing_campaigns;
create policy campaign_all on public.marketing_campaigns for all using (public.fin_can(company_id, 'sales') or public.fin_can(company_id, 'mkt'))
  with check (public.fin_can(company_id, 'sales') or public.fin_can(company_id, 'mkt'));

-- projects: owner/admin/finance/HR as before, or anyone given the projects permission
create or replace function public.proj_can(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.aal_ok() and public.module_on(p_company, 'proj') and exists(
    select 1 from public.members m where m.company_id = p_company and m.user_id = auth.uid() and public.member_live(m.employee_id, m.role)
      and (m.role in ('owner','admin','finance','hr') or m.extra_roles && array['admin','finance','hr']))
    or public.fin_can(p_company, 'proj')
$$;

-- the purchasing step
alter table public.workflows drop constraint if exists workflows_route_check;
alter table public.workflows add constraint workflows_route_check check (route <@ array['m','b','p','h','f','g']);

create or replace function public.step_label(p text) returns text language sql immutable as $$
  select case p when 'm' then 'المدير المباشر' when 'b' then 'مسؤول المشتريات' when 'p' then 'الموارد البشرية' when 'h' then 'مدير الموارد البشرية'
                when 'f' then 'المالية' when 'g' then 'المدير العام' end
$$;

create or replace function public.workflow_set(p_company uuid, p_kind text, p_route text[]) returns text[]
language plpgsql security definer set search_path = public as $$
declare rt text[];
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if p_kind not in ('leave','permit','cert','advance','resign','settle','expense','update','punch','ticket','visa','purchase') then raise exception 'نوع طلب غير معروف'; end if;
  if p_route is null then delete from public.workflows where company_id = p_company and kind = p_kind; return public.default_route(p_kind); end if;
  rt := array(select s from unnest(array['m','b','p','h','f','g']) with ordinality x(s, i) where s = any(p_route) order by i);
  if cardinality(rt) = 0 then raise exception 'اختر مرحلة اعتماد واحدة على الأقل'; end if;
  if p_kind in ('ticket','advance','expense','settle','purchase') and not ('f' = any(rt)) then raise exception 'هذا الطلب يصرف مبلغاً فلا بد أن يمر على المالية'; end if;
  insert into public.workflows(company_id, kind, route) values (p_company, p_kind, rt)
    on conflict (company_id, kind) do update set route = excluded.route;
  return rt;
end $$;

-- who may act on a step (0085 + the purchasing step; with nobody holding purchasing, the owner stands in)
create or replace function public.can_act(r public.requests, p text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.my_employee(r.company_id); is_owner boolean := public.has_role(r.company_id, array['owner']);
begin
  if me is not null and me = r.employee_id then return false; end if;   -- nobody approves their own request
  return case p
    when 'm' then exists(select 1 from public.employees e where e.id = r.employee_id and e.manager_id = me and me is not null)
                  or (is_owner and exists(select 1 from public.employees e where e.id = r.employee_id and e.manager_id is not null
                        and not exists(select 1 from public.members m where m.company_id = r.company_id and m.employee_id = e.manager_id)))
    when 'b' then (public.fin_can(r.company_id, 'purch') and not public.has_role(r.company_id, array['owner','admin','finance']))
                  or (exists(select 1 from public.members m where m.company_id = r.company_id and (m.role = 'accountant' or 'accountant' = any(m.extra_roles)) and
                        exists(select 1 from public.member_perms x where x.company_id = r.company_id and x.user_id = m.user_id and x.perm = 'purch')) is not true
                      and public.has_role(r.company_id, array['owner','admin']))
    when 'p' then public.has_role(r.company_id, array['hr','admin'])
                  or (is_owner and not exists(select 1 from public.members m where m.company_id = r.company_id
                        and (m.role in ('hr','admin') or m.extra_roles && array['hr','admin'])))
    when 'h' then exists(select 1 from public.companies c where c.id = r.company_id and c.hr_manager = auth.uid())
    when 'f' then public.has_role(r.company_id, array['finance'])
                  or (is_owner and not exists(select 1 from public.members m where m.company_id = r.company_id and (m.role = 'finance' or 'finance' = any(m.extra_roles))))
    when 'g' then is_owner
    else false end;
end $$;
