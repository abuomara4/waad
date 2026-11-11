'use strict';
/* The admin site (site/admin/, Waad's own team only): companies and subscriptions, system numbers, website visitors,
   website texts, and announcements to every company. Metadata only: no company records are ever read here. */
const SUB_ST = { pending: ['بانتظار القبول', 'info'], trial: ['تجربة', 'wait'], active: ['مفعّلة', 'ok'], suspended: ['موقوفة', 'bad'] };
const subState = c => c.status === 'trial' && c.trial_ends && c.trial_ends < today() ? ['انتهت التجربة', 'bad']
  : c.status === 'active' && c.sub_ends && c.sub_ends < today() ? ['انتهى الاشتراك', 'bad'] : SUB_ST[c.status] || [c.status, ''];
const subEnd = c => c.status === 'trial' ? c.trial_ends : c.status === 'active' ? c.sub_ends : null;
const daysLeft = d => d ? Math.round((new Date(d + 'T12:00:00Z') - new Date(today() + 'T12:00:00Z')) / 864e5) : null;
const PTABS = [['home', 'الرئيسية'], ['companies', 'المنشآت'], ['support', 'طلبات الدعم'], ['billing', 'الإيرادات والباقات'], ['system', 'أرقام النظام'], ['errors', 'أخطاء النظام'], ['site', 'زوار الموقع'], ['content', 'محتوى الموقع'], ['news', 'الإعلانات'], ['team', 'فريق وعد']];
const PV = {};   // tab id -> async (page, arg) => void   (#/company/<id> opens one company)
const money0 = n => Number(n || 0).toLocaleString('en-US', { maximumFractionDigits: 2 });
const MONTH0 = () => today().slice(0, 8) + '01';
const PAY_M = { transfer: 'تحويل بنكي', card: 'بطاقة', cash: 'نقداً', other: 'أخرى' };
const CH_N = { email: ['إيميل', '✉'], whatsapp: ['واتساب', '💬'], call: ['اتصال', '📞'], meeting: ['مقابلة حضورية', '🤝'], other: ['أخرى', '📝'] };
// quick actions on a company (list, home and company page); each re-draws the current screen
async function quickAct(c, act, days, st) {
  if (act === 'approve') { await db.rpc('platform_approve', { p_company: c.company_id, p_status: 'trial', p_days: (st && st.default_trial_days) || 7 }); toast(tr('تم القبول')); }
  else if (act === 'suspend') { if (!(await confirmBox(tr('إيقاف المنشأة'), tr('تنقفل كل الأقسام لين تعيد تفعيلها، وبياناتها ما تنحذف.') + ' ' + c.name, tr('إيقاف')))) return; await db.rpc('platform_quick', { p_company: c.company_id, p_action: 'suspend' }); toast(tr('تم الإيقاف')); }
  else { await db.rpc('platform_quick', { p_company: c.company_id, p_action: act, p_days: days || null }); toast(tr('تم الحفظ')); }
  platformView();
}
const quickBtns = c => { const b = (a, t, d) => `<button type="button" class="btn sm" data-q="${a}" data-d="${d || ''}" data-c="${esc(c.company_id)}">${esc(tr(t))}</button>`;
  return c.status === 'pending' ? b('approve', 'قبول تجربة') : c.status === 'suspended' ? b('resume', 'إعادة تفعيل')
    : b('extend', '+٧ أيام', 7) + ' ' + b('extend', '+٣٠ يوم', 30); };
function bindQuick(root, rows, st) {
  $$('[data-q]', root).forEach(btn => btn.onclick = async ev => { ev.stopPropagation();
    const c = rows.find(x => x.company_id === btn.dataset.c); if (!c) return;
    try { await quickAct(c, btn.dataset.q, +btn.dataset.d || null, st); } catch (e) { toast(e.message); } });
}
const dayAgo = n => new Date(new Date(today() + 'T12:00:00Z').getTime() - n * 864e5).toISOString().slice(0, 10);
const pct = (a, b) => b ? Math.round(a * 100 / b) + '%' : '—';
const pkpi = (label, v, sub = '') => `<div class="card kpi"><div class="muted small">${esc(tr(label))}</div><div class="v num">${v}</div>${sub ? `<div class="small muted">${esc(tr(sub))}</div>` : ''}</div>`;
// a simple daily bar chart: one bar per day, the first and last dates under it
function pbars(pts, label) {
  const mx = Math.max(1, ...pts.map(p => p.v));
  return `<div class="pbars" role="img" aria-label="${esc(tr(label))}">${pts.map(p => `<div class="pb" title="${esc(p.k)}: ${p.v}"><i style="height:${p.v ? Math.max(4, Math.round(p.v / mx * 100)) : 0}%"></i></div>`).join('')}</div>
    <div class="pbx small muted"><span class="num">${esc(pts[0].k)}</span><span class="num">${esc(pts[pts.length - 1].k)}</span></div>`;
}

const waTo = p => p ? 'https://wa.me/966' + String(p).replace(/^0/, '') : '';
const phoneBtns = p => p ? `<a class="btn sm pri" href="${esc(waTo(p))}" target="_blank" rel="noopener">${esc(tr('واتساب'))}</a> <a class="btn sm" href="tel:+966${esc(String(p).replace(/^0/, ''))}">${esc(tr('اتصال'))}</a>` : '';
const gmailTo = (to, su) => 'https://mail.google.com/mail/?view=cm&fs=1&to=' + encodeURIComponent(to) + (su ? '&su=' + encodeURIComponent(su) : '');
const mailBtns = (to, su) => to ? `<a class="btn sm pri" href="${esc(gmailTo(to, su))}" target="_blank" rel="noopener">${esc(tr('مراسلة عبر Gmail'))}</a>
  <a class="btn sm" href="mailto:${esc(to)}${su ? '?subject=' + encodeURIComponent(su) : ''}">${esc(tr('تطبيق البريد'))}</a>
  <button type="button" class="btn sm" data-copymail="${esc(to)}">${esc(tr('نسخ الإيميل'))}</button>` : `<span class="muted small">${esc(tr('ما فيه إيميل للمالك'))}</span>`;
