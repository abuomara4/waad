// QR reader check (node app/tests/qrread_test.js): QR codes made by Waad's own encoder, "photographed" in code —
// rotated, tilted in perspective, blurred, noisy and unevenly lit — must read back exactly.
const fs = require('fs'), vm = require('vm'), path = require('path');
const ctx = { TextEncoder, TextDecoder, atob, btoa, Uint8Array, Uint8ClampedArray, Float32Array, Math, console };
vm.createContext(ctx);
for (const f of ['qr.js', 'qrread.js']) vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'src', f), 'utf8').replace(/^const (QR|QRREAD) =/m, 'this.$1 ='), ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'src', 'receipt_text.js'), 'utf8') + '\nthis.receiptFromText = receiptFromText; this.receiptCheck = receiptCheck;', ctx);
const { QR, QRREAD, receiptFromText, receiptCheck } = ctx;
let pass = 0, fail = 0; const ok = (c, m) => { if (c) pass++; else { fail++; console.log('FAIL', m); } };
// a pseudo-random generator so every run is the same
let seed = 7; const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
// the matrix → a white page with the code, then mapped through a homography (angle, tilt), blur, noise, light gradient
function photo(m, { px = 4, angle = 0, tilt = 0, blur = 0, noise = 0, light = 0, W = 900, H = 1200, cx = 0.5, cy = 0.5 }) {
  const n = m.length, q = 4, S = (n + q * 2) * px, src = new Uint8Array(S * S).fill(235);
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) if (m[y][x]) for (let dy = 0; dy < px; dy++) for (let dx = 0; dx < px; dx++) src[((y + q) * px + dy) * S + (x + q) * px + dx] = 30;
  const ca = Math.cos(angle), sa = Math.sin(angle), out = new Uint8ClampedArray(W * H * 4);
  for (let Y = 0; Y < H; Y++) for (let X = 0; X < W; X++) {
    let u = X - W * cx, v = Y - H * cy; const wq = 1 - tilt * v / H; u /= wq; v /= wq;   // keystone tilt (a true perspective)
    const sx = ca * u + sa * v + S / 2, sy = -sa * u + ca * v + S / 2;
    let g = 245; if (sx >= 0 && sy >= 0 && sx < S - 1 && sy < S - 1) { const x0 = Math.floor(sx), y0 = Math.floor(sy), fx = sx - x0, fy = sy - y0;
      g = src[y0 * S + x0] * (1 - fx) * (1 - fy) + src[y0 * S + x0 + 1] * fx * (1 - fy) + src[(y0 + 1) * S + x0] * (1 - fx) * fy + src[(y0 + 1) * S + x0 + 1] * fx * fy; }
    g = g * (1 - light * X / W) + (rnd() - 0.5) * noise; const i = (Y * W + X) * 4; out[i] = out[i + 1] = out[i + 2] = g; out[i + 3] = 255;
  }
  if (blur) { const c = Uint8ClampedArray.from(out); for (let Y = 1; Y < H - 1; Y++) for (let X = 1; X < W - 1; X++) { let s = 0; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) s += c[((Y + dy) * W + X + dx) * 4]; const i = (Y * W + X) * 4; out[i] = out[i + 1] = out[i + 2] = s / 9; } }
  return { data: out, width: W, height: H };
}
const enc = new TextEncoder(), dec = new TextDecoder();
// a phase-1 invoice QR and a long phase-2 one (hash, signature, key, certificate signature → about version 15)
const p1 = QR.zatca({ seller: 'مؤسسة الريادة للتجارة', vat: '300000000000003', time: '2026-11-26T10:15:00Z', total: 1150, tax: 150 });
const big = new Uint8Array(70).map((_, i) => (i * 37) & 255), p2 = Buffer.from([...Buffer.from(p1, 'base64'), 6, 44, ...enc.encode('A'.repeat(44)), 7, 70, ...big, 8, 88, ...new Uint8Array(88).fill(9), 9, 70, ...big]).toString('base64');
const cases = [['straight', {}], ['rotated 30°', { angle: Math.PI / 6 }], ['upside down', { angle: Math.PI }], ['rotated 100°', { angle: 1.75 }],
  ['tilted', { tilt: 0.35 }], ['tilted and rotated', { tilt: 0.3, angle: 0.5 }], ['blurred', { blur: 1 }], ['noisy', { noise: 60 }], ['uneven light', { light: 0.45 }],
  ['small (3 px a module)', { px: 3 }], ['all together', { angle: 0.4, tilt: 0.25, blur: 1, noise: 40, light: 0.3 }], ['off centre', { cx: 0.35, cy: 0.62, angle: -0.3 }],
  ['45° and tilted', { angle: Math.PI / 4, tilt: 0.3 }], ['a small code on a big page', { px: 3, W: 1500, H: 2000, angle: 0.2, cx: 0.3, cy: 0.7 }],
  ['dim and noisy', { light: 0.6, noise: 80, blur: 1, angle: -0.6 }]];
