-- Permanently deletes ONE company (by its code) and everything in it.
-- Ledger/audit protections (append-only triggers) are paused only inside this transaction, then restored.
begin;
do $$ declare t text; begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I disable trigger user', t);
  end loop;
end $$;
do $$
declare cid uuid := (select id from public.companies where code = '72F3D0');
begin
  if cid is null then raise exception 'company code not found'; end if;
  delete from public.payroll_lines where run_id in (select id from public.payroll_runs where company_id = cid);
  delete from public.advance_deductions where run_id in (select id from public.payroll_runs where company_id = cid);
  delete from public.payroll_runs where company_id = cid;
  delete from public.request_actions where request_id in (select id from public.requests where company_id = cid);
  delete from public.requests where company_id = cid;
  delete from public.custody where company_id = cid;
  delete from public.credit_note_lines where note_id in (select id from public.credit_notes where company_id = cid);
  delete from public.credit_notes where company_id = cid;
  delete from public.payments where company_id = cid;
  delete from public.sales_invoice_lines where invoice_id in (select id from public.sales_invoices where company_id = cid);
  delete from public.sales_invoices where company_id = cid;
  delete from public.purchase_bill_lines where bill_id in (select id from public.purchase_bills where company_id = cid);
  delete from public.purchase_bills where company_id = cid;
  delete from public.stock_moves where company_id = cid;
  delete from public.journal_lines where company_id = cid;
  delete from public.journal_entries where company_id = cid;
  delete from public.items where company_id = cid;
  delete from public.parties where company_id = cid;
  delete from public.invites where company_id = cid;
  delete from public.members where company_id = cid;
  update public.employees set manager_id = null where company_id = cid;
  delete from public.employees where company_id = cid;
  delete from public.departments where company_id = cid;
  delete from public.workflows where company_id = cid;
  delete from public.finance_permissions where company_id = cid;
  delete from public.accounts where company_id = cid;
  delete from public.doc_sequences where company_id = cid;
  delete from public.audit_log where company_id = cid or (entity = 'companies' and entity_id = cid::text);
  delete from public.companies where id = cid;
end $$;
do $$ declare t text; begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable trigger user', t);
  end loop;
end $$;
commit;
select count(*) as companies_left from public.companies;
