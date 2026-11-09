-- Company limits per month (internal regulation, not the Labor Law): permit (استئذان) hours and forgotten-fingerprint
-- requests (نسيان بصمة). The month is the payroll month: with a payroll cutoff of 21, 21 Sep – 20 Oct is "October".
-- Exam leave (Art. 115): exam days are paid; only a repeated year's exams are unpaid.

alter table public.companies add column permit_hours_month numeric(5,2) check (permit_hours_month > 0 and permit_hours_month <= 200),
                             add column punch_fix_month int check (punch_fix_month between 0 and 31);
alter table public.requests drop constraint requests_kind_check;
alter table public.requests add constraint requests_kind_check check (kind in ('leave','permit','cert','advance','resign','settle','expense','update','punch'));
alter table public.attendance drop constraint attendance_source_check;
alter table public.attendance add constraint attendance_source_check check (source in ('self','hr','request'));

-- the payroll month that contains a day (internal)
create or replace function public.att_month_of(p_company uuid, p_day date) returns table(ps date, pe date)
language sql stable security definer set search_path = public as $$
  select case when c.payroll_cutoff is null then date_trunc('month', p_day)::date
              when extract(day from p_day) >= c.payroll_cutoff then make_date(extract(year from p_day)::int, extract(month from p_day)::int, c.payroll_cutoff)
              else (make_date(extract(year from p_day)::int, extract(month from p_day)::int, c.payroll_cutoff) - interval '1 month')::date end,
         case when c.payroll_cutoff is null then (date_trunc('month', p_day) + interval '1 month - 1 day')::date
              when extract(day from p_day) >= c.payroll_cutoff then (make_date(extract(year from p_day)::int, extract(month from p_day)::int, c.payroll_cutoff) + interval '1 month - 1 day')::date
              else make_date(extract(year from p_day)::int, extract(month from p_day)::int, c.payroll_cutoff) - 1 end
    from public.companies c where c.id = p_company
$$;

-- what the employee has used this month, for the request form
create or replace function public.my_month_limits(p_company uuid, p_day date default null)
returns table(ps date, pe date, permit_limit numeric, permit_used numeric, punch_limit int, punch_used int)
language sql stable security definer set search_path = public as $$
  select x.ps, x.pe, c.permit_hours_month,
         (select coalesce(sum((q.payload->>'hours')::numeric), 0) from public.requests q where q.employee_id = public.my_employee(p_company) and q.kind = 'permit' and q.status in ('pending','approved') and q.from_date between x.ps and x.pe),
         c.punch_fix_month,
         (select count(*)::int from public.requests q where q.employee_id = public.my_employee(p_company) and q.kind = 'punch' and q.status in ('pending','approved') and q.from_date between x.ps and x.pe)
    from public.companies c, public.att_month_of(p_company, coalesce(p_day, public.riyadh_today())) x
   where c.id = p_company and public.my_employee(p_company) is not null
$$;

create or replace function public.month_limits_set(p_company uuid, p_permit_hours numeric, p_punch int) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if p_permit_hours is not null and (p_permit_hours <= 0 or p_permit_hours > 200) then raise exception 'حد ساعات الاستئذان بين 0.5 و200'; end if;
  if p_punch is not null and (p_punch < 0 or p_punch > 31) then raise exception 'حد نسيان البصمة بين 0 و31'; end if;
  update public.companies set permit_hours_month = p_permit_hours, punch_fix_month = p_punch where id = p_company;
end $$;

create or replace function public.default_route(p_kind text) returns text[] language sql immutable as $$
  select case p_kind
    when 'leave' then array['m','p','g'] when 'permit' then array['m','p'] when 'punch' then array['m','p'] when 'cert' then array['p']
    when 'advance' then array['m','p','f','g'] when 'resign' then array['m','p','g','f']
    when 'settle' then array['p','f','g'] when 'expense' then array['m','f','g'] else array['p'] end
$$;

