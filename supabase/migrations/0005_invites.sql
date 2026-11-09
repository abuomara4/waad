-- Waad ERP — 0005 invitations: link a signed-up user (by email) to a company, role and employee record.
-- Flow: an admin invites an email and gets a one-time code → the person signs up with that email and enters the code.
-- The code matters when email confirmation is off (free Supabase SMTP only mails team members): email alone is not proof.

create table public.invites (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  email text not null check (email = lower(trim(email)) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  role text not null check (role in ('admin','hr','finance','accountant','storekeeper','manager','employee')),
  employee_id uuid references public.employees(id) on delete set null,
  code text not null default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  accepted_by uuid,
  accepted_at timestamptz,
  unique (company_id, email)
);

-- who may grant which role
create or replace function public.can_invite(p_company uuid, p_role text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when public.has_role(p_company, array['owner','admin']) then p_role <> 'owner'
    when public.has_role(p_company, array['hr']) then p_role in ('employee','manager')
    when public.has_role(p_company, array['finance']) then p_role in ('accountant','storekeeper')
    else false end
$$;

create or replace function public.invite_member(p_company uuid, p_email text, p_role text, p_employee uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare em text := lower(trim(coalesce(p_email,''))); iid uuid;
begin
  if not public.can_invite(p_company, p_role) then
    raise exception 'غير مصرح لك بدعوة دور «%»', p_role using errcode = '42501'; end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'البريد الإلكتروني غير صحيح'; end if;
  if p_employee is not null and not exists(select 1 from public.employees where id = p_employee and company_id = p_company) then
    raise exception 'الموظف غير موجود في المنشأة'; end if;
  if p_employee is not null and exists(select 1 from public.members where company_id = p_company and employee_id = p_employee) then
    raise exception 'سجل الموظف مربوط بحساب آخر'; end if;
  if exists(select 1 from public.invites where company_id = p_company and email = em and accepted_at is not null) then
    raise exception 'هذا البريد قبل الدعوة مسبقاً — عدّل دوره من قائمة المستخدمين'; end if;
  insert into public.invites(company_id, email, role, employee_id) values (p_company, em, p_role, p_employee)
  on conflict (company_id, email) do update set role = excluded.role, employee_id = excluded.employee_id, created_by = auth.uid(), created_at = now(),
    code = upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))
  returning id into iid;
  return iid;
end $$;

create or replace function public.revoke_invite(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare i public.invites;
begin
  select * into i from public.invites where id = p_id;
  if not found then raise exception 'الدعوة غير موجودة'; end if;
  if not public.can_invite(i.company_id, i.role) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if i.accepted_at is not null then raise exception 'الدعوة مقبولة — احذف المستخدم بدلاً منها'; end if;
  delete from public.invites where id = p_id;
end $$;

-- called by the app after sign-in with the code HR gave the person; email must match too
create or replace function public.accept_invite(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare em text := lower(coalesce(auth.jwt()->>'email','')); i public.invites;
begin
  if auth.uid() is null or em = '' then raise exception 'سجّل الدخول أولاً' using errcode = '42501'; end if;
  select * into i from public.invites where code = upper(replace(trim(coalesce(p_code,'')), '-', '')) and email = em and accepted_at is null for update;
  if not found then raise exception 'رمز الدعوة غير صحيح أو لا يطابق بريدك'; end if;
  if exists(select 1 from public.members where company_id = i.company_id and user_id = auth.uid()) then
    raise exception 'أنت عضو في هذه المنشأة مسبقاً'; end if;
  insert into public.members(company_id, user_id, role, employee_id)
  values (i.company_id, auth.uid(), i.role,
          case when i.employee_id is not null and not exists(select 1 from public.members m where m.company_id = i.company_id and m.employee_id = i.employee_id)
               then i.employee_id end);
  update public.invites set accepted_by = auth.uid(), accepted_at = now() where id = i.id;
  return i.company_id;
end $$;

-- the signed-in user's companies with their role (for the company switcher)
create or replace function public.my_companies()
returns table(company_id uuid, name text, role text, employee_id uuid)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, m.role, m.employee_id from public.members m join public.companies c on c.id = m.company_id
  where m.user_id = auth.uid() order by m.created_at
$$;

-- membership guard: only an owner may grant/alter/remove the owner role; a company keeps at least one owner
create or replace function public.members_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare cid uuid := coalesce(new.company_id, old.company_id);
begin
  if auth.uid() is null then return coalesce(new, old); end if;                 -- internal / service calls
  if not public.has_role(cid, array['owner','admin']) then return coalesce(new, old); end if;  -- others are limited by RLS
  if tg_op = 'INSERT' and new.role = 'owner' and exists(select 1 from public.members where company_id = cid)
     and not public.has_role(cid, array['owner']) then
    raise exception 'فقط المالك يمنح صلاحية المالك' using errcode = '42501'; end if;
  if tg_op = 'UPDATE' and (new.role = 'owner') <> (old.role = 'owner') and not public.has_role(cid, array['owner']) then
    raise exception 'فقط المالك يغيّر صلاحية المالك' using errcode = '42501'; end if;
  if tg_op = 'DELETE' and old.role = 'owner' and not public.has_role(cid, array['owner']) then
    raise exception 'فقط المالك يحذف مالكاً' using errcode = '42501'; end if;
  if old.role = 'owner' and (tg_op = 'DELETE' or new.role <> 'owner')
     and not exists(select 1 from public.members where company_id = cid and role = 'owner' and user_id <> old.user_id) then
    raise exception 'لا بد أن يبقى للمنشأة مالك واحد على الأقل'; end if;
  return coalesce(new, old);
end $$;
create trigger members_guard before insert or update or delete on public.members for each row execute function public.members_guard();

create trigger audit_invites after insert or update or delete on public.invites for each row execute function public.audit_trigger();
alter table public.invites enable row level security;
create policy inv_read on public.invites for select using (public.has_role(company_id, array['owner','admin','hr','finance']));

revoke all on function public.can_invite(uuid, text), public.invite_member(uuid, text, text, uuid), public.revoke_invite(uuid),
  public.accept_invite(text), public.my_companies() from public, anon;
grant execute on function public.can_invite(uuid, text), public.invite_member(uuid, text, text, uuid), public.revoke_invite(uuid),
  public.accept_invite(text), public.my_companies() to authenticated;
revoke all on public.invites from anon;
grant select on public.invites to authenticated;
revoke insert, update, delete on public.invites from authenticated;
