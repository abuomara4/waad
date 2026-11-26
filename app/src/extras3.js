/* ===== third free batch (0156 finance, 0157 people and customers) ===== */

/* ----- 18. FX revaluation ----- */
VIEWS['#/fxreval'] = async page => {
  if (!can('je')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const [curs, done] = await Promise.all([db.get('currencies', { company_id: 'eq.' + S.cid, order: 'code' }), db.get('fx_revaluations', { company_id: 'eq.' + S.cid, order: 'date.desc', limit: 24 })]);
  const me = new Date(); me.setDate(0); const lastMonthEnd = me.toISOString().slice(0, 10);
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('إعادة تقييم العملات الأجنبية'))}</h1><div class="muted">${esc(tr('الفواتير المفتوحة بعملة أجنبية تُقيَّم بسعر آخر الشهر؛ يُسجَّل الفرق غير المحقق ويُعكس في اليوم التالي، فيبقى الفرق الفعلي عند السداد.'))}</div></div></div>
    ${curs.length ? `<div class="card"><div class="fg">${field('تاريخ التقييم', `<input type="date" id="fxd" value="${lastMonthEnd}" max="${today()}">`)}${curs.map(c => field(c.code + ' — ' + tr('سعر الصرف (ريال للوحدة)'), `<input type="number" step="0.000001" min="0" data-fx="${c.code}" value="${+c.rate}">`)).join('')}</div>
      <div class="row" style="gap:8px;margin-top:10px"><button class="btn" id="fxp">${esc(tr('معاينة'))}</button><button class="btn pri" id="fxg" disabled>${esc(tr('ترحيل إعادة التقييم'))}</button></div><div id="fxv" style="margin-top:12px"></div></div>`
      : `<div class="note">${esc(tr('لا توجد عملات أجنبية. أضفها من «العملات» أولا.'))} <a href="#/currencies">${esc(tr('العملات'))}</a></div>`}
    ${done.length ? `<div class="card"><h2>${esc(tr('عمليات سابقة'))}</h2>${tbl([{ t: 'التاريخ', h: x => fdate(x.date) }, { t: 'أرباح', r: 1, h: x => money(x.gain) }, { t: 'خسائر', r: 1, h: x => money(x.loss) }, { t: 'المستندات', r: 1, h: x => `<span class="num">${x.details.length}</span>` }], done, {})}</div>` : ''}`;
  if (!curs.length) return;
  const rates = () => Object.fromEntries($$('[data-fx]', page).map(i => [i.dataset.fx, +i.value]));
  $('#fxp', page).onclick = () => busy($('#fxp', page), async () => { try { const r = await db.rpc('fx_reval_preview', { p_company: S.cid, p_date: $('#fxd', page).value, p_rates: rates() });
    const g = r.filter(x => x.diff > 0).reduce((a, x) => a + n0(x.diff), 0), l = r.filter(x => x.diff < 0).reduce((a, x) => a - n0(x.diff), 0);
    $('#fxv', page).innerHTML = (r.length ? tbl([{ t: 'المستند', h: x => `${esc(tr(x.kind === 'sales' ? 'فاتورة مبيعات' : 'فاتورة مشتريات'))} <span class="num">${esc(x.no)}</span> <span class="small muted" data-nt>${esc(x.party)}</span>` },
      { t: 'المتبقي بالعملة', r: 1, h: x => `<span class="num">${moneyN(x.fx)} ${esc(x.currency)}</span>` }, { t: 'القيمة الحالية', r: 1, h: x => money(x.carrying) }, { t: 'بالسعر الجديد', r: 1, h: x => money(x.new) },
      { t: 'الفرق', r: 1, h: x => `<b class="${x.diff >= 0 ? 'ok' : 'bad'}">${money(x.diff)}</b>` }], r, {}) : `<p class="muted">${esc(tr('لا توجد فروق صرف على المستندات المفتوحة'))}</p>`)
      + (r.length ? `<p>${esc(tr('أرباح فروق صرف'))} <b class="ok">${money(g)}</b> · ${esc(tr('خسائر فروق صرف'))} <b class="bad">${money(l)}</b></p>` : '');
    $('#fxg', page).disabled = !r.length; } catch (e) { toast(e.message); } });
  $('#fxg', page).onclick = () => busy($('#fxg', page), async () => { try { await db.rpc('fx_revalue', { p_company: S.cid, p_date: $('#fxd', page).value, p_rates: rates() }); toast(tr('رُحّلت إعادة التقييم وعكسها')); route(); } catch (e) { toast(e.message); } });
};

/* ----- 19. cost allocation ----- */
VIEWS['#/allocation'] = async page => {
  if (!can('je')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const [rules, runs, acc, ccs] = await Promise.all([db.get('alloc_rules', { company_id: 'eq.' + S.cid, order: 'name' }), db.get('alloc_runs', { order: 'period.desc', limit: 200 }), accounts(), db.get('cost_centers', { company_id: 'eq.' + S.cid, order: 'code' })]);
  const cm = {}; ccs.forEach(c => cm[c.id] = (c.code ? c.code + ' — ' : '') + c.name); const am = {}; acc.forEach(a => am[a.code] = a.name); const exp = acc.filter(a => a.type === 'exp' && !a.is_header);
  const lastM = new Date(); lastM.setDate(0); const lm = lastM.toISOString().slice(0, 7);
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('توزيع المصروفات العامة'))}</h1><div class="muted">${esc(tr('مصروف مشترك (إيجار المقر، الكهرباء، الإدارة) يُنقل شهريا من مركز تكلفته إلى المراكز المستفيدة بنسب ثابتة.'))}</div></div><button class="btn pri" id="aln">+ ${esc(tr('قاعدة توزيع'))}</button></div>
    ${tbl([{ t: 'القاعدة', h: r => `<b data-nt>${esc(r.name)}</b>${r.active ? '' : ` <span class="badge">${esc(tr('موقوفة'))}</span>`}` }, { t: 'الحساب', h: r => `<span class="num">${esc(r.account_code)}</span> ${esc(am[r.account_code] || '')}` },
      { t: 'من مركز', h: r => esc(cm[r.source_cc] || tr('بدون مركز')) }, { t: 'إلى', h: r => r.targets.map(t => esc(cm[t.cc] || '') + ' ' + `<span class="num">${t.pct}%</span>`).join('، ') },
      { t: 'آخر توزيع', h: r => { const x = runs.find(u => u.rule_id === r.id); return x ? `${esc(x.period.slice(0, 7))} · ${money(x.amount)}` : '—'; } },
      { t: '', h: r => r.active ? `<button class="btn sm pri" data-alr="${r.id}">${esc(tr('توزيع شهر'))}</button>` : '' }], rules, { empty: 'لا توجد قواعد توزيع', onRow: true })}`;
  const trow = t => `<tr><td><select data-t="cc">${ccs.map(c => opt(c.id, cm[c.id], (t && t.cc) || '')).join('')}</select></td><td><input data-t="pct" type="number" min="0" max="100" step="0.01" value="${t ? t.pct : ''}" style="width:90px"></td><td><button type="button" class="btn sm" data-tx>×</button></td></tr>`;
  const form = r => { const d = modal(r ? tr('تعديل قاعدة التوزيع') : tr('قاعدة توزيع جديدة'), `<div class="fg">${field('اسم القاعدة', inp('n', r && r.name, 'required maxlength="120"'), 'wide')}
      ${field('حساب المصروف', `<select name="a">${exp.map(a => opt(a.code, a.code + ' — ' + a.name, r ? r.account_code : '5300')).join('')}</select>`)}
      ${field('من مركز التكلفة', `<select name="s"><option value="">${esc(tr('بدون مركز'))}</option>${ccs.map(c => opt(c.id, cm[c.id], r ? r.source_cc || '' : '')).join('')}</select>`)}
      <label class="row small" style="gap:6px"><input type="checkbox" name="act" style="width:auto" ${!r || r.active ? 'checked' : ''}> ${esc(tr('مفعّلة'))}</label></div>
      <div class="tw"><table class="lines"><thead><tr><th>${esc(tr('المركز المستفيد'))}</th><th>%</th><th></th></tr></thead><tbody id="alt">${(r ? r.targets : [null, null]).map(trow).join('')}</tbody></table></div>
      <button type="button" class="btn sm" id="ala" style="margin-top:6px">+ ${esc(tr('مركز'))}</button><p class="small" id="als"></p>`,
    { onOk: async f => { const ts = $$('#alt tr', d).map(t => ({ cc: $('[data-t=cc]', t).value, pct: +$('[data-t=pct]', t).value })).filter(t => t.cc && t.pct > 0);
      await db.rpc('alloc_rule_save', { p_company: S.cid, p_id: r ? r.id : null, p_name: f.n, p_account: f.a, p_source: blank(f.s), p_targets: ts, p_active: !!f.act }); toast(tr('تم الحفظ')); route(); } });
    const sum = () => { const s = $$('#alt [data-t=pct]', d).reduce((a, i) => a + n0(i.value), 0); $('#als', d).innerHTML = `${esc(tr('المجموع'))}: <b class="num ${Math.abs(s - 100) < 0.001 ? 'ok' : 'bad'}">${r2(s)}%</b>`; };
    $('#ala', d).onclick = () => { $('#alt', d).insertAdjacentHTML('beforeend', trow(null)); sum(); };
    $('#alt', d).addEventListener('click', e => { if (e.target.matches('[data-tx]')) { e.target.closest('tr').remove(); sum(); } }); $('#alt', d).addEventListener('input', sum); sum(); };
  $('#aln', page).onclick = () => form(null);
  bindRows(page, rules, r => form(r));
  $$('[data-alr]', page).forEach(b => b.addEventListener('click', e => { e.stopPropagation(); modal(tr('توزيع شهر'), field('الشهر', `<input type="month" name="m" value="${lm}">`),
    { ok: 'توزيع', onOk: async f => { const a = await db.rpc('alloc_run', { p_company: S.cid, p_rule: b.dataset.alr, p_month: f.m + '-01' }); toast(tr('وُزّع') + ' ' + money(a)); route(); } }); }));
};

