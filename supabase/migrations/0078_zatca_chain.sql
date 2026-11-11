-- Waad ERP — 0078 ZATCA Phase 2 (Fatoora), step 1: the database side (docs/ZATCA_PHASE2.md).
-- Once a company is linked to Fatoora, every sales invoice, sales credit note and debit note it issues joins one unbroken
-- chain: a counter (ICV) with no gaps, and — filled in when the document is signed by the server — the hash of the previous
-- document (PIH). The signing, the XML and the calls to ZATCA come in the next steps (a server function); here: the queue,
-- the counter, the settings, the private-key store (never readable from the app), no voiding once a document is in the
-- chain (a credit note corrects it instead), and debit notes.

-- per company: linked or not, which ZATCA environment, the counter, the public certificate
create table if not exists public.zatca_settings (
  company_id uuid primary key references public.companies(id) on delete cascade,
  enabled boolean not null default false,
  env text not null default 'simulation' check (env in ('simulation','production')),
  icv bigint not null default 0 check (icv >= 0),
  egs_serial text,
  csid_cert text,
  onboarded_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.zatca_settings enable row level security;
drop policy if exists zatca_settings_read on public.zatca_settings;
create policy zatca_settings_read on public.zatca_settings for select using (public.fin_can(company_id, 'sales'));
revoke all on public.zatca_settings from anon, authenticated;
grant select on public.zatca_settings to authenticated;

-- the private key and the CSID secret: only the server (service role) reads them — no policy, no grant
create table if not exists public.zatca_secrets (
  company_id uuid primary key references public.companies(id) on delete cascade,
  private_key text,
  csid_secret text,
  updated_at timestamptz not null default now()
);
alter table public.zatca_secrets enable row level security;
revoke all on public.zatca_secrets from anon, authenticated;

-- debit notes are sales invoices of their own type, pointing at the invoice they add to (so payments, statements and
-- aging treat them like any receivable)
alter table public.sales_invoices add column if not exists doc_type text not null default 'invoice' check (doc_type in ('invoice','debit'));
alter table public.sales_invoices add column if not exists ref_id uuid references public.sales_invoices(id);
alter table public.sales_invoices add column if not exists reason text check (reason is null or length(reason) <= 500);

-- the chain: one row per document, in ICV order
create table if not exists public.zatca_docs (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  icv bigint not null check (icv > 0),
  kind text not null check (kind in ('invoice','credit','debit')),
  doc_id uuid not null unique,
  inv_type text not null check (inv_type in ('standard','simplified')),
  pih text, hash text, xml text, qr text,
  status text not null default 'pending' check (status in ('pending','reported','cleared','warning','rejected','error')),
  resp jsonb,
  attempts int not null default 0,
  next_try timestamptz not null default now(),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  unique (company_id, icv)
);
create index if not exists zatca_docs_todo on public.zatca_docs(company_id, icv) where status in ('pending','error');
alter table public.zatca_docs enable row level security;
drop policy if exists zatca_docs_read on public.zatca_docs;
create policy zatca_docs_read on public.zatca_docs for select using (public.fin_can(company_id, 'sales'));
revoke all on public.zatca_docs from anon, authenticated;
grant select on public.zatca_docs to authenticated;
-- the chain is never cut: no deletes, and the number / document / previous hash / hash of a row never change
-- (only a pending, unsigned row may turn from invoice into debit note — post_debit_note below)
create or replace function public.zatca_docs_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'سجل زاتكا لا يُحذف' using errcode = '42501'; end if;
  if (new.company_id, new.icv, new.doc_id, new.inv_type) is distinct from (old.company_id, old.icv, old.doc_id, old.inv_type)
     or (new.kind is distinct from old.kind and not (old.kind = 'invoice' and new.kind = 'debit' and old.hash is null))
     or (old.pih is not null and new.pih is distinct from old.pih) or (old.hash is not null and new.hash is distinct from old.hash) then
    raise exception 'سجل زاتكا لا يتغيّر' using errcode = '42501';
  end if;
  return new;
end $$;

drop trigger if exists zatca_docs_guard on public.zatca_docs;
create trigger zatca_docs_guard before update or delete on public.zatca_docs for each row execute function public.zatca_docs_guard();

-- a new document of a linked company takes the next number in the chain (the settings row is locked, so two invoices
-- posted at the same moment never share or skip a number). Standard (B2B) = the buyer has a VAT number; else simplified.
create or replace function public.zatca_enqueue() returns trigger
language plpgsql security definer set search_path = public as $$
declare s public.zatca_settings; k text; pty uuid; t text; n bigint;
begin
  if tg_table_name = 'sales_invoices' then
    if new.is_opening then return new; end if;
    k := 'invoice'; pty := new.party_id;
  else
    if new.kind <> 'sales' then return new; end if;
    k := 'credit'; pty := new.party_id;
  end if;
  select * into s from public.zatca_settings where company_id = new.company_id and enabled for update;
  if not found then return new; end if;
  if k = 'credit' then   -- a credit note follows the type of the invoice it corrects
    select inv_type into t from public.zatca_docs where doc_id = new.doc_id;
  end if;
  if t is null then
    select case when nullif(trim(vat_no), '') is not null then 'standard' else 'simplified' end into t from public.parties where id = pty;
  end if;
  n := s.icv + 1;
  update public.zatca_settings set icv = n, updated_at = now() where company_id = new.company_id;
  insert into public.zatca_docs(company_id, icv, kind, doc_id, inv_type) values (new.company_id, n, k, new.id, coalesce(t, 'simplified'));
  return new;
end $$;
drop trigger if exists sales_invoices_zatca on public.sales_invoices;
create trigger sales_invoices_zatca after insert on public.sales_invoices for each row execute function public.zatca_enqueue();
drop trigger if exists credit_notes_zatca on public.credit_notes;
create trigger credit_notes_zatca after insert on public.credit_notes for each row execute function public.zatca_enqueue();

-- once in the chain, an invoice is not voided: it is corrected by a credit note (Phase 2 forbids cancelling)
create or replace function public.zatca_void_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'void' and old.status <> 'void' and exists(select 1 from public.zatca_docs where doc_id = new.id) then
    raise exception 'الفاتورة مرسلة إلى زاتكا ولا تُلغى — صحّحها بإشعار دائن' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists sales_invoices_zatca_void on public.sales_invoices;
create trigger sales_invoices_zatca_void before update of status on public.sales_invoices for each row execute function public.zatca_void_guard();

-- the previous-invoice hash for document number p_icv: the hash of p_icv-1, or ZATCA's starting value for the first one
-- (base64 of the SHA-256 hex digest of "0"). Null while the previous document is not signed yet — the server signs in order.
create or replace function public.zatca_prev_hash(p_company uuid, p_icv bigint) returns text
language sql stable security definer set search_path = public as $$
  select case when p_icv <= 1 then 'NWZlY2ViNjZmZmM4NmYzOGQ5NTI3ODZjNmQ2OTZjNzljMmRiYzIzOWRkNGU5MWI0NjcyOWQ3M2EyN2ZiNTdlOQ=='
              else (select hash from public.zatca_docs where company_id = p_company and icv = p_icv - 1) end
$$;

-- a debit note: an extra amount on an invoice that was already issued (price difference, extra service…), with a reason.
-- p_doc = {"ref": <invoice id>, "date": "YYYY-MM-DD", "reason": "...", "lines": [{"item": <id>, "qty": n, "price": n}]}
create or replace function public.post_debit_note(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare r public.sales_invoices; iid uuid; rsn text := trim(coalesce(p_doc->>'reason', '')); d date := coalesce(nullif(p_doc->>'date', '')::date, current_date);
begin
  perform public.require_fin(p_company, 'sales');
  select * into r from public.sales_invoices where id = nullif(p_doc->>'ref', '')::uuid and company_id = p_company;
  if not found then raise exception 'الفاتورة الأصلية غير موجودة'; end if;
  if r.status <> 'posted' or r.is_opening or r.doc_type <> 'invoice' then raise exception 'الإشعار المدين يكون على فاتورة مبيعات قائمة'; end if;
  if length(rsn) < 3 then raise exception 'اكتب سبب الإشعار'; end if;
  if d < r.date then raise exception 'التاريخ قبل تاريخ الفاتورة'; end if;
  iid := public.post_sales_invoice_sn(p_company, jsonb_build_object('party', r.party_id, 'date', d, 'due', d, 'lines', coalesce(p_doc->'lines', '[]'),
    'warehouse', p_doc->>'warehouse', 'note', 'إشعار مدين على الفاتورة ' || r.no || ' — ' || rsn));
  update public.sales_invoices set doc_type = 'debit', ref_id = r.id, reason = rsn where id = iid;
  update public.zatca_docs set kind = 'debit' where doc_id = iid and status = 'pending' and hash is null;
  return iid;
end $$;

revoke all on function public.zatca_enqueue(), public.zatca_void_guard(), public.zatca_docs_guard(), public.zatca_prev_hash(uuid, bigint) from public, anon, authenticated;
revoke all on function public.post_debit_note(uuid, jsonb) from public, anon;
grant execute on function public.post_debit_note(uuid, jsonb) to authenticated;
