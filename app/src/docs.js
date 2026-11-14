'use strict';
/* ===== employee documents and contracts: expiry alerts (Labor Law Arts. 37, 55, 75) ===== */
const DOC_T = { iqama: 'الإقامة', national_id: 'الهوية الوطنية', passport: 'جواز السفر', work_permit: 'رخصة العمل', health: 'الشهادة الصحية', driving: 'رخصة القيادة', other: 'مستند آخر', contract: 'عقد العمل', probation: 'نهاية فترة التجربة', service5: 'إكمال 5 سنوات خدمة' };
const DOC_LVL = { expired: ['منتهي', 'bad'], d30: ['خلال 30 يوما', 'bad'], d60: ['خلال 60 يوما', 'wait'], d90: ['خلال 90 يوما', 'info'], missing: ['غير مسجّل', 'wait'] };
const CT_T = { fixed: 'محدد المدة', indefinite: 'غير محدد المدة' };
const lvlBadge = l => `<span class="badge ${DOC_LVL[l][1]}">${esc(DOC_LVL[l][0])}</span>`;
const daysTxt = n => n == null ? '—' : n < 0 ? 'منتهي منذ ' + (-n) + ' يوم' : n === 0 ? 'ينتهي اليوم' : 'باقي ' + n + ' يوم';
const docName = d => d.doc_type === 'other' ? (d.title || DOC_T.other) : DOC_T[d.doc_type];
// Art. 75: notice for an indefinite contract — 30 days from the worker, 60 from the employer (30 both ways if not paid monthly)
const noticeTxt = c => c.contract_type === 'fixed' ? 'ينتهي بانتهاء مدته، ويُستحق التعويض عن المدة الباقية إذا أُنهي قبلها بلا سبب مشروع (م77)'
  : c.monthly_paid ? 'مهلة الإشعار: 30 يوما إذا أنهاه الموظف، و60 يوما إذا أنهته المنشأة (م75)' : 'مهلة الإشعار: 30 يوما من أي طرف (م75)';
