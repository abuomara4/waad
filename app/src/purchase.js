'use strict';
/* ===== purchase cycle: purchase requests → purchase orders → goods receipts → supplier bills ===== */
const poBadge = o => { const m = { open: ['قيد التنفيذ', 'wait'], closed: [o.reason ? 'مغلق' : 'مكتمل', o.reason ? '' : 'ok'], cancelled: ['ملغى', ''] }[o.status] || [o.status, ''];
  return `<span class="badge ${m[1]}">${esc(m[0])}</span>`; };
async function poLookups() {
  const [parties, items, acc] = await Promise.all([can('purch') ? db.get('parties', Object.assign(C(), { kind: 'eq.supplier', order: 'name' })) : [], db.get('items', Object.assign(C(), { order: 'code' })), can('purch') ? accounts() : []]);
  const pm = {}, im = {}, am = {}; parties.forEach(p => pm[p.id] = p); items.forEach(i => im[i.id] = i); acc.forEach(a => am[a.code] = a);
  const expAcc = acc.filter(a => !a.is_header && (a.type === 'exp' || a.type === 'asset') && !['1110', '1120', '1200', '1300', '1400'].includes(a.code) && a.parent_code !== '1100');
  return { parties, items, pm, im, am, expAcc };
}
const poLineName = (L, l) => l.item_id ? ((L.im[l.item_id] || {}).name || '') : l.account_code + ' — ' + ((L.am[l.account_code] || {}).name || '');
const poStock = (L, l) => !!l.item_id && (L.im[l.item_id] || {}).type === 'stock';
const poBillCap = (L, l) => r2((poStock(L, l) ? n0(l.received) : n0(l.qty)) - n0(l.billed));

