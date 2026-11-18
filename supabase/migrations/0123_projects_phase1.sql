-- 0123 — projects, phase one (owner's projects spec, 2026-11-18)
-- * Project file: contract value, cost budget, project manager, location; every project gets its own cost center (code = project no)
--   so every riyal booked on it (sales invoices, supplier bills, purchase orders, petty cash, materials, labor) is tracked.
-- * Milestones with weights (% of the project) and tasks under them (start/due dates for the Gantt chart); actual progress
--   = Σ weight × milestone progress (tasks done / tasks, or the milestone's own %), planned progress from the milestone dates.
-- * Timesheets: an employee logs his own hours on his projects → the project manager (or whoever runs projects) approves;
--   hours keyed by HR/finance directly stay approved as before.
-- * Approved billable hours → one sales invoice (rate per team member, else the project's hourly rate).
-- * Labor cost: hourly cost = (monthly gross wage + the employer's GOSI share) ÷ 240 (30 days × 8 hours, Labor Law Art. 98);
--   approved hours are moved onto the project's cost center (Dr 5200 project / Cr 5200 the employee's own center) — a re-allocation
--   of salaries already booked by payroll, so the company's total expense does not change.
-- * Materials issued from stock to a project: Dr 5120 / Cr 1300 on the project's cost center.
-- * Profitability: contract vs invoiced vs collected, cost budget vs actual (from the books), expected margin at completion.

alter table public.journal_entries drop constraint if exists journal_entries_source_check;
alter table public.journal_entries add constraint journal_entries_source_check check (source in ('manual','reversal','sales','purchase','receipt','payment',
  'stock','payroll','payroll_pay','advance','expense','opening','sales_return','purchase_return','asset','depreciation','cheque','closing','petty','trip','vehicle',
  'prepaid','bank','loan','guarantee','zakat','project'));

-- ---------------- the project file ----------------
alter table public.projects
  add column if not exists contract_value numeric(14,2) check (contract_value is null or contract_value >= 0),
  add column if not exists cost_budget numeric(14,2) check (cost_budget is null or cost_budget >= 0),
  add column if not exists manager_id uuid references public.employees(id) on delete set null,
  add column if not exists location text check (location is null or length(location) <= 200),
  add column if not exists cost_center_id uuid references public.cost_centers(id) on delete set null;
update public.projects set contract_value = budget where billing = 'fixed' and contract_value is null and budget is not null;

create or replace function public.projects_more_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.manager_id is not null and not exists(select 1 from public.employees where id = new.manager_id and company_id = new.company_id) then
    raise exception 'مدير المشروع غير موجود'; end if;
  if new.billing = 'fixed' then new.budget := coalesce(new.contract_value, new.budget); new.contract_value := coalesce(new.contract_value, new.budget); end if;
  new.location := nullif(btrim(coalesce(new.location, '')), '');
  return new;
end $$;
drop trigger if exists projects_more_guard on public.projects;
create trigger projects_more_guard before insert or update on public.projects for each row execute function public.projects_more_guard();

-- its own cost center, created with the project and renamed with it
create or replace function public.project_cc(p_project uuid) returns uuid language plpgsql security definer set search_path = public as $$
declare p public.projects; c uuid;
begin
  select * into p from public.projects where id = p_project;
  if p.cost_center_id is not null then return p.cost_center_id; end if;
  insert into public.cost_centers(company_id, code, name) values (p.company_id, left(upper(regexp_replace(p.no, '[^A-Za-z0-9_-]', '', 'g')), 12), left(p.name, 120))
    on conflict (company_id, code) do nothing;
  select id into c from public.cost_centers where company_id = p.company_id and code = left(upper(regexp_replace(p.no, '[^A-Za-z0-9_-]', '', 'g')), 12);
  update public.projects set cost_center_id = c where id = p.id;
  return c;
end $$;
create or replace function public.projects_cc_after() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then perform public.project_cc(new.id);
  elsif new.name is distinct from old.name and new.cost_center_id is not null then update public.cost_centers set name = left(new.name, 120) where id = new.cost_center_id;
  end if;
  return null;
end $$;
drop trigger if exists projects_cc_after on public.projects;
create trigger projects_cc_after after insert or update of name on public.projects for each row execute function public.projects_cc_after();
do $$ declare r record; begin for r in select id from public.projects where cost_center_id is null loop perform public.project_cc(r.id); end loop; end $$;

-- ---------------- team (billing rate per member) and milestones ----------------
create table if not exists public.project_members (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  role text check (role is null or length(role) <= 80),
  rate numeric(10,2) check (rate is null or rate >= 0),
  alloc int check (alloc is null or alloc between 1 and 100),
  unique (project_id, employee_id)
);
create table if not exists public.project_milestones (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  name text not null check (length(btrim(name)) between 2 and 150),
  weight numeric(5,2) not null default 0 check (weight between 0 and 100),
  start_date date,
  end_date date,
  progress int not null default 0 check (progress between 0 and 100),
  sort int not null default 0,
  created_at timestamptz not null default now(),
  check (end_date is null or start_date is null or end_date >= start_date)
);
create index if not exists project_milestones_p on public.project_milestones(project_id, sort);
alter table public.project_tasks add column if not exists milestone_id uuid references public.project_milestones(id) on delete set null;
alter table public.project_tasks add column if not exists start_date date;

create or replace function public.project_part_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from public.projects where id = new.project_id and company_id = new.company_id) then raise exception 'المشروع غير موجود'; end if;
  if tg_table_name = 'project_members' then
    if not exists(select 1 from public.employees where id = new.employee_id and company_id = new.company_id) then raise exception 'الموظف غير موجود'; end if;
  elsif tg_table_name = 'project_milestones' then
    if (select coalesce(sum(weight), 0) from public.project_milestones where project_id = new.project_id and id <> new.id) + new.weight > 100 then
      raise exception 'مجموع أوزان المراحل يتجاوز 100%%'; end if;
  end if;
  return new;
end $$;
drop trigger if exists project_members_guard on public.project_members;
create trigger project_members_guard before insert or update on public.project_members for each row execute function public.project_part_guard();
drop trigger if exists project_milestones_guard on public.project_milestones;
create trigger project_milestones_guard before insert or update on public.project_milestones for each row execute function public.project_part_guard();
-- a task's milestone must belong to its project
create or replace function public.project_tasks_ms_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.milestone_id is not null and not exists(select 1 from public.project_milestones where id = new.milestone_id and project_id = new.project_id) then
    raise exception 'المرحلة غير موجودة في هذا المشروع'; end if;
  if new.start_date is not null and new.due_date is not null and new.due_date < new.start_date then raise exception 'تاريخ التسليم بعد تاريخ البداية'; end if;
  return new;
end $$;
drop trigger if exists project_tasks_ms_guard on public.project_tasks;
create trigger project_tasks_ms_guard before insert or update on public.project_tasks for each row execute function public.project_tasks_ms_guard();

do $$ declare t text;
begin
  foreach t in array array['project_members','project_milestones'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_all', t);
    execute format('create policy %I on public.%I for all using (public.proj_can(company_id)) with check (public.proj_can(company_id))', t || '_all', t);
    execute format('drop policy if exists proj_module on public.%I', t);
    execute format('create policy proj_module on public.%I as restrictive for all using (public.module_on(company_id, %L)) with check (public.module_on(company_id, %L))', t, 'proj', 'proj');
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

-- progress: actual (weights × milestone progress) and planned (weights × share of the milestone's dates already passed)
create or replace function public.project_progress(p_project uuid) returns jsonb language sql stable security definer set search_path = public as $$
  with m as (
    select ms.weight w,
      coalesce((select round(100.0 * count(*) filter (where t.status = 'done') / nullif(count(*), 0)) from public.project_tasks t where t.milestone_id = ms.id), ms.progress) act,
      case when ms.start_date is null or ms.end_date is null then null
           when current_date < ms.start_date then 0 when current_date >= ms.end_date then 100
           else round(100.0 * (current_date - ms.start_date) / greatest(ms.end_date - ms.start_date, 1)) end pl
    from public.project_milestones ms where ms.project_id = p_project)
  select jsonb_build_object('actual', case when sum(w) > 0 then round(sum(w * act) / sum(w), 1) end,
    'planned', case when sum(w) filter (where pl is not null) > 0 then round(sum(w * pl) filter (where pl is not null) / sum(w) filter (where pl is not null), 1) end,
    'weights', coalesce(sum(w), 0)) from m
$$;

-- ---------------- timesheets: employee self-service and approval ----------------
alter table public.timesheets
  add column if not exists status text not null default 'approved' check (status in ('submitted','approved','rejected')),
  add column if not exists reviewed_by uuid, add column if not exists reviewed_at timestamptz,
  add column if not exists reject_note text check (reject_note is null or length(reject_note) <= 300),
  add column if not exists invoice_id uuid references public.sales_invoices(id) on delete set null,
  add column if not exists cost numeric(12,2),
  add column if not exists cost_entry uuid references public.journal_entries(id) on delete set null;
drop policy if exists timesheets_mine on public.timesheets;
create policy timesheets_mine on public.timesheets for select using (employee_id = public.my_employee(company_id));
-- invoiced or costed hours are final
create or replace function public.timesheets_lock() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (old.invoice_id is not null or old.cost_entry is not null) and (tg_op = 'DELETE' or (new.hours, new.work_date, new.employee_id, new.project_id, new.billable)
       is distinct from (old.hours, old.work_date, old.employee_id, old.project_id, old.billable)) then
    raise exception 'الساعات مفوترة أو محمّلة على تكلفة المشروع ولا تُعدّل'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
drop trigger if exists timesheets_lock on public.timesheets;
create trigger timesheets_lock before update or delete on public.timesheets for each row execute function public.timesheets_lock();

-- the projects an employee may log time on: he is on the team, the manager, or has a task there
create or replace function public.my_time_projects(p_company uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company);
begin
  if me is null or not public.module_on(p_company, 'proj') then return '[]'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'no', p.no, 'name', p.name, 'billable', p.billing <> 'internal', 'manager', p.manager_id = me,
      'tasks', coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title) order by t.created_at) from public.project_tasks t where t.project_id = p.id and t.status <> 'done'), '[]'))
      order by p.no)
    from public.projects p where p.company_id = p_company and p.status = 'active'
      and (p.manager_id = me or exists(select 1 from public.project_members m where m.project_id = p.id and m.employee_id = me)
           or exists(select 1 from public.project_tasks t where t.project_id = p.id and t.assignee_id = me))), '[]');
