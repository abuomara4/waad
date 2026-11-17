'use strict';
/* ===== 0108: announcements, surveys, 360 feedback, careers page, expense policies, workforce plan ===== */

/* ----- company announcements ----- */
VIEWS['#/announcements'] = async page => {
  if (!(isHR() || hrCan('hr_ann'))) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للمالك والموارد البشرية.'))}</div>`; return; }
  const [rows, reads, deps, mem] = await Promise.all([db.get('company_announcements', { company_id: 'eq.' + S.cid, order: 'created_at.desc' }),
    db.get('announcement_reads', { company_id: 'eq.' + S.cid, select: 'announcement_id' }).catch(() => []), db.get('departments', { company_id: 'eq.' + S.cid, order: 'name' }).catch(() => []),
    db.get('members', { company_id: 'eq.' + S.cid, select: 'user_id' }).catch(() => [])]);
  const dn = {}; deps.forEach(d => dn[d.id] = d.name);
  const rc = id => reads.filter(r => r.announcement_id === id).length;
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الإعلانات الداخلية'))}</h1><div class="muted">${esc(tr('رسالة واحدة تصل لكل الموظفين في الصفحة الرئيسية وعلى أجهزتهم، بدل مجموعات الواتساب.'))}</div></div>
      <button class="btn pri" id="annn">${esc(tr('+ إعلان'))}</button></div>
    ${tbl([{ t: 'الإعلان', h: a => `<b data-nt>${esc(a.title)}</b>${a.pinned ? ` <span class="badge info">${esc(tr('مثبّت'))}</span>` : ''}<div class="small muted" data-nt>${esc(a.body.slice(0, 90))}${a.body.length > 90 ? '…' : ''}</div>` },
      { t: 'إلى', h: a => esc(a.department_id ? (dn[a.department_id] || '—') : tr('كل الموظفين')) }, { t: 'التاريخ', h: a => fdate(a.created_at) },
      { t: 'اطّلع عليه', r: 1, h: a => `<span class="num">${rc(a.id)}</span> / <span class="num">${mem.length}</span>` }], rows, { empty: 'لا توجد إعلانات بعد', onRow: true })}`;
  bindRows(page, rows, a => form(a)); $('#annn', page).onclick = () => form(null);
  function form(a) {
    const v = a || { pinned: false };
    const m = modal(a ? tr('تعديل الإعلان') : tr('إعلان جديد'), `<div class="fg">${field('العنوان', inp('title', v.title, 'required maxlength="150"'), 'wide')}
      ${field('نص الإعلان', `<textarea name="body" rows="5" maxlength="4000" required>${esc(v.body || '')}</textarea>`, 'wide')}
      ${field('يصل إلى', `<select name="dep"><option value="">${esc(tr('كل الموظفين'))}</option>${deps.map(d => opt(d.id, d.name, v.department_id)).join('')}</select>`)}
      ${field('يختفي بعد (اختياري)', `<input type="date" name="exp" value="${esc(v.expires_on || '')}">`)}
      <label class="row wide" style="gap:8px"><input type="checkbox" name="pin"${v.pinned ? ' checked' : ''}> ${esc(tr('تثبيت أعلى الصفحة الرئيسية'))}</label></div>
      ${a ? `<button type="button" class="btn sm danger" id="annd">${esc(tr('حذف الإعلان'))}</button>` : ''}`, {
      ok: a ? 'حفظ' : 'نشر', onOk: async f => {
        if ((f.title || '').trim().length < 2 || !(f.body || '').trim()) throw new Error('اكتب العنوان والنص');
        const row = { title: f.title.trim(), body: f.body.trim(), department_id: blank(f.dep), expires_on: blank(f.exp), pinned: !!f.pin };
        if (a) await db.upd('company_announcements', { id: 'eq.' + a.id }, row); else await db.ins('company_announcements', Object.assign(row, { company_id: S.cid }));
        toast(tr(a ? 'تم الحفظ' : 'نُشر الإعلان')); route(); } });
    if ($('#annd', m)) $('#annd', m).onclick = async () => { if (!await confirmBox(tr('حذف الإعلان'), tr('يختفي من عند كل الموظفين.'), tr('حذف'))) return; await db.del('company_announcements', { id: 'eq.' + a.id }); route(); };
  }
};
// the home page: unread announcements and surveys waiting for my answer
async function annHome(page) {
  const td = today();
  const [anns, reads, svs, took] = await Promise.all([db.get('company_announcements', { company_id: 'eq.' + S.cid, order: 'pinned.desc,created_at.desc', limit: 10 }).catch(() => []),
    db.get('announcement_reads', { user_id: 'eq.' + S.session.user.id, select: 'announcement_id' }).catch(() => []),
    db.get('surveys', { company_id: 'eq.' + S.cid, status: 'eq.open', select: 'id,title,closes_on' }).catch(() => []),
    db.get('survey_takers', { user_id: 'eq.' + S.session.user.id, select: 'survey_id' }).catch(() => [])]);
  const unread = anns.filter(a => (!a.expires_on || a.expires_on >= td) && (a.pinned || !reads.some(r => r.announcement_id === a.id)));
  const waiting = svs.filter(s => (!s.closes_on || s.closes_on >= td) && !took.some(t => t.survey_id === s.id));
  if (!unread.length && !waiting.length) return;
  const box = document.createElement('div');
  box.innerHTML = unread.map(a => `<div class="card annc" style="margin-bottom:12px;border-inline-start:4px solid var(--gold,#c9a227)"><div class="row" style="justify-content:space-between;gap:8px">
      <b data-nt>📢 ${esc(a.title)}</b><span class="small muted">${fdate(a.created_at)}</span></div><div data-nt style="white-space:pre-wrap;margin:6px 0">${esc(a.body)}</div>
      ${reads.some(r => r.announcement_id === a.id) ? '' : `<button class="btn sm" data-annr="${a.id}">${esc(tr('تم الاطلاع'))}</button>`}</div>`).join('')
    + (waiting.length ? `<a class="note" href="#/surveys" style="display:block;margin-bottom:12px">📝 ${esc(tr('استبيان بانتظار رأيك'))}: <b>${esc(waiting[0].title)}</b>${waiting.length > 1 ? ' +' + (waiting.length - 1) : ''}</a>` : '');
  const head = $('.head', page); if (head) head.after(box); else page.prepend(box);
  $$('[data-annr]', box).forEach(b => b.onclick = async () => { await db.ins('announcement_reads', { announcement_id: b.dataset.annr, company_id: S.cid }).catch(() => {}); b.closest('.annc').remove(); });
}

/* ----- surveys ----- */
const SV_KIND = { enps: 'رضا الموظفين (eNPS)', onboarding: 'استبيان الانضمام', exit: 'استبيان المغادرة', custom: 'استبيان مخصص' };
const SV_TPL = {
  enps: [{ t: 'ما مدى احتمال أن توصي بمنشأتنا كمكان عمل لصديق؟ (0 إلى 10)', type: 'enps' }, { t: 'ما أهم سبب لتقييمك؟', type: 'text' }],
  onboarding: [{ t: 'كانت أيامي الأولى منظمة وواضحة', type: 'scale' }, { t: 'حصلت على الأدوات والصلاحيات التي أحتاجها', type: 'scale' }, { t: 'فهمت مهامي وما هو متوقع مني', type: 'scale' }, { t: 'ما الذي كان سيجعل انضمامك أسهل؟', type: 'text' }],
  exit: [{ t: 'ما السبب الرئيسي لمغادرتك؟', type: 'text' }, { t: 'كانت علاقتي بمديري المباشر جيدة', type: 'scale' }, { t: 'كان الراتب والمزايا مناسبة', type: 'scale' }, { t: 'هل تنصح غيرك بالعمل هنا؟ (0 إلى 10)', type: 'enps' }, { t: 'ما الذي تقترح تحسينه؟', type: 'text' }],
  custom: [] };
VIEWS['#/surveys'] = async page => {
  const hr = isHR() || hrCan('hr_ann');
  const [svs, took] = await Promise.all([db.get('surveys', { company_id: 'eq.' + S.cid, order: 'created_at.desc' }), db.get('survey_takers', { user_id: 'eq.' + S.session.user.id, select: 'survey_id' }).catch(() => [])]);
  const td = today(), open = s => s.status === 'open' && (!s.closes_on || s.closes_on >= td), done = s => took.some(t => t.survey_id === s.id);
  const mine = svs.filter(s => open(s) && !done(s));
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الاستبيانات'))}</h1><div class="muted">${esc(tr('رأيك يهم. الاستبيانات مجهولة الهوية ما لم يُذكر غير ذلك.'))}</div></div>${hr ? `<button class="btn pri" id="svn">${esc(tr('+ استبيان'))}</button>` : ''}</div>
    <h2>${esc(tr('بانتظار رأيك'))}</h2>${tbl([{ t: 'الاستبيان', h: s => `<b>${esc(s.title)}</b>${s.anonymous ? ` <span class="badge">${esc(tr('مجهول الهوية'))}</span>` : ''}` }, { t: 'ينتهي', h: s => s.closes_on ? fdate(s.closes_on) : '—' }], mine, { empty: 'لا توجد استبيانات بانتظارك', onRow: true })}
    ${hr ? `<h2>${esc(tr('كل الاستبيانات'))}</h2>${tbl([{ t: 'الاستبيان', h: s => `<b>${esc(s.title)}</b> <span class="small muted">${esc(tr(SV_KIND[s.kind]))}</span>` }, { t: 'الحالة', h: s => `<span class="badge ${open(s) ? 'ok' : ''}">${esc(tr(open(s) ? 'مفتوح' : 'مغلق'))}</span>` },
      { t: 'التاريخ', h: s => fdate(s.created_at) }], svs, { empty: 'لا توجد استبيانات بعد', onRow: true })}` : ''}`;
  const tbls = $$('.tw', page);
  bindRows(tbls[0], mine, s => answer(s));
  if (hr) { bindRows(tbls[1], svs, s => results(s)); $('#svn', page).onclick = () => create(); }
  function answer(s) {
    const q = s.questions;
    const m = modal(s.title, `${s.anonymous ? `<p class="muted small" style="margin-top:0">${esc(tr('إجاباتك مجهولة الهوية: لا تظهر باسمك، ولا تُعرض النتائج إلا بعد 3 إجابات على الأقل.'))}</p>` : ''}
      <div style="display:grid;gap:14px">${q.map((x, i) => `<div><label><b>${i + 1}.</b> ${esc(x.t)}</label>${x.type === 'text' ? `<textarea name="q${i}" rows="2" maxlength="1000"></textarea>`
        : `<div class="row svsc" style="gap:4px;flex-wrap:wrap">${(x.type === 'enps' ? [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10] : [1, 2, 3, 4, 5]).map(n => `<label class="svb"><input type="radio" name="q${i}" value="${n}"><span class="num">${n}</span></label>`).join('')}</div>
          <div class="small muted">${esc(tr(x.type === 'enps' ? '0 = لا أوصي أبدا · 10 = أوصي بشدة' : '1 = لا أوافق أبدا · 5 = أوافق تماما'))}</div>`}</div>`).join('')}</div>`, {
      ok: 'إرسال', onOk: async f => {
        const ans = q.map((x, i) => x.type === 'text' ? (f['q' + i] || '').trim() : (f['q' + i] === undefined || f['q' + i] === '' ? null : +f['q' + i]));
        if (q.some((x, i) => x.type !== 'text' && ans[i] == null)) throw new Error('أجب على كل الأسئلة المرقمة');
        await db.rpc('survey_submit', { p_survey: s.id, p_answers: ans }); toast(tr('شكرا لك، وصل رأيك')); route(); } });
  }
  function create() {
    const m = modal(tr('استبيان جديد'), `<div class="fg">${field('النوع', `<select name="kind">${Object.entries(SV_KIND).map(([k, t]) => opt(k, tr(t), 'enps')).join('')}</select>`)}
      ${field('العنوان', inp('title', tr(SV_KIND.enps), 'required maxlength="150"'))}
      ${field('الأسئلة (سؤال لكل سطر)', `<textarea name="qs" rows="6"></textarea>`, 'wide')}
      <p class="wide muted small" style="margin:0">${esc(tr('في الاستبيان المخصص: كل سطر سؤال تقييم من 1 إلى 5، والسطر الذي يبدأ بـ «نص:» سؤال مفتوح.'))}</p>
      ${field('ينتهي في (اختياري)', '<input type="date" name="closes">')}<label class="row" style="gap:8px"><input type="checkbox" name="anon" checked> ${esc(tr('مجهول الهوية'))}</label></div>`, {
      ok: 'نشر', onOk: async f => {
        const qs = f.kind === 'custom' ? (f.qs || '').split('\n').map(x => x.trim()).filter(Boolean).map(x => /^نص:/.test(x) ? { t: x.replace(/^نص:\s*/, ''), type: 'text' } : { t: x, type: 'scale' }) : SV_TPL[f.kind];
        if (!qs.length) throw new Error('أضف سؤالا واحدا على الأقل');
        await db.ins('surveys', { company_id: S.cid, title: (f.title || '').trim() || tr(SV_KIND[f.kind]), kind: f.kind, questions: qs, anonymous: !!f.anon, closes_on: blank(f.closes) });
        toast(tr('نُشر الاستبيان')); route(); } });
    const sync = () => { const k = $('select[name=kind]', m).value; $('textarea[name=qs]', m).closest('div').hidden = k !== 'custom'; $('input[name=title]', m).value = tr(SV_KIND[k]); };
    $('select[name=kind]', m).onchange = sync; sync();
  }
  async function results(s) {
    const r = await db.rpc('survey_results', { p_survey: s.id });
    const ans = r.answers || [];
    const block = (x, i) => { const vals = ans.map(a => a[i]).filter(v => v !== null && v !== '' && v !== undefined);
      if (x.type === 'text') return `<div class="card"><b>${esc(x.t)}</b>${vals.length ? `<ul class="small">${vals.map(v => `<li>${esc(v)}</li>`).join('')}</ul>` : `<p class="muted small">${esc(tr('لا توجد إجابات'))}</p>`}</div>`;
      if (x.type === 'enps') { const n = vals.length, p = vals.filter(v => v >= 9).length, d = vals.filter(v => v <= 6).length, sc = n ? Math.round((p - d) / n * 100) : 0;
        return `<div class="card"><b>${esc(x.t)}</b><div class="grid" style="margin-top:8px"><div class="card kpi"><div class="muted small">eNPS</div><div class="v num ${sc < 0 ? 'bad' : ''}">${sc}</div></div>
          <div class="card kpi"><div class="muted small">${esc(tr('مروّجون (9–10)'))}</div><div class="v num">${n ? Math.round(p / n * 100) : 0}%</div></div><div class="card kpi"><div class="muted small">${esc(tr('منتقدون (0–6)'))}</div><div class="v num">${n ? Math.round(d / n * 100) : 0}%</div></div></div></div>`; }
      const avg = vals.length ? vals.reduce((a, v) => a + v, 0) / vals.length : 0;
      return `<div class="card"><b>${esc(x.t)}</b><div class="row" style="gap:8px;align-items:center;margin-top:6px"><div style="flex:1;height:10px;background:var(--line);border-radius:5px"><div style="width:${avg / 5 * 100}%;height:10px;border-radius:5px;background:#217FE1"></div></div><span class="num">${avg.toFixed(2)} / 5</span></div></div>`; };
    const m = modal(s.title, `<p class="muted small" style="margin-top:0">${esc(tr('عدد الإجابات'))}: <b class="num">${r.n}</b>${s.anonymous ? ' · ' + esc(tr('مجهول الهوية')) : ''}</p>
      ${r.hidden ? `<div class="note">${esc(tr('تظهر النتائج بعد 3 إجابات على الأقل حفاظا على سرية المشاركين.'))}</div>` : s.questions.map(block).join('')}
      ${s.status === 'open' ? `<button type="button" class="btn sm" id="svc">${esc(tr('إغلاق الاستبيان'))}</button>` : ''}`, { wide: true });
    if ($('#svc', m)) $('#svc', m).onclick = async () => { await db.upd('surveys', { id: 'eq.' + s.id }, { status: 'closed' }); $('#dlg').close(); route(); };
  }
};

