'use strict';
const C = () => ({ company_id: 'eq.' + S.cid });
async function accounts() { return cache.acc || (cache.acc = await db.get('accounts', Object.assign(C(), { order: 'code' }))); }
const cashAccounts = async () => (await accounts()).filter(a => a.parent_code === '1100' && !a.is_header);

/* ===== customers & suppliers ===== */
const SA_ADDR = [['bld_no', 'رقم المبنى', '4 أرقام', 'dir="ltr" inputmode="numeric" maxlength="4"'], ['street', 'الشارع'], ['district', 'الحي'], ['city', 'المدينة'],
  ['postal_code', 'الرمز البريدي', '5 أرقام', 'dir="ltr" inputmode="numeric" maxlength="5"'], ['add_no', 'الرقم الإضافي', '4 أرقام', 'dir="ltr" inputmode="numeric" maxlength="4"'],
  ['short_address', 'العنوان المختصر', 'RRRD2929', 'dir="ltr" maxlength="9" style="text-transform:uppercase"']];
const addrFields = (v, saudi = true) => SA_ADDR.map(([k, t, ph, at]) => field(t, inp(k, v && v[k], (at || '') + (ph && saudi ? ` placeholder="${esc(ph)}"` : '')))).join('');
const ibanBank = iban => { const i = String(iban || '').replace(/\s/g, '').toUpperCase(), b = /^SA\d{4}/.test(i) && typeof SA_BANKS !== 'undefined' && SA_BANKS[i.slice(4, 6)]; return b ? tr(b[1]) : ''; };
// national address as printed lines (ZATCA: building, street, district, city, postal code, additional no.)
const addrLine = o => o ? [o.bld_no && tr('مبنى') + ' ' + o.bld_no, o.street, o.district && tr('حي') + ' ' + o.district, o.city, o.postal_code && tr('الرمز البريدي') + ' ' + o.postal_code, o.add_no && tr('الرقم الإضافي') + ' ' + o.add_no].filter(Boolean).join('، ') : '';
const PARTY_COLS = [
  ['name', 'الاسم', 'name|الاسم|اسم العميل|اسم المورد|customer|supplier|company', true], ['name_en', 'الاسم بالإنجليزية', 'name_en|english name|name english'],
  ['vat_no', 'الرقم الضريبي', 'vat|vat no|vat number|الرقم الضريبي'], ['cr_no', 'السجل التجاري', 'cr|cr no|commercial registration|السجل'],
  ['phone', 'الهاتف', 'phone|mobile|الجوال|الهاتف'], ['email', 'البريد الإلكتروني', 'email|e-mail|البريد'], ['contact_name', 'الشخص المسؤول', 'contact|contact person|المسؤول'],
  ['country', 'رمز الدولة', 'country|الدولة'], ['city', 'المدينة', 'city|المدينة'], ['district', 'الحي', 'district|الحي'], ['street', 'الشارع', 'street|الشارع'],
  ['bld_no', 'رقم المبنى', 'building|building no|رقم المبنى'], ['postal_code', 'الرمز البريدي', 'postal code|zip|الرمز البريدي'], ['add_no', 'الرقم الإضافي', 'additional no|الرقم الاضافي'],
  ['short_address', 'العنوان المختصر', 'short address|العنوان المختصر'], ['terms_days', 'مدة السداد (يوم)', 'terms|payment terms|مدة السداد'],
  ['credit_limit', 'حد الائتمان', 'credit limit|حد الائتمان'], ['iban', 'الآيبان', 'iban|الايبان'], ['note', 'ملاحظات', 'note|notes|ملاحظات']];
