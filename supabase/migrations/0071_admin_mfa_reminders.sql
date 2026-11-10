-- Waad ERP — 0071 (1) the admin site requires two-step verification; (2) customers get an e-mail before their trial or
-- subscription ends (the notify workflow sends it and records which end date it reminded about).

alter table public.platform_settings add column if not exists require_admin_mfa boolean not null default true;
alter table public.company_subscriptions add column if not exists reminded_end date;

-- a platform admin counts only with a verified authenticator and a session that used it (when the setting is on)
create or replace function public.is_platform_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.platform_admins where user_id = auth.uid()) and public.aal_ok()
     and (not coalesce((select require_admin_mfa from public.platform_settings where id), true)
          or coalesce(auth.jwt()->>'aal', 'aal1') = 'aal2')
$$;

-- a team member who still has to switch on two-step verification before the admin site opens
create or replace function public.platform_needs_mfa() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.platform_admins where user_id = auth.uid())
     and coalesce((select require_admin_mfa from public.platform_settings where id), true)
     and coalesce(auth.jwt()->>'aal', 'aal1') <> 'aal2'
$$;
revoke all on function public.platform_needs_mfa() from public, anon;
grant execute on function public.platform_needs_mfa() to authenticated;
