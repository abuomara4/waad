'use strict';
/* ===== finance, part 2: cheques, foreign currencies, opening balances, petty cash (year-end closing lives in #/periods) ===== */
const CHQ_ST = { open: ['قائم', 'wait'], cleared: ['محصّل/مصروف', 'ok'], bounced: ['مرتجع', 'bad'], cancelled: ['ملغى', ''] };
const chqBadge = c => { const [t, k] = CHQ_ST[c.status] || [c.status, '']; return `<span class="badge ${k}">${esc(tr(c.direction === 'in' && c.status === 'cleared' ? 'محصّل' : c.direction === 'out' && c.status === 'cleared' ? 'مصروف' : t))}</span>`; };
const pEmp = e => e ? ((LANG === 'en' && e.full_name_en) || e.full_name) : '';
async function currencies(force) { if (force || !cache.cur) cache.cur = await db.get('currencies', Object.assign(C(), { order: 'code' })).catch(() => []); return cache.cur; }

/* ----- receive / issue a cheque (also opened from an invoice or bill) ----- */
async function chequeForm({ dir, party, doc, amount }) {
  const D = dir === 'in' ? DOCS.sales : DOCS.purchases;
  const [parties, open] = await Promise.all([db.get('parties', Object.assign(C(), { kind: 'eq.' + D.party, order: 'name' })), db.get(D.table, Object.assign(C(), { status: 'eq.posted', order: 'date', select: 'id,no,party_id,total,currency' }))]);
  const paid = await paidMap(D, open.map(o => o.id)), openDocs = open.filter(o => !o.currency && n0(o.total) - n0(paid[o.id]) > 0.001);
  if (!parties.length) return toast(dir === 'in' ? 'أضف عميلا أولا' : 'أضف موردا أولا');
  const d = modal(dir === 'in' ? 'شيك وارد من عميل' : 'شيك صادر لمورد', `<div class="fg">${field(dir === 'in' ? 'العميل' : 'المورد', `<select name="party" id="cqp">${parties.map(p => opt(p.id, p.name, party)).join('')}</select>`)}
      ${field('مقابل فاتورة', '<select name="doc" id="cqd"></select>')}${field('رقم الشيك', inp('cheque_no', '', 'dir="ltr" maxlength="30" required'))}${field('البنك', inp('bank', ''))}
      ${field('المبلغ', inp('amount', amount || '', 'type="number" step="0.01" min="0.01" id="cqa" required'))}
      ${field(dir === 'in' ? 'تاريخ الاستلام' : 'تاريخ التسليم', `<input type="date" name="issue_date" value="${today()}" max="${today()}">`)}${field('تاريخ الاستحقاق (المكتوب على الشيك)', `<input type="date" name="due_date" value="${today()}">`)}
      ${field('ملاحظات', inp('note'), 'wide')}</div>
    <p class="muted small">${esc(tr(dir === 'in' ? 'يُسدَّد العميل الآن، ويبقى المبلغ في «شيكات برسم التحصيل» حتى يحصّله البنك. إن ارتجع الشيك تعود المديونية.' : 'يُسدَّد المورد الآن، ويبقى المبلغ في «شيكات صادرة مؤجلة» حتى يصرفه البنك.'))}</p>`, {
    ok: 'حفظ الشيك', onOk: async f => { if (!(+f.amount > 0)) throw new Error('أدخل مبلغا أكبر من صفر');
      await db.rpc('cheque_save', { p_company: S.cid, p_doc: { direction: dir, party: f.party, [D.payKey]: f.doc || '', cheque_no: f.cheque_no, bank: blank(f.bank), amount: +f.amount, issue_date: f.issue_date, due_date: f.due_date, note: blank(f.note) } });
      toast(tr('حُفظ الشيك')); route(); } });
  const fill = () => { const p = $('#cqp', d).value; $('#cqd', d).innerHTML = `<option value="">${esc(tr('— دفعة على الحساب —'))}</option>` + openDocs.filter(o => o.party_id === p).map(o => opt(o.id, o.no + ' — ' + tr('متبقي') + ' ' + money(n0(o.total) - n0(paid[o.id])), doc)).join(''); };
  $('#cqp', d).onchange = () => { doc = null; fill(); }; fill();
  $('#cqd', d).onchange = e => { const o = openDocs.find(x => x.id === e.target.value); if (o) $('#cqa', d).value = r2(n0(o.total) - n0(paid[o.id])); };
}

