// ZATCA Phase 2 (Fatoora) — the e-invoice document itself, as pure functions (docs/ZATCA_PHASE2.md, step 2):
// build the UBL 2.1 XML of a sales invoice / credit note / debit note, its hash, the ECDSA (secp256k1) signature with the
// XAdES block, and the 9-field QR code. No network and no database here — the server function (step 3) feeds it.
//
// The XML is written already in canonical form (C14N 1.1: no XML declaration inside the hashed part, no whitespace between
// elements, empty elements as start + end tag, namespace declarations then attributes in canonical order), so the invoice
// hash ZATCA computes — the document without ext:UBLExtensions, cac:Signature and the QR reference, canonicalised — is the
// SHA-256 of exactly the string we hashed. Checked against ZATCA's own SDK (supabase/functions/_shared/zatca_test.ts).
import { secp256k1 } from 'npm:@noble/curves@1.4.0/secp256k1';
import { sha256 } from 'npm:@noble/hashes@1.4.0/sha256';

export type Party = {
  name: string; vat?: string | null; cr?: string | null;
  street?: string | null; building?: string | null; district?: string | null; city?: string | null; postal?: string | null; addNo?: string | null;
};
export type Line = { name: string; qty: number; price: number; rate: number; exemptCode?: string | null; exemptReason?: string | null };
export type ZDoc = {
  kind: 'invoice' | 'credit' | 'debit';
  type: 'standard' | 'simplified';      // standard = B2B (buyer has a VAT number) → clearance; simplified = B2C → reporting
  no: string; uuid: string; issueDate: string; issueTime: string;   // date YYYY-MM-DD, time HH:MM:SS (Riyadh)
  icv: number; pih: string;              // counter in the chain, hash of the previous document (base64)
  refNo?: string | null; reason?: string | null;   // credit / debit notes: the original invoice number and the reason
  supplyDate?: string | null;            // standard invoices: the supply date (defaults to the issue date)
  payCode?: string | null;               // UNTDID 4461: 10 cash, 30 credit transfer, 42 bank account, 48 card, 1 not defined
  seller: Party; buyer?: Party | null; lines: Line[];
};

const NS = 'xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2" xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2" xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2" xmlns:ext="urn:oasis:names:specification:ubl:schema:xsd:CommonExtensionComponents-2"';
export const PIH0 = 'NWZlY2ViNjZmZmM4NmYzOGQ5NTI3ODZjNmQ2OTZjNzljMmRiYzIzOWRkNGU5MWI0NjcyOWQ3M2EyN2ZiNTdlOQ==';

// canonical text / attribute escaping (C14N)
const esc = (s: unknown) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\r/g, '&#xD;');
const escA = (s: unknown) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;').replace(/\t/g, '&#x9;').replace(/\n/g, '&#xA;').replace(/\r/g, '&#xD;');
const el = (tag: string, v: unknown, attrs = '') => `<${tag}${attrs}>${esc(v)}</${tag}>`;
const opt = (tag: string, v: unknown) => (v == null || String(v).trim() === '') ? '' : el(tag, String(v).trim());
export const r2 = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;
const a2 = (n: number) => r2(n).toFixed(2);
const SAR = ' currencyID="SAR"';

// money as Waad posts it: line amount = qty × price rounded, line VAT = amount × rate rounded; per-category VAT from the taxable sum
export function totals(d: ZDoc) {
  const lines = d.lines.map((l, i) => { const amount = r2(l.qty * l.price); return { ...l, i: i + 1, amount, vat: r2(amount * l.rate / 100) }; });
  const cats = new Map<string, { cat: string; rate: number; taxable: number; code?: string | null; reason?: string | null }>();
  for (const l of lines) {
    const cat = l.rate > 0 ? 'S' : (l.exemptCode && /^VATEX-SA-(29|29-7|30)$/.test(l.exemptCode) ? 'E' : 'Z');
    const k = cat + '|' + l.rate + '|' + (l.exemptCode || '');
    const c = cats.get(k) || { cat, rate: l.rate, taxable: 0, code: l.exemptCode, reason: l.exemptReason };
    c.taxable = r2(c.taxable + l.amount); cats.set(k, c);
  }
  const subs = [...cats.values()].map(c => ({ ...c, tax: r2(c.taxable * c.rate / 100) }));
  const net = r2(lines.reduce((a, l) => a + l.amount, 0)), vat = r2(subs.reduce((a, c) => a + c.tax, 0));
  return { lines, subs, net, vat, gross: r2(net + vat) };
}

