'use strict';
/* ===== inventory: items, warehouses, transfers, stock counts, expiry, reorder ===== */
async function whList(force) { if (force || !cache.wh) cache.wh = await db.get('warehouses', Object.assign(C(), { order: 'is_default.desc,code' })); return cache.wh; }
const whName = w => w ? ((LANG === 'en' && w.name_en) || w.name) : '—';
/* a warehouse picker for documents — only shown when the company has more than one active warehouse */
async function whField(sel, label) {
  const ws = (await whList()).filter(w => w.active);
  if (ws.length < 2) return '';
  return field(label || 'المستودع', `<select name="warehouse">${ws.map(w => opt(w.id, whName(w) + (w.is_default ? ' ★' : ''), sel || (ws.find(x => x.is_default) || ws[0]).id)).join('')}</select>`);
}
async function whMap() { const m = {}; (await whList()).forEach(w => m[w.id] = w); return m; }
async function stockLevels() { const rows = can('stock') || can('sales') || can('purch') ? await db.rpc('stock_levels', { p_company: S.cid }) : []; const m = {};
  rows.forEach(r => { const x = m[r.item_id] || (m[r.item_id] = { qty: 0, value: 0, by: {} }); x.qty += n0(r.qty); x.value += n0(r.value); x.by[r.warehouse_id] = n0(r.qty); }); return m; }

/* ----- items ----- */
VIEWS['#/items'] = async page => {
  const [items, st, wm, ro] = await Promise.all([db.get('items', Object.assign(C(), { order: 'code' })), stockLevels(), whMap(), can('stock') || can('purch') ? db.rpc('reorder_list', { p_company: S.cid }).catch(() => []) : []]);
  const multi = Object.values(wm).filter(w => w.active).length > 1, low = new Set(ro.map(r => r.item_id));
  page.innerHTML = `<div class="head"><div><h1>الأصناف والمخزون</h1></div><div class="row">${can('stockadj') ? '<button class="btn" id="adj">تسوية مخزون</button>' : ''}${can('items') ? '<button class="btn" id="iim">استيراد من Excel</button><button class="btn pri" id="ni">صنف جديد</button>' : ''}</div></div>
    ${ro.length ? `<div class="note">${esc(tr('أصناف وصلت حد إعادة الطلب'))}: <b class="num">${ro.length}</b> — <a href="#/reorder">${esc(tr('إعادة الطلب'))}</a></div>` : ''}
    ${tbl([{ t: 'الرمز', k: 'code' }, { t: 'الصنف', h: i => esc(i.name) + (i.track_expiry ? ` <span class="badge">${esc(tr('صلاحية'))}</span>` : '') + (i.active === false ? ` <span class="badge">${esc(tr('موقوف'))}</span>` : '') + (i.category || i.barcode ? `<div class="small muted">${esc([i.category, i.barcode].filter(Boolean).join(' · '))}</div>` : '') }, { t: 'النوع', h: i => i.type === 'stock' ? 'مخزني' : 'خدمة' }, { t: 'سعر البيع', r: 1, h: i => money(i.sale_price) + (n0(i.vat_rate) === 0 ? ` <span class="small muted">${esc(tr('ضريبة 0%'))}</span>` : '') },
      ...(can('stock') ? [{ t: 'الكمية', r: 1, h: i => i.type !== 'stock' ? '—' : `<span class="num">${qtyTxt((st[i.id] || {}).qty)}</span>${low.has(i.id) ? ' <span class="badge wait">إعادة طلب</span>' : ''}`
        + (multi && st[i.id] ? `<div class="small muted">${Object.entries(st[i.id].by).map(([w, q]) => esc(whName(wm[w])) + ' <span class="num">' + qtyTxt(q) + '</span>').join(' · ')}</div>` : '') },
        { t: 'التكلفة', r: 1, h: i => i.type === 'stock' && st[i.id] ? money(st[i.id].value) : '—' }] : [])],
      items, { empty: 'لا توجد أصناف', onRow: can('items') })}`;
  const form = it => modal(it ? 'تعديل صنف' : 'صنف جديد', `<div class="fg">${field('الرمز', inp('code', it ? it.code : 'IT-' + String(items.length + 1).padStart(3, '0'), 'dir="ltr"'))}${field('الاسم', inp('name', it && it.name))}${enF('name_en', it && it.name_en)}
      ${field('النوع', `<select name="type" ${it ? 'disabled' : ''}>${opt('stock', 'مخزني', it && it.type)}${opt('service', 'خدمة', it && it.type)}</select>`)}${field('الوحدة', inp('unit', it && it.unit))}${field('التصنيف', inp('category', it && it.category, 'list="icats"') + `<datalist id="icats">${[...new Set(items.map(i => i.category).filter(Boolean))].map(c => `<option value="${esc(c)}">`).join('')}</datalist>`)}${field('الباركود', inp('barcode', it && it.barcode, 'dir="ltr" maxlength="32"'))}
      ${field('سعر البيع', inp('sale_price', it ? it.sale_price : '', 'type="number" step="0.01" min="0"'))}${field('سعر الشراء الافتراضي', inp('purchase_price', it && it.purchase_price, 'type="number" step="0.01" min="0"'))}
      ${field('ضريبة القيمة المضافة', `<select name="vat_rate">${opt(15, '15%', it ? +it.vat_rate : 15)}${opt(0, tr('0% (صفرية أو معفاة)'), it ? +it.vat_rate : 15)}</select>`)}${it ? field('الحالة', `<label class="row" style="gap:6px"><input type="checkbox" name="active" ${it.active !== false ? 'checked' : ''}> ${esc(tr('نشط — يظهر في الفواتير والأوامر الجديدة'))}</label>`) : ''}
      ${field('حد إعادة الطلب', inp('reorder_level', it ? it.reorder_level : 0, 'type="number" min="0" step="0.001"'))}${field('كمية إعادة الطلب', inp('reorder_qty', it ? it.reorder_qty : 0, 'type="number" min="0" step="0.001"'))}
      ${field('تتبع الصلاحية', `<select name="track_expiry">${opt('false', tr('لا'), String(!!(it && it.track_expiry)))}${opt('true', tr('نعم — دفعات وتواريخ انتهاء'), String(!!(it && it.track_expiry)))}</select>`)}
      ${field('الأرقام التسلسلية', `<select name="track_serial" ${it && st[it.id] ? 'disabled' : ''}>${opt('false', tr('لا'), String(!!(it && it.track_serial)))}${opt('true', tr('نعم — رقم لكل قطعة'), String(!!(it && it.track_serial)))}</select>`)}
      ${it ? `<div class="wide"><label>${esc(tr('وحدات أخرى'))}</label><div id="iul" class="small muted">${esc(tr('جارٍ التحميل…'))}</div>
        <div class="row" style="gap:6px;margin-top:6px"><input id="iun" placeholder="${esc(tr('الوحدة، مثل كرتون'))}" style="max-width:150px"><input id="iuf" type="number" min="0.0001" step="0.0001" placeholder="${esc(tr('كم') + ' ' + (it.unit || tr('وحدة')))}" style="max-width:120px"><input id="iub" dir="ltr" placeholder="${esc(tr('باركود (اختياري)'))}" style="max-width:170px"><button type="button" class="btn sm" id="iua">${esc(tr('إضافة'))}</button></div><div id="iuerr"></div></div>` : ''}</div>
      <p class="muted small">${esc(tr('عند تتبع الصلاحية يُطلب تاريخ الانتهاء عند الاستلام، ويُصرف الأقرب انتهاءً أولاً.'))}</p>`, {
    onOk: async f => { if (!f.code || f.name.length < 2) throw new Error('أدخل الرمز والاسم');
      const row = { code: f.code, name: f.name, name_en: blank((f.name_en || '').trim()), unit: blank(f.unit), sale_price: +f.sale_price || 0, reorder_level: +f.reorder_level || 0, reorder_qty: +f.reorder_qty || 0, track_expiry: f.track_expiry === 'true',
        category: blank(f.category), barcode: blank(f.barcode), purchase_price: f.purchase_price === '' ? null : +f.purchase_price, vat_rate: +f.vat_rate };
      if (f.track_serial !== undefined) row.track_serial = f.track_serial === 'true';
      if (it) row.active = !!f.active;
      if (it) await db.upd('items', { id: 'eq.' + it.id }, row); else await db.ins('items', Object.assign(row, { company_id: S.cid, type: f.type })); toast('تم الحفظ'); route(); }
  });
  const form0 = form, formU = it => { const d = form0(it); if (it) itemUnits(it, d); return d; };
  if ($('#ni', page)) $('#ni', page).onclick = () => formU(null);
  if ($('#iim', page)) $('#iim', page).onclick = itemImport;
  if (can('items')) bindRows(page, items, formU);
  if ($('#adj', page)) $('#adj', page).onclick = async () => { const wf = await whField();
    modal('تسوية مخزون', `<div class="fg">${field('الصنف', `<select name="item">${items.filter(i => i.type === 'stock').map(i => opt(i.id, i.code + ' — ' + i.name)).join('')}</select>`, 'wide')}${wf}${field('الكمية (+ زيادة / − عجز)', inp('qty', '', 'type="number" step="0.001"'))}${field('تكلفة الوحدة (للزيادة)', inp('cost', '', 'type="number" step="0.01" min="0"'))}${field('تاريخ الصلاحية (للزيادة في صنف بصلاحية)', '<input type="date" name="exp">')}${field('التاريخ', `<input type="date" name="d" value="${today()}">`)}${field('السبب', inp('reason'), 'wide')}</div>`, {
      onOk: async f => { await db.rpc('stock_adjust', { p_company: S.cid, p_item: f.item, p_date: f.d, p_qty: +f.qty, p_unit_cost: f.cost === '' ? null : +f.cost, p_reason: f.reason, p_warehouse: blank(f.warehouse), p_expiry: blank(f.exp) }); toast('سُجلت التسوية'); route(); } }); };
};

