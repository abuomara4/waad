"""Builds the public website from site/layout.html (shared head, header, footer, script) + site/pages/*.html (page bodies):
  site/index.html     home        site/modules.html   modules
  site/trust.html     compliance + security             site/contact.html   FAQ + contact
  site/pricing.html   plans + prices        site/guide.html   user guide (from app/src/guide_lib.js)
The official Waad logos are inlined straight from the system's source so they stay identical."""
import re, os
D = os.path.dirname(os.path.abspath(__file__))
BASE = 'https://abuomara4.github.io/waad/site/'
core = open(os.path.join(D, '..', 'app', 'src', 'core.js'), encoding='utf-8').read()
SB = re.search(r"url: '([^']+)', key: '([^']+)'", core)   # CFG in core.js
logo = {n: re.search(n + r" = '(data:image/webp;base64,[^']+)'", core).group(1) for n in ('LOGO_D', 'LOGO_L')}
fav = re.search(r'<link rel="icon" type="image/png" href="(data:image/png;base64,[^"]+)"', open(os.path.join(D, '..', 'app', 'build.py'), encoding='utf-8').read()).group(1)
layout = open(os.path.join(D, 'layout.html'), encoding='utf-8').read()
layout = layout.replace('<link rel="icon" href="__LOGO_L__">', '<link rel="icon" type="image/png" href="%s">' % fav)
layout = layout.replace('__LOGO_D__', logo['LOGO_D']).replace('__LOGO_L__', logo['LOGO_L'])

PAGES = [  # page, output file, title, description
    ('home', 'index.html', 'وعد | حلول دقيقة.. لوعد موثوق — نظام المنشآت السعودية',
     'حلول دقيقة.. لوعد موثوق. نظام سعودي للمنشآت الصغيرة والمتوسطة: الموظفين والرواتب وحماية الأجور والحسابات والفواتير الضريبية والمشتريات والمخزون، بالعربي والإنجليزي.'),
    ('modules', 'modules.html', 'الأقسام | وعد',
     'أقسام وعد الستة بالتفصيل: الموارد البشرية والرواتب، المالية والمحاسبة، المبيعات والتسويق، المشتريات، المخزون، والمشاريع.'),
    ('trust', 'trust.html', 'التوافق والأمان | وعد',
     'كيف يحسب وعد نظام العمل ونطاقات وضريبة القيمة المضافة والتأمينات وحماية الأجور والتأمين الطبي، وكيف يحمي بيانات كل منشأة.'),
    ('pricing', 'pricing.html', 'الباقات والأسعار | وعد',
     'باقات وعد الثلاث: أساس ونمو وريادة. اشتراك سنوي يُدفع مقدما بسعر 10 أشهر أو على أقساط شهرية، مع تجربة مجانية 14 يوما.'),
    ('guide', 'guide.html', 'دليل الاستخدام | وعد',
     'كيف يستخدم الموظف والمدير وإدارة المنشأة نظام وعد: الدخول، الحضور، طلب الإجازة، قسيمة الراتب، الاعتمادات، بخطوات قصيرة وصور توضيحية.'),
    ('guide', 'guide-employee.html', 'دليل الموظف | وعد', 'كيف يستخدم الموظف نظام وعد: الدخول، تسجيل الحضور، طلب الإجازة، متابعة الطلب، قسيمة الراتب، الملف والمخالفات.'),
    ('guide', 'guide-manager.html', 'دليل المدير المباشر | وعد', 'كيف يعتمد المدير المباشر طلبات فريقه ويتابع حضورهم وإجازاتهم وتقييم أدائهم في وعد.'),
    ('guide', 'guide-admin.html', 'دليل إدارة المنشأة | وعد', 'كيف تعطي إدارة المنشأة موظفيها الدخول إلى وعد، وتطبع دليل الموظف، وتجد شروحات بقية الأقسام.'),
    ('contact', 'contact.html', 'أسئلة وتواصل | وعد',
     'أسئلة شائعة عن وعد والتجربة المجانية، وطرق التواصل معنا بالواتساب أو الإيميل.'),
]

# «دليل الاستخدام» page: built from the system's own guide texts (app/src/guide_lib.js) and the screenshots of
# site/guide_shots.py, so the website and the in-app guide never drift apart.
import json, subprocess, html
GFILE = {'emp': 'guide-employee.html', 'mgr': 'guide-manager.html', 'admin': 'guide-admin.html'}
GDESC = {'emp': ['الدخول، الحضور، الإجازات والطلبات، قسيمة الراتب، ملفك', 'Signing in, attendance, leave and requests, payslips, your profile'],
         'mgr': ['اعتماد طلبات فريقك، حضورهم وإجازاتهم، تقييم أدائهم', 'Approving your team\'s requests, their attendance and leave, their reviews'],
         'admin': ['إعطاء الموظفين الدخول، دليل الموظف المطبوع، بقية الأقسام', 'Giving employees access, the printed employee guide, the other modules']}
