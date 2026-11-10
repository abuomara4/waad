-- Waad ERP — 0065 the owner's first team account was created as «abdulaziz1»: activate it the same way as 0064
-- (only if it already existed before this file was written).
insert into public.platform_admins(user_id, username, must_change_password)
select u.id, 'abdulaziz1', false
  from auth.users u
 where lower(u.email) = 'abdulaziz1@admin.waad.app'
   and u.created_at < timestamptz '2026-11-10 21:13:00+00'
   and not exists(select 1 from public.members m where m.user_id = u.id)
on conflict (user_id) do nothing;
