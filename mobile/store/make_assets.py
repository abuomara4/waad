"""Store images for Google Play and the App Store, from the official logo and the real system with sample data only.
Run:  bash devserver/start.sh app   (fresh DB)  then  python3 mobile/store/make_assets.py
Writes into mobile/store/: play-icon-512.png, play-feature-1024x500.png, ios-icon-1024.png,
phone/ar-*.png (1080x1920, Google Play) and iphone/ar-*.png (1290x2796, App Store 6.7"/6.9")."""
import os, re
from playwright.sync_api import sync_playwright
from PIL import Image
D = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(D, '..', '..'); BASE = 'http://127.0.0.1:54321'; PW = 'Passw0rd!x'
logo = re.search(r"LOGO_D = '(data:image/webp;base64,[^']+)'", open(os.path.join(ROOT, 'app', 'src', 'core.js'), encoding='utf-8').read()).group(1)
FONT = '<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;600;700&display=swap" rel="stylesheet">'
BG = 'background:radial-gradient(900px 420px at 88% -10%,rgba(184,137,58,.30),transparent 60%),radial-gradient(700px 420px at 0% 110%,rgba(37,99,235,.30),transparent 60%),#131B2E'
CAPS = [('#/home', 'كل ما يحتاجك اليوم في مكان واحد'), ('#/employees', 'ملف كامل لكل موظف بعقوده ووثائقه'), ('#/payroll/{run}', 'مسير الرواتب حسب نظام العمل'),
        ('#/hrdash', 'لوحة الموارد البشرية بالأرقام'), ('#/compliance', 'الامتثال في صفحة واحدة'), ('#/sales', 'فواتير متوافقة مع زاتكا')]
