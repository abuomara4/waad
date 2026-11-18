-- 0128 — access log (owner's request, 2026-11-18): who opened sensitive data, kept with the company's data and in its export.
-- Reading a table leaves no trace in the database, so the system's screens report what they open (employee files, payroll, payslips,
-- bank files, HR reports, attachments), and the data exports are recorded on the server. Append-only; the owner and admins read it.
create table if not exists public.access_log (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid,
  actor_name text,
  kind text not null check (kind in ('employee','payroll','payslip','bank_file','report','file','export')),
  employee_id uuid,            -- no foreign key: the record outlives a deleted employee
  employee_name text,
  ref text check (ref is null or length(ref) <= 120),
  label text check (label is null or length(label) <= 150),
  at timestamptz not null default now()
);
create index if not exists access_log_company on public.access_log(company_id, at desc);
create index if not exists access_log_recent on public.access_log(user_id, kind, at desc);
drop trigger if exists access_log_immutable on public.access_log;
create trigger access_log_immutable before update or delete on public.access_log for each row execute function public.block_change();
alter table public.access_log enable row level security;
drop policy if exists access_log_read on public.access_log;
create policy access_log_read on public.access_log for select using (public.has_role(company_id, array['owner','admin']));
revoke all on public.access_log from anon, authenticated;
grant select on public.access_log to authenticated;

create or replace function public.access_add(p_company uuid, p_user uuid, p_name text, p_kind text, p_emp uuid, p_ref text, p_label text) returns void
language plpgsql security definer set search_path = public as $$
declare en text;
begin
  -- the same thing opened again within ten minutes is one visit
  if exists(select 1 from public.access_log where user_id = p_user and kind = p_kind and at > now() - interval '10 minutes'
             and company_id = p_company and employee_id is not distinct from p_emp and ref is not distinct from p_ref) then return; end if;
  if p_emp is not null then
    select full_name into en from public.employees where id = p_emp and company_id = p_company;
    if en is null then return; end if;
  end if;
  insert into public.access_log(company_id, user_id, actor_name, kind, employee_id, employee_name, ref, label)
  values (p_company, p_user, left(p_name, 120), p_kind, p_emp, en, left(p_ref, 120), left(p_label, 150));
end $$;
-- what a screen reports; a person opening his own record is not logged
create or replace function public.access_note(p_company uuid, p_kind text, p_emp uuid, p_ref text, p_label text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_member(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p_kind not in ('employee','payroll','payslip','bank_file','report','file') then raise exception 'نوع غير معروف'; end if;
  if p_emp is not null and p_emp = public.my_employee(p_company) then return; end if;
  if (select count(*) from public.access_log where user_id = auth.uid() and at > now() - interval '1 hour') >= 300 then return; end if;
  perform public.access_add(p_company, auth.uid(), public.signer_name(p_company), p_kind, p_emp, p_ref, p_label);
end $$;

CREATE OR REPLACE FUNCTION public.company_export(p_company uuid, p_files boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d jsonb;
begin
  if not public.has_role(p_company, array['owner']) then raise exception 'تصدير البيانات لمالك المنشأة فقط' using errcode = '42501'; end if;
  if (select count(*) from public.audit_log where actor = auth.uid() and action = 'export' and at > now() - interval '1 hour') >= 5 then
    raise exception 'حاولت التصدير كثيراً — انتظر ساعة ثم أعد المحاولة'; end if;
  d := public.company_export_data(p_company, p_files);
  insert into public.audit_log(company_id, actor, action, entity, entity_id, data)
  values (p_company, auth.uid(), 'export', 'company', p_company::text, jsonb_build_object('files', p_files, 'tables', d->'n_tables', 'rows', d->'n_rows'));
  perform public.access_add(p_company, auth.uid(), public.signer_name(p_company), 'export', null, p_company::text, case when p_files then 'مع المرفقات' else 'بدون المرفقات' end);
  return d - 'n_tables' - 'n_rows';
end $function$;

CREATE OR REPLACE FUNCTION public.platform_company_export(p_company uuid, p_reason text, p_files boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare c public.companies; d jsonb;
begin perform public.platform_need('export');
  perform public.platform_guard();
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
  perform public.access_add(p_company, auth.uid(), 'فريق وعد', 'export', null, p_company::text, left(btrim(p_reason), 150));
  return (d - 'n_tables' - 'n_rows') || jsonb_build_object('company_name', c.name, 'company_code', c.code);
end $function$;

revoke all on function public.access_add(uuid, uuid, text, text, uuid, text, text), public.access_note(uuid, text, uuid, text, text) from public, anon, authenticated;
grant execute on function public.access_note(uuid, text, uuid, text, text) to authenticated;
