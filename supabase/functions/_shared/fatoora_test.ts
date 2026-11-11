// Tests for the CSR and the onboarding flow, offline (ZATCA's API is replaced by a fake that checks each request).
// The same flow ran against ZATCA's developer sandbox on 2026-11-11: 3 CLEARED + 3 REPORTED, production certificate issued.
import { assert, assertEquals, assertRejects, assertThrows } from 'jsr:@std/assert@1.0.13';
import { secp256k1 } from 'npm:@noble/curves@1.4.0/secp256k1';
import { sha256 } from 'npm:@noble/hashes@1.4.0/sha256';
import { makeCsr } from './csr.ts';
import { companyProblems, onboard } from './fatoora.ts';
import { unb64 } from './zatca.ts';

// a certificate issued by ZATCA's developer sandbox (test only, public data) — stands in for the issued ones
const CERT = Deno.readTextFileSync(new URL('./zatca_test.ts', import.meta.url)).match(/const CERT = '([^']+)'/)![1];
const co = { name: 'مؤسسة الريادة', vat: '399999999900003', cr: '1010010000', street: 'الأمير سلطان', building: '2322', district: 'المربع', city: 'الرياض', postal: '23333', addNo: '1234' };
const csrIn = { env: 'sandbox' as const, vat: co.vat, orgName: co.name, branch: 'الرئيسي', egsName: 'Waad-1', egsSerial: '1-Waad|2-1.0|3-x', invoiceTypes: '1100', address: 'الرياض', category: 'trade' };

// DER walk: [tag, start of body, end] of the children of the node at i
const kids = (b: Uint8Array, i: number) => { const l0 = b[i + 1], n = l0 & 0x80 ? l0 & 0x7f : 0, hl = 2 + n; let L = n ? 0 : l0; for (let k = 0; k < n; k++) L = L * 256 + b[i + 2 + k];
  const out: number[] = []; for (let j = i + hl; j < i + hl + L;) { out.push(j); const m = b[j + 1], nn = m & 0x80 ? m & 0x7f : 0; let LL = nn ? 0 : m; for (let k = 0; k < nn; k++) LL = LL * 256 + b[j + 2 + k]; j += 2 + nn + LL; } return out; };

Deno.test('CSR: signed by its own key, secp256k1, with the template name and the unit details ZATCA reads', () => {
  const key = secp256k1.utils.randomPrivateKey(), r = makeCsr(csrIn, key), der = r.csrDer;
  const [info, , sig] = kids(der, 0), infoEnd = sig - 12;   // info, algorithm (12 bytes), signature
  const infoBytes = der.slice(info, infoEnd), sigBytes = der.slice(sig + 3);
  assert(secp256k1.verify(secp256k1.Signature.fromDER(sigBytes), sha256(infoBytes), secp256k1.getPublicKey(key)));
  const s = new TextDecoder().decode(der);
  for (const x of ['TSTZATCA-Code-Signing', '399999999900003', '1100', '1-Waad|2-1.0|3-x', 'Waad-1']) assert(s.includes(x), x);
  assert(atob(r.csrB64).startsWith('-----BEGIN CERTIFICATE REQUEST-----'));
  assert(r.keyPem.startsWith('-----BEGIN EC PRIVATE KEY-----'));
  assert(new TextDecoder().decode(makeCsr({ ...csrIn, env: 'production' }, key).csrDer).includes('ZATCA-Code-Signing'));
  assertThrows(() => makeCsr({ ...csrIn, vat: '123' }), Error, 'الرقم الضريبي');
});

Deno.test('company data: VAT number and national address are checked before asking ZATCA', () => {
  assertEquals(companyProblems(co), []);
  assertEquals(companyProblems({ ...co, vat: '300000000000000' }).length, 1);
  assert(companyProblems({ ...co, street: '' })[0].includes('العنوان الوطني'));
  assert(companyProblems({ ...co, building: '12' }).some(x => x.includes('4 أرقام')));
});

Deno.test('onboarding: OTP → compliance certificate → six documents → production certificate', async () => {
  const calls: { path: string; h: Headers; body: Record<string, string> }[] = [];
  const fake = (async (url: string, init: RequestInit) => {
    const path = url.replace(/^.*\/developer-portal/, ''), h = new Headers(init.headers), body = JSON.parse(String(init.body));
    calls.push({ path, h, body });
    const json = (o: unknown) => new Response(JSON.stringify(o), { status: 200 });
    if (path === '/compliance') return json({ requestID: 77, dispositionMessage: 'ISSUED', binarySecurityToken: btoa(CERT), secret: 's1' });
    if (path === '/compliance/invoices') { const xml = new TextDecoder().decode(unb64(body.invoice)); return json(xml.includes('name="0100000"') ? { clearanceStatus: 'CLEARED' } : { reportingStatus: 'REPORTED' }); }
    if (path === '/production/csids') return json({ binarySecurityToken: btoa(CERT), secret: 's2' });
    return new Response('?', { status: 404 });
  }) as typeof fetch;
  const r = await onboard('sandbox', co, '123345', new Date('2026-11-11T10:00:00Z'), fake);
  assertEquals(calls.map(c => c.path), ['/compliance', ...Array(6).fill('/compliance/invoices'), '/production/csids']);
  assertEquals(calls[0].h.get('OTP'), '123345');
  assertEquals(calls[1].h.get('Authorization'), 'Basic ' + btoa(btoa(CERT) + ':s1'));
  assertEquals(calls[7].body.compliance_request_id, '77');
  assertEquals(r.results.filter(x => /CLEARED|REPORTED/.test(x)).length, 6);
  assertEquals([r.cert, r.secret], [CERT, 's2']);
  // the six documents form a chain: each one's PIH is the previous one's hash
  const pihs = calls.slice(1, 7).map(c => new TextDecoder().decode(unb64(c.body.invoice)).match(/<cbc:ID>PIH<\/cbc:ID><cac:Attachment><cbc:EmbeddedDocumentBinaryObject mimeCode="text\/plain">([^<]+)/)![1]);
  assertEquals(pihs.slice(1), calls.slice(1, 6).map(c => c.body.invoiceHash));
});

Deno.test('onboarding stops with a clear message when ZATCA refuses the OTP', async () => {
  const fake = (async () => new Response(JSON.stringify({ errors: [{ message: 'Invalid OTP' }] }), { status: 400 })) as unknown as typeof fetch;
  await assertRejects(() => onboard('sandbox', co, '000000', new Date(), fake), Error, 'Invalid OTP');
  await assertRejects(() => onboard('sandbox', { ...co, postal: '' }, '123345', new Date(), fake), Error, 'العنوان الوطني');
});
