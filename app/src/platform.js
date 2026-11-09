'use strict';
/* Platform admin panel (Waad's own team only): subscriptions of every company — metadata only, no company records. */
const SUB_ST = { trial: ['تجربة', 'wait'], active: ['مفعّلة', 'ok'], suspended: ['موقوفة', 'bad'] };
const subState = c => c.status === 'trial' && c.trial_ends && c.trial_ends < today() ? ['انتهت التجربة', 'bad'] : SUB_ST[c.status] || [c.status, ''];
async function platformView() {
  const app = $('#app');
  app.innerHTML = `<div class="plat"><header class="top"><div class="brand">${brand()}</div><div class="cname"><b>${esc(tr('لوحة إدارة المنصة'))}</b></div><div class="sp"></div>
      ${S.companies && S.companies.length ? `<a class="btn sm" href="#/home" id="pback">${esc(tr('العودة إلى منشأتي'))}</a>` : ''}
      <button class="btn sm" id="pmfa">${esc(tr('التحقق بخطوتين'))}</button>${langBtn('btn sm')}<button class="btn sm" id="plo">${esc(tr('تسجيل الخروج'))}</button></header>
    <main class="page" id="ppage"><div class="muted">${esc(tr('جارٍ التحميل…'))}</div></main></div>`;
  $('#plo').onclick = async () => { await authApi.signOut(); S.platform = false; authView(); };
  $('#pmfa').onclick = () => mfaSetup();
  $('#lg').onclick = () => setLang(LANG === 'en' ? 'ar' : 'en');
  if ($('#pback')) $('#pback').onclick = e => { e.preventDefault(); location.hash = '#/home'; boot(); };
  const page = $('#ppage');
  try {
    const [rows, st] = await Promise.all([db.rpc('platform_companies'), db.rpc('platform_get_settings')]);
    const live = rows.filter(c => subState(c)[1] !== 'bad'), q = (LS.get('waad.platq') || '').toLowerCase();
    const shown = rows.filter(c => !q || (c.name + ' ' + (c.owner_email || '') + ' ' + c.plan).toLowerCase().includes(q));
    page.innerHTML = `<div class="head"><div><h1>${esc(tr('المنشآت والاشتراكات'))}</h1><div class="muted">${esc(tr('بيانات الاشتراك فقط — لا تظهر هنا بيانات المنشآت نفسها.'))}</div></div></div>
      <div class="grid" style="margin-bottom:14px">
        <div class="card kpi"><div class="muted small">${esc(tr('المنشآت'))}</div><div class="v num">${rows.length}</div></div>
        <div class="card kpi"><div class="muted small">${esc(tr('مفعّلة'))}</div><div class="v num">${rows.filter(c => c.status === 'active').length}</div></div>
        <div class="card kpi"><div class="muted small">${esc(tr('تجربة'))}</div><div class="v num">${rows.filter(c => c.status === 'trial' && subState(c)[1] !== 'bad').length}</div></div>
        <div class="card kpi"><div class="muted small">${esc(tr('مغلقة (موقوفة أو انتهت تجربتها)'))}</div><div class="v num">${rows.length - live.length}</div></div>
        <div class="card kpi"><div class="muted small">${esc(tr('المستخدمون'))}</div><div class="v num">${rows.reduce((a, c) => a + (c.users || 0), 0)}</div></div></div>
      <div class="row" style="margin-bottom:10px"><input id="pq" placeholder="${esc(tr('بحث بالاسم أو البريد أو الباقة'))}" value="${esc(q)}" style="max-width:320px"></div>
      ${tbl([{ t: 'المنشأة', h: c => esc(c.name) + `<div class="small muted" dir="ltr">${esc(c.owner_email || '—')}</div>` }, { t: 'الباقة', h: c => esc(c.plan) },
        { t: 'الأقسام', h: c => (c.modules || []).map(m => `<span class="badge">${esc(tr(MODULES[m] || m))}</span>`).join(' ') },
        { t: 'الحالة', h: c => { const [t, k] = subState(c); return `<span class="badge ${k}">${esc(tr(t))}</span>` + (c.status === 'trial' && c.trial_ends ? ` <span class="small num">${esc(c.trial_ends)}</span>` : ''); } },
        { t: 'المستخدمون', r: 1, h: c => `<span class="num">${c.users}${c.max_users ? ' / ' + c.max_users : ''}</span>` },
        { t: 'آخر دخول', h: c => c.last_sign_in ? `<span class="num">${esc(String(c.last_sign_in).slice(0, 10))}</span>` : '—' },
        { t: 'التسجيل', h: c => `<span class="num">${esc(String(c.created_at).slice(0, 10))}</span>` }], shown, { empty: 'لا توجد منشآت', onRow: true })}
      <div class="card" style="margin-top:16px"><h2>${esc(tr('إعدادات المنشآت الجديدة'))}</h2>
        <form id="psf" class="fg">${field('الأقسام المفتوحة عند التسجيل', modChecks(st.default_modules), 'wide')}
        ${field('مدة التجربة بالأيام (فارغ = بدون حد)', inp('days', st.default_trial_days, 'type="number" min="1" max="365"'))}
        <div class="wide"><div id="pserr"></div><button class="btn pri" id="psb">${esc(tr('حفظ'))}</button></div></form></div>`;
    $('#pq', page).oninput = e => { LS.set('waad.platq', e.target.value); clearTimeout(platformView.t); platformView.t = setTimeout(platformView, 400); };
    bindRows(page, shown, subForm);
    $('#psf', page).onsubmit = async e => { e.preventDefault(); const f = e.target;
      try { await busy($('#psb', page), async () => { await db.rpc('platform_set_settings', { p_modules: pickMods(f), p_trial_days: f.days.value ? +f.days.value : null }); toast(tr('تم الحفظ')); }); }
      catch (er) { showErr($('#pserr', page), er); } };
  } catch (e) { page.innerHTML = `<div class="err">${esc(e.message)}</div>`; }
}
const modChecks = (sel, prefix = 'm') => `<div class="row" style="gap:14px;flex-wrap:wrap">${Object.entries(MODULES).map(([k, t]) =>
  `<label class="row" style="gap:6px"><input type="checkbox" name="${prefix}_${k}" ${(sel || []).includes(k) ? 'checked' : ''} style="width:auto"> ${esc(tr(t))}</label>`).join('')}</div>`;