function bindCopy(root) {
  $$('[data-copymail]', root).forEach(b => b.onclick = async () => {
    try { await navigator.clipboard.writeText(b.dataset.copymail); toast(tr('تم النسخ')); } catch (e) { prompt('', b.dataset.copymail); } });
}
async function platformView() {
  LS.set('waad.nocount', true);   // the team's own visits to the website are not counted (same browser, same site)
  const m = location.hash.match(/^#\/(\w+)(?:\/([\w-]+))?/) || [], tab = m[1], arg = m[2], cur = PV[tab] ? tab : 'home', nav = cur === 'company' ? 'companies' : cur;
  const app = $('#app');
  if (!$('#ppage')) {
    app.innerHTML = `<div class="plat"><header class="top"><div class="brand">${brand()}</div><div class="cname"><b>${esc(tr('لوحة إدارة وعد'))}</b></div><div class="sp"></div>
        <a class="btn sm" href="${SITE_URL}" target="_blank" rel="noopener">${esc(tr('الموقع'))}</a><a class="btn sm" href="${APP_URL}" target="_blank" rel="noopener">${esc(tr('النظام'))}</a>
        <button class="btn sm" id="pth" data-theme-btn="icon"></button><button class="btn sm" id="ppw">${esc(tr('تغيير كلمة المرور'))}</button><button class="btn sm" id="pmfa">${esc(tr('التحقق بخطوتين'))}</button>${langBtn('btn sm')}<button class="btn sm" id="plo">${esc(tr('تسجيل الخروج'))}</button></header>
      <nav class="ptabs" id="ptabs" aria-label="${esc(tr('أقسام اللوحة'))}"></nav>
      <main class="page" id="ppage"></main></div>`;
    $('#plo').onclick = async () => { await authApi.signOut(); S.platform = false; authView(); };
    $('#pmfa').onclick = () => mfaSetup();
    $('#ppw').onclick = () => changePasswordView(false);
    $('#pth').onclick = toggleTheme; applyTheme(curTheme());
    $('#lg').onclick = () => setLang(LANG === 'en' ? 'ar' : 'en');
  }
  $('#ptabs').innerHTML = PTABS.map(([k, t]) => `<a href="#/${k}"${k === nav ? ' aria-current="page"' : ''}>${esc(tr(t))}</a>`).join('');
  const page = $('#ppage'); page.innerHTML = `<div class="muted">${esc(tr('جارٍ التحميل…'))}</div>`;
  try { await PV[cur](page, arg); } catch (e) { if (page.isConnected) page.innerHTML = `<div class="err">${esc(e.message)}</div>`; }
}
// sign-in for the Waad team: a username and a password (internal address <username>@admin.waad.app, never mailed).
// ?setup creates the very first account; it becomes an admin only once it is activated.
function adminAuthView(msg = '') {
  const setup = new URLSearchParams(location.search).has('setup');
  $('#app').innerHTML = `<div class="auth"><div class="abox">${brand()}<div class="card">
    <h2>${esc(tr(setup ? 'إنشاء حساب لفريق وعد' : 'لوحة إدارة وعد'))}</h2>
    <p class="muted small" style="margin-top:0">${esc(tr(setup ? 'الحساب ما يصير أدمن إلا بعد تفعيله.' : 'لفريق وعد فقط.'))}</p>
    ${msg ? `<div class="note">${esc(msg)}</div>` : ''}
    <form id="af" novalidate>${field('اسم المستخدم', '<input name="user" required dir="ltr" autocapitalize="none" autocomplete="username" spellcheck="false">')}<div style="height:10px"></div>
      ${field('كلمة المرور', pwInput('password', setup ? 'new-password' : 'current-password'))}
      ${setup ? `<div style="height:10px"></div>${field('تأكيد كلمة المرور', pwInput('password2', 'new-password', ''))}` : ''}
      <div id="aerr"></div><div style="height:12px"></div><button class="btn pri full" id="ab">${esc(tr(setup ? 'إنشاء الحساب' : 'دخول'))}</button>
      ${setup ? '' : `<p class="muted small" style="margin:10px 0 0;text-align:center">${esc(tr('نسيت كلمة المرور؟ يعيّنها لك أدمن ثاني من «فريق وعد».'))}</p>`}</form></div>
    <p class="muted small" style="text-align:center"><a href="#" id="theme" data-theme-btn="text"></a> · ${langBtn('linkbtn')}</p>
    <p class="muted small afoot"><a href="${SITE_URL}">${esc(tr('← الموقع الرئيسي'))}</a></p></div></div>`;
  $('#lg').onclick = () => setLang(LANG === 'en' ? 'ar' : 'en');
  $('#theme').onclick = e => { e.preventDefault(); toggleTheme(); }; applyTheme(curTheme());
  $('#af').onsubmit = async e => { e.preventDefault(); const f = formData(e.target), u = (f.user || '').trim().toLowerCase();
    try { await busy($('#ab'), async () => {
      if (setup) {
        if (!/^[a-z0-9._-]{3,30}$/.test(u)) throw new Error('اسم المستخدم من ٣ إلى ٣٠ حرفاً إنجليزياً أو رقماً');
        if ((f.password || '').length < 8) throw new Error('كلمة المرور 8 أحرف على الأقل');
        if (f.password !== f.password2) throw new Error('كلمتا المرور غير متطابقتين');
        const r = await authApi.createStaff(adminEmail(u), f.password);
        if (r.existed) throw new Error('اسم المستخدم محجوز، اختر اسماً آخر');
        history.replaceState(null, '', location.pathname);
        return adminAuthView(tr('تم إنشاء الحساب') + ': ' + u + '. ' + tr('يصير أدمن بعد التفعيل، وبعدها ادخل من هنا.'));
      }
      await authApi.signIn(u.includes('@') ? u : adminEmail(u), f.password); return boot(); }); }
    catch (er) { showErr('#aerr', er); } };
}
// the admin site needs two-step verification: a team member without it sets it up here first
function adminMfaView() {
  $('#app').innerHTML = `<div class="auth"><div class="abox">${brand()}<div class="card"><h2>${esc(tr('فعّل التحقق بخطوتين'))}</h2>
    <p>${esc(tr('لوحة الإدارة تتحكم في اشتراكات كل المنشآت، فما تفتح إلا بعد تفعيل التحقق بخطوتين لحسابك.'))}</p>
    <p class="muted small">${esc(tr('تحتاج تطبيق مصادقة في جوالك مثل Google Authenticator أو Microsoft Authenticator. بعدها كل دخول يطلب رمز من التطبيق.'))}</p>
    <div class="row" style="gap:8px;flex-wrap:wrap"><button class="btn pri" id="pmfs">${esc(tr('ابدأ التفعيل'))}</button><button class="btn" id="plo">${esc(tr('تسجيل الخروج'))}</button></div></div></div></div>`;
  $('#pmfs').onclick = () => mfaSetup();
  $('#plo').onclick = async () => { await authApi.signOut(); authView(); };
}
function notAdminView() {
  $('#app').innerHTML = `<div class="auth"><div class="abox">${brand()}<div class="card"><h2>${esc(tr('هذا الحساب غير مفعّل في لوحة الإدارة'))}</h2>
    <p class="muted">${esc(tr('اللوحة لفريق وعد فقط. إذا أنشأت الحساب للتو، يتفعّل لما يضيفه أدمن من «فريق وعد».'))}</p>
    <div class="row" style="gap:8px"><button class="btn" id="plo">${esc(tr('تسجيل الخروج'))}</button></div></div></div></div>`;
  $('#plo').onclick = async () => { await authApi.signOut(); authView(); };
}

/* ---------- companies and subscriptions ---------- */
PV.companies = async page => {
  const [rows, st] = await Promise.all([db.rpc('platform_companies'), db.rpc('platform_get_settings')]);
  const live = rows.filter(c => subState(c)[1] !== 'bad'), q = (LS.get('waad.platq') || '').toLowerCase();
  const BUCKET = { all: ['الكل', () => true], pending: ['بانتظار القبول', c => c.status === 'pending'], trial: ['تجربة', c => c.status === 'trial' && subState(c)[1] !== 'bad'],
    active: ['مشتركة', c => c.status === 'active' && subState(c)[1] !== 'bad'], ended: ['منتهية', c => subState(c)[1] === 'bad' && c.status !== 'suspended'], suspended: ['موقوفة', c => c.status === 'suspended'] };
  const fk = BUCKET[LS.get('waad.platf')] ? LS.get('waad.platf') : 'all';
  const shown = rows.filter(BUCKET[fk][1]).filter(c => !q || (c.name + ' ' + (c.owner_email || '') + ' ' + c.plan).toLowerCase().includes(q));
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('المنشآت والاشتراكات'))}</h1><div class="muted">${esc(tr('بيانات الاشتراك فقط — لا تظهر هنا بيانات المنشآت نفسها.'))}</div></div></div>
    ${rows.some(c => c.status === 'pending') ? `<div class="note">${esc(tr('طلبات تنتظر قبولك'))}: <b class="num">${rows.filter(c => c.status === 'pending').length}</b> · ${esc(tr('اضغط على المنشأة لقبولها كتجربة أو اشتراك.'))}</div>` : ''}
    <div class="grid" style="margin-bottom:14px">${pkpi('المنشآت', rows.length)}${pkpi('بانتظار القبول', rows.filter(c => c.status === 'pending').length)}${pkpi('مفعّلة', rows.filter(c => c.status === 'active').length)}
      ${pkpi('تجربة', rows.filter(c => c.status === 'trial' && subState(c)[1] !== 'bad').length)}${pkpi('مغلقة (موقوفة أو انتهت تجربتها)', rows.length - live.length)}
      ${pkpi('المستخدمون', rows.reduce((a, c) => a + (c.users || 0), 0))}</div>
    <div class="ptabs pfil" role="tablist">${Object.entries(BUCKET).map(([k, [t, f]]) => `<a href="#" data-f="${k}"${k === fk ? ' aria-current="page"' : ''}>${esc(tr(t))} <span class="num">${rows.filter(f).length}</span></a>`).join('')}</div>
    <div class="row" style="margin-bottom:10px;gap:8px;flex-wrap:wrap"><input id="pq" placeholder="${esc(tr('بحث بالاسم أو البريد أو الباقة'))}" value="${esc(q)}" style="max-width:320px">
      <div class="sp"></div><button type="button" class="btn sm" data-copymail="${esc([...new Set(shown.map(c => c.owner_email).filter(Boolean))].join(', '))}">${esc(tr('نسخ إيميلات المنشآت الظاهرة'))}</button></div>
    ${tbl([{ t: 'المنشأة', h: c => esc(c.name) + `<div class="small muted" dir="ltr">${esc(c.owner_email || '—')}</div>` }, { t: 'الباقة', h: c => esc(c.plan) },
      { t: 'المدينة', h: c => esc(c.city || '—') + (c.size_band ? `<div class="small muted">${esc(tr(SIZE_B[c.size_band] || c.size_band))}</div>` : '') },
      { t: 'يستخدم', h: c => { const u = c.usage || {}; return `<span class="num">${u.employees || 0}</span> ${esc(tr('موظف'))}<div class="small muted">${(u.modules || []).map(m => esc(tr(MODULES[m] || m))).join('، ') || '—'}</div>`; } },
      { t: 'الحالة', h: c => { const [t, k] = subState(c); return `<span class="badge ${k}">${esc(tr(t))}</span>`; } },
      { t: 'ينتهي', h: c => { const e = subEnd(c), n = daysLeft(e); return e ? `<span class="num">${esc(e)}</span>` + (n >= 0 ? `<div class="small muted">${esc(tr('باقي'))} <span class="num">${n}</span> ${esc(tr('يوم'))}</div>` : '') : '—'; } },
      { t: 'المستخدمون', r: 1, h: c => `<span class="num">${c.users}${c.max_users ? ' / ' + c.max_users : ''}</span>` },
      { t: 'آخر دخول', h: c => c.last_sign_in ? `<span class="num">${esc(String(c.last_sign_in).slice(0, 10))}</span>` : '—' },
      { t: 'التسجيل', h: c => `<span class="num">${esc(String(c.created_at).slice(0, 10))}</span>` }, { t: '', h: c => `<div class="row" style="gap:4px;flex-wrap:nowrap">${quickBtns(c)}</div>` }], shown, { empty: 'لا توجد منشآت', onRow: true })}
    <div class="card" style="margin-top:16px"><h2>${esc(tr('إعدادات المنشآت الجديدة'))}</h2>
      <form id="psf" class="fg">${field('الأقسام المفتوحة عند التسجيل', modChecks(st.default_modules), 'wide')}
      ${field('مدة التجربة بالأيام', inp('days', st.default_trial_days || 7, 'type="number" min="1" max="365" required'))}
      <label class="row small wide" style="gap:6px"><input type="checkbox" name="approval" ${st.require_approval !== false ? 'checked' : ''} style="width:auto"> ${esc(tr('المنشآت الجديدة تنتظر قبولي قبل ما تبدأ'))}</label>
      <div class="wide"><div id="pserr"></div><button class="btn pri" id="psb">${esc(tr('حفظ'))}</button></div></form></div>`;
  $('#pq', page).oninput = e => { LS.set('waad.platq', e.target.value); clearTimeout(platformView.t); platformView.t = setTimeout(platformView, 400); };
  bindRows(page, shown, c => { location.hash = '#/company/' + c.company_id; }); bindCopy(page); bindQuick(page, shown, st);
  $$('[data-f]', page).forEach(a => a.onclick = e => { e.preventDefault(); LS.set('waad.platf', a.dataset.f); platformView(); });
  $('#psf', page).onsubmit = async e => { e.preventDefault(); const f = e.target;
    try { await busy($('#psb', page), async () => { await db.rpc('platform_set_settings', { p_modules: pickMods(f), p_trial_days: +f.days.value || 7, p_require_approval: f.approval.checked }); toast(tr('تم الحفظ')); }); }
    catch (er) { showErr($('#pserr', page), er); } };
};
const modChecks = (sel, prefix = 'm') => `<div class="row" style="gap:14px;flex-wrap:wrap">${Object.entries(MODULES).map(([k, t]) =>
  `<label class="row" style="gap:6px"><input type="checkbox" name="${prefix}_${k}" ${(sel || []).includes(k) ? 'checked' : ''} style="width:auto"> ${esc(tr(t))}</label>`).join('')}</div>`;
const pickMods = (f, prefix = 'm') => Object.keys(MODULES).filter(k => f.elements[prefix + '_' + k] && f.elements[prefix + '_' + k].checked);
function subForm(c) {
  modal(tr('اشتراك') + ': ' + c.name, `<div class="fg">${field('اسم الباقة', inp('plan', c.plan, 'maxlength="40" list="plans"') + '<datalist id="plans"><option value="الموارد البشرية"><option value="المالية"><option value="الشاملة"><option value="trial"></datalist>')}
      ${field('الحالة', `<select name="status">${Object.entries(SUB_ST).map(([k, [t]]) => opt(k, tr(t), c.status)).join('')}</select>`)}
      ${field('الأقسام المفتوحة', modChecks(c.modules), 'wide')}
      ${field('المدة بالأيام من اليوم', '<input name="days" type="number" min="1" max="3660" placeholder="30">')}
      ${field('أو تاريخ النهاية (فارغ = بدون نهاية)', `<input type="date" name="ends" value="${esc(subEnd(c) || '')}">`)}
      ${field('الحد الأعلى للمستخدمين (فارغ = بدون حد)', inp('max_users', c.max_users, 'type="number" min="1"'))}
      ${field('ملاحظة داخلية', inp('note', c.note), 'wide')}</div>
    <div class="card" style="margin-top:12px;padding:10px 12px"><b>${esc(tr('التواصل مع المالك'))}</b> <span class="small muted" dir="ltr">${esc(c.owner_email || '')}</span>
      <div class="row" style="gap:8px;flex-wrap:wrap;margin-top:8px">${mailBtns(c.owner_email, 'وعد: ' + c.name)}</div></div>
    <p class="muted small">${esc(tr('التغيير يظهر في سجل التدقيق الخاص بالمنشأة. إغلاق قسم لا يحذف بياناته — تعود عند فتحه.'))}</p>`, {
    wide: true, onOk: async (f, d) => {
      const mods = pickMods($('#mform', d) || d.querySelector('form'));
      if (!mods.length) throw new Error('اختر قسماً واحداً على الأقل');
      const ends = f.days ? dayAgo(-(+f.days)) : f.ends || null;
      await db.rpc('platform_set_subscription', { p_company: c.company_id, p_plan: f.plan, p_modules: mods, p_status: f.status,
        p_trial_ends: f.status === 'trial' ? ends : null, p_max_users: f.max_users ? +f.max_users : null, p_note: f.note || null, p_sub_ends: f.status === 'active' ? ends : null });
      toast(tr('تم الحفظ')); platformView();
    } });
  bindCopy($('#dlg'));
}

// accept a company that is waiting: as a trial or a subscription, for a number of days
function approveForm(c, st) {
  const d = modal(tr('قبول المنشأة') + ': ' + c.name, `<p class="muted small" style="margin-top:0" dir="ltr">${esc(c.owner_email || '')} · <span class="num">${esc(String(c.created_at).slice(0, 10))}</span></p>
    <div class="fg">${field('القبول كـ', `<select name="status">${opt('trial', tr('تجربة'), 'trial')}${opt('active', tr('اشتراك'), '')}</select>`)}
      ${field('المدة بالأيام (فارغ = بدون نهاية)', `<input name="days" type="number" min="1" max="3660" value="${esc(st && st.default_trial_days || 7)}">`)}</div>
    <div class="card" style="margin-top:12px;padding:10px 12px"><b>${esc(tr('التواصل مع المالك'))}</b>
      <div class="row" style="gap:8px;flex-wrap:wrap;margin-top:8px">${mailBtns(c.owner_email, 'وعد: ' + c.name)}</div></div>`, {
    ok: 'قبول', onOk: async f => {
      await db.rpc('platform_approve', { p_company: c.company_id, p_status: f.status, p_days: f.days ? +f.days : null });
      toast(tr('تم القبول')); platformView();
    } });
  bindCopy(d);
  d.querySelector('[name=status]').onchange = e => { d.querySelector('[name=days]').value = e.target.value === 'trial' ? (st && st.default_trial_days || 7) : 30; };
}

/* ---------- system numbers (from the same subscription metadata) ---------- */
// how many companies per value (city, size, activity, source), largest first
function countBy(rows, key, names) {
  const m = {}; rows.forEach(c => { const k = c[key] || ''; m[k] = (m[k] || 0) + 1; });
  return Object.entries(m).sort((a, b) => b[1] - a[1]).map(([k, n]) => [k ? tr(names ? names[k] || k : k) : tr('غير محدد'), n]);
}
const countCard = (title, list) => `<div class="card"><h2>${esc(tr(title))}</h2>${tbl([{ t: '', h: ([k]) => esc(k) }, { t: 'المنشآت', r: 1, h: ([, n]) => n }], list, { empty: 'ما فيه بيانات' })}</div>`;
PV.system = async page => {
  const rows = await db.rpc('platform_companies'), t0 = today();
  const since = n => rows.filter(c => String(c.created_at).slice(0, 10) > dayAgo(n)).length;
  const active7 = rows.filter(c => c.last_sign_in && String(c.last_sign_in).slice(0, 10) > dayAgo(7)).length;
  const ending = rows.filter(c => c.status === 'trial' && c.trial_ends && c.trial_ends >= t0 && c.trial_ends <= dayAgo(-3)).sort((a, b) => a.trial_ends < b.trial_ends ? -1 : 1);
  const paid = rows.filter(c => c.status === 'active').length, decided = rows.filter(c => c.status !== 'pending' && (c.status !== 'trial' || subState(c)[1] === 'bad')).length;
  const quiet = rows.filter(c => subState(c)[1] !== 'bad' && (!c.last_sign_in || String(c.last_sign_in).slice(0, 10) <= dayAgo(14)));
  const days = Array.from({ length: 30 }, (_, i) => dayAgo(29 - i));
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('أرقام النظام'))}</h1><div class="muted">${esc(tr('من بيانات الاشتراك وآخر دخول فقط.'))}</div></div></div>
    <div class="grid" style="margin-bottom:14px">${pkpi('تسجيلات آخر ٧ أيام', since(7))}${pkpi('تسجيلات آخر ٣٠ يوماً', since(30))}
      ${pkpi('منشآت دخلت آخر ٧ أيام', active7, rows.length ? pct(active7, rows.length) + ' ' + tr('من المنشآت') : '')}
      ${pkpi('نسبة التحويل إلى اشتراك', pct(paid, decided), 'من المنشآت اللي انتهت تجربتها أو اشتركت')}${pkpi('تجارب تنتهي خلال ٣ أيام', ending.length)}${pkpi('بانتظار القبول', rows.filter(c => c.status === 'pending').length)}</div>
    <div class="card" style="margin-bottom:14px"><h2>${esc(tr('التسجيلات الجديدة يومياً (آخر ٣٠ يوماً)'))}</h2>${pbars(days.map(k => ({ k, v: rows.filter(c => String(c.created_at).slice(0, 10) === k).length })), 'التسجيلات الجديدة يومياً (آخر ٣٠ يوماً)')}</div>
    <div class="g2p">
      <div class="card"><h2>${esc(tr('تجارب تنتهي قريباً'))}</h2><p class="muted small" style="margin-top:0">${esc(tr('تواصل معهم قبل ما تنتهي التجربة.'))}</p>
        ${tbl([{ t: 'المنشأة', h: c => esc(c.name) + `<div class="small muted" dir="ltr">${esc(c.owner_email || '—')}</div>` }, { t: 'نهاية التجربة', h: c => `<span class="num">${esc(c.trial_ends)}</span>` }, { t: '', h: c => c.owner_email ? `<a class="btn sm" href="${esc(gmailTo(c.owner_email, 'وعد: ' + c.name))}" target="_blank" rel="noopener">${esc(tr('مراسلة'))}</a>` : '' }], ending, { empty: 'لا توجد تجارب تنتهي خلال ٣ أيام' })}</div>
      <div class="card"><h2>${esc(tr('منشآت ما دخلت من أسبوعين'))}</h2><p class="muted small" style="margin-top:0">${esc(tr('اشتراكها مفتوح وما أحد دخل منها من ١٤ يوماً أو أكثر.'))}</p>
        ${tbl([{ t: 'المنشأة', h: c => esc(c.name) + `<div class="small muted" dir="ltr">${esc(c.owner_email || '—')}</div>` }, { t: 'آخر دخول', h: c => c.last_sign_in ? `<span class="num">${esc(String(c.last_sign_in).slice(0, 10))}</span>` : '—' }, { t: '', h: c => c.owner_email ? `<a class="btn sm" href="${esc(gmailTo(c.owner_email, 'وعد: ' + c.name))}" target="_blank" rel="noopener">${esc(tr('مراسلة'))}</a>` : '' }], quiet, { empty: 'كل المنشآت نشطة' })}</div></div>
    <h2 style="margin:18px 0 10px">${esc(tr('مين عملاؤك'))}</h2>
    <div class="g2p">${countCard('حسب المدينة', countBy(rows, 'city'))}${countCard('حسب عدد الموظفين', countBy(rows, 'size_band', SIZE_B))}
      ${countCard('حسب النشاط', countBy(rows, 'industry', INDUSTRY))}${countCard('من وين عرفوا عن وعد', countBy(rows, 'heard_from', HEARD))}</div>`;
};

