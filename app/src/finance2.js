'use strict';
/* ===== finance, phase one (0121): bank statement matching, one payment over several invoices, prepaid expenses,
   journal drafts with approval / automatic reversal / recurrence / Excel import, and the month-end close checklist ===== */
const accOpts = (acc, f, sel) => acc.filter(a => !a.is_header && (!f || f(a))).map(a => opt(a.code, a.code + ' — ' + ((LANG === 'en' && a.name_en) || a.name), sel)).join('');
const bankAccs = acc => acc.filter(a => a.parent_code === '1100' && !a.is_header && a.code !== '1110' && !/^113/.test(a.code));

/* ---------- «مطابقة كشف البنك» ---------- */
VIEWS['#/bankmatch'] = async (page, arg, q) => {
  if (!can('je')) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للمالية.'))}</div>`; return; }
  const acc = await accounts(), banks = bankAccs(acc); if (!banks.length) { page.innerHTML = `<div class="note">${esc(tr('لا يوجد حساب بنك في دليل الحسابات.'))}</div>`; return; }
  const code = q.get('a') || LS.get('waad.bma') || banks[0].code; LS.set('waad.bma', code);
  const rows = await db.rpc('bank_suggest', { p_company: S.cid, p_account: code });
  const sug = rows.filter(r => r.jl_id), rest = rows.filter(r => !r.jl_id);
  page.innerHTML = `<div class="head"><div><a href="#/bankrec" class="small back">${esc(tr('التسوية البنكية'))}</a><h1>${esc(tr('مطابقة كشف البنك'))}</h1>
      <div class="muted">${esc(tr('ارفع كشف حساب البنك (Excel أو CSV)، ويقترح وعد القيد المطابق لكل حركة بنفس المبلغ خلال 5 أيام. الحركات غير المسجلة (مثل العمولات) تسجّل لها قيدا سريعا.'))}</div></div>
      <div class="row" style="gap:6px"><select id="bma" style="width:auto">${banks.map(a => opt(a.code, a.code + ' — ' + a.name, code)).join('')}</select>
        <label class="btn pri" style="margin:0;color:var(--prim-ink)">${esc(tr('رفع كشف البنك'))}<input type="file" id="bmf" accept=".xlsx,.csv" hidden></label></div></div>
    <div class="card"><h2>${esc(tr('مطابقات مقترحة'))} <span class="num">${sug.length}</span></h2>${sug.length ? tbl([{ t: '', h: r => `<input type="checkbox" data-bm="${r.line_id}" data-jl="${r.jl_id}" checked aria-label="${esc(tr('اعتماد'))}">` },
        { t: 'تاريخ البنك', h: r => fdate(r.day) }, { t: 'وصف البنك', h: r => esc(r.description || r.ref || '') }, { t: 'المبلغ', r: 1, h: r => `<span class="${n0(r.amount) < 0 ? 'bad' : ''}">${money(r.amount)}</span>` },
        { t: 'القيد في الدفاتر', h: r => `${fdate(r.jl_date)} · ${esc(r.jl_memo || '')}` }], sug) + `<button class="btn pri" id="bmok" style="margin-top:8px">${esc(tr('اعتماد المحدد'))}</button>` : `<p class="muted small">${esc(tr('لا توجد مطابقات مقترحة.'))}</p>`}</div>
    <div class="card"><h2>${esc(tr('حركات بنكية غير موجودة في الدفاتر'))} <span class="num">${rest.length}</span></h2>${rest.length ? tbl([{ t: 'التاريخ', h: r => fdate(r.day) }, { t: 'الوصف', h: r => esc(r.description || r.ref || '') },
        { t: 'المبلغ', r: 1, h: r => `<span class="${n0(r.amount) < 0 ? 'bad' : ''}">${money(r.amount)}</span>` }, { t: '', h: r => can('jepost') ? `<button class="btn sm" data-bq="${r.line_id}">${esc(tr('قيد سريع'))}</button>` : '' }], rest) : `<p class="muted small">${esc(tr('كل حركات الكشف مطابقة.'))}</p>`}</div>`;
  $('#bma', page).onchange = e => location.hash = '#/bankmatch?a=' + e.target.value;
  if ($('#bmok', page)) $('#bmok', page).onclick = () => busy($('#bmok', page), async () => { const ls = $$('[data-bm]:checked', page).map(c => ({ line: c.dataset.bm, jl: +c.dataset.jl }));
    const n = await db.rpc('bank_match', { p_lines: ls }); toast(tr('طوبقت') + ' ' + n); route(); });
  $$('[data-bq]', page).forEach(b => b.onclick = () => { const r = rest.find(x => x.line_id === b.dataset.bq);
    modal(tr('قيد سريع للحركة البنكية'), `<p>${fdate(r.day)} · ${esc(r.description || '')} · <b class="num">${money(r.amount)}</b></p><div class="fg">${field(n0(r.amount) < 0 ? 'حساب المصروف' : 'الحساب المقابل', `<select name="a">${accOpts(acc, a => a.code !== code && (n0(r.amount) < 0 ? a.type === 'exp' || a.type === 'liab' : true), n0(r.amount) < 0 ? '5900' : '')}</select>`)}${field('البيان', inp('m', r.description || '', 'maxlength="200"'))}</div>`,
      { ok: 'ترحيل', onOk: async f => { await db.rpc('bank_quick_post', { p_line: r.line_id, p_account: f.a, p_memo: f.m }); toast(tr('تم الترحيل')); route(); } }); });
  $('#bmf', page).onchange = async ev => { const file = ev.target.files[0]; if (!file) return;
    try { const { hdr, body } = await readSheetFile(file), h = hdr.map(x => String(x || '').toLowerCase().trim());
      const fi = re => h.findIndex(x => re.test(x));
      const cD = fi(/date|تاريخ/), cDesc = fi(/desc|details|narr|بيان|وصف|تفاصيل/), cRef = fi(/ref|مرجع/), cAmt = fi(/^amount$|^المبلغ$|مبلغ/), cDr = fi(/debit|withdraw|مدين|سحب|خصم/), cCr = fi(/credit|deposit|دائن|إيداع|ايداع/);
      if (cD < 0 || (cAmt < 0 && cDr < 0 && cCr < 0)) throw new Error(tr('لم نجد عمود التاريخ والمبلغ (أو مدين ودائن) في الكشف'));
      const num = v => +String(v == null ? '' : v).replace(/[^\d.\-]/g, '') || 0, dt = v => { const s = String(v || '').trim(); let m;
        if ((m = /(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})/.exec(s))) return `${m[1]}-${m[2].padStart(2, '0')}-${m[3].padStart(2, '0')}`;
        if ((m = /(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})/.exec(s))) return `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`; return null; };
      // a bank statement debit is money out of the account (−), a credit is money in (+)
      const rows = body.map(({ r }, i) => ({ day: dt(r[cD]), desc: cDesc >= 0 ? String(r[cDesc] || '') : '', ref: cRef >= 0 ? String(r[cRef] || '') : '', seq: i,
        amount: cAmt >= 0 ? num(r[cAmt]) : num(r[cCr]) - num(r[cDr]) })).filter(x => x.day && x.amount);
      const res = await db.rpc('bank_lines_import', { p_company: S.cid, p_account: code, p_rows: rows });
      toast(tr('أُضيفت') + ' ' + res.added + (res.duplicates ? ' · ' + tr('مكررة') + ' ' + res.duplicates : '')); route();
    } catch (e) { toast(e.message); } };
};

