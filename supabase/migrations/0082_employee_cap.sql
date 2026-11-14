-- Waad ERP — 0082 employee limit per plan (pricing page: أساس 10, نمو 30, ريادة 75; extra employees are bought by raising the limit).
-- Empty (null) = no limit. Counted: employees still in service (no end date, or an end date today or later).

alter table public.company_subscriptions add column if not exists max_employees int check (max_employees is null or max_employees between 1 and 100000);
alter table public.platform_plans add column if not exists max_employees int check (max_employees is null or max_employees between 1 and 100000);

-- the check: adding an employee in service, or bringing a former employee back, beyond the limit is refused
create or replace function public.employees_cap_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare cap int;
begin
  if new.end_date is not null and new.end_date < current_date then return new; end if;               -- a past employee (e.g. imported history)
  if tg_op = 'UPDATE' and (old.end_date is null or old.end_date >= current_date) then return new; end if; -- was already counted
  select max_employees into cap from public.company_subscriptions where company_id = new.company_id;
  if cap is not null and (select count(*) from public.employees e where e.company_id = new.company_id and e.id <> new.id
                            and (e.end_date is null or e.end_date >= current_date)) >= cap then
    raise exception 'وصلت المنشأة إلى الحد الأعلى للموظفين في باقتها (%)', cap;
  end if;
  return new;
end $$;
drop trigger if exists employees_cap on public.employees;
create trigger employees_cap before insert or update of end_date on public.employees for each row execute function public.employees_cap_guard();

-- the admin site's list: the same columns plus the employee limit at the end
drop function if exists public.platform_companies();
create function public.platform_companies()
returns table(company_id uuid, name text, created_at timestamptz, owner_email text, plan text, modules text[], status text,
              trial_ends date, sub_ends date, max_users int, note text, users int, last_sign_in timestamptz,
              owner_phone text, city text, size_band text, industry text, heard_from text, usage jsonb, max_employees int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query
  select c.id, c.name, c.created_at,
         (select u.email::text from public.members m join auth.users u on u.id = m.user_id where m.company_id = c.id and m.role = 'owner' limit 1),
         s.plan, s.modules, s.status, s.trial_ends, s.sub_ends, s.max_users, s.note,
         (select count(*)::int from public.members m where m.company_id = c.id),
         (select max(u.last_sign_in_at) from public.members m join auth.users u on u.id = m.user_id where m.company_id = c.id),
         c.owner_phone, c.city, c.size_band, c.industry, c.heard_from, public.company_usage(c.id), s.max_employees
    from public.companies c left join public.company_subscriptions s on s.company_id = c.id
   order by (s.status = 'pending') desc, c.created_at desc;
end $$;
revoke all on function public.platform_companies() from public, anon;
grant execute on function public.platform_companies() to authenticated;

-- the subscription form with the employee limit (the older versions stay for older callers)
create or replace function public.platform_set_subscription(p_company uuid, p_plan text, p_modules text[], p_status text,
  p_trial_ends date, p_max_users int, p_note text, p_sub_ends date, p_max_employees int) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.platform_set_subscription(p_company, p_plan, p_modules, p_status, p_trial_ends, p_max_users, p_note, p_sub_ends);
  update public.company_subscriptions set max_employees = p_max_employees where company_id = p_company;
end $$;
revoke all on function public.platform_set_subscription(uuid, text, text[], text, date, int, text, date, int) from public, anon;
grant execute on function public.platform_set_subscription(uuid, text, text[], text, date, int, text, date, int) to authenticated;

-- plans carry an employee limit too
create or replace function public.platform_save_plan(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid := nullif(p->>'id', '')::uuid; m text[] := case when jsonb_typeof(p->'modules') = 'array' then array(select jsonb_array_elements_text(p->'modules')) else array['hr','finance','sales','purch','stock','proj'] end;
begin
  perform public.platform_guard();
  if nullif(trim(p->>'name'), '') is null then raise exception 'اكتب اسم الباقة'; end if;
  if coalesce(cardinality(m), 0) = 0 then raise exception 'اختر قسماً واحداً على الأقل'; end if;
  if v is null then
    insert into public.platform_plans(name, price, period_days, modules, max_users, max_employees, active)
    values (trim(p->>'name'), coalesce((p->>'price')::numeric, 0), coalesce((p->>'period_days')::int, 30), m, nullif(p->>'max_users', '')::int,
            nullif(p->>'max_employees', '')::int, coalesce((p->>'active')::boolean, true))
    returning id into v;
  else
    update public.platform_plans set name = trim(p->>'name'), price = coalesce((p->>'price')::numeric, 0), period_days = coalesce((p->>'period_days')::int, 30),
      modules = m, max_users = nullif(p->>'max_users', '')::int, max_employees = nullif(p->>'max_employees', '')::int, active = coalesce((p->>'active')::boolean, true) where id = v;
  end if;
  return v;
exception when unique_violation then raise exception 'اسم الباقة مستخدم مسبقاً';
end $$;

-- a payment with a plan also applies that plan's employee limit
create or replace function public.platform_add_payment(p_company uuid, p_amount numeric, p_paid_on date, p_method text, p_plan uuid, p_days int, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare pl public.platform_plans; s public.company_subscriptions; v_days int := p_days; v_from date;
begin
  perform public.platform_guard();
  if coalesce(p_amount, 0) <= 0 then raise exception 'اكتب المبلغ'; end if;
  if p_plan is not null then select * into pl from public.platform_plans where id = p_plan; v_days := coalesce(v_days, pl.period_days); end if;
  insert into public.platform_payments(company_id, amount, paid_on, method, plan_id, days, note)
  values (p_company, p_amount, coalesce(p_paid_on, (now() at time zone 'Asia/Riyadh')::date), coalesce(p_method, 'transfer'), p_plan, v_days, nullif(trim(p_note), ''));
  if v_days is not null then
    select * into s from public.company_subscriptions where company_id = p_company;
    v_from := greatest(current_date - 1, case when s.status = 'active' then coalesce(s.sub_ends, current_date - 1) else current_date - 1 end);
    update public.company_subscriptions set status = 'active', sub_ends = v_from + v_days, trial_ends = null,
      plan_id = coalesce(p_plan, plan_id), plan = coalesce(pl.name, case when plan = 'trial' then 'اشتراك' else plan end),
      modules = coalesce(pl.modules, modules), max_users = coalesce(pl.max_users, max_users),
      max_employees = case when p_plan is not null then pl.max_employees else max_employees end, updated_at = now()
     where company_id = p_company;
  end if;
end $$;

revoke all on function public.employees_cap_guard() from public, anon, authenticated;
