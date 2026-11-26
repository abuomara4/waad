/* ===== second free batch (0154 HR, 0155 sales / finance) ===== */
const stars = n => n ? `<span class="num">${n}</span>/5` : '—';
const rateSel = (name, v) => `<select name="${name}">${[5, 4, 3, 2, 1].map(n => opt(n, n + ' — ' + tr(['', 'ضعيف', 'مقبول', 'جيد', 'جيد جدا', 'ممتاز'][n]), String(v || 3))).join('')}</select>`;

/* ----- 8. staff directory ----- */
VIEWS['#/directory'] = async (page, arg, q) => {
  const rows = await db.rpc('staff_directory', { p_company: S.cid }), me = rows.find(r => r.mine);
  const draw = f => { const s = (f || '').trim().toLowerCase(), ls = s ? rows.filter(r => [r.name, r.name_en, r.job, r.department, r.ext].some(x => String(x || '').toLowerCase().includes(s))) : rows;
    $('#dirt', page).innerHTML = tbl([{ t: 'الاسم', h: r => `<b data-nt>${esc((LANG === 'en' && r.name_en) || r.name)}</b>${r.mine ? ` <span class="badge info">${esc(tr('أنت'))}</span>` : ''}<div class="small muted">${esc((LANG === 'en' && r.job_en) || r.job || '')}</div>` },
      { t: 'الإدارة', h: r => esc(r.department || '—') + (r.branch ? `<div class="small muted">${esc(r.branch)}</div>` : '') }, { t: 'المدير', h: r => `<span data-nt>${esc(r.manager || '—')}</span>` },
      { t: 'التحويلة', h: r => r.ext ? `<b class="num">${esc(r.ext)}</b>` : '—' },
      { t: 'الجوال', h: r => r.phone ? `<a class="num" dir="ltr" href="tel:${esc(r.phone)}">${esc(r.phone)}</a>` : '<span class="muted">—</span>' },
      { t: 'البريد', h: r => r.email ? `<a dir="ltr" href="mailto:${esc(r.email)}">${esc(r.email)}</a>` : '<span class="muted">—</span>' }], ls, { empty: 'لا نتائج' }); };
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('دليل الموظفين'))}</h1><div class="muted">${esc(tr('الاسم والإدارة والتحويلة لكل زملائك. الجوال والبريد يظهران فقط لمن اختار إظهارهما.'))}</div></div>${me ? `<button class="btn" id="dme">${esc(tr('بياناتي في الدليل'))}</button>` : ''}</div>
    <input id="dirq" placeholder="${esc(tr('ابحث بالاسم أو الإدارة أو التحويلة'))}" style="max-width:360px;margin-bottom:10px" aria-label="${esc(tr('بحث'))}"><div id="dirt"></div>`;
  draw(); $('#dirq', page).oninput = e => draw(e.target.value);
  if ($('#dme', page)) $('#dme', page).onclick = () => modal(tr('بياناتي في الدليل'), `<div class="fg">${field('رقم التحويلة', inp('ext', me.ext || '', 'inputmode="numeric" maxlength="8" dir="ltr"'))}
      <label class="row small wide" style="gap:6px"><input type="checkbox" name="ph" style="width:auto" ${S.myEmp && S.myEmp.dir_phone ? 'checked' : ''}> ${esc(tr('أظهر جوالي لزملائي'))}</label>
      <label class="row small wide" style="gap:6px"><input type="checkbox" name="em" style="width:auto" ${S.myEmp && S.myEmp.dir_email ? 'checked' : ''}> ${esc(tr('أظهر بريدي لزملائي'))}</label></div>`,
    { onOk: async f => { await db.rpc('directory_me_set', { p_company: S.cid, p_ext: f.ext || '', p_phone: !!f.ph, p_email: !!f.em }); if (S.myEmp) Object.assign(S.myEmp, { dir_phone: !!f.ph, dir_email: !!f.em }); toast(tr('تم الحفظ')); route(); } });
};

/* ----- 9. confidential grievances ----- */
const GRV_C = { harassment: 'تحرش أو إساءة', discrimination: 'تمييز', safety: 'السلامة في العمل', conduct: 'سلوك زميل أو مدير', pay: 'الأجر والمستحقات', workload: 'ضغط العمل وساعاته', policy: 'تطبيق السياسات', other: 'أخرى' };
const GRV_S = { open: ['جديد', 'wait'], review: ['قيد المعالجة', 'info'], resolved: ['تمت المعالجة', 'ok'], closed: ['مغلق', ''] };
const grvBadge = s => `<span class="badge ${GRV_S[s][1]}">${esc(tr(GRV_S[s][0]))}</span>`;
const grvThread = g => (g.messages || []).map(m => `<div class="card" style="padding:8px 10px;margin:6px 0;${m.side === 'handler' ? 'border-inline-start:4px solid var(--brand-blue,#217FE1)' : ''}"><div class="small muted">${esc(tr(m.side === 'handler' ? 'رد الجهة المختصة' : 'مقدم البلاغ'))} · ${fdate(String(m.at).slice(0, 10))}</div><div style="white-space:pre-wrap">${esc(m.body)}</div></div>`).join('');
VIEWS['#/grievance'] = async page => {
  if (!S.emp) { page.innerHTML = noEmpNote(); return; }
  const mine = await db.rpc('grievance_mine', { p_company: S.cid });
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('بلاغ سري'))}</h1><div class="muted">${esc(tr('قناة سرية لرفع شكوى أو بلاغ إلى الموارد البشرية أو المالك مباشرة. للتظلم من جزاء استخدم «ملفي» ← الجزاءات.'))}</div></div><button class="btn pri" id="gnew">${esc(tr('بلاغ جديد'))}</button></div>
    ${tbl([{ t: 'الرقم', h: g => `<span class="num">${esc(g.no)}</span>` }, { t: 'الموضوع', h: g => esc(g.subject) + `<div class="small muted">${esc(tr(GRV_C[g.category]))} · ${esc(tr(g.to === 'owner' ? 'إلى المالك' : 'إلى الموارد البشرية'))}${g.anonymous ? ' · ' + esc(tr('بدون اسم')) : ''}</div>` },
      { t: 'التاريخ', h: g => fdate(String(g.created_at).slice(0, 10)) }, { t: 'الحالة', h: g => grvBadge(g.status) }], mine, { empty: 'لا توجد بلاغات', onRow: true })}`;
  $('#gnew', page).onclick = () => modal(tr('بلاغ جديد'), `<div class="fg">${field('نوع البلاغ', `<select name="c">${Object.entries(GRV_C).map(([k, t]) => opt(k, tr(t))).join('')}</select>`)}
      ${field('يصل إلى', `<select name="to">${opt('hr', tr('الموارد البشرية'))}${opt('owner', tr('المالك فقط'))}</select>`)}${field('الموضوع', inp('s', '', 'required maxlength="200"'), 'wide')}
      ${field('التفاصيل', '<textarea name="b" rows="6" maxlength="5000" required></textarea>', 'wide')}
      <label class="row small wide" style="gap:6px"><input type="checkbox" name="an" style="width:auto"> ${esc(tr('أرسله بدون اسمي (لا يظهر اسمي لمن يعالج البلاغ)'))}</label></div>
      <p class="muted small">${esc(tr('يُحفظ البلاغ في النظام بسرية، ولا يراه إلا من اخترته. تابع الرد من هذه الصفحة.'))}</p>`,
    { ok: 'إرسال', onOk: async f => { const no = await db.rpc('grievance_submit', { p_company: S.cid, p_category: f.c, p_subject: f.s, p_body: f.b, p_anonymous: !!f.an, p_to: f.to }); toast(tr('أُرسل البلاغ') + ' ' + no); route(); } });
  bindRows(page, mine, g => { const d = modal(g.no + ' — ' + g.subject, `<p style="white-space:pre-wrap">${esc(g.body)}</p>${grvBadge(g.status)}${g.resolution ? `<div class="note" style="margin-top:8px">${esc(tr('ما تم'))}: ${esc(g.resolution)}</div>` : ''}${grvThread(g)}
      ${g.status !== 'closed' ? field('إضافة تعليق', '<textarea name="r" rows="2"></textarea>') : ''}`, g.status !== 'closed' ? { ok: 'إرسال', onOk: async f => { if (!(f.r || '').trim()) throw new Error(tr('اكتب التعليق')); await db.rpc('grievance_reply', { p_id: g.id, p_body: f.r }); toast(tr('تم')); route(); } } : {}); });
};
VIEWS['#/grievances'] = async page => {
  if (!has('owner', 'admin', 'hr')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const rows = await db.rpc('grievance_inbox', { p_company: S.cid });
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('البلاغات السرية'))}</h1><div class="muted">${esc(tr('بلاغات الموظفين إليك. البلاغ بدون اسم لا يظهر فيه اسم مقدمه. ردودك تصل إليه في صفحته.'))}</div></div></div>
    ${tbl([{ t: 'الرقم', h: g => `<span class="num">${esc(g.no)}</span>` }, { t: 'الموضوع', h: g => esc(g.subject) + `<div class="small muted">${esc(tr(GRV_C[g.category]))}${g.to === 'owner' ? ' · ' + esc(tr('إلى المالك')) : ''}</div>` },
      { t: 'مقدم البلاغ', h: g => g.reporter ? `<span data-nt>${esc(g.reporter.name)}</span> <span class="small muted num">${esc(g.reporter.no)}</span>` : `<span class="muted">${esc(tr('بدون اسم'))}</span>` },
      { t: 'التاريخ', h: g => fdate(String(g.created_at).slice(0, 10)) }, { t: 'الحالة', h: g => grvBadge(g.status) }], rows, { empty: 'لا توجد بلاغات', onRow: true })}`;
  bindRows(page, rows, g => { const d = modal(g.no + ' — ' + g.subject, `<p class="small muted">${esc(tr(GRV_C[g.category]))} · ${g.reporter ? esc(g.reporter.name) : esc(tr('بدون اسم'))}</p><p style="white-space:pre-wrap">${esc(g.body)}</p>${grvThread(g)}
      <div class="fg">${field('ردك على مقدم البلاغ', '<textarea name="r" rows="2"></textarea>', 'wide')}${field('الحالة', `<select name="st">${Object.entries(GRV_S).map(([k, [t]]) => opt(k, tr(t), g.status)).join('')}</select>`)}
      ${field('ما تم بشأن البلاغ', inp('res', g.resolution || ''), 'wide')}</div>`,
    { onOk: async f => { if ((f.r || '').trim()) await db.rpc('grievance_reply', { p_id: g.id, p_body: f.r });
        if (f.st !== g.status || (f.res || '') !== (g.resolution || '')) await db.rpc('grievance_status', { p_id: g.id, p_status: f.st, p_resolution: f.res || '' }); toast(tr('تم الحفظ')); route(); } }); });
};

/* ----- 10. exit interview ----- */
const EXIT_R = { pay: 'الراتب والمزايا', growth: 'فرص التطور والترقية', manager: 'العلاقة مع المدير', workload: 'ضغط العمل وساعاته', relocation: 'الانتقال لمدينة أخرى', study: 'الدراسة', offer: 'عرض عمل أفضل', family: 'ظروف عائلية', health: 'ظروف صحية', culture: 'بيئة العمل', other: 'أخرى' };
const EXIT_Q = { manager: 'المدير المباشر', pay: 'الراتب والمزايا', growth: 'التطور الوظيفي', workload: 'حجم العمل', culture: 'بيئة العمل', training: 'التدريب' };
VIEWS['#/exit'] = async page => {
  if (!S.emp) { page.innerHTML = noEmpNote(); return; }
  const st = await db.rpc('exit_interview_me', { p_company: S.cid });
  if (st.done) { page.innerHTML = `<div class="head"><div><h1>${esc(tr('مقابلة نهاية الخدمة'))}</h1></div></div><div class="note">${esc(tr('شكرا لك، وصلت إجاباتك إلى الموارد البشرية. نتمنى لك التوفيق.'))}</div>`; return; }
  if (!st.due) { page.innerHTML = `<div class="head"><div><h1>${esc(tr('مقابلة نهاية الخدمة'))}</h1></div></div><div class="note">${esc(tr('تظهر هذه الصفحة للموظف عند انتهاء خدمته.'))}</div>`; return; }
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('مقابلة نهاية الخدمة'))}</h1><div class="muted">${esc(tr('رأيك يساعدنا على التحسين. تراه الموارد البشرية فقط، ولا يؤثر على مستحقاتك.'))}</div></div></div>
    <form id="exf" class="card" novalidate><h2>${esc(tr('أسباب المغادرة'))}</h2><div class="row" style="flex-wrap:wrap;gap:10px">${Object.entries(EXIT_R).map(([k, t]) => `<label class="row small" style="gap:4px"><input type="checkbox" name="r_${k}" style="width:auto"> ${esc(tr(t))}</label>`).join('')}</div>
      <h2 style="margin-top:14px">${esc(tr('تقييمك'))}</h2><div class="fg">${Object.entries(EXIT_Q).map(([k, t]) => field(t, rateSel('q_' + k, 3))).join('')}
      ${field('هل تعود للعمل معنا مستقبلا؟', `<select name="wr">${opt('', '—')}${opt('true', tr('نعم'))}${opt('false', tr('لا'))}</select>`)}
      ${field('كم ترشحنا لصديق للعمل (0 إلى 10)؟', inp('rec', '', 'type="number" min="0" max="10"'))}
      ${field('أفضل ما في العمل هنا', '<textarea name="best" rows="2"></textarea>', 'wide')}${field('ما الذي يحتاج إلى تحسين؟', '<textarea name="imp" rows="2"></textarea>', 'wide')}${field('ملاحظات أخرى', '<textarea name="com" rows="2"></textarea>', 'wide')}</div>
      <div id="exerr"></div><button class="btn pri" id="exs" style="margin-top:10px">${esc(tr('إرسال'))}</button></form>`;
  $('#exf', page).onsubmit = async ev => { ev.preventDefault(); const f = formData(ev.target), ratings = {}; Object.keys(EXIT_Q).forEach(k => ratings[k] = +f['q_' + k]);
    try { await busy($('#exs', page), () => db.rpc('exit_interview_submit', { p_company: S.cid, p_a: { reasons: Object.keys(EXIT_R).filter(k => f['r_' + k]), ratings, would_return: f.wr === '' ? null : f.wr === 'true',
      recommend: f.rec === '' ? null : +f.rec, best: f.best || '', improve: f.imp || '', comments: f.com || '' } })); toast(tr('شكرا لك')); route(); } catch (e) { showErr($('#exerr', page), e); } };
};
VIEWS['#/exitresults'] = async (page, arg, q) => {
  if (!has('owner', 'admin', 'hr')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const from = (q && q.get('from')) || addDays(today(), -365), to = (q && q.get('to')) || today();
  const [r, rows, em] = await Promise.all([db.rpc('exit_results', { p_company: S.cid, p_from: from, p_to: to }), db.get('exit_interviews', { company_id: 'eq.' + S.cid, order: 'submitted_at.desc' }), employeesMap(true)]);
  const ls = rows.filter(x => x.submitted_at.slice(0, 10) >= from && x.submitted_at.slice(0, 10) <= to), rs = Object.entries(r.reasons || {}).sort((a, b) => b[1] - a[1]);
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('نتائج مقابلات نهاية الخدمة'))}</h1><div class="muted">${fdate(from)} – ${fdate(to)}</div></div>
      <form id="exr" class="row" style="gap:6px"><input type="date" name="from" value="${from}" aria-label="${esc(tr('من'))}"><input type="date" name="to" value="${to}" aria-label="${esc(tr('إلى'))}"><button class="btn">${esc(tr('عرض'))}</button></form></div>
    <div class="grid" style="margin-bottom:14px"><div class="card kpi"><div class="muted small">${esc(tr('عدد المقابلات'))}</div><div class="v num">${r.n}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('يعودون للعمل معنا'))}</div><div class="v num">${r.would_return == null ? '—' : r.would_return + '%'}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('مؤشر الترشيح (eNPS)'))}</div><div class="v num">${r.enps == null ? '—' : r.enps}</div></div></div>
    <div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(300px,1fr))"><div class="card"><h2>${esc(tr('أسباب المغادرة'))}</h2>${rs.length ? rs.map(([k, n]) => `<div class="row" style="justify-content:space-between"><span>${esc(tr(EXIT_R[k] || k))}</span><b class="num">${n}</b></div>`).join('') : '<p class="muted">—</p>'}</div>
      <div class="card"><h2>${esc(tr('متوسط التقييم'))}</h2>${Object.entries(EXIT_Q).map(([k, t]) => `<div class="row" style="justify-content:space-between"><span>${esc(tr(t))}</span><b>${stars(r.ratings && r.ratings[k])}</b></div>`).join('')}</div></div>
    <div class="card"><h2>${esc(tr('الإجابات'))}</h2>${tbl([{ t: 'الموظف', h: x => `<span data-nt>${esc((em[x.employee_id] || {}).full_name || '—')}</span>` }, { t: 'التاريخ', h: x => fdate(x.submitted_at.slice(0, 10)) },
      { t: 'الأسباب', h: x => esc(x.reasons.map(k => tr(EXIT_R[k] || k)).join('، ')) }, { t: 'يعود', h: x => x.would_return == null ? '—' : esc(tr(x.would_return ? 'نعم' : 'لا')) },
      { t: 'ما يحتاج إلى تحسين', h: x => esc(x.improve || x.comments || '') }], ls, { empty: 'لا توجد مقابلات' })}</div>`;
  $('#exr', page).onsubmit = ev => { ev.preventDefault(); const f = formData(ev.target); location.hash = `#/exitresults?from=${f.from}&to=${f.to}`; };
};

