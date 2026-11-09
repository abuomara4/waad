-- Waad ERP — 0004 grants. RLS decides row access; these grants decide which RPCs the browser may call.
-- Supabase grants every new function to anon/authenticated by default: any future migration that adds a
-- function must revoke it from public, anon, authenticated and grant only what the browser needs.
revoke all on all functions in schema public from public, anon, authenticated;
revoke all on all tables in schema public from anon;

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- helpers used inside RLS policies
grant execute on function public.my_role(uuid), public.is_member(uuid), public.has_role(uuid, text[]), public.my_employee(uuid),
  public.fin(uuid), public.fin_can(uuid, text), public.je_visible(uuid), public.can_see_payline(uuid, uuid), public.gross_wage(public.employees), public.can_act(public.requests, text),
  public.step_label(text), public.default_route(text), public.days_between(date, date) to authenticated;

-- callable RPCs (each checks the caller's role itself)
grant execute on function
  public.create_company(text, text, text),
  public.submit_request(uuid, text, text, date, date, numeric, jsonb, text),
  public.decide_request(uuid, boolean, text),
  public.cancel_request(uuid),
  public.annual_entitlement(date, date),
  public.gosi_is_new(boolean, date), public.gosi_annuity(boolean, date), public.gosi_rate(boolean, date), public.gosi_base(numeric, numeric),
  public.gosi_employee(boolean, numeric, numeric, boolean, date), public.gosi_employer(boolean, numeric, numeric, boolean, date),
  public.eos_fraction(text, numeric), public.eos_calc(numeric, date, date, text, numeric),
  public.payroll_prepare(uuid, int, int, date), public.payroll_adjust(uuid, uuid, numeric, numeric, numeric),
  public.payroll_approve(uuid), public.payroll_mark_paid(uuid, text),
  public.add_account(uuid, text, text, text), public.set_finance_permission(uuid, text, text, boolean),
  public.post_manual_journal(uuid, date, text, jsonb), public.reverse_journal(uuid, date),
  public.post_sales_invoice(uuid, jsonb), public.post_purchase_bill(uuid, jsonb), public.record_payment(uuid, jsonb),
  public.void_sales_invoice(uuid, text), public.void_purchase_bill(uuid, text), public.post_credit_note(uuid, jsonb),
  public.stock_adjust(uuid, uuid, date, numeric, numeric, text), 
  public.trial_balance(uuid, date), public.income_statement(uuid, date, date), public.balance_sheet(uuid, date),
  public.vat_summary(uuid, date, date), public.account_ledger(uuid, text, date, date), public.aging(uuid, text, date)
to authenticated;

-- trigger functions still run (triggers don't need EXECUTE for the caller).
-- NOT granted (internal only): post_journal, reverse_source, next_doc_no, seed_company, payroll_line_recalc,
-- on_request_approved, require_role, require_fin, cn_guard, audit_trigger, block_change, check_entry_balanced, account_balance, stock_state, paid_on, advance_remaining.

-- tables written only via RPC: remove direct write grants so RLS is not the only guard
revoke insert, update, delete on public.requests, public.request_actions, public.payroll_runs, public.payroll_lines,
  public.journal_entries, public.journal_lines, public.stock_moves, public.sales_invoices, public.sales_invoice_lines,
  public.purchase_bills, public.purchase_bill_lines, public.payments, public.credit_notes, public.credit_note_lines, public.advance_deductions, public.audit_log, public.doc_sequences, public.leave_types, public.finance_permissions,
  public.accounts
from authenticated;
