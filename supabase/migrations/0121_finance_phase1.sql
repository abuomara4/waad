-- 0121 — finance, phase one (owner's decision, 2026-11-18)
-- 1) bank statement import + matching: the company uploads its bank statement (Excel/CSV), Waad suggests the book line with
--    the same amount within 5 days, the accountant confirms; lines that are not in the books (bank charges...) get a quick entry;
-- 2) one receipt / payment spread over several invoices of the same customer / supplier, oldest first (leftover = on account);
-- 3) prepaid expenses spread over months (e.g. a year's rent): one entry per month Dr expense / Cr 1600;
-- 4) journal drafts: saved, sent for approval, approved by someone else with the posting permission (or the owner), with
--    optional automatic reversal on a date and monthly recurrence; due reversals / recurrences post when finance opens the books;
-- 5) the month-end close checklist (drafts, bank, depreciation, prepaid, payroll, e-invoices) before period_close.
-- Petty cash already checks the supplier VAT number; its «replenish» button only tops the fund up to its ceiling (petty_topup).

alter table public.journal_entries drop constraint if exists journal_entries_source_check;
alter table public.journal_entries add constraint journal_entries_source_check check (source in ('manual','reversal','sales','purchase','receipt','payment',
  'stock','payroll','payroll_pay','advance','expense','opening','sales_return','purchase_return','asset','depreciation','cheque','closing','petty','trip','vehicle','prepaid','bank'));

-- ---------------- 1. bank statement lines ----------------
create table if not exists public.bank_lines (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  account_code text not null,
  day date not null,
  description text check (description is null or length(description) <= 300),
  ref text check (ref is null or length(ref) <= 80),
  amount numeric(14,2) not null check (amount <> 0),          -- + money in, − money out
  hash text not null,
  status text not null default 'open' check (status in ('open','matched','posted')),
  journal_line_id bigint references public.journal_lines(id) on delete set null,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  unique (company_id, hash)
);
create index if not exists bank_lines_acc on public.bank_lines(company_id, account_code, day);
create unique index if not exists bank_lines_jl on public.bank_lines(journal_line_id) where journal_line_id is not null;
alter table public.bank_lines enable row level security;
drop policy if exists bank_lines_read on public.bank_lines;
create policy bank_lines_read on public.bank_lines for select using (public.fin_can(company_id, 'je'));
revoke all on public.bank_lines from anon;
grant select on public.bank_lines to authenticated;

