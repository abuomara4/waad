-- Waad ERP — 0084 «اختبر فهمك»: short questions at the end of the user guide (employee / direct manager). The database
-- marks each attempt against the answer key below (the browser never gets it), and the result is visible to the employee
-- and to the company's owner, admins and HR. Questions themselves: app/src/guide_lib.js (GUIDE_QUIZ), same ids and order.

create table if not exists public.guide_quiz_results (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null,
  employee_id uuid references public.employees(id) on delete set null,
  section text not null check (section in ('emp','mgr')),
  score int not null check (score >= 0),
  total int not null check (total > 0),
  passed boolean not null,
  answers jsonb not null default '{}',
  wrong text[] not null default '{}',
  taken_at timestamptz not null default now()
);
create index if not exists guide_quiz_results_co on public.guide_quiz_results(company_id, taken_at desc);
alter table public.guide_quiz_results enable row level security;
revoke all on public.guide_quiz_results from anon, authenticated;
grant select on public.guide_quiz_results to authenticated;
drop policy if exists gq_read on public.guide_quiz_results;
create policy gq_read on public.guide_quiz_results for select
  using (public.is_member(company_id) and (user_id = auth.uid() or public.has_role(company_id, array['owner','admin','hr'])));

-- the answer key: index of the right option (0-based) for each question id
create or replace function public.guide_quiz_key(p_section text) returns jsonb
language sql immutable set search_path = public as $$
  select case p_section
    when 'emp' then '{"e1":1,"e2":0,"e3":2,"e4":0,"e5":1,"e6":2,"e7":0}'::jsonb
    when 'mgr' then '{"m1":1,"m2":0,"m3":2,"m4":0}'::jsonb end
$$;
revoke all on function public.guide_quiz_key(text) from public, anon, authenticated;

-- submit an attempt: {"e1": 1, "e2": 0, ...} → marked here, stored, and the result returned (score, total, passed, wrong ids)
create or replace function public.guide_quiz_submit(p_company uuid, p_section text, p_answers jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare k jsonb := public.guide_quiz_key(p_section); q text; n int := 0; tot int := 0; bad text[] := '{}'; ok boolean;
begin
  if not public.is_member(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if k is null then raise exception 'اختبار غير معروف'; end if;
  if jsonb_typeof(p_answers) is distinct from 'object' then raise exception 'أجب عن الأسئلة'; end if;
  for q in select jsonb_object_keys(k) loop
    tot := tot + 1;
    if (p_answers->>q) is not null and (p_answers->>q) = (k->>q) then n := n + 1; else bad := bad || q; end if;
  end loop;
  ok := n * 100 >= tot * 80;   -- pass mark: 80%
  insert into public.guide_quiz_results(company_id, user_id, employee_id, section, score, total, passed, answers, wrong)
  values (p_company, auth.uid(), public.my_employee(p_company), p_section, n, tot, ok, p_answers, bad);
  return jsonb_build_object('score', n, 'total', tot, 'passed', ok, 'wrong', to_jsonb(bad));
end $$;
revoke all on function public.guide_quiz_submit(uuid, text, jsonb) from public, anon;
grant execute on function public.guide_quiz_submit(uuid, text, jsonb) to authenticated;
