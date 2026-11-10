-- Waad ERP — 0068 new companies wait for Waad's approval, and every subscription can have a length in days.
-- * status 'pending': a company that just signed up; nothing opens until an admin accepts it as a trial or a subscription.
-- * sub_ends: the last day of a paid subscription (trial_ends stays the last day of a trial). After it, modules close.
-- * notified_at: when the Waad team was told about a new request (the notify workflow fills it).
-- * platform_settings.require_approval: on by default; off = new companies start a trial straight away, as before.

alter table public.company_subscriptions drop constraint if exists company_subscriptions_status_check;
alter table public.company_subscriptions add constraint company_subscriptions_status_check check (status in ('pending','trial','active','suspended'));
alter table public.company_subscriptions add column if not exists sub_ends date;
alter table public.company_subscriptions add column if not exists notified_at timestamptz;
update public.company_subscriptions set notified_at = now() where notified_at is null;   -- existing companies are not new requests
alter table public.platform_settings add column if not exists require_approval boolean not null default true;

create or replace function public.company_sub_init() returns trigger
language plpgsql security definer set search_path = public as $$
declare s public.platform_settings;
begin
  select * into s from public.platform_settings where id;
  insert into public.company_subscriptions(company_id, modules, status, trial_ends)
  values (new.id, coalesce(s.default_modules, array['hr','finance','sales','purch','stock','proj']),
          case when coalesce(s.require_approval, true) then 'pending' else 'trial' end,
          case when not coalesce(s.require_approval, true) and s.default_trial_days is not null then current_date + s.default_trial_days end)
  on conflict do nothing;
  return new;
end $$;

-- is a module open for this company today?
create or replace function public.module_on(p_company uuid, p_module text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select p_module = any(s.modules) and case s.status
            when 'active' then s.sub_ends is null or s.sub_ends >= current_date
            when 'trial' then s.trial_ends is null or s.trial_ends >= current_date
            else false end
     from public.company_subscriptions s where s.company_id = p_company), true)
$$;

drop function if exists public.platform_companies();
create function public.platform_companies()
returns table(company_id uuid, name text, created_at timestamptz, owner_email text, plan text, modules text[], status text,
              trial_ends date, sub_ends date, max_users int, note text, users int, last_sign_in timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query
  select c.id, c.name, c.created_at,
         (select u.email::text from public.members m join auth.users u on u.id = m.user_id where m.company_id = c.id and m.role = 'owner' limit 1),
         s.plan, s.modules, s.status, s.trial_ends, s.sub_ends, s.max_users, s.note,
         (select count(*)::int from public.members m where m.company_id = c.id),
         (select max(u.last_sign_in_at) from public.members m join auth.users u on u.id = m.user_id where m.company_id = c.id)
    from public.companies c left join public.company_subscriptions s on s.company_id = c.id
   order by (s.status = 'pending') desc, c.created_at desc;
end $$;

-- the full subscription form (the 7-argument version stays for older callers)
create or replace function public.platform_set_subscription(p_company uuid, p_plan text, p_modules text[], p_status text,
  p_trial_ends date, p_max_users int, p_note text, p_sub_ends date) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.platform_set_subscription(p_company, p_plan, p_modules, p_status, p_trial_ends, p_max_users, p_note);
  update public.company_subscriptions set sub_ends = p_sub_ends where company_id = p_company;
end $$;

-- accept a waiting company: as a trial or a subscription, for a number of days (empty = no end date)
create or replace function public.platform_approve(p_company uuid, p_status text, p_days int) returns void
language plpgsql security definer set search_path = public as $$
declare v_end date := case when p_days is not null then current_date + p_days end;
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_status not in ('trial','active') then raise exception 'اختر تجربة أو اشتراك'; end if;
  if p_days is not null and (p_days < 1 or p_days > 3660) then raise exception 'المدة من يوم إلى ١٠ سنوات'; end if;
  update public.company_subscriptions
     set status = p_status, plan = case when p_status = 'trial' then 'trial' when plan = 'trial' then 'اشتراك' else plan end,
         trial_ends = case when p_status = 'trial' then v_end end, sub_ends = case when p_status = 'active' then v_end end, updated_at = now()
   where company_id = p_company;
  if not found then raise exception 'المنشأة غير موجودة'; end if;
end $$;

create or replace function public.platform_set_settings(p_modules text[], p_trial_days int, p_require_approval boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.platform_set_settings(p_modules, p_trial_days);
  update public.platform_settings set require_approval = coalesce(p_require_approval, true) where id;
end $$;

revoke all on function public.platform_companies(), public.platform_set_subscription(uuid, text, text[], text, date, int, text, date),
  public.platform_approve(uuid, text, int), public.platform_set_settings(text[], int, boolean) from public, anon;
grant execute on function public.platform_companies(), public.platform_set_subscription(uuid, text, text[], text, date, int, text, date),
  public.platform_approve(uuid, text, int), public.platform_set_settings(text[], int, boolean) to authenticated;
