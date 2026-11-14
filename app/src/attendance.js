'use strict';
const spanMin = (a, b) => { if (!a || !b) return 0; const m = t => +t.slice(0, 2) * 60 + +t.slice(3, 5); const d = m(b) - m(a); return d <= 0 ? d + 1440 : d; };
// lateness after an approved permit (استئذان) — the covered minutes are shown beside it
const lateCell = r => mins(r.late_min) + (n0(r.permit_min) ? ` <span class="small ok">(استئذان ${mins(r.permit_min)})</span>` : '');
/* ===== attendance: check-in/out from the phone, HR board, monthly sheet, settings ===== */
const AT_ST = { present: ['حاضر', 'ok'], late: ['متأخر', 'wait'], open: ['داخل الدوام', 'info'], nocheckout: ['بدون انصراف', 'bad'], absent: ['غائب', 'bad'],
  leave: ['إجازة', 'info'], holiday: ['عطلة رسمية', ''], off: ['راحة', ''], pending: ['لم يسجّل بعد', 'wait'], na: ['—', ''] };
const atBadge = s => `<span class="badge ${(AT_ST[s] || ['', ''])[1]}">${esc((AT_ST[s] || [s])[0])}</span>`;
const DOW = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
const rToday = () => new Date(Date.now() + 3 * 3600e3).toISOString().slice(0, 10);          // Riyadh (UTC+3, no DST)
const hm = ts => ts ? new Date(ts).toLocaleTimeString('en-GB', { timeZone: 'Asia/Riyadh', hour: '2-digit', minute: '2-digit' }) : '—';
const mins = m => { m = n0(m); if (!m) return '—'; const h = Math.floor(m / 60); return (h ? h + ' س ' : '') + (m % 60 ? (m % 60) + ' د' : ''); };
const monthEnd = ym => { const [y, m] = ym.split('-').map(Number); return new Date(Date.UTC(y, m, 0)).toISOString().slice(0, 10); };
const dayName = d => DOW[new Date(d + 'T12:00:00Z').getUTCDay()];
const attOn = () => !!(S.company && S.company.att_enabled);

/* ---------- employee: my attendance ---------- */
VIEWS['#/attendance'] = async (page, arg) => {
  if (!S.emp) { page.innerHTML = '<div class="note">حسابك غير مربوط بسجل موظف.</div>'; return; }
  const ym = /^\d{4}-\d{2}$/.test(arg || '') ? arg : rToday().slice(0, 7);
  const from = ym + '-01', to = monthEnd(ym) < rToday() ? monthEnd(ym) : rToday();
  const rows = from <= to ? await db.rpc('att_sheet', { p_company: S.cid, p_from: from, p_to: to, p_emp: S.emp }) : [];
  rows.reverse();
  const cnt = s => rows.filter(r => s.includes(r.status)).length;
  const prev = new Date(Date.UTC(+ym.slice(0, 4), +ym.slice(5) - 2, 1)).toISOString().slice(0, 7), next = new Date(Date.UTC(+ym.slice(0, 4), +ym.slice(5), 1)).toISOString().slice(0, 7);
  page.innerHTML = `<div class="head"><div><h1>الحضور والانصراف</h1><div class="muted">${esc(S.myEmp ? S.myEmp.full_name : '')}</div></div></div>
    ${attOn() ? await clockCard() : `<div class="note">تسجيل الحضور غير مفعّل في منشأتك.${isHR() ? ' <a href="#/att/settings">فعّله من الإعدادات</a>' : ''}</div>`}
    <div class="row" style="margin:14px 0 10px;align-items:center"><a class="btn sm" href="#/attendance/${prev}">→</a><b class="num">${ym}</b>${next <= rToday().slice(0, 7) ? `<a class="btn sm" href="#/attendance/${next}">←</a>` : ''}</div>
    <div class="grid" style="margin-bottom:14px">
      <div class="card kpi"><div class="muted small">أيام الحضور</div><div class="v num">${cnt(['present', 'late', 'open', 'nocheckout'])}</div></div>
      <div class="card kpi"><div class="muted small">أيام الغياب</div><div class="v num ${cnt(['absent']) ? 'bad' : ''}">${cnt(['absent'])}</div></div>
      <div class="card kpi"><div class="muted small">دقائق التأخير</div><div class="v num">${rows.reduce((a, r) => a + n0(r.late_min), 0)}</div></div>
      <div class="card kpi"><div class="muted small">إضافي معتمد</div><div class="v num">${mins(rows.reduce((a, r) => a + n0(r.ot_min), 0))}</div></div></div>
    ${tbl([{ t: 'التاريخ', h: r => `${esc(dayName(r.day))} <span class="num muted">${fdate(r.day)}</span>` }, { t: 'الحالة', h: r => atBadge(r.status) }, { t: 'الحضور', h: r => `<span class="num">${hm(r.check_in)}</span>` },
      { t: 'الانصراف', h: r => `<span class="num">${hm(r.check_out)}</span>` }, { t: 'التأخير', h: lateCell }, { t: 'إضافي', h: r => r.extra_min ? mins(r.extra_min) + (r.ot_min ? ` <span class="ok small">(معتمد ${mins(r.ot_min)})</span>` : '') : '—' },
      { t: 'ملاحظة', h: r => r.source === 'hr' ? `<span class="muted small">عدّلته الموارد البشرية: ${esc(r.note || '')}</span>` : r.source === 'request' ? `<span class="muted small">${esc(tr('نسيان بصمة — طلب معتمد'))}</span>` : '' }], rows.filter(r => r.status !== 'na'), { empty: 'لا توجد بيانات' })}`;
  bindClock(page);
};
async function clockCard() {
  const [t] = await db.rpc('att_sheet', { p_company: S.cid, p_from: rToday(), p_to: rToday(), p_emp: S.emp }).catch(() => []);
  const [sh] = S.myEmp && S.myEmp.shift_id ? await db.get('shifts', { id: 'eq.' + S.myEmp.shift_id }) : await db.get('shifts', { company_id: 'eq.' + S.cid, is_default: 'is.true' });
  if (S.myEmp && S.myEmp.att_exempt) return '<div class="note">أنت معفى من تسجيل الحضور.</div>';
  const done = t && t.check_out, inside = t && t.check_in && !t.check_out;
  return `<div class="card clock"><div><div class="muted small">${esc(dayName(rToday()))} <span class="num">${rToday()}</span>${sh ? ` · ${esc(sh.name)} <span class="num">${sh.start_time.slice(0, 5)}–${sh.end_time.slice(0, 5)}</span>` : ''}</div>
      <div style="margin:4px 0 2px">${t ? atBadge(t.status) : ''} ${t && t.check_in ? `حضور <b class="num">${hm(t.check_in)}</b>` : ''} ${t && t.check_out ? ` · انصراف <b class="num">${hm(t.check_out)}</b>` : ''}</div>
      ${t && t.late_min ? `<div class="small bad">تأخير ${mins(t.late_min)}</div>` : ''}</div>
    ${done ? '<div class="muted">سجّلت الحضور والانصراف لهذا اليوم</div>' : `<button class="btn pri big" id="clk">${inside ? 'تسجيل الانصراف' : 'تسجيل الحضور'}</button>`}
    <div id="clkerr" style="width:100%"></div></div>`;
}
function bindClock(page) {
  const b = $('#clk', page); if (!b) return;
  b.onclick = () => busy(b, async () => {
    $('#clkerr', page).innerHTML = '';
    let pos = null;
    try { pos = await new Promise((res, rej) => navigator.geolocation ? navigator.geolocation.getCurrentPosition(res, rej, { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }) : rej(new Error('no geolocation'))); }
    catch (e) { pos = null; }
    try {
      const r = await db.rpc('clock', pos ? { p_company: S.cid, p_lat: +pos.coords.latitude.toFixed(6), p_lng: +pos.coords.longitude.toFixed(6), p_acc: Math.round(pos.coords.accuracy) } : { p_company: S.cid });
      toast(r.action === 'in' ? 'سُجّل حضورك ' + hm(r.at) + (r.late_min ? ' — تأخير ' + mins(r.late_min) : '') : 'سُجّل انصرافك ' + hm(r.at));
      route();
    } catch (e) { showErr($('#clkerr', page), e); }
  });
}