/* ---------- website visitors (the site's own counter: daily totals only, no cookies) ---------- */
const SRC_N = { direct: 'مباشر', whatsapp: 'واتساب', google: 'قوقل', bing: 'بينق', x: 'إكس', linkedin: 'لينكدإن', instagram: 'إنستقرام', snapchat: 'سناب شات', tiktok: 'تيك توك', facebook: 'فيسبوك', other: 'مواقع أخرى' };
const PAGE_N = { home: 'الرئيسية', modules: 'الأقسام', trust: 'التوافق والأمان', contact: 'أسئلة وتواصل' };
const DEV_N = { mobile: 'جوال', tablet: 'تابلت', desktop: 'كمبيوتر' };
const LANG_N = { ar: 'العربية', en: 'الإنجليزية' };
PV.site = async page => {
  const n = [7, 30, 90].includes(LS.get('waad.sitedays')) ? LS.get('waad.sitedays') : 30;
  const rows = await db.rpc('platform_site_stats', { p_days: n });
  const sum = (rs, k) => rs.reduce((a, r) => a + (r[k] || 0), 0);
  const visits = sum(rows, 'visits'), views = sum(rows, 'views'), cta = sum(rows, 'cta');
  const days = Array.from({ length: n }, (_, i) => dayAgo(n - 1 - i));
  const brk = (title, key, names) => {
    const m = {}; rows.forEach(r => { const x = m[r[key]] = m[r[key]] || { visits: 0, views: 0, cta: 0 }; x.visits += r.visits; x.views += r.views; x.cta += r.cta; });
    const list = Object.entries(m).sort((a, b) => b[1].visits - a[1].visits || b[1].views - a[1].views);
    return `<div class="card"><h2>${esc(tr(title))}</h2>${tbl([{ t: '', h: ([k]) => esc(tr(names[k] || k)) }, { t: 'زيارات', r: 1, h: ([, v]) => v.visits }, { t: 'صفحات', r: 1, h: ([, v]) => v.views }, { t: 'ضغطات التجربة', r: 1, h: ([, v]) => v.cta }], list, { empty: 'ما فيه زيارات في هذي الفترة' })}</div>`;
  };
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('زوار الموقع'))}</h1><div class="muted">${esc(tr('عدّاد الموقع نفسه: أرقام يومية فقط، بدون كوكيز وبدون أي بيانات شخصية. زياراتك من هذا الجهاز ما تنحسب.'))}</div></div>
      <select id="sdays" style="width:auto">${[7, 30, 90].map(d => opt(d, tr('آخر') + ' ' + d + ' ' + tr('يوم'), n)).join('')}</select></div>
    <div class="grid" style="margin-bottom:14px">${pkpi('الزيارات', visits)}${pkpi('الصفحات المفتوحة', views, visits ? (views / visits).toFixed(1) + ' ' + tr('صفحة لكل زيارة') : '')}
      ${pkpi('ضغطات «جرّبه مجاناً»', cta)}${pkpi('نسبة الضغط من الزيارات', pct(cta, visits))}</div>
    <div class="card" style="margin-bottom:14px"><h2>${esc(tr('الزيارات يومياً'))}</h2>${pbars(days.map(k => ({ k, v: rows.filter(r => r.day === k).reduce((a, r) => a + r.visits, 0) })), 'الزيارات يومياً')}</div>
    <div class="g2p">${brk('من وين جاؤوا', 'source', SRC_N)}${brk('الصفحات', 'page', PAGE_N)}${brk('الأجهزة', 'device', DEV_N)}${brk('اللغة', 'lang', LANG_N)}</div>
    <p class="muted small">${esc(tr('الدول وسرعة الصفحات في'))} <a href="https://dash.cloudflare.com/?to=/:account/web-analytics" target="_blank" rel="noopener">Cloudflare Web Analytics</a>.</p>`;
  $('#sdays', page).onchange = e => { LS.set('waad.sitedays', +e.target.value); platformView(); };
};

/* ---------- website texts: contact details, a notice bar, and the FAQ ---------- */
// the built-in texts are read from the published contact page, so the editor starts from what visitors see today
async function siteDefaults() {
  try {
    const r = await fetch(new URL('contact.html', SITE_URL)); if (!r.ok) return {};
    const doc = new DOMParser().parseFromString(await r.text(), 'text/html');
    const telA = doc.querySelector('a[href^="tel:"]'), tel = telA ? telA.getAttribute('href').replace(/\D/g, '') : '';
    const t = (el, s) => ((el && el.querySelector(s)) || {}).textContent || '';
    return { contact: { phone: tel, email: (doc.querySelector('[data-copy]') || { dataset: {} }).dataset.copy || '' },
      faq: [...doc.querySelectorAll('.faq details')].map(d => ({ qa: t(d, 'summary .ar'), qe: t(d, 'summary .en'), aa: t(d, 'p .ar'), ae: t(d, 'p .en') })) };
  } catch (e) { return {}; }
}
const localPhone = p => p && /^9665\d{8}$/.test(p) ? '0' + p.slice(3) : '';
PV.content = async page => {
  const [cur, def] = await Promise.all([db.rpc('site_content'), siteDefaults()]);
  const contact = cur.contact || def.contact || {}, banner = cur.banner || {};
  let faq = (cur.faq || def.faq || []).map(x => Object.assign({ qa: '', aa: '', qe: '', ae: '' }, x));
  const changed = k => cur[k] ? `<span class="badge info">${esc(tr('معدّل من اللوحة'))}</span>` : `<span class="badge">${esc(tr('النص الأصلي'))}</span>`;
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('محتوى الموقع'))}</h1><div class="muted">${esc(tr('التعديل يظهر في الموقع فوراً، بدون نشر جديد.'))} <a href="${SITE_URL}" target="_blank" rel="noopener">${esc(tr('فتح الموقع'))}</a></div></div></div>
    <div class="g2p">
    <form class="card" id="fcon"><h2>${esc(tr('أرقام التواصل'))} ${changed('contact')}</h2><div class="fg">
      ${field('جوال الواتساب والاتصال', inp('phone', localPhone(contact.phone), 'dir="ltr" inputmode="numeric" placeholder="05XXXXXXXX" required'))}
      ${field('البريد الإلكتروني', inp('email', contact.email, 'dir="ltr" type="email" required'))}</div>
      <div id="econ"></div><div class="row" style="gap:8px;margin-top:10px"><button class="btn pri">${esc(tr('حفظ'))}</button>${cur.contact ? `<button type="button" class="btn" data-reset="contact">${esc(tr('رجوع للأصل'))}</button>` : ''}</div></form>
    <form class="card" id="fban"><h2>${esc(tr('شريط تنبيه أعلى الموقع'))} ${changed('banner')}</h2>
      <label class="row small" style="gap:6px;margin-bottom:8px"><input type="checkbox" name="on" ${banner.on ? 'checked' : ''} style="width:auto"> ${esc(tr('إظهار الشريط'))}</label><div class="fg">
      ${field('النص بالعربي', inp('ar', banner.ar, 'maxlength="160"'), 'wide')}${field('النص بالإنجليزي', inp('en', banner.en, 'maxlength="160" dir="ltr"'), 'wide')}</div>
      <div id="eban"></div><div class="row" style="gap:8px;margin-top:10px"><button class="btn pri">${esc(tr('حفظ'))}</button>${cur.banner ? `<button type="button" class="btn" data-reset="banner">${esc(tr('حذف الشريط'))}</button>` : ''}</div></form></div>
    <form class="card" id="ffaq" style="margin-top:14px"><h2>${esc(tr('الأسئلة الشائعة'))} ${changed('faq')}</h2><div id="faql"></div>
      <div id="efaq"></div><div class="row" style="gap:8px;margin-top:10px"><button type="button" class="btn" id="faqadd">${esc(tr('إضافة سؤال'))}</button><div class="sp"></div>
      <button class="btn pri">${esc(tr('حفظ الأسئلة'))}</button>${cur.faq ? `<button type="button" class="btn" data-reset="faq">${esc(tr('رجوع للأسئلة الأصلية'))}</button>` : ''}</div></form>`;
  const save = async (key, value, btn, err) => { try { await busy(btn, () => db.rpc('platform_set_site_content', { p_key: key, p_value: value })); toast(tr('تم الحفظ')); platformView(); } catch (e) { showErr(err, e); } };
  $('#fcon', page).onsubmit = e => { e.preventDefault(); const f = e.target, p = f.phone.value.replace(/\D/g, '');
    if (!/^05\d{8}$/.test(p)) return showErr($('#econ', page), tr('اكتب رقم الجوال بالشكل 05XXXXXXXX'));
    save('contact', { phone: '966' + p.slice(1), email: f.email.value.trim() }, $('button.pri', f), $('#econ', page)); };
  $('#fban', page).onsubmit = e => { e.preventDefault(); const f = e.target;
    if (f.on.checked && !f.ar.value.trim()) return showErr($('#eban', page), tr('اكتب نص الشريط بالعربي'));
    save('banner', { on: f.on.checked, ar: f.ar.value.trim(), en: f.en.value.trim() }, $('button.pri', f), $('#eban', page)); };
  $$('[data-reset]', page).forEach(b => b.onclick = () => save(b.dataset.reset, null, b, $('#e' + { contact: 'con', banner: 'ban', faq: 'faq' }[b.dataset.reset], page)));
  // FAQ editor: questions are edited in place; ↑ ↓ reorder; ✕ removes
  const list = $('#faql', page);
  const read = () => { faq = $$('.fqi', list).map(d => ({ qa: d.querySelector('[name=qa]').value, aa: d.querySelector('[name=aa]').value, qe: d.querySelector('[name=qe]').value, ae: d.querySelector('[name=ae]').value })); };
  const draw = () => {
    list.innerHTML = faq.length ? faq.map((x, i) => `<div class="fqi" data-i="${i}"><div class="row" style="gap:6px;margin-bottom:6px"><b class="num">${i + 1}</b><div class="sp"></div>
        <button type="button" class="btn sm" data-mv="-1" aria-label="${esc(tr('أعلى'))}" ${i ? '' : 'disabled'}>↑</button><button type="button" class="btn sm" data-mv="1" aria-label="${esc(tr('أسفل'))}" ${i < faq.length - 1 ? '' : 'disabled'}>↓</button>
        <button type="button" class="btn sm" data-rm aria-label="${esc(tr('حذف'))}">✕</button></div>
      <div class="fg">${field('السؤال بالعربي', `<input name="qa" value="${esc(x.qa)}" maxlength="200">`)}${field('السؤال بالإنجليزي', `<input name="qe" value="${esc(x.qe)}" maxlength="200" dir="ltr">`)}
        ${field('الجواب بالعربي', `<textarea name="aa" rows="3" maxlength="800">${esc(x.aa)}</textarea>`)}${field('الجواب بالإنجليزي', `<textarea name="ae" rows="3" maxlength="800" dir="ltr">${esc(x.ae)}</textarea>`)}</div></div>`).join('')
      : `<div class="empty">${esc(tr('ما فيه أسئلة. أضف سؤالاً.'))}</div>`;
    $$('.fqi', list).forEach(d => { const i = +d.dataset.i;
      $$('[data-mv]', d).forEach(b => b.onclick = () => { read(); const j = i + +b.dataset.mv; [faq[i], faq[j]] = [faq[j], faq[i]]; draw(); });
      d.querySelector('[data-rm]').onclick = () => { read(); faq.splice(i, 1); draw(); }; });
  };
  draw();
  $('#faqadd', page).onclick = () => { read(); faq.push({ qa: '', aa: '', qe: '', ae: '' }); draw(); const l = $$('.fqi', list).pop(); l.scrollIntoView({ block: 'nearest' }); l.querySelector('input').focus(); };
  $('#ffaq', page).onsubmit = e => { e.preventDefault(); read();
    const out = faq.map(x => ({ qa: x.qa.trim(), aa: x.aa.trim(), qe: x.qe.trim(), ae: x.ae.trim() })).filter(x => x.qa || x.aa);
    if (out.some(x => !x.qa || !x.aa)) return showErr($('#efaq', page), tr('كل سؤال يحتاج سؤالاً وجواباً بالعربي'));
    save('faq', out, $('#ffaq button.pri', page), $('#efaq', page)); };
};

