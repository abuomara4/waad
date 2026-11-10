-- Waad ERP database tests. Run with: supabase/tests/run.sh
\set ON_ERROR_STOP 1
\set QUIET 1
set client_min_messages = notice;
-- most tests create a company and use it at once: approval of new companies (0068) is tested on its own below
update public.platform_settings set require_approval = false;

-- ---------- test helpers ----------
create schema t;
create table t.results(n serial, name text, ok boolean, detail text);
grant usage on schema t to authenticated, anon;
grant insert, select on t.results to authenticated, anon;
grant usage on sequence t.results_n_seq to authenticated, anon;
create function t.ok(c boolean, name text, detail text default null) returns void language plpgsql as $$
begin
  insert into t.results(name, ok, detail) values (name, coalesce(c,false), detail);
  if coalesce(c,false) then raise notice 'PASS  %', name; else raise exception 'FAIL  % %', name, coalesce(detail,''); end if;
end $$;
create function t.err(q text, pat text, name text) returns void language plpgsql as $$
begin
  begin execute q; exception when others then
    if sqlerrm ~ pat or sqlstate ~ pat then perform t.ok(true, name); return; end if;
    perform t.ok(false, name, 'unexpected error: ' || sqlerrm); return;
  end;
  perform t.ok(false, name, 'no error raised');
end $$;
create function t.eq(a numeric, b numeric, name text) returns void language plpgsql as $$
begin perform t.ok(round(coalesce(a,-999999),2) = round(b,2), name, 'got ' || coalesce(a::text,'null') || ' expected ' || b); end $$;
grant execute on all functions in schema t to authenticated, anon;

-- ---------- users ----------
insert into auth.users(id, email) values
 ('00000000-0000-0000-0000-000000000001','owner@test'),('00000000-0000-0000-0000-000000000002','hr@test'),
 ('00000000-0000-0000-0000-000000000003','fin@test'),('00000000-0000-0000-0000-000000000004','mgr@test'),
 ('00000000-0000-0000-0000-000000000005','emp@test'),('00000000-0000-0000-0000-000000000009','other@test'),
 ('00000000-0000-0000-0000-000000000006','acc@test'),('00000000-0000-0000-0000-000000000007','store@test');
\set u_owner '00000000-0000-0000-0000-000000000001'
\set u_hr '00000000-0000-0000-0000-000000000002'
\set u_fin '00000000-0000-0000-0000-000000000003'
\set u_mgr '00000000-0000-0000-0000-000000000004'
\set u_emp '00000000-0000-0000-0000-000000000005'
\set u_other '00000000-0000-0000-0000-000000000009'
\set u_acc '00000000-0000-0000-0000-000000000006'
\set u_store '00000000-0000-0000-0000-000000000007'

-- ================= TENANCY =================
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select public.create_company('شركة وعد للتجربة', '300000000000003', '1010000000') as cid \gset
select t.ok((select count(*) from public.accounts where company_id = :'cid') = 32, 'chart of accounts seeded (32 accounts)');
select t.ok(public.my_role(:'cid') = 'owner', 'creator is owner');
select t.err($$select public.create_company('منشأة ثانية لنفس الحساب')$$, 'منشأة واحدة', 'one account = one company: the owner cannot create a second company');
insert into public.departments(company_id, name) values (:'cid','الإدارة'),(:'cid','التقنية'),(:'cid','المالية');
insert into public.employees(company_id, emp_no, full_name, national_id, is_saudi, gender, job_title, hire_date, basic, housing, transport)
 values (:'cid','1000','عبدالله الراشد','1021098767',true,'m','المدير العام','2018-01-01',25000,6250,1000) returning id as e_gm \gset
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, manager_id, hire_date, basic, housing, transport)
 values (:'cid','1001','منيرة السالم',true,'f','مديرة الموارد البشرية',:'e_gm','2019-04-10',15000,3750,800) returning id as e_hr \gset
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, manager_id, hire_date, basic, housing, transport)
 values (:'cid','5003','لمى الشهري',true,'f','محاسبة أولى',:'e_gm','2023-08-20',6500,1625,500) returning id as e_fin \gset
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, manager_id, hire_date, basic, housing, transport)
 values (:'cid','5001','خالد الدوسري',true,'m','مدير التقنية',:'e_gm','2020-02-01',12000,3000,800) returning id as e_mgr \gset
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, manager_id, hire_date, basic, housing, transport)
 values (:'cid','5000','محمد العتيبي',true,'m','مطوّر برمجيات',:'e_mgr','2023-03-01',8000,2000,500) returning id as e_emp \gset
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, manager_id, hire_date, basic, housing, transport)
 values (:'cid','5006','راجيش كومار',false,'m','فني صيانة',:'e_mgr','2021-09-10',5000,1250,500) returning id as e_exp \gset
update public.members set employee_id = :'e_gm' where company_id = :'cid' and user_id = :'u_owner';
insert into public.members(company_id, user_id, role, employee_id) values
 (:'cid', :'u_hr', 'hr', :'e_hr'), (:'cid', :'u_fin', 'finance', :'e_fin'), (:'cid', :'u_mgr', 'manager', :'e_mgr'), (:'cid', :'u_emp', 'employee', :'e_emp');
select t.err($$insert into public.employees(company_id, emp_no, full_name, hire_date, basic) values ('$$ || :'cid' || $$','5000','مكرر الرقم','2024-01-01',1000)$$, 'duplicate|unique', 'employee number unique per company');
select t.err($$insert into public.employees(company_id, emp_no, full_name, hire_date, basic, iban) values ('$$ || :'cid' || $$','5100','آيبان خطأ','2024-01-01',1000,'SA12')$$, 'check', 'invalid IBAN rejected');
reset role;

-- other company is fully isolated
select set_config('request.jwt.claim.sub', :'u_other', false); set role authenticated;
select public.create_company('منشأة أخرى') as cid2 \gset
select t.ok((select count(*) from public.employees where company_id = :'cid') = 0, 'other tenant cannot read employees');
select t.ok((select count(*) from public.companies) = 1, 'other tenant sees only its company');
select t.err($$select public.post_manual_journal('$$ || :'cid' || $$', current_date, 'اختراق', '[{"a":"1120","d":1},{"a":"3100","c":1}]')$$, '42501|غير مصرح', 'other tenant cannot post to company');
select t.err($$insert into public.employees(company_id, emp_no, full_name, hire_date, basic) values ('$$ || :'cid' || $$','9999','دخيل على الشركة','2024-01-01',1)$$, 'row-level|42501', 'other tenant cannot insert employees');
reset role;

-- ================= RLS inside the company =================
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.employees) = 1, 'employee sees only own record');
select t.ok((select count(*) from public.journal_entries) = 0, 'employee cannot read ledger');
update public.employees set basic = 99999 where emp_no = '5000';
reset role;
select t.ok((select basic from public.employees where emp_no = '5000' and company_id = :'cid') = 8000, 'salary unchanged after employee attempt');
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select t.ok((select count(*) from public.employees) = 3, 'manager sees self + 2 team members');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok((select count(*) from public.employees) = 6, 'HR sees all employees');
select t.err($$select public.post_sales_invoice('$$ || :'cid' || $$', '{}'::jsonb)$$, '42501|غير مصرح', 'HR cannot post sales invoices');
reset role;

-- ================= APPROVAL WORKFLOW =================
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select public.submit_request(:'cid', 'leave', 'annual', current_date + 40, current_date + 42, null, '{}', 'سفر') as r1 \gset
select t.ok((select route = array['m','p','g'] from public.requests where id = :'r1'), 'leave route = manager → HR → GM');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'leave', 'annual', current_date + 41, current_date + 43)$$, 'تتداخل', 'overlapping leave rejected');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'leave', 'annual', current_date + 100, current_date + 220)$$, 'رصيدك', 'annual balance enforced (accrued, Art. 109)');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'leave', 'maternity', current_date + 60, current_date + 70)$$, 'لا تنطبق', 'gender-specific leave enforced');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'leave', 'exam', current_date + 3, current_date + 4)$$, '15', 'exam leave 15-day notice');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'advance', null, null, null, 9000)$$, 'السلفة', 'advance capped at basic salary');
select t.err($$select public.decide_request('$$ || :'r1' || $$', true)$$, '42501|غير مصرح', 'employee cannot approve own request');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.decide_request('$$ || :'r1' || $$', true)$$, '42501|غير مصرح', 'HR cannot act on manager step');
reset role;
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select t.err($$select public.decide_request('$$ || :'r1' || $$', false, '')$$, 'سبب', 'rejection needs a reason');
select t.ok(public.decide_request(:'r1', true) = 'next:p', 'manager approves → HR');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok(public.decide_request(:'r1', true) = 'next:g', 'HR approves → GM');
reset role;
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select t.ok(public.decide_request(:'r1', true) = 'approved', 'GM final approval');
select t.ok((select count(*) from public.request_actions where request_id = :'r1') = 4, 'full approval trail recorded');
reset role;
select t.err($$update public.request_actions set note = 'x'$$, 'append-only', 'approval trail is immutable');

-- sick-leave year (Art. 117) runs 12 months from the first sick day
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select public.submit_request(:'cid', 'leave', 'sick', current_date + 200, current_date + 289, null, '{"doc_ref":"PSL26000001","files":[{"name":"r.pdf","mime":"application/pdf","data":"JVBERi0xLjQK"}]}', 'تقرير طبي');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'leave', 'sick', current_date + 300, current_date + 340)$$, '120', 'sick leave over 120 days in the sick-year rejected');
select public.submit_request(:'cid', 'leave', 'sick', current_date + 570, current_date + 600, null, '{"doc_ref":"PSL26000002","files":[{"name":"r.pdf","mime":"application/pdf","data":"JVBERi0xLjQK"}]}', 'سنة مرضية جديدة');
select t.ok(true, 'new sick-year starts 12 months after first sick day');
reset role;

-- advance: approved advance posts to the ledger
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'advance', null, null, null, 1000, '{"inst":25}')$$, 'الأقساط', 'advance installments limited to 24');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'advance', null, null, null, 3000, '{"inst":2}')$$, 'م92', 'advance installment above 10% of wage rejected (Art. 92)');
select public.submit_request(:'cid', 'advance', null, null, null, 3000, '{"inst":3}', 'ظرف عائلي') as r2 \gset
reset role;
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated; select public.decide_request(:'r2', true); reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated; select public.decide_request(:'r2', true); reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated; select public.decide_request(:'r2', true); reset role;
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select t.ok(public.decide_request(:'r2', true) = 'approved', 'advance approved through 4 steps');
reset role;
select t.ok(exists(select 1 from public.journal_entries where source = 'advance' and source_id = :'r2'), 'approved advance posted to ledger');

-- ================= GOSI & END OF SERVICE =================
select t.eq(public.gosi_rate(false,'2026-10-31'), 9.75, 'GOSI employee rate, old regime');
select t.eq(public.gosi_rate(true,'2025-07-02'), 9.75, 'GOSI new regime before first step (2025-07-02)');
select t.eq(public.gosi_rate(true,'2026-06-30'), 10.25, 'GOSI new regime Jan–Jun 2026 = 9.5% + 0.75%');
select t.eq(public.gosi_rate(true,'2026-10-31'), 10.75, 'GOSI new regime after 3 July 2026 = 10% + 0.75%');
select t.eq(public.gosi_rate(true,'2030-01-01'), 11.75, 'GOSI new regime capped at 11% + 0.75% from July 2028');
select t.ok(public.gosi_is_new(null,'2025-01-01') and not public.gosi_is_new(false,'2025-01-01'), 'GOSI regime follows registration flag, defaults to hire date');
select t.eq(public.gosi_employee(true, 40000, 10000, false, '2026-10-31'), 4387.50, 'GOSI base capped at 45,000');
select t.eq(public.gosi_employee(true, 1000, 200, false, '2026-10-31'), 146.25, 'GOSI base minimum 1,500');
select t.eq(public.gosi_employee(false, 5000, 1250, false, '2026-10-31'), 0, 'no employee GOSI for non-Saudis');
select t.eq(public.gosi_employer(true, 8000, 2000, false, '2026-10-31'), 1175, 'employer GOSI old regime 11.75%');
select t.eq(public.gosi_employer(true, 8000, 2000, true, '2026-10-31'), 1275, 'employer GOSI new regime 12.75% (Oct 2026)');
select t.eq(public.gosi_employer(false, 5000, 1250, false, '2026-10-31'), 125, 'employer pays 2% hazards for non-Saudis');
select t.eq((select award from public.eos_calc(10000, '2023-01-01', '2025-12-31', 'resign')), round(10000/2.0*(1096/365.0)/3), 'EOS resignation 3 years = 1/3');
select t.eq((select award from public.eos_calc(10000, '2023-01-01', '2024-06-30', 'resign')), 0, 'EOS resignation < 2 years = 0');
select t.eq((select fraction from public.eos_calc(10000, '2015-01-01', '2026-01-01', 'resign')), 1, 'EOS resignation 10+ years = full');
select t.eq((select award from public.eos_calc(10000, '2015-01-01', '2025-12-31', 'employer')), round(10000/2.0*5 + 10000*((4018/365.0)-5)), 'EOS > 5 years: half then full month');
select t.eq((select award from public.eos_calc(10000, '2015-01-01', '2025-12-31', 'art80')), 0, 'EOS Art. 80 = 0');
select t.eq((select leave_pay from public.eos_calc(9000, '2020-01-01', '2025-12-31', 'agree', 10)), 3000, 'EOS unused leave pay');
select t.err($$select * from public.eos_calc(1, '2020-01-01', '2021-01-01', 'unknown')$$, 'غير معروف', 'unknown EOS reason rejected');

-- ================= FINANCE =================
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select public.post_manual_journal(:'cid', current_date - 30, 'رأس المال الافتتاحي', '[{"a":"1120","d":300000},{"a":"3100","c":300000}]') as j_open \gset
select t.err($$select public.post_manual_journal('$$ || :'cid' || $$', current_date, 'غير متوازن', '[{"a":"1120","d":100},{"a":"3100","c":90}]')$$, 'متوازن', 'unbalanced entry rejected');
select t.err($$select public.post_manual_journal('$$ || :'cid' || $$', current_date, 'رئيسي', '[{"a":"1000","d":100},{"a":"3100","c":100}]')$$, 'رئيسي', 'cannot post to header account');
insert into public.parties(company_id, kind, name, vat_no, city) values (:'cid','customer','مؤسسة النخبة التجارية','310000000000003','الرياض') returning id as c1 \gset
insert into public.parties(company_id, kind, name, city) values (:'cid','customer','شركة الأفق للمقاولات','جدة') returning id as c2 \gset
insert into public.parties(company_id, kind, name, vat_no, city) values (:'cid','supplier','مصنع الجودة للمواد','300000000000003','الدمام') returning id as s1 \gset
insert into public.parties(company_id, kind, name) values (:'cid','supplier','شركة الإمداد السريع') returning id as s2 \gset
select t.err($$insert into public.parties(company_id, kind, name, vat_no) values ('$$ || :'cid' || $$','customer','رقم ضريبي خطأ','123')$$, 'check', 'invalid VAT number rejected');
insert into public.items(company_id, code, name, type, unit, sale_price, reorder_level) values (:'cid','P-001','طابعة ليزر','stock','حبة',1200,5) returning id as i1 \gset
insert into public.items(company_id, code, name, type, unit, sale_price, reorder_level) values (:'cid','P-002','حبر طابعة','stock','علبة',150,20) returning id as i2 \gset
insert into public.items(company_id, code, name, type, unit, sale_price) values (:'cid','S-001','خدمة صيانة','service','ساعة',200) returning id as i3 \gset

select public.post_purchase_bill(:'cid', jsonb_build_object('party', :'s1', 'ref','S-7781', 'date', current_date - 20,
  'lines', jsonb_build_array(jsonb_build_object('item', :'i1','qty',10,'price',800), jsonb_build_object('item', :'i2','qty',50,'price',90)))) as b1 \gset
select t.eq((select total from public.purchase_bills where id = :'b1'), 14375, 'purchase bill total incl. 15% VAT');
select t.err($$select public.post_purchase_bill('$$ || :'cid' || $$', '{"party":"$$ || :'s1' || $$","ref":"S-7781","lines":[{"account":"5300","qty":1,"price":10}]}')$$, 'مسجّل', 'duplicate supplier invoice rejected');
select public.post_purchase_bill(:'cid', jsonb_build_object('party', :'s2', 'ref','R-10', 'date', current_date - 18,
  'lines', jsonb_build_array(jsonb_build_object('account','5300','qty',1,'price',10000)))) as b2 \gset
select t.err($$select public.post_purchase_bill('$$ || :'cid' || $$', '{"party":"$$ || :'s2' || $$","lines":[{"account":"1120","qty":1,"price":10}]}')$$, 'غير صالح', 'bill cannot debit bank directly');

select t.err($$select public.post_sales_invoice('$$ || :'cid' || $$', '{"party":"$$ || :'c1' || $$","lines":[{"item":"$$ || :'i1' || $$","qty":11,"price":1200}]}')$$, 'المتوفرة', 'cannot sell more than on hand');
select t.err($$select public.post_sales_invoice('$$ || :'cid' || $$', '{"party":"$$ || :'s1' || $$","lines":[{"item":"$$ || :'i1' || $$","qty":1,"price":1200}]}')$$, 'العميل', 'supplier cannot be invoiced as customer');
select t.err($$select public.post_sales_invoice('$$ || :'cid' || $$', '{"party":"$$ || :'c1' || $$","date":"2099-01-01","lines":[{"item":"$$ || :'i1' || $$","qty":1,"price":1}]}')$$, 'المستقبل', 'future-dated invoice rejected');
select public.post_sales_invoice(:'cid', jsonb_build_object('party', :'c1', 'date', current_date - 10,
  'lines', jsonb_build_array(jsonb_build_object('item', :'i1','qty',3,'price',1200), jsonb_build_object('item', :'i3','qty',5,'price',200)))) as v1 \gset
select public.post_sales_invoice(:'cid', jsonb_build_object('party', :'c2', 'date', current_date - 5,
  'lines', jsonb_build_array(jsonb_build_object('item', :'i2','qty',40,'price',150)))) as v2 \gset
select t.eq((select total from public.sales_invoices where id = :'v1'), 5290, 'sales invoice total (4,600 + 690 VAT)');
select t.eq((select sum(cost) from public.sales_invoice_lines where invoice_id = :'v1'), 2400, 'COGS at average cost (3 × 800)');

select public.record_payment(:'cid', jsonb_build_object('direction','in','party', :'c1','invoice', :'v1','amount',5290,'date', current_date - 3,'account','1120')) as r_in \gset
select t.err($$select public.record_payment('$$ || :'cid' || $$', '{"direction":"in","party":"$$ || :'c1' || $$","invoice":"$$ || :'v1' || $$","amount":1}')$$, 'المتبقي', 'cannot overpay an invoice');
select t.err($$select public.record_payment('$$ || :'cid' || $$', '{"direction":"in","party":"$$ || :'c2' || $$","invoice":"$$ || :'v1' || $$","amount":1}')$$, 'لا يخص', 'payment party must match invoice');
select public.record_payment(:'cid', jsonb_build_object('direction','out','party', :'s1','bill', :'b1','amount',10000,'date', current_date - 2,'account','1120')) as p_out \gset
select t.err($$select public.record_payment('$$ || :'cid' || $$', '{"direction":"out","party":"$$ || :'s2' || $$","amount":99999999,"account":"1110"}')$$, 'الرصيد', 'cannot pay more than cash balance');
select t.err($$select public.void_sales_invoice('$$ || :'v1' || $$', 'خطأ في الفاتورة')$$, 'سداد', 'cannot void a paid invoice');

-- void an unpaid invoice: stock and ledger restored
select public.void_sales_invoice(:'v2', 'إدخال خاطئ');
select t.eq((select sum(qty) from public.stock_moves where item_id = :'i2'), 50, 'void restores stock');
select t.ok((select count(*) from public.journal_entries where source_id = :'v2' and source = 'reversal') = 1, 'void posts a reversing entry');

select public.stock_adjust(:'cid', :'i1', current_date, -1, null, 'جرد دوري');
select t.eq((select sum(qty) from public.stock_moves where item_id = :'i1'), 6, 'stock adjustment shortage');
select t.err($$select public.stock_adjust('$$ || :'cid' || $$', '$$ || :'i1' || $$', current_date, -100, null, 'كبير')$$, 'العجز', 'shortage beyond stock rejected');

-- manual reversal
select public.post_manual_journal(:'cid', current_date, 'إهلاك أكتوبر', '[{"a":"5500","d":300},{"a":"1700","c":300}]') as j_dep \gset
select public.reverse_journal(:'j_dep');
select t.err($$select public.reverse_journal('$$ || :'j_dep' || $$')$$, 'مسبقاً', 'entry reversed only once');
reset role;
select t.err($$update public.journal_lines set debit = debit + 1$$, 'append-only', 'ledger lines are immutable');
select t.err($$delete from public.journal_entries$$, 'append-only', 'ledger entries cannot be deleted');

-- ================= CREDIT NOTES & RETURNS =================
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select id as v1_l1 from public.sales_invoice_lines where invoice_id = :'v1' and item_id = :'i1' \gset
select id as b1_l2 from public.purchase_bill_lines where bill_id = :'b1' and item_id = :'i2' \gset
select sum(qty) as i1_before from public.stock_moves where item_id = :'i1' \gset
select output_vat as ov_before from public.vat_summary(:'cid', current_date - 60, current_date) \gset
select t.err($$select public.post_credit_note('$$ || :'cid' || $$', '{"kind":"sales","doc":"$$ || :'v1' || $$","reason":"مرتجع","lines":[{"line":$$ || :'v1_l1' || $$,"qty":4}]}')$$, 'المتاح', 'cannot return more than invoiced');
select public.post_credit_note(:'cid', jsonb_build_object('kind','sales','doc', :'v1','reason','تلف في الشحن','lines', jsonb_build_array(jsonb_build_object('line', :'v1_l1','qty',1)))) as cn1 \gset
select t.eq((select total from public.credit_notes where id = :'cn1'), 1380, 'credit note total (1,200 + 180 VAT)');
select t.eq((select sum(qty) from public.stock_moves where item_id = :'i1'), :'i1_before'::numeric + 1, 'returned item back in stock');
select t.eq((select value from public.stock_moves where source = 'return' and source_id = :'cn1'), 800, 'returned at original cost');
select t.err($$select public.post_credit_note('$$ || :'cid' || $$', '{"kind":"sales","doc":"$$ || :'v1' || $$","reason":"مرة ثانية","lines":[{"line":$$ || :'v1_l1' || $$,"qty":3}]}')$$, 'المتاح', 'returned qty counted against later notes');
select t.eq((select output_vat from public.vat_summary(:'cid', current_date - 60, current_date)), :'ov_before'::numeric - 180, 'credit note reduces output VAT');
select t.err($$select public.void_sales_invoice('$$ || :'v1' || $$', 'بعد المرتجع')$$, 'سداد', 'credited invoice cannot be voided');
select public.post_credit_note(:'cid', jsonb_build_object('kind','purchase','doc', :'b1','reason','بضاعة معيبة','lines', jsonb_build_array(jsonb_build_object('line', :'b1_l2','qty',5)))) as dn1 \gset
select t.eq((select total from public.credit_notes where id = :'dn1'), 517.5, 'purchase return total (450 + 67.5 VAT)');
select t.eq((select value from public.stock_moves where source = 'return' and source_id = :'dn1'), -450, 'purchase return leaves stock at purchase price');
select t.err($$update public.credit_notes set total = 0$$, 'append-only|permission', 'credit notes are immutable');
reset role;
select set_config('request.jwt.claim.sub', :'u_acc', false); set role authenticated;
reset role;

-- ================= PAYROLL =================
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.payroll_prepare(:'cid', extract(year from current_date)::int, extract(month from current_date)::int, current_date) as run \gset
select t.ok((select count(*) from public.payroll_lines where run_id = :'run') = 6, 'payroll run includes 6 active employees');
select t.eq((select gosi from public.payroll_lines where run_id = :'run' and employee_id = :'e_emp'), 975, 'GOSI 9.75% of (8,000 + 2,000)');
select t.eq((select gosi from public.payroll_lines where run_id = :'run' and employee_id = :'e_exp'), 0, 'no GOSI deduction for non-Saudi');
select t.eq((select employer_gosi from public.payroll_lines where run_id = :'run' and employee_id = :'e_exp'), 125, 'employer hazards GOSI for non-Saudi in payroll');
select t.eq((select employer_gosi from public.payroll_lines where run_id = :'run' and employee_id = :'e_emp'), 1175, 'employer GOSI for Saudi in payroll');
select public.payroll_adjust(:'run', :'e_emp', 10, 500, 200);
select t.eq((select overtime from public.payroll_lines where run_id = :'run' and employee_id = :'e_emp'), round((10500/240.0 + 0.5*8000/240.0)*10, 2), 'overtime (Art. 107) = actual hourly wage + 50% of basic hourly × hours');
select t.eq((select advance from public.payroll_lines where run_id = :'run' and employee_id = :'e_emp'), 1000, 'advance installment (3,000 / 3) deducted in payroll');
select t.eq((select net from public.payroll_lines where run_id = :'run' and employee_id = :'e_emp'), 10500 + round((10500/240.0 + 0.5*8000/240.0)*10, 2) + 500 - 975 - 200 - 1000, 'net pay formula incl. advance installment');
select public.payroll_prepare(:'cid', extract(year from current_date)::int, extract(month from current_date)::int, current_date);
select t.eq((select advance from public.payroll_lines where run_id = :'run' and employee_id = :'e_emp'), 1000, 'recalculating payroll does not deduct the installment twice');
select t.eq((select amount from public.requests where id = :'r2') - (select sum(amount) from public.advance_deductions where request_id = :'r2'), 2000, 'advance balance after first installment');
select t.err($$select public.payroll_approve('$$ || :'run' || $$')$$, '42501|غير مصرح', 'HR cannot approve its own payroll');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.payroll_lines) = 0, 'employee cannot see draft payroll');
reset role;
insert into public.cost_centers(company_id, code, name) values (:'cid','PAYCC','الإدارة العامة') returning id as cc_pay \gset
update public.employees set cost_center_id = :'cc_pay' where id = :'e_gm';
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select public.payroll_approve(:'run') as run_je \gset
reset role;
select t.eq((select sum(debit) from public.journal_lines where entry_id = :'run_je' and account_code = '5200' and cost_center_id = :'cc_pay'),
  (select gross + arrears + overtime + bonus - absence - att_absence - late_deduction - sick_deduction - damages from public.payroll_lines where run_id = :'run' and employee_id = :'e_gm'), 'payroll salary expense carries the employee cost center');
select t.eq((select sum(debit) from public.journal_lines where entry_id = :'run_je' and account_code = '5210' and cost_center_id = :'cc_pay'),
  (select employer_gosi from public.payroll_lines where run_id = :'run' and employee_id = :'e_gm'), 'employer GOSI expense carries the employee cost center');
select t.eq((select sum(debit) from public.journal_lines where entry_id = :'run_je' and account_code = '5200'),
  (select sum(gross + arrears + overtime + bonus - absence - att_absence - late_deduction - sick_deduction - damages) from public.payroll_lines where run_id = :'run'), 'total salary expense unchanged by the split');
update public.employees set cost_center_id = null where id = :'e_gm';
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.payroll_adjust('$$ || :'run' || $$', '$$ || :'e_emp' || $$', 1, 0, 0)$$, 'معتمد', 'approved payroll is locked');
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.eq((select sum(l.debit) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id where e.source = 'payroll' and l.account_code = '5210'), (select sum(employer_gosi) from public.payroll_lines where run_id = :'run'), 'employer GOSI share posted to expense');
select t.eq((select l.credit from public.journal_lines l join public.journal_entries e on e.id = l.entry_id where e.source = 'payroll' and l.account_code = '1500'), 1000, 'advance installment credited to employee advances');
select public.payroll_mark_paid(:'run');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.payroll_lines) = 1, 'employee sees only own approved payslip');
reset role;

-- ================= REPORTS =================
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.ok((select sum(debit) = sum(credit) from public.trial_balance(:'cid', current_date)), 'trial balance balances');
select t.ok((select abs(coalesce(sum(amount) filter (where section = 'asset'),0) - coalesce(sum(amount) filter (where section in ('liab','equity')),0)) < 0.01
             from public.balance_sheet(:'cid', current_date)), 'balance sheet: assets = liabilities + equity');
select t.eq((select amount from public.balance_sheet(:'cid', current_date) where code = '1300'), 4800 + 800 + 4500 - 450, 'inventory value after returns (7 printers + 45 toner at cost)');
select t.eq((select output_vat from public.vat_summary(:'cid', current_date - 60, current_date)), 690 - 180, 'output VAT excludes void invoice and credit note');
select t.eq((select input_vat from public.vat_summary(:'cid', current_date - 60, current_date)), 1875 + 1500 - 67.5, 'input VAT net of purchase return');
select t.eq((select amount from public.income_statement(:'cid', current_date - 60, current_date) where code = '4100'), 3600 - 1200, 'sales revenue after void and credit note');
select t.eq((select balance from (select balance, row_number() over () rn from public.account_ledger(:'cid', '1120', current_date - 60, current_date)) x order by rn desc limit 1),
            (select debit - credit from public.trial_balance(:'cid', current_date) where code = '1120'), 'bank ledger closing = trial balance');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select * from public.trial_balance('$$ || :'cid' || $$', current_date)$$, '42501|غير مصرح', 'HR cannot read financial reports');
reset role;

-- ================= FINANCE SUB-ROLES =================
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
insert into public.members(company_id, user_id, role) values (:'cid', :'u_acc', 'accountant'), (:'cid', :'u_store', 'storekeeper');
select t.err($$insert into public.members(company_id, user_id, role) values ('$$ || :'cid' || $$', '$$ || :'u_other' || $$', 'owner')$$, 'row-level', 'finance manager cannot create owners');
select t.err($$update public.members set role = 'admin' where user_id = '$$ || :'u_acc' || $$'$$, 'row-level', 'finance manager cannot promote an accountant to admin');
select t.ok((select count(*) from public.journal_entries where source = 'payroll') >= 1, 'finance manager sees payroll entries');
reset role;
select set_config('request.jwt.claim.sub', :'u_acc', false); set role authenticated;
select public.post_sales_invoice(:'cid', jsonb_build_object('party', :'c1', 'lines', jsonb_build_array(jsonb_build_object('item', :'i3','qty',1,'price',200)))) as v3 \gset
select t.ok(:'v3' is not null, 'accountant can issue sales invoices');
select t.ok((select count(*) from public.journal_entries where source in ('payroll','payroll_pay','advance')) = 0, 'accountant cannot see salary/advance entries');
select t.ok((select count(*) from public.journal_lines l where l.account_code = '5200') = 0, 'accountant cannot see salary expense lines');
select t.ok((select count(*) from public.journal_entries where source = 'sales') >= 1, 'accountant sees sales entries');
select t.err($$select * from public.trial_balance('$$ || :'cid' || $$', current_date)$$, 'غير مصرح', 'accountant cannot read trial balance by default');
select t.err($$select public.void_sales_invoice('$$ || :'v3' || $$', 'تجربة إلغاء')$$, 'غير مصرح', 'accountant cannot void invoices by default');
select t.err($$select public.post_credit_note('$$ || :'cid' || $$', '{"kind":"sales","doc":"$$ || :'v3' || $$","reason":"تجربة","lines":[]}')$$, 'غير مصرح', 'accountant cannot issue credit notes by default');
select t.err($$select public.post_manual_journal('$$ || :'cid' || $$', current_date, 'قيد محاسب', '[{"a":"5500","d":1},{"a":"1120","c":1}]')$$, 'غير مصرح', 'accountant cannot post manual journals by default');
select t.err($$select public.set_finance_permission('$$ || :'cid' || $$', 'accountant', 'reports', true)$$, 'غير مصرح', 'accountant cannot grant itself permissions');
reset role;
select set_config('request.jwt.claim.sub', :'u_store', false); set role authenticated;
select public.stock_adjust(:'cid', :'i2', current_date, 2, 90, 'جرد — زيادة');
select t.ok(true, 'storekeeper can adjust stock');
select t.ok((select count(*) from public.sales_invoices) = 0, 'storekeeper cannot see sales invoices');
select t.ok((select count(*) from public.parties) = 0, 'storekeeper cannot see customers or suppliers');
select t.ok((select count(*) from public.items) = 3, 'storekeeper sees items');
select t.err($$select public.post_sales_invoice('$$ || :'cid' || $$', '{}'::jsonb)$$, 'غير مصرح', 'storekeeper cannot sell');
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select public.set_finance_permission(:'cid', 'accountant', 'reports', true);
select t.err($$select public.set_finance_permission('$$ || :'cid' || $$', 'finance', 'reports', false)$$, 'ثابتة', 'finance manager permissions are fixed');
reset role;
select set_config('request.jwt.claim.sub', :'u_acc', false); set role authenticated;
select t.ok((select count(*) from public.trial_balance(:'cid', current_date)) > 0, 'granted permission takes effect immediately');
reset role;

