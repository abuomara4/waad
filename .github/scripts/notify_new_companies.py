"""Run by .github/workflows/notify.yml every 10 minutes. Two jobs:
 1. tell the Waad team about companies waiting for approval (status 'pending', not yet notified);
 2. remind each customer by e-mail 3 days before its trial or subscription ends (once per end date).
Channels (each optional, set as repository secrets):
  e-mail   : NOTIFY_GMAIL_USER + NOTIFY_GMAIL_APP_PASSWORD (a Google «App password»); team mail goes to NOTIFY_EMAIL_TO or to itself
  WhatsApp : CALLMEBOT_PHONE + CALLMEBOT_APIKEY (free CallMeBot key for your own number) — team notices only
Something is marked as done only after it was delivered; with no channel set nothing is marked."""
import json, os, re, smtplib, subprocess, sys, urllib.parse, urllib.request
from email.mime.text import MIMEText

ADMIN = 'https://abuomara4.github.io/waad/site/admin/'
SITE = 'https://abuomara4.github.io/waad/site/'
TEST = os.environ.get('NOTIFY_TEST') == 'true'   # «Run workflow» with test = true: one test message to the team, nothing read or marked
db = re.sub(r'\s', '', os.environ.get('DB', ''))
if not TEST and not db.startswith(('postgres://', 'postgresql://')):
    print('::error::SUPABASE_DB_URL is missing or not a connection URI'); sys.exit(1)
USER, PW = os.environ.get('NOTIFY_GMAIL_USER', '').strip(), re.sub(r'\s', '', os.environ.get('NOTIFY_GMAIL_APP_PASSWORD', ''))
WA_PHONE, WA_KEY = re.sub(r'[^\d+]', '', os.environ.get('CALLMEBOT_PHONE', '')), os.environ.get('CALLMEBOT_APIKEY', '').strip()

def psql(q):
    return subprocess.run(['psql', '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', db, '-c', q], check=True, capture_output=True, text=True).stdout.strip()

def mail(to, subject, body):
    if not (USER and PW and to): return False
    try:
        msg = MIMEText(body, 'plain', 'utf-8'); msg['Subject'] = subject; msg['From'] = 'وعد <%s>' % USER; msg['To'] = to
        with smtplib.SMTP_SSL('smtp.gmail.com', 465, timeout=30) as s:
            s.login(USER, PW); s.send_message(msg)
        return True
    except Exception as e:
        print('::warning::e-mail not sent:', type(e).__name__); return False

def whatsapp(text):
    if not (WA_PHONE and WA_KEY): return False
    try:
        q = urllib.parse.urlencode({'phone': WA_PHONE, 'text': text, 'apikey': WA_KEY})
        with urllib.request.urlopen('https://api.callmebot.com/whatsapp.php?' + q, timeout=30) as r:
            return r.status == 200
    except Exception as e:
        print('::warning::WhatsApp not sent:', type(e).__name__); return False

# ---------- 1. new requests → the Waad team ----------
def team():
    rows = [{'company_id': None, 'name': 'رسالة تجربة من وعد', 'email': 'test@example.com', 'at': 'الآن'}] if TEST else json.loads(psql("""select coalesce(json_agg(x), '[]') from (
      select s.company_id, c.name, to_char(c.created_at at time zone 'Asia/Riyadh', 'YYYY-MM-DD HH24:MI') as at,
             (select u.email from public.members m join auth.users u on u.id = m.user_id where m.company_id = c.id and m.role = 'owner' limit 1) as email,
             c.owner_phone as phone, c.city, c.size_band as size
        from public.company_subscriptions s join public.companies c on c.id = s.company_id
       where s.status = 'pending' and s.notified_at is null order by c.created_at limit 20) x"""))
    if not rows:
        print('no new requests'); return
    lines = ['• %s — %s — %s' % (r['name'], ' · '.join(x for x in (r['email'], r.get('phone'), r.get('city'), r.get('size') and r['size'] + ' موظف') if x) or '—', r['at']) for r in rows]
    title = 'وعد: %d طلب تجربة جديد' % len(rows) if len(rows) > 1 else 'وعد: طلب تجربة جديد'
    body = title + '\n\n' + '\n'.join(lines) + '\n\nللقبول افتح لوحة الإدارة ← المنشآت:\n' + ADMIN
    sent = [n for n, ok in (('email', mail(os.environ.get('NOTIFY_EMAIL_TO', '').strip() or USER, title, body)), ('whatsapp', whatsapp(body))) if ok]
    if TEST:
        print('test message sent by %s' % (' + '.join(sent) or 'nothing — check the secrets')); sys.exit(0 if sent else 1)
    if not sent:
        print('::warning::%d new request(s) but no notification channel worked — set the secrets (see this file)' % len(rows)); return
    psql('update public.company_subscriptions set notified_at = now() where company_id in (%s)' % ','.join("'%s'" % r['company_id'] for r in rows))
    print('notified %d request(s) by %s' % (len(rows), ' + '.join(sent)))

