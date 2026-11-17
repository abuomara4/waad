-- 0114 — Waad's own invoices for its subscriptions (owner's decision, 2026-11-17)
-- * every payment recorded in the admin site gets a number W-YYYY-NNNN (consecutive per year, never reused);
-- * the seller's details (Waad: name, VAT number, CR, address) are set once in the admin site «الإيرادات والباقات»;
--   with a VAT number the invoice is a tax invoice: the paid amount includes VAT at the set rate, and it carries the QR code;
--   without one it is a plain invoice with no VAT;
-- * the company's owner and admin see and print their invoices in «إعدادات المنشأة»; the team prints them from the company page.
-- The buyer shown is the company's name, VAT number, CR and city — billing data, no company records.

alter table public.platform_settings
  add column if not exists inv_name text check (inv_name is null or length(inv_name) <= 120),
  add column if not exists inv_vat text check (inv_vat is null or inv_vat ~ '^3\d{13}3$'),
  add column if not exists inv_cr text check (inv_cr is null or length(inv_cr) <= 30),
  add column if not exists inv_address text check (inv_address is null or length(inv_address) <= 200),
  add column if not exists inv_vat_rate numeric(5,2) not null default 15 check (inv_vat_rate between 0 and 100);
alter table public.platform_payments add column if not exists inv_no text unique;

create or replace function public.platform_payments_number() returns trigger language plpgsql security definer set search_path = public as $$
declare y text := to_char(coalesce(new.paid_on, current_date), 'YYYY'); n int;
begin
  if new.inv_no is null then
    perform pg_advisory_xact_lock(hashtext('waad_inv_' || y));
    select coalesce(max(substr(inv_no, 8)::int), 0) + 1 into n from public.platform_payments where inv_no like 'W-' || y || '-%';
    new.inv_no := 'W-' || y || '-' || lpad(n::text, 4, '0');
  end if;
  return new;
end $$;
drop trigger if exists platform_payments_number on public.platform_payments;
create trigger platform_payments_number before insert on public.platform_payments for each row execute function public.platform_payments_number();
-- payments already recorded get their numbers in order
do $$ declare r record; y text; n int; begin
  for r in select id, paid_on from public.platform_payments where inv_no is null order by paid_on, created_at loop
    y := to_char(r.paid_on, 'YYYY');
    select coalesce(max(substr(inv_no, 8)::int), 0) + 1 into n from public.platform_payments where inv_no like 'W-' || y || '-%';
    update public.platform_payments set inv_no = 'W-' || y || '-' || lpad(n::text, 4, '0') where id = r.id;
  end loop; end $$;

-- one invoice: for the Waad team, or the company's owner/admin
create or replace function public.waad_invoice(p_payment uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p public.platform_payments; s public.platform_settings; c public.companies; rate numeric; net numeric;
begin
  select * into p from public.platform_payments where id = p_payment;
  if not found then raise exception 'الفاتورة غير موجودة'; end if;
  if not (public.is_platform_admin() or public.has_role(p.company_id, array['owner','admin'])) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  select * into s from public.platform_settings where id;
  select * into c from public.companies where id = p.company_id;
  rate := case when s.inv_vat is not null then s.inv_vat_rate else 0 end;
  net := round(p.amount / (1 + rate / 100), 2);
  return jsonb_build_object('id', p.id, 'no', p.inv_no, 'date', p.paid_on, 'at', p.created_at, 'method', p.method, 'days', p.days, 'note', p.note,
    'plan', (select name from public.platform_plans where id = p.plan_id),
    'total', p.amount, 'net', net, 'vat', p.amount - net, 'rate', rate, 'tax', s.inv_vat is not null,
    'seller', jsonb_build_object('name', coalesce(s.inv_name, 'وعد'), 'vat', s.inv_vat, 'cr', s.inv_cr, 'address', s.inv_address),
    'buyer', jsonb_build_object('name', coalesce(c.name, p.company_name), 'vat', c.vat_no, 'cr', c.cr_no, 'city', c.city));
end $$;

-- the company's invoices (owner / admin)
create or replace function public.my_waad_invoices(p_company uuid) returns table(id uuid, inv_no text, paid_on date, amount numeric, plan text, days int)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin']);
  return query select p.id, p.inv_no, p.paid_on, p.amount, pl.name, p.days from public.platform_payments p left join public.platform_plans pl on pl.id = p.plan_id
    where p.company_id = p_company order by p.paid_on desc, p.created_at desc;
end $$;

-- the seller's details, set by the team (billing permission)
create or replace function public.platform_invoice_settings() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin perform public.platform_guard();
  return (select jsonb_build_object('inv_name', inv_name, 'inv_vat', inv_vat, 'inv_cr', inv_cr, 'inv_address', inv_address, 'inv_vat_rate', inv_vat_rate) from public.platform_settings where id); end $$;
create or replace function public.platform_invoice_settings_set(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.platform_need('billing');
  if nullif(btrim(p->>'inv_vat'), '') is not null and btrim(p->>'inv_vat') !~ '^3\d{13}3$' then raise exception 'الرقم الضريبي 15 رقما يبدأ وينتهي بـ 3'; end if;
  update public.platform_settings set inv_name = nullif(btrim(p->>'inv_name'), ''), inv_vat = nullif(btrim(p->>'inv_vat'), ''), inv_cr = nullif(btrim(p->>'inv_cr'), ''),
    inv_address = nullif(btrim(p->>'inv_address'), ''), inv_vat_rate = coalesce(nullif(p->>'inv_vat_rate', '')::numeric, 15), updated_at = now() where id;
end $$;

-- the payments list carries the invoice number
drop function if exists public.platform_payments_list(date, date);
create or replace function public.platform_payments_list(p_from date, p_to date) returns table(id uuid, company_id uuid, company text, amount numeric, paid_on date, method text, plan text, days int, note text, inv_no text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.platform_guard();
  return query select p.id, p.company_id, coalesce(c.name, p.company_name), p.amount, p.paid_on, p.method, pl.name, p.days, p.note, p.inv_no
    from public.platform_payments p left join public.companies c on c.id = p.company_id left join public.platform_plans pl on pl.id = p.plan_id
   where p.paid_on between coalesce(p_from, '2000-01-01') and coalesce(p_to, '2999-12-31') order by p.paid_on desc, p.created_at desc;
end $$;

revoke all on function public.platform_payments_number() from public, anon;
revoke all on function public.waad_invoice(uuid) from public, anon;
revoke all on function public.my_waad_invoices(uuid) from public, anon;
revoke all on function public.platform_invoice_settings() from public, anon;
revoke all on function public.platform_invoice_settings_set(jsonb) from public, anon;
revoke all on function public.platform_payments_list(date, date) from public, anon;
grant execute on function public.waad_invoice(uuid), public.my_waad_invoices(uuid), public.platform_invoice_settings(), public.platform_invoice_settings_set(jsonb),
  public.platform_payments_list(date, date) to authenticated;