async function itemUnits(it, d) {
  const draw = async () => {
    const us = await db.get('item_units', { item_id: 'eq.' + it.id, order: 'factor' }).catch(() => []);
    $('#iul', d).innerHTML = us.length ? us.map(u => `<div class="row" style="gap:8px"><b>${esc(u.name)}</b> = <span class="num">${+u.factor}</span> ${esc(it.unit || '')}${u.barcode ? ` · <span class="num" dir="ltr">${esc(u.barcode)}</span>` : ''}<button type="button" class="btn sm" data-ud="${u.id}" aria-label="${esc(tr('حذف'))}">×</button></div>`).join('') : esc(tr('لا توجد وحدات أخرى'));
    $$('[data-ud]', d).forEach(b => b.onclick = async () => { try { await db.del('item_units', { id: 'eq.' + b.dataset.ud }); draw(); } catch (er) { showErr($('#iuerr', d), er); } });
  };
  $('#iua', d).onclick = async () => { const n = $('#iun', d).value.trim(), f = +$('#iuf', d).value;
    try { if (!n || !(f > 0) || f === 1) throw new Error('اكتب اسم الوحدة وكم تساوي من الوحدة الأساسية (غير 1)');
      await db.ins('item_units', { company_id: S.cid, item_id: it.id, name: n, factor: f, barcode: blank($('#iub', d).value.trim()) });
      $('#iun', d).value = ''; $('#iuf', d).value = ''; $('#iub', d).value = ''; $('#iuerr', d).innerHTML = ''; draw(); } catch (er) { showErr($('#iuerr', d), er); } };
  draw();
}
const ITEM_COLS = [['code', 'رمز الصنف', 'code|item code|الرمز|رمز', true], ['name', 'اسم الصنف', 'name|item|الاسم|الصنف'], ['name_en', 'الاسم بالإنجليزية', 'name_en|english name'],
  ['type', 'النوع (مخزني / خدمة)', 'type|النوع'], ['unit', 'الوحدة', 'unit|الوحدة'], ['category', 'التصنيف', 'category|التصنيف|الفئة'], ['barcode', 'الباركود', 'barcode|الباركود|ean'],
  ['sale_price', 'سعر البيع', 'sale price|price|سعر البيع'], ['purchase_price', 'سعر الشراء', 'purchase price|cost|سعر الشراء'], ['vat_rate', 'نسبة الضريبة (0 أو 15)', 'vat|vat rate|الضريبة|نسبة الضريبة'],
  ['reorder_level', 'حد إعادة الطلب', 'reorder level|حد إعادة الطلب']];
