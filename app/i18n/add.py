import sys, os
D = os.path.dirname(os.path.abspath(__file__)); p = os.path.join(D, 'en.tsv')
cur = {}
if os.path.exists(p):
    for ln in open(p, encoding='utf-8'):
        ln = ln.rstrip('\n')
        if ln and not ln.startswith('#'): a, _, b = ln.partition('\t'); cur[a] = b
n = 0
for ln in sys.stdin.read().split('\n'):
    if not ln.strip(): continue
    a, sep, b = ln.partition('|')
    if not sep: print('BAD', ln); continue
    cur[a.strip()] = b.strip(); n += 1
with open(p, 'w', encoding='utf-8') as f:
    for a in sorted(cur): f.write(a + '\t' + cur[a] + '\n')
print('added', n, 'total', len(cur))
