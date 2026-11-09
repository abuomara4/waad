-- Waad ERP — 0051 CRM: opportunities through their stages, follow-ups (calls, meetings, tasks), and conversion to a quotation.
-- Part of the sales module: same permission ('sales') and same package switch.

create table if not exists public.crm_leads (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  title text not null check (length(trim(title)) >= 3),
  party_id uuid references public.parties(id),
  prospect text,                 -- company name before it becomes a customer
  contact_name text,
  phone text,
  email text,
  source text not null default 'other' check (source in ('website','referral','call','social','exhibition','campaign','other')),
  stage text not null default 'new' check (stage in ('new','contacted','qualified','proposal','negotiation','won','lost')),
  value numeric(14,2) check (value is null or value >= 0),
  probability int check (probability is null or probability between 0 and 100),
  expected_close date,
  owner_id uuid references auth.users(id) default auth.uid(),
  quote_id uuid references public.sales_orders(id),
  lost_reason text,
  note text,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, no),
  check (party_id is not null or length(trim(coalesce(prospect, ''))) >= 2),
  check (stage <> 'lost' or length(trim(coalesce(lost_reason, ''))) >= 3)
);
create index if not exists crm_leads_company on public.crm_leads(company_id, stage);

create table if not exists public.crm_activities (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  lead_id uuid not null references public.crm_leads(id) on delete cascade,
  kind text not null check (kind in ('call','meeting','email','whatsapp','visit','task','note')),
  due_at timestamptz,
  done boolean not null default false,
  done_at timestamptz,
  note text not null check (length(trim(note)) >= 2),
  user_id uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists crm_activities_lead on public.crm_activities(lead_id);
create index if not exists crm_activities_due on public.crm_activities(company_id, done, due_at);

-- normalise, number, stamp stage changes; a won/lost opportunity is closed
create or replace function public.crm_lead_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.no := public.next_doc_no(new.company_id, 'OP');
  elsif new.company_id <> old.company_id or new.no <> old.no then
    raise exception 'لا يتغير رقم الفرصة أو منشأتها';
  end if;
  new.prospect := nullif(trim(coalesce(new.prospect, '')), '');
  new.email := nullif(lower(trim(coalesce(new.email, ''))), '');
  new.phone := nullif(replace(trim(coalesce(new.phone, '')), ' ', ''), '');
  if new.email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'البريد الإلكتروني غير صحيح'; end if;
  if new.party_id is not null and not exists(select 1 from public.parties where id = new.party_id and company_id = new.company_id and kind = 'customer') then
    raise exception 'العميل غير موجود';
  end if;
  if new.probability is null then
    new.probability := case new.stage when 'new' then 10 when 'contacted' then 20 when 'qualified' then 40 when 'proposal' then 60
                                      when 'negotiation' then 80 when 'won' then 100 else 0 end;
  elsif tg_op = 'UPDATE' and new.stage <> old.stage and new.probability = old.probability then
    new.probability := case new.stage when 'new' then 10 when 'contacted' then 20 when 'qualified' then 40 when 'proposal' then 60
                                      when 'negotiation' then 80 when 'won' then 100 else 0 end;
  end if;
  if new.stage in ('won','lost') then new.closed_at := coalesce(new.closed_at, now()); else new.closed_at := null; new.lost_reason := null; end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists crm_leads_guard on public.crm_leads;
create trigger crm_leads_guard before insert or update on public.crm_leads for each row execute function public.crm_lead_guard();

create or replace function public.crm_activity_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from public.crm_leads where id = new.lead_id and company_id = new.company_id) then raise exception 'الفرصة غير موجودة'; end if;
  new.done_at := case when new.done then coalesce(new.done_at, now()) end;
  return new;
end $$;
drop trigger if exists crm_activities_guard on public.crm_activities;
create trigger crm_activities_guard before insert or update on public.crm_activities for each row execute function public.crm_activity_guard();

