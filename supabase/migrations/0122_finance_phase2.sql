-- 0122 — finance phase two (owner's finance spec, 2026-11-18)
-- 1. Zakat estimate from the books, following the Implementing Regulation for Zakat Collection (1445H, uqn.gov.sa/details?p=24722):
--    base = additions (equity, Art. 23/1; non-current liabilities within the deducted assets, Art. 23/2 + Art. 29; adjusted − book profit,
--    Art. 23/3) − deductions (Art. 26, e.g. net fixed assets); upper limit = equity + the profit difference (Art. 28/1); when the base is
--    below the adjusted net profit, Art. 27/2 (a: undeducted assets + profit difference, b: adjusted net profit, the lower one);
--    rate = 2.5% for a Hijri year, by actual days otherwise: (2.5% ÷ days of the Hijri year (354)) × days of the financial year (Art. 15/1–2).
--    It is a guide: every figure is editable before the estimate, and the taxpayer's own return on ZATCA's portal is what counts.
-- 2. Loans (instalment schedule, principal and profit) and letters of guarantee (cash margin, expiry alerts).
-- 3. VAT return drill-down: the documents behind each figure of vat_summary.
-- 4. Budget control on purchase orders and on manual journal drafts (warning, or a block with companies.budget_block).

alter table public.journal_entries drop constraint if exists journal_entries_source_check;
alter table public.journal_entries add constraint journal_entries_source_check check (source in ('manual','reversal','sales','purchase','receipt','payment',
  'stock','payroll','payroll_pay','advance','expense','opening','sales_return','purchase_return','asset','depreciation','cheque','closing','petty','trip','vehicle',
  'prepaid','bank','loan','guarantee','zakat'));

create or replace function public.fin2_accounts(p_company uuid) returns void language sql security definer set search_path = public as $$
  insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header) values
    (p_company, '1810', 'تأمينات خطابات الضمان', 'Letter of guarantee margins', 'asset', '1000', false),
    (p_company, '2350', 'مخصص الزكاة', 'Zakat provision', 'liab', '2000', false),
    (p_company, '2600', 'قروض وتسهيلات بنكية', 'Bank loans and facilities', 'liab', '2000', false),
    (p_company, '5800', 'تكلفة التمويل (أرباح القروض والعمولات البنكية)', 'Finance costs', 'exp', '5000', false),
    (p_company, '5960', 'مصروف الزكاة', 'Zakat expense', 'exp', '5000', false)
  on conflict do nothing
$$;

-- ---------------- 1. zakat ----------------
-- pure calculation (tested): p = {equity, liabilities, deducted, assets, profit_book, profit_adj, days}
create or replace function public.zakat_calc(p jsonb) returns jsonb language plpgsql immutable as $$
declare eq numeric := coalesce((p->>'equity')::numeric, 0); li numeric := greatest(coalesce((p->>'liabilities')::numeric, 0), 0);
  de numeric := greatest(coalesce((p->>'deducted')::numeric, 0), 0); ta numeric := coalesce((p->>'assets')::numeric, 0);
  pb numeric := coalesce((p->>'profit_book')::numeric, 0); pa numeric := coalesce((p->>'profit_adj')::numeric, coalesce((p->>'profit_book')::numeric, 0));
  dy int := coalesce((p->>'days')::int, 354); diff numeric; liab_in numeric; base0 numeric; cap numeric; base numeric; rule text := 'base'; rate numeric;
begin
  if dy < 1 or dy > 800 then raise exception 'عدد أيام السنة المالية غير صحيح'; end if;
  diff := pa - pb;
  liab_in := least(li, de);                          -- Art. 23/2: liabilities only within the deducted assets
  base0 := eq + liab_in + diff - de;                 -- Art. 23 additions − Art. 26 deductions
  cap := eq + diff;                                  -- Art. 28/1
  base := base0;
  if base > cap then base := cap; rule := 'cap'; end if;
  if pa > 0 and base < pa then                       -- Art. 27/2
    base := least(pa, (ta - de) + diff); rule := 'min';
  end if;
  if base < 0 then base := 0; rule := case when pa <= 0 then 'none' else rule end; end if;
  rate := round(0.025 / 354 * dy, 8);                -- Art. 15/1–2
  return jsonb_build_object('liab_added', liab_in, 'diff', diff, 'base_before', base0, 'cap', cap, 'base', round(base, 2), 'rule', rule,
    'rate', rate, 'days', dy, 'zakat', round(base * rate, 2));
