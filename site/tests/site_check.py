"""Quick check of the marketing website (used by CI when only the website changed, and locally before a push):
every built page opens without a JavaScript error, internal links point to pages that exist, and the free calculators work."""
import os, re, sys, glob
from playwright.sync_api import sync_playwright

SITE = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
pages = sorted(p for p in glob.glob(os.path.join(SITE, '*.html')) if os.path.basename(p) != 'layout.html')   # layout.html is the template, not a page
fails = []
def ok(cond, name):
    print(('PASS ' if cond else 'FAIL ') + name)
    if not cond: fails.append(name)

# internal links: every href to a local .html page must exist
names = {os.path.basename(p) for p in pages}
bad = set()
for p in pages:
    for h in re.findall(r'href="([^"#?:]+\.html)', open(p, encoding='utf-8').read()):
        if '/' not in h and h not in names: bad.add((os.path.basename(p), h))
ok(not bad, 'website: every internal link points to an existing page %s' % sorted(bad)[:5])

with sync_playwright() as pw:
    b = pw.chromium.launch(executable_path=os.environ.get('CHROME_PATH') or None)
    c = b.new_context(locale='ar-SA')
    c.route(re.compile(r'^https?://'), lambda r: r.abort())   # offline: fonts, analytics and the counter are not needed here
    g = c.new_page(); errs = []
    g.on('pageerror', lambda e: errs.append(str(e)[:200]))
    broken = []
    for p in pages:
        errs.clear(); g.goto('file://' + p, wait_until='domcontentloaded'); g.wait_for_timeout(80)
        if errs: broken.append((os.path.basename(p), errs[0]))
        if not g.locator('h1').count(): broken.append((os.path.basename(p), 'no heading'))
    ok(not broken, 'website: %d pages open without JavaScript errors %s' % (len(pages), broken[:3]))
    t = 'file://' + os.path.join(SITE, 'tools.html')
    g.goto(t); g.wait_for_selector('#teos .trow'); ok(' · ' not in g.inner_text('#teos select[name=reason]'), 'tools: the first calculator opens with one-language lists')
    g.fill('#teos input[name=wage]', '10000'); g.fill('#teos input[name=start]', '2020-01-01'); g.fill('#teos input[name=end]', '2022-12-31'); g.select_option('#teos select[name=reason]', 'resign'); g.wait_for_timeout(100)
    ok('5,004.57' in g.inner_text('#teos .tout'), 'tools: end of service after resignation (Art. 85)')
    g.goto(t + '#tnit'); g.wait_for_timeout(200); g.fill('#tnit input[name=total]', '0'); ok('واحد على الأقل' in g.inner_text('#tnit .tout'), 'tools: Nitaqat refuses zero employees')
    g.goto(t + '#tgosi'); g.wait_for_timeout(200); g.fill('#tgosi input[name=basic]', '8000'); g.fill('#tgosi input[name=housing]', '2000'); g.fill('#tgosi input[name=first]', '2020-01-01'); g.wait_for_timeout(100)
    ok('975.00' in g.inner_text('#tgosi .tout'), 'tools: GOSI 9.75% for a Saudi registered before July 2024')
    g.goto('file://' + os.path.join(SITE, 'pricing.html')); g.wait_for_selector('#pq .tout p'); g.fill('#pq input[name=n]', '40'); g.check('#pq input[name=sell]'); g.wait_for_timeout(100)
    ok('579' in g.inner_text('#pq .tout'), 'pricing: the plan quiz works')
    b.close()
print('%d failed' % len(fails))
sys.exit(1 if fails else 0)
