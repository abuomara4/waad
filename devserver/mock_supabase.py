#!/usr/bin/env python3
"""Tiny local stand-in for Supabase (Auth + PostgREST subset) used ONLY for UI tests.
Runs SQL through psql against a throwaway Postgres that has the shim + migrations.
Usage: mock_supabase.py <pg_port> <http_port> <static_dir> [autoconfirm=1]
"""
import base64, hashlib, hmac, json, os, re, struct, subprocess, sys, time, uuid, urllib.parse
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

PG_PORT, HTTP_PORT, STATIC = sys.argv[1], int(sys.argv[2]), sys.argv[3]
AUTOCONFIRM = (sys.argv[4] if len(sys.argv) > 4 else '1') == '1'
USERS = {}      # email -> {id, password, confirmed}
REFRESH = {}    # refresh token -> (email, aal)
CHALLENGES = {}  # challenge id -> factor id

def totp(secret, t=None, step=30):
    key = base64.b32decode(secret + '=' * (-len(secret) % 8)); c = int((t or time.time()) // step)
    h = hmac.new(key, struct.pack('>Q', c), hashlib.sha1).digest(); o = h[-1] & 15
    return '%06d' % ((struct.unpack('>I', h[o:o + 4])[0] & 0x7fffffff) % 1000000)

def factors_of(uid):
    raw = psql(f"select '@@' || coalesce(json_agg(json_build_object('id', id, 'factor_type', factor_type, 'status', status, 'friendly_name', friendly_name)), '[]') from auth.mfa_factors where user_id = {lit(uid)};")
    return json.loads(raw or '[]')
LOG = []

def psql(sql):
    p = subprocess.run(['psql', '-X', '-q', '-At', '-h', '/tmp', '-p', PG_PORT, '-U', 'postgres', '-v', 'ON_ERROR_STOP=1',
                        '-v', 'VERBOSITY=verbose'], input='\\set VERBOSITY verbose\n' + sql, capture_output=True, text=True)
    i = p.stdout.find('@@')
    out = [p.stdout[i + 2:].rstrip('\n')] if i >= 0 else []
    if p.returncode != 0:
        m = re.search(r'ERROR:\s+([0-9A-Z]{5}):\s+(.*)', p.stderr)
        code, msg = (m.group(1), m.group(2)) if m else ('XX000', p.stderr.strip())
        raise PgError(code, msg)
    return out[0] if out else None

class PgError(Exception):
    def __init__(self, code, msg): self.code, self.msg = code, msg

def lit(v):
    if v is None: return 'NULL'
    return "'" + str(v).replace("'", "''") + "'"

def token_for(email, aal='aal1'):
    u = USERS[email]
    payload = base64.urlsafe_b64encode(json.dumps({'sub': u['id'], 'email': email, 'role': 'authenticated', 'aal': aal}).encode()).decode().rstrip('=')
    return 'mock.' + payload + '.sig'

def claims_from(headers):
    a = headers.get('Authorization', '')
    if not a.startswith('Bearer mock.'): return None
    p = a.split('.')[1]; p += '=' * (-len(p) % 4)
    return json.loads(base64.urlsafe_b64decode(p))

def wrap(claims, q, raw=False):
    pre = 'begin;\n'
    if claims:
        pre += f"select set_config('request.jwt.claim.sub', {lit(claims['sub'])}, true), set_config('request.jwt.claims', {lit(json.dumps(claims))}, true) is null;\nset local role authenticated;\n"
    else:
        pre += 'set local role anon;\n'
    return pre + (q + ';\n' if raw else f"select '@@' || coalesce(({q})::text, '');\n") + 'commit;\n'

FUNCS = None
def funcs():
    global FUNCS
    if FUNCS is None:
        raw = psql("""select '@@' || json_agg(json_build_object('n', proname, 'args', coalesce(proargnames[1:pronargs], '{}'),
                 'types', array(select format_type(t, null) from unnest(proargtypes) t), 'set', proretset, 'ret', format_type(prorettype, null)))
                 from pg_proc where pronamespace = 'public'::regnamespace""".replace("select '@@' ||", "select '@@' ||"))
        FUNCS = {f['n']: f for f in json.loads(raw)}
    return FUNCS

OPS = {'eq': '=', 'neq': '<>', 'gt': '>', 'gte': '>=', 'lt': '<', 'lte': '<='}
IDENT = re.compile(r'^[a-z_][a-z0-9_]*$')

def where_clause(params):
    conds = []
    for k, vs in params.items():
        if k in ('select', 'order', 'limit', 'offset', 'on_conflict', 'columns'): continue
        if not IDENT.match(k): raise PgError('PGRST100', 'bad column ' + k)
        for v in vs:
            op, _, val = v.partition('.')
            if op == 'is': conds.append(f'{k} is {"null" if val == "null" else ("true" if val == "true" else "false")}')
            elif op == 'in':
                items = [x.strip('"') for x in val.strip('()').split(',') if x]
                conds.append(f'{k}::text in ({",".join(lit(x) for x in items)})' if items else 'false')
            elif op in OPS: conds.append(f'{k} {OPS[op]} {lit(val)}')
            else: raise PgError('PGRST100', 'unsupported op ' + op)
    return (' where ' + ' and '.join(conds)) if conds else ''

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body=None, ctype='application/json'):
        data = b'' if body is None else (body if isinstance(body, bytes) else (body if isinstance(body, str) else json.dumps(body)).encode())
        self.send_response(code)
        self.send_header('Content-Type', ctype); self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', '*'); self.send_header('Access-Control-Allow-Methods', '*')
        self.send_header('Content-Length', str(len(data))); self.end_headers(); self.wfile.write(data)
    def body(self):
        n = int(self.headers.get('Content-Length') or 0)
        return json.loads(self.rfile.read(n) or b'null') if n else None
    def do_OPTIONS(self): self.send(204)
    def do_GET(self): self.route('GET')
    def do_POST(self): self.route('POST')
    def do_PATCH(self): self.route('PATCH')
    def do_DELETE(self): self.route('DELETE')
    def do_PUT(self): self.route('PUT')

    def route(self, method):
        u = urllib.parse.urlparse(self.path); path = u.path; params = urllib.parse.parse_qs(u.query, keep_blank_values=True)
        LOG.append(f'{method} {self.path}')
        try:
            if path.startswith('/auth/v1/'): return self.auth(method, path[9:], params)
            if path.startswith('/rest/v1/'):
                if self.headers.get('apikey') != 'test-publishable-key': return self.send(401, {'message': 'Invalid API key'})
                return self.rest(method, path[9:], params)
            if path.startswith('/mock/'): return self.mock(path[6:], params)
            f = os.path.join(STATIC, path.lstrip('/') or 'index.html')
            if os.path.isfile(f):
                ext = os.path.splitext(f)[1]
                ct = {'.js': 'application/javascript', '.json': 'application/json', '.webmanifest': 'application/manifest+json',
                      '.png': 'image/png', '.css': 'text/css', '.svg': 'image/svg+xml'}.get(ext, 'text/html; charset=utf-8')
                return self.send(200, open(f, 'rb').read(), ct)
            self.send(404, {'message': 'not found'})
        except PgError as e:
            st = 401 if e.code == '42501' and not claims_from(self.headers) else (403 if e.code == '42501' else 400)
            if e.code == '23505': st = 409
            self.send(st, {'code': e.code, 'message': e.msg, 'details': None, 'hint': None})

    def mock(self, what, params):
        if what == 'confirm':
            USERS[params['email'][0]]['confirmed'] = True; return self.send(200, {'ok': True})
        if what == 'log': return self.send(200, LOG)
        if what == 'exec':
            return self.send(200, {'r': psql(self.body()['q'] + "; select '@@ok';")})
        if what == 'sql':
            return self.send(200, {'r': psql(f"select '@@' || coalesce(({self.body()['q']})::text,'');")})

    def auth(self, method, ep, params):
        b = self.body() if method in ('POST', 'PUT') else None
        if ep == 'signup':
            em = (b.get('email') or '').lower()
            if em in USERS: return self.send(422, {'code': 422, 'error_code': 'user_already_exists', 'msg': 'User already registered'})
            if len(b.get('password') or '') < 6: return self.send(422, {'code': 422, 'error_code': 'weak_password', 'msg': 'Password should be at least 6 characters.'})
            uid = str(uuid.uuid4()); USERS[em] = {'id': uid, 'password': b['password'], 'confirmed': AUTOCONFIRM}
            psql(f"insert into auth.users(id, email, encrypted_password) values ({lit(uid)}, {lit(em)}, crypt({lit(b['password'])}, gen_salt('bf'))); select '@@ok';")
            user = {'id': uid, 'email': em}
            if not AUTOCONFIRM: return self.send(200, user)
            return self.send(200, self.session(em))
        if ep == 'token':
            gt = params.get('grant_type', [''])[0]
            if gt == 'password':
                em = (b.get('email') or '').lower(); u = USERS.get(em)
                okpw = u and psql(f"select '@@' || (encrypted_password = crypt({lit(b.get('password') or '')}, encrypted_password))::text from auth.users where id = {lit(u['id'])};") == 'true'
                if not okpw: return self.send(400, {'code': 400, 'error_code': 'invalid_credentials', 'msg': 'Invalid login credentials'})
                if not u['confirmed']: return self.send(400, {'code': 400, 'error_code': 'email_not_confirmed', 'msg': 'Email not confirmed'})
                return self.send(200, self.session(em))
            if gt == 'refresh_token':
                ent = REFRESH.pop(b.get('refresh_token'), None)
                if not ent: return self.send(400, {'code': 400, 'error_code': 'refresh_token_not_found', 'msg': 'Invalid Refresh Token'})
                return self.send(200, self.session(*ent))
        if ep == 'user' and method == 'PUT':
            c = claims_from(self.headers)
            if not c: return self.send(401, {'msg': 'no session'})
            b = b or {}
            if len(b.get('password') or '') < 6: return self.send(422, {'code': 422, 'error_code': 'weak_password', 'msg': 'Password should be at least 6 characters.'})
            psql(f"update auth.users set encrypted_password = crypt({lit(b['password'])}, gen_salt('bf')) where id = {lit(c['sub'])}; select '@@ok';")
            return self.send(200, {'id': c['sub'], 'email': c['email']})
        if ep == 'user':
            c = claims_from(self.headers)
            return self.send(200, {'id': c['sub'], 'email': c['email'], 'factors': factors_of(c['sub'])}) if c else self.send(401, {'msg': 'no session'})
        if ep.startswith('factors'):
            c = claims_from(self.headers)
            if not c: return self.send(401, {'msg': 'no session'})
            parts = ep.split('/')
            if len(parts) == 1 and method == 'POST':
                sec = base64.b32encode(os.urandom(10)).decode().rstrip('=')
                fid = psql(f"insert into auth.mfa_factors(user_id, friendly_name, factor_type, status, secret) values ({lit(c['sub'])}, {lit((b or {}).get('friendly_name'))}, 'totp', 'unverified', {lit(sec)}) returning '@@' || id;")
                return self.send(200, {'id': fid, 'type': 'totp', 'totp': {'qr_code': '', 'secret': sec, 'uri': f"otpauth://totp/Waad:{c['email']}?secret={sec}&issuer=Waad"}})
            fid = parts[1]
            row = psql(f"select '@@' || coalesce((select secret || '|' || status from auth.mfa_factors where id = {lit(fid)} and user_id = {lit(c['sub'])}), '')")
            if not row: return self.send(404, {'msg': 'Factor not found', 'error_code': 'mfa_factor_not_found'})
            sec, st = row.split('|')
            if len(parts) == 2 and method == 'DELETE':
                if st == 'verified' and c.get('aal') != 'aal2': return self.send(422, {'msg': 'AAL2 required', 'error_code': 'insufficient_aal'})
                psql(f"delete from auth.mfa_factors where id = {lit(fid)}; select '@@ok';"); return self.send(200, {'id': fid})
            if parts[2] == 'challenge':
                ch = str(uuid.uuid4()); CHALLENGES[ch] = fid; return self.send(200, {'id': ch, 'type': 'totp', 'expires_at': int(time.time()) + 300})
            if parts[2] == 'verify':
                if CHALLENGES.pop((b or {}).get('challenge_id'), None) != fid: return self.send(422, {'msg': 'Challenge not found', 'error_code': 'mfa_challenge_expired'})
                code = (b or {}).get('code') or ''
                if code not in [totp(sec, time.time() + d) for d in (-30, 0, 30)]: return self.send(422, {'msg': 'Invalid TOTP code entered', 'error_code': 'mfa_verification_failed'})
                psql(f"update auth.mfa_factors set status = 'verified' where id = {lit(fid)}; select '@@ok';")
                return self.send(200, self.session(c['email'], 'aal2'))
        if ep in ('logout', 'recover'): return self.send(204)
        self.send(404, {'msg': 'unknown auth endpoint'})

    def session(self, em, aal='aal1'):
        rt = uuid.uuid4().hex; REFRESH[rt] = (em, aal)
        return {'access_token': token_for(em, aal), 'refresh_token': rt, 'expires_in': 3600, 'token_type': 'bearer',
                'user': {'id': USERS[em]['id'], 'email': em}}

    def rest(self, method, rel, params):
        claims = claims_from(self.headers)
        if rel.startswith('rpc/'):
            fn = rel[4:]; f = funcs().get(fn)
            if not f: raise PgError('PGRST202', 'function not found ' + fn)
            args = self.body() or {}
            parts = []
            for n, t in zip(f['args'], f['types']):
                if n in args:
                    v = args[n]
                    if t in ('jsonb', 'json'): parts.append(f'{n} := {lit(json.dumps(v))}::{t}')
                    elif t.endswith('[]') and isinstance(v, list): parts.append(f'{n} := array(select jsonb_array_elements_text({lit(json.dumps(v))}::jsonb))::{t}')
                    else: parts.append(f'{n} := {lit(v if not isinstance(v, bool) else str(v).lower())}::{t}')
            call = f'public.{fn}({", ".join(parts)})'
            if f['set']: q = f"select coalesce(json_agg(t), '[]') from {call} t"
            elif f['ret'] == 'void': q = f"select 'null' from (select {call}) x"
            else: q = f'select to_json({call})'
            return self.send(200, psql(wrap(claims, q)) or 'null')
        table = rel
        if not IDENT.match(table): raise PgError('PGRST100', 'bad table')
        w = where_clause(params)
        if method == 'GET':
            cols = params.get('select', ['*'])[0]
            if not all(c == '*' or IDENT.match(c) for c in cols.split(',')): raise PgError('PGRST100', 'unsupported select')
            order = ''
            if 'order' in params:
                obs = []
                for o in params['order'][0].split(','):
                    c, _, d = o.partition('.'); obs.append(f'{c} {"desc" if d.startswith("desc") else "asc"}')
                order = ' order by ' + ', '.join(obs)
            lim = f" limit {int(params['limit'][0])}" if 'limit' in params else ''
            q = f"select coalesce(json_agg(t), '[]') from (select {cols} from public.{table}{w}{order}{lim}) t"
            return self.send(200, psql(wrap(claims, q)))
        body = self.body()
        if method == 'POST':
            rows = body if isinstance(body, list) else [body]
            keys = sorted({k for r in rows for k in r})
            if not all(IDENT.match(k) for k in keys): raise PgError('PGRST100', 'bad column')
            kl = ', '.join(keys)
            q = (f"with r as (insert into public.{table} ({kl}) select {kl} from json_populate_recordset(null::public.{table}, {lit(json.dumps(rows))}) returning *) "
                 f"select '@@' || coalesce(json_agg(r), '[]')::text from r")
            return self.send(201, psql(wrap(claims, q, True)))
        if method == 'PATCH':
            keys = list(body.keys())
            if not all(IDENT.match(k) for k in keys): raise PgError('PGRST100', 'bad column')
            sets = ', '.join(f'{k} = (select {k} from json_populate_record(null::public.{table}, {lit(json.dumps(body))}))' for k in keys)
            q = f"with r as (update public.{table} set {sets}{w} returning *) select '@@' || coalesce(json_agg(r), '[]')::text from r"
            return self.send(200, psql(wrap(claims, q, True)))
        if method == 'DELETE':
            q = f"with r as (delete from public.{table}{w} returning *) select '@@' || coalesce(json_agg(r), '[]')::text from r"
            return self.send(200, psql(wrap(claims, q, True)))

if __name__ == '__main__':
    print(f'mock supabase on :{HTTP_PORT}', flush=True)
    ThreadingHTTPServer(('127.0.0.1', HTTP_PORT), H).serve_forever()
