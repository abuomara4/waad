'use strict';
/* ===== Request journey (step by step), approval settings, travel desk (tickets and exit/re-entry visas) ===== */

const waitTxt = ts => { if (!ts) return ''; const h = Math.max(0, (Date.now() - new Date(ts)) / 36e5);
  return h < 1 ? tr('أقل من ساعة') : h < 24 ? tr('منذ') + ' ' + Math.floor(h) + ' ' + tr('ساعة') : tr('منذ') + ' ' + Math.floor(h / 24) + ' ' + tr('يوم'); };
const slaLate = r => { const d = S.company && S.company.request_sla_days; return !!d && r.status === 'pending' && (Date.now() - new Date(r.step_at)) / 864e5 > d; };
const TT_ST = { approved: 'بانتظار الصرف', issued: 'صُرفت', cancelled: 'ملغاة' };
const ttSt = t => t.status === 'cancelled' ? 'ملغاة' : t.mode === 'cash' ? (t.status === 'issued' ? 'صُرف البدل' : 'بانتظار صرف البدل من المالية') : t.status === 'issued' ? 'سُلّمت التذكرة' : 'بانتظار إرفاق التذكرة من الموارد البشرية';
const ttCls = t => t.status === 'issued' ? 'ok' : t.status === 'cancelled' ? '' : 'wait';
const tfBtns = fl => (fl || []).map(f => `<button type="button" class="btn sm" data-tfile="${f.id}">${f.mime === 'application/pdf' ? 'PDF' : esc(tr('صورة'))} — ${esc(f.name)}</button>`).join(' ');
async function openTravelFile(id) {
  const w = window.open('', '_blank');
  try { const [a] = await db.get('travel_files', { id: 'eq.' + id, select: 'file_name,mime,data' }); if (!a) throw new Error(tr('المرفق غير موجود'));
    const bin = atob(a.data), u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
    const url = URL.createObjectURL(new Blob([u], { type: a.mime })); if (w) w.location = url; else location.href = url;
  } catch (er) { if (w) w.close(); toast(er.message); }
}
const bindTravelFiles = root => $$('[data-tfile]', root).forEach(b => b.onclick = () => openTravelFile(b.dataset.tfile));
const VZ_ST = { requested: 'بانتظار الإصدار', issued: 'صدرت', returned: 'عاد', not_returned: 'لم يعد', cancelled: 'ملغاة' };
const VZ_T = { single: 'خروج وعودة مفردة', multiple: 'خروج وعودة متعددة' };
const TM = { ticket: 'تذكرة تحجزها المنشأة', cash: 'بدل نقدي' };
const fdt = ts => ts ? `<span class="num">${esc(String(ts).slice(0, 16).replace('T', ' '))}</span>` : '';

