-- 0116 — spend control, closer to a full spend-management suite (owner's request, 2026-11-17):
-- 1) budgets before spending: every spend request (expense, purchase, business trip, ticket) shows how it stands against the
--    budget of the employee's cost center (or the company); a company may choose to block final approval over budget;
-- 2) supplier invoices: an inbox where purchasing records each supplier invoice with its file, finance approves or rejects it,
--    and it is then linked to the posted purchase bill; files on purchase bills; a three-way match of each purchase order
--    (ordered / received / billed quantities and prices);
-- 3) business trips («انتداب») as a request kind: destination, dates, purpose, inside or outside the Kingdom; the per diem comes
--    from the employee's job grade (or the company default) × days, follows the company's approval route, and is posted on approval;
-- 4) the finance manager's spend view: spending by month, account, cost center, supplier and department.
-- Per diem rates are company policy (the Labor Law sets no amount); the company enters them.

-- ---------------- 1. budgets ----------------
alter table public.companies add column if not exists budget_block boolean not null default false;
alter table public.companies add column if not exists per_diem_in numeric(10,2) check (per_diem_in is null or per_diem_in >= 0);
alter table public.companies add column if not exists per_diem_out numeric(10,2) check (per_diem_out is null or per_diem_out >= 0);
alter table public.job_grades add column if not exists per_diem_in numeric(10,2) check (per_diem_in is null or per_diem_in >= 0);
alter table public.job_grades add column if not exists per_diem_out numeric(10,2) check (per_diem_out is null or per_diem_out >= 0);