end $$;

-- the figures from the books (trial balance at the end, profit of the period); every one can be changed on screen
create or replace function public.zakat_inputs(p_company uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare eq numeric; li numeric; de numeric; ta numeric; pb numeric;
begin
  perform public.require_fin(p_company, 'reports');
  if p_to < p_from then raise exception 'نهاية السنة قبل بدايتها'; end if;
  with b as (select a.code, a.type, sum(l.debit - l.credit) dr from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
             join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
             where l.company_id = p_company and e.date <= p_to group by a.code, a.type)
  select coalesce(-sum(dr) filter (where type in ('equity','rev','exp')), 0),
         coalesce(-sum(dr) filter (where type = 'liab' and (code = '2500' or code >= '2600')), 0),
         coalesce(sum(dr) filter (where code ~ '^17'), 0),
         coalesce(sum(dr) filter (where type = 'asset'), 0)
    into eq, li, de, ta from b;
  select coalesce(sum(l.credit - l.debit), 0) into pb from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
    join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
   where l.company_id = p_company and e.date between p_from and p_to and a.type in ('rev','exp') and a.code <> '5960' and e.source <> 'closing';
  return jsonb_build_object('equity', round(eq, 2), 'liabilities', round(greatest(li, 0), 2), 'deducted', round(greatest(de, 0), 2), 'assets', round(ta, 2),
    'profit_book', round(pb, 2), 'profit_adj', round(pb, 2), 'days', p_to - p_from + 1,
    'posted', (select coalesce(sum(l.debit - l.credit), 0) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
               where l.company_id = p_company and l.account_code = '5960' and e.date between p_from and p_to));
end $$;

-- book the estimate: Dr 5960 zakat expense / Cr 2350 zakat provision
create or replace function public.zakat_post(p_company uuid, p_date date, p_amount numeric, p_memo text) returns uuid
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'jepost');
  if coalesce(p_amount, 0) <= 0 then raise exception 'مبلغ الزكاة صفر'; end if;
  perform public.fin2_accounts(p_company);
  return public.post_journal(p_company, p_date, coalesce(nullif(btrim(p_memo), ''), 'مخصص الزكاة التقديري'), 'zakat', null,
    jsonb_build_array(jsonb_build_object('a', '5960', 'd', round(p_amount, 2)), jsonb_build_object('a', '2350', 'c', round(p_amount, 2))));
end $$;

