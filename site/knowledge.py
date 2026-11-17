"""«مركز وعد للمعرفة» — renders the website's knowledge pages from the content in site/kb/*.py:
  knowledge.html (hub) · blog.html + blog-<slug>.html (guides) · policies.html + policy-<slug>.html (policy library)
  jobs.html (job descriptions by department) · glossary.html (company glossary by department) · updates.html (what's new)
Edit the content in site/kb/, never the built pages. Legal figures are cited and checked against the official Labor Law."""
from html import escape as e
import json
BASE = 'https://abuomara4.github.io/waad/site/'
from kb.articles import ARTICLES, CATS
from kb.policies import POLICIES
from kb.jobs import DEPTS
from kb.glossary import GROUPS
from kb.changelog import RELEASES

def bi(ar, en, tag='span'):
    return '<%s class="ar">%s</%s><%s class="en">%s</%s>' % (tag, e(ar), tag, tag, e(en), tag)

def hero(ar, en, sar, sen, crumb=None):
    c = '<a class="small kn-crumb" href="%s">%s</a>' % (crumb[0], bi(*crumb[1:])) if crumb else ''
    return '<div class="phero"><div class="wrap">%s<h1>%s</h1><p>%s</p></div></div>\n' % (c, bi(ar, en), bi(sar, sen))

HUB = ('knowledge.html', 'مركز وعد للمعرفة', 'Waad Knowledge Centre')
NOTE = '<p class="small kn-note">%s</p>' % bi('محتوى إرشادي عام، راجعناه على النص الرسمي لنظام العمل المنشور من وزارة الموارد البشرية (بتعديلاته حتى 2025). المرجع النهائي هو النظام ولوائحه والمنصات الرسمية، فراجع المختص قبل أي قرار.',
                                              'General guidance checked against the official Labor Law text published by the Ministry of Human Resources (amended to 2025). The final reference is the law, its regulations and the official platforms; consult a specialist before any decision.')
CTA = '<div class="kn-cta card">%s<a class="btn gold" href="app/?start=signup">%s</a></div>' % (
    bi('طبّق هذا تلقائيا في منشأتك: وعد يحسب الإجازات والرواتب والمكافآت وينبهك قبل كل موعد', 'Apply this automatically: Waad calculates leave, payroll and awards and alerts you before every deadline', 'p'),
    bi('جرّب وعد مجانا 14 يوما', 'Try Waad free for 14 days'))
SEARCH = '<input class="kn-search" type="search" placeholder="ابحث… / Search…" aria-label="search" data-kn-search>'
SEARCH_JS = '''<script>(function(){var i=document.querySelector('[data-kn-search]');if(!i)return;i.addEventListener('input',function(){var q=i.value.trim().toLowerCase();document.querySelectorAll('[data-kn-item]').forEach(function(x){x.hidden=q&&x.textContent.toLowerCase().indexOf(q)<0;});document.querySelectorAll('[data-kn-group]').forEach(function(g){g.hidden=!g.querySelector('[data-kn-item]:not([hidden])');});});})();</script>'''

