-- 0108 — owner's decision 2026-11-17: what the big HR systems have, in Waad.
--  1. company announcements to all employees (or one department), read receipts, sent to devices (push_due);
--  2. employee surveys, incl. eNPS, onboarding and exit; anonymous by default (results only from 3 answers);
--  3. 360 feedback: self, peers and direct reports, next to the manager's review; peers stay anonymous;
--  4. a public careers page per company (private link) where candidates apply with their CV;
--  5. interview link / place on candidates (the invitation message is composed in the app);
--  6. expense policies per category: per-claim and monthly limits (optionally blocking) + flags for approvers;
--  7. workforce plan: a department asks for positions with their cost; HR then finance (or the owner) approve.

-- ================= 1. announcements =================
create table if not exists public.company_announcements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null check (length(btrim(title)) between 2 and 150),
  body text not null check (length(body) between 1 and 4000),
  department_id uuid references public.departments(id) on delete set null,
  pinned boolean not null default false,
  expires_on date,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists company_announcements_co on public.company_announcements(company_id, created_at desc);
alter table public.company_announcements enable row level security;
drop policy if exists ca_read on public.company_announcements;
create policy ca_read on public.company_announcements for select using (
  public.has_role(company_id, array['owner','admin','hr'])
  or (public.is_member(company_id) and (department_id is null
      or exists(select 1 from public.employees e where e.id = public.my_employee(company_id) and e.department_id = company_announcements.department_id))));
drop policy if exists ca_write on public.company_announcements;
create policy ca_write on public.company_announcements for all using (public.has_role(company_id, array['owner','admin','hr']))
  with check (public.has_role(company_id, array['owner','admin','hr']));

