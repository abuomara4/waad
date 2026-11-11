'use strict';
/* «النماذج»: ready-made forms for every department (forms_lib.js) and the company's own templates (form_templates),
   filled from the employee / customer / supplier record plus a few typed fields, numbered (F-YYYY-0001) and printed on the
   company letterhead in Arabic or English. Custom templates use the same placeholders; any {f:label} becomes a field. */
const formCanDept = d => d === 'hr' ? (isHR() || has('manager')) : isFin();
const formCanWrite = () => has('owner', 'admin', 'hr', 'finance');
const fT = (ar, en) => LANG === 'en' && en ? en : ar;   // library texts carry both languages (not passed through the translator)
const FORM_PH = [['{e.name}', 'اسم الموظف'], ['{e.no}', 'الرقم الوظيفي'], ['{e.job}', 'المسمى الوظيفي'], ['{e.dept}', 'القسم'], ['{e.id}', 'رقم الهوية/الإقامة'],
  ['{e.nat}', 'الجنسية'], ['{e.hire}', 'تاريخ المباشرة'], ['{e.gross}', 'إجمالي الراتب'], ['{e.mgr}', 'المدير المباشر'], ['{e.phone}', 'جوال الموظف'], ['{e.end}', 'آخر يوم عمل'], ['{p.name}', 'اسم العميل/المورد'], ['{p.vat}', 'رقمه الضريبي'],
  ['{c.name}', 'اسم المنشأة'], ['{date}', 'التاريخ'], ['{hijri}', 'التاريخ الهجري'], ['{no}', 'رقم النموذج'], ['{f:المبلغ}', 'خانة تكتبها وقت التعبئة']];
// fields of a custom template = the {f:…} tokens in its text, in order of appearance
const customFields = t => [...new Set([...String(t.body_ar || '').matchAll(/\{f:([^}]{1,40})\}/g)].map(m => m[1].trim()))].map(k => [k, k, k, /ملاحظ|تفاصيل|بنود|أصناف/.test(k) ? 'textarea' : 'text']);
const libAsTpl = x => ({ key: x.k, dept: x.dept, subject: x.subject, title_ar: x.t[0], title_en: x.t[1], body_ar: x.ar, body_en: x.en, fields: x.f, sigs: x.sig.map(s => SIG[s]), lib: true });
const dbAsTpl = r => ({ key: 'custom:' + r.id, id: r.id, dept: r.dept, subject: r.subject, title_ar: r.title_ar, title_en: r.title_en, body_ar: r.body_ar, body_en: r.body_en,
  fields: customFields(r), sigs: (r.sigs || []).map(s => [s, s]), lib: false, row: r });