def hub():
    n_art, n_pol, n_job, n_term = len(ARTICLES), len(POLICIES), sum(len(d[3]) for d in DEPTS), sum(len(g[3]) for g in GROUPS)
    tiles = [('blog.html', 'الأدلة والمقالات', 'Guides and articles', '%d دليلا عمليا في التوظيف والأجور والإجازات وإنهاء الخدمة والضريبة والتشغيل، بمواد النظام' % n_art, '%d practical guides on hiring, pay, leave, ending employment, tax and operations, with the articles of law' % n_art),
             ('policies.html', 'مكتبة السياسات', 'Policy library', '%d سياسة مفصلة: الغرض والنطاق والأحكام والإجراءات والمسؤوليات، جاهزة للطباعة والتعديل' % n_pol, '%d detailed policies: purpose, scope, rules, procedures and responsibilities, ready to print and adapt' % n_pol),
             ('jobs.html', 'دليل الوظائف', 'Job guide', '%d وصفا وظيفيا لكل الإدارات: المهام والمتطلبات ومؤشرات الأداء' % n_job, '%d job descriptions across all departments: tasks, requirements and KPIs' % n_job),
             ('glossary.html', 'قاموس المنشأة', 'Company glossary', '%d مصطلحا في الموارد البشرية والامتثال والمالية والمبيعات والمشتريات والمخزون والمشاريع' % n_term, '%d terms across HR, compliance, finance, sales, purchasing, inventory and projects' % n_term),
             ('tools.html', 'حاسبات وعد', 'Waad calculators', 'نهاية الخدمة، صافي الراتب، التأمينات، العمل الإضافي، الإجازة، الإشعار والتعويض، الضريبة، تكلفة الموظف، نطاقات', 'End of service, net pay, GOSI, overtime, leave, notice and compensation, VAT, employee cost, Nitaqat'),
             ('updates.html', 'ما الجديد في وعد', 'What\'s new in Waad', 'كل تحديثات النظام بتواريخها منذ إطلاقه', 'Every update to the system, dated, since launch')]
    cards = ''.join('<a class="card kn-tile" href="%s"><h3>%s</h3><p>%s</p></a>' % (h, bi(a, b), bi(c, d)) for h, a, b, c, d in tiles)
    latest = ''.join('<li><a href="blog-%s.html">%s</a></li>' % (x['slug'], bi(x['ar'], x['en'])) for x in ARTICLES[:6])
    return (hero('مركز وعد للمعرفة', 'Waad Knowledge Centre', 'دليلك العملي لإدارة منشأتك في السعودية: نظام العمل والرواتب والمالية والمبيعات والمشتريات والمخزون، بمراجع نظامية محدثة وحاسبات مجانية',
                 'Your practical guide to running a company in Saudi Arabia: the Labor Law, payroll, finance, sales, purchasing and inventory, with up-to-date legal references and free calculators')
            + '<section><div class="wrap"><div class="grid g3">%s</div><div class="card" style="margin-top:18px"><h3>%s</h3><ul class="kn-list">%s</ul></div>%s</div></section>' % (cards, bi('أدلة مختارة', 'Selected guides'), latest, NOTE))

def blog():
    groups = ''
    for k, ar, en in CATS:
        items = ''.join('<a class="card kn-tile" data-kn-item href="blog-%s.html"><h3>%s</h3><p>%s</p></a>' % (a['slug'], bi(a['ar'], a['en']), bi(a['sar'], a['sen'])) for a in ARTICLES if a['cat'] == k)
        groups += '<div data-kn-group><h2 class="kn-h">%s</h2><div class="grid g2">%s</div></div>' % (bi(ar, en), items)
    return (hero('الأدلة والمقالات', 'Guides and articles', 'أدلة عملية للقطاع الخاص من التعيين حتى نهاية الخدمة، ومعها الضريبة والفوترة والتشغيل، بمواد نظام العمل', 'Practical private-sector guides from hiring to exit, plus tax, invoicing and operations, citing the Labor Law', (HUB[0],) + HUB[1:])
            + '<section><div class="wrap">%s%s%s</div></section>%s' % (SEARCH, groups, NOTE, SEARCH_JS))

def ld(obj):
    return '<script type="application/ld+json">%s</script>' % json.dumps(obj, ensure_ascii=False).replace('</', '<\\/')

def crumbs(*items):
    return {'@type': 'BreadcrumbList', 'itemListElement': [{'@type': 'ListItem', 'position': i + 1, 'name': n, 'item': BASE + u} for i, (n, u) in enumerate(items)]}

def article(a):
    cat = next(c for c in CATS if c[0] == a['cat'])
    schema = ld({'@context': 'https://schema.org', '@graph': [
        {'@type': 'Article', 'headline': a['ar'], 'alternativeHeadline': a['en'], 'description': a['sar'], 'inLanguage': ['ar', 'en'],
         'articleSection': cat[1], 'url': BASE + 'blog-%s.html' % a['slug'], 'citation': a['refs'],
         'publisher': {'@type': 'Organization', 'name': 'وعد Waad', 'url': BASE}, 'author': {'@type': 'Organization', 'name': 'وعد Waad'}},
        crumbs(('مركز وعد للمعرفة', 'knowledge.html'), ('الأدلة والمقالات', 'blog.html'), (a['ar'], 'blog-%s.html' % a['slug']))]})
    body = ''.join('<h2>%s</h2><p>%s</p>' % (bi(h1, h2), bi(p1, p2)) for h1, h2, p1, p2 in a['body'])
    rel = [x for x in ARTICLES if x['cat'] == a['cat'] and x is not a] + [x for x in ARTICLES if x['cat'] != a['cat']]
    more = ''.join('<li><a href="blog-%s.html">%s</a></li>' % (x['slug'], bi(x['ar'], x['en'])) for x in rel[:5])
    return (hero(a['ar'], a['en'], a['sar'], a['sen'], ('blog.html', 'الأدلة والمقالات', 'Guides and articles'))
            + '<section><div class="wrap kn-art"><article class="card"><div class="kn-cat">%s</div>%s<p class="kn-ref"><b>%s</b> %s</p>%s</article>%s<div class="card"><h3>%s</h3><ul class="kn-list">%s</ul></div></div></section>' % (
                bi(cat[1], cat[2]), body, bi('المرجع:', 'Reference:'), e(a['refs']), NOTE, CTA, bi('أدلة ذات صلة', 'Related guides'), more) + schema)

