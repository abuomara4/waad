-- 0118 — objectives and key results (OKRs), and attendance from fingerprint devices (owner's request, 2026-11-18)
-- * OKRs: objectives for the company, a department or an employee, per period (a year, a quarter or a half), each with
--   key results (from → target, current value); progress = the average of its key results. Everyone in the company sees
--   them (transparency); HR / the owner / the admin manage all, a manager manages his team's, an employee updates the
--   progress of his own key results.
-- * Fingerprint devices: HR imports the punch log exported from the device (ZKTeco and others: employee number + date and
--   time); the first punch of a day is the check-in, the last the check-out, recorded through att_set.

-- ---------------- OKRs ----------------
create table if not exists public.okr_objectives (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  period text not null check (period ~ '^[0-9]{4}(-Q[1-4]|-H[12])?$'),
  scope text not null default 'company' check (scope in ('company','department','employee')),
  department_id uuid references public.departments(id) on delete cascade,
  employee_id uuid references public.employees(id) on delete cascade,
  title text not null check (length(btrim(title)) between 3 and 200),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check ((scope = 'company' and department_id is null and employee_id is null) or (scope = 'department' and department_id is not null and employee_id is null)
      or (scope = 'employee' and employee_id is not null))
);
create index if not exists okr_objectives_co on public.okr_objectives(company_id, period);
create table if not exists public.okr_key_results (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  objective_id uuid not null references public.okr_objectives(id) on delete cascade,
  title text not null check (length(btrim(title)) between 2 and 200),
  start_value numeric(14,2) not null default 0,
  target numeric(14,2) not null,
  current numeric(14,2) not null default 0,
  unit text check (unit is null or length(unit) <= 20),
  updated_at timestamptz not null default now(),
  check (target <> start_value)
);
create index if not exists okr_kr_obj on public.okr_key_results(objective_id);

-- who may manage an objective: HR / owner / admin, or the manager of the employee it belongs to
create or replace function public.okr_can_manage(p_company uuid, p_emp uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.has_role(p_company, array['owner','admin','hr'])
      or (p_emp is not null and exists(select 1 from public.employees e where e.id = p_emp and e.company_id = p_company and e.manager_id is not null and e.manager_id = public.my_employee(p_company)))
$$;
alter table public.okr_objectives enable row level security;
alter table public.okr_key_results enable row level security;
drop policy if exists okr_obj_read on public.okr_objectives;
create policy okr_obj_read on public.okr_objectives for select using (public.is_member(company_id));
drop policy if exists okr_obj_write on public.okr_objectives;
create policy okr_obj_write on public.okr_objectives for all using (public.okr_can_manage(company_id, employee_id)) with check (public.okr_can_manage(company_id, employee_id));
drop policy if exists okr_kr_read on public.okr_key_results;
create policy okr_kr_read on public.okr_key_results for select using (public.is_member(company_id));
drop policy if exists okr_kr_write on public.okr_key_results;
create policy okr_kr_write on public.okr_key_results for all
  using (exists(select 1 from public.okr_objectives o where o.id = objective_id and o.company_id = okr_key_results.company_id and public.okr_can_manage(o.company_id, o.employee_id)))
  with check (exists(select 1 from public.okr_objectives o where o.id = objective_id and o.company_id = okr_key_results.company_id and public.okr_can_manage(o.company_id, o.employee_id)));
revoke all on public.okr_objectives, public.okr_key_results from anon;
grant select, insert, update, delete on public.okr_objectives, public.okr_key_results to authenticated;

-- the employee (or whoever manages the objective) records progress on a key result
create or replace function public.okr_progress(p_kr uuid, p_value numeric) returns void
language plpgsql security definer set search_path = public as $$
declare k public.okr_key_results; o public.okr_objectives;
begin
  select * into k from public.okr_key_results where id = p_kr;
  if not found then raise exception 'النتيجة غير موجودة'; end if;
  select * into o from public.okr_objectives where id = k.objective_id;
  if not (public.okr_can_manage(o.company_id, o.employee_id) or (o.employee_id is not null and o.employee_id = public.my_employee(o.company_id))) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_value is null then raise exception 'أدخل القيمة الحالية'; end if;
  update public.okr_key_results set current = p_value, updated_at = now() where id = p_kr;
end $$;

-- ---------------- fingerprint devices ----------------
-- p_rows = [{"no": employee number, "day": "YYYY-MM-DD", "in": "HH:MM", "out": "HH:MM" or null}]
create or replace function public.att_import(p_company uuid, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; e uuid; n int := 0; bad int := 0; unknown text[] := '{}'; msg text;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 20000 then raise exception 'الملف كبير أو غير صحيح (حتى 20,000 يوم في المرة)'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    select id into e from public.employees where company_id = p_company and emp_no = btrim(r->>'no');
    if e is null then
      if not (btrim(r->>'no') = any(unknown)) then unknown := unknown || btrim(r->>'no'); end if; continue; end if;
    begin
      perform public.att_set(p_company, e, (r->>'day')::date, (r->>'in')::time, nullif(r->>'out', '')::time, 'استيراد من جهاز البصمة');
      n := n + 1;
    exception when others then bad := bad + 1; msg := sqlerrm;
    end;
  end loop;
  return jsonb_build_object('days', n, 'failed', bad, 'last_error', msg, 'unknown', to_jsonb(unknown));
end $$;

revoke all on function public.okr_can_manage(uuid, uuid) from public, anon;
revoke all on function public.okr_progress(uuid, numeric) from public, anon;
revoke all on function public.att_import(uuid, jsonb) from public, anon;
grant execute on function public.okr_can_manage(uuid, uuid), public.okr_progress(uuid, numeric), public.att_import(uuid, jsonb) to authenticated;