/* ---------- one receipt / payment over several invoices (oldest first) ---------- */
async function allocateForm(dir) {
  const [parties, acc] = await Promise.all([db.get('parties', Object.assign(C(), { kind: 'eq.' + (dir === 'in' ? 'customer' : 'supplier'), select: 'id,name', order: 'name' })), accounts()]);
  const d = modal(dir === 'in' ? tr('سند قبض على عدة فواتير') : tr('سند صرف على عدة فواتير'), `<div class="fg">${field(dir === 'in' ? 'العميل' : 'المورد', `<select name="p"><option value="">—</option>${parties.map(p => opt(p.id, p.name)).join('')}</select>`)}
      ${field('المبلغ', inp('a', '', 'type="number" min="0.01" step="0.01" required'))}${field('التاريخ', `<input type="date" name="d" value="${today()}" max="${today()}">`)}
      ${field('الصندوق أو البنك', `<select name="acc">${accOpts(acc, a => a.parent_code === '1100', '1120')}</select>`)}${field('ملاحظة', inp('n', '', 'maxlength="200"'), 'wide')}
      <div class="wide" id="alp"></div></div>`, {
    ok: 'ترحيل', onOk: async f => { if (!f.p) throw new Error(tr('اختر الطرف')); if (!(+f.a > 0)) throw new Error(tr('أدخل المبلغ'));
      const docs = $$('[data-ad]:checked', d).map(c => c.dataset.ad);
      const r = await db.rpc('payment_allocate', { p_company: S.cid, p_doc: { direction: dir, party: f.p, amount: +f.a, date: f.d, account: f.acc, note: blank(f.n), docs } });
      toast(tr('سُجّلت السندات') + ': ' + r.map(x => (x.doc || tr('دفعة مقدمة')) + ' ' + money(x.amount)).join('، ')); route(); } });
  d.querySelector('[name=p]').onchange = async e => { const box = $('#alp', d); if (!e.target.value) { box.innerHTML = ''; return; }
    const docs = await db.get(dir === 'in' ? 'sales_invoices' : 'purchase_bills', { party_id: 'eq.' + e.target.value, status: 'eq.posted', order: 'date,created_at', select: 'id,no,date,total' });
    const paid = await paidMap(DOCS[dir === 'in' ? 'sales' : 'purchases'], docs.map(x => x.id)); const open = docs.map(x => Object.assign(x, { due: r2(n0(x.total) - n0(paid[x.id])) })).filter(x => x.due > 0.004);
    box.innerHTML = open.length ? `<label>${esc(tr('الفواتير المفتوحة (تُسدد الأقدم فالأحدث)'))}</label>` + tbl([{ t: '', h: x => `<input type="checkbox" data-ad="${x.id}" checked aria-label="${esc(x.no)}">` }, { t: 'الرقم', h: x => `<span class="num">${esc(x.no)}</span>` },
      { t: 'التاريخ', h: x => fdate(x.date) }, { t: 'المتبقي', r: 1, h: x => money(x.due) }], open) + `<p class="small">${esc(tr('إجمالي المتبقي'))}: <b class="num">${money(open.reduce((a, x) => a + x.due, 0))}</b> — ${esc(tr('ما يزيد يُسجّل دفعة مقدمة.'))}</p>`
      : `<p class="muted small">${esc(tr('لا توجد فواتير مفتوحة؛ يُسجّل المبلغ دفعة مقدمة.'))}</p>`;
    if (!d.querySelector('[name=a]').value && open.length) d.querySelector('[name=a]').value = r2(open.reduce((a, x) => a + x.due, 0)); };
}

