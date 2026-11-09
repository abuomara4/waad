-- Bulk update of employee data from Excel. Each row carries only the fields that change (a JSON null clears an
-- optional field). All-or-nothing. Wages are not updated here: they go through salary_change with a reason.

create or replace function public.update_employees(p_company uuid, p_rows jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare r jsonb; ln text; e public.employees; k text; dep uuid; n int := 0; seen uuid[] := '{}'; v text; mgr uuid;
  allowed text[] := array['_row','emp_no','full_name','full_name_en','national_id','is_saudi','gender','job_title','job_title_en','department','manager_emp_no','phone','email','iban'];
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

revoke all on function public.update_employees(uuid, jsonb) from public, anon;
grant execute on function public.update_employees(uuid, jsonb) to authenticated;
notify pgrst, 'reload schema';
