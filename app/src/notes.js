'use strict';
/* ===== الملاحظات والإشارات على السجلات (0098): a note under an invoice, a bill, a customer, an employee, an opportunity, a project ===== */
const NOTE_LINK = { employee: '#/docs/', sales: '#/sales/', purchase: '#/purchases/', party: '#/statement/', project: '#/projects/', crm: '#/crm/' };
let MEMBER_NAMES = null;
const memberNames = async () => MEMBER_NAMES || (MEMBER_NAMES = await db.rpc('member_names', { p_company: S.cid }).catch(() => []));
// appends a «ملاحظات» card to `root` for one record
async function notesBox(root, entity, refId) {
  if (!root || !refId) return;
  const card = document.createElement('div'); card.className = 'card notes'; root.appendChild(card);
  const draw = async () => {
    const [rows, names] = await Promise.all([db.get('record_notes', { company_id: 'eq.' + S.cid, entity: 'eq.' + entity, ref_id: 'eq.' + refId, order: 'created_at.desc' }).catch(() => []), memberNames()]);
    const nm = {}; names.forEach(n => nm[n.user_id] = n.name); const me = S.session.user.id;
    card.innerHTML = `<h2>${esc(tr('ملاحظات'))} <span class="num muted small">${rows.length || ''}</span></h2>
      <div class="nlist">${rows.map(r => `<div class="nrow"><div class="small muted"><b>${esc(nm[r.created_by] || tr('مستخدم'))}</b> · <span class="num">${esc(waitAt(r.created_at))}</span>${r.mentions.length ? ' · ' + esc(tr('إلى')) + ' ' + r.mentions.map(u => '@' + esc(nm[u] || '')).join(' ') : ''}${r.created_by === me ? ` <button type="button" class="linkbtn small" data-ndel="${r.id}">${esc(tr('حذف'))}</button>` : ''}</div><div style="white-space:pre-wrap">${esc(r.body)}</div></div>`).join('') || `<p class="muted small">${esc(tr('لا توجد ملاحظات بعد.'))}</p>`}</div>
      <div class="nadd"><textarea rows="2" maxlength="2000" placeholder="${esc(tr('اكتب ملاحظة… وأشر إلى زميل ليصله تنبيه'))}"></textarea>
        <div class="row" style="gap:6px;flex-wrap:wrap;margin-top:6px"><select class="nm" style="width:auto"><option value="">${esc(tr('@ إشارة إلى زميل'))}</option>${names.filter(n => n.user_id !== me).map(n => opt(n.user_id, n.name)).join('')}</select><span class="nchips"></span>
          <button type="button" class="btn sm pri" data-nadd>${esc(tr('إضافة الملاحظة'))}</button></div><div class="nerr"></div></div>`;
    const picked = new Set(), chips = $('.nchips', card), sel = $('.nm', card);
    const drawChips = () => { chips.innerHTML = [...picked].map(u => `<span class="badge info">@${esc(nm[u])} <button type="button" class="linkbtn" data-nx="${u}" aria-label="${esc(tr('إزالة'))}">×</button></span>`).join(' '); $$('[data-nx]', chips).forEach(b => b.onclick = () => { picked.delete(b.dataset.nx); drawChips(); }); };
    sel.onchange = () => { if (sel.value) picked.add(sel.value); sel.value = ''; drawChips(); };
    $('[data-nadd]', card).onclick = async () => { const body = $('textarea', card).value.trim(); if (!body) return showErr($('.nerr', card), tr('اكتب الملاحظة'));
      try { await db.ins('record_notes', { company_id: S.cid, entity, ref_id: refId, body, mentions: [...picked] }); draw(); } catch (er) { showErr($('.nerr', card), er); } };
    $$('[data-ndel]', card).forEach(b => b.onclick = async () => { try { await db.del('record_notes', { id: 'eq.' + b.dataset.ndel }); draw(); } catch (er) { toast(er.message); } });
  };
  draw().catch(() => {});
}
// for the bell: notes that mention me in the last 14 days
async function notesForMe() {
  const since = new Date(Date.now() - 14 * 864e5).toISOString();
  return db.get('record_notes', { company_id: 'eq.' + S.cid, mentions: 'cs.{' + S.session.user.id + '}', created_at: 'gte.' + since, order: 'created_at.desc', limit: 10 }).catch(() => []);
}
