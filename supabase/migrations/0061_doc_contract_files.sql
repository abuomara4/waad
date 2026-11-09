-- Waad ERP — 0061 attachments for employee documents and contracts (#9/#10). Additive; safe to re-run.

-- ---------- #9/#10 attachments for employee documents and contracts ----------
-- Optional file (PDF/image/Word) attached to a document record or a contract. Mirrors candidate_files.
create table if not exists public.document_files (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  document_id uuid not null references public.employee_documents(id) on delete cascade,
  file_name text not null check (length(file_name) between 1 and 200),
  mime text not null check (mime in ('application/pdf','image/jpeg','image/png','image/webp',
    'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document')),
  size int not null check (size between 1 and 3145728),
  data text not null,
  uploaded_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists document_files_doc on public.document_files(document_id);
alter table public.document_files enable row level security;
drop policy if exists document_files_all on public.document_files;
create policy document_files_all on public.document_files for all using (public.has_role(company_id, array['owner','admin','hr']))
  with check (public.has_role(company_id, array['owner','admin','hr'])
              and exists(select 1 from public.employee_documents d where d.id = document_id and d.company_id = document_files.company_id));
revoke all on public.document_files from anon;
grant select, insert, delete on public.document_files to authenticated;

create table if not exists public.contract_files (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  contract_id uuid not null references public.contracts(id) on delete cascade,
  file_name text not null check (length(file_name) between 1 and 200),
  mime text not null check (mime in ('application/pdf','image/jpeg','image/png','image/webp',
    'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document')),
  size int not null check (size between 1 and 3145728),
  data text not null,
  uploaded_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists contract_files_con on public.contract_files(contract_id);
alter table public.contract_files enable row level security;
drop policy if exists contract_files_all on public.contract_files;
create policy contract_files_all on public.contract_files for all using (public.has_role(company_id, array['owner','admin','hr']))
  with check (public.has_role(company_id, array['owner','admin','hr'])
              and exists(select 1 from public.contracts c where c.id = contract_id and c.company_id = contract_files.company_id));
revoke all on public.contract_files from anon;
grant select, insert, delete on public.contract_files to authenticated;
