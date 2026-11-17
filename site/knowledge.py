"""«المعرفة» — the website's knowledge section: articles, policy templates, job descriptions and an HR glossary.
Edit the content here; site/build.py turns it into pages (knowledge.html, blog-*.html, policies.html, jobs.html, glossary.html).
Every legal figure below is one Waad itself applies (migrations 0002/0008, hr.js) with its article number; anything else
is general guidance. Content is for guidance only — the reference is the Labor Law and the official platforms."""
from html import escape as e

# ---------------------------------------------------------------- articles
ARTICLES = [
  {'slug': 'eos', 'ar': 'كيف تحسب مكافأة نهاية الخدمة في السعودية؟', 'en': 'How is the end-of-service award calculated in Saudi Arabia?',
   'dar': 'طريقة الحساب حسب مدة الخدمة وسبب انتهاء العلاقة، مع أمثلة.', 'den': 'The method by length of service and reason for leaving, with examples.',
   'body': [
     ('الأساس: نصف شهر ثم شهر', 'The basis: half a month, then a month',
      'تستحق المكافأة عن مدة الخدمة كلها على أساس آخر أجر: أجر نصف شهر عن كل سنة من السنوات الخمس الأولى، وأجر شهر كامل عن كل سنة بعدها، وتُحسب كسور السنة بنسبتها (المادة 84).',
      'The award covers the whole service on the last wage: half a month\'s wage for each of the first five years and a full month for each year after, with part-years in proportion (Article 84).'),
     ('عند الاستقالة', 'On resignation',
      'إذا استقال الموظف: لا يستحق شيئا إذا كانت خدمته أقل من سنتين، ويستحق ثلث المكافأة من سنتين إلى أقل من خمس، وثلثيها من خمس إلى أقل من عشر، والمكافأة كاملة بعد عشر سنوات (المادة 85).',
      'If the employee resigns: nothing under two years, one third from two to under five years, two thirds from five to under ten, and the full award after ten years (Article 85).'),
     ('حالات المكافأة الكاملة', 'When the full award is due',
      'تُستحق المكافأة كاملة عند إنهاء صاحب العمل للعقد أو انتهاء مدته أو الاتفاق على إنهائه، وكذلك في حالات القوة القاهرة، واستقالة العاملة خلال ستة أشهر من زواجها أو ثلاثة أشهر من وضعها (المادة 87).',
      'The full award is due when the employer ends the contract, it expires or both agree to end it, in force majeure, and when a female employee resigns within six months of marriage or three months of giving birth (Article 87).'),
     ('حالة لا تُستحق فيها', 'When it is not due',
      'لا يستحق الموظف المكافأة إذا فُصل لأحد الأسباب الواردة في المادة 80 من نظام العمل.',
      'No award is due if the employee is dismissed for one of the reasons in Article 80 of the Labor Law.'),
     ('مثال', 'Example',
      'موظف أجره 10,000 ريال وخدم 7 سنوات وأنهى صاحب العمل عقده: 5 سنوات × 5,000 = 25,000، وسنتان × 10,000 = 20,000، فالمجموع 45,000 ريال. ولو استقال بعد المدة نفسها لاستحق ثلثيها: 30,000 ريال.',
      'An employee paid SAR 10,000 with 7 years, ended by the employer: 5 years × 5,000 = 25,000 plus 2 years × 10,000 = 20,000, total SAR 45,000. Resigning after the same period gives two thirds: SAR 30,000.')]},
  {'slug': 'annual-leave', 'ar': 'الإجازة السنوية في نظام العمل: 21 يوما أو 30', 'en': 'Annual leave under the Labor Law: 21 or 30 days',
   'dar': 'متى تصبح 30 يوما، وكيف يتراكم الرصيد، وما يحدث للأيام غير المستخدمة.', 'den': 'When it becomes 30 days, how the balance builds up, and what happens to unused days.',
   'body': [
     ('المدة', 'Length',
      'للعامل إجازة سنوية بأجر لا تقل عن 21 يوما، وتصبح 30 يوما إذا أمضى في خدمة صاحب العمل خمس سنوات متصلة (المادة 109).',
      'An employee is entitled to paid annual leave of at least 21 days, rising to 30 days after five continuous years with the employer (Article 109).'),
     ('كيف يتراكم الرصيد', 'How the balance builds up',
      'يتراكم الرصيد يوما بيوم على مدار السنة، فمن أمضى نصف سنة استحق نصف إجازته تقريبا. ويحسب وعد الرصيد تلقائيا لكل موظف من تاريخ مباشرته.',
      'The balance builds up day by day through the year, so half a year earns about half the leave. Waad calculates it automatically for each employee from the start date.'),
     ('الأيام غير المستخدمة عند انتهاء الخدمة', 'Unused days when service ends',
      'يستحق الموظف عند انتهاء خدمته أجر أيام الإجازة التي لم يستخدمها، ويُصرف مع مستحقاته النهائية.',
      'When service ends, the employee is paid for the leave days not used, with the final settlement.'),
     ('نصيحة عملية', 'Practical tip',
      'سجّل الإجازات في النظام بدل الجداول، فيبقى رصيد كل موظف واضحا له ولمديره، ويُحسب تلقائيا في المخالصة.',
      'Record leave in the system instead of spreadsheets, so every balance is clear to the employee and the manager and flows into the final settlement.')]},
  {'slug': 'gosi', 'ar': 'اشتراكات التأمينات الاجتماعية: من يدفع كم؟', 'en': 'GOSI contributions: who pays what?',
   'dar': 'الأجر الخاضع للاشتراك، ونسب السعودي وغير السعودي، والنظام الجديد للمسجلين بعد يوليو 2024.', 'den': 'The contribution wage, the rates for Saudis and non-Saudis, and the new rules for those registered after July 2024.',
   'body': [
     ('الأجر الخاضع للاشتراك', 'The contribution wage',
      'يُحسب الاشتراك على الأجر الأساسي مضافا إليه بدل السكن، بحد أدنى 1,500 ريال وحد أعلى 45,000 ريال شهريا.',
      'Contributions are calculated on basic salary plus housing allowance, with a minimum of SAR 1,500 and a maximum of SAR 45,000 a month.'),
     ('الموظف السعودي', 'Saudi employees',
      'للمسجلين قبل 3 يوليو 2024: يدفع الموظف 9.75% (المعاشات 9% وساند 0.75%)، ويدفع صاحب العمل 11.75% (المعاشات 9% وساند 0.75% والأخطار المهنية 2%).',
      'For those registered before 3 July 2024: the employee pays 9.75% (pension 9% and SANED 0.75%) and the employer 11.75% (pension 9%, SANED 0.75% and occupational hazards 2%).'),
     ('المسجلون لأول مرة من 3 يوليو 2024', 'First registered from 3 July 2024',
      'ترتفع نسبة المعاشات تدريجيا بنصف نقطة مئوية كل يوليو من 2025 حتى 2028 على كل من الموظف وصاحب العمل.',
      'The pension rate rises by half a percentage point every July from 2025 to 2028, for both the employee and the employer.'),
     ('الموظف غير السعودي', 'Non-Saudi employees',
      'لا يُقتطع من راتبه شيء، ويدفع صاحب العمل 2% للأخطار المهنية.',
      'Nothing is deducted from the salary; the employer pays 2% for occupational hazards.'),
     ('تحديث التأمينات', 'Keeping GOSI up to date',
      'عند تعيين موظف أو انتهاء خدمته أو تغير أجره الخاضع للاشتراك يلزم تحديث بياناته في التأمينات. يعرض وعد بعد كل مسير قائمة بمن يحتاج تحديثا.',
      'When an employee joins, leaves or their contribution wage changes, GOSI must be updated. After each payroll Waad lists who needs updating.')]},
  {'slug': 'nitaqat', 'ar': 'نطاقات: كيف تُحسب نسبة التوطين في منشأتك؟', 'en': 'Nitaqat: how is your Saudization ratio counted?',
   'dar': 'من يُحتسب كاملا ومن يُحتسب نصفا، وكيف تعرف المطلوب لبلوغ النطاق التالي.', 'den': 'Who counts in full or as half, and how to know what it takes to reach the next band.',
   'body': [
     ('الفكرة', 'The idea',
      'يصنّف برنامج نطاقات المنشآت حسب نسبة السعوديين فيها مقارنة بنشاطها وحجمها، والنسب المطلوبة لكل نطاق تظهر لمنشأتك في منصة قوى.',
      'Nitaqat classifies companies by their share of Saudi employees for their activity and size; the ratios required for each band are shown for your company on Qiwa.'),
     ('من يُحتسب', 'Who counts',
      'في الحساب الذي يطبقه وعد: السعودي الذي أجره (الأساسي والسكن) 4,000 ريال فأكثر يُحتسب موظفا كاملا، ومن 3,000 إلى أقل من 4,000 يُحتسب نصف موظف. والمرجع الرسمي في احتساب منشأتك هو منصة قوى.',
      'In the count Waad applies: a Saudi whose wage (basic and housing) is SAR 4,000 or more counts as one, and from 3,000 to under 4,000 as half. The official count for your company is on Qiwa.'),
     ('مثال', 'Example',
      'منشأة فيها 20 موظفا، منهم 4 سعوديين بأجر 4,000 فأكثر و2 بأجر 3,500: النسبة (4 + 1) ÷ 20 = 25%. فإذا كان المطلوب 30% فهي تحتاج سعوديين إضافيين اثنين بأجر 4,000 فأكثر.',
      'A company with 20 employees, 4 Saudis paid 4,000+ and 2 paid 3,500: (4 + 1) ÷ 20 = 25%. If 30% is required, it needs two more Saudis paid 4,000+.'),
     ('جرّبها', 'Try it', 'استخدم حاسبة النطاقات المجانية في صفحة الأدوات.', 'Use the free Nitaqat calculator on the tools page.')]},
  {'slug': 'wps', 'ar': 'نظام حماية الأجور: ما المطلوب من المنشأة شهريا؟', 'en': 'The Wage Protection System: what is required each month?',
   'dar': 'ما هو نظام حماية الأجور، وما البيانات التي يحتاجها ملف الرواتب، وأخطاء شائعة.', 'den': 'What wage protection is, the data the salary file needs, and common mistakes.',
   'body': [
     ('ما هو؟', 'What is it?',
      'نظام لمتابعة صرف الأجور في مواعيدها وبمقاديرها المتفق عليها، ترفع فيه المنشأة ملف رواتبها الشهري عبر منصة مدد ليُطابق مع المصروف فعلا.',
      'A system that checks wages are paid on time and in the agreed amounts; the company uploads its monthly salary file through Mudad to be matched with what was actually paid.'),
     ('ما يحتاجه الملف', 'What the file needs',
      'لكل موظف: رقم الهوية أو الإقامة، والآيبان، والأجر الأساسي والسكن والبدلات الأخرى والاستقطاعات وصافي الراتب.',
      'For each employee: ID or iqama number, IBAN, basic salary, housing, other allowances, deductions and net pay.'),
     ('أخطاء شائعة', 'Common mistakes',
      'آيبان ناقص أو خاطئ، أو موظف بلا رقم هوية، أو اختلاف الأجر في الملف عن الأجر في العقد، أو التأخر في الرفع.',
      'A missing or wrong IBAN, an employee without an ID number, a wage in the file that differs from the contract, or uploading late.'),
     ('كيف يساعد وعد', 'How Waad helps',
      'بعد اعتماد المسير يجهّز وعد ملف حماية الأجور للتنزيل، وتنبهك صفحة الامتثال إلى من ينقصه آيبان أو رقم هوية قبل الرفع.',
      'After the payroll is approved Waad prepares the wage protection file, and the compliance page flags anyone missing an IBAN or ID before you upload.')]},
]