-- ---------------- 2. loans and letters of guarantee ----------------
create table if not exists public.bank_facilities (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  kind text not null check (kind in ('loan','lg')),
  bank text not null check (length(btrim(bank)) between 2 and 100),
  ref text check (ref is null or length(ref) <= 60),
  amount numeric(14,2) not null check (amount > 0),
  start_date date not null,
  account_code text not null default '1120',
  -- loan
  rate numeric(7,4) check (rate is null or rate between 0 and 100),
  months int check (months is null or months between 1 and 360),
  method text check (method is null or method in ('annuity','flat')),
  -- letter of guarantee
  lg_type text check (lg_type is null or lg_type in ('bid','performance','advance','other')),
  beneficiary text check (beneficiary is null or length(beneficiary) <= 150),
  expiry date,
  margin numeric(14,2) not null default 0 check (margin >= 0),
  fee numeric(14,2) not null default 0 check (fee >= 0),
  note text check (note is null or length(note) <= 300),
  status text not null default 'active' check (status in ('active','closed','released')),
  entry_id uuid references public.journal_entries(id) on delete set null,
  release_entry uuid references public.journal_entries(id) on delete set null,
  released_on date,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check (kind <> 'loan' or (rate is not null and months is not null and method is not null)),
  check (kind <> 'lg' or (expiry is not null and expiry >= start_date and margin <= amount))
);
create index if not exists bank_facilities_co on public.bank_facilities(company_id, kind, status);
create table if not exists public.facility_instalments (
  id bigint generated always as identity primary key,
  facility_id uuid not null references public.bank_facilities(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  n int not null,
  due date not null,
  principal numeric(14,2) not null,
  profit numeric(14,2) not null,
  paid_on date,
  entry_id uuid references public.journal_entries(id) on delete set null,
  unique (facility_id, n)
);
alter table public.bank_facilities enable row level security;
alter table public.facility_instalments enable row level security;
drop policy if exists bank_facilities_read on public.bank_facilities;
create policy bank_facilities_read on public.bank_facilities for select using (public.fin_can(company_id, 'reports') or public.fin_can(company_id, 'je'));
drop policy if exists facility_instalments_read on public.facility_instalments;
create policy facility_instalments_read on public.facility_instalments for select using (public.fin_can(company_id, 'reports') or public.fin_can(company_id, 'je'));
revoke all on public.bank_facilities, public.facility_instalments from anon;
grant select on public.bank_facilities, public.facility_instalments to authenticated;

-- pure schedule (tested): annuity = equal instalments, profit on the declining balance; flat = profit on the original amount spread evenly
create or replace function public.loan_schedule(p_amount numeric, p_rate numeric, p_months int, p_method text, p_start date)
returns table(n int, due date, principal numeric, profit numeric, balance numeric) language plpgsql immutable as $$
declare r numeric := coalesce(p_rate, 0) / 1200; pay numeric; bal numeric := round(p_amount, 2); pr numeric; pf numeric; tot_pf numeric; i int;
begin
  if p_amount <= 0 or p_months < 1 then raise exception 'مبلغ القرض أو مدته غير صحيحة'; end if;
  if p_method = 'flat' then tot_pf := round(p_amount * coalesce(p_rate, 0) / 100 * p_months / 12, 2); end if;
  if p_method = 'annuity' and r > 0 then pay := round(p_amount * r / (1 - power(1 + r, -p_months)), 2); end if;
  for i in 1..p_months loop
    if p_method = 'flat' then
      pr := case when i = p_months then bal else round(p_amount / p_months, 2) end;
      pf := case when i = p_months then tot_pf - round(tot_pf / p_months, 2) * (p_months - 1) else round(tot_pf / p_months, 2) end;
    elsif r = 0 then
      pr := case when i = p_months then bal else round(p_amount / p_months, 2) end; pf := 0;
    else
      pf := round(bal * r, 2);
      pr := case when i = p_months then bal else pay - pf end;
    end if;
    bal := bal - pr;
    n := i; due := (p_start + make_interval(months => i))::date; principal := pr; profit := pf; balance := bal;
    return next;
  end loop;
end $$;

-- doc = {bank, ref, amount, start, rate, months, method, account, received (book the loan into the bank now), note}
create or replace function public.loan_create(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare fid uuid; jid uuid; acc text := coalesce(nullif(p_doc->>'account', ''), '1120'); amt numeric := round((p_doc->>'amount')::numeric, 2);
  st date := coalesce(nullif(p_doc->>'start', '')::date, current_date);
begin
  perform public.require_fin(p_company, 'jepost');
  if not exists(select 1 from public.accounts where company_id = p_company and code = acc and parent_code = '1100' and not is_header) then raise exception 'اختر حساب البنك'; end if;
  perform public.fin2_accounts(p_company);
  insert into public.bank_facilities(company_id, kind, bank, ref, amount, start_date, account_code, rate, months, method, note)
  values (p_company, 'loan', btrim(p_doc->>'bank'), nullif(btrim(p_doc->>'ref'), ''), amt, st, acc, coalesce((p_doc->>'rate')::numeric, 0),
          (p_doc->>'months')::int, coalesce(nullif(p_doc->>'method', ''), 'annuity'), nullif(btrim(p_doc->>'note'), '')) returning id into fid;
  insert into public.facility_instalments(facility_id, company_id, n, due, principal, profit)
    select fid, p_company, s.n, s.due, s.principal, s.profit from public.loan_schedule(amt, coalesce((p_doc->>'rate')::numeric, 0), (p_doc->>'months')::int,
      coalesce(nullif(p_doc->>'method', ''), 'annuity'), st) s;
  if coalesce((p_doc->>'received')::boolean, true) then
    jid := public.post_journal(p_company, st, 'استلام قرض — ' || btrim(p_doc->>'bank') || coalesce(' ' || nullif(btrim(p_doc->>'ref'), ''), ''), 'loan', fid,
      jsonb_build_array(jsonb_build_object('a', acc, 'd', amt), jsonb_build_object('a', '2600', 'c', amt)));
    update public.bank_facilities set entry_id = jid where id = fid;
  end if;
  return fid;
end $$;

-- pay one instalment: Dr 2600 principal + Dr 5800 profit / Cr the bank
create or replace function public.loan_pay(p_inst bigint, p_date date, p_account text) returns uuid
language plpgsql security definer set search_path = public as $$
declare i public.facility_instalments; f public.bank_facilities; jid uuid; acc text;
begin
  select * into i from public.facility_instalments where id = p_inst for update;
  if not found then raise exception 'القسط غير موجود'; end if;
  select * into f from public.bank_facilities where id = i.facility_id for update;
  perform public.require_fin(f.company_id, 'jepost');
  if i.paid_on is not null then raise exception 'القسط مدفوع'; end if;
  if exists(select 1 from public.facility_instalments where facility_id = f.id and n < i.n and paid_on is null) then raise exception 'ادفع الأقساط السابقة أولاً'; end if;
  acc := coalesce(nullif(p_account, ''), f.account_code);
  perform public.fin2_accounts(f.company_id);
  jid := public.post_journal(f.company_id, coalesce(p_date, current_date), 'قسط قرض ' || i.n || ' — ' || f.bank || coalesce(' ' || f.ref, ''), 'loan', f.id,
    jsonb_build_array(jsonb_build_object('a', '2600', 'd', i.principal), jsonb_build_object('a', '5800', 'd', i.profit), jsonb_build_object('a', acc, 'c', i.principal + i.profit)));
  update public.facility_instalments set paid_on = coalesce(p_date, current_date), entry_id = jid where id = p_inst;
  if not exists(select 1 from public.facility_instalments where facility_id = f.id and paid_on is null) then update public.bank_facilities set status = 'closed' where id = f.id; end if;
  return jid;
end $$;

-- doc = {bank, ref, type, beneficiary, amount, start, expiry, margin_pct, fee, account, note}; margin: Dr 1810 / Cr bank; fee: Dr 5800 / Cr bank
create or replace function public.lg_create(p_company uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare fid uuid; jid uuid; acc text := coalesce(nullif(p_doc->>'account', ''), '1120'); amt numeric := round((p_doc->>'amount')::numeric, 2);
  mg numeric; fe numeric := round(coalesce((p_doc->>'fee')::numeric, 0), 2); st date := coalesce(nullif(p_doc->>'start', '')::date, current_date); ls jsonb := '[]';
begin
  perform public.require_fin(p_company, 'jepost');
  if not exists(select 1 from public.accounts where company_id = p_company and code = acc and parent_code = '1100' and not is_header) then raise exception 'اختر حساب البنك'; end if;
  if coalesce((p_doc->>'margin_pct')::numeric, 0) not between 0 and 100 then raise exception 'نسبة الغطاء بين 0 و100'; end if;
  mg := round(amt * coalesce((p_doc->>'margin_pct')::numeric, 0) / 100, 2);
  perform public.fin2_accounts(p_company);
  insert into public.bank_facilities(company_id, kind, bank, ref, amount, start_date, account_code, lg_type, beneficiary, expiry, margin, fee, note)
  values (p_company, 'lg', btrim(p_doc->>'bank'), nullif(btrim(p_doc->>'ref'), ''), amt, st, acc, coalesce(nullif(p_doc->>'type', ''), 'other'),
          nullif(btrim(p_doc->>'beneficiary'), ''), (p_doc->>'expiry')::date, mg, fe, nullif(btrim(p_doc->>'note'), '')) returning id into fid;
  if mg > 0 then ls := ls || jsonb_build_array(jsonb_build_object('a', '1810', 'd', mg)); end if;
  if fe > 0 then ls := ls || jsonb_build_array(jsonb_build_object('a', '5800', 'd', fe)); end if;
  if mg + fe > 0 then
    jid := public.post_journal(p_company, st, 'خطاب ضمان — ' || btrim(p_doc->>'bank') || coalesce(' — ' || nullif(btrim(p_doc->>'beneficiary'), ''), ''), 'guarantee', fid,
      ls || jsonb_build_array(jsonb_build_object('a', acc, 'c', mg + fe)));
    update public.bank_facilities set entry_id = jid where id = fid;
  end if;
  return fid;
end $$;

-- extend (new expiry, optional fee) or release (the margin goes back to the bank)
create or replace function public.lg_action(p_id uuid, p_doc jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare f public.bank_facilities; jid uuid; fe numeric := round(coalesce((p_doc->>'fee')::numeric, 0), 2); dt date := coalesce(nullif(p_doc->>'date', '')::date, current_date);
begin
  select * into f from public.bank_facilities where id = p_id and kind = 'lg' for update;
  if not found then raise exception 'الخطاب غير موجود'; end if;
  perform public.require_fin(f.company_id, 'jepost');
  if f.status <> 'active' then raise exception 'الخطاب ليس قائماً'; end if;
  if p_doc->>'do' = 'extend' then
    if (p_doc->>'expiry')::date is null or (p_doc->>'expiry')::date <= f.expiry then raise exception 'تاريخ الانتهاء الجديد بعد الحالي'; end if;
    update public.bank_facilities set expiry = (p_doc->>'expiry')::date, fee = fee + fe where id = p_id;
    if fe > 0 then
      perform public.post_journal(f.company_id, dt, 'تمديد خطاب ضمان — ' || f.bank, 'guarantee', f.id,
        jsonb_build_array(jsonb_build_object('a', '5800', 'd', fe), jsonb_build_object('a', f.account_code, 'c', fe)));
    end if;
  elsif p_doc->>'do' = 'release' then
    if f.margin > 0 then
      jid := public.post_journal(f.company_id, dt, 'إفراج عن غطاء خطاب ضمان — ' || f.bank, 'guarantee', f.id,
        jsonb_build_array(jsonb_build_object('a', f.account_code, 'd', f.margin), jsonb_build_object('a', '1810', 'c', f.margin)));
    end if;
    update public.bank_facilities set status = 'released', released_on = dt, release_entry = jid where id = p_id;
  else raise exception 'إجراء غير معروف'; end if;
end $$;

-- what needs attention: instalments overdue or due within 15 days, guarantees expiring within 30 days (or already expired and not released)
create or replace function public.facility_alerts(p_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.fin_can(p_company, 'reports') or public.fin_can(p_company, 'je')) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return jsonb_build_object(
    'instalments', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'facility', f.id, 'bank', f.bank, 'ref', f.ref, 'n', i.n, 'due', i.due,
        'amount', i.principal + i.profit, 'overdue', i.due < current_date) order by i.due)
      from public.facility_instalments i join public.bank_facilities f on f.id = i.facility_id
      where i.company_id = p_company and i.paid_on is null and f.status = 'active' and i.due <= current_date + 15
        and i.n = (select min(n) from public.facility_instalments x where x.facility_id = f.id and x.paid_on is null)), '[]'),
    'guarantees', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'bank', f.bank, 'ref', f.ref, 'beneficiary', f.beneficiary, 'amount', f.amount,
        'expiry', f.expiry, 'days', f.expiry - current_date) order by f.expiry)
      from public.bank_facilities f where f.company_id = p_company and f.kind = 'lg' and f.status = 'active' and f.expiry <= current_date + 30), '[]'));
