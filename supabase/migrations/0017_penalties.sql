-- Violations and disciplinary penalties (Labor Law Arts. 66–73) with the violations-and-penalties tables of the model
-- work regulation (lateness/absence, work organisation, conduct). Each step is the penalty for the 1st…4th occurrence.
-- Step tokens: W = written warning, pN = N% of a day's wage, dN = N days' wage, defer = defer promotion or withhold the
-- raise once, defer80 = the same plus a written dismissal warning under Art. 80, eos = dismissal with end-of-service award,
-- a80 = dismissal under Art. 80 (no award, notice or compensation), '-' = no further step.

create table public.violation_types (
  code text primary key,
  cat text not null check (cat in ('time','org','conduct')),
  no int not null,
  title text not null,
  steps text[] not null check (cardinality(steps) = 4),
  extra text check (extra in ('late','absence','left')),   -- "in addition to deducting the wage of …"
  note text
);
insert into public.violation_types(code, cat, no, title, steps, extra, note) values
 ('T01','time',1,'التأخر عن مواعيد الحضور للعمل لغاية 15 دقيقة دون إذن أو عذر مقبول، إذا لم يترتب على ذلك تعطيل عمال آخرين','{W,p5,p10,p20}',null,null),
 ('T02','time',2,'التأخر عن مواعيد الحضور للعمل لغاية 15 دقيقة دون إذن أو عذر مقبول، إذا ترتب على ذلك تعطيل عمال آخرين','{W,p15,p25,p50}',null,null),
 ('T03','time',3,'التأخر عن مواعيد الحضور للعمل أكثر من 15 دقيقة لغاية 30 دقيقة دون إذن أو عذر مقبول، إذا لم يترتب على ذلك تعطيل عمال آخرين','{p10,p15,p25,p50}',null,null),
 ('T04','time',4,'التأخر عن مواعيد الحضور للعمل أكثر من 15 دقيقة لغاية 30 دقيقة دون إذن أو عذر مقبول، إذا ترتب على ذلك تعطيل عمال آخرين','{p25,p50,p75,d1}',null,null),
 ('T05','time',5,'التأخر عن مواعيد الحضور للعمل أكثر من 30 دقيقة لغاية 60 دقيقة دون إذن أو عذر مقبول، إذا لم يترتب على ذلك تعطيل عمال آخرين','{p25,p50,p75,d1}',null,null),
 ('T06','time',6,'التأخر عن مواعيد الحضور للعمل أكثر من 30 دقيقة لغاية 60 دقيقة دون إذن أو عذر مقبول، إذا ترتب على ذلك تعطيل عمال آخرين','{p30,p50,d1,d2}','late',null),
 ('T07','time',7,'التأخر عن مواعيد الحضور للعمل لمدة تزيد على ساعة دون إذن أو عذر مقبول، سواء ترتب أو لم يترتب على ذلك تعطيل عمال آخرين','{W,d1,d2,d3}','late',null),
 ('T08','time',8,'ترك العمل أو الانصراف قبل الميعاد دون إذن أو عذر مقبول بما لا يتجاوز 15 دقيقة','{W,p10,p25,d1}','left',null),
 ('T09','time',9,'ترك العمل أو الانصراف قبل الميعاد دون إذن أو عذر مقبول بما يتجاوز 15 دقيقة','{p10,p25,p50,d1}','left',null),
 ('T10','time',10,'البقاء في أماكن العمل أو العودة إليها بعد انتهاء مواعيد العمل دون إذن مسبق','{W,p10,p25,d1}',null,null),
 ('T11','time',11,'الغياب دون إذن كتابي أو عذر مقبول لمدة يوم خلال السنة العقدية الواحدة','{p50,d1,d2,d3}',null,null),
 ('T12','time',12,'الغياب المتصل دون إذن كتابي أو عذر مقبول من يومين إلى ستة أيام خلال السنة العقدية الواحدة','{d2,d3,d4,defer}','absence',null),
 ('T13','time',13,'الغياب المتصل دون إذن كتابي أو عذر مقبول من سبعة أيام إلى عشرة أيام خلال السنة العقدية الواحدة','{d4,d5,defer,eos}','absence','الفصل في المرة الرابعة مع المكافأة إذا لم يتجاوز مجموع الغياب 30 يوماً'),
 ('T14','time',14,'الغياب المتصل دون إذن كتابي أو عذر مقبول من أحد عشر يوماً إلى أربعة عشر يوماً خلال السنة العقدية الواحدة','{d5,defer80,a80,-}','absence',null),
 ('T15','time',15,'الانقطاع عن العمل دون سبب مشروع مدة تزيد على خمسة عشر يوماً متصلة خلال السنة العقدية الواحدة','{a80,a80,a80,a80}',null,'على أن يسبقه إنذار كتابي بعد الغياب مدة عشرة أيام، في نطاق حكم المادة 80'),
 ('T16','time',16,'الغياب المتقطع دون سبب مشروع مدداً تزيد في مجموعها على ثلاثين يوماً خلال السنة العقدية الواحدة','{a80,a80,a80,a80}',null,'على أن يسبقه إنذار كتابي بعد الغياب مدة عشرين يوماً، في نطاق حكم المادة 80'),
 ('O01','org',1,'التواجد دون مبرر في غير مكان العمل المخصص للعامل أثناء وقت الدوام','{p10,p25,p50,d1}',null,null),
 ('O02','org',2,'استقبال زائرين في غير أمور عمل المنشأة في أماكن العمل دون إذن من الإدارة','{W,p10,p15,p25}',null,null),
 ('O03','org',3,'استعمال آلات ومعدات وأدوات المنشأة لأغراض خاصة دون إذن','{W,p10,p25,p50}',null,null),
 ('O04','org',4,'تدخل العامل دون وجه حق في أي عمل ليس في اختصاصه أو لم يعهد به إليه','{p50,d1,d2,d3}',null,null),
 ('O05','org',5,'الخروج أو الدخول من غير المكان المخصص لذلك','{W,p10,p15,p25}',null,null),
 ('O06','org',6,'الإهمال في تنظيف الآلات وصيانتها أو عدم العناية بها أو عدم التبليغ عن ما بها من خلل','{p50,d1,d2,d3}',null,null),
 ('O07','org',7,'عدم وضع أدوات الإصلاح والصيانة واللوازم الأخرى في الأماكن المخصصة لها بعد الانتهاء من العمل','{W,p25,p50,d1}',null,null),
 ('O08','org',8,'تمزيق أو إتلاف إعلانات أو بلاغات إدارة المنشأة','{d2,d3,d5,eos}',null,null),
 ('O09','org',9,'الإهمال في العهد التي بحوزته، مثل: سيارات، آلات، أجهزة، معدات، أدوات','{d2,d3,d5,eos}',null,null),
 ('O10','org',10,'الأكل في مكان العمل أو غير المكان المعد له أو في غير أوقات الراحة','{W,p10,p15,p25}',null,null),
 ('O11','org',11,'النوم أثناء العمل','{W,p10,p25,p50}',null,null),
 ('O12','org',12,'النوم في الحالات التي تستدعي يقظة مستمرة','{p50,d1,d2,d3}',null,null),
 ('O13','org',13,'التسكع أو وجود العامل في غير مكان عمله أثناء ساعات العمل','{p10,p25,p50,d1}',null,null),
 ('O14','org',14,'التلاعب في إثبات الحضور والانصراف','{d1,d2,defer,eos}',null,null),
 ('O15','org',15,'عدم إطاعة الأوامر العادية الخاصة بالعمل أو عدم تنفيذ التعليمات الخاصة بالعمل والمعلقة في مكان ظاهر','{p25,p50,d1,d2}',null,null),
 ('O16','org',16,'التحريض على مخالفة الأوامر والتعليمات الخطية الخاصة بالعمل','{d2,d3,d5,eos}',null,null),
 ('O17','org',17,'التدخين في الأماكن المحظورة والمعلن عنها للمحافظة على سلامة العمال والمنشأة','{d2,d3,d5,eos}',null,null),
 ('O18','org',18,'الإهمال أو التهاون في العمل الذي قد ينشأ عنه ضرر في صحة العمال أو سلامتهم أو في المواد أو الأدوات أو الأجهزة','{d2,d3,d5,eos}',null,null),
 ('C01','conduct',1,'التشاجر مع الزملاء أو مع الغير أو إحداث مشاغبات في مكان العمل','{d1,d2,d3,d5}',null,null),
 ('C02','conduct',2,'التمارض أو ادعاء العامل كذباً أنه أصيب أثناء العمل أو بسببه','{d1,d2,d3,d5}',null,null),
 ('C03','conduct',3,'الامتناع عن إجراء الكشف الطبي عند طلب طبيب المنشأة أو رفض اتباع التعليمات الطبية أثناء العلاج','{d1,d2,d3,d5}',null,null),
 ('C04','conduct',4,'مخالفة التعليمات الصحية المعلقة بأماكن العمل','{p50,d1,d2,d5}',null,null),
 ('C05','conduct',5,'الكتابة على جدران المنشأة أو لصق إعلانات عليها','{W,p10,p25,p50}',null,null),
 ('C06','conduct',6,'رفض التفتيش الإداري عند الانصراف','{p25,p50,d1,d2}',null,null),
 ('C07','conduct',7,'عدم تسليم النقود المحصلة لحساب المنشأة في المواعيد المحددة دون تبرير مقبول','{d2,d3,d5,eos}',null,null),
 ('C08','conduct',8,'الامتناع عن ارتداء الملابس والأجهزة المقررة للوقاية وللسلامة','{W,d1,d2,d5}',null,null),
 ('C09','conduct',9,'تعمد الخلوة مع الجنس الآخر في أماكن العمل','{d2,d3,d5,eos}',null,null),
 ('C10','conduct',10,'الإيحاء للآخرين بما يخدش الحياء قولاً أو فعلاً','{d2,d3,d5,eos}',null,null),
 ('C11','conduct',11,'الاعتداء على زملاء العمل بالقول أو الإشارة أو باستعمال وسائل الاتصال الإلكترونية بالشتم أو التحقير','{d2,d3,d5,eos}',null,null),
 ('C12','conduct',12,'الاعتداء بالإيذاء الجسدي على زملاء العمل أو على غيرهم بطريقة إباحية','{a80,a80,a80,a80}',null,null),
 ('C13','conduct',13,'الاعتداء الجسدي أو القولي أو بأي وسيلة من وسائل الاتصال الإلكترونية على صاحب العمل أو المدير المسؤول أو أحد الرؤساء أثناء العمل أو بسببه','{a80,a80,a80,a80}',null,null),
 ('C14','conduct',14,'تقديم بلاغ أو شكوى كيدية','{d3,d5,eos,-}',null,null),
 ('C15','conduct',15,'عدم الامتثال لطلب لجنة التحقيق بالحضور','{d2,d3,d5,eos}',null,null),
 ('C16','conduct',16,'عدم التقيد بالزي الرسمي المعتمد بالمنشأة','{d1,d2,d3,d5}',null,null);

