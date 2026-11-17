"""Official WhatsApp (Meta WhatsApp Business Platform, Cloud API) for the Waad team's alerts.
A business-initiated message must use a template Meta approved. Waad's template (category «Utility», language Arabic «ar»):
  name: waad_alert      body: «تنبيه من نظام وعد: {{1}}»      example for {{1}}: «منشأة جديدة بانتظار القبول: مؤسسة الريادة»
Repository secrets (all optional; nothing is sent without the first three):
  WA_TOKEN      a permanent access token of a Meta «system user» with whatsapp_business_messaging
  WA_PHONE_ID   the «Phone number ID» of Waad's WhatsApp business number (not the number itself)
  WA_TO         the team's numbers in international form without + (e.g. 9665XXXXXXXX), comma-separated
  WA_TEMPLATE   template name if not «waad_alert»;  WA_LANG  template language if not «ar»;  WA_API_VERSION  if not v26.0
The public Actions logs get counts only, never numbers or texts."""
import json, os, re, urllib.request

def _cfg():
    e = os.environ.get
    return (e('WA_TOKEN', '').strip(), e('WA_PHONE_ID', '').strip(), [re.sub(r'\D', '', x) for x in e('WA_TO', '').split(',') if re.sub(r'\D', '', x)],
            e('WA_TEMPLATE', '').strip() or 'waad_alert', e('WA_LANG', '').strip() or 'ar', e('WA_API_VERSION', '').strip() or 'v26.0')

def enabled():
    tok, pid, to, *_ = _cfg(); return bool(tok and pid and to)

def send(text):
    """Send one alert to every team number. True when at least one was accepted by Meta."""
    tok, pid, to, tpl, lang, ver = _cfg()
    if not (tok and pid and to): return False
    # a template parameter may not hold new lines, tabs or more than four spaces in a row
    p = re.sub(r' {4,}', '   ', re.sub(r'\s*[\r\n\t]+\s*', ' — ', str(text))).strip()[:900]
    ok = 0
    for n in to:
        body = {'messaging_product': 'whatsapp', 'to': n, 'type': 'template',
                'template': {'name': tpl, 'language': {'code': lang}, 'components': [{'type': 'body', 'parameters': [{'type': 'text', 'text': p}]}]}}
        req = urllib.request.Request(f'https://graph.facebook.com/{ver}/{pid}/messages', data=json.dumps(body).encode(),
                                     headers={'Authorization': 'Bearer ' + tok, 'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req, timeout=30) as r: ok += r.status == 200
        except urllib.error.HTTPError as e:
            try: code = json.loads(e.read().decode()).get('error', {}).get('code')
            except Exception: code = None
            print('::warning::WhatsApp (official) refused, HTTP %s, code %s' % (e.code, code))
        except Exception as e:
            print('::warning::WhatsApp (official) not sent:', type(e).__name__)
    return ok > 0
