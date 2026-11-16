-- 0101 — deleting a company's data after it leaves (owner's decision, 2026-11-17):
-- * a trial/subscription that ended and was not renewed keeps all its data; nothing is ever deleted automatically.
-- * 60 days after the end (or after an admin's extension, purge_hold_until) the company shows in the admin site
--   under «بانتظار قرار الحذف»; the customer is e-mailed 30 days and 7 days before that (notify job, purge_notices_due).
-- * only a platform admin deletes, by typing the company's name; allowed for a company that ended, is suspended or
--   was never accepted — never for a live one (a customer who asks to be deleted early is suspended first).
-- * the deletion removes every row of the company (append-only guards step aside for this one transaction only),
--   the sign-in accounts that belonged only to it, and keeps a short log (company_deletions) + Waad's own payment
--   records (platform_payments keep the name, company_id becomes null).

alter table public.company_subscriptions add column if not exists purge_hold_until date;
alter table public.company_subscriptions add column if not exists purge_warn1 date;   -- the purge date the 30-day notice was sent for
alter table public.company_subscriptions add column if not exists purge_warn2 date;   -- the purge date the 7-day notice was sent for

-- Waad's revenue records outlive the company
alter table public.platform_payments add column if not exists company_name text;
alter table public.platform_payments alter column company_id drop not null;
alter table public.platform_payments drop constraint if exists platform_payments_company_id_fkey;
alter table public.platform_payments add constraint platform_payments_company_id_fkey foreign key (company_id) references public.companies(id) on delete set null;

create table if not exists public.company_deletions (
  id uuid primary key default gen_random_uuid(),
  company_name text not null,
  registered_on date,
  ended_on date,
  deleted_at timestamptz not null default now(),
  deleted_by uuid,
  deleted_by_email text,
  users_removed int not null default 0,
  reason text
);
alter table public.company_deletions enable row level security;   -- no policies: read only through platform_deletions()

-- when the company's access ended (null = still live, or never accepted)
create or replace function public.sub_ended_on(s public.company_subscriptions) returns date language sql stable as $$
  select case when s.status = 'trial' and s.trial_ends < (now() at time zone 'Asia/Riyadh')::date then s.trial_ends
              when s.status = 'active' and s.sub_ends < (now() at time zone 'Asia/Riyadh')::date then s.sub_ends end
$$;
-- the day it enters «بانتظار قرار الحذف»
create or replace function public.purge_on(s public.company_subscriptions) returns date language sql stable as $$
  select case when public.sub_ended_on(s) is not null then greatest(public.sub_ended_on(s) + 60, s.purge_hold_until) end
$$;

-- ---------- the append-only guards step aside only inside platform_company_purge ----------
create or replace function public.purging() returns boolean language sql stable as $$
  select coalesce(current_setting('waad.purge', true), '') = 'on'
$$;

create or replace function public.block_change() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' and public.purging() then return old; end if;
  raise exception '% records are append-only and cannot be modified', tg_table_name using errcode = '42501';
end $$;

create or replace function public.cn_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' and public.purging() then return old; end if;
  -- the only allowed update is the one-time totals fill inside post_credit_note
  if tg_op = 'UPDATE' and old.total = 0 and old.subtotal = 0 and old.vat = 0
     and (new.id, new.company_id, new.no, new.kind, new.doc_id, new.party_id, new.date, new.reason) = (old.id, old.company_id, old.no, old.kind, old.doc_id, old.party_id, old.date, old.reason) then
    return new;
  end if;
  raise exception 'credit_notes records are append-only and cannot be modified' using errcode = '42501';
end $$;

create or replace function public.zatca_docs_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' and public.purging() then return old; end if;
  if tg_op = 'DELETE' then raise exception 'سجل زاتكا لا يُحذف' using errcode = '42501'; end if;
  if (new.company_id, new.icv, new.doc_id, new.inv_type) is distinct from (old.company_id, old.icv, old.doc_id, old.inv_type)
     or (new.kind is distinct from old.kind and not (old.kind = 'invoice' and new.kind = 'debit' and old.hash is null))
     or (old.pih is not null and new.pih is distinct from old.pih) or (old.hash is not null and new.hash is distinct from old.hash) then
    raise exception 'سجل زاتكا لا يتغيّر' using errcode = '42501';
  end if;
  return new;
end $$;

create or replace function public.audit_trigger() returns trigger language plpgsql security definer set search_path = public as $$
declare r jsonb; cid uuid; eid text;
begin
  if public.purging() then return coalesce(new, old); end if;   -- nothing to log about a company being erased
  r := to_jsonb(coalesce(new, old));
  cid := nullif(r->>'company_id','')::uuid;
  eid := coalesce(r->>'id', r->>'code', r->>'user_id');
  insert into public.audit_log(company_id, actor, action, entity, entity_id, data)
  values (cid, auth.uid(), lower(tg_op), tg_table_name, eid,
          case when tg_op = 'UPDATE' then jsonb_build_object('old', to_jsonb(old), 'new', to_jsonb(new)) else r end);
  return coalesce(new, old);
end $$;

-- ---------- admin site ----------
-- companies that ended and were not renewed, with their purge date (due = it is time to decide)
create or replace function public.platform_purge_queue() returns table(company_id uuid, name text, status text, ended_on date, purge_on date, due boolean, warned int)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.platform_guard();
  return query select c.id, c.name, s.status, public.sub_ended_on(s), public.purge_on(s), public.purge_on(s) <= (now() at time zone 'Asia/Riyadh')::date,
         (case when s.purge_warn2 = public.purge_on(s) then 2 when s.purge_warn1 = public.purge_on(s) then 1 else 0 end)
    from public.company_subscriptions s join public.companies c on c.id = s.company_id
   where public.sub_ended_on(s) is not null order by 5, 2;
end $$;

-- give an ended company more time before the decision (the notices start over for the new date)
create or replace function public.platform_purge_extend(p_company uuid, p_days int) returns date
language plpgsql security definer set search_path = public as $$
declare s public.company_subscriptions; d date;
begin
  perform public.platform_guard();
  if p_days is null or p_days < 1 or p_days > 365 then raise exception 'مدة غير صحيحة'; end if;
  select * into s from public.company_subscriptions where company_id = p_company;
  if public.sub_ended_on(s) is null then raise exception 'المنشأة ليست منتهية'; end if;
  d := greatest(public.purge_on(s), (now() at time zone 'Asia/Riyadh')::date) + p_days;
  update public.company_subscriptions set purge_hold_until = d where company_id = p_company;
  return d;
end $$;

-- delete everything of one company; p_confirm must be its exact name
create or replace function public.platform_company_purge(p_company uuid, p_confirm text, p_reason text default null) returns void
language plpgsql security definer set search_path = public, auth as $$
declare c public.companies; s public.company_subscriptions; v_users uuid[]; v_pass int; v_left int; v_t text;
begin
  perform public.platform_guard();
  select * into c from public.companies where id = p_company for update;
  if c.id is null then raise exception 'المنشأة غير موجودة'; end if;
  if btrim(coalesce(p_confirm, '')) <> btrim(c.name) then raise exception 'اكتب اسم المنشأة كما هو للتأكيد'; end if;
  select * into s from public.company_subscriptions where company_id = p_company;
  if s.company_id is not null and s.status <> 'suspended' and s.status <> 'pending' and public.sub_ended_on(s) is null then
    raise exception 'المنشأة شغّالة. أوقفها أولا ثم احذفها'; end if;
  -- sign-in accounts that belong to this company only (never a Waad team account)
  select coalesce(array_agg(distinct m.user_id), '{}') into v_users from public.members m
   where m.company_id = p_company
     and not exists (select 1 from public.members o where o.user_id = m.user_id and o.company_id <> p_company)
     and not exists (select 1 from public.platform_admins a where a.user_id = m.user_id);
  update public.platform_payments set company_name = coalesce(company_name, c.name) where company_id = p_company;
  insert into public.company_deletions(company_name, registered_on, ended_on, deleted_by, deleted_by_email, users_removed, reason)
  values (c.name, (c.created_at at time zone 'Asia/Riyadh')::date, case when s.company_id is not null then public.sub_ended_on(s) end,
          auth.uid(), (select email from auth.users where id = auth.uid()), coalesce(array_length(v_users, 1), 0), nullif(btrim(coalesce(p_reason, '')), ''));
  perform set_config('waad.purge', 'on', true);
  -- table by table: rows that other rows still point to wait for the next pass (lines go with their documents)
  for v_pass in 1..12 loop
    v_left := 0;
    for v_t in select c2.table_name from information_schema.columns c2 join information_schema.tables t2 using (table_schema, table_name)
                where c2.table_schema = 'public' and c2.column_name = 'company_id' and t2.table_type = 'BASE TABLE'
                  and c2.table_name not in ('companies', 'platform_payments', 'company_deletions') loop
      begin
        execute format('delete from public.%I where company_id = $1', v_t) using p_company;
      exception when foreign_key_violation then v_left := v_left + 1;
      end;
    end loop;
    exit when v_left = 0;
  end loop;
  delete from public.companies where id = p_company;
  delete from auth.users where id = any(v_users);
  perform set_config('waad.purge', '', true);
end $$;

create or replace function public.platform_deletions() returns setof public.company_deletions
language plpgsql stable security definer set search_path = public as $$
begin perform public.platform_guard(); return query select * from public.company_deletions order by deleted_at desc limit 200; end $$;

-- payments list keeps the payments of deleted companies (by their saved name)
create or replace function public.platform_payments_list(p_from date, p_to date) returns table(id uuid, company_id uuid, company text, amount numeric, paid_on date, method text, plan text, days int, note text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.platform_guard();
  return query select p.id, p.company_id, coalesce(c.name, p.company_name), p.amount, p.paid_on, p.method, pl.name, p.days, p.note
    from public.platform_payments p left join public.companies c on c.id = p.company_id left join public.platform_plans pl on pl.id = p.plan_id
   where p.paid_on between coalesce(p_from, '2000-01-01') and coalesce(p_to, '2999-12-31') order by p.paid_on desc, p.created_at desc;
end $$;

-- ---------- notify job (service connection): the customer's two notices ----------
-- stage 1 = 30 days or less before the purge date, stage 2 = 7 days or less; each sent once per purge date
create or replace function public.purge_notices_due() returns table(company_id uuid, name text, email text, stage int, ended_on date, purge_on date)
language sql stable security definer set search_path = public as $$
  select x.company_id, x.name, x.email, x.stage, x.ended_on, x.purge_on from (
    select s.company_id, c.name, public.sub_ended_on(s) as ended_on, public.purge_on(s) as purge_on,
           (select u.email from public.members m join auth.users u on u.id = m.user_id where m.company_id = c.id and m.role = 'owner' limit 1) as email,
           case when public.purge_on(s) - (now() at time zone 'Asia/Riyadh')::date <= 7 and s.purge_warn2 is distinct from public.purge_on(s) then 2
                when public.purge_on(s) - (now() at time zone 'Asia/Riyadh')::date <= 30 and s.purge_warn1 is distinct from public.purge_on(s)
                     and s.purge_warn2 is distinct from public.purge_on(s) then 1 end as stage
      from public.company_subscriptions s join public.companies c on c.id = s.company_id
     where public.sub_ended_on(s) is not null and public.purge_on(s) >= (now() at time zone 'Asia/Riyadh')::date) x
   where x.stage is not null limit 50
$$;
create or replace function public.purge_notice_sent(p_company uuid, p_stage int, p_purge_on date) returns void
language sql security definer set search_path = public as $$
  update public.company_subscriptions set purge_warn1 = case when p_stage >= 1 then p_purge_on else purge_warn1 end,
         purge_warn2 = case when p_stage = 2 then p_purge_on else purge_warn2 end where company_id = p_company
$$;

revoke all on function public.platform_purge_queue(), public.platform_purge_extend(uuid, int), public.platform_company_purge(uuid, text, text),
  public.platform_deletions(), public.purge_notices_due(), public.purge_notice_sent(uuid, int, date), public.purging(),
  public.sub_ended_on(public.company_subscriptions), public.purge_on(public.company_subscriptions) from public, anon, authenticated;
grant execute on function public.platform_purge_queue(), public.platform_purge_extend(uuid, int), public.platform_company_purge(uuid, text, text),
  public.platform_deletions() to authenticated;
grant execute on function public.purging() to authenticated;