function party(p: Party, seller: boolean) {
  const id = p.cr ? el('cbc:ID', p.cr, ' schemeID="CRN"') : '';
  const addr = '<cac:PostalAddress>' + opt('cbc:StreetName', p.street) + opt('cbc:AdditionalStreetName', null) + opt('cbc:BuildingNumber', p.building)
    + opt('cbc:PlotIdentification', p.addNo) + opt('cbc:CitySubdivisionName', p.district) + opt('cbc:CityName', p.city) + opt('cbc:PostalZone', p.postal)
    + '<cac:Country><cbc:IdentificationCode>SA</cbc:IdentificationCode></cac:Country></cac:PostalAddress>';
  const tax = p.vat ? `<cac:PartyTaxScheme>${el('cbc:CompanyID', p.vat)}<cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:PartyTaxScheme>`
    : (seller ? '' : '<cac:PartyTaxScheme><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:PartyTaxScheme>');
  return `<cac:Party>${id ? `<cac:PartyIdentification>${id}</cac:PartyIdentification>` : ''}${addr}${tax}<cac:PartyLegalEntity>${el('cbc:RegistrationName', p.name)}</cac:PartyLegalEntity></cac:Party>`;
}

const taxCat = (c: { cat: string; rate: number; code?: string | null; reason?: string | null }) =>
  `<cac:TaxCategory><cbc:ID schemeAgencyID="6" schemeID="UN/ECE 5305">${c.cat}</cbc:ID><cbc:Percent>${a2(c.rate)}</cbc:Percent>`
  + (c.cat !== 'S' ? opt('cbc:TaxExemptionReasonCode', c.code) + opt('cbc:TaxExemptionReason', c.reason) : '')
  + '<cac:TaxScheme><cbc:ID schemeAgencyID="6" schemeID="UN/ECE 5153">VAT</cbc:ID></cac:TaxScheme></cac:TaxCategory>';

// the parts of the document; ext (UBLExtensions), qr and sig are added when signing
export function invoiceParts(d: ZDoc) {
  const t = totals(d);
  for (const l of t.lines) if (l.rate === 0 && !l.exemptCode) throw new Error(`البند «${l.name}» بضريبة صفر — حدّد سبب الإعفاء أو نسبة الصفر`);
  const typeCode = { invoice: 388, credit: 381, debit: 383 }[d.kind];
  const name = d.type === 'standard' ? '0100000' : '0200000';
  const head = el('cbc:ProfileID', 'reporting:1.0') + el('cbc:ID', d.no) + el('cbc:UUID', d.uuid) + el('cbc:IssueDate', d.issueDate) + el('cbc:IssueTime', d.issueTime)
    + el('cbc:InvoiceTypeCode', typeCode, ` name="${name}"`) + el('cbc:DocumentCurrencyCode', 'SAR') + el('cbc:TaxCurrencyCode', 'SAR')
    + (d.kind !== 'invoice' ? `<cac:BillingReference><cac:InvoiceDocumentReference>${el('cbc:ID', d.refNo || '')}</cac:InvoiceDocumentReference></cac:BillingReference>` : '')
    + `<cac:AdditionalDocumentReference><cbc:ID>ICV</cbc:ID>${el('cbc:UUID', d.icv)}</cac:AdditionalDocumentReference>`
    + `<cac:AdditionalDocumentReference><cbc:ID>PIH</cbc:ID><cac:Attachment>${el('cbc:EmbeddedDocumentBinaryObject', d.pih, ' mimeCode="text/plain"')}</cac:Attachment></cac:AdditionalDocumentReference>`;
  const buyer = d.buyer || { name: '' };
  const tail = `<cac:AccountingSupplierParty>${party(d.seller, true)}</cac:AccountingSupplierParty>`
    + `<cac:AccountingCustomerParty>${d.buyer ? party(buyer, false) : ''}</cac:AccountingCustomerParty>`
    + (d.type === 'standard' || d.supplyDate ? `<cac:Delivery>${el('cbc:ActualDeliveryDate', d.supplyDate || d.issueDate)}</cac:Delivery>` : '')
    + `<cac:PaymentMeans>${el('cbc:PaymentMeansCode', d.payCode || '10')}${d.kind !== 'invoice' ? el('cbc:InstructionNote', d.reason || '') : ''}</cac:PaymentMeans>`
    + `<cac:TaxTotal>${el('cbc:TaxAmount', a2(t.vat), SAR)}</cac:TaxTotal>`
    + `<cac:TaxTotal>${el('cbc:TaxAmount', a2(t.vat), SAR)}${t.subs.map(c => `<cac:TaxSubtotal>${el('cbc:TaxableAmount', a2(c.taxable), SAR)}${el('cbc:TaxAmount', a2(c.tax), SAR)}${taxCat(c)}</cac:TaxSubtotal>`).join('')}</cac:TaxTotal>`
    + `<cac:LegalMonetaryTotal>${el('cbc:LineExtensionAmount', a2(t.net), SAR)}${el('cbc:TaxExclusiveAmount', a2(t.net), SAR)}${el('cbc:TaxInclusiveAmount', a2(t.gross), SAR)}`
    + `${el('cbc:AllowanceTotalAmount', '0.00', SAR)}${el('cbc:PrepaidAmount', '0.00', SAR)}${el('cbc:PayableAmount', a2(t.gross), SAR)}</cac:LegalMonetaryTotal>`
    + t.lines.map(l => `<cac:InvoiceLine>${el('cbc:ID', l.i)}${el('cbc:InvoicedQuantity', +l.qty.toFixed(6), ' unitCode="PCE"')}${el('cbc:LineExtensionAmount', a2(l.amount), SAR)}`
      + `<cac:TaxTotal>${el('cbc:TaxAmount', a2(l.vat), SAR)}${el('cbc:RoundingAmount', a2(l.amount + l.vat), SAR)}</cac:TaxTotal>`
      + `<cac:Item>${el('cbc:Name', l.name)}<cac:ClassifiedTaxCategory>${el('cbc:ID', l.rate > 0 ? 'S' : (l.exemptCode && /^VATEX-SA-(29|29-7|30)$/.test(l.exemptCode) ? 'E' : 'Z'))}${el('cbc:Percent', a2(l.rate))}<cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:ClassifiedTaxCategory></cac:Item>`
      + `<cac:Price>${el('cbc:PriceAmount', +l.price.toFixed(6), SAR)}</cac:Price></cac:InvoiceLine>`).join('');
  return { head, tail, totals: t };
}

