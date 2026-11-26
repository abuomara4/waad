'use strict';
/* ===== spend control (0116): supplier invoices inbox, the finance manager's spend view, journal export ===== */

/* ---------- «فواتير الموردين الواردة»: purchasing records each supplier invoice with its file; finance approves or
   rejects it; once the purchase bill is posted it is linked here. ---------- */
const SINB = { new: ['بانتظار المراجعة', ''], approved: ['معتمدة — بانتظار فاتورة الشراء', 'info'], rejected: ['مرفوضة', 'bad'], billed: ['سُجّلت فاتورة الشراء', 'ok'] };
VIEWS['#/supinbox'] = async page => {
  if (!can('purch')) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للمشتريات والمالية.'))}</div>`; return; }
  const [rows, sup] = await Promise.all([db.get('supplier_inbox', { company_id: 'eq.' + S.cid, order: 'created_at.desc', limit: 300 }), db.get('parties', { company_id: 'eq.' + S.cid, kind: 'eq.supplier', select: 'id,name', order: 'name' })]);
  const pm = {}; sup.forEach(p => pm[p.id] = p.name);
  const reviewer = has('owner', 'admin', 'finance') || can('jepost');
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('فواتير الموردين الواردة'))}</h1><div class="muted">${esc(tr('سجّل فاتورة المورد مع ملفها، تراجعها المالية وتعتمدها، ثم تُربط بفاتورة الشراء المرحّلة.'))}</div></div>
      <button class="btn pri" id="sinew">${esc(tr('فاتورة واردة'))}</button></div>` +
    tbl([{ t: 'المورد', h: x => esc(pm[x.party_id] || x.supplier_name || '—') }, { t: 'رقم فاتورة المورد', h: x => `<span class="num">${esc(x.supplier_ref || '—')}</span>` },
      { t: 'التاريخ', h: x => x.inv_date ? fdate(x.inv_date) : '—' }, { t: 'المبلغ', r: 1, h: x => x.amount == null ? '—' : money(x.amount) },
      { t: 'الحالة', h: x => `<span class="badge ${SINB[x.status][1]}">${esc(tr(SINB[x.status][0]))}</span>` }], rows, { empty: 'لا توجد فواتير واردة', onRow: true });
  bindRows(page, rows, async x => {
    const bills = x.status === 'approved' ? await db.get('purchase_bills', Object.assign({ company_id: 'eq.' + S.cid, status: 'eq.posted', order: 'date.desc', limit: 50, select: 'id,no,date,total,supplier_ref,party_id' }, x.party_id ? { party_id: 'eq.' + x.party_id } : {})) : [];
    const d = modal(tr('فاتورة مورد واردة'), `<p><b>${esc(pm[x.party_id] || x.supplier_name || '')}</b> · <span class="num">${esc(x.supplier_ref || '')}</span> · ${x.amount == null ? '' : money(x.amount)} <span class="badge ${SINB[x.status][1]}">${esc(tr(SINB[x.status][0]))}</span></p>
      ${x.note ? `<p class="small">${esc(x.note)}</p>` : ''}${x.review_note ? `<p class="small">${esc(tr('ملاحظة المراجعة'))}: ${esc(x.review_note)}</p>` : ''}<div id="sifb"></div>
      ${x.status === 'new' && reviewer ? field('ملاحظة (إلزامية عند الرفض)', '<textarea name="rn" rows="2"></textarea>') + `<div class="row" style="margin-top:8px"><button type="button" class="btn pri" id="siok">${esc(tr('اعتماد'))}</button><button type="button" class="btn danger" id="sino">${esc(tr('رفض'))}</button></div>` : ''}
      ${x.status === 'approved' ? (bills.length ? field('اربطها بفاتورة الشراء المرحّلة', `<select name="bill">${bills.map(b => opt(b.id, b.no + ' · ' + fdate(b.date) + ' · ' + money(b.total) + (b.supplier_ref ? ' · ' + b.supplier_ref : ''))).join('')}</select>`) + `<button type="button" class="btn pri" id="silk" style="margin-top:8px">${esc(tr('ربط'))}</button>`
        : `<p class="muted small">${esc(tr('سجّل فاتورة الشراء لهذا المورد من «فواتير المشتريات» ثم اربطها هنا.'))} <a href="#/purchases/new">${esc(tr('فاتورة شراء جديدة'))}</a></p>`) : ''}
      ${x.bill_id ? `<p><a href="#/purchases/${x.bill_id}">${esc(tr('فتح فاتورة الشراء'))}</a></p>` : ''}`);
    fileBox($('#sifb', d), 'supplier_inbox_files', 'inbox_id', x.id).catch(() => {});
    if (x.receipt_key) db.rpc('receipt_seen', { p_company: S.cid, p_key: x.receipt_key }).then(n => { if (n > 1) $('#sifb', d).insertAdjacentHTML('beforebegin', `<div class="note">⚠️ ${esc(tr('هذه الفاتورة مقدّمة من قبل في المنشأة. تأكد أنها ليست مكررة.'))}</div>`); }).catch(() => {});
    const go = async (ok) => { try { await db.rpc('supplier_inbox_review', { p_id: x.id, p_ok: ok, p_note: d.querySelector('[name=rn]').value }); d.close(); toast(tr('تم الحفظ')); route(); } catch (e) { toast(e.message); } };
    if ($('#siok', d)) $('#siok', d).onclick = () => go(true);
    if ($('#sino', d)) $('#sino', d).onclick = () => go(false);
    if ($('#silk', d)) $('#silk', d).onclick = async () => { try { await db.rpc('supplier_inbox_link', { p_id: x.id, p_bill: d.querySelector('[name=bill]').value }); d.close(); toast(tr('تم الربط')); route(); } catch (e) { toast(e.message); } };
  });
  $('#sinew', page).onclick = () => { let rz = null; const d = modal(tr('فاتورة مورد واردة'), `<div class="fg">${field('المورد', `<select name="p"><option value="">${esc(tr('مورد غير مسجّل'))}</option>${sup.map(p => opt(p.id, p.name)).join('')}</select>`)}
      ${field('اسم المورد (إن لم يكن مسجّلا)', inp('pn', '', 'maxlength="120"'))}${field('رقم فاتورة المورد', inp('ref', '', 'maxlength="60"'))}${field('تاريخ الفاتورة', `<input type="date" name="d" value="${today()}">`)}
      ${field('المبلغ شامل الضريبة', inp('a', '', 'type="number" min="0" step="0.01"'))}${field('ملاحظة', inp('n', '', 'maxlength="500"'), 'wide')}
      <div class="wide"><label>${esc(tr('ملف الفاتورة (PDF أو صورة)'))}</label><input type="file" name="files" id="sif" accept="application/pdf,image/*"></div></div>`, {
    onOk: async f => { if (!f.p && !(f.pn || '').trim()) throw new Error(tr('اختر المورد أو اكتب اسمه'));
      const [row] = await db.ins('supplier_inbox', Object.assign({ company_id: S.cid, party_id: f.p || null, supplier_name: f.p ? null : f.pn.trim(), supplier_ref: blank(f.ref), inv_date: f.d || null, amount: f.a === '' ? null : +f.a, note: blank(f.n) },
        rz ? { receipt_key: rz.key, vat_no: /^3[0-9]{13}3$/.test(rz.vat_no || '') ? rz.vat_no : null, vat: rz.tax == null ? null : rz.tax } : {}));
      const fl = $('#sif').files; if (fl && fl.length) await attachFiles('supplier_inbox_files', 'inbox_id', row.id, fl);
      toast(tr('سُجّلت الفاتورة وتنتظر مراجعة المالية')); route(); } });
    // a photographed invoice picks the supplier by its VAT number (or writes its name), the date and the total (0160)
    if (typeof receiptReader === 'function') receiptReader($('#sif', d), z => { rz = z; const sp = sup.find(p => p.vat_no && p.vat_no === z.vat_no);
      if (sp) d.querySelector('[name=p]').value = sp.id; else { d.querySelector('[name=p]').value = ''; d.querySelector('[name=pn]').value = z.seller || ''; }
      if (z.date) d.querySelector('[name=d]').value = z.date; if (z.total != null) d.querySelector('[name=a]').value = z.total; if (z.ref) d.querySelector('[name=ref]').value = z.ref; }); };
};

/* ---------- «لوحة الإنفاق»: where the money goes ---------- */
VIEWS['#/spend'] = async (page, arg, q) => {
  if (!can('reports')) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للمالية.'))}</div>`; return; }
  const to = q.get('to') || today(), from = q.get('from') || (to.slice(0, 4) + '-01-01');
  const d = await db.rpc('spend_summary', { p_company: S.cid, p_from: from, p_to: to });
  const total = (d.months || []).reduce((a, m) => a + n0(m.v), 0);
  const bars = (rows, lab) => rows.length ? `<div class="hbars">${rows.map(x => `<div class="hb"><span class="small">${esc(lab(x))}</span><div class="hbt"><i style="width:${Math.max(2, Math.round(n0(x.v) / Math.max(...rows.map(y => n0(y.v)), 1) * 100))}%"></i></div><span class="num small">${money(x.v)}</span></div>`).join('')}</div>` : `<p class="muted small">${esc(tr('لا توجد بيانات في هذه الفترة'))}</p>`;
  const KN = { expense: 'مطالبات المصروفات', trip: 'رحلات العمل' };
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('لوحة الإنفاق'))}</h1><div class="muted">${esc(tr('أين تذهب أموال المنشأة: المصروفات حسب الشهر والحساب ومركز التكلفة والمورد والقسم.'))}</div></div>
      <form id="spf" class="row" style="gap:6px;flex-wrap:wrap"><input type="date" name="from" value="${from}" style="width:auto;max-width:150px" aria-label="${esc(tr('من'))}"><input type="date" name="to" value="${to}" style="width:auto;max-width:150px" aria-label="${esc(tr('إلى'))}"><button class="btn">${esc(tr('عرض'))}</button></form></div>
    <div class="grid" style="margin-bottom:14px"><div class="card kpi"><div class="muted small">${esc(tr('إجمالي المصروفات'))}</div><b class="num">${money(total)}</b></div>
      <div class="card kpi"><div class="muted small">${esc(tr('طلبات صرف بانتظار الاعتماد'))}</div><b class="num">${money(d.pending)}</b></div>
      <div class="card kpi"><div class="muted small">${esc(tr('مشتريات من الموردين'))}</div><b class="num">${money((d.suppliers || []).reduce((a, x) => a + n0(x.v), 0))}</b></div></div>
    <div class="grid g2"><div class="card"><h2>${esc(tr('المصروفات شهريا'))}</h2>${bars(d.months || [], x => x.m)}</div>
      <div class="card"><h2>${esc(tr('أعلى الحسابات'))}</h2>${bars(d.accounts || [], x => x.k + ' ' + x.n)}</div>
      <div class="card"><h2>${esc(tr('حسب مركز التكلفة'))}</h2>${bars(d.ccs || [], x => x.n === '—' ? tr('بدون مركز تكلفة') : x.n)}</div>
      <div class="card"><h2>${esc(tr('أعلى الموردين'))}</h2>${bars(d.suppliers || [], x => x.n + ' (' + x.c + ')')}</div>
      <div class="card"><h2>${esc(tr('مطالبات الموظفين ورحلاتهم حسب القسم'))}</h2>${bars(d.claims || [], x => (x.n === '—' ? tr('بدون قسم') : x.n) + ' · ' + tr(KN[x.k] || x.k))}</div></div>`;
  $('#spf', page).onsubmit = e => { e.preventDefault(); location.hash = '#/spend?' + new URLSearchParams({ from: e.target.from.value, to: e.target.to.value }); };
};

/* ---------- export journal entries for another accounting system (Excel or CSV, one row per line) ---------- */
function journalExport() {
  const y = today().slice(0, 4);
  modal(tr('تصدير القيود'), `<div class="fg">${field('من', `<input type="date" name="f" value="${y}-01-01">`)}${field('إلى', `<input type="date" name="t" value="${today()}">`)}
    ${field('الصيغة', `<select name="x">${opt('xlsx', 'Excel')}${opt('csv', 'CSV (UTF-8)')}</select>`)}</div>
    <p class="muted small">${esc(tr('ملف بسطر لكل طرف قيد: التاريخ، رقم القيد، البيان، رمز الحساب واسمه، مدين، دائن، مركز التكلفة، المصدر. تستورده أنظمة المحاسبة الأخرى (مثل قيود وزوهو بوكس وأودو) بمطابقة الأعمدة مع دليل حساباتها عند الاستيراد.'))}</p>`, {
    ok: 'تنزيل', onOk: async f => {
      const [jes, acc, ccs] = await Promise.all([db.get('journal_entries', { company_id: 'eq.' + S.cid, date: 'gte.' + f.f, order: 'date,no', select: 'id,no,date,memo,source', limit: 20000 }).then(r => r.filter(j => j.date <= f.t)), accounts(), db.get('cost_centers', { company_id: 'eq.' + S.cid, select: 'id,code,name' }).catch(() => [])]);
      if (!jes.length) throw new Error(tr('لا توجد قيود في هذه الفترة'));
      const am = {}; acc.forEach(a => am[a.code] = a); const cm = {}; ccs.forEach(c => cm[c.id] = c); const jm = {}; jes.forEach(j => jm[j.id] = j);
      const lines = [];
      for (let i = 0; i < jes.length; i += 150) lines.push(...await db.get('journal_lines', { entry_id: 'in.(' + jes.slice(i, i + 150).map(j => j.id).join(',') + ')', order: 'id', limit: 50000 }));
      const en = LANG === 'en', head = en ? ['Date', 'Entry no', 'Description', 'Account code', 'Account name', 'Debit', 'Credit', 'Cost center', 'Source', 'Line memo']
        : ['التاريخ', 'رقم القيد', 'البيان', 'رمز الحساب', 'اسم الحساب', 'مدين', 'دائن', 'مركز التكلفة', 'المصدر', 'بيان السطر'];
      const rows = lines.sort((a, b) => (jm[a.entry_id].date + jm[a.entry_id].no).localeCompare(jm[b.entry_id].date + jm[b.entry_id].no) || a.id - b.id).map(l => { const j = jm[l.entry_id], a = am[l.account_code] || {}, c = cm[l.cost_center_id];
        return [j.date, j.no, j.memo || '', l.account_code, (en && a.name_en) || a.name || '', r2(n0(l.debit)), r2(n0(l.credit)), c ? (c.code ? c.code + ' ' : '') + c.name : '', SRC[j.source] || j.source, l.memo || '']; });
      const name = 'waad-journal-' + f.f + '-' + f.t;
      let blob;
      if (f.x === 'csv') blob = new Blob(['﻿' + [head, ...rows].map(r => r.map(v => typeof v === 'number' ? v.toFixed(2) : '"' + String(v).replace(/"/g, '""') + '"').join(',')).join('\r\n')], { type: 'text/csv;charset=utf-8' });
      else blob = templateXlsx([head, ...rows]);
      const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name + '.' + (f.x === 'csv' ? 'csv' : 'xlsx'); document.body.appendChild(a); a.click(); a.remove();
      toast(tr('تم التنزيل') + ' · ' + rows.length);
    } });
}
