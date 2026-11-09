"""Records a step-by-step walkthrough (owner signup → company → self → employee → invite) against the local emulator."""
import re
from playwright.sync_api import sync_playwright
from PIL import Image

BASE = 'http://127.0.0.1:54321'
OUT = '/tmp/claude-0/demo'
import os; os.makedirs(OUT, exist_ok=True)
frames = []

def cap(p, n, text, hi=None):
    p.evaluate("""([t, hi]) => {
      document.querySelectorAll('.__cap,.__hi').forEach(e => e.remove());
      const d = document.createElement('div'); d.className = '__cap';
      d.style.cssText = 'position:fixed;top:0;left:0;right:0;z-index:9999;background:#2563eb;color:#fff;font:600 17px "IBM Plex Sans Arabic",Tahoma;padding:10px 14px;text-align:center;direction:rtl;line-height:1.6';
      d.textContent = t; document.body.appendChild(d);
      if (hi) { const el = document.querySelector(hi); if (el) { el.style.outline = '3px solid #f59e0b'; el.style.outlineOffset = '3px'; el.classList.add('__hiel'); } }
    }""", [text, hi])
    p.wait_for_timeout(250)
    path = f'{OUT}/{n:02d}.png'; p.screenshot(path=path); frames.append(path)
    p.evaluate("document.querySelectorAll('.__hiel').forEach(e => { e.style.outline = ''; e.classList.remove('__hiel'); })")

with sync_playwright() as pw:
    b = pw.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome')
    ctx = b.new_context(viewport={'width': 390, 'height': 760}, device_scale_factor=2, locale='ar-SA')
    ctx.add_init_script("window.WAAD_CONFIG={url:'%s',key:'test-publishable-key'}" % BASE)
    ctx.route(re.compile(r'https://fonts\.(googleapis|gstatic)\.com/.*'), lambda r: r.abort())
    p = ctx.new_page(); p.goto(BASE + '/waad-app.html'); p.wait_for_selector('.tabs')
    cap(p, 1, '1) افتح الرابط واضغط «حساب جديد»', '.tabs button[data-t=up]')
    p.click('.tabs button[data-t=up]')
    p.fill('input[name=email]', 'owner@example.com'); p.fill('input[name=password]', 'Waad2026!x'); p.fill('input[name=password2]', 'Waad2026!x')
    cap(p, 2, '2) اكتب بريدك وكلمة مرور (8 أحرف أو أكثر) مرتين، ثم «إنشاء الحساب»', '#ab')
    p.click('#ab'); p.wait_for_selector('#cf')
    cap(p, 3, '3) بعد الدخول تظهر هذه الصفحة — أنت صاحب منشأة، فاستخدم الجزء الثاني «أنشئ منشأة جديدة»', '#cf')
    p.fill('#cf input[name=name]', 'مؤسسة التجربة')
    cap(p, 4, '4) اكتب اسم المنشأة (الضريبي والسجل اختياريان) واضغط «إنشاء المنشأة»', '#cb')
    p.click('#cb'); p.wait_for_selector('text=جهّز منشأتك')
    cap(p, 5, '5) أُنشئت المنشأة وصرت المالك. أول خطوة: «إضافة بياناتي»', '#me')
    p.click('#me')
    p.fill('#dlg input[name=full_name]', 'عبدالعزيز (تجربة)'); p.fill('#dlg input[name=job_title]', 'المدير العام')
    p.fill('#dlg input[name=hire_date]', '2020-01-01'); p.fill('#dlg input[name=basic]', '20000'); p.fill('#dlg input[name=housing]', '5000')
    cap(p, 6, '6) عبّئ بياناتك كموظف (الاسم، المباشرة، الراتب) ثم «حفظ»', '#mok')
    p.click('#mok'); p.wait_for_selector('#dlg', state='hidden'); p.wait_for_timeout(500)
    p.evaluate("location.hash='#/employees'"); p.wait_for_selector('#ne')
    cap(p, 7, '7) من القائمة ☰ ← «الموظفون» ← «إضافة موظف»', '#ne')
    p.click('#ne')
    p.fill('#dlg input[name=full_name]', 'موظف تجريبي'); p.fill('#dlg input[name=basic]', '6000'); p.fill('#dlg input[name=housing]', '1500')
    p.select_option('#dlg select[name=manager_id]', index=1)
    cap(p, 8, '8) أدخل بيانات الموظف واختر مديره المباشر ثم «حفظ»', '#mok')
    p.click('#mok'); p.wait_for_selector('#dlg', state='hidden'); p.wait_for_timeout(500)
    p.evaluate("location.hash='#/users'"); p.wait_for_selector('#ni'); p.click('#ni')
    p.fill('#dlg input[name=email]', 'employee@example.com'); p.select_option('#dlg select[name=emp]', index=1)
    cap(p, 9, '9) «المستخدمون والدعوات» ← «دعوة مستخدم»: بريد الموظف + دوره + سجله', '#mok')
    p.click('#mok'); p.wait_for_selector('#dlg[open] #ic'); p.wait_for_timeout(400)
    cap(p, 10, '10) يظهر رمز الدعوة — انسخه أو انسخ الرسالة الجاهزة وأرسلها للموظف', '#ic')
    p.click('#mx'); p.wait_for_timeout(300)
    p.evaluate("location.hash='#/home'"); p.wait_for_timeout(700)
    cap(p, 11, 'جاهز ✓ — هذه رئيستك، وكل قسم يظهر حسب صلاحيتك')
    b.close()

imgs = [Image.open(f).convert('RGB') for f in frames]
w = 600; imgs = [i.resize((w, int(i.height * w / i.width))) for i in imgs]
imgs[0].save('/mnt/user-data/outputs/waad-walkthrough.gif', save_all=True, append_images=imgs[1:], duration=3200, loop=0, optimize=True)
# also a single tall sheet of all steps
cols = 3; rows = (len(imgs) + cols - 1) // cols; tw, th = 300, int(imgs[0].height * 300 / w)
sheet = Image.new('RGB', (cols * tw + (cols + 1) * 12, rows * th + (rows + 1) * 12), (241, 245, 249))
for k, im in enumerate(imgs):
    sheet.paste(im.resize((tw, th)), (12 + (k % cols) * (tw + 12), 12 + (k // cols) * (th + 12)))
sheet.save('/mnt/user-data/outputs/waad-steps.png')
print(len(frames), 'frames')
