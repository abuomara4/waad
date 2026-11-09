-- Waad ERP — 0046 anonymous-access hardening.
-- 1) Supabase's default privileges hand every new table/function/sequence to `anon`. Earlier migrations revoked
--    table by table; three travel tables (0037/0038) were missed. Revoke everything from anon and stop the default.
-- 2) company_by_code is the only call a signed-out visitor needs. Throttle failed guesses so company names can't
--    be enumerated by trying codes.

revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
-- functions: drop anon (and the PUBLIC grant anon inherits) but keep whatever authenticated already had
do $$
declare f record; keep boolean;
begin
  for f in select p.oid, p.oid::regprocedure::text sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind = 'f' and has_function_privilege('anon', p.oid, 'execute') loop
    keep := has_function_privilege('authenticated', f.oid, 'execute');
    execute format('revoke execute on function %s from public, anon', f.sig);
    if keep then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
end $$;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke execute on functions from anon, public;
alter default privileges in schema public grant execute on functions to authenticated;

create table if not exists public.code_lookups (
  ip text not null,
  at timestamptz not null default now(),
  ok boolean not null
);
create index if not exists code_lookups_ip_at on public.code_lookups (ip, at);
alter table public.code_lookups enable row level security;
revoke all on public.code_lookups from anon, authenticated;

drop function if exists public.company_by_code(text);
create function public.company_by_code(p_code text) returns text
language plpgsql volatile security definer set search_path = public as $$
declare
  hdr text := nullif(current_setting('request.headers', true), '');
  v_ip text;
  nm text;
begin
  begin v_ip := nullif(trim(coalesce(hdr::json ->> 'cf-connecting-ip', hdr::json ->> 'x-real-ip', split_part(hdr::json ->> 'x-forwarded-for', ',', 1))), ''); exception when others then v_ip := null; end;
  v_ip := coalesce(v_ip, 'unknown');
  if (select count(*) from public.code_lookups where ip = v_ip and not ok and at > now() - interval '15 minutes') >= 10
     or (select count(*) from public.code_lookups where not ok and at > now() - interval '1 minute') >= 200 then
    raise exception 'محاولات كثيرة لرمز منشأة غير صحيح — حاول بعد ربع ساعة' using errcode = 'P0001';
  end if;
  select name into nm from public.companies where code = upper(trim(coalesce(p_code, '')));
  delete from public.code_lookups where at < now() - interval '1 day';
  insert into public.code_lookups (ip, ok) values (v_ip, nm is not null);
  return nm;
end $$;
revoke all on function public.company_by_code(text) from public;
grant execute on function public.company_by_code(text) to anon, authenticated;