end $$;
create or replace function public.timesheet_submit(p_company uuid, p_doc jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company); pid uuid := (p_doc->>'project')::uuid; tid uuid := nullif(p_doc->>'task', '')::uuid; nid uuid;
begin
  if me is null then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if not exists(select 1 from jsonb_array_elements(public.my_time_projects(p_company)) x where (x->>'id')::uuid = pid) then raise exception 'لست ضمن فريق هذا المشروع'; end if;
  if (p_doc->>'hours')::numeric is null or (p_doc->>'hours')::numeric <= 0 or (p_doc->>'hours')::numeric > 24 then raise exception 'عدد الساعات بين 0 و24'; end if;
  if (select coalesce(sum(hours), 0) from public.timesheets where employee_id = me and work_date = (p_doc->>'date')::date and status <> 'rejected') + (p_doc->>'hours')::numeric > 24 then
    raise exception 'مجموع ساعات اليوم يتجاوز 24'; end if;
  insert into public.timesheets(company_id, project_id, task_id, employee_id, work_date, hours, billable, note, status)
  values (p_company, pid, tid, me, (p_doc->>'date')::date, round((p_doc->>'hours')::numeric, 2),
          (select billing <> 'internal' from public.projects where id = pid) and coalesce((p_doc->>'billable')::boolean, true),
          nullif(btrim(p_doc->>'note'), ''), 'submitted') returning id into nid;
  return nid;
