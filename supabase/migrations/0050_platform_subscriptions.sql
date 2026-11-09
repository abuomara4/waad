-- Waad ERP — 0050 subscriptions (which modules each company has) and the platform admin panel.
-- The platform admin sees subscription metadata only (company name, plan, modules, status, user count, last sign-in),
-- never company records. Module locks are enforced in the database, not only hidden in the interface.

-- ---------- platform admins (by account id; managed with SQL only, no grants) ----------
create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  added_at timestamptz not null default now()
);
alter table public.platform_admins enable row level security;
revoke all on public.platform_admins from anon, authenticated;

create or replace function public.is_platform_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.platform_admins where user_id = auth.uid()) and public.aal_ok()
$$;

-- ---------- platform settings (defaults for new companies) ----------
create table if not exists public.platform_settings (
  id boolean primary key default true check (id),
  default_modules text[] not null default array['hr','finance','sales','purch','stock'],
  default_trial_days int check (default_trial_days is null or default_trial_days between 1 and 365),
  updated_at timestamptz not null default now()
);
insert into public.platform_settings(id) values (true) on conflict do nothing;
alter table public.platform_settings enable row level security;
revoke all on public.platform_settings from anon, authenticated;

-- ---------- one subscription row per company ----------
create table if not exists public.company_subscriptions (
  company_id uuid primary key references public.companies(id) on delete cascade,
  plan text not null default 'trial' check (length(plan) between 1 and 40),
  modules text[] not null default array['hr','finance','sales','purch','stock']
    check (modules <@ array['hr','finance','sales','purch','stock']),
  status text not null default 'trial' check (status in ('trial','active','suspended')),
  trial_ends date,
  max_users int check (max_users is null or max_users between 1 and 100000),
  note text,
  updated_at timestamptz not null default now()
);
alter table public.company_subscriptions enable row level security;
drop policy if exists sub_read on public.company_subscriptions;
create policy sub_read on public.company_subscriptions for select using (public.is_member(company_id));
revoke all on public.company_subscriptions from anon, authenticated;
grant select on public.company_subscriptions to authenticated;
drop trigger if exists audit_company_subscriptions on public.company_subscriptions;
create trigger audit_company_subscriptions after insert or update on public.company_subscriptions
  for each row execute function public.audit_trigger();

-- existing companies keep everything; new ones get the platform defaults
insert into public.company_subscriptions(company_id) select id from public.companies on conflict do nothing;
create or replace function public.company_sub_init() returns trigger
language plpgsql security definer set search_path = public as $$
declare s public.platform_settings;
begin
  select * into s from public.platform_settings where id;
  insert into public.company_subscriptions(company_id, modules, trial_ends)
  values (new.id, coalesce(s.default_modules, array['hr','finance','sales','purch','stock']),
          case when s.default_trial_days is not null then current_date + s.default_trial_days end)
  on conflict do nothing;
  return new;
end $$;
drop trigger if exists companies_sub_init on public.companies;
create trigger companies_sub_init after insert on public.companies for each row execute function public.company_sub_init();

-- is a module open for this company today?
create or replace function public.module_on(p_company uuid, p_module text) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select s.status <> 'suspended' and p_module = any(s.modules)
                          and (s.status = 'active' or s.trial_ends is null or s.trial_ends >= current_date)
                     from public.company_subscriptions s where s.company_id = p_company), true)
$$;
create or replace function public.perm_module(p_perm text) returns text language sql immutable as $$
  select case when p_perm = 'sales' then 'sales' when p_perm = 'purch' then 'purch'
              when p_perm in ('stock','stockadj','items') then 'stock' when p_perm = 'payroll' then 'hr' else 'finance' end
$$;

