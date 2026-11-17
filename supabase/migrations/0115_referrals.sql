-- 0115 — «ادعُ منشأة» (owner's decision, 2026-11-17): a customer shares its link; when the company it invited makes its
-- first subscription payment, the inviting company gets a free month (30 days).
-- * companies.ref_code: the company's own invitation code (derived from its id, never changes);
-- * companies.referred_by: set once by the new company's owner within 2 days of creating it (referral_claim), never itself;
-- * the reward (trigger on the first platform payment of the invited company): an active subscription or a trial gets
--   30 more days at once; otherwise the 30 days wait in ref_credit_days for the Waad team to apply;
-- * the three referral columns change only inside these functions (guard trigger).

alter table public.companies
  add column if not exists ref_code text generated always as (upper(substr(md5(id::text), 1, 7))) stored,
  add column if not exists referred_by uuid references public.companies(id) on delete set null,
  add column if not exists ref_rewarded_at timestamptz,
  add column if not exists ref_credit_days int not null default 0 check (ref_credit_days >= 0);
create unique index if not exists companies_ref_code on public.companies(ref_code);
create index if not exists companies_referred_by on public.companies(referred_by);

create or replace function public.companies_ref_guard() returns trigger language plpgsql as $$
begin
  if auth.uid() is not null and coalesce(current_setting('waad.ref', true), '') <> '1' then
    if tg_op = 'INSERT' then new.referred_by := null; new.ref_rewarded_at := null; new.ref_credit_days := 0;
    elsif (new.referred_by is distinct from old.referred_by and new.referred_by is not null) or new.ref_rewarded_at is distinct from old.ref_rewarded_at
       or new.ref_credit_days is distinct from old.ref_credit_days then
      raise exception 'غير مصرح' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists companies_ref_guard on public.companies;
create trigger companies_ref_guard before insert or update on public.companies for each row execute function public.companies_ref_guard();

-- the new company's owner records who invited it
create or replace function public.referral_claim(p_company uuid, p_code text) returns boolean
language plpgsql security definer set search_path = public as $$
declare c public.companies; r uuid;
begin
  perform public.require_role(p_company, array['owner']);
  select * into c from public.companies where id = p_company;
  if c.referred_by is not null or c.created_at < now() - interval '2 days' then return false; end if;
  select id into r from public.companies where ref_code = upper(btrim(coalesce(p_code, '')));
  if r is null or r = p_company then return false; end if;
  perform set_config('waad.ref', '1', true);
  update public.companies set referred_by = r where id = p_company;
  return true;
end $$;

-- the inviting company's numbers (owner / admin): its code, how many joined, how many subscribed, days earned
create or replace function public.my_referrals(p_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin']);
  return (select jsonb_build_object('code', (select ref_code from public.companies where id = p_company),
    'joined', count(*), 'paid', count(*) filter (where x.ref_rewarded_at is not null),
    'days', 30 * count(*) filter (where x.ref_rewarded_at is not null),
    'waiting', (select ref_credit_days from public.companies where id = p_company))
    from public.companies x where x.referred_by = p_company);
end $$;

-- the reward, on the invited company's first payment
create or replace function public.platform_payments_referral() returns trigger language plpgsql security definer set search_path = public as $$
declare c public.companies; s public.company_subscriptions;
begin
  select * into c from public.companies where id = new.company_id;
  if c.id is null or c.referred_by is null or c.ref_rewarded_at is not null then return null; end if;
  perform set_config('waad.ref', '1', true);
  update public.companies set ref_rewarded_at = now() where id = c.id;
  select * into s from public.company_subscriptions where company_id = c.referred_by;
  if s.status = 'active' and s.sub_ends is not null then
    update public.company_subscriptions set sub_ends = greatest(s.sub_ends, current_date) + 30, updated_at = now() where company_id = c.referred_by;
  elsif s.status = 'trial' then
    update public.company_subscriptions set trial_ends = greatest(coalesce(s.trial_ends, current_date), current_date) + 30, updated_at = now() where company_id = c.referred_by;
  elsif s.status = 'active' then
    null;   -- an open-ended subscription: nothing to extend
  else
    update public.companies set ref_credit_days = ref_credit_days + 30 where id = c.referred_by;
  end if;
  return null;
end $$;
drop trigger if exists platform_payments_referral on public.platform_payments;
create trigger platform_payments_referral after insert on public.platform_payments for each row execute function public.platform_payments_referral();

-- the Waad team: every invitation
create or replace function public.platform_referrals() returns table(referrer uuid, referrer_name text, invited uuid, invited_name text, joined_on date, rewarded_at timestamptz, waiting_days int)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.platform_guard();
  return query select r.id, r.name, c.id, c.name, c.created_at::date, c.ref_rewarded_at, r.ref_credit_days
    from public.companies c join public.companies r on r.id = c.referred_by order by c.created_at desc;
end $$;
-- the team applied the waiting days by hand (billing permission)
create or replace function public.platform_referral_credit_clear(p_company uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.platform_need('billing');
  perform set_config('waad.ref', '1', true);
  update public.companies set ref_credit_days = 0 where id = p_company;
end $$;

revoke all on function public.companies_ref_guard() from public, anon;
revoke all on function public.platform_payments_referral() from public, anon;
revoke all on function public.referral_claim(uuid, text) from public, anon;
revoke all on function public.my_referrals(uuid) from public, anon;
revoke all on function public.platform_referrals() from public, anon;
revoke all on function public.platform_referral_credit_clear(uuid) from public, anon;
grant execute on function public.referral_claim(uuid, text), public.my_referrals(uuid), public.platform_referrals(), public.platform_referral_credit_clear(uuid) to authenticated;
