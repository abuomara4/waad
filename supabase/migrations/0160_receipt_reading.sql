-- 0160 «قراءة الفاتورة»: an invoice photographed in Waad is read on the device (its ZATCA QR: seller, VAT number, time, total, VAT —
-- app/src/qrread.js, no outside service). What it read is kept with the document as a key so the same invoice is not claimed twice
-- in the same company: expense / trip / purchase requests (payload.receipt.key), petty cash lines (rkey), the supplier inbox (receipt_key).
alter table public.supplier_inbox
  add column if not exists receipt_key text check (receipt_key is null or length(receipt_key) <= 200),
  add column if not exists vat_no text check (vat_no is null or vat_no ~ '^3[0-9]{13}3$'),
  add column if not exists vat numeric(14,2) check (vat is null or vat >= 0);
create index if not exists supplier_inbox_receipt on public.supplier_inbox(company_id, receipt_key) where receipt_key is not null;
create index if not exists requests_receipt on public.requests(company_id, ((payload->'receipt'->>'key'))) where payload ? 'receipt';

-- petty cash lines keep the key of the invoice they came from
create or replace function public.petty_claim_submit(p_fund uuid, p_date date, p_lines jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare f public.petty_funds; l jsonb; ls jsonb := '[]'; a numeric; v numeric; sa numeric := 0; sv numeric := 0; cid uuid; fin boolean;
begin
  select * into f from public.petty_funds where id = p_fund;
  if not found then raise exception 'العهدة غير موجودة'; end if;
  fin := public.fin_can(f.company_id, 'je');
  if not fin and public.my_employee(f.company_id) is distinct from f.employee_id then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if f.status <> 'active' then raise exception 'العهدة مقفلة'; end if;
  if p_date is null or p_date > current_date or p_date < f.opened_on then raise exception 'التاريخ غير صحيح'; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'أضف بنداً واحداً على الأقل'; end if;
  for l in select * from jsonb_array_elements(p_lines) loop
    a := round((l->>'amount')::numeric, 2);
    if coalesce(a, 0) <= 0 then raise exception 'مبلغ البند يجب أن يكون أكبر من صفر'; end if;
    if length(trim(coalesce(l->>'desc',''))) < 2 then raise exception 'اكتب وصف كل بند'; end if;
    if not exists(select 1 from public.accounts where company_id = f.company_id and code = l->>'a' and type = 'exp' and not is_header) then raise exception 'اختر حساب مصروف لكل بند'; end if;
    v := round(coalesce((l->>'vat')::numeric, 0), 2);
    if v < 0 or v > round(a * 0.15, 2) + 0.01 then raise exception 'ضريبة البند لا تتجاوز 15%% من مبلغه'; end if;
    if v > 0 and coalesce(l->>'vat_no','') !~ '^3[0-9]{13}3$' then raise exception 'لاسترداد الضريبة أدخل الرقم الضريبي للمورد (15 رقماً)'; end if;
    ls := ls || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('a', l->>'a', 'desc', trim(l->>'desc'), 'amount', a, 'vat', v, 'ref', nullif(trim(l->>'ref'),''), 'vat_no', nullif(trim(l->>'vat_no'),''),
      'rkey', nullif(left(trim(coalesce(l->>'rkey','')), 200), ''))));
    sa := sa + a; sv := sv + v;
  end loop;
  insert into public.petty_claims(company_id, fund_id, no, date, lines, amount, vat, total)
  values (f.company_id, f.id, public.next_doc_no(f.company_id, 'PCC'), p_date, ls, sa, sv, sa + sv) returning id into cid;
  return cid;
end $$;

-- how many live documents of THIS company already carry the invoice (rejected / cancelled ones do not count);
-- a member asks only about his own company and learns a number, never whose document it is
create or replace function public.receipt_seen(p_company uuid, p_key text) returns int
language plpgsql stable security definer set search_path = public as $$
declare k text := nullif(left(btrim(coalesce(p_key, '')), 200), '');
begin
  if not public.is_member(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if k is null then return 0; end if;
  return (select count(*) from public.requests where company_id = p_company and payload->'receipt'->>'key' = k and status in ('pending','approved'))
       + (select count(*) from public.petty_claims c, jsonb_array_elements(c.lines) x where c.company_id = p_company and c.status <> 'rejected' and x->>'rkey' = k)
       + (select count(*) from public.supplier_inbox where company_id = p_company and receipt_key = k and status <> 'rejected');
end $$;

revoke all on function public.receipt_seen(uuid, text) from public, anon;
grant execute on function public.receipt_seen(uuid, text) to authenticated;
revoke all on function public.petty_claim_submit(uuid, date, jsonb) from public, anon;
grant execute on function public.petty_claim_submit(uuid, date, jsonb) to authenticated;
