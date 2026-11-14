-- Waad ERP — 0085 a request never waits for nobody. Two gaps left requests invisible in «الاعتمادات»:
--  * the direct manager has no login in the system yet (or the owner's own employee record isn't linked to his account):
--    the manager step now falls to the owner until that manager can sign in;
--  * the company has no HR/admin user (a small company run by its owner): the HR step falls to the owner,
--    like the finance step already did.
-- Everything else is unchanged; app/src/core.js canAct() mirrors this.

create or replace function public.can_act(r public.requests, p text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.my_employee(r.company_id); is_owner boolean := public.has_role(r.company_id, array['owner']);
begin
  if me is not null and me = r.employee_id then return false; end if;   -- nobody approves their own request
  return case p
    when 'm' then exists(select 1 from public.employees e where e.id = r.employee_id and e.manager_id = me and me is not null)
                  or (is_owner and exists(select 1 from public.employees e where e.id = r.employee_id and e.manager_id is not null
                        and not exists(select 1 from public.members m where m.company_id = r.company_id and m.employee_id = e.manager_id)))
    when 'p' then public.has_role(r.company_id, array['hr','admin'])
                  or (is_owner and not exists(select 1 from public.members m where m.company_id = r.company_id
                        and (m.role in ('hr','admin') or m.extra_roles && array['hr','admin'])))
    when 'h' then exists(select 1 from public.companies c where c.id = r.company_id and c.hr_manager = auth.uid())
    when 'f' then public.has_role(r.company_id, array['finance'])
                  or (is_owner and not exists(select 1 from public.members m where m.company_id = r.company_id and (m.role = 'finance' or 'finance' = any(m.extra_roles))))
    when 'g' then is_owner
    else false end;
end $$;