# ---------- 2. 3 days before the end → the customer ----------
def remind():
    rows = json.loads(psql("""select coalesce(json_agg(x), '[]') from (
      select s.company_id, c.name, s.status, case when s.status = 'trial' then s.trial_ends else s.sub_ends end as ends,
             (case when s.status = 'trial' then s.trial_ends else s.sub_ends end) - (now() at time zone 'Asia/Riyadh')::date as days,
             (select u.email from public.members m join auth.users u on u.id = m.user_id where m.company_id = c.id and m.role = 'owner' limit 1) as email
        from public.company_subscriptions s join public.companies c on c.id = s.company_id
       where s.status in ('trial','active')
         and (case when s.status = 'trial' then s.trial_ends else s.sub_ends end) between (now() at time zone 'Asia/Riyadh')::date and (now() at time zone 'Asia/Riyadh')::date + 3
         and s.reminded_end is distinct from (case when s.status = 'trial' then s.trial_ends else s.sub_ends end)
       limit 50) x"""))
    if not rows:
        print('no reminders due'); return
    c = json.loads(psql("select coalesce((select value from public.site_content where key = 'contact'), '{}')") or '{}')
    phone = ('0' + c['phone'][3:]) if re.fullmatch(r'9665\d{8}', c.get('phone') or '') else '0554003226'
    reach = 'واتساب أو اتصال: %s · %s\n%scontact.html' % (phone, c.get('email') or 'waad.erp@gmail.com', SITE)
    done = []
    for r in rows:
        if not r.get('email'): continue
        trial, when = r['status'] == 'trial', ('اليوم' if r['days'] == 0 else 'بكرة' if r['days'] == 1 else 'بعد يومين' if r['days'] == 2 else 'بعد %d أيام' % r['days'])
        what, what_en = ('تجربتك المجانية', 'free trial') if trial else ('اشتراكك', 'subscription')
        subject = 'وعد: %s تنتهي %s' % (what, when)
        body = ('السلام عليكم،\n\n%s في نظام وعد لمنشأة «%s» تنتهي %s (%s).\n'
                '%s\n\nتواصل معنا:\n%s\n\nفريق وعد\n\n— — —\n'
                'Your Waad %s for «%s» ends on %s. %s, contact us: %s · %s') % (
            what, r['name'], when, r['ends'],
            'للاشتراك وإكمال استخدام النظام بدون انقطاع، تواصل معنا قبل هذا التاريخ.' if trial else 'لتجديد الاشتراك بدون انقطاع، تواصل معنا قبل هذا التاريخ.',
            reach, what_en, r['name'], r['ends'], 'To subscribe' if trial else 'To renew', phone, c.get('email') or 'waad.erp@gmail.com')
        if mail(r['email'], subject, body):
            psql("update public.company_subscriptions set reminded_end = '%s' where company_id = '%s'" % (r['ends'], r['company_id'])); done.append(r['name'])
    print('reminded %d of %d: %s' % (len(done), len(rows), ', '.join(done) or '—') if done else '::warning::%d reminder(s) due but none sent — check the e-mail secrets' % len(rows))

team()
if not TEST:
    remind()
