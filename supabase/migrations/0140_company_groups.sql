-- Company groups, phase 1 (docs/MULTI_ENTITY_DESIGN.md, owner's go-ahead 2026-11-24). A group gathers several Waad companies
-- (separate legal entities: own VAT number, books, GOSI, ZATCA) under one owner, who moves between them from one account.
-- The rule «one account = one company» (0044) becomes «one account = one group»: the owner of a group may create further
-- companies inside it. Every company keeps its own subscription and, like any new company, starts as the platform requires
-- (pending / trial). The platform admin sees the group's name next to its companies, still no company data.

create table if not exists public.company_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) between 2 and 120),
  owner uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create unique index if not exists company_groups_owner on public.company_groups(owner);
alter table public.companies add column if not exists group_id uuid references public.company_groups(id) on delete set null;
create index if not exists companies_group on public.companies(group_id) where group_id is not null;

alter table public.company_groups enable row level security;
drop policy if exists company_groups_read on public.company_groups;
create policy company_groups_read on public.company_groups for select
  using (owner = auth.uid() or exists(select 1 from public.companies c where c.group_id = company_groups.id and public.has_role(c.id, array['owner','admin'])));
revoke all on public.company_groups from anon, authenticated;
grant select on public.company_groups to authenticated;

-- the group of a company changes only inside the functions below (a company owner cannot attach it to someone else's group)
create or replace function public.companies_group_guard() returns trigger language plpgsql as $$
begin
  if auth.uid() is not null and coalesce(current_setting('waad.group', true), '') <> '1' then
    if tg_op = 'INSERT' then new.group_id := null;
    elsif new.group_id is distinct from old.group_id then raise exception 'غير مصرح' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists companies_group_guard on public.companies;
create trigger companies_group_guard before insert or update on public.companies for each row execute function public.companies_group_guard();

-- the owner of a company starts a group with it (one group per account)
create or replace function public.group_create(p_company uuid, p_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare g uuid; nm text := btrim(coalesce(p_name, ''));
begin
  perform public.require_role(p_company, array['owner']);
  if length(nm) < 2 then raise exception 'اكتب اسم المجموعة'; end if;
  if exists(select 1 from public.company_groups where owner = auth.uid()) then raise exception 'لديك مجموعة منشآت بالفعل'; end if;
  if (select group_id from public.companies where id = p_company) is not null then raise exception 'المنشأة في مجموعة بالفعل'; end if;
  insert into public.company_groups(name, owner) values (nm, auth.uid()) returning id into g;
  perform set_config('waad.group', '1', true);
  update public.companies set group_id = g where id = p_company;
  perform set_config('waad.group', '', true);
  return g;
end $$;

create or replace function public.group_rename(p_group uuid, p_name text) returns void
language plpgsql security definer set search_path = public as $$
declare nm text := btrim(coalesce(p_name, ''));
begin
  if length(nm) < 2 then raise exception 'اكتب اسم المجموعة'; end if;
  update public.company_groups set name = nm where id = p_group and owner = auth.uid();
  if not found then raise exception 'غير مصرح' using errcode = '42501'; end if;
end $$;

-- a new company inside the group: the caller owns the group; same start as create_company (chart of accounts, departments,
-- subscription row through the companies triggers) plus the consent to storage outside the Kingdom (0075). At most 20.
create or replace function public.group_company_create(p_group uuid, p_name text, p_vat text default null, p_cr text default null, p_consent boolean default false) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid; nm text := btrim(coalesce(p_name, ''));
begin
  if auth.uid() is null or not exists(select 1 from public.company_groups where id = p_group and owner = auth.uid()) then
    raise exception 'إضافة منشأة للمجموعة لمالك المجموعة فقط' using errcode = '42501'; end if;
  if not coalesce(p_consent, false) then raise exception 'يلزم الموافقة على تخزين البيانات خارج المملكة'; end if;
  if length(nm) < 2 then raise exception 'اكتب اسم المنشأة'; end if;
  if (select count(*) from public.companies where group_id = p_group) >= 20 then raise exception 'الحد الأعلى 20 منشأة في المجموعة'; end if;
  if exists(select 1 from public.companies c where c.group_id = p_group and lower(btrim(c.name)) = lower(nm)) then raise exception 'في المجموعة منشأة بهذا الاسم'; end if;
  insert into public.companies(name, vat_no, cr_no, xfer_consent_at) values (nm, nullif(btrim(coalesce(p_vat, '')), ''), nullif(btrim(coalesce(p_cr, '')), ''), now()) returning id into cid;
  perform set_config('waad.group', '1', true);
  update public.companies set group_id = p_group where id = cid;
  perform set_config('waad.group', '', true);
  insert into public.members(company_id, user_id, role) values (cid, auth.uid(), 'owner');
  perform public.seed_company(cid);
  return cid;
end $$;

-- take a company out of the group (it stays as it is, with its own subscription); the group's owner, who must own it
create or replace function public.group_company_remove(p_company uuid) returns void
language plpgsql security definer set search_path = public as $$
declare g uuid;
begin
  select c.group_id into g from public.companies c join public.company_groups x on x.id = c.group_id where c.id = p_company and x.owner = auth.uid();
  if g is null or not public.has_role(p_company, array['owner']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  perform set_config('waad.group', '1', true);
  update public.companies set group_id = null where id = p_company;
  perform set_config('waad.group', '', true);
end $$;

-- the owner's view of the group: every company in it with its subscription state (null when the caller owns no group)
create or replace function public.my_group() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', g.id, 'name', g.name, 'created_at', g.created_at, 'companies', coalesce((
    select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'vat_no', c.vat_no, 'cr_no', c.cr_no, 'created_at', c.created_at,
             'status', s.status, 'plan', s.plan, 'trial_ends', s.trial_ends, 'sub_ends', s.sub_ends,
             'member', exists(select 1 from public.members m where m.company_id = c.id and m.user_id = auth.uid())) order by c.created_at)
      from public.companies c left join public.company_subscriptions s on s.company_id = c.id where c.group_id = g.id), '[]'))
  from public.company_groups g where g.owner = auth.uid()