os.makedirs(os.path.join(D, 'phone'), exist_ok=True); os.makedirs(os.path.join(D, 'iphone'), exist_ok=True)
with sync_playwright() as p:
    b = p.chromium.launch()
    # icons and the Play feature graphic (no transparency: both stores want an opaque square icon)
    pg = b.new_page(viewport={'width': 1024, 'height': 1024})
    pg.set_content(f'<!doctype html><html><body style="margin:0;width:1024px;height:1024px;{BG};display:flex;align-items:center;justify-content:center"><img src="{logo}" style="width:660px"></body></html>')
    pg.wait_for_timeout(300); pg.screenshot(path=os.path.join(D, 'ios-icon-1024.png'))
    Image.open(os.path.join(D, 'ios-icon-1024.png')).convert('RGB').resize((512, 512), Image.LANCZOS).save(os.path.join(D, 'play-icon-512.png'))
    pg.set_viewport_size({'width': 1024, 'height': 500})
    pg.set_content(f'''<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">{FONT}</head><body style="margin:0;width:1024px;height:500px;{BG};color:#fff;font-family:'IBM Plex Sans Arabic',sans-serif;display:flex;align-items:center;justify-content:space-between;padding:0 70px;box-sizing:border-box">
      <div><div style="font-size:52px;font-weight:700;line-height:1.3">منشأتك كاملة،<br>في <span style="color:#C9B27B">نظام واحد</span></div><div style="font-size:26px;color:#cbd5e1;margin-top:14px">الموارد البشرية والرواتب والمالية · عربي وإنجليزي</div></div>
      <img src="{logo}" style="width:300px"></body></html>''', wait_until='networkidle')
    pg.wait_for_timeout(500); pg.screenshot(path=os.path.join(D, 'play-feature-1024x500.png')); pg.close()
    # screenshots: a sample company on the local mock, with a caption band on top
    ctx = b.new_context(viewport={'width': 412, 'height': 732}, device_scale_factor=2.625, locale='ar-SA', color_scheme='light', is_mobile=True, has_touch=True)
    ctx.add_init_script("window.WAAD_CONFIG={url:'%s',key:'test-publishable-key'}" % BASE)
    o = ctx.new_page(); o.goto(BASE + '/waad-app.html?start=signup')
    o.fill('input[name=email]', 'store@demo.test'); o.fill('input[name=password]', PW); o.fill('input[name=password2]', PW); o.check('input[name=agree]'); o.click('#ab')
    o.wait_for_selector('#cf'); o.fill('#cf input[name=name]', 'مؤسسة الريادة للتجارة'); o.fill('#cf input[name=owner_phone]', '0500000000'); o.fill('#cf input[name=city]', 'الرياض')
    o.select_option('#cf select[name=size_band]', '11-50'); o.select_option('#cf select[name=industry]', 'trade'); o.check('#cf input[name=xfer]'); o.fill('#cf input[name=vat]', '300000000000003'); o.click('#cb')
    o.wait_for_selector('#ccok'); o.check('#ccok'); o.click('#mok'); o.wait_for_selector('#dlg', state='hidden')
    run = o.evaluate("""async () => { const c = S.cid; await db.rpc('demo_seed', { p_company: c }); const d = new Date();
      const emp = (await db.get('employees', { company_id: 'eq.' + c, order: 'emp_no', limit: 1 }))[0];
      try { await db.upd('members', { company_id: 'eq.' + c, user_id: 'eq.' + S.session.user.id }, { employee_id: emp.id }); } catch (e) {}
      const items = await db.get('items', { company_id: 'eq.' + c, type: 'eq.stock' }), td = d.toISOString().slice(0, 10);
      for (const it of items) await db.rpc('stock_adjust', { p_company: c, p_item: it.id, p_date: td, p_qty: 40, p_unit_cost: Math.round(it.sale_price * 0.6), p_reason: 'رصيد افتتاحي' });
      const cust = await db.get('parties', { company_id: 'eq.' + c, kind: 'eq.customer' }), all = await db.get('items', { company_id: 'eq.' + c }), by = Object.fromEntries(all.map(i => [i.code, i]));
      for (const [ci, lines] of [[0, [['PRD-01', 6], ['SRV-01', 2]]], [1, [['SRV-02', 3], ['PRD-02', 10]]], [0, [['PRD-01', 4]]]]) { try { await db.rpc('post_sales_invoice', { p_company: c, p_doc: { party: cust[ci % cust.length].id, lines: lines.map(([k, q]) => ({ item: by[k].id, qty: q, price: by[k].sale_price })) } }); } catch (e) {} }
      return db.rpc('payroll_prepare', { p_company: c, p_year: d.getFullYear(), p_month: d.getMonth() + 1 }); }""")
    o.reload(); o.wait_for_selector('#nav', state='attached')
    for i, (route, cap) in enumerate(CAPS, 1):
        o.evaluate("h => location.hash = h", route.format(run=run)); o.wait_for_timeout(1500); o.evaluate("() => { const b = document.getElementById('subbar'); if (b) b.style.display = 'none'; }")
        o.evaluate("""t => { let c = document.getElementById('storecap'); if (!c) { c = document.createElement('div'); c.id = 'storecap';
          c.style.cssText = 'position:fixed;left:0;right:0;bottom:0;z-index:99999;background:#131B2E;color:#fff;font:700 19px/1.5 system-ui,sans-serif;padding:16px 18px 22px;text-align:center';
          document.body.appendChild(c); } c.textContent = t; }""", cap)
        path = os.path.join(D, 'phone', f'ar-{i}.png'); o.screenshot(path=path)
        Image.open(path).convert('RGB').resize((1080, 1920), Image.LANCZOS).save(path)
        Image.open(path).resize((1290, 2296), Image.LANCZOS).crop((0, 0, 1290, 2296)).save(os.path.join(D, 'iphone', 'tmp.png'))
        im = Image.new('RGB', (1290, 2796), (19, 27, 46)); im.paste(Image.open(os.path.join(D, 'iphone', 'tmp.png')), (0, 250)); im.save(os.path.join(D, 'iphone', f'ar-{i}.png'))
    os.remove(os.path.join(D, 'iphone', 'tmp.png')); b.close()
print('wrote mobile/store images')
