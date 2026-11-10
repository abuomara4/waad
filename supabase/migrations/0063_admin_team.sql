-- Waad ERP — 0063 the Waad team signs in to the admin site with a username and password (no e-mail), and an admin
-- adds the others. A team account is an internal address  <username>@admin.waad.app  (never mailed), like staff logins.
-- An account only becomes an admin when an existing admin links it right after creating it (or by a migration for the
-- first one), so registering such an address yourself gives nothing.

alter table public.platform_admins add column if not exists username text unique check (username ~ '^[a-z0-9._-]{3,30}$');
alter table public.platform_admins add column if not exists must_change_password boolean not null default false;
alter table public.platform_admins add column if not exists added_by uuid references auth.users(id) on delete set null;

create or replace function public.admin_email(p_username text) returns text language sql immutable as $$
  select lower(trim(p_username)) || '@admin.waad.app'
$$;

-- the signed-in admin: username and whether a temporary password must be changed first
create or replace function public.platform_admin_me() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return (select jsonb_build_object('username', username, 'must_change', must_change_password) from public.platform_admins where user_id = auth.uid());
end $$;

create or replace function public.platform_team()
returns table(username text, email text, added_at timestamptz, last_sign_in timestamptz, must_change boolean, is_me boolean, mfa boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query select a.username, case when a.username is null then u.email::text end, a.added_at, u.last_sign_in_at, a.must_change_password,
      a.user_id = auth.uid(), exists(select 1 from auth.mfa_factors f where f.user_id = a.user_id and f.status = 'verified')
    from public.platform_admins a join auth.users u on u.id = a.user_id order by a.added_at;
end $$;

-- link a team account the admin site has just created (sign-up with the internal address) as an admin
create or replace function public.platform_add_admin(p_username text) returns void
language plpgsql security definer set search_path = public as $$
declare v_user uuid; v_created timestamptz; v_name text := lower(trim(p_username));
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if v_name !~ '^[a-z0-9._-]{3,30}$' then raise exception 'اسم المستخدم من ٣ إلى ٣٠ حرفاً إنجليزياً أو رقماً'; end if;
  if exists(select 1 from public.platform_admins where username = v_name) then raise exception 'اسم المستخدم مستخدم مسبقاً'; end if;
  select id, created_at into v_user, v_created from auth.users where lower(email) = public.admin_email(v_name);
  if v_user is null then raise exception 'لم يُنشأ حساب الدخول بعد'; end if;
  -- only an account created moments ago by this admin: an address someone registered earlier is refused
  if v_created < now() - interval '10 minutes' then raise exception 'اسم المستخدم محجوز، اختر اسماً آخر'; end if;
  if exists(select 1 from public.members where user_id = v_user) then raise exception 'اسم المستخدم محجوز، اختر اسماً آخر'; end if;
  insert into public.platform_admins(user_id, username, must_change_password, added_by) values (v_user, v_name, true, auth.uid());
end $$;

create or replace function public.platform_reset_admin_password(p_username text, p_password text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare a public.platform_admins;
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  select * into a from public.platform_admins where username = lower(trim(p_username));
  if not found then raise exception 'المستخدم غير موجود'; end if;
  if a.user_id = auth.uid() then raise exception 'غيّر كلمة مرورك من حسابك'; end if;
  if length(coalesce(p_password, '')) < 8 then raise exception 'كلمة المرور 8 أحرف على الأقل'; end if;
  update auth.users set encrypted_password = crypt(p_password, gen_salt('bf')) where id = a.user_id;
  update public.platform_admins set must_change_password = true where user_id = a.user_id;
end $$;

create or replace function public.platform_remove_admin(p_username text) returns void
language plpgsql security definer set search_path = public as $$
declare a public.platform_admins;
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  select * into a from public.platform_admins where username = lower(trim(p_username));
  if not found then raise exception 'المستخدم غير موجود'; end if;
  if a.user_id = auth.uid() then raise exception 'لا تقدر تحذف حسابك'; end if;
  delete from public.platform_admins where user_id = a.user_id;
end $$;

-- changing a temporary password also clears it for a team account
create or replace function public.password_changed() returns void
language sql security definer set search_path = public as $$
  update public.members set must_change_password = false where user_id = auth.uid();
  update public.platform_admins set must_change_password = false where user_id = auth.uid();
$$;

revoke all on function public.admin_email(text), public.platform_admin_me(), public.platform_team(), public.platform_add_admin(text),
  public.platform_reset_admin_password(text, text), public.platform_remove_admin(text) from public, anon;
grant execute on function public.admin_email(text), public.platform_admin_me(), public.platform_team(), public.platform_add_admin(text),
  public.platform_reset_admin_password(text, text), public.platform_remove_admin(text) to authenticated;
