-- 0124 — projects, phase two (owner's projects spec, 2026-11-18): contracting
-- * Contract items (BOQ) and progress claims «المستخلصات» for projects billed by claims. VAT follows ZATCA's Guideline for the
--   Contracting Sector under VAT Provisions (Second Issue, May 2026):
--     - a down payment is invoiced (tax invoice, VAT due on receipt — §5.3 Example 5); it is held as a liability (2170), not revenue;
--     - each interim claim invoices the work done to date minus everything invoiced before, the down payment included
--       (Example 3: «Total works completed − previous payments = amount due»), so the recovered advance is not taxed twice;
--     - retention is part of the consideration: VAT is due on the whole invoice, the customer withholds the retention, and
--       no invoice or VAT arises when it is repaid (§5.2 Example 4). It stays a receivable on the invoice until collected.
--   The retention % and the advance-recovery % come from each contract (no legal rate).
-- * Change orders: value / days / cost budget / contract items, approved by the customer through a private link (anon co_view /
--   co_decide) or by the company; on approval the contract is updated and the previous version is kept (project_versions).
-- * Letters of guarantee linked to a project (bank_facilities.project_id).
-- * Risk register (probability × impact) and resource allocation by week.

alter table public.projects drop constraint if exists projects_billing_check;
alter table public.projects add constraint projects_billing_check check (billing in ('fixed','hourly','internal','claims'));
alter table public.projects
  add column if not exists retention_pct numeric(5,2) not null default 0 check (retention_pct between 0 and 100),
  add column if not exists retention_base text not null default 'excl' check (retention_base in ('excl','incl')),
  add column if not exists advance_recovery_pct numeric(5,2) not null default 0 check (advance_recovery_pct between 0 and 100);
alter table public.bank_facilities add column if not exists project_id uuid references public.projects(id) on delete set null;

-- ---------------- contract items (BOQ) ----------------
create table if not exists public.project_boq (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  code text check (code is null or length(code) <= 30),
  description text not null check (length(btrim(description)) between 2 and 300),
  unit text check (unit is null or length(unit) <= 30),
  qty numeric(14,3) not null check (qty >= 0),
  rate numeric(14,2) not null check (rate >= 0),
  sort int not null default 0,
  co_id uuid,                                  -- added by a change order
  created_at timestamptz not null default now()
);
create index if not exists project_boq_p on public.project_boq(project_id, sort);

-- ---------------- progress claims ----------------
create table if not exists public.project_claims (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  no text not null,
  kind text not null check (kind in ('advance','interim','final')),
  date date not null default current_date,
  period_to date,
  lines jsonb not null default '[]',            -- [{boq, qty}] cumulative quantity done to date
  gross_to_date numeric(14,2) not null default 0,
  previous_gross numeric(14,2) not null default 0,
  this_gross numeric(14,2) not null default 0,  -- work value of this claim (or the down payment)
  advance_recovery numeric(14,2) not null default 0,
  net numeric(14,2) not null default 0,         -- invoiced value before VAT
  vat numeric(14,2) not null default 0,
  retention numeric(14,2) not null default 0,   -- withheld by the customer (informational: it stays on the invoice)
  payable numeric(14,2) not null default 0,     -- what the customer pays now = net + VAT − retention
  status text not null default 'draft' check (status in ('draft','approved')),
  invoice_id uuid references public.sales_invoices(id) on delete set null,
  retention_released_on date,
  note text check (note is null or length(note) <= 300),
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  approved_by uuid, approved_at timestamptz,
  unique (company_id, no)
);
create index if not exists project_claims_p on public.project_claims(project_id, date);

-- ---------------- change orders and contract versions ----------------
create table if not exists public.project_change_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  no text not null,
  date date not null default current_date,
  title text not null check (length(btrim(title)) between 3 and 200),
  reason text check (reason is null or length(reason) <= 1000),
  value_delta numeric(14,2) not null default 0,
  days_delta int not null default 0 check (days_delta between -3650 and 3650),
  cost_delta numeric(14,2) not null default 0,
  items jsonb not null default '[]',            -- new contract items [{code, description, unit, qty, rate}]
  status text not null default 'draft' check (status in ('draft','sent','approved','rejected')),
  token text unique,
  decided_by_name text check (decided_by_name is null or length(decided_by_name) <= 120),
  decided_at timestamptz,
  decision_note text check (decision_note is null or length(decision_note) <= 500),
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  unique (company_id, no)
);
create table if not exists public.project_versions (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  co_id uuid references public.project_change_orders(id) on delete set null,
  at timestamptz not null default now(),
  contract_value numeric(14,2), due_date date, cost_budget numeric(14,2),
  boq_total numeric(14,2)
);