function journeyHtml(r, tl, acts) {
  if (!tl) return `<p class="small muted">${esc(tr('مسار الاعتماد'))}: ${r.route.map(s => esc(tr(STEP[s]))).join(' ← ')}</p>`;
  const ic = { done: ['✓', 'ok'], current: ['◀', 'info'], rejected: ['✗', 'bad'], cancelled: ['—', 'muted'], skipped: ['○', 'muted'], waiting: ['○', 'muted'] };
  const nm = s => (LANG === 'en' && s.by_en) || s.by;
  const rows = [`<li class="jr"><span class="jd ok">●</span><div><b>${esc(tr('أُرسل الطلب'))}</b> ${fdt(tl.submitted_at)}</div></li>`]
    .concat(tl.steps.map(s => { const [i, c] = ic[s.state] || ic.waiting;
      return `<li class="jr ${s.state}"><span class="jd ${c}">${i}</span><div><b>${esc(tr(STEP[s.step] || s.step))}</b>
        ${s.state === 'done' ? ` — ${esc(tr('اعتمده'))} ${esc(nm(s) || '')} ${fdt(s.at)}` : s.state === 'rejected' ? ` — <span class="bad">${esc(tr('رفضه'))} ${esc(nm(s) || '')}</span> ${fdt(s.at)}`
        : s.state === 'current' ? ` — <span class="${s.overdue ? 'bad' : 'muted'}">${esc(tr('بانتظاره'))} ${esc(waitTxt(s.since))}${s.overdue ? ' · ' + esc(tr('تجاوز المهلة')) + ' (' + tl.sla_days + ' ' + esc(tr('يوم')) + ')' : ''}</span>`
        : s.state === 'waiting' ? ` <span class="muted small">${esc(tr('لم يصل بعد'))}</span>` : ''}
        ${s.note ? `<div class="small">${esc(s.note)}</div>` : ''}</div></li>`; }))
    .concat(r.status === 'approved' && tl.decided_at ? [`<li class="jr"><span class="jd ok">★</span><div><b>${esc(tr('اعتُمد الطلب نهائياً'))}</b> ${fdt(tl.decided_at)}</div></li>`] : [])
    .concat(r.status === 'cancelled' ? [`<li class="jr"><span class="jd muted">—</span><div><b>${esc(tr('ألغاه الموظف'))}</b> ${fdt(tl.decided_at)}</div></li>`] : [])
    .concat((acts || []).filter(a => a.action === 'attached').map(a => `<li class="jr"><span class="jd muted">+</span><div>${esc(tr('أُرفق مستند'))} ${fdt(a.at)}</div></li>`));
  return `<div class="card" style="margin:10px 0;padding:10px 12px"><b class="small">${esc(tr('مسار الطلب'))}</b><ul class="journey">${rows.join('')}</ul></div>`;
}
function travelBox(r, tl) {
  const p = r.payload || {}, t = tl && tl.ticket, v = tl && tl.visa;
  if (!t && !v && !p.ticket && !p.visa) return '';
  const tk = t ? `${esc(tr(TM[t.mode]))} · ${esc(tr('المسافرون'))} <span class="num">${t.persons}</span> · ${badgeT(ttSt(t), ttCls(t))}${t.mode === 'cash' && t.amount != null ? ' · <span class="num">' + money(t.amount) + '</span>' : ''}${t.ref ? ' · ' + esc(tr('رقم الحجز')) + ' <span class="num">' + esc(t.ref) + '</span>' : ''}${(t.files || []).length ? '<div class="row" style="margin-top:6px">' + tfBtns(t.files) + '</div>' : ''}`
    : p.ticket ? `${esc(tr(TM[p.ticket.mode]))} · ${esc(tr('المسافرون'))} <span class="num">${p.ticket.persons}</span>` : '';
  const vz = v ? `${esc(tr(VZ_T[v.visa_type]))} · ${badgeT(v.status === 'requested' ? 'بانتظار إرفاق التأشيرة من الموارد البشرية' : VZ_ST[v.status], v.status === 'returned' ? 'ok' : v.status === 'not_returned' ? 'bad' : v.status === 'cancelled' ? '' : v.status === 'issued' ? 'ok' : 'wait')}${v.visa_no ? ' · ' + esc(tr('رقم التأشيرة')) + ' <span class="num">' + esc(v.visa_no) + '</span>' : ''}${v.expires_on ? ' · ' + esc(tr('آخر موعد للعودة')) + ' ' + fdate(v.expires_on) : ''}${v.returned_on ? ' · ' + esc(tr('عاد في')) + ' ' + fdate(v.returned_on) : ''}${(v.files || []).length ? '<div class="row" style="margin-top:6px">' + tfBtns(v.files) + '</div>' : ''}`
    : p.visa ? esc(tr(VZ_T[p.visa.type])) : '';
  return `<div class="card" style="margin:10px 0;padding:10px 12px"><b class="small">${esc(tr('السفر'))}</b>${tk ? `<div class="small" style="margin-top:4px">${esc(tr('التذكرة'))}: ${tk}</div>` : ''}${vz ? `<div class="small" style="margin-top:4px">${esc(tr('التأشيرة'))}: ${vz}</div>` : ''}</div>`;
}
const badgeT = (t, c) => `<span class="badge ${c || ''}">${esc(tr(t))}</span>`;

