'use strict';
/* ===== Projects, phase two (0124): contract items and progress claims (ZATCA contracting guideline), change orders with the
   customer's approval by private link, guarantees per project, risk register, resource allocation by week ===== */

const CLAIM_KIND = { advance: 'دفعة مقدمة', interim: 'مستخلص جارٍ', final: 'مستخلص ختامي' };
const CO_ST = { draft: ['مسودة', ''], sent: ['أُرسل للعميل', 'wait'], approved: ['معتمد', 'ok'], rejected: ['مرفوض', 'bad'] };

/* ---------- «البنود والمستخلصات» ---------- */
async function projectClaimsTab(body, p) {
  const [boq, claims, ct] = await Promise.all([db.get('project_boq', Object.assign(C(), { project_id: 'eq.' + p.id, order: 'sort,created_at' })),
    db.get('project_claims', Object.assign(C(), { project_id: 'eq.' + p.id, order: 'date,created_at' })), db.rpc('project_contract', { p_project: p.id })]);
  const claimLive = c => c.status === 'approved' && (n0(c.net) <= 0 || n0(c.credited) < n0(c.net) - 0.004);
  const approved = claims.filter(claimLive), lastQty = {};
  approved.filter(c => c.kind !== 'advance').forEach(c => (c.lines || []).forEach(l => { lastQty[l.boq] = Math.max(n0(lastQty[l.boq]), n0(l.qty)); }));
  const hasFinal = approved.some(c => c.kind === 'final');
  const kpi = (t, v) => `<div class="card kpi"><div class="muted small">${esc(tr(t))}</div><div class="v num">${v}</div></div>`;
  body.innerHTML = `<div class="grid" style="margin-bottom:14px">${kpi('قيمة البنود', money(ct.boq_total))}${kpi('المنفذ المعتمد', money(ct.certified))}
      ${kpi('الدفعة المقدمة', money(ct.advance))}${kpi('المسترد منها', money(ct.recovered))}${kpi('محتجز الضمان لدى العميل', money(ct.retention))}</div>
    <div class="card" id="boqc"><div class="row" style="justify-content:space-between;align-items:center"><h2>${esc(tr('بنود العقد (جدول الكميات)'))}</h2>${prjOffice() ? `<button class="btn sm pri" id="nboq">${esc(tr('بند جديد'))}</button>` : ''}</div>
      ${tbl([{ t: 'الرمز', h: b => `<span class="num">${esc(b.code || '')}</span>` }, { t: 'البند', h: b => esc(b.description) + (b.co_id ? ` <span class="badge info small">${esc(tr('أمر تغيير'))}</span>` : '') }, { t: 'الوحدة', h: b => esc(b.unit || '') },
        { t: 'الكمية', r: 1, h: b => qtyTxt(b.qty) }, { t: 'السعر', r: 1, h: b => money(b.rate) }, { t: 'القيمة', r: 1, h: b => money(r2(n0(b.qty) * n0(b.rate))) },
        { t: 'المنفذ', r: 1, h: b => `${qtyTxt(lastQty[b.id] || 0)} <span class="small muted">${n0(b.qty) ? Math.round(100 * n0(lastQty[b.id]) / n0(b.qty)) : 0}%</span>` }], boq,
        { empty: 'أضف بنود العقد بكمياتها وأسعارها', onRow: true, foot: `<td colspan="5">${esc(tr('الإجمالي'))}</td><td class="r num">${money(ct.boq_total)}</td><td></td>` })}</div>
    <div class="card" id="clmc"><div class="row" style="justify-content:space-between;align-items:center;flex-wrap:wrap;gap:6px"><h2>${esc(tr('المستخلصات'))}</h2>
      ${can('sales') && !hasFinal ? `<div class="row" style="gap:6px"><button class="btn sm" id="nadv">${esc(tr('دفعة مقدمة'))}</button><button class="btn sm pri" id="nclm">${esc(tr('مستخلص جديد'))}</button></div>` : ''}</div>
      ${tbl([{ t: 'الرقم', h: c => `<span class="num">${esc(c.no)}</span>` }, { t: 'النوع', h: c => esc(tr(CLAIM_KIND[c.kind])) }, { t: 'التاريخ', h: c => fdate(c.date) },
        { t: 'أعمال الفترة', r: 1, h: c => money(c.this_gross) }, { t: 'استرداد الدفعة', r: 1, h: c => n0(c.advance_recovery) ? money(c.advance_recovery) : '' },
        { t: 'قيمة الفاتورة', r: 1, h: c => money(c.net) }, { t: 'الضريبة', r: 1, h: c => money(c.vat) }, { t: 'المحتجز', r: 1, h: c => n0(c.retention) ? money(c.retention) + (c.retention_released_on ? ` <span class="badge ok">${esc(tr('استُلم'))}</span>` : '') : '' },
        { t: 'المطلوب سداده', r: 1, h: c => `<b>${money(c.payable)}</b>` }, { t: 'الحالة', h: c => c.status !== 'approved' ? `<span class="badge">${esc(tr('مسودة'))}</span>` : !claimLive(c) ? `<span class="badge bad">${esc(tr('أُلغي بإشعار دائن'))}</span>` : `<span class="badge ok">${esc(tr('معتمد'))}</span>` + (n0(c.credited) ? ` <span class="badge wait">${esc(tr('عليه إشعار دائن'))} <span class="num">${money(c.credited)}</span></span>` : '') }],
        claims, { empty: 'لا توجد مستخلصات', onRow: true })}
      <p class="small muted">${esc(tr('حسب دليل هيئة الزكاة والضريبة والجمارك لقطاع المقاولات: الدفعة المقدمة تصدر لها فاتورة ضريبية عند استلامها، وكل مستخلص يُفوتر الأعمال المنفذة حتى تاريخه مخصوما منها ما فُوتر سابقا (ومنه الدفعة المقدمة المستردة)، ومحتجز الضمان جزء من قيمة الفاتورة تُحسب عليه الضريبة ولا تصدر فاتورة عند استرداده. نسب الاحتجاز والاسترداد من عقد المشروع.'))}</p></div>`;
  const boqForm = b => { const d = modal(b ? tr('تعديل البند') : tr('بند جديد'), `<div class="fg">${field('الرمز', inp('code', b && b.code, 'maxlength="30"'))}${field('الوحدة', inp('unit', b && b.unit, 'maxlength="30"'))}
      ${field('وصف البند', inp('description', b && b.description, 'required maxlength="300"'), 'wide')}${field('الكمية', inp('qty', b && b.qty, 'type="number" step="0.001" min="0" required'))}${field('سعر الوحدة', inp('rate', b && b.rate, 'type="number" step="0.01" min="0" required'))}</div>
      ${b ? `<button type="button" class="btn danger sm" id="bdel">${esc(tr('حذف البند'))}</button>` : ''}`, {
    onOk: async f => { const row = { code: blank(f.code), unit: blank(f.unit), description: f.description, qty: +f.qty, rate: +f.rate };
      if (b) await db.upd('project_boq', { id: 'eq.' + b.id }, row); else await db.ins('project_boq', Object.assign(row, { company_id: S.cid, project_id: p.id, sort: boq.length })); toast(tr('تم الحفظ')); route(); } });
    if (b) $('#bdel', d).onclick = async () => { try { await db.del('project_boq', { id: 'eq.' + b.id }); d.close(); route(); } catch (e) { showErr($('#merr', d), e); } }; };
  if ($('#nboq', body)) { $('#nboq', body).onclick = () => boqForm(null); bindRows($('#boqc', body), boq, b => boqForm(b)); }
  const claimForm = (c, kind) => {
    const k = c ? c.kind : kind, cur = {}; (c ? c.lines : []).forEach(l => cur[l.boq] = l.qty);
    const d = modal((c ? tr('تعديل') + ' ' + c.no : tr(CLAIM_KIND[k])), `<div class="fg">${k === 'advance' ? '' : field('النوع', `<select name="kind">${opt('interim', tr('مستخلص جارٍ'), k)}${opt('final', tr('مستخلص ختامي'), k)}</select>`)}
        ${field('التاريخ', `<input type="date" name="date" value="${esc(c ? c.date : today())}" max="${today()}">`)}${k === 'advance' ? field('مبلغ الدفعة المقدمة (قبل الضريبة)', inp('advance', c ? c.this_gross : '', 'type="number" min="0.01" step="0.01" required')) : field('الأعمال حتى تاريخ', `<input type="date" name="period_to" value="${esc(c && c.period_to || today())}">`)}
        ${field('ملاحظة', inp('note', c && c.note, 'maxlength="300"'), 'wide')}</div>
      ${k === 'advance' ? '' : `<p class="small">${esc(tr('أدخل الكمية المنفذة حتى تاريخه (تراكمية) لكل بند.'))}</p>` + tbl([{ t: 'البند', h: b => esc((b.code ? b.code + ' — ' : '') + b.description) }, { t: 'كمية العقد', r: 1, h: b => qtyTxt(b.qty) },
        { t: 'السابق', r: 1, h: b => qtyTxt(lastQty[b.id] || 0) }, { t: 'حتى تاريخه', h: b => `<input type="number" data-bq="${b.id}" step="0.001" min="${n0(lastQty[b.id])}" max="${n0(b.qty)}" value="${cur[b.id] != null ? cur[b.id] : n0(lastQty[b.id])}" style="width:110px" aria-label="${esc(tr('حتى تاريخه'))}">` }], boq)}`,
      { wide: true, ok: 'حفظ كمسودة', onOk: async f => {
        const lines = $$('[data-bq]', d).map(i => ({ boq: i.dataset.bq, qty: +i.value || 0 })).filter(l => l.qty > 0);
        const id = await db.rpc('claim_save', { p_project: p.id, p_doc: { id: c ? c.id : null, kind: f.kind || k, date: f.date, period_to: f.period_to || null, advance: f.advance ? +f.advance : null, lines, note: f.note } });
        toast(tr('حُفظ المستخلص')); route(); setTimeout(() => claimView(id), 400); } }); };
  if ($('#nclm', body)) $('#nclm', body).onclick = () => { if (!boq.length) return toast(tr('أضف بنود العقد أولا')); claimForm(null, 'interim'); };
  if ($('#nadv', body)) $('#nadv', body).onclick = () => claimForm(null, 'advance');
  const claimView = async id => { const [c] = await db.get('project_claims', { id: 'eq.' + id }); if (!c) return;
    const row = (t, v, b) => `<tr><td>${b ? '<b>' : ''}${esc(tr(t))}${b ? '</b>' : ''}</td><td class="r num">${b ? '<b>' : ''}${v}${b ? '</b>' : ''}</td></tr>`;
    const d = modal(c.no + ' — ' + tr(CLAIM_KIND[c.kind]), `<div class="tw"><table><tbody>
        ${c.kind === 'advance' ? row('الدفعة المقدمة', money(c.this_gross)) : row('الأعمال المنفذة حتى تاريخه', money(c.gross_to_date)) + row('المستخلصات السابقة', '−' + money(c.previous_gross)) + row('أعمال هذه الفترة', money(c.this_gross)) + (n0(c.advance_recovery) ? row('استرداد الدفعة المقدمة', '−' + money(c.advance_recovery)) : '')}
        ${row('قيمة الفاتورة قبل الضريبة', money(c.net), 1)}${row('ضريبة القيمة المضافة 15%', money(c.vat))}${row('إجمالي الفاتورة', money(n0(c.net) + n0(c.vat)))}
        ${n0(c.retention) ? row('محتجز ضمان حسن التنفيذ', '−' + money(c.retention)) : ''}${row('المطلوب سداده الآن', money(c.payable), 1)}</tbody></table></div>
      <div class="row" style="gap:6px;margin-top:10px;flex-wrap:wrap">${c.status === 'draft' && can('sales') ? `<button type="button" class="btn pri" id="cap">${esc(tr('اعتماد وإصدار الفاتورة'))}</button><button type="button" class="btn" id="ced">${esc(tr('تعديل'))}</button><button type="button" class="btn danger" id="cdl">${esc(tr('حذف'))}</button>` : ''}
        ${c.invoice_id ? `<a class="btn" href="#/sales/${c.invoice_id}">${esc(tr('الفاتورة'))}</a>` : ''}${claimLive(c) && n0(c.retention) && !c.retention_released_on && can('sales') ? `<button type="button" class="btn" id="crr">${esc(tr('استُلم المحتجز'))}</button>` : ''}
        <button type="button" class="btn" id="cpr">${esc(tr('طباعة المستخلص'))}</button></div>`, { wide: true });
    if ($('#cap', d)) $('#cap', d).onclick = () => busy($('#cap', d), async () => { try { const iid = await db.rpc('claim_approve', { p_id: c.id }); d.close(); toast(tr('اعتُمد المستخلص وصدرت فاتورته')); if (typeof zatcaKick === 'function') zatcaKick(); route(); } catch (e) { showErr($('#merr', d), e); } });
    if ($('#ced', d)) $('#ced', d).onclick = () => { d.close(); claimForm(c); };
    if ($('#cdl', d)) $('#cdl', d).onclick = async () => { try { await db.rpc('claim_delete', { p_id: c.id }); d.close(); route(); } catch (e) { showErr($('#merr', d), e); } };
    if ($('#crr', d)) $('#crr', d).onclick = async () => { try { await db.rpc('claim_retention_released', { p_id: c.id, p_date: today() }); d.close(); toast(tr('تم')); route(); } catch (e) { showErr($('#merr', d), e); } };
    $('#cpr', d).onclick = () => { const n = document.createElement('div'); n.className = 'pdoc';
      const bl = c.kind === 'advance' ? '' : `<table class="pt"><thead><tr><th>${esc(tr('البند'))}</th><th>${esc(tr('الوحدة'))}</th><th>${esc(tr('كمية العقد'))}</th><th>${esc(tr('السعر'))}</th><th>${esc(tr('المنفذ حتى تاريخه'))}</th><th>${esc(tr('القيمة'))}</th></tr></thead><tbody>
        ${(c.lines || []).map(l => { const b = boq.find(x => x.id === l.boq) || {}; return `<tr><td>${esc((b.code ? b.code + ' — ' : '') + (b.description || ''))}</td><td>${esc(b.unit || '')}</td><td class="num">${qtyTxt(b.qty)}</td><td class="num">${money(b.rate)}</td><td class="num">${qtyTxt(l.qty)}</td><td class="num">${money(r2(n0(l.qty) * n0(b.rate)))}</td></tr>`; }).join('')}</tbody></table>`;
      n.innerHTML = printHead(tr(CLAIM_KIND[c.kind]) + ' ' + c.no) + `<p>${esc(tr('المشروع'))}: <b>${esc(p.name)}</b> <span class="num">${esc(p.no)}</span> · ${esc(tr('التاريخ'))} ${fdate(c.date)}${c.period_to ? ' · ' + esc(tr('الأعمال حتى تاريخ')) + ' ' + fdate(c.period_to) : ''}</p>` + bl + $('.tw', d).outerHTML
        + `<div style="display:flex;justify-content:space-between;margin-top:40px"><div>${esc(tr('إعداد'))}: ____________</div><div>${esc(tr('اعتماد الاستشاري / العميل'))}: ____________</div></div>`;
      printWith(n, '@page{size:A4 portrait;margin:12mm}'); };
  };
  bindRows($('#clmc', body), claims, c => claimView(c.id));
}

