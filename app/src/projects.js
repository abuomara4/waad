'use strict';
/* ===== Projects (0058, phase one 0123): project file with its own cost center, milestones (WBS weights), Kanban and Gantt,
   timesheets with approval, hours → sales invoice, labor cost from wage + GOSI, materials from stock, profitability. Module: 'proj'. ===== */

const PRJ_STATUS = { active: 'جارٍ', on_hold: 'متوقف مؤقتا', done: 'منتهٍ', cancelled: 'ملغى' };
const PRJ_BILLING = { fixed: 'مقطوعية (سعر ثابت)', hourly: 'زمن ومواد (بالساعة)', internal: 'داخلي (غير مفوتر)' };
const TASK_STATUS = { todo: 'لم تبدأ', doing: 'جارية', done: 'منجزة' };
const TS_STATUS = { submitted: ['بانتظار الاعتماد', 'wait'], approved: ['معتمدة', 'ok'], rejected: ['مرفوضة', 'bad'] };
const prjBadge = s => `<span class="badge ${s === 'active' ? 'ok' : s === 'cancelled' ? 'bad' : s === 'on_hold' ? 'wait' : 'info'}">${esc(tr(PRJ_STATUS[s] || s))}</span>`;
const taskBadge = s => `<span class="badge ${s === 'done' ? 'ok' : s === 'doing' ? 'info' : 'wait'}">${esc(tr(TASK_STATUS[s] || s))}</span>`;
const prjPct = v => v == null ? '—' : `<span class="num">${(+v).toFixed(0)}%</span>`;
// actual vs planned progress as two thin bars
const progBar = pg => { const a = n0(pg && pg.actual), p = pg && pg.planned;
  return `<div title="${esc(tr('الفعلي'))} ${a}% · ${esc(tr('المخطط'))} ${p == null ? '—' : p + '%'}" style="min-width:110px"><div style="height:7px;border-radius:4px;background:var(--line3);overflow:hidden"><div style="height:100%;width:${Math.min(a, 100)}%;background:${p != null && a + 10 < p ? 'var(--bad)' : 'var(--ok,#16a34a)'}"></div></div>
    ${p == null ? '' : `<div style="height:3px;border-radius:2px;background:var(--line3);margin-top:2px;overflow:hidden"><div style="height:100%;width:${Math.min(p, 100)}%;background:var(--muted)"></div></div>`}<div class="small muted num">${a}%${p == null ? '' : ' / ' + p + '%'}</div></div>`; };
const prjFlags = (r, p) => { const f = [], a = n0(r.progress && r.progress.actual), pl = r.progress && r.progress.planned;
  if (pl != null && a + 10 < pl) f.push(`<span class="badge bad">${esc(tr('متأخر عن الخطة'))}</span>`);
  const cost = n0(r.cost) + n0(r.unposted_labor);
  if (n0(r.cost_budget) > 0 && cost > n0(r.cost_budget) * Math.max(a, 1) / 100 + 0.01 && a < 100 && cost > 0) f.push(`<span class="badge wait">${esc(tr('التكلفة أسرع من الإنجاز'))}</span>`);
  if (n0(r.cost_budget) > 0 && cost > n0(r.cost_budget)) f.push(`<span class="badge bad">${esc(tr('تجاوز موازنة التكلفة'))}</span>`);
  return f.join(' '); };

