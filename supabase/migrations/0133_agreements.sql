-- Contracts and agreements «العقود والاتفاقيات»: service, maintenance, lease, supply, subscription and consulting
-- contracts with customers (sales) or suppliers (purchases): term, value, billing, renewal notice, the signed copy,
-- an alert before the end, and a recurring invoice made from a sales contract.
create table if not exists public.agreements (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text,
  direction text not null check (direction in ('sale','purchase')),
  party_id uuid not null references public.parties(id),
  kind text not null default 'service' check (kind in ('service','maintenance','lease','supply','subscription','consulting','other')),
  title text not null check (length(btrim(title)) between 2 and 150),
  start_date date not null,
  end_date date,
  value numeric(14,2) not null default 0 check (value >= 0),
  billing text not null default 'none' check (billing in ('none','once','monthly','quarterly','semiannual','annual')),
  auto_renew boolean not null default false,
  notice_days int not null default 30 check (notice_days between 0 and 365),
  status text not null default 'active' check (status in ('draft','active','ended','terminated')),
  owner_id uuid references public.employees(id) on delete set null,
  recurring_id uuid references public.recurring_invoices(id) on delete set null,
  notes text check (notes is null or length(notes) <= 2000),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date is null or end_date >= start_date)
);
create index if not exists agreements_co on public.agreements(company_id, status, end_date);
create index if not exists agreements_party on public.agreements(party_id);
create index if not exists agreements_owner on public.agreements(owner_id);
create index if not exists agreements_rec on public.agreements(recurring_id);

create table if not exists public.agreement_files (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  agreement_id uuid not null references public.agreements(id) on delete cascade,
  file_name text not null check (length(file_name) between 1 and 200),
  mime text not null check (mime in ('application/pdf','image/jpeg','image/png','image/webp','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document')),
  size int not null check (size between 1 and 3145728),
  data text not null, uploaded_by uuid default auth.uid(), created_at timestamptz not null default now()
);
create index if not exists agreement_files_ag on public.agreement_files(agreement_id);
create index if not exists agreement_files_co on public.agreement_files(company_id);



create or replace function public.agreements_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from public.parties p where p.id = new.party_id and p.company_id = new.company_id
                and p.kind = case when new.direction = 'sale' then 'customer' else 'supplier' end) then
    raise exception 'اختر % من منشأتك', case when new.direction = 'sale' then 'عميلا' else 'موردا' end; end if;
  if new.owner_id is not null and not exists(select 1 from public.employees e where e.id = new.owner_id and e.company_id = new.company_id) then
    raise exception 'الموظف المسؤول غير موجود'; end if;
  if new.recurring_id is not null and not exists(select 1 from public.recurring_invoices r where r.id = new.recurring_id and r.company_id = new.company_id and r.party_id = new.party_id) then
    raise exception 'الفاتورة المتكررة لا تخص هذا العميل'; end if;
  if tg_op = 'INSERT' then new.no := public.next_doc_no(new.company_id, 'AG');
  else new.no := old.no; new.company_id := old.company_id; new.created_by := old.created_by; new.created_at := old.created_at; new.updated_at := now(); end if;
  return new;
end $$;
drop trigger if exists agreements_guard on public.agreements;
create trigger agreements_guard before insert or update on public.agreements for each row execute function public.agreements_guard();

alter table public.agreements enable row level security;
alter table public.agreement_files enable row level security;
revoke all on public.agreements, public.agreement_files from anon;
grant select, insert, update, delete on public.agreements, public.agreement_files to authenticated;
drop policy if exists agreements_all on public.agreements;
create policy agreements_all on public.agreements for all
  using (public.fin_can(company_id, case when direction = 'sale' then 'sales' else 'purch' end))
  with check (public.fin_can(company_id, case when direction = 'sale' then 'sales' else 'purch' end));
drop policy if exists agreement_files_all on public.agreement_files;
create policy agreement_files_all on public.agreement_files for all
  using (exists(select 1 from public.agreements a where a.id = agreement_id and a.company_id = agreement_files.company_id and public.fin_can(a.company_id, case when a.direction = 'sale' then 'sales' else 'purch' end)))
  with check (exists(select 1 from public.agreements a where a.id = agreement_id and a.company_id = agreement_files.company_id and public.fin_can(a.company_id, case when a.direction = 'sale' then 'sales' else 'purch' end)));
drop trigger if exists files_quota on public.agreement_files;
create trigger files_quota before insert on public.agreement_files for each row execute function public.files_quota_guard();
drop trigger if exists audit_agreements on public.agreements;
create trigger audit_agreements after insert or update or delete on public.agreements for each row execute function public.audit_trigger();

-- the company's file space counts the contract copies too
create or replace function public.company_files_bytes(p_company uuid) returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(sum(size), 0)::bigint from (select company_id, size from public.request_attachments union all select company_id, size from public.travel_files union all select company_id, size from public.candidate_files union all select company_id, size from public.contract_files union all select company_id, size from public.document_files union all select company_id, size from public.custody_files union all select company_id, size from public.company_document_files union all select company_id, size from public.vehicle_files union all select company_id, size from public.purchase_bill_files union all select company_id, size from public.supplier_inbox_files union all select company_id, size from public.agreement_files) f where f.company_id = p_company
$$;


-- contracts that end within their notice period (or already ended while still marked active)
create or replace function public.agreements_due(p_company uuid) returns table(id uuid, no text, title text, direction text, end_date date, days int)
language sql stable security definer set search_path = public as $$
  select a.id, a.no, a.title, a.direction, a.end_date, (a.end_date - public.riyadh_today())::int
    from public.agreements a
   where a.company_id = p_company and a.status = 'active' and a.end_date is not null
     and public.fin_can(p_company, case when a.direction = 'sale' then 'sales' else 'purch' end)
     and a.end_date <= public.riyadh_today() + greatest(a.notice_days, 7)
   order by a.end_date
$$;
revoke all on function public.agreements_guard() from public, anon, authenticated;
revoke all on function public.company_files_bytes(uuid) from public, anon, authenticated;
revoke all on function public.agreements_due(uuid) from public, anon;
grant execute on function public.agreements_due(uuid) to authenticated;
notify pgrst, 'reload schema';
