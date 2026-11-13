'use strict';
/* «مركز المساعدة» (#/help) and the «؟» button in the top bar (help_lib.js holds the texts), and «ابدأ هنا» (#/welcome):
   the company's setup steps, each ticked by itself from the data. Owners see the progress on the home page until done. */
function helpModal() {
  const f = helpFor(location.hash), body = f ? `<ol style="padding-inline-start:20px;margin:0">${f[1].s.map(x => `<li style="margin-bottom:6px">${esc(hT(x))}</li>`).join('')}</ol>`
    : `<p class="muted">${esc(tr('لا يوجد شرح لهذه الصفحة بعد.'))}</p>`;
  const d = modal(f ? hT(f[1].t) : tr('مركز المساعدة'), `<div data-nt>${body}</div>
    <p class="small" style="margin-top:12px"><a href="#/help" id="hall">${esc(tr('كل الشروحات'))}</a>${has('owner', 'admin', 'hr', 'finance', 'accountant') ? ` · <a href="#/support" id="hsup">${esc(tr('ما لقيت جوابك؟ راسل الدعم الفني'))}</a>` : ''}</p>`, { ok: 'تم' });
  ['#hall', '#hsup'].forEach(s => { const a = d.querySelector(s); if (a) a.addEventListener('click', () => d.close()); });
}
VIEWS['#/help'] = async page => {
  const list = Object.entries(HELP);
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('مركز المساعدة'))}</h1><div class="muted">${esc(tr('شرح مختصر لكل صفحة. وفي أي صفحة اضغط «؟» أعلى الشاشة ليظهر شرحها.'))}</div></div></div>
    <input id="hq" type="search" aria-label="${esc(tr('بحث في الشروحات'))}" placeholder="${esc(tr('ابحث، مثل: الرواتب، فاتورة، زاتكا'))}" style="max-width:420px;margin-bottom:12px">
    <div id="hl" data-nt>${list.map(([k, v]) => `<details class="card hitem" data-k="${esc(k)}" style="margin-bottom:8px"><summary style="cursor:pointer"><b>${esc(hT(v.t))}</b></summary>
      <ol style="padding-inline-start:20px;margin:8px 0 0">${v.s.map(x => `<li style="margin-bottom:6px">${esc(hT(x))}</li>`).join('')}</ol>
      <a class="small" href="${esc(k)}">${esc(LANG === 'en' ? 'Open the page' : 'افتح الصفحة')}</a></details>`).join('')}</div>
    ${has('owner', 'admin', 'hr', 'finance', 'accountant') ? `<p class="small muted">${esc(tr('ما لقيت جوابك؟'))} <a href="#/support">${esc(tr('راسل الدعم الفني'))}</a></p>` : ''}`;
  $('#hq', page).oninput = e => { const q = e.target.value.trim().toLowerCase();
    $$('.hitem', page).forEach(x => { const hit = !q || x.textContent.toLowerCase().includes(q); x.style.display = hit ? '' : 'none'; if (q && hit) x.open = true; }); };
};

// «ابدأ هنا»: what is done is read from the company's own data
async function setupSteps() {
  const co = S.company || {}, cnt = async (t, q) => (await db.get(t, Object.assign({ company_id: 'eq.' + S.cid, select: 'id', limit: 2 }, q || {})).catch(() => [])).length;
  const [emps, mem, runs, inv, zs] = await Promise.all([modOn('hr') ? cnt('employees') : 0, cnt('members'), modOn('hr') ? cnt('payroll_runs') : 0,
    modOn('sales') ? cnt('sales_invoices') : 0, modOn('sales') && co.vat_no ? db.get('zatca_settings', { company_id: 'eq.' + S.cid, select: 'enabled' }).catch(() => []) : []]);
  const z = zs[0];
  return [
    { k: 'co', t: 'أكمل بيانات المنشأة', d: 'السجل التجاري والعنوان الوطني (والرقم الضريبي إن كنت مسجّلاً) — تظهر في الفواتير والخطابات.', ok: !!(co.cr_no && co.city && co.street), h: '#/settings' },
    { k: 'logo', t: 'ارفع شعار المنشأة', d: 'يظهر أعلى الفواتير والخطابات والنماذج المطبوعة.', ok: !!co.logo, h: '#/settings' },
    ...(modOn('hr') ? [{ k: 'me', t: 'أضف نفسك كموظف', d: 'ليظهر لك نظام الطلبات وقسائم الراتب، ويُعرف أنك المدير العام في مسارات الاعتماد.', ok: !!S.emp, btn: 'me' },
      { k: 'emps', t: 'أضف الموظفين', d: 'سجلات الموظفين ورواتبهم ومديريهم المباشرين — أو استوردهم من Excel.', ok: emps >= 2, h: '#/employees' }] : []),
    { k: 'team', t: 'أعطِ فريقك الدخول', d: 'الموظف من سجله في «الموظفون» ← «إنشاء دخول للموظف»، والمدراء من «المستخدمون والدعوات».', ok: mem >= 2, h: '#/users', code: true },
    { k: 'mfa', t: 'فعّل التحقق بخطوتين', d: 'حتى لا تكفي كلمة المرور وحدها للدخول إلى الرواتب والأموال.', ok: !!(S.mfa && S.mfa.enrolled), btn: 'mfa' },
    ...(modOn('hr') ? [{ k: 'pay', t: 'جهّز أول مسير رواتب', d: 'يُحسب الراتب والتأمينات، ويعتمده المالك، ويُخرج ملف حماية الأجور.', ok: runs > 0, h: '#/payroll' }] : []),
    ...(modOn('sales') ? [{ k: 'inv', t: 'أصدر أول فاتورة', d: 'فاتورة ضريبية أو مبسطة فيها رمز QR، وتُرحّل في الحسابات تلقائياً.', ok: inv > 0, h: '#/sales' }] : []),
    ...(modOn('sales') && co.vat_no ? [{ k: 'zatca', t: 'اربط منشأتك بـ «فاتورة» (زاتكا)', d: 'لترسل فواتيرك لزاتكا تلقائياً كما تشترط المرحلة الثانية.', ok: !!(z && z.enabled), h: '#/settings' }] : [])];
}
VIEWS['#/welcome'] = async page => {
  const st = await setupSteps(), done = st.filter(s => s.ok).length;
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('ابدأ هنا'))}</h1><div class="muted">${esc(tr('خطوات تجهيز منشأتك، وكل خطوة تنتهي تتعلّم تلقائياً.'))}</div></div></div>
    <div class="card"><b>${esc(tr('تم'))} <span class="num">${done}</span> ${esc(tr('من'))} <span class="num">${st.length}</span></b>
      <div style="height:8px;background:var(--line);border-radius:6px;margin-top:8px;overflow:hidden"><div style="height:100%;width:${Math.round(done / st.length * 100)}%;background:var(--ok, #16a34a)"></div></div></div>
    ${st.map((s, i) => `<div class="card setstep" data-k="${s.k}" style="${s.ok ? 'opacity:.7' : ''}"><div class="row" style="justify-content:space-between;align-items:flex-start;gap:10px">
      <div><h2 style="margin:0 0 4px">${s.ok ? '✓' : (i + 1) + '.'} ${esc(tr(s.t))}</h2><p class="muted small" style="margin:0">${esc(tr(s.d))}</p>
      ${s.code ? `<p class="small" style="margin:6px 0 0">${esc(tr('رمز المنشأة لدخول الموظفين'))}: <b class="num">${esc(S.company.code || '')}</b> <button class="btn sm" id="ccw">${esc(tr('إرسال رمز المنشأة لبريدي'))}</button></p>` : ''}</div>
      <div>${s.ok ? `<span class="badge ok">${esc(tr('تم'))}</span>` : s.btn ? `<button class="btn sm pri" data-b="${s.btn}" id="${s.btn === 'me' ? 'me' : 'mfab'}">${esc(tr(s.btn === 'me' ? 'إضافة بياناتي' : 'تفعيل'))}</button>` : `<a class="btn sm pri" href="${s.h}">${esc(tr('ابدأ'))}</a>`}</div></div></div>`).join('')}
    <p class="small muted">${esc(tr('تحتاج مساعدة؟'))} <a href="#/help">${esc(tr('مركز المساعدة'))}</a>${has('owner', 'admin') ? ' · <a href="#/support">' + esc(tr('الدعم الفني')) + '</a>' : ''}</p>`;
  const me = page.querySelector('[data-b=me]'), mf = page.querySelector('[data-b=mfa]');
  if (me) me.onclick = () => employeeForm(null, { linkMe: true });
  if (mf) mf.onclick = mfaSetup;
  if ($('#ccw', page)) $('#ccw', page).onclick = () => companyCodeBox(false);
};