/* ----- 360 feedback (used from talent.js) ----- */
const FB_C = [['c1', 'التعاون وروح الفريق'], ['c2', 'التواصل'], ['c3', 'جودة العمل'], ['c4', 'المبادرة وحل المشكلات'], ['c5', 'الالتزام والانضباط']];
const FB_KIND = { self: 'التقييم الذاتي', peer: 'الزملاء', report: 'الفريق (من يرفعون له)' };
function feedbackAsk(cycleId, emp, em) {
  const others = Object.values(em).filter(e => e.id !== emp.id && (!e.end_date || e.end_date >= today())).sort((a, b) => String(a.full_name).localeCompare(String(b.full_name)));
  modal(tr('تقييم 360') + ' — ' + emp.full_name, `<p class="small" style="margin-top:0">${esc(tr('يُطلب من الموظف تقييم نفسه، ومن الزملاء الذين تختارهم. آراء الزملاء لا تظهر بأسمائهم، ولا تُعرض إلا من رأيين فأكثر.'))}</p>
    <div style="max-height:280px;overflow:auto;display:grid;gap:4px">${others.map(e => `<label class="row" style="gap:8px"><input type="checkbox" data-fr="${e.id}"${e.manager_id === emp.manager_id && emp.manager_id ? '' : ''}> ${esc(e.full_name)} <span class="small muted">${esc(e.job_title || '')}</span></label>`).join('')}</div>`, {
    ok: 'إرسال الطلب', onOk: async () => { const ids = $$('[data-fr]').filter(x => x.checked).map(x => x.dataset.fr);
      const n = await db.rpc('feedback_request', { p_cycle: cycleId, p_employee: emp.id, p_raters: ids }); toast(tr('أُرسلت طلبات التقييم') + ': ' + n); } });
}
async function feedbackMine(page, em) {
  if (!S.emp) return;
  const rows = await db.get('review_feedback', { rater_id: 'eq.' + S.emp, submitted_at: 'is.null' }).catch(() => []);
  if (!rows.length) return;
  const box = document.createElement('div');
  box.innerHTML = `<h2>${esc(tr('مطلوب رأيك (تقييم 360)'))}</h2>${tbl([{ t: 'الموظف', h: f => f.kind === 'self' ? esc(tr('أنت (التقييم الذاتي)')) : esc((em[f.employee_id] || {}).full_name || '—') }, { t: 'النوع', h: f => esc(tr(FB_KIND[f.kind])) }], rows, { onRow: true })}`;
  const head = $('.head', page); if (head) head.after(box); else page.prepend(box);
  bindRows(box, rows, f => modal(tr('تقييم 360'), `<p class="muted small" style="margin-top:0">${esc(f.kind === 'self' ? tr('قيّم نفسك بصدق.') : tr('رأيك لا يظهر باسمك.'))}</p>
    <div style="display:grid;gap:10px">${FB_C.map(([k, t]) => `<div><label>${esc(tr(t))}</label><div class="row" style="gap:4px">${[1, 2, 3, 4, 5].map(n => `<label class="svb"><input type="radio" name="${k}" value="${n}"><span class="num">${n}</span></label>`).join('')}</div></div>`).join('')}
    ${field('ملاحظة (اختياري)', '<textarea name="cm" rows="2" maxlength="2000"></textarea>')}</div>`, {
    ok: 'إرسال', onOk: async v => { const sc = {}; FB_C.forEach(([k]) => sc[k] = +v[k] || 0);
      await db.rpc('feedback_submit', { p_id: f.id, p_scores: sc, p_comment: blank(v.cm) }); toast(tr('شكرا لك')); route(); } }));
}
async function feedbackBox(cycleId, empId) {
  const s = await db.rpc('feedback_summary', { p_cycle: cycleId, p_employee: empId }).catch(() => null);
  if (!s || !Object.keys(s).length) return '';
  const row = (k) => { const g = s[k]; if (!g) return ''; return `<tr><td>${esc(tr(FB_KIND[k]))} <span class="small muted num">${g.done}/${g.asked}</span></td>${FB_C.map(([c]) => `<td class="r num">${g.avg && g.avg[c] != null ? g.avg[c] : '—'}</td>`).join('')}</tr>`; };
  const comments = ['peer', 'report'].flatMap(k => (s[k] && s[k].comments) || []);
  return `<div class="card" style="margin-top:12px"><b>${esc(tr('تقييم 360'))}</b><div class="tw"><table><thead><tr><th></th>${FB_C.map(([, t]) => `<th class="r small">${esc(tr(t))}</th>`).join('')}</tr></thead><tbody>${['self', 'peer', 'report'].map(row).join('')}</tbody></table></div>
    ${comments.length ? `<ul class="small">${comments.map(c => `<li>${esc(c)}</li>`).join('')}</ul>` : ''}<p class="muted small">${esc(tr('متوسط الزملاء والفريق يظهر من رأيين فأكثر، وبدون أسماء.'))}</p></div>`;
}

