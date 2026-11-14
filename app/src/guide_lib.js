'use strict';
/* ===== «دليل الاستخدام» (#/guide): how to use Waad, by role (employee, direct manager, the people who run the company).
   Arabic and English pairs, read with hT() like help_lib.js, so this file is skipped by i18n/extract.py.
   Each topic: id, t = [ar, en] title, s = steps, img = screenshot base name (site/img/guide/<img>-<lang>.webp, taken by
   site/guide_shots.py from a fictitious company), go = the page it opens, when = only shown if true. ===== */
const GUIDE = {
  emp: { t: ['للموظف', 'For employees'], items: [
    { id: 'login', img: 'login', t: ['أول دخول للنظام', 'Signing in for the first time'], s: [
      ['افتح رابط النظام من جوالك أو جهازك، واختر «دخول الموظفين».', 'Open the system link on your phone or computer and choose «Employee sign-in».'],
      ['أدخل رمز المنشأة الذي أعطتك إياه الموارد البشرية (مرة واحدة فقط، ويتذكره النظام).', 'Enter the company code HR gave you (only once; the system remembers it).'],
      ['أدخل رقمك الوظيفي وكلمة المرور المؤقتة، ثم اختر كلمة مرور خاصة بك.', 'Enter your employee number and the temporary password, then choose your own password.'],
      ['نسيت كلمة المرور؟ اطلب من الموارد البشرية إعادة تعيينها.', 'Forgot your password? Ask HR to reset it.']] },
    { id: 'home', img: 'home', go: '#/home', t: ['الصفحة الرئيسية والتنبيهات', 'Home page and alerts'], s: [
      ['تعرض الرئيسية رصيد إجازتك وآخر طلباتك وما يحتاج انتباهك.', 'Home shows your leave balance, your latest requests and what needs your attention.'],
      ['من «حسابي» أعلى الشاشة تجد التنبيهات، واللغة، وتغيير كلمة المرور، وتثبيت وعد على جوالك.', 'From «My account» at the top you get alerts, language, password change and installing Waad on your phone.'],
      ['القائمة الجانبية (☰ في الجوال) فيها كل خدماتك تحت «خدماتي».', 'The side menu (☰ on a phone) lists all your services under «My services».']] },
    { id: 'att', img: 'attendance', go: '#/attendance', when: () => !!(S.company && S.company.att_enabled && !(S.myEmp && S.myEmp.att_exempt)), t: ['تسجيل الحضور والانصراف', 'Checking in and out'], s: [
      ['افتح «حضوري» واضغط «تسجيل الحضور» عند وصولك.', 'Open «My attendance» and press «Check in» when you arrive.'],
      ['إذا طلب المتصفح موقعك فاسمح له، فبعض المنشآت تشترط التسجيل من موقع العمل.', 'If the browser asks for your location, allow it; some companies require checking in at the workplace.'],
      ['عند خروجك اضغط «تسجيل الانصراف»، وتظهر لك ساعات يومك وتأخيرك إن وُجد.', 'When you leave press «Check out»; your hours and any lateness are shown.'],
      ['نسيت التسجيل؟ قدّم طلب «نسيان بصمة» من «طلباتي».', 'Forgot to check in? Send a «Missed punch» request from «My requests».']] },
    { id: 'leave', img: 'newreq', go: '#/requests', t: ['طلب إجازة', 'Requesting leave'], s: [
      ['افتح «طلباتي» واضغط «طلب جديد».', 'Open «My requests» and press «New request».'],
      ['اختر «إجازة» ونوعها (سنوية، مرضية، ...)، ثم تاريخ البداية والنهاية.', 'Choose «Leave» and its type (annual, sick, ...), then the start and end dates.'],
      ['يعرض لك النموذج رصيدك وعدد الأيام قبل الإرسال.', 'The form shows your balance and the number of days before you send.'],
      ['اضغط «إرسال»، فيذهب الطلب إلى مديرك المباشر ثم الموارد البشرية حسب مسار منشأتك.', 'Press «Send»; it goes to your direct manager and then HR, following your company\'s route.']] },
    { id: 'other', go: '#/requests', t: ['طلبات أخرى', 'Other requests'], s: [
      ['من «طلب جديد» نفسه تقدر تطلب: استئذان، سلفة، تعريف بالراتب، مطالبة مصروفات، تحديث بيانات، تذكرة سفر، تأشيرة خروج وعودة، أو استقالة.', 'The same «New request» covers: a permission, an advance, a salary certificate, an expense claim, a data update, a travel ticket, an exit/re-entry visa, or a resignation.'],
      ['بعض أنواع الإجازة تطلب مرفقا (مثل التقرير الطبي للإجازة المرضية)، ويوضح لك النموذج ذلك.', 'Some leave types need an attachment (like a medical report for sick leave); the form tells you.']] },
    { id: 'track', img: 'requests', go: '#/requests', t: ['متابعة طلبك أو إلغاؤه', 'Following or cancelling a request'], s: [
      ['في «طلباتي» ترى حالة كل طلب: بانتظار (وعند من)، معتمد، أو مرفوض مع السبب.', 'In «My requests» you see each request\'s status: waiting (and with whom), approved, or rejected with the reason.'],
      ['تقدر تلغي الطلب ما دام لم يُعتمد بعد.', 'You can cancel a request until it is approved.'],
      ['الاستقالة: يحق لك العدول عنها خلال 7 أيام من تقديمها.', 'Resignation: you may withdraw it within 7 days of submitting it.']] },
    { id: 'slip', img: 'payslips', go: '#/payslips', t: ['قسيمة الراتب', 'Your payslip'], s: [
      ['تظهر قسيمة كل شهر في «قسائم الراتب» بعد اعتماد مسير الرواتب.', 'Each month\'s payslip appears in «Payslips» once the payroll run is approved.'],
      ['اضغط الشهر لترى التفاصيل: الراتب والبدلات والإضافي والاستقطاعات والصافي.', 'Press the month for the details: pay, allowances, overtime, deductions and net.'],
      ['تقدر تطبعها أو تحفظها PDF.', 'You can print it or save it as PDF.']] },
    { id: 'profile', img: 'profile', go: '#/profile', t: ['ملفي والمخالفات', 'My profile and penalties'], s: [
      ['في «ملفي» بياناتك الوظيفية وراتبك ومديرك المباشر.', '«My profile» has your job details, pay and direct manager.'],
      ['لتعديل بياناتك (الجوال، العنوان، ...) اضغط «طلب تعديل بياناتي»، وتعتمده الموارد البشرية.', 'To change your data (mobile, address, ...) press «Request a change to my data»; HR approves it.'],
      ['إذا نُسبت إليك مخالفة تظهر هنا: اطّلع عليها وأرسل ردك الكتابي.', 'If a violation is recorded against you it shows here: read it and send your written reply.'],
      ['إذا صدر بحقك جزاء فلك حق التظلم خلال 30 يوما من إبلاغك (م72).', 'If a penalty is issued you may appeal within 30 days of being notified (Art. 72).']] },
    { id: 'pol', go: '#/policies', t: ['السياسات واللوائح', 'Policies'], s: [
      ['اقرأ سياسات منشأتك ولائحة تنظيم العمل من «السياسات واللوائح».', 'Read your company\'s policies and work regulations under «Policies».'],
      ['بعد القراءة اضغط «اطلعت على هذه السياسة» ليُسجَّل اطلاعك.', 'After reading press «I have read this policy» to record it.']] },
    { id: 'app', t: ['ثبّت وعد على جوالك', 'Install Waad on your phone'], s: [
      ['من «حسابي» اختر «ثبّت وعد على جوالك»، فيظهر النظام كتطبيق على شاشتك.', 'From «My account» choose «Install Waad on your phone»; it appears as an app on your screen.'],
      ['في آيفون: من سفاري اضغط زر المشاركة ثم «إضافة إلى الشاشة الرئيسية».', 'On iPhone: in Safari press Share, then «Add to Home Screen».']] }] },
  mgr: { t: ['للمدير المباشر', 'For direct managers'], items: [
    { id: 'appr', img: 'approvals', go: '#/approvals', t: ['اعتماد طلبات فريقك', 'Approving your team\'s requests'], s: [
      ['الرقم بجانب «الاعتمادات» هو عدد الطلبات التي تنتظرك.', 'The number next to «Approvals» is how many requests wait for you.'],
      ['افتح الطلب وراجع التفاصيل ورصيد الموظف.', 'Open the request and check the details and the employee\'s balance.'],
      ['اعتمد أو ارفض، واكتب السبب عند الرفض ليصل للموظف.', 'Approve or reject, and write the reason when rejecting so the employee sees it.']] },
    { id: 'team', go: '#/att', t: ['حضور فريقك وإجازاتهم', 'Your team\'s attendance and leave'], s: [
      ['«حضور الفريق» يعرض الحاضر والمتأخر والغائب كل يوم.', '«Team attendance» shows who is present, late or absent each day.'],
      ['«تقويم الإجازات» يعرض من في إجازة، لتنظيم العمل قبل اعتماد طلب جديد.', '«Leave calendar» shows who is on leave, so you can plan before approving a new request.']] },
    { id: 'rev', go: '#/reviews', t: ['تقييم أداء فريقك', 'Reviewing your team'], s: [
      ['عند فتح دورة تقييم، تظهر لك مراجعة لكل موظف في فريقك.', 'When a review cycle opens, you get a review for each member of your team.'],
      ['اكتب الأهداف بأوزان مجموعها 100% وقيّم كل هدف، ثم أرسل التقييم للموارد البشرية.', 'Write the goals with weights totalling 100% and score each one, then send it to HR.']] }] },
  admin: { t: ['لإدارة المنشأة', 'For the company\'s admins'], items: [
    { id: 'access', img: 'mklogin', go: '#/employees', t: ['أعطِ موظفيك الدخول', 'Give your employees access'], s: [
      ['من «الموظفون» افتح سجل الموظف واضغط «إنشاء دخول للموظف».', 'In «Employees» open the employee\'s record and press «Create employee login».'],
      ['يظهر رمز المنشأة والرقم الوظيفي وكلمة مرور مؤقتة، وأرسلها للموظف بزر الواتساب.', 'The company code, employee number and a temporary password appear; send them with the WhatsApp button.'],
      ['المدراء والمحاسبون يُدعَون بالبريد من «المستخدمون والدعوات».', 'Managers and accountants are invited by e-mail from «Users and invitations».']] },
    { id: 'print', t: ['اطبع دليل الموظف', 'Print the employee guide'], s: [
      ['اضغط «اطبع دليل الموظف» أعلى هذه الصفحة: صفحة واحدة فيها رابط النظام ورمز منشأتك وأهم الخدمات.', 'Press «Print the employee guide» at the top of this page: one page with the system link, your company code and the main services.'],
      ['احفظها PDF وأرسلها لموظفيك يوم الإطلاق، أو علّقها في لوحة الإعلانات.', 'Save it as PDF and send it to your employees on launch day, or pin it on the notice board.']] },
    { id: 'more', go: '#/help', t: ['شروحات بقية الأقسام', 'The other modules'], s: [
      ['لكل صفحة شرح مختصر: اضغط «؟» أعلى الشاشة، أو افتح «مركز المساعدة».', 'Every page has a short explanation: press «?» at the top, or open the «Help center».'],
      ['وقائمة «ابدأ هنا» ترتّب لك تجهيز المنشأة خطوة بخطوة.', 'And «Start here» walks you through setting up the company step by step.']] }] }
};

