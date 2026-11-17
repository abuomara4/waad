-- 0107 — «التهيئة والترحيب»: a checklist for every new employee (owner's decision, 2026-11-17).
-- Some steps are read from the employee's own data in the app (contract, account, IBAN, documents, manager, medical
-- insurance, policies); the others are ticked by HR here: GOSI registration, contract documented in Qiwa, the welcome
-- session, work tools, plus the company's own steps (companies.onboarding_items).

alter table public.companies add column if not exists onboarding_items text[] not null default '{}';

create table if not exists public.onboarding_marks (
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  item text not null check (length(item) between 1 and 120),
  done_by uuid default auth.uid(),
  done_at timestamptz not null default now(),
  primary key (employee_id, item)
);
alter table public.onboarding_marks enable row level security;
drop policy if exists onb_hr on public.onboarding_marks;
create policy onb_hr on public.onboarding_marks for all
  using (public.has_role(company_id, array['owner','admin','hr']))
  with check (public.has_role(company_id, array['owner','admin','hr'])
              and exists(select 1 from public.employees e where e.id = employee_id and e.company_id = onboarding_marks.company_id));

create or replace function public.onboarding_items_set(p_company uuid, p_items text[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  update public.companies set onboarding_items = array(select distinct left(btrim(x), 120) from unnest(coalesce(p_items, '{}')) x where btrim(x) <> '' limit 30)
   where id = p_company;
end $$;
revoke all on function public.onboarding_items_set(uuid, text[]) from public, anon;
grant execute on function public.onboarding_items_set(uuid, text[]) to authenticated;
