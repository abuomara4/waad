-- 0106 — notifications on the phone / computer (Web Push), free: the notify job (every 10 minutes) sends them.
-- * a user turns them on per device (push_subscribe); the browser gives an endpoint + keys, stored per user;
-- * the job's VAPID key pair is made by the job itself on its first run and kept server-only (push_keys) — nobody
--   handles it; the app reads only the public half (push_public_key);
-- * what is sent (push_due, each once per user — push_sent): a request waiting for my approval, a decision on my own
--   request, a document waiting for my signature, a colleague mentioning me in a note, my payslip. Only events after
--   the device was registered and within the last 2 days, so turning it on never floods old news.

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique check (endpoint ~ '^https://' and length(endpoint) < 1000),
  p256dh text not null check (length(p256dh) < 200),
  auth text not null check (length(auth) < 100),
  created_at timestamptz not null default now()
);
alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from anon, authenticated;

create table if not exists public.push_keys (id int primary key default 1 check (id = 1), public_key text not null, private_pem text not null, created_at timestamptz not null default now());
alter table public.push_keys enable row level security;
revoke all on public.push_keys from anon, authenticated;

create table if not exists public.push_sent (user_id uuid not null references auth.users(id) on delete cascade, key text not null, at timestamptz not null default now(), primary key (user_id, key));
alter table public.push_sent enable row level security;
revoke all on public.push_sent from anon, authenticated;

create or replace function public.push_public_key() returns text language sql stable security definer set search_path = public as $$
  select public_key from public.push_keys where id = 1
$$;
create or replace function public.push_subscribe(p_endpoint text, p_p256dh text, p_auth text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'سجّل الدخول أولاً' using errcode = '42501'; end if;
  if (select count(*) from public.push_subscriptions where user_id = auth.uid()) >= 10 then
    delete from public.push_subscriptions where id = (select id from public.push_subscriptions where user_id = auth.uid() order by created_at limit 1); end if;
  insert into public.push_subscriptions(user_id, endpoint, p256dh, auth) values (auth.uid(), p_endpoint, p_p256dh, p_auth)
    on conflict (endpoint) do update set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth;
end $$;
create or replace function public.push_unsubscribe(p_endpoint text) returns void
language sql security definer set search_path = public as $$
  delete from public.push_subscriptions where endpoint = p_endpoint and user_id = auth.uid()
$$;

create or replace function public.request_kind_ar(k text) returns text language sql immutable as $$
  select case k when 'leave' then 'إجازة' when 'permit' then 'استئذان' when 'cert' then 'تعريف بالراتب' when 'advance' then 'سلفة' when 'resign' then 'استقالة'
    when 'settle' then 'مخالصة' when 'expense' then 'مطالبة مصروفات' when 'update' then 'تحديث بيانات' when 'punch' then 'نسيان بصمة' when 'ticket' then 'تذكرة سفر'
    when 'visa' then 'تأشيرة خروج وعودة' when 'purchase' then 'طلب شراء' else k end
$$;

-- for the notify job (database connection): what each subscribed user should hear about now
create or replace function public.push_due() returns table(user_id uuid, key text, title text, body text, url text)
language plpgsql security definer set search_path = public, auth as $$
declare u record; since timestamptz;
begin
  for u in select s.user_id, min(s.created_at) as first_at from public.push_subscriptions s group by s.user_id loop
    since := greatest(u.first_at, now() - interval '2 days');
    perform set_config('request.jwt.claim.sub', u.user_id::text, true);   -- can_act() decides as this user
    return query
    with mine as (select m.company_id, m.employee_id from public.members m where m.user_id = u.user_id and public.member_live(m.employee_id, m.role)),
    ev as (
      -- a request waiting for my approval at its current step
      select 'req:' || r.id || ':' || r.step as k, 'طلب بانتظار اعتمادك' as t,
             coalesce((select e.full_name from public.employees e where e.id = r.employee_id), '') || ' — ' || public.request_kind_ar(r.kind) as b, '#/approvals' as l
        from public.requests r join mine on mine.company_id = r.company_id
       where r.status = 'pending' and coalesce(r.step_at, r.created_at) > since and public.can_act(r, r.route[r.step + 1])
      union all
      -- a decision on my own request
      select 'dec:' || r.id, case when r.status = 'approved' then 'اعتُمد طلبك' else 'رُفض طلبك' end, public.request_kind_ar(r.kind), '#/requests'
        from public.requests r join mine on mine.employee_id = r.employee_id
       where r.status in ('approved', 'rejected') and r.decided_at > since
      union all
      -- a document waiting for my signature
      select 'sig:' || s.id, 'مستند بانتظار توقيعك', s.title, '#/sign'
        from public.signature_requests s join mine on mine.employee_id = s.employee_id
       where s.status = 'pending' and s.created_at > since
      union all
      -- a colleague mentioned me
      select 'note:' || n.id, 'أشار إليك زميل في ملاحظة', left(n.body, 120), '#/home'
        from public.record_notes n join mine on mine.company_id = n.company_id
       where u.user_id = any(n.mentions) and n.created_by is distinct from u.user_id and n.created_at > since
      union all
      -- my payslip is out
      select 'pay:' || p.id, 'صدرت قسيمة راتبك', p.month || '/' || p.year, '#/payslips'
        from public.payroll_runs p join mine on mine.company_id = p.company_id
       where p.status <> 'draft' and p.approved_at > since and mine.employee_id is not null
         and exists(select 1 from public.payroll_lines l where l.run_id = p.id and l.employee_id = mine.employee_id))
    select u.user_id, ev.k, ev.t, ev.b, ev.l from ev
     where not exists(select 1 from public.push_sent x where x.user_id = u.user_id and x.key = ev.k);
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

revoke all on function public.push_due(), public.request_kind_ar(text) from public, anon, authenticated;
revoke all on function public.push_subscribe(text, text, text), public.push_unsubscribe(text), public.push_public_key() from public, anon;
grant execute on function public.push_subscribe(text, text, text), public.push_unsubscribe(text), public.push_public_key() to authenticated;