const enc = new TextEncoder();
export const b64 = (u: Uint8Array) => btoa(String.fromCharCode(...u));
export const unb64 = (s: string) => Uint8Array.from(atob(s.replace(/\s+/g, '')), c => c.charCodeAt(0));
const hex = (u: Uint8Array) => [...u].map(b => b.toString(16).padStart(2, '0')).join('');

// the document without the signature parts, exactly as ZATCA canonicalises it before hashing
export const hashedXml = (d: ZDoc) => { const p = invoiceParts(d); return `<Invoice ${NS}>${p.head}${p.tail}</Invoice>`; };
// invoice hash: SHA-256 of the canonical document, base64 of the raw digest
export const invoiceHash = (d: ZDoc) => b64(sha256(enc.encode(hashedXml(d))));

// ---- a tiny DER reader: enough for the certificate fields the XAdES block and the QR need ----
type Node = { tag: number; start: number; hlen: number; len: number; end: number };
function node(b: Uint8Array, i: number): Node {
  const tag = b[i]; let len = b[i + 1], hlen = 2;
  if (len & 0x80) { const n = len & 0x7f; len = 0; for (let k = 0; k < n; k++) len = len * 256 + b[i + 2 + k]; hlen = 2 + n; }
  return { tag, start: i, hlen, len, end: i + hlen + len };
}
function kids(b: Uint8Array, n: Node) { const out: Node[] = []; let i = n.start + n.hlen; while (i < n.end) { const c = node(b, i); out.push(c); i = c.end; } return out; }
const OIDN: Record<string, string> = { '2.5.4.3': 'CN', '2.5.4.6': 'C', '2.5.4.10': 'O', '2.5.4.11': 'OU', '0.9.2342.19200300.100.1.25': 'DC' };
function oid(b: Uint8Array) { const out = [Math.floor(b[0] / 40), b[0] % 40]; let v = 0; for (let i = 1; i < b.length; i++) { v = v * 128 + (b[i] & 0x7f); if (!(b[i] & 0x80)) { out.push(v); v = 0; } } return out.join('.'); }
export function certInfo(certB64: string) {
  const der = unb64(certB64), cert = node(der, 0), [tbs, , sigV] = kids(der, cert), tk = kids(der, tbs);
  const off = tk[0].tag === 0xa0 ? 1 : 0, serialN = tk[off], issuerN = tk[off + 2], spkiN = tk[off + 5];
  let serial = 0n; for (const x of der.slice(serialN.start + serialN.hlen, serialN.end)) serial = serial * 256n + BigInt(x);
  const rdns = kids(der, issuerN).map(set => { const atv = kids(der, kids(der, set)[0]); const [o, v] = atv;
    const name = OIDN[oid(der.slice(o.start + o.hlen, o.end))] || oid(der.slice(o.start + o.hlen, o.end)); return name + '=' + new TextDecoder().decode(der.slice(v.start + v.hlen, v.end)); });
  return {
    issuer: rdns.reverse().join(', '),                         // RFC 2253 order, as Java prints it
    serial: serial.toString(),
    spki: der.slice(spkiN.start, spkiN.end),                   // QR tag 8: the public key (SubjectPublicKeyInfo DER)
    signature: der.slice(sigV.start + sigV.hlen + 1, sigV.end), // QR tag 9: the CA's signature on the certificate
  };
}

