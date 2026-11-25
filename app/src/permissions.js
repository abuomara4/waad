'use strict';
/* ===== «الصلاحيات»: every permission in one page, set by HR (0111, 0112) =====
   The owner, the system admin, the finance manager and HR always have everything (fixed). HR — or the deputy the HR
   manager names (companies.perm_deputy) — sets what every other job sees and does:
   1) people: each user's roles and personal permissions, edited with accessDialog (hr.js);
   2) job permissions by department (finance_permissions), the HR section included (hr_*);
   3) a map of what each role covers in each department. */
const PERM_DEPTS = [
  ['المبيعات والتسويق', ['sales', 'mkt', 'void']],
  ['المشتريات', ['purch']],
  ['المخزون', ['stock', 'stockadj', 'items']],
  ['المالية والمحاسبة', ['dash', 'je', 'jepost', 'ledger', 'reports', 'vat', 'coa', 'payroll', 'settings']],
  ['المشاريع', ['proj']],
  ['الموارد البشرية', ['hr_emp', 'hr_att', 'hr_pay', 'hr_disc', 'hr_recruit', 'hr_train', 'hr_ann', 'hr_cdocs']]];
// what each role covers, per department (✓ all, ◐ by permission, — none)
const PERM_ROLES = ['manager', 'accountant', 'storekeeper', 'employee'];   // the jobs whose permissions HR sets (0112)
const ROLE_MAP = [
  ['الموارد البشرية', { owner: '✓', admin: '✓', hr: '✓', finance: '✓', manager: '◐', accountant: '◐', storekeeper: '◐', employee: '◐' }],
  ['الاعتمادات', { owner: '✓', admin: '✓', hr: '✓', finance: 'المبالغ', manager: 'فريقه', accountant: '—', storekeeper: '—', employee: 'طلباته' }],
  ['المالية والمحاسبة', { owner: '✓', admin: '✓', hr: '✓', finance: '✓', manager: '◐', accountant: '◐', storekeeper: '◐', employee: '◐' }],
  ['المبيعات والتسويق', { owner: '✓', admin: '✓', hr: '✓', finance: '✓', manager: '◐', accountant: '◐', storekeeper: '◐', employee: '◐' }],
  ['المشتريات', { owner: '✓', admin: '✓', hr: '✓', finance: '✓', manager: '◐', accountant: '◐', storekeeper: '◐', employee: '◐' }],
  ['المخزون', { owner: '✓', admin: '✓', hr: '✓', finance: '✓', manager: '◐', accountant: '◐', storekeeper: '◐', employee: '◐' }],
  ['المشاريع', { owner: '✓', admin: '✓', hr: '✓', finance: '✓', manager: '◐', accountant: '◐', storekeeper: '◐', employee: '◐' }],
  ['إعدادات المنشأة والمستخدمون', { owner: '✓', admin: '✓', hr: 'المستخدمون والصلاحيات', finance: 'المالية', manager: '—', accountant: '—', storekeeper: '—', employee: '—' }]];