-- the year's budget and actual spending of one expense account (or all expense accounts) for a cost center (or the company)
create or replace function public.budget_position(p_company uuid, p_cc uuid, p_account text, p_amount numeric, p_date date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare y int := extract(year from coalesce(p_date, current_date)); v_cc uuid; b numeric; a numeric;
begin
  -- a cost center with its own budget, else the company-wide budget
  v_cc := case when p_cc is not null and exists(select 1 from public.budgets where company_id = p_company and year = y and cost_center_id = p_cc) then p_cc end;
  select sum((select sum(v) from unnest(bu.months) v)) into b from public.budgets bu join public.accounts ac on ac.company_id = bu.company_id and ac.code = bu.account_code
   where bu.company_id = p_company and bu.year = y and bu.cost_center_id is not distinct from v_cc and ac.type = 'exp' and (p_account is null or bu.account_code = p_account);
  if coalesce(b, 0) = 0 then return jsonb_build_object('has', false); end if;
  select coalesce(sum(l.debit - l.credit), 0) into a from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
    join public.accounts ac on ac.company_id = l.company_id and ac.code = l.account_code
   where l.company_id = p_company and ac.type = 'exp' and (p_account is null or l.account_code = p_account)
     and (v_cc is null or l.cost_center_id = v_cc) and e.date between make_date(y, 1, 1) and make_date(y, 12, 31);
  return jsonb_build_object('has', true, 'year', y, 'budget', b, 'actual', a, 'amount', coalesce(p_amount, 0), 'after', a + coalesce(p_amount, 0),
    'remaining', b - a, 'over', a + coalesce(p_amount, 0) > b, 'scope', case when p_account is null then 'all' else p_account end,
    'cc', (select name from public.cost_centers where id = v_cc));
end $$;
create or replace function public.request_budget_account(p_kind text) returns text language sql immutable as $$
  select case p_kind when 'expense' then '5500' when 'trip' then '5230' when 'ticket' then '5220' else null end
$$;
-- a spend request against the budget: for whoever may see the request's money (finance, the owner, HR, the employee's manager)
create or replace function public.request_budget(p_request uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.requests; e public.employees; amt numeric;
begin
  select * into r from public.requests where id = p_request;
  if not found or r.kind not in ('expense','purchase','trip','ticket') then return null; end if;
  select * into e from public.employees where id = r.employee_id;
  if not (public.fin_can(r.company_id, 'reports') or public.has_role(r.company_id, array['owner','admin','hr','finance'])
          or (e.manager_id is not null and e.manager_id = public.my_employee(r.company_id))) then return null; end if;
  amt := coalesce(r.amount, (select sum(coalesce((x->>'qty')::numeric, 0) * coalesce((x->>'price')::numeric, 0)) from jsonb_array_elements(coalesce(r.payload->'lines', '[]')) x), 0);
  return public.budget_position(r.company_id, e.cost_center_id, public.request_budget_account(r.kind), amt, coalesce(r.from_date, current_date))
    || jsonb_build_object('block', (select budget_block from public.companies where id = r.company_id));
end $$;
create or replace function public.budget_block_set(p_company uuid, p_on boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin','finance']);
  update public.companies set budget_block = coalesce(p_on, false) where id = p_company;
end $$;
-- the company's choice: no final approval over budget
create or replace function public.requests_budget_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare b jsonb;
begin
  if new.status = 'approved' and old.status is distinct from 'approved' and new.kind in ('expense','purchase','trip','ticket')
     and (select budget_block from public.companies where id = new.company_id) then
    b := public.budget_position(new.company_id, (select cost_center_id from public.employees where id = new.employee_id), public.request_budget_account(new.kind),
      coalesce(new.amount, (select sum(coalesce((x->>'qty')::numeric, 0) * coalesce((x->>'price')::numeric, 0)) from jsonb_array_elements(coalesce(new.payload->'lines', '[]')) x), 0),
      coalesce(new.from_date, current_date));
    if coalesce((b->>'over')::boolean, false) then
      raise exception 'الطلب يتجاوز الموازنة (المتبقي % ريال) — منشأتك تمنع اعتماد ما يتجاوزها', round((b->>'remaining')::numeric, 2); end if;
  end if;
  return new;
end $$;
drop trigger if exists requests_budget_guard on public.requests;
create trigger requests_budget_guard before update of status on public.requests for each row execute function public.requests_budget_guard();

-- ---------------- 2. supplier invoices ----------------
create table if not exists public.purchase_bill_files (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  bill_id uuid not null references public.purchase_bills(id) on delete cascade,
  file_name text not null check (length(file_name) between 1 and 200),
  mime text not null check (mime in ('application/pdf','image/jpeg','image/png','image/webp')),
  size int not null check (size between 1 and 3145728),
  data text not null,
  uploaded_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists purchase_bill_files_bill on public.purchase_bill_files(bill_id);
alter table public.purchase_bill_files enable row level security;
drop policy if exists purchase_bill_files_all on public.purchase_bill_files;
create policy purchase_bill_files_all on public.purchase_bill_files for all using (public.fin_can(company_id, 'purch'))
  with check (public.fin_can(company_id, 'purch') and exists(select 1 from public.purchase_bills b where b.id = bill_id and b.company_id = purchase_bill_files.company_id));
revoke all on public.purchase_bill_files from anon;
grant select, insert, delete on public.purchase_bill_files to authenticated;

create table if not exists public.supplier_inbox (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  party_id uuid references public.parties(id) on delete set null,
  supplier_name text check (supplier_name is null or length(supplier_name) <= 120),
  supplier_ref text check (supplier_ref is null or length(supplier_ref) <= 60),
  inv_date date,
  amount numeric(14,2) check (amount is null or amount >= 0),
  order_id uuid references public.purchase_orders(id) on delete set null,
  note text check (note is null or length(note) <= 500),
  status text not null default 'new' check (status in ('new','approved','rejected','billed')),
  review_note text, reviewed_by uuid, reviewed_at timestamptz,
  bill_id uuid references public.purchase_bills(id) on delete set null,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists supplier_inbox_co on public.supplier_inbox(company_id, status, created_at desc);
alter table public.supplier_inbox enable row level security;
drop policy if exists supplier_inbox_read on public.supplier_inbox;
create policy supplier_inbox_read on public.supplier_inbox for select using (public.fin_can(company_id, 'purch'));
drop policy if exists supplier_inbox_add on public.supplier_inbox;
create policy supplier_inbox_add on public.supplier_inbox for insert with check (public.fin_can(company_id, 'purch') and status = 'new' and bill_id is null and reviewed_by is null);
revoke all on public.supplier_inbox from anon;
grant select, insert on public.supplier_inbox to authenticated;
create table if not exists public.supplier_inbox_files (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  inbox_id uuid not null references public.supplier_inbox(id) on delete cascade,
  file_name text not null check (length(file_name) between 1 and 200),
  mime text not null check (mime in ('application/pdf','image/jpeg','image/png','image/webp')),
  size int not null check (size between 1 and 3145728),
  data text not null,
  uploaded_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists supplier_inbox_files_i on public.supplier_inbox_files(inbox_id);
alter table public.supplier_inbox_files enable row level security;
drop policy if exists supplier_inbox_files_all on public.supplier_inbox_files;
create policy supplier_inbox_files_all on public.supplier_inbox_files for all using (public.fin_can(company_id, 'purch'))
  with check (public.fin_can(company_id, 'purch') and exists(select 1 from public.supplier_inbox s where s.id = inbox_id and s.company_id = supplier_inbox_files.company_id and s.status = 'new'));
revoke all on public.supplier_inbox_files from anon;
grant select, insert, delete on public.supplier_inbox_files to authenticated;

-- finance reviews: approve or reject (never the person who recorded it, except the owner)
create or replace function public.supplier_inbox_review(p_id uuid, p_ok boolean, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare s public.supplier_inbox;
begin
  select * into s from public.supplier_inbox where id = p_id for update;
  if not found then raise exception 'الفاتورة غير موجودة'; end if;
  if not (public.has_role(s.company_id, array['owner','admin','finance']) or public.fin_can(s.company_id, 'jepost')) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if s.status <> 'new' then raise exception 'رُوجعت هذه الفاتورة مسبقا'; end if;
  if s.created_by = auth.uid() and not public.has_role(s.company_id, array['owner']) then raise exception 'لا يراجع الفاتورة من سجّلها'; end if;
  if not p_ok and nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'اكتب سبب الرفض'; end if;
  update public.supplier_inbox set status = case when p_ok then 'approved' else 'rejected' end, review_note = nullif(btrim(coalesce(p_note, '')), ''),
    reviewed_by = auth.uid(), reviewed_at = now() where id = p_id;
end $$;
-- the approved invoice is linked to the purchase bill that was posted for it
create or replace function public.supplier_inbox_link(p_id uuid, p_bill uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s public.supplier_inbox; b public.purchase_bills;
begin
  select * into s from public.supplier_inbox where id = p_id for update;
  if not found or not public.fin_can(s.company_id, 'purch') then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if s.status <> 'approved' then raise exception 'تُربط الفاتورة بعد اعتمادها من المالية'; end if;
  select * into b from public.purchase_bills where id = p_bill and company_id = s.company_id and status = 'posted';
  if not found then raise exception 'فاتورة الشراء غير موجودة'; end if;
  if s.party_id is not null and b.party_id <> s.party_id then raise exception 'فاتورة الشراء لمورد آخر'; end if;
  if exists(select 1 from public.supplier_inbox where bill_id = p_bill and id <> p_id) then raise exception 'فاتورة الشراء مربوطة بفاتورة أخرى'; end if;
  update public.supplier_inbox set status = 'billed', bill_id = p_bill where id = p_id;
end $$;

-- three-way match of a purchase order: ordered, received and billed quantities, and the billed price against the order price
create or replace function public.po_match(p_order uuid) returns table(line_id bigint, label text, ordered numeric, received numeric, billed numeric, po_price numeric, bill_price numeric, issue text)
language plpgsql stable security definer set search_path = public as $$
declare o public.purchase_orders;
begin
  select * into o from public.purchase_orders where id = p_order;
  if not found or not public.fin_can(o.company_id, 'purch') then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query
  select l.id, coalesce(i.name, l.description, l.account_code), l.qty, l.received, l.billed, l.unit_price, bp.p,
    case when l.billed > l.received and i.type = 'stock' then 'billed_over_received'
         when bp.p is not null and abs(bp.p - l.unit_price) > 0.009 then 'price_diff'
         when l.received < l.qty and o.status = 'closed' then 'short_received'
         when l.billed < l.received then 'not_billed' else null end
    from public.purchase_order_lines l left join public.items i on i.id = l.item_id
    left join lateral (select round(sum(bl.unit_price * bl.qty) / nullif(sum(bl.qty), 0), 2) p from public.purchase_bill_lines bl
                         join public.purchase_bills pb on pb.id = bl.bill_id and pb.status = 'posted' where bl.order_line = l.id) bp on true
   where l.order_id = p_order order by l.id;
end $$;

-- ---------------- 4. spend view ----------------
create or replace function public.spend_summary(p_company uuid, p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'reports');
  return jsonb_build_object(
    'months', (select coalesce(jsonb_agg(x order by x->>'m'), '[]') from (select jsonb_build_object('m', to_char(e.date, 'YYYY-MM'), 'v', sum(l.debit - l.credit)) x
       from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
      where l.company_id = p_company and a.type = 'exp' and e.date between p_from and p_to group by to_char(e.date, 'YYYY-MM')) t),
    'accounts', (select coalesce(jsonb_agg(x order by (x->>'v')::numeric desc), '[]') from (select jsonb_build_object('k', a.code, 'n', a.name, 'v', sum(l.debit - l.credit)) x
       from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
      where l.company_id = p_company and a.type = 'exp' and e.date between p_from and p_to group by a.code, a.name having sum(l.debit - l.credit) <> 0 order by sum(l.debit - l.credit) desc limit 12) t),
    'ccs', (select coalesce(jsonb_agg(x order by (x->>'v')::numeric desc), '[]') from (select jsonb_build_object('n', coalesce(c.name, '—'), 'v', sum(l.debit - l.credit)) x
       from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
       left join public.cost_centers c on c.id = l.cost_center_id
      where l.company_id = p_company and a.type = 'exp' and e.date between p_from and p_to group by c.name having sum(l.debit - l.credit) <> 0) t),
    'suppliers', (select coalesce(jsonb_agg(x order by (x->>'v')::numeric desc), '[]') from (select jsonb_build_object('n', p.name, 'v', sum(b.total), 'c', count(*)) x
       from public.purchase_bills b join public.parties p on p.id = b.party_id where b.company_id = p_company and b.status = 'posted' and b.date between p_from and p_to
      group by p.name order by sum(b.total) desc limit 10) t),
    'claims', (select coalesce(jsonb_agg(x order by (x->>'v')::numeric desc), '[]') from (select jsonb_build_object('n', coalesce(d.name, '—'), 'k', r.kind, 'v', sum(r.amount), 'c', count(*)) x
       from public.requests r join public.employees e on e.id = r.employee_id left join public.departments d on d.id = e.department_id
      where r.company_id = p_company and r.kind in ('expense','trip') and r.status = 'approved' and coalesce(r.from_date, r.created_at::date) between p_from and p_to
      group by d.name, r.kind) t),
    'pending', (select coalesce(sum(r.amount), 0) from public.requests r where r.company_id = p_company and r.kind in ('expense','trip','advance') and r.status = 'pending'));
end $$;

-- ---------------- 3. business trips: a request kind ----------------
alter table public.journal_entries drop constraint if exists journal_entries_source_check;
alter table public.journal_entries add constraint journal_entries_source_check check (source in ('manual','reversal','sales','purchase','receipt','payment','stock','payroll','payroll_pay','advance','expense','opening','sales_return','purchase_return','asset','depreciation','cheque','closing','petty','trip'));
alter table public.requests drop constraint if exists requests_kind_check;
alter table public.requests add constraint requests_kind_check check (kind in ('leave','permit','cert','advance','resign','settle','expense','update','punch','ticket','visa','purchase','trip'));
create or replace function public.default_route(p_kind text) returns text[] language sql immutable as $$
  select case p_kind
    when 'leave' then array['m','p','h','g'] when 'permit' then array['m','p'] when 'cert' then array['p'] when 'punch' then array['m','p']
    when 'advance' then array['m','p','h','f','g'] when 'resign' then array['m','p','h','g','f']
    when 'settle' then array['p','h','f','g'] when 'expense' then array['m','f','g']
    when 'ticket' then array['m','p','h','f'] when 'visa' then array['m','p','h']
    when 'purchase' then array['m','f','g'] when 'trip' then array['m','p','f']
    else array['p'] end
$$;
-- the per diem of an employee: the grade's rate, else the company default
create or replace function public.per_diem_rate(p_emp uuid, p_abroad boolean) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(case when p_abroad then g.per_diem_out else g.per_diem_in end, case when p_abroad then c.per_diem_out else c.per_diem_in end, 0)
    from public.employees e join public.companies c on c.id = e.company_id left join public.job_grades g on g.id = e.grade_id where e.id = p_emp
$$;
create or replace function public.per_diem_set(p_company uuid, p_in numeric, p_out numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin','hr','finance']);
  update public.companies set per_diem_in = p_in, per_diem_out = p_out where id = p_company;
end $$;

CREATE OR REPLACE FUNCTION public.workflow_set(p_company uuid, p_kind text, p_route text[])
 RETURNS text[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rt text[];
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if p_kind not in ('leave','permit','cert','advance','resign','settle','expense','update','punch','ticket','visa','purchase','trip') then raise exception 'نوع طلب غير معروف'; end if;
  if p_route is null then delete from public.workflows where company_id = p_company and kind = p_kind; return public.default_route(p_kind); end if;
  rt := array(select s from unnest(array['m','b','p','h','f','g']) with ordinality x(s, i) where s = any(p_route) order by i);
  if cardinality(rt) = 0 then raise exception 'اختر مرحلة اعتماد واحدة على الأقل'; end if;
  if p_kind in ('ticket','advance','expense','settle','purchase','trip') and not ('f' = any(rt)) then raise exception 'هذا الطلب يصرف مبلغاً فلا بد أن يمر على المالية'; end if;
  insert into public.workflows(company_id, kind, route) values (p_company, p_kind, rt)
    on conflict (company_id, kind) do update set route = excluded.route;
  return rt;
end $function$;

CREATE OR REPLACE FUNCTION public.submit_request(p_company uuid, p_kind text, p_sub text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_amount numeric DEFAULT NULL::numeric, p_payload jsonb DEFAULT '{}'::jsonb, p_note text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  me uuid := public.my_employee(p_company);
  e public.employees; lt public.leave_types; d int; used int; rt text[]; rid uuid; owner_emp uuid; k text; ev date; bal numeric; g numeric; minst int; v_files jsonb; lim numeric; ps date; pe date; hm uuid; v_rate numeric;
begin
  if me is null then raise exception 'حسابك غير مربوط بسجل موظف' using errcode = '42501'; end if;
  select * into e from public.employees where id = me;
  if e.end_date is not null and e.end_date < current_date then raise exception 'انتهت خدمتك'; end if;
  g := public.gross_wage(e);
  v_files := p_payload->'files'; p_payload := coalesce(p_payload, '{}'::jsonb) - 'files';   -- files go to request_attachments, never into the payload

  if p_kind = 'leave' then
    select * into lt from public.leave_types where code = p_sub;
    if not found then raise exception 'نوع إجازة غير معروف'; end if;
    if p_from is null or p_to is null then raise exception 'حدد تاريخ البداية والنهاية'; end if;
    if p_to < p_from then raise exception 'تاريخ النهاية قبل البداية'; end if;
    d := public.days_between(p_from, p_to);
    -- Reg. Art. 24(2): official holidays inside annual leave are not counted (the leave is extended by them)
    if p_sub = 'annual' then d := d - public.holidays_in(p_company, p_from, p_to); end if;
    if d <= 0 then raise exception 'الفترة كلها عطل رسمية'; end if;
    if exists(select 1 from public.requests where employee_id = me and kind = 'leave' and status in ('pending','approved')
              and p_from <= to_date and p_to >= from_date) then
      raise exception 'الفترة تتداخل مع إجازة سابقة'; end if;
    if lt.gender is not null and lt.gender <> e.gender then raise exception 'هذه الإجازة لا تنطبق عليك'; end if;
    if lt.max_days is not null and d > lt.max_days and lt.code <> 'sick' then raise exception 'الحد الأقصى لهذه الإجازة % يوماً', lt.max_days; end if;
    if lt.min_days is not null and d < lt.min_days then raise exception 'أقل مدة لهذه الإجازة % أيام', lt.min_days; end if;
    if lt.min_service_years is not null and (current_date - e.hire_date) / 365.0 < lt.min_service_years then
      raise exception 'تُمنح هذه الإجازة بعد % سنة خدمة', lt.min_service_years; end if;
    if lt.once_in_service and exists(select 1 from public.requests where employee_id = me and kind='leave' and sub = lt.code and status in ('pending','approved')) then
      raise exception 'هذه الإجازة تُمنح مرة واحدة خلال الخدمة'; end if;
    if lt.notice_days is not null and (p_from - current_date) < lt.notice_days then
      raise exception 'قدّم الطلب قبل % يوماً على الأقل', lt.notice_days; end if;
    -- Art. 113/160: counted from the event date
    if lt.code in ('marriage','death','death2','birth','iddah','iddahn') then
      ev := nullif(p_payload->>'event_date','')::date;
      if ev is null then raise exception 'أدخل تاريخ الواقعة (الزواج/الوفاة/الولادة)'; end if;
      if ev > current_date + 30 then raise exception 'تاريخ الواقعة غير صحيح'; end if;
      if p_from < ev then raise exception 'تبدأ الإجازة من تاريخ الواقعة أو بعده'; end if;
      if lt.code = 'birth' and p_to > ev + 6 then raise exception 'إجازة المولود تؤخذ خلال 7 أيام من تاريخ الولادة — م113'; end if;
      if lt.code in ('marriage','death','death2') and p_to > ev + lt.max_days - 1 then
        raise exception 'تُحتسب هذه الإجازة من تاريخ الواقعة، فتنتهي في % — م113', ev + lt.max_days - 1; end if;
      if lt.code in ('iddah','iddahn') and p_from <> ev then raise exception 'تبدأ إجازة العدة من تاريخ الوفاة — م160'; end if;
    end if;
    if lt.code = 'sick' then
      used := public.sick_days_used(me, p_from);
      if used + d > 120 then raise exception 'تتجاوز 120 يوماً مرضية خلال سنة الإجازة المرضية (المستخدم %)', used; end if;
    end if;
    if lt.code = 'annual' then   -- Art. 109: accrued balance
      select x.taken, floor(x.accrued - x.taken) into used, bal from public.annual_leave_raw(e, p_to) x;
      if d > bal then raise exception 'رصيدك المستحق حتى نهاية الإجازة % يوماً', greatest(bal, 0); end if;
    end if;
    -- Art. 115: exam days are paid leave; only the exams of a repeated year are unpaid
    if lt.code = 'exam' then
      if coalesce(p_payload->>'exam_mode', 'approved') not in ('approved','repeat') then
        raise exception 'حدد حالة الدراسة: سنة غير معادة أو سنة معادة — م115'; end if;
      if p_payload->>'exam_mode' = 'repeat' then p_sub := 'unpaid'; end if;
      p_payload := coalesce(p_payload, '{}'::jsonb) || jsonb_build_object('exam', true, 'exam_mode', coalesce(p_payload->>'exam_mode', 'approved'));
    end if;
    -- Reg. Art. 22-bis: compensatory leave is taken from the hours earned for overtime (8 hours a day)
    if lt.doc_label is not null and (v_files is null or jsonb_typeof(v_files) <> 'array' or jsonb_array_length(v_files) = 0) then
      raise exception 'أرفق المستند المطلوب: %', lt.doc_label; end if;
    if nullif(regexp_replace(coalesce(p_payload->>'doc_ref', ''), '\s', '', 'g'), '') is not null then
      p_payload := p_payload || jsonb_build_object('doc_ref', upper(left(regexp_replace(p_payload->>'doc_ref', '\s', '', 'g'), 40)));
    else p_payload := p_payload - 'doc_ref'; end if;
    if lt.ref_required and length(coalesce(p_payload->>'doc_ref', '')) < 5 then raise exception 'اكتب %', lt.ref_label; end if;
    if lt.code = 'comp' then
      select balance_hours into bal from public.comp_balance(me);
      if d * 8 > coalesce(bal, 0) then raise exception 'رصيد الإجازة التعويضية % ساعة (% يوم)', coalesce(bal, 0), floor(coalesce(bal, 0) / 8); end if;
    end if;
  elsif p_kind = 'permit' then
    if coalesce((p_payload->>'hours')::numeric, 0) <= 0 or (p_payload->>'hours')::numeric > 4 then
      raise exception 'الاستئذان من دقائق حتى 4 ساعات'; end if;
    if p_from is null then raise exception 'حدد تاريخ الاستئذان'; end if;
    -- the company's monthly allowance of permit hours (counted in the payroll month of the date)
    select permit_hours_month into lim from public.companies where id = p_company;
    if lim is not null then
      select x.ps, x.pe into ps, pe from public.att_month_of(p_company, p_from) x;
      select coalesce(sum((payload->>'hours')::numeric), 0) into bal from public.requests
       where employee_id = me and kind = 'permit' and status in ('pending','approved') and from_date between ps and pe;
      if bal + (p_payload->>'hours')::numeric > lim then
        raise exception 'تجاوزت حد الاستئذان الشهري (% ساعة) — المتبقي لك % ساعة', lim, greatest(lim - bal, 0); end if;
    end if;
  elsif p_kind = 'punch' then
    -- forgotten fingerprint: the employee states the missing check-in/out time; HR (or the route) approves it
    if not exists(select 1 from public.companies where id = p_company and att_enabled) then raise exception 'تسجيل الحضور غير مفعّل في منشأتك'; end if;
    if p_from is null or p_from > public.riyadh_today() then raise exception 'حدد يوماً مضى'; end if;
    if p_from < public.riyadh_today() - 30 then raise exception 'طلب نسيان البصمة خلال 30 يوماً من اليوم'; end if;
    if nullif(p_payload->>'in', '') is null and nullif(p_payload->>'out', '') is null then raise exception 'اكتب وقت الحضور أو الانصراف'; end if;
    if coalesce(p_payload->>'in', '') <> '' and p_payload->>'in' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'وقت الحضور غير صحيح'; end if;
    if coalesce(p_payload->>'out', '') <> '' and p_payload->>'out' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'وقت الانصراف غير صحيح'; end if;
    if nullif(p_payload->>'in', '') is null and not exists(select 1 from public.attendance where employee_id = me and day = p_from) then
      raise exception 'لا يوجد تسجيل حضور في هذا اليوم — اكتب وقت الحضور'; end if;
    if exists(select 1 from public.requests where employee_id = me and kind = 'punch' and status = 'pending' and from_date = p_from) then
      raise exception 'لديك طلب نسيان بصمة لهذا اليوم قيد المراجعة'; end if;
    select punch_fix_month into lim from public.companies where id = p_company;
    if lim is not null then
      select x.ps, x.pe into ps, pe from public.att_month_of(p_company, p_from) x;
      if (select count(*) from public.requests where employee_id = me and kind = 'punch' and status in ('pending','approved') and from_date between ps and pe) >= lim then
        raise exception 'تجاوزت حد طلبات نسيان البصمة الشهري (% مرات)', lim::int; end if;
    end if;
    p_to := p_from;
    p_payload := jsonb_build_object('in', nullif(p_payload->>'in', ''), 'out', nullif(p_payload->>'out', ''));
  elsif p_kind in ('advance','expense') then
    if coalesce(p_amount,0) <= 0 then raise exception 'أدخل المبلغ'; end if;
    if p_kind = 'advance' then
      if p_amount > e.basic then raise exception 'السلفة لا تزيد على الراتب الأساسي (%)', e.basic; end if;
      minst := ceil(p_amount / (g * 0.10));
      if coalesce((p_payload->>'inst')::int, 1) < minst then
        raise exception 'القسط الشهري لا يزيد على 10%% من الأجر (% ريال) — اختر % أقساط على الأقل (م92)', round(g * 0.10, 2), minst; end if;
      if coalesce((p_payload->>'inst')::int, 1) > 24 then raise exception 'عدد الأقساط حتى 24'; end if;
    end if;
  elsif p_kind = 'resign' then   -- Art. 79-bis: no deferred date; ends on acceptance
    if p_to is not null and p_to > current_date then raise exception 'لا يصح تحديد تاريخ مؤجل للاستقالة — م79 مكرر'; end if;
    if exists(select 1 from public.requests where employee_id = me and kind = 'resign' and status = 'pending') then
      raise exception 'لديك طلب استقالة قيد المعالجة'; end if;
    p_from := current_date; p_to := null;
  elsif p_kind = 'ticket' then
    if p_from is not null and p_from < current_date then raise exception 'تاريخ السفر قبل اليوم'; end if;
    p_to := coalesce(p_to, p_from);
  elsif p_kind = 'trip' then
    if nullif(btrim(coalesce(p_payload->>'dest', '')), '') is null then raise exception 'اكتب وجهة الرحلة'; end if;
    if nullif(btrim(coalesce(p_payload->>'purpose', '')), '') is null then raise exception 'اكتب الغرض من الرحلة'; end if;
    if p_from is null or p_to is null then raise exception 'حدد تاريخ الذهاب والعودة'; end if;
    if p_to < p_from then raise exception 'تاريخ العودة قبل الذهاب'; end if;
    d := p_to - p_from + 1;
    if d > 90 then raise exception 'مدة الرحلة حتى 90 يوما'; end if;
    if exists(select 1 from public.requests where employee_id = me and kind = 'trip' and status in ('pending','approved') and p_from <= to_date and p_to >= from_date) then
      raise exception 'الفترة تتداخل مع رحلة عمل سابقة'; end if;
    v_rate := public.per_diem_rate(me, coalesce((p_payload->>'abroad')::boolean, false));
    p_amount := round(v_rate * d, 2);
    p_payload := jsonb_build_object('dest', left(btrim(p_payload->>'dest'), 120), 'purpose', left(btrim(p_payload->>'purpose'), 300),
      'abroad', coalesce((p_payload->>'abroad')::boolean, false), 'rate', v_rate, 'transport', coalesce(nullif(p_payload->>'transport', ''), 'none'));
  elsif p_kind = 'visa' then
    if p_from is not null and p_to is not null and p_to >= p_from then d := public.days_between(p_from, p_to); end if;
  elsif p_kind = 'update' then
    if p_payload is null or p_payload = '{}'::jsonb then raise exception 'حدد البيانات المطلوب تعديلها'; end if;
    for k in select jsonb_object_keys(p_payload) loop
      if not (k = any(public.update_request_fields())) then raise exception 'لا يمكن طلب تعديل الحقل «%»', k; end if;
    end loop;
    if p_payload ? 'iban' and coalesce(p_payload->>'iban','') !~ '^SA[0-9]{22}$' then raise exception 'الآيبان يبدأ بـ SA ويليه 22 رقماً'; end if;
    if p_payload ? 'email' and coalesce(p_payload->>'email','') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'البريد الإلكتروني غير صحيح'; end if;
    if p_payload ? 'phone' and coalesce(p_payload->>'phone','') !~ '^(05[0-9]{8}|\+9665[0-9]{8})$' then raise exception 'رقم الجوال بصيغة 05XXXXXXXX'; end if;
    if p_payload ? 'short_address' and upper(replace(coalesce(p_payload->>'short_address',''), ' ', '')) !~ '^([A-Z]{4}[0-9]{4})?$' then raise exception 'العنوان المختصر 4 حروف و4 أرقام مثل RRRD2929'; end if;
    if p_payload ? 'marital_status' and coalesce(p_payload->>'marital_status','') not in ('', 'single','married','divorced','widowed') then raise exception 'الحالة الاجتماعية غير صحيحة'; end if;
    if p_payload ? 'dependents' and coalesce(p_payload->>'dependents','') !~ '^([0-9]|[12][0-9]|30)?$' then raise exception 'عدد المرافقين بين 0 و30'; end if;
    if p_payload ? 'emergency_phone' and coalesce(p_payload->>'emergency_phone','') !~ '^(\+?[0-9 ]{7,16})?$' then raise exception 'رقم جوال الطوارئ غير صحيح'; end if;
    if exists(select 1 from public.requests where employee_id = me and kind = 'update' and status = 'pending') then
      raise exception 'لديك طلب تعديل بيانات قيد المراجعة'; end if;
  end if;

  if p_kind in ('leave','ticket','visa') then p_payload := public.travel_check(e, p_kind, p_from, p_to, p_payload); end if;
  select route into rt from public.workflows where company_id = p_company and kind = p_kind;
  rt := coalesce(rt, public.default_route(p_kind));
  -- a ticket inside a leave request is paid by finance, so finance joins the route (before the general manager)
  if p_kind = 'leave' and p_payload ? 'ticket' and not ('f' = any(rt)) then
    rt := case when 'g' = any(rt) then array_remove(rt, 'g') || array['f','g'] else rt || array['f'] end; end if;
  -- the HR-manager step applies only when one is appointed, and never to his own request
  select hr_manager into hm from public.companies where id = p_company;
  if hm is null or exists(select 1 from public.members m where m.company_id = p_company and m.user_id = hm and m.employee_id = me) then
    rt := array_remove(rt, 'h'); end if;
  select m.employee_id into owner_emp from public.members m where m.company_id = p_company and m.role = 'owner' limit 1;
  if e.manager_id is null then rt := array_remove(rt, 'm'); end if;
  if me = owner_emp or (e.manager_id = owner_emp and 'm' = any(rt)) then rt := array_remove(rt, 'g'); end if;

  insert into public.requests(company_id, employee_id, kind, sub, from_date, to_date, days, amount, payload, note, route, step, status)
  values (p_company, me, p_kind, p_sub, p_from, p_to, d, p_amount, coalesce(p_payload,'{}'), nullif(trim(p_note),''), rt, 0,
          case when cardinality(rt) = 0 then 'approved' else 'pending' end)
  returning id into rid;
  insert into public.request_actions(request_id, actor, action) values (rid, auth.uid(), 'submitted');
  perform public.attach_files(rid, v_files);
  if cardinality(rt) = 0 then perform public.on_request_approved(rid); end if;
  return rid;
end $function$;

CREATE OR REPLACE FUNCTION public.on_request_approved(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.requests; nm text;
begin
  select * into r from public.requests where id = p_id;
  select full_name into nm from public.employees where id = r.employee_id;
  if r.kind = 'advance' then
    perform public.post_journal(r.company_id, current_date, 'سلفة — ' || nm, 'advance', r.id,
      jsonb_build_array(jsonb_build_object('a','1500','d',r.amount), jsonb_build_object('a','1120','c',r.amount)));
  elsif r.kind = 'expense' then
    perform public.post_journal(r.company_id, current_date, 'مطالبة مصروفات — ' || nm, 'expense', r.id,
      jsonb_build_array(jsonb_build_object('a','5500','d',r.amount), jsonb_build_object('a','1120','c',r.amount)));
  elsif r.kind = 'trip' and coalesce(r.amount, 0) > 0 then
    insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header)
    values (r.company_id, '5230', 'بدل انتداب ورحلات العمل', 'Business travel per diem', 'exp', '5000', false) on conflict do nothing;
    perform public.post_journal(r.company_id, current_date, 'بدل انتداب — ' || nm || ' — ' || coalesce(r.payload->>'dest', ''), 'trip', r.id,
      jsonb_build_array(jsonb_build_object('a','5230','d',r.amount,'cc',(select cost_center_id from public.employees where id = r.employee_id)), jsonb_build_object('a','1120','c',r.amount)));
  elsif r.kind = 'resign' then
    -- ends on acceptance, or at the end of the 30 days, or at the end of a deferral (Art. 79-bis(2))
    update public.requests set to_date = least(current_date, coalesce(nullif(r.payload->>'defer_until', '')::date, r.created_at::date + 30)) where id = p_id;
    update public.employees set end_date = least(current_date, coalesce(nullif(r.payload->>'defer_until', '')::date, r.created_at::date + 30)), end_reason = 'resign' where id = r.employee_id;
  elsif r.kind = 'punch' then
    perform public.punch_apply(r.id);
  elsif r.kind = 'update' then
    update public.employees set
      phone = case when r.payload ? 'phone' then r.payload->>'phone' else phone end,
      email = case when r.payload ? 'email' then r.payload->>'email' else email end,
      iban  = case when r.payload ? 'iban'  then r.payload->>'iban'  else iban end
    where id = r.employee_id;
    perform public.emp_apply_profile(r.company_id, r.employee_id, r.payload - 'phone' - 'email' - 'iban', '');
  end if;
  if r.kind in ('leave','ticket') and r.payload ? 'ticket' then
    insert into public.travel_tickets(company_id, employee_id, request_id, mode, persons, estimate)
    select r.company_id, r.employee_id, r.id, r.payload->'ticket'->>'mode', (r.payload->'ticket'->>'persons')::int,
           e.ticket_amount * (r.payload->'ticket'->>'persons')::int from public.employees e where e.id = r.employee_id;
  end if;
  if r.kind in ('leave','visa') and r.payload ? 'visa' then
    insert into public.exit_visas(company_id, employee_id, request_id, visa_type, travel_on, return_on)
    values (r.company_id, r.employee_id, r.id, r.payload->'visa'->>'type', r.from_date, r.to_date);
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public.seed_company(p_company uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.accounts(company_id, code, name, type, parent_code, is_header) values
  (p_company,'1000','الأصول','asset',null,true),(p_company,'1100','النقدية والبنوك','asset','1000',true),
  (p_company,'1110','الصندوق','asset','1100',false),(p_company,'1120','البنك','asset','1100',false),
  (p_company,'1200','العملاء (ذمم مدينة)','asset','1000',false),(p_company,'1300','المخزون','asset','1000',false),
  (p_company,'1400','ضريبة القيمة المضافة — مدخلات','asset','1000',false),(p_company,'1500','سلف الموظفين','asset','1000',false),
  (p_company,'1600','مصروفات مدفوعة مقدماً','asset','1000',false),(p_company,'1700','الأصول الثابتة','asset','1000',false),
  (p_company,'2000','الخصوم','liab',null,true),(p_company,'2100','الموردون (ذمم دائنة)','liab','2000',false),
  (p_company,'2200','ضريبة القيمة المضافة — مخرجات','liab','2000',false),(p_company,'2300','رواتب مستحقة','liab','2000',false),
  (p_company,'2400','التأمينات الاجتماعية المستحقة','liab','2000',false),(p_company,'2500','مخصص مكافأة نهاية الخدمة','liab','2000',false),
  (p_company,'3000','حقوق الملكية','equity',null,true),(p_company,'3100','رأس المال','equity','3000',false),
  (p_company,'3200','الأرباح المبقاة','equity','3000',false),
  (p_company,'4000','الإيرادات','rev',null,true),(p_company,'4100','إيرادات المبيعات','rev','4000',false),
  (p_company,'4200','إيرادات الخدمات','rev','4000',false),(p_company,'4900','إيرادات أخرى','rev','4000',false),
  (p_company,'5000','المصروفات','exp',null,true),(p_company,'5100','تكلفة البضاعة المباعة','exp','5000',false),
  (p_company,'5200','الرواتب والأجور','exp','5000',false),(p_company,'5210','حصة المنشأة في التأمينات الاجتماعية','exp','5000',false),(p_company,'5300','الإيجار','exp','5000',false),
  (p_company,'5400','المرافق والاتصالات','exp','5000',false),(p_company,'5500','مصروفات إدارية وعمومية','exp','5000',false),(p_company,'5230','بدل انتداب ورحلات العمل','exp','5000',false),
  (p_company,'5600','فروقات المخزون','exp','5000',false),(p_company,'5900','مصروفات أخرى','exp','5000',false)
  on conflict do nothing;
  insert into public.finance_permissions(company_id, role, perm)
  select p_company, r, p from (values ('accountant','sales'),('accountant','purch'),('accountant','stock'),('accountant','items'),('accountant','je'),
                                      ('storekeeper','stock'),('storekeeper','stockadj'),('storekeeper','items')) v(r,p)
  on conflict do nothing;
end $function$;

insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header)
  select a.company_id, '5230', 'بدل انتداب ورحلات العمل', 'Business travel per diem', 'exp', '5000', false from public.accounts a where a.code = '5000'
  on conflict do nothing;

revoke all on function public.budget_position(uuid, uuid, text, numeric, date) from public, anon, authenticated;
revoke all on function public.requests_budget_guard() from public, anon;
revoke all on function public.request_budget_account(text) from public, anon;
revoke all on function public.request_budget(uuid) from public, anon;
revoke all on function public.budget_block_set(uuid, boolean) from public, anon;
revoke all on function public.supplier_inbox_review(uuid, boolean, text) from public, anon;
revoke all on function public.supplier_inbox_link(uuid, uuid) from public, anon;
revoke all on function public.po_match(uuid) from public, anon;
revoke all on function public.spend_summary(uuid, date, date) from public, anon;
revoke all on function public.per_diem_rate(uuid, boolean) from public, anon;
revoke all on function public.per_diem_set(uuid, numeric, numeric) from public, anon;
grant execute on function public.request_budget(uuid), public.budget_block_set(uuid, boolean), public.supplier_inbox_review(uuid, boolean, text),
  public.supplier_inbox_link(uuid, uuid), public.po_match(uuid), public.spend_summary(uuid, date, date), public.per_diem_rate(uuid, boolean),
  public.per_diem_set(uuid, numeric, numeric) to authenticated;
