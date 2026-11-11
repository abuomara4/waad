// Sending a linked company's documents to ZATCA, strictly in chain order (docs/ZATCA_PHASE2.md, step 4):
// claim → (build + sign, once) → report (simplified) or clear (standard) → store ZATCA's answer.
// Database and network are passed in, so the whole loop is tested offline (process_test.ts).
import { api, type ApiResult, docBody, zMessages } from './fatoora.ts';
import type { Env } from './csr.ts';
import { signInvoice, type ZDoc } from './zatca.ts';

// deno-lint-ignore no-explicit-any
export type Rpc = (fn: string, args: Record<string, unknown>) => Promise<any>;
export type Outcome = { status: 'reported' | 'cleared' | 'warning' | 'rejected' | 'error'; xml?: string | null; qr?: string | null; retry: number; error?: string | null };

// deno-lint-ignore no-explicit-any
export function toZDoc(d: any, pih: string): ZDoc {
  const num = (x: unknown) => Number(x);
  return { kind: d.kind, type: d.type, no: d.no, uuid: d.uuid, issueDate: d.issueDate, issueTime: d.issueTime, icv: Number(d.icv), pih,
    refNo: d.refNo, reason: d.reason, seller: d.seller, buyer: d.buyer,
    // deno-lint-ignore no-explicit-any
    lines: (d.lines || []).map((l: any) => ({ name: l.name, qty: num(l.qty), price: num(l.price), rate: num(l.rate), exemptCode: l.exemptCode, exemptReason: l.exemptReason })) };
}

const utf8 = (b64s: string) => new TextDecoder().decode(Uint8Array.from(atob(b64s), c => c.charCodeAt(0)));
const qrOf = (xml: string) => (xml.match(/<cbc:ID>QR<\/cbc:ID>\s*<cac:Attachment>\s*<cbc:EmbeddedDocumentBinaryObject[^>]*>([^<]+)</) || [])[1] || null;
export const backoff = (attempts: number) => Math.min(3600, 60 * 2 ** Math.max(0, attempts - 1));

// ZATCA's answer → what we store. Only a real refusal is final; anything else is retried.
export function mapResult(r: ApiResult | null, standard: boolean, attempts: number): Outcome {
  if (!r) return { status: 'error', retry: backoff(attempts), error: 'تعذّر الاتصال بزاتكا — ستُعاد المحاولة' };
  const b = r.body || {}, msgs = zMessages(b), warns = b?.validationResults?.warningMessages?.length > 0;
  const st = String(b.clearanceStatus || b.reportingStatus || '');
  const xml = standard && b.clearedInvoice ? utf8(b.clearedInvoice) : null;
  if ((r.status === 200 || r.status === 202) && /^(REPORTED|CLEARED)$/.test(st))
    return { status: r.status === 202 || warns ? 'warning' : standard ? 'cleared' : 'reported', xml, qr: xml ? qrOf(xml) : null, retry: 0, error: warns ? msgs.join(' — ') : null };
  if (r.status === 409) return { status: 'warning', retry: 0, error: 'سبق إرسال المستند: ' + msgs.join(' — ') };
  if (r.status === 400 && /NOT_/.test(st)) return { status: 'rejected', retry: 0, error: msgs.join(' — ') || st };
  if (r.status === 401 || r.status === 403) return { status: 'error', retry: 3600, error: 'شهادة الربط غير مقبولة — أعد الربط مع فاتورة' };
  return { status: 'error', retry: backoff(attempts), error: (msgs.join(' — ') || 'HTTP ' + r.status).slice(0, 500) };
}

const riyadhNow = (d: Date) => new Date(d.getTime() + 3 * 3600e3).toISOString().slice(0, 19);

export async function processCompany(company: string, rpc: Rpc, o: { fetcher?: typeof fetch; now?: () => Date; budgetMs?: number } = {}) {
  const now = o.now || (() => new Date()), t0 = Date.now(), budget = o.budgetMs ?? 45000, out: { icv: number; status: string; error?: string | null }[] = [];
  const cr = await rpc('zatca_creds', { p_company: company });
  if (!cr) return out;
  const env = cr.env as Env, creds = { token: cr.token, secret: cr.secret };
  while (Date.now() - t0 < budget) {
    const c = await rpc('zatca_claim', { p_company: company });
    if (!c) break;
    const standard = c.inv_type === 'standard';
    let xml: string = c.xml, hash: string = c.hash;
    if (!hash) {
      try {
        if (!c.pih) throw new Error('بانتظار توقيع المستند السابق');
        const s = signInvoice(toZDoc(await rpc('zatca_doc_data', { p_doc: c.doc_id }), c.pih), { certB64: cr.cert, keyPem: cr.key, signingTime: riyadhNow(now()) });
        await rpc('zatca_signed', { p_id: c.id, p_pih: c.pih, p_hash: s.hash, p_xml: s.xml, p_qr: s.qr });
        xml = s.xml; hash = s.hash;
      } catch (e) {   // the document cannot be built (e.g. a zero-rated item without its exemption): it waits, and so do the ones after it
        const msg = (e as Error).message;
        await rpc('zatca_result', { p_id: c.id, p_status: 'error', p_resp: null, p_xml: null, p_qr: null, p_retry: 600, p_error: msg });
        out.push({ icv: c.icv, status: 'error', error: msg }); break;
      }
    }
    let r: ApiResult | null = null;
    try { r = await api(env, standard ? '/invoices/clearance/single' : '/invoices/reporting/single', { creds, body: docBody({ hash, xml }, c.doc_id), clearance: standard }, o.fetcher); }
    catch { r = null; }
    const m = mapResult(r, standard, c.attempts);
    await rpc('zatca_result', { p_id: c.id, p_status: m.status, p_resp: r ? (typeof r.body === 'object' ? r.body : { text: String(r.body).slice(0, 2000) }) : null,
      p_xml: m.xml ?? null, p_qr: m.qr ?? null, p_retry: m.retry, p_error: m.error ?? null });
    out.push({ icv: c.icv, status: m.status, error: m.error });
    if (m.status === 'error') break;   // keep the order: the rest waits for this one
  }
  return out;
}
