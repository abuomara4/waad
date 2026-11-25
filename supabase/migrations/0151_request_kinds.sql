-- Waad ERP — 0151 three request kinds (owner's request, 2026-11-25):
--  * «overtime»: the employee asks for overtime hours before the work (or within 7 days after it). On approval the hours
--    become the day's approved overtime automatically, up to the overtime the attendance actually records; the yearly
--    720-hour cap (0033) is checked when asking. Route m, p.
--  * «remote»: work from home / another place for up to 30 days; on the approved days «حضوري» skips the work-site
--    location check (as att_any_place does for good). Route m, p.
--  * «move»: transfer / promotion / new title / raise, raised about an employee by his direct manager or HR
--    (request_file), never by the employee himself. Department, job title, manager, branch, grade and pay (never lower;
--    within the grade's range). Applied on the final approval; the salary history takes the effective date.
--    Route m (dropped when the manager raised it), p, h, f, g.
-- Clearance (إخلاء الطرف) already exists since 0033 (#/clearance); the employee now sees its progress in «ملفي».

alter table public.requests drop constraint if exists requests_kind_check;
alter table public.requests add constraint requests_kind_check check (kind in ('leave','permit','cert','advance','resign','settle','expense','update','punch','ticket','visa','purchase','trip','overtime','remote','move'));

create or replace function public.default_route(p_kind text) returns text[] language sql immutable as $$
  select case p_kind
    when 'leave' then array['m','p','h','g'] when 'permit' then array['m','p'] when 'cert' then array['p'] when 'punch' then array['m','p']
    when 'advance' then array['m','p','h','f','g'] when 'resign' then array['m','p','h','g','f']
    when 'settle' then array['p','h','f','g'] when 'expense' then array['m','f','g']
    when 'ticket' then array['m','p','h','f'] when 'visa' then array['m','p','h']
    when 'purchase' then array['m','f','g'] when 'trip' then array['m','p','f']
    when 'overtime' then array['m','p'] when 'remote' then array['m','p'] when 'move' then array['m','p','h','f','g']
    else array['p'] end
$$;

CREATE OR REPLACE FUNCTION public.workflow_set(p_company uuid, p_kind text, p_route text[])
 RETURNS text[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rt text[];
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if p_kind not in ('leave','permit','cert','advance','resign','settle','expense','update','punch','ticket','visa','purchase','trip','overtime','remote','move') then raise exception 'نوع طلب غير معروف'; end if;
  if p_route is null then delete from public.workflows where company_id = p_company and kind = p_kind; return public.default_route(p_kind); end if;
  rt := array(select s from unnest(array['m','b','p','h','f','g']) with ordinality x(s, i) where s = any(p_route) order by i);
  if cardinality(rt) = 0 then raise exception 'اختر مرحلة اعتماد واحدة على الأقل'; end if;
  if p_kind in ('ticket','advance','expense','settle','purchase','trip') and not ('f' = any(rt)) then raise exception 'هذا الطلب يصرف مبلغاً فلا بد أن يمر على المالية'; end if;
  if p_kind = 'move' and not ('p' = any(rt)) then raise exception 'طلب النقل أو الترقية يمر على الموارد البشرية'; end if;
  insert into public.workflows(company_id, kind, route) values (p_company, p_kind, rt)
    on conflict (company_id, kind) do update set route = excluded.route;
  return rt;
end $function$;

-- ---------------- overtime asked in advance ----------------
-- the approved overtime hours asked for an employee's day
create or replace function public.ot_preapproved_min(p_emp uuid, p_day date) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(round(sum((payload->>'hours')::numeric) * 60), 0)::int from public.requests
   where employee_id = p_emp and kind = 'overtime' and status = 'approved' and from_date = p_day
$$;
-- when the request is approved after the day was recorded: raise the day's approved overtime (never above what was worked)
create or replace function public.ot_preapproved_apply(p_emp uuid, p_day date) returns void
language plpgsql security definer set search_path = public as $$
declare a public.attendance; v int;
begin
  select * into a from public.attendance where employee_id = p_emp and day = p_day;
  if not found then return; end if;
  if exists(select 1 from public.payroll_runs r where r.company_id = a.company_id and r.status <> 'draft'
            and make_date(r.year, r.month, 1) <= a.day and a.day < make_date(r.year, r.month, 1) + interval '1 month') then return; end if;
  v := least(greatest(a.extra_min - a.ot_comp_min, 0), public.ot_preapproved_min(p_emp, p_day));
  if v > a.ot_min then update public.attendance set ot_min = v where id = a.id; end if;
end $$;
-- when the day is (re)computed after the approval: the same rule inside the row being saved
create or replace function public.attendance_ot_preapproved() returns trigger
language plpgsql security definer set search_path = public as $$
declare v int;
begin
  if tg_op = 'UPDATE' and new.extra_min is not distinct from old.extra_min then return new; end if;
  new.ot_min := least(coalesce(new.ot_min, 0), greatest(coalesce(new.extra_min, 0), 0));
  if coalesce(new.extra_min, 0) <= 0 then return new; end if;
  v := least(greatest(new.extra_min - coalesce(new.ot_comp_min, 0), 0), public.ot_preapproved_min(new.employee_id, new.day));
  if v > new.ot_min then new.ot_min := v; end if;
  return new;
end $$;
drop trigger if exists attendance_ot_preapproved on public.attendance;
create trigger attendance_ot_preapproved before insert or update of extra_min on public.attendance for each row execute function public.attendance_ot_preapproved();

-- ---------------- remote work days ----------------
create or replace function public.remote_on(p_emp uuid, p_day date) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.requests where employee_id = p_emp and kind = 'remote' and status = 'approved' and p_day between from_date and to_date)
$$;
-- for «حضوري»: is today an approved remote day (the page then does not ask for the location)
create or replace function public.my_remote_today(p_company uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company);
begin
  if me is null then raise exception 'حسابك غير مربوط بسجل موظف' using errcode = '42501'; end if;
  return public.remote_on(me, public.riyadh_today());
end $$;

create or replace function public.clock(p_company uuid, p_lat numeric default null, p_lng numeric default null, p_acc numeric default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company); c public.companies; e public.employees; a public.attendance; s public.shifts;
        site uuid; near_name text; near_d numeric; d date := public.riyadh_today(); rid uuid;
begin
  if me is null then raise exception 'حسابك غير مربوط بسجل موظف' using errcode = '42501'; end if;
  select * into c from public.companies where id = p_company;
  if not c.att_enabled then raise exception 'تسجيل الحضور غير مفعّل في منشأتك'; end if;
  select * into e from public.employees where id = me;
  if e.att_exempt then raise exception 'أنت معفى من تسجيل الحضور'; end if;
  if e.end_date is not null and e.end_date < d then raise exception 'انتهت خدمتك'; end if;
  if c.att_geofence and not e.att_any_place and not public.remote_on(me, d) and exists(select 1 from public.work_sites where company_id = p_company) then
    if p_lat is null or p_lng is null then raise exception 'فعّل خدمة الموقع في جوالك ثم أعد المحاولة'; end if;
    if coalesce(p_acc, 0) > 150 then raise exception 'دقة الموقع ضعيفة (± % م) — فعّل GPS أو اقترب من نافذة ثم أعد المحاولة', round(p_acc); end if;
    select id into site from public.work_sites w where w.company_id = p_company and (e.work_site_id is null or w.id = e.work_site_id) and public.geo_dist_m(w.lat, w.lng, p_lat, p_lng) <= w.radius_m + coalesce(p_acc, 0) / 2
     order by public.geo_dist_m(w.lat, w.lng, p_lat, p_lng) limit 1;
    if site is null then
      select name, round(public.geo_dist_m(lat, lng, p_lat, p_lng)) into near_name, near_d from public.work_sites where company_id = p_company and (e.work_site_id is null or id = e.work_site_id) order by public.geo_dist_m(lat, lng, p_lat, p_lng) limit 1;
      raise exception 'أنت خارج نطاق مواقع العمل — أقرب موقع «%» على بعد % م', near_name, near_d;
    end if;
  end if;
  -- an open record from today or a night shift that started yesterday → check out
  select * into a from public.attendance where employee_id = me and check_out is null and check_in > now() - interval '20 hours' order by check_in desc limit 1;
  if found then
    if now() < a.check_in + interval '1 minute' then raise exception 'سجّلت حضورك قبل لحظات'; end if;
    update public.attendance set check_out = now(), out_lat = p_lat, out_lng = p_lng, out_acc = p_acc, out_site = site, updated_by = auth.uid(), updated_at = now() where id = a.id;
    perform public.att_recalc(a.id);
    select * into a from public.attendance where id = a.id;
    return jsonb_build_object('action', 'out', 'at', a.check_out, 'worked_min', a.worked_min, 'early_min', a.early_min, 'extra_min', a.extra_min);
  end if;
  if exists(select 1 from public.attendance where employee_id = me and day = d) then raise exception 'سجّلت الحضور والانصراف لهذا اليوم'; end if;
  s := public.employee_shift_on(me, d);
  insert into public.attendance(company_id, employee_id, day, shift_id, check_in, in_lat, in_lng, in_acc, in_site)
  values (p_company, me, d, s.id, now(), p_lat, p_lng, p_acc, site) returning id into rid;
  perform public.att_recalc(rid);
  select * into a from public.attendance where id = rid;
  return jsonb_build_object('action', 'in', 'at', a.check_in, 'late_min', a.late_min, 'shift', s.name);
end $$;

-- ---------------- transfer / promotion raised by the manager or HR ----------------
-- who may raise one about this employee: HR / owner / admin, or his direct manager (never about oneself)
create or replace function public.request_file_can(p_company uuid, p_emp uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company); e public.employees;
begin
  select * into e from public.employees where id = p_emp and company_id = p_company;
  if not found or e.end_date is not null and e.end_date < current_date then return false; end if;
  if me is not null and e.id = me then return false; end if;
  if not public.emp_branch_ok(p_company, e.id) then return false; end if;
  return public.has_role(p_company, array['owner','admin','hr']) or coalesce(me is not null and e.manager_id = me, false);
end $$;

-- the choices of the form (a manager cannot read the grades, branches or the whole staff list otherwise)
create or replace function public.move_options(p_company uuid, p_emp uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.employees;
begin
  if not public.request_file_can(p_company, p_emp) then raise exception 'يرفع طلب النقل أو الترقية المدير المباشر أو الموارد البشرية' using errcode = '42501'; end if;
  select * into e from public.employees where id = p_emp;
  return jsonb_build_object(
    'current', jsonb_build_object('department_id', e.department_id, 'job_title', e.job_title, 'job_title_en', e.job_title_en, 'manager_id', e.manager_id,
       'branch_id', e.branch_id, 'grade_id', e.grade_id, 'basic', e.basic, 'housing', e.housing, 'transport', e.transport, 'name', e.full_name),
    'departments', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'name', d.name) order by d.name) from public.departments d where d.company_id = p_company), '[]'),
    'grades', coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'name', g.code || ' — ' || g.name, 'min', g.min_basic, 'max', g.max_basic) order by g.code) from public.job_grades g where g.company_id = p_company), '[]'),
    'branches', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.code || ' — ' || b.name) order by b.code) from public.branches b where b.company_id = p_company), '[]'),
    'managers', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'name', m.full_name, 'no', m.emp_no) order by m.full_name) from public.employees m
                  where m.company_id = p_company and m.id <> p_emp and (m.end_date is null or m.end_date >= current_date) and public.emp_branch_ok(p_company, m.id)), '[]'));