function itemImport() {
  const d = modal(tr('استيراد الأصناف من Excel'), `<ol class="small" style="padding-inline-start:18px;margin-top:0"><li>${esc(tr('نزّل القالب واملأ سطراً لكل صنف — الرمز مطلوب، والاسم مطلوب للصنف الجديد.'))}</li>
    <li>${esc(tr('الرمز الموجود تُحدَّث بياناته من الخانات المعبأة فقط، والجديد يُضاف. نوع الصنف لا يتغير بعد إنشائه.'))}</li><li>${esc(tr('الكميات الافتتاحية تُدخل من «الأرصدة الافتتاحية».'))}</li></ol>
    <div class="row"><button type="button" class="btn" id="itpl">${esc(tr('تنزيل القالب'))}</button><label class="btn pri" style="margin:0;color:var(--prim-ink)">${esc(tr('اختيار الملف'))}<input type="file" id="iimf" accept=".xlsx,.csv,text/csv" hidden></label></div><div id="iimp"></div>`, { wide: true });
  $('#itpl', d).onclick = () => { const a = document.createElement('a'); a.href = URL.createObjectURL(templateXlsx([ITEM_COLS.map(c => tr(c[1]) + (c[3] ? ' *' : ''))])); a.download = 'waad-items.xlsx'; a.click(); };
  $('#iimf', d).onchange = async ev => {
    const file = ev.target.files[0]; if (!file) return; const box = $('#iimp', d);
    try {
      const { hdr, body } = await readSheetFile(file), idx = mapHeadersBy(ITEM_COLS, hdr);
      if (!('code' in idx)) throw new Error('عمود رمز الصنف غير موجود — استخدم القالب');
      if (!body.length) throw new Error('لا توجد صفوف تحت العناوين');
      if (body.length > 3000) throw new Error('الحد الأقصى 3000 سطر في الملف الواحد');
      const seen = {}, rows = body.map(({ r, no }) => { const x = { _row: no }, errs = [];
        ITEM_COLS.forEach(([k]) => { if (idx[k] != null) { const v = arDigits(String(r[idx[k]] == null ? '' : r[idx[k]]).trim()); if (v) x[k] = v; } });
        if (!x.code) errs.push(tr('رمز الصنف مطلوب')); else if (seen[x.code]) errs.push(tr('الرمز مكرر في الملف')); seen[x.code] = 1;
        ['sale_price', 'purchase_price', 'reorder_level'].forEach(k => { if (x[k] && !(+x[k] >= 0)) errs.push(tr('الأسعار والكميات أرقام فقط')); });
        if (x.vat_rate && !['0', '15'].includes(x.vat_rate.replace('%', ''))) errs.push(tr('نسبة الضريبة 0 أو 15'));
        return { x, errs }; });
      const bad = rows.filter(i => i.errs.length);
      box.innerHTML = `<div class="${bad.length ? 'err' : 'note'}">${rows.length} ${esc(tr('سطر في الملف'))}${bad.length ? ` — ${bad.length} ${esc(tr('سطر فيه أخطاء، صحّحها في الملف ثم ارفعه مجدداً'))}` : ' — ' + esc(tr('جاهز للاستيراد'))}</div>
        ${tbl([{ t: 'السطر', h: i => i.x._row }, { t: 'الرمز', h: i => `<span class="num">${esc(i.x.code || '')}</span>` }, { t: 'الاسم', h: i => esc(i.x.name || '') }, { t: 'سعر البيع', r: 1, h: i => esc(i.x.sale_price || '') },
          { t: 'الملاحظات', h: i => i.errs.length ? `<span class="bad">${esc(i.errs.join('، '))}</span>` : '<span class="ok">✓</span>' }], (bad.length ? bad : rows).slice(0, 300))}
        ${bad.length ? '' : `<div class="row" style="margin-top:12px"><button type="button" class="btn pri" id="igo">${esc(tr('استيراد'))} ${rows.length} ${esc(tr('سطر'))}</button></div><div id="iier"></div>`}`;
      if ($('#igo', d)) $('#igo', d).onclick = async () => { try { await busy($('#igo', d), async () => {
        const res = await db.rpc('import_items', { p_company: S.cid, p_rows: rows.map(i => i.x) }); d.close(); cache.items = null;
        toast(tr('أُضيف') + ' ' + res.added + ' · ' + tr('حُدّث') + ' ' + res.updated); route(); }); } catch (er) { showErr($('#iier', d), er); } };
    } catch (er) { showErr(box, er); }
    ev.target.value = '';
  };
}

