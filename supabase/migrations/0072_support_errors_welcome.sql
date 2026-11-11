-- Waad ERP — 0072 (1) support requests from customers to the Waad team, answered in the admin site;
-- (2) the admin site reads the script-error log (message, place, screen — no record contents);
-- (3) a welcome e-mail once a company is accepted (the notify workflow sends it and stamps welcomed_at).

-- ---------- support requests ----------
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kind text not null default 'question' check (kind in ('question','problem','suggestion')),
  subject text not null check (length(trim(subject)) between 3 and 120),
  body text not null check (length(trim(body)) between 3 and 3000),
  route text check (route is null or length(route) <= 120),
  status text not null default 'open' check (status in ('open','answered','closed')),
  reply text check (reply is null or length(reply) <= 3000),
  replied_at timestamptz,
  replied_by uuid references auth.users(id) on delete set null,
  notified_at timestamptz,            -- the team was told about it
  reply_notified_at timestamptz,      -- the customer was told about the reply
  created_at timestamptz not null default now()
);
create index if not exists support_tickets_co on public.support_tickets(company_id, created_at desc);
create index if not exists support_tickets_open on public.support_tickets(status, created_at desc);
alter table public.support_tickets enable row level security;
revoke all on public.support_tickets from anon, authenticated;

-- the company's managers (not every employee) write to Waad and read the answers
create or replace function public.support_can(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.has_role(p_company, array['owner','admin','hr','finance','accountant'])
$$;

create or replace function public.support_open(p_company uuid, p_kind text, p_subject text, p_body text, p_route text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid;
begin
  if not public.support_can(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if (select count(*) from public.support_tickets where company_id = p_company and created_at > now() - interval '1 day') >= 10 then
    raise exception 'وصلت حد ١٠ طلبات في اليوم — تواصل معنا بالواتساب إذا الأمر عاجل';
  end if;
  insert into public.support_tickets(company_id, kind, subject, body, route)
  values (p_company, coalesce(p_kind, 'question'), trim(p_subject), trim(p_body), left(regexp_replace(coalesce(p_route, ''), '[0-9a-f]{8}-[0-9a-f-]{27}', ':id', 'g'), 120))
  returning id into v;
  return v;
end $$;

create or replace function public.support_mine(p_company uuid)
returns table(id uuid, kind text, subject text, body text, status text, reply text, replied_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.support_can(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query select t.id, t.kind, t.subject, t.body, t.status, t.reply, t.replied_at, t.created_at
    from public.support_tickets t where t.company_id = p_company order by t.created_at desc limit 100;
end $$;

-- the admin site
create or replace function public.platform_tickets(p_status text default null)
returns table(id uuid, company_id uuid, company text, owner_email text, author text, kind text, subject text, body text, route text,
              status text, reply text, replied_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.platform_guard();
  return query select t.id, t.company_id, c.name,
      (select u.email::text from public.members m join auth.users u on u.id = m.user_id where m.company_id = c.id and m.role = 'owner' limit 1),
      (select u.email::text from auth.users u where u.id = t.user_id), t.kind, t.subject, t.body, t.route, t.status, t.reply, t.replied_at, t.created_at
    from public.support_tickets t join public.companies c on c.id = t.company_id
   where p_status is null or t.status = p_status
   order by (t.status = 'open') desc, t.created_at desc limit 300;
end $$;

create or replace function public.platform_reply_ticket(p_id uuid, p_reply text, p_status text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.platform_guard();
  if p_status not in ('open','answered','closed') then raise exception 'حالة غير معروفة'; end if;
  update public.support_tickets set
      reply = coalesce(nullif(trim(p_reply), ''), reply),
      replied_at = case when nullif(trim(p_reply), '') is not null and nullif(trim(p_reply), '') is distinct from reply then now() else replied_at end,
      replied_by = case when nullif(trim(p_reply), '') is not null then auth.uid() else replied_by end,
      reply_notified_at = case when nullif(trim(p_reply), '') is not null and nullif(trim(p_reply), '') is distinct from reply then null else reply_notified_at end,
      status = p_status
   where id = p_id;
  if not found then raise exception 'الطلب غير موجود'; end if;
end $$;

-- ---------- script errors seen by users, grouped (no record contents are ever logged) ----------
create or replace function public.platform_errors(p_days int default 7)
returns table(message text, source text, route text, times int, users int, companies int, last_at timestamptz, agent text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.platform_guard();
  return query select e.message, max(e.source), max(e.route), count(*)::int, count(distinct e.user_id)::int, count(distinct e.company_id)::int,
      max(e.at), (array_agg(e.agent order by e.at desc))[1]
    from public.client_errors e where e.at > now() - make_interval(days => least(greatest(coalesce(p_days, 7), 1), 30))
   group by e.message order by max(e.at) desc limit 200;
end $$;

-- ---------- welcome e-mail after acceptance ----------
alter table public.company_subscriptions add column if not exists welcomed_at timestamptz;
update public.company_subscriptions set welcomed_at = now() where welcomed_at is null and status <> 'pending';   -- existing customers are not new

revoke all on function public.support_can(uuid), public.support_open(uuid, text, text, text, text), public.support_mine(uuid),
  public.platform_tickets(text), public.platform_reply_ticket(uuid, text, text), public.platform_errors(int) from public, anon;
grant execute on function public.support_can(uuid), public.support_open(uuid, text, text, text, text), public.support_mine(uuid),
  public.platform_tickets(text), public.platform_reply_ticket(uuid, text, text), public.platform_errors(int) to authenticated;
