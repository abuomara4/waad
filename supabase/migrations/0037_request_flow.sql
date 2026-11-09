-- Request approval flow: an HR-manager step after the HR officer, a visible timeline, same-approver auto-pass,
-- a company deadline per step; annual travel tickets per contract and exit/re-entry visas, as their own
-- requests or inside a leave request (one request: leave + ticket + visa, with finance added when a ticket is asked).
--  * Tickets are a contractual benefit (not a general statutory one): the entitlement lives on the employee record.
--  * Exit/re-entry visas are for non-Saudi workers; HR records the visa after issuing it on Muqeem/Absher.

alter table public.companies
  add column hr_manager uuid references auth.users(id) on delete set null,
  add column request_sla_days int check (request_sla_days between 1 and 30);

alter table public.requests add column step_at timestamptz not null default now();
update public.requests r set step_at = coalesce((select max(a.at) from public.request_actions a where a.request_id = r.id), r.created_at);
alter table public.requests drop constraint requests_kind_check;
alter table public.requests add constraint requests_kind_check
  check (kind in ('leave','permit','cert','advance','resign','settle','expense','update','punch','ticket','visa'));

alter table public.workflows drop constraint if exists workflows_route_check;
alter table public.workflows add constraint workflows_route_check check (route <@ array['m','p','h','f','g']);

alter table public.employees
  add column ticket_every int check (ticket_every in (12, 24)),
  add column ticket_persons int not null default 1 check (ticket_persons between 1 and 10),
  add column ticket_class text not null default 'economy' check (ticket_class in ('economy','business')),
  add column ticket_dest text,
  add column ticket_dest_en text,
  add column ticket_amount numeric(12,2) check (ticket_amount is null or ticket_amount >= 0);

create table public.travel_tickets (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  request_id uuid references public.requests(id) on delete set null,
  mode text not null check (mode in ('ticket','cash')),
  persons int not null check (persons between 1 and 10),
  estimate numeric(12,2),
  status text not null default 'approved' check (status in ('approved','issued','cancelled')),
  amount numeric(12,2) check (amount is null or amount >= 0),
  ref text,
  issued_on date,
  entry_id uuid,
  created_at timestamptz not null default now()
);
create index on public.travel_tickets(employee_id);

create table public.exit_visas (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  request_id uuid references public.requests(id) on delete set null,
  visa_type text not null check (visa_type in ('single','multiple')),
  travel_on date,
  return_on date,
  status text not null default 'requested' check (status in ('requested','issued','returned','not_returned','cancelled')),
  visa_no text,
  issued_on date,
  expires_on date,
  returned_on date,
  note text,
  created_at timestamptz not null default now(),
  check (expires_on is null or issued_on is null or expires_on >= issued_on)
);
create index on public.exit_visas(employee_id);

alter table public.travel_tickets enable row level security;
alter table public.exit_visas enable row level security;
create policy tt_read on public.travel_tickets for select using (public.has_role(company_id, array['owner','admin','hr','finance']) or employee_id = public.my_employee(company_id));
create policy ev_read on public.exit_visas for select using (public.has_role(company_id, array['owner','admin','hr','finance']) or employee_id = public.my_employee(company_id));
grant select on public.travel_tickets, public.exit_visas to authenticated;
create trigger audit_travel_tickets after insert or update or delete on public.travel_tickets for each row execute function public.audit_trigger();
create trigger audit_exit_visas after insert or update or delete on public.exit_visas for each row execute function public.audit_trigger();

create or replace function public.step_label(p text) returns text language sql immutable as $$
  select case p when 'm' then 'المدير المباشر' when 'p' then 'الموارد البشرية' when 'h' then 'مدير الموارد البشرية'
                when 'f' then 'المالية' when 'g' then 'المدير العام' end
$$;

