'use strict';
/* ===== home ===== */
VIEWS['#/home'] = async page => {
  const cards = [];
  if (isHR()) { try { const n = await db.rpc('apply_deemed_resignations', { p_company: S.cid }); if (n) toast(n + ' استقالة اعتُبرت مقبولة لمضي 30 يوماً دون رد (م79 مكرر)'); } catch (e) {} }
  const pend = await pendingForMe().catch(() => []);
  NAVC.approvals = pend.length; drawNav();
  if (!['accountant', 'storekeeper'].includes(S.role) || S.emp) cards.push(`<a class="card kpi" href="#/approvals"><div class="muted small">بانتظار اعتمادك</div><div class="v num">${pend.length}</div></a>`);
  if (S.emp) {
    const mine = await db.get('requests', { employee_id: 'eq.' + S.emp, status: 'eq.pending', select: 'id' });
    cards.push(`<a class="card kpi" href="#/requests"><div class="muted small">طلباتي قيد المعالجة</div><div class="v num">${mine.length}</div></a>`);
    if (S.company.att_enabled && !(S.myEmp && S.myEmp.att_exempt)) { const [t] = await db.rpc('att_sheet', { p_company: S.cid, p_from: rToday(), p_to: rToday(), p_emp: S.emp }).catch(() => []);
      cards.push(`<a class="card kpi" href="#/attendance"><div class="muted small">حضور اليوم</div><div class="v">${t ? atBadge(t.status) : '—'} ${t && t.check_in ? '<span class="small">حضور <b class="num">' + hm(t.check_in) + '</b>' + (t.check_out ? ' · انصراف <b class="num">' + hm(t.check_out) + '</b>' : '') + '</span>' : ''}</div></a>`); }
    const bal = await leaveBalance();
    cards.push(`<a class="card kpi" href="#/requests"><div class="muted small">رصيد الإجازة السنوية</div><div class="v num">${bal.left} <span class="small muted">يوماً متراكماً (${bal.ent} يوماً/سنة)</span></div></a>`);
  }
  if (isHR()) { const emps = await db.get('employees', { company_id: 'eq.' + S.cid, end_date: 'is.null', select: 'id' }); cards.push(`<a class="card kpi" href="#/employees"><div class="muted small">الموظفون على رأس العمل</div><div class="v num">${emps.length}</div></a>`);
    NAVC.docs = await docAlertCount(); drawNav(); cards.push(`<a class="card kpi" href="#/docs"><div class="muted small">مستندات وعقود منتهية أو تنتهي خلال 30 يوماً</div><div class="v num ${NAVC.docs ? 'bad' : ''}">${NAVC.docs}</div></a>`); }
  if (can('sales')) { const inv = await db.get('sales_invoices', { company_id: 'eq.' + S.cid, status: 'eq.posted', select: 'total' }); cards.push(`<a class="card kpi" href="#/sales"><div class="muted small">إجمالي المبيعات المرحّلة</div><div class="v num">${money(inv.reduce((a, x) => a + n0(x.total), 0))}</div></a>`); }
  if (can('purch')) { const b = await db.get('purchase_bills', { company_id: 'eq.' + S.cid, status: 'eq.posted', select: 'total' }); cards.push(`<a class="card kpi" href="#/purchases"><div class="muted small">إجمالي المشتريات المرحّلة</div><div class="v num">${money(b.reduce((a, x) => a + n0(x.total), 0))}</div></a>`); }
  // first-use guide: a dismissible banner that walks a new owner back to the setup steps
  // on a phone, suggest installing the app once (until installed or dismissed)
  const inst = !isStandalone() && innerWidth < 760 && !LS.get('waad.instx') ? `<div class="note" id="instg" style="display:flex;justify-content:space-between;align-items:center;gap:10px"><span>${esc(tr('ثبّت وعد على جوالك ليفتح مثل التطبيق — مجاناً وبدون متجر.'))}</span><span style="white-space:nowrap"><button class="btn sm pri" id="instb">${esc(tr('ثبّت'))}</button> <button class="btn sm" id="instx" aria-label="${esc(tr('إخفاء'))}">×</button></span></div>` : '';
  const ss = has('owner', 'admin') && !LS.get('waad.setupdone') ? await setupSteps().catch(() => []) : [], sd = ss.filter(x => x.ok).length;
  const setup = ss.length && sd < ss.length
    ? `<div class="note" id="setupg" style="display:flex;justify-content:space-between;align-items:center;gap:10px"><span>${esc(tr('ابدأ هنا: جهّز منشأتك'))} — ${esc(tr('تم'))} <b class="num">${sd}</b> ${esc(tr('من'))} <b class="num">${ss.length}</b></span><span style="white-space:nowrap"><a class="btn sm pri" href="#/welcome">${esc(tr('أكمل'))}</a> <button class="btn sm" id="setupx" aria-label="${esc(tr('إخفاء'))}">×</button></span></div>` : '';
  const nudge = !S.emp && !['accountant', 'storekeeper'].includes(S.role) ? `<div class="note">حسابك غير مربوط بسجل موظف، لذلك لا تظهر لك خدمات الإجازات والطلبات. ${isHR() ? '<a href="#/welcome">اربطه الآن</a>' : 'اطلب من الموارد البشرية ربطه.'}</div>` : '';
  const pp = await pendingPolicies().catch(() => []);
  const polNote = pp.length ? `<a class="note" href="#/policies" style="display:block">${esc(tr('سياسات بانتظار إقرارك'))}: <b class="num">${pp.length}</b> — ${pp.map(p => esc((LANG === 'en' && p.title_en) || p.title)).join('، ')}</a>` : '';
  // owners and finance hold the keys to payroll and money: nudge them to turn on two-step verification
  const mfaNote = has('owner', 'admin', 'finance') && S.mfa && !S.mfa.enrolled ? `<div class="note">${esc(tr('احمِ حسابك: فعّل التحقق بخطوتين حتى لا تكفي كلمة المرور وحدها للدخول.'))} <button class="btn sm" id="mfan">${esc(tr('تفعيل الآن'))}</button></div>` : '';
  page.innerHTML = `<div class="head"><div><h1>أهلاً${S.myEmp ? '، ' + esc(S.myEmp.full_name.split(' ')[0]) : ''}</h1><div class="muted">${esc(S.company.name)}</div></div>${isHR() || has('finance') ? `<a class="btn" href="#/hrdash">${esc(tr('لوحة الموارد البشرية'))}</a>` : ''}</div>${setup}${inst}${nudge}${polNote}${mfaNote}<div class="grid">${cards.join('')}</div>`;
  if ($('#instb', page)) $('#instb', page).onclick = installApp;
  if ($('#instx', page)) $('#instx', page).onclick = () => { LS.set('waad.instx', 1); $('#instg', page).remove(); };
  if ($('#setupx', page)) $('#setupx', page).onclick = () => { LS.set('waad.setupdone', 1); const g = $('#setupg', page); if (g) g.remove(); };
  if ($('#mfan', page)) $('#mfan', page).onclick = mfaSetup;
};
// Art. 109: annual leave accrues daily — 21 days a year, 30 after five continuous years
async function leaveBalance() {
  if (!S.myEmp) return { ent: 0, used: 0, left: 0 };
  const [b] = await db.rpc('annual_leave_balance', { p_emp: S.emp });
  const yrs = (new Date(today()) - new Date(S.myEmp.hire_date)) / 864e5 / 365;
  return { ent: yrs >= 5 ? 30 : 21, used: n0(b && b.taken), left: Math.floor(n0(b && b.balance)) };
}

