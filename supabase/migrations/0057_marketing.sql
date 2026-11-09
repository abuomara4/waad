-- Waad ERP — 0057 Marketing: campaigns with a budget and spend, linked to the CRM lead source.
-- Part of the sales module: same permission ('sales') and the same package switch as CRM.

create table if not exists public.marketing_campaigns (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  name text not null check (length(trim(name)) >= 2),
  channel text not null default 'other'
    check (channel in ('social','google','email','sms','event','print','referral','influencer','other')),
  budget numeric(14,2) check (budget is null or budget >= 0),
  spent numeric(14,2) not null default 0 check (spent >= 0),
  start_date date,
  end_date date,
  status text not null default 'planned' check (status in ('planned','active','paused','done','cancelled')),
  goal text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, no),
  check (end_date is null or start_date is null or end_date >= start_date)
);
create index if not exists marketing_campaigns_company on public.marketing_campaigns(company_id, status);

-- a lead can point to the campaign that generated it (its source then reads «campaign»)
alter table public.crm_leads add column if not exists campaign_id uuid references public.marketing_campaigns(id);
create index if not exists crm_leads_campaign on public.crm_leads(campaign_id);

create or replace function public.campaign_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    new.no := public.next_doc_no(new.company_id, 'CMP');
  elsif new.company_id <> old.company_id or new.no <> old.no then
    raise exception 'لا يتغير رقم الحملة أو منشأتها';
  end if;
  new.name := trim(new.name);
  new.goal := nullif(trim(coalesce(new.goal, '')), '');
  new.note := nullif(trim(coalesce(new.note, '')), '');
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists marketing_campaigns_guard on public.marketing_campaigns;
create trigger marketing_campaigns_guard before insert or update on public.marketing_campaigns
  for each row execute function public.campaign_guard();

-- keep a lead's campaign inside the same company, and set its source to «campaign» when linked
create or replace function public.crm_lead_campaign_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.campaign_id is not null then
    if not exists(select 1 from public.marketing_campaigns c where c.id = new.campaign_id and c.company_id = new.company_id) then
      raise exception 'الحملة غير موجودة';
    end if;
    new.source := 'campaign';
  end if;
  return new;
end $$;
drop trigger if exists crm_leads_campaign_guard on public.crm_leads;
create trigger crm_leads_campaign_guard before insert or update on public.crm_leads
  for each row execute function public.crm_lead_campaign_guard();

alter table public.marketing_campaigns enable row level security;
drop policy if exists campaign_all on public.marketing_campaigns;
create policy campaign_all on public.marketing_campaigns for all
  using (public.fin_can(company_id, 'sales')) with check (public.fin_can(company_id, 'sales'));
-- restrictive lock: closed when the sales module is not in the package (same as CRM)
drop policy if exists sales_module on public.marketing_campaigns;
create policy sales_module on public.marketing_campaigns as restrictive for all
  using (public.module_on(company_id, 'sales')) with check (public.module_on(company_id, 'sales'));
revoke all on public.marketing_campaigns from anon;
grant select, insert, update, delete on public.marketing_campaigns to authenticated;
drop trigger if exists audit_marketing_campaigns on public.marketing_campaigns;
create trigger audit_marketing_campaigns after insert or update or delete on public.marketing_campaigns
  for each row execute function public.audit_trigger();

-- results per campaign: leads, won deals, won revenue, spend, cost per lead and return on spend
create or replace function public.marketing_summary(p_company uuid)
returns table(campaign_id uuid, no text, name text, channel text, status text, budget numeric, spent numeric,
              leads int, won int, revenue numeric, cost_per_lead numeric, roi numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_fin(p_company, 'sales');
  return query
  select c.id, c.no, c.name, c.channel, c.status, c.budget, c.spent,
         count(l.id)::int,
         count(l.id) filter (where l.stage = 'won')::int,
         coalesce(sum(l.value) filter (where l.stage = 'won'), 0),
         case when count(l.id) > 0 and c.spent > 0 then round(c.spent / count(l.id), 2) end,
         case when c.spent > 0 then round((coalesce(sum(l.value) filter (where l.stage = 'won'), 0) - c.spent) / c.spent * 100, 1) end
    from public.marketing_campaigns c
    left join public.crm_leads l on l.campaign_id = c.id and l.company_id = c.company_id
   where c.company_id = p_company
   group by c.id
   order by c.created_at desc;
end $$;

revoke all on function public.campaign_guard(), public.crm_lead_campaign_guard() from public, anon, authenticated;
revoke all on function public.marketing_summary(uuid) from public, anon;
grant execute on function public.marketing_summary(uuid) to authenticated;
notify pgrst, 'reload schema';
