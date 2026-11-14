'use strict';
/* ===== performance reviews ===== */
const RATING = { 1: 'غير مرضٍ', 2: 'يحتاج إلى تحسين', 3: 'يلبي التوقعات', 4: 'يفوق التوقعات', 5: 'متميز' };
const RV_STATUS = { draft: ['لم يُرسل', 'wait'], submitted: ['بانتظار اعتماد الموارد البشرية', 'info'], approved: ['معتمد', 'ok'] };
const rvBadge = s => `<span class="badge ${RV_STATUS[s][1]}">${esc(RV_STATUS[s][0])}</span>`;
const ratingTxt = o => o == null ? '—' : `<span class="num">${(+o).toFixed(2)}</span> ${esc(RATING[Math.min(5, Math.max(1, Math.round(+o)))])}`;

VIEWS['#/reviews'] = async (page, arg) => {
  if (arg) return reviewCycle(page, arg);
  const hr = isHR();
  const [cycles, revs, em] = await Promise.all([db.get('review_cycles', { company_id: 'eq.' + S.cid, order: 'period_end.desc' }), db.get('reviews', { company_id: 'eq.' + S.cid }), employeesMap().catch(() => ({}))]);
  const cyc = {}; cycles.forEach(c => cyc[c.id] = c);
  const mine = revs.filter(r => r.employee_id === S.emp && r.status === 'approved');
  const team = revs.filter(r => S.emp && r.reviewer_id === S.emp && r.employee_id !== S.emp && cyc[r.cycle_id] && cyc[r.cycle_id].status === 'open');
  const nm = id => esc((em[id] || {}).full_name || '—');
  // #17 performance indicators and a ratings chart, shown to HR and the owner
  let perfCard = '';
  if (hr) {
    const lastCyc = cycles.find(c => revs.some(r => r.cycle_id === c.id));
    if (lastCyc) {
      const rs = revs.filter(r => r.cycle_id === lastCyc.id), done = rs.filter(r => r.status === 'approved');
      const avg = done.length ? done.reduce((a, r) => a + n0(r.overall), 0) / done.length : 0;
      const bars = [1, 2, 3, 4, 5].map(k => ({ label: String(k), values: [done.filter(r => Math.round(n0(r.overall)) === k).length] }));
      perfCard = `<div class="card"><h2 style="margin-top:0">مؤشرات الأداء — ${esc(lastCyc.name)}</h2>
        <div class="grid" style="margin:12px 0 4px">
          <div class="card kpi"><div class="muted small">نسبة الإنجاز</div><div class="v num">${rs.length ? Math.round(done.length / rs.length * 100) : 0}%</div><div class="muted small"><span class="num">${done.length}/${rs.length}</span> معتمد</div></div>
          <div class="card kpi"><div class="muted small">متوسط التقييم</div><div class="v num">${avg ? avg.toFixed(2) : '—'}</div><div class="muted small">من 5</div></div>
          <div class="card kpi"><div class="muted small">الأعلى أداء (4–5)</div><div class="v num">${done.filter(r => n0(r.overall) >= 3.5).length}</div></div>
          <div class="card kpi"><div class="muted small">يحتاج متابعة (أقل من 3)</div><div class="v num">${done.filter(r => r.overall != null && n0(r.overall) < 3).length}</div></div>
        </div>
        ${done.length ? `<div class="muted small" style="margin-bottom:6px">توزيع التقديرات (عدد الموظفين لكل درجة)</div>${barChart(bars, [{ name: 'عدد الموظفين', color: '#2563eb' }])}` : `<p class="muted small">لا توجد تقييمات معتمدة بعد في آخر دورة.</p>`}</div>`;
    }
  }
  page.innerHTML = `<div class="head"><div><h1>تقييم الأداء</h1><div class="muted">أهداف بأوزان ودرجات من 1 إلى 5، يقيّم المدير المباشر وتعتمد الموارد البشرية ثم يطّلع الموظف</div></div>${hr ? '<button class="btn pri" id="nc">دورة تقييم جديدة</button>' : ''}</div>
    ${perfCard}
    ${team.length ? `<h2>تقييم فريقي</h2>${tbl([{ t: 'الموظف', h: r => nm(r.employee_id) }, { t: 'الدورة', h: r => esc(cyc[r.cycle_id].name) }, { t: 'الحالة', h: r => rvBadge(r.status) }, { t: 'النتيجة', h: r => ratingTxt(r.overall) }], team, { onRow: true })}<div style="height:18px"></div>` : ''}
    ${S.emp ? `<h2>تقييماتي</h2>${tbl([{ t: 'الدورة', h: r => esc((cyc[r.cycle_id] || {}).name || '') }, { t: 'النتيجة', h: r => ratingTxt(r.overall) }, { t: 'الاطلاع', h: r => r.ack_at ? '<span class="badge ok">اطّلعت</span>' : '<span class="badge wait">بانتظار اطلاعك</span>' }], mine, { empty: 'لا توجد تقييمات معتمدة لك بعد', onRow: true })}<div style="height:18px"></div>` : ''}
    ${hr ? `<h2>دورات التقييم</h2>${tbl([{ t: 'الدورة', k: 'name' }, { t: 'الفترة', h: c => fdate(c.period_start) + ' → ' + fdate(c.period_end) }, { t: 'الإنجاز', h: c => { const rs = revs.filter(r => r.cycle_id === c.id); return `<span class="num">${rs.filter(r => r.status === 'approved').length}/${rs.length}</span>`; } }, { t: 'الحالة', h: c => c.status === 'open' ? '<span class="badge info">مفتوحة</span>' : '<span class="badge">مغلقة</span>' }], cycles, { empty: 'لم تبدأ أي دورة تقييم', onRow: true })}` : ''}`;
  const tbls = $$('.tw', page); let i = 0;
  if (team.length) bindRows(tbls[i++], team, r => reviewForm(r, em, cyc[r.cycle_id]));
  if (S.emp) bindRows(tbls[i++], mine, r => reviewView(r, em, cyc[r.cycle_id], { ack: !r.ack_at }));
  if (hr) bindRows(tbls[i++], cycles, c => location.hash = '#/reviews/' + c.id);
  if ($('#nc', page)) $('#nc', page).onclick = () => { const y = new Date().getFullYear();
    modal('دورة تقييم جديدة', `<div class="fg">${field('اسم الدورة', inp('n', 'تقييم الأداء ' + y))}${enF('ne', 'Performance review ' + y)}${field('من', `<input type="date" name="s" value="${y}-01-01">`)}${field('إلى', `<input type="date" name="e" value="${y}-12-31">`)}</div><p class="muted small">يُنشأ تقييم لكل موظف على رأس العمل، ويكون المقيّم مديره المباشر. من ليس له مدير مباشر تقيّمه الموارد البشرية.</p>`, {
      ok: 'بدء الدورة', onOk: async f => { const id = await db.rpc('start_review_cycle', { p_company: S.cid, p_name: f.n, p_start: f.s, p_end: f.e }); if ((f.ne || '').trim()) await db.rpc('review_cycle_set_name_en', { p_id: id, p_name_en: f.ne }); location.hash = '#/reviews/' + id; } }); };
};
async function reviewCycle(page, id) {
  const [[c], revs, em] = await Promise.all([db.get('review_cycles', { id: 'eq.' + id }), db.get('reviews', { cycle_id: 'eq.' + id }), employeesMap()]);
  if (!c) throw new Error('الدورة غير موجودة');
  revs.sort((a, b) => String((em[a.employee_id] || {}).emp_no).localeCompare(String((em[b.employee_id] || {}).emp_no)));
  const nm = i => esc((em[i] || {}).full_name || '—');
  const dist = [1, 2, 3, 4, 5].map(k => revs.filter(r => r.status === 'approved' && Math.round(+r.overall) === k).length);
  page.innerHTML = `<div class="head"><div><a href="#/reviews" class="small">← تقييم الأداء</a><h1>${esc(c.name)} ${c.status === 'open' ? '<span class="badge info">مفتوحة</span>' : '<span class="badge">مغلقة</span>'}</h1><div class="muted">${fdate(c.period_start)} → ${fdate(c.period_end)}</div></div>${c.status === 'open' ? '<button class="btn" id="cl">إغلاق الدورة</button>' : ''}</div>
    <div class="grid" style="margin-bottom:16px">${[5, 4, 3, 2, 1].map(k => `<div class="card kpi"><div class="muted small">${esc(RATING[k])}</div><div class="v num">${dist[k - 1]}</div></div>`).join('')}</div>
    ${tbl([{ t: 'الموظف', h: r => nm(r.employee_id) }, { t: 'المقيّم', h: r => r.reviewer_id ? nm(r.reviewer_id) : '<span class="muted">الموارد البشرية</span>' }, { t: 'الحالة', h: r => rvBadge(r.status) }, { t: 'النتيجة', h: r => ratingTxt(r.overall) }, { t: 'اطلاع الموظف', h: r => r.ack_at ? '<span class="badge ok">اطّلع</span>' : '—' }], revs, { onRow: true })}`;
  bindRows(page, revs, r => r.status === 'submitted' ? reviewView(r, em, c, { decide: true }) : r.status === 'draft' && c.status === 'open' ? reviewForm(r, em, c) : reviewView(r, em, c));
  if ($('#cl', page)) $('#cl', page).onclick = async () => { if (!await confirmBox('إغلاق الدورة', 'لن يمكن تعديل أي تقييم في هذه الدورة بعد الإغلاق.', 'إغلاق')) return; try { await db.rpc('close_review_cycle', { p_id: id }); route(); } catch (e) { toast(e.message); } };
}
function reviewForm(r, em, c) {
  const goals = (r.goals && r.goals.length ? r.goals : [{ t: '', w: 100, s: null, c: '' }]).map(g => Object.assign({}, g));
  const e = em[r.employee_id] || {};
  const d = modal('تقييم ' + (e.full_name || ''), `<p class="muted small">${esc(c.name)} · ${esc(e.job_title || '')}${r.hr_comment ? ` — <span class="bad">ملاحظة الموارد البشرية: ${esc(r.hr_comment)}</span>` : ''}</p>
    <div class="tw"><table><thead><tr><th>الهدف</th><th>الوزن %</th><th>الدرجة</th><th>تعليق</th><th></th></tr></thead><tbody id="gl"></tbody></table></div>
    <div class="row" style="margin:8px 0 14px"><button type="button" class="btn sm" id="ga">+ هدف</button><span class="sp" style="flex:1"></span><span class="small">مجموع الأوزان: <b class="num" id="gw"></b>% · النتيجة: <b id="go"></b></span></div>
    <div class="fg">${field('نقاط القوة', `<textarea name="st" rows="2">${esc(r.strengths || '')}</textarea>`, 'wide')}${field('مجالات التطوير', `<textarea name="im" rows="2">${esc(r.improvements || '')}</textarea>`, 'wide')}${field('تعليق المقيّم', `<textarea name="cm" rows="2">${esc(r.manager_comment || '')}</textarea>`, 'wide')}</div>
    <p class="muted small">الدرجات: ${[1, 2, 3, 4, 5].map(k => k + ' ' + RATING[k]).join(' · ')}</p>`, {
    wide: true, ok: 'إرسال للاعتماد', onOk: async f => { await save(f, true); toast('أُرسل التقييم للموارد البشرية'); route(); } });
  const save = (f, submit) => db.rpc('save_review', { p_id: r.id, p_goals: goals.map(g => ({ t: g.t.trim(), w: +g.w || 0, s: g.s ? +g.s : null, c: (g.c || '').trim() || undefined })), p_strengths: f.st, p_improvements: f.im, p_comment: f.cm, p_submit: submit });
  const draw = () => {
    $('#gl', d).innerHTML = goals.map((g, i) => `<tr><td style="min-width:200px"><input data-i="${i}" data-k="t" value="${esc(g.t)}" placeholder="مثال: إنجاز المشروع في موعده"></td>
      <td style="width:90px"><input data-i="${i}" data-k="w" type="number" min="0" max="100" value="${esc(g.w)}"></td>
      <td style="width:150px"><select data-i="${i}" data-k="s"><option value="">—</option>${[1, 2, 3, 4, 5].map(k => opt(k, k + ' — ' + RATING[k], g.s)).join('')}</select></td>
      <td style="min-width:160px"><input data-i="${i}" data-k="c" value="${esc(g.c || '')}"></td><td><button type="button" class="btn sm danger" data-rm="${i}" aria-label="حذف الهدف">×</button></td></tr>`).join('');
    $$('[data-k]', d).forEach(x => x.oninput = x.onchange = () => { goals[+x.dataset.i][x.dataset.k] = x.value; sums(); });
    $$('[data-rm]', d).forEach(b => b.onclick = () => { goals.splice(+b.dataset.rm, 1); draw(); });
    sums();
  };
  const sums = () => { const w = goals.reduce((a, g) => a + n0(g.w), 0), ok = w === 100 && goals.every(g => g.s);
    $('#gw', d).textContent = w; $('#gw', d).className = 'num ' + (w === 100 ? 'ok' : 'bad');
    $('#go', d).innerHTML = ok ? ratingTxt(goals.reduce((a, g) => a + n0(g.w) * n0(g.s), 0) / 100) : '—'; };
  $('#ga', d).onclick = () => { if (goals.length < 10) { goals.push({ t: '', w: 0, s: null, c: '' }); draw(); } };
  draw();
  const sv = document.createElement('button'); sv.type = 'button'; sv.className = 'btn'; sv.textContent = 'حفظ كمسودة';
  $('.df', d).insertBefore(sv, $('#mok', d));
  sv.onclick = async () => { try { await busy(sv, () => save(formData($('#mform', d)), false)); d.close(); toast('حُفظت المسودة'); route(); } catch (er) { showErr($('#merr', d), er); } };
}
function reviewView(r, em, c, { decide, ack } = {}) {
  const e = em[r.employee_id] || S.myEmp || {};
  const body = `<p><b>${esc(e.full_name || '')}</b> <span class="muted">${esc(c ? c.name : '')}</span> ${rvBadge(r.status)}</p>
    <div class="tw"><table><thead><tr><th>الهدف</th><th class="r">الوزن</th><th class="r">الدرجة</th><th>تعليق</th></tr></thead><tbody>${(r.goals || []).map(g => `<tr><td>${esc(g.t)}</td><td class="r num">${esc(g.w)}%</td><td class="r num">${g.s ? esc(g.s) : '—'}</td><td>${esc(g.c || '')}</td></tr>`).join('')}</tbody>
    <tfoot><tr><td>النتيجة</td><td></td><td class="r" colspan="2">${ratingTxt(r.overall)}</td></tr></tfoot></table></div>
    ${r.strengths ? `<p><b>نقاط القوة:</b> ${esc(r.strengths)}</p>` : ''}${r.improvements ? `<p><b>مجالات التطوير:</b> ${esc(r.improvements)}</p>` : ''}${r.manager_comment ? `<p><b>تعليق المقيّم:</b> ${esc(r.manager_comment)}</p>` : ''}
    ${r.hr_comment ? `<p><b>ملاحظة الموارد البشرية:</b> ${esc(r.hr_comment)}</p>` : ''}${r.ack_at ? `<p class="muted small">اطّلع الموظف في ${fdate(r.ack_at)}${r.employee_comment ? ': ' + esc(r.employee_comment) : ''}</p>` : ''}
    ${decide ? field('ملاحظة (إلزامية عند الإعادة)', '<textarea name="note" rows="2"></textarea>') : ''}${ack ? field('تعليقك (اختياري)', '<textarea name="note" rows="2"></textarea>') : ''}`;
  const d = modal('تقييم الأداء', body, decide ? { ok: 'اعتماد', onOk: async f => { await db.rpc('decide_review', { p_id: r.id, p_approve: true, p_comment: blank(f.note) }); toast('اعتُمد التقييم'); route(); } }
    : ack ? { ok: 'اطّلعت على التقييم', onOk: async f => { await db.rpc('acknowledge_review', { p_id: r.id, p_comment: blank(f.note) }); toast('شكرا، سُجّل اطلاعك'); route(); } } : {});
  if (decide) {
    const rb = document.createElement('button'); rb.type = 'button'; rb.className = 'btn danger'; rb.textContent = 'إعادة للمقيّم';
    $('.df', d).insertBefore(rb, $('#mok', d));
    rb.onclick = async () => { try { await busy(rb, () => db.rpc('decide_review', { p_id: r.id, p_approve: false, p_comment: $('#mform', d).note.value })); d.close(); toast('أُعيد التقييم للمقيّم'); route(); } catch (er) { showErr($('#merr', d), er); } };
  }
}

