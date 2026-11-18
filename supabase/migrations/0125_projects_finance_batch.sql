-- 0125 — projects and finance completion batch (owner's request, 2026-11-18)
-- * A project manager who is an ordinary employee opens the projects he manages (no wages: hours come without their cost).
-- * Change orders can change the quantity or rate of an existing contract item (never below what was claimed; a claimed item keeps its rate).
-- * A credit note or a void on a claim's invoice now corrects the claim: earlier work, the advance and the retention follow it.
-- * Bell and phone alerts: hours to approve, rejected hours, loan instalments, guarantees expiring.
-- * Costs can carry a milestone (purchase orders, petty cash, materials): journal_lines.milestone_id, cost per milestone.
-- * A week of hours is submitted in one step.

-- ---------------- the project manager ----------------
create or replace function public.proj_mgr(p_project uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.projects p where p.id = p_project and p.manager_id is not null and p.manager_id = public.my_employee(p.company_id) and public.module_on(p.company_id, 'proj'))
$$;
create or replace function public.require_proj_of(p_project uuid) returns uuid language plpgsql stable security definer set search_path = public as $$
declare c uuid;
begin
  select company_id into c from public.projects where id = p_project;
  if c is null then raise exception 'المشروع غير موجود'; end if;
  if not (public.proj_can(c) or public.proj_mgr(p_project)) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return c;
end $$;
drop policy if exists projects_pm on public.projects;
create policy projects_pm on public.projects for select using (manager_id is not null and manager_id = public.my_employee(company_id));
do $$ declare t text;
begin
  foreach t in array array['project_tasks','project_milestones','project_members','project_risks'] loop
    execute format('drop policy if exists %I on public.%I', t || '_pm', t);
    execute format('create policy %I on public.%I for all using (public.proj_mgr(project_id)) with check (public.proj_mgr(project_id))', t || '_pm', t);
  end loop;
  foreach t in array array['project_boq','project_claims','project_change_orders','project_versions'] loop
    execute format('drop policy if exists %I on public.%I', t || '_pm', t);
    execute format('create policy %I on public.%I for select using (public.proj_mgr(project_id))', t || '_pm', t);
  end loop;
end $$;
-- names only, for the manager's screens
create or replace function public.project_people(p_company uuid) returns table(id uuid, emp_no text, full_name text, full_name_en text, end_date date)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.proj_can(p_company) or exists(select 1 from public.projects p where p.company_id = p_company and p.manager_id = public.my_employee(p_company))) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query select e.id, e.emp_no::text, e.full_name, e.full_name_en, e.end_date from public.employees e where e.company_id = p_company;
end $$;
-- the project's hours without their cost (the cost would reveal a wage)
create or replace function public.project_hours(p_project uuid) returns table(id uuid, task_id uuid, employee_id uuid, work_date date, hours numeric, billable boolean, note text,
  status text, reject_note text, invoice_id uuid, cost_entry uuid) language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_proj_of(p_project);
  return query select t.id, t.task_id, t.employee_id, t.work_date, t.hours, t.billable, t.note, t.status, t.reject_note, t.invoice_id, t.cost_entry
    from public.timesheets t where t.project_id = p_project order by t.work_date desc;
end $$;

-- ---------------- claims follow credit notes and voids ----------------
alter table public.project_claims
  add column if not exists credited numeric(14,2) not null default 0,
  add column if not exists credited_gross numeric(14,2) not null default 0,
  add column if not exists credited_recovery numeric(14,2) not null default 0,
  add column if not exists credited_retention numeric(14,2) not null default 0;
create or replace function public.claim_live(c public.project_claims) returns boolean language sql immutable as $$
  select c.status = 'approved' and (c.net <= 0 or c.credited < c.net - 0.004)
$$;
create or replace function public.claim_credit(p_claim uuid, p_amount numeric, p_date date) returns void language plpgsql security definer set search_path = public as $$
declare c public.project_claims; p public.projects; q numeric; rr numeric; g numeric; rt numeric; ao numeric; cc uuid;
begin
  select * into c from public.project_claims where id = p_claim for update;
  if c.net <= 0 or p_amount <= 0 then return; end if;
  select * into p from public.projects where id = c.project_id;
  cc := public.project_cc(p.id);
  perform public.fin3_accounts(c.company_id);
  q := least(p_amount, c.net - c.credited) / c.net;
  g := least(round(c.this_gross * q, 2), c.this_gross - c.credited_gross);
  rr := least(round(c.advance_recovery * q, 2), c.advance_recovery - c.credited_recovery);
  rt := least(round(c.retention * q, 2), c.retention - c.credited_retention);
  if c.kind = 'advance' then
    select coalesce(sum(this_gross - credited_gross) filter (where kind = 'advance'), 0) - coalesce(sum(advance_recovery - credited_recovery), 0) into ao
      from public.project_claims where project_id = c.project_id and status = 'approved';
    if g > ao + 0.004 then raise exception 'استُرد جزء من الدفعة المقدمة في المستخلصات؛ المتاح للإشعار %', ao; end if;
    perform public.post_journal(c.company_id, p_date, 'إشعار على دفعة مقدمة ' || c.no, 'project', p.id,
      jsonb_build_array(jsonb_build_object('a', '2170', 'd', g), jsonb_build_object('a', '4200', 'c', g, 'cc', cc)));
  elsif rr > 0 then
    perform public.post_journal(c.company_id, p_date, 'عكس استرداد دفعة مقدمة ' || c.no, 'project', p.id,
      jsonb_build_array(jsonb_build_object('a', '4200', 'd', rr, 'cc', cc), jsonb_build_object('a', '2170', 'c', rr)));
  end if;
  update public.project_claims set credited = least(net, credited + p_amount), credited_gross = credited_gross + g, credited_recovery = credited_recovery + rr,
    credited_retention = credited_retention + rt where id = p_claim;