-- a day's wage for fines: actual wage (basic + allowances, the default) or basic wage only, divided by 30
alter table public.companies add column penalty_base text not null default 'gross' check (penalty_base in ('gross','basic'));

create table public.penalties (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  code text not null references public.violation_types(code),
  occurred_on date not null,
  discovered_on date not null,
  description text,
  step int not null check (step between 1 and 4),
  action text not null,
  daily_wage numeric(12,2) not null default 0,
  fine numeric(12,2) not null default 0 check (fine >= 0),
  status text not null default 'open' check (status in ('open','applied','dropped','overturned')),
  emp_defense text,                     -- written reply by the employee
  inv_mode text check (inv_mode in ('written','oral','refused')),
  inv_on date, inv_text text,           -- investigation minutes (Art. 71)
  decided_on date, notified_on date, decision_note text,   -- written decision and its notification (Art. 72)
  griev_on date, griev_text text, griev_result text check (griev_result in ('upheld','overturned')), griev_on_decided date, griev_note text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check (discovered_on >= occurred_on)
);
create index on public.penalties(employee_id, code);
create index on public.penalties(company_id, status);
create table public.penalty_deductions (
  run_id uuid not null references public.payroll_runs(id) on delete cascade,
  penalty_id uuid not null references public.penalties(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  primary key (run_id, penalty_id)
);
alter table public.payroll_lines add column penalty_fine numeric(12,2) not null default 0;

-- the step for a new violation: Art. 68 — repeat counts only if it falls within 180 days of the notification of the
-- previous penalty for the same violation; otherwise it starts again from the first step
create or replace function public.pen_step(p_emp uuid, p_code text, p_on date, p_self uuid default null) returns int
language sql stable security definer set search_path = public as $$
  select coalesce((select case when p_on - p.notified_on <= 180 then least(p.step + 1, 4) else 1 end
    from public.penalties p where p.employee_id = p_emp and p.code = p_code and p.status = 'applied' and p.notified_on is not null
      and p.notified_on <= p_on and p.id is distinct from p_self
    order by p.notified_on desc, p.created_at desc limit 1), 1)
$$;

create or replace function public.pen_calc(p_emp uuid, p_code text, p_on date, p_self uuid default null)
returns table(step int, action text, daily_wage numeric, fine numeric)
language plpgsql stable security definer set search_path = public as $$
declare v public.violation_types; e public.employees; base text; s int; a text; dw numeric;
begin
  select * into v from public.violation_types where code = p_code;
  if not found then raise exception 'المخالفة غير موجودة في جدول المخالفات — م67'; end if;
  select * into e from public.employees where id = p_emp;
  select penalty_base into base from public.companies where id = e.company_id;
  s := public.pen_step(p_emp, p_code, p_on, p_self);
  a := v.steps[s];
  while a = '-' and s > 1 loop s := s - 1; a := v.steps[s]; end loop;   -- no further step: keep the last one
  dw := round(case when base = 'basic' then e.basic else e.basic + e.housing + e.transport end / 30, 2);
  return query select s, a, dw,
    least(round(dw * 5, 2),   -- Art. 70: a fine for one violation never exceeds five days' wage
      case when a ~ '^p[0-9]+$' then round(dw * substr(a, 2)::numeric / 100, 2)
           when a ~ '^d[0-9]+$' then round(dw * substr(a, 2)::numeric, 2) else 0 end);
end $$;

create or replace function public.pen_preview(p_emp uuid, p_code text, p_on date)
returns table(step int, action text, daily_wage numeric, fine numeric) language plpgsql stable security definer set search_path = public as $$
declare c uuid;
begin
  select company_id into c from public.employees where id = p_emp;
  if not public.has_role(c, array['owner','admin','hr']) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  return query select * from public.pen_calc(p_emp, p_code, p_on);
end $$;

-- accusation (written notice of what is attributed to the worker)
create or replace function public.pen_open(p_company uuid, p_emp uuid, p_code text, p_occurred date, p_discovered date, p_desc text)
returns uuid language plpgsql security definer set search_path = public as $$
declare e public.employees; td date := (now() at time zone 'Asia/Riyadh')::date; k record; rid uuid;
begin
  perform public.require_role(p_company, array['owner','admin','hr']);
  select * into e from public.employees where id = p_emp and company_id = p_company;
  if not found then raise exception 'الموظف غير موجود في المنشأة'; end if;
  if p_occurred is null or p_discovered is null then raise exception 'حدد تاريخ المخالفة وتاريخ اكتشافها'; end if;
  if p_discovered < p_occurred then raise exception 'تاريخ الاكتشاف قبل تاريخ المخالفة'; end if;
  if p_discovered > td then raise exception 'تاريخ الاكتشاف في المستقبل'; end if;
  if td - p_discovered > 30 then raise exception 'لا يجوز اتهام العامل بمخالفة مضى على كشفها أكثر من 30 يوماً — م69'; end if;
  if e.end_date is not null and e.end_date < p_occurred then raise exception 'المخالفة بعد انتهاء خدمة الموظف'; end if;
  select * into k from public.pen_calc(p_emp, p_code, p_occurred);
  insert into public.penalties(company_id, employee_id, code, occurred_on, discovered_on, description, step, action, daily_wage, fine)
  values (p_company, p_emp, p_code, p_occurred, p_discovered, nullif(trim(p_desc), ''), k.step, k.action, k.daily_wage, k.fine) returning id into rid;
  return rid;
end $$;

-- the employee's own written reply while the case is open
create or replace function public.pen_defend(p_id uuid, p_text text) returns void
language plpgsql security definer set search_path = public as $$
declare p public.penalties;
begin
  select * into p from public.penalties where id = p_id;
  if not found or p.employee_id is distinct from public.my_employee(p.company_id) then raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p.status <> 'open' or p.inv_on is not null then raise exception 'انتهى التحقيق في هذه المخالفة'; end if;
  if length(trim(coalesce(p_text, ''))) < 3 then raise exception 'اكتب ردك'; end if;
  update public.penalties set emp_defense = trim(p_text) where id = p_id;
end $$;

-- investigation minutes (Art. 71): oral questioning only for a warning or a fine of at most one day's wage
create or replace function public.pen_investigate(p_id uuid, p_mode text, p_text text, p_on date) returns void
language plpgsql security definer set search_path = public as $$
declare p public.penalties; td date := (now() at time zone 'Asia/Riyadh')::date;
begin
  select * into p from public.penalties where id = p_id;
  if not found then raise exception 'المخالفة غير موجودة'; end if;
  perform public.require_role(p.company_id, array['owner','admin','hr']);
  if p.status <> 'open' then raise exception 'المخالفة ليست قيد التحقيق'; end if;
  if p_mode not in ('written','oral','refused') then raise exception 'حدد طريقة التحقيق'; end if;
  if p_mode = 'oral' and not (p.action = 'W' or (p.action ~ '^p[0-9]+$') or p.action = 'd1') then
    raise exception 'التحقيق الشفهي فقط للمخالفات البسيطة التي جزاؤها إنذار أو غرامة لا تزيد على أجر يوم — م71'; end if;
  if length(trim(coalesce(p_text, ''))) < 5 then raise exception 'اكتب محضر التحقيق: ما نُسب للعامل ودفاعه'; end if;
  if p_on is null or p_on > td or p_on < p.discovered_on then raise exception 'تاريخ التحقيق غير صحيح'; end if;
  update public.penalties set inv_mode = p_mode, inv_text = trim(p_text), inv_on = p_on where id = p_id;
end $$;

-- the decision: applied within 30 days of the end of the investigation (Art. 69) and notified in writing (Art. 72)
create or replace function public.pen_decide(p_id uuid, p_apply boolean, p_notified date, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare p public.penalties; td date := (now() at time zone 'Asia/Riyadh')::date; k record;
begin
  select * into p from public.penalties where id = p_id for update;
  if not found then raise exception 'المخالفة غير موجودة'; end if;
  perform public.require_role(p.company_id, array['owner','admin','hr']);
  if p.status <> 'open' then raise exception 'صدر قرار في هذه المخالفة'; end if;
  if not p_apply then
    if length(trim(coalesce(p_note, ''))) < 3 then raise exception 'اكتب سبب الحفظ'; end if;
    update public.penalties set status = 'dropped', decided_on = td, decision_note = trim(p_note) where id = p_id; return;
  end if;
  if p.inv_on is null then raise exception 'لا يجوز توقيع جزاء قبل إبلاغ العامل والتحقيق معه وسماع دفاعه — م71'; end if;
  if td - p.inv_on > 30 then raise exception 'لا يجوز توقيع الجزاء بعد مضي 30 يوماً على انتهاء التحقيق — م69'; end if;
  if p_notified is null or p_notified < p.inv_on or p_notified > td then raise exception 'تاريخ إبلاغ العامل بالقرار غير صحيح'; end if;
  select * into k from public.pen_calc(p.employee_id, p.code, p.occurred_on, p.id);
  update public.penalties set status = 'applied', step = k.step, action = k.action, daily_wage = k.daily_wage, fine = k.fine,
    decided_on = td, notified_on = p_notified, decision_note = nullif(trim(p_note), '') where id = p_id;
  perform public.payroll_line_recalc(l.run_id, l.employee_id) from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id
   where r.status = 'draft' and l.employee_id = p.employee_id;
end $$;

-- grievance: in writing within 30 days of notification, public holidays excluded; decided within 15 days (Art. 72)
create or replace function public.pen_grieve(p_id uuid, p_text text) returns void
language plpgsql security definer set search_path = public as $$
declare p public.penalties; td date := (now() at time zone 'Asia/Riyadh')::date;
begin
  select * into p from public.penalties where id = p_id;
  if not found then raise exception 'المخالفة غير موجودة'; end if;
  if p.employee_id is distinct from public.my_employee(p.company_id) and not public.has_role(p.company_id, array['owner','admin','hr']) then
    raise exception 'غير مصرح' using errcode = '42501'; end if;
  if p.status <> 'applied' then raise exception 'التظلم على جزاء صادر فقط'; end if;
  if p.griev_on is not null then raise exception 'قُدّم تظلم على هذا الجزاء'; end if;
  if td > public.pen_grievance_deadline(p.company_id, p.notified_on) then raise exception 'انتهت مهلة التظلم: 30 يوماً من الإبلاغ بالقرار عدا العطل الرسمية — م72'; end if;
  if length(trim(coalesce(p_text, ''))) < 5 then raise exception 'اكتب أسباب التظلم'; end if;
  update public.penalties set griev_on = td, griev_text = trim(p_text) where id = p_id;
end $$;
create or replace function public.pen_grievance_deadline(p_company uuid, p_from date) returns date
language plpgsql stable security definer set search_path = public as $$
declare d date := p_from; n int := 0;
begin
  while n < 30 loop d := d + 1; if not exists(select 1 from public.holidays where company_id = p_company and day = d) then n := n + 1; end if; end loop;
  return d;
end $$;
create or replace function public.pen_grievance_decide(p_id uuid, p_overturn boolean, p_note text) returns numeric
language plpgsql security definer set search_path = public as $$
declare p public.penalties; td date := (now() at time zone 'Asia/Riyadh')::date; paid numeric;
begin
  select * into p from public.penalties where id = p_id for update;
  if not found then raise exception 'المخالفة غير موجودة'; end if;
  perform public.require_role(p.company_id, array['owner','admin','hr']);
  if p.griev_on is null or p.griev_result is not null then raise exception 'لا يوجد تظلم قائم'; end if;
  if length(trim(coalesce(p_note, ''))) < 3 then raise exception 'اكتب قرار التظلم'; end if;
  update public.penalties set griev_result = case when p_overturn then 'overturned' else 'upheld' end, griev_on_decided = td, griev_note = trim(p_note),
    status = case when p_overturn then 'overturned' else status end where id = p_id;
  -- deductions not yet in an approved payroll fall away; amounts already paid are returned to the employee by HR
  delete from public.penalty_deductions d using public.payroll_runs r where p_overturn and d.penalty_id = p_id and r.id = d.run_id and r.status = 'draft';
  if p_overturn then perform public.payroll_line_recalc(l.run_id, l.employee_id) from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id
   where r.status = 'draft' and l.employee_id = p.employee_id; end if;
  select coalesce(sum(d.amount), 0) into paid from public.penalty_deductions d where d.penalty_id = p_id;
  return case when p_overturn then paid else 0 end;
end $$;

-- payroll: applied fines are deducted automatically, oldest first, within five days' wage a month together with any
-- manual fine (Art. 70); the rest carries to the next month. All deductions together stay within half the wage (Art. 93).
create or replace function public.payroll_line_recalc(p_run uuid, p_emp uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; e public.employees; ms date; me date; ab numeric; l public.payroll_lines; g numeric; sk record; adv_sched numeric; room numeric;
        am record; deduct_late boolean; cap numeric; pen record; take numeric; pen_total numeric := 0;
begin
  select * into r from public.payroll_runs where id = p_run;
  select * into e from public.employees where id = p_emp;
  select * into l from public.payroll_lines where run_id = p_run and employee_id = p_emp;
  select att_deduct_late into deduct_late from public.companies where id = r.company_id;
  ms := make_date(r.year, r.month, 1); me := (ms + interval '1 month - 1 day')::date;
  g := e.basic + e.housing + e.transport;
  select coalesce(sum(greatest(0, least(to_date, me) - greatest(from_date, ms) + 1)), 0) into ab
  from public.requests where employee_id = p_emp and kind = 'leave' and sub = 'unpaid' and status = 'approved' and from_date <= me and to_date >= ms;
  select * into sk from public.sick_deduction(p_emp, ms, me, g / 30);
  select * into am from public.att_month(p_emp, ms, me);
  update public.payroll_lines set
    basic = e.basic, housing = e.housing, transport = e.transport, gross = g,
    gosi = public.gosi_employee(e.is_saudi, e.basic, e.housing, public.gosi_is_new(e.gosi_new, e.hire_date), me),
    employer_gosi = public.gosi_employer(e.is_saudi, e.basic, e.housing, public.gosi_is_new(e.gosi_new, e.hire_date), me),
    absence_days = ab, absence = round(g / 30 * ab, 2),
    sick_days = sk.days, sick_deduction = sk.amount,
    att_absent_days = am.absent_days, att_absence = round(g / 30 * am.absent_days, 2),
    late_min = am.late_min, late_deduction = case when deduct_late then round(g / 30 / 8 / 60 * am.late_min, 2) else 0 end,
    att_ot_hours = round(am.ot_min / 60.0, 2),
    overtime = round((g / 30 / 8 + 0.5 * e.basic / 30 / 8) * (l.overtime_hours + round(am.ot_min / 60.0, 2)), 2)  -- Art. 107
  where run_id = p_run and employee_id = p_emp;
  select * into l from public.payroll_lines where run_id = p_run and employee_id = p_emp;
  -- disciplinary fines
  delete from public.penalty_deductions d using public.penalties p where d.run_id = p_run and p.id = d.penalty_id and p.employee_id = p_emp;
  cap := greatest(0, least(round(g / 30 * 5, 2) - l.deductions, round(g * 0.5, 2) - l.gosi - l.deductions - l.damages));
  for pen in select p.id, p.fine - coalesce((select sum(x.amount) from public.penalty_deductions x join public.payroll_runs rr on rr.id = x.run_id
                                                 where x.penalty_id = p.id and rr.status = 'approved'), 0) due
               from public.penalties p where p.employee_id = p_emp and p.status = 'applied' and p.fine > 0 and p.notified_on <= me
               order by p.notified_on, p.created_at loop
    exit when cap <= 0;
    take := least(pen.due, cap);
    if take > 0 then insert into public.penalty_deductions(run_id, penalty_id, amount) values (p_run, pen.id, take); cap := cap - take; pen_total := pen_total + take; end if;
  end loop;
  update public.payroll_lines set penalty_fine = pen_total where run_id = p_run and employee_id = p_emp;
  select coalesce(sum(d.amount),0) into adv_sched from public.advance_deductions d join public.requests q on q.id = d.request_id
   where d.run_id = p_run and q.employee_id = p_emp;
  room := greatest(0, round(g * 0.5, 2) - l.gosi - l.deductions - l.damages - pen_total);
  update public.payroll_lines set advance = least(adv_sched, round(g * 0.10, 2), room) where run_id = p_run and employee_id = p_emp;
  if adv_sched > least(adv_sched, round(g * 0.10, 2), room) then
    with x as (select d.request_id, d.amount, sum(d.amount) over (order by d.request_id) running from public.advance_deductions d
               join public.requests q on q.id = d.request_id where d.run_id = p_run and q.employee_id = p_emp)
    update public.advance_deductions ad set amount = greatest(0, least(x.amount, least(adv_sched, round(g * 0.10, 2), room) - (x.running - x.amount)))
      from x where ad.run_id = p_run and ad.request_id = x.request_id;
    delete from public.advance_deductions where run_id = p_run and amount <= 0;
  end if;
  update public.payroll_lines set net = gross + overtime + bonus - gosi - absence - att_absence - late_deduction - sick_deduction - deductions - penalty_fine - damages - advance
   where run_id = p_run and employee_id = p_emp;
end $$;

-- Art. 73: fines are not the employer's income — they go to a liability account kept for the workers' benefit
create or replace function public.payroll_approve(p_run uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; t record; me date; je uuid;
begin
  select * into r from public.payroll_runs where id = p_run for update;
  perform public.require_role(r.company_id, array['owner','finance']);
  if r.status <> 'draft' then raise exception 'المسير معتمد مسبقاً'; end if;
  select coalesce(sum(gross + overtime + bonus - absence - att_absence - late_deduction - sick_deduction - damages),0) ex, coalesce(sum(gosi),0) g, coalesce(sum(employer_gosi),0) eg,
         coalesce(sum(advance),0) adv, coalesce(sum(net),0) n, coalesce(sum(deductions + penalty_fine),0) fines, count(*) c
    into t from public.payroll_lines where run_id = p_run;
  if t.c = 0 then raise exception 'المسير فارغ'; end if;
  insert into public.accounts(company_id, code, name, type, parent_code, is_header)
  values (r.company_id, '2450', 'غرامات العاملين — لصالح العمال (م73)', 'liab', '2000', false) on conflict do nothing;
  me := (make_date(r.year, r.month, 1) + interval '1 month - 1 day')::date;
  je := public.post_journal(r.company_id, me, 'استحقاق رواتب ' || lpad(r.month::text,2,'0') || '/' || r.year, 'payroll', r.id,
    jsonb_build_array(jsonb_build_object('a','5200','d',t.ex), jsonb_build_object('a','5210','d',t.eg),
                      jsonb_build_object('a','2400','c',t.g + t.eg), jsonb_build_object('a','1500','c',t.adv),
                      jsonb_build_object('a','2450','c',t.fines), jsonb_build_object('a','2300','c',t.n)));
  update public.payroll_runs set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = p_run;
  return je;
end $$;

create trigger audit_penalties after insert or update or delete on public.penalties for each row execute function public.audit_trigger();
alter table public.violation_types enable row level security;
alter table public.penalties enable row level security;
alter table public.penalty_deductions enable row level security;
create policy vt_read on public.violation_types for select using (auth.uid() is not null);
create policy pen_read on public.penalties for select using (public.has_role(company_id, array['owner','admin','hr','finance']) or employee_id = public.my_employee(company_id));
create policy pd_read on public.penalty_deductions for select using (exists(select 1 from public.penalties p where p.id = penalty_id));
revoke all on public.violation_types, public.penalties, public.penalty_deductions from anon;
grant select on public.violation_types, public.penalties, public.penalty_deductions to authenticated;
revoke insert, update, delete on public.violation_types, public.penalties, public.penalty_deductions from authenticated;
revoke all on function public.pen_step(uuid, text, date, uuid), public.pen_calc(uuid, text, date, uuid), public.pen_preview(uuid, text, date),
  public.pen_open(uuid, uuid, text, date, date, text), public.pen_defend(uuid, text), public.pen_investigate(uuid, text, text, date),
  public.pen_decide(uuid, boolean, date, text), public.pen_grieve(uuid, text), public.pen_grievance_deadline(uuid, date),
  public.pen_grievance_decide(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.pen_preview(uuid, text, date), public.pen_open(uuid, uuid, text, date, date, text), public.pen_defend(uuid, text),
  public.pen_investigate(uuid, text, text, date), public.pen_decide(uuid, boolean, date, text), public.pen_grieve(uuid, text),
  public.pen_grievance_deadline(uuid, date), public.pen_grievance_decide(uuid, boolean, text) to authenticated;
notify pgrst, 'reload schema';