create or replace function public.bank_lines_import(p_company uuid, p_account text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare r jsonb; n int := 0; dup int := 0; h text; amt numeric;
begin
  perform public.require_fin(p_company, 'je');
  if not exists(select 1 from public.accounts where company_id = p_company and code = p_account and parent_code = '1100' and not is_header) then raise exception 'اختر حساب البنك'; end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 5000 then raise exception 'الكشف كبير أو غير صحيح (حتى 5,000 حركة في المرة)'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    amt := round((r->>'amount')::numeric, 2);
    if amt is null or amt = 0 or (r->>'day') is null then continue; end if;
    h := md5(p_account || '|' || (r->>'day') || '|' || amt::text || '|' || coalesce(r->>'desc', '') || '|' || coalesce(r->>'ref', '') || '|' || coalesce(r->>'seq', ''));
    insert into public.bank_lines(company_id, account_code, day, description, ref, amount, hash)
    values (p_company, p_account, (r->>'day')::date, left(nullif(btrim(r->>'desc'), ''), 300), left(nullif(btrim(r->>'ref'), ''), 80), amt, h)
    on conflict (company_id, hash) do nothing;
    if found then n := n + 1; else dup := dup + 1; end if;
  end loop;
  return jsonb_build_object('added', n, 'duplicates', dup);
end $$;

-- open statement lines of an account, each with the best book line (same amount, ±5 days, not matched yet)
create or replace function public.bank_suggest(p_company uuid, p_account text) returns table(line_id uuid, day date, description text, ref text, amount numeric,
  jl_id bigint, jl_date date, jl_memo text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'je');
  return query
  select b.id, b.day, b.description, b.ref, b.amount, m.lid, m.d, m.memo
    from public.bank_lines b
    left join lateral (select l.id lid, e.date d, e.memo from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
                        where l.company_id = p_company and l.account_code = p_account and round(l.debit - l.credit, 2) = b.amount
                          and e.date between b.day - 5 and b.day + 5
                          and not exists(select 1 from public.bank_lines x where x.journal_line_id = l.id)
                        order by abs(e.date - b.day), l.id limit 1) m on true
   where b.company_id = p_company and b.account_code = p_account and b.status = 'open' order by b.day, b.amount;
end $$;

create or replace function public.bank_match(p_lines jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare r jsonb; b public.bank_lines; l public.journal_lines; n int := 0;
begin
  for r in select * from jsonb_array_elements(p_lines) loop
    select * into b from public.bank_lines where id = (r->>'line')::uuid for update;
    if not found then continue; end if;
    perform public.require_fin(b.company_id, 'je');
    select * into l from public.journal_lines where id = (r->>'jl')::bigint;
    if l.id is null or l.company_id <> b.company_id or l.account_code <> b.account_code or round(l.debit - l.credit, 2) <> b.amount then raise exception 'القيد لا يطابق الحركة البنكية'; end if;
    if b.status <> 'open' then continue; end if;
    update public.bank_lines set status = 'matched', journal_line_id = l.id where id = b.id;
    n := n + 1;
  end loop;
  return n;
end $$;
create or replace function public.bank_unmatch(p_line uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b public.bank_lines;
begin
  select * into b from public.bank_lines where id = p_line;
  if not found then raise exception 'الحركة غير موجودة'; end if;
  perform public.require_fin(b.company_id, 'je');
  if b.status = 'posted' then raise exception 'سُجّل لهذه الحركة قيد: اعكسه من القيود اليومية'; end if;
  update public.bank_lines set status = 'open', journal_line_id = null where id = p_line;
end $$;
-- a line that is not in the books (bank charges, interest...): post it against the chosen account and match it at once
create or replace function public.bank_quick_post(p_line uuid, p_account text, p_memo text) returns uuid
language plpgsql security definer set search_path = public as $$
declare b public.bank_lines; jid uuid; lid bigint;
begin
  select * into b from public.bank_lines where id = p_line for update;
  if not found then raise exception 'الحركة غير موجودة'; end if;
  perform public.require_fin(b.company_id, 'jepost');
  if b.status <> 'open' then raise exception 'الحركة مطابقة مسبقا'; end if;
  if not exists(select 1 from public.accounts where company_id = b.company_id and code = p_account and not is_header and code <> b.account_code) then raise exception 'اختر الحساب المقابل'; end if;
  jid := public.post_journal(b.company_id, b.day, coalesce(nullif(btrim(p_memo), ''), b.description, 'حركة بنكية'), 'bank', b.id,
    case when b.amount < 0 then jsonb_build_array(jsonb_build_object('a', p_account, 'd', -b.amount), jsonb_build_object('a', b.account_code, 'c', -b.amount))
         else jsonb_build_array(jsonb_build_object('a', b.account_code, 'd', b.amount), jsonb_build_object('a', p_account, 'c', b.amount)) end);
  select id into lid from public.journal_lines where entry_id = jid and account_code = b.account_code limit 1;
  update public.bank_lines set status = 'posted', journal_line_id = lid where id = b.id;
  return jid;
end $$;

-- ---------------- 2. one payment over several invoices ----------------
-- p_doc: {direction in|out, party, amount, date, account, note, docs?: [ids] (else every open document, oldest first)}
create or replace function public.payment_allocate(p_company uuid, p_doc jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare dir text := p_doc->>'direction'; pid uuid := (p_doc->>'party')::uuid; left_ numeric := round((p_doc->>'amount')::numeric, 2);
  r record; part numeric; v_out jsonb := '[]'; vid uuid; v_only uuid[];
begin
  perform public.require_fin(p_company, case dir when 'in' then 'sales' else 'purch' end);
  if coalesce(left_, 0) <= 0 then raise exception 'أدخل مبلغا أكبر من صفر'; end if;
  if jsonb_typeof(p_doc->'docs') = 'array' and jsonb_array_length(p_doc->'docs') > 0 then v_only := array(select (x)::uuid from jsonb_array_elements_text(p_doc->'docs') x); end if;
  for r in
    select d.id, d.no, d.total - public.paid_on(d.id) due from (
      select id, no, date, total, created_at from public.sales_invoices where dir = 'in' and company_id = p_company and party_id = pid and status = 'posted'
      union all
      select id, no, date, total, created_at from public.purchase_bills where dir = 'out' and company_id = p_company and party_id = pid and status = 'posted') d
     where d.total - public.paid_on(d.id) > 0.004 and (v_only is null or d.id = any(v_only))
     order by d.date, d.created_at
  loop
    exit when left_ <= 0;
    part := least(left_, round(r.due, 2));
    vid := public.record_payment(p_company, jsonb_build_object('direction', dir, 'party', pid, 'amount', part, 'date', p_doc->>'date', 'account', p_doc->>'account', 'note', p_doc->>'note',
      case dir when 'in' then 'invoice' else 'bill' end, r.id));
    v_out := v_out || jsonb_build_object('doc', r.no, 'amount', part, 'payment', vid);
    left_ := round(left_ - part, 2);
  end loop;
  if left_ > 0 then   -- more than what is open: the rest is an advance on the account
    vid := public.record_payment(p_company, jsonb_build_object('direction', dir, 'party', pid, 'amount', left_, 'date', p_doc->>'date', 'account', p_doc->>'account', 'note', coalesce(p_doc->>'note', '') || ' — دفعة مقدمة'));
    v_out := v_out || jsonb_build_object('doc', null, 'amount', left_, 'payment', vid);
  end if;
  return v_out;
end $$;

-- ---------------- 3. prepaid expenses ----------------
create table if not exists public.prepaid_schedules (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null check (length(btrim(name)) between 2 and 120),
  prepaid_account text not null default '1600',
  expense_account text not null,
  cost_center_id uuid references public.cost_centers(id) on delete set null,
  total numeric(14,2) not null check (total > 0),
  start_month date not null check (extract(day from start_month) = 1),
  months int not null check (months between 1 and 120),
  status text not null default 'active' check (status in ('active','done','stopped')),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create table if not exists public.prepaid_postings (
  schedule_id uuid not null references public.prepaid_schedules(id) on delete cascade,
  period date not null,
  amount numeric(14,2) not null,
  entry_id uuid references public.journal_entries(id) on delete set null,
  primary key (schedule_id, period)
);
alter table public.prepaid_schedules enable row level security;
alter table public.prepaid_postings enable row level security;
drop policy if exists prepaid_read on public.prepaid_schedules;
create policy prepaid_read on public.prepaid_schedules for select using (public.fin_can(company_id, 'je'));
drop policy if exists prepaid_post_read on public.prepaid_postings;
create policy prepaid_post_read on public.prepaid_postings for select using (exists(select 1 from public.prepaid_schedules s where s.id = schedule_id and public.fin_can(s.company_id, 'je')));
revoke all on public.prepaid_schedules, public.prepaid_postings from anon;
grant select on public.prepaid_schedules, public.prepaid_postings to authenticated;

create or replace function public.prepaid_create(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare sid uuid;
begin
  perform public.require_fin(p_company, 'jepost');
  if not exists(select 1 from public.accounts where company_id = p_company and code = coalesce(p_doc->>'prepaid', '1600') and type = 'asset' and not is_header) then raise exception 'حساب المصروف المقدم غير صحيح'; end if;
  if not exists(select 1 from public.accounts where company_id = p_company and code = p_doc->>'expense' and type = 'exp' and not is_header) then raise exception 'اختر حساب المصروف'; end if;
  insert into public.prepaid_schedules(company_id, name, prepaid_account, expense_account, cost_center_id, total, start_month, months)
  values (p_company, btrim(p_doc->>'name'), coalesce(p_doc->>'prepaid', '1600'), p_doc->>'expense', nullif(p_doc->>'cc', '')::uuid,
          round((p_doc->>'amount')::numeric, 2), date_trunc('month', (p_doc->>'start')::date)::date, (p_doc->>'months')::int) returning id into sid;
  return sid;
end $$;
-- posts every month due up to p_through (inclusive month); the last month takes the rounding difference
create or replace function public.prepaid_run(p_company uuid, p_through date) returns int
language plpgsql security definer set search_path = public as $$
declare s public.prepaid_schedules; i int; per date; amt numeric; jid uuid; n int := 0; done numeric;
begin
  perform public.require_fin(p_company, 'jepost');
  for s in select * from public.prepaid_schedules where company_id = p_company and status = 'active' order by start_month loop
    for i in 0 .. s.months - 1 loop
      per := (s.start_month + make_interval(months => i))::date;
      exit when per > date_trunc('month', p_through)::date;
      continue when exists(select 1 from public.prepaid_postings where schedule_id = s.id and period = per);
      select coalesce(sum(amount), 0) into done from public.prepaid_postings where schedule_id = s.id;
      amt := case when i = s.months - 1 then s.total - done else round(s.total / s.months, 2) end;
      jid := public.post_journal(p_company, (per + interval '1 month - 1 day')::date, s.name || ' — ' || to_char(per, 'YYYY-MM'), 'prepaid', s.id,
        jsonb_build_array(jsonb_build_object('a', s.expense_account, 'd', amt, 'cc', s.cost_center_id), jsonb_build_object('a', s.prepaid_account, 'c', amt)));
      insert into public.prepaid_postings(schedule_id, period, amount, entry_id) values (s.id, per, amt, jid);
      n := n + 1;
    end loop;
    if (select count(*) from public.prepaid_postings where schedule_id = s.id) >= s.months then update public.prepaid_schedules set status = 'done' where id = s.id; end if;
  end loop;
  return n;
end $$;
create or replace function public.prepaid_stop(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s public.prepaid_schedules;
begin
  select * into s from public.prepaid_schedules where id = p_id;
  if not found then raise exception 'الجدول غير موجود'; end if;
  perform public.require_fin(s.company_id, 'jepost');
  update public.prepaid_schedules set status = 'stopped' where id = p_id and status = 'active';
end $$;

-- ---------------- 4. journal drafts, approval, reversal, recurrence ----------------
create table if not exists public.journal_drafts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  date date not null,
  memo text not null check (length(btrim(memo)) >= 3),
  lines jsonb not null check (jsonb_typeof(lines) = 'array'),
  status text not null default 'draft' check (status in ('draft','pending','posted','rejected','recurring','ended')),
  reverse_on date,
  reversed_entry uuid references public.journal_entries(id) on delete set null,
  recur_months int check (recur_months is null or recur_months between 1 and 12),
  next_run date,
  entry_id uuid references public.journal_entries(id) on delete set null,
  note text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  approved_by uuid, approved_at timestamptz
);
create index if not exists journal_drafts_co on public.journal_drafts(company_id, status, date);
alter table public.journal_drafts enable row level security;
drop policy if exists journal_drafts_read on public.journal_drafts;
create policy journal_drafts_read on public.journal_drafts for select using (public.fin_can(company_id, 'je'));
revoke all on public.journal_drafts from anon;
grant select on public.journal_drafts to authenticated;

create or replace function public.jd_check(p_company uuid, p_lines jsonb) returns void language plpgsql stable security definer set search_path = public as $$
declare d numeric; c numeric;
begin
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then raise exception 'القيد سطران على الأقل'; end if;
  select sum(round(coalesce((x->>'d')::numeric, 0), 2)), sum(round(coalesce((x->>'c')::numeric, 0), 2)) into d, c from jsonb_array_elements(p_lines) x;
  if d <> c or d = 0 then raise exception 'القيد غير متوازن (مدين % / دائن %)', d, c; end if;
  if exists(select 1 from jsonb_array_elements(p_lines) x where not exists(select 1 from public.accounts a where a.company_id = p_company and a.code = x->>'a' and not a.is_header)) then
    raise exception 'حساب غير موجود أو رئيسي في القيد'; end if;
end $$;
-- save (new or edit while draft / rejected); p_submit sends it for approval
create or replace function public.jd_save(p_company uuid, p_id uuid, p_doc jsonb, p_submit boolean) returns uuid
language plpgsql security definer set search_path = public as $$
declare j public.journal_drafts; did uuid := p_id;
begin
  perform public.require_fin(p_company, 'je');
  perform public.jd_check(p_company, p_doc->'lines');
  if p_doc->>'reverse_on' is not null and (p_doc->>'reverse_on')::date <= (p_doc->>'date')::date then raise exception 'تاريخ العكس بعد تاريخ القيد'; end if;
  if did is null then
    insert into public.journal_drafts(company_id, date, memo, lines, reverse_on, recur_months, status)
    values (p_company, (p_doc->>'date')::date, btrim(p_doc->>'memo'), p_doc->'lines', nullif(p_doc->>'reverse_on', '')::date, nullif(p_doc->>'recur', '')::int,
            case when p_submit then 'pending' else 'draft' end) returning id into did;
  else
    select * into j from public.journal_drafts where id = did and company_id = p_company for update;
    if not found then raise exception 'المسودة غير موجودة'; end if;
    if j.status not in ('draft','rejected','pending') then raise exception 'لا تُعدّل بعد الترحيل'; end if;
    update public.journal_drafts set date = (p_doc->>'date')::date, memo = btrim(p_doc->>'memo'), lines = p_doc->'lines', reverse_on = nullif(p_doc->>'reverse_on', '')::date,
      recur_months = nullif(p_doc->>'recur', '')::int, status = case when p_submit then 'pending' else 'draft' end, note = null where id = did;
  end if;
  return did;
end $$;
-- approve: posted now; with recurrence it becomes a template that posts again every N months; never by its author (except the owner)
create or replace function public.jd_approve(p_id uuid, p_ok boolean, p_note text) returns uuid
language plpgsql security definer set search_path = public as $$
declare j public.journal_drafts; jid uuid;
begin
  select * into j from public.journal_drafts where id = p_id for update;
  if not found then raise exception 'المسودة غير موجودة'; end if;
  perform public.require_fin(j.company_id, 'jepost');
  if j.status <> 'pending' then raise exception 'المسودة ليست بانتظار الاعتماد'; end if;
  if j.created_by = auth.uid() and not public.has_role(j.company_id, array['owner']) then raise exception 'لا يعتمد القيد من أعدّه'; end if;
  if not p_ok then
    if nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'اكتب سبب الرفض'; end if;
    update public.journal_drafts set status = 'rejected', note = btrim(p_note) where id = p_id; return null;
  end if;
  jid := public.post_journal(j.company_id, j.date, j.memo, 'manual', j.id, j.lines);
  update public.journal_drafts set entry_id = jid, approved_by = auth.uid(), approved_at = now(),
    status = case when j.recur_months is not null then 'recurring' else 'posted' end,
    next_run = case when j.recur_months is not null then (j.date + make_interval(months => j.recur_months))::date end where id = p_id;
  return jid;
end $$;
create or replace function public.jd_delete(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare j public.journal_drafts;
begin
  select * into j from public.journal_drafts where id = p_id;
  if not found then raise exception 'المسودة غير موجودة'; end if;
  perform public.require_fin(j.company_id, 'je');
  if j.status = 'recurring' then update public.journal_drafts set status = 'ended', next_run = null where id = p_id; return; end if;
  if j.status not in ('draft','rejected','pending') then raise exception 'القيد مُرحّل: اعكسه من القيود اليومية'; end if;
  delete from public.journal_drafts where id = p_id;
end $$;
-- due automatic reversals and recurring entries (run when finance opens the books and by the month-end check)
create or replace function public.jd_run_due(p_company uuid) returns int
language plpgsql security definer set search_path = public as $$
declare j public.journal_drafts; jid uuid; n int := 0;
begin
  perform public.require_fin(p_company, 'jepost');
  for j in select * from public.journal_drafts where company_id = p_company and status in ('posted','recurring') and reverse_on is not null and reverse_on <= current_date and reversed_entry is null and entry_id is not null loop
    jid := public.post_journal(p_company, j.reverse_on, 'عكس آلي — ' || j.memo, 'reversal', null,
      (select jsonb_agg(jsonb_build_object('a', account_code, 'd', credit, 'c', debit, 'cc', cost_center_id)) from public.journal_lines where entry_id = j.entry_id), j.entry_id);
    update public.journal_drafts set reversed_entry = jid where id = j.id; n := n + 1;
  end loop;
  for j in select * from public.journal_drafts where company_id = p_company and status = 'recurring' and next_run is not null and next_run <= current_date order by next_run loop
    while j.next_run <= current_date loop
      perform public.post_journal(p_company, j.next_run, j.memo || ' — ' || to_char(j.next_run, 'YYYY-MM'), 'manual', j.id, j.lines);
      j.next_run := (j.next_run + make_interval(months => j.recur_months))::date; n := n + 1;
    end loop;
    update public.journal_drafts set next_run = j.next_run where id = j.id;
  end loop;
  return n;
end $$;

-- ---------------- 5. month-end close checklist ----------------
create or replace function public.month_close_status(p_company uuid, p_month date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare ms date := date_trunc('month', p_month)::date; me date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  drafts int; banks int; banks_ok int; dep_need boolean; dep_done boolean; pre_due int; pay_need boolean; pay_ok boolean; z_bad int; z_on boolean;
begin
  perform public.require_fin(p_company, 'reports');
  select count(*) into drafts from public.journal_drafts where company_id = p_company and status in ('draft','pending') and date <= me;
  select count(*), count(*) filter (where exists(select 1 from public.bank_recons r where r.company_id = p_company and r.account_code = a.code and r.status = 'done' and r.statement_date >= me)
                                       or (exists(select 1 from public.bank_lines b where b.company_id = p_company and b.account_code = a.code and b.day between ms and me)
                                           and not exists(select 1 from public.bank_lines b where b.company_id = p_company and b.account_code = a.code and b.day between ms and me and b.status = 'open')))
    into banks, banks_ok from public.accounts a where a.company_id = p_company and a.parent_code = '1100' and not a.is_header and a.code <> '1110' and a.code !~ '^113'
      and exists(select 1 from public.journal_lines l join public.journal_entries e on e.id = l.entry_id where l.company_id = p_company and l.account_code = a.code and e.date between ms and me);
  dep_need := exists(select 1 from public.fixed_assets where company_id = p_company and status = 'active' and acquire_date <= me);
  dep_done := exists(select 1 from public.journal_entries where company_id = p_company and source = 'depreciation' and date between ms and me);
  select count(*) into pre_due from public.prepaid_schedules s where s.company_id = p_company and s.status = 'active' and s.start_month <= ms
     and not exists(select 1 from public.prepaid_postings p where p.schedule_id = s.id and p.period = ms) and (s.start_month + make_interval(months => s.months - 1))::date >= ms;
  pay_need := public.module_on(p_company, 'hr') and exists(select 1 from public.employees where company_id = p_company and hire_date <= me and (end_date is null or end_date >= ms));
  pay_ok := exists(select 1 from public.payroll_runs where company_id = p_company and year = extract(year from ms) and month = extract(month from ms) and status in ('approved','paid'));
  z_on := exists(select 1 from public.zatca_settings where company_id = p_company and enabled);
  select count(*) into z_bad from public.zatca_docs z where z.company_id = p_company and z.status in ('pending','error','rejected') and z.created_at::date <= me;
  return jsonb_build_object('month', to_char(ms, 'YYYY-MM'), 'through', me,
    'closed_through', (select books_closed_through from public.companies where id = p_company),
    'checks', jsonb_build_array(
      jsonb_build_object('k', 'drafts', 'ok', drafts = 0, 'n', drafts),
      jsonb_build_object('k', 'bank', 'ok', banks_ok = banks, 'n', banks - banks_ok, 'na', banks = 0),
      jsonb_build_object('k', 'depreciation', 'ok', not dep_need or dep_done, 'na', not dep_need),
      jsonb_build_object('k', 'prepaid', 'ok', pre_due = 0, 'n', pre_due),
      jsonb_build_object('k', 'payroll', 'ok', not pay_need or pay_ok, 'na', not pay_need),
      jsonb_build_object('k', 'zatca', 'ok', not z_on or z_bad = 0, 'n', z_bad, 'na', not z_on)));
end $$;

revoke all on function public.bank_lines_import(uuid, text, jsonb), public.bank_suggest(uuid, text), public.bank_match(jsonb), public.bank_unmatch(uuid),
  public.bank_quick_post(uuid, text, text), public.payment_allocate(uuid, jsonb), public.prepaid_create(uuid, jsonb), public.prepaid_run(uuid, date), public.prepaid_stop(uuid),
  public.jd_check(uuid, jsonb), public.jd_save(uuid, uuid, jsonb, boolean), public.jd_approve(uuid, boolean, text), public.jd_delete(uuid), public.jd_run_due(uuid),
  public.month_close_status(uuid, date) from public, anon;
grant execute on function public.bank_lines_import(uuid, text, jsonb), public.bank_suggest(uuid, text), public.bank_match(jsonb), public.bank_unmatch(uuid),
  public.bank_quick_post(uuid, text, text), public.payment_allocate(uuid, jsonb), public.prepaid_create(uuid, jsonb), public.prepaid_run(uuid, date), public.prepaid_stop(uuid),
  public.jd_save(uuid, uuid, jsonb, boolean), public.jd_approve(uuid, boolean, text), public.jd_delete(uuid), public.jd_run_due(uuid), public.month_close_status(uuid, date) to authenticated;
