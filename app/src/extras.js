/* ===== the first free batch from the comparison with the big systems (0153) =====
   overdue customers (#/dunning), price lists (#/pricelists), probation evaluation (#/probation), shift swaps, bulk approval */

/* ----- reminding customers of overdue invoices ----- */
const DUN_CH = { whatsapp: 'واتساب', email: 'إيميل', copy: 'نسخ', print: 'طباعة' };
function dunText(c, lang, url) {
  const co = (S.company || {}).name || '', en = lang === 'en';
  const ls = c.invoices.map(i => en ? `• Invoice ${i.no} of ${i.date} — due ${i.due} — outstanding ${money(i.rem)} — ${i.days} days late`
    : `• فاتورة رقم ${i.no} بتاريخ ${i.date} — استحقت في ${i.due} — المتبقي ${money(i.rem)} — متأخرة ${i.days} يوما`);
  return en ? `Dear ${c.contact || c.name},\n\nThis is a friendly reminder of the following invoices from ${co} that are past due:\n\n${ls.join('\n')}\n\nTotal outstanding: ${money(c.overdue)}${url ? `\nYour invoices and statement: ${url}` : ''}\n\nThank you. If you have already paid, please disregard this message.`
    : `السادة ${c.name}${c.contact ? ' — ' + c.contact : ''}،\n\nنود تذكيركم بالفواتير التالية من ${co} وقد تجاوزت موعد سدادها:\n\n${ls.join('\n')}\n\nإجمالي المستحق: ${money(c.overdue)}${url ? `\nللاطلاع على الفواتير وكشف الحساب: ${url}` : ''}\n\nشاكرين تعاونكم، وإن كنتم سددتم فنرجو تجاهل هذه الرسالة.`;
}
VIEWS['#/dunning'] = async page => {
  if (!can('sales')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const rows = await db.rpc('overdue_customers', { p_company: S.cid });
  const tot = rows.reduce((a, c) => a + n0(c.overdue), 0), band = d => d > 90 ? 'bad' : d > 30 ? 'wait' : '';
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('تحصيل المتأخرات'))}</h1><div class="muted">${esc(tr('العملاء الذين تجاوزت فواتيرهم موعد السداد، مع رسالة تذكير جاهزة. الإرسال من واتساب أو إيميل المنشأة نفسها.'))}</div></div>
      <div class="row" style="gap:6px"><label class="small" for="dlang">${esc(tr('لغة الرسالة'))}</label><select id="dlang" style="width:auto">${opt('ar', 'العربية', LANG)}${opt('en', 'English', LANG)}</select></div></div>
    <div class="grid" style="margin-bottom:14px"><div class="card kpi"><div class="muted small">${esc(tr('إجمالي المتأخرات'))}</div><div class="v num bad">${money(tot)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('عدد العملاء'))}</div><div class="v num">${rows.length}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('أكثر من 90 يوما'))}</div><div class="v num">${money(rows.reduce((a, c) => a + c.invoices.filter(i => i.days > 90).reduce((b, i) => b + n0(i.rem), 0), 0))}</div></div></div>
    ${rows.length ? tbl([{ t: 'العميل', h: c => `<a href="#/customer/${c.party_id}" data-nt>${esc(c.name)}</a>${c.phone ? ` <span class="small muted num" dir="ltr">${esc(c.phone)}</span>` : ''}` },
      { t: 'الفواتير', r: 1, h: c => `<span class="num">${c.n}</span>` }, { t: 'المتأخر', r: 1, h: c => `<b>${money(c.overdue)}</b>` },
      { t: 'أقدم تأخير', h: c => `<span class="badge ${band(c.max_days)}"><span class="num">${c.max_days}</span> ${esc(tr('يوما'))}</span>` },
      { t: 'آخر تذكير', h: c => c.last_at ? `${fdate(String(c.last_at).slice(0, 10))} <span class="muted small">${esc(tr(DUN_CH[c.last_channel] || ''))}${c.times > 1 ? ' · ' + c.times + ' ' + esc(tr('مرات')) : ''}</span>` : '<span class="muted">—</span>' },
      { t: '', h: c => `<button class="btn sm pri" data-dun="${c.party_id}">${esc(tr('تذكير'))}</button>` }], rows, {})
      : `<div class="note">${esc(tr('لا توجد فواتير متأخرة. أحسنت!'))}</div>`}`;
  $$('[data-dun]', page).forEach(b => b.onclick = () => dunDialog(rows.find(c => c.party_id === b.dataset.dun), $('#dlang', page).value));
};
async function dunDialog(c, lang) {
  let url = ''; try { url = location.origin + location.pathname + '#/portal/' + await db.rpc('portal_link_get', { p_party: c.party_id }); } catch (e) { url = ''; }
  const txt = dunText(c, lang, url), sub = lang === 'en' ? `Payment reminder — ${(S.company || {}).name || ''}` : `تذكير بفواتير مستحقة — ${(S.company || {}).name || ''}`, q = encodeURIComponent;
  const d = modal(tr('تذكير العميل') + ' — ' + c.name, `<textarea id="dtx" rows="12" style="width:100%" dir="${lang === 'en' ? 'ltr' : 'rtl'}">${esc(txt)}</textarea>
    <div class="row" style="gap:8px;margin-top:10px;flex-wrap:wrap">${c.phone ? `<a class="btn wa" id="dwa" target="_blank" rel="noopener" href="#">${esc(tr('واتساب'))}</a>` : ''}
      ${c.email ? `<a class="btn" id="dgm" target="_blank" rel="noopener" href="#">Gmail</a><a class="btn" id="dol" target="_blank" rel="noopener" href="#">Outlook</a><a class="btn" id="dml" href="#">${esc(tr('تطبيق البريد'))}</a>` : ''}
      <button type="button" class="btn" id="dcp">${esc(tr('نسخ الرسالة'))}</button></div>
    ${!c.phone && !c.email ? `<p class="muted small">${esc(tr('لا يوجد جوال أو إيميل للعميل: أضفهما في بطاقة العميل، أو انسخ الرسالة.'))}</p>` : ''}
    <p class="muted small">${esc(tr('الرابط يفتح للعميل فواتيره وكشف حسابه دون تسجيل دخول. وعد لا يرسل شيئا بنفسه: تُرسل الرسالة من جوالك أو بريدك.'))}</p>`, {});
  const body = () => $('#dtx', d).value, log = ch => db.rpc('dunning_note', { p_company: S.cid, p_party: c.party_id, p_channel: ch, p_amount: c.overdue, p_invoices: c.n }).catch(() => {});
  const set = () => { if ($('#dwa', d)) $('#dwa', d).href = waUrl(c.phone, body());
    if ($('#dgm', d)) { $('#dgm', d).href = `https://mail.google.com/mail/?view=cm&fs=1&to=${q(c.email)}&su=${q(sub)}&body=${q(body())}`; $('#dol', d).href = `https://outlook.office.com/mail/deeplink/compose?to=${q(c.email)}&subject=${q(sub)}&body=${q(body())}`; $('#dml', d).href = `mailto:${q(c.email)}?subject=${q(sub)}&body=${q(body())}`; } };
  set(); $('#dtx', d).oninput = set;
  if ($('#dwa', d)) $('#dwa', d).addEventListener('click', () => log('whatsapp'));
  ['#dgm', '#dol', '#dml'].forEach(id => { if ($(id, d)) $(id, d).addEventListener('click', () => log('email')); });
  $('#dcp', d).onclick = async () => { try { await navigator.clipboard.writeText(body()); toast(tr('نُسخت الرسالة')); } catch (e) { $('#dtx', d).select(); } log('copy'); };
  d.addEventListener('close', () => { if (location.hash.startsWith('#/dunning')) route(); }, { once: true });
}