-- ================= PRIVILEGE ESCALATION =================
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select public.post_journal('$$ || :'cid' || $$', current_date, 'x', 'manual', null, '[{"a":"1120","d":1},{"a":"3100","c":1}]')$$, 'permission denied', 'internal post_journal not callable from the browser');
select t.err($$insert into public.members(company_id, user_id, role) values ('$$ || :'cid' || $$', '$$ || :'u_other' || $$', 'owner')$$, 'row-level', 'employee cannot add members');
update public.members set role = 'owner' where user_id = :'u_emp';
reset role;
select t.ok((select role from public.members where user_id = :'u_emp' and company_id = :'cid') = 'employee', 'employee cannot promote own role');
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.err($$insert into public.journal_entries(company_id, no, date, memo, source) values ('$$ || :'cid' || $$', 'X-1', current_date, 'مباشر', 'manual')$$, 'permission denied', 'ledger not writable directly, only via RPC');
reset role;

select set_config('request.jwt.claim.sub', '', false); set role anon;
select t.err($$select count(*) from public.employees$$, 'permission denied', 'anonymous visitors cannot read employees');
select t.err($$select public.create_company('هجوم مجهول')$$, 'permission denied', 'anonymous visitors cannot call RPCs');
reset role;

-- ================= CUSTODY =================
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
insert into public.custody(company_id, employee_id, item, serial, value, issued) values (:'cid', :'e_emp', 'حاسب محمول Dell', 'DL-1', 4200, current_date - 100);
select t.err($$insert into public.custody(company_id, employee_id, item, serial, value, issued) values ('$$ || :'cid' || $$', '$$ || :'e_mgr' || $$', 'جهاز آخر', 'DL-1', 1, current_date)$$, 'duplicate|unique', 'same serial cannot be issued twice while open');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.custody) = 1, 'employee sees own custody');
select t.err($$insert into public.custody(company_id, employee_id, item, issued) values ('$$ || :'cid' || $$', '$$ || :'e_emp' || $$', 'عهدة ذاتية', current_date)$$, 'row-level', 'employee cannot record custody');
reset role;
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select t.ok((select count(*) from public.custody) = 0, 'other staff cannot see custody records');
reset role;

-- ================= AGING =================
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.eq((select net from public.aging(:'cid', 'sales', current_date) where party_id = :'c1'), 230 - 1380, 'AR aging nets customer credit against open invoice');
select t.eq((select unallocated from public.aging(:'cid', 'sales', current_date) where party_id = :'c1'), 1380, 'credit balance shown as unallocated');
select t.eq((select sum(d1_30) from public.aging(:'cid', 'purchase', current_date)), 14375 - 10000 - 517.5 + 11500, 'AP aging: overdue 1–30 days bucket');
reset role;
select set_config('request.jwt.claim.sub', :'u_store', false); set role authenticated;
select t.err($$select * from public.aging('$$ || :'cid' || $$', 'sales', current_date)$$, 'غير مصرح', 'storekeeper cannot read receivables');
reset role;

-- ================= INVITES =================
insert into auth.users(id, email) values ('00000000-0000-0000-0000-000000000010','new.hire@test.sa');
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select t.err($$select public.invite_member('$$ || :'cid' || $$', 'x@test.sa', 'employee')$$, 'غير مصرح', 'a manager cannot invite');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.invite_member('$$ || :'cid' || $$', 'x@test.sa', 'hr')$$, 'غير مصرح', 'HR cannot appoint another HR (the owner does)');
select t.err($$select public.invite_member('$$ || :'cid' || $$', 'x@test.sa', 'admin')$$, 'غير مصرح', 'HR cannot appoint a system admin');
select t.err($$select public.invite_member('$$ || :'cid' || $$', 'not-an-email', 'employee')$$, 'البريد', 'invalid email rejected');
select t.err($$select public.invite_member('$$ || :'cid' || $$', 'x@test.sa', 'employee', '$$ || :'e_emp' || $$')$$, 'مربوط', 'cannot invite onto an already-linked employee record');
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, manager_id, hire_date, basic, housing, transport)
 values (:'cid','5100','ريم القحطاني',true,'f','أخصائية',:'e_mgr','2026-01-05',7000,1750,500) returning id as e_new \gset
select public.invite_member(:'cid', '  New.Hire@Test.SA ', 'employee', :'e_new') as inv \gset
select t.ok((select email from public.invites where id = :'inv') = 'new.hire@test.sa', 'invite email normalised to lower case');
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.err($$select public.invite_member('$$ || :'cid' || $$', 'y@test.sa', 'hr')$$, 'غير مصرح', 'finance manager cannot grant HR role');
select t.ok(public.invite_member(:'cid', 'acc2@test.sa', 'accountant') is not null, 'finance manager can invite an accountant');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000010', false);
select set_config('request.jwt.claims', '{"email":"new.hire@test.sa"}', false); set role authenticated;
select t.ok((select count(*) from public.my_companies()) = 0, 'before accepting, the new user belongs to no company');
select t.err($$select public.accept_invite('WRONG123')$$, 'غير صحيح', 'wrong invite code rejected');
reset role; select code as inv_code from public.invites where id = :'inv' \gset
set role authenticated;
select t.ok(public.accept_invite(lower(:'inv_code')) = :'cid', 'accept_invite joins the inviting company (code case-insensitive)');
select t.ok(public.my_role(:'cid') = 'employee' and public.my_employee(:'cid') = :'e_new', 'joined with the invited role and employee record');
select t.err($$select public.accept_invite('$$ || :'inv_code' || $$')$$, 'غير صحيح', 'invite code is single-use');
select t.ok((select count(*) from public.employees) = 1, 'new employee sees only her own record');
select t.ok(public.submit_request(:'cid', 'permit', null, current_date, current_date, null, '{"hours":2}') is not null, 'new employee can submit a request');
reset role;
select set_config('request.jwt.claims', '', false);
select set_config('request.jwt.claim.sub', :'u_other', false); set role authenticated;
select t.ok((select count(*) from public.invites) = 0, 'outsiders cannot read invites');
select t.err($$select public.accept_invite('$$ || :'inv_code' || $$')$$, 'سجّل الدخول', 'no email claim → cannot accept');
select set_config('request.jwt.claims', '{"email":"other@test"}', false);
select t.err($$select public.accept_invite((select code from public.invites limit 1))$$, 'غير صحيح', 'a code only works for the invited email');
select set_config('request.jwt.claims', '', false);
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.revoke_invite('$$ || :'inv' || $$')$$, 'مقبولة', 'accepted invite cannot be revoked');
select t.err($$insert into public.invites(company_id, email, role) values ('$$ || :'cid' || $$', 'z@test.sa', 'admin')$$, 'permission denied|42501', 'invites are written only through RPCs');
reset role;

-- ================= MEMBERSHIP GUARD =================
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
insert into public.members(company_id, user_id, role) values (:'cid', :'u_other', 'admin');
reset role;
select set_config('request.jwt.claim.sub', :'u_other', false); set role authenticated;
select t.err($$update public.members set role = 'employee' where user_id = '$$ || :'u_owner' || $$'$$, 'فقط المالك', 'admin cannot demote the owner');
select t.err($$delete from public.members where user_id = '$$ || :'u_owner' || $$'$$, 'فقط المالك', 'admin cannot remove the owner');
select t.err($$update public.members set role = 'owner' where user_id = '$$ || :'u_other' || $$' and company_id = '$$ || :'cid' || $$'$$, 'فقط المالك', 'admin cannot promote self to owner');
reset role;
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select t.err($$delete from public.members where user_id = '$$ || :'u_owner' || $$'$$, 'مالك واحد', 'company keeps at least one owner');
delete from public.members where company_id = :'cid' and user_id = :'u_other';
select t.ok(not exists(select 1 from public.members where company_id = :'cid' and user_id = :'u_other'), 'owner can remove an admin');
reset role;

-- ================= STAFF LOGIN BY EMPLOYEE NUMBER =================
select code as ccode from public.companies where id = :'cid' \gset
select t.ok(:'ccode' ~ '^[A-Z0-9]{6}$', 'company gets a short login code');
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, manager_id, hire_date, basic, housing, transport)
 values (:'cid','7001','فهد المطيري',true,'m',:'e_mgr','2026-02-01',6000,1500,500) returning id as e_staff \gset
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, hire_date, basic)
 values (:'cid','٧٠٠٢','رقم عربي',true,'m','2026-02-01',5000) returning id as e_badno \gset
select public.staff_email(:'cid', :'e_staff') as staff_mail \gset
select t.ok(:'staff_mail' = '7001.' || lower(:'ccode') || '@staff.waad.app', 'staff login address = empno.code@staff.waad.app');
select t.err($$select public.link_staff_login('$$ || :'cid' || $$', '$$ || :'e_staff' || $$')$$, 'لم يُنشأ', 'cannot link before the account exists');
select t.err($$select public.link_staff_login('$$ || :'cid' || $$', '$$ || :'e_badno' || $$')$$, 'حروف إنجليزية', 'non-latin employee number rejected for login');
reset role;
insert into auth.users(id, email, encrypted_password) values ('00000000-0000-0000-0000-000000000020', :'staff_mail', crypt('Temp#12345', gen_salt('bf')));
insert into auth.users(id, email) values ('00000000-0000-0000-0000-000000000021', 'attacker@test');
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select t.err($$select public.link_staff_login('$$ || :'cid' || $$', '$$ || :'e_staff' || $$')$$, 'غير مصرح', 'a manager cannot create staff logins');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.link_staff_login('$$ || :'cid' || $$', '$$ || :'e_staff' || $$', 'hr')$$, 'غير مصرح', 'HR cannot make another HR via staff login');
select public.link_staff_login(:'cid', :'e_staff', 'employee');
select t.err($$select public.link_staff_login('$$ || :'cid' || $$', '$$ || :'e_staff' || $$')$$, 'مسبقاً', 'cannot link the same employee twice');
select t.ok((select by_number and must_change_password from public.staff_logins(:'cid') where employee_id = :'e_staff'), 'staff login listed, flagged to change password');
select t.err($$select public.reset_staff_password('$$ || :'cid' || $$', '$$ || :'e_staff' || $$', 'short')$$, '8 أحرف', 'reset requires 8+ chars');
select public.reset_staff_password(:'cid', :'e_staff', 'NewTemp#999');
reset role;
select t.ok((select encrypted_password = crypt('NewTemp#999', encrypted_password) from auth.users where id = '00000000-0000-0000-0000-000000000020'), 'HR reset sets a bcrypt password');
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.reset_staff_password('$$ || :'cid' || $$', '$$ || :'e_emp' || $$', 'Whatever#123')$$, 'يدخل ببريده', 'cannot reset passwords of email-based accounts');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000020', false); set role authenticated;
select t.ok((select role = 'employee' and must_change_password and code = :'ccode' from public.my_companies()), 'staff member sees company, role and must-change flag');
select public.password_changed();
select t.ok(not (select must_change_password from public.my_companies()), 'flag cleared after changing password');
select t.err($$select public.reset_staff_password('$$ || :'cid' || $$', '$$ || :'e_staff' || $$', 'Hacker#1234')$$, 'غير مصرح|غيّر', 'staff cannot reset passwords');
reset role;
select set_config('request.jwt.claim.sub', :'u_other', false); set role authenticated;
select t.ok(public.staff_email(:'cid', :'e_staff') is null, 'outsiders cannot derive staff login addresses');
reset role;

-- ================= COMPANY CODE + DATA-CHANGE REQUESTS =================
set role anon;
select t.ok(public.company_by_code(lower(:'ccode')) = 'شركة وعد للتجربة', 'anonymous visitor resolves company name from its code');
select t.ok(public.company_by_code('NOPE00') is null, 'unknown company code → nothing');
select t.err($$select * from public.employees$$, 'permission denied', 'company code alone exposes no data');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000020', false); set role authenticated;
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'update', null, null, null, null, '{"basic":"99999"}')$$, 'لا يمكن طلب تعديل', 'employee cannot request salary change via data update');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'update', null, null, null, null, '{"iban":"SA12"}')$$, 'الآيبان', 'invalid IBAN in update request rejected');
select public.submit_request(:'cid', 'update', null, null, null, null, '{"phone":"0551234567","iban":"SA0380000000608010167519"}', 'رقم جديد') as upd \gset
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'update', null, null, null, null, '{"phone":"0550000000"}')$$, 'قيد المراجعة', 'only one pending data-update request at a time');
update public.employees set phone = '0599999999' where id = :'e_staff';
reset role;
select t.ok((select phone is distinct from '0599999999' from public.employees where id = :'e_staff'), 'employee cannot edit own record directly');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000020', false); set role authenticated;
select t.ok((select route = array['p'] from public.requests where id = :'upd'), 'data-update request goes to HR');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.decide_request(:'upd', true, null);
select t.ok((select phone = '0551234567' and iban = 'SA0380000000608010167519' from public.employees where id = :'e_staff'), 'HR approval applies the requested changes');
reset role;

-- ================= LABOR LAW (M/51 as amended by M/44 1446) =================
select t.err($$update public.employees set probation_end = hire_date + 200 where emp_no = '5000'$$, 'probation_check', 'probation cannot exceed 180 days (Art. 53)');
select t.ok(public.eos_fraction('probation', 3) = 0, 'no end-of-service award when ending during probation (Art. 54)');
select t.eq(public.annual_leave_accrued('2020-01-01', '2020-12-30'), 21, 'one year of service accrues 21 days (Art. 109)');
select t.eq(public.annual_leave_accrued('2020-01-01', '2026-01-01'), round(1826*21/365.0 + (2193-1826)*30/365.0, 2), 'after 5 continuous years accrual is 30 days/yr (Art. 109)');
select t.eq((select s.days from public.sick_deduction(null, '2025-01-01', '2025-01-31', 300) s), 0, 'sick deduction with no sick leave = 0');
reset role;
insert into public.requests(company_id, employee_id, kind, sub, from_date, to_date, days, route, step, status)
 values (:'cid', :'e_emp', 'leave', 'sick', '2025-01-01', '2025-04-30', 120, '{}', 0, 'approved'),
        (:'cid', :'e_emp', 'leave', 'unpaid', '2024-06-01', '2024-06-30', 30, '{}', 0, 'approved');
select t.ok((select s.days = 1 and s.amount = 75 from public.sick_deduction(:'e_emp', '2025-01-01', '2025-01-31', 300) s), 'sick day 31 paid at 75% (Art. 117)');
select t.ok((select s.days = 28 and s.amount = 28 * 75 from public.sick_deduction(:'e_emp', '2025-02-01', '2025-02-28', 300) s), 'sick days 32–59 deducted 25% each');
select t.ok((select s.days = 30 and s.amount = 30 * 300 from public.sick_deduction(:'e_emp', '2025-04-01', '2025-04-30', 300) s), 'sick days 91–120 unpaid (Art. 117)');
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'leave', 'marriage', current_date + 5, current_date + 9)$$, 'تاريخ الواقعة', 'marriage leave needs the event date (Art. 113)');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'leave', 'marriage', current_date + 6, current_date + 10, null, jsonb_build_object('event_date', current_date + 5))$$, 'م113', 'marriage leave counted from the event date');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'leave', 'birth', current_date + 6, current_date + 8, null, jsonb_build_object('event_date', current_date - 2))$$, '7 أيام', 'paternity leave within 7 days of birth (Art. 113)');
select t.ok(public.submit_request(:'cid', 'leave', 'birth', current_date + 1, current_date + 3, null, jsonb_build_object('event_date', current_date - 1) || '{"files":[{"name":"r.pdf","mime":"application/pdf","data":"JVBERi0xLjQK"}]}'::jsonb) is not null, 'paternity leave within the 7-day window accepted');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'resign', null, null, current_date + 30)$$, 'مؤجل', 'resignation cannot carry a deferred date (Art. 79-bis)');
select public.submit_request(:'cid', 'resign', null, null, null, null, '{}', 'ظروف خاصة') as rsg \gset
select t.ok((select from_date = current_date and to_date is null from public.requests where id = :'rsg'), 'resignation dated on submission, ends on acceptance');
reset role; update public.requests set created_at = now() - interval '8 days' where id = :'rsg';
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select public.cancel_request('$$ || :'rsg' || $$')$$, '7 أيام', 'resignation withdrawal only within 7 days (Art. 79-bis)');
reset role; update public.requests set created_at = now() - interval '31 days' where id = :'rsg';
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select t.ok(public.apply_deemed_resignations(:'cid') = 0, 'only HR/admin/owner can apply deemed acceptance');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok(public.apply_deemed_resignations(:'cid') = 1, 'resignation unanswered 30 days is deemed accepted (Art. 79-bis)');
select t.ok((select end_date = (now() - interval '31 days')::date + 30 from public.employees where id = :'e_emp'), 'employment ends on the deemed-acceptance date');
reset role; update public.employees set end_date = null, end_reason = null where id = :'e_emp';
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select * from public.eos_for_employee(:'e_emp', current_date, 'resign') \gset eos_
select t.ok(:eos_excluded_days = 10, 'unpaid leave beyond 20 days excluded from service (Art. 116)');
select * from public.eos_for_employee(:'e_emp', current_date, 'noreason') \gset nr_
select t.eq(:nr_compensation, greatest(10500 / 30.0 * 15 * :nr_years, 21000), 'unjustified termination compensation = max(15 days/yr, 2 months) (Art. 77)');
select t.ok(:nr_fraction = 1 and :nr_award > 0 and :nr_leave_days >= 0, 'full award + leave balance pay on unjustified termination');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select * from public.eos_for_employee('$$ || :'e_emp' || $$', current_date, 'resign')$$, 'غير مصرح', 'employees cannot run EOS settlements');
select t.ok((select balance is not null from public.annual_leave_balance(:'e_emp')), 'employee can read own leave balance');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.payroll_prepare(:'cid', 2025, 2, '2025-02-27') as feb \gset
select t.ok((select sick_days = 28 and sick_deduction > 0 and net = gross + overtime + bonus - gosi - absence - sick_deduction - deductions - damages - advance from public.payroll_lines where run_id = :'feb' and employee_id = :'e_emp'), 'payroll deducts sick-pay tiers');
select t.err($$select public.payroll_set_line('$$ || :'feb' || $$', '$$ || :'e_emp' || $$', 0, 0, 2000, 0)$$, 'م70', 'fines capped at 5 days wage per month (Art. 70)');
select t.err($$select public.payroll_set_line('$$ || :'feb' || $$', '$$ || :'e_emp' || $$', 0, 0, 0, 2000)$$, 'م91', 'damages capped at 5 days wage per month (Art. 91)');
select public.payroll_set_line(:'feb', :'e_emp', 0, 0, 1000, 1000);
select t.ok((select deductions = 1000 and damages = 1000 from public.payroll_lines where run_id = :'feb' and employee_id = :'e_emp'), 'fines and damages within limits accepted');
reset role;

-- ================= TALENT: REVIEWS, RECRUITMENT, TRAINING, IMPORT =================
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select t.err($$select public.start_review_cycle('$$ || :'cid' || $$', 'تقييم 2026', '2026-01-01', '2026-12-31')$$, 'غير مصرح', 'only HR starts a review cycle');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.start_review_cycle(:'cid', 'تقييم 2026', '2026-01-01', '2026-12-31') as cyc \gset
select t.ok((select count(*) from public.reviews where cycle_id = :'cyc') = (select count(*) from public.employees where company_id = :'cid' and hire_date <= '2026-12-31' and (end_date is null or end_date >= '2026-12-31')), 'cycle creates one review per active employee');
select id as rv_emp from public.reviews where cycle_id = :'cyc' and employee_id = :'e_emp' \gset
select id as rv_exp from public.reviews where cycle_id = :'cyc' and employee_id = :'e_exp' \gset
select t.ok((select reviewer_id = :'e_mgr' from public.reviews where id = :'rv_emp'), 'direct manager is the reviewer');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.reviews where id = :'rv_emp') = 0, 'employee cannot see own review before approval');
select t.err($$select public.save_review('$$ || :'rv_emp' || $$', '[]', null, null, null, false)$$, 'نفسك', 'employee cannot fill own review');
select t.err($$insert into public.reviews(company_id, cycle_id, employee_id) values ('$$ || :'cid' || $$', '$$ || :'cyc' || $$', '$$ || :'e_emp' || $$')$$, 'permission|42501', 'reviews cannot be written directly');
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.err($$select public.save_review('$$ || :'rv_emp' || $$', '[]', null, null, null, false)$$, 'غير مصرح', 'non-reviewer cannot fill a review');
reset role;
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select t.ok((select count(*) from public.reviews where cycle_id = :'cyc') > 0 and (select bool_and(reviewer_id = :'e_mgr') from public.reviews where cycle_id = :'cyc'), 'manager sees only reviews of direct reports');
select t.err($$select public.save_review('$$ || :'rv_emp' || $$', '[{"t":"تسليم المشروع","w":60,"s":4},{"t":"جودة الكود","w":30,"s":5}]', null, null, null, true)$$, '100', 'weights must total 100% to submit');
select t.err($$select public.save_review('$$ || :'rv_emp' || $$', '[{"t":"تسليم المشروع","w":60,"s":7},{"t":"جودة الكود","w":40,"s":5}]', null, null, null, false)$$, 'من 1 إلى 5', 'scores are 1 to 5');
select public.save_review(:'rv_emp', '[{"t":"تسليم المشروع","w":60,"s":4},{"t":"جودة الكود","w":40,"s":5}]', 'سرعة التعلم', 'التوثيق', 'أداء جيد', false);
select t.ok((select status = 'draft' and overall = 4.4 from public.reviews where id = :'rv_emp'), 'draft saved with weighted score 4.4');
select public.save_review(:'rv_emp', '[{"t":"تسليم المشروع","w":60,"s":4},{"t":"جودة الكود","w":40,"s":5}]', 'سرعة التعلم', 'التوثيق', 'أداء جيد', true);
select t.ok((select status = 'submitted' from public.reviews where id = :'rv_emp'), 'manager submits review');
select t.err($$select public.save_review('$$ || :'rv_emp' || $$', '[]', null, null, null, false)$$, 'أُرسل', 'submitted review is locked for the reviewer');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.decide_review('$$ || :'rv_emp' || $$', false, '')$$, 'سبب', 'returning a review needs a reason');
select public.decide_review(:'rv_emp', true, 'معتمد');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.reviews where id = :'rv_emp') = 1, 'employee sees review after approval');
select public.acknowledge_review(:'rv_emp', 'شكراً');
select t.ok((select ack_at is not null and employee_comment = 'شكراً' from public.reviews where id = :'rv_emp'), 'employee acknowledges with a comment');
select t.err($$select public.acknowledge_review('$$ || :'rv_emp' || $$')$$, 'سبق', 'acknowledgement only once');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.close_review_cycle(:'cyc');
select t.err($$select public.save_review('$$ || :'rv_exp' || $$', '[]', null, null, null, false)$$, 'مغلقة', 'closed cycle cannot be edited');

insert into public.job_openings(company_id, title, department_id, positions) values (:'cid', 'محاسب', (select id from public.departments where company_id = :'cid' and name = 'المالية'), 1) returning id as jo \gset
insert into public.candidates(company_id, opening_id, full_name, national_id, is_saudi, gender, phone) values (:'cid', :'jo', 'سلمان القحطاني', '1012345678', true, 'm', '0551112222') returning id as cand \gset
select t.err($$update public.candidates set stage = 'hired' where id = '$$ || :'cand' || $$'$$, 'تعيين', 'hired stage only through hire_candidate');
update public.candidates set stage = 'interview', rating = 4 where id = :'cand';
select t.err($$select public.hire_candidate('$$ || :'cand' || $$', '{"emp_no":"5000","basic":7000}')$$, 'مستخدم', 'hiring rejects a used employee number');
select public.hire_candidate(:'cand', '{"emp_no":"6001","basic":7000,"housing":1750,"hire_date":"2026-11-01"}') as hired_emp \gset
select t.ok((select full_name = 'سلمان القحطاني' and job_title = 'محاسب' and national_id = '1012345678' and basic = 7000 from public.employees where id = :'hired_emp'), 'hiring creates the employee record from the candidate');
select t.ok((select stage = 'hired' and employee_id = :'hired_emp' from public.candidates where id = :'cand') and (select status = 'closed' from public.job_openings where id = :'jo'), 'candidate marked hired and the filled opening closes');
select t.err($$update public.candidates set stage = 'rejected' where id = '$$ || :'cand' || $$'$$, 'عُيّن', 'a hired candidate is final');
insert into public.trainings(company_id, title, start_date, end_date, hours, cost) values (:'cid', 'السلامة المهنية', '2026-10-01', '2026-10-02', 12, 1500) returning id as trn \gset
insert into public.training_attendees(training_id, employee_id, company_id, status, cert_expiry) values (:'trn', :'e_emp', :'cid', 'completed', '2028-10-01'), (:'trn', :'e_exp', :'cid', 'enrolled', null);
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.candidates) = 0 and (select count(*) from public.job_openings) = 0, 'employees cannot see recruitment data');
select t.err($$insert into public.job_openings(company_id, title) values ('$$ || :'cid' || $$', 'وظيفة')$$, 'row-level|42501', 'employees cannot create job openings');
select t.ok((select count(*) from public.training_attendees) = 1 and (select count(*) from public.trainings) = 1, 'employee sees only own training records');
select t.err($$select public.import_employees('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"7100","full_name":"موظف دخيل","hire_date":"2026-01-01","basic":"1"}]')$$, 'غير مصرح', 'only HR imports employees');
reset role;
select set_config('request.jwt.claim.sub', :'u_other', false); set role authenticated;
select t.err($$insert into public.candidates(company_id, opening_id, full_name) values ('$$ || :'cid2' || $$', '$$ || :'jo' || $$', 'مرشح دخيل')$$, 'row-level|42501', 'cannot attach a candidate to another company opening');
select t.err($$insert into public.training_attendees(training_id, employee_id, company_id) values ('$$ || :'trn' || $$', '$$ || :'e_emp' || $$', '$$ || :'cid2' || $$')$$, 'row-level|42501', 'cannot enrol another company employee');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.import_employees('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"7101","full_name":"موظف مستورد","hire_date":"2026-01-01","basic":"5000"},{"_row":3,"emp_no":"7101","full_name":"موظف مكرر","hire_date":"2026-01-01","basic":"5000"}]')$$, 'السطر 3', 'import names the row of a duplicate number');
select t.ok((select count(*) from public.employees where company_id = :'cid' and emp_no = '7101') = 0, 'a failed import changes nothing');
select t.err($$select public.import_employees('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"7101","full_name":"موظف مستورد","national_id":"123","hire_date":"2026-01-01","basic":"5000"}]')$$, 'السطر 2.*الهوية', 'import validates the national ID');
select t.err($$select public.import_employees('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"7101","full_name":"موظف مستورد","hire_date":"2026-01-01","basic":"5000","manager_emp_no":"9999"}]')$$, 'غير موجود', 'import rejects an unknown manager');
select public.import_employees(:'cid', '[{"_row":2,"emp_no":"7102","full_name":"نوف المطيري","gender":"f","is_saudi":"true","hire_date":"2026-02-01","basic":"6000","housing":"1500","department":"المبيعات","manager_emp_no":"7103"},{"_row":3,"emp_no":"7103","full_name":"فهد السبيعي","hire_date":"2025-05-01","basic":"9000","department":"المبيعات","manager_emp_no":"1000"}]') as nimp \gset
select t.ok(:nimp = 2 and (select m.emp_no = '7103' and d.name = 'المبيعات' and e.gender = 'f' and e.housing = 1500 from public.employees e join public.employees m on m.id = e.manager_id join public.departments d on d.id = e.department_id where e.company_id = :'cid' and e.emp_no = '7102'), 'import creates employees, departments and manager links');
reset role;

-- ================= ATTENDANCE =================
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.att_settings('$$ || :'cid' || $$', true, '2026-09-01', true, false)$$, 'وردية افتراضية', 'attendance needs a default shift first');
insert into public.shifts(company_id, name, start_time, end_time, grace_min, is_default) values (:'cid', 'الدوام الرسمي', '08:00', '16:00', 15, true) returning id as sh_day \gset
insert into public.shifts(company_id, name, start_time, end_time, grace_min, work_days) values (:'cid', 'الوردية الليلية', '22:00', '06:00', 15, '{0,1,2,3,4,5,6}') returning id as sh_night \gset
update public.employees set shift_id = :'sh_night' where id = :'e_mgr';
insert into public.work_sites(company_id, name, lat, lng, radius_m) values (:'cid', 'المكتب الرئيسي', 24.713600, 46.675300, 200);
select public.att_settings(:'cid', true, '2026-09-01', true, false);
insert into public.holidays(company_id, day, name) values (:'cid', '2026-09-14', 'إجازة تجريبية'), (:'cid', '2026-09-23', 'اليوم الوطني');
reset role;
insert into public.requests(company_id, employee_id, kind, sub, from_date, to_date, days, status) values (:'cid', :'e_emp', 'leave', 'annual', '2026-09-16', '2026-09-16', 1, 'approved');
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select public.clock('$$ || :'cid' || $$')$$, 'خدمة الموقع', 'check-in needs the phone location');
select t.err($$select public.clock('$$ || :'cid' || $$', 24.80, 46.70, 20)$$, 'خارج نطاق', 'check-in outside every work site is refused');
select t.err($$select public.clock('$$ || :'cid' || $$', 24.7137, 46.6754, 500)$$, 'دقة', 'check-in with a poor GPS fix is refused');
select t.ok((public.clock(:'cid', 24.7137, 46.6754, 20))->>'action' = 'in', 'check-in inside the site geofence');
select t.err($$select public.clock('$$ || :'cid' || $$', 24.7137, 46.6754, 20)$$, 'قبل لحظات', 'a double tap does not check out');
select t.err($$insert into public.attendance(company_id, employee_id, day, check_in) values ('$$ || :'cid' || $$', '$$ || :'e_emp' || $$', '2026-09-01', now())$$, '42501|permission|row-level', 'employees cannot write attendance directly');
select t.err($$select public.att_set('$$ || :'cid' || $$', '$$ || :'e_emp' || $$', '2026-09-15', '08:00', '16:00', 'تعديل ذاتي')$$, '42501|غير مصرح', 'employees cannot correct their own attendance');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.att_set('$$ || :'cid' || $$', '$$ || :'e_emp' || $$', '2026-09-13', '08:40', '17:30', '')$$, 'سبب التعديل', 'an HR correction needs a reason');
select public.att_set(:'cid', :'e_emp', '2026-09-13', '08:40', '17:30', 'نسي تسجيل الحضور');
select id as a13 from public.attendance where employee_id = :'e_emp' and day = '2026-09-13' \gset
select t.ok((select late_min = 40 and early_min = 0 and worked_min = 530 and extra_min = 90 from public.attendance where id = :'a13'), 'late beyond the grace period counts from the shift start; time after the shift is extra');
select public.att_set(:'cid', :'e_emp', '2026-09-17', '08:10', '15:30', 'تصحيح');
select t.ok((select late_min = 0 and early_min = 30 from public.attendance where employee_id = :'e_emp' and day = '2026-09-17'), 'arrival within the grace period is not late; early leave recorded');
select public.att_set(:'cid', :'e_emp', '2026-09-18', '09:00', '13:00', 'عمل يوم الجمعة');
select t.ok((select late_min = 0 and extra_min = 240 from public.attendance where employee_id = :'e_emp' and day = '2026-09-18'), 'all time worked on a day off is extra');
select public.att_set(:'cid', :'e_mgr', '2026-09-13', '22:30', '06:10', 'وردية ليلية');
select t.ok((select late_min = 30 and worked_min = 460 and extra_min = 10 from public.attendance where employee_id = :'e_mgr' and day = '2026-09-13'), 'night shift ends the next morning');
select t.err($$select public.att_approve_ot('$$ || :'a13' || $$', 200)$$, 'بين 0 و90', 'approved overtime cannot exceed the extra time');
select public.att_approve_ot(:'a13', 60);
select t.ok((select string_agg(status, ',' order by day) from public.att_sheet(:'cid', '2026-09-13', '2026-09-19', :'e_emp')) = 'late,holiday,absent,leave,present,present,off', 'daily sheet: late, holiday, absent, leave, present, day off');
reset role;
select t.ok((select absent_days = 1 and late_min = 40 and ot_min = 60 from public.att_month(:'e_emp', '2026-09-13', '2026-09-19')), 'monthly totals: absent days, late minutes, approved overtime');
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.att_settings(:'cid', true, '2026-09-01', true, true);
select public.payroll_prepare(:'cid', 2026, 9, '2026-09-27') as sep \gset
reset role;
select absent_days as sep_abs from public.att_month(:'e_emp', '2026-09-01', '2026-09-30') \gset
select t.ok(:sep_abs = 17, 'September: 22 workdays − 2 attended − 2 holidays − 1 leave = 17 absent', 'got ' || :sep_abs);
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok((select att_absent_days = 17 and att_absence = round(10500 / 30.0 * 17, 2) and late_min = 40 and late_deduction = round(10500 / 30.0 / 8 / 60 * 40, 2) and att_ot_hours = 1
               and overtime = round((10500/240.0 + 0.5*8000/240.0) * 1, 2)
               and net = gross + overtime + bonus - gosi - absence - att_absence - late_deduction - sick_deduction - deductions - damages - advance
             from public.payroll_lines where run_id = :'sep' and employee_id = :'e_emp'), 'payroll takes absence, lateness and approved overtime from attendance');