async function docAlertCount() { try { return (await db.rpc('doc_alerts', { p_company: S.cid, p_within: 30 })).filter(a => a.level === 'expired' || a.level === 'd30').length; } catch (e) { return 0; } }
const docWaMsg = (a, e) => 'السلام عليكم ' + String(e.full_name || '').split(' ')[0] + '،\n' + (a.days_left < 0 ? 'انتهت ' : 'تنتهي ') + DOC_T[a.label] + (a.ref_no ? ' رقم ' + a.ref_no : '') + ' بتاريخ ' + a.due + '.\nنأمل تجهيز متطلبات التجديد والتواصل مع الموارد البشرية.\n' + S.company.name;
// #9/#10 attachments widget: list, open, upload and delete files for one parent row (document or contract)
async function fileBox(box, table, key, id) {
  const draw = async () => {
    const fs = await db.get(table, Object.assign({ select: 'id,file_name,size', order: 'created_at' }, { [key]: 'eq.' + id })).catch(() => []);
    box.innerHTML = `<label>${esc(tr('المرفقات'))}</label>` + (fs.length ? fs.map(x => `<div class="row" style="gap:8px;align-items:center"><a href="#" data-fo="${x.id}">${esc(x.file_name)}</a><span class="num muted small">${Math.ceil(x.size / 1024)} KB</span><button type="button" class="btn sm" data-fd="${x.id}" aria-label="${esc(tr('حذف المرفق'))}">×</button></div>`).join('') : `<div class="small muted">${esc(tr('لا توجد مرفقات'))}</div>`)
      + `<label class="btn sm" style="margin-top:6px">${esc(tr('إرفاق ملف'))}<input type="file" accept=".pdf,.doc,.docx,image/*" hidden></label> <span class="small muted">${esc(tr('PDF أو Word أو صورة — حتى 3 ميجابايت'))}</span><div class="fbe"></div>`;
    $$('[data-fo]', box).forEach(a => a.onclick = e => { e.preventDefault(); openAttachment(a.dataset.fo, table); });
    $$('[data-fd]', box).forEach(b => b.onclick = async () => { try { await db.del(table, { id: 'eq.' + b.dataset.fd }); draw(); } catch (er) { showErr($('.fbe', box), er); } });
    $('input[type=file]', box).onchange = async ev => { const file = ev.target.files[0]; if (!file) return;
      try { let a;
        if (/\.(docx?)$/i.test(file.name)) { if (file.size > 3 * 1048576) throw new Error(tr('حجم الملف أكبر من 3 ميجابايت') + ': ' + file.name);
          a = { name: file.name, mime: /\.docx$/i.test(file.name) ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' : 'application/msword', data: await blobB64(file) }; }
        else a = await readAttachment(file);
        await db.ins(table, Object.assign({ company_id: S.cid, file_name: a.name, mime: a.mime, size: Math.round(a.data.length * 3 / 4), data: a.data }, { [key]: id })); draw();
      } catch (er) { showErr($('.fbe', box), er); } ev.target.value = ''; };
  };
  await draw();
}

VIEWS['#/docs'] = async (page, arg) => {
  if (!isHR()) { page.innerHTML = '<div class="note">هذه الصفحة للموارد البشرية.</div>'; return; }
  if (arg && arg !== 'all') return docsEmployee(page, arg);
  const within = +(new URLSearchParams(location.hash.split('?')[1] || '').get('d') || 90);
  const [alerts, em] = await Promise.all([db.rpc('doc_alerts', { p_company: S.cid, p_within: within }), employeesMap(true)]);
  NAVC.docs = alerts.filter(a => a.level === 'expired' || a.level === 'd30').length; drawNav();
  const c = l => alerts.filter(a => a.level === l).length;
  page.innerHTML = `<div class="head"><div><h1>المستندات والعقود</h1><div class="muted">الإقامات ورخص العمل والجوازات والعقود ونهاية فترات التجربة وإكمال 5 سنوات خدمة — نحفظ الأرقام والتواريخ فقط بدون صور المستندات</div></div>
      <div class="row"><select id="dw" style="width:auto">${[30, 60, 90, 180].map(n => opt(n, 'خلال ' + n + ' يوما', within)).join('')}</select><button class="btn" id="imd">استيراد المستندات</button><button class="btn" id="imc">استيراد العقود</button></div></div>
    <div class="grid" style="margin-bottom:16px">
      <div class="card kpi"><div class="muted small">منتهية</div><div class="v num ${c('expired') ? 'bad' : ''}">${c('expired')}</div></div>
      <div class="card kpi"><div class="muted small">خلال 30 يوما</div><div class="v num ${c('d30') ? 'bad' : ''}">${c('d30')}</div></div>
      <div class="card kpi"><div class="muted small">خلال 31–${within} يوما</div><div class="v num">${c('d60') + c('d90')}</div></div>
      <div class="card kpi"><div class="muted small">غير مسجّلة</div><div class="v num">${c('missing')}</div></div></div>
    ${tbl([{ t: 'الموظف', h: a => esc((em[a.employee_id] || {}).full_name || '') }, { t: 'البند', h: a => esc(DOC_T[a.label] || a.label) + (a.ref_no ? ` <span class="num muted small">${esc(a.ref_no)}</span>` : '') },
      { t: 'تاريخ الانتهاء', h: a => fdate(a.due) }, { t: 'المتبقي', h: a => daysTxt(a.days_left) }, { t: 'الحالة', h: a => lvlBadge(a.level) },
      { t: 'ملاحظة', h: a => a.note ? `<span class="small">${esc(a.note)}</span>` : '' },
      { t: '', h: a => a.kind === 'doc' && em[a.employee_id] ? waBtn(em[a.employee_id].phone, tr(docWaMsg(a, em[a.employee_id])), 'تذكير', 'btn sm wa') : '' }], alerts, { empty: 'لا توجد تنبيهات — كل المستندات والعقود سارية', onRow: true })}
    <p class="muted small">غير السعودي: يُفترض وجود إقامة ورخصة عمل سارية، وعقد مكتوب محدد المدة (م37). عدم تجديد رخص العمل والإقامة يعرّض المنشأة لإيقاف الخدمات.</p>
    <h2 style="margin-top:20px">الموظفون</h2>${tbl([{ t: 'الرقم', k: 'emp_no' }, { t: 'الاسم', k: 'full_name' }, { t: 'الجنسية', h: e => e.is_saudi ? 'سعودي' : 'غير سعودي' }, { t: 'التنبيهات', r: 1, h: e => alerts.filter(a => a.employee_id === e.id).length || '' }],
      Object.values(em).filter(e => !e.end_date || e.end_date >= today()), { empty: 'لا يوجد موظفون', onRow: true })}`;
  const [t1, t2] = $$('.tw', page);
  bindRows(t1, alerts, a => location.hash = '#/docs/' + a.employee_id);
  bindRows(t2, Object.values(em).filter(e => !e.end_date || e.end_date >= today()), e => location.hash = '#/docs/' + e.id);
  $$('a.wa', page).forEach(a => a.addEventListener('click', ev => ev.stopPropagation()));
  $('#dw', page).onchange = ev => location.hash = '#/docs?d=' + ev.target.value;
  $('#imd', page).onclick = () => importDocsDialog();
  $('#imc', page).onclick = () => importContractsDialog();
};

async function docsEmployee(page, id) {
  const em = await employeesMap(true), e = em[id];
  if (!e) throw new Error('الموظف غير موجود');
  const [docs, cons] = await Promise.all([db.get('employee_documents', { employee_id: 'eq.' + id, order: 'expiry_date.asc.nullslast' }), db.get('contracts', { employee_id: 'eq.' + id, order: 'start_date.desc' })]);
  const cur = cons.find(c => c.status === 'active'), td = today();
  const left = d => d ? Math.round((new Date(d) - new Date(td)) / 864e5) : null;
  const st = d => { const n = left(d); return n == null ? '' : n < 0 ? lvlBadge('expired') : n <= 30 ? lvlBadge('d30') : n <= 60 ? lvlBadge('d60') : n <= 90 ? lvlBadge('d90') : '<span class="badge ok">ساري</span>'; };
  const conv = cur && cur.contract_type === 'fixed' && e.is_saudi && (cur.renewal_no >= 3 || (new Date(cur.end_date) - new Date(cur.first_start)) / 864e5 >= 4 * 365 - 1);
  page.innerHTML = `<div class="head"><div><a href="#/docs" class="small">← المستندات والعقود</a><h1>${esc(e.full_name)}</h1><div class="muted"><span class="num">${esc(e.emp_no)}</span> · ${e.is_saudi ? 'سعودي' : 'غير سعودي'} · المباشرة ${fdate(e.hire_date)}</div></div></div>
    <div class="card"><div class="row" style="justify-content:space-between"><h2>العقد</h2><div class="row">${cur && cur.contract_type === 'fixed' ? '<button class="btn sm" id="crn">تجديد</button><button class="btn sm" id="cind">تحويل لغير محدد المدة</button>' : ''}<button class="btn sm pri" id="cnew">عقد جديد</button></div></div>
      ${cur ? `<div class="tw"><table><tbody>
        <tr><td class="muted">النوع</td><td>${esc(CT_T[cur.contract_type])}${cur.renewal_no ? ' — التجديد رقم ' + cur.renewal_no : ''}</td></tr>
        <tr><td class="muted">من</td><td>${fdate(cur.start_date)}</td></tr><tr><td class="muted">إلى</td><td>${cur.end_date ? fdate(cur.end_date) + ' ' + st(cur.end_date) : '—'}</td></tr>
        <tr><td class="muted">بداية أول عقد</td><td>${fdate(cur.first_start)}</td></tr>
        <tr><td class="muted">الإشعار</td><td class="small">${esc(noticeTxt(cur))}</td></tr></tbody></table></div>
        ${conv ? '<div class="note" style="margin-top:10px">جُدد العقد ثلاث مرات أو بلغت مدته أربع سنوات؛ إذا استمر الطرفان بعد نهايته يتحوّل إلى غير محدد المدة (م55).</div>' : ''}
        ${cur.contract_type === 'fixed' && !e.is_saudi ? '<p class="muted small">إذا استمر العمل بعد انتهاء العقد عُدّ متجددا لمدة مماثلة (م37).</p>' : ''}`
      : `<div class="note">لا يوجد عقد مسجّل لهذا الموظف.${e.is_saudi ? '' : ' عقد غير السعودي يكون مكتوبا ومحدد المدة (م37).'}</div>`}
      ${cons.length > 1 ? `<details style="margin-top:10px"><summary class="small">العقود السابقة (${cons.length - 1})</summary>${tbl([{ t: 'النوع', h: c => esc(CT_T[c.contract_type]) }, { t: 'من', h: c => fdate(c.start_date) }, { t: 'إلى', h: c => fdate(c.end_date) }, { t: 'الحالة', h: c => c.status === 'renewed' ? 'جُدّد' : 'انتهى' }], cons.filter(c => c !== cur))}</details>` : ''}
      ${cur ? '<div id="cfiles" style="margin-top:12px;border-top:1px solid var(--line3);padding-top:10px"></div>' : ''}</div>
    <div class="card" id="dcard"><div class="row" style="justify-content:space-between"><h2>المستندات</h2><button class="btn sm pri" id="dnew">+ مستند</button></div>
      ${tbl([{ t: 'المستند', h: d => esc(docName(d)) }, { t: 'الرقم', h: d => `<span class="num">${esc(d.doc_no || '—')}</span>` }, { t: 'تاريخ الإصدار', h: d => fdate(d.issue_date) }, { t: 'تاريخ الانتهاء', h: d => fdate(d.expiry_date) }, { t: 'الحالة', h: d => st(d.expiry_date) }], docs, { empty: 'لا توجد مستندات مسجّلة', onRow: true })}
      ${!e.is_saudi ? '<p class="muted small">لغير السعودي: سجّل الإقامة ورخصة العمل وجواز السفر.</p>' : ''}</div>
    <div id="lvbox"></div><div id="custbox"></div><div id="clrbox"></div>`;
  leaveStatementCard($('#lvbox', page), e).catch(() => {});
  custodyCard($('#custbox', page), e).catch(er => toast(er.message));
  clearanceCard($('#clrbox', page), e).catch(() => {});
  if (cur) fileBox($('#cfiles', page), 'contract_files', 'contract_id', cur.id).catch(() => {});
  const docForm = d => { const v = d || { doc_type: e.is_saudi ? 'national_id' : 'iqama', doc_no: (!d && e.national_id) ? e.national_id : '' };
    const m = modal(d ? 'تعديل مستند' : 'مستند جديد', `<div class="fg">${field('نوع المستند', `<select name="t">${Object.entries(DOC_T).filter(([k]) => k !== 'contract').map(([k, t]) => opt(k, t, v.doc_type)).join('')}</select>`)}
      <div data-o>${field('اسم المستند', inp('title', v.title))}</div><div data-o>${enF('title_en', v.title_en)}</div>${field('رقم المستند', inp('no', v.doc_no, 'dir="ltr"'))}
      ${field('تاريخ الإصدار', `<input type="date" name="is" value="${esc(v.issue_date || '')}">`)}${field('تاريخ الانتهاء', `<input type="date" name="ex" value="${esc(v.expiry_date || '')}">`)}
      ${field('ملاحظات', inp('notes', v.notes), 'wide')}${d ? '<div class="wide" id="dfiles" style="border-top:1px solid var(--line3);padding-top:10px"></div><div class="wide"><button type="button" class="btn sm danger" id="ddel">حذف المستند</button></div>' : ''}</div>
      <p class="muted small">التنبيه يظهر قبل الانتهاء بـ90 و60 و30 يوما. عند التجديد عدّل تاريخ الانتهاء أو أضف المستند الجديد.</p>`, {
      onOk: async f => { if (f.t === 'other' && (f.title || '').trim().length < 2) throw new Error('أدخل اسم المستند'); if (f.is && f.ex && f.ex < f.is) throw new Error('تاريخ الانتهاء قبل الإصدار');
        const row = { doc_type: f.t, title: f.t === 'other' ? f.title.trim() : null, title_en: f.t === 'other' ? blank((f.title_en || '').trim()) : null, doc_no: blank(f.no), issue_date: blank(f.is), expiry_date: blank(f.ex), notes: blank(f.notes) };
        if (d) await db.upd('employee_documents', { id: 'eq.' + d.id }, row); else await db.ins('employee_documents', Object.assign(row, { company_id: S.cid, employee_id: id })); toast('تم الحفظ'); route(); } });
    const sync = () => $$('[data-o]', m).forEach(x => x.hidden = $('select[name=t]', m).value !== 'other'); $('select[name=t]', m).onchange = sync; sync();
    if (d) fileBox($('#dfiles', m), 'document_files', 'document_id', d.id).catch(() => {});
    if (d) $('#ddel', m).onclick = async () => { try { await db.del('employee_documents', { id: 'eq.' + d.id }); m.close(); route(); } catch (er) { showErr($('#merr', m), er); } }; };
  bindRows($('#dcard', page), docs, docForm);
  $('#dnew', page).onclick = () => docForm(null);
  $('#cnew', page).onclick = () => { const m = modal('عقد جديد', `<div class="fg">${field('نوع العقد', `<select name="ty">${e.is_saudi ? opt('indefinite', CT_T.indefinite) : ''}${opt('fixed', CT_T.fixed, 'fixed')}</select>`)}
      ${field('تاريخ البداية', `<input type="date" name="st" value="${cur ? '' : esc(e.hire_date)}">`)}<div data-f>${field('تاريخ النهاية', `<input type="date" name="en">`)}</div>
      ${field('الأجر', `<select name="mp">${opt('true', 'شهري')}${opt('false', 'غير شهري')}</select>`)}<div data-f>${field('فيه شرط تجديد تلقائي؟', `<select name="cl">${opt('false', 'لا')}${opt('true', 'نعم')}</select>`)}</div>${field('ملاحظات', inp('notes', ''), 'wide')}</div>
      <p class="muted small">${e.is_saudi ? 'العقد المحدد المدة إذا استمر الطرفان بعد نهايته صار غير محدد المدة (م55).' : 'عقد غير السعودي محدد المدة؛ إذا لم تُحدد النهاية فمدته سنة من تاريخ البداية (م37).'}${cur ? ' سيُغلق العقد الحالي.' : ''}</p>`, {
      onOk: async f => { if (!f.st) throw new Error('أدخل تاريخ بداية العقد'); if (f.ty === 'fixed' && f.en && f.en < f.st) throw new Error('تاريخ النهاية قبل البداية');
        await db.rpc('contract_add', { p_company: S.cid, p_emp: id, p_type: f.ty, p_start: f.st, p_end: f.ty === 'fixed' ? blank(f.en) : null, p_monthly: f.mp === 'true', p_clause: f.cl === 'true', p_notes: blank(f.notes) }); toast('تم الحفظ'); route(); } });
    const sync = () => $$('[data-f]', m).forEach(x => x.hidden = $('select[name=ty]', m).value !== 'fixed'); $('select[name=ty]', m).onchange = sync; sync(); };
  if ($('#crn', page)) $('#crn', page).onclick = () => { const def = new Date(new Date(cur.end_date).getTime() + (new Date(cur.end_date) - new Date(cur.start_date)) + 864e5).toISOString().slice(0, 10);
    modal('تجديد العقد', `<p class="small">يبدأ التجديد من <b class="num">${fdate(new Date(new Date(cur.end_date).getTime() + 864e5).toISOString())}</b>، اليوم التالي لنهاية العقد الحالي.</p>${field('نهاية العقد الجديد', `<input type="date" name="en" value="${def}">`)}
      ${e.is_saudi && cur.renewal_no >= 2 ? '<div class="note" style="margin-top:10px">هذا التجديد الثالث؛ إذا استمر الطرفان بعد نهايته يتحوّل العقد إلى غير محدد المدة (م55).</div>' : ''}`, {
      ok: 'تجديد', onOk: async f => { await db.rpc('contract_renew', { p_id: cur.id, p_end: f.en }); toast('جُدد العقد'); route(); } }); };
  if ($('#cind', page)) $('#cind', page).onclick = () => { if (!e.is_saudi) return toast('عقد غير السعودي يكون محدد المدة — م37');
    modal('تحويل إلى غير محدد المدة', `${field('من تاريخ', `<input type="date" name="fr" value="${esc(today())}">`)}<p class="muted small">يبقى تاريخ بداية الخدمة كما هو، ويُحفظ العقد الحالي في السجل.</p>`, {
      ok: 'تحويل', onOk: async f => { await db.rpc('contract_make_indefinite', { p_id: cur.id, p_from: blank(f.fr) }); toast('تم الحفظ'); route(); } }); };
  await payAndRequestsSection(page, e);
  await lettersSection(page, e);
}

/* ===== pay: salary history, extra allowances, compensatory leave, the employee's requests ===== */
const allowActive = (a, d = today()) => a.start_on <= d && (!a.end_on || a.end_on >= d);
async function payAndRequestsSection(page, e) {
  const [als, hist, cc, [cb], rqs, lt] = await Promise.all([db.get('employee_allowances', { employee_id: 'eq.' + e.id, order: 'start_on.desc' }).catch(() => []),
    db.get('salary_history', { employee_id: 'eq.' + e.id, order: 'created_at.desc' }).catch(() => []), db.get('comp_credits', { employee_id: 'eq.' + e.id, order: 'earned_on.desc' }).catch(() => []),
    db.rpc('comp_balance', { p_emp: e.id }).catch(() => [null]), db.get('requests', { employee_id: 'eq.' + e.id, order: 'created_at.desc', limit: 30 }).catch(() => []), LEAVE_TYPES().catch(() => [])]);
  const ltn = {}; lt.forEach(l => ltn[l.code] = l.name_ar);
  const other = als.filter(a => allowActive(a)).reduce((s, a) => s + n0(a.amount), 0), gross = n0(e.basic) + n0(e.housing) + n0(e.transport) + other;
  const bal = cb || { earned_hours: 0, used_hours: 0, balance_hours: 0 };
  page.insertAdjacentHTML('beforeend', `<div class="card" id="paycard"><div class="row" style="justify-content:space-between"><h2>الأجر والبدلات</h2><div class="row"><button class="btn sm" id="salch">تعديل الأجر</button><button class="btn sm pri" id="alnew">+ بدل</button></div></div>
      <div class="tw"><table><tbody><tr><td class="muted">الراتب الأساسي</td><td class="r num">${money(e.basic)}</td></tr><tr><td class="muted">بدل السكن</td><td class="r num">${money(e.housing)}</td></tr><tr><td class="muted">بدل النقل</td><td class="r num">${money(e.transport)}</td></tr><tr><td class="muted">بدلات أخرى</td><td class="r num">${money(other)}</td></tr></tbody>
      <tfoot><tr><td>الأجر الفعلي الشهري</td><td class="r num">${money(gross)}</td></tr></tfoot></table></div>
      <div id="altbl">${tbl([{ t: 'البدل', h: a => esc(a.name) }, { t: 'المبلغ الشهري', r: 1, h: a => money(a.amount) }, { t: 'من', h: a => fdate(a.start_on) }, { t: 'إلى', h: a => a.end_on ? fdate(a.end_on) : '—' },
        { t: 'الحالة', h: a => allowActive(a) ? '<span class="badge ok">ساري</span>' : a.start_on > today() ? '<span class="badge info">لم يبدأ</span>' : '<span class="badge">منتهٍ</span>' }], als, { empty: 'لا توجد بدلات أخرى', onRow: true })}</div>
      <p class="muted small">البدلات الثابتة جزء من الأجر الفعلي (م2)، فتدخل في المسير والعمل الإضافي والغياب ومكافأة نهاية الخدمة. اشتراك التأمينات يبقى على الأساسي والسكن.</p>
      <details style="margin-top:8px"><summary class="small">سجل الرواتب (${hist.length})</summary>${tbl([{ t: 'تاريخ السريان', h: h => fdate(h.effective_on) }, { t: 'الأساسي', r: 1, h: h => money(h.basic) }, { t: 'السكن', r: 1, h: h => money(h.housing) }, { t: 'النقل', r: 1, h: h => money(h.transport) },
        { t: 'أخرى', r: 1, h: h => money(h.allowances) }, { t: 'الإجمالي', r: 1, h: h => money(h.gross) }, { t: 'التغيير', r: 1, h: h => h.prev_gross == null ? '—' : `<span class="num ${n0(h.gross) < n0(h.prev_gross) ? 'bad' : n0(h.gross) > n0(h.prev_gross) ? 'ok' : ''}">${n0(h.gross) > n0(h.prev_gross) ? '+' : ''}${money(n0(h.gross) - n0(h.prev_gross))}</span>` },
        { t: 'السبب', h: h => `<span class="small">${esc(h.reason || '')}</span>` }, { t: 'سُجّل في', h: h => fdate(h.created_at) }], hist, { empty: 'لا يوجد سجل' })}</details></div>
    <div class="card" id="compcard"><div class="row" style="justify-content:space-between"><h2>الإجازة التعويضية</h2><button class="btn sm pri" id="ccnew">+ ساعات تعويضية</button></div>
      <div class="grid"><div class="card kpi"><div class="muted small">المكتسب</div><div class="v num">${r2(bal.earned_hours)}</div></div><div class="card kpi"><div class="muted small">المستخدم والمحجوز</div><div class="v num">${r2(bal.used_hours)}</div></div>
        <div class="card kpi"><div class="muted small">الرصيد بالساعات</div><div class="v num">${r2(bal.balance_hours)}</div></div><div class="card kpi"><div class="muted small">قيمة الرصيد</div><div class="v num">${money(r2(Math.max(0, n0(bal.balance_hours)) * gross / 30 / 8))}</div></div></div>
      ${tbl([{ t: 'تاريخ العمل الإضافي', h: c => fdate(c.earned_on) }, { t: 'ساعات إضافية', r: 1, h: c => r2(c.ot_hours) }, { t: 'ساعات الإجازة', r: 1, h: c => r2(c.hours) }, { t: 'تُستخدم قبل', h: c => fdate(c.use_by) + (c.use_by < today() ? ' <span class="badge wait">' + esc('انتهت المهلة') + '</span>' : '') }, { t: 'ملاحظة', h: c => `<span class="small">${esc(c.note || '')}</span>` }], cc, { empty: 'لا توجد ساعات تعويضية' })}
      <p class="muted small">م107 والمادة 22 مكرر من اللائحة: بموافقة العامل يُعوَّض عن العمل الإضافي بإجازة مدفوعة بدل الأجر، بما لا يقل عن ساعة ونصف عن كل ساعة، وبحد 30 يوما في السنة، وتُؤخذ خلال 60 يوما ما لم يُتفق على غير ذلك. إذا انتهت العلاقة قبل استخدامها يُصرف للعامل أجرها، ويظهر ذلك في حساب نهاية الخدمة. للتحويل من سجل الحضور: افتح يوم العمل من صفحة الحضور.</p></div>
    <div class="card" id="rqcard"><h2>طلبات الموظف</h2>${tbl([{ t: 'النوع', h: r => esc(KIND[r.kind] + (r.sub ? ' — ' + (ltn[r.sub] || r.sub) : '')) }, { t: 'من', h: r => fdate(r.from_date) }, { t: 'إلى', h: r => fdate(r.to_date) },
      { t: 'الحالة', h: r => badge(r.status) + (r.payload && r.payload.defer_until ? ' <span class="badge wait">' + esc('قبول مؤجل') + '</span>' : '') }, { t: 'تاريخ الطلب', h: r => fdate(r.created_at) }], rqs, { empty: 'لا توجد طلبات', onRow: true })}</div>`);
  bindRows($('#rqcard', page), rqs, r => requestDetail(Object.assign({ _emp: e }, r)));
  const alForm = a => modal(a ? 'تعديل بدل' : 'بدل جديد', `<div class="fg">${field('اسم البدل', inp('name', a ? a.name : '', 'required placeholder="مثال: بدل اتصال، بدل طبيعة عمل"'))}${enF('name_en', a ? a.name_en : '', 'اسم البدل بالإنجليزية')}
      ${field('المبلغ الشهري', inp('amount', a ? a.amount : '', 'type="number" step="0.01" min="0"'))}${field('من تاريخ', `<input type="date" name="st" value="${esc(a ? a.start_on : today())}">`)}${field('إلى تاريخ (اتركه فارغا إن كان مستمرا)', `<input type="date" name="en" value="${esc(a && a.end_on || '')}">`)}${field('ملاحظة', inp('note', a ? a.note : ''), 'wide')}</div>
      <p class="muted small">لإيقاف البدل حدد تاريخ النهاية؛ لا يُحذف حتى يبقى في السجل. يدخل البدل مسير الشهر إذا كان ساريا في آخر يوم منه.</p>`, {
      onOk: async f => { const x = await db.rpc('allowance_save', { p_id: a ? a.id : null, p_emp: e.id, p_name: f.name, p_name_en: blank(f.name_en), p_amount: +f.amount || 0, p_start: blank(f.st), p_end: blank(f.en), p_note: blank(f.note) });
        if (f.name_en) EN[f.name.trim().replace(/\s+/g, ' ')] = f.name_en.trim(); cache.emps = null; toast('تم الحفظ'); route(); } });
  $('#alnew', page).onclick = () => alForm(null);
  bindRows($('#altbl', page), als, alForm);
  $('#salch', page).onclick = () => { const m = modal('تعديل الأجر', `<div class="fg">${field('الراتب الأساسي', inp('b', e.basic, 'type="number" step="0.01" min="0"'))}${field('بدل السكن', inp('h', e.housing, 'type="number" step="0.01" min="0"'))}${field('بدل النقل', inp('t', e.transport, 'type="number" step="0.01" min="0"'))}
      ${field('تاريخ السريان', `<input type="date" name="on" value="${today()}" max="${today()}">`)}${field('السبب', inp('why', '', 'required placeholder="ترقية، علاوة سنوية، تعديل عقد..."'), 'wide')}
      <label class="wide row small" id="cons" style="gap:6px;display:none"><input type="checkbox" name="ok"> ${esc('وافق العامل كتابيا على تخفيض الأجر (ملحق عقد موقّع)')}</label></div>
      <p class="muted small">يُحفظ التعديل في سجل الرواتب مع السبب، ويُعاد احتساب مسير الشهر غير المعتمد. الأجر شرط في العقد، فلا يُخفَّض إلا بموافقة العامل الكتابية. الفروقات عن أشهر معتمدة تُضاف مكافأة في المسير القادم.</p>`, {
      ok: 'حفظ التعديل', onOk: async f => { await db.rpc('salary_change', { p_emp: e.id, p_basic: +f.b || 0, p_housing: +f.h || 0, p_transport: +f.t || 0, p_effective: f.on, p_reason: f.why, p_consent: !!f.ok }); cache.emps = null; toast('عُدّل الأجر'); route(); } });
    const sync = () => { const f = $('#mform', m); if (!$('#cons', m)) return m.removeEventListener('input', sync); $('#cons', m).style.display = !(+f.b.value < n0(e.basic) || (+f.b.value + +f.h.value + +f.t.value) < n0(e.basic) + n0(e.housing) + n0(e.transport)) ? 'none' : ''; };
    m.addEventListener('input', sync); sync(); };
  $('#ccnew', page).onclick = () => modal('ساعات إجازة تعويضية', `<div class="fg">${field('تاريخ العمل الإضافي', `<input type="date" name="on" value="${today()}">`)}${field('ساعات العمل الإضافي', inp('h', '', 'type="number" step="0.25" min="0"'))}
      ${field('ساعات الإجازة عن كل ساعة (1.5 على الأقل)', inp('rate', 1.5, 'type="number" step="0.25" min="1.5"'))}${field('ملاحظة', inp('note', ''))}
      <label class="wide row small" style="gap:6px"><input type="checkbox" name="ok"> ${esc('وافق العامل على الإجازة التعويضية بدل أجر العمل الإضافي')}</label></div>
      <p class="muted small">استخدمها للعمل الإضافي الذي لم يُسجَّل في الحضور. لا تصرف أجر هذه الساعات في المسير.</p>`, {
      ok: 'إضافة', onOk: async f => { await db.rpc('comp_credit', { p_emp: e.id, p_ot_hours: +f.h || 0, p_rate: +f.rate || 0, p_on: blank(f.on), p_consent: !!f.ok, p_note: blank(f.note) }); toast('أُضيفت الساعات'); route(); } });
}

/* employee self-service: own documents and contract on the profile page */
async function myDocsHtml() {
  if (!S.emp) return '';
  const [docs, cons] = await Promise.all([db.get('employee_documents', { employee_id: 'eq.' + S.emp, order: 'expiry_date.asc.nullslast' }).catch(() => []), db.get('contracts', { employee_id: 'eq.' + S.emp, status: 'eq.active' }).catch(() => [])]);
  if (!docs.length && !cons.length) return '';
  const c = cons[0];
  return `<div class="card"><h2>مستنداتي وعقدي</h2>${c ? `<p class="small">العقد: ${esc(CT_T[c.contract_type])} من ${fdate(c.start_date)}${c.end_date ? ' إلى ' + fdate(c.end_date) : ''}. <span class="muted">${esc(noticeTxt(c))}</span></p>` : ''}
    ${docs.length ? tbl([{ t: 'المستند', h: d => esc(docName(d)) }, { t: 'الرقم', h: d => `<span class="num">${esc(d.doc_no || '—')}</span>` }, { t: 'تاريخ الانتهاء', h: d => fdate(d.expiry_date) }], docs) : ''}</div>`;
}

/* ===== ready-made letters: salary certificate and service certificate (Art. 64), printed on A4 ===== */
const LTR_KIND = { salary: 'تعريف بالراتب', service: 'شهادة خدمة' };
const LTR_COLS = [{ t: 'الرقم', h: l => `<span class="num">${esc(l.ref_no)}</span>` }, { t: 'النوع', h: l => esc(LTR_KIND[l.kind]) + (l.kind === 'salary' && !l.with_salary ? ' — بدون راتب' : '') },
  { t: 'اللغة', h: l => l.lang === 'en' ? 'إنجليزي' : 'عربي' }, { t: 'موجّه إلى', h: l => esc(l.addressee || 'إلى من يهمه الأمر') }, { t: 'تاريخ الإصدار', h: l => fdate(l.data && l.data.date) }];
const lettersOf = emp => db.get('letters', { employee_id: 'eq.' + emp, order: 'issued_at.desc' }).catch(() => []);
async function lettersSection(page, e) {
  const ls = await lettersOf(e.id), left = !!e.end_date && e.end_date <= today();
  page.insertAdjacentHTML('beforeend', `<div class="card" id="lcard"><div class="row" style="justify-content:space-between"><h2>الخطابات</h2><div class="row">
    ${left ? '' : '<button class="btn sm" id="lsal">خطاب تعريف بالراتب</button>'}<button class="btn sm${left ? ' pri' : ''}" id="lsvc">شهادة خدمة (م64)</button></div></div>
    ${tbl(LTR_COLS, ls, { empty: 'لم يصدر خطاب بعد', onRow: true })}</div>`);
  bindRows($('#lcard', page), ls, l => location.hash = '#/letter/' + l.id);
  if ($('#lsal', page)) $('#lsal', page).onclick = () => letterDialog(e, 'salary');
  $('#lsvc', page).onclick = () => left ? letterDialog(e, 'service') : toast('شهادة الخدمة تصدر عند انتهاء الخدمة — سجّل تاريخ نهاية الخدمة في بيانات الموظف أولا (م64)');
}
async function letterDialog(e, kind, req) {
  const self = !isHR(), co = LS.get('waad.enco.' + S.cid) || '';
  const prev = ((await db.get('letters', { employee_id: 'eq.' + e.id, lang: 'eq.en', order: 'issued_at.desc', limit: 1 }).catch(() => []))[0] || { data: {} }).data.en || {};
  const m = modal(kind === 'service' ? 'شهادة خدمة (م64)' : 'خطاب تعريف بالراتب', `<div class="fg">
    ${field('لغة الخطاب', `<select name="lang">${opt('ar', 'عربي')}${opt('en', 'إنجليزي')}</select>`)}
    ${field('موجّه إلى', inp('to', '', 'placeholder="إلى من يهمه الأمر"'))}
    ${kind === 'salary' ? field('الراتب', `<select name="sal">${opt('true', 'يظهر الراتب وتفاصيله')}${opt('false', 'بدون راتب')}</select>`) : ''}
    ${!self && !e.is_saudi ? field('الجنسية', inp('nat', '')) : ''}
    ${field('الاسم بالإنجليزية', inp('en_name', prev.name || e.full_name_en || '', 'dir="ltr"'), 'en-only')}${field('المسمى الوظيفي بالإنجليزية', inp('en_job', prev.job || e.job_title_en || '', 'dir="ltr"'), 'en-only')}
    ${self ? '' : field('اسم المنشأة بالإنجليزية', inp('en_co', prev.company || S.company.name_en || co, 'dir="ltr"'), 'en-only')}</div>
    ${kind === 'service' ? '<p class="muted small">المادة 64: توضّح الشهادة تاريخ الالتحاق بالعمل وتاريخ انتهائه والمهنة وآخر أجر، وتُعطى دون مقابل، ولا يجوز أن تتضمن ما يسيء إلى سمعة العامل؛ لذلك لا تذكر سبب انتهاء الخدمة ولا أي ملاحظات.</p>' : ''}
    <p class="muted small">يُسجَّل الخطاب برقم مرجعي مع البيانات وقت إصداره، ويُطبع على ورقة A4.</p>`, { ok: 'إصدار', onOk: async f => {
      const en = f.lang === 'en';
      if (en && !self && f.en_co) LS.set('waad.enco.' + S.cid, f.en_co.trim());
      const p = { p_emp: e.id, p_kind: kind, p_lang: f.lang, p_to: blank((f.to || '').trim()), p_salary: kind === 'salary' ? f.sal === 'true' : true, p_nat: blank(f.nat), p_request: req ? req.id : null,
        p_en: en ? { name: f.en_name || '', job: f.en_job || '', company: f.en_co || '' } : null };
      Object.keys(p).forEach(k => p[k] == null && delete p[k]);
      const l = await db.rpc('issue_letter', p); toast('صدر الخطاب ' + l.ref_no); location.hash = '#/letter/' + l.id; } });
  const sync = () => $$('.en-only', m).forEach(x => x.hidden = $('select[name=lang]', m).value !== 'en'); $('select[name=lang]', m).onchange = sync; sync();
}
async function myLettersHtml() {
  if (!S.emp) return '';
  const ls = await lettersOf(S.emp); if (!ls.length) return '';
  return `<div class="card" id="mylt"><h2>خطاباتي</h2>${tbl(LTR_COLS, ls, { onRow: true })}</div>`;
}
function fitA4() { const w = document.querySelector('#page .a4wrap'), s = w && w.querySelector('.a4'); if (!s) return; s.style.zoom = ''; s.style.zoom = Math.min(1, (w.clientWidth - 2) / s.offsetWidth); }
window.addEventListener('resize', fitA4);
VIEWS['#/letter'] = async (page, id) => {
  const [l] = id ? await db.get('letters', { id: 'eq.' + id }) : [];
  if (!l) throw new Error('الخطاب غير موجود');
  const back = isHR() ? '#/docs/' + l.employee_id : '#/profile';
  const draw = () => {
    const head = LS.get('waad.ltr.head') !== false;
    page.innerHTML = `<div class="head"><div><a href="${back}" class="small">← رجوع</a><h1>${esc(LTR_KIND[l.kind])} <span class="num muted">${esc(l.ref_no)}</span></h1>
        <div class="muted">${esc(((l.data || {}).employee || {}).full_name || '')} · صدر في ${fdate((l.data || {}).date)}</div></div>
      <div class="row"><label class="row small" style="gap:6px"><input type="checkbox" id="lhd" ${head ? '' : 'checked'}> على ورق المنشأة الرسمي (بدون ترويسة)</label><button class="btn pri" id="lpr">طباعة A4</button></div></div>
      ${!(S.company || {}).logo && has('owner', 'admin') ? '<div class="note" style="margin-bottom:12px">لا يوجد شعار للمنشأة. <a href="#/settings">أضف الشعار من الإعدادات</a> ليظهر أعلى الخطاب.</div>' : ''}
      <div class="a4wrap">${letterHtml(l, { head })}</div>
      <p class="muted small">مقاس الورقة A4 210 × 297 ملم. في نافذة الطباعة اختر الحجم A4 والمقياس 100%.</p>`;
    fitA4();
    $('#lhd', page).onchange = ev => { LS.set('waad.ltr.head', !ev.target.checked); draw(); };
    $('#lpr', page).onclick = () => printSheet($('.a4', page));
  };
  draw();
};

/* ===== bulk import of documents and contracts from Excel (.xlsx) or CSV ===== */
const DOC_IMPORT_COLS = [
  ['emp_no', 'الرقم الوظيفي', 'employee number|emp no|emp_no|رقم الموظف', true],
  ['emp_name', 'اسم الموظف (للمراجعة فقط)', 'employee name|name|الاسم|اسم الموظف'],
  ['doc_type', 'نوع المستند', 'document type|doc type|doc_type|type|النوع|المستند', true],
  ['title', 'اسم المستند (للمستند الآخر)', 'document name|title|اسم المستند'],
  ['title_en', 'اسم المستند بالإنجليزية', 'document name english|title_en|title en'],
  ['doc_no', 'رقم المستند', 'document number|doc no|doc_no|number|الرقم|رقم الهوية|رقم الاقامة|رقم الجواز'],
  ['issue_date', 'تاريخ الإصدار (YYYY-MM-DD)', 'issue date|issue_date|issued|تاريخ الاصدار'],
  ['expiry_date', 'تاريخ الانتهاء (YYYY-MM-DD)', 'expiry date|expiry_date|expiry|expires|تاريخ الانتهاء|الانتهاء'],
  ['notes', 'ملاحظات', 'notes|note|ملاحظة']];
const CON_IMPORT_COLS = [
  ['emp_no', 'الرقم الوظيفي', 'employee number|emp no|emp_no|رقم الموظف', true],
  ['emp_name', 'اسم الموظف (للمراجعة فقط)', 'employee name|name|الاسم|اسم الموظف'],
  ['contract_type', 'نوع العقد (محدد المدة/غير محدد المدة)', 'contract type|contract_type|type|النوع|نوع العقد', true],
  ['start_date', 'بداية العقد (YYYY-MM-DD)', 'start date|start_date|from|البداية|تاريخ البداية|بداية العقد', true],
  ['end_date', 'نهاية العقد (YYYY-MM-DD)', 'end date|end_date|to|النهاية|تاريخ النهاية|نهاية العقد'],
  ['first_start', 'بداية أول عقد', 'first start|first_start|بداية اول عقد'],
  ['renewal_no', 'عدد مرات التجديد', 'renewals|renewal_no|renewal count|عدد التجديدات'],
  ['monthly_paid', 'الأجر (شهري/غير شهري)', 'pay|monthly|monthly_paid|الاجر'],
  ['renewal_clause', 'شرط تجديد تلقائي (نعم/لا)', 'auto renewal|renewal clause|renewal_clause|تجديد تلقائي'],
  ['notes', 'ملاحظات', 'notes|note|ملاحظة']];
const DOC_TYPE_IN = { iqama: 'iqama|اقامة|الاقامة|هوية مقيم|residence|residence permit|resident id', national_id: 'national_id|national id|هوية|الهوية|الهوية الوطنية|هوية وطنية|id',
  passport: 'passport|جواز|جواز السفر|جواز سفر', work_permit: 'work_permit|work permit|رخصة العمل|رخصة عمل', health: 'health|health certificate|الشهادة الصحية|شهادة صحية',
  driving: 'driving|driving license|driving licence|رخصة القيادة|رخصة قيادة', other: 'other|اخرى|مستند اخر|مستند آخر|آخر|اخر' };
const docTypeOf = v => { const n = normHead(v); if (!n) return ''; for (const [k, a] of Object.entries(DOC_TYPE_IN)) if (a.split('|').some(x => normHead(x) === n) || normHead(DOC_T[k]) === n || normHead(trTo(DOC_T[k])) === n) return k; return '?'; };
const yesNo = v => { const n = normHead(v); return !n ? '' : /^(نعم|yes|y|true|1|شهري|monthly|محدد المدة|محدد|fixed|fixed-term|fixed term|limited)$/.test(n) ? 'true' : /^(لا|no|n|false|0|غير شهري|not monthly|non-monthly|non monthly|غير محدد المدة|غير محدد|indefinite|indefinite-term|open-ended|open ended|unlimited)$/.test(n) ? 'false' : '?'; };
// Hijri (Umm al-Qura) dates are common on iqamas: 1446-11-03 becomes the Gregorian date
function hijriToG(y, m, d) {
  const f = new Intl.DateTimeFormat('en-u-ca-islamic-umalqura-nu-latn', { year: 'numeric', month: 'numeric', day: 'numeric', timeZone: 'UTC' });
  const parts = t => { const p = {}; f.formatToParts(new Date(t)).forEach(x => p[x.type] = parseInt(x.value, 10)); return p; };
  let t = Date.UTC(622, 6, 16) + Math.round(((y - 1) * 354.36707 + (m - 1) * 29.530589 + (d - 1)) * 864e5);
  for (let i = 0; i < 6; i++) { const p = parts(t), diff = (y - p.year) * 354.36707 + (m - p.month) * 29.530589 + (d - p.day); if (Math.abs(diff) < 0.5) break; t += Math.round(diff) * 864e5; }
  for (let k = -3; k <= 3; k++) { const p = parts(t + k * 864e5); if (p.year === y && p.month === m && p.day === d) return new Date(t + k * 864e5).toISOString().slice(0, 10); }
  return '';
}
function impDate(v) {
  const s = cellDate(v); if (!s) return { v: '' };
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})$/); if (!m) return { v: s, bad: 1 };
  if (+m[1] >= 1300 && +m[1] <= 1500) { const g = hijriToG(+m[1], +m[2], +m[3]); return g ? { v: g, hijri: s } : { v: s, bad: 1 }; }
  return isNaN(new Date(s)) ? { v: s, bad: 1 } : { v: s };
}
function mapHeadersBy(cols, hdr) {
  const idx = {};
  hdr.forEach((h, i) => { const n = normHead(h); if (!n) return;
    for (const [k, ar, alt] of cols) if (!(k in idx) && [ar, trTo(ar), ...alt.split('|')].some(a => normHead(a) === n)) { idx[k] = i; break; } });
  return idx;
}
async function readSheetFile(file) {
  const buf = await file.arrayBuffer();
  const rows = /\.csv$/i.test(file.name) ? readCsv(new TextDecoder().decode(buf)) : await readXlsx(buf);
  const hi = rows.findIndex(r => r && r.some(v => String(v || '').trim())); if (hi < 0) throw new Error('الملف فارغ');
  return { hdr: rows[hi], body: rows.slice(hi + 1).map((r, i) => ({ r, no: hi + i + 2 })).filter(x => x.r && x.r.some(v => String(v == null ? '' : v).trim())) };
}
function bulkImport({ title, intro, cols, fileName, tplRows, parse, post, dupKey, dupMsg, rpc, cells, done, send, goLabel = 'استيراد' }) {
  const d = modal(title, `<ol class="small" style="padding-inline-start:18px;margin-top:0">${intro.map(t => `<li>${t}</li>`).join('')}</ol>
    <div class="row"><button type="button" class="btn" id="tpl">تنزيل القالب بأسماء الموظفين</button><label class="btn pri" style="margin:0;color:var(--prim-ink)">اختيار الملف<input type="file" id="imf" accept=".xlsx,.csv,text/csv" hidden></label></div>
    <div id="imp"></div>`, { wide: true });
  $('#tpl', d).onclick = async () => { const a = document.createElement('a');
    a.href = URL.createObjectURL(templateXlsx([cols.map(c => tr(c[1]) + (c[3] ? ' *' : '')), ...(await tplRows()).map(r => r.map(v => String(v == null ? '' : v)))]));
    a.download = fileName; a.click(); };
  $('#imf', d).onchange = async ev => {
    const file = ev.target.files[0]; if (!file) return; const box = $('#imp', d);
    try {
      const { hdr, body } = await readSheetFile(file), idx = mapHeadersBy(cols, hdr);
      const miss = cols.filter(c => c[3] && !(c[0] in idx)).map(c => c[1]);
      if (miss.length) throw new Error('أعمدة مطلوبة غير موجودة: ' + miss.join('، ') + ' — استخدم القالب');
      if (!body.length) throw new Error('لا توجد صفوف تحت العناوين');
      if (body.length > 3000) throw new Error('الحد الأقصى 3000 سطر في الملف الواحد');
      const byNo = {}; Object.values(await employeesMap(true)).forEach(e => byNo[e.emp_no] = e);
      const items = body.map(({ r, no }) => { const g = k => idx[k] == null ? '' : arDigits(String(r[idx[k]] == null ? '' : r[idx[k]]).trim()); const x = parse(g, r, idx); x.r._row = no;
        x.e = byNo[x.r.emp_no]; if (!x.r.emp_no) x.errs.unshift('الرقم الوظيفي مطلوب'); else if (!x.e) x.errs.unshift('الرقم الوظيفي غير موجود'); else if (post) post(x); return x; });
      const seen = {}; items.forEach(x => { const k = x.e && dupKey(x); if (!k) return; if (seen[k]) x.errs.push(dupMsg); seen[k] = 1; });
      const bad = items.filter(x => x.errs.length), out = bad.length ? items : send ? send(items) : items;
      const shown = (bad.length ? bad.concat(items.filter(x => !x.errs.length)) : out.concat(items.filter(x => !out.includes(x)))).slice(0, 300);
      box.innerHTML = `<div class="${bad.length ? 'err' : out.length ? 'note' : 'note'}">${items.length} سطر في الملف${bad.length ? ` — ${bad.length} سطر فيه أخطاء، صحّحها في الملف ثم ارفعه مجددا` : out.length ? (send ? ` — ${out.length} ${tr('موظف تتغير بياناتهم')}` : ' — جاهز للاستيراد') : ' — ' + tr('لا توجد تغييرات عن البيانات الحالية')}</div>
        ${tbl([{ t: 'السطر', h: x => x.r._row }, { t: 'الموظف', h: x => x.e ? esc(x.e.full_name) + ` <span class="muted num">${esc(x.r.emp_no)}</span>` : `<span class="num">${esc(x.r.emp_no)}</span>` }, ...cells,
          { t: 'الملاحظات', h: x => x.errs.length ? `<span class="bad">${esc(x.errs.join('، '))}</span>` : `<span class="ok">✓</span>${x.warn ? ' <span class="small muted">' + esc(x.warn) + '</span>' : ''}` }], shown)}
        ${bad.length || !out.length ? '' : `<div class="row" style="margin-top:12px"><button type="button" class="btn pri" id="go">${esc(tr(goLabel))} ${out.length} ${esc(tr('سطر'))}</button></div><div id="ier"></div>`}`;
      if ($('#go', d)) $('#go', d).onclick = async () => { try { await busy($('#go', d), async () => { const res = await db.rpc(rpc, { p_company: S.cid, p_rows: out.map(x => x.r) }); d.close(); toast(done(res)); route(); }); } catch (er) { showErr($('#ier', d), er); } };
    } catch (er) { showErr(box, er); }
    ev.target.value = '';
  };
}
const activeEmps = async () => Object.values(await employeesMap(true)).filter(e => !e.end_date || e.end_date >= today()).sort((a, b) => String(a.emp_no).localeCompare(String(b.emp_no), undefined, { numeric: true }));
function importDocsDialog() {
  bulkImport({ title: 'استيراد المستندات من Excel', cols: DOC_IMPORT_COLS, fileName: 'waad-documents.xlsx', rpc: 'import_documents',
    intro: ['نزّل القالب: فيه سطر لكل موظف بنوع مستنده الأساسي (الهوية الوطنية للسعودي، والإقامة لغيره). أضف سطرا لكل مستند آخر للموظف نفسه.',
      'أنواع المستندات: الإقامة، الهوية الوطنية، جواز السفر، رخصة العمل، الشهادة الصحية، رخصة القيادة، مستند آخر (مع اسمه).',
      'التواريخ بالميلادي أو الهجري (مثل 1447-03-15) وتُحوَّل تلقائيا. إذا كان للموظف مستند من النوع نفسه يُحدَّث بدل تكراره، والخلايا الفارغة لا تمسح المحفوظ.',
      'ارفع الملف وراجع المعاينة. إذا كان في أي سطر خطأ لا يُستورد شيء.'],
    tplRows: async () => (await activeEmps()).flatMap(e => e.is_saudi ? [[e.emp_no, e.full_name, DOC_T.national_id, '', '', e.national_id || '', '', '', '']]
      : [[e.emp_no, e.full_name, DOC_T.iqama, '', '', e.national_id || '', '', '', ''], [e.emp_no, e.full_name, DOC_T.work_permit, '', '', '', '', '', '']]),
    parse: (g, raw, idx) => { const errs = [], t = docTypeOf(g('doc_type')), iss = impDate(raw[idx.issue_date]), exp = impDate(raw[idx.expiry_date]);
      const r = { emp_no: g('emp_no').replace(/[,\s]/g, '').replace(/\.0+$/, ''), doc_type: t, title: g('title'), title_en: g('title_en'), doc_no: g('doc_no').replace(/\.0+$/, ''), issue_date: iss.v, expiry_date: exp.v, notes: g('notes') };
      if (!t) errs.push('نوع المستند مطلوب'); else if (t === '?') errs.push('نوع المستند غير معروف');
      if (t === 'other' && r.title.length < 2) errs.push('اكتب اسم المستند الآخر');
      if (iss.bad) errs.push('تاريخ الإصدار غير صحيح'); if (exp.bad) errs.push('تاريخ الانتهاء غير صحيح');
      if (!iss.bad && !exp.bad && r.issue_date && r.expiry_date && r.expiry_date < r.issue_date) errs.push('تاريخ الانتهاء قبل الإصدار');
      if (!r.doc_no && !r.expiry_date) errs.push('أدخل رقم المستند أو تاريخ انتهائه');
      const warn = [iss.hijri && tr('الإصدار هجري') + ' ' + iss.hijri, exp.hijri && tr('الانتهاء هجري') + ' ' + exp.hijri].filter(Boolean).join(' · ');
      return { r, errs, warn }; },
    dupKey: x => x.r.doc_type && x.r.emp_no + '|' + x.r.doc_type + '|' + (x.r.doc_type === 'other' ? x.r.title.toLowerCase() : ''), dupMsg: 'المستند مكرر في الملف لنفس الموظف',
    cells: [{ t: 'المستند', h: x => esc(x.r.doc_type && x.r.doc_type !== '?' ? (x.r.doc_type === 'other' ? x.r.title : DOC_T[x.r.doc_type]) : '—') }, { t: 'الرقم', h: x => `<span class="num">${esc(x.r.doc_no || '—')}</span>` }, { t: 'تاريخ الانتهاء', h: x => esc(x.r.expiry_date || '—') }],
    done: res => tr('مستندات جديدة') + ': ' + res.added + ' — ' + tr('محدَّثة') + ': ' + res.updated });
}
function importContractsDialog() {
  bulkImport({ title: 'استيراد العقود من Excel', cols: CON_IMPORT_COLS, fileName: 'waad-contracts.xlsx', rpc: 'import_contracts',
    intro: ['نزّل القالب: فيه سطر لكل موظف على رأس العمل. اكتب بيانات العقد الساري فقط.',
      'نوع العقد: محدد المدة أو غير محدد المدة. عقد غير السعودي محدد المدة، وإذا لم تُكتب نهايته فمدته سنة (م37). العقد غير محدد المدة بلا تاريخ نهاية.',
      'إن كان العقد مجددا من قبل فاكتب «بداية أول عقد» و«عدد مرات التجديد» حتى تصل تنبيهات المادة 55 صحيحة.',
      'العقد المستورد يحل محل العقد الساري. إذا بدأ في اليوم التالي لنهاية العقد الحالي يُسجَّل تجديدا له، وإذا كان مطابقا له لا يتغير شيء.'],
    tplRows: async () => (await activeEmps()).map(e => [e.emp_no, e.full_name, e.is_saudi ? '' : CT_T.fixed, e.hire_date, '', '', '', 'شهري', 'لا', '']),
    parse: (g, raw, idx) => { const errs = [], st = impDate(raw[idx.start_date]), en = impDate(raw[idx.end_date]), fs = impDate(raw[idx.first_start]);
      const ty = yesNo(g('contract_type')), mp = yesNo(g('monthly_paid')), cl = yesNo(g('renewal_clause'));
      const r = { emp_no: g('emp_no').replace(/[,\s]/g, '').replace(/\.0+$/, ''), contract_type: ty === 'true' ? 'fixed' : ty === 'false' ? 'indefinite' : '', start_date: st.v, end_date: en.v, first_start: fs.v,
        renewal_no: g('renewal_no').replace(/\.0+$/, ''), monthly_paid: mp === '?' ? '' : mp, renewal_clause: cl === '?' ? '' : cl, notes: g('notes') };
      if (!r.contract_type) errs.push(ty === '?' ? 'نوع العقد: محدد المدة أو غير محدد المدة' : 'نوع العقد مطلوب');
      if (!r.start_date) errs.push('تاريخ بداية العقد مطلوب');
      [st, en, fs].forEach(x => { if (x.bad) errs.push('تاريخ غير صحيح: ' + x.v); });
      if (r.contract_type === 'indefinite' && r.end_date) errs.push('العقد غير محدد المدة ليس له تاريخ نهاية');
      if (r.end_date && r.start_date && r.end_date < r.start_date) errs.push('تاريخ نهاية العقد قبل بدايته');
      if (r.first_start && r.start_date && r.first_start > r.start_date) errs.push('بداية أول عقد بعد بداية هذا العقد');
      if (r.renewal_no && !/^\d{1,2}$/.test(r.renewal_no)) errs.push('عدد مرات التجديد رقم من 0 إلى 99');
      if (mp === '?') errs.push('الأجر: شهري أو غير شهري'); if (cl === '?') errs.push('شرط التجديد: نعم أو لا');
      return { r, errs, warn: [st, en, fs].filter(x => x.hijri).map(x => tr('هجري') + ' ' + x.hijri).join(' · ') }; },
    post: x => { if (!x.e.is_saudi && x.r.contract_type === 'indefinite') x.errs.push('عقد غير السعودي يكون محدد المدة — م37');
      if (x.e.is_saudi && x.r.contract_type === 'fixed' && !x.r.end_date) x.errs.push('أدخل تاريخ نهاية العقد المحدد المدة');
      if (!x.e.is_saudi && x.r.contract_type === 'fixed' && !x.r.end_date && x.r.start_date) x.warn = (x.warn ? x.warn + ' · ' : '') + tr('مدته سنة (م37)'); },
    dupKey: x => x.r.emp_no, dupMsg: 'للموظف أكثر من عقد في الملف',
    cells: [{ t: 'النوع', h: x => esc(CT_T[x.r.contract_type] || '—') }, { t: 'من', h: x => esc(x.r.start_date || '—') }, { t: 'إلى', h: x => esc(x.r.end_date || '—') }],
    done: res => tr('عقود جديدة') + ': ' + res.added + ' — ' + tr('تجديدات') + ': ' + res.renewed + (res.same ? ' — ' + tr('بلا تغيير') + ': ' + res.same : '') });
}

