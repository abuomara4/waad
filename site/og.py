"""Renders site/og.png (1200x630), the preview image shown when the landing page link is shared (WhatsApp, X, LinkedIn).
Run: python3 site/og.py  (needs playwright + chromium). Uses the official logo from app/src/core.js."""
import os, re
from playwright.sync_api import sync_playwright
D = os.path.dirname(os.path.abspath(__file__))
logo = re.search(r"LOGO_D = '(data:image/webp;base64,[^']+)'", open(os.path.join(D, '..', 'app', 'src', 'core.js'), encoding='utf-8').read()).group(1)
html = '''<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;600;700&display=swap" rel="stylesheet">
<style>*{box-sizing:border-box;margin:0}body{width:1200px;height:630px;font-family:"IBM Plex Sans Arabic",sans-serif;color:#fff;
background:radial-gradient(900px 420px at 88% -10%,rgba(184,137,58,.30),transparent 60%),radial-gradient(700px 420px at 0% 110%,rgba(37,99,235,.30),transparent 60%),#131b2e;
padding:70px 80px;display:flex;flex-direction:column;justify-content:space-between}
img{height:84px;align-self:flex-start}h1{font-size:60px;line-height:1.25;font-weight:700}h1 b{color:#d6ad5e}
p{font-size:30px;color:#cbd5e1;margin-top:18px;line-height:1.6}.tags{display:flex;gap:14px;flex-wrap:wrap}
.tags span{border:1px solid rgba(255,255,255,.22);border-radius:999px;padding:8px 22px;font-size:24px;color:#e2e8f0}</style></head><body>
<img src="LOGO">
<div><h1>منشأتك كاملة، في <b>نظام واحد</b></h1><p>نظام سعودي للمنشآت الصغيرة والمتوسطة. جرّبه ٧ أيام مجاناً.</p></div>
<div class="tags"><span>نظام العمل</span><span>ضريبة القيمة المضافة</span><span>حماية الأجور</span><span>عربي وإنجليزي</span></div>
</body></html>'''.replace('LOGO', logo)
with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(viewport={'width': 1200, 'height': 630})
    pg.set_content(html, wait_until='networkidle'); pg.wait_for_timeout(500)
    pg.screenshot(path=os.path.join(D, 'og.png')); b.close()
print('wrote site/og.png', os.path.getsize(os.path.join(D, 'og.png')), 'bytes')