VIEWS['#/parties'] = async (page, kind) => {
  kind = kind === 'supplier' ? 'supplier' : 'customer';
  const cust = kind === 'customer', rows = await db.get('parties', Object.assign(C(), { kind: 'eq.' + kind, order: 'active.desc,name' }));
  const scm = {}; if (!cust) (await db.rpc('supplier_scorecard', { p_company: S.cid }).catch(() => [])).forEach(x => scm[x.party_id] = x);
  const T = cust ? ['العملاء', 'عميل'] : ['الموردون', 'مورد'];
  page.innerHTML = `<div class="head"><div><h1>${T[0]}</h1></div><div class="row"><button class="btn" id="pim">استيراد من Excel</button><button class="btn pri" id="np">إضافة ${T[1]}</button></div></div>
    ${tbl([{ t: 'الاسم', h: p => esc(p.name) + (p.active === false ? ` <span class="badge">${esc(tr('موقوف'))}</span>` : '') }, { t: 'الرقم الضريبي', h: p => `<span class="num">${esc(p.vat_no || '—')}</span>` }, { t: 'الجوال', h: p => `<span class="num">${esc(p.phone || '—')}</span>` },
      { t: 'المدينة', h: p => esc(p.city || '—') + (p.country && p.country !== 'SA' ? ` <span class="muted num">${esc(p.country)}</span>` : '') }, { t: 'مدة السداد', h: p => p.terms_days ? `<span class="num">${p.terms_days}</span> ${esc(tr('يوماً'))}` : '—' },
      ...(cust ? [{ t: 'حد الائتمان', r: 1, h: p => p.credit_limit != null ? money(p.credit_limit) : '—' }] : [{ t: 'التقييم', h: p => { const x = scm[p.id]; return x && x.ratings ? `★ <span class="num">${x.overall}</span> <span class="small muted">(${x.ratings})</span>` : '—'; } },
        { t: 'الالتزام بالمواعيد', r: 1, h: p => { const x = scm[p.id]; return x && x.on_time_pct != null ? `<span class="num">${x.on_time_pct}%</span>` : '—'; } }]),
      { t: '', h: p => `<a class="btn sm" href="#/statement/${p.id}" data-st>${esc(tr('كشف حساب'))}</a>` }], rows, { empty: 'لا يوجد ' + T[0], onRow: true })}`;
  $$('[data-st]', page).forEach(a => a.addEventListener('click', e => e.stopPropagation()));
  const form = p => {
    const saudi = !p || !p.country || p.country === 'SA';
    const d = modal(p ? 'تعديل ' + T[1] : 'إضافة ' + T[1], `<div class="fg">${field('الاسم', inp('name', p && p.name, 'required'), 'wide')}${enF('name_en', p && p.name_en, undefined, 'wide')}
      ${field('الموقع', `<select name="loc" id="ploc">${opt('SA', 'داخل المملكة', saudi ? 'SA' : 'X')}${opt('X', 'خارج المملكة', saudi ? 'SA' : 'X')}</select>`)}<div id="pcw" ${saudi ? 'hidden' : ''}>${field('رمز الدولة', inp('country', saudi ? '' : p.country, 'dir="ltr" maxlength="2" placeholder="AE" style="text-transform:uppercase"'))}</div>
      ${field('الرقم الضريبي', inp('vat_no', p && p.vat_no, 'dir="ltr" inputmode="numeric" maxlength="15"'))}${field('السجل التجاري', inp('cr_no', p && p.cr_no, 'dir="ltr" inputmode="numeric" maxlength="10"'))}
      <h3 class="wide" style="margin:8px 0 0">${esc(tr('التواصل'))}</h3>${field('الشخص المسؤول', inp('contact_name', p && p.contact_name))}${field('الهاتف', inp('phone', p && p.phone, 'dir="ltr" placeholder="05XXXXXXXX"'))}${field('البريد الإلكتروني', inp('email', p && p.email, 'type="email" dir="ltr"'))}
      <h3 class="wide" style="margin:8px 0 0">${esc(tr('العنوان الوطني'))}</h3><p class="wide muted small" style="margin:0">${esc(tr(cust ? 'مطلوب في الفاتورة الضريبية للعميل المسجل في ضريبة القيمة المضافة.' : 'يظهر في أوامر الشراء.'))}</p>${addrFields(p, saudi)}
      <h3 class="wide" style="margin:8px 0 0">${esc(tr('الدفع'))}</h3>${field('مدة السداد (يوم)', inp('terms_days', p && p.terms_days, 'type="number" min="0" max="365" step="1"'))}
      ${cust ? field('حد الائتمان (ريال)', inp('credit_limit', p && p.credit_limit, 'type="number" min="0" step="0.01" placeholder="' + esc(tr('بدون حد')) + '"')) : ''}
      ${field('الآيبان', inp('iban', p && p.iban, 'dir="ltr" maxlength="34" id="piban"') + '<div class="small muted" id="pibk"></div>')}
      ${field('ملاحظات', inp('note', p && p.note), 'wide')}${p ? field('الحالة', `<label class="row" style="gap:6px"><input type="checkbox" name="active" ${p.active !== false ? 'checked' : ''}> ${esc(tr('نشط — يظهر في الفواتير والأوامر الجديدة'))}</label>`, 'wide') : ''}</div>`, {
      wide: true, onOk: async f => {
        if (f.vat_no && !/^3\d{13}3$/.test(f.vat_no)) throw new Error('الرقم الضريبي 15 رقماً يبدأ وينتهي بـ 3');
        if (f.cr_no && !/^\d{10}$/.test(f.cr_no)) throw new Error('السجل التجاري 10 أرقام');
        const out = f.loc === 'X', country = out ? (f.country || '').trim().toUpperCase() : 'SA';
        if (out && !/^[A-Z]{2}$/.test(country)) throw new Error('رمز الدولة حرفان مثل AE');
        const row = { name: f.name.trim(), name_en: blank((f.name_en || '').trim()), vat_no: blank(f.vat_no), cr_no: blank(f.cr_no), phone: blank(f.phone), country, contact_name: blank(f.contact_name), email: blank(f.email),
          iban: blank(f.iban), note: blank(f.note), terms_days: f.terms_days === '' ? null : +f.terms_days };
        SA_ADDR.forEach(([k]) => row[k] = blank(f[k]));
        if (cust) row.credit_limit = f.credit_limit === '' ? null : +f.credit_limit;
        if (p) row.active = !!f.active;
        if (p) await db.upd('parties', { id: 'eq.' + p.id }, row); else await db.ins('parties', Object.assign(row, { company_id: S.cid, kind }));
        toast('تم الحفظ'); route();
      }
    });
    $('#ploc', d).onchange = e => { $('#pcw', d).hidden = e.target.value === 'SA'; };
    const ib = () => { $('#pibk', d).textContent = ibanBank($('#piban', d).value); }; $('#piban', d).oninput = ib; ib();
  };
  $('#np', page).onclick = () => form(null); bindRows(page, rows, form);
  $('#pim', page).onclick = () => partyImport(kind, T);
};
/* ===== customer / supplier statement ===== */
const ST_KIND = { opening_balance: 'رصيد أول المدة', opening: 'رصيد افتتاحي', invoice: 'فاتورة مبيعات', bill: 'فاتورة مشتريات', receipt: 'سند قبض', payment: 'سند صرف', credit_note: 'إشعار دائن', debit_note: 'إشعار مدين' };
VIEWS['#/statement'] = async (page, id, q) => {
  const [p] = await db.get('parties', { id: 'eq.' + id });
  if (!p) { page.innerHTML = '<div class="note">' + esc(tr('الطرف غير موجود')) + '</div>'; return; }
  const cust = p.kind === 'customer', y = today().slice(0, 4), from = q.get('from') || y + '-01-01', to = q.get('to') || today();
  const rows = await db.rpc('party_statement', { p_party: id, p_from: from, p_to: to });
  const last = rows.length ? rows[rows.length - 1].balance : 0, dr = rows.slice(1).reduce((a, r) => a + n0(r.debit), 0), cr = rows.slice(1).reduce((a, r) => a + n0(r.credit), 0);
  const link = r => r.doc_id && ['invoice', 'opening'].includes(r.kind) && cust ? `#/sales/${r.doc_id}` : r.doc_id && ['bill', 'opening'].includes(r.kind) && !cust ? `#/purchases/${r.doc_id}` : '';
  page.innerHTML = `<div class="head"><div><a href="#/parties/${p.kind}" class="small">← ${esc(tr(cust ? 'العملاء' : 'الموردون'))}</a><h1>${esc(tr('كشف حساب'))} — ${esc(p.name)}</h1>
      <div class="muted">${esc(tr(cust ? 'الرصيد الموجب = مستحق لنا على العميل' : 'الرصيد الموجب = مستحق للمورد علينا'))}</div></div><button class="btn" id="stp">${esc(tr('طباعة / PDF'))}</button></div>
    <form id="stf" class="row" style="margin-bottom:12px">${field('من', `<input type="date" name="from" value="${from}">`)}${field('إلى', `<input type="date" name="to" value="${to}">`)}<button class="btn" style="align-self:end">${esc(tr('عرض'))}</button></form>
    <div id="stb"><div class="grid" style="margin-bottom:12px"><div class="card kpi"><div class="muted small">${esc(tr('مدين'))}</div><div class="v num">${money(dr)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('دائن'))}</div><div class="v num">${money(cr)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('الرصيد في'))} <span class="num">${esc(to)}</span></div><div class="v num">${money(last)}</div></div></div>
    ${tbl([{ t: 'التاريخ', h: r => fdate(r.d) }, { t: 'البيان', h: r => esc(tr(ST_KIND[r.kind] || r.kind)) }, { t: 'الرقم', h: r => r.no ? (link(r) ? `<a href="${link(r)}" class="num">${esc(r.no)}</a>` : `<span class="num">${esc(r.no)}</span>`) : '' },
      { t: 'المرجع', h: r => esc(r.ref || '') }, { t: 'مدين', r: 1, h: r => n0(r.debit) ? money(r.debit) : '' }, { t: 'دائن', r: 1, h: r => n0(r.credit) ? money(r.credit) : '' }, { t: 'الرصيد', r: 1, h: r => '<b>' + money(r.balance) + '</b>' }], rows, { empty: 'لا توجد حركات' })}</div>`;
  $('#stf', page).onsubmit = e => { e.preventDefault(); const f = formData(e.target); location.hash = `#/statement/${id}?from=${f.from}&to=${f.to}`; };
  $('#stp', page).onclick = () => { const w = document.createElement('div');
    w.innerHTML = `<p><b>${esc(tr(cust ? 'العميل' : 'المورد'))}:</b> ${esc(p.name)}${p.vat_no ? ' · ' + esc(tr('الرقم الضريبي')) + ' <span class="num">' + esc(p.vat_no) + '</span>' : ''}${addrLine(p) ? '<br>' + esc(addrLine(p)) : ''}<br>
      <b>${esc(tr('الفترة'))}:</b> <span class="num">${esc(from)} — ${esc(to)}</span></p>` + $('#stb', page).innerHTML;
    printBlock(w, tr('كشف حساب') + ' — ' + p.name); };
};
function partyImport(kind, T) {
  const d = modal(tr('استيراد') + ' ' + tr(T[0]) + ' ' + tr('من Excel'), `<ol class="small" style="padding-inline-start:18px;margin-top:0"><li>${esc(tr('نزّل القالب واملأ سطراً لكل اسم — الاسم وحده مطلوب.'))}</li>
    <li>${esc(tr('الاسم الموجود مسبقاً تُحدَّث بياناته من الخانات المعبأة فقط، والجديد يُضاف.'))}</li><li>${esc(tr('رمز الدولة فارغ = داخل المملكة.'))}</li></ol>
    <div class="row"><button type="button" class="btn" id="ptpl">${esc(tr('تنزيل القالب'))}</button><label class="btn pri" style="margin:0;color:var(--prim-ink)">${esc(tr('اختيار الملف'))}<input type="file" id="pimf" accept=".xlsx,.csv,text/csv" hidden></label></div><div id="pimp"></div>`, { wide: true });
  const cols = PARTY_COLS.filter(c => kind === 'customer' || c[0] !== 'credit_limit');
  $('#ptpl', d).onclick = () => { const a = document.createElement('a'); a.href = URL.createObjectURL(templateXlsx([cols.map(c => tr(c[1]) + (c[3] ? ' *' : ''))])); a.download = kind === 'customer' ? 'waad-customers.xlsx' : 'waad-suppliers.xlsx'; a.click(); };
  $('#pimf', d).onchange = async ev => {
    const file = ev.target.files[0]; if (!file) return; const box = $('#pimp', d);
    try {
      const { hdr, body } = await readSheetFile(file), idx = mapHeadersBy(cols, hdr);
      if (!('name' in idx)) throw new Error('عمود الاسم غير موجود — استخدم القالب');
      if (!body.length) throw new Error('لا توجد صفوف تحت العناوين');
      if (body.length > 3000) throw new Error('الحد الأقصى 3000 سطر في الملف الواحد');
      const seen = {}, items = body.map(({ r, no }) => { const x = { _row: no }, errs = [];
        cols.forEach(([k]) => { if (idx[k] != null) { const v = arDigits(String(r[idx[k]] == null ? '' : r[idx[k]]).trim()); if (v) x[k] = v; } });
        const nm = (x.name || '').replace(/\s+/g, ' ');
        if (nm.length < 3) errs.push(tr('الاسم مطلوب')); else if (seen[nm]) errs.push(tr('الاسم مكرر في الملف')); seen[nm] = 1;
        if (x.vat_no && !/^3\d{13}3$/.test(x.vat_no)) errs.push(tr('الرقم الضريبي 15 رقماً يبدأ وينتهي بـ 3'));
        if (x.cr_no && !/^\d{10}$/.test(x.cr_no)) errs.push(tr('السجل التجاري 10 أرقام'));
        if (x.terms_days && !/^\d{1,3}$/.test(x.terms_days)) errs.push(tr('مدة السداد أرقام فقط'));
        if (x.credit_limit && !(+x.credit_limit >= 0)) errs.push(tr('حد الائتمان أرقام فقط'));
        return { x, errs }; });
      const bad = items.filter(i => i.errs.length);
      box.innerHTML = `<div class="${bad.length ? 'err' : 'note'}">${items.length} ${esc(tr('سطر في الملف'))}${bad.length ? ` — ${bad.length} ${esc(tr('سطر فيه أخطاء، صحّحها في الملف ثم ارفعه مجدداً'))}` : ' — ' + esc(tr('جاهز للاستيراد'))}</div>
        ${tbl([{ t: 'السطر', h: i => i.x._row }, { t: 'الاسم', h: i => esc(i.x.name || '') }, { t: 'الرقم الضريبي', h: i => `<span class="num">${esc(i.x.vat_no || '')}</span>` }, { t: 'المدينة', h: i => esc(i.x.city || '') },
          { t: 'الملاحظات', h: i => i.errs.length ? `<span class="bad">${esc(i.errs.join('، '))}</span>` : '<span class="ok">✓</span>' }], (bad.length ? bad : items).slice(0, 300))}
        ${bad.length ? '' : `<div class="row" style="margin-top:12px"><button type="button" class="btn pri" id="pgo">${esc(tr('استيراد'))} ${items.length} ${esc(tr('سطر'))}</button></div><div id="pier"></div>`}`;
      if ($('#pgo', d)) $('#pgo', d).onclick = async () => { try { await busy($('#pgo', d), async () => {
        const res = await db.rpc('import_parties', { p_company: S.cid, p_kind: kind, p_rows: items.map(i => i.x) }); d.close();
        toast(tr('أُضيف') + ' ' + res.added + ' · ' + tr('حُدّث') + ' ' + res.updated); route(); }); } catch (er) { showErr($('#pier', d), er); } };
    } catch (er) { showErr(box, er); }
    ev.target.value = '';
  };
}

