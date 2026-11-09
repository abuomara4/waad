-- An approved permit (استئذان) excuses lateness and early leave on its day, up to its hours: it first covers the late
-- minutes, then the early-leave minutes. The covered minutes are kept in permit_min so the sheet can say why.
alter table public.attendance add column permit_min int not null default 0;

create or replace function public.att_recalc(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare a public.attendance; s public.shifts; ss timestamptz; se timestamptz; workday boolean; late int := 0; early int := 0; worked int := 0; extra int := 0;
        pm int := 0; cov_l int := 0; cov_e int := 0;
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
    select coalesce(sum(round(coalesce((r.payload->>'hours')::numeric, 0) * 60)), 0)::int into pm
      from public.requests r where r.employee_id = a.employee_id and r.kind = 'permit' and r.status = 'approved' and r.from_date = a.day;
    cov_l := least(late, pm); cov_e := least(early, pm - cov_l);
  else
    extra := worked;
  end if;
  update public.attendance set sched_start = case when workday then ss end, sched_end = case when workday then se end,
    late_min = late - cov_l, early_min = early - cov_e, permit_min = cov_l + cov_e, worked_min = worked, extra_min = extra, ot_min = least(ot_min, extra)
   where id = p_id;
end $$;

-- approving or cancelling a permit re-evaluates that day's attendance
create or replace function public.permit_att_sync() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'permit' and new.status is distinct from old.status then
    perform public.att_recalc(a.id) from public.attendance a where a.employee_id = new.employee_id and a.day = new.from_date;
  end if;
  return new;
end $$;
create trigger requests_permit_att after update of status on public.requests for each row execute function public.permit_att_sync();

revoke all on function public.att_recalc(uuid), public.permit_att_sync() from public, anon, authenticated;
do $$ begin
  perform public.att_recalc(a.id) from public.attendance a
   where exists(select 1 from public.requests r where r.employee_id = a.employee_id and r.kind = 'permit' and r.status = 'approved' and r.from_date = a.day);
end $$;

-- the attendance sheet also reports the minutes a permit covered
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
      when s.id is null or not (extract(dow from dd.d)::int = any(s.work_days)) then 'off'
      when not c.att_enabled or c.att_start is null or dd.d < c.att_start then 'na'
      when dd.d = td then 'pending'
      else 'absent' end,
    lv.sub, a.id, a.check_in, a.check_out, a.late_min, a.early_min, a.worked_min, a.extra_min, a.ot_min, a.source, a.note, a.permit_min
  from emps e cross join days dd
  left join public.attendance a on a.employee_id = e.id and a.day = dd.d
  left join public.holidays h on h.company_id = p_company and h.day = dd.d
  left join lateral (select q.sub from public.requests q where q.employee_id = e.id and q.kind = 'leave' and q.status = 'approved'
                     and dd.d between q.from_date and q.to_date limit 1) lv on true
  left join lateral (select * from public.employee_shift(e.id)) s on true
  where dd.d >= e.hire_date - 0 or a.id is not null
  order by e.emp_no, dd.d;
end $$;
revoke all on function public.att_sheet(uuid, date, date, uuid) from public, anon;
grant execute on function public.att_sheet(uuid, date, date, uuid) to authenticated;
notify pgrst, 'reload schema';
