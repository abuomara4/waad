'use strict';
/* «نقطة البيع» (#/pos): a till for shops on any tablet or phone browser. The cashier opens a shift with the cash float, picks
   items by tapping, typing or scanning the barcode (camera too), gives a discount within the company's limit, takes cash, card,
   a cheque, or a mix of them (the rest on credit), and pos_sale posts a simplified sales invoice on the shift, records the receipts, takes the stock out,
   sends it to ZATCA when linked, and prints a small receipt with the QR. Closing the shift counts the cash and prints the Z
   report; a shortage or overage is posted at once (0144). */
const POS_CASH = 'عميل نقدي';
const posUid = () => ((S.session || {}).user || {}).id;
VIEWS['#/pos'] = async page => {
  if (!can('sales')) { page.innerHTML = `<div class="note">${esc(tr('نقطة البيع لمن لديه صلاحية المبيعات.'))}</div>`; return; }
  const [shifts, items, units, custs] = await Promise.all([db.get('pos_shifts', { company_id: 'eq.' + S.cid, opened_by: 'eq.' + posUid(), status: 'eq.open', select: 'id,no,opened_at,opening_float' }).catch(() => []),
    db.get('items', { company_id: 'eq.' + S.cid, active: 'eq.true', order: 'name', select: 'id,code,name,name_en,barcode,sale_price,vat_rate,type,track_serial,unit' }),
    db.get('item_units', { company_id: 'eq.' + S.cid, select: 'item_id,name,factor,barcode' }).catch(() => []),
    db.get('parties', { company_id: 'eq.' + S.cid, kind: 'eq.customer', order: 'name', select: 'id,name,vat_no' })]);
  const shift = shifts[0], mgr = has('owner', 'admin', 'finance'), lim = n0((S.company || {}).pos_max_disc ?? 10);
  const headBtns = `<button type="button" class="btn" id="phs">${esc(tr('سجل الورديات'))}</button>${has('owner', 'admin') ? `<button type="button" class="btn" id="pst">${esc(tr('إعدادات'))}</button>` : ''}`;
  const bindHead = () => {
    $('#phs', page).onclick = () => posHistory();
    if ($('#pst', page)) $('#pst', page).onclick = () => modal(tr('إعدادات نقطة البيع'), `<div class="fg">${field('أعلى خصم يعطيه الكاشير %', inp('d', lim, 'type="number" min="0" max="100" step="0.5" required'))}</div>
      <p class="muted small">${esc(tr('المالك ومدير النظام والمالية يتجاوزون الحد. الحد يُفحص في الخادم عند كل بيع.'))}</p>`, {
      onOk: async f => { await db.upd('companies', { id: 'eq.' + S.cid }, { pos_max_disc: +f.d }); await loadContext(); toast(tr('تم الحفظ')); route(); } });
  };
  if (!shift) {
    page.innerHTML = `<div class="head"><div><h1>${esc(tr('نقطة البيع'))}</h1><div class="muted">${esc(tr('ابدأ ورديتك بعدّ النقد الموجود في الصندوق.'))}</div></div><div class="row" style="gap:6px">${headBtns}</div></div>
      <div class="card" style="max-width:420px"><h2>${esc(tr('فتح وردية'))}</h2><form id="pof" class="fg">${field('النقد في الصندوق عند البدء', inp('f', '0', 'type="number" min="0" step="0.01" required inputmode="decimal"'), 'wide')}
        <div class="wide"><div id="poe"></div><button class="btn pri" id="pob" style="min-height:44px">${esc(tr('فتح الوردية'))}</button></div></form></div>`;
    bindHead();
    $('#pof', page).onsubmit = async e => { e.preventDefault(); const f = formData(e.target);
      try { await busy($('#pob', page), async () => { await db.rpc('pos_shift_open', { p_company: S.cid, p_float: +f.f || 0 }); route(); }); } catch (er) { showErr($('#poe', page), er); } };
    return;
  }
  const sellable = items.filter(i => !i.track_serial && !/^PRJ-/.test(i.code || ''));   // project hours / claims items are invoiced from the project
  const cart = [];   // { it, qty, disc }
  const priceOf = l => r2(n0(l.it.sale_price) * (1 - n0(l.disc) / 100));
  const find = v => { v = String(v || '').trim(); if (!v) return null;
    const it = sellable.find(i => i.barcode === v || i.code === v); if (it) return { it, f: 1 };
    const u = units.find(x => x.barcode === v); if (u) { const i2 = sellable.find(i => i.id === u.item_id); if (i2) return { it: i2, f: +u.factor }; }
    const byName = sellable.filter(i => i.name.includes(v) || (i.name_en || '').toLowerCase().includes(v.toLowerCase()));
    return byName.length === 1 ? { it: byName[0], f: 1 } : null; };
  const add = (it, q = 1) => { const l = cart.find(x => x.it.id === it.id); if (l) l.qty = r2(l.qty + q); else cart.push({ it, qty: q, disc: n0($('#pdall', page) && $('#pdall', page).value) }); draw(); };
  const tot = () => { let net = 0, vat = 0, disc = 0; cart.forEach(l => { const p = priceOf(l), a = r2(l.qty * p); net += a; vat += r2(a * n0(l.it.vat_rate == null ? 15 : l.it.vat_rate) / 100); disc += r2(l.qty * (n0(l.it.sale_price) - p)); });
    return { net: r2(net), vat: r2(vat), total: r2(net + vat), disc: r2(disc) }; };
  const okDisc = d => mgr || d <= lim + 0.0001;
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('نقطة البيع'))}</h1><div class="muted">${esc(tr('وردية'))} <span class="num">${esc(shift.no)}</span> · ${esc(tr('منذ'))} <span class="num">${esc(String(shift.opened_at).slice(11, 16))}</span></div></div>
      <div class="row" style="gap:6px;flex-wrap:wrap">${headBtns}<button type="button" class="btn danger" id="pcl">${esc(tr('إغلاق الوردية'))}</button></div></div>
    <div class="pos" style="display:grid;grid-template-columns:minmax(0,3fr) minmax(280px,2fr);gap:14px">
      <div><div class="row" style="gap:8px;margin-bottom:10px"><input id="psc" aria-label="${esc(tr('بحث عن صنف'))}" placeholder="${esc(tr('امسح الباركود أو اكتب اسم الصنف أو رمزه'))}" autocomplete="off" style="flex:1">
        ${'BarcodeDetector' in window ? `<button type="button" class="btn" id="pcam">${esc(tr('الكاميرا'))}</button>` : ''}</div><div class="small" id="pmsg" role="status"></div>
        <div id="pgrid" style="display:grid;grid-template-columns:repeat(auto-fill,minmax(130px,1fr));gap:8px;margin-top:8px"></div></div>
      <div class="card" style="align-self:start"><div id="pcart"></div>
        <div class="fg" style="margin-top:10px">${field('خصم على كل الأصناف %', inp('dall', '', `id="pdall" type="number" min="0" max="${mgr ? 100 : lim}" step="0.5" placeholder="0"`), 'wide')}
          ${field('العميل', `<select id="pcu"><option value="">${esc(tr(POS_CASH))}</option>${custs.filter(c => c.name !== POS_CASH).map(c => opt(c.id, c.name)).join('')}</select>`, 'wide')}
          ${field('طريقة الدفع', `<select id="ppm">${opt('cash', tr('نقدا'))}${opt('card', tr('شبكة / بطاقة'))}${opt('cheque', tr('شيك'))}${opt('credit', tr('آجل — بدون قبض'))}${opt('mix', tr('أكثر من طريقة'))}</select>`, 'wide')}
          <div class="wide" id="ppx"></div></div>
        <div id="perr"></div><button class="btn pri" id="pok" style="width:100%;margin-top:8px;min-height:48px">${esc(tr('إتمام البيع'))}</button></div></div>
    <div class="posbar" id="pbar"></div>`;
  bindHead();
  // cash: what the customer handed over and the change; cheque: its number, bank and date; mix: cash, card and cheque amounts —
  // whatever is left stays on credit
  const chqF = () => `<div class="fg">${field('رقم الشيك', '<input id="pqn" maxlength="30" dir="ltr" inputmode="numeric">')}${field('البنك', '<input id="pqb" maxlength="60">')}${field('تاريخ الاستحقاق', `<input id="pqd" type="date" value="${today()}" min="${today()}">`)}</div>`;
  const amtF = (id, t) => field(t, `<input id="${id}" type="number" min="0" step="0.01" inputmode="decimal">`);
  const payBox = () => { const m = $('#ppm', page).value, t = tot();
    $('#ppx', page).innerHTML = m === 'cash' ? `${field('المستلم من العميل', `<input id="prc" type="number" min="0" step="0.01" inputmode="decimal" placeholder="${money(t.total)}">`)}<div class="small" id="pchg"></div>`
      : m === 'cheque' ? chqF()
      : m === 'mix' ? `<div class="fg">${amtF('pmc', 'نقدا')}${amtF('pmd', 'شبكة / بطاقة')}${amtF('pmq', 'شيك')}</div><div id="pmqx"></div><div class="small" id="pchg"></div>` : '';
    const upd = () => { const t2 = tot();
      if ($('#prc', page)) { const g = n0($('#prc', page).value); $('#pchg', page).innerHTML = g ? (g >= t2.total ? `${esc(tr('الباقي للعميل'))} <b class="num">${money(r2(g - t2.total))}</b>` : `<span class="bad">${esc(tr('المستلم أقل من الإجمالي'))}</span>`) : ''; }
      if ($('#pmc', page)) { const paid = r2(n0($('#pmc', page).value) + n0($('#pmd', page).value) + n0($('#pmq', page).value)), rest = r2(t2.total - paid);
        if (n0($('#pmq', page).value) > 0 && !$('#pqn', page)) $('#pmqx', page).innerHTML = chqF(); else if (!(n0($('#pmq', page).value) > 0)) $('#pmqx', page).innerHTML = '';
        $('#pchg', page).innerHTML = rest < 0 ? `<span class="bad">${esc(tr('المدفوع أكبر من الإجمالي'))}</span>` : rest > 0 ? `${esc(tr('الباقي آجل على العميل'))} <b class="num">${money(rest)}</b>` : `<span class="ok">${esc(tr('مدفوع بالكامل'))}</span>`; } };
    ['#prc', '#pmc', '#pmd', '#pmq'].forEach(x => { if ($(x, page)) $(x, page).oninput = upd; }); upd(); };
  const grid = $('#pgrid', page), draw = () => {
    const t = tot();
    $('#pcart', page).innerHTML = cart.length ? `<table class="lines" style="width:100%"><tbody>${cart.map((l, i) => `<tr><td>${esc(l.it.name)}<div class="small muted num">${n0(l.disc) ? `<s>${money(l.it.sale_price)}</s> ` : ''}${money(priceOf(l))}</div></td>
        <td style="white-space:nowrap"><button class="btn sm" data-m="${i}" aria-label="-">−</button> <b class="num">${+l.qty}</b> <button class="btn sm" data-p="${i}" aria-label="+">+</button></td>
        <td class="num r">${money(r2(l.qty * priceOf(l)))}</td><td style="white-space:nowrap"><button class="btn sm" data-d="${i}" aria-label="${esc(tr('خصم'))}" title="${esc(tr('خصم'))}">${n0(l.disc) ? `<span class="num">${n0(l.disc)}%</span>` : '%'}</button> <button class="btn sm" data-x="${i}" aria-label="${esc(tr('حذف'))}">×</button></td></tr>`).join('')}</tbody></table>
      <p class="r" style="margin:8px 0 0">${t.disc ? `${esc(tr('الخصم'))} <span class="num">${money(t.disc)}</span> · ` : ''}${esc(tr('قبل الضريبة'))} <span class="num">${money(t.net)}</span> · ${esc(tr('الضريبة'))} <span class="num">${money(t.vat)}</span></p>
      <p class="r" style="font-size:1.4em;margin:4px 0 0"><b>${esc(tr('الإجمالي'))} <span class="num">${money(t.total)}</span></b></p>`
      : `<p class="muted">${esc(tr('السلة فارغة — اختر صنفا.'))}</p>`;
    // phones: the total and «complete sale» stay at the bottom of the screen while picking items
    $('#pbar', page).innerHTML = cart.length ? `<b>${esc(tr('الإجمالي'))} <span class="num">${money(t.total)}</span> <span class="small muted">(${cart.reduce((a, l) => a + l.qty, 0)})</span></b>
      <button type="button" class="btn pri" id="pbgo">${esc(tr('السلة والدفع'))}</button>` : '';
    if ($('#pbgo', page)) $('#pbgo', page).onclick = () => $('#pcart', page).scrollIntoView({ behavior: 'smooth', block: 'start' });
    $$('[data-p]', page).forEach(b => b.onclick = () => { cart[+b.dataset.p].qty += 1; draw(); });
    $$('[data-m]', page).forEach(b => b.onclick = () => { const l = cart[+b.dataset.m]; l.qty = r2(l.qty - 1); if (l.qty <= 0) cart.splice(+b.dataset.m, 1); draw(); });
    $$('[data-x]', page).forEach(b => b.onclick = () => { cart.splice(+b.dataset.x, 1); draw(); });
    $$('[data-d]', page).forEach(b => b.onclick = () => { const l = cart[+b.dataset.d];
      modal(tr('خصم على') + ' ' + l.it.name, `<div class="fg">${field('نسبة الخصم %', inp('d', l.disc || '', `type="number" min="0" max="${mgr ? 100 : lim}" step="0.5" required`))}</div>
        <p class="muted small">${esc(mgr ? tr('بلا حد لدورك.') : tr('أعلى خصم مسموح') + ' ' + lim + '%')}</p>`, {
        onOk: async f => { const d = n0(f.d); if (d < 0 || d > 100) throw new Error(tr('نسبة الخصم بين 0 و 100')); if (!okDisc(d)) throw new Error(tr('أعلى خصم مسموح') + ' ' + lim + '%'); l.disc = d; draw(); } }); });
    if ($('#ppx', page)) payBox();
  };
  $('#pdall', page).oninput = e => { const d = n0(e.target.value); if (!okDisc(d)) { e.target.value = lim; return toast(tr('أعلى خصم مسموح') + ' ' + lim + '%'); } cart.forEach(l => l.disc = d); draw(); };
  $('#ppm', page).onchange = payBox;
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
  $('#pcl', page).onclick = () => posClose(shift.id);
  $('#pok', page).onclick = async () => {
    if (!cart.length) return showErr($('#perr', page), new Error('السلة فارغة'));
    try { await busy($('#pok', page), async () => {
      const t = tot(), m = $('#ppm', page).value, v = x => $(x, page) ? r2(n0($(x, page).value)) : 0;
      let party = $('#pcu', page).value;
      const card = m === 'card' ? t.total : m === 'mix' ? v('#pmd') : 0, chq = m === 'cheque' ? t.total : m === 'mix' ? v('#pmq') : 0;
      const cash = m === 'cash' ? t.total : m === 'mix' ? v('#pmc') : 0, rest = r2(t.total - cash - card - chq);
      if (rest < -0.004) throw new Error(tr('المدفوع أكبر من الإجمالي'));
      if ((rest > 0.004 || chq > 0) && !party) throw new Error(tr(chq > 0 ? 'الدفع بشيك لعميل مسجّل — اختر العميل' : 'البيع الآجل لعميل مسجّل — اختر العميل'));
      if (m === 'cash' && $('#prc', page) && $('#prc', page).value !== '' && n0($('#prc', page).value) < t.total) throw new Error(tr('المستلم أقل من الإجمالي'));
      const cheque = chq > 0 ? { amount: chq, cheque_no: ($('#pqn', page) || {}).value || '', bank: ($('#pqb', page) || {}).value || '', due_date: ($('#pqd', page) || {}).value || today() } : null;
      if (cheque && !cheque.cheque_no.trim()) throw new Error(tr('أدخل رقم الشيك'));
      if (!party) { const [w] = await db.get('parties', { company_id: 'eq.' + S.cid, kind: 'eq.customer', name: 'eq.' + POS_CASH, select: 'id' });
        party = w ? w.id : (await db.ins('parties', { company_id: S.cid, kind: 'customer', name: POS_CASH }))[0].id; }
      const id = await db.rpc('pos_sale', { p_company: S.cid, p_shift: shift.id, p_doc: { party, lines: cart.map(l => ({ item: l.it.id, qty: l.qty, price: priceOf(l) })) }, p_cash: cash, p_card: card, p_cheque: cheque });
      const got = m === 'cash' && $('#prc', page) ? n0($('#prc', page).value) : 0;
      const lines = cart.map(l => ({ ...l, price: priceOf(l) })); cart.length = 0; $('#pdall', page).value = ''; draw();
      toast(tr('تم البيع')); await posReceipt(id, lines, { cash, card, chq, got, disc: t.disc });
    }); } catch (er) { showErr($('#perr', page), er); }
  };
  showItems(''); draw(); setTimeout(() => $('#psc', page).focus(), 50);
};
// close the shift: the figures, the cash counted, then the Z report
async function posClose(id) {
  const s = await db.rpc('pos_shift_summary', { p_shift: id });
  const row = (t, v, b) => `<tr><td>${esc(tr(t))}</td><td class="num r">${b ? '<b>' + v + '</b>' : v}</td></tr>`;
  modal(tr('إغلاق الوردية') + ' ' + s.no, `<div class="tw"><table><tbody>${row('الفواتير', s.invoices)}${row('إجمالي المبيعات', money(s.gross))}${row('الخصومات', money(s.discounts))}
      ${row('شبكة / بطاقة', money(s.card))}${row('شيكات', money(s.cheque))}${row('آجل', money(s.credit))}${row('النقد في البداية', money(s.opening_float))}${row('نقدا', money(s.cash))}${row('النقد المتوقع في الصندوق', money(s.expected_cash), 1)}</tbody></table></div>
    <div class="fg" style="margin-top:10px">${field('النقد المعدود فعلا', inp('c', '', 'type="number" min="0" step="0.01" required inputmode="decimal" id="pcc"'))}${field('ملاحظة', inp('n', '', 'maxlength="500"'))}</div><div class="small" id="pcdf"></div>
    <p class="muted small">${esc(tr('العجز أو الزيادة يُقيّد فورا على حساب «عجز وزيادة الصندوق».'))}</p>`, {
    ok: 'إغلاق وطباعة', onOk: async f => { const r = await db.rpc('pos_shift_close', { p_shift: id, p_counted: +f.c, p_note: f.n || null }); toast(tr('أُغلقت الوردية')); posZ(r); route(); } });
  const cc = document.getElementById('pcc'); if (cc) cc.oninput = () => { const d = r2(n0(cc.value) - n0(s.expected_cash));
    document.getElementById('pcdf').innerHTML = cc.value === '' ? '' : d === 0 ? `<span class="ok">${esc(tr('مطابق'))}</span>` : `<span class="bad">${esc(tr(d < 0 ? 'عجز' : 'زيادة'))} <b class="num">${money(Math.abs(d))}</b></span>`; };
}
// the Z report (80 mm)
function posZ(s) {
  const c = S.company || {}, ln = (t, v) => `<div style="display:flex;justify-content:space-between"><span>${t}</span><span class="num">${v}</span></div>`;
  const w = document.createElement('div'); w.className = 'rcpt'; w.setAttribute('data-nt', ''); w.dir = 'rtl';
  w.innerHTML = `<div style="text-align:center"><div style="font-weight:700;font-size:12pt">${esc(c.name || '')}</div><div style="font-weight:700;margin-top:2mm">تقرير إغلاق الوردية<br>Shift Z report</div>
      <div><span class="num">${esc(s.no)}</span> · ${esc(s.cashier || '')}</div><div class="num">${esc(String(s.opened_at || '').slice(0, 16).replace('T', ' '))} → ${esc(String(s.closed_at || '').slice(0, 16).replace('T', ' '))}</div></div>
    <div style="border-top:1px dashed #000;margin-top:2mm;padding-top:2mm">${ln('الفواتير Invoices', s.invoices)}${ln('المبيعات Sales', money(s.gross))}${ln('الخصومات Discounts', money(s.discounts))}
      ${ln('شبكة Card', money(s.card))}${ln('شيكات Cheques', money(s.cheque))}${ln('آجل Credit', money(s.credit))}${ln('نقد البداية Float', money(s.opening_float))}${ln('نقدا Cash', money(s.cash))}</div>
    <div style="border-top:1px dashed #000;margin-top:2mm;padding-top:2mm;font-weight:700">${ln('المتوقع Expected', money(s.expected_cash))}${ln('المعدود Counted', money(s.counted_cash))}${ln('الفرق Difference', money(s.difference))}</div>
    ${s.note ? `<div style="margin-top:2mm">${esc(s.note)}</div>` : ''}<div style="margin-top:8mm">توقيع الكاشير ____________</div><div style="margin-top:6mm">توقيع المستلم ____________</div>`;
  printWith(w, '@page{size:80mm auto;margin:4mm}.rcpt{font-family:"IBM Plex Sans Arabic",Tahoma,Arial,sans-serif;font-size:9.5pt;color:#000;width:72mm}');
}
// the shifts: the cashier's own, or every cashier's for management; a closed one reprints its Z report
async function posHistory() {
  const mgr = has('owner', 'admin', 'finance');
  const rows = await db.get('pos_shifts', Object.assign({ company_id: 'eq.' + S.cid, order: 'opened_at.desc', limit: 40 }, mgr ? {} : { opened_by: 'eq.' + posUid() }));
  const d = modal(tr('سجل الورديات'), tbl([{ t: 'الوردية', h: s => `<span class="num">${esc(s.no)}</span>` }, { t: 'الفتح', h: s => `<span class="num">${esc(String(s.opened_at).slice(0, 16).replace('T', ' '))}</span>` },
    { t: 'الحالة', h: s => `<span class="badge ${s.status === 'open' ? 'info' : ''}">${esc(tr(s.status === 'open' ? 'مفتوحة' : 'مغلقة'))}</span>` }, { t: 'المبيعات', r: 1, h: s => s.gross != null ? money(s.gross) : '—' },
    { t: 'نقدا', r: 1, h: s => s.cash != null ? money(s.cash) : '—' }, { t: 'شبكة', r: 1, h: s => s.card != null ? money(s.card) : '—' }, { t: 'شيكات', r: 1, h: s => s.cheque != null ? money(s.cheque) : '—' },
    { t: 'الفرق', r: 1, h: s => s.difference == null ? '—' : `<span class="${n0(s.difference) ? 'bad' : 'ok'}">${money(s.difference)}</span>` },
    { t: '', h: s => s.status === 'closed' ? `<button type="button" class="btn sm" data-z="${s.id}">${esc(tr('طباعة'))}</button>` : mgr && s.opened_by !== posUid() ? `<button type="button" class="btn sm" data-zc="${s.id}">${esc(tr('إغلاق'))}</button>` : '' }], rows, { empty: 'لا توجد ورديات' }), { wide: true });
  $$('[data-z]', d).forEach(b => b.onclick = async () => posZ(await db.rpc('pos_shift_summary', { p_shift: b.dataset.z })));
  $$('[data-zc]', d).forEach(b => b.onclick = () => { d.close(); posClose(b.dataset.zc); });
}
// the small receipt (80 mm): a simplified tax invoice with the QR; when linked to Fatoora, it waits a few seconds for the signed QR
async function posReceipt(id, lines, pay) {
  const [doc] = await db.get('sales_invoices', { id: 'eq.' + id }), c = S.company || {};
  if (S.zatcaOn) { await fnCall('zatca', { action: 'process', company: S.cid }).catch(() => null);
    const [z] = await db.get('zatca_docs', { doc_id: 'eq.' + id, select: 'qr' }).catch(() => []); if (z && z.qr) doc._zqr = z.qr; }
  const ln = (t, v, b) => `<div style="display:flex;justify-content:space-between${b ? ';font-weight:700;font-size:12pt' : ''}"><span>${t}</span><span class="num">${v}</span></div>`;
  const parts = [[pay.cash, 'نقدا Cash'], [pay.card, 'شبكة Card'], [pay.chq, 'شيك Cheque']].filter(x => n0(x[0]) > 0), rest = r2(n0(doc.total) - n0(pay.cash) - n0(pay.card) - n0(pay.chq));
  const how = parts.length === 1 && rest <= 0 ? parts[0][1] : !parts.length ? 'آجل Credit' : '';
  const w = document.createElement('div'); w.className = 'rcpt'; w.setAttribute('data-nt', ''); w.dir = 'rtl';
  w.innerHTML = `<div style="text-align:center">${c.logo ? `<img src="${esc(c.logo)}" alt="" style="max-height:18mm;max-width:50mm">` : ''}<div style="font-weight:700;font-size:12pt">${esc(c.name || '')}</div>
      ${c.vat_no ? `<div>الرقم الضريبي VAT <span class="num">${esc(c.vat_no)}</span></div>` : ''}<div style="font-weight:700;margin-top:2mm">فاتورة ضريبية مبسطة<br>Simplified Tax Invoice</div>
      <div>${esc(doc.no)} · <span class="num">${esc(String(doc.created_at || '').slice(0, 16).replace('T', ' '))}</span></div></div>
    <table style="width:100%;border-collapse:collapse;margin-top:2mm">${lines.map(l => `<tr><td>${esc(l.it.name)}<br><span class="num">${+l.qty} × ${money(l.price)}</span>${n0(l.disc) ? ` <span class="num">(−${n0(l.disc)}%)</span>` : ''}</td><td class="num" style="text-align:end;vertical-align:bottom">${money(r2(l.qty * l.price))}</td></tr>`).join('')}</table>
    <div style="border-top:1px dashed #000;margin-top:2mm;padding-top:2mm">
      ${pay.disc ? ln('الخصم Discount', money(pay.disc)) : ''}${ln('الإجمالي قبل الضريبة', money(doc.subtotal))}${ln('ضريبة القيمة المضافة', money(doc.vat))}${ln('الإجمالي Total', money(doc.total) + ' SAR', 1)}
      ${how ? `<div>${how}</div>` : parts.map(x => ln(x[1], money(x[0]))).join('') + (rest > 0 ? ln('آجل Credit', money(rest)) : '')}
      ${pay.got && pay.got >= doc.total ? ln('المستلم Received', money(pay.got)) + ln('الباقي Change', money(r2(pay.got - doc.total))) : ''}</div>
    <div style="text-align:center;margin-top:3mm">${zatcaQr(doc, 150)}</div><div style="text-align:center">شكرا لزيارتكم · Thank you</div>`;
  printWith(w, '@page{size:80mm auto;margin:4mm}.rcpt{font-family:"IBM Plex Sans Arabic",Tahoma,Arial,sans-serif;font-size:9.5pt;color:#000;width:72mm}');
}
