'use strict';
/* ===== التوقيع الإلكتروني: HR asks, the employee signs with a finger in «توقيعاتي» (0096) ===== */
const SIGN_KIND = { contract: 'عقد العمل', custody: 'استلام عهدة', penalty: 'إشعار جزاء', clearance: 'مخالصة نهائية', letter: 'خطاب', policy: 'سياسة', other: 'مستند' };

// a drawing pad: finger or mouse; returns { png(), empty(), clear() }
function signPad(box) {
  box.innerHTML = `<canvas class="sigpad" width="600" height="220" aria-label="${esc(tr('مساحة التوقيع'))}"></canvas><div class="row" style="justify-content:space-between;margin-top:6px"><span class="small muted">${esc(tr('وقّع بإصبعك أو بالفأرة داخل المربع'))}</span><button type="button" class="btn sm" data-sigclr>${esc(tr('مسح'))}</button></div>`;
  const c = $('canvas', box), x = c.getContext('2d'); let draw = false, ink = 0, last = null;
  x.lineWidth = 3; x.lineCap = 'round'; x.lineJoin = 'round'; x.strokeStyle = '#142039';
  const pt = ev => { const r = c.getBoundingClientRect(); return [(ev.clientX - r.left) * c.width / r.width, (ev.clientY - r.top) * c.height / r.height]; };
  c.addEventListener('pointerdown', ev => { draw = true; last = pt(ev); c.setPointerCapture(ev.pointerId); ev.preventDefault(); });
  c.addEventListener('pointermove', ev => { if (!draw) return; const p = pt(ev); x.beginPath(); x.moveTo(last[0], last[1]); x.lineTo(p[0], p[1]); x.stroke(); ink += Math.hypot(p[0] - last[0], p[1] - last[1]); last = p; ev.preventDefault(); });
  ['pointerup', 'pointercancel', 'pointerleave'].forEach(t => c.addEventListener(t, () => { draw = false; }));
  $('[data-sigclr]', box).onclick = () => { x.clearRect(0, 0, c.width, c.height); ink = 0; };
  return { png: () => c.toDataURL('image/png'), empty: () => ink < 40, clear: () => { x.clearRect(0, 0, c.width, c.height); ink = 0; } };
}

// HR: ask an employee to sign
async function signAsk(emp, kind, ref, title, body) {
  const d = modal(tr('طلب توقيع إلكتروني') + ' — ' + emp.full_name, `<p>${esc(tr('يصل الطلب للموظف في «توقيعاتي»، ويوقّع من جواله. يُحفظ التوقيع مع النص والوقت ولا يمكن تعديله بعد ذلك.'))}</p>
    <div class="fg">${field('عنوان المستند', inp('t', title, 'required maxlength="200"'), 'wide')}${field('النص الذي سيوقّع عليه', `<textarea name="b" rows="5" maxlength="4000">${esc(body || '')}</textarea>`, 'wide')}</div>`, {
    ok: 'إرسال طلب التوقيع', wide: true, onOk: async f => { if ((f.t || '').trim().length < 2) throw new Error('اكتب عنوان المستند');
      await db.rpc('sign_request_create', { p_company: S.cid, p_emp: emp.id, p_kind: kind, p_ref: ref || null, p_title: f.t, p_body: blank(f.b) }); toast(tr('أُرسل طلب التوقيع للموظف')); route(); } });
  return d;
}
// the state of a signature for one record: «بانتظار التوقيع» / «وُقّع» (click to see it) / a button to ask
function signState(reqs, kind, ref, emp, title, body) {
  const r = reqs.filter(x => x.kind === kind && x.ref_id === ref && x.status !== 'cancelled').sort((a, b) => b.created_at.localeCompare(a.created_at))[0];
  if (r && r.status === 'signed') return `<button type="button" class="btn sm" data-sigview="${r.id}">✓ ${esc(tr('وُقّع'))} <span class="num small">${esc(waitAt(r.signed_at).slice(0, 10))}</span></button>`;
  if (r) return `<span class="badge wait">${esc(tr('بانتظار التوقيع'))}</span>`;
  return isHR() ? `<button type="button" class="btn sm" data-sigask="${esc(kind)}|${esc(ref || '')}" data-sigt="${esc(title)}" data-sigb="${esc(body || '')}">${esc(tr('طلب توقيع'))}</button>` : '';
}
function bindSign(root, reqs, emp) {
  $$('[data-sigask]', root).forEach(b => b.onclick = ev => { ev.stopPropagation(); const [k, ref] = b.dataset.sigask.split('|'); signAsk(emp, k, ref || null, b.dataset.sigt, b.dataset.sigb); });
  $$('[data-sigview]', root).forEach(b => b.onclick = ev => { ev.stopPropagation(); signShow(reqs.find(r => r.id === b.dataset.sigview), emp); });
}
function signShow(r, emp) {
  if (!r) return;
  modal(tr(SIGN_KIND[r.kind] || 'مستند') + ' — ' + tr('موقّع'), `<p><b>${esc(r.title)}</b></p>${r.body ? `<div class="note" style="white-space:pre-wrap">${esc(r.body)}</div>` : ''}
    <p class="small">${esc(tr('الموقّع'))}: <b>${esc(emp ? emp.full_name : '')}</b> · ${esc(tr('وقت التوقيع'))}: <span class="num">${esc(waitAt(r.signed_at))}</span></p>
    <div class="sigimg"><img src="${esc(r.signature)}" alt="${esc(tr('التوقيع'))}"></div>
    <p class="row" style="margin-top:10px"><button type="button" class="btn" id="sigpr">${esc(tr('طباعة'))}</button></p>`, {});
  $('#sigpr').onclick = () => { const n = document.createElement('div'); n.innerHTML = `<h3>${esc(r.title)}</h3>${r.body ? `<p style="white-space:pre-wrap">${esc(r.body)}</p>` : ''}<p>${esc(tr('الموقّع'))}: <b>${esc(emp ? emp.full_name : '')}</b> — ${esc(tr('وقت التوقيع'))}: ${esc(waitAt(r.signed_at))}</p><img src="${esc(r.signature)}" style="max-width:70mm;border-bottom:1px solid #999">`; printBlock(n, tr('مستند موقّع إلكترونيا')); };
}