/* ----- warehouses ----- */
VIEWS['#/warehouses'] = async page => {
  const [ws, st] = await Promise.all([whList(true), stockLevels()]);
  const tot = {}; Object.values(st).forEach(x => Object.entries(x.by).forEach(([w, q]) => { const t = tot[w] || (tot[w] = { n: 0, q: 0 }); if (q > 0) t.n++; t.q += q; }));
  page.innerHTML = `<div class="head"><div><h1>المستودعات</h1><div class="muted small">لكل مستودع رصيده، والتكلفة متوسط واحد للمنشأة</div></div>${can('items') ? '<button class="btn pri" id="nw">مستودع جديد</button>' : ''}</div>
    ${tbl([{ t: 'الرمز', h: w => `<span class="num">${esc(w.code)}</span>` }, { t: 'المستودع', h: w => esc(whName(w)) + (w.is_default ? ` <span class="badge ok">${esc(tr('افتراضي'))}</span>` : '') + (w.active ? '' : ` <span class="badge">${esc(tr('موقوف'))}</span>`) },
      { t: 'أصناف فيها رصيد', r: 1, h: w => (tot[w.id] || {}).n || 0 }, { t: '', h: w => can('items') && !w.is_default && w.active ? `<button class="btn sm" data-def="${w.id}">${esc(tr('اجعله الافتراضي'))}</button>` : '' }], ws, { onRow: can('items') })}`;
  const form = w => modal(w ? 'تعديل مستودع' : 'مستودع جديد', `<div class="fg">${field('الرمز (حروف إنجليزية وأرقام)', inp('code', w ? w.code : '', 'dir="ltr" maxlength="12" required'))}${field('الاسم', inp('name', w && w.name, 'required'))}${enF('name_en', w && w.name_en)}
      ${w ? field('الحالة', `<select name="active">${opt('true', tr('نشط'), String(w.active))}${opt('false', tr('موقوف'), String(w.active))}</select>`) : ''}</div>`, {
    onOk: async f => { await db.rpc('warehouse_save', { p_company: S.cid, p_doc: { id: w ? w.id : null, code: f.code, name: f.name, name_en: blank(f.name_en), active: w ? f.active === 'true' : true } }); cache.wh = null; toast('تم الحفظ'); route(); } });
  if ($('#nw', page)) $('#nw', page).onclick = () => form(null);
  if (can('items')) bindRows(page, ws, form);
  $$('[data-def]', page).forEach(b => b.onclick = async e => { e.stopPropagation(); await db.rpc('warehouse_set_default', { p_company: S.cid, p_id: b.dataset.def }); cache.wh = null; toast('تم الحفظ'); route(); });
};

