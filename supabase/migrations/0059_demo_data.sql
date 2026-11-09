-- Waad ERP — 0059 Demo data: fill a fresh/empty company with realistic sample data so testers see a full
-- system (HR, CRM, marketing, projects), and remove it with one click. Owner/admin only. No financial postings
-- are created, so clearing is a plain delete. Seeding is refused on a company that already has employees.

create table if not exists public.demo_seeds (
  company_id uuid primary key references public.companies(id) on delete cascade,
  seeded_at timestamptz not null default now(),
  by_user uuid references auth.users(id) default auth.uid()
);
alter table public.demo_seeds enable row level security;
drop policy if exists demo_read on public.demo_seeds;
create policy demo_read on public.demo_seeds for select using (public.is_member(company_id));
revoke all on public.demo_seeds from anon, authenticated;
grant select on public.demo_seeds to authenticated;

create or replace function public.demo_seed(p_company uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  d_sales uuid; d_ops uuid; d_admin uuid;
  e_gm uuid; e_s1 uuid; e_s2 uuid; e_o1 uuid; e_o2 uuid; e_a1 uuid;
  cu1 uuid; cu2 uuid; cu3 uuid;
  cmp1 uuid; cmp2 uuid;
  pr1 uuid; pr2 uuid; tk1 uuid; tk2 uuid;
  td date := current_date;
begin
  if not public.has_role(p_company, array['owner','admin']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if exists(select 1 from public.demo_seeds where company_id = p_company) then raise exception 'البيانات التجريبية مضافة مسبقاً — يمكنك مسحها أولاً'; end if;
  if exists(select 1 from public.employees where company_id = p_company) then
    raise exception 'البيانات التجريبية تُضاف فقط لمنشأة جديدة بلا موظفين (لحماية بياناتك الحقيقية)';
  end if;

  -- departments
  insert into public.departments(company_id, name, name_en) values (p_company, 'المبيعات والتسويق', 'Sales & Marketing') returning id into d_sales;
  insert into public.departments(company_id, name, name_en) values (p_company, 'العمليات', 'Operations') returning id into d_ops;
  insert into public.departments(company_id, name, name_en) values (p_company, 'الإدارة والمالية', 'Admin & Finance') returning id into d_admin;

  -- employees (varied tenure, nationality, gender; one recent joiner, one leaver this year)
  insert into public.employees(company_id, emp_no, full_name, full_name_en, job_title, job_title_en, department_id, is_saudi, gender, hire_date, basic, housing, transport, national_id)
    values (p_company, '1001', 'عبدالله القحطاني', 'Abdullah Al-Qahtani', 'المدير العام', 'General Manager', d_admin, true, 'm', td - 2400, 32000, 8000, 2000, '1055500011') returning id into e_gm;
  insert into public.employees(company_id, emp_no, full_name, full_name_en, job_title, job_title_en, department_id, manager_id, is_saudi, gender, hire_date, basic, housing, transport, national_id)
    values (p_company, '1002', 'سارة العتيبي', 'Sara Al-Otaibi', 'مديرة المبيعات', 'Sales Manager', d_sales, e_gm, true, 'f', td - 1500, 18000, 4500, 1200, '1055500022') returning id into e_s1;
  insert into public.employees(company_id, emp_no, full_name, full_name_en, job_title, job_title_en, department_id, manager_id, is_saudi, gender, hire_date, basic, housing, transport, national_id)
    values (p_company, '1003', 'محمد الزهراني', 'Mohammed Al-Zahrani', 'أخصائي مبيعات', 'Sales Specialist', d_sales, e_s1, true, 'm', td - 400, 9000, 2250, 800, '1055500033') returning id into e_s2;
  insert into public.employees(company_id, emp_no, full_name, full_name_en, job_title, job_title_en, department_id, manager_id, is_saudi, gender, hire_date, basic, housing, transport, national_id)
    values (p_company, '1004', 'راج كومار', 'Raj Kumar', 'فني عمليات', 'Operations Technician', d_ops, e_gm, false, 'm', td - 1100, 5500, 1375, 500, '2055500044') returning id into e_o1;
  insert into public.employees(company_id, emp_no, full_name, full_name_en, job_title, job_title_en, department_id, manager_id, is_saudi, gender, hire_date, basic, housing, transport, national_id)
    values (p_company, '1005', 'فاطمة الشهري', 'Fatimah Al-Shahri', 'منسقة عمليات', 'Operations Coordinator', d_ops, e_gm, true, 'f', td - 90, 8500, 2125, 700, '1055500055') returning id into e_o2;
  insert into public.employees(company_id, emp_no, full_name, full_name_en, job_title, job_title_en, department_id, manager_id, is_saudi, gender, hire_date, end_date, end_reason, basic, housing, transport, national_id)
    values (p_company, '1006', 'خالد الدوسري', 'Khalid Al-Dosari', 'محاسب', 'Accountant', d_admin, e_gm, true, 'm', td - 800, td - 30, 'resign', 11000, 2750, 900, '1055500066') returning id into e_a1;

  -- customers and suppliers
  insert into public.parties(company_id, kind, name, name_en) values (p_company, 'customer', 'شركة الأفق للتجارة', 'Al-Ufuq Trading Co.') returning id into cu1;
  insert into public.parties(company_id, kind, name, name_en) values (p_company, 'customer', 'مؤسسة النخبة', 'Al-Nukhba Est.') returning id into cu2;
  insert into public.parties(company_id, kind, name, name_en) values (p_company, 'customer', 'مجموعة روابي', 'Rawabi Group') returning id into cu3;
  insert into public.parties(company_id, kind, name, name_en) values (p_company, 'supplier', 'الإمداد الموحّد', 'Unified Supply');

  -- a few items
  insert into public.items(company_id, code, name, name_en, type, sale_price, reorder_level)
    values (p_company, 'SRV-01', 'استشارة تقنية', 'Technical Consulting', 'service', 1500, 0),
           (p_company, 'SRV-02', 'اشتراك سنوي', 'Annual Subscription', 'service', 6000, 0),
           (p_company, 'PRD-01', 'جهاز نقطة بيع', 'POS Terminal', 'stock', 2200, 5),
           (p_company, 'PRD-02', 'طابعة فواتير', 'Receipt Printer', 'stock', 650, 8);

  -- marketing campaigns
  insert into public.marketing_campaigns(company_id, name, channel, budget, spent, status, start_date, goal)
    values (p_company, 'حملة سناب — إطلاق الخدمة', 'social', 20000, 14500, 'active', td - 60, 'جذب عملاء جدد للخدمة الجديدة') returning id into cmp1;
  insert into public.marketing_campaigns(company_id, name, channel, budget, spent, status, start_date, goal)
    values (p_company, 'إعلانات جوجل — بحث', 'google', 12000, 9800, 'active', td - 45, 'استهداف نية الشراء') returning id into cmp2;

  -- CRM pipeline: leads across stages, some attributed to campaigns, some won (owner_id defaults to the caller)
  insert into public.crm_leads(company_id, title, party_id, source, stage, value, campaign_id)
    values (p_company, 'تجهيز فرع جديد', cu1, 'campaign', 'won', 48000, cmp1);
  insert into public.crm_leads(company_id, title, prospect, source, stage, value, campaign_id)
    values (p_company, 'نظام نقاط بيع لثلاثة فروع', 'كافيهات الركن', 'campaign', 'proposal', 36000, cmp1);
  insert into public.crm_leads(company_id, title, party_id, source, stage, value, campaign_id)
    values (p_company, 'اشتراك سنوي موسّع', cu2, 'campaign', 'won', 18000, cmp2);
  insert into public.crm_leads(company_id, title, prospect, source, stage, value, campaign_id)
    values (p_company, 'استشارة تحول رقمي', 'مصنع الديار', 'campaign', 'negotiation', 60000, cmp2);
  insert into public.crm_leads(company_id, title, party_id, source, stage, value)
    values (p_company, 'تجديد عقد الصيانة', cu3, 'referral', 'qualified', 24000);
  insert into public.crm_leads(company_id, title, prospect, source, stage, value, lost_reason)
    values (p_company, 'توريد أجهزة', 'بقالة الحي', 'call', 'lost', 9000, 'السعر أعلى من المنافس');

  -- projects with tasks and logged hours
  insert into public.projects(company_id, name, party_id, billing, hourly_rate, status, start_date)
    values (p_company, 'تطبيق متجر إلكتروني', cu1, 'hourly', 180, 'active', td - 40) returning id into pr1;
  insert into public.projects(company_id, name, party_id, billing, budget, status, start_date)
    values (p_company, 'تدقيق وتهيئة الأنظمة', cu2, 'fixed', 45000, 'active', td - 20) returning id into pr2;

  insert into public.project_tasks(company_id, project_id, title, assignee_id, status) values (p_company, pr1, 'تصميم الواجهات', e_s2, 'done') returning id into tk1;
  insert into public.project_tasks(company_id, project_id, title, assignee_id, status) values (p_company, pr1, 'ربط بوابة الدفع', e_o1, 'doing') returning id into tk2;
  insert into public.project_tasks(company_id, project_id, title, assignee_id, status) values (p_company, pr2, 'جرد الأنظمة الحالية', e_o2, 'todo');

  insert into public.timesheets(company_id, project_id, task_id, employee_id, work_date, hours, billable) values
    (p_company, pr1, tk1, e_s2, td - 10, 6, true), (p_company, pr1, tk1, e_s2, td - 9, 7, true),
    (p_company, pr1, tk2, e_o1, td - 3, 8, true), (p_company, pr1, tk2, e_o1, td - 2, 5.5, true),
    (p_company, pr2, null, e_o2, td - 4, 4, false), (p_company, pr2, null, e_o2, td - 1, 6, true);

  insert into public.demo_seeds(company_id) values (p_company);
end $$;

create or replace function public.demo_clear(p_company uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.has_role(p_company, array['owner','admin']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if not exists(select 1 from public.demo_seeds where company_id = p_company) then raise exception 'لا توجد بيانات تجريبية لهذه المنشأة'; end if;
  -- children first; self and party/campaign references cleared by delete order
  delete from public.timesheets where company_id = p_company;
  delete from public.project_tasks where company_id = p_company;
  delete from public.projects where company_id = p_company;
  delete from public.crm_activities where company_id = p_company;
  delete from public.crm_leads where company_id = p_company;
  delete from public.marketing_campaigns where company_id = p_company;
  delete from public.items where company_id = p_company;
  delete from public.parties where company_id = p_company;
  delete from public.employees where company_id = p_company;   -- manager_id / members.employee_id are ON DELETE SET NULL
  delete from public.departments where company_id = p_company;
  delete from public.demo_seeds where company_id = p_company;
end $$;

revoke all on function public.demo_seed(uuid), public.demo_clear(uuid) from public, anon;
grant execute on function public.demo_seed(uuid), public.demo_clear(uuid) to authenticated;
notify pgrst, 'reload schema';