VIEWS['#/permissions'] = async page => {
  const deputy = !!(S.company && S.company.perm_deputy && S.company.perm_deputy === S.session.user.id);
  if (!(isHR() || deputy)) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للموارد البشرية ومن ينوب عنها.'))}</div>`; return; }
  const editGrid = true;
  const [mem, em, mpr, fp, inv] = await Promise.all([db.get('members', { company_id: 'eq.' + S.cid, order: 'created_at' }), employeesMap(),
    isHR() ? db.get('member_perms', { company_id: 'eq.' + S.cid }).catch(() => []) : [], db.get('finance_permissions', { company_id: 'eq.' + S.cid }).catch(() => []),
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
    ${editGrid ? `<div class="card"><h2>${esc(tr('صلاحيات كل وظيفة حسب القسم'))}</h2><p class="muted small" style="margin-top:0">${esc(tr('حدد لكل وظيفة ما تراه وما تعمله في كل قسم. المالك ومدير النظام والمدير المالي والموارد البشرية يرون كل شيء دائما. الصلاحيات الخاصة لأي شخص تحل محل صلاحيات وظيفته.'))}</p>
      <div class="tw"><table class="permg"><thead><tr><th>${esc(tr('الصلاحيات'))}</th>${PERM_ROLES.map(r => `<th class="c small">${esc(tr(ROLES[r]))}</th>`).join('')}</tr></thead><tbody>
      ${PERM_DEPTS.map(([d, ps]) => `<tr class="pgrp"><td colspan="${PERM_ROLES.length + 1}"><b>${esc(tr(d))}</b></td></tr>` + ps.filter(p => FPERMS[p]).map(p => `<tr><td>${esc(tr(FPERMS[p]))}</td>${PERM_ROLES.map(r => `<td class="c"><input type="checkbox" data-r="${r}" data-p="${p}" ${on(r, p) ? 'checked' : ''} aria-label="${esc(tr(FPERMS[p]) + ' — ' + tr(ROLES[r]))}"></td>`).join('')}</tr>`).join('')).join('')}
      </tbody></table></div><p class="muted small">${esc(tr('تنبيه: ما تمنحه لوظيفة «موظف» يصل لكل الموظفين.'))}</p></div>` : ''}
    ${isHR() ? `<div class="card"><h2>${esc(tr('من ينوب عن الموارد البشرية في الصلاحيات'))}</h2><p class="muted small" style="margin-top:0">${esc(tr('اختر شخصا يحدد صلاحيات الوظائف نيابة عن مدير الموارد البشرية. لا يستطيع أن يغير أدوار الأشخاص.'))}</p>
      <div class="row" style="gap:8px;align-items:center"><select id="pdep" style="max-width:320px"><option value="">${esc(tr('لا أحد'))}</option>${mem.filter(m => m.role !== 'owner' && !rolesOf(m).some(r => ['admin', 'hr'].includes(r))).map(m => `<option value="${m.user_id}" ${S.company && S.company.perm_deputy === m.user_id ? 'selected' : ''}>${esc(who(m))}</option>`).join('')}</select>
      <button class="btn pri" id="pdepsave">${esc(tr('حفظ'))}</button></div></div>` : ''}
    <div class="card"><h2>${esc(tr('ماذا يرى كل دور'))}</h2><p class="muted small" style="margin-top:0">${esc(tr('✓ كل القسم · ◐ حسب الصلاحيات المحددة · — لا يرى القسم'))}</p>
      <div class="tw"><table><thead><tr><th>${esc(tr('القسم'))}</th>${roles.map(r => `<th class="c small">${esc(tr(ROLES[r]))}</th>`).join('')}</tr></thead><tbody>
      ${ROLE_MAP.map(([d, m]) => `<tr><td>${esc(tr(d))}</td>${roles.map(r => `<td class="c small">${esc(m[r].length > 1 ? tr(m[r]) : m[r])}</td>`).join('')}</tr>`).join('')}</tbody></table></div>
      <p class="muted small">${esc(tr('مسار اعتماد كل نوع طلب ومن يرفع طلبات الشراء يُحددان في «مسارات الاعتماد».'))} ${isHR() ? `<a href="#/workflows">${esc(tr('مسارات الاعتماد'))}</a>` : ''}</p></div>`;
  $('#pdepsave', page) && ($('#pdepsave', page).onclick = async () => { const v = $('#pdep', page).value || null; try { await db.rpc('perm_deputy_set', { p_company: S.cid, p_user: v }); S.company.perm_deputy = v; toast(tr('تم الحفظ')); } catch (e) { toast(e.message); } });
  $$('[data-pacc]', page).forEach(b => b.onclick = () => { const m = mem.find(x => x.user_id === b.dataset.pacc); accessDialog(m, who(m), mp[m.user_id] || []); });
  $$('input[data-p]', page).forEach(c => c.onchange = async () => { try { await db.rpc('set_finance_permission', { p_company: S.cid, p_role: c.dataset.r, p_perm: c.dataset.p, p_allowed: c.checked }); toast(tr('تم الحفظ')); } catch (e) { c.checked = !c.checked; toast(e.message); } });
};

/* ===== «سجل الوصول» (0128): who opened sensitive data. The owner and admins read it; nobody can edit it ===== */
const ACCESS_K = { employee: 'ملف موظف', payroll: 'مسير رواتب', payslip: 'قسيمة راتب', bank_file: 'ملف بنك أو حماية أجور', report: 'تقرير موارد بشرية', file: 'مرفق', export: 'تصدير بيانات المنشأة' };
VIEWS['#/accesslog'] = async (page, arg, q) => {
  if (!has('owner', 'admin')) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة لمالك المنشأة ومدير النظام.'))}</div>`; return; }
  const from = q.get('from') || addDays(today(), -30), to = q.get('to') || today(), k = q.get('k') || '';
  const f = Object.assign(C(), { order: 'at.desc', limit: 500, at: 'gte.' + from + 'T00:00:00' }); if (k) f.kind = 'eq.' + k;
  const all = await db.get('access_log', f), rows = all.filter(r => String(r.at).slice(0, 10) <= to);
  const go = () => location.hash = `#/accesslog?from=${$('#alf', page).value}&to=${$('#alt', page).value}&k=${$('#alk', page).value}`;
  const what = r => tr(ACCESS_K[r.kind]) + (r.employee_name ? ' — ' + r.employee_name : '') + (r.label ? ' — ' + (r.kind === 'file' ? r.label : tr(r.label)) : '');
  // the device from the browser's user agent: system and browser in two words
  const dev = u => { u = u || ''; if (!u) return ''; const os = /iPhone|iPad/.test(u) ? 'iPhone/iPad' : /Android/.test(u) ? 'Android' : /Windows/.test(u) ? 'Windows' : /Mac OS X/.test(u) ? 'Mac' : /Linux/.test(u) ? 'Linux' : '';
    const br = /Edg\//.test(u) ? 'Edge' : /OPR\//.test(u) ? 'Opera' : /Chrome\//.test(u) ? 'Chrome' : /Firefox\//.test(u) ? 'Firefox' : /Safari\//.test(u) ? 'Safari' : ''; return [os, br].filter(Boolean).join(' · ') || u.slice(0, 40); };
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('سجل الوصول'))}</h1><div class="muted small">${esc(tr('من فتح البيانات الحساسة ومتى. لا يمكن تعديله أو حذفه، ويبقى مع بيانات المنشأة ويدخل في تصديرها.'))}</div></div>
      <div class="row"><button class="btn" id="alx">${esc(tr('تنزيل CSV'))}</button></div></div>
    <div class="row" style="gap:6px;flex-wrap:wrap;margin-bottom:10px"><input type="date" id="alf" value="${esc(from)}" style="width:auto" aria-label="${esc(tr('من'))}"><input type="date" id="alt" value="${esc(to)}" style="width:auto" aria-label="${esc(tr('إلى'))}">
      <select id="alk" style="width:auto" aria-label="${esc(tr('النوع'))}"><option value="">${esc(tr('كل الأنواع'))}</option>${Object.keys(ACCESS_K).map(x => opt(x, tr(ACCESS_K[x]), k)).join('')}</select>
      <input id="alq" placeholder="${esc(tr('بحث بالاسم'))}" style="width:auto" aria-label="${esc(tr('بحث بالاسم'))}"></div>
    <div id="alb"></div><p class="muted small">${esc(tr('يسجل ما يُفتح من شاشات النظام وعمليات التصدير. فتح الشخص لبياناته هو لا يُسجل، وتكرار الفتح خلال 10 دقائق يُحسب مرة واحدة.'))}</p>`;
  const draw = () => { const t = $('#alq', page).value.trim(), r2w = rows.filter(r => !t || (String(r.actor_name || '') + ' ' + String(r.employee_name || '')).includes(t));
    $('#alb', page).innerHTML = tbl([{ t: 'الوقت', h: r => `<span class="num">${esc(String(r.at).slice(0, 16).replace('T', ' '))}</span>` }, { t: 'من', h: r => esc(r.actor_name || '') }, { t: 'ماذا فتح', h: r => esc(what(r)) }, { t: 'عنوان IP', h: r => `<span class="num" dir="ltr">${esc(r.ip || '—')}</span>` }, { t: 'الجهاز', h: r => `<span class="small" dir="ltr">${esc(dev(r.ua) || '—')}</span>` }], r2w, { empty: 'لا توجد سجلات في هذه الفترة' }); return r2w; };
  draw(); $('#alq', page).oninput = draw; ['#alf', '#alt', '#alk'].forEach(x => $(x, page).onchange = go);
  $('#alx', page).onclick = () => { const c = v => '"' + String(v == null ? '' : v).replace(/"/g, '""') + '"', csv = '\ufeff' + [[tr('الوقت'), tr('من'), tr('ماذا فتح'), tr('عنوان IP'), tr('الجهاز')].map(c).join(',')].concat(draw().map(r => [String(r.at).slice(0, 19).replace('T', ' '), r.actor_name, what(r), r.ip, dev(r.ua)].map(c).join(','))).join('\n');
    const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' })); a.download = 'waad-access-log.csv'; a.click(); };
};
