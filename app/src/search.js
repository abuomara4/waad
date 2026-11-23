'use strict';
/* ===== البحث الشامل (Ctrl/⌘+K or the top-bar button): pages, employees, customers/suppliers, invoices, items, opportunities ===== */
function searchOpen() {
  const d = modal(tr('بحث'), `<input id="gsq" type="search" autocomplete="off" aria-label="${esc(tr('بحث'))}" placeholder="${esc(tr('ابحث: موظف، عميل، رقم فاتورة، صنف، صفحة…'))}">
    <div id="gsr" class="gsr" role="listbox"></div><p class="small muted" style="margin:8px 0 0">${esc(tr('اختصار: Ctrl+K أو ⌘K · الأسهم للتنقل · Enter للفتح'))}</p>`, { wide: true });
  const q = $('#gsq', d), out = $('#gsr', d); let t = 0, sel = 0, hits = [];
  const like = v => '*' + v.replace(/[*,()]/g, ' ') + '*';
  const run = async () => {
    const v = q.value.trim(); if (v.length < 2) { out.innerHTML = ''; hits = []; return; }
    const L = like(v), g = (p, f) => p.then(f).catch(() => []);
    const pages = navItems().filter(i => i.h && tr(i.t).toLowerCase().includes(v.toLowerCase())).slice(0, 5).map(i => ({ g: 'صفحات', t: tr(i.t), h: i.h }));
    const parts = await Promise.all([
      isHR() ? g(db.get('employees', { company_id: 'eq.' + S.cid, or: `(full_name.ilike.${L},full_name_en.ilike.${L},emp_no.ilike.${L},national_id.ilike.${L})`, select: 'id,full_name,emp_no', limit: 6 }), r => r.map(e => ({ g: 'الموظفون', t: e.full_name, s: e.emp_no, h: '#/docs/' + e.id }))) : [],
      can('sales') || can('purch') ? g(db.get('parties', { company_id: 'eq.' + S.cid, or: `(name.ilike.${L},name_en.ilike.${L},vat_no.ilike.${L},phone.ilike.${L})`, select: 'id,name,kind', limit: 6 }), r => r.map(p => ({ g: 'العملاء والموردون', t: p.name, s: tr(p.kind === 'customer' ? 'عميل' : 'مورد'), h: '#/statement/' + p.id }))) : [],
      can('sales') ? g(db.get('sales_invoices', { company_id: 'eq.' + S.cid, no: 'ilike.' + L, select: 'id,no,date,total', order: 'date.desc', limit: 5 }), r => r.map(x => ({ g: 'فواتير المبيعات', t: x.no, s: x.date + ' · ' + money(x.total), h: '#/sales/' + x.id }))) : [],
      can('purch') ? g(db.get('purchase_bills', { company_id: 'eq.' + S.cid, or: `(no.ilike.${L},ref.ilike.${L})`, select: 'id,no,date,total', order: 'date.desc', limit: 5 }), r => r.map(x => ({ g: 'فواتير المشتريات', t: x.no, s: x.date + ' · ' + money(x.total), h: '#/purchases/' + x.id }))) : [],
      isFin() ? g(db.get('items', { company_id: 'eq.' + S.cid, or: `(name.ilike.${L},code.ilike.${L},barcode.ilike.${L})`, select: 'id,code,name', limit: 5 }), r => r.map(x => ({ g: 'الأصناف', t: x.name, s: x.code, h: '#/items' }))) : [],
      can('sales') || can('mkt') ? g(db.get('crm_leads', { company_id: 'eq.' + S.cid, or: `(title.ilike.${L},prospect.ilike.${L},no.ilike.${L})`, select: 'id,no,title', limit: 5 }), r => r.map(x => ({ g: 'الفرص', t: x.title, s: x.no, h: '#/crm/' + x.id }))) : []]);
    hits = pages.concat(...parts); sel = 0; draw();
  };
  const draw = () => { let last = '';
    out.innerHTML = hits.length ? hits.map((h, i) => (h.g !== last ? `<div class="gsg">${esc(tr((last = h.g)))}</div>` : '') + `<a class="gsi${i === sel ? ' on' : ''}" href="${esc(h.h)}" data-i="${i}" role="option"><b>${esc(h.t)}</b>${h.s ? ` <span class="small muted num">${esc(h.s)}</span>` : ''}</a>`).join('')
      : `<div class="muted small" style="padding:10px">${esc(tr('لا توجد نتائج'))}</div>`;
    $$('.gsi', out).forEach(a => a.onclick = () => d.close()); };
  q.oninput = () => { clearTimeout(t); t = setTimeout(() => { t = 0; run(); }, 250); };
  q.onkeydown = async ev => { if (ev.key === 'Enter' && (t || !hits.length)) { ev.preventDefault(); clearTimeout(t); t = 0; await run(); if (hits.length) { location.hash = hits[0].h; d.close(); } return; }
    if (!hits.length) return;
    if (ev.key === 'ArrowDown' || ev.key === 'ArrowUp') { ev.preventDefault(); sel = (sel + (ev.key === 'ArrowDown' ? 1 : hits.length - 1)) % hits.length; draw(); }
    if (ev.key === 'Enter') { ev.preventDefault(); location.hash = hits[sel].h; d.close(); } };
  setTimeout(() => q.focus(), 30);
}
document.addEventListener('keydown', ev => { if ((ev.ctrlKey || ev.metaKey) && ev.key.toLowerCase() === 'k' && S.session && S.cid && !ADMIN) { ev.preventDefault(); searchOpen(); } });

