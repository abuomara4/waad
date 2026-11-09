-- Shift schedules (e.g. 01:00–09:00, 02:00–10:00, 03:00–11:00, each with its break), a Ramadan time for each shift,
-- and assignment by employee or by department.
--  * Art. 98: at most 8 working hours a day (break excluded); in Ramadan at most 6 for Muslim workers only.
--  * Art. 101: breaks are not working time.
--  * Effective shift: the employee's own shift, else the department's, else the company default.

alter table public.employees rename column ramadan_hours to is_muslim;   -- Ramadan hours apply to Muslim workers only (Art. 98)

alter table public.shifts add column break_min int not null default 0 check (break_min between 0 and 180),
                          add column ramadan_start time, add column ramadan_end time,
                          add constraint shifts_ramadan_both check ((ramadan_start is null) = (ramadan_end is null));
alter table public.departments add column shift_id uuid references public.shifts(id) on delete set null;

-- minutes from a start to an end time (an end at or before the start is the next day)
create or replace function public.span_min(p_start time, p_end time) returns int language sql immutable as $$
  select (extract(epoch from (p_end - p_start)) / 60)::int + case when p_end <= p_start then 1440 else 0 end
$$;

create or replace function public.shift_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if public.span_min(new.start_time, new.end_time) - new.break_min > 480 then
    raise exception 'ساعات العمل في الوردية لا تزيد على 8 ساعات بعد خصم الراحة — م98'; end if;
  if new.break_min >= public.span_min(new.start_time, new.end_time) then raise exception 'مدة الراحة أطول من الوردية'; end if;
  if new.ramadan_start is not null then
    if new.ramadan_start = new.ramadan_end then raise exception 'وقت رمضان: البداية تساوي النهاية'; end if;
    if public.span_min(new.ramadan_start, new.ramadan_end) - new.break_min > 360 then
      raise exception 'دوام رمضان لا يزيد على 6 ساعات بعد خصم الراحة — م98'; end if;
  end if;
  return new;
end $$;
create trigger shift_guard before insert or update of start_time, end_time, break_min, ramadan_start, ramadan_end on public.shifts
  for each row execute function public.shift_guard();

create or replace function public.department_shift_guard() returns trigger language plpgsql set search_path = public as $$
begin
  if new.shift_id is not null and not exists(select 1 from public.shifts s where s.id = new.shift_id and s.company_id = new.company_id) then
    raise exception 'الوردية ليست من المنشأة'; end if;
  return new;
end $$;
create trigger department_shift_guard before insert or update of shift_id on public.departments for each row execute function public.department_shift_guard();

create or replace function public.employee_shift(p_emp uuid) returns public.shifts language sql stable security definer set search_path = public as $$
  select s.* from public.employees e
    left join public.departments d on d.id = e.department_id
    join public.shifts s on s.company_id = e.company_id
   where e.id = p_emp and (s.id = e.shift_id or s.id = d.shift_id or s.is_default)
   order by coalesce(s.id = e.shift_id, false) desc, coalesce(s.id = d.shift_id, false) desc limit 1
$$;

-- HR assigns a shift to every employee of a department (their own shift is cleared so the department's applies)
create or replace function public.department_shift_set(p_dept uuid, p_shift uuid, p_override boolean default false) returns int
language plpgsql security definer set search_path = public as $$
declare d public.departments; n int := 0;
begin
  select * into d from public.departments where id = p_dept;
  if not found then raise exception 'القسم غير موجود'; end if;
  perform public.require_role(d.company_id, array['owner','admin','hr']);
  update public.departments set shift_id = p_shift where id = p_dept;
  if coalesce(p_override, false) then
    update public.employees set shift_id = null where department_id = p_dept and shift_id is not null;
    get diagnostics n = row_count;
  end if;
  return n;
end $$;

create or replace function public.att_recalc(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare a public.attendance; s public.shifts; ss timestamptz; se timestamptz; workday boolean; late int := 0; early int := 0; worked int := 0; extra int := 0;
        pm int := 0; cov_l int := 0; cov_e int := 0; c public.companies; rmd boolean; nlen interval;
begin
  select * into a from public.attendance where id = p_id;
  select * into s from public.shifts where id = a.shift_id;
  workday := s.id is not null and extract(dow from a.day)::int = any(s.work_days)
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

revoke all on function public.shift_guard(), public.department_shift_guard() from public, anon, authenticated;
revoke all on function public.department_shift_set(uuid, uuid, boolean) from public, anon;
grant execute on function public.department_shift_set(uuid, uuid, boolean) to authenticated;
notify pgrst, 'reload schema';
