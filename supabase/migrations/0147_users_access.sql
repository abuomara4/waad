-- Users page and access log details (QA report): the last sign-in and e-mail of each member (owner / admin / HR), and the IP
-- address and device of every access-log entry, taken on the server from the request itself (the app cannot set them).

-- the company's members with their sign-in e-mail and last sign-in (auth.users), for the users page
create or replace function public.members_activity(p_company uuid) returns table(user_id uuid, email text, last_sign_in_at timestamptz, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select u.id, u.email::text, u.last_sign_in_at, u.created_at from public.members m join auth.users u on u.id = m.user_id
   where m.company_id = p_company and public.has_role(p_company, array['owner','admin','hr'])
$$;

alter table public.access_log add column if not exists ip text check (ip is null or length(ip) <= 64);
alter table public.access_log add column if not exists ua text check (ua is null or length(ua) <= 300);
create or replace function public.access_log_meta() returns trigger language plpgsql as $$
declare h json;
begin
  begin h := nullif(current_setting('request.headers', true), '')::json; exception when others then h := null; end;
  new.ip := null; new.ua := null;
  if h is not null then
    new.ip := left(nullif(btrim(coalesce(h->>'cf-connecting-ip', split_part(coalesce(h->>'x-forwarded-for', ''), ',', 1), h->>'x-real-ip', '')), ''), 64);
    new.ua := left(nullif(h->>'user-agent', ''), 300);
  end if;
  return new;
end $$;
drop trigger if exists access_log_meta on public.access_log;
create trigger access_log_meta before insert on public.access_log for each row execute function public.access_log_meta();

revoke all on function public.access_log_meta() from public, anon, authenticated;
revoke all on function public.members_activity(uuid) from public, anon;
grant execute on function public.members_activity(uuid) to authenticated;
notify pgrst, 'reload schema';