/* ----- transfers ----- */
VIEWS['#/transfers'] = async (page, arg) => {
  if (arg === 'new') return trForm(page);
  if (arg) return trView(page, arg);
  const [rows, wm] = await Promise.all([db.get('stock_transfers', Object.assign(C(), { order: 'date.desc,no.desc', limit: 300 })), whMap()]);
  page.innerHTML = `<div class="head"><div><h1>تحويلات المخزون</h1><div class="muted small">نقل كميات بين المستودعات بالتكلفة نفسها، مع دفعاتها وتواريخ صلاحيتها</div></div>${can('stock') && Object.keys(wm).length > 1 ? '<a class="btn pri" href="#/transfers/new">تحويل جديد</a>' : ''}</div>
    ${Object.keys(wm).length < 2 ? `<div class="note">${esc(tr('أضف مستودعاً ثانياً لتحويل الكميات بينهما.'))} <a href="#/warehouses">${esc(tr('المستودعات'))}</a></div>` : ''}
    ${tbl([{ t: 'الرقم', h: r => `<span class="num">${esc(r.no)}</span>` }, { t: 'التاريخ', h: r => fdate(r.date) }, { t: 'من', h: r => esc(whName(wm[r.from_wh])) }, { t: 'إلى', h: r => esc(whName(wm[r.to_wh])) }, { t: 'ملاحظات', h: r => esc(r.note || '') }],
      rows, { empty: 'لا توجد تحويلات', onRow: true })}`;
  bindRows(page, rows, r => location.hash = '#/transfers/' + r.id);
};
async function trForm(page) {
  if (!can('stock')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const [ws, items, st] = await Promise.all([whList(), db.get('items', Object.assign(C(), { type: 'eq.stock', order: 'code' })), stockLevels()]);
  const act = ws.filter(w => w.active), lines = [{}];
  page.innerHTML = `<div class="head"><div><a href="#/transfers" class="small">← تحويلات المخزون</a><h1>تحويل جديد</h1></div></div><form id="tf" class="card" novalidate>
    <div class="fg">${field('من مستودع', `<select name="from">${act.map(w => opt(w.id, whName(w))).join('')}</select>`)}${field('إلى مستودع', `<select name="to">${act.map((w, i) => opt(w.id, whName(w), (act[1] || act[0]).id)).join('')}</select>`)}${field('التاريخ', `<input type="date" name="date" value="${today()}" max="${today()}">`)}${field('ملاحظات', inp('note'), 'wide')}</div>
    <div style="height:12px"></div><div class="tw"><table class="lines"><thead><tr><th>الصنف</th><th>المتوفر في المصدر</th><th>الكمية</th><th></th></tr></thead><tbody id="lb"></tbody></table></div>
    <div class="row" style="margin-top:10px"><button type="button" class="btn sm" id="al">+ بند</button></div><div id="terr"></div>
    <div class="row" style="margin-top:14px"><button class="btn pri" id="ts">ترحيل التحويل</button><a class="btn" href="#/transfers">إلغاء</a></div></form>`;
  const from = () => $('[name=from]', page).value;
  const draw = () => { $('#lb', page).innerHTML = lines.map((l, i) => `<tr data-i="${i}"><td style="min-width:220px"><select data-f="item"><option value="">—</option>${items.map(it => opt(it.id, it.code + ' — ' + it.name, l.item)).join('')}</select></td>
      <td class="num" data-av>${l.item ? qtyTxt(((st[l.item] || {}).by || {})[from()]) : '—'}</td><td><input data-f="qty" type="number" min="0" step="0.001" value="${esc(l.qty || '')}" style="width:100px"></td><td><button type="button" class="btn sm" data-rm aria-label="حذف البند">×</button></td></tr>`).join(''); };
  $('#lb', page).addEventListener('input', e => { const tr = e.target.closest('tr'); if (!tr) return; lines[+tr.dataset.i][e.target.dataset.f] = e.target.value; if (e.target.dataset.f === 'item') draw(); });
  $('#lb', page).addEventListener('click', e => { if (e.target.matches('[data-rm]')) { lines.splice(+e.target.closest('tr').dataset.i, 1); if (!lines.length) lines.push({}); draw(); } });
  $('[name=from]', page).onchange = draw; $('#al', page).onclick = () => { lines.push({}); draw(); }; draw();
  $('#tf', page).onsubmit = async e => { e.preventDefault(); const f = formData(e.target); const ls = lines.filter(l => l.item && +l.qty > 0).map(l => ({ item: l.item, qty: +l.qty }));
    if (!ls.length) return showErr($('#terr', page), 'أضف بنداً واحداً على الأقل');
    try { await busy($('#ts', page), async () => { const id = await db.rpc('stock_transfer', { p_company: S.cid, p_doc: { from: f.from, to: f.to, date: f.date, note: blank(f.note), lines: ls } }); toast('رُحّل التحويل'); location.hash = '#/transfers/' + id; }); } catch (er) { showErr($('#terr', page), er); } };
}
async function trView(page, id) {
  const [[t], lines, items, wm] = await Promise.all([db.get('stock_transfers', { id: 'eq.' + id }), db.get('stock_transfer_lines', { transfer_id: 'eq.' + id, order: 'id' }), db.get('items', Object.assign(C(), { select: 'id,code,name,name_en,unit' })), whMap()]);
  if (!t) throw new Error('التحويل غير موجود');
  const im = {}; items.forEach(i => im[i.id] = i);
  page.innerHTML = `<div class="head"><div><a href="#/transfers" class="small">← تحويلات المخزون</a><h1>تحويل <span class="num">${esc(t.no)}</span></h1><div class="muted">${fdate(t.date)} · ${esc(whName(wm[t.from_wh]))} ← ${esc(whName(wm[t.to_wh]))}</div></div><button class="btn" id="tprint">طباعة</button></div>
    <div class="card">${tbl([{ t: 'الصنف', h: l => esc((im[l.item_id] || {}).code + ' — ' + (im[l.item_id] || {}).name) }, { t: 'الوحدة', h: l => esc((im[l.item_id] || {}).unit || '—') }, { t: 'الكمية', r: 1, h: l => qtyTxt(l.qty) }], lines)}${t.note ? `<p class="muted small">${esc(t.note)}</p>` : ''}</div>`;
  $('#tprint', page).onclick = () => { const w = document.createElement('div');
    w.innerHTML = invSheet(['سند تحويل مخزون', 'Stock Transfer Note'], [[['الرقم', 'No.'], t.no], [['التاريخ', 'Date'], fdate(t.date)], [['من مستودع', 'From'], whName(wm[t.from_wh])], [['إلى مستودع', 'To'], whName(wm[t.to_wh])]],
      [['الصنف', 'Item'], ['الوحدة', 'Unit'], ['الكمية', 'Qty']], lines.map(l => [esc((im[l.item_id] || {}).code + ' — ' + (im[l.item_id] || {}).name), esc((im[l.item_id] || {}).unit || ''), qtyTxt(l.qty)]), [['سلّمها', 'Issued by'], ['استلمها', 'Received by']], t.note);
    printWith(w.firstElementChild, '@page{size:A4 portrait;margin:12mm}'); };
}

/* ----- stock counts ----- */
VIEWS['#/counts'] = async (page, arg) => {
  if (arg) return countView(page, arg);
  const [rows, ws] = await Promise.all([db.get('stock_counts', Object.assign(C(), { order: 'created_at.desc', limit: 200 })), whList()]);
  const wm = {}; ws.forEach(w => wm[w.id] = w);
  const stb = s => ({ draft: `<span class="badge wait">${esc(tr('قيد العد'))}</span>`, posted: badge('posted'), cancelled: badge('cancelled') }[s]);
  page.innerHTML = `<div class="head"><div><h1>الجرد</h1><div class="muted small">ورقة عد لكل مستودع بالكمية في النظام، وعند الترحيل تُقيد الفروقات بمتوسط التكلفة</div></div>${can('stockadj') ? '<button class="btn pri" id="nc">جرد جديد</button>' : ''}</div>
    ${tbl([{ t: 'الرقم', h: r => `<span class="num">${esc(r.no)}</span>` }, { t: 'التاريخ', h: r => fdate(r.date) }, { t: 'المستودع', h: r => esc(whName(wm[r.warehouse_id])) }, { t: 'زيادة', r: 1, h: r => r.status === 'posted' ? money(r.gain) : '—' }, { t: 'عجز', r: 1, h: r => r.status === 'posted' ? money(r.loss) : '—' }, { t: 'الحالة', h: r => stb(r.status) }],
      rows, { empty: 'لا يوجد جرد', onRow: true })}`;
  bindRows(page, rows, r => location.hash = '#/counts/' + r.id);
  if ($('#nc', page)) $('#nc', page).onclick = () => modal('جرد جديد', `<div class="fg">${field('المستودع', `<select name="wh">${ws.filter(w => w.active).map(w => opt(w.id, whName(w))).join('')}</select>`)}${field('ملاحظات', inp('note'), 'wide')}</div><p class="muted small">${esc(tr('تُنشأ ورقة بكل الأصناف المخزنية وكمياتها في النظام الآن. اطبعها للعد ثم أدخل الكميات المعدودة.'))}</p>`, {
    ok: 'إنشاء ورقة الجرد', onOk: async f => { const id = await db.rpc('count_open', { p_company: S.cid, p_wh: f.wh, p_note: blank(f.note) }); location.hash = '#/counts/' + id; } });
};
async function countView(page, id) {
  const [[c], lines, items, wm, units] = await Promise.all([db.get('stock_counts', { id: 'eq.' + id }), db.get('stock_count_lines', { count_id: 'eq.' + id, order: 'id' }), db.get('items', Object.assign(C(), { select: 'id,code,name,name_en,unit,track_expiry,barcode' })), whMap(), db.get('item_units', Object.assign(C(), { select: 'item_id,factor,barcode' })).catch(() => [])]);
  if (!c) throw new Error('الجرد غير موجود');
  const im = {}; items.forEach(i => im[i.id] = i); const draft = c.status === 'draft' && can('stockadj');
  const nm = l => esc((im[l.item_id] || {}).code + ' — ' + (im[l.item_id] || {}).name);
  page.innerHTML = `<div class="head"><div><a href="#/counts" class="small">← الجرد</a><h1>جرد <span class="num">${esc(c.no)}</span> ${c.status === 'draft' ? `<span class="badge wait">${esc(tr('قيد العد'))}</span>` : badge(c.status)}</h1><div class="muted">${esc(whName(wm[c.warehouse_id]))} · ${fdate(c.date)}${c.note ? ' · ' + esc(c.note) : ''}</div></div>
      <div class="row">${draft ? '<button class="btn" id="csv">حفظ</button><button class="btn pri" id="cpost">ترحيل الجرد</button><button class="btn danger" id="ccn">إلغاء</button>' : ''}<button class="btn" id="cprint">${c.status === 'draft' ? 'طباعة ورقة العد' : 'طباعة'}</button></div></div>
    ${draft ? `<div class="card"><div class="row" style="gap:8px;flex-wrap:wrap"><input id="cscan" dir="ltr" autocomplete="off" placeholder="${esc(tr('امسح الباركود أو اكتب رمز الصنف ثم Enter — كل مسحة تزيد المعدود'))}" style="max-width:420px">
      ${'BarcodeDetector' in window ? `<button type="button" class="btn" id="ccam">${esc(tr('المسح بكاميرا الجوال'))}</button>` : ''}<span class="small" id="cmsg" role="status"></span></div></div>` : ''}
    <div class="card"><div class="tw"><table><thead><tr><th>الصنف</th><th class="r">في النظام</th><th class="r">المعدود</th>${c.status === 'posted' ? '<th class="r">الفرق</th><th class="r">القيمة</th>' : '<th>الدفعة / الصلاحية (للزيادة)</th>'}</tr></thead><tbody>
      ${lines.map(l => `<tr data-l="${l.id}" data-it="${l.item_id}"><td>${nm(l)}</td><td class="r num">${qtyTxt(c.status === 'posted' && l.posted_qty != null ? l.posted_qty : l.system_qty)}</td>
        <td class="r">${draft ? `<input data-c type="number" min="0" step="0.001" value="${l.counted == null ? '' : +l.counted}" style="width:100px">` : `<span class="num">${l.counted == null ? '—' : qtyTxt(l.counted)}</span>`}</td>
        ${c.status === 'posted' ? `<td class="r num ${n0(l.diff) < 0 ? 'bad' : n0(l.diff) > 0 ? 'ok' : ''}">${l.diff == null ? '—' : qtyTxt(l.diff)}</td><td class="r num">${l.value == null ? '—' : money(l.value)}</td>`
          : `<td>${(im[l.item_id] || {}).track_expiry && draft ? `<input data-b placeholder="${esc(tr('الدفعة'))}" value="${esc(l.batch || '')}" style="width:110px"> <input data-x type="date" value="${l.expiry || ''}" style="width:150px">` : ''}</td>`}</tr>`).join('')}</tbody></table></div>
      <p class="muted small">${esc(tr('اترك المعدود فارغاً للأصناف التي لم تُعد؛ لا تتغير. الفرق يُحسب على الكمية في النظام لحظة الترحيل.'))}</p></div>`;
  const collect = () => $$('tr[data-l]', page).map(tr => ({ id: +tr.dataset.l, counted: $('[data-c]', tr).value, batch: $('[data-b]', tr) ? $('[data-b]', tr).value : null, expiry: $('[data-x]', tr) ? $('[data-x]', tr).value : null }));
  const on = (s, fn) => { const b = $(s, page); if (b) b.onclick = fn; };
  // scanning: each scan adds one piece (or a carton's worth when its unit barcode is scanned) to the counted quantity
  const scan = v => { v = String(v || '').trim(); if (!v) return;
    const un = units.find(u => u.barcode === v), it = un ? items.find(i => i.id === un.item_id) : items.find(i => i.barcode === v || String(i.code).toLowerCase() === v.toLowerCase());
    const row = it && $(`tr[data-it="${it.id}"]`, page);
    if (!row) { $('#cmsg', page).innerHTML = `<span class="bad">${esc(tr('ليس في ورقة هذا الجرد'))}: ${esc(v)}</span>`; return; }
    const inp = $('[data-c]', row); inp.value = r2(n0(inp.value) + (un ? +un.factor : 1));
    $$('tr.hl', page).forEach(x => x.classList.remove('hl')); row.classList.add('hl'); row.scrollIntoView({ block: 'center' });
    $('#cmsg', page).innerHTML = `<span class="ok">${esc(it.name)}: <b class="num">${inp.value}</b></span>`; };
  if ($('#cscan', page)) $('#cscan', page).onkeydown = e => { if (e.key !== 'Enter') return; e.preventDefault(); scan(e.target.value); e.target.value = ''; };
  on('#ccam', async () => {
    let stream; try { stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } }); } catch (e) { return toast(tr('لم يُسمح باستخدام الكاميرا')); }
    const d = modal(tr('المسح بالكاميرا'), `<video id="cv" playsinline muted style="width:100%;max-height:60vh;background:#000;border-radius:8px"></video><p class="small" id="cvm">${esc(tr('وجّه الكاميرا إلى الباركود'))}</p>`, { ok: 'تم' });
    const v = $('#cv', d); v.srcObject = stream; await v.play().catch(() => {});
    const det = new BarcodeDetector(); let last = '', lastAt = 0, live = true;
    d.addEventListener('close', () => { live = false; stream.getTracks().forEach(t => t.stop()); }, { once: true });
    const loop = async () => { if (!live) return; try { const r = await det.detect(v); const code = r[0] && r[0].rawValue;
      if (code && (code !== last || Date.now() - lastAt > 1500)) { last = code; lastAt = Date.now(); scan(code); $('#cvm', d).textContent = $('#cmsg', page).textContent; if (navigator.vibrate) navigator.vibrate(60); } } catch (e) {}
      setTimeout(loop, 250); };
    loop(); });
  on('#csv', async e => { await busy(e.target, () => db.rpc('count_save', { p_id: id, p_lines: collect() })); toast('تم الحفظ'); });
  on('#cpost', async e => { if (!await confirmBox('ترحيل الجرد', tr('تُقيد الفروقات على المخزون ولا يمكن التعديل بعدها. متابعة؟'), 'ترحيل الجرد')) return;
    try { await busy(e.target, async () => { await db.rpc('count_save', { p_id: id, p_lines: collect() }); const r = await db.rpc('count_post', { p_id: id }); toast(tr('رُحّل الجرد') + ' — ' + tr('زيادة') + ' ' + money(r.gain) + ' · ' + tr('عجز') + ' ' + money(r.loss)); route(); }); } catch (er) { toast(er.message); } });
  on('#ccn', async () => { if (!await confirmBox('إلغاء الجرد', tr('تُلغى ورقة العد بدون أي أثر على المخزون.'), 'إلغاء الجرد')) return; await db.rpc('count_cancel', { p_id: id }); toast('تم'); route(); });
  on('#cprint', () => { const w = document.createElement('div'); const posted = c.status === 'posted';
    w.innerHTML = invSheet(['ورقة جرد', 'Stock Count Sheet'], [[['الرقم', 'No.'], c.no], [['التاريخ', 'Date'], fdate(c.date)], [['المستودع', 'Warehouse'], whName(wm[c.warehouse_id])], [['الحالة', 'Status'], posted ? tr('مرحّل') : tr('قيد العد')]],
      [['الصنف', 'Item'], ['الوحدة', 'Unit'], ['في النظام', 'System qty'], ['المعدود', 'Counted'], ...(posted ? [['الفرق', 'Difference']] : [])],
      lines.map(l => [nm(l), esc((im[l.item_id] || {}).unit || ''), qtyTxt(posted && l.posted_qty != null ? l.posted_qty : l.system_qty), l.counted == null ? '' : qtyTxt(l.counted), ...(posted ? [l.diff == null ? '' : qtyTxt(l.diff)] : [])]), [['عدّها', 'Counted by'], ['راجعها', 'Checked by']], c.note);
    printWith(w.firstElementChild, '@page{size:A4 portrait;margin:12mm}'); });
}