alter table public.crm_leads enable row level security;
alter table public.crm_activities enable row level security;
drop policy if exists crm_leads_all on public.crm_leads;
create policy crm_leads_all on public.crm_leads for all using (public.fin_can(company_id, 'sales')) with check (public.fin_can(company_id, 'sales'));
drop policy if exists crm_act_all on public.crm_activities;
create policy crm_act_all on public.crm_activities for all using (public.fin_can(company_id, 'sales')) with check (public.fin_can(company_id, 'sales'));
revoke all on public.crm_leads, public.crm_activities from anon;
grant select, insert, update on public.crm_leads to authenticated;
grant select, insert, update, delete on public.crm_activities to authenticated;
drop trigger if exists audit_crm_leads on public.crm_leads;
create trigger audit_crm_leads after insert or update or delete on public.crm_leads for each row execute function public.audit_trigger();

-- the prospect becomes a customer (or the existing customer with that name is reused)
create or replace function public.crm_make_customer(p_lead uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare l public.crm_leads; pid uuid;
begin
  select * into l from public.crm_leads where id = p_lead for update;
  if not found then raise exception 'الفرصة غير موجودة'; end if;
  perform public.require_fin(l.company_id, 'sales');
  if l.party_id is not null then return l.party_id; end if;
  select id into pid from public.parties where company_id = l.company_id and kind = 'customer' and name = l.prospect;
  if pid is null then
    insert into public.parties(company_id, kind, name, email, contact_name, phone)
    values (l.company_id, 'customer', l.prospect, l.email, l.contact_name, case when l.phone ~ '^\+?[0-9]{7,15}$' then l.phone end) returning id into pid;
  end if;
  update public.crm_leads set party_id = pid where id = p_lead;
  return pid;
end $$;

-- a quotation made from the opportunity is linked to it and moves it to «proposal»
create or replace function public.crm_link_quote(p_lead uuid, p_quote uuid) returns void
language plpgsql security definer set search_path = public as $$
declare l public.crm_leads; q public.sales_orders;
begin
  select * into l from public.crm_leads where id = p_lead for update;
  if not found then raise exception 'الفرصة غير موجودة'; end if;
  perform public.require_fin(l.company_id, 'sales');
  select * into q from public.sales_orders where id = p_quote and company_id = l.company_id and kind = 'quote';
  if not found then raise exception 'عرض السعر غير موجود'; end if;
  update public.crm_leads set quote_id = q.id, party_id = q.party_id, value = coalesce(q.total, value),
    stage = case when stage in ('new','contacted','qualified') then 'proposal' else stage end where id = p_lead;
end $$;

-- quotation accepted → opportunity won; rejected → back to negotiation (the salesperson decides if it is lost)
create or replace function public.crm_quote_sync() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'quote' and new.status is distinct from old.status then
    if new.status = 'accepted' then
      update public.crm_leads set stage = 'won' where quote_id = new.id and stage not in ('won','lost');
    elsif new.status = 'rejected' then
      update public.crm_leads set stage = 'negotiation' where quote_id = new.id and stage not in ('won','lost');
    end if;
  end if;
  return new;
end $$;
drop trigger if exists sales_orders_crm_sync on public.sales_orders;
create trigger sales_orders_crm_sync after update of status on public.sales_orders for each row execute function public.crm_quote_sync();

-- pipeline summary: count and value per stage, weighted forecast, overdue follow-ups
create or replace function public.crm_summary(p_company uuid)
returns table(stage text, n int, value numeric, weighted numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'sales');
  return query select l.stage, count(*)::int, coalesce(sum(l.value), 0), coalesce(round(sum(l.value * l.probability / 100.0), 2), 0)
    from public.crm_leads l where l.company_id = p_company group by l.stage;
end $$;

revoke all on function public.crm_lead_guard(), public.crm_activity_guard(), public.crm_quote_sync() from public, anon, authenticated;
revoke all on function public.crm_make_customer(uuid), public.crm_link_quote(uuid, uuid), public.crm_summary(uuid) from public, anon;
grant execute on function public.crm_make_customer(uuid), public.crm_link_quote(uuid, uuid), public.crm_summary(uuid) to authenticated;
notify pgrst, 'reload schema';