# ---------------------------------------------------------------- policy templates
POLICIES = [
  ('سياسة الحضور والانصراف', 'Attendance policy', [
    ('أوقات العمل وفق جدول الدوام المعتمد في المنشأة، ويُسجَّل الحضور والانصراف عبر النظام المعتمد.', 'Working hours follow the approved schedule; attendance is recorded through the approved system.'),
    ('يُبلّغ الموظف مديره المباشر مسبقا عند التأخر أو الغياب، ويقدّم طلب استئذان أو إجازة عبر النظام.', 'Employees inform their direct manager in advance of lateness or absence and submit a permission or leave request through the system.'),
    ('يُعالج التأخر والغياب دون عذر وفق جدول المخالفات والجزاءات في لائحة تنظيم العمل المعتمدة.', 'Unexcused lateness and absence are handled under the violations and penalties schedule of the approved work regulations.'),
    ('يُعتمد العمل الإضافي مسبقا من المدير المباشر، ويُعوَّض وفق نظام العمل.', 'Overtime is approved in advance by the direct manager and compensated under the Labor Law.')]),
  ('سياسة الإجازات', 'Leave policy', [
    ('تُطلب الإجازة السنوية عبر النظام قبل موعدها بمدة كافية، وتُعتمد حسب حاجة العمل.', 'Annual leave is requested through the system well in advance and approved according to business needs.'),
    ('تُرفق المستندات المؤيدة للإجازات المرضية والإجازات الخاصة عند طلبها.', 'Supporting documents are attached to sick and special leave requests.'),
    ('يُسلّم الموظف أعماله لزميل يحدده مديره قبل بدء إجازته.', 'Before leave starts, the employee hands over work to a colleague named by the manager.'),
    ('مدد الإجازات وأجرها وفق نظام العمل ولائحة تنظيم العمل المعتمدة.', 'Leave lengths and pay follow the Labor Law and the approved work regulations.')]),
  ('سياسة العمل عن بعد', 'Remote work policy', [
    ('يُسمح بالعمل عن بعد للوظائف التي تقبله وبموافقة المدير المباشر.', 'Remote work is allowed for suitable roles with the direct manager\'s approval.'),
    ('يلتزم الموظف بساعات العمل المعتادة ويبقى متاحا عبر وسائل التواصل المعتمدة.', 'Employees keep normal working hours and stay reachable through the approved channels.'),
    ('تُحمى بيانات المنشأة ولا تُستخدم أجهزة أو شبكات غير آمنة.', 'Company data is protected and insecure devices or networks are not used.'),
    ('يحق للمنشأة إنهاء ترتيب العمل عن بعد عند تأثر الأداء.', 'The company may end remote work if performance is affected.')]),
  ('سياسة استخدام الأجهزة والعهد', 'Devices and custody policy', [
    ('تُسلَّم العهد بمحضر استلام موقّع، وتبقى ملكا للمنشأة.', 'Custody items are handed over with a signed receipt and remain company property.'),
    ('يحافظ الموظف على العهدة ويستخدمها لأغراض العمل فقط، ويُبلّغ فورا عن أي تلف أو فقد.', 'Employees look after custody items, use them for work only and report damage or loss at once.'),
    ('تُعاد العهد عند انتهاء الخدمة أو عند الطلب ضمن إجراءات إخلاء الطرف.', 'Items are returned when service ends or on request, as part of clearance.'),
    ('الاقتطاع مقابل الفقد أو التلف يكون وفق نظام العمل وبعد التحقق.', 'Any deduction for loss or damage follows the Labor Law and an investigation.')]),
  ('سياسة السلوك المهني وتعارض المصالح', 'Code of conduct and conflict of interest', [
    ('يلتزم الموظف بالأمانة والاحترام في التعامل مع الزملاء والعملاء.', 'Employees act with integrity and respect towards colleagues and customers.'),
    ('يُفصح الموظف عن أي مصلحة شخصية قد تتعارض مع مصلحة المنشأة.', 'Employees disclose any personal interest that may conflict with the company\'s.'),
    ('لا يُقبل أي هدية أو منفعة قد تؤثر على قرارات العمل.', 'No gift or benefit that may influence business decisions is accepted.'),
    ('تُحفظ سرية معلومات المنشأة وعملائها أثناء الخدمة وبعدها.', 'Company and customer information stays confidential during and after employment.')]),
  ('سياسة المصروفات ورحلات العمل', 'Expenses and business travel policy', [
    ('تُقدّم المطالبة عبر النظام خلال الشهر نفسه، مع الإيصال الأصلي وفئة المصروف.', 'Claims are submitted through the system within the same month, with the original receipt and the expense category.'),
    ('تُلتزم حدود كل فئة المعتمدة في سياسات المصروفات، وما تجاوزها يحتاج موافقة مسبقة.', 'Each category\'s approved limits apply; anything above needs prior approval.'),
    ('يُعتمد السفر للعمل مسبقا، ويُحجز وفق درجة السفر المعتمدة للمستوى الوظيفي.', 'Business travel is approved in advance and booked in the class approved for the job level.'),
    ('لا يُقبل الإيصال نفسه في أكثر من مطالبة.', 'The same receipt is never accepted in more than one claim.')]),
]