/* ----- collect / pay a foreign-currency invoice or bill ----- */
async function fxPaymentForm({ key, doc, rem }) {
  const D = DOCS[key], [cash, curs] = await Promise.all([cashAccounts(), currencies()]), cur = curs.find(c => c.code === doc.currency) || {};
  const fxrem = r2(n0(doc.fx_total) * rem / n0(doc.total));
  modal((key === 'sales' ? tr('قبض') : tr('صرف')) + ' — ' + doc.no, `<div class="fg">${field(tr('المبلغ بالعملة') + ' (' + doc.currency + ')', inp('fx', fxrem, 'type="number" step="0.01" min="0.01" required'))}${field('سعر الصرف اليوم (ريال لكل وحدة)', inp('rate', cur.rate || doc.fx_rate, 'type="number" step="0.000001" min="0.000001" required'))}
      ${field(key === 'sales' ? 'إلى حساب' : 'من حساب', `<select name="acc">${cash.map(a => opt(a.code, a.name, '1120')).join('')}</select>`)}${field('التاريخ', `<input type="date" name="date" value="${today()}" max="${today()}">`)}${field('ملاحظات', inp('note'), 'wide')}</div>
    <p class="muted small">${esc(tr('سعر الفاتورة'))} <span class="num">${doc.fx_rate}</span> — ${esc(tr('الفرق بين سعر الفاتورة وسعر اليوم يُقيد ربحا (4950) أو خسارة (5950) فروقات عملة.'))}</p>`, {
    ok: 'حفظ السند', onOk: async f => { await db.rpc('record_payment_fx', { p_company: S.cid, p_doc: { direction: D.payDir, [D.payKey]: doc.id, fx_amount: +f.fx, fx_rate: +f.rate, account: f.acc, date: f.date, note: blank(f.note) } }); toast('حُفظ السند'); route(); } });
}