VIEWS['#/projects'] = async (page, arg) => {
  if (!has('owner', 'admin', 'finance', 'hr') && !can('proj')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  if (arg) return projectView(page, arg);
  const [projs, pnl, em] = await Promise.all([db.get('projects', Object.assign(C(), { order: 'created_at.desc', limit: 500 })), db.rpc('project_pnl', { p_company: S.cid }).catch(() => []), employeesMap(true)]);
  const rm = {}; pnl.forEach(r => rm[r.project_id] = r);
  const act = projs.filter(p => p.status === 'active'), sum = k => act.reduce((a, p) => a + n0((rm[p.id] || {})[k]), 0);
  const nm = e => e ? ((LANG === 'en' && e.full_name_en) || e.full_name) : '—';
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('المشاريع'))}</h1><div class="muted small">${esc(tr('ملف كل مشروع ومراحله ومهامه وساعات فريقه وتكلفته وربحيته من الدفاتر'))}</div></div>
      <div class="row"><a class="btn" href="#/mytime">${esc(tr('ساعات عملي'))}</a><button class="btn pri" id="nprj">${esc(tr('مشروع جديد'))}</button></div></div>
    <div class="grid" style="margin-bottom:14px">
      <div class="card kpi"><div class="muted small">${esc(tr('مشاريع جارية'))}</div><div class="v num">${act.length} <span class="small muted">/ ${projs.length}</span></div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('قيمة العقود الجارية'))}</div><div class="v num">${money(sum('contract'))}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('المفوتر'))}</div><div class="v num">${money(sum('invoiced'))}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('التكلفة الفعلية'))}</div><div class="v num">${money(sum('cost') + sum('unposted_labor'))}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('الهامش المتوقع'))}</div><div class="v num ${sum('margin') < 0 ? 'bad' : 'ok'}">${money(sum('margin'))}</div></div></div>
    ${tbl([{ t: 'الرقم', h: p => `<span class="num">${esc(p.no)}</span>` }, { t: 'المشروع', h: p => `<b>${esc(p.name)}</b><div class="small muted">${esc(nm(em[p.manager_id]))}${p.location ? ' · ' + esc(p.location) : ''}</div>` },
      { t: 'الحالة', h: p => prjBadge(p.status) + ' ' + prjFlags(rm[p.id] || {}, p) }, { t: 'الإنجاز', h: p => progBar((rm[p.id] || {}).progress) },
      { t: 'العقد', r: 1, h: p => money((rm[p.id] || {}).contract) }, { t: 'التكلفة', r: 1, h: p => money(n0((rm[p.id] || {}).cost) + n0((rm[p.id] || {}).unposted_labor)) },
      { t: 'الهامش المتوقع', r: 1, h: p => { const m = (rm[p.id] || {}).margin; return m == null ? '—' : `<span class="num ${n0(m) < 0 ? 'bad' : ''}">${money(m)}</span>`; } }],
      projs, { empty: 'لا توجد مشاريع بعد — ابدأ بمشروع جديد', onRow: true })}`;
  $('#nprj', page).onclick = () => projectForm(null);
  bindRows(page, projs, p => location.hash = '#/projects/' + p.id);
};

async function projectForm(p) {
  const [parties, em] = await Promise.all([db.get('parties', Object.assign(C(), { kind: 'eq.customer', select: 'id,name' })).catch(() => []), employeesMap(true)]);
  const v = p || { billing: 'fixed', status: 'active' };
  const emps = Object.values(em).filter(e => !e.end_date || e.end_date >= today() || e.id === v.manager_id).sort((a, b) => String(a.emp_no).localeCompare(String(b.emp_no)));
  modal(p ? tr('تعديل المشروع') : tr('مشروع جديد'), `<div class="fg">
    ${field('اسم المشروع', inp('name', v.name, 'required maxlength="150"'), 'wide')}
    ${field('العميل', `<select name="party_id"><option value="">${esc(tr('— بلا عميل —'))}</option>${parties.map(x => opt(x.id, x.name, v.party_id)).join('')}</select>`)}
    ${field('نوع العقد', `<select name="billing">${Object.entries(PRJ_BILLING).map(([k, t]) => opt(k, tr(t), v.billing)).join('')}</select>`)}
    ${field('قيمة العقد', inp('contract_value', v.contract_value, 'type="number" step="0.01" min="0"'))}
    ${field('سعر الساعة (للعقد بالساعة)', inp('hourly_rate', v.hourly_rate, 'type="number" step="0.01" min="0"'))}
    ${field('موازنة التكلفة', inp('cost_budget', v.cost_budget, 'type="number" step="0.01" min="0"'))}
    ${field('مدير المشروع', `<select name="manager_id"><option value="">—</option>${emps.map(e => opt(e.id, ((LANG === 'en' && e.full_name_en) || e.full_name) + ' (' + e.emp_no + ')', v.manager_id)).join('')}</select>`)}
    ${field('الموقع', inp('location', v.location, 'maxlength="200"'))}
    ${field('الحالة', `<select name="status">${Object.entries(PRJ_STATUS).map(([k, t]) => opt(k, tr(t), v.status)).join('')}</select>`)}
    ${field('تاريخ البدء', inp('start_date', v.start_date, 'type="date"'))}
    ${field('تاريخ التسليم', inp('due_date', v.due_date, 'type="date"'))}
    ${field('ملاحظات', `<textarea name="note" rows="2">${esc(v.note || '')}</textarea>`, 'wide')}</div>
    <p class="muted small">${esc(tr('يُنشأ للمشروع مركز تكلفة برقمه تلقائيا؛ اختره في فواتير المبيعات والمشتريات وأوامر الشراء والعهد ليُحمَّل عليه.'))}</p>`, {
    wide: true, onOk: async f => {
      const row = { company_id: S.cid, name: f.name, party_id: blank(f.party_id), billing: f.billing, contract_value: blank(f.contract_value), cost_budget: blank(f.cost_budget),
        hourly_rate: blank(f.hourly_rate), manager_id: blank(f.manager_id), location: blank(f.location), status: f.status, start_date: blank(f.start_date), due_date: blank(f.due_date), note: blank(f.note) };
      if (p) await db.upd('projects', { id: 'eq.' + p.id }, row); else { const [n] = await db.ins('projects', row); cache.cc = null; if (n && n.id) { toast(tr('تم الحفظ')); location.hash = '#/projects/' + n.id; return; } }
      cache.cc = null; toast(tr('تم الحفظ')); route();
    } });
}

async function projectView(page, id) {
  const tab = (new URLSearchParams(location.hash.split('?')[1] || '')).get('t') || 'over';
  const [[p], tasks, ts, ms, mem, em, parties, pnl, pend] = await Promise.all([
    db.get('projects', Object.assign(C(), { id: 'eq.' + id })),
    db.get('project_tasks', Object.assign(C(), { project_id: 'eq.' + id, order: 'created_at' })),
    db.get('timesheets', Object.assign(C(), { project_id: 'eq.' + id, order: 'work_date.desc' })),
    db.get('project_milestones', Object.assign(C(), { project_id: 'eq.' + id, order: 'sort,start_date,created_at' })),
    db.get('project_members', Object.assign(C(), { project_id: 'eq.' + id })),
    employeesMap(true), db.get('parties', Object.assign(C(), { kind: 'eq.customer', select: 'id,name' })).catch(() => []),
    db.rpc('project_pnl', { p_company: S.cid }).catch(() => []), db.rpc('timesheets_pending', { p_company: S.cid }).catch(() => [])]);
  if (!p) { page.innerHTML = `<div class="note">${esc(tr('المشروع غير موجود'))}</div>`; return; }
  const r = pnl.find(x => x.project_id === id) || {}, pg = r.progress || {};
  const pm = {}; parties.forEach(x => pm[x.id] = x.name);
  const nm = e => e ? ((LANG === 'en' && e.full_name_en) || e.full_name) : '—';
  const msName = mid => (ms.find(m => m.id === mid) || {}).name || '';
  const liveEmps = Object.values(em).filter(e => !e.end_date || e.end_date >= today()).sort((a, b) => String(a.emp_no).localeCompare(String(b.emp_no)));
  const TABS = [['over', 'نظرة عامة'], ['plan', 'المراحل والمهام'], ['gantt', 'الجدول الزمني'], ['hours', 'ساعات العمل'], ['team', 'الفريق']];
  const kpi = (t, v, cls = '') => `<div class="card kpi"><div class="muted small">${esc(tr(t))}</div><div class="v num ${cls}">${v}</div></div>`;
  const cost = n0(r.cost) + n0(r.unposted_labor);
  page.innerHTML = `<div class="head"><div><a href="#/projects" class="small back">${esc(tr('المشاريع'))}</a><h1>${esc(p.name)} <span class="muted num small">${esc(p.no)}</span></h1>
      <div class="muted small">${prjBadge(p.status)} ${prjFlags(r, p)} · ${esc(tr(PRJ_BILLING[p.billing] || p.billing))}${p.party_id ? ' · ' + esc(pm[p.party_id] || '') : ''}${p.manager_id ? ' · ' + esc(tr('مدير المشروع')) + ': ' + esc(nm(em[p.manager_id])) : ''}${p.location ? ' · ' + esc(p.location) : ''}${p.due_date ? ' · ' + esc(tr('التسليم')) + ' ' + fdate(p.due_date) : ''}</div></div>
      <div class="row"><button class="btn" id="pedit">${esc(tr('تعديل'))}</button></div></div>
    <div class="seg" style="margin-bottom:12px">${TABS.map(([k, t]) => `<a class="${tab === k ? 'on' : ''}" href="#/projects/${id}?t=${k}">${esc(tr(t))}${k === 'hours' && pend.some(x => x.project_id === id) ? ` <span class="badge wait num">${pend.filter(x => x.project_id === id).length}</span>` : ''}</a>`).join('')}</div>
    <div id="pbody"></div>`;
  $('#pedit', page).onclick = () => projectForm(p);
  const body = $('#pbody', page);

  if (tab === 'over') {
    body.innerHTML = `<div class="grid" style="margin-bottom:14px">${kpi('قيمة العقد', money(r.contract))}${kpi('المفوتر', money(r.invoiced))}${kpi('المحصّل', money(r.collected))}
        ${kpi('موازنة التكلفة', money(r.cost_budget))}${kpi('التكلفة الفعلية', money(cost))}${kpi('التكلفة المتوقعة عند الإنجاز', money(r.eac))}${kpi('الهامش المتوقع', money(r.margin), n0(r.margin) < 0 ? 'bad' : 'ok')}</div>
      <div class="card"><h2>${esc(tr('الإنجاز'))}</h2>${progBar(pg)}<p class="small muted">${esc(tr('الفعلي = أوزان المراحل × إنجاز كل مرحلة (المهام المنجزة أو النسبة المدخلة). المخطط = ما مضى من مدة كل مرحلة حسب تواريخها.'))}</p>
        ${n0(pg.weights) && n0(pg.weights) !== 100 ? `<p class="small bad">${esc(tr('مجموع أوزان المراحل'))} <span class="num">${n0(pg.weights)}%</span> — ${esc(tr('يُفضّل أن يكون 100%'))}</p>` : ''}</div>
      <div class="card"><h2>${esc(tr('التكلفة من الدفاتر'))}</h2><p class="small">${esc(tr('كل ما يُقيَّد على مركز تكلفة المشروع'))} <span class="num">${esc(p.no)}</span>: ${esc(tr('فواتير الموردين وأوامر الشراء والعهد والمواد المصروفة من المخزون وتكلفة ساعات الفريق.'))}</p>
        <div class="row" style="gap:6px;flex-wrap:wrap">${can('stock') ? `<button class="btn" id="pmat">${esc(tr('صرف مواد من المخزون'))}</button>` : ''}${can('purch') ? `<a class="btn" href="#/porders/new">${esc(tr('أمر شراء'))}</a>` : ''}
          ${p.cost_center_id && can('reports') ? `<a class="btn" href="#/costcenters">${esc(tr('تقرير مراكز التكلفة'))}</a>` : ''}</div>
        ${n0(r.unposted_labor) ? `<p class="small muted">${esc(tr('تكلفة ساعات معتمدة لم تُرحَّل بعد'))}: <span class="num">${money(r.unposted_labor)}</span></p>` : ''}</div>`;
    if ($('#pmat', body)) $('#pmat', body).onclick = async () => {
      const [items, whf] = await Promise.all([db.get('items', Object.assign(C(), { type: 'eq.stock', order: 'code' })), whField(null, 'يُصرف من مستودع')]);
      modal(tr('صرف مواد للمشروع'), `<div class="fg">${field('الصنف', `<select name="item">${items.map(i => opt(i.id, i.code + ' — ' + i.name)).join('')}</select>`)}${field('الكمية', inp('qty', '', 'type="number" step="0.001" min="0.001" required'))}
          ${whf}${field('التاريخ', `<input type="date" name="date" value="${today()}" max="${today()}">`)}${field('ملاحظة', inp('note', '', 'maxlength="150"'), 'wide')}</div>
          <p class="muted small">${esc(tr('قيد: من ح/ مواد مصروفة على المشاريع (5120) على مركز تكلفة المشروع، إلى ح/ المخزون — بمتوسط التكلفة.'))}</p>`,
        { ok: 'صرف', onOk: async f => { await db.rpc('stock_issue_project', { p_project: id, p_doc: { item: f.item, qty: +f.qty, warehouse: blank(f.warehouse), date: f.date, note: f.note } }); toast(tr('تم الترحيل')); route(); } });
    };
    notesBox(page, 'project', id);
  }

  if (tab === 'plan') {
    const col = s => tasks.filter(t => t.status === s);
    body.innerHTML = `<div class="card"><div class="row" style="justify-content:space-between;align-items:center"><h2>${esc(tr('المراحل'))}</h2><button class="btn sm pri" id="nms">${esc(tr('مرحلة جديدة'))}</button></div>
        ${tbl([{ t: 'المرحلة', h: m => `<b>${esc(m.name)}</b>` }, { t: 'الوزن', r: 1, h: m => prjPct(m.weight) }, { t: 'من', h: m => fdate(m.start_date) }, { t: 'إلى', h: m => fdate(m.end_date) },
          { t: 'الإنجاز', r: 1, h: m => { const ts2 = tasks.filter(t => t.milestone_id === m.id); return ts2.length ? `${prjPct(100 * ts2.filter(t => t.status === 'done').length / ts2.length)} <span class="small muted">(${ts2.filter(t => t.status === 'done').length}/${ts2.length})</span>` : prjPct(m.progress); } }],
          ms, { empty: 'لا توجد مراحل — قسّم المشروع إلى مراحل بأوزان مجموعها 100%', onRow: true })}</div>
      <div class="card"><div class="row" style="justify-content:space-between;align-items:center"><h2>${esc(tr('المهام'))}</h2><button class="btn sm pri" id="ntask">${esc(tr('مهمة جديدة'))}</button></div>
        <div class="kanban" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px">${Object.keys(TASK_STATUS).map(s => `<div class="kcol" data-col="${s}" style="background:var(--soft);border-radius:10px;padding:8px;min-height:120px">
          <div class="small" style="font-weight:700;margin-bottom:6px">${esc(tr(TASK_STATUS[s]))} <span class="num muted">${col(s).length}</span></div>
          ${col(s).map(t => `<div class="kcard card" draggable="true" data-t="${t.id}" style="padding:8px 10px;margin:0 0 6px;cursor:grab">
            <div>${esc(t.title)}</div><div class="small muted">${esc(nm(em[t.assignee_id]))}${t.due_date ? ' · ' + fdate(t.due_date) : ''}${t.milestone_id ? ' · ' + esc(msName(t.milestone_id)) : ''}</div>
            <div class="row" style="gap:4px;margin-top:4px">${s !== 'todo' ? `<button type="button" class="btn sm" data-mv="${t.id}" data-to="${s === 'done' ? 'doing' : 'todo'}" aria-label="${esc(tr('رجوع'))}">‹</button>` : ''}${s !== 'done' ? `<button type="button" class="btn sm" data-mv="${t.id}" data-to="${s === 'todo' ? 'doing' : 'done'}" aria-label="${esc(tr('التالي'))}">›</button>` : ''}
              <button type="button" class="btn sm" data-tedit="${t.id}">${esc(tr('تعديل'))}</button></div></div>`).join('')}</div>`).join('')}</div></div>`;
    const msForm = m => { const d = modal(m ? tr('تعديل المرحلة') : tr('مرحلة جديدة'), `<div class="fg">${field('اسم المرحلة', inp('name', m && m.name, 'required maxlength="150"'), 'wide')}
        ${field('الوزن من المشروع %', inp('weight', m ? m.weight : '', 'type="number" min="0" max="100" step="0.01"'))}${field('نسبة الإنجاز % (إن لم تكن لها مهام)', inp('progress', m ? m.progress : 0, 'type="number" min="0" max="100"'))}
        ${field('من', inp('start_date', m && m.start_date, 'type="date"'))}${field('إلى', inp('end_date', m && m.end_date, 'type="date"'))}</div>
        ${m ? `<button type="button" class="btn danger sm" id="msdel">${esc(tr('حذف المرحلة'))}</button>` : ''}`, {
      onOk: async f => { const row = { name: f.name, weight: +f.weight || 0, progress: +f.progress || 0, start_date: blank(f.start_date), end_date: blank(f.end_date) };
        if (m) await db.upd('project_milestones', { id: 'eq.' + m.id }, row); else await db.ins('project_milestones', Object.assign(row, { company_id: S.cid, project_id: id, sort: ms.length })); toast(tr('تم الحفظ')); route(); } });
      if (m) $('#msdel', d).onclick = async () => { try { await db.del('project_milestones', { id: 'eq.' + m.id }); d.close(); route(); } catch (e) { showErr($('#merr', d), e); } }; };
    $('#nms', body).onclick = () => msForm(null);
    bindRows(body.querySelector('.card'), ms, m => msForm(m));
    const taskForm = t => { const d = modal(t ? tr('تعديل المهمة') : tr('مهمة جديدة'), `<div class="fg">${field('عنوان المهمة', inp('title', t ? t.title : '', 'required'), 'wide')}
      ${field('المرحلة', `<select name="milestone_id"><option value="">—</option>${ms.map(m => opt(m.id, m.name, t && t.milestone_id)).join('')}</select>`)}
      ${field('المكلّف', `<select name="assignee_id"><option value="">${esc(tr('— بلا تكليف —'))}</option>${liveEmps.map(e => opt(e.id, nm(e) + ' (' + e.emp_no + ')', t && t.assignee_id)).join('')}</select>`)}
      ${field('تاريخ البداية', inp('start_date', t ? t.start_date || '' : '', 'type="date"'))}${field('تاريخ التسليم', inp('due_date', t ? t.due_date || '' : '', 'type="date"'))}</div>
      ${t ? `<button type="button" class="btn danger sm" id="tdel">${esc(tr('حذف المهمة'))}</button>` : ''}`, {
      onOk: async f => { const row = { title: f.title, milestone_id: blank(f.milestone_id), assignee_id: blank(f.assignee_id), start_date: blank(f.start_date), due_date: blank(f.due_date) };
        if (t) await db.upd('project_tasks', { id: 'eq.' + t.id }, row); else await db.ins('project_tasks', Object.assign(row, { company_id: S.cid, project_id: id })); toast(tr('تم الحفظ')); route(); } });
      if (t) $('#tdel', d).onclick = async () => { if (!await confirmBox(tr('حذف المهمة'), tr('تُحذف المهمة، وتبقى الساعات المسجلة عليها في المشروع بلا مهمة.'), tr('حذف'))) return;
        try { await db.del('project_tasks', { id: 'eq.' + t.id }); toast(tr('حُذفت المهمة')); route(); } catch (er) { toast(er.message); } }; };
    $('#ntask', body).onclick = () => taskForm(null);
    $$('[data-tedit]', body).forEach(b => b.onclick = () => taskForm(tasks.find(x => x.id === b.dataset.tedit)));
    const move = async (tid, to) => { try { await db.upd('project_tasks', { id: 'eq.' + tid }, { status: to }); route(); } catch (e) { toast(e.message); } };
    $$('[data-mv]', body).forEach(b => b.onclick = () => move(b.dataset.mv, b.dataset.to));
    $$('.kcard', body).forEach(c => c.addEventListener('dragstart', e => e.dataTransfer.setData('text/plain', c.dataset.t)));
    $$('.kcol', body).forEach(c => { c.addEventListener('dragover', e => e.preventDefault()); c.addEventListener('drop', e => { e.preventDefault(); const tid = e.dataTransfer.getData('text/plain'); const t = tasks.find(x => x.id === tid); if (t && t.status !== c.dataset.col) move(tid, c.dataset.col); }); });
  }

  if (tab === 'gantt') {
    const rows = [];
    ms.forEach(m => { rows.push({ k: 'm', name: m.name, s: m.start_date, e: m.end_date, done: null });
      tasks.filter(t => t.milestone_id === m.id).forEach(t => rows.push({ k: 't', name: t.title, s: t.start_date || t.due_date, e: t.due_date || t.start_date, done: t.status })); });
    tasks.filter(t => !t.milestone_id).forEach(t => rows.push({ k: 't', name: t.title, s: t.start_date || t.due_date, e: t.due_date || t.start_date, done: t.status }));
    const ds = [p.start_date, p.due_date, ...rows.flatMap(x => [x.s, x.e])].filter(Boolean).sort();
    if (!ds.length) { body.innerHTML = `<div class="note">${esc(tr('أدخل تواريخ المراحل والمهام ليظهر الجدول الزمني.'))}</div>`; return; }
    const t0 = new Date(ds[0]).getTime(), t1 = new Date(ds[ds.length - 1]).getTime() + 864e5, span = Math.max(t1 - t0, 864e5);
    const pos = d => ((new Date(d).getTime() - t0) / span * 100);
    const now = Date.now(), nowP = now >= t0 && now <= t1 ? ((now - t0) / span * 100) : null;
    const months = []; for (let d = new Date(ds[0].slice(0, 8) + '01'); d.getTime() < t1; d.setMonth(d.getMonth() + 1)) months.push(d.toISOString().slice(0, 7));
    body.innerHTML = `<div class="card" style="overflow-x:auto"><div style="min-width:640px">
      <div style="display:grid;grid-template-columns:200px 1fr;gap:6px;align-items:center"><div></div><div style="position:relative;height:18px">${months.map(m => { const x = Math.max(0, pos(m + '-01')); return `<span class="small muted num" style="position:absolute;inset-inline-start:${x}%">${esc(m)}</span>`; }).join('')}</div>
      ${rows.map(x => `<div class="small" style="${x.k === 'm' ? 'font-weight:700' : 'padding-inline-start:12px'};white-space:nowrap;overflow:hidden;text-overflow:ellipsis" title="${esc(x.name)}">${esc(x.name)}</div>
        <div style="position:relative;height:${x.k === 'm' ? 14 : 10}px;background:var(--line3);border-radius:4px">${x.s && x.e ? `<div style="position:absolute;inset-inline-start:${pos(x.s)}%;width:${Math.max(pos(x.e) - pos(x.s) + 864e5 / span * 100, 0.8)}%;top:0;bottom:0;border-radius:4px;background:${x.k === 'm' ? 'var(--prim,#1B6CC9)' : x.done === 'done' ? 'var(--ok,#16a34a)' : x.done === 'doing' ? 'var(--gold,#C9B27B)' : 'var(--muted)'}"></div>` : ''}
          ${nowP != null ? `<div style="position:absolute;inset-inline-start:${nowP}%;top:-3px;bottom:-3px;width:2px;background:var(--bad)"></div>` : ''}</div>`).join('')}</div>
      <p class="small muted" style="margin-top:10px">${esc(tr('الخط الأحمر = اليوم. المراحل بالأزرق، والمهام: الأخضر منجزة، والذهبي جارية، والرمادي لم تبدأ.'))}</p></div></div>`;
  }

  if (tab === 'hours') {
    const mine = pend.filter(x => x.project_id === id);
    const logged = ts.filter(x => x.status !== 'rejected').reduce((a, x) => a + n0(x.hours), 0), billable = ts.filter(x => x.status === 'approved' && x.billable).reduce((a, x) => a + n0(x.hours), 0);
    const toBill = ts.filter(x => x.status === 'approved' && x.billable && !x.invoice_id).reduce((a, x) => a + n0(x.hours), 0);
    body.innerHTML = `<div class="grid" style="margin-bottom:14px">${kpi('الساعات المسجلة', r2(logged))}${kpi('ساعات معتمدة قابلة للفوترة', r2(billable))}${kpi('لم تُفوتر بعد', r2(toBill))}${kpi('تكلفة الساعات', money(ts.reduce((a, x) => a + n0(x.cost), 0) + n0(r.unposted_labor)))}</div>
      ${mine.length ? `<div class="card"><h2>${esc(tr('بانتظار اعتمادك'))} <span class="badge wait num">${mine.length}</span></h2>${tsPendingTable(mine)}</div>` : ''}
      <div class="card"><div class="row" style="justify-content:space-between;align-items:center;flex-wrap:wrap;gap:6px"><h2>${esc(tr('ساعات العمل'))}</h2><div class="row" style="gap:6px;flex-wrap:wrap">
          ${p.billing === 'hourly' && can('sales') && toBill > 0 ? `<button class="btn sm" id="pinv">${esc(tr('فوترة الساعات المعتمدة'))}</button>` : ''}
          ${can('jepost') && n0(r.unposted_labor) > 0 ? `<button class="btn sm" id="plab">${esc(tr('ترحيل تكلفة الساعات'))}</button>` : ''}
          <button class="btn sm pri" id="nts">${esc(tr('تسجيل ساعات'))}</button></div></div>
        ${tbl([{ t: 'التاريخ', h: x => fdate(x.work_date) }, { t: 'الموظف', h: x => esc(nm(em[x.employee_id])) }, { t: 'المهمة', h: x => esc((tasks.find(t => t.id === x.task_id) || {}).title || '—') },
          { t: 'الساعات', r: 1, h: x => `<span class="num">${r2(x.hours)}</span>` }, { t: 'مفوترة', h: x => x.billable ? (x.invoice_id ? `<a class="badge ok" href="#/sales/${x.invoice_id}">${esc(tr('فُوترت'))}</a>` : `<span class="badge info">${esc(tr('قابلة'))}</span>`) : `<span class="badge">${esc(tr('داخلية'))}</span>` },
          { t: 'الحالة', h: x => `<span class="badge ${TS_STATUS[x.status][1]}">${esc(tr(TS_STATUS[x.status][0]))}</span>${x.reject_note ? `<div class="small bad">${esc(x.reject_note)}</div>` : ''}` },
          { t: 'التكلفة', r: 1, h: x => x.cost != null ? money(x.cost) : '' },
          { t: '', h: x => !x.invoice_id && !x.cost_entry ? `<button class="btn sm danger" data-del="${x.id}">${esc(tr('حذف'))}</button>` : '' }], ts, { empty: 'لا توجد ساعات مسجلة' })}
        <p class="small muted">${esc(tr('تكلفة الساعة = (الأجر الشهري مع البدلات + حصة المنشأة في التأمينات الاجتماعية) ÷ 240 ساعة (30 يوما × 8 ساعات). الترحيل ينقل هذه التكلفة من الرواتب إلى مركز تكلفة المشروع دون تغيير إجمالي المصروف.'))}</p></div>`;
    bindTsPending(body);
    $('#nts', body).onclick = () => modal(tr('تسجيل ساعات عمل'), `<div class="fg">
      ${field('الموظف', `<select name="employee_id" required>${liveEmps.map(e => opt(e.id, nm(e) + ' (' + e.emp_no + ')')).join('')}</select>`)}
      ${field('المهمة (اختياري)', `<select name="task_id"><option value="">${esc(tr('— بلا مهمة —'))}</option>${tasks.map(t => opt(t.id, t.title)).join('')}</select>`)}
      ${field('التاريخ', inp('work_date', today(), 'type="date" required max="' + today() + '"'))}
      ${field('عدد الساعات', inp('hours', '', 'type="number" step="0.25" min="0.25" max="24" required'))}
      ${field('قابلة للفوترة؟', `<select name="billable">${opt('true', tr('نعم'), p.billing === 'internal' ? 'false' : 'true')}${opt('false', tr('لا'), p.billing === 'internal' ? 'false' : 'true')}</select>`)}
      ${field('ملاحظة', inp('note', ''), 'wide')}</div>`, {
      onOk: async f => { if (!f.employee_id) throw new Error(tr('اختر الموظف'));
        await db.ins('timesheets', { company_id: S.cid, project_id: id, task_id: blank(f.task_id), employee_id: f.employee_id, work_date: f.work_date, hours: +f.hours, billable: f.billable === 'true', note: blank(f.note) });
        toast(tr('تم الحفظ')); route(); } });
    $$('[data-del]', body).forEach(b => b.onclick = async () => { try { await db.del('timesheets', { id: 'eq.' + b.dataset.del }); toast(tr('تم الحذف')); route(); } catch (e) { toast(e.message); } });
    if ($('#pinv', body)) $('#pinv', body).onclick = () => modal(tr('فوترة الساعات المعتمدة'), `<p>${esc(tr('تصدر فاتورة مبيعات واحدة للعميل بالساعات المعتمدة القابلة للفوترة غير المفوترة حتى التاريخ، بسعر كل عضو في الفريق أو سعر ساعة المشروع.'))}</p>
        <div class="fg">${field('حتى تاريخ', `<input type="date" name="d" value="${today()}" max="${today()}">`)}</div>`,
      { ok: 'إصدار الفاتورة', onOk: async f => { const iid = await db.rpc('project_invoice_hours', { p_project: id, p_through: f.d }); toast(tr('صدرت الفاتورة')); if (typeof zatcaKick === 'function') zatcaKick(); location.hash = '#/sales/' + iid; } });
    if ($('#plab', body)) $('#plab', body).onclick = () => modal(tr('ترحيل تكلفة الساعات'), `<p>${esc(tr('يُرحَّل قيد لكل مشروع بتكلفة الساعات المعتمدة حتى التاريخ: من ح/ الرواتب (مركز تكلفة المشروع) إلى ح/ الرواتب (مركز الموظف).'))}</p>
        <div class="fg">${field('حتى تاريخ', `<input type="date" name="d" value="${today()}" max="${today()}">`)}</div>`,
      { ok: 'ترحيل', onOk: async f => { const n = await db.rpc('project_labor_post', { p_company: S.cid, p_through: f.d }); toast(tr('رُحّل') + ' ' + n + ' ' + tr('قيد')); route(); } });
  }

  if (tab === 'team') {
    body.innerHTML = `<div class="card"><div class="row" style="justify-content:space-between;align-items:center"><h2>${esc(tr('فريق المشروع'))}</h2><button class="btn sm pri" id="nmem">${esc(tr('إضافة عضو'))}</button></div>
      ${tbl([{ t: 'الموظف', h: m => esc(nm(em[m.employee_id])) }, { t: 'الدور', h: m => esc(m.role || '') }, { t: 'سعر الساعة للعميل', r: 1, h: m => m.rate != null ? money(m.rate) : `<span class="muted small">${esc(tr('سعر المشروع'))}</span>` },
        { t: 'نسبة التفرغ', r: 1, h: m => prjPct(m.alloc) }, { t: 'تكلفة الساعة', r: 1, h: m => money(empHourEst(em[m.employee_id])) }], mem, { empty: 'لا يوجد أعضاء — أضف الفريق ليسجّلوا ساعاتهم من «ساعات عملي»', onRow: true })}
      <p class="small muted">${esc(tr('أعضاء الفريق ومدير المشروع ومن كُلّف بمهمة يسجّلون ساعاتهم بأنفسهم، ويعتمدها مدير المشروع. تكلفة الساعة هنا تقديرية من الأجر الحالي.'))}</p></div>`;
    const memForm = m => { const d = modal(m ? tr('تعديل العضو') : tr('إضافة عضو'), `<div class="fg">${m ? '' : field('الموظف', `<select name="employee_id">${liveEmps.filter(e => !mem.some(x => x.employee_id === e.id)).map(e => opt(e.id, nm(e) + ' (' + e.emp_no + ')')).join('')}</select>`)}
        ${field('الدور في المشروع', inp('role', m && m.role, 'maxlength="80"'))}${field('سعر الساعة للعميل (اختياري)', inp('rate', m && m.rate, 'type="number" min="0" step="0.01"'))}${field('نسبة التفرغ %', inp('alloc', m && m.alloc, 'type="number" min="1" max="100"'))}</div>
        ${m ? `<button type="button" class="btn danger sm" id="mdel">${esc(tr('إزالة من الفريق'))}</button>` : ''}`, {
      onOk: async f => { const row = { role: blank(f.role), rate: blank(f.rate), alloc: blank(f.alloc) };
        if (m) await db.upd('project_members', { id: 'eq.' + m.id }, row); else await db.ins('project_members', Object.assign(row, { company_id: S.cid, project_id: id, employee_id: f.employee_id })); toast(tr('تم الحفظ')); route(); } });
      if (m) $('#mdel', d).onclick = async () => { await db.del('project_members', { id: 'eq.' + m.id }); d.close(); route(); }; };
    $('#nmem', body).onclick = () => memForm(null);
    bindRows(body, mem, m => memForm(m));
  }
}
const empHourEst = e => e ? (n0(e.basic) + n0(e.housing) + n0(e.transport)) / 240 : 0;   // display only; the posted cost adds allowances and GOSI (emp_hour_cost)

