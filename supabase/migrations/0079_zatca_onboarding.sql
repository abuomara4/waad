-- Waad ERP — 0079 ZATCA Phase 2, step 3: linking a company to Fatoora (docs/ZATCA_PHASE2.md).
-- The server function «zatca» asks the database (with the caller's own login) whether this person may link the company
-- and what its official data are; ZATCA then issues the certificates, and the function stores them with the service key.

alter table public.zatca_settings drop constraint if exists zatca_settings_env_check;
alter table public.zatca_settings add constraint zatca_settings_env_check check (env in ('sandbox','simulation','production'));
alter table public.zatca_settings add column if not exists last_error text;
alter table public.zatca_secrets add column if not exists csid_token text;

-- who may link: the owner or an admin (with two-step verification when the company requires it). Returns the data ZATCA needs.
create or replace function public.zatca_onboard_info(p_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare c public.companies;
begin
  if not (public.aal_ok() and public.has_role(p_company, array['owner','admin'])) then raise exception 'الربط مع فاتورة لمالك المنشأة أو مديرها' using errcode = '42501'; end if;
  select * into c from public.companies where id = p_company;
  return jsonb_build_object('name', c.name, 'vat', c.vat_no, 'cr', c.cr_no, 'street', c.street, 'building', c.bld_no, 'district', c.district,
    'city', c.city, 'postal', c.postal_code, 'addNo', c.add_no, 'category', coalesce(c.industry, 'other'));
end $$;

-- the server stores the result of a successful linking (service role only): the chain continues where it was
create or replace function public.zatca_onboarded(p_company uuid, p_env text, p_serial text, p_cert text, p_key text, p_token text, p_secret text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.zatca_settings(company_id, enabled, env, egs_serial, csid_cert, onboarded_at, last_error, updated_at)
  values (p_company, true, p_env, p_serial, p_cert, now(), null, now())
  on conflict (company_id) do update set enabled = true, env = excluded.env, egs_serial = excluded.egs_serial, csid_cert = excluded.csid_cert,
    onboarded_at = now(), last_error = null, updated_at = now();
  insert into public.zatca_secrets(company_id, private_key, csid_token, csid_secret, updated_at) values (p_company, p_key, p_token, p_secret, now())
  on conflict (company_id) do update set private_key = excluded.private_key, csid_token = excluded.csid_token, csid_secret = excluded.csid_secret, updated_at = now();
end $$;

-- a failed attempt is kept on the settings row so the screen can say why (the company stays as it was)
create or replace function public.zatca_onboard_failed(p_company uuid, p_error text) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.zatca_settings(company_id, last_error) values (p_company, left(p_error, 1000))
  on conflict (company_id) do update set last_error = left(p_error, 1000), updated_at = now();
end $$;

revoke all on function public.zatca_onboard_info(uuid) from public, anon;
grant execute on function public.zatca_onboard_info(uuid) to authenticated;
revoke all on function public.zatca_onboarded(uuid, text, text, text, text, text, text), public.zatca_onboard_failed(uuid, text) from public, anon, authenticated;
grant execute on function public.zatca_onboarded(uuid, text, text, text, text, text, text), public.zatca_onboard_failed(uuid, text) to service_role;