/* ----- approval settings: routes per request type, HR manager, deadline ----- */
const WF_KINDS = ['leave', 'permit', 'punch', 'advance', 'expense', 'purchase', 'cert', 'update', 'ticket', 'visa', 'resign', 'settle'];
const DEF_ROUTE = { leave: 'mphg', permit: 'mp', cert: 'p', punch: 'mp', advance: 'mphfg', resign: 'mphgf', settle: 'phfg', expense: 'mfg', ticket: 'mphf', visa: 'mph', update: 'p', purchase: 'mfg' };
VIEWS['#/workflows'] = async page => {
  if (!isHR()) { page.innerHTML = '<div class="note">هذه الصفحة للموارد البشرية.</div>'; return; }
  const [wf, mem, em] = await Promise.all([db.get('workflows', { company_id: 'eq.' + S.cid }), db.get('members', { company_id: 'eq.' + S.cid }), employeesMap(true)]);
  const cur = {}; wf.forEach(w => cur[w.kind] = w.route);
  const hrUsers = mem.filter(m => rolesOf(m).some(r => r === 'hr' || r === 'admin'));
  const mn = m => (m.employee_id && em[m.employee_id] ? ((LANG === 'en' && em[m.employee_id].full_name_en) || em[m.employee_id].full_name) : m.user_id === S.session.user.id ? S.session.user.email : '—');
  const admin = has('owner', 'admin'), steps = ['m', 'p', 'h', 'f', 'g'];
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('مسارات الاعتماد'))}</h1><div class="muted small">${esc(tr('من يعتمد كل نوع طلب وبأي ترتيب. الترتيب ثابت: المدير المباشر ثم الموارد البشرية ثم مدير الموارد البشرية ثم المالية ثم المدير العام.'))}</div></div></div>
    <div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(280px,1fr))">
      <div class="card"><h2>${esc(tr('مدير الموارد البشرية'))}</h2><select id="whm" ${admin ? '' : 'disabled'}><option value="">${esc(tr('غير معيّن — تُتخطى مرحلته'))}</option>${hrUsers.map(m => opt(m.user_id, mn(m), S.company.hr_manager || '')).join('')}</select>
        <p class="muted small">${esc(tr('يعيّنه المالك أو مدير النظام. إذا كان الشخص نفسه في مرحلتين متتاليتين يعتمد مرة واحدة.'))}</p></div>
      <div class="card"><h2>${esc(tr('مهلة كل مرحلة'))}</h2><div class="row"><input type="number" id="wsla" min="1" max="30" style="width:90px" value="${S.company.request_sla_days || ''}" placeholder="—"><span class="small">${esc(tr('يوم'))}</span><button class="btn sm" id="wslb">${esc(tr('حفظ'))}</button></div>
        <p class="muted small">${esc(tr('الطلب الذي يتأخر عند مرحلة أكثر من المهلة يظهر «متأخر» عند المعتمد وفي مسار الطلب. اتركها فارغة لإلغائها.'))}</p></div>
      <div class="card"><h2>${esc(tr('من يرفع طلب الشراء'))}</h2><div class="row"><select id="wpr" style="flex:1">${[['managers', 'مدراء الأقسام فقط'], ['selected', 'المدراء وموظفون محددون'], ['all', 'جميع الموظفين']].map(([k, t]) => opt(k, tr(t), S.company.purchase_requesters || 'managers')).join('')}</select><button class="btn sm" id="wprb">${esc(tr('حفظ'))}</button></div>
        <p class="muted small">${esc(tr('المدراء: من له موظفون تحته، والمالك والمالية. الموظفون المحددون: تُفعّل «يرفع طلبات الشراء» في ملف الموظف.'))}</p></div></div>
    <div class="card"><div class="tw"><table><thead><tr><th>${esc(tr('نوع الطلب'))}</th>${steps.map(s => `<th class="c">${esc(tr(STEP[s]))}</th>`).join('')}<th></th></tr></thead><tbody>
      ${WF_KINDS.map(k => { const rt = cur[k] || DEF_ROUTE[k].split(''); return `<tr data-wk="${k}"><td>${esc(tr(KIND[k]))}${cur[k] ? '' : ` <span class="muted small">(${esc(tr('افتراضي'))})</span>`}</td>${steps.map(s => `<td class="c"><input type="checkbox" data-st="${s}" style="width:auto" ${rt.includes(s) ? 'checked' : ''}></td>`).join('')}
        <td><button class="btn sm" data-wsave="${k}">${esc(tr('حفظ'))}</button>${cur[k] ? ` <button class="btn sm" data-wreset="${k}">${esc(tr('الافتراضي'))}</button>` : ''}</td></tr>`; }).join('')}</tbody></table></div>
      <p class="muted small">${esc(tr('المدير المباشر يُتخطى لمن ليس له مدير، والمدير العام لا يعتمد طلبه بنفسه، ومرحلة مدير الموارد البشرية تُتخطى إن لم يُعيَّن. الإجازة التي فيها تذكرة تمر على المالية تلقائياً. إذا لم يكن في المنشأة مدير مالي يعتمد المالك مرحلة المالية.'))}</p></div>`;
  $('#whm', page).onchange = async ev => { try { await db.rpc('hr_manager_set', { p_company: S.cid, p_user: blank(ev.target.value) }); await loadContext(); toast(tr('تم الحفظ')); } catch (er) { toast(er.message); route(); } };
  $('#wprb', page).onclick = async () => { try { await db.rpc('purchase_requesters_set', { p_company: S.cid, p_mode: $('#wpr', page).value }); await loadContext(); toast(tr('تم الحفظ')); } catch (er) { toast(er.message); } };
  $('#wslb', page).onclick = async () => { const v = $('#wsla', page).value; try { await db.rpc('request_sla_set', { p_company: S.cid, p_days: v ? +v : null }); await loadContext(); toast(tr('تم الحفظ')); } catch (er) { toast(er.message); } };
  $$('[data-wsave]', page).forEach(b => b.onclick = async () => { const k = b.dataset.wsave, tr_ = b.closest('tr');
    try { await db.rpc('workflow_set', { p_company: S.cid, p_kind: k, p_route: $$('[data-st]', tr_).filter(x => x.checked).map(x => x.dataset.st) }); toast(tr('تم الحفظ')); route(); } catch (er) { toast(er.message); } });
  $$('[data-wreset]', page).forEach(b => b.onclick = async () => { try { await db.rpc('workflow_set', { p_company: S.cid, p_kind: b.dataset.wreset, p_route: null }); toast(tr('تم الحفظ')); route(); } catch (er) { toast(er.message); } });
};

/* ----- travel desk ----- */
VIEWS['#/travel'] = async page => {
  if (!(isHR() || has('finance'))) { page.innerHTML = '<div class="note">هذه الصفحة للموارد البشرية والمالية.</div>'; return; }
  const d = await db.rpc('travel_board', { p_company: S.cid }), nm = x => (LANG === 'en' && x.name_en) || x.name, dst = x => (LANG === 'en' && x.dest_en) || x.dest || '—';
  const pay = has('owner', 'admin', 'finance'), hr = isHR();
  const late = d.visas.filter(v => v.late || v.expiring).length, toPay = d.tickets.filter(t => !t.paid && t.status !== 'cancelled').length, toIssue = d.visas.filter(v => v.status === 'requested').length;
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('السفر: التذاكر والتأشيرات'))}</h1><div class="muted small">${esc(tr('تذاكر السفر حسب العقد، وتأشيرات الخروج والعودة لغير السعوديين بعد اعتماد طلباتهم.'))}</div></div></div>
    <div class="grid">${[['تذاكر بانتظار الصرف', toPay, toPay], ['تأشيرات بانتظار الإصدار', toIssue, toIssue], ['تأشيرات تنتهي أو تأخر صاحبها', late, late], ['مستحقون للتذكرة', d.due.length, 0]].map(([l, v, b]) => `<div class="card kpi"><div class="muted small">${esc(tr(l))}</div><div class="v num ${b ? 'bad' : ''}">${v}</div></div>`).join('')}</div>
    <div class="card"><h2>${esc(tr('التذاكر'))}</h2>${tbl([{ t: 'الموظف', h: x => esc(nm(x)) + ` <span class="muted num small">${esc(x.emp_no)}</span>` }, { t: 'النوع', h: x => esc(tr(TM[x.mode])) },
      { t: 'المسافرون', r: 1, h: x => `<span class="num">${x.persons}</span>` }, { t: 'الوجهة', h: x => esc(dst(x)) }, { t: 'الإجازة', h: x => x.from_date ? fdate(x.from_date) + ' → ' + fdate(x.to_date) : '—' },
      { t: 'التقدير', r: 1, h: x => x.estimate != null ? money(x.estimate) : '—' }, { t: 'المصروف', r: 1, h: x => x.paid ? money(x.amount) : `<span class="muted small">${esc(tr('لم يُصرف'))}</span>` }, { t: 'الحالة', h: x => badgeT(ttSt(x), ttCls(x)) + (x.ref ? ` <span class="num small">${esc(x.ref)}</span>` : '') + ((x.files || []).length ? '<div class="row" style="margin-top:4px">' + tfBtns(x.files) + '</div>' : '') },
      { t: '', h: x => x.status === 'cancelled' ? '' : [hr && x.mode === 'ticket' ? `<button class="btn sm ${x.status === 'approved' ? 'pri' : ''}" data-tatt="${x.id}">${esc(tr(x.status === 'approved' ? 'إرفاق التذكرة' : 'إضافة مرفق'))}</button>` : '',
        pay && !x.paid ? `<button class="btn sm ${x.mode === 'cash' ? 'pri' : ''}" data-tpay="${x.id}">${esc(tr('تسجيل الصرف'))}</button>` : '', hr && x.status === 'approved' && !x.paid ? `<button class="btn sm" data-tcan="${x.id}">${esc(tr('إلغاء'))}</button>` : ''].join(' ') }], d.tickets, { empty: 'لا توجد تذاكر' })}</div>
    <div class="card"><h2>${esc(tr('تأشيرات الخروج والعودة'))}</h2>${tbl([{ t: 'الموظف', h: x => esc(nm(x)) + ` <span class="muted num small">${esc(x.emp_no)}</span>` }, { t: 'النوع', h: x => esc(tr(VZ_T[x.visa_type])) },
      { t: 'السفر', h: x => fdate(x.travel_on) }, { t: 'العودة المتوقعة', h: x => `<span class="${x.late ? 'bad' : ''}">${fdate(x.return_on)}</span>` }, { t: 'رقم التأشيرة', h: x => (x.visa_no ? `<span class="num">${esc(x.visa_no)}</span>` : '—') + ((x.files || []).length ? '<div class="row" style="margin-top:4px">' + tfBtns(x.files) + '</div>' : '') },
      { t: 'آخر موعد للعودة', h: x => x.expires_on ? `<span class="${x.expiring ? 'bad' : ''}">${fdate(x.expires_on)}</span>` : '—' },
      { t: 'الحالة', h: x => badgeT(VZ_ST[x.status], x.status === 'returned' ? 'ok' : x.status === 'not_returned' ? 'bad' : x.status === 'cancelled' ? '' : 'wait') + (x.late ? ' ' + badgeT('تأخر عن العودة', 'bad') : '') },
      { t: '', h: x => !hr ? '' : x.status === 'requested' ? `<button class="btn sm pri" data-vrec="${x.id}">${esc(tr('إرفاق التأشيرة'))}</button> <button class="btn sm" data-vcl="${x.id}|cancelled">${esc(tr('إلغاء'))}</button>`
        : x.status === 'issued' ? `<button class="btn sm pri" data-vret="${x.id}">${esc(tr('عاد'))}</button> <button class="btn sm danger" data-vcl="${x.id}|not_returned">${esc(tr('لم يعد'))}</button> <button class="btn sm" data-vrec="${x.id}">${esc(tr('تعديل'))}</button>` : '' }], d.visas, { empty: 'لا توجد تأشيرات' })}</div>
    <div class="card"><h2>${esc(tr('مستحقون للتذكرة الآن'))}</h2>${tbl([{ t: 'الموظف', h: x => esc(nm(x)) + ` <span class="muted num small">${esc(x.emp_no)}</span>` }, { t: 'التذاكر المستحقة', r: 1, h: x => `<b class="num">${x.available}</b>` },
      { t: 'المسافرون', r: 1, h: x => `<span class="num">${x.persons}</span>` }, { t: 'الوجهة', h: x => esc(dst(x)) }, { t: 'الدرجة', h: x => esc(tr(x.class === 'business' ? 'أعمال' : 'سياحية')) }, { t: 'التقدير', r: 1, h: x => x.amount != null ? money(n0(x.amount) * x.persons) : '—' }], d.due, { empty: 'لا أحد' })}
      <p class="muted small">${esc(tr('التذكرة حق تعاقدي: تُحدد في ملف الموظف (كل سنة أو سنتين، وعدد المسافرين، والوجهة). يطلبها الموظف مع إجازته أو منفردة، وما لم يُستخدم منها يظهر في حساب المخالصة.'))}</p></div>`;
  const T = id => d.tickets.find(x => x.id === id), V = id => d.visas.find(x => x.id === id);
  bindTravelFiles(page);
  const fileF = req => `<div class="wide"><label>${esc(tr(req ? 'الملف (صورة أو PDF)' : 'ملف إضافي (اختياري)'))}</label><input type="file" id="tvf" multiple accept="image/*,application/pdf"></div>`;
  const files = async () => Promise.all([...($('#tvf').files || [])].slice(0, 5).map(readAttachment));
  $$('[data-tatt]', page).forEach(b => b.onclick = () => { const t = T(b.dataset.tatt), first = !(t.files || []).length;
    modal(tr('إرفاق التذكرة') + ' — ' + nm(t), `<div class="fg">${field('رقم الحجز أو التذكرة', inp('ref', t.ref || '', 'dir="ltr"'))}${fileF(first)}</div><p class="muted small">${esc(tr('بعد الإرفاق تصل التذكرة للموظف في طلبه ويُنبَّه بها. صرف قيمتها تسجله المالية.'))}</p>`,
      { ok: 'إرفاق', onOk: async f => { const fl = await files(); if (first && !fl.length) throw new Error(tr('أرفق التذكرة (صورة أو PDF)'));
        await db.rpc('ticket_attach', { p_id: t.id, p_ref: blank(f.ref), p_files: fl }); toast(tr('وصلت للموظف')); route(); } }); });
  $$('[data-tpay]', page).forEach(b => b.onclick = () => { const t = T(b.dataset.tpay);
    modal(tr('تسجيل صرف التذكرة') + ' — ' + nm(t), `<div class="fg">${field('المبلغ', inp('amt', t.estimate || '', 'type="number" step="0.01" min="0" required'))}${field('المرجع (اختياري)', inp('ref', '', 'dir="ltr"'))}
      ${field('التاريخ', `<input type="date" name="on" value="${today()}">`)}${field('من حساب', `<select name="acc">${opt('1120', tr('البنك'))}${opt('1110', tr('الصندوق'))}</select>`)}</div><p class="muted small">${esc(tr('يُسجَّل قيد: مدين تذاكر سفر الموظفين، دائن البنك أو الصندوق.'))}</p>`,
      { ok: 'تسجيل', onOk: async f => { await db.rpc('ticket_pay', { p_id: t.id, p_amount: +f.amt, p_ref: blank(f.ref), p_on: f.on, p_account: f.acc }); toast(tr('تم الحفظ')); route(); } }); });
  $$('[data-tcan]', page).forEach(b => b.onclick = async () => { if (!await confirmBox('إلغاء التذكرة', 'تعود التذكرة إلى رصيد الموظف.', 'إلغاء التذكرة')) return; try { await db.rpc('ticket_cancel', { p_id: b.dataset.tcan }); route(); } catch (er) { toast(er.message); } });
  $$('[data-vrec]', page).forEach(b => b.onclick = () => { const v = V(b.dataset.vrec);
    modal(tr('إرفاق التأشيرة') + ' — ' + nm(v), `<div class="fg">${field('رقم التأشيرة', inp('no', v.visa_no || '', 'dir="ltr" required'))}${field('النوع', `<select name="ty">${opt('single', tr(VZ_T.single), v.visa_type)}${opt('multiple', tr(VZ_T.multiple), v.visa_type)}</select>`)}
      ${field('تاريخ الإصدار', `<input type="date" name="iss" value="${v.issued_on || today()}">`)}${field('آخر موعد للعودة', `<input type="date" name="exp" value="${v.expires_on || v.return_on || ''}">`)}${fileF(!(v.files || []).length)}</div><p class="muted small">${esc(tr('تصدر من منصة مقيم أو أبشر أعمال، ثم تُرفق هنا فتصل للموظف في طلبه، ويتابعها النظام وينبه قبل انتهائها.'))}</p>`,
      { ok: 'حفظ', onOk: async f => { const fl = await files(); if (!(v.files || []).length && !fl.length) throw new Error(tr('أرفق التأشيرة (صورة أو PDF)'));
        await db.rpc('visa_record', { p_id: v.id, p_no: f.no, p_issued: f.iss, p_expires: f.exp, p_type: f.ty, p_files: fl }); toast(tr('وصلت للموظف')); route(); } }); });
  $$('[data-vret]', page).forEach(b => b.onclick = () => { const v = V(b.dataset.vret);
    modal(tr('تسجيل العودة') + ' — ' + nm(v), field('تاريخ العودة', `<input type="date" name="on" value="${today()}">`), { ok: 'حفظ', onOk: async f => { await db.rpc('visa_close', { p_id: v.id, p_status: 'returned', p_on: f.on }); toast(tr('تم الحفظ')); route(); } }); });
  $$('[data-vcl]', page).forEach(b => b.onclick = async () => { const [id, st] = b.dataset.vcl.split('|');
    if (!await confirmBox(st === 'cancelled' ? 'إلغاء التأشيرة' : 'لم يعد', st === 'cancelled' ? 'إلغاء طلب التأشيرة قبل إصدارها.' : 'يُسجَّل أن الموظف لم يعد من السفر. راجع إجراءات الغياب وإبلاغ الجهات.', 'تأكيد')) return;
    try { await db.rpc('visa_close', { p_id: id, p_status: st }); route(); } catch (er) { toast(er.message); } });
};
