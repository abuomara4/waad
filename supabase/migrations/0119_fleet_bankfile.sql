-- 0119 — fleet upkeep and the bank's own salary file (owner's request, 2026-11-18)
-- * Fleet: each vehicle gets an odometer, a service plan (every N km and/or N months, next service date / km) and a log of
--   fuel, maintenance and other costs; services coming due join the company-documents alerts. The driver stays on the vehicle.
-- * Bank salary file: a bank's salary-upload layout differs from bank to bank (e.g. Al Rajhi «تبادل»); the company uploads the
--   bank's own sample file once, maps its columns to Waad fields, and every payroll exports in exactly that layout.

alter table public.vehicles
  add column if not exists odometer int check (odometer is null or odometer >= 0),
  add column if not exists service_every_km int check (service_every_km is null or service_every_km > 0),
  add column if not exists service_every_months int check (service_every_months is null or service_every_months between 1 and 60),
  add column if not exists next_service_date date,
  add column if not exists next_service_km int check (next_service_km is null or next_service_km >= 0);

create table if not exists public.vehicle_logs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  kind text not null check (kind in ('fuel','maintenance','service','repair','other')),
  day date not null default current_date,
  amount numeric(12,2) not null default 0 check (amount >= 0),
  odometer int check (odometer is null or odometer >= 0),
  liters numeric(8,2) check (liters is null or liters >= 0),
  driver_id uuid references public.employees(id) on delete set null,
  note text check (note is null or length(note) <= 300),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists vehicle_logs_v on public.vehicle_logs(vehicle_id, day desc);
alter table public.vehicle_logs enable row level security;
drop policy if exists vehicle_logs_all on public.vehicle_logs;
create policy vehicle_logs_all on public.vehicle_logs for all
  using (public.has_role(company_id, array['owner','admin','hr','finance']) or public.fin_can(company_id, 'hr_cdocs'))
  with check ((public.has_role(company_id, array['owner','admin','hr','finance']) or public.fin_can(company_id, 'hr_cdocs'))
              and exists(select 1 from public.vehicles v where v.id = vehicle_id and v.company_id = vehicle_logs.company_id));
revoke all on public.vehicle_logs from anon;
grant select, insert, update, delete on public.vehicle_logs to authenticated;

-- a log entry moves the odometer forward; a service resets the plan (next date / km)
create or replace function public.vehicle_logs_after() returns trigger language plpgsql security definer set search_path = public as $$
declare v public.vehicles;
begin
  select * into v from public.vehicles where id = new.vehicle_id;
  if new.odometer is not null and new.odometer > coalesce(v.odometer, 0) then update public.vehicles set odometer = new.odometer where id = v.id; end if;
  if new.kind = 'service' then
    update public.vehicles set
      next_service_date = case when v.service_every_months is not null then (new.day + make_interval(months => v.service_every_months))::date else next_service_date end,
      next_service_km = case when v.service_every_km is not null and new.odometer is not null then new.odometer + v.service_every_km else next_service_km end
    where id = v.id;
  end if;
  return null;
end $$;
drop trigger if exists vehicle_logs_after on public.vehicle_logs;
create trigger vehicle_logs_after after insert on public.vehicle_logs for each row execute function public.vehicle_logs_after();

-- the bank file layout: {"bank": "...", "headers": [...], "map": [field per column], "start_row": n, "ext": "xlsx|csv"}
alter table public.companies add column if not exists bank_file jsonb;
create or replace function public.bank_file_set(p_company uuid, p_tpl jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin','hr','finance']);
  if p_tpl is not null and (jsonb_typeof(p_tpl->'headers') <> 'array' or jsonb_typeof(p_tpl->'map') <> 'array'
       or jsonb_array_length(p_tpl->'headers') <> jsonb_array_length(p_tpl->'map') or jsonb_array_length(p_tpl->'headers') > 60) then
    raise exception 'قالب ملف البنك غير صحيح'; end if;
  update public.companies set bank_file = p_tpl where id = p_company;
end $$;

revoke all on function public.vehicle_logs_after() from public, anon;
revoke all on function public.bank_file_set(uuid, jsonb) from public, anon;
grant execute on function public.bank_file_set(uuid, jsonb) to authenticated;
