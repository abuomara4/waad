-- Ready-made HR letters: salary certificate (تعريف بالراتب) and service certificate (شهادة خدمة, Labor Law Art. 64).
-- Each issue is logged with a reference number and a snapshot of the data printed, so a reprint shows exactly what was issued.
-- Art. 64: the service certificate states the join date, the end date, the occupation and the last wage, is free of charge,
-- and must not contain anything that harms the worker's reputation — so it carries no free text (no end reason, no notes).

create table public.letters (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  kind text not null check (kind in ('salary','service')),
  lang text not null default 'ar' check (lang in ('ar','en')),
  ref_no text not null,
  addressee text,
  with_salary boolean not null default true,
  request_id uuid references public.requests(id) on delete set null,
  data jsonb not null,
  issued_by uuid default auth.uid(),
  issued_at timestamptz not null default now(),
  unique (company_id, ref_no)
);
create index on public.letters(employee_id);
create unique index letters_one_per_request on public.letters(request_id, lang) where request_id is not null;

create or replace function public.issue_letter(p_emp uuid, p_kind text, p_lang text default 'ar', p_to text default null,
  p_salary boolean default true, p_nat text default null, p_request uuid default null, p_en jsonb default null)
returns public.letters language plpgsql security definer set search_path = public as $$
declare e public.employees; c public.companies; r public.requests; hr boolean; td date := (now() at time zone 'Asia/Riyadh')::date;
  dept text; l public.letters; v_sal boolean := coalesce(p_salary, true);
begin
  select * into e from public.employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود'; end if;
  hr := public.has_role(e.company_id, array['owner','admin','hr']);
  if not hr then
    -- an employee prints own salary certificate only against an approved request
    if e.id is distinct from public.my_employee(e.company_id) or p_kind <> 'salary' then raise exception 'غير مصرح' using errcode = '42501'; end if;
    select * into r from public.requests where id = p_request and employee_id = e.id and kind = 'cert' and status = 'approved';
    if not found then raise exception 'يصدر الخطاب بعد اعتماد طلب التعريف بالراتب'; end if;
  elsif p_request is not null then
    select * into r from public.requests where id = p_request and employee_id = e.id and kind = 'cert';
    if not found then raise exception 'الطلب لا يخص هذا الموظف'; end if;
  end if;
  if p_kind not in ('salary','service') then raise exception 'نوع الخطاب غير معروف'; end if;
  if coalesce(p_lang, 'ar') not in ('ar','en') then raise exception 'لغة الخطاب غير معروفة'; end if;
  if p_kind = 'salary' and e.end_date is not null and e.end_date < td then
    raise exception 'الموظف ليس على رأس العمل — أصدر له شهادة خدمة'; end if;
  if p_kind = 'service' then
    if e.end_date is null then raise exception 'شهادة الخدمة تصدر عند انتهاء العلاقة التعاقدية — سجّل تاريخ نهاية الخدمة أولاً (م64)'; end if;
    if e.end_date > td then raise exception 'تصدر شهادة الخدمة في آخر يوم عمل أو بعده (م64)'; end if;
    v_sal := true;   -- Art. 64: the last wage is a required part of the certificate
  end if;
  if r.id is not null and exists(select 1 from public.letters where request_id = r.id and lang = coalesce(p_lang, 'ar')) then
    raise exception 'صدر خطاب لهذا الطلب بهذه اللغة — اطبعه من سجل الخطابات'; end if;
  select * into c from public.companies where id = e.company_id;
  select name into dept from public.departments where id = e.department_id;
  insert into public.letters(company_id, employee_id, kind, lang, ref_no, addressee, with_salary, request_id, data)
  values (e.company_id, e.id, p_kind, coalesce(p_lang, 'ar'), public.next_doc_no(e.company_id, 'LTR'), nullif(trim(p_to), ''), v_sal, r.id,
    jsonb_build_object(
      'company', jsonb_build_object('name', c.name, 'cr_no', c.cr_no, 'vat_no', c.vat_no, 'address', c.address),
      'employee', jsonb_build_object('full_name', e.full_name, 'emp_no', e.emp_no, 'gender', e.gender, 'is_saudi', e.is_saudi,
        'nationality', coalesce(nullif(trim(p_nat), ''), case when e.is_saudi then 'سعودي' end), 'national_id', e.national_id,
        'job_title', e.job_title, 'department', dept, 'hire_date', e.hire_date, 'end_date', case when p_kind = 'service' then e.end_date end),
      'wage', case when v_sal then jsonb_build_object('basic', e.basic, 'housing', e.housing, 'transport', e.transport, 'gross', public.gross_wage(e)) end,
      'en', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(p_en->>'name'), ''), 'job', nullif(trim(p_en->>'job'), ''), 'company', nullif(trim(p_en->>'company'), ''))),
      'date', td))
  returning * into l;
  return l;
end $$;

create trigger audit_letters after insert or update or delete on public.letters for each row execute function public.audit_trigger();
alter table public.letters enable row level security;
create policy letters_read on public.letters for select using (public.has_role(company_id, array['owner','admin','hr']) or employee_id = public.my_employee(company_id));
revoke all on public.letters from anon;
grant select on public.letters to authenticated;
revoke insert, update, delete on public.letters from authenticated;
revoke all on function public.issue_letter(uuid, text, text, text, boolean, text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.issue_letter(uuid, text, text, text, boolean, text, uuid, jsonb) to authenticated;
notify pgrst, 'reload schema';
