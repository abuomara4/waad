"""«وعد حسب القطاع»: one page per sector + a hub (industries.html), rendered into the shared layout by site/build.py.
Every feature named here exists in the system; keep it that way (no promises of integrations Waad does not have).
pages() returns (page key, output file, title, description, body) like knowledge.pages()."""
from html import escape as E

def T(ar, en):
    return '<span class="ar">%s</span><span class="en">%s</span>' % (E(ar), E(en))

SECTORS = [
  ('contracting', 'المقاولات والمشاريع', 'Contracting and projects',
   'عمالة كبيرة في مواقع متعددة، ووثائق وإقامات تنتهي، ومشاريع تحتاج تكاليف دقيقة.',
   'Large crews across several sites, documents and iqamas that expire, and projects that need accurate costs.',
   [('إقامات وجوازات وتأشيرات تنتهي دون أن ينتبه أحد', 'Iqamas, passports and visas expiring unnoticed'),
    ('الحضور في مواقع بعيدة عن المكتب', 'Attendance at sites far from the office'),
    ('تكلفة كل مشروع غير واضحة', 'Unclear cost per project'),
    ('العهد والمعدات مع العمال', 'Custody and equipment held by workers')],
   [('تنبيهات انتهاء الإقامات والجوازات والعقود ووثائق المنشأة والسيارات', 'Expiry alerts for iqamas, passports, contracts, company documents and vehicles'),
    ('الحضور من جوال العامل بالموقع الجغرافي، وجدول الورديات', 'Attendance from the worker’s phone by location, and shift rosters'),
    ('المشاريع وجداول الوقت وتكلفة كل مشروع، ومراكز التكلفة', 'Projects, timesheets and the cost of each project, with cost centers'),
    ('العُهد بتوقيع إلكتروني، والعهد النقدية لكل موقع', 'Custody signed electronically, and petty cash per site'),
    ('العمل الإضافي حسب المادة 107، ولائحة المخالفات والجزاءات', 'Overtime per Art. 107, and the work rules for penalties'),
    ('نطاقات وحماية الأجور والتأمينات الاجتماعية في صفحة الامتثال', 'Nitaqat, wage protection and GOSI on the compliance page'),
    ('طلبات الشراء وأوامر الشراء والمطابقة الثلاثية، والمخزون لكل مستودع', 'Purchase requests, orders and three-way matching, and stock per warehouse')]),
  ('retail', 'التجزئة والمتاجر', 'Retail and shops',
   'نقاط بيع وفروع ومخزون يتحرك كل يوم، وفواتير مبسطة لزاتكا، وموظفون بورديات.',
   'Points of sale, branches and stock that moves every day, simplified ZATCA invoices and staff on shifts.',
   [('المخزون لا يطابق الواقع', 'Stock that does not match reality'),
    ('نفاد الأصناف المهمة', 'Key items running out'),
    ('الفوترة الإلكترونية للمبيعات اليومية', 'E-invoicing for daily sales'),
    ('ورديات الموظفين وحضورهم', 'Staff shifts and attendance')],
   [('نقطة البيع بفاتورة مبسطة ورمز QR، والربط مع منصة «فاتورة»', 'Point of sale with simplified invoices and QR, linked with Fatoora'),
    ('عدة مستودعات وفروع، والتحويل بينها، والجرد', 'Several warehouses and branches, transfers between them, and stock counts'),
    ('حد إعادة الطلب وتنبيه النقص، والأرقام التسلسلية والدفعات وتواريخ الانتهاء', 'Reorder points and shortage alerts, serial numbers, batches and expiry dates'),
    ('المبيعات والمرتجعات والإشعارات الدائنة، وأعمار ديون العملاء', 'Sales, returns and credit notes, and receivables ageing'),
    ('جدول الورديات والحضور من الجوال', 'Shift rosters and attendance from the phone'),
    ('القوائم المالية والإقرار الضريبي من نفس النظام', 'Financial statements and the VAT return from the same system')]),
  ('restaurants', 'المطاعم والمقاهي', 'Restaurants and cafés',
   'ورديات طويلة، وشهادات صحية تنتهي، ومواد غذائية لها تاريخ صلاحية، ومبيعات سريعة.',
   'Long shifts, health certificates that expire, food with expiry dates and fast sales.',
   [('الشهادات الصحية للعاملين تنتهي', 'Staff health certificates expiring'),
    ('تنظيم الورديات والإجازات', 'Organising shifts and leave'),
    ('هدر المواد بسبب الصلاحية', 'Waste from expired stock'),
    ('الرواتب والعمل الإضافي بدقة', 'Accurate payroll and overtime')],
   [('الشهادة الصحية كمستند للموظف مع تنبيه قبل انتهائها', 'The health certificate as an employee document with an alert before it expires'),
    ('جدول الورديات، والحضور بالموقع، وتقويم الإجازات', 'Shift rosters, attendance by location and a leave calendar'),
    ('تواريخ انتهاء المخزون وتنبيهاتها، وإعادة الطلب', 'Stock expiry dates with alerts, and reordering'),
    ('نقطة البيع والفاتورة المبسطة لزاتكا', 'Point of sale and the simplified ZATCA invoice'),
    ('مسير الرواتب بالعمل الإضافي والغياب والتأمينات وملف حماية الأجور', 'Payroll with overtime, absence, GOSI and the wage protection file'),
    ('المشتريات من الموردين واعتماد فواتيرهم', 'Purchasing from suppliers and approving their invoices')]),
  ('services', 'الخدمات والمكاتب المهنية', 'Services and professional firms',
   'مشاريع للعملاء، وساعات عمل تُفوتر، وعقود وتوقيعات، وفريق يحتاج تقييما وتطويرا.',
   'Client projects, billable hours, contracts and signatures, and a team that needs reviews and growth.',
   [('معرفة ربحية كل عميل ومشروع', 'Knowing the profit of each client and project'),
    ('الفواتير الدورية والمتابعة', 'Recurring invoices and follow-up'),
    ('العروض والعقود والتوقيع', 'Quotes, contracts and signatures'),
    ('تقييم الأداء والتدريب', 'Performance reviews and training')],
   [('المشاريع وجداول الوقت وتكلفة كل مشروع', 'Projects, timesheets and the cost of each project'),
    ('عروض الأسعار والفواتير المتكررة وإرسالها للعميل، وبوابة العميل برابط خاص', 'Quotes and recurring invoices sent to the client, and a private client portal'),
    ('التوقيع الإلكتروني للعقود والمستندات', 'E-signature for contracts and documents'),
    ('إدارة العملاء المحتملين والفرص (CRM) والحملات', 'Leads, opportunities (CRM) and campaigns'),
    ('تقييم الأداء بالأهداف والنتائج الرئيسية (OKRs) و360 درجة، وخطة التدريب', 'Performance reviews with OKRs and 360 feedback, and a training plan'),
    ('المحاسبة الكاملة ومراكز التكلفة والموازنات', 'Full accounting, cost centers and budgets')]),
  ('trading', 'التجارة والتوزيع', 'Trading and distribution',
   'موردون وعملاء كثيرون، ومستودعات، وتوصيل، وذمم مدينة ودائنة تحتاج متابعة يومية.',
   'Many suppliers and customers, warehouses, deliveries, and receivables and payables to follow daily.',
   [('متابعة ديون العملاء والموردين', 'Following customer and supplier balances'),
    ('مطابقة المشتريات مع الاستلام والفواتير', 'Matching purchases with receipts and invoices'),
    ('حركة المخزون بين المستودعات', 'Stock moving between warehouses'),
    ('الفوترة الإلكترونية للعملاء المسجلين في الضريبة', 'E-invoicing for VAT-registered customers')],
   [('فواتير ضريبية بالعنوان الوطني والربط مع «فاتورة» (المرحلة الثانية)', 'Tax invoices with the national address, linked with Fatoora (phase two)'),
    ('أوامر البيع وإشعارات التسليم، والمرتجعات', 'Sales orders, delivery notes and returns'),
    ('أوامر الشراء والاستلام وفواتير الموردين الواردة والمطابقة الثلاثية', 'Purchase orders, receipts, incoming supplier invoices and three-way matching'),
    ('عدة مستودعات والتحويلات والجرد وحد إعادة الطلب', 'Several warehouses, transfers, counts and reorder points'),
    ('كشوف حساب العملاء والموردين وأعمار الديون والشيكات', 'Customer and supplier statements, ageing and cheques'),
    ('لوحة الإنفاق وتصدير القيود لمحاسبك', 'The spend overview and journal export for your accountant')]),
]