/* ----- 11. interview scorecards ----- */
const SC_C = { technical: 'المعرفة الفنية', experience: 'الخبرة المناسبة', communication: 'التواصل', problem: 'حل المشكلات', culture: 'التوافق مع بيئة العمل', motivation: 'الدافعية' };
const SC_R = { hire: ['يُعيّن', 'ok'], maybe: ['ربما', 'wait'], no: ['لا يُعيّن', 'bad'] };
async function scorecardDialog(c) {
  const all = await db.get('candidate_scores', { candidate_id: 'eq.' + c.id, order: 'created_at' }).catch(() => []), mine = all.find(x => x.by_user === S.session.user.id) || {};
  modal(tr('بطاقة تقييم المقابلة') + ' — ' + c.full_name, `${all.length ? `<div class="tw"><table><thead><tr><th>${esc(tr('المقيّم'))}</th>${Object.values(SC_C).map(t => `<th class="c">${esc(tr(t))}</th>`).join('')}<th class="c">${esc(tr('المتوسط'))}</th><th>${esc(tr('التوصية'))}</th></tr></thead><tbody>
      ${all.map(s => `<tr><td data-nt>${esc(s.by_name || '')}</td>${Object.keys(SC_C).map(k => `<td class="c num">${s.ratings[k] || '—'}</td>`).join('')}<td class="c"><b class="num">${s.score}</b></td><td><span class="badge ${SC_R[s.recommendation][1]}">${esc(tr(SC_R[s.recommendation][0]))}</span>${s.notes ? `<div class="small muted">${esc(s.notes)}</div>` : ''}</td></tr>`).join('')}</tbody></table></div>` : ''}
    <h3 style="margin:12px 0 6px">${esc(tr('تقييمك'))}</h3><div class="fg">${Object.entries(SC_C).map(([k, t]) => field(t, rateSel('s_' + k, (mine.ratings || {})[k]))).join('')}
      ${field('التوصية', `<select name="rec">${Object.entries(SC_R).map(([k, [t]]) => opt(k, tr(t), mine.recommendation || 'maybe')).join('')}</select>`)}${field('ملاحظات', `<textarea name="n" rows="2">${esc(mine.notes || '')}</textarea>`, 'wide')}</div>`,
    { wide: true, ok: 'حفظ التقييم', onOk: async f => { const r = {}; Object.keys(SC_C).forEach(k => r[k] = +f['s_' + k]); await db.rpc('candidate_score_save', { p_candidate: c.id, p_ratings: r, p_rec: f.rec, p_notes: f.n || '' }); toast(tr('تم الحفظ')); } });
}
async function scoreCompare(o, cands) {
  const sc = await db.get('candidate_scores', { company_id: 'eq.' + S.cid, candidate_id: 'in.(' + cands.map(c => c.id).join(',') + ')' }).catch(() => []);
  const rows = cands.map(c => { const s = sc.filter(x => x.candidate_id === c.id), avg = k => s.length && s.some(x => x.ratings[k]) ? r2(s.reduce((a, x) => a + n0(x.ratings[k]), 0) / s.filter(x => x.ratings[k]).length) : null;
    return { c, n: s.length, per: Object.fromEntries(Object.keys(SC_C).map(k => [k, avg(k)])), score: s.length ? r2(s.reduce((a, x) => a + n0(x.score), 0) / s.length) : null, hire: s.filter(x => x.recommendation === 'hire').length }; })
    .sort((a, b) => (b.score || 0) - (a.score || 0));
  modal(tr('مقارنة المرشحين') + ' — ' + o.title, `<div class="tw"><table><thead><tr><th>${esc(tr('المرشح'))}</th>${Object.values(SC_C).map(t => `<th class="c">${esc(tr(t))}</th>`).join('')}<th class="c">${esc(tr('المتوسط'))}</th><th class="c">${esc(tr('يُعيّن'))}</th><th class="c">${esc(tr('المقيّمون'))}</th></tr></thead><tbody>
    ${rows.map((x, i) => `<tr${i === 0 && x.score ? ' style="background:var(--ok-bg,rgba(0,160,80,.08))"' : ''}><td data-nt>${esc(x.c.full_name)}<div class="small muted">${esc(STAGES[x.c.stage] || '')}</div></td>${Object.keys(SC_C).map(k => `<td class="c num">${x.per[k] == null ? '—' : x.per[k]}</td>`).join('')}<td class="c"><b class="num">${x.score == null ? '—' : x.score}</b></td><td class="c num">${x.hire}</td><td class="c num">${x.n}</td></tr>`).join('')}</tbody></table></div>
    <p class="muted small">${esc(tr('مرتبة حسب متوسط التقييم. كل مقيّم يقيّم من «بطاقة التقييم» في ملف المرشح.'))}</p>`, { wide: true });
}