reset role;
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select t.ok((select bool_and(e.id = :'e_mgr' or e.manager_id = :'e_mgr') and bool_or(e.id = :'e_emp') and bool_or(e.id = :'e_mgr') from (select distinct employee_id from public.att_sheet(:'cid', '2026-09-13', '2026-09-19')) x join public.employees e on e.id = x.employee_id) and (select count(*) from public.attendance where employee_id = :'e_emp') >= 3, 'a manager sees own and direct reports attendance');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(distinct employee_id) from public.att_sheet(:'cid', '2026-09-13', '2026-09-19')) = 1 and (select count(*) from public.attendance where employee_id <> :'e_emp') = 0, 'an employee sees only own attendance');
reset role;
select set_config('request.jwt.claim.sub', :'u_other', false); set role authenticated;
select t.err($$insert into public.employees(company_id, emp_no, full_name, hire_date, basic, shift_id) values ('$$ || :'cid2' || $$', '9901', 'موظف آخر', '2026-01-01', 5000, '$$ || :'sh_day' || $$')$$, 'الوردية غير موجودة', 'cannot assign another company shift');
select t.ok((select count(*) from public.attendance) = 0 and (select count(*) from public.work_sites) = 0, 'another company sees no attendance');
select t.err($$select public.att_sheet('$$ || :'cid' || $$', '2026-09-01', '2026-09-30')$$, '42501|غير مصرح', 'another company cannot read the daily sheet');
reset role;

-- ================= WHATSAPP REMINDER CONTACTS =================
update public.employees set phone = '0551234567' where id = :'e_mgr';
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select public.submit_request(:'cid', 'permit', null, current_date + 1, current_date + 1, null, '{"hours": 2}', 'تذكير') as rq_wa \gset
select t.ok((select string_agg(full_name || ':' || coalesce(phone, '') || ':' || step, ',') from public.request_waiting_on(:'rq_wa')) = 'خالد الدوسري:0551234567:m', 'requester sees who the request waits on (direct manager) with the mobile');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok((select count(*) from public.request_waiting_on(:'rq_wa')) = 1, 'HR can look up who a request waits on');
reset role;
select set_config('request.jwt.claim.sub', :'u_other', false); set role authenticated;
select t.err($$select * from public.request_waiting_on('$$ || :'rq_wa' || $$')$$, '42501|غير مصرح', 'outsiders cannot see approver contacts');
reset role;
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select public.decide_request(:'rq_wa', true, null);
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select status from public.requests where id = :'rq_wa') = 'approved' or exists(select 1 from public.request_waiting_on(:'rq_wa') where step = 'p' and employee_id = :'e_hr'), 'after the manager, the reminder goes to the HR members');
reset role;

-- ================= HOLIDAYS INSIDE LEAVE AND PROBATION (Reg. Arts. 19, 24) =================
insert into public.holidays(company_id, day, name) values (:'cid', '2027-10-12', 'عطلة تجريبية'), (:'cid', '2027-02-10', 'عطلة تجريبية');
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select public.submit_request(:'cid', 'leave', 'annual', '2027-10-10', '2027-10-14', null, '{}', 'إجازة') as rq_hol \gset
select t.ok((select days from public.requests where id = :'rq_hol') = 4, 'a holiday inside annual leave is not counted (Reg. Art. 24/2)');
reset role;
update public.employees set probation_end = hire_date + 179 where id = :'hired_emp';
insert into public.requests(company_id, employee_id, kind, sub, from_date, to_date, days, status) values (:'cid', :'hired_emp', 'leave', 'sick', '2027-01-01', '2027-03-01', 60, 'approved');
select t.eq((select amount from public.sick_deduction(:'hired_emp', '2027-01-01', '2027-03-01', 100)), 29 * 25, 'a holiday inside sick leave is paid in full (Reg. Art. 24/3)');
select t.eq((select days from public.sick_deduction(:'hired_emp', '2027-03-01', '2027-03-01', 100)), 1, 'the holiday still counts toward the sick-leave days (day 60 is in the 3/4 band)');
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok(public.probation_effective_end(:'hired_emp') = (select probation_end + 60 from public.employees where id = :'hired_emp'), 'probation is extended by sick days and holidays inside it (Reg. Art. 19/2)', public.probation_effective_end(:'hired_emp')::text);
select t.ok((select effective_end = public.probation_effective_end(:'hired_emp') from public.probation_ends(:'cid') where employee_id = :'hired_emp'), 'HR lists effective probation ends');
reset role;
select set_config('request.jwt.claim.sub', :'u_other', false); set role authenticated;
select t.err($$select public.probation_effective_end('$$ || :'hired_emp' || $$')$$, '42501|غير مصرح', 'outsiders cannot read probation dates');
reset role;

-- ================= DOCUMENTS AND CONTRACTS (Arts. 37, 55, 75) =================
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
insert into public.employee_documents(company_id, employee_id, doc_type, doc_no, expiry_date) values
  (:'cid', :'e_exp', 'iqama', '2000000007', current_date + 20), (:'cid', :'e_exp', 'passport', 'P123', current_date - 5), (:'cid', :'e_emp', 'national_id', '1000000002', current_date + 400);
select t.err($$insert into public.employee_documents(company_id, employee_id, doc_type) values ('$$ || :'cid' || $$', '$$ || :'e_emp' || $$', 'other')$$, 'check|23514', 'an "other" document needs a title');
select t.err($$select public.contract_add('$$ || :'cid' || $$', '$$ || :'e_exp' || $$', 'indefinite', '2024-01-01', null)$$, 'م37', 'a non-Saudi contract must be fixed-term (Art. 37)');
select public.contract_add(:'cid', :'e_exp', 'fixed', current_date - 300, null) as c_exp \gset
select t.ok((select end_date = start_date + interval '1 year' - interval '1 day' from public.contracts where id = :'c_exp'), 'a non-Saudi contract without a term runs one year (Art. 37)');
select t.err($$select public.contract_add('$$ || :'cid' || $$', '$$ || :'e_emp' || $$', 'fixed', '2023-03-01', null)$$, 'نهاية العقد', 'a Saudi fixed-term contract needs an end date');
select public.contract_add(:'cid', :'e_emp', 'fixed', current_date - 1000, current_date + 30, true, true) as c_emp \gset
select public.contract_renew(:'c_emp', current_date + 400) as c_emp2 \gset
select t.ok((select status from public.contracts where id = :'c_emp') = 'renewed' and (select renewal_no = 1 and start_date = current_date + 31 and first_start = current_date - 1000 from public.contracts where id = :'c_emp2'), 'renewal continues from the day after the old term');
select t.err($$select public.contract_renew('$$ || :'c_emp' || $$', current_date + 900)$$, 'الساري', 'only the active contract can be renewed');
select t.ok((select count(*) from public.doc_alerts(:'cid', 90) where employee_id = :'e_exp' and kind = 'doc') = 2
       and (select level from public.doc_alerts(:'cid', 90) where employee_id = :'e_exp' and label = 'passport') = 'expired'
       and (select level from public.doc_alerts(:'cid', 90) where employee_id = :'e_exp' and label = 'iqama') = 'd30', 'expiring and expired documents flagged by urgency');
select t.ok(exists(select 1 from public.doc_alerts(:'cid', 90) where employee_id = :'e_exp' and kind = 'missing' and label = 'work_permit')
       and exists(select 1 from public.doc_alerts(:'cid', 90) where employee_id = :'e_gm' and kind = 'missing' and label = 'contract'), 'missing work permit (non-Saudi) and missing contracts are flagged');
select t.ok(not exists(select 1 from public.doc_alerts(:'cid', 90) where employee_id = :'e_emp' and kind = 'contract'), 'a renewed contract no longer alerts');
select public.contract_renew(:'c_emp2', current_date + 800) as c_emp3 \gset
select public.contract_renew(:'c_emp3', current_date + 900) as c_emp4 \gset
reset role;
update public.contracts set start_date = current_date + 80, end_date = current_date + 85 where id = :'c_emp3';
update public.contracts set start_date = current_date + 86, end_date = current_date + 88 where id = :'c_emp4';
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok((select note from public.doc_alerts(:'cid', 90) where ref_id = :'c_emp4') like 'م55/2%', 'after 3 renewals the alert warns it turns indefinite (Art. 55/2)');
select public.contract_make_indefinite(:'c_emp4', null) as c_emp5 \gset
select t.ok((select contract_type = 'indefinite' and end_date is null and first_start = current_date - 1000 from public.contracts where id = :'c_emp5'), 'contract converted to indefinite keeps the service start');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.employee_documents) = 1 and (select count(*) from public.contracts where employee_id <> :'e_emp') = 0, 'an employee sees only own documents and contracts');
select t.err($$select * from public.doc_alerts('$$ || :'cid' || $$')$$, '42501|غير مصرح', 'employees cannot list company alerts');
select t.err($$insert into public.employee_documents(company_id, employee_id, doc_type, doc_no) values ('$$ || :'cid' || $$', '$$ || :'e_emp' || $$', 'passport', 'X')$$, 'row-level|42501', 'employees cannot add documents');
reset role;
select set_config('request.jwt.claim.sub', :'u_other', false); set role authenticated;
select t.err($$insert into public.employee_documents(company_id, employee_id, doc_type, doc_no) values ('$$ || :'cid2' || $$', '$$ || :'e_emp' || $$', 'passport', 'X')$$, 'غير موجود|row-level', 'cannot attach a document to another company employee');
reset role;

-- ================= LETTERS: SALARY CERTIFICATE AND SERVICE CERTIFICATE (Art. 64) =================
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select (public.issue_letter(:'e_emp', 'salary', 'ar', 'بنك الرياض')).id as l1 \gset
select t.ok((select ref_no like 'LTR-%' and with_salary and (data->'wage'->>'gross')::numeric = (data->'wage'->>'basic')::numeric + (data->'wage'->>'housing')::numeric + (data->'wage'->>'transport')::numeric
             and data->'employee'->>'nationality' = 'سعودي' and data->'company'->>'name' is not null from public.letters where id = :'l1'), 'HR issues a numbered salary certificate with a data snapshot');
select t.ok((select coalesce(jsonb_typeof(data->'wage'), 'null') = 'null' and not with_salary from public.issue_letter(:'e_emp', 'salary', 'en', null, false)), 'salary can be left out of the letter');
select t.err($$select public.issue_letter('$$ || :'e_emp' || $$', 'service')$$, 'م64', 'service certificate needs an end of service (Art. 64)');
reset role;
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, hire_date, end_date, end_reason, basic, housing)
 values (:'cid', '5090', 'سارة القحطاني', true, 'f', 'محاسبة', '2020-02-01', current_date - 3, 'فصل م80', 9000, 2250) returning id as e_left \gset
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select (public.issue_letter(:'e_left', 'service', 'ar', null, false)).id as l2 \gset
select t.ok((select kind = 'service' and with_salary and (data->'wage'->>'gross')::numeric = 11250 and (data->'employee'->>'end_date')::date = current_date - 3
             and data::text not like '%فصل%' from public.letters where id = :'l2'), 'service certificate states dates, job and last wage, and nothing about the end reason (Art. 64)');
select t.err($$select public.issue_letter('$$ || :'e_left' || $$', 'salary')$$, 'شهادة خدمة', 'no salary certificate for someone who left');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select public.issue_letter('$$ || :'e_emp' || $$', 'salary')$$, 'اعتماد طلب', 'an employee needs an approved request to print a letter');
select public.submit_request(:'cid', 'cert', null, null, null) as rq_cert \gset
select t.err($$select public.issue_letter('$$ || :'e_emp' || $$', 'salary', 'ar', null, true, null, '$$ || :'rq_cert' || $$')$$, 'اعتماد طلب', 'a pending request is not enough');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.decide_request(:'rq_cert', true, null);
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select request_id = :'rq_cert' from public.issue_letter(:'e_emp', 'salary', 'ar', null, true, null, :'rq_cert')), 'employee prints own salary certificate after approval');
select t.err($$select public.issue_letter('$$ || :'e_emp' || $$', 'salary', 'ar', null, true, null, '$$ || :'rq_cert' || $$')$$, 'صدر خطاب', 'one letter per request and language');
select t.err($$select public.issue_letter('$$ || :'e_mgr' || $$', 'salary', 'ar', null, true, null, '$$ || :'rq_cert' || $$')$$, '42501|غير مصرح|غير موجود', 'an employee cannot issue a letter for someone else');
select t.ok((select count(*) from public.letters) = 3 and not exists(select 1 from public.letters where employee_id <> :'e_emp'), 'an employee sees only own letters');
select t.err($$update public.letters set data = '{}'$$, 'permission|42501', 'issued letters cannot be edited');
reset role;
select set_config('request.jwt.claim.sub', :'u_other', false); set role authenticated;
select t.err($$select public.issue_letter('$$ || :'e_emp' || $$', 'salary')$$, '42501|غير مصرح', 'another company cannot issue letters for our employees');
select t.ok((select count(*) from public.letters) = 0, 'another company sees no letters');
reset role;

-- ================= COMPANY LOGO =================
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
update public.companies set logo = 'data:image/png;base64,iVBORw0KGgo=' where id = :'cid';
select t.ok((select logo like 'data:image/png;base64,%' from public.companies where id = :'cid'), 'owner sets the company logo');
select t.err($$update public.companies set logo = 'data:image/svg+xml;base64,PHN2Zz4=' where id = '$$ || :'cid' || $$'$$, 'check', 'only raster logos (no SVG) are accepted');
select t.err($$update public.companies set logo = 'data:image/png;base64,' || repeat('A', 200000) where id = '$$ || :'cid' || $$'$$, 'check', 'logo size is capped');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
update public.companies set logo = null where id = :'cid';
select t.ok((select logo is not null from public.companies where id = :'cid'), 'HR cannot change the logo (owner/admin only)');
reset role;

-- ================= PERMITS EXCUSE LATENESS AND EARLY LEAVE =================
insert into public.requests(company_id, employee_id, kind, from_date, to_date, payload, route) values (:'cid', :'e_emp', 'permit', '2026-09-13', '2026-09-13', '{"hours":0.5}', '{m,p}') returning id as pm1 \gset
select t.ok((select late_min = 40 and permit_min = 0 from public.attendance where employee_id = :'e_emp' and day = '2026-09-13'), 'a pending permit excuses nothing');
update public.requests set status = 'approved' where id = :'pm1';
select t.ok((select late_min = 10 and permit_min = 30 from public.attendance where employee_id = :'e_emp' and day = '2026-09-13'), 'an approved half-hour permit covers 30 late minutes');
insert into public.requests(company_id, employee_id, kind, from_date, to_date, payload, route, status) values (:'cid', :'e_emp', 'permit', '2026-09-17', '2026-09-17', '{"hours":1}', '{m,p}', 'pending') returning id as pm2 \gset
update public.requests set status = 'approved' where id = :'pm2';
select t.ok((select late_min = 0 and early_min = 0 and permit_min = 30 from public.attendance where employee_id = :'e_emp' and day = '2026-09-17'), 'a permit covers early leave, only the minutes actually used');
select t.ok((select permit_min = 30 and status = 'late' from public.att_sheet(:'cid', '2026-09-13', '2026-09-13', :'e_emp')), 'the sheet reports the minutes a permit covered');
update public.requests set status = 'cancelled' where id = :'pm1';
select t.ok((select late_min = 40 and permit_min = 0 from public.attendance where employee_id = :'e_emp' and day = '2026-09-13'), 'cancelling the permit brings the lateness back');

-- ================= VIOLATIONS AND PENALTIES (Arts. 66–73, model regulation tables) =================
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok((select count(*) from public.violation_types) = 50, 'the model regulation tables are loaded (16 + 18 + 16 violations)');
select t.err($$select public.pen_open('$$ || :'cid' || $$', '$$ || :'e_emp' || $$', 'T01', current_date - 40, current_date - 31, 'تأخر')$$, 'م69', 'no accusation more than 30 days after discovery (Art. 69)');
select t.err($$select public.pen_open('$$ || :'cid' || $$', '$$ || :'e_emp' || $$', 'X99', current_date, current_date, '')$$, 'م67', 'only violations in the regulation table (Art. 67)');
select public.pen_open(:'cid', :'e_emp', 'T01', current_date - 5, current_date - 3, 'تأخر 10 دقائق') as pn1 \gset
select t.ok((select step = 1 and action = 'W' and fine = 0 and daily_wage = 350 from public.penalties where id = :'pn1'), 'first lateness ≤ 15 min: written warning');
select t.err($$select public.pen_decide('$$ || :'pn1' || $$', true, current_date, null)$$, 'م71', 'no penalty before written notice, questioning and defence (Art. 71)');
select public.pen_open(:'cid', :'e_emp', 'O08', current_date - 2, current_date - 2, 'تمزيق إعلان') as pn_o8 \gset
select t.err($$select public.pen_investigate('$$ || :'pn_o8' || $$', 'oral', 'سُئل شفهياً', current_date)$$, 'م71', 'oral questioning only for a warning or a fine up to one day (Art. 71)');
select public.pen_investigate(:'pn1', 'oral', 'أقر بالتأخر بسبب الزحام', current_date - 2);
select public.pen_decide(:'pn1', true, current_date - 2, 'إنذار كتابي');
select t.ok((select status = 'applied' and notified_on = current_date - 2 from public.penalties where id = :'pn1'), 'penalty applied and notified in writing (Art. 72)');
select public.pen_open(:'cid', :'e_emp', 'T01', current_date - 1, current_date - 1, 'تأخر ثانٍ') as pn2 \gset
select t.ok((select step = 2 and action = 'p5' and fine = 17.5 from public.penalties where id = :'pn2'), 'a repeat within 180 days moves to the next step: 5% of a day (Art. 68)');
select t.err($$select public.pen_decide('$$ || :'pn2' || $$', false, null, '')$$, 'سبب الحفظ', 'dropping a case needs a reason');
select public.pen_decide(:'pn_o8', false, null, 'لم تثبت المخالفة');
reset role;
insert into public.penalties(company_id, employee_id, code, occurred_on, discovered_on, step, action, fine, status, notified_on)
values (:'cid', :'e_mgr', 'C01', current_date - 210, current_date - 210, 3, 'd3', 0, 'applied', current_date - 200);
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok((select step = 1 from public.pen_preview(:'e_mgr', 'C01', current_date)), 'after 180 days from the last notification the steps start over (Art. 68)');
select t.ok((select step = 4 and action = 'd5' from public.pen_preview(:'e_mgr', 'C01', current_date - 50)), 'within 180 days the next step applies');
reset role;
update public.companies set penalty_base = 'basic' where id = :'cid';
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok((select daily_wage = 266.67 and fine = 533.34 from public.pen_preview(:'e_emp', 'O08', current_date)), 'fines can be based on the basic wage instead of the actual wage');
reset role;
update public.companies set penalty_base = 'gross' where id = :'cid';
-- employee side
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.penalties) = 3, 'the employee sees own cases');
select t.err($$select public.pen_open('$$ || :'cid' || $$', '$$ || :'e_emp' || $$', 'T01', current_date, current_date, '')$$, '42501|غير مصرح', 'employees cannot open cases');
select public.pen_defend(:'pn2', 'كان عندي موعد في المستشفى');
select t.ok((select emp_defense like 'كان عندي%' from public.penalties where id = :'pn2'), 'the employee replies in writing to an open case');
select public.pen_grieve(:'pn1', 'الزحام خارج عن إرادتي');
select t.err($$select public.pen_grieve('$$ || :'pn1' || $$', 'مرة ثانية')$$, 'قُدّم تظلم', 'one grievance per penalty');
select t.err($$select public.pen_grievance_decide('$$ || :'pn1' || $$', true, 'قبول')$$, '42501|غير مصرح', 'the employee cannot decide own grievance');
select t.err($$update public.penalties set fine = 0$$, 'permission|42501', 'cases cannot be edited directly');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.pen_grievance_decide(:'pn1', true, 'قُبل التظلم');
select t.ok((select status = 'overturned' and griev_result = 'overturned' from public.penalties where id = :'pn1'), 'an accepted grievance cancels the penalty');
reset role;
update public.penalties set notified_on = current_date - 60 where id = :'pn1';
insert into public.holidays(company_id, day, name) values (:'cid', '2030-01-10', 'عطلة اختبار');
select t.ok(public.pen_grievance_deadline(:'cid', '2030-01-01') = '2030-02-01' and public.pen_grievance_deadline(:'cid2', '2030-01-01') = '2030-01-31', 'the grievance window is 30 days excluding public holidays (Art. 72)');
-- payroll: Art. 70 cap and carry-over, Art. 73 fines account
insert into public.penalties(company_id, employee_id, code, occurred_on, discovered_on, step, action, daily_wage, fine, status, notified_on, created_at) values
 (:'cid', :'e_emp', 'C16', '2026-12-01', '2026-12-01', 4, 'd5', 350, 1750, 'applied', '2026-12-02', now() - interval '2 minutes'),
 (:'cid', :'e_emp', 'C01', '2026-12-03', '2026-12-03', 2, 'd2', 350, 700, 'applied', '2026-12-04', now() - interval '1 minute');
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.payroll_prepare(:'cid', 2026, 12, '2026-12-27') as dec26 \gset
select t.ok((select penalty_fine = 1750 from public.payroll_lines where run_id = :'dec26' and employee_id = :'e_emp'), 'fines deducted in a month never exceed five days'' wage (Art. 70)');
reset role;
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select public.payroll_approve(:'dec26') as dec_je \gset
select t.ok((select credit from public.journal_lines where entry_id = :'dec_je' and account_code = '2450') >= 1750, 'fines go to the workers'' fines account, not income (Art. 73)');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.payroll_prepare(:'cid', 2027, 1, '2027-01-27') as jan27 \gset
select t.ok((select penalty_fine = 700 from public.payroll_lines where run_id = :'jan27' and employee_id = :'e_emp'), 'the rest of the fines carries to the next month');
reset role;

-- ================= RESIGNATION DEFERRAL, COMPENSATORY LEAVE, EXAM LEAVE (Arts. 79-bis, 107, 115) =================
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select public.submit_request(:'cid', 'resign', null, null, null, null, '{}', 'فرصة أخرى') as rs2 \gset
reset role; update public.requests set created_at = now() - interval '30 days' where id = :'rs2';
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.resign_defer('$$ || :'rs2' || $$', 30, 'تسليم مشروع العميل')$$, 'الثلاثين', 'deferral must be notified before the 30 days run out (Art. 79-bis)');
reset role; update public.requests set created_at = now() - interval '10 days' where id = :'rs2';
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.resign_defer('$$ || :'rs2' || $$', 61, 'تسليم مشروع العميل')$$, '60', 'deferral at most 60 days');
select t.err($$select public.resign_defer('$$ || :'rs2' || $$', 30, 'x')$$, 'سبب', 'deferral needs a written reason');
select t.ok(public.resign_defer(:'rs2', 45, 'تسليم مشروع العميل') = (now() at time zone 'Asia/Riyadh')::date + 45, 'deferral counts from the notice date');
select t.err($$select public.resign_defer('$$ || :'rs2' || $$', 10, 'تمديد آخر للتأجيل')$$, 'سبق', 'only one deferral');
reset role; update public.requests set created_at = now() - interval '35 days' where id = :'rs2';
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok(public.apply_deemed_resignations(:'cid') = 0, 'a deferred resignation is not deemed accepted after 30 days');
reset role; update public.requests set payload = payload || jsonb_build_object('defer_until', current_date - 1) where id = :'rs2';
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok(public.apply_deemed_resignations(:'cid') = 1, 'accepted when the deferral ends');
select t.ok((select end_date = current_date - 1 from public.employees where id = :'e_emp'), 'service ends at the end of the deferral');
reset role; update public.employees set end_date = null, end_reason = null where id = :'e_emp';
-- compensatory leave
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.comp_credit('$$ || :'e_emp' || $$', 10, 1.5, '2027-03-01', false, null)$$, 'م107', 'compensatory leave needs the worker''s consent');
select t.err($$select public.comp_credit('$$ || :'e_emp' || $$', 10, 1.2, '2027-03-01', true, null)$$, '22 مكرر', 'at least 1.5 leave hours per overtime hour');
select public.comp_credit(:'e_emp', 10, 1.5, '2027-03-01', true, 'مشروع الإطلاق') as cc1 \gset
select t.ok((select hours = 15 and use_by = '2027-04-30' from public.comp_credits where id = :'cc1'), 'credit = 1.5 × hours, to be used within 60 days');
select t.err($$select public.comp_credit('$$ || :'e_emp' || $$', 160, 1.5, '2027-03-02', true, null)$$, '240', 'at most 30 days (240 hours) a year');
select public.att_set(:'cid', :'e_emp', '2026-08-12', '08:00', '19:00', 'جرد');
select id as a310, extra_min as a310x from public.attendance where employee_id = :'e_emp' and day = '2026-08-12' \gset
select public.att_approve_ot(:'a310', :a310x);
select public.att_ot_to_comp(:'a310', 60, 1.5, true) as cc2 \gset
select t.ok((select ot_min = :a310x - 60 and ot_comp_min = 60 from public.attendance where id = :'a310') and (select hours = 1.5 and att_id = :'a310' from public.comp_credits where id = :'cc2'), 'approved overtime converted to leave is no longer paid');
select t.err($$select public.att_approve_ot('$$ || :'a310' || $$', $$ || :a310x || $$)$$, 'بين 0', 'converted minutes cannot be paid again');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select public.comp_credit('$$ || :'e_emp' || $$', 1, 1.5, '2027-03-01', true, null)$$, '42501|غير مصرح', 'employees cannot credit themselves');
select t.ok((select balance_hours = 16.5 from public.comp_balance(:'e_emp')), 'employee sees own compensatory balance');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'leave', 'comp', current_date + 400, current_date + 402)$$, 'التعويضية', 'compensatory leave limited to the balance');
select public.submit_request(:'cid', 'leave', 'comp', current_date + 400, current_date + 401, null, '{}', 'راحة') as rcomp \gset
select t.ok((select used_hours = 16 and balance_hours = 0.5 from public.comp_balance(:'e_emp')), 'a pending compensatory leave reserves the hours');
-- exam leave modes
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'leave', 'exam', current_date + 20, current_date + 21, null, '{"exam_mode":"own","files":[{"name":"r.pdf","mime":"application/pdf","data":"JVBERi0xLjQK"}]}')$$, 'م115', 'only first-attempt or repeated-year exams');
-- far-future month (no payroll run touches it) so exam_not_sat below is stable whatever day the suite runs
select public.submit_request(:'cid', 'leave', 'exam', '2030-03-10', '2030-03-11', null, '{"exam_mode":"approved"}'::jsonb || '{"files":[{"name":"r.pdf","mime":"application/pdf","data":"JVBERi0xLjQK"}]}'::jsonb) as rex1 \gset
select public.submit_request(:'cid', 'leave', 'exam', current_date + 25, current_date + 26, null, '{"exam_mode":"repeat"}'::jsonb || '{"files":[{"name":"r.pdf","mime":"application/pdf","data":"JVBERi0xLjQK"}]}'::jsonb) as rex2 \gset
select public.submit_request(:'cid', 'leave', 'exam', current_date + 30, current_date + 31, null, '{"files":[{"name":"r.pdf","mime":"application/pdf","data":"JVBERi0xLjQK"}]}'::jsonb) as rex3 \gset
select t.ok((select sub = 'exam' from public.requests where id = :'rex1') and (select sub = 'unpaid' and (payload->>'exam')::boolean from public.requests where id = :'rex2')
             and (select sub = 'exam' and payload->>'exam_mode' = 'approved' from public.requests where id = :'rex3'), 'exam days are paid leave; only a repeated year is unpaid (Art. 115)');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.exam_not_sat('$$ || :'rex1' || $$', null)$$, 'غير معتمدة', 'only an approved exam leave');
reset role; update public.requests set status = 'approved' where id = :'rex1';
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.exam_not_sat(:'rex1', 'لم يحضر الاختبار');
select t.ok((select sub = 'unpaid' and (payload->>'exam_missed')::boolean from public.requests where id = :'rex1'), 'exam not sat: the leave becomes unpaid (Art. 115)');
reset role;

-- ================= EXTRA ALLOWANCES AND SALARY HISTORY =================
select t.ok((select count(*) from public.salary_history where employee_id = :'e_emp' and reason = 'الأجر عند التعيين') = 1, 'hiring writes the first salary history row');
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.payroll_prepare(:'cid', 2027, 2, '2027-02-25') as feb27 \gset
select t.err($$select public.allowance_save(null, '$$ || :'e_emp' || $$', 'بدل اتصال', null, 0, current_date, null, null)$$, 'أكبر من صفر', 'an allowance needs an amount');
select public.allowance_save(null, :'e_emp', 'بدل اتصال', 'Phone allowance', 300, '2026-01-01', null, null) as al1 \gset
select t.ok((select allowances = 300 and gross = 10800 from public.payroll_lines where run_id = :'feb27' and employee_id = :'e_emp'), 'an active allowance is added to the wage in the draft payroll');
select t.ok((select gosi = public.gosi_employee(true, 8000, 2000, public.gosi_is_new(e.gosi_new, e.hire_date), '2027-02-28') from public.payroll_lines, public.employees e where run_id = :'feb27' and employee_id = :'e_emp' and e.id = :'e_emp'), 'the GOSI basis stays basic + housing');
select t.ok((select wage = 10800 from public.eos_for_employee(:'e_emp', current_date, 'resign')), 'end-of-service uses the wage with allowances (Art. 84)');
select t.ok((select (data->'wage'->>'other')::numeric = 300 and (data->'wage'->>'gross')::numeric = 10800 from public.issue_letter(:'e_emp', 'salary', 'ar', null, true)), 'salary certificate shows other allowances');
select public.allowance_save(:'al1', null, 'بدل اتصال', 'Phone allowance', 300, '2026-01-01', '2027-01-31', 'انتهاء المهمة');
select t.ok((select allowances = 0 and gross = 10500 from public.payroll_lines where run_id = :'feb27' and employee_id = :'e_emp'), 'an ended allowance stops in the following payroll');
select t.ok((select reason like 'إيقاف بدل%' and effective_on = '2027-02-01' from public.salary_history where employee_id = :'e_emp' order by created_at desc, id desc limit 1), 'stopping an allowance is logged');
select t.err($$select public.salary_change('$$ || :'e_emp' || $$', 9000, 2250, 500, current_date, '')$$, 'سبب', 'a salary change needs a reason');
select t.err($$select public.salary_change('$$ || :'e_emp' || $$', 7000, 2000, 500, current_date, 'إعادة هيكلة')$$, 'موافقة العامل', 'a reduction needs the worker''s written consent');
select t.err($$select public.salary_change('$$ || :'e_emp' || $$', 9000, 2250, 500, current_date + 5, 'ترقية')$$, 'السريان', 'no future-dated change');
select public.salary_change(:'e_emp', 9000, 2250, 500, current_date, 'ترقية إلى مطوّر أول');
select t.ok((select basic = 9000 and allowances = 300 and gross = 12050 and prev_gross = 10500 and reason = 'ترقية إلى مطوّر أول' from public.salary_history where employee_id = :'e_emp' order by created_at desc, id desc limit 1), 'raise logged with the reason and the previous wage');
select t.ok((select basic = 9000 and gross = 11750 from public.payroll_lines where run_id = :'feb27' and employee_id = :'e_emp'), 'the draft payroll follows the new wage');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.salary_history where employee_id <> :'e_emp') = 0 and (select count(*) from public.salary_history) >= 3, 'an employee sees only own salary history');
select t.err($$select public.allowance_save(null, '$$ || :'e_emp' || $$', 'بدل', null, 100, current_date, null, null)$$, '42501|غير مصرح', 'employees cannot add allowances');
select t.err($$select public.emp_allow('$$ || :'e_emp' || $$', current_date)$$, 'permission', 'allowance sums are internal');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.salary_change(:'e_emp', 8000, 2000, 500, current_date, 'إعادة الأجر للاختبارات', true);
reset role;

-- ================= IMPORT DOCUMENTS AND CONTRACTS FROM EXCEL =================
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.import_documents('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"9999","doc_type":"passport","doc_no":"X1"}]')$$, 'السطر 2.*غير موجود', 'unknown employee number names the row');
select t.err($$select public.import_documents('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"5006","doc_type":"other","doc_no":"X1"}]')$$, 'اسم المستند', 'an "other" document needs its name');
select t.err($$select public.import_documents('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"5006","doc_type":"work_permit","doc_no":"W1","issue_date":"2026-05-01","expiry_date":"2026-01-01"}]')$$, 'قبل الإصدار', 'expiry before issue rejected');
select t.err($$select public.import_documents('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"5006","doc_type":"work_permit","doc_no":"W1"},{"_row":3,"emp_no":"5006","doc_type":"work_permit","doc_no":"W2"}]')$$, 'مكرر', 'the same document twice in a file rejected');
select count(*) as docs0 from public.employee_documents \gset
select t.err($$select public.import_documents('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"5001","doc_type":"national_id","doc_no":"1012345670"},{"_row":3,"emp_no":"9999","doc_type":"passport","doc_no":"X"}]')$$, 'السطر 3', 'a bad row aborts the file');
select t.ok((select count(*) from public.employee_documents) = :docs0, 'nothing is imported when any row is bad');
select public.import_documents(:'cid', jsonb_build_array(
  jsonb_build_object('_row', 2, 'emp_no', '5006', 'doc_type', 'iqama', 'doc_no', '2000000007', 'expiry_date', (current_date + 380)::text),
  jsonb_build_object('_row', 3, 'emp_no', '5006', 'doc_type', 'work_permit', 'doc_no', 'WP-77', 'expiry_date', (current_date + 380)::text),
  jsonb_build_object('_row', 4, 'emp_no', '5001', 'doc_type', 'other', 'title', 'رخصة مزاولة', 'title_en', 'Practice license', 'doc_no', 'PL-1', 'expiry_date', (current_date + 100)::text))) as imd \gset
