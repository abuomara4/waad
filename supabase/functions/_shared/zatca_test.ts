// Tests for the ZATCA document builder (zatca.ts). Run: deno test supabase/functions/_shared/
// The hash vectors were checked with ZATCA's SDK (-generateHash), and the same builder passed ZATCA's sandbox compliance
// check (simplified + standard invoice, credit note and debit note: REPORTED / CLEARED, no warnings) on 2026-11-11.
import { assert, assertEquals, assertThrows } from 'jsr:@std/assert@1.0.13';
import { secp256k1 } from 'npm:@noble/curves@1.4.0/secp256k1';
import { sha256 } from 'npm:@noble/hashes@1.4.0/sha256';
import { certInfo, hashedXml, invoiceHash, PIH0, signInvoice, totals, unb64, type ZDoc } from './zatca.ts';

// a certificate issued by ZATCA's developer sandbox (test only, public data)
const CERT = 'MIICFDCCAbqgAwIBAgIGAaHMlub6MAoGCCqGSM49BAMCMBUxEzARBgNVBAMMCmVJbnZvaWNpbmcwHhcNMjYxMTExMjE0OTU5WhcNMzExMTExMjEwMDAwWjBfMQswCQYDVQQGEwJTQTETMBEGA1UECwwKMzEyMzQ1Njc4OTETMBEGA1UECgwKMzEyMzQ1Njc4OTEmMCQGA1UEAwwdVFNULTg4NjQzMTE0NS0zMTIzNDU2Nzg5MDAwMDMwVjAQBgcqhkjOPQIBBgUrgQQACgNCAATBiww0LlOcA+xAqPwhpPDs43T8me+Ot7O5DlFbAkR1tVgUFFONU5Ax4uB1RFxzSgUDmxtETEVOremX6Q2KjM5Ao4GuMIGrMAwGA1UdEwEB/wQCMAAwgZoGA1UdEQSBkjCBj6SBjDCBiTE7MDkGA1UEBAwyMS1UU1R8Mi1UU1R8My1lZDIyZjFkOC1lNmEyLTExMTgtOWI1OC1kOWE4ZjExZTQ0NWYxHzAdBgoJkiaJk/IsZAEBDA8zMTIzNDU2Nzg5MDAwMDMxDTALBgNVBAwMBDExMTExDDAKBgNVBBoMA1RTVDEMMAoGA1UEDwwDVFNUMAoGCCqGSM49BAMCA0gAMEUCIQCYsJEQuPmmOtepFfzH3of+ksczAatk84XNqg1esVy5ogIgDbd0U96z/3c5ZIXd17LmFthpNE7SwAneWh2QcsXmPKs=';
const seller = { name: 'مؤسسة الريادة', vat: '312345678900003', cr: '1010010000', street: 'الأمير سلطان', building: '2322', district: 'المربع', city: 'الرياض', postal: '23333', addNo: '1234' };
const buyer = { name: 'شركة النخبة', vat: '310000000000003', street: 'صلاح الدين', building: '1111', district: 'المروج', city: 'الرياض', postal: '12222', addNo: '2222' };
const base = { no: 'INV-0001', uuid: '3cf5ee18-ee25-44ea-a444-2c37ba7f28be', issueDate: '2026-11-11', issueTime: '14:40:40', icv: 1, pih: PIH0, seller,
  lines: [{ name: 'خدمة صيانة', qty: 2, price: 200, rate: 15 }, { name: 'حبر طابعة', qty: 3, price: 33.33, rate: 15 }] };
const simp: ZDoc = { ...base, kind: 'invoice', type: 'simplified', buyer: null };
const std: ZDoc = { ...base, kind: 'invoice', type: 'standard', buyer };
const keyPem = (k: Uint8Array) => { // SEC1 EC private key PEM for a raw secp256k1 key
  const der = Uint8Array.from([0x30, 0x2e, 0x02, 0x01, 0x01, 0x04, 0x20, ...k, 0xa0, 0x07, 0x06, 0x05, 0x2b, 0x81, 0x04, 0x00, 0x0a]);
  return '-----BEGIN EC PRIVATE KEY-----\n' + btoa(String.fromCharCode(...der)) + '\n-----END EC PRIVATE KEY-----';
};
const tlv = (b64s: string) => { const u = unb64(b64s), out: Uint8Array[] = []; for (let i = 0; i < u.length;) { const l = u[i + 1]; out[u[i]] = u.slice(i + 2, i + 2 + l); i += 2 + l; } return out; };
const txt = (u: Uint8Array) => new TextDecoder().decode(u);

Deno.test('invoice hash = the value ZATCA SDK computes for the same document', () => {
  assertEquals(invoiceHash(simp), 'jm549PbOZTHkfHvXFYzF++Zu93dPuwvFOdsa1ad7ars=');
  assertEquals(invoiceHash(std), '3R7BgcKT5D14SbUiZMQphM4admCYGIgcoQkSMT3Dq3s=');
});

