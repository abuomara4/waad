-- Waad ERP — 0156 third free batch, larger companies (owner's request, 2026-11-26):
-- 18. month-end foreign-currency revaluation of open invoices and bills: the unrealised difference is posted (4950 gain /
--     5950 loss) on the chosen date and reversed the next day, so the payment still books the realised difference;
-- 19. allocation of shared costs: a rule moves an account's monthly cost from one cost centre (or none) to others by percent;
-- 21. custom reports: saved definitions (dataset, fields, filters, sort), run in the browser under the user's own access;
--     an optional weekly / monthly e-mail with a link to the report (never the data itself);
-- 22. webhooks: chosen events are queued and the notify job (every 10 minutes) posts them as JSON signed with HMAC-SHA256;
-- 23. financial ratios: liquidity, profitability, leverage and activity from the books.

alter table public.journal_entries drop constraint if exists journal_entries_source_check;
alter table public.journal_entries add constraint journal_entries_source_check check (source in ('manual','reversal','sales','purchase','receipt','payment',
  'stock','payroll','payroll_pay','advance','expense','opening','sales_return','purchase_return','asset','depreciation','cheque','closing','petty','trip','vehicle',
  'prepaid','bank','loan','guarantee','zakat','project','pos','production','landed','deferred','wht','fx','allocation','loyalty'));

-- ---------------- 18. FX revaluation ----------------
create table if not exists public.fx_revaluations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  date date not null,
  rates jsonb not null,
  gain numeric(14,2) not null default 0, loss numeric(14,2) not null default 0,
  details jsonb not null default '[]',
  entry_id uuid references public.journal_entries(id) on delete set null,
  reversal_id uuid references public.journal_entries(id) on delete set null,
  created_by uuid default auth.uid(), created_at timestamptz not null default now(),
  unique (company_id, date)
);
create index if not exists fx_reval_entry on public.fx_revaluations(entry_id);
create index if not exists fx_reval_rev on public.fx_revaluations(reversal_id);
alter table public.fx_revaluations enable row level security;
revoke all on public.fx_revaluations from anon, authenticated;
grant select on public.fx_revaluations to authenticated;
drop policy if exists fxr_read on public.fx_revaluations;
create policy fxr_read on public.fx_revaluations for select using (public.fin_can(company_id, 'je'));

