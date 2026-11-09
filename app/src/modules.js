'use strict';
/* CRM (sales), requests for quotation and supplier rating (purchasing), serial search (inventory),
   job grades, medical insurance and the annual training plan (HR). */

/* ================= CRM: opportunities ================= */
const CRM_STAGES = { new: 'جديدة', contacted: 'تم التواصل', qualified: 'مؤهلة', proposal: 'عرض سعر', negotiation: 'تفاوض', won: 'مكسوبة', lost: 'خاسرة' };
const CRM_SRC = { website: 'الموقع الإلكتروني', referral: 'توصية', call: 'اتصال', social: 'وسائل التواصل', exhibition: 'معرض', campaign: 'حملة', other: 'أخرى' };
const CRM_ACT = { call: 'اتصال', meeting: 'اجتماع', email: 'بريد', whatsapp: 'واتساب', visit: 'زيارة', task: 'مهمة', note: 'ملاحظة' };
const crmBadge = s => `<span class="badge ${s === 'won' ? 'ok' : s === 'lost' ? 'bad' : s === 'proposal' || s === 'negotiation' ? 'info' : 'wait'}">${esc(tr(CRM_STAGES[s] || s))}</span>`;
VIEWS['#/crm'] = async (page, arg) => {
  if (!can('sales')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  if (arg) return crmView(page, arg);
  const [leads, sum, parties, acts, campaigns] = await Promise.all([db.get('crm_leads', Object.assign(C(), { order: 'updated_at.desc', limit: 500 })), db.rpc('crm_summary', { p_company: S.cid }),
    db.get('parties', Object.assign(C(), { kind: 'eq.customer', select: 'id,name' })),
    db.get('crm_activities', Object.assign(C(), { done: 'eq.false', due_at: 'lte.' + new Date(Date.now() + 864e5).toISOString(), order: 'due_at', limit: 50 })),
    db.get('marketing_campaigns', Object.assign(C(), { status: 'neq.cancelled', select: 'id,name', order: 'created_at.desc' })).catch(() => [])]);
  const pm = {}; parties.forEach(p => pm[p.id] = p.name); const lm = {}; leads.forEach(l => lm[l.id] = l);
  const sm = {}; sum.forEach(x => sm[x.stage] = x);
  const open = sum.filter(x => !['won', 'lost'].includes(x.stage)), pipe = open.reduce((a, x) => a + n0(x.value), 0), weighted = open.reduce((a, x) => a + n0(x.weighted), 0);
  const won = sm.won || { n: 0, value: 0 }, lost = sm.lost || { n: 0 }, rate = won.n + lost.n ? Math.round(100 * won.n / (won.n + lost.n)) : null;
  const view = LS.get('waad.crmv') || 'board', who = l => esc(l.party_id ? pm[l.party_id] || '' : l.prospect || '');
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الفرص والعملاء المحتملون'))}</h1></div><div class="row"><button class="btn" id="crv">${esc(tr(view === 'board' ? 'عرض كقائمة' : 'عرض كمراحل'))}</button><button class="btn pri" id="nop">${esc(tr('فرصة جديدة'))}</button></div></div>
    <div class="grid" style="margin-bottom:14px">
      <div class="card kpi"><div class="muted small">${esc(tr('فرص مفتوحة'))}</div><div class="v num">${open.reduce((a, x) => a + x.n, 0)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('قيمة الفرص المفتوحة'))}</div><div class="v num">${money(pipe)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('المتوقع (حسب الاحتمال)'))}</div><div class="v num">${money(weighted)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('نسبة الكسب'))}</div><div class="v num">${rate == null ? '—' : rate + '%'}</div></div></div>
    ${acts.length ? `<div class="card"><h2>${esc(tr('متابعات مستحقة'))}</h2>${tbl([{ t: 'الموعد', h: a => `<span class="num ${new Date(a.due_at) < new Date() ? 'bad' : ''}">${esc(String(a.due_at).slice(0, 16).replace('T', ' '))}</span>` },
      { t: 'النوع', h: a => esc(tr(CRM_ACT[a.kind])) }, { t: 'الفرصة', h: a => lm[a.lead_id] ? `<a href="#/crm/${a.lead_id}">${esc(lm[a.lead_id].title)}</a>` : '' }, { t: 'الملاحظة', k: 'note' }], acts)}</div>` : ''}
    ${view === 'board' ? `<div class="kanban">${Object.keys(CRM_STAGES).map(s => { const ls = leads.filter(l => l.stage === s);
        return `<div class="kcol"><div class="khead">${esc(tr(CRM_STAGES[s]))} <span class="num">${ls.length}</span><div class="small muted num">${money(ls.reduce((a, l) => a + n0(l.value), 0))}</div></div>
          ${ls.slice(0, 60).map(l => `<a class="kcard" href="#/crm/${l.id}"><b>${esc(l.title)}</b><div class="small">${who(l)}</div><div class="small muted"><span class="num">${money(l.value)}</span>${l.expected_close ? ' · <span class="num">' + esc(l.expected_close) + '</span>' : ''}</div></a>`).join('')}</div>`; }).join('')}</div>`
      : tbl([{ t: 'الرقم', h: l => `<span class="num">${esc(l.no)}</span>` }, { t: 'الفرصة', k: 'title' }, { t: 'العميل', h: who }, { t: 'المرحلة', h: l => crmBadge(l.stage) },
        { t: 'القيمة', r: 1, h: l => money(l.value) }, { t: 'الاحتمال', r: 1, h: l => l.probability + '%' }, { t: 'الإغلاق المتوقع', h: l => fdate(l.expected_close) }, { t: 'المصدر', h: l => esc(tr(CRM_SRC[l.source])) }], leads, { empty: 'لا توجد فرص بعد', onRow: true })}`;
  $('#crv', page).onclick = () => { LS.set('waad.crmv', view === 'board' ? 'list' : 'board'); route(); };
  $('#nop', page).onclick = () => leadForm(null, parties, campaigns);
  if (view !== 'board') bindRows(page, leads, l => location.hash = '#/crm/' + l.id);
};
function leadForm(l, parties, campaigns = []) {
  const v = l || { stage: 'new', source: 'other' };
  modal(l ? tr('تعديل الفرصة') : tr('فرصة جديدة'), `<div class="fg">${field('عنوان الفرصة', inp('title', v.title, 'required'), 'wide')}
      ${field('عميل حالي', `<select name="party_id"><option value="">${esc(tr('— عميل جديد محتمل —'))}</option>${parties.map(p => opt(p.id, p.name, v.party_id)).join('')}</select>`)}${field('اسم الجهة (للعميل المحتمل)', inp('prospect', v.prospect))}
      ${field('الشخص المسؤول', inp('contact_name', v.contact_name))}${field('الجوال', inp('phone', v.phone, 'dir="ltr"'))}${field('البريد', inp('email', v.email, 'type="email" dir="ltr"'))}
      ${field('المصدر', `<select name="source">${Object.entries(CRM_SRC).map(([k, t]) => opt(k, tr(t), v.source)).join('')}</select>`)}
      ${campaigns.length ? field('الحملة التسويقية', `<select name="campaign_id"><option value="">${esc(tr('— بلا حملة —'))}</option>${campaigns.map(c => opt(c.id, c.name, v.campaign_id)).join('')}</select>`) : ''}
      ${field('المرحلة', `<select name="stage">${Object.entries(CRM_STAGES).filter(([k]) => k !== 'lost').map(([k, t]) => opt(k, tr(t), v.stage)).join('')}</select>`)}
      ${field('القيمة المتوقعة (ريال)', inp('value', v.value, 'type="number" min="0" step="0.01"'))}${field('تاريخ الإغلاق المتوقع', `<input type="date" name="expected_close" value="${esc(v.expected_close || '')}">`)}
      ${field('ملاحظات', `<textarea name="note" rows="2">${esc(v.note || '')}</textarea>`, 'wide')}</div>`, {
    wide: true, onOk: async f => {
      if (!f.party_id && (f.prospect || '').trim().length < 2) throw new Error('اختر عميلاً أو اكتب اسم الجهة');
      const row = { title: f.title.trim(), party_id: blank(f.party_id), prospect: blank(f.prospect), contact_name: blank(f.contact_name), phone: blank(f.phone), email: blank(f.email),
        source: f.source, stage: f.stage, value: f.value === '' ? null : +f.value, expected_close: blank(f.expected_close), note: blank(f.note) };
      if (f.campaign_id !== undefined) row.campaign_id = blank(f.campaign_id);   // only when the picker was shown
      if (l) { await db.upd('crm_leads', { id: 'eq.' + l.id }, row); toast(tr('تم الحفظ')); route(); }
      else { const [n] = await db.ins('crm_leads', Object.assign(row, { company_id: S.cid })); location.hash = '#/crm/' + n.id; }
    } });
}
async function crmView(page, id) {
  const [[l], acts, parties, campaigns] = await Promise.all([db.get('crm_leads', { id: 'eq.' + id }), db.get('crm_activities', { lead_id: 'eq.' + id, order: 'created_at.desc' }), db.get('parties', Object.assign(C(), { kind: 'eq.customer', select: 'id,name' })),
    db.get('marketing_campaigns', Object.assign(C(), { status: 'neq.cancelled', select: 'id,name', order: 'created_at.desc' })).catch(() => [])]);
  if (!l) throw new Error('الفرصة غير موجودة');
  const pm = {}; parties.forEach(p => pm[p.id] = p.name); const closed = ['won', 'lost'].includes(l.stage);
  const [q] = l.quote_id ? await db.get('sales_orders', { id: 'eq.' + l.quote_id, select: 'id,no,status,total' }) : [];
  page.innerHTML = `<div class="head"><div><a href="#/crm" class="small">← ${esc(tr('الفرص'))}</a><h1>${esc(l.title)} ${crmBadge(l.stage)}</h1>
      <div class="muted"><span class="num">${esc(l.no)}</span> · ${esc(l.party_id ? pm[l.party_id] || '' : l.prospect || '')} · ${esc(tr(CRM_SRC[l.source]))}</div></div>
      <div class="row">${!closed ? `<button class="btn" id="ced">${esc(tr('تعديل'))}</button>${!l.quote_id ? `<button class="btn pri" id="cq">${esc(tr('تحويل إلى عرض سعر'))}</button>` : ''}<button class="btn" id="cwon">${esc(tr('كسبناها'))}</button><button class="btn danger" id="clost">${esc(tr('خسرناها'))}</button>` : `<button class="btn" id="creo">${esc(tr('إعادة فتح'))}</button>`}</div></div>
    ${!closed ? `<div class="steps">${Object.entries(CRM_STAGES).filter(([k]) => !['won', 'lost'].includes(k)).map(([k, t]) => `<button type="button" class="btn sm ${k === l.stage ? 'pri' : ''}" data-st="${k}">${esc(tr(t))}</button>`).join('')}</div>` : ''}
    <div class="grid" style="margin:12px 0">
      <div class="card kpi"><div class="muted small">${esc(tr('القيمة المتوقعة'))}</div><div class="v num">${money(l.value)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('الاحتمال'))}</div><div class="v num">${l.probability}%</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('الإغلاق المتوقع'))}</div><div class="v num">${fdate(l.expected_close)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('عرض السعر'))}</div><div class="v">${q ? `<a href="#/quotes/${q.id}" class="num">${esc(q.no)}</a> <span class="small num">${money(q.total)}</span>` : '—'}</div></div></div>
    <div class="card"><h2>${esc(tr('التواصل'))}</h2><p>${esc(l.contact_name || '—')} · <span class="num" dir="ltr">${esc(l.phone || '')}</span> · <span dir="ltr">${esc(l.email || '')}</span></p>
      ${l.phone ? `<p class="row" style="gap:6px"><a class="btn sm" href="tel:${esc(l.phone)}">${esc(tr('اتصال'))}</a><a class="btn sm" target="_blank" rel="noopener" href="https://wa.me/${esc(String(l.phone).replace(/^0/, '966').replace(/\D/g, ''))}">${esc(tr('واتساب'))}</a></p>` : ''}
      ${l.note ? `<p class="muted" style="white-space:pre-wrap">${esc(l.note)}</p>` : ''}${l.stage === 'lost' ? `<div class="note">${esc(tr('سبب الخسارة'))}: ${esc(l.lost_reason)}</div>` : ''}</div>
    <div class="card"><div class="row" style="justify-content:space-between"><h2>${esc(tr('المتابعات'))}</h2><button class="btn sm pri" id="nact">${esc(tr('إضافة متابعة'))}</button></div>
      ${tbl([{ t: 'النوع', h: a => esc(tr(CRM_ACT[a.kind])) }, { t: 'الموعد', h: a => a.due_at ? `<span class="num">${esc(String(a.due_at).slice(0, 16).replace('T', ' '))}</span>` : '—' }, { t: 'الملاحظة', k: 'note' },
        { t: 'الحالة', h: a => a.done ? `<span class="badge ok">${esc(tr('تمت'))}</span>` : `<button type="button" class="btn sm" data-done="${a.id}">${esc(tr('تمت'))}</button>` }], acts, { empty: 'لا توجد متابعات' })}</div>`;
  const on = (s, fn) => { const b = $(s, page); if (b) b.onclick = fn; };
  on('#ced', () => leadForm(l, parties, campaigns));
  $$('[data-st]', page).forEach(b => b.onclick = async () => { try { await db.upd('crm_leads', { id: 'eq.' + id }, { stage: b.dataset.st }); route(); } catch (e) { toast(e.message); } });
  on('#cwon', async () => { await db.upd('crm_leads', { id: 'eq.' + id }, { stage: 'won' }); toast(tr('تم')); route(); });
  on('#creo', async () => { await db.upd('crm_leads', { id: 'eq.' + id }, { stage: 'negotiation' }); route(); });
  on('#clost', () => modal(tr('خسرنا الفرصة'), field('السبب', inp('reason', '', 'required')), { ok: 'حفظ', onOk: async f => {
    if ((f.reason || '').length < 3) throw new Error('اكتب السبب'); await db.upd('crm_leads', { id: 'eq.' + id }, { stage: 'lost', lost_reason: f.reason }); route(); } }));
  on('#cq', async e => { try { await busy(e.target, async () => { const pid = await db.rpc('crm_make_customer', { p_lead: id }); location.hash = `#/quotes/new?party=${pid}&lead=${id}`; }); } catch (er) { toast(er.message); } });
  on('#nact', () => modal(tr('متابعة جديدة'), `<div class="fg">${field('النوع', `<select name="kind">${Object.entries(CRM_ACT).map(([k, t]) => opt(k, tr(t), 'call')).join('')}</select>`)}
      ${field('الموعد (اختياري)', '<input type="datetime-local" name="due">')}${field('الملاحظة', `<textarea name="note" rows="2" required></textarea>`, 'wide')}
      <label class="row wide" style="gap:6px"><input type="checkbox" name="done" style="width:auto"> ${esc(tr('تمت الآن'))}</label></div>`, { onOk: async f => {
    if ((f.note || '').length < 2) throw new Error('اكتب الملاحظة');
    await db.ins('crm_activities', { company_id: S.cid, lead_id: id, kind: f.kind, due_at: f.due ? new Date(f.due).toISOString() : null, note: f.note, done: !!f.done });
    if (l.stage === 'new') await db.upd('crm_leads', { id: 'eq.' + id }, { stage: 'contacted' }).catch(() => {});
    route(); } }));
  $$('[data-done]', page).forEach(b => b.onclick = async () => { await db.upd('crm_activities', { id: 'eq.' + b.dataset.done }, { done: true }); route(); });
}

