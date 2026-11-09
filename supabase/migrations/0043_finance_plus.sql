-- Finance additions: period closing, bank reconciliation, fixed assets & monthly depreciation, cost centers,
-- budgets vs actual, and the cash-flow statement (direct method).
--  * Closing a period locks every journal entry and stock move dated on or before the lock date. Only the owner can
--    reopen, with a reason; every close/reopen is logged.
--  * Bank reconciliation ticks ledger lines of a cash/bank account against the bank statement; it finishes only when
--    the cleared balance equals the statement balance. Cleared lines stay cleared.
--  * Fixed assets depreciate straight-line monthly (cost − salvage) ÷ life; one run per month, in order, posting
--    Dr 5700 depreciation / Cr 1790 accumulated depreciation. Disposal books the gain (4900) or loss (5900).
--  * Cost centers tag revenue and expense lines (manual entries per line; sales invoices and bills per document).
--  * The cash-flow statement classifies every cash movement by its counter-account: operating / investing / financing.

alter table public.journal_entries drop constraint journal_entries_source_check;
alter table public.journal_entries add constraint journal_entries_source_check check (source in
  ('manual','reversal','sales','purchase','receipt','payment','stock','payroll','payroll_pay','advance','expense','opening','sales_return','purchase_return','asset','depreciation'));

-- ---------- period closing ----------
alter table public.companies add column books_closed_through date;
create table public.period_locks (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  action text not null check (action in ('close','reopen')),
  through date,
  previous date,
  reason text,
  by_user uuid default auth.uid(),
  at timestamptz not null default now()
);
create or replace function public.period_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare lk date;
begin
  select books_closed_through into lk from public.companies where id = new.company_id;
  if lk is not null and new.date <= lk then raise exception 'الفترة مقفلة حتى % — لا تُسجل حركات بتاريخ قبلها', lk; end if;
  return new;
end $$;
create trigger je_period_guard before insert on public.journal_entries for each row execute function public.period_guard();
create trigger sm_period_guard before insert on public.stock_moves for each row execute function public.period_guard();

create or replace function public.period_close(p_company uuid, p_through date) returns void
language plpgsql security definer set search_path = public as $$
declare lk date;
begin
  perform public.require_role(p_company, array['owner','admin','finance']);
  select books_closed_through into lk from public.companies where id = p_company;
  if p_through is null or p_through >= current_date then raise exception 'تاريخ الإقفال قبل اليوم'; end if;
  if lk is not null and p_through <= lk then raise exception 'الفترة مقفلة حتى % — اختر تاريخاً بعده', lk; end if;
  update public.companies set books_closed_through = p_through where id = p_company;
  insert into public.period_locks(company_id, action, through, previous) values (p_company, 'close', p_through, lk);
end $$;

create or replace function public.period_reopen(p_company uuid, p_through date, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare lk date;
begin
  perform public.require_role(p_company, array['owner']);
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'اكتب سبب إعادة الفتح'; end if;
  select books_closed_through into lk from public.companies where id = p_company;
  if lk is null then raise exception 'لا توجد فترة مقفلة'; end if;
  if p_through is not null and p_through >= lk then raise exception 'تاريخ الإقفال الجديد قبل الحالي (%)', lk; end if;
  update public.companies set books_closed_through = p_through where id = p_company;
  insert into public.period_locks(company_id, action, through, previous, reason) values (p_company, 'reopen', p_through, lk, trim(p_reason));
end $$;

-- ---------- cost centers ----------
create table public.cost_centers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null check (code ~ '^[A-Za-z0-9_-]{1,12}$'),
  name text not null check (length(trim(name)) >= 2),
  name_en text,
  active boolean not null default true,
  unique (company_id, code)
);
alter table public.journal_lines add column cost_center_id uuid references public.cost_centers(id);
alter table public.sales_invoices add column cost_center_id uuid references public.cost_centers(id);
alter table public.purchase_bills add column cost_center_id uuid references public.cost_centers(id);
create index on public.journal_lines(cost_center_id) where cost_center_id is not null;

