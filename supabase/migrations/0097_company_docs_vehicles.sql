-- Waad ERP — 0097 the company's own documents (commercial registration, municipal licence, Chamber of Commerce, civil
-- defence, lease, insurance, Zakat/GOSI certificates…) and its vehicles (registration «استمارة», insurance, periodic
-- inspection «الفحص الدوري», driver), each with expiry alerts and attachments. Owner, admins, HR and finance manage them.

create table if not exists public.company_documents (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  doc_type text not null check (doc_type in ('cr','municipal','chamber','civil_defense','lease','insurance','zakat','gosi','saudization','vat','other')),
  title text check (title is null or length(title) <= 120),
  title_en text check (title_en is null or length(title_en) <= 120),
  doc_no text check (doc_no is null or length(doc_no) <= 60),
  issue_date date,
  expiry_date date,
  notes text check (notes is null or length(notes) <= 500),
  created_at timestamptz not null default now(),
  check (doc_type <> 'other' or length(trim(coalesce(title, ''))) >= 2),
  check (issue_date is null or expiry_date is null or expiry_date >= issue_date)
);
create index if not exists company_documents_co on public.company_documents(company_id, expiry_date);

create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  plate text not null check (length(trim(plate)) between 2 and 20),
  make text check (make is null or length(make) <= 60),
  model text check (model is null or length(model) <= 60),
  year int check (year is null or year between 1950 and 2100),
  color text check (color is null or length(color) <= 30),
  driver_id uuid references public.employees(id) on delete set null,
  istimara_expiry date,
  insurance_expiry date,
  inspection_expiry date,
  notes text check (notes is null or length(notes) <= 500),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (company_id, plate)
);

create table if not exists public.company_document_files (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  company_document_id uuid not null references public.company_documents(id) on delete cascade,
  file_name text not null check (length(file_name) between 1 and 200),
  mime text not null check (mime in ('application/pdf','image/jpeg','image/png','image/webp','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document')),
  size int not null check (size between 1 and 3145728),
  data text not null, uploaded_by uuid default auth.uid(), created_at timestamptz not null default now()
);
create table if not exists public.vehicle_files (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  file_name text not null check (length(file_name) between 1 and 200),
  mime text not null check (mime in ('application/pdf','image/jpeg','image/png','image/webp','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document')),
  size int not null check (size between 1 and 3145728),
  data text not null, uploaded_by uuid default auth.uid(), created_at timestamptz not null default now()
);

do $$ declare t text; begin
  foreach t in array array['company_documents','vehicles','company_document_files','vehicle_files'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_all', t);
    execute format('create policy %I on public.%I for all using (public.has_role(company_id, array[''owner'',''admin'',''hr'',''finance''])) with check (public.has_role(company_id, array[''owner'',''admin'',''hr'',''finance'']))', t || '_all', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;
-- a file belongs to a record of the same company
create or replace function public.co_file_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_table_name = 'company_document_files' and not exists(select 1 from public.company_documents d where d.id = new.company_document_id and d.company_id = new.company_id) then raise exception 'المستند غير موجود'; end if;
  if tg_table_name = 'vehicle_files' and not exists(select 1 from public.vehicles v where v.id = new.vehicle_id and v.company_id = new.company_id) then raise exception 'السيارة غير موجودة'; end if;
  return new;
end $$;
revoke all on function public.co_file_guard() from public, anon, authenticated;
drop trigger if exists company_document_files_guard on public.company_document_files;
create trigger company_document_files_guard before insert on public.company_document_files for each row execute function public.co_file_guard();
drop trigger if exists vehicle_files_guard on public.vehicle_files;
create trigger vehicle_files_guard before insert on public.vehicle_files for each row execute function public.co_file_guard();
-- a driver from the same company
create or replace function public.vehicle_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.driver_id is not null and not exists(select 1 from public.employees e where e.id = new.driver_id and e.company_id = new.company_id) then raise exception 'السائق ليس من موظفي المنشأة'; end if;
  return new;
end $$;
revoke all on function public.vehicle_guard() from public, anon, authenticated;
drop trigger if exists vehicles_guard on public.vehicles;
create trigger vehicles_guard before insert or update on public.vehicles for each row execute function public.vehicle_guard();