def cta():
    return ('<section><div class="wrap"><div class="band"><div><h2>' + T('جرّب «وعد» لمدة 14 يوما مجانا', 'Try Waad free for 14 days') + '</h2><p>' +
            T('دون بطاقة دفع، ببيانات منشأتك الفعلية.', 'No payment card, with your real company data.') + '</p></div>'
            '<div class="cta"><a class="btn gold" href="app/?start=signup">' + T('ابدأ التجربة المجانية', 'Start the free trial') + '</a>'
            '<a class="btn ghost" href="pricing.html#which">' + T('أي باقة تناسبني؟', 'Which plan fits me?') + '</a></div></div></div></section>')

def lil(ar):   # «لـ» + «ال» = «لل»: للمقاولات
    return 'ل' + ar[1:] if ar.startswith('ال') else 'ل' + ar

def page(s):
    k, ar, en, iar, ien, pains, feats = s
    return ('<div class="phero"><div class="wrap"><a class="small kn-crumb" href="industries.html">' + T('وعد حسب القطاع', 'Waad by sector') + '</a><h1>' + T('وعد ' + lil(ar), 'Waad for ' + en.lower()) + '</h1><p>' + T(iar, ien) + '</p></div></div>'
            '<section><div class="wrap"><div class="grid g2">'
            '<div class="card"><h3>' + T('التحديات المعتادة', 'Usual challenges') + '</h3><ul>' + ''.join('<li>' + T(a, b) + '</li>' for a, b in pains) + '</ul></div>'
            '<div class="card"><h3>' + T('كيف يساعدك وعد', 'How Waad helps') + '</h3><ul>' + ''.join('<li>' + T(a, b) + '</li>' for a, b in feats) + '</ul></div>'
            '</div><p class="small" style="margin-top:14px">' + T('كل ما سبق في نظام واحد بالعربي والإنجليزي، على الجوال والكمبيوتر، ووفق نظام العمل السعودي.', 'All of it in one system, in Arabic and English, on phone and computer, following the Saudi Labor Law.') +
            ' <a href="modules.html">' + T('تفاصيل الأقسام', 'Module details') + '</a></p></div></section>' + cta())

