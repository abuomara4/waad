-- 0102 — the Waad platform owner exports a company's full data at its owner's request (owner's decision, 2026-11-17):
-- * only platform admins with can_export: the owner's own accounts (abdulaziz, abdulaziz1); other team members cannot;
-- * a reason / how the owner asked is required; every export is kept in company_exports_log (never edited or deleted,
--   survives the company's deletion) and the company owner is e-mailed at once by the notify job («تم تصدير بيانات منشأتك…»);
-- * the data is the same as the owner's own export (company_export), now built by one internal function;
--   ZATCA private keys and customer-portal tokens are never exported (they are credentials, not business data).

alter table public.platform_admins add column if not exists can_export boolean not null default false;
update public.platform_admins set can_export = true where username in ('abdulaziz', 'abdulaziz1');   -- the owner's own accounts

create table if not exists public.company_exports_log (
  id uuid primary key default gen_random_uuid(),
  company_ref uuid not null,           -- not «company_id» and no foreign key: the record stays after the company is deleted (purge skips it)
  company_name text not null,
  by_user uuid,
  by_email text,
  at timestamptz not null default now(),
  reason text not null,
  with_files boolean not null default false,
  notified_at timestamptz
);
alter table public.company_exports_log enable row level security;   -- no policies: read through platform_exports_log()
revoke all on public.company_exports_log from anon, authenticated;
revoke all on public.company_deletions from anon, authenticated;
create or replace function public.exports_log_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'سجل التصدير لا يُحذف' using errcode = '42501'; end if;
  if (new.id, new.company_ref, new.company_name, new.by_user, new.by_email, new.at, new.reason, new.with_files)
     is distinct from (old.id, old.company_ref, old.company_name, old.by_user, old.by_email, old.at, old.reason, old.with_files) then
    raise exception 'سجل التصدير لا يتغيّر' using errcode = '42501'; end if;
  return new;
end $$;
drop trigger if exists exports_log_guard on public.company_exports_log;
create trigger exports_log_guard before update or delete on public.company_exports_log for each row execute function public.exports_log_guard();

-- the data itself (no permission check: called only by the two functions below)
create or replace function public.company_export_data(p_company uuid, p_files boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  f jsonb := jsonb_build_object('companies', format('id = %L', p_company));   -- table → where clause
  skip text[] := array['client_errors', 'doc_sequences', 'platform_admins', 'platform_settings', 'zatca_secrets', 'portal_links', 'company_exports_log', 'company_deletions'];
  t record; fk record; pass int; added boolean; res jsonb := '{}'; rows jsonb; strip text[]; n int := 0; tot int := 0;
begin
  for t in select c.relname from pg_class c join pg_attribute a on a.attrelid = c.oid
            where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and a.attname = 'company_id' and not a.attisdropped
              and c.relname <> all(skip) loop
    f := f || jsonb_build_object(t.relname, format('company_id = %L', p_company));
  end loop;
  for pass in 1..4 loop
    added := false;
    for fk in select distinct on (c.relname) c.relname child, a.attname col, p.relname parent, pa.attname pcol
                from pg_constraint k join pg_class c on c.oid = k.conrelid join pg_class p on p.oid = k.confrelid
                join pg_attribute a on a.attrelid = c.oid and a.attnum = k.conkey[1]
                join pg_attribute pa on pa.attrelid = p.oid and pa.attnum = k.confkey[1]
               where k.contype = 'f' and cardinality(k.conkey) = 1 and c.relnamespace = 'public'::regnamespace and p.relnamespace = 'public'::regnamespace
                 and f ? p.relname and not f ? c.relname and c.relname <> all(skip)
               order by c.relname, k.conname loop
      f := f || jsonb_build_object(fk.child, format('%I in (select %I from public.%I where %s)', fk.col, fk.pcol, fk.parent, f->>fk.parent));
      added := true;
    end loop;
    exit when not added;
  end loop;
  for t in select key tbl, value #>> '{}' cond from jsonb_each(f) order by key loop
    strip := case when p_files then '{}'::text[] else array(
      select a.attname::text from pg_attribute a where a.attrelid = ('public.' || quote_ident(t.tbl))::regclass and a.attnum > 0 and not a.attisdropped
         and ((a.attname = 'data' and a.atttypid = 'text'::regtype) or (t.tbl = 'companies' and a.attname = 'logo'))) end;
    execute format('select coalesce(jsonb_agg(to_jsonb(x) - %L::text[]), ''[]'') from public.%I x where %s', strip, t.tbl, t.cond) into rows;
    n := n + 1; tot := tot + jsonb_array_length(rows);
    res := res || jsonb_build_object(t.tbl, rows);
  end loop;
  return jsonb_build_object('company_id', p_company, 'exported_at', now(), 'with_files', p_files, 'tables', res, 'n_tables', n, 'n_rows', tot);
end $$;

-- the owner's own export (unchanged behaviour)
create or replace function public.company_export(p_company uuid, p_files boolean default false) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d jsonb;
begin
  if not public.has_role(p_company, array['owner']) then raise exception 'تصدير البيانات لمالك المنشأة فقط' using errcode = '42501'; end if;
  if (select count(*) from public.audit_log where actor = auth.uid() and action = 'export' and at > now() - interval '1 hour') >= 5 then
    raise exception 'حاولت التصدير كثيراً — انتظر ساعة ثم أعد المحاولة'; end if;
  d := public.company_export_data(p_company, p_files);
  insert into public.audit_log(company_id, actor, action, entity, entity_id, data)
  values (p_company, auth.uid(), 'export', 'company', p_company::text, jsonb_build_object('files', p_files, 'tables', d->'n_tables', 'rows', d->'n_rows'));
  return d - 'n_tables' - 'n_rows';
end $$;

-- the platform owner's export at the company owner's request
create or replace function public.platform_company_export(p_company uuid, p_reason text, p_files boolean default false) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare c public.companies; d jsonb;
begin
  perform public.platform_guard();
  if not coalesce((select can_export from public.platform_admins where user_id = auth.uid()), false) then
    raise exception 'تصدير بيانات المنشآت لمالك منصة وعد فقط' using errcode = '42501'; end if;
  select * into c from public.companies where id = p_company;
  if c.id is null then raise exception 'المنشأة غير موجودة'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 5 then raise exception 'اكتب كيف طلب المالك التصدير ومتى'; end if;
  if (select count(*) from public.company_exports_log where by_user = auth.uid() and at > now() - interval '1 hour') >= 5 then
    raise exception 'حاولت التصدير كثيراً — انتظر ساعة ثم أعد المحاولة'; end if;
  insert into public.company_exports_log(company_ref, company_name, by_user, by_email, reason, with_files)
  values (c.id, c.name, auth.uid(), (select email from auth.users where id = auth.uid()), btrim(p_reason), coalesce(p_files, false));
  d := public.company_export_data(p_company, coalesce(p_files, false));
  insert into public.audit_log(company_id, actor, action, entity, entity_id, data)
  values (p_company, auth.uid(), 'export', 'company', p_company::text, jsonb_build_object('files', p_files, 'by', 'waad', 'reason', btrim(p_reason), 'tables', d->'n_tables', 'rows', d->'n_rows'));
  return (d - 'n_tables' - 'n_rows') || jsonb_build_object('company_name', c.name, 'company_code', c.code);
end $$;

create or replace function public.platform_exports_log() returns setof public.company_exports_log
language plpgsql stable security definer set search_path = public as $$
begin perform public.platform_guard(); return query select * from public.company_exports_log order by at desc limit 200; end $$;

create or replace function public.platform_can_export() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_platform_admin() and coalesce((select can_export from public.platform_admins where user_id = auth.uid()), false)
$$;

revoke all on function public.company_export_data(uuid, boolean), public.exports_log_guard() from public, anon, authenticated;
revoke all on function public.platform_company_export(uuid, text, boolean), public.platform_exports_log(), public.platform_can_export() from public, anon;
grant execute on function public.platform_company_export(uuid, text, boolean), public.platform_exports_log(), public.platform_can_export() to authenticated;
revoke all on function public.company_export(uuid, boolean) from public, anon;
grant execute on function public.company_export(uuid, boolean) to authenticated;
