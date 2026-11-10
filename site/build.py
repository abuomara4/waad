"""Builds the public website from site/layout.html (shared head, header, footer, script) + site/pages/*.html (page bodies):
  site/index.html     home        site/modules.html   modules
  site/trust.html     compliance + security             site/contact.html   FAQ + contact
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
    ('home', 'index.html', 'وعد | نظام لإدارة المنشآت السعودية',
     'نظام سعودي للمنشآت الصغيرة والمتوسطة: الموظفين والرواتب وحماية الأجور والحسابات والفواتير الضريبية والمشتريات والمخزون، بالعربي والإنجليزي.'),
    ('modules', 'modules.html', 'الأقسام | وعد',
     'أقسام وعد الستة بالتفصيل: الموارد البشرية والرواتب، المالية والمحاسبة، المبيعات والتسويق، المشتريات، المخزون، والمشاريع.'),
    ('trust', 'trust.html', 'التوافق والأمان | وعد',
     'كيف يحسب وعد نظام العمل ونطاقات وضريبة القيمة المضافة والتأمينات وحماية الأجور والتأمين الطبي، وكيف يحمي بيانات كل منشأة.'),
    ('contact', 'contact.html', 'أسئلة وتواصل | وعد',
     'أسئلة شائعة عن وعد والتجربة المجانية، وطرق التواصل معنا بالواتساب أو الإيميل.'),
]
for page, out, title, desc in PAGES:
    body = open(os.path.join(D, 'pages', page + '.html'), encoding='utf-8').read()
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
