-- HR batch: weekly shift rosters (rotation by employee or department), bulk salary raise, policy acknowledgements,
-- overtime consent per year, and the HR dashboard.

-- ---------- shift roster: a shift (or a day off) for an employee on a given day ----------
create table public.shift_roster (
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  day date not null,
  shift_id uuid references public.shifts(id) on delete cascade,
  off boolean not null default false,
  created_by uuid default auth.uid(),
  primary key (employee_id, day),
  check (off or shift_id is not null)
);
create index on public.shift_roster(company_id, day);

-- the shift that applies on a day: the roster, else the employee's / department's / default shift
create or replace function public.employee_shift_on(p_emp uuid, p_day date) returns public.shifts
language plpgsql stable security definer set search_path = public as $$
declare r public.shift_roster; s public.shifts;
begin
  select * into r from public.shift_roster where employee_id = p_emp and day = p_day;
  if found then
    if r.off then return null; end if;
    select * into s from public.shifts where id = r.shift_id; return s;
  end if;
  return public.employee_shift(p_emp);
end $$;

create or replace function public.is_workday(p_emp uuid, p_day date) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare r public.shift_roster; s public.shifts;
begin
  select * into r from public.shift_roster where employee_id = p_emp and day = p_day;
  if found then return not r.off and r.shift_id is not null; end if;
  s := public.employee_shift(p_emp);
  return s.id is not null and extract(dow from p_day)::int = any(s.work_days);
end $$;

-- assign a rotation: the shifts in order (null = day off), changing every p_every days
create or replace function public.roster_assign(p_company uuid, p_emps uuid[], p_from date, p_to date, p_shifts uuid[], p_every int default 7) returns int
language plpgsql security definer set search_path = public as $$
declare d date; n int := 0; k int; sh uuid; e uuid; a public.attendance;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if p_from is null or p_to is null or p_to < p_from then raise exception 'حدد الفترة'; end if;
  if p_to - p_from > 366 then raise exception 'الفترة لا تزيد على سنة'; end if;
  if coalesce(cardinality(p_emps), 0) = 0 then raise exception 'اختر موظفاً واحداً على الأقل'; end if;
  if coalesce(cardinality(p_shifts), 0) = 0 then raise exception 'اختر وردية واحدة على الأقل'; end if;
  if coalesce(p_every, 0) < 1 or p_every > 31 then raise exception 'التبديل كل 1 إلى 31 يوماً'; end if;
  if exists(select 1 from unnest(p_shifts) x where x is not null and not exists(select 1 from public.shifts s where s.id = x and s.company_id = p_company)) then
    raise exception 'الوردية ليست من المنشأة'; end if;
  if exists(select 1 from unnest(p_emps) x where not exists(select 1 from public.employees m where m.id = x and m.company_id = p_company)) then
    raise exception 'الموظف غير موجود في المنشأة'; end if;
  foreach e in array p_emps loop
    d := p_from;
    while d <= p_to loop
      k := ((d - p_from) / p_every) % cardinality(p_shifts) + 1;
      sh := p_shifts[k];
      insert into public.shift_roster(company_id, employee_id, day, shift_id, off) values (p_company, e, d, sh, sh is null)
      on conflict (employee_id, day) do update set shift_id = excluded.shift_id, off = excluded.off, created_by = auth.uid();
      -- a day already recorded follows the new shift
      select * into a from public.attendance where employee_id = e and day = d;
      if found then update public.attendance set shift_id = coalesce(sh, shift_id) where id = a.id; perform public.att_recalc(a.id); end if;
      n := n + 1; d := d + 1;
    end loop;
  end loop;
  return n;
end $$;

create or replace function public.roster_clear(p_company uuid, p_emps uuid[], p_from date, p_to date) returns int
language plpgsql security definer set search_path = public as $$
declare n int; a record;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  delete from public.shift_roster where company_id = p_company and employee_id = any(p_emps) and day between p_from and p_to;
  get diagnostics n = row_count;
  for a in select x.id, x.employee_id from public.attendance x where x.company_id = p_company and x.employee_id = any(p_emps) and x.day between p_from and p_to loop
    update public.attendance set shift_id = coalesce((public.employee_shift(a.employee_id)).id, shift_id) where id = a.id;
    perform public.att_recalc(a.id);
  end loop;
  return n;
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
  s := public.employee_shift_on(me, d);
  insert into public.attendance(company_id, employee_id, day, shift_id, check_in, in_lat, in_lng, in_acc, in_site)
  values (p_company, me, d, s.id, now(), p_lat, p_lng, p_acc, site) returning id into rid;
  perform public.att_recalc(rid);
  select * into a from public.attendance where id = rid;
  return jsonb_build_object('action', 'in', 'at', a.check_in, 'late_min', a.late_min, 'shift', s.name);