/* ================= purchasing: requests for quotation ================= */
const RFQ_ST = { open: ['مفتوح', 'wait'], awarded: ['تمت الترسية', 'ok'], cancelled: ['ملغى', 'bad'] };
VIEWS['#/rfq'] = async (page, arg) => {
  if (!can('purch')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  if (arg === 'new') return rfqForm(page);
  if (arg) return rfqView(page, arg);
  const rows = await db.get('rfqs', Object.assign(C(), { order: 'date.desc,no.desc', limit: 300 }));
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('طلبات عروض الأسعار'))}</h1><div class="muted">${esc(tr('اطلب عروضاً من أكثر من مورد، قارنها، ورسِّ الأفضل بأمر شراء.'))}</div></div><a class="btn pri" href="#/rfq/new">${esc(tr('طلب عروض جديد'))}</a></div>
    ${tbl([{ t: 'الرقم', h: r => `<span class="num">${esc(r.no)}</span>` }, { t: 'التاريخ', h: r => fdate(r.date) }, { t: 'العنوان', k: 'title' }, { t: 'آخر موعد للرد', h: r => fdate(r.reply_by) },
      { t: 'الحالة', h: r => `<span class="badge ${RFQ_ST[r.status][1]}">${esc(tr(RFQ_ST[r.status][0]))}</span>` }], rows, { empty: 'لا توجد طلبات', onRow: true })}`;
  bindRows(page, rows, r => location.hash = '#/rfq/' + r.id);
};
async function rfqForm(page) {
  const L = await poLookups(), lines = [{}];
  const opts = L.items.filter(i => i.active !== false).map(i => opt('i:' + i.id, i.code + ' — ' + i.name)).join('') + `<optgroup label="${esc(tr('حسابات المصروفات'))}">${L.expAcc.map(a => opt('a:' + a.code, a.code + ' — ' + a.name)).join('')}</optgroup>`;
  page.innerHTML = `<div class="head"><div><a href="#/rfq" class="small">← ${esc(tr('طلبات عروض الأسعار'))}</a><h1>${esc(tr('طلب عروض جديد'))}</h1></div></div><form id="rf" class="card" novalidate>
    <div class="fg">${field('العنوان', inp('title', '', 'required'), 'wide')}${field('آخر موعد للرد', `<input type="date" name="reply_by" value="${addDays(today(), 7)}">`)}${field('ملاحظات للموردين', inp('note'), 'wide')}</div>
    <div class="tw" style="margin-top:12px"><table class="lines"><thead><tr><th>${esc(tr('صنف أو حساب مصروف'))}</th><th>${esc(tr('الوصف'))}</th><th>${esc(tr('الكمية'))}</th><th></th></tr></thead><tbody id="lb"></tbody></table></div>
    <div class="row" style="margin-top:10px"><button type="button" class="btn sm" id="al">+ ${esc(tr('بند'))}</button></div><div id="rerr"></div>
    <div class="row" style="margin-top:14px"><button class="btn pri" id="rs">${esc(tr('حفظ'))}</button><a class="btn" href="#/rfq">${esc(tr('إلغاء'))}</a></div></form>`;
  const draw = () => { $('#lb', page).innerHTML = lines.map((l, i) => `<tr data-i="${i}"><td style="min-width:220px"><select data-f="what"><option value="">—</option>${opts}</select></td><td><input data-f="desc" value="${esc(l.desc || '')}"></td><td><input data-f="qty" type="number" min="0" step="0.001" value="${esc(l.qty == null ? 1 : l.qty)}" style="width:90px"></td><td><button type="button" class="btn sm" data-rm aria-label="${esc(tr('حذف البند'))}">×</button></td></tr>`).join('');
    $$('tr', $('#lb', page)).forEach(t => { $('[data-f=what]', t).value = lines[+t.dataset.i].what || ''; }); };
  $('#lb', page).addEventListener('input', e => { const t = e.target.closest('tr'); if (t) lines[+t.dataset.i][e.target.dataset.f] = e.target.value; });
  $('#lb', page).addEventListener('click', e => { if (e.target.matches('[data-rm]')) { lines.splice(+e.target.closest('tr').dataset.i, 1); if (!lines.length) lines.push({}); draw(); } });
  $('#al', page).onclick = () => { lines.push({}); draw(); }; draw();
  $('#rf', page).onsubmit = async e => { e.preventDefault(); const f = formData(e.target);
    const ls = lines.filter(l => l.what).map(l => { const o = { qty: +(l.qty == null ? 1 : l.qty), desc: blank((l.desc || '').trim()) }; if (l.what.startsWith('i:')) o.item = l.what.slice(2); else o.account = l.what.slice(2); return o; });
    try { await busy($('#rs', page), async () => { const id = await db.rpc('rfq_save', { p_company: S.cid, p_doc: { title: f.title, reply_by: blank(f.reply_by), note: blank(f.note), lines: ls } }); location.hash = '#/rfq/' + id; }); } catch (er) { showErr($('#rerr', page), er); } };
}
async function rfqView(page, id) {
  const [[r], rl, qs, L, sc] = await Promise.all([db.get('rfqs', { id: 'eq.' + id }), db.get('rfq_lines', { rfq_id: 'eq.' + id, order: 'id' }), db.get('rfq_quotes', { rfq_id: 'eq.' + id, order: 'total' }), poLookups(), db.rpc('supplier_scorecard', { p_company: S.cid }).catch(() => [])]);
  if (!r) throw new Error('الطلب غير موجود');
  const ql = qs.length ? await db.get('rfq_quote_lines', { quote_id: 'in.(' + qs.map(q => q.id).join(',') + ')' }) : [];
  const price = (q, l) => (ql.find(x => x.quote_id === q.id && x.line_id === l.id) || {}).unit_price;
  const scm = {}; sc.forEach(x => scm[x.party_id] = x);
  const name = l => esc(l.item_id ? ((L.im[l.item_id] || {}).name || '') : l.account_code + ' — ' + ((L.am[l.account_code] || {}).name || '')) + (l.description ? `<div class="small muted">${esc(l.description)}</div>` : '');
  const best = l => Math.min(...qs.map(q => n0(price(q, l))).filter(x => x > 0));
  const cheapest = qs.length ? Math.min(...qs.map(q => n0(q.total))) : null, open = r.status === 'open';
  page.innerHTML = `<div class="head"><div><a href="#/rfq" class="small">← ${esc(tr('طلبات عروض الأسعار'))}</a><h1>${esc(r.title)} <span class="badge ${RFQ_ST[r.status][1]}">${esc(tr(RFQ_ST[r.status][0]))}</span></h1>
      <div class="muted"><span class="num">${esc(r.no)}</span> · ${fdate(r.date)}${r.reply_by ? ' · ' + esc(tr('آخر موعد للرد')) + ' ' + fdate(r.reply_by) : ''}${r.po_id ? ` · <a href="#/porders/${r.po_id}">${esc(tr('أمر الشراء'))}</a>` : ''}</div></div>
      <div class="row">${open ? `<button class="btn pri" id="nq">${esc(tr('إدخال عرض مورد'))}</button><button class="btn danger" id="rcn">${esc(tr('إلغاء الطلب'))}</button>` : ''}<button class="btn" id="rpr">${esc(tr('طباعة للموردين'))}</button></div></div>
    <div class="card"><h2>${esc(tr('مقارنة العروض'))}</h2>${qs.length ? `<div class="tw"><table><thead><tr><th>${esc(tr('البند'))}</th><th class="r">${esc(tr('الكمية'))}</th>${qs.map(q => `<th class="r">${esc((L.pm[q.party_id] || {}).name || '')}${scm[q.party_id] && scm[q.party_id].overall ? `<div class="small muted">★ <span class="num">${scm[q.party_id].overall}</span></div>` : ''}</th>`).join('')}</tr></thead><tbody>
      ${rl.map(l => `<tr><td>${name(l)}</td><td class="r num">${qtyTxt(l.qty)}</td>${qs.map(q => { const p = price(q, l); return `<td class="r num ${n0(p) === best(l) ? 'ok' : ''}">${money(p)}</td>`; }).join('')}</tr>`).join('')}
      <tr><td colspan="2"><b>${esc(tr('الإجمالي شامل الضريبة'))}</b></td>${qs.map(q => `<td class="r num ${n0(q.total) === cheapest ? 'ok' : ''}"><b>${money(q.total)}</b></td>`).join('')}</tr>
      <tr><td colspan="2">${esc(tr('مدة التوريد (يوم)'))}</td>${qs.map(q => `<td class="r num">${q.delivery_days == null ? '—' : q.delivery_days}</td>`).join('')}</tr>
      <tr><td colspan="2">${esc(tr('الالتزام بالمواعيد سابقاً'))}</td>${qs.map(q => `<td class="r num">${scm[q.party_id] && scm[q.party_id].on_time_pct != null ? scm[q.party_id].on_time_pct + '%' : '—'}</td>`).join('')}</tr>
      <tr><td colspan="2">${esc(tr('صالح حتى'))}</td>${qs.map(q => `<td class="r num">${fdate(q.valid_until)}</td>`).join('')}</tr>
      ${open ? `<tr><td colspan="2"></td>${qs.map(q => `<td class="r"><button type="button" class="btn sm" data-eq="${q.id}">${esc(tr('تعديل'))}</button> <button type="button" class="btn sm pri" data-aw="${q.id}">${esc(tr('ترسية'))}</button></td>`).join('')}</tr>`
        : `<tr><td colspan="2"></td>${qs.map(q => `<td class="r">${q.id === r.awarded_quote ? `<span class="badge ok">${esc(tr('العرض الفائز'))}</span>` : ''}</td>`).join('')}</tr>`}
      </tbody></table></div><p class="muted small">${esc(tr('الأخضر = أقل سعر للبند ولإجمالي العرض. الترسية تنشئ أمر شراء بأسعار العرض الفائز.'))}</p>` : `<div class="note">${esc(tr('لم تُدخل عروض بعد — أرسل الطلب للموردين ثم أدخل عرض كل مورد.'))}</div>`}</div>
    ${r.note ? `<div class="card"><p>${esc(r.note)}</p></div>` : ''}${r.reason ? `<div class="note">${esc(tr('سبب الإلغاء'))}: ${esc(r.reason)}</div>` : ''}`;
  const on = (s, fn) => { const b = $(s, page); if (b) b.onclick = fn; };
  const quoteForm = q => { const sup = L.parties.filter(p => p.active !== false && (!qs.some(x => x.party_id === p.id) || (q && q.party_id === p.id)));
    modal(tr('عرض مورد'), `<div class="fg">${field('المورد', `<select name="party" ${q ? 'disabled' : ''}>${sup.map(p => opt(p.id, p.name, q && q.party_id)).join('')}</select>`)}${field('تاريخ العرض', `<input type="date" name="received_on" value="${esc(q ? q.received_on : today())}">`)}
        ${field('صالح حتى', `<input type="date" name="valid_until" value="${esc(q && q.valid_until || '')}">`)}${field('مدة التوريد (يوم)', inp('delivery_days', q && q.delivery_days, 'type="number" min="0" max="365"'))}
        ${field('شروط الدفع والتسليم', inp('terms', q && q.terms), 'wide')}</div>
      <div class="tw"><table class="lines"><thead><tr><th>${esc(tr('البند'))}</th><th>${esc(tr('الكمية'))}</th><th>${esc(tr('سعر الوحدة قبل الضريبة'))}</th><th>${esc(tr('الضريبة'))}</th></tr></thead><tbody>
        ${rl.map(l => `<tr><td>${name(l)}</td><td class="num">${qtyTxt(l.qty)}</td><td><input name="p_${l.id}" type="number" min="0" step="0.01" value="${q ? esc(price(q, l) == null ? '' : price(q, l)) : ''}" required style="width:120px"></td>
          <td><select name="v_${l.id}" style="width:80px">${opt(15, '15%', q ? (ql.find(x => x.quote_id === q.id && x.line_id === l.id) || {}).vat_rate : 15)}${opt(0, '0%', q ? (ql.find(x => x.quote_id === q.id && x.line_id === l.id) || {}).vat_rate : 15)}</select></td></tr>`).join('')}</tbody></table></div>`, {
      wide: true, onOk: async f => {
        if (!q && !sup.length) throw new Error('أضف مورداً أولاً');
        await db.rpc('rfq_quote_save', { p_rfq: id, p_doc: { party: q ? q.party_id : f.party, received_on: f.received_on, valid_until: blank(f.valid_until), delivery_days: f.delivery_days === '' ? null : +f.delivery_days, terms: blank(f.terms),
          prices: rl.map(l => ({ line: l.id, price: f['p_' + l.id] === '' ? null : +f['p_' + l.id], vat: +f['v_' + l.id] })) } });
        toast(tr('تم الحفظ')); route(); } }); };
  on('#nq', () => quoteForm(null));
  $$('[data-eq]', page).forEach(b => b.onclick = () => quoteForm(qs.find(q => q.id === b.dataset.eq)));
  $$('[data-aw]', page).forEach(b => b.onclick = async () => { const q = qs.find(x => x.id === b.dataset.aw);
    if (!await confirmBox(tr('ترسية'), tr('ينشأ أمر شراء للمورد') + ' ' + ((L.pm[q.party_id] || {}).name || '') + ' ' + tr('بمبلغ') + ' ' + money(q.total) + '. ' + tr('متابعة؟'), 'ترسية')) return;
    try { const po = await db.rpc('rfq_award', { p_quote: q.id }); toast(tr('أُنشئ أمر الشراء')); location.hash = '#/porders/' + po; } catch (e) { toast(e.message); } });
  on('#rcn', () => modal(tr('إلغاء الطلب'), field('السبب', inp('reason', '', 'required')), { ok: 'إلغاء الطلب', onOk: async f => { await db.rpc('rfq_cancel', { p_rfq: id, p_reason: f.reason }); route(); } }));
  on('#rpr', () => { const w = document.createElement('div');
    w.innerHTML = invSheet(['طلب عرض سعر', 'Request for Quotation'], [[['الرقم', 'No.'], r.no], [['التاريخ', 'Date'], fdate(r.date)], [['آخر موعد للرد', 'Reply by'], fdate(r.reply_by)], [['الموضوع', 'Subject'], r.title]],
      [['البند', 'Item'], ['الكمية', 'Qty'], ['سعر الوحدة', 'Unit price'], ['الإجمالي', 'Total']], rl.map(l => [name(l), qtyTxt(l.qty), '', '']), [['اسم المورد وختمه', 'Supplier name & stamp'], ['التاريخ', 'Date']], r.note);
    printWith(w.firstElementChild, '@page{size:A4 portrait;margin:12mm}'); });
}
// rating a supplier after an order (from the purchase order screen)
function rateSupplier(po, party) {
  const stars = (n, t) => field(t, `<select name="${n}">${[5, 4, 3, 2, 1].map(k => opt(k, '★'.repeat(k), 5)).join('')}</select>`);
  modal(tr('تقييم المورد') + ': ' + (party ? party.name : ''), `<div class="fg">${stars('quality', 'الجودة')}${stars('delivery', 'الالتزام بالتوريد')}${stars('price', 'السعر')}${stars('service', 'الخدمة والتعامل')}${field('ملاحظة', inp('note'), 'wide')}</div>`, {
    onOk: async f => { await db.ins('supplier_ratings', { company_id: S.cid, party_id: po.party_id, po_id: po.id, quality: +f.quality, delivery: +f.delivery, price: +f.price, service: +f.service, note: blank(f.note) }); toast(tr('شكراً — حُفظ التقييم')); route(); } });
}

/* ================= inventory: where is a serial number? ================= */
VIEWS['#/serials'] = async (page, arg, q) => {
  const s = (q && q.get('s')) || '', items = await db.get('items', Object.assign(C(), { select: 'id,code,name' })), im = {}; items.forEach(i => im[i.id] = i);
  const rows = s ? await db.rpc('serial_find', { p_company: S.cid, p_serial: s }) : [];
  const docLink = (k, id) => !id ? '' : k === 'grn' ? `<a href="#/receipts/${id}">${esc(tr('استلام'))}</a>` : k === 'delivery' ? `<a href="#/deliveries/${id}">${esc(tr('إشعار تسليم'))}</a>` : `<a href="#/sales/${id}">${esc(tr('فاتورة'))}</a>`;
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الأرقام التسلسلية'))}</h1><div class="muted">${esc(tr('ابحث برقم تسلسلي لتعرف متى دخل ولمن بيع.'))}</div></div></div>
    <form id="snf" class="row" style="margin-bottom:12px"><input name="s" dir="ltr" value="${esc(s)}" placeholder="${esc(tr('الرقم التسلسلي'))}" style="max-width:320px"><button class="btn">${esc(tr('بحث'))}</button></form>
    ${s ? tbl([{ t: 'الرقم', h: r => `<span class="num" dir="ltr">${esc(r.serial)}</span>` }, { t: 'الصنف', h: r => esc((im[r.item_id] || {}).name || '') }, { t: 'الحالة', h: r => r.status === 'sold' ? `<span class="badge">${esc(tr('مبيع'))}</span>` : `<span class="badge ok">${esc(tr('في المخزون'))}</span>` },
      { t: 'الدخول', h: r => fdate(r.in_date) + ' ' + docLink(r.in_kind, r.in_id) }, { t: 'الخروج', h: r => r.out_date ? fdate(r.out_date) + ' ' + docLink(r.out_kind, r.out_id) : '—' }], rows, { empty: 'لا نتائج' }) : ''}`;
  $('#snf', page).onsubmit = e => { e.preventDefault(); location.hash = '#/serials?s=' + encodeURIComponent(e.target.s.value.trim()); };
};

