-- Branches (part 1 of the SAP/Oracle-style organisation: the branch is a plant / profit centre inside the legal entity).
-- Each branch gets its own cost centre (so the books show each branch's results), warehouse and attendance site.
-- Employees, warehouses, sites, cost centres and the main money documents carry the branch; a document without one
-- takes the signed-in user's default branch, and its cost centre follows the branch unless a project / other centre was chosen.
create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null check (code ~ '^[A-Za-z0-9_-]{1,12}$'),
  name text not null check (length(btrim(name)) between 2 and 120),
  name_en text check (name_en is null or length(name_en) <= 120),
  city text check (city is null or length(city) <= 80),
  address text check (address is null or length(address) <= 300),
  cr_sub text check (cr_sub is null or cr_sub ~ '^[0-9]{10}$'),
  phone text check (phone is null or length(phone) <= 20),
  manager_id uuid references public.employees(id) on delete set null,
  cost_center_id uuid references public.cost_centers(id) on delete set null,
  warehouse_id uuid references public.warehouses(id) on delete set null,
  work_site_id uuid references public.work_sites(id) on delete set null,
  is_main boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (company_id, code)
);
create unique index if not exists branches_one_main on public.branches(company_id) where is_main;
create index if not exists branches_co on public.branches(company_id);
create index if not exists branches_mgr on public.branches(manager_id);
create index if not exists branches_cc on public.branches(cost_center_id);
create index if not exists branches_wh on public.branches(warehouse_id);
create index if not exists branches_site on public.branches(work_site_id);
alter table public.branches enable row level security;
revoke all on public.branches from anon;
grant select on public.branches to authenticated;
drop policy if exists branches_read on public.branches;
create policy branches_read on public.branches for select using (public.is_member(company_id));
drop trigger if exists audit_branches on public.branches;
create trigger audit_branches after insert or update or delete on public.branches for each row execute function public.audit_trigger();

-- the branch on records and documents, and each member's default branch
do $$ declare t text;
begin
  foreach t in array array['employees','warehouses','work_sites','cost_centers','sales_invoices','purchase_bills','payments','sales_orders','purchase_orders','members'] loop
    execute format('alter table public.%I add column if not exists branch_id uuid references public.branches(id) on delete set null', t);
    execute format('create index if not exists %I on public.%I(branch_id)', t || '_branch', t);
  end loop;
end $$;

-- the branch must belong to the same company
create or replace function public.branch_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare b public.branches; d uuid;
begin
  if tg_table_name in ('sales_invoices','purchase_bills','payments','sales_orders','purchase_orders') and new.branch_id is null and tg_op = 'INSERT' then
    select m.branch_id into d from public.members m where m.company_id = new.company_id and m.user_id = auth.uid();
    new.branch_id := d;
  end if;
  if new.branch_id is null then return new; end if;
  select * into b from public.branches where id = new.branch_id;
  if not found or b.company_id <> new.company_id then raise exception 'الفرع لا يخص هذه المنشأة'; end if;
  -- documents: the branch's cost centre when none was chosen (a project or another centre stays as chosen)
  if tg_table_name in ('sales_invoices','purchase_bills','purchase_orders') then   -- nested: other tables have no cost_center_id
    if new.cost_center_id is null and b.cost_center_id is not null then new.cost_center_id := b.cost_center_id; end if;
  end if;
  return new;
end $$;
do $$ declare t text;
begin
  foreach t in array array['employees','warehouses','work_sites','cost_centers','sales_invoices','purchase_bills','payments','sales_orders','purchase_orders','members'] loop
    execute format('drop trigger if exists branch_guard on public.%I', t);
    execute format('create trigger branch_guard before insert or update of branch_id on public.%I for each row execute function public.branch_guard()', t);
  end loop;
end $$;