/* ----- 23. financial ratios ----- */
const RATIOS = [['current', 'نسبة التداول', 'الأصول المتداولة ÷ الالتزامات المتداولة. أقل من 1 يعني أن الالتزامات قصيرة الأجل أكبر من الأصول المتداولة.', 'x'],
  ['quick', 'النسبة السريعة', 'الأصول المتداولة بدون المخزون ÷ الالتزامات المتداولة.', 'x'], ['cash_ratio', 'نسبة النقدية', 'النقد في الصندوق والبنوك ÷ الالتزامات المتداولة.', 'x'],
  ['gross_margin', 'هامش الربح الإجمالي', '(الإيرادات − تكلفة المبيعات) ÷ الإيرادات.', '%'], ['net_margin', 'هامش صافي الربح', 'صافي الربح ÷ الإيرادات.', '%'],
  ['roa', 'العائد على الأصول', 'صافي ربح الفترة ÷ إجمالي الأصول.', '%'], ['roe', 'العائد على حقوق الملكية', 'صافي ربح الفترة ÷ حقوق الملكية.', '%'],
  ['debt_to_equity', 'المديونية إلى حقوق الملكية', 'إجمالي الالتزامات ÷ حقوق الملكية.', 'x'], ['debt_ratio', 'نسبة المديونية', 'إجمالي الالتزامات ÷ إجمالي الأصول.', '%'],
  ['dso', 'متوسط مدة التحصيل', 'رصيد العملاء ÷ إيرادات الفترة × أيام الفترة.', 'd'], ['dpo', 'متوسط مدة السداد للموردين', 'رصيد الموردين ÷ تكلفة المبيعات × أيام الفترة.', 'd'],
  ['inventory_turnover', 'معدل دوران المخزون', 'تكلفة المبيعات ÷ المخزون.', 'x'], ['dio', 'أيام بقاء المخزون', 'المخزون ÷ تكلفة المبيعات × أيام الفترة.', 'd']];
VIEWS['#/ratios'] = async (page, arg, q) => {
  if (!can('reports')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const from = (q && q.get('from')) || today().slice(0, 4) + '-01-01', to = (q && q.get('to')) || today();
  const r = await db.rpc('fin_ratios', { p_company: S.cid, p_from: from, p_to: to }), u = { x: '', '%': '%', d: ' ' + tr('يوما') };
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('النسب المالية'))}</h1><div class="muted">${esc(tr('السيولة والربحية والمديونية والنشاط من دفاترك. الأرصدة حتى نهاية الفترة، والإيرادات والمصروفات خلالها.'))}</div></div>
      <form id="raf" class="row" style="gap:6px"><input type="date" name="from" value="${from}" aria-label="${esc(tr('من'))}"><input type="date" name="to" value="${to}" aria-label="${esc(tr('إلى'))}"><button class="btn">${esc(tr('عرض'))}</button></form></div>
    <div class="grid">${RATIOS.map(([k, t, h, un]) => `<div class="card kpi"><div class="muted small">${esc(tr(t))}</div><div class="v num">${r[k] == null ? '—' : r[k] + u[un]}</div><div class="small muted">${esc(tr(h))}</div></div>`).join('')}</div>
    <div class="card"><h2>${esc(tr('الأرقام المستخدمة'))}</h2>${tbl([{ t: 'البند', h: x => esc(tr(x[0])) }, { t: 'المبلغ', r: 1, h: x => money(x[1]) }],
      [['الأصول المتداولة', r.inputs.current_assets], ['الالتزامات المتداولة', r.inputs.current_liabilities], ['المخزون', r.inputs.inventory], ['النقد', r.inputs.cash], ['العملاء', r.inputs.receivables], ['الموردون', r.inputs.payables],
       ['إجمالي الأصول', r.inputs.total_assets], ['إجمالي الالتزامات', r.inputs.total_liabilities], ['حقوق الملكية مع ربح السنة', r.inputs.equity], ['الإيرادات', r.inputs.revenue], ['تكلفة المبيعات', r.inputs.cogs], ['صافي الربح', r.inputs.net_profit]], {})}
      <p class="muted small">${esc(tr('المتداول: كل الأصول عدا الأصول الثابتة (17xx) وغطاء خطابات الضمان، وكل الالتزامات عدا مخصص نهاية الخدمة (2500) والقروض طويلة الأجل (2600). المؤشرات للمتابعة، والحكم عليها يكون حسب نشاطك.'))}</p></div>`;
  $('#raf', page).onsubmit = ev => { ev.preventDefault(); const f = formData(ev.target); location.hash = `#/ratios?from=${f.from}&to=${f.to}`; };
};