end $$;
create or replace function public.timesheet_withdraw(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare t public.timesheets;
begin
  select * into t from public.timesheets where id = p_id;
  if not found or t.employee_id is distinct from public.my_employee(t.company_id) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if t.status = 'approved' then raise exception 'اعتُمدت الساعات ولا تُسحب'; end if;
  delete from public.timesheets where id = p_id;
end $$;
-- hours waiting for me: all of them for whoever runs projects, else those of the projects I manage
create or replace function public.timesheets_pending(p_company uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company); al boolean := public.proj_can(p_company);
begin
  if not al and me is null then return '[]'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', t.id, 'date', t.work_date, 'hours', t.hours, 'billable', t.billable, 'note', t.note,
      'employee', e.full_name, 'employee_en', e.full_name_en, 'project', p.name, 'project_id', p.id, 'task', k.title) order by t.work_date, e.full_name)
    from public.timesheets t join public.projects p on p.id = t.project_id join public.employees e on e.id = t.employee_id
    left join public.project_tasks k on k.id = t.task_id
    where t.company_id = p_company and t.status = 'submitted' and (al or p.manager_id = me) and t.employee_id is distinct from me), '[]');
end $$;
create or replace function public.timesheet_review(p_ids uuid[], p_ok boolean, p_note text) returns int language plpgsql security definer set search_path = public as $$
declare t public.timesheets; n int := 0;
begin
  if not p_ok and nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'اكتب سبب الرفض'; end if;
  for t in select * from public.timesheets where id = any(p_ids) for update loop
    if t.status <> 'submitted' then continue; end if;
    if not (public.proj_can(t.company_id) or exists(select 1 from public.projects where id = t.project_id and manager_id = public.my_employee(t.company_id))) then
      raise exception 'غير مصرح' using errcode = '42501'; end if;
    if t.employee_id = public.my_employee(t.company_id) and not public.has_role(t.company_id, array['owner']) then raise exception 'لا يعتمد الموظف ساعاته بنفسه'; end if;
    update public.timesheets set status = case when p_ok then 'approved' else 'rejected' end, reviewed_by = auth.uid(), reviewed_at = now(),
      reject_note = case when p_ok then null else btrim(p_note) end where id = t.id;
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------- money: hourly cost, labor cost posting, hours to invoice ----------------
create or replace function public.emp_hour_cost(p_emp uuid, p_date date) returns numeric language sql stable security definer set search_path = public as $$
  select round((public.gross_wage(e) + public.gosi_employer(e.is_saudi, e.basic, e.housing, public.gosi_is_new(e.gosi_new, e.hire_date), coalesce(p_date, current_date))) / 240.0, 4)
  from public.employees e where e.id = p_emp
