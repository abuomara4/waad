'use strict';
/* «الدعم الفني»: the company's managers write to the Waad team and read the answers here
   (the team answers in the admin site → «طلبات الدعم»; the customer also gets the answer by e-mail). */
const SUP_KIND = { question: 'سؤال', problem: 'مشكلة', suggestion: 'اقتراح' };
const SUP_ST = { open: ['بانتظار الرد', 'wait'], answered: ['تم الرد', 'ok'], closed: ['مغلق', ''] };
const supportOk = () => has('owner', 'admin', 'hr', 'finance', 'accountant');
VIEWS['#/support'] = async page => {
  if (!supportOk()) { page.innerHTML = `<div class="note">${esc(tr('الدعم الفني لمدير المنشأة. راجع مالك المنشأة.'))}</div>`; return; }
  const rows = await db.rpc('support_mine', { p_company: S.cid });
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الدعم الفني'))}</h1><div class="muted">${esc(tr('اكتب لنا سؤالك أو المشكلة اللي واجهتك، ونرد عليك هنا وعلى إيميلك.'))}</div></div></div>
    <form class="card" id="supf" style="margin-bottom:14px"><div class="fg">
      ${field('النوع', `<select name="kind">${Object.entries(SUP_KIND).map(([k, t]) => opt(k, tr(t), 'question')).join('')}</select>`)}
      ${field('العنوان', '<input name="subject" maxlength="120" required>')}
      ${field('التفاصيل', `<textarea name="body" rows="4" maxlength="3000" required placeholder="${esc(tr('اكتب وش صار، ووين، وإذا فيه رسالة خطأ اكتبها.'))}"></textarea>`, 'wide')}</div>
      <div id="superr"></div><button class="btn pri" id="supb" style="margin-top:10px">${esc(tr('إرسال'))}</button></form>
    <div class="card"><h2>${esc(tr('طلباتك'))}</h2>
      ${rows.length ? rows.map(r => `<details class="supi"${r.reply && r.status === 'answered' ? ' open' : ''}><summary><span class="badge ${SUP_ST[r.status][1]}">${esc(tr(SUP_ST[r.status][0]))}</span>
          <b data-nt>${esc(r.subject)}</b> <span class="small muted">${esc(tr(SUP_KIND[r.kind]))} · <span class="num">${esc(String(r.created_at).slice(0, 10))}</span></span></summary>
        <div class="supb" data-nt>${esc(r.body)}</div>
        ${r.reply ? `<div class="supr"><div class="small muted">${esc(tr('رد فريق وعد'))} · <span class="num">${esc(String(r.replied_at || '').slice(0, 10))}</span></div><div data-nt>${esc(r.reply)}</div></div>` : ''}</details>`).join('')
        : `<div class="empty">${esc(tr('ما أرسلت طلبات للحين.'))}</div>`}</div>`;
  $('#supf', page).onsubmit = async e => { e.preventDefault(); const f = formData(e.target);
    if ((f.subject || '').length < 3 || (f.body || '').length < 3) return showErr($('#superr', page), tr('اكتب العنوان والتفاصيل'));
    try { await busy($('#supb', page), () => db.rpc('support_open', { p_company: S.cid, p_kind: f.kind, p_subject: f.subject, p_body: f.body, p_route: S.prevRoute || null }));
      toast(tr('وصلنا طلبك، ونرد عليك قريباً')); route(); } catch (er) { showErr($('#superr', page), er); } };
};
