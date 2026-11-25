'use strict';
/* ===== finance, phase two (0122): zakat estimate, loans and letters of guarantee, VAT return drill-down, budget warnings ===== */

/* ---------- «الزكاة التقديرية» ---------- */
const ZK_F = [
  ['equity', 'حقوق الملكية وما في حكمها (آخر السنة)', 'م23/1 — رأس المال والاحتياطيات والأرباح المبقاة وربح السنة؛ والمخصصات (عدا نهاية الخدمة والإجازات) م24.'],
  ['liabilities', 'الالتزامات غير المتداولة', 'م29 — مثل القروض طويلة الأجل ومخصص نهاية الخدمة؛ تضاف في حدود الأصول المحسومة فقط (م23/2).'],
  ['deducted', 'الأصول المحسومة', 'م26 — صافي الأصول الثابتة، والاستثمارات في منشآت محلية خاضعة للزكاة، والأصول غير الملموسة، والودائع النظامية…'],
  ['assets', 'إجمالي الأصول', 'لحساب الأصول غير المحسومة عند تطبيق الحد الأدنى (م27/2).'],
  ['profit_book', 'صافي الربح الدفتري للسنة', 'من قائمة الدخل قبل الزكاة.'],
  ['profit_adj', 'صافي الربح المعدّل', 'الربح الدفتري بعد التعديلات الزكوية (مثل المخصصات غير المستخدمة)؛ الفرق بينهما يضاف للوعاء (م23/3).']];
