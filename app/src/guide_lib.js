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
      ['نسيت كلمة المرور؟ اكتب رقمك الوظيفي واضغط «نسيت كلمة المرور»، فيصل طلبك إلى الموارد البشرية في منشأتك.', 'Forgot your password? Enter your employee number and press «Forgot password»; the request goes to your company\'s HR.'],
      ['ابقِ «تذكر دخولي» مفعلا على جهازك الخاص فقط، ويمكنك تفعيل الدخول بالبصمة أو الوجه من «حسابي».', 'Keep «Remember me» on only on your own device; you can turn on fingerprint or face unlock from «My account».']] },
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
      ['من «طلب جديد» نفسه يمكنك طلب: استئذان، سلفة، تعريف بالراتب، مطالبة مصروفات، رحلة عمل، عمل إضافي بموافقة مسبقة، عمل عن بعد، تحديث بيانات، تذكرة سفر، تأشيرة خروج وعودة، أو استقالة.', 'The same «New request» covers: a permission, an advance, a salary certificate, an expense claim, a business trip, overtime approved in advance, remote work, a data update, a travel ticket, an exit/re-entry visa, or a resignation.'],
      ['في الإجازة المرضية يبين لك النموذج قبل الإرسال كم يوما بأجر كامل وبثلاثة أرباع الأجر وبدون أجر (م117). وللسفر اختر «إجازة سنوية خارجية» واكتب بلد الوجهة.', 'For sick leave the form shows, before you send, how many days are at full pay, three-quarter pay and unpaid (Art. 117). For travel choose «Annual leave abroad» and enter the destination.'],
      ['بعض أنواع الإجازة تطلب مرفقا (مثل التقرير الطبي للإجازة المرضية)، ويوضح لك النموذج ذلك.', 'Some leave types need an attachment (like a medical report for sick leave); the form tells you.']] },
    { id: 'track', img: 'requests', go: '#/requests', t: ['متابعة طلبك أو إلغاؤه', 'Following or cancelling a request'], s: [
      ['في «طلباتي» ترى حالة كل طلب: بانتظار (وعند من)، معتمد، أو مرفوض مع السبب.', 'In «My requests» you see each request\'s status: waiting (and with whom), approved, or rejected with the reason.'],
      ['يمكنك إلغاء الطلب ما دام لم يُعتمد بعد.', 'You can cancel a request until it is approved.'],
      ['الاستقالة: يحق لك العدول عنها خلال 7 أيام من تقديمها.', 'Resignation: you may withdraw it within 7 days of submitting it.']] },
    { id: 'slip', img: 'payslips', go: '#/payslips', t: ['قسيمة الراتب', 'Your payslip'], s: [
      ['تظهر قسيمة كل شهر في «قسائم الراتب» بعد اعتماد مسير الرواتب.', 'Each month\'s payslip appears in «Payslips» once the payroll run is approved.'],
      ['اضغط الشهر لترى التفاصيل: الراتب والبدلات والإضافي والاستقطاعات والصافي.', 'Press the month for the details: pay, allowances, overtime, deductions and net.'],
      ['يمكنك طباعتها أو حفظها PDF.', 'You can print it or save it as PDF.']] },
    { id: 'profile', img: 'profile', go: '#/profile', t: ['ملفي والمخالفات', 'My profile and penalties'], s: [
      ['في «ملفي» بياناتك الوظيفية وراتبك ومديرك المباشر.', '«My profile» has your job details, pay and direct manager.'],
      ['لتعديل بياناتك (الجوال، العنوان، ...) اضغط «طلب تعديل بياناتي»، وتعتمده الموارد البشرية.', 'To change your data (mobile, address, ...) press «Request a change to my data»; HR approves it.'],
      ['إذا نُسبت إليك مخالفة تظهر هنا: اطّلع عليها وأرسل ردك الكتابي.', 'If a violation is recorded against you it shows here: read it and send your written reply.'],
      ['إذا صدر بحقك جزاء فلك حق التظلم خلال 30 يوما من إبلاغك (م72).', 'If a penalty is issued you may appeal within 30 days of being notified (Art. 72).']] },
    { id: 'dir', go: '#/directory', t: ['دليل الموظفين', 'Staff directory'], s: [
      ['افتح «دليل الموظفين» لتجد أي زميل: اسمه وإدارته ومسماه ورقم تحويلته.', 'Open «Staff directory» to find any colleague: name, department, title and extension.'],
      ['من «بياناتي في الدليل» اكتب رقم تحويلتك، واختر هل يظهر جوالك وبريدك لزملائك (مخفيان ما لم تختر إظهارهما).', 'In «My directory details» enter your extension and choose whether your mobile and e-mail show to colleagues (hidden unless you choose).']] },
    { id: 'kudos', go: '#/kudos', t: ['الشكر والتقدير', 'Recognition'], s: [
      ['افتح «الشكر والتقدير» واضغط «اشكر زميلا»، واختر الزميل والقيمة (روح الفريق، التميز، المساعدة…) واكتب رسالتك.', 'Open «Recognition», press «Thank a colleague», pick the colleague and the value (teamwork, excellence, help…) and write your message.'],
      ['يرى الجميع الشكر في الصفحة وفي الرئيسية، ويظهر الأكثر شكرا في الشهر.', 'Everyone sees it on the page and on home, with the most thanked of the month.']] },
    { id: 'grv', go: '#/grievance', t: ['البلاغ السري', 'Confidential report'], s: [
      ['لرفع شكوى أو بلاغ بسرية افتح «بلاغ سري» ثم «بلاغ جديد»، واختر نوعه ولمن يصل: الموارد البشرية أو المالك فقط.', 'To raise a complaint or report confidentially open «Confidential report», then «New report»; choose its type and who gets it: HR or the owner only.'],
      ['يمكنك إرساله «بدون اسمي» فلا يظهر اسمك لمن يعالجه، وتتابع الرد والحالة من الصفحة نفسها.', 'You can send it «without my name» so whoever handles it does not see it, and you follow the replies and status on the same page.'],
      ['للاعتراض على جزاء صدر بحقك استخدم «ملفي» ← الجزاءات، وليس البلاغ السري.', 'To appeal a penalty use «My profile» → penalties, not the confidential report.']] },
    { id: 'expr', go: '#/requests', t: ['مطالبة المصروفات مع الإيصال', 'Expense claims with the receipt'], s: [
      ['في «طلب جديد» اختر «مطالبة مصروفات» واكتب المبلغ، ثم أرفق الإيصال أو الفاتورة (صورة أو PDF).', 'In «New request» choose «Expense claim», enter the amount and attach the receipt or invoice (photo or PDF).'],
      ['اضغط «📷 تصوير الفاتورة وقراءتها» وصوّر رمز QR في الفاتورة: يقرؤه وعد على جهازك ويكتب المبلغ والمورد والرقم الضريبي بنفسه، ويرفق الصورة. يراها مديرك والمالية قبل الاعتماد.', 'Press «📷 Photograph and read the invoice» and take the QR code on the invoice: Waad reads it on your device, fills in the amount, supplier and VAT number, and attaches the photo. Your manager and finance see it before approving.'],
      ['إذا قُدّمت الفاتورة نفسها من قبل في المنشأة يظهر لك ولمن يعتمد تنبيه بأنها مكررة. الفاتورة اللي ما فيها رمز QR تُكتب بياناتها باليد.', 'If the same invoice was already submitted in the company, you and the approver see a duplicate warning. An invoice without a QR code is typed in by hand.']] },
    { id: 'swap', go: '#/requests', when: () => !!(S.company && S.company.att_enabled), t: ['تبديل الوردية مع زميل', 'Swapping a shift with a colleague'], s: [
      ['في «طلب جديد» اختر «تبديل وردية مع زميل»، ثم الزميل واليوم.', 'In «New request» choose «Swap a shift with a colleague», then the colleague and the day.'],
      ['يوافق زميلك من «طلباتي»، ثم يعتمد مديرك أو الموارد البشرية، فيتغيّر جدول الورديات لكما تلقائيا.', 'Your colleague accepts from «My requests», then your manager or HR approves, and the roster changes for both of you automatically.']] },
    { id: 'exit', go: '#/exit', when: () => !!(S.myEmp && S.myEmp.end_date), t: ['مقابلة نهاية الخدمة', 'Exit interview'], s: [
      ['عند انتهاء خدمتك تجد «مقابلة نهاية الخدمة» في القائمة: أسباب مغادرتك وتقييمك وملاحظاتك.', 'When your service ends you find «Exit interview» in the menu: your reasons for leaving, your ratings and comments.'],
      ['تراها الموارد البشرية فقط، ولا تؤثر على مستحقاتك.', 'Only HR sees it, and it does not affect your dues.']] },
    { id: 'pol', go: '#/policies', t: ['السياسات واللوائح', 'Policies'], s: [
      ['اقرأ سياسات منشأتك ولائحة تنظيم العمل من «السياسات واللوائح».', 'Read your company\'s policies and work regulations under «Policies».'],
      ['بعد القراءة اضغط «اطلعت على هذه السياسة» ليُسجَّل اطلاعك.', 'After reading press «I have read this policy» to record it.']] },
    { id: 'sign', go: '#/sign', t: ['توقيع المستندات', 'Signing documents'], s: [
      ['عندما تطلب منك الموارد البشرية توقيع عقد أو عهدة، يظهر الرقم بجانب «توقيعاتي».', 'When HR asks you to sign a contract or custody receipt, a number appears next to «My signatures».'],
      ['افتحه واقرأ النص ثم وقّع بإصبعك.', 'Open it, read the text and sign with your finger.']] },
    { id: 'surveys', go: '#/surveys', t: ['الاستبيانات والإعلانات', 'Surveys and announcements'], s: [
      ['إعلانات المنشأة تظهر أعلى صفحتك الرئيسية؛ اضغط «تم الاطلاع» بعد قراءتها.', 'Company announcements appear at the top of your home page; press «Got it» after reading.'],
      ['إذا وصلك استبيان أجب عليه من «الاستبيانات». الاستبيان المجهول لا يظهر فيه اسمك.', 'If you get a survey, answer it from «Surveys». In an anonymous survey your name never shows.']] },
    { id: 'notify', t: ['التنبيهات على جوالك', 'Notifications on your phone'], s: [
      ['من «حسابي» اختر «تفعيل التنبيهات على هذا الجهاز» ووافق على السماح.', 'From «My account» choose «Turn on notifications on this device» and allow them.'],
      ['يصلك تنبيه عند اعتماد طلبك أو رفضه، وعند صدور قسيمة راتبك، وعند طلب توقيعك.', 'You are notified when a request is approved or rejected, when your payslip is out and when your signature is needed.'],
      ['في الآيفون ثبّت وعد على الشاشة الرئيسية أولا ثم فعّل التنبيهات من داخله.', 'On iPhone, add Waad to the home screen first, then turn notifications on from inside it.']] },
    { id: 'mytime', go: '#/mytime', when: () => !!S.myTime, t: ['تسجيل ساعات عملك على المشاريع', 'Logging your project hours'], s: [
      ['افتح «ساعات عملي» وسجّل ساعات يوم، أو افتح «جدول الأسبوع» لتعبئة الأسبوع كله مرة واحدة.', 'Open «My hours» and log a day, or open «Week sheet» to fill the whole week at once.'],
      ['تذهب الساعات لمدير المشروع للاعتماد، ويمكنك سحبها قبل اعتمادها. إذا رُفضت يظهر لك السبب.', 'The hours go to the project manager for approval, and you can withdraw them before that. If rejected, you see the reason.']] },
    { id: 'app', t: ['ثبّت وعد على جوالك', 'Install Waad on your phone'], s: [
      ['من «حسابي» اختر «ثبّت وعد على جوالك»، فيظهر النظام كتطبيق على شاشتك.', 'From «My account» choose «Install Waad on your phone»; it appears as an app on your screen.'],
      ['في آيفون: من سفاري اضغط زر المشاركة ثم «إضافة إلى الشاشة الرئيسية».', 'On iPhone: in Safari press Share, then «Add to Home Screen».']] }] },
  mgr: { t: ['للمدير المباشر', 'For direct managers'], items: [
    { id: 'pm', go: '#/projects', when: () => !!S.myPM, t: ['إدارة مشروعك', 'Running your project'], s: [
      ['إذا كنت مدير مشروع تجده في «المشاريع»، وترى مشاريعك أنت فقط.', 'If you manage a project you find it under «Projects»; you see only your own projects.'],
      ['نظّم المراحل والمهام والفريق والمخاطر، وتابع الإنجاز والربحية.', 'Organise milestones, tasks, the team and risks, and follow progress and profitability.'],
      ['اعتمد ساعات فريقك من «ساعات عملي». لا تظهر لك تكلفة ساعات كل موظف حفاظا على سرية الرواتب.', 'Approve your team\'s hours from «My hours». Each person\'s hourly cost is hidden to keep pay private.']] },
    { id: 'appr', img: 'approvals', go: '#/approvals', t: ['اعتماد طلبات فريقك', 'Approving your team\'s requests'], s: [
      ['الرقم بجانب «الاعتمادات» هو عدد الطلبات التي تنتظرك.', 'The number next to «Approvals» is how many requests wait for you.'],
      ['افتح الطلب وراجع التفاصيل ورصيد الموظف.', 'Open the request and check the details and the employee\'s balance.'],
      ['اعتمد أو ارفض، واكتب السبب عند الرفض ليصل للموظف.', 'Approve or reject, and write the reason when rejecting so the employee sees it.']] },
    { id: 'team', go: '#/att', t: ['حضور فريقك وإجازاتهم', 'Your team\'s attendance and leave'], s: [
      ['«حضور الفريق» يعرض الحاضر والمتأخر والغائب كل يوم.', '«Team attendance» shows who is present, late or absent each day.'],
      ['«تقويم الإجازات» يعرض من في إجازة، لتنظيم العمل قبل اعتماد طلب جديد.', '«Leave calendar» shows who is on leave, so you can plan before approving a new request.']] },
    { id: 'fb360', go: '#/reviews', t: ['تقييم 360 وآراء الزملاء', '360 feedback'], s: [
      ['من نافذة تقييم الموظف اضغط «طلب تقييم 360 من الزملاء» واختر الزملاء.', 'From an employee\'s review press «Request 360 feedback from colleagues» and pick colleagues.'],
      ['يظهر لك متوسط التقييم الذاتي وآراء الزملاء بدون أسماء، من رأيين فأكثر.', 'You see the self-rating and colleagues\' averages without names, from two answers.']] },
    { id: 'bulk', img: 'approvals', go: '#/approvals', t: ['الاعتماد الجماعي وتذكير المتأخر', 'Bulk approval and late reminders'], s: [
      ['في «الاعتمادات» حدد عدة طلبات (أو «تحديد الكل») ثم «اعتماد المحدد» لتعتمدها بضغطة.', 'In «Approvals» tick several requests (or «Select all») then «Approve selected» to approve them with one press.'],
      ['الطلب الذي ينتظرك أكثر من 3 أيام (أو مهلة منشأتك) يصلك عنه تذكير على جوالك وبالإيميل.', 'A request waiting for you more than 3 days (or your company\'s deadline) brings a reminder on your phone and by e-mail.'],
      ['طلبات تبديل الورديات التي وافق عليها الزميلان تظهر أسفل الصفحة لتعتمدها أو ترفضها.', 'Shift swaps both colleagues agreed to show at the bottom of the page for you to approve or reject.']] },
    { id: 'prob', go: '#/probation', t: ['تقييم فترة التجربة', 'Probation evaluation'], s: [
      ['افتح «تقييم فترة التجربة»: يظهر من تنتهي فترة تجربته خلال 30 يوما.', 'Open «Probation evaluation»: it lists who finishes probation within 30 days.'],
      ['اضغط «تقييم» وقيّم خمسة بنود من 1 إلى 5، واكتب نقاط القوة وما يحتاج تحسينا، ثم التوصية: تثبيت أو تمديد أو إنهاء.', 'Press «Evaluate», rate five items from 1 to 5, write strengths and what needs improving, then recommend: confirm, extend or end.'],
      ['تصدر الموارد البشرية القرار، والتمديد لا تزيد معه فترة التجربة كلها على 180 يوما (م53).', 'HR issues the decision; with an extension the whole probation stays within 180 days (Art. 53).']] },
    { id: 'move', go: '#/employees', t: ['طلب نقل أو ترقية لموظفك', 'Transfer or promotion for your employee'], s: [
      ['افتح ملف الموظف واضغط «طلب نقل أو ترقية»: الإدارة أو المسمى أو المدير أو الأجر الجديد وتاريخ السريان والسبب.', 'Open the employee\'s file and press «Transfer or promotion request»: the new department, title, manager or pay, the effective date and the reason.'],
      ['يمر على الموارد البشرية ثم الاعتماد حسب مسار منشأتك، ويُطبَّق على ملف الموظف عند الاعتماد النهائي.', 'It passes HR and then the company\'s approvals, and is applied to the employee file on the final approval.']] },
    { id: 'cmp', go: '#/competencies', t: ['جدارات فريقك', 'Your team\'s competencies'], s: [
      ['في «جدارات فريقي» قيّم كل موظف على الجدارات من 1 إلى 5.', 'In «My team\'s competencies» rate each employee on the competencies from 1 to 5.'],
      ['الرقم الأحمر يعني أقل من المطلوب في وصفه الوظيفي: فجوة تحتاج تطويرا أو تدريبا.', 'A red number is below what their job description requires: a gap that needs development or training.']] },
    { id: 'hc', go: '#/workforce', t: ['طلب وظيفة جديدة لفريقك', 'Requesting a new position for your team'], s: [
      ['من «خطة القوى العاملة» اضغط «طلب وظيفة» واكتب المسمى والعدد والتكلفة الشهرية.', 'In «Workforce plan» press «Position request» and enter the title, headcount and monthly cost.'],
      ['تعتمدها الموارد البشرية ثم المالية، وبعدها تصبح وظيفة شاغرة.', 'HR then finance approve it, and it becomes a job opening.']] },
    { id: 'rev', go: '#/reviews', t: ['تقييم أداء فريقك', 'Reviewing your team'], s: [
      ['عند فتح دورة تقييم، تظهر لك مراجعة لكل موظف في فريقك.', 'When a review cycle opens, you get a review for each member of your team.'],
      ['اكتب الأهداف بأوزان مجموعها 100% وقيّم كل هدف، ثم أرسل التقييم للموارد البشرية.', 'Write the goals with weights totalling 100% and score each one, then send it to HR.']] }] },
  admin: { t: ['لإدارة المنشأة', 'For the company\'s admins'], items: [
    { id: 'projects', go: '#/projects', t: ['المشاريع وربحيتها', 'Projects and their profitability'], s: [
      ['أنشئ المشروع بقيمة عقده وموازنة تكلفته ومديره؛ يُنشأ له مركز تكلفة برقمه تلقائيا.', 'Create the project with its contract value, cost budget and manager; it gets a cost center with its number automatically.'],
      ['قسّمه إلى مراحل بأوزان مجموعها 100%، وأضف المهام، وتابعها في لوحة المهام والجدول الزمني.', 'Split it into milestones whose weights total 100%, add tasks, and follow them on the board and the timeline.'],
      ['اختر المشروع والمرحلة في أوامر الشراء والعهد وصرف المواد، واختر المشروع في الفواتير، لتظهر تكلفته الفعلية.', 'Choose the project and milestone on purchase orders, petty cash and material issues, and the project on invoices, to see its real cost.'],
      ['الساعات المعتمدة تُفوتر للعميل، وتكلفتها تُرحّل للمشروع من تبويب «ساعات العمل».', 'Approved hours are invoiced to the customer and their cost is posted to the project from the «Hours» tab.']] },
    { id: 'claims', go: '#/projects', t: ['المستخلصات وأوامر التغيير', 'Progress claims and change orders'], s: [
      ['اختر نوع العقد «مستخلصات»، وأدخل نسبة المحتجز واسترداد الدفعة المقدمة كما في عقدك، ثم بنود العقد.', 'Choose the «Claims» contract type, enter the retention and advance recovery rates from your contract, then the contract items.'],
      ['سجّل الدفعة المقدمة، ثم في كل مستخلص أدخل الكمية المنفذة حتى تاريخه واعتمده لتصدر فاتورته الضريبية.', 'Record the down payment, then in each claim enter the quantity done to date and approve it to issue its tax invoice.'],
      ['محتجز الضمان يبقى ضمن رصيد الفاتورة؛ عند تحصيله سجّل سند القبض ثم «استُلم المحتجز».', 'Retention stays in the invoice balance; when collected, record the receipt, then «Retention received».'],
      ['أمر التغيير يُرسل للعميل برابط خاص، وعند اعتماده تتحدث قيمة العقد ومدته وبنوده مع حفظ النسخة السابقة.', 'A change order goes to the customer by a private link; on approval the contract value, duration and items update and the old version is kept.']] },
    { id: 'accesslog', go: '#/accesslog', t: ['سجل الوصول', 'Access log'], s: [
      ['من «الإعدادات» افتح «سجل الوصول» لتعرف من فتح ملفات الموظفين والرواتب والمرفقات ومتى.', 'Open «Access log» under Settings to see who opened employee files, payroll and attachments, and when.'],
      ['صفِّ بالفترة أو النوع أو الاسم، ونزّل النتيجة CSV عند الحاجة.', 'Filter by period, type or name, and download the result as CSV when needed.']] },
    { id: 'zakatfac', go: '#/zakat', t: ['الزكاة والقروض وخطابات الضمان', 'Zakat, loans and guarantees'], s: [
      ['«الزكاة التقديرية» تحسب تقديرا من دفاترك وفق اللائحة، ويمكنك تعديل أي رقم. الإقرار الرسمي يُقدَّم في بوابة الهيئة.', '«Zakat estimate» works out a guide figure from your books under the regulation, and any number can be changed. The official return is filed on the ZATCA portal.'],
      ['«القروض وخطابات الضمان» تعرض جدول الأقساط، وغطاء كل خطاب، وتنبهك قبل الاستحقاق والانتهاء.', '«Loans and guarantees» shows the instalment schedule and each guarantee\'s margin, and alerts you before due and expiry dates.']] },
    { id: 'access', img: 'mklogin', go: '#/employees', t: ['أعطِ موظفيك الدخول', 'Give your employees access'], s: [
      ['من «الموظفون» افتح سجل الموظف واضغط «إنشاء دخول للموظف».', 'In «Employees» open the employee\'s record and press «Create employee login».'],
      ['يظهر رمز المنشأة والرقم الوظيفي وكلمة مرور مؤقتة، وأرسلها للموظف بزر الواتساب.', 'The company code, employee number and a temporary password appear; send them with the WhatsApp button.'],
      ['المدراء والمحاسبون يُدعَون بالبريد من «المستخدمون والدعوات».', 'Managers and accountants are invited by e-mail from «Users and invitations».']] },
    { id: 'cmpl', go: '#/compliance', t: ['تابع الامتثال من مكان واحد', 'Follow compliance in one place'], s: [
      ['افتح «الامتثال» أسبوعيا: البطاقات الحمراء عاجلة، والصفراء تحتاج متابعة.', 'Open «Compliance» weekly: red cards are urgent, amber need follow-up.'],
      ['اضغط أي بطاقة لتنتقل للصفحة التي تعالجها، مثل الوثائق أو المسير.', 'Click a card to go to the page that fixes it, like documents or payroll.']] },
    { id: 'onb', go: '#/onboarding', t: ['استقبال الموظف الجديد', 'Welcoming a new employee'], s: [
      ['من «التهيئة والترحيب» افتح الموظف الجديد وأكمل البنود الناقصة.', 'In «Onboarding» open the new employee and complete the missing items.'],
      ['أضف بنود منشأتك الخاصة مرة واحدة فتظهر لكل موظف جديد.', 'Add your own steps once and they show for every new hire.']] },
    { id: 'ann', go: '#/announcements', t: ['الإعلانات والاستبيانات', 'Announcements and surveys'], s: [
      ['انشر إعلانا من «الإعلانات الداخلية» بدل مجموعات الواتساب، وتابع من اطّلع.', 'Post from «Company announcements» instead of WhatsApp groups, and see who read it.'],
      ['لإيصاله خارج النظام اضغط «بريد وواتساب»: اكتب بريد المنشأة، وافتح رقم المنشأة في واتساب جهازك، ثم أرسل.', 'To reach staff outside the system press «E-mail & WhatsApp»: enter the company e-mail, open the company number in WhatsApp on your device, then send.'],
      ['أنشئ استبيان رضا الموظفين (eNPS) من «الاستبيانات» مرة كل ربع سنة.', 'Run an eNPS survey from «Surveys» once a quarter.']] },
    { id: 'careers', go: '#/recruit', t: ['صفحة الوظائف والمقابلات', 'Careers page and interviews'], s: [
      ['من «التوظيف» اضغط «صفحة الوظائف» وانسخ الرابط وانشره.', 'In «Recruitment» press «Careers page», copy the link and share it.'],
      ['فعّل «تظهر في صفحة الوظائف» للوظيفة، فيصل المتقدمون إلى قائمة المرشحين.', 'Turn on «Shows on the careers page» for the opening; applicants arrive in the candidates list.'],
      ['حدد موعد المقابلة ثم أرسل الدعوة الجاهزة بالواتساب أو البريد.', 'Set the interview time, then send the ready invitation by WhatsApp or e-mail.']] },
    { id: 'exp', go: '#/expensepolicy', t: ['سياسات المصروفات', 'Expense policies'], s: [
      ['حدد فئات المصروفات وحد كل فئة، واختر المنع أو التنبيه عند التجاوز.', 'Set expense categories and their limits, and choose to block or warn when exceeded.']] },
    { id: 'grvhr', go: '#/grievances', t: ['البلاغات السرية ومقابلات نهاية الخدمة', 'Confidential reports and exit interviews'], s: [
      ['«البلاغات السرية» تعرض بلاغات الموظفين إليك؛ البلاغ بدون اسم لا يظهر فيه اسم مقدمه. ردّك يصله في صفحته، وغيّر الحالة واكتب ما تم.', '«Confidential reports» lists employees\' reports to you; an anonymous one shows no name. Your reply reaches them; update the status and write what was done.'],
      ['«مقابلات نهاية الخدمة» تجمع إجابات المغادرين: أسباب المغادرة ومتوسط التقييم ومن يعود للعمل معكم.', '«Exit interviews» gathers leavers\' answers: reasons for leaving, average ratings and who would return.']] },
    { id: 'talent2', go: '#/jobdesc', t: ['الأوصاف الوظيفية والجدارات والإحلال', 'Job descriptions, competencies and succession'], s: [
      ['«مكتبة الوصف الوظيفي»: مهام كل وظيفة ومؤهلاتها، تربطها بالوظيفة الشاغرة وتطبعها مع العرض الوظيفي.', '«Job descriptions library»: each job\'s duties and qualifications, linked to the opening and printed with the offer.'],
      ['في ملف المرشح «بطاقة التقييم» لكل مقيّم، و«مقارنة المرشحين» ترتّبهم حسب متوسط التقييم.', 'In the candidate file each interviewer fills «Scorecard», and «Compare candidates» ranks them by average.'],
      ['«مصفوفة الجدارات» و«تخطيط الإحلال» للمناصب المهمة وخلفائها، و«عدالة الأجور» تقارن المتوسطات حسب الجنس والجنسية داخل الدرجة.', '«Competency matrix» and «Succession planning» for key positions and successors; «Pay equity» compares averages by gender and nationality inside each grade.']] },
    { id: 'sales2', go: '#/dunning', t: ['التحصيل والأسعار وخدمة العملاء', 'Collections, prices and customer service'], s: [
      ['«تحصيل المتأخرات»: العملاء المتأخرون مع رسالة تذكير جاهزة بالواتساب أو الإيميل ورابط كشف الحساب.', '«Overdue collections»: late customers with a ready WhatsApp or e-mail reminder and their statement link.'],
      ['«قوائم الأسعار»: سعر خاص لكل فئة عملاء وخصم الكمية، تُطبَّق تلقائيا في العروض والأوامر والفواتير.', '«Price lists»: a special price per customer group and quantity discounts, applied automatically in quotations, orders and invoices.'],
      ['في عرض السعر «رابط للعميل»: يقبله العميل من الرابط فيتحول إلى أمر بيع. و«تذاكر الدعم والصيانة» تُظهر إن كان المنتج في الضمان.', 'On a quotation «Customer link»: the customer accepts it from the link and it becomes a sales order. «Support and service tickets» show whether the product is under warranty.']] },
    { id: 'fin2', go: '#/payrun', t: ['السداد والضرائب والإيرادات المؤجلة', 'Payments, taxes and deferred revenue'], s: [
      ['«دفعة سداد جماعية»: اختر فواتير الموردين المستحقة وادفعها مرة واحدة، ونزّل ملف البنك.', '«Supplier payment run»: pick the supplier bills due, pay them at once and download the bank file.'],
      ['«سداد مع ضريبة الاستقطاع» في فاتورة المورد غير المقيم: تُحجز الضريبة حسب نوع الدفعة وتظهر في «ضريبة الاستقطاع» لسدادها للهيئة خلال أول 10 أيام من الشهر التالي.', '«Pay with withholding tax» on a non-resident\'s bill: the tax is held by payment type and listed in «Withholding tax» to pay ZATCA within the first 10 days of the next month.'],
      ['«الإيرادات المؤجلة» و«التكاليف المحمّلة» و«إعادة تقييم العملات» و«توزيع المصروفات» و«النسب المالية» في قسم المالية.', '«Deferred revenue», «Landed costs», «Currency revaluation», «Cost allocation» and «Financial ratios» are in the finance section.']] },
    { id: 'myrep', go: '#/myreports', t: ['التقارير المخصصة والربط مع الأنظمة', 'Custom reports and connecting systems'], s: [
      ['«تقاريري المخصصة»: اختر البيانات والأعمدة والفلاتر، واحفظ التقرير ونزّله Excel، ويمكن أن يصلك رابطه بالإيميل أسبوعيا أو شهريا.', '«My custom reports»: choose the data, columns and filters, save it and download Excel; its link can reach you by e-mail weekly or monthly.'],
      ['من «إعدادات المنشأة»: «الربط البرمجي (API)» للقراءة، و«إشعارات الأنظمة الأخرى (Webhooks)» تبلغ نظامك بالأحداث، و«نقاط الولاء» لنقطة البيع.', 'In «Company settings»: «API» for reading, «Webhooks» to tell your system about events, and «Loyalty points» for the point of sale.']] },
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
    { id: 'e5', q: ['متى يمكنك إلغاء طلبك؟', 'When can you cancel your request?'], a: [['في أي وقت حتى بعد اعتماده', 'Any time, even after approval'], ['ما دام لم يُعتمد بعد', 'As long as it isn\'t approved yet'], ['لا يمكن إلغاء أي طلب', 'No request can be cancelled']] },
    { id: 'e6', q: ['إذا صدر بحقك جزاء، خلال كم يوما يحق لك التظلم؟', 'If a penalty is issued against you, within how many days may you appeal?'], a: [['7 أيام', '7 days'], ['60 يوما', '60 days'], ['30 يوما من إبلاغك', '30 days from being notified']] },
    { id: 'e7', q: ['نسيت كلمة المرور، ماذا تفعل؟', 'You forgot your password. What do you do?'], a: [['أطلب من الموارد البشرية إعادة تعيينها', 'Ask HR to reset it'], ['أنشئ حسابا جديدا', 'Create a new account'], ['أدخل برقم موظف آخر', 'Sign in with another employee\'s number']] },
    { id: 'e8', q: ['تريد رفع شكوى بسرية دون أن يظهر اسمك، من أين؟', 'You want to raise a complaint confidentially without your name showing. Where?'], a: [['من «بلاغ سري» مع اختيار «بدون اسمي»', 'From «Confidential report», choosing «without my name»'], ['أكتبها في ملاحظات طلب إجازة', 'In the notes of a leave request'], ['في «الشكر والتقدير»', 'In «Recognition»']] },
    { id: 'e9', q: ['من يرى رقم جوالك في «دليل الموظفين»؟', 'Who sees your mobile number in «Staff directory»?'], a: [['جميع الزملاء دائما', 'All colleagues, always'], ['زملائي فقط إذا اخترت إظهاره من «بياناتي في الدليل»', 'My colleagues only if I choose to show it in «My directory details»'], ['المدير المباشر فقط', 'My direct manager only']] },
    { id: 'e10', q: ['كيف ترفق إيصال مطالبة المصروفات؟', 'How do you attach the receipt of an expense claim?'], a: [['أرسله للمالية بالواتساب', 'Send it to finance on WhatsApp'], ['أسلّمه ورقيا فقط', 'Hand in the paper only'], ['أرفقه في الطلب نفسه، أو أصوّره من الجوال بزر «تصوير بالكاميرا»', 'Attach it to the request itself, or snap it on the phone with «Take a photo»']] }],
  mgr: [
    { id: 'm1', q: ['أين تجد طلبات فريقك التي تنتظرك؟', 'Where do you find your team\'s requests waiting for you?'], a: [['في «طلباتي»', 'In «My requests»'], ['في «الاعتمادات»', 'In «Approvals»'], ['في «ملفي»', 'In «My profile»']] },
    { id: 'm2', q: ['عند رفض طلب موظف، ماذا تفعل؟', 'When you reject an employee\'s request, what do you do?'], a: [['أكتب سبب الرفض ليصل للموظف', 'Write the reason so the employee sees it'], ['أرفضه دون سبب', 'Reject it without a reason'], ['أتركه دون قرار', 'Leave it without a decision']] },
    { id: 'm3', q: ['قبل اعتماد إجازة جديدة، أين ترى من في إجازة من فريقك؟', 'Before approving new leave, where do you see who in your team is on leave?'], a: [['في «قسائم الراتب»', 'In «Payslips»'], ['في «السياسات واللوائح»', 'In «Policies»'], ['في «تقويم الإجازات»', 'In «Leave calendar»']] },
    { id: 'm4', q: ['في تقييم الأداء، كم يجب أن يكون مجموع أوزان الأهداف؟', 'In a performance review, what must the goals\' weights total?'], a: [['100%', '100%'], ['50%', '50%'], ['أي مجموع', 'Any total']] },
    { id: 'm5', q: ['عندك عشرة طلبات استئذان بانتظارك، ما أسرع طريقة؟', 'Ten permission requests are waiting for you. What is the quickest way?'], a: [['أفتح كل طلب وأعتمده وحده', 'Open each request and approve it alone'], ['أحددها ثم «اعتماد المحدد»', 'Tick them, then «Approve selected»'], ['أنتظر حتى تُعتمد تلقائيا', 'Wait until they are approved automatically']] },
    { id: 'm6', q: ['موظفك تنتهي فترة تجربته قريبا، ما دورك؟', 'Your employee\'s probation ends soon. What is your part?'], a: [['أقيّمه وأكتب توصيتي في «تقييم فترة التجربة»', 'Evaluate them and give my recommendation in «Probation evaluation»'], ['لا شيء، تنتهي تلقائيا', 'Nothing, it ends by itself'], ['أنهي خدمته من ملفه', 'End their service from their file']] }]
};