/* ---------- announcements: a notice every company sees inside the system ---------- */
const annState = a => a.starts_at > today() ? ['مجدول', 'wait'] : a.ends_at && a.ends_at < today() ? ['منتهي', ''] : ['ظاهر الآن', 'ok'];
PV.news = async page => {
  const rows = await db.rpc('platform_announcements');
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الإعلانات'))}</h1><div class="muted">${esc(tr('رسالة قصيرة تظهر أعلى النظام لكل المستخدمين في كل المنشآت، ويقدر كل مستخدم يقفلها.'))}</div></div>
      <button class="btn pri" id="annadd">${esc(tr('إعلان جديد'))}</button></div>
    ${tbl([{ t: 'النص', h: a => `<div data-nt>${esc(a.body_ar)}</div>` + (a.body_en ? `<div class="small muted" data-nt dir="ltr">${esc(a.body_en)}</div>` : '') },
      { t: 'النوع', h: a => `<span class="badge ${a.level === 'warn' ? 'bad' : 'info'}">${esc(tr(a.level === 'warn' ? 'تنبيه مهم' : 'معلومة'))}</span>` },
      { t: 'الفترة', h: a => `<span class="num">${esc(a.starts_at)}</span> ← <span class="num">${esc(a.ends_at || '…')}</span>` },
      { t: 'الحالة', h: a => { const [t, k] = annState(a); return `<span class="badge ${k}">${esc(tr(t))}</span>`; } }], rows, { empty: 'ما فيه إعلانات', onRow: true })}`;
  $('#annadd', page).onclick = () => annForm({});
  bindRows(page, rows, annForm);
};
function annForm(a) {
  const d = modal(a.id ? tr('تعديل الإعلان') : tr('إعلان جديد'), `<div class="fg">
      ${field('النص بالعربي', `<textarea name="body_ar" rows="2" maxlength="400" required>${esc(a.body_ar || '')}</textarea>`, 'wide')}
      ${field('النص بالإنجليزي (اختياري)', `<textarea name="body_en" rows="2" maxlength="400" dir="ltr">${esc(a.body_en || '')}</textarea>`, 'wide')}
      ${field('النوع', `<select name="level">${opt('info', tr('معلومة'), a.level)}${opt('warn', tr('تنبيه مهم'), a.level)}</select>`)}
      ${field('يبدأ', `<input type="date" name="starts_at" value="${esc(a.starts_at || today())}">`)}
      ${field('ينتهي (فارغ = حتى تحذفه)', `<input type="date" name="ends_at" value="${esc(a.ends_at || '')}">`)}</div>
    ${a.id ? `<button type="button" class="btn sm" id="anndel" style="margin-top:10px">${esc(tr('حذف الإعلان'))}</button>` : ''}`, {
    onOk: async f => {
      await db.rpc('platform_save_announcement', { p_id: a.id || null, p_body_ar: f.body_ar, p_body_en: f.body_en || null, p_level: f.level, p_starts: f.starts_at || null, p_ends: f.ends_at || null });
      toast(tr('تم الحفظ')); platformView();
    } });
  if (a.id) $('#anndel', d).onclick = async () => { await db.rpc('platform_delete_announcement', { p_id: a.id }); d.close(); toast(tr('تم الحذف')); platformView(); };
}

/* ---------- the Waad team: who can open this site ---------- */
const tempPw = () => { const c = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789', v = crypto.getRandomValues(new Uint32Array(10)); return [...v].map(x => c[x % c.length]).join(''); };
const credsBox = (u, pw) => `<p>${esc(tr('أرسل له بياناته، وبيطلب منه النظام يغيّر كلمة المرور أول ما يدخل.'))}</p>
  <div class="card" style="padding:10px 12px" dir="ltr" data-nt><div>${esc(tr('اسم المستخدم'))}: <b>${esc(u)}</b></div><div>${esc(tr('كلمة المرور المؤقتة'))}: <b>${esc(pw)}</b></div></div>
  <p class="small muted">${esc(tr('رابط اللوحة'))}: <span dir="ltr">${esc(location.href.split('#')[0].split('?')[0])}</span></p>`;
PV.team = async page => {
  const rows = await db.rpc('platform_team');
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('فريق وعد'))}</h1><div class="muted">${esc(tr('كل عضو يدخل اللوحة باسم مستخدم وكلمة مرور. تضيفه بكلمة مرور مؤقتة، ويغيّرها أول ما يدخل.'))}</div></div>
      <button class="btn pri" id="tadd">${esc(tr('إضافة عضو'))}</button></div>
    ${tbl([{ t: 'اسم المستخدم', h: a => `<b dir="ltr">${esc(a.username || a.email)}</b>` + (a.is_me ? ` <span class="badge info">${esc(tr('أنت'))}</span>` : '') },
      { t: 'آخر دخول', h: a => a.last_sign_in ? `<span class="num">${esc(String(a.last_sign_in).slice(0, 10))}</span>` : '—' },
      { t: 'التحقق بخطوتين', h: a => `<span class="badge ${a.mfa ? 'ok' : 'wait'}">${esc(tr(a.mfa ? 'مفعّل' : 'غير مفعّل'))}</span>` },
      { t: 'كلمة المرور', h: a => a.must_change ? `<span class="badge wait">${esc(tr('مؤقتة'))}</span>` : `<span class="muted small">${esc(tr('خاصة به'))}</span>` }], rows, { empty: 'ما فيه أعضاء', onRow: true })}
    <p class="muted small">${esc(tr('اضغط على عضو لإعادة تعيين كلمة مروره أو حذفه من الفريق.'))}</p>`;
  $('#tadd', page).onclick = () => {
    const pw = tempPw();
    modal(tr('إضافة عضو لفريق وعد'), `<div class="fg">${field('اسم المستخدم (إنجليزي، بدون مسافات)', '<input name="user" required dir="ltr" autocapitalize="none" spellcheck="false" placeholder="sara">')}
        ${field('كلمة المرور المؤقتة', `<input name="pw" required dir="ltr" value="${esc(pw)}">`)}</div>`, {
      ok: 'إضافة', onOk: async f => {
        const u = (f.user || '').trim().toLowerCase();
        if (!/^[a-z0-9._-]{3,30}$/.test(u)) throw new Error('اسم المستخدم من ٣ إلى ٣٠ حرفاً إنجليزياً أو رقماً');
        if ((f.pw || '').length < 8) throw new Error('كلمة المرور 8 أحرف على الأقل');
        const r = await authApi.createStaff(adminEmail(u), f.pw);
        if (r.existed) throw new Error('اسم المستخدم محجوز، اختر اسماً آخر');
        await db.rpc('platform_add_admin', { p_username: u });
        setTimeout(() => { modal(tr('تمت إضافة العضو'), credsBox(u, f.pw)); platformView(); }, 0);
      } });
  };
  bindRows(page, rows, a => {
    if (a.is_me) return changePasswordView(false);
    if (!a.username) return toast(tr('هذا الحساب يدخل بالبريد'));
    const pw = tempPw();
    const d = modal(tr('عضو الفريق') + ': ' + a.username, `<div class="fg">${field('كلمة مرور مؤقتة جديدة', `<input name="pw" required dir="ltr" value="${esc(pw)}">`)}</div>
      <button type="button" class="btn sm" id="trm" style="margin-top:12px">${esc(tr('حذف من الفريق'))}</button>`, {
      ok: 'إعادة تعيين كلمة المرور', onOk: async f => {
        await db.rpc('platform_reset_admin_password', { p_username: a.username, p_password: f.pw });
        setTimeout(() => { modal(tr('تم تعيين كلمة مرور مؤقتة'), credsBox(a.username, f.pw)); platformView(); }, 0);
      } });
    $('#trm', d).onclick = async () => {
      if (!(await confirmBox(tr('حذف من الفريق'), tr('ما يقدر يدخل اللوحة بعدها.') + ' ' + a.username, tr('حذف')))) return;
      try { await db.rpc('platform_remove_admin', { p_username: a.username }); toast(tr('تم الحذف')); } catch (e) { toast(e.message); } platformView();
    };
  });
};

