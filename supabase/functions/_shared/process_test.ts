// Tests for sending (process.ts), offline: a fake database and a fake ZATCA. The same loop ran against ZATCA's developer
// sandbox on 2026-11-12 (simplified invoice + credit note REPORTED, standard invoice + debit note CLEARED with the stamped XML).
import { assert, assertEquals } from 'jsr:@std/assert@1.0.13';
import { secp256k1 } from 'npm:@noble/curves@1.4.0/secp256k1';
import { sha256 } from 'npm:@noble/hashes@1.4.0/sha256';
import { backoff, mapResult, processCompany, type Rpc, toZDoc } from './process.ts';
import { PIH0, signInvoice, unb64 } from './zatca.ts';

const CERT = Deno.readTextFileSync(new URL('./zatca_test.ts', import.meta.url)).match(/const CERT = '([^']+)'/)![1];
const key = secp256k1.utils.randomPrivateKey();
const keyPem = '-----BEGIN EC PRIVATE KEY-----\n' + btoa(String.fromCharCode(0x30, 0x2e, 0x02, 0x01, 0x01, 0x04, 0x20, ...key, 0xa0, 0x07, 0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x0a)) + '\n-----END EC PRIVATE KEY-----';
const seller = { name: 'مؤسسة الريادة', vat: '399999999900003', street: 'الأمير سلطان', building: '2322', district: 'المربع', city: 'الرياض', postal: '23333' };
const buyer = { ...seller, name: 'شركة النخبة', vat: '310000000000003' };
const res = (status: number, body: unknown) => ({ status, body });

Deno.test('ZATCA answers: reported / cleared (stamped XML + QR kept) / warning / rejected / retried', () => {
  assertEquals(mapResult(res(200, { reportingStatus: 'REPORTED' }), false, 1).status, 'reported');
  const xml = '<Invoice><cac:AdditionalDocumentReference><cbc:ID>QR</cbc:ID><cac:Attachment><cbc:EmbeddedDocumentBinaryObject mimeCode="text/plain">QRDATA</cbc:EmbeddedDocumentBinaryObject></cac:Attachment></cac:AdditionalDocumentReference></Invoice>';
  const c = mapResult(res(200, { clearanceStatus: 'CLEARED', clearedInvoice: btoa(xml) }), true, 1);
  assertEquals([c.status, c.xml, c.qr], ['cleared', xml, 'QRDATA']);
  assertEquals(mapResult(res(202, { reportingStatus: 'REPORTED', validationResults: { warningMessages: [{ code: 'W1', message: 'x' }] } }), false, 1).status, 'warning');
  const rj = mapResult(res(400, { reportingStatus: 'NOT_REPORTED', validationResults: { errorMessages: [{ code: 'BR-KSA-1', message: 'bad' }] } }), false, 1);
  assertEquals([rj.status, rj.retry, rj.error], ['rejected', 0, 'BR-KSA-1: bad']);
  assertEquals(mapResult(res(503, 'down'), false, 3), { status: 'error', retry: 240, error: 'down' });
  assertEquals(mapResult(null, false, 1).status, 'error');
  assertEquals(mapResult(res(401, ''), false, 1).retry, 3600);
  assertEquals([backoff(1), backoff(2), backoff(20)], [60, 120, 3600]);
});

Deno.test('signed properties: digest over the form ZATCA checks (ds namespace per element, self-closing DigestMethod)', () => {
  const d = toZDoc({ kind: 'invoice', type: 'simplified', no: 'I-1', uuid: crypto.randomUUID(), issueDate: '2026-11-12', issueTime: '10:00:00', icv: 1, seller, lines: [{ name: 'x', qty: '1', price: '100.00', rate: '15.00' }] }, PIH0);
  const s = signInvoice(d, { certB64: CERT, keyPem, signingTime: '2026-11-12T10:00:01' });
  const certHash = btoa([...sha256(new TextEncoder().encode(CERT))].map(b => b.toString(16).padStart(2, '0')).join(''));
  const DS = ' xmlns:ds="http://www.w3.org/2000/09/xmldsig#"';
  const sp = `<xades:SignedProperties xmlns:xades="http://uri.etsi.org/01903/v1.3.2#" Id="xadesSignedProperties"><xades:SignedSignatureProperties><xades:SigningTime>2026-11-12T10:00:01</xades:SigningTime><xades:SigningCertificate><xades:Cert><xades:CertDigest><ds:DigestMethod${DS} Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"/><ds:DigestValue${DS}>${certHash}</ds:DigestValue></xades:CertDigest><xades:IssuerSerial><ds:X509IssuerName${DS}>CN=eInvoicing</ds:X509IssuerName><ds:X509SerialNumber${DS}>1794433804026</ds:X509SerialNumber></xades:IssuerSerial></xades:Cert></xades:SigningCertificate></xades:SignedSignatureProperties></xades:SignedProperties>`;
  const want = btoa([...sha256(new TextEncoder().encode(sp))].map(b => b.toString(16).padStart(2, '0')).join(''));
  assert(s.xml.includes(`URI="#xadesSignedProperties"><ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"></ds:DigestMethod><ds:DigestValue>${want}</ds:DigestValue>`));
});

