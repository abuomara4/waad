-- Leave requests: sick-pay split shown before sending (Labor Law Art. 117: 30 days full pay, 60 days at three quarters,
-- 30 days unpaid, within the year that starts at the first sick leave), a sick-leave number used once per company,
-- HR's recorded result of the manual check on the official Seha inquiry page, and annual leave abroad.
-- Seha offers no public employer API and its inquiry page is protected against automated use: Waad never queries it.

alter table public.request_actions drop constraint request_actions_action_check;
alter table public.request_actions add constraint request_actions_action_check check (action in ('submitted','approved','rejected','cancelled','attached','verified'));

create or replace function public.sick_split(p_used int, p_days int)
returns table(full_days int, part_days int, unpaid_days int, over_days int)
language sql immutable set search_path = public as $$
  with v as (select greatest(coalesce(p_used, 0), 0) u, greatest(coalesce(p_used, 0), 0) + greatest(coalesce(p_days, 0), 0) e)
  select greatest(0, least(30, e) - least(30, u)), greatest(0, least(90, e) - greatest(30, u)),
         greatest(0, least(120, e) - greatest(90, u)), greatest(0, e - greatest(120, u)) from v
$$;

create or replace function public.sick_preview(p_emp uuid, p_from date, p_to date)
returns table(used_days int, year_start date, full_days int, part_days int, unpaid_days int, over_days int)
language plpgsql stable security definer set search_path = public as $$
declare e public.employees; me uuid; r record; ws date; u int := 0; s record;
begin
  select * into e from public.employees where id = p_emp;
  if not found then raise exception 'غير مصرح' using errcode = '42501'; end if;
  me := public.my_employee(e.company_id);
  if not (coalesce(me = e.id, false) or coalesce(me = e.manager_id, false) or public.has_role(e.company_id, array['owner','admin','hr','finance'])) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception 'تحقق من التواريخ'; end if;
  for r in select from_date, days from public.requests where employee_id = p_emp and kind = 'leave' and sub = 'sick'
           and status in ('pending','approved') and from_date < p_from order by from_date loop
    if ws is null or r.from_date >= (ws + interval '1 year')::date then ws := r.from_date; u := 0; end if;
    u := u + r.days;
  end loop;
  if ws is null or p_from >= (ws + interval '1 year')::date then ws := p_from; u := 0; end if;
  select * into s from public.sick_split(u, p_to - p_from + 1);
  return query select u, ws, s.full_days, s.part_days, s.unpaid_days, s.over_days;
end $$;

create or replace function public.requests_leave_guard() returns trigger
language plpgsql set search_path = public as $$
declare ref text; old_ref text; d text;
begin
  if new.kind <> 'leave' then return new; end if;
  new.payload := coalesce(new.payload, '{}'::jsonb);
  if tg_op = 'INSERT' then
    new.payload := new.payload - 'seha';
    if new.sub = 'annual' and new.payload->>'abroad' = 'true' then
      d := left(btrim(coalesce(new.payload->>'dest', '')), 120);
      if length(d) < 2 then raise exception 'اكتب بلد الوجهة'; end if;
      new.payload := new.payload || jsonb_build_object('abroad', true, 'dest', d);
    else new.payload := new.payload - 'abroad' - 'dest'; end if;
  end if;
  if new.sub is distinct from 'sick' then return new; end if;
  ref := nullif(upper(coalesce(new.payload->>'doc_ref', '')), '');
  if tg_op = 'UPDATE' then
    old_ref := nullif(upper(coalesce(old.payload->>'doc_ref', '')), '');
    if ref is distinct from old_ref then new.payload := new.payload - 'seha';
    elsif new.payload->'seha' is distinct from old.payload->'seha' and coalesce(current_setting('waad.seha', true), '') <> '1' then
      new.payload := case when old.payload ? 'seha' then new.payload || jsonb_build_object('seha', old.payload->'seha') else new.payload - 'seha' end;
    end if;
    if new.status = 'approved' and old.status <> 'approved' and new.payload#>>'{seha,status}' = 'bad' then
      raise exception 'لا يمكن اعتماد إجازة مرضية نتيجة التحقق منها غير مطابقة'; end if;
  end if;
  if ref is not null and new.status in ('pending','approved') and (tg_op = 'INSERT' or ref is distinct from old_ref) and exists(
       select 1 from public.requests q where q.company_id = new.company_id and q.kind = 'leave' and q.sub = 'sick' and q.id <> new.id
         and q.status in ('pending','approved') and upper(q.payload->>'doc_ref') = ref) then
    raise exception 'رقم الإجازة المرضية مستخدم في طلب آخر'; end if;
  return new;
end $$;
drop trigger if exists requests_leave_guard on public.requests;
create trigger requests_leave_guard before insert or update on public.requests for each row execute function public.requests_leave_guard();

create or replace function public.sick_verify(p_id uuid, p_ok boolean) returns void
language plpgsql security definer set search_path = public as $$
declare r public.requests;
begin
  select * into r from public.requests where id = p_id for update;
  if not found or not public.has_role(r.company_id, array['owner','admin','hr']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if r.kind <> 'leave' or r.sub is distinct from 'sick' or r.status not in ('pending','approved') or coalesce(r.payload->>'doc_ref', '') = '' or p_ok is null then
    raise exception 'لا يمكن تسجيل التحقق لهذا الطلب'; end if;
  perform set_config('waad.seha', '1', true);
  update public.requests set payload = payload || jsonb_build_object('seha', jsonb_build_object('status', case when p_ok then 'ok' else 'bad' end, 'at', now(), 'by', auth.uid())) where id = p_id;
  perform set_config('waad.seha', '', true);
  insert into public.request_actions(request_id, actor, action, note) values (p_id, auth.uid(), 'verified', case when p_ok then 'مطابقة في منصة صحة' else 'غير مطابقة في منصة صحة' end);
end $$;

revoke all on function public.sick_split(int, int), public.requests_leave_guard() from public, anon, authenticated;
revoke all on function public.sick_preview(uuid, date, date), public.sick_verify(uuid, boolean) from public, anon;
grant execute on function public.sick_preview(uuid, date, date), public.sick_verify(uuid, boolean) to authenticated;
notify pgrst, 'reload schema';
