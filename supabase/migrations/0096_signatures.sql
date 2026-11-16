-- Waad ERP — 0096 electronic signature: HR asks an employee to sign (a contract, a custody handover, a penalty notice,
-- a final settlement, a letter…); the employee signs with a finger on the phone in «توقيعاتي». The drawn signature, the
-- text that was signed and the time are kept and can't be changed afterwards.

create table if not exists public.signature_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  kind text not null check (kind in ('contract','custody','penalty','clearance','letter','policy','other')),
  ref_id uuid,
  title text not null check (length(trim(title)) between 2 and 200),
  body text check (body is null or length(body) <= 4000),
  status text not null default 'pending' check (status in ('pending','signed','cancelled')),
  signature text check (signature is null or (signature like 'data:image/png;base64,%' and length(signature) <= 300000)),
  signed_at timestamptz,
  requested_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index if not exists signature_requests_emp on public.signature_requests(employee_id, status);
create index if not exists signature_requests_ref on public.signature_requests(company_id, kind, ref_id);
alter table public.signature_requests enable row level security;
revoke all on public.signature_requests from anon, authenticated;
grant select on public.signature_requests to authenticated;
drop policy if exists sig_read on public.signature_requests;
create policy sig_read on public.signature_requests for select
  using (public.has_role(company_id, array['owner','admin','hr']) or employee_id = public.my_employee(company_id));

create or replace function public.sign_request_create(p_company uuid, p_emp uuid, p_kind text, p_ref uuid, p_title text, p_body text) returns uuid
language plpgsql security definer set search_path = public as $$
declare rid uuid;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if not exists(select 1 from public.employees where id = p_emp and company_id = p_company) then raise exception 'الموظف غير موجود'; end if;
  if exists(select 1 from public.signature_requests where company_id = p_company and kind = p_kind and ref_id is not distinct from p_ref
            and employee_id = p_emp and status = 'pending') then raise exception 'يوجد طلب توقيع قائم لهذا المستند'; end if;
  insert into public.signature_requests(company_id, employee_id, kind, ref_id, title, body)
  values (p_company, p_emp, p_kind, p_ref, trim(p_title), nullif(trim(p_body), '')) returning id into rid;
  return rid;
end $$;

-- the employee signs his own pending request (once; a signed request can't be changed)
create or replace function public.sign_submit(p_id uuid, p_signature text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.signature_requests;
begin
  select * into r from public.signature_requests where id = p_id for update;
  if not found then raise exception 'طلب التوقيع غير موجود'; end if;
  if r.employee_id is distinct from public.my_employee(r.company_id) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if r.status <> 'pending' then raise exception 'تم التوقيع على هذا الطلب أو أُلغي'; end if;
  if p_signature is null or p_signature not like 'data:image/png;base64,%' or length(p_signature) < 200 then raise exception 'ارسم توقيعك أولا'; end if;
  update public.signature_requests set status = 'signed', signature = p_signature, signed_at = now() where id = p_id;
end $$;

create or replace function public.sign_cancel(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.signature_requests;
begin
  select * into r from public.signature_requests where id = p_id for update;
  if not found then raise exception 'طلب التوقيع غير موجود'; end if;
  perform public.require_role(r.company_id, array['owner','admin','hr']);
  if r.status <> 'pending' then raise exception 'لا يُلغى طلب موقّع'; end if;
  update public.signature_requests set status = 'cancelled' where id = p_id;
end $$;

revoke all on function public.sign_request_create(uuid, uuid, text, uuid, text, text), public.sign_submit(uuid, text), public.sign_cancel(uuid) from public, anon;
grant execute on function public.sign_request_create(uuid, uuid, text, uuid, text, text), public.sign_submit(uuid, text), public.sign_cancel(uuid) to authenticated;
