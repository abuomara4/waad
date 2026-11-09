'use strict';
/* ===== sales cycle: quotations → sales orders → delivery notes → tax invoices ===== */
const SK = {
  quote: { h: '#/quotes', t: 'عروض الأسعار', one: 'عرض سعر', newT: 'عرض سعر جديد' },
  order: { h: '#/orders', t: 'أوامر البيع', one: 'أمر بيع', newT: 'أمر بيع جديد' },
};
const soExpired = o => o.kind === 'quote' && o.status === 'open' && o.valid_until < today();
const soBadge = o => {
  if (soExpired(o)) return '<span class="badge bad">منتهي</span>';
  const m = { open: [o.kind === 'quote' ? 'مفتوح' : 'قيد التنفيذ', 'wait'], accepted: ['مقبول', 'ok'], rejected: ['مرفوض', 'bad'], converted: ['حُوّل إلى أمر بيع', 'ok'],
    closed: [o.reason ? 'مغلق' : 'مكتمل', o.reason ? '' : 'ok'], cancelled: ['ملغى', ''] }[o.status] || [o.status, ''];
  return `<span class="badge ${m[1]}">${esc(m[0])}</span>`;
};
const soNet = (price, disc) => r2(n0(price) * (1 - n0(disc) / 100));
const qtyTxt = v => String(+n0(v).toFixed(3));
async function soLookups() {
  const [parties, items] = await Promise.all([can('sales') ? db.get('parties', Object.assign(C(), { kind: 'eq.customer', order: 'name' })) : [], db.get('items', Object.assign(C(), { order: 'code' }))]);
  const pm = {}, im = {}; parties.forEach(p => pm[p.id] = p); items.forEach(i => im[i.id] = i); return { parties, items, pm, im };
}