def policies():
    items = ''.join('<a class="card kn-tile" data-kn-item href="policy-%s.html"><h3>%s</h3><p>%s</p></a>' % (p['slug'], bi(p['ar'], p['en']), bi(*p['purpose'])) for p in POLICIES)
    return (hero('مكتبة السياسات', 'Policy library', 'سياسات موارد بشرية مفصلة تبدأ منها: الغرض والنطاق والأحكام والإجراءات والمسؤوليات والمرجع النظامي', 'Detailed HR policies to start from: purpose, scope, rules, procedures, responsibilities and legal reference', (HUB[0],) + HUB[1:])
            + '<section><div class="wrap">%s<div class="grid g2">%s</div>%s</div></section>%s' % (SEARCH, items, NOTE, SEARCH_JS))

def policy(p):
    ol = lambda xs: '<ol>%s</ol>' % ''.join('<li>%s</li>' % bi(a, b) for a, b in xs)
    sec = lambda ar, en, inner: '<h2>%s</h2>%s' % (bi(ar, en), inner)
    body = (sec('الغرض', 'Purpose', '<p>%s</p>' % bi(*p['purpose'])) + sec('النطاق', 'Scope', '<p>%s</p>' % bi(*p['scope']))
            + sec('الأحكام', 'Provisions', ol(p['prov'])) + sec('الإجراءات', 'Procedures', ol(p['proc'])) + sec('المسؤوليات', 'Responsibilities', ol(p['resp']))
            + sec('الاعتماد والمراجعة', 'Approval and review', '<p>%s</p>' % bi('تُعتمد هذه السياسة من الإدارة العليا، وتُراجع سنويا أو عند تعديل الأنظمة، وتُربط بلائحة تنظيم العمل المعتمدة في المنشأة.', 'Approved by senior management, reviewed yearly or when the law changes, and linked to the company\'s approved work regulations.')))
    schema = ld({'@context': 'https://schema.org', '@graph': [{'@type': 'Article', 'headline': p['ar'], 'alternativeHeadline': p['en'], 'description': p['purpose'][0], 'inLanguage': ['ar', 'en'],
        'url': BASE + 'policy-%s.html' % p['slug'], 'publisher': {'@type': 'Organization', 'name': 'وعد Waad', 'url': BASE}},
        crumbs(('مركز وعد للمعرفة', 'knowledge.html'), ('مكتبة السياسات', 'policies.html'), (p['ar'], 'policy-%s.html' % p['slug']))]})
    return schema + (hero(p['ar'], p['en'], 'نموذج سياسة قابل للتعديل', 'An adaptable policy template', ('policies.html', 'مكتبة السياسات', 'Policy library'))
            + '<section><div class="wrap kn-art"><article class="card kn-policy"><div class="kn-tools"><button class="btn line" type="button" onclick="window.print()">%s</button></div>%s<p class="kn-ref"><b>%s</b> %s</p>%s</article>%s</div></section>' % (
                bi('طباعة أو حفظ PDF', 'Print or save as PDF'), body, bi('المرجع:', 'Reference:'), e(p['refs']), NOTE, CTA))

def jobs():
    groups = ''
    for k, ar, en, js in DEPTS:
        items = ''.join('<details class="card kn-d" data-kn-item><summary><b>%s</b></summary><p>%s</p><h4>%s</h4><ul>%s</ul><h4>%s</h4><ul>%s</ul><h4>%s</h4><ul>%s</ul></details>' % (
            bi(j['ar'], j['en']), bi(j['par'], j['pen']), bi('المهام', 'Tasks'), ''.join('<li>%s</li>' % bi(*t) for t in j['tasks']),
            bi('المتطلبات', 'Requirements'), ''.join('<li>%s</li>' % bi(*t) for t in j['req']), bi('مؤشرات الأداء', 'KPIs'), ''.join('<li>%s</li>' % bi(*t) for t in j['kpi'])) for j in js)
        groups += '<div data-kn-group><h2 class="kn-h">%s</h2>%s</div>' % (bi(ar, en), items)
    return (hero('دليل الوظائف', 'Job guide', 'أوصاف وظيفية لكل إدارات المنشأة: الغرض والمهام والمتطلبات ومؤشرات الأداء', 'Job descriptions for every department: purpose, tasks, requirements and KPIs', (HUB[0],) + HUB[1:])
            + '<section><div class="wrap kn-art">%s%s%s</div></section>%s' % (SEARCH, groups, CTA, SEARCH_JS))