/* ----- approved purchase requests waiting for a PO ----- */
VIEWS['#/purchreq'] = async page => {
  if (!can('purch')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const rows = await db.rpc('purchase_requests', { p_company: S.cid });
  const nm = r => (LANG === 'en' && r.employee_en) || r.employee;
  page.innerHTML = `<div class="head"><div><h1>طلبات الشراء المعتمدة</h1><div class="muted small">يرفعها الموظف من «طلباتي» وتمر على مديره ثم المالية ثم المدير العام، ثم يصدر منها أمر الشراء هنا</div></div><a class="btn" href="#/porders/new">أمر شراء مباشر</a></div>
    ${tbl([{ t: 'التاريخ', h: r => fdate(r.created_at) }, { t: 'الموظف', h: r => esc(nm(r)) + (r.dept ? `<div class="small muted">${esc(r.dept)}</div>` : '') },
      { t: 'البنود', h: r => (r.lines || []).map(l => `<div class="small">${esc(l.desc)} × <span class="num">${+l.qty}</span></div>`).join('') }, { t: 'مطلوب بتاريخ', h: r => fdate(r.needed_by) },
      { t: 'التقديري', r: 1, h: r => money(r.amount) }, { t: 'أمر الشراء', h: r => r.po_id ? `<a href="#/porders/${r.po_id}" class="num">${esc(r.po_no)}</a>` : `<a class="btn sm pri" href="#/porders/new?req=${r.id}">إنشاء أمر شراء</a>` }],
      rows, { empty: 'لا توجد طلبات شراء معتمدة' })}`;
};

/* ----- purchase orders ----- */
VIEWS['#/porders'] = async (page, arg, q) => {
  if (arg === 'new') return poForm(page, null, q && q.get('req'), q);
  if (arg && arg.endsWith('/edit')) return poForm(page, arg.split('/')[0]);
  if (arg) return poView(page, arg);
  const [docs, L] = await Promise.all([db.get('purchase_orders', Object.assign(C(), { order: 'date.desc,no.desc', limit: 300 })), poLookups()]);
  const prog = {};
  if (docs.length) (await db.get('purchase_order_lines', { order_id: 'in.(' + docs.map(d => d.id).join(',') + ')', select: 'order_id,item_id,qty,received,billed' }))
    .forEach(l => { const p = prog[l.order_id] = prog[l.order_id] || { q: 0, r: 0, rq: 0, b: 0 }; p.q += n0(l.qty); p.b += n0(l.billed); if (l.item_id) { p.rq += n0(l.qty); p.r += n0(l.received); } });
  const pct = (a, b) => b ? Math.round(a / b * 100) + '%' : '—';
  page.innerHTML = `<div class="head"><div><h1>أوامر الشراء</h1><div class="muted small">من الأمر يُسجَّل استلام البضاعة ثم فاتورة المورد، ولا تُفوتر بضاعة لم تُستلم</div></div>${can('purch') ? '<a class="btn pri" href="#/porders/new">أمر شراء جديد</a>' : ''}</div>
    ${tbl([{ t: 'الرقم', h: d => `<span class="num">${esc(d.no)}</span>` }, { t: 'التاريخ', h: d => fdate(d.date) }, { t: 'المورد', h: d => esc((L.pm[d.party_id] || {}).name || '—') }, { t: 'التوريد المتوقع', h: d => fdate(d.expected_date) },
      { t: 'الاستلام', h: d => pct((prog[d.id] || {}).r, (prog[d.id] || {}).rq) }, { t: 'الفوترة', h: d => pct((prog[d.id] || {}).b, (prog[d.id] || {}).q) },
      { t: 'الإجمالي', r: 1, h: d => money(d.total) }, { t: 'الحالة', h: poBadge }], docs, { empty: 'لا توجد أوامر شراء', onRow: true })}`;
  bindRows(page, docs, d => location.hash = '#/porders/' + d.id);
};

async function poForm(page, id, reqId, q) {
  if (!can('purch')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const L = await poLookups();
  if (!L.parties.length) { page.innerHTML = '<div class="note">أضف مورداً أولاً. <a href="#/parties/supplier">الموردون</a></div>'; return; }
  let doc = null, lines = [{}], req = null;
  if (id) {
    [doc] = await db.get('purchase_orders', { id: 'eq.' + id });
    if (!doc) throw new Error('الأمر غير موجود');
    reqId = doc.request_id;
    lines = (await db.get('purchase_order_lines', { order_id: 'eq.' + id, order: 'id' })).map(l => ({ what: l.item_id ? 'i:' + l.item_id : 'a:' + l.account_code, qty: +l.qty, price: +l.unit_price, vat: +l.vat_rate, desc: l.description || '' }));
  }
  if (reqId) { req = (await db.rpc('purchase_requests', { p_company: S.cid })).find(r => r.id === reqId) || null;
    if (req && !id) lines = (req.lines || []).map(l => ({ what: '', desc: l.desc, qty: +l.qty, price: +l.price || '' })); }
  let supSel = doc && doc.party_id;
  if (!id && q && q.get('items')) { supSel = q.get('sup') || null;   // from «إعادة الطلب»
    lines = q.get('items').split(',').map(x => x.split(':')).filter(x => L.im[x[0]]).map(([it, qt, pr]) => ({ what: 'i:' + it, qty: +qt || 1, price: pr === '' ? '' : +pr })); }
  const back = id ? '#/porders/' + id : reqId ? '#/purchreq' : q && q.get('items') ? '#/reorder' : '#/porders';
  const whf = await whField(doc && doc.warehouse_id, 'يُستلم في مستودع');
  page.innerHTML = `<div class="head"><div><a href="${back}" class="small">← أوامر الشراء</a><h1>${id ? 'تعديل أمر الشراء <span class="num">' + esc(doc.no) + '</span>' : 'أمر شراء جديد'}</h1>
      ${req ? `<div class="muted small">من طلب شراء ${esc((LANG === 'en' && req.employee_en) || req.employee)} · ${fdate(req.created_at)}${req.note ? ' · ' + esc(req.note) : ''}</div>` : ''}</div></div><form id="pf" class="card" novalidate>
    <div class="fg">${field('المورد', `<select name="party">${L.parties.filter(p => p.active !== false || p.id === supSel).map(p => opt(p.id, p.name, supSel)).join('')}</select>`)}${field('التاريخ', `<input type="date" name="date" value="${doc ? doc.date : today()}" max="${today()}">`)}
      ${field('التوريد المتوقع', `<input type="date" name="expected" value="${doc && doc.expected_date || (req && req.needed_by) || ''}">`)}
      ${whf}${field('ملاحظات', inp('note', doc && doc.note), 'wide')}${field('الشروط (تظهر في المطبوع)', `<textarea name="terms" rows="2">${esc(doc && doc.terms || '')}</textarea>`, 'wide')}</div>
    ${req && !id ? '<p class="small" style="color:var(--gold)">اختر لكل بند الصنف أو حساب المصروف، وعدّل السعر حسب عرض المورد.</p>' : ''}
    <div style="height:14px"></div><div class="tw"><table class="lines"><thead><tr><th>صنف أو حساب مصروف</th><th>الوصف</th><th>الكمية</th><th>السعر</th><th>الضريبة</th><th class="r">المبلغ</th><th></th></tr></thead><tbody id="lb"></tbody>
    <tfoot><tr><td colspan="5">الإجمالي قبل الضريبة</td><td class="r num" id="ts">0.00</td><td></td></tr><tr><td colspan="5">ضريبة القيمة المضافة</td><td class="r num" id="tv">0.00</td><td></td></tr><tr><td colspan="5">الإجمالي</td><td class="r num" id="tt">0.00</td><td></td></tr></tfoot></table></div>
    <div class="row" style="margin-top:10px"><button type="button" class="btn sm" id="al">+ بند</button></div><div id="perr"></div>
    <div class="row" style="margin-top:14px"><button class="btn pri" id="ps">حفظ</button><a class="btn" href="${back}">إلغاء</a></div></form>`;
  const opts = L.items.filter(i => i.active !== false || lines.some(l => l.what === 'i:' + i.id)).map(i => opt('i:' + i.id, i.code + ' — ' + i.name)).join('') + `<optgroup label="${esc(tr('حسابات المصروفات'))}">${L.expAcc.map(a => opt('a:' + a.code, a.code + ' — ' + a.name)).join('')}</optgroup>`;
  const draw = () => {
    $('#lb', page).innerHTML = lines.map((l, i) => `<tr data-i="${i}"><td style="min-width:210px"><select data-f="what"><option value="">—</option>${opts}</select></td><td><input data-f="desc" value="${esc(l.desc || '')}" style="min-width:140px"></td>
      <td><input data-f="qty" type="number" step="0.001" min="0" value="${esc(l.qty == null ? 1 : l.qty)}" style="width:80px"></td><td><input data-f="price" type="number" step="0.01" min="0" value="${esc(l.price == null ? '' : l.price)}" style="width:110px"></td>
      <td><select data-f="vat" style="width:80px">${opt(15, '15%', l.vat == null ? 15 : l.vat)}${opt(0, '0%', l.vat)}</select></td><td class="r num" data-amt></td><td><button type="button" class="btn sm" data-rm aria-label="حذف البند">×</button></td></tr>`).join('');
    $$('tr', $('#lb', page)).forEach(tr => { $('[data-f=what]', tr).value = lines[+tr.dataset.i].what || ''; });
    calc();
  };
  const calc = () => { let s = 0, v = 0; $$('tr', $('#lb', page)).forEach(tr => { const l = lines[+tr.dataset.i], a = r2(n0(l.qty == null ? 1 : l.qty) * n0(l.price)), t = r2(a * n0(l.vat == null ? 15 : l.vat) / 100); s += a; v += t; $('[data-amt]', tr).textContent = money(a); });
    $('#ts', page).textContent = money(s); $('#tv', page).textContent = money(v); $('#tt', page).textContent = money(s + v); };
  $('#lb', page).addEventListener('input', e => { const tr = e.target.closest('tr'); if (!tr) return; const l = lines[+tr.dataset.i]; l[e.target.dataset.f] = e.target.value;
    if (e.target.dataset.f === 'what' && l.what.startsWith('i:')) { const it = L.im[l.what.slice(2)]; if (it) { if (!l.price && it.purchase_price != null) { l.price = it.purchase_price; $('[data-f=price]', tr).value = it.purchase_price; } l.vat = n0(it.vat_rate == null ? 15 : it.vat_rate); $('[data-f=vat]', tr).value = String(l.vat); } }
    calc(); });
  $('#lb', page).addEventListener('click', e => { if (e.target.matches('[data-rm]')) { lines.splice(+e.target.closest('tr').dataset.i, 1); if (!lines.length) lines.push({}); draw(); } });
  $('#al', page).onclick = () => { lines.push({}); draw(); };
  draw();
  $('#pf', page).onsubmit = async e => {
    e.preventDefault(); const f = formData(e.target);
    if (lines.some(l => !l.what && (l.desc || '').trim())) return showErr($('#perr', page), 'اختر لكل بند الصنف أو حساب المصروف');
    const ls = lines.filter(l => l.what).map(l => { const o = { qty: +(l.qty == null ? 1 : l.qty), price: +l.price, vat: +(l.vat == null ? 15 : l.vat), desc: blank((l.desc || '').trim()) }; if (l.what.startsWith('i:')) o.item = l.what.slice(2); else o.account = l.what.slice(2); return o; });
    if (!ls.length) return showErr($('#perr', page), 'أضف بنداً واحداً على الأقل');
    if (ls.some(l => !(l.qty > 0) || !(l.price >= 0) || isNaN(l.price))) return showErr($('#perr', page), 'تحقق من الكميات والأسعار');
    const d = { party: f.party, date: f.date, expected: blank(f.expected), note: blank(f.note), terms: blank(f.terms), warehouse: blank(f.warehouse), lines: ls }; if (id) d.id = id; if (reqId) d.request = reqId;
    try { await busy($('#ps', page), async () => { const nid = await db.rpc('po_save_wh', { p_company: S.cid, p_doc: d }); toast('تم الحفظ'); location.hash = '#/porders/' + nid; }); } catch (er) { showErr($('#perr', page), er); }
  };
}

async function poView(page, id) {
  const [[doc], lines, L] = await Promise.all([db.get('purchase_orders', { id: 'eq.' + id }), db.get('purchase_order_lines', { order_id: 'eq.' + id, order: 'id' }), poLookups()]);
  if (!doc) throw new Error('الأمر غير موجود');
  const party = L.pm[doc.party_id], wmm = await whMap(), multiWh = Object.values(wmm).filter(w => w.active).length > 1, whTxt = multiWh && doc.warehouse_id ? ' · ' + esc(whName(wmm[doc.warehouse_id])) : '';
  const [grns, bills] = await Promise.all([db.get('goods_receipts', { order_id: 'eq.' + id, order: 'date,no' }), can('purch') ? db.get('purchase_bills', { order_id: 'eq.' + id, order: 'date,no' }) : []]);
  const open = doc.status === 'open', touched = lines.some(l => n0(l.received) || n0(l.billed));
  const leftRec = lines.some(l => l.item_id && n0(l.qty) > n0(l.received)), billable = lines.some(l => poBillCap(L, l) > 0);
  const btns = [];
  if (open && leftRec && (can('purch') || can('stock'))) btns.push('<button class="btn" id="prc">استلام بضاعة</button>');
  if (open && can('purch')) {
    if (billable) btns.push('<button class="btn pri" id="pbl">فاتورة المورد</button>');
    if (!touched) btns.push('<a class="btn" id="ped">تعديل</a>');
    btns.push('<button class="btn danger" id="pcn">' + (touched ? 'إغلاق الباقي' : 'إلغاء الأمر') + '</button>');
  }
  if (can('purch') && doc.status !== 'cancelled' && lines.some(l => n0(l.received) > 0 || n0(l.billed) > 0)) btns.push('<button class="btn" id="prate">' + esc(tr('تقييم المورد')) + '</button>');
  btns.push('<button class="btn" id="pprint">طباعة</button>');
  page.innerHTML = `<div class="head"><div><a href="#/porders" class="small">← أوامر الشراء</a><h1>أمر شراء <span class="num">${esc(doc.no)}</span> ${poBadge(doc)}</h1>
      <div class="muted">${esc(party ? party.name : '')} · ${fdate(doc.date)}${doc.expected_date ? ' · التوريد المتوقع ' + fdate(doc.expected_date) : ''}${whTxt}${doc.request_id && can('purch') ? ' · <a href="#/purchreq">من طلب شراء معتمد</a>' : ''}</div></div>
      <div class="row">${btns.join('')}</div></div>
    <div class="card">${tbl([{ t: 'البند', h: l => esc(poLineName(L, l)) + (l.description ? `<div class="small muted">${esc(l.description)}</div>` : '') }, { t: 'الكمية', r: 1, h: l => qtyTxt(l.qty) },
      { t: 'المُستلم', r: 1, h: l => l.item_id ? qtyTxt(l.received) : '—' }, { t: 'المُفوتر', r: 1, h: l => qtyTxt(l.billed) },
      { t: 'السعر', r: 1, h: l => money(l.unit_price) }, { t: 'الضريبة', r: 1, h: l => +l.vat_rate + '%' }, { t: 'المبلغ', r: 1, h: l => money(l.amount) }], lines,
      { foot: `<td colspan="6">الإجمالي قبل الضريبة / الضريبة / الإجمالي</td><td class="r num">${money(doc.subtotal)} / ${money(doc.vat)} / <b>${money(doc.total)}</b></td>` })}
      ${doc.terms ? `<p class="small"><b>الشروط:</b> ${esc(doc.terms)}</p>` : ''}${doc.note ? `<p class="muted small">${esc(doc.note)}</p>` : ''}${doc.reason ? `<p class="small">السبب: ${esc(doc.reason)}</p>` : ''}</div>
    ${grns.length ? '<h2>استلام البضاعة</h2><div id="tgr">' + tbl([{ t: 'الرقم', h: n => `<span class="num">${esc(n.no)}</span>` }, { t: 'التاريخ', h: n => fdate(n.date) }, { t: 'إشعار المورد', h: n => `<span class="num">${esc(n.supplier_doc || '—')}</span>` }, { t: 'الحالة', h: n => badge(n.status) }], grns, { onRow: true }) + '</div>' : ''}
    ${bills.length ? '<div style="height:12px"></div><h2>فواتير المورد</h2><div id="tbl">' + tbl([{ t: 'الرقم', h: v => `<span class="num">${esc(v.no)}</span>` }, { t: 'رقم المورد', h: v => `<span class="num">${esc(v.supplier_ref || '—')}</span>` }, { t: 'التاريخ', h: v => fdate(v.date) }, { t: 'الإجمالي', r: 1, h: v => money(v.total) }, { t: 'الحالة', h: v => badge(v.status) }], bills, { onRow: true }) + '</div>' : ''}`;
  if (grns.length) bindRows($('#tgr', page), grns, n => location.hash = '#/receipts/' + n.id);
  if (bills.length) bindRows($('#tbl', page), bills, v => location.hash = '#/purchases/' + v.id);
  const on = (s, fn) => { const b = $(s, page); if (b) b.onclick = fn; };
  on('#pprint', () => { const w = document.createElement('div'); w.innerHTML = poSheet({ kind: 'po', doc, lines, party, L }); printWith(w.firstElementChild, '@page{size:A4 portrait;margin:12mm}'); });
  on('#ped', () => location.hash = '#/porders/' + id + '/edit');
  on('#pcn', () => modal(touched ? 'إغلاق باقي الأمر' : 'إلغاء الأمر', field('السبب', '<textarea name="r" rows="2" required></textarea>') + (touched ? '<p class="muted small">يبقى ما استُلم وفُوتر كما هو، ويُغلق الباقي.</p>' : ''), {
    ok: touched ? 'إغلاق' : 'إلغاء الأمر', onOk: async f => { await db.rpc('po_cancel', { p_id: id, p_reason: f.r }); toast('تم'); route(); } }));
  const qtyRows = (key, max, hint) => `<div class="tw"><table class="lines"><thead><tr><th>البند</th><th>${esc(tr(hint))}</th><th>الكمية</th></tr></thead><tbody>${lines.filter(l => max(l) > 0).map(l => `<tr><td>${esc(poLineName(L, l))}</td><td class="num">${qtyTxt(max(l))}</td><td><input name="${key}_${l.id}" type="number" min="0" step="0.001" max="${max(l)}" value="${max(l)}" style="width:110px"></td></tr>`).join('')}</tbody></table></div><div style="height:10px"></div>`;
  const pick = (f, key) => lines.map(l => ({ line: l.id, qty: +(f[key + '_' + l.id] || 0) })).filter(x => x.qty > 0);
  const trk = l => l.item_id && (L.im[l.item_id] || {}).track_expiry;
  const recRows = () => `<div class="tw"><table class="lines"><thead><tr><th>البند</th><th>المتبقي</th><th>الكمية</th><th>${esc(tr('الدفعة / تاريخ الصلاحية'))}</th></tr></thead><tbody>${lines.filter(l => l.item_id && n0(l.qty) > n0(l.received)).map(l => { const m = r2(n0(l.qty) - n0(l.received));
    return `<tr><td>${esc(poLineName(L, l))}</td><td class="num">${qtyTxt(m)}</td><td><input name="r_${l.id}" type="number" min="0" step="0.001" max="${m}" value="${m}" style="width:100px"></td><td>${trk(l) ? `<input name="rb_${l.id}" placeholder="${esc(tr('الدفعة'))}" style="width:110px"> <input name="rx_${l.id}" type="date" required style="width:150px">` : ''}${(L.im[l.item_id] || {}).track_serial ? `<textarea name="rs_${l.id}" rows="2" dir="ltr" placeholder="${esc(tr('الأرقام التسلسلية — رقم في كل سطر'))}" style="min-width:200px"></textarea>` : ''}${!trk(l) && !(L.im[l.item_id] || {}).track_serial ? '<span class="muted">—</span>' : ''}</td></tr>`; }).join('')}</tbody></table></div><div style="height:10px"></div>`;
  on('#prc', () => modal('استلام بضاعة', recRows() + `<div class="fg">${multiWh ? field('يُستلم في مستودع', `<select name="warehouse">${Object.values(wmm).filter(w => w.active).map(w => opt(w.id, whName(w), doc.warehouse_id)).join('')}</select>`) : ''}${field('تاريخ الاستلام', `<input type="date" name="date" value="${today()}" max="${today()}">`)}${field('رقم إشعار تسليم المورد', inp('supplier_doc', '', 'dir="ltr"'))}${field('ملاحظات', inp('note'), 'wide')}</div><p class="muted small">تدخل الأصناف المخزنية المخزون بسعر الأمر فوراً، فتُباع قبل وصول فاتورة المورد.</p>`, {
    wide: true, ok: 'تسجيل الاستلام', onOk: async f => { const ls = pick(f, 'r').map(x => Object.assign(x, { batch: blank(f['rb_' + x.line]), expiry: blank(f['rx_' + x.line]), serials: snSplit(f['rs_' + x.line]) })); if (!ls.length) throw new Error('أدخل كمية مستلمة لبند واحد على الأقل');
      if (ls.some(x => trk(lines.find(l => l.id === x.line)) && !x.expiry)) throw new Error(tr('أدخل تاريخ الصلاحية للأصناف التي تتبع الصلاحية'));
      const gid = await db.rpc('grn_post_sn', { p_order: id, p_doc: { date: f.date, warehouse: blank(f.warehouse), supplier_doc: blank(f.supplier_doc), note: blank(f.note), lines: ls } }); toast('سُجّل الاستلام'); location.hash = '#/receipts/' + gid; } }));
  on('#prate', () => rateSupplier(doc, party));
  on('#pbl', () => modal('فاتورة المورد من الأمر', qtyRows('b', l => poBillCap(L, l), 'القابل للفوترة') + `<div class="fg">${field('رقم فاتورة المورد', inp('ref', '', 'dir="ltr" required'))}${field('تاريخ الفاتورة', `<input type="date" name="date" value="${today()}" max="${today()}">`)}${field('تاريخ الاستحقاق', `<input type="date" name="due" value="${addDays(today(), n0(party && party.terms_days))}">`)}</div>
      <p class="muted small">مطابقة ثلاثية: الأصناف المخزنية تُفوتر بقدر ما استُلم فقط، وبسعر الأمر.</p>`, {
    wide: true, ok: 'ترحيل الفاتورة', onOk: async f => { const ls = pick(f, 'b'); if (!ls.length) throw new Error('أدخل كمية لبند واحد على الأقل'); if (!(f.ref || '').trim()) throw new Error('اكتب رقم فاتورة المورد');
      const bid = await db.rpc('po_bill', { p_order: id, p_doc: { ref: f.ref.trim(), date: f.date, due: f.due || f.date, lines: ls } }); toast('رُحّلت الفاتورة'); location.hash = '#/purchases/' + bid; } }));
}

/* ----- goods receipts ----- */
VIEWS['#/receipts'] = async (page, arg) => {
  if (arg) return grnView(page, arg);
  const [rows, orders, L] = await Promise.all([db.get('goods_receipts', Object.assign(C(), { order: 'date.desc,no.desc', limit: 300 })), db.get('purchase_orders', Object.assign(C(), { select: 'id,no' })), poLookups()]);
  const om = {}; orders.forEach(o => om[o.id] = o.no);
  page.innerHTML = `<div class="head"><div><h1>استلام البضاعة</h1><div class="muted small">يُسجَّل من أمر الشراء عند وصول البضاعة</div></div><a class="btn" href="#/porders">أوامر الشراء</a></div>
    ${tbl([{ t: 'الرقم', h: n => `<span class="num">${esc(n.no)}</span>` }, { t: 'التاريخ', h: n => fdate(n.date) }, { t: 'أمر الشراء', h: n => `<span class="num">${esc(om[n.order_id] || '')}</span>` }, { t: 'المورد', h: n => esc((L.pm[n.party_id] || {}).name || '—') }, { t: 'إشعار المورد', h: n => `<span class="num">${esc(n.supplier_doc || '—')}</span>` }, { t: 'الحالة', h: n => badge(n.status) }],
      rows, { empty: 'لا يوجد استلام بضاعة', onRow: true })}`;
  bindRows(page, rows, n => location.hash = '#/receipts/' + n.id);
};
async function grnView(page, id) {
  const [[g], lines, L] = await Promise.all([db.get('goods_receipts', { id: 'eq.' + id }), db.get('goods_receipt_lines', { receipt_id: 'eq.' + id, order: 'id' }), poLookups()]);
  if (!g) throw new Error('الاستلام غير موجود');
  const [o] = await db.get('purchase_orders', { id: 'eq.' + g.order_id, select: 'id,no' });
  const party = L.pm[g.party_id], wmm = await whMap(), whTxt = Object.keys(wmm).length > 1 && g.warehouse_id ? ' · ' + esc(whName(wmm[g.warehouse_id])) : '';
  page.innerHTML = `<div class="head"><div><a href="#/receipts" class="small">← استلام البضاعة</a><h1>استلام بضاعة <span class="num">${esc(g.no)}</span> ${badge(g.status)}</h1>
      <div class="muted">${esc(party ? party.name : '')} · ${fdate(g.date)} · أمر الشراء <a href="#/porders/${g.order_id}" class="num">${esc(o ? o.no : '')}</a>${g.supplier_doc ? ' · إشعار المورد <span class="num">' + esc(g.supplier_doc) + '</span>' : ''}${whTxt}</div></div>
      <div class="row">${g.status === 'posted' && (can('purch') || can('stock')) ? '<button class="btn danger" id="gvd">إلغاء الاستلام</button>' : ''}<button class="btn" id="gprint">طباعة</button></div></div>
    <div class="card">${tbl([{ t: 'الصنف', h: l => esc(((L.im[l.item_id] || {}).code || '') + ' — ' + ((L.im[l.item_id] || {}).name || '')) }, { t: 'الوحدة', h: l => esc((L.im[l.item_id] || {}).unit || '—') }, { t: 'الكمية المستلمة', r: 1, h: l => qtyTxt(l.qty) }, ...(lines.some(l => l.expiry) ? [{ t: 'الدفعة / الصلاحية', h: l => l.expiry ? `<span class="num">${esc(l.batch || '—')}</span> · ${fdate(l.expiry)}` : '—' }] : [])], lines)}
      ${g.note ? `<p class="muted small">${esc(g.note)}</p>` : ''}${g.void_reason ? `<p class="small">سبب الإلغاء: ${esc(g.void_reason)}</p>` : ''}</div>`;
  $('#gprint', page).onclick = () => { const w = document.createElement('div'); w.innerHTML = poSheet({ kind: 'grn', doc: g, lines, party, L, order: o }); printWith(w.firstElementChild, '@page{size:A4 portrait;margin:12mm}'); };
  if ($('#gvd', page)) $('#gvd', page).onclick = () => modal('إلغاء الاستلام', field('السبب', '<textarea name="r" rows="2" required></textarea>') + '<p class="muted small">تخرج الكميات من المخزون ويُعكس القيد وتعود للمتبقي في أمر الشراء. لا يُلغى استلام فُوتر أو صُرف منه.</p>', {
    ok: 'إلغاء الاستلام', onOk: async f => { await db.rpc('grn_void', { p_id: id, p_reason: f.r }); toast('أُلغي الاستلام'); route(); } });
}

/* ----- bilingual printouts: purchase order, goods received note ----- */
function poSheet({ kind, doc, lines, party, L, order }) {
  const c = S.company || {}, grn = kind === 'grn';
  const enOf = s => { const t = trTo(s); return t !== s ? t : ''; };
  const two = (ar, en) => `<div>${esc(ar)}</div>${en && en !== ar ? `<div class="iv-en" dir="ltr">${esc(en)}</div>` : ''}`;
  const B = (ar, en) => `<div>${ar}</div><div class="iv-en" dir="ltr">${en}</div>`;
  const title = grn ? ['سند استلام بضاعة', 'Goods Received Note'] : ['أمر شراء', 'Purchase Order'];
  const itm = l => { if (l.item_id) { const it = L.im[l.item_id] || {}; return two(it.name || '', it.name_en || enOf(it.name || '')) + (l.description ? `<div class="small">${esc(l.description)}</div>` : ''); }
    const a = L.am[l.account_code] || {}; return two(a.name || l.account_code, a.name_en || enOf(a.name || '')) + (l.description ? `<div class="small">${esc(l.description)}</div>` : ''); };
  const row = (ar, en, v) => `<tr><td>${B(esc(ar), esc(en))}</td><td class="num r">${v}</td></tr>`;
  const head = `<div class="iv-head"><div class="ph-brand">${c.logo ? `<img class="ph-logo" src="${esc(c.logo)}" alt="">` : ''}<div><div class="ph-co">${esc(c.name || '')}</div>${c.name_en ? `<div class="iv-en" dir="ltr"><b>${esc(c.name_en)}</b></div>` : ''}
      <div class="ph-ids">${c.vat_no ? 'الرقم الضريبي VAT No. <span class="num">' + esc(c.vat_no) + '</span>' : ''}${c.cr_no ? ' · س.ت C.R. <span class="num">' + esc(c.cr_no) + '</span>' : ''}</div>${c.address ? `<div class="ph-ids">${esc(c.address)}</div>` : ''}</div></div>
      <div class="iv-title">${B(title[0], title[1])}</div></div>`;
  const meta = `<table class="iv-meta"><tbody>
      <tr><td>${B('الرقم', 'No.')}</td><td class="num">${esc(doc.no)}</td><td>${B('التاريخ', 'Date')}</td><td class="num">${esc(fdate(doc.date))}</td></tr>
      <tr><td>${B('المورد', 'Supplier')}</td><td>${two(party ? party.name : '', party ? (party.name_en || enOf(party.name)) : '')}</td>${grn ? `<td>${B('أمر الشراء', 'Purchase order')}</td><td class="num">${esc(order ? order.no : '')}</td>` : `<td>${B('التوريد المتوقع', 'Expected delivery')}</td><td class="num">${esc(fdate(doc.expected_date))}</td>`}</tr>
      ${party && party.vat_no ? `<tr><td>${B('الرقم الضريبي للمورد', "Supplier's VAT No.")}</td><td class="num" colspan="3">${esc(party.vat_no)}</td></tr>` : ''}
      ${grn && doc.supplier_doc ? `<tr><td>${B('إشعار تسليم المورد', "Supplier's delivery note")}</td><td class="num" colspan="3">${esc(doc.supplier_doc)}</td></tr>` : ''}
      ${doc.status === 'void' || doc.status === 'cancelled' ? `<tr><td colspan="4"><b>${B('ملغى', 'VOID')}</b></td></tr>` : ''}</tbody></table>`;
  const body = grn ? `<table class="iv-lines"><thead><tr><th>${B('الصنف', 'Item')}</th><th>${B('الوحدة', 'Unit')}</th><th class="r">${B('الكمية المستلمة', 'Qty received')}</th></tr></thead>
      <tbody>${lines.map(l => `<tr><td>${itm(l)}${l.expiry ? `<div class="small">${B('الدفعة / الصلاحية', 'Batch / expiry')} <span class="num">${esc(l.batch || '—')} · ${esc(fdate(l.expiry))}</span></div>` : ''}</td><td>${esc((L.im[l.item_id] || {}).unit || '')}</td><td class="num r">${qtyTxt(l.qty)}</td></tr>`).join('')}</tbody></table>
    <table class="iv-meta"><tbody><tr><td>${B('استلمها', 'Received by')}</td><td></td><td>${B('التوقيع', 'Signature')}</td><td style="height:16mm"></td></tr>
      <tr><td>${B('سلّمها (المورد)', 'Delivered by (supplier)')}</td><td></td><td>${B('التاريخ', 'Date')}</td><td></td></tr></tbody></table>`
    : `<table class="iv-lines"><thead><tr><th>${B('البند', 'Item')}</th><th class="r">${B('الكمية', 'Qty')}</th><th class="r">${B('سعر الوحدة', 'Unit price')}</th><th class="r">${B('المبلغ قبل الضريبة', 'Taxable amount')}</th><th class="r">${B('نسبة الضريبة', 'VAT rate')}</th><th class="r">${B('الإجمالي شامل الضريبة', 'Total incl. VAT')}</th></tr></thead>
      <tbody>${lines.map(l => `<tr><td>${itm(l)}</td><td class="num r">${qtyTxt(l.qty)}</td><td class="num r">${money(l.unit_price)}</td><td class="num r">${money(l.amount)}</td><td class="num r">${n0(l.vat_rate)}%</td><td class="num r">${money(n0(l.amount) + n0(l.vat))}</td></tr>`).join('')}</tbody></table>
    <table class="iv-tot"><tbody>${row('الإجمالي قبل الضريبة', 'Total excl. VAT', money(doc.subtotal))}${row('ضريبة القيمة المضافة', 'VAT', money(doc.vat))}
      <tr class="iv-grand"><td>${B('الإجمالي', 'Total')}</td><td class="num r">${money(doc.total)} <span class="small">SAR</span></td></tr></tbody></table>
    ${doc.terms ? `<p class="small"><b>${B('الشروط', 'Terms')}</b>${esc(doc.terms)}</p>` : ''}
    <table class="iv-meta"><tbody><tr><td>${B('اعتمده', 'Approved by')}</td><td></td><td>${B('التوقيع', 'Signature')}</td><td style="height:14mm"></td></tr></tbody></table>`;
  return `<div class="iv" dir="rtl" data-nt>${head}${meta}${body}${doc.note ? `<p class="small">${esc(doc.note)}</p>` : ''}
    <div class="iv-foot">${B('صدر من نظام وعد · تاريخ الطباعة <span class="num">' + esc(today()) + '</span>', 'Issued by Waad · printed <span class="num">' + esc(today()) + '</span>')}</div></div>`;
}
