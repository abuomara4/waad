'use strict';
/* QR reader written for Waad (no external library, nothing leaves the device): reads the QR code on a photographed invoice —
   straight, rotated or photographed at an angle — and the ZATCA TLV inside it (seller, VAT number, time, total, VAT).
   Steps: grey → local-threshold black/white → the three finder patterns (1:1:3:1:1) → orientation → version estimate →
   the bottom-right alignment pattern → perspective transform → sample the modules → format info (BCH) → unmask →
   de-interleave the blocks → Reed–Solomon correction → decode the segments. Pure functions: QRREAD.decode(ImageData-like). */
const QRREAD = (() => {
  // ---------- Galois field GF(256), primitive 0x11d (as QR) ----------
  const EXP = new Uint8Array(512), LOG = new Uint8Array(256);
  { let x = 1; for (let i = 0; i < 255; i++) { EXP[i] = x; LOG[x] = i; x <<= 1; if (x & 256) x ^= 0x11d; } for (let i = 255; i < 512; i++) EXP[i] = EXP[i - 255]; }
  const gmul = (a, b) => (a === 0 || b === 0 ? 0 : EXP[LOG[a] + LOG[b]]);
  const ginv = a => { if (!a) throw new Error('rs'); return EXP[255 - LOG[a]]; };
  // polynomials: arrays, highest degree first, no leading zeros (except the zero polynomial [0])
  const pnorm = c => { let i = 0; while (i < c.length - 1 && c[i] === 0) i++; return c.slice(i); };
  const pdeg = p => p.length - 1, pzero = p => p[0] === 0, pcoef = (p, d) => p[p.length - 1 - d];
  const padd = (a, b) => { if (pzero(a)) return b; if (pzero(b)) return a; let s = a, l = b; if (s.length > l.length) { s = b; l = a; } const r = l.slice(), d = l.length - s.length; for (let i = 0; i < s.length; i++) r[i + d] ^= s[i]; return pnorm(r); };
  const pmul = (a, b) => { if (pzero(a) || pzero(b)) return [0]; const r = new Array(a.length + b.length - 1).fill(0); for (let i = 0; i < a.length; i++) for (let j = 0; j < b.length; j++) r[i + j] ^= gmul(a[i], b[j]); return pnorm(r); };
  const pscale = (a, s) => (s === 0 ? [0] : pnorm(a.map(c => gmul(c, s))));
  const pmono = (deg, c) => { if (c === 0) return [0]; const r = new Array(deg + 1).fill(0); r[0] = c; return r; };
  const pmulmono = (a, deg, c) => { if (c === 0 || pzero(a)) return [0]; return pnorm(a.map(x => gmul(x, c)).concat(new Array(deg).fill(0))); };
  const peval = (p, a) => { if (a === 0) return pcoef(p, 0); let r = 0; for (const c of p) r = gmul(r, a) ^ c; return r; };

  // Reed–Solomon (generator roots α^0 … α^(n−1)): corrects the block in place, throws when it cannot
  function rsCorrect(cw, nEc) {
    const poly = pnorm(Array.from(cw)), syn = new Array(nEc).fill(0); let bad = false;
    for (let i = 0; i < nEc; i++) { const v = peval(poly, EXP[i]); syn[nEc - 1 - i] = v; if (v) bad = true; }
    if (!bad) return 0;
    // Euclid
    let rLast = pmono(nEc, 1), r = pnorm(syn), tLast = [0], t = [1];
    if (pdeg(rLast) < pdeg(r)) [rLast, r] = [r, rLast];
    while (2 * pdeg(r) >= nEc) {
      const rLL = rLast, tLL = tLast; rLast = r; tLast = t;
      if (pzero(rLast)) throw new Error('rs');
      r = rLL; let q = [0]; const dlt = ginv(pcoef(rLast, pdeg(rLast)));
      while (pdeg(r) >= pdeg(rLast) && !pzero(r)) { const dd = pdeg(r) - pdeg(rLast), sc = gmul(pcoef(r, pdeg(r)), dlt); q = padd(q, pmono(dd, sc)); r = padd(r, pmulmono(rLast, dd, sc)); }
      t = padd(pmul(q, tLast), tLL);
      if (pdeg(r) >= pdeg(rLast)) throw new Error('rs');
    }
    const s0 = pcoef(t, 0); if (!s0) throw new Error('rs');
    const inv = ginv(s0), sigma = pscale(t, inv), omega = pscale(r, inv);
    const ne = pdeg(sigma), locs = [];
    if (ne === 1) locs.push(pcoef(sigma, 1)); else for (let i = 1; i < 256 && locs.length < ne; i++) if (peval(sigma, i) === 0) locs.push(ginv(i));
    if (locs.length !== ne) throw new Error('rs');
    for (let i = 0; i < locs.length; i++) {
      const xi = ginv(locs[i]); let den = 1;
      for (let j = 0; j < locs.length; j++) if (i !== j) { const term = gmul(locs[j], xi); den = gmul(den, (term & 1) === 0 ? term | 1 : term & ~1); }
      const mag = gmul(peval(omega, xi), ginv(den)), pos = cw.length - 1 - LOG[locs[i]];
      if (pos < 0) throw new Error('rs');
      cw[pos] ^= mag;
    }
    return locs.length;
  }

  // ---------- the QR structure ----------
  const ECC = { L: [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    M: [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
    Q: [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    H: [-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30] };
  const BLK = { L: [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
    M: [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
    Q: [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
    H: [-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81] };
  const rawMods = v => { let r = (16 * v + 128) * v + 64; if (v >= 2) { const n = Math.floor(v / 7) + 2; r -= (25 * n - 10) * n - 55; if (v >= 7) r -= 36; } return r; };
  const alignPos = v => { if (v === 1) return []; const n = Math.floor(v / 7) + 2, size = v * 4 + 17, step = v === 32 ? 26 : Math.ceil((v * 4 + 4) / (n * 2 - 2)) * 2, r = [6]; for (let p = size - 7; r.length < n; p -= step) r.splice(1, 0, p); return r; };
  const LEVELS = ['M', 'L', 'H', 'Q'];   // format bits 00, 01, 10, 11
  const FORMATS = []; for (let e = 0; e < 4; e++) for (let k = 0; k < 8; k++) { const d = (e << 3) | k; let r = d; for (let i = 0; i < 10; i++) r = (r << 1) ^ ((r >>> 9) * 0x537); FORMATS.push([((d << 10) | r) ^ 0x5412, LEVELS[e], k]); }
  const VERSIONS = []; for (let v = 7; v <= 40; v++) { let r = v; for (let i = 0; i < 12; i++) r = (r << 1) ^ ((r >>> 11) * 0x1f25); VERSIONS.push([(v << 12) | r, v]); }
  const popc = x => { let c = 0; while (x) { c += x & 1; x >>>= 1; } return c; };
  const MASK = [(x, y) => (x + y) % 2 === 0, (x, y) => y % 2 === 0, x => x % 3 === 0, (x, y) => (x + y) % 3 === 0, (x, y) => (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0,
    (x, y) => (x * y) % 2 + (x * y) % 3 === 0, (x, y) => ((x * y) % 2 + (x * y) % 3) % 2 === 0, (x, y) => ((x + y) % 2 + (x * y) % 3) % 2 === 0];

  function funcMap(v) {
    const n = v * 4 + 17, f = []; for (let i = 0; i < n; i++) f.push(new Uint8Array(n));
    const box = (x0, y0, w, h) => { for (let y = y0; y < y0 + h; y++) for (let x = x0; x < x0 + w; x++) if (x >= 0 && y >= 0 && x < n && y < n) f[y][x] = 1; };
    box(0, 0, 9, 9); box(n - 8, 0, 8, 9); box(0, n - 8, 9, 8);   // finders, separators and format areas
    for (let i = 0; i < n; i++) { f[6][i] = 1; f[i][6] = 1; }
    const ap = alignPos(v); ap.forEach((a, i) => ap.forEach((b, j) => { if (!((i === 0 && j === 0) || (i === 0 && j === ap.length - 1) || (i === ap.length - 1 && j === 0))) box(a - 2, b - 2, 5, 5); }));
    if (v >= 7) { box(n - 11, 0, 3, 6); box(0, n - 11, 6, 3); }
    return f;
  }

  // the matrix (array of rows of 0/1, read as module[y][x]) → bytes of the message
  function readMatrix(m) {
    const n = m.length, v = (n - 17) / 4; if (v !== Math.floor(v) || v < 1 || v > 40) throw new Error('size');
    const bit = (x, y) => m[y][x];
    let f1 = 0; for (let i = 0; i <= 5; i++) f1 |= bit(8, i) << i; f1 |= bit(8, 7) << 6; f1 |= bit(8, 8) << 7; f1 |= bit(7, 8) << 8; for (let i = 9; i < 15; i++) f1 |= bit(14 - i, 8) << i;
    let f2 = 0; for (let i = 0; i < 8; i++) f2 |= bit(n - 1 - i, 8) << i; for (let i = 8; i < 15; i++) f2 |= bit(8, n - 15 + i) << i;
    let best = null, bd = 99; for (const [code, lv, mk] of FORMATS) for (const f of [f1, f2]) { const d = popc(code ^ f); if (d < bd) { bd = d; best = [lv, mk]; } }
    if (bd > 3) throw new Error('format');
    if (v >= 7) {   // the version blocks must agree with the size (when readable)
      let a = 0, b = 0; for (let i = 0; i < 18; i++) { a |= bit(n - 11 + i % 3, Math.floor(i / 3)) << i; b |= bit(Math.floor(i / 3), n - 11 + i % 3) << i; }
      let bv = 0, bvd = 99; for (const [code, vv] of VERSIONS) for (const x of [a, b]) { const d = popc(code ^ x); if (d < bvd) { bvd = d; bv = vv; } }
      if (bvd <= 3 && bv !== v) throw new Error('version');
    }
    const [lv, mk] = best, fn = funcMap(v), raw = Math.floor(rawMods(v) / 8), bits = [];
    for (let right = n - 1; right >= 1; right -= 2) { if (right === 6) right = 5; for (let vert = 0; vert < n; vert++) for (let j = 0; j < 2; j++) {
      const x = right - j, up = ((right + 1) & 2) === 0, y = up ? n - 1 - vert : vert;
      if (!fn[y][x] && bits.length < raw * 8) bits.push(bit(x, y) ^ (MASK[mk](x, y) ? 1 : 0)); } }
    const cw = []; for (let i = 0; i < raw * 8; i += 8) { let b = 0; for (let k = 0; k < 8; k++) b = (b << 1) | bits[i + k]; cw.push(b); }
    // de-interleave, correct, keep the data parts
    const nb = BLK[lv][v], ec = ECC[lv][v], nShort = nb - raw % nb, shortLen = Math.floor(raw / nb), blocks = [];
    for (let i = 0; i < nb; i++) blocks.push(new Array(shortLen + 1).fill(0));
    let k = 0; for (let i = 0; i <= shortLen; i++) for (let j = 0; j < nb; j++) if (i !== shortLen - ec || j >= nShort) blocks[j][i] = cw[k++];
    const data = [];
    blocks.forEach((b, j) => { const blk = j < nShort ? b.slice(0, shortLen - ec).concat(b.slice(shortLen - ec + 1)) : b; rsCorrect(blk, ec); for (let i = 0; i < blk.length - ec; i++) data.push(blk[i]); });
    return segments(data, v);
  }

  // the message segments: numeric, alphanumeric, byte (with ECI), kanji is not used on invoices
  function segments(data, v) {
    let p = 0; const rd = n => { let r = 0; for (let i = 0; i < n; i++) { const by = data[p >> 3]; r = (r << 1) | (by === undefined ? 0 : (by >> (7 - (p & 7))) & 1); p++; } return r; };
    const left = () => data.length * 8 - p, out = [], AN = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:';
    const cb = (a, b, c) => (v < 10 ? a : v < 27 ? b : c);
    while (left() >= 4) {
      const mode = rd(4); if (mode === 0) break;
      if (mode === 7) { const b = rd(8); if ((b & 0x80) === 0) {} else if ((b & 0xc0) === 0x80) rd(8); else rd(16); continue; }
      if (mode === 3) { rd(16); continue; } if (mode === 5) continue; if (mode === 9) { rd(8); continue; }
      if (mode === 1) { let c = rd(cb(10, 12, 14)); while (c >= 3) { const x = rd(10); String(x).padStart(3, '0').split('').forEach(ch => out.push(ch.charCodeAt(0))); c -= 3; }
        if (c === 2) String(rd(7)).padStart(2, '0').split('').forEach(ch => out.push(ch.charCodeAt(0))); else if (c === 1) out.push(48 + rd(4)); continue; }
      if (mode === 2) { let c = rd(cb(9, 11, 13)); while (c >= 2) { const x = rd(11); out.push(AN.charCodeAt(Math.floor(x / 45)), AN.charCodeAt(x % 45)); c -= 2; } if (c === 1) out.push(AN.charCodeAt(rd(6))); continue; }
      if (mode === 4) { const c = rd(cb(8, 16, 16)); for (let i = 0; i < c; i++) out.push(rd(8)); continue; }
      throw new Error('mode');
    }
    return Uint8Array.from(out);
  }

  // ---------- from the photo to the matrix ----------
  const toGrey = img => { const { data, width: w, height: h } = img, g = new Uint8Array(w * h); for (let i = 0, j = 0; i < g.length; i++, j += 4) g[i] = (data[j] * 77 + data[j + 1] * 150 + data[j + 2] * 29) >> 8; return { g, w, h }; };
  // local threshold over 8×8 blocks, averaged with the blocks around (uneven light, shadows on paper)
  function binarize({ g, w, h }, bias = 0) {
    const B = 8, bw = Math.ceil(w / B), bh = Math.ceil(h / B), avg = new Float32Array(bw * bh), bin = new Uint8Array(w * h);
    for (let by = 0; by < bh; by++) for (let bx = 0; bx < bw; bx++) {
      let s = 0, n = 0, mn = 255, mx = 0;
      for (let y = by * B; y < Math.min(h, by * B + B); y++) for (let x = bx * B; x < Math.min(w, bx * B + B); x++) { const v = g[y * w + x]; s += v; n++; if (v < mn) mn = v; if (v > mx) mx = v; }
      let a = s / n; if (mx - mn <= 24) { a = mn / 2; if (by > 0 && bx > 0) { const nb = (avg[(by - 1) * bw + bx] + 2 * avg[by * bw + bx - 1] + avg[(by - 1) * bw + bx - 1]) / 4; if (mn < nb) a = nb; } }
      avg[by * bw + bx] = a;
    }
    for (let by = 0; by < bh; by++) for (let bx = 0; bx < bw; bx++) {
      let s = 0, n = 0; for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) { const yy = by + dy, xx = bx + dx; if (yy >= 0 && xx >= 0 && yy < bh && xx < bw) { s += avg[yy * bw + xx]; n++; } }
      const t = s / n + bias;
      for (let y = by * B; y < Math.min(h, by * B + B); y++) for (let x = bx * B; x < Math.min(w, bx * B + B); x++) bin[y * w + x] = g[y * w + x] <= t ? 1 : 0;
    }
    return { b: bin, w, h };
  }

  // finder patterns: runs dark:light:dark:light:dark ≈ 1:1:3:1:1 across rows, checked down the column and diagonally
  const ratioOk = (s, tol = 0.5) => { const tot = s[0] + s[1] + s[2] + s[3] + s[4]; if (tot < 7 || s.some(x => x === 0)) return false; const m = tot / 7, v = m * tol;
    return Math.abs(m - s[0]) < v && Math.abs(m - s[1]) < v && Math.abs(3 * m - s[2]) < 3 * v && Math.abs(m - s[3]) < v && Math.abs(m - s[4]) < v; };
  // runs along one direction through (cx, cy); returns the offset of the dark centre's middle and the module size
  function crossCheck(img, cx, cy, dx, dy, maxCount) {
    const { b, w, h } = img, at = (x, y) => (x >= 0 && y >= 0 && x < w && y < h ? b[y * w + x] : -1), s = [0, 0, 0, 0, 0];
    if (at(cx, cy) !== 1) return null;
    let x = cx, y = cy, back = 0, fwd = 0;
    while (at(x, y) === 1) { back++; x -= dx; y -= dy; }
    while (at(x, y) === 0 && s[1] <= maxCount) { s[1]++; x -= dx; y -= dy; } if (at(x, y) !== 1 || s[1] > maxCount) return null;
    while (at(x, y) === 1 && s[0] <= maxCount) { s[0]++; x -= dx; y -= dy; } if (s[0] > maxCount) return null;
    x = cx + dx; y = cy + dy; while (at(x, y) === 1) { fwd++; x += dx; y += dy; }
    while (at(x, y) === 0 && s[3] <= maxCount) { s[3]++; x += dx; y += dy; } if (at(x, y) !== 1 || s[3] > maxCount) return null;
    while (at(x, y) === 1 && s[4] <= maxCount) { s[4]++; x += dx; y += dy; } if (s[4] > maxCount) return null;
    s[2] = back + fwd;
    if (!ratioOk(s, 0.7)) return null;
    return { off: (fwd - back + 1) / 2, size: (s[0] + s[1] + s[2] + s[3] + s[4]) / 7 };
  }
  function addCand(cands, img, s, x, y) {
    const tot = s[0] + s[1] + s[2] + s[3] + s[4], cx = Math.round(x - s[4] - s[3] - s[2] / 2);
    const vc = crossCheck(img, cx, y, 0, 1, s[2] * 2); if (!vc) return;
    const fy = y + vc.off, hc = crossCheck(img, cx, Math.round(fy), 1, 0, s[2] * 2); if (!hc) return;
    const fx = cx + hc.off, dg = crossCheck(img, Math.round(fx), Math.round(fy), 1, 1, s[2] * 3);
    const size = (tot / 7 + vc.size + hc.size) / 3;
    const near = cands.find(c => Math.abs(c.x - fx) <= size * 2 && Math.abs(c.y - fy) <= size * 2 && Math.abs(c.size - size) <= Math.max(1, size * 0.5));
    if (near) { near.x = (near.x * near.n + fx) / (near.n + 1); near.y = (near.y * near.n + fy) / (near.n + 1); near.size = (near.size * near.n + size) / (near.n + 1); near.n++; if (dg) near.diag = true; }
    else cands.push({ x: fx, y: fy, size, n: 1, diag: !!dg });
  }
  function findFinders(img) {
    const { b, w, h } = img, cands = [], step = Math.max(1, Math.floor(h / 500));
    for (let y = 0; y < h; y += step) {
      const s = [0, 0, 0, 0, 0]; let st = 0;
      for (let x = 0; x <= w; x++) {
        const d = x < w ? b[y * w + x] : 0;
        if (d === 1) { if (st & 1) st++; s[st]++; continue; }
        if (st & 1) { s[st]++; continue; }
        if (st === 4) { if (ratioOk(s)) addCand(cands, img, s, x, y); s[0] = s[2]; s[1] = s[3]; s[2] = s[4]; s[3] = 1; s[4] = 0; st = 3; }
        else { st++; s[st]++; }
      }
    }
    return cands;
  }
  function core(img, p, size, lim) {
    const { b, w, h } = img, x0 = Math.round(p.x), y0 = Math.round(p.y); if (x0 < 0 || y0 < 0 || x0 >= w || y0 >= h || !b[y0 * w + x0]) return p;
    const seen = new Set([y0 * w + x0]), st = [[x0, y0]], r2 = (lim * size) ** 2; let sx = 0, sy = 0, n = 0;
    while (st.length) { const [x, y] = st.pop(); sx += x; sy += y; n++; if (n > 40000) return p;
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) { const xx = x + dx, yy = y + dy, k = yy * w + xx;
        if (xx < 0 || yy < 0 || xx >= w || yy >= h || seen.has(k) || !b[k]) continue; if ((xx - p.x) ** 2 + (yy - p.y) ** 2 > r2) return p; seen.add(k); st.push([xx, yy]); } }
    return n >= 3 ? Object.assign({}, p, { x: sx / n, y: sy / n }) : p;
  }
  // the best three: similar size, two equal sides at a right angle
  function pickThree(cands, img) {
    const c = cands.filter(x => x.n >= 2 || cands.length <= 6).sort((a, b) => b.n - a.n).slice(0, 12), out = [];
    const d2 = (p, q) => (p.x - q.x) ** 2 + (p.y - q.y) ** 2;
    for (let i = 0; i < c.length; i++) for (let j = i + 1; j < c.length; j++) for (let k = j + 1; k < c.length; k++) {
      const t = [c[i], c[j], c[k]], sz = t.map(x => x.size), mn = Math.min(...sz), mx = Math.max(...sz); if (mx > mn * 1.6) continue;
      const ds = [[d2(t[1], t[2]), 0], [d2(t[0], t[2]), 1], [d2(t[0], t[1]), 2]].sort((a, b) => b[0] - a[0]);
      const tl = t[ds[0][1]], others = t.filter((_, q) => q !== ds[0][1]), a = Math.sqrt(ds[1][0]), bb = Math.sqrt(ds[2][0]), hyp = Math.sqrt(ds[0][0]);
      const mod = (mn + mx) / 2, side = (a + bb) / 2; if (side < mod * 10) continue;
      const err = Math.abs(a - bb) / side + Math.abs(hyp - side * Math.SQRT2) / (side * Math.SQRT2);
      if (err > 0.5) continue;
      let [p, q] = others.map(o => core(img, o, o.size, 2.6)); const cr = (p.x - tl.x) * (q.y - tl.y) - (p.y - tl.y) * (q.x - tl.x); if (cr < 0) [p, q] = [q, p];
      out.push({ err: err - (t.reduce((s, x) => s + Math.min(x.n, 8), 0) / 100), tl: core(img, tl, tl.size, 2.6), tr: p, bl: q, mod });
    }
    return out.sort((a, b) => a.err - b.err).slice(0, 4);
  }

  // perspective (as in the usual QR readers): unit square ↔ quadrilateral
  function sq2q(x0, y0, x1, y1, x2, y2, x3, y3) {
    const dx3 = x0 - x1 + x2 - x3, dy3 = y0 - y1 + y2 - y3;
    if (Math.abs(dx3) < 1e-9 && Math.abs(dy3) < 1e-9) return [x1 - x0, x2 - x1, x0, y1 - y0, y2 - y1, y0, 0, 0, 1];
    const dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2, den = dx1 * dy2 - dx2 * dy1, a13 = (dx3 * dy2 - dx2 * dy3) / den, a23 = (dx1 * dy3 - dx3 * dy1) / den;
    return [x1 - x0 + a13 * x1, x3 - x0 + a23 * x3, x0, y1 - y0 + a13 * y1, y3 - y0 + a23 * y3, y0, a13, a23, 1];
  }
  const adj = ([a11, a21, a31, a12, a22, a32, a13, a23, a33]) => [a22 * a33 - a23 * a32, a23 * a31 - a21 * a33, a21 * a32 - a22 * a31, a13 * a32 - a12 * a33, a11 * a33 - a13 * a31, a12 * a31 - a11 * a32, a12 * a23 - a13 * a22, a13 * a21 - a11 * a23, a11 * a22 - a12 * a21];
  const times = (t, o) => [t[0] * o[0] + t[1] * o[3] + t[2] * o[6], t[0] * o[1] + t[1] * o[4] + t[2] * o[7], t[0] * o[2] + t[1] * o[5] + t[2] * o[8],
    t[3] * o[0] + t[4] * o[3] + t[5] * o[6], t[3] * o[1] + t[4] * o[4] + t[5] * o[7], t[3] * o[2] + t[4] * o[5] + t[5] * o[8],
    t[6] * o[0] + t[7] * o[3] + t[8] * o[6], t[6] * o[1] + t[7] * o[4] + t[8] * o[7], t[6] * o[2] + t[7] * o[5] + t[8] * o[8]];
  const q2q = (src, dst) => times(sq2q(...dst), adj(sq2q(...src)));
  const tf = (m, x, y) => { const d = m[6] * x + m[7] * y + m[8]; return [(m[0] * x + m[1] * y + m[2]) / d, (m[3] * x + m[4] * y + m[5]) / d]; };

  // alignment patterns near where one should be (dark centre, light ring, dark ring): the nearest few, each one blob
  function findAligns(img, ex, ey, mod, rad = 12) {
    const { b, w, h } = img, at = (x, y) => { x = Math.round(x); y = Math.round(y); return x >= 0 && y >= 0 && x < w && y < h ? b[y * w + x] : 0; };
    const r = Math.ceil(rad * mod), hits = [];
    for (let y = Math.max(0, Math.round(ey - r)); y <= Math.min(h - 1, Math.round(ey + r)); y++) for (let x = Math.max(0, Math.round(ex - r)); x <= Math.min(w - 1, Math.round(ex + r)); x++) {
      if (!at(x, y)) continue;
      let sc = 0; for (let a = 0; a < 16; a++) { const ca = Math.cos(a * Math.PI / 8), sa = Math.sin(a * Math.PI / 8), k = 1 / Math.max(Math.abs(ca), Math.abs(sa));
        if (!at(x + ca * mod * k, y + sa * mod * k)) sc++; if (at(x + ca * 2 * mod * k, y + sa * 2 * mod * k)) sc++; }
      if (sc >= 29) hits.push({ x, y, sc, d: (x - ex) ** 2 + (y - ey) ** 2 });
    }
    hits.sort((p, q) => p.d - q.d); const out = [];
    for (const p of hits) { const c = out.find(o => Math.hypot(o.x - p.x, o.y - p.y) < mod * 2); if (c) { c.sx += p.x; c.sy += p.y; c.n++; } else if (out.length < 3) out.push({ x: p.x, y: p.y, sx: p.x, sy: p.y, n: 1 }); }
    return out.map(o => core(img, { x: o.sx / o.n, y: o.sy / o.n }, mod, 1.6));
  }

  // least squares: grid points → image points (8 unknowns, normal equations)
  function fitH(pts) {
    const A = Array.from({ length: 8 }, () => new Float64Array(9));
    for (const [gx, gy, x, y] of pts) for (const [row, rhs] of [[[gx, gy, 1, 0, 0, 0, -gx * x, -gy * x], x], [[0, 0, 0, gx, gy, 1, -gx * y, -gy * y], y]])
      for (let i = 0; i < 8; i++) { for (let j = 0; j < 8; j++) A[i][j] += row[i] * row[j]; A[i][8] += row[i] * rhs; }
    for (let c = 0; c < 8; c++) { let pv = c; for (let r = c + 1; r < 8; r++) if (Math.abs(A[r][c]) > Math.abs(A[pv][c])) pv = r; [A[c], A[pv]] = [A[pv], A[c]]; if (Math.abs(A[c][c]) < 1e-12) return null;
      for (let r = 0; r < 8; r++) if (r !== c) { const f = A[r][c] / A[c][c]; for (let k = c; k < 9; k++) A[r][k] -= f * A[c][k]; } }
    const x = A.map((r, i) => r[8] / r[i]); return [x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7], 1];
  }
  // a second pass: every alignment pattern where the first mapping puts it, found nearby, then one mapping fitted to all of them
  function refine(img, m, n, tri, mod) {
    const v = (n - 17) / 4, ap = alignPos(v), pts = [[3.5, 3.5, tri.tl.x, tri.tl.y], [n - 3.5, 3.5, tri.tr.x, tri.tr.y], [3.5, n - 3.5, tri.bl.x, tri.bl.y]];
    ap.forEach((a, i) => ap.forEach((b, j) => { if ((i === 0 && j === 0) || (i === 0 && j === ap.length - 1) || (i === ap.length - 1 && j === 0)) return;
      const [ex, ey] = tf(m, a + 0.5, b + 0.5), f = findAligns(img, ex, ey, mod, 3.5)[0]; if (f) pts.push([a + 0.5, b + 0.5, f.x, f.y]); }));
    return pts.length >= 5 ? fitH(pts) : null;
  }

  function sample(img, m, n) {
    const { b, w, h } = img, out = [];
    for (let y = 0; y < n; y++) { const row = new Uint8Array(n); for (let x = 0; x < n; x++) { const [px, py] = tf(m, x + 0.5, y + 0.5);
      if (!(px > -2 && py > -2 && px < w + 1 && py < h + 1)) throw new Error('out'); const ix = Math.min(w - 1, Math.max(0, Math.round(px))), iy = Math.min(h - 1, Math.max(0, Math.round(py))); row[x] = b[iy * w + ix]; } out.push(row); }
    return out;
  }

  // the finder's width along a direction (7 modules): from its centre out through dark, light, dark, to the light outside
  function widthAlong(img, p, ux, uy) {
    const { b, w, h } = img, at = (x, y) => { x = Math.round(x); y = Math.round(y); return x >= 0 && y >= 0 && x < w && y < h ? b[y * w + x] : -1; };
    const run = sg => { let t = 0, cur = 1, flips = 0; for (let k = 0; k < 400; k++) { const v = at(p.x + sg * ux * t, p.y + sg * uy * t); if (v === -1) return null; if (v !== cur) { flips++; cur = v; if (flips === 3) return t; } t += 0.5; } return null; };
    const a = run(1), c = run(-1); return a && c ? (a + c) / 7 : null;
  }
  function tryPatterns(img, tri) {
    const { tl, tr, bl } = tri, dist = (p, q) => Math.hypot(p.x - q.x, p.y - q.y);
    const mod = (tl.size + tr.size + bl.size) / 3;
    // module size measured along the code's own axes (a rotated code looks wider across rows)
    const dTR = dist(tl, tr), dBL = dist(tl, bl), ax = [(tr.x - tl.x) / dTR, (tr.y - tl.y) / dTR], ay = [(bl.x - tl.x) / dBL, (bl.y - tl.y) / dBL];
    const mx = [widthAlong(img, tl, ...ax), widthAlong(img, tr, ...ax)].filter(Boolean), my = [widthAlong(img, tl, ...ay), widthAlong(img, bl, ...ay)].filter(Boolean);
    const mX = mx.length ? mx.reduce((a, c) => a + c, 0) / mx.length : mod, mY = my.length ? my.reduce((a, c) => a + c, 0) / my.length : mod;
    let dim = Math.round((dTR / mX + dBL / mY) / 2) + 7; const am = (mX + mY) / 2;   // the true module size (rows across a turned code overstate it)
    switch (dim & 3) { case 0: dim += 1; break; case 2: dim -= 1; break; case 3: dim -= 2; break; }
    const dims = [dim, dim + 4, dim - 4, dim + 8, dim - 8, dim + 12].filter(d => d >= 21 && d <= 177);
    for (const n of dims) {
      const v = (n - 17) / 4, brx = tr.x - tl.x + bl.x, bry = tr.y - tl.y + bl.y, quads = [];
      // under perspective the far corner is not the parallelogram's: scale each side by how the finders' sizes change
      const kr = tr.size / tl.size, kb = bl.size / tl.size, px = ((tr.x + (bl.x - tl.x) * kr) + (bl.x + (tr.x - tl.x) * kb)) / 2, py = ((tr.y + (bl.y - tl.y) * kr) + (bl.y + (tr.y - tl.y) * kb)) / 2;
      if (v >= 2) { const c = 1 - 3 / (n - 7);
        for (const [cx, cy] of [[px, py], [brx, bry]]) { const ex = tl.x + c * (cx - tl.x), ey = tl.y + c * (cy - tl.y);
          for (const ap of findAligns(img, ex, ey, am)) quads.push([[3.5, 3.5, n - 3.5, 3.5, n - 6.5, n - 6.5, 3.5, n - 3.5], [tl.x, tl.y, tr.x, tr.y, ap.x, ap.y, bl.x, bl.y]]); } }
      quads.push([[3.5, 3.5, n - 3.5, 3.5, n - 3.5, n - 3.5, 3.5, n - 3.5], [tl.x, tl.y, tr.x, tr.y, px, py, bl.x, bl.y]]);
      quads.push([[3.5, 3.5, n - 3.5, 3.5, n - 3.5, n - 3.5, 3.5, n - 3.5], [tl.x, tl.y, tr.x, tr.y, brx, bry, bl.x, bl.y]]);
      const read = mt => { const mtx = sample(img, mt, n); try { return readMatrix(mtx); } catch (e) { return readMatrix(mtx[0].map((_, i) => mtx.map(r => r[i]))); } };
      for (const [src, dst] of quads) {
        const mt = q2q(src, dst);
        try { return read(mt); } catch (e) { /* refine below */ }
        // refine again from each better mapping: far patterns come into reach as the near ones fix the perspective
        let cur = mt; for (let it = 0; it < 3 && v >= 2; it++) { const r2 = refine(img, cur, n, tri, am); if (!r2) break; cur = r2; try { return read(cur); } catch (e) { /* again */ } }
      }
    }
    return null;
  }

  // a canvas-sized image: try the full size, then smaller (blur from the camera), and two thresholds
  function scale(img, f) {
    if (f === 1) return img; const w = Math.max(1, Math.round(img.width * f)), h = Math.max(1, Math.round(img.height * f)), d = new Uint8ClampedArray(w * h * 4), s = img.data;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const sx = Math.min(img.width - 1, Math.floor(x / f)), sy = Math.min(img.height - 1, Math.floor(y / f)), i = (y * w + x) * 4, j = (sy * img.width + sx) * 4;
      d[i] = s[j]; d[i + 1] = s[j + 1]; d[i + 2] = s[j + 2]; d[i + 3] = 255; }
    return { data: d, width: w, height: h };
  }
  function decode(img, budgetMs = 7000) {
    const big = Math.max(img.width, img.height), fs = [], until = Date.now() + budgetMs;
    for (const target of [1600, 1000, 2400, 700]) { const f = Math.min(1, target / big); if (!fs.some(x => Math.abs(x - f) < 0.05)) fs.push(f); }
    for (const f of fs) {
      const grey = toGrey(scale(img, f));
      for (const bias of [0, -12, 12]) {
        const bin = binarize(grey, bias), tris = pickThree(findFinders(bin), bin);
        for (const t of tris) { const r = tryPatterns(bin, t); if (r) return r; if (Date.now() > until) return null; }
      }
    }
    return null;
  }

  // ---------- ZATCA: base64 of TLV (1 seller, 2 VAT number, 3 time, 4 total with VAT, 5 VAT) ----------
  const utf8 = b => new TextDecoder().decode(b);
  function zatca(bytes) {
    const text = utf8(bytes).trim(), out = { raw: text };
    try {
      const bin = atob(text.replace(/\s+/g, '')), u = Uint8Array.from(bin, ch => ch.charCodeAt(0)); let i = 0; const f = {};
      while (i + 2 <= u.length) { const tag = u[i], len = u[i + 1]; if (i + 2 + len > u.length) break; if (tag >= 1 && tag <= 5) f[tag] = utf8(u.slice(i + 2, i + 2 + len)); i += 2 + len; }
      // digits in any script (Arabic-Indic ٠١٢, Persian ۰۱۲, …) and an Arabic decimal comma are read as ordinary numbers
      const num = t => { if (t === undefined) return null; const v = +String(t).replace(/[\u0660-\u0669]/g, d => d.charCodeAt(0) - 0x660).replace(/[\u06F0-\u06F9]/g, d => d.charCodeAt(0) - 0x6F0).replace(/[\u066B,]/g, '.').replace(/[^\d.\-]/g, ''); return isFinite(v) ? v : null; };
      const digits = t => String(t || '').replace(/[\u0660-\u0669]/g, d => d.charCodeAt(0) - 0x660).replace(/[\u06F0-\u06F9]/g, d => d.charCodeAt(0) - 0x6F0).replace(/\s/g, '');
      if (f[1] && f[2]) { const vat = digits(f[2]); Object.assign(out, { seller: f[1].trim(), vat, time: digits(f[3]), total: num(f[4]), tax: num(f[5]), zatca: /^3\d{13}3$/.test(vat) }); }
    } catch (e) { /* not base64 */ }
    if (!out.seller) { const m = text.match(/\b3\d{13}3\b/); if (m) out.vat = m[0]; }
    return out;
  }
  const date = t => { const d = new Date(t); if (isNaN(d)) { const m = String(t || '').match(/(\d{4})-(\d{2})-(\d{2})/); return m ? m[0] : ''; } return new Date(d.getTime() + 3 * 3600e3).toISOString().slice(0, 10); };

  // a photo file → { seller, vat, time, date, total, tax, raw } (or null when there is no readable code)
  async function fromFile(file) {
    const url = URL.createObjectURL(file);
    try {
      const im = new Image(); await new Promise((ok, no) => { im.onload = ok; im.onerror = () => no(new Error('img')); im.src = url; });
      const k = Math.min(1, 2400 / Math.max(im.naturalWidth, im.naturalHeight)), w = Math.round(im.naturalWidth * k), h = Math.round(im.naturalHeight * k);
      const cv = document.createElement('canvas'); cv.width = w; cv.height = h; const g = cv.getContext('2d', { willReadFrequently: true }); g.drawImage(im, 0, 0, w, h);
      let bytes = null;
      if ('BarcodeDetector' in window) { try { const r = await new BarcodeDetector({ formats: ['qr_code'] }).detect(cv); if (r[0] && r[0].rawValue) bytes = new TextEncoder().encode(r[0].rawValue); } catch (e) { /* use ours */ } }
      if (!bytes) bytes = decode(g.getImageData(0, 0, w, h));
      if (!bytes) return null;
      const z = zatca(bytes); z.date = z.time ? date(z.time) : ''; return z;
    } finally { URL.revokeObjectURL(url); }
  }
  return { decode, zatca, fromFile, readMatrix, rsCorrect };
})();
