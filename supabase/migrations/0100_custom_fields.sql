-- Waad ERP — 0100 custom fields: a company adds its own fields to the employee file, the customer/supplier card or the item
-- (text, number, date or a list), in Arabic and English. Values live in a `custom` jsonb on the record itself, so they are
-- protected by the record's own permissions. The owner and admins define the fields.

alter table public.employees add column if not exists custom jsonb not null default '{}';
alter table public.parties add column if not exists custom jsonb not null default '{}';
alter table public.items add column if not exists custom jsonb not null default '{}';

create table if not exists public.custom_fields (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  entity text not null check (entity in ('employee','party','item')),
  label text not null check (length(trim(label)) between 2 and 60),
  label_en text check (label_en is null or length(label_en) <= 60),
  kind text not null default 'text' check (kind in ('text','number','date','select')),
  options text[] not null default '{}',
  sort int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  check (kind <> 'select' or cardinality(options) between 1 and 40)
);
create index if not exists custom_fields_co on public.custom_fields(company_id, entity, sort);
alter table public.custom_fields enable row level security;
revoke all on public.custom_fields from anon;
grant select, insert, update, delete on public.custom_fields to authenticated;
drop policy if exists cf_read on public.custom_fields;
create policy cf_read on public.custom_fields for select using (public.is_member(company_id));
drop policy if exists cf_write on public.custom_fields;
create policy cf_write on public.custom_fields for all using (public.has_role(company_id, array['owner','admin']))
  with check (public.has_role(company_id, array['owner','admin']));