end $$;

-- ---------------- 3. VAT return drill-down ----------------
-- p_box: sales (standard-rated sales + output VAT) | sales_zero | purch (standard-rated purchases + input VAT) | purch_zero; credit notes come negative
create or replace function public.vat_docs(p_company uuid, p_from date, p_to date, p_box text)
returns table(kind text, id uuid, doc_id uuid, no text, date date, party text, amount numeric, vat numeric)
language plpgsql stable security definer set search_path = public as $$
declare z boolean := p_box like '%zero'; s boolean := p_box like 'sales%';
begin
  perform public.require_fin(p_company, 'vat');
  if p_box not in ('sales','sales_zero','purch','purch_zero') then raise exception 'خانة غير معروفة'; end if;
  return query
  select x.kind, x.id, x.doc_id, x.no, x.date, p.name, x.amount, x.vat from (
    select case when i.doc_type = 'debit' then 'debit' else 'invoice' end kind, i.id, i.id doc_id, i.no, i.date, i.party_id,
           sum(l.amount) amount, sum(l.vat) vat
      from public.sales_invoices i join public.sales_invoice_lines l on l.invoice_id = i.id
     where s and i.company_id = p_company and i.status = 'posted' and i.date between p_from and p_to and (l.vat_rate = 0) = z group by i.id
    union all
    select 'bill', b.id, b.id, coalesce(b.supplier_ref, b.no), b.date, b.party_id, sum(l.amount), sum(l.vat)
      from public.purchase_bills b join public.purchase_bill_lines l on l.bill_id = b.id
     where not s and b.company_id = p_company and b.status = 'posted' and b.date between p_from and p_to and (l.vat_rate = 0) = z group by b.id
    union all
    select 'credit', n.id, n.doc_id, n.no, n.date, n.party_id, -sum(l.amount), -sum(l.vat)
      from public.credit_notes n join public.credit_note_lines l on l.note_id = n.id
     where n.company_id = p_company and n.kind = case when s then 'sales' else 'purchase' end and n.date between p_from and p_to and (l.vat_rate = 0) = z group by n.id
  ) x left join public.parties p on p.id = x.party_id
  order by x.date, x.no;
