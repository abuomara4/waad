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
    ('contact', 'contact.html', 'أسئلة وتواصل | وعد',
     'أسئلة شائعة عن وعد والتجربة المجانية، وطرق التواصل معنا بالواتساب أو الإيميل.'),
]

# «دليل الاستخدام» page: built from the system's own guide texts (app/src/guide_lib.js) and the screenshots of
# site/guide_shots.py, so the website and the in-app guide never drift apart.
import json, subprocess, html
def guide_body():
    js = "const fs=require('fs');eval(fs.readFileSync(process.argv[1],'utf8').replace('const GUIDE','globalThis.GUIDE'));process.stdout.write(JSON.stringify(GUIDE))"
    G = json.loads(subprocess.run(['node', '-e', js, os.path.join(D, '..', 'app', 'src', 'guide_lib.js')], capture_output=True, text=True, check=True).stdout)
    e = lambda t: html.escape(t, quote=False)
    bi = lambda p, tag='span': '<span class="ar">%s</span><span class="en">%s</span>' % (e(p[0].rstrip('.')), e(p[1].rstrip('.')))
    out = ['<div class="phero"><div class="wrap"><h1><span class="ar">دليل الاستخدام</span><span class="en">User guide</span></h1><p><span class="ar">خطوات قصيرة مع صور توضيحية لكل ما يستخدمه الموظف والمدير وإدارة المنشأة في «وعد»، والصور من منشأة تجريبية</span><span class="en">Short steps with pictures for what employees, managers and admins use in Waad; the pictures come from a sample company</span></p>',
           '<nav class="gnav">' + ''.join('<a href="#%s">%s</a>' % (k, bi(G[k]['t'])) for k in G) + '</nav></div></div>']
    for i, (k, sec) in enumerate(G.items()):
        out.append('<section id="%s"%s><div class="wrap"><div class="sh"><h2>%s</h2></div><div class="gitems">' % (k, ' class="alt"' if i % 2 else '', bi(sec['t'])))
        for it in sec['items']:
            if it['id'] == 'print': continue   # «print the guide» is a button inside the system
            img = ('<figure class="gimg"><img class="ar" src="img/guide/%s-ar.webp" alt="%s" width="480" height="1039" loading="lazy" decoding="async"><img class="en" src="img/guide/%s-en.webp" alt="%s" width="480" height="1039" loading="lazy" decoding="async"></figure>'
                   % (it['img'], e(it['t'][0]), it['img'], e(it['t'][1]))) if it.get('img') else ''
            out.append('<article class="gitem" id="g-%s"><div><h3>%s</h3><ol>%s</ol></div>%s</article>' % (it['id'], bi(it['t']), ''.join('<li>%s</li>' % bi(x) for x in it['s']), img))
        out.append('</div></div></section>')
    out.append('<section><div class="wrap"><div class="band"><div><h2><span class="ar">جرّب «وعد» لمدة 14 يوما مجانا</span><span class="en">Try Waad free for 14 days</span></h2><p><span class="ar">ابدأ ببيانات منشأتك، ووزّع على موظفيك رمز المنشأة وهذا الدليل</span><span class="en">Start with your company\'s data, and give your employees the company code and this guide</span></p></div><div class="cta"><a class="btn gold" href="app/?start=signup"><span class="ar">ابدأ التجربة المجانية</span><span class="en">Start the free trial</span></a><a class="btn ghost" href="app/"><span class="ar">دخول النظام</span><span class="en">Sign in</span></a></div></div></div></section>')
    return '\n'.join(out)

for page, out, title, desc in PAGES:
    body = guide_body() if page == 'guide' else open(os.path.join(D, 'pages', page + '.html'), encoding='utf-8').read()
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
