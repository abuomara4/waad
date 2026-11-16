-- Waad ERP — 0092 add employees to a review cycle that is already open (new joiners after it started; QA report).
-- Everyone in service at the end of the cycle's period who has no review in it yet gets one (reviewer = direct manager).

create or replace function public.review_cycle_add(p_cycle uuid) returns int
language plpgsql security definer set search_path = public as $$
declare c public.review_cycles; n int;
begin
  select * into c from public.review_cycles where id = p_cycle;
  if not found then raise exception 'الدورة غير موجودة'; end if;
  perform public.require_role(c.company_id, array['owner','admin','hr']);
  if c.status <> 'open' then raise exception 'الدورة مغلقة'; end if;
  insert into public.reviews(company_id, cycle_id, employee_id, reviewer_id)
    select c.company_id, c.id, e.id, e.manager_id from public.employees e
     where e.company_id = c.company_id and e.hire_date <= c.period_end and (e.end_date is null or e.end_date >= c.period_end)
       and not exists(select 1 from public.reviews r where r.cycle_id = c.id and r.employee_id = e.id);
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.review_cycle_add(uuid) from public, anon;
grant execute on function public.review_cycle_add(uuid) to authenticated;