const ZK_RULE = { base: 'الوعاء = الإضافات − الحسميات', cap: 'طُبّق الحد الأعلى: حقوق الملكية + فرق الربح (م28/1)', min: 'الوعاء أقل من صافي الربح المعدّل: طُبّقت م27/2', none: 'لا وعاء: الوعاء سالب ولا يوجد ربح معدّل (م27/3)' };
VIEWS['#/zakat'] = async (page, arg, q) => {
  if (!can('reports')) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للمالية.'))}</div>`; return; }
  const y = new Date().getFullYear() - 1, from = q.get('f') || `${y}-01-01`, to = q.get('t') || `${y}-12-31`;
  const inp0 = await db.rpc('zakat_inputs', { p_company: S.cid, p_from: from, p_to: to });
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الزكاة التقديرية'))}</h1><div class="muted">${esc(tr('تقدير استرشادي لزكاة المنشأة من دفاترها وفق اللائحة التنفيذية لجباية الزكاة (1445هـ). عدّل أي رقم قبل الحساب؛ الإقرار الرسمي يُقدَّم في بوابة هيئة الزكاة والضريبة والجمارك.'))}</div></div>
      <div class="row" style="gap:6px"><input type="date" id="zf" value="${esc(from)}" aria-label="${esc(tr('بداية السنة المالية'))}" style="width:auto"><input type="date" id="zt" value="${esc(to)}" aria-label="${esc(tr('نهاية السنة المالية'))}" style="width:auto"></div></div>
    <div class="card"><h2>${esc(tr('عناصر الوعاء'))}</h2><form id="zform" class="fg" novalidate>${ZK_F.map(([k, t, h]) => field(t, inp(k, inp0[k], 'type="number" step="0.01"') + `<div class="small muted">${esc(tr(h))}</div>`)).join('')}
      ${field('عدد أيام السنة المالية', inp('days', inp0.days, 'type="number" min="1" max="800"') + `<div class="small muted">${esc(tr('م15: النسبة 2.5% للسنة الهجرية؛ وإذا اختلفت السنة المالية تُحسب بالأيام الفعلية = (2.5% ÷ 354) × عدد الأيام.'))}</div>`)}</form>
      <button class="btn pri" id="zgo" style="margin-top:8px">${esc(tr('احسب الزكاة'))}</button></div>
    <div id="zres"></div>
    <p class="muted small">${esc(tr('المصدر: اللائحة التنفيذية لجباية الزكاة الصادرة عام 1445هـ (المواد 15، 23، 24، 26، 27، 28، 29). هذا التقدير لا يغني عن مراجعة محاسب قانوني، ولا يشمل الأنشطة التمويلية والتأمين والصناديق التي لها أحكام خاصة.'))}
      <a href="https://www.uqn.gov.sa/details?p=24722" target="_blank" rel="noopener">${esc(tr('نص اللائحة'))}</a></p>`;
  const go = () => { location.hash = `#/zakat?f=${$('#zf', page).value}&t=${$('#zt', page).value}`; };
  $('#zf', page).onchange = go; $('#zt', page).onchange = go;
  $('#zgo', page).onclick = () => busy($('#zgo', page), async () => {
    const f = formData($('#zform', page)), p = {}; ZK_F.forEach(([k]) => p[k] = +f[k] || 0); p.days = +f.days || 354;
    const r = await db.rpc('zakat_calc', { p });
    const row = (t, v, b) => `<tr><td>${b ? '<b>' : ''}${esc(tr(t))}${b ? '</b>' : ''}</td><td class="r num">${b ? '<b>' : ''}${v}${b ? '</b>' : ''}</td></tr>`;
    $('#zres', page).innerHTML = `<div class="card"><h2>${esc(tr('النتيجة'))}</h2><div class="tw"><table><tbody>
        ${row('حقوق الملكية', money(p.equity))}${row('الالتزامات المضافة (في حدود الأصول المحسومة)', money(r.liab_added))}${row('فرق الربح المعدّل عن الدفتري', money(r.diff))}
        ${row('الأصول المحسومة', (p.deducted ? '−' : '') + money(p.deducted))}${row('الوعاء قبل الحدود', money(r.base_before))}${row('الحد الأعلى (م28)', money(r.cap))}
        ${row('الوعاء الزكوي', money(r.base), 1)}${row('النسبة', (r.rate * 100).toFixed(4) + '% · ' + r.days + ' ' + tr('يوما'))}${row('الزكاة التقديرية', money(r.zakat), 1)}</tbody></table></div>
      <p class="small">${esc(tr(ZK_RULE[r.rule]))}</p>
      ${n0(inp0.posted) ? `<p class="small muted">${esc(tr('سبق تسجيل مصروف زكاة في هذه السنة'))}: <span class="num">${money(inp0.posted)}</span></p>` : ''}
      ${can('jepost') && n0(r.zakat) > 0 ? `<button class="btn" id="zpost">${esc(tr('تسجيل مخصص الزكاة في الدفاتر'))}</button>` : ''}</div>`;
    if ($('#zpost', page)) $('#zpost', page).onclick = () => modal(tr('مخصص الزكاة'), `<p class="small">${esc(tr('قيد: من ح/ مصروف الزكاة (5960) إلى ح/ مخصص الزكاة (2350).'))}</p><div class="fg">${field('التاريخ', `<input type="date" name="d" value="${esc(to)}">`)}${field('المبلغ', inp('a', r.zakat, 'type="number" min="0.01" step="0.01"'))}</div>`,
      { ok: 'ترحيل', onOk: async x => { await db.rpc('zakat_post', { p_company: S.cid, p_date: x.d, p_amount: +x.a, p_memo: tr('مخصص الزكاة التقديري') + ' ' + to.slice(0, 4) }); toast(tr('تم الترحيل')); route(); } });
  });
};