/* ----- 12. job descriptions ----- */
const JD_F = [['purpose', 'الغرض من الوظيفة'], ['duties', 'المهام والمسؤوليات'], ['qualifications', 'المؤهلات'], ['experience', 'الخبرة'], ['skills', 'المهارات والجدارات']];
VIEWS['#/jobdesc'] = async page => {
  const [rows, deps, grades] = await Promise.all([db.get('job_descriptions', { company_id: 'eq.' + S.cid, order: 'title' }), db.get('departments', { company_id: 'eq.' + S.cid, order: 'name' }), db.get('job_grades', { company_id: 'eq.' + S.cid, order: 'code' }).catch(() => [])]);
  const dm = {}; deps.forEach(d => dm[d.id] = d.name); const gm = {}; grades.forEach(g => gm[g.id] = g.code + ' — ' + g.name); const hr = isHR() || hrCan('hr_recruit');
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('مكتبة الوصف الوظيفي'))}</h1><div class="muted">${esc(tr('مهام كل وظيفة ومؤهلاتها، تُربط بالوظائف الشاغرة وتُطبع مع العرض الوظيفي.'))}</div></div>${hr ? `<button class="btn pri" id="jdn">+ ${esc(tr('وصف وظيفي'))}</button>` : ''}</div>
    ${tbl([{ t: 'الوظيفة', h: j => `<b data-nt>${esc((LANG === 'en' && j.title_en) || j.title)}</b>` }, { t: 'الإدارة', h: j => esc(dm[j.department_id] || '—') }, { t: 'الدرجة', h: j => esc(gm[j.grade_id] || '—') },
      { t: '', h: j => `<button class="btn sm" data-jdp="${j.id}">${esc(tr('طباعة'))}</button>` }], rows, { empty: 'لا توجد أوصاف وظيفية بعد', onRow: true })}`;
  const form = j => { const v = j || {}; modal(j ? tr('تعديل الوصف الوظيفي') : tr('وصف وظيفي جديد'), `<div class="fg">${field('المسمى الوظيفي', inp('title', v.title, 'required maxlength="120"'))}${field('المسمى بالإنجليزية', inp('title_en', v.title_en, 'dir="ltr" maxlength="120"'))}
      ${field('الإدارة', `<select name="dep"><option value="">—</option>${deps.map(d => opt(d.id, d.name, v.department_id || '')).join('')}</select>`)}${grades.length ? field('الدرجة', `<select name="gr"><option value="">—</option>${grades.map(g => opt(g.id, gm[g.id], v.grade_id || '')).join('')}</select>`) : ''}
      ${field('يرتبط بـ', inp('rep', v.reports_to, 'maxlength="120"'))}${JD_F.map(([k, t]) => field(t, `<textarea name="${k}" rows="${k === 'duties' ? 5 : 3}">${esc(v[k] || '')}</textarea>`, 'wide')).join('')}</div>`,
    { wide: true, onOk: async f => { if ((f.title || '').trim().length < 2) throw new Error(tr('أدخل المسمى الوظيفي'));
      const row = { title: f.title.trim(), title_en: blank((f.title_en || '').trim()), department_id: blank(f.dep), grade_id: blank(f.gr), reports_to: blank(f.rep), updated_at: new Date().toISOString() }; JD_F.forEach(([k]) => row[k] = blank(f[k]));
      if (j) await db.upd('job_descriptions', { id: 'eq.' + j.id }, row); else await db.ins('job_descriptions', Object.assign(row, { company_id: S.cid })); toast(tr('تم الحفظ')); route(); } }); };
  if ($('#jdn', page)) $('#jdn', page).onclick = () => form(null);
  if (hr) bindRows(page, rows, j => form(j)); else bindRows(page, rows, j => jdPrint(j, dm, gm));
  $$('[data-jdp]', page).forEach(b => b.addEventListener('click', e => { e.stopPropagation(); jdPrint(rows.find(j => j.id === b.dataset.jdp), dm, gm); }));
};
// the printable job description (optionally for a named candidate, with the offer)
async function jdPrint(j, dm, gm, cand) {
  if (!j) return;
  if (!dm) { const [deps, grades] = await Promise.all([db.get('departments', { company_id: 'eq.' + S.cid }), db.get('job_grades', { company_id: 'eq.' + S.cid }).catch(() => [])]); dm = {}; deps.forEach(d => dm[d.id] = d.name); gm = {}; grades.forEach(g => gm[g.id] = g.code + ' — ' + g.name); }
  const n = document.createElement('div'); n.className = 'pdoc';
  n.innerHTML = printHead(tr('الوصف الوظيفي') + ' — ' + j.title) + `${cand ? `<p>${esc(tr('مرفق بالعرض الوظيفي المقدم إلى'))}: <b>${esc(cand.full_name)}</b></p>` : ''}
    <table class="kv"><tbody><tr><td>${esc(tr('المسمى الوظيفي'))}</td><td><b>${esc(j.title)}</b>${j.title_en ? ` — <span dir="ltr">${esc(j.title_en)}</span>` : ''}</td></tr><tr><td>${esc(tr('الإدارة'))}</td><td>${esc(dm[j.department_id] || '—')}</td></tr>
      ${j.grade_id ? `<tr><td>${esc(tr('الدرجة'))}</td><td>${esc(gm[j.grade_id] || '')}</td></tr>` : ''}${j.reports_to ? `<tr><td>${esc(tr('يرتبط بـ'))}</td><td>${esc(j.reports_to)}</td></tr>` : ''}</tbody></table>
    ${JD_F.filter(([k]) => j[k]).map(([k, t]) => `<h3>${esc(tr(t))}</h3><div style="white-space:pre-wrap">${esc(j[k])}</div>`).join('')}
    <div style="margin-top:40px;display:flex;justify-content:space-between"><div>${esc(tr('اطلعت عليه'))}: ____________</div><div>${esc(tr('التوقيع'))}: ____________</div><div>${esc(tr('التاريخ'))}: ____________</div></div>`;
  printWith(n, '@page{size:A4 portrait;margin:14mm}');
}

/* ----- 13. the customer's quotation page: #/q/<token>, no sign-in ----- */
const quoteToken = () => (location.hash.match(/^#\/q\/([0-9a-f]{64})/) || [])[1] || null;
async function quotePublicView(token) {
  document.title = tr('عرض سعر') + ' — ' + tr('وعد');
  $('#app').innerHTML = `<div class="portal"><div class="muted">${esc(tr('جاري التحميل…'))}</div></div>`;
  let o = null; try { o = await db.rpc('quote_view', { p_token: token }); } catch (e) { o = null; }
  const box = $('.portal');
  if (!o) { box.innerHTML = `<div class="card"><h2>${esc(tr('الرابط غير صالح'))}</h2></div>`; return; }
  const st = { open: ['بانتظار ردكم', 'wait'], accepted: ['مقبول', 'ok'], converted: ['مقبول', 'ok'], rejected: ['مرفوض', 'bad'] }[o.status] || [o.status, ''];
  box.innerHTML = `<div class="phead"><div>${o.logo ? `<img src="${esc(o.logo)}" alt="" style="max-height:48px">` : ''}<h1>${esc(o.company)}</h1><div class="small muted">${esc(tr('عرض سعر'))} <span class="num">${esc(o.no)}</span> · ${esc(o.customer)}</div></div><div class="sp"></div><button class="btn sm" id="plg">${LANG === 'en' ? 'العربية' : 'English'}</button></div>
    <div class="card"><p>${esc(tr('التاريخ'))} ${fdate(o.date)} · ${esc(tr('صالح حتى'))} ${fdate(o.valid_until)} <span class="badge ${st[1]}">${esc(tr(st[0]))}</span></p>
      ${tbl([{ t: 'البند', h: x => esc(x.item) }, { t: 'الكمية', r: 1, h: x => `<span class="num">${+x.qty}</span>` }, { t: 'السعر', r: 1, h: x => money(x.price) }, { t: 'الخصم', r: 1, h: x => n0(x.disc) ? `<span class="num">${+x.disc}%</span>` : '—' }, { t: 'المبلغ', r: 1, h: x => money(x.amount) }], o.lines, {})}
      <p class="r">${esc(tr('قبل الضريبة'))} ${money(o.subtotal)} · ${esc(tr('الضريبة'))} ${money(o.vat)} · <b>${esc(tr('الإجمالي'))} ${money(o.total)}</b></p>${o.terms ? `<p class="small"><b>${esc(tr('الشروط'))}:</b> ${esc(o.terms)}</p>` : ''}
      ${o.status === 'open' && !o.expired ? `<form id="qf" class="fg" style="margin-top:12px" novalidate>${field('اسمك وصفتك', inp('n', '', 'required maxlength="120"'))}${field('ملاحظة (إلزامية عند الرفض)', inp('note', '', 'maxlength="500"'))}</form><div id="qerr"></div>
        <div class="row" style="gap:8px;margin-top:10px"><button class="btn pri" id="qy">${esc(tr('أقبل العرض'))}</button><button class="btn danger" id="qn">${esc(tr('أرفض'))}</button></div>`
        : o.status === 'open' ? `<div class="note">${esc(tr('انتهت صلاحية العرض — تواصل مع الشركة'))}</div>` : `<p class="small">${esc(o.decided_by || '')} ${o.decided_at ? fdate(String(o.decided_at).slice(0, 10)) : ''}</p>`}</div>
    <p class="small muted" style="text-align:center">${esc(tr('هذه الصفحة خاصة بكم؛ لا تشاركوا رابطها.'))} · ${esc(tr('نظام وعد'))}</p>`;
  $('#plg').onclick = () => { setLang(LANG === 'en' ? 'ar' : 'en'); quotePublicView(token); };
  const dec = ok => async () => { const f = formData($('#qf')); try { const r = await db.rpc('quote_respond', { p_token: token, p_accept: ok, p_name: f.n, p_note: f.note || null }); toast(ok ? tr('شكرا لكم، تم قبول العرض') + (r && r !== 'rejected' ? ' — ' + r : '') : tr('تم تسجيل الرفض')); quotePublicView(token); } catch (e) { showErr($('#qerr'), e); } };
  if ($('#qy')) { $('#qy').onclick = dec(true); $('#qn').onclick = dec(false); }
}
async function quoteLinkDialog(doc, party) {
  const t = await db.rpc('quote_link_get', { p_id: doc.id }), url = location.origin + location.pathname + '#/q/' + t;
  const msg = tr('السادة') + ' ' + party.name + tr('،') + '\n' + tr('مرفق عرض السعر رقم') + ' ' + doc.no + ' ' + tr('بقيمة') + ' ' + money(doc.total) + '.\n' + tr('للاطلاع عليه وقبوله أو رفضه:') + '\n' + url;
  const d = modal(tr('رابط العرض للعميل'), `<p class="small">${esc(tr('يفتح العميل العرض بدون تسجيل دخول ويقبله أو يرفضه. عند القبول يتحول إلى أمر بيع تلقائيا.'))}</p><input id="qurl" readonly dir="ltr" value="${esc(url)}">
    <div class="row" style="gap:8px;margin-top:10px;flex-wrap:wrap"><button type="button" class="btn" id="qcp">${esc(tr('نسخ الرابط'))}</button>${party.phone ? waBtn(party.phone, msg, tr('إرسال واتساب'), 'btn wa') : ''}
      ${party.email ? `<a class="btn" href="mailto:${encodeURIComponent(party.email)}?subject=${encodeURIComponent(tr('عرض سعر') + ' ' + doc.no)}&body=${encodeURIComponent(msg)}">${esc(tr('إيميل'))}</a>` : ''}<a class="btn" href="${esc(url)}" target="_blank" rel="noopener">${esc(tr('معاينة'))}</a></div>`, {});
  $('#qcp', d).onclick = () => { navigator.clipboard && navigator.clipboard.writeText(url).then(() => toast(tr('نُسخ الرابط'))).catch(() => $('#qurl', d).select()); };
}

/* ----- 14. landed costs ----- */
const LC_T = { freight: 'الشحن', customs: 'الجمارك', insurance: 'التأمين', clearing: 'التخليص', other: 'أخرى' };
VIEWS['#/landed'] = async page => {
  if (!can('purch')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const [rows, bills, parties, acc] = await Promise.all([db.get('landed_costs', { company_id: 'eq.' + S.cid, order: 'date.desc' }), db.get('purchase_bills', { company_id: 'eq.' + S.cid, status: 'eq.posted', order: 'date.desc', limit: 200, select: 'id,no,supplier_ref,date,party_id,subtotal' }),
    db.get('parties', { company_id: 'eq.' + S.cid, kind: 'eq.supplier', select: 'id,name' }), accounts()]);
  const pm = {}; parties.forEach(p => pm[p.id] = p.name); const bm = {}; bills.forEach(b => bm[b.id] = b); const cash = acc.filter(a => a.parent_code === '1100' && !a.is_header);
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('التكاليف المحمّلة على البضاعة'))}</h1><div class="muted">${esc(tr('الشحن والجمارك والتأمين على بضاعة مستوردة تُوزَّع على أصناف فواتير الشراء: ما زال في المخزون ترتفع تكلفته، وما بيع منه يذهب إلى تكلفة المبيعات.'))}</div></div><button class="btn pri" id="lcn">+ ${esc(tr('تكاليف جديدة'))}</button></div>
    ${tbl([{ t: 'الرقم', h: l => `<span class="num">${esc(l.no)}</span>` }, { t: 'التاريخ', h: l => fdate(l.date) }, { t: 'الفواتير', h: l => l.bill_ids.map(b => bm[b] ? esc(bm[b].supplier_ref || bm[b].no) : '').join('، ') },
      { t: 'الإجمالي', r: 1, h: l => money(l.total) }, { t: 'على المخزون', r: 1, h: l => money(l.to_stock) }, { t: 'على تكلفة المبيعات', r: 1, h: l => money(l.to_cogs) }], rows, { empty: 'لا توجد تكاليف محمّلة', onRow: true })}`;
  bindRows(page, rows, l => modal(l.no, tbl([{ t: 'الصنف', h: x => esc(x.name) }, { t: 'الكمية', r: 1, h: x => `<span class="num">${+x.qty}</span>` }, { t: 'قيمة الشراء', r: 1, h: x => money(x.value) }, { t: 'نصيبه', r: 1, h: x => money(x.share) }, { t: 'على المخزون', r: 1, h: x => money(x.stock) }, { t: 'على تكلفة المبيعات', r: 1, h: x => money(x.cogs) }], l.allocation, {}), { wide: true }));
  const crow = () => `<tr><td><select data-c="t">${Object.entries(LC_T).map(([k, t]) => opt(k, tr(t))).join('')}</select></td><td><input data-c="a" type="number" min="0" step="0.01" style="width:120px"></td><td><input data-c="n" maxlength="120"></td><td><button type="button" class="btn sm" data-cx aria-label="${esc(tr('حذف'))}">×</button></td></tr>`;
  $('#lcn', page).onclick = () => { const d = modal(tr('تكاليف محمّلة جديدة'), `<div class="fg">${field('التاريخ', `<input type="date" name="d" value="${today()}" max="${today()}">`)}${field('تُدفع من', `<select name="acc">${cash.map(a => opt(a.code, a.code + ' — ' + a.name, '1120')).join('')}</select>`)}
      ${field('طريقة التوزيع', `<select name="m">${opt('value', tr('حسب قيمة الشراء'))}${opt('qty', tr('حسب الكمية'))}</select>`)}
      <div class="wide"><label>${esc(tr('فواتير الشراء'))}</label><div style="max-height:180px;overflow:auto;border:1px solid var(--line);border-radius:8px;padding:6px">${bills.map(b => `<label class="row small" style="gap:6px"><input type="checkbox" data-b="${b.id}" style="width:auto"> <span class="num">${esc(b.supplier_ref || b.no)}</span> — ${esc(pm[b.party_id] || '')} — ${fdate(b.date)} — ${money(b.subtotal)}</label>`).join('')}</div></div></div>
      <div class="tw"><table class="lines"><thead><tr><th>${esc(tr('النوع'))}</th><th>${esc(tr('المبلغ'))}</th><th>${esc(tr('ملاحظة'))}</th><th></th></tr></thead><tbody id="lcl">${crow()}</tbody></table></div><button type="button" class="btn sm" id="lca" style="margin-top:6px">+ ${esc(tr('تكلفة'))}</button>`,
    { wide: true, onOk: async f => { const bs = $$('[data-b]:checked', d).map(x => x.dataset.b), cs = $$('#lcl tr', d).map(t => ({ type: $('[data-c=t]', t).value, amount: +$('[data-c=a]', t).value, note: $('[data-c=n]', t).value })).filter(c => c.amount > 0);
      if (!bs.length) throw new Error(tr('اختر فاتورة شراء واحدة على الأقل')); if (!cs.length) throw new Error(tr('أدخل التكاليف'));
      await db.rpc('landed_post', { p_company: S.cid, p_doc: { date: f.d, account: f.acc, method: f.m, bills: bs, costs: cs } }); toast(tr('تم الترحيل')); route(); } });
    $('#lca', d).onclick = () => $('#lcl', d).insertAdjacentHTML('beforeend', crow()); $('#lcl', d).addEventListener('click', e => { if (e.target.matches('[data-cx]')) e.target.closest('tr').remove(); }); };
};

