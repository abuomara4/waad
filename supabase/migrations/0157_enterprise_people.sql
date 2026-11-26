-- Waad ERP — 0157 third free batch, people and customers (owner's request, 2026-11-26):
-- 20. competency matrix (a library, levels required per job description, each employee's assessed level) and succession
--     plans (a key position, its holder and ready successors);
-- 24. pay equity: average pay by gender and by Saudi / non-Saudi inside each grade (or job title), with the gap;
-- 25. recognition wall: colleagues thank each other with a value; everyone in the company sees it;
-- 26. product warranty (months per item, from the sales invoice) and service tickets (staff, or the customer from the portal);
-- 27. loyalty points at the point of sale: earned on what the customer pays, redeemed as part of the payment.

-- ---------------- 20. competencies and succession ----------------
create table if not exists public.competencies (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null check (length(btrim(name)) between 2 and 120),
  category text not null default 'core' check (category in ('core','technical','leadership','behavioral')),
  description text,
  unique (company_id, name)
);
create table if not exists public.jd_competencies (
  jd_id uuid not null references public.job_descriptions(id) on delete cascade,
  competency_id uuid not null references public.competencies(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  level int not null check (level between 1 and 5),
  primary key (jd_id, competency_id)
);
create index if not exists jd_comp_comp on public.jd_competencies(competency_id);
create index if not exists jd_comp_company on public.jd_competencies(company_id);
create table if not exists public.employee_competencies (
  employee_id uuid not null references public.employees(id) on delete cascade,
  competency_id uuid not null references public.competencies(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  level int not null check (level between 1 and 5),
  assessed_by uuid default auth.uid(), assessed_at timestamptz not null default now(),
  primary key (employee_id, competency_id)
);
create index if not exists emp_comp_comp on public.employee_competencies(competency_id);
create index if not exists emp_comp_company on public.employee_competencies(company_id);
alter table public.employees add column if not exists jd_id uuid references public.job_descriptions(id) on delete set null;
create index if not exists employees_jd on public.employees(jd_id);
create table if not exists public.succession_plans (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  position text not null check (length(btrim(position)) between 2 and 120),
  incumbent_id uuid references public.employees(id) on delete set null,
  risk text not null default 'medium' check (risk in ('low','medium','high')),
  successors jsonb not null default '[]',          -- [{emp, readiness: now|1y|2y, note}]
  note text, updated_at timestamptz not null default now()
);
create index if not exists succession_company on public.succession_plans(company_id);
create index if not exists succession_inc on public.succession_plans(incumbent_id);
alter table public.competencies enable row level security;
alter table public.jd_competencies enable row level security;
alter table public.employee_competencies enable row level security;
alter table public.succession_plans enable row level security;
revoke all on public.competencies, public.jd_competencies, public.employee_competencies, public.succession_plans from anon;
grant select on public.competencies, public.jd_competencies to authenticated;
revoke insert, update, delete on public.competencies, public.jd_competencies from authenticated;
revoke all on public.employee_competencies, public.succession_plans from authenticated;
grant select on public.employee_competencies, public.succession_plans to authenticated;
drop policy if exists comp_read on public.competencies;
create policy comp_read on public.competencies for select using (public.is_member(company_id));
drop policy if exists jdc_read on public.jd_competencies;
create policy jdc_read on public.jd_competencies for select using (public.is_member(company_id));
drop policy if exists empc_read on public.employee_competencies;
create policy empc_read on public.employee_competencies for select using (public.emp_branch_ok(company_id, employee_id) and (public.has_role(company_id, array['owner','admin','hr']) or public.fin_can(company_id, 'hr_emp')
  or employee_id = public.my_employee(company_id) or exists(select 1 from public.employees e where e.id = employee_id and e.manager_id = public.my_employee(company_id))));
drop policy if exists succ_read on public.succession_plans;
create policy succ_read on public.succession_plans for select using (public.has_role(company_id, array['owner','admin','hr']));

create or replace function public.competency_save(p_company uuid, p_id uuid, p_name text, p_category text, p_desc text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid := p_id;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if v is null then insert into public.competencies(company_id, name, category, description) values (p_company, btrim(p_name), coalesce(nullif(p_category, ''), 'core'), nullif(btrim(p_desc), '')) returning id into v;
  else update public.competencies set name = btrim(p_name), category = coalesce(nullif(p_category, ''), 'core'), description = nullif(btrim(p_desc), '') where id = v and company_id = p_company; end if;
  return v;
end $$;
-- the levels a job description requires: p_levels = {competency_id: level, …} (0 removes)
create or replace function public.jd_competencies_set(p_jd uuid, p_levels jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare j public.job_descriptions; k text;
begin
  select * into j from public.job_descriptions where id = p_jd;
  if not found then raise exception 'الوصف الوظيفي غير موجود'; end if;
  perform public.require_role(j.company_id, array['owner','admin','hr']);
  for k in select jsonb_object_keys(coalesce(p_levels, '{}')) loop
    if not exists(select 1 from public.competencies where id = k::uuid and company_id = j.company_id) then raise exception 'الجدارة ليست من المنشأة'; end if;
    if coalesce((p_levels->>k)::int, 0) = 0 then delete from public.jd_competencies where jd_id = p_jd and competency_id = k::uuid;
    else insert into public.jd_competencies(jd_id, competency_id, company_id, level) values (p_jd, k::uuid, j.company_id, (p_levels->>k)::int)
      on conflict (jd_id, competency_id) do update set level = excluded.level; end if;
  end loop;
end $$;
-- an employee's assessed levels: HR, or his direct manager
create or replace function public.employee_competencies_set(p_emp uuid, p_levels jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare e public.employees; k text;
begin
  select * into e from public.employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود'; end if;
  if not (public.has_role(e.company_id, array['owner','admin','hr']) or coalesce(e.manager_id = public.my_employee(e.company_id), false)) or not public.emp_branch_ok(e.company_id, e.id) then
    raise exception 'يقيّم الجدارات المدير المباشر أو الموارد البشرية' using errcode = '42501'; end if;
  for k in select jsonb_object_keys(coalesce(p_levels, '{}')) loop
    if not exists(select 1 from public.competencies where id = k::uuid and company_id = e.company_id) then raise exception 'الجدارة ليست من المنشأة'; end if;
    if coalesce((p_levels->>k)::int, 0) = 0 then delete from public.employee_competencies where employee_id = p_emp and competency_id = k::uuid;
    else insert into public.employee_competencies(employee_id, competency_id, company_id, level) values (p_emp, k::uuid, e.company_id, (p_levels->>k)::int)
      on conflict (employee_id, competency_id) do update set level = excluded.level, assessed_by = auth.uid(), assessed_at = now(); end if;
  end loop;
end $$;
create or replace function public.employee_jd_set(p_emp uuid, p_jd uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e public.employees;
begin
  select * into e from public.employees where id = p_emp;
  if not found then raise exception 'الموظف غير موجود'; end if;
  perform public.require_role(e.company_id, array['owner','admin','hr']);
  if p_jd is not null and not exists(select 1 from public.job_descriptions where id = p_jd and company_id = e.company_id) then raise exception 'الوصف الوظيفي ليس من المنشأة'; end if;
  update public.employees set jd_id = p_jd where id = p_emp;
end $$;
create or replace function public.succession_save(p_company uuid, p_id uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid := p_id; s jsonb;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if nullif(p_doc->>'incumbent', '') is not null and not exists(select 1 from public.employees where id = (p_doc->>'incumbent')::uuid and company_id = p_company) then raise exception 'الموظف غير موجود'; end if;
  for s in select * from jsonb_array_elements(coalesce(p_doc->'successors', '[]')) loop
    if not exists(select 1 from public.employees where id = (s->>'emp')::uuid and company_id = p_company) then raise exception 'المرشح غير موجود'; end if;
    if coalesce(s->>'readiness', '') not in ('now','1y','2y') then raise exception 'حدد جاهزية المرشح'; end if;
  end loop;
  if v is null then
    insert into public.succession_plans(company_id, position, incumbent_id, risk, successors, note)
    values (p_company, btrim(p_doc->>'position'), nullif(p_doc->>'incumbent', '')::uuid, coalesce(nullif(p_doc->>'risk', ''), 'medium'), coalesce(p_doc->'successors', '[]'), nullif(btrim(p_doc->>'note'), '')) returning id into v;
  else
    update public.succession_plans set position = btrim(p_doc->>'position'), incumbent_id = nullif(p_doc->>'incumbent', '')::uuid, risk = coalesce(nullif(p_doc->>'risk', ''), 'medium'),
      successors = coalesce(p_doc->'successors', '[]'), note = nullif(btrim(p_doc->>'note'), ''), updated_at = now() where id = v and company_id = p_company;
  end if;
  return v;
end $$;

-- ---------------- 24. pay equity ----------------
create or replace function public.pay_equity(p_company uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  return coalesce((with e as (
      select coalesce((select g.code || ' — ' || g.name from public.job_grades g where g.id = x.grade_id), nullif(btrim(x.job_title), ''), '—') grp, x.gender, x.is_saudi,
             x.basic + x.housing + x.transport + public.emp_allow(x.id, current_date) gross, x.basic
        from public.employees x where x.company_id = p_company and (x.end_date is null or x.end_date >= current_date) and public.emp_branch_ok(p_company, x.id)),
    g as (select grp, count(*) n,
        count(*) filter (where gender = 'm') nm, count(*) filter (where gender = 'f') nf,
        round(avg(gross) filter (where gender = 'm'), 2) am, round(avg(gross) filter (where gender = 'f'), 2) af,
        count(*) filter (where is_saudi) ns, count(*) filter (where not is_saudi) nn,
        round(avg(gross) filter (where is_saudi), 2) asa, round(avg(gross) filter (where not is_saudi), 2) ano,
        round(percentile_cont(0.5) within group (order by gross)::numeric, 2) med
      from e group by grp)
    select jsonb_agg(jsonb_build_object('group', grp, 'n', n, 'median', med, 'men', nm, 'women', nf, 'avg_men', am, 'avg_women', af,
        'gender_gap', case when nm > 0 and nf > 0 and am > 0 then round((am - af) / am * 100, 1) end,
        'saudi', ns, 'non_saudi', nn, 'avg_saudi', asa, 'avg_non_saudi', ano,
        'nat_gap', case when ns > 0 and nn > 0 and asa > 0 then round((asa - ano) / asa * 100, 1) end) order by grp) from g), '[]');
end $$;

-- ---------------- 25. recognition ----------------
create table if not exists public.kudos (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  from_emp uuid not null references public.employees(id) on delete cascade,
  to_emp uuid not null references public.employees(id) on delete cascade,
  value text not null check (value in ('teamwork','excellence','help','initiative','customer','integrity')),
  message text not null check (length(btrim(message)) between 3 and 500),
  created_at timestamptz not null default now(),
  check (from_emp <> to_emp)
);
create index if not exists kudos_company on public.kudos(company_id, created_at desc);
create index if not exists kudos_from on public.kudos(from_emp);
create index if not exists kudos_to on public.kudos(to_emp);
alter table public.kudos enable row level security;
revoke all on public.kudos from anon, authenticated;
grant select on public.kudos to authenticated;
drop policy if exists kudos_read on public.kudos;
create policy kudos_read on public.kudos for select using (public.is_member(company_id));
create or replace function public.kudos_send(p_company uuid, p_to uuid, p_value text, p_message text) returns uuid
language plpgsql security definer set search_path = public as $$
declare me uuid := public.my_employee(p_company); v uuid;
begin
  if me is null then raise exception 'حسابك غير مربوط بسجل موظف' using errcode = '42501'; end if;
  if p_to = me then raise exception 'الشكر لزميل'; end if;
  if not exists(select 1 from public.employees where id = p_to and company_id = p_company and (end_date is null or end_date >= current_date)) then raise exception 'اختر زميلا من المنشأة'; end if;
  if (select count(*) from public.kudos where from_emp = me and created_at > now() - interval '1 day') >= 10 then raise exception 'حد 10 رسائل شكر في اليوم'; end if;
  insert into public.kudos(company_id, from_emp, to_emp, value, message) values (p_company, me, p_to, p_value, btrim(p_message)) returning id into v;
  return v;
end $$;
create or replace function public.kudos_wall(p_company uuid, p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_member(p_company) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return jsonb_build_object(
    'items', coalesce((select jsonb_agg(z) from (select jsonb_build_object('id', k.id, 'from', a.full_name, 'to', b.full_name, 'to_id', k.to_emp, 'value', k.value, 'message', k.message, 'at', k.created_at) z
        from public.kudos k join public.employees a on a.id = k.from_emp join public.employees b on b.id = k.to_emp where k.company_id = p_company order by k.created_at desc limit least(coalesce(p_limit, 50), 200)) t), '[]'),
    'top', coalesce((select jsonb_agg(z) from (select jsonb_build_object('name', b.full_name, 'n', count(*)) z from public.kudos k join public.employees b on b.id = k.to_emp
        where k.company_id = p_company and k.created_at >= date_trunc('month', now()) group by b.full_name order by count(*) desc limit 5) t), '[]'));
end $$;

-- ---------------- 26. warranty and service tickets ----------------
alter table public.items add column if not exists warranty_months int check (warranty_months is null or warranty_months between 1 and 120);
create table if not exists public.service_tickets (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  no text not null,
  party_id uuid references public.parties(id) on delete set null,
  contact text,
  kind text not null default 'support' check (kind in ('support','repair','maintenance','complaint','question')),
  subject text not null check (length(btrim(subject)) between 3 and 200),
  description text,
  item_id uuid references public.items(id) on delete set null,
  serial text,
  invoice_id uuid references public.sales_invoices(id) on delete set null,
  warranty_until date,
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  status text not null default 'new' check (status in ('new','open','waiting','resolved','closed')),
  assigned_to uuid references public.employees(id) on delete set null,
  resolution text,
  source text not null default 'staff' check (source in ('staff','portal')),
  created_by uuid default auth.uid(), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), resolved_at timestamptz,
  unique (company_id, no)
);
create index if not exists tickets_company on public.service_tickets(company_id, status);
create index if not exists tickets_party on public.service_tickets(party_id);
create index if not exists tickets_item on public.service_tickets(item_id);
create index if not exists tickets_inv on public.service_tickets(invoice_id);
create index if not exists tickets_assigned on public.service_tickets(assigned_to);
create table if not exists public.ticket_notes (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.service_tickets(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  side text not null check (side in ('staff','customer','internal')),
  body text not null check (length(btrim(body)) between 1 and 5000),
  by_user uuid default auth.uid(), created_at timestamptz not null default now()
);
create index if not exists ticket_notes_t on public.ticket_notes(ticket_id);
create index if not exists ticket_notes_c on public.ticket_notes(company_id);
alter table public.service_tickets enable row level security;
alter table public.ticket_notes enable row level security;
revoke all on public.service_tickets, public.ticket_notes from anon, authenticated;
grant select on public.service_tickets, public.ticket_notes to authenticated;
drop policy if exists tickets_read on public.service_tickets;
create policy tickets_read on public.service_tickets for select using (public.fin_can(company_id, 'sales') or assigned_to = public.my_employee(company_id));
drop policy if exists tnotes_read on public.ticket_notes;
create policy tnotes_read on public.ticket_notes for select using (exists(select 1 from public.service_tickets t where t.id = ticket_id and (public.fin_can(t.company_id, 'sales') or t.assigned_to = public.my_employee(t.company_id))));

-- pure: the warranty end of an item sold on an invoice date
create or replace function public.warranty_end(p_sold date, p_months int) returns date language sql immutable as $$
  select case when p_sold is not null and coalesce(p_months, 0) > 0 then (p_sold + make_interval(months => p_months))::date - 1 end
$$;
-- the warranty of a sold item: by serial (if serial-tracked) or by invoice + item
create or replace function public.warranty_lookup(p_company uuid, p_invoice uuid, p_item uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare i public.sales_invoices; m int;
begin
  perform public.require_fin(p_company, 'sales');
  select * into i from public.sales_invoices where id = p_invoice and company_id = p_company and status = 'posted';
  if not found then return null; end if;
  if not exists(select 1 from public.sales_invoice_lines l where l.invoice_id = i.id and l.item_id = p_item) then return null; end if;
  select warranty_months into m from public.items where id = p_item;
  return jsonb_build_object('sold', i.date, 'months', m, 'until', public.warranty_end(i.date, m), 'valid', coalesce(public.warranty_end(i.date, m) >= current_date, false));
end $$;
create or replace function public.ticket_save(p_company uuid, p_id uuid, p_doc jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid := p_id; w jsonb; t public.service_tickets;
begin
  perform public.require_fin(p_company, 'sales');
  if nullif(p_doc->>'party', '') is not null and not exists(select 1 from public.parties where id = (p_doc->>'party')::uuid and company_id = p_company and kind = 'customer') then raise exception 'العميل غير موجود'; end if;
  if nullif(p_doc->>'assigned', '') is not null and not exists(select 1 from public.employees where id = (p_doc->>'assigned')::uuid and company_id = p_company) then raise exception 'الموظف غير موجود'; end if;
  if nullif(p_doc->>'item', '') is not null and not exists(select 1 from public.items where id = (p_doc->>'item')::uuid and company_id = p_company) then raise exception 'الصنف غير موجود'; end if;
  if nullif(p_doc->>'invoice', '') is not null and nullif(p_doc->>'item', '') is not null then w := public.warranty_lookup(p_company, (p_doc->>'invoice')::uuid, (p_doc->>'item')::uuid); end if;
  if v is null then
    insert into public.service_tickets(company_id, no, party_id, contact, kind, subject, description, item_id, serial, invoice_id, warranty_until, priority, assigned_to)
    values (p_company, public.next_doc_no(p_company, 'TK'), nullif(p_doc->>'party', '')::uuid, nullif(btrim(p_doc->>'contact'), ''), coalesce(nullif(p_doc->>'kind', ''), 'support'),
            btrim(p_doc->>'subject'), nullif(btrim(p_doc->>'description'), ''), nullif(p_doc->>'item', '')::uuid, nullif(btrim(p_doc->>'serial'), ''),
            nullif(p_doc->>'invoice', '')::uuid, (w->>'until')::date, coalesce(nullif(p_doc->>'priority', ''), 'normal'), nullif(p_doc->>'assigned', '')::uuid) returning id into v;
  else
    select * into t from public.service_tickets where id = v and company_id = p_company;
    if not found then raise exception 'التذكرة غير موجودة'; end if;
    update public.service_tickets set kind = coalesce(nullif(p_doc->>'kind', ''), kind), priority = coalesce(nullif(p_doc->>'priority', ''), priority),
      status = coalesce(nullif(p_doc->>'status', ''), status), assigned_to = case when p_doc ? 'assigned' then nullif(p_doc->>'assigned', '')::uuid else assigned_to end,
      resolution = case when p_doc ? 'resolution' then nullif(btrim(p_doc->>'resolution'), '') else resolution end, updated_at = now(),
      resolved_at = case when coalesce(nullif(p_doc->>'status', ''), status) in ('resolved','closed') then coalesce(resolved_at, now()) end where id = v;
    if coalesce(p_doc->>'status', '') in ('resolved','closed') and nullif(btrim(coalesce(p_doc->>'resolution', t.resolution, '')), '') is null then raise exception 'اكتب الحل قبل إغلاق التذكرة'; end if;
  end if;
  return v;
end $$;
create or replace function public.ticket_note(p_id uuid, p_body text, p_internal boolean) returns void
language plpgsql security definer set search_path = public as $$
declare t public.service_tickets;
begin
  select * into t from public.service_tickets where id = p_id;
  if not found or not (public.fin_can(t.company_id, 'sales') or coalesce(t.assigned_to = public.my_employee(t.company_id), false)) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  insert into public.ticket_notes(ticket_id, company_id, side, body) values (p_id, t.company_id, case when coalesce(p_internal, false) then 'internal' else 'staff' end, btrim(p_body));
  update public.service_tickets set updated_at = now(), status = case when status = 'new' then 'open' else status end where id = p_id;
end $$;
-- anon, from the customer's portal link: open a ticket and follow the company's replies (internal notes never shown)
create or replace function public.portal_tickets(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l public.portal_links;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return null; end if;
  select * into l from public.portal_links where token = p_token and revoked_at is null;
  if not found then return null; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('no', t.no, 'subject', t.subject, 'status', t.status, 'at', t.created_at, 'resolution', t.resolution,
      'notes', coalesce((select jsonb_agg(jsonb_build_object('side', n.side, 'body', n.body, 'at', n.created_at) order by n.created_at) from public.ticket_notes n where n.ticket_id = t.id and n.side <> 'internal'), '[]'))
      order by t.created_at desc) from public.service_tickets t where t.company_id = l.company_id and t.party_id = l.party_id), '[]');
end $$;
create or replace function public.portal_ticket_open(p_token text, p_subject text, p_body text) returns text
language plpgsql security definer set search_path = public as $$
declare l public.portal_links; v text;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then raise exception 'رابط غير صحيح'; end if;
  select * into l from public.portal_links where token = p_token and revoked_at is null;
  if not found then raise exception 'رابط غير صحيح'; end if;
  if length(btrim(coalesce(p_subject, ''))) < 3 or length(btrim(coalesce(p_body, ''))) < 5 then raise exception 'اكتب الموضوع والتفاصيل'; end if;
  if (select count(*) from public.service_tickets where party_id = l.party_id and source = 'portal' and created_at > now() - interval '1 day') >= 5 then raise exception 'حد 5 تذاكر في اليوم'; end if;
  v := public.next_doc_no(l.company_id, 'TK');
  insert into public.service_tickets(company_id, no, party_id, subject, description, source, created_by) values (l.company_id, v, l.party_id, left(btrim(p_subject), 200), left(btrim(p_body), 5000), 'portal', null);
  return v;
end $$;

-- ---------------- 27. loyalty points (point of sale) ----------------
alter table public.companies add column if not exists loyalty_on boolean not null default false,
  add column if not exists loyalty_earn numeric(8,4) not null default 1 check (loyalty_earn >= 0),       -- points per riyal paid
  add column if not exists loyalty_value numeric(8,4) not null default 0.05 check (loyalty_value >= 0),  -- riyals per point
  add column if not exists loyalty_min int not null default 100 check (loyalty_min >= 0);
create table if not exists public.loyalty_ledger (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  party_id uuid not null references public.parties(id) on delete cascade,
  points int not null check (points <> 0),
  source text not null check (source in ('earn','redeem','void','adjust')),
  invoice_id uuid references public.sales_invoices(id) on delete set null,
  note text,
  created_by uuid default auth.uid(), created_at timestamptz not null default now()
);
create index if not exists loyalty_party on public.loyalty_ledger(party_id);
create index if not exists loyalty_company on public.loyalty_ledger(company_id);
create index if not exists loyalty_inv on public.loyalty_ledger(invoice_id);
alter table public.loyalty_ledger enable row level security;
revoke all on public.loyalty_ledger from anon, authenticated;
grant select on public.loyalty_ledger to authenticated;
drop policy if exists loyalty_read on public.loyalty_ledger;
create policy loyalty_read on public.loyalty_ledger for select using (public.fin_can(company_id, 'sales'));
create or replace function public.loyalty_set(p_company uuid, p_on boolean, p_earn numeric, p_value numeric, p_min int) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin','finance']);
  if coalesce(p_earn, 0) < 0 or coalesce(p_value, 0) < 0 or coalesce(p_min, 0) < 0 then raise exception 'القيم لا تكون سالبة'; end if;
  update public.companies set loyalty_on = coalesce(p_on, false), loyalty_earn = coalesce(p_earn, 1), loyalty_value = coalesce(p_value, 0.05), loyalty_min = coalesce(p_min, 100) where id = p_company;
end $$;
create or replace function public.loyalty_balance(p_party uuid) returns int
language plpgsql stable security definer set search_path = public as $$
declare c uuid;
begin
  select company_id into c from public.parties where id = p_party;
  if c is null then return 0; end if;
  perform public.require_fin(c, 'sales');
  return coalesce((select sum(points) from public.loyalty_ledger where party_id = p_party), 0)::int;
end $$;
-- the points of a sale: redeem first (settled through 5975 «تكلفة برنامج الولاء», VAT stays on the whole invoice), then earn
-- on what the customer paid in money
create or replace function public.loyalty_apply(p_company uuid, p_invoice uuid, p_redeem int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c public.companies; i public.sales_invoices; bal int; val numeric := 0; earn int := 0; no text; pid uuid;
begin
  select * into c from public.companies where id = p_company;
  select * into i from public.sales_invoices where id = p_invoice and company_id = p_company and status = 'posted';
  if not found or not c.loyalty_on then return null; end if;
  if exists(select 1 from public.parties where id = i.party_id and name = 'عميل نقدي') then return null; end if;
  if exists(select 1 from public.loyalty_ledger where invoice_id = p_invoice) then raise exception 'سُجّلت نقاط هذه الفاتورة'; end if;
  bal := coalesce((select sum(points) from public.loyalty_ledger where party_id = i.party_id), 0);
  if coalesce(p_redeem, 0) > 0 then
    if p_redeem > bal then raise exception 'رصيد النقاط %', bal; end if;
    if p_redeem < c.loyalty_min then raise exception 'أقل استبدال % نقطة', c.loyalty_min; end if;
    val := round(p_redeem * c.loyalty_value, 2);
    if val > i.total - public.paid_on(i.id) + 0.001 then raise exception 'قيمة النقاط أكبر من المتبقي'; end if;
    insert into public.accounts(company_id, code, name, name_en, type, parent_code, is_header) values (p_company, '5975', 'تكلفة برنامج الولاء', 'Loyalty programme cost', 'exp', '5000', false) on conflict do nothing;
    no := public.next_doc_no(p_company, 'RV');
    insert into public.payments(company_id, no, direction, party_id, invoice_id, date, amount, account_code, note)
    values (p_company, no, 'in', i.party_id, i.id, current_date, val, '5975', 'استبدال ' || p_redeem || ' نقطة ولاء') returning id into pid;
    perform public.post_journal(p_company, current_date, 'استبدال نقاط ولاء ' || no, 'loyalty', pid,
      jsonb_build_array(jsonb_build_object('a', '5975', 'd', val), jsonb_build_object('a', '1200', 'c', val)));
    insert into public.loyalty_ledger(company_id, party_id, points, source, invoice_id) values (p_company, i.party_id, -p_redeem, 'redeem', i.id);
  end if;
  earn := floor((i.total - val) * c.loyalty_earn)::int;
  if earn > 0 then insert into public.loyalty_ledger(company_id, party_id, points, source, invoice_id) values (p_company, i.party_id, earn, 'earn', i.id); end if;
  return jsonb_build_object('redeemed', coalesce(p_redeem, 0), 'value', val, 'earned', earn, 'balance', bal - coalesce(p_redeem, 0) + earn);
end $$;
-- a voided invoice takes its points back
create or replace function public.loyalty_void_trg() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'void' and old.status is distinct from 'void' then
    insert into public.loyalty_ledger(company_id, party_id, points, source, invoice_id, note)
    select new.company_id, l.party_id, -sum(l.points), 'void', new.id, 'إلغاء الفاتورة' from public.loyalty_ledger l where l.invoice_id = new.id group by l.party_id having sum(l.points) <> 0;
  end if;
  return null;
end $$;
drop trigger if exists loyalty_void on public.sales_invoices;
create trigger loyalty_void after update of status on public.sales_invoices for each row execute function public.loyalty_void_trg();

-- the till: pos_sale with points (p_doc.points), applied inside the same transaction
create or replace function public.pos_sale_pts(p_company uuid, p_shift uuid, p_doc jsonb, p_cash numeric, p_card numeric, p_cheque jsonb default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare iid uuid; c public.companies; pts int := coalesce(nullif(p_doc->>'points', '')::int, 0); val numeric; tot numeric; r jsonb;
begin
  select * into c from public.companies where id = p_company;
  val := round(pts * coalesce(c.loyalty_value, 0), 2);
  if pts > 0 and pts > coalesce((select sum(points) from public.loyalty_ledger where party_id = nullif(p_doc->>'party', '')::uuid), 0) then
    raise exception 'رصيد النقاط %', coalesce((select sum(points) from public.loyalty_ledger where party_id = nullif(p_doc->>'party', '')::uuid), 0); end if;
  iid := public.pos_sale(p_company, p_shift, p_doc - 'points', p_cash, p_card, p_cheque);
  select total into tot from public.sales_invoices where id = iid;
  if round(coalesce(p_cash, 0), 2) + round(coalesce(p_card, 0), 2) + round(coalesce((p_cheque->>'amount')::numeric, 0), 2) + val > tot + 0.005 then raise exception 'المدفوع مع النقاط أكبر من الإجمالي'; end if;
  r := public.loyalty_apply(p_company, iid, pts);
  return jsonb_build_object('invoice', iid, 'loyalty', r);
end $$;

revoke all on function public.loyalty_void_trg(), public.loyalty_apply(uuid, uuid, int) from public, anon, authenticated;
revoke all on function public.competency_save(uuid, uuid, text, text, text), public.jd_competencies_set(uuid, jsonb), public.employee_competencies_set(uuid, jsonb), public.employee_jd_set(uuid, uuid),
  public.succession_save(uuid, uuid, jsonb), public.pay_equity(uuid), public.kudos_send(uuid, uuid, text, text), public.kudos_wall(uuid, int),
  public.warranty_end(date, int), public.warranty_lookup(uuid, uuid, uuid), public.ticket_save(uuid, uuid, jsonb), public.ticket_note(uuid, text, boolean),
  public.loyalty_set(uuid, boolean, numeric, numeric, int), public.loyalty_balance(uuid), public.pos_sale_pts(uuid, uuid, jsonb, numeric, numeric, jsonb) from public, anon;
grant execute on function public.competency_save(uuid, uuid, text, text, text), public.jd_competencies_set(uuid, jsonb), public.employee_competencies_set(uuid, jsonb), public.employee_jd_set(uuid, uuid),
  public.succession_save(uuid, uuid, jsonb), public.pay_equity(uuid), public.kudos_send(uuid, uuid, text, text), public.kudos_wall(uuid, int),
  public.warranty_end(date, int), public.warranty_lookup(uuid, uuid, uuid), public.ticket_save(uuid, uuid, jsonb), public.ticket_note(uuid, text, boolean),
  public.loyalty_set(uuid, boolean, numeric, numeric, int), public.loyalty_balance(uuid), public.pos_sale_pts(uuid, uuid, jsonb, numeric, numeric, jsonb) to authenticated;
revoke all on function public.portal_tickets(text), public.portal_ticket_open(text, text, text) from public;
grant execute on function public.portal_tickets(text), public.portal_ticket_open(text, text, text) to anon, authenticated;
notify pgrst, 'reload schema';
