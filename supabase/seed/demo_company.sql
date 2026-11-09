-- Demo company with fictional data, owned by an existing account (by email). Re-runnable guard: skips if the owner already has a company.
do $$
declare
  owner_email text := 'abuomara4@gmail.com';
  uid uuid; cid uuid; d jsonb; e jsonb; r record;
  dep jsonb := '{}'; emp jsonb := '{}';
  c1 uuid; c2 uuid; s1 uuid; s2 uuid; i1 uuid; i2 uuid; i3 uuid; inv uuid; run uuid;
begin
  select id into uid from auth.users where lower(email) = owner_email;
  if uid is null then raise exception 'no auth user %', owner_email; end if;
  if exists(select 1 from public.members where user_id = uid) then raise notice 'owner already has a company — skipped'; return; end if;
  perform set_config('request.jwt.claim.sub', uid::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'email', owner_email, 'role', 'authenticated')::text, true);

  cid := public.create_company('مؤسسة الأفق التجريبية', '300000000000003', '1010000000');
  update public.companies set address = 'الرياض — حي العليا (عنوان تجريبي)' where id = cid;

  for r in select * from (values ('admin','الإدارة'),('hr','الموارد البشرية'),('fin','المالية'),('sales','المبيعات'),('tech','التقنية'),('wh','المستودع')) v(k,n) loop
    insert into public.departments(company_id, name) values (cid, r.n) returning jsonb_build_object(r.k, id) into d;
    dep := dep || d;
  end loop;

  -- emp_no, name, saudi, gender, title, dept, manager emp_no, hire, basic, housing, transport, national id, phone
  for r in select * from (values
    ('1000','عبدالعزيز (المدير العام)',true,'m','المدير العام','admin',null,'2019-01-01'::date,25000,6250,1500,'1000000001','0500000001'),
    ('1001','نورة القحطاني',true,'f','مديرة الموارد البشرية','hr','1000','2020-03-15',15000,3750,1000,'1000000002','0500000002'),
    ('1002','فيصل العنزي',true,'m','المدير المالي','fin','1000','2020-06-01',16000,4000,1000,'1000000003','0500000003'),
    ('1003','ريم الشمري',true,'f','محاسبة','fin','1002','2022-09-01',8000,2000,700,'1000000004','0500000004'),
    ('1004','سلطان الحربي',true,'m','مدير المبيعات','sales','1000','2021-02-01',12000,3000,1000,'1000000005','0500000005'),
    ('1005','محمد العتيبي',true,'m','مندوب مبيعات','sales','1004','2023-05-10',6000,1500,600,'1000000006','0500000006'),
    ('1006','أحمد خان',false,'m','أمين مستودع','wh','1002','2021-11-20',4500,1125,400,'2000000007','0500000007'),
    ('1007','سارة الدوسري',true,'f','مطوّرة برمجيات','tech','1000','2025-02-01',11000,2750,800,'1000000008','0500000008'),
    ('1008','راجيش كومار',false,'m','فني دعم','tech','1007','2024-08-15',5000,1250,500,'2000000009','0500000009')
  ) v(no,nm,sa,g,t,dp,mg,h,b,ho,tr,nid,ph) loop
    insert into public.employees(company_id, emp_no, full_name, is_saudi, gender, job_title, department_id, manager_id, hire_date, basic, housing, transport, national_id, phone, iban)
    values (cid, r.no, r.nm, r.sa, r.g, r.t, (dep->>r.dp)::uuid, (emp->>r.mg)::uuid, r.h, r.b, r.ho, r.tr, r.nid, r.ph, 'SA00' || lpad(r.no, 20, '0'))
    returning jsonb_build_object(r.no, id) into e;
    emp := emp || e;
  end loop;
  update public.members set employee_id = (emp->>'1000')::uuid where company_id = cid and user_id = uid;

  -- opening capital into the bank
  perform public.post_manual_journal(cid, '2026-09-01', 'رأس المال الافتتاحي (تجريبي)', '[{"a":"1120","d":300000},{"a":"3100","c":300000}]');

  insert into public.parties(company_id, kind, name, vat_no, phone, city) values (cid,'customer','شركة النخبة للتجارة (تجريبي)','310000000000003','0550000101','الرياض') returning id into c1;
  insert into public.parties(company_id, kind, name, phone, city) values (cid,'customer','مؤسسة الريادة (تجريبي)','0550000102','جدة') returning id into c2;
  insert into public.parties(company_id, kind, name, vat_no, phone, city) values (cid,'supplier','شركة التوريدات المتحدة (تجريبي)','311111111111113','0550000201','الدمام') returning id into s1;
  insert into public.parties(company_id, kind, name, phone, city) values (cid,'supplier','مؤسسة المكتب الحديث (تجريبي)','0550000202','الرياض') returning id into s2;
  insert into public.items(company_id, code, name, type, unit, sale_price, reorder_level) values (cid,'IT-001','حاسب محمول','stock','حبة',3500,3) returning id into i1;
  insert into public.items(company_id, code, name, type, unit, sale_price, reorder_level) values (cid,'IT-002','طابعة ليزر','stock','حبة',900,2) returning id into i2;
  insert into public.items(company_id, code, name, type, unit, sale_price) values (cid,'SV-001','خدمة دعم فني (شهري)','service','شهر',500) returning id into i3;

  perform public.post_purchase_bill(cid, jsonb_build_object('party', s1, 'date', '2026-10-01', 'due', '2026-10-31', 'ref', 'UT-5521', 'lines',
    jsonb_build_array(jsonb_build_object('item', i1, 'qty', 10, 'price', 2800), jsonb_build_object('item', i2, 'qty', 6, 'price', 650))));
  perform public.post_purchase_bill(cid, jsonb_build_object('party', s2, 'date', '2026-10-02', 'due', '2026-10-02', 'ref', 'MH-118', 'note', 'إيجار مكتب أكتوبر',
    'lines', jsonb_build_array(jsonb_build_object('account', '5300', 'qty', 1, 'price', 8000))));
  perform public.record_payment(cid, jsonb_build_object('direction', 'out', 'party', s2, 'amount', 9200, 'date', '2026-10-02', 'account', '1120',
    'bill', (select id from public.purchase_bills where company_id = cid and supplier_ref = 'MH-118')));
  perform public.record_payment(cid, jsonb_build_object('direction', 'out', 'party', s1, 'amount', 20000, 'date', '2026-10-12', 'account', '1120',
    'bill', (select id from public.purchase_bills where company_id = cid and supplier_ref = 'UT-5521')));

  inv := public.post_sales_invoice(cid, jsonb_build_object('party', c1, 'date', '2026-10-10', 'due', '2026-10-25', 'lines',
    jsonb_build_array(jsonb_build_object('item', i1, 'qty', 3, 'price', 3500), jsonb_build_object('item', i2, 'qty', 2, 'price', 900), jsonb_build_object('item', i3, 'qty', 2, 'price', 500))));
  perform public.record_payment(cid, jsonb_build_object('direction', 'in', 'party', c1, 'amount', 8000, 'date', '2026-10-15', 'account', '1120', 'invoice', inv));
  perform public.post_sales_invoice(cid, jsonb_build_object('party', c2, 'date', '2026-09-20', 'due', '2026-10-05', 'lines',
    jsonb_build_array(jsonb_build_object('item', i1, 'qty', 1, 'price', 3500))));

  -- September payroll: prepared, approved and paid
  run := public.payroll_prepare(cid, 2026, 9, '2026-09-27');
  perform public.payroll_adjust(run, (emp->>'1005')::uuid, 6, 500, 0);
  perform public.payroll_approve(run);
  perform public.payroll_mark_paid(run, '1120');
  -- October payroll left as a draft to review
  perform public.payroll_prepare(cid, 2026, 10, '2026-10-27');

  raise notice 'demo company % code %', cid, (select code from public.companies where id = cid);
end $$;
