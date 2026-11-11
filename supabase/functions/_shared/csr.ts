// ZATCA onboarding, step 1: a new secp256k1 key and the certificate signing request (PKCS#10) Fatoora expects
// (docs/ZATCA_PHASE2.md, step 3). Built with a small DER encoder — no OpenSSL on the server.
import { secp256k1 } from 'npm:@noble/curves@1.4.0/secp256k1';
import { sha256 } from 'npm:@noble/hashes@1.4.0/sha256';
import { b64 } from './zatca.ts';

export type Env = 'sandbox' | 'simulation' | 'production';
export const TEMPLATE: Record<Env, string> = { sandbox: 'TSTZATCA-Code-Signing', simulation: 'PREZATCA-Code-Signing', production: 'ZATCA-Code-Signing' };

// ---- DER encoding ----
const len = (n: number) => n < 128 ? [n] : n < 256 ? [0x81, n] : [0x82, n >> 8, n & 255];
const tlv = (tag: number, body: Uint8Array | number[]) => Uint8Array.from([tag, ...len(body.length), ...body]);
const cat = (...p: Uint8Array[]) => { const o = new Uint8Array(p.reduce((a, x) => a + x.length, 0)); let i = 0; for (const x of p) { o.set(x, i); i += x.length; } return o; };
const seq = (...p: Uint8Array[]) => tlv(0x30, cat(...p));
const set = (...p: Uint8Array[]) => tlv(0x31, cat(...p));
const utf8 = (s: string) => tlv(0x0c, new TextEncoder().encode(s));
const printable = (s: string) => tlv(0x13, new TextEncoder().encode(s));
function oid(s: string) {
  const p = s.split('.').map(Number), out = [p[0] * 40 + p[1]];
  for (const v of p.slice(2)) { const b = [v & 0x7f]; let x = v >>> 7; while (x) { b.unshift((x & 0x7f) | 0x80); x >>>= 7; } out.push(...b); }
  return tlv(0x06, out);
}
const atv = (o: string, v: Uint8Array) => set(seq(oid(o), v));

export type CsrInput = {
  env: Env;
  vat: string;            // 15 digits, starts and ends with 3
  orgName: string;        // the taxpayer's name
  branch: string;         // branch / unit name (OU)
  egsName: string;        // a name for this e-invoicing unit (CN)
  egsSerial: string;      // "1-<solution>|2-<version>|3-<unit uuid>"
  invoiceTypes: string;   // 4 digits: standard, simplified, (future), (future) — "1100" = both
  address: string;        // the branch address (short)
  category: string;       // business category / industry
};

export function validVat(v: string) { return /^3\d{13}3$/.test(v); }

// returns the private key (SEC1 PEM, kept on the server only) and the CSR (base64 of the PEM, as the API takes it)
export function makeCsr(x: CsrInput, key = secp256k1.utils.randomPrivateKey()) {
  if (!validVat(x.vat)) throw new Error('الرقم الضريبي 15 رقماً يبدأ وينتهي بـ 3');
  const pub = secp256k1.getPublicKey(key, false);
  const subject = seq(atv('2.5.4.6', printable('SA')), atv('2.5.4.11', utf8(x.branch)), atv('2.5.4.10', utf8(x.orgName)), atv('2.5.4.3', utf8(x.egsName)));
  const spki = seq(seq(oid('1.2.840.10045.2.1'), oid('1.3.132.0.10')), tlv(0x03, [0, ...pub]));
  const dirName = seq(atv('2.5.4.4', utf8(x.egsSerial)), atv('0.9.2342.19200300.100.1.1', utf8(x.vat)), atv('2.5.4.12', utf8(x.invoiceTypes)),
    atv('2.5.4.26', utf8(x.address)), atv('2.5.4.15', utf8(x.category)));
  const san = seq(tlv(0xa4, dirName));
  const exts = seq(seq(oid('1.3.6.1.4.1.311.20.2'), tlv(0x04, utf8(TEMPLATE[x.env]))), seq(oid('2.5.29.17'), tlv(0x04, san)));
  const attrs = tlv(0xa0, seq(oid('1.2.840.113549.1.9.14'), set(exts)));
  const info = seq(tlv(0x02, [0]), subject, spki, attrs);
  const sig = secp256k1.sign(sha256(info), key).toDERRawBytes();
  const csr = seq(info, seq(oid('1.2.840.10045.4.3.2')), tlv(0x03, [0, ...sig]));
  const pem = (label: string, der: Uint8Array) => `-----BEGIN ${label}-----\n${b64(der).match(/.{1,64}/g)!.join('\n')}\n-----END ${label}-----\n`;
  const sec1 = seq(tlv(0x02, [1]), tlv(0x04, key), tlv(0xa0, oid('1.3.132.0.10')), tlv(0xa1, tlv(0x03, [0, ...pub])));
  return { keyPem: pem('EC PRIVATE KEY', sec1), csrB64: btoa(pem('CERTIFICATE REQUEST', csr)), csrDer: csr };
}
