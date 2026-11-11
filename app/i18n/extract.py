#!/usr/bin/env python3
"""Lists every Arabic text run the UI can show (app source + DB messages/seed names) and reports runs missing from i18n/en.tsv."""
import re, os, glob, sys
D = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(D)
L = r'[ء-غـ-ْٰ-ۓ]'
RUN = re.compile(L + r'+(?:[  ]+' + L + r'+)*')
def runs():
    files = glob.glob(os.path.join(ROOT, 'src', '*.js')) + glob.glob(os.path.join(ROOT, '..', 'supabase', 'migrations', '*.sql')) + [os.path.join(ROOT, 'build.py')]
    out = {}
    for f in files:
        if f.endswith('i18n_en.js') or f.endswith('letters.js') or f.endswith('legal.js') or f.endswith('forms_lib.js'): continue   # letter sheets render in the language chosen for the letter (data-nt)
        for line in open(f, encoding='utf-8'):
            if f.endswith('.sql') and line.lstrip().startswith('--'): continue
            for m in RUN.findall(line): out.setdefault(m, os.path.basename(f))
    return out
def load():
    d = {}
    p = os.path.join(D, 'en.tsv')
    if os.path.exists(p):
        for ln in open(p, encoding='utf-8'):
            ln = ln.rstrip('\n')
            if not ln or ln.startswith('#'): continue
            a, _, b = ln.partition('\t'); d[a] = b
    return d
if __name__ == '__main__':
    r, d = runs(), load()
    miss = [k for k in r if k not in d]
    for k in sorted(miss, key=lambda k: (r[k], k)): print(r[k] + '\t' + k)
    print(len(r), 'runs,', len(miss), 'missing', file=sys.stderr)