Deno.test('the hash covers the content: any change in amount or chain changes it', () => {
  assert(invoiceHash({ ...simp, lines: [{ ...simp.lines[0], price: 201 }] }) !== invoiceHash(simp));
  assert(invoiceHash({ ...simp, icv: 2 }) !== invoiceHash(simp));
  assert(invoiceHash({ ...simp, pih: 'x' }) !== invoiceHash(simp));
});

Deno.test('money: line amount and VAT rounded per line, VAT per category from the taxable sum', () => {
  const t = totals(simp);
  assertEquals([t.lines[1].amount, t.lines[1].vat, t.net, t.vat, t.gross], [99.99, 15, 499.99, 75, 574.99]);
});

Deno.test('a zero-rated line must say why (exemption code)', () => {
  assertThrows(() => hashedXml({ ...simp, lines: [{ name: 'تصدير', qty: 1, price: 100, rate: 0 }] }), Error, 'الإعفاء');
  const x = hashedXml({ ...simp, lines: [{ name: 'تصدير', qty: 1, price: 100, rate: 0, exemptCode: 'VATEX-SA-32', exemptReason: 'Export of goods' }] });
  assert(x.includes('<cbc:TaxExemptionReasonCode>VATEX-SA-32</cbc:TaxExemptionReasonCode>') && x.includes('>Z</cbc:ID>'));
});

Deno.test('document types: 388 invoice / 381 credit / 383 debit; credit and debit carry the original number and the reason', () => {
  assert(hashedXml(simp).includes('<cbc:InvoiceTypeCode name="0200000">388</cbc:InvoiceTypeCode>'));
  assert(hashedXml(std).includes('<cbc:InvoiceTypeCode name="0100000">388</cbc:InvoiceTypeCode>'));
  const cn = hashedXml({ ...simp, kind: 'credit', refNo: 'INV-0001', reason: 'إرجاع' });
  assert(cn.includes('>381<') && cn.includes('<cac:BillingReference><cac:InvoiceDocumentReference><cbc:ID>INV-0001</cbc:ID>') && cn.includes('<cbc:InstructionNote>إرجاع</cbc:InstructionNote>'));
  assert(hashedXml({ ...std, kind: 'debit', refNo: 'INV-0001', reason: 'فرق' }).includes('>383<'));
  assert(hashedXml(std).includes('<cac:Delivery><cbc:ActualDeliveryDate>2026-11-11</cbc:ActualDeliveryDate></cac:Delivery>'));
});

Deno.test('text is escaped (a name with & and <)', () => {
  assert(hashedXml({ ...simp, seller: { ...seller, name: 'A & B <Co>' } }).includes('A &amp; B &lt;Co&gt;'));
});

Deno.test('certificate: issuer, serial, public key and CA signature are read from the DER', () => {
  const c = certInfo(CERT);
  assertEquals([c.issuer, BigInt(c.serial).toString(16), c.spki.length], ['CN=eInvoicing', '1a1cc96e6fa', 88]);
  assert(c.signature[0] === 0x30);
});

Deno.test('signing: the signature verifies over the invoice hash, and the QR carries the 9 fields', () => {
  const k = secp256k1.utils.randomPrivateKey(), pub = secp256k1.getPublicKey(k);
  const s = signInvoice(simp, { certB64: CERT, keyPem: keyPem(k), signingTime: '2026-11-11T14:40:41' });
  assertEquals(s.hash, invoiceHash(simp));
  assert(secp256k1.verify(secp256k1.Signature.fromDER(unb64(s.signature)), sha256(unb64(s.hash)), pub));
  const q = tlv(s.qr);
  assertEquals([txt(q[1]), txt(q[2]), txt(q[3]), txt(q[4]), txt(q[5]), txt(q[6]), txt(q[7])],
    [seller.name, seller.vat, '2026-11-11T14:40:40', '574.99', '75.00', s.hash, s.signature]);
  assertEquals(q[8].length, 88); assert(q[9] && q[9][0] === 0x30);
  assert(!tlv(signInvoice(std, { certB64: CERT, keyPem: keyPem(k), signingTime: '2026-11-11T14:40:41' }).qr)[9], 'standard: no tag 9');
  // removing the signature parts gives back exactly the hashed document
  const stripped = s.xml.replace(/^<\?xml[^>]*>\n/, '').replace(/<ext:UBLExtensions>.*<\/ext:UBLExtensions>/, '')
    .replace(/<cac:AdditionalDocumentReference><cbc:ID>QR<\/cbc:ID>.*?<\/cac:AdditionalDocumentReference>/, '').replace(/<cac:Signature>.*?<\/cac:Signature>/, '');
  assertEquals(stripped, hashedXml(simp));
});
