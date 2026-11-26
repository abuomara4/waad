"""Screens for the Remotion tour (video/public/shots/<lang>/<name>-desk.png and -phone.png), high resolution, sample data only.
Run:  bash devserver/start.sh app   (fresh DB)  then  python3 video/capture.py
Signs up a throwaway owner on the local mock, loads the demo seed, then captures each screen in Arabic and English at
computer size (1440x900 @2x) and phone size (412x732 @2.625x), with the trial bar hidden."""
import json, os, re
from playwright.sync_api import sync_playwright
BASE = 'http://127.0.0.1:54321'; PW = 'Passw0rd!x'
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'public', 'shots')
INIT = "window.WAAD_CONFIG={url:'%s',key:'test-publishable-key'}" % BASE
SCREENS = [('home', '#/home'), ('employees', '#/employees'), ('payroll', '#/payroll/{run}'), ('compliance', '#/compliance'),
           ('invoice', '#/sales/{inv}'), ('reports', '#/reports'), ('items', '#/items'), ('att', '#/att'), ('dash', '#/hrdash')]
FOCUS = {'home': '.kpi', 'employees': '#page table', 'payroll': '#page table', 'compliance': '.kpi', 'invoice': 'svg.qr, img.qr, .qr, canvas',
         'reports': '#page table', 'items': '#page table', 'att': '#page table', 'dash': '.kpi'}
RECT = """sel => { const els = [...document.querySelectorAll(sel)].filter(e => { const r = e.getBoundingClientRect(); return r.width > 4 && r.height > 4 && r.top < innerHeight && r.bottom > 0; });
  if (!els.length) return null; let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
  for (const e of els) { const r = e.getBoundingClientRect(); x0 = Math.min(x0, r.left); y0 = Math.min(y0, r.top); x1 = Math.max(x1, r.right); y1 = Math.max(y1, r.bottom); }
  x0 = Math.max(0, x0); y0 = Math.max(0, y0); x1 = Math.min(innerWidth, x1); y1 = Math.min(innerHeight, y1);
  return [x0 / innerWidth, y0 / innerHeight, (x1 - x0) / innerWidth, (y1 - y0) / innerHeight].map(v => Math.round(v * 1000) / 1000); }"""
focus = {}
HIDE = "() => { for (const id of ['subbar','setupg']) { const b = document.getElementById(id); if (b) b.style.display = 'none'; } }"
with sync_playwright() as p:
    b = p.chromium.launch()
    ctx = b.new_context(viewport={'width': 1440, 'height': 900}, locale='ar-SA')
    ctx.add_init_script(INIT); ctx.route(re.compile(r'https://fonts\.(googleapis|gstatic)\.com/.*'), lambda r: r.abort())
    o = ctx.new_page(); o.goto(BASE + '/waad-app.html?start=signup')
    o.fill('input[name=email]', 'video@demo.test'); o.fill('input[name=password]', PW); o.fill('input[name=password2]', PW); o.check('input[name=agree]'); o.click('#ab')
    o.wait_for_selector('#cf'); o.fill('#cf input[name=name]', 'مؤسسة الريادة للتجارة'); o.fill('#cf input[name=owner_phone]', '0500000000'); o.fill('#cf input[name=city]', 'الرياض')
    o.select_option('#cf select[name=size_band]', '11-50'); o.select_option('#cf select[name=industry]', 'trade'); o.check('#cf input[name=xfer]'); o.fill('#cf input[name=vat]', '300000000000003'); o.click('#cb')
    o.wait_for_selector('#ccok'); o.check('#ccok'); o.click('#mok'); o.wait_for_selector('#dlg', state='hidden')
    ids = o.evaluate("""async () => { const c = S.cid; await db.rpc('demo_seed', { p_company: c }); const d = new Date();
      try { await db.upd('companies', { id: 'eq.' + c }, { name_en: 'Al Riyadah Trading' }); } catch (e) {}
      const items = await db.get('items', { company_id: 'eq.' + c, type: 'eq.stock' }), td = d.toISOString().slice(0, 10);
      for (const it of items) await db.rpc('stock_adjust', { p_company: c, p_item: it.id, p_date: td, p_qty: 40, p_unit_cost: Math.round(it.sale_price * 0.6), p_reason: 'رصيد افتتاحي' });
      const cust = await db.get('parties', { company_id: 'eq.' + c, kind: 'eq.customer' }), all = await db.get('items', { company_id: 'eq.' + c }), by = Object.fromEntries(all.map(i => [i.code, i]));
      let inv = null;
      for (const [ci, lines] of [[0, [['PRD-01', 6], ['SRV-01', 2]]], [1, [['SRV-02', 3], ['PRD-02', 10]]]]) { try { inv = await db.rpc('post_sales_invoice', { p_company: c, p_doc: { party: cust[ci % cust.length].id, lines: lines.filter(([k]) => by[k]).map(([k, q]) => ({ item: by[k].id, qty: q, price: by[k].sale_price })) } }); } catch (e) {} }
      const run = await db.rpc('payroll_prepare', { p_company: c, p_year: d.getFullYear(), p_month: d.getMonth() + 1 });
      return { run, inv }; }""")
    state = ctx.storage_state(); ctx.close()
    for lang in ('ar', 'en'):
        os.makedirs(os.path.join(OUT, lang), exist_ok=True)
        for kind, vp, dsf, mob in (('desk', {'width': 1440, 'height': 900}, 2, False), ('phone', {'width': 412, 'height': 732}, 2.625, True)):
            c = b.new_context(viewport=vp, device_scale_factor=dsf, is_mobile=mob, has_touch=mob, locale='ar-SA', color_scheme='light', storage_state=state)
            c.add_init_script(INIT); c.add_init_script("localStorage.setItem('waad.lang', JSON.stringify('%s'))" % lang)
            c.route(re.compile(r'https://fonts\.(googleapis|gstatic)\.com/.*'), lambda r: r.abort())
            v = c.new_page(); v.goto(BASE + '/waad-app.html#/home'); v.wait_for_selector('#nav', state='attached')
            for name, route in SCREENS:
                v.evaluate("h => location.hash = h", route.format(run=ids['run'], inv=ids['inv'] or '')); v.wait_for_timeout(1600); v.evaluate(HIDE)
                v.mouse.move(vp['width'] - 1, vp['height'] - 1); v.wait_for_timeout(200)
                v.screenshot(path=os.path.join(OUT, lang, f'{name}-{kind}.png'))
                focus[f'{lang}/{name}-{kind}'] = v.evaluate(RECT, FOCUS[name])
            c.close()
        print(lang, 'done')
    b.close()
    open(os.path.join(OUT, 'focus.json'), 'w').write(json.dumps(focus, indent=1))
