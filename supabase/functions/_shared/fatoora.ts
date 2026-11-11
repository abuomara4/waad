// The Fatoora (ZATCA) API and the onboarding flow: OTP → compliance certificate → the six compliance documents →
// production certificate (docs/ZATCA_PHASE2.md, step 3). Network only; the database side is in the server function.
import { makeCsr, type Env, validVat } from './csr.ts';
import { PIH0, signInvoice, type Party, type ZDoc } from './zatca.ts';

export const BASE: Record<Env, string> = {
  sandbox: 'https://gw-fatoora.zatca.gov.sa/e-invoicing/developer-portal',
  simulation: 'https://gw-fatoora.zatca.gov.sa/e-invoicing/simulation',
  production: 'https://gw-fatoora.zatca.gov.sa/e-invoicing/core',
};
export type Creds = { token: string; secret: string };
// deno-lint-ignore no-explicit-any
export type ApiResult = { status: number; body: any };

const u8b64 = (s: string) => { const u = new TextEncoder().encode(s); let x = ''; for (let i = 0; i < u.length; i += 0x8000) x += String.fromCharCode(...u.subarray(i, i + 0x8000)); return btoa(x); };
export async function api(env: Env, path: string, o: { creds?: Creds; otp?: string; body: unknown; clearance?: boolean }, fetcher = fetch): Promise<ApiResult> {
  const h: Record<string, string> = { 'Content-Type': 'application/json', Accept: 'application/json', 'Accept-Language': 'en', 'Accept-Version': 'V2' };
  if (o.otp) h.OTP = o.otp;
  if (o.creds) h.Authorization = 'Basic ' + btoa(o.creds.token + ':' + o.creds.secret);
  if (o.clearance) h['Clearance-Status'] = '1';
  const r = await fetcher(BASE[env] + path, { method: 'POST', headers: h, body: JSON.stringify(o.body), signal: AbortSignal.timeout(30000) });
  const t = await r.text(); let body: unknown = t; try { body = JSON.parse(t); } catch { /* text */ }
  return { status: r.status, body };
}
export const docBody = (s: { hash: string; xml: string }, uuid: string) => ({ invoiceHash: s.hash, uuid, invoice: u8b64(s.xml) });
// the certificate inside a CSID token (base64 of the base64 DER)
export const certOf = (token: string) => atob(token);

// a short reason from a ZATCA answer, for the logs and the screen
export function zMessages(b: { validationResults?: { errorMessages?: { code: string; message: string }[]; warningMessages?: { code: string; message: string }[] } } | string) {
  if (typeof b === 'string') return [b.slice(0, 300)];
  const v = b?.validationResults || {};
  return [...(v.errorMessages || []), ...(v.warningMessages || [])].map(m => `${m.code}: ${m.message}`);
}

export type Company = { name: string; vat: string; cr?: string | null; street?: string | null; building?: string | null; district?: string | null; city?: string | null; postal?: string | null; addNo?: string | null; branch?: string | null; category?: string | null };
export function companyProblems(c: Company) {
  const p: string[] = [];
  if (!validVat(c.vat || '')) p.push('الرقم الضريبي 15 رقماً يبدأ وينتهي بـ 3');
  if (!c.street || !c.building || !c.district || !c.city || !c.postal) p.push('العنوان الوطني ناقص (الشارع، المبنى، الحي، المدينة، الرمز البريدي)');
  if (c.building && !/^\d{4}$/.test(c.building)) p.push('رقم المبنى 4 أرقام');
  if (c.postal && !/^\d{5}$/.test(c.postal)) p.push('الرمز البريدي 5 أرقام');
  return p;
}

// onboarding: everything ZATCA asks before an e-invoicing unit may send real documents. Returns what must be stored.
export async function onboard(env: Env, c: Company, otp: string, now = new Date(), fetcher = fetch) {
  const bad = companyProblems(c); if (bad.length) throw new Error(bad.join(' — '));
  const egsSerial = '1-Waad|2-1.0|3-' + crypto.randomUUID();
  const { keyPem, csrB64 } = makeCsr({ env, vat: c.vat, orgName: c.name, branch: c.branch || c.name, egsName: 'Waad-' + c.vat.slice(0, 10),
    egsSerial, invoiceTypes: '1100', address: c.city || 'SA', category: c.category || 'Trading' });
  const cc = await api(env, '/compliance', { otp: String(otp).trim(), body: { csr: csrB64 } }, fetcher);
  if (cc.status !== 200 || !cc.body?.binarySecurityToken) throw new Error('رفضت زاتكا الطلب: ' + (cc.body?.errors?.map?.((e: { message: string }) => e.message).join(' — ') || zMessages(cc.body).join(' — ') || cc.status) + ' (تأكد من رمز OTP وأنه لم تنتهِ صلاحيته)');
  const comp: Creds = { token: cc.body.binarySecurityToken, secret: cc.body.secret };
  // the six compliance documents (standard + simplified: invoice, credit note, debit note), signed with the compliance certificate
  const t = new Date(now.getTime() + 3 * 3600e3).toISOString(), date = t.slice(0, 10), time = t.slice(11, 19);
  const seller: Party = { name: c.name, vat: c.vat, cr: c.cr, street: c.street, building: c.building, district: c.district, city: c.city, postal: c.postal, addNo: c.addNo };
  const buyer: Party = { name: 'Compliance Test Buyer', vat: '300000000000003', street: 'King Fahd Road', building: '1234', district: 'Al Olaya', city: 'Riyadh', postal: '12211' };
  const lines = [{ name: 'Compliance test item', qty: 1, price: 100, rate: 15 }];
  const kinds: [ZDoc['kind'], ZDoc['type']][] = [['invoice', 'standard'], ['credit', 'standard'], ['debit', 'standard'], ['invoice', 'simplified'], ['credit', 'simplified'], ['debit', 'simplified']];
  let pih = PIH0; const results: string[] = [];
  for (let i = 0; i < kinds.length; i++) {
    const [kind, type] = kinds[i], uuid = crypto.randomUUID();
    const d: ZDoc = { kind, type, no: 'COMP-' + (i + 1), uuid, issueDate: date, issueTime: time, icv: i + 1, pih, seller, buyer: type === 'standard' ? buyer : null, lines,
      refNo: kind === 'invoice' ? null : 'COMP-1', reason: kind === 'invoice' ? null : 'Compliance test' };
    const s = signInvoice(d, { certB64: certOf(comp.token), keyPem, signingTime: date + 'T' + time });
    const r = await api(env, '/compliance/invoices', { creds: comp, body: docBody(s, uuid) }, fetcher);
    const st = r.body?.reportingStatus || r.body?.clearanceStatus;
    if (r.status >= 300 || !st || /NOT/.test(st)) throw new Error(`فشل فحص الامتثال (${kind}/${type}): ` + zMessages(r.body).join(' — '));
    results.push(`${kind}/${type}: ${st}`); pih = s.hash;
  }
  const pc = await api(env, '/production/csids', { creds: comp, body: { compliance_request_id: String(cc.body.requestID) } }, fetcher);
  if (pc.status !== 200 || !pc.body?.binarySecurityToken) throw new Error('لم تُصدر شهادة الإنتاج: ' + (zMessages(pc.body).join(' — ') || pc.status));
  return { keyPem, egsSerial, token: pc.body.binarySecurityToken as string, secret: pc.body.secret as string, cert: certOf(pc.body.binarySecurityToken), results };
}
