-- HR safeguards:
--  * custody (العهد) handed to employees and the clearance (إخلاء الطرف) checklist before the final settlement;
--  * Ramadan working hours (Art. 98: 6 hours a day, 36 a week, for Muslim workers) between dates set by HR;
--  * the annual overtime cap (720 hours a year, more only with the worker's written consent — HRSD).

-- ---------- custody ----------
create table public.custody_items (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  name text not null check (length(trim(name)) >= 2),
  name_en text,
  serial text,
  value numeric(12,2) check (value is null or value >= 0),
  issued_on date not null,
  status text not null default 'held' check (status in ('held','returned','lost')),
  returned_on date,
  note text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check (returned_on is null or returned_on >= issued_on)
);
create index on public.custody_items(employee_id);

create or replace function public.custody_save(p_id uuid, p_emp uuid, p_name text, p_name_en text, p_serial text, p_value numeric, p_issued date, p_note text)
returns uuid language plpgsql security definer set search_path = public as $$
declare e public.employees; c public.custody_items; rid uuid := p_id;
begin
  if p_id is not null then
    select * into c from public.custody_items where id = p_id for update;
    if not found then raise exception 'العهدة غير موجودة'; end if;
    p_emp := c.employee_id;
  end if;
  select * into e from public.employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود'; end if;
  perform public.require_role(e.company_id, array['owner','admin','hr']);
  if length(trim(coalesce(p_name, ''))) < 2 then raise exception 'اكتب اسم العهدة'; end if;
  if p_issued is null then raise exception 'حدد تاريخ التسليم'; end if;
  if p_id is null then
    insert into public.custody_items(company_id, employee_id, name, name_en, serial, value, issued_on, note)
    values (e.company_id, p_emp, trim(p_name), nullif(trim(p_name_en), ''), nullif(trim(p_serial), ''), p_value, p_issued, nullif(trim(p_note), '')) returning id into rid;
  else
    update public.custody_items set name = trim(p_name), name_en = nullif(trim(p_name_en), ''), serial = nullif(trim(p_serial), ''), value = p_value,
      issued_on = p_issued, note = nullif(trim(p_note), '') where id = p_id;
  end if;
  return rid;
end $$;

-- returned, or lost/damaged (a deduction for loss needs Art. 91: the worker's fault, investigation, max 5 days' wage a month)
create or replace function public.custody_return(p_id uuid, p_on date, p_lost boolean, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare c public.custody_items;
begin
  select * into c from public.custody_items where id = p_id for update;
  if not found then raise exception 'العهدة غير موجودة'; end if;
  perform public.require_role(c.company_id, array['owner','admin','hr']);
  if c.status <> 'held' then raise exception 'العهدة مُسلَّمة مسبقاً'; end if;
  if p_on is null or p_on < c.issued_on then raise exception 'تاريخ الاستلام قبل تاريخ التسليم'; end if;
  if coalesce(p_lost, false) and length(trim(coalesce(p_note, ''))) < 3 then raise exception 'اكتب ما حدث للعهدة'; end if;
  update public.custody_items set status = case when p_lost then 'lost' else 'returned' end, returned_on = p_on,
    note = coalesce(nullif(trim(p_note), ''), note) where id = p_id;
end $$;

-- ---------- clearance ----------
create table public.clearance_marks (
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  step text not null check (step in ('manager','it','finance','hr')),
  done_by uuid default auth.uid(),
  done_at timestamptz not null default now(),
  note text,
  primary key (employee_id, step)
);

create or replace function public.clearance_can(p_emp uuid, p_step text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.has_role(e.company_id, array['owner','admin','hr'])
      or (p_step = 'finance' and public.has_role(e.company_id, array['finance']))
      or (p_step = 'manager' and e.manager_id is not null and e.manager_id = public.my_employee(e.company_id))
    from public.employees e where e.id = p_emp
$$;

create or replace function public.clearance_status(p_emp uuid)
returns table(step text, ok boolean, detail text, done_at timestamptz, note text, can_mark boolean)
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; held int; hv numeric; adv numeric;
begin
  select * into e from public.employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود'; end if;
  if not (public.has_role(e.company_id, array['owner','admin','hr','finance']) or coalesce(e.manager_id = public.my_employee(e.company_id), false)) then
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

create or replace function public.clearance_mark(p_emp uuid, p_step text, p_done boolean, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare e public.employees;
begin
  select * into e from public.employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود'; end if;
  if p_step not in ('manager','it','finance','hr') then raise exception 'بند غير معروف'; end if;
  if not coalesce(public.clearance_can(p_emp, p_step), false) then raise exception 'غير مصرح لك بهذا البند' using errcode = '42501'; end if;
  if p_step = 'hr' and coalesce(p_done, true) and exists(select 1 from public.custody_items where employee_id = p_emp and status = 'held') then
    raise exception 'لم تُسلَّم كل العهد — استلمها أولاً'; end if;
  if coalesce(p_done, true) then
    insert into public.clearance_marks(company_id, employee_id, step, note) values (e.company_id, p_emp, p_step, nullif(trim(p_note), ''))
    on conflict (employee_id, step) do update set done_by = auth.uid(), done_at = now(), note = excluded.note;
  else
    delete from public.clearance_marks where employee_id = p_emp and step = p_step;
  end if;
end $$;

-- ---------- Ramadan hours and the overtime cap ----------
alter table public.companies add column ramadan_from date, add column ramadan_to date, add column ramadan_start time,
  add column ramadan_hours numeric(3,1) not null default 6 check (ramadan_hours between 4 and 6);
alter table public.employees add column ramadan_hours boolean not null default true,
  add column ot_over_cap boolean not null default false;

create or replace function public.ramadan_set(p_company uuid, p_from date, p_to date, p_start time, p_hours numeric) returns void
language plpgsql security definer set search_path = public as $$
declare c public.companies;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if (p_from is null) <> (p_to is null) then raise exception 'حدد بداية رمضان ونهايته'; end if;
  if p_to < p_from or p_to - p_from > 30 then raise exception 'مدة رمضان من 29 إلى 30 يوماً'; end if;
  if coalesce(p_hours, 6) < 4 or coalesce(p_hours, 6) > 6 then raise exception 'ساعات العمل في رمضان لا تزيد على 6 ساعات — م98'; end if;
  select * into c from public.companies where id = p_company;
  update public.companies set ramadan_from = p_from, ramadan_to = p_to, ramadan_start = p_start, ramadan_hours = coalesce(p_hours, 6) where id = p_company;
  perform public.att_recalc(a.id) from public.attendance a
   where a.company_id = p_company and (a.day between c.ramadan_from and c.ramadan_to or a.day between p_from and p_to);
end $$;

-- overtime hours in a calendar year: approved attendance overtime + hours entered in payroll
create or replace function public.ot_year_hours(p_emp uuid, p_year int) returns numeric
language sql stable security definer set search_path = public as $$
  select case when not exists(select 1 from public.employees e where e.id = p_emp
                and (public.has_role(e.company_id, array['owner','admin','hr','finance']) or e.id = public.my_employee(e.company_id))) then null else
         coalesce((select sum(ot_min) from public.attendance where employee_id = p_emp and extract(year from day) = p_year), 0) / 60.0
       + coalesce((select sum(l.overtime_hours) from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id where l.employee_id = p_emp and r.year = p_year), 0) end
$$;

create or replace function public.ot_cap_check(p_emp uuid, p_year int, p_add numeric) returns void
language plpgsql stable security definer set search_path = public as $$
declare used numeric; ok boolean;
begin
  if coalesce(p_add, 0) <= 0 then return; end if;
  select ot_over_cap into ok from public.employees where id = p_emp;
  if ok then return; end if;
  used := coalesce(public.ot_year_hours(p_emp, p_year), 0);
  if used + p_add > 720 then
    raise exception 'يتجاوز الحد السنوي للعمل الإضافي 720 ساعة (المستخدم % ساعة) — يلزم موافقة العامل الكتابية', round(used, 1); end if;
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
    -- Art. 98: in Ramadan, at most 6 hours a day (36 a week) for Muslim workers — the shift is shortened, never lengthened
    select * into c from public.companies where id = a.company_id;
    select a.day between c.ramadan_from and c.ramadan_to and e.ramadan_hours into rmd from public.employees e where e.id = a.employee_id;
    if coalesce(rmd, false) then
      nlen := se - ss;
      ss := public.riyadh_ts(a.day, coalesce(c.ramadan_start, s.start_time));
      se := ss + least(nlen, make_interval(mins => round(c.ramadan_hours * 60)::int));
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
  else
    extra := worked;
  end if;
  update public.attendance set sched_start = case when workday then ss end, sched_end = case when workday then se end,
    late_min = late - cov_l, early_min = early - cov_e, permit_min = cov_l + cov_e, worked_min = worked, extra_min = extra, ot_min = least(ot_min, extra)
   where id = p_id;
end $$;

create or replace function public.att_approve_ot(p_id uuid, p_minutes int) returns void
language plpgsql security definer set search_path = public as $$
declare a public.attendance;
begin
  select * into a from public.attendance where id = p_id;
  if not found then raise exception 'السجل غير موجود'; end if;
  perform public.require_role(a.company_id, array['owner','admin','hr']);
  if p_minutes < 0 or p_minutes + a.ot_comp_min > a.extra_min then raise exception 'الإضافي المعتمد بين 0 و% دقيقة', a.extra_min - a.ot_comp_min; end if;
  if exists(select 1 from public.payroll_runs r where r.company_id = a.company_id and r.status <> 'draft'
            and make_date(r.year, r.month, 1) <= a.day and a.day < make_date(r.year, r.month, 1) + interval '1 month') then
    raise exception 'مسير هذا الشهر معتمد — لا يمكن تعديل الإضافي'; end if;
  perform public.ot_cap_check(a.employee_id, extract(year from a.day)::int, (p_minutes - a.ot_min) / 60.0);
  update public.attendance set ot_min = p_minutes, updated_by = auth.uid(), updated_at = now() where id = p_id;
end $$;

create or replace function public.payroll_set_line(p_run uuid, p_emp uuid, p_ot_hours numeric, p_bonus numeric, p_fines numeric, p_damages numeric default 0)
returns void language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; g numeric; l public.payroll_lines;
begin
  select * into r from public.payroll_runs where id = p_run;
  perform public.require_role(r.company_id, array['hr','admin','owner']);
  if r.status <> 'draft' then raise exception 'المسير معتمد ولا يمكن تعديله'; end if;
  select gross into g from public.payroll_lines where run_id = p_run and employee_id = p_emp;
  if not found then raise exception 'الموظف غير موجود في المسير'; end if;
  if coalesce(p_fines,0) > round(g / 30 * 5, 2) then raise exception 'الغرامات لا تزيد على أجر 5 أيام في الشهر (%) — م70', round(g / 30 * 5, 2); end if;
  if coalesce(p_damages,0) > round(g / 30 * 5, 2) then raise exception 'اقتطاع التلفيات لا يزيد على أجر 5 أيام في الشهر (%) — م91', round(g / 30 * 5, 2); end if;
  if coalesce(p_ot_hours,0) < 0 or coalesce(p_bonus,0) < 0 or coalesce(p_fines,0) < 0 or coalesce(p_damages,0) < 0 then raise exception 'القيم لا تكون سالبة'; end if;
  select * into l from public.payroll_lines where run_id = p_run and employee_id = p_emp;
  if l.gosi + coalesce(p_fines,0) + coalesce(p_damages,0) > round(g * 0.5, 2) then
    raise exception 'مجموع الحسميات لا يتجاوز نصف الأجر — م93'; end if;
  perform public.ot_cap_check(p_emp, r.year, coalesce(p_ot_hours,0) - l.overtime_hours);
  update public.payroll_lines set overtime_hours = coalesce(p_ot_hours,0), bonus = coalesce(p_bonus,0), deductions = coalesce(p_fines,0), damages = coalesce(p_damages,0)
   where run_id = p_run and employee_id = p_emp;
  perform public.payroll_line_recalc(p_run, p_emp);
end $$;

-- ---------- RLS, audit, grants ----------
create trigger audit_custody after insert or update or delete on public.custody_items for each row execute function public.audit_trigger();
create trigger audit_clearance after insert or update or delete on public.clearance_marks for each row execute function public.audit_trigger();
alter table public.custody_items enable row level security;
alter table public.clearance_marks enable row level security;
create policy cu_read on public.custody_items for select using (public.has_role(company_id, array['owner','admin','hr','finance']) or employee_id = public.my_employee(company_id));
create policy cm_read on public.clearance_marks for select using (public.has_role(company_id, array['owner','admin','hr','finance']) or employee_id = public.my_employee(company_id));
revoke all on public.custody_items, public.clearance_marks from anon;
grant select on public.custody_items, public.clearance_marks to authenticated;
revoke insert, update, delete on public.custody_items, public.clearance_marks from authenticated;
revoke all on function public.ot_cap_check(uuid, int, numeric), public.clearance_can(uuid, text) from public, anon, authenticated;
revoke all on function public.custody_save(uuid, uuid, text, text, text, numeric, date, text), public.custody_return(uuid, date, boolean, text),
  public.clearance_status(uuid), public.clearance_mark(uuid, text, boolean, text), public.ramadan_set(uuid, date, date, time, numeric), public.ot_year_hours(uuid, int) from public, anon;
grant execute on function public.custody_save(uuid, uuid, text, text, text, numeric, date, text), public.custody_return(uuid, date, boolean, text),
  public.clearance_status(uuid), public.clearance_mark(uuid, text, boolean, text), public.ramadan_set(uuid, date, date, time, numeric), public.ot_year_hours(uuid, int) to authenticated;
notify pgrst, 'reload schema';
