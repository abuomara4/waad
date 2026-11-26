"""The website's short tour video (site/img/tour-ar.mp4, tour-en.mp4 + posters) recorded from the real system with sample data only.
Run:  bash devserver/start.sh app   (fresh DB)  then  python3 site/tour.py
Needs playwright + pillow + imageio-ffmpeg (bundles ffmpeg). Signs up a throwaway owner on the local mock, loads the demo seed,
then walks through the main screens with a caption on each, in Arabic and in English, at computer size (1280x720) and at phone size
(390x844, files *-m.mp4). The brand intro (site/img/intro-wide.mp4 / intro-tall.mp4, from the owner's video) opens each one.
Chapters (seconds, intro included) are printed for home.html."""
import json, os, re, shutil, subprocess, tempfile
from playwright.sync_api import sync_playwright
import imageio_ffmpeg
SITE = os.path.dirname(os.path.abspath(__file__)); BASE = 'http://127.0.0.1:54321'; PW = 'Passw0rd!x'; OUT = tempfile.mkdtemp()
INIT = "window.WAAD_CONFIG={url:'%s',key:'test-publishable-key'}" % BASE
HOLD = 4200   # ms on each screen
STEPS = [   # route, Arabic caption, English caption
    ('#/home', 'الرئيسية: ما يحتاجك اليوم في مكان واحد', 'Home: what needs you today, in one place'),
    ('#/employees', 'الموظفون: ملف كامل لكل موظف بعقوده ووثائقه', 'Employees: a full file per employee with contracts and documents'),
    ('#/att', 'الحضور والانصراف من الجوال بالموقع', 'Attendance from the phone, by location'),
    ('#/payroll/{run}', 'مسير الرواتب يُحسب تلقائيا حسب نظام العمل، ويُعتمد على ثلاث مراحل', 'Payroll calculated by the Labor Law, approved in three steps'),
    ('#/compliance', 'الامتثال: حماية الأجور والتأمينات والوثائق والعقود في صفحة واحدة', 'Compliance: wage protection, GOSI, documents and contracts on one page'),
    ('#/sales', 'فواتير إلكترونية متوافقة مع زاتكا', 'E-invoices compatible with ZATCA'),
    ('#/reports', 'القوائم المالية تُحدَّث مع كل عملية', 'Financial statements updated with every transaction'),
    ('#/items', 'المخزون والأصناف', 'Stock and items'),
    ('#/forms', 'أكثر من 100 نموذج جاهز بالعربي والإنجليزي', 'Over 100 ready forms in Arabic and English'),
]
CAP = """(t) => { let c = document.getElementById('tourcap'); if (!c) { c = document.createElement('div'); c.id = 'tourcap';
  c.style.cssText = 'position:fixed;left:50%;bottom:26px;transform:translateX(-50%);z-index:99999;background:rgba(20,32,57,.92);color:#fff;font:600 21px/1.5 system-ui,sans-serif;padding:12px 26px;border-radius:14px;box-shadow:0 10px 30px rgba(0,0,0,.25);max-width:88%;text-align:center';
  document.body.appendChild(c); } c.textContent = t; }"""
CARD = """([t, s]) => { let c = document.getElementById('tourcard'); if (!t) { if (c) c.remove(); return; } if (!c) { c = document.createElement('div'); c.id = 'tourcard';
  c.style.cssText = 'position:fixed;inset:0;z-index:100000;background:#142039;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;font-family:system-ui,sans-serif;text-align:center';
  document.body.appendChild(c); } c.innerHTML = '<img src="' + LOGO_D + '" style="height:90px" alt=""><div style="font:700 40px/1.3 system-ui">' + t + '</div><div style="font:500 22px/1.5 system-ui;color:#C9B27B">' + s + '</div>'; }"""