/* ----- expiry ----- */
VIEWS['#/expiry'] = async (page, arg, q) => {
  const days = +(q && q.get('d')) || 60;
  const [rows, items, wm] = await Promise.all([db.rpc('expiry_list', { p_company: S.cid, p_days: days }), db.get('items', Object.assign(C(), { select: 'id,code,name,unit' })), whMap()]);
  const im = {}; items.forEach(i => im[i.id] = i);
  page.innerHTML = `<div class="head"><div><h1>صلاحية الأصناف</h1><div class="muted small">الدفعات التي تنتهي خلال المدة المختارة أو انتهت، للأصناف التي تتبع الصلاحية</div></div>
      <div class="row">${[30, 60, 90, 180].map(d => `<a class="btn sm ${d === days ? 'pri' : ''}" href="#/expiry?d=${d}">${d} ${esc(tr('يوم'))}</a>`).join('')}</div></div>
    ${tbl([{ t: 'الصنف', h: r => esc((im[r.item_id] || {}).code + ' — ' + (im[r.item_id] || {}).name) }, { t: 'المستودع', h: r => esc(whName(wm[r.warehouse_id])) }, { t: 'الدفعة', h: r => `<span class="num">${esc(r.batch || '—')}</span>` },
      { t: 'تاريخ الانتهاء', h: r => fdate(r.expiry) }, { t: 'المتبقي', h: r => r.days_left < 0 ? `<span class="badge bad">${esc(tr('منتهٍ'))}</span>` : `<span class="badge ${r.days_left <= 30 ? 'wait' : ''}"><span class="num">${r.days_left}</span> ${esc(tr('يوم'))}</span>` },
      { t: 'الكمية', r: 1, h: r => qtyTxt(r.qty) + ' ' + esc((im[r.item_id] || {}).unit || '') }], rows, { empty: 'لا توجد دفعات تنتهي خلال هذه المدة' })}`;
};

