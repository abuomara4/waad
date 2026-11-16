-- Waad ERP — 0091 fixed assets: who holds it, where it is charged and kept, and its serial number (QA report).
-- The code was already there (set or numbered FA-…); these are the missing details. Set with asset_details after saving.

alter table public.fixed_assets add column if not exists custodian_id uuid references public.employees(id) on delete set null;
alter table public.fixed_assets add column if not exists cost_center_id uuid references public.cost_centers(id) on delete set null;
alter table public.fixed_assets add column if not exists serial_no text check (serial_no is null or length(serial_no) <= 60);
alter table public.fixed_assets add column if not exists location text check (location is null or length(location) <= 120);

create or replace function public.asset_details(p_id uuid, p_custodian uuid, p_cost_center uuid, p_serial text, p_location text) returns void
language plpgsql security definer set search_path = public as $$
declare a public.fixed_assets;
begin
  select * into a from public.fixed_assets where id = p_id;
  if not found then raise exception 'الأصل غير موجود'; end if;
  perform public.require_fin(a.company_id, 'je');
  if p_custodian is not null and not exists(select 1 from public.employees where id = p_custodian and company_id = a.company_id) then raise exception 'الموظف غير موجود'; end if;
  if p_cost_center is not null and not exists(select 1 from public.cost_centers where id = p_cost_center and company_id = a.company_id) then raise exception 'مركز التكلفة غير موجود'; end if;
  update public.fixed_assets set custodian_id = p_custodian, cost_center_id = p_cost_center,
    serial_no = nullif(trim(p_serial), ''), location = nullif(trim(p_location), '') where id = p_id;
end $$;
revoke all on function public.asset_details(uuid, uuid, uuid, text, text) from public, anon;
grant execute on function public.asset_details(uuid, uuid, uuid, text, text) to authenticated;