create or replace function public.cc_save(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid := nullif(p_doc->>'id', '')::uuid;
begin
  perform public.require_fin(p_company, 'coa');
  if cid is null then
    insert into public.cost_centers(company_id, code, name, name_en) values (p_company, upper(trim(p_doc->>'code')), trim(p_doc->>'name'), nullif(trim(p_doc->>'name_en'), '')) returning id into cid;
  else
    update public.cost_centers set code = upper(trim(p_doc->>'code')), name = trim(p_doc->>'name'), name_en = nullif(trim(p_doc->>'name_en'), ''),
      active = coalesce((p_doc->>'active')::boolean, true) where id = cid and company_id = p_company;
    if not found then raise exception 'مركز التكلفة غير موجود'; end if;
  end if;
  return cid;
exception when unique_violation then raise exception 'رمز مركز التكلفة مستخدم';
end $$;

-- the posting engine: a line may carry "cc"; documents set one cost center for all their revenue/expense lines
create or replace function public.post_journal(p_company uuid, p_date date, p_memo text, p_source text, p_source_id uuid, p_lines jsonb, p_reverses uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare jid uuid; l jsonb; d numeric := 0; c numeric := 0; n int := 0; pre text; dcc uuid := nullif(current_setting('waad.cc', true), '')::uuid;
begin
  for l in select * from jsonb_array_elements(p_lines) loop
    if round(coalesce((l->>'d')::numeric,0),2) = 0 and round(coalesce((l->>'c')::numeric,0),2) = 0 then continue; end if;
    if not exists(select 1 from public.accounts where company_id = p_company and code = l->>'a' and not is_header) then
      raise exception 'الحساب % غير موجود أو رئيسي', l->>'a'; end if;
    if nullif(l->>'cc', '') is not null and not exists(select 1 from public.cost_centers where id = (l->>'cc')::uuid and company_id = p_company) then
      raise exception 'مركز التكلفة غير موجود'; end if;
    d := d + round(coalesce((l->>'d')::numeric,0),2); c := c + round(coalesce((l->>'c')::numeric,0),2); n := n + 1;
  end loop;
  if n < 2 or d <> c then raise exception 'قيد غير متوازن (مدين % / دائن %)', d, c; end if;
  if dcc is not null and not exists(select 1 from public.cost_centers where id = dcc and company_id = p_company) then dcc := null; end if;
  pre := case p_source when 'manual' then 'JV' when 'reversal' then 'RJ' when 'opening' then 'OB' else 'AJ' end;
  insert into public.journal_entries(company_id, no, date, memo, source, source_id, reverses)
  values (p_company, public.next_doc_no(p_company, pre), p_date, p_memo, p_source, p_source_id, p_reverses) returning id into jid;
  insert into public.journal_lines(entry_id, company_id, account_code, debit, credit, cost_center_id)
  select jid, p_company, x->>'a', round(coalesce((x->>'d')::numeric,0),2), round(coalesce((x->>'c')::numeric,0),2),
         coalesce(nullif(x->>'cc', '')::uuid, case when a.type in ('rev','exp') then dcc end)
  from jsonb_array_elements(p_lines) x join public.accounts a on a.company_id = p_company and a.code = x->>'a'
  where round(coalesce((x->>'d')::numeric,0),2) <> 0 or round(coalesce((x->>'c')::numeric,0),2) <> 0;
  return jid;
end $$;

create or replace function public.reverse_source(p_company uuid, p_source_id uuid, p_date date, p_memo text) returns void
language plpgsql security definer set search_path = public as $$
declare j record;
begin
  for j in select * from public.journal_entries where company_id = p_company and source_id = p_source_id and reverses is null
           and not exists(select 1 from public.journal_entries r where r.reverses = journal_entries.id) loop
    perform public.post_journal(p_company, p_date, p_memo || ' — ' || j.no, 'reversal', p_source_id,
      (select jsonb_agg(jsonb_build_object('a', account_code, 'd', credit, 'c', debit, 'cc', cost_center_id)) from public.journal_lines where entry_id = j.id), j.id);
  end loop;
end $$;

create or replace function public.reverse_journal(p_entry uuid, p_date date default current_date) returns uuid
language plpgsql security definer set search_path = public as $$
declare j public.journal_entries;
begin
  select * into j from public.journal_entries where id = p_entry;
  if not found then raise exception 'القيد غير موجود'; end if;
  perform public.require_fin(j.company_id, 'jepost');
  if j.source <> 'manual' then raise exception 'القيود الآلية تُعكس بإلغاء مستندها'; end if;
  if exists(select 1 from public.journal_entries where reverses = p_entry) then raise exception 'القيد معكوس مسبقاً'; end if;
  return public.post_journal(j.company_id, p_date, 'عكس ' || j.no || ' — ' || j.memo, 'reversal', null,
    (select jsonb_agg(jsonb_build_object('a', account_code, 'd', credit, 'c', debit, 'cc', cost_center_id)) from public.journal_lines where entry_id = p_entry), p_entry);
end $$;

-- document wrappers also carry the cost center
create or replace function public.cc_use(p_company uuid, p_cc text) returns uuid
language plpgsql security definer set search_path = public as $$
declare c uuid := nullif(p_cc, '')::uuid;
begin
  if c is not null and not exists(select 1 from public.cost_centers where id = c and company_id = p_company and active) then raise exception 'مركز التكلفة غير موجود أو موقوف'; end if;
  perform set_config('waad.cc', coalesce(c::text, ''), true);
  return c;
end $$;
create or replace function public.post_sales_invoice_wh(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare iid uuid; c uuid;
begin
  perform public.wh_use(p_company, p_doc->>'warehouse'); c := public.cc_use(p_company, p_doc->>'cost_center');
  iid := public.post_sales_invoice(p_company, p_doc);
  if c is not null then update public.sales_invoices set cost_center_id = c where id = iid; end if;
  return iid;
end $$;
create or replace function public.post_purchase_bill_wh(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare bid uuid; c uuid;
begin
  perform public.wh_use(p_company, p_doc->>'warehouse'); c := public.cc_use(p_company, p_doc->>'cost_center');
  bid := public.post_purchase_bill(p_company, p_doc);
  if c is not null then update public.purchase_bills set cost_center_id = c where id = bid; end if;
  return bid;
end $$;

-- credit notes / returns follow the original document's cost center
create or replace function public.post_credit_note_cc(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare c uuid;
begin
  if p_doc->>'kind' = 'sales' then select cost_center_id into c from public.sales_invoices where id = (p_doc->>'doc')::uuid and company_id = p_company;
  else select cost_center_id into c from public.purchase_bills where id = (p_doc->>'doc')::uuid and company_id = p_company; end if;
  perform set_config('waad.cc', coalesce(c::text, ''), true);
  return public.post_credit_note(p_company, p_doc);
end $$;

create or replace function public.cc_report(p_company uuid, p_from date, p_to date)
returns table(cost_center_id uuid, revenue numeric, expense numeric, profit numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'reports');
  return query
  select l.cost_center_id, coalesce(sum(l.credit - l.debit) filter (where a.type = 'rev'), 0)::numeric, coalesce(sum(l.debit - l.credit) filter (where a.type = 'exp'), 0)::numeric,
         (coalesce(sum(l.credit - l.debit) filter (where a.type = 'rev'), 0) - coalesce(sum(l.debit - l.credit) filter (where a.type = 'exp'), 0))::numeric
  from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
  where l.company_id = p_company and e.date between p_from and p_to and a.type in ('rev','exp')
  group by l.cost_center_id order by l.cost_center_id nulls last;
end $$;

-- ---------- budgets ----------
create table public.budgets (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  year int not null check (year between 2000 and 2100),
  account_code text not null,
  cost_center_id uuid references public.cost_centers(id),
  months numeric(14,2)[] not null check (array_length(months, 1) = 12),
  foreign key (company_id, account_code) references public.accounts(company_id, code)
);
create unique index budgets_key on public.budgets(company_id, year, account_code, coalesce(cost_center_id, '00000000-0000-0000-0000-000000000000'::uuid));

-- p_rows = [{"a": code, "m": [12 amounts]}] — replaces the budget for that year (and cost center)
create or replace function public.budget_save(p_company uuid, p_year int, p_cc uuid, p_rows jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare r jsonb; n int := 0; m numeric[];
begin
  perform public.require_fin(p_company, 'coa');
  if p_cc is not null and not exists(select 1 from public.cost_centers where id = p_cc and company_id = p_company) then raise exception 'مركز التكلفة غير موجود'; end if;
  delete from public.budgets where company_id = p_company and year = p_year and cost_center_id is not distinct from p_cc;
  for r in select * from jsonb_array_elements(coalesce(p_rows, '[]')) loop
    if not exists(select 1 from public.accounts where company_id = p_company and code = r->>'a' and not is_header and type in ('rev','exp')) then
      raise exception 'الموازنة لحسابات الإيرادات والمصروفات فقط (%)', r->>'a'; end if;
    select array_agg(round(coalesce(nullif(x, 'null')::numeric, 0), 2) order by o) into m from jsonb_array_elements_text(r->'m') with ordinality t(x, o);
    if coalesce(array_length(m, 1), 0) <> 12 then raise exception 'الموازنة 12 شهراً'; end if;
    if (select sum(v) from unnest(m) v) = 0 then continue; end if;
    insert into public.budgets(company_id, year, account_code, cost_center_id, months) values (p_company, p_year, r->>'a', p_cc, m);
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.budget_report(p_company uuid, p_year int, p_cc uuid, p_to_month int)
returns table(code text, name text, type text, budget numeric, actual numeric, variance numeric)
language plpgsql stable security definer set search_path = public as $$
declare tm int := least(greatest(coalesce(p_to_month, 12), 1), 12);
begin
  perform public.require_fin(p_company, 'reports');
  return query
  with b as (select bu.account_code, (select sum(v) from unnest(bu.months[1:tm]) v) amt from public.budgets bu
             where bu.company_id = p_company and bu.year = p_year and bu.cost_center_id is not distinct from p_cc),
       ac as (select l.account_code, sum(case when a.type = 'rev' then l.credit - l.debit else l.debit - l.credit end) amt
              from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
              where l.company_id = p_company and a.type in ('rev','exp') and e.date between make_date(p_year, 1, 1) and (make_date(p_year, tm, 1) + interval '1 month' - interval '1 day')::date
                and (p_cc is null or l.cost_center_id = p_cc) group by l.account_code)
  select a.code, a.name, a.type, coalesce(b.amt, 0)::numeric, coalesce(ac.amt, 0)::numeric,
         (case when a.type = 'rev' then coalesce(ac.amt, 0) - coalesce(b.amt, 0) else coalesce(b.amt, 0) - coalesce(ac.amt, 0) end)::numeric
  from public.accounts a left join b on b.account_code = a.code left join ac on ac.account_code = a.code
  where a.company_id = p_company and a.type in ('rev','exp') and not a.is_header and (b.amt is not null or ac.amt is not null)
  order by a.code;
end $$;

-- ---------- cash-flow statement (direct method) ----------
create or replace function public.cash_flow(p_company uuid, p_from date, p_to date)
returns table(section text, line text, amount numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'reports');
  return query
  with cash as (select a.code from public.accounts a where a.company_id = p_company and a.parent_code = '1100' and not a.is_header),
       ent as (select l.entry_id from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
               where l.company_id = p_company and e.date between p_from and p_to and l.account_code in (select code from cash) group by l.entry_id),
       oth as (select l.account_code, a.type, a.parent_code, l.credit - l.debit amt, je.source from public.journal_lines l join ent on ent.entry_id = l.entry_id join public.journal_entries je on je.id = l.entry_id
               join public.accounts a on a.company_id = l.company_id and a.code = l.account_code where l.account_code not in (select code from cash)),
       cls as (select case
                 when o.source = 'asset' or o.account_code = '1700' or o.parent_code = '1700' or o.account_code = '1790' then 'investing'
                 when o.type = 'equity' or (o.type = 'liab' and o.account_code >= '2600') then 'financing'
                 else 'operating' end sec,
               case
                 when o.account_code = '1200' then 'تحصيلات من العملاء'
                 when o.account_code = '2100' then 'مدفوعات للموردين'
                 when o.account_code in ('2300','2400','2500','5200','5210','1500') then 'الرواتب والمزايا والسلف'
                 when o.account_code in ('2200','1400') then 'ضريبة القيمة المضافة'
                 when o.source = 'asset' or o.account_code = '1700' or o.parent_code = '1700' or o.account_code = '1790' then 'شراء وبيع الأصول الثابتة'
                 when o.type = 'equity' then 'رأس المال والمسحوبات'
                 when o.type = 'liab' and o.account_code >= '2600' then 'القروض والتمويل'
                 when o.type = 'rev' then 'إيرادات نقدية أخرى'
                 when o.type = 'exp' then 'مصروفات تشغيلية'
                 else 'تشغيلية أخرى' end ln, o.amt from oth o)
  select '0open'::text, 'النقدية أول الفترة'::text, coalesce((select sum(l.debit - l.credit) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
           where l.company_id = p_company and e.date < p_from and l.account_code in (select code from cash)), 0)::numeric
  union all
  select case cls.sec when 'operating' then '1operating' when 'investing' then '2investing' else '3financing' end, cls.ln, sum(cls.amt)::numeric from cls group by cls.sec, cls.ln having sum(cls.amt) <> 0
  union all
  select '9close', 'النقدية آخر الفترة', coalesce((select sum(l.debit - l.credit) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
           where l.company_id = p_company and e.date <= p_to and l.account_code in (select code from cash)), 0)::numeric
  order by 1, 3 desc;
end $$;

-- ---------- bank reconciliation ----------
create table public.bank_recons (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  account_code text not null,
  statement_date date not null,
  statement_balance numeric(14,2) not null,
  status text not null default 'open' check (status in ('open','done')),
  note text, created_by uuid default auth.uid(), created_at timestamptz not null default now(), done_at timestamptz,
  foreign key (company_id, account_code) references public.accounts(company_id, code)
);
create table public.bank_cleared (
  line_id bigint primary key references public.journal_lines(id),
  recon_id uuid not null references public.bank_recons(id) on delete cascade,
  company_id uuid not null
);

create or replace function public.recon_start(p_company uuid, p_account text, p_date date, p_balance numeric, p_note text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare rid uuid; last date;
begin
  perform public.require_fin(p_company, 'je');
  if not exists(select 1 from public.accounts where company_id = p_company and code = p_account and parent_code = '1100' and not is_header) then raise exception 'اختر حساب بنك أو صندوق'; end if;
  if p_date is null or p_date > current_date then raise exception 'تاريخ الكشف لا يكون في المستقبل'; end if;
  if exists(select 1 from public.bank_recons where company_id = p_company and account_code = p_account and status = 'open') then raise exception 'توجد تسوية مفتوحة لهذا الحساب'; end if;
  select max(statement_date) into last from public.bank_recons where company_id = p_company and account_code = p_account and status = 'done';
  if last is not null and p_date <= last then raise exception 'آخر تسوية مكتملة بتاريخ % — اختر تاريخاً بعده', last; end if;
  insert into public.bank_recons(company_id, account_code, statement_date, statement_balance, note) values (p_company, p_account, p_date, round(p_balance, 2), nullif(trim(p_note), '')) returning id into rid;
  return rid;
end $$;

create or replace function public.recon_lines(p_id uuid)
returns table(line_id bigint, date date, entry_no text, memo text, debit numeric, credit numeric, cleared boolean)
language plpgsql stable security definer set search_path = public as $$
declare r public.bank_recons;
begin
  select * into r from public.bank_recons where id = p_id;
  if not found then raise exception 'التسوية غير موجودة'; end if;
  perform public.require_fin(r.company_id, 'je');
  return query
  select l.id, e.date, e.no, e.memo, l.debit, l.credit, bc.recon_id is not null
  from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
  left join public.bank_cleared bc on bc.line_id = l.id
  where l.company_id = r.company_id and l.account_code = r.account_code and e.date <= r.statement_date and (bc.recon_id is null or bc.recon_id = p_id)
  order by e.date, e.no, l.id;
end $$;

-- the cleared lines of this reconciliation (replaces the selection) → {cleared_balance, statement_balance, difference}
create or replace function public.recon_save(p_id uuid, p_lines bigint[]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r public.bank_recons; cb numeric;
begin
  select * into r from public.bank_recons where id = p_id for update;
  if not found then raise exception 'التسوية غير موجودة'; end if;
  perform public.require_fin(r.company_id, 'je');
  if r.status <> 'open' then raise exception 'التسوية مكتملة'; end if;
  delete from public.bank_cleared where recon_id = p_id;
  insert into public.bank_cleared(line_id, recon_id, company_id)
  select l.id, p_id, r.company_id from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
  where l.id = any(coalesce(p_lines, '{}')) and l.company_id = r.company_id and l.account_code = r.account_code and e.date <= r.statement_date
    and not exists(select 1 from public.bank_cleared x where x.line_id = l.id);
  select coalesce(sum(l.debit - l.credit), 0) into cb from public.bank_cleared bc join public.journal_lines l on l.id = bc.line_id
  where bc.company_id = r.company_id and l.account_code = r.account_code;
  return jsonb_build_object('cleared_balance', cb, 'statement_balance', r.statement_balance, 'difference', r.statement_balance - cb);
end $$;

-- balances for the reconciliation screen: prior = lines cleared by earlier reconciliations; book = ledger balance at the statement date
create or replace function public.recon_totals(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.bank_recons; pr numeric; bk numeric;
begin
  select * into r from public.bank_recons where id = p_id;
  if not found then raise exception 'التسوية غير موجودة'; end if;
  perform public.require_fin(r.company_id, 'je');
  select coalesce(sum(l.debit - l.credit), 0) into pr from public.bank_cleared bc join public.journal_lines l on l.id = bc.line_id
  where bc.company_id = r.company_id and l.account_code = r.account_code and bc.recon_id <> p_id;
  select coalesce(sum(l.debit - l.credit), 0) into bk from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
  where l.company_id = r.company_id and l.account_code = r.account_code and e.date <= r.statement_date;
  return jsonb_build_object('prior', pr, 'book', bk);
end $$;

create or replace function public.recon_finish(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.bank_recons; cb numeric;
begin
  select * into r from public.bank_recons where id = p_id for update;
  if not found then raise exception 'التسوية غير موجودة'; end if;
  perform public.require_fin(r.company_id, 'je');
  if r.status <> 'open' then raise exception 'التسوية مكتملة'; end if;
  select coalesce(sum(l.debit - l.credit), 0) into cb from public.bank_cleared bc join public.journal_lines l on l.id = bc.line_id
  where bc.company_id = r.company_id and l.account_code = r.account_code;
  if abs(cb - r.statement_balance) > 0.004 then raise exception 'الفرق % — يجب أن يساوي الرصيد المطابق رصيد الكشف', r.statement_balance - cb; end if;
  update public.bank_recons set status = 'done', done_at = now() where id = p_id;
end $$;

create or replace function public.recon_cancel(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.bank_recons;
begin
  select * into r from public.bank_recons where id = p_id for update;
  if not found then raise exception 'التسوية غير موجودة'; end if;
  perform public.require_fin(r.company_id, 'je');
  if r.status <> 'open' then raise exception 'التسوية مكتملة'; end if;
  delete from public.bank_recons where id = p_id;
end $$;

-- ---------- fixed assets ----------
create or replace function public.ensure_fa_accounts(p_company uuid) returns void
language sql security definer set search_path = public as $$
  insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header) values
    (p_company, '1790', 'مجمع إهلاك الأصول الثابتة', 'Accumulated depreciation', 'asset', '1000', false),
    (p_company, '5700', 'مصروف الإهلاك', 'Depreciation expense', 'exp', '5000', false)
  on conflict do nothing
$$;
select public.ensure_fa_accounts(id) from public.companies;

create table public.fixed_assets (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null,
  name text not null check (length(trim(name)) >= 2),
  name_en text,
  category text,
  acquire_date date not null,
  cost numeric(14,2) not null check (cost > 0),
  salvage numeric(14,2) not null default 0 check (salvage >= 0),
  life_months int not null check (life_months between 1 and 600),
  asset_account text not null default '1700',
  accum_account text not null default '1790',
  expense_account text not null default '5700',
  status text not null default 'active' check (status in ('active','disposed')),
  disposed_on date, disposal_amount numeric(14,2), note text,
  created_at timestamptz not null default now(),
  unique (company_id, code),
  check (salvage < cost)
);
create table public.asset_depreciation (
  id bigint generated always as identity primary key,
  asset_id uuid not null references public.fixed_assets(id) on delete cascade,
  company_id uuid not null,
  period date not null,
  amount numeric(14,2) not null,
  entry_id uuid references public.journal_entries(id),
  unique (asset_id, period)
);

-- p_doc = {id?, code, name, name_en, category, acquire_date, cost, salvage, life_months, asset_account, note, pay_account?}
-- pay_account (a cash/bank account) posts the purchase: Dr asset / Cr cash. Leave it empty if the purchase is already booked (e.g. a supplier bill to 1700).
create or replace function public.asset_save(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare aid uuid := nullif(p_doc->>'id', '')::uuid; a public.fixed_assets; acc text := coalesce(nullif(p_doc->>'asset_account', ''), '1700'); pay text := nullif(p_doc->>'pay_account', '');
  d date := (p_doc->>'acquire_date')::date; cst numeric := round((p_doc->>'cost')::numeric, 2);
begin
  perform public.require_fin(p_company, 'je');
  perform public.ensure_fa_accounts(p_company);
  if not exists(select 1 from public.accounts where company_id = p_company and code = acc and type = 'asset' and not is_header and (code = '1700' or parent_code = '1700')) then
    raise exception 'حساب الأصل يكون 1700 أو حساباً فرعياً تحته'; end if;
  if d is null or d > current_date then raise exception 'تاريخ الاقتناء لا يكون في المستقبل'; end if;
  if aid is null then
    insert into public.fixed_assets(company_id, code, name, name_en, category, acquire_date, cost, salvage, life_months, asset_account, note)
    values (p_company, coalesce(nullif(trim(p_doc->>'code'), ''), public.next_doc_no(p_company, 'FA')), trim(p_doc->>'name'), nullif(trim(p_doc->>'name_en'), ''), nullif(trim(p_doc->>'category'), ''),
            d, cst, round(coalesce((p_doc->>'salvage')::numeric, 0), 2), (p_doc->>'life_months')::int, acc, nullif(trim(p_doc->>'note'), ''))
    returning id into aid;
    if pay is not null then
      if not exists(select 1 from public.accounts where company_id = p_company and code = pay and parent_code = '1100' and not is_header) then raise exception 'حساب الدفع يكون صندوقاً أو بنكاً'; end if;
      perform public.post_journal(p_company, d, 'شراء أصل ثابت — ' || trim(p_doc->>'name'), 'asset', aid,
        jsonb_build_array(jsonb_build_object('a', acc, 'd', cst), jsonb_build_object('a', pay, 'c', cst)));
    end if;
  else
    select * into a from public.fixed_assets where id = aid and company_id = p_company for update;
    if not found then raise exception 'الأصل غير موجود'; end if;
    if exists(select 1 from public.asset_depreciation where asset_id = aid) and
       (a.cost <> cst or a.salvage <> round(coalesce((p_doc->>'salvage')::numeric, 0), 2) or a.life_months <> (p_doc->>'life_months')::int or a.acquire_date <> d or a.asset_account <> acc) then
      raise exception 'بدأ إهلاك الأصل — لا تُعدّل التكلفة أو العمر أو التاريخ'; end if;
    update public.fixed_assets set code = coalesce(nullif(trim(p_doc->>'code'), ''), code), name = trim(p_doc->>'name'), name_en = nullif(trim(p_doc->>'name_en'), ''),
      category = nullif(trim(p_doc->>'category'), ''), acquire_date = d, cost = cst, salvage = round(coalesce((p_doc->>'salvage')::numeric, 0), 2),
      life_months = (p_doc->>'life_months')::int, asset_account = acc, note = nullif(trim(p_doc->>'note'), '') where id = aid;
  end if;
  return aid;
exception when unique_violation then raise exception 'رمز الأصل مستخدم';
end $$;

-- straight-line monthly depreciation for one month (in order: the month after the last run)
create or replace function public.depreciation_run(p_company uuid, p_month date) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m date := date_trunc('month', p_month)::date; me date; last date; a record; amt numeric; acc numeric; tot numeric := 0; n int := 0;
  dep jsonb := '[]'; jl jsonb := '[]'; k record; eid uuid;
begin
  perform public.require_fin(p_company, 'je');
  me := (m + interval '1 month' - interval '1 day')::date;
  if m > date_trunc('month', current_date)::date then raise exception 'لا يُشغّل الإهلاك لشهر مستقبلي'; end if;
  select max(period) into last from public.asset_depreciation where company_id = p_company;
  if last is not null and m <> (last + interval '1 month')::date then raise exception 'شغّل الإهلاك بالترتيب — الشهر التالي %', to_char(last + interval '1 month', 'YYYY-MM'); end if;
  for a in select * from public.fixed_assets where company_id = p_company and status = 'active' and acquire_date <= me loop
    select coalesce(sum(amount), 0) into acc from public.asset_depreciation where asset_id = a.id;
    amt := least(round((a.cost - a.salvage) / a.life_months, 2), a.cost - a.salvage - acc);
    if amt > 0 then dep := dep || jsonb_build_object('id', a.id, 'amt', amt, 'exp', a.expense_account, 'acc', a.accum_account); tot := tot + amt; n := n + 1; end if;
  end loop;
  if n = 0 then raise exception 'لا يوجد ما يُهلك في هذا الشهر'; end if;
  for k in select x->>'exp' e, x->>'acc' c, sum((x->>'amt')::numeric) s from jsonb_array_elements(dep) x group by 1, 2 loop
    jl := jl || jsonb_build_array(jsonb_build_object('a', k.e, 'd', k.s), jsonb_build_object('a', k.c, 'c', k.s));
  end loop;
  eid := public.post_journal(p_company, me, 'إهلاك الأصول الثابتة — ' || to_char(m, 'YYYY-MM'), 'depreciation', null, jl);
  insert into public.asset_depreciation(asset_id, company_id, period, amount, entry_id)
  select (x->>'id')::uuid, p_company, m, (x->>'amt')::numeric, eid from jsonb_array_elements(dep) x;
  return jsonb_build_object('assets', n, 'total', tot, 'month', to_char(m, 'YYYY-MM'));
end $$;

create or replace function public.depreciation_undo(p_company uuid) returns text
language plpgsql security definer set search_path = public as $$
declare last date; eid uuid;
begin
  perform public.require_fin(p_company, 'je');
  select max(period) into last from public.asset_depreciation where company_id = p_company;
  if last is null then raise exception 'لا يوجد إهلاك'; end if;
  select entry_id into eid from public.asset_depreciation where company_id = p_company and period = last limit 1;
  if exists(select 1 from public.fixed_assets f join public.asset_depreciation d on d.asset_id = f.id where d.company_id = p_company and d.period = last and f.status = 'disposed') then
    raise exception 'استُبعد أصل بعد هذا الإهلاك — لا يُلغى'; end if;
  perform public.post_journal(p_company, current_date, 'إلغاء إهلاك ' || to_char(last, 'YYYY-MM'), 'reversal', null,
    (select jsonb_agg(jsonb_build_object('a', account_code, 'd', credit, 'c', debit)) from public.journal_lines where entry_id = eid), eid);
  delete from public.asset_depreciation where company_id = p_company and period = last;
  return to_char(last, 'YYYY-MM');
end $$;

-- disposal / sale: removes cost and accumulated depreciation; proceeds to cash; difference is a gain (4900) or loss (5900)
create or replace function public.asset_dispose(p_id uuid, p_date date, p_amount numeric, p_account text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a public.fixed_assets; acc numeric; bv numeric; g numeric; amt numeric := round(coalesce(p_amount, 0), 2);
begin
  select * into a from public.fixed_assets where id = p_id for update;
  if not found then raise exception 'الأصل غير موجود'; end if;
  perform public.require_fin(a.company_id, 'je');
  if a.status <> 'active' then raise exception 'الأصل مستبعد مسبقاً'; end if;
  if p_date is null or p_date > current_date or p_date < a.acquire_date then raise exception 'تاريخ الاستبعاد غير صحيح'; end if;
  if amt < 0 then raise exception 'مبلغ البيع لا يكون سالباً'; end if;
  if amt > 0 and not exists(select 1 from public.accounts where company_id = a.company_id and code = p_account and parent_code = '1100' and not is_header) then raise exception 'اختر الصندوق أو البنك المستلم'; end if;
  select coalesce(sum(amount), 0) into acc from public.asset_depreciation where asset_id = p_id;
  bv := a.cost - acc; g := amt - bv;
  perform public.post_journal(a.company_id, p_date, 'استبعاد أصل ثابت — ' || a.name, 'asset', a.id, jsonb_build_array(
    jsonb_build_object('a', a.accum_account, 'd', acc), jsonb_build_object('a', p_account, 'd', amt), jsonb_build_object('a', a.asset_account, 'c', a.cost),
    jsonb_build_object('a', '4900', 'c', greatest(g, 0)), jsonb_build_object('a', '5900', 'd', greatest(-g, 0))));
  update public.fixed_assets set status = 'disposed', disposed_on = p_date, disposal_amount = amt where id = p_id;
  return jsonb_build_object('book_value', bv, 'gain', g);
end $$;

-- ---------- RLS, audit, grants ----------
alter table public.period_locks enable row level security;
alter table public.cost_centers enable row level security;
alter table public.budgets enable row level security;
alter table public.bank_recons enable row level security;
alter table public.bank_cleared enable row level security;
alter table public.fixed_assets enable row level security;
alter table public.asset_depreciation enable row level security;
create policy pl_read on public.period_locks for select using (public.has_role(company_id, array['owner','admin','finance']));
create policy cc_read on public.cost_centers for select using (public.fin(company_id));
create policy bu_read on public.budgets for select using (public.fin_can(company_id, 'reports') or public.fin_can(company_id, 'coa'));
create policy br_read on public.bank_recons for select using (public.fin_can(company_id, 'je'));
create policy bc_read on public.bank_cleared for select using (public.fin_can(company_id, 'je'));
create policy fa_read on public.fixed_assets for select using (public.fin_can(company_id, 'je') or public.fin_can(company_id, 'reports'));
create policy ad_read on public.asset_depreciation for select using (public.fin_can(company_id, 'je') or public.fin_can(company_id, 'reports'));
create trigger audit_period_locks after insert on public.period_locks for each row execute function public.audit_trigger();
create trigger audit_cost_centers after insert or update on public.cost_centers for each row execute function public.audit_trigger();
create trigger audit_bank_recons after insert or update on public.bank_recons for each row execute function public.audit_trigger();
create trigger audit_fixed_assets after insert or update on public.fixed_assets for each row execute function public.audit_trigger();
create trigger pl_immutable before update or delete on public.period_locks for each row execute function public.block_change();

revoke all on public.period_locks, public.cost_centers, public.budgets, public.bank_recons, public.bank_cleared, public.fixed_assets, public.asset_depreciation from anon;
revoke insert, update, delete on public.period_locks, public.cost_centers, public.budgets, public.bank_recons, public.bank_cleared, public.fixed_assets, public.asset_depreciation from authenticated;
grant select on public.period_locks, public.cost_centers, public.budgets, public.bank_recons, public.bank_cleared, public.fixed_assets, public.asset_depreciation to authenticated;

revoke all on function public.period_guard(), public.period_close(uuid, date), public.period_reopen(uuid, date, text), public.cc_save(uuid, jsonb), public.cc_use(uuid, text),
  public.post_journal(uuid, date, text, text, uuid, jsonb, uuid), public.reverse_source(uuid, uuid, date, text), public.post_sales_invoice_wh(uuid, jsonb), public.post_purchase_bill_wh(uuid, jsonb), public.post_credit_note_cc(uuid, jsonb),
  public.cc_report(uuid, date, date), public.budget_save(uuid, int, uuid, jsonb), public.budget_report(uuid, int, uuid, int), public.cash_flow(uuid, date, date),
  public.recon_start(uuid, text, date, numeric, text), public.recon_lines(uuid), public.recon_totals(uuid), public.recon_save(uuid, bigint[]), public.recon_finish(uuid), public.recon_cancel(uuid),
  public.ensure_fa_accounts(uuid), public.asset_save(uuid, jsonb), public.depreciation_run(uuid, date), public.depreciation_undo(uuid), public.asset_dispose(uuid, date, numeric, text)
  from public, anon, authenticated;
grant execute on function public.period_close(uuid, date), public.period_reopen(uuid, date, text), public.cc_save(uuid, jsonb),
  public.post_sales_invoice_wh(uuid, jsonb), public.post_purchase_bill_wh(uuid, jsonb), public.post_credit_note_cc(uuid, jsonb), public.cc_report(uuid, date, date), public.budget_save(uuid, int, uuid, jsonb),
  public.budget_report(uuid, int, uuid, int), public.cash_flow(uuid, date, date), public.recon_start(uuid, text, date, numeric, text), public.recon_lines(uuid), public.recon_totals(uuid),
  public.recon_save(uuid, bigint[]), public.recon_finish(uuid), public.recon_cancel(uuid), public.asset_save(uuid, jsonb), public.depreciation_run(uuid, date),
  public.depreciation_undo(uuid), public.asset_dispose(uuid, date, numeric, text) to authenticated;
