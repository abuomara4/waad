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
  const carNext = v => [v.istimara_expiry, v.insurance_expiry, v.inspection_expiry, v.next_service_date].filter(Boolean).sort()[0] || null;
  const y0 = today().slice(0, 4) + '-01-01', logs = tab === 'vehicles' ? await db.get('vehicle_logs', { company_id: 'eq.' + S.cid, day: 'gte.' + y0, select: 'vehicle_id,kind,amount' }).catch(() => []) : [];
  const cost = {}; logs.forEach(l => { const c = cost[l.vehicle_id] = cost[l.vehicle_id] || { fuel: 0, other: 0 }; c[l.kind === 'fuel' ? 'fuel' : 'other'] += n0(l.amount); });
  const svcDue = v => (v.next_service_date && expLeft(v.next_service_date) <= 30) || (v.next_service_km && v.odometer && v.odometer >= v.next_service_km - 500);
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
      { t: 'التأمين', h: v => expBadge(v.insurance_expiry) }, { t: 'الفحص الدوري', h: v => expBadge(v.inspection_expiry) },
      { t: 'الصيانة القادمة', h: v => (v.next_service_date ? fdate(v.next_service_date) : '') + (v.next_service_km ? ` <span class="num small">${v.next_service_km} ${esc(tr('كم'))}</span>` : '') + (svcDue(v) ? ` <span class="badge bad">${esc(tr('مستحقة'))}</span>` : '') || '—' },
      { t: 'العداد', r: 1, h: v => v.odometer ? `<span class="num">${v.odometer}</span>` : '—' }, { t: 'مصاريف السنة (وقود / صيانة)', r: 1, h: v => cost[v.id] ? `<span class="num">${money(cost[v.id].fuel)} / ${money(cost[v.id].other)}</span>` : '—' }], cars, { empty: 'لا توجد سيارات مسجلة.', onRow: true });
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
      ${field('قراءة العداد (كم)', inp('odo', v.odometer, 'type="number" min="0"'))}${field('الصيانة كل (كم)', inp('sek', v.service_every_km, 'type="number" min="1" placeholder="5000"'))}
      ${field('أو كل (أشهر)', inp('sem', v.service_every_months, 'type="number" min="1" max="60" placeholder="6"'))}${field('الصيانة القادمة بتاريخ', `<input type="date" name="nsd" value="${esc(v.next_service_date || '')}">`)}
      ${field('أو عند العداد (كم)', inp('nsk', v.next_service_km, 'type="number" min="0"'))}
      ${c ? field('الحالة', `<select name="act">${opt('true', tr('مستخدمة'), String(v.active))}${opt('false', tr('موقوفة / مُباعة'), String(v.active))}</select>`) : ''}
      ${field('ملاحظات', inp('notes', v.notes, 'maxlength="500"'), 'wide')}${c ? '<div class="wide" id="vf" style="border-top:1px solid var(--line3);padding-top:10px"></div><div class="wide"><button type="button" class="btn sm danger" id="vdel">' + esc(tr('حذف السيارة')) + '</button></div>' : filePick()}</div>`, {
      onOk: async f => { if ((f.plate || '').trim().length < 2) throw new Error('اكتب رقم اللوحة');
        const row = { plate: f.plate.trim(), make: blank(f.make), model: blank(f.model), year: f.year ? +f.year : null, color: blank(f.color), driver_id: blank(f.driver),
          istimara_expiry: blank(f.ist), insurance_expiry: blank(f.ins), inspection_expiry: blank(f.insp), notes: blank(f.notes), ...(c ? { active: f.act === 'true' } : {}),
          odometer: f.odo === '' ? null : +f.odo, service_every_km: f.sek === '' ? null : +f.sek, service_every_months: f.sem === '' ? null : +f.sem, next_service_date: blank(f.nsd), next_service_km: f.nsk === '' ? null : +f.nsk };
        if (c) await db.upd('vehicles', { id: 'eq.' + c.id }, row);
        else { const [n] = await db.ins('vehicles', Object.assign(row, { company_id: S.cid })); await attachFiles('vehicle_files', 'vehicle_id', n.id, $('#mform').files.files); }
        toast(tr('تم الحفظ')); route(); } });
    if (c) { fileBox($('#vf', m), 'vehicle_files', 'vehicle_id', c.id).catch(() => {});
      $('#vf', m).insertAdjacentHTML('afterend', `<div class="wide" id="vlog" style="border-top:1px solid var(--line3);padding-top:10px"></div>`); vehicleLog($('#vlog', m), c, em);
      $('#vdel', m).onclick = async () => { if (!await confirmBox(tr('حذف السيارة'), tr('تُحذف السيارة ومرفقاتها.'), tr('حذف'))) return; try { await db.del('vehicles', { id: 'eq.' + c.id }); toast(tr('حُذف')); route(); } catch (er) { toast(er.message); } }; }
  }
};
// a vehicle's log: fuel, maintenance and service costs (a service moves the next service date / km), 0119
const VLOG_K = { fuel: 'وقود', service: 'صيانة دورية', maintenance: 'صيانة', repair: 'إصلاح', other: 'أخرى' };
async function vehicleLog(box, c, em) {
  const draw = async () => { const ls = await db.get('vehicle_logs', { vehicle_id: 'eq.' + c.id, order: 'day.desc,created_at.desc', limit: 50 }).catch(() => []);
    box.innerHTML = `<div class="row" style="justify-content:space-between;align-items:center"><label>${esc(tr('سجل الوقود والصيانة'))}</label><button type="button" class="btn sm" id="vlnew">+ ${esc(tr('تسجيل'))}</button></div>` +
      (ls.length ? tbl([{ t: 'التاريخ', h: l => fdate(l.day) }, { t: 'النوع', h: l => esc(tr(VLOG_K[l.kind])) }, { t: 'المبلغ', r: 1, h: l => money(l.amount) }, { t: 'العداد', r: 1, h: l => l.odometer ? `<span class="num">${l.odometer}</span>` : '—' },
        { t: 'ملاحظة', h: l => esc(l.note || '') + (l.liters ? ` <span class="num small">${l.liters} ${esc(tr('لتر'))}</span>` : '') + (l.entry_id ? ` <span class="badge ok">${esc(tr('مُرحّل'))}</span>` : '') }], ls) : `<p class="muted small">${esc(tr('لا توجد قيود بعد.'))}</p>`);
    $('#vlnew', box).onclick = () => { const f = document.createElement('div');
      f.innerHTML = `<div class="fg" style="margin-top:8px">${field('النوع', `<select name="vk">${Object.entries(VLOG_K).map(([k, t]) => opt(k, tr(t))).join('')}</select>`)}${field('التاريخ', `<input type="date" name="vd" value="${today()}" max="${today()}">`)}
        ${field('المبلغ', inp('va', '', 'type="number" min="0" step="0.01"'))}${field('العداد (كم)', inp('vo', '', 'type="number" min="0"'))}${field('اللترات', inp('vlt', '', 'type="number" min="0" step="0.01"'))}${field('دُفع من', `<select name="vpf">${opt('1120', tr('البنك'))}${opt('1110', tr('الصندوق'))}</select>`)}${field('ملاحظة', inp('vn', '', 'maxlength="300"'))}
        <div class="wide"><button type="button" class="btn pri sm" id="vlsave">${esc(tr('حفظ'))}</button></div></div>`;
      box.appendChild(f); $('#vlnew', box).hidden = true;
      $('#vlsave', box).onclick = async () => { const g = n => f.querySelector('[name=' + n + ']').value;
        try { await db.ins('vehicle_logs', { company_id: S.cid, vehicle_id: c.id, kind: g('vk'), day: g('vd'), amount: +g('va') || 0, odometer: g('vo') === '' ? null : +g('vo'), liters: g('vlt') === '' ? null : +g('vlt'), driver_id: c.driver_id || null, note: blank(g('vn')), paid_from: g('vpf') });
          toast(tr('تم الحفظ')); draw(); } catch (e) { toast(e.message); } }; }; };
  await draw();
}
// for the bell: company papers and vehicle dates that end within 30 days (or already ended)
async function coExpiring() {
  if (!coCan()) return 0;
  const lim = new Date(Date.now() + 30 * 864e5 + 3 * 3600e3).toISOString().slice(0, 10);
  const [d, v] = await Promise.all([db.get('company_documents', { company_id: 'eq.' + S.cid, expiry_date: 'lte.' + lim, select: 'id' }).catch(() => []),
    db.get('vehicles', { company_id: 'eq.' + S.cid, active: 'eq.true', or: `(istimara_expiry.lte.${lim},insurance_expiry.lte.${lim},inspection_expiry.lte.${lim},next_service_date.lte.${lim})`, select: 'id' }).catch(() => [])]);
  return d.length + v.length;
}