/* ----- cheques register ----- */
VIEWS['#/cheques'] = async (page, arg, q) => {
  const v = q.get('v') || 'due', inOk = can('sales'), outOk = can('purch');
  const [rows, parties, cash] = await Promise.all([db.get('cheques', Object.assign(C(), { order: 'due_date,no', limit: 500 })), db.get('parties', Object.assign(C(), { select: 'id,name' })), cashAccounts()]);
  const pm = {}; parties.forEach(p => pm[p.id] = p.name);
  const td = today(), soon = new Date(Date.now() + 7 * 864e5).toISOString().slice(0, 10);
  const pick = { due: rows.filter(c => c.status === 'open' && c.due_date <= soon), in: rows.filter(c => c.direction === 'in'), out: rows.filter(c => c.direction === 'out') }[v] || rows;
  const sum = (d) => rows.filter(c => c.status === 'open' && c.direction === d).reduce((a, c) => a + n0(c.amount), 0);
  page.innerHTML = `<div class="head"><div><h1>الشيكات</h1><div class="muted small">الشيكات الواردة من العملاء والصادرة للموردين، بتواريخ استحقاقها</div></div>
      <div class="row">${inOk ? '<button class="btn pri" id="nci">شيك وارد</button>' : ''}${outOk ? '<button class="btn" id="nco">شيك صادر</button>' : ''}</div></div>
    <div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(170px,1fr))"><div class="card"><div class="muted small">${esc(tr('برسم التحصيل'))}</div><b class="num">${money(sum('in'))}</b></div>
      <div class="card"><div class="muted small">${esc(tr('صادرة لم تُصرف'))}</div><b class="num">${money(sum('out'))}</b></div>
      <div class="card"><div class="muted small">${esc(tr('مستحقة خلال 7 أيام أو متأخرة'))}</div><b class="num ${rows.some(c => c.status === 'open' && c.due_date < td) ? 'bad' : ''}">${rows.filter(c => c.status === 'open' && c.due_date <= soon).length}</b></div></div>
    <div class="seg" style="margin-bottom:12px">${[['due', 'المستحقة قريبا'], ['in', 'الواردة'], ['out', 'الصادرة'], ['all', 'الكل']].map(t => `<a href="#/cheques?v=${t[0]}" class="${t[0] === v ? 'on' : ''}">${esc(tr(t[1]))}</a>`).join('')}</div>
    ${tbl([{ t: 'الرقم', h: c => `<span class="num">${esc(c.no)}</span>` }, { t: 'النوع', h: c => esc(tr(c.direction === 'in' ? 'وارد' : 'صادر')) }, { t: 'الطرف', h: c => esc(pm[c.party_id] || '') },
      { t: 'رقم الشيك', h: c => `<span class="num">${esc(c.cheque_no)}</span>${c.bank ? ` <span class="muted small">${esc(c.bank)}</span>` : ''}` },
      { t: 'الاستحقاق', h: c => `<span class="${c.status === 'open' && c.due_date < td ? 'bad' : ''}">${fdate(c.due_date)}</span>` }, { t: 'المبلغ', r: 1, h: c => money(c.amount) }, { t: 'الحالة', h: chqBadge }],
      pick, { empty: 'لا توجد شيكات', onRow: true })}`;
  if ($('#nci', page)) $('#nci', page).onclick = () => chequeForm({ dir: 'in' });
  if ($('#nco', page)) $('#nco', page).onclick = () => chequeForm({ dir: 'out' });
  bindRows(page, pick, c => {
    const ok = c.direction === 'in' ? inOk : outOk;
    const d = modal(tr(c.direction === 'in' ? 'شيك وارد' : 'شيك صادر') + ' ' + c.cheque_no, `<p>${esc(pm[c.party_id] || '')} · <b class="num">${money(c.amount)}</b> · ${esc(tr('الاستحقاق'))} ${fdate(c.due_date)} ${chqBadge(c)}</p>
      ${c.reason ? `<p class="muted small">${esc(c.reason)}</p>` : ''}${c.closed_on ? `<p class="muted small">${esc(tr('بتاريخ'))} ${fdate(c.closed_on)}</p>` : ''}
      ${ok && c.status === 'open' ? `<div class="fg">${field(c.direction === 'in' ? 'أُودع في حساب' : 'صُرف من حساب', `<select name="acc">${cash.map(a => opt(a.code, a.name, '1120')).join('')}</select>`)}${field('التاريخ', `<input type="date" name="date" value="${c.due_date <= td ? c.due_date : td}" max="${td}">`)}</div>
        <div class="row" style="margin-top:10px"><button type="button" class="btn pri" id="cqc">${esc(tr(c.direction === 'in' ? 'تحصيل' : 'تم الصرف'))}</button><button type="button" class="btn danger" id="cqr">${esc(tr(c.direction === 'in' ? 'ارتجع الشيك' : 'إلغاء الشيك'))}</button></div>`
      : ok && c.direction === 'in' && c.status === 'cleared' ? '<button type="button" class="btn danger sm" id="cqr">ارتجع بعد الإيداع</button>' : ''}`);
    if ($('#cqc', d)) $('#cqc', d).onclick = async () => { try { await db.rpc('cheque_clear', { p_id: c.id, p_date: $('[name=date]', d).value, p_account: $('[name=acc]', d).value }); d.close(); toast('تم'); route(); } catch (e) { showErr($('#merr', d), e); } };
    if ($('#cqr', d)) $('#cqr', d).onclick = () => { d.close(); modal(tr(c.direction === 'in' ? 'شيك مرتجع' : 'إلغاء شيك'), `<div class="fg">${field('السبب', inp('reason', '', 'required'), 'wide')}${field('التاريخ', `<input type="date" name="date" value="${td}" max="${td}">`)}</div>
        <p class="muted small">${esc(tr('تعود المديونية على الطرف، ويُعاد فتح الفاتورة المرتبطة.'))}</p>`, { ok: 'تأكيد', onOk: async f => { await db.rpc('cheque_return', { p_id: c.id, p_date: f.date, p_reason: f.reason }); toast('تم'); route(); } }); };
  });
};

/* ----- currencies ----- */
VIEWS['#/currencies'] = async page => {
  const rows = await currencies(true);
  page.innerHTML = `<div class="head"><div><h1>العملات</h1><div class="muted small">العملة الأساسية الريال السعودي. أضف العملات التي تبيع أو تشتري بها، وحدّث سعر الصرف عند الحاجة — كل فاتورة تحفظ سعرها</div></div>${can('coa') ? '<button class="btn pri" id="ncu">عملة جديدة</button>' : ''}</div>
    ${tbl([{ t: 'الرمز', h: c => `<span class="num">${esc(c.code)}</span>` }, { t: 'العملة', h: c => esc((LANG === 'en' && c.name_en) || c.name) }, { t: 'سعر الصرف (ريال)', r: 1, h: c => `<span class="num">${+c.rate}</span>` }, { t: 'آخر تحديث', h: c => fdate(c.updated_at) }], rows, { empty: 'لا توجد عملات — كل المعاملات بالريال', onRow: can('coa') })}`;
  const form = c => modal(c ? tr('تحديث') + ' ' + c.code : 'عملة جديدة', `<div class="fg">${field('الرمز (ISO)', inp('code', c ? c.code : '', `dir="ltr" maxlength="3" placeholder="USD" ${c ? 'readonly' : ''} required`))}${field('الاسم', inp('name', c && c.name, 'required'))}${enF('name_en', c && c.name_en)}${field('سعر الصرف: كم ريالا للوحدة', inp('rate', c && +c.rate, 'type="number" step="0.000001" min="0.000001" required'))}</div>`, {
    onOk: async f => { await db.rpc('currency_save', { p_company: S.cid, p_code: f.code, p_name: f.name, p_name_en: blank(f.name_en), p_rate: +f.rate }); cache.cur = null; toast('تم الحفظ'); route(); } });
  if ($('#ncu', page)) $('#ncu', page).onclick = () => form(null);
  if (can('coa')) bindRows(page, rows, form);
};