/* ----- price lists and quantity discounts ----- */
VIEWS['#/pricelists'] = async page => {
  if (!can('sales')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const [lists, rules, items, parties] = await Promise.all([db.get('price_lists', { company_id: 'eq.' + S.cid, order: 'name' }), db.get('price_list_rules', { company_id: 'eq.' + S.cid }),
    db.get('items', { company_id: 'eq.' + S.cid, order: 'code', select: 'id,code,name,sale_price,active' }), db.get('parties', { company_id: 'eq.' + S.cid, kind: 'eq.customer', select: 'id,price_list_id' })]);
  const im = {}; items.forEach(i => im[i.id] = i);
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('قوائم الأسعار'))}</h1><div class="muted">${esc(tr('سعر خاص لكل فئة عملاء، وخصم يزيد مع الكمية. تُطبَّق تلقائيا في عروض الأسعار وأوامر البيع وفواتير المبيعات، ويبقى تعديل السعر في المستند متاحا.'))}</div></div><button class="btn pri" id="pln">+ ${esc(tr('قائمة أسعار'))}</button></div>
    ${tbl([{ t: 'القائمة', h: l => `<b data-nt>${esc((LANG === 'en' && l.name_en) || l.name)}</b>${l.is_default ? ` <span class="badge info">${esc(tr('افتراضية'))}</span>` : ''}${l.active ? '' : ` <span class="badge">${esc(tr('موقوفة'))}</span>`}` },
      { t: 'الخصم العام', r: 1, h: l => n0(l.discount_pct) ? `<span class="num">${+l.discount_pct}%</span>` : '—' },
      { t: 'أسعار الأصناف', r: 1, h: l => `<span class="num">${rules.filter(r => r.list_id === l.id).length}</span>` },
      { t: 'العملاء', r: 1, h: l => l.is_default ? `<span class="muted small">${esc(tr('كل من ليست له قائمة'))}</span>` : `<span class="num">${parties.filter(p => p.price_list_id === l.id).length}</span>` }], lists, { empty: 'لا توجد قوائم أسعار بعد', onRow: true })}
    <p class="muted small">${esc(tr('اختر قائمة العميل من بطاقته (العملاء ← تعديل). القائمة الافتراضية تُطبَّق على من ليست له قائمة.'))}</p>`;
  const edit = l => {
    const rs = l ? rules.filter(r => r.list_id === l.id) : [], itemOpts = v => `<option value="">—</option>` + items.filter(i => i.active !== false || i.id === v).map(i => opt(i.id, i.code + ' — ' + i.name, v || '')).join('');
    const row = r => `<tr><td><select data-r="item" style="min-width:200px">${itemOpts(r && r.item_id)}</select></td><td><input data-r="min" type="number" min="0.001" step="0.001" value="${r ? +r.min_qty : 1}" style="width:90px"></td>
      <td><input data-r="price" type="number" min="0" step="0.01" value="${r && r.price != null ? +r.price : ''}" style="width:110px"></td><td><input data-r="pct" type="number" min="0" max="100" step="0.01" value="${r && r.discount_pct != null ? +r.discount_pct : ''}" style="width:90px"></td>
      <td><button type="button" class="btn sm" data-rx aria-label="${esc(tr('حذف'))}">×</button></td></tr>`;
    const d = modal(l ? tr('تعديل قائمة الأسعار') : tr('قائمة أسعار جديدة'), `<div class="fg">${field('اسم القائمة', inp('name', l && l.name, 'required maxlength="80"'))}${field('الاسم بالإنجليزية', inp('name_en', l && l.name_en, 'dir="ltr" maxlength="80"'))}
      ${field('خصم عام على كل الأصناف (%)', inp('disc', l ? +l.discount_pct : 0, 'type="number" min="0" max="100" step="0.01"'))}
      <div><label class="row small" style="gap:6px;margin-top:26px"><input type="checkbox" name="def" style="width:auto" ${l && l.is_default ? 'checked' : ''}> ${esc(tr('افتراضية لمن ليست له قائمة'))}</label>
      <label class="row small" style="gap:6px"><input type="checkbox" name="act" style="width:auto" ${!l || l.active ? 'checked' : ''}> ${esc(tr('مفعّلة'))}</label></div></div>
      <h3 style="margin:12px 0 4px">${esc(tr('أسعار خاصة وخصم الكمية'))}</h3><p class="muted small" style="margin:0 0 6px">${esc(tr('لكل بند سعر ثابت أو نسبة خصم من سعر البيع. أكثر من بند للصنف نفسه بكميات مختلفة = خصم الكمية: يُطبَّق البند ذو أعلى كمية بلغها المستند.'))}</p>
      <div class="tw"><table class="lines"><thead><tr><th>${esc(tr('الصنف'))}</th><th>${esc(tr('من كمية'))}</th><th>${esc(tr('السعر'))}</th><th>${esc(tr('أو خصم %'))}</th><th></th></tr></thead><tbody id="plr">${(rs.length ? rs : [null]).map(row).join('')}</tbody></table></div>
      <div class="row" style="gap:6px;margin-top:6px"><button type="button" class="btn sm" id="pla">+ ${esc(tr('بند'))}</button>${l ? `<button type="button" class="btn sm danger" id="pld">${esc(tr('حذف القائمة'))}</button>` : ''}</div>`,
      { wide: true, onOk: async f => {
        const ls = $$('#plr tr', d).map(t => ({ item: $('[data-r=item]', t).value, min_qty: $('[data-r=min]', t).value, price: $('[data-r=price]', t).value, discount_pct: $('[data-r=pct]', t).value })).filter(x => x.item);
        if (ls.some(x => (x.price === '') === (x.discount_pct === ''))) throw new Error(tr('لكل بند سعر أو نسبة خصم'));
        await db.rpc('price_list_save', { p_company: S.cid, p_id: l ? l.id : null, p_name: (f.name || '').trim(), p_name_en: blank(f.name_en), p_discount: +f.disc || 0, p_default: !!f.def, p_active: !!f.act, p_rules: ls });
        PL_CACHE.clear(); PL_HAS = null; toast(tr('تم الحفظ')); route(); } });
    $('#pla', d).onclick = () => $('#plr', d).insertAdjacentHTML('beforeend', row(null));
    $('#plr', d).addEventListener('click', e => { if (e.target.matches('[data-rx]')) e.target.closest('tr').remove(); });
    if ($('#pld', d)) $('#pld', d).onclick = async () => { d.close(); if (!await confirmBox(tr('حذف القائمة'), tr('يُحذف السعر الخاص من عملاء هذه القائمة ويعودون للافتراضية.'), tr('حذف'))) return; await db.rpc('price_list_delete', { p_id: l.id }); PL_CACHE.clear(); PL_HAS = null; toast(tr('حُذفت')); route(); };
  };
  $('#pln', page).onclick = () => edit(null);
  bindRows(page, lists, l => edit(l));
};
// the price of an item for a customer and quantity (the server applies the rules); null when the company has no lists
const PL_CACHE = new Map(); let PL_HAS = null;
async function listPriceFor(party, item, qty) {
  if (!party || !item) return null;
  if (PL_HAS === null || PL_HAS.cid !== S.cid || Date.now() - PL_HAS.at > 60000) { PL_CACHE.clear(); PL_HAS = { cid: S.cid, at: Date.now(), v: (await db.get('price_lists', { company_id: 'eq.' + S.cid, active: 'eq.true', select: 'id', limit: 1 }).catch(() => [])).length > 0 }; }
  if (!PL_HAS.v) return null;
  const k = party + '|' + item + '|' + (+qty || 1); if (PL_CACHE.has(k)) return PL_CACHE.get(k);
  const p = await db.rpc('list_price', { p_party: party, p_item: item, p_qty: +qty || 1 }).catch(() => null); PL_CACHE.set(k, p); return p;
}
// a document line takes the list price unless the user typed a price himself (l.pman)
async function plApply(l, party, item, qty, done) {
  if (l.pman || !item) return; const p = await listPriceFor(party, item, qty);
  if (p == null || l.pman) return; if (+l.price !== +p) { l.price = +p; done(); }
}

/* ----- probation evaluation (Art. 53: up to 180 days in all) ----- */
const PRB_C = { quality: 'جودة العمل', commitment: 'الالتزام والانضباط', teamwork: 'التعاون والعمل الجماعي', learning: 'سرعة التعلم', conduct: 'السلوك المهني' };
const PRB_R = { confirm: 'تثبيت في الوظيفة', extend: 'تمديد فترة التجربة', end: 'إنهاء العقد خلال فترة التجربة' };
VIEWS['#/probation'] = async page => {
  const rows = await db.rpc('probation_due', { p_company: S.cid }), hr = isHR();
  const st = x => { const v = x.review; if (v && v.status === 'final') return `<span class="badge ok">${esc(tr('القرار'))}: ${esc(tr(PRB_R[v.decision]))}</span>`;
    if (v) return `<span class="badge wait">${esc(tr('التوصية'))}: ${esc(tr(PRB_R[v.recommendation]))}</span> <span class="small muted">${esc(v.by_name || '')} · <span class="num">${v.score}</span>/5</span>`;
    return `<span class="badge ${x.days_left <= 7 ? 'bad' : ''}">${esc(tr('لم يُقيَّم'))}</span>`; };
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('تقييم فترة التجربة'))}</h1><div class="muted">${esc(tr('الموظفون الذين تنتهي فترة تجربتهم خلال 30 يوما. يقيّمهم المدير المباشر، وتصدر الموارد البشرية القرار قبل نهايتها.'))}</div></div></div>
    ${tbl([{ t: 'الموظف', h: x => `<a href="#/emp/${x.employee_id}" data-nt>${esc(x.name)}</a> <span class="muted small num">${esc(x.emp_no)}</span><div class="small muted">${esc(x.job || '')}${x.manager ? ' · ' + esc(x.manager) : ''}</div>` },
      { t: 'تاريخ المباشرة', h: x => fdate(x.hire_date) }, { t: 'نهاية التجربة', h: x => `${fdate(x.effective_end)} <span class="small ${x.days_left < 0 ? 'bad' : 'muted'}">(${x.days_left < 0 ? esc(tr('انتهت')) : `<span class="num">${x.days_left}</span> ${esc(tr('يوما'))}`})</span>` },
      { t: 'الحالة', h: st }, { t: '', h: x => x.review && x.review.status === 'final' ? '' : `<button class="btn sm" data-prv="${x.employee_id}">${esc(tr('تقييم'))}</button>${hr ? ` <button class="btn sm pri" data-prd="${x.employee_id}">${esc(tr('القرار'))}</button>` : ''}` }],
      rows, { empty: 'لا يوجد موظفون تنتهي فترة تجربتهم قريبا' })}
    <p class="muted small">${esc(tr('فترة التجربة كلها لا تزيد على 180 يوما، ولكل من الطرفين إنهاء العقد خلالها دون تعويض ولا مكافأة نهاية خدمة عنها (المادتان 53 و54). قرار الإنهاء يُسجَّل هنا، ثم تُنهى الخدمة من ملف الموظف.'))}</p>`;
  const byId = id => rows.find(x => x.employee_id === id);
  $$('[data-prv]', page).forEach(b => b.onclick = () => { const x = byId(b.dataset.prv), v = x.review || {}, rt = v.ratings || {};
    const d = modal(tr('تقييم فترة التجربة') + ' — ' + x.name, `<div class="fg">${Object.entries(PRB_C).map(([k, t]) => field(t, `<select name="r_${k}">${[5, 4, 3, 2, 1].map(n => opt(n, n + ' — ' + tr(['', 'ضعيف', 'مقبول', 'جيد', 'جيد جدا', 'ممتاز'][n]), String(rt[k] || 3))).join('')}</select>`)).join('')}
      ${field('نقاط القوة', `<textarea name="s" rows="2">${esc(v.strengths || '')}</textarea>`, 'wide')}${field('ما يحتاج إلى تحسين', `<textarea name="i" rows="2">${esc(v.improve || '')}</textarea>`, 'wide')}
      ${field('التوصية', `<select name="rec" id="prec">${Object.entries(PRB_R).map(([k, t]) => opt(k, tr(t), v.recommendation || 'confirm')).join('')}</select>`)}
      <div id="pxw" hidden>${field('أيام التمديد', inp('ext', v.extend_days || 30, 'type="number" min="1" max="179"'))}</div></div>`,
      { ok: 'حفظ التقييم', onOk: async f => { const r = {}; Object.keys(PRB_C).forEach(k => r[k] = +f['r_' + k]);
        await db.rpc('probation_review_save', { p_company: S.cid, p_emp: x.employee_id, p_ratings: r, p_strengths: f.s || '', p_improve: f.i || '', p_rec: f.rec, p_extend_days: f.rec === 'extend' ? +f.ext : null }); toast(tr('تم الحفظ')); route(); } });
    const sx = () => { $('#pxw', d).hidden = $('#prec', d).value !== 'extend'; }; $('#prec', d).onchange = sx; sx(); });
  $$('[data-prd]', page).forEach(b => b.onclick = () => { const x = byId(b.dataset.prd), v = x.review;
    const d = modal(tr('قرار فترة التجربة') + ' — ' + x.name, `${v ? `<div class="card" style="padding:10px 12px;margin-bottom:10px"><b class="small">${esc(tr('توصية'))} ${esc(v.by_name || '')}</b>: ${esc(tr(PRB_R[v.recommendation]))}${v.extend_days ? ` (<span class="num">${v.extend_days}</span> ${esc(tr('يوما'))})` : ''} · ${esc(tr('التقييم'))} <b class="num">${v.score}</b>/5
        ${v.strengths ? `<div class="small">${esc(tr('نقاط القوة'))}: ${esc(v.strengths)}</div>` : ''}${v.improve ? `<div class="small">${esc(tr('ما يحتاج إلى تحسين'))}: ${esc(v.improve)}</div>` : ''}</div>` : `<p class="muted small">${esc(tr('لم يُقيّمه المدير بعد.'))}</p>`}
      <div class="fg">${field('القرار', `<select name="dec" id="pdec">${Object.entries(PRB_R).map(([k, t]) => opt(k, tr(t), v ? v.recommendation : 'confirm')).join('')}</select>`)}
      <div id="pdx" hidden>${field('أيام التمديد', inp('ext', (v && v.extend_days) || 30, 'type="number" min="1" max="179"'))}</div>${field('ملاحظة', inp('note', ''), 'wide')}</div>
      <p class="muted small">${esc(tr('التثبيت ينهي فترة التجربة اليوم إن كانت جارية. التمديد يغيّر نهايتها في ملف الموظف، والمدة كلها لا تزيد على 180 يوما (م53).'))}</p>`,
      { ok: 'اعتماد القرار', onOk: async f => { await db.rpc('probation_decide', { p_company: S.cid, p_emp: x.employee_id, p_decision: f.dec, p_extend_days: f.dec === 'extend' ? +f.ext : null, p_note: f.note || '' });
        toast(tr('صدر القرار')); if (f.dec === 'end') toast(tr('أنهِ الخدمة الآن من ملف الموظف ← نهاية الخدمة')); route(); } });
    const sx = () => { $('#pdx', d).hidden = $('#pdec', d).value !== 'extend'; }; $('#pdec', d).onchange = sx; sx(); });
};