def hub():
    cards = ''.join('<a class="card mini" href="industry-%s.html" style="text-decoration:none;color:inherit"><h3>%s</h3><p class="small">%s</p></a>' % (s[0], T(s[1], s[2]), T(s[3], s[4])) for s in SECTORS)
    return ('<div class="phero"><div class="wrap"><h1>' + T('وعد حسب القطاع', 'Waad by sector') + '</h1><p>' + T('كيف يخدم وعد منشأتك حسب نشاطها: نفس النظام، بما يهم قطاعك أولا.', 'How Waad serves your company by its activity: the same system, with what matters to your sector first.') + '</p></div></div>'
            '<section><div class="wrap"><div class="grid g3">' + cards + '</div></div></section>' + cta())

def pages():
    out = [('industries', 'industries.html', 'وعد حسب القطاع | وعد', 'كيف يخدم وعد المقاولات والتجزئة والمطاعم والخدمات والتجارة: الموارد البشرية والمحاسبة والمخزون في نظام واحد.', hub())]
    for s in SECTORS:
        out.append(('industry', 'industry-%s.html' % s[0], 'وعد %s | وعد' % lil(s[1]), s[3] + ' ' + 'وعد يجمع الموارد البشرية والمحاسبة والمخزون في نظام واحد.', page(s)))
    return out