/* ---------- home: what needs the team today ---------- */
PV.home = async page => {
  const [rows, st, visits, pays, tks] = await Promise.all([db.rpc('platform_companies'), db.rpc('platform_get_settings'),
    db.rpc('platform_site_stats', { p_days: 7 }).catch(() => []), db.rpc('platform_payments_list', { p_from: MONTH0(), p_to: today() }).catch(() => []), db.rpc('platform_tickets', { p_status: 'open' }).catch(() => [])]);
  const t0 = today(), pending = rows.filter(c => c.status === 'pending');
  const trialEnd = rows.filter(c => c.status === 'trial' && c.trial_ends && c.trial_ends >= t0 && c.trial_ends <= dayAgo(-3));
  const subEnd7 = rows.filter(c => c.status === 'active' && c.sub_ends && c.sub_ends >= t0 && c.sub_ends <= dayAgo(-7));
  const ended = rows.filter(c => subState(c)[1] === 'bad' && c.status !== 'suspended');
  const sum = (a, k) => a.reduce((x, r) => x + (+r[k] || 0), 0);
  const list = (title, sub, items, cols) => `<div class="card"><h2>${esc(tr(title))} <span class="badge${items.length ? ' info' : ''} num">${items.length}</span></h2>
    ${sub ? `<p class="muted small" style="margin-top:0">${esc(tr(sub))}</p>` : ''}${tbl(cols, items, { empty: 'ما فيه شي', onRow: true })}</div>`;
  const nameCol = { t: 'المنشأة', h: c => esc(c.name) + `<div class="small muted" dir="ltr">${esc(c.owner_email || '—')}</div>` };
  const endCol = { t: 'ينتهي', h: c => `<span class="num">${esc(subEnd(c) || '')}</span>` }, actCol = { t: '', h: c => `<div class="row" style="gap:4px">${quickBtns(c)}</div>` };
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الرئيسية'))}</h1><div class="muted">${esc(tr('اللي يحتاج منك اليوم، وأهم الأرقام.'))}</div></div></div>
    ${tks.length ? `<a class="note" href="#/support" style="display:block">${esc(tr('طلبات دعم تنتظر ردك'))}: <b class="num">${tks.length}</b></a>` : ''}
    <div class="grid" style="margin-bottom:14px">${pkpi('بانتظار القبول', pending.length)}${pkpi('طلبات دعم مفتوحة', tks.length)}${pkpi('منشآت مشتركة', rows.filter(c => c.status === 'active' && subState(c)[1] !== 'bad').length)}
      ${pkpi('تجارب شغّالة', rows.filter(c => c.status === 'trial' && subState(c)[1] !== 'bad').length)}${pkpi('إيرادات هذا الشهر', money0(sum(pays, 'amount')), 'ريال')}
      ${pkpi('زيارات الموقع (٧ أيام)', sum(visits, 'visits'))}${pkpi('ضغطات «جرّبه» (٧ أيام)', sum(visits, 'cta'))}</div>
    <div class="g2p">
      ${list('طلبات تنتظر قبولك', 'اقبلها كتجربة بضغطة، أو افتح المنشأة لتختار اشتراك ومدة.', pending, [nameCol, { t: 'التسجيل', h: c => `<span class="num">${esc(String(c.created_at).slice(0, 10))}</span>` }, actCol])}
      ${list('تجارب تنتهي خلال ٣ أيام', 'تواصل معهم قبل ما تنتهي.', trialEnd, [nameCol, endCol, actCol])}
      ${list('اشتراكات تنتهي خلال ٧ أيام', 'ذكّرهم بالتجديد.', subEnd7, [nameCol, endCol, actCol])}
      ${list('انتهت ولم تُجدَّد', 'أقسامها مقفلة الحين.', ended, [nameCol, endCol, actCol])}</div>`;
  const all = [...pending, ...trialEnd, ...subEnd7, ...ended];
  $$('.g2p .card', page).forEach((card, i) => bindRows(card, [pending, trialEnd, subEnd7, ended][i], c => { location.hash = '#/company/' + c.company_id; }));
  bindQuick(page, all, st);
};

/* ---------- one company: subscription, quick actions, payments, notes, history ---------- */
PV.company = async (page, id) => {
  const [d, st, plans] = await Promise.all([db.rpc('platform_company', { p_company: id }), db.rpc('platform_get_settings'), db.rpc('platform_plans_list')]);
  const c = d.company; if (!c) { page.innerHTML = `<div class="err">${esc(tr('المنشأة غير موجودة'))}</div>`; return; }
  const [stt, stk] = subState(c), e = subEnd(c), n = daysLeft(e), paid = d.payments.reduce((a, p) => a + (+p.amount || 0), 0);
  const plan = plans.find(p => p.id === d.plan_id);
  const histTxt = h => [h.status && tr((SUB_ST[h.status] || [h.status])[0]), h.plan && h.plan !== 'trial' ? h.plan : '', h.trial_ends && tr('التجربة حتى') + ' ' + h.trial_ends, h.sub_ends && tr('الاشتراك حتى') + ' ' + h.sub_ends].filter(Boolean).join(' · ');
  page.innerHTML = `<div class="head"><div><a href="#/companies" class="small">← ${esc(tr('المنشآت'))}</a><h1>${esc(c.name)} <span class="badge ${stk}">${esc(tr(stt))}</span></h1>
      <div class="muted small" dir="ltr">${esc(c.owner_email || '')}</div></div></div>
    <div class="row" style="gap:6px;flex-wrap:wrap;margin-bottom:14px">
      ${c.status === 'pending' ? `<button class="btn pri" id="capp">${esc(tr('قبول…'))}</button>` : ''}
      <button class="btn pri" id="cpay">${esc(tr('تسجيل دفعة'))}</button><button class="btn" id="csub">${esc(tr('تعديل الاشتراك'))}</button>
      ${c.status === 'trial' || c.status === 'active' ? `<button class="btn" data-q="extend" data-d="7" data-c="${esc(id)}">${esc(tr('+٧ أيام'))}</button><button class="btn" data-q="extend" data-d="30" data-c="${esc(id)}">${esc(tr('+٣٠ يوم'))}</button>` : ''}
      ${c.status === 'suspended' ? `<button class="btn" data-q="resume" data-c="${esc(id)}">${esc(tr('إعادة تفعيل'))}</button>` : c.status !== 'pending' ? `<button class="btn" data-q="suspend" data-c="${esc(id)}">${esc(tr('إيقاف'))}</button>` : ''}</div>
    <div class="g2p">
      <div class="card"><h2>${esc(tr('الاشتراك'))}</h2><dl class="pdl">
        <dt>${esc(tr('الباقة'))}</dt><dd>${esc(plan ? plan.name : c.plan)}${plan ? ` · <span class="num">${money0(plan.price)}</span> ${esc(tr('ريال'))} / <span class="num">${plan.period_days}</span> ${esc(tr('يوم'))}` : ''}</dd>
        <dt>${esc(tr('ينتهي'))}</dt><dd>${e ? `<span class="num">${esc(e)}</span>` + (n >= 0 ? ` · ${esc(tr('باقي'))} <span class="num">${n}</span> ${esc(tr('يوم'))}` : ` · ${esc(tr('انتهى'))}`) : esc(tr('بدون نهاية'))}</dd>
        <dt>${esc(tr('الأقسام'))}</dt><dd>${(c.modules || []).map(m => `<span class="badge">${esc(tr(MODULES[m] || m))}</span>`).join(' ')}</dd>
        <dt>${esc(tr('المستخدمون'))}</dt><dd class="num">${c.users}${c.max_users ? ' / ' + c.max_users : ''}</dd>
        <dt>${esc(tr('آخر دخول'))}</dt><dd class="num">${c.last_sign_in ? esc(String(c.last_sign_in).slice(0, 10)) : '—'}</dd>
        <dt>${esc(tr('التسجيل'))}</dt><dd class="num">${esc(String(c.created_at).slice(0, 10))}</dd>
        <dt>${esc(tr('مجموع المدفوع'))}</dt><dd><span class="num">${money0(paid)}</span> ${esc(tr('ريال'))}</dd></dl>
        <h2 style="margin-top:18px">${esc(tr('عن المنشأة'))}</h2><dl class="pdl">
        <dt>${esc(tr('جوال المالك'))}</dt><dd>${c.owner_phone ? `<span class="num" dir="ltr">${esc(c.owner_phone)}</span>` : '—'}</dd>
        <dt>${esc(tr('المدينة'))}</dt><dd>${esc(c.city || '—')}</dd>
        <dt>${esc(tr('عدد الموظفين'))}</dt><dd>${esc(c.size_band ? tr(SIZE_B[c.size_band] || c.size_band) : '—')}</dd>
        <dt>${esc(tr('النشاط'))}</dt><dd>${esc(c.industry ? tr(INDUSTRY[c.industry] || c.industry) : '—')}</dd>
        <dt>${esc(tr('عرف عن وعد من'))}</dt><dd>${esc(c.heard_from ? tr(HEARD[c.heard_from] || c.heard_from) : '—')}</dd></dl>
        <h2 style="margin-top:18px">${esc(tr('الاستخدام'))}</h2><p class="muted small" style="margin-top:0">${esc(tr('أعداد وتواريخ فقط، بدون أي بيانات من داخل المنشأة.'))}</p><dl class="pdl">
        <dt>${esc(tr('الموظفون المسجّلون'))}</dt><dd class="num">${(c.usage || {}).employees || 0}</dd>
        <dt>${esc(tr('أقسام فيها بيانات'))}</dt><dd>${((c.usage || {}).modules || []).map(m => `<span class="badge ok">${esc(tr(MODULES[m] || m))}</span>`).join(' ') || '—'}</dd>
        <dt>${esc(tr('آخر نشاط'))}</dt><dd class="num">${(c.usage || {}).last_activity ? esc(String(c.usage.last_activity).slice(0, 16).replace('T', ' ')) : '—'}</dd></dl></div>
      <div class="card"><h2>${esc(tr('التواصل مع المالك'))}</h2><div class="row" style="gap:8px;flex-wrap:wrap">${phoneBtns(c.owner_phone)}${mailBtns(c.owner_email, 'وعد: ' + c.name)}</div>
        <h2 style="margin-top:18px">${esc(tr('سجل التواصل'))}</h2>
        <form id="nform"><div class="row" style="gap:8px;flex-wrap:wrap;margin-bottom:8px">
            <select name="channel" style="width:auto">${Object.entries(CH_N).map(([k, [t, i]]) => opt(k, i + ' ' + tr(t), 'call')).join('')}</select>
            <input type="date" name="on" value="${today()}" max="${today()}" style="width:auto" aria-label="${esc(tr('تاريخ التواصل'))}"></div>
          <div class="row" style="gap:8px;align-items:flex-start"><textarea name="body" rows="2" maxlength="1000" placeholder="${esc(tr('مثلاً: اتصلت بالمالك، يبي باقة أكبر'))}" style="flex:1"></textarea><button class="btn pri">${esc(tr('إضافة'))}</button></div></form>
        <div id="nerr"></div>
        ${d.notes.length ? d.notes.map(x => { const [t, i] = CH_N[x.channel] || CH_N.other; return `<div class="pnote"><div><span class="badge">${i} ${esc(tr(t))}</span> <span class="num small">${esc(x.on || String(x.at).slice(0, 10))}</span></div>
          <div data-nt style="margin-top:4px">${esc(x.body)}</div><div class="small muted"><span dir="ltr">${esc(x.by || '')}</span> · <a href="#" data-dn="${esc(x.id)}">${esc(tr('حذف'))}</a></div></div>`; }).join('')
          : `<p class="muted small">${esc(tr('ما فيه تواصل مسجّل.'))}</p>`}</div></div>
    <div class="card" style="margin-bottom:14px"><h2>${esc(tr('الدفعات'))}</h2>
      ${tbl([{ t: 'التاريخ', h: p => `<span class="num">${esc(p.paid_on)}</span>` }, { t: 'المبلغ', r: 1, h: p => money0(p.amount) }, { t: 'الطريقة', h: p => esc(tr(PAY_M[p.method] || p.method)) },
        { t: 'المدة', h: p => p.days ? `<span class="num">${p.days}</span> ${esc(tr('يوم'))}` : '—' }, { t: 'ملاحظة', h: p => `<span data-nt>${esc(p.note || '')}</span>` },
        { t: '', h: p => `<a href="#" data-rc="${esc(p.id)}">${esc(tr('إيصال'))}</a> · <a href="#" data-dp="${esc(p.id)}">${esc(tr('حذف'))}</a>` }], d.payments, { empty: 'ما فيه دفعات' })}</div>
    <div class="card"><h2>${esc(tr('سجل الاشتراك'))}</h2>
      ${tbl([{ t: 'التاريخ', h: h => `<span class="num">${esc(String(h.at).slice(0, 16).replace('T', ' '))}</span>` }, { t: 'الحالة بعد التغيير', h: h => esc(histTxt(h)) }], d.history, { empty: 'ما فيه تغييرات' })}</div>`;
  bindCopy(page); bindQuick(page, [c], st);
  if ($('#capp', page)) $('#capp', page).onclick = () => approveForm(c, st);
  $('#csub', page).onclick = () => subForm(c);
  $('#cpay', page).onclick = () => platPayForm(c, plans);
  $('#nform', page).onsubmit = async ev => { ev.preventDefault();
    const f = ev.target; try { await db.rpc('platform_add_note', { p_company: id, p_body: f.body.value, p_channel: f.channel.value, p_on: f.on.value || null }); platformView(); } catch (er) { showErr($('#nerr', page), er); } };
  $$('[data-dn]', page).forEach(a => a.onclick = async ev => { ev.preventDefault(); await db.rpc('platform_delete_note', { p_id: a.dataset.dn }); platformView(); });
  $$('[data-rc]', page).forEach(a => a.onclick = ev => { ev.preventDefault(); const p = d.payments.find(x => x.id === a.dataset.rc); if (p) printReceipt(c, p, plans.find(x => x.id === p.plan_id)); });
  $$('[data-dp]', page).forEach(a => a.onclick = async ev => { ev.preventDefault();
    if (!(await confirmBox(tr('حذف الدفعة'), tr('تنحذف من السجل والإيرادات. مدة الاشتراك ما تتغير.'), tr('حذف')))) return;
    await db.rpc('platform_delete_payment', { p_id: a.dataset.dp }); platformView(); });
};
// record a payment; choosing a plan fills the amount and its period, and the subscription is extended by it
function platPayForm(c, plans) {
  const act = plans.filter(p => p.active);
  const d = modal(tr('تسجيل دفعة') + ': ' + c.name, `<div class="fg">
      ${field('الباقة', `<select name="plan"><option value="">${esc(tr('بدون باقة'))}</option>${act.map(p => opt(p.id, p.name + ' · ' + money0(p.price), '')).join('')}</select>`)}
      ${field('المبلغ (ريال)', '<input name="amount" type="number" min="0.01" step="0.01" required>')}
      ${field('تاريخ الدفع', `<input name="paid_on" type="date" value="${today()}">`)}
      ${field('الطريقة', `<select name="method">${Object.entries(PAY_M).map(([k, t]) => opt(k, tr(t), 'transfer')).join('')}</select>`)}
      ${field('يمدّد الاشتراك بالأيام (فارغ = ما يمدّد)', '<input name="days" type="number" min="1" max="3660">')}
      ${field('ملاحظة', '<input name="note" maxlength="300">', 'wide')}</div>
    <p class="muted small">${esc(tr('إذا حددت مدة أو باقة، يصير الاشتراك «مفعّل» وتنضاف المدة بعد تاريخ نهايته الحالي.'))}</p>`, {
    onOk: async f => {
      await db.rpc('platform_add_payment', { p_company: c.company_id, p_amount: +f.amount, p_paid_on: f.paid_on || null, p_method: f.method,
        p_plan: f.plan || null, p_days: f.days ? +f.days : null, p_note: f.note || null });
      toast(tr('تم تسجيل الدفعة')); platformView();
    } });
  d.querySelector('[name=plan]').onchange = e => { const p = act.find(x => x.id === e.target.value); if (p) { d.querySelector('[name=amount]').value = p.price; d.querySelector('[name=days]').value = p.period_days; } };
}

/* ---------- revenue and price plans ---------- */
PV.billing = async page => {
  const y0 = today().slice(0, 4) + '-01-01', from = dayAgo(365).slice(0, 8) + '01';
  const [plans, pays, rows] = await Promise.all([db.rpc('platform_plans_list'), db.rpc('platform_payments_list', { p_from: from, p_to: today() }), db.rpc('platform_companies')]);
  const m0 = MONTH0(), lm = new Date(new Date(m0 + 'T12:00:00Z').getTime() - 20 * 864e5).toISOString().slice(0, 8) + '01';
  const sumIf = f => pays.filter(f).reduce((a, p) => a + (+p.amount || 0), 0);
  const months = Array.from({ length: 12 }, (_, i) => { const d = new Date(m0 + 'T12:00:00Z'); d.setUTCMonth(d.getUTCMonth() - 11 + i); return d.toISOString().slice(0, 7); });
  const paying = rows.filter(c => c.status === 'active' && subState(c)[1] !== 'bad').length;
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الإيرادات والباقات'))}</h1><div class="muted">${esc(tr('سجّل كل دفعة من صفحة المنشأة، وتنحسب هنا.'))}</div></div>
      <button class="btn pri" id="padd">${esc(tr('باقة جديدة'))}</button></div>
    <div class="grid" style="margin-bottom:14px">${pkpi('هذا الشهر', money0(sumIf(p => p.paid_on >= m0)), 'ريال')}${pkpi('الشهر الماضي', money0(sumIf(p => p.paid_on >= lm && p.paid_on < m0)), 'ريال')}
      ${pkpi('هذي السنة', money0(sumIf(p => p.paid_on >= y0)), 'ريال')}${pkpi('منشآت مشتركة', paying)}</div>
    <div class="card" style="margin-bottom:14px"><h2>${esc(tr('الإيرادات شهرياً (آخر ١٢ شهر)'))}</h2>${pbars(months.map(k => ({ k, v: Math.round(sumIf(p => p.paid_on.slice(0, 7) === k)) })), 'الإيرادات شهرياً (آخر ١٢ شهر)')}</div>
    <div class="card" style="margin-bottom:14px"><h2>${esc(tr('الباقات والأسعار'))}</h2>
      ${tbl([{ t: 'الباقة', h: p => `<b>${esc(p.name)}</b>` + (p.active ? '' : ` <span class="badge">${esc(tr('موقوفة'))}</span>`) }, { t: 'السعر', r: 1, h: p => money0(p.price) },
        { t: 'المدة', h: p => `<span class="num">${p.period_days}</span> ${esc(tr('يوم'))}` }, { t: 'الأقسام', h: p => p.modules.map(m => `<span class="badge">${esc(tr(MODULES[m] || m))}</span>`).join(' ') },
        { t: 'المستخدمون', r: 1, h: p => p.max_users || '—' }], plans, { empty: 'ما فيه باقات. أضف أول باقة.', onRow: true })}</div>
    <div class="card"><h2>${esc(tr('آخر الدفعات'))}</h2>
      ${tbl([{ t: 'التاريخ', h: p => `<span class="num">${esc(p.paid_on)}</span>` }, { t: 'المنشأة', h: p => esc(p.company) }, { t: 'المبلغ', r: 1, h: p => money0(p.amount) },
        { t: 'الباقة', h: p => esc(p.plan || '—') }, { t: 'الطريقة', h: p => esc(tr(PAY_M[p.method] || p.method)) }], pays.slice(0, 50), { empty: 'ما فيه دفعات', onRow: true })}</div>`;
  $('#padd', page).onclick = () => planForm({});
  const cards = $$('.card', page);
  bindRows(cards[2], plans, planForm);
  bindRows(cards[3], pays.slice(0, 50), p => { location.hash = '#/company/' + p.company_id; });
};
function planForm(p) {
  modal(p.id ? tr('تعديل الباقة') : tr('باقة جديدة'), `<div class="fg">${field('اسم الباقة', inp('name', p.name, 'maxlength="40" required'))}
      ${field('السعر (ريال)', inp('price', p.price, 'type="number" min="0" step="0.01" required'))}${field('المدة بالأيام', inp('period_days', p.period_days || 30, 'type="number" min="1" max="3660"'))}
      ${field('الحد الأعلى للمستخدمين (فارغ = بدون حد)', inp('max_users', p.max_users, 'type="number" min="1"'))}
      ${field('الأقسام', modChecks(p.modules || Object.keys(MODULES)), 'wide')}
      <label class="row small wide" style="gap:6px"><input type="checkbox" name="active" ${p.active === false ? '' : 'checked'} style="width:auto"> ${esc(tr('متاحة للاختيار'))}</label></div>`, {
    wide: true, onOk: async (f, d) => {
      const mods = pickMods($('#mform', d)); if (!mods.length) throw new Error('اختر قسماً واحداً على الأقل');
      await db.rpc('platform_save_plan', { p: { id: p.id || null, name: f.name, price: f.price, period_days: f.period_days, max_users: f.max_users || '', modules: mods, active: f.active } });
      toast(tr('تم الحفظ')); platformView();
    } });
}