/* «اختبر فهمك»: a few questions at the end of a role's guide. The right answers are kept in the database only
   (guide_quiz_key in 0084), which marks each attempt; the result goes to the company's owner and HR. */
const GUIDE_QUIZ = {
  emp: [
    { id: 'e1', q: ['من أين تطلب إجازة؟', 'Where do you request leave?'], a: [['من «ملفي»', 'From «My profile»'], ['من «طلباتي» ثم «طلب جديد»', 'From «My requests», then «New request»'], ['من «قسائم الراتب»', 'From «Payslips»']] },
    { id: 'e2', q: ['نسيت تسجيل حضورك اليوم، ماذا تفعل؟', 'You forgot to check in today. What do you do?'], a: [['أقدّم طلب «نسيان بصمة» من «طلباتي»', 'Send a «Missed punch» request from «My requests»'], ['لا شيء، يُصحَّح تلقائيا', 'Nothing, it fixes itself'], ['أسجّل الحضور مرتين غدا', 'Check in twice tomorrow']] },
    { id: 'e3', q: ['متى تظهر قسيمة راتبك في النظام؟', 'When does your payslip appear in the system?'], a: [['أول يوم من كل شهر', 'On the first day of each month'], ['عندما أطلبها من الموارد البشرية', 'When I ask HR for it'], ['بعد اعتماد مسير الرواتب', 'Once the payroll run is approved']] },
    { id: 'e4', q: ['تريد تغيير رقم جوالك المسجّل، كيف؟', 'You want to change your registered mobile number. How?'], a: [['من «ملفي» ثم «طلب تعديل بياناتي»', 'From «My profile», then «Request a change to my data»'], ['أعدّله بنفسي مباشرة في أي صفحة', 'I edit it myself on any page'], ['لا يمكن تغييره', 'It can\'t be changed']] },
    { id: 'e5', q: ['تقدر تلغي طلبك متى؟', 'When can you cancel your request?'], a: [['في أي وقت حتى بعد اعتماده', 'Any time, even after approval'], ['ما دام لم يُعتمد بعد', 'As long as it isn\'t approved yet'], ['لا يمكن إلغاء أي طلب', 'No request can be cancelled']] },
    { id: 'e6', q: ['إذا صدر بحقك جزاء، خلال كم يوما يحق لك التظلم؟', 'If a penalty is issued against you, within how many days may you appeal?'], a: [['7 أيام', '7 days'], ['60 يوما', '60 days'], ['30 يوما من إبلاغك', '30 days from being notified']] },
    { id: 'e7', q: ['نسيت كلمة المرور، ماذا تفعل؟', 'You forgot your password. What do you do?'], a: [['أطلب من الموارد البشرية إعادة تعيينها', 'Ask HR to reset it'], ['أنشئ حسابا جديدا', 'Create a new account'], ['أدخل برقم موظف آخر', 'Sign in with another employee\'s number']] }],
  mgr: [
    { id: 'm1', q: ['أين تجد طلبات فريقك التي تنتظرك؟', 'Where do you find your team\'s requests waiting for you?'], a: [['في «طلباتي»', 'In «My requests»'], ['في «الاعتمادات»', 'In «Approvals»'], ['في «ملفي»', 'In «My profile»']] },
    { id: 'm2', q: ['عند رفض طلب موظف، ماذا تفعل؟', 'When you reject an employee\'s request, what do you do?'], a: [['أكتب سبب الرفض ليصل للموظف', 'Write the reason so the employee sees it'], ['أرفضه دون سبب', 'Reject it without a reason'], ['أتركه دون قرار', 'Leave it without a decision']] },
    { id: 'm3', q: ['قبل اعتماد إجازة جديدة، أين ترى من في إجازة من فريقك؟', 'Before approving new leave, where do you see who in your team is on leave?'], a: [['في «قسائم الراتب»', 'In «Payslips»'], ['في «السياسات واللوائح»', 'In «Policies»'], ['في «تقويم الإجازات»', 'In «Leave calendar»']] },
    { id: 'm4', q: ['في تقييم الأداء، كم يجب أن يكون مجموع أوزان الأهداف؟', 'In a performance review, what must the goals\' weights total?'], a: [['100%', '100%'], ['50%', '50%'], ['أي مجموع', 'Any total']] }]
};
