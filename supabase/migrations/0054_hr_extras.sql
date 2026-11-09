-- Waad ERP — 0054 HR extras: job grades with salary ranges, medical insurance (policies, employees and dependants),
-- and the annual training plan (planned vs. delivered, budget vs. actual cost). All inside the HR module.

-- ---------- job grades ----------
create table if not exists public.job_grades (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null check (length(trim(code)) between 1 and 20),
  name text not null check (length(trim(name)) >= 2),
  name_en text,
  min_basic numeric(12,2) not null check (min_basic >= 0),
  max_basic numeric(12,2) not null,
  housing_pct numeric(5,2) check (housing_pct is null or housing_pct between 0 and 100),
  transport numeric(12,2) check (transport is null or transport >= 0),
  ticket_class text,
  active boolean not null default true,
  note text,
  unique (company_id, code),
  check (max_basic >= min_basic)
);
alter table public.employees add column if not exists grade_id uuid references public.job_grades(id) on delete set null;

-- ---------- medical insurance ----------
create table if not exists public.insurance_policies (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  provider text not null check (length(trim(provider)) >= 2),
  policy_no text not null,
  start_date date not null,
  end_date date not null,
  note text,
  unique (company_id, policy_no),
  check (end_date > start_date)
);
create table if not exists public.insurance_members (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  policy_id uuid not null references public.insurance_policies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  relation text not null default 'self' check (relation in ('self','spouse','son','daughter','father','mother')),
  name text,                      -- dependant's name (empty for the employee)
  birth_date date,
  id_no text check (id_no is null or id_no ~ '^[12][0-9]{9}$'),
  class text not null default 'B' check (length(class) between 1 and 10),
  member_no text,
  start_date date not null default current_date,
  end_date date,
  premium numeric(12,2) check (premium is null or premium >= 0),
  status text not null default 'active' check (status in ('active','removed')),
  created_at timestamptz not null default now(),
  check (relation = 'self' or length(trim(coalesce(name, ''))) >= 3)
);
create unique index if not exists insurance_members_self on public.insurance_members(policy_id, employee_id) where relation = 'self' and status = 'active';
create index if not exists insurance_members_emp on public.insurance_members(employee_id);

create or replace function public.insurance_member_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare p public.insurance_policies;
begin
  select * into p from public.insurance_policies where id = new.policy_id;
  if p.company_id <> new.company_id or not exists(select 1 from public.employees where id = new.employee_id and company_id = new.company_id) then
    raise exception 'الوثيقة أو الموظف من منشأة أخرى'; end if;
  if new.relation = 'self' then new.name := null; end if;
  if new.end_date is not null and new.end_date < new.start_date then raise exception 'نهاية التغطية قبل بدايتها'; end if;
  if new.status = 'removed' and new.end_date is null then new.end_date := current_date; end if;
  return new;
end $$;
drop trigger if exists insurance_members_guard on public.insurance_members;
create trigger insurance_members_guard before insert or update on public.insurance_members for each row execute function public.insurance_member_guard();