-- finance-side permissions now also need the module (reads through RLS and writes through RPCs both use fin_can)
create or replace function public.fin_can(p_company uuid, p_perm text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.aal_ok() and public.module_on(p_company, public.perm_module(p_perm))
     and exists(select 1 from public.members m where m.company_id = p_company and m.user_id = auth.uid() and (
    m.role in ('owner','admin','finance') or m.extra_roles && array['admin','finance']
    or ((m.role in ('accountant','storekeeper') or m.extra_roles && array['accountant','storekeeper']) and (
         exists(select 1 from public.finance_permissions f where f.company_id = p_company and f.perm = p_perm
                and (f.role = m.role or f.role = any(m.extra_roles)))
      or exists(select 1 from public.member_perms x where x.company_id = p_company and x.user_id = m.user_id and x.perm = p_perm)))))
$$;
create or replace function public.require_fin(p_company uuid, p_perm text) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.module_on(p_company, public.perm_module(p_perm)) then
    raise exception 'هذا القسم غير مشمول في باقة منشأتك' using errcode = '42501';
  end if;
  if not public.fin_can(p_company, p_perm) then
    raise exception 'غير مصرح: تحتاج صلاحية «%» في المالية', p_perm using errcode = '42501';
  end if;
end $$;

-- HR-only tables: a restrictive policy on top of the existing ones closes them when HR is not in the package
do $$
declare t text;
begin
  foreach t in array array['attendance','candidate_files','candidates','clearance_marks','comp_credits','contracts','custody','custody_items',
    'employee_allowances','employee_documents','exit_visas','job_openings','letters','payroll_runs','penalties','policies','policy_acks',
    'review_cycles','reviews','salary_history','shift_roster','training_attendees','trainings','travel_files','travel_tickets'] loop
    execute format('drop policy if exists hr_module on public.%I', t);
    execute format('create policy hr_module on public.%I as restrictive for all using (public.module_on(company_id, %L)) with check (public.module_on(company_id, %L))', t, 'hr', 'hr');
  end loop;
end $$;

-- user cap of the package
create or replace function public.members_cap_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare cap int;
begin
  select max_users into cap from public.company_subscriptions where company_id = new.company_id;
  if cap is not null and (select count(*) from public.members where company_id = new.company_id) >= cap then
    raise exception 'وصلت المنشأة إلى الحد الأعلى للمستخدمين في باقتها (%)', cap;
  end if;
  return new;
end $$;
drop trigger if exists members_cap on public.members;
create trigger members_cap before insert on public.members for each row execute function public.members_cap_guard();

-- ---------- platform admin panel: metadata only ----------
create or replace function public.platform_companies()
returns table(company_id uuid, name text, created_at timestamptz, owner_email text, plan text, modules text[], status text,
              trial_ends date, max_users int, note text, users int, last_sign_in timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query
  select c.id, c.name, c.created_at,
         (select u.email::text from public.members m join auth.users u on u.id = m.user_id where m.company_id = c.id and m.role = 'owner' limit 1),
         s.plan, s.modules, s.status, s.trial_ends, s.max_users, s.note,
         (select count(*)::int from public.members m where m.company_id = c.id),
         (select max(u.last_sign_in_at) from public.members m join auth.users u on u.id = m.user_id where m.company_id = c.id)
    from public.companies c left join public.company_subscriptions s on s.company_id = c.id
   order by c.created_at desc;
end $$;

create or replace function public.platform_set_subscription(p_company uuid, p_plan text, p_modules text[], p_status text,
  p_trial_ends date, p_max_users int, p_note text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if not exists(select 1 from public.companies where id = p_company) then raise exception 'المنشأة غير موجودة'; end if;
  if coalesce(cardinality(p_modules), 0) = 0 then raise exception 'اختر قسماً واحداً على الأقل'; end if;
  insert into public.company_subscriptions(company_id, plan, modules, status, trial_ends, max_users, note, updated_at)
  values (p_company, coalesce(nullif(trim(p_plan), ''), 'custom'), p_modules, p_status, p_trial_ends, p_max_users, nullif(trim(p_note), ''), now())
  on conflict (company_id) do update set plan = excluded.plan, modules = excluded.modules, status = excluded.status,
    trial_ends = excluded.trial_ends, max_users = excluded.max_users, note = excluded.note, updated_at = now();
end $$;

create or replace function public.platform_get_settings() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return (select to_jsonb(s) from public.platform_settings s where id);
end $$;
create or replace function public.platform_set_settings(p_modules text[], p_trial_days int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if coalesce(cardinality(p_modules), 0) = 0 or not p_modules <@ array['hr','finance','sales','purch','stock'] then raise exception 'اختر قسماً واحداً على الأقل'; end if;
  update public.platform_settings set default_modules = p_modules, default_trial_days = p_trial_days, updated_at = now() where id;
end $$;

revoke all on function public.company_sub_init(), public.members_cap_guard() from public, anon, authenticated;
revoke all on function public.is_platform_admin(), public.module_on(uuid, text), public.perm_module(text), public.platform_companies(),
  public.platform_set_subscription(uuid, text, text[], text, date, int, text), public.platform_get_settings(),
  public.platform_set_settings(text[], int) from public, anon;
grant execute on function public.is_platform_admin(), public.module_on(uuid, text), public.perm_module(text), public.platform_companies(),
  public.platform_set_subscription(uuid, text, text[], text, date, int, text), public.platform_get_settings(),
  public.platform_set_settings(text[], int) to authenticated;
notify pgrst, 'reload schema';