/* ===== items & stock ===== */
async function stockMap() {
  if (!can('stock')) return {};
  const mv = await db.get('stock_moves', Object.assign(C(), { select: 'item_id,qty,value' }));
  const m = {}; mv.forEach(x => { const s = m[x.item_id] || (m[x.item_id] = { qty: 0, value: 0 }); s.qty += n0(x.qty); s.value += n0(x.value); });
  Object.values(m).forEach(s => s.avg = s.qty > 0 ? s.value / s.qty : 0); return m;
}

/* ===== sales invoices & purchase bills (shared) ===== */
const DOCS = {
  sales: { t: 'المبيعات', one: 'فاتورة مبيعات', table: 'sales_invoices', lines: 'sales_invoice_lines', fk: 'invoice_id', party: 'customer', perm: 'sales', rpc: 'post_sales_invoice_sn', void: 'void_sales_invoice', payDir: 'in', payKey: 'invoice', cnKind: 'sales', cnT: 'إشعار دائن (مرتجع مبيعات)' },
  purchases: { t: 'المشتريات', one: 'فاتورة مشتريات', table: 'purchase_bills', lines: 'purchase_bill_lines', fk: 'bill_id', party: 'supplier', perm: 'purch', rpc: 'post_purchase_bill_wh', void: 'void_purchase_bill', payDir: 'out', payKey: 'bill', cnKind: 'purchase', cnT: 'إشعار مدين (مرتجع مشتريات)' },
};
async function paidMap(D, ids) {
  if (!ids.length) return {};
  const [pays, cns] = await Promise.all([db.get('payments', { [D.payKey + '_id']: 'in.(' + ids.join(',') + ')', select: D.payKey + '_id,amount' }), db.get('credit_notes', { doc_id: 'in.(' + ids.join(',') + ')', select: 'doc_id,total' })]);
  const m = {}; pays.forEach(p => m[p[D.payKey + '_id']] = (m[p[D.payKey + '_id']] || 0) + n0(p.amount)); cns.forEach(c => m[c.doc_id] = (m[c.doc_id] || 0) + n0(c.total)); return m;
}
function docList(key) {
  return async (page, arg) => {
    const D = DOCS[key];
    if (arg === 'new') return docForm(page, key);
    if (arg) return docView(page, key, arg);
    const [docs, parties] = await Promise.all([db.get(D.table, Object.assign(C(), { order: 'date.desc,no.desc', limit: 300 })), db.get('parties', Object.assign(C(), { kind: 'eq.' + D.party, select: 'id,name' }))]);
    const pm = {}; parties.forEach(p => pm[p.id] = p.name);
    const paid = await paidMap(D, docs.filter(d => d.status === 'posted').map(d => d.id));
    page.innerHTML = `<div class="head"><div><h1>${D.t}</h1></div><a class="btn pri" href="#/${key}/new">${D.one} جديدة</a></div>
      ${tbl([{ t: 'الرقم', h: d => `<span class="num">${esc(d.no)}</span>` }, ...(key === 'purchases' ? [{ t: 'رقم المورد', h: d => `<span class="num">${esc(d.supplier_ref || '—')}</span>` }] : []), { t: 'التاريخ', h: d => fdate(d.date) }, { t: key === 'sales' ? 'العميل' : 'المورد', h: d => esc(pm[d.party_id] || '') },
        { t: 'الإجمالي', r: 1, h: d => money(d.total) }, { t: 'المتبقي', r: 1, h: d => { if (d.status !== 'posted') return '—'; const x = r2(n0(d.total) - n0(paid[d.id])); return x < -0.001 ? `<span class="ok">رصيد دائن ${money(-x)}</span>` : money(x); } },
        { t: 'الحالة', h: d => d.status === 'void' ? badge('void') : n0(d.total) - n0(paid[d.id]) <= 0.001 ? '<span class="badge ok">مسددة</span>' : d.due_date < today() ? '<span class="badge bad">متأخرة</span>' : '<span class="badge wait">مستحقة</span>' }],
        docs, { empty: 'لا توجد فواتير', onRow: true })}`;
    bindRows(page, docs, d => location.hash = `#/${key}/${d.id}`);
  };
}
VIEWS['#/sales'] = docList('sales'); VIEWS['#/purchases'] = docList('purchases');

