/* ===== Branches «الفروع» (0136): a branch is a plant / profit centre inside the company, with its own cost centre,
   warehouse and attendance site; staff, warehouses and money documents carry it (part 1 of the organisation structure) ===== */
const brName = b => b ? ((LANG === 'en' && b.name_en) || b.name) : '';
async function branchesList(force) { if (force || !cache.branches) cache.branches = await db.get('branches', { company_id: 'eq.' + S.cid, order: 'is_main.desc,code' }).catch(() => []);
  const n = cache.branches.filter(b => b.active).length; if (S.nBranches !== n) { S.nBranches = n; if (typeof drawNav === 'function' && $('#nav')) drawNav(); } return cache.branches; }
VIEWS['#/branches'] = async page => {
  if (!has('owner', 'admin', 'hr', 'finance')) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة لإدارة المنشأة.'))}</div>`; return; }
  const [rows, em, ccs, whs, mem] = await Promise.all([branchesList(true), employeesMap(), db.get('cost_centers', { company_id: 'eq.' + S.cid, select: 'id,code' }).catch(() => []),
    db.get('warehouses', { company_id: 'eq.' + S.cid, select: 'id,code,name' }).catch(() => []), db.get('members', { company_id: 'eq.' + S.cid, select: 'user_id,branch_id' }).catch(() => [])]);
  const ccm = {}; ccs.forEach(c => ccm[c.id] = c.code); const whm = {}; whs.forEach(w => whm[w.id] = w.code);
  const staff = id => Object.values(em).filter(e => e.branch_id === id && (!e.end_date || e.end_date >= today())).length, users = id => mem.filter(m => m.branch_id === id).length;
  const admin = has('owner', 'admin');
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الفروع'))}</h1><div class="muted">${esc(tr('لكل فرع مركز تكلفة ومستودع خاصان به، فتظهر نتائجه في الدفاتر والتقارير، ويأخذ كل مستند فرع المستخدم الذي أنشأه.'))}</div></div>
      ${admin ? `<button class="btn pri" id="brn">${esc(tr('+ فرع'))}</button>` : ''}</div>
    ${tbl([{ t: 'الفرع', h: b => `<b class="num">${esc(b.code)}</b> <span data-nt>${esc(brName(b))}</span>${b.is_main ? ` <span class="badge info">${esc(tr('الرئيسي'))}</span>` : ''}${b.active ? '' : ` <span class="badge">${esc(tr('موقوف'))}</span>`}<div class="small muted">${esc(b.city || '')}</div>` },
      { t: 'المدير', h: b => esc(b.manager_id && em[b.manager_id] ? em[b.manager_id].full_name : '—') }, { t: 'الموظفون', r: 1, h: b => `<span class="num">${staff(b.id)}</span>` }, { t: 'المستخدمون', r: 1, h: b => `<span class="num">${users(b.id)}</span>` },
      { t: 'مركز التكلفة', h: b => `<span class="num">${esc(ccm[b.cost_center_id] || '—')}</span>` }, { t: 'المستودع', h: b => `<span class="num">${esc(whm[b.warehouse_id] || '—')}</span>` }], rows, { empty: 'لا توجد فروع بعد — المنشأة تعمل كفرع واحد', onRow: admin })}`;
  if (!admin) return;
  bindRows(page, rows, b => form(b)); $('#brn', page).onclick = () => form(null);
  function form(b) {
    const v = b || { is_main: !rows.length, active: true }, emps = Object.values(em).filter(e => !e.end_date || e.end_date >= today());
    modal(b ? tr('الفرع') + ' ' + b.code : tr('فرع جديد'), `<div class="fg">${field('رمز الفرع', inp('code', v.code, `required dir="ltr" maxlength="12" style="text-transform:uppercase" ${b ? 'readonly' : ''} placeholder="RUH"`))}
        ${field('اسم الفرع', inp('name', v.name, 'required maxlength="120"'))}${enF('name_en', v.name_en)}${field('المدينة', inp('city', v.city, 'maxlength="80"'))}
        ${field('العنوان', inp('address', v.address, 'maxlength="300"'), 'wide')}${field('الرقم الفرعي للسجل التجاري (اختياري)', inp('cr_sub', v.cr_sub, 'dir="ltr" inputmode="numeric" maxlength="10"'))}${field('هاتف الفرع', inp('phone', v.phone, 'dir="ltr" maxlength="20"'))}
        ${field('مدير الفرع', `<select name="manager_id"><option value="">—</option>${emps.map(e => opt(e.id, e.emp_no + ' — ' + e.full_name, v.manager_id)).join('')}</select>`)}
        <label class="row small" style="gap:6px"><input type="checkbox" name="is_main" style="width:auto"${v.is_main ? ' checked' : ''}> ${esc(tr('الفرع الرئيسي'))}</label>
        ${b ? `<label class="row small" style="gap:6px"><input type="checkbox" name="active" style="width:auto"${v.active ? ' checked' : ''}> ${esc(tr('الفرع نشط'))}</label>` : ''}</div>
      ${b ? '' : `<p class="muted small">${esc(tr('يُنشأ مع الفرع مركز تكلفة ومستودع برمز BR- ثم رمز الفرع.'))}</p>`}`, {
      onOk: async f => { if (f.cr_sub && !/^\d{10}$/.test(f.cr_sub)) throw new Error(tr('الرقم الفرعي للسجل 10 أرقام'));
        await db.rpc('branch_save', { p_company: S.cid, p: { code: (f.code || '').trim().toUpperCase(), name: f.name, name_en: f.name_en, city: f.city, address: f.address, cr_sub: f.cr_sub, phone: f.phone, manager_id: f.manager_id, is_main: !!f.is_main, active: b ? !!f.active : true }, p_id: b ? b.id : null });
        cache.branches = null; toast(tr('تم الحفظ')); route(); } });
  }
};
