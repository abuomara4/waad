"""Builds the public website from site/layout.html (shared head, header, footer, script) + site/pages/*.html (page bodies):
  site/index.html     home        site/modules.html   modules
  site/trust.html     compliance + security             site/contact.html   FAQ + contact
The official Waad logos are inlined straight from the system's source so they stay identical."""
import re, os
D = os.path.dirname(os.path.abspath(__file__))
BASE = 'https://abuomara4.github.io/waad/site/'
core = open(os.path.join(D, '..', 'app', 'src', 'core.js'), encoding='utf-8').read()
logo = {n: re.search(n + r" = '(data:image/webp;base64,[^']+)'", core).group(1) for n in ('LOGO_D', 'LOGO_L')}
fav = re.search(r'<link rel="icon" type="image/png" href="(data:image/png;base64,[^"]+)"', open(os.path.join(D, '..', 'app', 'build.py'), encoding='utf-8').read()).group(1)
layout = open(os.path.join(D, 'layout.html'), encoding='utf-8').read()
layout = layout.replace('<link rel="icon" href="__LOGO_L__">', '<link rel="icon" type="image/png" href="%s">' % fav)
layout = layout.replace('__LOGO_D__', logo['LOGO_D']).replace('__LOGO_L__', logo['LOGO_L'])

PAGES = [  # page, output file, title, description
    ('home', 'index.html', 'وعد — نظام إدارة المنشآت | Waad ERP',
     'وعد: نظام سعودي واحد للموارد البشرية والرواتب والمالية والمبيعات والمشتريات والمخزون، بالعربية والإنجليزية، متوافق مع نظام العمل وضريبة القيمة المضافة.'),
    ('modules', 'modules.html', 'الأقسام — وعد | Waad ERP',
     'أقسام وعد: الموارد البشرية، الرواتب وحماية الأجور، المالية والمحاسبة، المبيعات والفواتير الضريبية، المشتريات، والمخزون.'),
    ('trust', 'trust.html', 'التوافق والأمان — وعد | Waad ERP',
     'نظام العمل، نطاقات والتوطين، ضريبة القيمة المضافة، التأمينات الاجتماعية، حماية الأجور، والتأمين الطبي داخل وعد، مع عزل تام لبيانات كل منشأة.'),
    ('contact', 'contact.html', 'الأسئلة والتواصل — وعد | Waad ERP',
     'الأسئلة الشائعة عن نظام وعد، وطرق التواصل معنا عبر واتساب والبريد الإلكتروني.'),
]
for page, out, title, desc in PAGES:
    body = open(os.path.join(D, 'pages', page + '.html'), encoding='utf-8').read()
    url = BASE if out == 'index.html' else BASE + out
    t = (layout.replace('__BODY__', body).replace('__TITLE__', title).replace('__DESC__', desc)
               .replace('__URL__', url).replace('__PAGE__', page))
    assert not re.search(r'__[A-Z]+__', t), out   # every placeholder filled
    open(os.path.join(D, out), 'w', encoding='utf-8').write(t)
    print('built site/%s' % out, len(t.encode()), 'bytes')
