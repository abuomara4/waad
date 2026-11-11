#!/usr/bin/env python3
"""Inline src/* into one self-contained waad-app.html (open it directly in a browser, or host it anywhere static)."""
import os
import re
import json
D = os.path.dirname(os.path.abspath(__file__)); r = lambda f: open(os.path.join(D, 'src', f), encoding='utf-8').read()
EN = {}
for ln in open(os.path.join(D, 'i18n', 'en.tsv'), encoding='utf-8'):
    ln = ln.rstrip('\n')
    if ln and not ln.startswith('#'): a, _, b = ln.partition('\t'); EN[a] = b
EN_JS = 'const EN = ' + json.dumps(EN, ensure_ascii=False, separators=(',', ':')) + ';'
html = f'''<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#131b29">
<meta name="color-scheme" content="dark light">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="وعد">
<meta name="mobile-web-app-capable" content="yes">
<link rel="icon" type="image/png" href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACgAAAAnCAMAAABKdvqKAAAAwFBMVEVcZmaioGybl2omULAjT54oXNBoem+PiWR4i3qidWeWj2UTcfMpWcNqjXAsaHRtiHxojIP///8NG3OcnJwnVbtgnp5wjIIAAP+EfFg1PK9qOw1jY/9vhnlrhYH//wAAKytiWiqaZBfDrmcsXMYA/wBmZplff4NVqv9//3+ClIL/AAD/fwAAAACPlnN0lYcqZed8fnywpGmmm2VqjYKEmYQqYtp0jXuRk29ti4NTWFZUZ2tne3WqmF11g3RVVap8kXtBj4qOAAAAQHRSTlMUEtxdI+JOV8QWmgOcGAet4gEIBZoEqwFICggCa1oBBg4I/38BBUADAt8BAgD6+/0G/vf3/vf2zMkIEDP3SAP76+CavQAAApNJREFUeNptlImWojAQRcOOoKK2S3dPL9M9+0wRksgiuP3/X01VCLaNxHM4oJdXVe8lMhhYJ1iMPc8bu3jXLTbAxeAUGa3C+SDZkF7HZVlHzgfAzWbqZV5WFAWS3kO80NwA+AAOEc7UQTpbwheAEbDoFnRhnFHNGFwPy7ubBXK2ugW/EFi4p0UMS5Qcwwpq+10NKS614kO8cQt6BfXk4TAEuh72+Bq7cdvEV+Rsmw3ZSFM7+qUic96IO9wP+6jNdl3HXY4fkZPy/sYeMbLECUtidx7KLh4r5FQAVg8U7eBuGw32h5xS9+Rkj9tHUfAKep4sW74ZzuolI+AplVLaDAN2nW8O1lVSjYj7BKJemeKSEdzR8z/ipDUKqKPPoM+JlPYU4Mcv1nKWDLBFA4rJ/Lf4PiWQyEpATXmkSgWWeg+6HoVRnAKbbZG0I/yqriS+4gOKRgZcAXta79bPDO/8Ged5Je5epoYT6tCBAtiO09rt8YklyVMDL3VEU+EUDMG2tICfnG+3nJec703L87qykTviEIHsQPC3HD8JXYmcrsSc2XarB0wpdajhL4LPM9Rbo4Uz4vcg8NewrWuBdihqDSeO+zChTrH6BOYszHVdw6Vs/kIg/q5rrqAJeZnzySJJDSdMgqI9140hJ3iXn/MyTM/ki9ZLpbJ0YQRPLbllRM7y8px3HA6EyXRxMArLaKJ6SGR+pHlp8NS6xIbG1ab6hCYKsfozbp5Gc/6F0w73NI/IsarHtVHUl4kENHRhOplrzmRWQ33RRD1RtU5ecd3G1ZqlSaYJb7nLDhcmmSPeDnEfRwG3akJkkpTkZJ+7OjOC+ix5nqPe+Xjzz8Cuz1az5vyMhv/x+3r9UwjHXVnO1qw9rp/Wf2y18Td/DYv0AAAAAElFTkSuQmCC">
<script>try{{var t=JSON.parse(localStorage.getItem('waad.theme'));if(t!=='auto')document.documentElement.dataset.theme=t==='light'?'light':'dark'}}catch(e){{document.documentElement.dataset.theme='dark'}}</script>
<meta name="referrer" content="no-referrer">
<meta name="robots" content="noindex, nofollow">
<link rel="manifest" href="manifest.webmanifest">
<link rel="apple-touch-icon" href="icon-192.png">
<title>وعد — الموارد البشرية والمالية</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>
{r('style.css')}
</style>
</head>
<body>
<div id="app"><div class="auth"><div class="muted">جارٍ التحميل…</div></div></div>
<div id="toast" role="status" aria-live="polite" hidden></div>
<dialog id="dlg"></dialog>
<script>
{EN_JS}
{r('core.js')}
{r('hr.js')}
{r('talent.js')}
{r('attendance.js')}
{r('penalties.js')}
{r('qr.js')}
{r('letters.js')}
{r('docs.js')}
{r('org.js')}
{r('hrplus.js')}
{r('analytics.js')}
{r('flow.js')}
{r('finance.js')}
{r('sales.js')}
{r('purchase.js')}
{r('inventory.js')}
{r('financeplus.js')}
{r('financemore.js')}
{r('legal.js')}
{r('platform.js')}
{r('modules.js')}
{r('marketing.js')}
{r('projects.js')}
applyLang();
boot();
</script>
<script>if('serviceWorker'in navigator&&location.pathname.indexOf('waad-app.html')<0){{window.addEventListener('load',function(){{navigator.serviceWorker.register('sw.js').catch(function(){{}});}});}}</script>
</body>
</html>
'''
open(os.path.join(D, 'waad-app.html'), 'w', encoding='utf-8').write(html)
print('built', len(html), 'bytes')