-- an approved forgotten-fingerprint request writes the missing time to the attendance record
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
    s := public.employee_shift(r.employee_id);
    insert into public.attendance(company_id, employee_id, day, shift_id, check_in, check_out, source, note)
    values (r.company_id, r.employee_id, r.from_date, s.id, ti, tout, 'request', why) returning id into aid;
  else
    update public.attendance set check_in = ti, check_out = tout, source = 'request', note = why, updated_at = now() where id = a.id;
    aid := a.id;
  end if;
  perform public.att_recalc(aid);
end $$;

create or replace function public.on_request_approved(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
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
  elsif r.kind = 'resign' then
    -- ends on acceptance, or at the end of the 30 days, or at the end of a deferral (Art. 79-bis(2))
    update public.requests set to_date = least(current_date, coalesce(nullif(r.payload->>'defer_until', '')::date, r.created_at::date + 30)) where id = p_id;
    update public.employees set end_date = least(current_date, coalesce(nullif(r.payload->>'defer_until', '')::date, r.created_at::date + 30)), end_reason = 'resign' where id = r.employee_id;
  elsif r.kind = 'punch' then
    perform public.punch_apply(r.id);
  elsif r.kind = 'update' then
    update public.employees set
      phone = case when r.payload ? 'phone' then r.payload->>'phone' else phone end,
      email = case when r.payload ? 'email' then r.payload->>'email' else email end,
      iban  = case when r.payload ? 'iban'  then r.payload->>'iban'  else iban end
    where id = r.employee_id;
  end if;
end $$;

create or replace function public.submit_request(
  p_company uuid, p_kind text, p_sub text default null, p_from date default null, p_to date default null,
  p_amount numeric default null, p_payload jsonb default '{}', p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := public.my_employee(p_company);
  e public.employees; lt public.leave_types; d int; used int; rt text[]; rid uuid; owner_emp uuid; k text; ev date; bal numeric; g numeric; minst int; v_files jsonb; lim numeric; ps date; pe date;
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
      select coalesce(sum(days),0) into used from public.requests where employee_id = me and kind='leave' and sub='annual' and status in ('pending','approved');
      bal := floor(public.annual_leave_accrued(e.hire_date, p_to) - used);
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
  elsif p_kind = 'update' then
    if p_payload is null or p_payload = '{}'::jsonb then raise exception 'حدد البيانات المطلوب تعديلها'; end if;
    for k in select jsonb_object_keys(p_payload) loop
      if not (k = any(public.update_request_fields())) then raise exception 'لا يمكن طلب تعديل الحقل «%»', k; end if;
    end loop;
    if p_payload ? 'iban' and coalesce(p_payload->>'iban','') !~ '^SA[0-9]{22}$' then raise exception 'الآيبان يبدأ بـ SA ويليه 22 رقماً'; end if;
    if p_payload ? 'email' and coalesce(p_payload->>'email','') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'البريد الإلكتروني غير صحيح'; end if;
    if p_payload ? 'phone' and coalesce(p_payload->>'phone','') !~ '^(05[0-9]{8}|\+9665[0-9]{8})$' then raise exception 'رقم الجوال بصيغة 05XXXXXXXX'; end if;
    if exists(select 1 from public.requests where employee_id = me and kind = 'update' and status = 'pending') then
      raise exception 'لديك طلب تعديل بيانات قيد المراجعة'; end if;
  end if;

  select route into rt from public.workflows where company_id = p_company and kind = p_kind;
  rt := coalesce(rt, public.default_route(p_kind));
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
end $$;

revoke all on function public.att_month_of(uuid, date), public.punch_apply(uuid) from public, anon, authenticated;
revoke all on function public.my_month_limits(uuid, date), public.month_limits_set(uuid, numeric, int) from public, anon;
grant execute on function public.my_month_limits(uuid, date), public.month_limits_set(uuid, numeric, int) to authenticated;
notify pgrst, 'reload schema';
