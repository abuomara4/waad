-- Waad ERP — 0009 talent: performance reviews, recruitment, training, bulk employee import.

-- ---------- performance reviews ----------
create table public.review_cycles (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null check (length(trim(name)) >= 3),
  period_start date not null,
  period_end date not null,
  status text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now(),
  unique (company_id, name),
  check (period_end >= period_start)
);
create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  cycle_id uuid not null references public.review_cycles(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  reviewer_id uuid references public.employees(id) on delete set null,
  status text not null default 'draft' check (status in ('draft','submitted','approved')),
  goals jsonb not null default '[]',          -- [{"t": title, "w": weight %, "s": score 1-5, "c": comment}]
  overall numeric(3,2),
  strengths text, improvements text, manager_comment text, hr_comment text,
  submitted_at timestamptz, approved_at timestamptz,
  ack_at timestamptz, employee_comment text,
  created_at timestamptz not null default now(),
  unique (cycle_id, employee_id)
);
create index on public.reviews(company_id);
create index on public.reviews(reviewer_id);

create or replace function public.start_review_cycle(p_company uuid, p_name text, p_start date, p_end date) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if p_start is null or p_end is null or p_end < p_start then raise exception 'حدد فترة التقييم بشكل صحيح'; end if;
  insert into public.review_cycles(company_id, name, period_start, period_end) values (p_company, trim(p_name), p_start, p_end) returning id into cid;
  insert into public.reviews(company_id, cycle_id, employee_id, reviewer_id)
    select p_company, cid, e.id, e.manager_id from public.employees e
     where e.company_id = p_company and e.hire_date <= p_end and (e.end_date is null or e.end_date >= p_end);
  if not found then raise exception 'لا يوجد موظفون على رأس العمل في هذه الفترة'; end if;
  return cid;
end $$;

