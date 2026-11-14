'use strict';
/* «نقطة البيع» (#/pos): a till for shops on any tablet or phone browser. Pick items by tapping, typing or scanning the barcode
   (camera too), take cash or card, and it posts a simplified sales invoice to a walk-in customer (or a chosen one), records
   the receipt, takes the stock out, sends it to ZATCA when the company is linked, and prints a small receipt with the QR. */
const POS_CASH = 'عميل نقدي';
VIEWS['#/pos'] = async page => {
  if (!can('sales')) { page.innerHTML = `<div class="note">${esc(tr('نقطة البيع لمن لديه صلاحية المبيعات.'))}</div>`; return; }
  const [items, units, custs] = await Promise.all([db.get('items', { company_id: 'eq.' + S.cid, active: 'eq.true', order: 'name', select: 'id,code,name,name_en,barcode,sale_price,vat_rate,type,track_serial,unit' }),
    db.get('item_units', { company_id: 'eq.' + S.cid, select: 'item_id,name,factor,barcode' }).catch(() => []),
    db.get('parties', { company_id: 'eq.' + S.cid, kind: 'eq.customer', order: 'name', select: 'id,name,vat_no' })]);
  const sellable = items.filter(i => !i.track_serial);
  const cart = [];   // { it, qty, price }
  const find = v => { v = String(v || '').trim(); if (!v) return null;
    const it = sellable.find(i => i.barcode === v || i.code === v); if (it) return { it, f: 1 };
    const u = units.find(x => x.barcode === v); if (u) { const i2 = sellable.find(i => i.id === u.item_id); if (i2) return { it: i2, f: +u.factor }; }
    const byName = sellable.filter(i => i.name.includes(v) || (i.name_en || '').toLowerCase().includes(v.toLowerCase()));
    return byName.length === 1 ? { it: byName[0], f: 1 } : null; };
  const add = (it, q = 1) => { const l = cart.find(x => x.it.id === it.id); if (l) l.qty = r2(l.qty + q); else cart.push({ it, qty: q, price: n0(it.sale_price) }); draw(); };
  const tot = () => { let net = 0, vat = 0; cart.forEach(l => { const a = r2(l.qty * l.price); net += a; vat += r2(a * n0(l.it.vat_rate == null ? 15 : l.it.vat_rate) / 100); }); return { net: r2(net), vat: r2(vat), total: r2(net + vat) }; };
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('نقطة البيع'))}</h1><div class="muted">${esc(tr('فاتورة مبسطة سريعة: اختر الأصناف، استلم المبلغ، واطبع الإيصال.'))}</div></div></div>
    <div class="pos" style="display:grid;grid-template-columns:minmax(0,3fr) minmax(280px,2fr);gap:14px">
      <div><div class="row" style="gap:8px;margin-bottom:10px"><input id="psc" aria-label="${esc(tr('بحث عن صنف'))}" placeholder="${esc(tr('امسح الباركود أو اكتب اسم الصنف أو رمزه'))}" autocomplete="off" style="flex:1">
        ${'BarcodeDetector' in window ? `<button type="button" class="btn" id="pcam">${esc(tr('الكاميرا'))}</button>` : ''}</div><div class="small" id="pmsg" role="status"></div>
        <div id="pgrid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(130px,1fr));gap:8px;margin-top:8px"></div></div>
      <div class="card" style="align-self:start"><div id="pcart"></div>
        <div class="fg" style="margin-top:10px">${field('العميل', `<select id="pcu"><option value="">${esc(tr(POS_CASH))}</option>${custs.filter(c => c.name !== POS_CASH).map(c => opt(c.id, c.name)).join('')}</select>`, 'wide')}
          ${field('طريقة الدفع', `<select id="ppm">${opt('1110', tr('نقدا (الصندوق)'))}${opt('1120', tr('شبكة / بطاقة (البنك)'))}${opt('', tr('آجل — بدون قبض'))}</select>`, 'wide')}</div>
        <div id="perr"></div><button class="btn pri" id="pok" style="width:100%;margin-top:8px;min-height:48px">${esc(tr('إتمام البيع'))}</button></div></div>
    <div class="posbar" id="pbar"></div>`;
  const grid = $('#pgrid', page), draw = () => {
    const t = tot();
    $('#pcart', page).innerHTML = cart.length ? `<table class="lines" style="width:100%"><tbody>${cart.map((l, i) => `<tr><td>${esc(l.it.name)}<div class="small muted num">${money(l.price)}</div></td>
        <td style="white-space:nowrap"><button class="btn sm" data-m="${i}" aria-label="-">−</button> <b class="num">${+l.qty}</b> <button class="btn sm" data-p="${i}" aria-label="+">+</button></td>
        <td class="num r">${money(r2(l.qty * l.price))}</td><td><button class="btn sm" data-x="${i}" aria-label="${esc(tr('حذف'))}">×</button></td></tr>`).join('')}</tbody></table>
      <p class="r" style="margin:8px 0 0">${esc(tr('قبل الضريبة'))} <span class="num">${money(t.net)}</span> · ${esc(tr('الضريبة'))} <span class="num">${money(t.vat)}</span></p>
      <p class="r" style="font-size:1.4em;margin:4px 0 0"><b>${esc(tr('الإجمالي'))} <span class="num">${money(t.total)}</span></b></p>`
      : `<p class="muted">${esc(tr('السلة فارغة — اختر صنفا.'))}</p>`;
    // phones: the total and «complete sale» stay at the bottom of the screen while picking items
    $('#pbar', page).innerHTML = cart.length ? `<b>${esc(tr('الإجمالي'))} <span class="num">${money(t.total)}</span> <span class="small muted">(${cart.reduce((a, l) => a + l.qty, 0)})</span></b>
      <button type="button" class="btn pri" id="pbgo">${esc(tr('السلة والدفع'))}</button>` : '';
    if ($('#pbgo', page)) $('#pbgo', page).onclick = () => $('#pcart', page).scrollIntoView({ behavior: 'smooth', block: 'start' });
    $$('[data-p]', page).forEach(b => b.onclick = () => { cart[+b.dataset.p].qty += 1; draw(); });
    $$('[data-m]', page).forEach(b => b.onclick = () => { const l = cart[+b.dataset.m]; l.qty = r2(l.qty - 1); if (l.qty <= 0) cart.splice(+b.dataset.m, 1); draw(); });
    $$('[data-x]', page).forEach(b => b.onclick = () => { cart.splice(+b.dataset.x, 1); draw(); });
  };
  const showItems = q => { const list = (q ? sellable.filter(i => i.name.includes(q) || (i.code || '').includes(q)) : sellable).slice(0, 60);
    grid.innerHTML = list.map(i => `<button type="button" class="card" data-i="${i.id}" style="text-align:start;padding:10px;cursor:pointer"><b>${esc(i.name)}</b><div class="small muted num">${money(i.sale_price)}</div></button>`).join('')
      || `<p class="muted">${esc(tr('لا توجد أصناف مطابقة.'))}</p>`;
    $$('[data-i]', grid).forEach(b => b.onclick = () => add(sellable.find(i => i.id === b.dataset.i))); };
  const scan = v => { const r = find(v); if (r) { add(r.it, r.f); $('#pmsg', page).innerHTML = `<span class="ok">${esc(r.it.name)}</span>`; return true; }
    $('#pmsg', page).innerHTML = `<span class="bad">${esc(tr('لم يُعثر على الصنف'))}: ${esc(v)}</span>`; return false; };
  $('#psc', page).oninput = e => showItems(e.target.value.trim());
  $('#psc', page).onkeydown = e => { if (e.key !== 'Enter') return; e.preventDefault(); if (scan(e.target.value)) { e.target.value = ''; showItems(''); } };
  if ($('#pcam', page)) $('#pcam', page).onclick = async () => {
    let stream; try { stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } }); } catch (e) { return toast(tr('لم يُسمح باستخدام الكاميرا')); }
    const d = modal(tr('المسح بالكاميرا'), `<video id="cv" playsinline muted style="width:100%;max-height:60vh;background:#000;border-radius:8px"></video><p class="small" id="cvm">${esc(tr('وجّه الكاميرا إلى الباركود'))}</p>`, { ok: 'تم' });
    const v = $('#cv', d); v.srcObject = stream; await v.play().catch(() => {});
    const det = new BarcodeDetector(); let last = '', lastAt = 0, live = true;
    d.addEventListener('close', () => { live = false; stream.getTracks().forEach(t => t.stop()); }, { once: true });
    const loop = async () => { if (!live) return; try { const r = await det.detect(v), code = r[0] && r[0].rawValue;
      if (code && (code !== last || Date.now() - lastAt > 1500)) { last = code; lastAt = Date.now(); scan(code); $('#cvm', d).textContent = $('#pmsg', page).textContent; if (navigator.vibrate) navigator.vibrate(60); } } catch (e) {}
      setTimeout(loop, 250); };
    loop(); };
  $('#pok', page).onclick = async () => {
    if (!cart.length) return showErr($('#perr', page), new Error('السلة فارغة'));
    try { await busy($('#pok', page), async () => {
      let party = $('#pcu', page).value;
      if (!party) { const [w] = await db.get('parties', { company_id: 'eq.' + S.cid, kind: 'eq.customer', name: 'eq.' + POS_CASH, select: 'id' });
        party = w ? w.id : (await db.ins('parties', { company_id: S.cid, kind: 'customer', name: POS_CASH }))[0].id; }
      const t = tot(), d0 = today();
      const id = await db.rpc('post_sales_invoice_sn', { p_company: S.cid, p_doc: { party, date: d0, due: d0, lines: cart.map(l => ({ item: l.it.id, qty: l.qty, price: l.price })) } });
      const acc = $('#ppm', page).value;
      if (acc) await db.rpc('record_payment', { p_company: S.cid, p_doc: { direction: 'in', party, invoice: id, amount: t.total, date: d0, account: acc } });
      const lines = cart.map(l => ({ ...l })); cart.length = 0; draw();
      toast(tr('تم البيع')); await posReceipt(id, lines, acc);
    }); } catch (er) { showErr($('#perr', page), er); }
  };
  showItems(''); draw(); setTimeout(() => $('#psc', page).focus(), 50);
};
// the small receipt (80 mm): a simplified tax invoice with the QR; when linked to Fatoora, it waits a few seconds for the signed QR
async function posReceipt(id, lines, acc) {
  const [doc] = await db.get('sales_invoices', { id: 'eq.' + id }), c = S.company || {};
  if (S.zatcaOn) { await fnCall('zatca', { action: 'process', company: S.cid }).catch(() => null);
    const [z] = await db.get('zatca_docs', { doc_id: 'eq.' + id, select: 'qr' }).catch(() => []); if (z && z.qr) doc._zqr = z.qr; }
  const w = document.createElement('div'); w.className = 'rcpt'; w.setAttribute('data-nt', ''); w.dir = 'rtl';
  w.innerHTML = `<div style="text-align:center">${c.logo ? `<img src="${esc(c.logo)}" alt="" style="max-height:18mm;max-width:50mm">` : ''}<div style="font-weight:700;font-size:12pt">${esc(c.name || '')}</div>
      ${c.vat_no ? `<div>الرقم الضريبي VAT <span class="num">${esc(c.vat_no)}</span></div>` : ''}<div style="font-weight:700;margin-top:2mm">فاتورة ضريبية مبسطة<br>Simplified Tax Invoice</div>
      <div>${esc(doc.no)} · <span class="num">${esc(String(doc.created_at || '').slice(0, 16).replace('T', ' '))}</span></div></div>
    <table style="width:100%;border-collapse:collapse;margin-top:2mm">${lines.map(l => `<tr><td>${esc(l.it.name)}<br><span class="num">${+l.qty} × ${money(l.price)}</span></td><td class="num" style="text-align:end;vertical-align:bottom">${money(r2(l.qty * l.price))}</td></tr>`).join('')}</table>
    <div style="border-top:1px dashed #000;margin-top:2mm;padding-top:2mm">
      <div style="display:flex;justify-content:space-between"><span>الإجمالي قبل الضريبة</span><span class="num">${money(doc.subtotal)}</span></div>
      <div style="display:flex;justify-content:space-between"><span>ضريبة القيمة المضافة</span><span class="num">${money(doc.vat)}</span></div>
      <div style="display:flex;justify-content:space-between;font-weight:700;font-size:12pt"><span>الإجمالي Total</span><span class="num">${money(doc.total)} SAR</span></div>
      <div>${acc === '1110' ? 'نقدا Cash' : acc === '1120' ? 'شبكة Card' : 'آجل Credit'}</div></div>
    <div style="text-align:center;margin-top:3mm">${zatcaQr(doc, 150)}</div><div style="text-align:center">شكرا لزيارتكم · Thank you</div>`;
  printWith(w, '@page{size:80mm auto;margin:4mm}.rcpt{font-family:"IBM Plex Sans Arabic",Tahoma,Arial,sans-serif;font-size:9.5pt;color:#000;width:72mm}');
}
