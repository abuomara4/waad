-- Waad ERP — 0001 core: tenancy, roles, sequences, audit
-- Target: Supabase (Postgres 15+). auth.uid() comes from Supabase Auth.
create extension if not exists pgcrypto;

-- ---------- companies & membership ----------
create table public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) >= 3),
  vat_no text check (vat_no is null or vat_no ~ '^3[0-9]{13}3$'),
  cr_no text check (cr_no is null or cr_no ~ '^[0-9]{10}$'),
  address text,
  created_at timestamptz not null default now()
);

-- roles: owner (GM), admin, hr, finance (finance manager), accountant, storekeeper, manager, employee
create table public.members (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','admin','hr','finance','accountant','storekeeper','manager','employee')),  -- finance = finance manager
  employee_id uuid,             -- link to the person's employee record (FK added in 0002)
  created_at timestamptz not null default now(),
  primary key (company_id, user_id)
);
create index on public.members(user_id);

-- ---------- helpers (security definer so RLS policies can call them without recursion) ----------
create or replace function public.my_role(p_company uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from public.members where company_id = p_company and user_id = auth.uid()
$$;

create or replace function public.is_member(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.members where company_id = p_company and user_id = auth.uid())
$$;

create or replace function public.has_role(p_company uuid, p_roles text[]) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.members where company_id = p_company and user_id = auth.uid() and role = any(p_roles))
$$;

create or replace function public.my_employee(p_company uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select employee_id from public.members where company_id = p_company and user_id = auth.uid()
$$;

create or replace function public.require_role(p_company uuid, p_roles text[]) returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.has_role(p_company, p_roles) then
    raise exception 'غير مصرح: هذا الإجراء يتطلب أحد الأدوار %', p_roles using errcode = '42501';
  end if;
end $$;

-- ---------- document numbering ----------
create table public.doc_sequences (
  company_id uuid not null references public.companies(id) on delete cascade,
  kind text not null,
  last_no int not null default 0,
  primary key (company_id, kind)
);

create or replace function public.next_doc_no(p_company uuid, p_kind text) returns text
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public.doc_sequences(company_id, kind, last_no) values (p_company, p_kind, 1)
  on conflict (company_id, kind) do update set last_no = doc_sequences.last_no + 1
  returning last_no into n;
  return p_kind || '-' || lpad(n::text, 4, '0');
end $$;

-- ---------- append-only audit log ----------
create table public.audit_log (
  id bigint generated always as identity primary key,
  company_id uuid references public.companies(id) on delete cascade,
  actor uuid,
  action text not null,
  entity text not null,
  entity_id text,
  data jsonb,
  at timestamptz not null default now()
);
create index on public.audit_log(company_id, at desc);

create or replace function public.block_change() returns trigger language plpgsql as $$
begin
  raise exception '% records are append-only and cannot be modified', tg_table_name using errcode = '42501';
end $$;
create trigger audit_log_immutable before update or delete on public.audit_log
  for each row execute function public.block_change();

create or replace function public.audit_trigger() returns trigger
language plpgsql security definer set search_path = public as $$
declare r jsonb; cid uuid; eid text;
begin
  r := to_jsonb(coalesce(new, old));
  cid := nullif(r->>'company_id','')::uuid;
  eid := coalesce(r->>'id', r->>'code', r->>'user_id');
  insert into public.audit_log(company_id, actor, action, entity, entity_id, data)
  values (cid, auth.uid(), lower(tg_op), tg_table_name, eid,
          case when tg_op = 'UPDATE' then jsonb_build_object('old', to_jsonb(old), 'new', to_jsonb(new)) else r end);
  return coalesce(new, old);
end $$;

create trigger audit_companies after insert or update or delete on public.companies for each row execute function public.audit_trigger();
create trigger audit_members after insert or update or delete on public.members for each row execute function public.audit_trigger();

-- ---------- RLS ----------
alter table public.companies enable row level security;
alter table public.members enable row level security;
alter table public.doc_sequences enable row level security;
alter table public.audit_log enable row level security;

create policy companies_read on public.companies for select using (public.is_member(id));
create policy companies_update on public.companies for update using (public.has_role(id, array['owner','admin'])) with check (public.has_role(id, array['owner','admin']));

create policy members_read on public.members for select using (user_id = auth.uid() or public.has_role(company_id, array['owner','admin','hr']));
create policy members_write on public.members for all using (public.has_role(company_id, array['owner','admin'])) with check (public.has_role(company_id, array['owner','admin']));
-- the finance manager may manage accountant/storekeeper memberships only
create policy members_fin_write on public.members for all using (public.has_role(company_id, array['finance']) and role in ('accountant','storekeeper')) with check (public.has_role(company_id, array['finance']) and role in ('accountant','storekeeper'));

create policy audit_read on public.audit_log for select using (public.has_role(company_id, array['owner','admin']));
-- doc_sequences: no policies → only security-definer functions touch it.

-- ---------- bootstrap: a signed-in user creates their company ----------
create or replace function public.create_company(p_name text, p_vat text default null, p_cr text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if auth.uid() is null then raise exception 'سجّل الدخول أولاً' using errcode = '42501'; end if;
  insert into public.companies(name, vat_no, cr_no) values (trim(p_name), nullif(p_vat,''), nullif(p_cr,'')) returning id into cid;
  insert into public.members(company_id, user_id, role) values (cid, auth.uid(), 'owner');
  perform public.seed_company(cid);   -- defined in 0003 (chart of accounts)
  return cid;
end $$;