/* ===== bulk update of employee data from Excel: only the cells that differ are changed; "-" clears a cell ===== */
const UPD_COLS = [['emp_no', true], ['full_name'], ['full_name_en'], ['national_id'], ['is_saudi'], ['gender'], ['job_title'], ['job_title_en'], ['department'], ['manager_emp_no']]
  .map(([k, req]) => { const c = IMPORT_COLS.find(x => x[0] === k); return [k, c[1], c[2], !!req]; })
  .concat([['manager_name', 'اسم المدير (للمراجعة فقط)', 'manager name|اسم المدير'], ...['phone', 'email', 'iban', 'nationality'].map(k => { const c = IMPORT_COLS.find(x => x[0] === k); return [k, c[1], c[2]]; }), ...PROFILE_COLS.map(c => [c[0], c[1], c[2]])]);
const PROFILE_KEYS = ['nationality', ...PROFILE_COLS.map(c => c[0])];
const UPD_LABEL = { full_name: 'الاسم الكامل', full_name_en: 'الاسم بالإنجليزية', national_id: 'رقم الهوية/الإقامة', is_saudi: 'الجنسية', gender: 'الجنس', job_title: 'المسمى الوظيفي', job_title_en: 'المسمى الوظيفي بالإنجليزية', department: 'القسم', manager_emp_no: 'المدير المباشر', phone: 'الجوال', email: 'البريد', iban: 'الآيبان', nationality: 'بلد الجنسية' };
PROFILE_COLS.forEach(c => { UPD_LABEL[c[0]] = c[1]; });
async function updateEmployeesDialog() {
  const em = await employeesMap(true), deps = cache.deps || (cache.deps = await db.get('departments', { company_id: 'eq.' + S.cid, order: 'name' }));
  const dn = {}; deps.forEach(d => dn[d.id] = d.name);
  const [ccs, sites] = await Promise.all([db.get('cost_centers', { company_id: 'eq.' + S.cid }).catch(() => []), db.get('work_sites', { company_id: 'eq.' + S.cid }).catch(() => [])]);
  const ccm = {}, wsm = {}; ccs.forEach(c => ccm[c.id] = c.code); sites.forEach(w => wsm[w.id] = w.name);
  const ccOk = v => ccs.some(c => [c.code, c.name, c.name_en].includes(v)), wsOk = v => sites.some(w => [w.name, w.name_en].includes(v));
  const cur = e => ({ nationality: e.nationality || (e.is_saudi ? 'SA' : ''), birth_date: e.birth_date || '', marital_status: e.marital_status || '', dependents: e.dependents == null ? '' : String(e.dependents),
    official_profession: e.official_profession || '', education: e.education || '', specialization: e.specialization || '', emergency_name: e.emergency_name || '', emergency_relation: e.emergency_relation || '',
    emergency_phone: e.emergency_phone || '', short_address: e.short_address || '', national_address: e.national_address || '', cost_center: ccm[e.cost_center_id] || '', work_site: wsm[e.work_site_id] || '',
    leave_open_days: e.leave_open_days == null ? '' : String(+e.leave_open_days), leave_open_date: e.leave_open_date || '', full_name: e.full_name || '', full_name_en: e.full_name_en || '', national_id: e.national_id || '', is_saudi: String(!!e.is_saudi), gender: e.gender || 'm', job_title: e.job_title || '', job_title_en: e.job_title_en || '',
    department: dn[e.department_id] || '', manager_emp_no: e.manager_id && em[e.manager_id] ? em[e.manager_id].emp_no : '', phone: e.phone || '', email: e.email || '', iban: e.iban || '' });
  const show = (k, v) => PROFILE_KEYS.includes(k) ? profileShow(k, v) : k === 'is_saudi' ? (v === 'true' ? 'سعودي' : 'غير سعودي') : k === 'gender' ? (v === 'f' ? 'أنثى' : 'ذكر') : k === 'manager_emp_no' && v ? (Object.values(em).find(x => x.emp_no === v) || {}).full_name || v : v;
  bulkImport({ title: 'تحديث بيانات الموظفين من Excel', cols: UPD_COLS, fileName: 'waad-employees-update.xlsx', rpc: 'update_employees', goLabel: 'تحديث',
    intro: ['نزّل القالب: فيه بيانات كل الموظفين على رأس العمل كما هي الآن. عدّل الخلايا التي تريد تغييرها فقط، ويمكنك حذف الأعمدة التي لا تحتاجها.',
      'الخلية الفارغة لا تغيّر شيئا، ولمسح قيمة اكتب «-». الرقم الوظيفي هو مفتاح الربط ولا يتغير من الملف.',
      'القسم يُكتب باسمه (القسم الجديد يُنشأ تلقائيا)، والمدير المباشر برقمه الوظيفي. لا يُقبل تسلسل دائري.',
      'الرواتب والبدلات لا تُعدَّل من هنا؛ تُعدَّل من صفحة الموظف ← الأجر والبدلات حتى يُحفظ السبب في سجل الرواتب.',
      'ستظهر المعاينة بالتغييرات فقط (القيمة الحالية ← الجديدة) قبل الحفظ. إذا كان في أي سطر خطأ لا يُحدَّث شيء.'],
    tplRows: async () => (await activeEmps()).map(e => { const c = cur(e); return UPD_COLS.map(([k]) => k === 'emp_no' ? e.emp_no : k === 'manager_name' ? (c.manager_emp_no ? show('manager_emp_no', c.manager_emp_no) : '')
      : ['is_saudi', 'gender', ...PROFILE_KEYS].includes(k) ? show(k, c[k]) : c[k]); }),
    parse: (g, raw, idx) => { const v = {}; Object.keys(UPD_LABEL).forEach(k => { if (idx[k] != null) v[k] = g(k); });
      return { r: { emp_no: g('emp_no').replace(/[,\s]/g, '').replace(/\.0+$/, '') }, vals: v, errs: [] }; },
    post: x => { const c = cur(x.e), ch = [];
      for (const [k, raw] of Object.entries(x.vals)) {
        if (raw === '') continue;
        const clear = /^[-–—]$/.test(raw); let nv = clear ? '' : raw;
        if (k === 'national_id' || k === 'manager_emp_no') nv = nv.replace(/[,\s]/g, '').replace(/\.0+$/, '');
        if (k === 'phone') { nv = nv.replace(/[\s-]/g, '').replace(/\.0+$/, ''); if (/^5\d{8}$/.test(nv)) nv = '0' + nv; if (/^9665\d{8}$/.test(nv)) nv = '+' + nv; }
        if (k === 'iban') nv = nv.replace(/\s/g, '').toUpperCase();
        if (k === 'is_saudi') { if (clear) { x.errs.push(tr('الجنسية') + ': ' + tr('لا تُمسح')); continue; } const n = normHead(nv);
          nv = /^(سعودي|سعوديه|سعودية|saudi|ksa|نعم|yes|true|1)$/.test(n) ? 'true' : /^(غير سعودي|غير سعوديه|غير سعودية|non-saudi|non saudi|expat|لا|no|false|0)$/.test(n) ? 'false' : '?'; if (nv === '?') { x.errs.push('الجنسية: سعودي أو غير سعودي'); continue; } }
        if (k === 'gender') { if (clear) { x.errs.push(tr('الجنس') + ': ' + tr('لا تُمسح')); continue; } const n = normHead(nv);
          nv = /^(ذكر|m|male)$/.test(n) ? 'm' : /^(انثى|انثي|f|female|امراة)$/.test(n) ? 'f' : '?'; if (nv === '?') { x.errs.push('الجنس: ذكر أو أنثى'); continue; } }
        if (k === 'full_name' && (clear || nv.length < 3)) { x.errs.push('الاسم الكامل لا يُمسح'); continue; }
        if (PROFILE_KEYS.includes(k) && !clear) { const [pv, er] = profileCell(k, nv); if (er) { x.errs.push(er); continue; } nv = pv; }
        if (k === 'cost_center' && nv && !ccOk(nv)) { x.errs.push(tr('مركز التكلفة غير موجود') + ': ' + nv); continue; }
        if (k === 'work_site' && nv && !wsOk(nv)) { x.errs.push(tr('موقع العمل غير موجود') + ': ' + nv); continue; }
        if (nv === c[k]) continue;
        if (k === 'national_id' && nv && !/^[12]\d{9}$/.test(nv)) x.errs.push('رقم الهوية/الإقامة 10 أرقام يبدأ بـ 1 أو 2');
        if (k === 'iban' && nv && !/^SA\d{22}$/.test(nv)) x.errs.push('الآيبان يبدأ بـ SA ويليه 22 رقما');
        if (k === 'phone' && nv && !/^(05\d{8}|\+9665\d{8})$/.test(nv)) x.errs.push('رقم الجوال بصيغة 05XXXXXXXX');
        if (k === 'email' && nv && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(nv)) x.errs.push('البريد الإلكتروني غير صحيح');
        if (k === 'manager_emp_no' && nv) { if (nv === x.e.emp_no) x.errs.push('لا يكون الموظف مديرا لنفسه'); else if (!Object.values(em).some(y => y.emp_no === nv)) x.errs.push('المدير المباشر غير موجود'); }
        x.r[k] = nv === '' ? null : nv; ch.push([k, c[k], nv]);
      }
      x.changes = ch; },
    send: items => items.filter(x => x.changes && x.changes.length),
    dupKey: x => x.r.emp_no, dupMsg: 'الرقم الوظيفي مكرر في الملف',
    cells: [{ t: 'التغييرات', h: x => (x.changes || []).map(([k, a, b]) => `<div class="small"><span class="muted">${esc(UPD_LABEL[k])}:</span> <s class="muted">${esc(show(k, a) || '—')}</s> ← <b>${esc(show(k, b) || '—')}</b></div>`).join('') || `<span class="muted small">${esc('بلا تغيير')}</span>` }],
    done: n => tr('حُدّثت بيانات') + ' ' + n + ' ' + tr('موظف') });
}


