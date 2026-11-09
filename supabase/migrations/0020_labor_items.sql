-- Remaining labor-law items:
--  * Art. 79-bis(1): the employer may defer accepting a resignation up to 60 days for work needs, by a reasoned written
--    notice given before the 30 days run out; the deferral counts from that notice, and the contract ends at its end.
--  * Art. 107 + Reg. Art. 22-bis: with the worker's consent, overtime can be compensated with paid leave instead of pay —
--    at least 1.5 hours of leave per overtime hour, at most 30 days a year, taken within 60 days unless agreed
--    otherwise, and paid out if the worker leaves before using it.
--  * Art. 115: exam leave — paid for an approved course, unpaid for a repeated year, from the annual balance (or
--    unpaid) without the employer's approval; requested 15 days ahead; pay is lost if the exam was not sat.

-- ---------- resignation deferral ----------
create or replace function public.resign_defer(p_id uuid, p_days int, p_reason text) returns date
language plpgsql security definer set search_path = public as $$
declare r public.requests; td date := (now() at time zone 'Asia/Riyadh')::date; until date;
begin
  select * into r from public.requests where id = p_id for update;
  if not found or r.kind <> 'resign' then raise exception 'الطلب غير موجود'; end if;
  perform public.require_role(r.company_id, array['owner','admin','hr']);
  if r.status <> 'pending' then raise exception 'تم البت في طلب الاستقالة'; end if;
  if r.payload ? 'defer_until' then raise exception 'سبق تأجيل قبول هذه الاستقالة'; end if;
  if td >= r.created_at::date + 30 then raise exception 'يكون تأجيل القبول قبل انتهاء الثلاثين يوماً من تقديم الاستقالة — م79 مكرر'; end if;
  if p_days is null or p_days < 1 or p_days > 60 then raise exception 'مدة التأجيل من يوم إلى 60 يوماً — م79 مكرر'; end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'اكتب سبب التأجيل (مصلحة العمل) — يُقدَّم للعامل مكتوباً'; end if;
  until := td + p_days;
  update public.requests set payload = payload || jsonb_build_object('defer_on', td, 'defer_until', until, 'defer_days', p_days, 'defer_reason', trim(p_reason), 'defer_by', auth.uid())
   where id = p_id;
  return until;
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
  elsif r.kind = 'update' then
    update public.employees set
      phone = case when r.payload ? 'phone' then r.payload->>'phone' else phone end,
      email = case when r.payload ? 'email' then r.payload->>'email' else email end,
      iban  = case when r.payload ? 'iban'  then r.payload->>'iban'  else iban end
    where id = r.employee_id;
  end if;
end $$;

