-- Approval delegation and amount levels.
-- 1) An approver hands their approvals to a colleague for a period (leave, travel): during it the colleague can act on
--    every step the approver could, and the trail records who acted. Set by the approver, or by the owner / admin / HR.
-- 2) The finance step, like the GM step (0105), can apply only above an amount: workflows.f_above.
create table if not exists public.approval_delegations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  from_user uuid not null references auth.users(id) on delete cascade,
  to_user uuid not null references auth.users(id) on delete cascade,
  from_date date not null,
  to_date date not null,
  note text check (note is null or length(note) <= 300),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check (from_user <> to_user), check (to_date >= from_date), check (to_date - from_date <= 90)
);
create index if not exists approval_delegations_to on public.approval_delegations(to_user, company_id, from_date, to_date);
create index if not exists approval_delegations_from on public.approval_delegations(from_user);
create index if not exists approval_delegations_co on public.approval_delegations(company_id);
alter table public.approval_delegations enable row level security;
revoke all on public.approval_delegations from anon;
grant select on public.approval_delegations to authenticated;
drop policy if exists approval_delegations_read on public.approval_delegations;
create policy approval_delegations_read on public.approval_delegations for select
  using (public.is_member(company_id) and (from_user = auth.uid() or to_user = auth.uid() or public.has_role(company_id, array['owner','admin','hr'])));
drop trigger if exists audit_approval_delegations on public.approval_delegations;
create trigger audit_approval_delegations after insert or update or delete on public.approval_delegations for each row execute function public.audit_trigger();

-- the step check as before, under a new name; can_act adds the delegations
alter function public.can_act(public.requests, text) rename to can_act_self;
revoke all on function public.can_act_self(public.requests, text) from public, anon, authenticated;

create or replace function public.can_act(r public.requests, p text) returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); orig text := current_setting('request.jwt.claim.sub', true); d record; ok boolean := false;
begin
  if public.can_act_self(r, p) then return true; end if;
  if me is null or coalesce(public.my_employee(r.company_id) = r.employee_id, false) then return false; end if;   -- never on one's own request
  for d in select g.from_user from public.approval_delegations g
            where g.company_id = r.company_id and g.to_user = me and public.riyadh_today() between g.from_date and g.to_date loop
    begin
      perform set_config('request.jwt.claim.sub', d.from_user::text, true);   -- decide as the approver who delegated
      ok := public.can_act_self(r, p);
      perform set_config('request.jwt.claim.sub', coalesce(orig, ''), true);
    exception when others then perform set_config('request.jwt.claim.sub', coalesce(orig, ''), true); raise; end;
    if ok then return true; end if;
  end loop;
  return false;
end $$;
revoke all on function public.can_act(public.requests, text) from public, anon;
grant execute on function public.can_act(public.requests, text) to authenticated;

-- live members of the company to delegate to (names only: the employee name, else the role)
create or replace function public.delegation_people(p_company uuid) returns table(user_id uuid, name text)
language sql stable security definer set search_path = public as $$
  select m.user_id, coalesce(e.full_name, case m.role when 'owner' then 'المالك' when 'admin' then 'مدير النظام' when 'hr' then 'الموارد البشرية' when 'finance' then 'المالية' else m.role end)
    from public.members m left join public.employees e on e.id = m.employee_id
   where public.is_member(p_company) and m.company_id = p_company and public.member_live(m.employee_id, m.role)
   order by 2
$$;