// QR: TLV fields 1–9 (9 = certificate signature, simplified invoices), base64
export function qrTlv(f: (string | Uint8Array)[]) {
  const parts: number[] = [];
  f.forEach((v, i) => { const u = typeof v === 'string' ? enc.encode(v) : v; if (u.length > 255) throw new Error('QR field too long'); parts.push(i + 1, u.length, ...u); });
  return b64(Uint8Array.from(parts));
}

// private key: the PEM from the CSR step (SEC1 "EC PRIVATE KEY" or PKCS#8) → 32 raw bytes
export function rawKey(pem: string) {
  const body = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, ''), der = unb64(body);
  for (let i = 0; i < der.length - 33; i++) if (der[i] === 0x04 && der[i + 1] === 0x20 && (der[i - 1] === 0x01 || der[i - 3] === 0x02)) return der.slice(i + 2, i + 34);
  throw new Error('private key not recognised');
}

const SP = (time: string, certHash: string, issuer: string, serial: string) =>
  `<xades:SignedProperties xmlns:xades="http://uri.etsi.org/01903/v1.3.2#" Id="xadesSignedProperties">`
  + `<xades:SignedSignatureProperties><xades:SigningTime>${time}</xades:SigningTime><xades:SigningCertificate><xades:Cert><xades:CertDigest>`
  + `<ds:DigestMethod xmlns:ds="http://www.w3.org/2000/09/xmldsig#" Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"></ds:DigestMethod>`
  + `<ds:DigestValue xmlns:ds="http://www.w3.org/2000/09/xmldsig#">${certHash}</ds:DigestValue></xades:CertDigest><xades:IssuerSerial>`
  + `<ds:X509IssuerName xmlns:ds="http://www.w3.org/2000/09/xmldsig#">${esc(issuer)}</ds:X509IssuerName><ds:X509SerialNumber xmlns:ds="http://www.w3.org/2000/09/xmldsig#">${serial}</ds:X509SerialNumber>`
  + `</xades:IssuerSerial></xades:Cert></xades:SigningCertificate></xades:SignedSignatureProperties></xades:SignedProperties>`;

