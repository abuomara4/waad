-- Permissions per person.
--  * The owner always has everything and nobody can lower it.
--  * The owner appoints HR / system admins; HR then sets each member's access: several roles at once
--    (e.g. employee + storekeeper) and, for accountants and storekeepers, individual finance permissions.
--  * Nobody changes their own access; every change is in the audit log.

alter table public.members add column extra_roles text[] not null default '{}'
  check (extra_roles <@ array['admin','hr','finance','accountant','storekeeper','manager','employee']::text[]);

create table public.member_perms (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  perm text not null check (perm in ('dash','sales','purch','stock','stockadj','items','void','je','jepost','ledger','reports','vat','coa','payroll','settings')),
  primary key (company_id, user_id, perm)
);

-- a member holds a role if it is the main role or one of the added ones
create or replace function public.has_role(p_company uuid, p_roles text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.members where company_id = p_company and user_id = auth.uid() and (role = any(p_roles) or extra_roles && p_roles))
$$;

create or replace function public.fin_can(p_company uuid, p_perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.members m where m.company_id = p_company and m.user_id = auth.uid() and (
    m.role in ('owner','admin','finance') or m.extra_roles && array['admin','finance']
    or ((m.role in ('accountant','storekeeper') or m.extra_roles && array['accountant','storekeeper']) and (
         exists(select 1 from public.finance_permissions f where f.company_id = p_company and f.perm = p_perm
                and (f.role = m.role or f.role = any(m.extra_roles)))
      or exists(select 1 from public.member_perms x where x.company_id = p_company and x.user_id = m.user_id and x.perm = p_perm)))))
$$;

-- who may hand out which role
create or replace function public.can_invite(p_company uuid, p_role text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when public.has_role(p_company, array['owner']) then p_role <> 'owner'
    when public.has_role(p_company, array['admin']) then p_role not in ('owner','admin')
    when public.has_role(p_company, array['hr']) then p_role in ('employee','manager','finance','accountant','storekeeper')
    when public.has_role(p_company, array['finance']) then p_role in ('accountant','storekeeper')
    else false end
$$;

drop function public.my_companies();
create function public.my_companies()
returns table(company_id uuid, name text, role text, employee_id uuid, code text, must_change_password boolean, roles text[], perms text[])
language sql stable security definer set search_path = public as $$
  select c.id, c.name, m.role, m.employee_id, c.code, m.must_change_password, array[m.role] || m.extra_roles,
         array(select x.perm from public.member_perms x where x.company_id = m.company_id and x.user_id = m.user_id order by 1)
  from public.members m join public.companies c on c.id = m.company_id
  where m.user_id = auth.uid() order by m.created_at
$$;

-- everyone's access, for the permissions screen
create or replace function public.member_access(p_company uuid)
returns table(user_id uuid, role text, roles text[], perms text[])
language sql stable security definer set search_path = public as $$
  select m.user_id, m.role, array[m.role] || m.extra_roles,
         array(select x.perm from public.member_perms x where x.company_id = m.company_id and x.user_id = m.user_id order by 1)
  from public.members m where m.company_id = p_company and public.has_role(p_company, array['owner','admin','hr'])
$$;

create or replace function public.set_member_access(p_company uuid, p_user uuid, p_roles text[], p_perms text[] default '{}')
returns void language plpgsql security definer set search_path = public as $$
declare m public.members; r text; main text; rest text[]; prio text[] := array['admin','hr','finance','accountant','storekeeper','manager','employee'];
  old_roles text[];
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  select * into m from public.members where company_id = p_company and user_id = p_user for update;
  if not found then raise exception 'المستخدم غير موجود في المنشأة'; end if;
  if p_user = auth.uid() then raise exception 'لا يمكنك تعديل صلاحياتك بنفسك'; end if;
  if m.role = 'owner' then raise exception 'المالك له كل الصلاحيات دائماً ولا تُعدَّل'; end if;
  p_roles := array(select distinct x from unnest(coalesce(p_roles, '{}')) x where x is not null);
  if cardinality(p_roles) = 0 then raise exception 'اختر صلاحية واحدة على الأقل'; end if;
  if 'owner' = any(p_roles) then raise exception 'صلاحية المالك لا تُمنح من هنا'; end if;
  old_roles := array[m.role] || m.extra_roles;
  -- HR may not touch other HR staff or system admins, and only the owner/admin grants HR, only the owner grants admin
  if not public.has_role(p_company, array['owner','admin']) and old_roles && array['hr','admin'] then
    raise exception 'صلاحيات الموارد البشرية ومدير النظام يعدّلها المالك' using errcode = '42501'; end if;
  foreach r in array p_roles loop
    if not (r = any(prio)) then raise exception 'صلاحية غير معروفة: %', r; end if;
    if not (r = any(old_roles)) and not public.can_invite(p_company, r) then raise exception 'غير مصرح لك بمنح صلاحية «%»', r using errcode = '42501'; end if;
  end loop;
  foreach r in array old_roles loop
    if not (r = any(p_roles)) and not public.can_invite(p_company, r) then raise exception 'غير مصرح لك بسحب صلاحية «%»', r using errcode = '42501'; end if;
  end loop;
  select x into main from unnest(prio) with ordinality t(x, i) where x = any(p_roles) order by i limit 1;
  rest := array(select x from unnest(prio) with ordinality t(x, i) where x = any(p_roles) and x <> main order by i);
  update public.members set role = main, extra_roles = rest where company_id = p_company and user_id = p_user;
  -- individual finance permissions only make sense for accountants and storekeepers
  delete from public.member_perms where company_id = p_company and user_id = p_user;
  if p_roles && array['accountant','storekeeper'] then
    insert into public.member_perms(company_id, user_id, perm)
    select p_company, p_user, x from unnest(coalesce(p_perms, '{}')) x where x is not null group by x;
  end if;
end $$;

create trigger audit_member_perms after insert or update or delete on public.member_perms for each row execute function public.audit_trigger();
alter table public.member_perms enable row level security;
create policy mp_read on public.member_perms for select using (user_id = auth.uid() or public.has_role(company_id, array['owner','admin','hr']));
revoke all on public.member_perms from anon;
grant select on public.member_perms to authenticated;
revoke insert, update, delete on public.member_perms from authenticated;
revoke all on function public.my_companies(), public.member_access(uuid), public.set_member_access(uuid, uuid, text[], text[]) from public, anon;
grant execute on function public.my_companies(), public.member_access(uuid), public.set_member_access(uuid, uuid, text[], text[]) to authenticated;
notify pgrst, 'reload schema';
