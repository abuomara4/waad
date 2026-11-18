-- 0127 — capacity findings of the full review (2026-11-18)
-- * Indexes on the foreign keys that row policies, joins and deletes rely on (a parent's delete scans cascade / set-null children).
-- * Files are kept inside the database: the Waad team sees how much each company uses and the database's share of its plan limit,
--   and may set a files limit per company (none by default, so nothing changes for anyone until it is set).

create index if not exists advance_deductions_request_id_fk on public.advance_deductions(request_id);
create index if not exists announcement_reads_company_id_fk on public.announcement_reads(company_id);
create index if not exists announcement_reads_user_id_fk on public.announcement_reads(user_id);
create index if not exists attendance_in_site_fk on public.attendance(in_site);
create index if not exists attendance_out_site_fk on public.attendance(out_site);
create index if not exists attendance_shift_id_fk on public.attendance(shift_id);
create index if not exists bank_cleared_recon_id_fk on public.bank_cleared(recon_id);
create index if not exists bank_facilities_entry_id_fk on public.bank_facilities(entry_id);
create index if not exists bank_facilities_project_id_fk on public.bank_facilities(project_id);
create index if not exists bank_facilities_release_entry_fk on public.bank_facilities(release_entry);
create index if not exists bank_recons_company_id_fk on public.bank_recons(company_id);
create index if not exists candidate_files_company_id_fk on public.candidate_files(company_id);
create index if not exists candidates_company_id_fk on public.candidates(company_id);
create index if not exists candidates_employee_id_fk on public.candidates(employee_id);
create index if not exists cheques_bill_id_fk on public.cheques(bill_id);
create index if not exists cheques_invoice_id_fk on public.cheques(invoice_id);
create index if not exists cheques_party_id_fk on public.cheques(party_id);
create index if not exists clearance_marks_company_id_fk on public.clearance_marks(company_id);
create index if not exists client_errors_company_id_fk on public.client_errors(company_id);
create index if not exists comp_credits_att_id_fk on public.comp_credits(att_id);
create index if not exists comp_credits_company_id_fk on public.comp_credits(company_id);
create index if not exists company_announcements_department_id_fk on public.company_announcements(department_id);
create index if not exists company_document_files_company_document_id_fk on public.company_document_files(company_document_id);
create index if not exists company_document_files_company_id_fk on public.company_document_files(company_id);
create index if not exists company_subscriptions_plan_id_fk on public.company_subscriptions(plan_id);
create index if not exists contract_files_company_id_fk on public.contract_files(company_id);
create index if not exists contracts_company_id_fk on public.contracts(company_id);
create index if not exists contracts_prev_id_fk on public.contracts(prev_id);
create index if not exists credit_note_lines_item_id_fk on public.credit_note_lines(item_id);
create index if not exists credit_note_lines_note_id_fk on public.credit_note_lines(note_id);
create index if not exists credit_notes_party_id_fk on public.credit_notes(party_id);
create index if not exists crm_leads_party_id_fk on public.crm_leads(party_id);
create index if not exists custody_employee_id_fk on public.custody(employee_id);
create index if not exists custody_files_company_id_fk on public.custody_files(company_id);
create index if not exists custody_items_company_id_fk on public.custody_items(company_id);
create index if not exists delivery_note_lines_item_id_fk on public.delivery_note_lines(item_id);
create index if not exists delivery_notes_party_id_fk on public.delivery_notes(party_id);
create index if not exists departments_head_id_fk on public.departments(head_id);
create index if not exists departments_shift_id_fk on public.departments(shift_id);
create index if not exists document_files_company_id_fk on public.document_files(company_id);
create index if not exists employee_allowances_company_id_fk on public.employee_allowances(company_id);
create index if not exists employees_department_id_fk on public.employees(department_id);
create index if not exists employees_grade_id_fk on public.employees(grade_id);
create index if not exists employees_shift_id_fk on public.employees(shift_id);
create index if not exists employees_work_site_id_fk on public.employees(work_site_id);
create index if not exists exit_visas_company_id_fk on public.exit_visas(company_id);
create index if not exists exit_visas_request_id_fk on public.exit_visas(request_id);
create index if not exists facility_instalments_company_id_fk on public.facility_instalments(company_id);
create index if not exists facility_instalments_entry_id_fk on public.facility_instalments(entry_id);
create index if not exists fixed_assets_cost_center_id_fk on public.fixed_assets(cost_center_id);
create index if not exists fixed_assets_custodian_id_fk on public.fixed_assets(custodian_id);
create index if not exists goods_receipt_lines_item_id_fk on public.goods_receipt_lines(item_id);
create index if not exists goods_receipts_party_id_fk on public.goods_receipts(party_id);
create index if not exists guide_quiz_results_employee_id_fk on public.guide_quiz_results(employee_id);
create index if not exists headcount_plans_company_id_fk on public.headcount_plans(company_id);
create index if not exists headcount_plans_department_id_fk on public.headcount_plans(department_id);
create index if not exists headcount_plans_opening_id_fk on public.headcount_plans(opening_id);
create index if not exists insurance_members_company_id_fk on public.insurance_members(company_id);
create index if not exists invites_employee_id_fk on public.invites(employee_id);
create index if not exists job_openings_department_id_fk on public.job_openings(department_id);
create index if not exists journal_drafts_entry_id_fk on public.journal_drafts(entry_id);
create index if not exists journal_drafts_reversed_entry_fk on public.journal_drafts(reversed_entry);
create index if not exists journal_lines_entry_id_fk on public.journal_lines(entry_id);
create index if not exists member_perms_user_id_fk on public.member_perms(user_id);
create index if not exists members_employee_id_fk on public.members(employee_id);
create index if not exists okr_key_results_company_id_fk on public.okr_key_results(company_id);
create index if not exists okr_objectives_department_id_fk on public.okr_objectives(department_id);
create index if not exists okr_objectives_employee_id_fk on public.okr_objectives(employee_id);
create index if not exists onboarding_marks_company_id_fk on public.onboarding_marks(company_id);
create index if not exists payments_bill_id_fk on public.payments(bill_id);
create index if not exists payments_invoice_id_fk on public.payments(invoice_id);
create index if not exists payments_party_id_fk on public.payments(party_id);
create index if not exists payroll_lines_employee_id_fk on public.payroll_lines(employee_id);
create index if not exists penalty_deductions_penalty_id_fk on public.penalty_deductions(penalty_id);
create index if not exists period_locks_company_id_fk on public.period_locks(company_id);
create index if not exists petty_claims_cost_center_id_fk on public.petty_claims(cost_center_id);
create index if not exists petty_claims_milestone_id_fk on public.petty_claims(milestone_id);
create index if not exists petty_funds_employee_id_fk on public.petty_funds(employee_id);
create index if not exists platform_payments_plan_id_fk on public.platform_payments(plan_id);
create index if not exists policies_company_id_fk on public.policies(company_id);
create index if not exists policy_acks_company_id_fk on public.policy_acks(company_id);
create index if not exists policy_acks_employee_id_fk on public.policy_acks(employee_id);
create index if not exists portal_links_party_id_fk on public.portal_links(party_id);
create index if not exists prepaid_postings_entry_id_fk on public.prepaid_postings(entry_id);
create index if not exists prepaid_schedules_company_id_fk on public.prepaid_schedules(company_id);
create index if not exists prepaid_schedules_cost_center_id_fk on public.prepaid_schedules(cost_center_id);
create index if not exists project_boq_company_id_fk on public.project_boq(company_id);
create index if not exists project_change_orders_project_id_fk on public.project_change_orders(project_id);
create index if not exists project_claims_invoice_id_fk on public.project_claims(invoice_id);
create index if not exists project_members_company_id_fk on public.project_members(company_id);
create index if not exists project_members_employee_id_fk on public.project_members(employee_id);
create index if not exists project_milestones_company_id_fk on public.project_milestones(company_id);
create index if not exists project_risks_company_id_fk on public.project_risks(company_id);
create index if not exists project_risks_owner_id_fk on public.project_risks(owner_id);
create index if not exists project_risks_project_id_fk on public.project_risks(project_id);
create index if not exists project_tasks_assignee_id_fk on public.project_tasks(assignee_id);
create index if not exists project_tasks_company_id_fk on public.project_tasks(company_id);
create index if not exists project_tasks_milestone_id_fk on public.project_tasks(milestone_id);
create index if not exists project_versions_co_id_fk on public.project_versions(co_id);
create index if not exists project_versions_company_id_fk on public.project_versions(company_id);
create index if not exists project_versions_project_id_fk on public.project_versions(project_id);
create index if not exists projects_cost_center_id_fk on public.projects(cost_center_id);
create index if not exists projects_manager_id_fk on public.projects(manager_id);
create index if not exists projects_party_id_fk on public.projects(party_id);
create index if not exists purchase_bill_files_company_id_fk on public.purchase_bill_files(company_id);
create index if not exists purchase_bill_lines_bill_id_fk on public.purchase_bill_lines(bill_id);
create index if not exists purchase_bill_lines_item_id_fk on public.purchase_bill_lines(item_id);
create index if not exists purchase_bills_party_id_fk on public.purchase_bills(party_id);
create index if not exists purchase_order_lines_item_id_fk on public.purchase_order_lines(item_id);
create index if not exists purchase_orders_cost_center_id_fk on public.purchase_orders(cost_center_id);
create index if not exists purchase_orders_milestone_id_fk on public.purchase_orders(milestone_id);
create index if not exists purchase_orders_party_id_fk on public.purchase_orders(party_id);
create index if not exists push_subscriptions_user_id_fk on public.push_subscriptions(user_id);
create index if not exists recurring_invoices_last_invoice_id_fk on public.recurring_invoices(last_invoice_id);
create index if not exists recurring_invoices_party_id_fk on public.recurring_invoices(party_id);
create index if not exists request_actions_request_id_fk on public.request_actions(request_id);
create index if not exists request_attachments_company_id_fk on public.request_attachments(company_id);
create index if not exists review_feedback_company_id_fk on public.review_feedback(company_id);
create index if not exists review_feedback_employee_id_fk on public.review_feedback(employee_id);
create index if not exists review_feedback_rater_id_fk on public.review_feedback(rater_id);
create index if not exists reviews_employee_id_fk on public.reviews(employee_id);
create index if not exists rfq_lines_item_id_fk on public.rfq_lines(item_id);
create index if not exists rfq_lines_rfq_id_fk on public.rfq_lines(rfq_id);
create index if not exists rfq_quote_lines_line_id_fk on public.rfq_quote_lines(line_id);
create index if not exists rfq_quotes_party_id_fk on public.rfq_quotes(party_id);
create index if not exists rfqs_po_id_fk on public.rfqs(po_id);
create index if not exists rfqs_request_id_fk on public.rfqs(request_id);
create index if not exists salary_history_company_id_fk on public.salary_history(company_id);
create index if not exists sales_invoice_lines_invoice_id_fk on public.sales_invoice_lines(invoice_id);
create index if not exists sales_invoice_lines_item_id_fk on public.sales_invoice_lines(item_id);
create index if not exists sales_invoices_party_id_fk on public.sales_invoices(party_id);
create index if not exists sales_invoices_ref_id_fk on public.sales_invoices(ref_id);
create index if not exists sales_orders_party_id_fk on public.sales_orders(party_id);
create index if not exists shift_roster_shift_id_fk on public.shift_roster(shift_id);
create index if not exists stock_batches_company_id_fk on public.stock_batches(company_id);
create index if not exists stock_count_lines_item_id_fk on public.stock_count_lines(item_id);
create index if not exists stock_transfer_lines_item_id_fk on public.stock_transfer_lines(item_id);
create index if not exists stock_transfer_lines_transfer_id_fk on public.stock_transfer_lines(transfer_id);
create index if not exists supplier_inbox_bill_id_fk on public.supplier_inbox(bill_id);
create index if not exists supplier_inbox_order_id_fk on public.supplier_inbox(order_id);
create index if not exists supplier_inbox_party_id_fk on public.supplier_inbox(party_id);
create index if not exists supplier_inbox_files_company_id_fk on public.supplier_inbox_files(company_id);
create index if not exists supplier_ratings_company_id_fk on public.supplier_ratings(company_id);
create index if not exists supplier_ratings_po_id_fk on public.supplier_ratings(po_id);
create index if not exists support_tickets_user_id_fk on public.support_tickets(user_id);
create index if not exists survey_responses_company_id_fk on public.survey_responses(company_id);
create index if not exists survey_responses_survey_id_fk on public.survey_responses(survey_id);
create index if not exists survey_takers_user_id_fk on public.survey_takers(user_id);
create index if not exists surveys_company_id_fk on public.surveys(company_id);
create index if not exists timesheets_cost_entry_fk on public.timesheets(cost_entry);
create index if not exists timesheets_employee_id_fk on public.timesheets(employee_id);
create index if not exists timesheets_invoice_id_fk on public.timesheets(invoice_id);
create index if not exists timesheets_task_id_fk on public.timesheets(task_id);
create index if not exists training_attendees_company_id_fk on public.training_attendees(company_id);
create index if not exists training_plans_department_id_fk on public.training_plans(department_id);
create index if not exists training_plans_training_id_fk on public.training_plans(training_id);
create index if not exists travel_files_company_id_fk on public.travel_files(company_id);
create index if not exists travel_files_employee_id_fk on public.travel_files(employee_id);
create index if not exists travel_tickets_company_id_fk on public.travel_tickets(company_id);
create index if not exists travel_tickets_request_id_fk on public.travel_tickets(request_id);
create index if not exists vehicle_files_company_id_fk on public.vehicle_files(company_id);
create index if not exists vehicle_files_vehicle_id_fk on public.vehicle_files(vehicle_id);
create index if not exists vehicle_logs_company_id_fk on public.vehicle_logs(company_id);
create index if not exists vehicle_logs_driver_id_fk on public.vehicle_logs(driver_id);
create index if not exists vehicle_logs_entry_id_fk on public.vehicle_logs(entry_id);
create index if not exists vehicles_driver_id_fk on public.vehicles(driver_id);

alter table public.company_subscriptions add column if not exists max_file_mb int check (max_file_mb is null or max_file_mb > 0);
alter table public.platform_settings add column if not exists db_limit_mb int not null default 500 check (db_limit_mb > 0);

create or replace function public.company_files_bytes(p_company uuid) returns bigint language sql stable security definer set search_path = public as $$
  select coalesce(sum(size), 0)::bigint from (select company_id, size from public.request_attachments union all select company_id, size from public.travel_files union all select company_id, size from public.candidate_files union all select company_id, size from public.contract_files union all select company_id, size from public.document_files union all select company_id, size from public.custody_files union all select company_id, size from public.company_document_files union all select company_id, size from public.vehicle_files union all select company_id, size from public.purchase_bill_files union all select company_id, size from public.supplier_inbox_files) f where f.company_id = p_company
$$;
create or replace function public.files_quota_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare q int;
begin
  select max_file_mb into q from public.company_subscriptions where company_id = new.company_id;
  if q is not null and public.company_files_bytes(new.company_id) + new.size > q::bigint * 1048576 then
    raise exception 'وصلت منشأتك إلى حد مساحة الملفات (% ميجابايت). احذف ملفات لا تحتاجها أو تواصل مع وعد', q; end if;
  return new;
end $$;
do $$ declare t text;
begin
  foreach t in array array['request_attachments','travel_files','candidate_files','contract_files','document_files','custody_files','company_document_files','vehicle_files','purchase_bill_files','supplier_inbox_files'] loop
    execute format('drop trigger if exists files_quota on public.%I', t);
    execute format('create trigger files_quota before insert on public.%I for each row execute function public.files_quota_guard()', t);
  end loop;
end $$;
-- sizes only: never a file or a file name
create or replace function public.platform_storage() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.platform_guard();
  return jsonb_build_object('db_bytes', pg_database_size(current_database()), 'limit_mb', (select db_limit_mb from public.platform_settings limit 1),
    'files_bytes', (select coalesce(sum(size), 0) from (select company_id, size from public.request_attachments union all select company_id, size from public.travel_files union all select company_id, size from public.candidate_files union all select company_id, size from public.contract_files union all select company_id, size from public.document_files union all select company_id, size from public.custody_files union all select company_id, size from public.company_document_files union all select company_id, size from public.vehicle_files union all select company_id, size from public.purchase_bill_files union all select company_id, size from public.supplier_inbox_files) f),
    'companies', coalesce((select jsonb_agg(x order by x.bytes desc) from (select c.id, c.name, s.max_file_mb quota, f.bytes from (select company_id, sum(size)::bigint bytes from (select company_id, size from public.request_attachments union all select company_id, size from public.travel_files union all select company_id, size from public.candidate_files union all select company_id, size from public.contract_files union all select company_id, size from public.document_files union all select company_id, size from public.custody_files union all select company_id, size from public.company_document_files union all select company_id, size from public.vehicle_files union all select company_id, size from public.purchase_bill_files union all select company_id, size from public.supplier_inbox_files) a group by 1 order by 2 desc limit 30) f
       join public.companies c on c.id = f.company_id left join public.company_subscriptions s on s.company_id = c.id) x), '[]'));
end $$;
create or replace function public.platform_file_quota_set(p_company uuid, p_mb int) returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.platform_need('subs');
  update public.company_subscriptions set max_file_mb = p_mb where company_id = p_company;
  if not found then raise exception 'المنشأة بلا اشتراك'; end if;
end $$;
revoke all on function public.company_files_bytes(uuid), public.files_quota_guard(), public.platform_storage(), public.platform_file_quota_set(uuid, int) from public, anon, authenticated;
grant execute on function public.platform_storage(), public.platform_file_quota_set(uuid, int) to authenticated;