/* ----- opening balances from Excel ----- */
const OB_COLS = ['النوع', 'الرمز أو الاسم', 'مدين', 'دائن', 'المبلغ', 'تاريخ الاستحقاق', 'المرجع', 'الكمية', 'تكلفة الوحدة', 'تاريخ الصلاحية'];
const OB_T = { 'حساب': 'acc', 'account': 'acc', 'عميل': 'cust', 'customer': 'cust', 'مورد': 'supp', 'supplier': 'supp', 'صنف': 'item', 'item': 'item' };
VIEWS['#/opening'] = async page => {
  if (!has('owner', 'admin', 'finance')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const [[b]] = await Promise.all([db.get('opening_batches', Object.assign(C(), { status: 'eq.posted' }))]);
  const s = b && b.summary || {};
  page.innerHTML = `<div class="head"><div><h1>الأرصدة الافتتاحية</h1><div class="muted small">انقل أرصدتك من النظام السابق مرة واحدة: الحسابات، ومديونية كل عميل، ودائنية كل مورد، وكميات الأصناف وتكلفتها</div></div></div>
    ${b ? `<div class="card"><h2>${esc(tr('مُدخلة بتاريخ'))} ${fdate(b.date)}</h2><p>${esc(tr('حسابات'))} <b class="num">${s.accounts || 0}</b> · ${esc(tr('عملاء'))} <b class="num">${s.customers || 0}</b> (${money(s.ar || 0)}) · ${esc(tr('موردون'))} <b class="num">${s.suppliers || 0}</b> (${money(s.ap || 0)}) · ${esc(tr('أصناف'))} <b class="num">${s.items || 0}</b> (${money(s.stock || 0)})${n0(s.to_equity) ? ` · ${esc(tr('فرق مُرحّل إلى 3900'))} <b class="num">${money(s.to_equity)}</b>` : ''}</p>
        <button class="btn danger" id="obu">${esc(tr('إلغاء الأرصدة الافتتاحية'))}</button> <span class="muted small">${esc(tr('متاح فقط قبل تسجيل أي عملية أخرى.'))}</span></div>`
    : `<div class="card"><ol class="small" style="line-height:2"><li>${esc(tr('نزّل القالب واملأه: سطر لكل حساب أو عميل أو مورد أو صنف.'))}</li><li>${esc(tr('العملاء والموردون بأسمائهم — يُنشأ الطرف إن لم يكن موجودا. الأصناف برموزها (يجب أن تكون معرّفة).'))}</li>
        <li>${esc(tr('لا تكتب أرصدة العملاء (1200) والموردين (2100) والمخزون (1300) كأرقام حسابات — تُحسب من التفاصيل.'))}</li><li>${esc(tr('تاريخ الأرصدة يسبق أول عملية في النظام، وعادة نهاية السنة السابقة.'))}</li></ol>
        <div class="row"><button class="btn" id="obt">تنزيل القالب</button><label class="btn pri" style="margin:0;color:var(--prim-ink)">اختيار الملف<input type="file" id="obf" accept=".xlsx,.csv" hidden></label></div></div><div id="obp"></div>`}`;
  if ($('#obu', page)) $('#obu', page).onclick = async () => { if (!await confirmBox('إلغاء الأرصدة الافتتاحية', tr('يُعكس القيد وحركات المخزون، وتُلغى أرصدة العملاء والموردين الافتتاحية.'), 'إلغاء')) return;
    try { await db.rpc('opening_undo', { p_company: S.cid }); toast('تم'); route(); } catch (e) { toast(e.message); } };
  if (!$('#obt', page)) return;
  $('#obt', page).onclick = () => { const a = document.createElement('a'); a.href = URL.createObjectURL(templateXlsx([OB_COLS.map(c => tr(c)),
      [tr('حساب'), '1120', '50000', '', '', '', '', '', '', ''], [tr('حساب'), '3100', '', '100000', '', '', '', '', '', ''],
      [tr('عميل'), tr('مؤسسة مثال'), '', '', '12000', '2026-01-31', 'INV-88', '', '', ''], [tr('مورد'), tr('مورد مثال'), '', '', '4000', '', '', '', '', ''], [tr('صنف'), 'P-001', '', '', '', '', '', '20', '150', '']]));
    a.download = 'waad-opening-balances.xlsx'; document.body.appendChild(a); a.click(); a.remove(); };
  $('#obf', page).onchange = async e => {
    const file = e.target.files[0]; if (!file) return; const buf = await file.arrayBuffer();
    try {
      const raw = /\.csv$/i.test(file.name) ? readCsv(new TextDecoder().decode(buf)) : await readXlsx(buf);
      const rows = [], bad = [], num = v => v === '' || v == null ? 0 : +String(v).replace(/,/g, '');
      raw.slice(1).forEach((r, i) => { const c = k => String(r[k] == null ? '' : r[k]).trim(); if (!c(0) && !c(1)) return;
        const t = OB_T[c(0).toLowerCase()] || OB_T[c(0)]; if (!t) { bad.push((i + 2) + ': ' + tr('نوع غير معروف') + ' «' + c(0) + '»'); return; }
        if (t === 'acc') rows.push({ t, a: c(1), d: num(c(2)), c: num(c(3)) });
        else if (t === 'cust' || t === 'supp') rows.push({ t, name: c(1), amount: num(c(4)), due: c(5) || null, ref: c(6) || null });
        else rows.push({ t, code: c(1), qty: num(c(7)), cost: num(c(8)), expiry: c(9) || null });
        const l = rows[rows.length - 1]; if (Object.values(l).some(x => typeof x === 'number' && isNaN(x))) { rows.pop(); bad.push((i + 2) + ': ' + tr('رقم غير صحيح')); } });
      if (bad.length) throw new Error(bad.slice(0, 8).join(' · '));
      if (!rows.length) throw new Error('الملف فارغ');
      const dr = rows.reduce((a, r) => a + (r.t === 'acc' ? r.d : r.t === 'cust' ? r.amount : r.t === 'item' ? r.qty * r.cost : 0), 0), cr = rows.reduce((a, r) => a + (r.t === 'acc' ? r.c : r.t === 'supp' ? r.amount : 0), 0), diff = r2(dr - cr);
      const lastYear = (+today().slice(0, 4) - 1) + '-12-31', p = $('#obp', page);
      p.innerHTML = `<div class="card"><h2>${esc(tr('مراجعة قبل الترحيل'))}</h2>
        ${tbl([{ t: 'النوع', h: r => esc(tr({ acc: 'حساب', cust: 'عميل', supp: 'مورد', item: 'صنف' }[r.t])) }, { t: 'الرمز أو الاسم', h: r => esc(r.a || r.name || r.code) }, { t: 'مدين', r: 1, h: r => money(r.t === 'acc' ? r.d : r.t === 'cust' ? r.amount : r.t === 'item' ? r.qty * r.cost : 0) }, { t: 'دائن', r: 1, h: r => money(r.t === 'acc' ? r.c : r.t === 'supp' ? r.amount : 0) }], rows,
          { foot: `<td colspan="2">${esc(tr('الإجمالي'))} ${Math.abs(diff) < 0.005 ? `<span class="badge ok">${esc(tr('متوازن'))}</span>` : `<span class="badge bad">${esc(tr('الفرق'))} ${money(diff)}</span>`}</td><td class="r num">${money(dr)}</td><td class="r num">${money(cr)}</td>` })}
        <div class="fg" style="margin-top:12px">${field('تاريخ الأرصدة', `<input type="date" id="obd" value="${lastYear}" max="${today()}">`)}${Math.abs(diff) >= 0.005 ? `<label class="row small wide" style="gap:6px"><input type="checkbox" id="obe" style="width:auto">${esc(tr('رحّل الفرق إلى حساب «أرصدة افتتاحية» 3900 لمراجعته لاحقا'))}</label>` : ''}</div>
        <div class="row" style="margin-top:12px"><button class="btn pri" id="obg">${esc(tr('ترحيل الأرصدة'))}</button></div></div>`;
      $('#obg', p).onclick = async ev => { try { await busy(ev.target, () => db.rpc('opening_post', { p_company: S.cid, p_date: $('#obd', p).value, p_rows: rows, p_to_equity: !!($('#obe', p) && $('#obe', p).checked) })); toast(tr('رُحّلت الأرصدة الافتتاحية')); route(); } catch (er) { toast(er.message); } };
    } catch (er) { $('#obp', page).innerHTML = `<div class="err">${esc(er.message)}</div>`; }
  };
};

/* ----- petty cash (finance) ----- */
const pettyLines = (ls, am) => (ls || []).map(l => `${esc(l.desc)} — ${esc(am[l.a] || l.a)} <span class="num">${money(l.amount)}</span>${n0(l.vat) ? ` + ${esc(tr('ضريبة'))} <span class="num">${money(l.vat)}</span>` : ''}${l.ref ? ` <span class="muted">#${esc(l.ref)}</span>` : ''}`).join('<br>');
VIEWS['#/petty'] = async page => {
  if (!can('je')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const [funds, claims, em, cash, acc] = await Promise.all([db.rpc('petty_list', { p_company: S.cid }), db.get('petty_claims', Object.assign(C(), { order: 'created_at.desc', limit: 200 })), employeesMap(), cashAccounts(), accounts()]);
  const am = {}; acc.forEach(a => am[a.code] = a.name); const fm = {}; funds.forEach(f => fm[f.id] = f);
  const pend = claims.filter(c => c.status === 'pending'), en = id => esc(pEmp(em[id]) || '');
  page.innerHTML = `<div class="head"><div><h1>العُهد النقدية</h1><div class="muted small">صندوق صغير لموظف يصرف منه المصروفات النثرية، ثم يقدّم تسوية بالفواتير فتُعتمد وتُقيد على حساباتها</div></div><button class="btn pri" id="npf">عهدة جديدة</button></div>
    ${pend.length ? `<h2>${esc(tr('تسويات بانتظار الاعتماد'))} <span class="badge wait">${pend.length}</span></h2><div id="pcw">` + tbl([{ t: 'الرقم', h: c => `<span class="num">${esc(c.no)}</span>` }, { t: 'الموظف', h: c => en((fm[c.fund_id] || {}).employee_id) }, { t: 'التاريخ', h: c => fdate(c.date) }, { t: 'البنود', h: c => pettyLines(c.lines, am) }, { t: 'الإجمالي', r: 1, h: c => money(c.total) }], pend, { onRow: true }) + '</div><div style="height:14px"></div>' : ''}
    <h2>${esc(tr('العهد'))}</h2><div id="pfl">${tbl([{ t: 'الموظف', h: f => en(f.employee_id) }, { t: 'الحساب', h: f => `<span class="num">${esc(f.account_code)}</span>` }, { t: 'السقف', r: 1, h: f => money(f.ceiling) }, { t: 'الرصيد', r: 1, h: f => `<b class="num">${money(f.balance)}</b>` }, { t: 'معلّق', r: 1, h: f => n0(f.pending) ? money(f.pending) : '' },
      { t: 'الحالة', h: f => f.status === 'active' ? `<span class="badge ok">${esc(tr('قائمة'))}</span>` : `<span class="badge">${esc(tr('مقفلة'))} ${fdate(f.closed_on)}</span>` }], funds, { empty: 'لا توجد عهد نقدية', onRow: true })}</div>`;
  const ce = Object.values(em).filter(e => !e.end_date && !funds.some(f => f.employee_id === e.id && f.status === 'active'));
  $('#npf', page).onclick = () => modal('عهدة نقدية جديدة', `<div class="fg">${field('الموظف', `<select name="emp">${ce.map(e => opt(e.id, e.emp_no + ' — ' + pEmp(e))).join('')}</select>`)}${field('المبلغ المصروف الآن', inp('amount', '', 'type="number" step="0.01" min="0.01" required'))}
      ${field('سقف العهدة', inp('ceiling', '', 'type="number" step="0.01" min="0.01" placeholder="' + esc(tr('يساوي المبلغ إن تُرك فارغا')) + '"'))}${field('من حساب', `<select name="from">${cash.map(a => opt(a.code, a.name, '1110')).join('')}</select>`)}${field('التاريخ', `<input type="date" name="date" value="${today()}" max="${today()}">`)}</div>`, {
    ok: 'صرف العهدة', onOk: async f => { await db.rpc('petty_open', { p_company: S.cid, p_employee: f.emp, p_amount: +f.amount, p_from: f.from, p_ceiling: f.ceiling ? +f.ceiling : null, p_date: f.date }); cache.acc = null; toast('تم'); route(); } });
  if ($('#pcw', page)) bindRows($('#pcw', page), pend, c => { const d = modal(tr('تسوية') + ' ' + c.no, `<p>${en((fm[c.fund_id] || {}).employee_id)} · ${fdate(c.date)} · <b class="num">${money(c.total)}</b> · ${esc(tr('رصيد العهدة'))} <span class="num">${money((fm[c.fund_id] || {}).balance)}</span></p><p class="small">${pettyLines(c.lines, am)}</p>
      <div class="row"><button type="button" class="btn pri" id="pca">اعتماد وقيد</button><button type="button" class="btn danger" id="pcr">رفض</button></div>`);
    $('#pca', d).onclick = async () => { try { await db.rpc('petty_claim_decide', { p_id: c.id, p_approve: true }); d.close(); toast('اعتُمدت التسوية'); route(); } catch (e) { showErr($('#merr', d), e); } };
    $('#pcr', d).onclick = () => { d.close(); modal('رفض التسوية', field('السبب', inp('reason', '', 'required'), 'wide'), { ok: 'رفض', onOk: async f => { await db.rpc('petty_claim_decide', { p_id: c.id, p_approve: false, p_reason: f.reason }); toast('تم'); route(); } }); }; });
  bindRows($('#pfl', page), funds, f => {
    const fc = claims.filter(c => c.fund_id === f.id);
    const d = modal(pEmp(em[f.employee_id]) + ' — ' + f.account_code, `<p>${esc(tr('الرصيد'))} <b class="num">${money(f.balance)}</b> ${esc(tr('من سقف'))} <span class="num">${money(f.ceiling)}</span></p>
      ${tbl([{ t: 'الرقم', h: c => `<span class="num">${esc(c.no)}</span>` }, { t: 'التاريخ', h: c => fdate(c.date) }, { t: 'الإجمالي', r: 1, h: c => money(c.total) }, { t: 'الحالة', h: c => badge(c.status) }], fc, { empty: 'لا توجد تسويات' })}
      ${f.status === 'active' ? `<div class="row" style="margin-top:12px"><button type="button" class="btn sm" id="pfs">تسوية بالنيابة عنه</button><button type="button" class="btn sm" id="pft">تعزيز</button><button type="button" class="btn sm danger" id="pfc">إقفال العهدة</button></div>` : ''}`);
    if (f.status !== 'active') return;
    $('#pfs', d).onclick = () => { d.close(); pettyClaimForm(f.id); };
    $('#pft', d).onclick = () => { d.close(); modal('تعزيز العهدة', `<div class="fg">${field('المبلغ', inp('amount', r2(n0(f.ceiling) - n0(f.balance)) || '', 'type="number" step="0.01" min="0.01" required'))}${field('من حساب', `<select name="from">${cash.filter(a => a.code !== f.account_code).map(a => opt(a.code, a.name, '1110')).join('')}</select>`)}${field('التاريخ', `<input type="date" name="date" value="${today()}" max="${today()}">`)}</div>`, {
      ok: 'تعزيز', onOk: async x => { await db.rpc('petty_topup', { p_fund: f.id, p_amount: +x.amount, p_from: x.from, p_date: x.date }); toast('تم'); route(); } }); };
    $('#pfc', d).onclick = () => { d.close(); modal('إقفال العهدة', `<p>${esc(tr('يُعاد الرصيد المتبقي'))} <b class="num">${money(f.balance)}</b> ${esc(tr('إلى'))}:</p><div class="fg">${field('حساب', `<select name="to">${cash.filter(a => a.code !== f.account_code).map(a => opt(a.code, a.name, '1110')).join('')}</select>`)}${field('التاريخ', `<input type="date" name="date" value="${today()}" max="${today()}">`)}</div>`, {
      ok: 'إقفال', onOk: async x => { await db.rpc('petty_close', { p_fund: f.id, p_to: x.to, p_date: x.date }); toast('أُقفلت العهدة'); route(); } }); };
  });
};

/* ----- settlement form (the employee, or finance on his behalf) ----- */
async function pettyClaimForm(fund) {
  const acc = await db.rpc('petty_accounts', { p_company: S.cid }), ao = acc.map(a => opt(a.code, a.code + ' — ' + ((LANG === 'en' && a.name_en) || a.name), '5500')).join('');
  const row = () => `<tr><td><input data-k="desc" placeholder="${esc(tr('الوصف'))}" style="min-width:140px"></td><td><select data-k="a">${ao}</select></td><td><input data-k="amount" type="number" step="0.01" min="0" style="width:100px"></td>
    <td><input data-k="vat" type="number" step="0.01" min="0" style="width:80px"></td><td><input data-k="vat_no" dir="ltr" maxlength="15" placeholder="3…3" style="width:140px"></td><td><input data-k="ref" dir="ltr" style="width:90px"></td></tr>`;
  const d = modal('تسوية عهدة', `${field('التاريخ', `<input type="date" name="date" value="${today()}" max="${today()}">`)}<div class="tw"><table class="lines"><thead><tr><th>الوصف</th><th>الحساب</th><th>المبلغ قبل الضريبة</th><th>الضريبة</th><th>الرقم الضريبي للمورد</th><th>رقم الفاتورة</th></tr></thead><tbody id="pcl">${row()}${row()}</tbody></table></div>
    <button type="button" class="btn sm" id="pca2" style="margin-top:8px">+ بند</button><p class="muted small">${esc(tr('الضريبة تُسترد فقط إذا كانت الفاتورة ضريبية وفيها الرقم الضريبي للمورد. احتفظ بأصول الفواتير لتسليمها للمالية.'))}</p>`, {
    wide: true, ok: 'إرسال التسوية', onOk: async f => {
      const lines = $$('#pcl tr', d).map(tr0 => { const o = {}; $$('[data-k]', tr0).forEach(x => o[x.dataset.k] = x.value.trim()); return o; }).filter(l => l.desc || +l.amount)
        .map(l => ({ desc: l.desc, a: l.a, amount: +l.amount, vat: +l.vat || 0, vat_no: l.vat_no || null, ref: l.ref || null }));
      if (!lines.length) throw new Error('أضف بندا واحدا على الأقل');
      await db.rpc('petty_claim_submit', { p_fund: fund, p_date: f.date, p_lines: lines }); toast(tr('أُرسلت التسوية')); route(); } });
  $('#pca2', d).onclick = () => $('#pcl', d).insertAdjacentHTML('beforeend', row());
  $('#pcl', d).addEventListener('input', e => { if (e.target.dataset.k === 'amount') { const v = $('[data-k=vat]', e.target.closest('tr')); if (!v.dataset.touched) v.value = ''; } if (e.target.dataset.k === 'vat') e.target.dataset.touched = '1'; });
}

/* ----- my petty cash (employee) ----- */
VIEWS['#/mypetty'] = async page => {
  const funds = await db.rpc('petty_mine', { p_company: S.cid }), f = funds.find(x => x.status === 'active') || funds[0];
  if (!f) { page.innerHTML = `<div class="note">${esc(tr('لا توجد عهدة نقدية باسمك.'))}</div>`; return; }
  const [claims, acc] = await Promise.all([db.get('petty_claims', { fund_id: 'in.(' + funds.map(x => x.id).join(',') + ')', order: 'created_at.desc' }), db.rpc('petty_accounts', { p_company: S.cid }).catch(() => [])]);
  const am = {}; acc.forEach(a => am[a.code] = (LANG === 'en' && a.name_en) || a.name);
  page.innerHTML = `<div class="head"><div><h1>عهدتي النقدية</h1><div class="muted small">قدّم تسوية بما صرفته من العهدة مع أرقام الفواتير — تعتمدها المالية فيُخصم من رصيدك</div></div>${f.status === 'active' ? '<button class="btn pri" id="mpc">تسوية جديدة</button>' : ''}</div>
    <div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(170px,1fr))"><div class="card"><div class="muted small">${esc(tr('الرصيد لديك'))}</div><b class="num" style="font-size:22px">${money(f.balance)}</b></div>
      <div class="card"><div class="muted small">${esc(tr('بانتظار الاعتماد'))}</div><b class="num">${money(f.pending)}</b></div><div class="card"><div class="muted small">${esc(tr('سقف العهدة'))}</div><b class="num">${money(f.ceiling)}</b></div></div>
    ${tbl([{ t: 'الرقم', h: c => `<span class="num">${esc(c.no)}</span>` }, { t: 'التاريخ', h: c => fdate(c.date) }, { t: 'البنود', h: c => pettyLines(c.lines, am) }, { t: 'الإجمالي', r: 1, h: c => money(c.total) }, { t: 'الحالة', h: c => badge(c.status) + (c.reason ? ` <span class="muted small">${esc(c.reason)}</span>` : '') }], claims, { empty: 'لا توجد تسويات' })}`;
  if ($('#mpc', page)) $('#mpc', page).onclick = () => pettyClaimForm(f.id);
};

/* ----- notifications for finance: cheques falling due, petty cash claims waiting ----- */
async function finNotifs(add, safe) {
  if (!isFin()) return;
  const soon = new Date(Date.now() + 3 * 864e5).toISOString().slice(0, 10);
  const [chq, pc] = await Promise.all([can('sales') || can('purch') ? safe(db.get('cheques', Object.assign(C(), { status: 'eq.open', due_date: 'lte.' + soon, select: 'id,due_date' }))) : null,
    can('je') ? safe(db.get('petty_claims', Object.assign(C(), { status: 'eq.pending', select: 'id' }))) : null]);
  if (chq && chq.length) add(chq.length + ' شيكات مستحقة خلال 3 أيام أو متأخرة', '#/cheques?v=due', { hot: 1 });
  if (pc && pc.length) add(pc.length + ' تسويات عهد نقدية بانتظار الاعتماد', '#/petty', { hot: 1 });
}