-- create / update a branch: its cost centre, warehouse and attendance site are made with it (owner / admin)
create or replace function public.branch_save(p_company uuid, p jsonb, p_id uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare id_ uuid := p_id; code_ text := upper(btrim(coalesce(p->>'code', ''))); nm text := btrim(coalesce(p->>'name', '')); cc uuid; wh uuid; b public.branches;
begin
  perform public.require_role(p_company, array['owner','admin']);
  if code_ !~ '^[A-Z0-9_-]{1,12}$' then raise exception 'رمز الفرع حروف إنجليزية أو أرقام (حتى 12)'; end if;
  if length(nm) < 2 then raise exception 'اكتب اسم الفرع'; end if;
  if nullif(p->>'manager_id', '') is not null and not exists(select 1 from public.employees where id = (p->>'manager_id')::uuid and company_id = p_company) then raise exception 'مدير الفرع غير موجود'; end if;
  if coalesce((p->>'is_main')::boolean, false) then update public.branches set is_main = false where company_id = p_company and is_main and id is distinct from p_id; end if;
  if id_ is null then
    insert into public.cost_centers(company_id, code, name, name_en) values (p_company, left('BR-' || code_, 12), 'فرع ' || nm, nullif('Branch ' || coalesce(nullif(p->>'name_en', ''), code_), 'Branch '))
      on conflict (company_id, code) do update set active = true returning cost_centers.id into cc;
    insert into public.warehouses(company_id, code, name, name_en) values (p_company, left('BR-' || code_, 12), 'مستودع ' || nm, nullif(p->>'name_en', ''))
      on conflict (company_id, code) do update set active = true returning warehouses.id into wh;
    insert into public.branches(company_id, code, name, name_en, city, address, cr_sub, phone, manager_id, cost_center_id, warehouse_id, is_main)
      values (p_company, code_, nm, nullif(btrim(coalesce(p->>'name_en', '')), ''), nullif(btrim(coalesce(p->>'city', '')), ''), nullif(btrim(coalesce(p->>'address', '')), ''),
              nullif(p->>'cr_sub', ''), nullif(p->>'phone', ''), nullif(p->>'manager_id', '')::uuid, cc, wh, coalesce((p->>'is_main')::boolean, false))
      returning branches.id into id_;
    update public.cost_centers set branch_id = id_ where id = cc;
    update public.warehouses set branch_id = id_ where id = wh;
  else
    select * into b from public.branches where id = id_ and company_id = p_company;
    if not found then raise exception 'الفرع غير موجود'; end if;
    update public.branches set name = nm, name_en = nullif(btrim(coalesce(p->>'name_en', '')), ''), city = nullif(btrim(coalesce(p->>'city', '')), ''),
      address = nullif(btrim(coalesce(p->>'address', '')), ''), cr_sub = nullif(p->>'cr_sub', ''), phone = nullif(p->>'phone', ''),
      manager_id = nullif(p->>'manager_id', '')::uuid, is_main = coalesce((p->>'is_main')::boolean, false), active = coalesce((p->>'active')::boolean, true)
     where id = id_;
  end if;
  return id_;
end $$;

-- a member's default branch (owner / admin, or HR for staff)
create or replace function public.member_branch_set(p_company uuid, p_user uuid, p_branch uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if p_branch is not null and not exists(select 1 from public.branches where id = p_branch and company_id = p_company) then raise exception 'الفرع لا يخص هذه المنشأة'; end if;
  update public.members set branch_id = p_branch where company_id = p_company and user_id = p_user;
  if not found then raise exception 'المستخدم غير موجود'; end if;
end $$;

revoke all on function public.branch_guard() from public, anon, authenticated;
revoke all on function public.branch_save(uuid, jsonb, uuid), public.member_branch_set(uuid, uuid, uuid) from public, anon;
grant execute on function public.branch_save(uuid, jsonb, uuid), public.member_branch_set(uuid, uuid, uuid) to authenticated;
notify pgrst, 'reload schema';