async function docForm(page, key) {
  const D = DOCS[key];
  const [allParties, items, acc] = await Promise.all([db.get('parties', Object.assign(C(), { kind: 'eq.' + D.party, order: 'name' })), db.get('items', Object.assign(C(), { order: 'code' })), accounts()]);
  const parties = allParties.filter(p => p.active !== false), units = await db.get('item_units', Object.assign(C(), { select: 'item_id,name,name_en,factor,barcode' })).catch(() => []);
  const expAcc = acc.filter(a => !a.is_header && (a.type === 'exp' || a.type === 'asset') && !['1110', '1120', '1200', '1300', '1400'].includes(a.code) && a.parent_code !== '1100');
  if (!parties.length) { page.innerHTML = `<div class="note">أضف ${key === 'sales' ? 'عميلاً' : 'مورداً'} أولاً. <a href="#/parties/${D.party}">${key === 'sales' ? 'العملاء' : 'الموردون'}</a></div>`; return; }
  const lines = [{}], whf = await whField(null, key === 'sales' ? 'يُصرف من مستودع' : 'يُستلم في مستودع'), ccf = await ccField(null), curs = await currencies();
  const fxf = curs.length ? field('العملة', `<select name="currency" id="dcur"><option value="">${esc(tr('ريال سعودي'))} (SAR)</option>${curs.map(c => opt(c.code, c.code + ' — ' + ((LANG === 'en' && c.name_en) || c.name))).join('')}</select>`) + `<div id="dfxw" hidden>${field('سعر الصرف (ريال للوحدة)', inp('fx_rate', '', 'type="number" step="0.000001" min="0.000001" id="dfx"'))}</div>` : '';
  page.innerHTML = `<div class="head"><div><a href="#/${key}" class="small">← ${D.t}</a><h1>${D.one} جديدة</h1></div></div><form id="df" class="card" novalidate>
    <div class="fg">${field(key === 'sales' ? 'العميل' : 'المورد', `<select name="party" id="dpt">${parties.map(p => opt(p.id, p.name)).join('')}</select>`)}${field('التاريخ', `<input type="date" name="date" id="ddt" value="${today()}" max="${today()}">`)}${field('تاريخ الاستحقاق', `<input type="date" name="due" id="ddu" value="${today()}">`)}<div class="wide small muted" id="pcr"></div>
      ${key === 'purchases' ? field('رقم فاتورة المورد', inp('ref', '', 'dir="ltr"')) : ''}${whf}${ccf}${fxf}${field('ملاحظات', inp('note'), 'wide')}</div>
    <div style="height:14px"></div><div class="tw"><table class="lines"><thead><tr><th>${key === 'purchases' ? 'صنف أو حساب مصروف' : 'الصنف'}</th><th>الكمية</th><th>السعر</th><th>الضريبة</th><th class="r">المبلغ</th><th></th></tr></thead><tbody id="lb"></tbody>
    <tfoot><tr><td colspan="4">الإجمالي قبل الضريبة</td><td class="r num" id="ts">0.00</td><td></td></tr><tr><td colspan="4">ضريبة القيمة المضافة</td><td class="r num" id="tv">0.00</td><td></td></tr><tr><td colspan="4">الإجمالي</td><td class="r num" id="tt">0.00</td><td></td></tr><tr id="tsr" hidden><td colspan="4">${esc(tr('المعادل بالريال'))}</td><td class="r num" id="tsar"></td><td></td></tr></tfoot></table></div>
    <div class="row" style="margin-top:10px"><button type="button" class="btn sm" id="al">+ بند</button><input id="dbc" dir="ltr" autocomplete="off" placeholder="${esc(tr('باركود أو رمز الصنف ثم Enter'))}" style="max-width:260px" aria-label="${esc(tr('باركود'))}"><span class="small muted" id="dbm"></span></div><div id="derr"></div>
    <div class="row" style="margin-top:14px"><button class="btn pri" id="ds">ترحيل الفاتورة</button><a class="btn" href="#/${key}">إلغاء</a></div></form>`;
  const itemOpts = items.filter(i => i.active !== false).map(i => opt('i:' + i.id, i.code + ' — ' + i.name)).join('');
  const accOpts = key === 'purchases' ? `<optgroup label="حسابات المصروفات">${expAcc.map(a => opt('a:' + a.code, a.code + ' — ' + a.name)).join('')}</optgroup>` : '';
  const draw = () => {
    $('#lb', page).innerHTML = lines.map((l, i) => { const it = l.what && l.what.startsWith('i:') ? items.find(x => x.id === l.what.slice(2)) : null, us = it ? units.filter(u => u.item_id === it.id) : [];
      return `<tr data-i="${i}"><td style="min-width:220px"><select data-f="what"><option value="">—</option>${itemOpts}${accOpts}</select>${it && it.track_serial && key === 'sales' ? `<textarea data-f="sn" rows="2" dir="ltr" placeholder="${esc(tr('الأرقام التسلسلية — رقم في كل سطر'))}" style="margin-top:4px">${esc(l.sn || '')}</textarea>` : ''}</td><td><input data-f="qty" type="number" step="0.001" min="0" value="${esc(l.qty || 1)}" style="width:90px">${us.length ? `<select data-f="u" style="width:110px;margin-top:4px" aria-label="${esc(tr('الوحدة'))}">${opt(1, it.unit || tr('الوحدة الأساسية'), l.u || 1)}${us.map(u => opt(+u.factor, ((LANG === 'en' && u.name_en) || u.name) + ' (' + (+u.factor) + ')', l.u || 1)).join('')}</select>` : ''}</td><td><input data-f="price" type="number" step="0.01" min="0" value="${esc(l.price || '')}" style="width:120px"></td><td><select data-f="vat" style="width:90px">${opt(15, '15%', l.vat == null ? 15 : l.vat)}${opt(0, '0%', l.vat)}</select></td><td class="r num" data-amt></td><td><button type="button" class="btn sm" data-rm aria-label="حذف البند">×</button></td></tr>`; }).join('');
    $$('tr', $('#lb', page)).forEach(tr => { const l = lines[+tr.dataset.i]; $('[data-f=what]', tr).value = l.what || ''; });
    calc();
  };
  const calc = () => { let s = 0, v = 0; $$('tr', $('#lb', page)).forEach(tr => { const l = lines[+tr.dataset.i]; const a = r2(n0(l.qty == null ? 1 : l.qty) * n0(l.u || 1) * n0(l.price)); const t = r2(a * n0(l.vat == null ? 15 : l.vat) / 100); s += a; v += t; $('[data-amt]', tr).textContent = money(a); }); $('#ts', page).textContent = money(s); $('#tv', page).textContent = money(v); $('#tt', page).textContent = money(s + v); const cu = $('#dcur', page) && $('#dcur', page).value; if ($('#tsr', page)) { $('#tsr', page).hidden = !cu; if (cu) $('#tsar', page).textContent = money((s + v) * n0($('#dfx', page).value)); } };
  $('#lb', page).addEventListener('input', e => { const tr = e.target.closest('tr'); if (!tr) return; const l = lines[+tr.dataset.i]; const f = e.target.dataset.f; l[f] = e.target.value;
    if (f === 'what') { l.u = 1; l.sn = ''; if (l.what.startsWith('i:')) { const it = items.find(x => x.id === l.what.slice(2)); if (it) itemDefaults(l, it); } return draw(); } calc(); });
  $('#lb', page).addEventListener('change', e => { if (e.target.dataset.f === 'u') { lines[+e.target.closest('tr').dataset.i].u = +e.target.value; calc(); } });
  $('#lb', page).addEventListener('click', e => { if (e.target.matches('[data-rm]')) { lines.splice(+e.target.closest('tr').dataset.i, 1); if (!lines.length) lines.push({}); draw(); } });
  $('#al', page).onclick = () => { lines.push({}); draw(); };
  // price and VAT come from the item card: sale price on sales, purchase price on purchases
  function itemDefaults(l, it) { const pr = key === 'sales' ? it.sale_price : it.purchase_price; if (!l.price && pr != null) l.price = pr; l.vat = n0(it.vat_rate == null ? 15 : it.vat_rate); }
  // scanner or typed barcode/code: adds the item (or one more of it) as a line
  $('#dbc', page).onkeydown = e => { if (e.key !== 'Enter') return; e.preventDefault(); const v = e.target.value.trim(); if (!v) return;
    const un = units.find(u => u.barcode === v), it = un ? items.find(i => i.id === un.item_id && i.active !== false) : items.find(i => i.active !== false && (i.barcode === v || String(i.code).toLowerCase() === v.toLowerCase()));
    if (!it) { $('#dbm', page).textContent = tr('لا يوجد صنف بهذا الباركود أو الرمز'); return; } $('#dbm', page).textContent = '';
    const fu = un ? +un.factor : 1, ex = lines.find(l => l.what === 'i:' + it.id && n0(l.u || 1) === fu);
    if (ex) ex.qty = n0(ex.qty == null ? 1 : ex.qty) + 1; else { const blankL = lines.find(l => !l.what), l = blankL || {}; l.what = 'i:' + it.id; l.qty = 1; l.u = fu; itemDefaults(l, it); if (!blankL) lines.push(l); }
    e.target.value = ''; draw(); };
  if ($('#dcur', page)) { $('#dcur', page).onchange = e => { const c = curs.find(x => x.code === e.target.value); $('#dfxw', page).hidden = !c; $('#dfx', page).value = c ? +c.rate : ''; calc(); }; $('#dfx', page).oninput = calc; }
  // payment terms fill the due date (until the user changes it); a customer's credit limit is shown and checked
  let dueTouched = false, credit = null;
  const partyNow = () => parties.find(p => p.id === $('#dpt', page).value) || {};
  const syncParty = async () => {
    const p = partyNow(); if (!dueTouched) $('#ddu', page).value = addDays($('#ddt', page).value || today(), n0(p.terms_days));
    credit = null; $('#pcr', page).textContent = '';
    const bits = []; if (p.terms_days) bits.push(tr('مدة السداد') + ' ' + p.terms_days + ' ' + tr('يوماً'));
    if (key === 'sales' && p.credit_limit != null) { try { [credit] = await db.rpc('party_credit', { p_party: p.id }); } catch (e) { credit = null; }
      if (credit && partyNow().id === p.id) bits.push(tr('الرصيد') + ' ' + money(credit.balance) + ' · ' + tr('حد الائتمان') + ' ' + money(credit.credit_limit)); }
    $('#pcr', page).textContent = bits.join(' · ');
  };
  $('#dpt', page).onchange = syncParty; $('#ddt', page).onchange = () => { if (!dueTouched) syncParty(); }; $('#ddu', page).oninput = () => { dueTouched = true; };
  draw(); syncParty();
  $('#df', page).onsubmit = async e => {
    e.preventDefault(); const f = formData(e.target);
    if (credit && credit.credit_limit != null) {
      const tot = n0(($('#tt', page).textContent || '0').replace(/[^\d.]/g, '')) * (f.currency ? n0(f.fx_rate) : 1), after = n0(credit.balance) + tot;
      if (after > n0(credit.credit_limit)) {
        if (!has('owner', 'admin', 'finance')) return showErr($('#derr', page), tr('تجاوز حد الائتمان للعميل') + ': ' + money(after) + ' > ' + money(credit.credit_limit) + ' — ' + tr('يعتمدها المدير المالي أو المالك'));
        if (!await confirmBox(tr('تجاوز حد الائتمان'), tr('رصيد العميل بعد هذه الفاتورة') + ' ' + money(after) + ' ' + tr('وحد الائتمان') + ' ' + money(credit.credit_limit) + '. ' + tr('ترحيل الفاتورة رغم ذلك؟'), 'ترحيل')) return;
      }
    }
    const ls = lines.filter(l => l.what).map(l => { const o = { qty: r2(+(l.qty == null ? 1 : l.qty) * n0(l.u || 1) * 1000) / 1000, price: +l.price, vat: +(l.vat == null ? 15 : l.vat) }; if (l.sn) o.serials = snSplit(l.sn); if (l.what.startsWith('i:')) o.item = l.what.slice(2); else o.account = l.what.slice(2); return o; });
    if (!ls.length) return showErr($('#derr', page), 'أضف بنداً واحداً على الأقل');
    if (ls.some(l => !(l.qty > 0) || !(l.price >= 0))) return showErr($('#derr', page), 'تحقق من الكميات والأسعار');
    const doc = { party: f.party, date: f.date, due: f.due || f.date, note: blank(f.note), warehouse: blank(f.warehouse), cost_center: blank(f.cost_center), currency: blank(f.currency), fx_rate: f.currency ? +f.fx_rate : null, lines: ls }; if (key === 'purchases') doc.ref = blank(f.ref);
    try { await busy($('#ds', page), async () => { const id = await db.rpc(D.rpc, { p_company: S.cid, p_doc: doc }); toast('رُحّلت الفاتورة'); location.hash = `#/${key}/${id}`; }); } catch (er) { showErr($('#derr', page), er); }
  };
}