/* ----- 21. custom reports ----- */
const RB = {
  employees: ['الموظفون', 'hr', { emp_no: 'الرقم', full_name: 'الاسم', job_title: 'المسمى', department_id: 'الإدارة', hire_date: 'تاريخ المباشرة', end_date: 'نهاية الخدمة', is_saudi: 'سعودي', gender: 'الجنس', nationality: 'الجنسية', basic: 'الأساسي', housing: 'السكن', transport: 'النقل', phone: 'الجوال' }, 'hire_date'],
  sales_invoices: ['فواتير المبيعات', 'sales', { no: 'الرقم', date: 'التاريخ', due_date: 'الاستحقاق', party_id: 'العميل', subtotal: 'قبل الضريبة', vat: 'الضريبة', total: 'الإجمالي', status: 'الحالة' }, 'date'],
  purchase_bills: ['فواتير المشتريات', 'purch', { no: 'الرقم', supplier_ref: 'رقم المورد', date: 'التاريخ', due_date: 'الاستحقاق', party_id: 'المورد', subtotal: 'قبل الضريبة', vat: 'الضريبة', total: 'الإجمالي', status: 'الحالة' }, 'date'],
  payments: ['السندات', 'finance', { no: 'الرقم', date: 'التاريخ', direction: 'النوع', party_id: 'الطرف', amount: 'المبلغ', account_code: 'الحساب', note: 'البيان' }, 'date'],
  requests: ['الطلبات', 'hr', { kind: 'النوع', sub: 'التفصيل', employee_id: 'الموظف', from_date: 'من', to_date: 'إلى', days: 'الأيام', amount: 'المبلغ', status: 'الحالة', created_at: 'تاريخ الطلب' }, 'created_at'],
  items: ['الأصناف', 'stock', { code: 'الرمز', name: 'الاسم', type: 'النوع', unit: 'الوحدة', sale_price: 'سعر البيع', purchase_price: 'سعر الشراء', reorder_level: 'حد إعادة الطلب' }, null],
  parties: ['العملاء والموردون', 'sales', { name: 'الاسم', kind: 'النوع', city: 'المدينة', phone: 'الهاتف', email: 'البريد', credit_limit: 'حد الائتمان', terms_days: 'مدة السداد' }, null],
  attendance: ['الحضور', 'hr', { day: 'اليوم', employee_id: 'الموظف', check_in: 'الحضور', check_out: 'الانصراف', late_min: 'دقائق التأخير', worked_min: 'دقائق العمل', ot_min: 'الإضافي المعتمد' }, 'day'] };