-- ---------- annual training plan ----------
create table if not exists public.training_plans (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  year int not null check (year between 2000 and 2100),
  title text not null check (length(trim(title)) >= 3),
  title_en text,
  department_id uuid references public.departments(id) on delete set null,
  audience text,
  quarter int check (quarter between 1 and 4),
  participants int check (participants is null or participants > 0),
  hours numeric(6,1) check (hours is null or hours > 0),
  budget numeric(12,2) check (budget is null or budget >= 0),
  status text not null default 'planned' check (status in ('planned','in_progress','done','cancelled')),
  training_id uuid references public.trainings(id) on delete set null,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists training_plans_year on public.training_plans(company_id, year);

-- ---------- access: HR manages; employees read their own insurance cover ----------
alter table public.job_grades enable row level security;
alter table public.insurance_policies enable row level security;
alter table public.insurance_members enable row level security;
alter table public.training_plans enable row level security;
drop policy if exists grades_read on public.job_grades;
create policy grades_read on public.job_grades for select using (public.has_role(company_id, array['owner','admin','hr','finance']));
drop policy if exists grades_write on public.job_grades;
create policy grades_write on public.job_grades for all using (public.has_role(company_id, array['owner','admin','hr'])) with check (public.has_role(company_id, array['owner','admin','hr']));
drop policy if exists ipol_read on public.insurance_policies;
create policy ipol_read on public.insurance_policies for select using (public.has_role(company_id, array['owner','admin','hr','finance'])
  or exists(select 1 from public.insurance_members m where m.policy_id = insurance_policies.id and m.employee_id = public.my_employee(insurance_policies.company_id)));
drop policy if exists ipol_write on public.insurance_policies;
create policy ipol_write on public.insurance_policies for all using (public.has_role(company_id, array['owner','admin','hr'])) with check (public.has_role(company_id, array['owner','admin','hr']));
drop policy if exists imem_read on public.insurance_members;
create policy imem_read on public.insurance_members for select using (public.has_role(company_id, array['owner','admin','hr','finance']) or employee_id = public.my_employee(company_id));
drop policy if exists imem_write on public.insurance_members;
create policy imem_write on public.insurance_members for all using (public.has_role(company_id, array['owner','admin','hr'])) with check (public.has_role(company_id, array['owner','admin','hr']));
drop policy if exists tplan_read on public.training_plans;
create policy tplan_read on public.training_plans for select using (public.has_role(company_id, array['owner','admin','hr','finance','manager']));
drop policy if exists tplan_write on public.training_plans;
create policy tplan_write on public.training_plans for all using (public.has_role(company_id, array['owner','admin','hr'])) with check (public.has_role(company_id, array['owner','admin','hr']));
do $$
declare t text;
begin
  foreach t in array array['job_grades','insurance_policies','insurance_members','training_plans'] loop
    execute format('drop policy if exists hr_module on public.%I', t);
    execute format('create policy hr_module on public.%I as restrictive for all using (public.module_on(company_id, %L)) with check (public.module_on(company_id, %L))', t, 'hr', 'hr');
    execute format('drop trigger if exists audit_%s on public.%I', t, t);
    execute format('create trigger audit_%s after insert or update or delete on public.%I for each row execute function public.audit_trigger()', t, t);
  end loop;
end $$;
revoke all on public.job_grades, public.insurance_policies, public.insurance_members, public.training_plans from anon;
grant select, insert, update, delete on public.job_grades, public.insurance_policies, public.insurance_members, public.training_plans to authenticated;

-- employees whose basic salary is outside their grade's range
create or replace function public.grade_exceptions(p_company uuid)
returns table(employee_id uuid, grade_id uuid, basic numeric, min_basic numeric, max_basic numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_role(p_company, array['owner','admin','hr','finance']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query select e.id, g.id, e.basic, g.min_basic, g.max_basic from public.employees e join public.job_grades g on g.id = e.grade_id
   where e.company_id = p_company and (e.end_date is null or e.end_date >= current_date) and (e.basic < g.min_basic or e.basic > g.max_basic);
end $$;

-- insurance gaps: active employees without active cover on a valid policy, and policies ending within 60 days
create or replace function public.insurance_alerts(p_company uuid)
returns table(kind text, employee_id uuid, policy_id uuid, end_date date)
language plpgsql stable security definer set search_path = public as $$
begin
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

-- training plan vs. delivery for a year
create or replace function public.training_plan_summary(p_company uuid, p_year int)
returns table(planned int, done int, cancelled int, budget numeric, actual numeric, hours numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_role(p_company, array['owner','admin','hr','finance','manager']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query select count(*)::int, count(*) filter (where p.status = 'done')::int, count(*) filter (where p.status = 'cancelled')::int,
    coalesce(sum(p.budget), 0), coalesce(sum(t.cost), 0), coalesce(sum(p.hours), 0)
    from public.training_plans p left join public.trainings t on t.id = p.training_id where p.company_id = p_company and p.year = p_year;
end $$;

revoke all on function public.insurance_member_guard() from public, anon, authenticated;
revoke all on function public.grade_exceptions(uuid), public.insurance_alerts(uuid), public.training_plan_summary(uuid, int) from public, anon;
grant execute on function public.grade_exceptions(uuid), public.insurance_alerts(uuid), public.training_plan_summary(uuid, int) to authenticated;
notify pgrst, 'reload schema';