/* ---------- HR / managers ---------- */
VIEWS['#/att'] = async (page, arg) => {
  if (!isHR() && !has('manager', 'finance')) { page.innerHTML = '<div class="note">هذه الصفحة للموارد البشرية.</div>'; return; }
  const [tab, sub] = String(arg || 'today').split('/');
  const tabs = [['today', 'اليوم'], ['month', 'الكشف الشهري']].concat(isHR() ? [['settings', 'الإعدادات']] : []);
  page.innerHTML = `<div class="head"><div><h1>الحضور والانصراف</h1><div class="muted">${attOn() ? 'مفعّل منذ <span class="num">' + fdate(S.company.att_start) + '</span>' : 'غير مفعّل'}</div></div></div>
    <div class="tabs" style="max-width:420px">${tabs.map(([k, t]) => `<button type="button" class="${k === tab ? 'on' : ''}" data-tab="${k}">${t}</button>`).join('')}</div><div id="atb"></div>`;
  $$('[data-tab]', page).forEach(b => b.onclick = () => location.hash = '#/att/' + b.dataset.tab);
  const box = $('#atb', page);
  if (tab === 'settings' && isHR()) return attSettings(box);
  if (!attOn()) { box.innerHTML = `<div class="note">تسجيل الحضور غير مفعّل بعد.${isHR() ? ' أضف موقع العمل والوردية من «الإعدادات» ثم فعّله.' : ''}</div>`; return; }
  if (tab === 'month') return attMonth(box, sub);
  return attToday(box);
};
async function attToday(box) {
  const d = rToday();
  const [rows, em] = await Promise.all([db.rpc('att_sheet', { p_company: S.cid, p_from: d, p_to: d }), employeesMap(true)]);
  const c = s => rows.filter(r => s.includes(r.status)).length;
  box.innerHTML = `<div class="grid" style="margin-bottom:14px">
      <div class="card kpi"><div class="muted small">حاضرون</div><div class="v num ok">${c(['present', 'late', 'open', 'nocheckout'])}</div></div>
      <div class="card kpi"><div class="muted small">متأخرون</div><div class="v num">${rows.filter(r => n0(r.late_min) > 0).length}</div></div>
      <div class="card kpi"><div class="muted small">لم يسجّلوا بعد</div><div class="v num ${c(['pending']) ? 'bad' : ''}">${c(['pending'])}</div></div>
      <div class="card kpi"><div class="muted small">في إجازة</div><div class="v num">${c(['leave'])}</div></div></div>
    ${tbl([{ t: 'الموظف', h: r => esc((em[r.employee_id] || {}).full_name || '') }, { t: 'الحالة', h: r => atBadge(r.status) }, { t: 'الحضور', h: r => `<span class="num">${hm(r.check_in)}</span>` }, { t: 'الانصراف', h: r => `<span class="num">${hm(r.check_out)}</span>` }, { t: 'التأخير', h: lateCell }],
      rows.filter(r => r.status !== 'na'), { empty: 'لا يوجد موظفون', onRow: isHR() })}
    <p class="muted small">يوم <span class="num">${d}</span> بتوقيت الرياض.${isHR() ? ' اضغط على أي موظف لتعديل حضوره.' : ''}</p>`;
  if (isHR()) bindRows(box, rows.filter(r => r.status !== 'na'), r => attEdit(r, em));
}
async function attMonth(box, sub) {
  const [ymArg, empArg] = String(sub || '').split(':');
  const ym = /^\d{4}-\d{2}$/.test(ymArg || '') ? ymArg : rToday().slice(0, 7);
  const from = ym + '-01', to = monthEnd(ym) < rToday() ? monthEnd(ym) : rToday();
  const em = await employeesMap(true);
  const rows = from <= to ? await db.rpc('att_sheet', { p_company: S.cid, p_from: from, p_to: to, p_emp: empArg || null }) : [];
  const ids = [...new Set(rows.map(r => r.employee_id))];
  const pick = `<div class="row" style="margin-bottom:12px;align-items:end"><div><label>الشهر</label><input type="month" id="amy" value="${ym}" max="${rToday().slice(0, 7)}"></div>
    <div><label>الموظف</label><select id="ame"><option value="">كل الموظفين</option>${Object.values(em).filter(e => !e.att_exempt).map(e => opt(e.id, e.full_name + ' (' + e.emp_no + ')', empArg || '')).join('')}</select></div></div>`;
  if (empArg) {
    box.innerHTML = pick + tbl([{ t: 'التاريخ', h: r => `${esc(dayName(r.day))} <span class="num muted">${fdate(r.day)}</span>` }, { t: 'الحالة', h: r => atBadge(r.status) }, { t: 'الحضور', h: r => `<span class="num">${hm(r.check_in)}</span>` }, { t: 'الانصراف', h: r => `<span class="num">${hm(r.check_out)}</span>` },
      { t: 'التأخير', h: lateCell }, { t: 'خروج مبكر', h: r => mins(r.early_min) }, { t: 'إضافي', h: r => mins(r.extra_min) }, { t: 'إضافي معتمد', h: r => r.ot_min ? `<span class="ok">${mins(r.ot_min)}</span>` : '—' }, { t: 'ملاحظة', h: r => esc(r.note || '') }],
      rows.filter(r => r.status !== 'na'), { empty: 'لا توجد بيانات', onRow: isHR() });
    if (isHR()) bindRows(box, rows.filter(r => r.status !== 'na'), r => attEdit(r, em));
  } else {
    const sumBy = id => { const l = rows.filter(r => r.employee_id === id); const n = s => l.filter(r => s.includes(r.status)).length;
      return { id, present: n(['present', 'late', 'open', 'nocheckout']), absent: n(['absent']), leave: n(['leave']), noout: n(['nocheckout']), late: l.reduce((a, r) => a + n0(r.late_min), 0), extra: l.reduce((a, r) => a + n0(r.extra_min), 0), ot: l.reduce((a, r) => a + n0(r.ot_min), 0) }; };
    const sums = ids.map(sumBy);
    box.innerHTML = pick + tbl([{ t: 'الموظف', h: x => esc((em[x.id] || {}).full_name || '') }, { t: 'حضور', r: 1, h: x => x.present }, { t: 'غياب', r: 1, h: x => x.absent ? `<span class="bad">${x.absent}</span>` : 0 }, { t: 'إجازة', r: 1, h: x => x.leave },
      { t: 'بدون انصراف', r: 1, h: x => x.noout ? `<span class="bad">${x.noout}</span>` : 0 }, { t: 'التأخير', h: x => mins(x.late) }, { t: 'إضافي', h: x => mins(x.extra) }, { t: 'إضافي معتمد', h: x => mins(x.ot) }], sums, { empty: 'لا يوجد موظفون', onRow: true })
      + `<p class="muted small">الغياب والتأخير والإضافي المعتمد تنتقل إلى مسير الرواتب عند إعداده. الإضافي لا يُحتسب إلا بعد اعتماده (م107).</p>`;
    bindRows(box, sums, x => location.hash = '#/att/month/' + ym + ':' + x.id);
  }
  const go = () => location.hash = '#/att/month/' + ($('#amy', box).value || ym) + ($('#ame', box).value ? ':' + $('#ame', box).value : '');
  $('#amy', box).onchange = go; $('#ame', box).onchange = go;
}
function attEdit(r, em) {
  const e = em[r.employee_id] || {};
  const loc = ts => ts ? hm(ts) : '';
  const d = modal('تعديل الحضور — ' + (e.full_name || ''), `<p class="muted small">${esc(dayName(r.day))} <span class="num">${fdate(r.day)}</span> · ${atBadge(r.status)}</p>
    <div class="fg">${field('وقت الحضور', `<input type="time" name="tin" value="${loc(r.check_in)}">`)}${field('وقت الانصراف', `<input type="time" name="tout" value="${loc(r.check_out)}">`)}
    ${field('سبب التعديل', inp('note', '', 'required placeholder="مثال: نسي تسجيل الانصراف"'), 'wide')}
    ${n0(r.extra_min) ? field('الإضافي المعتمد بالدقائق (من ' + r.extra_min + ')', inp('ot', r.ot_min || 0, `type="number" min="0" max="${r.extra_min}" step="1"`), 'wide') : ''}</div>
    <p class="muted small">اترك وقت الحضور فارغا لحذف السجل واعتبار اليوم غيابا. التعديل يُحفظ في سجل التدقيق.</p>
    ${n0(r.ot_min) && r.att_id ? '<div class="row"><button type="button" class="btn sm" id="ot2c">تحويل الإضافي المعتمد إلى إجازة تعويضية</button></div>' : ''}`, {
    onOk: async f => {
      const changed = (f.tin || '') !== loc(r.check_in) || (f.tout || '') !== loc(r.check_out);
      if (changed || !r.att_id) await db.rpc('att_set', { p_company: S.cid, p_emp: r.employee_id, p_day: r.day, p_in: blank(f.tin), p_out: blank(f.tout), p_note: f.note });
      if (f.ot != null && f.ot !== '' && r.att_id && +f.ot !== n0(r.ot_min)) await db.rpc('att_approve_ot', { p_id: r.att_id, p_minutes: Math.round(+f.ot) });
      toast('تم الحفظ'); route();
    } });
  if ($('#ot2c', d)) $('#ot2c', d).onclick = () => { d.close(); modal('تحويل إلى إجازة تعويضية', `<div class="fg">${field('الدقائق المحوّلة (من ' + r.ot_min + ')', inp('m', r.ot_min, `type="number" min="1" max="${r.ot_min}" step="1"`))}${field('ساعات الإجازة عن كل ساعة (1.5 على الأقل)', inp('rate', 1.5, 'type="number" step="0.25" min="1.5"'))}
      <label class="wide row small" style="gap:6px"><input type="checkbox" name="ok"> ${esc('وافق العامل على الإجازة التعويضية بدل أجر العمل الإضافي')}</label></div>
      <p class="muted small">م107 والمادة 22 مكرر من اللائحة: الدقائق المحوّلة لا تُصرف في المسير، وتُضاف لرصيد الإجازة التعويضية للموظف.</p>`, {
      ok: 'تحويل', onOk: async f => { await db.rpc('att_ot_to_comp', { p_att: r.att_id, p_minutes: Math.round(+f.m || 0), p_rate: +f.rate || 0, p_consent: !!f.ok }); toast('أُضيفت للإجازة التعويضية'); route(); } }); };
  return d;
}

