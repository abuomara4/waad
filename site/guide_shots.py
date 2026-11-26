"""Screenshots for «دليل الاستخدام» (site/img/guide/*.webp), from a fictitious company («منشأة وعد التجريبية») on the local mock.
Run:  bash devserver/start.sh app   (fresh DB)  then  python3 site/guide_shots.py      (CHROME_PATH optional)
Phone-sized shots (390x844), Arabic and English. Sample data only (demo seed + one leave request)."""
import os, re, json, tempfile, urllib.request
from playwright.sync_api import sync_playwright
from PIL import Image
OUT = tempfile.mkdtemp(); SITE = os.path.dirname(os.path.abspath(__file__)); BASE = 'http://127.0.0.1:54321'; PW = 'Passw0rd!x'
DEST = os.path.join(SITE, 'img', 'guide'); os.makedirs(DEST, exist_ok=True)
INIT = "window.WAAD_CONFIG={url:'%s',key:'test-publishable-key'}" % BASE
def q(path, s): return json.loads(urllib.request.urlopen(urllib.request.Request(BASE + path, data=json.dumps({'q': s}).encode(), headers={'Content-Type': 'application/json'})).read())['r']
sql = lambda s: q('/mock/sql', s); sqlx = lambda s: q('/mock/exec', s)
names = []
with sync_playwright() as p:
    b = p.chromium.launch(**({'executable_path': os.environ['CHROME_PATH']} if os.environ.get('CHROME_PATH') else {}))
    def ctx():
        c = b.new_context(viewport={'width': 390, 'height': 844}, locale='ar-SA', device_scale_factor=2, is_mobile=True, has_touch=True)
        c.add_init_script(INIT); c.route(re.compile(r'https://fonts\.(googleapis|gstatic)\.com/.*'), lambda r: r.abort()); pg = c.new_page(); pg.errs = []
        pg.on('pageerror', lambda e: pg.errs.append(str(e))); return pg
    def lang(pg, l): pg.evaluate("l => localStorage.setItem('waad.lang', JSON.stringify(l))", l); pg.reload(); pg.wait_for_timeout(900)
    def shot(pg, name, l):
        pg.mouse.move(389, 843); pg.wait_for_timeout(900); pg.screenshot(path=f'{OUT}/{name}-{l}.png')
        if name not in names: names.append(name)
    def go(pg, h): pg.evaluate("h => location.hash = h", h); pg.wait_for_timeout(1200)
    # the owner: a fictitious company with sample data, an approved payroll and attendance switched on
    o = ctx(); o.goto(BASE + '/waad-app.html?start=signup')
    o.fill('input[name=email]', 'owner@guide.test'); o.fill('input[name=password]', PW); o.fill('input[name=password2]', PW); o.check('input[name=agree]'); o.click('#ab')
    o.wait_for_selector('#cf'); o.fill('#cf input[name=name]', 'منشأة وعد التجريبية'); o.fill('#cf input[name=name_en]', 'Waad Sample Co.'); o.fill('#cf input[name=owner_phone]', '0500000000'); o.fill('#cf input[name=city]', 'الرياض')
    o.select_option('#cf select[name=size_band]', '11-50'); o.select_option('#cf select[name=industry]', 'trade'); o.check('#cf input[name=xfer]'); o.click('#cb')
    o.wait_for_selector('#ccok'); o.check('#ccok'); o.click('#mok'); o.wait_for_selector('#dlg', state='hidden')
    print(o.evaluate("""async () => { const c = S.cid; await db.rpc('demo_seed', { p_company: c }); const d = new Date();
      const d1 = new Date(d.getFullYear(), d.getMonth() - 1, 1); let r = 'ok';
      try { const run = await db.rpc('payroll_prepare', { p_company: c, p_year: d1.getFullYear(), p_month: d1.getMonth() + 1 }); await db.rpc('payroll_sign', { p_run: run }); await db.rpc('payroll_sign', { p_run: run }); await db.rpc('payroll_approve', { p_run: run }); } catch (e) { r = 'payroll: ' + e.message; }
      return r; }"""))
    cid = o.evaluate('S.cid'); code = o.evaluate('S.company.code')
    sqlx(f"update companies set att_enabled = true where id = '{cid}'")
    emp, mgr = sql(f"(select e.emp_no || '|' || m.emp_no from employees e join employees m on m.id = e.manager_id where e.company_id = '{cid}' and e.end_date is null and m.end_date is null order by e.emp_no limit 1)").split('|')
    def mklogin(no, role):
        go(o, '#/employees'); o.locator('tbody tr', has_text=no).first.locator('td').first.click(); o.wait_for_selector('#mklogin'); o.click('#mklogin')
        o.wait_for_selector('#dlg[open] select[name=role]'); o.select_option('#dlg select[name=role]', role); o.click('#mok'); o.wait_for_selector('#dlg[open] #cpm')
        pw = o.inner_text('#dlg table').strip().split('\n')[-1].split('\t')[-1].strip(); o.click('#mx'); return pw
    def staff(no, pw):
        s = ctx(); s.goto(BASE + '/waad-app.html?c=' + code); s.wait_for_selector('input[name=emp]'); s.fill('input[name=emp]', no)
        if no == emp:
            for l in ('ar', 'en'): lang(s, l); s.wait_for_selector('input[name=emp]'); s.fill('input[name=emp]', no); shot(s, 'login', l)
            lang(s, 'ar'); s.wait_for_selector('input[name=emp]'); s.fill('input[name=emp]', no)
        s.fill('input[name=password]', pw); s.click('#ab'); s.wait_for_selector('#pf'); s.fill('input[name=p1]', PW); s.fill('input[name=p2]', PW); s.click('#pb')
        s.wait_for_selector('#nav'); s.wait_for_timeout(800)
        if s.locator('#dlg[open]').count(): s.click('#mx')
        return s
    e = staff(emp, mklogin(emp, 'employee'))
    go(e, '#/requests'); e.click('#nr'); e.wait_for_selector('#dlg[open] select[name=kind]')
    e.evaluate("""() => { const f = document.querySelector('#mform'), d = n => { const x = new Date(); x.setDate(x.getDate() + n); return x.toISOString().slice(0, 10); };
      f.from.value = d(14); f.to.value = d(16); f.from.dispatchEvent(new Event('change', { bubbles: true })); f.to.dispatchEvent(new Event('change', { bubbles: true })); }""")
    e.click('#mok'); e.wait_for_timeout(1200)
    for l in ('ar', 'en'):
        lang(e, l)
        for name, h in [('home', '#/home'), ('attendance', '#/attendance'), ('requests', '#/requests'), ('payslips', '#/payslips'), ('profile', '#/profile')]:
            go(e, h); shot(e, name, l)
        go(e, '#/requests'); e.click('#nr'); e.wait_for_selector('#dlg[open] select[name=kind]'); shot(e, 'newreq', l); e.click('#mx')
    m = staff(mgr, mklogin(mgr, 'manager'))
    for l in ('ar', 'en'): lang(m, l); go(m, '#/approvals'); shot(m, 'approvals', l)
    for l in ('ar', 'en'):
        lang(o, l); go(o, '#/employees'); o.locator('tbody tr', has_text=emp).first.locator('td').first.click(); o.wait_for_selector('#rspw'); o.click('#rspw'); o.click('#mok'); o.wait_for_selector('#dlg[open] #cpm'); shot(o, 'mklogin', l); o.click('#mx')
    print('errors:', (o.errs + e.errs + m.errs)[:3]); b.close()
for n in names:
    for l in ('ar', 'en'):
        im = Image.open(f'{OUT}/{n}-{l}.png').convert('RGB'); im = im.resize((480, round(im.height * 480 / im.width)), Image.LANCZOS)
        im.save(os.path.join(DEST, f'{n}-{l}.webp'), 'WEBP', quality=78, method=6)
print('wrote site/img/guide/*.webp:', ', '.join(names))