select t.ok(:'imd'::jsonb = '{"added":2,"updated":1}'::jsonb, 'documents imported: new ones added, an existing iqama updated');
select t.ok((select count(*) from public.employee_documents where employee_id = :'e_exp' and doc_type = 'iqama') = 1 and (select expiry_date = current_date + 380 from public.employee_documents where employee_id = :'e_exp' and doc_type = 'iqama'), 'a renewed iqama replaces the expiry date instead of duplicating');
select t.ok(not exists(select 1 from public.doc_alerts(:'cid', 90) where employee_id = :'e_exp' and label in ('iqama','work_permit')), 'imported documents clear the alerts');
select t.err($$select public.import_contracts('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"5006","contract_type":"indefinite","start_date":"2026-01-01"}]')$$, 'م37', 'non-Saudi indefinite contract rejected (Art. 37)');
select t.err($$select public.import_contracts('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"5001","contract_type":"fixed","start_date":"2026-01-01"}]')$$, 'نهاية العقد', 'a Saudi fixed-term contract needs an end date');
select t.err($$select public.import_contracts('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"5001","contract_type":"indefinite","start_date":"2026-01-01","end_date":"2027-01-01"}]')$$, 'ليس له تاريخ نهاية', 'an indefinite contract has no end date');
select t.err($$select public.import_contracts('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"5001","contract_type":"indefinite","start_date":"2026-01-01"},{"_row":3,"emp_no":"5001","contract_type":"indefinite","start_date":"2025-01-01"}]')$$, 'أكثر من عقد', 'one contract per employee in a file');
select end_date + 1 as exp_next from public.contracts where id = :'c_exp' \gset
select public.import_contracts(:'cid', jsonb_build_array(
  jsonb_build_object('_row', 2, 'emp_no', '5001', 'contract_type', 'fixed', 'start_date', '2024-02-01', 'end_date', '2027-01-31', 'first_start', '2020-02-01', 'renewal_no', '2'),
  jsonb_build_object('_row', 3, 'emp_no', '5006', 'contract_type', 'fixed', 'start_date', :'exp_next'),
  jsonb_build_object('_row', 4, 'emp_no', '1000', 'contract_type', 'indefinite', 'start_date', '2018-01-01', 'monthly_paid', 'true'))) as imc \gset
select t.ok(:'imc'::jsonb = '{"added":2,"renewed":1,"same":0}'::jsonb, 'contracts imported: ' || :'imc');
select t.ok((select status = 'renewed' from public.contracts where id = :'c_exp') and (select renewal_no = 1 and prev_id = :'c_exp' and end_date = :'exp_next'::date + interval '1 year' - interval '1 day' from public.contracts where employee_id = :'e_exp' and status = 'active'),
  'a contract starting the day after the current one ends is its renewal (non-Saudi: one year)');
select t.ok((select first_start = '2020-02-01' and renewal_no = 2 from public.contracts where employee_id = :'e_mgr' and status = 'active'), 'first start and renewals carried for Art. 55');
select t.ok(public.import_contracts(:'cid', '[{"_row":2,"emp_no":"1000","contract_type":"indefinite","start_date":"2018-01-01"}]') = '{"added":0,"renewed":0,"same":1}'::jsonb
       and (select count(*) from public.contracts where employee_id = :'e_gm') = 1, 're-uploading the same contract changes nothing');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select public.import_documents('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"5000","doc_type":"passport","doc_no":"X"}]')$$, '42501|غير مصرح', 'employees cannot import');
reset role;

-- ================= ORGANISATION CHART =================
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$update public.employees set manager_id = '$$ || :'e_emp' || $$' where id = '$$ || :'e_mgr' || $$'$$, 'دائري', 'a manager cannot report to their own report (no loops)');
select t.err($$update public.employees set manager_id = '$$ || :'e_emp' || $$' where id = '$$ || :'e_gm' || $$'$$, 'دائري', 'loops are caught across several levels');
select id as dep_it from public.departments where company_id = :'cid' and name = 'التقنية' \gset
update public.departments set head_id = :'e_mgr' where id = :'dep_it';
select t.ok((select head_id = :'e_mgr' from public.departments where id = :'dep_it'), 'HR sets the department head');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.org_chart(:'cid')) > 3 and (select manager_id = :'e_mgr' and job_title is not null from public.org_chart(:'cid') where id = :'e_emp'), 'every employee sees the chart: names, titles and reporting lines');
select t.ok((select count(*) from public.employees) = 1, 'the chart does not open the employee records themselves');
update public.departments set head_id = null;
reset role;
select t.ok((select head_id = :'e_mgr' from public.departments where id = :'dep_it'), 'employees cannot change department heads');
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
reset role;
select set_config('request.jwt.claim.sub', :'u_other', false); set role authenticated;
select t.ok((select count(*) from public.org_chart(:'cid')) = 0, 'another company sees nothing');
select t.err($$insert into public.departments(company_id, name, head_id) values ('$$ || :'cid2' || $$', 'قسم', '$$ || :'e_mgr' || $$')$$, 'ليس من موظفي', 'a head from another company is refused');
reset role;

-- ================= BULK UPDATE OF EMPLOYEE DATA =================
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.update_employees('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"5000","basic":"1"}]')$$, 'لا يمكن تحديث الحقل', 'wages cannot be changed from the bulk file');
select t.err($$select public.update_employees('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"5000","iban":"SA1"}]')$$, 'السطر 2.*الآيبان', 'invalid IBAN names the row');
select t.err($$select public.update_employees('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"5000","full_name":null}]')$$, 'لا يُمسح', 'the full name cannot be cleared');
select t.err($$select public.update_employees('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"5001","manager_emp_no":"5000"}]')$$, 'السطر 2.*دائري', 'a reporting loop is refused with its row');
select coalesce(full_name_en, '') as en0 from public.employees where id = :'e_emp' \gset
select t.err($$select public.update_employees('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"5000","full_name_en":"X Y"},{"_row":3,"emp_no":"9999","phone":"0500000000"}]')$$, 'السطر 3', 'unknown employee aborts the file');
select t.ok((select coalesce(full_name_en, '') = :'en0' from public.employees where id = :'e_emp'), 'nothing changes when any row is bad');
select t.ok(public.update_employees(:'cid', jsonb_build_array(
  jsonb_build_object('_row', 2, 'emp_no', '5000', 'full_name_en', 'Mohammed Alotaibi', 'phone', '0551112233', 'iban', 'SA0380000000608010167519', 'department', 'الدعم الفني', 'job_title_en', 'Developer'),
  jsonb_build_object('_row', 3, 'emp_no', '5006', 'email', null, 'manager_emp_no', '5000'))) = 2, 'two employees updated');
select t.ok((select full_name_en = 'Mohammed Alotaibi' and phone = '0551112233' and iban like 'SA03%' and job_title_en = 'Developer' and basic = 8000 from public.employees where id = :'e_emp')
       and (select d.name from public.employees e join public.departments d on d.id = e.department_id where e.id = :'e_emp') = 'الدعم الفني', 'fields updated; a new department is created; the wage is untouched');
select t.ok((select manager_id = :'e_emp' and email is null from public.employees where id = :'e_exp'), 'manager by employee number; a null clears the field');
select t.ok(public.update_employees(:'cid', jsonb_build_array(
  jsonb_build_object('_row', 2, 'emp_no', '5000', 'manager_emp_no', '5006'), jsonb_build_object('_row', 3, 'emp_no', '5006', 'manager_emp_no', '5001'))) = 2, 'a swap of reporting lines in one file runs');
select t.ok((select manager_id = :'e_exp' from public.employees where id = :'e_emp'), 'a valid swap of reporting lines in one file is accepted');
select public.update_employees(:'cid', jsonb_build_array(jsonb_build_object('_row', 2, 'emp_no', '5006', 'manager_emp_no', '5001'), jsonb_build_object('_row', 3, 'emp_no', '5000', 'manager_emp_no', '5001')));
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select public.update_employees('$$ || :'cid' || $$', '[{"_row":2,"emp_no":"5000","phone":"0500000000"}]')$$, '42501|غير مصرح', 'employees cannot bulk-update');
reset role;

-- ================= COMPANY CODE =================
select code as cc1 from public.companies where id = :'cid' \gset
insert into public.companies(name, code) values ('منشأة برمز مكرر', :'cc1') returning code as cc2 \gset
select t.ok(:'cc2' <> :'cc1' and :'cc2' ~ '^[A-Z0-9]{6}$', 'a clashing company code is replaced automatically (' || :'cc2' || ')');
select t.ok((select count(distinct code) = count(*) from public.companies), 'every company has its own code');
-- (the temporary company stays: its audit trail cannot be deleted)

-- ================= SUPPORTING DOCUMENTS ON LEAVE REQUESTS =================
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'leave', 'sick', current_date + 700, current_date + 701)$$, 'تقرير طبي', 'a sick leave needs the medical report (Art. 117)');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'leave', 'sick', current_date + 700, current_date + 701, null, '{"doc_ref":"PSL26000009","files":[{"name":"x.pdf","mime":"application/pdf","data":"aGVsbG8="}]}')$$, 'ليس صورة أو PDF', 'a file that is not really a PDF is refused');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'leave', 'sick', current_date + 700, current_date + 701, null, '{"doc_ref":"PSL26000009","files":[{"name":"x.exe","mime":"application/x-msdownload","data":"TVo="}]}')$$, 'ليس صورة', 'only images and PDF are accepted');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'leave', 'sick', current_date + 700, current_date + 701, null, '{"files":[{"name":"report.jpg","mime":"image/jpeg","data":"/9j/4AAQ"}]}')$$, 'رقم الإجازة المرضية', 'a sick leave needs its number from Seha');
select public.submit_request(:'cid', 'leave', 'sick', current_date + 700, current_date + 701, null, '{"doc_ref":" psl 2600 0123 ","files":[{"name":"report.jpg","mime":"image/jpeg","data":"/9j/4AAQ"}]}', 'زكام') as rsk \gset
select t.ok((select payload->>'doc_ref' = 'PSL26000123' from public.requests where id = :'rsk'), 'the document number is kept, cleaned (no spaces, upper case)');
select t.ok((select count(*) = 1 and min(size) = 6 from public.request_attachments where request_id = :'rsk') and (select not (payload ? 'files') from public.requests where id = :'rsk'), 'the report is stored apart from the request');
select t.ok((select count(*) from public.request_attachments where request_id = :'rsk') = 1, 'the employee sees own attachment');
select t.ok(public.request_attach(:'rsk', '[{"name":"page2.png","mime":"image/png","data":"iVBORw0KGgo="}]') = 1, 'the employee adds a page while the request is pending');
select t.ok(public.request_attach(:'rsk', null, 'psl26000124') = 0, 'a number alone can be sent');
select t.ok((select payload->>'doc_ref' = 'PSL26000124' from public.requests where id = :'rsk'), 'the document number can be corrected while pending');
select t.ok(public.submit_request(:'cid', 'leave', 'annual', current_date + 710, current_date + 710) is not null, 'annual leave needs no document');
reset role;
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select t.ok((select count(*) from public.request_attachments where request_id = :'rsk') = 0, 'the manager does not see the medical report (health data)');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok((select count(*) from public.request_attachments where request_id = :'rsk') = 2, 'HR sees the attachments');
select t.err($$delete from public.request_attachments$$, 'permission|42501', 'attachments cannot be deleted or changed directly');
reset role;
select t.ok(not exists(select 1 from public.audit_log where entity = 'request_attachments'), 'file contents never go to the audit log');
update public.requests set status = 'cancelled' where id = :'rsk';

-- ================= PERMISSIONS PER PERSON =================
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.set_member_access('$$ || :'cid' || $$', '$$ || :'u_owner' || $$', array['employee'])$$, 'المالك له كل الصلاحيات', 'the owner''s access cannot be lowered');
select t.err($$select public.set_member_access('$$ || :'cid' || $$', '$$ || :'u_hr' || $$', array['employee'])$$, 'بنفسك', 'nobody changes their own access');
select t.err($$select public.set_member_access('$$ || :'cid' || $$', '$$ || :'u_emp' || $$', array['employee','hr'])$$, 'غير مصرح', 'HR cannot make another HR (only the owner)');
select public.set_member_access(:'cid', :'u_emp', array['employee','storekeeper'], array['stock','items']);
select t.ok((select role = 'storekeeper' and extra_roles = array['employee'] from public.members where company_id = :'cid' and user_id = :'u_emp'), 'HR gives an employee a second role (employee + storekeeper)');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok(public.has_role(:'cid', array['employee']) and public.has_role(:'cid', array['storekeeper']) and public.fin_can(:'cid', 'stock') and public.fin_can(:'cid', 'items') and not public.fin_can(:'cid', 'je'),
  'both roles work, with only the finance permissions HR chose');
select t.ok((select roles @> array['storekeeper','employee'] and perms = array['items','stock'] from public.my_companies() where company_id = :'cid'), 'the app gets all roles and permissions');
select t.ok(public.submit_request(:'cid', 'permit', null, current_date + 3, current_date + 3, null, '{"hours":1}') is not null, 'still an employee: can send requests');
select t.err($$select public.set_member_access('$$ || :'cid' || $$', '$$ || :'u_mgr' || $$', array['employee'])$$, 'غير مصرح|42501', 'a storekeeper cannot change anyone''s access');
reset role;
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select public.set_member_access(:'cid', :'u_mgr', array['manager','hr']);
select t.ok((select role = 'hr' and extra_roles = array['manager'] from public.members where company_id = :'cid' and user_id = :'u_mgr'), 'the owner appoints HR');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.set_member_access('$$ || :'cid' || $$', '$$ || :'u_mgr' || $$', array['manager'])$$, 'يعدّلها المالك', 'HR cannot change another HR person');
select t.ok((select count(*) from public.member_access(:'cid')) >= 5, 'HR sees everyone''s access');
select public.set_member_access(:'cid', :'u_emp', array['employee']);
select t.ok((select role = 'employee' and extra_roles = '{}' from public.members where company_id = :'cid' and user_id = :'u_emp') and not exists(select 1 from public.member_perms where user_id = :'u_emp'), 'HR takes a role back');
reset role;
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select public.set_member_access(:'cid', :'u_mgr', array['manager']);
reset role;
select t.ok(exists(select 1 from public.audit_log where entity = 'members' and action = 'update'), 'access changes are in the audit log');

-- ================= PART-MONTH PAY (joiners, leavers, mid-month changes) =================
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, hire_date, basic, housing, transport)
values (:'cid', '7801', 'منضم منتصف الشهر', true, 'm', 'محاسب', '2027-03-16', 6000, 1500, 300) returning id as pj \gset
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, hire_date, basic, housing, transport)
values (:'cid', '7802', 'زيادة منتصف الشهر', true, 'm', 'محاسب', '2026-01-01', 6000, 1500, 300) returning id as pr \gset
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, hire_date, end_date, end_reason, basic, housing, transport)
values (:'cid', '7803', 'مغادر منتصف الشهر', true, 'm', 'محاسب', '2024-01-01', '2027-03-10', 'resign', 3000, 0, 0) returning id as pl \gset
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, hire_date, basic, housing, transport)
values (:'cid', '7804', 'منضم في فبراير', true, 'm', 'محاسب', '2027-02-15', 3000, 0, 0) returning id as pf \gset
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.payroll_prepare(:'cid', 2027, 3, '2027-03-27') as mar27 \gset
select t.ok((select paid_days = 15 and basic = 3000 and housing = 750 and transport = 150 and gross = 3900 from public.payroll_lines where run_id = :'mar27' and employee_id = :'pj'),
  'a joiner on the 16th is paid 15 of 30 days');
select t.ok((select paid_days = 10 and gross = 1000 from public.payroll_lines where run_id = :'mar27' and employee_id = :'pl'), 'a leaver on the 10th is paid 10 days');
select t.ok((select paid_days = 30 and gross = 10500 from public.payroll_lines where run_id = :'mar27' and employee_id = :'e_emp'), 'a full month is unchanged');
select public.allowance_save(null, :'pj', 'بدل اتصال', 'Phone allowance', 600, '2027-03-21', null, null);
select t.ok((select allowances = 200 and gross = 4100 from public.payroll_lines where run_id = :'mar27' and employee_id = :'pj'), 'an allowance starting on the 21st is paid for 10 days');
select t.ok((select not wage_change from public.salary_history where employee_id = :'pj' order by created_at desc, id desc limit 1), 'an allowance row is not read as a wage change');
select public.payroll_prepare(:'cid', 2026, 8, '2026-08-27') as aug26 \gset
select public.salary_change(:'pr', 9000, 2250, 300, '2026-08-11', 'ترقية');
select t.ok((select paid_days = 30 and basic = 8000 and housing = 2000 and transport = 300 and gross = 10300 from public.payroll_lines where run_id = :'aug26' and employee_id = :'pr'),
  'a raise from the 11th: 10 days at the old wage, 20 at the new');
select t.ok((select absence = 0 and overtime = 0 from public.payroll_lines where run_id = :'aug26' and employee_id = :'pr'), 'no deductions invented');
select public.payroll_adjust(:'aug26', :'pr', 1, 0, 0);
select t.ok((select overtime = round((11550 / 30.0 / 8 + 0.5 * 9000 / 30.0 / 8), 2) from public.payroll_lines where run_id = :'aug26' and employee_id = :'pr'), 'overtime uses the wage in force at month end');
select public.payroll_prepare(:'cid', 2027, 2, '2027-02-25');
select t.ok((select paid_days = 16 and gross = 1600 from public.payroll_lines where run_id = :'feb27' and employee_id = :'pf'), 'February: a joiner on the 15th is paid 16 of 30 days');
reset role;
update public.employees set end_date = '2027-03-31', end_reason = 'resign' where id in (:'pj', :'pr', :'pf');

-- ================= PAYROLL CUTOFF DAY =================
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, hire_date, basic, housing, transport)
values (:'cid', '7811', 'منضم بعد الإقفال', true, 'm', 'محاسب', '2027-06-25', 3000, 0, 0) returning id as cj \gset
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, hire_date, end_date, end_reason, basic, housing, transport)
values (:'cid', '7812', 'مغادر بعد الإقفال', true, 'm', 'محاسب', '2020-01-01', '2027-07-28', 'resign', 3000, 0, 0) returning id as cl \gset
insert into public.requests(company_id, employee_id, kind, sub, from_date, to_date, days, status) values
  (:'cid', :'e_emp', 'leave', 'unpaid', '2027-06-25', '2027-06-26', 2, 'approved'), (:'cid', :'cl', 'leave', 'unpaid', '2027-07-24', '2027-07-25', 2, 'approved');
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select public.payroll_cutoff_set('$$ || :'cid' || $$', 21)$$, '42501|غير مصرح', 'an employee cannot set the cutoff');
select t.err($$select public.payroll_period('$$ || :'cid' || $$', 2027, 6)$$, 'permission', 'the period function is internal');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.payroll_cutoff_set('$$ || :'cid' || $$', 31)$$, 'بين 2 و28', 'cutoff day between 2 and 28');
select public.payroll_cutoff_set(:'cid', 21);
select public.payroll_prepare(:'cid', 2027, 6, '2027-06-27') as jun27 \gset
select t.ok((select att_from = '2027-05-21' and att_to = '2027-06-20' from public.payroll_runs where id = :'jun27'), 'cutoff 21: June counts 21 May – 20 June');
select t.ok(not exists(select 1 from public.payroll_lines where run_id = :'jun27' and employee_id = :'cj'), 'a joiner on the 25th waits for next month''s payroll');
select t.ok((select absence_days = 0 from public.payroll_lines where run_id = :'jun27' and employee_id = :'e_emp'), 'unpaid leave after the cutoff is not in this month');
reset role;
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select public.payroll_approve(:'jun27');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.payroll_prepare(:'cid', 2027, 7, '2027-07-27') as jul27 \gset
select t.ok((select att_from = '2027-06-21' and att_to = '2027-07-20' from public.payroll_runs where id = :'jul27'), 'July counts 21 June – 20 July');
select t.ok((select arrears_days = 6 and arrears = 600 and gross = 3000 and net = 3600 - gosi from public.payroll_lines where run_id = :'jul27' and employee_id = :'cj'),
  'the joiner gets June''s 6 days as previous month''s dues with the full July wage');
select t.ok((select absence_days = 2 from public.payroll_lines where run_id = :'jul27' and employee_id = :'e_emp'), 'the unpaid leave of 25–26 June is deducted in July');
select t.ok((select paid_days = 28 and absence_days = 2 from public.payroll_lines where run_id = :'jul27' and employee_id = :'cl'), 'a leaver''s last payroll runs to the last day (leave after the cutoff included)');
reset role;
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select t.ok(public.payroll_approve(:'jul27') is not null, 'approval posts a balanced entry including the dues');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.payroll_cutoff_set(:'cid', null);
select public.payroll_prepare(:'cid', 2027, 8, '2027-08-27') as aug27 \gset
select t.ok((select att_from = '2027-07-21' and att_to = '2027-08-31' from public.payroll_runs where id = :'aug27'), 'switching the cutoff off: no day is skipped or counted twice');
select t.ok((select arrears = 0 from public.payroll_lines where run_id = :'aug27' and employee_id = :'cj'), 'dues are paid only once');
reset role;
update public.employees set end_date = '2027-08-31', end_reason = 'resign' where id = :'cj';

-- ================= MONTHLY LIMITS: PERMIT HOURS AND FORGOTTEN FINGERPRINT =================
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select public.month_limits_set('$$ || :'cid' || $$', 4, 2)$$, '42501|غير مصرح', 'an employee cannot set the limits');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.month_limits_set(:'cid', 2, 1);
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select public.submit_request(:'cid', 'permit', null, '2027-09-05', '2027-09-05', null, '{"hours":1.5}');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'permit', null, '2027-09-20', '2027-09-20', null, '{"hours":1}')$$, 'المتبقي لك 0.5', 'permit hours are capped per month');
select t.ok(public.submit_request(:'cid', 'permit', null, '2027-10-02', '2027-10-02', null, '{"hours":2}') is not null, 'next month starts a new allowance');
select t.ok((select permit_limit = 2 and permit_used = 1.5 and punch_limit = 1 from public.my_month_limits(:'cid', '2027-09-10')), 'the employee sees the monthly limits and what is used');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'punch', null, public.riyadh_today() + 1, null, null, '{"in":"08:00"}')$$, 'يوماً مضى', 'no forgotten fingerprint for a future day');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'punch', null, public.riyadh_today() - 1, null, null, '{}')$$, 'وقت الحضور أو الانصراف', 'the request states the missing time');
select public.submit_request(:'cid', 'punch', null, public.riyadh_today() - 1, null, null, '{"in":"08:05","out":"16:10"}', 'نسيت البصمة') as pu1 \gset
select t.ok((select route = array['m','p'] and to_date = from_date from public.requests where id = :'pu1'), 'a forgotten fingerprint goes to the manager then HR');
reset role;
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select public.decide_request(:'pu1', true);
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.decide_request(:'pu1', true);
reset role;
select t.ok((select source = 'request' and check_in = public.riyadh_ts(public.riyadh_today() - 1, '08:05') and check_out = public.riyadh_ts(public.riyadh_today() - 1, '16:10')
             from public.attendance where employee_id = :'e_emp' and day = public.riyadh_today() - 1), 'approval writes the times to the attendance record');
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'punch', null, public.riyadh_today() - 1, null, null, '{"out":"17:00"}')$$, 'حد طلبات نسيان البصمة', 'forgotten-fingerprint requests are capped per month');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.month_limits_set(:'cid', null, null);
reset role;

-- ================= HR COMPLIANCE: CALENDAR, GOSI REPORT, NITAQAT, ORG CHART VISIBILITY =================
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, hire_date, probation_end, basic, housing, transport)
values (:'cid', '7821', 'تحت التجربة', true, 'm', 'محاسب', current_date - 30, current_date + 60, 5000, 1000, 0) returning id as cp \gset
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, hire_date, basic, housing, transport)
values (:'cid', '7822', 'يكمل خمس سنوات', true, 'm', 'محاسب', (current_date - interval '5 years')::date + 10, 5000, 1000, 0) returning id as c5 \gset
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok(exists(select 1 from public.doc_alerts(:'cid', 90) where employee_id = :'cp' and kind = 'probation' and due >= current_date + 60), 'the expiry list shows the end of probation');
select t.ok(exists(select 1 from public.doc_alerts(:'cid', 30) where employee_id = :'c5' and kind = 'service5' and due = (current_date - interval '5 years')::date + 10 + interval '5 years'), 'and the 5-year service milestone (Arts. 84, 109)');
select t.ok((select status = 'new' from public.gosi_report(:'jul27') where employee_id = :'cj') and (select status = 'left' from public.gosi_report(:'mar27') where employee_id = :'pl'),
  'GOSI report flags joiners and leavers');
select t.ok((select base = 10000 and prev_base = 10000 and status = '' and employee_share > 0 from public.gosi_report(:'mar27') where employee_id = :'e_emp'), 'GOSI report: contribution wage = basic + housing, compared with last month');
select t.err($$select public.nitaqat_set('$$ || :'cid' || $$', '{"low":30,"mid":25}')$$, 'تتصاعد', 'Nitaqat thresholds must rise band by band');
select public.nitaqat_set(:'cid', '{"low":"31.65","mid":"40","high":"52","plat":""}');
select t.ok((select nitaqat = '{"low":31.65,"mid":40,"high":52}'::jsonb from public.companies where id = :'cid'), 'HR saves the Nitaqat thresholds from Qiwa');
select public.org_visibility_set(:'cid', 'hr');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.org_chart(:'cid')) = 0, 'org chart for HR only: an employee sees nothing');
select t.err($$select public.gosi_report('$$ || :'mar27' || $$')$$, '42501|غير مصرح', 'employees cannot open the GOSI report');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.org_visibility_set(:'cid', 'managers');
reset role;
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select t.ok((select count(*) from public.org_chart(:'cid')) > 3, 'org chart for managers: a manager sees it');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.org_chart(:'cid')) = 0, '...and an employee without a team does not');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.org_visibility_set(:'cid', 'all');
reset role;
update public.employees set end_date = current_date - 1, end_reason = 'resign' where id in (:'cp', :'c5');

-- ================= GOSI BY DAYS, JOINER ON THE 31ST =================
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, hire_date, basic, housing, transport)
values (:'cid', '7831', 'منضم يوم 31', true, 'm', 'محاسب', '2027-05-31', 6000, 1500, 0) returning id as c31 \gset
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.payroll_prepare(:'cid', 2027, 5, '2027-05-27') as may27 \gset
select t.ok((select paid_days = 1 and basic = 200 and housing = 50 from public.payroll_lines where run_id = :'may27' and employee_id = :'c31'), 'a joiner on the 31st is paid one day');
select t.ok((select gosi = round(public.gosi_employee(true, 6000, 1500, true, '2027-05-31') / 30, 2) and employer_gosi = round(public.gosi_employer(true, 6000, 1500, true, '2027-05-31') / 30, 2)
             from public.payroll_lines where run_id = :'may27' and employee_id = :'c31'), 'GOSI for one day: monthly contribution / 30');
select t.ok((select gosi = round(public.gosi_employee(true, 6000, 1500, public.gosi_is_new(null, '2027-03-16'), '2027-03-31') * 15 / 30, 2)
             from public.payroll_lines where run_id = :'mar27' and employee_id = :'pj'), 'GOSI by the days worked (joiner on the 16th: 15/30)');
reset role;
select t.ok((select l.gosi = public.gosi_employee(true, 8000, 2000, public.gosi_is_new(e.gosi_new, e.hire_date), '2027-05-31') from public.payroll_lines l join public.employees e on e.id = l.employee_id
             where l.run_id = :'may27' and l.employee_id = :'e_emp'), 'a full month pays the full contribution');
update public.employees set end_date = '2027-05-31', end_reason = 'resign' where id = :'c31';

-- ================= CUSTODY AND CLEARANCE, RAMADAN HOURS, OVERTIME CAP =================
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.custody_save(null, :'e_emp', 'حاسب محمول', 'Laptop', 'SN-123', 3500, '2026-01-10', null) as cu1 \gset
select t.ok((select ok = false and detail like '1 — 3500%' from public.clearance_status(:'e_emp') where step = 'custody'), 'clearance: custody still held');
select t.err($$select public.clearance_mark('$$ || :'e_emp' || $$', 'hr', true, null)$$, 'العهد', 'HR cannot clear while custody is held');
select t.err($$select public.custody_return('$$ || :'cu1' || $$', '2026-10-20', true, '')$$, 'اكتب ما حدث', 'a lost item needs a note');
select public.custody_return(:'cu1', '2026-10-20', false, null);
select t.ok((select ok from public.clearance_status(:'e_emp') where step = 'custody'), 'custody returned');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.custody_items where employee_id = :'e_emp') = 1, 'the employee sees own custody');
select t.err($$select public.clearance_status('$$ || :'e_emp' || $$')$$, '42501|غير مصرح', 'the employee cannot sign the clearance');
reset role;
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select public.clearance_mark(:'e_emp', 'manager', true, 'سلّم المهام');
select t.err($$select public.clearance_mark('$$ || :'e_emp' || $$', 'it', true, null)$$, '42501|غير مصرح', 'the manager signs only the manager step');
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select public.clearance_mark(:'e_emp', 'finance', true, null);
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.clearance_mark(:'e_emp', 'it', true, null);
select public.clearance_mark(:'e_emp', 'hr', true, null);
select t.ok((select count(*) filter (where ok) from public.clearance_status(:'e_emp') where step in ('manager','it','finance','hr')) = 4, 'every department signed the clearance');
select public.clearance_mark(:'e_emp', 'it', false, null);
select t.ok(not (select ok from public.clearance_status(:'e_emp') where step = 'it'), 'a step can be reopened');
-- Ramadan (Art. 98)
select public.att_set(:'cid', :'e_emp', '2026-10-05', '08:00', '14:00', 'اختبار رمضان');
select t.ok((select early_min = 120 from public.attendance where employee_id = :'e_emp' and day = '2026-10-05'), 'before Ramadan dates: leaving at 14:00 is early');
select t.err($$select public.ramadan_set('$$ || :'cid' || $$', '2026-10-04', '2026-10-08', null, 7)$$, 'م98', 'Ramadan hours cannot exceed 6 (Art. 98)');
select public.ramadan_set(:'cid', '2026-10-04', '2026-10-08', null, 6);
select t.ok((select early_min = 0 from public.attendance where employee_id = :'e_emp' and day = '2026-10-05'), 'in Ramadan the shift is 6 hours: no early leave');
select public.ramadan_set(:'cid', '2026-10-04', '2026-10-08', '10:00', 6);
select public.att_set(:'cid', :'e_emp', '2026-10-06', '10:05', '16:00', 'اختبار رمضان');
select t.ok((select late_min = 0 and early_min = 0 from public.attendance where employee_id = :'e_emp' and day = '2026-10-06'), 'Ramadan start time 10:00 – 16:00');
reset role;
update public.employees set is_muslim = false where id = :'e_emp';
select public.att_recalc(id) from public.attendance where employee_id = :'e_emp' and day = '2026-10-05';
select t.ok((select early_min = 120 from public.attendance where employee_id = :'e_emp' and day = '2026-10-05'), 'a non-Muslim worker keeps the normal shift in Ramadan');
update public.employees set is_muslim = true where id = :'e_emp';
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.ramadan_set(:'cid', null, null, null, 6);
select t.ok((select early_min = 120 from public.attendance where employee_id = :'e_emp' and day = '2026-10-05'), 'clearing the dates restores the normal shift');
-- overtime cap (720 hours a year)
select t.err($$select public.payroll_set_line('$$ || :'aug27' || $$', '$$ || :'e_emp' || $$', 721, 0, 0, 0)$$, '720', 'overtime above 720 hours a year is refused');
reset role;
update public.employees set ot_consent_year = 2027 where id = :'e_emp';
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.payroll_set_line(:'aug27', :'e_emp', 721, 0, 0, 0);
select t.ok((select overtime_hours = 721 from public.payroll_lines where run_id = :'aug27' and employee_id = :'e_emp') and public.ot_year_hours(:'e_emp', 2027) >= 721, 'allowed with the worker''s written consent');
select public.payroll_set_line(:'aug27', :'e_emp', 0, 0, 0, 0);
reset role;
update public.employees set ot_consent_year = null where id = :'e_emp';
delete from public.attendance where employee_id = :'e_emp' and day in ('2026-10-05', '2026-10-06');

