-- Waad ERP — 0076 forms library: ready-made forms for every department (in the app) plus the company's own templates
-- (stored here), filled from the employee / customer / supplier record and printed on the company letterhead.
-- Every printed form gets a yearly serial number and is kept in a log (who issued what, for whom, when).

create table if not exists public.form_templates (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  dept text not null check (dept in ('hr','finance','sales','purch','stock','proj')),
  subject text not null default 'none' check (subject in ('employee','customer','supplier','none')),
  title_ar text not null check (length(trim(title_ar)) between 2 and 120),
  title_en text check (title_en is null or length(title_en) <= 120),
  body_ar text not null check (length(trim(body_ar)) between 2 and 8000),
  body_en text check (body_en is null or length(body_en) <= 8000),
  fields jsonb not null default '[]' check (jsonb_typeof(fields) = 'array'),
  sigs jsonb not null default '[]' check (jsonb_typeof(sigs) = 'array'),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists form_templates_co on public.form_templates(company_id);
alter table public.form_templates enable row level security;
-- who uses forms: the company's managers (HR side and finance side)
create or replace function public.forms_can(p_company uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.has_role(p_company, array['owner','admin','hr','finance','accountant','storekeeper','manager'])
$$;
drop policy if exists form_templates_read on public.form_templates;
create policy form_templates_read on public.form_templates for select using (public.forms_can(company_id));
drop policy if exists form_templates_write on public.form_templates;
create policy form_templates_write on public.form_templates for all using (public.has_role(company_id, array['owner','admin','hr','finance']))
  with check (public.has_role(company_id, array['owner','admin','hr','finance']));
revoke all on public.form_templates from anon;
grant select, insert, update, delete on public.form_templates to authenticated;

create table if not exists public.form_issues (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  template text not null check (length(template) <= 120),
  title text not null check (length(title) <= 160),
  subject_name text check (subject_name is null or length(subject_name) <= 200),
  lang text not null default 'ar' check (lang in ('ar','en')),
  issued_by uuid default auth.uid(),
  issued_at timestamptz not null default now(),
  unique (company_id, no)
);
create index if not exists form_issues_co on public.form_issues(company_id, issued_at desc);
alter table public.form_issues enable row level security;
drop policy if exists form_issues_read on public.form_issues;
create policy form_issues_read on public.form_issues for select using (public.forms_can(company_id));
revoke all on public.form_issues from anon, authenticated;
grant select on public.form_issues to authenticated;

-- number and log one printed form: F-<year>-<0001…>, counted per company and year
create or replace function public.form_issue(p_company uuid, p_template text, p_title text, p_subject text, p_lang text) returns text
language plpgsql security definer set search_path = public as $$
declare y text := to_char((now() at time zone 'Asia/Riyadh')::date, 'YYYY'); n int; v text;
begin
  if not public.forms_can(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtext('form_issue:' || p_company::text));
  select count(*) + 1 into n from public.form_issues where company_id = p_company and no like 'F-' || y || '-%';
  v := 'F-' || y || '-' || lpad(n::text, 4, '0');
  insert into public.form_issues(company_id, no, template, title, subject_name, lang)
  values (p_company, v, left(coalesce(p_template, 'custom'), 120), left(coalesce(nullif(trim(p_title), ''), '—'), 160), left(nullif(trim(p_subject), ''), 200), case when p_lang = 'en' then 'en' else 'ar' end);
  return v;
end $$;
revoke all on function public.forms_can(uuid), public.form_issue(uuid, text, text, text, text) from public, anon;
grant execute on function public.forms_can(uuid), public.form_issue(uuid, text, text, text, text) to authenticated;