# ---------------------------------------------------------------- job descriptions
JOBS = [
  ('أخصائي موارد بشرية', 'HR specialist', 'إدارة شؤون الموظفين من التعيين حتى نهاية الخدمة وفق نظام العمل.', 'Manage employee affairs from hiring to end of service under the Labor Law.',
   [('متابعة ملفات الموظفين وعقودهم ووثائقهم', 'Maintain employee files, contracts and documents'), ('إعداد مسير الرواتب ومتابعة حماية الأجور والتأمينات', 'Prepare payroll and follow wage protection and GOSI'),
    ('إدارة الإجازات والحضور والانصراف', 'Manage leave and attendance'), ('تنفيذ التوظيف والتهيئة للموظفين الجدد', 'Run hiring and onboarding'), ('متابعة نطاقات والامتثال لنظام العمل', 'Follow Nitaqat and Labor Law compliance')],
   [('بكالوريوس في الموارد البشرية أو إدارة الأعمال', 'Bachelor\'s in HR or business'), ('معرفة بنظام العمل السعودي', 'Knowledge of the Saudi Labor Law'), ('مهارات تواصل وتنظيم', 'Communication and organisation skills')]),
  ('محاسب', 'Accountant', 'تسجيل العمليات المالية وإعداد التقارير بدقة وفي موعدها.', 'Record financial transactions and prepare accurate, timely reports.',
   [('تسجيل القيود اليومية ومطابقة الحسابات البنكية', 'Post journal entries and reconcile bank accounts'), ('متابعة الذمم المدينة والدائنة', 'Follow receivables and payables'), ('إعداد إقرارات ضريبة القيمة المضافة', 'Prepare VAT returns'),
    ('إعداد القوائم المالية الشهرية', 'Prepare monthly financial statements'), ('متابعة الفوترة الإلكترونية', 'Follow e-invoicing')],
   [('بكالوريوس محاسبة', 'Bachelor\'s in accounting'), ('معرفة بالمعايير المحاسبية وأنظمة الضريبة', 'Knowledge of accounting standards and tax rules'), ('إتقان الأنظمة المحاسبية وExcel', 'Proficiency in accounting systems and Excel')]),
  ('مندوب مبيعات', 'Sales representative', 'تحقيق أهداف المبيعات وبناء علاقات طويلة مع العملاء.', 'Achieve sales targets and build long-term customer relationships.',
   [('البحث عن عملاء جدد ومتابعة العملاء الحاليين', 'Find new customers and follow existing ones'), ('إعداد عروض الأسعار ومتابعتها حتى البيع', 'Prepare quotes and follow them to sale'), ('تسجيل الفرص والزيارات في النظام', 'Record opportunities and visits in the system'),
    ('متابعة تحصيل المستحقات', 'Follow collections')],
   [('خبرة في المبيعات', 'Sales experience'), ('مهارات تفاوض وإقناع', 'Negotiation and persuasion skills'), ('رخصة قيادة سارية عند الحاجة', 'Valid driving licence when needed')]),
  ('كاشير', 'Cashier', 'إتمام عمليات البيع بدقة وتقديم خدمة سريعة للعملاء.', 'Complete sales accurately and serve customers quickly.',
   [('تسجيل المبيعات عبر نقطة البيع', 'Record sales at the point of sale'), ('استلام المبالغ وإصدار الفواتير', 'Take payments and issue invoices'), ('إقفال الصندوق ومطابقته نهاية الوردية', 'Close and reconcile the till at the end of the shift')],
   [('دقة في التعامل مع النقد', 'Accuracy with cash'), ('مهارات خدمة العملاء', 'Customer service skills')]),
  ('أمين مستودع', 'Storekeeper', 'استلام البضائع وصرفها وضبط المخزون.', 'Receive and issue goods and keep inventory accurate.',
   [('استلام البضائع ومطابقتها مع أوامر الشراء', 'Receive goods and match them with purchase orders'), ('صرف المواد وتسجيل الحركات في النظام', 'Issue materials and record movements in the system'), ('إجراء الجرد الدوري', 'Carry out periodic stock counts'),
    ('متابعة حد إعادة الطلب وتواريخ الانتهاء', 'Watch reorder levels and expiry dates')],
   [('خبرة في المستودعات', 'Warehouse experience'), ('دقة وتنظيم', 'Accuracy and organisation')]),
  ('مساعد إداري', 'Administrative assistant', 'دعم الإدارة في الأعمال المكتبية والتنظيمية.', 'Support management with office and organisational work.',
   [('تنظيم المواعيد والاجتماعات', 'Organise appointments and meetings'), ('إعداد المراسلات والخطابات', 'Prepare correspondence and letters'), ('حفظ المستندات وأرشفتها', 'File and archive documents'), ('متابعة طلبات المكتب', 'Follow office requests')],
   [('مهارات حاسب آلي', 'Computer skills'), ('تنظيم وإدارة وقت', 'Organisation and time management')]),
  ('موظف خدمة عملاء', 'Customer service officer', 'الرد على استفسارات العملاء وحل مشكلاتهم بسرعة.', 'Answer customer enquiries and resolve issues quickly.',
   [('الرد على الاتصالات والرسائل', 'Answer calls and messages'), ('تسجيل الشكاوى ومتابعتها حتى الحل', 'Log complaints and follow them to resolution'), ('رفع مقترحات تحسين الخدمة', 'Suggest service improvements')],
   [('مهارات تواصل', 'Communication skills'), ('صبر وحسن تعامل', 'Patience and courtesy')]),
  ('أخصائي تسويق', 'Marketing specialist', 'تخطيط الحملات التسويقية وقياس نتائجها.', 'Plan marketing campaigns and measure their results.',
   [('إعداد خطة التسويق والمحتوى', 'Prepare the marketing and content plan'), ('إدارة حسابات التواصل الاجتماعي', 'Manage social media accounts'), ('متابعة العملاء المحتملين وتحويلهم للمبيعات', 'Follow leads and pass them to sales'), ('قياس نتائج الحملات', 'Measure campaign results')],
   [('خبرة في التسويق الرقمي', 'Digital marketing experience'), ('مهارات كتابة وتحليل', 'Writing and analysis skills')]),
  ('مسؤول مشتريات', 'Purchasing officer', 'توفير احتياجات المنشأة بأفضل جودة وسعر وفي الوقت المناسب.', 'Supply the company\'s needs at the best quality and price, on time.',
   [('طلب عروض الأسعار ومقارنتها', 'Request and compare quotes'), ('إصدار أوامر الشراء ومتابعتها', 'Issue and follow purchase orders'), ('تقييم الموردين', 'Evaluate suppliers'), ('التنسيق مع المستودع والمالية', 'Coordinate with the warehouse and finance')],
   [('خبرة في المشتريات', 'Purchasing experience'), ('مهارات تفاوض', 'Negotiation skills')]),
  ('أخصائي دعم تقني', 'IT support specialist', 'تشغيل الأجهزة والأنظمة ودعم الموظفين تقنيا.', 'Keep devices and systems running and support staff technically.',
   [('تجهيز أجهزة الموظفين وصلاحياتهم', 'Set up staff devices and access'), ('حل المشكلات التقنية', 'Solve technical problems'), ('متابعة النسخ الاحتياطي وأمن المعلومات', 'Follow backups and information security'), ('إدارة الأجهزة كعهد', 'Manage devices as custody')],
   [('دبلوم أو بكالوريوس في تقنية المعلومات', 'Diploma or degree in IT'), ('خبرة في الدعم الفني', 'Help-desk experience')]),
]