/* ---------- settings: sites, shifts, holidays ---------- */
async function attSettings(box) {
  const [sites, shifts, hols] = await Promise.all([db.get('work_sites', { company_id: 'eq.' + S.cid, order: 'name' }), db.get('shifts', { company_id: 'eq.' + S.cid, order: 'name' }), db.get('holidays', { company_id: 'eq.' + S.cid, order: 'day.desc' })]);
  const c = S.company;
  const deps = { list: await db.get('departments', { company_id: 'eq.' + S.cid, order: 'name' }).catch(() => []), cnt: {} };
  Object.values(await employeesMap()).forEach(e => { if (e.department_id && (!e.end_date || e.end_date >= today())) deps.cnt[e.department_id] = (deps.cnt[e.department_id] || 0) + 1; });
  box.innerHTML = `<div class="card"><h2>التفعيل</h2><form id="asf" class="fg" novalidate>
      ${field('تسجيل الحضور', `<select name="en">${opt('false', 'غير مفعّل', String(c.att_enabled))}${opt('true', 'مفعّل', String(c.att_enabled))}</select>`)}
      ${field('يبدأ احتساب الغياب من', `<input type="date" name="st" value="${esc(c.att_start || rToday())}">`)}
      ${field('التحقق من الموقع', `<select name="geo">${opt('true', 'نعم — داخل مواقع العمل فقط', String(c.att_geofence))}${opt('false', 'لا', String(c.att_geofence))}</select>`)}
      ${field('حسم دقائق التأخير من الراتب', `<select name="dl">${opt('false', 'لا', String(c.att_deduct_late))}${opt('true', 'نعم — بقدر الوقت المتأخر', String(c.att_deduct_late))}</select>`)}
      ${field('حد ساعات الاستئذان في الشهر', `<input name="plim" type="number" step="0.5" min="0.5" max="200" placeholder="${esc(tr('بلا حد'))}" value="${c.permit_hours_month == null ? '' : esc(c.permit_hours_month)}">`)}
      ${field('بداية رمضان', `<input type="date" name="rf" value="${esc(c.ramadan_from || '')}">`)}${field('نهاية رمضان', `<input type="date" name="rt" value="${esc(c.ramadan_to || '')}">`)}
      ${field('بداية الدوام في رمضان للورديات بلا وقت رمضان', `<input type="time" name="rs" value="${esc(String(c.ramadan_start || '').slice(0, 5))}">`)}${field('ساعات العمل اليومية في رمضان', `<input name="rh" type="number" step="0.5" min="4" max="6" value="${esc(c.ramadan_hours || 6)}">`)}
      ${field('حد طلبات نسيان البصمة في الشهر', `<input name="flim" type="number" step="1" min="0" max="31" placeholder="${esc(tr('بلا حد'))}" value="${c.punch_fix_month == null ? '' : esc(c.punch_fix_month)}">`)}
      <div class="wide"><button class="btn pri" id="ass">حفظ</button></div><div id="aserr" class="wide"></div></form>
      <p class="muted small">${esc(tr('رمضان (م98): لا تزيد ساعات العمل على 6 ساعات يوميا و36 أسبوعيا للعمال المسلمين فقط (حسب الديانة في ملف الموظف). كل وردية تستخدم وقت رمضان المحدد لها، وإن لم يُحدد تبدأ من بداية الدوام في رمضان أدناه بعدد الساعات. يُعاد احتساب الحضور تلقائيا.'))}</p>
      <p class="muted small">${esc(tr('الحدود الشهرية من لائحة المنشأة الداخلية، وتُحسب على شهر الرواتب (مع يوم الإقفال إن وُجد). اتركها فارغة لعدم التحديد.'))}</p>
      <p class="muted small">الغياب بلا عذر يُحسم بأجر اليوم (الأجر الفعلي ÷ 30). حسم التأخير يكون بقدر الوقت الذي لم يُعمل فيه فقط؛ أي جزاء إضافي يحتاج لائحة جزاءات معتمدة وتحقيقا (م66 و71).</p></div>
    <div class="card"><div class="row" style="justify-content:space-between"><h2>مواقع العمل</h2><button class="btn sm" id="ns">+ موقع</button></div>
      ${tbl([{ t: 'الموقع', k: 'name' }, { t: 'الإحداثيات', h: s => `<span class="num small">${(+s.lat).toFixed(5)}, ${(+s.lng).toFixed(5)}</span>` }, { t: 'النطاق', h: s => `<span class="num">${s.radius_m}</span> م` }], sites, { empty: 'لا توجد مواقع — بدونها يُقبل التسجيل من أي مكان', onRow: true })}</div>
    <div class="card"><div class="row" style="justify-content:space-between"><h2>الورديات</h2><button class="btn sm" id="nsh">+ وردية</button></div>
      ${tbl([{ t: 'الوردية', h: s => esc(s.name) + (s.is_default ? ' <span class="badge info">الافتراضية</span>' : '') }, { t: 'الوقت', h: s => `<span class="num">${s.start_time.slice(0, 5)}–${s.end_time.slice(0, 5)}</span>` }, { t: 'الراحة', h: s => s.break_min ? `<span class="num">${s.break_min}</span> ${esc(tr('د'))}` : '—' },
        { t: 'ساعات العمل', h: s => `<span class="num">${r2((spanMin(s.start_time, s.end_time) - n0(s.break_min)) / 60)}</span>` }, { t: 'في رمضان', h: s => s.ramadan_start ? `<span class="num">${s.ramadan_start.slice(0, 5)}–${s.ramadan_end.slice(0, 5)}</span>` : '<span class="muted small">' + esc(tr('حسب إعداد رمضان العام')) + '</span>' }, { t: 'السماح', h: s => s.grace_min + ' د' }, { t: 'أيام العمل', h: s => s.work_days.map(i => DOW[i]).join('، ') }], shifts, { empty: 'لا توجد ورديات', onRow: true })}</div>
    <div class="card"><div class="row" style="justify-content:space-between"><h2>العطل الرسمية</h2><div class="row"><button class="btn sm" id="nat">+ اليوم الوطني ويوم التأسيس</button><button class="btn sm" id="nh">+ عطلة</button></div></div>
      ${tbl([{ t: 'التاريخ', h: h => `${esc(dayName(h.day))} <span class="num">${fdate(h.day)}</span>` }, { t: 'العطلة', k: 'name' }], hols, { empty: 'لا توجد عطل', onRow: true })}
      <p class="muted small">أضف عطلتي عيد الفطر وعيد الأضحى بتواريخهما كل سنة حسب إعلان وزارة الموارد البشرية.</p></div>
    <div class="card"><h2>${esc(tr('ورديات الأقسام'))}</h2><p class="muted small">${esc(tr('الوردية الفعلية للموظف: ورديته في ملفه، وإلا وردية قسمه، وإلا الوردية الافتراضية.'))}</p>
      ${tbl([{ t: 'القسم', h: d => esc((LANG === 'en' && d.name_en) || d.name) }, { t: 'الموظفون', r: 1, h: d => String(deps.cnt[d.id] || 0) },
        { t: 'الوردية', h: d => `<select data-dsh="${d.id}" style="width:auto"><option value="">${esc(tr('الافتراضية'))}</option>${shifts.map(x => opt(x.id, x.name + ' (' + x.start_time.slice(0, 5) + '–' + x.end_time.slice(0, 5) + ')', d.shift_id)).join('')}</select>` },
        { t: '', h: d => d.shift_id ? `<button type="button" class="btn sm" data-dov="${d.id}">${esc(tr('فرضها على كل موظفي القسم'))}</button>` : '' }], deps.list, { empty: 'لا توجد أقسام' })}</div>`;
  $$('[data-dsh]', box).forEach(x => x.onchange = async () => { try { await db.rpc('department_shift_set', { p_dept: x.dataset.dsh, p_shift: blank(x.value), p_override: false }); cache.deps = null; toast('تم الحفظ'); route(); } catch (er) { toast(er.message); } });
  $$('[data-dov]', box).forEach(b => b.onclick = async () => { if (!await confirmBox(tr('فرض وردية القسم'), tr('تُلغى الورديات الخاصة لموظفي هذا القسم ويطبق عليهم وردية القسم.'), tr('فرض'))) return;
    try { const n = await db.rpc('department_shift_set', { p_dept: b.dataset.dov, p_shift: (deps.list.find(d => d.id === b.dataset.dov) || {}).shift_id, p_override: true }); toast(tr('تم التطبيق على') + ' ' + n); route(); } catch (er) { toast(er.message); } });
  const [stbl, shtbl, htbl] = $$('.tw', box);
  $('#ass', box).onclick = ev => { ev.preventDefault(); busy(ev.target, async () => { const f = formData($('#asf', box));
    try { await db.rpc('att_settings', { p_company: S.cid, p_enabled: f.en === 'true', p_start: blank(f.st), p_geofence: f.geo === 'true', p_deduct_late: f.dl === 'true' });
      if (!!f.rf !== !!f.rt) throw new Error(tr('حدد بداية رمضان ونهايته'));
      await db.rpc('ramadan_set', { p_company: S.cid, p_from: blank(f.rf), p_to: blank(f.rt), p_start: blank(f.rs), p_hours: +f.rh || 6 });
      await db.rpc('month_limits_set', { p_company: S.cid, p_permit_hours: f.plim === '' || f.plim == null ? null : +f.plim, p_punch: f.flim === '' || f.flim == null ? null : +f.flim }); await loadContext(); shell(); toast('تم الحفظ'); route(); } catch (e) { showErr($('#aserr', box), e); } }); };
  const siteForm = s => { const v = s || { radius_m: 200 };
    const d = modal(s ? 'تعديل موقع' : 'موقع عمل جديد', `<div class="fg">${field('اسم الموقع', inp('name', v.name, 'required'))}${enF('name_en', v.name_en)}${field('خط العرض', inp('lat', v.lat, 'dir="ltr" inputmode="decimal"'))}${field('خط الطول', inp('lng', v.lng, 'dir="ltr" inputmode="decimal"'))}
      ${field('نصف قطر النطاق (متر)', inp('r', v.radius_m, 'type="number" min="30" max="5000"'))}<div class="wide"><button type="button" class="btn sm" id="here">استخدم موقعي الحالي</button> <span class="muted small" id="hereinf"></span></div>
      ${s ? '<div class="wide"><button type="button" class="btn sm danger" id="sdel">حذف الموقع</button></div>' : ''}</div><p class="muted small">افتح هذه النافذة وأنت داخل مقر العمل واضغط «استخدم موقعي الحالي». 200 متر نطاق مناسب لأغلب المباني.</p>`, {
      onOk: async f => { if (!(f.name || '').trim()) throw new Error('أدخل اسم الموقع'); if (!(Math.abs(+f.lat) <= 90) || !(Math.abs(+f.lng) <= 180) || f.lat === '' || f.lng === '') throw new Error('أدخل الإحداثيات أو استخدم موقعك الحالي');
        const row = { name: f.name.trim(), name_en: blank((f.name_en || '').trim()), lat: +(+f.lat).toFixed(6), lng: +(+f.lng).toFixed(6), radius_m: Math.round(+f.r || 200) };
        if (s) await db.upd('work_sites', { id: 'eq.' + s.id }, row); else await db.ins('work_sites', Object.assign(row, { company_id: S.cid })); route(); } });
    $('#here', d).onclick = () => navigator.geolocation ? navigator.geolocation.getCurrentPosition(p => { const f = $('#mform', d); f.lat.value = p.coords.latitude.toFixed(6); f.lng.value = p.coords.longitude.toFixed(6); $('#hereinf', d).textContent = 'دقة ± ' + Math.round(p.coords.accuracy) + ' م'; },
      () => { $('#hereinf', d).textContent = 'تعذّر تحديد موقعك — اسمح للمتصفح باستخدام الموقع'; }, { enableHighAccuracy: true, timeout: 15000 }) : null;
    if (s) $('#sdel', d).onclick = async () => { try { await db.del('work_sites', { id: 'eq.' + s.id }); d.close(); route(); } catch (e) { showErr($('#merr', d), e); } }; };
  const shiftForm = s => { const v = s || { start_time: '08:00', end_time: '16:00', grace_min: 15, break_min: 60, work_days: [0, 1, 2, 3, 4], is_default: !shifts.length };
    const d = modal(s ? 'تعديل وردية' : 'وردية جديدة', `<div class="fg">${field('اسم الوردية', inp('name', v.name, 'required'))}${enF('name_en', v.name_en)}${field('بداية الدوام', `<input type="time" name="st" value="${String(v.start_time).slice(0, 5)}">`)}${field('نهاية الدوام', `<input type="time" name="en" value="${String(v.end_time).slice(0, 5)}">`)}
      ${field('مدة الراحة (دقيقة)', inp('brk', v.break_min || 0, 'type="number" min="0" max="180" step="5"'))}
      ${field('بداية الدوام في رمضان (للمسلمين)', `<input type="time" name="rst" value="${String(v.ramadan_start || '').slice(0, 5)}">`)}${field('نهاية الدوام في رمضان', `<input type="time" name="ren" value="${String(v.ramadan_end || '').slice(0, 5)}">`)}
      <div class="wide"><p class="small" id="shh" style="margin:0"></p></div>
      ${field('فترة السماح بالتأخير (دقيقة)', inp('g', v.grace_min, 'type="number" min="0" max="120"'))}${field('الوردية الافتراضية', `<select name="def">${opt('false', 'لا', String(v.is_default))}${opt('true', 'نعم — لكل موظف بلا وردية محددة', String(v.is_default))}</select>`)}
      <div class="wide"><label>أيام العمل</label><div class="row">${DOW.map((n, i) => `<label style="display:flex;gap:6px;align-items:center;color:var(--ink)"><input type="checkbox" name="d${i}" ${v.work_days.includes(i) ? 'checked' : ''}> ${n}</label>`).join('')}</div></div>
      ${s ? '<div class="wide"><button type="button" class="btn sm danger" id="shdel">حذف الوردية</button></div>' : ''}</div>
      <p class="muted small">إذا كانت نهاية الدوام قبل بدايته فالوردية ليلية تنتهي صباح اليوم التالي. ساعات العمل لا تزيد على 8 يوميا أو 48 أسبوعيا، و6 ساعات في رمضان للمسلمين (م98).</p>`, {
      onOk: async f => { const days = DOW.map((_, i) => i).filter(i => f['d' + i]); if (!(f.name || '').trim()) throw new Error('أدخل اسم الوردية'); if (!days.length) throw new Error('اختر يوم عمل واحدا على الأقل'); if (f.st === f.en) throw new Error('وقت البداية والنهاية متساويان');
        if (!!f.rst !== !!f.ren) throw new Error(tr('أدخل بداية ونهاية دوام رمضان أو اتركهما فارغين'));
        const row = { name: f.name.trim(), name_en: blank((f.name_en || '').trim()), start_time: f.st, end_time: f.en, grace_min: Math.round(+f.g || 0), break_min: Math.round(+f.brk || 0),
          ramadan_start: blank(f.rst), ramadan_end: blank(f.ren), work_days: days, is_default: f.def === 'true' };
        if (row.is_default) { const cur = shifts.find(x => x.is_default && (!s || x.id !== s.id)); if (cur) await db.upd('shifts', { id: 'eq.' + cur.id }, { is_default: false }); }
        if (s) await db.upd('shifts', { id: 'eq.' + s.id }, row); else await db.ins('shifts', Object.assign(row, { company_id: S.cid })); route(); } });
    const hint = () => { const F = $('#mform', d), w = spanMin(F.st.value, F.en.value) - (+F.brk.value || 0), rw = F.rst.value && F.ren.value ? spanMin(F.rst.value, F.ren.value) - (+F.brk.value || 0) : null;
      $('#shh', d).innerHTML = `${esc(tr('ساعات العمل'))}: <b class="num ${w > 480 ? 'bad' : ''}">${r2(w / 60)}</b>${rw != null ? ` · ${esc(tr('في رمضان'))}: <b class="num ${rw > 360 ? 'bad' : ''}">${r2(rw / 60)}</b>` : ''}${w > 300 && (+F.brk.value || 0) < 30 ? ` · <span class="bad">${esc(tr('م101: راحة لا تقل عن نصف ساعة حتى لا يعمل أكثر من 5 ساعات متواصلة'))}</span>` : ''}`; };
    $$('input', $('#mform', d)).forEach(x => x.addEventListener('input', hint)); hint();
    if (s) $('#shdel', d).onclick = async () => { try { await db.del('shifts', { id: 'eq.' + s.id }); d.close(); route(); } catch (e) { showErr($('#merr', d), e); } }; };
  $('#ns', box).onclick = () => siteForm(null); bindRows(stbl, sites, siteForm);
  $('#nsh', box).onclick = () => shiftForm(null); bindRows(shtbl, shifts, shiftForm);
  bindRows(htbl, hols, h => confirmBox('حذف العطلة', h.name + ' — ' + h.day, 'حذف').then(ok => ok && db.del('holidays', { company_id: 'eq.' + S.cid, day: 'eq.' + h.day }).then(route).catch(e => toast(e.message))));
  const dayList = (from, to) => { const out = []; for (let d = new Date(from + 'T12:00:00Z'); d.toISOString().slice(0, 10) <= to && out.length < 15; d = new Date(d.getTime() + 864e5)) out.push(d.toISOString().slice(0, 10)); return out; };
  const nextDay = d => new Date(new Date(d + 'T12:00:00Z').getTime() + 864e5).toISOString().slice(0, 10);
  // Reg. Art. 24(1): a holiday on the weekly rest day is compensated with an equal day before or after the holiday
  const addHolidays = async rows => {
    const have = new Set(hols.map(h => h.day)), fresh = rows.filter(r => !have.has(r.day));
    if (fresh.length) await db.ins('holidays', fresh.map(r => Object.assign({ company_id: S.cid }, r)));
    const def = shifts.find(x => x.is_default), taken = new Set([...have, ...fresh.map(r => r.day)]);
    const onRest = def ? fresh.filter(r => !def.work_days.includes(new Date(r.day + 'T12:00:00Z').getUTCDay())) : [];
    if (!onRest.length) return route();
    let cur = fresh.map(r => r.day).sort().pop(); const sugg = [];
    for (const r of onRest) { do { cur = nextDay(cur); } while (taken.has(cur) || !def.work_days.includes(new Date(cur + 'T12:00:00Z').getUTCDay())); taken.add(cur); sugg.push({ day: cur, name: 'تعويض عن ' + r.name, name_en: 'Compensation for ' + (r.name_en || trTo(r.name)) }); }
    modal('تعويض عن عطلة في يوم الراحة', `<p class="small">وقع ${onRest.length} يوم من العطلة في يوم الراحة الأسبوعية (${onRest.map(r => esc(dayName(r.day)) + ' <span class="num">' + r.day + '</span>').join('، ')}). يعوَّض الموظف عنها بما يعادلها قبل العطلة أو بعدها (م24 من اللائحة التنفيذية).</p>
      <div class="fg">${sugg.map((x, i) => field('يوم التعويض ' + (i + 1), `<input type="date" name="c${i}" value="${x.day}">`)).join('')}</div>
      <p class="muted small">اقترحنا أول أيام عمل بعد العطلة، ويمكنك تغييرها. لا تعويض إذا وافق اليوم الوطني أو يوم التأسيس أحد العيدين.</p>`, {
      ok: 'إضافة أيام التعويض', onOk: async f => { const add = [];
        sugg.forEach((x, i) => { const day = f['c' + i]; if (day && !have.has(day) && !fresh.some(r => r.day === day) && !add.some(a => a.day === day)) add.push({ company_id: S.cid, day, name: x.name, name_en: x.name_en }); });
        if (add.length) await db.ins('holidays', add); } });
    $('#dlg').addEventListener('close', () => route(), { once: true });
  };
  $('#nh', box).onclick = () => modal('عطلة رسمية', `<div class="fg">${field('من', `<input type="date" name="f" value="${rToday()}">`)}${field('إلى', `<input type="date" name="t">`)}${field('الاسم', inp('n', '', 'placeholder="مثال: عيد الفطر"'))}${enF('ne', '', undefined)}</div>
    <p class="muted small">عيد الفطر 4 أيام تبدأ من اليوم التالي لـ29 رمضان، وعيد الأضحى 4 أيام تبدأ من يوم عرفة (م24 من اللائحة التنفيذية).</p>`, {
    onOk: async f => { if ((f.n || '').trim().length < 2) throw new Error('أدخل اسم العطلة'); const to = f.t || f.f; if (to < f.f) throw new Error('تاريخ النهاية قبل البداية');
      setTimeout(() => addHolidays(dayList(f.f, to).map(day => ({ day, name: f.n.trim(), name_en: blank((f.ne || '').trim()) }))).catch(e => toast(e.message)), 0); } });
  $('#nat', box).onclick = () => busy($('#nat', box), async () => { const y = rToday().slice(0, 4);
    await addHolidays([{ day: y + '-02-22', name: 'يوم التأسيس', name_en: 'Founding Day' }, { day: y + '-09-23', name: 'اليوم الوطني', name_en: 'National Day' }]); });
}