-- ---------------- risks ----------------
create table if not exists public.project_risks (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  title text not null check (length(btrim(title)) between 3 and 200),
  probability int not null check (probability between 1 and 5),
  impact int not null check (impact between 1 and 5),
  owner_id uuid references public.employees(id) on delete set null,
  mitigation text check (mitigation is null or length(mitigation) <= 1000),
  status text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now()
);

create or replace function public.project_part2_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from public.projects where id = new.project_id and company_id = new.company_id) then raise exception 'المشروع غير موجود'; end if;
  if tg_table_name = 'project_risks' then   -- kept inside the branch so the other table's trigger never compiles owner_id
    if new.owner_id is not null and not exists(select 1 from public.employees where id = new.owner_id and company_id = new.company_id) then
      raise exception 'الموظف غير موجود'; end if;
  end if;
  return new;
end $$;
do $$ declare t text;
begin
  foreach t in array array['project_boq','project_risks'] loop
    execute format('drop trigger if exists %I on public.%I', t || '_guard', t);
    execute format('create trigger %I before insert or update on public.%I for each row execute function public.project_part2_guard()', t || '_guard', t);
  end loop;
  -- read: whoever runs projects; write: boq and risks directly, claims / change orders only through the functions below
  foreach t in array array['project_boq','project_risks','project_claims','project_change_orders','project_versions'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_read', t);
    execute format('create policy %I on public.%I for select using (public.proj_can(company_id))', t || '_read', t);
    execute format('drop policy if exists proj_module on public.%I', t);
    execute format('create policy proj_module on public.%I as restrictive for all using (public.module_on(company_id, %L)) with check (public.module_on(company_id, %L))', t, 'proj', 'proj');
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
  foreach t in array array['project_boq','project_risks'] loop
    execute format('drop policy if exists %I on public.%I', t || '_write', t);
    execute format('create policy %I on public.%I for all using (public.proj_can(company_id)) with check (public.proj_can(company_id))', t || '_write', t);
    execute format('grant insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;
-- a contract item already claimed is not removed or cut below what was claimed
create or replace function public.project_boq_lock() returns trigger language plpgsql security definer set search_path = public as $$
declare done numeric;
begin
  select coalesce(max((l->>'qty')::numeric), 0) into done from public.project_claims c, jsonb_array_elements(c.lines) l
   where c.project_id = old.project_id and c.status = 'approved' and (l->>'boq')::uuid = old.id;
  if done > 0 and (tg_op = 'DELETE' or new.qty < done or new.rate <> old.rate) then
    raise exception 'البند مُطالَب به في مستخلص معتمد: لا يُحذف ولا تُخفض كميته أو سعره (استخدم أمر تغيير)'; end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
drop trigger if exists project_boq_lock on public.project_boq;
create trigger project_boq_lock before update or delete on public.project_boq for each row execute function public.project_boq_lock();

create or replace function public.fin3_accounts(p_company uuid) returns void language sql security definer set search_path = public as $$
  insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header) values
    (p_company, '2170', 'دفعات مقدمة من العملاء (مشاريع)', 'Customer advances (projects)', 'liab', '2000', false)
  on conflict do nothing
$$;

-- ---------------- claim calculation (pure, tested) ----------------
-- p = {gross_to_date, previous_gross, kind, advance (amount for an advance claim), adv_open (down payments not yet recovered),
--      recovery_pct, retention_pct, retention_base, vat_rate}
create or replace function public.claim_calc(p jsonb) returns jsonb language plpgsql immutable as $$
declare k text := p->>'kind'; g numeric := coalesce((p->>'gross_to_date')::numeric, 0); pg numeric := coalesce((p->>'previous_gross')::numeric, 0);
  vr numeric := coalesce((p->>'vat_rate')::numeric, 15); this numeric; rec numeric := 0; net numeric; vat numeric; ret numeric;
  ao numeric := greatest(coalesce((p->>'adv_open')::numeric, 0), 0);
begin
  if k = 'advance' then
    this := round(coalesce((p->>'advance')::numeric, 0), 2);
    if this <= 0 then raise exception 'أدخل مبلغ الدفعة المقدمة'; end if;
    net := this; vat := round(net * vr / 100, 2);
    return jsonb_build_object('this_gross', this, 'advance_recovery', 0, 'net', net, 'vat', vat, 'retention', 0, 'payable', net + vat);
  end if;
  this := round(g - pg, 2);
  if this < 0 then raise exception 'الأعمال المنفذة حتى تاريخه أقل من المستخلصات السابقة'; end if;
  rec := case when k = 'final' then ao else least(ao, round(this * coalesce((p->>'recovery_pct')::numeric, 0) / 100, 2)) end;
  rec := least(rec, this);
  net := this - rec;                                   -- invoiced = work this period − the down payment already invoiced (Example 3)
  vat := round(net * vr / 100, 2);
  ret := round((case when p->>'retention_base' = 'incl' then net + vat else net end) * coalesce((p->>'retention_pct')::numeric, 0) / 100, 2);
  return jsonb_build_object('this_gross', this, 'advance_recovery', rec, 'net', net, 'vat', vat, 'retention', ret, 'payable', net + vat - ret);
end $$;

-- the claim's figures from the project's contract items and earlier claims
create or replace function public.claim_figures(p_project uuid, p_kind text, p_lines jsonb, p_advance numeric, p_except uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
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
  select coalesce(max(gross_to_date) filter (where kind <> 'advance'), 0),
         coalesce(sum(this_gross) filter (where kind = 'advance'), 0) - coalesce(sum(advance_recovery), 0)
    into pg, ao from public.project_claims where project_id = p_project and status = 'approved' and id is distinct from p_except;
  return public.claim_calc(jsonb_build_object('kind', p_kind, 'gross_to_date', g, 'previous_gross', pg, 'advance', p_advance, 'adv_open', ao,
           'recovery_pct', p.advance_recovery_pct, 'retention_pct', p.retention_pct, 'retention_base', p.retention_base, 'vat_rate', 15))
         || jsonb_build_object('gross_to_date', g, 'previous_gross', pg, 'adv_open', ao);
end $$;

-- save a draft claim; doc = {id?, kind, date, period_to, lines:[{boq, qty}], advance, note}
create or replace function public.claim_save(p_project uuid, p_doc jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare p public.projects; cid uuid := nullif(p_doc->>'id', '')::uuid; f jsonb; k text := coalesce(p_doc->>'kind', 'interim'); c public.project_claims;
begin
  select * into p from public.projects where id = p_project;
  if not found then raise exception 'المشروع غير موجود'; end if;
  perform public.require_fin(p.company_id, 'sales');
  if p.billing <> 'claims' then raise exception 'المستخلصات للمشاريع المفوترة بالمستخلصات فقط'; end if;
  if p.party_id is null then raise exception 'حدّد عميل المشروع أولاً'; end if;
  if exists(select 1 from public.project_claims where project_id = p_project and kind = 'final' and status = 'approved') then raise exception 'صدر المستخلص الختامي للمشروع'; end if;
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
end $$;

-- approve: one tax invoice (on the project's cost center) + the advance moved in/out of 2170
create or replace function public.claim_approve(p_id uuid) returns uuid language plpgsql security definer set search_path = public as $$
declare c public.project_claims; p public.projects; f jsonb; itm uuid; iid uuid; cc uuid;
begin
  select * into c from public.project_claims where id = p_id for update;
  if not found then raise exception 'المستخلص غير موجود'; end if;
  select * into p from public.projects where id = c.project_id;
  perform public.require_fin(c.company_id, 'sales');
  if c.status <> 'draft' then raise exception 'المستخلص معتمد مسبقاً'; end if;
  if c.date > current_date then raise exception 'التاريخ لا يكون في المستقبل'; end if;
  -- figures again, in case an earlier claim was approved meanwhile
  f := public.claim_figures(c.project_id, c.kind, c.lines, c.this_gross, c.id);
  update public.project_claims set gross_to_date = (f->>'gross_to_date')::numeric, previous_gross = (f->>'previous_gross')::numeric, this_gross = (f->>'this_gross')::numeric,
    advance_recovery = (f->>'advance_recovery')::numeric, net = (f->>'net')::numeric, vat = (f->>'vat')::numeric, retention = (f->>'retention')::numeric,
    payable = (f->>'payable')::numeric where id = p_id returning * into c;
  if c.this_gross <= 0 then raise exception 'لا أعمال جديدة في هذا المستخلص'; end if;
  perform public.fin3_accounts(c.company_id);
  cc := public.project_cc(p.id);
  if c.net > 0 then
    insert into public.items(company_id, code, name, type, unit) values (c.company_id, 'PRJ-CLM', 'أعمال منفذة — مستخلص مشروع', 'service', 'مستخلص') on conflict (company_id, code) do nothing;
    select id into itm from public.items where company_id = c.company_id and code = 'PRJ-CLM';
    iid := public.post_sales_invoice_wh(c.company_id, jsonb_build_object('party', p.party_id, 'date', c.date, 'cost_center', cc,
      'lines', jsonb_build_array(jsonb_build_object('item', itm, 'qty', 1, 'price', c.net, 'vat', 15)),
      'note', case c.kind when 'advance' then 'دفعة مقدمة' when 'final' then 'المستخلص الختامي' else 'مستخلص جاري' end || ' ' || c.no || ' — ' || p.no || ' ' || p.name
        || case when c.retention > 0 then ' — محتجز ضمان حسن التنفيذ ' || c.retention || ' — المطلوب سداده ' || c.payable else '' end));
  end if;
  -- the down payment is a liability until recovered; recovery recognises it as revenue
  if c.kind = 'advance' then
    perform public.post_journal(c.company_id, c.date, 'دفعة مقدمة ' || c.no || ' — ' || p.no, 'project', p.id,
      jsonb_build_array(jsonb_build_object('a', '4200', 'd', c.net, 'cc', cc), jsonb_build_object('a', '2170', 'c', c.net)));
  elsif c.advance_recovery > 0 then
    perform public.post_journal(c.company_id, c.date, 'استرداد دفعة مقدمة ' || c.no || ' — ' || p.no, 'project', p.id,
      jsonb_build_array(jsonb_build_object('a', '2170', 'd', c.advance_recovery), jsonb_build_object('a', '4200', 'c', c.advance_recovery, 'cc', cc)));
  end if;
  update public.project_claims set status = 'approved', invoice_id = iid, approved_by = auth.uid(), approved_at = now() where id = p_id;
  return iid;
end $$;
create or replace function public.claim_delete(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare c public.project_claims;
begin
  select * into c from public.project_claims where id = p_id;
  if not found then raise exception 'المستخلص غير موجود'; end if;
  perform public.require_fin(c.company_id, 'sales');
  if c.status <> 'draft' then raise exception 'المستخلص معتمد: يُعالج بإشعار دائن على فاتورته'; end if;
  delete from public.project_claims where id = p_id;
end $$;
-- the customer repaid the retention (collected as a receipt on the claim's invoice)
create or replace function public.claim_retention_released(p_id uuid, p_date date) returns void language plpgsql security definer set search_path = public as $$
declare c public.project_claims;
begin
  select * into c from public.project_claims where id = p_id;
  if not found then raise exception 'المستخلص غير موجود'; end if;
  perform public.require_fin(c.company_id, 'sales');
  if c.status <> 'approved' or c.retention <= 0 then raise exception 'لا يوجد محتجز في هذا المستخلص'; end if;
  update public.project_claims set retention_released_on = coalesce(p_date, current_date) where id = p_id;
end $$;

-- ---------------- change orders ----------------
create or replace function public.co_save(p_project uuid, p_doc jsonb) returns uuid language plpgsql security definer set search_path = public as $$
declare p public.projects; oid uuid := nullif(p_doc->>'id', '')::uuid; o public.project_change_orders;
begin
  select * into p from public.projects where id = p_project;
  if not found then raise exception 'المشروع غير موجود'; end if;
  perform public.require_proj(p.company_id);
  if jsonb_typeof(coalesce(p_doc->'items', '[]')) <> 'array' or exists(select 1 from jsonb_array_elements(coalesce(p_doc->'items', '[]')) x
       where length(btrim(coalesce(x->>'description', ''))) < 2 or coalesce((x->>'qty')::numeric, -1) < 0 or coalesce((x->>'rate')::numeric, -1) < 0) then
    raise exception 'تحقق من بنود أمر التغيير'; end if;
  if oid is null then
    insert into public.project_change_orders(company_id, project_id, no, date, title, reason, value_delta, days_delta, cost_delta, items)
    values (p.company_id, p_project, public.next_doc_no(p.company_id, 'CO'), coalesce(nullif(p_doc->>'date', '')::date, current_date), btrim(p_doc->>'title'),
      nullif(btrim(p_doc->>'reason'), ''), coalesce((p_doc->>'value')::numeric, 0), coalesce((p_doc->>'days')::int, 0), coalesce((p_doc->>'cost')::numeric, 0),
      coalesce(p_doc->'items', '[]')) returning id into oid;
  else
    select * into o from public.project_change_orders where id = oid and project_id = p_project for update;
    if not found or o.status not in ('draft','sent','rejected') then raise exception 'لا يُعدّل أمر تغيير معتمد'; end if;
    update public.project_change_orders set title = btrim(p_doc->>'title'), reason = nullif(btrim(p_doc->>'reason'), ''), value_delta = coalesce((p_doc->>'value')::numeric, 0),
      days_delta = coalesce((p_doc->>'days')::int, 0), cost_delta = coalesce((p_doc->>'cost')::numeric, 0), items = coalesce(p_doc->'items', '[]'),
      status = 'draft', token = null, decided_by_name = null, decided_at = null, decision_note = null where id = oid;
  end if;
  return oid;
end $$;
-- a private link for the customer to approve or reject
create or replace function public.co_send(p_id uuid) returns text language plpgsql security definer set search_path = public as $$
declare o public.project_change_orders; t text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
begin
  select * into o from public.project_change_orders where id = p_id for update;
  if not found then raise exception 'أمر التغيير غير موجود'; end if;
  perform public.require_proj(o.company_id);
  if o.status = 'approved' then raise exception 'أمر التغيير معتمد'; end if;
  update public.project_change_orders set status = 'sent', token = coalesce(token, t) where id = p_id returning token into t;
  return t;
end $$;
-- apply an approved change: contract value, due date, cost budget, new contract items; the version before is kept
create or replace function public.co_apply(p_id uuid, p_ok boolean, p_name text, p_note text) returns void language plpgsql security definer set search_path = public as $$
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
    n := n + 1;
    insert into public.project_boq(company_id, project_id, code, description, unit, qty, rate, sort, co_id)
    values (p.company_id, p.id, nullif(btrim(x->>'code'), ''), btrim(x->>'description'), nullif(btrim(x->>'unit'), ''), (x->>'qty')::numeric, (x->>'rate')::numeric, n, o.id);
  end loop;
  update public.project_change_orders set status = 'approved', decided_by_name = nullif(btrim(p_name), ''), decided_at = now(), decision_note = nullif(btrim(p_note), '') where id = p_id;
end $$;
-- the company records the customer's decision itself (e.g. a signed paper)
create or replace function public.co_decide_internal(p_id uuid, p_ok boolean, p_name text, p_note text) returns void language plpgsql security definer set search_path = public as $$
declare o public.project_change_orders;
begin
  select * into o from public.project_change_orders where id = p_id;
  if not found then raise exception 'أمر التغيير غير موجود'; end if;
  perform public.require_proj(o.company_id);
  if nullif(btrim(coalesce(p_name, '')), '') is null then raise exception 'اكتب اسم من اعتمد من طرف العميل'; end if;
  perform public.co_apply(p_id, p_ok, p_name, p_note);
end $$;
-- anon: the customer's private link
create or replace function public.co_view(p_token text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare o public.project_change_orders; p public.projects;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return null; end if;
  select * into o from public.project_change_orders where token = p_token;
  if not found then return null; end if;
  select * into p from public.projects where id = o.project_id;
  return jsonb_build_object('company', (select name from public.companies where id = o.company_id), 'project', p.name, 'project_no', p.no,
    'customer', (select name from public.parties where id = p.party_id), 'no', o.no, 'date', o.date, 'title', o.title, 'reason', o.reason,
    'value', o.value_delta, 'days', o.days_delta, 'items', o.items, 'status', o.status, 'decided_by', o.decided_by_name, 'decided_at', o.decided_at,
    'contract_before', p.contract_value, 'due_before', p.due_date);
end $$;
create or replace function public.co_decide(p_token text, p_ok boolean, p_name text, p_note text) returns text language plpgsql security definer set search_path = public as $$
declare o public.project_change_orders;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then raise exception 'رابط غير صحيح'; end if;
  select * into o from public.project_change_orders where token = p_token;
  if not found then raise exception 'رابط غير صحيح'; end if;
  if o.status <> 'sent' then raise exception 'تم البت في أمر التغيير'; end if;
  if length(btrim(coalesce(p_name, ''))) < 3 then raise exception 'اكتب اسمك'; end if;
  perform public.co_apply(o.id, p_ok, left(btrim(p_name), 120), left(p_note, 500));
  return case when p_ok then 'approved' else 'rejected' end;
end $$;

-- ---------------- resources: allocation by week (active projects, team members with an allocation) ----------------
create or replace function public.resource_load(p_company uuid, p_weeks int) returns table(employee_id uuid, week date, alloc int, projects jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_proj(p_company);
  return query
  with w as (select (date_trunc('week', current_date) + make_interval(weeks => g))::date wk from generate_series(0, least(greatest(coalesce(p_weeks, 8), 1), 26) - 1) g)
  select m.employee_id, w.wk, sum(m.alloc)::int, jsonb_agg(jsonb_build_object('no', p.no, 'name', p.name, 'alloc', m.alloc) order by p.no)
    from w join public.project_members m on m.company_id = p_company and m.alloc is not null
    join public.projects p on p.id = m.project_id and p.status = 'active'
     and coalesce(p.start_date, '-infinity'::date) <= w.wk + 6 and coalesce(p.due_date, 'infinity'::date) >= w.wk
   group by m.employee_id, w.wk;
end $$;

-- ---------------- guarantees per project ----------------
create or replace function public.lg_set_project(p_id uuid, p_project uuid) returns void language plpgsql security definer set search_path = public as $$
declare f public.bank_facilities;
begin
  select * into f from public.bank_facilities where id = p_id;
  if not found then raise exception 'الخطاب غير موجود'; end if;
  perform public.require_fin(f.company_id, 'jepost');
  if p_project is not null and not exists(select 1 from public.projects where id = p_project and company_id = f.company_id) then raise exception 'المشروع غير موجود'; end if;
  update public.bank_facilities set project_id = p_project where id = p_id;
end $$;

-- ---------------- project summary for contracting ----------------
create or replace function public.project_contract(p_project uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare p public.projects;
begin
  select * into p from public.projects where id = p_project;
  if not found then return null; end if;
  perform public.require_proj(p.company_id);
  return jsonb_build_object(
    'boq_total', (select coalesce(sum(round(qty * rate, 2)), 0) from public.project_boq where project_id = p_project),
    'certified', (select coalesce(max(gross_to_date) filter (where kind <> 'advance'), 0) from public.project_claims where project_id = p_project and status = 'approved'),
    'advance', (select coalesce(sum(this_gross) filter (where kind = 'advance'), 0) from public.project_claims where project_id = p_project and status = 'approved'),
    'recovered', (select coalesce(sum(advance_recovery), 0) from public.project_claims where project_id = p_project and status = 'approved'),
    'retention', (select coalesce(sum(retention) filter (where retention_released_on is null), 0) from public.project_claims where project_id = p_project and status = 'approved'),
    'retention_released', (select coalesce(sum(retention) filter (where retention_released_on is not null), 0) from public.project_claims where project_id = p_project and status = 'approved'),
    'changes', (select coalesce(sum(value_delta), 0) from public.project_change_orders where project_id = p_project and status = 'approved'),
    'guarantees', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'bank', f.bank, 'ref', f.ref, 'type', f.lg_type, 'amount', f.amount, 'expiry', f.expiry, 'status', f.status))
                            from public.bank_facilities f where f.project_id = p_project and f.kind = 'lg'), '[]'));
end $$;

revoke all on function public.project_part2_guard(), public.project_boq_lock(), public.fin3_accounts(uuid), public.co_apply(uuid, boolean, text, text) from public, anon, authenticated;
revoke all on function public.claim_calc(jsonb), public.claim_figures(uuid, text, jsonb, numeric, uuid), public.claim_save(uuid, jsonb), public.claim_approve(uuid),
  public.claim_delete(uuid), public.claim_retention_released(uuid, date), public.co_save(uuid, jsonb), public.co_send(uuid), public.co_decide_internal(uuid, boolean, text, text),
  public.co_view(text), public.co_decide(text, boolean, text, text), public.resource_load(uuid, int), public.lg_set_project(uuid, uuid), public.project_contract(uuid) from public, anon;
grant execute on function public.claim_calc(jsonb), public.claim_save(uuid, jsonb), public.claim_approve(uuid), public.claim_delete(uuid), public.claim_retention_released(uuid, date),
  public.co_save(uuid, jsonb), public.co_send(uuid), public.co_decide_internal(uuid, boolean, text, text), public.resource_load(uuid, int), public.lg_set_project(uuid, uuid),
  public.project_contract(uuid) to authenticated;
grant execute on function public.co_view(text), public.co_decide(text, boolean, text, text) to anon, authenticated;