end $$;

-- the request about another employee; p_payload holds the new values only (null / missing = unchanged)
create or replace function public.request_file(p_company uuid, p_emp uuid, p_kind text, p_from date, p_payload jsonb, p_note text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company); e public.employees; g public.job_grades; p jsonb := '{}'; o jsonb; rt text[]; hm uuid; owner_emp uuid; rid uuid;
        v_basic numeric; v_housing numeric; v_transport numeric; v_dept uuid; v_mgr uuid; v_br uuid; v_gr uuid; v_job text; v_type text;
begin
  if p_kind <> 'move' then raise exception 'نوع طلب غير معروف'; end if;
  if not public.request_file_can(p_company, p_emp) then raise exception 'يرفع طلب النقل أو الترقية المدير المباشر أو الموارد البشرية' using errcode = '42501'; end if;
  select * into e from public.employees where id = p_emp;
  p_payload := coalesce(p_payload, '{}');
  v_type := coalesce(nullif(p_payload->>'type', ''), 'transfer');
  if v_type not in ('transfer','promotion','title','raise') then raise exception 'نوع الطلب غير صحيح'; end if;
  if p_from is null then raise exception 'حدد تاريخ السريان'; end if;
  if p_from < current_date - 31 or p_from > current_date + 180 then raise exception 'تاريخ السريان خلال شهر مضى أو ستة أشهر قادمة'; end if;
  if exists(select 1 from public.requests where employee_id = p_emp and kind = 'move' and status = 'pending') then raise exception 'يوجد طلب نقل أو ترقية لهذا الموظف قيد الاعتماد'; end if;
  v_dept := nullif(p_payload->>'department_id', '')::uuid; v_mgr := nullif(p_payload->>'manager_id', '')::uuid;
  v_br := nullif(p_payload->>'branch_id', '')::uuid; v_gr := nullif(p_payload->>'grade_id', '')::uuid; v_job := nullif(btrim(coalesce(p_payload->>'job_title', '')), '');
  v_basic := nullif(p_payload->>'basic', '')::numeric; v_housing := nullif(p_payload->>'housing', '')::numeric; v_transport := nullif(p_payload->>'transport', '')::numeric;
  if v_dept is not null and v_dept is distinct from e.department_id then
    if not exists(select 1 from public.departments where id = v_dept and company_id = p_company) then raise exception 'الإدارة غير موجودة'; end if;
    p := p || jsonb_build_object('department_id', v_dept); end if;
  if v_mgr is not null and v_mgr is distinct from e.manager_id then
    if v_mgr = e.id then raise exception 'لا يكون الموظف مديرا لنفسه'; end if;
    if not exists(select 1 from public.employees where id = v_mgr and company_id = p_company and (end_date is null or end_date >= current_date)) then raise exception 'المدير غير موجود'; end if;
    -- no loop: the new manager must not report (directly or not) to this employee
    if exists(with recursive up(id, n) as (select v_mgr, 0 union all select m.manager_id, up.n + 1 from public.employees m join up on m.id = up.id where m.manager_id is not null and up.n < 50)
              select 1 from up where id = e.id) then raise exception 'المدير الجديد يتبع هذا الموظف في الهيكل'; end if;
    p := p || jsonb_build_object('manager_id', v_mgr); end if;
  if v_br is not null and v_br is distinct from e.branch_id then
    if not exists(select 1 from public.branches where id = v_br and company_id = p_company) then raise exception 'الفرع غير موجود'; end if;
    p := p || jsonb_build_object('branch_id', v_br); end if;
  if v_job is not null and v_job is distinct from e.job_title then
    p := p || jsonb_build_object('job_title', left(v_job, 120), 'job_title_en', nullif(left(btrim(coalesce(p_payload->>'job_title_en', '')), 120), '')); end if;
  if v_gr is not null and v_gr is distinct from e.grade_id then
    select * into g from public.job_grades where id = v_gr and company_id = p_company;
    if not found then raise exception 'الدرجة غير موجودة'; end if;
    p := p || jsonb_build_object('grade_id', v_gr); end if;
  -- pay: this request raises or keeps it; a lower wage is a contract change, not a promotion
  if v_basic is not null and v_basic <> e.basic then
    if v_basic < e.basic then raise exception 'هذا الطلب لا يخفض الأجر الأساسي (الحالي %)', e.basic; end if;
    p := p || jsonb_build_object('basic', round(v_basic, 2)); end if;
  if v_housing is not null and v_housing <> e.housing then
    if v_housing < e.housing then raise exception 'هذا الطلب لا يخفض بدل السكن (الحالي %)', e.housing; end if;
    p := p || jsonb_build_object('housing', round(v_housing, 2)); end if;
  if v_transport is not null and v_transport <> e.transport then
    if v_transport < e.transport then raise exception 'هذا الطلب لا يخفض بدل النقل (الحالي %)', e.transport; end if;
    p := p || jsonb_build_object('transport', round(v_transport, 2)); end if;
  if p = '{}'::jsonb then raise exception 'حدد ما يتغير: الإدارة أو المسمى أو المدير أو الفرع أو الدرجة أو الأجر'; end if;
  if (p ? 'grade_id' or p ? 'basic') and coalesce(v_gr, e.grade_id) is not null then
    select * into g from public.job_grades where id = coalesce(v_gr, e.grade_id);
    if coalesce(v_basic, e.basic) < g.min_basic or coalesce(v_basic, e.basic) > g.max_basic then
      raise exception 'الأجر الأساسي خارج نطاق الدرجة % (% – %)', g.code, g.min_basic, g.max_basic; end if;
  end if;
  if nullif(btrim(coalesce(p_payload->>'reason', '')), '') is null then raise exception 'اكتب سبب الطلب'; end if;
  -- the values before, for the approvers and the record
  o := jsonb_build_object('department_id', e.department_id, 'manager_id', e.manager_id, 'branch_id', e.branch_id, 'grade_id', e.grade_id, 'job_title', e.job_title,
         'basic', e.basic, 'housing', e.housing, 'transport', e.transport);
  p := jsonb_build_object('type', v_type, 'new', p, 'old', o, 'reason', left(btrim(p_payload->>'reason'), 500),
         'by', (select full_name from public.employees where id = me), 'names', jsonb_strip_nulls(jsonb_build_object(
           'department', (select name from public.departments where id = coalesce(v_dept, e.department_id)), 'old_department', (select name from public.departments where id = e.department_id),
           'manager', (select full_name from public.employees where id = coalesce(v_mgr, e.manager_id)), 'old_manager', (select full_name from public.employees where id = e.manager_id),
           'branch', (select code || ' — ' || name from public.branches where id = coalesce(v_br, e.branch_id)), 'old_branch', (select code || ' — ' || name from public.branches where id = e.branch_id),
           'grade', (select code || ' — ' || name from public.job_grades where id = coalesce(v_gr, e.grade_id)), 'old_grade', (select code || ' — ' || name from public.job_grades where id = e.grade_id))));

  select route into rt from public.workflows where company_id = p_company and kind = p_kind;
  rt := coalesce(rt, public.default_route(p_kind));
  select hr_manager into hm from public.companies where id = p_company;
  if hm is null or exists(select 1 from public.members m where m.company_id = p_company and m.user_id = hm and m.employee_id = p_emp) then rt := array_remove(rt, 'h'); end if;
  -- the direct manager raised it himself: his step is done
  if e.manager_id is null or e.manager_id = me then rt := array_remove(rt, 'm'); end if;
  select m.employee_id into owner_emp from public.members m where m.company_id = p_company and m.role = 'owner' limit 1;
  if p_emp = owner_emp then rt := array_remove(rt, 'g'); end if;

  insert into public.requests(company_id, employee_id, kind, from_date, to_date, payload, note, route, step, status)
  values (p_company, p_emp, p_kind, p_from, p_from, p, nullif(trim(p_note), ''), rt, 0, case when cardinality(rt) = 0 then 'approved' else 'pending' end)
  returning id into rid;
  insert into public.request_actions(request_id, actor, action) values (rid, auth.uid(), 'submitted');
  if cardinality(rt) = 0 then perform public.on_request_approved(rid); end if;
  return rid;