create table if not exists public.announcement_reads (
  announcement_id uuid not null references public.company_announcements(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (announcement_id, user_id)
);
alter table public.announcement_reads enable row level security;
drop policy if exists ar_own on public.announcement_reads;
create policy ar_own on public.announcement_reads for select using (user_id = auth.uid() or public.has_role(company_id, array['owner','admin','hr']));
drop policy if exists ar_ins on public.announcement_reads;
create policy ar_ins on public.announcement_reads for insert with check (user_id = auth.uid() and public.is_member(company_id));

-- ================= 2. surveys =================
create table if not exists public.surveys (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  title text not null check (length(btrim(title)) between 2 and 150),
  kind text not null default 'custom' check (kind in ('enps','custom','onboarding','exit')),
  questions jsonb not null check (jsonb_typeof(questions) = 'array' and jsonb_array_length(questions) between 1 and 30),
  anonymous boolean not null default true,
  status text not null default 'open' check (status in ('open','closed')),
  closes_on date,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
alter table public.surveys enable row level security;
drop policy if exists sv_read on public.surveys;
create policy sv_read on public.surveys for select using (public.is_member(company_id));
drop policy if exists sv_write on public.surveys;
create policy sv_write on public.surveys for all using (public.has_role(company_id, array['owner','admin','hr']))
  with check (public.has_role(company_id, array['owner','admin','hr']));

create table if not exists public.survey_takers (survey_id uuid not null references public.surveys(id) on delete cascade, user_id uuid not null references auth.users(id) on delete cascade,
  at timestamptz not null default now(), primary key (survey_id, user_id));
create table if not exists public.survey_responses (
  id uuid primary key default gen_random_uuid(),
  survey_id uuid not null references public.surveys(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  respondent uuid references auth.users(id) on delete set null,      -- null when the survey is anonymous
  answers jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.survey_takers enable row level security;
alter table public.survey_responses enable row level security;
drop policy if exists st_own on public.survey_takers;
create policy st_own on public.survey_takers for select using (user_id = auth.uid());
revoke all on public.survey_responses from anon, authenticated;   -- read only through survey_results()

create or replace function public.survey_submit(p_survey uuid, p_answers jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare s public.surveys;
begin
  select * into s from public.surveys where id = p_survey;
  if s.id is null or not public.is_member(s.company_id) then raise exception 'الاستبيان غير موجود' using errcode = '42501'; end if;
  if s.status <> 'open' or (s.closes_on is not null and s.closes_on < (now() at time zone 'Asia/Riyadh')::date) then raise exception 'الاستبيان مغلق'; end if;
  if jsonb_typeof(p_answers) <> 'array' or jsonb_array_length(p_answers) <> jsonb_array_length(s.questions) or length(p_answers::text) > 20000 then raise exception 'الإجابات غير مكتملة'; end if;
  insert into public.survey_takers(survey_id, user_id) values (p_survey, auth.uid());   -- primary key: once per person
  insert into public.survey_responses(survey_id, company_id, respondent, answers)
  values (p_survey, s.company_id, case when s.anonymous then null else auth.uid() end, p_answers);
exception when unique_violation then raise exception 'سبق أن أجبت على هذا الاستبيان';
end $$;

-- answers for HR; an anonymous survey shows nothing until it has 3 answers (nobody can be singled out)
create or replace function public.survey_results(p_survey uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.surveys; n int;
begin
  select * into s from public.surveys where id = p_survey;
  if s.id is null or not public.has_role(s.company_id, array['owner','admin','hr']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  select count(*) into n from public.survey_responses where survey_id = p_survey;
  if s.anonymous and n < 3 then return jsonb_build_object('n', n, 'hidden', true, 'answers', '[]'::jsonb); end if;
  return jsonb_build_object('n', n, 'hidden', false, 'answers', coalesce((select jsonb_agg(r.answers order by r.created_at) from public.survey_responses r where r.survey_id = p_survey), '[]'::jsonb),
    'who', case when s.anonymous then '[]'::jsonb else coalesce((select jsonb_agg(e.full_name order by r.created_at) from public.survey_responses r
      left join public.members m on m.user_id = r.respondent and m.company_id = s.company_id left join public.employees e on e.id = m.employee_id where r.survey_id = p_survey), '[]'::jsonb) end);
end $$;

-- ================= 3. 360 feedback =================
create table if not exists public.review_feedback (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  cycle_id uuid not null references public.review_cycles(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,   -- who is reviewed
  rater_id uuid not null references public.employees(id) on delete cascade,      -- who answers
  kind text not null check (kind in ('self','peer','report')),
  scores jsonb,
  comment text check (comment is null or length(comment) <= 2000),
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (cycle_id, employee_id, rater_id)
);
alter table public.review_feedback enable row level security;
drop policy if exists rf_rater on public.review_feedback;
create policy rf_rater on public.review_feedback for select using (rater_id = public.my_employee(company_id));
-- the 5 competencies the app asks about (scores = {"c1":1-5,…})
create or replace function public.feedback_request(p_cycle uuid, p_employee uuid, p_raters uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare c public.review_cycles; e public.employees; r uuid; n int := 0;
begin
  select * into c from public.review_cycles where id = p_cycle;
  select * into e from public.employees where id = p_employee and company_id = c.company_id;
  if c.id is null or e.id is null then raise exception 'غير موجود'; end if;
  if not (public.has_role(c.company_id, array['owner','admin','hr']) or e.manager_id = public.my_employee(c.company_id)) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if c.status <> 'open' then raise exception 'الدورة مغلقة'; end if;
  insert into public.review_feedback(company_id, cycle_id, employee_id, rater_id, kind) values (c.company_id, p_cycle, p_employee, p_employee, 'self') on conflict do nothing;
  get diagnostics n = row_count;
  foreach r in array coalesce(p_raters, '{}') loop
    if r = p_employee or not exists(select 1 from public.employees x where x.id = r and x.company_id = c.company_id and (x.end_date is null or x.end_date >= current_date)) then continue; end if;
    insert into public.review_feedback(company_id, cycle_id, employee_id, rater_id, kind)
    values (c.company_id, p_cycle, p_employee, r, case when exists(select 1 from public.employees x where x.id = r and x.manager_id = p_employee) then 'report' else 'peer' end)
    on conflict do nothing;
    if found then n := n + 1; end if;
  end loop;
  return n;
end $$;
create or replace function public.feedback_submit(p_id uuid, p_scores jsonb, p_comment text) returns void
language plpgsql security definer set search_path = public as $$
declare f public.review_feedback; k text;
begin
  select * into f from public.review_feedback where id = p_id;
  if f.id is null or f.rater_id is distinct from public.my_employee(f.company_id) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if (select status from public.review_cycles where id = f.cycle_id) <> 'open' then raise exception 'الدورة مغلقة'; end if;
  foreach k in array array['c1','c2','c3','c4','c5'] loop
    if coalesce((p_scores->>k)::int, 0) not between 1 and 5 then raise exception 'قيّم كل البنود من 1 إلى 5'; end if;
  end loop;
  update public.review_feedback set scores = p_scores, comment = nullif(btrim(coalesce(p_comment, '')), ''), submitted_at = now() where id = p_id;
end $$;
-- the summary for HR and the direct manager: averages per group; peers' and reports' comments without names, shown from 2 answers
create or replace function public.feedback_summary(p_cycle uuid, p_employee uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare e public.employees;
begin
  select * into e from public.employees where id = p_employee;
  if e.id is null or not (public.has_role(e.company_id, array['owner','admin','hr']) or e.manager_id = public.my_employee(e.company_id)) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return coalesce((select jsonb_object_agg(g.kind, g.v) from (
    select f.kind, jsonb_build_object('asked', count(*), 'done', count(f.submitted_at),
      'avg', case when f.kind = 'self' or count(f.submitted_at) >= 2 then (select jsonb_object_agg(q.k, q.a) from (select k, round(avg((x.scores->>k)::numeric), 2) a
                  from public.review_feedback x cross join unnest(array['c1','c2','c3','c4','c5']) k
                  where x.cycle_id = p_cycle and x.employee_id = p_employee and x.kind = f.kind and x.submitted_at is not null group by k) q) end,
      'comments', case when f.kind = 'self' or count(f.submitted_at) >= 2 then coalesce(jsonb_agg(f.comment order by random()) filter (where f.comment is not null), '[]'::jsonb) else '[]'::jsonb end) v
    from public.review_feedback f where f.cycle_id = p_cycle and f.employee_id = p_employee group by f.kind) g), '{}'::jsonb);
end $$;

-- ================= 4. public careers page =================
alter table public.companies add column if not exists careers_token text unique check (careers_token is null or careers_token ~ '^[0-9a-f]{32}$');
alter table public.job_openings add column if not exists public boolean not null default false;
alter table public.job_openings add column if not exists requirements text check (requirements is null or length(requirements) <= 3000);
alter table public.candidates add column if not exists source text;
alter table public.candidates add column if not exists interview_link text check (interview_link is null or interview_link ~ '^https://');
alter table public.candidates add column if not exists interview_place text;

create or replace function public.careers_link_get(p_company uuid, p_new boolean default false) returns text
language plpgsql security definer set search_path = public as $$
declare t text;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  select careers_token into t from public.companies where id = p_company;
  if t is null or p_new then t := replace(gen_random_uuid()::text, '-', ''); update public.companies set careers_token = t where id = p_company; end if;
  return t;
end $$;

create or replace function public.careers_view(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.companies;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{32}$' then return null; end if;
  select * into c from public.companies where careers_token = p_token;
  if c.id is null then return null; end if;
  return jsonb_build_object('company', c.name, 'company_en', c.name_en, 'logo', c.logo, 'city', c.city,
    'jobs', coalesce((select jsonb_agg(jsonb_build_object('id', o.id, 'title', o.title, 'title_en', o.title_en, 'dept', d.name, 'positions', o.positions,
                       'description', o.description, 'requirements', o.requirements) order by o.created_at desc)
              from public.job_openings o left join public.departments d on d.id = o.department_id
             where o.company_id = c.id and o.public and o.status = 'open'), '[]'::jsonb));
end $$;

create or replace function public.careers_apply(p_token text, p_opening uuid, p_name text, p_phone text, p_email text, p_note text,
  p_file_name text default null, p_mime text default null, p_data text default null) returns void
language plpgsql security definer set search_path = public as $$
declare c public.companies; o public.job_openings; cid uuid; ph text := regexp_replace(coalesce(p_phone, ''), '[\s-]', '', 'g');
begin
  if p_token is null or p_token !~ '^[0-9a-f]{32}$' then raise exception 'الرابط غير صالح'; end if;
  select * into c from public.companies where careers_token = p_token;
  select * into o from public.job_openings where id = p_opening and company_id = c.id and public and status = 'open';
  if c.id is null or o.id is null then raise exception 'الوظيفة غير متاحة'; end if;
  if length(btrim(coalesce(p_name, ''))) < 3 or length(p_name) > 120 then raise exception 'اكتب اسمك الكامل'; end if;
  if ph !~ '^(05[0-9]{8}|\+9665[0-9]{8}|\+?[0-9]{8,15})$' then raise exception 'رقم الجوال غير صحيح'; end if;
  if p_email is not null and p_email <> '' and p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'البريد الإلكتروني غير صحيح'; end if;
  if p_data is not null and (length(p_data) > 4200000 or coalesce(p_mime, '') not in ('application/pdf', 'image/jpeg', 'image/png',
       'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document')) then raise exception 'السيرة الذاتية PDF أو Word أو صورة، حتى 3 ميجابايت'; end if;
  if exists(select 1 from public.candidates where opening_id = o.id and phone = ph) then raise exception 'سبق أن تقدّمت لهذه الوظيفة بهذا الجوال'; end if;
  if (select count(*) from public.candidates where company_id = c.id and source = 'careers' and created_at > now() - interval '1 hour') >= 60 then
    raise exception 'طلبات كثيرة الآن، حاول بعد قليل'; end if;
  insert into public.candidates(company_id, opening_id, full_name, phone, email, stage, notes, source)
  values (c.id, o.id, btrim(p_name), ph, nullif(btrim(coalesce(p_email, '')), ''), 'applied', nullif(left(btrim(coalesce(p_note, '')), 1500), ''), 'careers')
  returning id into cid;
  if p_data is not null then
    insert into public.candidate_files(company_id, candidate_id, file_name, mime, size, data)
    values (c.id, cid, left(coalesce(nullif(btrim(p_file_name), ''), 'cv'), 120), p_mime, (length(p_data) * 3 / 4)::int, p_data);
  end if;
end $$;

-- ================= 6. expense policies =================
create table if not exists public.expense_policies (
  company_id uuid not null references public.companies(id) on delete cascade,
  category text not null check (length(btrim(category)) between 2 and 60),
  per_claim numeric check (per_claim is null or per_claim > 0),
  monthly numeric check (monthly is null or monthly > 0),
  hard boolean not null default false,       -- true: a claim above the per-claim limit cannot be sent
  primary key (company_id, category)
);
alter table public.expense_policies enable row level security;
drop policy if exists ep_read on public.expense_policies;
create policy ep_read on public.expense_policies for select using (public.is_member(company_id));
drop policy if exists ep_write on public.expense_policies;
create policy ep_write on public.expense_policies for all using (public.has_role(company_id, array['owner','admin','hr','finance']))
  with check (public.has_role(company_id, array['owner','admin','hr','finance']));

create or replace function public.expense_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare p public.expense_policies;
begin
  if new.kind <> 'expense' then return new; end if;
  select * into p from public.expense_policies where company_id = new.company_id and category = coalesce(new.payload->>'cat', '');
  if p.hard and p.per_claim is not null and new.amount > p.per_claim then
    raise exception 'المبلغ أعلى من حد المطالبة لفئة «%» (% ريال)', p.category, p.per_claim; end if;
  return new;
end $$;
drop trigger if exists expense_guard on public.requests;
create trigger expense_guard before insert on public.requests for each row execute function public.expense_guard();

-- warnings shown to whoever approves the claim
create or replace function public.expense_flags(p_request uuid) returns text[]
language plpgsql stable security definer set search_path = public as $$
declare r public.requests; p public.expense_policies; out text[] := '{}'; m numeric;
begin
  select * into r from public.requests where id = p_request;
  if r.id is null or r.kind <> 'expense' or not (public.has_role(r.company_id, array['owner','admin','hr','finance'])
     or exists(select 1 from public.employees e where e.id = r.employee_id and e.manager_id = public.my_employee(r.company_id))) then return out; end if;
  select * into p from public.expense_policies where company_id = r.company_id and category = coalesce(r.payload->>'cat', '');
  if p.per_claim is not null and r.amount > p.per_claim then out := out || ('أعلى من حد المطالبة (' || p.per_claim || ')'); end if;
  if p.monthly is not null then
    select coalesce(sum(amount), 0) into m from public.requests x where x.employee_id = r.employee_id and x.kind = 'expense' and x.status in ('pending','approved')
       and coalesce(x.payload->>'cat', '') = coalesce(r.payload->>'cat', '') and date_trunc('month', x.created_at) = date_trunc('month', r.created_at);
    if m > p.monthly then out := out || ('مجموع الشهر ' || m || ' أعلى من الحد الشهري (' || p.monthly || ')'); end if;
  end if;
  if exists(select 1 from public.requests x where x.id <> r.id and x.employee_id = r.employee_id and x.kind = 'expense' and x.amount = r.amount
            and coalesce(x.payload->>'cat', '') = coalesce(r.payload->>'cat', '') and x.status <> 'rejected' and abs(extract(epoch from x.created_at - r.created_at)) < 30 * 86400) then
    out := out || 'مطالبة بنفس المبلغ والفئة خلال 30 يوما'::text; end if;
  if exists(select 1 from public.request_attachments a join public.request_attachments b on md5(a.data) = md5(b.data) and a.id <> b.id
              join public.requests rb on rb.id = b.request_id and rb.kind = 'expense' and rb.status <> 'rejected'
            where a.request_id = r.id and b.company_id = r.company_id) then
    out := out || 'نفس الإيصال مرفق في مطالبة أخرى'::text; end if;
  return out;
end $$;

-- ================= 7. workforce plan =================
create table if not exists public.headcount_plans (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  year int not null check (year between 2020 and 2100),
  department_id uuid references public.departments(id) on delete set null,
  title text not null check (length(btrim(title)) between 2 and 120),
  positions int not null default 1 check (positions between 1 and 500),
  monthly_cost numeric not null check (monthly_cost >= 0),
  start_month int check (start_month between 1 and 12),
  reason text check (reason is null or length(reason) <= 1000),
  status text not null default 'submitted' check (status in ('submitted','hr_ok','approved','rejected','hired')),
  requested_by uuid default auth.uid(),
  hr_by uuid, fin_by uuid, note text, opening_id uuid references public.job_openings(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.headcount_plans enable row level security;
drop policy if exists hp_read on public.headcount_plans;
create policy hp_read on public.headcount_plans for select using (public.has_role(company_id, array['owner','admin','hr','finance']) or requested_by = auth.uid());

create or replace function public.headcount_submit(p_company uuid, p_year int, p_dept uuid, p_title text, p_positions int, p_cost numeric, p_start int, p_reason text) returns uuid
language plpgsql security definer set search_path = public as $$
declare id_ uuid; me uuid := public.my_employee(p_company);
begin
  if not (public.has_role(p_company, array['owner','admin','hr']) or (me is not null and exists(select 1 from public.employees e where e.manager_id = me))) then
    raise exception 'طلب الوظائف لمدراء الأقسام والموارد البشرية' using errcode = '42501'; end if;
  if p_dept is not null and not exists(select 1 from public.departments d where d.id = p_dept and d.company_id = p_company) then raise exception 'القسم غير موجود'; end if;
  insert into public.headcount_plans(company_id, year, department_id, title, positions, monthly_cost, start_month, reason)
  values (p_company, p_year, p_dept, btrim(p_title), coalesce(p_positions, 1), p_cost, p_start, nullif(btrim(coalesce(p_reason, '')), '')) returning id into id_;
  return id_;
end $$;
-- HR approves first, then finance (or the owner when there is no finance user); a rejection needs a note
create or replace function public.headcount_decide(p_id uuid, p_ok boolean, p_note text) returns text
language plpgsql security definer set search_path = public as $$
declare h public.headcount_plans;
begin
  select * into h from public.headcount_plans where id = p_id;
  if h.id is null then raise exception 'غير موجود'; end if;
  if not p_ok and length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'اكتب سبب الرفض'; end if;
  if h.status = 'submitted' and public.has_role(h.company_id, array['owner','admin','hr']) then
    update public.headcount_plans set status = case when p_ok then 'hr_ok' else 'rejected' end, hr_by = auth.uid(), note = nullif(btrim(coalesce(p_note, '')), '') where id = p_id;
  elsif h.status = 'hr_ok' and (public.has_role(h.company_id, array['finance']) or (public.has_role(h.company_id, array['owner'])
        and not exists(select 1 from public.members m where m.company_id = h.company_id and (m.role = 'finance' or 'finance' = any(m.extra_roles))))) then
    update public.headcount_plans set status = case when p_ok then 'approved' else 'rejected' end, fin_by = auth.uid(), note = coalesce(nullif(btrim(coalesce(p_note, '')), ''), note) where id = p_id;
  else raise exception 'ليس دورك في اعتماد هذا الطلب' using errcode = '42501'; end if;
  return (select status from public.headcount_plans where id = p_id);
end $$;
-- an approved plan becomes a job opening in «التوظيف»
create or replace function public.headcount_open(p_id uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare h public.headcount_plans; o uuid;
begin
  select * into h from public.headcount_plans where id = p_id;
  if h.id is null or not public.has_role(h.company_id, array['owner','admin','hr']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if h.status <> 'approved' then raise exception 'الطلب لم يُعتمد بعد'; end if;
  insert into public.job_openings(company_id, title, department_id, positions, description, status)
  values (h.company_id, h.title, h.department_id, h.positions, h.reason, 'open') returning id into o;
  update public.headcount_plans set status = 'hired', opening_id = o where id = p_id;
  return o;
end $$;

-- ================= grants =================
revoke all on function public.survey_submit(uuid, jsonb), public.survey_results(uuid), public.feedback_request(uuid, uuid, uuid[]), public.feedback_submit(uuid, jsonb, text),
  public.feedback_summary(uuid, uuid), public.careers_link_get(uuid, boolean), public.expense_flags(uuid), public.headcount_submit(uuid, int, uuid, text, int, numeric, int, text),
  public.headcount_decide(uuid, boolean, text), public.headcount_open(uuid) from public, anon;
grant execute on function public.survey_submit(uuid, jsonb), public.survey_results(uuid), public.feedback_request(uuid, uuid, uuid[]), public.feedback_submit(uuid, jsonb, text),
  public.feedback_summary(uuid, uuid), public.careers_link_get(uuid, boolean), public.expense_flags(uuid), public.headcount_submit(uuid, int, uuid, text, int, numeric, int, text),
  public.headcount_decide(uuid, boolean, text), public.headcount_open(uuid) to authenticated;
revoke all on function public.expense_guard() from public, anon, authenticated;
revoke all on function public.careers_view(text), public.careers_apply(text, uuid, text, text, text, text, text, text, text) from public;
grant execute on function public.careers_view(text), public.careers_apply(text, uuid, text, text, text, text, text, text, text) to anon, authenticated;

-- devices hear about new announcements too (0106 + this)
create or replace function public.push_due() returns table(user_id uuid, key text, title text, body text, url text)
language plpgsql security definer set search_path = public, auth as $$
declare u record; since timestamptz;
begin
  for u in select s.user_id, min(s.created_at) as first_at from public.push_subscriptions s group by s.user_id loop
    since := greatest(u.first_at, now() - interval '2 days');
    perform set_config('request.jwt.claim.sub', u.user_id::text, true);
    return query
    with mine as (select m.company_id, m.employee_id from public.members m where m.user_id = u.user_id and public.member_live(m.employee_id, m.role)),
    ev as (
      select 'req:' || r.id || ':' || r.step as k, 'طلب بانتظار اعتمادك' as t,
             coalesce((select e.full_name from public.employees e where e.id = r.employee_id), '') || ' — ' || public.request_kind_ar(r.kind) as b, '#/approvals' as l
        from public.requests r join mine on mine.company_id = r.company_id
       where r.status = 'pending' and coalesce(r.step_at, r.created_at) > since and public.can_act(r, r.route[r.step + 1])
      union all
      select 'dec:' || r.id, case when r.status = 'approved' then 'اعتُمد طلبك' else 'رُفض طلبك' end, public.request_kind_ar(r.kind), '#/requests'
        from public.requests r join mine on mine.employee_id = r.employee_id
       where r.status in ('approved', 'rejected') and r.decided_at > since
      union all
      select 'sig:' || s.id, 'مستند بانتظار توقيعك', s.title, '#/sign'
        from public.signature_requests s join mine on mine.employee_id = s.employee_id
       where s.status = 'pending' and s.created_at > since
      union all
      select 'note:' || n.id, 'أشار إليك زميل في ملاحظة', left(n.body, 120), '#/home'
        from public.record_notes n join mine on mine.company_id = n.company_id
       where u.user_id = any(n.mentions) and n.created_by is distinct from u.user_id and n.created_at > since
      union all
      select 'pay:' || p.id, 'صدرت قسيمة راتبك', p.month || '/' || p.year, '#/payslips'
        from public.payroll_runs p join mine on mine.company_id = p.company_id
       where p.status <> 'draft' and p.approved_at > since and mine.employee_id is not null
         and exists(select 1 from public.payroll_lines l where l.run_id = p.id and l.employee_id = mine.employee_id)
      union all
      select 'ann:' || a.id, a.title, left(a.body, 120), '#/home'
        from public.company_announcements a join mine on mine.company_id = a.company_id
       where a.created_at > since and a.created_by is distinct from u.user_id
         and (a.department_id is null or exists(select 1 from public.employees e where e.id = mine.employee_id and e.department_id = a.department_id))
      union all
      select 'srv:' || s.id, 'استبيان جديد', s.title, '#/surveys'
        from public.surveys s join mine on mine.company_id = s.company_id
       where s.status = 'open' and s.created_at > since and s.created_by is distinct from u.user_id
      union all
      select 'fb:' || f.id, 'مطلوب رأيك في تقييم 360', coalesce((select e.full_name from public.employees e where e.id = f.employee_id), ''), '#/reviews'
        from public.review_feedback f join mine on mine.employee_id = f.rater_id
       where f.submitted_at is null and f.created_at > since)
    select u.user_id, ev.k, ev.t, ev.b, ev.l from ev
     where not exists(select 1 from public.push_sent x where x.user_id = u.user_id and x.key = ev.k);
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
revoke all on function public.push_due() from public, anon, authenticated;
