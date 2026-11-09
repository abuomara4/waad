-- Waad ERP — 0012: official holidays overlapping other leave and probation (Implementing Regulations, Arts. 19 and 24).
-- Reg. Art. 24(2) annual leave is extended by holidays inside it; 24(3) sick leave pays holidays in full;
-- 24(1) a holiday on the weekly rest day is compensated with a day before or after (handled in the UI);
-- Reg. Art. 19(2) Eid, National Day, Founding Day and sick leave are not counted in the probation period.

create or replace function public.holidays_in(p_company uuid, p_from date, p_to date) returns int
language sql stable security definer set search_path = public as $$
  select count(*)::int from public.holidays where company_id = p_company and day between p_from and p_to and public.is_member(p_company)
$$;

create or replace function public.submit_request(
  p_company uuid, p_kind text, p_sub text default null, p_from date default null, p_to date default null,
  p_amount numeric default null, p_payload jsonb default '{}', p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := public.my_employee(p_company);
  e public.employees; lt public.leave_types; d int; used int; rt text[]; rid uuid; owner_emp uuid; k text; ev date; bal numeric; g numeric; minst int;
begin
  if me is null then raise exception 'حسابك غير مربوط بسجل موظف' using errcode = '42501'; end if;
  select * into e from public.employees where id = me;
  if e.end_date is not null and e.end_date < current_date then raise exception 'انتهت خدمتك'; end if;
  g := e.basic + e.housing + e.transport;

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
  elsif p_kind = 'permit' then
    if coalesce((p_payload->>'hours')::numeric, 0) <= 0 or (p_payload->>'hours')::numeric > 4 then
      raise exception 'الاستئذان من دقائق حتى 4 ساعات'; end if;
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
  if cardinality(rt) = 0 then perform public.on_request_approved(rid); end if;
  return rid;
end $$;

-- Reg. Art. 24(3): a holiday inside sick leave is paid in full (it still counts toward the 120 days of Art. 117)
create or replace function public.sick_deduction(p_emp uuid, p_month_start date, p_month_end date, p_daily numeric)
returns table(days int, amount numeric) language plpgsql stable security definer set search_path = public as $$
declare r record; d date; ws date; idx int := 0; n int := 0; amt numeric := 0; cid uuid;
begin
  select company_id into cid from public.employees where id = p_emp;
  for r in select from_date, to_date from public.requests where employee_id = p_emp and kind = 'leave' and sub = 'sick' and status = 'approved' order by from_date loop
    d := r.from_date;
    while d <= r.to_date loop
      if ws is null or d >= (ws + interval '1 year')::date then ws := d; idx := 0; end if;
      idx := idx + 1;
      if d between p_month_start and p_month_end and idx > 30
         and not exists(select 1 from public.holidays h where h.company_id = cid and h.day = d) then
        n := n + 1; amt := amt + p_daily * case when idx <= 90 then 0.25 else 1 end;
      end if;
      d := d + 1;
    end loop;
  end loop;
  return query select n, round(amt, 2);
end $$;

-- Reg. Art. 19(2): the actual end of probation = agreed end + Eid/National/Founding holidays + approved sick days inside it
create or replace function public.probation_effective_end(p_emp uuid) returns date
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; ex int := 0; prev int := -1; fin date;
begin
  select * into e from public.employees where id = p_emp;
  if e.probation_end is null then return null; end if;
  if not (coalesce(e.id = public.my_employee(e.company_id), false) or public.has_role(e.company_id, array['owner','admin','hr','finance'])
          or coalesce(e.manager_id = public.my_employee(e.company_id), false)) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  while ex <> prev loop
    prev := ex; fin := e.probation_end + ex;
    select count(*) into ex from generate_series(e.hire_date, fin, interval '1 day') g
     where exists(select 1 from public.holidays h where h.company_id = e.company_id and h.day = g::date)
        or exists(select 1 from public.requests q where q.employee_id = e.id and q.kind = 'leave' and q.sub = 'sick' and q.status = 'approved' and g::date between q.from_date and q.to_date);
  end loop;
  return e.probation_end + ex;
end $$;

-- all employees on probation in one call (HR screens)
create or replace function public.probation_ends(p_company uuid) returns table(employee_id uuid, probation_end date, effective_end date)
language sql stable security definer set search_path = public as $$
  select e.id, e.probation_end, public.probation_effective_end(e.id) from public.employees e
   where e.company_id = p_company and e.probation_end is not null and public.has_role(p_company, array['owner','admin','hr','finance'])
$$;

revoke all on function public.holidays_in(uuid, date, date), public.sick_deduction(uuid, date, date, numeric), public.probation_effective_end(uuid), public.probation_ends(uuid),
  public.submit_request(uuid, text, text, date, date, numeric, jsonb, text) from public, anon;
revoke all on function public.sick_deduction(uuid, date, date, numeric) from authenticated;
grant execute on function public.holidays_in(uuid, date, date), public.probation_effective_end(uuid), public.probation_ends(uuid), public.submit_request(uuid, text, text, date, date, numeric, jsonb, text) to authenticated;
notify pgrst, 'reload schema';