# ---------------------------------------------------------------- glossary
GLOSSARY = [
  ('نظام حماية الأجور', 'Wage Protection System (WPS)', 'نظام لمتابعة صرف أجور العاملين في القطاع الخاص في مواعيدها وبمقاديرها المتفق عليها، يُرفع ملفه الشهري عبر منصة مدد.', 'A system that checks private-sector wages are paid on time and in the agreed amounts; the monthly file is uploaded through Mudad.'),
  ('مدد', 'Mudad', 'منصة رفع ملفات الرواتب لنظام حماية الأجور.', 'The platform for uploading salary files for wage protection.'),
  ('قوى', 'Qiwa', 'منصة وزارة الموارد البشرية لخدمات المنشآت والعاملين، ومنها توثيق العقود ونطاقات.', 'The Ministry of Human Resources platform for company and worker services, including contract documentation and Nitaqat.'),
  ('مقيم', 'Muqeem', 'منصة خدمات الإقامات والتأشيرات للعاملين غير السعوديين.', 'The platform for iqama and visa services for non-Saudi workers.'),
  ('التأمينات الاجتماعية', 'GOSI', 'المؤسسة العامة للتأمينات الاجتماعية: تُسجَّل فيها اشتراكات المعاشات والأخطار المهنية وساند.', 'The General Organization for Social Insurance: registers pension, occupational hazard and SANED contributions.'),
  ('ساند', 'SANED', 'نظام التأمين ضد التعطل عن العمل، يُدفع اشتراكه للسعوديين بنسبة 0.75% من الموظف و0.75% من صاحب العمل.', 'Unemployment insurance; for Saudis it costs 0.75% from the employee and 0.75% from the employer.'),
  ('الأجر الخاضع للاشتراك', 'Contribution wage', 'الأجر الأساسي مع بدل السكن، بحد أدنى 1,500 وأعلى 45,000 ريال، وعليه تُحسب اشتراكات التأمينات.', 'Basic salary plus housing, between SAR 1,500 and 45,000; GOSI contributions are calculated on it.'),
  ('نطاقات', 'Nitaqat', 'برنامج يصنّف المنشآت حسب نسبة التوطين فيها، وتختلف النسب المطلوبة حسب النشاط والحجم.', 'A programme classifying companies by their Saudization ratio; required ratios vary by activity and size.'),
  ('التوطين', 'Saudization', 'نسبة الموظفين السعوديين في المنشأة.', 'The share of Saudi employees in the company.'),
  ('مكافأة نهاية الخدمة', 'End-of-service award', 'مبلغ يستحقه الموظف عند انتهاء خدمته، يُحسب حسب مدة الخدمة وآخر أجر وسبب الانتهاء (المواد 84 و85 و87).', 'An amount due when service ends, based on length of service, last wage and the reason for leaving (Articles 84, 85 and 87).'),
  ('فترة التجربة', 'Probation period', 'مدة في بداية العقد يُقيَّم فيها الموظف، ويقرر صاحب العمل قبل نهايتها التثبيت أو الإنهاء (المادة 53).', 'A period at the start of the contract to assess the employee; before it ends the employer decides to confirm or end (Article 53).'),
  ('الإجازة السنوية', 'Annual leave', '21 يوما بأجر، و30 يوما بعد خمس سنوات متصلة (المادة 109).', '21 paid days, 30 after five continuous years (Article 109).'),
  ('العمل الإضافي', 'Overtime', 'ساعات العمل الزائدة على الساعات المعتادة، ويُدفع عنها أجر الساعة مضافا إليه 50% من الأجر الأساسي (المادة 107).', 'Hours beyond the normal hours, paid at the hourly wage plus 50% of the basic wage (Article 107).'),
  ('لائحة تنظيم العمل', 'Work regulations', 'لائحة داخلية للمنشأة تنظم العمل والجزاءات، وتُعتمد وفق نظام العمل.', 'The company\'s internal regulations on work and penalties, approved under the Labor Law.'),
  ('عقد محدد المدة', 'Fixed-term contract', 'عقد له تاريخ انتهاء محدد.', 'A contract with a set end date.'),
  ('عقد غير محدد المدة', 'Open-ended contract', 'عقد بلا تاريخ انتهاء، ويستمر حتى ينهيه أحد الطرفين وفق النظام.', 'A contract with no end date that runs until either party ends it under the law.'),
  ('الإقامة', 'Iqama', 'وثيقة إقامة العامل غير السعودي في المملكة.', 'The residence permit of a non-Saudi worker in the Kingdom.'),
  ('رخصة العمل', 'Work permit', 'ترخيص يسمح لغير السعودي بالعمل لدى صاحب العمل.', 'A permit allowing a non-Saudi to work for the employer.'),
  ('تأشيرة خروج وعودة', 'Exit and re-entry visa', 'تأشيرة تسمح للعامل غير السعودي بالسفر والعودة خلال مدة محددة.', 'A visa letting a non-Saudi worker travel and return within a set period.'),
  ('مسير الرواتب', 'Payroll', 'كشف شهري برواتب الموظفين واستحقاقاتهم واستقطاعاتهم وصافي ما يُصرف لكل منهم.', 'A monthly sheet of salaries, entitlements, deductions and net pay for each employee.'),
  ('المخالصة', 'Final settlement', 'تسوية نهائية لمستحقات الموظف عند انتهاء خدمته: المكافأة وأجر الإجازات والمستحقات الأخرى.', 'The final settlement when service ends: the award, leave pay and other dues.'),
  ('إخلاء الطرف', 'Clearance', 'إجراء يتأكد فيه كل قسم أن الموظف المغادر سلّم ما عليه من عهد والتزامات.', 'A process where each department confirms the leaving employee returned custody and settled obligations.'),
  ('ضريبة القيمة المضافة', 'VAT', 'ضريبة على السلع والخدمات بنسبة 15% في المملكة.', 'A tax on goods and services at 15% in the Kingdom.'),
  ('الفوترة الإلكترونية', 'E-invoicing (Fatoora)', 'إصدار الفواتير الضريبية إلكترونيا وربطها بمنصة «فاتورة» لدى هيئة الزكاة والضريبة والجمارك.', 'Issuing tax invoices electronically and linking them to ZATCA\'s Fatoora platform.'),
  ('مؤشر رضا الموظفين', 'eNPS', 'مقياس من -100 إلى 100 من سؤال: ما مدى احتمال أن توصي بالمنشأة كمكان عمل؟ (نسبة من أجاب 9–10 ناقص نسبة من أجاب 0–6).', 'A score from -100 to 100 from: how likely are you to recommend the company as a workplace? (share answering 9–10 minus share answering 0–6).'),
  ('تقييم 360 درجة', '360 feedback', 'تقييم الموظف من عدة جهات: نفسه وزملاؤه ومن يرفعون له، بجانب مديره.', 'Feedback on an employee from several sides: self, peers and direct reports, beside the manager.'),
  ('الهيكل التنظيمي', 'Organisation chart', 'رسم يوضح الأقسام والوظائف وتبعية كل موظف لمديره.', 'A chart of departments, jobs and who reports to whom.'),
]