async function docView(page, key, id) {
  const D = DOCS[key];
  const [[doc], lines, items, acc] = await Promise.all([db.get(D.table, { id: 'eq.' + id }), db.get(D.lines, { [D.fk]: 'eq.' + id, order: 'id' }), db.get('items', Object.assign(C(), { select: 'id,code,name,name_en' })), accounts()]);
  if (!doc) throw new Error('الفاتورة غير موجودة');
  const [[party], pays, cns] = await Promise.all([db.get('parties', { id: 'eq.' + doc.party_id }), db.get('payments', { [D.payKey + '_id']: 'eq.' + id, order: 'date' }), db.get('credit_notes', { doc_id: 'eq.' + id, order: 'date' })]);
  const im = {}; items.forEach(i => im[i.id] = i); const am = {}; acc.forEach(a => am[a.code] = a.name);
  // ZATCA Phase 2: the document's place in the Fatoora chain (status, QR) and, for a debit note, the invoice it adds to
  const zm = {}; if (key === 'sales') (await db.get('zatca_docs', { doc_id: 'in.(' + [id, ...cns.map(c => c.id)].join(',') + ')', select: 'doc_id,icv,status,last_error,qr,sent_at,inv_type' }).catch(() => [])).forEach(z => { zm[z.doc_id] = z; });
  doc._zqr = zm[id] && zm[id].qr; cns.forEach(c => { c._zqr = zm[c.id] && zm[c.id].qr; });
  const [ref] = doc.ref_id ? await db.get('sales_invoices', { id: 'eq.' + doc.ref_id, select: 'id,no' }).catch(() => []) : [], isDn = doc.doc_type === 'debit';
  const paid = pays.reduce((a, p) => a + n0(p.amount), 0) + cns.reduce((a, c) => a + n0(c.total), 0), rem = r2(n0(doc.total) - paid);
  const wmm = await whMap(), whTxt = Object.keys(wmm).length > 1 && doc.warehouse_id ? ' · ' + esc(whName(wmm[doc.warehouse_id])) : '';
  const fxRem = doc.currency ? r2(n0(doc.fx_total) * rem / n0(doc.total)) : 0, fxTxt = doc.currency ? `<p>${esc(tr('العملة'))} <b>${esc(doc.currency)}</b> · ${esc(tr('سعر الصرف'))} <span class="num">${+doc.fx_rate}</span> · ${esc(tr('الإجمالي'))} <b class="num">${money(doc.fx_total)} ${esc(doc.currency)}</b> · ${esc(tr('المتبقي'))} <b class="num">${money(fxRem)} ${esc(doc.currency)}</b></p>` : '';
  const ccTxt = doc.cost_center_id ? ' · ' + esc(ccName((await ccList()).find(c => c.id === doc.cost_center_id))) : '';
  const co = S.company, [so] = doc.order_id ? await db.get(key === 'sales' ? 'sales_orders' : 'purchase_orders', { id: 'eq.' + doc.order_id, select: 'id,no' }) : [];
  page.innerHTML = `<div class="head"><div><a href="#/${key}" class="small">← ${D.t}</a><h1>${isDn ? esc(tr('إشعار مدين')) : D.one} <span class="num">${esc(doc.no)}</span> ${badge(doc.status)}</h1><div class="muted">${esc(party ? party.name : '')} · ${fdate(doc.date)}${ref ? ` · ${esc(tr('على الفاتورة'))} <a href="#/sales/${ref.id}" class="num">${esc(ref.no)}</a>` : ''}${doc.reason ? ' · ' + esc(doc.reason) : ''}${doc.supplier_ref ? ' · رقم المورد ' + esc(doc.supplier_ref) : ''}${whTxt}${ccTxt}${so ? ` · ${key === 'sales' ? 'أمر البيع' : 'أمر الشراء'} <a href="#/${key === 'sales' ? 'orders' : 'porders'}/${so.id}" class="num">${esc(so.no)}</a>` : ''}</div></div>
    <div class="row">${doc.status === 'posted' && rem > 0.001 ? `<button class="btn pri" id="pay">${key === 'sales' ? 'تسجيل قبض' : 'تسجيل صرف'}</button>` : ''}${doc.status === 'posted' && rem > 0.001 && !doc.currency ? '<button class="btn" id="chq">شيك</button>' : ''}${doc.status === 'posted' && can('void') && !doc.is_opening ? `<button class="btn" id="cn">${key === 'sales' ? 'إشعار دائن' : 'مرتجع'}</button>` : ''}${key === 'sales' && doc.status === 'posted' && !doc.is_opening && !isDn && can('sales') ? `<button class="btn" id="dn">${esc(tr('إشعار مدين'))}</button>` : ''}${doc.status === 'posted' && can('void') && paid === 0 && !doc.is_opening && !zm[id] ? '<button class="btn danger" id="vd">إلغاء الفاتورة</button>' : ''}${doc.is_opening ? '' : '<button class="btn" id="dprint">طباعة</button>'}</div></div>
    ${zm[id] ? zatcaBox(zm[id]) : ''}
    <div class="card" id="dcard">${doc.is_opening ? `<p><span class="badge info">${esc(tr('رصيد افتتاحي'))}</span></p>` : ''}${key === 'sales' && !doc.is_opening ? `<div class="row" style="justify-content:space-between;align-items:flex-start"><div class="ph-dup"><b>${esc(co.name)}</b><div class="small muted">${co.vat_no ? 'الرقم الضريبي ' + esc(co.vat_no) : 'لا يوجد رقم ضريبي مسجّل'}</div></div><div style="text-align:end"><b>فاتورة ضريبية${party && party.vat_no ? '' : ' مبسطة'}</b><div class="small muted">${esc(party ? party.name : '')}${party && party.vat_no ? ' · ' + esc(party.vat_no) : ''}</div></div>${co.vat_no ? `<div class="dqr" title="رمز الفاتورة الإلكترونية (زاتكا)">${zatcaQr(doc, 96)}</div>` : ''}</div>${co.vat_no ? '' : '<p class="small" style="color:var(--gold)">لن يظهر رمز QR للفاتورة الإلكترونية حتى يُسجّل الرقم الضريبي للمنشأة في الإعدادات.</p>'}<div style="height:12px"></div>` : ''}
    ${tbl([{ t: 'البند', h: l => esc(l.item_id ? (im[l.item_id] || {}).name : l.account_code + ' — ' + (am[l.account_code] || '')) }, { t: 'الكمية', r: 1, h: l => +l.qty }, { t: 'السعر', r: 1, h: l => money(l.unit_price) }, { t: 'الضريبة', r: 1, h: l => l.vat_rate + '%' }, { t: 'المبلغ', r: 1, h: l => money(l.amount) }], lines,
      { foot: `<td colspan="4">الإجمالي قبل الضريبة / الضريبة / الإجمالي</td><td class="r num">${money(doc.subtotal)} / ${money(doc.vat)} / <b>${money(doc.total)}</b></td>` })}
    ${fxTxt}<p>المسدد والمرتجع: <b class="num">${money(paid)}</b> · ${rem < -0.001 ? 'رصيد دائن للطرف: <b class="num ok">' + money(-rem) + '</b>' : 'المتبقي: <b class="num">' + money(rem) + '</b>'} · الاستحقاق ${fdate(doc.due_date)}</p>${doc.note ? `<p class="muted">${esc(doc.note)}</p>` : ''}</div>
    ${pays.length ? '<h2>السندات</h2>' + tbl([{ t: 'الرقم', h: p => `<span class="num">${esc(p.no)}</span>` }, { t: 'التاريخ', h: p => fdate(p.date) }, { t: 'المبلغ', r: 1, h: p => money(p.amount) }], pays) : ''}
    ${cns.length ? '<div style="height:12px"></div><h2>الإشعارات</h2>' + tbl([{ t: 'الرقم', h: c => `<span class="num">${esc(c.no)}</span>` }, { t: 'التاريخ', h: c => fdate(c.date) }, { t: 'السبب', k: 'reason' }, { t: 'المبلغ', r: 1, h: c => money(c.total) }, ...(Object.keys(zm).length ? [{ t: 'زاتكا', h: c => zm[c.id] ? zatcaBadge(zm[c.id].status) : '—' }] : []), ...(key === 'sales' ? [{ t: '', h: c => `<button class="btn sm" data-cnp="${c.id}">طباعة</button>` }] : [])], cns) : ''}`;
  if ($('#dprint', page)) $('#dprint', page).onclick = () => { const w = document.createElement('div'); w.innerHTML = invoiceSheet({ key, doc, lines, party, im, am, paid, ref }); printWith(w.firstElementChild, '@page{size:A4 portrait;margin:12mm}'); };
  page.querySelectorAll('[data-cnp]').forEach(bt => bt.onclick = async e => { e.stopPropagation(); const cn = cns.find(c => c.id === bt.dataset.cnp), cl = await db.get('credit_note_lines', { note_id: 'eq.' + cn.id, order: 'id' }); const w = document.createElement('div'); w.innerHTML = invoiceSheet({ key, doc, lines: cl, party, im, am, cn }); printWith(w.firstElementChild, '@page{size:A4 portrait;margin:12mm}'); });
  if ($('#zrs', page)) $('#zrs', page).onclick = () => { zatcaKick(); toast(tr('جارٍ الإرسال إلى زاتكا…')); setTimeout(route, 6000); };
  if ($('#dn', page)) $('#dn', page).onclick = () => debitNoteForm(doc, items);
  if ($('#pay', page)) $('#pay', page).onclick = () => doc.currency ? fxPaymentForm({ key, doc, rem }) : paymentForm({ dir: D.payDir, party: doc.party_id, doc: id, amount: rem });
  if ($('#chq', page)) $('#chq', page).onclick = () => chequeForm({ dir: D.payDir, party: doc.party_id, doc: id, amount: rem });
  if ($('#vd', page)) $('#vd', page).onclick = () => modal('إلغاء الفاتورة', field('سبب الإلغاء', '<textarea name="r" rows="2" required></textarea>') + '<p class="muted small">يُعكس القيد وحركة المخزون، وتبقى الفاتورة ظاهرة بحالة ملغاة.</p>', { ok: 'إلغاء الفاتورة', onOk: async f => { await db.rpc(D.void, { p_id: id, p_reason: f.r }); toast('أُلغيت الفاتورة'); route(); } });
  if ($('#cn', page)) $('#cn', page).onclick = async () => {
    const used = {}; if (cns.length) (await db.get('credit_note_lines', { note_id: 'in.(' + cns.map(c => c.id).join(',') + ')', select: 'src_line,qty' })).forEach(x => used[x.src_line] = (used[x.src_line] || 0) + n0(x.qty));
    modal(D.cnT, `<div class="tw"><table class="lines"><thead><tr><th>البند</th><th>المتاح</th><th>كمية المرتجع</th></tr></thead><tbody>${lines.map(l => `<tr><td>${esc(l.item_id ? (im[l.item_id] || {}).name : am[l.account_code] || l.account_code)}</td><td class="num">${+(n0(l.qty) - n0(used[l.id])).toFixed(3)}</td><td><input name="q_${l.id}" type="number" min="0" step="0.001" max="${n0(l.qty) - n0(used[l.id])}" value="0" style="width:110px"></td></tr>`).join('')}</tbody></table></div><div style="height:10px"></div>${field('السبب', '<input name="reason" required>')}${field('التاريخ', `<input type="date" name="d" value="${today()}">`)}`, {
      wide: true, ok: 'ترحيل الإشعار', onOk: async f => { const ls = lines.map(l => ({ line: l.id, qty: +f['q_' + l.id] })).filter(x => x.qty > 0); if (!ls.length) throw new Error('أدخل كمية مرتجع لبند واحد على الأقل');
        await db.rpc('post_credit_note_cc', { p_company: S.cid, p_doc: { kind: D.cnKind, doc: id, date: f.d, reason: f.reason, lines: ls } }); toast('رُحّل الإشعار'); route(); }
    });
  };
}

