-- 0105 — conditional approval (owner's decision, 2026-11-17): per request type, the general manager / owner step applies
-- only above an amount (advance, expense, settlement, ticket, purchase) or a number of days (leave).
-- workflows.g_above = the limit; a request at or below it skips the «g» step. Saving a limit puts «g» in the route.
-- Nothing else in the route changes, and a request never ends up with an empty route.

alter table public.workflows add column if not exists g_above numeric check (g_above is null or g_above >= 0);

create or replace function public.workflow_rule_set(p_company uuid, p_kind text, p_above numeric) returns void
language plpgsql security definer set search_path = public as $$
declare rt text[];
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if p_kind not in ('leave','advance','expense','settle','ticket','purchase') then raise exception 'الشرط متاح لطلبات الإجازة والمبالغ فقط'; end if;
  if p_above is not null and p_above < 0 then raise exception 'الحد لا يكون سالباً'; end if;
  select route into rt from public.workflows where company_id = p_company and kind = p_kind;
  rt := coalesce(rt, public.default_route(p_kind));
  if p_above is not null and not ('g' = any(rt)) then rt := rt || array['g']; end if;
  insert into public.workflows(company_id, kind, route, g_above) values (p_company, p_kind, rt, p_above)
    on conflict (company_id, kind) do update set g_above = excluded.g_above, route = excluded.route;
end $$;
revoke all on function public.workflow_rule_set(uuid, text, numeric) from public, anon;
grant execute on function public.workflow_rule_set(uuid, text, numeric) to authenticated;

-- applied to every new request, whichever function created it
create or replace function public.requests_route_rule() returns trigger language plpgsql security definer set search_path = public as $$
declare lim numeric; val numeric;
begin
  if new.status <> 'pending' or new.route is null or not ('g' = any(new.route)) or cardinality(new.route) < 2 then return new; end if;
  select g_above into lim from public.workflows where company_id = new.company_id and kind = new.kind;
  if lim is null then return new; end if;
  val := case when new.kind = 'leave' then new.days else new.amount end;
  if coalesce(val, 0) <= lim then new.route := array_remove(new.route, 'g'); end if;
  return new;
end $$;
drop trigger if exists requests_route_rule on public.requests;
create trigger requests_route_rule before insert on public.requests for each row execute function public.requests_route_rule();
revoke all on function public.requests_route_rule() from public, anon, authenticated;
