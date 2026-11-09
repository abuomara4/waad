-- Bilingual data everywhere: an English name next to every name or title people type — finance (accounts, customers,
-- suppliers, items), attendance (work sites, shifts, holidays), talent (review cycles, job openings, candidates,
-- trainings) and documents. The English interface shows these wherever the Arabic one would appear.
alter table public.accounts add column name_en text;
alter table public.parties add column name_en text;
alter table public.items add column name_en text;
alter table public.work_sites add column name_en text;
alter table public.shifts add column name_en text;
alter table public.holidays add column name_en text;
alter table public.review_cycles add column name_en text;
alter table public.job_openings add column title_en text;
alter table public.candidates add column full_name_en text;
alter table public.trainings add column title_en text;
alter table public.employee_documents add column title_en text;

-- (system account names seeded in Arabic are translated by the interface dictionary)

-- English name for an account and a review cycle (both are created through functions)
create or replace function public.account_set_name_en(p_company uuid, p_code text, p_name_en text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'coa');
  update public.accounts set name_en = nullif(trim(p_name_en), '') where company_id = p_company and code = p_code;
  if not found then raise exception 'الحساب غير موجود'; end if;
end $$;
create or replace function public.review_cycle_set_name_en(p_id uuid, p_name_en text) returns void
language plpgsql security definer set search_path = public as $$
declare c uuid;
begin
  select company_id into c from public.review_cycles where id = p_id;
  if c is null then raise exception 'الدورة غير موجودة'; end if;
  perform public.require_role(c, array['owner','admin','hr']);
  update public.review_cycles set name_en = nullif(trim(p_name_en), '') where id = p_id;
end $$;

-- hiring a candidate carries the English name, and the opening's English title when the job title is not changed
create or replace function public.hire_candidate(p_cand uuid, p_emp jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare c public.candidates; o public.job_openings; eid uuid; hired int;
begin
  select * into c from public.candidates where id = p_cand for update;
  if not found then raise exception 'المرشح غير موجود'; end if;
  perform public.require_role(c.company_id, array['owner','admin','hr']);
  if c.stage in ('hired','rejected') then raise exception 'لا يمكن تعيين مرشح مرحلته «%»', case c.stage when 'hired' then 'تم التعيين' else 'مرفوض' end; end if;
  select * into o from public.job_openings where id = c.opening_id;
  if coalesce(p_emp->>'emp_no', '') = '' then raise exception 'أدخل الرقم الوظيفي'; end if;
  if exists(select 1 from public.employees where company_id = c.company_id and emp_no = p_emp->>'emp_no') then raise exception 'الرقم الوظيفي مستخدم مسبقاً'; end if;
  if coalesce((p_emp->>'basic')::numeric, -1) < 0 then raise exception 'أدخل الراتب الأساسي'; end if;
  if nullif(p_emp->>'department_id', '') is not null and not exists(select 1 from public.departments where id = (p_emp->>'department_id')::uuid and company_id = c.company_id) then raise exception 'القسم غير موجود'; end if;
  if nullif(p_emp->>'manager_id', '') is not null and not exists(select 1 from public.employees where id = (p_emp->>'manager_id')::uuid and company_id = c.company_id) then raise exception 'المدير المباشر غير موجود'; end if;
  if nullif(p_emp->>'probation_end', '') is not null and (p_emp->>'probation_end')::date > coalesce((p_emp->>'hire_date')::date, current_date) + 179 then
    raise exception 'فترة التجربة لا تزيد على 180 يوماً — م53'; end if;
  insert into public.employees(company_id, emp_no, full_name, national_id, is_saudi, gender, job_title, department_id, manager_id, hire_date, probation_end, basic, housing, transport, phone, email, full_name_en, job_title_en)
  values (c.company_id, p_emp->>'emp_no', c.full_name, c.national_id, c.is_saudi, c.gender, coalesce(nullif(p_emp->>'job_title', ''), o.title),
          coalesce(nullif(p_emp->>'department_id', '')::uuid, o.department_id), nullif(p_emp->>'manager_id', '')::uuid,
          coalesce(nullif(p_emp->>'hire_date', '')::date, current_date), nullif(p_emp->>'probation_end', '')::date,
          (p_emp->>'basic')::numeric, coalesce(nullif(p_emp->>'housing', '')::numeric, 0), coalesce(nullif(p_emp->>'transport', '')::numeric, 0), c.phone, c.email,
          c.full_name_en, case when nullif(p_emp->>'job_title', '') is null then o.title_en end)
  returning id into eid;
  perform set_config('waad.hiring', 'on', true);
  update public.candidates set stage = 'hired', employee_id = eid where id = p_cand;
  perform set_config('waad.hiring', 'off', true);
  select count(*) into hired from public.candidates where opening_id = o.id and stage = 'hired';
  if hired >= o.positions then update public.job_openings set status = 'closed' where id = o.id; end if;
  return eid;
end $$;

revoke all on function public.account_set_name_en(uuid, text, text), public.review_cycle_set_name_en(uuid, text) from public, anon;
grant execute on function public.account_set_name_en(uuid, text, text), public.review_cycle_set_name_en(uuid, text) to authenticated;
notify pgrst, 'reload schema';