def glossary():
    groups = ''
    for k, ar, en, terms in GROUPS:
        rows = ''.join('<div class="kn-g" data-kn-item><h3>%s <span>%s</span></h3><p>%s</p></div>' % (e(a), e(b), bi(c, d)) for a, b, c, d in terms)
        groups += '<div class="card" data-kn-group><h2 class="kn-h">%s</h2>%s</div>' % (bi(ar, en), rows)
    terms = [{'@type': 'DefinedTerm', 'name': a, 'alternateName': b, 'description': c} for _, _, _, ts in GROUPS for a, b, c, d in ts]
    schema = ld({'@context': 'https://schema.org', '@type': 'DefinedTermSet', 'name': 'قاموس المنشأة — وعد', 'url': BASE + 'glossary.html', 'hasDefinedTerm': terms})
    return schema + (hero('قاموس المنشأة', 'Company glossary', 'معاني المصطلحات التي تحتاجها في الموارد البشرية والامتثال والمالية والمبيعات والمشتريات والمخزون والمشاريع', 'The terms you need across HR, compliance, finance, sales, purchasing, inventory and projects', (HUB[0],) + HUB[1:])
            + '<section><div class="wrap kn-art">%s%s%s</div></section>%s' % (SEARCH, groups, NOTE, SEARCH_JS))

def updates():
    blocks = ''.join('<div class="card kn-rel"><div class="ud">%s</div><ul>%s</ul></div>' % (bi(d1, d2), ''.join('<li>%s</li>' % bi(a, b) for a, b in items)) for d1, d2, items in RELEASES)
    return (hero('ما الجديد في وعد', 'What\'s new in Waad', 'كل تحديثات وعد منذ إطلاقه، وتصل لكل المشتركين تلقائيا وبدون رسوم', 'Every Waad update since launch; all reach every subscriber automatically at no cost', (HUB[0],) + HUB[1:])
            + '<section><div class="wrap kn-art">%s</div></section>' % (blocks + CTA))

def pages():
    """(page, out, title, description, body) for site/build.py"""
    K = 'knowledge'
    out = [(K, 'knowledge.html', 'مركز وعد للمعرفة | وعد', 'دليل عملي مجاني لإدارة المنشآت في السعودية: أدلة نظام العمل، ومكتبة السياسات، ودليل الوظائف، وقاموس المنشأة، وحاسبات مجانية.', hub()),
           (K, 'blog.html', 'الأدلة والمقالات | وعد', 'أدلة نظام العمل السعودي للقطاع الخاص: العقود والتجربة والأجور والإجازات والإشعار ونهاية الخدمة والجزاءات والضريبة والفوترة.', blog())]
    out += [(K, 'blog-%s.html' % a['slug'], a['ar'] + ' | وعد', a['sar'], article(a)) for a in ARTICLES]
    out += [(K, 'policies.html', 'مكتبة السياسات | وعد', 'نماذج سياسات موارد بشرية مفصلة: الدوام والإجازات والعمل الإضافي والعهد والسلوك والمصروفات والسفر والبيانات والتوظيف والأداء وإنهاء الخدمة.', policies())]
    out += [(K, 'policy-%s.html' % p['slug'], p['ar'] + ' | وعد', p['purpose'][0], policy(p)) for p in POLICIES]
    out += [(K, 'jobs.html', 'دليل الوظائف | وعد', 'أوصاف وظيفية جاهزة لكل الإدارات: الموارد البشرية والمالية والمبيعات والتسويق والمشتريات والمستودعات والإدارة والتقنية.', jobs()),
            (K, 'glossary.html', 'قاموس المنشأة | وعد', 'مصطلحات الموارد البشرية ونظام العمل والمنصات الحكومية والمالية والضريبة والمبيعات والمشتريات والمخزون والمشاريع.', glossary()),
            (K, 'updates.html', 'ما الجديد في وعد | وعد', 'سجل تحديثات نظام وعد منذ إطلاقه.', updates())]
    return out
