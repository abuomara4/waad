-- Local test shim that mimics the parts of Supabase the migrations rely on. NOT applied in Supabase.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key, email text unique);
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to public;
-- Supabase grants everything in public to anon/authenticated by default; mimic that so tests catch missing revokes.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb)
$$;
grant execute on function auth.jwt() to public;
alter table auth.users add column if not exists encrypted_password text;

-- two-step verification factors (Supabase keeps them in auth.mfa_factors)
create table if not exists auth.mfa_factors (id uuid primary key default gen_random_uuid(), user_id uuid not null, friendly_name text,
  factor_type text not null default 'totp', status text not null default 'unverified', secret text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
alter table auth.users add column if not exists last_sign_in_at timestamptz;
