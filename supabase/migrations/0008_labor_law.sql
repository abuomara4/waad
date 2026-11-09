-- Waad ERP — 0008 Saudi Labor Law alignment (Royal Decree M/51 1426 as amended up to M/44 dated 1446/2/8).
-- Article numbers are cited inline. Not legal advice — review with a labour-law specialist before production use.

-- ---------- Art. 53/54: probation (max 180 days; no EOS if the contract ends during probation) ----------
alter table public.employees add column probation_end date;
alter table public.employees add constraint employees_probation_check
  check (probation_end is null or (probation_end >= hire_date and probation_end <= hire_date + 179));

create or replace function public.eos_fraction(p_reason text, p_years numeric) returns numeric language sql immutable as $$
  select case
    when p_reason in ('art80', 'probation') then 0
    when p_reason = 'resign' then case when p_years < 2 then 0 when p_years < 5 then 1.0/3 when p_years < 10 then 2.0/3 else 1 end
    when p_reason in ('agree','expiry','employer','noreason','art81','resignw','resignfm','force','ret','disab','death') then 1
    else null end
$$;

-- ---------- Art. 109/111: annual leave accrues daily (21 days/yr, 30 after 5 continuous years) ----------
create or replace function public.annual_leave_accrued(p_hire date, p_as_of date) returns numeric language sql immutable as $$
  select case when p_as_of < p_hire then 0 else
    round(least(p_as_of - p_hire + 1, 1826) * 21 / 365.0 + greatest(p_as_of - p_hire + 1 - 1826, 0) * 30 / 365.0, 2) end
$$;
create or replace function public.annual_leave_balance(p_emp uuid, p_as_of date default current_date)
returns table(accrued numeric, taken numeric, balance numeric)
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; t numeric;
begin
  select * into e from public.employees where id = p_emp;
  if not found then return; end if;
  if not (p_emp = public.my_employee(e.company_id) or public.has_role(e.company_id, array['owner','admin','hr','finance'])
          or e.manager_id = public.my_employee(e.company_id)) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  select coalesce(sum(days), 0) into t from public.requests where employee_id = p_emp and kind = 'leave' and sub = 'annual' and status in ('pending','approved');
  return query select public.annual_leave_accrued(e.hire_date, p_as_of), t, round(public.annual_leave_accrued(e.hire_date, p_as_of) - t, 2);
end $$;

-- ---------- Art. 113 / 151 / 160: event-based leaves are counted from the event date ----------
update public.leave_types set min_days = 130, max_days = null, paid_note = 'كامل — لا تقل عن 4 أشهر و10 أيام من تاريخ الوفاة' where code = 'iddah';
update public.leave_types set paid_note = 'كامل — خلال 7 أيام من تاريخ الولادة' where code = 'birth';

-- ---------- Art. 117: sick-pay tiers (days 1–30 full, 31–90 at 75%, 91–120 unpaid) — returns the deduction for a month ----------
create or replace function public.sick_deduction(p_emp uuid, p_month_start date, p_month_end date, p_daily numeric)
returns table(days int, amount numeric) language plpgsql stable security definer set search_path = public as $$
declare r record; d date; ws date; idx int := 0; n int := 0; amt numeric := 0;
begin
  for r in select from_date, to_date from public.requests where employee_id = p_emp and kind = 'leave' and sub = 'sick' and status = 'approved' order by from_date loop
    d := r.from_date;
    while d <= r.to_date loop
      if ws is null or d >= (ws + interval '1 year')::date then ws := d; idx := 0; end if;
      idx := idx + 1;
      if d between p_month_start and p_month_end and idx > 30 then
        n := n + 1; amt := amt + p_daily * case when idx <= 90 then 0.25 else 1 end;
      end if;
      d := d + 1;
    end loop;
  end loop;
  return query select n, round(amt, 2);
end $$;

-- ---------- Art. 70/91/92/93: payroll deductions ----------
alter table public.payroll_lines add column damages numeric(12,2) not null default 0 check (damages >= 0);
alter table public.payroll_lines add column sick_days numeric(6,2) not null default 0;
alter table public.payroll_lines add column sick_deduction numeric(12,2) not null default 0;

