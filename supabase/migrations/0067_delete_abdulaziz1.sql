-- Waad ERP — 0067 delete the extra team account «abdulaziz1» entirely (owner's request). It has no company and no
-- data; the username becomes free again. Guarded so it can never touch an account that belongs to a company.
delete from auth.users u
 where lower(u.email) = 'abdulaziz1@admin.waad.app'
   and not exists(select 1 from public.members m where m.user_id = u.id);