/* ----- 15. deferred revenue ----- */
VIEWS['#/deferred'] = async page => {
  if (!can('je')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const [rows, posts, acc, invs] = await Promise.all([db.get('deferred_schedules', { company_id: 'eq.' + S.cid, order: 'created_at.desc' }), db.get('deferred_postings', { select: 'schedule_id,amount' }), accounts(),
    db.get('sales_invoices', { company_id: 'eq.' + S.cid, status: 'eq.posted', order: 'date.desc', limit: 200, select: 'id,no,date,subtotal' })]);
  const done = {}; posts.forEach(p => done[p.schedule_id] = n0(done[p.schedule_id]) + n0(p.amount)); const rev = acc.filter(a => a.type === 'rev' && !a.is_header);
  const ST = { active: ['جارٍ', 'wait'], done: ['اكتمل', 'ok'], stopped: ['موقوف', ''] };
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الإيرادات المؤجلة'))}</h1><div class="muted">${esc(tr('مبلغ فُوتر مقدما (عقد سنوي مثلا) يُنقل إلى «إيرادات مؤجلة» ثم يُثبت إيرادا شهرا بشهر.'))}</div></div>
      <div class="row" style="gap:6px"><button class="btn" id="dfr">${esc(tr('ترحيل أشهر الإيراد المستحقة'))}</button><button class="btn pri" id="dfn">+ ${esc(tr('إيراد مؤجل'))}</button></div></div>
    ${tbl([{ t: 'الوصف', h: s => `<b data-nt>${esc(s.name)}</b>` }, { t: 'من شهر', h: s => esc(s.start_month.slice(0, 7)) }, { t: 'الأشهر', r: 1, h: s => `<span class="num">${s.months}</span>` },
      { t: 'الإجمالي', r: 1, h: s => money(s.total) }, { t: 'أُثبت', r: 1, h: s => money(done[s.id] || 0) }, { t: 'المتبقي', r: 1, h: s => money(n0(s.total) - n0(done[s.id])) },
      { t: 'الحالة', h: s => `<span class="badge ${ST[s.status][1]}">${esc(tr(ST[s.status][0]))}</span>` }, { t: '', h: s => s.status === 'active' ? `<button class="btn sm" data-dfs="${s.id}">${esc(tr('إيقاف'))}</button>` : '' }], rows, { empty: 'لا توجد إيرادات مؤجلة' })}`;
  $('#dfr', page).onclick = () => busy($('#dfr', page), async () => { const n = await db.rpc('deferred_run', { p_company: S.cid, p_through: today() }); toast(tr('رُحّل') + ' ' + n + ' ' + tr('قيد')); route(); });
  $$('[data-dfs]', page).forEach(b => b.onclick = async () => { await db.rpc('deferred_stop', { p_id: b.dataset.dfs }); route(); });
  $('#dfn', page).onclick = () => modal(tr('إيراد مؤجل'), `<div class="fg">${field('الوصف', inp('n', '', 'required maxlength="120"'), 'wide')}${field('الفاتورة (اختياري)', `<select name="inv"><option value="">—</option>${invs.map(i => opt(i.id, i.no + ' — ' + i.date + ' — ' + moneyN(i.subtotal))).join('')}</select>`)}
      ${field('حساب الإيراد', `<select name="ra">${rev.map(a => opt(a.code, a.code + ' — ' + a.name, '4200')).join('')}</select>`)}${field('المبلغ قبل الضريبة', inp('a', '', 'type="number" min="0" step="0.01"'))}
      ${field('من شهر', `<input type="month" name="st" value="${today().slice(0, 7)}">`)}${field('عدد الأشهر', inp('m', 12, 'type="number" min="2" max="120"'))}</div>
      <p class="muted small">${esc(tr('عند الحفظ يُنقل المبلغ من حساب الإيراد إلى «إيرادات مؤجلة» (2180)، ثم يُثبت كل شهر جزؤه بزر الترحيل أو عند إقفال الشهر.'))}</p>`,
    { onOk: async f => { await db.rpc('deferred_create', { p_company: S.cid, p_doc: { name: f.n, invoice: f.inv || null, revenue: f.ra, amount: +f.a, start: f.st + '-01', months: +f.m } }); toast(tr('تم الحفظ')); route(); } });
};

/* ----- 16. supplier payment run ----- */
VIEWS['#/payrun'] = async page => {
  if (!can('purch')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const [bills, parties, acc, batches] = await Promise.all([db.get('purchase_bills', { company_id: 'eq.' + S.cid, status: 'eq.posted', order: 'due_date', select: 'id,no,supplier_ref,date,due_date,party_id,total,currency' }),
    db.get('parties', { company_id: 'eq.' + S.cid, kind: 'eq.supplier', select: 'id,name,iban,phone' }), accounts(), db.get('payment_batches', { company_id: 'eq.' + S.cid, order: 'created_at.desc', limit: 20 })]);
  const pm = {}; parties.forEach(p => pm[p.id] = p); const paid = await paidMap(DOCS.purchases, bills.map(b => b.id)), cash = acc.filter(a => a.parent_code === '1100' && !a.is_header);
  const open = bills.filter(b => !b.currency && n0(b.total) - n0(paid[b.id]) > 0.009).map(b => Object.assign(b, { rem: r2(n0(b.total) - n0(paid[b.id])) }));
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('دفعة سداد جماعية'))}</h1><div class="muted">${esc(tr('اختر فواتير الموردين المستحقة وادفعها مرة واحدة، ثم نزّل ملف البنك بأسماء الموردين والآيبان والمبالغ.'))}</div></div></div>
    <div class="card"><div class="row" style="gap:8px;flex-wrap:wrap;align-items:flex-end">${field('تُدفع من', `<select id="pra">${cash.map(a => opt(a.code, a.code + ' — ' + a.name, '1120')).join('')}</select>`)}${field('التاريخ', `<input type="date" id="prd" value="${today()}" max="${today()}">`)}
      <label class="row small" style="gap:4px"><input type="checkbox" id="prall" style="width:auto"> ${esc(tr('المستحق حتى اليوم'))}</label><div class="sp"></div><b>${esc(tr('الإجمالي'))}: <span id="prt" class="num">${money(0)}</span></b><button class="btn pri" id="prgo" disabled>${esc(tr('سداد المحدد'))}</button></div>
    ${tbl([{ t: '', h: b => `<input type="checkbox" data-pb="${b.id}" style="width:auto" aria-label="${esc(tr('تحديد'))}">` }, { t: 'المورد', h: b => `<span data-nt>${esc((pm[b.party_id] || {}).name || '')}</span>${(pm[b.party_id] || {}).iban ? '' : ` <span class="badge wait">${esc(tr('بدون آيبان'))}</span>`}` },
      { t: 'الفاتورة', h: b => `<span class="num">${esc(b.supplier_ref || b.no)}</span>` }, { t: 'الاستحقاق', h: b => fdate(b.due_date) + (b.due_date < today() ? ` <span class="badge bad">${esc(tr('متأخرة'))}</span>` : '') },
      { t: 'المتبقي', r: 1, h: b => money(b.rem) }, { t: 'يُدفع', r: 1, h: b => `<input type="number" data-pa="${b.id}" value="${b.rem}" min="0" max="${b.rem}" step="0.01" style="width:120px">` }], open, { empty: 'لا توجد فواتير موردين مستحقة' })}</div>
    ${batches.length ? `<div class="card"><h2>${esc(tr('الدفعات السابقة'))}</h2>${tbl([{ t: 'الرقم', h: x => `<span class="num">${esc(x.no)}</span>` }, { t: 'التاريخ', h: x => fdate(x.date) }, { t: 'الفواتير', r: 1, h: x => `<span class="num">${x.n}</span>` }, { t: 'الإجمالي', r: 1, h: x => money(x.total) }, { t: '', h: x => `<button class="btn sm" data-pbf="${x.id}">${esc(tr('ملف البنك'))}</button>` }], batches, {})}</div>` : ''}`;
  const sel = () => $$('[data-pb]:checked', page).map(x => ({ bill: x.dataset.pb, amount: +$(`[data-pa="${x.dataset.pb}"]`, page).value }));
  const sync = () => { if (!$('#prt', page)) return; const s = sel(); $('#prt', page).textContent = money(s.reduce((a, x) => a + n0(x.amount), 0)); $('#prgo', page).disabled = !s.length; };
  page.addEventListener('input', sync); page.addEventListener('change', e => { if (!$('#prt', page)) return; if (e.target.id === 'prall') $$('[data-pb]', page).forEach(x => { const b = open.find(o => o.id === x.dataset.pb); x.checked = e.target.checked && b.due_date <= today(); }); sync(); });
  const bankFileOf = async bid => { const ps = await db.get('payments', { batch_id: 'eq.' + bid, select: 'party_id,amount,bill_id,no' }), bl = {}; bills.forEach(b => bl[b.id] = b);
    const rows = ps.map(p => [(pm[p.party_id] || {}).name || '', (pm[p.party_id] || {}).iban || '', +p.amount, (bl[p.bill_id] || {}).supplier_ref || (bl[p.bill_id] || {}).no || '', p.no]);
    const csv = '﻿' + [[tr('المستفيد'), 'IBAN', tr('المبلغ'), tr('المرجع'), tr('رقم السند')], ...rows].map(r => r.map(v => '"' + String(v).replace(/"/g, '""') + '"').join(',')).join('\r\n');
    const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv' })); a.download = 'payment-batch.csv'; a.click(); };
  $$('[data-pbf]', page).forEach(b => b.onclick = () => bankFileOf(b.dataset.pbf));
  $('#prgo', page).onclick = async () => { const s = sel().filter(x => x.amount > 0); if (!s.length) return; const tot = s.reduce((a, x) => a + x.amount, 0);
    if (!await confirmBox(tr('دفعة سداد جماعية'), tr('سداد') + ' ' + s.length + ' ' + tr('فاتورة بإجمالي') + ' ' + money(tot) + '؟', tr('سداد'))) return;
    try { const bid = await db.rpc('payment_batch', { p_company: S.cid, p_doc: { account: $('#pra', page).value, date: $('#prd', page).value, items: s } }); toast(tr('تم السداد')); await bankFileOf(bid); route(); } catch (e) { toast(e.message); } };
};

/* ----- 17. withholding tax (ZATCA guideline, May 2026) ----- */
const WHT_T = { management: 'أتعاب إدارة', royalty: 'إتاوات / ريع', dividends: 'أرباح موزعة', rent: 'إيجار', loan: 'عوائد قروض', insurance: 'أقساط تأمين أو إعادة تأمين', technical: 'خدمات فنية أو استشارية',
  air: 'تذاكر طيران أو شحن جوي / بحري', telecom: 'خدمات اتصالات هاتفية دولية', land_transport: 'نقل بري داخل المملكة', other: 'أي مدفوعات أخرى' };
const WHT_R = { management: 20, royalty: 15, dividends: 5, rent: 5, loan: 5, insurance: 5, technical: 5, air: 5, telecom: 5, land_transport: 15, other: 15 };
const WHT_SRC = 'الدليل الإرشادي العام لضريبة الاستقطاع — هيئة الزكاة والضريبة والجمارك (مايو 2026): المادة 68 من نظام ضريبة الدخل والمادة 63 من لائحته التنفيذية';
function whtDialog(doc, party, rem, acc) {
  const cash = (acc || []).filter(a => a.parent_code === '1100' && !a.is_header);
  const d = modal(tr('سداد مع ضريبة الاستقطاع'), `<div class="fg">${field('نوع الدفعة', `<select name="t" id="wtt">${Object.entries(WHT_T).map(([k, t]) => opt(k, tr(t) + ' — ' + WHT_R[k] + '%', party.wht_type || 'technical')).join('')}</select>`, 'wide')}
      ${field('المبلغ الإجمالي المستحق للمورد', inp('g', rem, `type="number" min="0" step="0.01" max="${rem}"`))}${field('تُدفع من', `<select name="acc">${(cash.length ? cash : [{ code: '1120', name: tr('البنك') }]).map(a => opt(a.code, a.code + ' — ' + a.name, '1120')).join('')}</select>`)}
      ${field('التاريخ', `<input type="date" name="d" value="${today()}" max="${today()}">`)}<div class="wide"><p class="small" id="wth" style="margin:0"></p></div>
      <label class="row small wide" style="gap:6px"><input type="checkbox" name="rem" style="width:auto" checked> ${esc(tr('احفظ نوع الدفعة لهذا المورد'))}</label></div>
      <p class="muted small">${esc(tr('ضريبة الاستقطاع على المدفوعات لغير المقيمين مقابل دخل من مصدر في المملكة. تُحجز من المبلغ وتُسدَّد لهيئة الزكاة والضريبة والجمارك خلال أول 10 أيام من الشهر التالي، ويُعطى المستفيد شهادة بها.'))} ${esc(tr('المصدر'))}: ${esc(tr(WHT_SRC))}.
      ${party.country && party.country !== 'SA' ? '' : ' ' + esc(tr('تنبيه: المورد مسجّل داخل المملكة، والاستقطاع يكون على غير المقيم.'))}</p>`,
    { ok: 'سداد', onOk: async f => { await db.rpc('wht_pay', { p_company: S.cid, p_doc: { bill: doc.id, type: f.t, gross: +f.g, account: f.acc, date: f.d, remember: !!f.rem } }); toast(tr('تم السداد وحُجزت الضريبة')); route(); } });
  const sx = () => { if (!$('#wtt', d)) return; const r = WHT_R[$('#wtt', d).value], g = n0(d.querySelector('[name=g]').value), t = r2(g * r / 100); $('#wth', d).innerHTML = `${esc(tr('الضريبة'))} <b class="num">${r}%</b> = <b>${money(t)}</b> · ${esc(tr('يُدفع للمورد'))} <b>${money(r2(g - t))}</b>`; };
  d.addEventListener('input', sx); d.addEventListener('change', sx); sx();
}
VIEWS['#/wht'] = async (page, arg, q) => {
  if (!(can('purch') || can('je'))) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const mo = (q && q.get('m')) || today().slice(0, 7), [m, acc] = await Promise.all([db.rpc('wht_month', { p_company: S.cid, p_month: mo + '-01' }), accounts()]);
  const cash = acc.filter(a => a.parent_code === '1100' && !a.is_header), due = n0(m.tax) - n0(m.remitted);
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('ضريبة الاستقطاع'))}</h1><div class="muted">${esc(tr('ما حُجز من مدفوعات غير المقيمين في الشهر، وموعد سداده للهيئة.'))}</div></div>
      <form id="whm" class="row" style="gap:6px"><input type="month" name="m" value="${mo}" aria-label="${esc(tr('الشهر'))}"><button class="btn">${esc(tr('عرض'))}</button></form></div>
    <div class="grid" style="margin-bottom:14px"><div class="card kpi"><div class="muted small">${esc(tr('الضريبة المحجوزة'))}</div><div class="v num">${money(m.tax)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('سُددت للهيئة'))}</div><div class="v num">${money(m.remitted)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('آخر موعد للسداد والإقرار'))}</div><div class="v num ${due > 0 && m.due < today() ? 'bad' : ''}">${fdate(m.due)}</div></div></div>
    ${due > 0 ? `<div class="card row" style="gap:8px;align-items:flex-end">${field('تُسدد من', `<select id="wra">${cash.map(a => opt(a.code, a.code + ' — ' + a.name, '1120')).join('')}</select>`)}<button class="btn pri" id="wrg">${esc(tr('تسجيل السداد للهيئة'))} (${money(due)})</button></div>` : ''}
    ${tbl([{ t: 'التاريخ', h: x => fdate(x.date) }, { t: 'المستفيد', h: x => `<span data-nt>${esc(x.party)}</span>${x.country ? ` <span class="small muted num">${esc(x.country)}</span>` : ''}` }, { t: 'نوع الدفعة', h: x => esc(tr(WHT_T[x.type] || x.type)) },
      { t: 'الفاتورة', h: x => `<span class="num">${esc(x.bill || '')}</span>` }, { t: 'المبلغ', r: 1, h: x => money(x.gross) }, { t: 'النسبة', r: 1, h: x => `<span class="num">${+x.rate}%</span>` }, { t: 'الضريبة', r: 1, h: x => `<b>${money(x.tax)}</b>` },
      { t: '', h: x => (x.remitted_at ? `<span class="badge ok">${esc(tr('سُددت'))}</span> ` : '') + `<button class="btn sm" data-wc="${x.id}">${esc(tr('شهادة'))}</button>` }], m.rows, { empty: 'لا توجد ضريبة استقطاع في هذا الشهر' })}
    <p class="muted small">${esc(tr('النسب'))}: ${Object.entries(WHT_T).map(([k, t]) => esc(tr(t)) + ' ' + WHT_R[k] + '%').join(' · ')}. ${esc(tr('المصدر'))}: ${esc(tr(WHT_SRC))}. ${esc(tr('اتفاقيات منع الازدواج الضريبي قد تخفض النسبة بطلب من الهيئة.'))}</p>`;
  $('#whm', page).onsubmit = ev => { ev.preventDefault(); location.hash = '#/wht?m=' + formData(ev.target).m; };
  if ($('#wrg', page)) $('#wrg', page).onclick = () => busy($('#wrg', page), async () => { try { await db.rpc('wht_remit', { p_company: S.cid, p_month: mo + '-01', p_account: $('#wra', page).value, p_date: today() }); toast(tr('سُجّل السداد')); route(); } catch (e) { toast(e.message); } });
  $$('[data-wc]', page).forEach(b => b.onclick = () => { const x = m.rows.find(r => r.id === b.dataset.wc), n = document.createElement('div'); n.className = 'pdoc';
    n.innerHTML = printHead(tr('شهادة ضريبة الاستقطاع')) + `<table class="kv"><tbody><tr><td>${esc(tr('المستفيد'))}</td><td><b>${esc(x.party)}</b></td></tr><tr><td>${esc(tr('تاريخ الدفع'))}</td><td>${fdate(x.date)}</td></tr><tr><td>${esc(tr('نوع الدفعة'))}</td><td>${esc(tr(WHT_T[x.type]))}</td></tr>
      <tr><td>${esc(tr('المبلغ المدفوع (الإجمالي)'))}</td><td>${money(x.gross)}</td></tr><tr><td>${esc(tr('نسبة الاستقطاع'))}</td><td>${+x.rate}%</td></tr><tr><td>${esc(tr('الضريبة المستقطعة'))}</td><td><b>${money(x.tax)}</b></td></tr>
      ${x.bill ? `<tr><td>${esc(tr('الفاتورة'))}</td><td>${esc(x.bill)}</td></tr>` : ''}</tbody></table><p class="small">${esc(tr('نشهد بأننا استقطعنا الضريبة المبينة أعلاه من المبلغ المدفوع لكم، وتُورَّد لهيئة الزكاة والضريبة والجمارك.'))}</p>
      <div style="margin-top:40px">${esc(tr('الختم والتوقيع'))}: ____________</div>`;
    printWith(n, '@page{size:A4 portrait;margin:14mm}'); });
};