for (const [name, text] of [['phase 1', p1], ['phase 2', p2]]) {
  const m = QR.encode(Array.from(enc.encode(text))).map(r => r.map(Boolean));
  for (const [cn, o] of cases) {
    const px = o.px || (m.length > 60 ? 6 : 8), img = photo(m, Object.assign({ W: 900, H: 1200 }, o, { px }));
    const t0 = Date.now(); let got = null; try { got = QRREAD.decode(img); } catch (e) { console.log('ERR', name, cn, e.message); }
    ok(got && dec.decode(got) === text, `${name} (version ${(m.length - 17) / 4}): ${cn}`);
    if (got) { const z = QRREAD.zatca(got); ok(z.seller === 'مؤسسة الريادة للتجارة' && z.vat === '300000000000003' && z.total === 1150 && z.tax === 150 && z.zatca, `${name}: ${cn} → ZATCA fields`); }
    console.log((got && dec.decode(got) === text ? 'PASS ' : 'FAIL ') + name + ' ' + cn + ' ' + (Date.now() - t0) + 'ms');
  }
}
// any language and any digits: the seller's name in Arabic, English, Urdu, Chinese, French, Hindi; numbers in Arabic-Indic digits
for (const seller of ['مؤسسة النخبة 2 للتجارة', 'Al Nukhba Trading Co. Ltd.', 'نخبہ ٹریڈنگ کمپنی', '精英贸易有限公司', 'Société Élite & Fils', 'एलीट ट्रेडिंग']) {
  const t = QR.zatca({ seller, vat: '310122393500003', time: '2026-11-27T08:05:00Z', total: 57.5, tax: 7.5 }), m = QR.encode(Array.from(enc.encode(t))).map(r => r.map(Boolean));
  const got = QRREAD.decode(photo(m, { px: 6, angle: 0.3, noise: 30 })), z = got && QRREAD.zatca(got);
  ok(z && z.seller === seller && z.vat === '310122393500003' && z.total === 57.5 && z.tax === 7.5, 'any language: ' + seller);
}
{ const tl = (tag, v) => { const b = enc.encode(v); return [tag, b.length, ...b]; };
  const t = Buffer.from([...tl(1, 'متجر الأمل'), ...tl(2, '٣٠٠٠٠٠٠٠٠٠٠٠٠٠٣'), ...tl(3, '2026-11-27T08:05:00Z'), ...tl(4, '١٢٣٫٤٥'), ...tl(5, '١٦٫١٠')]).toString('base64');
  const z = QRREAD.zatca(enc.encode(t)); ok(z.vat === '300000000000003' && z.total === 123.45 && z.tax === 16.1 && z.zatca, 'Arabic-Indic digits in the VAT number and amounts'); }