# ---------------------------------------------------------------- pages
def bi(ar, en, tag='span'):
    return '<%s class="ar">%s</%s><%s class="en">%s</%s>' % (tag, e(ar), tag, tag, e(en), tag)

def hero(ar, en, sar, sen):
    return '<div class="phero"><div class="wrap"><h1>%s</h1><p>%s</p></div></div>\n' % (bi(ar, en), bi(sar, sen))

NOTE = ('<p class="small kn-note">%s</p>' % bi('محتوى إرشادي عام، والمرجع نظام العمل ولوائحه والمنصات الرسمية. راجع المختص قبل أي قرار.',
                                                  'General guidance; the reference is the Labor Law, its regulations and the official platforms. Consult a specialist before any decision.'))
CTA = '<p style="text-align:center;margin-top:24px"><a class="btn gold" href="app/?start=signup">%s</a></p>' % bi('جرّب وعد مجانا 14 يوما', 'Try Waad free for 14 days')

def hub():
    tiles = [('blog.html', 'المدونة', 'Blog', 'مقالات في نظام العمل والرواتب والتأمينات', 'Articles on the Labor Law, payroll and GOSI'),
             ('policies.html', 'نماذج السياسات', 'Policy templates', 'سياسات جاهزة تعدّلها لمنشأتك', 'Ready policies to adapt for your company'),
             ('jobs.html', 'الأوصاف الوظيفية', 'Job descriptions', 'مهام ومتطلبات أشهر الوظائف', 'Tasks and requirements of common jobs'),
             ('glossary.html', 'مصطلحات الموارد البشرية', 'HR glossary', 'معاني أهم المصطلحات بالعربي والإنجليزي', 'Key terms in Arabic and English'),
             ('tools.html', 'الأدوات المجانية', 'Free tools', 'حاسبات نهاية الخدمة والرواتب والتأمينات ونطاقات', 'End-of-service, salary, GOSI and Nitaqat calculators'),
             ('updates.html', 'ما الجديد في وعد', 'What\'s new', 'آخر تحديثات النظام', 'The latest updates')]
    cards = ''.join('<a class="card kn-tile" href="%s"><h3>%s</h3><p>%s</p></a>' % (h, bi(a, b), bi(c, d)) for h, a, b, c, d in tiles)
    return hero('المعرفة', 'Knowledge', 'مرجع مجاني لأصحاب المنشآت وفرق الموارد البشرية', 'A free reference for business owners and HR teams') + '<section><div class="wrap"><div class="grid g3">%s</div></div></section>' % cards

