-- Waad ERP — 0006 staff login by employee number.
-- Staff accounts use an internal address  <emp_no>.<company code>@staff.waad.app  (never mailed; needs "Confirm email" OFF).
-- HR creates the account with a temporary password, links it here, and can reset it. First login forces a password change.

alter table public.companies add column code text not null default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
alter table public.companies add constraint companies_code_key unique (code);
alter table public.companies add constraint companies_code_check check (code ~ '^[A-Z0-9]{4,10}$');
alter table public.members add column must_change_password boolean not null default false;

create or replace function public.staff_email(p_company uuid, p_employee uuid) returns text
language sql stable security definer set search_path = public as $$
  select lower(e.emp_no) || '.' || lower(c.code) || '@staff.waad.app'
  from public.employees e join public.companies c on c.id = e.company_id
  where e.id = p_employee and e.company_id = p_company and public.is_member(p_company)
$$;

-- link an account HR just created (via Auth sign-up) to the employee record
create or replace function public.link_staff_login(p_company uuid, p_employee uuid, p_role text default 'employee') returns void
language plpgsql security definer set search_path = public as $$
declare em text; uid uuid; e public.employees;
begin
  if not public.can_invite(p_company, p_role) then raise exception 'غير مصرح لك بمنح دور «%»', p_role using errcode = '42501'; end if;
  select * into e from public.employees where id = p_employee and company_id = p_company;
  if not found then raise exception 'الموظف غير موجود في المنشأة'; end if;
  if e.emp_no !~ '^[A-Za-z0-9_-]{1,20}$' then raise exception 'الرقم الوظيفي يُكتب بحروف إنجليزية أو أرقام فقط ليُستخدم في الدخول'; end if;
  if exists(select 1 from public.members where company_id = p_company and employee_id = p_employee) then raise exception 'للموظف حساب دخول مسبقاً'; end if;
  em := public.staff_email(p_company, p_employee);
  select id into uid from auth.users where lower(email) = em;
  if uid is null then raise exception 'لم يُنشأ حساب الدخول بعد'; end if;
  if exists(select 1 from public.members where user_id = uid) then raise exception 'الحساب مرتبط مسبقاً'; end if;
  insert into public.members(company_id, user_id, role, employee_id, must_change_password) values (p_company, uid, p_role, p_employee, true);
end $$;

-- HR sets a new temporary password for a staff login (never for email-based accounts)
create or replace function public.reset_staff_password(p_company uuid, p_employee uuid, p_password text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare m public.members;
begin
  select * into m from public.members where company_id = p_company and employee_id = p_employee;
  if not found then raise exception 'لا يوجد حساب دخول لهذا الموظف'; end if;
  if not public.can_invite(p_company, m.role) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if m.user_id = auth.uid() then raise exception 'غيّر كلمة مرورك من حسابك'; end if;
  if length(coalesce(p_password, '')) < 8 then raise exception 'كلمة المرور 8 أحرف على الأقل'; end if;
  if not exists(select 1 from auth.users where id = m.user_id and lower(email) = public.staff_email(p_company, p_employee)) then
    raise exception 'هذا الموظف يدخل ببريده — يستعيد كلمة المرور من «نسيت كلمة المرور»'; end if;
  update auth.users set encrypted_password = crypt(p_password, gen_salt('bf')) where id = m.user_id;
  update public.members set must_change_password = true where company_id = p_company and user_id = m.user_id;
end $$;

create or replace function public.password_changed() returns void
language sql security definer set search_path = public as $$
  update public.members set must_change_password = false where user_id = auth.uid()
$$;

drop function public.my_companies();
create function public.my_companies()
returns table(company_id uuid, name text, role text, employee_id uuid, code text, must_change_password boolean)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, m.role, m.employee_id, c.code, m.must_change_password from public.members m join public.companies c on c.id = m.company_id
  where m.user_id = auth.uid() order by m.created_at
$$;

-- which employees already have a login (HR screens), without exposing auth.users
create or replace function public.staff_logins(p_company uuid) returns table(employee_id uuid, role text, by_number boolean, must_change_password boolean)
language sql stable security definer set search_path = public as $$
  select m.employee_id, m.role, lower(u.email) = public.staff_email(p_company, m.employee_id), m.must_change_password
  from public.members m join auth.users u on u.id = m.user_id
  where m.company_id = p_company and m.employee_id is not null and public.has_role(p_company, array['owner','admin','hr'])
$$;

revoke all on function public.staff_email(uuid, uuid), public.link_staff_login(uuid, uuid, text), public.reset_staff_password(uuid, uuid, text),
  public.password_changed(), public.my_companies(), public.staff_logins(uuid) from public, anon;
grant execute on function public.staff_email(uuid, uuid), public.link_staff_login(uuid, uuid, text), public.reset_staff_password(uuid, uuid, text),
  public.password_changed(), public.my_companies(), public.staff_logins(uuid) to authenticated;
