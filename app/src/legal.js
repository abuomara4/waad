'use strict';
/* Privacy policy and terms of use. Each text exists in Arabic and English and is shown in the interface language
   (data-nt: not passed through the UI translator). Bump TERMS_VERSION when either text changes materially. */
const TERMS_VERSION = '2026-10';
const LEGAL_CONTACT = '';   // privacy contact e-mail; shown when set
const LEGAL = {
  privacy: {
    ar: { t: 'سياسة الخصوصية', d: 'آخر تحديث: 29 أكتوبر 2026 — الإصدار 2026-10', s: [
      ['من نحن', 'وعد نظام سحابي لإدارة الموارد البشرية والمالية والمبيعات والمشتريات والمخزون للمنشآت. هذه نسخة تجريبية مقدّمة للتقييم.'],
      ['دور كل طرف', 'المنشأة التي تسجّل في وعد هي «جهة التحكم» في البيانات التي تُدخلها عن موظفيها وعملائها ومورديها، ووعد «جهة معالجة» تحفظ هذه البيانات وتعالجها نيابة عنها ولغرض تشغيل الخدمة فقط، وفق نظام حماية البيانات الشخصية في المملكة العربية السعودية ولوائحه.'],
      ['البيانات التي نجمعها', 'بيانات الحساب: البريد الإلكتروني وكلمة المرور (تُحفظ مشفّرة لدى مزوّد الدخول ولا نراها). بيانات المنشأة وما يُدخله مستخدموها: الموظفون والرواتب والحضور والفواتير والعملاء والموردون وغيرها. بيانات تقنية محدودة: رسائل الأخطاء التقنية دون محتوى السجلات، وعنوان IP عند إدخال رمز منشأة خاطئ (لمنع التخمين، ويُحذف بعد يوم).'],
      ['لماذا نستخدمها', 'لتشغيل الخدمة وحساب الرواتب والفواتير والتقارير التي تطلبها المنشأة، وحماية الحسابات من الدخول غير المصرّح به، وإصلاح الأعطال. لا نبيع البيانات، ولا نستخدمها للإعلانات، ولا نشاركها مع منشأة أخرى.'],
      ['من يطّلع عليها', 'مستخدمو المنشأة حسب الصلاحيات التي يحددها مالكها، ولا ترى أي منشأة بيانات منشأة أخرى. إدارة المنصة لا تطّلع على بيانات المنشآت، ولا تدخل إليها إلا بإذن مؤقت من مالك المنشأة لغرض الدعم.'],
      ['أين تُحفظ', 'تُحفظ البيانات لدى مزوّد البنية السحابية Supabase على خوادم في طوكيو باليابان. هذا نقل للبيانات خارج المملكة، ولذلك لا تُدخل في النسخة التجريبية بيانات شخصية حقيقية. سننقل الحفظ إلى موقع يحقق متطلبات النظام قبل الإطلاق التجاري.'],
      ['مدة الحفظ', 'تبقى البيانات ما دام حساب المنشأة قائماً. عند طلب حذف الحساب تُحذف بياناته، ويبقى سجل التدقيق والقيود المحاسبية المدة التي تُلزم بها الأنظمة.'],
      ['الحماية', 'الاتصال مشفّر، وكل منشأة معزولة في قاعدة البيانات بقواعد وصول، وكل تعديل مسجّل في سجل تدقيق لا يُعدّل. يمكن تفعيل التحقق بخطوتين لكل حساب.'],
      ['حقوقك', 'لصاحب البيانات حق العلم بمعالجتها، والوصول إليها، وطلب تصحيحها أو إتلافها، والرجوع عن موافقته. يُقدَّم الطلب أولاً إلى المنشأة التي يعمل لديها أو يتعامل معها، وسنساعدها في تنفيذه.'],
      ['التغييرات', 'إذا تغيّرت هذه السياسة تغييراً جوهرياً سنطلب موافقتك على الإصدار الجديد عند الدخول.']] },
    en: { t: 'Privacy Policy', d: 'Last updated: 29 October 2026 — version 2026-10', s: [
      ['Who we are', 'Waad is a cloud system for HR, finance, sales, purchasing and inventory. This is a trial version offered for evaluation.'],
      ['Roles', 'The company that signs up is the "controller" of the data it enters about its employees, customers and suppliers. Waad is a "processor" that stores and processes that data on the company\'s behalf, only to run the service, under the Saudi Personal Data Protection Law and its regulations.'],
      ['Data we collect', 'Account data: e-mail and password (stored hashed by the sign-in provider; we never see it). Company data entered by its users: employees, payroll, attendance, invoices, customers, suppliers and so on. Limited technical data: technical error messages without record contents, and the IP address when a wrong company code is entered (to prevent guessing; deleted after one day).'],
      ['Why we use it', 'To run the service and produce the payroll, invoices and reports the company asks for, to protect accounts from unauthorised access, and to fix faults. We do not sell data, use it for advertising, or share it with any other company.'],
      ['Who can see it', 'The company\'s own users, according to the permissions its owner sets. No company can see another company\'s data. The platform administrators do not view company data and only access it with the owner\'s temporary permission for support.'],
      ['Where it is stored', 'Data is stored with the cloud provider Supabase on servers in Tokyo, Japan. This is a transfer outside the Kingdom, so do not enter real personal data in the trial. We will move storage to a location that meets the law before the commercial launch.'],
      ['Retention', 'Data is kept while the company account exists. When deletion of the account is requested its data is deleted; the audit log and accounting entries are kept for the period the law requires.'],
      ['Security', 'Connections are encrypted, each company is isolated in the database by access rules, and every change is recorded in a tamper-proof audit log. Two-step verification can be enabled on every account.'],
      ['Your rights', 'Data subjects may be informed about processing, access their data, ask for it to be corrected or destroyed, and withdraw consent. Requests go first to the company they work for or deal with, and we will help it carry them out.'],
      ['Changes', 'If this policy changes materially we will ask you to accept the new version when you sign in.']] },
  },
  terms: {
    ar: { t: 'شروط الاستخدام', d: 'آخر تحديث: 29 أكتوبر 2026 — الإصدار 2026-10', s: [
      ['نسخة تجريبية', 'وعد حالياً نسخة تجريبية مجانية للتقييم، مقدّمة «كما هي» دون ضمان لاستمرار الخدمة أو بقاء البيانات. قد تتغير المزايا أو تُحذف البيانات التجريبية.'],
      ['الحساب', 'لكل حساب منشأة واحدة. أنت مسؤول عن سرية كلمة مرورك وعن كل ما يتم من حسابك، وعن صلاحيات المستخدمين الذين تضيفهم.'],
      ['البيانات', 'أنت مسؤول عن صحة ما تُدخله وعن نظامية جمعه. لا تُدخل في النسخة التجريبية بيانات شخصية حقيقية لموظفين أو عملاء.'],
      ['الاستخدام المقبول', 'يُمنع استخدام وعد في أي نشاط مخالف للأنظمة، أو محاولة الوصول إلى بيانات منشأة أخرى، أو تعطيل الخدمة، أو اختبار اختراقها دون إذن مكتوب.'],
      ['النتائج والحسابات', 'يحسب وعد الرواتب ونهاية الخدمة والضريبة وفق الأنظمة السعودية حسب البيانات المدخلة، لكنه لا يغني عن مراجعة المختص، ولا يتحمل مسؤولية قرار يُبنى على نتائج النسخة التجريبية.'],
      ['الإيقاف', 'يحق لنا إيقاف أي حساب يخالف هذه الشروط أو يهدد أمن الخدمة.'],
      ['النظام المطبق', 'تخضع هذه الشروط لأنظمة المملكة العربية السعودية.']] },
    en: { t: 'Terms of Use', d: 'Last updated: 29 October 2026 — version 2026-10', s: [
      ['Trial version', 'Waad is currently a free trial for evaluation, provided "as is" with no guarantee that the service will continue or that data will be kept. Features may change and trial data may be deleted.'],
      ['Account', 'Each account has one company. You are responsible for keeping your password secret, for everything done from your account, and for the permissions of the users you add.'],
      ['Data', 'You are responsible for the accuracy of what you enter and for collecting it lawfully. Do not enter real personal data of employees or customers in the trial.'],
      ['Acceptable use', 'Do not use Waad for anything unlawful, try to reach another company\'s data, disrupt the service, or test its security without written permission.'],
      ['Results', 'Waad calculates payroll, end-of-service and VAT under Saudi rules from the data entered, but it does not replace review by a specialist and is not responsible for decisions based on trial results.'],
      ['Suspension', 'We may suspend any account that breaks these terms or threatens the security of the service.'],
      ['Governing law', 'These terms are governed by the laws of the Kingdom of Saudi Arabia.']] },
  },
};
function legalHtml(kind) {
  const L = LEGAL[kind][LANG === 'en' ? 'en' : 'ar'];
  const contact = LEGAL_CONTACT ? `<p>${LANG === 'en' ? 'Privacy contact' : 'للتواصل بشأن الخصوصية'}: <a href="mailto:${esc(LEGAL_CONTACT)}" dir="ltr">${esc(LEGAL_CONTACT)}</a></p>` : '';
  return `<div class="legal" data-nt dir="${LANG === 'en' ? 'ltr' : 'rtl'}"><h1>${esc(L.t)}</h1><p class="muted small">${esc(L.d)}</p>
    ${L.s.map(([h, b]) => `<h2>${esc(h)}</h2><p>${esc(b)}</p>`).join('')}${kind === 'privacy' ? contact : ''}
    <p class="small"><a href="#/${kind === 'privacy' ? 'terms' : 'privacy'}">${esc(LEGAL[kind === 'privacy' ? 'terms' : 'privacy'][LANG === 'en' ? 'en' : 'ar'].t)}</a></p></div>`;
}
// signed out: a standalone page; signed in: a normal screen
function legalView(kind) {
  $('#app').innerHTML = `<div class="auth"><div class="abox" style="max-width:760px">${brand()}<div class="card">${legalHtml(kind)}</div>
    <p class="muted small" style="text-align:center"><a href="${SITE_URL}" id="tosite">${esc(tr('← الموقع الرئيسي'))}</a> · <a href="#" id="lback">${esc(tr('العودة إلى الدخول'))}</a> · ${langBtn('linkbtn')}</p></div></div>`;
  $('#lback').onclick = e => { e.preventDefault(); history.replaceState(null, '', location.pathname + location.search); authView(); };
  $('#lg').onclick = () => { setLang(LANG === 'en' ? 'ar' : 'en'); };
}
VIEWS['#/privacy'] = async page => { page.innerHTML = legalHtml('privacy'); };
VIEWS['#/terms'] = async page => { page.innerHTML = legalHtml('terms'); };
const legalHash = () => (/^#\/(privacy|terms)\b/.exec(location.hash || '') || [])[1];
