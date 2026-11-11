-- Waad ERP — 0074 fixes from a full walk-through as a new customer.
-- (1) Opening stock entered through «تسوية مخزون» was posted against 5600 (inventory differences, an expense account),
--     so it showed as profit (negative expenses, margins above 1000%). An adjustment marked as opening stock now posts
--     against 3900 (opening balances, equity) — the same account the opening-balances import uses.
-- (2) An employee could not see the name of their own direct manager (other employees' records are closed to them).

drop function if exists public.stock_adjust(uuid, uuid, date, numeric, numeric, text, uuid, date);
create function public.stock_adjust(p_company uuid, p_item uuid, p_date date, p_qty numeric, p_unit_cost numeric, p_reason text,
  p_warehouse uuid default null, p_expiry date default null, p_opening boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare it public.items; st record; v numeric; aid uuid := gen_random_uuid(); w uuid; ctr text := case when coalesce(p_opening, false) then '3900' else '5600' end;
begin
  perform public.require_fin(p_company, 'stockadj');
  select * into it from public.items where id = p_item and company_id = p_company and type = 'stock';
  if not found then raise exception 'الصنف غير موجود أو ليس مخزنياً'; end if;
  if coalesce(p_qty,0) = 0 then raise exception 'أدخل كمية التسوية'; end if;
  if p_date > current_date then raise exception 'التاريخ لا يكون في المستقبل'; end if;
  if length(trim(coalesce(p_reason,''))) < 3 then raise exception 'اكتب سبب التسوية'; end if;
  if coalesce(p_opening, false) and p_qty < 0 then raise exception 'الرصيد الافتتاحي يكون زيادة في الكمية'; end if;
  if coalesce(p_opening, false) then perform public.ensure_fin2_accounts(p_company); end if;
  w := public.wh_use(p_company, p_warehouse::text);
  if it.track_expiry and p_qty > 0 and p_expiry is null then raise exception 'أدخل تاريخ الصلاحية'; end if;
  select * into st from public.stock_state(p_item);
  if p_qty < 0 and public.wh_qty(p_item, w) + p_qty < 0 then raise exception 'العجز أكبر من الرصيد المتوفر في المستودع (%)', public.wh_qty(p_item, w); end if;
  v := case when p_qty > 0 then round(p_qty * coalesce(p_unit_cost, st.avg_cost), 2)
            when st.qty + p_qty = 0 then -st.value else round(p_qty * st.avg_cost, 2) end;
  insert into public.stock_moves(company_id, item_id, warehouse_id, date, qty, value, source, source_id, expiry, note)
  values (p_company, p_item, w, p_date, p_qty, v, 'adjust', aid, case when p_qty > 0 then p_expiry end, trim(p_reason));
  perform public.post_journal(p_company, p_date, (case when coalesce(p_opening, false) then 'رصيد افتتاحي للمخزون — ' else 'تسوية مخزون — ' end) || it.name, 'stock', aid,
    case when v >= 0 then jsonb_build_array(jsonb_build_object('a','1300','d',v), jsonb_build_object('a',ctr,'c',v))
         else jsonb_build_array(jsonb_build_object('a',ctr,'d',-v), jsonb_build_object('a','1300','c',-v)) end);
end $$;
revoke all on function public.stock_adjust(uuid, uuid, date, numeric, numeric, text, uuid, date, boolean) from public, anon;
grant execute on function public.stock_adjust(uuid, uuid, date, numeric, numeric, text, uuid, date, boolean) to authenticated;

-- (2) the signed-in employee's direct manager: name and title only
create or replace function public.my_manager(p_company uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('name', m.full_name, 'name_en', m.full_name_en, 'title', m.job_title)
    from public.members me join public.employees e on e.id = me.employee_id and e.company_id = me.company_id
    join public.employees m on m.id = e.manager_id
   where me.company_id = p_company and me.user_id = auth.uid()
$$;
revoke all on function public.my_manager(uuid) from public, anon;
grant execute on function public.my_manager(uuid) to authenticated;
