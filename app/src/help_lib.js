'use strict';
/* ===== «مركز المساعدة»: a short explanation of each main page, in Arabic and English (the sheet picks the user's language
   itself, so this file is skipped by i18n/extract.py like forms_lib.js). Key = the page's route; the «؟» button in the top bar
   opens the entry of the page you are on, and #/help lists them all. Each entry: t = [ar, en] title, s = steps [[ar, en], …]. ===== */
const HELP = {
  '#/home': { t: ['الرئيسية', 'Home'], s: [
    ['تعرض لك ما ينتظرك: طلبات بانتظار اعتمادك، طلباتك، رصيد إجازتك، وأرقام منشأتك حسب صلاحيتك.', 'Shows what waits for you: approvals, your requests, your leave balance and your company\'s figures, by your role.'],
    ['إذا كانت منشأتك جديدة، اتبع «ابدأ هنا» لتجهيزها خطوة بخطوة.', 'If your company is new, follow «Start here» to set it up step by step.']] },
  '#/welcome': { t: ['ابدأ هنا', 'Start here'], s: [
    ['قائمة بخطوات تجهيز المنشأة، وكل خطوة تنتهي تتعلّم تلقائياً.', 'The setup steps of your company; each one is ticked by itself once done.'],
    ['ابدأ ببيانات المنشأة (الرقم الضريبي والعنوان الوطني)، ثم الموظفين، ثم دخول الفريق.', 'Start with the company data (VAT number and national address), then employees, then your team\'s access.']] },
  '#/employees': { t: ['الموظفون', 'Employees'], s: [
    ['أضف كل موظف براتبه الأساسي والبدلات ومديره المباشر وتاريخ مباشرته؛ منها تُحسب الرواتب والإجازات ونهاية الخدمة.', 'Add each employee with basic pay, allowances, direct manager and start date; payroll, leave and end-of-service are calculated from them.'],
    ['لإعطاء الموظف دخولاً: افتح سجله واضغط «إنشاء دخول للموظف»، ويدخل برمز المنشأة.', 'To give an employee access: open the record and press «Create employee login»; they sign in with the company code.'],
    ['تقدر تستورد الموظفين من ملف Excel بدل إدخالهم واحداً واحداً.', 'You can import employees from an Excel file instead of one by one.']] },
  '#/payroll': { t: ['مسير الرواتب', 'Payroll'], s: [
    ['جهّز مسير الشهر: يُحسب الراتب والإضافي والغياب والخصومات والسلف والتأمينات لكل موظف.', 'Prepare the month\'s run: pay, overtime, absence, deductions, advances and GOSI are calculated for each employee.'],
    ['راجع الأسطر وعدّل ما يلزم، ثم يعتمده المالك، فيُنشأ قيده في الحسابات تلقائياً.', 'Review and adjust the lines, then the owner approves it and its journal entry is posted by itself.'],
    ['بعد الاعتماد: نزّل ملف حماية الأجور لرفعه في مدد، وتظهر قسائم الراتب للموظفين.', 'After approval: download the wage protection file for Mudad; payslips appear for employees.']] },
  '#/requests': { t: ['طلباتي', 'My requests'], s: [
    ['قدّم طلب إجازة أو استئذان أو سلفة أو شهادة أو استقالة، ويمشي على مسار الاعتماد في منشأتك.', 'Request leave, a permission, an advance, a certificate or a resignation; it follows your company\'s approval route.'],
    ['النموذج يعرض رصيدك والحدود النظامية قبل الإرسال، وتتابع حالة كل طلب هنا.', 'The form shows your balance and the legal limits before you send, and you follow each request here.']] },
  '#/approvals': { t: ['الاعتمادات', 'Approvals'], s: [
    ['كل ما ينتظر قرارك: طلبات الموظفين، طلبات الشراء، والمسيرات.', 'Everything waiting for your decision: employee requests, purchase requests and payroll runs.'],
    ['افتح الطلب، راجع التفاصيل، ثم اعتمد أو ارفض مع ذكر السبب.', 'Open it, check the details, then approve or reject with a reason.']] },
  '#/att': { t: ['الحضور والانصراف', 'Attendance'], s: [
    ['يسجّل الموظف حضوره من جواله، ويظهر هنا الحاضر والمتأخر والغائب لكل يوم.', 'Employees check in from their phone; this page shows who is present, late or absent each day.'],
    ['حدّد الورديات وموقع العمل من الإعدادات، والغياب والتأخير يُحسبان في المسير.', 'Set shifts and the work location in settings; absence and lateness flow into payroll.']] },
  '#/docs': { t: ['المستندات والعقود', 'Documents & contracts'], s: [
    ['احفظ الإقامات والهويات والجوازات والعقود مع تواريخ انتهائها.', 'Keep iqamas, IDs, passports and contracts with their expiry dates.'],
    ['يُنبّهك النظام قبل الانتهاء بـ 30 يوماً، ويظهر العدد في الرئيسية والملخص الشهري.', 'You are warned 30 days before expiry; the count shows on the home page and in the monthly summary.']] },
  '#/clearance': { t: ['إخلاء الطرف', 'Clearance'], s: [
    ['عند انتهاء خدمة موظف: كل إدارة تؤكد إخلاء طرفه أو تذكر ما عليه من متعلقات.', 'When an employee leaves, each department confirms clearance or lists what is pending.'],
    ['بعد اكتمال الإخلاء تُصرف مستحقاته، وتقدر تطبع نموذج إخلاء الطرف من «النماذج».', 'Once cleared, final dues are paid; print the clearance form from «Forms».']] },
  '#/eos': { t: ['مكافأة نهاية الخدمة', 'End of service'], s: [
    ['تُحسب حسب نظام العمل من الأجر الأخير ومدة الخدمة وسبب انتهاء العقد.', 'Calculated under the Labour Law from the last wage, length of service and reason for leaving.']] },
  '#/nitaqat': { t: ['نطاقات والتوطين', 'Nitaqat'], s: [
    ['يحسب نسبة التوطين ويقدّر نطاق منشأتك، ويقول كم سعودياً تحتاج لتنتقل للنطاق الأعلى.', 'Works out your Saudization rate and estimated band, and how many Saudis you need to move up.'],
    ['هو تقدير للمساعدة؛ المرجع الرسمي هو منصة قوى.', 'It is an estimate to help you; the official figure is on Qiwa.']] },
  '#/penalties': { t: ['المخالفات والجزاءات', 'Penalties'], s: [
    ['يمشي على لائحة تنظيم العمل خطوة بخطوة: المخالفة، التحقيق، الجزاء، وحق الموظف في التظلم.', 'Follows the work regulations step by step: violation, investigation, penalty and the employee\'s right to appeal.']] },
  '#/forms': { t: ['النماذج', 'Forms'], s: [
    ['اختر القسم ثم النموذج، واختر الموظف أو العميل أو المورد؛ تتعبّى بياناته تلقائياً وتقدر تعدّلها.', 'Pick a department and a form, then the employee, customer or supplier; their data fills in and you can edit it.'],
    ['كل نموذج يُطبع على ترويسة منشأتك برقم مسلسل، والنماذج الإجرائية جدول بالعربي والإنجليزي.', 'Each form prints on your letterhead with a serial number; procedural forms are an Arabic + English table.'],
    ['«نموذج جديد» لإضافة نماذجك الخاصة: أي كلمة بين {f: و } تصير خانة تُعبّأ وقت الطباعة.', '«New form» adds your own: any word between {f: and } becomes a field to fill when printing.']] },
  '#/sales': { t: ['فواتير المبيعات', 'Sales invoices'], s: [
    ['أنشئ الفاتورة واختر العميل والأصناف؛ تُحسب الضريبة ويُنشأ القيد وينقص المخزون عند الترحيل.', 'Create the invoice, pick the customer and items; VAT, the journal entry and stock are handled on posting.'],
    ['العميل الذي له رقم ضريبي تصدر له فاتورة ضريبية، وغيره فاتورة مبسطة.', 'A customer with a VAT number gets a tax invoice; others get a simplified one.'],
    ['من صفحة الفاتورة: «تسجيل قبض» للتحصيل، «إشعار دائن» للمرتجع أو الخصم، «إشعار مدين» لمبلغ إضافي.', 'From the invoice: «Record receipt» to collect, «Credit note» for a return or discount, «Debit note» for an extra amount.'],
    ['إذا كانت منشأتك مربوطة بـ «فاتورة»، تُرسل الفاتورة لزاتكا تلقائياً وتظهر حالتها أعلاها.', 'If your company is linked to Fatoora, the invoice is sent to ZATCA automatically and its status shows at the top.']] },
  '#/pos': { t: ['نقطة البيع', 'Point of sale'], s: [
    ['اختر الأصناف بالضغط عليها، أو امسح الباركود بالقارئ أو بكاميرا الجوال، أو اكتب الاسم أو الرمز.', 'Pick items by tapping them, scan the barcode with a reader or the phone camera, or type the name or code.'],
    ['اختر طريقة الدفع (نقداً أو شبكة أو آجل) واضغط «إتمام البيع»: تُرحّل فاتورة مبسطة ويُسجّل القبض وينقص المخزون.', 'Choose the payment (cash, card or credit) and press «Complete sale»: a simplified invoice is posted, the receipt recorded and stock taken out.'],
    ['يُطبع إيصال صغير (80 مم) فيه رمز QR؛ وإذا كانت منشأتك مربوطة بـ «فاتورة» يُرسل لزاتكا تلقائياً.', 'A small 80 mm receipt prints with the QR code; if your company is linked to Fatoora it is sent to ZATCA automatically.'],
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
    ['ابدأ جرداً، وامسح الباركود بكاميرا الجوال أو أدخل الكميات؛ تظهر الفروقات وتُسوّى بقيد.', 'Start a count, scan barcodes with the phone camera or type quantities; differences show and are posted as an adjustment.']] },
  '#/reports': { t: ['التقارير', 'Reports'], s: [
    ['ميزان المراجعة، وقائمة الدخل، والمركز المالي، والتدفقات النقدية، وملخص ضريبة القيمة المضافة.', 'Trial balance, income statement, balance sheet, cash flow and the VAT summary.'],
    ['اختر الفترة، وتقدر تطبع أو تصدّر إلى Excel.', 'Pick the period; you can print or export to Excel.']] },
  '#/journal': { t: ['القيود اليومية', 'Journal'], s: [
    ['أغلب القيود تُنشأ تلقائياً من الفواتير والسندات والمسير؛ هنا تراها، وتضيف قيداً يدوياً عند الحاجة.', 'Most entries are posted by invoices, vouchers and payroll; see them here and add a manual entry when needed.']] },
  '#/projects': { t: ['المشاريع', 'Projects'], s: [
    ['أنشئ المشروع ومهامه، وسجّل ساعات العمل؛ تظهر التكلفة التقديرية والهامش.', 'Create the project and its tasks and log hours; estimated cost and margin appear.']] },
  '#/users': { t: ['المستخدمون والدعوات', 'Users & invitations'], s: [
    ['ادعُ المدراء والمحاسبين بأدوارهم؛ كل دور يرى ما يخصه فقط.', 'Invite managers and accountants with their roles; each role sees only what it needs.'],
    ['الموظف العادي يُعطى الدخول من سجله في «الموظفون».', 'An ordinary employee gets access from their record in «Employees».']] },
  '#/settings': { t: ['إعدادات المنشأة', 'Company settings'], s: [
    ['أكمل الرقم الضريبي والسجل التجاري والعنوان الوطني؛ تظهر في الفواتير والخطابات.', 'Fill in the VAT number, CR and national address; they appear on invoices and letters.'],
    ['ارفع الشعار، واضبط صلاحيات المحاسب وأمين المستودع، والملخص الشهري بالإيميل.', 'Upload your logo, set the accountant\'s and storekeeper\'s permissions and the monthly e-mail summary.'],
    ['«الربط مع فاتورة»: الصق رمز OTP من بوابة فاتورة لترسل فواتيرك لزاتكا تلقائياً (المرحلة الثانية).', '«Link with Fatoora»: paste the OTP from the Fatoora portal to send your invoices to ZATCA automatically (Phase 2).']] },
  '#/support': { t: ['الدعم الفني', 'Support'], s: [
    ['اكتب سؤالك أو المشكلة، ويصلك رد فريق وعد هنا وعلى بريدك.', 'Write your question or problem; the Waad team replies here and by e-mail.']] },
};
// the entry for a route: exact, else the longest key it starts with (#/sales/123 → #/sales)
const helpFor = h => { h = (h || '#/home').split('?')[0]; if (HELP[h]) return [h, HELP[h]]; const k = Object.keys(HELP).filter(x => h.startsWith(x + '/')).sort((a, b) => b.length - a.length)[0]; return k ? [k, HELP[k]] : null; };
const hT = p => LANG === 'en' && p[1] ? p[1] : p[0];
