'use strict';
/* ===== «التهيئة والترحيب» (0107): a checklist per new employee (hired in the last 120 days) =====
   Automatic steps are read from the employee's data; the rest are ticked by HR (onboarding_marks), including the
   company's own steps (companies.onboarding_items). */
const ONB_MANUAL = [['gosi', 'التسجيل في التأمينات الاجتماعية'], ['qiwa', 'توثيق العقد في منصة قوى'], ['welcome', 'جلسة الترحيب والتعريف بالمنشأة'], ['tools', 'تسليم أدوات العمل والعهد']];
VIEWS['#/onboarding'] = async page => {
  if (!isHR()) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للمالك والموارد البشرية.'))}</div>`; return; }
  const td = today(), since = new Date(Date.now() - 120 * 864e5 + 3 * 3600e3).toISOString().slice(0, 10), q = { company_id: 'eq.' + S.cid };
  const [em, con, mem, docs, ins, pol, acks, marks] = await Promise.all([employeesMap(true),
    db.get('contracts', Object.assign({ status: 'eq.active', select: 'employee_id' }, q)).catch(() => []),
    db.get('members', Object.assign({ select: 'employee_id,role' }, q)).catch(() => []),
    db.get('employee_documents', Object.assign({ select: 'employee_id,doc_type' }, q)).catch(() => []),
    db.get('insurance_members', Object.assign({ select: 'employee_id,end_date' }, q)).catch(() => []),
    db.get('policies', Object.assign({ active: 'eq.true', select: 'id' }, q)).catch(() => []),
    db.get('policy_acks', Object.assign({ select: 'employee_id,policy_id' }, q)).catch(() => []),
    db.get('onboarding_marks', q).catch(() => [])]);
  const has_ = (rows, id, f) => rows.some(r => r.employee_id === id && (!f || f(r)));
  const ownerEmp = (mem.find(m => m.role === 'owner') || {}).employee_id, custom = (S.company && S.company.onboarding_items) || [];
  const steps = e => [
    { k: 'contract', t: 'عقد عمل ساري', ok: has_(con, e.id), h: '#/docs/' + e.id },
    { k: 'account', t: 'حساب دخول للموظف في وعد', ok: has_(mem, e.id), h: '#/users' },
    { k: 'id', t: e.is_saudi ? 'رقم الهوية في ملفه' : 'الإقامة مسجلة في وثائقه', ok: e.is_saudi ? !!e.national_id : has_(docs, e.id, r => r.doc_type === 'iqama'), h: e.is_saudi ? '#/employees' : '#/docs/' + e.id },
    { k: 'iban', t: 'الآيبان لصرف الراتب', ok: !!e.iban, h: '#/employees' },
    { k: 'manager', t: 'المدير المباشر محدد', ok: !!e.manager_id || e.id === ownerEmp, h: '#/employees' },
    { k: 'insurance', t: 'التأمين الطبي', ok: has_(ins, e.id, r => !r.end_date || r.end_date >= td), h: '#/insurance' },
    ...(pol.length ? [{ k: 'policies', t: 'الإقرار بسياسات المنشأة', ok: pol.every(p => acks.some(a => a.employee_id === e.id && a.policy_id === p.id)), h: '#/policies' }] : []),
    ...ONB_MANUAL.concat(custom.map(c => ['c:' + c, c])).map(([k, t]) => ({ k, t, manual: true, ok: marks.some(m => m.employee_id === e.id && m.item === k) }))];
  const news = Object.values(em).filter(e => e.hire_date && e.hire_date >= since && (!e.end_date || e.end_date >= td)).sort((a, b) => (b.hire_date || '').localeCompare(a.hire_date || ''));
  const prog = e => { const s = steps(e); return [s.filter(x => x.ok).length, s.length, s.filter(x => !x.ok)]; };
  const name = e => (LANG === 'en' && e.full_name_en) || e.full_name;
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('التهيئة والترحيب'))}</h1><div class="muted">${esc(tr('قائمة مهام لكل موظف جديد خلال أول 120 يوما. بعضها يكتمل تلقائيا من بياناته، والباقي تعلّمه هنا.'))}</div></div>
      <button class="btn" id="onbc">${esc(tr('بنود المنشأة الخاصة'))}</button></div>
    ${tbl([{ t: 'الموظف', h: e => `<b>${esc(name(e))}</b> <span class="small muted num">${esc(e.emp_no || '')}</span>` }, { t: 'المباشرة', h: e => fdate(e.hire_date) },
      { t: 'الإنجاز', h: e => { const [d, n] = prog(e), p = Math.round(d / n * 100); return `<div class="row" style="gap:8px;align-items:center"><div style="flex:1;min-width:80px;height:8px;background:var(--line);border-radius:4px"><div style="width:${p}%;height:8px;border-radius:4px;background:${p === 100 ? 'var(--ok,#1f9d55)' : '#d98e04'}"></div></div><span class="num small">${p}%</span></div>`; } },
      { t: 'ينقصه', h: e => { const m = prog(e)[2]; return m.length ? `<span class="small">${m.slice(0, 3).map(x => esc(tr(x.t))).join('، ')}${m.length > 3 ? ' …' : ''}</span>` : `<span class="badge ok">${esc(tr('اكتملت'))}</span>`; } }],
      news, { empty: 'لا يوجد موظفون جدد خلال آخر 120 يوما', onRow: true })}`;
  bindRows(page, news, e => open(e));
  $('#onbc', page).onclick = () => modal(tr('بنود المنشأة الخاصة'), `<p class="muted small" style="margin-top:0">${esc(tr('تظهر لكل موظف جديد مع البنود الأساسية. سطر لكل بند.'))}</p>
    <textarea name="items" rows="6" style="width:100%">${esc(custom.join('\n'))}</textarea>`, { onOk: async f => {
      await db.rpc('onboarding_items_set', { p_company: S.cid, p_items: (f.items || '').split('\n') }); await loadContext(); toast(tr('تم الحفظ')); route(); } });
  function open(e) {
    const s = steps(e);
    const d = modal(tr('التهيئة والترحيب') + ' — ' + name(e), `<div style="display:grid;gap:8px">${s.map(x => x.manual
      ? `<label class="row" style="gap:8px"><input type="checkbox" data-onb="${esc(x.k)}"${x.ok ? ' checked' : ''}> ${esc(tr(x.t))}</label>`
      : `<div class="row" style="gap:8px"><span class="badge ${x.ok ? 'ok' : 'wait'}">${x.ok ? '✓' : '○'}</span> ${esc(tr(x.t))} ${x.ok ? '' : `<a class="small" href="${x.h}">${esc(tr('أكمله'))}</a>`}</div>`).join('')}</div>
      <p class="muted small">${esc(tr('البنود بالعلامة تكتمل تلقائيا عند إدخال بياناتها في النظام.'))}</p>`, { ok: tr('تم'), onOk: () => route() });
    $$('[data-onb]', d).forEach(c => c.onchange = async () => { try {
      if (c.checked) await db.ins('onboarding_marks', { company_id: S.cid, employee_id: e.id, item: c.dataset.onb });
      else await db.del('onboarding_marks', { employee_id: 'eq.' + e.id, item: 'eq.' + c.dataset.onb });
      const m = marks.findIndex(x => x.employee_id === e.id && x.item === c.dataset.onb); if (c.checked && m < 0) marks.push({ employee_id: e.id, item: c.dataset.onb }); if (!c.checked && m >= 0) marks.splice(m, 1);
    } catch (er) { c.checked = !c.checked; toast(er.message); } });
    $$('a', d).forEach(a => a.addEventListener('click', () => $('#dlg').close()));
  }
};