/* ---------- «أوامر التغيير» ---------- */
const coQty = x => x.boq ? `<span class="muted">${qtyTxt(x.old_qty)} ←</span> ${qtyTxt(x.qty)}` : qtyTxt(x.qty), coRate = x => x.boq && n0(x.old_rate) !== n0(x.rate) ? `<span class="muted">${money(x.old_rate)} ←</span> ${money(x.rate)}` : money(x.rate);
async function projectChangesTab(body, p) {
  const [cos, vers, boq] = await Promise.all([db.get('project_change_orders', Object.assign(C(), { project_id: 'eq.' + p.id, order: 'created_at' })), db.get('project_versions', Object.assign(C(), { project_id: 'eq.' + p.id, order: 'at' })),
    db.get('project_boq', Object.assign(C(), { project_id: 'eq.' + p.id, order: 'sort,created_at' }))]);
  body.innerHTML = `<div class="card"><div class="row" style="justify-content:space-between;align-items:center"><h2>${esc(tr('أوامر التغيير'))}</h2><button class="btn sm pri" id="nco">${esc(tr('أمر تغيير جديد'))}</button></div>
      ${tbl([{ t: 'الرقم', h: o => `<span class="num">${esc(o.no)}</span>` }, { t: 'العنوان', h: o => esc(o.title) }, { t: 'التاريخ', h: o => fdate(o.date) }, { t: 'أثر القيمة', r: 1, h: o => `<span class="num ${n0(o.value_delta) < 0 ? 'bad' : ''}">${money(o.value_delta)}</span>` },
        { t: 'أثر المدة', r: 1, h: o => `<span class="num">${o.days_delta} ${esc(tr('يوما'))}</span>` }, { t: 'الحالة', h: o => `<span class="badge ${CO_ST[o.status][1]}">${esc(tr(CO_ST[o.status][0]))}</span>${o.decided_by_name ? `<div class="small muted">${esc(o.decided_by_name)}</div>` : ''}` }],
        cos, { empty: 'لا توجد أوامر تغيير', onRow: true })}</div>
    ${vers.length ? `<div class="card"><h2>${esc(tr('سجل نسخ العقد'))}</h2>${tbl([{ t: 'قبل أمر التغيير', h: v => esc((cos.find(o => o.id === v.co_id) || {}).no || '') }, { t: 'التاريخ', h: v => fdate(v.at) },
        { t: 'قيمة العقد', r: 1, h: v => money(v.contract_value) }, { t: 'التسليم', h: v => fdate(v.due_date) }, { t: 'موازنة التكلفة', r: 1, h: v => money(v.cost_budget) }, { t: 'قيمة البنود', r: 1, h: v => money(v.boq_total) }], vers)}</div>` : ''}`;
  const coForm = o => { const items = o ? o.items.filter(x => !x.boq) : [], edits = o ? o.items.filter(x => x.boq) : [];
    const d = modal(o ? tr('تعديل') + ' ' + o.no : tr('أمر تغيير جديد'), `<div class="fg">${field('العنوان', inp('title', o && o.title, 'required maxlength="200"'), 'wide')}${field('السبب والوصف', `<textarea name="reason" rows="2" maxlength="1000">${esc(o && o.reason || '')}</textarea>`, 'wide')}
        ${field('أثره على قيمة العقد (+ أو −)', inp('value', o ? o.value_delta : '', 'type="number" step="0.01"'))}${field('أثره على المدة بالأيام (+ أو −)', inp('days', o ? o.days_delta : 0, 'type="number" step="1"'))}
        ${field('أثره على موازنة التكلفة', inp('cost', o ? o.cost_delta : '', 'type="number" step="0.01"'))}</div>
      <p class="small">${esc(tr('بنود جديدة تُضاف للعقد عند الاعتماد (اختياري):'))}</p><div class="tw"><table class="lines"><thead><tr><th>${esc(tr('الرمز'))}</th><th>${esc(tr('البند'))}</th><th>${esc(tr('الوحدة'))}</th><th>${esc(tr('الكمية'))}</th><th>${esc(tr('السعر'))}</th></tr></thead><tbody id="coi"></tbody></table></div>
      <button type="button" class="btn sm" id="coa" style="margin-top:6px">+ ${esc(tr('بند'))}</button>
      ${boq.length ? `<p class="small" style="margin-top:12px">${esc(tr('تعديل كمية أو سعر بند قائم (لا تقل الكمية عن المنفذ، ولا يتغير سعر بند طُولب به):'))}</p><div class="tw"><table class="lines"><thead><tr><th>${esc(tr('البند'))}</th><th>${esc(tr('الكمية الجديدة'))}</th><th>${esc(tr('السعر الجديد'))}</th></tr></thead><tbody id="coe"></tbody></table></div>
        <button type="button" class="btn sm" id="coea" style="margin-top:6px">+ ${esc(tr('تعديل بند'))}</button>` : ''}
      <p class="small" id="covh"></p>`, { wide: true, onOk: async f => {
        const its = $$('#coi tr', d).map(r => ({ code: $('[data-c=code]', r).value, description: $('[data-c=description]', r).value, unit: $('[data-c=unit]', r).value, qty: +$('[data-c=qty]', r).value || 0, rate: +$('[data-c=rate]', r).value || 0 })).filter(x => x.description.trim()).concat(editRows());
        await db.rpc('co_save', { p_project: p.id, p_doc: { id: o ? o.id : null, title: f.title, reason: f.reason, value: +f.value || 0, days: +f.days || 0, cost: +f.cost || 0, items: its } }); toast(tr('تم الحفظ')); route(); } });
    const add = x => $('#coi', d).insertAdjacentHTML('beforeend', `<tr><td><input data-c="code" value="${esc(x.code || '')}" style="width:70px"></td><td><input data-c="description" value="${esc(x.description || '')}" style="min-width:180px"></td><td><input data-c="unit" value="${esc(x.unit || '')}" style="width:70px"></td>
      <td><input data-c="qty" type="number" step="0.001" min="0" value="${esc(x.qty == null ? '' : x.qty)}" style="width:90px"></td><td><input data-c="rate" type="number" step="0.01" min="0" value="${esc(x.rate == null ? '' : x.rate)}" style="width:100px"></td></tr>`);
    const editRows = () => $$('#coe tr', d).map(r => ({ boq: $('[data-e=boq]', r).value, qty: +$('[data-e=qty]', r).value || 0, rate: +$('[data-e=rate]', r).value || 0 })).filter(x => x.boq);
    const addE = x => { $('#coe', d).insertAdjacentHTML('beforeend', `<tr><td><select data-e="boq" style="min-width:180px" aria-label="${esc(tr('البند'))}"><option value="">—</option>${boq.map(b => opt(b.id, (b.code ? b.code + ' — ' : '') + b.description, x.boq)).join('')}</select></td>
      <td><input data-e="qty" type="number" step="0.001" min="0" value="${esc(x.qty == null ? '' : x.qty)}" style="width:100px" aria-label="${esc(tr('الكمية الجديدة'))}"></td><td><input data-e="rate" type="number" step="0.01" min="0" value="${esc(x.rate == null ? '' : x.rate)}" style="width:100px" aria-label="${esc(tr('السعر الجديد'))}"></td></tr>`); };
    // the effect of the items on the contract, offered as the change's value
    let hintV = null;
    const hint = () => { let v = 0; $$('#coi tr', d).forEach(r => v += n0($('[data-c=qty]', r).value) * n0($('[data-c=rate]', r).value));
      editRows().forEach(x => { const b = boq.find(y => y.id === x.boq); if (b) v += x.qty * x.rate - n0(b.qty) * n0(b.rate); }); v = r2(v); if (v === hintV) return; hintV = v;   // redrawing on the blur of a field would swallow the click on the button
      $('#covh', d).innerHTML = v ? `${esc(tr('أثر البنود على قيمة العقد'))}: <b class="num">${money(v)}</b> <button type="button" class="btn sm" id="covu">${esc(tr('استخدمه'))}</button>` : '';
      if ($('#covu', d)) $('#covu', d).onclick = () => { $('[name=value]', d).value = v; }; };
    items.forEach(add); $('#coa', d).onclick = () => add({});
    if ($('#coe', d)) { edits.forEach(addE); $('#coea', d).onclick = () => addE({}); $('#coe', d).addEventListener('change', e => { if (e.target.dataset.e !== 'boq') return; const b = boq.find(y => y.id === e.target.value), r = e.target.closest('tr'); if (b) { $('[data-e=qty]', r).value = +b.qty; $('[data-e=rate]', r).value = +b.rate; } }); }
    d.addEventListener('input', hint); d.addEventListener('change', hint); hint(); };
  $('#nco', body).onclick = () => coForm(null);
  bindRows(body.querySelector('.card'), cos, o => {
    const url = o.token ? location.origin + location.pathname + '#/co/' + o.token : '';
    const d = modal(o.no + ' — ' + o.title, `<p>${esc(o.reason || '')}</p><p>${esc(tr('أثر القيمة'))} <b class="num">${money(o.value_delta)}</b> · ${esc(tr('أثر المدة'))} <b class="num">${o.days_delta}</b> ${esc(tr('يوما'))} · ${esc(tr('أثر التكلفة'))} <span class="num">${money(o.cost_delta)}</span></p>
      ${o.items.length ? tbl([{ t: 'البند', h: x => esc(x.description) }, { t: 'الكمية', r: 1, h: coQty }, { t: 'السعر', r: 1, h: coRate }], o.items) : ''}
      <p><span class="badge ${CO_ST[o.status][1]}">${esc(tr(CO_ST[o.status][0]))}</span> ${o.decided_by_name ? esc(o.decided_by_name) + ' · ' + fdate(o.decided_at) : ''} ${o.decision_note ? '· ' + esc(o.decision_note) : ''}</p>
      ${url ? `<input readonly dir="ltr" value="${esc(url)}" id="cou">` : ''}
      ${['draft', 'sent', 'rejected'].includes(o.status) ? `<div class="row" style="gap:6px;margin-top:10px;flex-wrap:wrap"><button type="button" class="btn pri" id="cos">${esc(tr(o.token ? 'نسخ رابط العميل' : 'إرسال للعميل للاعتماد'))}</button>
        ${o.status !== 'rejected' && prjOffice() ? `<button type="button" class="btn" id="coin">${esc(tr('تسجيل قرار العميل'))}</button>` : ''}<button type="button" class="btn" id="coe">${esc(tr('تعديل'))}</button></div>` : ''}`, { wide: true });
    if ($('#cos', d)) $('#cos', d).onclick = async () => { try { const t = o.token || await db.rpc('co_send', { p_id: o.id }); const u = location.origin + location.pathname + '#/co/' + t;
      try { await navigator.clipboard.writeText(u); } catch (e) {} toast(tr('نُسخ رابط الاعتماد — أرسله للعميل')); d.close(); route(); } catch (e) { showErr($('#merr', d), e); } };
    if ($('#coe', d)) $('#coe', d).onclick = () => { d.close(); coForm(o); };
    if ($('#coin', d)) $('#coin', d).onclick = () => { d.close(); modal(tr('تسجيل قرار العميل'), `<div class="fg">${field('القرار', `<select name="ok">${opt('1', tr('اعتمد'))}${opt('0', tr('رفض'))}</select>`)}${field('اسم من اعتمد من طرف العميل', inp('n', '', 'required maxlength="120"'))}${field('ملاحظة', inp('note', '', 'maxlength="500"'), 'wide')}</div>`,
      { onOk: async f => { await db.rpc('co_decide_internal', { p_id: o.id, p_ok: f.ok === '1', p_name: f.n, p_note: f.note }); toast(tr('تم')); route(); } }); };
  });
}

