-- HR attaches the booked ticket and the issued exit/re-entry visa; once attached they are delivered to the employee
-- who asked for them (the records exist only after the request's final approval). Finance records the payment
-- separately; a cash allowance is delivered by that payment.

alter table public.travel_tickets add column delivered_at timestamptz;
alter table public.exit_visas add column delivered_at timestamptz;
update public.travel_tickets set delivered_at = coalesce(issued_on::timestamptz, now()) where status = 'issued';
update public.exit_visas set delivered_at = coalesce(issued_on::timestamptz, now()) where status in ('issued','returned','not_returned');

create table public.travel_files (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  ticket_id uuid references public.travel_tickets(id) on delete cascade,
  visa_id uuid references public.exit_visas(id) on delete cascade,
  file_name text not null check (length(file_name) between 1 and 200),
  mime text not null check (mime in ('application/pdf','image/jpeg','image/png','image/webp')),
  size int not null check (size between 1 and 3145728),
  data text not null,
  uploaded_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check ((ticket_id is null) <> (visa_id is null))
);
create index on public.travel_files(ticket_id);
create index on public.travel_files(visa_id);
alter table public.travel_files enable row level security;
create policy tf_read on public.travel_files for select using (public.has_role(company_id, array['owner','admin','hr','finance']) or employee_id = public.my_employee(company_id));
grant select on public.travel_files to authenticated;

-- stores [{name, mime, data(base64)}] after checking the real file type
create or replace function public.travel_store_files(p_company uuid, p_emp uuid, p_ticket uuid, p_visa uuid, p_files jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare f jsonb; b bytea; m text; n int := 0;
begin
  if p_files is null or jsonb_typeof(p_files) <> 'array' or jsonb_array_length(p_files) = 0 then return 0; end if;
  if (select count(*) from public.travel_files where ticket_id is not distinct from p_ticket and visa_id is not distinct from p_visa) + jsonb_array_length(p_files) > 5 then
    raise exception 'الحد الأقصى 5 مرفقات'; end if;
  for f in select * from jsonb_array_elements(p_files) loop
    m := f->>'mime';
    begin b := decode(coalesce(f->>'data', ''), 'base64'); exception when others then raise exception 'تعذّر قراءة المرفق «%»', coalesce(f->>'name', ''); end;
    if b is null or octet_length(b) = 0 then raise exception 'المرفق «%» فارغ', coalesce(f->>'name', ''); end if;
    if octet_length(b) > 3145728 then raise exception 'حجم المرفق «%» أكبر من 3 ميجابايت', coalesce(f->>'name', ''); end if;
    if not ((m = 'application/pdf' and substr(b, 1, 4) = '\x25504446'::bytea) or (m = 'image/jpeg' and substr(b, 1, 3) = '\xffd8ff'::bytea)
         or (m = 'image/png' and substr(b, 1, 4) = '\x89504e47'::bytea) or (m = 'image/webp' and substr(b, 1, 4) = '\x52494646'::bytea)) then
      raise exception 'المرفق «%» ليس صورة أو PDF', coalesce(f->>'name', ''); end if;
    insert into public.travel_files(company_id, employee_id, ticket_id, visa_id, file_name, mime, size, data)
    values (p_company, p_emp, p_ticket, p_visa, left(coalesce(nullif(trim(f->>'name'), ''), 'مرفق'), 200), m, octet_length(b), encode(b, 'base64'));
    n := n + 1;
  end loop;
  return n;
end $$;

-- HR attaches the booked ticket: it reaches the employee
create or replace function public.ticket_attach(p_id uuid, p_ref text, p_files jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare t public.travel_tickets; n int;
begin
  select * into t from public.travel_tickets where id = p_id for update;
  if not found then raise exception 'السجل غير موجود'; end if;
  perform public.require_role(t.company_id, array['owner','admin','hr']);
  if t.status = 'cancelled' then raise exception 'التذكرة ملغاة'; end if;
  if t.mode <> 'ticket' then raise exception 'البدل النقدي يُسلَّم بتسجيل صرفه من المالية'; end if;
  n := public.travel_store_files(t.company_id, t.employee_id, t.id, null, p_files);
  if n = 0 and not exists(select 1 from public.travel_files where ticket_id = p_id) then raise exception 'أرفق التذكرة (صورة أو PDF)'; end if;
  update public.travel_tickets set status = 'issued', ref = coalesce(nullif(trim(p_ref), ''), ref), issued_on = coalesce(issued_on, current_date),
    delivered_at = coalesce(delivered_at, now()) where id = p_id;
end $$;

-- finance records the payment (journal); a cash allowance is delivered by it
drop function if exists public.ticket_issue(uuid, numeric, text, date, text);
create or replace function public.ticket_pay(p_id uuid, p_amount numeric, p_ref text, p_on date, p_account text default '1120')
returns void language plpgsql security definer set search_path = public as $$
declare t public.travel_tickets; nm text; jid uuid;
begin
  select * into t from public.travel_tickets where id = p_id for update;
  if not found then raise exception 'السجل غير موجود'; end if;
  perform public.require_role(t.company_id, array['owner','admin','finance']);
  if t.status = 'cancelled' then raise exception 'التذكرة ملغاة'; end if;
  if t.entry_id is not null then raise exception 'سُجّل صرف هذه التذكرة من قبل'; end if;
  if coalesce(p_amount, 0) <= 0 then raise exception 'أدخل المبلغ'; end if;
  if p_account not in ('1110','1120') then raise exception 'اختر البنك أو الصندوق'; end if;
  insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header)
  values (t.company_id, '5220', 'تذاكر سفر الموظفين', 'Employee travel tickets', 'exp', '5000', false) on conflict do nothing;
  select full_name into nm from public.employees where id = t.employee_id;
  jid := public.post_journal(t.company_id, coalesce(p_on, current_date),
    case t.mode when 'cash' then 'بدل تذكرة سفر — ' else 'تذكرة سفر — ' end || nm, 'expense', t.id,
    jsonb_build_array(jsonb_build_object('a','5220','d',p_amount), jsonb_build_object('a',p_account,'c',p_amount)));
  update public.travel_tickets set amount = p_amount, entry_id = jid,
    ref = case when t.mode = 'cash' then coalesce(nullif(trim(p_ref), ''), ref) else ref end,
    status = case when t.mode = 'cash' then 'issued' else status end,
    issued_on = case when t.mode = 'cash' then coalesce(p_on, current_date) else issued_on end,
    delivered_at = case when t.mode = 'cash' then now() else delivered_at end
   where id = p_id;
end $$;

create or replace function public.ticket_cancel(p_id uuid) returns void language plpgsql security definer set search_path = public as $$
declare t public.travel_tickets;
begin
  select * into t from public.travel_tickets where id = p_id for update;
  if not found then raise exception 'السجل غير موجود'; end if;
  perform public.require_role(t.company_id, array['owner','admin','hr']);
  if t.status <> 'approved' or t.entry_id is not null then raise exception 'لا يُلغى إلا قبل التسليم والصرف'; end if;
  update public.travel_tickets set status = 'cancelled' where id = p_id;   -- the entitlement returns to the employee
end $$;

-- HR attaches the issued visa with its number and return deadline: it reaches the employee
drop function if exists public.visa_record(uuid, text, date, date, text);
create or replace function public.visa_record(p_id uuid, p_no text, p_issued date, p_expires date, p_type text default null, p_files jsonb default null)
returns void language plpgsql security definer set search_path = public as $$
declare v public.exit_visas; n int;
begin
  select * into v from public.exit_visas where id = p_id for update;
  if not found then raise exception 'السجل غير موجود'; end if;
  perform public.require_role(v.company_id, array['owner','admin','hr']);
  if v.status not in ('requested','issued') then raise exception 'التأشيرة مغلقة'; end if;
  if length(trim(coalesce(p_no, ''))) < 4 then raise exception 'اكتب رقم التأشيرة'; end if;
  if p_issued is null or p_expires is null or p_expires < p_issued then raise exception 'حدد تاريخ الإصدار وآخر موعد للعودة'; end if;
  n := public.travel_store_files(v.company_id, v.employee_id, null, v.id, p_files);
  if n = 0 and not exists(select 1 from public.travel_files where visa_id = p_id) then raise exception 'أرفق التأشيرة (صورة أو PDF)'; end if;
  update public.exit_visas set status = 'issued', visa_no = trim(p_no), issued_on = p_issued, expires_on = p_expires,
    visa_type = coalesce(nullif(p_type, ''), visa_type), delivered_at = coalesce(delivered_at, now()) where id = p_id;
end $$;

-- file lists (names only) for a ticket or a visa
create or replace function public.travel_file_list(p_ticket uuid, p_visa uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'name', f.file_name, 'mime', f.mime, 'size', f.size) order by f.created_at), '[]')
    from public.travel_files f where (p_ticket is not null and f.ticket_id = p_ticket) or (p_visa is not null and f.visa_id = p_visa)