end $$;

-- the final approval applies the change (the salary history takes the effective date)
create or replace function public.move_apply(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.requests; n jsonb;
begin
  select * into r from public.requests where id = p_id;
  n := r.payload->'new';
  perform set_config('waad.sal_on', r.from_date::text, true);
  perform set_config('waad.sal_reason', case r.payload->>'type' when 'promotion' then 'ترقية' when 'raise' then 'زيادة في الأجر' when 'title' then 'تغيير المسمى' else 'نقل' end
    || ' — ' || coalesce(r.payload->>'reason', ''), true);
  update public.employees set
    department_id = case when n ? 'department_id' then (n->>'department_id')::uuid else department_id end,
    manager_id    = case when n ? 'manager_id' then (n->>'manager_id')::uuid else manager_id end,
    branch_id     = case when n ? 'branch_id' then (n->>'branch_id')::uuid else branch_id end,
    grade_id      = case when n ? 'grade_id' then (n->>'grade_id')::uuid else grade_id end,
    job_title     = case when n ? 'job_title' then n->>'job_title' else job_title end,
    job_title_en  = case when n ? 'job_title' then coalesce(n->>'job_title_en', job_title_en) else job_title_en end,
    basic         = case when n ? 'basic' then (n->>'basic')::numeric else basic end,
    housing       = case when n ? 'housing' then (n->>'housing')::numeric else housing end,
    transport     = case when n ? 'transport' then (n->>'transport')::numeric else transport end
  where id = r.employee_id;
  perform set_config('waad.sal_on', '', true); perform set_config('waad.sal_reason', '', true);
end $$;

-- the employee cannot cancel a request raised about him; the one who raised it can, while it waits
create or replace function public.cancel_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.requests;
begin
  select * into r from public.requests where id = p_id for update;
  if not found then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if r.kind = 'move' then
    if r.created_by is distinct from (select auth.uid()) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  elsif r.employee_id is distinct from public.my_employee(r.company_id) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if r.status <> 'pending' then raise exception 'لا يمكن إلغاء طلب تم البت فيه'; end if;
  if r.kind = 'resign' and r.created_at < now() - interval '7 days' then raise exception 'يجوز العدول عن الاستقالة خلال 7 أيام من تقديمها فقط — م79 مكرر'; end if;
  update public.requests set status = 'cancelled', decided_at = now() where id = p_id;
  insert into public.request_actions(request_id, actor, action) values (p_id, auth.uid(), 'cancelled');
end $$;

CREATE OR REPLACE FUNCTION public.submit_request(p_company uuid, p_kind text, p_sub text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_amount numeric DEFAULT NULL::numeric, p_payload jsonb DEFAULT '{}'::jsonb, p_note text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := public.my_employee(p_company);
  e public.employees; lt public.leave_types; d int; used int; rt text[]; rid uuid; owner_emp uuid; k text; ev date; bal numeric; g numeric; minst int; v_files jsonb; lim numeric; ps date; pe date; hm uuid; v_rate numeric;
begin
  if me is null then raise exception 'حسابك غير مربوط بسجل موظف' using errcode = '42501'; end if;
  select * into e from public.employees where id = me;
  if e.end_date is not null and e.end_date < current_date then raise exception 'انتهت خدمتك'; end if;
  g := public.gross_wage(e);
  v_files := p_payload->'files'; p_payload := coalesce(p_payload, '{}'::jsonb) - 'files';   -- files go to request_attachments, never into the payload

  if p_kind = 'leave' then
    select * into lt from public.leave_types where code = p_sub;
    if not found then raise exception 'نوع إجازة غير معروف'; end if;
    if p_from is null or p_to is null then raise exception 'حدد تاريخ البداية والنهاية'; end if;
    if p_to < p_from then raise exception 'تاريخ النهاية قبل البداية'; end if;
    d := public.days_between(p_from, p_to);
    -- Reg. Art. 24(2): official holidays inside annual leave are not counted (the leave is extended by them)
    if p_sub = 'annual' then d := d - public.holidays_in(p_company, p_from, p_to); end if;
    if d <= 0 then raise exception 'الفترة كلها عطل رسمية'; end if;
    if exists(select 1 from public.requests where employee_id = me and kind = 'leave' and status in ('pending','approved')
              and p_from <= to_date and p_to >= from_date) then
      raise exception 'الفترة تتداخل مع إجازة سابقة'; end if;
    if lt.gender is not null and lt.gender <> e.gender then raise exception 'هذه الإجازة لا تنطبق عليك'; end if;
    if lt.max_days is not null and d > lt.max_days and lt.code <> 'sick' then raise exception 'الحد الأقصى لهذه الإجازة % يوماً', lt.max_days; end if;
    if lt.min_days is not null and d < lt.min_days then raise exception 'أقل مدة لهذه الإجازة % أيام', lt.min_days; end if;
    if lt.min_service_years is not null and (current_date - e.hire_date) / 365.0 < lt.min_service_years then
      raise exception 'تُمنح هذه الإجازة بعد % سنة خدمة', lt.min_service_years; end if;
    if lt.once_in_service and exists(select 1 from public.requests where employee_id = me and kind='leave' and sub = lt.code and status in ('pending','approved')) then
      raise exception 'هذه الإجازة تُمنح مرة واحدة خلال الخدمة'; end if;
    if lt.notice_days is not null and (p_from - current_date) < lt.notice_days then
      raise exception 'قدّم الطلب قبل % يوماً على الأقل', lt.notice_days; end if;
    -- Art. 113/160: counted from the event date
    if lt.code in ('marriage','death','death2','birth','iddah','iddahn') then
      ev := nullif(p_payload->>'event_date','')::date;
      if ev is null then raise exception 'أدخل تاريخ الواقعة (الزواج/الوفاة/الولادة)'; end if;
      if ev > current_date + 30 then raise exception 'تاريخ الواقعة غير صحيح'; end if;
      if p_from < ev then raise exception 'تبدأ الإجازة من تاريخ الواقعة أو بعده'; end if;
      if lt.code = 'birth' and p_to > ev + 6 then raise exception 'إجازة المولود تؤخذ خلال 7 أيام من تاريخ الولادة — م113'; end if;
      if lt.code in ('marriage','death','death2') and p_to > ev + lt.max_days - 1 then
        raise exception 'تُحتسب هذه الإجازة من تاريخ الواقعة، فتنتهي في % — م113', ev + lt.max_days - 1; end if;
      if lt.code in ('iddah','iddahn') and p_from <> ev then raise exception 'تبدأ إجازة العدة من تاريخ الوفاة — م160'; end if;
    end if;
    if lt.code = 'sick' then
      used := public.sick_days_used(me, p_from);
      if used + d > 120 then raise exception 'تتجاوز 120 يوماً مرضية خلال سنة الإجازة المرضية (المستخدم %)', used; end if;
    end if;
    if lt.code = 'annual' then   -- Art. 109: accrued balance
      select x.taken, floor(x.accrued - x.taken) into used, bal from public.annual_leave_raw(e, p_to) x;
      if d > bal then raise exception 'رصيدك المستحق حتى نهاية الإجازة % يوماً', greatest(bal, 0); end if;
    end if;
    -- Art. 115: exam days are paid leave; only the exams of a repeated year are unpaid
    if lt.code = 'exam' then
      if coalesce(p_payload->>'exam_mode', 'approved') not in ('approved','repeat') then
        raise exception 'حدد حالة الدراسة: سنة غير معادة أو سنة معادة — م115'; end if;
      if p_payload->>'exam_mode' = 'repeat' then p_sub := 'unpaid'; end if;
      p_payload := coalesce(p_payload, '{}'::jsonb) || jsonb_build_object('exam', true, 'exam_mode', coalesce(p_payload->>'exam_mode', 'approved'));
    end if;
    -- Reg. Art. 22-bis: compensatory leave is taken from the hours earned for overtime (8 hours a day)
    if lt.doc_label is not null and (v_files is null or jsonb_typeof(v_files) <> 'array' or jsonb_array_length(v_files) = 0) then
      raise exception 'أرفق المستند المطلوب: %', lt.doc_label; end if;
    if nullif(regexp_replace(coalesce(p_payload->>'doc_ref', ''), '\s', '', 'g'), '') is not null then
      p_payload := p_payload || jsonb_build_object('doc_ref', upper(left(regexp_replace(p_payload->>'doc_ref', '\s', '', 'g'), 40)));
    else p_payload := p_payload - 'doc_ref'; end if;
    if lt.ref_required and length(coalesce(p_payload->>'doc_ref', '')) < 5 then raise exception 'اكتب %', lt.ref_label; end if;
    if lt.code = 'comp' then
      select balance_hours into bal from public.comp_balance(me);
      if d * 8 > coalesce(bal, 0) then raise exception 'رصيد الإجازة التعويضية % ساعة (% يوم)', coalesce(bal, 0), floor(coalesce(bal, 0) / 8); end if;
    end if;
  elsif p_kind = 'permit' then
    if coalesce((p_payload->>'hours')::numeric, 0) <= 0 or (p_payload->>'hours')::numeric > 4 then
      raise exception 'الاستئذان من دقائق حتى 4 ساعات'; end if;
    if p_from is null then raise exception 'حدد تاريخ الاستئذان'; end if;
    -- the company's monthly allowance of permit hours (counted in the payroll month of the date)
    select permit_hours_month into lim from public.companies where id = p_company;
    if lim is not null then
      select x.ps, x.pe into ps, pe from public.att_month_of(p_company, p_from) x;
      select coalesce(sum((payload->>'hours')::numeric), 0) into bal from public.requests
       where employee_id = me and kind = 'permit' and status in ('pending','approved') and from_date between ps and pe;
      if bal + (p_payload->>'hours')::numeric > lim then
        raise exception 'تجاوزت حد الاستئذان الشهري (% ساعة) — المتبقي لك % ساعة', lim, greatest(lim - bal, 0); end if;
    end if;
  elsif p_kind = 'punch' then
    -- forgotten fingerprint: the employee states the missing check-in/out time; HR (or the route) approves it
    if not exists(select 1 from public.companies where id = p_company and att_enabled) then raise exception 'تسجيل الحضور غير مفعّل في منشأتك'; end if;
    if p_from is null or p_from > public.riyadh_today() then raise exception 'حدد يوماً مضى'; end if;
    if p_from < public.riyadh_today() - 30 then raise exception 'طلب نسيان البصمة خلال 30 يوماً من اليوم'; end if;
    if nullif(p_payload->>'in', '') is null and nullif(p_payload->>'out', '') is null then raise exception 'اكتب وقت الحضور أو الانصراف'; end if;
    if coalesce(p_payload->>'in', '') <> '' and p_payload->>'in' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'وقت الحضور غير صحيح'; end if;
    if coalesce(p_payload->>'out', '') <> '' and p_payload->>'out' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'وقت الانصراف غير صحيح'; end if;
    if nullif(p_payload->>'in', '') is null and not exists(select 1 from public.attendance where employee_id = me and day = p_from) then
      raise exception 'لا يوجد تسجيل حضور في هذا اليوم — اكتب وقت الحضور'; end if;
    if exists(select 1 from public.requests where employee_id = me and kind = 'punch' and status = 'pending' and from_date = p_from) then
      raise exception 'لديك طلب نسيان بصمة لهذا اليوم قيد المراجعة'; end if;
    select punch_fix_month into lim from public.companies where id = p_company;
    if lim is not null then
      select x.ps, x.pe into ps, pe from public.att_month_of(p_company, p_from) x;
      if (select count(*) from public.requests where employee_id = me and kind = 'punch' and status in ('pending','approved') and from_date between ps and pe) >= lim then
        raise exception 'تجاوزت حد طلبات نسيان البصمة الشهري (% مرات)', lim::int; end if;
    end if;
    p_to := p_from;
    p_payload := jsonb_build_object('in', nullif(p_payload->>'in', ''), 'out', nullif(p_payload->>'out', ''));
  elsif p_kind in ('advance','expense') then
    if coalesce(p_amount,0) <= 0 then raise exception 'أدخل المبلغ'; end if;
    if p_kind = 'advance' then
      if p_amount > e.basic then raise exception 'السلفة لا تزيد على الراتب الأساسي (%)', e.basic; end if;
      minst := ceil(p_amount / (g * 0.10));
      if coalesce((p_payload->>'inst')::int, 1) < minst then
        raise exception 'القسط الشهري لا يزيد على 10%% من الأجر (% ريال) — اختر % أقساط على الأقل (م92)', round(g * 0.10, 2), minst; end if;
      if coalesce((p_payload->>'inst')::int, 1) > 24 then raise exception 'عدد الأقساط حتى 24'; end if;
    end if;
  elsif p_kind = 'resign' then   -- Art. 79-bis: no deferred date; ends on acceptance
    if p_to is not null and p_to > current_date then raise exception 'لا يصح تحديد تاريخ مؤجل للاستقالة — م79 مكرر'; end if;
    if exists(select 1 from public.requests where employee_id = me and kind = 'resign' and status = 'pending') then
      raise exception 'لديك طلب استقالة قيد المعالجة'; end if;
    p_from := current_date; p_to := null;
  elsif p_kind = 'ticket' then
    if p_from is not null and p_from < current_date then raise exception 'تاريخ السفر قبل اليوم'; end if;
    p_to := coalesce(p_to, p_from);
  elsif p_kind = 'trip' then
    if nullif(btrim(coalesce(p_payload->>'dest', '')), '') is null then raise exception 'اكتب وجهة الرحلة'; end if;
    if nullif(btrim(coalesce(p_payload->>'purpose', '')), '') is null then raise exception 'اكتب الغرض من الرحلة'; end if;
    if p_from is null or p_to is null then raise exception 'حدد تاريخ الذهاب والعودة'; end if;
    if p_to < p_from then raise exception 'تاريخ العودة قبل الذهاب'; end if;
    d := p_to - p_from + 1;
    if d > 90 then raise exception 'مدة الرحلة حتى 90 يوما'; end if;
    if exists(select 1 from public.requests where employee_id = me and kind = 'trip' and status in ('pending','approved') and p_from <= to_date and p_to >= from_date) then
      raise exception 'الفترة تتداخل مع رحلة عمل سابقة'; end if;
    v_rate := public.per_diem_rate(me, coalesce((p_payload->>'abroad')::boolean, false));
    p_amount := round(v_rate * d, 2);
    p_payload := jsonb_build_object('dest', left(btrim(p_payload->>'dest'), 120), 'purpose', left(btrim(p_payload->>'purpose'), 300),
      'abroad', coalesce((p_payload->>'abroad')::boolean, false), 'rate', v_rate, 'transport', coalesce(nullif(p_payload->>'transport', ''), 'none'));
  elsif p_kind = 'overtime' then
    -- asked before the work (or within 7 days after it); after approval the day's overtime counts automatically up to these hours
    if p_from is null then raise exception 'حدد يوم العمل الإضافي'; end if;
    if p_from < public.riyadh_today() - 7 then raise exception 'طلب العمل الإضافي قبل العمل أو خلال 7 أيام بعده'; end if;
    if p_from > public.riyadh_today() + 60 then raise exception 'طلب العمل الإضافي خلال 60 يوما القادمة'; end if;
    if coalesce((p_payload->>'hours')::numeric, 0) <= 0 or (p_payload->>'hours')::numeric > 12 then raise exception 'ساعات العمل الإضافي من نصف ساعة حتى 12 ساعة'; end if;
    if nullif(btrim(coalesce(p_payload->>'reason', '')), '') is null then raise exception 'اكتب سبب العمل الإضافي'; end if;
    if exists(select 1 from public.requests where employee_id = me and kind = 'overtime' and status in ('pending','approved') and from_date = p_from) then
      raise exception 'لديك طلب عمل إضافي لهذا اليوم'; end if;
    perform public.ot_cap_check(me, extract(year from p_from)::int, (p_payload->>'hours')::numeric);
    p_to := p_from;
    p_payload := jsonb_build_object('hours', trim_scale(round((p_payload->>'hours')::numeric * 2) / 2), 'reason', left(btrim(p_payload->>'reason'), 300));
  elsif p_kind = 'remote' then
    -- work from home / another place for some days: the work-site check of «حضوري» is skipped on those days only
    if p_from is null or p_to is null then raise exception 'حدد تاريخ البداية والنهاية'; end if;
    if p_to < p_from then raise exception 'تاريخ النهاية قبل البداية'; end if;
    if p_from < public.riyadh_today() then raise exception 'يبدأ العمل عن بعد من اليوم أو بعده'; end if;
    d := p_to - p_from + 1;
    if d > 30 then raise exception 'العمل عن بعد حتى 30 يوما في الطلب الواحد'; end if;
    if nullif(btrim(coalesce(p_payload->>'reason', '')), '') is null then raise exception 'اكتب سبب العمل عن بعد'; end if;
    if exists(select 1 from public.requests where employee_id = me and kind = 'remote' and status in ('pending','approved') and p_from <= to_date and p_to >= from_date) then
      raise exception 'الفترة تتداخل مع طلب عمل عن بعد سابق'; end if;
    p_payload := jsonb_build_object('reason', left(btrim(p_payload->>'reason'), 300), 'place', left(btrim(coalesce(p_payload->>'place', '')), 120));
  elsif p_kind = 'move' then
    raise exception 'طلب النقل أو الترقية يرفعه المدير المباشر أو الموارد البشرية من ملف الموظف';
  elsif p_kind = 'visa' then
    if p_from is not null and p_to is not null and p_to >= p_from then d := public.days_between(p_from, p_to); end if;
  elsif p_kind = 'update' then
    if p_payload is null or p_payload = '{}'::jsonb then raise exception 'حدد البيانات المطلوب تعديلها'; end if;
    for k in select jsonb_object_keys(p_payload) loop
      if not (k = any(public.update_request_fields())) then raise exception 'لا يمكن طلب تعديل الحقل «%»', k; end if;
    end loop;
    if p_payload ? 'iban' and coalesce(p_payload->>'iban','') !~ '^SA[0-9]{22}$' then raise exception 'الآيبان يبدأ بـ SA ويليه 22 رقماً'; end if;
    if p_payload ? 'email' and coalesce(p_payload->>'email','') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'البريد الإلكتروني غير صحيح'; end if;
    if p_payload ? 'phone' and coalesce(p_payload->>'phone','') !~ '^(05[0-9]{8}|\+9665[0-9]{8})$' then raise exception 'رقم الجوال بصيغة 05XXXXXXXX'; end if;
    if p_payload ? 'short_address' and upper(replace(coalesce(p_payload->>'short_address',''), ' ', '')) !~ '^([A-Z]{4}[0-9]{4})?$' then raise exception 'العنوان المختصر 4 حروف و4 أرقام مثل RRRD2929'; end if;
    if p_payload ? 'marital_status' and coalesce(p_payload->>'marital_status','') not in ('', 'single','married','divorced','widowed') then raise exception 'الحالة الاجتماعية غير صحيحة'; end if;
    if p_payload ? 'dependents' and coalesce(p_payload->>'dependents','') !~ '^([0-9]|[12][0-9]|30)?$' then raise exception 'عدد المرافقين بين 0 و30'; end if;
    if p_payload ? 'emergency_phone' and coalesce(p_payload->>'emergency_phone','') !~ '^(\+?[0-9 ]{7,16})?$' then raise exception 'رقم جوال الطوارئ غير صحيح'; end if;
    if exists(select 1 from public.requests where employee_id = me and kind = 'update' and status = 'pending') then
      raise exception 'لديك طلب تعديل بيانات قيد المراجعة'; end if;
  end if;

  if p_kind in ('leave','ticket','visa') then p_payload := public.travel_check(e, p_kind, p_from, p_to, p_payload); end if;
  select route into rt from public.workflows where company_id = p_company and kind = p_kind;
  rt := coalesce(rt, public.default_route(p_kind));
  -- a ticket inside a leave request is paid by finance, so finance joins the route (before the general manager)
  if p_kind = 'leave' and p_payload ? 'ticket' and not ('f' = any(rt)) then
    rt := case when 'g' = any(rt) then array_remove(rt, 'g') || array['f','g'] else rt || array['f'] end; end if;
  -- the HR-manager step applies only when one is appointed, and never to his own request
  select hr_manager into hm from public.companies where id = p_company;
  if hm is null or exists(select 1 from public.members m where m.company_id = p_company and m.user_id = hm and m.employee_id = me) then
    rt := array_remove(rt, 'h'); end if;
  select m.employee_id into owner_emp from public.members m where m.company_id = p_company and m.role = 'owner' limit 1;
  if e.manager_id is null then rt := array_remove(rt, 'm'); end if;
  if me = owner_emp or (e.manager_id = owner_emp and 'm' = any(rt)) then rt := array_remove(rt, 'g'); end if;

  insert into public.requests(company_id, employee_id, kind, sub, from_date, to_date, days, amount, payload, note, route, step, status)
  values (p_company, me, p_kind, p_sub, p_from, p_to, d, p_amount, coalesce(p_payload,'{}'), nullif(trim(p_note),''), rt, 0,
          case when cardinality(rt) = 0 then 'approved' else 'pending' end)
  returning id into rid;
  insert into public.request_actions(request_id, actor, action) values (rid, auth.uid(), 'submitted');
  perform public.attach_files(rid, v_files);
  if cardinality(rt) = 0 then perform public.on_request_approved(rid); end if;
  return rid;
end $function$;

CREATE OR REPLACE FUNCTION public.on_request_approved(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.requests; nm text;
begin
  select * into r from public.requests where id = p_id;
  select full_name into nm from public.employees where id = r.employee_id;
  if r.kind = 'advance' then
    perform public.post_journal(r.company_id, current_date, 'سلفة — ' || nm, 'advance', r.id,
      jsonb_build_array(jsonb_build_object('a','1500','d',r.amount), jsonb_build_object('a','1120','c',r.amount)));
  elsif r.kind = 'expense' then
    perform public.post_journal(r.company_id, current_date, 'مطالبة مصروفات — ' || nm, 'expense', r.id,
      jsonb_build_array(jsonb_build_object('a','5500','d',r.amount), jsonb_build_object('a','1120','c',r.amount)));
  elsif r.kind = 'trip' and coalesce(r.amount, 0) > 0 then
    insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header)
    values (r.company_id, '5230', 'بدل انتداب ورحلات العمل', 'Business travel per diem', 'exp', '5000', false) on conflict do nothing;
    perform public.post_journal(r.company_id, current_date, 'بدل انتداب — ' || nm || ' — ' || coalesce(r.payload->>'dest', ''), 'trip', r.id,
      jsonb_build_array(jsonb_build_object('a','5230','d',r.amount,'cc',(select cost_center_id from public.employees where id = r.employee_id)), jsonb_build_object('a','1120','c',r.amount)));
  elsif r.kind = 'resign' then
    -- ends on acceptance, or at the end of the 30 days, or at the end of a deferral (Art. 79-bis(2))
    update public.requests set to_date = least(current_date, coalesce(nullif(r.payload->>'defer_until', '')::date, r.created_at::date + 30)) where id = p_id;
    update public.employees set end_date = least(current_date, coalesce(nullif(r.payload->>'defer_until', '')::date, r.created_at::date + 30)), end_reason = 'resign' where id = r.employee_id;
  elsif r.kind = 'overtime' then
    perform public.ot_preapproved_apply(r.employee_id, r.from_date);
  elsif r.kind = 'move' then
    perform public.move_apply(r.id);
  elsif r.kind = 'punch' then
    perform public.punch_apply(r.id);
  elsif r.kind = 'update' then
    update public.employees set
      phone = case when r.payload ? 'phone' then r.payload->>'phone' else phone end,
      email = case when r.payload ? 'email' then r.payload->>'email' else email end,
      iban  = case when r.payload ? 'iban'  then r.payload->>'iban'  else iban end
    where id = r.employee_id;
    perform public.emp_apply_profile(r.company_id, r.employee_id, r.payload - 'phone' - 'email' - 'iban', '');
  end if;
  if r.kind in ('leave','ticket') and r.payload ? 'ticket' then
    insert into public.travel_tickets(company_id, employee_id, request_id, mode, persons, estimate)
    select r.company_id, r.employee_id, r.id, r.payload->'ticket'->>'mode', (r.payload->'ticket'->>'persons')::int,
           e.ticket_amount * (r.payload->'ticket'->>'persons')::int from public.employees e where e.id = r.employee_id;
  end if;
  if r.kind in ('leave','visa') and r.payload ? 'visa' then
    insert into public.exit_visas(company_id, employee_id, request_id, visa_type, travel_on, return_on)
    values (r.company_id, r.employee_id, r.id, r.payload->'visa'->>'type', r.from_date, r.to_date);
  end if;
end $function$;

-- clearance: the leaving employee follows his own checklist (read only) in «ملفي»
create or replace function public.clearance_status(p_emp uuid)
returns table(step text, ok boolean, detail text, done_at timestamptz, note text, can_mark boolean)
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; held int; hv numeric; adv numeric;
begin
  select * into e from public.employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود'; end if;
  if not (public.has_role(e.company_id, array['owner','admin','hr','finance']) or coalesce(e.manager_id = public.my_employee(e.company_id), false)
          or coalesce(e.id = public.my_employee(e.company_id), false)) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  select count(*), coalesce(sum(value), 0) into held, hv from public.custody_items where employee_id = p_emp and status = 'held';
  select coalesce(sum(public.advance_remaining(q.id)), 0) into adv from public.requests q where q.employee_id = p_emp and q.kind = 'advance' and q.status = 'approved';
  return query
  select 'custody'::text, held = 0, case when held = 0 then null else held || ' — ' || hv end, null::timestamptz, null::text, false
  union all select 'advance', adv = 0, case when adv = 0 then null else adv::text end, null, null, false
  union all
  select s.k, m.employee_id is not null, null, m.done_at, m.note, public.clearance_can(p_emp, s.k)
    from (values (1, 'manager'), (2, 'it'), (3, 'finance'), (4, 'hr')) s(o, k)
    left join public.clearance_marks m on m.employee_id = p_emp and m.step = s.k
   order by 1;
end $$;

revoke all on function public.ot_preapproved_min(uuid, date), public.ot_preapproved_apply(uuid, date), public.attendance_ot_preapproved(),
  public.remote_on(uuid, date), public.move_apply(uuid), public.request_file_can(uuid, uuid) from public, anon, authenticated;
revoke all on function public.my_remote_today(uuid), public.move_options(uuid, uuid), public.request_file(uuid, uuid, text, date, jsonb, text) from public, anon;
grant execute on function public.my_remote_today(uuid), public.move_options(uuid, uuid), public.request_file(uuid, uuid, text, date, jsonb, text) to authenticated;
notify pgrst, 'reload schema';