// the printed text of invoices without a QR (as the text reader returns it): total, VAT, VAT number, date, number, seller
const TX = [
  ['Arabic simplified invoice', `مؤسسة النخبة للتجارة\nفاتورة ضريبية مبسطة\nالرقم الضريبي: 300 0000 0000 0003\nرقم الفاتورة: INV-2291\nالتاريخ: 27/11/2026\nقهوة 2 × 15.00 30.00\nالمجموع قبل الضريبة 100.00\nضريبة القيمة المضافة 15% 15.00\nالإجمالي شامل الضريبة 115.00`,
    { seller: 'مؤسسة النخبة للتجارة', vat: '300000000000003', total: 115, tax: 15, date: '2026-11-27', ref: 'INV-2291' }],
  ['English receipt', `ALNUKHBA RESTAURANT\nTax Invoice\nVAT No 310122393500003\nInvoice No: 88341\nDate 2026-11-20 13:42\nSubtotal 1,000.00\nVAT 15% 150.00\nTOTAL 1,150.00`,
    { seller: 'ALNUKHBA RESTAURANT', vat: '310122393500003', total: 1150, tax: 150, date: '2026-11-20', ref: '88341' }],
  ['no VAT, Arabic-Indic digits', `بقالة الحي\nإيصال\nالتاريخ ٢٠٢٦/١١/٢٥\nخبز ٥٫٠٠\nحليب ١٢٫٥٠\nالمبلغ المستحق ١٧٫٥٠`, { seller: 'بقالة الحي', total: 17.5, date: '2026-11-25' }],
  ['a total on the next line', `Market One\nReceipt\nGrand Total\nSAR 64.90`, { seller: 'Market One', total: 64.9, invoice: true }],
];
for (const [name, text, want] of TX) { const z = receiptFromText(text); const bad = Object.keys(want).filter(k => z[k] !== want[k]);
  ok(!bad.length, 'invoice text: ' + name + (bad.length ? ' — ' + bad.map(k => k + '=' + JSON.stringify(z[k])).join(', ') : '')); }
// only invoices: these papers are not
const NOT = [['a letter', 'السلام عليكم\nنفيدكم بأن الاجتماع يوم 2026-11-30 الساعة 10\nمع التحية'], ['a menu', 'MENU\nBurger 25\nPizza 40\nJuice 12'],
  ['an ID card', 'المملكة العربية السعودية\nبطاقة الهوية الوطنية\n1021098767\nتاريخ الانتهاء 1450/05/20'], ['a payslip-like table', 'الاسم أحمد\nالراتب الأساسي 8000\nبدل السكن 2000'],
  ['numbers only', '125.00\n300.50\n2026-11-02']];
for (const [name, text] of NOT) ok(!receiptCheck(receiptFromText(text)).ok, 'not an invoice: ' + name);
for (const [name, text] of TX) ok(receiptCheck(receiptFromText(text), '2026-11-27').ok, 'is an invoice: ' + name);
// a ZATCA code is an invoice only with all its fields; and the sums are checked
const zq = (o) => Object.assign({ seller: 'مؤسسة', vat: '300000000000003', time: '2026-11-20T10:00:00Z', date: '2026-11-20', total: 115, tax: 15 }, o);
ok(receiptCheck(zq({}), '2026-11-27').ok && !receiptCheck(zq({}), '2026-11-27').warn.length, 'ZATCA invoice: complete and adds up');
ok(!receiptCheck(zq({ vat: '12345' }), '2026-11-27').ok && !receiptCheck({ raw: 'https://example.com' }, '2026-11-27').ok, 'ZATCA invoice: a wrong VAT number or a plain link is not an invoice');
ok(receiptCheck(zq({ tax: 40 }), '2026-11-27').warn.includes('rate'), 'warning: VAT is not 15% of the amount');
ok(receiptCheck(zq({ date: '2026-12-05' }), '2026-11-27').warn.includes('future') && receiptCheck(zq({ date: '2025-01-01' }), '2026-11-27').warn.includes('old'), 'warning: a future or year-old date');
// Reed–Solomon: errors up to half the correction codewords are fixed
const m0 = QR.encode(Array.from(enc.encode(p1))).map(r => r.map(x => (x ? 1 : 0)));
const dirty = m0.map(r => r.slice()); for (let k = 0; k < 25; k++) { const y = 9 + Math.floor(rnd() * (m0.length - 18)), x = 9 + Math.floor(rnd() * (m0.length - 18)); dirty[y][x] ^= 1; }
let rd = null; try { rd = QRREAD.readMatrix(dirty); } catch (e) { console.log('ERR rs', e.message); }
ok(rd && dec.decode(rd) === p1, 'Reed–Solomon repairs 25 wrong modules');
ok(!QRREAD.decode(photo([[0]], { px: 1, W: 300, H: 300 })), 'a page with no code reads as nothing');
console.log(`${pass} passed, ${fail} failed`);