// a fake database with the same rules as 0080: strict chain order, sign once, results stored
function fakeDb(types: ('simplified' | 'standard')[]) {
  // deno-lint-ignore no-explicit-any
  const docs: any[] = types.map((t, i) => ({ id: i + 1, icv: i + 1, doc_id: crypto.randomUUID(), kind: 'invoice', inv_type: t, status: 'pending', attempts: 0, hash: null, xml: null, pih: null }));
  const calls: string[] = [];
  const rpc: Rpc = async (fn, a) => {
    calls.push(fn);
    if (fn === 'zatca_creds') return { env: 'sandbox', cert: CERT, key: keyPem, token: 't', secret: 's' };
    if (fn === 'zatca_claim') { const d = docs.find(x => ['pending', 'error'].includes(x.status)); if (!d || d.waiting) return null; d.attempts++;
      return { ...d, pih: d.pih || (d.icv === 1 ? PIH0 : docs[d.icv - 2].hash) }; }
    if (fn === 'zatca_doc_data') { const d = docs.find(x => x.doc_id === a.p_doc);
      return { kind: 'invoice', type: d.inv_type, no: 'I-' + d.icv, uuid: d.doc_id, icv: d.icv, issueDate: '2026-11-12', issueTime: '10:00:00', seller, buyer: d.inv_type === 'standard' ? buyer : null,
        lines: d.bad ? [{ name: 'تصدير', qty: 1, price: 100, rate: 0 }] : [{ name: 'خدمة', qty: '2', price: '50.00', rate: '15.00' }] }; }
    if (fn === 'zatca_signed') { const d = docs.find(x => x.id === a.p_id); if (d.hash) throw new Error('signed twice'); Object.assign(d, { pih: a.p_pih, hash: a.p_hash, xml: a.p_xml }); return null; }
    if (fn === 'zatca_result') { const d = docs.find(x => x.id === a.p_id); Object.assign(d, { status: a.p_status, error: a.p_error, waiting: a.p_status === 'error' }); return null; }
  };
  return { docs, rpc, calls };
}

Deno.test('sending: in chain order, each document chained to the previous hash, reporting vs clearance by type', async () => {
  const db = fakeDb(['simplified', 'standard', 'simplified']), paths: string[] = [];
  const fake = (async (url: string, init: RequestInit) => {
    const path = url.replace(/^.*\/developer-portal/, ''), b = JSON.parse(String(init.body)); paths.push(path + (new Headers(init.headers).get('Clearance-Status') ? ' +clearance' : ''));
    const xml = new TextDecoder().decode(unb64(b.invoice));
    return new Response(JSON.stringify(path.includes('clearance') ? { clearanceStatus: 'CLEARED', clearedInvoice: btoa(unescape(encodeURIComponent(xml))) } : { reportingStatus: 'REPORTED' }), { status: 200 });
  }) as typeof fetch;
  const out = await processCompany('c', db.rpc, { fetcher: fake });
  assertEquals(out.map(o => o.status), ['reported', 'cleared', 'reported']);
  assertEquals(paths, ['/invoices/reporting/single', '/invoices/clearance/single +clearance', '/invoices/reporting/single']);
  assertEquals(db.docs[1].pih, db.docs[0].hash); assertEquals(db.docs[2].pih, db.docs[1].hash);
});

Deno.test('sending: a network failure keeps the signature and stops (the next run resends the same XML); a rejection does not stop the chain', async () => {
  const db = fakeDb(['simplified', 'simplified', 'simplified']); let n = 0;
  const flaky = (async () => { n++; if (n === 2) throw new Error('timeout'); return new Response(JSON.stringify(n === 1 ? { reportingStatus: 'NOT_REPORTED', validationResults: { errorMessages: [{ code: 'E', message: 'x' }] } } : { reportingStatus: 'REPORTED' }), { status: n === 1 ? 400 : 200 }); }) as typeof fetch;
  const out = await processCompany('c', db.rpc, { fetcher: flaky });
  assertEquals(out.map(o => o.status), ['rejected', 'error']);
  const h = db.docs[1].hash; assert(h);
  db.docs[1].waiting = false;   // time passes
  const out2 = await processCompany('c', db.rpc, { fetcher: flaky });
  assertEquals(out2.map(o => o.status), ['reported', 'reported']);
  assertEquals(db.docs[1].hash, h, 'resent with the same signature');
});

Deno.test('sending: a document that cannot be built (zero rate without exemption) waits with a clear message, and holds the rest', async () => {
  const db = fakeDb(['simplified', 'simplified']); db.docs[0].bad = true;
  const out = await processCompany('c', db.rpc, { fetcher: (async () => new Response('{}')) as unknown as typeof fetch });
  assertEquals(out.length, 1); assert(out[0].error!.includes('الإعفاء'));
  assertEquals([db.docs[0].hash, db.docs[1].status], [null, 'pending']);
});
