-- Waad ERP — 0086 the owner, admins and HR may decide a request at the direct manager's step in his place (a manager on
-- leave, slow to answer, …). A reason is required; it is logged under their name as «تجاوز المدير المباشر: …» in the
-- request's journey, which the employee and the manager see. After that the route continues as usual.

create or replace function public.request_override(p_id uuid, p_approve boolean, p_note text) returns text
language plpgsql security definer set search_path = public as $$
declare r public.requests; nxt int; why text := 'تجاوز المدير المباشر: ' || trim(coalesce(p_note, ''));
begin
  select * into r from public.requests where id = p_id for update;
  if not found then raise exception 'الطلب غير موجود'; end if;
  if not public.has_role(r.company_id, array['owner','admin','hr']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if r.employee_id = public.my_employee(r.company_id) then raise exception 'لا يمكنك البت في طلبك'; end if;
  if r.status <> 'pending' then raise exception 'الطلب ليس بانتظار قرار'; end if;
  if r.route[r.step + 1] is distinct from 'm' then raise exception 'الطلب ليس عند المدير المباشر'; end if;
  if coalesce(length(trim(p_note)), 0) < 3 then raise exception 'اكتب سبب التجاوز'; end if;
  if not p_approve then
    update public.requests set status = 'rejected', decided_at = now(), step_at = now() where id = p_id;
    insert into public.request_actions(request_id, actor, actor_step, action, note) values (p_id, auth.uid(), 'm', 'rejected', why);
    return 'rejected';
  end if;
  insert into public.request_actions(request_id, actor, actor_step, action, note) values (p_id, auth.uid(), 'm', 'approved', why);
  nxt := r.step + 1;
  -- as in decide_request: the same person holding the next step(s) approves once
  while nxt < cardinality(r.route) and public.can_act(r, r.route[nxt + 1]) loop
    insert into public.request_actions(request_id, actor, actor_step, action, note)
    values (p_id, auth.uid(), r.route[nxt + 1], 'approved', 'اعتماد تلقائي: المعتمد نفسه في المرحلة السابقة');
    nxt := nxt + 1;
  end loop;
  if nxt >= cardinality(r.route) then
    update public.requests set step = nxt, status = 'approved', decided_at = now(), step_at = now() where id = p_id;
    perform public.on_request_approved(p_id);
    return 'approved';
  end if;
  update public.requests set step = nxt, step_at = now() where id = p_id;
  return 'next:' || r.route[nxt + 1];
end $$;
revoke all on function public.request_override(uuid, boolean, text) from public, anon;
grant execute on function public.request_override(uuid, boolean, text) to authenticated;