// sign: hash → ECDSA-SHA256 over the hash bytes → XAdES block + QR → the full XML (with declaration) ready to send
export function signInvoice(d: ZDoc, opts: { certB64: string; keyPem: string; signingTime: string }) {
  const p = invoiceParts(d), hash = b64(sha256(enc.encode(`<Invoice ${NS}>${p.head}${p.tail}</Invoice>`)));
  const key = rawKey(opts.keyPem), sig = b64(secp256k1.sign(sha256(unb64(hash)), key).toDERRawBytes());
  const ci = certInfo(opts.certB64), certHash = btoa(hex(sha256(enc.encode(opts.certB64))));
  const spHash = btoa(hex(sha256(enc.encode(SP(opts.signingTime, certHash, ci.issuer, ci.serial)))));
  const t = p.totals, ts = d.issueDate + 'T' + d.issueTime;
  const qr = qrTlv([d.seller.name, d.seller.vat || '', ts, a2(t.gross), a2(t.vat), hash, sig, ci.spki, ...(d.type === 'simplified' ? [ci.signature] : [])]);
  const ext = '<ext:UBLExtensions><ext:UBLExtension><ext:ExtensionURI>urn:oasis:names:specification:ubl:dsig:enveloped:xades</ext:ExtensionURI><ext:ExtensionContent>'
    + '<sig:UBLDocumentSignatures xmlns:sac="urn:oasis:names:specification:ubl:schema:xsd:SignatureAggregateComponents-2" xmlns:sbc="urn:oasis:names:specification:ubl:schema:xsd:SignatureBasicComponents-2" xmlns:sig="urn:oasis:names:specification:ubl:schema:xsd:CommonSignatureComponents-2">'
    + '<sac:SignatureInformation><cbc:ID>urn:oasis:names:specification:ubl:signature:1</cbc:ID><sbc:ReferencedSignatureID>urn:oasis:names:specification:ubl:signature:Invoice</sbc:ReferencedSignatureID>'
    + '<ds:Signature xmlns:ds="http://www.w3.org/2000/09/xmldsig#" Id="signature"><ds:SignedInfo>'
    + '<ds:CanonicalizationMethod Algorithm="http://www.w3.org/2006/12/xml-c14n11"></ds:CanonicalizationMethod><ds:SignatureMethod Algorithm="http://www.w3.org/2001/04/xmldsig-more#ecdsa-sha256"></ds:SignatureMethod>'
    + '<ds:Reference Id="invoiceSignedData" URI=""><ds:Transforms>'
    + '<ds:Transform Algorithm="http://www.w3.org/TR/1999/REC-xpath-19991116"><ds:XPath>not(//ancestor-or-self::ext:UBLExtensions)</ds:XPath></ds:Transform>'
    + '<ds:Transform Algorithm="http://www.w3.org/TR/1999/REC-xpath-19991116"><ds:XPath>not(//ancestor-or-self::cac:Signature)</ds:XPath></ds:Transform>'
    + '<ds:Transform Algorithm="http://www.w3.org/TR/1999/REC-xpath-19991116"><ds:XPath>not(//ancestor-or-self::cac:AdditionalDocumentReference[cbc:ID=\'QR\'])</ds:XPath></ds:Transform>'
    + '<ds:Transform Algorithm="http://www.w3.org/2006/12/xml-c14n11"></ds:Transform></ds:Transforms>'
    + `<ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"></ds:DigestMethod><ds:DigestValue>${hash}</ds:DigestValue></ds:Reference>`
    + `<ds:Reference Type="http://www.w3.org/2000/09/xmldsig#SignatureProperties" URI="#xadesSignedProperties"><ds:DigestMethod Algorithm="http://www.w3.org/2001/04/xmlenc#sha256"></ds:DigestMethod><ds:DigestValue>${spHash}</ds:DigestValue></ds:Reference>`
    + `</ds:SignedInfo><ds:SignatureValue>${sig}</ds:SignatureValue><ds:KeyInfo><ds:X509Data><ds:X509Certificate>${opts.certB64}</ds:X509Certificate></ds:X509Data></ds:KeyInfo>`
    + `<ds:Object><xades:QualifyingProperties xmlns:xades="http://uri.etsi.org/01903/v1.3.2#" Target="signature">`
    + SP(opts.signingTime, certHash, ci.issuer, ci.serial).replace(' xmlns:xades="http://uri.etsi.org/01903/v1.3.2#"', '').replace(/ xmlns:ds="http:\/\/www\.w3\.org\/2000\/09\/xmldsig#"/g, '')
    + '</xades:QualifyingProperties></ds:Object></ds:Signature></sac:SignatureInformation></sig:UBLDocumentSignatures></ext:ExtensionContent></ext:UBLExtension></ext:UBLExtensions>';
  const qrRef = `<cac:AdditionalDocumentReference><cbc:ID>QR</cbc:ID><cac:Attachment>${el('cbc:EmbeddedDocumentBinaryObject', qr, ' mimeCode="text/plain"')}</cac:Attachment></cac:AdditionalDocumentReference>`;
  const sigRef = '<cac:Signature><cbc:ID>urn:oasis:names:specification:ubl:signature:Invoice</cbc:ID><cbc:SignatureMethod>urn:oasis:names:specification:ubl:dsig:enveloped:xades</cbc:SignatureMethod></cac:Signature>';
  const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<Invoice ${NS}>${ext}${p.head}${qrRef}${sigRef}${p.tail}</Invoice>`;
  return { xml, hash, signature: sig, qr, totals: t };
}
export { escA };
