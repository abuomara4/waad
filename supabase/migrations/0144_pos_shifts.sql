-- Point of sale, phase two: cashier shifts, discounts with a limit, payment by cash, card, cheque or on credit (or a mix). A cashier opens a shift with the cash float
-- in the drawer; every till sale is made through pos_sale on that shift (the invoice carries pos_shift_id and the discount it
-- gave); closing the shift counts the cash: expected = float + cash taken; a shortage or overage is posted at once
-- (Dr / Cr 1110 cash against 5970 «عجز وزيادة الصندوق», journal source 'pos') and the Z report is printed. Discounts lower the
-- line price below the item's sale price; above the company's limit (companies.pos_max_disc, default 10%) only the owner,
-- admins and finance may sell.

alter table public.companies add column if not exists pos_max_disc numeric(5,2) not null default 10 check (pos_max_disc between 0 and 100);
alter table public.sales_invoices add column if not exists pos_shift_id uuid;
alter table public.sales_invoices add column if not exists pos_discount numeric(14,2);

create table if not exists public.pos_shifts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  opened_by uuid not null default auth.uid() references auth.users(id),
  opened_at timestamptz not null default now(),
  opening_float numeric(14,2) not null default 0 check (opening_float >= 0),
  status text not null default 'open' check (status in ('open','closed')),
  closed_at timestamptz, closed_by uuid references auth.users(id),
  invoices int, gross numeric(14,2), discounts numeric(14,2), cash numeric(14,2), card numeric(14,2), cheque numeric(14,2), credit numeric(14,2),
  expected_cash numeric(14,2), counted_cash numeric(14,2), difference numeric(14,2), entry_id uuid references public.journal_entries(id),
  note text check (note is null or length(note) <= 500),
  unique (company_id, no)
);
create unique index if not exists pos_shifts_one_open on public.pos_shifts(company_id, opened_by) where status = 'open';
create index if not exists pos_shifts_company on public.pos_shifts(company_id, opened_at desc);
alter table public.sales_invoices drop constraint if exists sales_invoices_pos_shift_fk;
alter table public.sales_invoices add constraint sales_invoices_pos_shift_fk foreign key (pos_shift_id) references public.pos_shifts(id) on delete set null;
create index if not exists sales_invoices_pos_shift on public.sales_invoices(pos_shift_id) where pos_shift_id is not null;
alter table public.pos_shifts enable row level security;
drop policy if exists pos_shifts_read on public.pos_shifts;
create policy pos_shifts_read on public.pos_shifts for select
  using (public.has_role(company_id, array['owner','admin','finance']) or (opened_by = auth.uid() and public.is_member(company_id)));
revoke all on public.pos_shifts from anon, authenticated;
grant select on public.pos_shifts to authenticated;

alter table public.journal_entries drop constraint if exists journal_entries_source_check;
alter table public.journal_entries add constraint journal_entries_source_check check (source in ('manual','reversal','sales','purchase','receipt','payment',
  'stock','payroll','payroll_pay','advance','expense','opening','sales_return','purchase_return','asset','depreciation','cheque','closing','petty','trip','vehicle',
  'prepaid','bank','loan','guarantee','zakat','project','pos'));

-- the shift and the discount reach the invoice only from pos_sale (GUC), never from the app
create or replace function public.sales_invoices_pos() returns trigger language plpgsql as $$
begin
  new.pos_shift_id := nullif(current_setting('waad.pos_shift', true), '')::uuid;
  new.pos_discount := case when new.pos_shift_id is not null then nullif(current_setting('waad.pos_disc', true), '')::numeric end;
  return new;
end $$;
drop trigger if exists sales_invoices_pos on public.sales_invoices;
create trigger sales_invoices_pos before insert on public.sales_invoices for each row execute function public.sales_invoices_pos();
create or replace function public.sales_invoices_pos_lock() returns trigger language plpgsql as $$
begin
  if (new.pos_shift_id, new.pos_discount) is distinct from (old.pos_shift_id, old.pos_discount) and not public.purging() then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  return new;
end $$;
drop trigger if exists sales_invoices_pos_lock on public.sales_invoices;
create trigger sales_invoices_pos_lock before update of pos_shift_id, pos_discount on public.sales_invoices for each row execute function public.sales_invoices_pos_lock();

