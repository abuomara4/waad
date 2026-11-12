"""Regenerates the website's screenshots (site/img/*.webp) from the real system with sample data only.
Run:  bash devserver/start.sh app   (fresh DB)  then  python3 site/screens.py
Needs playwright + pillow. Signs up a throwaway owner on the local mock, loads the demo seed, adds a few
invoices, purchase bills and a payroll run, then captures one screen per module in Arabic and English."""
import os, tempfile
import re, sys, json
from playwright.sync_api import sync_playwright
OUT = tempfile.mkdtemp(); SITE = os.path.dirname(os.path.abspath(__file__)); BASE = 'http://127.0.0.1:54321'; PW = 'Passw0rd!x'
INIT = "window.WAAD_CONFIG={url:'%s',key:'test-publishable-key'}" % BASE
with sync_playwright() as p:
    b = p.chromium.launch()
    ctx = b.new_context(viewport={'width': 1280, 'height': 800}, locale='ar-SA', device_scale_factor=2)
    ctx.add_init_script(INIT); ctx.route(re.compile(r'https://fonts\.(googleapis|gstatic)\.com/.*'), lambda r: r.abort())
    o = ctx.new_page(); errs = []; o.on('pageerror', lambda e: errs.append(str(e)))
    o.goto(BASE + '/waad-app.html?start=signup')
    o.fill('input[name=email]', 'owner@demo.test'); o.fill('input[name=password]', PW); o.fill('input[name=password2]', PW); o.check('input[name=agree]'); o.click('#ab')
    o.wait_for_selector('#cf'); o.fill('#cf input[name=name]', 'مؤسسة الريادة للتجارة'); o.fill('#cf input[name=owner_phone]', '0500000000'); o.fill('#cf input[name=city]', 'الرياض'); o.select_option('#cf select[name=size_band]', '11-50'); o.select_option('#cf select[name=industry]', 'trade'); o.check('#cf input[name=xfer]');  o.fill('#cf input[name=vat]', '300000000000003'); o.click('#cb')
    o.wait_for_selector('#ccok'); o.check('#ccok'); o.click('#mok'); o.wait_for_selector('#dlg', state='hidden')
    res = o.evaluate("""async () => {
      const c = S.cid, out = {};
      await db.rpc('demo_seed', { p_company: c });
      const items = await db.get('items', { company_id: 'eq.' + c, type: 'eq.stock' });
      const today = new Date().toISOString().slice(0, 10);
      for (const it of items) await db.rpc('stock_adjust', { p_company: c, p_item: it.id, p_date: today, p_qty: 40, p_unit_cost: Math.round(it.sale_price * 0.6), p_reason: 'رصيد افتتاحي' });
      const cust = await db.get('parties', { company_id: 'eq.' + c, kind: 'eq.customer' });
      const all = await db.get('items', { company_id: 'eq.' + c });
      const by = Object.fromEntries(all.map(i => [i.code, i]));
      const inv = [[0, [['PRD-01', 6], ['SRV-01', 2]]], [1, [['SRV-02', 3], ['PRD-02', 10]]], [0, [['PRD-01', 4]]]];
      out.invoices = [];
      for (const [ci, lines] of inv) { try { out.invoices.push(await db.rpc('post_sales_invoice', { p_company: c, p_doc: { party: cust[ci % cust.length].id, lines: lines.map(([code, qty]) => ({ item: by[code].id, qty, price: by[code].sale_price })) } })); } catch (e) { out.invoices.push('ERR ' + e.message); } }
      const sup = await db.get('parties', { company_id: 'eq.' + c, kind: 'eq.supplier' });
      out.bills = [];
      for (const [ref, lines] of [['S-2041', [['PRD-01', 15, 1300], ['PRD-02', 20, 390]]], ['S-2057', [['PRD-02', 12, 385]]]]) { try { out.bills.push(await db.rpc('post_purchase_bill', { p_company: c, p_doc: { party: sup[0].id, ref, lines: lines.map(([code, qty, price]) => ({ item: by[code].id, qty, price })) } })); } catch (e) { out.bills.push('ERR ' + e.message); } }
      const d = new Date(); try { out.run = await db.rpc('payroll_prepare', { p_company: c, p_year: d.getFullYear(), p_month: d.getMonth() + 1 }); } catch (e) { out.run = 'ERR ' + e.message; }
      out.projects = (await db.get('projects', { company_id: 'eq.' + c })).map(p => p.id);
      return out; }""")
    print(json.dumps(res, ensure_ascii=False)[:600])
    # e-invoicing: link the sample company to Fatoora on the local mock only, post one invoice and mark it cleared (no ZATCA call)
    import urllib.request
    def mx(q): urllib.request.urlopen(urllib.request.Request(BASE + '/mock/exec', data=json.dumps({'q': q}).encode(), headers={'Content-Type': 'application/json'}))
    cid = o.evaluate('S.cid')
    mx(f"insert into zatca_settings(company_id, enabled, env, onboarded_at) values ('{cid}', true, 'simulation', now()) on conflict (company_id) do update set enabled = true")
    mx(f"update parties set vat_no = '310000000000003' where id = (select id from parties where company_id = '{cid}' and kind = 'customer' order by name limit 1)")
    zinv = o.evaluate("""async () => { const c = S.cid, cust = await db.get('parties', { company_id: 'eq.' + c, kind: 'eq.customer' }), all = await db.get('items', { company_id: 'eq.' + c });
      const by = Object.fromEntries(all.map(i => [i.code, i]));
      return db.rpc('post_sales_invoice_sn', { p_company: c, p_doc: { party: cust.find(p => p.vat_no).id, lines: [['PRD-01', 3], ['SRV-01', 2]].map(([k, q]) => ({ item: by[k].id, qty: q, price: by[k].sale_price })) } }); }""")
    mx(f"update zatca_docs set status = 'cleared', sent_at = now() where doc_id = '{zinv}'")
    shots = [('hr', '#/hrdash'), ('finance', '#/reports'), ('marketing', '#/marketing'), ('purch', '#/purchases'), ('stock', '#/items'), ('project', '#/projects/' + (res['projects'] or [''])[0]), ('forms', '#/forms'), ('invoice', '#/sales/' + zinv)]
    for lang in ('ar', 'en'):
        o.evaluate("l => localStorage.setItem('waad.lang', JSON.stringify(l))", lang); o.reload(); o.wait_for_selector('#nav')
        for name, route in shots:
            o.evaluate("h => location.hash = h", route); o.mouse.move(1279, 799); o.wait_for_timeout(1500); o.screenshot(path=f'{OUT}/{name}-{lang}.png')
    print('errors:', errs[:3]); b.close()
from PIL import Image
for name, _ in shots:
    for lang in ('ar', 'en'):
        im = Image.open(f'{OUT}/{name}-{lang}.png').convert('RGB').resize((1280, 800), Image.LANCZOS)
        im.save(os.path.join(SITE, 'img', f'{name}-{lang}.webp'), 'WEBP', quality=80, method=6)
print('wrote site/img/*.webp')
