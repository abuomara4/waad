-- Waad ERP — 0047 employee profile: personal/official fields, cost center & work site, opening leave balance.
-- Nationality (ISO code) drives is_saudi; birth date enforces Art. 162 (no work under 15); opening annual-leave
-- balance lets a company that moves to Waad start from its real balances instead of "all leave since hiring".

alter table public.employees
  add column if not exists nationality text,
  add column if not exists birth_date date,
  add column if not exists marital_status text,
  add column if not exists dependents int,
  add column if not exists official_profession text,
  add column if not exists education text,
  add column if not exists specialization text,
  add column if not exists emergency_name text,
  add column if not exists emergency_relation text,
  add column if not exists emergency_phone text,
  add column if not exists short_address text,
  add column if not exists national_address text,
  add column if not exists cost_center_id uuid references public.cost_centers(id) on delete set null,
  add column if not exists work_site_id uuid references public.work_sites(id) on delete set null,
  add column if not exists leave_open_days numeric(7,2),
  add column if not exists leave_open_date date;
create index if not exists employees_cost_center on public.employees(cost_center_id);

create or replace function public.employees_profile_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  new.nationality := nullif(upper(trim(coalesce(new.nationality, ''))), '');
  if new.nationality is not null then
    if new.nationality !~ '^[A-Z]{2}$' then raise exception 'رمز الجنسية غير صحيح'; end if;
    new.is_saudi := new.nationality = 'SA';
  end if;
  if new.birth_date is not null then
    if new.birth_date > current_date then raise exception 'تاريخ الميلاد في المستقبل'; end if;
    if new.birth_date > (new.hire_date - interval '15 years')::date then raise exception 'لا يجوز تشغيل من لم يتم 15 سنة — م162'; end if;
  end if;
  if new.marital_status is not null and new.marital_status not in ('single','married','divorced','widowed') then raise exception 'الحالة الاجتماعية غير صحيحة'; end if;
  if new.dependents is not null and (new.dependents < 0 or new.dependents > 30) then raise exception 'عدد المرافقين بين 0 و30'; end if;
  if new.education is not null and new.education not in ('none','primary','intermediate','secondary','diploma','bachelor','master','phd') then raise exception 'المؤهل الدراسي غير صحيح'; end if;
  new.short_address := nullif(upper(replace(trim(coalesce(new.short_address, '')), ' ', '')), '');
  if new.short_address is not null and new.short_address !~ '^[A-Z]{4}[0-9]{4}$' then raise exception 'العنوان المختصر 4 حروف و4 أرقام مثل RRRD2929'; end if;
  if new.emergency_phone is not null and new.emergency_phone !~ '^\+?[0-9 ]{7,16}$' then raise exception 'رقم جوال الطوارئ غير صحيح'; end if;
  if new.cost_center_id is not null and not exists(select 1 from public.cost_centers where id = new.cost_center_id and company_id = new.company_id) then
    raise exception 'مركز التكلفة غير موجود'; end if;
  if new.work_site_id is not null and not exists(select 1 from public.work_sites where id = new.work_site_id and company_id = new.company_id) then
    raise exception 'موقع العمل غير موجود'; end if;
  if tg_op = 'UPDATE' and old.is_saudi and not new.is_saudi and exists(select 1 from public.contracts c where c.employee_id = new.id and c.status = 'active' and c.contract_type = 'indefinite') then
    raise exception 'للموظف عقد غير محدد المدة، وعقد غير السعودي محدد المدة — عدّل العقد أولاً (م37)'; end if;
  if new.leave_open_days is not null and new.leave_open_date is null then new.leave_open_date := current_date; end if;
  if new.leave_open_date is not null then
    if new.leave_open_days is null then raise exception 'أدخل رصيد الإجازة الافتتاحي'; end if;
    if new.leave_open_days < 0 or new.leave_open_days > 999 then raise exception 'رصيد الإجازة الافتتاحي بين 0 و999 يوماً'; end if;
    if new.leave_open_date < new.hire_date then raise exception 'تاريخ الرصيد الافتتاحي قبل تاريخ المباشرة'; end if;
    if new.leave_open_date > current_date then raise exception 'تاريخ الرصيد الافتتاحي في المستقبل'; end if;
  end if;
  return new;