$$;
-- approved hours not yet costed, up to a date: one entry per project, Dr 5200 (project) / Cr 5200 (the employee's own center)
create or replace function public.project_labor_post(p_company uuid, p_through date) returns int language plpgsql security definer set search_path = public as $$
declare p record; ls jsonb; jid uuid; n int := 0;
begin
  perform public.require_fin(p_company, 'jepost');
  if not public.module_on(p_company, 'finance') then raise exception 'قسم المالية غير مفعّل'; end if;
  update public.timesheets t set cost = round(t.hours * public.emp_hour_cost(t.employee_id, t.work_date), 2)
   where t.company_id = p_company and t.status = 'approved' and t.cost_entry is null and t.work_date <= p_through;
  for p in select pr.id, pr.no, pr.name, public.project_cc(pr.id) cc from public.projects pr
            where pr.company_id = p_company and exists(select 1 from public.timesheets t where t.project_id = pr.id and t.status = 'approved' and t.cost_entry is null and t.work_date <= p_through and t.cost > 0) loop
    select jsonb_build_array(jsonb_build_object('a', '5200', 'd', sum(t.cost), 'cc', p.cc)) ||
           (select jsonb_agg(jsonb_build_object('a', '5200', 'c', x.s, 'cc', x.cc)) from (select e.cost_center_id cc, sum(t2.cost) s from public.timesheets t2 join public.employees e on e.id = t2.employee_id
              where t2.project_id = p.id and t2.status = 'approved' and t2.cost_entry is null and t2.work_date <= p_through and t2.cost > 0 group by e.cost_center_id) x)
      into ls from public.timesheets t where t.project_id = p.id and t.status = 'approved' and t.cost_entry is null and t.work_date <= p_through and t.cost > 0;
    jid := public.post_journal(p_company, p_through, 'تكلفة ساعات العمل — ' || p.no || ' ' || p.name, 'project', p.id, ls);
    update public.timesheets set cost_entry = jid where project_id = p.id and status = 'approved' and cost_entry is null and work_date <= p_through and cost > 0;
    n := n + 1;
  end loop;
  return n;
end $$;
-- approved billable hours not yet invoiced → one sales invoice on the project's cost center
create or replace function public.project_invoice_hours(p_project uuid, p_through date) returns uuid language plpgsql security definer set search_path = public as $$
declare p public.projects; itm uuid; ls jsonb; iid uuid;
begin
  select * into p from public.projects where id = p_project;
  if not found then raise exception 'المشروع غير موجود'; end if;
  perform public.require_fin(p.company_id, 'sales');
  if p.billing <> 'hourly' then raise exception 'الفوترة بالساعات للمشاريع بالساعة فقط'; end if;
  if p.party_id is null then raise exception 'حدّد عميل المشروع أولاً'; end if;
  insert into public.items(company_id, code, name, type, unit) values (p.company_id, 'PRJ-HRS', 'ساعات عمل على المشاريع', 'service', 'ساعة') on conflict (company_id, code) do nothing;
  select id into itm from public.items where company_id = p.company_id and code = 'PRJ-HRS';
  select jsonb_agg(jsonb_build_object('item', itm, 'qty', x.h, 'price', x.r)) into ls from (
    select coalesce(m.rate, p.hourly_rate) r, sum(t.hours) h from public.timesheets t left join public.project_members m on m.project_id = t.project_id and m.employee_id = t.employee_id
     where t.project_id = p.id and t.status = 'approved' and t.billable and t.invoice_id is null and t.work_date <= p_through
     group by 1 having coalesce(m.rate, p.hourly_rate) > 0) x;
  if ls is null then raise exception 'لا توجد ساعات معتمدة غير مفوترة'; end if;
  iid := public.post_sales_invoice_wh(p.company_id, jsonb_build_object('party', p.party_id, 'date', least(p_through, current_date), 'lines', ls,
           'cost_center', public.project_cc(p.id), 'note', 'ساعات عمل — ' || p.no || ' ' || p.name || ' حتى ' || p_through));
  update public.timesheets t set invoice_id = iid where t.project_id = p.id and t.status = 'approved' and t.billable and t.invoice_id is null and t.work_date <= p_through
    and coalesce((select m.rate from public.project_members m where m.project_id = t.project_id and m.employee_id = t.employee_id), p.hourly_rate) > 0;
  return iid;
end $$;

-- ---------------- materials from stock to a project: Dr 5120 / Cr 1300 ----------------
create or replace function public.stock_issue_project(p_project uuid, p_doc jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare p public.projects; it public.items; st record; q numeric := (p_doc->>'qty')::numeric; v numeric; aid uuid := gen_random_uuid(); w uuid; d date := coalesce(nullif(p_doc->>'date', '')::date, current_date);
begin
  select * into p from public.projects where id = p_project;
  if not found then raise exception 'المشروع غير موجود'; end if;
  perform public.require_fin(p.company_id, 'stock');
  select * into it from public.items where id = (p_doc->>'item')::uuid and company_id = p.company_id and type = 'stock';
  if not found then raise exception 'الصنف غير موجود أو ليس مخزنياً'; end if;
  if q is null or q <= 0 then raise exception 'أدخل الكمية'; end if;
  if d > current_date then raise exception 'التاريخ لا يكون في المستقبل'; end if;
  w := public.wh_use(p.company_id, p_doc->>'warehouse');
  if public.wh_qty(it.id, w) < q then raise exception 'الكمية أكبر من الرصيد المتوفر في المستودع (%)', public.wh_qty(it.id, w); end if;
  select * into st from public.stock_state(it.id);
  v := case when st.qty = q then st.value else round(q * st.avg_cost, 2) end;
  insert into public.stock_moves(company_id, item_id, warehouse_id, date, qty, value, source, source_id, note)
  values (p.company_id, it.id, w, d, -q, -v, 'adjust', aid, 'صرف للمشروع ' || p.no || coalesce(' — ' || nullif(btrim(p_doc->>'note'), ''), ''));
  insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header)
    values (p.company_id, '5120', 'مواد مصروفة على المشاريع', 'Materials used on projects', 'exp', '5000', false) on conflict do nothing;
  perform public.post_journal(p.company_id, d, 'صرف مواد للمشروع ' || p.no || ' — ' || it.name, 'stock', aid,
    jsonb_build_array(jsonb_build_object('a', '5120', 'd', v, 'cc', public.project_cc(p.id)), jsonb_build_object('a', '1300', 'c', v)));
  return aid;
end $$;

-- ---------------- purchase orders and petty cash carry a cost center (the project's) ----------------
alter table public.purchase_orders add column if not exists cost_center_id uuid references public.cost_centers(id) on delete set null;
alter table public.petty_claims add column if not exists cost_center_id uuid references public.cost_centers(id) on delete set null;
create or replace function public.po_save_wh(p_company uuid, p_doc jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare oid uuid; c uuid;
begin
  perform public.wh_use(p_company, p_doc->>'warehouse');
  c := public.cc_use(p_company, p_doc->>'cost_center');
  oid := public.po_save(p_company, p_doc);
  update public.purchase_orders set cost_center_id = c where id = oid and cost_center_id is distinct from c;
  return oid;
end $$;
create or replace function public.petty_claim_set_cc(p_id uuid, p_cc uuid) returns void language plpgsql security definer set search_path = public as $$
declare c public.petty_claims;
begin
  select * into c from public.petty_claims where id = p_id;
  if not found then raise exception 'التسوية غير موجودة'; end if;
  perform public.require_fin(c.company_id, 'je');
  if c.status <> 'pending' then raise exception 'تمت معالجة هذه التسوية'; end if;
  perform public.cc_use(c.company_id, p_cc::text);
  update public.petty_claims set cost_center_id = p_cc where id = p_id;
end $$;

CREATE OR REPLACE FUNCTION public.po_bill(p_order uuid, p_doc jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.purchase_orders; l jsonb; ol public.purchase_order_lines; it public.items; q numeric; cap numeric; amt numeric; vt numeric; acc text;
  bid uuid; no text; sub numeric := 0; v_vat numeric := 0; dr jsonb := '{}'; jl jsonb := '[]'; k text; n int := 0;
  d date := coalesce((p_doc->>'date')::date, current_date); ref text := nullif(trim(p_doc->>'ref'), '');
begin
  select * into o from public.purchase_orders where id = p_order for update;
  if not found then raise exception 'الأمر غير موجود'; end if;
  perform public.require_fin(o.company_id, 'purch');
  if o.status <> 'open' then raise exception 'الأمر ليس مفتوحاً'; end if;
  perform public.cc_use(o.company_id, o.cost_center_id::text);   -- the order's project / cost center (0123)
  if d > current_date then raise exception 'تاريخ الفاتورة لا يكون في المستقبل'; end if;
  if (p_doc->>'due') is not null and (p_doc->>'due')::date < d then raise exception 'تاريخ الاستحقاق قبل تاريخ الفاتورة'; end if;
  if ref is not null and exists(select 1 from public.purchase_bills where company_id = o.company_id and party_id = o.party_id and supplier_ref = ref and status = 'posted') then
    raise exception 'رقم فاتورة المورد مسجّل مسبقاً'; end if;
  no := public.next_doc_no(o.company_id, 'BIL');
  insert into public.purchase_bills(company_id, no, supplier_ref, date, due_date, party_id, subtotal, vat, total, note, order_id, cost_center_id)
  values (o.company_id, no, ref, d, coalesce((p_doc->>'due')::date, d), o.party_id, 0, 0, 0, 'أمر شراء ' || o.no, o.id, o.cost_center_id) returning id into bid;
  for ol in select * from public.purchase_order_lines where order_id = o.id order by id for update loop
    if p_doc ? 'lines' then
      l := null; select x.value into l from jsonb_array_elements(p_doc->'lines') x where (x.value->>'line')::bigint = ol.id limit 1;
      q := case when l is null then 0 else (l->>'qty')::numeric end;
    else q := null; end if;
    it := null; if ol.item_id is not null then select * into it from public.items where id = ol.item_id; end if;
    -- three-way match: stock lines up to what was received, others up to what was ordered
    cap := case when it.type = 'stock' then ol.received - ol.billed else ol.qty - ol.billed end;
    q := coalesce(q, greatest(cap, 0));
    continue when q = 0;
    if q < 0 then raise exception 'الكمية لا تكون سالبة'; end if;
    if q > cap then raise exception '«%»: الكمية القابلة للفوترة % (%)', coalesce(it.name, ol.account_code), greatest(cap, 0),
      case when it.type = 'stock' then 'المستلم ناقص المفوتر' else 'المطلوب ناقص المفوتر' end; end if;
    amt := case when q = ol.qty then ol.amount else round(q * ol.unit_price, 2) end; vt := round(amt * ol.vat_rate / 100, 2);
    acc := case when it.type = 'stock' then '2150' when it.id is not null then '5500' else ol.account_code end;
    insert into public.purchase_bill_lines(bill_id, item_id, account_code, qty, unit_price, vat_rate, amount, vat, order_line)
    values (bid, ol.item_id, case when ol.item_id is null then ol.account_code end, q, ol.unit_price, ol.vat_rate, amt, vt, ol.id);
    update public.purchase_order_lines set billed = billed + q where id = ol.id;
    dr := jsonb_set(dr, array[acc], to_jsonb(coalesce((dr->>acc)::numeric, 0) + amt));
    sub := sub + amt; v_vat := v_vat + vt; n := n + 1;
  end loop;
  if n = 0 then raise exception 'لا يوجد ما يُفوتر — استلم البضاعة أولاً'; end if;
  update public.purchase_bills set subtotal = sub, vat = v_vat, total = sub + v_vat where id = bid;
  for k in select jsonb_object_keys(dr) loop jl := jl || jsonb_build_array(jsonb_build_object('a', k, 'd', (dr->>k)::numeric)); end loop;
  jl := jl || jsonb_build_array(jsonb_build_object('a','1400','d',v_vat), jsonb_build_object('a','2100','c',sub + v_vat));
  perform public.ensure_grni(o.company_id);
  perform public.post_journal(o.company_id, d, 'فاتورة مشتريات ' || no || ' — أمر ' || o.no, 'purchase', bid, jl);
  if not exists(select 1 from public.purchase_order_lines where order_id = o.id and billed < qty) then
    update public.purchase_orders set status = 'closed', updated_at = now() where id = o.id; end if;
  return bid;
end $function$;

CREATE OR REPLACE FUNCTION public.petty_claim_decide(p_id uuid, p_approve boolean, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.petty_claims; f public.petty_funds; jl jsonb; eid uuid; emp text;
begin
  select * into c from public.petty_claims where id = p_id for update;
  if not found then raise exception 'التسوية غير موجودة'; end if;
  perform public.require_fin(c.company_id, 'je');
  if c.status <> 'pending' then raise exception 'تمت معالجة هذه التسوية'; end if;
  select * into f from public.petty_funds where id = c.fund_id;
  if not p_approve then
    if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'اكتب سبب الرفض'; end if;
    update public.petty_claims set status = 'rejected', reason = trim(p_reason), decided_by = auth.uid(), decided_at = now() where id = p_id;
    return;
  end if;
  if c.total > public.petty_balance(f.id) + 0.004 then raise exception 'المصروف (%) أكبر من رصيد العهدة (%) — عزّز العهدة أولاً', c.total, public.petty_balance(f.id); end if;
  select full_name into emp from public.employees where id = f.employee_id;
  select jsonb_agg(jsonb_build_object('a', x.a, 'd', x.s)) into jl from (select l->>'a' a, sum((l->>'amount')::numeric) s from jsonb_array_elements(c.lines) l group by 1) x;
  if c.vat > 0 then jl := jl || jsonb_build_array(jsonb_build_object('a','1400','d', c.vat)); end if;
  jl := jl || jsonb_build_array(jsonb_build_object('a', f.account_code, 'c', c.total));
  perform public.cc_use(c.company_id, c.cost_center_id::text);   -- the claim's project / cost center (0123)
  eid := public.post_journal(c.company_id, c.date, 'تسوية عهدة ' || c.no || ' — ' || emp, 'petty', c.id, jl);
  update public.petty_claims set status = 'approved', entry_id = eid, decided_by = auth.uid(), decided_at = now() where id = p_id;
end $function$;

-- ---------------- profitability ----------------
create or replace function public.project_pnl(p_company uuid) returns table(project_id uuid, contract numeric, invoiced numeric, collected numeric, revenue numeric,
  cost numeric, cost_budget numeric, unposted_labor numeric, hours numeric, progress jsonb, eac numeric, margin numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_proj(p_company);
  return query
  with b as (
    select p.id, p.cost_center_id cc, p.billing, p.contract_value, p.cost_budget, public.project_progress(p.id) pg from public.projects p where p.company_id = p_company),
  g as (
    select b.id, coalesce(sum(l.credit - l.debit) filter (where a.type = 'rev'), 0) rv, coalesce(sum(l.debit - l.credit) filter (where a.type = 'exp'), 0) ex
      from b left join public.journal_lines l on l.company_id = p_company and l.cost_center_id = b.cc
      left join public.accounts a on a.company_id = l.company_id and a.code = l.account_code group by b.id),
  s as (
    select b.id, coalesce(sum(i.subtotal), 0) inv, coalesce(sum(least(public.paid_on(i.id), i.total)), 0) col
      from b left join public.sales_invoices i on i.company_id = p_company and i.cost_center_id = b.cc and i.status = 'posted' group by b.id),
  h as (
    select b.id, coalesce(sum(t.hours), 0) hrs,
           coalesce(sum(t.hours * public.emp_hour_cost(t.employee_id, t.work_date)) filter (where t.status = 'approved' and t.cost_entry is null), 0) un
      from b left join public.timesheets t on t.project_id = b.id group by b.id)
  select b.id, case when b.billing = 'fixed' then b.contract_value else coalesce(b.contract_value, s.inv) end, s.inv, s.col, g.rv,
         round(g.ex, 2), b.cost_budget, round(h.un, 2), h.hrs, b.pg,
         -- estimate at completion: actual cost ÷ % complete, never below the actual
         case when coalesce((b.pg->>'actual')::numeric, 0) > 0 then round(greatest(g.ex + h.un, (g.ex + h.un) * 100 / (b.pg->>'actual')::numeric), 2) else b.cost_budget end,
         round(case when b.billing = 'fixed' then b.contract_value else coalesce(b.contract_value, s.inv) end
           - case when coalesce((b.pg->>'actual')::numeric, 0) > 0 then greatest(g.ex + h.un, (g.ex + h.un) * 100 / (b.pg->>'actual')::numeric) else coalesce(b.cost_budget, g.ex + h.un) end, 2)
    from b join g on g.id = b.id join s on s.id = b.id join h on h.id = b.id;
end $$;

revoke all on function public.projects_more_guard(), public.projects_cc_after(), public.project_part_guard(), public.project_tasks_ms_guard(), public.timesheets_lock(),
  public.project_cc(uuid), public.emp_hour_cost(uuid, date) from public, anon, authenticated;
revoke all on function public.project_progress(uuid), public.my_time_projects(uuid), public.timesheet_submit(uuid, jsonb), public.timesheet_withdraw(uuid),
  public.timesheets_pending(uuid), public.timesheet_review(uuid[], boolean, text), public.project_labor_post(uuid, date), public.project_invoice_hours(uuid, date),
  public.stock_issue_project(uuid, jsonb), public.petty_claim_set_cc(uuid, uuid), public.project_pnl(uuid) from public, anon;
grant execute on function public.my_time_projects(uuid), public.timesheet_submit(uuid, jsonb), public.timesheet_withdraw(uuid),
  public.timesheets_pending(uuid), public.timesheet_review(uuid[], boolean, text), public.project_labor_post(uuid, date), public.project_invoice_hours(uuid, date),
  public.stock_issue_project(uuid, jsonb), public.petty_claim_set_cc(uuid, uuid), public.project_pnl(uuid) to authenticated;