// a receipt for a payment received (print or «Save as PDF»); Arabic and English on one sheet. Not a tax invoice.
function printReceipt(c, p, plan) {
  const no = 'R-' + String(p.id).replace(/-/g, '').slice(0, 8).toUpperCase(), M = PAY_M[p.method] || p.method;
  const M_EN = { transfer: 'Bank transfer', card: 'Card', cash: 'Cash', other: 'Other' }[p.method] || p.method;
  const row = (ar, en, v) => `<tr><th>${esc(ar)}<div class="en">${esc(en)}</div></th><td>${v}</td></tr>`;
  const w = document.createElement('div'); w.className = 'rcpt'; w.setAttribute('data-nt', '');
  w.innerHTML = `<div class="rh"><div>${brand()}</div><div class="rt"><b>إيصال استلام دفعة</b><div class="en">Payment receipt</div><div class="num">${esc(no)}</div></div></div>
    <table>${row('التاريخ', 'Date', `<span class="num">${esc(p.paid_on)}</span>`)}${row('استلمنا من', 'Received from', esc(c.name))}
      ${row('المبلغ', 'Amount', `<b class="num">${money0(p.amount)}</b> ريال · SAR`)}${row('طريقة الدفع', 'Method', esc(M) + ' · ' + esc(M_EN))}
      ${plan ? row('الباقة', 'Plan', esc(plan.name)) : ''}${p.days ? row('مدة الاشتراك', 'Period', `<span class="num">${p.days}</span> يوم · days`) : ''}
      ${p.note ? row('ملاحظة', 'Note', esc(p.note)) : ''}</table>
    <p class="rf">هذا إيصال استلام وليس فاتورة ضريبية.<br><span class="en">This is a receipt of payment, not a tax invoice.</span></p>
    <p class="rf">وعد · Waad — ${esc(SITE_URL)}</p>`;
  printWith(w, `@page{size:A5 portrait;margin:12mm}
    .rcpt{font-family:inherit;color:#111;direction:rtl}.rcpt .en{direction:ltr;font-size:11px;color:#555}
    .rcpt .rh{display:flex;justify-content:space-between;align-items:center;border-bottom:2px solid #946a24;padding-bottom:10px;margin-bottom:14px}
    .rcpt .rh .brand{justify-content:flex-start;margin:0}.rcpt .wlogo{height:40px}.rcpt .wl-d{display:none!important}.rcpt .wl-l{display:block!important}
    .rcpt .rt{text-align:left}.rcpt .rt b{font-size:18px}
    .rcpt table{width:100%;border-collapse:collapse;font-size:14px}.rcpt th,.rcpt td{border-bottom:1px solid #ddd;padding:8px 6px;text-align:start;vertical-align:top}
    .rcpt th{width:38%;color:#444;font-weight:600}.rcpt .rf{font-size:11px;color:#666;margin-top:14px;text-align:center}`);
}