/* ===== first-run checklist for a new owner ===== */
/* ===== my requests ===== */
const LEAVE_TYPES = async () => cache.lt || (cache.lt = await db.get('leave_types', { order: 'code' }));
VIEWS['#/requests'] = async page => {
  if (!S.emp) { page.innerHTML = '<div class="note">حسابك غير مربوط بسجل موظف.</div>'; return; }
  const [rs, bal, cpr] = await Promise.all([db.get('requests', { employee_id: 'eq.' + S.emp, order: 'created_at.desc' }), leaveBalance(), db.rpc('my_purchase_allowed', { p_company: S.cid }).catch(() => false)]);
  S.canPR = cpr === true;
  const lt = await LEAVE_TYPES(); const ltn = {}; lt.forEach(l => ltn[l.code] = l.name_ar);
  page.innerHTML = `<div class="head"><div><h1>طلباتي</h1><div class="muted">رصيد الإجازة السنوية المتراكم: <b class="num">${bal.left}</b> يوماً · الاستحقاق ${bal.ent} يوماً في السنة (م109)</div></div><button class="btn pri" id="nr">طلب جديد</button></div>
    ${tbl([{ t: 'النوع', h: r => esc(KIND[r.kind] + (r.sub ? ' — ' + (ltn[r.sub] || r.sub) : '')) }, { t: 'من', h: r => fdate(r.from_date) }, { t: 'إلى', h: r => fdate(r.to_date) },
      { t: 'أيام/مبلغ', r: 1, h: r => r.amount != null ? money(r.amount) : (r.days || (r.payload && r.payload.hours ? r.payload.hours + ' س' : '—')) },
      { t: 'الحالة', h: r => badge(r.status) + (r.status === 'pending' ? ` <span class="muted small">${esc(tr('عند'))} ${esc(tr(STEP[r.route[r.step]] || ''))} · ${esc(waitTxt(r.step_at))}</span>` : '') },
      { t: '', h: r => r.status === 'pending' && !(r.kind === 'resign' && (Date.now() - new Date(r.created_at)) > 7 * 864e5) ? `<button class="btn sm" data-cancel="${r.id}">${r.kind === 'resign' ? 'العدول عن الاستقالة' : 'إلغاء'}</button>` : '' }], rs, { empty: 'لا توجد طلبات بعد', onRow: true })}`;
  bindRows(page, rs, r => requestDetail(r));
  $$('[data-cancel]', page).forEach(b => b.onclick = async ev => { ev.stopPropagation(); if (!await confirmBox('إلغاء الطلب', 'هل تريد إلغاء هذا الطلب؟', 'إلغاء الطلب')) return; try { await db.rpc('cancel_request', { p_id: b.dataset.cancel }); toast('أُلغي الطلب'); route(); } catch (e) { toast(e.message); } });
  $('#nr', page).onclick = () => newRequest(lt);
};
const EXAM_MODE = { approved: 'سنة غير معادة — إجازة بأجر كامل', repeat: 'سنة دراسية معادة — بدون أجر', own: 'من رصيد الإجازة السنوية' };
const EVENT_LEAVES = { marriage: 'تُحتسب 5 أيام من تاريخ الزواج — م113', death: 'تُحتسب 5 أيام من تاريخ الوفاة — م113', death2: 'تُحتسب 3 أيام من تاريخ الوفاة — م113', birth: '3 أيام تؤخذ خلال 7 أيام من تاريخ الولادة — م113', iddah: 'تبدأ من تاريخ الوفاة ولا تقل عن 4 أشهر و10 أيام — م160', iddahn: '15 يوماً من تاريخ الوفاة — م160' };
function newRequest(lt) {
  const g = S.myEmp && S.myEmp.gender;
  const leaveOpts = lt.filter(l => !l.gender || l.gender === g).map(l => opt(l.code, l.name_ar + (l.article ? ' (' + l.article + ')' : ''))).join('');
  modal('طلب جديد', `<div class="fg">${field('نوع الطلب', `<select name="kind" id="rk">${Object.entries(Object.assign({ leave: 'إجازة', permit: 'استئذان' }, S.company && S.company.att_enabled ? { punch: 'نسيان بصمة' } : {}, { advance: 'سلفة', expense: 'مطالبة مصروفات' }, S.canPR ? { purchase: 'طلب شراء' } : {}, { cert: 'تعريف بالراتب' }, S.myEmp && S.myEmp.ticket_every ? { ticket: 'تذكرة سفر' } : {}, S.myEmp && S.myEmp.is_saudi === false ? { visa: 'تأشيرة خروج وعودة' } : {}, { resign: 'استقالة' })).map(([k, t]) => opt(k, t)).join('')}</select>`)}
    <div data-k="leave">${field('نوع الإجازة', `<select name="sub">${leaveOpts}</select>`)}</div>
    <div data-k="leave permit">${field('من / التاريخ', `<input type="date" name="from" value="${today()}">`)}</div>
    <div data-k="punch">${field('يوم البصمة المنسية', `<input type="date" name="pday" value="${today()}" max="${today()}">`)}</div>
    <div data-k="punch">${field('وقت الحضور', `<input type="time" name="pin">`)}</div>
    <div data-k="punch">${field('وقت الانصراف', `<input type="time" name="pout">`)}</div>
    <div data-k="punch" class="wide"><p class="muted small" style="margin:0">اكتب الوقت الذي نسيت بصمته (الحضور أو الانصراف أو كليهما). بعد اعتماده يُصحَّح سجل حضورك تلقائياً. خلال 30 يوماً من اليوم.</p></div>
    <div data-k="permit punch" class="wide"><p class="small" id="limh" style="margin:0"></p></div>
    <div data-k="leave">${field('إلى', `<input type="date" name="to" value="${today()}">`)}</div>
    <div data-k="visa ticket">${field('تاريخ السفر', `<input type="date" name="tfrom" value="${today()}">`)}</div>
    <div data-k="visa">${field('تاريخ العودة', `<input type="date" name="tto" value="${today()}">`)}</div>
    <div data-k="leave" class="wide" id="trvw" hidden><div class="card" style="margin:0;padding:10px 12px"><b class="small">${esc(tr('السفر مع الإجازة'))}</b>
      <div id="tkw" hidden><label class="row small" style="gap:6px;margin:6px 0 0"><input type="checkbox" name="wt" style="width:auto">${esc(tr('أحتاج تذكرة السفر المستحقة'))}</label></div>
      <div id="vzw" hidden><label class="row small" style="gap:6px;margin:6px 0 0"><input type="checkbox" name="wv" style="width:auto">${esc(tr('أحتاج تأشيرة خروج وعودة'))}</label></div></div></div>
    <div data-k="tkt">${field('التذكرة', `<select name="tmode">${opt('ticket', tr('تذكرة تحجزها المنشأة'))}${opt('cash', tr('بدل نقدي'))}</select>`)}</div>
    <div data-k="tkt">${field('عدد المسافرين', inp('tpers', (S.myEmp || {}).ticket_persons || 1, 'type="number" min="1" max="' + ((S.myEmp || {}).ticket_persons || 1) + '"'))}</div>
    <div data-k="tkt" class="wide"><p class="muted small" id="tkh" style="margin:0"></p></div>
    <div data-k="vz">${field('نوع التأشيرة', `<select name="vtype">${opt('single', tr('خروج وعودة مفردة'))}${opt('multiple', tr('خروج وعودة متعددة'))}</select>`)}</div>
    <div data-k="vz" class="wide"><p class="muted small" style="margin:0">${esc(tr('تصدرها الموارد البشرية بعد الاعتماد، ويُسجَّل رقمها وآخر موعد للعودة في طلبك.'))}</p></div>
    <div data-k="annual" class="wide"><p class="muted small" style="margin:0">العطل الرسمية داخل الإجازة السنوية لا تُحسب من رصيدك، وتُمدَّد الإجازة بقدرها (م24 من اللائحة التنفيذية).</p></div>
    <div data-k="exam" class="wide">${field('حالة الدراسة (م115)', `<select name="exam_mode">${opt('approved', EXAM_MODE.approved)}${opt('repeat', EXAM_MODE.repeat)}</select>`)}<p class="muted small" style="margin:4px 0 0">أيام الاختبارات إجازة بأجر كامل بعدد أيام الاختبار الفعلية، عدا اختبارات السنة المعادة فبدون أجر. قدّم الطلب قبل 15 يوماً على الأقل، ويسقط الأجر إذا ثبت عدم أداء الامتحان.</p></div>
    <div data-k="comp" class="wide"><p class="muted small" id="comph" style="margin:0"></p></div>
    <div data-k="doc" class="wide"><div><label id="doch"></label><input type="file" name="files" id="rqf" multiple accept="image/*,application/pdf"></div><div id="refw" style="margin-top:8px"><label id="refh" for="rqref"></label><input name="doc_ref" id="rqref" dir="ltr" maxlength="40" autocomplete="off"></div><p class="muted small" style="margin:4px 0 0">${esc('صورة أو PDF (حتى 3 ميجابايت للملف). تراه الموارد البشرية فقط.')}</p></div>
    <div data-k="event" class="wide">${field('تاريخ الواقعة (الزواج/الوفاة/الولادة)', `<input type="date" name="event" value="${today()}">`)}<p class="muted small" id="evh" style="margin:4px 0 0"></p></div>
    <div data-k="permit">${field('عدد الساعات (حتى 4)', `<input name="hours" type="number" step="0.5" min="0.5" max="4" value="1">`)}</div>
    <div data-k="permit" class="wide"><p class="muted small" style="margin:0">بعد اعتماده يغطي الاستئذان التأخير أو الخروج المبكر في يومه بقدر ساعاته، فلا يُخصم.</p></div>
    <div data-k="purchase" class="wide"><div class="tw"><table class="lines"><thead><tr><th>${esc(tr('الصنف أو الخدمة المطلوبة'))}</th><th>${esc(tr('الكمية'))}</th><th>${esc(tr('السعر التقديري'))}</th></tr></thead><tbody id="prl">${[0, 1, 2].map(prRow).join('')}</tbody>
      <tfoot><tr><td colspan="2">${esc(tr('الإجمالي التقديري'))}</td><td class="num" id="prt">0.00</td></tr></tfoot></table></div><button type="button" class="btn sm" id="pra" style="margin-top:6px">+ ${esc(tr('بند'))}</button></div>
    <div data-k="purchase">${field('مطلوب بتاريخ', `<input type="date" name="pneed" min="${today()}">`)}</div>
    <div data-k="purchase" class="wide"><p class="muted small" style="margin:0">${esc(tr('يمر الطلب على مديرك ثم المالية ثم المدير العام، وبعد اعتماده يصدر قسم المشتريات أمر الشراء. اكتب الغرض في الملاحظات.'))}</p></div>
    <div data-k="advance expense">${field('المبلغ', `<input name="amount" type="number" step="0.01" min="0">`)}</div>
    <div data-k="advance">${field('عدد الأقساط', `<input name="inst" type="number" min="1" max="24" value="1">`)}</div>
    <div data-k="advance" class="wide"><p class="muted small" id="advh" style="margin:0"></p></div>
    <div data-k="resign" class="wide"><div class="note">حسب المادة 79 مكرر: لا يُحدد للاستقالة تاريخ مؤجل، وتنتهي العلاقة من تاريخ قبولها. وإذا لم يُرد عليها خلال 30 يوماً تُعد مقبولة. ويحق لك العدول عنها خلال 7 أيام من تقديمها. تبقى ملتزماً بالعمل خلال هذه المدة.</div></div>
    ${field('ملاحظات', `<textarea name="note" rows="2"></textarea>`, 'wide')}</div>`, {
    ok: 'إرسال', onOk: async f => {
      const k = f.kind, a = { p_company: S.cid, p_kind: k, p_note: blank(f.note), p_payload: {} };
      if (k === 'leave') { Object.assign(a, { p_sub: f.sub, p_from: f.from, p_to: f.to }); if (EVENT_LEAVES[f.sub]) a.p_payload = { event_date: f.event }; if (f.sub === 'exam') a.p_payload = { exam_mode: f.exam_mode };
        const ltx = lt.find(l => l.code === f.sub), fl = [...($('#rqf').files || [])];
        if (ltx && ltx.doc_label && !fl.length) throw new Error(tr('أرفق المستند المطلوب') + ': ' + docLabel(ltx));
        const ref = (f.doc_ref || '').replace(/\s/g, '');
        if (ltx && ltx.ref_required && ref.length < 5) throw new Error(tr('اكتب') + ' ' + refLabel(ltx));
        if (ref && ltx && ltx.ref_label) a.p_payload = Object.assign({}, a.p_payload, { doc_ref: ref });
        if (fl.length) a.p_payload = Object.assign({}, a.p_payload, { files: await Promise.all(fl.slice(0, 5).map(readAttachment)) }); }
      if (k === 'leave') { if (f.wt) a.p_payload = Object.assign({}, a.p_payload, { ticket: { mode: f.tmode, persons: +f.tpers || 1 } }); if (f.wv) a.p_payload = Object.assign({}, a.p_payload, { visa: { type: f.vtype } }); }
      if (k === 'ticket') Object.assign(a, { p_from: blank(f.tfrom), p_payload: { mode: f.tmode, persons: +f.tpers || 1 } });
      if (k === 'visa') Object.assign(a, { p_from: f.tfrom, p_to: f.tto, p_payload: { visa_type: f.vtype } });
      if (k === 'permit') Object.assign(a, { p_from: f.from, p_to: f.from, p_payload: { hours: +f.hours } });
      if (k === 'punch') { if (!f.pin && !f.pout) throw new Error('اكتب وقت الحضور أو الانصراف'); Object.assign(a, { p_from: f.pday, p_payload: { in: f.pin || null, out: f.pout || null } }); }
      if (k === 'purchase') { const ls = $$('#prl tr').map(tr => ({ desc: $('[data-p=d]', tr).value.trim(), qty: +$('[data-p=q]', tr).value, price: +($('[data-p=p]', tr).value || 0) })).filter(l => l.desc);
        if (!ls.length) throw new Error('أضف بنداً واحداً على الأقل'); if (ls.some(l => !(l.qty > 0))) throw new Error('الكمية أكبر من صفر');
        Object.assign(a, { p_from: blank(f.pneed), p_payload: { lines: ls } }); }
      if (k === 'advance' || k === 'expense') { if (!(+f.amount > 0)) throw new Error('أدخل المبلغ'); a.p_amount = +f.amount; if (k === 'advance') a.p_payload = { inst: +f.inst || 1 }; }
      await db.rpc('submit_request', a); toast('أُرسل الطلب'); route();
    }
  });
  const D = $('#dlg'), gross = S.myEmp ? n0(S.myEmp.basic) + n0(S.myEmp.housing) + n0(S.myEmp.transport) : 0;
  const sync = () => {
    const k = $('#rk').value, sub = D.querySelector('[name=sub]').value, ev = k === 'leave' && EVENT_LEAVES[sub];
    const subK = { annual: 1, exam: 1, comp: 1 }, ltx = lt.find(l => l.code === sub), need = k === 'leave' && ltx && ltx.doc_label;
    const fm = $('#mform', D) || D.querySelector('form') || D, wt = k === 'ticket' || (k === 'leave' && D.querySelector('[name=wt]').checked), wv = k === 'visa' || (k === 'leave' && D.querySelector('[name=wv]').checked);
    $$('[data-k]', D).forEach(d => d.hidden = d.dataset.k === 'event' ? !ev : d.dataset.k === 'doc' ? !need : d.dataset.k === 'tkt' ? !wt : d.dataset.k === 'vz' ? !wv : subK[d.dataset.k] ? !(k === 'leave' && sub === d.dataset.k) : !d.dataset.k.split(' ').includes(k));
    const me = S.myEmp || {}; $('#tkw', D).hidden = !me.ticket_every; $('#vzw', D).hidden = me.is_saudi !== false; $('#trvw', D).hidden = k !== 'leave' || (!me.ticket_every && me.is_saudi !== false);
    if (wt && !$('#tkh', D).dataset.done) { $('#tkh', D).dataset.done = 1; db.rpc('ticket_status', { p_emp: S.emp }).then(([t]) => { if (!t) return;
      $('#tkh', D).innerHTML = `${esc(tr('رصيد التذاكر المستحقة'))}: <b class="num">${t.available}</b> · ${esc(tr('المسافرون'))} <span class="num">${t.persons}</span>${t.dest ? ' · ' + esc((LANG === 'en' && t.dest_en) || t.dest) : ''}${t.available < 1 ? ' · <span class="bad">' + esc(tr('الاستحقاق القادم')) + ' ' + fdate(t.next_due) + '</span>' : ''}`; }).catch(() => {}); }
    if (need) { $('#doch', D).textContent = tr('المرفق المطلوب') + ': ' + docLabel(ltx); $('#refw', D).hidden = !ltx.ref_label;
      if (ltx.ref_label) $('#refh', D).textContent = refLabel(ltx) + (ltx.ref_required ? '' : ' (' + tr('اختياري') + ')'); }
    if ((k === 'permit' || k === 'punch') && !$('#limh', D).dataset.done) { $('#limh', D).dataset.done = 1; db.rpc('my_month_limits', { p_company: S.cid }).then(([m]) => { if (!m) return;
      const parts = []; if (m.permit_limit != null) parts.push(`${tr('الاستئذان هذا الشهر')}: <b class="num">${r2(n0(m.permit_used))} / ${r2(n0(m.permit_limit))}</b> ${tr('ساعة')}`);
      if (m.punch_limit != null) parts.push(`${tr('نسيان البصمة هذا الشهر')}: <b class="num">${m.punch_used} / ${m.punch_limit}</b>`);
      $('#limh', D).innerHTML = parts.join(' · '); }).catch(() => {}); }
    if (k === 'leave' && sub === 'comp' && !$('#comph', D).dataset.done) { $('#comph', D).dataset.done = 1; db.rpc('comp_balance', { p_emp: S.emp }).then(([b]) => { const h = n0(b && b.balance_hours); $('#comph', D).innerHTML = `${tr('رصيدك من الإجازة التعويضية')}: <b class="num">${r2(h)}</b> ${tr('ساعة')} (<span class="num">${Math.floor(h / 8)}</span> ${tr('يوم')}) — ${tr('تُحسب من ساعات العمل الإضافي التي اخترت التعويض عنها بإجازة بدل الأجر (م107).')}`; }).catch(() => {}); }
    if (ev) $('#evh', D).textContent = EVENT_LEAVES[sub];
    const amt = n0(D.querySelector('[name=amount]').value), cap = r2(gross * 0.10);
    if (k === 'advance') $('#advh', D).textContent = gross ? `القسط الشهري لا يزيد على 10% من أجرك (${money(cap)}) — م92.` + (amt ? ` أقل عدد أقساط لهذا المبلغ: ${Math.ceil(amt / cap)}.` : '') : '';
  };
  const prTot = () => { $('#prt', D).textContent = money($$('#prl tr', D).reduce((t, tr) => t + r2(n0($('[data-p=q]', tr).value) * n0($('[data-p=p]', tr).value)), 0)); };
  $('#pra', D).onclick = () => { $('#prl', D).insertAdjacentHTML('beforeend', prRow($$('#prl tr', D).length)); };
  $('#prl', D).addEventListener('input', prTot);
  D.addEventListener('input', sync); D.addEventListener('change', sync); sync();
}
const prRow = i => `<tr><td><input data-p="d" maxlength="200" style="min-width:180px" aria-label="${esc(tr('البند'))} ${i + 1}"></td><td><input data-p="q" type="number" min="0" step="0.001" value="1" style="width:80px"></td><td><input data-p="p" type="number" min="0" step="0.01" style="width:110px"></td></tr>`;
async function requestDetail(r, { decide } = {}) {
  const [acts, tl] = await Promise.all([db.get('request_actions', { request_id: 'eq.' + r.id, order: 'at' }), db.rpc('request_timeline', { p_id: r.id }).catch(() => null)]);
  const label = { submitted: 'أُرسل', approved: 'اعتُمد', rejected: 'رُفض', cancelled: 'أُلغي', attached: 'أُرفق مستند' };
  const atts = r.kind === 'leave' ? await db.get('request_attachments', { request_id: 'eq.' + r.id, select: 'id,file_name,mime,size,created_at', order: 'created_at' }).catch(() => []) : [];
  const canAttach = r.kind === 'leave' && (isHR() || (r.employee_id === S.emp && r.status === 'pending'));
  const lt = await LEAVE_TYPES(); const ln = (lt.find(l => l.code === r.sub) || {}).name_ar;
  const body = `<p><b>${esc(KIND[r.kind])}${ln ? ' — ' + esc(ln) : ''}</b> ${badge(r.status)}</p>
    ${r._emp ? `<p>الموظف: ${esc(r._emp.full_name)} <span class="muted">(${esc(r._emp.emp_no)})</span></p>` : ''}
    ${r.kind === 'purchase' ? `<div class="tw"><table><thead><tr><th>${esc(tr('البند'))}</th><th class="r">${esc(tr('الكمية'))}</th><th class="r">${esc(tr('السعر التقديري'))}</th></tr></thead><tbody>${((r.payload || {}).lines || []).map(l => `<tr><td>${esc(l.desc)}</td><td class="r num">${+l.qty}</td><td class="r num">${money(l.price)}</td></tr>`).join('')}</tbody></table></div>${r.from_date ? `<p class="small">${esc(tr('مطلوب بتاريخ'))} <span class="num">${fdate(r.from_date)}</span></p>` : ''}` : ''}
    <p class="muted">${r.from_date && r.kind !== 'purchase' ? 'من ' + fdate(r.from_date) + ' إلى ' + fdate(r.to_date) + (r.days ? ' — ' + r.days + ' يوماً' : '') : ''}${r.amount != null ? ' المبلغ: ' + money(r.amount) : ''}${r.payload && r.payload.hours ? ' — ' + r.payload.hours + ' ساعة' : ''}${r.payload && r.payload.inst ? ' — ' + r.payload.inst + ' أقساط' : ''}${r.kind === 'punch' ? ` — ${esc(tr('الحضور'))} <b class="num">${esc(r.payload.in || '—')}</b> · ${esc(tr('الانصراف'))} <b class="num">${esc(r.payload.out || '—')}</b>` : ''}</p>
    ${r.kind === 'update' ? `<div class="tw"><table><tbody>${Object.entries(r.payload || {}).map(([k, v]) => `<tr><td class="muted">${esc({ phone: 'الجوال', email: 'البريد الشخصي', iban: 'الآيبان', marital_status: 'الحالة الاجتماعية', dependents: 'عدد المرافقين', emergency_name: 'جهة اتصال الطوارئ', emergency_relation: 'صلة القرابة', emergency_phone: 'جوال الطوارئ', short_address: 'العنوان المختصر', national_address: 'العنوان الوطني' }[k] || k)}</td><td class="num">${esc(profileShow(k, v))}</td></tr>`).join('')}</tbody></table></div>` : ''}
    ${r.payload && r.payload.event_date ? `<p class="muted small">تاريخ الواقعة: ${fdate(r.payload.event_date)}</p>` : ''}
    ${r.payload && r.payload.exam_mode ? `<p class="muted small">${esc(EXAM_MODE[r.payload.exam_mode] || '')}${r.payload.exam_missed ? ' — <span class="bad">' + esc('لم يؤدِّ الامتحان: حُوّلت إلى إجازة بدون أجر (م115)') + '</span>' : ''}</p>` : ''}
    ${r.payload && r.payload.defer_until ? `<div class="note">${esc('أُجّل قبول الاستقالة لمصلحة العمل حتى')} <b class="num">${fdate(r.payload.defer_until)}</b> (${esc('م79 مكرر')}) — ${esc(r.payload.defer_reason || '')}</div>` : ''}
    ${r.note ? `<p>${esc(r.note)}</p>` : ''}
    ${!atts.length && !canAttach && lt.find(l => l.code === r.sub && l.doc_label) ? `<p class="muted small">${esc(tr('المرفق المطلوب') + ': ' + docLabel(lt.find(l => l.code === r.sub)))} — ${esc('تراه الموارد البشرية فقط')}</p>` : ''}
    ${atts.length || canAttach || (r.payload && r.payload.doc_ref) ? `<div class="card" style="margin:10px 0;padding:10px 12px"><b class="small">${esc('المرفقات')}</b>${r.payload && r.payload.doc_ref ? `<div class="small" style="margin-top:4px">${esc(refLabel(lt.find(l => l.code === r.sub) || {}) || tr('رقم المستند'))}: <b class="num" data-nt>${esc(r.payload.doc_ref)}</b>${r.sub === 'sick' && isHR() ? ` — <a href="https://www.seha.sa" target="_blank" rel="noopener">${esc('تحقق منه في منصة صحة')}</a>` : ''}</div>` : ''}${atts.length ? atts.map(x => `<div class="row small" style="justify-content:space-between;margin-top:6px"><span><span class="badge">${x.mime === 'application/pdf' ? 'PDF' : esc('صورة')}</span> ${esc(x.file_name)} <span class="muted num">${Math.ceil(x.size / 1024)} KB</span></span><button type="button" class="btn sm" data-att="${x.id}">${esc('عرض')}</button></div>`).join('') : `<p class="muted small" style="margin:6px 0 0">${esc('لا توجد مرفقات ظاهرة لك')}</p>`}
      ${canAttach ? `<div class="row" style="margin-top:8px"><label class="btn sm">${esc('إضافة مرفق')}<input type="file" id="ratt" multiple accept="image/*,application/pdf" hidden></label>${(lt.find(l => l.code === r.sub) || {}).ref_label ? `<button type="button" class="btn sm" id="rref">${esc(r.payload && r.payload.doc_ref ? 'تعديل رقم المستند' : 'إضافة رقم المستند')}</button>` : ''}</div>` : ''}</div>` : ''}
    ${travelBox(r, tl)}${journeyHtml(r, tl, acts)}
    ${decide ? await teamOverlap(r) : ''}
    ${decide ? field('ملاحظة (إلزامية عند الرفض)', '<textarea name="note" rows="2"></textarea>') : ''}`;
  const remind = r.status === 'pending' && !decide && (r.employee_id === S.emp || isHR()) ? await db.rpc('request_waiting_on', { p_id: r.id }).catch(() => []) : [];
  const empName = r._emp ? r._emp.full_name : (S.myEmp || {}).full_name || '';
  const since = String(r.created_at || '').slice(0, 10);
  const remMsg = w => 'السلام عليكم ' + w.full_name.split(' ')[0] + '،\nطلب ' + KIND[r.kind] + (ln ? ' (' + ln + ')' : '') + ' لـ ' + empName + ' بانتظار اعتمادك في نظام وعد منذ ' + since + '.\nللاطلاع والاعتماد: ' + location.origin + location.pathname + '#/approvals';
  const body2 = body + (remind.length ? `<div class="card" style="margin:12px 0 0;padding:12px"><b>تذكير عبر واتساب</b> <span class="muted small">بانتظار: ${esc(STEP[remind[0].step])}</span>
    <div class="row" style="margin-top:8px">${remind.map(w => waBtn(w.phone, tr(remMsg(w)), 'تذكير ' + w.full_name + (waPhone(w.phone) ? '' : ' (بدون جوال)'), 'btn sm wa')).join('')}</div></div>` : '');
  const certLs = r.kind === 'cert' && r.status === 'approved' && (r.employee_id === S.emp || isHR()) ? await db.get('letters', { request_id: 'eq.' + r.id }).catch(() => []) : null;
  const body3 = body2 + (certLs ? `<div class="card" style="margin:12px 0 0;padding:12px"><b>الخطاب</b><div class="row" style="margin-top:8px">${certLs.map(l => `<a class="btn sm" href="#/letter/${l.id}" onclick="document.getElementById('dlg').close()"><span class="num">${esc(l.ref_no)}</span> — ${l.lang === 'en' ? 'إنجليزي' : 'عربي'}</a>`).join('')}${certLs.length < 2 ? '<button type="button" class="btn sm pri" id="mkltr">إصدار الخطاب وطباعته</button>' : ''}</div></div>` : '');
  const hrResign = isHR() && r.kind === 'resign' && r.status === 'pending' && !(r.payload && r.payload.defer_until) && (Date.now() - new Date(r.created_at)) < 30 * 864e5;
  const hrExam = isHR() && r.kind === 'leave' && r.sub === 'exam' && r.status === 'approved';
  const body4 = body3 + (hrResign || hrExam || (r.payload && r.payload.defer_until) ? `<div class="row" style="margin-top:12px">${hrResign ? '<button type="button" class="btn sm" id="rdefer">تأجيل قبول الاستقالة</button>' : ''}${r.payload && r.payload.defer_until ? '<button type="button" class="btn sm" id="rdprint">طباعة إشعار التأجيل</button>' : ''}${hrExam ? '<button type="button" class="btn sm danger" id="xmiss">لم يؤدِّ الامتحان</button>' : ''}</div>` : '');
  const d = modal('تفاصيل الطلب', body4, decide ? { ok: 'اعتماد', onOk: async f => { await db.rpc('decide_request', { p_id: r.id, p_approve: true, p_note: blank(f.note) }); toast('تم الاعتماد'); route(); refreshCounts(); } } : {});
  $$('[data-att]', d).forEach(b => b.onclick = () => openAttachment(b.dataset.att));
  bindTravelFiles(d);
  if ($('#rref', d)) $('#rref', d).onclick = () => { const l = lt.find(x => x.code === r.sub) || {}; d.close();
    modal(refLabel(l), field(refLabel(l), inp('ref', (r.payload || {}).doc_ref || '', 'dir="ltr" maxlength="40" required')), { onOk: async f => { if ((f.ref || '').replace(/\s/g, '').length < 5) throw new Error(tr('اكتب') + ' ' + refLabel(l));
      await db.rpc('request_attach', { p_id: r.id, p_files: [], p_ref: f.ref }); toast('تم الحفظ'); route(); } }); };
  if ($('#ratt', d)) $('#ratt', d).onchange = async ev => { const fl = [...ev.target.files]; if (!fl.length) return;
    try { const files = await Promise.all(fl.slice(0, 5).map(readAttachment)); await db.rpc('request_attach', { p_id: r.id, p_files: files }); toast('أُرفق المستند'); d.close(); requestDetail(r, { decide }); } catch (er) { toast(er.message); } };
  const empOf = async () => r._emp || (r.employee_id === S.emp ? S.myEmp : (await employeesMap(true))[r.employee_id]) || {};
  if ($('#rdefer', d)) $('#rdefer', d).onclick = () => { d.close(); modal('تأجيل قبول الاستقالة', `<div class="fg">${field('مدة التأجيل بالأيام (حتى 60)', inp('days', 30, 'type="number" min="1" max="60"'))}${field('سبب التأجيل (مصلحة العمل)', '<textarea name="why" rows="3" required></textarea>', 'wide')}</div>
      <p class="muted small">م79 مكرر: لصاحب العمل تأجيل قبول الاستقالة مدة لا تزيد على 60 يوماً إذا اقتضت مصلحة العمل، بإشعار مكتوب مسبّب يُقدَّم للعامل قبل انتهاء 30 يوماً من تقديمها. تُحسب المدة من تاريخ الإشعار، وتنتهي العلاقة بانتهائها.</p>`, {
      ok: 'تأجيل', onOk: async f => { await db.rpc('resign_defer', { p_id: r.id, p_days: +f.days, p_reason: f.why }); toast('أُجّل قبول الاستقالة — اطبع الإشعار وسلّمه للموظف'); route(); } }); };
  if ($('#rdprint', d)) $('#rdprint', d).onclick = async () => { const e = await empOf(), p = r.payload;
    const n = document.createElement('div'); n.innerHTML = `<p>${esc('الموظف')}: <b>${esc(e.full_name || '')}</b> — ${esc('الرقم الوظيفي')} <span class="num">${esc(e.emp_no || '')}</span></p>
      <p><span>${esc('إشارة إلى طلب الاستقالة المقدَّم بتاريخ')}</span> <span class="num">${fdate(r.created_at)}</span><span>${esc('، نفيدكم بأن مصلحة العمل تقتضي تأجيل قبول الاستقالة مدة')}</span> <b class="num">${p.defer_days}</b> <span>${esc('يوماً من تاريخ هذا الإشعار')}</span> <span class="num">${fdate(p.defer_on)}</span><span>${esc('، وتنتهي في')}</span> <b class="num">${fdate(p.defer_until)}</b><span>${esc('، وذلك استناداً إلى المادة 79 مكرر من نظام العمل.')}</span></p>
      <p>${esc('سبب التأجيل')}: <b>${esc(p.defer_reason || '')}</b></p><p>${esc('تنتهي علاقة العمل بانتهاء مدة التأجيل، وتبقى ملتزماً بأداء عملك خلالها.')}</p>
      <div class="row" style="justify-content:space-between;margin-top:14mm">${['صاحب الصلاحية', 'استلام العامل والتاريخ'].map(t => `<div style="min-width:60mm"><div>${esc(t)}:</div><div style="border-bottom:1px dotted #777;height:9mm"></div></div>`).join('')}</div>`;
    printBlock(n, 'إشعار تأجيل قبول الاستقالة'); };
  if ($('#xmiss', d)) $('#xmiss', d).onclick = () => { d.close(); modal('لم يؤدِّ الامتحان', `${field('ملاحظة', '<textarea name="n" rows="2"></textarea>')}<p class="muted small">م115: يسقط الأجر عن إجازة الاختبارات إذا ثبت أن العامل لم يؤدِّ الامتحان، فتُحوَّل إلى إجازة بدون أجر وتُخصم في المسير.</p>`, {
      ok: 'تحويل لإجازة بدون أجر', onOk: async f => { await db.rpc('exam_not_sat', { p_id: r.id, p_note: blank(f.n) }); toast('تم'); route(); } }); };
  if ($('#mkltr', d)) $('#mkltr', d).onclick = async () => { const e = r.employee_id === S.emp ? S.myEmp : (await employeesMap(true))[r.employee_id]; d.close(); letterDialog(e, 'salary', r); };
  if (decide) {
    const rej = document.createElement('button'); rej.type = 'button'; rej.className = 'btn danger'; rej.textContent = 'رفض';
    $('.df', d).insertBefore(rej, $('#mok', d));
    rej.onclick = async () => { try { await busy(rej, () => db.rpc('decide_request', { p_id: r.id, p_approve: false, p_note: $('#mform', d).note.value })); d.close(); toast('تم الرفض'); route(); refreshCounts(); } catch (e) { showErr($('#merr', d), e); } };
  }
}