def blog():
    cards = ''.join('<a class="card kn-tile" href="blog-%s.html"><h3>%s</h3><p>%s</p></a>' % (a['slug'], bi(a['ar'], a['en']), bi(a['dar'], a['den'])) for a in ARTICLES)
    return hero('المدونة', 'Blog', 'مقالات قصيرة وواضحة في نظام العمل والرواتب والامتثال', 'Short, clear articles on the Labor Law, payroll and compliance') + '<section><div class="wrap"><div class="grid g2">%s</div>%s</div></section>' % (cards, NOTE)

def article(a):
    body = ''.join('<h2>%s</h2><p>%s</p>' % (bi(h1, h2), bi(p1, p2)) for h1, h2, p1, p2 in a['body'])
    more = ''.join('<li><a href="blog-%s.html">%s</a></li>' % (x['slug'], bi(x['ar'], x['en'])) for x in ARTICLES if x is not a)
    return ('<div class="phero"><div class="wrap"><a class="small" href="blog.html" style="color:inherit">%s</a><h1>%s</h1><p>%s</p></div></div>' % (bi('المدونة', 'Blog'), bi(a['ar'], a['en']), bi(a['dar'], a['den']))
            + '<section><div class="wrap kn-art"><article class="card">%s%s</article><div class="card"><h3>%s</h3><ul>%s</ul></div>%s</div></section>' % (body, NOTE, bi('مقالات أخرى', 'More articles'), more, CTA))