create or replace function public.payroll_line_recalc(p_run uuid, p_emp uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; e public.employees; ms date; me date; ab numeric; l public.payroll_lines; g numeric; sk record; adv_sched numeric; room numeric;
begin
  select * into r from public.payroll_runs where id = p_run;
  select * into e from public.employees where id = p_emp;
  select * into l from public.payroll_lines where run_id = p_run and employee_id = p_emp;
  ms := make_date(r.year, r.month, 1); me := (ms + interval '1 month - 1 day')::date;
  g := e.basic + e.housing + e.transport;
  -- unpaid leave days inside the month (Art. 116)
  select coalesce(sum(greatest(0, least(to_date, me) - greatest(from_date, ms) + 1)), 0) into ab
  from public.requests where employee_id = p_emp and kind = 'leave' and sub = 'unpaid' and status = 'approved' and from_date <= me and to_date >= ms;
  select * into sk from public.sick_deduction(p_emp, ms, me, g / 30);
  update public.payroll_lines set
    basic = e.basic, housing = e.housing, transport = e.transport, gross = g,
    gosi = public.gosi_employee(e.is_saudi, e.basic, e.housing, public.gosi_is_new(e.gosi_new, e.hire_date), me),
    employer_gosi = public.gosi_employer(e.is_saudi, e.basic, e.housing, public.gosi_is_new(e.gosi_new, e.hire_date), me),
    absence_days = ab, absence = round(g / 30 * ab, 2),
    sick_days = sk.days, sick_deduction = sk.amount,
    overtime = round((g / 30 / 8 + 0.5 * e.basic / 30 / 8) * l.overtime_hours, 2)  -- Art. 107
  where run_id = p_run and employee_id = p_emp;
  select * into l from public.payroll_lines where run_id = p_run and employee_id = p_emp;
  -- advance installments: ≤ 10% of wage (Art. 92) and total statutory deductions ≤ 50% of wage (Art. 93)
  select coalesce(sum(d.amount),0) into adv_sched from public.advance_deductions d join public.requests q on q.id = d.request_id
   where d.run_id = p_run and q.employee_id = p_emp;
  room := greatest(0, round(g * 0.5, 2) - l.gosi - l.deductions - l.damages);
  update public.payroll_lines set advance = least(adv_sched, round(g * 0.10, 2), room) where run_id = p_run and employee_id = p_emp;
  -- keep the advance schedule consistent with what was actually deducted
  if adv_sched > least(adv_sched, round(g * 0.10, 2), room) then
    with x as (select d.request_id, d.amount, sum(d.amount) over (order by d.request_id) running from public.advance_deductions d
               join public.requests q on q.id = d.request_id where d.run_id = p_run and q.employee_id = p_emp)
    update public.advance_deductions ad set amount = greatest(0, least(x.amount, least(adv_sched, round(g * 0.10, 2), room) - (x.running - x.amount)))
      from x where ad.run_id = p_run and ad.request_id = x.request_id;
    delete from public.advance_deductions where run_id = p_run and amount <= 0;
  end if;
  update public.payroll_lines set net = gross + overtime + bonus - gosi - absence - sick_deduction - deductions - damages - advance
   where run_id = p_run and employee_id = p_emp;
end $$;

-- fines (Art. 70: ≤ 5 days' wage per month) and damages (Art. 91: ≤ 5 days' wage per month)
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
  update public.payroll_lines set overtime_hours = coalesce(p_ot_hours,0), bonus = coalesce(p_bonus,0), deductions = coalesce(p_fines,0), damages = coalesce(p_damages,0)
   where run_id = p_run and employee_id = p_emp;
  perform public.payroll_line_recalc(p_run, p_emp);
end $$;
create or replace function public.payroll_adjust(p_run uuid, p_emp uuid, p_ot_hours numeric, p_bonus numeric, p_deductions numeric)
returns void language sql security definer set search_path = public as $$
  select public.payroll_set_line(p_run, p_emp, p_ot_hours, p_bonus, p_deductions, 0)
$$;

-- payroll approval: include sick deductions and damages in the expense/net
create or replace function public.payroll_approve(p_run uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; t record; me date; je uuid;
begin
  select * into r from public.payroll_runs where id = p_run for update;
  perform public.require_role(r.company_id, array['owner','finance']);
  if r.status <> 'draft' then raise exception 'المسير معتمد مسبقاً'; end if;
  select coalesce(sum(gross + overtime + bonus - absence - sick_deduction - deductions - damages),0) ex, coalesce(sum(gosi),0) g, coalesce(sum(employer_gosi),0) eg,
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

-- ---------- requests: Art. 92 (advance), 113 (event leaves), 79-bis (resignation), 109 (accrued annual leave) ----------
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

-- Art. 79-bis(3): the employee may withdraw a resignation within 7 days (unless already accepted)
create or replace function public.cancel_request(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.requests;
begin
  select * into r from public.requests where id = p_id for update;
  if not found or r.employee_id is distinct from public.my_employee(r.company_id) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if r.status <> 'pending' then raise exception 'لا يمكن إلغاء طلب تم البت فيه'; end if;
  if r.kind = 'resign' and r.created_at < now() - interval '7 days' then raise exception 'يجوز العدول عن الاستقالة خلال 7 أيام من تقديمها فقط — م79 مكرر'; end if;
  update public.requests set status = 'cancelled', decided_at = now() where id = p_id;
  insert into public.request_actions(request_id, actor, action) values (p_id, auth.uid(), 'cancelled');
end $$;

-- resignation ends on acceptance (Art. 79-bis(2))
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
    update public.requests set to_date = least(current_date, r.created_at::date + 30) where id = p_id;
    update public.employees set end_date = least(current_date, r.created_at::date + 30), end_reason = 'resign' where id = r.employee_id;
  elsif r.kind = 'update' then
    update public.employees set
      phone = case when r.payload ? 'phone' then r.payload->>'phone' else phone end,
      email = case when r.payload ? 'email' then r.payload->>'email' else email end,
      iban  = case when r.payload ? 'iban'  then r.payload->>'iban'  else iban end
    where id = r.employee_id;
  end if;
end $$;

-- Art. 79-bis(1): a resignation unanswered for 30 days is deemed accepted
create or replace function public.apply_deemed_resignations(p_company uuid) returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  if not public.has_role(p_company, array['owner','admin','hr']) then return 0; end if;
  for r in select id from public.requests where company_id = p_company and kind = 'resign' and status = 'pending' and created_at::date + 30 <= current_date for update loop
    update public.requests set status = 'approved', decided_at = now(), step = cardinality(route) where id = r.id;
    insert into public.request_actions(request_id, actor, action, note) values (r.id, null, 'approved', 'مقبولة حكماً لمضي 30 يوماً دون رد — م79 مكرر');
    perform public.on_request_approved(r.id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------- end-of-service settlement for an employee (Art. 77, 84–88, 111, 116) ----------
create or replace function public.eos_for_employee(p_emp uuid, p_end date, p_reason text, p_contract_end date default null)
returns table(wage numeric, service_days int, excluded_days int, years numeric, full_award numeric, fraction numeric, award numeric,
              leave_days numeric, leave_pay numeric, compensation numeric, total numeric)
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; w numeric; ex int := 0; sd int; y numeric; fa numeric; f numeric; lb numeric; comp numeric := 0; r record;
begin
  select * into e from public.employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود'; end if;
  perform public.require_role(e.company_id, array['owner','admin','hr','finance']);
  if p_end < e.hire_date then raise exception 'نهاية الخدمة قبل بدايتها'; end if;
  if public.eos_fraction(p_reason, 0) is null then raise exception 'سبب انتهاء خدمة غير معروف: %', p_reason; end if;
  w := e.basic + e.housing + e.transport;                       -- Art. 84: last wage
  for r in select from_date, least(to_date, p_end) t from public.requests where employee_id = p_emp and kind = 'leave' and sub = 'unpaid' and status = 'approved' and from_date <= p_end loop
    ex := ex + greatest(0, (r.t - r.from_date + 1) - 20);      -- Art. 116: suspended beyond 20 days
  end loop;
  sd := (p_end - e.hire_date + 1) - ex;
  y := sd / 365.0;
  fa := case when y <= 5 then w / 2 * y else w / 2 * 5 + w * (y - 5) end;
  f := public.eos_fraction(p_reason, y);
  select greatest(0, b.balance) into lb from public.annual_leave_balance(p_emp, p_end) b;  -- Art. 111
  if p_reason = 'noreason' then                                  -- Art. 77
    comp := case when p_contract_end is null then greatest(w / 30 * 15 * y, w * 2)
                 else greatest(w / 30 * greatest(p_contract_end - p_end, 0), w * 2) end;
  end if;
  return query select w, sd, ex, round(y, 4), round(fa, 2), round(f, 4), round(fa * f, 2), coalesce(lb, 0), round(w / 30 * coalesce(lb, 0), 2),
                      round(comp, 2), round(fa * f, 2) + round(w / 30 * coalesce(lb, 0), 2) + round(comp, 2);
end $$;

-- ---------- grants ----------
revoke all on function public.annual_leave_balance(uuid, date), public.sick_deduction(uuid, date, date, numeric), public.payroll_set_line(uuid, uuid, numeric, numeric, numeric, numeric),
  public.payroll_adjust(uuid, uuid, numeric, numeric, numeric), public.payroll_approve(uuid), public.submit_request(uuid, text, text, date, date, numeric, jsonb, text),
  public.cancel_request(uuid), public.on_request_approved(uuid), public.apply_deemed_resignations(uuid), public.eos_for_employee(uuid, date, text, date),
  public.payroll_line_recalc(uuid, uuid), public.annual_leave_accrued(date, date), public.eos_fraction(text, numeric) from public, anon;
revoke all on function public.on_request_approved(uuid), public.payroll_line_recalc(uuid, uuid), public.sick_deduction(uuid, date, date, numeric) from authenticated;
grant execute on function public.annual_leave_balance(uuid, date), public.payroll_set_line(uuid, uuid, numeric, numeric, numeric, numeric),
  public.payroll_adjust(uuid, uuid, numeric, numeric, numeric), public.payroll_approve(uuid), public.submit_request(uuid, text, text, date, date, numeric, jsonb, text),
  public.cancel_request(uuid), public.apply_deemed_resignations(uuid), public.eos_for_employee(uuid, date, text, date),
  public.annual_leave_accrued(date, date), public.eos_fraction(text, numeric) to authenticated;