/* ===== approvals ===== */
VIEWS['#/approvals'] = async page => {
  const mine = await pendingForMe(); NAVC.approvals = mine.length; drawNav();
  const lt = await LEAVE_TYPES(); const ltn = {}; lt.forEach(l => ltn[l.code] = l.name_ar);
  page.innerHTML = `<div class="head"><div><h1>الاعتمادات</h1><div class="muted">الطلبات التي تنتظر قرارك</div></div></div>
   ${tbl([{ t: 'الموظف', h: r => esc(r._emp ? r._emp.full_name : '') }, { t: 'النوع', h: r => esc(KIND[r.kind] + (r.sub ? ' — ' + (ltn[r.sub] || r.sub) : '')) },
     { t: 'الفترة/المبلغ', h: r => r.amount != null ? `<span class="num">${money(r.amount)}</span>` : r.from_date ? fdate(r.from_date) + ' → ' + fdate(r.to_date) : '—' },
     { t: 'مرحلتك', h: r => esc(STEP[r.route[r.step]]) }, { t: 'تاريخ الطلب', h: r => fdate(r.created_at) }, { t: 'بانتظارك منذ', h: r => `<span class="${slaLate(r) ? 'bad' : 'muted'} small">${esc(waitTxt(r.step_at))}${slaLate(r) ? ' · ' + esc(tr('متأخر')) : ''}</span>` }], mine, { empty: 'لا شيء بانتظارك', onRow: true })}`;
  bindRows(page, mine, r => requestDetail(r, { decide: true }));
};

/* ===== payslips ===== */
VIEWS['#/payslips'] = async page => {
  if (!S.emp) { page.innerHTML = '<div class="note">حسابك غير مربوط بسجل موظف.</div>'; return; }
  const lines = await db.get('payroll_lines', { employee_id: 'eq.' + S.emp });
  const runs = lines.length ? await db.get('payroll_runs', { id: 'in.(' + lines.map(l => l.run_id).join(',') + ')' }) : [];
  const rm = {}; runs.forEach(r => rm[r.id] = r);
  const rows = lines.map(l => Object.assign({}, l, { _r: rm[l.run_id] })).filter(l => l._r).sort((a, b) => (b._r.year * 12 + b._r.month) - (a._r.year * 12 + a._r.month));
  page.innerHTML = `<div class="head"><div><h1>قسائم الراتب</h1></div></div>${tbl([{ t: 'الشهر', h: l => `${l._r.month}/${l._r.year}` }, { t: 'الإجمالي', r: 1, h: l => money(n0(l.gross) + n0(l.arrears)) }, { t: 'الاستقطاعات', r: 1, h: l => money(n0(l.gosi) + n0(l.absence) + n0(l.att_absence) + n0(l.late_deduction) + n0(l.sick_deduction) + n0(l.deductions) + n0(l.penalty_fine) + n0(l.damages) + n0(l.advance)) }, { t: 'الصافي', r: 1, h: l => '<b>' + money(l.net) + '</b>' }, { t: 'الحالة', h: l => badge(l._r.status) }], rows, { empty: 'لا توجد قسائم معتمدة بعد', onRow: true })}`;
  bindRows(page, rows, l => payslip(l, S.myEmp));
};
function payslip(l, e) {
  const row = (t, v, neg) => `<tr><td>${esc(t)}</td><td class="r num">${neg && n0(v) ? '−' : ''}${money(v)}</td></tr>`;
  const title = `قسيمة راتب ${l._r ? l._r.month + '/' + l._r.year : ''}`;
  const d = modal(title, `<div id="psl"><p><b>${esc(e ? e.full_name : '')}</b> <span class="muted">${esc(e ? e.emp_no : '')}</span>${l.paid_days != null && l.paid_days < 30 ? ` <span class="badge">${esc(tr('أيام مستحقة'))} <span class="num">${l.paid_days}/30</span></span>` : ''}</p><div class="tw"><table><tbody>
    ${row('الراتب الأساسي', l.basic)}${row('بدل السكن', l.housing)}${row('بدل النقل', l.transport)}${n0(l.allowances) ? row('بدلات أخرى', l.allowances) : ''}${n0(l.arrears) ? row(tr('مستحقات الشهر السابق') + ' (' + l.arrears_days + ' ' + tr('يوم') + ')', l.arrears) : ''}${n0(l.overtime) ? row('عمل إضافي (' + r2(n0(l.overtime_hours) + n0(l.att_ot_hours)) + ' ساعة)', l.overtime) : ''}${n0(l.bonus) ? row('مكافأة', l.bonus) : ''}
    ${row('التأمينات الاجتماعية', l.gosi, 1)}${n0(l.absence) ? row('غياب/إجازة بدون راتب (' + l.absence_days + ' يوم)', l.absence, 1) : ''}${n0(l.att_absence) ? row('غياب بدون عذر (' + l.att_absent_days + ' يوم)', l.att_absence, 1) : ''}${n0(l.late_deduction) ? row('تأخير (' + l.late_min + ' دقيقة)', l.late_deduction, 1) : ''}${n0(l.sick_deduction) ? row('إجازة مرضية (' + l.sick_days + ' يوم بأجر جزئي/بدون أجر)', l.sick_deduction, 1) : ''}${n0(l.deductions) ? row('غرامات', l.deductions, 1) : ''}${n0(l.penalty_fine) ? row('جزاءات تأديبية', l.penalty_fine, 1) : ''}${n0(l.damages) ? row('اقتطاع تلفيات', l.damages, 1) : ''}${n0(l.advance) ? row('قسط سلفة', l.advance, 1) : ''}
    </tbody><tfoot><tr><td>الصافي</td><td class="r num">${money(l.net)}</td></tr></tfoot></table></div></div>
    <div style="margin-top:10px"><button type="button" class="btn sm" id="pslp">طباعة</button></div>`);
  $('#pslp', d).onclick = () => printBlock($('#psl', d), title);
}

/* ===== profile ===== */
VIEWS['#/profile'] = async page => {
  const e = S.myEmp; if (!e) { page.innerHTML = '<div class="note">حسابك غير مربوط بسجل موظف.</div>'; return; }
  const [em, als, mm] = await Promise.all([employeesMap().catch(() => ({})), db.get('employee_allowances', { employee_id: 'eq.' + e.id }).catch(() => []),
    e.manager_id ? db.rpc('my_manager', { p_company: S.cid }).catch(() => null) : null]);
  const myAl = als.filter(a => allowActive(a));
  const mgr = e.manager_id && em[e.manager_id] ? em[e.manager_id].full_name : mm && mm.name ? mm.name + (mm.title ? ' — ' + mm.title : '') : '—';
  const mail = (S.session.user || {}).email || '', staffLogin = /@staff\.waad\.app$/i.test(mail);
  const r = (t, v) => `<tr><td class="muted">${esc(t)}</td><td>${v}</td></tr>`;
  page.innerHTML = `<div class="head"><div><h1>${esc(e.full_name)}</h1><div class="muted">${esc(e.job_title || '')}</div></div></div><div class="card"><div class="tw"><table><tbody>
    ${r('الرقم الوظيفي', esc(e.emp_no))}${staffLogin ? r('الدخول', esc(tr('برمز المنشأة ورقمك الوظيفي'))) : r('البريد', esc(mail))}${r('تاريخ المباشرة', fdate(e.hire_date))}${r('المدير المباشر', esc(mgr))}
    ${r('الراتب الأساسي', `<span class="num">${money(e.basic)}</span>`)}${r('بدل السكن', `<span class="num">${money(e.housing)}</span>`)}${r('بدل النقل', `<span class="num">${money(e.transport)}</span>`)}${myAl.map(a => r(a.name, `<span class="num">${money(a.amount)}</span>`)).join('')}
    ${r('الجوال', `<span class="num">${esc(e.phone || '—')}</span>`)}${r('البريد الشخصي', `<span class="num">${esc(e.email || '—')}</span>`)}${r('الآيبان', `<span class="num">${esc(e.iban || '—')}</span>`)}
    ${r('الجنسية', esc(e.nationality ? natName(e.nationality) : tr(e.is_saudi ? 'سعودي' : 'غير سعودي')))}${e.birth_date ? r('تاريخ الميلاد', fdate(e.birth_date)) : ''}${e.marital_status ? r('الحالة الاجتماعية', esc(profileShow('marital_status', e.marital_status))) : ''}${e.dependents != null ? r('عدد المرافقين', `<span class="num">${e.dependents}</span>`) : ''}
    ${e.education ? r('المؤهل الدراسي', esc(profileShow('education', e.education) + (e.specialization ? ' — ' + e.specialization : ''))) : ''}
    ${r('جهة اتصال الطوارئ', e.emergency_name ? esc(e.emergency_name + (e.emergency_relation ? ' (' + e.emergency_relation + ')' : '')) + ` <span class="num">${esc(e.emergency_phone || '')}</span>` : '—')}
    ${r('العنوان الوطني', esc([e.short_address, e.national_address].filter(Boolean).join(' — ') || '—'))}</tbody></table></div>
    <div class="row" style="margin-top:12px"><button class="btn pri" id="upd">طلب تعديل بياناتي</button><span class="muted small">التعديل يمر على الموارد البشرية، ويُطبَّق تلقائياً بعد اعتماده.</span></div></div>`;
  // documents, letters and training load in parallel and never hold up the buttons above
  (async () => { const [dh, lh, myl, th, ph, cu] = await Promise.all([myDocsHtml(), myLettersHtml(), lettersOf(S.emp), myTrainingHtml(), myPenaltiesHtml(), db.get('custody_items', { employee_id: 'eq.' + S.emp, order: 'issued_on.desc' }).catch(() => [])]);
    const cuh = cu.length ? `<div class="card"><h2>${esc(tr('عهدي'))}</h2>${tbl([{ t: 'العهدة', h: x => esc((LANG === 'en' && x.name_en) || x.name) + (x.serial ? ` <span class="num muted small">${esc(x.serial)}</span>` : '') }, { t: 'التسليم', h: x => fdate(x.issued_on) }, { t: 'الحالة', h: x => `<span class="badge ${CUST_ST[x.status][1]}">${esc(tr(CUST_ST[x.status][0]))}</span>` }], cu)}</div>` : '';
    if (!page.isConnected) return; page.insertAdjacentHTML('beforeend', '<div id="mylv"></div>' + dh + cuh + lh + ph + th); bindMyPenalties(page); leaveStatementCard($('#mylv', page), e).catch(() => {});
    if ($('#mylt', page)) bindRows($('#mylt', page), myl, l => location.hash = '#/letter/' + l.id); })().catch(() => {});
  $('#upd', page).onclick = () => modal('طلب تعديل بيانات', `<p class="muted small">غيّر ما تريد تعديله فقط.</p><div class="fg">${field('الجوال', inp('phone', e.phone, 'dir="ltr" placeholder="05XXXXXXXX"'))}${field('البريد الشخصي', inp('email', e.email, 'dir="ltr" type="email"'))}${field('الآيبان', inp('iban', e.iban, 'dir="ltr" placeholder="SA…" maxlength="24"'), 'wide')}
    ${field('الحالة الاجتماعية', `<select name="marital_status"><option value="">—</option>${Object.entries(MARITAL).map(([k, t]) => opt(k, t, e.marital_status)).join('')}</select>`)}${field('عدد المرافقين', inp('dependents', e.dependents, 'type="number" min="0" max="30"'))}
    ${field('جهة اتصال الطوارئ', inp('emergency_name', e.emergency_name))}${field('صلة القرابة', inp('emergency_relation', e.emergency_relation))}${field('جوال الطوارئ', inp('emergency_phone', e.emergency_phone, 'dir="ltr"'))}
    ${field('العنوان المختصر', inp('short_address', e.short_address, 'dir="ltr" maxlength="9" placeholder="RRRD2929" style="text-transform:uppercase"'))}${field('العنوان الوطني', inp('national_address', e.national_address), 'wide')}
    ${field('ملاحظة للموارد البشرية', '<textarea name="note" rows="2"></textarea>', 'wide')}</div>`, {
    ok: 'إرسال الطلب', onOk: async f => {
      const p = {}; ['phone', 'email', 'iban', 'marital_status', 'dependents', 'emergency_name', 'emergency_relation', 'emergency_phone', 'short_address', 'national_address'].forEach(k => { let v = String(f[k] || '').trim();
        if (k === 'iban' || k === 'short_address') v = v.replace(/\s/g, '').toUpperCase(); if (k === 'emergency_phone') v = v.replace(/[\s-]/g, '');
        if (v && v !== String(e[k] == null ? '' : e[k])) p[k] = v; });
      if (!Object.keys(p).length) throw new Error('لم تغيّر أي بيانات');
      await db.rpc('submit_request', { p_company: S.cid, p_kind: 'update', p_payload: p, p_note: blank(f.note) }); toast('أُرسل طلب التعديل للموارد البشرية'); location.hash = '#/requests';
    }
  });
  // my medical insurance cover (me and my dependants)
  const ins = await db.get('insurance_members', { employee_id: 'eq.' + e.id, status: 'eq.active', order: 'created_at' }).catch(() => []);
  if (ins.length) { const pols = await db.get('insurance_policies', { id: 'in.(' + [...new Set(ins.map(m => m.policy_id))].join(',') + ')' }).catch(() => []), pm = {}; pols.forEach(x => pm[x.id] = x);
    const c = document.createElement('div'); c.className = 'card';
    c.innerHTML = `<h2>${esc(tr('التأمين الطبي'))}</h2>${tbl([{ t: 'المؤمَّن عليه', h: m => m.relation === 'self' ? esc(tr('الموظف نفسه')) : esc(m.name) + ` <span class="small muted">(${esc(tr(REL[m.relation]))})</span>` },
      { t: 'الفئة', k: 'class' }, { t: 'رقم العضوية', h: m => `<span class="num">${esc(m.member_no || '—')}</span>` }, { t: 'شركة التأمين', h: m => esc((pm[m.policy_id] || {}).provider || '') },
      { t: 'نهاية الوثيقة', h: m => fdate((pm[m.policy_id] || {}).end_date) }], ins)}`;
    page.appendChild(c); }
};