/* ----- reorder ----- */
VIEWS['#/reorder'] = async page => {
  const [rows, items, sup] = await Promise.all([db.rpc('reorder_list', { p_company: S.cid }), db.get('items', Object.assign(C(), { select: 'id,code,name,unit' })), can('purch') ? db.get('parties', Object.assign(C(), { kind: 'eq.supplier', order: 'name' })) : []]);
  const im = {}, sm = {}; items.forEach(i => im[i.id] = i); sup.forEach(s => sm[s.id] = s);
  page.innerHTML = `<div class="head"><div><h1>إعادة الطلب</h1><div class="muted small">أصناف رصيدها مع المطلوب في أوامر الشراء المفتوحة عند حد إعادة الطلب أو أقل</div></div></div>
    ${rows.length && can('purch') ? `<div class="card row" style="align-items:flex-end">${field('المورد', `<select id="rsup">${sup.map(s => opt(s.id, s.name, (rows.find(r => r.last_supplier) || {}).last_supplier)).join('')}</select>`)}<button class="btn pri" id="rpo">إنشاء أمر شراء بالمحدد</button></div>` : ''}
    <div class="tw"><table><thead><tr>${can('purch') ? '<th></th>' : ''}<th>الصنف</th><th class="r">الرصيد</th><th class="r">تحت الطلب</th><th class="r">حد إعادة الطلب</th><th class="r">الكمية المقترحة</th><th>آخر مورد</th><th class="r">آخر سعر</th></tr></thead><tbody>
      ${rows.length ? rows.map(r => `<tr data-it="${r.item_id}">${can('purch') ? '<td><input type="checkbox" data-pick checked style="width:auto"></td>' : ''}<td>${esc((im[r.item_id] || {}).code + ' — ' + (im[r.item_id] || {}).name)}</td><td class="r num">${qtyTxt(r.on_hand)}</td><td class="r num">${qtyTxt(r.on_order)}</td><td class="r num">${qtyTxt(r.reorder_level)}</td>
        <td class="r"><input data-q type="number" min="0" step="0.001" value="${+n0(r.suggested).toFixed(3)}" style="width:100px" ${can('purch') ? '' : 'disabled'}></td><td>${esc((sm[r.last_supplier] || {}).name || '—')}</td><td class="r num" data-p="${r.last_price == null ? '' : r.last_price}">${r.last_price == null ? '—' : money(r.last_price)}</td></tr>`).join('')
        : `<tr><td colspan="8" class="muted">${esc(tr('لا توجد أصناف تحت حد إعادة الطلب'))}</td></tr>`}</tbody></table></div>
    <p class="muted small">${esc(tr('حدد حد إعادة الطلب وكميته من بطاقة الصنف. الكمية المقترحة = كمية إعادة الطلب، أو ما يرفع الرصيد إلى ضعف الحد.'))}</p>`;
  if ($('#rpo', page)) $('#rpo', page).onclick = () => {
    const pick = $$('tr[data-it]', page).filter(tr => $('[data-pick]', tr).checked).map(tr => [tr.dataset.it, +$('[data-q]', tr).value || 0, $('[data-p]', tr).dataset.p || ''].join(':')).filter(x => !/:0:/.test(x));
    if (!pick.length) return toast(tr('حدد صنفاً واحداً على الأقل'));
    location.hash = '#/porders/new?sup=' + $('#rsup', page).value + '&items=' + encodeURIComponent(pick.join(','));
  };
};

