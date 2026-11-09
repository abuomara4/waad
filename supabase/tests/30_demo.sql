-- Waad ERP — demo data seed/clear tests. Reuses the harness (schema t) from 10_test_all.sql.
\set ON_ERROR_STOP 1
set client_min_messages = notice;

insert into auth.users(id, email) values
 ('00000000-0000-0000-0000-0000000d0001','demo-owner@demo'),
 ('00000000-0000-0000-0000-0000000d0002','demo-outsider@demo');
\set d_owner '00000000-0000-0000-0000-0000000d0001'
\set d_out   '00000000-0000-0000-0000-0000000d0002'

-- a fresh, empty company owned by the demo owner
select set_config('request.jwt.claim.sub', :'d_owner', false); set role authenticated;
select public.create_company('منشأة التجربة') as dco \gset
reset role;
-- ensure the projects module is on for this company (an earlier test resets the platform defaults without it)
update public.company_subscriptions set modules = array(select distinct unnest(modules || array['proj'])) where company_id = :'dco';

-- an outsider owns a different company (no access to the demo company)
select set_config('request.jwt.claim.sub', :'d_out', false); set role authenticated;
select public.create_company('منشأة الغريب') as oco \gset
select t.err(format('select public.demo_seed(%L::uuid)', :'dco'), '42501', 'an outsider cannot seed another company');
select t.err(format('select public.demo_clear(%L::uuid)', :'dco'), '42501', 'an outsider cannot clear another company');
reset role;

-- the owner seeds the empty company
select set_config('request.jwt.claim.sub', :'d_owner', false); set role authenticated;
select public.demo_seed(:'dco');
select t.ok((select count(*) from public.employees where company_id = :'dco') = 6, 'demo seed creates the sample employees');
select t.ok((select count(*) from public.departments where company_id = :'dco') = 3, 'demo seed creates the departments');
select t.ok((select count(*) from public.parties where company_id = :'dco') = 4, 'demo seed creates customers and a supplier');
select t.ok((select count(*) from public.items where company_id = :'dco') = 4, 'demo seed creates the items');
select t.ok((select count(*) from public.marketing_campaigns where company_id = :'dco') = 2, 'demo seed creates the campaigns');
select t.ok((select count(*) from public.crm_leads where company_id = :'dco') = 6, 'demo seed creates the CRM pipeline');
select t.ok((select count(*) from public.crm_leads where company_id = :'dco' and stage='won') = 2, 'two sample opportunities are won');
select t.ok((select count(*) from public.crm_leads where company_id = :'dco' and campaign_id is not null) = 4, 'four leads are attributed to a campaign');
select t.ok((select count(*) from public.projects where company_id = :'dco') = 2, 'demo seed creates the projects');
select t.ok((select count(*) from public.project_tasks where company_id = :'dco') = 3, 'demo seed creates project tasks');
select t.ok((select count(*) from public.timesheets where company_id = :'dco') = 6, 'demo seed logs sample hours');
select t.ok((select count(*) from public.employees where company_id = :'dco' and emp_no='1006' and end_date is not null) = 1, 'one sample employee is a leaver (populates turnover)');
-- the numbers the dashboards read actually roll up
select t.ok((select coalesce(sum(value),0) from public.crm_leads where company_id = :'dco' and stage='won') = 66000, 'won revenue rolls up to 66,000');
select t.ok((select round(sum(h.hours),2) from public.timesheets h where h.company_id = :'dco') = 36.50, 'logged hours total 36.5');

-- a second seed is refused
select t.err(format('select public.demo_seed(%L::uuid)', :'dco'), 'مسبقاً', 'a second demo seed is refused');

-- clearing removes everything it created
select public.demo_clear(:'dco');
select t.ok((select count(*) from public.employees where company_id = :'dco') = 0, 'clear removes the employees');
select t.ok((select count(*) from public.marketing_campaigns where company_id = :'dco') = 0, 'clear removes the campaigns');
select t.ok((select count(*) from public.projects where company_id = :'dco') = 0, 'clear removes the projects');
select t.ok((select count(*) from public.timesheets where company_id = :'dco') = 0, 'clear removes the timesheets');
select t.ok((select count(*) from public.demo_seeds where company_id = :'dco') = 0, 'clear removes the demo marker');

-- clearing again is refused (nothing to clear)
select t.err(format('select public.demo_clear(%L::uuid)', :'dco'), 'لا توجد', 'clearing when nothing is seeded is refused');

-- seeding is refused once the company holds real employees
insert into public.employees(company_id, emp_no, full_name, national_id, is_saudi, gender, hire_date, basic)
  values (:'dco','R1','موظف حقيقي للمنشأة','1099887766',true,'m', current_date - 100, 10000);
select t.err(format('select public.demo_seed(%L::uuid)', :'dco'), 'موظفين', 'seeding is refused when the company already has employees');
reset role;

select format('demo: %s passed, %s failed', count(*) filter (where ok), count(*) filter (where not ok)) as demo_summary
  from t.results where name like 'demo%' or name like '%demo%' or name like '%sample%' or name like '%seed%' or name like '%clear%' or name like '%opportun%' or name like '%leaver%' or name like '%campaign%' or name like '%hours%' or name like '%outsider%' or name like '%won revenue%' \gset
\echo :demo_summary
