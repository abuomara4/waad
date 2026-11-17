'use strict';
/* ===== مستندات المنشأة والسيارات (0097): the company's own papers and its vehicles, with expiry alerts and attachments ===== */
const CO_DOC_T = { cr: ['السجل التجاري', 'Commercial registration'], municipal: ['رخصة البلدية', 'Municipal licence'], chamber: ['شهادة الغرفة التجارية', 'Chamber of Commerce certificate'],
  civil_defense: ['شهادة الدفاع المدني', 'Civil defence certificate'], lease: ['عقد الإيجار', 'Lease contract'], insurance: ['وثيقة تأمين', 'Insurance policy'],
  zakat: ['شهادة الزكاة والدخل', 'Zakat certificate'], gosi: ['شهادة التأمينات الاجتماعية', 'GOSI certificate'], saudization: ['شهادة السعودة', 'Saudization certificate'],
  vat: ['شهادة ضريبة القيمة المضافة', 'VAT certificate'], other: ['مستند آخر', 'Other document'] };
const coDocName = d => d.doc_type === 'other' ? ((LANG === 'en' && d.title_en) || d.title || '') : (CO_DOC_T[d.doc_type] || [''])[LANG === 'en' ? 1 : 0] + (d.title ? ' — ' + d.title : '');
const expLeft = d => d ? Math.round((new Date(d) - new Date(today())) / 864e5) : null;
const expBadge = d => { const n = expLeft(d); if (n == null) return '<span class="muted">—</span>';
  const c = n < 0 ? 'bad' : n <= 30 ? 'bad' : n <= 60 ? 'wait' : 'ok';
  return `<span class="num">${esc(d)}</span> <span class="badge ${c}">${esc(n < 0 ? tr('منتهي') : n === 0 ? tr('ينتهي اليوم') : tr('متبقي') + ' ' + arCount(n, 'يوم'))}</span>`; };
const coCan = () => has('owner', 'admin', 'hr', 'finance') || hrCan('hr_cdocs');

