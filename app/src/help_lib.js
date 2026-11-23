'use strict';
/* ===== «مركز المساعدة»: a short explanation of each main page, in Arabic and English (the sheet picks the user's language
   itself, so this file is skipped by i18n/extract.py like forms_lib.js). Key = the page's route; the «؟» button in the top bar
   opens the entry of the page you are on, and #/help lists them all. Each entry: t = [ar, en] title, s = steps [[ar, en], …]. ===== */
const HELP = {
  '#/home': { t: ['الرئيسية', 'Home'], s: [
    ['تعرض لك ما ينتظرك: طلبات بانتظار اعتمادك، طلباتك، رصيد إجازتك، وأرقام منشأتك حسب صلاحيتك.', 'Shows what waits for you: approvals, your requests, your leave balance and your company\'s figures, by your role.'],
    ['إذا كانت منشأتك جديدة، اتبع «ابدأ هنا» لتجهيزها خطوة بخطوة.', 'If your company is new, follow «Start here» to set it up step by step.']] },
  '#/welcome': { t: ['ابدأ هنا', 'Start here'], s: [
    ['قائمة بخطوات تجهيز المنشأة، وكل خطوة تنتهي تتعلّم تلقائيا.', 'The setup steps of your company; each one is ticked by itself once done.'],
    ['ابدأ ببيانات المنشأة (الرقم الضريبي والعنوان الوطني)، ثم الموظفين، ثم دخول الفريق.', 'Start with the company data (VAT number and national address), then employees, then your team\'s access.']] },
  '#/employees': { t: ['الموظفون', 'Employees'], s: [
    ['أضف كل موظف براتبه الأساسي والبدلات ومديره المباشر وتاريخ مباشرته؛ منها تُحسب الرواتب والإجازات ونهاية الخدمة.', 'Add each employee with basic pay, allowances, direct manager and start date; payroll, leave and end-of-service are calculated from them.'],
    ['لإعطاء الموظف دخولا: افتح سجله واضغط «إنشاء دخول للموظف»، ويدخل برمز المنشأة.', 'To give an employee access: open the record and press «Create employee login»; they sign in with the company code.'],
    ['تقدر تستورد الموظفين من ملف Excel بدل إدخالهم واحدا واحدا.', 'You can import employees from an Excel file instead of one by one.']] },
  '#/payroll': { t: ['مسير الرواتب', 'Payroll'], s: [
    ['جهّز مسير الشهر: يُحسب الراتب والإضافي والغياب والخصومات والسلف والتأمينات لكل موظف.', 'Prepare the month\'s run: pay, overtime, absence, deductions, advances and GOSI are calculated for each employee.'],
    ['راجع الأسطر وعدّل ما يلزم، ثم يعتمده مدير الموارد البشرية، ثم المالية، ثم المدير العام اعتمادا نهائيا فيُنشأ قيده في الحسابات تلقائيا. يمكن إرجاعه للتعديل في أي مرحلة، وأي تعديل يلغي الاعتمادات السابقة.', 'Review and adjust the lines; then the HR manager approves it, then finance, then the general manager gives the final approval and its journal entry is posted by itself. It can be returned for correction at any step, and any change clears earlier approvals.'],
    ['«طباعة المسير» تطبع كشف الموظفين بالإجماليات وأسماء المعتمدين وتواريخهم وخانات التوقيع.', '«Print payroll» prints the employee sheet with totals, the approvers\' names and dates, and signature lines.'],
    ['بعد الاعتماد: نزّل ملف حماية الأجور لرفعه في مدد، وتظهر قسائم الراتب للموظفين.', 'After approval: download the wage protection file for Mudad; payslips appear for employees.']] },
  '#/requests': { t: ['طلباتي', 'My requests'], s: [
    ['قدّم طلب إجازة أو استئذان أو سلفة أو شهادة أو استقالة، ويمشي على مسار الاعتماد في منشأتك.', 'Request leave, a permission, an advance, a certificate or a resignation; it follows your company\'s approval route.'],
    ['النموذج يعرض رصيدك والحدود النظامية قبل الإرسال، وتتابع حالة كل طلب هنا.', 'The form shows your balance and the legal limits before you send, and you follow each request here.']] },
  '#/approvals': { t: ['الاعتمادات', 'Approvals'], s: [
    ['كل ما ينتظر قرارك: طلبات الموظفين، طلبات الشراء، والمسيرات.', 'Everything waiting for your decision: employee requests, purchase requests and payroll runs.'],
    ['افتح الطلب، راجع التفاصيل، ثم اعتمد أو ارفض مع ذكر السبب.', 'Open it, check the details, then approve or reject with a reason.']] },
  '#/att': { t: ['الحضور والانصراف', 'Attendance'], s: [
    ['يسجّل الموظف حضوره من جواله أو من الموقع دون جهاز بصمة، ويظهر هنا الحاضر والمتأخر والغائب لكل يوم.', 'Employees check in from their phone or the website with no fingerprint device; this page shows who is present, late or absent each day.'],
    ['جدول الورديات يعرض كل قسم في جدول مستقل، ومن زر «تعيين جدول للقسم» تعيّن ورديات موظفيه.', 'The shift roster shows each department in its own table; «Set department roster» assigns its employees.'],
    ['من «الإعدادات» ← «الورديات» ← «+ وردية» اختر وردية جاهزة فتظهر تفاصيلها وأوقات رمضان، ثم احفظ.', 'From «Settings» → «Shifts» → «+ Shift» choose a ready-made shift; its details and Ramadan times appear, then save.'],
    ['لموظفي المكاتب أو العمل عن بعد: اختر في ملف الموظف «من أي مكان بدون تحديد الموقع»، ويبقى التحقق من الموقع لغيرهم.', 'For desk or remote staff: choose «From any place, without location» in the employee file; the location check stays on for everyone else.'],
    ['حدّد الورديات وموقع العمل من الإعدادات، والغياب والتأخير يُحسبان في المسير.', 'Set shifts and the work location in settings; absence and lateness flow into payroll.']] },
  '#/docs': { t: ['المستندات والعقود', 'Documents & contracts'], s: [
    ['احفظ الإقامات والهويات والجوازات والعقود مع تواريخ انتهائها.', 'Keep iqamas, IDs, passports and contracts with their expiry dates.'],
    ['يُنبّهك النظام قبل الانتهاء بـ 30 يوما، ويظهر العدد في الرئيسية والملخص الشهري.', 'You are warned 30 days before expiry; the count shows on the home page and in the monthly summary.']] },
  '#/clearance': { t: ['إخلاء الطرف', 'Clearance'], s: [
    ['عند انتهاء خدمة موظف: كل إدارة تؤكد إخلاء طرفه أو تذكر ما عليه من متعلقات.', 'When an employee leaves, each department confirms clearance or lists what is pending.'],
    ['بعد اكتمال الإخلاء تُصرف مستحقاته، وتقدر تطبع نموذج إخلاء الطرف من «النماذج».', 'Once cleared, final dues are paid; print the clearance form from «Forms».']] },
  '#/eos': { t: ['مكافأة نهاية الخدمة', 'End of service'], s: [
    ['تُحسب حسب نظام العمل من الأجر الأخير ومدة الخدمة وسبب انتهاء العقد.', 'Calculated under the Labour Law from the last wage, length of service and reason for leaving.']] },
  '#/nitaqat': { t: ['نطاقات والتوطين', 'Nitaqat'], s: [
    ['يحسب نسبة التوطين ويقدّر نطاق منشأتك، ويقول كم سعوديا تحتاج لتنتقل للنطاق الأعلى.', 'Works out your Saudization rate and estimated band, and how many Saudis you need to move up.'],
    ['هو تقدير للمساعدة؛ المرجع الرسمي هو منصة قوى.', 'It is an estimate to help you; the official figure is on Qiwa.']] },
  '#/penalties': { t: ['المخالفات والجزاءات', 'Penalties'], s: [
    ['يمشي على لائحة تنظيم العمل خطوة بخطوة: المخالفة، التحقيق، الجزاء، وحق الموظف في التظلم.', 'Follows the work regulations step by step: violation, investigation, penalty and the employee\'s right to appeal.']] },
  '#/forms': { t: ['النماذج', 'Forms'], s: [
    ['اختر القسم ثم النموذج، واختر الموظف أو العميل أو المورد؛ تتعبّى بياناته تلقائيا وتقدر تعدّلها.', 'Pick a department and a form, then the employee, customer or supplier; their data fills in and you can edit it.'],
    ['كل نموذج يُطبع على ترويسة منشأتك برقم مسلسل، والنماذج الإجرائية جدول بالعربي والإنجليزي.', 'Each form prints on your letterhead with a serial number; procedural forms are an Arabic + English table.'],
    ['«نموذج جديد» لإضافة نماذجك الخاصة: أي كلمة بين {f: و } تصير خانة تُعبّأ وقت الطباعة.', '«New form» adds your own: any word between {f: and } becomes a field to fill when printing.']] },
  '#/sales': { t: ['فواتير المبيعات', 'Sales invoices'], s: [
    ['أنشئ الفاتورة واختر العميل والأصناف؛ تُحسب الضريبة ويُنشأ القيد وينقص المخزون عند الترحيل.', 'Create the invoice, pick the customer and items; VAT, the journal entry and stock are handled on posting.'],
    ['العميل الذي له رقم ضريبي تصدر له فاتورة ضريبية، وغيره فاتورة مبسطة.', 'A customer with a VAT number gets a tax invoice; others get a simplified one.'],
    ['من صفحة الفاتورة: «تسجيل قبض» للتحصيل، «إشعار دائن» للمرتجع أو الخصم، «إشعار مدين» لمبلغ إضافي.', 'From the invoice: «Record receipt» to collect, «Credit note» for a return or discount, «Debit note» for an extra amount.'],
    ['إذا كانت منشأتك مربوطة بـ «فاتورة»، تُرسل الفاتورة لزاتكا تلقائيا وتظهر حالتها أعلاها.', 'If your company is linked to Fatoora, the invoice is sent to ZATCA automatically and its status shows at the top.']] },
  '#/pos': { t: ['نقطة البيع', 'Point of sale'], s: [
    ['اختر الأصناف بالضغط عليها، أو امسح الباركود بالقارئ أو بكاميرا الجوال، أو اكتب الاسم أو الرمز.', 'Pick items by tapping them, scan the barcode with a reader or the phone camera, or type the name or code.'],
    ['اختر طريقة الدفع (نقدا أو شبكة أو آجل) واضغط «إتمام البيع»: تُرحّل فاتورة مبسطة ويُسجّل القبض وينقص المخزون.', 'Choose the payment (cash, card or credit) and press «Complete sale»: a simplified invoice is posted, the receipt recorded and stock taken out.'],
    ['يُطبع إيصال صغير (80 مم) فيه رمز QR؛ وإذا كانت منشأتك مربوطة بـ «فاتورة» يُرسل لزاتكا تلقائيا.', 'A small 80 mm receipt prints with the QR code; if your company is linked to Fatoora it is sent to ZATCA automatically.'],
    ['الأصناف ذات الأرقام التسلسلية تُباع من «فواتير المبيعات» لا من نقطة البيع.', 'Serial-tracked items are sold from «Sales invoices», not from the point of sale.']] },
  '#/purchases': { t: ['فواتير المشتريات', 'Purchase bills'], s: [
    ['سجّل فاتورة المورد بالأصناف أو الحسابات؛ تُضاف الكميات للمخزون ويُنشأ القيد.', 'Record the supplier\'s bill by items or accounts; stock goes up and the journal entry is posted.'],
    ['سجّل السداد من «سندات القبض والصرف» أو من صفحة الفاتورة.', 'Record payment from «Receipts & payments» or from the bill.']] },
  '#/payments': { t: ['سندات القبض والصرف', 'Receipts & payments'], s: [
    ['سند قبض لما تستلمه من العملاء، وسند صرف لما تدفعه للموردين أو للمصروفات.', 'A receipt for what customers pay you, a payment for suppliers or expenses.']] },
  '#/items': { t: ['الأصناف والمخزون', 'Items & stock'], s: [
    ['أضف الأصناف بالسعر ونسبة الضريبة؛ الصنف المخزني تُتابَع كميته وتكلفته، والخدمة لا.', 'Add items with price and VAT rate; stock items track quantity and cost, services do not.'],
    ['الصنف بضريبة 0% يحتاج سبب الصفر أو الإعفاء (زاتكا تطلبه).', 'A 0% item needs its zero-rate or exemption reason (ZATCA requires it).']] },
  '#/counts': { t: ['الجرد', 'Stock counts'], s: [
    ['ابدأ جردا، وامسح الباركود بكاميرا الجوال أو أدخل الكميات؛ تظهر الفروقات وتُسوّى بقيد.', 'Start a count, scan barcodes with the phone camera or type quantities; differences show and are posted as an adjustment.']] },
  '#/reports': { t: ['التقارير', 'Reports'], s: [
    ['ميزان المراجعة، وقائمة الدخل، والمركز المالي، والتدفقات النقدية، وملخص ضريبة القيمة المضافة.', 'Trial balance, income statement, balance sheet, cash flow and the VAT summary.'],
    ['اختر الفترة، وتقدر تطبع أو تصدّر إلى Excel.', 'Pick the period; you can print or export to Excel.']] },
  '#/journal': { t: ['القيود اليومية', 'Journal'], s: [
    ['أغلب القيود تُنشأ تلقائيا من الفواتير والسندات والمسير؛ هنا تراها، وتضيف قيدا يدويا عند الحاجة.', 'Most entries are posted by invoices, vouchers and payroll; see them here and add a manual entry when needed.']] },
  '#/projects': { t: ['المشاريع', 'Projects'], s: [
    ['أنشئ المشروع بقيمة عقده وموازنته ومديره؛ يُنشأ له مركز تكلفة تلقائيا.', 'Create the project with its contract value, budget and manager; it gets a cost center automatically.'],
    ['التبويبات: المراحل والمهام، والجدول الزمني، والساعات، والفريق، وأوامر التغيير، والمخاطر، والمستخلصات لعقود المقاولات.', 'Tabs: milestones and tasks, timeline, hours, team, change orders, risks, and claims for contracting jobs.'],
    ['الربحية تأتي من القيود على مركز تكلفة المشروع، والهامش المتوقع = قيمة العقد − التكلفة ÷ نسبة الإنجاز.', 'Profitability comes from entries on the project\'s cost center; expected margin = contract value − cost ÷ % complete.']] },
  '#/accesslog': { t: ['سجل الوصول', 'Access log'], s: [
    ['يعرض من فتح ملفات الموظفين والرواتب وملفات البنك والتقارير والمرفقات، ومتى. لا يمكن تعديله أو حذفه.', 'Shows who opened employee files, payroll, bank files, reports and attachments, and when. It cannot be edited or deleted.'],
    ['يراه مالك المنشأة ومدير النظام، ويدخل في تصدير بيانات المنشأة.', 'The owner and administrators can see it, and it is part of the company data export.']] },
  '#/mytime': { t: ['ساعات عملي', 'My hours'], s: [
    ['سجّل ساعاتك ليوم أو لأسبوع كامل، وتذهب لمدير المشروع للاعتماد.', 'Log your hours for a day or a whole week; they go to the project manager for approval.'],
    ['إذا كنت مدير مشروع تظهر هنا ساعات فريقك بانتظار اعتمادك.', 'If you manage a project, your team\'s hours waiting for approval appear here.']] },
  '#/resources': { t: ['إشغال الفريق', 'Team allocation'], s: [
    ['يعرض نسبة تفرغ كل موظف على المشاريع الجارية أسبوعا بأسبوع، من نسب «الفريق» في كل مشروع. الأحمر يعني أكثر من 100%.', 'Shows each employee\'s allocation on active projects week by week, from each project\'s «Team» tab. Red means over 100%.']] },
  '#/zakat': { t: ['الزكاة التقديرية', 'Zakat estimate'], s: [
    ['الأرقام من دفاترك ويمكن تعديلها، وكل خانة مكتوب بجانبها مادتها في اللائحة.', 'The figures come from your books and can be changed; each one shows its article in the regulation.'],
    ['النتيجة استرشادية؛ راجعها مع محاسبك، والإقرار الرسمي في بوابة الهيئة.', 'The result is a guide; review it with your accountant. The official return is filed on the ZATCA portal.']] },
  '#/facilities': { t: ['القروض وخطابات الضمان', 'Loans and guarantees'], s: [
    ['سجّل القرض فيظهر جدول أقساطه، وكل قسط يُقيَّد عند سداده بأصله وربحه.', 'Record a loan to get its schedule; each instalment is posted when paid, split into principal and profit.'],
    ['خطاب الضمان يُسجَّل بغطائه وعمولته، ويمكن ربطه بمشروع، وتمديده أو الإفراج عنه.', 'A guarantee is recorded with its margin and fee, can be linked to a project, and can be extended or released.']] },
  '#/users': { t: ['المستخدمون والدعوات', 'Users & invitations'], s: [
    ['ادعُ المدراء والمحاسبين بأدوارهم؛ كل دور يرى ما يخصه فقط.', 'Invite managers and accountants with their roles; each role sees only what it needs.'],
    ['الموظف العادي يُعطى الدخول من سجله في «الموظفون».', 'An ordinary employee gets access from their record in «Employees».']] },
  '#/settings': { t: ['إعدادات المنشأة', 'Company settings'], s: [
    ['أكمل الرقم الضريبي والسجل التجاري والعنوان الوطني؛ تظهر في الفواتير والخطابات.', 'Fill in the VAT number, CR and national address; they appear on invoices and letters.'],
    ['ارفع الشعار، واضبط صلاحيات المحاسب وأمين المستودع، والملخص الشهري بالإيميل.', 'Upload your logo, set the accountant\'s and storekeeper\'s permissions and the monthly e-mail summary.'],
    ['«الربط مع فاتورة»: الصق رمز OTP من بوابة فاتورة لترسل فواتيرك لزاتكا تلقائيا (المرحلة الثانية).', '«Link with Fatoora»: paste the OTP from the Fatoora portal to send your invoices to ZATCA automatically (Phase 2).']] },
  '#/compliance': { t: ['الامتثال', 'Compliance'], s: [
    ['تجمع ما يلزم منشأتك نظاما في بطاقات: حماية الأجور، والتأمينات، والوثائق، والعقود وفترات التجربة، والآيبان، ونطاقات، ومستندات المنشأة، والتأمين الطبي.', 'Gathers what your company must do by law in cards: wage protection, GOSI, documents, contracts and probation, IBANs, Nitaqat, company documents and medical insurance.'],
    ['الأحمر عاجل، والأصفر يحتاج متابعة. اضغط البطاقة لتفتح الصفحة التي تعالجها.', 'Red is urgent and amber needs follow-up. Click a card to open the page that fixes it.'],
    ['وعد لا يتصل بمنصات مدد أو التأمينات أو قوى؛ يجهّز الملفات والتنبيهات وأنت ترفعها.', 'Waad does not connect to Mudad, GOSI or Qiwa; it prepares the files and alerts and you upload them.']] },
  '#/onboarding': { t: ['التهيئة والترحيب', 'Onboarding'], s: [
    ['قائمة مهام لكل موظف باشر خلال آخر 120 يوما، مع نسبة الإنجاز.', 'A checklist for each employee who started in the last 120 days, with progress.'],
    ['بنود مثل العقد والآيبان والإقامة والتأمين الطبي تكتمل تلقائيا عند إدخالها، والباقي كالتسجيل في التأمينات وتوثيق العقد في قوى تعلّمه أنت.', 'Items such as the contract, IBAN, iqama and medical insurance complete themselves when entered; you tick the rest, like GOSI registration and documenting the contract in Qiwa.'],
    ['أضف بنود منشأتك الخاصة من «بنود المنشأة الخاصة».', 'Add your own steps from «Company\'s own steps».']] },
  '#/approvals': { t: ['الاعتمادات', 'Approvals'], s: [
    ['هنا الطلبات التي تنتظر قرارك. عند غيابك اضغط «تفويض الاعتمادات» واختر زميلا ومدة، فيعتمد بدلا منك ويُسجَّل باسمه.', 'Requests waiting for your decision. Before an absence press «Delegate approvals», choose a colleague and a period; they approve in your place and the trail shows their name.']] },
  '#/agreements': { t: ['العقود والاتفاقيات', 'Contracts and agreements'], s: [
    ['سجّل عقود الخدمات والصيانة والإيجار والتوريد مع العملاء والموردين: المدة والقيمة والفوترة والمسؤول، وأرفق النسخة الموقعة.', 'Record service, maintenance, lease and supply contracts with customers and suppliers: term, value, billing and owner, and attach the signed copy.'],
    ['يصلك تنبيه في الجرس قبل انتهاء العقد بالمدة التي تحددها، وتجدده بضغطة لمدة مماثلة.', 'The bell warns you before a contract ends by the period you set, and you renew it with one click for the same term.'],
    ['من عقد البيع أنشئ فاتورة متكررة بقيمة كل فترة، وتصدرها من «الفواتير المتكررة» عند موعدها.', 'From a sales contract create a recurring invoice for each period, and issue it from «Recurring invoices» when due.']] },
  '#/announcements': { t: ['الإعلانات الداخلية', 'Company announcements'], s: [
    ['انشر إعلانا لكل الموظفين أو لقسم واحد، فيظهر في الصفحة الرئيسية لكل منهم ويصل على أجهزتهم.', 'Post to all staff or one department; it shows on each home page and reaches their devices.'],
    ['ثبّت المهم أعلى الرئيسية، وحدد تاريخا يختفي بعده إن أردت.', 'Pin the important ones to the top of home, and set a date to hide them if you like.'],
    ['بعد النشر، أو من زر «بريد وواتساب»، تُفتح الرسالة جاهزة من بريدك وواتساب جهازك للموظفين المعنيين، وتضغط أنت «إرسال».', 'After posting, or from «E-mail & WhatsApp», the message opens ready in your own mailbox and WhatsApp for the staff concerned, and you press send.'],
    ['عمود «اطّلع عليه» يبين كم موظفا ضغط «تم الاطلاع».', 'The «Read by» column shows how many pressed «Got it».']] },
  '#/surveys': { t: ['الاستبيانات', 'Surveys'], s: [
    ['الموظف يرى هنا الاستبيانات التي تنتظر رأيه، ويجيب مرة واحدة.', 'Employees see the surveys waiting for them here and answer once.'],
    ['الموارد البشرية تنشئ استبيانا من قالب جاهز: رضا الموظفين (eNPS)، أو الانضمام، أو المغادرة، أو أسئلة خاصة.', 'HR creates a survey from a template: eNPS, onboarding, exit, or custom questions.'],
    ['الاستبيان المجهول لا يحفظ اسم من أجاب، ولا تظهر نتائجه قبل 3 إجابات.', 'An anonymous survey keeps no names and shows no results before 3 answers.']] },
  '#/workforce': { t: ['خطة القوى العاملة', 'Workforce plan'], s: [
    ['مدير القسم يطلب وظيفة بعددها وتكلفتها الشهرية وشهر بدايتها.', 'A department manager requests a position with headcount, monthly cost and start month.'],
    ['تعتمدها الموارد البشرية ثم المالية (أو المالك إن لم يوجد مسؤول مالي).', 'HR approves it, then finance (or the owner when there is no finance user).'],
    ['بعد الاعتماد تفتحها الموارد البشرية وظيفة شاغرة في «التوظيف» بضغطة.', 'Once approved, HR turns it into a job opening in «Recruitment» with one click.']] },
  '#/expensepolicy': { t: ['سياسات المصروفات', 'Expense policies'], s: [
    ['أضف فئات المصروفات (وقود، ضيافة، تنقلات…) مع حد للمطالبة الواحدة وحد شهري للموظف.', 'Add expense categories (fuel, hospitality, transport…) with a per-claim limit and a monthly limit per employee.'],
    ['اختر لكل فئة: منع المطالبة إذا تجاوزت الحد، أو تنبيه المعتمد فقط.', 'For each category choose: block claims over the limit, or just warn the approver.'],
    ['يرى المعتمد تنبيها إذا تكررت المطالبة بنفس المبلغ أو أُرفق الإيصال نفسه في مطالبة أخرى.', 'The approver is warned of a repeated amount or the same receipt on another claim.']] },
  '#/sign': { t: ['توقيعاتي', 'My signatures'], s: [
    ['المستندات التي تنتظر توقيعك: العقد، والعهدة، والجزاء، والمخالصة.', 'Documents waiting for your signature: contract, custody, penalty and settlement.'],
    ['اقرأ النص ثم وقّع بإصبعك أو بالفأرة، فيُحفظ التوقيع مع وقته.', 'Read the text, then sign with your finger or mouse; the signature is saved with its time.']] },
  '#/companydocs': { t: ['مستندات المنشأة والسيارات', 'Company documents and vehicles'], s: [
    ['سجّل السجل التجاري والرخص والشهادات والسيارات بتواريخ انتهائها، وأرفق صورها.', 'Record the CR, licences, certificates and vehicles with their expiry dates and attach copies.'],
    ['تظهر التنبيهات في الجرس وصفحة الامتثال قبل الانتهاء بثلاثين يوما.', 'Alerts appear in the bell and on the compliance page 30 days before expiry.']] },
  '#/recurring': { t: ['الفواتير المتكررة', 'Recurring invoices'], s: [
    ['فاتورة تتكرر لعميل كل شهر أو أكثر، كالإيجار أو الصيانة.', 'An invoice that repeats for a customer every month or more, like rent or maintenance.'],
    ['عند موعدها تصدرها بضغطة وتُرحّل كأي فاتورة.', 'When due, issue it with one click and it posts like any invoice.']] },
  '#/customfields': { t: ['الحقول المخصصة', 'Custom fields'], s: [
    ['أضف حقولا خاصة بمنشأتك لملف الموظف أو بطاقة العميل والمورد أو الصنف.', 'Add your own fields to the employee file, the customer/supplier card or the item.'],
    ['تظهر الحقول في النماذج وتُحفظ مع السجل.', 'They appear in the forms and are saved with the record.']] },
  '#/reviews': { t: ['تقييم الأداء', 'Performance reviews'], s: [
    ['تفتح الموارد البشرية دورة تقييم، فيقيّم كل مدير فريقه على أهداف بأوزان مجموعها 100%.', 'HR opens a review cycle; each manager rates the team on goals weighted to 100%.'],
    ['من نافذة التقييم اطلب «تقييم 360» ليقيّم الموظف نفسه ويقيّمه زملاء تختارهم، وتظهر المتوسطات بدون أسماء.', 'From the review, request «360 feedback» so the employee rates themselves and chosen colleagues give views; averages show without names.'],
    ['إذا طُلب رأيك في تقييم 360 تجده أعلى هذه الصفحة.', 'If your opinion is requested for 360 feedback, it is at the top of this page.']] },
  '#/recruit': { t: ['التوظيف', 'Recruitment'], s: [
    ['أضف الوظيفة الشاغرة، وفعّل «تظهر في صفحة الوظائف» لتقبل التقديم عليها من الرابط العام.', 'Add the opening and turn on «Shows on the careers page» to accept applications through the public link.'],
    ['من «صفحة الوظائف» انسخ رابط منشأتك وانشره، فيصل المتقدمون بسيرهم الذاتية إلى قائمة المرشحين.', 'Copy your company\'s link from «Careers page» and share it; applicants arrive with their CVs in the candidates list.'],
    ['حدد موعد المقابلة ورابطها أو مكانها، ثم أرسل «رسالة دعوة المقابلة» بالواتساب أو البريد.', 'Set the interview time and link or place, then send the «interview invitation» by WhatsApp or e-mail.']] },
  '#/permissions': { t: ['الصلاحيات', 'Permissions'], s: [
    ['كل صلاحيات المنشأة في صفحة واحدة: صلاحيات كل شخص، وصلاحيات الأدوار في كل قسم، وجدول بما يراه كل دور.', 'Every permission in one page: each person\'s permissions, role permissions per department, and a map of what each role sees.'],
    ['«تعديل الصلاحيات» يحدد أدوار الشخص وصلاحياته الخاصة، والخاصة تحل محل صلاحيات دوره في المالية والمخزون.', '«Edit permissions» sets a person\'s roles and personal permissions; personal ones replace the role\'s finance and inventory permissions.'],
    ['المالك له كل الصلاحيات دائما، وكل تغيير يُحفظ في سجل التدقيق.', 'The owner always has every permission, and every change is kept in the audit log.']] },
  '#/support': { t: ['الدعم الفني', 'Support'], s: [
    ['اكتب سؤالك أو المشكلة، ويصلك رد فريق وعد هنا وعلى بريدك.', 'Write your question or problem; the Waad team replies here and by e-mail.']] },
};
// the entry for a route: exact, else the longest key it starts with (#/sales/123 → #/sales)
const helpFor = h => { h = (h || '#/home').split('?')[0]; if (HELP[h]) return [h, HELP[h]]; const k = Object.keys(HELP).filter(x => h.startsWith(x + '/')).sort((a, b) => b.length - a.length)[0]; return k ? [k, HELP[k]] : null; };
const hT = p => LANG === 'en' && p[1] ? p[1] : p[0];