/* ===== ZATCA Phase 2 on a sales document: status in the Fatoora chain, resend, debit note ===== */
const ZST = { pending: ['بانتظار الإرسال إلى زاتكا', 'wait'], reported: ['أُبلغت زاتكا', 'ok'], cleared: ['اعتمدتها زاتكا', 'ok'], warning: ['قبلتها زاتكا مع ملاحظات', 'wait'],
  rejected: ['رفضتها زاتكا', 'bad'], error: ['تعذّر الإرسال — ستُعاد المحاولة', 'wait'] };
const zatcaBadge = st => `<span class="badge ${(ZST[st] || ['', ''])[1]}">${esc(tr((ZST[st] || [st])[0]))}</span>`;
function zatcaBox(z) {
  const again = ['pending', 'error'].includes(z.status);
  return `<div class="card zbox" style="margin-bottom:12px"><div class="row" style="justify-content:space-between;gap:8px;flex-wrap:wrap">
      <div>${esc(tr('فاتورة (زاتكا)'))}: ${zatcaBadge(z.status)} <span class="small muted">${esc(tr(z.inv_type === 'standard' ? 'ضريبية — تُعتمد قبل تسليمها للعميل' : 'مبسطة — تُبلَّغ خلال 24 ساعة'))} · ${esc(tr('التسلسل'))} <span class="num">${z.icv}</span>${z.sent_at ? ' · ' + fdate(String(z.sent_at).slice(0, 10)) : ''}</span></div>
      ${again ? `<button class="btn sm" id="zrs">${esc(tr('إعادة الإرسال الآن'))}</button>` : ''}</div>
    ${z.last_error ? `<p class="small" style="margin:6px 0 0;color:var(${z.status === 'rejected' ? '--bad' : '--gold'})" data-nt>${esc(z.last_error)}</p>` : ''}
    ${z.status === 'rejected' ? `<p class="small muted" style="margin:6px 0 0">${esc(tr('المستند المرفوض لا يُعدّل: أصدر إشعاراً دائناً عليه ثم فاتورة صحيحة جديدة.'))}</p>` : ''}
    ${z.inv_type === 'standard' && z.status === 'pending' ? `<p class="small muted" style="margin:6px 0 0">${esc(tr('لا تسلّم الفاتورة الضريبية للعميل قبل اعتماد زاتكا.'))}</p>` : ''}</div>`;
}
// a debit note: an extra amount on this invoice (price difference, extra service…) — posted as its own document, chained to ZATCA
function debitNoteForm(doc, items) {
  const its = items.filter(i => i.active !== false), row = i => `<tr><td><select name="it${i}"><option value="">—</option>${its.map(x => opt(x.id, (x.code ? x.code + ' — ' : '') + x.name)).join('')}</select></td>
    <td><input name="q${i}" type="number" min="0" step="0.001" value="${i ? '' : 1}"></td><td><input name="p${i}" type="number" min="0" step="0.01"></td></tr>`;
  modal(tr('إشعار مدين على الفاتورة') + ' ' + doc.no, `<div class="fg">${field('التاريخ', `<input type="date" name="d" value="${today()}" min="${doc.date}" max="${today()}">`)}
      ${field('السبب', '<input name="reason" required maxlength="300" placeholder="' + esc(tr('مثل: فرق سعر، خدمة إضافية')) + '">', 'wide')}</div>
    <div class="tw"><table class="lines"><thead><tr><th>${esc(tr('البند'))}</th><th>${esc(tr('الكمية'))}</th><th>${esc(tr('السعر'))}</th></tr></thead><tbody>${[0, 1, 2].map(row).join('')}</tbody></table></div>
    <p class="muted small">${esc(tr('يُرحّل كمستند مستقل على نفس العميل ويُضاف لرصيده، ويُرسل إلى زاتكا مرتبطاً بالفاتورة الأصلية.'))}</p>`, {
    wide: true, ok: 'ترحيل الإشعار', onOk: async f => {
      const lines = [0, 1, 2].map(i => ({ item: f['it' + i], qty: +f['q' + i], price: +f['p' + i] })).filter(l => l.item && l.qty > 0 && l.price > 0);
      if (!lines.length) throw new Error('أدخل بنداً واحداً على الأقل بكمية وسعر');
      if ((f.reason || '').trim().length < 3) throw new Error('اكتب سبب الإشعار');
      const nid = await db.rpc('post_debit_note', { p_company: S.cid, p_doc: { ref: doc.id, date: f.d, reason: f.reason.trim(), lines } });
      toast(tr('رُحّل الإشعار المدين')); location.hash = '#/sales/' + nid;
    } });
}

/* ===== payments ===== */
VIEWS['#/payments'] = async page => {
  const [pays, parties] = await Promise.all([db.get('payments', Object.assign(C(), { order: 'date.desc,no.desc', limit: 300 })), db.get('parties', Object.assign(C(), { select: 'id,name' }))]);
  const pm = {}; parties.forEach(p => pm[p.id] = p.name);
  page.innerHTML = `<div class="head"><div><h1>سندات القبض والصرف</h1></div><div class="row">${can('sales') ? '<button class="btn" id="pin">سند قبض</button>' : ''}${can('purch') ? '<button class="btn" id="pout">سند صرف</button>' : ''}</div></div>
    ${tbl([{ t: 'الرقم', h: p => `<span class="num">${esc(p.no)}</span>` }, { t: 'النوع', h: p => p.direction === 'in' ? '<span class="badge ok">قبض</span>' : '<span class="badge info">صرف</span>' }, { t: 'التاريخ', h: p => fdate(p.date) }, { t: 'الطرف', h: p => esc(pm[p.party_id] || '') }, { t: 'الحساب', h: p => p.account_code === '1110' ? 'الصندوق' : p.account_code === '1120' ? 'البنك' : esc(p.account_code) }, { t: 'المبلغ', r: 1, h: p => money(p.amount) }, { t: 'مقابل', h: p => p.invoice_id || p.bill_id ? 'فاتورة' : '<span class="muted">دفعة على الحساب</span>' }], pays, { empty: 'لا توجد سندات' })}`;
  if ($('#pin', page)) $('#pin', page).onclick = () => paymentForm({ dir: 'in' });
  if ($('#pout', page)) $('#pout', page).onclick = () => paymentForm({ dir: 'out' });
};
async function paymentForm({ dir, party, doc, amount }) {
  const D = dir === 'in' ? DOCS.sales : DOCS.purchases;
  const [parties, cash, open] = await Promise.all([db.get('parties', Object.assign(C(), { kind: 'eq.' + D.party, order: 'name' })), cashAccounts(), db.get(D.table, Object.assign(C(), { status: 'eq.posted', order: 'date', select: 'id,no,party_id,total,date' }))]);
  const paid = await paidMap(D, open.map(o => o.id));
  const openDocs = open.filter(o => n0(o.total) - n0(paid[o.id]) > 0.001);
  if (!parties.length) return toast(dir === 'in' ? 'أضف عميلاً أولاً' : 'أضف مورداً أولاً');
  const d = modal(dir === 'in' ? 'سند قبض' : 'سند صرف', `<div class="fg">${field(dir === 'in' ? 'العميل' : 'المورد', `<select name="party" id="pp">${parties.map(p => opt(p.id, p.name, party)).join('')}</select>`)}
     ${field('مقابل فاتورة', `<select name="doc" id="pdoc"></select>`)}${field('المبلغ', inp('amount', amount || '', 'type="number" step="0.01" min="0.01" id="pam"'))}${field(dir === 'in' ? 'إلى حساب' : 'من حساب', `<select name="acc">${cash.map(a => opt(a.code, a.name, '1120')).join('')}</select>`)}
     ${field('التاريخ', `<input type="date" name="date" value="${today()}" max="${today()}">`)}${field('ملاحظات', inp('note'))}</div>`, {
    ok: 'حفظ السند', onOk: async f => { if (!(+f.amount > 0)) throw new Error('أدخل مبلغاً أكبر من صفر');
      await db.rpc('record_payment', { p_company: S.cid, p_doc: { direction: dir, party: f.party, amount: +f.amount, account: f.acc, date: f.date, note: blank(f.note), [D.payKey]: f.doc || '' } }); toast('حُفظ السند'); route(); }
  });
  const fill = () => { const p = $('#pp', d).value; $('#pdoc', d).innerHTML = '<option value="">— دفعة على الحساب —</option>' + openDocs.filter(o => o.party_id === p).map(o => opt(o.id, o.no + ' — متبقي ' + money(n0(o.total) - n0(paid[o.id])), doc)).join(''); };
  $('#pp', d).onchange = () => { doc = null; fill(); }; fill();
  $('#pdoc', d).onchange = e => { const o = openDocs.find(x => x.id === e.target.value); if (o) $('#pam', d).value = r2(n0(o.total) - n0(paid[o.id])); };
}

