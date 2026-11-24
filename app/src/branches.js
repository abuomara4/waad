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

/* ===== «مجموعة المنشآت» (0140): several companies — separate legal entities with their own VAT number, books, GOSI and ZATCA —
   under one owner, who moves between them from one account. Each company keeps its own subscription. ===== */
// through boot(), so a company still waiting for approval shows its waiting page (with the way back to the others)
async function switchCompany(id, hash) { S.cid = id; LS.set('waad.cid', id); cache.branches = null; history.replaceState(null, '', hash || '#/home'); await boot(); }
async function groupCard(el) {
  const g = await db.rpc('my_group').catch(() => null);
  const ST = { pending: ['بانتظار الموافقة', 'warn'], trial: ['تجريبية', 'info'], active: ['فعّال', 'ok'], suspended: ['موقوف', 'bad'] };
  const st = c => c.status === 'trial' && c.trial_ends && c.trial_ends < today() ? ['انتهت التجربة', 'bad'] : c.status === 'active' && c.sub_ends && c.sub_ends < today() ? ['انتهى الاشتراك', 'bad'] : ST[c.status] || [c.status || '—', ''];
  if (!g) {
    if ((S.company || {}).group_id) { el.remove(); return; }   // in someone else's group: only its owner manages it
    el.innerHTML = `<h2>${esc(tr('مجموعة المنشآت'))}</h2>
      <p class="muted small">${esc(tr('إذا كان لديك أكثر من سجل تجاري مستقل (رقم ضريبي وتأمينات ودفاتر خاصة)، اجمعها في مجموعة: تنتقل بينها من حسابك نفسه، ولكل منشأة اشتراكها وبياناتها المنفصلة.'))}</p>
      <form id="gcf" class="row" style="gap:8px;flex-wrap:wrap"><input name="name" required maxlength="120" placeholder="${esc(tr('اسم المجموعة'))}" style="max-width:280px" value="${esc((S.company || {}).name || '')}">
        <button class="btn pri" id="gcb">${esc(tr('إنشاء مجموعة بهذه المنشأة'))}</button></form><div id="gerr"></div>`;
    $('#gcf', el).onsubmit = async e => { e.preventDefault(); const f = formData(e.target);
      try { await busy($('#gcb', el), async () => { await db.rpc('group_create', { p_company: S.cid, p_name: f.name }); toast(tr('تم إنشاء المجموعة')); await loadContext(); groupCard(el); }); }
      catch (er) { showErr($('#gerr', el), er); } };
    return;
  }
  el.innerHTML = `<div class="row" style="justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap"><h2 style="margin:0">${esc(tr('مجموعة المنشآت'))}: <span data-nt>${esc(g.name)}</span></h2>
      <div class="row" style="gap:6px"><button type="button" class="btn sm" id="grn">${esc(tr('تغيير الاسم'))}</button><button type="button" class="btn sm pri" id="gnc">${esc(tr('+ منشأة في المجموعة'))}</button></div></div>
    <p class="muted small">${esc(tr('كل منشأة كيان مستقل ببياناتها واشتراكها، وتنتقل بينها من قائمة المنشآت أعلى الشاشة.'))}</p>
    ${tbl([{ t: 'المنشأة', h: c => `<b data-nt>${esc(c.name)}</b>${c.id === S.cid ? ` <span class="badge info">${esc(tr('الحالية'))}</span>` : ''}<div class="small muted num">${esc(c.vat_no || '')}</div>` },
      { t: 'الاشتراك', h: c => `<span class="badge ${st(c)[1]}">${esc(tr(st(c)[0]))}</span>` },
      { t: '', h: c => c.id === S.cid ? '' : `${c.member ? `<button type="button" class="btn sm" data-gop="${c.id}">${esc(tr('فتح'))}</button> ` : ''}<button type="button" class="btn sm" data-grm="${c.id}">${esc(tr('إخراج من المجموعة'))}</button>` }], g.companies, {})}
    <p class="muted small">${esc(tr('القوائم الموحدة للمجموعة واستبعاد المعاملات بين شركاتها في المرحلة التالية.'))}</p>`;
  $('#grn', el).onclick = () => modal(tr('اسم المجموعة'), `<div class="fg">${field('الاسم', inp('name', g.name, 'required maxlength="120"'))}</div>`, {
    onOk: async f => { await db.rpc('group_rename', { p_group: g.id, p_name: f.name }); await loadContext(); shell(); route(); } });
  $$('[data-gop]', el).forEach(b => b.onclick = () => switchCompany(b.dataset.gop, '#/settings'));
  $$('[data-grm]', el).forEach(b => b.onclick = () => { const c = g.companies.find(x => x.id === b.dataset.grm);
    modal(tr('إخراج من المجموعة'), `<p><b data-nt>${esc(c.name)}</b></p><p class="muted small">${esc(tr('تبقى المنشأة كما هي ببياناتها واشتراكها، وتخرج فقط من المجموعة.'))}</p>`, {
      ok: 'إخراج', onOk: async () => { await db.rpc('group_company_remove', { p_company: c.id }); await loadContext(); shell(); route(); } }); });
  $('#gnc', el).onclick = () => modal(tr('منشأة جديدة في المجموعة'), `<div class="fg">${field('اسم المنشأة', inp('name', '', 'required maxlength="120"'))}
      ${field('الرقم الضريبي', inp('vat', '', 'dir="ltr" inputmode="numeric" maxlength="15"'))}${field('السجل التجاري', inp('cr', '', 'dir="ltr" inputmode="numeric" maxlength="10"'))}
      <label class="row small wide" style="gap:6px;align-items:flex-start"><input type="checkbox" name="xfer" style="width:auto;margin-top:4px"> <span>${esc(tr('أوافق على حفظ بيانات منشأتي وموظفيها وعملائها لدى مزوّد سحابي خارج المملكة (اليابان)، وأتحمّل إبلاغهم بذلك، كما في'))} <a href="#/privacy">${esc(tr('سياسة الخصوصية'))}</a>.</span></label></div>
    <p class="muted small">${esc(tr('تبدأ المنشأة الجديدة فارغة باشتراكها الخاص، مثل أي منشأة جديدة في وعد.'))}</p>`, {
    ok: 'إنشاء', onOk: async f => {
      if ((f.name || '').trim().length < 3) throw new Error('اسم المنشأة 3 أحرف على الأقل');
      if (f.vat && !/^3\d{13}3$/.test(f.vat)) throw new Error('الرقم الضريبي 15 رقما يبدأ وينتهي بـ 3');
      if (f.cr && !/^\d{10}$/.test(f.cr)) throw new Error('السجل التجاري 10 أرقام');
      if (!f.xfer) throw new Error('وافق على حفظ البيانات خارج المملكة لإكمال إنشاء المنشأة');
      const cid = await db.rpc('group_company_create', { p_group: g.id, p_name: f.name.trim(), p_vat: blank(f.vat), p_cr: blank(f.cr), p_consent: true });
      const co = S.company || {};   // the owner's details carry over (phone, size, sector)
      await db.upd('companies', { id: 'eq.' + cid }, { owner_phone: co.owner_phone || null, size_band: co.size_band || null, industry: co.industry || null, heard_from: co.heard_from || null }).catch(() => {});
      toast(tr('تم إنشاء المنشأة')); await switchCompany(cid, '#/home'); } });
}
