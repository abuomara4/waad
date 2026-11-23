/* ===== Contracts and agreements «العقود والاتفاقيات» (0133): with customers (sales) or suppliers (purchases), term, value,
   billing, renewal notice, the signed copy, an alert before the end, and a recurring invoice made from a sales contract ===== */
const AG_KIND = { service: ['عقد خدمات', 'Services'], maintenance: ['عقد صيانة وتشغيل', 'Maintenance and operation'], lease: ['عقد إيجار', 'Lease'], supply: ['عقد توريد', 'Supply'], subscription: ['اشتراك', 'Subscription'], consulting: ['استشارات', 'Consulting'], other: ['أخرى', 'Other'] };
const AG_BILL = { none: ['بدون فوترة دورية', 'No periodic billing', 0], once: ['دفعة واحدة', 'One payment', 0], monthly: ['شهريا', 'Monthly', 1], quarterly: ['كل 3 أشهر', 'Every 3 months', 3], semiannual: ['كل 6 أشهر', 'Every 6 months', 6], annual: ['سنويا', 'Yearly', 12] };
const AG_ST = { draft: ['مسودة', ''], active: ['ساري', 'ok'], ended: ['منتهٍ', ''], terminated: ['مُنهى', 'bad'] };
const agT = m => m[LANG === 'en' ? 1 : 0];
const agCan = () => can('sales') || can('purch');
// days left, and the alert state of an active contract with an end date
function agLeft(a) { if (!a.end_date || a.status !== 'active') return null; return Math.round((new Date(a.end_date + 'T12:00:00Z') - new Date(today() + 'T12:00:00Z')) / 864e5); }
function agBadge(a) { const d = agLeft(a); if (d == null) return `<span class="badge ${AG_ST[a.status][1]}">${esc(agT(AG_ST[a.status]))}</span>`;
  if (d < 0) return `<span class="badge bad">${esc(tr('انتهى ولم يُجدد'))}</span>`;
  return d <= Math.max(a.notice_days, 7) ? `<span class="badge wait">${esc(tr('ينتهي خلال'))} <span class="num">${d}</span> ${esc(tr('يوما'))}</span>` : `<span class="badge ok">${esc(agT(AG_ST.active))}</span>`; }
// per-period amount from the contract value and its billing (equal instalments over the term)
function agPeriodAmount(a) { const per = AG_BILL[a.billing] ? AG_BILL[a.billing][2] : 0; if (!per || !a.end_date || !+a.value) return 0;
  const months = Math.max(1, Math.round((new Date(a.end_date + 'T12:00:00Z') - new Date(a.start_date + 'T12:00:00Z')) / 864e5 / 30.44)); return r2(+a.value / Math.max(1, Math.round(months / per))); }