end $$;

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
    s := public.employee_shift_on(p_emp, p_day);
    insert into public.attendance(company_id, employee_id, day, shift_id, check_in, check_out, source, note)
    values (p_company, p_emp, p_day, s.id, ti, tout, 'hr', trim(p_note)) returning id into rid;
  else
    update public.attendance set check_in = ti, check_out = tout, source = 'hr', note = trim(p_note), updated_by = auth.uid(), updated_at = now() where id = rid;
  end if;
  perform public.att_recalc(rid);
end $$;

create or replace function public.punch_apply(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.requests; a public.attendance; s public.shifts; ti timestamptz; tout timestamptz; aid uuid; why text;
begin
  select * into r from public.requests where id = p_id;
  select * into a from public.attendance where employee_id = r.employee_id and day = r.from_date;
  ti := case when r.payload->>'in' is not null then public.riyadh_ts(r.from_date, (r.payload->>'in')::time) else a.check_in end;
  if ti is null then raise exception 'لا يوجد وقت حضور لهذا اليوم'; end if;
  if r.payload->>'out' is not null then
    tout := public.riyadh_ts(r.from_date, (r.payload->>'out')::time);
    if tout <= ti then tout := tout + interval '1 day'; end if;      -- a night shift ends the next day
  else tout := a.check_out; end if;
  if tout is not null and tout <= ti then raise exception 'وقت الانصراف قبل وقت الحضور'; end if;
  why := 'نسيان بصمة — طلب معتمد';
  if a.id is null then
    s := public.employee_shift_on(r.employee_id, r.from_date);
    insert into public.attendance(company_id, employee_id, day, shift_id, check_in, check_out, source, note)
    values (r.company_id, r.employee_id, r.from_date, s.id, ti, tout, 'request', why) returning id into aid;
  else
    update public.attendance set check_in = ti, check_out = tout, source = 'request', note = why, updated_at = now() where id = a.id;
    aid := a.id;
  end if;
  perform public.att_recalc(aid);
end $$;

create or replace function public.att_month(p_emp uuid, p_ms date, p_me date)
returns table(absent_days int, late_min int, ot_min int) language sql stable security definer set search_path = public as $$
  with e as (select * from public.employees where id = p_emp), c as (select x.* from public.companies x join e on x.id = e.company_id),
  days as (select g::date d from generate_series(greatest(p_ms, (select hire_date from e), coalesce((select att_start from c), p_me + 1)),
                                                  least(p_me, coalesce((select end_date from e), p_me), public.riyadh_today() - 1), interval '1 day') g)
  select
    (select count(*)::int from days where (select att_enabled from c) and not (select att_exempt from e)
       and public.is_workday(p_emp, days.d)
       and not exists(select 1 from public.holidays h where h.company_id = (select company_id from e) and h.day = days.d)
       and not exists(select 1 from public.attendance a where a.employee_id = p_emp and a.day = days.d)
       and not exists(select 1 from public.requests q where q.employee_id = p_emp and q.kind = 'leave' and q.status = 'approved' and days.d between q.from_date and q.to_date)),
    (select coalesce(sum(a.late_min), 0)::int from public.attendance a where a.employee_id = p_emp and a.day between p_ms and p_me),
    (select coalesce(sum(a.ot_min), 0)::int from public.attendance a where a.employee_id = p_emp and a.day between p_ms and p_me)
$$;

drop function public.att_sheet(uuid, date, date, uuid);
create or replace function public.att_sheet(p_company uuid, p_from date, p_to date, p_emp uuid default null)
returns table(employee_id uuid, day date, status text, leave_sub text, att_id uuid, check_in timestamptz, check_out timestamptz,
              late_min int, early_min int, worked_min int, extra_min int, ot_min int, source text, note text, permit_min int)
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
      when not public.is_workday(e.id, dd.d) then 'off'
      when not c.att_enabled or c.att_start is null or dd.d < c.att_start then 'na'
      when dd.d = td then 'pending'
      else 'absent' end,
    lv.sub, a.id, a.check_in, a.check_out, a.late_min, a.early_min, a.worked_min, a.extra_min, a.ot_min, a.source, a.note, a.permit_min
  from emps e cross join days dd
  left join public.attendance a on a.employee_id = e.id and a.day = dd.d
  left join public.holidays h on h.company_id = p_company and h.day = dd.d
  left join lateral (select q.sub from public.requests q where q.employee_id = e.id and q.kind = 'leave' and q.status = 'approved'
                     and dd.d between q.from_date and q.to_date limit 1) lv on true
  left join lateral (select * from public.employee_shift_on(e.id, dd.d)) s on true
  where dd.d >= e.hire_date - 0 or a.id is not null
  order by e.emp_no, dd.d;
end $$;

create or replace function public.att_recalc(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare a public.attendance; s public.shifts; ss timestamptz; se timestamptz; workday boolean; late int := 0; early int := 0; worked int := 0; extra int := 0;
        pm int := 0; cov_l int := 0; cov_e int := 0; c public.companies; rmd boolean; nlen interval;
begin
  select * into a from public.attendance where id = p_id;
  select * into s from public.shifts where id = a.shift_id;
  workday := s.id is not null and public.is_workday(a.employee_id, a.day)
             and not exists(select 1 from public.holidays h where h.company_id = a.company_id and h.day = a.day);
  if s.id is not null then
    ss := public.riyadh_ts(a.day, s.start_time);
    se := public.riyadh_ts(a.day + case when s.end_time <= s.start_time then 1 else 0 end, s.end_time);
    -- Art. 98: in Ramadan, Muslim workers follow the shift's Ramadan time (or the company's Ramadan start + hours)
    select * into c from public.companies where id = a.company_id;
    select a.day between c.ramadan_from and c.ramadan_to and e.is_muslim into rmd from public.employees e where e.id = a.employee_id;
    if coalesce(rmd, false) then
      if s.ramadan_start is not null then
        ss := public.riyadh_ts(a.day, s.ramadan_start);
        se := public.riyadh_ts(a.day + case when s.ramadan_end <= s.ramadan_start then 1 else 0 end, s.ramadan_end);
      else
        nlen := se - ss;
        ss := public.riyadh_ts(a.day, coalesce(c.ramadan_start, s.start_time));
        se := ss + least(nlen, make_interval(mins => round(c.ramadan_hours * 60)::int + s.break_min));
      end if;
    end if;
  end if;
  if a.check_out is not null then worked := floor(extract(epoch from a.check_out - a.check_in) / 60); end if;
  if workday then
    if a.check_in > ss + make_interval(mins => s.grace_min) then late := ceil(extract(epoch from a.check_in - ss) / 60); end if;
    if a.check_out is not null and a.check_out < se then early := ceil(extract(epoch from se - a.check_out) / 60); end if;
    if a.check_out is not null and a.check_out > se then extra := floor(extract(epoch from a.check_out - greatest(se, a.check_in)) / 60); end if;
    select coalesce(sum(round(coalesce((r.payload->>'hours')::numeric, 0) * 60)), 0)::int into pm
      from public.requests r where r.employee_id = a.employee_id and r.kind = 'permit' and r.status = 'approved' and r.from_date = a.day;
    cov_l := least(late, pm); cov_e := least(early, pm - cov_l);
    if worked > 300 then worked := worked - s.break_min; end if;   -- Art. 101: the break (due after 5 hours) is not working time
  else
    extra := worked;
  end if;
  update public.attendance set sched_start = case when workday then ss end, sched_end = case when workday then se end,
    late_min = late - cov_l, early_min = early - cov_e, permit_min = cov_l + cov_e, worked_min = worked, extra_min = extra, ot_min = least(ot_min, extra)
   where id = p_id;
end $$;

-- ---------- bulk salary raise (a raise needs no consent; recorded in the salary history with its reason) ----------
create or replace function public.salary_raise_bulk(p_company uuid, p_emps uuid[], p_pct numeric, p_amount numeric, p_housing boolean, p_effective date, p_reason text)
returns int language plpgsql security definer set search_path = public as $$
declare e public.employees; n int := 0; nb numeric; nh numeric;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if coalesce(p_pct, 0) < 0 or coalesce(p_amount, 0) < 0 then raise exception 'الزيادة الجماعية لا تكون بالسالب — التخفيض يحتاج موافقة كل عامل'; end if;
  if coalesce(p_pct, 0) = 0 and coalesce(p_amount, 0) = 0 then raise exception 'حدد نسبة أو مبلغ الزيادة'; end if;
  if coalesce(p_pct, 0) > 100 then raise exception 'النسبة حتى 100%%'; end if;
  for e in select * from public.employees where company_id = p_company and id = any(p_emps) and (end_date is null or end_date >= current_date) loop
    nb := round(e.basic * (1 + coalesce(p_pct, 0) / 100) + coalesce(p_amount, 0), 2);
    nh := case when coalesce(p_housing, false) then round(e.housing * (1 + coalesce(p_pct, 0) / 100), 2) else e.housing end;
    perform public.salary_change(e.id, nb, nh, e.transport, p_effective, p_reason);
    n := n + 1;
  end loop;
  if n = 0 then raise exception 'لا يوجد موظفون على رأس العمل في الاختيار'; end if;
  return n;
end $$;

-- ---------- policies and acknowledgements ----------
create table public.policies (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null check (length(trim(title)) >= 3),
  title_en text,
  body text not null check (length(trim(body)) >= 10),
  body_en text,
  active boolean not null default true,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create table public.policy_acks (
  policy_id uuid not null references public.policies(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  acked_at timestamptz not null default now(),
  primary key (policy_id, employee_id)
);

create or replace function public.policy_save(p_company uuid, p_id uuid, p_title text, p_title_en text, p_body text, p_body_en text, p_active boolean) returns uuid
language plpgsql security definer set search_path = public as $$
declare rid uuid := p_id;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if length(trim(coalesce(p_title, ''))) < 3 then raise exception 'اكتب عنوان السياسة'; end if;
  if length(trim(coalesce(p_body, ''))) < 10 then raise exception 'اكتب نص السياسة'; end if;
  if p_id is null then
    insert into public.policies(company_id, title, title_en, body, body_en, active) values (p_company, trim(p_title), nullif(trim(p_title_en), ''), trim(p_body), nullif(trim(p_body_en), ''), coalesce(p_active, true)) returning id into rid;
  else
    -- a changed text needs a new acknowledgement from everyone
    if exists(select 1 from public.policies where id = p_id and company_id = p_company and body is distinct from trim(p_body)) then delete from public.policy_acks where policy_id = p_id; end if;
    update public.policies set title = trim(p_title), title_en = nullif(trim(p_title_en), ''), body = trim(p_body), body_en = nullif(trim(p_body_en), ''), active = coalesce(p_active, true)
     where id = p_id and company_id = p_company;
    if not found then raise exception 'السياسة غير موجودة'; end if;
  end if;
  return rid;
end $$;

create or replace function public.policy_ack(p_policy uuid) returns void
language plpgsql security definer set search_path = public as $$
declare p public.policies; me uuid;
begin
  select * into p from public.policies where id = p_policy and active;
  if not found then raise exception 'السياسة غير موجودة'; end if;
  me := public.my_employee(p.company_id);
  if me is null then raise exception 'حسابك غير مربوط بسجل موظف' using errcode = '42501'; end if;
  insert into public.policy_acks(policy_id, company_id, employee_id) values (p_policy, p.company_id, me) on conflict do nothing;
end $$;

-- ---------- overtime above 720 hours: the worker's consent is for one calendar year ----------
alter table public.employees add column ot_consent_year int;
update public.employees set ot_consent_year = extract(year from current_date)::int where ot_over_cap;
alter table public.employees drop column ot_over_cap;
create or replace function public.ot_cap_check(p_emp uuid, p_year int, p_add numeric) returns void
language plpgsql stable security definer set search_path = public as $$
declare used numeric; cy int;
begin
  if coalesce(p_add, 0) <= 0 then return; end if;
  select ot_consent_year into cy from public.employees where id = p_emp;
  if cy = p_year then return; end if;
  used := coalesce(public.ot_year_hours(p_emp, p_year), 0);
  if used + p_add > 720 then
    raise exception 'يتجاوز الحد السنوي للعمل الإضافي 720 ساعة (المستخدم % ساعة) — يلزم موافقة العامل الكتابية لسنة %', round(used, 1), p_year; end if;
end $$;

-- ---------- HR dashboard (one call) ----------
create or replace function public.hr_dashboard(p_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare td date := public.riyadh_today(); r jsonb := '{}'; m date; hc int; j int; l int; avg_hc numeric := 0; leavers12 int := 0; months jsonb := '[]';
begin
  if not public.has_role(p_company, array['owner','admin','hr','finance']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  -- people
  select jsonb_build_object('active', count(*), 'saudi', count(*) filter (where is_saudi), 'female', count(*) filter (where gender = 'f'),
           'probation', count(*) filter (where probation_end >= td), 'avg_wage', round(coalesce(avg(basic + housing + transport), 0), 2))
    into r from public.employees where company_id = p_company and hire_date <= td and (end_date is null or end_date >= td);
  r := r || jsonb_build_object('by_dept', coalesce((select jsonb_agg(jsonb_build_object('name', coalesce(d.name, '—'), 'name_en', d.name_en, 'n', x.n) order by x.n desc)
           from (select department_id, count(*) n from public.employees where company_id = p_company and hire_date <= td and (end_date is null or end_date >= td) group by 1) x
           left join public.departments d on d.id = x.department_id), '[]'));
  -- 12 months: joiners, leavers, headcount at month end
  for i in reverse 11..0 loop
    m := (date_trunc('month', td) - make_interval(months => i))::date;
    select count(*) filter (where hire_date between m and (m + interval '1 month - 1 day')::date),
           count(*) filter (where end_date between m and (m + interval '1 month - 1 day')::date),
           count(*) filter (where hire_date <= (m + interval '1 month - 1 day')::date and (end_date is null or end_date > (m + interval '1 month - 1 day')::date))
      into j, l, hc from public.employees where company_id = p_company;
    months := months || jsonb_build_object('m', to_char(m, 'YYYY-MM'), 'joins', j, 'leaves', l, 'hc', hc);
    avg_hc := avg_hc + hc; leavers12 := leavers12 + l;
  end loop;
  r := r || jsonb_build_object('months', months, 'turnover', case when avg_hc > 0 then round(leavers12 / (avg_hc / 12) * 100, 1) else 0 end);
  -- today's attendance
  r := r || jsonb_build_object('today', (select jsonb_build_object('expected', count(*) filter (where s.status <> 'off' and s.status <> 'holiday' and s.status <> 'leave' and s.status <> 'na'),
           'present', count(*) filter (where s.status in ('present','late','open','nocheckout')), 'late', count(*) filter (where s.status = 'late'),
           'leave', count(*) filter (where s.status = 'leave'))
         from public.att_sheet(p_company, td, td) s));
  -- requests waiting
  r := r || jsonb_build_object('pending', coalesce((select jsonb_object_agg(kind, n) from (select kind, count(*) n from public.requests where company_id = p_company and status = 'pending' group by 1) x), '{}'));
  -- payroll cost of the last 6 payrolls
  r := r || jsonb_build_object('payroll', coalesce((select jsonb_agg(x order by x->>'p') from (
           select jsonb_build_object('p', pr.year || '-' || lpad(pr.month::text, 2, '0'), 'status', pr.status,
                  'gross', sum(pl.gross + pl.arrears + pl.overtime + pl.bonus), 'net', sum(pl.net), 'employer_gosi', sum(pl.employer_gosi), 'n', count(*)) x
             from public.payroll_runs pr join public.payroll_lines pl on pl.run_id = pr.id
            where pr.company_id = p_company group by pr.id order by pr.year desc, pr.month desc limit 6) q), '[]'));
  -- what needs attention
  r := r || jsonb_build_object(
    'docs30', case when public.has_role(p_company, array['owner','admin','hr']) then (select count(*) from public.doc_alerts(p_company, 30) a where a.level in ('expired','d30')) end,
    'leave_high', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.full_name, 'name_en', e.full_name_en, 'days', b.balance) order by b.balance desc)
        from public.employees e cross join lateral public.annual_leave_balance(e.id, td) b
       where e.company_id = p_company and (e.end_date is null or e.end_date >= td) and b.balance > 30), '[]'),
    'ot_near_cap', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.full_name, 'name_en', e.full_name_en, 'hours', round(h, 1)) order by h desc)
        from public.employees e cross join lateral (select public.ot_year_hours(e.id, extract(year from td)::int) h) x
       where e.company_id = p_company and (e.end_date is null or e.end_date >= td) and h >= 600), '[]'),
    'comp_expiring', coalesce((select jsonb_agg(jsonb_build_object('id', e.id, 'name', e.full_name, 'name_en', e.full_name_en, 'hours', b.balance_hours, 'use_by', c.use_by))
        from public.employees e cross join lateral public.comp_balance(e.id) b
        cross join lateral (select min(use_by) use_by from public.comp_credits cc where cc.employee_id = e.id and cc.use_by >= td) c
       where e.company_id = p_company and (e.end_date is null or e.end_date >= td) and b.balance_hours > 0 and c.use_by <= td + 14), '[]'),
    'clearance_open', (select count(*) from public.employees e where e.company_id = p_company and e.end_date between td - 90 and td + 30
        and ((select count(*) from public.clearance_marks k where k.employee_id = e.id) < 4 or exists(select 1 from public.custody_items ci where ci.employee_id = e.id and ci.status = 'held'))),
    'policies_unacked', (select count(*) from public.policies p cross join public.employees e
        where p.company_id = p_company and p.active and e.company_id = p_company and (e.end_date is null or e.end_date >= td)
          and not exists(select 1 from public.policy_acks a where a.policy_id = p.id and a.employee_id = e.id)));
  return r;
