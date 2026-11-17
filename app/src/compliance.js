'use strict';
/* ===== «الامتثال»: one page that gathers what the company must act on (owner / admin / HR) =====
   Everything comes from data already in Waad: document and contract expiries (doc_alerts), last month's payroll and its
   wage-protection file, GOSI changes from that payroll (gosi_report), Nitaqat estimate, missing employee data, company
   documents and vehicles, medical insurance. No government system is contacted: each card links to the page that fixes it. */
VIEWS['#/compliance'] = async page => {
  if (!isHR()) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للمالك والموارد البشرية.'))}</div>`; return; }
  const td = today(), prev = new Date(td + 'T12:00:00Z'); prev.setUTCDate(1); prev.setUTCMonth(prev.getUTCMonth() - 1);
  const py = prev.getUTCFullYear(), pm = prev.getUTCMonth() + 1;
  const [al, em, runs, ins, coN] = await Promise.all([db.rpc('doc_alerts', { p_company: S.cid, p_within: 30 }).catch(() => []), employeesMap(true),
    db.get('payroll_runs', { company_id: 'eq.' + S.cid, order: 'year.desc,month.desc', limit: 6 }).catch(() => []),
    db.rpc('insurance_alerts', { p_company: S.cid }).catch(() => []), typeof coExpiring === 'function' ? coExpiring().catch(() => 0) : 0]);
  const act = Object.values(em).filter(e => !e.end_date || e.end_date >= td);
  const last = runs.find(r => r.year === py && r.month === pm), lastOk = runs.find(r => r.status !== 'draft');
  const gosi = lastOk ? await db.rpc('gosi_report', { p_run: lastOk.id }).catch(() => []) : [];
  const gosiTodo = gosi.filter(x => x.status || (x.prev_base != null && r2(x.prev_base) !== r2(x.base))).length;
  const docsExp = al.filter(a => a.kind === 'doc' && a.level === 'expired').length, docsSoon = al.filter(a => a.kind === 'doc' && a.level !== 'expired').length;
  const missing = al.filter(a => a.kind === 'missing').length, contracts = al.filter(a => a.kind === 'contract').length, prob = al.filter(a => a.kind === 'probation').length;
  const noIban = act.filter(e => !e.iban).length, noId = act.filter(e => !e.national_id).length;
  // Nitaqat estimate (same rule as «نطاقات والتوطين»)
  const th = (S.company && S.company.nitaqat) || {}, W = act.reduce((a, e) => a + nitW(e), 0), pct = act.length ? W / act.length * 100 : 0, [bt, bc] = nitBand(pct, th);
  // [state ok|warn|bad|info, title, number, sentence, link, button]
  const cards = [
    !last ? ['bad', 'حماية الأجور', '—', `${tr('لم يُجهَّز مسير رواتب')} ${pm}/${py}. ${tr('جهّزه واعتمده ثم نزّل ملف حماية الأجور لرفعه في مدد.')}`, '#/payroll', 'مسير الرواتب']
      : last.status === 'draft' ? ['warn', 'حماية الأجور', '—', `${tr('مسير')} ${pm}/${py} ${tr('مسودة لم يُعتمد بعد. اعتمده ثم نزّل ملف حماية الأجور.')}`, '#/payroll/' + last.id, 'فتح المسير']
      : ['ok', 'حماية الأجور', '✓', `${tr('مسير')} ${pm}/${py} ${tr('معتمد. ملف حماية الأجور جاهز للتنزيل من المسير.')}`, '#/payroll/' + last.id, 'فتح المسير'],
    !lastOk ? ['info', 'التأمينات الاجتماعية', '—', tr('يظهر هنا ما يلزم تحديثه في التأمينات بعد اعتماد أول مسير.'), '#/payroll', 'مسير الرواتب']
      : [gosiTodo ? 'warn' : 'ok', 'التأمينات الاجتماعية', gosiTodo || '✓', gosiTodo ? tr('موظفون جدد أو منتهية خدمتهم أو تغيّر أجرهم الخاضع للاشتراك: حدّثهم في التأمينات (تقرير التأمينات في المسير).') : tr('لا تغييرات تحتاج تحديثا في التأمينات حسب آخر مسير.'), '#/payroll/' + lastOk.id, 'تقرير التأمينات'],
    [docsExp ? 'bad' : docsSoon ? 'warn' : 'ok', 'وثائق الموظفين', docsExp + docsSoon || '✓', docsExp || docsSoon ? `${docsExp} ${tr('منتهية')} · ${docsSoon} ${tr('تنتهي خلال 30 يوما')} (${tr('إقامات، جوازات، رخص عمل…')})` : tr('لا وثائق منتهية أو قريبة الانتهاء.'), '#/docs', 'الوثائق'],
    [missing ? 'bad' : 'ok', 'وثائق وعقود ناقصة', missing || '✓', missing ? tr('موظفون بلا عقد ساري، أو غير سعوديين بلا إقامة أو رخصة عمل مسجلة.') : tr('لكل موظف عقد، وللوافدين إقامة ورخصة عمل.'), '#/docs', 'الوثائق'],
    [contracts || prob ? 'warn' : 'ok', 'العقود وفترات التجربة', contracts + prob || '✓', contracts || prob ? `${contracts} ${tr('عقد محدد المدة ينتهي خلال 30 يوما')} · ${prob} ${tr('فترة تجربة تنتهي')}` : tr('لا عقود أو فترات تجربة تنتهي قريبا.'), '#/docs', 'الوثائق'],
    [noIban || noId ? 'bad' : 'ok', 'بيانات الرواتب الأساسية', noIban + noId || '✓', noIban || noId ? `${noIban} ${tr('بلا آيبان')} · ${noId} ${tr('بلا رقم هوية')} — ${tr('لازمة لملف حماية الأجور')}` : tr('لكل موظف رقم هوية وآيبان.'), '#/employees', 'الموظفون'],
    th.low == null ? ['info', 'نطاقات', '—', tr('أدخل نسب النطاقات من منصة قوى لمعرفة النطاق المتوقع.'), '#/nitaqat', 'نطاقات والتوطين']
      : [bc === 'ok' ? 'ok' : bc === 'info' ? 'warn' : 'bad', 'نطاقات', r2(pct) + '%', `${tr('النطاق المتوقع')}: ${tr(bt)} (${tr('تقدير داخلي، والتصنيف الرسمي في قوى')})`, '#/nitaqat', 'نطاقات والتوطين'],
    [coN ? 'warn' : 'ok', 'مستندات المنشأة والسيارات', coN || '✓', coN ? tr('سجل تجاري أو رخصة أو استمارة أو تأمين ينتهي خلال 30 يوما.') : tr('لا مستندات للمنشأة أو سيارات تنتهي قريبا.'), '#/companydocs', 'المستندات'],
    [ins.length ? 'warn' : 'ok', 'التأمين الطبي', ins.length || '✓', ins.length ? tr('موظفون بلا تأمين طبي أو وثيقة تقترب من نهايتها.') : tr('كل الموظفين مغطّون بالتأمين الطبي.'), '#/insurance', 'التأمين الطبي']];
  const okN = cards.filter(c => c[0] === 'ok').length, scored = cards.filter(c => c[0] !== 'info').length, score = scored ? Math.round(okN / scored * 100) : 100;
  const CL = { ok: ['ok', 'سليم'], warn: ['wait', 'يحتاج متابعة'], bad: ['bad', 'عاجل'], info: ['info', 'معلومة'] };
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الامتثال'))}</h1><div class="muted">${esc(tr('ما يلزم منشأتك نظاما في مكان واحد، من بيانات وعد نفسها. اضغط على أي بطاقة لمعالجتها.'))}</div></div></div>
    <div class="grid" style="margin-bottom:14px"><div class="card kpi"><div class="muted small">${esc(tr('نسبة الامتثال'))}</div><div class="v num ${score >= 80 ? '' : 'bad'}">${score}%</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('عاجل'))}</div><div class="v num ${cards.some(c => c[0] === 'bad') ? 'bad' : ''}">${cards.filter(c => c[0] === 'bad').length}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('يحتاج متابعة'))}</div><div class="v num">${cards.filter(c => c[0] === 'warn').length}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('الموظفون على رأس العمل'))}</div><div class="v num">${act.length}</div></div></div>
    <div class="cmpl">${cards.sort((a, b) => ['bad', 'warn', 'info', 'ok'].indexOf(a[0]) - ['bad', 'warn', 'info', 'ok'].indexOf(b[0])).map(([s, t, n, x, h, bn]) =>
      `<a class="card cmc ${s}" href="${h}"><div class="row" style="justify-content:space-between;gap:8px"><b>${esc(tr(t))}</b><span class="badge ${CL[s][0]}">${esc(tr(CL[s][1]))}</span></div>
        <div class="v num">${esc(String(n))}</div><div class="small">${esc(x)}</div><div class="small cml">${esc(tr(bn))} ←</div></a>`).join('')}</div>
    <p class="muted small">${esc(tr('وعد لا يتصل بمنصات مدد أو التأمينات أو قوى أو مقيم؛ يجهّز لك البيانات والملفات وأنت ترفعها.'))}</p>`;
};
