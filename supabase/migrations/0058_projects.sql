-- Waad ERP — 0058 Projects & timesheets: projects with tasks and logged hours, rolled up into
-- cost (from the employee wage) and billing (fixed budget or hourly rate). A new sellable module: 'proj'.

-- ---------- make 'proj' a real package module ----------
alter table public.company_subscriptions drop constraint if exists company_subscriptions_modules_check;
alter table public.company_subscriptions add constraint company_subscriptions_modules_check
  check (modules <@ array['hr','finance','sales','purch','stock','proj']);
-- open it for every existing company and for new ones by default (free tier: everything on)
update public.company_subscriptions set modules = array(select distinct unnest(modules || array['proj']))
  where not ('proj' = any(modules));
update public.platform_settings set default_modules = array(select distinct unnest(default_modules || array['proj']))
  where not ('proj' = any(default_modules));

create or replace function public.platform_set_settings(p_modules text[], p_trial_days int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if coalesce(cardinality(p_modules), 0) = 0 or not p_modules <@ array['hr','finance','sales','purch','stock','proj'] then raise exception 'اختر قسماً واحداً على الأقل'; end if;
  update public.platform_settings set default_modules = p_modules, default_trial_days = p_trial_days, updated_at = now() where id;
end $$;
revoke all on function public.platform_set_settings(text[], int) from public, anon;
grant execute on function public.platform_set_settings(text[], int) to authenticated;

-- ---------- who runs projects: owner/admin/finance/HR (they can read the employee list for timesheets) ----------
create or replace function public.proj_can(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.aal_ok() and public.module_on(p_company, 'proj') and exists(
    select 1 from public.members m where m.company_id = p_company and m.user_id = auth.uid()
      and (m.role in ('owner','admin','finance','hr') or m.extra_roles && array['admin','finance','hr']))
$$;
create or replace function public.require_proj(p_company uuid) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.module_on(p_company, 'proj') then raise exception 'هذا القسم غير مشمول في باقة منشأتك' using errcode = '42501'; end if;
  if not public.proj_can(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
end $$;

-- ---------- tables ----------
create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  name text not null check (length(trim(name)) >= 2),
  party_id uuid references public.parties(id),            -- the customer, when billable
  billing text not null default 'internal' check (billing in ('fixed','hourly','internal')),
  budget numeric(14,2) check (budget is null or budget >= 0),
  hourly_rate numeric(10,2) check (hourly_rate is null or hourly_rate >= 0),
  status text not null default 'active' check (status in ('active','on_hold','done','cancelled')),
  start_date date,
  due_date date,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, no),
  check (due_date is null or start_date is null or due_date >= start_date)
);
create index if not exists projects_company on public.projects(company_id, status);

create table if not exists public.project_tasks (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  title text not null check (length(trim(title)) >= 2),
  assignee_id uuid references public.employees(id),
  status text not null default 'todo' check (status in ('todo','doing','done')),
  due_date date,
  created_at timestamptz not null default now()
);
create index if not exists project_tasks_project on public.project_tasks(project_id);

create table if not exists public.timesheets (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  task_id uuid references public.project_tasks(id) on delete set null,
  employee_id uuid not null references public.employees(id),
  work_date date not null,
  hours numeric(6,2) not null check (hours > 0 and hours <= 24),
  billable boolean not null default true,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists timesheets_project on public.timesheets(project_id);
create index if not exists timesheets_emp on public.timesheets(company_id, employee_id, work_date);

-- ---------- guards ----------
create or replace function public.project_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then new.no := public.next_doc_no(new.company_id, 'PRJ');
  elsif new.company_id <> old.company_id or new.no <> old.no then raise exception 'لا يتغير رقم المشروع أو منشأته'; end if;
  new.name := trim(new.name);
  if new.party_id is not null and not exists(select 1 from public.parties where id = new.party_id and company_id = new.company_id and kind = 'customer') then
    raise exception 'العميل غير موجود';
  end if;
  if new.billing = 'hourly' and coalesce(new.hourly_rate, 0) <= 0 then raise exception 'حدّد سعر الساعة للمشروع بالساعة'; end if;
  new.note := nullif(trim(coalesce(new.note, '')), '');
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists projects_guard on public.projects;
create trigger projects_guard before insert or update on public.projects for each row execute function public.project_guard();

create or replace function public.project_child_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare pc uuid;
begin
  select company_id into pc from public.projects where id = new.project_id;
  if pc is null or pc <> new.company_id then raise exception 'المشروع غير موجود'; end if;
  -- the field references below are kept inside the matching branch so the other table's trigger never compiles them
  if tg_table_name = 'project_tasks' then
    if new.assignee_id is not null and not exists(select 1 from public.employees where id = new.assignee_id and company_id = new.company_id) then
      raise exception 'الموظف غير موجود'; end if;
  elsif tg_table_name = 'timesheets' then
    if not exists(select 1 from public.employees where id = new.employee_id and company_id = new.company_id) then raise exception 'الموظف غير موجود'; end if;
    if new.work_date > current_date then raise exception 'تاريخ العمل لا يكون في المستقبل'; end if;
    if new.task_id is not null and not exists(select 1 from public.project_tasks where id = new.task_id and project_id = new.project_id) then raise exception 'المهمة غير موجودة'; end if;
  end if;
  return new;
end $$;
drop trigger if exists project_tasks_guard on public.project_tasks;
create trigger project_tasks_guard before insert or update on public.project_tasks for each row execute function public.project_child_guard();
drop trigger if exists timesheets_guard on public.timesheets;
create trigger timesheets_guard before insert or update on public.timesheets for each row execute function public.project_child_guard();

-- ---------- RLS: the proj permission, with a restrictive module lock ----------
do $$ declare t text;
begin
  foreach t in array array['projects','project_tasks','timesheets'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_all', t);
    execute format('create policy %I on public.%I for all using (public.proj_can(company_id)) with check (public.proj_can(company_id))', t || '_all', t);
    execute format('drop policy if exists proj_module on public.%I', t);
    execute format('create policy proj_module on public.%I as restrictive for all using (public.module_on(company_id, %L)) with check (public.module_on(company_id, %L))', t, 'proj', 'proj');
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('drop trigger if exists %I on public.%I', 'audit_' || t, t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.audit_trigger()', 'audit_' || t, t);
  end loop;
end $$;

-- ---------- results per project: tasks, hours, estimated cost (from the wage) and billing ----------
create or replace function public.project_summary(p_company uuid)
returns table(project_id uuid, no text, name text, status text, billing text, budget numeric, hourly_rate numeric,
              tasks int, tasks_done int, logged_hours numeric, billable_hours numeric, est_revenue numeric, est_cost numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_proj(p_company);
  return query
  select p.id, p.no, p.name, p.status, p.billing, p.budget, p.hourly_rate,
         (select count(*)::int from public.project_tasks t where t.project_id = p.id),
         (select count(*)::int from public.project_tasks t where t.project_id = p.id and t.status = 'done'),
         coalesce((select sum(h.hours) from public.timesheets h where h.project_id = p.id), 0),
         coalesce((select sum(h.hours) from public.timesheets h where h.project_id = p.id and h.billable), 0),
         case p.billing
           when 'hourly' then round(coalesce((select sum(h.hours) from public.timesheets h where h.project_id = p.id and h.billable), 0) * coalesce(p.hourly_rate, 0), 2)
           when 'fixed' then p.budget else null end,
         coalesce((select round(sum(h.hours * (e.basic + e.housing + e.transport) / 240.0), 2)
                     from public.timesheets h join public.employees e on e.id = h.employee_id where h.project_id = p.id), 0)
    from public.projects p where p.company_id = p_company
   order by p.created_at desc;
end $$;

revoke all on function public.project_guard(), public.project_child_guard() from public, anon, authenticated;
revoke all on function public.proj_can(uuid), public.require_proj(uuid), public.project_summary(uuid) from public, anon;
grant execute on function public.proj_can(uuid), public.require_proj(uuid), public.project_summary(uuid) to authenticated;
notify pgrst, 'reload schema';
