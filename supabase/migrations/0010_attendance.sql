-- Waad ERP — 0010 attendance: work sites (geofence), shifts, public holidays, self check-in/out from the phone,
-- HR corrections, overtime approval, daily sheet, and payroll integration (absence, lateness, approved overtime).
-- Times are Asia/Riyadh. A shift whose end is not after its start runs past midnight; the record belongs to the start day.

-- ---------- settings (per company) ----------
alter table public.companies add column att_enabled boolean not null default false;
alter table public.companies add column att_start date;
alter table public.companies add column att_geofence boolean not null default true;
alter table public.companies add column att_deduct_late boolean not null default false;

create table public.work_sites (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null check (length(trim(name)) >= 2),
  lat numeric(9,6) not null check (lat between -90 and 90),
  lng numeric(9,6) not null check (lng between -180 and 180),
  radius_m int not null default 200 check (radius_m between 30 and 5000),
  created_at timestamptz not null default now()
);
create index on public.work_sites(company_id);

create table public.shifts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null check (length(trim(name)) >= 2),
  start_time time not null,
  end_time time not null,
  grace_min int not null default 15 check (grace_min between 0 and 120),
  work_days int[] not null default '{0,1,2,3,4}' check (cardinality(work_days) between 1 and 7 and work_days <@ '{0,1,2,3,4,5,6}'),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  unique (company_id, name),
  check (start_time <> end_time)
);
create unique index shifts_one_default on public.shifts(company_id) where is_default;

create table public.holidays (
  company_id uuid not null references public.companies(id) on delete cascade,
  day date not null,
  name text not null check (length(trim(name)) >= 2),
  primary key (company_id, day)
);

alter table public.employees add column shift_id uuid references public.shifts(id) on delete set null;
alter table public.employees add column att_exempt boolean not null default false;

create or replace function public.employee_shift_guard() returns trigger language plpgsql as $$
begin
  if new.shift_id is not null and not exists(select 1 from public.shifts s where s.id = new.shift_id and s.company_id = new.company_id) then
    raise exception 'الوردية غير موجودة'; end if;
  return new;
end $$;
create trigger employees_shift_guard before insert or update of shift_id on public.employees for each row execute function public.employee_shift_guard();

-- ---------- attendance records ----------
create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  day date not null,
  shift_id uuid references public.shifts(id) on delete set null,
  check_in timestamptz not null,
  check_out timestamptz,
  in_lat numeric(9,6), in_lng numeric(9,6), in_acc numeric(8,1), in_site uuid references public.work_sites(id) on delete set null,
  out_lat numeric(9,6), out_lng numeric(9,6), out_acc numeric(8,1), out_site uuid references public.work_sites(id) on delete set null,
  sched_start timestamptz, sched_end timestamptz,
  late_min int not null default 0,
  early_min int not null default 0,
  worked_min int not null default 0,
  extra_min int not null default 0,      -- time worked beyond the schedule (or on a day off / holiday)
  ot_min int not null default 0,         -- overtime approved by HR (Art. 107: overtime is worked at the employer's request)
  source text not null default 'self' check (source in ('self','hr')),
  note text,
  updated_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  unique (employee_id, day),
  check (check_out is null or check_out > check_in),
  check (ot_min >= 0 and ot_min <= extra_min)
);
create index on public.attendance(company_id, day);

-- local (Riyadh) helpers
create or replace function public.riyadh_today() returns date language sql stable as $$ select (now() at time zone 'Asia/Riyadh')::date $$;
create or replace function public.riyadh_ts(p_day date, p_time time) returns timestamptz language sql immutable as $$
  select (p_day + p_time) at time zone 'Asia/Riyadh'
$$;
create or replace function public.employee_shift(p_emp uuid) returns public.shifts language sql stable security definer set search_path = public as $$
  select s.* from public.employees e join public.shifts s on s.company_id = e.company_id
   where e.id = p_emp and (s.id = e.shift_id or (e.shift_id is null and s.is_default)) order by (s.id = e.shift_id) desc limit 1
$$;
-- great-circle distance in metres
create or replace function public.geo_dist_m(lat1 numeric, lng1 numeric, lat2 numeric, lng2 numeric) returns numeric language sql immutable as $$
  select 2 * 6371000 * asin(sqrt(power(sin(radians(lat2 - lat1) / 2), 2) + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)))
$$;

