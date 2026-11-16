-- Waad ERP — 0089 delete an employee record added by mistake (QA report). Only while nothing hangs on it: any payroll
-- line, request, document, penalty… referencing the employee stops the deletion with a clear message (end the service
-- instead). His sign-in, if one was created, goes with the record. The owner's own record is never deleted here.

create or replace function public.employee_delete(p_emp uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e public.employees;
begin
  select * into e from public.employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود'; end if;
  if not public.has_role(e.company_id, array['owner','admin','hr']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if exists(select 1 from public.members m where m.company_id = e.company_id and m.employee_id = p_emp and m.role = 'owner') then
    raise exception 'هذا سجل المالك ولا يُحذف'; end if;
  -- anything recorded for him (most of these tables would be emptied silently with the record, so they are checked here)
  if exists(select 1 from public.requests where employee_id = p_emp) or exists(select 1 from public.attendance where employee_id = p_emp)
     or exists(select 1 from public.employee_documents where employee_id = p_emp) or exists(select 1 from public.contracts where employee_id = p_emp)
     or exists(select 1 from public.letters where employee_id = p_emp) or exists(select 1 from public.penalties where employee_id = p_emp)
     or exists(select 1 from public.reviews where employee_id = p_emp) or exists(select 1 from public.training_attendees where employee_id = p_emp)
     or exists(select 1 from public.comp_credits where employee_id = p_emp) or exists(select 1 from public.custody_items where employee_id = p_emp)
     or exists(select 1 from public.clearance_marks where employee_id = p_emp) or exists(select 1 from public.policy_acks where employee_id = p_emp)
     or exists(select 1 from public.travel_files where employee_id = p_emp) or exists(select 1 from public.travel_tickets where employee_id = p_emp)
     or exists(select 1 from public.exit_visas where employee_id = p_emp) or exists(select 1 from public.insurance_members where employee_id = p_emp)
     or exists(select 1 from public.shift_roster where employee_id = p_emp) then
    raise exception 'لا يمكن حذف الموظف لوجود حركات مرتبطة به (رواتب أو طلبات أو مستندات). أنهِ خدمته بدلا من ذلك';
  end if;
  delete from public.members where company_id = e.company_id and employee_id = p_emp;
  begin
    delete from public.employees where id = p_emp;
  exception when foreign_key_violation then
    raise exception 'لا يمكن حذف الموظف لوجود حركات مرتبطة به (رواتب أو طلبات أو مستندات). أنهِ خدمته بدلا من ذلك';
  end;
end $$;
revoke all on function public.employee_delete(uuid) from public, anon;
grant execute on function public.employee_delete(uuid) to authenticated;