/* ---------- «القروض وخطابات الضمان» ---------- */
const LG_T = { bid: 'ابتدائي (دخول منافسة)', performance: 'حسن تنفيذ', advance: 'دفعة مقدمة', other: 'أخرى' };
VIEWS['#/facilities'] = async page => {
  if (!(can('je') || can('reports'))) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للمالية.'))}</div>`; return; }
  const [rows, inst, al, acc, prjs] = await Promise.all([db.get('bank_facilities', Object.assign(C(), { order: 'start_date.desc' })), db.get('facility_instalments', Object.assign(C(), { order: 'n' })),
    db.rpc('facility_alerts', { p_company: S.cid }), accounts(), modOn('proj') ? db.get('projects', Object.assign(C(), { select: 'id,no,name', order: 'no' })).catch(() => []) : []]);
  const loans = rows.filter(r => r.kind === 'loan'), lgs = rows.filter(r => r.kind === 'lg'), banks = acc.filter(a => a.parent_code === '1100' && !a.is_header && a.code !== '1110');
  const left = f => inst.filter(i => i.facility_id === f.id && !i.paid_on).reduce((a, i) => a + n0(i.principal), 0);
  const nxt = f => inst.find(i => i.facility_id === f.id && !i.paid_on);
  const st = { active: ['قائم', 'info'], closed: ['مُسدّد', 'ok'], released: ['مُفرج عنه', 'ok'] };
  const alerts = [...al.instalments.map(i => `<li>${esc(tr(i.overdue ? 'قسط متأخر' : 'قسط قريب'))}: ${esc(i.bank)}${i.ref ? ' ' + esc(i.ref) : ''} — ${esc(tr('القسط'))} <span class="num">${i.n}</span> · ${fdate(i.due)} · <b class="num">${money(i.amount)}</b></li>`),
    ...al.guarantees.map(g => `<li>${esc(tr(g.days < 0 ? 'خطاب ضمان منتهٍ ولم يُفرج عنه' : 'خطاب ضمان ينتهي قريبا'))}: ${esc(g.bank)} — ${esc(g.beneficiary || '')} · ${fdate(g.expiry)} (<span class="num">${g.days}</span> ${esc(tr('يوما'))})</li>`)];
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('القروض وخطابات الضمان'))}</h1><div class="muted">${esc(tr('جدول أقساط كل قرض (أصل وربح) وقيده عند السداد، وخطابات الضمان بغطائها النقدي وتنبيه قبل انتهائها بـ30 يوما.'))}</div></div>
      <div class="row">${can('jepost') ? `<button class="btn" id="fnl">${esc(tr('خطاب ضمان جديد'))}</button><button class="btn pri" id="fnn">${esc(tr('قرض جديد'))}</button>` : ''}</div></div>
    <div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(170px,1fr));margin-bottom:12px"><div class="card"><div class="muted small">${esc(tr('أصل القروض المتبقي'))}</div><b class="num">${money(loans.filter(f => f.status === 'active').reduce((a, f) => a + left(f), 0))}</b></div><div class="card"><div class="muted small">${esc(tr('أقساط خلال 30 يوما'))}</div><b class="num">${money(inst.filter(i => !i.paid_on && i.due <= addDays(today(), 30)).reduce((a, i) => a + n0(i.principal) + n0(i.profit), 0))}</b></div><div class="card"><div class="muted small">${esc(tr('خطابات ضمان قائمة'))}</div><b class="num">${money(lgs.filter(f => f.status === 'active').reduce((a, f) => a + n0(f.amount), 0))}</b> <span class="small muted">(${lgs.filter(f => f.status === 'active').length})</span></div></div>
    ${alerts.length ? `<div class="note warn"><b>${esc(tr('تنبيهات'))}</b><ul style="margin:6px 0 0;padding-inline-start:18px">${alerts.join('')}</ul></div>` : ''}
    <div class="card"><h2>${esc(tr('القروض'))}</h2><div id="fl">${tbl([{ t: 'البنك', h: f => `<b>${esc(f.bank)}</b>${f.ref ? ` <span class="num small muted">${esc(f.ref)}</span>` : ''}` }, { t: 'المبلغ', r: 1, h: f => money(f.amount) },
      { t: 'الربح السنوي', r: 1, h: f => `<span class="num">${+f.rate}%</span>` }, { t: 'الأقساط', r: 1, h: f => `<span class="num">${inst.filter(i => i.facility_id === f.id && i.paid_on).length} / ${f.months}</span>` },
      { t: 'المتبقي من الأصل', r: 1, h: f => money(left(f)) }, { t: 'القسط القادم', h: f => { const i = nxt(f); return i ? `${fdate(i.due)} · <span class="num">${money(n0(i.principal) + n0(i.profit))}</span>` : '—'; } },
      { t: 'الحالة', h: f => `<span class="badge ${st[f.status][1]}">${esc(tr(st[f.status][0]))}</span>` }], loans, { empty: 'لا توجد قروض', onRow: true })}</div></div>
    <div class="card"><h2>${esc(tr('خطابات الضمان'))}</h2><div id="fg">${tbl([{ t: 'البنك', h: f => `<b>${esc(f.bank)}</b>${f.ref ? ` <span class="num small muted">${esc(f.ref)}</span>` : ''}` }, { t: 'النوع', h: f => esc(tr(LG_T[f.lg_type] || '')) },
      { t: 'المستفيد', h: f => esc(f.beneficiary || '') }, { t: 'المبلغ', r: 1, h: f => money(f.amount) }, { t: 'الغطاء النقدي', r: 1, h: f => money(f.margin) },
      { t: 'ينتهي', h: f => `${fdate(f.expiry)}${f.status === 'active' && f.expiry < today() ? ` <span class="badge bad">${esc(tr('منتهٍ'))}</span>` : ''}` },
      { t: 'الحالة', h: f => `<span class="badge ${st[f.status][1]}">${esc(tr(st[f.status][0]))}</span>` }], lgs, { empty: 'لا توجد خطابات ضمان', onRow: true })}</div></div>`;
  const bankSel = sel => `<select name="acc">${banks.map(a => opt(a.code, a.code + ' — ' + ((LANG === 'en' && a.name_en) || a.name), sel)).join('')}</select>`;
  bindRows($('#fl', page), loans, f => {
    const is = inst.filter(i => i.facility_id === f.id), first = is.find(i => !i.paid_on);
    const d = modal(f.bank + (f.ref ? ' ' + f.ref : ''), `<p class="small">${money(f.amount)} · ${+f.rate}% · ${f.months} ${esc(tr('شهرا'))} · ${esc(tr(f.method === 'flat' ? 'ربح ثابت على أصل القرض' : 'أقساط متساوية (ربح على الرصيد المتناقص)'))}</p>
      ${tbl([{ t: '#', h: i => `<span class="num">${i.n}</span>` }, { t: 'الاستحقاق', h: i => fdate(i.due) }, { t: 'الأصل', r: 1, h: i => money(i.principal) }, { t: 'الربح', r: 1, h: i => money(i.profit) },
        { t: 'القسط', r: 1, h: i => money(n0(i.principal) + n0(i.profit)) },
        { t: '', h: i => i.paid_on ? `<span class="badge ok">${esc(tr('مدفوع'))} ${fdate(i.paid_on)}</span>` : first && i.id === first.id && can('jepost') ? `<button type="button" class="btn sm pri" data-pay="${i.id}">${esc(tr('سداد'))}</button>` : '' }], is)}
      <p class="muted small">${esc(tr('عند السداد: من ح/ القروض (2600) بالأصل ومن ح/ تكلفة التمويل (5800) بالربح، إلى ح/ البنك.'))}</p>`, { wide: true });
    $$('[data-pay]', d).forEach(b => b.onclick = () => { const i = is.find(x => String(x.id) === b.dataset.pay);
      modal(tr('سداد قسط'), `<p>${esc(tr('القسط'))} <span class="num">${i.n}</span> · <b class="num">${money(n0(i.principal) + n0(i.profit))}</b></p><div class="fg">${field('تاريخ السداد', `<input type="date" name="d" value="${esc(today())}">`)}${field('من حساب', bankSel(f.account_code))}</div>`,
        { ok: 'سداد وترحيل', onOk: async x => { await db.rpc('loan_pay', { p_inst: i.id, p_date: x.d, p_account: x.acc }); toast(tr('تم الترحيل')); route(); } }); });
  });
  bindRows($('#fg', page), lgs, f => {
    if (f.status !== 'active' || !can('jepost')) return;
    const d = modal(tr('خطاب ضمان') + ' — ' + f.bank, `<p class="small">${esc(f.beneficiary || '')} · ${money(f.amount)} · ${esc(tr('ينتهي'))} ${fdate(f.expiry)}</p>
      <div class="fg">${field('تاريخ الانتهاء الجديد', `<input type="date" name="e" min="${esc(f.expiry)}">`)}${field('عمولة التمديد (اختياري)', inp('fee', '', 'type="number" min="0" step="0.01"'))}</div>
      <div class="row" style="gap:6px;margin-top:8px"><button type="button" class="btn pri" id="lgx">${esc(tr('تمديد'))}</button><button type="button" class="btn" id="lgr">${esc(tr('إفراج واسترداد الغطاء'))}</button></div>`);
    $('#lgx', d).onclick = () => busy($('#lgx', d), async () => { try { await db.rpc('lg_action', { p_id: f.id, p_doc: { do: 'extend', expiry: $('[name=e]', d).value, fee: +$('[name=fee]', d).value || 0 } }); d.close(); toast(tr('تم')); route(); } catch (e) { showErr($('#merr', d), e); } });
    $('#lgr', d).onclick = () => busy($('#lgr', d), async () => { try { await db.rpc('lg_action', { p_id: f.id, p_doc: { do: 'release', date: today() } }); d.close(); toast(tr('تم')); route(); } catch (e) { showErr($('#merr', d), e); } });
  });
  if ($('#fnn', page)) $('#fnn', page).onclick = () => {
    const d = modal(tr('قرض جديد'), `<div class="fg">${field('البنك', inp('bank', '', 'maxlength="100" required'))}${field('رقم العقد (اختياري)', inp('ref', '', 'maxlength="60"'))}
      ${field('مبلغ القرض', inp('amount', '', 'type="number" min="1" step="0.01"'))}${field('نسبة الربح السنوية %', inp('rate', '', 'type="number" min="0" max="100" step="0.01"'))}
      ${field('عدد الأشهر', inp('months', 12, 'type="number" min="1" max="360"'))}${field('طريقة الأقساط', `<select name="method">${opt('annuity', tr('أقساط متساوية (ربح على الرصيد المتناقص)'))}${opt('flat', tr('ربح ثابت على أصل القرض (مرابحة)'))}</select>`)}
      ${field('تاريخ الاستلام', `<input type="date" name="start" value="${esc(today())}">`)}${field('حساب البنك', bankSel('1120'))}
      ${field('', `<label class="row" style="gap:6px"><input type="checkbox" name="received" checked> ${esc(tr('سجّل استلام المبلغ في البنك الآن'))}</label>`)}</div><div id="lsch"></div>`,
      { wide: true, onOk: async x => { await db.rpc('loan_create', { p_company: S.cid, p_doc: { bank: x.bank, ref: x.ref, amount: +x.amount, rate: +x.rate || 0, months: +x.months, method: x.method, start: x.start, account: x.acc, received: !!x.received } }); toast(tr('تم الحفظ')); route(); } });
    const prev = async () => { const x = formData($('#mform', d)); if (!(+x.amount > 0 && +x.months > 0)) { $('#lsch', d).innerHTML = ''; return; }
      try { const s = await db.rpc('loan_schedule', { p_amount: +x.amount, p_rate: +x.rate || 0, p_months: +x.months, p_method: x.method, p_start: x.start || today() });
        const tp = s.reduce((a, r) => a + n0(r.profit), 0);
        $('#lsch', d).innerHTML = `<p class="small">${esc(tr('القسط الأول'))} <b class="num">${money(n0(s[0].principal) + n0(s[0].profit))}</b> · ${esc(tr('إجمالي الربح'))} <b class="num">${money(tp)}</b> · ${esc(tr('إجمالي السداد'))} <b class="num">${money(+x.amount + tp)}</b></p>`; } catch (e) { $('#lsch', d).innerHTML = ''; } };
    $('#mform', d).addEventListener('change', prev);
  };
  if ($('#fnl', page)) $('#fnl', page).onclick = () => modal(tr('خطاب ضمان جديد'), `<div class="fg">${field('البنك', inp('bank', '', 'maxlength="100" required'))}${field('رقم الخطاب', inp('ref', '', 'maxlength="60"'))}
      ${field('النوع', `<select name="type">${Object.keys(LG_T).map(k => opt(k, tr(LG_T[k]))).join('')}</select>`)}${field('المستفيد', inp('beneficiary', '', 'maxlength="150"'))}
      ${field('مبلغ الخطاب', inp('amount', '', 'type="number" min="1" step="0.01"'))}${field('نسبة الغطاء النقدي %', inp('margin_pct', 10, 'type="number" min="0" max="100" step="0.01"'))}
      ${field('عمولة الإصدار', inp('fee', '', 'type="number" min="0" step="0.01"'))}${field('حساب البنك', bankSel('1120'))}
      ${field('تاريخ الإصدار', `<input type="date" name="start" value="${esc(today())}">`)}${field('تاريخ الانتهاء', `<input type="date" name="expiry">`)}
      ${prjs.length ? field('المشروع (اختياري)', `<select name="project"><option value="">—</option>${prjs.map(x => opt(x.id, x.no + ' — ' + x.name)).join('')}</select>`) : ''}</div>
      <p class="muted small">${esc(tr('الغطاء: من ح/ تأمينات خطابات الضمان (1810) إلى ح/ البنك، ويعود للبنك عند الإفراج. العمولة على ح/ تكلفة التمويل (5800).'))}</p>`,
    { wide: true, onOk: async x => { const lid = await db.rpc('lg_create', { p_company: S.cid, p_doc: { bank: x.bank, ref: x.ref, type: x.type, beneficiary: x.beneficiary, amount: +x.amount, margin_pct: +x.margin_pct || 0, fee: +x.fee || 0, account: x.acc, start: x.start, expiry: x.expiry } });
      if (x.project) await db.rpc('lg_set_project', { p_id: lid, p_project: x.project }); toast(tr('تم الحفظ')); route(); } });
};

/* ---------- VAT return: the documents behind a figure ---------- */
const VAT_BOX = { sales: 'المبيعات الخاضعة للنسبة الأساسية', sales_zero: 'المبيعات الصفرية', purch: 'المشتريات الخاضعة للنسبة الأساسية', purch_zero: 'المشتريات الصفرية' };
async function vatDocs(from, to, box) {
  const rows = await db.rpc('vat_docs', { p_company: S.cid, p_from: from, p_to: to, p_box: box });
  const K = { invoice: 'فاتورة', debit: 'إشعار مدين', bill: 'فاتورة مورد', credit: 'إشعار دائن' };
  const d = modal(tr(VAT_BOX[box]), `<p class="muted small">${fdate(from)} — ${fdate(to)} · ${rows.length} ${esc(tr('مستند'))}</p>` +
    tbl([{ t: 'النوع', h: r => esc(tr(K[r.kind])) }, { t: 'الرقم', h: r => `<span class="num">${esc(r.no)}</span>` }, { t: 'التاريخ', h: r => fdate(r.date) }, { t: 'الطرف', h: r => esc(r.party || '') },
      { t: 'المبلغ', r: 1, h: r => money(r.amount) }, { t: 'الضريبة', r: 1, h: r => money(r.vat) }], rows,
      { empty: 'لا توجد مستندات', onRow: true, foot: `<td colspan="4">${esc(tr('الإجمالي'))}</td><td class="r num">${money(rows.reduce((a, r) => a + n0(r.amount), 0))}</td><td class="r num">${money(rows.reduce((a, r) => a + n0(r.vat), 0))}</td>` }), { wide: true });
  bindRows(d, rows, r => { d.close(); location.hash = (box.startsWith('sales') ? '#/sales/' : '#/purchases/') + r.doc_id; });
}

/* ---------- budget warnings on a purchase order / a journal draft ---------- */
function budgetWarn(over) {
  if (!over || !over.length) return '';
  return `<div class="note warn"><b>${esc(tr('يتجاوز الموازنة'))}</b><ul style="margin:6px 0 0;padding-inline-start:18px">${over.map(o => `<li>${esc(o.account + ' ' + (o.name || ''))}${o.cc ? ' · ' + esc(o.cc) : ''}: ${esc(tr('الموازنة'))} <span class="num">${money(o.budget)}</span> · ${esc(tr('الصرف الفعلي'))} <span class="num">${money(o.actual)}</span> · ${esc(tr('بعد هذا'))} <b class="num bad">${money(o.after)}</b></li>`).join('')}</ul>
    ${S.company && S.company.budget_block ? `<p class="small bad" style="margin:6px 0 0">${esc(tr('منشأتك تمنع اعتماد ما يتجاوز الموازنة.'))}</p>` : ''}</div>`;
}