const pickMods = (f, prefix = 'm') => Object.keys(MODULES).filter(k => f.elements[prefix + '_' + k] && f.elements[prefix + '_' + k].checked);
function subForm(c) {
  modal(tr('اشتراك') + ': ' + c.name, `<div class="fg">${field('اسم الباقة', inp('plan', c.plan, 'maxlength="40" list="plans"') + '<datalist id="plans"><option value="الموارد البشرية"><option value="المالية"><option value="الشاملة"><option value="trial"></datalist>')}
      ${field('الحالة', `<select name="status">${Object.entries(SUB_ST).map(([k, [t]]) => opt(k, tr(t), c.status)).join('')}</select>`)}
      ${field('الأقسام المفتوحة', modChecks(c.modules), 'wide')}
      ${field('نهاية التجربة (للحالة «تجربة»)', `<input type="date" name="trial_ends" value="${esc(c.trial_ends || '')}">`)}
      ${field('الحد الأعلى للمستخدمين (فارغ = بدون حد)', inp('max_users', c.max_users, 'type="number" min="1"'))}
      ${field('ملاحظة داخلية', inp('note', c.note), 'wide')}</div>
    <p class="muted small">${esc(tr('التغيير يظهر في سجل التدقيق الخاص بالمنشأة. إغلاق قسم لا يحذف بياناته — تعود عند فتحه.'))}</p>`, {
    wide: true, onOk: async (f, d) => {
      const mods = pickMods($('#mform', d) || d.querySelector('form'));
      if (!mods.length) throw new Error('اختر قسماً واحداً على الأقل');
      await db.rpc('platform_set_subscription', { p_company: c.company_id, p_plan: f.plan, p_modules: mods, p_status: f.status, p_trial_ends: f.trial_ends || null, p_max_users: f.max_users ? +f.max_users : null, p_note: f.note || null });
      toast(tr('تم الحفظ')); platformView();
    } });
}