/* ===== custody (العهد) and clearance (إخلاء الطرف) ===== */
const CUST_ST = { held: ['لدى الموظف', 'info'], returned: ['مُستلمة', 'ok'], lost: ['مفقودة / تالفة', 'bad'] };
const CLR_T = { custody: 'العهد', advance: 'السلف', manager: 'المدير المباشر — تسليم المهام', it: 'تقنية المعلومات — الحسابات والأجهزة', finance: 'المالية — الذمم والمطالبات', hr: 'الموارد البشرية' };
async function custodyCard(box, e) {
  const items = await db.get('custody_items', { employee_id: 'eq.' + e.id, order: 'issued_on.desc' });
  const held = items.filter(x => x.status === 'held');
  box.innerHTML = `<div class="card"><div class="row" style="justify-content:space-between"><h2>${esc(tr('العهد'))}</h2>${isHR() ? `<button class="btn sm pri" id="cunew">${esc(tr('+ عهدة'))}</button>` : ''}</div>
    ${tbl([{ t: 'العهدة', h: x => esc((LANG === 'en' && x.name_en) || x.name) + (x.serial ? ` <span class="num muted small">${esc(x.serial)}</span>` : '') }, { t: 'القيمة', r: 1, h: x => x.value == null ? '—' : money(x.value) },
      { t: 'التسليم', h: x => fdate(x.issued_on) }, { t: 'الحالة', h: x => `<span class="badge ${CUST_ST[x.status][1]}">${esc(tr(CUST_ST[x.status][0]))}</span>` + (x.returned_on ? ` <span class="small muted">${fdate(x.returned_on)}</span>` : '') },
      { t: '', h: x => isHR() && x.status === 'held' ? `<button class="btn sm" data-cret="${x.id}">${esc(tr('استلام'))}</button>` : '' }], items, { empty: 'لا توجد عهد مسجلة', onRow: isHR() })}
    ${held.length ? `<p class="small muted">${esc(tr('لدى الموظف'))} <b class="num">${held.length}</b> ${esc(tr('عهدة بقيمة'))} <b class="num">${money(held.reduce((a, x) => a + n0(x.value), 0))}</b></p>` : ''}</div>`;
  if (!isHR()) return;
  const form = x => { const v = x || { issued_on: today() };
    modal(x ? tr('تعديل عهدة') : tr('تسليم عهدة'), `<div class="fg">${field('العهدة', inp('name', v.name, 'required placeholder="' + esc(tr('حاسب محمول، جوال، سيارة، مفاتيح…')) + '"'))}${enF('name_en', v.name_en)}${field('الرقم التسلسلي / اللوحة', inp('serial', v.serial, 'dir="ltr"'))}
      ${field('القيمة التقديرية', inp('value', v.value, 'type="number" step="0.01" min="0"'))}${field('تاريخ التسليم', `<input type="date" name="iss" value="${esc(v.issued_on)}">`)}${field('ملاحظات', inp('note', v.note), 'wide')}</div>`,
      { onOk: async f => { await db.rpc('custody_save', { p_id: x ? x.id : null, p_emp: e.id, p_name: f.name, p_name_en: blank(f.name_en), p_serial: blank(f.serial), p_value: f.value === '' ? null : +f.value, p_issued: f.iss, p_note: blank(f.note) }); toast('تم الحفظ'); route(); } }); };
  $('#cunew', box).onclick = () => form(null);
  bindRows(box, items, x => form(x));
  $$('[data-cret]', box).forEach(b => b.onclick = ev => { ev.stopPropagation(); const x = items.find(i => i.id === b.dataset.cret);
    modal(tr('استلام العهدة') + ' — ' + x.name, `<div class="fg">${field('تاريخ الاستلام', `<input type="date" name="on" value="${today()}">`)}${field('الحالة', `<select name="st">${opt('ok', tr('سليمة'))}${opt('lost', tr('مفقودة أو تالفة'))}</select>`)}${field('ملاحظات', inp('note', ''), 'wide')}</div>
      <p class="muted small">${esc(tr('الحسم مقابل الفقد أو التلف يكون بخطأ العامل وبعد التحقيق، ولا يتجاوز أجر 5 أيام في الشهر (م91).'))}</p>`,
      { onOk: async f => { await db.rpc('custody_return', { p_id: x.id, p_on: f.on, p_lost: f.st === 'lost', p_note: blank(f.note) }); toast('تم الحفظ'); route(); } }); });
}
async function clearanceCard(box, e, opts = {}) {
  const rows = await db.rpc('clearance_status', { p_emp: e.id });
  const done = rows.filter(r => r.ok).length;
  box.innerHTML = `<div class="card"><div class="row" style="justify-content:space-between"><h2>${esc(tr('إخلاء الطرف'))}${opts.title ? ' — ' + esc(e.full_name) : ''}</h2><span class="badge ${done === rows.length ? 'ok' : 'wait'}"><span class="num">${done}/${rows.length}</span></span></div>
    ${!e.end_date && !opts.title ? `<p class="muted small" style="margin:4px 0">${esc(tr('يُستكمل عند الاستقالة أو انتهاء الخدمة، قبل صرف المخالصة.'))}</p>` : ''}
    <div class="tw"><table><tbody>${rows.map(r => `<tr><td>${r.ok ? '✓' : '○'} ${esc(tr(CLR_T[r.step]))}</td>
      <td class="small">${r.step === 'custody' ? (r.ok ? esc(tr('لا توجد عهد لدى الموظف')) : esc(tr('عهد لم تُسلَّم')) + ': <span class="num">' + esc(r.detail) + '</span>') : r.step === 'advance' ? (r.ok ? esc(tr('لا توجد سلف متبقية')) : esc(tr('سلفة متبقية تُحسم من المخالصة')) + ': <b class="num">' + money(r.detail) + '</b>') : r.ok ? `<span class="muted">${esc(String(r.done_at).slice(0, 10))}</span>${r.note ? ' — ' + esc(r.note) : ''}` : ''}</td>
      <td>${r.can_mark ? `<button class="btn sm${r.ok ? '' : ' pri'}" data-clr="${r.step}" data-done="${r.ok ? 0 : 1}">${esc(tr(r.ok ? 'إلغاء' : 'تم'))}</button>` : ''}</td></tr>`).join('')}</tbody></table></div></div>`;
  $$('[data-clr]', box).forEach(b => b.onclick = async () => { try { await db.rpc('clearance_mark', { p_emp: e.id, p_step: b.dataset.clr, p_done: b.dataset.done === '1', p_note: null }); clearanceCard(box, e, opts); } catch (er) { toast(er.message); } });
  return rows;
}
VIEWS['#/clearance'] = async page => {
  const em = await employeesMap(true), td = today(), lim = new Date(Date.now() - 90 * 864e5).toISOString().slice(0, 10);
  const list = Object.values(em).filter(e => e.end_date && e.end_date >= lim).sort((a, b) => a.end_date.localeCompare(b.end_date));
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('إخلاء الطرف'))}</h1><div class="muted">${esc(tr('الموظفون المنتهية خدمتهم أو قريبا (آخر 90 يوما)'))}</div></div></div>
    ${list.length ? list.map(e => `<div data-cl="${e.id}"><div class="muted small" style="margin:12px 4px 4px">${esc(tr('آخر يوم عمل'))}: ${fdate(e.end_date)}${e.end_date > td ? '' : ' — ' + esc(tr('انتهت'))}</div><div class="clb"></div></div>`).join('') : `<div class="note">${esc(tr('لا يوجد موظفون يغادرون حاليا.'))}</div>`}`;
  for (const e of list) clearanceCard($(`[data-cl="${e.id}"] .clb`, page), e, { title: true }).catch(() => { $(`[data-cl="${e.id}"]`, page).remove(); });
};