VIEWS['#/agreements'] = async (page, arg, q) => {
  if (!agCan()) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للمبيعات والمشتريات والمالية.'))}</div>`; return; }
  const p = new URLSearchParams(location.hash.split('?')[1] || ''), dir = p.get('d') || '', st = p.get('s') || 'live', qq = (p.get('q') || '').trim();
  const [rows, parties, em] = await Promise.all([db.get('agreements', { company_id: 'eq.' + S.cid, order: 'end_date.asc.nullslast,created_at.desc' }),
    db.get('parties', { company_id: 'eq.' + S.cid, select: 'id,name,kind', order: 'name' }).catch(() => []), employeesMap().catch(() => ({}))]);
  const pm = {}; parties.forEach(x => pm[x.id] = x);
  const due = rows.filter(a => { const d = agLeft(a); return d != null && d <= Math.max(a.notice_days, 7); });
  const shown = rows.filter(a => (!dir || a.direction === dir) && (st === 'all' || (st === 'live' ? ['active', 'draft'].includes(a.status) : st === 'due' ? due.includes(a) : a.status === st))
    && (!qq || [a.no, a.title, (pm[a.party_id] || {}).name].join(' ').toLowerCase().includes(qq.toLowerCase())));
  const act = rows.filter(a => a.status === 'active'), sumV = l => l.reduce((t, a) => t + n0(a.value), 0);
  const link = (k, v) => { const n = new URLSearchParams({ d: dir, s: st, q: qq }); n.set(k, v); return '#/agreements?' + n.toString(); };
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('العقود والاتفاقيات'))}</h1><div class="muted">${esc(tr('عقود الخدمات والصيانة والإيجار والتوريد مع العملاء والموردين: المدة والقيمة والفوترة وتنبيه قبل الانتهاء.'))}</div></div>
      <button class="btn pri" id="agn">${esc(tr('+ عقد'))}</button></div>
    <div class="grid">${[['عقود سارية', act.length], ['قيمة عقود البيع السارية', money(sumV(act.filter(a => a.direction === 'sale')))], ['قيمة عقود الشراء السارية', money(sumV(act.filter(a => a.direction === 'purchase')))], ['تنتهي قريبا أو انتهت', due.length]]
      .map(([t, v], i) => `<a class="card kpi" href="${i === 3 ? link('s', 'due') : '#/agreements'}"><div class="muted small">${esc(tr(t))}</div><div class="v num ${i === 3 && due.length ? 'bad' : ''}">${v}</div></a>`).join('')}</div>
    <div class="card"><div class="row" style="gap:8px;flex-wrap:wrap;margin-bottom:10px"><input id="agq" placeholder="${esc(tr('بحث برقم العقد أو العنوان أو الطرف'))}" value="${esc(qq)}" style="flex:1;min-width:180px">
      <select id="agd" style="width:auto">${opt('', tr('البيع والشراء'), dir)}${opt('sale', tr('عقود مع العملاء'), dir)}${opt('purchase', tr('عقود مع الموردين'), dir)}</select>
      <select id="ags" style="width:auto">${opt('live', tr('السارية والمسودات'), st)}${opt('due', tr('تنتهي قريبا'), st)}${opt('ended', tr('المنتهية'), st)}${opt('terminated', tr('المُنهاة'), st)}${opt('all', tr('الكل'), st)}</select></div>
    ${tbl([{ t: 'العقد', h: a => `<b class="num">${esc(a.no || '')}</b> <span data-nt>${esc(a.title)}</span><div class="small muted">${esc(agT(AG_KIND[a.kind]))} · ${esc(tr(a.direction === 'sale' ? 'مع عميل' : 'مع مورد'))}</div>` },
      { t: 'الطرف', h: a => `<span data-nt>${esc((pm[a.party_id] || {}).name || '')}</span>` }, { t: 'المدة', h: a => `${fdate(a.start_date)} – ${a.end_date ? fdate(a.end_date) : esc(tr('مفتوح'))}` },
      { t: 'القيمة', r: 1, h: a => +a.value ? money(a.value) : '—' }, { t: 'الفوترة', h: a => esc(agT(AG_BILL[a.billing])) + (a.recurring_id ? ` <span class="badge info">${esc(tr('مرتبط بفاتورة متكررة'))}</span>` : '') },
      { t: 'الحالة', h: a => agBadge(a) }], shown, { empty: 'لا توجد عقود', onRow: true })}</div>`;
  bindRows(page, shown, a => agForm(a, parties, em));
  $('#agn', page).onclick = () => agForm(null, parties, em);
  const go = (k, v) => location.hash = link(k, v);
  $('#agd', page).onchange = e => go('d', e.target.value); $('#ags', page).onchange = e => go('s', e.target.value);
  $('#agq', page).onkeydown = e => { if (e.key === 'Enter') go('q', e.target.value.trim()); };
};

function agForm(a, parties, em) {
  const v = a || { direction: can('sales') ? 'sale' : 'purchase', kind: 'service', start_date: today(), billing: 'none', notice_days: 30, status: 'active', auto_renew: false, value: '' };
  const dirOk = d => can(d === 'sale' ? 'sales' : 'purch'), emps = Object.values(em || {}).filter(e => !e.end_date || e.end_date >= today());
  const partyOpts = d => `<option value="">—</option>` + parties.filter(x => x.kind === (d === 'sale' ? 'customer' : 'supplier')).map(x => opt(x.id, x.name, v.party_id)).join('');
  const m = modal(a ? tr('العقد') + ' ' + (a.no || '') : tr('عقد جديد'), `<div class="fg">
      ${field('نوع العلاقة', `<select name="dir" ${a ? 'disabled' : ''}>${['sale', 'purchase'].filter(dirOk).map(d => opt(d, tr(d === 'sale' ? 'عقد مع عميل (بيع)' : 'عقد مع مورد (شراء)'), v.direction)).join('')}</select>`)}
      ${field('الطرف', `<select name="party" required>${partyOpts(v.direction)}</select>`)}
      ${field('عنوان العقد', inp('title', v.title, 'required maxlength="150"'), 'wide')}
      ${field('نوع العقد', `<select name="kind">${Object.keys(AG_KIND).map(k => opt(k, agT(AG_KIND[k]), v.kind)).join('')}</select>`)}
      ${field('الحالة', `<select name="st">${Object.keys(AG_ST).map(k => opt(k, agT(AG_ST[k]), v.status)).join('')}</select>`)}
      ${field('تاريخ البداية', `<input type="date" name="from" value="${esc(v.start_date || '')}" required>`)}${field('تاريخ النهاية (اختياري)', `<input type="date" name="to" value="${esc(v.end_date || '')}">`)}
      ${field('قيمة العقد قبل الضريبة', inp('value', v.value, 'type="number" min="0" step="0.01"'))}${field('الفوترة', `<select name="bill">${Object.keys(AG_BILL).map(k => opt(k, agT(AG_BILL[k]), v.billing)).join('')}</select>`)}
      ${field('التنبيه قبل الانتهاء بـ (يوما)', inp('notice', v.notice_days, 'type="number" min="0" max="365"'))}
      ${field('الموظف المسؤول', `<select name="owner"><option value="">—</option>${emps.map(e => opt(e.id, e.full_name, v.owner_id)).join('')}</select>`)}
      <label class="row small wide" style="gap:6px"><input type="checkbox" name="renew" style="width:auto"${v.auto_renew ? ' checked' : ''}> ${esc(tr('يتجدد تلقائيا ما لم يُشعر أحد الطرفين'))}</label>
      ${field('ملاحظات وشروط مهمة', `<textarea name="notes" rows="3" maxlength="2000">${esc(v.notes || '')}</textarea>`, 'wide')}
      ${a ? `<div class="wide" id="agf" style="border-top:1px solid var(--line3);padding-top:10px"></div>
        <div class="wide row" style="gap:6px;flex-wrap:wrap">${a.end_date && a.status === 'active' ? `<button type="button" class="btn sm" id="agr">${esc(tr('تجديد لمدة مماثلة'))}</button>` : ''}${a.direction === 'sale' && can('sales') && !a.recurring_id && AG_BILL[a.billing][2] ? `<button type="button" class="btn sm" id="agi">${esc(tr('إنشاء فاتورة متكررة'))}</button>` : ''}${a.recurring_id ? `<a class="btn sm" href="#/recurring">${esc(tr('الفاتورة المتكررة'))}</a>` : ''}<button type="button" class="btn sm danger" id="agdel">${esc(tr('حذف العقد'))}</button></div>`
        : filePick()}</div>`, {
    wide: true, onOk: async f => {
      const d = a ? a.direction : f.dir;
      if (!f.party) throw new Error(tr(d === 'sale' ? 'اختر العميل' : 'اختر المورد')); if ((f.title || '').trim().length < 2) throw new Error(tr('اكتب عنوان العقد'));
      if (f.to && f.to < f.from) throw new Error(tr('تاريخ النهاية قبل البداية'));
      const row = { party_id: f.party, title: f.title.trim(), kind: f.kind, status: f.st, start_date: f.from, end_date: blank(f.to), value: +f.value || 0, billing: f.bill, notice_days: Math.round(+f.notice || 0), owner_id: blank(f.owner), auto_renew: !!f.renew, notes: blank((f.notes || '').trim()) };
      if (a) await db.upd('agreements', { id: 'eq.' + a.id }, row);
      else { const [n] = await db.ins('agreements', Object.assign(row, { company_id: S.cid, direction: d })); await attachFiles('agreement_files', 'agreement_id', n.id, $('#mform').files.files); }
      toast(tr('تم الحفظ')); route(); } });
  if (!a) { const F = $('#mform', m); F.dir.onchange = () => { v.party_id = ''; F.party.innerHTML = partyOpts(F.dir.value); }; return; }
  fileBox($('#agf', m), 'agreement_files', 'agreement_id', a.id).catch(() => {});
  if ($('#agr', m)) $('#agr', m).onclick = async () => { const days = Math.round((new Date(a.end_date + 'T12:00:00Z') - new Date(a.start_date + 'T12:00:00Z')) / 864e5) + 1, nf = addDaysU(a.end_date, 1), nt = addDaysU(a.end_date, days);
    if (!await confirmBox(tr('تجديد العقد'), tr('يبدأ من') + ' ' + nf + ' ' + tr('وينتهي في') + ' ' + nt, tr('تجديد'))) return;
    try { await db.upd('agreements', { id: 'eq.' + a.id }, { start_date: nf, end_date: nt, status: 'active' }); toast(tr('جُدد العقد')); route(); } catch (e) { toast(e.message); } };
  if ($('#agi', m)) $('#agi', m).onclick = async () => { const items = await db.get('items', { company_id: 'eq.' + S.cid, active: 'neq.false', order: 'code', select: 'id,code,name,type' }).catch(() => []);
    const per = AG_BILL[a.billing][2], amt = agPeriodAmount(a);
    const d2 = modal(tr('إنشاء فاتورة متكررة'), `<div class="fg">${field('الصنف أو الخدمة', `<select name="item" required><option value="">—</option>${items.map(i => opt(i.id, i.code + ' — ' + i.name, '')).join('')}</select>`)}
        ${field('المبلغ لكل فترة قبل الضريبة', inp('price', amt || '', 'type="number" min="0.01" step="0.01" required'))}${field('أول موعد', `<input type="date" name="nx" value="${esc(a.start_date > today() ? a.start_date : today())}">`)}</div>
        <p class="muted small">${esc(tr('تتكرر'))} ${esc(agT(AG_BILL[a.billing]))}${a.end_date ? ' ' + esc(tr('حتى')) + ' ' + esc(a.end_date) : ''}. ${esc(tr('عند موعدها تصدرها من «الفواتير المتكررة» بضغطة.'))}</p>`, {
      ok: tr('إنشاء'), onOk: async f => { if (!f.item) throw new Error(tr('اختر الصنف أو الخدمة')); if (!(+f.price > 0)) throw new Error(tr('اكتب المبلغ'));
        const [r] = await db.ins('recurring_invoices', { company_id: S.cid, party_id: a.party_id, title: (a.no + ' — ' + a.title).slice(0, 120), lines: [{ item: f.item, qty: 1, price: +f.price }], every_months: per, next_date: f.nx, end_date: a.end_date || null });
        await db.upd('agreements', { id: 'eq.' + a.id }, { recurring_id: r.id }); toast(tr('أُنشئت الفاتورة المتكررة')); route(); } }); };
  $('#agdel', m).onclick = async () => { if (!await confirmBox(tr('حذف العقد'), tr('يُحذف العقد ومرفقاته، ولا تتأثر الفواتير الصادرة.'), tr('حذف'))) return;
    try { await db.del('agreements', { id: 'eq.' + a.id }); toast(tr('حُذف')); route(); } catch (e) { toast(e.message); } };
}

// bell: contracts ending within their notice period (or already ended while still active)
async function agNotifs(add, safe) { if (!agCan()) return; const r = await safe(db.rpc('agreements_due', { p_company: S.cid }));
  if (r && r.length) add(r.length + ' ' + tr('عقود تنتهي قريبا أو انتهت ولم تُجدد'), '#/agreements?s=due', { hot: r.some(x => x.days < 0) }); }

// the customer / supplier file: contact details and contracts above the statement
async function partyFile(page, p) {
  const ags = agCan() ? await db.get('agreements', { party_id: 'eq.' + p.id, order: 'end_date.asc.nullslast' }).catch(() => []) : [];
  const wa = typeof waPhone === 'function' ? waPhone(p.phone) : '', val = (k, v) => v ? `<div><span class="muted small">${esc(tr(k))}</span><div>${v}</div></div>` : '';
  const box = document.createElement('div'); box.className = 'card'; box.id = 'pfile';
  box.innerHTML = `<h2 style="margin-top:0">${esc(tr(p.kind === 'customer' ? 'ملف العميل' : 'ملف المورد'))}</h2>
    <div class="grid" style="margin-bottom:10px">${val('الجوال', p.phone ? `<span class="num" dir="ltr">${esc(p.phone)}</span>${wa ? ` <a href="https://wa.me/${wa}" target="_blank" rel="noopener" class="small">${esc(tr('واتساب'))}</a>` : ''}` : '')}
      ${val('البريد', p.email ? `<a href="mailto:${esc(p.email)}" dir="ltr">${esc(p.email)}</a>` : '')}${val('المدينة', esc(p.city || ''))}${val('الرقم الضريبي', p.vat_no ? `<span class="num">${esc(p.vat_no)}</span>` : '')}
      ${val('مدة السداد', p.terms_days ? `<span class="num">${p.terms_days}</span> ${esc(tr('يوما'))}` : '')}${val('حد الائتمان', p.credit_limit != null ? money(p.credit_limit) : '')}</div>
    ${agCan() ? `<h3 style="margin:8px 0 6px">${esc(tr('العقود والاتفاقيات'))}</h3>${ags.length ? tbl([{ t: 'العقد', h: a => `<a href="#/agreements?q=${encodeURIComponent(a.no || '')}" class="num">${esc(a.no || '')}</a> <span data-nt>${esc(a.title)}</span>` },
      { t: 'المدة', h: a => `${fdate(a.start_date)} – ${a.end_date ? fdate(a.end_date) : esc(tr('مفتوح'))}` }, { t: 'القيمة', r: 1, h: a => +a.value ? money(a.value) : '—' }, { t: 'الحالة', h: a => agBadge(a) }], ags, {}) : `<p class="muted small">${esc(tr('لا توجد عقود'))} · <a href="#/agreements">${esc(tr('+ عقد'))}</a></p>`}` : ''}`;
  const head = $('.head', page); if (head) head.after(box);
}