-- ================= SHIFT SCHEDULES, BREAKS, RAMADAN TIMES, DEPARTMENT SHIFTS =================
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$insert into public.shifts(company_id, name, start_time, end_time) values ('$$ || :'cid' || $$', 'طويلة', '08:00', '17:00')$$, 'م98', 'a shift above 8 working hours is refused (Art. 98)');
insert into public.shifts(company_id, name, start_time, end_time, break_min, ramadan_start, ramadan_end, work_days)
values (:'cid', 'الوردية 1', '01:00', '09:00', 60, '22:00', '04:00', '{0,1,2,3,4,5,6}') returning id as sh1 \gset
select t.ok(:'sh1' is not null, 'shift 01:00–09:00 with a one-hour break (7 working hours) is accepted');
select t.err($$insert into public.shifts(company_id, name, start_time, end_time, ramadan_start, ramadan_end) values ('$$ || :'cid' || $$', 'رمضان طويل', '14:00', '22:00', '12:00', '19:00')$$, 'م98', 'a Ramadan time above 6 hours is refused');
insert into public.shifts(company_id, name, start_time, end_time, break_min, ramadan_start, ramadan_end, work_days)
values (:'cid', 'الوردية 2', '14:00', '22:00', 30, '20:00', '02:00', '{0,1,2,3,4,5,6}') returning id as sh2 \gset
insert into public.departments(company_id, name) values (:'cid', 'الاستقبال') returning id as dpr \gset
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, hire_date, department_id, basic, housing, transport, is_muslim)
values (:'cid', '7841', 'موظف استقبال', false, 'm', 'استقبال', '2026-01-01', :'dpr', 4000, 1000, 0, false) returning id as rec1 \gset
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, hire_date, department_id, basic, housing, transport)
values (:'cid', '7842', 'موظف استقبال 2', true, 'm', 'استقبال', '2026-01-01', :'dpr', 4000, 1000, 0) returning id as rec2 \gset
reset role;
select t.ok((public.employee_shift(:'rec1')).id = :'sh_day', 'without department or own shift: the company default');
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.department_shift_set(:'dpr', :'sh2');
reset role;
select t.ok((public.employee_shift(:'rec1')).id = :'sh2', 'HR assigns a shift to a whole department');
update public.employees set shift_id = :'sh1' where id = :'rec2';
select t.ok((public.employee_shift(:'rec2')).id = :'sh1' and (public.employee_shift(:'rec1')).id = :'sh2', 'an employee''s own shift wins over the department''s');
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.department_shift_set(:'dpr', :'sh2', true) as ovr \gset
reset role;
select t.ok(:ovr = 1 and (public.employee_shift(:'rec2')).id = :'sh2', 'department assignment can override personal shifts');
-- Ramadan for Muslims only, using the shift's Ramadan time; the break is not working time
update public.companies set ramadan_from = '2026-10-04', ramadan_to = '2026-10-08' where id = :'cid';
insert into public.attendance(company_id, employee_id, day, shift_id, check_in, check_out, source)
values (:'cid', :'rec2', '2026-10-05', :'sh2', public.riyadh_ts('2026-10-05', '20:00'), public.riyadh_ts('2026-10-06', '02:00'), 'hr'),
       (:'cid', :'rec1', '2026-10-05', :'sh2', public.riyadh_ts('2026-10-05', '20:00'), public.riyadh_ts('2026-10-06', '02:00'), 'hr'),
       (:'cid', :'rec1', '2026-10-12', :'sh2', public.riyadh_ts('2026-10-12', '14:00'), public.riyadh_ts('2026-10-12', '22:00'), 'hr');
select public.att_recalc(id) from public.attendance where employee_id in (:'rec1', :'rec2');
select t.ok((select late_min = 0 and early_min = 0 and worked_min = 330 from public.attendance where employee_id = :'rec2' and day = '2026-10-05'), 'a Muslim worker follows the shift''s Ramadan time 20:00–02:00 (break not counted)');
select t.ok((select late_min > 0 from public.attendance where employee_id = :'rec1' and day = '2026-10-05'), 'a non-Muslim worker keeps the normal shift in Ramadan');
select t.ok((select late_min = 0 and early_min = 0 and worked_min = 450 from public.attendance where employee_id = :'rec1' and day = '2026-10-12'), 'outside Ramadan: 14:00–22:00, 30-minute break not counted');
update public.companies set ramadan_from = null, ramadan_to = null where id = :'cid';
update public.employees set end_date = '2026-10-31', end_reason = 'resign' where id in (:'rec1', :'rec2');

-- ================= ROSTER, BULK RAISE, POLICIES, OT CONSENT PER YEAR, DASHBOARD =================
insert into public.departments(company_id, name) values (:'cid', 'المطبخ') returning id as dk \gset
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, hire_date, department_id, basic, housing, transport)
values (:'cid', '7851', 'طاهٍ 1', false, 'm', 'طاهٍ', '2026-01-01', :'dk', 4000, 1000, 0) returning id as k1 \gset
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, hire_date, department_id, basic, housing, transport)
values (:'cid', '7852', 'طاهٍ 2', true, 'm', 'طاهٍ', '2026-01-01', :'dk', 5000, 1250, 0) returning id as k2 \gset
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.roster_assign('$$ || :'cid' || $$', array['$$ || :'k1' || $$']::uuid[], '2026-09-06', '2026-09-19', array[]::uuid[], 7)$$, 'وردية', 'a rotation needs at least one shift');
select public.roster_assign(:'cid', array[:'k1', :'k2']::uuid[], '2026-09-06', '2026-09-19', array[:'sh1', :'sh2']::uuid[], 7) as nr \gset
select t.ok(:nr = 28, 'HR rotates two employees weekly between two shifts (2 x 14 days)');
reset role;
select t.ok((public.employee_shift_on(:'k1', '2026-09-08')).id = :'sh1' and (public.employee_shift_on(:'k1', '2026-09-15')).id = :'sh2', 'week 1 on shift 1, week 2 on shift 2');
select t.ok((public.employee_shift_on(:'k1', '2026-09-25')).id = :'sh_day', 'after the roster the usual shift applies');
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.roster_assign(:'cid', array[:'k1']::uuid[], '2026-09-12', '2026-09-12', array[null]::uuid[], 1);
reset role;
select t.ok(not public.is_workday(:'k1', '2026-09-12') and public.is_workday(:'k1', '2026-09-11'), 'a roster day off is not a working day (no absence)');
select t.ok(public.is_workday(:'k1', '2026-09-18'), 'a roster shift makes Friday a working day');
insert into public.attendance(company_id, employee_id, day, shift_id, check_in, check_out, source)
values (:'cid', :'k2', '2026-09-08', :'sh_day', public.riyadh_ts('2026-09-08', '01:00'), public.riyadh_ts('2026-09-08', '09:00'), 'hr') returning id as ka \gset
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.roster_assign(:'cid', array[:'k2']::uuid[], '2026-09-08', '2026-09-08', array[:'sh1']::uuid[], 7);
select t.ok((select shift_id = :'sh1' and late_min = 0 from public.attendance where id = :'ka'), 'a recorded day follows the new roster shift');
select t.ok((select count(*) from public.att_sheet(:'cid', '2026-09-12', '2026-09-12', :'k1') where status = 'off') = 1, 'the attendance sheet shows the roster day off');
select public.roster_clear(:'cid', array[:'k1', :'k2']::uuid[], '2026-09-06', '2026-09-19');
-- bulk raise
select t.err($$select public.salary_raise_bulk('$$ || :'cid' || $$', array['$$ || :'k1' || $$']::uuid[], -5, 0, false, current_date, 'تخفيض')$$, 'التخفيض', 'a bulk change cannot reduce wages');
select public.salary_raise_bulk(:'cid', array[:'k1', :'k2']::uuid[], 10, 0, true, current_date, 'زيادة سنوية 2026') as nraise \gset
select t.ok(:nraise = 2 and (select basic = 4400 and housing = 1100 from public.employees where id = :'k1') and (select basic = 5500 and housing = 1375 from public.employees where id = :'k2'),
  'bulk raise of 10% on basic and housing');
select t.ok((select count(*) from public.salary_history where employee_id in (:'k1', :'k2') and reason = 'زيادة سنوية 2026') = 2, 'each raise is in the salary history with the reason');
-- policies
select public.policy_save(:'cid', null, 'لائحة تنظيم العمل', 'Work regulation', 'نص لائحة تنظيم العمل المعتمدة من الوزارة', null, true) as pol \gset
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.policies where id = :'pol') = 1, 'employees see active policies');
select public.policy_ack(:'pol');
select t.ok((select count(*) from public.policy_acks where policy_id = :'pol') = 1, 'the employee acknowledges the policy');
select t.err($$select public.policy_save('$$ || :'cid' || $$', null, 'سياسة', null, 'نص طويل بما يكفي للاختبار', null, true)$$, '42501|غير مصرح', 'employees cannot publish policies');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.policy_save(:'cid', :'pol', 'لائحة تنظيم العمل', 'Work regulation', 'نص لائحة تنظيم العمل بعد التعديل', null, true);
select t.ok((select count(*) from public.policy_acks where policy_id = :'pol') = 0, 'a changed policy text needs a new acknowledgement');
-- dashboard
select public.hr_dashboard(:'cid') as dash \gset
select t.ok((:'dash'::jsonb->>'active')::int >= 5 and jsonb_array_length(:'dash'::jsonb->'months') = 12 and (:'dash'::jsonb ? 'today') and (:'dash'::jsonb->>'policies_unacked')::int >= 5,
  'the HR dashboard returns headcount, 12 months, today and what needs attention');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select public.hr_dashboard('$$ || :'cid' || $$')$$, '42501|غير مصرح', 'employees cannot open the HR dashboard');
reset role;
update public.employees set end_date = '2026-12-31', end_reason = 'resign' where id in (:'k1', :'k2');

-- ================= COMPANY ANALYTICS =================
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select public.company_analytics(:'cid', '2026-01-01', '2026-12-31') as an \gset
select t.ok((:'an'::jsonb ? 'exec') and (:'an'::jsonb ? 'finance') and (:'an'::jsonb ? 'sales') and (:'an'::jsonb ? 'supply') and (:'an'::jsonb ? 'hr') and (:'an'::jsonb ? 'departments'),
  'the owner gets every analytics section');
select t.ok((:'an'::jsonb->'exec'->>'revenue')::numeric > 0 and jsonb_array_length(:'an'::jsonb->'exec'->'months') = 12 and (:'an'::jsonb->>'prev_from') = '2025-01-01',
  'executive revenue, 12 months and the previous period of the same length');
select t.ok((:'an'::jsonb->'hr'->>'headcount')::int > 0 and jsonb_array_length(:'an'::jsonb->'departments') > 0, 'HR headcount and departments');
select t.err($$select public.company_analytics('$$ || :'cid' || $$', '2023-01-01', '2026-12-31')$$, 'سنتين', 'the period is at most two years');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.company_analytics(:'cid', '2026-01-01', '2026-12-31') as an \gset
select t.ok((:'an'::jsonb ? 'hr') and not (:'an'::jsonb ? 'exec') and not (:'an'::jsonb ? 'finance'), 'HR sees HR analytics but not the finances');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select public.company_analytics(:'cid', '2026-01-01', '2026-12-31') as an \gset
select t.ok(not (:'an'::jsonb ? 'hr') and not (:'an'::jsonb ? 'exec') and not (:'an'::jsonb ? 'sales'), 'an employee sees no company analytics');
reset role;
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select public.company_analytics(:'cid', '2026-01-01', '2026-12-31') as an \gset
select t.ok(jsonb_array_length(coalesce(:'an'::jsonb->'team', '[]')) > 0, 'a manager sees his own team');
reset role;
select set_config('request.jwt.claim.sub', :'u_other', false); set role authenticated;
select t.err($$select public.company_analytics('$$ || :'cid' || $$', '2026-01-01', '2026-12-31')$$, '42501|غير مصرح', 'outsiders cannot open analytics');
reset role;

-- ================= APPROVAL FLOW, TICKETS, EXIT/RE-ENTRY VISAS =================
insert into auth.users(id, email) values ('00000000-0000-0000-0000-000000000a10','x@test'),('00000000-0000-0000-0000-000000000a11','hrm@test');
\set u_x '00000000-0000-0000-0000-000000000a10'
\set u_hrm '00000000-0000-0000-0000-000000000a11'
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, manager_id, hire_date, basic, housing, transport, ticket_every, ticket_persons, ticket_dest, ticket_amount)
values (:'cid', '7901', 'سانجاي باتيل', false, 'm', 'فني', :'e_mgr', '2023-01-01', 5000, 1250, 0, 12, 3, 'مومباي', 1500) returning id as ex \gset
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, manager_id, hire_date, basic, housing, transport)
values (:'cid', '7902', 'نورة القحطاني', true, 'f', 'مديرة الموارد البشرية', :'e_gm', '2022-01-01', 14000, 3500, 0) returning id as ehm \gset
insert into public.members(company_id, user_id, role, employee_id) values (:'cid', :'u_x', 'employee', :'ex'), (:'cid', :'u_hrm', 'hr', :'ehm');
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.hr_manager_set('$$ || :'cid' || $$', '$$ || :'u_hrm' || $$')$$, '42501|غير مصرح', 'only the owner appoints the HR manager');
reset role;
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select t.err($$select public.hr_manager_set('$$ || :'cid' || $$', '$$ || :'u_fin' || $$')$$, 'الموارد البشرية', 'the HR manager is chosen from HR users');
select public.hr_manager_set(:'cid', :'u_hrm');
reset role;
-- one leave request with a ticket and a visa
select set_config('request.jwt.claim.sub', :'u_x', false); set role authenticated;
select (public.ticket_status(:'ex')).* \gset ts_
select t.ok(:ts_earned >= 3 and :ts_available = :ts_earned and :ts_persons = 3, 'ticket entitlement: one per completed year since hiring');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'leave', 'annual', current_date + 20, current_date + 34, null, '{"ticket":{"mode":"cash","persons":4}}')$$, 'المستحق', 'no more travellers than the contract allows');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'leave', 'annual', current_date + 20, current_date + 34, null, '{"visa":{"type":"x"}}')$$, 'مفردة', 'visa type is single or multiple');
select public.submit_request(:'cid', 'leave', 'annual', current_date + 20, current_date + 34, null, '{"ticket":{"mode":"cash","persons":2},"visa":{"type":"single"}}', 'إجازة سنوية مع تذكرة') as lr \gset
select t.ok((select route = array['m','p','h','f','g'] from public.requests where id = :'lr'), 'leave with a ticket: manager → HR → HR manager → finance → general manager');
select t.ok((public.request_timeline(:'lr')->'steps'->0->>'state') = 'current' and jsonb_array_length(public.request_timeline(:'lr')->'steps') = 5, 'the employee follows each step of his request');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'visa', null, current_date + 5, current_date + 9, null, '{"visa_type":"single"}')$$, 'لغير السعوديين', 'exit/re-entry visas are for non-Saudis');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'ticket', null, null, null, null, '{"mode":"cash"}')$$, 'عقدك', 'no ticket without a contract entitlement');
select t.err($$select public.request_timeline('$$ || :'lr' || $$')$$, '42501|غير مصرح', 'other employees cannot see the request journey');
reset role;
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select public.decide_request(:'lr', true, 'موافق');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok(public.decide_request(:'lr', true) = 'next:h', 'HR officer passes it to the HR manager');
select t.err($$select public.decide_request('$$ || :'lr' || $$', true)$$, '42501|غير مصرح', 'the HR officer cannot approve the HR-manager step');
reset role;
select set_config('request.jwt.claim.sub', :'u_hrm', false); set role authenticated;
select t.ok(public.decide_request(:'lr', true) = 'next:f', 'HR manager approves, then finance (a ticket is paid)');
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select public.decide_request(:'lr', true);
reset role;
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select t.ok(public.decide_request(:'lr', true) = 'approved', 'the general manager gives the final approval');
select t.ok((select (public.request_timeline(:'lr')->'steps'->2->>'by')) = 'نورة القحطاني', 'the journey shows who approved each step');
reset role;
select t.ok((select mode = 'cash' and persons = 2 and estimate = 3000 and status = 'approved' from public.travel_tickets where request_id = :'lr'), 'approval opens the ticket for payment (2 × 1500)');
select t.ok((select status = 'requested' and travel_on = current_date + 20 and return_on = current_date + 34 from public.exit_visas where request_id = :'lr'), 'approval opens the visa for HR to issue');
select set_config('request.jwt.claim.sub', :'u_x', false); set role authenticated;
select t.ok((public.ticket_status(:'ex')).available = :ts_available - 1, 'the ticket is deducted from the entitlement');
reset role;
select id as tk from public.travel_tickets where request_id = :'lr' \gset
select id as vz from public.exit_visas where request_id = :'lr' \gset
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.ticket_pay('$$ || :'tk' || $$', 2900, null, current_date)$$, '42501|غير مصرح', 'HR cannot pay the ticket');
select t.err($$select public.ticket_attach('$$ || :'tk' || $$', null, null)$$, 'البدل النقدي', 'a cash allowance has no ticket file');
select t.err($$select public.visa_record('$$ || :'vz' || $$', '4401234567', current_date + 1, current_date + 60)$$, 'أرفق التأشيرة', 'HR must attach the visa');
select t.err($$select public.visa_record('$$ || :'vz' || $$', '4401234567', current_date + 1, current_date + 60, null, '[{"name":"v.pdf","mime":"application/pdf","data":"aGVsbG8="}]')$$, 'ليس صورة', 'the visa file must really be a PDF or image');
select public.visa_record(:'vz', '4401234567', current_date + 1, current_date + 60, null, '[{"name":"visa.pdf","mime":"application/pdf","data":"JVBERi0xLjQKJSVFT0Y="}]');
reset role;
select set_config('request.jwt.claim.sub', :'u_x', false); set role authenticated;
select t.ok((select count(*) from public.travel_files where visa_id = :'vz') = 1 and (public.request_timeline(:'lr')->'visa'->>'delivered_at') is not null
  and jsonb_array_length(public.request_timeline(:'lr')->'visa'->'files') = 1, 'the attached visa reaches the employee in his request');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.travel_files where visa_id = :'vz') = 0, 'other employees cannot see the visa file');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.visa_close('$$ || :'vz' || $$', 'returned', null)$$, 'تاريخ العودة', 'return needs a date');
select public.visa_close(:'vz', 'returned', current_date + 33);
select t.ok((select status = 'returned' and visa_no = '4401234567' from public.exit_visas where id = :'vz'), 'HR records the visa and the return');
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select public.ticket_pay(:'tk', 2900, null, current_date, '1120');
select t.ok((select status = 'issued' and amount = 2900 from public.travel_tickets where id = :'tk')
  and (select sum(l.debit) from public.journal_lines l join public.journal_entries j on j.id = l.entry_id where j.source_id = :'tk' and l.account_code = '5220') = 2900, 'finance pays the ticket allowance: journal to travel tickets');
select t.err($$select public.ticket_pay('$$ || :'tk' || $$', 2900, null, current_date)$$, 'من قبل', 'a ticket is paid once');
reset role;
-- a booked ticket: HR attaches it, finance pays it separately
insert into public.travel_tickets(company_id, employee_id, mode, persons, estimate) values (:'cid', :'ex', 'ticket', 1, 1500) returning id as tk2 \gset
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.ticket_attach('$$ || :'tk2' || $$', 'PNR1', null)$$, 'أرفق التذكرة', 'HR must attach the ticket file');
select public.ticket_attach(:'tk2', 'PNR123', '[{"name":"ticket.png","mime":"image/png","data":"iVBORw0KGgo="}]');
select t.ok((select status = 'issued' and ref = 'PNR123' and delivered_at is not null and entry_id is null from public.travel_tickets where id = :'tk2'), 'HR attaches the booked ticket: delivered, not yet paid');
reset role;
select set_config('request.jwt.claim.sub', :'u_x', false); set role authenticated;
select t.ok((select count(*) from public.travel_files where ticket_id = :'tk2') = 1, 'the employee can open his ticket');
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select public.ticket_pay(:'tk2', 1450, null, current_date, '1120');
select t.ok((select status = 'issued' and amount = 1450 and entry_id is not null from public.travel_tickets where id = :'tk2'), 'finance pays the booked ticket');
select public.travel_board(:'cid') as tb \gset
select t.ok(jsonb_array_length(:'tb'::jsonb->'tickets') >= 1 and jsonb_array_length(:'tb'::jsonb->'visas') >= 1 and jsonb_array_length(:'tb'::jsonb->'due') >= 1, 'the travel desk lists tickets, visas and who is due');
reset role;
select set_config('request.jwt.claim.sub', :'u_x', false); set role authenticated;
select t.err($$select public.travel_board('$$ || :'cid' || $$')$$, '42501|غير مصرح', 'employees cannot open the travel desk');
reset role;
-- the same person at two steps approves once
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select public.hr_manager_set(:'cid', :'u_hr');
reset role;
select set_config('request.jwt.claim.sub', :'u_x', false); set role authenticated;
select public.submit_request(:'cid', 'ticket', null, null, null, null, '{"mode":"ticket","persons":1}') as tr2 \gset
reset role;
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated; select public.decide_request(:'tr2', true); reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok(public.decide_request(:'tr2', true) = 'next:f', 'HR officer who is also the HR manager approves both steps at once');
select t.ok((select count(*) from public.request_actions where request_id = :'tr2' and note like 'اعتماد تلقائي%') = 1, 'the automatic step is recorded');
-- company settings: routes and a deadline per step
select t.err($$select public.workflow_set('$$ || :'cid' || $$', 'ticket', array['m','p'])$$, 'المالية', 'a paid request must pass finance');
select t.ok(public.workflow_set(:'cid', 'visa', array['p','m']) = array['m','p'], 'HR sets the visa route; steps keep their order');
select public.request_sla_set(:'cid', 2);
reset role;
update public.requests set step_at = now() - interval '3 days' where id = :'tr2';
select set_config('request.jwt.claim.sub', :'u_x', false); set role authenticated;
select t.ok((public.request_timeline(:'tr2')->'steps'->3->>'overdue')::boolean, 'a step waiting longer than the company deadline is flagged');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.workflow_set(:'cid', 'visa', null); select public.request_sla_set(:'cid', null);
reset role;
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated; select public.hr_manager_set(:'cid', null); reset role;
update public.requests set status = 'cancelled' where id = :'tr2';
update public.employees set end_date = '2026-12-31', end_reason = 'resign' where id in (:'ex', :'ehm');

-- ================= SALES CYCLE (quote → order → delivery → invoice) =================
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
insert into public.items(company_id, code, name, type, unit, sale_price) values (:'cid','SC-01','شاشة عرض','stock','حبة',1000) returning id as sci1 \gset
insert into public.items(company_id, code, name, type, unit, sale_price) values (:'cid','SC-02','تركيب','service','ساعة',100) returning id as sci2 \gset
select public.post_purchase_bill(:'cid', jsonb_build_object('party', :'s1', 'ref','SC-B1', 'date', current_date - 3,
  'lines', jsonb_build_array(jsonb_build_object('item', :'sci1','qty',10,'price',600)))) as scb \gset
-- quotation with a line discount
select public.sales_doc_save(:'cid', jsonb_build_object('kind','quote','party', :'c1','date', current_date,'valid_until', current_date + 14,'terms','الأسعار شاملة التركيب',
  'lines', jsonb_build_array(jsonb_build_object('item', :'sci1','qty',4,'price',1000,'disc',12.5), jsonb_build_object('item', :'sci2','qty',3,'price',100)))) as q1 \gset
select t.ok((select no from public.sales_orders where id = :'q1') ~ '^QT-\d{4}$', 'quotation numbered QT-');
select t.eq((select subtotal from public.sales_orders where id = :'q1'), 3800, 'quote subtotal after 12.5% line discount (4×875 + 300)');
select t.eq((select discount from public.sales_orders where id = :'q1'), 500, 'quote discount total');
select t.eq((select total from public.sales_orders where id = :'q1'), 4370, 'quote total incl. VAT');
select t.err($$select public.sales_doc_save('$$ || :'cid' || $$', '{"kind":"quote","party":"$$ || :'c1' || $$","valid_until":"2000-01-01","lines":[{"item":"$$ || :'sci1' || $$","qty":1,"price":1}]}')$$, 'انتهاء', 'quote validity must be after its date');
select t.err($$select public.sales_doc_save('$$ || :'cid' || $$', '{"kind":"quote","party":"$$ || :'c1' || $$","valid_until":"2099-01-01","lines":[{"item":"$$ || :'sci1' || $$","qty":1,"price":10,"disc":120}]}')$$, 'الخصم', 'discount over 100% rejected');
select t.err($$select public.sales_doc_save('$$ || :'cid' || $$', '{"kind":"quote","party":"$$ || :'s1' || $$","valid_until":"2099-01-01","lines":[{"item":"$$ || :'sci1' || $$","qty":1,"price":1}]}')$$, 'العميل', 'supplier cannot receive a quotation');
-- edit while open
select public.sales_doc_save(:'cid', jsonb_build_object('id', :'q1', 'kind','quote','party', :'c1','date', current_date,'valid_until', current_date + 14,
  'lines', jsonb_build_array(jsonb_build_object('item', :'sci1','qty',5,'price',1000,'disc',12.5), jsonb_build_object('item', :'sci2','qty',3,'price',100))));
select t.eq((select total from public.sales_orders where id = :'q1'), 5376.25, 'edited quote recalculated (5×875 + 300, +VAT)');
select t.ok((select count(*) from public.sales_order_lines where order_id = :'q1') = 2, 'edit replaces lines, no duplicates');
-- reject / accept
select public.sales_doc_save(:'cid', jsonb_build_object('kind','quote','party', :'c2','valid_until', current_date + 7,'lines', jsonb_build_array(jsonb_build_object('item', :'sci2','qty',1,'price',100)))) as q2 \gset
select t.err($$select public.quote_decide('$$ || :'q2' || $$', false, '')$$, 'سبب', 'rejection needs a reason');
select public.quote_decide(:'q2', false, 'السعر مرتفع');
select t.err($$select public.quote_to_order('$$ || :'q2' || $$')$$, 'مفتوح أو مقبول', 'rejected quote cannot become an order');
select public.quote_decide(:'q1', true);
select public.quote_to_order(:'q1') as so1 \gset
select t.ok((select kind||'|'||status||'|'||quote_id from public.sales_orders where id = :'so1') = 'order|open|' || :'q1', 'order created from the quote and linked');
select t.ok((select status from public.sales_orders where id = :'q1') = 'converted', 'quote marked converted');
select t.err($$select public.quote_to_order('$$ || :'q1' || $$')$$, 'مفتوح أو مقبول', 'a quote converts only once');
select t.eq((select total from public.sales_orders where id = :'so1'), 5376.25, 'order carries the quote total');
select t.err($$select public.sales_doc_save('$$ || :'cid' || $$', '{"id":"$$ || :'q1' || $$","kind":"quote","party":"$$ || :'c1' || $$","valid_until":"2099-01-01","lines":[{"item":"$$ || :'sci1' || $$","qty":1,"price":1}]}')$$, 'المفتوح', 'converted quote is locked');
reset role;
-- storekeeper delivers; cannot see quotes or invoice
select set_config('request.jwt.claim.sub', :'u_store', false); set role authenticated;
select t.ok((select count(*) from public.sales_orders where kind = 'quote') = 0 and (select count(*) from public.sales_orders where id = :'so1') = 1, 'storekeeper sees orders but not quotations');
select id as sol1 from public.sales_order_lines where order_id = :'so1' and item_id = :'sci1' \gset
select id as sol2 from public.sales_order_lines where order_id = :'so1' and item_id = :'sci2' \gset
select t.err($$select public.delivery_post('$$ || :'so1' || $$', '{"lines":[{"line":$$ || :'sol1' || $$,"qty":6}]}')$$, 'المتبقي للتسليم', 'cannot deliver more than ordered');
select public.delivery_post(:'so1', jsonb_build_object('received_by','أحمد — مستودع العميل','lines', jsonb_build_array(jsonb_build_object('line', :'sol1','qty',3)))) as dn1 \gset
select t.ok((select no from public.delivery_notes where id = :'dn1') ~ '^DN-\d{4}$', 'delivery note numbered DN-');
select t.eq((select delivered from public.sales_order_lines where id = :'sol1'), 3, 'order line delivered qty updated');
select t.eq((select sum(qty) from public.stock_moves where item_id = :'sci1'), 10, 'delivery alone does not move stock (moves at invoicing)');
select t.err($$select public.order_invoice('$$ || :'so1' || $$', '{}')$$, 'غير مصرح', 'storekeeper cannot invoice');
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
-- delivered-not-invoiced goods are reserved: a direct sale + this delivery cannot exceed what is on the shelf
select public.sales_doc_save(:'cid', jsonb_build_object('kind','order','party', :'c2','lines', jsonb_build_array(jsonb_build_object('item', :'sci1','qty',9,'price',1000)))) as so2 \gset
select t.ok((select no from public.sales_orders where id = :'so2') ~ '^SO-\d{4}$', 'direct sales order numbered SO-');
select id as so2l from public.sales_order_lines where order_id = :'so2' \gset
select t.err($$select public.delivery_post('$$ || :'so2' || $$', '{"lines":[{"line":$$ || :'so2l' || $$,"qty":8}]}')$$, 'لا تكفي', 'delivery checks shelf stock net of goods delivered but not invoiced');
-- partial invoice of the first order
select public.order_invoice(:'so1', jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line', :'sol1','qty',3)))) as inv1 \gset
select t.eq((select total from public.sales_invoices where id = :'inv1'), 3018.75, 'invoice from order at net price (3×875 + VAT)');
select t.ok((select order_id from public.sales_invoices where id = :'inv1') = :'so1'::uuid, 'invoice linked to its order');
select t.ok((select order_line from public.sales_invoice_lines where invoice_id = :'inv1') = :'sol1'::bigint, 'invoice line tied back to the order line');
select t.eq((select sum(qty) from public.stock_moves where item_id = :'sci1'), 7, 'invoicing moves stock');
select t.ok((select status from public.sales_orders where id = :'so1') = 'open', 'partly invoiced order stays open');
select t.err($$select public.sales_doc_save('$$ || :'cid' || $$', '{"id":"$$ || :'so1' || $$","kind":"order","party":"$$ || :'c1' || $$","lines":[{"item":"$$ || :'sci1' || $$","qty":1,"price":1}]}')$$, 'بدأ', 'order cannot be edited after delivery/invoicing');
-- invoice the rest (default = everything left)
select public.order_invoice(:'so1', '{}') as inv2 \gset
select t.eq((select total from public.sales_invoices where id = :'inv2'), 2357.50, 'remainder invoiced (2×875 + 300 + VAT)');
select t.ok((select status from public.sales_orders where id = :'so1') = 'closed', 'fully invoiced order closes');
select t.err($$select public.order_invoice('$$ || :'so1' || $$', '{}')$$, 'مفتوح', 'closed order cannot be invoiced again');
select t.ok(public.delivery_post(:'so1', jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line', :'sol2','qty',1)))) is not null, 'fully invoiced order can still deliver what is left');
select t.eq((select sum(total) from public.sales_invoices where order_id = :'so1'), 5376.25, 'invoices add up to the order total');
-- voiding an order invoice gives quantities back and reopens the order
select public.void_sales_invoice(:'inv2', 'خطأ في الفوترة');
select t.ok((select status from public.sales_orders where id = :'so1') = 'open', 'voiding an order invoice reopens the order');
select t.eq((select invoiced from public.sales_order_lines where id = :'sol1'), 3, 'invoiced qty given back on void');
select t.eq((select invoiced from public.sales_order_lines where id = :'sol2'), 0, 'service line invoiced qty given back on void');
-- invoice ahead of delivery, then deliver: the line's own invoiced qty is not double-counted against stock
select public.delivery_post(:'so1', jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line', :'sol1','qty',2), jsonb_build_object('line', :'sol2','qty',2)))) as dn2 \gset
select t.eq((select delivered from public.sales_order_lines where id = :'sol1'), 5, 'second delivery completes the line');
select public.delivery_void(:'dn2', 'تسليم مكرر');
select t.eq((select delivered from public.sales_order_lines where id = :'sol1'), 3, 'voided delivery gives the qty back');
select t.err($$select public.delivery_void('$$ || :'dn2' || $$', 'مرة ثانية')$$, 'مسبقاً', 'delivery note voided only once');
select t.err($$update public.delivery_note_lines set qty = 1$$, 'permission denied', 'delivery lines are not writable directly');
select t.err($$update public.sales_orders set total = 1 where id = '$$ || :'so1' || $$'$$, 'permission denied', 'orders are written only through RPCs');
-- cancel: untouched order → cancelled; touched → closed
select t.ok(public.order_cancel(:'so2', 'العميل ألغى الطلب') = 'cancelled', 'untouched order is cancelled');
select t.ok(public.order_cancel(:'so1', 'لن يُستكمل الباقي') = 'closed', 'partly done order is closed, not cancelled');
select t.err($$select public.delivery_post('$$ || :'so1' || $$', '{"lines":[{"line":$$ || :'sol1' || $$,"qty":1}]}')$$, 'مفتوح', 'closed order takes no more deliveries');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.sales_orders) = 0 and (select count(*) from public.delivery_notes) = 0, 'employee sees no quotes, orders or deliveries');
select t.err($$select public.sales_doc_save('$$ || :'cid' || $$', '{"kind":"quote"}')$$, 'غير مصرح', 'employee cannot create quotations');
reset role;
select set_config('request.jwt.claim.sub', :'u_other', false); set role authenticated;
select t.err($$select public.quote_decide('$$ || :'q1' || $$', true)$$, 'غير موجود|غير مصرح', 'outsider cannot touch another company''s quotes');
reset role;
select set_config('request.jwt.claim.sub', null, false); set role anon;
select t.err($$select public.order_invoice('$$ || :'so1' || $$', '{}')$$, 'permission denied', 'anon cannot call sales-cycle RPCs');
reset role;

-- ================= PURCHASE CYCLE (request → PO → receipt → bill) =================
-- who may raise a purchase request: managers by default; flagged employees in «selected» mode; everyone in «all»
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok(not public.my_purchase_allowed(:'cid'), 'ordinary employee may not raise purchase requests by default');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'purchase', null, null, null, null, '{"lines":[{"desc":"ورق","qty":1,"price":1}]}')$$, 'مدراء الأقسام', 'server rejects a purchase request from an ordinary employee');
reset role;
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select t.ok(public.my_purchase_allowed(:'cid'), 'a department manager may raise purchase requests');
select t.err($$select public.purchase_requesters_set('$$ || :'cid' || $$', 'all')$$, '42501|غير مصرح', 'a manager cannot change who raises purchase requests');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select public.purchase_requesters_set(:'cid', 'selected');
update public.employees set can_request_purchase = true where id = (select employee_id from public.members where user_id = :'u_emp' and company_id = :'cid');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok(public.my_purchase_allowed(:'cid'), 'flagged employee may raise purchase requests in «selected» mode');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'purchase', null, null, null, null, '{"lines":[]}')$$, 'بنداً', 'purchase request needs lines');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'purchase', null, null, null, null, '{"lines":[{"desc":"ورق","qty":0,"price":1}]}')$$, 'الكمية', 'purchase request qty > 0');
select public.submit_request(:'cid', 'purchase', null, current_date + 5, null, 99999, '{"lines":[{"desc":"شاشة عرض 27 بوصة","qty":4,"price":700},{"desc":"صيانة المكيفات","qty":1,"price":350}]}', 'لقسم المبيعات') as pr1 \gset
select t.eq((select amount from public.requests where id = :'pr1'), 3150, 'purchase request total is computed from its lines (not taken from the client)');
select t.ok((select 'f' = any(route) and route[cardinality(route)] = 'g' from public.requests where id = :'pr1'), 'purchase request goes through finance and the GM');
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.err($$select public.po_save('$$ || :'cid' || $$', '{"party":"$$ || :'s1' || $$","request":"$$ || :'pr1' || $$","lines":[{"account":"5500","qty":1,"price":1}]}')$$, 'غير معتمد', 'PO cannot use a request that is not approved yet');
reset role;
select set_config('request.jwt.claim.sub', :'u_mgr', false); set role authenticated;
select public.decide_request(:'pr1', true) where (select route[step+1] from public.requests where id = :'pr1') = 'm';
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select public.decide_request(:'pr1', true) where (select route[step+1] from public.requests where id = :'pr1') = 'f';
reset role;
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select public.decide_request(:'pr1', true) where (select route[step+1] from public.requests where id = :'pr1') = 'g';
select t.ok((select status from public.requests where id = :'pr1') = 'approved', 'purchase request approved through its route');
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.ok((select count(*) from public.purchase_requests(:'cid') where id = :'pr1' and po_id is null) = 1, 'purchasing sees the approved request waiting for a PO');
insert into public.items(company_id, code, name, type, unit, sale_price) values (:'cid','PC-01','شاشة 27','stock','حبة',1100) returning id as pci1 \gset
insert into public.items(company_id, code, name, type, unit, sale_price) values (:'cid','PC-02','صيانة دورية','service','زيارة',0) returning id as pci2 \gset
select t.err($$select public.po_save('$$ || :'cid' || $$', '{"party":"$$ || :'c1' || $$","lines":[{"account":"5500","qty":1,"price":1}]}')$$, 'المورد', 'customer cannot receive a purchase order');
select t.err($$select public.po_save('$$ || :'cid' || $$', '{"party":"$$ || :'s1' || $$","lines":[{"account":"1120","qty":1,"price":1}]}')$$, 'حساب', 'PO line cannot debit the bank');
select public.po_save(:'cid', jsonb_build_object('party', :'s1', 'request', :'pr1', 'expected', current_date + 3, 'lines', jsonb_build_array(
  jsonb_build_object('item', :'pci1', 'qty', 4, 'price', 680), jsonb_build_object('item', :'pci2', 'qty', 1, 'price', 350), jsonb_build_object('account', '5400', 'qty', 1, 'price', 100, 'desc', 'شحن')))) as po1 \gset