end $$;
drop trigger if exists employees_profile_guard on public.employees;
create trigger employees_profile_guard before insert or update on public.employees for each row execute function public.employees_profile_guard();
revoke all on function public.employees_profile_guard() from public, anon;

-- ---------- annual leave with an optional opening balance (as at the end of leave_open_date) ----------
create or replace function public.annual_leave_raw(e public.employees, p_as_of date) returns table(accrued numeric, taken numeric)
language sql stable security definer set search_path = public as $$
  select case when e.leave_open_date is null then public.annual_leave_accrued(e.hire_date, p_as_of)
              else e.leave_open_days + greatest(0, public.annual_leave_accrued(e.hire_date, p_as_of) - public.annual_leave_accrued(e.hire_date, e.leave_open_date)) end,
         (select coalesce(sum(r.days), 0) from public.requests r where r.employee_id = e.id and r.kind = 'leave' and r.sub = 'annual'
             and r.status in ('pending','approved') and (e.leave_open_date is null or r.from_date > e.leave_open_date))::numeric
$$;
revoke all on function public.annual_leave_raw(public.employees, date) from public, anon, authenticated;

create or replace function public.annual_leave_balance(p_emp uuid, p_as_of date default current_date)
returns table(accrued numeric, taken numeric, balance numeric)
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; x record;
begin
  select * into e from public.employees where id = p_emp;
  if not found then return; end if;
  if not (p_emp = public.my_employee(e.company_id) or public.has_role(e.company_id, array['owner','admin','hr','finance'])
          or e.manager_id = public.my_employee(e.company_id)) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  select * into x from public.annual_leave_raw(e, p_as_of);
  return query select round(x.accrued, 2), x.taken, round(x.accrued - x.taken, 2);
end $$;

-- ---------- apply the new profile fields from an import / bulk-update row (only the keys present) ----------
create or replace function public.emp_apply_profile(p_company uuid, p_emp uuid, r jsonb, ln text) returns void
language plpgsql security definer set search_path = public as $$
declare cc uuid; ws uuid; v text; k text;
begin
  foreach k in array array['birth_date','leave_open_date'] loop
    if coalesce(r->>k, '') <> '' and r->>k !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception '%التاريخ بصيغة YYYY-MM-DD (%)', ln, r->>k; end if;
  end loop;
  if coalesce(r->>'dependents', '') !~ '^([0-9]+)?$' then raise exception '%عدد المرافقين رقم', ln; end if;
  if coalesce(r->>'leave_open_days', '') !~ '^([0-9]+(\.[0-9]+)?)?$' then raise exception '%رصيد الإجازة الافتتاحي رقم', ln; end if;
  if r ? 'cost_center' then
    v := nullif(trim(coalesce(r->>'cost_center', '')), ''); cc := null;
    if v is not null then
      select id into cc from public.cost_centers where company_id = p_company and (code = v or name = v or name_en = v) limit 1;
      if cc is null then raise exception '%مركز التكلفة «%» غير موجود', ln, v; end if;
    end if;
  end if;
  if r ? 'work_site' then
    v := nullif(trim(coalesce(r->>'work_site', '')), ''); ws := null;
    if v is not null then
      select id into ws from public.work_sites where company_id = p_company and (name = v or name_en = v) limit 1;
      if ws is null then raise exception '%موقع العمل «%» غير موجود', ln, v; end if;
    end if;
  end if;
  begin
    update public.employees set
      nationality = case when r ? 'nationality' then nullif(trim(coalesce(r->>'nationality', '')), '') else nationality end,
      birth_date = case when r ? 'birth_date' then nullif(r->>'birth_date', '')::date else birth_date end,
      marital_status = case when r ? 'marital_status' then nullif(r->>'marital_status', '') else marital_status end,
      dependents = case when r ? 'dependents' then nullif(r->>'dependents', '')::int else dependents end,
      official_profession = case when r ? 'official_profession' then nullif(trim(coalesce(r->>'official_profession', '')), '') else official_profession end,
      education = case when r ? 'education' then nullif(r->>'education', '') else education end,
      specialization = case when r ? 'specialization' then nullif(trim(coalesce(r->>'specialization', '')), '') else specialization end,
      emergency_name = case when r ? 'emergency_name' then nullif(trim(coalesce(r->>'emergency_name', '')), '') else emergency_name end,
      emergency_relation = case when r ? 'emergency_relation' then nullif(trim(coalesce(r->>'emergency_relation', '')), '') else emergency_relation end,
      emergency_phone = case when r ? 'emergency_phone' then nullif(trim(coalesce(r->>'emergency_phone', '')), '') else emergency_phone end,
      short_address = case when r ? 'short_address' then nullif(trim(coalesce(r->>'short_address', '')), '') else short_address end,
      national_address = case when r ? 'national_address' then nullif(trim(coalesce(r->>'national_address', '')), '') else national_address end,
      cost_center_id = case when r ? 'cost_center' then cc else cost_center_id end,
      work_site_id = case when r ? 'work_site' then ws else work_site_id end,
      leave_open_days = case when r ? 'leave_open_days' then nullif(r->>'leave_open_days', '')::numeric else leave_open_days end,
      leave_open_date = case when r ? 'leave_open_date' then nullif(r->>'leave_open_date', '')::date
                             when r ? 'leave_open_days' and coalesce(r->>'leave_open_days', '') = '' then null else leave_open_date end
    where id = p_emp;
  exception when raise_exception then raise exception '%', ln || sqlerrm;
  end;