def guide_data():
    js = "const fs=require('fs');eval(fs.readFileSync(process.argv[1],'utf8').replace('const GUIDE','globalThis.GUIDE'));process.stdout.write(JSON.stringify(GUIDE))"
    return json.loads(subprocess.run(['node', '-e', js, os.path.join(D, '..', 'app', 'src', 'guide_lib.js')], capture_output=True, text=True, check=True).stdout)
e = lambda t: html.escape(t, quote=False)
bi = lambda p: '<span class="ar">%s</span><span class="en">%s</span>' % (e(p[0].rstrip('.')), e(p[1].rstrip('.')))
GBAND = '<section><div class="wrap"><div class="band"><div><h2><span class="ar">جرّب «وعد» لمدة 14 يوما مجانا</span><span class="en">Try Waad free for 14 days</span></h2><p><span class="ar">ابدأ ببيانات منشأتك، ووزّع على موظفيك رمز المنشأة وهذا الدليل</span><span class="en">Start with your company\'s data, and give your employees the company code and this guide</span></p></div><div class="cta"><a class="btn gold" href="app/?start=signup"><span class="ar">ابدأ التجربة المجانية</span><span class="en">Start the free trial</span></a><a class="btn ghost" href="app/"><span class="ar">دخول النظام</span><span class="en">Sign in</span></a></div></div></div></section>'
# guide.html: pick your role; guide-<role>.html: that role's topics, one page each (shorter on a phone)
def guide_body(out):
    G = guide_data(); role = next((k for k, f in GFILE.items() if f == out), None)
    tabs = '<nav class="gnav">' + ''.join('<a href="%s"%s>%s</a>' % (GFILE[k], ' aria-current="page"' if k == role else '', bi(G[k]['t'])) for k in G) + '</nav>'
    if not role:
        cards = ''.join('<a class="card ccard" id="%s" href="%s"><h3>%s</h3><p>%s</p><span class="btn line"><span class="ar">افتح الدليل</span><span class="en">Open the guide</span></span></a>'
                        % (k, GFILE[k], bi(G[k]['t']), bi(GDESC[k])) for k in G)
        return ('<div class="phero"><div class="wrap"><h1><span class="ar">دليل الاستخدام</span><span class="en">User guide</span></h1><p><span class="ar">خطوات قصيرة مع صور توضيحية، والصور من منشأة تجريبية. اختر دليلك</span><span class="en">Short steps with pictures from a sample company. Choose your guide</span></p></div></div>'
                '<section><div class="wrap"><div class="grid g3">%s</div></div></section>' % cards + GBAND)
    sec = G[role]; out_ = ['<div class="phero"><div class="wrap"><h1><span class="ar">دليل الاستخدام: </span><span class="en">User guide: </span>%s</h1><p>%s</p>%s</div></div>' % (bi(sec['t']), bi(GDESC[role]), tabs),
                          '<section><div class="wrap"><div class="gitems">']
    for it in sec['items']:
        if it['id'] == 'print': continue   # «print the guide» is a button inside the system
        img = ('<figure class="gimg"><img class="ar" src="img/guide/%s-ar.webp" alt="%s" width="480" height="1039" loading="lazy" decoding="async"><img class="en" src="img/guide/%s-en.webp" alt="%s" width="480" height="1039" loading="lazy" decoding="async"></figure>'
               % (it['img'], e(it['t'][0]), it['img'], e(it['t'][1]))) if it.get('img') else ''
        out_.append('<article class="gitem" id="g-%s"><div><h3>%s</h3><ol>%s</ol></div>%s</article>' % (it['id'], bi(it['t']), ''.join('<li>%s</li>' % bi(x) for x in it['s']), img))
    out_.append('</div></div></section>' + GBAND)
    return '\n'.join(out_)

for page, out, title, desc in PAGES:
    body = guide_body(out) if page == 'guide' else open(os.path.join(D, 'pages', page + '.html'), encoding='utf-8').read()
    url = BASE if out == 'index.html' else BASE + out
    t = (layout.replace('__BODY__', body).replace('__TITLE__', title).replace('__DESC__', desc)
               .replace('__URL__', url).replace('__PAGE__', page).replace('__SB_URL__', SB.group(1)).replace('__SB_KEY__', SB.group(2)))
    assert not re.search(r'__[A-Z]+__', t), out   # every placeholder filled
    open(os.path.join(D, out), 'w', encoding='utf-8').write(t)
    print('built site/%s' % out, len(t.encode()), 'bytes')

# search engines: one sitemap of the public pages (canonical GitHub Pages URLs). robots.txt only takes effect where
# site/ is the domain root (Cloudflare Pages); on github.io the root belongs to another repo, so submit the sitemap
# in Google Search Console instead. The system (app/) carries its own noindex.
urls = ''.join('  <url><loc>%s</loc></url>\n' % (BASE if out == 'index.html' else BASE + out) for _, out, _, _ in PAGES)  # no lastmod: it would change on every build
open(os.path.join(D, 'sitemap.xml'), 'w', encoding='utf-8').write('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' + urls + '</urlset>\n')
open(os.path.join(D, 'robots.txt'), 'w', encoding='utf-8').write('User-agent: *\nDisallow: /app/\nDisallow: /admin/\nSitemap: %ssitemap.xml\n' % BASE)
print('built site/sitemap.xml + site/robots.txt')