/* ================= HR: job grades ================= */
VIEWS['#/grades'] = async page => {
  if (!isHR()) { page.innerHTML = '<div class="note">هذه الصفحة للموارد البشرية.</div>'; return; }
  const [gs, ex, em] = await Promise.all([db.get('job_grades', { company_id: 'eq.' + S.cid, order: 'code' }), db.rpc('grade_exceptions', { p_company: S.cid }), employeesMap(true)]);
  const cnt = {}; Object.values(em).filter(e => !e.end_date || e.end_date >= today()).forEach(e => { if (e.grade_id) cnt[e.grade_id] = (cnt[e.grade_id] || 0) + 1; });
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الدرجات الوظيفية'))}</h1><div class="muted">${esc(tr('سلّم رواتب بحد أدنى وأعلى للراتب الأساسي لكل درجة.'))}</div></div><button class="btn pri" id="ng">${esc(tr('درجة جديدة'))}</button></div>
    ${ex.length ? `<div class="note">${esc(tr('موظفون رواتبهم خارج حدود درجتهم'))}: ${ex.map(x => `<b>${esc((em[x.employee_id] || {}).full_name || '')}</b> <span class="num">${money(x.basic)}</span>`).join(' · ')}</div>` : ''}
    ${tbl([{ t: 'الرمز', h: g => `<span class="num">${esc(g.code)}</span>` }, { t: 'الدرجة', h: g => esc((LANG === 'en' && g.name_en) || g.name) + (g.active === false ? ` <span class="badge">${esc(tr('موقوفة'))}</span>` : '') },
      { t: 'أدنى أساسي', r: 1, h: g => money(g.min_basic) }, { t: 'أعلى أساسي', r: 1, h: g => money(g.max_basic) }, { t: 'بدل السكن', r: 1, h: g => g.housing_pct == null ? '—' : g.housing_pct + '%' },
      { t: 'بدل النقل', r: 1, h: g => g.transport == null ? '—' : money(g.transport) }, { t: 'درجة التذكرة', h: g => esc(g.ticket_class || '—') }, { t: 'الموظفون', r: 1, h: g => cnt[g.id] || 0 }], gs, { empty: 'لا توجد درجات بعد', onRow: true })}`;
  const form = g => modal(g ? tr('تعديل درجة') : tr('درجة جديدة'), `<div class="fg">${field('الرمز', inp('code', g && g.code, 'required dir="ltr"'))}${field('الاسم', inp('name', g && g.name, 'required'))}${enF('name_en', g && g.name_en)}
      ${field('أدنى راتب أساسي', inp('min', g && g.min_basic, 'type="number" min="0" step="0.01" required'))}${field('أعلى راتب أساسي', inp('max', g && g.max_basic, 'type="number" min="0" step="0.01" required'))}
      ${field('بدل السكن % من الأساسي', inp('hp', g && g.housing_pct, 'type="number" min="0" max="100" step="0.01"'))}${field('بدل النقل الشهري', inp('tp', g && g.transport, 'type="number" min="0" step="0.01"'))}
      ${field('درجة تذكرة السفر', inp('tc', g && g.ticket_class))}${g ? field('الحالة', `<label class="row" style="gap:6px"><input type="checkbox" name="active" ${g.active !== false ? 'checked' : ''} style="width:auto"> ${esc(tr('نشطة'))}</label>`) : ''}</div>`, {
    onOk: async f => { if (+f.max < +f.min) throw new Error('أعلى راتب أقل من أدناه');
      const row = { code: f.code.trim(), name: f.name.trim(), name_en: blank((f.name_en || '').trim()), min_basic: +f.min, max_basic: +f.max, housing_pct: f.hp === '' ? null : +f.hp, transport: f.tp === '' ? null : +f.tp, ticket_class: blank(f.tc) };
      if (g) { row.active = !!f.active; await db.upd('job_grades', { id: 'eq.' + g.id }, row); } else await db.ins('job_grades', Object.assign(row, { company_id: S.cid }));
      toast(tr('تم الحفظ')); route(); } });
  $('#ng', page).onclick = () => form(null); bindRows(page, gs, form);
};

/* ================= HR: medical insurance ================= */
const REL = { self: 'الموظف نفسه', spouse: 'الزوج/الزوجة', son: 'ابن', daughter: 'ابنة', father: 'الأب', mother: 'الأم' };
VIEWS['#/insurance'] = async page => {
  if (!isHR()) { page.innerHTML = '<div class="note">هذه الصفحة للموارد البشرية.</div>'; return; }
  const [pols, mem, al, em] = await Promise.all([db.get('insurance_policies', { company_id: 'eq.' + S.cid, order: 'end_date.desc' }), db.get('insurance_members', { company_id: 'eq.' + S.cid, order: 'created_at' }),
    db.rpc('insurance_alerts', { p_company: S.cid }), employeesMap(true)]);
  const pm = {}; pols.forEach(p => pm[p.id] = p); const act = mem.filter(m => m.status === 'active');
  const unins = al.filter(a => a.kind === 'uninsured'), ending = al.filter(a => a.kind === 'policy_ending');
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('التأمين الطبي'))}</h1><div class="muted">${esc(tr('نظام الضمان الصحي التعاوني يلزم صاحب العمل بالتأمين على العامل غير السعودي وأسرته، وعلى السعودي وأسرته في القطاع الخاص.'))}</div></div>
      <div class="row"><button class="btn" id="npol">${esc(tr('وثيقة جديدة'))}</button><button class="btn pri" id="nmem" ${pols.length ? '' : 'disabled'}>${esc(tr('إضافة مؤمَّن عليه'))}</button></div></div>
    ${unins.length ? `<div class="note">${esc(tr('موظفون بلا تغطية سارية'))} (<span class="num">${unins.length}</span>): ${unins.slice(0, 15).map(a => esc((em[a.employee_id] || {}).full_name || '')).join('، ')}${unins.length > 15 ? '…' : ''}</div>` : ''}
    ${ending.map(a => `<div class="note">${esc(tr('وثيقة تنتهي قريباً'))}: ${esc(pm[a.policy_id].provider)} <span class="num">${esc(pm[a.policy_id].policy_no)}</span> — <span class="num">${esc(a.end_date)}</span></div>`).join('')}
    <div class="grid" style="margin-bottom:12px"><div class="card kpi"><div class="muted small">${esc(tr('المؤمَّن عليهم'))}</div><div class="v num">${act.length}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('منهم تابعون'))}</div><div class="v num">${act.filter(m => m.relation !== 'self').length}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('القسط السنوي'))}</div><div class="v num">${money(act.reduce((a, m) => a + n0(m.premium), 0))}</div></div></div>
    <div class="card" id="polc"><h2>${esc(tr('الوثائق'))}</h2>${tbl([{ t: 'شركة التأمين', k: 'provider' }, { t: 'رقم الوثيقة', h: p => `<span class="num">${esc(p.policy_no)}</span>` }, { t: 'من', h: p => fdate(p.start_date) }, { t: 'إلى', h: p => `<span class="num ${p.end_date < today() ? 'bad' : ''}">${esc(p.end_date)}</span>` },
      { t: 'المؤمَّن عليهم', r: 1, h: p => act.filter(m => m.policy_id === p.id).length }], pols, { empty: 'لا توجد وثائق', onRow: true })}</div>
    <div class="card" id="memc"><h2>${esc(tr('المؤمَّن عليهم'))}</h2>${tbl([{ t: 'الموظف', h: m => esc((em[m.employee_id] || {}).full_name || '') }, { t: 'المؤمَّن عليه', h: m => m.relation === 'self' ? esc(tr('الموظف نفسه')) : esc(m.name) + ` <span class="small muted">(${esc(tr(REL[m.relation]))})</span>` },
      { t: 'الفئة', k: 'class' }, { t: 'رقم العضوية', h: m => `<span class="num">${esc(m.member_no || '—')}</span>` }, { t: 'الوثيقة', h: m => `<span class="num">${esc((pm[m.policy_id] || {}).policy_no || '')}</span>` },
      { t: 'القسط', r: 1, h: m => money(m.premium) }, { t: 'الحالة', h: m => m.status === 'active' ? `<span class="badge ok">${esc(tr('سارية'))}</span>` : `<span class="badge">${esc(tr('أُلغيت'))}</span> <span class="small num">${esc(m.end_date || '')}</span>` }], mem, { empty: 'لا يوجد مؤمَّن عليهم', onRow: true })}</div>`;
  const polForm = p => modal(p ? tr('تعديل وثيقة') : tr('وثيقة جديدة'), `<div class="fg">${field('شركة التأمين', inp('provider', p && p.provider, 'required'))}${field('رقم الوثيقة', inp('policy_no', p && p.policy_no, 'required dir="ltr"'))}
      ${field('بداية الوثيقة', `<input type="date" name="start" value="${esc(p ? p.start_date : today())}">`)}${field('نهاية الوثيقة', `<input type="date" name="end" value="${esc(p ? p.end_date : addDays(today(), 365))}">`)}${field('ملاحظات', inp('note', p && p.note), 'wide')}</div>`, {
    onOk: async f => { const row = { provider: f.provider.trim(), policy_no: f.policy_no.trim(), start_date: f.start, end_date: f.end, note: blank(f.note) };
      if (p) await db.upd('insurance_policies', { id: 'eq.' + p.id }, row); else await db.ins('insurance_policies', Object.assign(row, { company_id: S.cid })); toast(tr('تم الحفظ')); route(); } });
  const emps = Object.values(em).filter(e => !e.end_date || e.end_date >= today()).sort((a, b) => a.full_name.localeCompare(b.full_name, 'ar'));
  const memForm = m => modal(m ? tr('تعديل التغطية') : tr('إضافة مؤمَّن عليه'), `<div class="fg">${field('الوثيقة', `<select name="policy_id" ${m ? 'disabled' : ''}>${pols.filter(p => p.end_date >= today() || (m && m.policy_id === p.id)).map(p => opt(p.id, p.provider + ' — ' + p.policy_no, m && m.policy_id)).join('')}</select>`)}
      ${field('الموظف', `<select name="employee_id" ${m ? 'disabled' : ''}>${emps.map(e => opt(e.id, e.full_name + ' (' + e.emp_no + ')', m && m.employee_id)).join('')}</select>`)}
      ${field('المؤمَّن عليه', `<select name="relation" id="irel" ${m ? 'disabled' : ''}>${Object.entries(REL).map(([k, t]) => opt(k, tr(t), m ? m.relation : 'self')).join('')}</select>`)}
      <div id="idep" class="wide fg" ${m && m.relation !== 'self' ? '' : 'hidden'}>${field('اسم التابع', inp('name', m && m.name))}${field('تاريخ الميلاد', `<input type="date" name="birth_date" value="${esc(m && m.birth_date || '')}">`)}${field('رقم الهوية/الإقامة', inp('id_no', m && m.id_no, 'dir="ltr" maxlength="10"'))}</div>
      ${field('الفئة', inp('class', m ? m.class : 'B', 'maxlength="10"'))}${field('رقم العضوية', inp('member_no', m && m.member_no, 'dir="ltr"'))}${field('القسط السنوي', inp('premium', m && m.premium, 'type="number" min="0" step="0.01"'))}
      ${field('بداية التغطية', `<input type="date" name="start" value="${esc(m ? m.start_date : today())}">`)}${m ? field('الحالة', `<select name="status">${opt('active', tr('سارية'), m.status)}${opt('removed', tr('إلغاء التغطية'), m.status)}</select>`) : ''}</div>`, {
    wide: true, onOk: async f => {
      const row = { class: f.class || 'B', member_no: blank(f.member_no), premium: f.premium === '' ? null : +f.premium, start_date: f.start, name: blank(f.name), birth_date: blank(f.birth_date), id_no: blank(f.id_no) };
      if (m) { row.status = f.status; await db.upd('insurance_members', { id: 'eq.' + m.id }, row); }
      else await db.ins('insurance_members', Object.assign(row, { company_id: S.cid, policy_id: f.policy_id, employee_id: f.employee_id, relation: f.relation }));
      toast(tr('تم الحفظ')); route(); } });
  const relToggle = () => { const r = $('#irel'); if (r) $('#idep').hidden = r.value === 'self'; };
  $('#npol', page).onclick = () => polForm(null);
  $('#nmem', page).onclick = () => { memForm(null); $('#irel').onchange = relToggle; };
  bindRows($('#polc', page), pols, polForm);
  bindRows($('#memc', page), mem, m => { memForm(m); });
};

