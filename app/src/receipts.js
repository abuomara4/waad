'use strict';
/* «قراءة الفاتورة» (0160): photograph an invoice in Waad and the form fills itself — the ZATCA QR on every Saudi tax invoice is read
   on the device by qrread.js (no outside service, the photo never leaves the company's records), and the invoice's key warns when
   the same invoice was already claimed in this company. Used in: expense / trip / purchase requests, petty cash claims, supplier inbox. */
const receiptKey = z => [z.vat || '', z.time || z.date || '', z.total == null ? '' : (+z.total).toFixed(2), z.vat ? '' : (z.ref || z.seller || '')].join('|');
const receiptRow = z => ({ seller: z.seller || '', vat_no: z.vat || '', time: z.time || '', date: z.date || '', total: z.total, tax: z.tax, ref: z.ref || '', src: z.src || 'qr', key: receiptKey(z) });

/* reading the printed text on the device: Tesseract (site/app/ocr, Apache-2.0) is loaded the first time it is needed */
let ocrP = null, ocrTick = null;
function ocrWorker() {
  if (ocrP) return ocrP;
  const base = new URL('ocr/', location.href).href;
  ocrP = new Promise((ok, no) => { if (window.Tesseract) return ok(); const sc = document.createElement('script'); sc.src = base + 'tesseract.min.js'; sc.onload = ok; sc.onerror = () => no(new Error('ocr')); document.head.appendChild(sc); })
    .then(() => Tesseract.createWorker(['ara', 'eng'], 1, { workerPath: base + 'worker.min.js', corePath: base.replace(/\/$/, ''), langPath: base.replace(/\/$/, ''), workerBlobURL: false, gzip: true,
      logger: m => { if (ocrTick && m && typeof m.progress === 'number') ocrTick(m); } }))
    .then(async w => { await w.setParameters({ preserve_interword_spaces: '1' }); return w; })
    .catch(e => { ocrP = null; throw e; });
  return ocrP;
}
async function ocrRead(file, tick) {
  const url = URL.createObjectURL(file);
  try {
    const im = new Image(); await new Promise((ok, no) => { im.onload = ok; im.onerror = () => no(new Error('img')); im.src = url; });
    const big = Math.max(im.naturalWidth, im.naturalHeight), k = big < 1200 ? 2 : Math.min(1, 2200 / big), cv = document.createElement('canvas');
    cv.width = Math.round(im.naturalWidth * k); cv.height = Math.round(im.naturalHeight * k);
    const g = cv.getContext('2d'); g.fillStyle = '#fff'; g.fillRect(0, 0, cv.width, cv.height); g.drawImage(im, 0, 0, cv.width, cv.height);
    ocrTick = tick; const w = await ocrWorker(), r = await w.recognize(cv); ocrTick = null;
    return receiptFromText(r.data.text || '');
  } finally { URL.revokeObjectURL(url); ocrTick = null; }
}

function receiptSummary(z, dup) {
  return `<div class="card rcpt" style="margin:8px 0;padding:10px 12px"><b>✓ ${esc(tr(z.src === 'text' ? 'قُرئ نص الفاتورة' : 'قُرئت الفاتورة'))}</b>${z.src === 'text' ? `<div class="small muted">${esc(tr('قراءة النص تقريبية: راجع الأرقام وعدّلها في النموذج قبل الإرسال.'))}</div>` : ''}
    <div class="small" style="display:grid;grid-template-columns:auto 1fr;gap:2px 10px;margin-top:6px">
      <span class="muted">${esc(tr('المورد'))}</span><span>${esc(z.seller || '—')}</span>
      <span class="muted">${esc(tr('الرقم الضريبي'))}</span><span class="num" dir="ltr">${esc(z.vat_no || z.vat || '—')}</span>
      <span class="muted">${esc(tr('التاريخ'))}</span><span class="num">${esc(z.date ? fdate(z.date) : '—')}</span>
      <span class="muted">${esc(tr('الإجمالي شامل الضريبة'))}</span><span>${z.total == null ? '—' : money(z.total)}</span>
      <span class="muted">${esc(tr('الضريبة'))}</span><span>${z.tax == null ? '—' : money(z.tax)}</span>${z.ref ? `<span class="muted">${esc(tr('رقم الفاتورة'))}</span><span class="num" dir="ltr">${esc(z.ref)}</span>` : ''}</div>
    ${dup ? `<div class="note" style="margin-top:8px">⚠️ ${esc(tr('هذه الفاتورة مقدّمة من قبل في المنشأة. تأكد أنها ليست مكررة.'))}</div>` : ''}</div>`;
}

/* adds «📷 تصوير الفاتورة» next to a file input; a photo taken or chosen is read and handed to onRead(receipt, dupCount) */
function receiptReader(fileInput, onRead) {
  if (!fileInput || fileInput.dataset.rcpt) return; fileInput.dataset.rcpt = 1; fileInput.dataset.cam = 1;
  const box = document.createElement('div'); box.className = 'rcptbox';
  box.innerHTML = `<label class="btn sm pri" style="margin-top:6px">📷 ${esc(tr('تصوير الفاتورة وقراءتها'))}<input type="file" accept="image/*" capture="environment" hidden></label>
    <span class="small muted" role="status" style="margin-inline-start:8px"></span><div class="rcptout"></div>`;
  (fileInput.closest('label') || fileInput).insertAdjacentElement('afterend', box);
  const msg = $('[role=status]', box), out = $('.rcptout', box);
  const read = async file => {
    if (!file || !/^image\//.test(file.type)) return;
    msg.textContent = tr('جارٍ قراءة الفاتورة…'); out.innerHTML = '';
    let z = null; try { z = await QRREAD.fromFile(file); } catch (e) { z = null; }
    // no QR (or an empty one): read the printed text on the device
    if (!z || (!z.vat && z.total == null)) {
      msg.textContent = tr('لا يوجد رمز QR، جارٍ قراءة نص الفاتورة…');
      try { z = await ocrRead(file, m => { msg.textContent = (m.status === 'recognizing text' ? tr('جارٍ قراءة نص الفاتورة') : tr('جارٍ تجهيز القارئ أول مرة')) + ' ' + Math.round(m.progress * 100) + '%'; }); } catch (e) { z = null; }
    }
    if (!z || (!z.vat && z.total == null && !z.seller)) { msg.textContent = tr('تعذّرت قراءة الفاتورة. صوّرها مرة ثانية بإضاءة جيدة، أو اكتب البيانات بنفسك (الصورة مرفقة).'); return; }
    const r = receiptRow(z), dup = await db.rpc('receipt_seen', { p_company: S.cid, p_key: r.key }).catch(() => 0);
    msg.textContent = ''; out.innerHTML = receiptSummary(r, dup > 0); onRead(r, dup);
  };
  $('input', box).onchange = ev => { const f = ev.target.files[0]; if (!f) return;
    try { const dt = new DataTransfer(); [...(fileInput.files || [])].forEach(x => dt.items.add(x)); dt.items.add(f); fileInput.files = dt.files; } catch (e) { /* older browsers: the photo is still read */ }
    read(f); };
  fileInput.addEventListener('change', () => { const f = [...(fileInput.files || [])].reverse().find(x => /^image\//.test(x.type)); if (f) read(f); });
}

// for approvers: what the photographed invoice said, and whether it was claimed elsewhere in the company too
async function receiptInfo(r) {
  const z = r.payload && r.payload.receipt; if (!z || !z.key) return '';
  const n = await db.rpc('receipt_seen', { p_company: S.cid, p_key: z.key }).catch(() => 0);
  return receiptSummary(z, n > 1);
}
