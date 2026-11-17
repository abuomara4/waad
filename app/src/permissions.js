'use strict';
/* ===== «الصلاحيات»: every permission in one page (owner, admin, HR; finance edits the finance grid) =====
   1) people: each user's roles and personal permissions, edited with accessDialog (hr.js);
   2) role permissions by department: what the accountant and the storekeeper roles see (finance_permissions);
   3) a map of what each role covers in each department. */
const PERM_DEPTS = [
  ['المبيعات والتسويق', ['sales', 'mkt', 'void']],
  ['المشتريات', ['purch']],
  ['المخزون', ['stock', 'stockadj', 'items']],
  ['المالية والمحاسبة', ['dash', 'je', 'jepost', 'ledger', 'reports', 'vat', 'coa', 'payroll', 'settings']],
  ['المشاريع', ['proj']]];
// what each role covers, per department (✓ all, ◐ by permission, — none)
const ROLE_MAP = [
  ['الموارد البشرية', { owner: '✓', admin: '✓', hr: '✓', finance: 'الرواتب', manager: 'فريقه', accountant: '—', storekeeper: '—', employee: 'خدماته' }],
  ['الاعتمادات', { owner: '✓', admin: '✓', hr: '✓', finance: 'المبالغ', manager: 'فريقه', accountant: '—', storekeeper: '—', employee: 'طلباته' }],
  ['المالية والمحاسبة', { owner: '✓', admin: '✓', hr: '—', finance: '✓', manager: '—', accountant: '◐', storekeeper: '—', employee: '—' }],
  ['المبيعات والتسويق', { owner: '✓', admin: '✓', hr: '—', finance: '✓', manager: '—', accountant: '◐', storekeeper: '—', employee: '—' }],
  ['المشتريات', { owner: '✓', admin: '✓', hr: '—', finance: '✓', manager: 'طلب شراء', accountant: '◐', storekeeper: '◐', employee: '—' }],
  ['المخزون', { owner: '✓', admin: '✓', hr: '—', finance: '✓', manager: '—', accountant: '◐', storekeeper: '◐', employee: '—' }],
  ['المشاريع', { owner: '✓', admin: '✓', hr: '—', finance: '✓', manager: '—', accountant: '◐', storekeeper: '—', employee: '—' }],
  ['إعدادات المنشأة والمستخدمون', { owner: '✓', admin: '✓', hr: 'المستخدمون', finance: 'المالية', manager: '—', accountant: '—', storekeeper: '—', employee: '—' }]];