end $$;

-- ---------- RLS, audit, grants ----------
create trigger audit_roster after insert or update or delete on public.shift_roster for each row execute function public.audit_trigger();
create trigger audit_policies after insert or update or delete on public.policies for each row execute function public.audit_trigger();
alter table public.shift_roster enable row level security;
alter table public.policies enable row level security;
alter table public.policy_acks enable row level security;
create policy sr_read on public.shift_roster for select using (public.has_role(company_id, array['owner','admin','hr','finance'])
  or employee_id = public.my_employee(company_id) or exists(select 1 from public.employees x where x.id = employee_id and x.manager_id = public.my_employee(company_id)));
create policy po_read on public.policies for select using (public.is_member(company_id) and (active or public.has_role(company_id, array['owner','admin','hr'])));
create policy pa_read on public.policy_acks for select using (public.has_role(company_id, array['owner','admin','hr']) or employee_id = public.my_employee(company_id));
revoke all on public.shift_roster, public.policies, public.policy_acks from anon;
grant select on public.shift_roster, public.policies, public.policy_acks to authenticated;
revoke insert, update, delete on public.shift_roster, public.policies, public.policy_acks from authenticated;
revoke all on function public.att_sheet(uuid, date, date, uuid) from public, anon;
grant execute on function public.att_sheet(uuid, date, date, uuid) to authenticated;
revoke all on function public.employee_shift_on(uuid, date), public.is_workday(uuid, date) from public, anon, authenticated;
revoke all on function public.roster_assign(uuid, uuid[], date, date, uuid[], int), public.roster_clear(uuid, uuid[], date, date), public.salary_raise_bulk(uuid, uuid[], numeric, numeric, boolean, date, text),
  public.policy_save(uuid, uuid, text, text, text, text, boolean), public.policy_ack(uuid), public.hr_dashboard(uuid) from public, anon;
grant execute on function public.roster_assign(uuid, uuid[], date, date, uuid[], int), public.roster_clear(uuid, uuid[], date, date), public.salary_raise_bulk(uuid, uuid[], numeric, numeric, boolean, date, text),
  public.policy_save(uuid, uuid, text, text, text, text, boolean), public.policy_ack(uuid), public.hr_dashboard(uuid) to authenticated;
notify pgrst, 'reload schema';
