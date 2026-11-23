"""Run by .github/workflows/notify.yml every 10 minutes:
 1. tell the Waad team about companies waiting for approval (status 'pending', not yet notified);
 2. remind each customer by e-mail 3 days before its trial or subscription ends (once per end date);
 3. tell the team about new support requests; 4. e-mail the team's reply to the customer who asked;
 5. send the welcome e-mail once a company is accepted;
 6. on the 1st–3rd of each month, e-mail each owner a summary of last month (once; they can switch it off in settings);
 7. a company that ended and was not renewed: e-mail its owner 30 and 7 days before the deletion decision (day 60);
 8. the Waad team exported a company's data at its owner's request: e-mail the owner at once;
 9. notifications on users' devices (Web Push): approvals waiting, decisions, signatures, mentions, payslips.
Channels (each optional, set as repository secrets):
  e-mail   : NOTIFY_GMAIL_USER + NOTIFY_GMAIL_APP_PASSWORD (a Google «App password»); team mail goes to NOTIFY_EMAIL_TO or to itself
  WhatsApp : CALLMEBOT_PHONE + CALLMEBOT_APIKEY (free CallMeBot key for your own number) — team notices only
  WhatsApp (official, Meta Cloud API): WA_TOKEN + WA_PHONE_ID + WA_TO (+ WA_TEMPLATE) — see wa_cloud.py
  Telegram : TELEGRAM_BOT_TOKEN (from @BotFather) + TELEGRAM_CHAT_ID (your id, e.g. from @userinfobot; send /start to the bot first) — team notices only
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

TG_TOKEN, TG_CHAT = os.environ.get('TELEGRAM_BOT_TOKEN', '').strip(), os.environ.get('TELEGRAM_CHAT_ID', '').strip()
import wa_cloud   # official WhatsApp (Meta Cloud API) — .github/scripts/wa_cloud.py
def telegram(text):
    if not (TG_TOKEN and TG_CHAT): return False
    try:
        data = urllib.parse.urlencode({'chat_id': TG_CHAT, 'text': text[:4000], 'disable_web_page_preview': 'true'}).encode()
        with urllib.request.urlopen('https://api.telegram.org/bot%s/sendMessage' % TG_TOKEN, data=data, timeout=30) as r:
            return r.status == 200
    except Exception as e:
        print('::warning::Telegram not sent:', type(e).__name__); return False

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
    sent = [n for n, ok in (('email', mail(os.environ.get('NOTIFY_EMAIL_TO', '').strip() or USER, title, body)), ('whatsapp', whatsapp(body)), ('whatsapp-official', wa_cloud.send(body)), ('telegram', telegram(body))) if ok]
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
    phone, cmail = contact()
    reach = 'واتساب أو اتصال: %s · %s\n%scontact.html' % (phone, cmail, SITE)
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
            reach, what_en, r['name'], r['ends'], 'To subscribe' if trial else 'To renew', phone, cmail)
        if mail(r['email'], subject, body):
            psql("update public.company_subscriptions set reminded_end = '%s' where company_id = '%s'" % (r['ends'], r['company_id'])); done.append(r['name'])
    print('reminded %d of %d' % (len(done), len(rows)) if done else '::warning::%d reminder(s) due but none sent — check the e-mail secrets' % len(rows))

# ---------- 7. a company that ended and was not renewed: 30 and 7 days before the deletion decision (0101) ----------
def purge_notices():
    rows = json.loads(psql("select coalesce(json_agg(x), '[]') from (select * from public.purge_notices_due()) x"))
    if not rows:
        print('purge notices: none due'); return
    phone, cmail = contact()
    n = 0
    for r in rows:
        if not r.get('email'): continue
        last = r['stage'] == 2
        subject = 'وعد: %s بيانات منشأتك «%s»' % ('تنبيه أخير قبل حذف' if last else 'تنبيه قبل حذف', r['name'])
        body = ('السلام عليكم،\n\nانتهى اشتراك منشأة «%s» في نظام وعد بتاريخ %s ولم يُجدَّد، وبياناتها ما زالت محفوظة كما هي.\n'
                'ستُحذف بيانات المنشأة نهائيا من خوادمنا ابتداء من %s.\n\n'
                'قبل هذا التاريخ تقدر:\n• تجدّد الاشتراك فيرجع كل شيء كما كان، أو\n• تدخل النظام بحساب المالك وتنزّل نسخة كاملة من بياناتك (Excel وJSON) من «إعدادات المنشأة».\n\n'
                'ننبهك أن حفظ السجلات المحاسبية والفواتير للمدة النظامية مسؤولية المنشأة، فنزّل نسختك قبل الحذف.\n\n'
                'تواصل معنا: %s · %s\n%scontact.html\n\nفريق وعد\n\n— — —\n'
                'Your Waad subscription for «%s» ended on %s and was not renewed. Its data is kept as is until %s, then deleted from our servers. '
                'Renew, or sign in as the owner and download a full copy (Excel and JSON) from the company settings first. Contact: %s · %s') % (
            r['name'], r['ended_on'], r['purge_on'], phone, cmail, SITE, r['name'], r['ended_on'], r['purge_on'], phone, cmail)
        if mail(r['email'], subject, body):
            psql("select public.purge_notice_sent('%s', %d, '%s')" % (r['company_id'], int(r['stage']), r['purge_on'])); n += 1
    print('purge notices: sent %d of %d' % (n, len(rows)) if n else '::warning::%d purge notice(s) due but none sent — check the e-mail secrets' % len(rows))

# ---------- 8. the Waad team exported a company's data at its owner's request → tell the owner at once (0102) ----------
def export_notices():
    rows = json.loads(psql("""select coalesce(json_agg(x), '[]') from (
      select l.id, l.company_name as name, to_char(l.at at time zone 'Asia/Riyadh', 'YYYY-MM-DD HH24:MI') as at,
             (select u.email from public.members m join auth.users u on u.id = m.user_id where m.company_id = l.company_ref and m.role = 'owner' limit 1) as email
        from public.company_exports_log l where l.notified_at is null order by l.at limit 50) x"""))
    if not rows:
        print('export notices: none due'); return
    phone, cmail = contact()
    n = 0
    for r in rows:
        if not r.get('email'):
            psql("update public.company_exports_log set notified_at = now() where id = '%s'" % r['id']); continue   # company already deleted: nobody to tell
        subject = 'وعد: تم تصدير بيانات منشأتك «%s»' % r['name']
        body = ('السلام عليكم،\n\nصدّر فريق وعد نسخة كاملة من بيانات منشأة «%s» بتاريخ %s بتوقيت الرياض، بناء على طلبكم.\n\n'
                'إذا لم تطلب ذلك أنت أو أحد المخوّلين في منشأتك، تواصل معنا فورا:\n%s · %s\n\nفريق وعد\n\n— — —\n'
                'The Waad team exported a full copy of the data of «%s» on %s (Riyadh time), at your request. '
                'If you did not ask for this, contact us right away: %s · %s') % (r['name'], r['at'], phone, cmail, r['name'], r['at'], phone, cmail)
        if mail(r['email'], subject, body):
            psql("update public.company_exports_log set notified_at = now() where id = '%s'" % r['id']); n += 1
    print('export notices: sent %d of %d' % (n, len(rows)) if n else '::warning::%d export notice(s) due but none sent — check the e-mail secrets' % len(rows))

# ---------- 9. notifications on the users' devices (Web Push, 0106) ----------
def sqlq(x): return "'" + str(x).replace("'", "''") + "'"
def push_notices():
    try:
        import base64
        from pywebpush import webpush, WebPushException
        from py_vapid import Vapid01
        from cryptography.hazmat.primitives import serialization
    except ImportError:
        print('::warning::push: pywebpush is not installed'); return
    k = json.loads(psql("select coalesce((select json_build_object('pub', public_key, 'pem', private_pem) from public.push_keys where id = 1)::text, 'null')"))
    if not k:   # first run: make the key pair here; it never leaves the database (the app reads only the public half)
        v = Vapid01(); v.generate_keys()
        pub = base64.urlsafe_b64encode(v.public_key.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)).decode().rstrip('=')
        psql("insert into public.push_keys(id, public_key, private_pem) values (1, %s, %s) on conflict (id) do nothing" % (sqlq(pub), sqlq(v.private_pem().decode())))
        print('push: key pair created'); return
    vapid = Vapid01.from_pem(k['pem'].encode())
    rows = json.loads(psql("select coalesce(json_agg(x), '[]') from (select * from public.push_due() limit 300) x"))
    if not rows:
        print('push: none due'); return
    _, cmail = contact()
    subs = {}
    sent = gone = 0
    for r in rows:
        uid = r['user_id']
        if uid not in subs:
            subs[uid] = json.loads(psql("select coalesce(json_agg(json_build_object('endpoint', endpoint, 'keys', json_build_object('p256dh', p256dh, 'auth', auth))), '[]') from public.push_subscriptions where user_id = %s" % sqlq(uid)))
        ok = False
        data = json.dumps({'title': r['title'], 'body': r['body'] or '', 'url': r['url'] or '#/home', 'tag': r['key']}, ensure_ascii=False)
        for sub in list(subs[uid]):
            try:
                webpush(subscription_info=sub, data=data, vapid_private_key=vapid, vapid_claims={'sub': 'mailto:' + cmail}, ttl=86400, timeout=15)
                ok = True
            except WebPushException as e:
                code = getattr(getattr(e, 'response', None), 'status_code', None)
                if code in (404, 410):   # the device turned it off or the browser was removed
                    psql("delete from public.push_subscriptions where endpoint = %s" % sqlq(sub['endpoint'])); subs[uid].remove(sub); gone += 1
            except Exception:
                pass
        if ok or not subs[uid]:
            psql("insert into public.push_sent(user_id, key) values (%s, %s) on conflict do nothing" % (sqlq(uid), sqlq(r['key']))); sent += ok
    psql("delete from public.push_sent where at < now() - interval '30 days'")
    print('push: sent %d of %d, removed %d old device(s)' % (sent, len(rows), gone))

def contact():
    c = json.loads(psql("select coalesce((select value from public.site_content where key = 'contact'), '{}')") or '{}')
    phone = ('0' + c['phone'][3:]) if re.fullmatch(r'9665\d{8}', c.get('phone') or '') else '0554003226'
    return phone, c.get('email') or 'waad.erp@gmail.com'

# ---------- 3. new support requests → the Waad team ----------
def support_team():
    rows = json.loads(psql("""select coalesce(json_agg(x), '[]') from (
      select t.id, c.name, t.kind, t.subject, left(t.body, 600) as body, (select u.email from auth.users u where u.id = t.user_id) as author
        from public.support_tickets t join public.companies c on c.id = t.company_id
       where t.notified_at is null order by t.created_at limit 20) x"""))
    if not rows: return
    kinds = {'question': 'سؤال', 'problem': 'مشكلة', 'suggestion': 'اقتراح'}
    title = 'وعد: %d طلب دعم جديد' % len(rows) if len(rows) > 1 else 'وعد: طلب دعم جديد'
    body = title + '\n\n' + '\n\n'.join('• [%s] %s — %s (%s)\n%s' % (kinds.get(r['kind'], r['kind']), r['subject'], r['name'], r['author'] or '—', r['body']) for r in rows) \
        + '\n\nللرد افتح لوحة الإدارة ← طلبات الدعم:\n' + ADMIN + '#/support'
    sent = [n for n, ok in (('email', mail(os.environ.get('NOTIFY_EMAIL_TO', '').strip() or USER, title, body)), ('whatsapp', whatsapp(body)), ('whatsapp-official', wa_cloud.send(body)), ('telegram', telegram(body))) if ok]
    if sent:
        psql('update public.support_tickets set notified_at = now() where id in (%s)' % ','.join("'%s'" % r['id'] for r in rows))
        print('support: told the team about %d request(s)' % len(rows))

# ---------- 4. the team's reply → the customer who asked ----------
def support_replies():
    rows = json.loads(psql("""select coalesce(json_agg(x), '[]') from (
      select t.id, c.name, t.subject, t.reply, (select u.email from auth.users u where u.id = t.user_id) as author
        from public.support_tickets t join public.companies c on c.id = t.company_id
       where t.reply is not null and t.replied_at is not null and t.reply_notified_at is null order by t.replied_at limit 30) x"""))
    n = 0
    for r in rows:
        if r.get('author') and mail(r['author'], 'وعد: رد على طلبك «%s»' % r['subject'],
                'السلام عليكم،\n\nرد فريق وعد على طلبك «%s» لمنشأة «%s»:\n\n%s\n\nتشوف الرد كمان في النظام ← قائمة حسابك ← الدعم الفني.\n\nفريق وعد' % (r['subject'], r['name'], r['reply'])):
            psql("update public.support_tickets set reply_notified_at = now() where id = '%s'" % r['id']); n += 1
    if rows: print('support: sent %d of %d replies' % (n, len(rows)))

# ---------- 5. welcome e-mail once a company is accepted ----------
def welcome():
    rows = json.loads(psql("""select coalesce(json_agg(x), '[]') from (
      select s.company_id, c.name, c.code, s.status, case when s.status = 'trial' then s.trial_ends else s.sub_ends end as ends,
             (select u.email from public.members m join auth.users u on u.id = m.user_id where m.company_id = c.id and m.role = 'owner' limit 1) as email
        from public.company_subscriptions s join public.companies c on c.id = s.company_id
       where s.status in ('trial','active') and s.welcomed_at is null limit 30) x"""))
    if not rows: return
    phone, email = contact()
    n = 0
    for r in rows:
        if not r.get('email'): continue
        until = (' حتى %s' % r['ends']) if r.get('ends') else ''
        body = ('السلام عليكم،\n\nأهلاً بك في وعد! فعّلنا %s لمنشأة «%s»%s.\n\n'
                'ادخل النظام: %sapp/\n\nأول ثلاث خطوات:\n'
                '١. الإعدادات ← «بيانات تجريبية» إذا تبي تجرّب بدون بياناتك الحقيقية.\n'
                '٢. الموظفون ← أضفهم واحد واحد أو ارفعهم من ملف Excel.\n'
                '٣. أرسل للموظفين رمز المنشأة (%s) ليدخلوا برقمهم الوظيفي من جوالاتهم.\n\n'
                'أي سؤال: من النظام ← قائمة حسابك ← الدعم الفني، أو واتساب/اتصال %s · %s\n\nفريق وعد\n\n— — —\n'
                'Welcome to Waad! Your %s for «%s» is active%s. Sign in: %sapp/ — company code for staff: %s. Questions: Support in the account menu, or %s · %s') % (
            'التجربة المجانية' if r['status'] == 'trial' else 'الاشتراك', r['name'], until, SITE, r.get('code') or '—', phone, email,
            'free trial' if r['status'] == 'trial' else 'subscription', r['name'], (' until %s' % r['ends']) if r.get('ends') else '', SITE, r.get('code') or '—', phone, email)
        if mail(r['email'], 'أهلاً بك في وعد — حسابك جاهز', body):
            psql("update public.company_subscriptions set welcomed_at = now() where company_id = '%s'" % r['company_id']); n += 1
    print('welcome: sent %d of %d' % (n, len(rows)))

# ---------- 6. the monthly summary → each company's owner ----------
def money(x): return '{:,.2f}'.format(float(x or 0))
def monthly_body(name, d):
    L, E = [], []
    if d['sales_n'] or float(d['sales']):
        L.append('• المبيعات: %s ريال (عدد الفواتير %d)' % (money(d['sales']), d['sales_n'])); E.append('Sales: %d invoices, SAR %s' % (d['sales_n'], money(d['sales'])))
    if float(d['collected']): L.append('• المحصّل من العملاء: %s ريال' % money(d['collected'])); E.append('Collected: SAR %s' % money(d['collected']))
    if float(d['purchases']): L.append('• المشتريات: %s ريال' % money(d['purchases'])); E.append('Purchases: SAR %s' % money(d['purchases']))
    if float(d['paid_out']): L.append('• المدفوع للموردين والمصروفات: %s ريال' % money(d['paid_out'])); E.append('Paid out: SAR %s' % money(d['paid_out']))
    pr = d.get('payroll')
    if pr: L.append('• الرواتب: صافي %s ريال (عدد الموظفين %d)%s' % (money(pr['net']), pr['n'], '' if pr['status'] in ('approved', 'paid') else ' (المسير لم يُعتمد بعد)')); E.append('Payroll: SAR %s net for %d employees%s' % (money(pr['net']), pr['n'], '' if pr['status'] in ('approved', 'paid') else ' (not approved yet)'))
    elif d['staff']: L.append('• الرواتب: لا يوجد مسير لهذا الشهر'); E.append('Payroll: no run for this month')
    if d['overdue_n']: L.append('• فواتير متأخرة السداد: %s ريال (عددها %d)' % (money(d['overdue']), d['overdue_n'])); E.append('Overdue invoices: %d, SAR %s' % (d['overdue_n'], money(d['overdue'])))
    if d['staff'] or d['joined'] or d['left']:
        L.append('• الموظفون على رأس العمل: %d%s' % (d['staff'], (' (انضم %d، غادر %d)' % (d['joined'], d['left'])) if d['joined'] or d['left'] else ''))
        E.append('Staff: %d%s' % (d['staff'], (' (%d joined, %d left)' % (d['joined'], d['left'])) if d['joined'] or d['left'] else ''))
    if d['expiring']: L.append('• مستندات موظفين تنتهي خلال 30 يوما: %d' % d['expiring']); E.append('Employee documents expiring within 30 days: %d' % d['expiring'])
    if d['pending']: L.append('• طلبات بانتظار الاعتماد: %d' % d['pending']); E.append('Requests waiting for approval: %d' % d['pending'])
    if d.get('applicants'): L.append('• متقدمون جدد من صفحة الوظائف: %d' % d['applicants']); E.append('New applicants from the careers page: %d' % d['applicants'])
    if d.get('survey_answers'): L.append('• إجابات الاستبيانات: %d' % d['survey_answers']); E.append('Survey answers: %d' % d['survey_answers'])
    if d.get('onb_missing'): L.append('• موظفون جدد تنقصهم بيانات (عقد أو آيبان أو إقامة): %d — راجع «التهيئة والترحيب»' % d['onb_missing']); E.append('New hires missing a contract, IBAN or iqama: %d' % d['onb_missing'])
    if d.get('hc_pending'): L.append('• طلبات وظائف بانتظار الاعتماد في خطة القوى العاملة: %d' % d['hc_pending']); E.append('Position requests waiting for approval: %d' % d['hc_pending'])
    if d['zatca_bad']: L.append('• زاتكا: مستندات مرفوضة أو لم تُرسل (عددها %d) — راجعها في المبيعات' % d['zatca_bad']); E.append('ZATCA: %d document(s) rejected or not sent' % d['zatca_bad'])
    if not L: return None   # nothing happened: no e-mail
    return ('السلام عليكم،\n\nملخص شهر %s لمنشأة «%s» من نظام وعد:\n\n%s\n\nللتفاصيل: %sapp/\n'
            'لإيقاف هذا الملخص: إعدادات المنشأة ← «الملخص الشهري بالإيميل».\n\nفريق وعد\n\n— — —\n'
            'Your Waad summary for %s, «%s»:\n%s\nDetails: %sapp/ · To stop it: company settings → monthly e-mail summary.') % (
        d['month'], name, '\n'.join(L), SITE, d['month'], name, '\n'.join(E), SITE)

def monthly():
    rows = json.loads(psql("select coalesce(json_agg(x), '[]') from (select * from public.monthly_report_due()) x"))
    if not rows:
        print('monthly: none due'); return
    n = skip = 0
    for r in rows:
        if not r.get('email'): continue
        d = json.loads(psql("select public.monthly_report('%s', '%s-01')" % (r['company_id'], r['month'])))
        body = monthly_body(r['name'], d)
        if body is None or mail(r['email'], 'وعد: ملخص شهر %s' % r['month'], body):
            psql("update public.companies set monthly_report_sent = '%s' where id = '%s'" % (r['month'], r['company_id']))
            n += body is not None; skip += body is None
    print('monthly: sent %d, nothing to report %d, of %d due' % (n, skip, len(rows)))

# ---------- 6b. the weekly summary → each company's owner (Sunday or Monday) ----------
def weekly_body(name, d):
    L, E = [], []
    if d['sales_n'] or float(d['sales']): L.append('• المبيعات: %s ريال (عدد الفواتير %d)' % (money(d['sales']), d['sales_n'])); E.append('Sales: %d invoices, SAR %s' % (d['sales_n'], money(d['sales'])))
    if float(d['collected']): L.append('• المحصل من العملاء: %s ريال' % money(d['collected'])); E.append('Collected: SAR %s' % money(d['collected']))
    if float(d['paid_out']): L.append('• المدفوع للموردين والمصروفات: %s ريال' % money(d['paid_out'])); E.append('Paid out: SAR %s' % money(d['paid_out']))
    if float(d['cash']): L.append('• رصيد الصندوق والبنك الآن: %s ريال' % money(d['cash'])); E.append('Cash and bank now: SAR %s' % money(d['cash']))
    if d['overdue_n']: L.append('• فواتير متأخرة السداد: %s ريال (عددها %d)' % (money(d['overdue']), d['overdue_n'])); E.append('Overdue invoices: %d, SAR %s' % (d['overdue_n'], money(d['overdue'])))
    if d['present_days'] or d['late']: L.append('• الحضور: %d يوم حضور، منها %d بتأخير' % (d['present_days'], d['late'])); E.append('Attendance: %d days present, %d late' % (d['present_days'], d['late']))
    if d['on_leave']: L.append('• موظفون في إجازة خلال الأسبوع: %d' % d['on_leave']); E.append('Staff on leave during the week: %d' % d['on_leave'])
    if d['joined'] or d['left']: L.append('• انضم %d وغادر %d' % (d['joined'], d['left'])); E.append('%d joined, %d left' % (d['joined'], d['left']))
    if d['pending']: L.append('• طلبات بانتظار الاعتماد: %d' % d['pending']); E.append('Requests waiting for approval: %d' % d['pending'])
    if d['contracts_due']: L.append('• عقود تنتهي قريبا أو انتهت ولم تجدد: %d' % d['contracts_due']); E.append('Contracts ending soon or not renewed: %d' % d['contracts_due'])
    if d['expiring']: L.append('• مستندات موظفين تنتهي خلال 30 يوما: %d' % d['expiring']); E.append('Employee documents expiring within 30 days: %d' % d['expiring'])
    if not L: return None   # a quiet week: no e-mail
    return ('السلام عليكم،\n\nملخص أسبوع %s إلى %s لمنشأة «%s» من نظام وعد:\n\n%s\n\nللتفاصيل: %sapp/\n'
            'لإيقاف هذا الملخص: إعدادات المنشأة ← «الملخص الأسبوعي بالإيميل».\n\nفريق وعد\n\n— — —\n'
            'Your Waad week %s to %s, «%s»:\n%s\nDetails: %sapp/ · To stop it: company settings → weekly e-mail summary.') % (
        d['from'], d['to'], name, '\n'.join(L), SITE, d['from'], d['to'], name, '\n'.join(E), SITE)

def weekly():
    rows = json.loads(psql("select coalesce(json_agg(x), '[]') from (select * from public.weekly_report_due()) x"))
    if not rows:
        print('weekly: none due'); return
    n = skip = 0
    for r in rows:
        if not r.get('email'): continue
        d = json.loads(psql("select public.weekly_report('%s', '%s')" % (r['company_id'], r['week_from'])))
        body = weekly_body(r['name'], d)
        if body is None or mail(r['email'], 'وعد: ملخص الأسبوع %s' % r['week_from'], body):
            psql("update public.companies set weekly_report_sent = '%s' where id = '%s'" % (r['week_from'], r['company_id']))
            n += body is not None; skip += body is None
    print('weekly: sent %d, nothing to report %d, of %d due' % (n, skip, len(rows)))

team()
if not TEST:
    remind(); support_team(); support_replies(); welcome(); monthly(); weekly(); purge_notices(); export_notices(); push_notices()
