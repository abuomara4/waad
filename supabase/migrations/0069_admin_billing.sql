-- Waad ERP — 0069 admin site: price plans, payments received, notes per company, quick actions, subscription history.
-- All of it is Waad's own data about its customers (no company records). Platform admins only.

-- ---------- price plans ----------
create table if not exists public.platform_plans (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (length(trim(name)) between 1 and 40),
  price numeric(12,2) not null check (price >= 0),
  period_days int not null default 30 check (period_days between 1 and 3660),
  modules text[] not null default array['hr','finance','sales','purch','stock','proj'] check (modules <@ array['hr','finance','sales','purch','stock','proj']),
  max_users int check (max_users is null or max_users between 1 and 100000),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.platform_plans enable row level security;
revoke all on public.platform_plans from anon, authenticated;
alter table public.company_subscriptions add column if not exists plan_id uuid references public.platform_plans(id) on delete set null;

-- ---------- payments received from companies ----------
create table if not exists public.platform_payments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  paid_on date not null default ((now() at time zone 'Asia/Riyadh')::date),
  method text not null default 'transfer' check (method in ('transfer','card','cash','other')),
  plan_id uuid references public.platform_plans(id) on delete set null,
  days int check (days is null or days between 1 and 3660),
  note text check (note is null or length(note) <= 300),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists platform_payments_co on public.platform_payments(company_id, paid_on desc);
alter table public.platform_payments enable row level security;
revoke all on public.platform_payments from anon, authenticated;

-- ---------- the team's notes about a company ----------
create table if not exists public.platform_notes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  body text not null check (length(trim(body)) between 1 and 1000),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists platform_notes_co on public.platform_notes(company_id, created_at desc);
alter table public.platform_notes enable row level security;
revoke all on public.platform_notes from anon, authenticated;

create or replace function public.platform_guard() returns void language plpgsql stable security definer set search_path = public as $$
begin if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if; end $$;

-- plans
create or replace function public.platform_plans_list() returns setof public.platform_plans
language plpgsql stable security definer set search_path = public as $$
begin perform public.platform_guard(); return query select * from public.platform_plans order by active desc, price; end $$;
create or replace function public.platform_save_plan(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid := nullif(p->>'id', '')::uuid; m text[] := case when jsonb_typeof(p->'modules') = 'array' then array(select jsonb_array_elements_text(p->'modules')) else array['hr','finance','sales','purch','stock','proj'] end;
begin
  perform public.platform_guard();
  if nullif(trim(p->>'name'), '') is null then raise exception 'اكتب اسم الباقة'; end if;
  if coalesce(cardinality(m), 0) = 0 then raise exception 'اختر قسماً واحداً على الأقل'; end if;
  if v is null then
    insert into public.platform_plans(name, price, period_days, modules, max_users, active)
    values (trim(p->>'name'), coalesce((p->>'price')::numeric, 0), coalesce((p->>'period_days')::int, 30), m, nullif(p->>'max_users', '')::int, coalesce((p->>'active')::boolean, true))
    returning id into v;
  else
    update public.platform_plans set name = trim(p->>'name'), price = coalesce((p->>'price')::numeric, 0), period_days = coalesce((p->>'period_days')::int, 30),
      modules = m, max_users = nullif(p->>'max_users', '')::int, active = coalesce((p->>'active')::boolean, true) where id = v;
  end if;
  return v;
exception when unique_violation then raise exception 'اسم الباقة مستخدم مسبقاً';
end $$;

-- one company: subscription metadata, payments, notes, and the history of its subscription changes
create or replace function public.platform_company(p_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.platform_guard();
  return (select jsonb_build_object(
    'company', (select to_jsonb(x) from public.platform_companies() x where x.company_id = p_company),
    'plan_id', (select plan_id from public.company_subscriptions where company_id = p_company),
    'payments', coalesce((select jsonb_agg(to_jsonb(p) order by p.paid_on desc, p.created_at desc) from public.platform_payments p where p.company_id = p_company), '[]'),
    'notes', coalesce((select jsonb_agg(jsonb_build_object('id', n.id, 'body', n.body, 'at', n.created_at,
                 'by', (select coalesce(a.username, u.email) from auth.users u left join public.platform_admins a on a.user_id = u.id where u.id = n.created_by)) order by n.created_at desc)
               from public.platform_notes n where n.company_id = p_company), '[]'),
    'history', coalesce((select jsonb_agg(jsonb_build_object('at', l.at, 'action', l.action, 'status', l.r->>'status', 'plan', l.r->>'plan',
                 'trial_ends', l.r->>'trial_ends', 'sub_ends', l.r->>'sub_ends') order by l.at desc)
               from (select at, action, coalesce(data->'new', data) as r from public.audit_log    -- an update is stored as {old, new}
                      where company_id = p_company and entity = 'company_subscriptions' order by at desc limit 50) l), '[]')));
end $$;

create or replace function public.platform_add_note(p_company uuid, p_body text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.platform_guard();
  if nullif(trim(p_body), '') is null then raise exception 'اكتب الملاحظة'; end if;
  insert into public.platform_notes(company_id, body) values (p_company, trim(p_body));
end $$;
create or replace function public.platform_delete_note(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin perform public.platform_guard(); delete from public.platform_notes where id = p_id; end $$;

-- a payment; with a plan and/or days it also activates the subscription and moves its end date forward
create or replace function public.platform_add_payment(p_company uuid, p_amount numeric, p_paid_on date, p_method text, p_plan uuid, p_days int, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare pl public.platform_plans; s public.company_subscriptions; v_days int := p_days; v_from date;
begin
  perform public.platform_guard();
  if coalesce(p_amount, 0) <= 0 then raise exception 'اكتب المبلغ'; end if;
  if p_plan is not null then select * into pl from public.platform_plans where id = p_plan; v_days := coalesce(v_days, pl.period_days); end if;
  insert into public.platform_payments(company_id, amount, paid_on, method, plan_id, days, note)
  values (p_company, p_amount, coalesce(p_paid_on, (now() at time zone 'Asia/Riyadh')::date), coalesce(p_method, 'transfer'), p_plan, v_days, nullif(trim(p_note), ''));
  if v_days is not null then
    select * into s from public.company_subscriptions where company_id = p_company;
    v_from := greatest(current_date - 1, case when s.status = 'active' then coalesce(s.sub_ends, current_date - 1) else current_date - 1 end);
    update public.company_subscriptions set status = 'active', sub_ends = v_from + v_days, trial_ends = null,
      plan_id = coalesce(p_plan, plan_id), plan = coalesce(pl.name, case when plan = 'trial' then 'اشتراك' else plan end),
      modules = coalesce(pl.modules, modules), max_users = coalesce(pl.max_users, max_users), updated_at = now()
     where company_id = p_company;
  end if;
end $$;
create or replace function public.platform_delete_payment(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin perform public.platform_guard(); delete from public.platform_payments where id = p_id; end $$;
create or replace function public.platform_payments_list(p_from date, p_to date) returns table(id uuid, company_id uuid, company text, amount numeric, paid_on date, method text, plan text, days int, note text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.platform_guard();
  return query select p.id, p.company_id, c.name, p.amount, p.paid_on, p.method, pl.name, p.days, p.note
    from public.platform_payments p join public.companies c on c.id = p.company_id left join public.platform_plans pl on pl.id = p.plan_id
   where p.paid_on between coalesce(p_from, '2000-01-01') and coalesce(p_to, '2999-12-31') order by p.paid_on desc, p.created_at desc;
end $$;

-- quick actions from the list: extend by N days (from the current end, or today if it already passed), suspend, resume
create or replace function public.platform_quick(p_company uuid, p_action text, p_days int default null) returns void
language plpgsql security definer set search_path = public as $$
declare s public.company_subscriptions;
begin
  perform public.platform_guard();
  select * into s from public.company_subscriptions where company_id = p_company for update;
  if not found then raise exception 'المنشأة غير موجودة'; end if;
  if p_action = 'extend' then
    if coalesce(p_days, 0) < 1 or p_days > 3660 then raise exception 'المدة من يوم إلى ١٠ سنوات'; end if;
    if s.status = 'trial' then
      update public.company_subscriptions set trial_ends = greatest(coalesce(trial_ends, current_date), current_date) + p_days, updated_at = now() where company_id = p_company;
    elsif s.status = 'active' then
      update public.company_subscriptions set sub_ends = greatest(coalesce(sub_ends, current_date), current_date) + p_days, updated_at = now() where company_id = p_company;
    else raise exception 'التمديد للتجربة أو الاشتراك فقط'; end if;
  elsif p_action = 'suspend' then
    update public.company_subscriptions set status = 'suspended', updated_at = now() where company_id = p_company;
  elsif p_action = 'resume' then
    update public.company_subscriptions set status = case when sub_ends is not null or plan_id is not null then 'active' else 'trial' end, updated_at = now() where company_id = p_company;
  else raise exception 'إجراء غير معروف'; end if;
end $$;

revoke all on function public.platform_guard(), public.platform_plans_list(), public.platform_save_plan(jsonb), public.platform_company(uuid),
  public.platform_add_note(uuid, text), public.platform_delete_note(uuid), public.platform_add_payment(uuid, numeric, date, text, uuid, int, text),
  public.platform_delete_payment(uuid), public.platform_payments_list(date, date), public.platform_quick(uuid, text, int) from public, anon;
grant execute on function public.platform_guard(), public.platform_plans_list(), public.platform_save_plan(jsonb), public.platform_company(uuid),
  public.platform_add_note(uuid, text), public.platform_delete_note(uuid), public.platform_add_payment(uuid, numeric, date, text, uuid, int, text),
  public.platform_delete_payment(uuid), public.platform_payments_list(date, date), public.platform_quick(uuid, text, int) to authenticated;