def policies():
    items = ''.join('<details class="card kn-d"><summary><b>%s</b></summary><ol>%s</ol><p class="small">%s</p></details>' % (
        bi(a, b), ''.join('<li>%s</li>' % bi(x, y) for x, y in cl), bi('عدّل النص لمنشأتك، واربطه بلائحة تنظيم العمل المعتمدة لديك.', 'Adapt the text for your company and link it to your approved work regulations.')) for a, b, cl in POLICIES)
    return hero('نماذج السياسات', 'Policy templates', 'نقاط أساسية لسياسات الموارد البشرية الشائعة، تبدأ منها وتعدّلها', 'Key points of common HR policies to start from and adapt') + '<section><div class="wrap kn-art">%s%s%s</div></section>' % (items, NOTE, CTA)

def jobs():
    items = ''.join('<details class="card kn-d"><summary><b>%s</b></summary><p>%s</p><h4>%s</h4><ul>%s</ul><h4>%s</h4><ul>%s</ul></details>' % (
        bi(a, b), bi(pa, pe), bi('المهام', 'Tasks'), ''.join('<li>%s</li>' % bi(x, y) for x, y in t), bi('المتطلبات', 'Requirements'), ''.join('<li>%s</li>' % bi(x, y) for x, y in r))
        for a, b, pa, pe, t, r in JOBS)
    return hero('الأوصاف الوظيفية', 'Job descriptions', 'الغرض والمهام والمتطلبات لأشهر الوظائف في المنشآت', 'Purpose, tasks and requirements of common jobs') + '<section><div class="wrap kn-art">%s%s</div></section>' % (items, CTA)

