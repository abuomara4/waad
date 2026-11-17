#!/usr/bin/env python3
"""Fills the store-app files with the real domain, once Waad has its own domain (see mobile/README.md).

  python3 mobile/setup.py --domain waad.sa                      # Android + iPhone config files
  python3 mobile/setup.py --domain waad.sa --sha256 AB:CD:...    # + the Android ownership file for the website

--app-path   where the system lives on the domain (default /site/app/, as on GitHub Pages today)
--package    the store app id, the same on Google Play and the App Store; it can never change after the first upload (default sa.waad.app)
Writes: mobile/android/twa-manifest.json, mobile/ios/capacitor.config.json and, with --sha256,
.well-known/assetlinks.json at the repository root (served at https://DOMAIN/.well-known/assetlinks.json) plus .nojekyll so GitHub Pages serves it."""
import argparse, json, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))); M = os.path.join(ROOT, 'mobile')
ap = argparse.ArgumentParser()
ap.add_argument('--domain', required=True); ap.add_argument('--app-path', default='/site/app/'); ap.add_argument('--package', default='sa.waad.app'); ap.add_argument('--sha256')
a = ap.parse_args()
dom = re.sub(r'^https?://', '', a.domain).strip('/').lower()
if not re.fullmatch(r'[a-z0-9.-]+\.[a-z]{2,}', dom) or 'github.io' in dom: sys.exit('Use your own domain (e.g. waad.sa), not github.io')
path = '/' + a.app_path.strip('/') + '/' if a.app_path.strip('/') else '/'
if not re.fullmatch(r'[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+', a.package): sys.exit('Package id like sa.waad.app')
vals = {'{{DOMAIN}}': dom, '{{APP_PATH}}': path, '{{PACKAGE_ID}}': a.package}
def fill(src, dst, extra=None):
    t = open(os.path.join(M, src), encoding='utf-8').read()
    for k, v in {**vals, **(extra or {})}.items(): t = t.replace(k, v)
    assert '{{' not in t, 'unfilled placeholder in ' + src
    json.loads(t); out = os.path.join(ROOT, dst); os.makedirs(os.path.dirname(out), exist_ok=True); open(out, 'w', encoding='utf-8').write(t); print('wrote', dst)
fill('android/twa-manifest.template.json', 'mobile/android/twa-manifest.json')
fill('ios/capacitor.config.template.json', 'mobile/ios/capacitor.config.json')
if a.sha256:
    fp = a.sha256.strip().upper()
    if not re.fullmatch(r'([0-9A-F]{2}:){31}[0-9A-F]{2}', fp): sys.exit('--sha256 must be the SHA-256 certificate fingerprint (32 pairs like AB:CD:...) from Play Console → App integrity')
    fill('android/assetlinks.template.json', '.well-known/assetlinks.json', {'{{SHA256}}': fp})
    open(os.path.join(ROOT, '.nojekyll'), 'w').close(); print('wrote .nojekyll (GitHub Pages serves .well-known as is)')
print('done — next steps in mobile/README.md')