/* ---------- approval table shared by the project page and «ساعات عملي» ---------- */
function tsPendingTable(rows) {
  return `<div class="tw"><table><thead><tr><th><input type="checkbox" id="tsall" aria-label="${esc(tr('تحديد الكل'))}"></th><th>${esc(tr('التاريخ'))}</th><th>${esc(tr('الموظف'))}</th><th>${esc(tr('المشروع'))}</th><th>${esc(tr('المهمة'))}</th><th class="r">${esc(tr('الساعات'))}</th><th>${esc(tr('ملاحظة'))}</th></tr></thead><tbody>
    ${rows.map(x => `<tr><td><input type="checkbox" data-tsr="${x.id}" checked aria-label="${esc(tr('اعتماد'))}"></td><td>${fdate(x.date)}</td><td>${esc((LANG === 'en' && x.employee_en) || x.employee)}</td><td>${esc(x.project)}</td><td>${esc(x.task || '—')}</td><td class="r num">${r2(x.hours)}</td><td class="small">${esc(x.note || '')}</td></tr>`).join('')}</tbody></table></div>
    <div class="row" style="gap:6px;margin-top:8px"><button class="btn pri sm" id="tsok">${esc(tr('اعتماد المحدد'))}</button><button class="btn danger sm" id="tsno">${esc(tr('رفض المحدد'))}</button></div>`;
}
function bindTsPending(root) {
  if (!$('#tsok', root)) return;
  const ids = () => $$('[data-tsr]:checked', root).map(c => c.dataset.tsr);
  $('#tsall', root).onchange = e => $$('[data-tsr]', root).forEach(c => c.checked = e.target.checked);
  $('#tsok', root).onclick = () => busy($('#tsok', root), async () => { if (!ids().length) return; const n = await db.rpc('timesheet_review', { p_ids: ids(), p_ok: true, p_note: null }); toast(tr('اعتُمدت') + ' ' + n); route(); });
  $('#tsno', root).onclick = () => { if (!ids().length) return; const sel = ids(); modal(tr('رفض الساعات'), field('السبب', inp('r', '', 'required maxlength="300"'), 'wide'),
    { ok: 'رفض', onOk: async f => { await db.rpc('timesheet_review', { p_ids: sel, p_ok: false, p_note: f.r }); toast(tr('تم')); route(); } }); };
}