/* ===== journal ===== */
const SRC = { manual: 'يدوي', reversal: 'عكس', sales: 'مبيعات', purchase: 'مشتريات', receipt: 'قبض', payment: 'صرف', stock: 'مخزون', payroll: 'رواتب', payroll_pay: 'صرف رواتب', advance: 'سلفة', expense: 'مصروفات', opening: 'افتتاحي', sales_return: 'مرتجع مبيعات', purchase_return: 'مرتجع مشتريات', asset: 'أصول ثابتة', depreciation: 'إهلاك' };
VIEWS['#/journal'] = async page => {
  const [jes, acc] = await Promise.all([db.get('journal_entries', Object.assign(C(), { order: 'date.desc,created_at.desc', limit: 200 })), accounts()]);
  const am = {}; acc.forEach(a => am[a.code] = a.name);
  const reversed = new Set(jes.filter(j => j.reverses).map(j => j.reverses));
  page.innerHTML = `<div class="head"><div><h1>القيود اليومية</h1><div class="muted">آخر 200 قيد — القيود لا تُعدّل، تُعكس فقط</div></div>${can('jepost') ? '<button class="btn pri" id="nj">قيد يدوي</button>' : ''}</div>
    ${tbl([{ t: 'الرقم', h: j => `<span class="num">${esc(j.no)}</span>` }, { t: 'التاريخ', h: j => fdate(j.date) }, { t: 'البيان', k: 'memo' }, { t: 'المصدر', h: j => `<span class="badge">${esc(SRC[j.source] || j.source)}</span>` + (reversed.has(j.id) ? ' <span class="badge bad">معكوس</span>' : '') }], jes, { empty: 'لا توجد قيود', onRow: true })}`;
  bindRows(page, jes, async j => {
    const ls = await db.get('journal_lines', { entry_id: 'eq.' + j.id, order: 'id' });
    const d = modal('قيد ' + j.no, `<p>${esc(j.memo)} · ${fdate(j.date)}</p>${tbl([{ t: 'الحساب', h: l => esc(l.account_code + ' — ' + (am[l.account_code] || '')) }, { t: 'مدين', r: 1, h: l => n0(l.debit) ? money(l.debit) : '' }, { t: 'دائن', r: 1, h: l => n0(l.credit) ? money(l.credit) : '' }], ls)}
      ${j.source === 'manual' && !reversed.has(j.id) && can('jepost') ? '<button type="button" class="btn danger sm" id="rv" style="margin-top:12px">عكس القيد</button>' : ''}`);
    if ($('#rv', d)) $('#rv', d).onclick = async () => { try { await db.rpc('reverse_journal', { p_entry: j.id, p_date: today() }); d.close(); toast('عُكس القيد'); route(); } catch (e) { showErr($('#merr', d), e); } };
  });
  if ($('#nj', page)) $('#nj', page).onclick = async () => {
    const post = acc.filter(a => !a.is_header); const ao = '<option value="">—</option>' + post.map(a => opt(a.code, a.code + ' — ' + a.name)).join('');
    const ccs = (await ccList()).filter(c => c.active), co = ccs.length ? `<option value="">—</option>${ccs.map(c => opt(c.id, ccName(c))).join('')}` : '';
    const row = () => `<tr><td><select data-a>${ao}</select></td><td><input data-d type="number" step="0.01" min="0" style="width:120px"></td><td><input data-c type="number" step="0.01" min="0" style="width:120px"></td>${co ? `<td><select data-cc style="width:150px">${co}</select></td>` : ''}</tr>`;
    const d = modal('قيد يدوي', `<div class="fg">${field('التاريخ', `<input type="date" name="date" value="${today()}">`)}${field('البيان', inp('memo'))}</div><div style="height:10px"></div><div class="tw"><table class="lines"><thead><tr><th>الحساب</th><th>مدين</th><th>دائن</th>${co ? '<th>مركز التكلفة</th>' : ''}</tr></thead><tbody id="jl">${row()}${row()}</tbody><tfoot><tr><td>الفرق</td><td colspan="${co ? 3 : 2}" class="num" id="jd">0.00</td></tr></tfoot></table></div><button type="button" class="btn sm" id="ja" style="margin-top:8px">+ سطر</button>`, {
      wide: true, ok: 'ترحيل', onOk: async f => {
        const lines = $$('#jl tr', d).map(tr => ({ a: $('[data-a]', tr).value, d: +$('[data-d]', tr).value || 0, c: +$('[data-c]', tr).value || 0, cc: $('[data-cc]', tr) ? $('[data-cc]', tr).value || null : null })).filter(l => l.a && (l.d || l.c));
        if (lines.some(l => l.d && l.c)) throw new Error('السطر الواحد إما مدين أو دائن');
        const dd = r2(lines.reduce((a, l) => a + l.d, 0)), cc = r2(lines.reduce((a, l) => a + l.c, 0));
        if (lines.length < 2 || dd !== cc) throw new Error('القيد غير متوازن');
        await db.rpc('post_manual_journal', { p_company: S.cid, p_date: f.date, p_memo: f.memo, p_lines: lines }); toast('رُحّل القيد'); route();
      }
    });
    $('#ja', d).onclick = () => $('#jl', d).insertAdjacentHTML('beforeend', row());
    $('#jl', d).addEventListener('input', () => { let s = 0; $$('#jl tr', d).forEach(tr => s += (+$('[data-d]', tr).value || 0) - (+$('[data-c]', tr).value || 0)); $('#jd', d).textContent = money(Math.abs(s)); });
  };
};

/* ===== chart of accounts ===== */
VIEWS['#/coa'] = async page => {
  cache.acc = null; const acc = await accounts();
  page.innerHTML = `<div class="head"><div><h1>دليل الحسابات</h1></div>${can('coa') ? '<button class="btn pri" id="na">حساب فرعي</button>' : ''}</div>
    ${tbl([{ t: 'الرمز', h: a => `<span class="num">${esc(a.code)}</span>` }, { t: 'الحساب', h: a => a.is_header ? '<b>' + esc(a.name) + '</b>' : '&nbsp;&nbsp;&nbsp;' + esc(a.name) }, { t: 'النوع', h: a => ({ asset: 'أصول', liab: 'خصوم', equity: 'حقوق ملكية', rev: 'إيرادات', exp: 'مصروفات' })[a.type] }], acc, { onRow: can('ledger') })}`;
  if (can('ledger')) bindRows(page, acc, a => { if (!a.is_header) location.hash = '#/reports?r=ledger&code=' + a.code; });
  if ($('#na', page)) $('#na', page).onclick = () => modal('حساب فرعي جديد', `<div class="fg">${field('الحساب الرئيسي', `<select name="p">${acc.filter(a => a.is_header).map(a => opt(a.code, a.code + ' — ' + a.name)).join('')}</select>`)}${field('الرمز (4 أرقام)', inp('code', '', 'dir="ltr" maxlength="4" inputmode="numeric"'))}${field('الاسم', inp('name'), 'wide')}${enF('name_en', '')}</div>`, {
    onOk: async f => { await db.rpc('add_account', { p_company: S.cid, p_code: f.code, p_name: f.name, p_parent: f.p }); if ((f.name_en || '').trim()) await db.rpc('account_set_name_en', { p_company: S.cid, p_code: f.code, p_name_en: f.name_en }); toast('أُضيف الحساب'); route(); }
  });
};

