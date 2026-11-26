-- Waad ERP — 0154 second free batch, HR (owner's request, 2026-11-26):
--  8. staff directory: name, department, job and extension for everyone in the company; each person chooses whether his
--     mobile and e-mail show (off by default);
--  9. confidential grievances: to HR or to the owner only; may be anonymous (the handler never sees the name); a thread
--     of messages both ways; separate from the appeal against a penalty (0017);
-- 10. exit interview: the leaving employee answers once; HR sees each answer and the totals;
-- 11. interview scorecards: each interviewer rates a candidate on criteria; candidates of an opening compared side by side;
-- 12. job descriptions library: purpose, duties, qualifications per job / grade, linked to openings, printed with the offer.

-- ---------------- 8. directory ----------------
alter table public.employees add column if not exists ext text check (ext is null or ext ~ '^[0-9]{1,8}$'),
  add column if not exists dir_phone boolean not null default false,
  add column if not exists dir_email boolean not null default false;

create or replace function public.staff_directory(p_company uuid) returns table(id uuid, name text, name_en text, job text, job_en text, department text,
  branch text, manager text, ext text, phone text, email text, mine boolean)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company);
begin
  if not public.is_member(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query
  select e.id, e.full_name, e.full_name_en, e.job_title, e.job_title_en, d.name, (select b.name from public.branches b where b.id = e.branch_id),
         (select m.full_name from public.employees m where m.id = e.manager_id), e.ext,
         case when e.dir_phone or e.id = me then e.phone end, case when e.dir_email or e.id = me then e.email end, coalesce(e.id = me, false)
    from public.employees e left join public.departments d on d.id = e.department_id
   where e.company_id = p_company and (e.end_date is null or e.end_date >= current_date) and public.emp_branch_ok(p_company, e.id)
   order by d.name nulls last, e.full_name;
end $$;
create or replace function public.directory_me_set(p_company uuid, p_ext text, p_phone boolean, p_email boolean) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company);
begin
  if me is null then raise exception 'حسابك غير مربوط بسجل موظف' using errcode = '42501'; end if;
  if nullif(btrim(coalesce(p_ext, '')), '') is not null and btrim(p_ext) !~ '^[0-9]{1,8}$' then raise exception 'رقم التحويلة أرقام فقط (حتى 8)'; end if;
  update public.employees set ext = nullif(btrim(coalesce(p_ext, '')), ''), dir_phone = coalesce(p_phone, false), dir_email = coalesce(p_email, false) where id = me;
end $$;

-- ---------------- 9. grievances ----------------
create table if not exists public.grievances (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  no text not null,
  category text not null check (category in ('harassment','discrimination','safety','conduct','pay','workload','policy','other')),
  subject text not null check (length(btrim(subject)) between 3 and 200),
  body text not null check (length(btrim(body)) between 10 and 5000),
  anonymous boolean not null default false,
  to_whom text not null default 'hr' check (to_whom in ('hr','owner')),
  status text not null default 'open' check (status in ('open','review','resolved','closed')),
  resolution text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), closed_at timestamptz,
  unique (company_id, no)
);
create index if not exists grievances_company on public.grievances(company_id, status);
create index if not exists grievances_emp on public.grievances(employee_id);
create table if not exists public.grievance_messages (
  id uuid primary key default gen_random_uuid(),
  grievance_id uuid not null references public.grievances(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  side text not null check (side in ('reporter','handler')),
  body text not null check (length(btrim(body)) between 1 and 5000),
  by_user uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists grievance_messages_g on public.grievance_messages(grievance_id);
create index if not exists grievance_messages_c on public.grievance_messages(company_id);
-- no direct reads: the functions below keep an anonymous reporter's name away from the handler
alter table public.grievances enable row level security;
alter table public.grievance_messages enable row level security;
revoke all on public.grievances, public.grievance_messages from anon, authenticated;

create or replace function public.grievance_handler(p_company uuid, p_to text) returns boolean
language sql stable security definer set search_path = public as $$
  select case when p_to = 'owner' then public.has_role(p_company, array['owner']) else public.has_role(p_company, array['owner','admin','hr']) end
$$;
create or replace function public.grievance_submit(p_company uuid, p_category text, p_subject text, p_body text, p_anonymous boolean, p_to text) returns text
language plpgsql security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company); v text;
begin
  if me is null then raise exception 'حسابك غير مربوط بسجل موظف' using errcode = '42501'; end if;
  if (select count(*) from public.grievances where employee_id = me and created_at > now() - interval '1 day') >= 5 then raise exception 'حد 5 بلاغات في اليوم'; end if;
  v := public.next_doc_no(p_company, 'GR');
  insert into public.grievances(company_id, employee_id, no, category, subject, body, anonymous, to_whom)
  values (p_company, me, v, p_category, btrim(p_subject), btrim(p_body), coalesce(p_anonymous, false), coalesce(nullif(p_to, ''), 'hr'));
  return v;
end $$;
-- the reporter's own
create or replace function public.grievance_mine(p_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company);
begin
  if me is null then raise exception 'حسابك غير مربوط بسجل موظف' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'no', g.no, 'category', g.category, 'subject', g.subject, 'body', g.body, 'anonymous', g.anonymous, 'to', g.to_whom,
      'status', g.status, 'resolution', g.resolution, 'created_at', g.created_at,
      'messages', coalesce((select jsonb_agg(jsonb_build_object('side', m.side, 'body', m.body, 'at', m.created_at) order by m.created_at) from public.grievance_messages m where m.grievance_id = g.id), '[]'))
      order by g.created_at desc) from public.grievances g where g.employee_id = me), '[]');