# the admin site (site/admin/): the same page shell with only the sign-in, the shared helpers and the admin screens.
# It is not installable (no manifest / service worker) and never indexed.
start, end = html.index('<script>\n' + EN_JS), html.index('applyLang();\nboot();')
admin = html[:start] + '<script>\nconst ADMIN_SITE = true;\n' + EN_JS + '\n' + r('core.js') + '\n' + r('qr.js') + '\n' + r('legal.js') + '\n' + r('platform.js') + '\n' + html[end:]
admin = re.sub(r'<link rel="manifest"[^>]*>\n?|<link rel="apple-touch-icon"[^>]*>\n?|<meta name="(apple-mobile-web-app-capable|apple-mobile-web-app-title|mobile-web-app-capable)"[^>]*>\n?', '', admin)
admin = re.sub(r"<script>if\('serviceWorker'.*?</script>\n", '', admin, flags=re.S)
admin = admin.replace('<title>وعد — الموارد البشرية والمالية</title>', '<title>وعد — لوحة الإدارة</title>')
# the admin site keeps its own look setting, light by default (the system stays dark by default)
admin = admin.replace("localStorage.getItem('waad.theme')", "localStorage.getItem('waad.atheme')").replace("t==='light'?'light':'dark'}catch(e){document.documentElement.dataset.theme='dark'}", "t==='dark'?'dark':'light'}catch(e){document.documentElement.dataset.theme='light'}").replace('<meta name="theme-color" content="#131b29">', '<meta name="theme-color" content="#f5f7fb">')
assert "waad.atheme" in admin and "dataset.theme='light'" in admin
assert 'serviceWorker' not in admin and 'ADMIN_SITE' in admin and 'manifest' not in admin
open(os.path.join(D, 'waad-admin.html'), 'w', encoding='utf-8').write(admin)
print('built admin', len(admin), 'bytes')
