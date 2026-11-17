#!/usr/bin/env python3
"""Uptime check (every 10 minutes, from notify.yml): the website, the system, the admin site, Supabase's API and the database.
Tells the Waad team (e-mail and/or WhatsApp) when something goes down, again every hour while it stays down, and when it is back.
State between runs lives in .uptime/state.json (kept by actions/cache). The Actions logs are public: only counts are printed."""
import json, os, re, smtplib, subprocess, time, urllib.request
from email.mime.text import MIMEText

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SITE = 'https://abuomara4.github.io/waad/site/'
src = open(os.path.join(ROOT, 'app/src/core.js'), encoding='utf-8').read()
SB_URL, SB_KEY = re.search(r"url: '([^']+)', key: '([^']+)'", src).groups()
CHECKS = [('الموقع التسويقي', SITE, None), ('النظام', SITE + 'app/', None), ('لوحة الإدارة', SITE + 'admin/', None),
          ('خادم البيانات (Supabase)', SB_URL + '/auth/v1/health', SB_KEY)]
db = re.sub(r'\s', '', os.environ.get('DB', ''))
USER, PW = os.environ.get('NOTIFY_GMAIL_USER', '').strip(), re.sub(r'\s', '', os.environ.get('NOTIFY_GMAIL_APP_PASSWORD', ''))
TO = os.environ.get('NOTIFY_EMAIL_TO', '').strip()
WA_PHONE, WA_KEY = re.sub(r'[^\d+]', '', os.environ.get('CALLMEBOT_PHONE', '')), os.environ.get('CALLMEBOT_APIKEY', '').strip()
STATE = os.path.join(ROOT, '.uptime/state.json')

def http_ok(url, key):
    for attempt in range(3):   # a single slow answer is not an outage
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'waad-uptime', **({'apikey': key} if key else {})})
            with urllib.request.urlopen(req, timeout=20) as r:
                if 200 <= r.status < 400: return True
        except Exception:
            pass
        time.sleep(5)
    return False

def db_ok():
    if not db.startswith(('postgres://', 'postgresql://')): return True   # no secret: nothing to check
    for attempt in range(2):
        try:
            if subprocess.run(['psql', '-X', '-At', '-d', db, '-c', 'select 1'], capture_output=True, text=True, timeout=30).stdout.strip() == '1': return True
        except Exception:
            pass
        time.sleep(5)
    return False

def notify(subject, body):
    sent = False
    if USER and PW and TO:
        try:
            msg = MIMEText(body, 'plain', 'utf-8'); msg['Subject'] = subject; msg['From'] = 'وعد <%s>' % USER; msg['To'] = TO
            with smtplib.SMTP_SSL('smtp.gmail.com', 465, timeout=30) as s: s.login(USER, PW); s.send_message(msg)
            sent = True
        except Exception as e:
            print('::warning::e-mail not sent:', type(e).__name__)
    if WA_PHONE and WA_KEY:
        try:
            q = urllib.parse.urlencode({'phone': WA_PHONE, 'text': subject + '\n' + body, 'apikey': WA_KEY})
            with urllib.request.urlopen('https://api.callmebot.com/whatsapp.php?' + q, timeout=30) as r: sent = sent or r.status == 200
        except Exception as e:
            print('::warning::WhatsApp not sent:', type(e).__name__)
    return sent

import urllib.parse
down = [name for name, url, key in CHECKS if not http_ok(url, key)]
if not db_ok(): down.append('قاعدة البيانات')
try: st = json.load(open(STATE))
except Exception: st = {}
now, prev = time.time(), st.get('down', [])
if down:
    if sorted(down) != sorted(prev) or now - st.get('alerted', 0) >= 3600:
        if notify('وعد: تنبيه توقف — ' + '، '.join(down),
                  'توقف أو لا يستجيب:\n' + '\n'.join('• ' + d for d in down) + '\n\nفُحص ثلاث مرات خلال دقيقة. سيصلك تنبيه كل ساعة ما دام متوقفا، ورسالة عند عودته.\n' + SITE):
            st['alerted'] = now
    st.setdefault('since', now)
elif prev:
    mins = int((now - st.get('since', now)) / 60)
    notify('وعد: عاد كل شيء للعمل', 'عاد للعمل: ' + '، '.join(prev) + '\nمدة التوقف التقريبية: %d دقيقة.' % mins)
    st = {}
st['down'] = down
os.makedirs(os.path.dirname(STATE), exist_ok=True); json.dump(st, open(STATE, 'w'))
print('uptime: %d of %d down' % (len(down), len(CHECKS) + 1))
