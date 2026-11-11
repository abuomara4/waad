-- Waad ERP — 0080 ZATCA Phase 2, step 4: sending documents to Fatoora (docs/ZATCA_PHASE2.md).
-- The server function takes the documents of a linked company strictly in chain order (zatca_claim), reads what the XML
-- needs (zatca_doc_data), stores the signature (zatca_signed) and ZATCA's answer (zatca_result). Failures of the network or
-- of ZATCA's service are retried with a growing wait; a rejected document stays rejected (it is corrected by a new one).
-- Sending is started by the app (right after posting, and when a finance user opens it); zatca_waiting lists the companies
-- with something due, for a scheduled retry later.

-- a zero-rated item must say why (ZATCA exemption code, e.g. VATEX-SA-32 exports, VATEX-SA-35 medicines)
alter table public.items add column if not exists vat_exempt_code text check (vat_exempt_code is null or vat_exempt_code ~ '^VATEX-SA-[0-9A-Z-]{2,10}$');
alter table public.items add column if not exists vat_exempt_reason text check (vat_exempt_reason is null or length(vat_exempt_reason) <= 200);

alter table public.zatca_docs add column if not exists lease_until timestamptz;
alter table public.zatca_docs add column if not exists last_error text;

-- who may ask the server to send now: anyone who may see the company's sales
create or replace function public.zatca_can_send(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.fin_can(p_company, 'sales') and exists(select 1 from public.zatca_settings where company_id = p_company and enabled)
$$;

-- the next document to work on, strictly in chain order (a waiting one holds the ones after it), leased for 2 minutes
create or replace function public.zatca_claim(p_company uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d public.zatca_docs;
begin
  select * into d from public.zatca_docs where company_id = p_company and status in ('pending','error') order by icv limit 1 for update;
  if not found or d.next_try > now() or coalesce(d.lease_until, '-infinity') > now() then return null; end if;
  update public.zatca_docs set lease_until = now() + interval '2 minutes', attempts = attempts + 1 where id = d.id;
  return jsonb_build_object('id', d.id, 'doc_id', d.doc_id, 'icv', d.icv, 'kind', d.kind, 'inv_type', d.inv_type, 'hash', d.hash, 'xml', d.xml,
    'pih', coalesce(d.pih, public.zatca_prev_hash(p_company, d.icv)), 'attempts', d.attempts + 1);
end $$;

-- everything the XML needs about one document: seller, buyer, lines, the original invoice for a credit / debit note
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
    'seller', jsonb_build_object('name', c.name, 'vat', c.vat_no, 'cr', c.cr_no, 'street', c.street, 'building', c.bld_no, 'district', c.district,
      'city', c.city, 'postal', c.postal_code, 'addNo', c.add_no),
    'buyer', case when z.inv_type = 'standard' or nullif(trim(p.vat_no), '') is not null then jsonb_build_object('name', p.name, 'vat', nullif(trim(p.vat_no), ''),
      'cr', p.cr_no, 'street', p.street, 'building', p.bld_no, 'district', p.district, 'city', p.city, 'postal', p.postal_code, 'addNo', p.add_no) end,
    'lines', lines);
end $$;

-- the signature, once (the chain guard refuses a second one)
create or replace function public.zatca_signed(p_id bigint, p_pih text, p_hash text, p_xml text, p_qr text) returns void
language sql security definer set search_path = public as $$
  update public.zatca_docs set pih = p_pih, hash = p_hash, xml = p_xml, qr = p_qr where id = p_id
$$;

-- ZATCA's answer. p_status: reported / cleared / warning / rejected / error. For a cleared invoice ZATCA returns the stamped
-- XML and QR, kept in place of ours. An error waits p_retry seconds; a document that cannot be built keeps its error text.
create or replace function public.zatca_result(p_id bigint, p_status text, p_resp jsonb, p_xml text, p_qr text, p_retry int, p_error text) returns void
language sql security definer set search_path = public as $$
  update public.zatca_docs set status = p_status, resp = coalesce(p_resp, resp), xml = coalesce(p_xml, xml), qr = coalesce(p_qr, qr),
    sent_at = case when p_status in ('reported','cleared','warning','rejected') then now() else sent_at end,
    next_try = now() + make_interval(secs => coalesce(p_retry, 0)), lease_until = null, last_error = p_error
  where id = p_id
$$;

-- companies with something waiting (for a scheduled retry)
create or replace function public.zatca_waiting() returns setof uuid
language sql stable security definer set search_path = public as $$
  select distinct z.company_id from public.zatca_docs z join public.zatca_settings s on s.company_id = z.company_id and s.enabled
  where z.status in ('pending','error') and z.next_try <= now()
$$;

-- the secrets the server signs and sends with (service role only)
create or replace function public.zatca_creds(p_company uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('env', s.env, 'cert', s.csid_cert, 'key', k.private_key, 'token', k.csid_token, 'secret', k.csid_secret)
  from public.zatca_settings s join public.zatca_secrets k on k.company_id = s.company_id where s.company_id = p_company and s.enabled
$$;

revoke all on function public.zatca_claim(uuid), public.zatca_doc_data(uuid), public.zatca_signed(bigint, text, text, text, text),
  public.zatca_result(bigint, text, jsonb, text, text, int, text), public.zatca_waiting(), public.zatca_creds(uuid) from public, anon, authenticated;
grant execute on function public.zatca_claim(uuid), public.zatca_doc_data(uuid), public.zatca_signed(bigint, text, text, text, text),
  public.zatca_result(bigint, text, jsonb, text, text, int, text), public.zatca_waiting(), public.zatca_creds(uuid) to service_role;
revoke all on function public.zatca_can_send(uuid) from public, anon;
grant execute on function public.zatca_can_send(uuid) to authenticated;
