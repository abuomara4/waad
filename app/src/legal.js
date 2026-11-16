'use strict';
/* Privacy policy and terms of use. Each text exists in Arabic and English and is shown in the interface language
   (data-nt: not passed through the UI translator). Bump TERMS_VERSION when either text changes materially. */
const TERMS_VERSION = '2026-11';
const LEGAL_CONTACT = '';   // privacy contact e-mail; shown when set
const LEGAL = {
  privacy: {
    ar: { t: 'سياسة الخصوصية', d: 'آخر تحديث: 17 نوفمبر 2026 — الإصدار 2026-11', s: [
      ['من نحن', 'وعد نظام سحابي لإدارة الموارد البشرية والمالية والمبيعات والمشتريات والمخزون للمنشآت. هذه نسخة تجريبية مقدّمة للتقييم.'],
      ['دور كل طرف', 'المنشأة التي تسجّل في وعد هي «جهة التحكم» في البيانات التي تُدخلها عن موظفيها وعملائها ومورديها، ووعد «جهة معالجة» تحفظ هذه البيانات وتعالجها نيابة عنها ولغرض تشغيل الخدمة فقط، وفق نظام حماية البيانات الشخصية في المملكة العربية السعودية ولوائحه.'],
      ['البيانات التي نجمعها', 'بيانات الحساب: البريد الإلكتروني وكلمة المرور (تُحفظ مشفّرة لدى مزوّد الدخول ولا نراها). بيانات المنشأة وما يُدخله مستخدموها: الموظفون والرواتب والحضور والفواتير والعملاء والموردون وغيرها. بيانات تقنية محدودة: رسائل الأخطاء التقنية دون محتوى السجلات، وعنوان IP عند إدخال رمز منشأة خاطئ (لمنع التخمين، ويُحذف بعد يوم). بيانات التسجيل عن المنشأة: جوال المالك والمدينة وعدد الموظفين التقريبي ونشاط المنشأة ومن أين عرفت عن وعد.'],
      ['لماذا نستخدمها', 'لتشغيل الخدمة وحساب الرواتب والفواتير والتقارير التي تطلبها المنشأة، وحماية الحسابات من الدخول غير المصرّح به، وإصلاح الأعطال. لا نبيع البيانات، ولا نستخدمها للإعلانات، ولا نشاركها مع منشأة أخرى.'],
      ['من يطّلع عليها', 'مستخدمو المنشأة حسب الصلاحيات التي يحددها مالكها، ولا ترى أي منشأة بيانات منشأة أخرى. إدارة المنصة لا تطّلع على بيانات المنشآت، ولا تدخل إليها إلا بإذن مؤقت من مالك المنشأة لغرض الدعم. ترى إدارة المنصة فقط بيانات الاشتراك وبيانات التسجيل أعلاه وأرقام استخدام إجمالية (عدد الموظفين المسجّلين، والأقسام التي فيها بيانات، وتاريخ آخر نشاط) لخدمة العميل ومتابعة الاشتراك، دون أي أسماء أو مبالغ أو سجلات.'],
      ['أين تُحفظ', 'تُحفظ البيانات لدى مزوّد البنية السحابية Supabase على خوادم في طوكيو باليابان، أي خارج المملكة. يوافق مالك المنشأة على ذلك صراحة عند إنشاء المنشأة، وهو مسؤول عن إبلاغ موظفيه وعملائه بأن بياناتهم تُحفظ خارج المملكة وعن استيفاء ما يتطلبه نظام حماية البيانات الشخصية لنقلها. ونعمل على نقل الحفظ إلى موقع داخل المملكة.'],
      ['مدة الحفظ', 'تبقى البيانات ما دام اشتراك المنشأة قائما. إذا انتهى الاشتراك أو التجربة دون تجديد تبقى البيانات محفوظة كما هي 60 يوما، ونرسل للمالك تنبيها قبل 30 يوما وقبل 7 أيام من نهايتها، وبعدها تُحذف بيانات المنشأة نهائيا بقرار من فريق وعد لا تلقائيا، ويمكن تمديد المهلة عند الطلب. وتُحذف كذلك عند طلب المالك. يستطيع المالك تنزيل نسخة كاملة من بياناته في أي وقت من «إعدادات المنشأة»، والمنشأة مسؤولة عن الاحتفاظ بسجلاتها المحاسبية وفواتيرها المدة التي تُلزمها بها الأنظمة. تُمسح النسخ الاحتياطية المشفّرة تلقائيا خلال 30 يوما من الحذف، ويبقى لدينا سجل مختصر بالحذف وتاريخه ودفعات الاشتراك فقط.'],
      ['الحماية', 'الاتصال مشفّر، وكل منشأة معزولة في قاعدة البيانات بقواعد وصول، وكل تعديل مسجّل في سجل تدقيق لا يُعدّل. يمكن تفعيل التحقق بخطوتين لكل حساب.'],
      ['حقوقك', 'لصاحب البيانات حق العلم بمعالجتها، والوصول إليها، وطلب تصحيحها أو إتلافها، والرجوع عن موافقته. يُقدَّم الطلب أولا إلى المنشأة التي يعمل لديها أو يتعامل معها، وسنساعدها في تنفيذه.'],
      ['التغييرات', 'إذا تغيّرت هذه السياسة تغييرا جوهريا سنطلب موافقتك على الإصدار الجديد عند الدخول.']] },
    en: { t: 'Privacy Policy', d: 'Last updated: 17 November 2026 — version 2026-11', s: [
      ['Who we are', 'Waad is a cloud system for HR, finance, sales, purchasing and inventory. This is a trial version offered for evaluation.'],
      ['Roles', 'The company that signs up is the "controller" of the data it enters about its employees, customers and suppliers. Waad is a "processor" that stores and processes that data on the company\'s behalf, only to run the service, under the Saudi Personal Data Protection Law and its regulations.'],
      ['Data we collect', 'Account data: e-mail and password (stored hashed by the sign-in provider; we never see it). Company data entered by its users: employees, payroll, attendance, invoices, customers, suppliers and so on. Limited technical data: technical error messages without record contents, and the IP address when a wrong company code is entered (to prevent guessing; deleted after one day). Sign-up details about the company: the owner\'s mobile, city, approximate number of employees, activity, and how it heard about Waad.'],
      ['Why we use it', 'To run the service and produce the payroll, invoices and reports the company asks for, to protect accounts from unauthorised access, and to fix faults. We do not sell data, use it for advertising, or share it with any other company.'],
      ['Who can see it', 'The company\'s own users, according to the permissions its owner sets. No company can see another company\'s data. The platform administrators do not view company data and only access it with the owner\'s temporary permission for support. They see only the subscription, the sign-up details above and overall usage numbers (number of registered employees, which modules hold data, and the date of the last activity) to serve the customer and follow the subscription, never any names, amounts or records.'],
      ['Where it is stored', 'Data is stored with the cloud provider Supabase on servers in Tokyo, Japan, i.e. outside the Kingdom. The company owner explicitly agrees to this when creating the company, and is responsible for informing its employees and customers that their data is stored outside the Kingdom and for meeting what the Personal Data Protection Law requires for the transfer. We are working on moving storage to a location inside the Kingdom.'],
      ['Retention', 'Data is kept while the company\'s subscription is active. If the subscription or trial ends without renewal, the data is kept as is for 60 days and the owner is notified 30 days and 7 days before that ends; after that the company\'s data is permanently deleted by a decision of the Waad team, never automatically, and the period can be extended on request. It is also deleted when the owner asks. The owner can download a full copy at any time from the company settings, and the company is responsible for keeping its accounting records and invoices for the period the law requires. Encrypted backups are erased automatically within 30 days of the deletion; we keep only a short record of the deletion, its date and the subscription payments.'],
      ['Security', 'Connections are encrypted, each company is isolated in the database by access rules, and every change is recorded in a tamper-proof audit log. Two-step verification can be enabled on every account.'],
      ['Your rights', 'Data subjects may be informed about processing, access their data, ask for it to be corrected or destroyed, and withdraw consent. Requests go first to the company they work for or deal with, and we will help it carry them out.'],
      ['Changes', 'If this policy changes materially we will ask you to accept the new version when you sign in.']] },
  },
  terms: {
    ar: { t: 'شروط الاستخدام', d: 'آخر تحديث: 17 نوفمبر 2026 — الإصدار 2026-11', s: [
      ['التجربة والاشتراك', 'تبدأ كل منشأة بتجربة مجانية مدتها 14 يوما، ثم تستمر باشتراك مدفوع حسب الباقة المختارة وما تشمله من أقسام وحد للموظفين، والأسعار المعلنة شاملة ضريبة القيمة المضافة. إذا انتهت التجربة أو الاشتراك دون تجديد تُقفل الأقسام وتبقى البيانات محفوظة وفق بند «مدة الحفظ» في سياسة الخصوصية.'],
      ['الخدمة', 'نبذل عناية معقولة لاستمرار الخدمة وحماية البيانات، مع نسخ احتياطي يومي مشفّر. قد تتوقف الخدمة مؤقتا للصيانة أو لأسباب خارجة عن إرادتنا، وقد نطوّر المزايا أو نغيّرها، ولا نحذف بيانات منشأة إلا وفق سياسة الخصوصية أو بطلب مالكها.'],
      ['الحساب', 'لكل حساب منشأة واحدة. أنت مسؤول عن سرية كلمة مرورك وعن كل ما يتم من حسابك، وعن صلاحيات المستخدمين الذين تضيفهم.'],
      ['البيانات', 'أنت مسؤول عن صحة ما تُدخله وعن نظامية جمعه، وعن إبلاغ موظفيك وعملائك بأن بياناتهم تُحفظ لدى مزوّد سحابي خارج المملكة (اليابان). يمكنك البدء ببياناتك الفعلية من أول يوم في التجربة، واستكمال العمل عليها عند الاشتراك.'],
      ['الاستخدام المقبول', 'يُمنع استخدام وعد في أي نشاط مخالف للأنظمة، أو محاولة الوصول إلى بيانات منشأة أخرى، أو تعطيل الخدمة، أو اختبار اختراقها دون إذن مكتوب.'],
      ['النتائج والحسابات', 'يحسب وعد الرواتب ونهاية الخدمة والضريبة وفق الأنظمة السعودية حسب البيانات المدخلة، لكنه لا يغني عن مراجعة المختص، ولا يتحمل مسؤولية قرار يُبنى على نتائجه دون مراجعة.'],
      ['الإيقاف', 'يحق لنا إيقاف أي حساب يخالف هذه الشروط أو يهدد أمن الخدمة.'],
      ['النظام المطبق', 'تخضع هذه الشروط لأنظمة المملكة العربية السعودية.']] },
    en: { t: 'Terms of Use', d: 'Last updated: 17 November 2026 — version 2026-11', s: [
      ['Trial and subscription', 'Every company starts with a 14-day free trial, then continues on a paid subscription according to the chosen plan, with its modules and employee limit; listed prices include VAT. If the trial or subscription ends without renewal, the modules close and the data is kept as set out in «Retention» in the privacy policy.'],
      ['The service', 'We take reasonable care to keep the service running and the data protected, with an encrypted daily backup. The service may stop for a while for maintenance or for reasons beyond our control, and we may develop or change features. We delete a company\'s data only under the privacy policy or at its owner\'s request.'],
      ['Account', 'Each account has one company. You are responsible for keeping your password secret, for everything done from your account, and for the permissions of the users you add.'],
      ['Data', 'You are responsible for the accuracy of what you enter, for collecting it lawfully, and for informing your employees and customers that their data is stored with a cloud provider outside the Kingdom (Japan). You can start with your real data from day one of the trial and keep it if you subscribe.'],
      ['Acceptable use', 'Do not use Waad for anything unlawful, try to reach another company\'s data, disrupt the service, or test its security without written permission.'],
      ['Results', 'Waad calculates payroll, end-of-service and VAT under Saudi rules from the data entered, but it does not replace review by a specialist and is not responsible for decisions based on its results without review.'],
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