-- what would be posted (also the preview): every open document in a foreign currency at the new rate
create or replace function public.fx_reval_preview(p_company uuid, p_date date, p_rates jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb := '[]'; x record; rate numeric; rem numeric; fxrem numeric; nw numeric;
begin
  perform public.require_fin(p_company, 'je');
  for x in select 'sales' k, i.id, i.no, i.currency, i.total, i.fx_total, i.date, (select name from public.parties where id = i.party_id) party from public.sales_invoices i
             where i.company_id = p_company and i.status = 'posted' and i.currency is not null and i.date <= p_date
           union all
           select 'purchase', b.id, b.no, b.currency, b.total, b.fx_total, b.date, (select name from public.parties where id = b.party_id) from public.purchase_bills b
             where b.company_id = p_company and b.status = 'posted' and b.currency is not null and b.date <= p_date loop
    rem := x.total - public.paid_on(x.id);
    continue when rem <= 0.009 or coalesce(x.fx_total, 0) <= 0;
    rate := coalesce(nullif(p_rates->>x.currency, '')::numeric, (select c.rate from public.currencies c where c.company_id = p_company and c.code = x.currency));
    continue when rate is null or rate <= 0;
    fxrem := round(x.fx_total * rem / x.total, 2); nw := round(fxrem * rate, 2);
    continue when abs(nw - rem) < 0.01;
    r := r || jsonb_build_array(jsonb_build_object('kind', x.k, 'id', x.id, 'no', x.no, 'party', x.party, 'currency', x.currency, 'fx', fxrem, 'carrying', rem, 'rate', rate, 'new', nw,
           'diff', case x.k when 'sales' then nw - rem else rem - nw end));   -- + = gain for the company
  end loop;
  return r;
end $$;
create or replace function public.fx_revalue(p_company uuid, p_date date, p_rates jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare det jsonb; d jsonb; lines jsonb := '[]'; g numeric := 0; l numeric := 0; ar numeric := 0; ap numeric := 0; jid uuid; rid uuid; vid uuid; rev jsonb := '[]';
begin
  perform public.require_fin(p_company, 'jepost');
  perform public.ensure_fin2_accounts(p_company);
  if p_date is null or p_date > current_date then raise exception 'تاريخ إعادة التقييم لا يكون في المستقبل'; end if;
  if exists(select 1 from public.fx_revaluations where company_id = p_company and date = p_date) then raise exception 'أُعيد التقييم في هذا التاريخ'; end if;
  det := public.fx_reval_preview(p_company, p_date, p_rates);
  if jsonb_array_length(det) = 0 then raise exception 'لا توجد فروق صرف على المستندات المفتوحة'; end if;
  for d in select * from jsonb_array_elements(det) loop
    if d->>'kind' = 'sales' then ar := ar + (d->>'diff')::numeric; else ap := ap - (d->>'diff')::numeric; end if;   -- ar: change of the receivable, ap: change of the payable
    if (d->>'diff')::numeric > 0 then g := g + (d->>'diff')::numeric; else l := l - (d->>'diff')::numeric; end if;
  end loop;
  if ar > 0 then lines := lines || jsonb_build_array(jsonb_build_object('a', '1200', 'd', ar)); elsif ar < 0 then lines := lines || jsonb_build_array(jsonb_build_object('a', '1200', 'c', -ar)); end if;
  if ap > 0 then lines := lines || jsonb_build_array(jsonb_build_object('a', '2100', 'c', ap)); elsif ap < 0 then lines := lines || jsonb_build_array(jsonb_build_object('a', '2100', 'd', -ap)); end if;
  if g > 0 then lines := lines || jsonb_build_array(jsonb_build_object('a', '4950', 'c', g)); end if;
  if l > 0 then lines := lines || jsonb_build_array(jsonb_build_object('a', '5950', 'd', l)); end if;
  vid := gen_random_uuid();
  jid := public.post_journal(p_company, p_date, 'إعادة تقييم العملات الأجنبية ' || p_date, 'fx', vid, lines);
  select coalesce(jsonb_agg(case when x ? 'd' then jsonb_build_object('a', x->>'a', 'c', x->'d') else jsonb_build_object('a', x->>'a', 'd', x->'c') end), '[]') into rev from jsonb_array_elements(lines) x;
  rid := public.post_journal(p_company, p_date + 1, 'عكس إعادة تقييم العملات ' || p_date, 'fx', vid, rev, jid);
  insert into public.fx_revaluations(id, company_id, date, rates, gain, loss, details, entry_id, reversal_id)
  values (vid, p_company, p_date, coalesce(p_rates, '{}'), g, l, det, jid, rid);
  return vid;
end $$;

-- ---------------- 19. cost allocation ----------------
create table if not exists public.alloc_rules (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null check (length(btrim(name)) between 2 and 120),
  account_code text not null,
  source_cc uuid references public.cost_centers(id) on delete set null,
  targets jsonb not null,                          -- [{cc, pct}] adding up to 100
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index if not exists alloc_rules_company on public.alloc_rules(company_id);
create index if not exists alloc_rules_cc on public.alloc_rules(source_cc);
create table if not exists public.alloc_runs (
  rule_id uuid not null references public.alloc_rules(id) on delete cascade,
  period date not null,
  amount numeric(14,2) not null,
  entry_id uuid references public.journal_entries(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (rule_id, period)
);
create index if not exists alloc_runs_entry on public.alloc_runs(entry_id);
alter table public.alloc_rules enable row level security;
alter table public.alloc_runs enable row level security;
revoke all on public.alloc_rules, public.alloc_runs from anon, authenticated;
grant select on public.alloc_rules, public.alloc_runs to authenticated;
drop policy if exists alloc_read on public.alloc_rules;
create policy alloc_read on public.alloc_rules for select using (public.fin_can(company_id, 'je'));
drop policy if exists alloc_run_read on public.alloc_runs;
create policy alloc_run_read on public.alloc_runs for select using (exists(select 1 from public.alloc_rules r where r.id = rule_id and public.fin_can(r.company_id, 'je')));
create or replace function public.alloc_rule_save(p_company uuid, p_id uuid, p_name text, p_account text, p_source uuid, p_targets jsonb, p_active boolean) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid := p_id; t jsonb; s numeric := 0;
begin
  perform public.require_fin(p_company, 'jepost');
  if not exists(select 1 from public.accounts where company_id = p_company and code = p_account and type = 'exp' and not is_header) then raise exception 'اختر حساب مصروف'; end if;
  if p_source is not null and not exists(select 1 from public.cost_centers where id = p_source and company_id = p_company) then raise exception 'مركز التكلفة ليس من المنشأة'; end if;
  if jsonb_array_length(coalesce(p_targets, '[]')) = 0 then raise exception 'أضف مراكز التوزيع'; end if;
  for t in select * from jsonb_array_elements(p_targets) loop
    if not exists(select 1 from public.cost_centers where id = (t->>'cc')::uuid and company_id = p_company) then raise exception 'مركز التكلفة ليس من المنشأة'; end if;
    if (t->>'cc')::uuid is not distinct from p_source then raise exception 'لا يوزَّع المركز على نفسه'; end if;
    if coalesce((t->>'pct')::numeric, 0) <= 0 then raise exception 'النسبة أكبر من صفر'; end if;
    s := s + (t->>'pct')::numeric;
  end loop;
  if abs(s - 100) > 0.001 then raise exception 'مجموع النسب % وليس 100', s; end if;
  if v is null then
    insert into public.alloc_rules(company_id, name, account_code, source_cc, targets, active) values (p_company, btrim(p_name), p_account, p_source, p_targets, coalesce(p_active, true)) returning id into v;
  else
    update public.alloc_rules set name = btrim(p_name), account_code = p_account, source_cc = p_source, targets = p_targets, active = coalesce(p_active, true) where id = v and company_id = p_company;
    if not found then raise exception 'القاعدة غير موجودة'; end if;
  end if;
  return v;
end $$;
-- moves the month's amount of the account (in the source centre, allocations themselves excluded) to the target centres
create or replace function public.alloc_run(p_company uuid, p_rule uuid, p_month date) returns numeric
language plpgsql security definer set search_path = public as $$
declare r public.alloc_rules; ms date := date_trunc('month', p_month)::date; me date; amt numeric; left_amt numeric; t jsonb; i int := 0; n int; sh numeric; lines jsonb; jid uuid;
begin
  perform public.require_fin(p_company, 'jepost');
  select * into r from public.alloc_rules where id = p_rule and company_id = p_company;
  if not found then raise exception 'القاعدة غير موجودة'; end if;
  if exists(select 1 from public.alloc_runs where rule_id = p_rule and period = ms) then raise exception 'وُزّع هذا الشهر'; end if;
  me := (ms + interval '1 month - 1 day')::date;
  select round(coalesce(sum(l.debit - l.credit), 0), 2) into amt from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
   where l.company_id = p_company and l.account_code = r.account_code and l.cost_center_id is not distinct from r.source_cc and e.date between ms and me and e.source <> 'allocation';
  if amt <= 0 then raise exception 'لا يوجد مبلغ لتوزيعه في هذا الشهر'; end if;
  lines := jsonb_build_array(jsonb_build_object('a', r.account_code, 'c', amt, 'cc', r.source_cc));
  n := jsonb_array_length(r.targets); left_amt := amt;
  for t in select * from jsonb_array_elements(r.targets) loop
    i := i + 1; sh := case when i = n then left_amt else round(amt * (t->>'pct')::numeric / 100, 2) end; left_amt := left_amt - sh;
    lines := lines || jsonb_build_array(jsonb_build_object('a', r.account_code, 'd', sh, 'cc', (t->>'cc')::uuid));
  end loop;
  jid := public.post_journal(p_company, me, 'توزيع ' || r.name || ' — ' || to_char(ms, 'YYYY-MM'), 'allocation', r.id, lines);
  insert into public.alloc_runs(rule_id, period, amount, entry_id) values (p_rule, ms, amt, jid);
  return amt;
end $$;

-- ---------------- 21. custom reports ----------------
create table if not exists public.report_defs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null check (length(btrim(name)) between 2 and 120),
  dataset text not null check (dataset in ('employees','sales_invoices','purchase_bills','payments','requests','items','parties','attendance')),
  fields text[] not null,
  filters jsonb not null default '{}',
  sort text,
  shared boolean not null default false,
  schedule text not null default 'none' check (schedule in ('none','weekly','monthly')),
  last_sent date,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists report_defs_company on public.report_defs(company_id);
alter table public.report_defs enable row level security;
revoke all on public.report_defs from anon;
grant select, insert, update, delete on public.report_defs to authenticated;
drop policy if exists rd_read on public.report_defs;
create policy rd_read on public.report_defs for select using (public.is_member(company_id) and (created_by = (select auth.uid()) or shared));
drop policy if exists rd_ins on public.report_defs;
create policy rd_ins on public.report_defs for insert with check (public.is_member(company_id) and created_by = (select auth.uid()));
drop policy if exists rd_upd on public.report_defs;
create policy rd_upd on public.report_defs for update using (created_by = (select auth.uid())) with check (created_by = (select auth.uid()) and public.is_member(company_id));
drop policy if exists rd_del on public.report_defs;
create policy rd_del on public.report_defs for delete using (created_by = (select auth.uid()) or public.has_role(company_id, array['owner','admin']));
-- for the notify job: scheduled reports due today (Sunday for weekly, the 1st for monthly), with the owner's mailbox
create or replace function public.report_schedules_due() returns table(id uuid, company text, name text, email text)
language sql stable security definer set search_path = public, auth as $$
  select d.id, c.name, d.name, u.email from public.report_defs d join public.companies c on c.id = d.company_id join auth.users u on u.id = d.created_by
   where d.schedule <> 'none' and u.email !~* '@(staff|admin)\.waad\.app$' and d.last_sent is distinct from public.riyadh_today()
     and ((d.schedule = 'weekly' and extract(dow from public.riyadh_today()) = 0) or (d.schedule = 'monthly' and extract(day from public.riyadh_today()) = 1))
     and exists(select 1 from public.members m where m.company_id = d.company_id and m.user_id = d.created_by)
$$;
create or replace function public.report_schedule_sent(p_id uuid) returns void language sql security definer set search_path = public as $$
  update public.report_defs set last_sent = public.riyadh_today() where id = p_id;
$$;

-- ---------------- 22. webhooks ----------------
create table if not exists public.webhook_endpoints (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  url text not null check (url ~ '^https://[^\s]{4,}$' and length(url) <= 500),
  secret text not null,
  events text[] not null,
  active boolean not null default true,
  note text,
  last_status int, last_at timestamptz, failures int not null default 0,
  created_by uuid default auth.uid(), created_at timestamptz not null default now()
);
create index if not exists webhook_endpoints_company on public.webhook_endpoints(company_id);
create table if not exists public.webhook_deliveries (
  id bigint generated always as identity primary key,
  endpoint_id uuid not null references public.webhook_endpoints(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  event text not null,
  payload jsonb not null,
  created_at timestamptz not null default now(),
  attempts int not null default 0, delivered_at timestamptz, last_status int
);
create index if not exists webhook_deliveries_pending on public.webhook_deliveries(delivered_at, attempts) where delivered_at is null;
create index if not exists webhook_deliveries_ep on public.webhook_deliveries(endpoint_id);
create index if not exists webhook_deliveries_company on public.webhook_deliveries(company_id);
-- the secret never leaves the server except once, when created; the list comes from webhook_list
alter table public.webhook_endpoints enable row level security;
alter table public.webhook_deliveries enable row level security;
revoke all on public.webhook_endpoints, public.webhook_deliveries from anon, authenticated;
create or replace function public.webhook_events() returns text[] language sql immutable as $$
  select array['invoice.posted','bill.posted','payment.recorded','employee.created','request.approved']
$$;
create or replace function public.webhook_save(p_company uuid, p_url text, p_events text[], p_note text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v uuid; s text := encode(gen_random_bytes(24), 'hex');
begin
  perform public.require_role(p_company, array['owner','admin']);
  if btrim(coalesce(p_url, '')) !~ '^https://[^\s]{4,}$' or length(p_url) > 500 then raise exception 'الرابط يبدأ بـ https://'; end if;
  if coalesce(cardinality(p_events), 0) = 0 or not (p_events <@ public.webhook_events()) then raise exception 'اختر الأحداث'; end if;
  if (select count(*) from public.webhook_endpoints where company_id = p_company and active) >= 5 then raise exception 'الحد 5 روابط مفعّلة'; end if;
  insert into public.webhook_endpoints(company_id, url, secret, events, note) values (p_company, btrim(p_url), s, p_events, nullif(btrim(p_note), '')) returning id into v;
  return jsonb_build_object('id', v, 'secret', s);
end $$;
create or replace function public.webhook_list(p_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin']);
  return coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'url', w.url, 'events', w.events, 'active', w.active, 'note', w.note, 'last_status', w.last_status, 'last_at', w.last_at, 'failures', w.failures,
      'pending', (select count(*) from public.webhook_deliveries d where d.endpoint_id = w.id and d.delivered_at is null and d.attempts < 6)) order by w.created_at)
    from public.webhook_endpoints w where w.company_id = p_company), '[]');
end $$;
create or replace function public.webhook_toggle(p_id uuid, p_active boolean, p_delete boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare c uuid;
begin
  select company_id into c from public.webhook_endpoints where id = p_id;
  if c is null then raise exception 'الرابط غير موجود'; end if;
  perform public.require_role(c, array['owner','admin']);
  if coalesce(p_delete, false) then delete from public.webhook_endpoints where id = p_id; else update public.webhook_endpoints set active = p_active, failures = 0 where id = p_id; end if;
end $$;
-- queue an event for every active endpoint of the company that subscribed to it
create or replace function public.webhook_emit(p_company uuid, p_event text, p_payload jsonb) returns void
language sql security definer set search_path = public as $$
  insert into public.webhook_deliveries(endpoint_id, company_id, event, payload)
  select w.id, p_company, p_event, jsonb_build_object('event', p_event, 'company', p_company, 'at', now(), 'data', p_payload)
    from public.webhook_endpoints w where w.company_id = p_company and w.active and p_event = any(w.events);
$$;
create or replace function public.webhook_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from public.webhook_endpoints w where w.company_id = new.company_id and w.active) then return null; end if;
  if tg_table_name = 'sales_invoices' then
    if new.status = 'posted' then perform public.webhook_emit(new.company_id, 'invoice.posted', jsonb_build_object('id', new.id, 'no', new.no, 'date', new.date, 'party', (select name from public.parties where id = new.party_id), 'subtotal', new.subtotal, 'vat', new.vat, 'total', new.total)); end if;
  elsif tg_table_name = 'purchase_bills' then
    if new.status = 'posted' then perform public.webhook_emit(new.company_id, 'bill.posted', jsonb_build_object('id', new.id, 'no', new.no, 'date', new.date, 'party', (select name from public.parties where id = new.party_id), 'total', new.total)); end if;
  elsif tg_table_name = 'payments' then
    perform public.webhook_emit(new.company_id, 'payment.recorded', jsonb_build_object('id', new.id, 'no', new.no, 'direction', new.direction, 'date', new.date, 'amount', new.amount,
      'party', (select name from public.parties where id = new.party_id), 'invoice_id', new.invoice_id, 'bill_id', new.bill_id));
  elsif tg_table_name = 'employees' then   -- work profile only (as the API): no pay, IBAN, ID or contacts
    perform public.webhook_emit(new.company_id, 'employee.created', jsonb_build_object('id', new.id, 'emp_no', new.emp_no, 'name', new.full_name, 'job', new.job_title,
      'department', (select name from public.departments where id = new.department_id), 'hire_date', new.hire_date));
  elsif tg_table_name = 'requests' then
    if new.status = 'approved' and old.status is distinct from 'approved' then perform public.webhook_emit(new.company_id, 'request.approved', jsonb_build_object('id', new.id, 'kind', new.kind, 'sub', new.sub, 'from', new.from_date, 'to', new.to_date,
      'emp_no', (select emp_no from public.employees where id = new.employee_id))); end if;
  end if;
  return null;
end $$;
drop trigger if exists webhook_si on public.sales_invoices;
create trigger webhook_si after insert on public.sales_invoices for each row execute function public.webhook_trg();
drop trigger if exists webhook_pb on public.purchase_bills;
create trigger webhook_pb after insert on public.purchase_bills for each row execute function public.webhook_trg();
drop trigger if exists webhook_pay on public.payments;
create trigger webhook_pay after insert on public.payments for each row execute function public.webhook_trg();
drop trigger if exists webhook_emp on public.employees;
create trigger webhook_emp after insert on public.employees for each row execute function public.webhook_trg();
drop trigger if exists webhook_req on public.requests;
create trigger webhook_req after update of status on public.requests for each row execute function public.webhook_trg();
-- for the notify job (service role only)
create or replace function public.webhooks_due() returns table(id bigint, url text, secret text, event text, payload jsonb)
language sql stable security definer set search_path = public as $$
  select d.id, w.url, w.secret, d.event, d.payload from public.webhook_deliveries d join public.webhook_endpoints w on w.id = d.endpoint_id
   where d.delivered_at is null and d.attempts < 6 and w.active order by d.id limit 300
$$;
create or replace function public.webhook_mark(p_id bigint, p_status int, p_ok boolean) returns void
language plpgsql security definer set search_path = public as $$
declare e uuid;
begin
  update public.webhook_deliveries set attempts = attempts + 1, last_status = p_status, delivered_at = case when p_ok then now() end where id = p_id returning endpoint_id into e;
  update public.webhook_endpoints set last_status = p_status, last_at = now(), failures = case when p_ok then 0 else failures + 1 end,
    active = case when not p_ok and failures + 1 >= 50 then false else active end where id = e;
  delete from public.webhook_deliveries where delivered_at < now() - interval '30 days';
end $$;

-- ---------------- 23. financial ratios ----------------
-- balances by account type from the books; current = assets other than fixed assets (17xx) and guarantee margins (1810),
-- liabilities other than the end-of-service provision (2500) and long-term loans (2600)
create or replace function public.fin_ratios(p_company uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare b record; rv numeric; cogs numeric; ex numeric; ca numeric; cl numeric; inv numeric; cash numeric; ar numeric; ap numeric; ta numeric; tl numeric; eq numeric; days int := greatest(p_to - p_from + 1, 1); np numeric;
begin
  perform public.require_fin(p_company, 'reports');
  select
    coalesce(sum(case when a.type = 'asset' and a.code not like '17%' and a.code <> '1810' then l.debit - l.credit end), 0),
    coalesce(sum(case when a.type = 'liab' and a.code not in ('2500','2600') then l.credit - l.debit end), 0),
    coalesce(sum(case when a.code = '1300' then l.debit - l.credit end), 0),
    coalesce(sum(case when a.parent_code = '1100' then l.debit - l.credit end), 0),
    coalesce(sum(case when a.code = '1200' then l.debit - l.credit end), 0),
    coalesce(sum(case when a.code = '2100' then l.credit - l.debit end), 0),
    coalesce(sum(case when a.type = 'asset' then l.debit - l.credit end), 0),
    coalesce(sum(case when a.type = 'liab' then l.credit - l.debit end), 0),
    coalesce(sum(case when a.type in ('equity','rev') then l.credit - l.debit when a.type = 'exp' then l.credit - l.debit end), 0)
  into ca, cl, inv, cash, ar, ap, ta, tl, eq
    from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
   where l.company_id = p_company and e.date <= p_to;
  select coalesce(sum(case when a.type = 'rev' then l.credit - l.debit end), 0), coalesce(sum(case when a.code = '5100' then l.debit - l.credit end), 0),
         coalesce(sum(case when a.type = 'exp' then l.debit - l.credit end), 0)
    into rv, cogs, ex
    from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
   where l.company_id = p_company and e.date between p_from and p_to and e.source <> 'closing';
  np := rv - ex;
  return jsonb_build_object('from', p_from, 'to', p_to, 'days', days,
    'inputs', jsonb_build_object('current_assets', ca, 'current_liabilities', cl, 'inventory', inv, 'cash', cash, 'receivables', ar, 'payables', ap,
      'total_assets', ta, 'total_liabilities', tl, 'equity', eq, 'revenue', rv, 'cogs', cogs, 'expenses', ex, 'net_profit', np),
    'current', case when cl > 0 then round(ca / cl, 2) end, 'quick', case when cl > 0 then round((ca - inv) / cl, 2) end, 'cash_ratio', case when cl > 0 then round(cash / cl, 2) end,
    'gross_margin', case when rv > 0 then round((rv - cogs) / rv * 100, 1) end, 'net_margin', case when rv > 0 then round(np / rv * 100, 1) end,
    'roa', case when ta > 0 then round(np / ta * 100, 1) end, 'roe', case when eq > 0 then round(np / eq * 100, 1) end,
    'debt_to_equity', case when eq > 0 then round(tl / eq, 2) end, 'debt_ratio', case when ta > 0 then round(tl / ta * 100, 1) end,
    'dso', case when rv > 0 then round(ar / rv * days) end, 'dpo', case when cogs > 0 then round(ap / cogs * days) end,
    'inventory_turnover', case when inv > 0 then round(cogs / inv, 2) end, 'dio', case when cogs > 0 then round(inv / cogs * days) end);
end $$;

revoke all on function public.webhook_trg(), public.webhook_emit(uuid, text, jsonb), public.webhooks_due(), public.webhook_mark(bigint, int, boolean),
  public.report_schedules_due(), public.report_schedule_sent(uuid) from public, anon, authenticated;
revoke all on function public.fx_reval_preview(uuid, date, jsonb), public.fx_revalue(uuid, date, jsonb), public.alloc_rule_save(uuid, uuid, text, text, uuid, jsonb, boolean),
  public.alloc_run(uuid, uuid, date), public.webhook_save(uuid, text, text[], text), public.webhook_list(uuid), public.webhook_toggle(uuid, boolean, boolean),
  public.webhook_events(), public.fin_ratios(uuid, date, date) from public, anon;
grant execute on function public.fx_reval_preview(uuid, date, jsonb), public.fx_revalue(uuid, date, jsonb), public.alloc_rule_save(uuid, uuid, text, text, uuid, jsonb, boolean),
  public.alloc_run(uuid, uuid, date), public.webhook_save(uuid, text, text[], text), public.webhook_list(uuid), public.webhook_toggle(uuid, boolean, boolean),
  public.webhook_events(), public.fin_ratios(uuid, date, date) to authenticated;
notify pgrst, 'reload schema';
