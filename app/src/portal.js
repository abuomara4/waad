'use strict';
/* ===== بوابة العميل (0099): a private link that shows one customer its invoices, without signing in ===== */
const portalToken = () => (location.hash.match(/^#\/portal\/([0-9a-f]{64})/) || [])[1] || null;
async function portalView(token) {
  document.title = tr('بوابة العميل') + ' — ' + tr('وعد');
  $('#app').innerHTML = `<div class="portal"><div class="muted">${esc(tr('جاري التحميل…'))}</div></div>`;
  let d = null; try { d = await db.rpc('portal_view', { p_token: token }); } catch (e) { d = null; }
  const box = $('.portal');
  if (!d) { box.innerHTML = `${brand()}<div class="card"><h2>${esc(tr('الرابط غير صالح'))}</h2><p class="muted">${esc(tr('انتهى هذا الرابط أو أُلغي. اطلب رابطا جديدا من المنشأة.'))}</p></div>`; return; }
  const co = d.company, inv = d.invoices || [], rem = i => Math.max(0, r2(n0(i.total) - n0(i.paid) - n0(i.credit)));
  const due = inv.reduce((a, i) => a + rem(i), 0);
  box.innerHTML = `<div class="phead">${co.logo ? `<img src="${esc(co.logo)}" alt="" class="plogo">` : ''}<div><h1>${esc(co.name)}</h1><div class="small muted">${[co.cr_no && tr('السجل التجاري') + ' ' + co.cr_no, co.vat_no && tr('الرقم الضريبي') + ' ' + co.vat_no].filter(Boolean).map(esc).join(' · ')}</div></div>
      <div class="sp"></div><button class="btn sm" id="plg">${LANG === 'en' ? 'العربية' : 'English'}</button></div>
    <div class="card"><div class="muted small">${esc(tr('بوابة العميل'))}</div><h2 style="margin:4px 0">${esc(d.party.name)}</h2>
      <div class="grid" style="margin-top:10px"><div class="card kpi"><div class="muted small">${esc(tr('عدد الفواتير'))}</div><div class="v num">${inv.length}</div></div>
        <div class="card kpi"><div class="muted small">${esc(tr('المستحق عليكم'))}</div><div class="v num ${due > 0.001 ? 'bad' : 'ok'}">${money(due)}</div></div></div></div>
    <div class="card"><h2>${esc(tr('الفواتير'))}</h2>${tbl([{ t: 'الرقم', h: i => `<span class="num">${esc(i.no)}</span>` }, { t: 'التاريخ', h: i => fdate(i.date) }, { t: 'الاستحقاق', h: i => fdate(i.due_date) },
      { t: 'الإجمالي', r: 1, h: i => money(i.total) }, { t: 'المتبقي', r: 1, h: i => rem(i) > 0.001 ? `<b class="bad">${money(rem(i))}</b>` : `<span class="badge ok">${esc(tr('مسددة'))}</span>` }], inv, { empty: 'لا توجد فواتير', onRow: true })}</div>
    <p class="small muted" style="text-align:center">${esc(tr('هذه الصفحة خاصة بكم؛ لا تشاركوا رابطها.'))} · ${esc(tr('نظام وعد'))}</p>`;
  $('#plg').onclick = () => { setLang(LANG === 'en' ? 'ar' : 'en'); portalView(token); };
  if (typeof portalTicketsBox === 'function') portalTicketsBox(box, token);
  bindRows(box, inv, i => {
    const lines = i.lines || [];
    const m = modal(tr('فاتورة') + ' ' + i.no, `<p class="small muted">${fdate(i.date)} · ${esc(tr('الاستحقاق'))} ${fdate(i.due_date)}</p>
      ${tbl([{ t: 'البند', h: l => esc(l.item) }, { t: 'الكمية', r: 1, h: l => qtyTxt(l.qty) }, { t: 'السعر', r: 1, h: l => money(l.price) }, { t: 'الضريبة', r: 1, h: l => money(l.vat) }, { t: 'المبلغ', r: 1, h: l => money(n0(l.amount) + n0(l.vat)) }], lines)}
      <p class="r">${esc(tr('قبل الضريبة'))} <span class="num">${money(i.subtotal)}</span> · ${esc(tr('الضريبة'))} <span class="num">${money(i.vat)}</span> · <b>${esc(tr('الإجمالي'))} <span class="num">${money(i.total)}</span></b></p>
      <p class="r">${esc(tr('المدفوع'))} <span class="num">${money(n0(i.paid) + n0(i.credit))}</span> · <b>${esc(tr('المتبقي'))} <span class="num">${money(rem(i))}</span></b></p>
      <button type="button" class="btn" id="ppr">${esc(tr('طباعة'))}</button>`, { wide: true });
    $('#ppr', m).onclick = () => { const n = document.createElement('div'); n.className = 'pdoc';
      n.innerHTML = `<h2>${esc(co.name)}</h2><p>${esc(tr('فاتورة'))} <b class="num">${esc(i.no)}</b> — ${esc(d.party.name)} — ${fdate(i.date)}</p>` + $('.tw', m).outerHTML + $$('p.r', m).map(x => x.outerHTML).join('');
      printWith(n, '@page{size:A4 portrait;margin:12mm}'); };
  });
}

/* the sales side: the customer's link (create, copy, send by WhatsApp, revoke) — from the customer statement */
async function portalLinkDialog(party) {
  const tok = await db.rpc('portal_link_get', { p_party: party.id }), url = location.origin + location.pathname + '#/portal/' + tok;
  const msg = tr('السادة') + ' ' + party.name + tr('،') + '\n' + tr('يمكنكم الاطلاع على فواتيركم والمبالغ المستحقة عبر الرابط:') + '\n' + url;
  const d = modal(tr('بوابة العميل') + ' — ' + party.name, `<p class="small">${esc(tr('رابط خاص يفتح للعميل فواتيره والمتبقي عليه دون تسجيل دخول. أرسله للعميل فقط.'))}</p>
    <input id="purl" readonly dir="ltr" value="${esc(url)}">
    <div class="row" style="gap:8px;margin-top:10px;flex-wrap:wrap"><button type="button" class="btn" id="pcp">${esc(tr('نسخ الرابط'))}</button>${waBtn(party.phone, msg, tr('إرسال واتساب'), 'btn wa')}
      <a class="btn" href="${esc(url)}" target="_blank" rel="noopener">${esc(tr('معاينة'))}</a><button type="button" class="btn danger" id="prv">${esc(tr('إلغاء الرابط'))}</button></div>`, {});
  $('#pcp', d).onclick = () => { navigator.clipboard && navigator.clipboard.writeText(url).then(() => toast(tr('نُسخ الرابط'))).catch(() => { $('#purl', d).select(); }); };
  $('#prv', d).onclick = async () => { await db.rpc('portal_link_revoke', { p_party: party.id }); d.close(); toast(tr('أُلغي الرابط؛ يمكنك إنشاء رابط جديد لاحقا')); };
}

/* ===== الفواتير المتكررة (0099) ===== */
VIEWS['#/recurring'] = async page => {
  if (!can('sales')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const [rows, parties, items] = await Promise.all([db.get('recurring_invoices', { company_id: 'eq.' + S.cid, order: 'next_date' }), db.get('parties', { company_id: 'eq.' + S.cid, kind: 'eq.customer', order: 'name', select: 'id,name' }),
    db.get('items', { company_id: 'eq.' + S.cid, active: 'neq.false', order: 'code', select: 'id,code,name,sale_price,type' })]);
  const pm = {}; parties.forEach(p => pm[p.id] = p.name); const td = today(), due = rows.filter(r => r.active && r.next_date <= td);
  const tot = r => r2((r.lines || []).reduce((a, l) => a + n0(l.qty) * n0(l.price), 0));
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الفواتير المتكررة'))}</h1><div class="muted">${esc(tr('فاتورة تتكرر لعميل كل شهر أو أكثر (إيجار، صيانة، اشتراك). عند موعدها تصدرها بضغطة، وتُرحّل كأي فاتورة.'))}</div></div>
      <div class="row">${due.length ? `<button class="btn pri" id="rcall">${esc(tr('إصدار المستحق'))} <span class="num">(${due.length})</span></button>` : ''}<button class="btn" id="rcnew">${esc(tr('+ فاتورة متكررة'))}</button></div></div>
    ${tbl([{ t: 'العميل', h: r => esc(pm[r.party_id] || '') + `<div class="small muted">${esc(r.title)}</div>` }, { t: 'قبل الضريبة', r: 1, h: r => money(tot(r)) },
      { t: 'التكرار', h: r => esc(r.every_months === 1 ? tr('شهريا') : tr('كل') + ' ' + r.every_months + ' ' + tr('أشهر')) },
      { t: 'الموعد القادم', h: r => r.active ? `<span class="num ${r.next_date <= td ? 'bad' : ''}">${esc(r.next_date)}</span>${r.next_date <= td ? ` <span class="badge bad">${esc(tr('مستحقة'))}</span>` : ''}` : `<span class="badge">${esc(tr('موقوفة'))}</span>` },
      { t: 'صدر منها', r: 1, h: r => `<span class="num">${r.issued_count}</span>` },
      { t: '', h: r => r.active && r.next_date <= td ? `<button class="btn sm pri" data-rci="${r.id}">${esc(tr('إصدار'))}</button>` : '' }], rows, { empty: 'لا توجد فواتير متكررة', onRow: true })}`;
  const issue = async id => { const inv = await db.rpc('recurring_issue', { p_id: id }); if (typeof zatcaKick === 'function') zatcaKick(); return inv; };
  $$('[data-rci]', page).forEach(b => b.onclick = async ev => { ev.stopPropagation(); try { await busy(b, () => issue(b.dataset.rci)); toast(tr('صدرت الفاتورة')); route(); } catch (er) { toast(er.message); } });
  if ($('#rcall', page)) $('#rcall', page).onclick = async () => { let n = 0; for (const r of due) { try { await issue(r.id); n++; } catch (er) { toast(er.message); } } toast(tr('صدرت') + ' ' + n); route(); };
  bindRows(page, rows, r => form(r));
  $('#rcnew', page).onclick = () => form(null);
  function form(r) { const v = r || { every_months: 1, next_date: td, lines: [{ item: '', qty: 1, price: '' }] };
    if (!parties.length) return toast(tr('أضف عميلا أولا'));
    const row = l => `<tr><td><select data-it>${items.map(i => opt(i.id, i.code + ' — ' + i.name, l.item)).join('')}</select></td><td><input data-q type="number" min="0.001" step="any" value="${esc(l.qty)}" style="width:90px"></td><td><input data-p type="number" min="0" step="0.01" value="${esc(l.price)}" style="width:120px"></td><td><button type="button" class="btn sm" data-x>×</button></td></tr>`;
    const m = modal(r ? tr('تعديل فاتورة متكررة') : tr('فاتورة متكررة جديدة'), `<div class="fg">${field('العميل', `<select name="party">${parties.map(p => opt(p.id, p.name, v.party_id)).join('')}</select>`)}${field('الوصف', inp('title', v.title, 'required maxlength="120" placeholder="' + esc(tr('مثل: إيجار شهري، عقد صيانة')) + '"'))}
      ${field('التكرار', `<select name="ev">${[1, 2, 3, 6, 12].map(k => opt(String(k), k === 1 ? tr('شهريا') : k === 12 ? tr('سنويا') : tr('كل') + ' ' + k + ' ' + tr('أشهر'), String(v.every_months))).join('')}</select>`)}
      ${field('الموعد القادم', `<input type="date" name="nx" value="${esc(v.next_date)}" required>`)}${field('ينتهي بعد (اختياري)', `<input type="date" name="en" value="${esc(v.end_date || '')}">`)}
      ${r ? field('الحالة', `<select name="act">${opt('true', tr('فعّالة'), String(v.active))}${opt('false', tr('موقوفة'), String(v.active))}</select>`) : ''}</div>
      <div class="tw" style="margin-top:10px"><table class="lines"><thead><tr><th>${esc(tr('الصنف أو الخدمة'))}</th><th>${esc(tr('الكمية'))}</th><th>${esc(tr('السعر قبل الضريبة'))}</th><th></th></tr></thead><tbody id="rl">${(v.lines || []).map(row).join('')}</tbody></table></div>
      <button type="button" class="btn sm" id="rla" style="margin-top:6px">${esc(tr('+ بند'))}</button>
      ${r ? `<div style="margin-top:12px"><button type="button" class="btn sm danger" id="rdel">${esc(tr('حذف'))}</button></div>` : ''}`, {
      wide: true, onOk: async f => {
        const lines = $$('#rl tr', m).map(t => ({ item: $('[data-it]', t).value, qty: +$('[data-q]', t).value || 0, price: +$('[data-p]', t).value || 0 })).filter(l => l.item && l.qty > 0);
        if (!lines.length) throw new Error('أضف بندا واحدا على الأقل'); if ((f.title || '').trim().length < 2) throw new Error('اكتب الوصف');
        const rowd = { party_id: f.party, title: f.title.trim(), lines, every_months: +f.ev, next_date: f.nx, end_date: blank(f.en), ...(r ? { active: f.act === 'true' } : {}) };
        if (r) await db.upd('recurring_invoices', { id: 'eq.' + r.id }, rowd); else await db.ins('recurring_invoices', Object.assign(rowd, { company_id: S.cid }));
        toast(tr('تم الحفظ')); route(); } });
    $('#rla', m).onclick = () => $('#rl', m).insertAdjacentHTML('beforeend', row({ item: '', qty: 1, price: '' }));
    $('#rl', m).addEventListener('click', ev => { const x = ev.target.closest('[data-x]'); if (x && $$('#rl tr', m).length > 1) x.closest('tr').remove(); });
    $('#rl', m).addEventListener('change', ev => { const s = ev.target.closest('[data-it]'); if (!s) return; const it = items.find(i => i.id === s.value), p = $('[data-p]', s.closest('tr')); if (it && !p.value) p.value = it.sale_price || ''; });
    if ($('#rdel', m)) $('#rdel', m).onclick = async () => { if (!await confirmBox(tr('حذف الفاتورة المتكررة'), tr('تتوقف ولا تُحذف الفواتير التي صدرت منها.'), tr('حذف'))) return; await db.del('recurring_invoices', { id: 'eq.' + r.id }); route(); };
  }
};