select t.ok((select no from public.purchase_orders where id = :'po1') ~ '^PO-\d{4}$', 'purchase order numbered PO-');
select t.eq((select total from public.purchase_orders where id = :'po1'), 3645.50, 'PO total (2,720 + 350 + 100 = 3,170 + VAT)');
select t.err($$select public.po_save('$$ || :'cid' || $$', '{"party":"$$ || :'s1' || $$","request":"$$ || :'pr1' || $$","lines":[{"account":"5500","qty":1,"price":1}]}')$$, 'من قبل', 'one PO per purchase request');
select t.ok((select po_no from public.purchase_requests(:'cid') where id = :'pr1') is not null, 'request shows its PO');
select id as pol1 from public.purchase_order_lines where order_id = :'po1' and item_id = :'pci1' \gset
select id as pol2 from public.purchase_order_lines where order_id = :'po1' and item_id = :'pci2' \gset
select id as pol3 from public.purchase_order_lines where order_id = :'po1' and account_code = '5400' \gset
-- bill before receipt: stock lines cannot be billed yet, service/expense can
select t.err($$select public.po_bill('$$ || :'po1' || $$', '{"lines":[{"line":$$ || :'pol1' || $$,"qty":1}]}')$$, 'المستلم', 'three-way match: stock cannot be billed before it is received');
reset role;
select set_config('request.jwt.claim.sub', :'u_store', false); set role authenticated;
select t.ok((select count(*) from public.purchase_orders where id = :'po1') = 1, 'storekeeper sees purchase orders');
select t.err($$select public.grn_post('$$ || :'po1' || $$', '{"lines":[{"line":$$ || :'pol1' || $$,"qty":5}]}')$$, 'المتبقي للاستلام', 'cannot receive more than ordered');
select t.err($$select public.grn_post('$$ || :'po1' || $$', '{"lines":[{"line":$$ || :'pol3' || $$,"qty":1}]}')$$, 'تُفوتر مباشرة', 'expense lines are not received');
select public.grn_post(:'po1', jsonb_build_object('supplier_doc', 'DN-7781', 'lines', jsonb_build_array(jsonb_build_object('line', :'pol1', 'qty', 3)))) as grn1 \gset
select t.ok((select no from public.goods_receipts where id = :'grn1') ~ '^GRN-\d{4}$', 'goods receipt numbered GRN-');
select t.eq((select sum(qty) from public.stock_moves where item_id = :'pci1'), 3, 'receipt brings stock in');
select t.eq((select sum(value) from public.stock_moves where item_id = :'pci1'), 2040, 'stock valued at the PO price');
select t.err($$select public.po_bill('$$ || :'po1' || $$', '{}')$$, 'غير مصرح', 'storekeeper cannot bill');
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.eq((select coalesce(sum(debit - credit), 0) from public.journal_lines where company_id = :'cid' and account_code = '2150'), -2040, 'goods received not invoiced (2150) holds the receipt');
-- received goods can be sold before the supplier bill arrives
select public.post_sales_invoice(:'cid', jsonb_build_object('party', :'c1', 'lines', jsonb_build_array(jsonb_build_object('item', :'pci1', 'qty', 1, 'price', 1100)))) as pcs \gset
select t.eq((select sum(qty) from public.stock_moves where item_id = :'pci1'), 2, 'received stock sold before the bill');
-- bill everything billable: 3 received screens + service + expense
select t.err($$select public.po_bill('$$ || :'po1' || $$', '{"lines":[{"line":$$ || :'pol1' || $$,"qty":4}]}')$$, 'القابلة للفوترة', 'cannot bill more than received');
select public.po_bill(:'po1', jsonb_build_object('ref', 'INV-S-5501')) as pb1 \gset
select t.eq((select total from public.purchase_bills where id = :'pb1'), 2863.50, 'bill = 3×680 + 350 + 100 + VAT');
select t.ok((select order_id from public.purchase_bills where id = :'pb1') = :'po1'::uuid, 'bill linked to its PO');
select t.eq((select coalesce(sum(debit - credit), 0) from public.journal_lines where company_id = :'cid' and account_code = '2150'), 0, 'bill clears goods received not invoiced');
select t.eq((select sum(qty) from public.stock_moves where item_id = :'pci1'), 2, 'billing does not move stock again');
select t.ok((select status from public.purchase_orders where id = :'po1') = 'open', 'PO stays open while a screen is still to come');
select t.err($$select public.po_bill('$$ || :'po1' || $$', '{"ref":"INV-S-5501"}')$$, 'مسجّل', 'same supplier invoice number rejected');
-- last screen arrives and is billed → PO closes
select public.grn_post(:'po1', jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line', :'pol1', 'qty', 1)))) as grn2 \gset
select public.po_bill(:'po1', jsonb_build_object('ref', 'INV-S-5502')) as pb2 \gset
select t.ok((select status from public.purchase_orders where id = :'po1') = 'closed', 'fully received and billed PO closes');
select t.err($$select public.grn_void('$$ || :'grn2' || $$', 'خطأ إدخال')$$, 'فُوترت', 'cannot void a receipt that was already billed');
select public.void_purchase_bill(:'pb2', 'رقم خاطئ');
select t.ok((select status from public.purchase_orders where id = :'po1') = 'open', 'voiding a PO bill reopens the PO');
select t.eq((select billed from public.purchase_order_lines where id = :'pol1'), 3, 'billed qty given back on void');
select public.grn_void(:'grn2', 'إدخال مكرر');
select t.eq((select received from public.purchase_order_lines where id = :'pol1'), 3, 'voided receipt gives the qty back');
select t.eq((select sum(qty) from public.stock_moves where item_id = :'pci1'), 2, 'voided receipt takes the stock out');
select t.eq((select coalesce(sum(debit - credit), 0) from public.journal_lines where company_id = :'cid' and account_code = '2150'), 0, 'voided receipt reverses its 2150 entry');
select t.err($$update public.purchase_orders set total = 1$$, 'permission denied', 'POs are written only through RPCs');
select t.ok(public.po_cancel(:'po1', 'لن يورد المورد الباقي') = 'closed', 'partly done PO is closed, not cancelled');
select public.po_save(:'cid', jsonb_build_object('party', :'s2', 'lines', jsonb_build_array(jsonb_build_object('account', '5300', 'qty', 1, 'price', 500)))) as po2 \gset
select t.ok(public.po_cancel(:'po2', 'غير مطلوب') = 'cancelled', 'untouched PO is cancelled');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.purchase_orders) = 0 and (select count(*) from public.goods_receipts) = 0, 'employee sees no POs or receipts');
select t.err($$select * from public.purchase_requests('$$ || :'cid' || $$')$$, 'غير مصرح', 'employee cannot list purchasing''s request queue');
reset role;
select set_config('request.jwt.claim.sub', null, false); set role anon;
select t.err($$select public.po_bill('$$ || :'po1' || $$', '{}')$$, 'permission denied', 'anon cannot call purchase RPCs');
reset role;

-- ================= INVENTORY (warehouses, transfers, batches & expiry, counts, reorder) =================
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select id as whm from public.warehouses where company_id = :'cid' and is_default \gset
select t.ok((select code from public.warehouses where id = :'whm') = 'MAIN', 'every company has a default main warehouse');
select t.ok((select count(*) from public.stock_moves where company_id = :'cid' and warehouse_id is null) = 0, 'all existing stock moves belong to a warehouse');
select public.warehouse_save(:'cid', '{"code":"jed","name":"مستودع جدة","name_en":"Jeddah warehouse"}') as wh2 \gset
select t.ok((select code from public.warehouses where id = :'wh2') = 'JED', 'warehouse created (code upper-cased)');
select t.err($$select public.warehouse_save('$$ || :'cid' || $$', '{"code":"JED","name":"مكرر"}')$$, 'مستخدم', 'warehouse code is unique');
insert into public.items(company_id, code, name, type, unit, sale_price, reorder_level, reorder_qty) values (:'cid','INV-01','كرتون مياه','stock','كرتون',20,30,100) returning id as ii1 \gset
insert into public.items(company_id, code, name, type, unit, sale_price, track_expiry) values (:'cid','INV-02','حليب طويل الأجل','stock','علبة',8,true) returning id as ii2 \gset
-- purchase into MAIN, transfer to Jeddah
select public.post_purchase_bill_wh(:'cid', jsonb_build_object('party', :'s1', 'ref', 'INV-B1', 'warehouse', :'whm', 'lines', jsonb_build_array(jsonb_build_object('item', :'ii1', 'qty', 50, 'price', 10)))) as ib1 \gset
select t.eq((select coalesce(sum(qty), 0) from public.stock_moves where item_id = :'ii1' and warehouse_id = :'whm'), 50, 'bill puts stock in the chosen warehouse');
select t.err($$select public.stock_transfer('$$ || :'cid' || $$', '{"from":"$$ || :'whm' || $$","to":"$$ || :'wh2' || $$","lines":[{"item":"$$ || :'ii1' || $$","qty":60}]}')$$, 'المتوفرة', 'cannot transfer more than the warehouse holds');
select t.err($$select public.stock_transfer('$$ || :'cid' || $$', '{"from":"$$ || :'whm' || $$","to":"$$ || :'whm' || $$","lines":[{"item":"$$ || :'ii1' || $$","qty":1}]}')$$, 'مختلفين', 'transfer needs two different warehouses');
select public.stock_transfer(:'cid', jsonb_build_object('from', :'whm', 'to', :'wh2', 'lines', jsonb_build_array(jsonb_build_object('item', :'ii1', 'qty', 20)))) as tr1 \gset
select t.ok((select no from public.stock_transfers where id = :'tr1') ~ '^TRF-\d{4}$', 'transfer numbered TRF-');
select t.ok((select coalesce(sum(qty), 0) from public.stock_moves where item_id = :'ii1' and warehouse_id = :'whm') = 30 and (select coalesce(sum(qty), 0) from public.stock_moves where item_id = :'ii1' and warehouse_id = :'wh2') = 20, 'transfer moves quantity between warehouses');
select t.eq((select sum(value) from public.stock_moves where item_id = :'ii1'), 500, 'transfer does not change the stock value');
-- sell from Jeddah
select t.err($$select public.post_sales_invoice_wh('$$ || :'cid' || $$', '{"party":"$$ || :'c1' || $$","warehouse":"$$ || :'wh2' || $$","lines":[{"item":"$$ || :'ii1' || $$","qty":25,"price":20}]}')$$, 'مستودع جدة', 'sale checks the chosen warehouse, not the company total');
select public.post_sales_invoice_wh(:'cid', jsonb_build_object('party', :'c1', 'warehouse', :'wh2', 'lines', jsonb_build_array(jsonb_build_object('item', :'ii1', 'qty', 15, 'price', 20)))) as is1 \gset
select t.ok((select warehouse_id from public.sales_invoices where id = :'is1') = :'wh2'::uuid and (select coalesce(sum(qty), 0) from public.stock_moves where item_id = :'ii1' and warehouse_id = :'wh2') = 5, 'sale issues from its warehouse');
select t.eq((select sum(cost) from public.sales_invoice_lines where invoice_id = :'is1'), 150, 'cost of sales at company average cost');
select public.void_sales_invoice(:'is1', 'إلغاء تجريبي');
select t.eq((select coalesce(sum(qty), 0) from public.stock_moves where item_id = :'ii1' and warehouse_id = :'wh2'), 20, 'void returns the stock to the same warehouse');
-- warehouse with stock cannot be deactivated; default cannot be deactivated
select t.err($$select public.warehouse_save('$$ || :'cid' || $$', '{"id":"$$ || :'wh2' || $$","code":"JED","name":"مستودع جدة","active":false}')$$, 'رصيد', 'warehouse with stock cannot be deactivated');
select t.err($$select public.warehouse_save('$$ || :'cid' || $$', '{"id":"$$ || :'whm' || $$","code":"MAIN","name":"الرئيسي","active":false}')$$, 'الافتراضي', 'default warehouse cannot be deactivated');
-- adjustment in a warehouse
select public.stock_adjust(:'cid', :'ii1', current_date, -2, null, 'تالف في جدة', :'wh2');
select t.eq((select coalesce(sum(qty), 0) from public.stock_moves where item_id = :'ii1' and warehouse_id = :'wh2'), 18, 'adjustment books against the chosen warehouse');
-- batches & expiry through a PO receipt
select public.po_save_wh(:'cid', jsonb_build_object('party', :'s1', 'warehouse', :'wh2', 'lines', jsonb_build_array(jsonb_build_object('item', :'ii2', 'qty', 100, 'price', 5)))) as ipo \gset
select t.ok((select warehouse_id from public.purchase_orders where id = :'ipo') = :'wh2'::uuid, 'PO keeps its warehouse');
select id as ipol from public.purchase_order_lines where order_id = :'ipo' \gset
select t.err($$select public.grn_post('$$ || :'ipo' || $$', '{"lines":[{"line":$$ || :'ipol' || $$,"qty":40}]}')$$, 'الصلاحية', 'tracked item needs an expiry date on receipt');
select public.grn_post(:'ipo', jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line', :'ipol', 'qty', 40, 'batch', 'L-LATE', 'expiry', current_date + 200))));
select public.grn_post(:'ipo', jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line', :'ipol', 'qty', 60, 'batch', 'L-SOON', 'expiry', current_date + 20))));
select t.ok((select sum(qty) from public.stock_batches where item_id = :'ii2' and warehouse_id = :'wh2') = 100, 'receipts create batches in the PO warehouse');
select public.post_sales_invoice_wh(:'cid', jsonb_build_object('party', :'c1', 'warehouse', :'wh2', 'lines', jsonb_build_array(jsonb_build_object('item', :'ii2', 'qty', 70, 'price', 8)))) as is2 \gset
select t.ok((select qty from public.stock_batches where item_id = :'ii2' and batch = 'L-SOON') = 0 and (select qty from public.stock_batches where item_id = :'ii2' and batch = 'L-LATE') = 30, 'sales take the earliest expiry first (FEFO)');
select t.ok((select count(*) from public.expiry_list(:'cid', 60) where item_id = :'ii2') = 0 and (select count(*) from public.expiry_list(:'cid', 365) where item_id = :'ii2' and batch = 'L-LATE') = 1, 'expiry report lists batches by days left');
select public.stock_transfer(:'cid', jsonb_build_object('from', :'wh2', 'to', :'whm', 'lines', jsonb_build_array(jsonb_build_object('item', :'ii2', 'qty', 10))));
select t.ok((select qty from public.stock_batches where item_id = :'ii2' and warehouse_id = :'whm' and batch = 'L-LATE') = 10, 'transfer carries the batch and its expiry');
-- stock count
select public.count_open(:'cid', :'whm', 'جرد ربع سنوي') as sc1 \gset
select t.ok((select no from public.stock_counts where id = :'sc1') ~ '^STC-\d{4}$', 'stock count numbered STC-');
select t.err($$select public.count_open('$$ || :'cid' || $$', '$$ || :'whm' || $$')$$, 'مفتوح', 'one open count per warehouse');
select t.eq((select system_qty from public.stock_count_lines where count_id = :'sc1' and item_id = :'ii1'), 30, 'count sheet snapshots the warehouse quantity');
select public.count_save(:'sc1', (select jsonb_agg(jsonb_build_object('id', id, 'counted', case when item_id = :'ii1'::uuid then 27 end)) from public.stock_count_lines where count_id = :'sc1'));
select t.eq((select (public.count_post(:'sc1')->>'loss')::numeric), 30, 'count posts a 3-unit shortage at average cost (3 × 10)');
select t.eq((select coalesce(sum(qty), 0) from public.stock_moves where item_id = :'ii1' and warehouse_id = :'whm'), 27, 'warehouse quantity set to the counted quantity');
select t.ok((select count(*) from public.journal_entries where source_id = :'sc1') = 1, 'count shortage is journalised (5600 / 1300)');
select t.err($$select public.count_post('$$ || :'sc1' || $$')$$, 'مرحّل', 'a count posts once');
-- reorder
update public.items set reorder_level = 50 where id = :'ii1';
select t.ok((select suggested from public.reorder_list(:'cid') where item_id = :'ii1') = 100, 'item at/below reorder level is suggested with its reorder qty');
select public.po_save_wh(:'cid', jsonb_build_object('party', :'s1', 'lines', jsonb_build_array(jsonb_build_object('item', :'ii1', 'qty', 100, 'price', 10))));
select t.ok((select count(*) from public.reorder_list(:'cid') where item_id = :'ii1') = 0, 'quantity already on order removes the suggestion');
reset role;
select set_config('request.jwt.claim.sub', :'u_store', false); set role authenticated;
select t.ok((select count(*) from public.warehouses) >= 2, 'storekeeper sees warehouses');
select public.stock_transfer(:'cid', jsonb_build_object('from', :'whm', 'to', :'wh2', 'lines', jsonb_build_array(jsonb_build_object('item', :'ii1', 'qty', 1))));
select t.ok(true, 'storekeeper can transfer stock');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.warehouses) = 0 and (select count(*) from public.stock_counts) = 0, 'employee sees no warehouses or counts');
select t.err($$select public.stock_transfer('$$ || :'cid' || $$', '{}')$$, 'غير مصرح', 'employee cannot transfer stock');
select t.err($$insert into public.warehouses(company_id, code, name) values ('$$ || :'cid' || $$', 'X', 'xx')$$, 'permission denied|row-level', 'warehouses are written only through RPCs');
reset role;
select set_config('request.jwt.claim.sub', null, false); set role anon;
select t.err($$select public.count_post('$$ || :'sc1' || $$')$$, 'permission denied', 'anon cannot post counts');
reset role;

-- ================= FINANCE PLUS (cost centers, budgets, cash flow, bank reconciliation, fixed assets, period closing) =================
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
-- cost centers
select public.cc_save(:'cid', '{"code":"ryd","name":"فرع الرياض","name_en":"Riyadh branch"}') as cc1 \gset
select public.cc_save(:'cid', '{"code":"JED2","name":"فرع جدة"}') as cc2 \gset
select t.err($$select public.cc_save('$$ || :'cid' || $$', '{"code":"RYD","name":"مكرر"}')$$, 'مستخدم', 'cost center code is unique');
select public.post_manual_journal(:'cid', current_date, 'إيجار فرع الرياض', jsonb_build_array(jsonb_build_object('a','5300','d',4000,'cc', :'cc1'), jsonb_build_object('a','1120','c',4000))) as jcc \gset
select t.ok((select cost_center_id from public.journal_lines where entry_id = :'jcc' and account_code = '5300') = :'cc1'::uuid, 'manual entry line carries its cost center');
select t.err($$select public.post_manual_journal('$$ || :'cid' || $$', current_date, 'خطأ', '[{"a":"5300","d":1,"cc":"00000000-0000-0000-0000-00000000dead"},{"a":"1120","c":1}]')$$, 'مركز التكلفة', 'unknown cost center rejected');
select public.post_sales_invoice_wh(:'cid', jsonb_build_object('party', :'c1', 'cost_center', :'cc2', 'lines', jsonb_build_array(jsonb_build_object('item', :'i3', 'qty', 2, 'price', 500)))) as ccinv \gset
select t.ok((select cost_center_id from public.sales_invoices where id = :'ccinv') = :'cc2'::uuid, 'sales invoice keeps its cost center');
select t.ok((select count(*) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id where e.source_id = :'ccinv' and l.cost_center_id = :'cc2') = 1
  and (select count(*) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id where e.source_id = :'ccinv' and l.account_code = '1200' and l.cost_center_id is null) = 1,
  'only revenue/expense lines are tagged (not receivables or VAT)');
select t.eq((select profit from public.cc_report(:'cid', current_date - 1, current_date) where cost_center_id = :'cc2'), 1000, 'cost center report: Jeddah profit');
select t.eq((select expense from public.cc_report(:'cid', current_date - 1, current_date) where cost_center_id = :'cc1'), 4000, 'cost center report: Riyadh rent');
select public.reverse_journal(:'jcc') as jccr \gset
select t.ok((select cost_center_id from public.journal_lines where entry_id = :'jccr' and account_code = '5300') = :'cc1'::uuid, 'reversing a manual entry keeps the cost center');
select t.eq((select coalesce(expense, 0) from public.cc_report(:'cid', current_date - 1, current_date) where cost_center_id = :'cc1'), 0, 'reversed rent nets to zero in the cost center');
select public.post_manual_journal(:'cid', current_date, 'إيجار فرع الرياض', jsonb_build_array(jsonb_build_object('a','5300','d',4000,'cc', :'cc1'), jsonb_build_object('a','1120','c',4000))) as jcc \gset
select public.void_sales_invoice(:'ccinv', 'تجربة إلغاء');
select t.eq((select coalesce(profit, 0) from public.cc_report(:'cid', current_date - 1, current_date) where cost_center_id = :'cc2'), 0, 'void reverses within the same cost center');
select public.post_sales_invoice_wh(:'cid', jsonb_build_object('party', :'c1', 'cost_center', :'cc2', 'lines', jsonb_build_array(jsonb_build_object('item', :'i3', 'qty', 2, 'price', 500)))) as ccinv2 \gset
select public.post_credit_note_cc(:'cid', jsonb_build_object('kind', 'sales', 'doc', :'ccinv2', 'reason', 'إرجاع صنف', 'lines', jsonb_build_array(jsonb_build_object('line', (select id from public.sales_invoice_lines where invoice_id = :'ccinv2' limit 1), 'qty', 1))));
select t.eq((select profit from public.cc_report(:'cid', current_date - 1, current_date) where cost_center_id = :'cc2'), 500, 'credit note follows the invoice cost center');
-- budgets
select t.eq(public.budget_save(:'cid', extract(year from current_date)::int, null, jsonb_build_array(jsonb_build_object('a','5300','m', jsonb_build_array(5000,5000,5000,5000,5000,5000,5000,5000,5000,5000,5000,5000)),
  jsonb_build_object('a','4200','m', jsonb_build_array(0,0,0,0,0,0,0,0,0,0,0,0)))), 1, 'budget saved (all-zero rows skipped)');
select t.err($$select public.budget_save('$$ || :'cid' || $$', 2026, null, '[{"a":"1120","m":[1,1,1,1,1,1,1,1,1,1,1,1]}]')$$, 'الإيرادات والمصروفات', 'budgets only for revenue and expense accounts');
select t.eq((select budget from public.budget_report(:'cid', extract(year from current_date)::int, null, 12) where code = '5300'), 60000, 'budget vs actual: annual rent budget');
select t.ok((select actual > 0 and variance = budget - actual from public.budget_report(:'cid', extract(year from current_date)::int, null, 12) where code = '5300'), 'budget vs actual: expense variance = budget − actual');
-- cash flow
select t.ok((select amount from public.cash_flow(:'cid', current_date - 365, current_date) where section = '9close')
  = (select amount from public.cash_flow(:'cid', current_date - 365, current_date) where section = '0open') + (select sum(amount) from public.cash_flow(:'cid', current_date - 365, current_date) where section between '1' and '3z'),
  'cash flow: opening + movements = closing');
select t.ok((select count(*) from public.cash_flow(:'cid', current_date - 365, current_date) where section = '3financing' and line = 'رأس المال والمسحوبات') = 1, 'capital injection shows under financing');
select t.ok((select amount from public.cash_flow(:'cid', current_date - 365, current_date) where line = 'تحصيلات من العملاء') > 0, 'customer receipts show under operating');
-- bank reconciliation
select public.post_manual_journal(:'cid', current_date - 1, 'رسوم بنكية', '[{"a":"5900","d":25},{"a":"1120","c":25}]') as jfee \gset
select coalesce(sum(l.debit - l.credit), 0) as bankbal from public.journal_lines l join public.journal_entries e on e.id = l.entry_id where l.company_id = :'cid' and l.account_code = '1120' and e.date <= current_date - 1 \gset
select public.recon_start(:'cid', '1120', current_date - 1, :'bankbal') as rec1 \gset
select t.err($$select public.recon_start('$$ || :'cid' || $$', '1120', current_date - 1, 0)$$, 'مفتوحة', 'one open reconciliation per account');
select t.err($$select public.recon_start('$$ || :'cid' || $$', '1200', current_date - 1, 0)$$, 'بنك', 'reconciliation only for cash/bank accounts');
select t.ok((select count(*) from public.recon_lines(:'rec1')) > 3, 'reconciliation lists the ledger lines up to the statement date');
select t.ok((public.recon_save(:'rec1', (select array_agg(line_id) from public.recon_lines(:'rec1') where line_id <> (select id from public.journal_lines where entry_id = :'jfee' and account_code = '1120'))))->>'difference' = '-25.00', 'unticked bank fee leaves a −25 difference');
select t.err($$select public.recon_finish('$$ || :'rec1' || $$')$$, 'الفرق', 'reconciliation cannot finish with a difference');
select t.ok((public.recon_totals(:'rec1')->>'book')::numeric = :'bankbal'::numeric and (public.recon_totals(:'rec1')->>'prior')::numeric = 0, 'reconciliation totals: book balance and no prior cleared lines');
select t.eq(((public.recon_save(:'rec1', (select array_agg(line_id) from public.recon_lines(:'rec1'))))->>'difference')::numeric, 0, 'all lines ticked → no difference');
select public.recon_finish(:'rec1');
select t.ok((select status from public.bank_recons where id = :'rec1') = 'done', 'reconciliation completed');
select t.err($$select public.recon_start('$$ || :'cid' || $$', '1120', current_date - 1, 0)$$, 'بعده', 'next reconciliation must be after the last statement date');
-- fixed assets
select public.asset_save(:'cid', jsonb_build_object('name', 'سيارة توصيل', 'name_en', 'Delivery van', 'category', 'سيارات', 'acquire_date', date_trunc('month', current_date - interval '2 months')::date,
  'cost', 60000, 'salvage', 0, 'life_months', 60, 'pay_account', '1120')) as fa1 \gset
select t.ok((select code from public.fixed_assets where id = :'fa1') ~ '^FA-\d{4}$', 'fixed asset numbered FA-');
select t.ok((select count(*) from public.journal_entries where source = 'asset' and source_id = :'fa1') = 1, 'paying for the asset posts Dr 1700 / Cr bank');
select t.err($$select public.asset_save('$$ || :'cid' || $$', '{"name":"خطأ","acquire_date":"2026-01-01","cost":10,"life_months":12,"asset_account":"5300"}')$$, '1700', 'asset account must be 1700 or under it');
select public.depreciation_run(:'cid', date_trunc('month', current_date - interval '2 months')::date);
select t.eq((select sum(amount) from public.asset_depreciation where asset_id = :'fa1'), 1000, 'monthly straight-line depreciation (60,000 ÷ 60)');
select t.err($$select public.depreciation_run('$$ || :'cid' || $$', date_trunc('month', current_date)::date)$$, 'بالترتيب', 'depreciation runs month by month in order');
select public.depreciation_run(:'cid', date_trunc('month', current_date - interval '1 month')::date);
select t.err($$select public.asset_save('$$ || :'cid' || $$', jsonb_build_object('id', '$$ || :'fa1' || $$', 'name', 'سيارة', 'acquire_date', '$$ || (date_trunc('month', current_date - interval '2 months')::date) || $$', 'cost', 50000, 'life_months', 60))$$, 'بدأ إهلاك', 'cost locked once depreciation started');
select t.ok(public.depreciation_undo(:'cid') = to_char(current_date - interval '1 month', 'YYYY-MM'), 'last depreciation run can be undone');
select t.eq((select sum(amount) from public.asset_depreciation where asset_id = :'fa1'), 1000, 'undo removes that month only');
select t.eq(((public.asset_dispose(:'fa1', current_date, 62000, '1120'))->>'gain')::numeric, 3000, 'disposal: sold 62,000 vs book 59,000 → gain 3,000');
select t.ok((select count(*) from public.cash_flow(:'cid', current_date, current_date) where line = 'إيرادات نقدية أخرى') = 0 and (select amount from public.cash_flow(:'cid', current_date, current_date) where line = 'شراء وبيع الأصول الثابتة') >= 62000, 'cash flow: asset sale proceeds (incl. gain) are investing, not operating');
select t.ok((select status from public.fixed_assets where id = :'fa1') = 'disposed', 'asset marked disposed');
select t.ok((select sum(debit) = sum(credit) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id where e.source_id = :'fa1' and e.source = 'asset'), 'asset entries balance');
-- period closing (last: locks the books)
select t.err($$select public.period_close('$$ || :'cid' || $$', current_date)$$, 'قبل اليوم', 'cannot close today or later');
select public.period_close(:'cid', current_date - 1);
select t.err($$select public.post_manual_journal('$$ || :'cid' || $$', current_date - 1, 'بعد الإقفال', '[{"a":"5900","d":1},{"a":"1120","c":1}]')$$, 'مقفلة', 'no entry dated in a closed period');
select t.ok(public.post_manual_journal(:'cid', current_date, 'بعد الإقفال بتاريخ اليوم', '[{"a":"5900","d":1},{"a":"1120","c":1}]') is not null, 'entries after the lock date are allowed');
select t.err($$select public.stock_adjust('$$ || :'cid' || $$', '$$ || :'i1' || $$', current_date - 2, 1, 1, 'قبل الإقفال')$$, 'مقفلة', 'stock moves in a closed period are blocked too');
select t.err($$select public.period_reopen('$$ || :'cid' || $$', null, 'تصحيح خطأ في الإقفال')$$, '42501|غير مصرح', 'only the owner can reopen a closed period');
reset role;
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select t.err($$select public.period_reopen('$$ || :'cid' || $$', null, 'x')$$, 'سبب', 'reopening needs a reason');
select public.period_reopen(:'cid', null, 'تصحيح قيد في الفترة السابقة');
select t.ok((select books_closed_through from public.companies where id = :'cid') is null and (select count(*) from public.period_locks where company_id = :'cid') = 2, 'reopen logged; books open again');
reset role;
select set_config('request.jwt.claim.sub', :'u_acc', false); set role authenticated;
select t.err($$select public.period_close('$$ || :'cid' || $$', current_date - 1)$$, '42501|غير مصرح', 'accountant cannot close periods');
reset role;
select set_config('request.jwt.claim.sub', :'u_store', false); set role authenticated;
select t.err($$select public.recon_start('$$ || :'cid' || $$', '1120', current_date, 0)$$, '42501|غير مصرح', 'storekeeper cannot reconcile the bank');
select t.err($$select public.depreciation_run('$$ || :'cid' || $$', current_date)$$, '42501|غير مصرح', 'storekeeper cannot run depreciation');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.fixed_assets) = 0 and (select count(*) from public.cost_centers) = 0 and (select count(*) from public.bank_recons) = 0, 'employee sees no finance data');
reset role;
select set_config('request.jwt.claim.sub', null, false); set role anon;
select t.err($$select * from public.cash_flow('$$ || :'cid' || $$', current_date, current_date)$$, 'permission denied', 'anon cannot read the cash flow');
reset role;