/* ===== recruitment ===== */
const STAGES = { applied: 'تقدّم', screening: 'فرز أولي', interview: 'مقابلة', offer: 'عرض وظيفي', hired: 'تم التعيين', rejected: 'مرفوض' };
const IV_TYPE = { onsite: 'حضورية', remote: 'عن بُعد (فيديو)', phone: 'هاتفية' };
const STAGE_CLS = { applied: '', screening: 'info', interview: 'info', offer: 'wait', hired: 'ok', rejected: 'bad' };
const OPEN_ST = { open: ['مفتوحة', 'ok'], onhold: ['معلّقة', 'wait'], closed: ['مغلقة', ''] };
const stBadge = s => `<span class="badge ${STAGE_CLS[s]}">${esc(STAGES[s])}</span>`;
VIEWS['#/recruit'] = async (page, arg) => {
  if (!isHR()) { page.innerHTML = '<div class="note">هذه الصفحة للموارد البشرية.</div>'; return; }
  if (arg) return opening(page, arg);
  const [ops, cands, deps] = await Promise.all([db.get('job_openings', { company_id: 'eq.' + S.cid, order: 'created_at.desc' }), db.get('candidates', { company_id: 'eq.' + S.cid, select: 'opening_id,stage' }), db.get('departments', { company_id: 'eq.' + S.cid, order: 'name' })]);
  const dm = {}; deps.forEach(d => dm[d.id] = d.name);
  const cnt = (o, f) => cands.filter(c => c.opening_id === o.id && f(c)).length;
  page.innerHTML = `<div class="head"><div><h1>التوظيف</h1><div class="muted">الوظائف الشاغرة والمرشحون حتى التعيين</div></div><button class="btn pri" id="no">وظيفة شاغرة جديدة</button></div>
    ${tbl([{ t: 'الوظيفة', k: 'title' }, { t: 'القسم', h: o => esc(dm[o.department_id] || '—') }, { t: 'العدد', r: 1, h: o => o.positions }, { t: 'المرشحون', r: 1, h: o => cnt(o, () => true) }, { t: 'في المقابلات', r: 1, h: o => cnt(o, c => c.stage === 'interview') }, { t: 'عُيّن', r: 1, h: o => cnt(o, c => c.stage === 'hired') }, { t: 'الحالة', h: o => `<span class="badge ${OPEN_ST[o.status][1]}">${esc(OPEN_ST[o.status][0])}</span>` }], ops, { empty: 'لا توجد وظائف شاغرة', onRow: true })}`;
  bindRows(page, ops, o => location.hash = '#/recruit/' + o.id);
  $('#no', page).onclick = () => openingForm(null, deps);
};
function openingForm(o, deps) {
  const v = o || { positions: 1, status: 'open' };
  modal(o ? 'تعديل الوظيفة' : 'وظيفة شاغرة جديدة', `<div class="fg">${field('المسمى الوظيفي', inp('title', v.title, 'required'))}${enF('title_en', v.title_en, 'المسمى الوظيفي بالإنجليزية')}${field('القسم', `<select name="dep"><option value="">—</option>${deps.map(d => opt(d.id, d.name, v.department_id)).join('')}</select>`)}
    ${field('عدد الشواغر', inp('pos', v.positions, 'type="number" min="1" max="100"'))}${field('الحالة', `<select name="st">${Object.entries(OPEN_ST).map(([k, [t]]) => opt(k, t, v.status)).join('')}</select>`)}
    ${field('الوصف والمتطلبات', `<textarea name="desc" rows="4">${esc(v.description || '')}</textarea>`, 'wide')}</div>`, {
    onOk: async f => { if (f.title.length < 2) throw new Error('أدخل المسمى الوظيفي');
      const row = { title: f.title, title_en: blank((f.title_en || '').trim()), department_id: blank(f.dep), positions: +f.pos || 1, status: f.st, description: blank(f.desc) };
      if (o) await db.upd('job_openings', { id: 'eq.' + o.id }, row); else { const [x] = await db.ins('job_openings', Object.assign(row, { company_id: S.cid })); location.hash = '#/recruit/' + x.id; return; }
      route(); } });
}
async function opening(page, id) {
  const [[o], cands, deps] = await Promise.all([db.get('job_openings', { id: 'eq.' + id }), db.get('candidates', { opening_id: 'eq.' + id, order: 'created_at' }), db.get('departments', { company_id: 'eq.' + S.cid, order: 'name' })]);
  if (!o) throw new Error('الوظيفة غير موجودة');
  const by = s => cands.filter(c => c.stage === s).length;
  page.innerHTML = `<div class="head"><div><a href="#/recruit" class="small">← التوظيف</a><h1>${esc(o.title)} <span class="badge ${OPEN_ST[o.status][1]}">${esc(OPEN_ST[o.status][0])}</span></h1><div class="muted">${o.positions} شاغر · ${by('hired')} عُيّن</div></div>
    <div class="row"><button class="btn" id="eo">تعديل الوظيفة</button><button class="btn pri" id="nc">إضافة مرشح</button></div></div>
    ${o.description ? `<div class="card" style="white-space:pre-wrap">${esc(o.description)}</div>` : ''}
    <div class="grid" style="margin-bottom:16px">${Object.keys(STAGES).map(s => `<div class="card kpi"><div class="muted small">${esc(STAGES[s])}</div><div class="v num">${by(s)}</div></div>`).join('')}</div>
    ${tbl([{ t: 'المرشح', k: 'full_name' }, { t: 'الجوال', h: c => `<span class="num">${esc(c.phone || '—')}</span>` }, { t: 'الجنسية', h: c => c.is_saudi ? 'سعودي' : 'غير سعودي' }, { t: 'الراتب المتوقع', r: 1, h: c => money(c.expected_salary) }, { t: 'التقييم', h: c => c.rating ? '★'.repeat(c.rating) : '—' }, { t: 'المقابلة', h: c => c.interview_at ? `<span class="num">${esc(String(c.interview_at).slice(0, 16).replace('T', ' '))}</span>` : '—' }, { t: 'المرحلة', h: c => stBadge(c.stage) }], cands, { empty: 'لا يوجد مرشحون بعد', onRow: true })}`;
  bindRows(page, cands, c => candidateForm(c, o, deps));
  $('#nc', page).onclick = () => candidateForm(null, o, deps);
  $('#eo', page).onclick = () => openingForm(o, deps);
}
function candidateForm(c, o, deps) {
  const v = c || { is_saudi: true, gender: 'm', stage: 'applied' };
  const locked = v.stage === 'hired';
  const stages = Object.entries(STAGES).filter(([k]) => k !== 'hired' || locked);
  const local = v.interview_at ? new Date(new Date(v.interview_at).getTime() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16) : '';
  const d = modal(c ? 'المرشح: ' + c.full_name : 'مرشح جديد — ' + o.title, `<div class="fg">
    ${field('الاسم الكامل', inp('full_name', v.full_name, 'required'))}${enF('full_name_en', v.full_name_en)}${field('الجوال', inp('phone', v.phone, 'dir="ltr" placeholder="05XXXXXXXX"'))}${field('البريد', inp('email', v.email, 'dir="ltr" type="email"'))}
    ${field('رقم الهوية/الإقامة', inp('national_id', v.national_id, 'dir="ltr" inputmode="numeric" maxlength="10"'))}
    ${field('الجنسية', `<select name="is_saudi">${opt('true', 'سعودي', String(v.is_saudi))}${opt('false', 'غير سعودي', String(v.is_saudi))}</select>`)}
    ${field('الجنس', `<select name="gender">${opt('m', 'ذكر', v.gender)}${opt('f', 'أنثى', v.gender)}</select>`)}
    ${field('الراتب المتوقع', inp('sal', v.expected_salary, 'type="number" step="0.01" min="0"'))}
    ${field('المرحلة', `<select name="stage" ${locked ? 'disabled' : ''}>${stages.map(([k, t]) => opt(k, t, v.stage)).join('')}</select>`)}
    ${field('موعد المقابلة', `<input type="datetime-local" name="iv" value="${local}">`)}
    ${field('نوع المقابلة', `<select name="itype"><option value="">—</option>${Object.entries(IV_TYPE).map(([k, t]) => opt(k, t, v.interview_type)).join('')}</select>`)}
    ${field('تقييم المقابلة', `<select name="rating"><option value="">—</option>${[1, 2, 3, 4, 5].map(k => opt(k, '★'.repeat(k), v.rating)).join('')}</select>`)}
    ${field('ملاحظات', `<textarea name="notes" rows="3">${esc(v.notes || '')}</textarea>`, 'wide')}
    ${c ? `<div class="wide"><label>${esc(tr('السيرة الذاتية والمرفقات'))}</label><div id="cvl" class="small muted">${esc(tr('جارٍ التحميل…'))}</div>
      <label class="btn sm" style="margin-top:6px">${esc(tr('إرفاق ملف'))}<input type="file" id="cvf" accept=".pdf,.doc,.docx,image/*" hidden></label> <span class="small muted">${esc(tr('PDF أو Word أو صورة — حتى 3 ميجابايت'))}</span><div id="cverr"></div></div>` : ''}
    ${c && !['hired', 'rejected'].includes(c.stage) ? '<div class="wide"><button type="button" class="btn pri" id="hire">تعيين وإنشاء سجل موظف</button></div>' : ''}
    ${locked ? '<div class="wide note">عُيّن هذا المرشح وأُنشئ سجله في «الموظفون».</div>' : ''}</div>`, {
    wide: true, onOk: async f => {
      if (f.full_name.length < 3) throw new Error('أدخل الاسم الكامل');
      if (f.national_id && !/^[12]\d{9}$/.test(f.national_id)) throw new Error('رقم الهوية/الإقامة 10 أرقام يبدأ بـ 1 أو 2');
      const row = { full_name: f.full_name, full_name_en: blank((f.full_name_en || '').trim()), phone: blank(f.phone), email: blank(f.email), national_id: blank(f.national_id), is_saudi: f.is_saudi === 'true', gender: f.gender, expected_salary: f.sal === '' ? null : +f.sal, interview_at: f.iv ? new Date(f.iv).toISOString() : null, interview_type: blank(f.itype), rating: f.rating ? +f.rating : null, notes: blank(f.notes) };
      if (!locked) row.stage = f.stage;
      if (c) await db.upd('candidates', { id: 'eq.' + c.id }, row); else await db.ins('candidates', Object.assign(row, { company_id: S.cid, opening_id: o.id }));
      toast('تم الحفظ'); route();
    } });
  if ($('#hire', d)) $('#hire', d).onclick = () => hireForm(c, o, deps);
  if (c) candFiles(c, d);
}
async function candFiles(c, d) {
  const draw = async () => {
    const fs = await db.get('candidate_files', { candidate_id: 'eq.' + c.id, select: 'id,file_name,size,created_at', order: 'created_at' }).catch(() => []);
    $('#cvl', d).innerHTML = fs.length ? fs.map(x => `<div class="row" style="gap:8px"><a href="#" data-cvo="${x.id}">${esc(x.file_name)}</a><span class="num">${Math.ceil(x.size / 1024)} KB</span><button type="button" class="btn sm" data-cvd="${x.id}" aria-label="${esc(tr('حذف المرفق'))}">×</button></div>`).join('') : esc(tr('لا توجد مرفقات'));
    $$('[data-cvo]', d).forEach(a => a.onclick = e => { e.preventDefault(); openAttachment(a.dataset.cvo, 'candidate_files'); });
    $$('[data-cvd]', d).forEach(b => b.onclick = async () => { try { await db.del('candidate_files', { id: 'eq.' + b.dataset.cvd }); draw(); } catch (er) { showErr($('#cverr', d), er); } });
  };
  $('#cvf', d).onchange = async ev => { const file = ev.target.files[0]; if (!file) return;
    try {
      let a;
      if (/\.(docx?)$/i.test(file.name)) { if (file.size > 3 * 1048576) throw new Error(tr('حجم الملف أكبر من 3 ميجابايت') + ': ' + file.name);
        a = { name: file.name, mime: /\.docx$/i.test(file.name) ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' : 'application/msword', data: await blobB64(file) }; }
      else a = await readAttachment(file);
      await db.ins('candidate_files', { company_id: S.cid, candidate_id: c.id, file_name: a.name, mime: a.mime, size: Math.round(a.data.length * 3 / 4), data: a.data });
      $('#cverr', d).innerHTML = ''; draw();
    } catch (er) { showErr($('#cverr', d), er); }
    ev.target.value = ''; };
  draw();
}
async function hireForm(c, o, deps) {
  const em = await employeesMap(true);
  const nums = Object.values(em).map(e => +e.emp_no).filter(n => n > 0);
  const next = String(nums.length ? Math.max(...nums) + 1 : 1000);
  const basic = c.expected_salary ? r2(c.expected_salary / 1.35) : '';
  modal('تعيين ' + c.full_name, `<div class="fg">${field('الرقم الوظيفي', inp('emp_no', next, 'dir="ltr" required'))}${field('المسمى الوظيفي', inp('job_title', o.title))}
    ${field('القسم', `<select name="dep"><option value="">—</option>${deps.map(d => opt(d.id, d.name, o.department_id)).join('')}</select>`)}
    ${field('المدير المباشر', `<select name="mgr"><option value="">—</option>${Object.values(em).filter(e => !e.end_date).map(e => opt(e.id, e.full_name + ' (' + e.emp_no + ')')).join('')}</select>`)}
    ${field('تاريخ المباشرة', `<input type="date" name="hd" value="${today()}">`)}${field('نهاية فترة التجربة (حد أقصى 180 يوما — م53)', '<input type="date" name="pe">')}
    ${field('الراتب الأساسي', inp('basic', basic, 'type="number" step="0.01" min="0" required'))}${field('بدل السكن', inp('housing', basic ? r2(basic * 0.25) : '', 'type="number" step="0.01" min="0"'))}${field('بدل النقل', inp('transport', basic ? r2(basic * 0.10) : '', 'type="number" step="0.01" min="0"'))}</div>
    <p class="muted small">يُنشأ سجل الموظف ببيانات المرشح (الاسم والهوية والجوال والبريد). إذا اكتمل عدد الشواغر تُغلق الوظيفة تلقائيا.</p>`, {
    wide: true, ok: 'تعيين', onOk: async f => {
      if (f.basic === '' || !(+f.basic >= 0)) throw new Error('أدخل الراتب الأساسي');
      if (f.pe && (new Date(f.pe) - new Date(f.hd)) / 864e5 > 179) throw new Error('فترة التجربة لا تزيد على 180 يوما — م53');
      await db.rpc('hire_candidate', { p_cand: c.id, p_emp: { emp_no: f.emp_no, job_title: f.job_title, department_id: f.dep, manager_id: f.mgr, hire_date: f.hd, probation_end: f.pe, basic: +f.basic, housing: +f.housing || 0, transport: +f.transport || 0 } });
      cache.emps = null; toast('عُيّن المرشح وأُنشئ سجل الموظف'); route();
    } });
}

/* ===== training ===== */
const TA_ST = { enrolled: ['مسجّل', 'info'], completed: ['أكمل', 'ok'], no_show: ['لم يحضر', 'bad'] };
VIEWS['#/training'] = async (page, arg) => {
  if (!isHR()) { page.innerHTML = '<div class="note">هذه الصفحة للموارد البشرية.</div>'; return; }
  if (arg) return training(page, arg);
  const [trs, att] = await Promise.all([db.get('trainings', { company_id: 'eq.' + S.cid, order: 'start_date.desc' }), db.get('training_attendees', { company_id: 'eq.' + S.cid, select: 'training_id,status,cert_expiry' })]);
  const y = today().slice(0, 4), thisYear = trs.filter(t => String(t.start_date).startsWith(y));
  const soon = att.filter(a => a.cert_expiry && a.cert_expiry >= today() && a.cert_expiry <= addDays(today(), 60)).length;
  page.innerHTML = `<div class="head"><div><h1>التدريب</h1><div class="muted">الدورات والحضور والشهادات</div></div><button class="btn pri" id="nt">دورة جديدة</button></div>
    <div class="grid" style="margin-bottom:16px"><div class="card kpi"><div class="muted small">دورات ${y}</div><div class="v num">${thisYear.length}</div></div>
      <div class="card kpi"><div class="muted small">ساعات التدريب ${y}</div><div class="v num">${thisYear.reduce((a, t) => a + n0(t.hours) * att.filter(x => x.training_id === t.id && x.status === 'completed').length, 0)}</div></div>
      <div class="card kpi"><div class="muted small">تكلفة التدريب ${y}</div><div class="v num">${money(thisYear.reduce((a, t) => a + n0(t.cost), 0))}</div></div>
      <div class="card kpi"><div class="muted small">شهادات تنتهي خلال 60 يوما</div><div class="v num ${soon ? 'bad' : ''}">${soon}</div></div></div>
    ${tbl([{ t: 'الدورة', k: 'title' }, { t: 'الجهة', h: t => esc(t.provider || '—') }, { t: 'التاريخ', h: t => fdate(t.start_date) + (t.end_date && t.end_date !== t.start_date ? ' → ' + fdate(t.end_date) : '') }, { t: 'الساعات', r: 1, h: t => t.hours == null ? '—' : t.hours }, { t: 'التكلفة', r: 1, h: t => money(t.cost) }, { t: 'المتدربون', r: 1, h: t => att.filter(a => a.training_id === t.id).length }], trs, { empty: 'لا توجد دورات بعد', onRow: true })}`;
  bindRows(page, trs, t => location.hash = '#/training/' + t.id);
  $('#nt', page).onclick = () => trainingForm(null);
};
const addDays = (d, n) => new Date(new Date(d).getTime() + n * 864e5).toISOString().slice(0, 10);
function trainingForm(t) {
  const v = t || { start_date: today(), cost: 0 };
  modal(t ? 'تعديل الدورة' : 'دورة تدريبية جديدة', `<div class="fg">${field('عنوان الدورة', inp('title', v.title, 'required'), 'wide')}${enF('title_en', v.title_en, 'عنوان الدورة بالإنجليزية', 'wide')}${field('الجهة المقدمة', inp('provider', v.provider))}${field('المكان', inp('location', v.location))}
    ${field('من', `<input type="date" name="sd" value="${esc(v.start_date)}">`)}${field('إلى', `<input type="date" name="ed" value="${esc(v.end_date || '')}">`)}
    ${field('عدد الساعات', inp('hours', v.hours, 'type="number" step="0.5" min="0"'))}${field('التكلفة', inp('cost', v.cost, 'type="number" step="0.01" min="0"'))}
    ${field('ملاحظات', `<textarea name="notes" rows="2">${esc(v.notes || '')}</textarea>`, 'wide')}</div>`, {
    onOk: async f => { if (f.title.length < 3) throw new Error('أدخل عنوان الدورة'); if (!f.sd) throw new Error('أدخل تاريخ البداية');
      const row = { title: f.title, title_en: blank((f.title_en || '').trim()), provider: blank(f.provider), location: blank(f.location), start_date: f.sd, end_date: blank(f.ed), hours: f.hours === '' ? null : +f.hours, cost: +f.cost || 0, notes: blank(f.notes) };
      if (t) await db.upd('trainings', { id: 'eq.' + t.id }, row); else { const [x] = await db.ins('trainings', Object.assign(row, { company_id: S.cid })); location.hash = '#/training/' + x.id; return; }
      route(); } });
}
async function training(page, id) {
  const [[t], att, em] = await Promise.all([db.get('trainings', { id: 'eq.' + id }), db.get('training_attendees', { training_id: 'eq.' + id }), employeesMap(true)]);
  if (!t) throw new Error('الدورة غير موجودة');
  const inIt = new Set(att.map(a => a.employee_id));
  att.sort((a, b) => String((em[a.employee_id] || {}).emp_no).localeCompare(String((em[b.employee_id] || {}).emp_no)));
  page.innerHTML = `<div class="head"><div><a href="#/training" class="small">← التدريب</a><h1>${esc(t.title)}</h1><div class="muted">${esc(t.provider || '')} · ${fdate(t.start_date)}${t.end_date ? ' → ' + fdate(t.end_date) : ''} · ${t.hours == null ? '' : t.hours + ' ساعة · '}<span class="num">${money(t.cost)}</span></div></div>
    <div class="row"><button class="btn" id="et">تعديل الدورة</button><button class="btn pri" id="ad">إضافة متدربين</button></div></div>
    ${tbl([{ t: 'الموظف', h: a => esc((em[a.employee_id] || {}).full_name || '') }, { t: 'الحالة', h: a => `<span class="badge ${TA_ST[a.status][1]}">${esc(TA_ST[a.status][0])}</span>` }, { t: 'رقم الشهادة', h: a => `<span class="num">${esc(a.certificate_no || '—')}</span>` }, { t: 'انتهاء الشهادة', h: a => a.cert_expiry ? (a.cert_expiry < today() ? `<span class="badge bad">${fdate(a.cert_expiry)}</span>` : fdate(a.cert_expiry)) : '—' }], att, { empty: 'لم يُسجَّل متدربون', onRow: true })}`;
  bindRows(page, att, a => { const e = em[a.employee_id] || {};
    const d = modal(e.full_name || '', `<div class="fg">${field('الحالة', `<select name="st">${Object.entries(TA_ST).map(([k, [x]]) => opt(k, x, a.status)).join('')}</select>`)}${field('رقم الشهادة', inp('cn', a.certificate_no, 'dir="ltr"'))}${field('تاريخ انتهاء الشهادة', `<input type="date" name="ce" value="${esc(a.cert_expiry || '')}">`)}</div>
      <button type="button" class="btn sm danger" id="rm" style="margin-top:12px">إزالة من الدورة</button>`, {
      onOk: async f => { await db.upd('training_attendees', { training_id: 'eq.' + id, employee_id: 'eq.' + a.employee_id }, { status: f.st, certificate_no: blank(f.cn), cert_expiry: blank(f.ce) }); route(); } });
    $('#rm', d).onclick = async () => { try { await db.del('training_attendees', { training_id: 'eq.' + id, employee_id: 'eq.' + a.employee_id }); d.close(); route(); } catch (er) { showErr($('#merr', d), er); } }; });
  $('#et', page).onclick = () => trainingForm(t);
  $('#ad', page).onclick = () => { const free = Object.values(em).filter(e => !inIt.has(e.id) && (!e.end_date || e.end_date >= today()));
    modal('إضافة متدربين', free.length ? `<p class="muted small">اختر الموظفين:</p><div style="columns:2;column-gap:16px">${free.map(e => `<label style="display:flex;gap:8px;align-items:center;color:var(--ink);font-size:14px"><input type="checkbox" name="e_${e.id}"> ${esc(e.full_name)}</label>`).join('')}</div>` : '<p class="muted">كل الموظفين مسجّلون في الدورة.</p>', {
      ok: 'إضافة', onOk: async f => { const ids = Object.keys(f).filter(k => k.startsWith('e_') && f[k]).map(k => k.slice(2)); if (!ids.length) throw new Error('اختر موظفا واحدا على الأقل');
        await db.ins('training_attendees', ids.map(eid => ({ training_id: id, employee_id: eid, company_id: S.cid }))); route(); } }); };
}

/* ===== HR reports ===== */
VIEWS['#/hrreports'] = async page => {
  if (!isHR() && !has('finance')) { page.innerHTML = '<div class="note">هذه الصفحة للموارد البشرية.</div>'; return; }
  const y = today().slice(0, 4), yAgo = addDays(today(), -365), in60 = addDays(today(), 60);
  const [em, deps, reqs, lt, att, trs, cycles, revs] = await Promise.all([employeesMap(true), db.get('departments', { company_id: 'eq.' + S.cid, order: 'name' }),
    db.get('requests', { company_id: 'eq.' + S.cid, kind: 'eq.leave', status: 'eq.approved', from_date: 'gte.' + y + '-01-01', select: 'sub,days,employee_id' }), LEAVE_TYPES(),
    isHR() ? db.get('training_attendees', { company_id: 'eq.' + S.cid }) : [], isHR() ? db.get('trainings', { company_id: 'eq.' + S.cid }) : [],
    isHR() ? db.get('review_cycles', { company_id: 'eq.' + S.cid, order: 'period_end.desc' }) : [], isHR() ? db.get('reviews', { company_id: 'eq.' + S.cid, status: 'eq.approved' }) : []]);
  const all = Object.values(em), act = all.filter(e => !e.end_date || e.end_date >= today());
  const docAl = isHR() ? await db.rpc('doc_alerts', { p_company: S.cid, p_within: 60 }).catch(() => []) : [];
  const pend = {}; (await db.rpc('probation_ends', { p_company: S.cid }).catch(() => [])).forEach(p => pend[p.employee_id] = p.effective_end);
  // #23 custody currently held by employees, for the HR report
  const custody = isHR() ? await db.get('custody_items', { company_id: 'eq.' + S.cid, status: 'eq.held', order: 'issued_on.desc' }).catch(() => []) : [];
  const custTotal = custody.reduce((a, c) => a + n0(c.value), 0);
  const gross = e => n0(e.basic) + n0(e.housing) + n0(e.transport);
  const pct = (a, b) => b ? Math.round(a / b * 1000) / 10 + '%' : '—';
  const hires = all.filter(e => e.hire_date >= yAgo && e.hire_date <= today()).length;
  const leavers = all.filter(e => e.end_date && e.end_date >= yAgo && e.end_date < today()).length;
  const startHc = all.filter(e => e.hire_date < yAgo && (!e.end_date || e.end_date >= yAgo)).length;
  const avgHc = (startHc + act.length) / 2;
  const svc = act.length ? act.reduce((a, e) => a + (new Date(today()) - new Date(e.hire_date)) / 864e5 / 365, 0) / act.length : 0;
  const saudi = act.filter(e => e.is_saudi).length, women = act.filter(e => e.gender === 'f').length;
  const dm = {}; deps.forEach(d => dm[d.id] = d.name);
  const groups = [...deps.map(d => ({ n: d.name, l: act.filter(e => e.department_id === d.id) })), { n: 'بدون قسم', l: act.filter(e => !e.department_id || !dm[e.department_id]) }].filter(g => g.l.length);
  const ltn = {}; lt.forEach(l => ltn[l.code] = l.name_ar);
  const leaveBy = {}; reqs.forEach(r => leaveBy[r.sub] = (leaveBy[r.sub] || 0) + n0(r.days));
  const alerts = [
    ...act.map(e => Object.assign({}, e, { probation_end: pend[e.id] || e.probation_end })).filter(e => e.probation_end && e.probation_end >= today() && e.probation_end <= in60).map(e => ({ d: e.probation_end, t: 'نهاية فترة التجربة', n: e.full_name })),
    ...att.filter(a => a.cert_expiry && a.cert_expiry <= in60 && em[a.employee_id] && (!em[a.employee_id].end_date || em[a.employee_id].end_date >= today())).map(a => ({ d: a.cert_expiry, t: (a.cert_expiry < today() ? 'شهادة منتهية: ' : 'انتهاء شهادة: ') + ((trs.find(t => t.id === a.training_id) || {}).title || ''), n: em[a.employee_id].full_name })),
    ...all.filter(e => e.end_date && e.end_date >= today() && e.end_date <= in60).map(e => ({ d: e.end_date, t: 'آخر يوم عمل', n: e.full_name })),
    ...docAl.filter(a => a.due).map(a => ({ d: a.due, t: (a.days_left < 0 ? 'منتهي: ' : 'انتهاء: ') + (DOC_T[a.label] || a.label), n: (em[a.employee_id] || {}).full_name || '' }))].sort((a, b) => a.d < b.d ? -1 : 1);
  const lastCyc = cycles.find(c => revs.some(r => r.cycle_id === c.id));
  const dist = lastCyc ? [5, 4, 3, 2, 1].map(k => ({ k, n: revs.filter(r => r.cycle_id === lastCyc.id && Math.round(+r.overall) === k).length })) : [];
  const kpi = (t, v, s = '') => `<div class="card kpi"><div class="muted small">${esc(t)}</div><div class="v num">${v}</div>${s ? `<div class="muted small">${s}</div>` : ''}</div>`;
  const tHrs = trs.filter(t => String(t.start_date).startsWith(y)).reduce((a, t) => a + n0(t.hours) * att.filter(x => x.training_id === t.id && x.status === 'completed').length, 0);
  page.innerHTML = `<div class="head"><div><h1>تقارير الموارد البشرية</h1><div class="muted">حتى ${today()}</div></div><div class="row"><button class="btn" id="xd">تصدير الأقسام CSV</button><button class="btn" id="xe">تصدير الموظفين CSV</button></div></div>
    <div class="grid" style="margin-bottom:16px">${kpi('الموظفون على رأس العمل', act.length)}${kpi('نسبة السعوديين', pct(saudi, act.length), saudi + ' سعودي · ' + (act.length - saudi) + ' غير سعودي')}${kpi('نسبة النساء', pct(women, act.length))}
      ${kpi('متوسط مدة الخدمة', svc.toFixed(1), 'سنة')}${kpi('التعيينات (12 شهرا)', hires)}${kpi('المغادرون (12 شهرا)', leavers)}${kpi('معدل الدوران', pct(leavers, avgHc), 'المغادرون ÷ متوسط العدد')}
      ${kpi('الرواتب الشهرية', money(act.reduce((a, e) => a + gross(e), 0)), 'إجمالي الأساسي والبدلات')}${isHR() ? kpi('ساعات التدريب ' + y, tHrs) : ''}</div>
    <div class="card"><h2>حسب القسم</h2>${tbl([{ t: 'القسم', k: 'n' }, { t: 'العدد', r: 1, h: g => g.l.length }, { t: 'سعودي', r: 1, h: g => g.l.filter(e => e.is_saudi).length }, { t: 'غير سعودي', r: 1, h: g => g.l.filter(e => !e.is_saudi).length }, { t: 'نسبة التوطين', r: 1, h: g => pct(g.l.filter(e => e.is_saudi).length, g.l.length) }, { t: 'الرواتب الشهرية', r: 1, h: g => money(g.l.reduce((a, e) => a + gross(e), 0)) }, { t: 'متوسط الراتب', r: 1, h: g => money(g.l.reduce((a, e) => a + gross(e), 0) / g.l.length) }], groups, { empty: 'لا يوجد موظفون' })}</div>
    <div class="card"><h2>الإجازات المعتمدة في ${y}</h2>${tbl([{ t: 'النوع', h: k => esc(ltn[k] || k) }, { t: 'الأيام', r: 1, h: k => leaveBy[k] }], Object.keys(leaveBy), { empty: 'لا توجد إجازات معتمدة هذه السنة' })}</div>
    <div class="card"><h2>تنبيهات خلال 60 يوما</h2>${tbl([{ t: 'التاريخ', h: a => fdate(a.d) }, { t: 'التنبيه', h: a => esc(a.t) }, { t: 'الموظف', h: a => esc(a.n) }], alerts, { empty: 'لا توجد تنبيهات' })}</div>
    ${isHR() ? `<div class="card"><div class="row" style="justify-content:space-between;align-items:center"><h2 style="margin:0">العهد المسلّمة للموظفين</h2><span class="muted small">إجمالي القيمة: <b class="num">${money(custTotal)}</b></span></div>
      ${tbl([{ t: 'الموظف', h: c => esc((em[c.employee_id] || {}).full_name || '—') }, { t: 'العهدة', h: c => esc((LANG === 'en' && c.name_en) || c.name) }, { t: 'الرقم التسلسلي', h: c => esc(c.serial || '—') }, { t: 'القيمة', r: 1, h: c => c.value == null ? '—' : money(c.value) }, { t: 'تاريخ التسليم', h: c => fdate(c.issued_on) }], custody, { empty: 'لا توجد عهد مسلّمة حاليا' })}</div>` : ''}
    ${lastCyc ? `<div class="card"><h2>توزيع نتائج ${esc(lastCyc.name)}</h2>${tbl([{ t: 'التقدير', h: x => x.k + ' — ' + esc(RATING[x.k]) }, { t: 'العدد', r: 1, h: x => x.n }, { t: 'النسبة', r: 1, h: x => pct(x.n, dist.reduce((a, z) => a + z.n, 0)) }], dist)}</div>` : ''}`;
  const dl = (name, rows) => { const csv = '﻿' + rows.map(r => r.map(tr)).map(r => r.map(v => /[",\n]/.test(String(v)) ? '"' + String(v).replace(/"/g, '""') + '"' : v).join(',')).join('\r\n');
    const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' })); a.download = name; a.click(); };
  $('#xd', page).onclick = () => dl('departments-' + today() + '.csv', [['القسم', 'العدد', 'سعودي', 'غير سعودي', 'الرواتب الشهرية'], ...groups.map(g => [g.n, g.l.length, g.l.filter(e => e.is_saudi).length, g.l.filter(e => !e.is_saudi).length, r2(g.l.reduce((a, e) => a + gross(e), 0))])]);
  $('#xe', page).onclick = () => dl('employees-' + today() + '.csv', [EXPORT_COLS.map(c => c[1]), ...act.map(e => EXPORT_COLS.map(c => c[2](e, em, dm)))]);
};
const NATIONS = [['SA', 'سعودي'], ['EG', 'مصري'], ['IN', 'هندي'], ['PK', 'باكستاني'], ['BD', 'بنغلاديشي'], ['PH', 'فلبيني'], ['YE', 'يمني'], ['SY', 'سوري'], ['JO', 'أردني'], ['SD', 'سوداني'], ['LK', 'سريلانكي'], ['NP', 'نيبالي'], ['ID', 'إندونيسي'], ['LB', 'لبناني'], ['PS', 'فلسطيني'], ['MA', 'مغربي'], ['TN', 'تونسي'], ['DZ', 'جزائري'], ['IQ', 'عراقي'], ['AE', 'إماراتي'], ['KW', 'كويتي'], ['BH', 'بحريني'], ['QA', 'قطري'], ['OM', 'عماني'], ['LY', 'ليبي'], ['MR', 'موريتاني'], ['SO', 'صومالي'], ['ER', 'إريتري'], ['ET', 'إثيوبي'], ['KE', 'كيني'], ['UG', 'أوغندي'], ['NG', 'نيجيري'], ['GH', 'غاني'], ['TD', 'تشادي'], ['TR', 'تركي'], ['IR', 'إيراني'], ['AF', 'أفغاني'], ['UZ', 'أوزبكي'], ['MM', 'ميانماري'], ['TH', 'تايلندي'], ['VN', 'فيتنامي'], ['MY', 'ماليزي'], ['CN', 'صيني'], ['KR', 'كوري'], ['JP', 'ياباني'], ['US', 'أمريكي'], ['CA', 'كندي'], ['GB', 'بريطاني'], ['FR', 'فرنسي'], ['DE', 'ألماني'], ['IT', 'إيطالي'], ['ES', 'إسباني'], ['RU', 'روسي'], ['AU', 'أسترالي'], ['ZA', 'جنوب أفريقي'], ['BR', 'برازيلي']];
const natName = c => { if (!c) return ''; const n = NATIONS.find(x => x[0] === c); return n ? tr(n[1]) : c; };
const natOpts = (sel, isSaudi) => (sel || isSaudi ? '' : opt('', tr('غير سعودي — حدد الجنسية'), '')) + NATIONS.map(n => opt(n[0], tr(n[1]), sel || (isSaudi ? 'SA' : ''))).join('');
const soft = s => normHead(s).replace(/[\u0629\u0647]$/, '').replace(/\u0649$/, '\u064a');
function natCode(v) {
  const s = soft(v); if (!s) return '';
  if (/^[a-z]{2}$/.test(s)) return s.toUpperCase();
  if (/^(ksa|السعودي|السعوديه|المملكه العربيه السعودي)$/.test(s)) return 'SA';
  const n = NATIONS.find(x => [x[1], trTo(x[1])].some(a => soft(a) === s)); return n ? n[0] : '?';
}
const MARITAL = { single: 'أعزب', married: 'متزوج', divorced: 'مطلق', widowed: 'أرمل' };
const EDU = { none: 'بدون مؤهل', primary: 'ابتدائي', intermediate: 'متوسط', secondary: 'ثانوي', diploma: 'دبلوم', bachelor: 'بكالوريوس', master: 'ماجستير', phd: 'دكتوراه' };
const ALIAS = { single: 'عزباء', married: 'متزوجة', divorced: 'مطلقة', widowed: 'أرملة' };
function pickKey(map, v) { const s = soft(v); if (!s) return ''; for (const [k, ar] of Object.entries(map)) if ([k, ar, trTo(ar), ALIAS[k] || ''].some(a => a && soft(a) === s)) return k; return '?'; }
/* the new profile columns, shared by the import, the bulk update and the export */
const PROFILE_COLS = [
  ['birth_date', 'تاريخ الميلاد', 'birth date|date of birth|dob|birth_date'],
  ['marital_status', 'الحالة الاجتماعية', 'marital status|marital_status'],
  ['dependents', 'عدد المرافقين', 'dependents|المرافقين|عدد التابعين'],
  ['official_profession', 'المهنة الرسمية (قوى/الإقامة)', 'official profession|iqama profession|profession|المهنة|المهنة في الاقامة'],
  ['education', 'المؤهل الدراسي', 'education|qualification|المؤهل'],
  ['specialization', 'التخصص', 'specialization|major|التخصص الدراسي'],
  ['emergency_name', 'جهة اتصال الطوارئ', 'emergency contact|emergency name|اسم جهة الطوارئ'],
  ['emergency_relation', 'صلة القرابة', 'emergency relation|relation|relationship'],
  ['emergency_phone', 'جوال الطوارئ', 'emergency phone|رقم الطوارئ'],
  ['short_address', 'العنوان المختصر', 'short address|short_address|العنوان الوطني المختصر'],
  ['national_address', 'العنوان الوطني', 'national address|national_address|address|العنوان'],
  ['cost_center', 'مركز التكلفة', 'cost center|cost_center|cost centre'],
  ['work_site', 'موقع العمل', 'work site|work_site|site|location'],
  ['leave_open_days', 'رصيد الإجازة الافتتاحي (يوم)', 'opening leave balance|leave balance|leave_open_days|رصيد الاجازة|رصيد الإجازة'],
  ['leave_open_date', 'تاريخ الرصيد الافتتاحي', 'leave balance date|opening balance date|leave_open_date|تاريخ الرصيد']];
/* normalise one profile cell; returns [value, error] — '' means empty */
function profileCell(k, v) {
  v = arDigits(String(v == null ? '' : v).trim()); if (!v) return [''];
  if (k === 'nationality') { const c = natCode(v); return c === '?' ? ['', tr('الجنسية غير معروفة') + ': ' + v] : [c]; }
  if (k === 'birth_date' || k === 'leave_open_date') { const d = cellDate(v); return /^\d{4}-\d{2}-\d{2}$/.test(d) && !isNaN(new Date(d)) ? [d] : ['', (k === 'birth_date' ? tr('تاريخ الميلاد') : tr('تاريخ الرصيد الافتتاحي')) + ': ' + tr('التاريخ بصيغة YYYY-MM-DD')]; }
  if (k === 'marital_status') { const x = pickKey(MARITAL, v); return x === '?' ? ['', 'الحالة الاجتماعية غير صحيحة'] : [x]; }
  if (k === 'education') { const x = pickKey(EDU, v); return x === '?' ? ['', 'المؤهل الدراسي غير صحيح'] : [x]; }
  if (k === 'dependents') { v = v.replace(/\.0+$/, ''); return /^\d{1,2}$/.test(v) && +v <= 30 ? [v] : ['', 'عدد المرافقين بين 0 و30']; }
  if (k === 'leave_open_days') { v = v.replace(/[,\s]/g, ''); return /^\d+(\.\d+)?$/.test(v) && +v <= 999 ? [v] : ['', 'رصيد الإجازة الافتتاحي بين 0 و999 يوما']; }
  if (k === 'short_address') { v = v.replace(/\s/g, '').toUpperCase(); return /^[A-Z]{4}\d{4}$/.test(v) ? [v] : ['', 'العنوان المختصر 4 حروف و4 أرقام مثل RRRD2929']; }
  if (k === 'emergency_phone') { v = v.replace(/[\s-]/g, '').replace(/\.0+$/, ''); if (/^5\d{8}$/.test(v)) v = '0' + v; return /^\+?\d{7,16}$/.test(v) ? [v] : ['', 'رقم جوال الطوارئ غير صحيح']; }
  return [v];
}
const profileShow = (k, v) => !v ? '' : k === 'nationality' ? natName(v) : k === 'marital_status' ? tr(MARITAL[v] || v) : k === 'education' ? tr(EDU[v] || v) : String(v);
const EXPORT_COLS = [['emp_no', 'الرقم الوظيفي', e => e.emp_no], ['full_name', 'الاسم الكامل', e => e.full_name], ['full_name_en', 'الاسم بالإنجليزية', e => e.full_name_en || ''], ['national_id', 'رقم الهوية/الإقامة', e => e.national_id || ''], ['is_saudi', 'الجنسية', e => e.is_saudi ? 'سعودي' : 'غير سعودي'], ['gender', 'الجنس', e => e.gender === 'f' ? 'أنثى' : 'ذكر'],
  ['job_title', 'المسمى الوظيفي', e => e.job_title || ''], ['job_title_en', 'المسمى الوظيفي بالإنجليزية', e => e.job_title_en || ''], ['department', 'القسم', (e, em, dm) => dm[e.department_id] || ''], ['manager', 'الرقم الوظيفي للمدير', (e, em) => e.manager_id && em[e.manager_id] ? em[e.manager_id].emp_no : ''], ['hire_date', 'تاريخ المباشرة', e => e.hire_date],
  ['probation_end', 'نهاية فترة التجربة', e => e.probation_end || ''], ['basic', 'الراتب الأساسي', e => e.basic], ['housing', 'بدل السكن', e => e.housing], ['transport', 'بدل النقل', e => e.transport], ['iban', 'الآيبان', e => e.iban || ''], ['phone', 'الجوال', e => e.phone || ''], ['email', 'البريد', e => e.email || '']].concat([['nationality', 'بلد الجنسية'], ...PROFILE_COLS.filter(c => !['cost_center', 'work_site'].includes(c[0]))].map(([k, t]) => [k, t, e => profileShow(k, e[k] == null ? '' : e[k])]));

/* ===== employee import from Excel (.xlsx) or CSV — no external library ===== */

const IMPORT_COLS = [
  ['emp_no', 'الرقم الوظيفي', 'employee number|emp no|emp_no|رقم الموظف', true],
  ['full_name', 'الاسم الكامل', 'full name|name|الاسم|اسم الموظف', true],
  ['full_name_en', 'الاسم بالإنجليزية', 'english name|name (english)|name en|name_en|full_name_en|full name english|الاسم بالانجليزي'],
  ['national_id', 'رقم الهوية/الإقامة', 'national id|id|iqama|الهوية|رقم الهوية|رقم الإقامة|national_id'],
  ['is_saudi', 'الجنسية (سعودي/غير سعودي)', 'nationality|saudi|is_saudi|الجنسية'],
  ['gender', 'الجنس (ذكر/أنثى)', 'gender|الجنس'],
  ['job_title', 'المسمى الوظيفي', 'job title|title|job_title|الوظيفة'],
  ['job_title_en', 'المسمى الوظيفي بالإنجليزية', 'job title english|job_title_en|title en|المسمى بالانجليزي'],
  ['department', 'القسم', 'department|dept|الإدارة'],
  ['manager_emp_no', 'الرقم الوظيفي للمدير', 'manager|manager number|manager_emp_no|المدير المباشر|رقم المدير'],
  ['hire_date', 'تاريخ المباشرة (YYYY-MM-DD)', 'hire date|start date|hire_date|تاريخ التعيين|تاريخ المباشرة', true],
  ['probation_end', 'نهاية فترة التجربة', 'probation end|probation_end|نهاية التجربة'],
  ['basic', 'الراتب الأساسي', 'basic|basic salary|الأساسي', true],
  ['housing', 'بدل السكن', 'housing|housing allowance|السكن'],
  ['transport', 'بدل النقل', 'transport|transport allowance|النقل|المواصلات'],
  ['iban', 'الآيبان', 'iban|ايبان|الحساب البنكي'],
  ['phone', 'الجوال', 'phone|mobile|جوال|رقم الجوال'],
  ['email', 'البريد', 'email|e-mail|البريد الإلكتروني'],
  ['nationality', 'بلد الجنسية', 'nationality country|country|الدولة|بلد الجنسية'], ...PROFILE_COLS];
const normHead = h => String(h || '').replace(/\(.*?\)|\*/g, '').replace(/[إأآ]/g, 'ا').replace(/\s+/g, ' ').trim().toLowerCase();
const arDigits = s => String(s).replace(/[٠-٩]/g, d => '٠١٢٣٤٥٦٧٨٩'.indexOf(d)).replace(/[۰-۹]/g, d => '۰۱۲۳۴۵۶۷۸۹'.indexOf(d));
function mapHeaders(hdr) {
  const idx = {};
  hdr.forEach((h, i) => { const n = normHead(h); if (!n) return;
    for (const [k, ar, alt] of IMPORT_COLS) if (!(k in idx) && [ar, trTo(ar), ...alt.split('|')].some(a => normHead(a) === n)) { idx[k] = i; break; } });
  return idx;
}
function cellDate(v) {
  v = arDigits(String(v == null ? '' : v).trim()); if (!v) return '';
  if (/^\d+(\.\d+)?$/.test(v) && +v > 20000 && +v < 80000) return new Date(Math.round((+v - 25569) * 864e5)).toISOString().slice(0, 10);   // Excel serial date
  let m = v.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})/); if (m) return m[1] + '-' + m[2].padStart(2, '0') + '-' + m[3].padStart(2, '0');
  m = v.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})/); if (m) return m[3] + '-' + m[2].padStart(2, '0') + '-' + m[1].padStart(2, '0');
  return v;
}
function importRow(raw, idx, rowNo) {
  const g = k => idx[k] == null ? '' : arDigits(String(raw[idx[k]] == null ? '' : raw[idx[k]]).trim());
  const num = k => g(k).replace(/[,\s]/g, '').replace(/\.0+$/, '');
  const r = { _row: rowNo, emp_no: num('emp_no'), full_name: g('full_name'), full_name_en: g('full_name_en'), job_title_en: g('job_title_en'), national_id: num('national_id'), job_title: g('job_title'), department: g('department'),
    manager_emp_no: num('manager_emp_no'), hire_date: cellDate(raw[idx.hire_date]), probation_end: cellDate(raw[idx.probation_end]), basic: num('basic'), housing: num('housing'), transport: num('transport'),
    iban: g('iban').replace(/\s/g, '').toUpperCase(), phone: num('phone'), email: g('email') };
  const nat = normHead(g('is_saudi')); r.is_saudi = !nat || /^(سعودي|سعوديه|سعودية|saudi|ksa|نعم|yes|true|1)$/.test(nat) ? 'true' : 'false';
  const gd = normHead(g('gender')); r.gender = /^(انثى|انثي|f|female|امراة)$/.test(gd) ? 'f' : 'm';
  if (/^5\d{8}$/.test(r.phone)) r.phone = '0' + r.phone;
  const errs = [];
  if (!r.emp_no) errs.push('الرقم الوظيفي مطلوب');
  if (r.full_name.length < 3) errs.push('الاسم الكامل مطلوب');
  if (r.national_id && !/^[12]\d{9}$/.test(r.national_id)) errs.push('رقم الهوية/الإقامة 10 أرقام يبدأ بـ 1 أو 2');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(r.hire_date) || isNaN(new Date(r.hire_date))) errs.push('تاريخ المباشرة غير صحيح');
  if (r.probation_end && !/^\d{4}-\d{2}-\d{2}$/.test(r.probation_end)) errs.push('نهاية فترة التجربة غير صحيحة');
  if (!/^\d+(\.\d+)?$/.test(r.basic)) errs.push('الراتب الأساسي رقم مطلوب');
  if ((r.housing && !/^\d+(\.\d+)?$/.test(r.housing)) || (r.transport && !/^\d+(\.\d+)?$/.test(r.transport))) errs.push('البدلات أرقام');
  if (r.iban && !/^SA\d{22}$/.test(r.iban)) errs.push('الآيبان يبدأ بـ SA ويليه 22 رقما');
  if (nat && !/^(سعودي|سعوديه|سعودية|saudi|ksa|نعم|yes|true|1|غير سعودي|غير سعوديه|غير سعودية|non-saudi|non saudi|expat|لا|no|false|0)$/.test(nat)) {
    const c = natCode(g('is_saudi')); if (c === '?') errs.push('الجنسية: سعودي أو غير سعودي أو اسم الدولة'); else { r.nationality = c; r.is_saudi = String(c === 'SA'); } }
  if (gd && !/^(ذكر|m|male|انثى|انثي|f|female|امراة)$/.test(gd)) errs.push('الجنس: ذكر أو أنثى');
  for (const k of ['nationality', ...PROFILE_COLS.map(c => c[0])]) if (idx[k] != null) {
    const [v, er] = profileCell(k, raw[idx[k]]); if (er) errs.push(er); else r[k] = v; }
  if (r.nationality) r.is_saudi = String(r.nationality === 'SA');
  if (r.birth_date && r.hire_date && new Date(r.birth_date) > new Date(new Date(r.hire_date).setFullYear(new Date(r.hire_date).getFullYear() - 15))) errs.push('لا يجوز تشغيل من لم يتم 15 سنة — م162');
  if (r.leave_open_date && !r.leave_open_days) errs.push('أدخل رصيد الإجازة الافتتاحي');
  return { r, errs };
}
async function unzipEntries(buf) {
  const dv = new DataView(buf); let e = buf.byteLength - 22;
  while (e >= 0 && dv.getUint32(e, true) !== 0x06054b50) e--;
  if (e < 0) throw new Error('الملف ليس بصيغة Excel (.xlsx) — احفظه بصيغة xlsx أو CSV');
  const out = {}; let p = dv.getUint32(e + 16, true);
  for (let i = 0, n = dv.getUint16(e + 10, true); i < n; i++) {
    const method = dv.getUint16(p + 10, true), size = dv.getUint32(p + 20, true), nl = dv.getUint16(p + 28, true), xl = dv.getUint16(p + 30, true), cl = dv.getUint16(p + 32, true), lo = dv.getUint32(p + 42, true);
    const name = new TextDecoder().decode(new Uint8Array(buf, p + 46, nl));
    out[name] = { method, data: new Uint8Array(buf, lo + 30 + dv.getUint16(lo + 26, true) + dv.getUint16(lo + 28, true), size) };
    p += 46 + nl + xl + cl;
  }
  return out;
}
async function zipText(z, name) {
  const e = z[name]; if (!e) return null;
  if (e.method === 0) return new TextDecoder().decode(e.data);
  if (typeof DecompressionStream === 'undefined') throw new Error('متصفحك لا يدعم قراءة ملفات Excel — احفظ الملف بصيغة CSV');
  return new Response(new Blob([e.data]).stream().pipeThrough(new DecompressionStream('deflate-raw'))).text();
}
async function readXlsx(buf) {
  const z = await unzipEntries(buf), xml = s => new DOMParser().parseFromString(s, 'application/xml');
  const wb = xml(await zipText(z, 'xl/workbook.xml') || ''), sh = wb.getElementsByTagNameNS('*', 'sheet')[0];
  let path = 'xl/worksheets/sheet1.xml';
  if (sh) { const rid = sh.getAttribute('r:id'), rels = xml(await zipText(z, 'xl/_rels/workbook.xml.rels') || '<x/>');
    const rel = [...rels.getElementsByTagNameNS('*', 'Relationship')].find(r => r.getAttribute('Id') === rid);
    if (rel) { const t = rel.getAttribute('Target'); path = t.startsWith('/') ? t.slice(1) : 'xl/' + t; } }
  const ssx = await zipText(z, 'xl/sharedStrings.xml');
  const ss = ssx ? [...xml(ssx).getElementsByTagNameNS('*', 'si')].map(si => [...si.getElementsByTagNameNS('*', 't')].map(t => t.textContent).join('')) : [];
  const sheet = await zipText(z, path); if (!sheet) throw new Error('تعذّر قراءة الورقة الأولى في الملف');
  const col = ref => { let n = 0; for (const ch of ref.replace(/\d+/g, '')) n = n * 26 + ch.charCodeAt(0) - 64; return n - 1; };
  return [...xml(sheet).getElementsByTagNameNS('*', 'row')].map(row => { const out = [];
    for (const c of row.getElementsByTagNameNS('*', 'c')) { const t = c.getAttribute('t'), v = c.getElementsByTagNameNS('*', 'v')[0];
      out[col(c.getAttribute('r') || 'A')] = t === 's' ? ss[+(v && v.textContent)] : t === 'inlineStr' ? [...c.getElementsByTagNameNS('*', 't')].map(x => x.textContent).join('') : t === 'b' ? (v && v.textContent === '1' ? 'true' : 'false') : v ? v.textContent : ''; }
    return out; });
}
function readCsv(text) {
  text = text.replace(/^﻿/, ''); const first = text.split(/\r?\n/)[0] || '', sep = (first.match(/;/g) || []).length > (first.match(/,/g) || []).length ? ';' : first.includes('\t') && !first.includes(',') ? '\t' : ',';
  const rows = [[]]; let f = '', q = false;
  for (let i = 0; i < text.length; i++) { const ch = text[i];
    if (q) { if (ch === '"') { if (text[i + 1] === '"') { f += '"'; i++; } else q = false; } else f += ch; }
    else if (ch === '"') q = true; else if (ch === sep) { rows[rows.length - 1].push(f); f = ''; }
    else if (ch === '\n' || ch === '\r') { if (ch === '\r' && text[i + 1] === '\n') i++; rows[rows.length - 1].push(f); f = ''; rows.push([]); }
    else f += ch; }
  rows[rows.length - 1].push(f);
  return rows;
}
/* template .xlsx written as an uncompressed zip */
function crc32(b) { let c, t = crc32.t; if (!t) { t = crc32.t = []; for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } }
  c = 0xFFFFFFFF; for (let i = 0; i < b.length; i++) c = t[(c ^ b[i]) & 255] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; }