create or replace function public.apply_deemed_resignations(p_company uuid) returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  if not public.has_role(p_company, array['owner','admin','hr']) then return 0; end if;
  for r in select id, payload from public.requests where company_id = p_company and kind = 'resign' and status = 'pending'
             and coalesce(nullif(payload->>'defer_until', '')::date, created_at::date + 30) <= current_date for update loop
    update public.requests set status = 'approved', decided_at = now(), step = cardinality(route) where id = r.id;
    insert into public.request_actions(request_id, actor, action, note) values (r.id, null, 'approved',
      case when r.payload ? 'defer_until' then 'مقبولة بانتهاء مدة تأجيل القبول — م79 مكرر' else 'مقبولة حكماً لمضي 30 يوماً دون رد — م79 مكرر' end);
    perform public.on_request_approved(r.id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------- compensatory leave ----------
insert into public.leave_types(code, name_ar, name_en, article, max_days, min_days, gender, min_service_years, once_in_service, notice_days, paid_note)
values ('comp', 'إجازة تعويضية', 'Compensatory leave', 'م107', 30, null, null, null, false, null, 'كامل — من رصيد ساعات العمل الإضافي') on conflict (code) do nothing;
alter table public.attendance add column ot_comp_min int not null default 0 check (ot_comp_min >= 0);
create table public.comp_credits (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  att_id uuid references public.attendance(id) on delete set null,
  ot_hours numeric(6,2) not null check (ot_hours > 0),
  hours numeric(6,2) not null check (hours > 0),
  earned_on date not null,
  use_by date not null,
  note text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check (hours >= ot_hours * 1.5)
);
create index on public.comp_credits(employee_id);

create or replace function public.comp_balance(p_emp uuid) returns table(earned_hours numeric, used_hours numeric, balance_hours numeric)
language sql stable security definer set search_path = public as $$
  with e as (select * from public.employees where id = p_emp
             and (public.has_role(company_id, array['owner','admin','hr','finance']) or id = public.my_employee(company_id) or manager_id = public.my_employee(company_id)))
  select coalesce((select sum(hours) from public.comp_credits c where c.employee_id = e.id), 0),
         coalesce((select sum(days) * 8 from public.requests q where q.employee_id = e.id and q.kind = 'leave' and q.sub = 'comp' and q.status in ('pending','approved')), 0),
         coalesce((select sum(hours) from public.comp_credits c where c.employee_id = e.id), 0)
           - coalesce((select sum(days) * 8 from public.requests q where q.employee_id = e.id and q.kind = 'leave' and q.sub = 'comp' and q.status in ('pending','approved')), 0)
  from e
$$;

-- credit leave hours for overtime (1.5 per hour at least), with the worker's consent, within 30 days (240 hours) a year
create or replace function public.comp_credit(p_emp uuid, p_ot_hours numeric, p_rate numeric, p_on date, p_consent boolean, p_note text, p_att uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare e public.employees; y numeric; rid uuid;
begin
  select * into e from public.employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود'; end if;
  perform public.require_role(e.company_id, array['owner','admin','hr']);
  if not coalesce(p_consent, false) then raise exception 'الإجازة التعويضية بدل أجر العمل الإضافي تكون بموافقة العامل — م107'; end if;
  if coalesce(p_ot_hours, 0) <= 0 then raise exception 'أدخل ساعات العمل الإضافي'; end if;
  if coalesce(p_rate, 0) < 1.5 then raise exception 'لا تقل الإجازة التعويضية عن ساعة ونصف عن كل ساعة عمل إضافي — م22 مكرر من اللائحة'; end if;
  if p_on is null then raise exception 'حدد تاريخ العمل الإضافي'; end if;
  select coalesce(sum(hours), 0) into y from public.comp_credits where employee_id = p_emp and extract(year from earned_on) = extract(year from p_on);
  if y + round(p_ot_hours * p_rate, 2) > 240 then
    raise exception 'لا تزيد الإجازة التعويضية في السنة على 30 يوماً (240 ساعة) — المتبقي % ساعة', greatest(0, 240 - y); end if;
  insert into public.comp_credits(company_id, employee_id, att_id, ot_hours, hours, earned_on, use_by, note)
  values (e.company_id, p_emp, p_att, p_ot_hours, round(p_ot_hours * p_rate, 2), p_on, p_on + 60, nullif(trim(p_note), '')) returning id into rid;
  return rid;
end $$;

-- convert approved overtime on an attendance day into compensatory leave instead of pay
create or replace function public.att_ot_to_comp(p_att uuid, p_minutes int, p_rate numeric, p_consent boolean) returns uuid
language plpgsql security definer set search_path = public as $$
declare a public.attendance;
begin
  select * into a from public.attendance where id = p_att for update;
  if not found then raise exception 'السجل غير موجود'; end if;
  perform public.require_role(a.company_id, array['owner','admin','hr']);
  if p_minutes is null or p_minutes <= 0 or p_minutes > a.ot_min then raise exception 'الدقائق المحوّلة من الإضافي المعتمد (حتى % دقيقة)', a.ot_min; end if;
  if exists(select 1 from public.payroll_runs r where r.company_id = a.company_id and r.status <> 'draft'
            and make_date(r.year, r.month, 1) <= a.day and a.day < make_date(r.year, r.month, 1) + interval '1 month') then
    raise exception 'مسير هذا الشهر معتمد — لا يمكن تعديل الإضافي'; end if;
  update public.attendance set ot_min = ot_min - p_minutes, ot_comp_min = ot_comp_min + p_minutes where id = p_att;
  return public.comp_credit(a.employee_id, round(p_minutes / 60.0, 2), p_rate, a.day, p_consent, 'تحويل إضافي يوم ' || a.day, p_att);
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
  update public.attendance set ot_min = p_minutes, updated_by = auth.uid(), updated_at = now() where id = p_id;
end $$;

-- ---------- exam leave: pay is lost if the exam was not sat (Art. 115(1)) ----------
create or replace function public.exam_not_sat(p_id uuid, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.requests;
begin
  select * into r from public.requests where id = p_id for update;
  if not found or r.kind <> 'leave' or r.sub <> 'exam' or r.status <> 'approved' then raise exception 'إجازة الاختبارات غير موجودة أو غير معتمدة'; end if;
  perform public.require_role(r.company_id, array['owner','admin','hr']);
  if exists(select 1 from public.payroll_runs pr where pr.company_id = r.company_id and pr.status <> 'draft'
            and make_date(pr.year, pr.month, 1) <= r.to_date and r.from_date < make_date(pr.year, pr.month, 1) + interval '1 month') then
    raise exception 'مسير الشهر معتمد — اخصم أجر الإجازة يدوياً في المسير القادم'; end if;
  update public.requests set sub = 'unpaid', payload = payload || jsonb_build_object('exam_missed', true, 'exam_note', nullif(trim(p_note), '')) where id = p_id;
  perform public.payroll_line_recalc(l.run_id, l.employee_id) from public.payroll_lines l join public.payroll_runs pr on pr.id = l.run_id
   where pr.status = 'draft' and l.employee_id = r.employee_id;
end $$;

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
    -- Art. 115: exam leave — paid for an approved course (first attempt), unpaid for a repeated year, and from the
    -- annual balance (or unpaid when there is none) when the employer did not approve the enrolment
    if lt.code = 'exam' then
      if coalesce(p_payload->>'exam_mode', '') not in ('approved','repeat','own') then
        raise exception 'حدد حالة الدراسة: بموافقة المنشأة، أو سنة معادة، أو بدون موافقة المنشأة — م115'; end if;
      if p_payload->>'exam_mode' = 'repeat' then p_sub := 'unpaid';
      elsif p_payload->>'exam_mode' = 'own' then
        select coalesce(sum(days),0) into used from public.requests where employee_id = me and kind='leave' and sub='annual' and status in ('pending','approved');
        bal := floor(public.annual_leave_accrued(e.hire_date, p_to) - used);
        p_sub := case when bal >= d then 'annual' else 'unpaid' end;
      end if;
      p_payload := coalesce(p_payload, '{}'::jsonb) || jsonb_build_object('exam', true);
    end if;
    -- Reg. Art. 22-bis: compensatory leave is taken from the hours earned for overtime (8 hours a day)
    if lt.code = 'comp' then
      select balance_hours into bal from public.comp_balance(me);
      if d * 8 > coalesce(bal, 0) then raise exception 'رصيد الإجازة التعويضية % ساعة (% يوم)', coalesce(bal, 0), floor(coalesce(bal, 0) / 8); end if;
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

create trigger audit_comp_credits after insert or update or delete on public.comp_credits for each row execute function public.audit_trigger();
alter table public.comp_credits enable row level security;
create policy cc_read on public.comp_credits for select using (public.has_role(company_id, array['owner','admin','hr','finance']) or employee_id = public.my_employee(company_id));
revoke all on public.comp_credits from anon;
grant select on public.comp_credits to authenticated;
revoke insert, update, delete on public.comp_credits from authenticated;
revoke all on function public.resign_defer(uuid, int, text), public.comp_balance(uuid), public.comp_credit(uuid, numeric, numeric, date, boolean, text, uuid),
  public.att_ot_to_comp(uuid, int, numeric, boolean), public.exam_not_sat(uuid, text) from public, anon;
grant execute on function public.resign_defer(uuid, int, text), public.comp_balance(uuid), public.comp_credit(uuid, numeric, numeric, date, boolean, text, uuid),
  public.att_ot_to_comp(uuid, int, numeric, boolean), public.exam_not_sat(uuid, text) to authenticated;
notify pgrst, 'reload schema';