/* ----- shift swaps ----- */
const SWAP_ST = { asked: ['بانتظار الزميل', 'wait'], accepted: ['بانتظار الاعتماد', 'wait'], declined: ['رفضه الزميل', 'bad'], approved: ['معتمد', 'ok'], rejected: ['مرفوض', 'bad'], cancelled: ['ملغى', ''] };
const swapBadge = s => { const [t, c] = SWAP_ST[s] || [s, '']; return `<span class="badge ${c}">${esc(tr(t))}</span>`; };
const swapShift = (n, off) => off || !n ? esc(tr('راحة')) : `<span data-nt>${esc(n)}</span>`;
// mode 'mine' (my requests and those asked of me) or 'decide' (manager / HR)
async function swapsBox(box, mode) {
  if (!box) return; const all = await db.rpc('swaps_list', { p_company: S.cid }).catch(() => []);
  const rows = all.filter(x => mode === 'decide' ? x.can_decide : (x.mine || x.to_emp === S.emp));
  if (!rows.length) { box.innerHTML = ''; return; }
  box.innerHTML = `<div class="card" style="margin-top:14px"><h2>${esc(tr(mode === 'decide' ? 'تبديل الورديات بانتظار اعتمادك' : 'تبديل الورديات'))}</h2>
    ${tbl([{ t: 'اليوم', h: x => fdate(x.day) }, { t: 'الطلب', h: x => `<span data-nt>${esc(x.from_name)}</span> (${swapShift(x.from_shift, !x.from_shift)}) ⇄ <span data-nt>${esc(x.to_name)}</span> (${swapShift(x.to_shift, !x.to_shift)})${x.note ? `<div class="small muted">${esc(x.note)}</div>` : ''}` },
      { t: 'الحالة', h: x => swapBadge(x.status) + (x.decide_note ? ` <span class="small muted">${esc(x.decide_note)}</span>` : '') },
      { t: '', h: x => mode === 'decide' ? `<button class="btn sm pri" data-swd="${x.id}" data-ok="1">${esc(tr('اعتماد'))}</button> <button class="btn sm danger" data-swd="${x.id}" data-ok="0">${esc(tr('رفض'))}</button>`
        : x.asked_me ? `<button class="btn sm pri" data-swa="${x.id}" data-ok="1">${esc(tr('موافقة'))}</button> <button class="btn sm" data-swa="${x.id}" data-ok="0">${esc(tr('اعتذار'))}</button>`
        : x.mine && ['asked', 'accepted'].includes(x.status) ? `<button class="btn sm" data-swc="${x.id}">${esc(tr('إلغاء'))}</button>` : '' }], rows, {})}</div>`;
  const redo = () => { swapsBox(box, mode); refreshCounts(); };
  $$('[data-swa]', box).forEach(b => b.onclick = async () => { try { await db.rpc('swap_answer', { p_id: b.dataset.swa, p_accept: b.dataset.ok === '1' }); toast(tr('تم')); redo(); } catch (e) { toast(e.message); } });
  $$('[data-swc]', box).forEach(b => b.onclick = async () => { try { await db.rpc('swap_cancel', { p_id: b.dataset.swc }); toast(tr('أُلغي الطلب')); redo(); } catch (e) { toast(e.message); } });
  $$('[data-swd]', box).forEach(b => b.onclick = async () => { const ok = b.dataset.ok === '1';
    if (ok) { try { await db.rpc('swap_decide', { p_id: b.dataset.swd, p_approve: true, p_note: null }); toast(tr('اعتُمد التبديل وتغيّر جدول الورديات')); redo(); } catch (e) { toast(e.message); } return; }
    modal(tr('رفض تبديل الوردية'), field('سبب الرفض', inp('why', '', 'required')), { ok: 'رفض', onOk: async f => { await db.rpc('swap_decide', { p_id: b.dataset.swd, p_approve: false, p_note: f.why }); toast(tr('تم الرفض')); redo(); } }); });
}

