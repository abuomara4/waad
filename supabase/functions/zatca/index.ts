// Supabase Edge Function «zatca»: the server side of the Fatoora (ZATCA Phase 2) link (docs/ZATCA_PHASE2.md).
// action "onboard" {company, otp, env}: the owner / an admin pastes the OTP from the Fatoora portal; the function checks the
// caller with the database (their own login), creates the key + CSR, passes ZATCA's six compliance documents, gets the
// production certificate and stores it with the service key. The private key never leaves the server.
// (Sending invoices — reporting / clearance — is step 4.)
import { onboard, type Company } from '../_shared/fatoora.ts';
import type { Env } from '../_shared/csr.ts';

const URL_ = Deno.env.get('SUPABASE_URL')!, ANON = Deno.env.get('SUPABASE_ANON_KEY')!, SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

async function rpc(fn: string, args: unknown, auth: string, key: string) {
  const r = await fetch(`${URL_}/rest/v1/rpc/${fn}`, { method: 'POST', headers: { apikey: key, Authorization: auth, 'Content-Type': 'application/json' }, body: JSON.stringify(args) });
  const t = await r.text(); let b: unknown = t; try { b = JSON.parse(t); } catch { /* text */ }
  // deno-lint-ignore no-explicit-any
  if (!r.ok) throw new Error((b as any)?.message || t || String(r.status));
  return b;
}
const service = (fn: string, args: unknown) => rpc(fn, args, 'Bearer ' + SERVICE, SERVICE);

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return reply({ error: 'POST only' }, 405);
  const auth = req.headers.get('Authorization') || '';
  // deno-lint-ignore no-explicit-any
  let p: any; try { p = await req.json(); } catch { return reply({ error: 'bad request' }, 400); }
  if (p.action === 'onboard') {
    const env: Env = ['sandbox', 'simulation', 'production'].includes(p.env) ? p.env : 'simulation';
    if (!/^[0-9a-f-]{36}$/.test(String(p.company)) || !/^\d{6}$/.test(String(p.otp || '').trim())) return reply({ error: 'رمز OTP من 6 أرقام' }, 400);
    let info: Company;
    try { info = await rpc('zatca_onboard_info', { p_company: p.company }, auth, ANON) as Company; }
    catch (e) { return reply({ error: (e as Error).message }, 403); }
    try {
      const r = await onboard(env, info, p.otp);
      await service('zatca_onboarded', { p_company: p.company, p_env: env, p_serial: r.egsSerial, p_cert: r.cert, p_key: r.keyPem, p_token: r.token, p_secret: r.secret });
      return reply({ ok: true, env, results: r.results });
    } catch (e) {
      const msg = (e as Error).message;
      await service('zatca_onboard_failed', { p_company: p.company, p_error: msg }).catch(() => {});
      return reply({ error: msg }, 422);
    }
  }
  return reply({ error: 'unknown action' }, 400);
});
