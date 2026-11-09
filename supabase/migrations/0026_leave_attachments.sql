-- Supporting documents on leave requests: a sick leave needs the medical report, a bereavement leave the death
-- certificate, an exam leave the approved exam timetable, and so on. Files are kept in the database (images are
-- shrunk in the browser first), visible only to the employee and to HR / admin / owner — never to other staff.
-- Medical reports are health data: kept private, never copied into the audit log or request payloads.

alter table public.leave_types add column doc_label text, add column doc_label_en text;
update public.leave_types set doc_label = 'تقرير طبي معتمد (إجازة مرضية صادرة من منصة صحة أو المنشأة الصحية)', doc_label_en = 'Approved medical report (sick leave issued via Seha or the health facility)' where code = 'sick';
update public.leave_types set doc_label = 'شهادة الوفاة', doc_label_en = 'Death certificate' where code in ('death', 'death2', 'iddah', 'iddahn');
update public.leave_types set doc_label = 'جدول الاختبارات المعتمد من الجهة التعليمية', doc_label_en = 'Exam timetable approved by the educational institution' where code = 'exam';
update public.leave_types set doc_label = 'عقد النكاح', doc_label_en = 'Marriage contract' where code = 'marriage';
update public.leave_types set doc_label = 'شهادة الميلاد أو تبليغ الولادة', doc_label_en = 'Birth certificate or birth notification' where code in ('birth', 'newbornd');
update public.leave_types set doc_label = 'تقرير طبي بتاريخ الولادة', doc_label_en = 'Medical report with the delivery date' where code = 'maternity';
update public.leave_types set doc_label = 'تصريح الحج', doc_label_en = 'Hajj permit' where code = 'hajj';
-- the document number, so HR can verify it at the source (the sick-leave number is checked on the Seha platform)
alter table public.leave_types add column ref_label text, add column ref_label_en text, add column ref_required boolean not null default false;
update public.leave_types set ref_label = 'رقم الإجازة المرضية (من منصة صحة / صحتي)', ref_label_en = 'Sick leave number (from Seha / Sehhaty)', ref_required = true where code = 'sick';
update public.leave_types set ref_label = 'رقم شهادة الوفاة', ref_label_en = 'Death certificate number' where code in ('death', 'death2', 'iddah', 'iddahn');
update public.leave_types set ref_label = 'رقم عقد النكاح', ref_label_en = 'Marriage contract number' where code = 'marriage';
update public.leave_types set ref_label = 'رقم شهادة الميلاد', ref_label_en = 'Birth certificate number' where code in ('birth', 'newbornd');
update public.leave_types set ref_label = 'رقم تصريح الحج', ref_label_en = 'Hajj permit number' where code = 'hajj';

create table public.request_attachments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  request_id uuid not null references public.requests(id) on delete cascade,
  file_name text not null check (length(file_name) between 1 and 200),
  mime text not null check (mime in ('application/pdf','image/jpeg','image/png','image/webp')),
  size int not null check (size between 1 and 3145728),
  data text not null,
  uploaded_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index on public.request_attachments(request_id);

-- validates and stores files given as [{name, mime, data(base64)}]; checks the real file type, not just the name
create or replace function public.attach_files(p_req uuid, p_files jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare r public.requests; f jsonb; b bytea; m text; n int := 0;
begin
  select * into r from public.requests where id = p_req;
  if p_files is null or jsonb_typeof(p_files) <> 'array' or jsonb_array_length(p_files) = 0 then return 0; end if;
  if (select count(*) from public.request_attachments where request_id = p_req) + jsonb_array_length(p_files) > 5 then
    raise exception 'الحد الأقصى 5 مرفقات للطلب'; end if;
  for f in select * from jsonb_array_elements(p_files) loop
    m := f->>'mime';
    begin b := decode(coalesce(f->>'data', ''), 'base64'); exception when others then raise exception 'تعذّر قراءة المرفق «%»', coalesce(f->>'name', ''); end;
    if b is null or octet_length(b) = 0 then raise exception 'المرفق «%» فارغ', coalesce(f->>'name', ''); end if;
    if octet_length(b) > 3145728 then raise exception 'حجم المرفق «%» أكبر من 3 ميجابايت', coalesce(f->>'name', ''); end if;
    if not ((m = 'application/pdf' and substr(b, 1, 4) = '\x25504446'::bytea) or (m = 'image/jpeg' and substr(b, 1, 3) = '\xffd8ff'::bytea)
         or (m = 'image/png' and substr(b, 1, 4) = '\x89504e47'::bytea) or (m = 'image/webp' and substr(b, 1, 4) = '\x52494646'::bytea)) then
      raise exception 'المرفق «%» ليس صورة أو PDF', coalesce(f->>'name', ''); end if;
    insert into public.request_attachments(company_id, request_id, file_name, mime, size, data)
    values (r.company_id, p_req, left(coalesce(nullif(trim(f->>'name'), ''), 'مرفق'), 200), m, octet_length(b), encode(b, 'base64'));
    n := n + 1;
  end loop;
  return n;
end $$;

-- add files later to a pending request (the employee) or to any request (HR)
create or replace function public.request_attach(p_id uuid, p_files jsonb, p_ref text default null) returns int
language plpgsql security definer set search_path = public as $$
declare r public.requests; n int := 0; v text := upper(left(regexp_replace(coalesce(p_ref, ''), '\s', '', 'g'), 40));
begin
  select * into r from public.requests where id = p_id;
  if not found then raise exception 'الطلب غير موجود'; end if;
  if not (public.has_role(r.company_id, array['owner','admin','hr']) or (r.employee_id = public.my_employee(r.company_id) and r.status = 'pending')) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  if (p_files is null or jsonb_typeof(p_files) <> 'array' or jsonb_array_length(p_files) = 0) and v = '' then raise exception 'اختر ملفاً'; end if;
  if p_files is not null and jsonb_typeof(p_files) = 'array' and jsonb_array_length(p_files) > 0 then n := public.attach_files(p_id, p_files); end if;
  if v <> '' then update public.requests set payload = payload || jsonb_build_object('doc_ref', v) where id = p_id; end if;
  insert into public.request_actions(request_id, actor, action, note) values (p_id, auth.uid(), 'attached', case when n > 0 then n || ' مرفق' else 'رقم المستند ' || v end);
  return n;
end $$;

create or replace function public.submit_request(
  p_company uuid, p_kind text, p_sub text default null, p_from date default null, p_to date default null,
  p_amount numeric default null, p_payload jsonb default '{}', p_note text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := public.my_employee(p_company);
  e public.employees; lt public.leave_types; d int; used int; rt text[]; rid uuid; owner_emp uuid; k text; ev date; bal numeric; g numeric; minst int; v_files jsonb;
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


alter table public.request_actions drop constraint request_actions_action_check;
alter table public.request_actions add constraint request_actions_action_check check (action in ('submitted','approved','rejected','cancelled','attached'));

alter table public.request_attachments enable row level security;
create policy ra_read on public.request_attachments for select using (
  public.has_role(company_id, array['owner','admin','hr'])
  or exists(select 1 from public.requests q where q.id = request_id and q.employee_id = public.my_employee(q.company_id)));
revoke all on public.request_attachments from anon;
grant select on public.request_attachments to authenticated;
revoke insert, update, delete on public.request_attachments from authenticated;
revoke all on function public.attach_files(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.request_attach(uuid, jsonb, text) from public, anon;
grant execute on function public.request_attach(uuid, jsonb, text) to authenticated;
notify pgrst, 'reload schema';