const RB_MONEY = ['basic', 'housing', 'transport', 'subtotal', 'vat', 'total', 'amount', 'sale_price', 'purchase_price', 'credit_limit'];
VIEWS['#/myreports'] = async (page, arg) => {
  const defs = await db.get('report_defs', { company_id: 'eq.' + S.cid, order: 'name' }).catch(() => []);
  if (arg) { const d = defs.find(x => x.id === arg); if (d) return reportRun(page, d); }
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('تقاريري المخصصة'))}</h1><div class="muted">${esc(tr('اختر البيانات والأعمدة والفلاتر واحفظ التقرير لتفتحه بضغطة. كل شخص يرى فيه ما تسمح به صلاحياته فقط.'))}</div></div><button class="btn pri" id="rbn">+ ${esc(tr('تقرير جديد'))}</button></div>
    ${tbl([{ t: 'التقرير', h: d => `<b data-nt>${esc(d.name)}</b>${d.shared ? ` <span class="badge info">${esc(tr('مشترك'))}</span>` : ''}` }, { t: 'البيانات', h: d => esc(tr(RB[d.dataset][0])) },
      { t: 'الإرسال', h: d => d.schedule === 'none' ? '—' : esc(tr(d.schedule === 'weekly' ? 'أسبوعي (الأحد)' : 'شهري (يوم 1)')) }], defs, { empty: 'لا توجد تقارير محفوظة', onRow: true })}`;
  $('#rbn', page).onclick = () => reportEdit(null);
  bindRows(page, defs, d => location.hash = '#/myreports/' + d.id);
};
function reportEdit(d) {
  const v = d || { dataset: 'sales_invoices', fields: [], filters: {}, schedule: 'none' };
  const fieldsBox = ds => Object.entries(RB[ds][2]).map(([k, t]) => `<label class="row small" style="gap:4px"><input type="checkbox" data-rf="${k}" style="width:auto" ${!d || v.fields.includes(k) ? 'checked' : ''}> ${esc(tr(t))}</label>`).join('');
  const m = modal(d ? tr('تعديل التقرير') : tr('تقرير جديد'), `<div class="fg">${field('اسم التقرير', inp('n', v.name, 'required maxlength="120"'), 'wide')}
      ${field('البيانات', `<select name="ds" id="rbd">${Object.entries(RB).filter(([k, x]) => modOn(x[1])).map(([k, x]) => opt(k, tr(x[0]), v.dataset)).join('')}</select>`)}
      ${field('من تاريخ', `<input type="date" name="from" value="${esc(v.filters.from || '')}">`)}${field('إلى تاريخ', `<input type="date" name="to" value="${esc(v.filters.to || '')}">`)}
      ${field('آخر كم يوما (بدل التاريخين)', inp('last', v.filters.last || '', 'type="number" min="1" max="3650"'))}${field('الحالة تساوي', inp('st', v.filters.status || '', 'maxlength="30" dir="ltr"'))}
      ${field('يحتوي النص', inp('q', v.filters.q || '', 'maxlength="60"'))}
      ${field('الإرسال بالإيميل', `<select name="sch">${opt('none', tr('بدون'))}${opt('weekly', tr('أسبوعي (الأحد)'))}${opt('monthly', tr('شهري (يوم 1)'))}</select>`)}
      <label class="row small" style="gap:6px"><input type="checkbox" name="sh" style="width:auto" ${v.shared ? 'checked' : ''}> ${esc(tr('مشترك مع زملائي (كلٌّ يرى بصلاحياته)'))}</label>
      <div class="wide"><label>${esc(tr('الأعمدة'))}</label><div class="row" id="rbf" style="flex-wrap:wrap;gap:10px">${fieldsBox(v.dataset)}</div></div></div>
      <p class="muted small">${esc(tr('الإيميل المجدول يحمل رابط التقرير فقط، وتُفتح البيانات بعد تسجيل الدخول.'))}</p>`,
    { wide: true, onOk: async f => { const fs = $$('[data-rf]:checked', m).map(x => x.dataset.rf); if (!fs.length) throw new Error(tr('اختر عمودا واحدا على الأقل'));
      const row = { name: (f.n || '').trim(), dataset: f.ds, fields: fs, filters: { from: f.from || undefined, to: f.to || undefined, last: f.last ? +f.last : undefined, status: f.st || undefined, q: f.q || undefined }, schedule: f.sch, shared: !!f.sh };
      if (row.name.length < 2) throw new Error(tr('اكتب اسم التقرير'));
      if (d) await db.upd('report_defs', { id: 'eq.' + d.id }, row); else { const [x] = await db.ins('report_defs', Object.assign(row, { company_id: S.cid })); location.hash = '#/myreports/' + x.id; return; }
      toast(tr('تم الحفظ')); route(); } });
  $('select[name=sch]', m).value = v.schedule || 'none';
  $('#rbd', m).onchange = e => { $('#rbf', m).innerHTML = fieldsBox(e.target.value); };
}
async function reportRun(page, d) {
  const ds = RB[d.dataset], f = d.filters || {}, dt = ds[3], q = { company_id: 'eq.' + S.cid, select: d.fields.concat(['id']).filter((x, i, a) => a.indexOf(x) === i).join(','), limit: 5000 };
  if (dt) { const from = f.last ? addDays(today(), -f.last) : f.from; if (from) q[dt] = 'gte.' + from; if (dt) q.order = dt + '.desc'; }
  if (f.status && d.fields.includes('status')) q.status = 'eq.' + f.status;
  let rows = await db.get(d.dataset, q).catch(e => { toast(e.message); return []; });
  if (dt && f.to && !f.last) rows = rows.filter(r => String(r[dt]).slice(0, 10) <= f.to);
  const [pm, em, dm] = await Promise.all([d.fields.includes('party_id') ? db.get('parties', { company_id: 'eq.' + S.cid, select: 'id,name' }).then(x => Object.fromEntries(x.map(p => [p.id, p.name]))).catch(() => ({})) : {},
    d.fields.includes('employee_id') ? employeesMap(true).catch(() => ({})) : {}, d.fields.includes('department_id') ? db.get('departments', { company_id: 'eq.' + S.cid, select: 'id,name' }).then(x => Object.fromEntries(x.map(p => [p.id, p.name]))).catch(() => ({})) : {}]);
  const show = (k, v) => v == null ? '' : k === 'party_id' ? pm[v] || '' : k === 'employee_id' ? (em[v] || {}).full_name || '' : k === 'department_id' ? dm[v] || '' : k === 'kind' && KIND[v] ? tr(KIND[v]) : typeof v === 'boolean' ? tr(v ? 'نعم' : 'لا') : String(v);
  if (f.q) { const s = f.q.toLowerCase(); rows = rows.filter(r => d.fields.some(k => show(k, r[k]).toLowerCase().includes(s))); }
  page.innerHTML = `<div class="head"><div><a href="#/myreports" class="small back">${esc(tr('تقاريري المخصصة'))}</a><h1>${esc(d.name)}</h1><div class="muted">${esc(tr(ds[0]))} · <span class="num">${rows.length}</span> ${esc(tr('سطر'))}</div></div>
      <div class="row" style="gap:6px"><button class="btn" id="rbx">${esc(tr('تنزيل Excel'))}</button><button class="btn" id="rbp">${esc(tr('طباعة'))}</button>${d.created_by === S.session.user.id ? `<button class="btn" id="rbe">${esc(tr('تعديل'))}</button><button class="btn danger" id="rbdl">${esc(tr('حذف'))}</button>` : ''}</div></div>
    <div class="card" id="rbt">${tbl(d.fields.map(k => ({ t: ds[2][k], r: RB_MONEY.includes(k) ? 1 : 0, h: r => RB_MONEY.includes(k) && r[k] != null ? money(r[k]) : esc(show(k, r[k])) })), rows, { empty: 'لا توجد بيانات' })}</div>`;
  $('#rbx', page).onclick = () => tablesXlsx($('#rbt', page), d.name);
  $('#rbp', page).onclick = () => { const n = document.createElement('div'); n.innerHTML = printHead(d.name) + $('#rbt', page).innerHTML; printWith(n, '@page{size:A4 landscape;margin:10mm}'); };
  if ($('#rbe', page)) $('#rbe', page).onclick = () => reportEdit(d);
  if ($('#rbdl', page)) $('#rbdl', page).onclick = async () => { if (!await confirmBox(tr('حذف التقرير'), d.name, tr('حذف'))) return; await db.del('report_defs', { id: 'eq.' + d.id }); location.hash = '#/myreports'; };
}

/* ----- 22. webhooks (company settings) ----- */
const WH_EV = { 'invoice.posted': 'ترحيل فاتورة مبيعات', 'bill.posted': 'ترحيل فاتورة مشتريات', 'payment.recorded': 'تسجيل سند قبض أو صرف', 'employee.created': 'إضافة موظف', 'request.approved': 'اعتماد طلب موظف' };
async function webhooksCard(el) {
  const ws = await db.rpc('webhook_list', { p_company: S.cid });
  el.innerHTML = `<h2>${esc(tr('إشعارات الأنظمة الأخرى (Webhooks)'))}</h2><p class="muted small">${esc(tr('يرسل وعد إلى رابطك رسالة JSON عند كل حدث تختاره، خلال 10 دقائق من وقوعه، موقّعة بمفتاح سري لتتحقق أنها من وعد: الترويسة X-Waad-Signature = HMAC-SHA256 للطابع الزمني (X-Waad-Timestamp) ثم نقطة ثم نص الرسالة.'))}</p>
    ${ws.length ? tbl([{ t: 'الرابط', h: w => `<span dir="ltr" class="small">${esc(w.url)}</span>${w.note ? `<div class="small muted">${esc(w.note)}</div>` : ''}` }, { t: 'الأحداث', h: w => w.events.map(e => esc(tr(WH_EV[e] || e))).join('، ') },
      { t: 'آخر رد', h: w => w.last_status ? `<span class="badge ${w.last_status < 300 ? 'ok' : 'bad'} num">${w.last_status}</span> ${w.pending ? `<span class="small muted">${esc(tr('بالانتظار'))} <span class="num">${w.pending}</span></span>` : ''}` : (w.pending ? `<span class="small muted">${esc(tr('بالانتظار'))} <span class="num">${w.pending}</span></span>` : '—') },
      { t: '', h: w => `<button class="btn sm" data-wht="${w.id}" data-on="${w.active ? 0 : 1}">${esc(tr(w.active ? 'إيقاف' : 'تشغيل'))}</button> <button class="btn sm danger" data-whd="${w.id}">×</button>` }], ws, {}) : ''}
    <button type="button" class="btn sm pri" id="whn">+ ${esc(tr('رابط جديد'))}</button>`;
  $('#whn', el).onclick = () => modal(tr('رابط إشعارات جديد'), `<div class="fg">${field('الرابط (https)', inp('u', '', 'dir="ltr" placeholder="https://"'), 'wide')}${field('ملاحظة', inp('n', ''), 'wide')}
      <div class="wide">${Object.entries(WH_EV).map(([k, t]) => `<label class="row small" style="gap:6px"><input type="checkbox" data-we="${k}" style="width:auto" checked> ${esc(tr(t))} <span class="muted num" dir="ltr">${k}</span></label>`).join('')}</div></div>
      <p class="muted small">${esc(tr('بيانات الموظف المرسلة: الرقم والاسم والمسمى والإدارة وتاريخ المباشرة فقط، بلا راتب أو هوية.'))}</p>`,
    { onOk: async (f, dlg) => { const ev = $$('[data-we]:checked', dlg).map(x => x.dataset.we); const r = await db.rpc('webhook_save', { p_company: S.cid, p_url: (f.u || '').trim(), p_events: ev, p_note: f.n || '' });
      setTimeout(() => { modal(tr('المفتاح السري'), `<p class="small">${esc(tr('انسخه الآن: لن يظهر مرة أخرى. احفظه في النظام المستقبِل للتحقق من التوقيع.'))}</p><input readonly dir="ltr" value="${esc(r.secret)}" onclick="this.select()">`, {});
        $('#dlg').addEventListener('close', () => webhooksCard(el), { once: true }); }, 50); } });
  $$('[data-wht]', el).forEach(b => b.onclick = async () => { await db.rpc('webhook_toggle', { p_id: b.dataset.wht, p_active: b.dataset.on === '1', p_delete: false }); webhooksCard(el); });
  $$('[data-whd]', el).forEach(b => b.onclick = async () => { if (!await confirmBox(tr('حذف الرابط'), tr('تتوقف الإشعارات إليه.'), tr('حذف'))) return; await db.rpc('webhook_toggle', { p_id: b.dataset.whd, p_active: false, p_delete: true }); webhooksCard(el); });
}

/* ----- 20. competencies and succession ----- */
const CMP_CAT = { core: 'جدارات أساسية', technical: 'جدارات فنية', leadership: 'جدارات قيادية', behavioral: 'جدارات سلوكية' };
VIEWS['#/competencies'] = async page => {
  const hr = isHR();
  const [cs, em, jds, jdc, ec] = await Promise.all([db.get('competencies', { company_id: 'eq.' + S.cid, order: 'category,name' }), employeesMap(true), db.get('job_descriptions', { company_id: 'eq.' + S.cid, order: 'title', select: 'id,title' }),
    db.get('jd_competencies', { company_id: 'eq.' + S.cid }), db.get('employee_competencies', { company_id: 'eq.' + S.cid }).catch(() => [])]);
  const emps = Object.values(em).filter(e => (!e.end_date || e.end_date >= today()) && (hr || e.manager_id === S.emp));
  const lvl = (e, c) => (ec.find(x => x.employee_id === e.id && x.competency_id === c.id) || {}).level, req = (e, c) => (jdc.find(x => x.jd_id === e.jd_id && x.competency_id === c.id) || {}).level;
  const cell = (e, c) => { const a = lvl(e, c), r = req(e, c); return `<td class="c">${a ? `<b class="num ${r && a < r ? 'bad' : r ? 'ok' : ''}">${a}</b>` : '<span class="muted">—</span>'}${r ? `<span class="small muted num">/${r}</span>` : ''}</td>`; };
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('مصفوفة الجدارات'))}</h1><div class="muted">${esc(tr('مستوى كل موظف (1–5) مقابل المطلوب في وصفه الوظيفي. الأحمر = فجوة تحتاج تطويرا أو تدريبا.'))}</div></div>
      <div class="row" style="gap:6px">${hr ? `<a class="btn" href="#/succession">${esc(tr('تخطيط الإحلال'))}</a><button class="btn" id="cmr">${esc(tr('المطلوب لكل وظيفة'))}</button><button class="btn pri" id="cmn">+ ${esc(tr('جدارة'))}</button>` : ''}</div></div>
    ${cs.length ? `<div class="card"><div class="tw"><table><thead><tr><th>${esc(tr('الموظف'))}</th>${cs.map(c => `<th class="c" title="${esc(tr(CMP_CAT[c.category]))}">${esc(c.name)}</th>`).join('')}<th></th></tr></thead><tbody>
      ${emps.map(e => `<tr><td data-nt>${esc(e.full_name)}<div class="small muted">${esc((jds.find(j => j.id === e.jd_id) || {}).title || e.job_title || '')}</div></td>${cs.map(c => cell(e, c)).join('')}<td><button class="btn sm" data-cme="${e.id}">${esc(tr('تقييم'))}</button></td></tr>`).join('')}</tbody></table></div></div>`
      : `<div class="note">${esc(tr('أضف الجدارات أولا (مثل: التواصل، حل المشكلات، القيادة، المعرفة الفنية).'))}</div>`}`;
  if ($('#cmn', page)) $('#cmn', page).onclick = () => modal(tr('جدارة جديدة'), `<div class="fg">${field('الاسم', inp('n', '', 'required maxlength="120"'))}${field('النوع', `<select name="c">${Object.entries(CMP_CAT).map(([k, t]) => opt(k, tr(t))).join('')}</select>`)}${field('الوصف', inp('d', ''), 'wide')}</div>`,
    { onOk: async f => { await db.rpc('competency_save', { p_company: S.cid, p_id: null, p_name: f.n, p_category: f.c, p_desc: f.d || '' }); toast(tr('تم الحفظ')); route(); } });
  if ($('#cmr', page)) $('#cmr', page).onclick = () => { if (!jds.length) return toast(tr('أضف الأوصاف الوظيفية أولا من «مكتبة الوصف الوظيفي»'));
    const d = modal(tr('المطلوب لكل وظيفة'), `${field('الوظيفة', `<select id="cmj">${jds.map(j => opt(j.id, j.title)).join('')}</select>`)}<div class="fg" id="cmjl"></div>`,
      { onOk: async () => { const lv = {}; $$('[data-cmr]', d).forEach(s => lv[s.dataset.cmr] = +s.value); await db.rpc('jd_competencies_set', { p_jd: $('#cmj', d).value, p_levels: lv }); toast(tr('تم الحفظ')); route(); } });
    const draw = () => { const j = $('#cmj', d).value; $('#cmjl', d).innerHTML = cs.map(c => field(c.name, `<select data-cmr="${c.id}">${[0, 1, 2, 3, 4, 5].map(n => opt(n, n ? String(n) : '—', String((jdc.find(x => x.jd_id === j && x.competency_id === c.id) || {}).level || 0))).join('')}</select>`)).join(''); };
    $('#cmj', d).onchange = draw; draw(); };
  $$('[data-cme]', page).forEach(b => b.onclick = () => { const e = em[b.dataset.cme];
    const d = modal(tr('تقييم الجدارات') + ' — ' + e.full_name, `${hr && jds.length ? field('الوصف الوظيفي', `<select id="cmej"><option value="">—</option>${jds.map(j => opt(j.id, j.title, e.jd_id || '')).join('')}</select>`) : ''}
      <div class="fg">${cs.map(c => field(c.name + (req(e, c) ? ` (${tr('المطلوب')} ${req(e, c)})` : ''), `<select data-cmv="${c.id}">${[0, 1, 2, 3, 4, 5].map(n => opt(n, n ? String(n) : '—', String(lvl(e, c) || 0))).join('')}</select>`)).join('')}</div>`,
      { onOk: async () => { if ($('#cmej', d) && ($('#cmej', d).value || null) !== (e.jd_id || null)) await db.rpc('employee_jd_set', { p_emp: e.id, p_jd: blank($('#cmej', d).value) });
        const lv = {}; $$('[data-cmv]', d).forEach(s => lv[s.dataset.cmv] = +s.value); await db.rpc('employee_competencies_set', { p_emp: e.id, p_levels: lv }); toast(tr('تم الحفظ')); route(); } }); });
};
const SUC_R = { now: ['جاهز الآن', 'ok'], '1y': ['خلال سنة', 'wait'], '2y': ['خلال سنتين', ''] }, SUC_K = { low: ['منخفض', 'ok'], medium: ['متوسط', 'wait'], high: ['مرتفع', 'bad'] };
VIEWS['#/succession'] = async page => {
  if (!isHR()) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const [ps, em] = await Promise.all([db.get('succession_plans', { company_id: 'eq.' + S.cid, order: 'position' }), employeesMap(true)]);
  const emps = Object.values(em).filter(e => !e.end_date || e.end_date >= today()), nm = id => (em[id] || {}).full_name || '—';
  page.innerHTML = `<div class="head"><div><a href="#/competencies" class="small back">${esc(tr('مصفوفة الجدارات'))}</a><h1>${esc(tr('تخطيط الإحلال الوظيفي'))}</h1><div class="muted">${esc(tr('المناصب المهمة، من يشغلها، ومن يجهز لخلافته ومتى.'))}</div></div><button class="btn pri" id="spn">+ ${esc(tr('منصب'))}</button></div>
    ${tbl([{ t: 'المنصب', h: p => `<b data-nt>${esc(p.position)}</b>` }, { t: 'الشاغل الحالي', h: p => `<span data-nt>${esc(nm(p.incumbent_id))}</span>` }, { t: 'خطر الشغور', h: p => `<span class="badge ${SUC_K[p.risk][1]}">${esc(tr(SUC_K[p.risk][0]))}</span>` },
      { t: 'الخلفاء المحتملون', h: p => p.successors.length ? p.successors.map(s => `<span data-nt>${esc(nm(s.emp))}</span> <span class="badge ${SUC_R[s.readiness][1]}">${esc(tr(SUC_R[s.readiness][0]))}</span>`).join('<br>') : `<span class="bad small">${esc(tr('لا يوجد خليفة'))}</span>` }], ps, { empty: 'لا توجد خطط إحلال', onRow: true })}`;
  const srow = s => `<tr><td><select data-s="emp"><option value="">—</option>${emps.map(e => opt(e.id, e.full_name, (s && s.emp) || '')).join('')}</select></td><td><select data-s="r">${Object.entries(SUC_R).map(([k, [t]]) => opt(k, tr(t), (s && s.readiness) || '1y')).join('')}</select></td><td><button type="button" class="btn sm" data-sx>×</button></td></tr>`;
  const form = p => { const d = modal(p ? tr('تعديل خطة الإحلال') : tr('منصب جديد'), `<div class="fg">${field('المنصب', inp('pos', p && p.position, 'required maxlength="120"'))}
      ${field('الشاغل الحالي', `<select name="inc"><option value="">—</option>${emps.map(e => opt(e.id, e.full_name, (p && p.incumbent_id) || '')).join('')}</select>`)}${field('خطر الشغور', `<select name="risk">${Object.entries(SUC_K).map(([k, [t]]) => opt(k, tr(t), (p && p.risk) || 'medium')).join('')}</select>`)}
      ${field('ملاحظات', inp('note', p && p.note), 'wide')}</div><div class="tw"><table class="lines"><thead><tr><th>${esc(tr('الخليفة'))}</th><th>${esc(tr('الجاهزية'))}</th><th></th></tr></thead><tbody id="spl">${((p && p.successors.length ? p.successors : [null])).map(srow).join('')}</tbody></table></div>
      <button type="button" class="btn sm" id="spa" style="margin-top:6px">+ ${esc(tr('خليفة'))}</button>`,
    { onOk: async f => { const su = $$('#spl tr', d).map(t => ({ emp: $('[data-s=emp]', t).value, readiness: $('[data-s=r]', t).value })).filter(s => s.emp);
      await db.rpc('succession_save', { p_company: S.cid, p_id: p ? p.id : null, p_doc: { position: f.pos, incumbent: f.inc || null, risk: f.risk, note: f.note || '', successors: su } }); toast(tr('تم الحفظ')); route(); } });
    $('#spa', d).onclick = () => $('#spl', d).insertAdjacentHTML('beforeend', srow(null)); $('#spl', d).addEventListener('click', e => { if (e.target.matches('[data-sx]')) e.target.closest('tr').remove(); }); };
  $('#spn', page).onclick = () => form(null);
  bindRows(page, ps, p => form(p));
};