create or replace function public.default_route(p_kind text) returns text[] language sql immutable as $$
  select case p_kind
    when 'leave' then array['m','p','h','g'] when 'permit' then array['m','p'] when 'cert' then array['p'] when 'punch' then array['m','p']
    when 'advance' then array['m','p','h','f','g'] when 'resign' then array['m','p','h','g','f']
    when 'settle' then array['p','h','f','g'] when 'expense' then array['m','f','g']
    when 'ticket' then array['m','p','h','f'] when 'visa' then array['m','p','h']
    else array['p'] end
$$;

-- who may act on a step. Finance falls back to the owner when the company has no finance manager.
create or replace function public.can_act(r public.requests, p text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.my_employee(r.company_id);
begin
  if me is not null and me = r.employee_id then return false; end if;   -- nobody approves their own request
  return case p
    when 'm' then exists(select 1 from public.employees e where e.id = r.employee_id and e.manager_id = me and me is not null)
    when 'p' then public.has_role(r.company_id, array['hr','admin'])
    when 'h' then exists(select 1 from public.companies c where c.id = r.company_id and c.hr_manager = auth.uid())
    when 'f' then public.has_role(r.company_id, array['finance'])
                  or (public.has_role(r.company_id, array['owner'])
                      and not exists(select 1 from public.members m where m.company_id = r.company_id and (m.role = 'finance' or 'finance' = any(m.extra_roles))))
    when 'g' then public.has_role(r.company_id, array['owner'])
    else false end;
end $$;

create or replace function public.decide_request(p_id uuid, p_approve boolean, p_note text default null)
returns text language plpgsql security definer set search_path = public as $$
declare r public.requests; cur text; nxt int;
begin
  select * into r from public.requests where id = p_id for update;
  if not found then raise exception 'الطلب غير موجود'; end if;
  if r.status <> 'pending' then raise exception 'الطلب ليس بانتظار قرار'; end if;
  cur := r.route[r.step + 1];
  if not public.can_act(r, cur) then raise exception 'غير مصرح لك باعتماد هذه المرحلة (%)', public.step_label(cur) using errcode = '42501'; end if;
  if not p_approve then
    if coalesce(length(trim(p_note)),0) < 3 then raise exception 'اكتب سبب الرفض'; end if;
    update public.requests set status = 'rejected', decided_at = now(), step_at = now() where id = p_id;
    insert into public.request_actions(request_id, actor, actor_step, action, note) values (p_id, auth.uid(), cur, 'rejected', trim(p_note));
    return 'rejected';
  end if;
  insert into public.request_actions(request_id, actor, actor_step, action, note) values (p_id, auth.uid(), cur, 'approved', nullif(trim(p_note),''));
  nxt := r.step + 1;
  -- the same person holding the next step(s) approves once
  while nxt < cardinality(r.route) and public.can_act(r, r.route[nxt + 1]) loop
    insert into public.request_actions(request_id, actor, actor_step, action, note)
    values (p_id, auth.uid(), r.route[nxt + 1], 'approved', 'اعتماد تلقائي: المعتمد نفسه في المرحلة السابقة');
    nxt := nxt + 1;
  end loop;
  if nxt >= cardinality(r.route) then
    update public.requests set step = nxt, status = 'approved', decided_at = now(), step_at = now() where id = p_id;
    perform public.on_request_approved(p_id);
    return 'approved';
  end if;
  update public.requests set step = nxt, step_at = now() where id = p_id;
  return 'next:' || r.route[nxt + 1];
end $$;

create or replace function public.request_waiting_on(p_id uuid)
returns table(employee_id uuid, full_name text, phone text, step text)
language plpgsql stable security definer set search_path = public as $$
declare r public.requests; st text; roles text[]; nofin boolean;
begin
  select * into r from public.requests where id = p_id;
  if not found then raise exception 'الطلب غير موجود'; end if;
  if not (coalesce(r.employee_id = public.my_employee(r.company_id), false) or public.has_role(r.company_id, array['owner','admin','hr'])) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  if r.status <> 'pending' then return; end if;
  st := r.route[r.step + 1];
  if st = 'm' then
    return query select m.id, m.full_name, m.phone, st from public.employees e join public.employees m on m.id = e.manager_id where e.id = r.employee_id;
    return;
  end if;
  if st = 'h' then
    return query select x.id, x.full_name, x.phone, st from public.companies c join public.members mb on mb.company_id = c.id and mb.user_id = c.hr_manager
      join public.employees x on x.id = mb.employee_id where c.id = r.company_id;
    return;
  end if;
  nofin := not exists(select 1 from public.members m where m.company_id = r.company_id and (m.role = 'finance' or 'finance' = any(m.extra_roles)));
  roles := case st when 'p' then array['hr','admin'] when 'f' then case when nofin then array['owner'] else array['finance'] end when 'g' then array['owner'] else array[]::text[] end;
  return query select distinct x.id, x.full_name, x.phone, st from public.members mb join public.employees x on x.id = mb.employee_id
    where mb.company_id = r.company_id and (mb.role = any(roles) or mb.extra_roles && roles) and x.id <> r.employee_id and (x.end_date is null or x.end_date >= current_date)
    order by x.full_name;
end $$;

-- ---------- tickets ----------
-- completed entitlement periods since hiring, minus tickets already granted
create or replace function public.ticket_status(p_emp uuid, p_on date default null)
returns table(every int, persons int, ticket_class text, dest text, dest_en text, amount numeric, earned int, used int, available int, next_due date)
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; m int; d date := coalesce(p_on, current_date); u int;
begin
  select * into e from public.employees where id = p_emp;
  if not found then return; end if;
  if not (e.id = public.my_employee(e.company_id) or public.has_role(e.company_id, array['owner','admin','hr','finance'])) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  if e.ticket_every is null then return; end if;
  m := (extract(year from age(d, e.hire_date)) * 12 + extract(month from age(d, e.hire_date)))::int;
  select count(*) into u from public.travel_tickets t where t.employee_id = p_emp and t.status <> 'cancelled';
  u := u + (select count(*) from public.requests q where q.employee_id = p_emp and q.status = 'pending'
              and ((q.kind = 'ticket') or (q.kind = 'leave' and q.payload ? 'ticket')))::int;
  return query select e.ticket_every, e.ticket_persons, e.ticket_class, e.ticket_dest, e.ticket_dest_en, e.ticket_amount,
    greatest(m / e.ticket_every, 0), u, greatest(m / e.ticket_every - u, 0),
    (e.hire_date + make_interval(months => (u + 1) * e.ticket_every))::date;
end $$;

-- validates the travel parts of a request and returns the cleaned payload
create or replace function public.travel_check(e public.employees, p_kind text, p_from date, p_to date, p_payload jsonb)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare t jsonb; v jsonb; out jsonb := coalesce(p_payload, '{}'::jsonb) - 'ticket' - 'visa' - 'mode' - 'persons' - 'visa_type'; ts record; n int;
begin
  if p_kind = 'ticket' then t := jsonb_build_object('mode', p_payload->>'mode', 'persons', p_payload->'persons');
  elsif p_kind = 'visa' then v := jsonb_build_object('type', p_payload->>'visa_type');
  else t := p_payload->'ticket'; v := p_payload->'visa'; end if;
  if t is not null and jsonb_typeof(t) = 'object' then
    if e.ticket_every is null then raise exception 'عقدك لا ينص على تذكرة سفر — راجع الموارد البشرية'; end if;
    if coalesce(t->>'mode', '') not in ('ticket','cash') then raise exception 'اختر: تذكرة أو بدل نقدي'; end if;
    n := coalesce(nullif(t->>'persons', '')::int, e.ticket_persons);
    if n < 1 or n > e.ticket_persons then raise exception 'عدد المسافرين المستحق لك % — حسب العقد', e.ticket_persons; end if;
    select * into ts from public.ticket_status(e.id, coalesce(p_from, current_date));
    if ts.available < 1 then raise exception 'لا يوجد لك استحقاق تذكرة الآن — الاستحقاق القادم في %', ts.next_due; end if;
    out := out || jsonb_build_object('ticket', jsonb_build_object('mode', t->>'mode', 'persons', n));
  end if;
  if v is not null and jsonb_typeof(v) = 'object' then
    if e.is_saudi then raise exception 'تأشيرة الخروج والعودة لغير السعوديين'; end if;
    if coalesce(v->>'type', '') not in ('single','multiple') then raise exception 'اختر نوع التأشيرة: مفردة أو متعددة'; end if;
    if p_from is null or p_to is null or p_to < p_from then raise exception 'حدد تاريخ السفر وتاريخ العودة'; end if;
    if p_from < current_date then raise exception 'تاريخ السفر قبل اليوم'; end if;
    if exists(select 1 from public.exit_visas x where x.employee_id = e.id and x.status in ('requested','issued')) then
      raise exception 'لديك تأشيرة خروج وعودة لم تُغلق بعد'; end if;
    out := out || jsonb_build_object('visa', jsonb_build_object('type', v->>'type'));
  end if;
  if p_kind = 'ticket' and not (out ? 'ticket') then raise exception 'اختر تفاصيل التذكرة'; end if;
  if p_kind = 'visa' and not (out ? 'visa') then raise exception 'اختر نوع التأشيرة'; end if;
  return out;
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
  if r.kind in ('leave','ticket') and r.payload ? 'ticket' then
    insert into public.travel_tickets(company_id, employee_id, request_id, mode, persons, estimate)
    select r.company_id, r.employee_id, r.id, r.payload->'ticket'->>'mode', (r.payload->'ticket'->>'persons')::int,
           e.ticket_amount * (r.payload->'ticket'->>'persons')::int from public.employees e where e.id = r.employee_id;
  end if;
  if r.kind in ('leave','visa') and r.payload ? 'visa' then
    insert into public.exit_visas(company_id, employee_id, request_id, visa_type, travel_on, return_on)
    values (r.company_id, r.employee_id, r.id, r.payload->'visa'->>'type', r.from_date, r.to_date);
  end if;
end $$;

create or replace function public.submit_request(
  p_company uuid, p_kind text, p_sub text default null, p_from date default null, p_to date default null,
  p_amount numeric default null, p_payload jsonb default '{}', p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := public.my_employee(p_company);
  e public.employees; lt public.leave_types; d int; used int; rt text[]; rid uuid; owner_emp uuid; k text; ev date; bal numeric; g numeric; minst int; v_files jsonb; lim numeric; ps date; pe date; hm uuid;
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
  elsif p_kind = 'ticket' then
    if p_from is not null and p_from < current_date then raise exception 'تاريخ السفر قبل اليوم'; end if;
    p_to := coalesce(p_to, p_from);
  elsif p_kind = 'visa' then
    if p_from is not null and p_to is not null and p_to >= p_from then d := public.days_between(p_from, p_to); end if;
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

  if p_kind in ('leave','ticket','visa') then p_payload := public.travel_check(e, p_kind, p_from, p_to, p_payload); end if;
  select route into rt from public.workflows where company_id = p_company and kind = p_kind;
  rt := coalesce(rt, public.default_route(p_kind));
  -- a ticket inside a leave request is paid by finance, so finance joins the route (before the general manager)
  if p_kind = 'leave' and p_payload ? 'ticket' and not ('f' = any(rt)) then
    rt := case when 'g' = any(rt) then array_remove(rt, 'g') || array['f','g'] else rt || array['f'] end; end if;
  -- the HR-manager step applies only when one is appointed, and never to his own request
  select hr_manager into hm from public.companies where id = p_company;
  if hm is null or exists(select 1 from public.members m where m.company_id = p_company and m.user_id = hm and m.employee_id = me) then
    rt := array_remove(rt, 'h'); end if;
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


-- ---------- HR / finance actions on tickets and visas ----------
create or replace function public.ticket_issue(p_id uuid, p_amount numeric, p_ref text, p_on date, p_account text default '1120')
returns void language plpgsql security definer set search_path = public as $$
declare t public.travel_tickets; nm text; jid uuid;
begin
  select * into t from public.travel_tickets where id = p_id for update;
  if not found then raise exception 'السجل غير موجود'; end if;
  perform public.require_role(t.company_id, array['owner','admin','finance']);
  if t.status <> 'approved' then raise exception 'سُجّلت هذه التذكرة من قبل أو أُلغيت'; end if;
  if coalesce(p_amount, 0) <= 0 then raise exception 'أدخل المبلغ'; end if;
  if p_account not in ('1110','1120') then raise exception 'اختر البنك أو الصندوق'; end if;
  if t.mode = 'ticket' and length(trim(coalesce(p_ref, ''))) < 3 then raise exception 'اكتب رقم الحجز أو التذكرة'; end if;
  insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header)
  values (t.company_id, '5220', 'تذاكر سفر الموظفين', 'Employee travel tickets', 'exp', '5000', false) on conflict do nothing;
  select full_name into nm from public.employees where id = t.employee_id;
  jid := public.post_journal(t.company_id, coalesce(p_on, current_date),
    case t.mode when 'cash' then 'بدل تذكرة سفر — ' else 'تذكرة سفر — ' end || nm, 'expense', t.id,
    jsonb_build_array(jsonb_build_object('a','5220','d',p_amount), jsonb_build_object('a',p_account,'c',p_amount)));
  update public.travel_tickets set status = 'issued', amount = p_amount, ref = nullif(trim(p_ref), ''), issued_on = coalesce(p_on, current_date), entry_id = jid where id = p_id;
end $$;

create or replace function public.ticket_cancel(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare t public.travel_tickets;
begin
  select * into t from public.travel_tickets where id = p_id for update;
  if not found then raise exception 'السجل غير موجود'; end if;
  perform public.require_role(t.company_id, array['owner','admin','hr']);
  if t.status <> 'approved' then raise exception 'لا يُلغى إلا قبل الصرف'; end if;
  update public.travel_tickets set status = 'cancelled' where id = p_id;   -- the entitlement returns to the employee
end $$;

create or replace function public.visa_record(p_id uuid, p_no text, p_issued date, p_expires date, p_type text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v public.exit_visas;
begin
  select * into v from public.exit_visas where id = p_id for update;
  if not found then raise exception 'السجل غير موجود'; end if;
  perform public.require_role(v.company_id, array['owner','admin','hr']);
  if v.status not in ('requested','issued') then raise exception 'التأشيرة مغلقة'; end if;
  if length(trim(coalesce(p_no, ''))) < 4 then raise exception 'اكتب رقم التأشيرة'; end if;
  if p_issued is null or p_expires is null or p_expires < p_issued then raise exception 'حدد تاريخ الإصدار وآخر موعد للعودة'; end if;
  update public.exit_visas set status = 'issued', visa_no = trim(p_no), issued_on = p_issued, expires_on = p_expires,
    visa_type = coalesce(nullif(p_type, ''), visa_type) where id = p_id;
end $$;

create or replace function public.visa_close(p_id uuid, p_status text, p_on date default null, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v public.exit_visas;
begin
  select * into v from public.exit_visas where id = p_id for update;
  if not found then raise exception 'السجل غير موجود'; end if;
  perform public.require_role(v.company_id, array['owner','admin','hr']);
  if p_status not in ('returned','not_returned','cancelled') then raise exception 'حالة غير معروفة'; end if;
  if p_status = 'cancelled' and v.status <> 'requested' then raise exception 'تُلغى التأشيرة قبل تسجيل إصدارها فقط'; end if;
  if p_status <> 'cancelled' and v.status <> 'issued' then raise exception 'سجّل التأشيرة أولاً'; end if;
  if p_status = 'returned' and (p_on is null or p_on < v.issued_on) then raise exception 'حدد تاريخ العودة'; end if;
  update public.exit_visas set status = p_status, returned_on = case when p_status = 'returned' then p_on end, note = nullif(trim(p_note), '') where id = p_id;
end $$;

-- ---------- approval settings ----------
create or replace function public.hr_manager_set(p_company uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin']);
  if p_user is not null and not exists(select 1 from public.members m where m.company_id = p_company and m.user_id = p_user and (m.role in ('hr','admin') or m.extra_roles && array['hr','admin'])) then
    raise exception 'مدير الموارد البشرية يُختار من مستخدمي الموارد البشرية'; end if;
  update public.companies set hr_manager = p_user where id = p_company;
end $$;

create or replace function public.request_sla_set(p_company uuid, p_days int) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  update public.companies set request_sla_days = p_days where id = p_company;
end $$;

-- steps are kept in the fixed order: direct manager → HR → HR manager → finance → general manager
create or replace function public.workflow_set(p_company uuid, p_kind text, p_route text[]) returns text[]
language plpgsql security definer set search_path = public as $$
declare rt text[];
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if p_kind not in ('leave','permit','cert','advance','resign','settle','expense','update','punch','ticket','visa') then raise exception 'نوع طلب غير معروف'; end if;
  if p_route is null then delete from public.workflows where company_id = p_company and kind = p_kind; return public.default_route(p_kind); end if;
  rt := array(select s from unnest(array['m','p','h','f','g']) with ordinality x(s, i) where s = any(p_route) order by i);
  if cardinality(rt) = 0 then raise exception 'اختر مرحلة اعتماد واحدة على الأقل'; end if;
  if p_kind in ('ticket','advance','expense','settle') and not ('f' = any(rt)) then raise exception 'هذا الطلب يصرف مبلغاً فلا بد أن يمر على المالية'; end if;
  insert into public.workflows(company_id, kind, route) values (p_company, p_kind, rt)
    on conflict (company_id, kind) do update set route = excluded.route;
  return rt;
end $$;

-- ---------- the request's journey, step by step ----------
create or replace function public.request_timeline(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.requests; me uuid; sla int; i int; st text; a record; nm text; nm_en text; steps jsonb := '[]'; state text;
begin
  select * into r from public.requests where id = p_id;
  if not found then raise exception 'الطلب غير موجود'; end if;
  me := public.my_employee(r.company_id);
  if not (r.employee_id = me or public.has_role(r.company_id, array['owner','admin','hr','finance'])
          or exists(select 1 from public.employees e where e.id = r.employee_id and e.manager_id = me and me is not null)
          or exists(select 1 from public.companies c where c.id = r.company_id and c.hr_manager = auth.uid())) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  select request_sla_days into sla from public.companies where id = r.company_id;
  for i in 1 .. coalesce(cardinality(r.route), 0) loop
    st := r.route[i];
    select x.actor, x.action, x.at, x.note into a from public.request_actions x
     where x.request_id = p_id and x.actor_step = st and x.action in ('approved','rejected') order by x.at desc limit 1;
    nm := null; nm_en := null;
    if a.actor is not null then
      select e.full_name, e.full_name_en into nm, nm_en from public.members mb join public.employees e on e.id = mb.employee_id
       where mb.company_id = r.company_id and mb.user_id = a.actor;
    end if;
    state := case when i <= r.step then 'done'
                  when i = r.step + 1 and r.status = 'pending' then 'current'
                  when i = r.step + 1 and r.status = 'rejected' then 'rejected'
                  when i = r.step + 1 and r.status = 'cancelled' then 'cancelled'
                  when r.status in ('rejected','cancelled') then 'skipped' else 'waiting' end;
    steps := steps || jsonb_build_object('step', st, 'state', state,
      'by', case when state in ('done','rejected') then coalesce(nm, '—') end, 'by_en', case when state in ('done','rejected') then nm_en end,
      'at', case when state in ('done','rejected') then a.at end, 'note', case when state in ('done','rejected') then a.note end,
      'since', case when state = 'current' then r.step_at end,
      'hours', case when state = 'current' then round(extract(epoch from now() - r.step_at) / 3600) end,
      'overdue', state = 'current' and sla is not null and now() - r.step_at > make_interval(days => sla));
  end loop;
  return jsonb_build_object('status', r.status, 'submitted_at', r.created_at, 'decided_at', r.decided_at, 'sla_days', sla, 'steps', steps,
    'ticket', (select to_jsonb(t) - 'entry_id' from public.travel_tickets t where t.request_id = p_id limit 1),
    'visa', (select to_jsonb(v) from public.exit_visas v where v.request_id = p_id limit 1));
end $$;

-- ---------- travel desk for HR and finance ----------
create or replace function public.travel_board(p_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare td date := public.riyadh_today(); due jsonb := '[]'; e record; ts record;
begin
  perform public.require_role(p_company, array['owner','admin','hr','finance']);
  for e in select id, emp_no, full_name, full_name_en from public.employees where company_id = p_company and ticket_every is not null and (end_date is null or end_date >= td) order by emp_no loop
    select * into ts from public.ticket_status(e.id, td);
    if ts.available > 0 then due := due || jsonb_build_object('employee_id', e.id, 'emp_no', e.emp_no, 'name', e.full_name, 'name_en', e.full_name_en,
      'available', ts.available, 'persons', ts.persons, 'dest', ts.dest, 'dest_en', ts.dest_en, 'amount', ts.amount, 'class', ts.ticket_class); end if;
  end loop;
  return jsonb_build_object(
    'tickets', coalesce((select jsonb_agg(to_jsonb(t) - 'entry_id' || jsonb_build_object('name', x.full_name, 'name_en', x.full_name_en, 'emp_no', x.emp_no,
        'dest', x.ticket_dest, 'dest_en', x.ticket_dest_en, 'class', x.ticket_class, 'from_date', q.from_date, 'to_date', q.to_date) order by t.status, t.created_at desc)
      from public.travel_tickets t join public.employees x on x.id = t.employee_id left join public.requests q on q.id = t.request_id
     where t.company_id = p_company and (t.status = 'approved' or t.created_at > now() - interval '1 year')), '[]'),
    'visas', coalesce((select jsonb_agg(to_jsonb(v) || jsonb_build_object('name', x.full_name, 'name_en', x.full_name_en, 'emp_no', x.emp_no,
        'expiring', v.status = 'issued' and v.expires_on <= td + 7, 'late', v.status = 'issued' and v.return_on < td) order by v.status, v.travel_on)
      from public.exit_visas v join public.employees x on x.id = v.employee_id
     where v.company_id = p_company and (v.status in ('requested','issued') or v.created_at > now() - interval '1 year')), '[]'),
    'due', due);
end $$;

revoke all on function public.travel_check(public.employees, text, date, date, jsonb) from public, anon, authenticated;
revoke all on function public.ticket_status(uuid, date), public.ticket_issue(uuid, numeric, text, date, text), public.ticket_cancel(uuid),
  public.visa_record(uuid, text, date, date, text), public.visa_close(uuid, text, date, text), public.hr_manager_set(uuid, uuid),
  public.request_sla_set(uuid, int), public.workflow_set(uuid, text, text[]), public.request_timeline(uuid), public.travel_board(uuid) from public, anon;
grant execute on function public.ticket_status(uuid, date), public.ticket_issue(uuid, numeric, text, date, text), public.ticket_cancel(uuid),
  public.visa_record(uuid, text, date, date, text), public.visa_close(uuid, text, date, text), public.hr_manager_set(uuid, uuid),
  public.request_sla_set(uuid, int), public.workflow_set(uuid, text, text[]), public.request_timeline(uuid), public.travel_board(uuid) to authenticated;
notify pgrst, 'reload schema';
