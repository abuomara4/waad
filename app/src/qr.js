/* ZATCA phase-1 e-invoice QR: TLV (seller, VAT no., timestamp, total, VAT) → base64 → QR code (byte mode, ECC M).
   Self-contained QR encoder (no external library): versions 1–40, all 8 masks scored, best kept. */
const QR = (() => {
  const ECC = [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28];
  const BLK = [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49];
  const rawMods = v => { let r = (16 * v + 128) * v + 64; if (v >= 2) { const n = Math.floor(v / 7) + 2; r -= (25 * n - 10) * n - 55; if (v >= 7) r -= 36; } return r; };
  const dataCw = v => Math.floor(rawMods(v) / 8) - ECC[v] * BLK[v];
  const mul = (x, y) => { let z = 0; for (let i = 7; i >= 0; i--) { z = (z << 1) ^ ((z >>> 7) * 0x11d); z ^= ((y >>> i) & 1) * x; } return z & 255; };
  const divisor = deg => { const r = new Array(deg).fill(0); r[deg - 1] = 1; let root = 1; for (let i = 0; i < deg; i++) { for (let j = 0; j < r.length; j++) { r[j] = mul(r[j], root); if (j + 1 < r.length) r[j] ^= r[j + 1]; } root = mul(root, 2); } return r; };
  const remainder = (data, dv) => { const r = dv.map(() => 0); for (const b of data) { const f = b ^ r.shift(); r.push(0); dv.forEach((c, i) => r[i] ^= mul(c, f)); } return r; };
  const align = v => { if (v === 1) return []; const n = Math.floor(v / 7) + 2, step = v === 32 ? 26 : Math.ceil((v * 4 + 4) / (n * 2 - 2)) * 2, r = [6]; for (let p = v * 4 + 10; r.length < n; p -= step) r.splice(1, 0, p); return r; };

  function encode(bytes) {
    let v = 1; for (; v <= 40; v++) if (4 + (v < 10 ? 8 : 16) + bytes.length * 8 <= dataCw(v) * 8) break;
    if (v > 40) throw new Error('QR data too long');
    const bits = []; const put = (val, len) => { for (let i = len - 1; i >= 0; i--) bits.push((val >>> i) & 1); };
    put(4, 4); put(bytes.length, v < 10 ? 8 : 16); bytes.forEach(b => put(b, 8));
    const cap = dataCw(v) * 8; put(0, Math.min(4, cap - bits.length)); put(0, (8 - bits.length % 8) % 8);
    for (let p = 0xec; bits.length < cap; p ^= 0xec ^ 0x11) put(p, 8);
    const data = []; for (let i = 0; i < bits.length; i += 8) data.push(bits.slice(i, i + 8).reduce((a, b) => a * 2 + b, 0));
    // split into blocks, add ECC, interleave
    const nb = BLK[v], ec = ECC[v], raw = Math.floor(rawMods(v) / 8), nShort = nb - raw % nb, shortLen = Math.floor(raw / nb), dv = divisor(ec), blocks = [];
    for (let i = 0, k = 0; i < nb; i++) { const dat = data.slice(k, k + shortLen - ec + (i < nShort ? 0 : 1)); k += dat.length; const e = remainder(dat, dv); if (i < nShort) dat.push(0); blocks.push(dat.concat(e)); }
    const cw = []; for (let i = 0; i < blocks[0].length; i++) blocks.forEach((b, j) => { if (i !== shortLen - ec || j >= nShort) cw.push(b[i]); });
    // matrix
    const n = v * 4 + 17, m = [], fn = []; for (let i = 0; i < n; i++) { m.push(new Array(n).fill(false)); fn.push(new Array(n).fill(false)); }
    const set = (x, y, d) => { m[y][x] = d; fn[y][x] = true; };
    for (let i = 0; i < n; i++) { set(6, i, i % 2 === 0); set(i, 6, i % 2 === 0); }
    const finder = (x, y) => { for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) { const d = Math.max(Math.abs(dx), Math.abs(dy)), xx = x + dx, yy = y + dy; if (xx >= 0 && xx < n && yy >= 0 && yy < n) set(xx, yy, d !== 2 && d !== 4); } };
    finder(3, 3); finder(n - 4, 3); finder(3, n - 4);
    const ap = align(v); ap.forEach((a, i) => ap.forEach((b, j) => { if (!((i === 0 && j === 0) || (i === 0 && j === ap.length - 1) || (i === ap.length - 1 && j === 0))) for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) set(a + dx, b + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1); }));
    const fmt = mask => { const d = (0 << 3) | mask; let r = d; for (let i = 0; i < 10; i++) r = (r << 1) ^ ((r >>> 9) * 0x537); const b = ((d << 10) | r) ^ 0x5412, bit = i => ((b >>> i) & 1) !== 0;
      for (let i = 0; i <= 5; i++) set(8, i, bit(i)); set(8, 7, bit(6)); set(8, 8, bit(7)); set(7, 8, bit(8)); for (let i = 9; i < 15; i++) set(14 - i, 8, bit(i));
      for (let i = 0; i < 8; i++) set(n - 1 - i, 8, bit(i)); for (let i = 8; i < 15; i++) set(8, n - 15 + i, bit(i)); set(8, n - 8, true); };
    fmt(0);
    if (v >= 7) { let r = v; for (let i = 0; i < 12; i++) r = (r << 1) ^ ((r >>> 11) * 0x1f25); const b = (v << 12) | r; for (let i = 0; i < 18; i++) { const bt = ((b >>> i) & 1) !== 0, a = n - 11 + i % 3, c = Math.floor(i / 3); set(a, c, bt); set(c, a, bt); } }
    // place data (zigzag)
    let i = 0; for (let right = n - 1; right >= 1; right -= 2) { if (right === 6) right = 5; for (let vert = 0; vert < n; vert++) for (let j = 0; j < 2; j++) { const x = right - j, up = ((right + 1) & 2) === 0, y = up ? n - 1 - vert : vert; if (!fn[y][x] && i < cw.length * 8) { m[y][x] = ((cw[i >>> 3] >>> (7 - (i & 7))) & 1) !== 0; i++; } } }
    const maskFn = [(x, y) => (x + y) % 2 === 0, (x, y) => y % 2 === 0, x => x % 3 === 0, (x, y) => (x + y) % 3 === 0, (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0, (x, y) => x * y % 2 + x * y % 3 === 0, (x, y) => (x * y % 2 + x * y % 3) % 2 === 0, (x, y) => ((x + y) % 2 + x * y % 3) % 2 === 0];
    const applyMask = k => { for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) if (!fn[y][x] && maskFn[k](x, y)) m[y][x] = !m[y][x]; };
    const penalty = () => { let p = 0; const line = get => { for (let a = 0; a < n; a++) { let run = 1; const seq = []; for (let b = 0; b < n; b++) seq.push(get(a, b) ? 1 : 0);
        for (let b = 1; b <= n; b++) { if (b < n && seq[b] === seq[b - 1]) run++; else { if (run >= 5) p += run - 2; run = 1; } }
        const s = seq.join(''); for (const pat of ['10111010000', '00001011101']) { let k = s.indexOf(pat); while (k >= 0) { p += 40; k = s.indexOf(pat, k + 1); } } } };
      line((a, b) => m[a][b]); line((a, b) => m[b][a]);
      for (let y = 0; y < n - 1; y++) for (let x = 0; x < n - 1; x++) { const c = m[y][x]; if (c === m[y][x + 1] && c === m[y + 1][x] && c === m[y + 1][x + 1]) p += 3; }
      let dark = 0; m.forEach(r => r.forEach(c => { if (c) dark++; })); p += Math.floor(Math.abs(dark * 20 - n * n * 10) / (n * n)) * 10; return p; };
    let best = 0, bestP = Infinity; for (let k = 0; k < 8; k++) { applyMask(k); fmt(k); const p = penalty(); if (p < bestP) { bestP = p; best = k; } applyMask(k); }
    applyMask(best); fmt(best); return m;
  }
  const svg = (text, px) => { const m = encode(Array.from(new TextEncoder().encode(text))), n = m.length, q = 4, s = n + q * 2; let d = '';
    m.forEach((r, y) => r.forEach((c, x) => { if (c) d += `M${x + q} ${y + q}h1v1h-1z`; }));
    return `<svg class="qr" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${s} ${s}" width="${px || 130}" height="${px || 130}" shape-rendering="crispEdges"><rect width="${s}" height="${s}" fill="#fff"/><path d="${d}" fill="#000"/></svg>`; };
  // ZATCA TLV: tag(1 byte) + length(1 byte, UTF-8 bytes) + value; base64 of the whole
  const tlv = fields => { const out = []; fields.forEach((v, i) => { const b = Array.from(new TextEncoder().encode(String(v))); if (b.length > 255) throw new Error('TLV value too long'); out.push(i + 1, b.length, ...b); }); return btoa(String.fromCharCode(...out)); };
  const zatca = ({ seller, vat, time, total, tax }) => tlv([seller, vat, time, (+total).toFixed(2), (+tax).toFixed(2)]);
  return { encode, svg, tlv, zatca };
})();
/* ISO-8601 UTC timestamp of the invoice (seconds precision, as ZATCA examples) */
const zatcaTime = d => new Date(d).toISOString().replace(/\.\d{3}Z$/, 'Z');
// Phase 2: once the document is signed for Fatoora, its 9-field QR (or ZATCA's stamped one) replaces the phase-1 code
const zatcaQr = (doc, px) => { const c = S.company || {}; if (doc._zqr) return QR.svg(doc._zqr, Math.max(px, 150)); if (!c.vat_no) return ''; return QR.svg(QR.zatca({ seller: c.name, vat: c.vat_no, time: zatcaTime(doc.created_at || doc.date), total: doc.total, tax: doc.vat }), px); };
