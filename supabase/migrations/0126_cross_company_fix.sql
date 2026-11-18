-- 0126 — security fix from the full project review (2026-11-18): no access across companies.
-- 1. A permission test such as "not (x = my_employee(c) or ...)" is NULL, and so passes, for a signed-in user with no employee
--    record in that company. Every such test now treats "unknown" as "no".
-- 2. Internal helpers that took a company or record id without checking the caller are no longer callable from the app;
--    the functions that use them run with their owner's rights and are unaffected.
-- 3. The per-diem rate is only for people of the employee's own company.

CREATE OR REPLACE FUNCTION public.annual_leave_balance(p_emp uuid, p_as_of date DEFAULT CURRENT_DATE)
 RETURNS TABLE(accrued numeric, taken numeric, balance numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.employees; x record;
begin
  select * into e from public.employees where id = p_emp;
  if not found then return; end if;
  if not coalesce((p_emp = public.my_employee(e.company_id) or (public.has_role(e.company_id, array['owner','admin','hr','finance']) or public.fin_can(e.company_id, 'hr_emp'))
          or e.manager_id = public.my_employee(e.company_id)), false) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  select * into x from public.annual_leave_raw(e, p_as_of);
  return query select round(x.accrued, 2), x.taken, round(x.accrued - x.taken, 2);
end $function$;

CREATE OR REPLACE FUNCTION public.request_attach(p_id uuid, p_files jsonb, p_ref text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.requests; n int := 0; v text := upper(left(regexp_replace(coalesce(p_ref, ''), '\s', '', 'g'), 40));
begin
  select * into r from public.requests where id = p_id;
  if not found then raise exception 'الطلب غير موجود'; end if;
  if not coalesce((public.has_role(r.company_id, array['owner','admin','hr']) or (r.employee_id = public.my_employee(r.company_id) and r.status = 'pending')), false) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  if (p_files is null or jsonb_typeof(p_files) <> 'array' or jsonb_array_length(p_files) = 0) and v = '' then raise exception 'اختر ملفاً'; end if;
  if p_files is not null and jsonb_typeof(p_files) = 'array' and jsonb_array_length(p_files) > 0 then n := public.attach_files(p_id, p_files); end if;
  if v <> '' then update public.requests set payload = payload || jsonb_build_object('doc_ref', v) where id = p_id; end if;
  insert into public.request_actions(request_id, actor, action, note) values (p_id, auth.uid(), 'attached', case when n > 0 then n || ' مرفق' else 'رقم المستند ' || v end);
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.ticket_status(p_emp uuid, p_on date DEFAULT NULL::date)
 RETURNS TABLE(every integer, persons integer, ticket_class text, dest text, dest_en text, amount numeric, earned integer, used integer, available integer, next_due date)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.employees; m int; d date := coalesce(p_on, current_date); u int;
begin
  select * into e from public.employees where id = p_emp;
  if not found then return; end if;
  if not coalesce((e.id = public.my_employee(e.company_id) or public.has_role(e.company_id, array['owner','admin','hr','finance'])), false) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  if e.ticket_every is null then return; end if;
  m := (extract(year from age(d, e.hire_date)) * 12 + extract(month from age(d, e.hire_date)))::int;
  select count(*) into u from public.travel_tickets t where t.employee_id = p_emp and t.status <> 'cancelled';
  u := u + (select count(*) from public.requests q where q.employee_id = p_emp and q.status = 'pending'
              and ((q.kind = 'ticket') or (q.kind = 'leave' and q.payload ? 'ticket')))::int;
  return query select e.ticket_every, e.ticket_persons, e.ticket_class, e.ticket_dest, e.ticket_dest_en, e.ticket_amount,
    greatest(m / e.ticket_every, 0), u, greatest(m / e.ticket_every - u, 0),
    (e.hire_date + make_interval(months => (u + 1) * e.ticket_every))::date;
end $function$;

CREATE OR REPLACE FUNCTION public.request_timeline(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.requests; me uuid; sla int; i int; st text; a record; nm text; nm_en text; steps jsonb := '[]'; state text;
begin
  select * into r from public.requests where id = p_id;
  if not found then raise exception 'الطلب غير موجود'; end if;
  me := public.my_employee(r.company_id);
  if not coalesce((r.employee_id = me or public.has_role(r.company_id, array['owner','admin','hr','finance'])
          or exists(select 1 from public.employees e where e.id = r.employee_id and e.manager_id = me and me is not null)
          or exists(select 1 from public.companies c where c.id = r.company_id and c.hr_manager = auth.uid())), false) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  select request_sla_days into sla from public.companies where id = r.company_id;
  for i in 1 .. coalesce(cardinality(r.route), 0) loop
    st := r.route[i];
    select x.actor, x.action, x.at, x.note into a from public.request_actions x
     where x.request_id = p_id and x.actor_step = st and x.action in ('approved','rejected') order by x.at desc limit 1;
    nm := null; nm_en := null;
    if a.actor is not null then
      select e.full_name, e.full_name_en into nm, nm_en from public.members mb join public.employees e on e.id = mb.employee_id
       where mb.company_id = r.company_id and mb.user_id = a.actor;
    end if;
    state := case when i <= r.step then 'done'
                  when i = r.step + 1 and r.status = 'pending' then 'current'
                  when i = r.step + 1 and r.status = 'rejected' then 'rejected'
                  when i = r.step + 1 and r.status = 'cancelled' then 'cancelled'
                  when r.status in ('rejected','cancelled') then 'skipped' else 'waiting' end;
    steps := steps || jsonb_build_object('step', st, 'state', state,
      'by', case when state in ('done','rejected') then coalesce(nm, '—') end, 'by_en', case when state in ('done','rejected') then nm_en end,
      'at', case when state in ('done','rejected') then a.at end, 'note', case when state in ('done','rejected') then a.note end,
      'since', case when state = 'current' then r.step_at end,
      'hours', case when state = 'current' then round(extract(epoch from now() - r.step_at) / 3600) end,
      'overdue', state = 'current' and sla is not null and now() - r.step_at > make_interval(days => sla));
  end loop;
  return jsonb_build_object('status', r.status, 'submitted_at', r.created_at, 'decided_at', r.decided_at, 'sla_days', sla, 'steps', steps,
    'ticket', (select to_jsonb(t) - 'entry_id' || jsonb_build_object('paid', t.entry_id is not null, 'files', public.travel_file_list(t.id, null))
               from public.travel_tickets t where t.request_id = p_id limit 1),
    'visa', (select to_jsonb(v) || jsonb_build_object('files', public.travel_file_list(null, v.id)) from public.exit_visas v where v.request_id = p_id limit 1));
end $function$;

CREATE OR REPLACE FUNCTION public.okr_progress(p_kr uuid, p_value numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare k public.okr_key_results; o public.okr_objectives;
begin
  select * into k from public.okr_key_results where id = p_kr;
  if not found then raise exception 'النتيجة غير موجودة'; end if;
  select * into o from public.okr_objectives where id = k.objective_id;
  if not coalesce((public.okr_can_manage(o.company_id, o.employee_id) or (o.employee_id is not null and o.employee_id = public.my_employee(o.company_id))), false) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_value is null then raise exception 'أدخل القيمة الحالية'; end if;
  update public.okr_key_results set current = p_value, updated_at = now() where id = p_kr;
end $function$;

CREATE OR REPLACE FUNCTION public.feedback_request(p_cycle uuid, p_employee uuid, p_raters uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.review_cycles; e public.employees; r uuid; n int := 0;
begin
  select * into c from public.review_cycles where id = p_cycle;
  select * into e from public.employees where id = p_employee and company_id = c.company_id;
  if c.id is null or e.id is null then raise exception 'غير موجود'; end if;
  if not coalesce((public.has_role(c.company_id, array['owner','admin','hr']) or e.manager_id = public.my_employee(c.company_id)), false) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if c.status <> 'open' then raise exception 'الدورة مغلقة'; end if;
  insert into public.review_feedback(company_id, cycle_id, employee_id, rater_id, kind) values (c.company_id, p_cycle, p_employee, p_employee, 'self') on conflict do nothing;
  get diagnostics n = row_count;
  foreach r in array coalesce(p_raters, '{}') loop
    if r = p_employee or not exists(select 1 from public.employees x where x.id = r and x.company_id = c.company_id and (x.end_date is null or x.end_date >= current_date)) then continue; end if;
    insert into public.review_feedback(company_id, cycle_id, employee_id, rater_id, kind)
    values (c.company_id, p_cycle, p_employee, r, case when exists(select 1 from public.employees x where x.id = r and x.manager_id = p_employee) then 'report' else 'peer' end)
    on conflict do nothing;
    if found then n := n + 1; end if;
  end loop;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION public.feedback_summary(p_cycle uuid, p_employee uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.employees;
begin
  select * into e from public.employees where id = p_employee;
  if e.id is null or not coalesce((public.has_role(e.company_id, array['owner','admin','hr']) or e.manager_id = public.my_employee(e.company_id)), false) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return coalesce((select jsonb_object_agg(g.kind, g.v) from (
    select f.kind, jsonb_build_object('asked', count(*), 'done', count(f.submitted_at),
      'avg', case when f.kind = 'self' or count(f.submitted_at) >= 2 then (select jsonb_object_agg(q.k, q.a) from (select k, round(avg((x.scores->>k)::numeric), 2) a
                  from public.review_feedback x cross join unnest(array['c1','c2','c3','c4','c5']) k
                  where x.cycle_id = p_cycle and x.employee_id = p_employee and x.kind = f.kind and x.submitted_at is not null group by k) q) end,
      'comments', case when f.kind = 'self' or count(f.submitted_at) >= 2 then coalesce(jsonb_agg(f.comment order by random()) filter (where f.comment is not null), '[]'::jsonb) else '[]'::jsonb end) v
    from public.review_feedback f where f.cycle_id = p_cycle and f.employee_id = p_employee group by f.kind) g), '{}'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.request_budget(p_request uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.requests; e public.employees; amt numeric;
begin
  select * into r from public.requests where id = p_request;
  if not found or r.kind not in ('expense','purchase','trip','ticket') then return null; end if;
  select * into e from public.employees where id = r.employee_id;
  if not coalesce((public.fin_can(r.company_id, 'reports') or public.has_role(r.company_id, array['owner','admin','hr','finance'])
          or (e.manager_id is not null and e.manager_id = public.my_employee(r.company_id))), false) then return null; end if;
  amt := coalesce(r.amount, (select sum(coalesce((x->>'qty')::numeric, 0) * coalesce((x->>'price')::numeric, 0)) from jsonb_array_elements(coalesce(r.payload->'lines', '[]')) x), 0);
  return public.budget_position(r.company_id, e.cost_center_id, public.request_budget_account(r.kind), amt, coalesce(r.from_date, current_date))
    || jsonb_build_object('block', (select budget_block from public.companies where id = r.company_id));
end $function$;

create or replace function public.per_diem_rate(p_emp uuid, p_abroad boolean) returns numeric
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; g public.job_grades; c public.companies;
begin
  select * into e from public.employees where id = p_emp;
  if not found then return null; end if;
  if auth.uid() is not null and not public.is_member(e.company_id) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  select * into c from public.companies where id = e.company_id;
  select * into g from public.job_grades where id = e.grade_id;
  return coalesce(case when p_abroad then g.per_diem_out else g.per_diem_in end, case when p_abroad then c.per_diem_out else c.per_diem_in end, 0);
end $$;

create or replace function public.training_company(p_training uuid) returns uuid language sql stable security definer set search_path = public as $$
  select company_id from public.trainings where id = p_training and public.is_member(company_id)
$$;

revoke all on function public.budget_check_lines(uuid, date, jsonb), public.budget_guard_lines(uuid, date, jsonb),
  public.claim_figures(uuid, text, jsonb, numeric, uuid), public.fin2_accounts(uuid), public.jd_check(uuid, jsonb),
  public.month_close_loans(uuid, date), public.po_budget_lines(uuid), public.project_progress(uuid) from public, anon, authenticated;
