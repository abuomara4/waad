-- Waad ERP — 0011: who a pending request is waiting on (name + mobile), so the requester or HR can send a WhatsApp reminder.
-- Only the requester and HR/admin/owner may ask, and only for the approvers of that request's current step.
create or replace function public.request_waiting_on(p_id uuid)
returns table(employee_id uuid, full_name text, phone text, step text)
language plpgsql stable security definer set search_path = public as $$
declare r public.requests; st text; roles text[];
begin
  select * into r from public.requests where id = p_id;
  if not found then raise exception 'الطلب غير موجود'; end if;
  if not (coalesce(r.employee_id = public.my_employee(r.company_id), false) or public.has_role(r.company_id, array['owner','admin','hr'])) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  if r.status <> 'pending' then return; end if;
  st := r.route[r.step + 1];
  if st = 'm' then
    return query select m.id, m.full_name, m.phone, st from public.employees e join public.employees m on m.id = e.manager_id where e.id = r.employee_id;
    return;
  end if;
  roles := case st when 'p' then array['hr','admin'] when 'f' then array['finance'] when 'g' then array['owner'] else array[]::text[] end;
  return query select distinct x.id, x.full_name, x.phone, st from public.members mb join public.employees x on x.id = mb.employee_id
    where mb.company_id = r.company_id and mb.role = any(roles) and x.id <> r.employee_id and (x.end_date is null or x.end_date >= current_date)
    order by x.full_name;
end $$;
revoke all on function public.request_waiting_on(uuid) from public, anon;
grant execute on function public.request_waiting_on(uuid) to authenticated;
notify pgrst, 'reload schema';