end $$;

-- ---------------- 4. budget control on purchase orders and journals ----------------
-- expense lines [{a, d, c, cc}] against the year's budget: one row per (cost center, account) that goes over
create or replace function public.budget_check_lines(p_company uuid, p_date date, p_lines jsonb) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r record; b jsonb; res jsonb := '[]';
begin
  for r in select nullif(x->>'cc', '')::uuid cc, x->>'a' a, sum(coalesce((x->>'d')::numeric, 0) - coalesce((x->>'c')::numeric, 0)) amt
             from jsonb_array_elements(coalesce(p_lines, '[]')) x join public.accounts ac on ac.company_id = p_company and ac.code = x->>'a' and ac.type = 'exp'
            group by 1, 2 having sum(coalesce((x->>'d')::numeric, 0) - coalesce((x->>'c')::numeric, 0)) > 0 loop
    b := public.budget_position(p_company, r.cc, r.a, r.amt, p_date);
    if coalesce((b->>'over')::boolean, false) then
      res := res || jsonb_build_array(b || jsonb_build_object('account', r.a, 'name', (select name from public.accounts where company_id = p_company and code = r.a)));
    end if;
  end loop;
  return res;
end $$;
create or replace function public.budget_guard_lines(p_company uuid, p_date date, p_lines jsonb) returns void
language plpgsql stable security definer set search_path = public as $$
declare o jsonb;
begin
  if not coalesce((select budget_block from public.companies where id = p_company), false) then return; end if;
  o := public.budget_check_lines(p_company, p_date, p_lines);
  if jsonb_array_length(o) > 0 then
    raise exception 'يتجاوز الموازنة في الحساب % (المتبقي % ريال) — منشأتك تمنع اعتماد ما يتجاوزها', o->0->>'account', round((o->0->>'remaining')::numeric, 2);
  end if;