/* ----- careers: the public page (no sign-in) and the HR link ----- */
const careersToken = () => (location.hash.match(/^#\/careers\/([0-9a-f]{32})/) || [])[1] || null;
async function careersView(token) {
  document.title = tr('الوظائف') + ' — ' + tr('وعد');
  $('#app').innerHTML = `<div class="portal"><div class="muted">${esc(tr('جاري التحميل…'))}</div></div>`;
  let d = null; try { d = await db.rpc('careers_view', { p_token: token }); } catch (e) { d = null; }
  const box = $('.portal');
  if (!d) { box.innerHTML = `<div class="card"><h2>${esc(tr('الرابط غير صالح'))}</h2></div>`; return; }
  const co = (LANG === 'en' && d.company_en) || d.company, title = j => (LANG === 'en' && j.title_en) || j.title;
  box.innerHTML = `<div class="phead">${d.logo ? `<img src="${esc(d.logo)}" alt="" class="plogo">` : ''}<div><h1>${esc(co)}</h1><div class="small muted">${esc(tr('الوظائف المتاحة'))}${d.city ? ' · ' + esc(d.city) : ''}</div></div>
      <div class="sp"></div><button class="btn sm" id="plg">${LANG === 'en' ? 'العربية' : 'English'}</button></div>
    ${d.jobs.length ? d.jobs.map(j => `<div class="card"><h2 style="margin:0 0 4px">${esc(title(j))}</h2><div class="small muted">${[j.dept, j.positions > 1 ? j.positions + ' ' + tr('شواغر') : ''].filter(Boolean).map(esc).join(' · ')}</div>
      ${j.description ? `<p style="white-space:pre-wrap">${esc(j.description)}</p>` : ''}${j.requirements ? `<p style="white-space:pre-wrap"><b>${esc(tr('المتطلبات'))}:</b> ${esc(j.requirements)}</p>` : ''}
      <button class="btn pri" data-apply="${j.id}">${esc(tr('قدّم الآن'))}</button></div>`).join('') : `<div class="card"><p>${esc(tr('لا توجد وظائف متاحة حاليا.'))}</p></div>`}
    <p class="small muted" style="text-align:center">${esc(tr('نظام وعد'))}</p>`;
  $('#plg').onclick = () => { setLang(LANG === 'en' ? 'ar' : 'en'); careersView(token); };
  $$('[data-apply]', box).forEach(b => b.onclick = () => { const j = d.jobs.find(x => x.id === b.dataset.apply);
    const m = modal(tr('التقديم على وظيفة') + ': ' + title(j), `<div class="fg">${field('الاسم الكامل', inp('name', '', 'required maxlength="120"'), 'wide')}${field('الجوال', inp('phone', '', 'required dir="ltr" placeholder="05XXXXXXXX"'))}
      ${field('البريد الإلكتروني', inp('email', '', 'type="email" dir="ltr"'))}${field('نبذة عنك (اختياري)', '<textarea name="note" rows="3" maxlength="1500"></textarea>', 'wide')}
      <div class="wide"><label>${esc(tr('السيرة الذاتية (PDF أو Word أو صورة، حتى 3 ميجابايت)'))}</label><input type="file" id="cvup" accept=".pdf,.doc,.docx,image/*"></div></div>
      <p class="muted small">${esc(tr('تُرسل بياناتك إلى المنشأة لغرض التوظيف فقط.'))}</p>`, {
      ok: 'إرسال الطلب', onOk: async f => { const file = $('#cvup', m).files[0];
        if (file && file.size > 3 * 1024 * 1024) throw new Error('حجم الملف أكبر من 3 ميجابايت');
        await db.rpc('careers_apply', { p_token: token, p_opening: j.id, p_name: f.name, p_phone: f.phone, p_email: blank(f.email), p_note: blank(f.note),
          p_file_name: file ? file.name : null, p_mime: file ? file.type : null, p_data: file ? await blobB64(file) : null });
        setTimeout(() => modal(tr('وصل طلبك'), `<p>${esc(tr('شكرا لك. وصل طلبك إلى المنشأة، وسيتواصلون معك إذا تأهلت للمرحلة التالية.'))}</p>`, { ok: 'تم' }), 0); } }); });
}
async function careersLinkDialog() {
  const tok = await db.rpc('careers_link_get', { p_company: S.cid }), url = location.origin + location.pathname + '#/careers/' + tok;
  const m = modal(tr('صفحة الوظائف'), `<p class="small" style="margin-top:0">${esc(tr('رابط عام لمنشأتك يعرض الوظائف التي فعّلت لها «تظهر في صفحة الوظائف». انشره في موقعك أو حساباتك، والمتقدمون يصلون مباشرة إلى قائمة المرشحين.'))}</p>
    <input id="curl" readonly dir="ltr" value="${esc(url)}"><div class="row" style="gap:8px;margin-top:10px;flex-wrap:wrap"><button type="button" class="btn" id="ccp">${esc(tr('نسخ الرابط'))}</button>
    <a class="btn" href="${esc(url)}" target="_blank" rel="noopener">${esc(tr('معاينة'))}</a><button type="button" class="btn sm" id="cnew">${esc(tr('رابط جديد (يلغي القديم)'))}</button></div>`, { ok: 'تم' });
  $('#ccp', m).onclick = () => { navigator.clipboard && navigator.clipboard.writeText(url); toast(tr('نُسخ الرابط')); };
  $('#cnew', m).onclick = async () => { await db.rpc('careers_link_get', { p_company: S.cid, p_new: true }); $('#dlg').close(); careersLinkDialog(); };
}
// the interview invitation, ready to send
function interviewInvite(c, o) {
  if (!c.interview_at) return toast(tr('حدد موعد المقابلة أولا'));
  const dt = new Date(c.interview_at), d = dt.toLocaleDateString(LANG === 'en' ? 'en-GB' : 'ar-SA-u-ca-gregory', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' }), t = dt.toLocaleTimeString(LANG === 'en' ? 'en-GB' : 'ar-SA', { hour: '2-digit', minute: '2-digit' });
  const where = c.interview_link ? tr('رابط المقابلة') + ': ' + c.interview_link : c.interview_place ? tr('المكان') + ': ' + c.interview_place : '';
  const msg = `${tr('السلام عليكم')} ${c.full_name}${tr('،')}\n${tr('يسرّنا دعوتك لمقابلة وظيفة')} «${o.title}» ${tr('في')} ${S.company.name}.\n${tr('الموعد')}: ${d} ${tr('الساعة')} ${t}\n${where}\n${tr('نرجو تأكيد حضورك بالرد على هذه الرسالة.')}`;
  const m = modal(tr('دعوة المقابلة'), `<textarea id="ivm" rows="8" style="width:100%">${esc(msg)}</textarea><div class="row" style="gap:8px;margin-top:10px;flex-wrap:wrap">
    <button type="button" class="btn" id="ivc">${esc(tr('نسخ'))}</button>${c.phone ? waBtn(c.phone, msg, tr('إرسال واتساب'), 'btn wa') : ''}
    ${c.email ? `<a class="btn" href="mailto:${esc(c.email)}?subject=${encodeURIComponent(tr('دعوة مقابلة') + ' — ' + o.title)}&body=${encodeURIComponent(msg)}">${esc(tr('إرسال بالبريد'))}</a>` : ''}</div>`, { ok: 'تم' });
  $('#ivc', m).onclick = () => { navigator.clipboard && navigator.clipboard.writeText($('#ivm', m).value); toast(tr('نُسخ')); };
}

/* ----- expense policies ----- */
VIEWS['#/expensepolicy'] = async page => {
  if (!has('owner', 'admin', 'hr', 'finance')) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للإدارة والمالية.'))}</div>`; return; }
  const rows = await db.get('expense_policies', { company_id: 'eq.' + S.cid, order: 'category' });
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('سياسات المصروفات'))}</h1><div class="muted">${esc(tr('حد لكل فئة مطالبة: حد للمطالبة الواحدة وحد شهري. المعتمد يرى تنبيها عند التجاوز أو تكرار المطالبة أو الإيصال.'))}</div></div>
      <button class="btn pri" id="epn">${esc(tr('+ فئة'))}</button></div>
    ${tbl([{ t: 'الفئة', h: p => `<b>${esc(p.category)}</b>` }, { t: 'حد المطالبة', r: 1, h: p => p.per_claim == null ? '—' : money(p.per_claim) }, { t: 'الحد الشهري', r: 1, h: p => p.monthly == null ? '—' : money(p.monthly) },
      { t: 'عند التجاوز', h: p => `<span class="badge ${p.hard ? 'bad' : 'wait'}">${esc(tr(p.hard ? 'تُمنع المطالبة' : 'تنبيه للمعتمد'))}</span>` }], rows, { empty: 'لا توجد فئات بعد', onRow: true })}`;
  bindRows(page, rows, p => form(p)); $('#epn', page).onclick = () => form(null);
  function form(p) {
    const v = p || { hard: false };
    const m = modal(p ? tr('تعديل الفئة') : tr('فئة جديدة'), `<div class="fg">${field('الفئة', inp('cat', v.category, `required maxlength="60" ${p ? 'readonly' : ''} placeholder="${esc(tr('مثل: وقود، ضيافة، تنقلات'))}"`), 'wide')}
      ${field('حد المطالبة الواحدة', inp('pc', v.per_claim, 'type="number" min="0" step="0.01"'))}${field('الحد الشهري للموظف', inp('mo', v.monthly, 'type="number" min="0" step="0.01"'))}
      <label class="row wide" style="gap:8px"><input type="checkbox" name="hard"${v.hard ? ' checked' : ''}> ${esc(tr('امنع المطالبة إذا تجاوزت حد المطالبة الواحدة'))}</label></div>
      ${p ? `<button type="button" class="btn sm danger" id="epd">${esc(tr('حذف الفئة'))}</button>` : ''}`, {
      onOk: async f => { if ((f.cat || '').trim().length < 2) throw new Error('اكتب اسم الفئة');
        const row = { per_claim: f.pc ? +f.pc : null, monthly: f.mo ? +f.mo : null, hard: !!f.hard };
        if (p) await db.upd('expense_policies', { company_id: 'eq.' + S.cid, category: 'eq.' + p.category }, row); else await db.ins('expense_policies', Object.assign(row, { company_id: S.cid, category: f.cat.trim() }));
        toast(tr('تم الحفظ')); route(); } });
    if ($('#epd', m)) $('#epd', m).onclick = async () => { await db.del('expense_policies', { company_id: 'eq.' + S.cid, category: 'eq.' + p.category }); $('#dlg').close(); route(); };
  }
};
async function expenseInfo(r, decide) {
  const cat = (r.payload || {}).cat, flags = decide || isHR() || has('finance') ? await db.rpc('expense_flags', { p_request: r.id }).catch(() => []) : [];
  return `${cat ? `<p class="small">${esc(tr('فئة المصروف'))}: <b>${esc(cat)}</b></p>` : ''}${flags.length ? `<div class="note" style="border-color:var(--bad)">⚠️ ${flags.map(x => esc(tr(x))).join('<br>⚠️ ')}</div>` : ''}`;
}

/* ----- workforce plan ----- */
const HC_ST = { submitted: ['بانتظار الموارد البشرية', 'wait'], hr_ok: ['بانتظار المالية', 'info'], approved: ['معتمد', 'ok'], rejected: ['مرفوض', 'bad'], hired: ['تحوّل إلى وظيفة شاغرة', 'ok'] };
VIEWS['#/workforce'] = async page => {
  const y0 = +(LS.get('waad.hcy') || new Date().getFullYear() + 1);
  const [rows, deps] = await Promise.all([db.get('headcount_plans', { company_id: 'eq.' + S.cid, year: 'eq.' + y0, order: 'created_at.desc' }).catch(() => []), db.get('departments', { company_id: 'eq.' + S.cid, order: 'name' }).catch(() => [])]);
  const dn = {}; deps.forEach(d => dn[d.id] = d.name);
  const months = h => 13 - (h.start_month || 1), annual = h => n0(h.monthly_cost) * h.positions * months(h);
  const live = rows.filter(h => h.status !== 'rejected'), ok = rows.filter(h => h.status === 'approved' || h.status === 'hired');
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('خطة القوى العاملة'))}</h1><div class="muted">${esc(tr('مدراء الأقسام يطلبون الوظائف بتكلفتها، فتعتمدها الموارد البشرية ثم المالية، وتتحول المعتمدة إلى وظيفة شاغرة.'))}</div></div>
      <div class="row" style="gap:6px"><select id="hcy" style="width:auto">${[0, 1, 2].map(i => new Date().getFullYear() + i).map(y => opt(y, y, y0)).join('')}</select><button class="btn pri" id="hcn">${esc(tr('+ طلب وظيفة'))}</button></div></div>
    <div class="grid" style="margin-bottom:14px"><div class="card kpi"><div class="muted small">${esc(tr('الوظائف المطلوبة'))}</div><div class="v num">${live.reduce((a, h) => a + h.positions, 0)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('المعتمدة'))}</div><div class="v num">${ok.reduce((a, h) => a + h.positions, 0)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('تكلفة المعتمد في السنة'))}</div><div class="v num">${money(ok.reduce((a, h) => a + annual(h), 0))}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('تكلفة كل المطلوب'))}</div><div class="v num">${money(live.reduce((a, h) => a + annual(h), 0))}</div></div></div>
    ${tbl([{ t: 'الوظيفة', h: h => `<b>${esc(h.title)}</b> <span class="small muted">× <span class="num">${h.positions}</span></span><div class="small muted">${esc(dn[h.department_id] || '')}</div>` },
      { t: 'من شهر', h: h => `<span class="num">${h.start_month || 1}</span>` }, { t: 'التكلفة الشهرية للفرد', r: 1, h: h => money(h.monthly_cost) }, { t: 'تكلفة السنة', r: 1, h: h => money(annual(h)) },
      { t: 'الحالة', h: h => `<span class="badge ${HC_ST[h.status][1]}">${esc(tr(HC_ST[h.status][0]))}</span>` }], rows, { empty: 'لا توجد طلبات لهذه السنة', onRow: true })}`;
  $('#hcy', page).onchange = e => { LS.set('waad.hcy', e.target.value); route(); };
  $('#hcn', page).onclick = () => modal(tr('طلب وظيفة'), `<div class="fg">${field('المسمى الوظيفي', inp('title', '', 'required maxlength="120"'))}${field('العدد', inp('pos', 1, 'type="number" min="1" max="500"'))}
    ${field('القسم', `<select name="dep"><option value="">—</option>${deps.map(d => opt(d.id, d.name, (S.myEmp || {}).department_id)).join('')}</select>`)}${field('من شهر', `<select name="sm">${[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].map(n => opt(n, n, 1)).join('')}</select>`)}
    ${field('التكلفة الشهرية للفرد (الراتب والبدلات والتأمينات)', inp('cost', '', 'type="number" min="0" step="0.01" required'), 'wide')}${field('السبب', '<textarea name="reason" rows="2" maxlength="1000"></textarea>', 'wide')}</div>`, {
    ok: 'إرسال', onOk: async f => { if (!(+f.cost >= 0) || f.cost === '') throw new Error('أدخل التكلفة الشهرية');
      await db.rpc('headcount_submit', { p_company: S.cid, p_year: y0, p_dept: blank(f.dep), p_title: f.title, p_positions: +f.pos || 1, p_cost: +f.cost, p_start: +f.sm, p_reason: blank(f.reason) }); toast(tr('أُرسل الطلب')); route(); } });
  bindRows(page, rows, h => {
    const m = modal(h.title, `<p><span class="badge ${HC_ST[h.status][1]}">${esc(tr(HC_ST[h.status][0]))}</span> · <span class="num">${h.positions}</span> × ${money(h.monthly_cost)} · ${esc(tr('تكلفة السنة'))} <b>${money(annual(h))}</b></p>
      ${h.reason ? `<p>${esc(h.reason)}</p>` : ''}${h.note ? `<p class="small muted">${esc(tr('ملاحظة'))}: ${esc(h.note)}</p>` : ''}
      ${['submitted', 'hr_ok'].includes(h.status) ? field('ملاحظة (إلزامية عند الرفض)', '<textarea name="note" rows="2"></textarea>') : ''}
      <div class="row" style="gap:6px;margin-top:8px;flex-wrap:wrap">${['submitted', 'hr_ok'].includes(h.status) ? `<button type="button" class="btn pri" id="hca">${esc(tr('اعتماد'))}</button><button type="button" class="btn danger" id="hcr">${esc(tr('رفض'))}</button>` : ''}
      ${h.status === 'approved' && isHR() ? `<button type="button" class="btn pri" id="hco">${esc(tr('فتح وظيفة شاغرة'))}</button>` : ''}${h.opening_id ? `<a class="btn" href="#/recruit/${h.opening_id}">${esc(tr('الوظيفة الشاغرة'))}</a>` : ''}</div>`, {});
    const decide = ok => async () => { try { await db.rpc('headcount_decide', { p_id: h.id, p_ok: ok, p_note: blank($('textarea[name=note]', m) && $('textarea[name=note]', m).value) }); $('#dlg').close(); toast(tr('تم الحفظ')); route(); } catch (er) { toast(er.message); } };
    if ($('#hca', m)) { $('#hca', m).onclick = decide(true); $('#hcr', m).onclick = decide(false); }
    if ($('#hco', m)) $('#hco', m).onclick = async () => { const id = await db.rpc('headcount_open', { p_id: h.id }); $('#dlg').close(); location.hash = '#/recruit/' + id; };
  });
};