/* ----- list ----- */
function soList(kind) {
  return async (page, arg, q) => {
    const K = SK[kind];
    if (kind === 'quote' && !can('sales')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
    if (arg === 'new') return soForm(page, kind, null, q);
    if (arg && arg.endsWith('/edit')) return soForm(page, kind, arg.split('/')[0]);
    if (arg) return soView(page, kind, arg);
    const [docs, L] = await Promise.all([db.get('sales_orders', Object.assign(C(), { kind: 'eq.' + kind, order: 'date.desc,no.desc', limit: 300 })), soLookups()]);
    let prog = {};
    if (kind === 'order' && docs.length) (await db.get('sales_order_lines', { order_id: 'in.(' + docs.map(d => d.id).join(',') + ')', select: 'order_id,qty,delivered,invoiced' }))
      .forEach(l => { const p = prog[l.order_id] = prog[l.order_id] || { q: 0, d: 0, i: 0 }; p.q += n0(l.qty); p.d += n0(l.delivered); p.i += n0(l.invoiced); });
    const pct = (a, b) => b ? Math.round(a / b * 100) + '%' : '—';
    page.innerHTML = `<div class="head"><div><h1>${K.t}</h1><div class="muted small">${kind === 'quote' ? 'العرض يُرسل للعميل، وعند قبوله يتحول إلى أمر بيع بضغطة' : 'من الأمر تُصدر إشعارات التسليم ثم الفاتورة الضريبية، كاملة أو على دفعات'}</div></div>${can('sales') ? `<a class="btn pri" href="${K.h}/new">${K.newT}</a>` : ''}</div>
      ${tbl([{ t: 'الرقم', h: d => `<span class="num">${esc(d.no)}</span>` }, { t: 'التاريخ', h: d => fdate(d.date) }, { t: 'العميل', h: d => esc((L.pm[d.party_id] || {}).name || '—') },
        ...(kind === 'quote' ? [{ t: 'صالح حتى', h: d => fdate(d.valid_until) }] : [{ t: 'التسليم', h: d => pct((prog[d.id] || {}).d, (prog[d.id] || {}).q) }, { t: 'الفوترة', h: d => pct((prog[d.id] || {}).i, (prog[d.id] || {}).q) }]),
        { t: 'الإجمالي', r: 1, h: d => money(d.total) }, { t: 'الحالة', h: soBadge }], docs, { empty: kind === 'quote' ? 'لا توجد عروض أسعار' : 'لا توجد أوامر بيع', onRow: true })}`;
    bindRows(page, docs, d => location.hash = `${K.h}/${d.id}`);
  };
}
VIEWS['#/quotes'] = soList('quote'); VIEWS['#/orders'] = soList('order');

/* ----- create / edit ----- */
async function soForm(page, kind, id, q) {
  const preParty = q && q.get('party'), lead = q && q.get('lead');
  const K = SK[kind];
  if (!can('sales')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const L = await soLookups();
  if (!L.parties.length) { page.innerHTML = '<div class="note">أضف عميلاً أولاً. <a href="#/parties/customer">العملاء</a></div>'; return; }
  let doc = null, lines = [{}];
  if (id) {
    [[doc]] = await Promise.all([db.get('sales_orders', { id: 'eq.' + id })]);
    if (!doc) throw new Error('المستند غير موجود');
    lines = (await db.get('sales_order_lines', { order_id: 'eq.' + id, order: 'id' })).map(l => ({ item: l.item_id, qty: +l.qty, price: +l.unit_price, disc: +l.disc_pct, vat: +l.vat_rate, desc: l.description || '' }));
  }
  const back = id ? `${K.h}/${id}` : K.h;
  const whf = await whField(doc && doc.warehouse_id, 'يُصرف من مستودع');
  page.innerHTML = `<div class="head"><div><a href="${back}" class="small">← ${K.t}</a><h1>${id ? 'تعديل ' + K.one + ' <span class="num">' + esc(doc.no) + '</span>' : K.newT}</h1></div></div><form id="sf" class="card" novalidate>
    <div class="fg">${field('العميل', `<select name="party">${L.parties.filter(p => p.active !== false || (doc && doc.party_id === p.id)).map(p => opt(p.id, p.name, doc ? doc.party_id : preParty)).join('')}</select>`)}${field('التاريخ', `<input type="date" name="date" value="${doc ? doc.date : today()}" max="${today()}">`)}
      ${kind === 'quote' ? field('صالح حتى', `<input type="date" name="valid_until" value="${doc ? doc.valid_until : new Date(Date.now() + 14 * 864e5).toISOString().slice(0, 10)}">`) : ''}
      ${whf}${field('ملاحظات', inp('note', doc && doc.note), 'wide')}${field('الشروط والأحكام (تظهر في المطبوع)', `<textarea name="terms" rows="2">${esc(doc && doc.terms || '')}</textarea>`, 'wide')}</div>
    <div style="height:14px"></div><div class="tw"><table class="lines"><thead><tr><th>الصنف</th><th>الوصف</th><th>الكمية</th><th>السعر</th><th>الخصم %</th><th>الضريبة</th><th class="r">المبلغ</th><th></th></tr></thead><tbody id="lb"></tbody>
    <tfoot><tr><td colspan="6">الإجمالي قبل الخصم</td><td class="r num" id="tg">0.00</td><td></td></tr><tr><td colspan="6">الخصم</td><td class="r num" id="td">0.00</td><td></td></tr><tr><td colspan="6">الإجمالي قبل الضريبة</td><td class="r num" id="ts">0.00</td><td></td></tr><tr><td colspan="6">ضريبة القيمة المضافة</td><td class="r num" id="tv">0.00</td><td></td></tr><tr><td colspan="6">الإجمالي</td><td class="r num" id="tt">0.00</td><td></td></tr></tfoot></table></div>
    <div class="row" style="margin-top:10px"><button type="button" class="btn sm" id="al">+ بند</button></div><div id="serr"></div>
    <div class="row" style="margin-top:14px"><button class="btn pri" id="ss">حفظ</button><a class="btn" href="${back}">إلغاء</a></div></form>`;
  const itemOpts = L.items.filter(i => i.active !== false || lines.some(l => l.item === i.id)).map(i => opt(i.id, i.code + ' — ' + i.name)).join('');
  const draw = () => {
    $('#lb', page).innerHTML = lines.map((l, i) => `<tr data-i="${i}"><td style="min-width:200px"><select data-f="item"><option value="">—</option>${itemOpts}</select></td><td><input data-f="desc" value="${esc(l.desc || '')}" style="min-width:140px"></td>
      <td><input data-f="qty" type="number" step="0.001" min="0" value="${esc(l.qty == null ? 1 : l.qty)}" style="width:80px"></td><td><input data-f="price" type="number" step="0.01" min="0" value="${esc(l.price == null ? '' : l.price)}" style="width:110px"></td>
      <td><input data-f="disc" type="number" step="0.01" min="0" max="100" value="${esc(l.disc || 0)}" style="width:75px"></td><td><select data-f="vat" style="width:80px">${opt(15, '15%', l.vat == null ? 15 : l.vat)}${opt(0, '0%', l.vat)}</select></td>
      <td class="r num" data-amt></td><td><button type="button" class="btn sm" data-rm aria-label="حذف البند">×</button></td></tr>`).join('');
    $$('tr', $('#lb', page)).forEach(tr => { $('[data-f=item]', tr).value = lines[+tr.dataset.i].item || ''; });
    calc();
  };
  const calc = () => { let g = 0, s = 0, v = 0; $$('tr', $('#lb', page)).forEach(tr => { const l = lines[+tr.dataset.i], q = n0(l.qty == null ? 1 : l.qty), a = r2(q * soNet(l.price, l.disc)), t = r2(a * n0(l.vat == null ? 15 : l.vat) / 100);
    g += r2(q * n0(l.price)); s += a; v += t; $('[data-amt]', tr).textContent = money(a); });
    $('#tg', page).textContent = money(g); $('#td', page).textContent = money(g - s); $('#ts', page).textContent = money(s); $('#tv', page).textContent = money(v); $('#tt', page).textContent = money(s + v); };
  $('#lb', page).addEventListener('input', e => { const tr = e.target.closest('tr'); if (!tr) return; const l = lines[+tr.dataset.i], f = e.target.dataset.f; l[f] = e.target.value;
    if (f === 'item') { const it = L.im[l.item]; if (it && !l.price) { l.price = it.sale_price; $('[data-f=price]', tr).value = it.sale_price; } if (it) { l.vat = n0(it.vat_rate == null ? 15 : it.vat_rate); $('[data-f=vat]', tr).value = String(l.vat); } } calc(); });
  $('#lb', page).addEventListener('click', e => { if (e.target.matches('[data-rm]')) { lines.splice(+e.target.closest('tr').dataset.i, 1); if (!lines.length) lines.push({}); draw(); } });
  $('#al', page).onclick = () => { lines.push({}); draw(); };
  draw();
  $('#sf', page).onsubmit = async e => {
    e.preventDefault(); const f = formData(e.target);
    const ls = lines.filter(l => l.item).map(l => ({ item: l.item, qty: +(l.qty == null ? 1 : l.qty), price: +l.price, disc: +(l.disc || 0), vat: +(l.vat == null ? 15 : l.vat), desc: blank((l.desc || '').trim()) }));
    if (!ls.length) return showErr($('#serr', page), 'أضف بنداً واحداً على الأقل');
    if (ls.some(l => !(l.qty > 0) || !(l.price >= 0) || isNaN(l.price))) return showErr($('#serr', page), 'تحقق من الكميات والأسعار');
    if (ls.some(l => l.disc < 0 || l.disc > 100)) return showErr($('#serr', page), 'نسبة الخصم بين 0 و 100');
    const d = { kind, party: f.party, date: f.date, note: blank(f.note), terms: blank(f.terms), warehouse: blank(f.warehouse), lines: ls }; if (id) d.id = id; if (kind === 'quote') d.valid_until = f.valid_until;
    try { await busy($('#ss', page), async () => { const nid = await db.rpc('sales_doc_save_wh', { p_company: S.cid, p_doc: d }); if (lead && kind === 'quote' && !id) await db.rpc('crm_link_quote', { p_lead: lead, p_quote: nid }).catch(() => {}); toast('تم الحفظ'); location.hash = `${K.h}/${nid}`; }); } catch (er) { showErr($('#serr', page), er); }
  };
}

/* ----- detail ----- */
async function soView(page, kind, id) {
  const K = SK[kind];
  const [[doc], lines, L] = await Promise.all([db.get('sales_orders', { id: 'eq.' + id }), db.get('sales_order_lines', { order_id: 'eq.' + id, order: 'id' }), soLookups()]);
  if (!doc || doc.kind !== kind) throw new Error('المستند غير موجود');
  const party = L.pm[doc.party_id], wmm = await whMap(), whTxt = Object.keys(wmm).length > 1 && doc.warehouse_id ? ' · ' + esc(whName(wmm[doc.warehouse_id])) : '';
  const [linked, dns, invs] = await Promise.all([
    kind === 'quote' ? db.get('sales_orders', { quote_id: 'eq.' + id, select: 'id,no' }) : doc.quote_id && can('sales') ? db.get('sales_orders', { id: 'eq.' + doc.quote_id, select: 'id,no' }) : [],
    kind === 'order' ? db.get('delivery_notes', { order_id: 'eq.' + id, order: 'date,no' }) : [],
    kind === 'order' && can('sales') ? db.get('sales_invoices', { order_id: 'eq.' + id, order: 'date,no' }) : []]);
  const open = doc.status === 'open', touched = lines.some(l => n0(l.delivered) || n0(l.invoiced));
  const leftDel = lines.some(l => n0(l.qty) > n0(l.delivered)), leftInv = lines.some(l => n0(l.qty) > n0(l.invoiced));
  const btns = [];
  if (kind === 'quote' && can('sales')) {
    if (open) btns.push('<a class="btn" id="qed">تعديل</a>', '<button class="btn" id="qac">قبول العميل</button>', '<button class="btn" id="qrj">رفض</button>');
    if ((open || doc.status === 'accepted') && !soExpired(doc)) btns.push('<button class="btn pri" id="qcv">تحويل إلى أمر بيع</button>');
  }
  if (kind === 'order' && leftDel && (open || (doc.status === 'closed' && !doc.reason)) && (can('sales') || can('stock'))) btns.push('<button class="btn" id="odl">إشعار تسليم</button>');
  if (kind === 'order' && open) {
    if (leftInv && can('sales')) btns.push('<button class="btn pri" id="oin">إصدار فاتورة</button>');
    if (can('sales') && !touched) btns.push('<a class="btn" id="oed">تعديل</a>');
    if (can('sales')) btns.push('<button class="btn danger" id="ocn">' + (touched ? 'إغلاق الباقي' : 'إلغاء الأمر') + '</button>');
  }
  btns.push('<button class="btn" id="sprint">طباعة</button>');
  const nm = l => esc((L.im[l.item_id] || {}).name || '') + (l.description ? `<div class="small muted">${esc(l.description)}</div>` : '');
  page.innerHTML = `<div class="head"><div><a href="${K.h}" class="small">← ${K.t}</a><h1>${K.one} <span class="num">${esc(doc.no)}</span> ${soBadge(doc)}</h1>
      <div class="muted">${esc(party ? party.name : '')} · ${fdate(doc.date)}${kind === 'quote' ? ' · صالح حتى ' + fdate(doc.valid_until) : ''}${whTxt}${linked.length ? ` · ${kind === 'quote' ? 'أمر البيع' : 'من عرض السعر'} <a href="${kind === 'quote' ? '#/orders/' : '#/quotes/'}${linked[0].id}" class="num">${esc(linked[0].no)}</a>` : ''}</div></div>
      <div class="row">${btns.join('')}</div></div>
    <div class="card">${tbl([{ t: 'البند', h: nm }, { t: 'الكمية', r: 1, h: l => qtyTxt(l.qty) }, ...(kind === 'order' ? [{ t: 'المُسلَّم', r: 1, h: l => qtyTxt(l.delivered) }, { t: 'المُفوتر', r: 1, h: l => qtyTxt(l.invoiced) }] : []),
      { t: 'السعر', r: 1, h: l => money(l.unit_price) }, { t: 'الخصم', r: 1, h: l => n0(l.disc_pct) ? +l.disc_pct + '%' : '—' }, { t: 'الضريبة', r: 1, h: l => +l.vat_rate + '%' }, { t: 'المبلغ', r: 1, h: l => money(l.amount) }], lines,
      { foot: `<td colspan="${kind === 'order' ? 7 : 5}">${n0(doc.discount) ? 'الخصم ' + money(doc.discount) + ' · ' : ''}الإجمالي قبل الضريبة / الضريبة / الإجمالي</td><td class="r num">${money(doc.subtotal)} / ${money(doc.vat)} / <b>${money(doc.total)}</b></td>` })}
      ${doc.terms ? `<p class="small"><b>الشروط:</b> ${esc(doc.terms)}</p>` : ''}${doc.note ? `<p class="muted small">${esc(doc.note)}</p>` : ''}${doc.reason ? `<p class="small">السبب: ${esc(doc.reason)}</p>` : ''}</div>
    ${dns.length ? '<h2>إشعارات التسليم</h2>' + tbl([{ t: 'الرقم', h: n => `<span class="num">${esc(n.no)}</span>` }, { t: 'التاريخ', h: n => fdate(n.date) }, { t: 'المستلم', h: n => esc(n.received_by || '—') }, { t: 'الحالة', h: n => badge(n.status) }], dns, { onRow: true }) : ''}
    ${invs.length ? '<div style="height:12px"></div><h2>الفواتير</h2>' + tbl([{ t: 'الرقم', h: v => `<span class="num">${esc(v.no)}</span>` }, { t: 'التاريخ', h: v => fdate(v.date) }, { t: 'الإجمالي', r: 1, h: v => money(v.total) }, { t: 'الحالة', h: v => badge(v.status) }], invs, { onRow: true }) : ''}`;
  // the two lists share bindRows' data-row index, so bind each table separately
  const tbs = $$('table', page).slice(1);
  if (dns.length) bindRows(tbs[0].parentElement, dns, n => location.hash = '#/deliveries/' + n.id);
  if (invs.length) bindRows(tbs[dns.length ? 1 : 0].parentElement, invs, v => location.hash = '#/sales/' + v.id);
  const on = (s, fn) => { const b = $(s, page); if (b) b.onclick = fn; };
  on('#sprint', () => { const w = document.createElement('div'); w.innerHTML = salesSheet({ kind, doc, lines, party, im: L.im }); printWith(w.firstElementChild, '@page{size:A4 portrait;margin:12mm}'); });
  on('#qed', () => location.hash = `${K.h}/${id}/edit`); on('#oed', () => location.hash = `${K.h}/${id}/edit`);
  on('#qac', async () => { await db.rpc('quote_decide', { p_id: id, p_accept: true, p_reason: null }); toast('سُجّل قبول العميل'); route(); });
  on('#qrj', () => modal('رفض العرض', field('السبب', '<textarea name="r" rows="2" required></textarea>'), { ok: 'رفض', onOk: async f => { await db.rpc('quote_decide', { p_id: id, p_accept: false, p_reason: f.r }); toast('سُجّل الرفض'); route(); } }));
  on('#qcv', async e => { await busy(e.target, async () => { const nid = await db.rpc('quote_to_order', { p_id: id }); toast('أُنشئ أمر البيع'); location.hash = '#/orders/' + nid; }); });
  on('#ocn', () => modal(touched ? 'إغلاق باقي الأمر' : 'إلغاء الأمر', field('السبب', '<textarea name="r" rows="2" required></textarea>') + (touched ? '<p class="muted small">يبقى ما سُلّم وفُوتر كما هو، ويُغلق الباقي.</p>' : ''), {
    ok: touched ? 'إغلاق' : 'إلغاء الأمر', onOk: async f => { await db.rpc('order_cancel', { p_id: id, p_reason: f.r }); toast('تم'); route(); } }));
  const qtyRows = (key, max) => `<div class="tw"><table class="lines"><thead><tr><th>البند</th><th>المتبقي</th><th>الكمية</th></tr></thead><tbody>${lines.filter(l => max(l) > 0).map(l => `<tr><td>${esc((L.im[l.item_id] || {}).name || '')}${key === 'd' && (L.im[l.item_id] || {}).track_serial ? `<textarea name="ds_${l.id}" rows="2" dir="ltr" placeholder="${esc(tr('الأرقام التسلسلية — رقم في كل سطر'))}" style="display:block;min-width:200px;margin-top:4px"></textarea>` : ''}</td><td class="num">${qtyTxt(max(l))}</td><td><input name="${key}_${l.id}" type="number" min="0" step="0.001" max="${max(l)}" value="${max(l)}" style="width:110px"></td></tr>`).join('')}</tbody></table></div><div style="height:10px"></div>`;
  const pick = (f, key) => lines.map(l => ({ line: l.id, qty: +(f[key + '_' + l.id] || 0), serials: snSplit(f[key + 's_' + l.id]) })).filter(x => x.qty > 0);
  on('#odl', () => modal('إشعار تسليم', qtyRows('d', l => n0(l.qty) - n0(l.delivered)) + `<div class="fg">${field('تاريخ التسليم', `<input type="date" name="date" value="${today()}" max="${today()}">`)}${field('اسم المستلم', inp('received_by'))}${field('ملاحظات', inp('note'), 'wide')}</div>`, {
    wide: true, ok: 'إصدار الإشعار', onOk: async f => { const ls = pick(f, 'd'); if (!ls.length) throw new Error('أدخل كمية تسليم لبند واحد على الأقل');
      const nid = await db.rpc('delivery_post_sn', { p_order: id, p_doc: { date: f.date, received_by: blank(f.received_by), note: blank(f.note), lines: ls } }); toast('صدر إشعار التسليم'); location.hash = '#/deliveries/' + nid; } }));
  on('#oin', () => modal('إصدار فاتورة ضريبية من الأمر', qtyRows('i', l => n0(l.qty) - n0(l.invoiced)) + `<div class="fg">${field('تاريخ الفاتورة', `<input type="date" name="date" value="${today()}" max="${today()}">`)}${field('تاريخ الاستحقاق', `<input type="date" name="due" value="${addDays(today(), n0(party && party.terms_days))}">`)}</div><p class="muted small">تُرحّل الفاتورة بسعر الأمر بعد الخصم، ويُخصم المخزون وتُقيد تكلفة المبيعات.</p>`, {
    wide: true, ok: 'ترحيل الفاتورة', onOk: async f => { const ls = pick(f, 'i'); if (!ls.length) throw new Error('أدخل كمية لبند واحد على الأقل');
      const iid = await db.rpc('order_invoice', { p_order: id, p_doc: { date: f.date, due: f.due || f.date, lines: ls } }); toast('رُحّلت الفاتورة'); location.hash = '#/sales/' + iid; } }));
}

/* ----- delivery notes ----- */
VIEWS['#/deliveries'] = async (page, arg) => {
  if (arg) return dnView(page, arg);
  const [dns, orders, L] = await Promise.all([db.get('delivery_notes', Object.assign(C(), { order: 'date.desc,no.desc', limit: 300 })), db.get('sales_orders', Object.assign(C(), { kind: 'eq.order', select: 'id,no' })), soLookups()]);
  const om = {}; orders.forEach(o => om[o.id] = o.no);
  page.innerHTML = `<div class="head"><div><h1>إشعارات التسليم</h1><div class="muted small">تُصدر من أمر البيع عند خروج البضاعة للعميل</div></div><a class="btn" href="#/orders">أوامر البيع</a></div>
    ${tbl([{ t: 'الرقم', h: n => `<span class="num">${esc(n.no)}</span>` }, { t: 'التاريخ', h: n => fdate(n.date) }, { t: 'أمر البيع', h: n => `<span class="num">${esc(om[n.order_id] || '')}</span>` }, { t: 'العميل', h: n => esc((L.pm[n.party_id] || {}).name || '—') }, { t: 'المستلم', h: n => esc(n.received_by || '—') }, { t: 'الحالة', h: n => badge(n.status) }],
      dns, { empty: 'لا توجد إشعارات تسليم', onRow: true })}`;
  bindRows(page, dns, n => location.hash = '#/deliveries/' + n.id);
};
async function dnView(page, id) {
  const [[n], lines, L] = await Promise.all([db.get('delivery_notes', { id: 'eq.' + id }), db.get('delivery_note_lines', { note_id: 'eq.' + id, order: 'id' }), soLookups()]);
  if (!n) throw new Error('الإشعار غير موجود');
  const [[o]] = await Promise.all([db.get('sales_orders', { id: 'eq.' + n.order_id, select: 'id,no,date' })]);
  const party = L.pm[n.party_id];
  page.innerHTML = `<div class="head"><div><a href="#/deliveries" class="small">← إشعارات التسليم</a><h1>إشعار تسليم <span class="num">${esc(n.no)}</span> ${badge(n.status)}</h1>
      <div class="muted">${esc(party ? party.name : '')} · ${fdate(n.date)} · أمر البيع <a href="#/orders/${n.order_id}" class="num">${esc(o ? o.no : '')}</a></div></div>
      <div class="row">${n.status === 'posted' && (can('sales') || can('stock')) ? '<button class="btn danger" id="dvd">إلغاء الإشعار</button>' : ''}<button class="btn" id="dprint">طباعة</button></div></div>
    <div class="card">${tbl([{ t: 'الصنف', h: l => esc(((L.im[l.item_id] || {}).code || '') + ' — ' + ((L.im[l.item_id] || {}).name || '')) }, { t: 'الوحدة', h: l => esc((L.im[l.item_id] || {}).unit || '—') }, { t: 'الكمية المسلّمة', r: 1, h: l => qtyTxt(l.qty) }], lines)}
      ${n.received_by ? `<p>المستلم: <b>${esc(n.received_by)}</b></p>` : ''}${n.note ? `<p class="muted small">${esc(n.note)}</p>` : ''}${n.void_reason ? `<p class="small">سبب الإلغاء: ${esc(n.void_reason)}</p>` : ''}</div>`;
  $('#dprint', page).onclick = () => { const w = document.createElement('div'); w.innerHTML = salesSheet({ kind: 'dn', doc: n, lines, party, im: L.im, order: o }); printWith(w.firstElementChild, '@page{size:A4 portrait;margin:12mm}'); };
  if ($('#dvd', page)) $('#dvd', page).onclick = () => modal('إلغاء إشعار التسليم', field('السبب', '<textarea name="r" rows="2" required></textarea>') + '<p class="muted small">تعود الكميات إلى المتبقي للتسليم في أمر البيع.</p>', {
    ok: 'إلغاء الإشعار', onOk: async f => { await db.rpc('delivery_void', { p_id: id, p_reason: f.r }); toast('أُلغي الإشعار'); route(); } });
}

/* ----- bilingual printouts: quotation, sales order, delivery note ----- */
function salesSheet({ kind, doc, lines, party, im, order }) {
  const c = S.company || {}, dn = kind === 'dn';
  const enOf = s => { const t = trTo(s); return t !== s ? t : ''; };
  const two = (ar, en) => `<div>${esc(ar)}</div>${en && en !== ar ? `<div class="iv-en" dir="ltr">${esc(en)}</div>` : ''}`;
  const L = (ar, en) => `<div>${ar}</div><div class="iv-en" dir="ltr">${en}</div>`;
  const title = { quote: ['عرض سعر', 'Quotation'], order: ['أمر بيع', 'Sales Order'], dn: ['إشعار تسليم', 'Delivery Note'] }[kind];
  const itm = l => { const it = im[l.item_id] || {}; return two(it.name || '', it.name_en || enOf(it.name || '')) + (l.description ? `<div class="small">${esc(l.description)}</div>` : ''); };
  const row = (ar, en, v, cls) => `<tr${cls ? ` class="${cls}"` : ''}><td>${L(esc(ar), esc(en))}</td><td class="num r">${v}</td></tr>`;
  const head = `<div class="iv-head"><div class="ph-brand">${c.logo ? `<img class="ph-logo" src="${esc(c.logo)}" alt="">` : ''}<div><div class="ph-co">${esc(c.name || '')}</div>${c.name_en ? `<div class="iv-en" dir="ltr"><b>${esc(c.name_en)}</b></div>` : ''}
      <div class="ph-ids">${c.vat_no ? 'الرقم الضريبي VAT No. <span class="num">' + esc(c.vat_no) + '</span>' : ''}${c.cr_no ? ' · س.ت C.R. <span class="num">' + esc(c.cr_no) + '</span>' : ''}</div>${c.address ? `<div class="ph-ids">${esc(c.address)}</div>` : ''}</div></div>
      <div class="iv-title">${L(title[0], title[1])}</div></div>`;
  const meta = `<table class="iv-meta"><tbody>
      <tr><td>${L('الرقم', 'No.')}</td><td class="num">${esc(doc.no)}</td><td>${L('التاريخ', 'Date')}</td><td class="num">${esc(fdate(doc.date))}</td></tr>
      <tr><td>${L('العميل', 'Customer')}</td><td>${two(party ? party.name : '', party ? (party.name_en || enOf(party.name)) : '')}</td>${kind === 'quote' ? `<td>${L('صالح حتى', 'Valid until')}</td><td class="num">${esc(fdate(doc.valid_until))}</td>` : dn ? `<td>${L('أمر البيع', 'Sales order')}</td><td class="num">${esc(order ? order.no : '')}</td>` : '<td></td><td></td>'}</tr>
      ${party && party.vat_no ? `<tr><td>${L('الرقم الضريبي للعميل', "Customer's VAT No.")}</td><td class="num" colspan="3">${esc(party.vat_no)}</td></tr>` : ''}
      ${party && addrLine(party) ? `<tr><td>${L('عنوان العميل', "Customer's address")}</td><td colspan="3">${esc(addrLine(party))}</td></tr>` : ''}
      ${doc.status === 'void' || doc.status === 'cancelled' ? `<tr><td colspan="4"><b>${L('ملغى', 'VOID')}</b></td></tr>` : ''}</tbody></table>`;
  let body;
  if (dn) body = `<table class="iv-lines"><thead><tr><th>${L('الصنف', 'Item')}</th><th>${L('الوحدة', 'Unit')}</th><th class="r">${L('الكمية المسلّمة', 'Qty delivered')}</th></tr></thead>
      <tbody>${lines.map(l => `<tr><td>${itm(l)}</td><td>${esc((im[l.item_id] || {}).unit || '')}</td><td class="num r">${qtyTxt(l.qty)}</td></tr>`).join('')}</tbody></table>
    <table class="iv-meta"><tbody><tr><td>${L('اسم المستلم', 'Received by')}</td><td>${esc(doc.received_by || '')}</td><td>${L('التوقيع', 'Signature')}</td><td style="height:16mm"></td></tr>
      <tr><td>${L('سلّمها', 'Delivered by')}</td><td></td><td>${L('التاريخ', 'Date')}</td><td></td></tr></tbody></table>`;
  else body = `<table class="iv-lines"><thead><tr><th>${L('البند', 'Item')}</th><th class="r">${L('الكمية', 'Qty')}</th><th class="r">${L('سعر الوحدة', 'Unit price')}</th><th class="r">${L('الخصم', 'Discount')}</th><th class="r">${L('المبلغ قبل الضريبة', 'Taxable amount')}</th><th class="r">${L('نسبة الضريبة', 'VAT rate')}</th><th class="r">${L('الإجمالي شامل الضريبة', 'Total incl. VAT')}</th></tr></thead>
      <tbody>${lines.map(l => `<tr><td>${itm(l)}</td><td class="num r">${qtyTxt(l.qty)}</td><td class="num r">${money(l.unit_price)}</td><td class="num r">${n0(l.disc_pct) ? +l.disc_pct + '%' : '—'}</td><td class="num r">${money(l.amount)}</td><td class="num r">${n0(l.vat_rate)}%</td><td class="num r">${money(n0(l.amount) + n0(l.vat))}</td></tr>`).join('')}</tbody></table>
    <table class="iv-tot"><tbody>${n0(doc.discount) ? row('الإجمالي قبل الخصم', 'Gross total', money(n0(doc.subtotal) + n0(doc.discount))) + row('الخصم', 'Discount', money(doc.discount)) : ''}${row('الإجمالي قبل الضريبة', 'Total excl. VAT', money(doc.subtotal))}${row('ضريبة القيمة المضافة', 'VAT', money(doc.vat))}
      <tr class="iv-grand"><td>${L('الإجمالي', 'Total')}</td><td class="num r">${money(doc.total)} <span class="small">SAR</span></td></tr></tbody></table>
    ${doc.terms ? `<p class="small"><b>${L('الشروط والأحكام', 'Terms and conditions')}</b>${esc(doc.terms)}</p>` : ''}
    ${kind === 'quote' ? `<p class="small">${L('هذا عرض سعر وليس فاتورة ضريبية.', 'This is a quotation, not a tax invoice.')}</p>` : ''}`;
  return `<div class="iv" dir="rtl" data-nt>${head}${meta}${body}${doc.note ? `<p class="small">${esc(doc.note)}</p>` : ''}
    <div class="iv-foot">${L('صدر من نظام وعد · تاريخ الطباعة <span class="num">' + esc(today()) + '</span>', 'Issued by Waad · printed <span class="num">' + esc(today()) + '</span>')}</div></div>`;
}