$$;

-- the switcher shows the group of each company
drop function if exists public.my_companies();
create function public.my_companies()
returns table(company_id uuid, name text, role text, employee_id uuid, code text, must_change_password boolean, roles text[], perms text[], group_id uuid, group_name text)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, m.role, m.employee_id, c.code, m.must_change_password, array[m.role] || m.extra_roles,
         array(select x.perm from public.member_perms x where x.company_id = m.company_id and x.user_id = m.user_id order by 1),
         c.group_id, (select g.name from public.company_groups g where g.id = c.group_id)
  from public.members m join public.companies c on c.id = m.company_id
  where m.user_id = auth.uid() and public.member_live(m.employee_id, m.role) order by m.created_at
$$;

-- the admin site: the same list with the group's name at the end
drop function if exists public.platform_companies();
create function public.platform_companies()
returns table(company_id uuid, name text, created_at timestamptz, owner_email text, plan text, modules text[], status text,
              trial_ends date, sub_ends date, max_users int, note text, users int, last_sign_in timestamptz,
              owner_phone text, city text, size_band text, industry text, heard_from text, usage jsonb, max_employees int, group_name text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query
  select c.id, c.name, c.created_at,
         (select u.email::text from public.members m join auth.users u on u.id = m.user_id where m.company_id = c.id and m.role = 'owner' limit 1),
         s.plan, s.modules, s.status, s.trial_ends, s.sub_ends, s.max_users, s.note,
         (select count(*)::int from public.members m where m.company_id = c.id),
         (select max(u.last_sign_in_at) from public.members m join auth.users u on u.id = m.user_id where m.company_id = c.id),
         c.owner_phone, c.city, c.size_band, c.industry, c.heard_from, public.company_usage(c.id), s.max_employees,
         (select g.name from public.company_groups g where g.id = c.group_id)
    from public.companies c left join public.company_subscriptions s on s.company_id = c.id
   order by (s.status = 'pending') desc, c.created_at desc;
end $$;

revoke all on function public.companies_group_guard() from public, anon, authenticated;
revoke all on function public.group_create(uuid, text), public.group_rename(uuid, text), public.group_company_create(uuid, text, text, text, boolean),
  public.group_company_remove(uuid), public.my_group(), public.my_companies(), public.platform_companies() from public, anon;
grant execute on function public.group_create(uuid, text), public.group_rename(uuid, text), public.group_company_create(uuid, text, text, text, boolean),
  public.group_company_remove(uuid), public.my_group(), public.my_companies(), public.platform_companies() to authenticated;
notify pgrst, 'reload schema';
