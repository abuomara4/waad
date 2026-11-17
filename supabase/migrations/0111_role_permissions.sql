-- 0111 — «الصلاحيات» under HR (owner's decision, 2026-11-17): HR sets, for every job, what it may see and do in finance,
-- sales, purchasing, inventory, marketing and projects — not only the accountant and the storekeeper, but also HR, the
-- department manager and the employee role. The owner, the system admin and the finance manager keep everything.
-- A person's own permissions (member_perms), when set, still replace their roles' permissions.

alter table public.finance_permissions drop constraint if exists finance_permissions_role_check;
alter table public.finance_permissions add constraint finance_permissions_role_check check (role in ('accountant','storekeeper','hr','manager','employee'));

-- members read the grants of their company (the app needs its own role's grants to draw the menu)
drop policy if exists fp_read on public.finance_permissions;
create policy fp_read on public.finance_permissions for select using (public.is_member(company_id));

create or replace function public.fin_can(p_company uuid, p_perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.aal_ok() and public.module_on(p_company, public.perm_module(p_perm))
     and exists(select 1 from public.members m where m.company_id = p_company and m.user_id = auth.uid() and public.member_live(m.employee_id, m.role) and (
    m.role in ('owner','admin','finance') or m.extra_roles && array['admin','finance']
    or (case when exists(select 1 from public.member_perms x where x.company_id = p_company and x.user_id = m.user_id)
             then exists(select 1 from public.member_perms x where x.company_id = p_company and x.user_id = m.user_id and x.perm = p_perm)
             else exists(select 1 from public.finance_permissions f where f.company_id = p_company and f.perm = p_perm
                         and (f.role = m.role or f.role = any(m.extra_roles))) end)))
$$;

-- HR (with the owner and the system admin) sets them; the finance manager still can
create or replace function public.set_finance_permission(p_company uuid, p_role text, p_perm text, p_allowed boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.has_role(p_company, array['owner','admin','hr']) or public.fin_can(p_company, 'settings')) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_role not in ('accountant','storekeeper','hr','manager','employee') then raise exception 'صلاحيات المالك ومدير النظام والمدير المالي ثابتة'; end if;
  if p_allowed then insert into public.finance_permissions values (p_company, p_role, p_perm) on conflict do nothing;
  else delete from public.finance_permissions where company_id = p_company and role = p_role and perm = p_perm; end if;
end $$;