with sync_playwright() as p:
    b = p.chromium.launch()
    ctx = b.new_context(viewport={'width': 1280, 'height': 720}, locale='ar-SA')
    ctx.add_init_script(INIT); ctx.route(re.compile(r'https://fonts\.(googleapis|gstatic)\.com/.*'), lambda r: r.abort())
    o = ctx.new_page()
    o.goto(BASE + '/waad-app.html?start=signup')
    o.fill('input[name=email]', 'owner@demo.test'); o.fill('input[name=password]', PW); o.fill('input[name=password2]', PW); o.check('input[name=agree]'); o.click('#ab')
    o.wait_for_selector('#cf'); o.fill('#cf input[name=name]', 'مؤسسة الريادة للتجارة'); o.fill('#cf input[name=owner_phone]', '0500000000'); o.fill('#cf input[name=city]', 'الرياض'); o.select_option('#cf select[name=size_band]', '11-50'); o.select_option('#cf select[name=industry]', 'trade'); o.check('#cf input[name=xfer]'); o.fill('#cf input[name=vat]', '300000000000003'); o.click('#cb')
    o.wait_for_selector('#ccok'); o.check('#ccok'); o.click('#mok'); o.wait_for_selector('#dlg', state='hidden')
    run = o.evaluate("""async () => { const c = S.cid; await db.rpc('demo_seed', { p_company: c });
      const items = await db.get('items', { company_id: 'eq.' + c, type: 'eq.stock' }), today = new Date().toISOString().slice(0, 10);
      for (const it of items) await db.rpc('stock_adjust', { p_company: c, p_item: it.id, p_date: today, p_qty: 40, p_unit_cost: Math.round(it.sale_price * 0.6), p_reason: 'رصيد افتتاحي' });
      const cust = await db.get('parties', { company_id: 'eq.' + c, kind: 'eq.customer' }), all = await db.get('items', { company_id: 'eq.' + c }), by = Object.fromEntries(all.map(i => [i.code, i]));
      for (const [ci, lines] of [[0, [['PRD-01', 6], ['SRV-01', 2]]], [1, [['SRV-02', 3], ['PRD-02', 10]]]]) { try { await db.rpc('post_sales_invoice', { p_company: c, p_doc: { party: cust[ci % cust.length].id, lines: lines.map(([k, q]) => ({ item: by[k].id, qty: q, price: by[k].sale_price, vat_rate: 15 })) } }); } catch (e) {} }
      const d = new Date(); const run = await db.rpc('payroll_prepare', { p_company: c, p_year: d.getFullYear(), p_month: d.getMonth() + 1 }); await db.rpc('payroll_sign', { p_run: run }); return run; }""")
    state = ctx.storage_state(); ctx.close()
    chapters = {}
    INTRO_S = 10.0
    for lang, sfx, vw, vh, dsf, intro in [(l, s_, w, h, d, i) for l in ('ar', 'en') for (s_, w, h, d, i) in (('', 1280, 720, 1, 'intro-wide.mp4'), ('-m', 390, 844, 2, 'intro-tall.mp4'))]:
        RW, RH = vw * dsf, vh * dsf
        vctx = b.new_context(viewport={'width': vw, 'height': vh}, is_mobile=dsf > 1, has_touch=dsf > 1, locale='ar-SA', color_scheme='light', storage_state=state, record_video_dir=OUT, record_video_size={'width': vw, 'height': vh})   # recorded at CSS size, enlarged ×dsf below
        vctx.add_init_script(INIT); vctx.add_init_script("localStorage.setItem('waad.lang', JSON.stringify('%s'))" % lang)
        vctx.route(re.compile(r'https://fonts\.(googleapis|gstatic)\.com/.*'), lambda r: r.abort())
        v = vctx.new_page(); v.goto(BASE + '/waad-app.html#/home'); v.wait_for_selector('#nav')
        en = lang == 'en'
        v.evaluate(CARD, ['Waad' if en else 'وعد', 'HR and finance for Saudi companies, in one system' if en else 'الموارد البشرية والمالية للمنشآت السعودية في نظام واحد']); v.wait_for_timeout(3000)
        v.evaluate(CARD, [None, None]); t = 3.0 + INTRO_S; chapters[lang + sfx] = []
        for route, ar, en_t in STEPS:
            v.evaluate("h => location.hash = h", route.format(run=run)); v.mouse.move(vw - 1, vh - 1); v.wait_for_timeout(700)
            v.evaluate(CAP, en_t if en else ar); chapters[lang + sfx].append([round(t, 1), en_t if en else ar])
            v.mouse.wheel(0, 260); v.wait_for_timeout(HOLD // 2); v.mouse.wheel(0, -260); v.wait_for_timeout(HOLD // 2); t += (700 + HOLD) / 1000
        v.evaluate("() => { const c = document.getElementById('tourcap'); if (c) c.remove(); }")
        v.evaluate(CARD, ['Try Waad free for 14 days' if en else 'جرّب وعد 14 يوما مجانا', 'abuomara4.github.io/waad/site']); v.wait_for_timeout(3500)
        path = v.video.path(); vctx.close()
        ff = imageio_ffmpeg.get_ffmpeg_exe(); mp4 = os.path.join(SITE, 'img', f'tour-{lang}{sfx}.mp4')
        dur = subprocess.run([ff, '-i', path], capture_output=True, text=True).stderr
        h_, m_, s_ = re.search(r'Duration: (\d+):(\d+):([\d.]+)', dur).groups(); dur = int(h_) * 3600 + int(m_) * 60 + float(s_) - 0.6
        # the intro (scaled to cover the frame) + the recording, one file; the tour part has a silent track so the intro keeps its sound
        fc = (f'[0:v]scale={RW}:{RH}:force_original_aspect_ratio=increase,crop={RW}:{RH},fps=25,setsar=1,format=yuv420p[iv];'
              f'[1:v]trim=start=0.6,setpts=PTS-STARTPTS,scale={RW}:{RH}:flags=lanczos,fps=25,setsar=1,format=yuv420p[tv];'
              '[0:a]aresample=44100,aformat=channel_layouts=stereo[ia];[2:a]aformat=channel_layouts=stereo[ta];[iv][ia][tv][ta]concat=n=2:v=1:a=1[v][a]')
        subprocess.run([ff, '-y', '-loglevel', 'error', '-i', os.path.join(SITE, 'img', intro), '-i', path, '-f', 'lavfi', '-t', f'{dur:.2f}', '-i', 'anullsrc=r=44100:cl=stereo',
                        '-filter_complex', fc, '-map', '[v]', '-map', '[a]', '-c:v', 'libx264', '-preset', 'slow', '-crf', '30', '-c:a', 'aac', '-b:a', '64k', '-movflags', '+faststart', mp4], check=True)
        subprocess.run([ff, '-y', '-loglevel', 'error', '-ss', str(INTRO_S - 0.4), '-i', mp4, '-frames:v', '1', '-q:v', '4', os.path.join(OUT, f'poster-{lang}{sfx}.png')], check=True)
        from PIL import Image
        Image.open(os.path.join(OUT, f'poster-{lang}{sfx}.png')).convert('RGB').save(os.path.join(SITE, 'img', f'tour-{lang}{sfx}.webp'), 'WEBP', quality=78, method=6)
        print(lang + sfx, os.path.getsize(mp4) // 1024, 'KB')
    b.close()
print(json.dumps(chapters, ensure_ascii=False))
shutil.rmtree(OUT, ignore_errors=True)