create or replace function public.delegation_set(p_company uuid, p_to uuid, p_from date, p_until date, p_note text default null, p_for uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare who uuid := coalesce(p_for, auth.uid()); id uuid;
begin
  if not public.is_member(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if who <> auth.uid() and not public.has_role(p_company, array['owner','admin','hr']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if not exists(select 1 from public.members where company_id = p_company and user_id = who) or not exists(select 1 from public.members where company_id = p_company and user_id = p_to) then
    raise exception 'اختر زميلا من منشأتك'; end if;
  if who = p_to then raise exception 'اختر زميلا غيرك'; end if;
  if p_from is null or p_until is null or p_until < p_from then raise exception 'تحقق من التواريخ'; end if;
  if p_until - p_from > 90 then raise exception 'التفويض 90 يوما على الأكثر'; end if;
  if p_until < public.riyadh_today() then raise exception 'تاريخ النهاية مضى'; end if;
  insert into public.approval_delegations(company_id, from_user, to_user, from_date, to_date, note)
  values (p_company, who, p_to, p_from, p_until, nullif(btrim(coalesce(p_note, '')), '')) returning approval_delegations.id into id;
  return id;
end $$;

create or replace function public.delegation_end(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g public.approval_delegations;
begin
  select * into g from public.approval_delegations where id = p_id;
  if not found or not (g.from_user = auth.uid() or public.has_role(g.company_id, array['owner','admin','hr'])) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  -- starting today or later: removed; started earlier: ends yesterday, so it stops at once
  if g.from_date >= public.riyadh_today() then delete from public.approval_delegations where id = p_id;
  else update public.approval_delegations set to_date = public.riyadh_today() - 1 where id = p_id; end if;
end $$;

-- pending requests that reach the signed-in user only through a delegation (for the approvals list)
create or replace function public.delegated_pending(p_company uuid) returns setof jsonb
language sql stable security definer set search_path = public as $$
  select to_jsonb(r) || jsonb_build_object('_emp', jsonb_build_object('id', e.id, 'full_name', e.full_name, 'emp_no', e.emp_no), '_deleg', true)
    from public.requests r join public.employees e on e.id = r.employee_id
   where public.is_member(p_company) and r.company_id = p_company and r.status = 'pending'
     and exists(select 1 from public.approval_delegations g where g.company_id = p_company and g.to_user = auth.uid() and public.riyadh_today() between g.from_date and g.to_date)
     and not public.can_act_self(r, r.route[r.step + 1]) and public.can_act(r, r.route[r.step + 1])
   order by r.created_at
$$;

-- finance level by amount: the «f» step only above f_above
alter table public.workflows add column if not exists f_above numeric check (f_above is null or f_above >= 0);
create or replace function public.workflow_f_set(p_company uuid, p_kind text, p_above numeric) returns void
language plpgsql security definer set search_path = public as $$
declare rt text[];
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if p_kind not in ('advance','expense','settle','ticket','purchase','trip') then raise exception 'الشرط متاح لطلبات المبالغ فقط'; end if;
  if p_above is not null and p_above < 0 then raise exception 'الحد لا يكون سالباً'; end if;
  select route into rt from public.workflows where company_id = p_company and kind = p_kind;
  rt := coalesce(rt, public.default_route(p_kind));
  if p_above is not null and not ('f' = any(rt)) then rt := rt || array['f']; end if;
  insert into public.workflows(company_id, kind, route, f_above) values (p_company, p_kind, rt, p_above)
    on conflict (company_id, kind) do update set f_above = excluded.f_above, route = excluded.route;
end $$;

create or replace function public.requests_route_rule() returns trigger language plpgsql security definer set search_path = public as $$
declare w public.workflows; val numeric;
begin
  if new.status <> 'pending' or new.route is null or cardinality(new.route) < 2 then return new; end if;
  select * into w from public.workflows where company_id = new.company_id and kind = new.kind;
  if not found then return new; end if;
  val := coalesce(case when new.kind = 'leave' then new.days else new.amount end, 0);
  if w.g_above is not null and 'g' = any(new.route) and val <= w.g_above and cardinality(new.route) > 1 then new.route := array_remove(new.route, 'g'); end if;
  if w.f_above is not null and 'f' = any(new.route) and val <= w.f_above and cardinality(new.route) > 1 then new.route := array_remove(new.route, 'f'); end if;
  return new;
end $$;

revoke all on function public.delegation_people(uuid), public.delegation_set(uuid, uuid, date, date, text, uuid), public.delegation_end(uuid), public.delegated_pending(uuid), public.workflow_f_set(uuid, text, numeric) from public, anon;
grant execute on function public.delegation_people(uuid), public.delegation_set(uuid, uuid, date, date, text, uuid), public.delegation_end(uuid), public.delegated_pending(uuid), public.workflow_f_set(uuid, text, numeric) to authenticated;
revoke all on function public.requests_route_rule() from public, anon, authenticated;
notify pgrst, 'reload schema';
