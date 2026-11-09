"""Builds site/index.html (the public landing page) from site/template.html,
inlining the official Waad logos straight from the system's source so they stay identical."""
import re, os
D = os.path.dirname(os.path.abspath(__file__))
core = open(os.path.join(D, '..', 'app', 'src', 'core.js'), encoding='utf-8').read()
logo = {n: re.search(n + r" = '(data:image/webp;base64,[^']+)'", core).group(1) for n in ('LOGO_D', 'LOGO_L')}
fav = re.search(r'<link rel="icon" type="image/png" href="(data:image/png;base64,[^"]+)"', open(os.path.join(D, '..', 'app', 'build.py'), encoding='utf-8').read()).group(1)
t = open(os.path.join(D, 'template.html'), encoding='utf-8').read()
t = t.replace('<link rel="icon" href="__LOGO_L__">', '<link rel="icon" type="image/png" href="%s">' % fav)
t = t.replace('__LOGO_D__', logo['LOGO_D']).replace('__LOGO_L__', logo['LOGO_L'])
assert '__LOGO' not in t
open(os.path.join(D, 'index.html'), 'w', encoding='utf-8').write(t)
print('built site/index.html', len(t.encode()), 'bytes')