$$;

create or replace function public.request_timeline(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.requests; me uuid; sla int; i int; st text; a record; nm text; nm_en text; steps jsonb := '[]'; state text;
begin
  select * into r from public.requests where id = p_id;
  if not found then raise exception 'الطلب غير موجود'; end if;
  me := public.my_employee(r.company_id);
  if not (r.employee_id = me or public.has_role(r.company_id, array['owner','admin','hr','finance'])
          or exists(select 1 from public.employees e where e.id = r.employee_id and e.manager_id = me and me is not null)
          or exists(select 1 from public.companies c where c.id = r.company_id and c.hr_manager = auth.uid())) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  select request_sla_days into sla from public.companies where id = r.company_id;
  for i in 1 .. coalesce(cardinality(r.route), 0) loop
    st := r.route[i];
    select x.actor, x.action, x.at, x.note into a from public.request_actions x
     where x.request_id = p_id and x.actor_step = st and x.action in ('approved','rejected') order by x.at desc limit 1;
    nm := null; nm_en := null;
    if a.actor is not null then
      select e.full_name, e.full_name_en into nm, nm_en from public.members mb join public.employees e on e.id = mb.employee_id
       where mb.company_id = r.company_id and mb.user_id = a.actor;
    end if;
    state := case when i <= r.step then 'done'
                  when i = r.step + 1 and r.status = 'pending' then 'current'
                  when i = r.step + 1 and r.status = 'rejected' then 'rejected'
                  when i = r.step + 1 and r.status = 'cancelled' then 'cancelled'
                  when r.status in ('rejected','cancelled') then 'skipped' else 'waiting' end;
    steps := steps || jsonb_build_object('step', st, 'state', state,
      'by', case when state in ('done','rejected') then coalesce(nm, '—') end, 'by_en', case when state in ('done','rejected') then nm_en end,
      'at', case when state in ('done','rejected') then a.at end, 'note', case when state in ('done','rejected') then a.note end,
      'since', case when state = 'current' then r.step_at end,
      'hours', case when state = 'current' then round(extract(epoch from now() - r.step_at) / 3600) end,
      'overdue', state = 'current' and sla is not null and now() - r.step_at > make_interval(days => sla));
  end loop;
  return jsonb_build_object('status', r.status, 'submitted_at', r.created_at, 'decided_at', r.decided_at, 'sla_days', sla, 'steps', steps,
    'ticket', (select to_jsonb(t) - 'entry_id' || jsonb_build_object('paid', t.entry_id is not null, 'files', public.travel_file_list(t.id, null))
               from public.travel_tickets t where t.request_id = p_id limit 1),
    'visa', (select to_jsonb(v) || jsonb_build_object('files', public.travel_file_list(null, v.id)) from public.exit_visas v where v.request_id = p_id limit 1));
end $$;

create or replace function public.travel_board(p_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare td date := public.riyadh_today(); due jsonb := '[]'; e record; ts record;
begin
  perform public.require_role(p_company, array['owner','admin','hr','finance']);
  for e in select id, emp_no, full_name, full_name_en from public.employees where company_id = p_company and ticket_every is not null and (end_date is null or end_date >= td) order by emp_no loop
    select * into ts from public.ticket_status(e.id, td);
    if ts.available > 0 then due := due || jsonb_build_object('employee_id', e.id, 'emp_no', e.emp_no, 'name', e.full_name, 'name_en', e.full_name_en,
      'available', ts.available, 'persons', ts.persons, 'dest', ts.dest, 'dest_en', ts.dest_en, 'amount', ts.amount, 'class', ts.ticket_class); end if;
  end loop;
  return jsonb_build_object(
    'tickets', coalesce((select jsonb_agg(to_jsonb(t) - 'entry_id' || jsonb_build_object('paid', t.entry_id is not null, 'files', public.travel_file_list(t.id, null),
        'name', x.full_name, 'name_en', x.full_name_en, 'emp_no', x.emp_no,
        'dest', x.ticket_dest, 'dest_en', x.ticket_dest_en, 'class', x.ticket_class, 'from_date', q.from_date, 'to_date', q.to_date) order by t.status, t.created_at desc)
      from public.travel_tickets t join public.employees x on x.id = t.employee_id left join public.requests q on q.id = t.request_id
     where t.company_id = p_company and (t.status = 'approved' or t.entry_id is null and t.status <> 'cancelled' or t.created_at > now() - interval '1 year')), '[]'),
    'visas', coalesce((select jsonb_agg(to_jsonb(v) || jsonb_build_object('files', public.travel_file_list(null, v.id), 'name', x.full_name, 'name_en', x.full_name_en, 'emp_no', x.emp_no,
        'expiring', v.status = 'issued' and v.expires_on <= td + 7, 'late', v.status = 'issued' and v.return_on < td) order by v.status, v.travel_on)
      from public.exit_visas v join public.employees x on x.id = v.employee_id
     where v.company_id = p_company and (v.status in ('requested','issued') or v.created_at > now() - interval '1 year')), '[]'),
    'due', due);
end $$;

revoke all on function public.travel_store_files(uuid, uuid, uuid, uuid, jsonb), public.travel_file_list(uuid, uuid) from public, anon, authenticated;
revoke all on function public.ticket_attach(uuid, text, jsonb), public.ticket_pay(uuid, numeric, text, date, text), public.ticket_cancel(uuid),
  public.visa_record(uuid, text, date, date, text, jsonb) from public, anon;
grant execute on function public.ticket_attach(uuid, text, jsonb), public.ticket_pay(uuid, numeric, text, date, text), public.ticket_cancel(uuid),
  public.visa_record(uuid, text, date, date, text, jsonb) to authenticated;
notify pgrst, 'reload schema';
