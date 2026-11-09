-- Bilingual data: English names next to the Arabic ones, so English screens, letters and printouts show them.
-- The UI shows the English value wherever the Arabic one appears when the interface is in English.
alter table public.companies add column name_en text;
alter table public.employees add column full_name_en text, add column job_title_en text;
alter table public.departments add column name_en text;

-- Excel/CSV import accepts the English name and job title
create or replace function public.import_employees(p_company uuid, p_rows jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare r jsonb; ln text; dep uuid; n int := 0; d date; seen text[] := '{}'; v text;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'الملف لا يحتوي موظفين'; end if;
  if jsonb_array_length(p_rows) > 1000 then raise exception 'الحد الأقصى 1000 موظف في الملف الواحد'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    ln := 'السطر ' || coalesce(r->>'_row', '?') || ': ';
    v := trim(coalesce(r->>'emp_no', ''));
    if v = '' then raise exception '%الرقم الوظيفي مطلوب', ln; end if;
    if v = any(seen) then raise exception '%الرقم الوظيفي % مكرر في الملف', ln, v; end if;
    seen := seen || v;
    if exists(select 1 from public.employees where company_id = p_company and emp_no = v) then raise exception '%الرقم الوظيفي % مسجّل مسبقاً', ln, v; end if;
    if length(trim(coalesce(r->>'full_name', ''))) < 3 then raise exception '%الاسم الكامل مطلوب', ln; end if;
    if coalesce(r->>'national_id', '') <> '' and r->>'national_id' !~ '^[12][0-9]{9}$' then raise exception '%رقم الهوية/الإقامة 10 أرقام يبدأ بـ 1 أو 2', ln; end if;
    if coalesce(r->>'iban', '') <> '' and r->>'iban' !~ '^SA[0-9]{22}$' then raise exception '%الآيبان يبدأ بـ SA ويليه 22 رقماً', ln; end if;
    if coalesce(r->>'gender', 'm') not in ('m','f') then raise exception '%الجنس: ذكر أو أنثى', ln; end if;
    begin d := (r->>'hire_date')::date; exception when others then d := null; end;
    if d is null then raise exception '%تاريخ المباشرة مطلوب بصيغة YYYY-MM-DD', ln; end if;
    if coalesce(r->>'probation_end', '') <> '' and (r->>'probation_end')::date > d + 179 then raise exception '%فترة التجربة لا تزيد على 180 يوماً — م53', ln; end if;
    if coalesce(r->>'basic', '') !~ '^[0-9]+(\.[0-9]+)?$' then raise exception '%الراتب الأساسي رقم مطلوب', ln; end if;
    if coalesce(r->>'housing', '') !~ '^([0-9]+(\.[0-9]+)?)?$' or coalesce(r->>'transport', '') !~ '^([0-9]+(\.[0-9]+)?)?$' then raise exception '%البدلات أرقام', ln; end if;
    dep := null;
    if coalesce(trim(r->>'department'), '') <> '' then
      select id into dep from public.departments where company_id = p_company and name = trim(r->>'department');
      if dep is null then insert into public.departments(company_id, name) values (p_company, trim(r->>'department')) returning id into dep; end if;
    end if;
    insert into public.employees(company_id, emp_no, full_name, national_id, is_saudi, gender, job_title, department_id, hire_date, probation_end, basic, housing, transport, iban, phone, email, full_name_en, job_title_en)
    values (p_company, v, trim(r->>'full_name'), nullif(r->>'national_id', ''), coalesce((r->>'is_saudi')::boolean, true), coalesce(r->>'gender', 'm'),
            nullif(trim(r->>'job_title'), ''), dep, d, nullif(r->>'probation_end', '')::date,
            (r->>'basic')::numeric, coalesce(nullif(r->>'housing', '')::numeric, 0), coalesce(nullif(r->>'transport', '')::numeric, 0),
            nullif(r->>'iban', ''), nullif(trim(r->>'phone'), ''), nullif(trim(r->>'email'), ''),
            nullif(trim(r->>'full_name_en'), ''), nullif(trim(r->>'job_title_en'), ''));
    n := n + 1;
  end loop;
  -- managers last, so a manager can appear anywhere in the file
  for r in select * from jsonb_array_elements(p_rows) where coalesce(value->>'manager_emp_no', '') <> '' loop
    if r->>'manager_emp_no' = r->>'emp_no' then raise exception 'السطر %: لا يكون الموظف مديراً لنفسه', r->>'_row'; end if;
    update public.employees e set manager_id = m.id from public.employees m
     where e.company_id = p_company and e.emp_no = trim(r->>'emp_no') and m.company_id = p_company and m.emp_no = trim(r->>'manager_emp_no');
    if not found then raise exception 'السطر %: المدير المباشر % غير موجود', r->>'_row', r->>'manager_emp_no'; end if;
  end loop;
  return n;
end $$;

-- English letters default to the stored English names
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
      'en', jsonb_strip_nulls(jsonb_build_object('name', coalesce(nullif(trim(p_en->>'name'), ''), e.full_name_en), 'job', coalesce(nullif(trim(p_en->>'job'), ''), e.job_title_en),
        'company', coalesce(nullif(trim(p_en->>'company'), ''), c.name_en))),
      'date', td))
  returning * into l;
  return l;
end $$;
notify pgrst, 'reload schema';
