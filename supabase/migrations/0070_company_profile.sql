-- Waad ERP — 0070 what Waad knows about each customer company.
-- * profile, asked at sign-up and editable by the owner in settings: owner mobile, city (0048), size, activity, how they heard of Waad
-- * usage, counted for the admin site: how many employees, which modules hold records, last activity.
--   Counts and dates only — never names, amounts or any record (the privacy policy says so).

alter table public.companies add column if not exists owner_phone text check (owner_phone is null or owner_phone ~ '^05[0-9]{8}$');
-- city: the national-address city already on companies (0048) is reused
alter table public.companies add column if not exists size_band text check (size_band is null or size_band in ('1-10','11-50','51-200','200+'));
alter table public.companies add column if not exists industry text check (industry is null or industry in ('trade','contracting','services','food','industry','health','education','tech','other'));
alter table public.companies add column if not exists heard_from text check (heard_from is null or heard_from in ('whatsapp','google','friend','x','linkedin','instagram','snapchat','tiktok','event','other'));

-- usage counters for one company (security definer, called only from the admin functions below)
create or replace function public.company_usage(p_company uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'employees', (select count(*) from public.employees e where e.company_id = p_company and e.end_date is null),
    'modules', array_remove(array[
        case when exists(select 1 from public.employees where company_id = p_company) then 'hr' end,
        case when exists(select 1 from public.journal_entries where company_id = p_company and source is distinct from 'opening') then 'finance' end,
        case when exists(select 1 from public.sales_invoices where company_id = p_company) then 'sales' end,
        case when exists(select 1 from public.purchase_bills where company_id = p_company) then 'purch' end,
        case when exists(select 1 from public.items where company_id = p_company) then 'stock' end,
        case when exists(select 1 from public.projects where company_id = p_company) then 'proj' end], null),
    'last_activity', (select max(at) from public.audit_log where company_id = p_company and entity <> 'company_subscriptions'))
$$;
revoke all on function public.company_usage(uuid) from public, anon, authenticated;

drop function if exists public.platform_companies();
create function public.platform_companies()
returns table(company_id uuid, name text, created_at timestamptz, owner_email text, plan text, modules text[], status text,
              trial_ends date, sub_ends date, max_users int, note text, users int, last_sign_in timestamptz,
              owner_phone text, city text, size_band text, industry text, heard_from text, usage jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query
  select c.id, c.name, c.created_at,
         (select u.email::text from public.members m join auth.users u on u.id = m.user_id where m.company_id = c.id and m.role = 'owner' limit 1),
         s.plan, s.modules, s.status, s.trial_ends, s.sub_ends, s.max_users, s.note,
         (select count(*)::int from public.members m where m.company_id = c.id),
         (select max(u.last_sign_in_at) from public.members m join auth.users u on u.id = m.user_id where m.company_id = c.id),
         c.owner_phone, c.city, c.size_band, c.industry, c.heard_from, public.company_usage(c.id)
    from public.companies c left join public.company_subscriptions s on s.company_id = c.id
   order by (s.status = 'pending') desc, c.created_at desc;
end $$;
revoke all on function public.platform_companies() from public, anon;
grant execute on function public.platform_companies() to authenticated;