def glossary():
    rows = ''.join('<div class="card kn-g"><h3>%s <span class="small">%s</span></h3><p>%s</p></div>' % (e(a), e(b), bi(c, d)) for a, b, c, d in sorted(GLOSSARY, key=lambda x: x[0]))
    return hero('مصطلحات الموارد البشرية', 'HR glossary', 'أهم المصطلحات في الموارد البشرية والرواتب والامتثال في السعودية', 'Key terms in HR, payroll and compliance in Saudi Arabia') + '<section><div class="wrap kn-art">%s%s</div></section>' % (rows, NOTE)

def pages():
    """(page, out, title, description, body) for site/build.py"""
    out = [('knowledge', 'knowledge.html', 'المعرفة | وعد', 'مرجع مجاني في الموارد البشرية: مقالات، ونماذج سياسات، وأوصاف وظيفية، ومصطلحات، وأدوات حساب.', hub()),
           ('knowledge', 'blog.html', 'المدونة | وعد', 'مقالات في نظام العمل السعودي ومكافأة نهاية الخدمة والإجازات والتأمينات ونطاقات وحماية الأجور.', blog())]
    out += [('knowledge', 'blog-%s.html' % a['slug'], a['ar'] + ' | وعد', a['dar'], article(a)) for a in ARTICLES]
    out += [('knowledge', 'policies.html', 'نماذج سياسات الموارد البشرية | وعد', 'نماذج جاهزة لسياسات الحضور والإجازات والعمل عن بعد والعهد والسلوك المهني والمصروفات.', policies()),
            ('knowledge', 'jobs.html', 'الأوصاف الوظيفية | وعد', 'أوصاف وظيفية جاهزة: أخصائي موارد بشرية، محاسب، مندوب مبيعات، أمين مستودع، وغيرها.', jobs()),
            ('knowledge', 'glossary.html', 'مصطلحات الموارد البشرية | وعد', 'معاني مصطلحات الموارد البشرية في السعودية: حماية الأجور، مدد، قوى، نطاقات، التأمينات، نهاية الخدمة.', glossary())]
    return out
