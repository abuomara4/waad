-- Waad ERP — 0098 notes on records with @mentions: a short note on an invoice, a bill, a customer/supplier, an employee
-- file, an opportunity or a project; mentioning a colleague puts it in his alerts. A note is read by whoever may open the
-- record (and by its author and the people mentioned), and only its author deletes it.

create table if not exists public.record_notes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  entity text not null check (entity in ('employee','sales','purchase','party','project','crm')),
  ref_id uuid not null,
  body text not null check (length(trim(body)) between 1 and 2000),
  mentions uuid[] not null default '{}',
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists record_notes_ref on public.record_notes(company_id, entity, ref_id, created_at desc);
create index if not exists record_notes_mentions on public.record_notes using gin (mentions);

-- may this person open records of this kind?
create or replace function public.note_can(p_company uuid, p_entity text) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_member(p_company) and case p_entity
    when 'employee' then public.has_role(p_company, array['owner','admin','hr'])
    when 'sales' then public.fin_can(p_company, 'sales')
    when 'purchase' then public.fin_can(p_company, 'purch')
    when 'party' then public.fin_can(p_company, 'sales') or public.fin_can(p_company, 'purch')
    when 'crm' then public.fin_can(p_company, 'sales') or public.fin_can(p_company, 'mkt')
    when 'project' then public.proj_can(p_company)
    else false end
$$;
revoke all on function public.note_can(uuid, text) from public, anon;
grant execute on function public.note_can(uuid, text) to authenticated;

alter table public.record_notes enable row level security;
revoke all on public.record_notes from anon, authenticated;
grant select, insert, delete on public.record_notes to authenticated;
drop policy if exists notes_read on public.record_notes;
create policy notes_read on public.record_notes for select
  using (public.is_member(company_id) and (created_by = auth.uid() or auth.uid() = any(mentions) or public.note_can(company_id, entity)));
drop policy if exists notes_add on public.record_notes;
create policy notes_add on public.record_notes for insert
  with check (created_by = auth.uid() and public.note_can(company_id, entity)
              and not exists(select 1 from unnest(mentions) u where not exists(select 1 from public.members m where m.company_id = record_notes.company_id and m.user_id = u)));
drop policy if exists notes_del on public.record_notes;
create policy notes_del on public.record_notes for delete using (created_by = auth.uid());

-- names to show next to a note and to pick a colleague to mention (members of the company only)
create or replace function public.member_names(p_company uuid) returns table(user_id uuid, name text)
language sql stable security definer set search_path = public as $$
  select m.user_id, coalesce(e.full_name, split_part(u.email, '@', 1))
    from public.members m left join public.employees e on e.id = m.employee_id left join auth.users u on u.id = m.user_id
   where m.company_id = p_company and public.is_member(p_company) and public.member_live(m.employee_id, m.role)
   order by 2
$$;
revoke all on function public.member_names(uuid) from public, anon;
grant execute on function public.member_names(uuid) to authenticated;