create or replace function public.pos_shift_open(p_company uuid, p_float numeric) returns uuid
language plpgsql security definer set search_path = public as $$
declare sid uuid;
begin
  perform public.require_fin(p_company, 'sales');
  if coalesce(p_float, 0) < 0 then raise exception 'رصيد الصندوق لا يكون سالبا'; end if;
  if exists(select 1 from public.pos_shifts where company_id = p_company and opened_by = auth.uid() and status = 'open') then raise exception 'لديك وردية مفتوحة'; end if;
  insert into public.pos_shifts(company_id, no, opening_float) values (p_company, public.next_doc_no(p_company, 'SHF'), round(coalesce(p_float, 0), 2)) returning id into sid;
  return sid;
end $$;

-- a till sale on the cashier's open shift. p_doc = {party, lines:[{item, qty, price}]}; p_card = paid by card, p_cash = paid in
-- cash (the change is not recorded), p_cheque = {amount, cheque_no, bank, due_date} — a customer cheque through the cheques module
-- (held in 1150 until it clears; a registered customer only, so a bounced cheque is owed by someone known); what is left is on
-- credit. Prices under the item's sale price are a discount, within the limit.
create or replace function public.pos_sale(p_company uuid, p_shift uuid, p_doc jsonb, p_cash numeric, p_card numeric, p_cheque jsonb default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare s public.pos_shifts; l jsonb; it public.items; lim numeric; disc numeric := 0; pr numeric; q numeric; iid uuid; tot numeric;
  ca numeric := round(coalesce(p_cash, 0), 2); cd numeric := round(coalesce(p_card, 0), 2); pty uuid := nullif(p_doc->>'party', '')::uuid;
  cq numeric := round(coalesce((p_cheque->>'amount')::numeric, 0), 2);
begin
  perform public.require_fin(p_company, 'sales');
  select * into s from public.pos_shifts where id = p_shift and company_id = p_company;
  if not found or s.status <> 'open' or s.opened_by <> auth.uid() then raise exception 'افتح ورديتك أولا'; end if;
  if ca < 0 or cd < 0 or cq < 0 then raise exception 'المبلغ لا يكون سالبا'; end if;
  if cq > 0 and exists(select 1 from public.parties where id = pty and name = 'عميل نقدي') then raise exception 'الدفع بشيك لعميل مسجّل — اختر العميل'; end if;
  select pos_max_disc into lim from public.companies where id = p_company;
  for l in select x from jsonb_array_elements(coalesce(p_doc->'lines', '[]')) x loop
    select * into it from public.items where id = nullif(l->>'item', '')::uuid and company_id = p_company;
    if not found then raise exception 'صنف غير موجود'; end if;
    pr := round((l->>'price')::numeric, 2); q := (l->>'qty')::numeric;
    if pr is null or q is null or q <= 0 or pr < 0 then raise exception 'تحقق من الكمية والسعر'; end if;
    if it.sale_price > 0 and pr < it.sale_price then
      if (1 - pr / it.sale_price) * 100 > lim + 0.005 and not public.has_role(p_company, array['owner','admin','finance']) then
        raise exception 'الخصم على «%» أكبر من الحد المسموح (%)', it.name, lim || '%'; end if;
      disc := disc + round(q * (it.sale_price - pr), 2);
    end if;
  end loop;
  perform set_config('waad.pos_shift', p_shift::text, true); perform set_config('waad.pos_disc', disc::text, true);
  iid := public.post_sales_invoice_sn(p_company, jsonb_build_object('party', pty, 'date', current_date, 'due', current_date, 'lines', p_doc->'lines'));
  perform set_config('waad.pos_shift', '', true); perform set_config('waad.pos_disc', '', true);
  select total into tot from public.sales_invoices where id = iid;
  if ca + cd + cq > tot + 0.005 then raise exception 'المدفوع أكبر من الإجمالي'; end if;
  if cq > 0 then perform public.cheque_save(p_company, jsonb_build_object('direction', 'in', 'party', pty, 'invoice', iid, 'amount', cq, 'issue_date', current_date,
    'due_date', coalesce(nullif(p_cheque->>'due_date', ''), current_date::text), 'cheque_no', p_cheque->>'cheque_no', 'bank', p_cheque->>'bank', 'note', 'نقطة البيع')); end if;
  if cd > 0 then perform public.record_payment(p_company, jsonb_build_object('direction', 'in', 'party', pty, 'invoice', iid, 'amount', cd, 'date', current_date, 'account', '1120')); end if;
  if ca > 0 then perform public.record_payment(p_company, jsonb_build_object('direction', 'in', 'party', pty, 'invoice', iid, 'amount', ca, 'date', current_date, 'account', '1110')); end if;
  return iid;
end $$;

-- the shift's figures so far (the cashier, or management)
create or replace function public.pos_shift_summary(p_shift uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare s public.pos_shifts; r jsonb;
begin
  select * into s from public.pos_shifts where id = p_shift;
  if not found or not (s.opened_by = auth.uid() and public.is_member(s.company_id) or public.has_role(s.company_id, array['owner','admin','finance'])) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  with inv as (select i.* from public.sales_invoices i where i.pos_shift_id = p_shift and i.status = 'posted'),
  pay as (select y.* from public.payments y join inv on inv.id = y.invoice_id where y.direction = 'in')
  select jsonb_build_object('id', s.id, 'no', s.no, 'status', s.status, 'opened_at', s.opened_at, 'closed_at', s.closed_at, 'opening_float', s.opening_float,
    'invoices', (select count(*) from inv), 'gross', coalesce((select sum(total) from inv), 0), 'discounts', coalesce((select sum(pos_discount) from inv), 0),
    'cash', coalesce((select sum(amount) from pay where account_code = '1110'), 0), 'card', coalesce((select sum(amount) from pay where account_code = '1120'), 0),
    'cheque', coalesce((select sum(amount) from pay where account_code = '1150'), 0),
    'credit', coalesce((select sum(total) from inv), 0) - coalesce((select sum(amount) from pay), 0),
    'expected_cash', s.opening_float + coalesce((select sum(amount) from pay where account_code = '1110'), 0),
    'counted_cash', s.counted_cash, 'difference', s.difference, 'note', s.note,
    'cashier', (select coalesce(e.full_name, u.email::text) from auth.users u left join public.members m on m.user_id = u.id and m.company_id = s.company_id
                 left join public.employees e on e.id = m.employee_id where u.id = s.opened_by)) into r;
  return r;
end $$;

-- close: the cash counted; a shortage or overage is posted against 5970
create or replace function public.pos_shift_close(p_shift uuid, p_counted numeric, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare s public.pos_shifts; m jsonb; diff numeric; eid uuid;
begin
  select * into s from public.pos_shifts where id = p_shift for update;
  if not found or s.status <> 'open' then raise exception 'الوردية غير مفتوحة'; end if;
  if not (s.opened_by = auth.uid() and public.fin_can(s.company_id, 'sales') or public.has_role(s.company_id, array['owner','admin','finance'])) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_counted is null or p_counted < 0 then raise exception 'أدخل النقد المعدود في الصندوق'; end if;
  m := public.pos_shift_summary(p_shift);
  diff := round(p_counted - (m->>'expected_cash')::numeric, 2);
  if diff <> 0 then
    insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header)
    select s.company_id, '5970', 'عجز وزيادة الصندوق', 'Cash over and short', 'exp', '5000', false
     where not exists(select 1 from public.accounts where company_id = s.company_id and code = '5970');
    eid := public.post_journal(s.company_id, current_date, 'فرق صندوق — وردية ' || s.no, 'pos', s.id,
      case when diff < 0 then jsonb_build_array(jsonb_build_object('a', '5970', 'd', -diff), jsonb_build_object('a', '1110', 'c', -diff))
           else jsonb_build_array(jsonb_build_object('a', '1110', 'd', diff), jsonb_build_object('a', '5970', 'c', diff)) end);
  end if;
  update public.pos_shifts set status = 'closed', closed_at = now(), closed_by = auth.uid(), invoices = (m->>'invoices')::int, gross = (m->>'gross')::numeric,
    discounts = (m->>'discounts')::numeric, cash = (m->>'cash')::numeric, card = (m->>'card')::numeric, cheque = (m->>'cheque')::numeric, credit = (m->>'credit')::numeric,
    expected_cash = (m->>'expected_cash')::numeric, counted_cash = round(p_counted, 2), difference = diff, entry_id = eid, note = nullif(btrim(coalesce(p_note, '')), '')
   where id = p_shift;
  return public.pos_shift_summary(p_shift);
end $$;

revoke all on function public.sales_invoices_pos(), public.sales_invoices_pos_lock() from public, anon, authenticated;
revoke all on function public.pos_shift_open(uuid, numeric), public.pos_sale(uuid, uuid, jsonb, numeric, numeric, jsonb), public.pos_shift_summary(uuid), public.pos_shift_close(uuid, numeric, text) from public, anon;
grant execute on function public.pos_shift_open(uuid, numeric), public.pos_sale(uuid, uuid, jsonb, numeric, numeric, jsonb), public.pos_shift_summary(uuid), public.pos_shift_close(uuid, numeric, text) to authenticated;
notify pgrst, 'reload schema';