/* ---------- the customer's page for a change order: #/co/<token>, no sign-in ---------- */
const coToken = () => (location.hash.match(/^#\/co\/([0-9a-f]{64})/) || [])[1] || null;
async function coPublicView(token) {
  document.title = tr('اعتماد أمر تغيير') + ' — ' + tr('وعد');
  $('#app').innerHTML = `<div class="portal"><div class="muted">${esc(tr('جاري التحميل…'))}</div></div>`;
  let o = null; try { o = await db.rpc('co_view', { p_token: token }); } catch (e) { o = null; }
  const box = $('.portal');
  if (!o) { box.innerHTML = `<div class="card"><h2>${esc(tr('الرابط غير صالح'))}</h2></div>`; return; }
  box.innerHTML = `<div class="phead"><div><h1>${esc(o.company)}</h1><div class="small muted">${esc(tr('اعتماد أمر تغيير'))} · ${esc(o.project)} <span class="num">${esc(o.project_no)}</span></div></div><div class="sp"></div><button class="btn sm" id="plg">${LANG === 'en' ? 'العربية' : 'English'}</button></div>
    <div class="card"><h2>${esc(o.no)} — ${esc(o.title)}</h2><p>${esc(o.reason || '')}</p>
      <p>${esc(tr('أثره على قيمة العقد'))}: <b class="num">${money(o.value)}</b> · ${esc(tr('أثره على المدة'))}: <b class="num">${o.days}</b> ${esc(tr('يوما'))}</p>
      ${(o.items || []).length ? tbl([{ t: 'البند', h: x => esc(x.description) }, { t: 'الوحدة', h: x => esc(x.unit || '') }, { t: 'الكمية', r: 1, h: coQty }, { t: 'السعر', r: 1, h: coRate }, { t: 'القيمة', r: 1, h: x => money(r2(n0(x.qty) * n0(x.rate))) }], o.items) : ''}
      ${o.status === 'sent' ? `<form id="cof" class="fg" style="margin-top:12px" novalidate>${field('اسمك وصفتك', inp('n', '', 'required maxlength="120"'))}${field('ملاحظة (اختياري)', inp('note', '', 'maxlength="500"'))}</form><div id="coerr"></div>
        <div class="row" style="gap:8px;margin-top:10px"><button class="btn pri" id="coy">${esc(tr('أعتمد أمر التغيير'))}</button><button class="btn danger" id="con">${esc(tr('أرفض'))}</button></div>`
        : `<p><span class="badge ${CO_ST[o.status][1]}">${esc(tr(CO_ST[o.status][0]))}</span> ${esc(o.decided_by || '')} ${o.decided_at ? fdate(o.decided_at) : ''}</p>`}</div>
    <p class="small muted" style="text-align:center">${esc(tr('هذه الصفحة خاصة بكم؛ لا تشاركوا رابطها.'))} · ${esc(tr('نظام وعد'))}</p>`;
  $('#plg').onclick = () => { setLang(LANG === 'en' ? 'ar' : 'en'); coPublicView(token); };
  const dec = ok => async () => { const f = formData($('#cof')); try { await db.rpc('co_decide', { p_token: token, p_ok: ok, p_name: f.n, p_note: f.note || null }); coPublicView(token); } catch (e) { showErr($('#coerr'), e); } };
  if ($('#coy')) { $('#coy').onclick = dec(true); $('#con').onclick = dec(false); }
}

/* ---------- «المخاطر» ---------- */
const riskCls = s => s >= 15 ? 'bad' : s >= 8 ? 'wait' : 'ok';
async function projectRisksTab(body, p, em) {
  const rs = await db.get('project_risks', Object.assign(C(), { project_id: 'eq.' + p.id, order: 'status,created_at' }));
  const nm = e => e ? ((LANG === 'en' && e.full_name_en) || e.full_name) : '—';
  body.innerHTML = `<div class="card"><div class="row" style="justify-content:space-between;align-items:center"><h2>${esc(tr('سجل المخاطر'))}</h2><button class="btn sm pri" id="nrk">${esc(tr('خطر جديد'))}</button></div>
    ${tbl([{ t: 'الخطر', h: r => esc(r.title) + (r.mitigation ? `<div class="small muted">${esc(r.mitigation)}</div>` : '') }, { t: 'الاحتمال', r: 1, h: r => `<span class="num">${r.probability}</span>` }, { t: 'الأثر', r: 1, h: r => `<span class="num">${r.impact}</span>` },
      { t: 'الدرجة', r: 1, h: r => `<span class="badge ${riskCls(r.probability * r.impact)} num">${r.probability * r.impact}</span>` }, { t: 'المسؤول', h: r => esc(nm(em[r.owner_id])) },
      { t: 'الحالة', h: r => r.status === 'open' ? `<span class="badge wait">${esc(tr('قائم'))}</span>` : `<span class="badge ok">${esc(tr('مغلق'))}</span>` }], rs, { empty: 'لا توجد مخاطر مسجلة', onRow: true })}
    <p class="small muted">${esc(tr('الدرجة = الاحتمال × الأثر (من 1 إلى 5 لكل منهما): 15 فأكثر عالية، 8–14 متوسطة.'))}</p></div>`;
  const emps = Object.values(em).filter(e => !e.end_date);
  const form = r => { const d = modal(r ? tr('تعديل الخطر') : tr('خطر جديد'), `<div class="fg">${field('الخطر', inp('title', r && r.title, 'required maxlength="200"'), 'wide')}
      ${field('الاحتمال (1–5)', `<select name="probability">${[1, 2, 3, 4, 5].map(v => opt(v, v, r ? r.probability : 3)).join('')}</select>`)}${field('الأثر (1–5)', `<select name="impact">${[1, 2, 3, 4, 5].map(v => opt(v, v, r ? r.impact : 3)).join('')}</select>`)}
      ${field('المسؤول', `<select name="owner_id"><option value="">—</option>${emps.map(e => opt(e.id, nm(e), r && r.owner_id)).join('')}</select>`)}${field('الحالة', `<select name="status">${opt('open', tr('قائم'), r && r.status)}${opt('closed', tr('مغلق'), r && r.status)}</select>`)}
      ${field('خطة المعالجة', `<textarea name="mitigation" rows="2" maxlength="1000">${esc(r && r.mitigation || '')}</textarea>`, 'wide')}</div>`, {
    onOk: async f => { const row = { title: f.title, probability: +f.probability, impact: +f.impact, owner_id: blank(f.owner_id), status: f.status, mitigation: blank(f.mitigation) };
      if (r) await db.upd('project_risks', { id: 'eq.' + r.id }, row); else await db.ins('project_risks', Object.assign(row, { company_id: S.cid, project_id: p.id })); toast(tr('تم الحفظ')); route(); } }); };
  $('#nrk', body).onclick = () => form(null);
  bindRows(body, rs, r => form(r));
}

/* ---------- «إشغال الفريق»: who is booked on which project, week by week ---------- */
VIEWS['#/resources'] = async page => {
  if (!has('owner', 'admin', 'finance', 'hr') && !can('proj')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  const [rows, em] = await Promise.all([db.rpc('resource_load', { p_company: S.cid, p_weeks: 8 }), employeesMap(true)]);
  const weeks = [...Array(8)].map((_, i) => { const d = new Date(); d.setDate(d.getDate() - ((d.getDay() + 6) % 7) + i * 7); return d.toISOString().slice(0, 10); });
  const emps = [...new Set(rows.map(r => r.employee_id))].map(id => em[id]).filter(Boolean);
  const cell = (eid, w) => rows.find(r => r.employee_id === eid && r.week === w);
  const col = a => a > 100 ? 'background:rgba(220,38,38,.18)' : a >= 80 ? 'background:rgba(217,119,6,.16)' : a > 0 ? 'background:rgba(22,163,74,.12)' : '';
  page.innerHTML = `<div class="head"><div><a href="#/projects" class="small back">${esc(tr('المشاريع'))}</a><h1>${esc(tr('إشغال الفريق'))}</h1><div class="muted small">${esc(tr('نسبة تفرغ كل موظف على المشاريع الجارية أسبوعا بأسبوع، من «فريق المشروع». الأحمر فوق 100%.'))}</div></div></div>
    ${emps.length ? `<div class="tw"><table><thead><tr><th>${esc(tr('الموظف'))}</th>${weeks.map(w => `<th class="num small">${esc(w.slice(5))}</th>`).join('')}</tr></thead><tbody>
      ${emps.map(e => `<tr><td>${esc((LANG === 'en' && e.full_name_en) || e.full_name)}</td>${weeks.map(w => { const c = cell(e.id, w); return `<td class="num" style="text-align:center;${col(c ? c.alloc : 0)}" title="${c ? esc(c.projects.map(x => x.no + ' ' + x.name + ' ' + x.alloc + '%').join(' · ')) : ''}">${c ? c.alloc + '%' : ''}</td>`; }).join('')}</tr>`).join('')}</tbody></table></div>`
      : `<div class="note">${esc(tr('حدّد نسبة تفرغ أعضاء الفريق في كل مشروع (تبويب «الفريق») ليظهر الإشغال هنا.'))}</div>`}`;
};

/* ---------- the bell: hours to approve, rejected hours, instalments and guarantees ---------- */
async function projNotifs(add, safe) {
  if (!modOn('proj') && !isFin()) return;
  if (modOn('proj') && (S.emp || prjOffice())) { const p = await safe(db.rpc('timesheets_pending', { p_company: S.cid })); NAVC.time = (p || []).length;
    if (NAVC.time) add(NAVC.time + ' تسجيل ساعات عمل بانتظار اعتمادك', '#/mytime', { hot: 1 });
    if (S.emp) { const since = new Date(Date.now() - 7 * 864e5).toISOString(), r = await safe(db.get('timesheets', { employee_id: 'eq.' + S.emp, status: 'eq.rejected', reviewed_at: 'gte.' + since, select: 'id,reviewed_at' })); (r || []).forEach(x => add('رُفضت ساعات عمل لك — راجع السبب', '#/mytime', { at: x.reviewed_at })); } }
  if (can('je') || can('reports')) { const a = await safe(db.rpc('facility_alerts', { p_company: S.cid })); if (!a) return;
    if (a.instalments.length) add(a.instalments.length + ' أقساط قروض مستحقة أو قريبة', '#/facilities', { hot: 1 });
    if (a.guarantees.length) add(a.guarantees.length + ' خطابات ضمان تنتهي خلال 30 يوما', '#/facilities', { hot: 1 }); }
}
/* «المرحلة» appears once a project with milestones is chosen in the cost-center picker */
function bindMsPick(root, cur) {
  const sel = $('[name=cost_center]', root), box = $('#msw', root); if (!sel || !box) return;
  const fill = async () => { if (!sel.value) { box.innerHTML = ''; return; } const ms = await db.rpc('cc_milestones', { p_company: S.cid, p_cc: sel.value }).catch(() => []);
    box.innerHTML = ms.length ? field('المرحلة', `<select name="milestone"><option value="">—</option>${ms.map(m => opt(m.id, m.name, cur)).join('')}</select>`) : ''; };
  sel.addEventListener('change', fill); fill();
}