// the employee: what waits for my signature, and what I signed
VIEWS['#/sign'] = async page => {
  if (!S.emp) { page.innerHTML = `<div class="note">${esc(tr('حسابك غير مربوط بسجل موظف.'))}</div>`; return; }
  const rows = await db.get('signature_requests', { employee_id: 'eq.' + S.emp, status: 'neq.cancelled', order: 'created_at.desc' });
  const pend = rows.filter(r => r.status === 'pending');
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('توقيعاتي'))}</h1><div class="muted">${esc(tr('المستندات التي طلبت منك المنشأة توقيعها إلكترونيا.'))}</div></div></div>
    ${tbl([{ t: 'المستند', h: r => `<b>${esc(r.title)}</b><div class="small muted">${esc(tr(SIGN_KIND[r.kind] || ''))}</div>` },
      { t: 'الحالة', h: r => r.status === 'signed' ? `<span class="badge ok">${esc(tr('وُقّع'))}</span> <span class="num small muted">${esc(waitAt(r.signed_at))}</span>` : `<span class="badge wait">${esc(tr('بانتظار توقيعك'))}</span>` },
      { t: 'تاريخ الطلب', h: r => `<span class="num">${esc(waitAt(r.created_at).slice(0, 10))}</span>` }], rows, { empty: 'لا توجد مستندات للتوقيع', onRow: true })}`;
  bindRows(page, rows, r => r.status === 'signed' ? signShow(r, S.myEmp) : signNow(r));
  if (pend.length === 1 && /[?&]open=1/.test(location.hash)) signNow(pend[0]);
};
function signNow(r) {
  const d = modal(tr('توقيع') + ' — ' + r.title, `${r.body ? `<div class="note" style="white-space:pre-wrap;max-height:260px;overflow:auto">${esc(r.body)}</div>` : ''}
    <p class="small muted">${esc(tr('بتوقيعك تقرّ بالاطلاع على المستند أعلاه والموافقة عليه. يُحفظ التوقيع مع الوقت ولا يمكن تعديله.'))}</p><div id="sigbox"></div>`, {
    ok: 'توقيع وإرسال', wide: true, onOk: async () => { if (pad.empty()) throw new Error('ارسم توقيعك أولا'); await db.rpc('sign_submit', { p_id: r.id, p_signature: pad.png() }); toast(tr('تم التوقيع')); refreshCounts(); route(); } });
  const pad = signPad($('#sigbox', d));
}