-- schedule, lateness, early leave, worked and extra time for one record
create or replace function public.att_recalc(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare a public.attendance; s public.shifts; ss timestamptz; se timestamptz; workday boolean; late int := 0; early int := 0; worked int := 0; extra int := 0;
begin
  select * into a from public.attendance where id = p_id;
  select * into s from public.shifts where id = a.shift_id;
  workday := s.id is not null and extract(dow from a.day)::int = any(s.work_days)
             and not exists(select 1 from public.holidays h where h.company_id = a.company_id and h.day = a.day);
  if s.id is not null then
    ss := public.riyadh_ts(a.day, s.start_time);
    se := public.riyadh_ts(a.day + case when s.end_time <= s.start_time then 1 else 0 end, s.end_time);
  end if;
  if a.check_out is not null then worked := floor(extract(epoch from a.check_out - a.check_in) / 60); end if;
  if workday then
    if a.check_in > ss + make_interval(mins => s.grace_min) then late := ceil(extract(epoch from a.check_in - ss) / 60); end if;
    if a.check_out is not null and a.check_out < se then early := ceil(extract(epoch from se - a.check_out) / 60); end if;
    if a.check_out is not null and a.check_out > se then extra := floor(extract(epoch from a.check_out - greatest(se, a.check_in)) / 60); end if;
  else
    extra := worked;
  end if;
  update public.attendance set sched_start = case when workday then ss end, sched_end = case when workday then se end,
    late_min = late, early_min = early, worked_min = worked, extra_min = extra, ot_min = least(ot_min, extra)
   where id = p_id;
end $$;

-- ---------- self check-in / check-out (one button) ----------
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
  if c.att_geofence and exists(select 1 from public.work_sites where company_id = p_company) then
    if p_lat is null or p_lng is null then raise exception 'فعّل خدمة الموقع في جوالك ثم أعد المحاولة'; end if;
    if coalesce(p_acc, 0) > 150 then raise exception 'دقة الموقع ضعيفة (± % م) — فعّل GPS أو اقترب من نافذة ثم أعد المحاولة', round(p_acc); end if;
    select id into site from public.work_sites w where w.company_id = p_company and public.geo_dist_m(w.lat, w.lng, p_lat, p_lng) <= w.radius_m + coalesce(p_acc, 0) / 2
     order by public.geo_dist_m(w.lat, w.lng, p_lat, p_lng) limit 1;
    if site is null then
      select name, round(public.geo_dist_m(lat, lng, p_lat, p_lng)) into near_name, near_d from public.work_sites where company_id = p_company order by public.geo_dist_m(lat, lng, p_lat, p_lng) limit 1;
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
  s := public.employee_shift(me);
  insert into public.attendance(company_id, employee_id, day, shift_id, check_in, in_lat, in_lng, in_acc, in_site)
  values (p_company, me, d, s.id, now(), p_lat, p_lng, p_acc, site) returning id into rid;
  perform public.att_recalc(rid);
  select * into a from public.attendance where id = rid;
  return jsonb_build_object('action', 'in', 'at', a.check_in, 'late_min', a.late_min, 'shift', s.name);
end $$;

-- ---------- HR: correct a day (times are local HH:MM; empty check-in deletes the record) ----------
create or replace function public.att_set(p_company uuid, p_emp uuid, p_day date, p_in time, p_out time, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare e public.employees; s public.shifts; ti timestamptz; tout timestamptz; rid uuid;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  select * into e from public.employees where id = p_emp and company_id = p_company;
  if not found then raise exception 'الموظف غير موجود في المنشأة'; end if;
  if length(trim(coalesce(p_note, ''))) < 3 then raise exception 'اكتب سبب التعديل'; end if;
  if p_day > public.riyadh_today() then raise exception 'لا يمكن تسجيل حضور ليوم لم يأتِ بعد'; end if;
  if p_in is null then delete from public.attendance where employee_id = p_emp and day = p_day; return; end if;
  ti := public.riyadh_ts(p_day, p_in);
  if p_out is not null then tout := public.riyadh_ts(p_day + case when p_out <= p_in then 1 else 0 end, p_out); end if;
  if tout is not null and tout > now() then raise exception 'وقت الانصراف في المستقبل'; end if;
  select id into rid from public.attendance where employee_id = p_emp and day = p_day;
  if rid is null then
    s := public.employee_shift(p_emp);
    insert into public.attendance(company_id, employee_id, day, shift_id, check_in, check_out, source, note)
    values (p_company, p_emp, p_day, s.id, ti, tout, 'hr', trim(p_note)) returning id into rid;
  else
    update public.attendance set check_in = ti, check_out = tout, source = 'hr', note = trim(p_note), updated_by = auth.uid(), updated_at = now() where id = rid;
  end if;
  perform public.att_recalc(rid);
end $$;

-- ---------- HR: approve overtime minutes on a record ----------
create or replace function public.att_approve_ot(p_id uuid, p_minutes int) returns void
language plpgsql security definer set search_path = public as $$
declare a public.attendance;
begin
  select * into a from public.attendance where id = p_id;
  if not found then raise exception 'السجل غير موجود'; end if;
  perform public.require_role(a.company_id, array['owner','admin','hr']);
  if p_minutes < 0 or p_minutes > a.extra_min then raise exception 'الإضافي المعتمد بين 0 و% دقيقة', a.extra_min; end if;
  if exists(select 1 from public.payroll_runs r where r.company_id = a.company_id and r.status <> 'draft'
            and make_date(r.year, r.month, 1) <= a.day and a.day < make_date(r.year, r.month, 1) + interval '1 month') then
    raise exception 'مسير هذا الشهر معتمد — لا يمكن تعديل الإضافي'; end if;
  update public.attendance set ot_min = p_minutes, updated_by = auth.uid(), updated_at = now() where id = p_id;
end $$;

-- ---------- settings ----------
create or replace function public.att_settings(p_company uuid, p_enabled boolean, p_start date, p_geofence boolean, p_deduct_late boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if p_enabled and not exists(select 1 from public.shifts where company_id = p_company and is_default) then
    raise exception 'أضف وردية افتراضية قبل تفعيل الحضور'; end if;
  update public.companies set att_enabled = p_enabled, att_start = case when p_enabled then coalesce(p_start, att_start, public.riyadh_today()) else att_start end,
    att_geofence = p_geofence, att_deduct_late = p_deduct_late where id = p_company;
end $$;

-- ---------- daily sheet: one row per employee per day ----------
-- status: present | late | open (no check-out yet) | nocheckout | absent | leave | holiday | off | pending (today, not in yet) | na (before tracking)
create or replace function public.att_sheet(p_company uuid, p_from date, p_to date, p_emp uuid default null)
returns table(employee_id uuid, day date, status text, leave_sub text, att_id uuid, check_in timestamptz, check_out timestamptz,
              late_min int, early_min int, worked_min int, extra_min int, ot_min int, source text, note text)
language plpgsql stable security definer set search_path = public as $$
declare c public.companies; me uuid := public.my_employee(p_company); hr boolean := public.has_role(p_company, array['owner','admin','hr','finance']); td date := public.riyadh_today();
begin
  if not public.is_member(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_to < p_from or p_to - p_from > 62 then raise exception 'الفترة من يوم إلى 62 يوماً'; end if;
  select * into c from public.companies where id = p_company;
  return query
  with emps as (
    select e.* from public.employees e where e.company_id = p_company and not e.att_exempt
      and (p_emp is null or e.id = p_emp)
      and (hr or e.id = me or e.manager_id = me)),
  days as (select g::date d from generate_series(p_from, least(p_to, td), interval '1 day') g)
  select e.id, dd.d,
    case
      when a.id is not null then case when a.check_out is null then case when dd.d >= td - 1 and a.check_in > now() - interval '20 hours' then 'open' else 'nocheckout' end
                                       when a.late_min > 0 then 'late' else 'present' end
      when dd.d < e.hire_date or (e.end_date is not null and dd.d > e.end_date) then 'na'
      when h.day is not null then 'holiday'
      when lv.sub is not null then 'leave'
      when s.id is null or not (extract(dow from dd.d)::int = any(s.work_days)) then 'off'
      when not c.att_enabled or c.att_start is null or dd.d < c.att_start then 'na'
      when dd.d = td then 'pending'
      else 'absent' end,
    lv.sub, a.id, a.check_in, a.check_out, a.late_min, a.early_min, a.worked_min, a.extra_min, a.ot_min, a.source, a.note
  from emps e cross join days dd
  left join public.attendance a on a.employee_id = e.id and a.day = dd.d
  left join public.holidays h on h.company_id = p_company and h.day = dd.d
  left join lateral (select q.sub from public.requests q where q.employee_id = e.id and q.kind = 'leave' and q.status = 'approved'
                     and dd.d between q.from_date and q.to_date limit 1) lv on true
  left join lateral (select * from public.employee_shift(e.id)) s on true
  where dd.d >= e.hire_date - 0 or a.id is not null
  order by e.emp_no, dd.d;
end $$;

-- ---------- monthly totals used by payroll ----------
create or replace function public.att_month(p_emp uuid, p_ms date, p_me date)
returns table(absent_days int, late_min int, ot_min int) language sql stable security definer set search_path = public as $$
  with e as (select * from public.employees where id = p_emp), c as (select x.* from public.companies x join e on x.id = e.company_id),
  days as (select g::date d from generate_series(greatest(p_ms, (select hire_date from e), coalesce((select att_start from c), p_me + 1)),
                                                  least(p_me, coalesce((select end_date from e), p_me), public.riyadh_today() - 1), interval '1 day') g),
  s as (select * from public.employee_shift(p_emp))
  select
    (select count(*)::int from days where (select att_enabled from c) and not (select att_exempt from e)
       and exists(select 1 from s where extract(dow from days.d)::int = any(s.work_days))
       and not exists(select 1 from public.holidays h where h.company_id = (select company_id from e) and h.day = days.d)
       and not exists(select 1 from public.attendance a where a.employee_id = p_emp and a.day = days.d)
       and not exists(select 1 from public.requests q where q.employee_id = p_emp and q.kind = 'leave' and q.status = 'approved' and days.d between q.from_date and q.to_date)),
    (select coalesce(sum(a.late_min), 0)::int from public.attendance a where a.employee_id = p_emp and a.day between p_ms and p_me),
    (select coalesce(sum(a.ot_min), 0)::int from public.attendance a where a.employee_id = p_emp and a.day between p_ms and p_me)
$$;

-- ---------- payroll: absence from attendance, lateness (optional), approved overtime ----------
alter table public.payroll_lines add column att_absent_days int not null default 0;
alter table public.payroll_lines add column att_absence numeric(12,2) not null default 0;
alter table public.payroll_lines add column late_min int not null default 0;
alter table public.payroll_lines add column late_deduction numeric(12,2) not null default 0;
alter table public.payroll_lines add column att_ot_hours numeric(6,2) not null default 0;

create or replace function public.payroll_line_recalc(p_run uuid, p_emp uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; e public.employees; ms date; me date; ab numeric; l public.payroll_lines; g numeric; sk record; adv_sched numeric; room numeric;
        am record; deduct_late boolean;
begin
  select * into r from public.payroll_runs where id = p_run;
  select * into e from public.employees where id = p_emp;
  select * into l from public.payroll_lines where run_id = p_run and employee_id = p_emp;
  select att_deduct_late into deduct_late from public.companies where id = r.company_id;
  ms := make_date(r.year, r.month, 1); me := (ms + interval '1 month - 1 day')::date;
  g := e.basic + e.housing + e.transport;
  select coalesce(sum(greatest(0, least(to_date, me) - greatest(from_date, ms) + 1)), 0) into ab
  from public.requests where employee_id = p_emp and kind = 'leave' and sub = 'unpaid' and status = 'approved' and from_date <= me and to_date >= ms;
  select * into sk from public.sick_deduction(p_emp, ms, me, g / 30);
  select * into am from public.att_month(p_emp, ms, me);
  update public.payroll_lines set
    basic = e.basic, housing = e.housing, transport = e.transport, gross = g,
    gosi = public.gosi_employee(e.is_saudi, e.basic, e.housing, public.gosi_is_new(e.gosi_new, e.hire_date), me),
    employer_gosi = public.gosi_employer(e.is_saudi, e.basic, e.housing, public.gosi_is_new(e.gosi_new, e.hire_date), me),
    absence_days = ab, absence = round(g / 30 * ab, 2),
    sick_days = sk.days, sick_deduction = sk.amount,
    att_absent_days = am.absent_days, att_absence = round(g / 30 * am.absent_days, 2),
    late_min = am.late_min, late_deduction = case when deduct_late then round(g / 30 / 8 / 60 * am.late_min, 2) else 0 end,
    att_ot_hours = round(am.ot_min / 60.0, 2),
    overtime = round((g / 30 / 8 + 0.5 * e.basic / 30 / 8) * (l.overtime_hours + round(am.ot_min / 60.0, 2)), 2)  -- Art. 107
  where run_id = p_run and employee_id = p_emp;
  select * into l from public.payroll_lines where run_id = p_run and employee_id = p_emp;
  select coalesce(sum(d.amount),0) into adv_sched from public.advance_deductions d join public.requests q on q.id = d.request_id
   where d.run_id = p_run and q.employee_id = p_emp;
  room := greatest(0, round(g * 0.5, 2) - l.gosi - l.deductions - l.damages);
  update public.payroll_lines set advance = least(adv_sched, round(g * 0.10, 2), room) where run_id = p_run and employee_id = p_emp;
  if adv_sched > least(adv_sched, round(g * 0.10, 2), room) then
    with x as (select d.request_id, d.amount, sum(d.amount) over (order by d.request_id) running from public.advance_deductions d
               join public.requests q on q.id = d.request_id where d.run_id = p_run and q.employee_id = p_emp)
    update public.advance_deductions ad set amount = greatest(0, least(x.amount, least(adv_sched, round(g * 0.10, 2), room) - (x.running - x.amount)))
      from x where ad.run_id = p_run and ad.request_id = x.request_id;
    delete from public.advance_deductions where run_id = p_run and amount <= 0;
  end if;
  update public.payroll_lines set net = gross + overtime + bonus - gosi - absence - att_absence - late_deduction - sick_deduction - deductions - damages - advance
   where run_id = p_run and employee_id = p_emp;
end $$;

create or replace function public.payroll_approve(p_run uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; t record; me date; je uuid;
begin
  select * into r from public.payroll_runs where id = p_run for update;
  perform public.require_role(r.company_id, array['owner','finance']);
  if r.status <> 'draft' then raise exception 'المسير معتمد مسبقاً'; end if;
  select coalesce(sum(gross + overtime + bonus - absence - att_absence - late_deduction - sick_deduction - deductions - damages),0) ex, coalesce(sum(gosi),0) g, coalesce(sum(employer_gosi),0) eg,
         coalesce(sum(advance),0) adv, coalesce(sum(net),0) n, count(*) c
    into t from public.payroll_lines where run_id = p_run;
  if t.c = 0 then raise exception 'المسير فارغ'; end if;
  me := (make_date(r.year, r.month, 1) + interval '1 month - 1 day')::date;
  je := public.post_journal(r.company_id, me, 'استحقاق رواتب ' || lpad(r.month::text,2,'0') || '/' || r.year, 'payroll', r.id,
    jsonb_build_array(jsonb_build_object('a','5200','d',t.ex), jsonb_build_object('a','5210','d',t.eg),
                      jsonb_build_object('a','2400','c',t.g + t.eg), jsonb_build_object('a','1500','c',t.adv), jsonb_build_object('a','2300','c',t.n)));
  update public.payroll_runs set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_run;
  return je;
end $$;

-- ---------- audit, RLS, grants ----------
create trigger audit_attendance after insert or update or delete on public.attendance for each row execute function public.audit_trigger();
create trigger audit_shifts after insert or update or delete on public.shifts for each row execute function public.audit_trigger();
create trigger audit_work_sites after insert or update or delete on public.work_sites for each row execute function public.audit_trigger();

alter table public.work_sites enable row level security;
alter table public.shifts enable row level security;
alter table public.holidays enable row level security;
alter table public.attendance enable row level security;

create policy ws_read on public.work_sites for select using (public.is_member(company_id));
create policy ws_write on public.work_sites for all using (public.has_role(company_id, array['owner','admin','hr'])) with check (public.has_role(company_id, array['owner','admin','hr']));
create policy sh_read on public.shifts for select using (public.is_member(company_id));
create policy sh_write on public.shifts for all using (public.has_role(company_id, array['owner','admin','hr'])) with check (public.has_role(company_id, array['owner','admin','hr']));
create policy hd_read on public.holidays for select using (public.is_member(company_id));
create policy hd_write on public.holidays for all using (public.has_role(company_id, array['owner','admin','hr'])) with check (public.has_role(company_id, array['owner','admin','hr']));
create policy att_read on public.attendance for select using (
  public.has_role(company_id, array['owner','admin','hr','finance'])
  or employee_id = public.my_employee(company_id)
  or exists(select 1 from public.employees e where e.id = employee_id and e.manager_id = public.my_employee(attendance.company_id)));

revoke all on public.work_sites, public.shifts, public.holidays, public.attendance from anon;
grant select, insert, update, delete on public.work_sites, public.shifts, public.holidays to authenticated;
grant select on public.attendance to authenticated;
revoke insert, update, delete on public.attendance from authenticated;

revoke all on function public.att_recalc(uuid), public.employee_shift(uuid), public.att_month(uuid, date, date), public.employee_shift_guard(),
  public.clock(uuid, numeric, numeric, numeric), public.att_set(uuid, uuid, date, time, time, text), public.att_approve_ot(uuid, int),
  public.att_settings(uuid, boolean, date, boolean, boolean), public.att_sheet(uuid, date, date, uuid) from public, anon, authenticated;
grant execute on function public.clock(uuid, numeric, numeric, numeric), public.att_set(uuid, uuid, date, time, time, text), public.att_approve_ot(uuid, int),
  public.att_settings(uuid, boolean, date, boolean, boolean), public.att_sheet(uuid, date, date, uuid), public.riyadh_today(), public.geo_dist_m(numeric, numeric, numeric, numeric) to authenticated;
notify pgrst, 'reload schema';