/* bilingual inventory printout: title, meta pairs, table, signature boxes */
function invSheet(title, meta, cols, rows, signs, note) {
  const c = S.company || {}, B = (ar, en) => `<div>${esc(ar)}</div><div class="iv-en" dir="ltr">${esc(en)}</div>`;
  const pairs = []; for (let i = 0; i < meta.length; i += 2) pairs.push(meta.slice(i, i + 2));
  return `<div class="iv" dir="rtl" data-nt><div class="iv-head"><div class="ph-brand">${c.logo ? `<img class="ph-logo" src="${esc(c.logo)}" alt="">` : ''}<div><div class="ph-co">${esc(c.name || '')}</div>${c.name_en ? `<div class="iv-en" dir="ltr"><b>${esc(c.name_en)}</b></div>` : ''}</div></div><div class="iv-title">${B(title[0], title[1])}</div></div>
    <table class="iv-meta"><tbody>${pairs.map(p => `<tr>${p.map(([l, v]) => `<td>${B(l[0], l[1])}</td><td class="num">${esc(v)}</td>`).join('')}${p.length < 2 ? '<td></td><td></td>' : ''}</tr>`).join('')}</tbody></table>
    <table class="iv-lines"><thead><tr>${cols.map((h, i) => `<th${i > 1 ? ' class="r"' : ''}>${B(h[0], h[1])}</th>`).join('')}</tr></thead><tbody>${rows.map(r => `<tr>${r.map((v, i) => `<td${i > 1 ? ' class="num r"' : ''}${i === 3 && v === '' ? ' style="min-width:22mm"' : ''}>${v}</td>`).join('')}</tr>`).join('')}</tbody></table>
    ${note ? `<p class="small">${esc(note)}</p>` : ''}
    <table class="iv-meta"><tbody><tr>${signs.map(s => `<td>${B(s[0], s[1])}</td><td style="height:14mm"></td>`).join('')}</tr></tbody></table>
    <div class="iv-foot">${B('صدر من نظام وعد · تاريخ الطباعة ' + today(), 'Issued by Waad · printed ' + today())}</div></div>`;
}