end $$;
-- the handler's inbox (HR, or the owner for those sent to him); an anonymous reporter shows no name
create or replace function public.grievance_inbox(p_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_role(p_company, array['owner','admin','hr']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', g.id, 'no', g.no, 'category', g.category, 'subject', g.subject, 'body', g.body, 'anonymous', g.anonymous, 'to', g.to_whom,
      'status', g.status, 'resolution', g.resolution, 'created_at', g.created_at, 'updated_at', g.updated_at,
      'reporter', case when g.anonymous then null else (select jsonb_build_object('name', e.full_name, 'no', e.emp_no, 'job', e.job_title) from public.employees e where e.id = g.employee_id) end,
      'messages', coalesce((select jsonb_agg(jsonb_build_object('side', m.side, 'body', m.body, 'at', m.created_at) order by m.created_at) from public.grievance_messages m where m.grievance_id = g.id), '[]'))
      order by (g.status in ('open','review')) desc, g.created_at desc)
    from public.grievances g where g.company_id = p_company and public.grievance_handler(p_company, g.to_whom)), '[]');
end $$;
create or replace function public.grievance_reply(p_id uuid, p_body text) returns void
language plpgsql security definer set search_path = public as $$
declare g public.grievances; side text;
begin
  select * into g from public.grievances where id = p_id;
  if not found then raise exception 'البلاغ غير موجود'; end if;
  if g.employee_id = public.my_employee(g.company_id) then side := 'reporter';
  elsif public.grievance_handler(g.company_id, g.to_whom) then side := 'handler';
  else raise exception 'غير مصرح' using errcode = '42501'; end if;
  if g.status = 'closed' then raise exception 'البلاغ مغلق'; end if;
  insert into public.grievance_messages(grievance_id, company_id, side, body) values (p_id, g.company_id, side, btrim(p_body));
  update public.grievances set updated_at = now(), status = case when side = 'handler' and status = 'open' then 'review' else status end where id = p_id;
end $$;
create or replace function public.grievance_status(p_id uuid, p_status text, p_resolution text) returns void
language plpgsql security definer set search_path = public as $$
declare g public.grievances;
begin
  select * into g from public.grievances where id = p_id;
  if not found or not public.grievance_handler(g.company_id, g.to_whom) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_status not in ('open','review','resolved','closed') then raise exception 'حالة غير معروفة'; end if;
  if p_status in ('resolved','closed') and coalesce(length(btrim(p_resolution)), 0) < 3 and g.resolution is null then raise exception 'اكتب ما تم بشأن البلاغ'; end if;
  update public.grievances set status = p_status, resolution = coalesce(nullif(btrim(p_resolution), ''), resolution), updated_at = now(),
    closed_at = case when p_status in ('resolved','closed') then now() end where id = p_id;
end $$;

-- ---------------- 10. exit interviews ----------------
create table if not exists public.exit_interviews (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null unique references public.employees(id) on delete cascade,
  reasons text[] not null default '{}',
  ratings jsonb not null default '{}',              -- {manager, pay, growth, workload, culture, training}: 1–5
  would_return boolean,
  recommend int check (recommend is null or recommend between 0 and 10),
  best text, improve text, comments text,
  submitted_at timestamptz not null default now()
);
create index if not exists exit_interviews_company on public.exit_interviews(company_id);
alter table public.exit_interviews enable row level security;
revoke all on public.exit_interviews from anon, authenticated;
grant select on public.exit_interviews to authenticated;
drop policy if exists exit_read on public.exit_interviews;
create policy exit_read on public.exit_interviews for select using (public.has_role(company_id, array['owner','admin','hr']) and public.emp_branch_ok(company_id, employee_id));
-- may the signed-in employee answer now: his service ends (end date, or a resignation waiting or accepted) and he has not answered
create or replace function public.exit_interview_me(p_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company); e public.employees;
begin
  if me is null then raise exception 'حسابك غير مربوط بسجل موظف' using errcode = '42501'; end if;
  select * into e from public.employees where id = me;
  return jsonb_build_object('due', (e.end_date is not null or exists(select 1 from public.requests where employee_id = me and kind = 'resign' and status = 'pending'))
           and not exists(select 1 from public.exit_interviews where employee_id = me), 'done', exists(select 1 from public.exit_interviews where employee_id = me), 'end_date', e.end_date);