/* ===== employees (HR) ===== */
VIEWS['#/employees'] = async (page, arg, q) => {
  const [em, deps, logins, probs, als] = await Promise.all([employeesMap(true), db.get('departments', { company_id: 'eq.' + S.cid, order: 'name' }), db.rpc('staff_logins', { p_company: S.cid }), db.rpc('probation_ends', { p_company: S.cid }).catch(() => []),
    db.get('employee_allowances', { company_id: 'eq.' + S.cid }).catch(() => [])]);
  const alSum = {}; als.filter(a => allowActive(a)).forEach(a => alSum[a.employee_id] = n0(alSum[a.employee_id]) + n0(a.amount));
  cache.deps = deps; const dm = {}; deps.forEach(d => dm[d.id] = d.name);
  cache.logins = {}; logins.forEach(l => cache.logins[l.employee_id] = l);
  const pend = {}; probs.forEach(p => pend[p.employee_id] = p.effective_end);
  const showEnded = q.get('all') === '1';
  const rows = cache.emps.filter(e => showEnded || !e.end_date || e.end_date >= today());
  const cols = [{ t: 'الرقم', k: 'emp_no' }, { t: 'الاسم', h: e => esc(e.full_name) }, { t: 'المسمى', h: e => esc(e.job_title || e.job_title_en || '') }, { t: 'القسم', h: e => esc(dm[e.department_id] || '—') }, { t: 'المدير', h: e => esc(e.manager_id && em[e.manager_id] ? em[e.manager_id].full_name : '—') },
      { t: 'الإجمالي', r: 1, h: e => money(n0(e.basic) + n0(e.housing) + n0(e.transport) + n0(alSum[e.id])) },
      { t: 'الدخول', h: e => { const l = cache.logins[e.id]; return !l ? '<span class="badge">بدون حساب</span>' : l.by_number ? '<span class="badge info">بالرقم الوظيفي</span>' + (l.must_change_password ? ' <span class="badge wait">لم يغيّر كلمة المرور بعد</span>' : '') : '<span class="badge info">بالبريد</span>'; } }, { t: 'الحالة', h: e => e.end_date && e.end_date < today() ? '<span class="badge bad">منتهية</span>' : e.end_date ? '<span class="badge wait">آخر يوم ' + fdate(e.end_date) + '</span>' : (pend[e.id] || e.probation_end) && (pend[e.id] || e.probation_end) >= today() ? '<span class="badge info">تحت التجربة حتى ' + fdate(pend[e.id] || e.probation_end) + '</span>' : '<span class="badge ok">على رأس العمل</span>' }];
  // one search box over everything: employee number, name (ar/en), job title, department, manager, national id, mobile
  const searchStr = e => [e.emp_no, e.full_name, e.full_name_en, e.job_title, e.job_title_en, dm[e.department_id], e.manager_id && em[e.manager_id] ? em[e.manager_id].full_name : '', e.national_id, e.iqama_no, e.mobile].filter(Boolean).join(' ').toLowerCase();
  page.innerHTML = `<div class="head"><div><h1>الموظفون</h1><div class="muted"><span id="ecount">${rows.length}</span> موظف</div></div><div class="row">
     <a class="btn" href="#/employees${showEnded ? '' : '?all=1'}">${showEnded ? 'على رأس العمل فقط' : 'إظهار المنتهية خدماتهم'}</a><button class="btn" id="dep">الأقسام</button><button class="btn" id="imx">استيراد من Excel</button><button class="btn" id="upx">تحديث جماعي من Excel</button><button class="btn" id="brs">زيادة جماعية</button><button class="btn pri" id="ne">إضافة موظف</button></div></div>
   <div style="margin-bottom:12px"><input id="esrch" type="search" placeholder="بحث: الرقم الوظيفي، الاسم، المسمى، القسم، المدير، الهوية، الجوال…" autocomplete="off"></div>
   <div id="emptbl"></div>`;
  const draw = term => { const t = (term || '').trim().toLowerCase(); const fr = t ? rows.filter(e => searchStr(e).includes(t)) : rows; const ec = $('#ecount', page); if (ec) ec.textContent = fr.length; $('#emptbl', page).innerHTML = tbl(cols, fr, { empty: t ? 'لا نتائج مطابقة' : 'لم تُضف موظفين بعد', onRow: true }); bindRows(page, fr, e => employeeForm(e)); };
  draw('');
  $('#esrch', page).oninput = e => draw(e.target.value);
  $('#ne', page).onclick = () => employeeForm(null);
  $('#dep', page).onclick = () => departmentsDlg();
  $('#imx', page).onclick = () => importDialog();
  $('#upx', page).onclick = () => updateEmployeesDialog();
  $('#brs', page).onclick = () => bulkRaiseDialog().catch(er => toast(er.message));
};
function departmentsDlg() {
  const list = () => (cache.deps || []).map(d => `<li class="row" style="justify-content:space-between"><span>${esc(d.name)}${d.name_en ? ' <span class="muted small" dir="ltr" data-nt>' + esc(d.name_en) + '</span>' : ''}</span><button type="button" class="btn sm danger" data-del="${d.id}">حذف</button></li>`).join('') || '<li class="muted">لا توجد أقسام</li>';
  const d = modal('الأقسام', `<ul class="timeline" id="dl">${list()}</ul><div class="row" style="margin-top:10px"><input name="name" placeholder="اسم القسم" style="flex:1"><input name="name_en" placeholder="الاسم بالإنجليزية" dir="ltr" style="flex:1"><button type="button" class="btn pri" id="da">إضافة</button></div>`);
  const redraw = () => { $('#dl', d).innerHTML = list(); $$('[data-del]', d).forEach(b => b.onclick = async () => { try { await db.del('departments', { id: 'eq.' + b.dataset.del }); cache.deps = cache.deps.filter(x => x.id !== b.dataset.del); redraw(); } catch (e) { showErr($('#merr', d), e); } }); };
  redraw();
  $('#da', d).onclick = async () => { const n = $('#mform', d).name.value.trim(); if (n.length < 2) return; try { const ne = $('#mform', d).name_en.value.trim(); const [x] = await db.ins('departments', { company_id: S.cid, name: n, name_en: ne || null }); learnNames(x, BILINGUAL.departments); cache.deps.push(x); $('#mform', d).name.value = ''; $('#mform', d).name_en.value = ''; redraw(); } catch (e) { showErr($('#merr', d), e); } };
  d.addEventListener('close', () => route(), { once: true });
}
async function employeeForm(e, { linkMe } = {}) {
  const em = await employeesMap(); const deps = cache.deps || (cache.deps = await db.get('departments', { company_id: 'eq.' + S.cid, order: 'name' }));
  const v = e || { is_saudi: true, gender: 'm', hire_date: today(), basic: '', housing: '', transport: '', emp_no: String(1000 + Object.keys(em).length) };
  const others = Object.values(em).filter(x => !e || x.id !== e.id);
  const grades = await db.get('job_grades', { company_id: 'eq.' + S.cid, order: 'code' }).catch(() => []);
  const [shifts, ccs, sites] = await Promise.all([db.get('shifts', { company_id: 'eq.' + S.cid, order: 'name' }).catch(() => []),
    db.get('cost_centers', { company_id: 'eq.' + S.cid, order: 'code' }).catch(() => []), db.get('work_sites', { company_id: 'eq.' + S.cid, order: 'name' }).catch(() => [])]);
  const sec = t => `<div class="wide muted small" style="margin:4px 0 -4px"><b>${esc(tr(t))}</b></div>`;
  const body = `<div class="fg">
    ${field('الرقم الوظيفي', inp('emp_no', v.emp_no, 'required dir="ltr"'))}${field('الاسم الكامل', inp('full_name', v.full_name, 'required'))}${field('الاسم بالإنجليزية', inp('full_name_en', v.full_name_en, 'dir="ltr"'))}
    ${field('رقم الهوية/الإقامة', inp('national_id', v.national_id, 'dir="ltr" inputmode="numeric" maxlength="10"'))}
    ${field('الجنسية', `<select name="nationality">${natOpts(v.nationality, v.is_saudi)}</select>`)}
    ${field('الجنس', `<select name="gender">${opt('m', 'ذكر', v.gender)}${opt('f', 'أنثى', v.gender)}</select>`)}
    ${field('المسمى الوظيفي', inp('job_title', v.job_title))}${field('المسمى الوظيفي بالإنجليزية', inp('job_title_en', v.job_title_en, 'dir="ltr"'))}
    ${field('القسم', `<select name="department_id"><option value="">—</option>${deps.map(d => opt(d.id, d.name, v.department_id)).join('')}</select>`)}
    ${grades.length ? field('الدرجة الوظيفية', `<select name="grade_id"><option value="">—</option>${grades.filter(g => g.active !== false || g.id === v.grade_id).map(g => opt(g.id, g.code + ' — ' + ((LANG === 'en' && g.name_en) || g.name) + ' (' + money(g.min_basic) + ' – ' + money(g.max_basic) + ')', v.grade_id)).join('')}</select>`) : ''}
    ${field('المدير المباشر', `<select name="manager_id"><option value="">—</option>${others.map(x => opt(x.id, x.full_name + ' (' + x.emp_no + ')', v.manager_id)).join('')}</select>`)}
    ${field('تاريخ المباشرة', `<input type="date" name="hire_date" value="${esc(v.hire_date)}">`)}
    ${field('مدة التجربة — تُحسب نهايتها تلقائياً', `<select name="prob_days"><option value="">— إدخال يدوي —</option>${[30, 60, 90, 180].map(d => opt(String(d), d + ' يوماً', e ? '' : '90')).join('')}</select>`)}
    ${field('نهاية فترة التجربة (حد أقصى 180 يوماً — م53)', `<input type="date" name="probation_end" value="${esc(e ? (v.probation_end || '') : addDays(v.hire_date, 90))}">`)}
    ${field('نظام التأمينات', `<select name="gosi_new">${opt('', 'حسب تاريخ أول تسجيل (تلقائي)', v.gosi_new == null ? '' : '')}${opt('false', 'النظام السابق (قبل 3 يوليو 2024)', v.gosi_new === false ? 'false' : '-')}${opt('true', 'النظام الجديد', v.gosi_new === true ? 'true' : '-')}</select>`)}
    ${field('الوردية', `<select name="shift_id"><option value="">${esc(tr('وردية القسم أو الافتراضية'))}</option>${shifts.map(s => opt(s.id, s.name + ' (' + s.start_time.slice(0, 5) + '–' + s.end_time.slice(0, 5) + ')', v.shift_id)).join('')}</select>`)}
    ${field('طلبات الشراء', `<select name="can_request_purchase">${opt('false', tr('حسب إعداد المنشأة'), String(!!v.can_request_purchase))}${opt('true', tr('يرفع طلبات الشراء'), String(!!v.can_request_purchase))}</select>`)}
    ${field('تسجيل الحضور', `<select name="att_exempt">${opt('false', 'مطلوب', String(!!v.att_exempt))}${opt('true', 'معفى', String(!!v.att_exempt))}</select>`)}
    ${field('الديانة — لدوام رمضان (م98)', `<select name="is_muslim">${opt('true', 'مسلم — يطبق عليه دوام رمضان', String(v.is_muslim !== false))}${opt('false', 'غير مسلم — دوامه العادي في رمضان', String(v.is_muslim !== false))}</select>`)}
    ${field('العمل الإضافي فوق 720 ساعة (موافقة العامل الكتابية)', `<select name="ot_consent_year">${opt('', tr('غير مسموح'), String(v.ot_consent_year || ''))}${[new Date().getFullYear(), new Date().getFullYear() + 1].map(y => opt(String(y), tr('موافق لسنة') + ' ' + y, String(v.ot_consent_year || ''))).join('')}</select>`)}
    <div class="wide muted small" style="margin:4px 0 -4px"><b>${esc(tr('تذكرة السفر حسب العقد'))}</b></div>
    ${field('استحقاق التذكرة', `<select name="ticket_every">${opt('', tr('لا ينص العقد على تذكرة'), String(v.ticket_every || ''))}${opt('12', tr('كل سنة'), String(v.ticket_every || ''))}${opt('24', tr('كل سنتين'), String(v.ticket_every || ''))}</select>`)}
    ${field('عدد المسافرين (الموظف وعائلته)', inp('ticket_persons', v.ticket_persons || 1, 'type="number" min="1" max="10"'))}${field('درجة السفر', `<select name="ticket_class">${opt('economy', tr('سياحية'), v.ticket_class || 'economy')}${opt('business', tr('أعمال'), v.ticket_class || 'economy')}</select>`)}
    ${field('الوجهة', inp('ticket_dest', v.ticket_dest))}${field('الوجهة بالإنجليزية', inp('ticket_dest_en', v.ticket_dest_en, 'dir="ltr"'))}${field('قيمة التذكرة للشخص ذهاباً وعودة (تقديرية)', inp('ticket_amount', v.ticket_amount, 'type="number" step="0.01" min="0"'))}
    ${field('الراتب الأساسي', inp('basic', v.basic, 'type="number" step="0.01" min="0" required' + (e ? ' readonly' : '')))}${field('بدل السكن', inp('housing', v.housing, 'type="number" step="0.01" min="0"' + (e ? ' readonly' : '')))}${field('بدل النقل', inp('transport', v.transport, 'type="number" step="0.01" min="0"' + (e ? ' readonly' : '')))}
    ${e ? `<p class="wide muted small" style="margin:0">${esc('لتعديل الأجر أو إضافة بدلات أخرى: صفحة «المستندات والعقود والخطابات» للموظف ← الأجر والبدلات، ليُحفظ السبب وتاريخ السريان في سجل الرواتب.')}</p>` : ''}
    ${field('الآيبان', inp('iban', v.iban, 'dir="ltr" placeholder="SA…" maxlength="24"') + '<div class="muted small" id="ibk"></div>')}${field('الجوال', inp('phone', v.phone, 'dir="ltr"'))}${field('البريد', inp('email', v.email, 'dir="ltr" type="email"'))}
    ${sec('البيانات الشخصية')}
    ${field('تاريخ الميلاد', `<input type="date" name="birth_date" value="${esc(v.birth_date || '')}">`)}
    ${field('الحالة الاجتماعية', `<select name="marital_status"><option value="">—</option>${Object.entries(MARITAL).map(([k, t]) => opt(k, t, v.marital_status)).join('')}</select>`)}
    ${field('عدد المرافقين', inp('dependents', v.dependents, 'type="number" min="0" max="30"'))}
    ${field('المؤهل الدراسي', `<select name="education"><option value="">—</option>${Object.entries(EDU).map(([k, t]) => opt(k, t, v.education)).join('')}</select>`)}${field('التخصص', inp('specialization', v.specialization))}
    ${field('المهنة الرسمية (قوى/الإقامة)', inp('official_profession', v.official_profession))}
    ${field('العنوان المختصر', inp('short_address', v.short_address, 'dir="ltr" maxlength="9" placeholder="RRRD2929" style="text-transform:uppercase"'))}${field('العنوان الوطني', inp('national_address', v.national_address), 'wide')}
    ${sec('جهة اتصال الطوارئ')}
    ${field('الاسم', inp('emergency_name', v.emergency_name))}${field('صلة القرابة', inp('emergency_relation', v.emergency_relation))}${field('الجوال', inp('emergency_phone', v.emergency_phone, 'dir="ltr"'))}
    ${ccs.length || sites.length ? sec('التوزيع') : ''}
    ${ccs.length ? field('مركز التكلفة — تُحمَّل عليه رواتبه', `<select name="cost_center_id"><option value="">—</option>${ccs.filter(c => c.active !== false || c.id === v.cost_center_id).map(c => opt(c.id, c.code + ' — ' + ((LANG === 'en' && c.name_en) || c.name), v.cost_center_id)).join('')}</select>`) : ''}
    ${sites.length ? field('موقع العمل — يسجّل حضوره فيه فقط', `<select name="work_site_id"><option value="">${esc(tr('أي موقع من مواقع المنشأة'))}</option>${sites.map(w => opt(w.id, (LANG === 'en' && w.name_en) || w.name, v.work_site_id)).join('')}</select>`) : ''}
    ${sec('رصيد الإجازة السنوية الافتتاحي')}
    <p class="wide muted small" style="margin:0">${esc(tr('للموظفين المنقولين من نظام سابق: رصيده من الإجازة السنوية كما في نهاية التاريخ المحدد، وما يُطلب بعده يُخصم منه. اتركه فارغاً إذا كانت كل إجازاته منذ المباشرة مسجّلة في النظام.'))}</p>
    ${field('الرصيد (يوم)', inp('leave_open_days', v.leave_open_days, 'type="number" step="0.5" min="0" max="999"'))}${field('كما في تاريخ', `<input type="date" name="leave_open_date" value="${esc(v.leave_open_date || '')}">`)}
    ${e ? field('تاريخ انتهاء الخدمة', `<input type="date" name="end_date" value="${esc(v.end_date || '')}">`) + field('سبب الانتهاء', inp('end_reason', v.end_reason)) : ''}
    ${linkMe ? `<div class="wide note">سيُربط هذا السجل بحسابك.</div>` : ''}
    ${e && !linkMe ? (() => { const l = (cache.logins || {})[e.id]; return `<div class="wide card" style="margin:0;padding:12px"><b>حساب الدخول</b> <span class="muted small">${!l ? 'لا يملك حساباً بعد' : l.by_number ? 'يدخل بالرقم الوظيفي ' + esc(e.emp_no) : 'يدخل ببريده الإلكتروني'}</span>
      <div class="row" style="margin-top:8px"><a class="btn sm" href="#/docs/${e.id}" onclick="document.getElementById('dlg').close()">المستندات والعقود والخطابات</a>${!S.emp && has('owner', 'admin') && !l ? '<button type="button" class="btn pri sm" id="linkself">هذا أنا — اربط هذا السجل بحسابي</button>' : ''}${!l ? '<button type="button" class="btn sm" id="mklogin">إنشاء دخول للموظف</button>' : l.by_number ? '<button type="button" class="btn sm" id="rspw">إعادة تعيين كلمة المرور</button>' : ''}</div>${!S.emp && has('owner', 'admin') && !l ? `<p class="muted small" style="margin:6px 0 0">${esc('إن كان هذا سجلك أنت، اربطه بحسابك لتظهر لك خدمات الطلبات والإجازات وقسائم راتبك.')}</p>` : ''}</div>`; })() : ''}</div>`;
  const dlg = modal(e ? 'تعديل بيانات موظف' : 'إضافة موظف', body, {
    wide: true, onOk: async f => {
      if (!f.emp_no) throw new Error('أدخل الرقم الوظيفي'); if (f.full_name.length < 3) throw new Error('أدخل الاسم الكامل');
      if (f.national_id && !/^[12]\d{9}$/.test(f.national_id)) throw new Error('رقم الهوية/الإقامة 10 أرقام يبدأ بـ 1 أو 2');
      if (f.iban && !/^SA\d{22}$/.test(f.iban.replace(/\s/g, '').toUpperCase())) throw new Error('الآيبان يبدأ بـ SA ويليه 22 رقماً');
      if (!(+f.basic >= 0) || f.basic === '') throw new Error('أدخل الراتب الأساسي');
      if (f.probation_end && (new Date(f.probation_end) - new Date(f.hire_date)) / 864e5 > 179) throw new Error('فترة التجربة لا تزيد على 180 يوماً — م53');
      if (f.birth_date && new Date(f.birth_date) > new Date(new Date(f.hire_date).setFullYear(new Date(f.hire_date).getFullYear() - 15))) throw new Error('لا يجوز تشغيل من لم يتم 15 سنة — م162');
      const sa = (f.short_address || '').replace(/\s/g, '').toUpperCase(); if (sa && !/^[A-Z]{4}\d{4}$/.test(sa)) throw new Error('العنوان المختصر 4 حروف و4 أرقام مثل RRRD2929');
      if (f.leave_open_date && f.leave_open_days === '') throw new Error('أدخل رصيد الإجازة الافتتاحي');
      if (f.leave_open_date && f.leave_open_date < f.hire_date) throw new Error('تاريخ الرصيد الافتتاحي قبل تاريخ المباشرة');
      const row = { emp_no: f.emp_no, full_name: f.full_name, national_id: blank(f.national_id), nationality: blank(f.nationality), is_saudi: f.nationality ? f.nationality === 'SA' : (e ? !!e.is_saudi : false), gender: f.gender,
        birth_date: blank(f.birth_date), marital_status: blank(f.marital_status), dependents: f.dependents === '' ? null : +f.dependents, education: blank(f.education), specialization: blank((f.specialization || '').trim()),
        official_profession: blank((f.official_profession || '').trim()), short_address: blank(sa), national_address: blank((f.national_address || '').trim()),
        emergency_name: blank((f.emergency_name || '').trim()), emergency_relation: blank((f.emergency_relation || '').trim()), emergency_phone: blank((f.emergency_phone || '').replace(/[\s-]/g, '')),
        leave_open_days: f.leave_open_days === '' ? null : +f.leave_open_days, leave_open_date: f.leave_open_days === '' ? null : blank(f.leave_open_date), job_title: blank(f.job_title), full_name_en: blank((f.full_name_en || '').trim()), job_title_en: blank((f.job_title_en || '').trim()),
        department_id: blank(f.department_id), manager_id: blank(f.manager_id), hire_date: f.hire_date, probation_end: blank(f.probation_end), shift_id: blank(f.shift_id), att_exempt: f.att_exempt === 'true', is_muslim: f.is_muslim !== 'false', ot_consent_year: f.ot_consent_year ? +f.ot_consent_year : null,
        can_request_purchase: f.can_request_purchase === 'true', ticket_every: f.ticket_every ? +f.ticket_every : null, ticket_persons: Math.max(1, +f.ticket_persons || 1), ticket_class: f.ticket_class || 'economy', ticket_dest: blank((f.ticket_dest || '').trim()), ticket_dest_en: blank((f.ticket_dest_en || '').trim()), ticket_amount: f.ticket_amount === '' ? null : +f.ticket_amount, gosi_new: f.gosi_new === '' ? null : f.gosi_new === 'true',
        ...(grades.length ? { grade_id: blank(f.grade_id) } : {}), ...(ccs.length ? { cost_center_id: blank(f.cost_center_id) } : {}), ...(sites.length ? { work_site_id: blank(f.work_site_id) } : {}),
        basic: +f.basic, housing: +f.housing || 0, transport: +f.transport || 0, iban: f.iban ? f.iban.replace(/\s/g, '').toUpperCase() : null, phone: blank(f.phone), email: blank(f.email) };
      if (e) { Object.assign(row, { end_date: blank(f.end_date), end_reason: blank(f.end_reason) }); await db.upd('employees', { id: 'eq.' + e.id }, row); }
      else {
        const [x] = await db.ins('employees', Object.assign(row, { company_id: S.cid }));
        if (linkMe) { await db.upd('members', { company_id: 'eq.' + S.cid, user_id: 'eq.' + S.session.user.id }, { employee_id: x.id }); await loadContext(); shell(); }
      }
      cache.emps = null; toast('تم الحفظ'); route();
    }
  });
  const ibf = $('#mform', dlg).iban, ibu = () => { const i = (ibf.value || '').replace(/\s/g, '').toUpperCase(), b = /^SA\d{4}/.test(i) && SA_BANKS[i.slice(4, 6)]; $('#ibk', dlg).textContent = b ? tr(b[1]) : ''; };
  ibf.addEventListener('input', ibu); ibu();
  // probation end is computed from hire date + chosen duration (still editable by hand)
  const _hd = $('#mform', dlg).hire_date, _pd = $('#mform', dlg).prob_days, _pe = $('#mform', dlg).probation_end;
  const _recalc = () => { const d = +_pd.value; if (d && _hd.value) _pe.value = addDays(_hd.value, d); };
  _pd.addEventListener('change', _recalc);
  _hd.addEventListener('change', () => { if (+_pd.value) _recalc(); });
  if (e && $('#mklogin', dlg)) $('#mklogin', dlg).onclick = () => createStaffLogin(e);
  if (e && $('#rspw', dlg)) $('#rspw', dlg).onclick = () => resetStaffPassword(e);
  if (e && $('#linkself', dlg)) $('#linkself', dlg).onclick = async () => {
    if (!await confirmBox('ربط السجل بحسابك', 'سيُربط سجل الموظف «' + e.full_name + '» بحسابك الحالي، فتظهر لك خدمات الطلبات والإجازات وقسائم راتبك. تأكد أن هذا سجلك أنت.', 'ربط')) return;
    try { await db.upd('members', { company_id: 'eq.' + S.cid, user_id: 'eq.' + S.session.user.id }, { employee_id: e.id }); await loadContext(); dlg.close(); shell(); toast('تم ربط حسابك بسجلك'); route(); }
    catch (er) { toast(er.message); }
  };
}

