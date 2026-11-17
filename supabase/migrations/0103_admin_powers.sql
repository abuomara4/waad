-- 0103 — who may do what on the admin site (owner's decision, 2026-11-17):
-- * export company data at its owner's request: abdulaziz and saud (can_export);
-- * the most sensitive actions are abdulaziz's only (is_super): permanently deleting a company, adding / removing team
--   members, resetting a member's password (otherwise a member could take over another's account), and granting export.
-- If the super account is ever lost, a migration sets is_super on another username.

alter table public.platform_admins add column if not exists is_super boolean not null default false;
update public.platform_admins set is_super = true, can_export = true where username = 'abdulaziz';
update public.platform_admins set can_export = true where username = 'saud';

create or replace function public.platform_is_super() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_platform_admin() and coalesce((select is_super from public.platform_admins where user_id = auth.uid()), false)
$$;
create or replace function public.platform_super_guard() returns void
language plpgsql stable security definer set search_path = public as $$
begin if not public.platform_is_super() then raise exception 'هذا الإجراء لمالك منصة وعد فقط' using errcode = '42501'; end if; end $$;

-- the signed-in admin: also what this account may do
create or replace function public.platform_admin_me() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return (select jsonb_build_object('username', username, 'must_change', must_change_password, 'super', is_super, 'can_export', can_export)
            from public.platform_admins where user_id = auth.uid());
end $$;

drop function if exists public.platform_team();
create function public.platform_team()
returns table(username text, email text, added_at timestamptz, last_sign_in timestamptz, must_change boolean, is_me boolean, mfa boolean, is_super boolean, can_export boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query select a.username, case when a.username is null then u.email::text end, a.added_at, u.last_sign_in_at, a.must_change_password,
      a.user_id = auth.uid(), exists(select 1 from auth.mfa_factors f where f.user_id = a.user_id and f.status = 'verified'), a.is_super, a.can_export
    from public.platform_admins a join auth.users u on u.id = a.user_id order by a.added_at;
end $$;

create or replace function public.platform_add_admin(p_username text) returns void
language plpgsql security definer set search_path = public as $$
declare v_user uuid; v_created timestamptz; v_name text := lower(trim(p_username));
begin
  perform public.platform_super_guard();
  if v_name !~ '^[a-z0-9._-]{3,30}$' then raise exception 'اسم المستخدم من ٣ إلى ٣٠ حرفاً إنجليزياً أو رقماً'; end if;
  if exists(select 1 from public.platform_admins where username = v_name) then raise exception 'اسم المستخدم مستخدم مسبقاً'; end if;
  select id, created_at into v_user, v_created from auth.users where lower(email) = public.admin_email(v_name);
  if v_user is null then raise exception 'لم يُنشأ حساب الدخول بعد'; end if;
  if v_created < now() - interval '10 minutes' then raise exception 'اسم المستخدم محجوز، اختر اسماً آخر'; end if;
  if exists(select 1 from public.members where user_id = v_user) then raise exception 'اسم المستخدم محجوز، اختر اسماً آخر'; end if;
  insert into public.platform_admins(user_id, username, must_change_password, added_by) values (v_user, v_name, true, auth.uid());
end $$;

create or replace function public.platform_reset_admin_password(p_username text, p_password text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare a public.platform_admins;
begin
  perform public.platform_super_guard();
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
  perform public.platform_super_guard();
  select * into a from public.platform_admins where username = lower(trim(p_username));
  if not found then raise exception 'المستخدم غير موجود'; end if;
  if a.user_id = auth.uid() then raise exception 'لا تقدر تحذف حسابك'; end if;
  delete from public.platform_admins where user_id = a.user_id;
end $$;

-- abdulaziz turns a member's export permission on or off
create or replace function public.platform_set_export(p_username text, p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.platform_super_guard();
  update public.platform_admins set can_export = coalesce(p_on, false) where username = lower(trim(p_username)) and not is_super;
  if not found then raise exception 'المستخدم غير موجود'; end if;
end $$;

create or replace function public.platform_company_purge(p_company uuid, p_confirm text, p_reason text default null) returns void
language plpgsql security definer set search_path = public, auth as $$
declare c public.companies; s public.company_subscriptions; v_users uuid[]; v_pass int; v_left int; v_t text;
begin
  perform public.platform_guard(); perform public.platform_super_guard();
  select * into c from public.companies where id = p_company for update;
  if c.id is null then raise exception 'المنشأة غير موجودة'; end if;
  if btrim(coalesce(p_confirm, '')) <> btrim(c.name) then raise exception 'اكتب اسم المنشأة كما هو للتأكيد'; end if;
  select * into s from public.company_subscriptions where company_id = p_company;
  if s.company_id is not null and s.status <> 'suspended' and s.status <> 'pending' and public.sub_ended_on(s) is null then
    raise exception 'المنشأة شغّالة. أوقفها أولا ثم احذفها'; end if;
  -- sign-in accounts that belong to this company only (never a Waad team account)
  select coalesce(array_agg(distinct m.user_id), '{}') into v_users from public.members m
   where m.company_id = p_company
     and not exists (select 1 from public.members o where o.user_id = m.user_id and o.company_id <> p_company)
     and not exists (select 1 from public.platform_admins a where a.user_id = m.user_id);
  update public.platform_payments set company_name = coalesce(company_name, c.name) where company_id = p_company;
  insert into public.company_deletions(company_name, registered_on, ended_on, deleted_by, deleted_by_email, users_removed, reason)
  values (c.name, (c.created_at at time zone 'Asia/Riyadh')::date, case when s.company_id is not null then public.sub_ended_on(s) end,
          auth.uid(), (select email from auth.users where id = auth.uid()), coalesce(array_length(v_users, 1), 0), nullif(btrim(coalesce(p_reason, '')), ''));
  perform set_config('waad.purge', 'on', true);
  -- table by table: rows that other rows still point to wait for the next pass (lines go with their documents)
  for v_pass in 1..12 loop
    v_left := 0;
    for v_t in select c2.table_name from information_schema.columns c2 join information_schema.tables t2 using (table_schema, table_name)
                where c2.table_schema = 'public' and c2.column_name = 'company_id' and t2.table_type = 'BASE TABLE'
                  and c2.table_name not in ('companies', 'platform_payments', 'company_deletions') loop
      begin
        execute format('delete from public.%I where company_id = $1', v_t) using p_company;
      exception when foreign_key_violation then v_left := v_left + 1;
      end;
    end loop;
    exit when v_left = 0;
  end loop;
  delete from public.companies where id = p_company;
  delete from auth.users where id = any(v_users);
  perform set_config('waad.purge', '', true);
end $$;

revoke all on function public.platform_is_super(), public.platform_super_guard(), public.platform_admin_me(), public.platform_team(), public.platform_add_admin(text),
  public.platform_reset_admin_password(text, text), public.platform_remove_admin(text), public.platform_set_export(text, boolean),
  public.platform_company_purge(uuid, text, text) from public, anon;
grant execute on function public.platform_is_super(), public.platform_super_guard(), public.platform_admin_me(), public.platform_team(), public.platform_add_admin(text),
  public.platform_reset_admin_password(text, text), public.platform_remove_admin(text), public.platform_set_export(text, boolean),
  public.platform_company_purge(uuid, text, text) to authenticated;