/* ----- 24. pay equity ----- */
VIEWS['#/payequity'] = async page => {
  if (!has('owner', 'admin', 'hr')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const rows = await db.rpc('pay_equity', { p_company: S.cid });
  const gap = v => v == null ? '—' : `<b class="num ${Math.abs(v) >= 10 ? 'bad' : Math.abs(v) >= 5 ? 'wait' : ''}">${v}%</b>`;
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('تحليل عدالة الأجور'))}</h1><div class="muted">${esc(tr('متوسط إجمالي الأجر داخل كل درجة (أو مسمى) حسب الجنس وحسب سعودي / غير سعودي. الفجوة = (المتوسط الأعلى − المتوسط الآخر) ÷ الأعلى.'))}</div></div></div>
    ${tbl([{ t: 'الدرجة / المسمى', h: r => `<b data-nt>${esc(r.group)}</b> <span class="small muted num">${r.n}</span>` }, { t: 'الوسيط', r: 1, h: r => money(r.median) },
      { t: 'رجال', r: 1, h: r => r.men ? `${money(r.avg_men)} <span class="small muted num">(${r.men})</span>` : '—' }, { t: 'نساء', r: 1, h: r => r.women ? `${money(r.avg_women)} <span class="small muted num">(${r.women})</span>` : '—' }, { t: 'فجوة الجنس', r: 1, h: r => gap(r.gender_gap) },
      { t: 'سعودي', r: 1, h: r => r.saudi ? `${money(r.avg_saudi)} <span class="small muted num">(${r.saudi})</span>` : '—' }, { t: 'غير سعودي', r: 1, h: r => r.non_saudi ? `${money(r.avg_non_saudi)} <span class="small muted num">(${r.non_saudi})</span>` : '—' },
      { t: 'فجوة الجنسية', r: 1, h: r => gap(r.nat_gap) }], rows, { empty: 'لا توجد بيانات' })}
    <p class="muted small">${esc(tr('الفروق قد تفسرها الخبرة أو الأقدمية أو الأداء؛ التحليل يدلّك على ما يستحق المراجعة، وليس حكما.'))}</p>`;
};

/* ----- 25. recognition wall ----- */
const KD_V = { teamwork: ['🤝', 'روح الفريق'], excellence: ['⭐', 'التميز'], help: ['🙌', 'المساعدة'], initiative: ['💡', 'المبادرة'], customer: ['😊', 'خدمة العملاء'], integrity: ['🛡️', 'النزاهة'] };
VIEWS['#/kudos'] = async page => {
  const w = await db.rpc('kudos_wall', { p_company: S.cid, p_limit: 100 });
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الشكر والتقدير'))}</h1><div class="muted">${esc(tr('اشكر زميلا على عمل مميز؛ يراه الجميع في المنشأة.'))}</div></div>${S.emp ? `<button class="btn pri" id="kdn">${esc(tr('اشكر زميلا'))}</button>` : ''}</div>
    ${w.top.length ? `<div class="card"><h2>${esc(tr('الأكثر شكرا هذا الشهر'))}</h2><div class="row" style="gap:10px;flex-wrap:wrap">${w.top.map((x, i) => `<span class="badge ${i ? '' : 'ok'}"><span data-nt>${esc(x.name)}</span> · <span class="num">${x.n}</span></span>`).join('')}</div></div>` : ''}
    ${w.items.length ? w.items.map(k => `<div class="card" style="padding:12px"><div class="row" style="gap:8px;align-items:center"><span style="font-size:1.4em">${KD_V[k.value][0]}</span><div><b data-nt>${esc(k.from)}</b> ← <b data-nt>${esc(k.to)}</b> <span class="badge info">${esc(tr(KD_V[k.value][1]))}</span>
      <div class="small muted">${fdate(String(k.at).slice(0, 10))}</div></div></div><p style="margin:8px 0 0" data-nt>${esc(k.message)}</p></div>`).join('') : `<div class="note">${esc(tr('كن أول من يشكر زميلا.'))}</div>`}`;
  if ($('#kdn', page)) $('#kdn', page).onclick = async () => { const em = (await db.rpc('staff_directory', { p_company: S.cid }).catch(() => [])).filter(x => !x.mine);
    modal(tr('اشكر زميلا'), `<div class="fg">${field('الزميل', `<select name="to"><option value="">—</option>${em.map(e => opt(e.id, e.name + (e.department ? ' — ' + e.department : ''))).join('')}</select>`)}
      ${field('القيمة', `<select name="v">${Object.entries(KD_V).map(([k, [i, t]]) => opt(k, i + ' ' + tr(t))).join('')}</select>`)}${field('رسالتك', '<textarea name="m" rows="3" maxlength="500"></textarea>', 'wide')}</div>`,
    { ok: 'إرسال', onOk: async f => { if (!f.to) throw new Error(tr('اختر الزميل')); await db.rpc('kudos_send', { p_company: S.cid, p_to: f.to, p_value: f.v, p_message: f.m || '' }); toast(tr('أُرسل الشكر')); route(); } }); };
};
async function kudosHome(page) {
  const w = await db.rpc('kudos_wall', { p_company: S.cid, p_limit: 3 }).catch(() => null); if (!w || !w.items.length || !page.isConnected) return;
  const box = document.createElement('div'); box.className = 'card'; box.style.marginTop = '14px';
  box.innerHTML = `<div class="row" style="justify-content:space-between"><h2>${esc(tr('الشكر والتقدير'))}</h2><a class="small" href="#/kudos">${esc(tr('الكل'))}</a></div>${w.items.map(k => `<div class="small" style="margin:6px 0">${KD_V[k.value][0]} <b data-nt>${esc(k.from)}</b> ← <b data-nt>${esc(k.to)}</b>: <span data-nt>${esc(k.message)}</span></div>`).join('')}`;
  page.appendChild(box);
}