/* ===== team leave calendar: who is off when (HR: everyone, manager: own team) ===== */
VIEWS['#/leavecal'] = async (page, arg, q) => {
  if (!isHR() && !has('manager')) { page.innerHTML = '<div class="note">هذه الصفحة للموارد البشرية والمدراء.</div>'; return; }
  const m = /^\d{4}-\d{2}$/.test(q.get('m') || '') ? q.get('m') : today().slice(0, 7);
  const [y, mo] = m.split('-').map(Number), nd = new Date(y, mo, 0).getDate(), ms = m + '-01', me = m + '-' + String(nd).padStart(2, '0');
  const shiftM = (k) => { const d = new Date(y, mo - 1 + k, 1); return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0'); };
  const [em, reqs, hols, shifts, lt] = await Promise.all([employeesMap(true), db.get('requests', { company_id: 'eq.' + S.cid, kind: 'eq.leave', status: 'in.(approved,pending)', from_date: 'lte.' + me, to_date: 'gte.' + ms }),
    db.get('holidays', { company_id: 'eq.' + S.cid, day: 'gte.' + ms }).catch(() => []), db.get('shifts', { company_id: 'eq.' + S.cid, is_default: 'eq.true' }).catch(() => []), LEAVE_TYPES()]);
  const ltn = {}; lt.forEach(l => ltn[l.code] = l.name_ar);
  const team = Object.values(em).filter(e => (isHR() || e.manager_id === S.emp) && e.hire_date <= me && (!e.end_date || e.end_date >= ms));
  const wd = (shifts[0] || {}).work_days || [0, 1, 2, 3, 4];
  const hol = {}; hols.filter(h => h.day <= me).forEach(h => hol[h.day] = h.name);
  const days = Array.from({ length: nd }, (_, i) => { const d = m + '-' + String(i + 1).padStart(2, '0'); return { d, n: i + 1, dow: new Date(d + 'T12:00:00').getDay() }; });
  const cell = (e, d) => reqs.find(r => r.employee_id === e.id && r.from_date <= d && r.to_date >= d);
  const DN = x => new Date(x.d + 'T12:00:00').toLocaleDateString(LANG === 'en' ? 'en-GB' : 'ar-SA', { weekday: 'narrow' });
  const cnt = days.map(x => team.filter(e => cell(e, x.d)).length), lim = Math.max(2, Math.ceil(team.length / 3));
  const ab = d => { const r = cell(d.e, d.x.d); return r ? `<td class="lc ${r.status === 'approved' ? 'on' : 'pend'}" title="${esc((ltn[r.sub] || 'إجازة') + ' · ' + r.from_date + ' → ' + r.to_date + (r.status === 'pending' ? ' · بانتظار الاعتماد' : ''))}"></td>` : `<td class="lc${hol[d.x.d] ? ' hol' : !wd.includes(d.x.dow) ? ' off' : ''}"></td>`; };
  page.innerHTML = `<div class="head"><div><h1>تقويم الإجازات</h1><div class="muted">${isHR() ? 'كل الموظفين' : 'فريقك'} · الإجازات المعتمدة وتحت الاعتماد</div></div>
      <div class="row"><a class="btn sm" href="#/leavecal?m=${shiftM(-1)}">→ السابق</a><b class="num">${m}</b><a class="btn sm" href="#/leavecal?m=${shiftM(1)}">التالي ←</a></div></div>
    ${team.length ? `<div class="tw lcal"><table><thead><tr><th class="lname">الموظف</th>${days.map(x => `<th class="${hol[x.d] ? 'hol' : !wd.includes(x.dow) ? 'off' : ''}" title="${esc(hol[x.d] || '')}"><span class="num">${x.n}</span><br><span class="small muted" data-nt>${DN(x)}</span></th>`).join('')}</tr></thead>
      <tbody>${team.map(e => `<tr><td class="lname">${esc(e.full_name)}</td>${days.map(x => ab({ e, x })).join('')}</tr>`).join('')}</tbody>
      <tfoot><tr><td class="lname">الغائبون</td>${cnt.map(c => `<td class="${c >= lim ? 'bad' : ''}"><span class="num">${c || ''}</span></td>`).join('')}</tr></tfoot></table></div>
      <div class="row small" style="margin-top:10px;gap:14px"><span><i class="lk on"></i> إجازة معتمدة</span><span><i class="lk pend"></i> بانتظار الاعتماد</span><span><i class="lk hol"></i> عطلة رسمية</span><span><i class="lk off"></i> راحة أسبوعية</span><span class="bad">الرقم الأحمر: غياب ثلث الفريق أو أكثر</span></div>`
      : '<div class="note">لا يوجد موظفون في فريقك.</div>'}`;
};
// leave overlap inside the requester's team, shown to whoever decides the request
async function teamOverlap(r) {
  if (r.kind !== 'leave' || !r.from_date || !r._emp) return '';
  const os = await db.get('requests', { company_id: 'eq.' + S.cid, kind: 'eq.leave', status: 'in.(approved,pending)', from_date: 'lte.' + r.to_date, to_date: 'gte.' + r.from_date, employee_id: 'neq.' + r.employee_id }).catch(() => []);
  if (!os.length) return '<p class="small ok">لا أحد من الفريق في إجازة خلال هذه الفترة.</p>';
  const em = await db.get('employees', { id: 'in.(' + [...new Set(os.map(o => o.employee_id))].join(',') + ')', select: 'id,full_name,manager_id,department_id' }).catch(() => []);
  const mates = em.filter(x => (r._emp.manager_id && x.manager_id === r._emp.manager_id) || (r._emp.department_id && x.department_id === r._emp.department_id));
  if (!mates.length) return '<p class="small ok">لا أحد من الفريق في إجازة خلال هذه الفترة.</p>';
  return `<div class="note" style="margin:8px 0"><span>في إجازة خلال نفس الفترة من الفريق:</span> ${mates.map(x => { const o = os.find(z => z.employee_id === x.id); return `<b>${esc(x.full_name)}</b>` + ` <span class="num small">(${o.from_date} → ${o.to_date}${o.status === 'pending' ? '، بانتظار الاعتماد' : ''})</span>`; }).join('، ')}</div>`;
}