/* ===== «إرسال للعميل»: a sales invoice or a quote by WhatsApp or e-mail, with its PDF saved from the print window ===== */
function sendDocDialog({ title, no, party, total, rem, due, printBtn }) {
  const co = (S.company || {}).name || '';
  const msg = `${tr('السادة')} ${party.name}${tr('،')}\n${tr('تحية طيبة،')}\n${title} ${tr('رقم')} ${no} ${tr('بمبلغ')} ${money(total)} ${tr('ريال')}${rem != null && rem > 0.001 && rem !== total ? ` (${tr('المتبقي')} ${money(rem)} ${tr('ريال')})` : ''}${due ? `${tr('، تاريخ الاستحقاق')} ${due}` : ''}.\n${tr('مرفق نسخة PDF.')}\n${co}`;
  const mail = party.email ? `mailto:${encodeURIComponent(party.email)}?subject=${encodeURIComponent(title + ' ' + no + ' — ' + co)}&body=${encodeURIComponent(msg)}` : '';
  const d = modal(tr('إرسال للعميل') + ' — ' + no, `<ol class="small" style="padding-inline-start:20px;margin-top:0"><li>${esc(tr('احفظ المستند PDF من زر «حفظ PDF» (اختر «حفظ بصيغة PDF» في نافذة الطباعة).'))}</li><li>${esc(tr('افتح الواتساب أو البريد برسالة جاهزة، وأرفق ملف PDF.'))}</li></ol>
    <textarea id="sdm" rows="6" data-nt>${esc(msg)}</textarea>
    <div class="row" style="gap:8px;margin-top:10px;flex-wrap:wrap"><button type="button" class="btn" id="sdp">${esc(tr('حفظ PDF'))}</button>
      <a class="btn wa" id="sdw" target="_blank" rel="noopener" href="#">${esc(tr('واتساب'))}${party.phone ? '' : ' (' + esc(tr('اختر المحادثة')) + ')'}</a>
      ${mail ? `<a class="btn" id="sdmail" href="${esc(mail)}">${esc(tr('البريد الإلكتروني'))}</a>` : `<span class="small muted">${esc(tr('لا يوجد بريد إلكتروني مسجّل للعميل'))}</span>`}</div>`, {});
  const upd = () => { $('#sdw', d).href = waUrl(party.phone, $('#sdm', d).value); if ($('#sdmail', d)) $('#sdmail', d).href = mail.replace(/body=[^&]*$/, 'body=' + encodeURIComponent($('#sdm', d).value)); };
  $('#sdm', d).oninput = upd; upd();
  $('#sdp', d).onclick = () => { d.close(); setTimeout(() => printBtn && printBtn.click(), 80); };
}