/* ---------- «ساعات عملي»: the employee logs his own hours; the project manager approves his team's ---------- */
VIEWS['#/mytime'] = async page => {
  if (!S.emp) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للموظفين المرتبطين بملف موظف.'))}</div>`; return; }
  const [projs, mine, pend] = await Promise.all([db.rpc('my_time_projects', { p_company: S.cid }), db.get('timesheets', Object.assign(C(), { employee_id: 'eq.' + S.emp, order: 'work_date.desc', limit: 200 })).catch(() => []),
    db.rpc('timesheets_pending', { p_company: S.cid }).catch(() => [])]);
  const pm = {}; projs.forEach(p => pm[p.id] = p);
  const wk = new Date(Date.now() - 6 * 864e5).toISOString().slice(0, 10), week = mine.filter(x => x.work_date >= wk && x.status !== 'rejected').reduce((a, x) => a + n0(x.hours), 0);
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('ساعات عملي'))}</h1><div class="muted small">${esc(tr('سجّل ساعات عملك على مشاريعك، ويعتمدها مدير المشروع.'))}</div></div>
      ${projs.length ? `<div class="row"><button class="btn pri" id="mtn">${esc(tr('تسجيل ساعات'))}</button></div>` : ''}</div>
    ${pend.length ? `<div class="card"><h2>${esc(tr('بانتظار اعتمادك'))} <span class="badge wait num">${pend.length}</span></h2>${tsPendingTable(pend)}</div>` : ''}
    ${projs.length ? '' : `<div class="note">${esc(tr('لست ضمن فريق أي مشروع جارٍ. يضيفك مدير المشروع أو يكلّفك بمهمة.'))}</div>`}
    <div class="grid" style="margin-bottom:14px"><div class="card kpi"><div class="muted small">${esc(tr('ساعاتك آخر 7 أيام'))}</div><div class="v num">${r2(week)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('بانتظار الاعتماد'))}</div><div class="v num">${mine.filter(x => x.status === 'submitted').length}</div></div></div>
    ${tbl([{ t: 'التاريخ', h: x => fdate(x.work_date) }, { t: 'المشروع', h: x => esc((pm[x.project_id] || {}).name || '') }, { t: 'الساعات', r: 1, h: x => `<span class="num">${r2(x.hours)}</span>` },
      { t: 'ملاحظة', h: x => esc(x.note || '') }, { t: 'الحالة', h: x => `<span class="badge ${TS_STATUS[x.status][1]}">${esc(tr(TS_STATUS[x.status][0]))}</span>${x.reject_note ? `<div class="small bad">${esc(x.reject_note)}</div>` : ''}` },
      { t: '', h: x => x.status !== 'approved' ? `<button class="btn sm" data-wd="${x.id}">${esc(tr('سحب'))}</button>` : '' }], mine, { empty: 'لم تسجّل ساعات بعد' })}`;
  bindTsPending(page);
  $$('[data-wd]', page).forEach(b => b.onclick = async () => { try { await db.rpc('timesheet_withdraw', { p_id: b.dataset.wd }); route(); } catch (e) { toast(e.message); } });
  if ($('#mtn', page)) $('#mtn', page).onclick = () => { const d = modal(tr('تسجيل ساعات'), `<div class="fg">${field('المشروع', `<select name="p">${projs.map(p => opt(p.id, p.no + ' — ' + p.name)).join('')}</select>`)}
      ${field('المهمة (اختياري)', '<select name="t"></select>')}${field('التاريخ', `<input type="date" name="d" value="${today()}" max="${today()}">`)}${field('عدد الساعات', inp('h', '', 'type="number" step="0.25" min="0.25" max="24" required'))}
      ${field('ملاحظة', inp('n', '', 'maxlength="200"'), 'wide')}</div>`, {
    onOk: async f => { await db.rpc('timesheet_submit', { p_company: S.cid, p_doc: { project: f.p, task: blank(f.t), date: f.d, hours: +f.h, note: f.n } }); toast(tr('أُرسلت للاعتماد')); route(); } });
    const fill = () => { const p = pm[$('[name=p]', d).value]; $('[name=t]', d).innerHTML = `<option value="">—</option>` + ((p && p.tasks) || []).map(t => opt(t.id, t.title)).join(''); };
    $('[name=p]', d).onchange = fill; fill(); };
};