end $$;
create or replace function public.exit_interview_submit(p_company uuid, p_a jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company); k text; r text;
begin
  if me is null then raise exception 'حسابك غير مربوط بسجل موظف' using errcode = '42501'; end if;
  if not coalesce((public.exit_interview_me(p_company)->>'due')::boolean, false) then raise exception 'مقابلة نهاية الخدمة للموظف المغادر، مرة واحدة'; end if;
  for r in select jsonb_array_elements_text(coalesce(p_a->'reasons', '[]')) loop
    if r not in ('pay','growth','manager','workload','relocation','study','offer','family','health','culture','other') then raise exception 'سبب غير معروف'; end if;
  end loop;
  for k in select jsonb_object_keys(coalesce(p_a->'ratings', '{}')) loop
    if k not in ('manager','pay','growth','workload','culture','training') or coalesce((p_a->'ratings'->>k)::int, 0) not between 1 and 5 then raise exception 'التقييم من 1 إلى 5'; end if;
  end loop;
  insert into public.exit_interviews(company_id, employee_id, reasons, ratings, would_return, recommend, best, improve, comments)
  values (p_company, me, array(select jsonb_array_elements_text(coalesce(p_a->'reasons', '[]'))), coalesce(p_a->'ratings', '{}'),
          (p_a->>'would_return')::boolean, nullif(p_a->>'recommend', '')::int, nullif(btrim(p_a->>'best'), ''), nullif(btrim(p_a->>'improve'), ''), nullif(btrim(p_a->>'comments'), ''));