end $$;
create or replace function public.credit_notes_claim() returns trigger language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if new.kind = 'sales' and new.subtotal > 0 and old.subtotal = 0 then
    select id into cid from public.project_claims where invoice_id = new.doc_id;
    if cid is not null then perform public.claim_credit(cid, new.subtotal, new.date); end if;
  end if;
  return null;
end $$;
drop trigger if exists credit_notes_claim on public.credit_notes;
create trigger credit_notes_claim after update of subtotal on public.credit_notes for each row execute function public.credit_notes_claim();
create or replace function public.sales_invoices_claim_void() returns trigger language plpgsql security definer set search_path = public as $$
declare c public.project_claims;
begin
  if new.status = 'void' and old.status <> 'void' then
    select * into c from public.project_claims where invoice_id = new.id;
    if found then perform public.claim_credit(c.id, c.net - c.credited, current_date); end if;
  end if;
  return null;
end $$;
drop trigger if exists sales_invoices_claim_void on public.sales_invoices;
create trigger sales_invoices_claim_void after update of status on public.sales_invoices for each row execute function public.sales_invoices_claim_void();

-- what was really claimed of an item (claims fully credited do not count)
create or replace function public.boq_done(p_boq uuid) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(max((l->>'qty')::numeric), 0) from public.project_claims c, jsonb_array_elements(c.lines) l where public.claim_live(c) and (l->>'boq')::uuid = p_boq
$$;
create or replace function public.project_boq_lock() returns trigger language plpgsql security definer set search_path = public as $$
declare done numeric := public.boq_done(old.id);
begin
  if done > 0 and (tg_op = 'DELETE' or new.qty < done or new.rate <> old.rate) then
    raise exception 'البند مُطالَب به في مستخلص معتمد: لا يُحذف ولا تقل كميته عن المنفذ (%) ولا يتغير سعره', done; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

-- ---------------- milestones on costs ----------------
alter table public.journal_lines add column if not exists milestone_id uuid references public.project_milestones(id) on delete set null;
create index if not exists journal_lines_ms on public.journal_lines(milestone_id) where milestone_id is not null;
alter table public.purchase_orders add column if not exists milestone_id uuid references public.project_milestones(id) on delete set null;
alter table public.petty_claims add column if not exists milestone_id uuid references public.project_milestones(id) on delete set null;
-- the milestone chosen for this transaction goes on the lines that carry the project's cost center; a reversal follows its original
create or replace function public.journal_lines_ms() returns trigger language plpgsql security definer set search_path = public as $$
declare m uuid := nullif(current_setting('waad.ms', true), '')::uuid; rv uuid;
begin
  if new.cost_center_id is null then return new; end if;
  if m is not null then new.milestone_id := m; return new; end if;
  select reverses into rv from public.journal_entries where id = new.entry_id;
  if rv is not null then
    select l.milestone_id into new.milestone_id from public.journal_lines l where l.entry_id = rv and l.account_code = new.account_code and l.cost_center_id = new.cost_center_id limit 1;
  end if;
  return new;
end $$;
drop trigger if exists journal_lines_ms on public.journal_lines;
create trigger journal_lines_ms before insert on public.journal_lines for each row execute function public.journal_lines_ms();
create or replace function public.ms_use(p_company uuid, p_cc uuid, p_ms uuid) returns uuid language plpgsql security definer set search_path = public as $$
begin
  if p_ms is not null and not exists(select 1 from public.project_milestones m join public.projects p on p.id = m.project_id
       where m.id = p_ms and p.company_id = p_company and p.cost_center_id is not distinct from p_cc) then raise exception 'المرحلة لا تتبع هذا المشروع'; end if;
  perform set_config('waad.ms', coalesce(p_ms::text, ''), true);
  return p_ms;
end $$;
-- the milestones of a project chosen by its cost center (for whoever can fill the document)
create or replace function public.cc_milestones(p_company uuid, p_cc uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.proj_can(p_company) or public.fin_can(p_company, 'purch') or public.fin_can(p_company, 'je') or public.fin_can(p_company, 'stock')) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name) order by m.sort, m.start_date) from public.project_milestones m join public.projects p on p.id = m.project_id
    where p.company_id = p_company and p.cost_center_id = p_cc), '[]');
