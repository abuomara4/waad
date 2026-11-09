'use strict';
/* ===== Projects & timesheets: projects with tasks and logged hours, rolled up into estimated cost
   (from the employee wage) and billing (fixed budget or hourly rate). Module: 'proj'. ===== */

const PRJ_STATUS = { active: 'جارٍ', on_hold: 'متوقف مؤقتاً', done: 'منتهٍ', cancelled: 'ملغى' };
const PRJ_BILLING = { fixed: 'سعر ثابت', hourly: 'بالساعة', internal: 'داخلي (غير مفوتر)' };
const TASK_STATUS = { todo: 'لم تبدأ', doing: 'جارية', done: 'منجزة' };
const prjBadge = s => `<span class="badge ${s === 'active' ? 'ok' : s === 'cancelled' ? 'bad' : s === 'on_hold' ? 'wait' : 'info'}">${esc(tr(PRJ_STATUS[s] || s))}</span>`;
const taskBadge = s => `<span class="badge ${s === 'done' ? 'ok' : s === 'doing' ? 'info' : 'wait'}">${esc(tr(TASK_STATUS[s] || s))}</span>`;
const empHourly = e => (n0(e.basic) + n0(e.housing) + n0(e.transport)) / 240;   // monthly wage → hourly estimate

VIEWS['#/projects'] = async (page, arg) => {
  if (!has('owner', 'admin', 'finance', 'hr')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  if (arg) return projectView(page, arg);
  const [projs, res] = await Promise.all([
    db.get('projects', Object.assign(C(), { order: 'created_at.desc', limit: 500 })),
    db.rpc('project_summary', { p_company: S.cid }).catch(() => [])]);
  const rm = {}; res.forEach(r => rm[r.project_id] = r);
  const active = projs.filter(p => p.status === 'active').length;
  const hours = res.reduce((a, r) => a + n0(r.logged_hours), 0);
  const rev = res.reduce((a, r) => a + n0(r.est_revenue), 0), cost = res.reduce((a, r) => a + n0(r.est_cost), 0);
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('المشاريع وجداول الوقت'))}</h1><div class="muted small">${esc(tr('المشاريع والمهام وساعات العمل والتكلفة التقديرية'))}</div></div>
      <div class="row"><button class="btn pri" id="nprj">${esc(tr('مشروع جديد'))}</button></div></div>
    <div class="grid" style="margin-bottom:14px">
      <div class="card kpi"><div class="muted small">${esc(tr('مشاريع جارية'))}</div><div class="v num">${active} <span class="small muted">/ ${projs.length}</span></div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('إجمالي الساعات'))}</div><div class="v num">${r2(hours)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('الإيراد المفوتر (تقديري)'))}</div><div class="v num">${money(rev)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('تكلفة العمل (تقديرية)'))}</div><div class="v num">${money(cost)}</div></div></div>
    ${tbl([{ t: 'الرقم', h: p => `<span class="num">${esc(p.no)}</span>` }, { t: 'المشروع', k: 'name' }, { t: 'الفوترة', h: p => esc(tr(PRJ_BILLING[p.billing] || p.billing)) }, { t: 'الحالة', h: p => prjBadge(p.status) },
      { t: 'المهام', r: 1, h: p => { const r = rm[p.id] || {}; return `<span class="num">${n0(r.tasks_done)}/${n0(r.tasks)}</span>`; } },
      { t: 'الساعات', r: 1, h: p => `<span class="num">${r2(n0((rm[p.id] || {}).logged_hours))}</span>` },
      { t: 'الإيراد', r: 1, h: p => money((rm[p.id] || {}).est_revenue) }, { t: 'التكلفة', r: 1, h: p => money((rm[p.id] || {}).est_cost) }],
      projs, { empty: 'لا توجد مشاريع بعد — ابدأ بمشروع جديد', onRow: true })}`;
  $('#nprj', page).onclick = () => projectForm(null);
  bindRows(page, projs, p => location.hash = '#/projects/' + p.id);
};

async function projectForm(p) {
  const parties = await db.get('parties', Object.assign(C(), { kind: 'eq.customer', select: 'id,name' })).catch(() => []);
  const v = p || { billing: 'internal', status: 'active' };
  modal(p ? tr('تعديل المشروع') : tr('مشروع جديد'), `<div class="fg">
    ${field('اسم المشروع', inp('name', v.name, 'required'), 'wide')}
    ${field('العميل (اختياري)', `<select name="party_id"><option value="">${esc(tr('— بلا عميل —'))}</option>${parties.map(x => opt(x.id, x.name, v.party_id)).join('')}</select>`)}
    ${field('طريقة الفوترة', `<select name="billing">${Object.entries(PRJ_BILLING).map(([k, t]) => opt(k, tr(t), v.billing)).join('')}</select>`)}
    ${field('الميزانية / السعر الثابت', inp('budget', v.budget, 'type="number" step="0.01" min="0"'))}
    ${field('سعر الساعة', inp('hourly_rate', v.hourly_rate, 'type="number" step="0.01" min="0"'))}
    ${field('الحالة', `<select name="status">${Object.entries(PRJ_STATUS).map(([k, t]) => opt(k, tr(t), v.status)).join('')}</select>`)}
    ${field('تاريخ البدء', inp('start_date', v.start_date, 'type="date"'))}
    ${field('تاريخ التسليم', inp('due_date', v.due_date, 'type="date"'))}
    ${field('ملاحظات', `<textarea name="note" rows="2">${esc(v.note || '')}</textarea>`, 'wide')}</div>
    <p class="muted small">${esc(tr('التكلفة تُحسب تقديرياً من أجر الموظف مقسوماً على ساعات الشهر.'))}</p>`, {
    onOk: async f => {
      const row = { company_id: S.cid, name: f.name, party_id: blank(f.party_id), billing: f.billing, budget: blank(f.budget),
        hourly_rate: blank(f.hourly_rate), status: f.status, start_date: blank(f.start_date), due_date: blank(f.due_date), note: blank(f.note) };
      if (p) await db.upd('projects', { id: 'eq.' + p.id }, row); else await db.ins('projects', row);
      toast(tr('تم الحفظ')); route();
    } });
}

async function projectView(page, id) {
  const [[p], tasks, ts, em, parties] = await Promise.all([
    db.get('projects', Object.assign(C(), { id: 'eq.' + id })),
    db.get('project_tasks', Object.assign(C(), { project_id: 'eq.' + id, order: 'created_at' })),
    db.get('timesheets', Object.assign(C(), { project_id: 'eq.' + id, order: 'work_date.desc' })),
    employeesMap(true), db.get('parties', Object.assign(C(), { kind: 'eq.customer', select: 'id,name' })).catch(() => [])]);
  if (!p) { page.innerHTML = `<div class="note">${esc(tr('المشروع غير موجود'))}</div>`; return; }
  const pm = {}; parties.forEach(x => pm[x.id] = x.name);
  const nm = e => e ? ((LANG === 'en' && e.full_name_en) || e.full_name) : '—';
  const logged = ts.reduce((a, r) => a + n0(r.hours), 0), billable = ts.filter(r => r.billable).reduce((a, r) => a + n0(r.hours), 0);
  const cost = ts.reduce((a, r) => a + n0(r.hours) * empHourly(em[r.employee_id] || {}), 0);
  const rev = p.billing === 'hourly' ? billable * n0(p.hourly_rate) : p.billing === 'fixed' ? n0(p.budget) : null;
  const margin = rev == null ? null : rev - cost;
  const liveEmps = Object.values(em).filter(e => !e.end_date || e.end_date >= today()).sort((a, b) => String(a.emp_no).localeCompare(String(b.emp_no)));
  page.innerHTML = `<div class="head"><div><h1>${esc(p.name)} <span class="muted num small">${esc(p.no)}</span></h1>
      <div class="muted small">${prjBadge(p.status)} · ${esc(tr(PRJ_BILLING[p.billing] || p.billing))}${p.party_id ? ' · ' + esc(pm[p.party_id] || '') : ''}${p.due_date ? ' · ' + esc(tr('التسليم')) + ' ' + fdate(p.due_date) : ''}</div></div>
      <div class="row"><a class="btn" href="#/projects">${esc(tr('رجوع'))}</a><button class="btn" id="pedit">${esc(tr('تعديل'))}</button></div></div>
    <div class="grid" style="margin-bottom:14px">
      <div class="card kpi"><div class="muted small">${esc(tr('الساعات المسجلة'))}</div><div class="v num">${r2(logged)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('ساعات مفوترة'))}</div><div class="v num">${r2(billable)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('الإيراد (تقديري)'))}</div><div class="v num">${money(rev)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('تكلفة العمل (تقديرية)'))}</div><div class="v num">${money(cost)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('الهامش (تقديري)'))}</div><div class="v num ${margin == null ? '' : margin >= 0 ? 'ok' : 'bad'}">${money(margin)}</div></div></div>
    <div class="card"><div class="row" style="justify-content:space-between;align-items:center"><h2>${esc(tr('المهام'))}</h2><button class="btn sm pri" id="ntask">${esc(tr('مهمة جديدة'))}</button></div>
      ${tbl([{ t: 'المهمة', k: 'title' }, { t: 'المكلّف', h: t => esc(nm(em[t.assignee_id])) }, { t: 'التسليم', h: t => fdate(t.due_date) }, { t: 'الحالة', h: t => taskBadge(t.status) },
        { t: '', h: t => `<select data-task="${t.id}" style="width:auto">${Object.entries(TASK_STATUS).map(([k, l]) => opt(k, tr(l), t.status)).join('')}</select>` }], tasks, { empty: 'لا توجد مهام' })}</div>
    <div class="card"><div class="row" style="justify-content:space-between;align-items:center"><h2>${esc(tr('ساعات العمل'))}</h2><button class="btn sm pri" id="nts">${esc(tr('تسجيل ساعات'))}</button></div>
      ${tbl([{ t: 'التاريخ', h: r => fdate(r.work_date) }, { t: 'الموظف', h: r => esc(nm(em[r.employee_id])) }, { t: 'المهمة', h: r => esc((tasks.find(t => t.id === r.task_id) || {}).title || '—') },
        { t: 'الساعات', r: 1, h: r => `<span class="num">${r2(r.hours)}</span>` }, { t: 'مفوترة', h: r => r.billable ? `<span class="badge ok">${esc(tr('نعم'))}</span>` : `<span class="badge">${esc(tr('لا'))}</span>` },
        { t: 'ملاحظة', k: 'note' }, { t: '', h: r => `<button class="btn sm danger" data-del="${r.id}">${esc(tr('حذف'))}</button>` }], ts, { empty: 'لا توجد ساعات مسجلة' })}</div>`;
  $('#pedit', page).onclick = () => projectForm(p);
  $('#ntask', page).onclick = () => modal(tr('مهمة جديدة'), `<div class="fg">${field('عنوان المهمة', inp('title', '', 'required'), 'wide')}
    ${field('المكلّف', `<select name="assignee_id"><option value="">${esc(tr('— بلا تكليف —'))}</option>${liveEmps.map(e => opt(e.id, nm(e) + ' (' + e.emp_no + ')')).join('')}</select>`)}
    ${field('تاريخ التسليم', inp('due_date', '', 'type="date"'))}</div>`, {
    onOk: async f => { await db.ins('project_tasks', { company_id: S.cid, project_id: id, title: f.title, assignee_id: blank(f.assignee_id), due_date: blank(f.due_date) }); toast(tr('تم الحفظ')); route(); } });
  $('#nts', page).onclick = () => modal(tr('تسجيل ساعات عمل'), `<div class="fg">
    ${field('الموظف', `<select name="employee_id" required>${liveEmps.map(e => opt(e.id, nm(e) + ' (' + e.emp_no + ')')).join('')}</select>`)}
    ${field('المهمة (اختياري)', `<select name="task_id"><option value="">${esc(tr('— بلا مهمة —'))}</option>${tasks.map(t => opt(t.id, t.title)).join('')}</select>`)}
    ${field('التاريخ', inp('work_date', today(), 'type="date" required max="' + today() + '"'))}
    ${field('عدد الساعات', inp('hours', '', 'type="number" step="0.25" min="0.25" max="24" required'))}
    ${field('مفوترة؟', `<select name="billable">${opt('true', tr('نعم'), 'true')}${opt('false', tr('لا'))}</select>`)}
    ${field('ملاحظة', inp('note', ''), 'wide')}</div>`, {
    onOk: async f => { if (!f.employee_id) throw new Error(tr('اختر الموظف'));
      await db.ins('timesheets', { company_id: S.cid, project_id: id, task_id: blank(f.task_id), employee_id: f.employee_id, work_date: f.work_date, hours: +f.hours, billable: f.billable === 'true', note: blank(f.note) });
      toast(tr('تم الحفظ')); route(); } });
  $$('[data-task]', page).forEach(s => s.onchange = async () => { try { await db.upd('project_tasks', { id: 'eq.' + s.dataset.task }, { status: s.value }); route(); } catch (e) { toast(e.message); } });
  $$('[data-del]', page).forEach(b => b.onclick = async () => { try { await db.del('timesheets', { id: 'eq.' + b.dataset.del }); toast(tr('تم الحذف')); route(); } catch (e) { toast(e.message); } });
}
