-- Waad ERP — 0013: employee documents (expiry dates only, no scans) and employment contracts, with expiry alerts.
-- Labor Law Art. 37: a non-Saudi's contract is written and fixed-term (1 year if no term; renewed for the same term if work continues).
-- Art. 55/1: a fixed-term contract that both parties keep performing after it ends becomes indefinite (non-Saudis: Art. 37).
-- Art. 55/2: after 3 consecutive renewals or 4 years in total (whichever is less), continuing turns it indefinite.
-- Art. 75: indefinite, monthly-paid: notice 30 days from the worker, 60 days from the employer; not monthly-paid: 30 days.

create table public.employee_documents (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  doc_type text not null check (doc_type in ('iqama','national_id','passport','work_permit','health','driving','other')),
  title text,
  doc_no text,
  issue_date date,
  expiry_date date,
  notes text,
  created_at timestamptz not null default now(),
  check (doc_type <> 'other' or length(trim(coalesce(title, ''))) >= 2),
  check (issue_date is null or expiry_date is null or expiry_date >= issue_date)
);
create index on public.employee_documents(company_id, expiry_date);
create index on public.employee_documents(employee_id);

create table public.contracts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  contract_type text not null check (contract_type in ('fixed','indefinite')),
  start_date date not null,
  end_date date,
  monthly_paid boolean not null default true,
  renewal_clause boolean not null default false,
  renewal_no int not null default 0 check (renewal_no >= 0),
  first_start date not null,
  prev_id uuid references public.contracts(id) on delete set null,
  status text not null default 'active' check (status in ('active','renewed','ended')),
  notes text,
  created_at timestamptz not null default now(),
  check ((contract_type = 'fixed') = (end_date is not null)),
  check (end_date is null or end_date >= start_date),
  check (first_start <= start_date)
);
create index on public.contracts(employee_id);
create unique index contracts_one_active on public.contracts(employee_id) where status = 'active';

-- same-company and Art. 37 checks
create or replace function public.contract_guard() returns trigger language plpgsql as $$
declare e public.employees;
begin
  select * into e from public.employees where id = new.employee_id;
  if e.company_id is distinct from new.company_id then raise exception 'الموظف غير موجود في المنشأة'; end if;
  if not e.is_saudi and new.contract_type = 'indefinite' then
    raise exception 'عقد غير السعودي يكون محدد المدة — م37'; end if;
  return new;
end $$;
create trigger contracts_guard before insert or update on public.contracts for each row execute function public.contract_guard();
create or replace function public.document_guard() returns trigger language plpgsql as $$
begin
  if not exists(select 1 from public.employees e where e.id = new.employee_id and e.company_id = new.company_id) then
    raise exception 'الموظف غير موجود في المنشأة'; end if;
  return new;
end $$;
create trigger documents_guard before insert or update on public.employee_documents for each row execute function public.document_guard();

