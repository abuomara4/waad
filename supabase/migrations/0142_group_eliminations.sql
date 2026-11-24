-- Company groups, phase 3 (docs/MULTI_ENTITY_DESIGN.md): transactions between the group's companies and their elimination in
-- the consolidated statements. A customer / supplier is marked as a sister company (parties.group_company_id). A journal entry
-- of a sales invoice, purchase bill, receipt / payment or return (or the reversal of one) whose party is a sister company is
-- intercompany. In the consolidation (each company's own books never change):
--   * intercompany revenue (the seller's revenue lines) is removed, and the same amount of cost: first the buyer's expense
--     lines on the intercompany bills, the rest from cost of goods sold 5100 (goods bought from a sister and sold on) — so the
--     group's profit does not change. Profit still unrealised in inventory at the date (goods not yet sold outside the group)
--     and assets bought from a sister are adjusted by hand (stated on the screen).
--   * intercompany receivables (1200) and payables (2100) are removed. When the two sides do not match (an invoice recorded by
--     one company only, a different amount), the difference shows on its own line «فروق المعاملات بين الشركات» so the
--     consolidated balance sheet still balances — and the matching report shows which pair differs.
-- VAT, cash and bank, and inventory lines are real for each company and are kept.

alter table public.parties add column if not exists group_company_id uuid references public.companies(id) on delete set null;
create index if not exists parties_group_company on public.parties(group_company_id) where group_company_id is not null;

-- a sister company must be another company of the same group
create or replace function public.parties_group_guard() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.group_company_id is not null and (tg_op = 'INSERT' or new.group_company_id is distinct from old.group_company_id) then
    if new.group_company_id = new.company_id or not exists(
         select 1 from public.companies a join public.companies b on b.group_id = a.group_id
          where a.id = new.company_id and b.id = new.group_company_id and a.group_id is not null) then
      raise exception 'الشركة الشقيقة يجب أن تكون منشأة أخرى في المجموعة نفسها';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists parties_group_guard on public.parties;
create trigger parties_group_guard before insert or update of group_company_id on public.parties for each row execute function public.parties_group_guard();

-- the other companies of the group, for the party form (management and finance of the company)
create or replace function public.group_sisters(p_company uuid) returns table(id uuid, name text)
language sql stable security definer set search_path = public as $$
  select b.id, b.name from public.companies a join public.companies b on b.group_id = a.group_id and b.id <> a.id
   where a.id = p_company and a.group_id is not null
     and (public.has_role(p_company, array['owner','admin','finance']) or public.fin_can(p_company, 'sales') or public.fin_can(p_company, 'purch'))
   order by b.created_at
$$;

-- one click for the group's owner: in every company, a customer and a supplier for each sister company (an existing party with
-- the sister's exact name is linked instead of duplicated). Returns how many parties were created or linked.
create or replace function public.group_link_parties(p_group uuid) returns int
language plpgsql security definer set search_path = public as $$
declare x record; k text; n int := 0; pid uuid; nm text;
begin
  perform public.group_need(p_group);
  for x in select a.id cid, b.id oid, b.name, b.vat_no, b.cr_no from public.companies a join public.companies b on b.group_id = a.group_id and b.id <> a.id
            where a.group_id = p_group loop
    nm := case when length(btrim(x.name)) >= 3 then btrim(x.name) else btrim(x.name) || ' — شقيقة' end;
    foreach k in array array['customer','supplier'] loop
      if exists(select 1 from public.parties where company_id = x.cid and kind = k and group_company_id = x.oid) then continue; end if;
      select id into pid from public.parties where company_id = x.cid and kind = k and name = nm;
      if pid is not null then update public.parties set group_company_id = x.oid where id = pid;
      else insert into public.parties(company_id, kind, name, vat_no, cr_no, group_company_id)
           values (x.cid, k, nm, case when x.vat_no ~ '^3[0-9]{13}3$' then x.vat_no end, case when x.cr_no ~ '^[0-9]{10}$' then x.cr_no end, x.oid);
      end if;
      n := n + 1; pid := null;
    end loop;
  end loop;
  return n;
end $$;

-- the intercompany journal lines of the group up to p_to (from p_from when given): company, the sister on the other side,
-- the document kind (sales side / purchase side / money), account, type and debit − credit
create or replace function public.group_ic_lines(p_group uuid, p_from date, p_to date)
returns table(company_id uuid, other uuid, src text, code text, type text, dr numeric)
language sql stable security definer set search_path = public as $$
  with en as (
    select e.id, e.company_id, coalesce(o.source, e.source) src, coalesce(o.source_id, e.source_id) sid
      from public.journal_entries e join public.companies c on c.id = e.company_id and c.group_id = p_group
      left join public.journal_entries o on o.id = e.reverses
     where e.date <= p_to and (p_from is null or e.date >= p_from)),
  ic as (
    select en.id, en.company_id, en.src, p.group_company_id other from en
      join public.parties p on p.id = case
        when en.src = 'sales' then (select s.party_id from public.sales_invoices s where s.id = en.sid)
        when en.src = 'purchase' then (select b.party_id from public.purchase_bills b where b.id = en.sid)
        when en.src in ('receipt','payment') then (select y.party_id from public.payments y where y.id = en.sid)
        when en.src in ('sales_return','purchase_return') then (select n.party_id from public.credit_notes n where n.id = en.sid) end
      join public.companies oc on oc.id = p.group_company_id and oc.group_id = p_group and oc.id <> en.company_id)
  select ic.company_id, ic.other, ic.src, l.account_code, a.type, l.debit - l.credit
    from ic join public.journal_lines l on l.entry_id = ic.id
    join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
$$;

-- the eliminations as adjustments (debit − credit) per account; code 'IC' = the unmatched difference
create or replace function public.group_elims(p_group uuid, p_from date, p_to date) returns table(code text, adj numeric)
language sql stable security definer set search_path = public as $$
  with l as (select * from public.group_ic_lines(p_group, p_from, p_to)),
  el as (select l.code, -sum(l.dr) adj from l
          where (l.type = 'rev' and l.src in ('sales','sales_return')) or (l.type = 'exp' and l.src in ('purchase','purchase_return')) or l.code in ('1200','2100')
          group by l.code),
  r as (select coalesce(-sum(l.dr) filter (where l.type = 'rev' and l.src in ('sales','sales_return')), 0)
             - coalesce(sum(l.dr) filter (where l.type = 'exp' and l.src in ('purchase','purchase_return')), 0) rest from l),
  allx as (select el.code, el.adj from el union all select '5100', -r.rest from r where r.rest <> 0)
  select x.code, sum(x.adj) from allx x group by x.code having sum(x.adj) <> 0
  union all
  select 'IC', -sum(x.adj) from allx x having abs(sum(x.adj)) >= 0.005
$$;

-- the group's chart: each code once, with the first company's name and type
create or replace function public.group_accounts(p_group uuid) returns table(code text, name text, type text)
language sql stable security definer set search_path = public as $$
  select distinct on (a.code) a.code, a.name, a.type from public.accounts a join public.companies c on c.id = a.company_id
   where c.group_id = p_group order by a.code, c.created_at
$$;

-- the statements with an «elim» column; amount = the companies' total + elim
drop function if exists public.group_income_statement(uuid, date, date);
create function public.group_income_statement(p_group uuid, p_from date, p_to date)
returns table(section text, code text, name text, amount numeric, by_company jsonb, elim numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.group_need(p_group);
  return query
  with b as (
    select a.code, a.type, l.company_id cid, sum(l.credit - l.debit) cr
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
      join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
      join public.companies c on c.id = l.company_id and c.group_id = p_group
     where e.date between p_from and p_to and a.type in ('rev','exp') and not public.is_closing_entry(e.id)
     group by a.code, a.type, l.company_id),
  x as (select g.code, g.adj from public.group_elims(p_group, p_from, p_to) g),
  t0 as (select b.code, sum(b.cr) cr, jsonb_object_agg(b.cid, case when b.type = 'rev' then b.cr else -b.cr end) byc from b group by b.code having bool_or(b.cr <> 0)),
  t as (select n.code, n.name, n.type, coalesce(t0.cr, 0) cr, coalesce(t0.byc, '{}'::jsonb) byc, coalesce(x.adj, 0) adj
          from public.group_accounts(p_group) n left join t0 on t0.code = n.code left join x on x.code = n.code
         where n.type in ('rev','exp') and (t0.code is not null or coalesce(x.adj, 0) <> 0))
  select case when t.type = 'rev' then 'revenue' when t.code = '5100' then 'cogs' else 'expense' end, t.code, t.name,
         case when t.type = 'rev' then t.cr - t.adj else -t.cr + t.adj end, t.byc, case when t.type = 'rev' then -t.adj else t.adj end
    from t
  union all
  select 'net_profit', null, 'صافي الربح', coalesce((select sum(t.cr - t.adj) from t), 0),
         coalesce((select jsonb_object_agg(z.cid, z.s) from (select b.cid, sum(b.cr) s from b group by b.cid) z), '{}'),
         -coalesce((select sum(t.adj) from t), 0)
  order by 1 desc, 2;
end $$;

drop function if exists public.group_balance_sheet(uuid, date);
create function public.group_balance_sheet(p_group uuid, p_as_of date)
returns table(section text, code text, name text, amount numeric, by_company jsonb, elim numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.group_need(p_group);
  return query
  with b as (
    select a.code, a.type, l.company_id cid, sum(l.debit - l.credit) dr
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
      join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
      join public.companies c on c.id = l.company_id and c.group_id = p_group
     where e.date <= p_as_of group by a.code, a.type, l.company_id),
  x as (select g.code, g.adj from public.group_elims(p_group, null, p_as_of) g),
  t0 as (select b.code, sum(b.dr) dr, jsonb_object_agg(b.cid, case when b.type = 'asset' then b.dr else -b.dr end) byc
           from b where b.type in ('asset','liab','equity') group by b.code having bool_or(b.dr <> 0)),
  t as (select n.code, n.name, n.type, coalesce(t0.dr, 0) dr, coalesce(t0.byc, '{}'::jsonb) byc, coalesce(x.adj, 0) adj
          from public.group_accounts(p_group) n left join t0 on t0.code = n.code left join x on x.code = n.code
         where n.type in ('asset','liab','equity') and (t0.code is not null or coalesce(x.adj, 0) <> 0))
  select t.type, t.code, t.name, case when t.type = 'asset' then t.dr + t.adj else -(t.dr + t.adj) end, t.byc,
         case when t.type = 'asset' then t.adj else -t.adj end
    from t
  union all
  select 'equity', null, 'أرباح (خسائر) الفترة غير المقفلة',
         coalesce((select -sum(b.dr) from b where b.type in ('rev','exp')), 0) - coalesce((select sum(x.adj) from x join public.group_accounts(p_group) n on n.code = x.code where n.type in ('rev','exp')), 0),
         coalesce((select jsonb_object_agg(z.cid, z.s) from (select b.cid, -sum(b.dr) s from b where b.type in ('rev','exp') group by b.cid) z), '{}'),
         -coalesce((select sum(x.adj) from x join public.group_accounts(p_group) n on n.code = x.code where n.type in ('rev','exp')), 0)
  union all
  select 'equity', 'IC', 'فروق المعاملات بين الشركات (تُراجع)', -x.adj, '{}'::jsonb, -x.adj from x where x.code = 'IC'
  order by 1, 2 nulls last;
end $$;

drop function if exists public.group_trial_balance(uuid, date);
create function public.group_trial_balance(p_group uuid, p_as_of date)
returns table(code text, name text, debit numeric, credit numeric, by_company jsonb, elim numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.group_need(p_group);
  return query
  with b as (
    select l.account_code code, l.company_id cid, sum(l.debit - l.credit) dr
      from public.journal_lines l join public.journal_entries e on e.id = l.entry_id
      join public.companies c on c.id = l.company_id and c.group_id = p_group
     where e.date <= p_as_of group by l.account_code, l.company_id),
  x as (select g.code, g.adj from public.group_elims(p_group, null, p_as_of) g),
  t0 as (select b.code, sum(b.dr) dr, jsonb_object_agg(b.cid, b.dr) byc from b group by b.code having bool_or(b.dr <> 0)),
  t as (select n.code, n.name, coalesce(t0.dr, 0) dr, coalesce(t0.byc, '{}'::jsonb) byc, coalesce(x.adj, 0) adj
          from public.group_accounts(p_group) n left join t0 on t0.code = n.code left join x on x.code = n.code
         where (t0.code is not null and t0.dr <> 0) or coalesce(x.adj, 0) <> 0 or (t0.code is not null and t0.byc::text <> '{}'))
  select t.code, t.name, greatest(t.dr + t.adj, 0)::numeric, greatest(-(t.dr + t.adj), 0)::numeric, t.byc, t.adj from t
  union all
  select 'IC', 'فروق المعاملات بين الشركات (تُراجع)', greatest(x.adj, 0), greatest(-x.adj, 0), '{}'::jsonb, x.adj from x where x.code = 'IC'
  order by 1;
end $$;

-- matching between each pair: what the seller invoiced (incl. VAT, net of returns) and what the buyer recorded, for the
-- period; the seller's receivable and the buyer's payable at the end
create or replace function public.group_ic_recon(p_group uuid, p_from date, p_to date)
returns table(seller uuid, seller_name text, buyer uuid, buyer_name text, invoiced numeric, recorded numeric, receivable numeric, payable numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.group_need(p_group);
  return query
  with per as (select l.company_id, l.other,
                 coalesce(sum(l.dr) filter (where l.code = '1200' and l.src in ('sales','sales_return')), 0) sold,
                 coalesce(-sum(l.dr) filter (where l.code = '2100' and l.src in ('purchase','purchase_return')), 0) bought
               from public.group_ic_lines(p_group, p_from, p_to) l group by l.company_id, l.other),
  bal as (select l.company_id, l.other, coalesce(sum(l.dr) filter (where l.code = '1200'), 0) ar, coalesce(-sum(l.dr) filter (where l.code = '2100'), 0) ap
            from public.group_ic_lines(p_group, null, p_to) l group by l.company_id, l.other),
  pairs as (select s.id a, b.id bb from public.companies s join public.companies b on b.group_id = s.group_id and b.id <> s.id where s.group_id = p_group)
  select p.a, ca.name, p.bb, cb.name,
         coalesce((select per.sold from per where per.company_id = p.a and per.other = p.bb), 0),
         coalesce((select per.bought from per where per.company_id = p.bb and per.other = p.a), 0),
         coalesce((select bal.ar from bal where bal.company_id = p.a and bal.other = p.bb), 0),
         coalesce((select bal.ap from bal where bal.company_id = p.bb and bal.other = p.a), 0)
    from pairs p join public.companies ca on ca.id = p.a join public.companies cb on cb.id = p.bb
   order by ca.created_at, cb.created_at;
end $$;

revoke all on function public.parties_group_guard(), public.group_ic_lines(uuid, date, date), public.group_elims(uuid, date, date), public.group_accounts(uuid) from public, anon, authenticated;
revoke all on function public.group_sisters(uuid), public.group_link_parties(uuid), public.group_income_statement(uuid, date, date), public.group_balance_sheet(uuid, date),
  public.group_trial_balance(uuid, date), public.group_ic_recon(uuid, date, date) from public, anon;
grant execute on function public.group_sisters(uuid), public.group_link_parties(uuid), public.group_income_statement(uuid, date, date), public.group_balance_sheet(uuid, date),
  public.group_trial_balance(uuid, date), public.group_ic_recon(uuid, date, date) to authenticated;
notify pgrst, 'reload schema';