create or replace function public.save_review(p_id uuid, p_goals jsonb, p_strengths text, p_improvements text, p_comment text, p_submit boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare r public.reviews; c public.review_cycles; g jsonb; tw numeric := 0; ov numeric := 0; n int := 0; me uuid; hr boolean;
begin
  select * into r from public.reviews where id = p_id for update;
  if not found then raise exception 'التقييم غير موجود'; end if;
  me := public.my_employee(r.company_id); hr := public.has_role(r.company_id, array['owner','admin','hr']);
  if me is not null and me = r.employee_id then raise exception 'لا يمكنك تقييم نفسك' using errcode = '42501'; end if;
  if not (hr or (me is not null and me = r.reviewer_id)) then raise exception 'غير مصرح: التقييم للمدير المباشر أو الموارد البشرية' using errcode = '42501'; end if;
  select * into c from public.review_cycles where id = r.cycle_id;
  if c.status <> 'open' then raise exception 'دورة التقييم مغلقة'; end if;
  if r.status <> 'draft' then raise exception 'أُرسل التقييم ولا يمكن تعديله إلا إذا أعادته الموارد البشرية'; end if;
  if jsonb_typeof(coalesce(p_goals, '[]')) <> 'array' or jsonb_array_length(coalesce(p_goals, '[]')) > 10 then raise exception 'الأهداف من 1 إلى 10'; end if;
  for g in select * from jsonb_array_elements(coalesce(p_goals, '[]')) loop
    n := n + 1;
    if length(trim(coalesce(g->>'t', ''))) < 2 then raise exception 'اكتب عنوان الهدف %', n; end if;
    if coalesce((g->>'w')::numeric, 0) <= 0 then raise exception 'وزن الهدف % يجب أن يكون أكبر من صفر', n; end if;
    if g->>'s' is not null and (g->>'s')::numeric not in (1,2,3,4,5) then raise exception 'درجة الهدف % من 1 إلى 5', n; end if;
    tw := tw + (g->>'w')::numeric;
    ov := ov + (g->>'w')::numeric * coalesce((g->>'s')::numeric, 0);
  end loop;
  if p_submit then
    if n = 0 then raise exception 'أضف هدفاً واحداً على الأقل'; end if;
    if tw <> 100 then raise exception 'مجموع أوزان الأهداف يجب أن يساوي 100%% (الحالي %)', tw; end if;
    if exists(select 1 from jsonb_array_elements(p_goals) x where x->>'s' is null) then raise exception 'أعط درجة لكل هدف قبل الإرسال'; end if;
  end if;
  update public.reviews set goals = coalesce(p_goals, '[]'), strengths = nullif(trim(p_strengths), ''), improvements = nullif(trim(p_improvements), ''),
         manager_comment = nullif(trim(p_comment), ''), overall = case when tw = 100 then round(ov / 100, 2) end,
         status = case when p_submit then 'submitted' else 'draft' end, submitted_at = case when p_submit then now() end
   where id = p_id;
end $$;

create or replace function public.decide_review(p_id uuid, p_approve boolean, p_comment text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r public.reviews;
begin
  select * into r from public.reviews where id = p_id for update;
  if not found then raise exception 'التقييم غير موجود'; end if;
  perform public.require_role(r.company_id, array['owner','admin','hr']);
  if r.status <> 'submitted' then raise exception 'التقييم ليس بانتظار الاعتماد'; end if;
  if not p_approve and length(trim(coalesce(p_comment, ''))) < 3 then raise exception 'اكتب سبب الإعادة للمقيّم'; end if;
  update public.reviews set status = case when p_approve then 'approved' else 'draft' end, hr_comment = nullif(trim(p_comment), ''),
         approved_at = case when p_approve then now() end, submitted_at = case when p_approve then submitted_at end
   where id = p_id;
end $$;

create or replace function public.acknowledge_review(p_id uuid, p_comment text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r public.reviews;
begin
  select * into r from public.reviews where id = p_id for update;
  if not found or r.employee_id is distinct from public.my_employee(r.company_id) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if r.status <> 'approved' then raise exception 'التقييم لم يُعتمد بعد'; end if;
  if r.ack_at is not null then raise exception 'سبق أن اطّلعت على التقييم'; end if;
  update public.reviews set ack_at = now(), employee_comment = nullif(trim(p_comment), '') where id = p_id;
end $$;

create or replace function public.close_review_cycle(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c public.review_cycles;
begin
  select * into c from public.review_cycles where id = p_id for update;
  if not found then raise exception 'الدورة غير موجودة'; end if;
  perform public.require_role(c.company_id, array['owner','admin','hr']);
  update public.review_cycles set status = 'closed' where id = p_id;
end $$;

-- ---------- recruitment ----------
create table public.job_openings (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null check (length(trim(title)) >= 2),
  department_id uuid references public.departments(id) on delete set null,
  positions int not null default 1 check (positions between 1 and 100),
  description text,
  status text not null default 'open' check (status in ('open','onhold','closed')),
  created_at timestamptz not null default now()
);
create index on public.job_openings(company_id);
create table public.candidates (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  opening_id uuid not null references public.job_openings(id) on delete cascade,
  full_name text not null check (length(trim(full_name)) >= 3),
  email text, phone text,
  national_id text check (national_id is null or national_id ~ '^[12][0-9]{9}$'),
  is_saudi boolean not null default true,
  gender text not null default 'm' check (gender in ('m','f')),
  stage text not null default 'applied' check (stage in ('applied','screening','interview','offer','hired','rejected')),
  expected_salary numeric(12,2) check (expected_salary is null or expected_salary >= 0),
  rating int check (rating is null or rating between 1 and 5),
  interview_at timestamptz,
  notes text,
  employee_id uuid references public.employees(id) on delete set null,
  created_at timestamptz not null default now()
);
create index on public.candidates(opening_id);
-- "hired" is set only by hire_candidate(), and a hired candidate is final
create or replace function public.candidate_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' and old.stage = 'hired' and (new.stage <> 'hired' or new.employee_id is distinct from old.employee_id) then
    raise exception 'المرشح عُيّن ولا يمكن تغيير مرحلته'; end if;
  if new.stage = 'hired' and coalesce(current_setting('waad.hiring', true), '') <> 'on' and (tg_op = 'INSERT' or old.stage <> 'hired') then
    raise exception 'التعيين يتم من زر «تعيين» ليُنشأ سجل الموظف'; end if;
  return new;
end $$;
create trigger candidates_guard before insert or update on public.candidates for each row execute function public.candidate_guard();

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
  insert into public.employees(company_id, emp_no, full_name, national_id, is_saudi, gender, job_title, department_id, manager_id, hire_date, probation_end, basic, housing, transport, phone, email)
  values (c.company_id, p_emp->>'emp_no', c.full_name, c.national_id, c.is_saudi, c.gender, coalesce(nullif(p_emp->>'job_title', ''), o.title),
          coalesce(nullif(p_emp->>'department_id', '')::uuid, o.department_id), nullif(p_emp->>'manager_id', '')::uuid,
          coalesce(nullif(p_emp->>'hire_date', '')::date, current_date), nullif(p_emp->>'probation_end', '')::date,
          (p_emp->>'basic')::numeric, coalesce(nullif(p_emp->>'housing', '')::numeric, 0), coalesce(nullif(p_emp->>'transport', '')::numeric, 0), c.phone, c.email)
  returning id into eid;
  perform set_config('waad.hiring', 'on', true);
  update public.candidates set stage = 'hired', employee_id = eid where id = p_cand;
  perform set_config('waad.hiring', 'off', true);
  select count(*) into hired from public.candidates where opening_id = o.id and stage = 'hired';
  if hired >= o.positions then update public.job_openings set status = 'closed' where id = o.id; end if;
  return eid;
end $$;

-- ---------- training ----------
create table public.trainings (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null check (length(trim(title)) >= 3),
  provider text, location text, notes text,
  start_date date not null, end_date date,
  hours numeric(6,1) check (hours is null or hours >= 0),
  cost numeric(12,2) not null default 0 check (cost >= 0),
  created_at timestamptz not null default now(),
  check (end_date is null or end_date >= start_date)
);
create index on public.trainings(company_id);
create table public.training_attendees (
  training_id uuid not null references public.trainings(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  status text not null default 'enrolled' check (status in ('enrolled','completed','no_show')),
  certificate_no text, cert_expiry date,
  primary key (training_id, employee_id)
);
create index on public.training_attendees(employee_id);

-- ---------- bulk import of employees ----------
-- p_rows: [{"_row": 2, "emp_no": "...", "full_name": "...", "department": "name", "manager_emp_no": "...", ...}]
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
    insert into public.employees(company_id, emp_no, full_name, national_id, is_saudi, gender, job_title, department_id, hire_date, probation_end, basic, housing, transport, iban, phone, email)
    values (p_company, v, trim(r->>'full_name'), nullif(r->>'national_id', ''), coalesce((r->>'is_saudi')::boolean, true), coalesce(r->>'gender', 'm'),
            nullif(trim(r->>'job_title'), ''), dep, d, nullif(r->>'probation_end', '')::date,
            (r->>'basic')::numeric, coalesce(nullif(r->>'housing', '')::numeric, 0), coalesce(nullif(r->>'transport', '')::numeric, 0),
            nullif(r->>'iban', ''), nullif(trim(r->>'phone'), ''), nullif(trim(r->>'email'), ''));
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

-- ---------- audit, RLS, grants ----------
create trigger audit_reviews after insert or update or delete on public.reviews for each row execute function public.audit_trigger();
create trigger audit_candidates after insert or update or delete on public.candidates for each row execute function public.audit_trigger();
create trigger audit_trainings after insert or update or delete on public.trainings for each row execute function public.audit_trigger();

alter table public.review_cycles enable row level security;
alter table public.reviews enable row level security;
alter table public.job_openings enable row level security;
alter table public.candidates enable row level security;
alter table public.trainings enable row level security;
alter table public.training_attendees enable row level security;

create policy rc_read on public.review_cycles for select using (public.is_member(company_id));
create policy rv_read on public.reviews for select using (
  public.has_role(company_id, array['owner','admin','hr'])
  or (reviewer_id is not null and reviewer_id = public.my_employee(company_id))
  or (employee_id = public.my_employee(company_id) and status = 'approved'));

create policy jo_all on public.job_openings for all using (public.has_role(company_id, array['owner','admin','hr']))
  with check (public.has_role(company_id, array['owner','admin','hr'])
    and (department_id is null or exists(select 1 from public.departments d where d.id = department_id and d.company_id = job_openings.company_id)));
create policy cand_all on public.candidates for all using (public.has_role(company_id, array['owner','admin','hr']))
  with check (public.has_role(company_id, array['owner','admin','hr'])
    and exists(select 1 from public.job_openings o where o.id = opening_id and o.company_id = candidates.company_id));

-- definer helpers keep the two training policies from referencing each other (RLS recursion)
create or replace function public.attends_training(p_training uuid, p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.training_attendees where training_id = p_training and employee_id = public.my_employee(p_company))
$$;
create or replace function public.training_company(p_training uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select company_id from public.trainings where id = p_training
$$;
create policy tr_read on public.trainings for select using (public.has_role(company_id, array['owner','admin','hr']) or public.attends_training(id, company_id));
create policy tr_write on public.trainings for all using (public.has_role(company_id, array['owner','admin','hr'])) with check (public.has_role(company_id, array['owner','admin','hr']));
create policy ta_read on public.training_attendees for select using (public.has_role(company_id, array['owner','admin','hr']) or employee_id = public.my_employee(company_id));
create policy ta_write on public.training_attendees for all using (public.has_role(company_id, array['owner','admin','hr']))
  with check (public.has_role(company_id, array['owner','admin','hr'])
    and public.training_company(training_id) = training_attendees.company_id
    and exists(select 1 from public.employees e where e.id = employee_id and e.company_id = training_attendees.company_id));

revoke all on public.review_cycles, public.reviews, public.job_openings, public.candidates, public.trainings, public.training_attendees from anon;
grant select on public.review_cycles, public.reviews to authenticated;
revoke insert, update, delete on public.review_cycles, public.reviews from authenticated;
grant select, insert, update, delete on public.job_openings, public.candidates, public.trainings, public.training_attendees to authenticated;

revoke all on function public.start_review_cycle(uuid, text, date, date), public.save_review(uuid, jsonb, text, text, text, boolean),
  public.decide_review(uuid, boolean, text), public.acknowledge_review(uuid, text), public.close_review_cycle(uuid),
  public.hire_candidate(uuid, jsonb), public.import_employees(uuid, jsonb), public.candidate_guard(),
  public.attends_training(uuid, uuid), public.training_company(uuid) from public, anon, authenticated;
grant execute on function public.attends_training(uuid, uuid), public.training_company(uuid) to authenticated;
grant execute on function public.start_review_cycle(uuid, text, date, date), public.save_review(uuid, jsonb, text, text, text, boolean),
  public.decide_review(uuid, boolean, text), public.acknowledge_review(uuid, text), public.close_review_cycle(uuid),
  public.hire_candidate(uuid, jsonb), public.import_employees(uuid, jsonb) to authenticated;
notify pgrst, 'reload schema';