-- ================= FINANCE MORE (cheques, currencies, opening balances, year-end, petty cash) =================
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
-- cheques
select public.post_sales_invoice_wh(:'cid', jsonb_build_object('party', :'c1', 'lines', jsonb_build_array(jsonb_build_object('item', :'i3', 'qty', 5, 'price', 200)))) as qinv \gset
select public.cheque_save(:'cid', jsonb_build_object('direction','in','party', :'c1','invoice', :'qinv','cheque_no','100234','bank','الراجحي','amount',1150,'issue_date', current_date,'due_date', current_date + 30)) as chq1 \gset
select t.eq((select coalesce(sum(amount), 0) from public.payments where invoice_id = :'qinv' or bill_id = :'qinv'), 1150, 'a received cheque settles the invoice');
select t.eq((select sum(debit - credit) from public.journal_lines where company_id = :'cid' and account_code = '1150'), 1150, 'the cheque sits in cheques-under-collection (1150) until the bank collects it');
select t.err($$select public.cheque_save('$$ || :'cid' || $$', jsonb_build_object('direction','in','party','$$ || :'c1' || $$','invoice','$$ || :'qinv' || $$','cheque_no','9','amount',1,'issue_date', current_date,'due_date', current_date))$$, 'المتبقي', 'cannot cheque more than what is still due');
select t.err($$select public.cheque_save('$$ || :'cid' || $$', jsonb_build_object('direction','in','party','$$ || :'c1' || $$','cheque_no','9','amount',10,'issue_date', current_date,'due_date', current_date - 1))$$, 'استحقاق', 'due date cannot be before the receipt date');
select bal0 from (select coalesce(sum(l.debit - l.credit), 0) bal0 from public.journal_lines l where l.company_id = :'cid' and l.account_code = '1120') x \gset
select public.cheque_clear(:'chq1', current_date, '1120');
select t.eq((select sum(debit - credit) from public.journal_lines where company_id = :'cid' and account_code = '1120') - :'bal0'::numeric, 1150, 'clearing moves the money into the bank');
select t.err($$select public.cheque_clear('$$ || :'chq1' || $$', current_date, '1120')$$, 'ليس قائماً', 'a cheque clears once');
select public.post_sales_invoice_wh(:'cid', jsonb_build_object('party', :'c1', 'lines', jsonb_build_array(jsonb_build_object('item', :'i3', 'qty', 1, 'price', 400)))) as qinv2 \gset
select public.cheque_save(:'cid', jsonb_build_object('direction','in','party', :'c1','invoice', :'qinv2','cheque_no','100235','amount',460,'issue_date', current_date,'due_date', current_date + 10)) as chq2 \gset
select t.err($$select public.cheque_return('$$ || :'chq2' || $$', current_date, '')$$, 'السبب', 'bouncing needs a reason');
select public.cheque_return(:'chq2', current_date, 'رصيد غير كافٍ');
select t.ok((select coalesce(sum(amount), 0) from public.payments where invoice_id = :'qinv2' or bill_id = :'qinv2') = 0 and (select status from public.cheques where id = :'chq2') = 'bounced', 'a bounced cheque reopens the invoice');
select t.eq((select coalesce(sum(debit - credit), 0) from public.journal_lines where company_id = :'cid' and account_code = '1150'), 0, 'nothing left under collection');
select public.post_purchase_bill_wh(:'cid', jsonb_build_object('party', :'s1', 'lines', jsonb_build_array(jsonb_build_object('account','5500','qty',1,'price',1000)))) as qbill \gset
select public.cheque_save(:'cid', jsonb_build_object('direction','out','party', :'s1','bill', :'qbill','cheque_no','500001','amount',1150,'issue_date', current_date,'due_date', current_date + 60)) as chq3 \gset
select t.ok((select coalesce(sum(amount), 0) from public.payments where invoice_id = :'qbill' or bill_id = :'qbill') = 1150 and (select sum(credit - debit) from public.journal_lines where company_id = :'cid' and account_code = '2160') = 1150, 'an issued post-dated cheque pays the supplier and waits in 2160');
select public.cheque_return(:'chq3', current_date, 'استبدال بتحويل بنكي');
select t.ok((select coalesce(sum(amount), 0) from public.payments where invoice_id = :'qbill' or bill_id = :'qbill') = 0 and (select status from public.cheques where id = :'chq3') = 'cancelled', 'cancelling an issued cheque reopens the bill');
-- foreign currencies
select t.err($$select public.currency_save('$$ || :'cid' || $$', 'SAR', 'ريال', null, 1)$$, 'الأساسية', 'SAR is the base currency');
select public.currency_save(:'cid', 'usd', 'دولار أمريكي', 'US dollar', 3.75);
select public.post_sales_invoice_wh(:'cid', jsonb_build_object('party', :'c1', 'currency', 'USD', 'lines', jsonb_build_array(jsonb_build_object('item', :'i3', 'qty', 1, 'price', 100)))) as fxinv \gset
select t.ok((select total = 431.25 and fx_total = 115 and currency = 'USD' and fx_rate = 3.75 from public.sales_invoices where id = :'fxinv'), 'USD invoice: 100 + VAT = 115 USD, booked 431.25 SAR at 3.75');
select t.err($$select public.record_payment_fx('$$ || :'cid' || $$', jsonb_build_object('direction','in','invoice','$$ || :'fxinv' || $$','fx_amount',116,'fx_rate',3.8,'account','1120'))$$, 'المتبقي', 'cannot collect more than the foreign balance');
select public.record_payment_fx(:'cid', jsonb_build_object('direction','in','invoice', :'fxinv','fx_amount',115,'fx_rate',3.80,'account','1120')) as fxpay \gset
select t.ok((select coalesce(sum(amount), 0) from public.payments where invoice_id = :'fxinv' or bill_id = :'fxinv') = 431.25 and (select sum(credit - debit) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id where e.source_id = :'fxpay' and l.account_code = '4950') = 5.75,
  'collected 115 USD at 3.80 = 437.00: invoice fully settled, 5.75 exchange gain');
select public.post_purchase_bill_wh(:'cid', jsonb_build_object('party', :'s1', 'currency', 'USD', 'fx_rate', 3.75, 'lines', jsonb_build_array(jsonb_build_object('account','5500','qty',2,'price',50)))) as fxbill \gset
select public.record_payment_fx(:'cid', jsonb_build_object('direction','out','bill', :'fxbill','fx_amount',57.5,'fx_rate',3.80,'account','1120')) as fxpay2 \gset
select t.ok((select coalesce(sum(amount), 0) from public.payments where invoice_id = :'fxbill' or bill_id = :'fxbill') = 215.63 and (select sum(debit - credit) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id where e.source_id = :'fxpay2' and l.account_code = '5950') = 2.87,
  'half a USD bill paid at a higher rate: half settled, exchange loss booked');
select t.err($$select public.record_payment_fx('$$ || :'cid' || $$', jsonb_build_object('direction','in','invoice','$$ || :'qinv2' || $$','fx_amount',1,'fx_rate',1,'account','1120'))$$, 'بالريال', 'SAR documents use the normal receipt');
-- petty cash
select public.petty_open(:'cid', :'e_emp', 1000, '1120', 1500) as pf \gset
select t.ok((select code like '113%' and parent_code = '1100' from public.accounts a join public.petty_funds f on f.account_code = a.code and f.company_id = a.company_id where f.id = :'pf'), 'a petty cash fund gets its own cash account under 1100');
select t.err($$select public.petty_open('$$ || :'cid' || $$', '$$ || :'e_emp' || $$', 10, '1120', 100)$$, 'قائمة', 'one active fund per employee');
select t.err($$select public.petty_topup('$$ || :'pf' || $$', 600, '1120')$$, 'سقف', 'top-up cannot exceed the ceiling');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select balance from public.petty_mine(:'cid')) = 1000, 'the employee sees his fund balance');
select t.ok((select count(*) from public.petty_accounts(:'cid')) > 3, 'the employee can pick expense accounts for his claim');
select t.err($$select public.petty_claim_submit('$$ || :'pf' || $$', current_date, '[{"a":"5500","desc":"قرطاسية","amount":200,"vat":30}]')$$, 'الرقم الضريبي', 'VAT is reclaimed only with the supplier VAT number');
select public.petty_claim_submit(:'pf', current_date, '[{"a":"5500","desc":"قرطاسية","amount":200,"vat":30,"vat_no":"300000000000003","ref":"INV-77"},{"a":"5400","desc":"شحن رصيد","amount":50}]') as pcl \gset
select t.err($$select public.petty_claim_decide('$$ || :'pcl' || $$', true)$$, '42501|غير مصرح', 'the employee cannot approve his own claim');
select t.ok((select count(*) from public.journal_lines) = 0, 'employee still cannot read the ledger');
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select public.petty_claim_decide(:'pcl', true);
select t.eq((select balance from public.petty_list(:'cid') where id = :'pf'), 720, 'approved claim (250 + 30 VAT) is taken from the fund');
select t.ok((select sum(debit) from public.journal_lines where entry_id = (select entry_id from public.petty_claims where id = :'pcl') and account_code = '1400') = 30, 'reclaimable VAT goes to input VAT (1400)');
select t.err($$select public.petty_claim_submit('$$ || :'pf' || $$', current_date, '[{"a":"1120","desc":"خطأ","amount":5}]')$$, 'مصروف', 'claims only against expense accounts');
select public.petty_topup(:'pf', 280, '1120');
select t.eq((select balance from public.petty_list(:'cid') where id = :'pf'), 1000, 'top-up restores the fund');
select public.petty_close(:'pf', '1120');
select t.ok((select balance from public.petty_list(:'cid') where id = :'pf') = 0 and (select status from public.petty_funds where id = :'pf') = 'closed', 'closing returns the balance to the bank');
-- year-end closing
select coalesce(sum(amount), 0) as np from public.income_statement(:'cid', '2000-01-01', current_date - 1) where section = 'net_profit' \gset
select t.err($$select public.year_close('$$ || :'cid' || $$', current_date)$$, 'قبل اليوم', 'year end must be in the past');
select (public.year_close(:'cid', current_date - 1))->>'net_profit' as ynp \gset
select t.eq(:'ynp'::numeric, :'np'::numeric, 'closing moves the year net profit to retained earnings');
select t.ok((select coalesce(sum(debit - credit), 0) from public.journal_lines l join public.journal_entries e on e.id = l.entry_id join public.accounts a on a.company_id = l.company_id and a.code = l.account_code
             where l.company_id = :'cid' and a.type in ('rev','exp') and e.date <= current_date - 1) = 0, 'after closing, revenue and expense accounts are zero at the year end');
select t.eq((select amount from public.income_statement(:'cid', '2000-01-01', current_date - 1) where section = 'net_profit'), :'np'::numeric, 'the income statement of a closed year still shows its profit');
select t.ok((select books_closed_through from public.companies where id = :'cid') = current_date - 1, 'closing the year locks the books through its end');
select t.err($$select public.year_close('$$ || :'cid' || $$', current_date - 1)$$, 'مقفلة', 'a year closes once');
select t.err($$select public.year_reopen('$$ || :'cid' || $$', 'تصحيح خطأ')$$, '42501|غير مصرح', 'only the owner reopens a year');
reset role;
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select public.year_reopen(:'cid', 'تصحيح خطأ في الإقفال');
select t.ok((select coalesce(sum(credit - debit), 0) from public.journal_lines where company_id = :'cid' and account_code = '3200') = 0 and (select status from public.fiscal_closings where company_id = :'cid') = 'reopened', 'reopening reverses the closing entry');
select public.period_reopen(:'cid', null, 'إعادة فتح بعد اختبار الإقفال السنوي');
reset role;
-- opening balances (a fresh company)
\set u_ob '00000000-0000-0000-0000-000000000b01'
insert into auth.users(id, email) values (:'u_ob', 'opening@test.sa');
select set_config('request.jwt.claim.sub', :'u_ob', false); set role authenticated;
select public.create_company('منشأة الأرصدة الافتتاحية') as cid3 \gset
select t.err($$select public.opening_post('$$ || :'cid3' || $$', current_date - 10, '[{"t":"acc","a":"1120","d":5000},{"t":"acc","a":"3100","c":4000}]')$$, 'غير متوازنة', 'unbalanced opening balances are refused unless sent to 3900');
reset role;
insert into public.items(company_id, code, name, type, unit, sale_price) values (:'cid3','OB-1','صنف افتتاحي','stock','حبة',50);
select set_config('request.jwt.claim.sub', :'u_ob', false); set role authenticated;
select t.err($$select public.opening_post('$$ || :'cid3' || $$', current_date - 10, '[{"t":"acc","a":"1200","d":5000}]')$$, 'تفصيلاً', 'receivables are entered per customer, not as one figure');
select public.opening_post(:'cid3', current_date - 10, '[{"t":"acc","a":"1120","d":20000},{"t":"acc","a":"3100","c":25000},{"t":"cust","name":"عميل قديم","amount":3000,"due":"2026-01-01","ref":"F-12"},
  {"t":"supp","name":"مورد قديم","amount":1000},{"t":"item","code":"OB-1","qty":10,"cost":30},{"t":"acc","a":"1700","d":2700}]') as ob \gset
select t.ok((select count(*) from public.sales_invoices where company_id = :'cid3' and is_opening and total = 3000) = 1
  and (select count(*) from public.parties where company_id = :'cid3' and name = 'مورد قديم' and kind = 'supplier') = 1, 'opening customer/supplier balances become open documents (party created if new)');
select t.ok((select sum(debit) = sum(credit) and sum(debit) = 26000 from public.journal_lines where entry_id = (select entry_id from public.opening_batches where id = :'ob')), 'one balanced opening entry');
select t.eq((select sum(qty) from public.stock_moves where company_id = :'cid3'), 10, 'opening stock quantity in the default warehouse');
select t.err($$select public.opening_post('$$ || :'cid3' || $$', current_date - 10, '[{"t":"acc","a":"1120","d":1},{"t":"acc","a":"3100","c":1}]')$$, 'مسبقاً', 'opening balances are entered once');
select t.err($$select public.void_sales_invoice((select id from public.sales_invoices where company_id = '$$ || :'cid3' || $$' and is_opening), 'خطأ')$$, 'افتتاحي', 'an opening balance is not voided like an invoice');
select public.opening_undo(:'cid3');
select t.ok((select coalesce(sum(debit - credit), 0) from public.journal_lines where company_id = :'cid3' and account_code = '1120') = 0
  and (select coalesce(sum(qty), 0) from public.stock_moves where company_id = :'cid3') = 0
  and (select count(*) from public.sales_invoices where company_id = :'cid3' and status = 'posted') = 0, 'undo reverses everything (nothing deleted)');
select public.opening_post(:'cid3', current_date - 10, '[{"t":"acc","a":"1120","d":5000},{"t":"acc","a":"3100","c":4000}]', true) as ob2 \gset
select t.ok((select sum(credit) from public.journal_lines where entry_id = (select entry_id from public.opening_batches where id = :'ob2') and account_code = '3900') = 1000, 'difference sent to opening balances equity (3900) when asked');
reset role;
-- permissions
select set_config('request.jwt.claim.sub', :'u_store', false); set role authenticated;
select t.err($$select public.cheque_save('$$ || :'cid' || $$', jsonb_build_object('direction','in','party','$$ || :'c1' || $$','cheque_no','1','amount',1,'issue_date', current_date,'due_date', current_date))$$, '42501|غير مصرح', 'storekeeper cannot record cheques');
select t.err($$select public.petty_open('$$ || :'cid' || $$', '$$ || :'e_emp' || $$', 10, '1120', 100)$$, '42501|غير مصرح', 'storekeeper cannot open petty cash');
reset role;
select set_config('request.jwt.claim.sub', :'u_acc', false); set role authenticated;
select t.err($$select public.year_close('$$ || :'cid' || $$', current_date - 1)$$, '42501|غير مصرح', 'accountant cannot close the year');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) from public.cheques) = 0 and (select count(*) from public.currencies) = 0, 'employee sees no cheques or currencies');
reset role;

-- ================= EMPLOYEE PROFILE (0047) =================
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
update public.employees set nationality = 'in' where id = :'e_exp';
select t.ok((select nationality = 'IN' and not is_saudi from public.employees where id = :'e_exp'), 'nationality stored as ISO code');
update public.employees set nationality = 'SA' where id = :'e_exp';
select t.ok((select is_saudi from public.employees where id = :'e_exp'), 'Saudi nationality sets is_saudi');
update public.employees set nationality = 'IN' where id = :'e_exp';
select t.err($$update public.employees set nationality = 'India' where id = '$$ || :'e_exp' || $$'$$, 'رمز الجنسية', 'bad nationality code rejected');
select t.err($$update public.employees set birth_date = '2010-01-01' where id = '$$ || :'e_exp' || $$'$$, 'م162', 'under-15 at hiring rejected (Art. 162)');
select t.err($$update public.employees set short_address = 'RRD29' where id = '$$ || :'e_exp' || $$'$$, 'العنوان المختصر', 'short national address format checked');
select t.err($$update public.employees set marital_status = 'x' where id = '$$ || :'e_exp' || $$'$$, 'الحالة الاجتماعية', 'marital status checked');
update public.employees set birth_date = '1990-05-01', marital_status = 'married', dependents = 3, education = 'bachelor', short_address = 'rrrd 2929',
  emergency_name = 'أحمد', emergency_relation = 'أخ', emergency_phone = '0555555555', official_profession = 'فني' where id = :'e_exp';
select t.ok((select short_address = 'RRRD2929' and dependents = 3 from public.employees where id = :'e_exp'), 'profile fields saved and normalised');
reset role;
insert into public.cost_centers(company_id, code, name) values (:'cid2','X1','مركز منشأة أخرى') returning id as cc_other \gset
select t.err($$update public.employees set cost_center_id = '$$ || :'cc_other' || $$' where id = '$$ || :'e_exp' || $$'$$, 'مركز التكلفة غير موجود', 'cost center of another company refused');
reset role;
insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, hire_date, basic) values (:'cid','8100','موظف قديم للتجربة',true,'m','2015-01-01',5000) returning id as e_old \gset
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok((select balance from public.annual_leave_balance(:'e_old')) > 250, 'without an opening balance all leave since 2015 counts as unused');
update public.employees set leave_open_days = 5, leave_open_date = current_date - 10 where id = :'e_old';
select t.eq((select balance from public.annual_leave_balance(:'e_old')), round(5 + round((current_date - date '2015-01-01' + 1 - 1826) * 30 / 365.0 + 1826 * 21 / 365.0, 2) - round((current_date - 10 - date '2015-01-01' + 1 - 1826) * 30 / 365.0 + 1826 * 21 / 365.0, 2), 2), 'opening balance + accrual since the opening date (30 days/yr after 5 years)');
reset role;
insert into public.requests(company_id, employee_id, kind, sub, from_date, to_date, days, status) values (:'cid', :'e_old', 'leave', 'annual', current_date - 40, current_date - 38, 3, 'approved');
insert into public.requests(company_id, employee_id, kind, sub, from_date, to_date, days, status) values (:'cid', :'e_old', 'leave', 'annual', current_date - 5, current_date - 4, 2, 'approved');
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.eq((select taken from public.annual_leave_balance(:'e_old')), 2, 'only leave after the opening date is deducted');
select t.err($$update public.employees set leave_open_days = 5, leave_open_date = '2014-01-01' where id = '$$ || :'e_old' || $$'$$, 'قبل تاريخ المباشرة', 'opening date before hiring rejected');
select t.err($$select * from public.annual_leave_raw((select e from public.employees e where id = '$$ || :'e_old' || $$'), current_date)$$, 'permission denied', 'raw leave helper is internal');
select public.import_employees(:'cid', jsonb_build_array(jsonb_build_object('_row', 2, 'emp_no', '8200', 'full_name', 'مستورد بالبيانات', 'hire_date', '2020-01-01', 'basic', '6000',
  'nationality', 'EG', 'birth_date', '1985-02-03', 'marital_status', 'single', 'education', 'diploma', 'cost_center', 'PAYCC', 'leave_open_days', '12.5', 'leave_open_date', '2025-12-31')));
select t.ok((select nationality = 'EG' and not is_saudi and cost_center_id = :'cc_pay' and leave_open_days = 12.5 and birth_date = '1985-02-03' from public.employees where company_id = :'cid' and emp_no = '8200'), 'import carries nationality, cost center and opening leave');
select t.err($$select public.import_employees('$$ || :'cid' || $$', '[{"_row":3,"emp_no":"8201","full_name":"خطأ مركز","hire_date":"2020-01-01","basic":"5000","cost_center":"NOPE"}]')$$, 'السطر 3: مركز التكلفة', 'import names the row with an unknown cost center');
select public.update_employees(:'cid', '[{"_row":2,"emp_no":"8200","nationality":"SA","dependents":"2"}]');
select t.ok((select is_saudi and dependents = 2 from public.employees where company_id = :'cid' and emp_no = '8200'), 'bulk update sets nationality and profile fields');
select t.err($$select public.update_employees('$$ || :'cid' || $$', '[{"_row":4,"emp_no":"8200","birth_date":"03/02/1985"}]')$$, 'السطر 4: التاريخ', 'bulk update checks date format');
reset role;
delete from public.requests where employee_id = :'e_old';

select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'update', null, null, null, null, '{"short_address":"AB12"}')$$, 'العنوان المختصر', 'employee update request checks the short address');
select t.err($$select public.submit_request('$$ || :'cid' || $$', 'update', null, null, null, null, '{"basic":"1"}')$$, 'لا يمكن طلب تعديل', 'salary still not requestable');
reset role;
insert into public.requests(company_id, employee_id, kind, payload, status) values (:'cid', :'e_emp', 'update', '{"emergency_name":"سعد","emergency_phone":"0501112222","marital_status":"married","dependents":"2","short_address":"abcd1234"}', 'approved') returning id as upd2 \gset
select public.on_request_approved(:'upd2');
select t.ok((select emergency_name = 'سعد' and marital_status = 'married' and dependents = 2 and short_address = 'ABCD1234' from public.employees where id = :'e_emp'), 'approved update request applies personal fields');
delete from public.requests where id = :'upd2';

-- ================= ANON HARDENING (0046) =================
set role anon;
select t.err($$select * from public.travel_tickets$$, 'permission denied', 'anon cannot read travel tickets');
select t.err($$select * from public.exit_visas$$, 'permission denied', 'anon cannot read exit visas');
select t.err($$select * from public.travel_files$$, 'permission denied', 'anon cannot read travel files');
select t.err($$select * from public.code_lookups$$, 'permission denied', 'anon cannot read code lookup log');
select t.err($$select public.riyadh_today()$$, 'permission denied', 'anon cannot call helper functions');
reset role;
select t.ok((select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
  and has_function_privilege('anon', p.oid, 'execute') and p.proname not in ('company_by_code', 'ping', 'site_hit', 'site_content')) = 0, 'anon can call only company_by_code, the health check, and the website counter/texts');
select t.ok(has_function_privilege('authenticated', 'public.riyadh_today()', 'execute'), 'signed-in users keep helper functions');
delete from public.code_lookups;
select set_config('request.headers', '{"cf-connecting-ip":"203.0.113.7"}', false);
set role anon;
select public.company_by_code('BAD' || g) from generate_series(1, 10) g;
select t.err($$select public.company_by_code('NOPE01')$$, 'محاولات كثيرة', '11th wrong company code in 15 minutes is throttled');
select t.err($$select public.company_by_code('$$ || :'ccode' || $$')$$, 'محاولات كثيرة', 'throttled visitor is blocked even with a valid code');
reset role;
select set_config('request.headers', '{"cf-connecting-ip":"203.0.113.8"}', false);
set role anon;
select t.ok(public.company_by_code(:'ccode') = 'شركة وعد للتجربة', 'other visitors are not affected');
reset role;
select set_config('request.headers', '', false);
delete from public.code_lookups;

-- ================= COMPANY & PARTY PROFILE (0048) =================
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select t.err($$update public.companies set unified_no = '123' where id = '$$ || :'cid' || $$'$$, 'الرقم الموحد', 'unified number must be 10 digits starting with 7');
select t.err($$update public.companies set postal_code = '123' where id = '$$ || :'cid' || $$'$$, 'الرمز البريدي', 'postal code must be 5 digits');
select t.err($$update public.companies set iban = 'SA12' where id = '$$ || :'cid' || $$'$$, 'الآيبان', 'company IBAN validated');
update public.companies set unified_no = '7001234567', mhrsd_no = '1-123456', gosi_no = '50012345', bld_no = '2345', street = 'طريق الملك فهد', district = 'العليا',
  city = 'الرياض', postal_code = '12211', add_no = '7788', short_address = 'rrrd 2929', email = 'Info@Waad.test', phone = '011 456 7890', iban = 'SA03 8000 0000 6080 1016 7519' where id = :'cid';
select t.ok((select short_address = 'RRRD2929' and email = 'info@waad.test' and phone = '0114567890' and iban = 'SA0380000000608010167519'
  and address like 'مبنى 2345، طريق الملك فهد، حي العليا، الرياض%' from public.companies where id = :'cid'), 'company national address saved, normalised and composed into the letter address');
reset role;
insert into public.items(company_id, code, name, type, unit, sale_price) values (:'cid', 'SV-CL', 'خدمة استشارية', 'service', 'ساعة', 100) returning id as isv \gset
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.err($$insert into public.parties(company_id, kind, name, bld_no) values ('$$ || :'cid' || $$','customer','عميل عنوان خطأ','12')$$, 'رقم المبنى', 'building number must be 4 digits for Saudi parties');
select t.err($$insert into public.parties(company_id, kind, name, country, vat_no) values ('$$ || :'cid' || $$','supplier','مورد خارجي ضريبي','AE','300000000000003')$$, 'داخل المملكة', 'foreign party cannot carry a Saudi VAT number');
insert into public.parties(company_id, kind, name, country, phone, postal_code, city) values (:'cid', 'supplier', 'Gulf Trading LLC', 'ae', '+971 50 123 4567', 'PO 1234', 'Dubai') returning id as sfx \gset
select t.ok((select country = 'AE' and phone = '+971501234567' from public.parties where id = :'sfx'), 'foreign supplier accepted with its own phone and postal format');
insert into public.parties(company_id, kind, name, credit_limit, terms_days) values (:'cid', 'customer', 'عميل بحد ائتمان', 100, 30) returning id as clim \gset
select t.err($$update public.parties set terms_days = 400 where id = '$$ || :'clim' || $$'$$, 'مدة السداد', 'payment terms capped at 365 days');
select t.ok((select terms_days = 30 and credit_limit = 100 and balance = 0 from public.party_credit(:'clim')), 'party_credit returns balance, limit and terms');
select public.set_finance_permission(:'cid', 'accountant', 'sales', true);
reset role;
select set_config('request.jwt.claim.sub', :'u_acc', false); set role authenticated;
select t.err($$select public.post_sales_invoice('$$ || :'cid' || $$', '{"party":"$$ || :'clim' || $$","lines":[{"item":"$$ || :'isv' || $$","qty":1,"price":100}]}')$$, 'حد الائتمان', 'accountant stopped above the customer credit limit (115 > 100)');
select public.post_sales_invoice(:'cid', jsonb_build_object('party', :'clim', 'lines', jsonb_build_array(jsonb_build_object('item', :'isv', 'qty', 0.5, 'price', 100)))) as ilim \gset
select t.ok((select balance = 57.5 from public.party_credit(:'clim')), 'within the limit the invoice posts and the balance follows');
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.ok(public.post_sales_invoice(:'cid', jsonb_build_object('party', :'clim', 'lines', jsonb_build_array(jsonb_build_object('item', :'isv', 'qty', 1, 'price', 100)))) is not null, 'finance manager may exceed the credit limit knowingly');
update public.parties set active = false where id = :'clim';
select t.err($$select public.post_sales_invoice('$$ || :'cid' || $$', '{"party":"$$ || :'clim' || $$","lines":[{"item":"$$ || :'isv' || $$","qty":1,"price":1}]}')$$, 'موقوف', 'no invoices for an inactive customer');
update public.parties set active = true where id = :'clim';
select public.import_parties(:'cid', 'customer', '[{"_row":2,"name":"عميل بحد ائتمان","terms_days":"45","email":"AR@client.test"},{"_row":3,"name":"  شركة   المستورد الجديد ","vat_no":"311111111100003","city":"جدة","credit_limit":"5000"}]') as imp \gset
select t.ok((:'imp'::jsonb->>'added')::int = 1 and (:'imp'::jsonb->>'updated')::int = 1
  and (select terms_days = 45 and email = 'ar@client.test' and credit_limit = 100 from public.parties where id = :'clim')
  and (select credit_limit = 5000 from public.parties where company_id = :'cid' and name = 'شركة المستورد الجديد'), 'import adds new customers and updates existing ones by name, keeping blank cells');
select t.err($$select public.import_parties('$$ || :'cid' || $$', 'customer', '[{"_row":7,"name":"عميل خطأ","bld_no":"9"}]')$$, 'السطر 7: رقم المبنى', 'import errors name the row');
select t.err($$select public.import_parties('$$ || :'cid' || $$', 'customer', '[{"_row":2,"name":"عميل مكرر"},{"_row":3,"name":"عميل مكرر"}]')$$, 'مكرر', 'duplicate names in the file refused');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.import_parties('$$ || :'cid' || $$', 'customer', '[{"_row":2,"name":"عميل من الموارد"}]')$$, '42501|غير مصرح', 'HR cannot import customers');
reset role;

-- ================= STATEMENTS, ITEMS, CV, TERMS, MFA (0049) =================
select round(public.party_balance(:'c1'), 2) as c1bal, round(public.party_balance(:'s1'), 2) as s1bal \gset
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.ok((select balance from public.party_statement(:'c1', '2000-01-01', current_date + 1) order by d desc, balance limit 1) is not null
  and (select balance from public.party_statement(:'c1', '2000-01-01', current_date + 1) offset (select count(*) - 1 from public.party_statement(:'c1', '2000-01-01', current_date + 1)) limit 1)
      = :c1bal, 'customer statement closes at the customer balance');
select t.ok((select balance from public.party_statement(:'s1', '2000-01-01', current_date + 1) offset (select count(*) - 1 from public.party_statement(:'s1', '2000-01-01', current_date + 1)) limit 1)
      = :s1bal, 'supplier statement closes at what we owe the supplier');
select t.ok((select count(*) = 1 and max(kind) = 'opening_balance' and max(balance) = 172.5 from public.party_statement(:'clim', current_date + 1, current_date + 1)),
  'a later period starts from the opening balance carried forward');
