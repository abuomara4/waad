-- 0113 — payroll sign-off in three steps (owner's decision, 2026-11-17):
--   1) the HR manager approves the prepared payroll, 2) the finance manager, 3) the general manager (the owner) approves it
--   finally (payroll_approve: posts the accrual entry). The owner may sign any step himself (small companies).
-- * payroll_sign(run): signs the next open step (HR, then finance) and keeps the signer's name for the printed sheet;
--   the same person cannot sign both steps, except the owner.
-- * payroll_return(run, note): finance, the owner or HR send the draft back; both signatures are cleared.
-- * recalculating the payroll or editing a line clears the signatures (they approved other numbers).
-- * the final approval (status draft → approved) needs both signatures and the owner; server jobs (no signed-in user) are exempt.

alter table public.payroll_runs
  add column if not exists hr_ok_by uuid, add column if not exists hr_ok_at timestamptz, add column if not exists hr_ok_name text,
  add column if not exists fin_ok_by uuid, add column if not exists fin_ok_at timestamptz, add column if not exists fin_ok_name text,
  add column if not exists approved_name text, add column if not exists return_note text;

-- the signer's name: the linked employee's name, or the account e-mail
create or replace function public.signer_name(p_company uuid) returns text language sql stable security definer set search_path = public as $$
  select coalesce((select e.full_name from public.members m join public.employees e on e.id = m.employee_id where m.company_id = p_company and m.user_id = auth.uid()),
                  (select u.email from auth.users u where u.id = auth.uid()), '')
$$;

create or replace function public.payroll_sign(p_run uuid) returns text
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs;
begin
  select * into r from public.payroll_runs where id = p_run for update;
  if not found then raise exception 'المسير غير موجود'; end if;
  if r.status <> 'draft' then raise exception 'المسير معتمد مسبقا'; end if;
  if not exists(select 1 from public.payroll_lines where run_id = p_run) then raise exception 'المسير فارغ'; end if;
  if r.hr_ok_at is null then
    perform public.require_role(r.company_id, array['owner','admin','hr']);
    update public.payroll_runs set hr_ok_by = auth.uid(), hr_ok_at = now(), hr_ok_name = public.signer_name(r.company_id), return_note = null where id = p_run;
    return 'hr';
  elsif r.fin_ok_at is null then
    perform public.require_role(r.company_id, array['owner','finance']);
    if r.hr_ok_by = auth.uid() and not public.has_role(r.company_id, array['owner']) then
      raise exception 'لا يعتمد الشخص نفسه مرحلتين من المسير'; end if;
    update public.payroll_runs set fin_ok_by = auth.uid(), fin_ok_at = now(), fin_ok_name = public.signer_name(r.company_id) where id = p_run;
    return 'fin';
  end if;
  raise exception 'المسير بانتظار اعتماد المدير العام';
end $$;

create or replace function public.payroll_return(p_run uuid, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs;
begin
  select * into r from public.payroll_runs where id = p_run for update;
  if not found then raise exception 'المسير غير موجود'; end if;
  perform public.require_role(r.company_id, array['owner','admin','hr','finance']);
  if r.status <> 'draft' then raise exception 'المسير معتمد مسبقا'; end if;
  update public.payroll_runs set hr_ok_by = null, hr_ok_at = null, hr_ok_name = null, fin_ok_by = null, fin_ok_at = null, fin_ok_name = null,
    return_note = nullif(btrim(coalesce(p_note, '')), '') where id = p_run;
end $$;

-- the final approval needs both signatures and the general manager
create or replace function public.payroll_runs_signoff() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.status = 'draft' and new.status = 'approved' and auth.uid() is not null then
    if not public.has_role(new.company_id, array['owner']) then raise exception 'الاعتماد النهائي للمسير للمدير العام' using errcode = '42501'; end if;
    if new.hr_ok_at is null then raise exception 'لم يعتمد مدير الموارد البشرية المسير بعد'; end if;
    if new.fin_ok_at is null then raise exception 'لم تعتمد المالية المسير بعد'; end if;
    new.approved_name := public.signer_name(new.company_id);
  end if;
  return new;
end $$;
drop trigger if exists payroll_runs_signoff on public.payroll_runs;
create trigger payroll_runs_signoff before update of status on public.payroll_runs for each row execute function public.payroll_runs_signoff();

-- a recalculation or an edited line clears the signatures
create or replace function public.payroll_lines_unsign() returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.payroll_runs set hr_ok_by = null, hr_ok_at = null, hr_ok_name = null, fin_ok_by = null, fin_ok_at = null, fin_ok_name = null
   where id = coalesce(new.run_id, old.run_id) and status = 'draft' and (hr_ok_at is not null or fin_ok_at is not null);
  return null;
end $$;
drop trigger if exists payroll_lines_unsign on public.payroll_lines;
create trigger payroll_lines_unsign after insert or update or delete on public.payroll_lines for each row execute function public.payroll_lines_unsign();

revoke all on function public.signer_name(uuid) from public, anon;
revoke all on function public.payroll_sign(uuid) from public, anon;
revoke all on function public.payroll_return(uuid, text) from public, anon;
grant execute on function public.payroll_sign(uuid) to authenticated;
grant execute on function public.payroll_return(uuid, text) to authenticated;
revoke all on function public.payroll_runs_signoff() from public, anon;
revoke all on function public.payroll_lines_unsign() from public, anon;