end $$;
-- totals for HR over a period
create or replace function public.exit_results(p_company uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  return (with x as (select * from public.exit_interviews i where i.company_id = p_company and i.submitted_at::date between p_from and p_to and public.emp_branch_ok(p_company, i.employee_id))
    select jsonb_build_object('n', (select count(*) from x),
      'reasons', coalesce((select jsonb_object_agg(r, c) from (select r, count(*) c from x, unnest(x.reasons) r group by r) t), '{}'),
      'ratings', coalesce((select jsonb_object_agg(k, a) from (select k, round(avg((x.ratings->>k)::numeric), 1) a from x, jsonb_object_keys(x.ratings) k group by k) t), '{}'),
      'would_return', (select round(100.0 * count(*) filter (where would_return) / nullif(count(*) filter (where would_return is not null), 0)) from x),
      'enps', (select round(100.0 * (count(*) filter (where recommend >= 9) - count(*) filter (where recommend <= 6)) / nullif(count(*) filter (where recommend is not null), 0)) from x)));
end $$;

-- ---------------- 11. interview scorecards ----------------
create table if not exists public.candidate_scores (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  candidate_id uuid not null references public.candidates(id) on delete cascade,
  by_user uuid not null default auth.uid(),
  by_name text,
  ratings jsonb not null,                            -- {technical, experience, communication, problem, culture, motivation}: 1–5
  score numeric(3,1) not null,
  recommendation text not null check (recommendation in ('hire','maybe','no')),
  notes text,
  created_at timestamptz not null default now(),
  unique (candidate_id, by_user)
);
create index if not exists candidate_scores_company on public.candidate_scores(company_id);
alter table public.candidate_scores enable row level security;
revoke all on public.candidate_scores from anon, authenticated;
grant select on public.candidate_scores to authenticated;
drop policy if exists cscore_read on public.candidate_scores;
create policy cscore_read on public.candidate_scores for select using (public.has_role(company_id, array['owner','admin','hr']) or public.fin_can(company_id, 'hr_recruit'));
create or replace function public.candidate_score_save(p_candidate uuid, p_ratings jsonb, p_rec text, p_notes text) returns void
language plpgsql security definer set search_path = public as $$
declare c public.candidates; k text; s numeric := 0; n int := 0;
begin
  select * into c from public.candidates where id = p_candidate;
  if not found then raise exception 'المرشح غير موجود'; end if;
  if not (public.has_role(c.company_id, array['owner','admin','hr']) or public.fin_can(c.company_id, 'hr_recruit')) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_rec not in ('hire','maybe','no') then raise exception 'اختر التوصية'; end if;
  for k in select jsonb_object_keys(coalesce(p_ratings, '{}')) loop
    if k not in ('technical','experience','communication','problem','culture','motivation') or coalesce((p_ratings->>k)::int, 0) not between 1 and 5 then raise exception 'التقييم من 1 إلى 5'; end if;
    s := s + (p_ratings->>k)::int; n := n + 1;
  end loop;
  if n = 0 then raise exception 'قيّم البنود من 1 إلى 5'; end if;
  insert into public.candidate_scores(company_id, candidate_id, by_name, ratings, score, recommendation, notes)
  values (c.company_id, p_candidate, coalesce((select full_name from public.employees where id = public.my_employee(c.company_id)), (select email from auth.users where id = auth.uid())),
          p_ratings, round(s / n, 1), p_rec, nullif(btrim(p_notes), ''))
  on conflict (candidate_id, by_user) do update set ratings = excluded.ratings, score = excluded.score, recommendation = excluded.recommendation, notes = excluded.notes, by_name = excluded.by_name, created_at = now();
end $$;

-- ---------------- 12. job descriptions ----------------
create table if not exists public.job_descriptions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null check (length(btrim(title)) between 2 and 120),
  title_en text,
  department_id uuid references public.departments(id) on delete set null,
  grade_id uuid references public.job_grades(id) on delete set null,
  reports_to text, purpose text, duties text, qualifications text, experience text, skills text,
  updated_at timestamptz not null default now(),
  unique (company_id, title)
);
create index if not exists job_descriptions_dept on public.job_descriptions(department_id);
create index if not exists job_descriptions_grade on public.job_descriptions(grade_id);
alter table public.job_openings add column if not exists jd_id uuid references public.job_descriptions(id) on delete set null;
create index if not exists job_openings_jd on public.job_openings(jd_id);
alter table public.job_descriptions enable row level security;
revoke all on public.job_descriptions from anon;
grant select, insert, update, delete on public.job_descriptions to authenticated;
drop policy if exists jd_read on public.job_descriptions;
create policy jd_read on public.job_descriptions for select using (public.is_member(company_id));
drop policy if exists jd_write on public.job_descriptions;
create policy jd_write on public.job_descriptions for insert with check (public.has_role(company_id, array['owner','admin','hr']) or public.fin_can(company_id, 'hr_recruit'));
drop policy if exists jd_update on public.job_descriptions;
create policy jd_update on public.job_descriptions for update using (public.has_role(company_id, array['owner','admin','hr']) or public.fin_can(company_id, 'hr_recruit'))
  with check (public.has_role(company_id, array['owner','admin','hr']) or public.fin_can(company_id, 'hr_recruit'));
drop policy if exists jd_delete on public.job_descriptions;
create policy jd_delete on public.job_descriptions for delete using (public.has_role(company_id, array['owner','admin','hr']) or public.fin_can(company_id, 'hr_recruit'));
-- a job opening's description must be the company's own
create or replace function public.job_openings_jd_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.jd_id is not null and not exists(select 1 from public.job_descriptions j where j.id = new.jd_id and j.company_id = new.company_id) then raise exception 'الوصف الوظيفي ليس من المنشأة'; end if;
  return new;
end $$;
drop trigger if exists job_openings_jd_guard on public.job_openings;
create trigger job_openings_jd_guard before insert or update of jd_id on public.job_openings for each row execute function public.job_openings_jd_guard();

revoke all on function public.grievance_handler(uuid, text), public.job_openings_jd_guard() from public, anon, authenticated;
revoke all on function public.staff_directory(uuid), public.directory_me_set(uuid, text, boolean, boolean), public.grievance_submit(uuid, text, text, text, boolean, text),
  public.grievance_mine(uuid), public.grievance_inbox(uuid), public.grievance_reply(uuid, text), public.grievance_status(uuid, text, text),
  public.exit_interview_me(uuid), public.exit_interview_submit(uuid, jsonb), public.exit_results(uuid, date, date),
  public.candidate_score_save(uuid, jsonb, text, text) from public, anon;
grant execute on function public.staff_directory(uuid), public.directory_me_set(uuid, text, boolean, boolean), public.grievance_submit(uuid, text, text, text, boolean, text),
  public.grievance_mine(uuid), public.grievance_inbox(uuid), public.grievance_reply(uuid, text), public.grievance_status(uuid, text, text),
  public.exit_interview_me(uuid), public.exit_interview_submit(uuid, jsonb), public.exit_results(uuid, date, date),
  public.candidate_score_save(uuid, jsonb, text, text) to authenticated;
notify pgrst, 'reload schema';