select t.ok((select count(*) filter (where kind = 'invoice') = 2 and sum(debit) = 172.5 from public.party_statement(:'clim', current_date - 1, current_date)), 'statement lists the invoices as debits');
select t.err($$select * from public.party_statement('$$ || :'clim' || $$', current_date, current_date - 5)$$, 'حدد الفترة', 'statement period must be valid');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select * from public.party_statement('$$ || :'c1' || $$', '2000-01-01', current_date)$$, '42501|غير مصرح', 'HR cannot read customer statements');
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
update public.items set barcode = '6281000000017', category = 'خدمات', purchase_price = 60, vat_rate = 0 where id = :'isv';
select t.ok((select barcode = '6281000000017' and vat_rate = 0 and active from public.items where id = :'isv'), 'item barcode, category, purchase price and VAT rate saved');
select t.err($$update public.items set vat_rate = 5 where id = '$$ || :'isv' || $$'$$, 'check', 'VAT rate is 0 or 15');
select t.err($$update public.items set barcode = '12' where id = '$$ || :'isv' || $$'$$, 'الباركود', 'barcode format checked');
select t.err($$insert into public.items(company_id, code, name, type, barcode) values ('$$ || :'cid' || $$', 'DUP-BC', 'صنف مكرر', 'service', '6281000000017')$$, 'duplicate|unique', 'barcode unique within the company');
update public.items set active = false where id = :'isv';
select t.err($$select public.post_sales_invoice('$$ || :'cid' || $$', '{"party":"$$ || :'clim' || $$","lines":[{"item":"$$ || :'isv' || $$","qty":1,"price":1}]}')$$, 'الصنف موقوف', 'inactive item cannot be invoiced');
update public.items set active = true where id = :'isv';
select public.import_items(:'cid', '[{"_row":2,"code":"SV-CL","sale_price":"120"},{"_row":3,"code":"NEW-01","name":"صنف مستورد","type":"خدمة","vat_rate":"15%","barcode":"ABC-1234"}]') as impi \gset
select t.ok((:'impi'::jsonb->>'added')::int = 1 and (:'impi'::jsonb->>'updated')::int = 1 and (select sale_price = 120 and name = 'خدمة استشارية' from public.items where id = :'isv')
  and (select type = 'service' and vat_rate = 15 and barcode = 'ABC-1234' from public.items where company_id = :'cid' and code = 'NEW-01'), 'items import adds new codes and updates existing ones');
select t.err($$select public.import_items('$$ || :'cid' || $$', '[{"_row":4,"code":"NEW-02","name":"صنف","barcode":"ABC-1234"}]')$$, 'السطر 4: الباركود مستخدم', 'import refuses a barcode used by another item');
select t.err($$select public.import_items('$$ || :'cid' || $$', '[{"_row":5,"code":"NEW-03"}]')$$, 'السطر 5: اسم الصنف مطلوب', 'new item needs a name');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
insert into public.candidate_files(company_id, candidate_id, file_name, mime, size, data) values (:'cid', :'cand', 'cv.pdf', 'application/pdf', 5, 'JVBER') returning id as cvf \gset
select t.ok((select count(*) = 1 from public.candidate_files where candidate_id = :'cand'), 'HR attaches a CV to a candidate');
select t.err($$insert into public.candidate_files(company_id, candidate_id, file_name, mime, size, data) values ('$$ || :'cid' || $$', '$$ || :'cand' || $$', 'x.exe', 'application/x-msdownload', 5, 'TVo=')$$, 'check', 'only PDF, Word and images accepted');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) = 0 from public.candidate_files), 'employees cannot see candidate CVs');
select public.accept_terms('2026-10');
select t.ok((select count(*) = 1 from public.terms_acceptance where version = '2026-10'), 'user acceptance of terms and privacy recorded');
select t.err($$select public.accept_terms('latest')$$, 'إصدار', 'terms version validated');
select public.log_client_error(:'cid', 'TypeError: x is undefined', 'app.js:10', '#/sales/' || gen_random_uuid(), 'test-agent');
reset role;
select t.ok((select route = '#/sales/:id' and company_id = :'cid' from public.client_errors order by id desc limit 1), 'client errors logged without record ids');
-- two-step verification: once enrolled, a password-only session no longer counts
insert into auth.mfa_factors(user_id, factor_type, status) values (:'u_fin', 'totp', 'verified');
select set_config('request.jwt.claim.sub', :'u_fin', false); select set_config('request.jwt.claims', '{"aal":"aal1"}', false); set role authenticated;
select t.ok(not public.has_role(:'cid', array['finance']) and not public.fin_can(:'cid', 'sales') and (select count(*) = 0 from public.parties)
  and (public.mfa_state()->>'enrolled')::boolean, 'enrolled user with a password-only session sees nothing');
reset role;
select set_config('request.jwt.claims', '{"aal":"aal2"}', false); set role authenticated;
select t.ok(public.has_role(:'cid', array['finance']) and (select count(*) > 0 from public.parties), 'after the authenticator code the same user works normally');
reset role;
select set_config('request.jwt.claims', '', false);
select set_config('request.jwt.claim.sub', :'u_acc', false); set role authenticated;
select t.ok(public.fin_can(:'cid', 'sales'), 'users without an authenticator are unaffected');
reset role;
delete from auth.mfa_factors;

-- ================= SUBSCRIPTIONS & PLATFORM ADMIN (0050) =================
insert into auth.users(id, email, last_sign_in_at) values ('00000000-0000-0000-0000-0000000000a1', 'platform@waad.test', now()) on conflict do nothing;
insert into public.platform_admins(user_id) values ('00000000-0000-0000-0000-0000000000a1');
select t.ok((select count(*) from public.company_subscriptions) = (select count(*) from public.companies), 'every company has a subscription row');
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.err($$select * from public.platform_companies()$$, '42501|غير مصرح', 'a company user cannot open the platform panel');
select t.ok((select count(*) = 1 and bool_and(company_id = :'cid') from public.company_subscriptions), 'members read only their own subscription');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select t.ok((select count(*) >= 2 and bool_or(owner_email is not null and users > 0) from public.platform_companies()), 'platform admin lists companies with owner, plan and user count');
select t.ok((select count(*) = 0 from public.employees) and (select count(*) = 0 from public.parties) and (select count(*) = 0 from public.journal_entries),
  'platform admin sees no company records');
select public.platform_set_subscription(:'cid', 'HR', array['hr'], 'active', null, null, 'باقة الموارد');
reset role;
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.ok((select count(*) = 0 from public.parties) and not public.fin_can(:'cid', 'sales'), 'without the sales/purchasing modules their records are closed');
select t.err($$select public.post_sales_invoice('$$ || :'cid' || $$', '{"party":"$$ || :'clim' || $$","lines":[{"item":"$$ || :'isv' || $$","qty":1,"price":1}]}')$$, 'غير مشمول في باقة', 'a locked module cannot be used through the API');
select t.ok((select count(*) > 0 from public.employees), 'the HR module stays open in an HR package');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select public.platform_set_subscription(:'cid', 'المالية', array['finance','sales','purch','stock'], 'active', null, null, null);
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok((select count(*) = 0 from public.contracts) and (select count(*) = 0 from public.payroll_runs), 'without the HR module contracts and payroll are closed');
select t.err($$insert into public.policies(company_id, title, body) values ('$$ || :'cid' || $$', 'لائحة', 'نص اللائحة')$$, 'row-level|policy|permission denied', 'HR records cannot be written in a locked module');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select public.platform_set_subscription(:'cid', 'trial', array['hr','finance','sales','purch','stock'], 'trial', current_date - 1, null, null);
reset role;
select t.ok(not public.module_on(:'cid', 'hr') and not public.module_on(:'cid', 'finance'), 'an expired trial closes every module');
select count(*)::int as mcount from public.members where company_id = :'cid' \gset
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select public.platform_set_subscription(:'cid', 'كاملة', array['hr','finance','sales','purch','stock'], 'active', current_date - 1, :mcount, null);
reset role;
select t.ok(public.module_on(:'cid', 'hr') and public.module_on(:'cid', 'sales'), 'an active package ignores the old trial date');
select t.err($$insert into public.members(company_id, user_id, role) values ('$$ || :'cid' || $$', '00000000-0000-0000-0000-000000000021', 'employee')$$, 'الحد الأعلى للمستخدمين', 'the package user cap stops new members');
select t.ok((select count(*) >= 3 from public.audit_log where company_id = :'cid' and entity = 'company_subscriptions'), 'package changes appear in the company audit log');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select public.platform_set_subscription(:'cid', 'كاملة', array['hr','finance','sales','purch','stock'], 'active', null, null, null);
select public.platform_set_settings(array['hr'], 14);
reset role;
insert into public.companies(name) values ('منشأة باقة افتراضية') returning id as cdef \gset
select t.ok((select modules = array['hr'] and trial_ends = current_date + 14 and status = 'trial' from public.company_subscriptions where company_id = :'cdef'), 'new companies get the platform default modules and trial days');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select public.platform_set_settings(array['hr','finance','sales','purch','stock'], null);
reset role;
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select t.err($$select public.platform_set_subscription('$$ || :'cid' || $$', 'x', array['hr'], 'active', null, null, null)$$, '42501|غير مصرح', 'a company owner cannot change its own package');
reset role;

-- ================= CRM (0051) =================
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
insert into public.crm_leads(company_id, title, prospect, contact_name, phone, email, source, value) values (:'cid', 'نظام كاميرات للفرع', 'شركة الرواد', 'سعد', '0551234567', 'Saad@Rowad.test', 'referral', 20000) returning id as op1, no as op1no \gset
select t.ok(:'op1no' like 'OP-%' and (select probability = 10 and email = 'saad@rowad.test' from public.crm_leads where id = :'op1'), 'opportunity numbered with stage probability');
select t.err($$insert into public.crm_leads(company_id, title) values ('$$ || :'cid' || $$', 'فرصة بلا عميل')$$, 'check', 'an opportunity needs a customer or a prospect name');
update public.crm_leads set stage = 'qualified' where id = :'op1';
select t.ok((select probability = 40 from public.crm_leads where id = :'op1'), 'moving the stage updates the probability');
select t.err($$update public.crm_leads set stage = 'lost' where id = '$$ || :'op1' || $$'$$, 'check', 'a lost opportunity needs a reason');
insert into public.crm_activities(company_id, lead_id, kind, due_at, note) values (:'cid', :'op1', 'call', now() + interval '1 day', 'اتصال للمتابعة') returning id as act1 \gset
update public.crm_activities set done = true where id = :'act1';
select t.ok((select done_at is not null from public.crm_activities where id = :'act1'), 'follow-up marked done with time');
select public.crm_make_customer(:'op1') as op1party \gset
select t.ok((select name = 'شركة الرواد' and kind = 'customer' and email = 'saad@rowad.test' from public.parties where id = :'op1party')
  and (select party_id = :'op1party' from public.crm_leads where id = :'op1'), 'prospect becomes a customer linked to the opportunity');
select public.sales_doc_save(:'cid', jsonb_build_object('kind','quote','party', :'op1party','valid_until', current_date + 10,'lines', jsonb_build_array(jsonb_build_object('item', :'isv','qty',2,'price',100)))) as q1 \gset
select public.crm_link_quote(:'op1', :'q1');
select t.ok((select stage = 'proposal' and quote_id = :'q1' and value = 230 from public.crm_leads where id = :'op1'), 'quotation linked: stage proposal and value from the quote');
select public.quote_decide(:'q1', true);
select t.ok((select stage = 'won' and closed_at is not null and probability = 100 from public.crm_leads where id = :'op1'), 'accepted quotation wins the opportunity');
select t.ok((select n = 1 and value = 230 from public.crm_summary(:'cid') where stage = 'won'), 'pipeline summary per stage');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok((select count(*) = 0 from public.crm_leads), 'HR does not see sales opportunities');
reset role;

-- ================= RFQ & SUPPLIER RATING (0052) =================
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
insert into public.parties(company_id, kind, name) values (:'cid', 'supplier', 'مورد العروض أ') returning id as sa \gset
insert into public.parties(company_id, kind, name) values (:'cid', 'supplier', 'مورد العروض ب') returning id as sb \gset
select public.rfq_save(:'cid', jsonb_build_object('title', 'توريد طابعات', 'reply_by', current_date + 7, 'lines', jsonb_build_array(jsonb_build_object('item', :'i1', 'qty', 4)))) as rfq1 \gset
select id as rl1 from public.rfq_lines where rfq_id = :'rfq1' \gset
select public.rfq_quote_save(:'rfq1', jsonb_build_object('party', :'sa', 'delivery_days', 5, 'prices', jsonb_build_array(jsonb_build_object('line', :'rl1', 'price', 900)))) as qa \gset
select public.rfq_quote_save(:'rfq1', jsonb_build_object('party', :'sb', 'delivery_days', 10, 'prices', jsonb_build_array(jsonb_build_object('line', :'rl1', 'price', 850)))) as qb \gset
select t.ok((select total = 4140 from public.rfq_quotes where id = :'qa') and (select total = 3910 from public.rfq_quotes where id = :'qb'), 'supplier offers totalled with VAT');
select t.err($$select public.rfq_quote_save('$$ || :'rfq1' || $$', '{"party":"$$ || :'sa' || $$","prices":[]}')$$, 'سعر كل بند', 'every line needs a price in an offer');
select t.err($$select public.rfq_save('$$ || :'cid' || $$', jsonb_build_object('id', '$$ || :'rfq1' || $$', 'title', 'تعديل', 'lines', jsonb_build_array(jsonb_build_object('item', '$$ || :'i1' || $$', 'qty', 1))))$$, 'وصلت عروض', 'lines are frozen once offers arrive');
select public.rfq_award(:'qb') as rpo \gset
select t.ok((select party_id = :'sb' and total = 3910 and expected_date = current_date + 10 from public.purchase_orders where id = :'rpo')
  and (select status = 'awarded' and po_id = :'rpo' from public.rfqs where id = :'rfq1'), 'awarding an offer creates the purchase order at its prices');
select t.err($$select public.rfq_award('$$ || :'qa' || $$')$$, 'ليس مفتوحاً', 'a request is awarded once');
insert into public.supplier_ratings(company_id, party_id, po_id, quality, delivery, price, service, note) values (:'cid', :'sb', :'rpo', 5, 4, 5, 4, 'ممتاز');
select t.err($$insert into public.supplier_ratings(company_id, party_id, po_id, quality, delivery, price, service) values ('$$ || :'cid' || $$', '$$ || :'sa' || $$', '$$ || :'rpo' || $$', 3, 3, 3, 3)$$, 'row-level', 'a rating must match the order''s supplier');
select t.ok((select ratings = 1 and overall = 4.5 and quotes = 1 and awards = 1 and orders = 1 from public.supplier_scorecard(:'cid') where party_id = :'sb'), 'supplier scorecard: ratings, offers and awards');
reset role;

-- ================= UNITS & SERIALS (0053) =================
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
insert into public.items(company_id, code, name, type, unit, sale_price, track_serial) values (:'cid', 'SN-01', 'جوال بسيريال', 'stock', 'حبة', 2000, true) returning id as isn \gset
insert into public.items(company_id, code, name, type, unit, sale_price) values (:'cid', 'UN-01', 'مياه', 'stock', 'حبة', 2) returning id as iun \gset
insert into public.item_units(company_id, item_id, name, factor, barcode) values (:'cid', :'iun', 'كرتون', 24, '6280000000240');
select t.err($$insert into public.item_units(company_id, item_id, name, factor) values ('$$ || :'cid' || $$', '$$ || :'iun' || $$', 'حبة', 1)$$, 'check', 'an extra unit needs a factor other than 1');
select t.err($$insert into public.items(company_id, code, name, type, track_serial) values ('$$ || :'cid' || $$', 'SN-X', 'خدمة بسيريال', 'service', true)$$, 'المخزنية فقط', 'serials only for stock items');
select public.po_save(:'cid', jsonb_build_object('party', :'sa', 'lines', jsonb_build_array(jsonb_build_object('item', :'isn', 'qty', 2, 'price', 1500)))) as snpo \gset
select id as snpl from public.purchase_order_lines where order_id = :'snpo' \gset
select t.err($$select public.grn_post_sn('$$ || :'snpo' || $$', jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line', $$ || :'snpl' || $$, 'qty', 2, 'serials', jsonb_build_array('A1')))))$$, 'يحتاج 2 رقماً', 'receipt needs one serial per piece');
select public.grn_post_sn(:'snpo', jsonb_build_object('lines', jsonb_build_array(jsonb_build_object('line', :'snpl', 'qty', 2, 'serials', jsonb_build_array('IMEI-001', 'IMEI-002'))))) as sngrn \gset
select t.ok((select count(*) = 2 and bool_and(status = 'in_stock') from public.item_serials where item_id = :'isn'), 'received serials are in stock');
select t.err($$select public.post_sales_invoice_sn('$$ || :'cid' || $$', jsonb_build_object('party', '$$ || :'c1' || $$', 'lines', jsonb_build_array(jsonb_build_object('item', '$$ || :'isn' || $$', 'qty', 1, 'price', 2000, 'serials', jsonb_build_array('IMEI-999')))))$$, 'غير متوفرة', 'cannot sell a serial that is not in stock');
select public.post_sales_invoice_sn(:'cid', jsonb_build_object('party', :'c1', 'lines', jsonb_build_array(jsonb_build_object('item', :'isn', 'qty', 1, 'price', 2000, 'serials', jsonb_build_array('IMEI-001'))))) as sninv \gset
select t.ok((select status = 'sold' and out_id = :'sninv' from public.item_serials where serial = 'IMEI-001'), 'sold serial linked to the invoice');
select t.ok((select count(*) = 1 and max(out_kind) = 'invoice' from public.serial_find(:'cid', 'IMEI-001')), 'serial search shows where a serial went');
select public.void_sales_invoice(:'sninv', 'إلغاء تجربة');
select t.ok((select status = 'in_stock' from public.item_serials where serial = 'IMEI-001'), 'voiding the invoice returns the serial to stock');
reset role;

-- ================= HR EXTRAS (0054) =================
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
insert into public.job_grades(company_id, code, name, min_basic, max_basic) values (:'cid', 'G5', 'الدرجة الخامسة', 8000, 12000) returning id as g5 \gset
select t.err($$insert into public.job_grades(company_id, code, name, min_basic, max_basic) values ('$$ || :'cid' || $$', 'GX', 'خطأ', 9000, 5000)$$, 'check', 'grade maximum above its minimum');
update public.employees set grade_id = :'g5' where id = :'e_emp';
select t.ok((select count(*) = 1 from public.grade_exceptions(:'cid') where employee_id = :'e_emp') = ((select basic from public.employees where id = :'e_emp') not between 8000 and 12000), 'grade exceptions list salaries outside the range');
insert into public.insurance_policies(company_id, provider, policy_no, start_date, end_date) values (:'cid', 'شركة التأمين', 'POL-1', current_date - 30, current_date + 30) returning id as pol \gset
insert into public.insurance_members(company_id, policy_id, employee_id, class) values (:'cid', :'pol', :'e_emp', 'A');
insert into public.insurance_members(company_id, policy_id, employee_id, relation, name, birth_date, class) values (:'cid', :'pol', :'e_emp', 'son', 'عبدالله الابن', '2015-05-01', 'A');
select t.err($$insert into public.insurance_members(company_id, policy_id, employee_id, relation) values ('$$ || :'cid' || $$', '$$ || :'pol' || $$', '$$ || :'e_emp' || $$', 'spouse')$$, 'check', 'a dependant needs a name');
select t.ok((select count(*) filter (where kind = 'policy_ending') = 1 and not bool_or(employee_id = :'e_emp') from public.insurance_alerts(:'cid'))
  and exists(select 1 from public.insurance_alerts(:'cid') where kind = 'uninsured'), 'insurance alerts: uninsured employees and policies ending soon');
insert into public.training_plans(company_id, year, title, quarter, budget, hours) values (:'cid', 2026, 'تطوير المشرفين', 2, 15000, 24) returning id as tp \gset
select t.ok((select planned = 1 and budget = 15000 from public.training_plan_summary(:'cid', 2026)), 'training plan summary with budget');
reset role;
select set_config('request.jwt.claim.sub', :'u_emp', false); set role authenticated;
select t.ok((select count(*) = 2 from public.insurance_members) and (select count(*) = 0 from public.job_grades), 'employee sees own insurance cover but not the grade table');
reset role;

-- ================= COMPANY EXPORT (0055) =================
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select public.company_export(:'cid') as exp \gset
reset role;
select t.ok((select jsonb_array_length((:'exp'::jsonb)->'tables'->'employees') = count(*) from public.employees where company_id = :'cid')
  and (select jsonb_array_length((:'exp'::jsonb)->'tables'->'rfq_quote_lines') = 2), 'export holds the company tables and their line tables');
select t.ok(not exists(select 1 from jsonb_each((:'exp'::jsonb)->'tables') tb, jsonb_array_elements(tb.value) r where r->>'company_id' = :'cid2' or r->>'id' = :'cid2'), 'export never contains another company''s rows');
select t.ok((select bool_and(not (r ? 'data')) and count(*) >= 1 from jsonb_array_elements((:'exp'::jsonb)->'tables'->'request_attachments') r), 'attachments left out unless asked for');
select t.ok(not ((:'exp'::jsonb)->'tables' ? 'platform_admins') and not ((:'exp'::jsonb)->'tables' ? 'client_errors'), 'platform tables are not exported');
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select t.ok((select bool_and(r ? 'data') from jsonb_array_elements(public.company_export(:'cid', true)->'tables'->'request_attachments') r), 'export with files includes the attachment contents');
reset role;
select t.ok((select count(*) = 2 from public.audit_log where company_id = :'cid' and action = 'export'), 'every export is written to the audit log');
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.err($$select public.company_export('$$ || :'cid' || $$')$$, 'لمالك المنشأة فقط', 'only the owner exports the company data');
reset role;
select set_config('request.jwt.claim.sub', :'u_other', false); set role authenticated;
select t.err($$select public.company_export('$$ || :'cid' || $$')$$, 'لمالك المنشأة فقط', 'another company''s owner cannot export it');
reset role;
select set_config('request.jwt.claim.sub', :'u_owner', false); set role authenticated;
select public.company_export(:'cid') is not null as x1 \gset
select public.company_export(:'cid') is not null as x2 \gset
select public.company_export(:'cid') is not null as x3 \gset
select t.err($$select public.company_export('$$ || :'cid' || $$')$$, 'انتظر ساعة', 'at most five exports an hour');
reset role;

-- ================= AUDIT =================
select t.ok((select count(*) from public.audit_log where company_id = :'cid' and entity = 'employees') >= 6, 'employee changes audited');
select t.err($$delete from public.audit_log$$, 'append-only', 'audit log is append-only');

-- ================= ADMIN SITE: website counter, website texts, announcements (0062) =================
select set_config('request.jwt.claim.sub', '', false); set role anon;
select public.site_hit('home', 'whatsapp', 'mobile', 'ar', 'visit');
select public.site_hit('home', 'whatsapp', 'mobile', 'ar', 'view');
select public.site_hit('home', 'whatsapp', 'mobile', 'ar', 'cta');
select public.site_hit('home', 'evil.example', 'fridge', 'fr', 'view');
select public.site_hit('../app', 'direct', 'mobile', 'ar', 'view');
select t.err($$select * from public.site_stats$$, 'permission denied', 'anon cannot read the visitor counts');
select t.err($$select * from public.platform_site_stats(30)$$, 'permission denied|42501', 'anon cannot open the website stats');
select t.ok(public.site_content() = '{}'::jsonb, 'website texts start empty (the built-in text shows)');
select t.err($$select public.platform_set_site_content('banner', '{"on":true,"ar":"x"}')$$, 'permission denied|42501', 'anon cannot change website texts');
select t.err($$select * from public.my_announcements()$$, 'permission denied', 'anon cannot read announcements');
reset role;
select t.ok((select views = 2 and visits = 1 and cta = 1 from public.site_stats where page = 'home' and source = 'whatsapp' and device = 'mobile'), 'a visit, a view and a trial click are counted in one daily row');
select t.ok((select views = 1 from public.site_stats where page = 'home' and source = 'other' and device = 'desktop' and lang = 'ar'), 'unknown source/device/language fold into safe values');
select t.ok(not exists(select 1 from public.site_stats where page not in ('home','modules','trust','contact')), 'unknown pages are not counted');
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.err($$select * from public.platform_site_stats(30)$$, '42501|غير مصرح', 'a company user cannot open the website stats');
select t.err($$select public.platform_save_announcement(null, 'x', null, 'info', null, null)$$, '42501|غير مصرح', 'a company user cannot post announcements');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select t.ok((select sum(views) = 3 from public.platform_site_stats(30)), 'platform admin reads the website stats');
select public.platform_set_site_content('contact', '{"phone":"966500000001","email":"hello@waad.test"}');
select public.platform_set_site_content('banner', '{"on":true,"ar":"عرض خاص","en":"Special offer"}');
select t.err($$select public.platform_set_site_content('contact', '{"phone":"0500","email":"x"}')$$, 'غير صحيح', 'a wrong phone or e-mail is refused');
select t.err($$select public.platform_set_site_content('faq', '{"q":"x"}')$$, 'غير معروف', 'the FAQ must be a list');
select t.err($$select public.platform_set_site_content('script', '{}')$$, 'غير معروف', 'only known website texts can be set');
select public.platform_save_announcement(null, 'صيانة الليلة', 'Maintenance tonight', 'warn', current_date, current_date + 1) as ann \gset
select public.platform_save_announcement(null, 'إعلان قديم', null, 'info', current_date - 10, current_date - 5);
select t.err($$select public.platform_save_announcement(null, 'x', null, 'info', current_date, current_date - 1)$$, 'قبل البداية', 'an announcement cannot end before it starts');
reset role;
select set_config('request.jwt.claim.sub', '', false); set role anon;
select t.ok(public.site_content()->'contact'->>'phone' = '966500000001' and public.site_content()->'banner'->>'en' = 'Special offer', 'the website reads the texts the admin saved');
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok((select count(*) = 1 and bool_and(body_en = 'Maintenance tonight') from public.my_announcements()), 'every signed-in user sees the current announcement only');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select public.platform_delete_announcement(:'ann');
select public.platform_set_site_content('banner', null);
reset role;
select set_config('request.jwt.claim.sub', :'u_hr', false); set role authenticated;
select t.ok((select count(*) = 0 from public.my_announcements()), 'a deleted announcement disappears');
reset role;
select t.ok(not (public.site_content() ? 'banner'), 'clearing a text brings the built-in one back');

-- ================= ADMIN TEAM: username sign-in, added by an admin (0063) =================
insert into auth.users(id, email, created_at) values ('00000000-0000-0000-0000-0000000000b1', 'sara@admin.waad.app', now());
insert into auth.users(id, email, created_at) values ('00000000-0000-0000-0000-0000000000b2', 'old@admin.waad.app', now() - interval '1 day');
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.err($$select public.platform_add_admin('sara')$$, '42501|غير مصرح', 'a company user cannot add Waad team members');
select t.err($$select * from public.platform_team()$$, '42501|غير مصرح', 'a company user cannot list the Waad team');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select public.platform_add_admin('Sara');
select t.err($$select public.platform_add_admin('old')$$, 'محجوز', 'an address someone registered earlier cannot be made an admin');
select t.err($$select public.platform_add_admin('nobody')$$, 'لم يُنشأ', 'a username without an account is refused');
select t.err($$select public.platform_add_admin('a b')$$, 'اسم المستخدم', 'usernames are latin letters and digits only');
select t.err($$select public.platform_add_admin('sara')$$, 'مستخدم مسبقاً', 'a username is used once');
select t.ok((select count(*) = 2 and bool_or(username = 'sara' and must_change and not is_me) from public.platform_team()), 'the team list shows the new member with a temporary password');
select public.platform_reset_admin_password('sara', 'NewTemp123');
select t.err($$select public.platform_reset_admin_password('sara', 'short')$$, '8 أحرف', 'team passwords are 8 characters or more');
reset role;
select t.ok((select encrypted_password = crypt('NewTemp123', encrypted_password) from auth.users where id = '00000000-0000-0000-0000-0000000000b1'), 'an admin resets a team member''s password');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false); set role authenticated;
select t.ok(public.is_platform_admin() and (public.platform_admin_me()->>'must_change')::boolean, 'the new member is an admin and must change the temporary password');
select public.password_changed();
select t.ok(not (public.platform_admin_me()->>'must_change')::boolean, 'changing the password clears the temporary flag');
select t.err($$select public.platform_remove_admin('sara')$$, 'حسابك', 'an admin cannot remove themself');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select public.platform_remove_admin('sara');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false); set role authenticated;
select t.ok(not public.is_platform_admin(), 'a removed member loses the admin site');
reset role;

-- ================= NEW COMPANIES WAIT FOR APPROVAL; SUBSCRIPTION LENGTH IN DAYS (0068) =================
update public.platform_settings set require_approval = true;
insert into public.companies(name) values ('منشأة بانتظار القبول') returning id as cpend \gset
select t.ok((select status = 'pending' and notified_at is null from public.company_subscriptions where company_id = :'cpend'), 'a new company waits for approval and is queued for a notification');
select t.ok(not public.module_on(:'cpend', 'hr'), 'a waiting company has every module closed');
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.err($$select public.platform_approve('$$ || :'cpend' || $$', 'trial', 7)$$, '42501|غير مصرح', 'a company user cannot approve companies');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select t.ok((select status = 'pending' from public.platform_companies() limit 1), 'waiting companies come first in the admin list');
select public.platform_approve(:'cpend', 'trial', 7);
reset role;
select t.ok((select status = 'trial' and trial_ends = current_date + 7 from public.company_subscriptions where company_id = :'cpend') and public.module_on(:'cpend', 'hr'), 'approved as a 7-day trial: open until the last day');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select public.platform_approve(:'cpend', 'active', 30);
reset role;
select t.ok((select status = 'active' and sub_ends = current_date + 30 and trial_ends is null and plan = 'اشتراك' from public.company_subscriptions where company_id = :'cpend'), 'approved as a 30-day subscription');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select public.platform_set_subscription(:'cpend', 'اشتراك', array['hr'], 'active', null, null, null, current_date - 1);
reset role;
select t.ok(not public.module_on(:'cpend', 'hr'), 'a subscription past its end date closes the modules');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select t.err($$select public.platform_approve('$$ || :'cpend' || $$', 'active', 0)$$, 'المدة', 'a length of zero days is refused');
select public.platform_approve(:'cpend', 'active', null);
select public.platform_set_settings(array['hr','finance','sales','purch','stock','proj'], 7, false);
reset role;
select t.ok(public.module_on(:'cpend', 'hr') and (select sub_ends is null from public.company_subscriptions where company_id = :'cpend'), 'a subscription without an end date stays open');
insert into public.companies(name) values ('منشأة بدون قبول') returning id as cnoap \gset
select t.ok((select status = 'trial' and trial_ends = current_date + 7 from public.company_subscriptions where company_id = :'cnoap'), 'with approval switched off a new company starts its trial at once');
update public.platform_settings set require_approval = false;

-- ================= ADMIN: PLANS, PAYMENTS, NOTES, QUICK ACTIONS, HISTORY (0069) =================
select set_config('request.jwt.claim.sub', :'u_fin', false); set role authenticated;
select t.err($$select * from public.platform_plans_list()$$, '42501|غير مصرح', 'a company user cannot see Waad price plans');
select t.err($$select public.platform_add_payment('$$ || :'cid' || $$', 100, null, 'transfer', null, 30, null)$$, '42501|غير مصرح', 'a company user cannot record payments');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select public.platform_save_plan('{"name":"الأساسية","price":299,"period_days":30,"modules":["hr"],"max_users":10}') as plan1 \gset
select t.err($$select public.platform_save_plan('{"name":"الأساسية","price":1}')$$, 'مستخدم مسبقاً', 'plan names are unique');
reset role;
insert into public.companies(name) values ('منشأة الفوترة') returning id as cbill \gset
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select public.platform_add_payment(:'cbill', 299, current_date, 'transfer', :'plan1', null, 'تحويل بنكي');
reset role;
select t.ok((select status = 'active' and sub_ends = current_date + 29 and plan = 'الأساسية' and modules = array['hr'] and max_users = 10 from public.company_subscriptions where company_id = :'cbill'),
  'a payment on a plan activates the subscription for the plan period with its modules and user cap');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select public.platform_add_payment(:'cbill', 299, current_date, 'card', :'plan1', null, null);
reset role;
select t.ok((select sub_ends = current_date + 59 from public.company_subscriptions where company_id = :'cbill'), 'a renewal before the end adds the period after the current end');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select public.platform_quick(:'cbill', 'extend', 10);
select public.platform_quick(:'cbill', 'suspend');
reset role;
select t.ok((select status = 'suspended' and sub_ends = current_date + 69 from public.company_subscriptions where company_id = :'cbill') and not public.module_on(:'cbill', 'hr'), 'quick actions: extend 10 days, then suspend closes the company');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false); set role authenticated;
select public.platform_quick(:'cbill', 'resume');
select public.platform_add_note(:'cbill', 'اتصلت بالمالك، يبي باقة أكبر');
select t.ok((select status = 'active' from public.platform_companies() where company_id = :'cbill'), 'resume brings the subscription back');
select t.ok((select jsonb_array_length(d->'payments') = 2 and jsonb_array_length(d->'notes') = 1 and d->'notes'->0->>'by' = 'platform@waad.test'
   and jsonb_array_length(d->'history') >= 3 and d->'history'->0->>'status' = 'active' and d->'company'->>'name' = 'منشأة الفوترة' from (select public.platform_company(:'cbill') d) x),
  'the company page brings payments, notes (with who wrote them) and the subscription history');
select t.ok((select sum(amount) = 598 from public.platform_payments_list(current_date - 1, current_date + 1) where company_id = :'cbill'), 'payments are listed by date for the revenue view');
select t.err($$select public.platform_quick('$$ || :'cbill' || $$', 'explode')$$, 'غير معروف', 'unknown quick actions are refused');
reset role;

select format('%s passed, %s failed', count(*) filter (where ok), count(*) filter (where not ok)) as summary from t.results \gset
\warn :summary
