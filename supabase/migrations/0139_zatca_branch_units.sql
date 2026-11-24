-- Branches part 4: an e-invoicing unit (EGS) per branch. ZATCA gives every e-invoicing solution unit its own certificate
-- (CSID), its own invoice counter (ICV) and its own hash chain (PIH). Until now a company had one unit; now each branch may
-- be linked to Fatoora as a unit of its own (zatca_units + server-only zatca_unit_secrets). A sales invoice of a branch that
-- has a linked unit joins that branch's chain; every other document joins the company's unit as before. A credit note
-- follows the chain of the invoice it corrects. The seller's commercial registration on a branch document is the branch's
-- sub-registration when it has one. One branch's chain waiting (a network failure, a document that cannot be built) no
-- longer holds the other branches.

create table if not exists public.zatca_units (
  branch_id uuid primary key references public.branches(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  enabled boolean not null default false,
  env text not null default 'simulation' check (env in ('sandbox','simulation','production')),
  icv bigint not null default 0 check (icv >= 0),
  egs_serial text, csid_cert text, onboarded_at timestamptz, last_error text,
  updated_at timestamptz not null default now()
);
create index if not exists zatca_units_company on public.zatca_units(company_id);
alter table public.zatca_units enable row level security;
drop policy if exists zatca_units_read on public.zatca_units;
create policy zatca_units_read on public.zatca_units for select using (public.fin_can(company_id, 'sales'));
revoke all on public.zatca_units from anon, authenticated;
grant select on public.zatca_units to authenticated;

-- the branch unit's private key and CSID secret: server only (no policy, no grant, never exported)
create table if not exists public.zatca_unit_secrets (
  branch_id uuid primary key references public.branches(id) on delete cascade,
  private_key text, csid_token text, csid_secret text,
  updated_at timestamptz not null default now()
);
alter table public.zatca_unit_secrets enable row level security;
revoke all on public.zatca_unit_secrets from anon, authenticated;

-- which chain a document is in: null = the company's unit, else the branch whose unit issued it
alter table public.zatca_docs add column if not exists unit uuid references public.branches(id);
alter table public.zatca_docs drop constraint if exists zatca_docs_company_id_icv_key;
create unique index if not exists zatca_docs_chain on public.zatca_docs(company_id, coalesce(unit, '00000000-0000-0000-0000-000000000000'::uuid), icv);
create index if not exists zatca_docs_unit on public.zatca_docs(unit) where unit is not null;

create or replace function public.zatca_docs_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' and public.purging() then return old; end if;
  if tg_op = 'DELETE' then raise exception 'سجل زاتكا لا يُحذف' using errcode = '42501'; end if;
  if (new.company_id, new.unit, new.icv, new.doc_id, new.inv_type) is distinct from (old.company_id, old.unit, old.icv, old.doc_id, old.inv_type)
     or (new.kind is distinct from old.kind and not (old.kind = 'invoice' and new.kind = 'debit' and old.hash is null))
     or (old.pih is not null and new.pih is distinct from old.pih) or (old.hash is not null and new.hash is distinct from old.hash) then
    raise exception 'سجل زاتكا لا يتغيّر' using errcode = '42501';
  end if;
  return new;
end $$;

-- a new document takes the next number of its chain: its branch's unit when that unit is linked, else the company's.
-- The counter row is updated (so locked): two documents posted at the same moment never share or skip a number.
create or replace function public.zatca_enqueue() returns trigger
language plpgsql security definer set search_path = public as $$
declare k text; pty uuid; t text; n bigint; br uuid; u uuid; inchain boolean := false;
begin
  if tg_table_name = 'sales_invoices' then
    if new.is_opening then return new; end if;
    k := 'invoice'; pty := new.party_id; br := new.branch_id;
  else
    if new.kind <> 'sales' then return new; end if;
    k := 'credit'; pty := new.party_id;
    -- a credit note follows the type and the chain of the invoice it corrects
    select z.inv_type, z.unit, true into t, br, inchain from public.zatca_docs z where z.doc_id = new.doc_id;
    if not coalesce(inchain, false) then select s.branch_id into br from public.sales_invoices s where s.id = new.doc_id; end if;
  end if;
  if br is not null then
    update public.zatca_units set icv = icv + 1, updated_at = now() where branch_id = br and company_id = new.company_id and enabled returning icv into n;
    if n is not null then u := br; end if;
  end if;
  if n is null then
    update public.zatca_settings set icv = icv + 1, updated_at = now() where company_id = new.company_id and enabled returning icv into n;
    if n is null then return new; end if;
  end if;
  if t is null then
    select case when nullif(trim(vat_no), '') is not null then 'standard' else 'simplified' end into t from public.parties where id = pty;
  end if;
  insert into public.zatca_docs(company_id, unit, icv, kind, doc_id, inv_type) values (new.company_id, u, n, k, new.id, coalesce(t, 'simplified'));
  return new;
end $$;

-- the previous-invoice hash inside one chain (ZATCA's starting value for the first document of a unit)
create or replace function public.zatca_unit_prev_hash(p_company uuid, p_unit uuid, p_icv bigint) returns text
language sql stable security definer set search_path = public as $$
  select case when p_icv <= 1 then 'NWZlY2ViNjZmZmM4NmYzOGQ5NTI3ODZjNmQ2OTZjNzljMmRiYzIzOWRkNGU5MWI0NjcyOWQ3M2EyN2ZiNTdlOQ=='
              else (select hash from public.zatca_docs where company_id = p_company and unit is not distinct from p_unit and icv = p_icv - 1) end
$$;
create or replace function public.zatca_prev_hash(p_company uuid, p_icv bigint) returns text
language sql stable security definer set search_path = public as $$ select public.zatca_unit_prev_hash(p_company, null, p_icv) $$;

-- the next document to send: the oldest waiting one of a linked chain, when nothing older of the same chain waits.
-- A chain that waits (lease, retry time) holds only itself; the other branches' chains go on.
create or replace function public.zatca_claim(p_company uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.zatca_docs;
begin
  select z.* into d from public.zatca_docs z
   where z.company_id = p_company and z.status in ('pending','error') and z.next_try <= now() and coalesce(z.lease_until, '-infinity') <= now()
     and not exists(select 1 from public.zatca_docs y where y.company_id = p_company and y.unit is not distinct from z.unit and y.icv < z.icv and y.status in ('pending','error'))
     and case when z.unit is null then exists(select 1 from public.zatca_settings s where s.company_id = p_company and s.enabled)
              else exists(select 1 from public.zatca_units x where x.branch_id = z.unit and x.enabled) end
   order by z.next_try, z.icv limit 1 for update of z;
  if not found then return null; end if;
  update public.zatca_docs set lease_until = now() + interval '2 minutes', attempts = attempts + 1 where id = d.id;
  return jsonb_build_object('id', d.id, 'doc_id', d.doc_id, 'icv', d.icv, 'unit', d.unit, 'kind', d.kind, 'inv_type', d.inv_type, 'hash', d.hash, 'xml', d.xml,
    'pih', coalesce(d.pih, public.zatca_unit_prev_hash(p_company, d.unit, d.icv)), 'attempts', d.attempts + 1);
end $$;

create or replace function public.zatca_doc_data(p_doc uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare z public.zatca_docs; c public.companies; p public.parties; no text; d date; t timestamptz; ref text; rsn text; lines jsonb;
begin
  select * into z from public.zatca_docs where doc_id = p_doc;
  if not found then return null; end if;
  select * into c from public.companies where id = z.company_id;
  if z.kind = 'credit' then
    select n.no, n.date, n.created_at, n.reason, (select s.no from public.sales_invoices s where s.id = n.doc_id), n.party_id into no, d, t, rsn, ref, p.id
      from public.credit_notes n where n.id = p_doc;
    select coalesce(jsonb_agg(jsonb_build_object('name', coalesce(i.name, 'بند'), 'qty', l.qty, 'price', l.unit_price, 'rate', l.vat_rate,
      'exemptCode', i.vat_exempt_code, 'exemptReason', i.vat_exempt_reason) order by l.id), '[]') into lines
      from public.credit_note_lines l left join public.items i on i.id = l.item_id where l.note_id = p_doc;
  else
    select s.no, s.date, s.created_at, s.reason, (select r.no from public.sales_invoices r where r.id = s.ref_id), s.party_id into no, d, t, rsn, ref, p.id
      from public.sales_invoices s where s.id = p_doc;
    select coalesce(jsonb_agg(jsonb_build_object('name', coalesce(i.name, 'بند'), 'qty', l.qty, 'price', l.unit_price, 'rate', l.vat_rate,
      'exemptCode', i.vat_exempt_code, 'exemptReason', i.vat_exempt_reason) order by l.id), '[]') into lines
      from public.sales_invoice_lines l left join public.items i on i.id = l.item_id where l.invoice_id = p_doc;
  end if;
  select * into p from public.parties where id = p.id;
  return jsonb_build_object('kind', z.kind, 'type', z.inv_type, 'no', no, 'uuid', z.doc_id, 'icv', z.icv,
    'issueDate', d, 'issueTime', to_char(t at time zone 'Asia/Riyadh', 'HH24:MI:SS'), 'refNo', ref, 'reason', rsn,
    'seller', jsonb_build_object('name', c.name, 'vat', c.vat_no, 'cr', coalesce((select nullif(b.cr_sub, '') from public.branches b where b.id = z.unit), c.cr_no), 'street', c.street, 'building', c.bld_no, 'district', c.district,
      'city', c.city, 'postal', c.postal_code, 'addNo', c.add_no),
    'buyer', case when z.inv_type = 'standard' or nullif(trim(p.vat_no), '') is not null then jsonb_build_object('name', p.name, 'vat', nullif(trim(p.vat_no), ''),
      'cr', p.cr_no, 'street', p.street, 'building', p.bld_no, 'district', p.district, 'city', p.city, 'postal', p.postal_code, 'addNo', p.add_no) end,
    'lines', lines);
end $$;

-- the signing secrets of one chain (service role only): the company's unit (p_unit null) or a branch's
create or replace function public.zatca_unit_creds(p_company uuid, p_unit uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when p_unit is null then public.zatca_creds(p_company) else
    (select jsonb_build_object('env', u.env, 'cert', u.csid_cert, 'key', k.private_key, 'token', k.csid_token, 'secret', k.csid_secret)
       from public.zatca_units u join public.zatca_unit_secrets k on k.branch_id = u.branch_id where u.branch_id = p_unit and u.company_id = p_company and u.enabled) end
$$;

create or replace function public.zatca_can_send(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.fin_can(p_company, 'sales') and (exists(select 1 from public.zatca_settings where company_id = p_company and enabled)
                                                 or exists(select 1 from public.zatca_units where company_id = p_company and enabled))
$$;

create or replace function public.zatca_waiting() returns setof uuid
language sql stable security definer set search_path = public as $$
  select distinct z.company_id from public.zatca_docs z
   where z.status in ('pending','error') and z.next_try <= now()
     and case when z.unit is null then exists(select 1 from public.zatca_settings s where s.company_id = z.company_id and s.enabled)
              else exists(select 1 from public.zatca_units x where x.branch_id = z.unit and x.enabled) end
$$;

-- linking a branch: the owner or an admin (two-step verification when required); the company's official data with the
-- branch as the unit (OU) and its sub-registration
create or replace function public.zatca_unit_onboard_info(p_company uuid, p_branch uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.companies; b public.branches;
begin
  if not (public.aal_ok() and public.has_role(p_company, array['owner','admin'])) then raise exception 'الربط مع فاتورة لمالك المنشأة أو مديرها' using errcode = '42501'; end if;
  select * into b from public.branches where id = p_branch and company_id = p_company;
  if not found then raise exception 'الفرع لا يخص هذه المنشأة'; end if;
  if not b.active then raise exception 'الفرع موقوف'; end if;
  select * into c from public.companies where id = p_company;
  return jsonb_build_object('name', c.name, 'vat', c.vat_no, 'cr', coalesce(nullif(b.cr_sub, ''), c.cr_no), 'street', c.street, 'building', c.bld_no, 'district', c.district,
    'city', c.city, 'postal', c.postal_code, 'addNo', c.add_no, 'category', coalesce(c.industry, 'other'), 'branch', b.name, 'egs', 'Waad-' || b.code);
end $$;

create or replace function public.zatca_unit_onboarded(p_company uuid, p_branch uuid, p_env text, p_serial text, p_cert text, p_key text, p_token text, p_secret text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from public.branches where id = p_branch and company_id = p_company) then raise exception 'الفرع لا يخص هذه المنشأة'; end if;
  insert into public.zatca_units(branch_id, company_id, enabled, env, egs_serial, csid_cert, onboarded_at, last_error, updated_at)
  values (p_branch, p_company, true, p_env, p_serial, p_cert, now(), null, now())
  on conflict (branch_id) do update set enabled = true, env = excluded.env, egs_serial = excluded.egs_serial, csid_cert = excluded.csid_cert,
    onboarded_at = now(), last_error = null, updated_at = now();
  insert into public.zatca_unit_secrets(branch_id, private_key, csid_token, csid_secret, updated_at) values (p_branch, p_key, p_token, p_secret, now())
  on conflict (branch_id) do update set private_key = excluded.private_key, csid_token = excluded.csid_token, csid_secret = excluded.csid_secret, updated_at = now();
end $$;

create or replace function public.zatca_unit_onboard_failed(p_company uuid, p_branch uuid, p_error text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from public.branches where id = p_branch and company_id = p_company) then return; end if;
  insert into public.zatca_units(branch_id, company_id, last_error) values (p_branch, p_company, left(p_error, 1000))
  on conflict (branch_id) do update set last_error = left(p_error, 1000), updated_at = now();
end $$;

-- the owner / an admin stops a branch's unit: its new documents go to the company's unit. Not while the branch chain
-- still has documents waiting (they must reach ZATCA first). Linking again restarts it where it was.
create or replace function public.zatca_unit_off(p_company uuid, p_branch uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (public.aal_ok() and public.has_role(p_company, array['owner','admin'])) then raise exception 'الربط مع فاتورة لمالك المنشأة أو مديرها' using errcode = '42501'; end if;
  if exists(select 1 from public.zatca_docs where company_id = p_company and unit = p_branch and status in ('pending','error')) then
    raise exception 'في سلسلة الفرع مستندات لم تصل زاتكا بعد — انتظر إرسالها ثم أوقف الوحدة'; end if;
  update public.zatca_units set enabled = false, updated_at = now() where branch_id = p_branch and company_id = p_company;
  if not found then raise exception 'الفرع غير مربوط'; end if;
end $$;

-- the company export never carries a signing key
create or replace function public.company_export_data(p_company uuid, p_files boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  f jsonb := jsonb_build_object('companies', format('id = %L', p_company));   -- table → where clause
  skip text[] := array['client_errors', 'doc_sequences', 'platform_admins', 'platform_settings', 'zatca_secrets', 'zatca_unit_secrets', 'portal_links', 'company_exports_log', 'company_deletions'];
  t record; fk record; pass int; added boolean; res jsonb := '{}'; rows jsonb; strip text[]; n int := 0; tot int := 0;
begin
  for t in select c.relname from pg_class c join pg_attribute a on a.attrelid = c.oid
            where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and a.attname = 'company_id' and not a.attisdropped
              and c.relname <> all(skip) loop
    f := f || jsonb_build_object(t.relname, format('company_id = %L', p_company));
  end loop;
  for pass in 1..4 loop
    added := false;
    for fk in select distinct on (c.relname) c.relname child, a.attname col, p.relname parent, pa.attname pcol
                from pg_constraint k join pg_class c on c.oid = k.conrelid join pg_class p on p.oid = k.confrelid
                join pg_attribute a on a.attrelid = c.oid and a.attnum = k.conkey[1]
                join pg_attribute pa on pa.attrelid = p.oid and pa.attnum = k.confkey[1]
               where k.contype = 'f' and cardinality(k.conkey) = 1 and c.relnamespace = 'public'::regnamespace and p.relnamespace = 'public'::regnamespace
                 and f ? p.relname and not f ? c.relname and c.relname <> all(skip)
               order by c.relname, k.conname loop
      f := f || jsonb_build_object(fk.child, format('%I in (select %I from public.%I where %s)', fk.col, fk.pcol, fk.parent, f->>fk.parent));
      added := true;
    end loop;
    exit when not added;
  end loop;
  for t in select key tbl, value #>> '{}' cond from jsonb_each(f) order by key loop
    strip := case when p_files then '{}'::text[] else array(
      select a.attname::text from pg_attribute a where a.attrelid = ('public.' || quote_ident(t.tbl))::regclass and a.attnum > 0 and not a.attisdropped
         and ((a.attname = 'data' and a.atttypid = 'text'::regtype) or (t.tbl = 'companies' and a.attname = 'logo'))) end;
    execute format('select coalesce(jsonb_agg(to_jsonb(x) - %L::text[]), ''[]'') from public.%I x where %s', strip, t.tbl, t.cond) into rows;
    n := n + 1; tot := tot + jsonb_array_length(rows);
    res := res || jsonb_build_object(t.tbl, rows);
  end loop;
  return jsonb_build_object('company_id', p_company, 'exported_at', now(), 'with_files', p_files, 'tables', res, 'n_tables', n, 'n_rows', tot);
end $$;

revoke all on function public.zatca_unit_prev_hash(uuid, uuid, bigint), public.zatca_enqueue(), public.zatca_docs_guard(), public.zatca_prev_hash(uuid, bigint) from public, anon, authenticated;
revoke all on function public.zatca_claim(uuid), public.zatca_doc_data(uuid), public.zatca_unit_creds(uuid, uuid), public.zatca_waiting(),
  public.zatca_unit_onboarded(uuid, uuid, text, text, text, text, text, text), public.zatca_unit_onboard_failed(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.zatca_claim(uuid), public.zatca_doc_data(uuid), public.zatca_unit_creds(uuid, uuid), public.zatca_waiting(),
  public.zatca_unit_onboarded(uuid, uuid, text, text, text, text, text, text), public.zatca_unit_onboard_failed(uuid, uuid, text) to service_role;
revoke all on function public.zatca_can_send(uuid), public.zatca_unit_onboard_info(uuid, uuid), public.zatca_unit_off(uuid, uuid) from public, anon;
grant execute on function public.zatca_can_send(uuid), public.zatca_unit_onboard_info(uuid, uuid), public.zatca_unit_off(uuid, uuid) to authenticated;
revoke all on function public.company_export_data(uuid, boolean) from public, anon, authenticated;
notify pgrst, 'reload schema';