/* ===== reports ===== */
VIEWS['#/reports'] = async (page, arg, q) => {
  const tabs = [['tb', 'ميزان المراجعة', 'reports'], ['is', 'قائمة الدخل', 'reports'], ['bs', 'المركز المالي', 'reports'], ['cf', 'التدفقات النقدية', 'reports'], ['vat', 'إقرار الضريبة', 'vat'], ['ar', 'أعمار الذمم المدينة', 'sales'], ['ap', 'أعمار الذمم الدائنة', 'purch'], ['ledger', 'دفتر الأستاذ', 'ledger']].filter(t => can(t[2]));
  if (!tabs.length) { page.innerHTML = '<div class="note">لا تملك صلاحية التقارير.</div>'; return; }
  const r = tabs.some(t => t[0] === q.get('r')) ? q.get('r') : tabs[0][0];
  const from = q.get('from') || today().slice(0, 4) + '-01-01', to = q.get('to') || today();
  const acc = await accounts();
  const ranged = ['is', 'cf', 'vat', 'ledger'].includes(r);
  page.innerHTML = `<div class="head"><div><h1>التقارير</h1></div></div><div class="seg" style="margin-bottom:14px">${tabs.map(t => `<a href="#/reports?r=${t[0]}" class="${t[0] === r ? 'on' : ''}">${t[1]}</a>`).join('')}</div>
    <form id="rf" class="row card" style="padding:12px">${r === 'ledger' ? `<select name="code" style="width:auto">${acc.filter(a => !a.is_header).map(a => opt(a.code, a.code + ' — ' + a.name, q.get('code') || '1120')).join('')}</select>` : ''}
      ${ranged ? `<label style="margin:0">من</label><input type="date" name="from" value="${from}" style="width:auto">` : ''}<label style="margin:0">${ranged ? 'إلى' : 'حتى تاريخ'}</label><input type="date" name="to" value="${to}" style="width:auto"><button class="btn">عرض</button><button type="button" class="btn" id="rprint">طباعة</button></form><div id="rb">جارٍ التحميل…</div>`;
  $('#rprint', page).onclick = () => printBlock($('#rb', page), tabs.find(t => t[0] === r)[1] + (ranged ? ' من ' + from + ' إلى ' + to : ' حتى ' + to) + (r === 'ledger' ? ' — ' + ($('select[name=code] option:checked', page) || {}).textContent : ''));
  $('#rf', page).onsubmit = e => { e.preventDefault(); const f = formData(e.target); location.hash = '#/reports?' + qs(Object.assign({ r }, f)); };
  const rb = $('#rb', page);
  if (r === 'tb') { const rows = await db.rpc('trial_balance', { p_company: S.cid, p_as_of: to }); const sd = rows.reduce((a, x) => a + n0(x.debit), 0), sc = rows.reduce((a, x) => a + n0(x.credit), 0);
    rb.innerHTML = tbl([{ t: 'الرمز', h: x => `<span class="num">${esc(x.code)}</span>` }, { t: 'الحساب', k: 'name' }, { t: 'مدين', r: 1, h: x => n0(x.debit) ? money(x.debit) : '' }, { t: 'دائن', r: 1, h: x => n0(x.credit) ? money(x.credit) : '' }], rows, { empty: 'لا توجد حركات', foot: `<td colspan="2">الإجمالي ${Math.abs(sd - sc) < 0.01 ? '<span class="badge ok">متوازن</span>' : '<span class="badge bad">غير متوازن</span>'}</td><td class="r num">${money(sd)}</td><td class="r num">${money(sc)}</td>` }); }
  if (r === 'is') { const rows = await db.rpc('income_statement', { p_company: S.cid, p_from: from, p_to: to }); const sec = { revenue: 'الإيرادات', cogs: 'تكلفة المبيعات', expense: 'المصروفات', net_profit: '' };
    rb.innerHTML = tbl([{ t: 'القسم', h: x => esc(sec[x.section]) }, { t: 'الحساب', h: x => x.section === 'net_profit' ? '<b>' + esc(x.name) + '</b>' : esc(x.name) }, { t: 'المبلغ', r: 1, h: x => x.section === 'net_profit' ? `<b class="${n0(x.amount) < 0 ? 'bad' : 'ok'}">${money(x.amount)}</b>` : money(x.amount) }], rows, { empty: 'لا توجد حركات' }); }
  if (r === 'bs') { const rows = await db.rpc('balance_sheet', { p_company: S.cid, p_as_of: to }); const sec = { asset: 'الأصول', liab: 'الخصوم', equity: 'حقوق الملكية' }; const tot = k => rows.filter(x => x.section === k).reduce((a, x) => a + n0(x.amount), 0);
    rb.innerHTML = tbl([{ t: 'القسم', h: x => esc(sec[x.section]) }, { t: 'الحساب', h: x => esc((x.code ? x.code + ' — ' : '') + x.name) }, { t: 'المبلغ', r: 1, h: x => money(x.amount) }], rows, { empty: 'لا توجد أرصدة' }) + `<p>الأصول <b class="num">${money(tot('asset'))}</b> · الخصوم وحقوق الملكية <b class="num">${money(tot('liab') + tot('equity'))}</b> ${Math.abs(tot('asset') - tot('liab') - tot('equity')) < 0.01 ? '<span class="badge ok">متوازن</span>' : '<span class="badge bad">غير متوازن</span>'}</p>`; }
  if (r === 'cf') { const rows = await db.rpc('cash_flow', { p_company: S.cid, p_from: from, p_to: to }); const sec = { '1operating': 'الأنشطة التشغيلية', '2investing': 'الأنشطة الاستثمارية', '3financing': 'الأنشطة التمويلية' };
    const g = k => rows.filter(x => x.section === k), tot = k => g(k).reduce((a, x) => a + n0(x.amount), 0), op = rows.find(x => x.section === '0open'), cl = rows.find(x => x.section === '9close');
    const net = tot('1operating') + tot('2investing') + tot('3financing');
    rb.innerHTML = `<div class="tw"><table><tbody><tr><td><b>${esc(tr('النقدية أول الفترة'))}</b></td><td class="r num"><b>${money(op ? op.amount : 0)}</b></td></tr>
      ${Object.keys(sec).map(k => `<tr><th colspan="2" style="text-align:start">${esc(tr(sec[k]))}</th></tr>${g(k).map(x => `<tr><td style="padding-inline-start:24px">${esc(tr(x.line))}</td><td class="r num">${money(x.amount)}</td></tr>`).join('') || `<tr><td class="muted" style="padding-inline-start:24px">—</td><td></td></tr>`}
        <tr><td><i>${esc(tr('صافي'))} ${esc(tr(sec[k]))}</i></td><td class="r num"><i class="${tot(k) < 0 ? 'bad' : ''}">${money(tot(k))}</i></td></tr>`).join('')}
      <tr><td><b>${esc(tr('صافي التغير في النقدية'))}</b></td><td class="r num"><b class="${net < 0 ? 'bad' : 'ok'}">${money(net)}</b></td></tr></tbody>
      <tfoot><tr><td>${esc(tr('النقدية آخر الفترة'))}</td><td class="r num">${money(cl ? cl.amount : 0)}</td></tr></tfoot></table></div>
      <p class="muted small">${esc(tr('الطريقة المباشرة: كل حركة على حسابات النقد والبنوك (1100) مصنفة حسب الحساب المقابل.'))}</p>`; }
  if (r === 'vat') { const [v] = await db.rpc('vat_summary', { p_company: S.cid, p_from: from, p_to: to }); const row = (t, a) => `<tr><td>${t}</td><td class="r num">${money(a)}</td></tr>`;
    rb.innerHTML = `<div class="tw"><table><tbody>${row('المبيعات الخاضعة للنسبة الأساسية (صافي المرتجعات)', v.sales_taxable)}${row('المبيعات الصفرية', v.sales_zero)}${row('ضريبة المخرجات', v.output_vat)}${row('المشتريات الخاضعة للنسبة الأساسية', v.purchases_taxable)}${row('المشتريات الصفرية', v.purchases_zero)}${row('ضريبة المدخلات', v.input_vat)}</tbody><tfoot><tr><td>صافي الضريبة ${n0(v.net_vat) >= 0 ? 'المستحقة' : 'القابلة للاسترداد'}</td><td class="r num">${money(Math.abs(v.net_vat))}</td></tr></tfoot></table></div><p class="muted small">ملخص استرشادي لتعبئة الإقرار في بوابة هيئة الزكاة والضريبة والجمارك.</p>`; }
  if (r === 'ar' || r === 'ap') { const rows = await db.rpc('aging', { p_company: S.cid, p_kind: r === 'ar' ? 'sales' : 'purchase', p_as_of: to });
    rb.innerHTML = tbl([{ t: r === 'ar' ? 'العميل' : 'المورد', k: 'party' }, { t: 'غير مستحق', r: 1, h: x => money(x.not_due) }, { t: '1–30', r: 1, h: x => money(x.d1_30) }, { t: '31–60', r: 1, h: x => money(x.d31_60) }, { t: '61–90', r: 1, h: x => money(x.d61_90) }, { t: '+90', r: 1, h: x => money(x.d90_plus) }, { t: 'دفعات غير مخصصة', r: 1, h: x => money(x.unallocated) }, { t: 'الصافي', r: 1, h: x => '<b>' + money(x.net) + '</b>' }], rows, { empty: 'لا توجد أرصدة مفتوحة' }); }
  if (r === 'ledger') { const code = q.get('code') || '1120'; const rows = await db.rpc('account_ledger', { p_company: S.cid, p_code: code, p_from: from, p_to: to });
    rb.innerHTML = tbl([{ t: 'التاريخ', h: x => fdate(x.date) }, { t: 'القيد', h: x => `<span class="num">${esc(x.no || '')}</span>` }, { t: 'البيان', k: 'memo' }, { t: 'مدين', r: 1, h: x => n0(x.debit) ? money(x.debit) : '' }, { t: 'دائن', r: 1, h: x => n0(x.credit) ? money(x.credit) : '' }, { t: 'الرصيد', r: 1, h: x => money(x.balance) }], rows); }
};