-- new contract (closes any active one as 'ended')
create or replace function public.contract_add(p_company uuid, p_emp uuid, p_type text, p_start date, p_end date, p_monthly boolean default true, p_clause boolean default false, p_notes text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare e public.employees; rid uuid; v_end date := p_end;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  select * into e from public.employees where id = p_emp and company_id = p_company;
  if not found then raise exception 'الموظف غير موجود في المنشأة'; end if;
  if p_start is null then raise exception 'أدخل تاريخ بداية العقد'; end if;
  if p_type = 'fixed' and v_end is null then
    if e.is_saudi then raise exception 'أدخل تاريخ نهاية العقد المحدد المدة'; end if;
    v_end := (p_start + interval '1 year' - interval '1 day')::date;   -- Art. 37: one year when no term is stated
  end if;
  if p_type = 'indefinite' then v_end := null; end if;
  update public.contracts set status = 'ended' where employee_id = p_emp and status = 'active';
  insert into public.contracts(company_id, employee_id, contract_type, start_date, end_date, monthly_paid, renewal_clause, first_start, notes)
  values (p_company, p_emp, p_type, p_start, v_end, coalesce(p_monthly, true), coalesce(p_clause, false), p_start, nullif(trim(p_notes), '')) returning id into rid;
  return rid;
end $$;

-- renew a fixed-term contract; the new term starts the day after the old one ends
create or replace function public.contract_renew(p_id uuid, p_end date) returns uuid
language plpgsql security definer set search_path = public as $$
declare c public.contracts; rid uuid;
begin
  select * into c from public.contracts where id = p_id;
  if not found then raise exception 'العقد غير موجود'; end if;
  perform public.require_role(c.company_id, array['owner','admin','hr']);
  if c.status <> 'active' or c.contract_type <> 'fixed' then raise exception 'يُجدد العقد الساري المحدد المدة فقط'; end if;
  if p_end is null or p_end <= c.end_date then raise exception 'تاريخ نهاية التجديد بعد نهاية العقد الحالي'; end if;
  update public.contracts set status = 'renewed' where id = p_id;
  insert into public.contracts(company_id, employee_id, contract_type, start_date, end_date, monthly_paid, renewal_clause, renewal_no, first_start, prev_id)
  values (c.company_id, c.employee_id, 'fixed', c.end_date + 1, p_end, c.monthly_paid, c.renewal_clause, c.renewal_no + 1, c.first_start, c.id) returning id into rid;
  return rid;
end $$;

-- convert to indefinite (Art. 55) keeping the service start
create or replace function public.contract_make_indefinite(p_id uuid, p_from date) returns uuid
language plpgsql security definer set search_path = public as $$
declare c public.contracts; rid uuid;
begin
  select * into c from public.contracts where id = p_id;
  if not found then raise exception 'العقد غير موجود'; end if;
  perform public.require_role(c.company_id, array['owner','admin','hr']);
  if c.status <> 'active' or c.contract_type <> 'fixed' then raise exception 'يُحوَّل العقد الساري المحدد المدة فقط'; end if;
  update public.contracts set status = 'renewed' where id = p_id;
  insert into public.contracts(company_id, employee_id, contract_type, start_date, end_date, monthly_paid, renewal_clause, renewal_no, first_start, prev_id, notes)
  values (c.company_id, c.employee_id, 'indefinite', coalesce(p_from, c.end_date + 1), null, c.monthly_paid, false, c.renewal_no, c.first_start, c.id, 'تحوّل إلى غير محدد المدة — م55') returning id into rid;
  return rid;
end $$;

-- every expiry / contract issue for active employees, soonest first
create or replace function public.doc_alerts(p_company uuid, p_within int default 90)
returns table(employee_id uuid, kind text, ref_id uuid, label text, ref_no text, due date, days_left int, level text, note text)
language plpgsql stable security definer set search_path = public as $$
declare td date := (now() at time zone 'Asia/Riyadh')::date;
begin
  if not public.has_role(p_company, array['owner','admin','hr']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query
  with act as (select * from public.employees e where e.company_id = p_company and (e.end_date is null or e.end_date >= td)),
  docs as (
    select d.employee_id, 'doc'::text kind, d.id ref_id, d.doc_type label, d.doc_no ref_no, d.expiry_date due, null::text note
    from public.employee_documents d join act on act.id = d.employee_id
    where d.expiry_date is not null and d.expiry_date <= td + p_within
      and not exists(select 1 from public.employee_documents n where n.employee_id = d.employee_id and n.doc_type = d.doc_type and n.doc_type <> 'other'
                     and n.expiry_date > d.expiry_date)),
  con as (
    select c.employee_id, 'contract'::text kind, c.id ref_id, 'contract'::text label, null::text ref_no, c.end_date due,
      case when not act.is_saudi then 'م37: إذا استمر العمل بعد انتهائه عُدّ متجدداً لمدة مماثلة'
           when (c.renewal_no >= 3 or c.end_date >= c.first_start + interval '4 years' - interval '1 day') then 'م55/2: الاستمرار بعده يحوّله إلى غير محدد المدة'
           when c.renewal_clause then 'يتجدد تلقائياً للمدة المتفق عليها — م55/2'
           else 'م55/1: الاستمرار بعده يجعله غير محدد المدة' end note
    from public.contracts c join act on act.id = c.employee_id
    where c.status = 'active' and c.contract_type = 'fixed' and c.end_date <= td + p_within),
  miss as (
    select act.id employee_id, 'missing'::text kind, null::uuid ref_id, t.k label, null::text ref_no, null::date due, null::text note
    from act cross join (values ('iqama'), ('work_permit')) t(k)
    where not act.is_saudi and not exists(select 1 from public.employee_documents d where d.employee_id = act.id and d.doc_type = t.k)
    union all
    select act.id, 'missing'::text, null::uuid, 'contract'::text, null::text, null::date, null::text from act
    where not exists(select 1 from public.contracts c where c.employee_id = act.id and c.status = 'active'))
  select x.employee_id, x.kind, x.ref_id, x.label, x.ref_no, x.due, (x.due - td)::int,
    case when x.due is null then 'missing' when x.due < td then 'expired' when x.due <= td + 30 then 'd30' when x.due <= td + 60 then 'd60' else 'd90' end,
    x.note
  from (select * from docs union all select * from con union all select * from miss) x
  order by x.due nulls last, x.employee_id;
end $$;

-- ---------- audit, RLS, grants ----------
create trigger audit_documents after insert or update or delete on public.employee_documents for each row execute function public.audit_trigger();
create trigger audit_contracts after insert or update or delete on public.contracts for each row execute function public.audit_trigger();

alter table public.employee_documents enable row level security;
alter table public.contracts enable row level security;
create policy doc_read on public.employee_documents for select using (public.has_role(company_id, array['owner','admin','hr']) or employee_id = public.my_employee(company_id));
create policy doc_write on public.employee_documents for all using (public.has_role(company_id, array['owner','admin','hr'])) with check (public.has_role(company_id, array['owner','admin','hr']));
create policy con_read on public.contracts for select using (public.has_role(company_id, array['owner','admin','hr','finance']) or employee_id = public.my_employee(company_id));

revoke all on public.employee_documents, public.contracts from anon;
grant select, insert, update, delete on public.employee_documents to authenticated;
grant select on public.contracts to authenticated;
revoke insert, update, delete on public.contracts from authenticated;

revoke all on function public.contract_add(uuid, uuid, text, date, date, boolean, boolean, text), public.contract_renew(uuid, date), public.contract_make_indefinite(uuid, date),
  public.doc_alerts(uuid, int), public.contract_guard(), public.document_guard() from public, anon, authenticated;
grant execute on function public.contract_add(uuid, uuid, text, date, date, boolean, boolean, text), public.contract_renew(uuid, date), public.contract_make_indefinite(uuid, date),
  public.doc_alerts(uuid, int) to authenticated;
notify pgrst, 'reload schema';
