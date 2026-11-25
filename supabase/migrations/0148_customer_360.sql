-- Customer 360: one page with everything about a customer — balance and overdue (with aging), sales this year and the last 12
-- months, how fast he pays, open quotations and orders, latest invoices and receipts, returns, open opportunities, active
-- contracts, cheques not yet cleared, and his sales rep. Sales management sees every customer; a sales rep sees his own
-- customers. Documents follow the reader's branches (branch_ok), like the lists they come from.

create or replace function public.customer_360(p_company uuid, p_party uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p public.parties; td date := current_date; y0 date := date_trunc('year', current_date)::date; m date; trend jsonb := '[]';
begin
  select * into p from public.parties where id = p_party and company_id = p_company and kind = 'customer';
  if not found then raise exception 'العميل غير موجود'; end if;
  if not (public.fin_can(p_company, 'sales') or coalesce(p.sales_rep_id = public.my_employee(p_company), false)) then
    raise exception 'ملف العميل لإدارة المبيعات أو مندوبه' using errcode = '42501'; end if;
  for m in select generate_series((date_trunc('month', td) - interval '11 months')::date, date_trunc('month', td)::date, interval '1 month')::date loop
    trend := trend || jsonb_build_object('month', to_char(m, 'YYYY-MM'), 'sales', coalesce((select sum(s.subtotal) from public.sales_invoices s
      where s.company_id = p_company and s.party_id = p_party and s.status = 'posted' and not s.is_opening and s.date between m and (m + interval '1 month - 1 day')::date
        and public.branch_ok(p_company, s.branch_id)), 0));
  end loop;
  return (with inv as (
      select s.*, greatest(s.total - public.paid_on(s.id), 0) rem from public.sales_invoices s
       where s.company_id = p_company and s.party_id = p_party and s.status = 'posted' and public.branch_ok(p_company, s.branch_id))
    select jsonb_build_object(
      'party', jsonb_build_object('id', p.id, 'name', p.name, 'name_en', p.name_en, 'vat_no', p.vat_no, 'cr_no', p.cr_no, 'phone', p.phone, 'email', p.email,
        'city', p.city, 'terms_days', p.terms_days, 'credit_limit', p.credit_limit, 'active', p.active, 'created_at', p.created_at, 'sister', p.group_company_id is not null,
        'rep', (select jsonb_build_object('id', e.id, 'name', e.full_name) from public.employees e where e.id = p.sales_rep_id)),
      'balance', public.party_balance(p_party),
      'open', coalesce((select sum(rem) from inv), 0),
      'overdue', coalesce((select sum(rem) from inv where due_date < td), 0),
      'aging', jsonb_build_object(
        'current', coalesce((select sum(rem) from inv where due_date >= td), 0),
        'd30', coalesce((select sum(rem) from inv where due_date < td and due_date >= td - 30), 0),
        'd60', coalesce((select sum(rem) from inv where due_date < td - 30 and due_date >= td - 60), 0),
        'd90', coalesce((select sum(rem) from inv where due_date < td - 60 and due_date >= td - 90), 0),
        'over90', coalesce((select sum(rem) from inv where due_date < td - 90), 0)),
      'sales_ytd', coalesce((select sum(subtotal) from inv where not is_opening and date >= y0), 0),
      'sales_all', coalesce((select sum(subtotal) from inv where not is_opening), 0),
      'invoices_n', (select count(*) from inv where not is_opening),
      'first_sale', (select min(date) from inv where not is_opening),
      'last_sale', (select max(date) from inv where not is_opening),
      -- days from the invoice to the receipt, weighted by the amount (receipts tied to an invoice)
      'pay_days', (select round(sum((y.date - s.date) * y.amount) / nullif(sum(y.amount), 0)) from public.payments y join public.sales_invoices s on s.id = y.invoice_id
                    where y.company_id = p_company and y.party_id = p_party and y.direction = 'in' and public.branch_ok(p_company, y.branch_id)),
      'returns', coalesce((select sum(n.total) from public.credit_notes n where n.company_id = p_company and n.party_id = p_party and n.kind = 'sales'), 0),
      'trend', trend,
      'invoices', coalesce((select jsonb_agg(z order by z.date desc, z.no desc) from (select id, no, date, due_date, total, rem, doc_type from inv order by date desc, no desc limit 15) z), '[]'),
      'payments', coalesce((select jsonb_agg(z order by z.date desc, z.no desc) from (select y.id, y.no, y.date, y.amount, y.account_code, (select s.no from public.sales_invoices s where s.id = y.invoice_id) inv_no
                    from public.payments y where y.company_id = p_company and y.party_id = p_party and y.direction = 'in' and public.branch_ok(p_company, y.branch_id)
                    order by y.date desc, y.no desc limit 15) z), '[]'),
      'orders', coalesce((select jsonb_agg(z order by z.date desc) from (select o.id, o.no, o.kind, o.date, o.total, o.status, o.valid_until from public.sales_orders o
                    where o.company_id = p_company and o.party_id = p_party and o.status in ('open','accepted') and public.branch_ok(p_company, o.branch_id) order by o.date desc limit 15) z), '[]'),
      'leads', coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'no', l.no, 'title', l.title, 'stage', l.stage, 'value', l.value) order by l.created_at desc)
                    from public.crm_leads l where l.company_id = p_company and l.party_id = p_party and l.stage not in ('won','lost')), '[]'),
      'won', (select count(*) from public.crm_leads l where l.company_id = p_company and l.party_id = p_party and l.stage = 'won'),
      'agreements', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'no', a.no, 'title', a.title, 'end_date', a.end_date, 'value', a.value, 'status', a.status) order by a.end_date nulls last)
                    from public.agreements a where a.company_id = p_company and a.party_id = p_party and a.direction = 'sale' and a.status = 'active'), '[]'),
      'cheques', coalesce((select jsonb_agg(jsonb_build_object('no', c.cheque_no, 'bank', c.bank, 'amount', c.amount, 'due_date', c.due_date) order by c.due_date)
                    from public.cheques c where c.company_id = p_company and c.party_id = p_party and c.direction = 'in' and c.status = 'open'), '[]')));
end $$;

revoke all on function public.customer_360(uuid, uuid) from public, anon;
grant execute on function public.customer_360(uuid, uuid) to authenticated;
notify pgrst, 'reload schema';