VIEWS['#/companydocs'] = async (page, arg, q) => {
  if (!coCan()) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للمالك والإدارة والموارد البشرية والمالية.'))}</div>`; return; }
  const tab = q.get('t') === 'vehicles' ? 'vehicles' : 'docs';
  const [docs, cars, em] = await Promise.all([db.get('company_documents', { company_id: 'eq.' + S.cid, order: 'expiry_date.asc.nullslast' }), db.get('vehicles', { company_id: 'eq.' + S.cid, order: 'plate' }), employeesMap().catch(() => ({}))]);
  const carNext = v => [v.istimara_expiry, v.insurance_expiry, v.inspection_expiry].filter(Boolean).sort()[0] || null;
  const soon = docs.filter(d => d.expiry_date && expLeft(d.expiry_date) <= 60).length + cars.filter(v => v.active && carNext(v) && expLeft(carNext(v)) <= 60).length;
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('مستندات المنشأة والسيارات'))}</h1><div class="muted">${esc(tr('السجل التجاري والرخص والشهادات وعقود الإيجار والتأمين، وسيارات المنشأة — مع تنبيه قبل الانتهاء.'))}</div></div>
      <button class="btn pri" id="cdnew">${esc(tr(tab === 'docs' ? '+ مستند' : '+ سيارة'))}</button></div>
    <div class="tabs" style="max-width:420px"><button type="button" class="${tab === 'docs' ? 'on' : ''}" onclick="location.hash='#/companydocs'">${esc(tr('المستندات'))} <span class="num">${docs.length}</span></button><button type="button" class="${tab === 'vehicles' ? 'on' : ''}" onclick="location.hash='#/companydocs?t=vehicles'">${esc(tr('السيارات'))} <span class="num">${cars.length}</span></button></div>
    ${soon ? `<div class="note">${esc(tr('ينتهي أو انتهى خلال 60 يوما'))}: <b class="num">${soon}</b></div>` : ''}
    <div id="cdl"></div>`;
  const box = $('#cdl', page);
  if (tab === 'docs') {
    box.innerHTML = tbl([{ t: 'المستند', h: d => `<b>${esc(coDocName(d))}</b>` }, { t: 'الرقم', h: d => `<span class="num">${esc(d.doc_no || '—')}</span>` },
      { t: 'تاريخ الإصدار', h: d => fdate(d.issue_date) }, { t: 'الانتهاء', h: d => expBadge(d.expiry_date) }], docs, { empty: 'لم تُضف مستندات المنشأة بعد. ابدأ بالسجل التجاري.', onRow: true });
    bindRows(box, docs, d => docForm(d));
  } else {
    box.innerHTML = tbl([{ t: 'اللوحة', h: v => `<b class="num">${esc(v.plate)}</b>${v.active ? '' : ` <span class="badge">${esc(tr('موقوفة'))}</span>`}<div class="small muted">${esc([v.make, v.model, v.year, v.color].filter(Boolean).join(' · '))}</div>` },
      { t: 'السائق', h: v => v.driver_id && em[v.driver_id] ? esc(em[v.driver_id].full_name) : '—' }, { t: 'الاستمارة', h: v => expBadge(v.istimara_expiry) },
      { t: 'التأمين', h: v => expBadge(v.insurance_expiry) }, { t: 'الفحص الدوري', h: v => expBadge(v.inspection_expiry) }], cars, { empty: 'لا توجد سيارات مسجلة.', onRow: true });
    bindRows(box, cars, v => carForm(v));
  }
  $('#cdnew', page).onclick = () => tab === 'docs' ? docForm(null) : carForm(null);

  function docForm(d) { const v = d || { doc_type: 'cr' };
    const m = modal(d ? tr('تعديل مستند') : tr('مستند جديد للمنشأة'), `<div class="fg">${field('نوع المستند', `<select name="t">${Object.entries(CO_DOC_T).map(([k, t]) => opt(k, t[LANG === 'en' ? 1 : 0], v.doc_type)).join('')}</select>`)}
      ${field('الاسم أو الوصف', inp('title', v.title, 'maxlength="120"'))}${enF('title_en', v.title_en)}${field('رقم المستند', inp('no', v.doc_no, 'dir="ltr" maxlength="60"'))}
      ${field('تاريخ الإصدار', `<input type="date" name="is" value="${esc(v.issue_date || '')}">`)}${field('تاريخ الانتهاء', `<input type="date" name="ex" value="${esc(v.expiry_date || '')}">`)}
      ${field('ملاحظات', inp('notes', v.notes, 'maxlength="500"'), 'wide')}${d ? '<div class="wide" id="cdf" style="border-top:1px solid var(--line3);padding-top:10px"></div><div class="wide"><button type="button" class="btn sm danger" id="cdd">' + esc(tr('حذف المستند')) + '</button></div>' : filePick()}</div>
      <p class="muted small">${esc(tr('يظهر التنبيه قبل الانتهاء بـ60 و30 يوما في الجرس والصفحة الرئيسية.'))}</p>`, {
      onOk: async f => { if (f.t === 'other' && (f.title || '').trim().length < 2) throw new Error('اكتب اسم المستند'); if (f.is && f.ex && f.ex < f.is) throw new Error('تاريخ الانتهاء قبل الإصدار');
        const row = { doc_type: f.t, title: blank((f.title || '').trim()), title_en: blank((f.title_en || '').trim()), doc_no: blank(f.no), issue_date: blank(f.is), expiry_date: blank(f.ex), notes: blank(f.notes) };
        if (d) await db.upd('company_documents', { id: 'eq.' + d.id }, row);
        else { const [n] = await db.ins('company_documents', Object.assign(row, { company_id: S.cid })); await attachFiles('company_document_files', 'company_document_id', n.id, $('#mform').files.files); }
        toast(tr('تم الحفظ')); route(); } });
    if (d) { fileBox($('#cdf', m), 'company_document_files', 'company_document_id', d.id).catch(() => {});
      $('#cdd', m).onclick = async () => { if (!await confirmBox(tr('حذف المستند'), tr('يُحذف المستند ومرفقاته.'), tr('حذف'))) return; try { await db.del('company_documents', { id: 'eq.' + d.id }); toast(tr('حُذف')); route(); } catch (er) { toast(er.message); } }; }
  }
  function carForm(c) { const v = c || { active: true };
    const m = modal(c ? tr('تعديل سيارة') : tr('سيارة جديدة'), `<div class="fg">${field('رقم اللوحة', inp('plate', v.plate, 'required maxlength="20" placeholder="ا ب ج 1234"'))}
      ${field('الشركة المصنعة', inp('make', v.make, 'maxlength="60" placeholder="' + esc(tr('تويوتا، هيونداي…')) + '"'))}${field('الطراز', inp('model', v.model, 'maxlength="60"'))}
      ${field('سنة الصنع', inp('year', v.year, 'type="number" min="1950" max="2100"'))}${field('اللون', inp('color', v.color, 'maxlength="30"'))}
      ${field('السائق المسؤول', `<select name="driver"><option value="">—</option>${Object.values(em).filter(e => !e.end_date || e.id === v.driver_id).map(e => opt(e.id, e.full_name + ' (' + e.emp_no + ')', v.driver_id)).join('')}</select>`)}
      ${field('انتهاء الاستمارة', `<input type="date" name="ist" value="${esc(v.istimara_expiry || '')}">`)}${field('انتهاء التأمين', `<input type="date" name="ins" value="${esc(v.insurance_expiry || '')}">`)}
      ${field('انتهاء الفحص الدوري', `<input type="date" name="insp" value="${esc(v.inspection_expiry || '')}">`)}
      ${c ? field('الحالة', `<select name="act">${opt('true', tr('مستخدمة'), String(v.active))}${opt('false', tr('موقوفة / مُباعة'), String(v.active))}</select>`) : ''}
      ${field('ملاحظات', inp('notes', v.notes, 'maxlength="500"'), 'wide')}${c ? '<div class="wide" id="vf" style="border-top:1px solid var(--line3);padding-top:10px"></div><div class="wide"><button type="button" class="btn sm danger" id="vdel">' + esc(tr('حذف السيارة')) + '</button></div>' : filePick()}</div>`, {
      onOk: async f => { if ((f.plate || '').trim().length < 2) throw new Error('اكتب رقم اللوحة');
        const row = { plate: f.plate.trim(), make: blank(f.make), model: blank(f.model), year: f.year ? +f.year : null, color: blank(f.color), driver_id: blank(f.driver),
          istimara_expiry: blank(f.ist), insurance_expiry: blank(f.ins), inspection_expiry: blank(f.insp), notes: blank(f.notes), ...(c ? { active: f.act === 'true' } : {}) };
        if (c) await db.upd('vehicles', { id: 'eq.' + c.id }, row);
        else { const [n] = await db.ins('vehicles', Object.assign(row, { company_id: S.cid })); await attachFiles('vehicle_files', 'vehicle_id', n.id, $('#mform').files.files); }
        toast(tr('تم الحفظ')); route(); } });
    if (c) { fileBox($('#vf', m), 'vehicle_files', 'vehicle_id', c.id).catch(() => {});
      $('#vdel', m).onclick = async () => { if (!await confirmBox(tr('حذف السيارة'), tr('تُحذف السيارة ومرفقاتها.'), tr('حذف'))) return; try { await db.del('vehicles', { id: 'eq.' + c.id }); toast(tr('حُذف')); route(); } catch (er) { toast(er.message); } }; }
  }
};
// for the bell: company papers and vehicle dates that end within 30 days (or already ended)
async function coExpiring() {
  if (!coCan()) return 0;
  const lim = new Date(Date.now() + 30 * 864e5 + 3 * 3600e3).toISOString().slice(0, 10);
  const [d, v] = await Promise.all([db.get('company_documents', { company_id: 'eq.' + S.cid, expiry_date: 'lte.' + lim, select: 'id' }).catch(() => []),
    db.get('vehicles', { company_id: 'eq.' + S.cid, active: 'eq.true', or: `(istimara_expiry.lte.${lim},insurance_expiry.lte.${lim},inspection_expiry.lte.${lim})`, select: 'id' }).catch(() => [])]);
  return d.length + v.length;
}