/* ---------- «المصروفات المقدمة» ---------- */
VIEWS['#/prepaid'] = async page => {
  if (!can('je')) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للمالية.'))}</div>`; return; }
  const [rows, posts, acc, ccs] = await Promise.all([db.get('prepaid_schedules', Object.assign(C(), { order: 'created_at.desc' })), db.get('prepaid_postings', { select: 'schedule_id,amount' }).catch(() => []), accounts(), ccList().catch(() => [])]);
  const done = {}; posts.forEach(p => { const x = done[p.schedule_id] = done[p.schedule_id] || { n: 0, a: 0 }; x.n++; x.a += n0(p.amount); });
  const am = {}; acc.forEach(a => am[a.code] = a.name);
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('المصروفات المقدمة'))}</h1><div class="muted">${esc(tr('مصروف تدفعه مقدما لعدة أشهر (مثل إيجار سنة) يُسجّل في «مصروفات مدفوعة مقدما»، ثم يوزَّع على المصروف قيدا لكل شهر.'))}</div></div>
      <div class="row">${can('jepost') ? `<button class="btn" id="ppr">${esc(tr('ترحيل المستحق حتى اليوم'))}</button><button class="btn pri" id="ppn">${esc(tr('توزيع جديد'))}</button>` : ''}</div></div>
    ${tbl([{ t: 'البيان', h: s => `<b>${esc(s.name)}</b>` }, { t: 'حساب المصروف', h: s => esc(s.expense_account + ' ' + (am[s.expense_account] || '')) }, { t: 'الإجمالي', r: 1, h: s => money(s.total) },
      { t: 'من شهر', h: s => `<span class="num">${esc(String(s.start_month).slice(0, 7))}</span>` }, { t: 'الأشهر', r: 1, h: s => `<span class="num">${(done[s.id] || {}).n || 0} / ${s.months}</span>` },
      { t: 'المتبقي', r: 1, h: s => money(n0(s.total) - n0((done[s.id] || {}).a)) }, { t: 'الحالة', h: s => `<span class="badge ${s.status === 'active' ? 'info' : s.status === 'done' ? 'ok' : ''}">${esc(tr({ active: 'جارٍ', done: 'اكتمل', stopped: 'أُوقف' }[s.status]))}</span>` }], rows, { empty: 'لا توجد مصروفات مقدمة', onRow: true })}`;
  bindRows(page, rows, s => { if (s.status !== 'active' || !can('jepost')) return; confirmBox(tr('إيقاف التوزيع'), tr('يتوقف ترحيل الأشهر الباقية؛ ما رُحّل يبقى كما هو.'), tr('إيقاف')).then(async y => { if (y) { await db.rpc('prepaid_stop', { p_id: s.id }); route(); } }); });
  if ($('#ppr', page)) $('#ppr', page).onclick = () => busy($('#ppr', page), async () => { const n = await db.rpc('prepaid_run', { p_company: S.cid, p_through: today() }); toast(tr('رُحّل') + ' ' + n + ' ' + tr('قيد')); route(); });
  if ($('#ppn', page)) $('#ppn', page).onclick = () => modal(tr('توزيع مصروف مقدم'), `<div class="fg">${field('البيان', inp('n', '', 'maxlength="120" placeholder="' + esc(tr('إيجار المكتب 2027')) + '"'))}${field('المبلغ الإجمالي', inp('a', '', 'type="number" min="0.01" step="0.01"'))}
      ${field('حساب المصروف', `<select name="e">${accOpts(acc, a => a.type === 'exp', '5300')}</select>`)}${field('حساب المدفوع مقدما', `<select name="pp">${accOpts(acc, a => a.type === 'asset' && /^1[5-6]/.test(a.code), '1600')}</select>`)}
      ${field('يبدأ من شهر', `<input type="month" name="s" value="${today().slice(0, 7)}">`)}${field('عدد الأشهر', inp('m', 12, 'type="number" min="1" max="120"'))}
      ${ccs.length ? field('مركز التكلفة', `<select name="cc"><option value="">—</option>${ccs.map(c => opt(c.id, ccName(c))).join('')}</select>`) : ''}</div>
      <p class="muted small">${esc(tr('سجّل فاتورة الدفع نفسها على حساب «مصروفات مدفوعة مقدما»، وهذا التوزيع ينقل قسط كل شهر إلى المصروف.'))}</p>`,
    { onOk: async f => { await db.rpc('prepaid_create', { p_company: S.cid, p_doc: { name: f.n, amount: +f.a, expense: f.e, prepaid: f.pp, start: f.s + '-01', months: +f.m, cc: f.cc || null } }); toast(tr('تم الحفظ')); route(); } });
};

/* ---------- journal drafts (inside «القيود اليومية») ---------- */
const JD_ST = { draft: ['مسودة', ''], pending: ['بانتظار الاعتماد', 'warn'], rejected: ['مرفوضة', 'bad'], recurring: ['متكرر', 'info'], posted: ['مُرحّل', 'ok'], ended: ['متوقف', ''] };
async function journalDrafts(box, acc) {
  if (can('jepost')) await db.rpc('jd_run_due', { p_company: S.cid }).catch(() => 0);
  const rows = await db.get('journal_drafts', Object.assign(C(), { status: 'in.(draft,pending,rejected,recurring)', order: 'date.desc' })).catch(() => []);
  box.innerHTML = `<div class="row" style="justify-content:space-between;align-items:center;flex-wrap:wrap;gap:6px"><h2 style="margin:0">${esc(tr('المسودات والاعتماد والقيود المتكررة'))}</h2>
      <div class="row" style="gap:6px"><button class="btn sm" id="jdx">${esc(tr('استيراد قيود من Excel'))}</button><button class="btn sm pri" id="jdn">${esc(tr('مسودة قيد'))}</button></div></div>` +
    (rows.length ? tbl([{ t: 'التاريخ', h: j => fdate(j.date) }, { t: 'البيان', h: j => esc(j.memo) + (j.note ? `<div class="small bad">${esc(j.note)}</div>` : '') }, { t: 'المبلغ', r: 1, h: j => money(j.lines.reduce((a, l) => a + n0(l.d), 0)) },
      { t: 'الحالة', h: j => `<span class="badge ${JD_ST[j.status][1]}">${esc(tr(JD_ST[j.status][0]))}</span>` + (j.reverse_on ? ` <span class="small muted">${esc(tr('يُعكس'))} ${fdate(j.reverse_on)}</span>` : '') + (j.next_run ? ` <span class="small muted">${esc(tr('التالي'))} ${fdate(j.next_run)}</span>` : '') }], rows, { onRow: true })
      : `<p class="muted small">${esc(tr('لا توجد مسودات. أنشئ مسودة ليعتمدها شخص آخر قبل ترحيلها، أو قيدا متكررا شهريا، أو قيدا يُعكس تلقائيا.'))}</p>`);
  $('#jdn', box).onclick = () => jdForm(null, acc);
  $('#jdx', box).onclick = () => jdImport(acc);
  bindRows(box, rows, j => jdView(j, acc));
}
function jdForm(j, acc) {
  const ls = j ? j.lines : [{}, {}], row = (l, i) => `<tr><td><select data-l="a" style="min-width:200px" aria-label="${esc(tr('الحساب'))} ${i + 1}"><option value="">—</option>${accOpts(acc, null, l.a)}</select></td>
    <td><input data-l="d" type="number" min="0" step="0.01" value="${l.d || ''}" style="width:110px"></td><td><input data-l="c" type="number" min="0" step="0.01" value="${l.c || ''}" style="width:110px"></td></tr>`;
  const d = modal(j ? tr('تعديل مسودة القيد') : tr('مسودة قيد'), `<div class="fg">${field('التاريخ', `<input type="date" name="d" value="${esc(j ? j.date : today())}">`)}${field('البيان', inp('m', j && j.memo, 'maxlength="200" required'))}
      ${field('عكس تلقائي في تاريخ (اختياري)', `<input type="date" name="r" value="${esc(j && j.reverse_on || '')}">`)}${field('يتكرر', `<select name="rc">${opt('', tr('لا'), j && j.recur_months)}${[1, 3, 6, 12].map(m => opt(m, tr('كل') + ' ' + m + ' ' + tr('شهر'), j && j.recur_months)).join('')}</select>`)}
      <div class="wide"><div class="tw"><table class="lines"><thead><tr><th>${esc(tr('الحساب'))}</th><th>${esc(tr('مدين'))}</th><th>${esc(tr('دائن'))}</th></tr></thead><tbody id="jdl">${ls.map(row).join('')}</tbody>
        <tfoot><tr><td>${esc(tr('الفرق'))}</td><td colspan="2" id="jdf" class="num"></td></tr></tfoot></table></div><button type="button" class="btn sm" id="jda" style="margin-top:6px">+ ${esc(tr('سطر'))}</button></div></div>
      <div class="row" style="gap:6px;margin-top:8px"><button type="button" class="btn pri" id="jds">${esc(tr('إرسال للاعتماد'))}</button></div>`, { ok: 'حفظ كمسودة', wide: true, onOk: f => save(f, false) });
  const lines = () => $$('#jdl tr', d).map(tr => ({ a: $('[data-l=a]', tr).value, d: +$('[data-l=d]', tr).value || 0, c: +$('[data-l=c]', tr).value || 0 })).filter(l => l.a && (l.d || l.c));
  const foot = () => { const ls2 = lines(), dd = r2(ls2.reduce((a, l) => a + l.d, 0)), cc = r2(ls2.reduce((a, l) => a + l.c, 0)); $('#jdf', d).innerHTML = `${money(dd)} / ${money(cc)} — ${dd === cc && dd > 0 ? `<span class="ok">${esc(tr('متوازن'))}</span>` : `<span class="bad">${money(r2(dd - cc))}</span>`}`; };
  const save = async (f, submit) => { await db.rpc('jd_save', { p_company: S.cid, p_id: j ? j.id : null, p_doc: { date: f.d, memo: f.m, reverse_on: f.r || null, recur: f.rc || null, lines: lines() }, p_submit: submit }); toast(submit ? tr('أُرسل للاعتماد') : tr('حُفظت المسودة')); route(); };
  $('#jda', d).onclick = () => { $('#jdl', d).insertAdjacentHTML('beforeend', row({}, $$('#jdl tr', d).length)); };
  $('#jdl', d).addEventListener('input', foot); $('#jdl', d).addEventListener('change', foot); foot();
  $('#jds', d).onclick = () => busy($('#jds', d), async () => { try { await save(formData($('#mform', d)), true); d.close(); } catch (e) { showErr($('#merr', d), e); } });
}
function jdView(j, acc) {
  const am = {}; acc.forEach(a => am[a.code] = a.name);
  const mine = j.created_by === S.session.user.id;
  const d = modal(j.memo, `<p>${fdate(j.date)} <span class="badge ${JD_ST[j.status][1]}">${esc(tr(JD_ST[j.status][0]))}</span></p>${tbl([{ t: 'الحساب', h: l => esc(l.a + ' — ' + (am[l.a] || '')) }, { t: 'مدين', r: 1, h: l => n0(l.d) ? money(l.d) : '' }, { t: 'دائن', r: 1, h: l => n0(l.c) ? money(l.c) : '' }], j.lines)}
    ${j.status === 'pending' && can('jepost') && (!mine || has('owner')) ? field('ملاحظة (إلزامية عند الرفض)', '<textarea name="rn" rows="2"></textarea>') + `<div class="row" style="gap:6px;margin-top:8px"><button type="button" class="btn pri" id="jdok">${esc(tr('اعتماد وترحيل'))}</button><button type="button" class="btn danger" id="jdno">${esc(tr('رفض'))}</button></div>` : ''}
    ${j.status === 'pending' && mine && !has('owner') ? `<p class="muted small">${esc(tr('ينتظر اعتماد شخص آخر لديه صلاحية ترحيل القيود.'))}</p>` : ''}
    <div class="row" style="gap:6px;margin-top:8px">${['draft', 'rejected', 'pending'].includes(j.status) ? `<button type="button" class="btn" id="jded">${esc(tr('تعديل'))}</button>` : ''}<button type="button" class="btn danger sm" id="jddel">${esc(tr(j.status === 'recurring' ? 'إيقاف التكرار' : 'حذف'))}</button></div>`);
  const dec = ok => async () => { try { await db.rpc('jd_approve', { p_id: j.id, p_ok: ok, p_note: (d.querySelector('[name=rn]') || {}).value || '' }); d.close(); toast(ok ? tr('رُحّل القيد') : tr('رُفضت')); route(); } catch (e) { showErr($('#merr', d), e); } };
  if ($('#jdok', d)) { $('#jdok', d).onclick = dec(true); $('#jdno', d).onclick = dec(false); }
  if ($('#jded', d)) $('#jded', d).onclick = () => { d.close(); jdForm(j, acc); };
  $('#jddel', d).onclick = async () => { try { await db.rpc('jd_delete', { p_id: j.id }); d.close(); toast(tr('تم')); route(); } catch (e) { showErr($('#merr', d), e); } };
}
// Excel: date, reference (groups lines into one entry), account code, debit, credit, memo
function jdImport(acc) {
  const d = modal(tr('استيراد قيود من Excel'), `<ol class="small" style="padding-inline-start:18px;margin-top:0"><li>${esc(tr('نزّل القالب واملأ سطرا لكل طرف قيد: التاريخ، رقم مرجعي يجمع أسطر القيد الواحد، رمز الحساب، مدين، دائن، البيان.'))}</li>
      <li>${esc(tr('ارفع الملف: يصير كل قيد مسودة بانتظار الاعتماد.'))}</li></ol><div class="row"><button type="button" class="btn" id="jtp">${esc(tr('تنزيل القالب'))}</button><label class="btn pri" style="margin:0;color:var(--prim-ink)">${esc(tr('اختيار الملف'))}<input type="file" id="jif" accept=".xlsx,.csv" hidden></label></div><div id="jip"></div>`, { wide: true });
  $('#jtp', d).onclick = () => { const a = document.createElement('a'); a.href = URL.createObjectURL(templateXlsx([[tr('التاريخ'), tr('المرجع'), tr('رمز الحساب'), tr('مدين'), tr('دائن'), tr('البيان')], [today(), 'J1', '5300', '1000', '', tr('إيجار')], [today(), 'J1', '1120', '', '1000', tr('إيجار')]])); a.download = 'waad-journal-import.xlsx'; a.click(); };
  $('#jif', d).onchange = async ev => { const file = ev.target.files[0]; if (!file) return; const box = $('#jip', d);
    try { const { body } = await readSheetFile(file), codes = new Set(acc.filter(a => !a.is_header).map(a => a.code)), g = {};
      const dt = v => { if (typeof v === 'number') return new Date(Date.UTC(1899, 11, 30) + v * 864e5).toISOString().slice(0, 10); const m = /(\d{4})-(\d{1,2})-(\d{1,2})/.exec(String(v || '')); return m ? `${m[1]}-${m[2].padStart(2, '0')}-${m[3].padStart(2, '0')}` : null; };
      const bad = [];
      body.forEach(({ r, no }) => { const day = dt(r[0]), ref = String(r[1] || '').trim(), a = String(r[2] == null ? '' : r[2]).trim().replace(/\.0+$/, ''), dd = +r[3] || 0, cc = +r[4] || 0;
        if (!day || !ref || !codes.has(a) || (!dd && !cc)) { bad.push(no); return; }
        const k = ref + '|' + day; (g[k] = g[k] || { date: day, memo: String(r[5] || ref).trim() || ref, lines: [] }).lines.push({ a, d: dd, c: cc }); });
      const docs = Object.values(g), unb = docs.filter(x => r2(x.lines.reduce((a, l) => a + l.d, 0)) !== r2(x.lines.reduce((a, l) => a + l.c, 0)));
      box.innerHTML = `<div class="note" style="margin-top:10px">${esc(tr('قيود'))}: <b class="num">${docs.length}</b>${bad.length ? ` · ${esc(tr('أسطر فيها خطأ'))}: <span class="num">${bad.slice(0, 15).join('، ')}</span>` : ''}${unb.length ? ` · <span class="bad">${esc(tr('قيود غير متوازنة'))}: ${unb.length}</span>` : ''}</div>
        ${docs.length && !unb.length && !bad.length ? `<button type="button" class="btn pri" id="jigo">${esc(tr('إنشاء المسودات وإرسالها للاعتماد'))}</button>` : ''}`;
      if ($('#jigo', d)) $('#jigo', d).onclick = () => busy($('#jigo', d), async () => { for (const x of docs) await db.rpc('jd_save', { p_company: S.cid, p_id: null, p_doc: x, p_submit: true }); toast(tr('أُرسل للاعتماد') + ' · ' + docs.length); d.close(); route(); });
    } catch (e) { box.innerHTML = `<div class="err">${esc(e.message)}</div>`; } };
}

/* ---------- «إقفال الشهر» ---------- */
const MC_K = { drafts: ['قيود بانتظار الاعتماد أو مسودات', '#/journal'], bank: ['مطابقة حسابات البنك مع الكشف', '#/bankmatch'], depreciation: ['ترحيل إهلاك الأصول للشهر', '#/assets'],
  prepaid: ['ترحيل أقساط المصروفات المقدمة', '#/prepaid'], payroll: ['اعتماد مسير رواتب الشهر', '#/payroll'], zatca: ['إرسال كل الفواتير لزاتكا بنجاح', '#/sales'] };
VIEWS['#/monthclose'] = async (page, arg, q) => {
  if (!can('reports')) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للمالية.'))}</div>`; return; }
  const def = new Date(Date.now() - 20 * 864e5).toISOString().slice(0, 7), month = q.get('m') || def;
  if (can('jepost')) await db.rpc('jd_run_due', { p_company: S.cid }).catch(() => 0);
  const st = await db.rpc('month_close_status', { p_company: S.cid, p_month: month + '-01' });
  const all = st.checks.every(c => c.ok), closed = st.closed_through && st.closed_through >= st.through;
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('إقفال الشهر'))}</h1><div class="muted">${esc(tr('قبل إقفال الشهر تأكد من هذه الخطوات؛ بعد الإقفال لا يُسجّل أي قيد بتاريخ داخل الشهر.'))}</div></div>
      <input type="month" id="mcm" value="${esc(month)}" max="${today().slice(0, 7)}" style="width:auto" aria-label="${esc(tr('الشهر'))}"></div>
    <div class="card">${st.checks.map(c => `<div class="row" style="justify-content:space-between;align-items:center;padding:10px 0;border-bottom:1px solid var(--line3)">
        <span>${c.na ? '<span class="muted">—</span>' : c.ok ? '<span class="ok">✓</span>' : '<span class="bad">✕</span>'} ${esc(tr(MC_K[c.k][0]))}${!c.ok && c.n ? ` <span class="badge bad num">${c.n}</span>` : ''}${c.na ? ` <span class="muted small">${esc(tr('لا ينطبق'))}</span>` : ''}</span>
        ${!c.ok ? `<a class="btn sm" href="${MC_K[c.k][1]}">${esc(tr('معالجة'))}</a>` : ''}</div>`).join('')}
      <div style="margin-top:14px">${closed ? `<span class="badge ok">${esc(tr('الشهر مقفل'))}</span>` : has('owner', 'admin', 'finance') ? `<button class="btn ${all ? 'pri' : ''}" id="mcgo">${esc(tr('إقفال الفترة حتى'))} <span class="num">${esc(st.through)}</span></button>${all ? '' : ` <span class="muted small">${esc(tr('توجد خطوات لم تكتمل'))}</span>`}` : ''}</div></div>`;
  $('#mcm', page).onchange = e => location.hash = '#/monthclose?m=' + e.target.value;
  if ($('#mcgo', page)) $('#mcgo', page).onclick = async () => {
    if (!all && !await confirmBox(tr('إقفال الشهر'), tr('توجد خطوات لم تكتمل. هل تريد الإقفال رغم ذلك؟'), tr('إقفال'))) return;
    try { await db.rpc('period_close', { p_company: S.cid, p_through: st.through }); toast(tr('أُقفل الشهر')); route(); } catch (e) { toast(e.message); } };
};