end $$;
revoke all on function public.emp_apply_profile(uuid, uuid, jsonb, text) from public, anon, authenticated;

-- ---------- import / bulk update carry the new fields ----------
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
    perform public.emp_apply_profile(p_company, (select id from public.employees where company_id = p_company and emp_no = v), r, ln);
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

create or replace function public.update_employees(p_company uuid, p_rows jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare r jsonb; ln text; e public.employees; k text; dep uuid; n int := 0; seen uuid[] := '{}'; v text; mgr uuid;
  allowed text[] := array['_row','emp_no','full_name','full_name_en','national_id','is_saudi','gender','job_title','job_title_en','department','manager_emp_no','phone','email','iban','nationality','birth_date','marital_status','dependents','official_profession','education','specialization','emergency_name','emergency_relation','emergency_phone','short_address','national_address','cost_center','work_site','leave_open_days','leave_open_date'];
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'لا توجد تغييرات في الملف'; end if;
  if jsonb_array_length(p_rows) > 3000 then raise exception 'الحد الأقصى 3000 سطر في الملف الواحد'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    ln := 'السطر ' || coalesce(r->>'_row', '?') || ': ';
    select * into e from public.employees where company_id = p_company and emp_no = trim(coalesce(r->>'emp_no', '')) for update;
    if not found then raise exception '%الرقم الوظيفي % غير موجود', ln, coalesce(r->>'emp_no', ''); end if;
    if e.id = any(seen) then raise exception '%الرقم الوظيفي % مكرر في الملف', ln, e.emp_no; end if;
    seen := seen || e.id;
    for k in select jsonb_object_keys(r) loop
      if not (k = any(allowed)) then raise exception '%لا يمكن تحديث الحقل «%» من الملف', ln, k; end if;
    end loop;
    if r ? 'full_name' and length(trim(coalesce(r->>'full_name', ''))) < 3 then raise exception '%الاسم الكامل لا يُمسح', ln; end if;
    if coalesce(r->>'national_id', '') <> '' and r->>'national_id' !~ '^[12][0-9]{9}$' then raise exception '%رقم الهوية/الإقامة 10 أرقام يبدأ بـ 1 أو 2', ln; end if;
    if coalesce(r->>'iban', '') <> '' and r->>'iban' !~ '^SA[0-9]{22}$' then raise exception '%الآيبان يبدأ بـ SA ويليه 22 رقماً', ln; end if;
    if coalesce(r->>'phone', '') <> '' and r->>'phone' !~ '^(05[0-9]{8}|\+9665[0-9]{8})$' then raise exception '%رقم الجوال بصيغة 05XXXXXXXX', ln; end if;
    if coalesce(r->>'email', '') <> '' and r->>'email' !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception '%البريد الإلكتروني غير صحيح', ln; end if;
    if r ? 'gender' and coalesce(r->>'gender', '') not in ('m','f') then raise exception '%الجنس: ذكر أو أنثى', ln; end if;
    if r ? 'is_saudi' and coalesce(r->>'is_saudi', '') not in ('true','false') then raise exception '%الجنسية: سعودي أو غير سعودي', ln; end if;
    if r ? 'is_saudi' and r->>'is_saudi' = 'false' and exists(select 1 from public.contracts c where c.employee_id = e.id and c.status = 'active' and c.contract_type = 'indefinite') then
      raise exception '%للموظف عقد غير محدد المدة، وعقد غير السعودي محدد المدة — عدّل العقد أولاً (م37)', ln; end if;
    dep := e.department_id;
    if r ? 'department' then
      v := nullif(trim(coalesce(r->>'department', '')), '');
      if v is null then dep := null;
      else
        select id into dep from public.departments where company_id = p_company and name = v;
        if dep is null then insert into public.departments(company_id, name) values (p_company, v) returning id into dep; end if;
      end if;
    end if;
    update public.employees set
      full_name = case when r ? 'full_name' then trim(r->>'full_name') else full_name end,
      full_name_en = case when r ? 'full_name_en' then nullif(trim(coalesce(r->>'full_name_en', '')), '') else full_name_en end,
      national_id = case when r ? 'national_id' then nullif(r->>'national_id', '') else national_id end,
      is_saudi = case when r ? 'is_saudi' then (r->>'is_saudi')::boolean else is_saudi end,
      gender = case when r ? 'gender' then r->>'gender' else gender end,
      job_title = case when r ? 'job_title' then nullif(trim(coalesce(r->>'job_title', '')), '') else job_title end,
      job_title_en = case when r ? 'job_title_en' then nullif(trim(coalesce(r->>'job_title_en', '')), '') else job_title_en end,
      department_id = dep,
      phone = case when r ? 'phone' then nullif(r->>'phone', '') else phone end,
      email = case when r ? 'email' then nullif(trim(coalesce(r->>'email', '')), '') else email end,
      iban = case when r ? 'iban' then nullif(r->>'iban', '') else iban end
    where id = e.id;
    perform public.emp_apply_profile(p_company, e.id, r, ln);
    n := n + 1;
  end loop;
  -- reporting lines last: detach the rows being moved first, then attach them one by one, so the result is checked
  -- for loops as a whole (a valid swap of two managers is not refused half-way)
  update public.employees em set manager_id = null from jsonb_array_elements(p_rows) x
   where x.value ? 'manager_emp_no' and em.company_id = p_company and em.emp_no = trim(x.value->>'emp_no');
  for r in select * from jsonb_array_elements(p_rows) where value ? 'manager_emp_no' loop
    ln := 'السطر ' || coalesce(r->>'_row', '?') || ': ';
    mgr := null;
    if coalesce(trim(r->>'manager_emp_no'), '') <> '' then
      select id into mgr from public.employees where company_id = p_company and emp_no = trim(r->>'manager_emp_no');
      if mgr is null then raise exception '%المدير المباشر % غير موجود', ln, r->>'manager_emp_no'; end if;
    end if;
    begin
      update public.employees set manager_id = mgr where company_id = p_company and emp_no = trim(r->>'emp_no');
    exception when raise_exception or check_violation then
      raise exception '%', ln || sqlerrm;
    end;
  end loop;
  return n;
end $$;

-- ---------- leave requests use the opening balance; employees can ask to update personal fields ----------
create or replace function public.update_request_fields() returns text[] language sql immutable as $$
  select array['phone','email','iban','marital_status','dependents','emergency_name','emergency_relation','emergency_phone','short_address','national_address']
$$;
revoke all on function public.update_request_fields() from public, anon, authenticated;
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
      select x.taken, floor(x.accrued - x.taken) into used, bal from public.annual_leave_raw(e, p_to) x;
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
    if p_payload ? 'short_address' and upper(replace(coalesce(p_payload->>'short_address',''), ' ', '')) !~ '^([A-Z]{4}[0-9]{4})?$' then raise exception 'العنوان المختصر 4 حروف و4 أرقام مثل RRRD2929'; end if;
    if p_payload ? 'marital_status' and coalesce(p_payload->>'marital_status','') not in ('', 'single','married','divorced','widowed') then raise exception 'الحالة الاجتماعية غير صحيحة'; end if;
    if p_payload ? 'dependents' and coalesce(p_payload->>'dependents','') !~ '^([0-9]|[12][0-9]|30)?$' then raise exception 'عدد المرافقين بين 0 و30'; end if;
    if p_payload ? 'emergency_phone' and coalesce(p_payload->>'emergency_phone','') !~ '^(\+?[0-9 ]{7,16})?$' then raise exception 'رقم جوال الطوارئ غير صحيح'; end if;
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
    perform public.emp_apply_profile(r.company_id, r.employee_id, r.payload - 'phone' - 'email' - 'iban', '');
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

-- ---------- payroll entry by cost center ----------
create or replace function public.payroll_approve(p_run uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; t record; me date; je uuid; pp record; exl jsonb;
begin
  select * into r from public.payroll_runs where id = p_run for update;
  perform public.require_role(r.company_id, array['owner','finance']);
  if r.status <> 'draft' then raise exception 'المسير معتمد مسبقاً'; end if;
  select coalesce(sum(gross + arrears + overtime + bonus - absence - att_absence - late_deduction - sick_deduction - damages),0) ex, coalesce(sum(gosi),0) g, coalesce(sum(employer_gosi),0) eg,
         coalesce(sum(advance),0) adv, coalesce(sum(net),0) n, coalesce(sum(deductions + penalty_fine),0) fines, count(*) c
    into t from public.payroll_lines where run_id = p_run;
  if t.c = 0 then raise exception 'المسير فارغ'; end if;
  insert into public.accounts(company_id, code, name, type, parent_code, is_header)
  values (r.company_id, '2450', 'غرامات العاملين — لصالح العمال (م73)', 'liab', '2000', false) on conflict do nothing;
  -- salary and employer-GOSI expense split by each employee's cost center
  select coalesce(jsonb_agg(x), '[]'::jsonb) into exl from (
    select jsonb_build_object('a','5200','d', sum(l.gross + l.arrears + l.overtime + l.bonus - l.absence - l.att_absence - l.late_deduction - l.sick_deduction - l.damages), 'cc', e.cost_center_id) x
      from public.payroll_lines l join public.employees e on e.id = l.employee_id where l.run_id = p_run group by e.cost_center_id
    union all
    select jsonb_build_object('a','5210','d', sum(l.employer_gosi), 'cc', e.cost_center_id)
      from public.payroll_lines l join public.employees e on e.id = l.employee_id where l.run_id = p_run group by e.cost_center_id) q;
  me := (make_date(r.year, r.month, 1) + interval '1 month - 1 day')::date;
  je := public.post_journal(r.company_id, me, 'استحقاق رواتب ' || lpad(r.month::text,2,'0') || '/' || r.year, 'payroll', r.id,
    exl || jsonb_build_array(jsonb_build_object('a','2400','c',t.g + t.eg), jsonb_build_object('a','1500','c',t.adv),
                      jsonb_build_object('a','2450','c',t.fines), jsonb_build_object('a','2300','c',t.n)));
  select * into pp from public.payroll_period(r.company_id, r.year, r.month);
  update public.payroll_runs set status = 'approved', approved_by = auth.uid(), approved_at = now(), att_from = pp.ps, att_to = least(pp.pe, me) where id = p_run;
  return je;
end $$;

-- ---------- an employee with an assigned work site checks in only there ----------
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
  if c.att_geofence and exists(select 1 from public.work_sites where company_id = p_company) then
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
