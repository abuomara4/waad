'use strict';
/* ===== finance additions: period closing, bank reconciliation, fixed assets, cost centers, budgets ===== */
async function ccList(force) { if (force || !cache.cc) cache.cc = await db.get('cost_centers', Object.assign(C(), { order: 'code' })).catch(() => []); return cache.cc; }
const ccName = c => c ? c.code + ' — ' + ((LANG === 'en' && c.name_en) || c.name) : '—';
/* cost-center picker — shown only once the company has cost centers */
async function ccField(sel) { const cs = (await ccList()).filter(c => c.active); if (!cs.length) return '';
  return field('مركز التكلفة', `<select name="cost_center"><option value="">${esc(tr('بدون'))}</option>${cs.map(c => opt(c.id, ccName(c), sel)).join('')}</select>`); }

/* ----- period closing ----- */
VIEWS['#/periods'] = async page => {
  if (!has('owner', 'admin', 'finance')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const [[co], log, fcs] = await Promise.all([db.get('companies', { id: 'eq.' + S.cid, select: 'books_closed_through' }), db.get('period_locks', Object.assign(C(), { order: 'at.desc', limit: 50 })), db.get('fiscal_closings', Object.assign(C(), { order: 'year_end.desc' })).catch(() => [])]);
  const lastFc = fcs.find(f => f.status === 'closed'), prevYe = (+today().slice(0, 4) - 1) + '-12-31';
  const lk = co && co.books_closed_through, lastMonthEnd = new Date(new Date(today().slice(0, 8) + '01').getTime() - 864e5).toISOString().slice(0, 10);
  page.innerHTML = `<div class="head"><div><h1>إقفال الفترات</h1><div class="muted small">بعد الإقفال لا يُسجَّل أي قيد أو حركة مخزون بتاريخ داخل الفترة المقفلة — يحمي الأرقام بعد تقديم الإقرار أو القوائم</div></div></div>
    <div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(280px,1fr))">
      <div class="card"><h2>${esc(tr('الحالة'))}</h2><p style="font-size:18px">${lk ? `${esc(tr('مقفلة حتى'))} <b class="num">${fdate(lk)}</b>` : esc(tr('لا توجد فترة مقفلة'))}</p></div>
      <div class="card"><h2>${esc(tr('إقفال حتى تاريخ'))}</h2><div class="row"><input type="date" id="pcd" value="${lastMonthEnd > (lk || '') ? lastMonthEnd : ''}" max="${new Date(Date.now() - 864e5).toISOString().slice(0, 10)}" style="width:auto"><button class="btn pri" id="pcb">${esc(tr('إقفال'))}</button></div>
        <p class="muted small">${esc(tr('عادةً نهاية الشهر أو الربع بعد تقديم إقرار ضريبة القيمة المضافة.'))}</p></div>
      ${has('owner') && lk ? `<div class="card"><h2>${esc(tr('إعادة فتح'))}</h2><p class="muted small">${esc(tr('للمالك فقط، مع ذكر السبب. يُسجَّل في السجل.'))}</p><button class="btn danger" id="prb">${esc(tr('إعادة فتح'))}</button></div>` : ''}</div>
    <h2>${esc(tr('إقفال السنة المالية'))}</h2><div class="card"><p class="muted small">${esc(tr('ينقل صافي ربح السنة (الإيرادات والمصروفات) إلى «الأرباح المبقاة» 3200 بقيد إقفال، ويقفل الدفاتر حتى نهاية السنة. قائمة الدخل للسنة المقفلة تبقى كما هي.'))}</p>
      <div class="row"><label style="margin:0">${esc(tr('نهاية السنة'))}</label><input type="date" id="yce" value="${lastFc && lastFc.year_end >= prevYe ? '' : prevYe}" max="${new Date(Date.now() - 864e5).toISOString().slice(0, 10)}" style="width:auto"><button class="btn pri" id="ycb">${esc(tr('إقفال السنة'))}</button>${has('owner') && lastFc ? `<button class="btn danger" id="ycr">${esc(tr('إعادة فتح آخر سنة'))}</button>` : ''}</div>
      ${fcs.length ? tbl([{ t: 'من', h: f => fdate(f.year_start) }, { t: 'إلى', h: f => fdate(f.year_end) }, { t: 'صافي الربح', r: 1, h: f => `<span class="num ${n0(f.net_profit) < 0 ? 'bad' : 'ok'}">${money(f.net_profit)}</span>` }, { t: 'الحالة', h: f => f.status === 'closed' ? `<span class="badge ok">${esc(tr('مقفلة'))}</span>` : `<span class="badge wait">${esc(tr('أُعيد فتحها'))}</span> <span class="muted small">${esc(f.reason || '')}</span>` }], fcs) : ''}</div>
    <h2>${esc(tr('السجل'))}</h2>${tbl([{ t: 'التاريخ', h: x => fdate(x.at) }, { t: 'الإجراء', h: x => x.action === 'close' ? `<span class="badge ok">${esc(tr('إقفال'))}</span>` : `<span class="badge wait">${esc(tr('إعادة فتح'))}</span>` },
      { t: 'حتى', h: x => fdate(x.through) }, { t: 'كان', h: x => fdate(x.previous) }, { t: 'السبب', h: x => esc(x.reason || '') }], log, { empty: 'لا يوجد سجل' })}`;
  $('#pcb', page).onclick = async () => { const d = $('#pcd', page).value; if (!d) return toast(tr('اختر التاريخ'));
    if (!await confirmBox('إقفال الفترة', tr('لن يُسمح بأي قيد أو حركة مخزون بتاريخ حتى') + ' ' + d + '. ' + tr('متابعة؟'), 'إقفال')) return;
    try { await db.rpc('period_close', { p_company: S.cid, p_through: d }); toast(tr('أُقفلت الفترة')); route(); } catch (e) { toast(e.message); } };
  $('#ycb', page).onclick = async () => { const d = $('#yce', page).value; if (!d) return toast(tr('اختر التاريخ'));
    if (!await confirmBox('إقفال السنة المالية', tr('يُرحَّل صافي ربح السنة المنتهية في') + ' ' + d + ' ' + tr('إلى الأرباح المبقاة وتُقفل الدفاتر حتى هذا التاريخ. متابعة؟'), 'إقفال السنة')) return;
    try { const r = await db.rpc('year_close', { p_company: S.cid, p_year_end: d }); toast(tr('أُقفلت السنة — صافي الربح') + ' ' + money(r.net_profit)); route(); } catch (e) { toast(e.message); } };
  if ($('#ycr', page)) $('#ycr', page).onclick = () => modal('إعادة فتح السنة المالية', `<p class="muted small">${esc(tr('يُعكس قيد الإقفال. لتسجيل تصحيحات داخل السنة أعد فتح الفترة أيضاً.'))}</p>${field('السبب', '<textarea name="reason" rows="2" required></textarea>', 'wide')}`, {
    ok: 'إعادة فتح', onOk: async f => { await db.rpc('year_reopen', { p_company: S.cid, p_reason: f.reason }); toast('تم'); route(); } });
  if ($('#prb', page)) $('#prb', page).onclick = () => modal('إعادة فتح الفترة', `<div class="fg">${field('مقفلة حتى (اتركه فارغاً لفتح كل شيء)', '<input type="date" name="through">')}${field('السبب', '<textarea name="reason" rows="2" required></textarea>', 'wide')}</div>`, {
    ok: 'إعادة فتح', onOk: async f => { await db.rpc('period_reopen', { p_company: S.cid, p_through: blank(f.through), p_reason: f.reason }); toast('تم'); route(); } });
};

/* ----- bank reconciliation ----- */
VIEWS['#/bankrec'] = async (page, arg) => {
  if (arg) return reconView(page, arg);
  const [rows, acc] = await Promise.all([db.get('bank_recons', Object.assign(C(), { order: 'statement_date.desc', limit: 100 })), accounts()]);
  const banks = acc.filter(a => a.parent_code === '1100' && !a.is_header), am = {}; acc.forEach(a => am[a.code] = a.name);
  page.innerHTML = `<div class="head"><div><h1>التسوية البنكية</h1><div class="muted small">طابق حركات البنك في الدفاتر مع كشف الحساب: حدد الحركات الظاهرة في الكشف حتى يتساوى الرصيدان</div></div>${can('je') ? '<button class="btn pri" id="nr">تسوية جديدة</button>' : ''}</div>
    ${tbl([{ t: 'الحساب', h: r => esc(r.account_code + ' — ' + (am[r.account_code] || '')) }, { t: 'تاريخ الكشف', h: r => fdate(r.statement_date) }, { t: 'رصيد الكشف', r: 1, h: r => money(r.statement_balance) },
      { t: 'الحالة', h: r => r.status === 'done' ? `<span class="badge ok">${esc(tr('مكتملة'))}</span>` : `<span class="badge wait">${esc(tr('مفتوحة'))}</span>` }], rows, { empty: 'لا توجد تسويات', onRow: true })}`;
  bindRows(page, rows, r => location.hash = '#/bankrec/' + r.id);
  if ($('#nr', page)) $('#nr', page).onclick = () => modal('تسوية جديدة', `<div class="fg">${field('الحساب', `<select name="acc">${banks.map(a => opt(a.code, a.code + ' — ' + a.name, '1120')).join('')}</select>`)}${field('تاريخ كشف الحساب', `<input type="date" name="date" value="${today()}" max="${today()}">`)}${field('الرصيد في الكشف', inp('bal', '', 'type="number" step="0.01" required'))}${field('ملاحظات', inp('note'), 'wide')}</div>`, {
    ok: 'بدء التسوية', onOk: async f => { if (f.bal === '') throw new Error('أدخل رصيد الكشف'); const id = await db.rpc('recon_start', { p_company: S.cid, p_account: f.acc, p_date: f.date, p_balance: +f.bal, p_note: blank(f.note) }); location.hash = '#/bankrec/' + id; } });
};
async function reconView(page, id) {
  const [[r], lines, acc, tt] = await Promise.all([db.get('bank_recons', { id: 'eq.' + id }), db.rpc('recon_lines', { p_id: id }), accounts(), db.rpc('recon_totals', { p_id: id })]);
  if (!r) throw new Error('التسوية غير موجودة');
  const open = r.status === 'open' && can('je'), an = (acc.find(a => a.code === r.account_code) || {}).name || '';
  const prior = n0(tt.prior), book = n0(tt.book);
  page.innerHTML = `<div class="head"><div><a href="#/bankrec" class="small">← التسوية البنكية</a><h1>${esc(r.account_code + ' — ' + an)} ${r.status === 'done' ? `<span class="badge ok">${esc(tr('مكتملة'))}</span>` : `<span class="badge wait">${esc(tr('مفتوحة'))}</span>`}</h1><div class="muted">${esc(tr('كشف بتاريخ'))} ${fdate(r.statement_date)}${r.note ? ' · ' + esc(r.note) : ''}</div></div>
      <div class="row">${open ? '<button class="btn" id="rsv">حفظ</button><button class="btn pri" id="rfin">إتمام التسوية</button><button class="btn danger" id="rcn">إلغاء</button>' : ''}<button class="btn" id="rprint">طباعة</button></div></div>
    <div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(160px,1fr))">
      <div class="card"><div class="muted small">${esc(tr('رصيد الكشف'))}</div><b class="num" style="font-size:20px">${money(r.statement_balance)}</b></div>
      <div class="card"><div class="muted small">${esc(tr('رصيد الدفاتر'))}</div><b class="num" style="font-size:20px">${money(book)}</b></div>
      <div class="card"><div class="muted small">${esc(tr('الرصيد المطابق'))}</div><b class="num" style="font-size:20px" id="rcb">0.00</b></div>
      <div class="card"><div class="muted small">${esc(tr('الفرق'))}</div><b class="num" style="font-size:20px" id="rdf">0.00</b></div></div>
    <div class="card"><div class="row" style="margin-bottom:8px">${open ? `<label class="row small" style="gap:6px"><input type="checkbox" id="rall" style="width:auto">${esc(tr('تحديد الكل'))}</label>` : ''}</div>
      <div class="tw"><table><thead><tr><th></th><th>التاريخ</th><th>القيد</th><th>البيان</th><th class="r">مدين (إيداع)</th><th class="r">دائن (سحب)</th></tr></thead><tbody>
      ${lines.map(l => `<tr><td><input type="checkbox" data-ln="${l.line_id}" ${l.cleared ? 'checked' : ''} ${open ? '' : 'disabled'} style="width:auto"></td><td>${fdate(l.date)}</td><td class="num">${esc(l.entry_no)}</td><td>${esc(l.memo)}</td>
        <td class="r num">${n0(l.debit) ? money(l.debit) : ''}</td><td class="r num">${n0(l.credit) ? money(l.credit) : ''}</td></tr>`).join('') || `<tr><td colspan="6" class="muted">${esc(tr('لا توجد حركات غير مطابقة'))}</td></tr>`}</tbody></table></div>
      <p class="muted small">${esc(tr('حركة في الكشف وليست في الدفاتر (رسوم أو عمولة أو فائدة)؟ سجّلها بقيد يدوي من «القيود اليومية» ثم عد هنا.'))}</p></div>`;
  const ln = new Map(lines.map(l => [String(l.line_id), l]));
  const calc = () => { const cb = prior + $$('[data-ln]', page).filter(c => c.checked).reduce((a, c) => { const l = ln.get(c.dataset.ln); return a + n0(l.debit) - n0(l.credit); }, 0);
    $('#rcb', page).textContent = money(cb); const df = r2(n0(r.statement_balance) - cb); $('#rdf', page).textContent = money(df); $('#rdf', page).className = 'num ' + (Math.abs(df) < 0.005 ? 'ok' : 'bad'); };
  page.addEventListener('change', e => { if (e.target.id === 'rall') $$('[data-ln]', page).forEach(c => c.checked = e.target.checked); calc(); }); calc();
  const sel = () => $$('[data-ln]', page).filter(c => c.checked).map(c => +c.dataset.ln);
  const on = (s, fn) => { const b = $(s, page); if (b) b.onclick = fn; };
  on('#rsv', async e => { await busy(e.target, () => db.rpc('recon_save', { p_id: id, p_lines: sel() })); toast('تم الحفظ'); });
  on('#rfin', async e => { try { await busy(e.target, async () => { await db.rpc('recon_save', { p_id: id, p_lines: sel() }); await db.rpc('recon_finish', { p_id: id }); }); toast(tr('اكتملت التسوية')); route(); } catch (er) { toast(er.message); } });
  on('#rcn', async () => { if (!await confirmBox('إلغاء التسوية', tr('تُحذف هذه التسوية المفتوحة وتعود حركاتها غير مطابقة.'), 'إلغاء التسوية')) return; await db.rpc('recon_cancel', { p_id: id }); location.hash = '#/bankrec'; });
  on('#rprint', () => printBlock(page, tr('تسوية بنكية') + ' — ' + r.account_code + ' — ' + fdate(r.statement_date)));
}

/* ----- fixed assets ----- */
VIEWS['#/assets'] = async page => {
  const [assets, dep, acc] = await Promise.all([db.get('fixed_assets', Object.assign(C(), { order: 'code' })), db.get('asset_depreciation', Object.assign(C(), { select: 'asset_id,period,amount' })), accounts()]);
  const ad = {}; let last = null; dep.forEach(d => { ad[d.asset_id] = (ad[d.asset_id] || 0) + n0(d.amount); if (!last || d.period > last) last = d.period; });
  const nextM = last ? new Date(new Date(last).setMonth(new Date(last).getMonth() + 1)).toISOString().slice(0, 7) : today().slice(0, 7);
  const act = assets.filter(a => a.status === 'active'), tot = k => act.reduce((s, a) => s + k(a), 0);
  page.innerHTML = `<div class="head"><div><h1>الأصول الثابتة</h1><div class="muted small">إهلاك بالقسط الثابت شهرياً: (التكلفة − القيمة المتبقية) ÷ العمر بالأشهر · آخر إهلاك: <span class="num">${last ? esc(last.slice(0, 7)) : '—'}</span></div></div>
      <div class="row">${can('je') ? `${last ? '<button class="btn" id="dun">إلغاء آخر إهلاك</button>' : ''}<button class="btn" id="drun">تشغيل إهلاك ${esc(nextM)}</button><button class="btn pri" id="na">أصل جديد</button>` : ''}</div></div>
    <div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(170px,1fr))"><div class="card"><div class="muted small">${esc(tr('التكلفة'))}</div><b class="num">${money(tot(a => n0(a.cost)))}</b></div>
      <div class="card"><div class="muted small">${esc(tr('مجمع الإهلاك'))}</div><b class="num">${money(tot(a => n0(ad[a.id])))}</b></div><div class="card"><div class="muted small">${esc(tr('القيمة الدفترية'))}</div><b class="num">${money(tot(a => n0(a.cost) - n0(ad[a.id])))}</b></div></div>
    ${tbl([{ t: 'الرمز', h: a => `<span class="num">${esc(a.code)}</span>` }, { t: 'الأصل', h: a => esc(a.name) + (a.category ? `<div class="small muted">${esc(a.category)}</div>` : '') }, { t: 'تاريخ الاقتناء', h: a => fdate(a.acquire_date) },
      { t: 'التكلفة', r: 1, h: a => money(a.cost) }, { t: 'مجمع الإهلاك', r: 1, h: a => money(ad[a.id] || 0) }, { t: 'القيمة الدفترية', r: 1, h: a => money(n0(a.cost) - n0(ad[a.id])) },
      { t: 'الحالة', h: a => a.status === 'active' ? `<span class="badge ok">${esc(tr('قيد الاستخدام'))}</span>` : `<span class="badge">${esc(tr('مستبعد'))} ${fdate(a.disposed_on)}</span>` }], assets, { empty: 'لا توجد أصول', onRow: true })}`;
  const fa = acc.filter(a => a.code === '1700' || a.parent_code === '1700'), cash = acc.filter(a => a.parent_code === '1100' && !a.is_header);
  const form = a => modal(a ? 'تعديل أصل' : 'أصل جديد', `<div class="fg">${field('الاسم', inp('name', a && a.name, 'required'))}${enF('name_en', a && a.name_en)}${field('الفئة', inp('category', a && a.category, 'placeholder="' + esc(tr('سيارات، أجهزة، أثاث…')) + '"'))}
      ${field('حساب الأصل', `<select name="asset_account">${fa.map(x => opt(x.code, x.code + ' — ' + x.name, a ? a.asset_account : '1700')).join('')}</select>`)}${field('تاريخ الاقتناء', `<input type="date" name="acquire_date" value="${a ? a.acquire_date : today()}" max="${today()}">`)}
      ${field('التكلفة', inp('cost', a && a.cost, 'type="number" step="0.01" min="0.01" required'))}${field('القيمة المتبقية في نهاية العمر', inp('salvage', a ? a.salvage : 0, 'type="number" step="0.01" min="0"'))}${field('العمر الإنتاجي (أشهر)', inp('life_months', a ? a.life_months : 60, 'type="number" min="1" max="600" required'))}
      ${a ? '' : field('سداد الشراء', `<select name="pay"><option value="">${esc(tr('مسجّل مسبقاً (فاتورة مورد على حساب الأصل)'))}</option>${cash.map(x => opt(x.code, tr('دُفع من') + ' ' + x.code + ' — ' + x.name)).join('')}</select>`, 'wide')}${field('ملاحظات', inp('note', a && a.note), 'wide')}</div>`, {
    onOk: async f => { await db.rpc('asset_save', { p_company: S.cid, p_doc: { id: a ? a.id : null, code: a ? a.code : null, name: f.name, name_en: blank(f.name_en), category: blank(f.category), asset_account: f.asset_account, acquire_date: f.acquire_date, cost: +f.cost, salvage: +f.salvage || 0, life_months: +f.life_months, note: blank(f.note), pay_account: blank(f.pay) } }); toast('تم الحفظ'); route(); } });
  if ($('#na', page)) $('#na', page).onclick = () => form(null);
  bindRows(page, assets, a => { const ds = dep.filter(d => d.asset_id === a.id).sort((x, y) => x.period < y.period ? -1 : 1), bv = n0(a.cost) - n0(ad[a.id]);
    const d = modal(a.code + ' — ' + a.name, `<p>${esc(tr('التكلفة'))} <b class="num">${money(a.cost)}</b> · ${esc(tr('القسط الشهري'))} <b class="num">${money(r2((n0(a.cost) - n0(a.salvage)) / a.life_months))}</b> · ${esc(tr('القيمة الدفترية'))} <b class="num">${money(bv)}</b></p>
      ${tbl([{ t: 'الشهر', h: x => `<span class="num">${esc(x.period.slice(0, 7))}</span>` }, { t: 'الإهلاك', r: 1, h: x => money(x.amount) }], ds, { empty: 'لم يبدأ الإهلاك' })}
      ${a.status === 'disposed' ? `<p class="small">${esc(tr('استُبعد في'))} ${fdate(a.disposed_on)} · ${esc(tr('مبلغ البيع'))} ${money(a.disposal_amount)}</p>` : can('je') ? '<div class="row" style="margin-top:12px"><button type="button" class="btn sm" id="aed">تعديل</button><button type="button" class="btn sm danger" id="adp">بيع أو استبعاد</button></div>' : ''}`);
    if ($('#aed', d)) $('#aed', d).onclick = () => { d.close(); form(a); };
    if ($('#adp', d)) $('#adp', d).onclick = () => { d.close(); modal('بيع أو استبعاد أصل', `<p class="small">${esc(tr('القيمة الدفترية'))} <b class="num">${money(bv)}</b></p><div class="fg">${field('التاريخ', `<input type="date" name="date" value="${today()}" max="${today()}">`)}${field('مبلغ البيع (صفر للإتلاف)', inp('amount', 0, 'type="number" step="0.01" min="0"'))}${field('استُلم في', `<select name="acc">${cash.map(x => opt(x.code, x.code + ' — ' + x.name, '1120')).join('')}</select>`)}</div>
      <p class="muted small">${esc(tr('الفرق بين مبلغ البيع والقيمة الدفترية يُقيد ربحاً (4900) أو خسارة (5900).'))}</p>`, { ok: 'تسجيل', onOk: async f => { const r = await db.rpc('asset_dispose', { p_id: a.id, p_date: f.date, p_amount: +f.amount || 0, p_account: f.acc }); toast((n0(r.gain) >= 0 ? tr('ربح') : tr('خسارة')) + ' ' + money(Math.abs(n0(r.gain)))); route(); } }); }; });
  if ($('#drun', page)) $('#drun', page).onclick = async e => { if (!await confirmBox('تشغيل الإهلاك', tr('يُقيد إهلاك شهر') + ' ' + nextM + ' ' + tr('لكل الأصول القائمة.'), 'تشغيل')) return;
    try { const r = await db.rpc('depreciation_run', { p_company: S.cid, p_month: nextM + '-01' }); toast(tr('أُهلك') + ' ' + r.assets + ' ' + tr('أصل') + ' — ' + money(r.total)); route(); } catch (er) { toast(er.message); } };
  if ($('#dun', page)) $('#dun', page).onclick = async () => { if (!await confirmBox('إلغاء آخر إهلاك', tr('يُعكس قيد آخر شهر مُهلك.'), 'إلغاء')) return; try { await db.rpc('depreciation_undo', { p_company: S.cid }); toast('تم'); route(); } catch (er) { toast(er.message); } };
};

/* ----- cost centers ----- */
VIEWS['#/costcenters'] = async (page, arg, q) => {
  const from = q.get('from') || today().slice(0, 4) + '-01-01', to = q.get('to') || today();
  const [cs, rep] = await Promise.all([ccList(true), can('reports') ? db.rpc('cc_report', { p_company: S.cid, p_from: from, p_to: to }) : []]);
  const rm = {}; rep.forEach(r => rm[r.cost_center_id || ''] = r);
  page.innerHTML = `<div class="head"><div><h1>مراكز التكلفة</h1><div class="muted small">فروع أو مشاريع أو أقسام: تُوسم بها بنود الإيرادات والمصروفات في الفواتير والقيود، ثم تُقرأ ربحية كل مركز</div></div>${can('coa') ? '<button class="btn pri" id="nc">مركز جديد</button>' : ''}</div>
    ${can('reports') ? `<form id="cf" class="row card" style="padding:12px"><label style="margin:0">من</label><input type="date" name="from" value="${from}" style="width:auto"><label style="margin:0">إلى</label><input type="date" name="to" value="${to}" style="width:auto"><button class="btn">عرض</button></form>` : ''}
    ${tbl([{ t: 'الرمز', h: c => `<span class="num">${esc(c.code)}</span>` }, { t: 'المركز', h: c => esc((LANG === 'en' && c.name_en) || c.name) + (c.active ? '' : ` <span class="badge">${esc(tr('موقوف'))}</span>`) },
      ...(can('reports') ? [{ t: 'الإيرادات', r: 1, h: c => money((rm[c.id] || {}).revenue || 0) }, { t: 'المصروفات', r: 1, h: c => money((rm[c.id] || {}).expense || 0) }, { t: 'الربح', r: 1, h: c => { const p = n0((rm[c.id] || {}).profit); return `<b class="num ${p < 0 ? 'bad' : 'ok'}">${money(p)}</b>`; } }] : [])],
      cs, { empty: 'لا توجد مراكز تكلفة', onRow: can('coa'), foot: can('reports') && rm[''] ? `<td colspan="2" class="muted">${esc(tr('بدون مركز تكلفة'))}</td><td class="r num">${money(rm[''].revenue)}</td><td class="r num">${money(rm[''].expense)}</td><td class="r num">${money(rm[''].profit)}</td>` : '' })}`;
  if ($('#cf', page)) $('#cf', page).onsubmit = e => { e.preventDefault(); const f = formData(e.target); location.hash = '#/costcenters?' + qs(f); };
  const form = c => modal(c ? 'تعديل مركز تكلفة' : 'مركز تكلفة جديد', `<div class="fg">${field('الرمز (حروف إنجليزية وأرقام)', inp('code', c ? c.code : '', 'dir="ltr" maxlength="12" required'))}${field('الاسم', inp('name', c && c.name, 'required'))}${enF('name_en', c && c.name_en)}
      ${c ? field('الحالة', `<select name="active">${opt('true', tr('نشط'), String(c.active))}${opt('false', tr('موقوف'), String(c.active))}</select>`) : ''}</div>`, {
    onOk: async f => { await db.rpc('cc_save', { p_company: S.cid, p_doc: { id: c ? c.id : null, code: f.code, name: f.name, name_en: blank(f.name_en), active: c ? f.active === 'true' : true } }); cache.cc = null; toast('تم الحفظ'); route(); } });
  if ($('#nc', page)) $('#nc', page).onclick = () => form(null);
  if (can('coa')) bindRows(page, cs, form);
};

/* ----- budgets ----- */
VIEWS['#/budgets'] = async (page, arg, q) => {
  const year = +(q.get('y')) || +today().slice(0, 4), cc = q.get('cc') || '', mode = q.get('m') === 'edit' && can('coa') ? 'edit' : 'report', tm = +(q.get('to')) || (year === +today().slice(0, 4) ? +today().slice(5, 7) : 12);
  const [acc, cs] = await Promise.all([accounts(), ccList()]);
  const pl = acc.filter(a => !a.is_header && (a.type === 'rev' || a.type === 'exp'));
  const MON = Array(12).fill(0);
  const head = `<div class="head"><div><h1>الموازنات</h1><div class="muted small">موازنة شهرية لكل حساب إيرادات ومصروفات، ومقارنتها بالفعلي</div></div>
      <div class="row">${can('coa') ? `<a class="btn ${mode === 'edit' ? 'pri' : ''}" href="#/budgets?${qs({ y: year, cc, m: 'edit' })}">${esc(tr('إعداد الموازنة'))}</a>` : ''}<a class="btn ${mode === 'report' ? 'pri' : ''}" href="#/budgets?${qs({ y: year, cc })}">${esc(tr('الموازنة مقابل الفعلي'))}</a></div></div>
    <form id="bf" class="row card" style="padding:12px"><label style="margin:0">${esc(tr('السنة'))}</label><input type="number" name="y" value="${year}" min="2000" max="2100" style="width:100px">
      ${cs.length ? `<select name="cc" style="width:auto"><option value="">${esc(tr('كل المنشأة'))}</option>${cs.map(c => opt(c.id, ccName(c), cc)).join('')}</select>` : ''}
      ${mode === 'report' ? `<label style="margin:0">${esc(tr('حتى شهر'))}</label><select name="to" style="width:auto">${MON.map((m, i) => opt(i + 1, String(i + 1).padStart(2, '0'), tm)).join('')}</select>` : '<input type="hidden" name="m" value="edit">'}<button class="btn">عرض</button>${mode === 'report' ? '<button type="button" class="btn" id="bprint">طباعة</button>' : ''}</form>`;
  if (mode === 'edit') {
    const rows = await db.get('budgets', Object.assign(C(), { year: 'eq.' + year, cost_center_id: cc ? 'eq.' + cc : 'is.null' }));
    const bm = {}; rows.forEach(r => bm[r.account_code] = r.months);
    page.innerHTML = head + `<div class="card"><div class="tw"><table class="lines"><thead><tr><th>الحساب</th><th>${esc(tr('سنوي ÷ 12'))}</th>${MON.map((m, i) => `<th class="num">${i + 1}</th>`).join('')}<th class="r">${esc(tr('السنة'))}</th></tr></thead><tbody>
      ${pl.map(a => `<tr data-a="${a.code}"><td style="min-width:200px">${esc(a.code + ' — ' + a.name)}</td><td><input data-y type="number" min="0" step="0.01" style="width:100px"></td>${Array.from({ length: 12 }, (_, i) => `<td><input data-m="${i}" type="number" min="0" step="0.01" value="${bm[a.code] ? n0(bm[a.code][i]) || '' : ''}" style="width:90px"></td>`).join('')}<td class="r num" data-t></td></tr>`).join('')}</tbody></table></div>
      <div class="row" style="margin-top:12px"><button class="btn pri" id="bsv">${esc(tr('حفظ الموازنة'))}</button></div></div>`;
    const tot = tr => { $('[data-t]', tr).textContent = money($$('[data-m]', tr).reduce((s, x) => s + n0(x.value), 0)); };
    $$('tr[data-a]', page).forEach(tot);
    page.addEventListener('input', e => { const tr = e.target.closest('tr[data-a]'); if (!tr) return; if (e.target.matches('[data-y]')) { const v = r2(n0(e.target.value) / 12); $$('[data-m]', tr).forEach(x => x.value = v || ''); } tot(tr); });
    $('#bsv', page).onclick = async e => { const data = $$('tr[data-a]', page).map(tr => ({ a: tr.dataset.a, m: $$('[data-m]', tr).map(x => n0(x.value)) })).filter(r => r.m.some(Boolean));
      try { await busy(e.target, async () => { const n = await db.rpc('budget_save', { p_company: S.cid, p_year: year, p_cc: cc || null, p_rows: data }); toast(tr('حُفظت الموازنة') + ' — ' + n + ' ' + tr('حساب')); }); } catch (er) { toast(er.message); } };
  } else {
    const rows = await db.rpc('budget_report', { p_company: S.cid, p_year: year, p_cc: cc || null, p_to_month: tm });
    const sum = (t, k) => rows.filter(r => r.type === t).reduce((s, r) => s + n0(r[k]), 0);
    page.innerHTML = head + `<div id="bb">${tbl([{ t: 'الحساب', h: r => esc(r.code + ' — ' + r.name) }, { t: 'النوع', h: r => r.type === 'rev' ? tr('إيراد') : tr('مصروف') }, { t: 'الموازنة', r: 1, h: r => money(r.budget) }, { t: 'الفعلي', r: 1, h: r => money(r.actual) },
      { t: 'الانحراف', r: 1, h: r => `<span class="num ${n0(r.variance) < 0 ? 'bad' : 'ok'}">${money(r.variance)}</span>` }, { t: '%', r: 1, h: r => n0(r.budget) ? Math.round(n0(r.actual) / n0(r.budget) * 100) + '%' : '—' }], rows,
      { empty: 'لا توجد موازنة ولا حركات لهذه السنة', foot: `<td colspan="2">${esc(tr('صافي الربح'))}</td><td class="r num">${money(sum('rev', 'budget') - sum('exp', 'budget'))}</td><td class="r num">${money(sum('rev', 'actual') - sum('exp', 'actual'))}</td><td colspan="2"></td>` })}
      <p class="muted small">${esc(tr('الانحراف الموجب جيد: إيراد فوق الموازنة أو مصروف تحتها.'))}</p></div>`;
    $('#bprint', page).onclick = () => printBlock($('#bb', page), tr('الموازنة مقابل الفعلي') + ' ' + year + ' — ' + tr('حتى شهر') + ' ' + tm);
  }
  $('#bf', page).onsubmit = e => { e.preventDefault(); location.hash = '#/budgets?' + qs(formData(e.target)); };
};