/* ================= HR: annual training plan ================= */
const TP_ST = { planned: ['مخطط', 'wait'], in_progress: ['قيد التنفيذ', 'info'], done: ['منفّذ', 'ok'], cancelled: ['ملغى', 'bad'] };
VIEWS['#/trainplan'] = async (page, arg, q) => {
  if (!(isHR() || has('finance') || has('manager'))) { page.innerHTML = '<div class="note">غير مصرح</div>'; return; }
  const y = +(q && q.get('y')) || new Date().getFullYear();
  const [rows, [sm], deps, trs] = await Promise.all([db.get('training_plans', { company_id: 'eq.' + S.cid, year: 'eq.' + y, order: 'quarter,title' }), db.rpc('training_plan_summary', { p_company: S.cid, p_year: y }),
    db.get('departments', { company_id: 'eq.' + S.cid, order: 'name' }), db.get('trainings', { company_id: 'eq.' + S.cid, order: 'start_date.desc', select: 'id,title,start_date,cost' })]);
  const dm = {}; deps.forEach(d => dm[d.id] = d); const tm = {}; trs.forEach(t => tm[t.id] = t); const edit = isHR();
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('خطة التدريب السنوية'))} <span class="num">${y}</span></h1></div>
      <div class="row"><a class="btn" href="#/trainplan?y=${y - 1}">${y - 1}</a><a class="btn" href="#/trainplan?y=${y + 1}">${y + 1}</a>${edit ? `<button class="btn pri" id="ntp">${esc(tr('برنامج جديد'))}</button>` : ''}</div></div>
    <div class="grid" style="margin-bottom:12px"><div class="card kpi"><div class="muted small">${esc(tr('البرامج المخططة'))}</div><div class="v num">${sm.planned}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('المنفّذ'))}</div><div class="v num">${sm.done}${sm.planned ? ' <span class="small">(' + Math.round(100 * sm.done / Math.max(1, sm.planned - sm.cancelled)) + '%)</span>' : ''}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('الميزانية'))}</div><div class="v num">${money(sm.budget)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('التكلفة الفعلية'))}</div><div class="v num ${n0(sm.actual) > n0(sm.budget) ? 'bad' : ''}">${money(sm.actual)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('ساعات التدريب'))}</div><div class="v num">${sm.hours}</div></div></div>
    ${tbl([{ t: 'الربع', h: r => r.quarter ? 'Q' + r.quarter : '—' }, { t: 'البرنامج', h: r => esc((LANG === 'en' && r.title_en) || r.title) }, { t: 'القسم / الفئة', h: r => esc([r.department_id && (dm[r.department_id] || {}).name, r.audience].filter(Boolean).join(' · ') || '—') },
      { t: 'المشاركون', r: 1, h: r => r.participants || '—' }, { t: 'الساعات', r: 1, h: r => r.hours || '—' }, { t: 'الميزانية', r: 1, h: r => money(r.budget) },
      { t: 'التنفيذ', h: r => r.training_id && tm[r.training_id] ? `<a href="#/training">${esc(tm[r.training_id].title)}</a> <span class="small num">${money(tm[r.training_id].cost)}</span>` : '—' },
      { t: 'الحالة', h: r => `<span class="badge ${TP_ST[r.status][1]}">${esc(tr(TP_ST[r.status][0]))}</span>` }], rows, { empty: 'لا توجد برامج لهذه السنة', onRow: edit })}`;
  const form = r => modal(r ? tr('تعديل برنامج') : tr('برنامج جديد'), `<div class="fg">${field('عنوان البرنامج', inp('title', r && r.title, 'required'), 'wide')}${enF('title_en', r && r.title_en, undefined, 'wide')}
      ${field('الربع', `<select name="quarter"><option value="">—</option>${[1, 2, 3, 4].map(k => opt(k, 'Q' + k, r && r.quarter)).join('')}</select>`)}${field('القسم', `<select name="dep"><option value="">${esc(tr('كل الأقسام'))}</option>${deps.map(d => opt(d.id, d.name, r && r.department_id)).join('')}</select>`)}
      ${field('الفئة المستهدفة', inp('audience', r && r.audience))}${field('عدد المشاركين', inp('participants', r && r.participants, 'type="number" min="1"'))}${field('الساعات', inp('hours', r && r.hours, 'type="number" min="0.5" step="0.5"'))}
      ${field('الميزانية', inp('budget', r && r.budget, 'type="number" min="0" step="0.01"'))}${field('الحالة', `<select name="status">${Object.entries(TP_ST).map(([k, [t]]) => opt(k, tr(t), r ? r.status : 'planned')).join('')}</select>`)}
      ${field('الدورة المنفّذة (من التدريب)', `<select name="training_id"><option value="">—</option>${trs.map(t => opt(t.id, t.title + ' · ' + fdate(t.start_date), r && r.training_id)).join('')}</select>`, 'wide')}</div>`, {
    wide: true, onOk: async f => { const row = { title: f.title.trim(), title_en: blank((f.title_en || '').trim()), quarter: f.quarter ? +f.quarter : null, department_id: blank(f.dep), audience: blank(f.audience),
      participants: f.participants ? +f.participants : null, hours: f.hours ? +f.hours : null, budget: f.budget === '' ? null : +f.budget, status: f.status, training_id: blank(f.training_id) };
      if (r) await db.upd('training_plans', { id: 'eq.' + r.id }, row); else await db.ins('training_plans', Object.assign(row, { company_id: S.cid, year: y }));
      toast(tr('تم الحفظ')); route(); } });
  if ($('#ntp', page)) $('#ntp', page).onclick = () => form(null);
  if (edit) bindRows(page, rows, form);
};
