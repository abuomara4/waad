-- Attendance: HR may let a chosen employee (desk or remote work) check in from any place, from the phone or the website,
-- while the company's work-site location check stays on for everyone else.
alter table public.employees add column if not exists att_any_place boolean not null default false;

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
  if c.att_geofence and not e.att_any_place and exists(select 1 from public.work_sites where company_id = p_company) then
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

notify pgrst, 'reload schema';
