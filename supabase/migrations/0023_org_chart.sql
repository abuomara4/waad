-- Organisation chart.
--  * Every member can see the chart (names, job titles, departments and reporting lines only — no salaries or IDs).
--  * Departments get an optional head.
--  * Reporting lines can never loop (A reports to B who reports to A), and a manager must be in the same company.

alter table public.departments add column head_id uuid references public.employees(id) on delete set null;

create or replace function public.department_guard() returns trigger language plpgsql as $$
begin
  if new.head_id is not null and not exists(select 1 from public.employees e where e.id = new.head_id and e.company_id = new.company_id) then
    raise exception 'رئيس القسم ليس من موظفي المنشأة'; end if;
  return new;
end $$;
create trigger departments_guard before insert or update of head_id on public.departments for each row execute function public.department_guard();

create or replace function public.employee_manager_guard() returns trigger language plpgsql as $$
declare cur uuid := new.manager_id; n int := 0;
begin
  if new.manager_id is null then return new; end if;
  if new.manager_id = new.id then raise exception 'لا يكون الموظف مديراً لنفسه'; end if;
  if not exists(select 1 from public.employees m where m.id = new.manager_id and m.company_id = new.company_id) then
    raise exception 'المدير المباشر ليس من موظفي المنشأة'; end if;
  while cur is not null and n < 500 loop
    select manager_id into cur from public.employees where id = cur;
    if cur = new.id then raise exception 'تسلسل دائري: المدير المختار يتبع هذا الموظف في الهيكل'; end if;
    n := n + 1;
  end loop;
  return new;
end $$;
create trigger employees_manager_guard before insert or update of manager_id on public.employees for each row execute function public.employee_manager_guard();

create or replace function public.org_chart(p_company uuid)
returns table(id uuid, emp_no text, full_name text, full_name_en text, job_title text, job_title_en text, department_id uuid, manager_id uuid, gender text, hire_date date)
language sql stable security definer set search_path = public as $$
  select e.id, e.emp_no, e.full_name, e.full_name_en, e.job_title, e.job_title_en, e.department_id, e.manager_id, e.gender, e.hire_date
    from public.employees e
   where e.company_id = p_company and public.is_member(p_company)
     and (e.end_date is null or e.end_date >= (now() at time zone 'Asia/Riyadh')::date)
   order by e.emp_no
$$;

revoke all on function public.org_chart(uuid) from public, anon;
grant execute on function public.org_chart(uuid) to authenticated;
revoke all on function public.department_guard(), public.employee_manager_guard() from public, anon, authenticated;
notify pgrst, 'reload schema';