/* ===== staff logins by employee number ===== */
// temporary password HR hands over; the employee must replace it at first sign-in
function tempPassword() {
  const A = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789', r = crypto.getRandomValues(new Uint32Array(8));
  let p = ''; for (const x of r) p += A[x % A.length]; return p;
}
function createStaffLogin(e) {
  if (!/^[A-Za-z0-9_-]{1,20}$/.test(e.emp_no)) return toast('الرقم الوظيفي يجب أن يكون أرقاماً أو حروفاً إنجليزية ليُستخدم في الدخول');
  const roles = INVITABLE();
  modal('إنشاء دخول — ' + e.full_name, `<p>سيدخل الموظف برمز المنشأة <b class="num">${esc(S.company.code)}</b> ثم <b>رقمه الوظيفي ${esc(e.emp_no)}</b> وكلمة مرور مؤقتة تظهر لك الآن، ويُطلب منه تغييرها عند أول دخول.</p>
    ${field('الصلاحية', `<select name="role">${roles.map(r => opt(r, ROLES[r], 'employee')).join('')}</select>`)}
    <p class="muted small">${esc(tr('موظف مبيعات أو مشتريات؟ اختر «محاسب»، ثم حدّد ما يراه (المبيعات، المشتريات…) من الإعدادات ← صلاحيات المحاسب وأمين المستودع.'))}</p>`, {
    ok: 'إنشاء الدخول', onOk: async f => {
      const pw = tempPassword();
      const res = await authApi.createStaff(staffEmail(S.company.code, e.emp_no), pw);
      await db.rpc('link_staff_login', { p_company: S.cid, p_employee: e.id, p_role: f.role });
      if (res.existed) await db.rpc('reset_staff_password', { p_company: S.cid, p_employee: e.id, p_password: pw });
      cache.logins = null; route(); setTimeout(() => credentialsBox(e, pw, !res.confirmed && !res.existed), 60);
    }
  });
}
function resetStaffPassword(e) {
  modal('إعادة تعيين كلمة المرور — ' + e.full_name, '<p>تتوقف كلمة المرور الحالية وتظهر لك كلمة مؤقتة جديدة، ويُطلب من الموظف تغييرها عند الدخول.</p>', {
    ok: 'إعادة التعيين', onOk: async () => { const pw = tempPassword(); await db.rpc('reset_staff_password', { p_company: S.cid, p_employee: e.id, p_password: pw }); route(); setTimeout(() => credentialsBox(e, pw), 60); }
  });
}
/* ===== WhatsApp: opens the chat with the message typed; the user presses send (nothing is sent automatically) ===== */
function waPhone(p) { let d = String(p || '').replace(/\D/g, ''); if (/^05\d{8}$/.test(d)) d = '966' + d.slice(1); else if (/^5\d{8}$/.test(d)) d = '966' + d; else if (/^00966/.test(d)) d = d.slice(2); return /^9665\d{8}$/.test(d) ? d : ''; }
const waUrl = (phone, text) => 'https://wa.me/' + waPhone(phone) + '?text=' + encodeURIComponent(text);
const waBtn = (phone, text, label = 'إرسال واتساب', cls = 'btn wa') => `<a class="${cls}" target="_blank" rel="noopener" href="${esc(waUrl(phone, text))}">${esc(label)}</a>`;
function credentialsBox(e, pw, warnConfirm) {
  const link = location.origin + location.pathname + '?c=' + S.company.code;
  const msg = 'بيانات دخولك لنظام وعد (' + S.company.name + '):\nالرابط: ' + link + '\nرمز المنشأة: ' + S.company.code + '\nالرقم الوظيفي: ' + e.emp_no + '\nكلمة المرور المؤقتة: ' + pw + '\nسيُطلب منك تغييرها عند أول دخول.';
  const row = (t, v) => `<tr><td class="muted">${t}</td><td class="num" style="font-weight:700;font-size:17px">${esc(v)}</td></tr>`;
  const d = modal('بيانات دخول ' + e.full_name, `${warnConfirm ? '<div class="err">خيار «Confirm email» مفعّل في Supabase، فلن يستطيع الموظف الدخول حتى يُطفأ.</div>' : ''}
    <div class="tw"><table><tbody>${row('رمز المنشأة', S.company.code)}${row('الرقم الوظيفي', e.emp_no)}${row('كلمة المرور المؤقتة', pw)}</tbody></table></div>
    <p class="muted small">لن تظهر كلمة المرور مجدداً. أعطها للموظف الآن، ويمكنك إعادة تعيينها لاحقاً.</p>
    <div class="row" style="justify-content:center">${waBtn(e.phone, tr(msg), waPhone(e.phone) ? 'إرسال واتساب إلى ' + e.phone : 'إرسال واتساب')}<button type="button" class="btn pri" id="cpm">نسخ الرسالة</button>${navigator.share ? '<button type="button" class="btn" id="shm">مشاركة</button>' : ''}</div>
    ${waPhone(e.phone) ? '' : '<p class="muted small" style="text-align:center">لا يوجد جوال صحيح في سجل الموظف — سيفتح واتساب لتختار المحادثة بنفسك.</p>'}`);
  $('#cpm', d).onclick = async ev => { try { await navigator.clipboard.writeText(tr(msg)); ev.target.textContent = 'نُسخت ✓'; } catch (er) { toast('تعذر النسخ — انسخ البيانات من الجدول'); } };
  if ($('#shm', d)) $('#shm', d).onclick = () => navigator.share({ text: tr(msg) }).catch(() => {});
}


/* ===== payroll ===== */
VIEWS['#/payroll'] = async (page, arg) => {
  if (arg) return payrollRun(page, arg);
  const runs = await db.get('payroll_runs', { company_id: 'eq.' + S.cid, order: 'year.desc,month.desc' });
  const d = new Date();
  const cut = S.company && S.company.payroll_cutoff;
  page.innerHTML = `<div class="head"><div><h1>مسير الرواتب</h1><div class="muted small">${cut ? esc(tr('يوم الإقفال')) + ' <span class="num">' + cut + '</span> — ' + esc(tr('الحضور والغياب والإضافي من يوم')) + ' <span class="num">' + cut + '</span> ' + esc(tr('في الشهر السابق إلى يوم')) + ' <span class="num">' + (cut - 1) + '</span>' : esc(tr('بدون يوم إقفال — الحضور والغياب حسب الشهر الميلادي'))}</div></div>
    <div class="row">${isHR() ? '<button class="btn" id="cut">يوم الإقفال</button><button class="btn pri" id="np">إعداد مسير شهر</button>' : ''}</div></div>
    ${tbl([{ t: 'الشهر', h: r => `${r.month}/${r.year}` }, { t: 'تاريخ الصرف', h: r => fdate(r.pay_date) }, { t: 'الحالة', h: r => badge(r.status) }], runs, { empty: 'لا توجد مسيرات', onRow: true })}`;
  bindRows(page, runs, r => location.hash = '#/payroll/' + r.id);
  if ($('#cut', page)) $('#cut', page).onclick = () => modal('يوم إقفال الرواتب', `${field('يوم الإقفال', `<select name="c"><option value="">${esc(tr('بدون إقفال (الشهر الميلادي)'))}</option>${[...Array(27)].map((_, i) => opt(i + 2, i + 2, String(cut || ''))).join('')}</select>`)}
    <p class="muted small">${esc(tr('مثال يوم 21: مسير أكتوبر يحسب الحضور والغياب والإضافي والإجازات من 21 سبتمبر إلى 20 أكتوبر. من ينضم يوم 21 أو بعده لا يدخل مسير أكتوبر، وتُصرف له أيام أكتوبر في مسير نوفمبر كمستحقات الشهر السابق مع راتب نوفمبر كاملاً. المغادر يُحسب له إلى آخر يوم عمل.'))}</p>
    <p class="muted small">${esc(tr('تنبيه: المادة 90 تلزم بصرف الأجر الشهري مرة في الشهر على الأقل، فالمنضم بعد الإقفال يتأخر أول راتب له.'))}</p>`, {
    ok: 'حفظ', onOk: async f => { await db.rpc('payroll_cutoff_set', { p_company: S.cid, p_day: f.c ? +f.c : null }); await loadContext(); toast('تم الحفظ'); route(); } });
  if ($('#np', page)) $('#np', page).onclick = () => modal('إعداد مسير', `<div class="fg">${field('السنة', inp('y', d.getFullYear(), 'type="number"'))}${field('الشهر', `<select name="m">${[...Array(12)].map((_, i) => opt(i + 1, i + 1, d.getMonth() + 1)).join('')}</select>`)}${field('تاريخ الصرف', `<input type="date" name="pd" value="${today()}">`)}</div><p class="muted small">يحتسب النظام التأمينات والغياب وأقساط السلف تلقائياً. يمكنك إعادة الإعداد ما دام المسير مسودة.</p>`, {
    ok: 'إعداد', onOk: async f => { const id = await db.rpc('payroll_prepare', { p_company: S.cid, p_year: +f.y, p_month: +f.m, p_pay_date: blank(f.pd) }); location.hash = '#/payroll/' + id; }
  });
};
async function payrollRun(page, id) {
  const [[run], lines, em] = await Promise.all([db.get('payroll_runs', { id: 'eq.' + id }), db.get('payroll_lines', { run_id: 'eq.' + id }), employeesMap(true)]);
  if (!run) throw new Error('المسير غير موجود');
  lines.sort((a, b) => String((em[a.employee_id] || {}).emp_no).localeCompare(String((em[b.employee_id] || {}).emp_no)));
  const sum = k => lines.reduce((a, l) => a + n0(l[k]), 0);
  const draft = run.status === 'draft', hasArr = lines.some(l => n0(l.arrears));
  page.innerHTML = `<div class="head"><div><a href="#/payroll" class="small">← المسيرات</a><h1>مسير ${run.month}/${run.year} ${badge(run.status)}</h1><div class="muted">${lines.length} موظف · الصافي <b class="num">${money(sum('net'))}</b></div>${run.att_from ? `<div class="muted small">${esc(tr('فترة الحضور والغياب والإضافي'))}: <span class="num">${fdate(run.att_from)} – ${fdate(run.att_to)}</span></div>` : ''}</div>
    <div class="row">${draft && isHR() ? '<button class="btn" id="re">إعادة الاحتساب</button>' : ''}${draft && has('owner', 'finance') ? '<button class="btn pri" id="ap">اعتماد وترحيل القيد</button>' : ''}${run.status === 'approved' && has('owner', 'finance') ? '<button class="btn pri" id="pd">تسجيل الصرف</button>' : ''}<button class="btn" id="gos">تقرير التأمينات</button>${run.status !== 'draft' ? '<button class="btn" id="wps">ملف حماية الأجور</button>' : ''}</div></div>
    ${draft && !has('owner', 'finance') ? '<div class="note">بعد المراجعة يعتمده المدير العام أو المدير المالي.</div>' : ''}
    ${tbl([{ t: 'الموظف', h: l => esc((em[l.employee_id] || {}).full_name || '') + (l.paid_days != null && l.paid_days < 30 ? ` <span class="badge" title="${esc(tr('جزء من الشهر'))}">${l.paid_days}/30</span>` : '') }, { t: 'الإجمالي', r: 1, h: l => money(l.gross) }, ...(hasArr ? [{ t: 'مستحقات الشهر السابق', r: 1, h: l => n0(l.arrears) ? money(l.arrears) + ` <span class="muted small num">(${l.arrears_days})</span>` : '—' }] : []), { t: 'إضافي', r: 1, h: l => money(l.overtime) }, { t: 'مكافأة', r: 1, h: l => money(l.bonus) },
      { t: 'التأمينات', r: 1, h: l => money(l.gosi) }, { t: 'بدون أجر', r: 1, h: l => money(l.absence) }, { t: 'غياب وتأخير', r: 1, h: l => money(n0(l.att_absence) + n0(l.late_deduction)) }, { t: 'مرضية', r: 1, h: l => money(l.sick_deduction) }, { t: 'غرامات وجزاءات', r: 1, h: l => money(n0(l.deductions) + n0(l.penalty_fine)) }, { t: 'تلفيات', r: 1, h: l => money(l.damages) }, { t: 'سلفة', r: 1, h: l => money(l.advance) }, { t: 'الصافي', r: 1, h: l => '<b>' + money(l.net) + '</b>' }],
      lines, { onRow: true, foot: `<td>الإجمالي</td>${['gross', ...(hasArr ? ['arrears'] : []), 'overtime', 'bonus', 'gosi', 'absence', 'att', 'sick_deduction', 'fines', 'damages', 'advance', 'net'].map(k => `<td class="r num">${money(k === 'att' ? sum('att_absence') + sum('late_deduction') : k === 'fines' ? sum('deductions') + sum('penalty_fine') : sum(k))}</td>`).join('')}` })}
    <p class="muted small">المرضية: أول 30 يوماً بأجر كامل، ثم 60 يوماً بثلاثة أرباع الأجر، ثم 30 يوماً بدون أجر خلال سنة الإجازة المرضية (م117). قسط السلفة لا يتجاوز 10% من الأجر (م92)، ومجموع الحسميات لا يتجاوز نصف الأجر (م93).</p>
    <p class="muted small">حصة المنشأة في التأمينات: <span class="num">${money(sum('employer_gosi'))}</span></p>`;
  bindRows(page, lines, l => {
    if (!(draft && isHR())) return payslip(Object.assign({ _r: run }, l), em[l.employee_id]);
    const cap5 = r2(n0(l.gross) / 30 * 5);
    modal('تعديل بند — ' + (em[l.employee_id] || {}).full_name, `<div class="fg">${field('ساعات العمل الإضافي', inp('ot', l.overtime_hours, 'type="number" step="0.5" min="0"'))}${field('مكافأة', inp('b', l.bonus, 'type="number" step="0.01" min="0"'))}${field('غرامات جزائية (حد ' + money(cap5) + ')', inp('d', l.deductions, 'type="number" step="0.01" min="0"'))}${field('اقتطاع تلفيات (حد ' + money(cap5) + ')', inp('dm', l.damages, 'type="number" step="0.01" min="0"'))}</div>
      <p class="muted small">أجر الساعة الإضافية = أجر الساعة + 50% من أجر الساعة الأساسي (م107). الغرامة لا تتجاوز أجر 5 أيام في الشهر (م70)، واقتطاع التلفيات كذلك (م91)، ولا يوقَّع جزاء إلا بعد إبلاغ الموظف كتابة والتحقيق معه (م71).</p>`,
      { onOk: async f => { await db.rpc('payroll_set_line', { p_run: id, p_emp: l.employee_id, p_ot_hours: +f.ot || 0, p_bonus: +f.b || 0, p_fines: +f.d || 0, p_damages: +f.dm || 0 }); route(); } });
  });
  if ($('#re', page)) $('#re', page).onclick = () => busy($('#re', page), async () => { await db.rpc('payroll_prepare', { p_company: S.cid, p_year: run.year, p_month: run.month, p_pay_date: run.pay_date }); route(); });
  if ($('#ap', page)) $('#ap', page).onclick = async () => { if (!await confirmBox('اعتماد المسير', 'بعد الاعتماد يُرحّل قيد الاستحقاق ولا يمكن تعديل المسير.', 'اعتماد')) return; try { await db.rpc('payroll_approve', { p_run: id }); toast('اعتُمد المسير'); route(); } catch (e) { toast(e.message); } };
  if ($('#pd', page)) $('#pd', page).onclick = () => modal('تسجيل صرف الرواتب', field('من حساب', `<select name="acc">${opt('1120', 'البنك')}${opt('1110', 'الصندوق')}</select>`), { ok: 'تسجيل', onOk: async f => { await db.rpc('payroll_mark_paid', { p_run: id, p_account: f.acc }); toast('سُجل الصرف'); route(); } });
  if ($('#wps', page)) $('#wps', page).onclick = () => wpsFile(run, lines, em);
  $('#gos', page).onclick = () => gosiReport(run, em).catch(er => toast(er.message));
}
// Saudi IBAN: SA + 22 digits with a valid ISO 13616 check (mod 97); digits 5–6 are the bank (SARIE codes)
const SA_BANKS = { '05': ['INMA', 'مصرف الإنماء'], '10': ['NCBK', 'البنك الأهلي السعودي'], '15': ['ALBI', 'بنك البلاد'], '20': ['RIBL', 'بنك الرياض'], '30': ['ARNB', 'البنك العربي الوطني'],
  '40': ['SAMB', 'البنك الأهلي السعودي (سامبا سابقاً)'], '45': ['SABB', 'البنك السعودي الأول'], '50': ['AAAL', 'البنك السعودي الأول (الأول سابقاً)'], '55': ['BSFR', 'البنك السعودي الفرنسي'],
  '60': ['BJAZ', 'بنك الجزيرة'], '65': ['SIBC', 'البنك السعودي للاستثمار'], '80': ['RJHI', 'مصرف الراجحي'] };