function zipStore(files) {
  const enc = new TextEncoder(), parts = [], cen = []; let off = 0;
  for (const [name, text] of files) {
    const nb = enc.encode(name), d = enc.encode(text), crc = crc32(d), h = new DataView(new ArrayBuffer(30));
    h.setUint32(0, 0x04034b50, true); h.setUint16(4, 20, true); h.setUint16(6, 0x0800, true); h.setUint32(14, crc, true); h.setUint32(18, d.length, true); h.setUint32(22, d.length, true); h.setUint16(26, nb.length, true);
    parts.push(new Uint8Array(h.buffer), nb, d);
    const c = new DataView(new ArrayBuffer(46)); c.setUint32(0, 0x02014b50, true); c.setUint16(4, 20, true); c.setUint16(6, 20, true); c.setUint16(8, 0x0800, true); c.setUint32(16, crc, true); c.setUint32(20, d.length, true); c.setUint32(24, d.length, true); c.setUint16(28, nb.length, true); c.setUint32(42, off, true);
    cen.push(new Uint8Array(c.buffer), nb); off += 30 + nb.length + d.length;
  }
  const size = cen.reduce((a, x) => a + x.length, 0), e = new DataView(new ArrayBuffer(22));
  e.setUint32(0, 0x06054b50, true); e.setUint16(8, files.length, true); e.setUint16(10, files.length, true); e.setUint32(12, size, true); e.setUint32(16, off, true);
  return new Blob([...parts, ...cen, new Uint8Array(e.buffer)], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
}
function templateXlsx(rows) {
  const x = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const colL = i => (i >= 26 ? String.fromCharCode(64 + Math.floor(i / 26)) : '') + String.fromCharCode(65 + i % 26);
  const sheet = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"${document.documentElement.dir === 'rtl' ? ' rightToLeft="1"' : ''}/></sheetViews><cols><col min="1" max="${rows[0].length}" width="22" customWidth="1"/></cols><sheetData>${rows.map((r, ri) => `<row r="${ri + 1}">${r.map((v, ci) => typeof v === 'number' && ri > 0 ? `<c r="${colL(ci)}${ri + 1}"><v>${v}</v></c>` : `<c r="${colL(ci)}${ri + 1}" t="inlineStr"${ri === 0 ? ' s="1"' : ''}><is><t>${x(v)}</t></is></c>`).join('')}</row>`).join('')}</sheetData></worksheet>`;
  return zipStore([
    ['[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'],
    ['_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'],
    ['xl/workbook.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="employees" sheetId="1" r:id="rId1"/></sheets></workbook>'],
    ['xl/_rels/workbook.xml.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'],
    ['xl/styles.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Arial"/></font><font><b/><sz val="11"/><name val="Arial"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf/><xf fontId="1" applyFont="1"/></cellXfs></styleSheet>'],
    ['xl/worksheets/sheet1.xml', sheet]]);
}
function importDialog() {
  const d = modal('استيراد الموظفين من Excel', `<ol class="small" style="padding-inline-start:18px;margin-top:0"><li>نزّل القالب واملأ سطرا لكل موظف. الأعمدة المطلوبة: الرقم الوظيفي، الاسم الكامل، تاريخ المباشرة، الراتب الأساسي.</li>
      <li>الأقسام غير الموجودة تُنشأ تلقائيا، والمدير المباشر يُكتب برقمه الوظيفي (من الملف أو من الموظفين الحاليين).</li><li>رصيد الإجازة الافتتاحي: رصيد الموظف من الإجازة السنوية كما في نهاية «تاريخ الرصيد الافتتاحي»، وما يُطلب بعده يُخصم منه. مركز التكلفة يُكتب برمزه، وموقع العمل باسمه.</li><li>ارفع الملف (xlsx أو CSV) وراجع المعاينة ثم اضغط استيراد. إذا كان في أي سطر خطأ لا يُستورد شيء.</li></ol>
    <div class="row"><button type="button" class="btn" id="tpl">تنزيل القالب</button><label class="btn pri" style="margin:0;color:var(--prim-ink)">اختيار الملف<input type="file" id="imf" accept=".xlsx,.csv,text/csv" hidden></label></div>
    <div id="imp"></div>`, { wide: true });
  $('#tpl', d).onclick = () => { const a = document.createElement('a');
    const ex = { emp_no: '1001', full_name: 'مثال: سارة أحمد', full_name_en: 'Sara Ahmed', national_id: '1012345678', is_saudi: 'سعودي', gender: 'أنثى', job_title: 'محاسبة', job_title_en: 'Accountant', department: 'المالية', hire_date: today(), basic: '8000', housing: '2000', transport: '800', phone: '0500000000',
      nationality: 'سعودي', birth_date: '1995-03-15', marital_status: 'متزوج', dependents: '2', education: 'بكالوريوس', specialization: 'محاسبة', short_address: 'RRRD2929', leave_open_days: '12.5', leave_open_date: today() };
    a.href = URL.createObjectURL(templateXlsx([IMPORT_COLS.map(c => c[1] + (c[3] ? ' *' : '')), IMPORT_COLS.map(c => ex[c[0]] || '')].map(r => r.map(tr))));
    a.download = 'waad-employees-template.xlsx'; a.click(); };
  $('#imf', d).onchange = async ev => {
    const file = ev.target.files[0]; if (!file) return; const box = $('#imp', d);
    try {
      const buf = await file.arrayBuffer();
      const rows = /\.csv$/i.test(file.name) ? readCsv(new TextDecoder().decode(buf)) : await readXlsx(buf);
      const hi = rows.findIndex(r => r && r.some(v => String(v || '').trim())); if (hi < 0) throw new Error('الملف فارغ');
      const idx = mapHeaders(rows[hi]);
      const miss = IMPORT_COLS.filter(c => c[3] && !(c[0] in idx)).map(c => c[1]);
      if (miss.length) throw new Error('أعمدة مطلوبة غير موجودة: ' + miss.join('، ') + ' — استخدم القالب');
      const items = rows.slice(hi + 1).map((r, i) => r && r.some(v => String(v == null ? '' : v).trim()) ? importRow(r, idx, hi + i + 2) : null).filter(Boolean);
      if (!items.length) throw new Error('لا توجد صفوف موظفين تحت العناوين');
      const nos = {}; items.forEach(x => { if (x.r.emp_no) { if (nos[x.r.emp_no]) x.errs.push('رقم مكرر في الملف'); nos[x.r.emp_no] = 1; } });
      const existing = new Set(Object.values(await employeesMap(true)).map(e => e.emp_no));
      items.forEach(x => { if (existing.has(x.r.emp_no)) x.errs.push('الرقم الوظيفي مسجّل مسبقا'); if (x.r.manager_emp_no && !nos[x.r.manager_emp_no] && !existing.has(x.r.manager_emp_no)) x.errs.push('المدير المباشر غير موجود'); });
      const bad = items.filter(x => x.errs.length);
      box.innerHTML = `<div class="${bad.length ? 'err' : 'note'}">${items.length} موظف في الملف${bad.length ? ` — ${bad.length} سطر فيه أخطاء، صحّحها في الملف ثم ارفعه مجددا` : ' — جاهز للاستيراد'}</div>
        ${tbl([{ t: 'السطر', h: x => x.r._row }, { t: 'الرقم', h: x => esc(x.r.emp_no) }, { t: 'الاسم', h: x => esc(x.r.full_name) }, { t: 'القسم', h: x => esc(x.r.department || '—') }, { t: 'المباشرة', h: x => esc(x.r.hire_date) }, { t: 'الأساسي', r: 1, h: x => money(x.r.basic) }, { t: 'الملاحظات', h: x => x.errs.length ? `<span class="bad">${esc(x.errs.join('، '))}</span>` : '<span class="ok">✓</span>' }], bad.length ? bad.concat(items.filter(x => !x.errs.length)).slice(0, 200) : items.slice(0, 200))}
        ${bad.length ? '' : `<div class="row" style="margin-top:12px"><button type="button" class="btn pri" id="go">استيراد ${items.length} موظف</button></div><div id="ier"></div>`}`;
      if ($('#go', d)) $('#go', d).onclick = async () => { try { await busy($('#go', d), async () => { const n = await db.rpc('import_employees', { p_company: S.cid, p_rows: items.map(x => x.r) }); cache.emps = null; cache.deps = null; d.close(); toast('استُورد ' + n + ' موظف'); route(); }); } catch (er) { showErr($('#ier', d), er); } };
    } catch (er) { showErr(box, er); }
    ev.target.value = '';
  };
}

/* ===== my training (employee) ===== */
async function myTrainingHtml() {
  if (!S.emp) return '';
  const att = await db.get('training_attendees', { employee_id: 'eq.' + S.emp }).catch(() => []);
  if (!att.length) return '';
  const trs = await db.get('trainings', { id: 'in.(' + att.map(a => a.training_id).join(',') + ')' }); const tm = {}; trs.forEach(t => tm[t.id] = t);
  return `<div class="card"><h2>تدريبي</h2>${tbl([{ t: 'الدورة', h: a => esc((tm[a.training_id] || {}).title || '') }, { t: 'التاريخ', h: a => fdate((tm[a.training_id] || {}).start_date) }, { t: 'الحالة', h: a => `<span class="badge ${TA_ST[a.status][1]}">${esc(TA_ST[a.status][0])}</span>` }, { t: 'انتهاء الشهادة', h: a => fdate(a.cert_expiry) }], att)}</div>`;
}
