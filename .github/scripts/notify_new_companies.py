"""Tells the Waad team about companies waiting for approval (status 'pending', not yet notified).
Run by .github/workflows/notify.yml every 10 minutes. Channels (each optional, set as repository secrets):
  e-mail   : NOTIFY_GMAIL_USER + NOTIFY_GMAIL_APP_PASSWORD (a Google «App password»), sent to NOTIFY_EMAIL_TO or to itself
  WhatsApp : CALLMEBOT_PHONE + CALLMEBOT_APIKEY (free CallMeBot key for your own number)
A request is marked as notified only after at least one channel delivered it; with no channel set nothing is marked."""
import json, os, re, smtplib, subprocess, sys, urllib.parse, urllib.request
from email.mime.text import MIMEText

ADMIN = 'https://abuomara4.github.io/waad/site/admin/'
db = re.sub(r'\s', '', os.environ.get('DB', ''))
if not db.startswith(('postgres://', 'postgresql://')):
    print('::error::SUPABASE_DB_URL is missing or not a connection URI'); sys.exit(1)

def psql(q):
    return subprocess.run(['psql', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', db, '-c', q], check=True, capture_output=True, text=True).stdout.strip()

rows = json.loads(psql("""select coalesce(json_agg(x), '[]') from (
  select s.company_id, c.name, to_char(c.created_at at time zone 'Asia/Riyadh', 'YYYY-MM-DD HH24:MI') as at,
         (select u.email from public.members m join auth.users u on u.id = m.user_id where m.company_id = c.id and m.role = 'owner' limit 1) as email
    from public.company_subscriptions s join public.companies c on c.id = s.company_id
   where s.status = 'pending' and s.notified_at is null order by c.created_at limit 20) x"""))
if not rows:
    print('no new requests'); sys.exit(0)

lines = ['• %s — %s — %s' % (r['name'], r['email'] or '—', r['at']) for r in rows]
title = 'وعد: %d طلب تجربة جديد' % len(rows) if len(rows) > 1 else 'وعد: طلب تجربة جديد'
body = title + '\n\n' + '\n'.join(lines) + '\n\nللقبول افتح لوحة الإدارة ← المنشآت:\n' + ADMIN
sent = []

user, pw = os.environ.get('NOTIFY_GMAIL_USER', '').strip(), re.sub(r'\s', '', os.environ.get('NOTIFY_GMAIL_APP_PASSWORD', ''))
if user and pw:
    try:
        msg = MIMEText(body, 'plain', 'utf-8'); msg['Subject'] = title; msg['From'] = user
        msg['To'] = os.environ.get('NOTIFY_EMAIL_TO', '').strip() or user
        with smtplib.SMTP_SSL('smtp.gmail.com', 465, timeout=30) as s:
            s.login(user, pw); s.send_message(msg)
        sent.append('email')
    except Exception as e:
        print('::warning::e-mail not sent:', type(e).__name__)

phone, key = re.sub(r'[^\d+]', '', os.environ.get('CALLMEBOT_PHONE', '')), os.environ.get('CALLMEBOT_APIKEY', '').strip()
if phone and key:
    try:
        q = urllib.parse.urlencode({'phone': phone, 'text': body, 'apikey': key})
        with urllib.request.urlopen('https://api.callmebot.com/whatsapp.php?' + q, timeout=30) as r:
            if r.status == 200: sent.append('whatsapp')
    except Exception as e:
        print('::warning::WhatsApp not sent:', type(e).__name__)

if not sent:
    print('::warning::%d new request(s) but no notification channel worked — set the secrets (see this file)' % len(rows)); sys.exit(0)
ids = ','.join("'%s'" % r['company_id'] for r in rows)
psql('update public.company_subscriptions set notified_at = now() where company_id in (%s)' % ids)
print('notified %d request(s) by %s' % (len(rows), ' + '.join(sent)))