end $$;
create or replace function public.project_milestone_costs(p_project uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_proj_of(p_project);
  return coalesce((select jsonb_object_agg(x.milestone_id, x.s) from (select l.milestone_id, sum(l.debit - l.credit) s from public.journal_lines l
     join public.project_milestones m on m.id = l.milestone_id join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
     where m.project_id = p_project and a.type = 'exp' group by 1) x), '{}');
end $$;
create or replace function public.po_save_wh(p_company uuid, p_doc jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare oid uuid; c uuid; m uuid;
begin
  perform public.wh_use(p_company, p_doc->>'warehouse');
  c := public.cc_use(p_company, p_doc->>'cost_center');
  m := public.ms_use(p_company, c, nullif(p_doc->>'milestone', '')::uuid);
  oid := public.po_save(p_company, p_doc);
  update public.purchase_orders set cost_center_id = c, milestone_id = m where id = oid;
  return oid;
end $$;
create or replace function public.petty_claim_set_project(p_id uuid, p_cc uuid, p_ms uuid) returns void language plpgsql security definer set search_path = public as $$
declare c public.petty_claims;
begin
  select * into c from public.petty_claims where id = p_id;
  if not found then raise exception 'التسوية غير موجودة'; end if;
  perform public.require_fin(c.company_id, 'je');
  if c.status <> 'pending' then raise exception 'تمت معالجة هذه التسوية'; end if;
  perform public.cc_use(c.company_id, p_cc::text); perform public.ms_use(c.company_id, p_cc, p_ms);
  update public.petty_claims set cost_center_id = p_cc, milestone_id = p_ms where id = p_id;
end $$;

-- ---------------- a week of hours at once ----------------
create or replace function public.timesheet_submit_many(p_company uuid, p_rows jsonb) returns int language plpgsql security definer set search_path = public as $$
declare x jsonb; n int := 0;
begin
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 200 then raise exception 'بيانات غير صحيحة'; end if;
  for x in select * from jsonb_array_elements(p_rows) loop
    if (x->>'date')::date > current_date then raise exception 'تاريخ العمل لا يكون في المستقبل'; end if;
    perform public.timesheet_submit(p_company, x); n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------- change orders on existing items ----------------
create or replace function public.co_save(p_project uuid, p_doc jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare p public.projects; oid uuid := nullif(p_doc->>'id', '')::uuid; o public.project_change_orders; x jsonb; b public.project_boq; its jsonb := '[]'; done numeric;
begin
  perform public.require_proj_of(p_project);
  select * into p from public.projects where id = p_project;
  if jsonb_typeof(coalesce(p_doc->'items', '[]')) <> 'array' then raise exception 'تحقق من بنود أمر التغيير'; end if;
  for x in select * from jsonb_array_elements(coalesce(p_doc->'items', '[]')) loop
    if coalesce((x->>'qty')::numeric, -1) < 0 or coalesce((x->>'rate')::numeric, -1) < 0 then raise exception 'تحقق من بنود أمر التغيير'; end if;
    if nullif(x->>'boq', '') is not null then
      select * into b from public.project_boq where id = (x->>'boq')::uuid and project_id = p_project;
      if not found then raise exception 'البند غير موجود في هذا المشروع'; end if;
      done := public.boq_done(b.id);
      if (x->>'qty')::numeric < done then raise exception 'لا تقل كمية البند «%» عن المنفذ (%)', b.description, done; end if;
      if done > 0 and (x->>'rate')::numeric <> b.rate then raise exception 'سعر البند «%» لا يتغير بعد المطالبة به؛ أضف بندا جديدا بالسعر الجديد', b.description; end if;
      its := its || jsonb_build_array(jsonb_build_object('boq', b.id, 'code', b.code, 'description', b.description, 'unit', b.unit, 'qty', (x->>'qty')::numeric, 'rate', (x->>'rate')::numeric, 'old_qty', b.qty, 'old_rate', b.rate));
    else
      if length(btrim(coalesce(x->>'description', ''))) < 2 then raise exception 'تحقق من بنود أمر التغيير'; end if;
      its := its || jsonb_build_array(x);
    end if;
  end loop;
  if oid is null then
    insert into public.project_change_orders(company_id, project_id, no, date, title, reason, value_delta, days_delta, cost_delta, items)
    values (p.company_id, p_project, public.next_doc_no(p.company_id, 'CO'), coalesce(nullif(p_doc->>'date', '')::date, current_date), btrim(p_doc->>'title'),
      nullif(btrim(p_doc->>'reason'), ''), coalesce((p_doc->>'value')::numeric, 0), coalesce((p_doc->>'days')::int, 0), coalesce((p_doc->>'cost')::numeric, 0), its) returning id into oid;
  else
    select * into o from public.project_change_orders where id = oid and project_id = p_project for update;
    if not found or o.status not in ('draft','sent','rejected') then raise exception 'لا يُعدّل أمر تغيير معتمد'; end if;
    update public.project_change_orders set title = btrim(p_doc->>'title'), reason = nullif(btrim(p_doc->>'reason'), ''), value_delta = coalesce((p_doc->>'value')::numeric, 0),
      days_delta = coalesce((p_doc->>'days')::int, 0), cost_delta = coalesce((p_doc->>'cost')::numeric, 0), items = its,
      status = 'draft', token = null, decided_by_name = null, decided_at = null, decision_note = null where id = oid;
  end if;
  return oid;
end $$;


CREATE OR REPLACE FUNCTION public.claim_figures(p_project uuid, p_kind text, p_lines jsonb, p_advance numeric, p_except uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.projects; g numeric := 0; pg numeric; ao numeric; bad text;
begin
  select * into p from public.projects where id = p_project;
  if p_kind <> 'advance' then
    select b.description into bad from jsonb_array_elements(coalesce(p_lines, '[]')) l join public.project_boq b on b.id = (l->>'boq')::uuid and b.project_id = p_project
     where (l->>'qty')::numeric > b.qty + 0.0005 limit 1;
    if bad is not null then raise exception 'الكمية المنفذة أكبر من كمية العقد في البند: %', bad; end if;
    select coalesce(sum(round((l->>'qty')::numeric * b.rate, 2)), 0) into g from jsonb_array_elements(coalesce(p_lines, '[]')) l
      join public.project_boq b on b.id = (l->>'boq')::uuid and b.project_id = p_project;
  end if;
  select coalesce(sum(this_gross - credited_gross) filter (where kind <> 'advance'), 0),
         coalesce(sum(this_gross - credited_gross) filter (where kind = 'advance'), 0) - coalesce(sum(advance_recovery - credited_recovery), 0)
    into pg, ao from public.project_claims where project_id = p_project and status = 'approved' and id is distinct from p_except;
  return public.claim_calc(jsonb_build_object('kind', p_kind, 'gross_to_date', g, 'previous_gross', pg, 'advance', p_advance, 'adv_open', ao,
           'recovery_pct', p.advance_recovery_pct, 'retention_pct', p.retention_pct, 'retention_base', p.retention_base, 'vat_rate', 15))
         || jsonb_build_object('gross_to_date', g, 'previous_gross', pg, 'adv_open', ao);
end $function$;

CREATE OR REPLACE FUNCTION public.claim_save(p_project uuid, p_doc jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.projects; cid uuid := nullif(p_doc->>'id', '')::uuid; f jsonb; k text := coalesce(p_doc->>'kind', 'interim'); c public.project_claims;
begin
  select * into p from public.projects where id = p_project;
  if not found then raise exception 'المشروع غير موجود'; end if;
  perform public.require_fin(p.company_id, 'sales');
  if p.billing <> 'claims' then raise exception 'المستخلصات للمشاريع المفوترة بالمستخلصات فقط'; end if;
  if p.party_id is null then raise exception 'حدّد عميل المشروع أولاً'; end if;
  if exists(select 1 from public.project_claims pc where pc.project_id = p_project and pc.kind = 'final' and public.claim_live(pc)) then raise exception 'صدر المستخلص الختامي للمشروع'; end if;
  if cid is not null then
    select * into c from public.project_claims where id = cid and project_id = p_project;
    if not found or c.status <> 'draft' then raise exception 'لا يُعدّل إلا المستخلص المسودة'; end if;
  end if;
  f := public.claim_figures(p_project, k, p_doc->'lines', (p_doc->>'advance')::numeric, cid);
  if cid is null then
    insert into public.project_claims(company_id, project_id, no, kind, date, period_to, lines, note)
    values (p.company_id, p_project, public.next_doc_no(p.company_id, 'IPC'), k, coalesce(nullif(p_doc->>'date', '')::date, current_date), nullif(p_doc->>'period_to', '')::date,
            case when k = 'advance' then '[]' else coalesce(p_doc->'lines', '[]') end, nullif(btrim(p_doc->>'note'), '')) returning id into cid;
  else
    update public.project_claims set kind = k, date = coalesce(nullif(p_doc->>'date', '')::date, date), period_to = nullif(p_doc->>'period_to', '')::date,
      lines = case when k = 'advance' then '[]' else coalesce(p_doc->'lines', '[]') end, note = nullif(btrim(p_doc->>'note'), '') where id = cid;
  end if;
  update public.project_claims set gross_to_date = (f->>'gross_to_date')::numeric, previous_gross = (f->>'previous_gross')::numeric, this_gross = (f->>'this_gross')::numeric,
    advance_recovery = (f->>'advance_recovery')::numeric, net = (f->>'net')::numeric, vat = (f->>'vat')::numeric, retention = (f->>'retention')::numeric,
    payable = (f->>'payable')::numeric where id = cid;
  return cid;
end $function$;

create or replace function public.project_contract(p_project uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_proj_of(p_project);
  return (select jsonb_build_object(
    'boq_total', (select coalesce(sum(round(qty * rate, 2)), 0) from public.project_boq where project_id = p_project),
    'certified', coalesce(sum(c.this_gross - c.credited_gross) filter (where c.kind <> 'advance'), 0),
    'advance', coalesce(sum(c.this_gross - c.credited_gross) filter (where c.kind = 'advance'), 0),
    'recovered', coalesce(sum(c.advance_recovery - c.credited_recovery), 0),
    'retention', coalesce(sum(c.retention - c.credited_retention) filter (where c.retention_released_on is null), 0),
    'retention_released', coalesce(sum(c.retention - c.credited_retention) filter (where c.retention_released_on is not null), 0),
    'changes', (select coalesce(sum(value_delta), 0) from public.project_change_orders where project_id = p_project and status = 'approved'),
    'guarantees', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'bank', f.bank, 'ref', f.ref, 'type', f.lg_type, 'amount', f.amount, 'expiry', f.expiry, 'status', f.status))
                            from public.bank_facilities f where f.project_id = p_project and f.kind = 'lg'), '[]'))
    from public.project_claims c right join (select 1) one on c.project_id = p_project and c.status = 'approved');
end $$;

CREATE OR REPLACE FUNCTION public.co_send(p_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.project_change_orders; t text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
begin
  select * into o from public.project_change_orders where id = p_id for update;
  if not found then raise exception 'أمر التغيير غير موجود'; end if;
  perform public.require_proj_of(o.project_id);
  if o.status = 'approved' then raise exception 'أمر التغيير معتمد'; end if;
  update public.project_change_orders set status = 'sent', token = coalesce(token, t) where id = p_id returning token into t;
  return t;
end $function$;

CREATE OR REPLACE FUNCTION public.co_apply(p_id uuid, p_ok boolean, p_name text, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.project_change_orders; p public.projects; x jsonb; n int;
begin
  select * into o from public.project_change_orders where id = p_id for update;
  if o.status not in ('draft','sent') then raise exception 'تم البت في أمر التغيير'; end if;
  if not p_ok then
    update public.project_change_orders set status = 'rejected', decided_by_name = nullif(btrim(p_name), ''), decided_at = now(), decision_note = nullif(btrim(p_note), '') where id = p_id;
    return;
  end if;
  select * into p from public.projects where id = o.project_id for update;
  insert into public.project_versions(company_id, project_id, co_id, contract_value, due_date, cost_budget, boq_total)
    values (p.company_id, p.id, o.id, p.contract_value, p.due_date, p.cost_budget, (select coalesce(sum(round(qty * rate, 2)), 0) from public.project_boq where project_id = p.id));
  update public.projects set contract_value = coalesce(contract_value, 0) + o.value_delta,
    due_date = case when due_date is not null then due_date + o.days_delta end,
    cost_budget = case when cost_budget is not null or o.cost_delta <> 0 then coalesce(cost_budget, 0) + o.cost_delta end where id = p.id;
  select coalesce(max(sort), 0) into n from public.project_boq where project_id = p.id;
  for x in select * from jsonb_array_elements(o.items) loop
    if nullif(x->>'boq', '') is not null then
      update public.project_boq set qty = (x->>'qty')::numeric, rate = (x->>'rate')::numeric where id = (x->>'boq')::uuid and project_id = p.id;
      continue;
    end if;
    n := n + 1;
    insert into public.project_boq(company_id, project_id, code, description, unit, qty, rate, sort, co_id)
    values (p.company_id, p.id, nullif(btrim(x->>'code'), ''), btrim(x->>'description'), nullif(btrim(x->>'unit'), ''), (x->>'qty')::numeric, (x->>'rate')::numeric, n, o.id);
  end loop;
  update public.project_change_orders set status = 'approved', decided_by_name = nullif(btrim(p_name), ''), decided_at = now(), decision_note = nullif(btrim(p_note), '') where id = p_id;
end $function$;

CREATE OR REPLACE FUNCTION public.project_pnl(p_company uuid)
 RETURNS TABLE(project_id uuid, contract numeric, invoiced numeric, collected numeric, revenue numeric, cost numeric, cost_budget numeric, unposted_labor numeric, hours numeric, progress jsonb, eac numeric, margin numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.module_on(p_company, 'proj') then raise exception 'هذا القسم غير مشمول في باقة منشأتك' using errcode = '42501'; end if;
  if not (public.proj_can(p_company) or exists(select 1 from public.projects x where x.company_id = p_company and x.manager_id = public.my_employee(p_company))) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query
  with b as (
    select p.id, p.cost_center_id cc, p.billing, p.contract_value, p.cost_budget, public.project_progress(p.id) pg from public.projects p where p.company_id = p_company and (public.proj_can(p_company) or p.manager_id = public.my_employee(p_company))),
  g as (
    select b.id, coalesce(sum(l.credit - l.debit) filter (where a.type = 'rev'), 0) rv, coalesce(sum(l.debit - l.credit) filter (where a.type = 'exp'), 0) ex
      from b left join public.journal_lines l on l.company_id = p_company and l.cost_center_id = b.cc
      left join public.accounts a on a.company_id = l.company_id and a.code = l.account_code group by b.id),
  s as (
    select b.id, coalesce(sum(i.subtotal), 0) inv, coalesce(sum(least(public.paid_on(i.id), i.total)), 0) col
      from b left join public.sales_invoices i on i.company_id = p_company and i.cost_center_id = b.cc and i.status = 'posted' group by b.id),
  h as (
    select b.id, coalesce(sum(t.hours), 0) hrs,
           coalesce(sum(t.hours * public.emp_hour_cost(t.employee_id, t.work_date)) filter (where t.status = 'approved' and t.cost_entry is null), 0) un
      from b left join public.timesheets t on t.project_id = b.id group by b.id)
  select b.id, case when b.billing = 'fixed' then b.contract_value else coalesce(b.contract_value, s.inv) end, s.inv, s.col, g.rv,
         round(g.ex, 2), b.cost_budget, round(h.un, 2), h.hrs, b.pg,
         -- estimate at completion: actual cost ÷ % complete, never below the actual
         case when coalesce((b.pg->>'actual')::numeric, 0) > 0 then round(greatest(g.ex + h.un, (g.ex + h.un) * 100 / (b.pg->>'actual')::numeric), 2) else b.cost_budget end,
         round(case when b.billing = 'fixed' then b.contract_value else coalesce(b.contract_value, s.inv) end
           - case when coalesce((b.pg->>'actual')::numeric, 0) > 0 then greatest(g.ex + h.un, (g.ex + h.un) * 100 / (b.pg->>'actual')::numeric) else coalesce(b.cost_budget, g.ex + h.un) end, 2)
    from b join g on g.id = b.id join s on s.id = b.id join h on h.id = b.id;
end $function$;

CREATE OR REPLACE FUNCTION public.po_bill(p_order uuid, p_doc jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.purchase_orders; l jsonb; ol public.purchase_order_lines; it public.items; q numeric; cap numeric; amt numeric; vt numeric; acc text;
  bid uuid; no text; sub numeric := 0; v_vat numeric := 0; dr jsonb := '{}'; jl jsonb := '[]'; k text; n int := 0;
  d date := coalesce((p_doc->>'date')::date, current_date); ref text := nullif(trim(p_doc->>'ref'), '');
begin
  select * into o from public.purchase_orders where id = p_order for update;
  if not found then raise exception 'الأمر غير موجود'; end if;
  perform public.require_fin(o.company_id, 'purch');
  if o.status <> 'open' then raise exception 'الأمر ليس مفتوحاً'; end if;
  perform public.cc_use(o.company_id, o.cost_center_id::text); perform public.ms_use(o.company_id, o.cost_center_id, o.milestone_id);   -- the order's project / cost center (0123)
  if d > current_date then raise exception 'تاريخ الفاتورة لا يكون في المستقبل'; end if;
  if (p_doc->>'due') is not null and (p_doc->>'due')::date < d then raise exception 'تاريخ الاستحقاق قبل تاريخ الفاتورة'; end if;
  if ref is not null and exists(select 1 from public.purchase_bills where company_id = o.company_id and party_id = o.party_id and supplier_ref = ref and status = 'posted') then
    raise exception 'رقم فاتورة المورد مسجّل مسبقاً'; end if;
  no := public.next_doc_no(o.company_id, 'BIL');
  insert into public.purchase_bills(company_id, no, supplier_ref, date, due_date, party_id, subtotal, vat, total, note, order_id, cost_center_id)
  values (o.company_id, no, ref, d, coalesce((p_doc->>'due')::date, d), o.party_id, 0, 0, 0, 'أمر شراء ' || o.no, o.id, o.cost_center_id) returning id into bid;
  for ol in select * from public.purchase_order_lines where order_id = o.id order by id for update loop
    if p_doc ? 'lines' then
      l := null; select x.value into l from jsonb_array_elements(p_doc->'lines') x where (x.value->>'line')::bigint = ol.id limit 1;
      q := case when l is null then 0 else (l->>'qty')::numeric end;
    else q := null; end if;
    it := null; if ol.item_id is not null then select * into it from public.items where id = ol.item_id; end if;
    -- three-way match: stock lines up to what was received, others up to what was ordered
    cap := case when it.type = 'stock' then ol.received - ol.billed else ol.qty - ol.billed end;
    q := coalesce(q, greatest(cap, 0));
    continue when q = 0;
    if q < 0 then raise exception 'الكمية لا تكون سالبة'; end if;
    if q > cap then raise exception '«%»: الكمية القابلة للفوترة % (%)', coalesce(it.name, ol.account_code), greatest(cap, 0),
      case when it.type = 'stock' then 'المستلم ناقص المفوتر' else 'المطلوب ناقص المفوتر' end; end if;
    amt := case when q = ol.qty then ol.amount else round(q * ol.unit_price, 2) end; vt := round(amt * ol.vat_rate / 100, 2);
    acc := case when it.type = 'stock' then '2150' when it.id is not null then '5500' else ol.account_code end;
    insert into public.purchase_bill_lines(bill_id, item_id, account_code, qty, unit_price, vat_rate, amount, vat, order_line)
    values (bid, ol.item_id, case when ol.item_id is null then ol.account_code end, q, ol.unit_price, ol.vat_rate, amt, vt, ol.id);
    update public.purchase_order_lines set billed = billed + q where id = ol.id;
    dr := jsonb_set(dr, array[acc], to_jsonb(coalesce((dr->>acc)::numeric, 0) + amt));
    sub := sub + amt; v_vat := v_vat + vt; n := n + 1;
  end loop;
  if n = 0 then raise exception 'لا يوجد ما يُفوتر — استلم البضاعة أولاً'; end if;
  update public.purchase_bills set subtotal = sub, vat = v_vat, total = sub + v_vat where id = bid;
  for k in select jsonb_object_keys(dr) loop jl := jl || jsonb_build_array(jsonb_build_object('a', k, 'd', (dr->>k)::numeric)); end loop;
  jl := jl || jsonb_build_array(jsonb_build_object('a','1400','d',v_vat), jsonb_build_object('a','2100','c',sub + v_vat));
  perform public.ensure_grni(o.company_id);
  perform public.post_journal(o.company_id, d, 'فاتورة مشتريات ' || no || ' — أمر ' || o.no, 'purchase', bid, jl);
  if not exists(select 1 from public.purchase_order_lines where order_id = o.id and billed < qty) then
    update public.purchase_orders set status = 'closed', updated_at = now() where id = o.id; end if;
  return bid;
end $function$;

CREATE OR REPLACE FUNCTION public.petty_claim_decide(p_id uuid, p_approve boolean, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c public.petty_claims; f public.petty_funds; jl jsonb; eid uuid; emp text;
begin
  select * into c from public.petty_claims where id = p_id for update;
  if not found then raise exception 'التسوية غير موجودة'; end if;
  perform public.require_fin(c.company_id, 'je');
  if c.status <> 'pending' then raise exception 'تمت معالجة هذه التسوية'; end if;
  select * into f from public.petty_funds where id = c.fund_id;
  if not p_approve then
    if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'اكتب سبب الرفض'; end if;
    update public.petty_claims set status = 'rejected', reason = trim(p_reason), decided_by = auth.uid(), decided_at = now() where id = p_id;
    return;
  end if;
  if c.total > public.petty_balance(f.id) + 0.004 then raise exception 'المصروف (%) أكبر من رصيد العهدة (%) — عزّز العهدة أولاً', c.total, public.petty_balance(f.id); end if;
  select full_name into emp from public.employees where id = f.employee_id;
  select jsonb_agg(jsonb_build_object('a', x.a, 'd', x.s)) into jl from (select l->>'a' a, sum((l->>'amount')::numeric) s from jsonb_array_elements(c.lines) l group by 1) x;
  if c.vat > 0 then jl := jl || jsonb_build_array(jsonb_build_object('a','1400','d', c.vat)); end if;
  jl := jl || jsonb_build_array(jsonb_build_object('a', f.account_code, 'c', c.total));
  perform public.cc_use(c.company_id, c.cost_center_id::text); perform public.ms_use(c.company_id, c.cost_center_id, c.milestone_id);   -- the claim's project / cost center (0123)
  eid := public.post_journal(c.company_id, c.date, 'تسوية عهدة ' || c.no || ' — ' || emp, 'petty', c.id, jl);
  update public.petty_claims set status = 'approved', entry_id = eid, decided_by = auth.uid(), decided_at = now() where id = p_id;
end $function$;

CREATE OR REPLACE FUNCTION public.stock_issue_project(p_project uuid, p_doc jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p public.projects; it public.items; st record; q numeric := (p_doc->>'qty')::numeric; v numeric; aid uuid := gen_random_uuid(); w uuid; d date := coalesce(nullif(p_doc->>'date', '')::date, current_date);
begin
  select * into p from public.projects where id = p_project;
  if not found then raise exception 'المشروع غير موجود'; end if;
  perform public.require_fin(p.company_id, 'stock');
  select * into it from public.items where id = (p_doc->>'item')::uuid and company_id = p.company_id and type = 'stock';
  if not found then raise exception 'الصنف غير موجود أو ليس مخزنياً'; end if;
  if q is null or q <= 0 then raise exception 'أدخل الكمية'; end if;
  if d > current_date then raise exception 'التاريخ لا يكون في المستقبل'; end if;
  w := public.wh_use(p.company_id, p_doc->>'warehouse');
  if public.wh_qty(it.id, w) < q then raise exception 'الكمية أكبر من الرصيد المتوفر في المستودع (%)', public.wh_qty(it.id, w); end if;
  select * into st from public.stock_state(it.id);
  v := case when st.qty = q then st.value else round(q * st.avg_cost, 2) end;
  insert into public.stock_moves(company_id, item_id, warehouse_id, date, qty, value, source, source_id, note)
  values (p.company_id, it.id, w, d, -q, -v, 'adjust', aid, 'صرف للمشروع ' || p.no || coalesce(' — ' || nullif(btrim(p_doc->>'note'), ''), ''));
  insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header)
    values (p.company_id, '5120', 'مواد مصروفة على المشاريع', 'Materials used on projects', 'exp', '5000', false) on conflict do nothing;
  perform public.ms_use(p.company_id, public.project_cc(p.id), nullif(p_doc->>'milestone', '')::uuid);
  perform public.post_journal(p.company_id, d, 'صرف مواد للمشروع ' || p.no || ' — ' || it.name, 'stock', aid,
    jsonb_build_array(jsonb_build_object('a', '5120', 'd', v, 'cc', public.project_cc(p.id)), jsonb_build_object('a', '1300', 'c', v)));
  return aid;
end $function$;

CREATE OR REPLACE FUNCTION public.push_due()
 RETURNS TABLE(user_id uuid, key text, title text, body text, url text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare u record; since timestamptz;
begin
  for u in select s.user_id, min(s.created_at) as first_at from public.push_subscriptions s group by s.user_id loop
    since := greatest(u.first_at, now() - interval '2 days');
    perform set_config('request.jwt.claim.sub', u.user_id::text, true);
    return query
    with mine as (select m.company_id, m.employee_id from public.members m where m.user_id = u.user_id and public.member_live(m.employee_id, m.role)),
    ev as (
      select 'req:' || r.id || ':' || r.step as k, 'طلب بانتظار اعتمادك' as t,
             coalesce((select e.full_name from public.employees e where e.id = r.employee_id), '') || ' — ' || public.request_kind_ar(r.kind) as b, '#/approvals' as l
        from public.requests r join mine on mine.company_id = r.company_id
       where r.status = 'pending' and coalesce(r.step_at, r.created_at) > since and public.can_act(r, r.route[r.step + 1])
      union all
      select 'dec:' || r.id, case when r.status = 'approved' then 'اعتُمد طلبك' else 'رُفض طلبك' end, public.request_kind_ar(r.kind), '#/requests'
        from public.requests r join mine on mine.employee_id = r.employee_id
       where r.status in ('approved', 'rejected') and r.decided_at > since
      union all
      select 'sig:' || s.id, 'مستند بانتظار توقيعك', s.title, '#/sign'
        from public.signature_requests s join mine on mine.employee_id = s.employee_id
       where s.status = 'pending' and s.created_at > since
      union all
      select 'note:' || n.id, 'أشار إليك زميل في ملاحظة', left(n.body, 120), '#/home'
        from public.record_notes n join mine on mine.company_id = n.company_id
       where u.user_id = any(n.mentions) and n.created_by is distinct from u.user_id and n.created_at > since
      union all
      select 'pay:' || p.id, 'صدرت قسيمة راتبك', p.month || '/' || p.year, '#/payslips'
        from public.payroll_runs p join mine on mine.company_id = p.company_id
       where p.status <> 'draft' and p.approved_at > since and mine.employee_id is not null
         and exists(select 1 from public.payroll_lines l where l.run_id = p.id and l.employee_id = mine.employee_id)
      union all
      select 'ann:' || a.id, a.title, left(a.body, 120), '#/home'
        from public.company_announcements a join mine on mine.company_id = a.company_id
       where a.created_at > since and a.created_by is distinct from u.user_id
         and (a.department_id is null or exists(select 1 from public.employees e where e.id = mine.employee_id and e.department_id = a.department_id))
      union all
      select 'srv:' || s.id, 'استبيان جديد', s.title, '#/surveys'
        from public.surveys s join mine on mine.company_id = s.company_id
       where s.status = 'open' and s.created_at > since and s.created_by is distinct from u.user_id
      union all
      select 'fb:' || f.id, 'مطلوب رأيك في تقييم 360', coalesce((select e.full_name from public.employees e where e.id = f.employee_id), ''), '#/reviews'
        from public.review_feedback f join mine on mine.employee_id = f.rater_id
       where f.submitted_at is null and f.created_at > since
      union all
      select 'ts:' || p.id || ':' || max(t.created_at)::date, 'ساعات عمل بانتظار اعتمادك', p.name || ' — ' || count(*) || ' تسجيل', '#/mytime'
        from public.timesheets t join public.projects p on p.id = t.project_id join mine on mine.employee_id = p.manager_id
       where t.status = 'submitted' and t.employee_id <> mine.employee_id and t.created_at > since group by p.id, p.name
      union all
      select 'tsr:' || t.id, 'رُفضت ساعات عمل لك', coalesce(t.reject_note, ''), '#/mytime'
        from public.timesheets t join mine on mine.employee_id = t.employee_id
       where t.status = 'rejected' and t.reviewed_at > since
      union all
      select 'inst:' || i.id, 'قسط قرض مستحق قريبا', f.bank || ' — ' || (i.principal + i.profit) || ' — ' || i.due, '#/facilities'
        from public.facility_instalments i join public.bank_facilities f on f.id = i.facility_id join mine on mine.company_id = i.company_id
       where i.paid_on is null and f.status = 'active' and i.due <= current_date + 7 and public.has_role(i.company_id, array['owner','admin','finance'])
         and i.n = (select min(x.n) from public.facility_instalments x where x.facility_id = f.id and x.paid_on is null)
      union all
      select 'lg:' || f.id || ':' || f.expiry, 'خطاب ضمان ينتهي قريبا', f.bank || coalesce(' — ' || f.beneficiary, '') || ' — ' || f.expiry, '#/facilities'
        from public.bank_facilities f join mine on mine.company_id = f.company_id
       where f.kind = 'lg' and f.status = 'active' and f.expiry <= current_date + 30 and public.has_role(f.company_id, array['owner','admin','finance']))
    select u.user_id, ev.k, ev.t, ev.b, ev.l from ev
     where not exists(select 1 from public.push_sent x where x.user_id = u.user_id and x.key = ev.k);
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);
end $function$;


revoke all on function public.proj_mgr(uuid), public.require_proj_of(uuid), public.claim_credit(uuid, numeric, date), public.credit_notes_claim(), public.sales_invoices_claim_void(),
  public.boq_done(uuid), public.claim_live(public.project_claims), public.journal_lines_ms(), public.ms_use(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.proj_mgr(uuid) to authenticated;   -- used by row policies
revoke all on function public.project_people(uuid), public.project_hours(uuid), public.cc_milestones(uuid, uuid), public.project_milestone_costs(uuid),
  public.petty_claim_set_project(uuid, uuid, uuid), public.timesheet_submit_many(uuid, jsonb) from public, anon;
grant execute on function public.project_people(uuid), public.project_hours(uuid), public.cc_milestones(uuid, uuid), public.project_milestone_costs(uuid),
  public.petty_claim_set_project(uuid, uuid, uuid), public.timesheet_submit_many(uuid, jsonb) to authenticated;