/* ----- bulk approval on «الاعتمادات» ----- */
function bulkApprove(page, mine) {
  const box = $('#bulkw', page); if (!box || !mine.length) return;
  const sel = () => $$('[data-bk]:checked', page).map(x => x.dataset.bk);
  const sync = () => { if (!$('#bkn', page)) return; const n = sel().length; $('#bkn', page).textContent = n; $('#bulk', page).disabled = !n; };
  page.addEventListener('change', e => { if (e.target.matches('[data-bk]')) sync(); if (e.target.id === 'bkall') { $$('[data-bk]', page).forEach(x => x.checked = e.target.checked); sync(); } });
  $('#bulk', page).onclick = async () => { const ids = sel(); if (!ids.length) return;
    if (!await confirmBox(tr('اعتماد المحدد'), tr('اعتماد') + ' ' + ids.length + ' ' + tr('طلب دفعة واحدة؟ كل طلب ينتقل لمرحلته التالية أو يُعتمد نهائيا.'), tr('اعتماد'))) return;
    let ok = 0; const bad = [];
    for (const id of ids) { try { await db.rpc('decide_request', { p_id: id, p_approve: true, p_note: null }); ok++; } catch (e) { const r = mine.find(x => x.id === id); bad.push((r && r._emp ? r._emp.full_name : '') + ': ' + e.message); } }
    toast(tr('اعتُمد') + ' ' + ok + (bad.length ? ' · ' + tr('تعذّر') + ' ' + bad.length : ''));
    if (bad.length) modal(tr('طلبات لم تُعتمد'), `<ul>${bad.map(x => `<li class="small">${esc(x)}</li>`).join('')}</ul><p class="muted small">${esc(tr('افتح الطلب لمعرفة ما يحتاجه.'))}</p>`, {});
    route(); refreshCounts(); };
  sync();
}