VIEWS['#/forms'] = async page => {
  const depts = Object.keys(FORM_DEPTS).filter(d => modOn(d) && formCanDept(d));
  if (!depts.length) { page.innerHTML = `<div class="note">${esc(tr('النماذج لمدراء المنشأة.'))}</div>`; return; }
  const cur = depts.includes(LS.get('waad.formdept')) ? LS.get('waad.formdept') : depts[0];
  const [mine, log] = await Promise.all([db.get('form_templates', { company_id: 'eq.' + S.cid, order: 'created_at' }).catch(() => []),
    db.get('form_issues', { company_id: 'eq.' + S.cid, order: 'issued_at.desc', limit: 30 }).catch(() => [])]);
  const list = [...FORM_LIB.filter(x => x.dept === cur).map(libAsTpl), ...mine.filter(r => r.dept === cur).map(dbAsTpl)];
  const subjN = { employee: 'موظف', customer: 'عميل', supplier: 'مورد', party: 'عميل أو مورد', none: 'عام' };
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('النماذج'))}</h1><div class="muted">${esc(tr('نماذج جاهزة تتعبّى من بيانات الموظف أو العميل أو المورد، وتنطبع بترويسة منشأتك برقم مسلسل.'))}</div></div>
      ${formCanWrite() ? `<button class="btn pri" id="fnew">${esc(tr('نموذج جديد'))}</button>` : ''}</div>
    <div class="ptabs pfil">${depts.map(d => `<a href="#" data-fd="${d}" data-nt${d === cur ? ' aria-current="page"' : ''}>${esc(fT(...FORM_DEPTS[d]))}</a>`).join('')}</div>
    <div class="fgrid">${list.map((t, i) => `<button type="button" class="card fcard" data-fi="${i}"><b data-nt>${esc(fT(t.title_ar, t.title_en))}</b>
        <span class="small muted">${esc(tr(subjN[t.subject] || ''))}${t.lib ? (FORM_GRID[t.key] ? ' · ' + esc(tr('جدول بالعربي والإنجليزي')) : '') : ' · ' + esc(tr('نموذج منشأتك'))}</span></button>`).join('') || `<div class="empty">${esc(tr('ما فيه نماذج في هذا القسم.'))}</div>`}</div>
    <div class="card" style="margin-top:14px"><h2>${esc(tr('آخر النماذج المطبوعة'))}</h2>
      ${tbl([{ t: 'الرقم', h: r => `<span class="num">${esc(r.no)}</span>` }, { t: 'النموذج', h: r => `<span data-nt>${esc(r.title)}</span>` },
        { t: 'لـ', h: r => `<span data-nt>${esc(r.subject_name || '—')}</span>` }, { t: 'التاريخ', h: r => `<span class="num">${esc(String(r.issued_at).slice(0, 10))}</span>` }], log, { empty: 'ما طُبع شي للحين' })}</div>`;
  $$('[data-fd]', page).forEach(a => a.onclick = e => { e.preventDefault(); LS.set('waad.formdept', a.dataset.fd); route(); });
  $$('[data-fi]', page).forEach(b => b.onclick = () => formFill(list[+b.dataset.fi]));
  if ($('#fnew', page)) $('#fnew', page).onclick = () => formEdit({ dept: cur });
};

// ---- auto-fill: values taken from the system when the employee / customer / supplier is chosen (still editable) ----
const plusDays = (d, n) => new Date(new Date(String(d).slice(0, 10) + 'T12:00:00Z').getTime() + n * 864e5).toISOString().slice(0, 10);
async function lastRequest(empId, kind, statuses = ['approved']) {
  return (await db.get('requests', { company_id: 'eq.' + S.cid, employee_id: 'eq.' + empId, kind: 'eq.' + kind, status: 'in.(' + statuses.join(',') + ')', order: 'created_at.desc', limit: 1 }).catch(() => []))[0];
}
async function openDocs(partyId, key) {   // a customer's unpaid sales invoices / a supplier's unpaid bills
  const D = DOCS[key], docs = await db.get(D.table, { company_id: 'eq.' + S.cid, party_id: 'eq.' + partyId, status: 'eq.posted', order: 'date', select: 'id,no,date,due_date,total' }).catch(() => []);
  const paid = await paidMap(D, docs.map(x => x.id)).catch(() => ({}));
  return docs.map(x => Object.assign(x, { rem: Math.round((n0(x.total) - n0(paid[x.id])) * 100) / 100 })).filter(x => x.rem > 0.001);
}
const leaveName = async code => { const lt = await LEAVE_TYPES().catch(() => []), x = lt.find(l => l.code === code); return x ? x.name_ar : code || ''; };
const FORM_PRE = {
  hire_decision: async e => ({ start: e.hire_date }),
  clearance: async e => { const it = await db.get('custody_items', { employee_id: 'eq.' + e.id, status: 'eq.held', order: 'issued_on' }).catch(() => []);
    return { last: e.end_date || '', reason: e.end_reason || '', held: it.map(x => x.name + (x.serial ? ' — ' + x.serial : '')).join('\n') }; },
  joining: async e => ({ date: e.hire_date }),
  custody: async e => { const it = (await db.get('custody_items', { employee_id: 'eq.' + e.id, status: 'eq.held', order: 'issued_on' }).catch(() => []));
    return it.length ? { items: it.map(x => x.name + (x.serial ? ' — ' + x.serial : '')).join('\n'), value: String(it.reduce((a, x) => a + n0(x.value), 0)) } : {}; },
  leave_form: async e => { const r = await lastRequest(e.id, 'leave', ['approved', 'pending']); return r ? { type: await leaveName(r.sub), from: r.from_date, to: r.to_date, days: String(r.days || '') } : {}; },
  return_leave: async e => { const r = await lastRequest(e.id, 'leave'); return r ? { from: r.from_date, to: r.to_date, back: r.to_date ? plusDays(r.to_date, 1) : '' } : {}; },
  permission: async e => { const r = await lastRequest(e.id, 'permit', ['approved', 'pending']); return r ? { date: r.from_date, reason: r.note || '' } : {}; },
  resignation_accept: async e => { const r = await lastRequest(e.id, 'resign', ['approved', 'pending']); return { date: r ? String(r.created_at).slice(0, 10) : '', last: e.end_date || (r && r.to_date) || '' }; },
  termination: async e => ({ last: e.end_date || '', reason: e.end_reason || '' }),
  advance_request: async e => { const r = await lastRequest(e.id, 'advance', ['approved', 'pending']); return r ? { amount: String(r.amount || ''), reason: r.note || '' } : {}; },
  promotion: async e => ({ date: today() }), transfer: async e => ({ date: today() }), salary_change: async e => ({ date: today(), basic: String(e.basic || ''), housing: String(e.housing || ''), transport: String(e.transport || '') }),
  probation_confirm: async e => ({ date: today() }),
  payment_reminder: async p => { const o = await openDocs(p.id, 'sales'); return o.length ? { amount: o.reduce((a, x) => a + x.rem, 0).toFixed(2), invoices: o.map(x => x.no).join('، '), due: plusDays(today(), 7) } : { due: plusDays(today(), 7) }; },
  balance_confirm: async p => { const o = await openDocs(p.id, p.kind === 'supplier' ? 'purchases' : 'sales'), c = S.company || {};
    return { date: today(), amount: o.reduce((a, x) => a + x.rem, 0).toFixed(2), side: p.kind === 'supplier' ? p.name : c.name }; },
  delivery_ack: async p => { const inv = (await db.get('sales_invoices', { company_id: 'eq.' + S.cid, party_id: 'eq.' + p.id, status: 'eq.posted', order: 'date.desc', limit: 1 }).catch(() => []))[0];
    if (!inv) return { date: today() };
    const ln = await db.get('sales_invoice_lines', { invoice_id: 'eq.' + inv.id, select: 'qty,item_id' }).catch(() => []);
    const its = ln.length ? await db.get('items', { id: 'in.(' + [...new Set(ln.map(l => l.item_id))].join(',') + ')', select: 'id,name' }).catch(() => []) : [];
    const nm = Object.fromEntries(its.map(i => [i.id, i.name]));
    return { ref: inv.no, date: inv.date, items: ln.map(l => (nm[l.item_id] || '') + ' × ' + n0(l.qty)).join('\n') }; },
  supply_delay: async p => { const po = (await db.get('purchase_orders', { company_id: 'eq.' + S.cid, party_id: 'eq.' + p.id, status: 'eq.open', order: 'date.desc', limit: 1 }).catch(() => []))[0];
    return po ? { po: po.no, due: po.expected_date || '', by: plusDays(today(), 7) } : { by: plusDays(today(), 7) }; },
  final_notice: async p => { const o = await openDocs(p.id, 'sales'); return o.length ? { amount: o.reduce((a, x) => a + x.rem, 0).toFixed(2), invoices: o.map(x => x.no).join('، '), due: plusDays(today(), 3) } : { due: plusDays(today(), 3) }; },
  debt_ack: async p => { const o = await openDocs(p.id, 'sales'); return { date: today(), amount: o.reduce((a, x) => a + x.rem, 0).toFixed(2), due: plusDays(today(), 30) }; },
  installments: async p => { const o = await openDocs(p.id, 'sales'); return { total: o.reduce((a, x) => a + x.rem, 0).toFixed(2), first: plusDays(today(), 30) }; },
  salary_bank_letter: async e => ({ iban: e.iban || '' }),
  petty_request: async e => ({ until: plusDays(today(), 30) }),
  po_cancel: async p => { const po = (await db.get('purchase_orders', { company_id: 'eq.' + S.cid, party_id: 'eq.' + p.id, status: 'eq.open', order: 'date.desc', limit: 1 }).catch(() => []))[0]; return po ? { po: po.no } : {}; },
  inspection: async p => { const b = (await db.get('purchase_bills', { company_id: 'eq.' + S.cid, party_id: 'eq.' + p.id, status: 'eq.posted', order: 'date.desc', limit: 1 }).catch(() => []))[0]; return { date: today(), ref: b ? b.no : '' }; },
  quote_cover: async p => ({ valid: plusDays(today(), 15) }),
  return_supplier: async p => { const b = (await db.get('purchase_bills', { company_id: 'eq.' + S.cid, party_id: 'eq.' + p.id, status: 'eq.posted', order: 'date.desc', limit: 1 }).catch(() => []))[0]; return b ? { ref: b.no } : {}; },
};
// fill a form: who it is for, the language, and its own fields → numbered sheet → print
async function formFill(t) {
  const kinds = t.subject === 'party' ? ['customer', 'supplier'] : ['customer', 'supplier'].includes(t.subject) ? [t.subject] : [];
  const [emps, parties] = await Promise.all([t.subject === 'employee' ? employeesMap().catch(() => ({})) : {},
    kinds.length ? db.get('parties', { company_id: 'eq.' + S.cid, kind: 'in.(' + kinds.join(',') + ')', order: 'name' }).catch(() => []) : []]);
  const el = Object.values(emps).filter(e => !e.end_date).sort((a, b) => String(a.emp_no).localeCompare(String(b.emp_no)));
  const inputFor = ([k, la, le, ty]) => field(fT(la, le), ty === 'textarea' ? `<textarea name="f_${esc(k)}" rows="3"></textarea>`
    : `<input name="f_${esc(k)}" type="${ty === 'number' ? 'number' : ty === 'date' ? 'date' : ty === 'time' ? 'time' : 'text'}"${ty === 'number' ? ' step="0.01"' : ''}${ty === 'date' ? ` value="${today()}"` : ''}>`, ty === 'textarea' ? 'wide' : '');
  const d = modal(fT(t.title_ar, t.title_en), `<div class="fg">
      ${t.subject === 'employee' ? field('الموظف', `<select name="who" required>${el.map(e => opt(e.id, e.emp_no + ' — ' + e.full_name)).join('')}</select>`, 'wide') : ''}
      ${kinds.length ? field(t.subject === 'supplier' ? 'المورد' : t.subject === 'customer' ? 'العميل' : 'العميل أو المورد', `<select name="who" required>${parties.map(p => opt(p.id, p.name)).join('')}</select>`, 'wide') : ''}
      ${t.lib && FORM_GRID[t.key] ? `<input type="hidden" name="lang" value="ar"><div class="wide small muted">${esc(tr('يطلع بالعربي والإنجليزي معاً على نفس الورقة.'))}</div>` : field('لغة النموذج', `<select name="lang">${opt('ar', 'العربية', LANG)}${t.body_en ? opt('en', 'English', LANG) : ''}</select>`)}
      ${t.fields.map(inputFor).join('')}</div>
    ${(t.subject === 'employee' && !el.length) || (kinds.length && !parties.length) ? `<div class="note">${esc(tr('ما فيه سجلات تختار منها. أضفها أول.'))}</div>` : ''}
    ${!t.lib && formCanWrite() ? `<button type="button" class="btn sm" id="fedit" style="margin-top:8px">${esc(tr('تعديل النموذج'))}</button>` : ''}`, {
    wide: true, ok: 'معاينة وطباعة', onOk: async f => {
      const en = f.lang === 'en', who = t.subject === 'employee' ? emps[f.who] : kinds.length ? parties.find(p => p.id === f.who) : null;
      if ((t.subject === 'employee' || kinds.length) && !who) throw new Error('اختر من القائمة');
      const deps = t.subject === 'employee' ? await db.get('departments', { company_id: 'eq.' + S.cid }).catch(() => []) : [];
      deps.emps = emps;
      const vals = {}; t.fields.forEach(([k]) => { vals[k] = f['f_' + k] || ''; });
      const title = en ? (t.title_en || t.title_ar) : t.title_ar, whoName = who ? (en && who.full_name_en ? who.full_name_en : en && who.name_en ? who.name_en : who.full_name || who.name) : '';
      const no = await db.rpc('form_issue', { p_company: S.cid, p_template: t.key, p_title: title, p_subject: whoName || null, p_lang: en ? 'en' : 'ar' });
      formPrint(t, { en, no, who, vals, deps });
    } });
  if ($('#fedit', d)) $('#fedit', d).onclick = () => { d.close(); setTimeout(() => formEdit(t.row), 50); };
  // values from the system go into empty fields (or ones it filled before); a small note says where they came from
  $$('input[type=date]', d).forEach(i => { i.dataset.auto = '1'; });
  const pre = FORM_PRE[t.key], sel = d.querySelector('select[name=who]');
  const apply = async () => {
    if (!pre || (sel && !sel.value) || (!sel && t.subject !== 'none')) return;
    const rec = !sel ? null : t.subject === 'employee' ? emps[sel.value] : parties.find(p => p.id === sel.value);
    let v = {}; try { v = await pre(rec || {}, t) || {}; } catch (er) { v = {}; }
    $$('.fauto', d).forEach(x => x.remove());
    Object.entries(v).forEach(([k, val]) => { const i = d.querySelector(`[name="f_${k}"]`); if (!i || val == null || val === '') return;
      if (i.value && !i.dataset.auto) return; i.value = val; i.dataset.auto = '1';
      i.insertAdjacentHTML('afterend', `<div class="fauto small muted">${esc(tr('تعبّى من النظام — تقدر تعدّله'))}</div>`); });
  };
  d.querySelectorAll('input,textarea').forEach(i => i.addEventListener('input', () => { delete i.dataset.auto; }));
  if (sel) sel.onchange = apply;
  apply();
  return d;
}
// values of the placeholders in one language
function formVals(t, { en, no, who, deps }) {
  const c = S.company || {}, e = t.subject === 'employee' ? who || {} : {}, p = ['customer', 'supplier', 'party'].includes(t.subject) ? who || {} : {};
  const dep = (deps || []).find(x => x.id === e.department_id) || {};
  const nat = e.is_saudi ? (en ? 'Saudi' : 'سعودي') : e.nationality ? (en ? trTo(natName(e.nationality)) : natName(e.nationality)) : (en ? 'Non-Saudi' : 'غير سعودي');
  const gross = (+e.basic || 0) + (+e.housing || 0) + (+e.transport || 0), d0 = today();
  return { 'c.name': en && c.name_en ? c.name_en : c.name, 'c.cr': c.cr_no, 'c.vat': c.vat_no,
    'e.name': en && e.full_name_en ? e.full_name_en : e.full_name, 'e.no': e.emp_no, 'e.job': en && e.job_title_en ? e.job_title_en : e.job_title,
    'e.dept': en && dep.name_en ? dep.name_en : dep.name, 'e.idlabel': e.is_saudi ? (en ? 'National ID' : 'هوية وطنية') : (en ? 'Iqama' : 'إقامة'), 'e.id': e.national_id,
    'e.nat': who && t.subject === 'employee' ? nat : '', 'e.hire': e.hire_date, 'e.basic': e.basic != null ? money(e.basic) : '', 'e.housing': e.housing != null ? money(e.housing) : '',
    'e.transport': e.transport != null ? money(e.transport) : '', 'e.gross': who && t.subject === 'employee' ? money(gross) : '',
    'e.mgr': (() => { const m = (deps && deps.emps || {})[e.manager_id]; return m ? (en && m.full_name_en ? m.full_name_en : m.full_name) : ''; })(),
    'e.phone': e.phone, 'e.iban': e.iban, 'e.end': e.end_date,
    'p.name': en && p.name_en ? p.name_en : p.name, 'p.vat': p.vat_no, 'p.cr': p.cr_no, 'p.phone': p.phone,
    date: d0, hijri: typeof hijriOf === 'function' ? hijriOf(d0, en) : '', no };
}
const FBLANK = '<span class="fblank">............</span>';
function formFillText(s, V, vals, skip, en) {
  return esc(s).replace(/\{f:([^}]{1,40})\}/g, (m, k) => { if (skip && k === skip) return en ? '(listed in the table)' : '(المبيّنة في الجدول)';
      const v = vals[k] != null ? vals[k] : vals[k.trim()]; return v ? `<b>${esc(v).replace(/\n/g, '<br>')}</b>` : FBLANK; })
    .replace(/\{([a-z]+(?:\.[a-z]+)?)\}/g, (m, k) => k in V ? (V[k] ? `<b>${esc(V[k])}</b>` : FBLANK) : m);
}
const FORM_CSS = `@page{size:A4 portrait;margin:14mm}
    .fsheet{font-family:"IBM Plex Sans Arabic",Tahoma,Arial,sans-serif;color:#111;font-size:12pt;line-height:1.9}
    .fsheet .fh{display:flex;justify-content:space-between;gap:8mm;border-bottom:1.2pt solid #1f3b57;padding-bottom:4mm;margin-bottom:8mm}
    .fsheet .fhb{display:flex;align-items:center;gap:4mm}.fsheet .fhb img{max-height:18mm;max-width:50mm;object-fit:contain}
    .fsheet .fco{font-size:15pt;font-weight:700;color:#1f3b57}.fsheet .fid,.fsheet .fmeta{font-size:9pt;color:#444}.fsheet .fmeta{text-align:end;white-space:nowrap}
    .fsheet .ft{text-align:center;font-size:17pt;margin:0 0 8mm;color:#1f3b57}.fsheet .fb p{margin:0 0 4mm;text-align:justify}
    .fsheet .fblank{color:#888}.fsheet .fsl{font-weight:700;margin-bottom:6mm}.fsheet .fsn{font-size:10pt;color:#333;margin-top:3mm}`;
// the A4 sheet: letterhead, title + number + dates, the filled text, signature lines
function formPrint(t, { en, no, who, vals, deps }) {
  if (t.lib && FORM_GRID[t.key]) return formPrintGrid(t, { no, who, vals, deps });
  const c = S.company || {}, V = formVals(t, { en, no, who, deps }), d0 = V.date;
  const body = (en ? t.body_en || t.body_ar : t.body_ar).split(/\n\s*\n/).map(pp => `<p>${formFillText(pp, V, vals).replace(/\n/g, '<br>')}</p>`).join('');
  const title = en ? (t.title_en || t.title_ar) : t.title_ar, ids = [c.cr_no && (en ? 'CR ' : 'السجل التجاري ') + c.cr_no, c.vat_no && (en ? 'VAT ' : 'الرقم الضريبي ') + c.vat_no].filter(Boolean).join(' · ');
  const w = document.createElement('div'); w.className = 'fsheet'; w.setAttribute('data-nt', ''); w.dir = en ? 'ltr' : 'rtl'; w.lang = en ? 'en' : 'ar';
  w.innerHTML = `<div class="fh"><div class="fhb">${c.logo ? `<img src="${esc(c.logo)}" alt="">` : ''}<div><div class="fco">${esc(V['c.name'] || '')}</div>${ids ? `<div class="fid">${esc(ids)}</div>` : ''}</div></div>
      <div class="fmeta"><div>${en ? 'No.' : 'الرقم'}: <b class="num">${esc(no)}</b></div><div>${en ? 'Date' : 'التاريخ'}: <span class="num">${esc(d0)}</span></div>${V.hijri ? `<div>${esc(V.hijri)}</div>` : ''}</div></div>
    <h1 class="ft">${esc(title)}</h1><div class="fb">${body}</div>
    ${(t.sigs || []).length ? `<div class="fsig">${t.sigs.map(s => `<div><div class="fsl">${esc(en ? s[1] || s[0] : s[0])}</div><div class="fsn">${en ? 'Name' : 'الاسم'}: ..................</div><div class="fsn">${en ? 'Signature' : 'التوقيع'}: ..............</div></div>`).join('')}</div>` : ''}`;
  printWith(w, FORM_CSS + `.fsheet .fsig{display:grid;grid-template-columns:repeat(${Math.min((t.sigs || []).length, 3) || 1},1fr);gap:8mm;margin-top:16mm}`);
  toast(tr('النموذج') + ' ' + no);
}
// the same form as a bilingual table (Arabic + English on one sheet): details grid, item table, approve / not-approve rows,
// notes, then one column per signer — for forms that are filled in and passed between departments (FORM_GRID)
function formPrintGrid(t, { no, who, vals, deps }) {
  const g = FORM_GRID[t.key], c = S.company || {}, A = formVals(t, { en: false, no, who, deps }), E = formVals(t, { en: true, no, who, deps });
  const L = (ar, en) => `<span class="gla">${esc(ar)}</span><span class="gle" dir="ltr">${esc(en)}</span>`;
  const both = k => { const a = A[k] || '', b = E[k] || ''; return a && b && a !== b ? `${esc(a)}<br><span class="gle" dir="ltr">${esc(b)}</span>` : esc(a || b); };
  const cells = [];
  if (t.subject === 'employee') [['e.name', 'الاسم', 'Name'], ['e.no', 'الرقم الوظيفي', 'Employee no.'], ['e.job', 'الوظيفة', 'Position'], ['e.dept', 'القسم', 'Division'],
    ['e.nat', 'الجنسية', 'Nationality'], ['e.id', 'رقم الهوية / الإقامة', 'ID / Iqama no.'], ['e.hire', 'تاريخ التعيين', 'Hire date'], ['e.mgr', 'المدير المباشر', 'Direct manager']]
    .slice(0, t.dept === 'hr' ? 8 : 4).forEach(([k, a, b]) => cells.push([L(a, b), both(k)]));
  if (['customer', 'supplier', 'party'].includes(t.subject)) [['p.name', t.subject === 'supplier' ? 'المورد' : t.subject === 'customer' ? 'العميل' : 'الجهة', t.subject === 'supplier' ? 'Supplier' : t.subject === 'customer' ? 'Customer' : 'Party'],
    ['p.vat', 'الرقم الضريبي', 'VAT no.'], ['p.cr', 'السجل التجاري', 'CR no.'], ['p.phone', 'الجوال', 'Phone']].forEach(([k, a, b]) => cells.push([L(a, b), both(k)]));
  const lf = g.l ? g.l[0] : null, boxes = [];
  t.fields.forEach(([k, la, le, ty]) => { if (k === lf || (g.ck && k === 'held')) return; const v = vals[k] || '';
    if (ty === 'textarea') boxes.push([L(la, le), v]); else cells.push([L(la, le), esc(v)]); });
  if (cells.length % 2) cells.push(['', '']);
  const rows = []; for (let i = 0; i < cells.length; i += 2) rows.push(`<tr>${[cells[i], cells[i + 1]].map(([l, v]) => `<th>${l}</th><td>${v}</td>`).join('')}</tr>`);
  const H = (ar, en) => `<div class="gh">${L(ar, en)}</div>`;
  let list = '';
  if (g.l) { const cols = g.l[1], lines = String(vals[lf] || '').split('\n').map(x => x.trim()).filter(Boolean).map(x => x.split(/\s+[—×|-]\s+|\t/));
    while (lines.length < 4) lines.push([]);
    const fl = t.fields.find(f => f[0] === lf);
    list = '<div class="gsec">' + H(fl[1].replace(/\s*\(.*\)$/, ''), fl[2].replace(/\s*\(.*\)$/, '')) + `<table class="gt gl"><tr><th class="gn">#<br><span class="gle">م</span></th>${cols.map(([a, b]) => `<th>${L(a, b)}</th>`).join('')}</tr>
      ${lines.map((r, i) => `<tr><td class="gn">${r.length ? i + 1 : ''}</td>${cols.map((x, j) => `<td>${esc(j === cols.length - 1 && r.length > cols.length ? r.slice(j).join(' — ') : r[j] || '')}</td>`).join('')}</tr>`).join('')}</table></div>`; }
  const ck = g.ck ? '<div class="gsec">' + H('بيانات إخلاء الطرف', 'Clearance data') + `<table class="gt gc"><tr><th>${L('الإدارة', 'Department')}</th><th>${L('القرار', 'Decision')}</th><th>${L('المتعلقات', 'Pending items')}</th><th>${L('التوقيع', 'Signature')}</th></tr>
      ${g.ck.map(([a, b], i) => `<tr><th>${L(a, b)}</th><td class="gd">☐ ${L('تم إخلاء الطرف', 'Approved')}<br>☐ ${L('لم يتم إخلاء الطرف', 'Not approved')}</td><td class="small">${i === g.ck.length - 1 && vals.held ? esc(vals.held).replace(/\n/g, '<br>') : ''}</td><td></td></tr>`).join('')}</table></div>` : '';
  const decl = g.d || g.ck ? `<div class="gdecl"><p>${formFillText(t.body_ar.split(/\n\s*\n/).filter((p, i) => g.note == null || i === g.note).join(' '), A, vals, lf, false).replace(/\n/g, ' ')}</p>
      <p dir="ltr">${formFillText(t.body_en.split(/\n\s*\n/).filter((p, i) => g.note == null || i === g.note).join(' '), E, vals, lf, true).replace(/\n/g, ' ')}</p></div>` : '';
  const sg = t.sigs || [];
  const w = document.createElement('div'); w.className = 'fsheet gsheet'; w.setAttribute('data-nt', ''); w.dir = 'rtl'; w.lang = 'ar';
  w.innerHTML = `<div class="fh"><div class="fhb">${c.logo ? `<img src="${esc(c.logo)}" alt="">` : ''}<div><div class="fco">${esc(A['c.name'] || '')}</div>${E['c.name'] && E['c.name'] !== A['c.name'] ? `<div class="fid" dir="ltr">${esc(E['c.name'])}</div>` : ''}
        ${c.cr_no || c.vat_no ? `<div class="fid">${[c.cr_no && 'السجل التجاري CR ' + c.cr_no, c.vat_no && 'الرقم الضريبي VAT ' + c.vat_no].filter(Boolean).map(esc).join(' · ')}</div>` : ''}</div></div>
      <div class="fmeta"><div>الرقم No.: <b class="num">${esc(no)}</b></div><div>التاريخ Date: <span class="num">${esc(A.date)}</span></div>${A.hijri ? `<div>${esc(A.hijri)}</div>` : ''}</div></div>
    <h1 class="ft">${esc(t.title_ar)}<span class="gle" dir="ltr">${esc(t.title_en || '')}</span></h1>
    ${rows.length ? `<div class="gsec">${H('البيانات', 'Details')}<table class="gt gd2">${rows.join('')}</table></div>` : ''}
    ${boxes.map(([l, v]) => `<table class="gt"><tr><th class="gbh">${l}</th></tr><tr><td class="${v ? 'gboxf' : 'gbox'}">${v ? esc(v).replace(/\n/g, '<br>') : ''}</td></tr></table>`).join('')}
    ${list}${ck}${decl}
    <table class="gt"><tr><th class="gbh">${L('ملاحظات', 'Notes')}</th></tr><tr><td class="gbox"></td></tr></table>
    ${sg.length ? '<div class="gsec">' + H('الاعتماد', 'Approvals') + `<table class="gt gs"><tr>${sg.map(s => `<th>${L(s[0], s[1] || s[0])}</th>`).join('')}</tr>
      ${[['الاسم', 'Name'], ['التوقيع والتاريخ', 'Signature & date']].map(([a, b]) => `<tr>${sg.map(() => `<td><span class="gsl">${L(a, b)}</span></td>`).join('')}</tr>`).join('')}</table></div>` : ''}`;
  printWith(w, FORM_CSS + `@page{size:A4 portrait;margin:10mm}.gsheet{-webkit-print-color-adjust:exact;print-color-adjust:exact}.gsheet .gsec{break-inside:avoid;page-break-inside:avoid}.gsheet{font-size:9.5pt;line-height:1.4}.gsheet .fh{margin-bottom:3mm;padding-bottom:2mm}.gsheet .fhb img{max-height:14mm}.gsheet .ft{margin-bottom:3mm;font-size:15pt}
    .gsheet .ft .gle{display:block;font-size:11pt;font-weight:600}
    .gsheet .gle{display:block;font-size:8pt;color:#444;font-weight:400}.gsheet .gla{display:block}
    .gsheet .gh{background:#1f3b57;color:#fff;padding:1mm 3mm;margin-top:3mm;display:flex;justify-content:space-between;align-items:baseline;font-weight:700}
    .gsheet .gh .gle{color:#dde6ef;font-size:9pt;font-weight:600}
    .gsheet .gt{width:100%;border-collapse:collapse;margin-top:0;page-break-inside:avoid}.gsheet .gt+.gt{margin-top:2mm}
    .gsheet .gt th,.gsheet .gt td{border:.6pt solid #8a99a8;padding:1mm 2mm;vertical-align:top;text-align:start}
    .gsheet .gt th{background:#eef2f6;font-weight:700;width:auto}.gsheet .gd2 th{width:20%}.gsheet .gd2 td{width:30%}
    .gsheet .gl td{height:6mm}.gsheet .gn{width:8mm;text-align:center!important}
    .gsheet .gc th:first-child{width:24%}.gsheet .gc td{height:auto}.gsheet .gc .gle{font-size:7.5pt}.gsheet .gc .gd{width:28%;white-space:nowrap}.gsheet .gc .gd .gla,.gsheet .gc .gd .gle{display:inline}
    .gsheet .gbh{background:#eef2f6}.gsheet .gbox{height:10mm}
    .gsheet .gdecl{margin-top:3mm;font-size:9pt;border:.6pt solid #8a99a8;padding:2mm 3mm}.gsheet .gdecl p{margin:0 0 1.5mm;text-align:justify}.gsheet .gdecl p[dir=ltr]{font-size:9pt;color:#333}
    .gsheet .gs{margin-top:0}.gsheet .gs th{text-align:center}.gsheet .gs td{height:7mm;font-size:8pt;color:#555}.gsheet .gsl .gla,.gsheet .gsl .gle{display:inline;margin-inline-end:2mm}`);
  toast(tr('النموذج') + ' ' + no);
}

// the company's own template: text with placeholders; {f:…} tokens become fields when filling
function formEdit(r) {
  const chips = FORM_PH.map(([ph, l]) => `<button type="button" class="btn sm" data-ph="${esc(ph)}" title="${esc(tr(l))}">${esc(tr(l))}</button>`).join(' ');
  const d = modal(r.id ? tr('تعديل نموذج') : tr('نموذج جديد'), `<div class="fg">
      ${field('القسم', `<select name="dept">${Object.keys(FORM_DEPTS).filter(x => modOn(x) && formCanDept(x)).map(x => opt(x, fT(...FORM_DEPTS[x]), r.dept)).join('')}</select>`)}
      ${field('النموذج لـ', `<select name="subject">${[['employee', 'موظف'], ['customer', 'عميل'], ['supplier', 'مورد'], ['none', 'عام']].map(([k, l]) => opt(k, tr(l), r.subject || 'employee')).join('')}</select>`)}
      ${field('عنوان النموذج', inp('title_ar', r.title_ar, 'maxlength="120" required'))}${field('العنوان بالإنجليزي (اختياري)', inp('title_en', r.title_en, 'maxlength="120" dir="ltr"'))}
      <div class="wide"><label>${esc(tr('اضغط لإضافة خانة تتعبّى تلقائياً'))}</label><div class="row" style="gap:6px;flex-wrap:wrap">${chips}</div></div>
      ${field('نص النموذج بالعربي', `<textarea name="body_ar" rows="9" maxlength="8000" required data-nt>${esc(r.body_ar || '')}</textarea>`, 'wide')}
      ${field('النص بالإنجليزي (اختياري)', `<textarea name="body_en" rows="5" maxlength="8000" dir="ltr" data-nt>${esc(r.body_en || '')}</textarea>`, 'wide')}
      ${field('التوقيعات (كل جهة في سطر)', `<textarea name="sigs" rows="3" placeholder="${esc(tr('الموظف') + '\n' + tr('الموارد البشرية'))}">${esc((r.sigs || []).join('\n'))}</textarea>`, 'wide')}</div>
    <p class="muted small">${esc(tr('أي كلمة تكتبها بين {f: و } تصير خانة تُعبّأ وقت الطباعة، مثل {f:المبلغ} أو {f:تاريخ الحادثة}.'))}</p>
    ${r.id ? `<button type="button" class="btn sm" id="fdel" style="margin-top:8px">${esc(tr('حذف النموذج'))}</button>` : ''}`, {
    wide: true, onOk: async f => {
      const row = { company_id: S.cid, dept: f.dept, subject: f.subject, title_ar: f.title_ar, title_en: blank(f.title_en), body_ar: f.body_ar, body_en: blank(f.body_en),
        sigs: (f.sigs || '').split('\n').map(s => s.trim()).filter(Boolean).slice(0, 6) };
      if ((row.title_ar || '').length < 2 || (row.body_ar || '').length < 2) throw new Error('اكتب العنوان والنص');
      if (r.id) await db.upd('form_templates', { id: 'eq.' + r.id }, row); else await db.ins('form_templates', row);
      toast(tr('تم الحفظ')); route();
    } });
  let last = d.querySelector('[name=body_ar]');
  ['body_ar', 'body_en'].forEach(n => d.querySelector(`[name=${n}]`).addEventListener('focus', ev => { last = ev.target; }));
  $$('[data-ph]', d).forEach(b => b.onclick = () => { const ta = last, s = ta.selectionStart || ta.value.length;
    ta.value = ta.value.slice(0, s) + b.dataset.ph + ta.value.slice(ta.selectionEnd || s); ta.focus(); ta.selectionStart = ta.selectionEnd = s + b.dataset.ph.length; });
  if (r.id) $('#fdel', d).onclick = async () => { await db.del('form_templates', { id: 'eq.' + r.id }); d.close(); toast(tr('تم الحذف')); route(); };
}
