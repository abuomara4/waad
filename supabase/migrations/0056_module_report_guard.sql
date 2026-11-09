-- 0056: close a locked-module gap found in penetration testing.
-- The HR report functions below are SECURITY DEFINER, so they read the HR tables bypassing
-- row-level security. They checked the caller's ROLE but not whether the HR module is open,
-- so a company with HR turned off could still pull HR data through them. Gate each on module_on.
-- (CRM/purchasing reports already go through fin_can → require_fin, which checks the module.)

create or replace function public.grade_exceptions(p_company uuid)
returns table(employee_id uuid, grade_id uuid, basic numeric, min_basic numeric, max_basic numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.module_on(p_company, 'hr') then raise exception 'هذا القسم غير مشمول في باقة منشأتك' using errcode = '42501'; end if;
  if not public.has_role(p_company, array['owner','admin','hr','finance']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query select e.id, g.id, e.basic, g.min_basic, g.max_basic from public.employees e join public.job_grades g on g.id = e.grade_id
   where e.company_id = p_company and (e.end_date is null or e.end_date >= current_date) and (e.basic < g.min_basic or e.basic > g.max_basic);
end $$;

create or replace function public.insurance_alerts(p_company uuid)
returns table(kind text, employee_id uuid, policy_id uuid, end_date date)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.module_on(p_company, 'hr') then raise exception 'هذا القسم غير مشمول في باقة منشأتك' using errcode = '42501'; end if;
  if not public.has_role(p_company, array['owner','admin','hr']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query
  select 'uninsured'::text, e.id, null::uuid, null::date from public.employees e
   where e.company_id = p_company and (e.end_date is null or e.end_date >= current_date)
     and not exists(select 1 from public.insurance_members m join public.insurance_policies p on p.id = m.policy_id
                     where m.employee_id = e.id and m.relation = 'self' and m.status = 'active' and p.end_date >= current_date)
  union all
  select 'policy_ending', null, p.id, p.end_date from public.insurance_policies p
   where p.company_id = p_company and p.end_date between current_date and current_date + 60;
end $$;

create or replace function public.training_plan_summary(p_company uuid, p_year int)
returns table(planned int, done int, cancelled int, budget numeric, actual numeric, hours numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.module_on(p_company, 'hr') then raise exception 'هذا القسم غير مشمول في باقة منشأتك' using errcode = '42501'; end if;
  if not public.has_role(p_company, array['owner','admin','hr','finance','manager']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query select count(*)::int, count(*) filter (where p.status = 'done')::int, count(*) filter (where p.status = 'cancelled')::int,
    coalesce(sum(p.budget), 0), coalesce(sum(t.cost), 0), coalesce(sum(p.hours), 0)
    from public.training_plans p left join public.trainings t on t.id = p.training_id where p.company_id = p_company and p.year = p_year;
end $$;

notify pgrst, 'reload schema';