/* ---------- support requests from customers ---------- */
const TK_KIND = { question: 'سؤال', problem: 'مشكلة', suggestion: 'اقتراح' };
const TK_ST = { open: ['بانتظار الرد', 'wait'], answered: ['تم الرد', 'ok'], closed: ['مغلق', ''] };
PV.support = async page => {
  const fk = ['open', 'answered', 'closed', 'all'].includes(LS.get('waad.tkf')) ? LS.get('waad.tkf') : 'open';
  const rows = await db.rpc('platform_tickets', { p_status: fk === 'all' ? null : fk });
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('طلبات الدعم'))}</h1><div class="muted">${esc(tr('أسئلة ومشاكل واقتراحات من مدراء المنشآت. ردّك يظهر لهم في النظام ويوصلهم على الإيميل.'))}</div></div></div>
    <div class="ptabs pfil">${[['open', 'بانتظار الرد'], ['answered', 'تم الرد'], ['closed', 'مغلق'], ['all', 'الكل']].map(([k, t]) => `<a href="#" data-tf="${k}"${k === fk ? ' aria-current="page"' : ''}>${esc(tr(t))}</a>`).join('')}</div>
    ${tbl([{ t: 'الطلب', h: r => `<b data-nt>${esc(r.subject)}</b><div class="small muted">${esc(tr(TK_KIND[r.kind]))}${r.route ? ' · <span dir="ltr">' + esc(r.route) + '</span>' : ''}</div>` },
      { t: 'المنشأة', h: r => esc(r.company) + `<div class="small muted" dir="ltr">${esc(r.author || '')}</div>` },
      { t: 'الحالة', h: r => `<span class="badge ${TK_ST[r.status][1]}">${esc(tr(TK_ST[r.status][0]))}</span>` },
      { t: 'التاريخ', h: r => `<span class="num">${esc(String(r.created_at).slice(0, 16).replace('T', ' '))}</span>` }], rows, { empty: 'ما فيه طلبات هنا', onRow: true })}`;
  $$('[data-tf]', page).forEach(a => a.onclick = e => { e.preventDefault(); LS.set('waad.tkf', a.dataset.tf); platformView(); });
  bindRows(page, rows, ticketForm);
};
function ticketForm(r) {
  const d = modal(r.subject, `<p class="small muted" style="margin-top:0">${esc(r.company)} · <span dir="ltr">${esc(r.author || '')}</span> · <span class="num">${esc(String(r.created_at).slice(0, 16).replace('T', ' '))}</span>${r.route ? ' · <span dir="ltr">' + esc(r.route) + '</span>' : ''}</p>
    <div class="supb card" style="padding:10px 12px" data-nt>${esc(r.body)}</div>
    <div class="fg" style="margin-top:12px">${field('ردّك', `<textarea name="reply" rows="5" maxlength="3000">${esc(r.reply || '')}</textarea>`, 'wide')}
      ${field('الحالة', `<select name="status">${opt('answered', tr('تم الرد'), r.status === 'open' ? 'answered' : r.status)}${opt('open', tr('بانتظار الرد'), r.status === 'open' ? '' : r.status)}${opt('closed', tr('مغلق'), r.status)}</select>`)}</div>
    <div class="row" style="gap:8px;flex-wrap:wrap;margin-top:8px">${mailBtns(r.author, 'وعد: ' + r.subject)}</div>`, {
    wide: true, ok: 'حفظ وإرسال', onOk: async f => {
      if (f.status === 'answered' && !(f.reply || '').trim()) throw new Error('اكتب الرد');
      await db.rpc('platform_reply_ticket', { p_id: r.id, p_reply: f.reply || null, p_status: f.status });
      toast(tr('تم الحفظ — يوصل الرد للعميل على الإيميل خلال دقائق')); platformView();
    } });
  bindCopy(d);
}

/* ---------- script errors users ran into (message, place, screen; no record contents) ---------- */
PV.errors = async page => {
  const n = [1, 7, 30].includes(LS.get('waad.errdays')) ? LS.get('waad.errdays') : 7;
  const rows = await db.rpc('platform_errors', { p_days: n });
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('أخطاء النظام'))}</h1><div class="muted">${esc(tr('أخطاء صارت في متصفحات المستخدمين، مجمّعة حسب الرسالة. ما فيها أي بيانات من داخل المنشآت.'))}</div></div>
      <select id="edays" style="width:auto">${[1, 7, 30].map(d => opt(d, tr('آخر') + ' ' + d + ' ' + tr('يوم'), n)).join('')}</select></div>
    <div class="grid" style="margin-bottom:14px">${pkpi('أخطاء مختلفة', rows.length)}${pkpi('مرات الحدوث', rows.reduce((a, r) => a + r.times, 0))}${pkpi('منشآت تأثرت', rows.length ? Math.max(...rows.map(r => r.companies)) : 0, 'أعلى عدد لخطأ واحد')}</div>
    ${tbl([{ t: 'الخطأ', h: r => `<span dir="ltr" class="small" style="word-break:break-word">${esc(r.message)}</span>` }, { t: 'الشاشة', h: r => `<span dir="ltr" class="small">${esc(r.route || '—')}</span>` },
      { t: 'مرات', r: 1, h: r => r.times }, { t: 'مستخدمين', r: 1, h: r => r.users }, { t: 'منشآت', r: 1, h: r => r.companies },
      { t: 'آخر مرة', h: r => `<span class="num">${esc(String(r.last_at).slice(0, 16).replace('T', ' '))}</span>` }], rows, { empty: 'ما فيه أخطاء في هذي الفترة 👌', onRow: true })}
    <p class="muted small">${esc(tr('اضغط على خطأ لتشوف مكانه في الكود والمتصفح. أرسل الصورة للمطوّر.'))}</p>`;
  $('#edays', page).onchange = e => { LS.set('waad.errdays', +e.target.value); platformView(); };
  bindRows(page, rows, r => modal(tr('تفاصيل الخطأ'), `<div dir="ltr" class="small" style="white-space:pre-wrap;word-break:break-word" data-nt><b>${esc(r.message)}</b>
source: ${esc(r.source || '—')}
screen: ${esc(r.route || '—')}
browser: ${esc(r.agent || '—')}
times: ${r.times} · users: ${r.users} · companies: ${r.companies} · last: ${esc(String(r.last_at))}</div>`));
};