end $$;
create or replace function public.po_budget_lines(p_order uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('a', l.account_code, 'd', l.amount)), '[]') from public.purchase_order_lines l where l.order_id = p_order and l.account_code is not null
$$;
create or replace function public.po_budget(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare o public.purchase_orders;
begin
  select * into o from public.purchase_orders where id = p_order;
  if not found or not (public.fin_can(o.company_id, 'purch') or public.fin_can(o.company_id, 'reports')) then return '[]'; end if;
  return public.budget_check_lines(o.company_id, o.date, public.po_budget_lines(p_order));
end $$;
create or replace function public.jd_budget(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare j public.journal_drafts;
begin
  select * into j from public.journal_drafts where id = p_id;
  if not found or not public.fin_can(j.company_id, 'je') then return '[]'; end if;
  return public.budget_check_lines(j.company_id, j.date, j.lines);
end $$;
-- the order's totals are written after its lines: check there (po_fill_lines)
create or replace function public.purchase_orders_budget_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'open' then perform public.budget_guard_lines(new.company_id, new.date, public.po_budget_lines(new.id)); end if;
  return new;
end $$;
drop trigger if exists purchase_orders_budget_guard on public.purchase_orders;
create trigger purchase_orders_budget_guard after update of subtotal on public.purchase_orders for each row
  when (new.subtotal is distinct from old.subtotal or new.subtotal > 0) execute function public.purchase_orders_budget_guard();
-- a journal draft is checked when it is approved
create or replace function public.journal_drafts_budget_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status in ('posted','recurring') and old.status = 'pending' then perform public.budget_guard_lines(new.company_id, new.date, new.lines); end if;
  return new;
end $$;
drop trigger if exists journal_drafts_budget_guard on public.journal_drafts;
create trigger journal_drafts_budget_guard before update of status on public.journal_drafts for each row execute function public.journal_drafts_budget_guard();

-- ---------------- month-end: loan instalments due in the month ----------------
create or replace function public.month_close_loans(p_company uuid, p_month date) returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.facility_instalments i join public.bank_facilities f on f.id = i.facility_id
   where i.company_id = p_company and f.status = 'active' and i.paid_on is null and i.due <= (date_trunc('month', p_month) + interval '1 month - 1 day')::date
$$;

CREATE OR REPLACE FUNCTION public.month_close_status(p_company uuid, p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ms date := date_trunc('month', p_month)::date; me date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  drafts int; banks int; banks_ok int; dep_need boolean; dep_done boolean; pre_due int; pay_need boolean; pay_ok boolean; z_bad int; z_on boolean; ln int;
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
  ln := public.month_close_loans(p_company, ms);
  return jsonb_build_object('month', to_char(ms, 'YYYY-MM'), 'through', me,
    'closed_through', (select books_closed_through from public.companies where id = p_company),
    'checks', jsonb_build_array(
      jsonb_build_object('k', 'drafts', 'ok', drafts = 0, 'n', drafts),
      jsonb_build_object('k', 'bank', 'ok', banks_ok = banks, 'n', banks - banks_ok, 'na', banks = 0),
      jsonb_build_object('k', 'depreciation', 'ok', not dep_need or dep_done, 'na', not dep_need),
      jsonb_build_object('k', 'prepaid', 'ok', pre_due = 0, 'n', pre_due),
      jsonb_build_object('k', 'payroll', 'ok', not pay_need or pay_ok, 'na', not pay_need),
      jsonb_build_object('k', 'zatca', 'ok', not z_on or z_bad = 0, 'n', z_bad, 'na', not z_on),
      jsonb_build_object('k', 'loans', 'ok', ln = 0, 'n', ln, 'na', not exists(select 1 from public.bank_facilities where company_id = p_company and kind = 'loan'))));
end $function$;

revoke all on function public.zakat_calc(jsonb), public.loan_schedule(numeric, numeric, int, text, date), public.month_close_status(uuid, date) from public, anon;
revoke all on function public.fin2_accounts(uuid), public.zakat_inputs(uuid, date, date), public.zakat_post(uuid, date, numeric, text),
  public.loan_create(uuid, jsonb), public.loan_pay(bigint, date, text), public.lg_create(uuid, jsonb), public.lg_action(uuid, jsonb), public.facility_alerts(uuid),
  public.vat_docs(uuid, date, date, text), public.budget_check_lines(uuid, date, jsonb), public.budget_guard_lines(uuid, date, jsonb), public.po_budget_lines(uuid),
  public.po_budget(uuid), public.jd_budget(uuid), public.purchase_orders_budget_guard(), public.journal_drafts_budget_guard(), public.month_close_loans(uuid, date) from public, anon;
grant execute on function public.zakat_calc(jsonb), public.zakat_inputs(uuid, date, date), public.zakat_post(uuid, date, numeric, text),
  public.loan_schedule(numeric, numeric, int, text, date), public.loan_create(uuid, jsonb), public.loan_pay(bigint, date, text), public.lg_create(uuid, jsonb),
  public.lg_action(uuid, jsonb), public.facility_alerts(uuid), public.vat_docs(uuid, date, date, text), public.po_budget(uuid), public.jd_budget(uuid) to authenticated;
