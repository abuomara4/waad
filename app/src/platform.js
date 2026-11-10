'use strict';
/* The admin site (site/admin/, Waad's own team only): companies and subscriptions, system numbers, website visitors,
   website texts, and announcements to every company. Metadata only: no company records are ever read here. */
const SUB_ST = { trial: ['تجربة', 'wait'], active: ['مفعّلة', 'ok'], suspended: ['موقوفة', 'bad'] };
const subState = c => c.status === 'trial' && c.trial_ends && c.trial_ends < today() ? ['انتهت التجربة', 'bad'] : SUB_ST[c.status] || [c.status, ''];
const PTABS = [['companies', 'المنشآت'], ['system', 'أرقام النظام'], ['site', 'زوار الموقع'], ['content', 'محتوى الموقع'], ['news', 'الإعلانات'], ['team', 'فريق وعد']];
const PV = {};   // tab id -> async (page) => void
const dayAgo = n => new Date(new Date(today() + 'T12:00:00Z').getTime() - n * 864e5).toISOString().slice(0, 10);
const pct = (a, b) => b ? Math.round(a * 100 / b) + '%' : '—';
const pkpi = (label, v, sub = '') => `<div class="card kpi"><div class="muted small">${esc(tr(label))}</div><div class="v num">${v}</div>${sub ? `<div class="small muted">${esc(tr(sub))}</div>` : ''}</div>`;
// a simple daily bar chart: one bar per day, the first and last dates under it
function pbars(pts, label) {
  const mx = Math.max(1, ...pts.map(p => p.v));
  return `<div class="pbars" role="img" aria-label="${esc(tr(label))}">${pts.map(p => `<div class="pb" title="${esc(p.k)}: ${p.v}"><i style="height:${p.v ? Math.max(4, Math.round(p.v / mx * 100)) : 0}%"></i></div>`).join('')}</div>
    <div class="pbx small muted"><span class="num">${esc(pts[0].k)}</span><span class="num">${esc(pts[pts.length - 1].k)}</span></div>`;
}

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
  const tab = (location.hash.match(/^#\/(\w+)/) || [])[1], cur = PV[tab] ? tab : 'companies';
  const app = $('#app');
  if (!$('#ppage')) {
    app.innerHTML = `<div class="plat"><header class="top"><div class="brand">${brand()}</div><div class="cname"><b>${esc(tr('لوحة إدارة وعد'))}</b></div><div class="sp"></div>
        <a class="btn sm" href="${SITE_URL}" target="_blank" rel="noopener">${esc(tr('الموقع'))}</a><a class="btn sm" href="${APP_URL}" target="_blank" rel="noopener">${esc(tr('النظام'))}</a>
        <button class="btn sm" id="ppw">${esc(tr('تغيير كلمة المرور'))}</button><button class="btn sm" id="pmfa">${esc(tr('التحقق بخطوتين'))}</button>${langBtn('btn sm')}<button class="btn sm" id="plo">${esc(tr('تسجيل الخروج'))}</button></header>
      <nav class="ptabs" id="ptabs" aria-label="${esc(tr('أقسام اللوحة'))}"></nav>
      <main class="page" id="ppage"></main></div>`;
    $('#plo').onclick = async () => { await authApi.signOut(); S.platform = false; authView(); };
    $('#pmfa').onclick = () => mfaSetup();
    $('#ppw').onclick = () => changePasswordView(false);
    $('#lg').onclick = () => setLang(LANG === 'en' ? 'ar' : 'en');
  }
  $('#ptabs').innerHTML = PTABS.map(([k, t]) => `<a href="#/${k}"${k === cur ? ' aria-current="page"' : ''}>${esc(tr(t))}</a>`).join('');
  const page = $('#ppage'); page.innerHTML = `<div class="muted">${esc(tr('جارٍ التحميل…'))}</div>`;
  try { await PV[cur](page); } catch (e) { if (page.isConnected) page.innerHTML = `<div class="err">${esc(e.message)}</div>`; }
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
function notAdminView() {
  $('#app').innerHTML = `<div class="auth"><div class="abox">${brand()}<div class="card"><h2>${esc(tr('هذا الحساب ليس من فريق وعد'))}</h2>
    <p class="muted">${esc(tr('لوحة الإدارة لفريق وعد فقط. لإدارة منشأتك ادخل النظام.'))}</p>
    <div class="row" style="gap:8px"><a class="btn pri" href="${APP_URL}">${esc(tr('فتح النظام'))}</a><button class="btn" id="plo">${esc(tr('تسجيل الخروج'))}</button></div></div></div></div>`;
  $('#plo').onclick = async () => { await authApi.signOut(); authView(); };
}

/* ---------- companies and subscriptions ---------- */
PV.companies = async page => {
  const [rows, st] = await Promise.all([db.rpc('platform_companies'), db.rpc('platform_get_settings')]);
  const live = rows.filter(c => subState(c)[1] !== 'bad'), q = (LS.get('waad.platq') || '').toLowerCase();
  const shown = rows.filter(c => !q || (c.name + ' ' + (c.owner_email || '') + ' ' + c.plan).toLowerCase().includes(q));
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('المنشآت والاشتراكات'))}</h1><div class="muted">${esc(tr('بيانات الاشتراك فقط — لا تظهر هنا بيانات المنشآت نفسها.'))}</div></div></div>
    <div class="grid" style="margin-bottom:14px">${pkpi('المنشآت', rows.length)}${pkpi('مفعّلة', rows.filter(c => c.status === 'active').length)}
      ${pkpi('تجربة', rows.filter(c => c.status === 'trial' && subState(c)[1] !== 'bad').length)}${pkpi('مغلقة (موقوفة أو انتهت تجربتها)', rows.length - live.length)}
      ${pkpi('المستخدمون', rows.reduce((a, c) => a + (c.users || 0), 0))}</div>
    <div class="row" style="margin-bottom:10px;gap:8px;flex-wrap:wrap"><input id="pq" placeholder="${esc(tr('بحث بالاسم أو البريد أو الباقة'))}" value="${esc(q)}" style="max-width:320px">
      <div class="sp"></div><button type="button" class="btn sm" data-copymail="${esc([...new Set(shown.map(c => c.owner_email).filter(Boolean))].join(', '))}">${esc(tr('نسخ إيميلات المنشآت الظاهرة'))}</button></div>
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
  bindRows(page, shown, subForm); bindCopy(page);
  $('#psf', page).onsubmit = async e => { e.preventDefault(); const f = e.target;
    try { await busy($('#psb', page), async () => { await db.rpc('platform_set_settings', { p_modules: pickMods(f), p_trial_days: f.days.value ? +f.days.value : null }); toast(tr('تم الحفظ')); }); }
    catch (er) { showErr($('#pserr', page), er); } };
};
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
    <div class="card" style="margin-top:12px;padding:10px 12px"><b>${esc(tr('التواصل مع المالك'))}</b> <span class="small muted" dir="ltr">${esc(c.owner_email || '')}</span>
      <div class="row" style="gap:8px;flex-wrap:wrap;margin-top:8px">${mailBtns(c.owner_email, 'وعد: ' + c.name)}</div></div>
    <p class="muted small">${esc(tr('التغيير يظهر في سجل التدقيق الخاص بالمنشأة. إغلاق قسم لا يحذف بياناته — تعود عند فتحه.'))}</p>`, {
    wide: true, onOk: async (f, d) => {
      const mods = pickMods($('#mform', d) || d.querySelector('form'));
      if (!mods.length) throw new Error('اختر قسماً واحداً على الأقل');
      await db.rpc('platform_set_subscription', { p_company: c.company_id, p_plan: f.plan, p_modules: mods, p_status: f.status, p_trial_ends: f.trial_ends || null, p_max_users: f.max_users ? +f.max_users : null, p_note: f.note || null });
      toast(tr('تم الحفظ')); platformView();
    } });
  bindCopy($('#dlg'));
}

/* ---------- system numbers (from the same subscription metadata) ---------- */
PV.system = async page => {
  const rows = await db.rpc('platform_companies'), t0 = today();
  const since = n => rows.filter(c => String(c.created_at).slice(0, 10) > dayAgo(n)).length;
  const active7 = rows.filter(c => c.last_sign_in && String(c.last_sign_in).slice(0, 10) > dayAgo(7)).length;
  const ending = rows.filter(c => c.status === 'trial' && c.trial_ends && c.trial_ends >= t0 && c.trial_ends <= dayAgo(-3)).sort((a, b) => a.trial_ends < b.trial_ends ? -1 : 1);
  const paid = rows.filter(c => c.status === 'active').length, decided = rows.filter(c => c.status !== 'trial' || subState(c)[1] === 'bad').length;
  const quiet = rows.filter(c => subState(c)[1] !== 'bad' && (!c.last_sign_in || String(c.last_sign_in).slice(0, 10) <= dayAgo(14)));
  const days = Array.from({ length: 30 }, (_, i) => dayAgo(29 - i));
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('أرقام النظام'))}</h1><div class="muted">${esc(tr('من بيانات الاشتراك وآخر دخول فقط.'))}</div></div></div>
    <div class="grid" style="margin-bottom:14px">${pkpi('تسجيلات آخر ٧ أيام', since(7))}${pkpi('تسجيلات آخر ٣٠ يوماً', since(30))}
      ${pkpi('منشآت دخلت آخر ٧ أيام', active7, rows.length ? pct(active7, rows.length) + ' ' + tr('من المنشآت') : '')}
      ${pkpi('نسبة التحويل إلى اشتراك', pct(paid, decided), 'من المنشآت اللي انتهت تجربتها أو اشتركت')}${pkpi('تجارب تنتهي خلال ٣ أيام', ending.length)}</div>
    <div class="card" style="margin-bottom:14px"><h2>${esc(tr('التسجيلات الجديدة يومياً (آخر ٣٠ يوماً)'))}</h2>${pbars(days.map(k => ({ k, v: rows.filter(c => String(c.created_at).slice(0, 10) === k).length })), 'التسجيلات الجديدة يومياً (آخر ٣٠ يوماً)')}</div>
    <div class="g2p">
      <div class="card"><h2>${esc(tr('تجارب تنتهي قريباً'))}</h2><p class="muted small" style="margin-top:0">${esc(tr('تواصل معهم قبل ما تنتهي التجربة.'))}</p>
        ${tbl([{ t: 'المنشأة', h: c => esc(c.name) + `<div class="small muted" dir="ltr">${esc(c.owner_email || '—')}</div>` }, { t: 'نهاية التجربة', h: c => `<span class="num">${esc(c.trial_ends)}</span>` }, { t: '', h: c => c.owner_email ? `<a class="btn sm" href="${esc(gmailTo(c.owner_email, 'وعد: ' + c.name))}" target="_blank" rel="noopener">${esc(tr('مراسلة'))}</a>` : '' }], ending, { empty: 'لا توجد تجارب تنتهي خلال ٣ أيام' })}</div>
      <div class="card"><h2>${esc(tr('منشآت ما دخلت من أسبوعين'))}</h2><p class="muted small" style="margin-top:0">${esc(tr('اشتراكها مفتوح وما أحد دخل منها من ١٤ يوماً أو أكثر.'))}</p>
        ${tbl([{ t: 'المنشأة', h: c => esc(c.name) + `<div class="small muted" dir="ltr">${esc(c.owner_email || '—')}</div>` }, { t: 'آخر دخول', h: c => c.last_sign_in ? `<span class="num">${esc(String(c.last_sign_in).slice(0, 10))}</span>` : '—' }, { t: '', h: c => c.owner_email ? `<a class="btn sm" href="${esc(gmailTo(c.owner_email, 'وعد: ' + c.name))}" target="_blank" rel="noopener">${esc(tr('مراسلة'))}</a>` : '' }], quiet, { empty: 'كل المنشآت نشطة' })}</div></div>`;
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