VIEWS['#/permissions'] = async page => {
  if (!(isHR() || can('settings'))) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للمالك ومدير النظام والموارد البشرية والمدير المالي.'))}</div>`; return; }
  const [mem, em, mpr, fp, inv] = await Promise.all([db.get('members', { company_id: 'eq.' + S.cid, order: 'created_at' }), employeesMap(),
    isHR() ? db.get('member_perms', { company_id: 'eq.' + S.cid }).catch(() => []) : [], can('settings') ? db.get('finance_permissions', { company_id: 'eq.' + S.cid }).catch(() => []) : [],
    db.get('invites', { company_id: 'eq.' + S.cid, select: 'email,accepted_by' }).catch(() => [])]);
  const mp = {}; mpr.forEach(x => (mp[x.user_id] = mp[x.user_id] || []).push(x.perm));
  const mail = {}; inv.forEach(i => { if (i.accepted_by) mail[i.accepted_by] = i.email; }); mail[S.session.user.id] = S.session.user.email;
  const who = m => mail[m.user_id] || (m.employee_id && em[m.employee_id] ? em[m.employee_id].full_name : '—');
  const canAcc = m => isHR() && m.user_id !== S.session.user.id && m.role !== 'owner' && (has('owner', 'admin') || !rolesOf(m).some(r => r === 'hr' || r === 'admin'));
  const on = (r, p) => fp.some(x => x.role === r && x.perm === p);
  const roles = ['owner', 'admin', 'hr', 'finance', 'manager', 'accountant', 'storekeeper', 'employee'];
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الصلاحيات'))}</h1><div class="muted">${esc(tr('كل صلاحيات المنشأة في مكان واحد: من يرى ماذا في كل قسم، وصلاحيات كل شخص. كل تغيير يُحفظ في سجل التدقيق.'))}</div></div>
      ${has('owner', 'admin', 'hr') ? `<a class="btn" href="#/users">${esc(tr('المستخدمون والدعوات'))}</a>` : ''}</div>
    ${isHR() ? `<div class="card"><h2>${esc(tr('صلاحيات كل شخص'))}</h2><p class="muted small" style="margin-top:0">${esc(tr('اضغط «تعديل الصلاحيات» لتحدد أدوار الشخص (يمكن أكثر من دور) وصلاحياته الخاصة. الصلاحيات الخاصة تحل محل صلاحيات دوره في المالية والمخزون.'))}</p>
      ${tbl([{ t: 'المستخدم', h: m => `<b>${esc(m.employee_id && em[m.employee_id] ? em[m.employee_id].full_name : '')}</b> <span class="small muted num" dir="ltr">${esc(mail[m.user_id] || '')}</span>` },
        { t: 'الأدوار', h: m => rolesOf(m).map(r => `<span class="badge${r === 'owner' ? ' info' : ''}">${esc(tr(ROLES[r] || r))}</span>`).join(' ') },
        { t: 'صلاحيات خاصة', h: m => (mp[m.user_id] || []).length ? `<span class="small">${mp[m.user_id].map(p => esc(tr(FPERMS[p] || p))).join('، ')}</span>` : `<span class="muted small">${esc(tr('حسب الدور'))}</span>` },
        { t: '', h: m => canAcc(m) ? `<button class="btn sm pri" data-pacc="${m.user_id}">${esc(tr('تعديل الصلاحيات'))}</button>` : '' }], mem)}</div>` : ''}
    ${can('settings') ? `<div class="card"><h2>${esc(tr('صلاحيات الأدوار حسب القسم'))}</h2><p class="muted small" style="margin-top:0">${esc(tr('المالك والمدير المالي يرون كل شيء. حدّد هنا ما يراه المحاسب وأمين المستودع في كل قسم، ما لم تكن للشخص صلاحيات خاصة.'))}</p>
      <div class="tw"><table><thead><tr><th>${esc(tr('الصلاحيات'))}</th><th class="c">${esc(tr('محاسب'))}</th><th class="c">${esc(tr('أمين مستودع'))}</th></tr></thead><tbody>
      ${PERM_DEPTS.map(([d, ps]) => `<tr class="pgrp"><td colspan="3"><b>${esc(tr(d))}</b></td></tr>` + ps.filter(p => FPERMS[p]).map(p => `<tr><td>${esc(tr(FPERMS[p]))}</td>${['accountant', 'storekeeper'].map(r => `<td class="c"><input type="checkbox" data-r="${r}" data-p="${p}" ${on(r, p) ? 'checked' : ''} aria-label="${esc(tr(FPERMS[p]) + ' — ' + tr(ROLES[r]))}"></td>`).join('')}</tr>`).join('')).join('')}
      </tbody></table></div></div>` : ''}
    <div class="card"><h2>${esc(tr('ماذا يرى كل دور'))}</h2><p class="muted small" style="margin-top:0">${esc(tr('✓ كل القسم · ◐ حسب الصلاحيات المحددة · — لا يرى القسم'))}</p>
      <div class="tw"><table><thead><tr><th>${esc(tr('القسم'))}</th>${roles.map(r => `<th class="c small">${esc(tr(ROLES[r]))}</th>`).join('')}</tr></thead><tbody>
      ${ROLE_MAP.map(([d, m]) => `<tr><td>${esc(tr(d))}</td>${roles.map(r => `<td class="c small">${esc(m[r].length > 1 ? tr(m[r]) : m[r])}</td>`).join('')}</tr>`).join('')}</tbody></table></div>
      <p class="muted small">${esc(tr('مسار اعتماد كل نوع طلب ومن يرفع طلبات الشراء يُحددان في «مسارات الاعتماد».'))} ${isHR() ? `<a href="#/workflows">${esc(tr('مسارات الاعتماد'))}</a>` : ''}</p></div>`;
  $$('[data-pacc]', page).forEach(b => b.onclick = () => { const m = mem.find(x => x.user_id === b.dataset.pacc); accessDialog(m, who(m), mp[m.user_id] || []); });
  $$('input[data-p]', page).forEach(c => c.onchange = async () => { try { await db.rpc('set_finance_permission', { p_company: S.cid, p_role: c.dataset.r, p_perm: c.dataset.p, p_allowed: c.checked }); toast(tr('تم الحفظ')); } catch (e) { c.checked = !c.checked; toast(e.message); } });
};
