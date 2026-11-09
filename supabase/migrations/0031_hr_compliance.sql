-- HR compliance tools:
--  * the expiry list also shows the end of probation and the 5-year service milestone;
--  * a GOSI report per payroll: contribution wage, shares, joiners/leavers and wage changes to update in GOSI;
--  * Nitaqat: the band thresholds of the company (from Qiwa), so the app can show the band and what-ifs;
--  * who may see the organisation chart.

alter table public.companies add column nitaqat jsonb not null default '{}',
                             add column org_visibility text not null default 'all' check (org_visibility in ('all','managers','hr'));

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
    where not exists(select 1 from public.contracts c where c.employee_id = act.id and c.status = 'active')),
  -- statutory dates HR must act on: the end of probation (Reg. Art. 19: extended by holidays and sick days)
  prob as (
    select act.id employee_id, 'probation'::text kind, null::uuid ref_id, 'probation'::text label, null::text ref_no, pe.d due,
           'م53: قرّر التثبيت أو الإنهاء قبل نهايتها'::text note
    from act cross join lateral (select public.probation_effective_end(act.id) d) pe
    where act.probation_end is not null and pe.d between td and td + p_within),
  -- five years of service: annual leave becomes 30 days (Art. 109) and end-of-service a full month per year after (Art. 84)
  svc as (
    select act.id employee_id, 'service5'::text kind, null::uuid ref_id, 'service5'::text label, null::text ref_no, (act.hire_date + interval '5 years')::date due,
           'م109: تصبح الإجازة السنوية 30 يوماً — م84: أجر شهر عن كل سنة بعد الخمس'::text note
    from act where (act.hire_date + interval '5 years')::date between td and td + p_within)
  select x.employee_id, x.kind, x.ref_id, x.label, x.ref_no, x.due, (x.due - td)::int,
    case when x.due is null then 'missing' when x.due < td then 'expired' when x.due <= td + 30 then 'd30' when x.due <= td + 60 then 'd60' else 'd90' end,
    x.note
  from (select * from docs union all select * from con union all select * from miss union all select * from prob union all select * from svc) x
  order by x.due nulls last, x.employee_id;
end $$;

-- GOSI per payroll: contribution wage = basic + housing in force at month end (min 1,500, max 45,000)
create or replace function public.gosi_report(p_run uuid)
returns table(employee_id uuid, is_saudi boolean, new_regime boolean, base numeric, employee_share numeric, employer_share numeric,
              prev_base numeric, status text)
language plpgsql stable security definer set search_path = public as $$
declare r public.payroll_runs; ms date; me date; pms date; pme date; pr uuid;
begin
  select * into r from public.payroll_runs where id = p_run;
  if not found then raise exception 'المسير غير موجود'; end if;
  if not public.has_role(r.company_id, array['owner','admin','hr','finance']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  ms := make_date(r.year, r.month, 1); me := (ms + interval '1 month - 1 day')::date;
  pms := (ms - interval '1 month')::date; pme := ms - 1;
  select id into pr from public.payroll_runs where company_id = r.company_id and year = extract(year from pms)::int and month = extract(month from pms)::int;
  return query
  select l.employee_id, e.is_saudi, public.gosi_is_new(e.gosi_new, e.hire_date),
         public.gosi_base(w.rate_basic, w.rate_housing), l.gosi, l.employer_gosi,
         case when pr is not null and exists(select 1 from public.payroll_lines x where x.run_id = pr and x.employee_id = l.employee_id)
              then (select public.gosi_base(p.rate_basic, p.rate_housing) from public.wage_month(l.employee_id, pms, pme) p) end,
         case when e.end_date between ms and me then 'left'
              when e.hire_date between ms and me or (pr is not null and not exists(select 1 from public.payroll_lines x where x.run_id = pr and x.employee_id = l.employee_id)) then 'new'
              else '' end
    from public.payroll_lines l join public.employees e on e.id = l.employee_id
    cross join lateral (select * from public.wage_month(l.employee_id, ms, me)) w
   where l.run_id = p_run
   order by e.emp_no;
end $$;

create or replace function public.nitaqat_set(p_company uuid, p_bands jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare k text; v numeric; prev numeric := -1;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  foreach k in array array['low','mid','high','plat'] loop
    v := nullif(p_bands->>k, '')::numeric;
    if v is null then continue; end if;
    if v < 0 or v > 100 then raise exception 'نسبة النطاق بين 0 و100'; end if;
    if v <= prev then raise exception 'النسب تتصاعد: الأخضر المنخفض ثم المتوسط ثم المرتفع ثم البلاتيني'; end if;
    prev := v;
  end loop;
  update public.companies set nitaqat = jsonb_strip_nulls(jsonb_build_object('low', nullif(p_bands->>'low', '')::numeric, 'mid', nullif(p_bands->>'mid', '')::numeric,
    'high', nullif(p_bands->>'high', '')::numeric, 'plat', nullif(p_bands->>'plat', '')::numeric)) where id = p_company;
end $$;

-- the organisation chart: everyone, managers only, or HR only
create or replace function public.org_can_see(p_company uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.has_role(p_company, array['owner','admin','hr','finance'])
      or (select org_visibility from public.companies where id = p_company) = 'all' and public.is_member(p_company)
      or (select org_visibility from public.companies where id = p_company) = 'managers'
         and (public.has_role(p_company, array['manager'])
              or exists(select 1 from public.employees x where x.company_id = p_company and x.manager_id = public.my_employee(p_company)))
$$;

create or replace function public.org_chart(p_company uuid)
returns table(id uuid, emp_no text, full_name text, full_name_en text, job_title text, job_title_en text, department_id uuid, manager_id uuid, gender text, hire_date date)
language sql stable security definer set search_path = public as $$
  select e.id, e.emp_no, e.full_name, e.full_name_en, e.job_title, e.job_title_en, e.department_id, e.manager_id, e.gender, e.hire_date
    from public.employees e
   where e.company_id = p_company and public.org_can_see(p_company)
     and (e.end_date is null or e.end_date >= (now() at time zone 'Asia/Riyadh')::date)
   order by e.emp_no
$$;

create or replace function public.org_visibility_set(p_company uuid, p_mode text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  if p_mode not in ('all','managers','hr') then raise exception 'خيار غير معروف'; end if;
  update public.companies set org_visibility = p_mode where id = p_company;
end $$;

revoke all on function public.gosi_report(uuid), public.nitaqat_set(uuid, jsonb), public.org_can_see(uuid), public.org_visibility_set(uuid, text) from public, anon;
grant execute on function public.gosi_report(uuid), public.nitaqat_set(uuid, jsonb), public.org_can_see(uuid), public.org_visibility_set(uuid, text) to authenticated;
notify pgrst, 'reload schema';