/* ----- 26. service tickets and warranty ----- */
const TK_K = { support: 'دعم', repair: 'إصلاح', maintenance: 'صيانة', complaint: 'شكوى', question: 'استفسار' }, TK_P = { low: ['منخفضة', ''], normal: ['عادية', ''], high: ['عالية', 'wait'], urgent: ['عاجلة', 'bad'] };
const TK_S = { new: ['جديدة', 'wait'], open: ['قيد العمل', 'info'], waiting: ['بانتظار العميل', ''], resolved: ['حُلّت', 'ok'], closed: ['مغلقة', ''] };
const tkBadge = s => `<span class="badge ${TK_S[s][1]}">${esc(tr(TK_S[s][0]))}</span>`;
VIEWS['#/tickets'] = async (page, arg, q) => {
  const [rows, parties, em, items] = await Promise.all([db.get('service_tickets', { company_id: 'eq.' + S.cid, order: 'created_at.desc', limit: 500 }), db.get('parties', { company_id: 'eq.' + S.cid, kind: 'eq.customer', select: 'id,name' }).catch(() => []),
    employeesMap(true).catch(() => ({})), db.get('items', { company_id: 'eq.' + S.cid, select: 'id,code,name,warranty_months', order: 'code' }).catch(() => [])]);
  const pm = {}; parties.forEach(p => pm[p.id] = p.name); const im = {}; items.forEach(i => im[i.id] = i); const st = (q && q.get('s')) || 'active';
  const ls = rows.filter(t => st === 'all' || (st === 'active' ? !['resolved', 'closed'].includes(t.status) : t.status === st));
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('تذاكر الدعم والصيانة'))}</h1><div class="muted">${esc(tr('طلبات العملاء: دعم، إصلاح، صيانة، شكوى. تُفتح هنا أو من بوابة العميل، ويظهر إن كان المنتج في الضمان.'))}</div></div><button class="btn pri" id="tkn">+ ${esc(tr('تذكرة'))}</button></div>
    <div class="tabs" style="max-width:520px">${[['active', 'المفتوحة'], ['resolved', 'حُلّت'], ['all', 'الكل']].map(([k, t]) => `<button type="button" class="${st === k ? 'on' : ''}" onclick="location.hash='#/tickets?s=${k}'">${esc(tr(t))}</button>`).join('')}</div>
    ${tbl([{ t: 'الرقم', h: t => `<span class="num">${esc(t.no)}</span>${t.source === 'portal' ? ` <span class="badge info">${esc(tr('من البوابة'))}</span>` : ''}` }, { t: 'الموضوع', h: t => esc(t.subject) + `<div class="small muted">${esc(tr(TK_K[t.kind]))}${t.item_id ? ' · ' + esc((im[t.item_id] || {}).name || '') : ''}</div>` },
      { t: 'العميل', h: t => `<span data-nt>${esc(pm[t.party_id] || t.contact || '—')}</span>` }, { t: 'الضمان', h: t => t.warranty_until ? (t.warranty_until >= today() ? `<span class="badge ok">${esc(tr('في الضمان'))}</span>` : `<span class="badge">${esc(tr('انتهى'))} ${fdate(t.warranty_until)}</span>`) : '—' },
      { t: 'الأولوية', h: t => `<span class="badge ${TK_P[t.priority][1]}">${esc(tr(TK_P[t.priority][0]))}</span>` }, { t: 'المسؤول', h: t => `<span data-nt>${esc((em[t.assigned_to] || {}).full_name || '—')}</span>` },
      { t: 'الحالة', h: t => tkBadge(t.status) }], ls, { empty: 'لا توجد تذاكر', onRow: true })}`;
  const emps = Object.values(em).filter(e => !e.end_date);
  $('#tkn', page).onclick = () => { const d = modal(tr('تذكرة جديدة'), `<div class="fg">${field('العميل', `<select name="p" id="tkp"><option value="">—</option>${parties.filter(p => p.name !== 'عميل نقدي').map(p => opt(p.id, p.name)).join('')}</select>`)}${field('جهة التواصل', inp('c', ''))}
      ${field('النوع', `<select name="k">${Object.entries(TK_K).map(([k, t]) => opt(k, tr(t))).join('')}</select>`)}${field('الأولوية', `<select name="pr">${Object.entries(TK_P).map(([k, [t]]) => opt(k, tr(t), 'normal')).join('')}</select>`)}
      ${field('الموضوع', inp('s', '', 'required maxlength="200"'), 'wide')}${field('التفاصيل', '<textarea name="d" rows="3"></textarea>', 'wide')}
      ${field('الصنف', `<select name="i"><option value="">—</option>${items.map(i => opt(i.id, i.code + ' — ' + i.name + (i.warranty_months ? ` (${tr('ضمان')} ${i.warranty_months} ${tr('شهرا')})` : ''))).join('')}</select>`)}${field('الفاتورة', '<select name="inv" id="tki"><option value="">—</option></select>')}
      ${field('الرقم التسلسلي', inp('sn', '', 'dir="ltr"'))}${field('المسؤول', `<select name="a"><option value="">—</option>${emps.map(e => opt(e.id, e.full_name)).join('')}</select>`)}</div>`,
    { onOk: async f => { await db.rpc('ticket_save', { p_company: S.cid, p_id: null, p_doc: { party: f.p || null, contact: f.c, kind: f.k, priority: f.pr, subject: f.s, description: f.d, item: f.i || null, invoice: f.inv || null, serial: f.sn, assigned: f.a || null } }); toast(tr('تم الحفظ')); route(); } });
    $('#tkp', d).onchange = async e => { const inv = e.target.value ? await db.get('sales_invoices', { company_id: 'eq.' + S.cid, party_id: 'eq.' + e.target.value, status: 'eq.posted', order: 'date.desc', limit: 50, select: 'id,no,date' }).catch(() => []) : [];
      $('#tki', d).innerHTML = '<option value="">—</option>' + inv.map(i => opt(i.id, i.no + ' — ' + i.date)).join(''); }; };
  bindRows(page, ls, async t => { const notes = await db.get('ticket_notes', { ticket_id: 'eq.' + t.id, order: 'created_at' }).catch(() => []);
    modal(t.no + ' — ' + t.subject, `<p class="small muted">${esc(tr(TK_K[t.kind]))} · ${esc(pm[t.party_id] || t.contact || '')} · ${fdate(String(t.created_at).slice(0, 10))}${t.serial ? ' · <span class="num">' + esc(t.serial) + '</span>' : ''}</p>${t.description ? `<p style="white-space:pre-wrap">${esc(t.description)}</p>` : ''}
      ${notes.map(n => `<div class="card" style="padding:8px 10px;margin:6px 0;${n.side === 'internal' ? 'background:var(--line)' : ''}"><div class="small muted">${esc(tr(n.side === 'internal' ? 'ملاحظة داخلية' : n.side === 'customer' ? 'العميل' : 'رد للعميل'))} · ${fdate(String(n.created_at).slice(0, 10))}</div><div style="white-space:pre-wrap">${esc(n.body)}</div></div>`).join('')}
      <div class="fg">${field('ردّ أو ملاحظة', '<textarea name="n" rows="2"></textarea>', 'wide')}<label class="row small" style="gap:6px"><input type="checkbox" name="int" style="width:auto"> ${esc(tr('ملاحظة داخلية (لا يراها العميل)'))}</label>
        ${field('الحالة', `<select name="st">${Object.entries(TK_S).map(([k, [x]]) => opt(k, tr(x), t.status)).join('')}</select>`)}${field('المسؤول', `<select name="a"><option value="">—</option>${emps.map(e => opt(e.id, e.full_name, t.assigned_to || '')).join('')}</select>`)}
        ${field('الحل', inp('res', t.resolution || ''), 'wide')}</div>`,
      { wide: true, onOk: async f => { if ((f.n || '').trim()) await db.rpc('ticket_note', { p_id: t.id, p_body: f.n, p_internal: !!f.int });
        await db.rpc('ticket_save', { p_company: S.cid, p_id: t.id, p_doc: { status: f.st, assigned: f.a || '', resolution: f.res || '' } }); toast(tr('تم الحفظ')); route(); } }); });
};
// the customer's portal: their tickets and a form to open one
async function portalTicketsBox(box, token) {
  const ts = await db.rpc('portal_tickets', { p_token: token }).catch(() => null); if (ts == null) return;
  const el = document.createElement('div'); el.className = 'card';
  el.innerHTML = `<h2>${esc(tr('طلبات الدعم'))}</h2>${ts.length ? ts.map(t => `<div style="margin:8px 0"><b class="num">${esc(t.no)}</b> ${esc(t.subject)} ${tkBadge(t.status)}${t.resolution ? `<div class="small">${esc(tr('الحل'))}: ${esc(t.resolution)}</div>` : ''}${t.notes.map(n => `<div class="small muted">↳ ${esc(n.body)}</div>`).join('')}</div>`).join('') : ''}
    <form id="ptf" class="fg" novalidate>${field('الموضوع', inp('s', '', 'maxlength="200"'), 'wide')}${field('التفاصيل', '<textarea name="b" rows="3" maxlength="5000"></textarea>', 'wide')}</form><div id="pterr"></div><button class="btn" id="pts">${esc(tr('فتح طلب دعم'))}</button>`;
  box.insertBefore(el, box.lastElementChild);
  $('#pts', el).onclick = async () => { const f = formData($('#ptf', el)); try { const no = await db.rpc('portal_ticket_open', { p_token: token, p_subject: f.s, p_body: f.b }); toast(tr('أُرسل الطلب') + ' ' + no); el.remove(); portalTicketsBox(box, token); } catch (e) { showErr($('#pterr', el), e); } };
}

/* ----- 27. loyalty points ----- */
async function loyaltyCard(el) {
  const c = S.company || {};
  el.innerHTML = `<h2>${esc(tr('نقاط الولاء في نقطة البيع'))}</h2><div class="fg"><label class="row small wide" style="gap:6px"><input type="checkbox" id="lyo" style="width:auto" ${c.loyalty_on ? 'checked' : ''}> ${esc(tr('تفعيل نقاط الولاء للعملاء المسجلين'))}</label>
    ${field('نقاط لكل ريال مدفوع', inp('e', c.loyalty_earn == null ? 1 : +c.loyalty_earn, 'id="lye" type="number" min="0" step="0.01"'))}${field('قيمة النقطة (ريال)', inp('v', c.loyalty_value == null ? 0.05 : +c.loyalty_value, 'id="lyv" type="number" min="0" step="0.0001"'))}
    ${field('أقل عدد نقاط للاستبدال', inp('m', c.loyalty_min == null ? 100 : c.loyalty_min, 'id="lym" type="number" min="0"'))}</div>
    <p class="muted small">${esc(tr('تُكسب النقاط على ما يدفعه العميل نقدا أو بالشبكة أو بالشيك، وتُستبدل جزءا من الدفع في البيع التالي (تُسجَّل على حساب «تكلفة برنامج الولاء» 5975، وتبقى الضريبة على كامل الفاتورة). إلغاء الفاتورة يلغي نقاطها. استشر محاسبك في المعالجة الضريبية لبرامج الولاء.'))}</p>
    <button type="button" class="btn sm pri" id="lys">${esc(tr('حفظ'))}</button>`;
  $('#lys', el).onclick = async () => { try { await db.rpc('loyalty_set', { p_company: S.cid, p_on: $('#lyo', el).checked, p_earn: +$('#lye', el).value, p_value: +$('#lyv', el).value, p_min: +$('#lym', el).value }); await loadContext(); toast(tr('تم الحفظ')); } catch (e) { toast(e.message); } };
}
// the till: the customer's balance and the points to redeem
async function posLoyalty(page) {
  const box = $('#ploy', page), c = S.company || {}; if (!box) return;
  const draw = async () => { const party = $('#pcu', page).value; if (!c.loyalty_on || !party) { box.innerHTML = ''; return; }
    const bal = await db.rpc('loyalty_balance', { p_party: party }).catch(() => 0);
    box.innerHTML = `<div class="small">${esc(tr('نقاط العميل'))}: <b class="num">${bal}</b> (${money(r2(bal * n0(c.loyalty_value)))})</div>${bal >= n0(c.loyalty_min) ? field('نقاط للاستبدال في هذا البيع', inp('pts', '', `id="ppts" type="number" min="0" max="${bal}" step="1" placeholder="0"`)) : ''}`;
    if ($('#ppts', box)) $('#ppts', box).oninput = () => { const t = $('#pbar', page); if (t) t.dispatchEvent(new Event('ptschange')); }; };
  $('#pcu', page).addEventListener('change', draw); draw();
}
