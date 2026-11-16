-- Waad ERP — 0095 custody: attachments (handover form, photo, invoice…) and the company's own list of item names
-- (the built-in list — desktop computer, laptop, phone, car… in Arabic and English — lives in the app; a company adds
-- its own names here and they show in the same list with their English name).

create table if not exists public.custody_files (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  custody_id uuid not null references public.custody_items(id) on delete cascade,
  file_name text not null check (length(file_name) between 1 and 200),
  mime text not null check (mime in ('application/pdf','image/jpeg','image/png','image/webp',
    'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document')),
  size int not null check (size between 1 and 3145728),
  data text not null,
  uploaded_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists custody_files_item on public.custody_files(custody_id);
alter table public.custody_files enable row level security;
drop policy if exists custody_files_all on public.custody_files;
create policy custody_files_all on public.custody_files for all using (public.has_role(company_id, array['owner','admin','hr']))
  with check (public.has_role(company_id, array['owner','admin','hr'])
              and exists(select 1 from public.custody_items c where c.id = custody_id and c.company_id = custody_files.company_id));
revoke all on public.custody_files from anon;
grant select, insert, delete on public.custody_files to authenticated;

create table if not exists public.custody_names (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null check (length(trim(name)) between 2 and 80),
  name_en text check (name_en is null or length(name_en) <= 80),
  created_at timestamptz not null default now(),
  unique (company_id, name)
);
alter table public.custody_names enable row level security;
drop policy if exists custody_names_read on public.custody_names;
create policy custody_names_read on public.custody_names for select using (public.is_member(company_id));
drop policy if exists custody_names_write on public.custody_names;
create policy custody_names_write on public.custody_names for all using (public.has_role(company_id, array['owner','admin','hr']))
  with check (public.has_role(company_id, array['owner','admin','hr']));
revoke all on public.custody_names from anon;
grant select, insert, update, delete on public.custody_names to authenticated;
