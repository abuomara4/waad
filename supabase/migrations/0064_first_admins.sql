-- Waad ERP — 0064 activate the first Waad team accounts, created by the owner on the admin site (?setup).
-- Only accounts that already existed before this file was written (cutoff below) are activated, so registering one of
-- these usernames after reading this public file gives nothing. Later members are added from «فريق وعد» in the admin site.
insert into public.platform_admins(user_id, username, must_change_password)
select u.id, split_part(lower(u.email), '@', 1), false
  from auth.users u
 where lower(u.email) in ('abdulaziz@admin.waad.app', 'saud@admin.waad.app')
   and u.created_at < timestamptz '2026-11-10 21:15:00+00'
   and not exists(select 1 from public.members m where m.user_id = u.id)
on conflict (user_id) do nothing;