function ibanOk(v) { const s = String(v || '').replace(/\s/g, '').toUpperCase(); if (!/^SA\d{22}$/.test(s)) return false;
  const r = (s.slice(4) + s.slice(0, 4)).replace(/[A-Z]/g, c => c.charCodeAt(0) - 55); let m = 0; for (const ch of r) m = (m * 10 + +ch) % 97; return m === 1; }
const lineOther = l => r2(n0(l.transport) + n0(l.allowances) + n0(l.arrears) + n0(l.overtime) + n0(l.bonus));
const lineDed = l => r2(n0(l.gosi) + n0(l.absence) + n0(l.att_absence) + n0(l.late_deduction) + n0(l.sick_deduction) + n0(l.deductions) + n0(l.penalty_fine) + n0(l.damages) + n0(l.advance));
function wpsFile(run, lines, em) {
  const en = LANG === 'en';
  const rows = lines.map(l => { const e = em[l.employee_id] || {}, iban = String(e.iban || '').replace(/\s/g, '').toUpperCase(), bank = SA_BANKS[iban.slice(4, 6)];
    const probs = [];
    if (!/^[12]\d{9}$/.test(e.national_id || '')) probs.push(tr('رقم الهوية/الإقامة مفقود أو غير صحيح'));
    if (!iban) probs.push(tr('لا يوجد آيبان')); else if (!ibanOk(iban)) probs.push(tr('الآيبان غير صحيح (رقم التحقق لا يطابق)')); else if (!bank) probs.push(tr('البنك غير معروف من الآيبان — أكمل رمزه يدوياً'));
    if (n0(l.net) < 0) probs.push(tr('الصافي سالب'));
    if (Math.abs(r2(n0(l.basic) + n0(l.housing) + lineOther(l) - lineDed(l)) - r2(l.net)) > 0.01) probs.push(tr('الصافي لا يساوي الأساسي + السكن + الأخرى − الاستقطاعات'));
    return { l, e, iban, bank, probs }; });
  const bad = rows.filter(x => x.probs.length), total = rows.reduce((a, x) => a + n0(x.l.net), 0);
  const head = en ? ['National ID / Iqama', 'Employee name', 'Bank code', 'IBAN', 'Basic salary', 'Housing allowance', 'Other earnings', 'Deductions', 'Net salary']
    : ['رقم الهوية / الإقامة', 'اسم الموظف', 'رمز البنك', 'رقم الآيبان', 'الراتب الأساسي', 'بدل السكن', 'الدخل الآخر', 'الاستقطاعات', 'صافي الراتب'];
  const data = rows.map(({ l, e, iban, bank }) => [e.national_id || '', (en && e.full_name_en) || e.full_name || '', bank ? bank[0] : '', iban, r2(l.basic), r2(l.housing), lineOther(l), lineDed(l), r2(l.net)]);
  const ym = run.year + '-' + String(run.month).padStart(2, '0');
  const xurl = URL.createObjectURL(templateXlsx([head, ...data]));
  const csv = '﻿' + [head, ...data].map(r => r.map(v => typeof v === 'number' ? v.toFixed(2) : '"' + String(v).replace(/"/g, '""') + '"').join(',')).join('\r\n');
  const curl = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
  const d = modal('ملف حماية الأجور (مدد)', `<p class="small">${esc(tr('الحقول المعتمدة في نظام حماية الأجور: الهوية، الاسم، البنك، الآيبان، الأساسي، السكن، الدخل الآخر، الاستقطاعات، الصافي.'))} <span class="muted">${esc(tr('الدخل الآخر = النقل والبدلات والمستحقات السابقة والإضافي والمكافآت. الاستقطاعات تشمل حصة الموظف في التأمينات.'))}</span></p>
    <div class="row" style="gap:16px;margin:8px 0"><span>${esc(tr('عدد الموظفين'))}: <b class="num">${rows.length}</b></span><span>${esc(tr('إجمالي الصافي'))}: <b class="num">${money(total)}</b></span></div>
    ${bad.length ? `<div class="err">${esc(tr('يحتاج تصحيحاً قبل الرفع'))}: <span class="num">${bad.length}</span></div><div class="tw" style="max-height:220px;overflow:auto"><table><tbody>${bad.map(x => `<tr><td>${esc(x.e.full_name || '')} <span class="muted num">${esc(x.e.emp_no || '')}</span></td><td class="small">${x.probs.map(esc).join('<br>')}</td></tr>`).join('')}</tbody></table></div>`
      : `<div class="note">${esc(tr('كل السطور سليمة: الهوية والآيبان ورقم التحقق ومطابقة الصافي.'))}</div>`}
    <div class="row" style="margin-top:10px"><a class="btn pri" id="wx" download="mudad-wps-${ym}.xlsx" href="${xurl}">${esc(tr('تنزيل Excel'))}</a><a class="btn" download="mudad-wps-${ym}.csv" href="${curl}">${esc(tr('تنزيل CSV'))}</a></div>
    <p class="muted small">${esc(tr('ترتيب الأعمدة في قالب مدد قد يختلف حسب البنك وإصدار المنصة؛ قارن مع القالب المنزّل من حسابك في مدد قبل الرفع.'))}</p>`);
  return d;
}
async function gosiReport(run, em) {
  const rows = await db.rpc('gosi_report', { p_run: run.id });
  const st = { new: ['مشترك جديد — سجّله في التأمينات', 'info'], left: ['انتهت خدمته — استبعده من التأمينات', 'wait'] };
  const chg = x => x.prev_base != null && r2(x.prev_base) !== r2(x.base);
  const sum = k => rows.reduce((a, x) => a + n0(x[k]), 0), todo = rows.filter(x => x.status || chg(x));
  const body = `<div id="gsr"><p class="small muted">${esc(tr('الأجر الخاضع للاشتراك = الأساسي + السكن (حد أدنى 1,500 وأعلى 45,000). غير السعودي: 2% أخطار مهنية على المنشأة فقط.'))} ${esc(tr('الاشتراك بعدد أيام العمل في الشهر (الشهري ÷ 30 × الأيام) للمنضم والمغادر.'))}</p>
    <div class="grid" style="margin:8px 0"><div class="card kpi"><div class="muted small">${esc(tr('حصة الموظفين'))}</div><div class="v num">${money(sum('employee_share'))}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('حصة المنشأة'))}</div><div class="v num">${money(sum('employer_share'))}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('الإجمالي المستحق للتأمينات'))}</div><div class="v num">${money(sum('employee_share') + sum('employer_share'))}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('يحتاج تحديثاً في التأمينات'))}</div><div class="v num ${todo.length ? 'bad' : ''}">${todo.length}</div></div></div>
    ${tbl([{ t: 'الموظف', h: x => esc((em[x.employee_id] || {}).full_name || '') + ` <span class="muted num small">${esc((em[x.employee_id] || {}).national_id || '')}</span>` },
      { t: 'الجنسية', h: x => x.is_saudi ? esc(tr('سعودي')) + (x.new_regime ? ' <span class="badge">' + esc(tr('النظام الجديد')) + '</span>' : '') : esc(tr('غير سعودي')) },
      { t: 'الأجر الخاضع', r: 1, h: x => money(x.base) + (chg(x) ? ` <span class="small muted">(${esc(tr('كان'))} ${money(x.prev_base)})</span>` : '') },
      { t: 'حصة الموظف', r: 1, h: x => money(x.employee_share) }, { t: 'حصة المنشأة', r: 1, h: x => money(x.employer_share) },
      { t: 'الإجراء', h: x => x.status ? `<span class="badge ${st[x.status][1]}">${esc(tr(st[x.status][0]))}</span>` : chg(x) ? `<span class="badge bad">${esc(tr('تغيّر الأجر — حدّثه في التأمينات'))}</span>` : '' }], rows, { empty: 'لا توجد بيانات' })}</div>
    <div class="row" style="margin-top:10px"><button type="button" class="btn" id="gsp">طباعة</button></div>`;
  const d = modal(tr('تقرير التأمينات الاجتماعية') + ' ' + run.month + '/' + run.year, body, { wide: true });
  $('#gsp', d).onclick = () => printBlock($('#gsr', d), tr('تقرير التأمينات الاجتماعية') + ' ' + run.month + '/' + run.year);
}

/* ===== end of service ===== */
const EOS_REASONS = { resign: 'استقالة العامل (م85)', agree: 'اتفاق الطرفين (م74/1)', expiry: 'انتهاء العقد محدد المدة (م74/2)', employer: 'إنهاء من صاحب العمل لسبب مشروع (م75)', noreason: 'إنهاء دون سبب مشروع (م77)', art81: 'ترك العمل مع بقاء الحقوق (م81)', resignw: 'استقالة العاملة للزواج أو الولادة (م87)', resignfm: 'ترك العمل لقوة قاهرة (م87)', force: 'القوة القاهرة (م74)', ret: 'بلوغ سن التقاعد (م74)', disab: 'العجز الكلي (م74)', death: 'الوفاة (م74)', art80: 'فسخ بدون مكافأة (م80)', probation: 'إنهاء خلال فترة التجربة (م54)' };
VIEWS['#/eos'] = async page => {
  const em = await employeesMap();
  page.innerHTML = `<div class="head"><div><h1>مكافأة نهاية الخدمة والمخالصة</h1><div class="muted">المواد 77 و84 إلى 88 و111 و116 من نظام العمل</div></div></div><div class="card"><form id="ef" class="fg" novalidate>
    ${field('الموظف', `<select name="e"><option value="">— إدخال يدوي —</option>${Object.values(em).map(e => opt(e.id, e.full_name + ' (' + e.emp_no + ')')).join('')}</select>`)}
    <div data-m="manual">${field('الأجر الفعلي الشهري', inp('w', '', 'type="number" step="0.01" min="0"'))}</div><div data-m="manual">${field('تاريخ المباشرة', '<input type="date" name="s">')}</div>
    ${field('آخر يوم عمل', `<input type="date" name="t" value="${today()}">`)}
    ${field('سبب انتهاء العلاقة', `<select name="r">${Object.entries(EOS_REASONS).map(([k, t]) => opt(k, t)).join('')}</select>`)}
    <div data-m="manual">${field('أيام إجازة غير مستخدمة', inp('l', '0', 'type="number" min="0" step="0.5"'))}</div>
    <div data-m="emp">${field('نهاية العقد محدد المدة (إن وجد)', '<input type="date" name="ce">')}</div>
    <div class="wide"><button class="btn pri" id="eb">احسب</button></div></form><div id="er"></div></div>`;
  const f = $('#ef', page);
  const mode = () => { const m = f.e.value ? 'emp' : 'manual'; $$('[data-m]', page).forEach(d => d.hidden = d.dataset.m !== m); };
  f.e.onchange = mode; mode();
  const row = (t, v) => `<tr><td>${t}</td><td class="r num">${v}</td></tr>`;
  f.onsubmit = async ev => { ev.preventDefault(); const v = formData(f);
    try {
      if (v.e) {
        const [x] = await db.rpc('eos_for_employee', { p_emp: v.e, p_end: v.t, p_reason: v.r, p_contract_end: blank(v.ce) });
        const cb = await db.rpc('comp_balance', { p_emp: v.e }).then(x => x[0]).catch(() => null), ch = Math.max(0, n0(cb && cb.balance_hours)), cpay = r2(ch * n0(x.wage) / 30 / 8);
        const tks = await db.rpc('ticket_status', { p_emp: v.e, p_on: v.t }).then(x => x[0]).catch(() => null), tkn = tks ? n0(tks.available) : 0, tpay = tks && tks.amount != null ? r2(tkn * n0(tks.persons) * n0(tks.amount)) : 0;
        const clr = await db.rpc('clearance_status', { p_emp: v.e }).catch(() => []), open = clr.filter(r => !r.ok && r.step !== 'advance'), adv = clr.find(r => r.step === 'advance' && !r.ok);
        const e = em[v.e]; const due = new Date(new Date(v.t).getTime() + (v.r.startsWith('resign') ? 14 : 7) * 864e5).toISOString().slice(0, 10);
        $('#er', page).innerHTML = `<div class="tw" style="margin-top:14px"><table><tbody>${row('الأجر الأخير', money(x.wage))}${row('مدة الخدمة', (+x.years).toFixed(2) + ' سنة (' + x.service_days + ' يوم)')}${+x.excluded_days ? row('مستبعد: إجازات بدون أجر تجاوزت 20 يوماً (م116)', x.excluded_days + ' يوم') : ''}
          ${row('المكافأة الكاملة (م84)', money(x.full_award))}${row('النسبة المستحقة', Math.round(x.fraction * 100) + '%')}${row('المكافأة المستحقة', money(x.award))}
          ${row('رصيد الإجازة السنوية (م111)', (+x.leave_days).toFixed(2) + ' يوم')}${row('بدل الإجازة', money(x.leave_pay))}${+x.compensation ? row('تعويض الإنهاء لغير سبب مشروع (م77)', money(x.compensation)) : ''}${ch ? row(tr('رصيد الإجازة التعويضية') + ' (' + r2(ch) + ' ' + tr('ساعة') + ')', money(cpay)) : ''}${tkn ? row(tr('تذاكر سفر مستحقة لم تُستخدم — حسب العقد') + ' (' + tkn + ' × ' + n0(tks.persons) + ')', tks.amount != null ? money(tpay) : tr('حدد قيمة التذكرة في ملف الموظف')) : ''}
          ${adv ? row(tr('سلفة متبقية تُحسم'), '−' + money(adv.detail)) : ''}</tbody>
          <tfoot><tr><td>الإجمالي</td><td class="r num">${money(n0(x.total) + cpay + tpay - (adv ? n0(adv.detail) : 0))}</td></tr></tfoot></table></div>
          ${open.length ? `<div class="note" style="margin-top:10px">${esc(tr('إخلاء الطرف غير مكتمل'))}: ${open.map(r => esc(tr(CLR_T[r.step]))).join('، ')} — <a href="#/docs/${v.e}">${esc(tr('افتح ملف الموظف'))}</a></div>` : ''}
          <p class="muted small">يُصرف خلال ${v.r.startsWith('resign') ? 'أسبوعين' : 'أسبوع'} من انتهاء العلاقة، أي حتى ${due} (م88)، ويجوز حسم الديون المستحقة بسبب العمل كرصيد السلف. لا تشمل الأرقام الأجر المستحق عن أيام الشهر الأخير، ولا مقابل الإشعار إن لم يُراعَ (م76). تقدير استرشادي؛ راجع الحالات الخاصة مع مختص.</p>`;
        return;
      }
      if (!(+v.w > 0) || !v.s || !v.t) return showErr($('#er', page), 'أكمل الأجر والتواريخ');
      const [x] = await db.rpc('eos_calc', { p_wage: +v.w, p_start: v.s, p_end: v.t, p_reason: v.r, p_unused_leave: +v.l || 0 });
      $('#er', page).innerHTML = `<div class="tw" style="margin-top:14px"><table><tbody>${row('مدة الخدمة', (+x.years).toFixed(2) + ' سنة')}${row('المكافأة الكاملة', money(x.full_award))}${row('النسبة المستحقة', Math.round(x.fraction * 100) + '%')}${row('المكافأة المستحقة', money(x.award))}${row('بدل الإجازات', money(x.leave_pay))}</tbody><tfoot><tr><td>الإجمالي</td><td class="r num">${money(x.total)}</td></tr></tfoot></table></div><p class="muted small">تقدير استرشادي؛ اختر الموظف من القائمة لحساب المخالصة كاملة من بياناته.</p>`;
    } catch (e) { showErr($('#er', page), e); } };
};

/* ===== users & invitations ===== */
const INVITABLE = () => has('owner') ? ['employee', 'manager', 'hr', 'finance', 'accountant', 'storekeeper', 'admin'] : has('admin') ? ['employee', 'manager', 'hr', 'finance', 'accountant', 'storekeeper']
  : has('hr') ? ['employee', 'manager', 'finance', 'accountant', 'storekeeper'] : has('finance') ? ['accountant', 'storekeeper'] : [];
const ROLE_DESC = { employee: 'خدماته الذاتية: الطلبات وقسائم الراتب وملفه', manager: 'اعتماد طلبات فريقه ومتابعة حضورهم', hr: 'الموظفون والرواتب والحضور والمستندات وصلاحيات الموظفين',
  finance: 'كل المالية واعتماد المسير والقيود', accountant: 'المالية حسب الصلاحيات المحددة له تحت', storekeeper: 'المخزون والأصناف حسب الصلاحيات المحددة له تحت', admin: 'كل شيء عدا ملكية المنشأة' };
const ACCESS_TPL = { employee: [['employee'], []], manager: [['employee', 'manager'], []], accountant: [['employee', 'accountant'], ['dash', 'sales', 'purch', 'je', 'ledger', 'reports', 'vat']],
  storekeeper: [['employee', 'storekeeper'], ['stock', 'stockadj', 'items']], sales: [['employee', 'accountant'], ['sales', 'items', 'stock']], purch: [['employee', 'accountant'], ['purch', 'items', 'stock']],
  finance: [['employee', 'finance'], []], hr: [['employee', 'hr'], []] };
const ACCESS_TPL_NAME = { employee: 'موظف', manager: 'مدير قسم', accountant: 'محاسب', storekeeper: 'أمين مستودع', sales: 'مندوب / مسؤول مبيعات', purch: 'مسؤول مشتريات', finance: 'مدير مالي', hr: 'موارد بشرية' };
const rolesOf = m => [m.role, ...(m.extra_roles || [])];
function accessDialog(m, who, myPerms) {
  const can2 = INVITABLE(), cur = rolesOf(m), order = ['employee', 'manager', 'hr', 'finance', 'accountant', 'storekeeper', 'admin'];
  const d = modal('صلاحيات ' + who, `<div class="row" style="gap:6px;align-items:center"><span class="small muted">${esc('قالب سريع')}:</span><select id="atpl" style="width:auto"><option value="">—</option>${Object.keys(ACCESS_TPL).filter(k => ACCESS_TPL[k][0].every(r => can2.includes(r) || cur.includes(r))).map(k => opt(k, ACCESS_TPL_NAME[k])).join('')}</select></div>
    <h3 style="margin:12px 0 6px;font-size:15px">${esc('الأدوار (يمكن اختيار أكثر من دور)')}</h3>
    <div class="acc-roles">${order.map(r => { const off = !can2.includes(r) && !cur.includes(r) || (!can2.includes(r) && cur.includes(r));
      return `<label class="acc-r${off ? ' off' : ''}"><input type="checkbox" name="r_${r}" ${cur.includes(r) ? 'checked' : ''} ${off ? 'disabled' : ''}><span><b>${esc(ROLES[r])}</b><br><span class="small muted">${esc(ROLE_DESC[r])}</span></span></label>`; }).join('')}</div>
    <div id="aperms"><h3 style="margin:14px 0 6px;font-size:15px">${esc('صلاحيات المالية والمخزون لهذا الشخص')}</h3><p class="muted small" style="margin:0 0 6px">${esc('تُضاف إلى صلاحيات دوره العامة في «إعدادات المنشأة».')}</p>
      <div class="acc-perms">${Object.entries(FPERMS).map(([p, t]) => `<label class="row small" style="gap:6px"><input type="checkbox" name="p_${p}" ${myPerms.includes(p) ? 'checked' : ''}> ${esc(t)}</label>`).join('')}</div></div>
    <p class="muted small">${esc('المالك له كل الصلاحيات دائماً. صلاحيات الموارد البشرية ومدير النظام يمنحها المالك. كل تغيير يُحفظ في سجل التدقيق.')}</p>`, {
    wide: true, ok: 'حفظ الصلاحيات', onOk: async f => {
      const roles = order.filter(r => f['r_' + r]), perms = Object.keys(FPERMS).filter(p => f['p_' + p]);
      if (!roles.length) throw new Error('اختر صلاحية واحدة على الأقل');
      await db.rpc('set_member_access', { p_company: S.cid, p_user: m.user_id, p_roles: roles, p_perms: perms }); toast('حُفظت الصلاحيات'); route(); } });
  const sync = () => { const f = $('#mform', d); $('#aperms', d).hidden = !(f.r_accountant.checked || f.r_storekeeper.checked); };
  $$('input[type=checkbox]', d).forEach(x => x.addEventListener('change', sync)); sync();
  $('#atpl', d).onchange = ev => { const t = ACCESS_TPL[ev.target.value]; if (!t) return; const f = $('#mform', d);
    order.forEach(r => { if (!f['r_' + r].disabled) f['r_' + r].checked = t[0].includes(r); }); Object.keys(FPERMS).forEach(p => f['p_' + p].checked = t[1].includes(p)); sync(); };
}
VIEWS['#/users'] = async page => {
  const [mem, inv, em] = await Promise.all([db.get('members', { company_id: 'eq.' + S.cid, order: 'created_at' }), db.get('invites', { company_id: 'eq.' + S.cid, order: 'created_at.desc' }), employeesMap()]);
  const mail = {}; inv.forEach(i => { if (i.accepted_by) mail[i.accepted_by] = i.email; }); mail[S.session.user.id] = S.session.user.email;
  const pending = inv.filter(i => !i.accepted_at);
  const admin = has('owner', 'admin');
  const mpr = isHR() ? await db.get('member_perms', { company_id: 'eq.' + S.cid }).catch(() => []) : [], mp = {}; mpr.forEach(x => (mp[x.user_id] = mp[x.user_id] || []).push(x.perm));
  const canAcc = m => isHR() && m.user_id !== S.session.user.id && m.role !== 'owner' && (has('owner', 'admin') || !rolesOf(m).some(r => r === 'hr' || r === 'admin'));
  page.innerHTML = `<div class="head"><div><h1>المستخدمون والدعوات</h1><div class="muted small">${esc('المالك يملك كل الصلاحيات، ويعيّن الموارد البشرية. الموارد البشرية تحدد صلاحيات كل موظف من زر «الصلاحيات».')}</div></div><button class="btn pri" id="ni">دعوة مستخدم</button></div>
    <h2>الدعوات المعلّقة</h2>${tbl([{ t: 'البريد', h: i => `<span class="num">${esc(i.email)}</span>` }, { t: 'الدور', h: i => esc(ROLES[i.role]) }, { t: 'سجل الموظف', h: i => esc(i.employee_id && em[i.employee_id] ? em[i.employee_id].full_name : '—') }, { t: 'رمز الدعوة', h: i => `<span class="code">${esc(i.code)}</span>` }, { t: '', h: i => `<button class="btn sm danger" data-rv="${i.id}">سحب</button>` }], pending, { empty: 'لا توجد دعوات معلّقة', onRow: true })}
    <div style="height:18px"></div><h2>المستخدمون</h2>${tbl([{ t: 'البريد / الدخول', h: m => mail[m.user_id] ? `<span class="num">${esc(mail[m.user_id])}</span>` : m.employee_id && em[m.employee_id] ? `<span class="muted small">${esc('بالرقم الوظيفي')}</span> <span class="num">${esc(em[m.employee_id].emp_no)}</span>` : '—' },
      { t: 'الصلاحيات', h: m => rolesOf(m).map(r => `<span class="badge${r === 'owner' ? ' info' : ''}">${esc(ROLES[r] || r)}</span>`).join(' ') + (mp[m.user_id] ? ` <span class="small muted">+${mp[m.user_id].length} ${esc('صلاحية مالية')}</span>` : '') },
      { t: 'سجل الموظف', h: m => esc(m.employee_id && em[m.employee_id] ? em[m.employee_id].full_name : '—') },
      { t: '', h: m => (canAcc(m) ? `<button class="btn sm pri" data-acc="${m.user_id}">${esc('الصلاحيات')}</button> ` : '') + (admin && (m.role !== 'owner' || has('owner')) ? `<button class="btn sm" data-ed="${m.user_id}">تعديل</button>` : '') }], mem)}`;
  bindRows(page, pending, inviteBox);
  $$('[data-rv]', page).forEach(b => b.addEventListener('click', ev => ev.stopPropagation()));
  $('#ni', page).onclick = () => {
    const linked = new Set(mem.map(m => m.employee_id).filter(Boolean));
    modal('دعوة مستخدم', `<div class="fg">${field('البريد الإلكتروني', inp('email', '', 'type="email" dir="ltr" required'))}${field('الدور', `<select name="role">${INVITABLE().map(r => opt(r, ROLES[r])).join('')}</select>`)}
      ${field('ربطه بسجل موظف', `<select name="emp"><option value="">—</option>${Object.values(em).filter(e => !linked.has(e.id)).map(e => opt(e.id, e.full_name + ' (' + e.emp_no + ')')).join('')}</select>`, 'wide')}</div>
      <p class="muted small">بعد الحفظ يظهر رمز دعوة. أرسله للشخص مع رابط النظام؛ ينشئ حساباً بنفس البريد ثم يُدخل الرمز.</p>`, {
      ok: 'إنشاء الدعوة', onOk: async f => { const id = await db.rpc('invite_member', { p_company: S.cid, p_email: f.email, p_role: f.role, p_employee: blank(f.emp) }); const [i] = await db.get('invites', { id: 'eq.' + id }); route(); setTimeout(() => inviteBox(i), 60); }
    });
  };
  $$('[data-rv]', page).forEach(b => b.onclick = async () => { try { await db.rpc('revoke_invite', { p_id: b.dataset.rv }); route(); } catch (e) { toast(e.message); } });
  $$('[data-acc]', page).forEach(b => b.onclick = () => { const m = mem.find(x => x.user_id === b.dataset.acc);
    accessDialog(m, mail[m.user_id] || (m.employee_id && em[m.employee_id] ? em[m.employee_id].full_name : ''), mp[m.user_id] || []); });
  $$('[data-ed]', page).forEach(b => b.onclick = () => {
    const m = mem.find(x => x.user_id === b.dataset.ed); const linked = new Set(mem.filter(x => x !== m).map(x => x.employee_id).filter(Boolean));
    const roles = Object.keys(ROLES).filter(r => r !== 'owner' || has('owner'));
    const d = modal('تعديل مستخدم', `<p class="num">${esc(mail[m.user_id] || '')}</p><div class="fg">${field('الدور', `<select name="role">${roles.map(r => opt(r, ROLES[r], m.role)).join('')}</select>`)}${field('سجل الموظف', `<select name="emp"><option value="">—</option>${Object.values(em).filter(e => !linked.has(e.id)).map(e => opt(e.id, e.full_name, m.employee_id)).join('')}</select>`)}</div>
      ${m.user_id !== S.session.user.id ? '<button type="button" class="btn danger sm" id="rm" style="margin-top:12px">إزالة من المنشأة</button>' : ''}`, {
      onOk: async f => { await db.upd('members', { company_id: 'eq.' + S.cid, user_id: 'eq.' + m.user_id }, { role: f.role, employee_id: blank(f.emp) }); if (m.user_id === S.session.user.id) { await loadContext(); shell(); } cache.emps = null; toast('تم الحفظ'); route(); }
    });
    if ($('#rm', d)) $('#rm', d).onclick = async () => { try { await db.del('members', { company_id: 'eq.' + S.cid, user_id: 'eq.' + m.user_id }); d.close(); toast('أُزيل المستخدم'); route(); } catch (e) { showErr($('#merr', d), e); } };
  });
};

function inviteBox(i) {
  if (!i) return;
  const link = location.origin + location.pathname;
  const msg = 'دعوة للانضمام إلى ' + S.company.name + ' في نظام وعد:\n1) افتح ' + link + '\n2) اختر «حساب جديد بالبريد» وسجّل بالبريد ' + i.email + '\n3) أدخل رمز الدعوة: ' + i.code;
  const d = modal('رمز الدعوة', `<p class="muted small">أرسل الرمز والرابط إلى <b class="num">${esc(i.email)}</b> (${esc(ROLES[i.role])}). يسجّل بنفس البريد ثم يُدخل الرمز.</p>
    <div style="text-align:center;margin:14px 0"><span class="code" id="ic" style="font-size:28px;padding:6px 16px">${esc(i.code)}</span></div>
    <div class="row" style="justify-content:center"><button type="button" class="btn pri" id="cpc">نسخ الرمز</button><button type="button" class="btn" id="cpm">نسخ رسالة جاهزة</button>${waBtn('', tr(msg))}${navigator.share ? '<button type="button" class="btn" id="shm">مشاركة</button>' : ''}</div>`);
  const copy = async (t, b) => { try { await navigator.clipboard.writeText(t); b.textContent = 'نُسخ ✓'; } catch (e) { toast('انسخه يدوياً: ' + t); } };
  $('#cpc', d).onclick = e => copy(i.code, e.target);
  $('#cpm', d).onclick = e => copy(tr(msg), e.target);
  if ($('#shm', d)) $('#shm', d).onclick = () => navigator.share({ text: tr(msg) }).catch(() => {});
}

/* ===== company settings & finance permissions ===== */
const FPERMS = { dash: 'لوحة المالية', sales: 'المبيعات والعملاء', purch: 'المشتريات والموردون', stock: 'عرض المخزون', stockadj: 'تسوية المخزون', items: 'إدارة الأصناف', void: 'الإلغاء والإشعارات الدائنة', je: 'عرض القيود', jepost: 'ترحيل القيود اليدوية', ledger: 'دفتر الأستاذ', reports: 'القوائم المالية', vat: 'إقرار الضريبة', coa: 'دليل الحسابات', payroll: 'قيود الرواتب', settings: 'إعدادات المالية' };
// «الربط مع فاتورة» (ZATCA Phase 2): the owner / an admin pastes the OTP from the Fatoora portal; the server does the rest
async function zatcaCard(el) {
  const co = S.company || {}, [z] = await db.get('zatca_settings', { company_id: 'eq.' + S.cid }).catch(() => []);
  const docs = z && z.enabled ? await db.get('zatca_docs', { company_id: 'eq.' + S.cid, select: 'status', limit: 5000 }).catch(() => []) : [];
  const cnt = st => docs.filter(d => d.status === st).length, envN = { simulation: 'بيئة المحاكاة (تجريبي)', production: 'الإنتاج (فعلي)', sandbox: 'بيئة المطوّرين' };
  const missing = [!/^3\d{13}3$/.test(co.vat_no || '') && tr('الرقم الضريبي (15 رقماً يبدأ وينتهي بـ 3)'), !(co.street && co.bld_no && co.district && co.city && co.postal_code) && tr('العنوان الوطني كاملاً')].filter(Boolean);
  el.innerHTML = `<h2>${esc(tr('الربط مع فاتورة (زاتكا — المرحلة الثانية)'))}</h2>
    ${z && z.enabled ? `<p><span class="badge ok">${esc(tr('مربوطة'))}</span> ${esc(tr(envN[z.env] || z.env))}${z.onboarded_at ? ' · ' + esc(tr('منذ')) + ' ' + fdate(String(z.onboarded_at).slice(0, 10)) : ''} · ${esc(tr('آخر تسلسل'))} <span class="num">${z.icv}</span></p>
      <p class="small">${esc(tr('أُبلغت أو اعتُمدت'))} <b class="num">${cnt('reported') + cnt('cleared') + cnt('warning')}</b> · ${esc(tr('بانتظار الإرسال'))} <b class="num">${cnt('pending') + cnt('error')}</b> · ${esc(tr('مرفوضة'))} <b class="num">${cnt('rejected')}</b></p>
      <p class="muted small">${esc(tr('كل فاتورة مبيعات وإشعار دائن أو مدين يُرسل تلقائياً بعد ترحيله. الفاتورة الضريبية (لعميل له رقم ضريبي) تُعتمد قبل تسليمها، والمبسطة تُبلَّغ خلال 24 ساعة. لا تُلغى الفواتير بعد الربط؛ التصحيح بإشعار دائن.'))}</p>`
    : `<p class="muted small">${esc(tr('اربط منشأتك ببوابة «فاتورة» لتُرسل فواتير المبيعات إلى زاتكا تلقائياً كما تشترط المرحلة الثانية من الفوترة الإلكترونية.'))}</p>
      <ol class="small" style="margin:0 0 8px;padding-inline-start:18px"><li>${esc(tr('ادخل بوابة فاتورة fatoora.zatca.gov.sa بحساب المنشأة.'))}</li><li>${esc(tr('اختر «تسجيل وحدة حلول فوترة إلكترونية جديدة» واطلب رمز OTP (صالح لمدة قصيرة).'))}</li><li>${esc(tr('الصق الرمز هنا واضغط «ربط». نُكمل الباقي: الشهادة واختبارات الامتثال الستة وشهادة الإنتاج.'))}</li></ol>`}
    ${missing.length ? `<p class="small" style="color:var(--gold)">${esc(tr('أكمل أولاً في «بيانات المنشأة»'))}: ${missing.map(esc).join('، ')}</p>` : ''}
    ${!co.cr_no ? `<p class="small muted">${esc(tr('يُفضّل إضافة السجل التجاري في «بيانات المنشأة»: زاتكا تقبل الفاتورة بدونه لكن مع ملاحظة.'))}</p>` : ''}
    ${z && z.last_error ? `<p class="small" style="color:var(--bad)" data-nt>${esc(tr('آخر محاولة'))}: ${esc(z.last_error)}</p>` : ''}
    <form id="zf" class="fg" style="margin-top:8px">${field('البيئة', `<select name="env">${opt('simulation', tr('بيئة المحاكاة (تجريبي)'), z && z.env)}${opt('production', tr('الإنتاج (فعلي)'), z && z.env)}</select>`)}
      ${field('رمز OTP من بوابة فاتورة', '<input name="otp" inputmode="numeric" pattern="\\d{6}" maxlength="6" dir="ltr" placeholder="123456" required>')}
      <div class="wide"><div id="zerr"></div><button class="btn ${z && z.enabled ? '' : 'pri'}" id="zb" ${missing.length ? 'disabled' : ''}>${esc(tr(z && z.enabled ? 'إعادة الربط (تجديد الشهادة أو الانتقال للإنتاج)' : 'ربط'))}</button>
      <p class="muted small">${esc(tr('قد يستغرق الربط دقيقة. بعد الربط لا تُلغى فواتير المبيعات، وتُصحّح بإشعار دائن.'))} ${esc(tr('فواتير بيئة المحاكاة للتجربة ولا يُعتدّ بها؛ للربط الفعلي اختر «الإنتاج».'))}</p></div></form>`;
  $('#zf', el).onsubmit = async e => { e.preventDefault(); const f = formData(e.target);
    try { await busy($('#zb', el), async () => {
      if (!/^\d{6}$/.test((f.otp || '').trim())) throw new Error('رمز OTP من 6 أرقام');
      await fnCall('zatca', { action: 'onboard', company: S.cid, env: f.env, otp: f.otp.trim() });
      S.zatcaOn = true; toast(tr('تم الربط مع فاتورة')); route(); }); }
    catch (er) { showErr($('#zerr', el), er); }
  };
}
VIEWS['#/settings'] = async page => {
  const co = S.company; const admin = has('owner', 'admin');
  const fp = can('settings') ? await db.get('finance_permissions', { company_id: 'eq.' + S.cid }) : [];
  const seeded = admin ? (await db.get('demo_seeds', { company_id: 'eq.' + S.cid }).catch(() => [])).length > 0 : false;
  const hasEmps = admin ? (await db.get('employees', { company_id: 'eq.' + S.cid, select: 'id', limit: 1 }).catch(() => [])).length > 0 : true;
  const on = (r, p) => fp.some(x => x.role === r && x.perm === p);
  page.innerHTML = `<div class="head"><div><h1>إعدادات المنشأة</h1></div></div>
   ${admin ? `<div class="card"><h2>بيانات المنشأة</h2><p>رمز المنشأة لدخول الموظفين: <span class="code">${esc(co.code || '')}</span> <button type="button" class="btn sm" id="ccb">إرسال الرمز لبريدي / مشاركته</button></p><form id="cf" class="fg" novalidate>${field('الاسم', inp('name', co.name))}${field('الاسم بالإنجليزية', inp('name_en', co.name_en, 'dir="ltr"'))}${field('الرقم الضريبي', inp('vat_no', co.vat_no, 'dir="ltr" inputmode="numeric" maxlength="15"'))}${field('السجل التجاري', inp('cr_no', co.cr_no, 'dir="ltr" inputmode="numeric" maxlength="10"'))}${profileFields(co, false)}
     ${field('الرقم الموحد للمنشأة', inp('unified_no', co.unified_no, 'dir="ltr" inputmode="numeric" maxlength="10" placeholder="7XXXXXXXXX"'))}${field('رقم المنشأة في الموارد البشرية (قوى)', inp('mhrsd_no', co.mhrsd_no, 'dir="ltr" placeholder="1-123456"'))}${field('رقم المنشأة في التأمينات', inp('gosi_no', co.gosi_no, 'dir="ltr" inputmode="numeric"'))}
     <h3 class="wide" style="margin:8px 0 0">${esc(tr('العنوان الوطني'))}</h3><p class="wide muted small" style="margin:0">${esc(tr('يظهر في الفواتير الضريبية والخطابات — من سبل (العنوان الوطني).'))}</p>${addrFields(co)}
     ${co.address && !co.city ? field('العنوان (نص حر)', inp('address', co.address), 'wide') : ''}
     <h3 class="wide" style="margin:8px 0 0">${esc(tr('التواصل والبنك'))}</h3>${field('الهاتف', inp('phone', co.phone, 'dir="ltr"'))}${field('البريد الإلكتروني', inp('email', co.email, 'type="email" dir="ltr"'))}
     ${field('الآيبان (يظهر في فواتير المبيعات)', inp('iban', co.iban, 'dir="ltr" maxlength="34" id="cibn"') + `<div class="small muted" id="cibk">${esc(ibanBank(co.iban))}</div>`)}
     <div class="wide"><label class="row" style="gap:6px"><input type="checkbox" name="monthly_report" ${co.monthly_report !== false ? 'checked' : ''}> ${esc(tr('الملخص الشهري بالإيميل: يصل للمالك أول كل شهر بمبيعات الشهر الماضي ومشترياته ورواتبه والمتأخرات وما ينتظر الاعتماد.'))}</label></div>
     <div class="wide"><div id="cerr"></div><button class="btn pri" id="cb">حفظ</button></div></form></div>
   <div class="card" id="logocard"><h2>شعار المنشأة</h2><div class="row"><div class="logo-prev">${co.logo ? `<img src="${esc(co.logo)}" alt="">` : '<span class="muted small">لا يوجد شعار</span>'}</div>
     <label class="btn sm pri">${co.logo ? 'تغيير الشعار' : 'رفع الشعار'}<input type="file" id="lgf" accept="image/*" hidden></label>${co.logo ? '<button type="button" class="btn sm" id="lgd">إزالة الشعار</button>' : ''}</div>
     <div id="lgerr"></div><p class="muted small">يظهر أعلى الخطابات المطبوعة. يفضّل PNG بخلفية شفافة؛ نصغّر الصورة تلقائياً.</p></div>` : ''}
   ${admin && S.sub ? `<div class="card"><h2>${esc(tr('الاشتراك'))}</h2><p>${esc(tr('الباقة'))}: <b>${esc(S.sub.plan)}</b> · <span class="badge ${subState(S.sub)[1]}">${esc(tr(subState(S.sub)[0]))}</span>${S.sub.status === 'trial' && S.sub.trial_ends ? ` · ${esc(tr('تنتهي التجربة'))} <span class="num">${esc(S.sub.trial_ends)}</span>` : ''}${S.sub.status === 'active' && S.sub.sub_ends ? ` · ${esc(tr('ينتهي الاشتراك'))} <span class="num">${esc(S.sub.sub_ends)}</span>` : ''}${S.sub.max_users ? ` · ${esc(tr('الحد الأعلى للمستخدمين'))} <span class="num">${S.sub.max_users}</span>` : ''}</p>
     <p>${Object.entries(MODULES).map(([k, t]) => `<span class="badge ${modOn(k) ? 'ok' : ''}">${modOn(k) ? '✓' : '✕'} ${esc(tr(t))}</span>`).join(' ')}</p><p class="muted small">${esc(tr('لتغيير الباقة أو فتح قسم تواصل مع إدارة وعد.'))}</p></div>` : ''}
   ${admin && (modOn('finance') || modOn('sales')) ? '<div class="card" id="zcard"></div>' : ''}
   ${admin && seeded ? `<div class="card"><h2>${esc(tr('بيانات تجريبية'))}</h2>
     ${seeded
       ? `<p class="muted small">${esc(tr('منشأتك تحتوي بيانات تجريبية. يمكنك مسحها لتبدأ بإدخال بياناتك الحقيقية.'))}</p><button type="button" class="btn danger" id="democlear">${esc(tr('مسح البيانات التجريبية'))}</button>`
       : hasEmps
         ? `<p class="muted small">${esc(tr('تُضاف البيانات التجريبية فقط لمنشأة جديدة بلا موظفين، لحماية بياناتك الحقيقية.'))}</p>`
         : ''}
     <div id="demoerr"></div></div>` : ''}
   ${has('owner') ? `<div class="card"><h2>${esc(tr('تصدير بيانات المنشأة'))}</h2><p class="muted small">${esc(tr('نسخة كاملة من كل بيانات منشأتك لحفظها لديك أو نقلها. للمالك فقط، ويُسجَّل كل تصدير في سجل التدقيق.'))}</p>
     <div class="row" style="gap:8px;flex-wrap:wrap"><button type="button" class="btn" id="exx">${esc(tr('ملف Excel (بدون المرفقات)'))}</button><button type="button" class="btn" id="exj">${esc(tr('ملف JSON كامل (مع المرفقات)'))}</button></div><div id="exerr"></div></div>` : ''}
   ${can('settings') ? `<div class="card"><h2>صلاحيات المحاسب وأمين المستودع</h2><p class="muted small">المدير المالي والمالك يرون كل شيء. حدّد هنا ما يراه غيرهم.</p>
     <div class="tw"><table><thead><tr><th>الصلاحية</th><th>محاسب</th><th>أمين مستودع</th></tr></thead><tbody>${Object.entries(FPERMS).map(([p, t]) => `<tr><td>${esc(t)}</td>${['accountant', 'storekeeper'].map(r => `<td><input type="checkbox" data-r="${r}" data-p="${p}" ${on(r, p) ? 'checked' : ''} aria-label="${esc(t + ' — ' + ROLES[r])}"></td>`).join('')}</tr>`).join('')}</tbody></table></div></div>` : ''}`;
  if ($('#cf', page)) $('#cf', page).onsubmit = async e => { e.preventDefault(); const f = formData(e.target);
    try { await busy($('#cb', page), async () => { const pe = profileErr(f, false); if (pe) throw new Error(pe); await db.upd('companies', { id: 'eq.' + S.cid }, Object.assign({ name: f.name, name_en: blank((f.name_en || '').trim()), vat_no: blank(f.vat_no), cr_no: blank(f.cr_no), unified_no: blank(f.unified_no), mhrsd_no: blank(f.mhrsd_no), gosi_no: blank(f.gosi_no),
      phone: blank(f.phone), email: blank(f.email), iban: blank(f.iban), monthly_report: !!f.monthly_report }, profileRow(f), Object.fromEntries(SA_ADDR.map(([k]) => [k, blank(f[k])])), 'address' in f ? { address: blank(f.address) } : {})); await loadContext(); shell(); toast('تم الحفظ'); route(); }); } catch (er) { showErr($('#cerr', page), er); } };
  const setLogo = async v => { try { await db.upd('companies', { id: 'eq.' + S.cid }, { logo: v }); await loadContext(); toast('تم الحفظ'); route(); } catch (er) { showErr($('#lgerr', page), er); } };
  if ($('#lgf', page)) $('#lgf', page).onchange = async ev => { const f = ev.target.files[0]; if (!f) return; try { await setLogo(await imgToLogo(f)); } catch (er) { showErr($('#lgerr', page), er); } };
  if ($('#lgd', page)) $('#lgd', page).onclick = () => setLogo(null);
  if ($('#zcard', page)) zatcaCard($('#zcard', page));
  if ($('#ccb', page)) $('#ccb', page).onclick = () => companyCodeBox(false);
  ['exx', 'exj'].forEach(k => { const b = $('#' + k, page); if (b) b.onclick = async () => { try { await busy(b, () => exportCompany(k === 'exj')); } catch (er) { showErr($('#exerr', page), er); } }; });
  if ($('#cibn', page)) $('#cibn', page).oninput = e => { $('#cibk', page).textContent = ibanBank(e.target.value); };
  if ($('#democlear', page)) $('#democlear', page).onclick = () => modal(tr('مسح البيانات التجريبية'),
    `<p>${esc(tr('سيُحذف كل ما في أقسام الموظفين والعملاء والحملات والمشاريع. هذا الإجراء لا يمكن التراجع عنه.'))}</p>`,
    { ok: 'مسح', onOk: async () => { await db.rpc('demo_clear', { p_company: S.cid }); cache.emps = null; toast(tr('مُسحت البيانات التجريبية')); route(); } });
  $$('input[data-p]', page).forEach(c => c.onchange = async () => { try { await db.rpc('set_finance_permission', { p_company: S.cid, p_role: c.dataset.r, p_perm: c.dataset.p, p_allowed: c.checked }); toast('تم'); } catch (e) { c.checked = !c.checked; toast(e.message); } });
};

/* ===== full company export (owner): Excel without attachments, or complete JSON ===== */
async function exportCompany(files) {
  const d = await db.rpc('company_export', { p_company: S.cid, p_files: files }), stamp = today(), base = 'waad-' + (S.company.code || 'company') + '-' + stamp;
  if (files) return anSave(new Blob([JSON.stringify(d, null, 1)], { type: 'application/json' }), base + '.json');
  const cell = v => v == null ? '' : typeof v === 'number' ? v : typeof v === 'boolean' ? (v ? 'true' : 'false') : (typeof v === 'object' ? JSON.stringify(v) : String(v)).slice(0, 32000);
  const tabs = Object.entries(d.tables).filter(([, rows]) => rows.length);
  const sheets = [{ name: tr('اقرأني'), rows: [[tr('البند'), tr('القيمة')], [tr('المنشأة'), S.company.name], [tr('تاريخ التصدير'), String(d.exported_at).slice(0, 19).replace('T', ' ')],
    [tr('الجداول'), tabs.length], [tr('السجلات'), tabs.reduce((a, [, r]) => a + r.length, 0)], [tr('ملاحظة'), tr('المرفقات والشعار غير مضمّنة في Excel — نزّل ملف JSON الكامل للحصول عليها.')]] }];
  for (const [t, rows] of tabs) { const cols = [...new Set(rows.flatMap(r => Object.keys(r)))]; sheets.push({ name: t, rows: [cols, ...rows.map(r => cols.map(c => cell(r[c])))] }); }
  anSave(xlsxBook(sheets), base + '.xlsx'); toast(tr('تم التصدير'));
}

/* ===== Nitaqat (Saudization) estimate: weights by registered wage; band thresholds entered by HR from Qiwa ===== */
const NIT_BANDS = [['plat', 'بلاتيني', 'ok'], ['high', 'أخضر مرتفع', 'ok'], ['mid', 'أخضر متوسط', 'ok'], ['low', 'أخضر منخفض', 'info']];
const nitW = e => { if (!e.is_saudi) return 0; const w = n0(e.basic) + n0(e.housing); return w >= 4000 ? 1 : w >= 3000 ? 0.5 : 0; };
function nitBand(pct, th) { for (const [k, t, c] of NIT_BANDS) if (th[k] != null && pct >= th[k]) return [t, c, k]; return th.low != null ? ['أحمر', 'bad', 'red'] : ['—', '', '']; }
const nitNeed = (W, T, thr) => { const f = thr / 100; if (T > 0 && W / T >= f) return 0; return Math.max(0, Math.ceil((f * T - W) / (1 - f) - 1e-9)); };
VIEWS['#/nitaqat'] = async page => {
  if (!isHR()) { page.innerHTML = '<div class="note">هذه الصفحة للموارد البشرية.</div>'; return; }
  const em = await employeesMap(true), td = today(), act = Object.values(em).filter(e => !e.end_date || e.end_date >= td);
  const th = (S.company && S.company.nitaqat) || {};
  const sa = act.filter(e => e.is_saudi), W = act.reduce((a, e) => a + nitW(e), 0), T = act.length, pct = T ? W / T * 100 : 0;
  const [bt, bc, bk] = nitBand(pct, th), under = sa.filter(e => nitW(e) < 1).sort((a, b) => (n0(b.basic) + n0(b.housing)) - (n0(a.basic) + n0(a.housing)));
  const order = ['low', 'mid', 'high', 'plat'], next = order.find(k => th[k] != null && pct < th[k]);
  const nm = { low: 'أخضر منخفض', mid: 'أخضر متوسط', high: 'أخضر مرتفع', plat: 'بلاتيني' };
  page.innerHTML = `<div class="head"><div><h1>نطاقات والتوطين</h1><div class="muted">${esc(tr('تقدير داخلي من بيانات الموظفين — التصنيف الرسمي في منصة قوى'))}</div></div></div>
    <div class="grid" style="margin-bottom:16px">
      <div class="card kpi"><div class="muted small">${esc(tr('نسبة التوطين المحتسبة'))}</div><div class="v num">${r2(pct)}%</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('النطاق المتوقع'))}</div><div class="v"><span class="badge ${bc}" style="font-size:16px">${esc(tr(bt))}</span></div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('السعوديون المحتسبون'))}</div><div class="v num">${r2(W)} / ${sa.length}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('إجمالي العاملين'))}</div><div class="v num">${T}</div></div></div>
    ${next ? `<div class="note">${esc(tr('للوصول إلى'))} <b>${esc(tr(nm[next]))}</b> (${th[next]}%): ${esc(tr('توظيف'))} <b class="num">${nitNeed(W, T, th[next])}</b> ${esc(tr('سعودي بأجر 4,000 فأكثر'))}${under.length ? ` — ${esc(tr('أو رفع أجور السعوديين المحتسبين جزئياً'))}` : ''}.</div>` : th.low == null ? `<div class="note">${esc(tr('أدخل نسب النطاقات من منصة قوى لمعرفة النطاق والمطلوب.'))}</div>` : ''}
    <div class="card"><h2>${esc(tr('ماذا لو؟'))}</h2><div class="fg" id="nwf">
      ${field('توظيف سعوديين (عدد)', '<input name="ns" type="number" min="0" value="0">')}${field('بأجر (أساسي + سكن)', '<input name="nw" type="number" min="0" value="4000">')}
      ${field('توظيف غير سعوديين (عدد)', '<input name="nf" type="number" min="0" value="0">')}${field('خروج غير سعوديين (عدد)', '<input name="xf" type="number" min="0" value="0">')}</div>
      <p id="nwr" style="margin:8px 0 0"></p></div>
    <div class="card"><h2>${esc(tr('سعوديون لا يُحتسبون كاملاً'))}</h2>
      ${tbl([{ t: 'الموظف', h: e => esc(e.full_name) + ` <span class="muted num small">${esc(e.emp_no)}</span>` }, { t: 'أساسي + سكن', r: 1, h: e => money(n0(e.basic) + n0(e.housing)) },
        { t: 'يُحتسب', r: 1, h: e => String(nitW(e)) }, { t: 'للاحتساب كاملاً', h: e => `${esc(tr('رفع الأجر'))} <b class="num">${money(4000 - n0(e.basic) - n0(e.housing))}</b>` }], under, { empty: 'كل السعوديين يُحتسبون كاملاً' })}</div>
    <div class="card"><h2>${esc(tr('نسب النطاقات لمنشأتك'))}</h2><p class="muted small">${esc(tr('تختلف النسب حسب النشاط وعدد العاملين — انسخها من منصة قوى (نطاقات ← تفاصيل النطاق).'))}</p>
      <form id="ntf" class="fg" novalidate>${order.map(k => field(nm[k] + ' %', `<input name="${k}" type="number" step="0.01" min="0" max="100" value="${th[k] ?? ''}">`)).join('')}<div class="wide"><button class="btn pri" id="nts">حفظ</button></div><div id="nterr" class="wide"></div></form></div>
    <p class="muted small">${esc(tr('طريقة الاحتساب: السعودي بأجر 4,000 فأكثر = 1، من 3,000 إلى أقل من 4,000 = نصف، أقل من 3,000 = لا يُحتسب. الأجر = المسجل في التأمينات (أساسي + سكن). لا يشمل التقدير ذوي الإعاقة والطلاب والعمل الجزئي والمرن، ويُشترط توثيق العقد في قوى.'))}</p>`;
  const f = $('#nwf', page), calc = () => { const v = n => Math.max(0, +f.querySelector(`[name=${n}]`).value || 0), ns = v('ns'), w = v('nw'), nf = v('nf'), xf = Math.min(v('xf'), T - sa.length);
    const W2 = W + ns * (w >= 4000 ? 1 : w >= 3000 ? 0.5 : 0), T2 = T + ns + nf - xf, p2 = T2 ? W2 / T2 * 100 : 0, [b2, c2] = nitBand(p2, th);
    $('#nwr', page).innerHTML = `${esc(tr('النسبة بعد التغيير'))}: <b class="num">${r2(p2)}%</b> — <span class="badge ${c2}">${esc(tr(b2))}</span>`; };
  $$('input', f).forEach(x => x.oninput = calc); calc();
  $('#nts', page).onclick = ev => { ev.preventDefault(); busy(ev.target, async () => { const v = formData($('#ntf', page));
    try { await db.rpc('nitaqat_set', { p_company: S.cid, p_bands: v }); await loadContext(); toast('تم الحفظ'); route(); } catch (e) { showErr($('#nterr', page), e); } }); };
};
