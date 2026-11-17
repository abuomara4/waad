'use strict';
/* ===== «الأهداف والنتائج الرئيسية» (OKRs, 0118) and attendance from fingerprint devices ===== */
const OKR_SCOPE = { company: 'المنشأة', department: 'القسم', employee: 'الموظف' };
const okrPct = k => { const span = n0(k.target) - n0(k.start_value); return span ? Math.max(0, Math.min(1, (n0(k.current) - n0(k.start_value)) / span)) : 0; };
const okrPeriods = () => { const y = +today().slice(0, 4), q = Math.ceil(+today().slice(5, 7) / 3), out = [];
  for (const yy of [y - 1, y, y + 1]) out.push(String(yy), yy + '-H1', yy + '-H2', yy + '-Q1', yy + '-Q2', yy + '-Q3', yy + '-Q4');
  return { list: out, cur: y + '-Q' + q }; };
const okrPeriodName = p => { const m = /^(\d{4})(?:-(Q|H)(\d))?$/.exec(p) || []; return !m[2] ? tr('سنة') + ' ' + m[1] : (m[2] === 'Q' ? tr('الربع') + ' ' + m[3] : tr('النصف') + ' ' + m[3]) + ' — ' + m[1]; };
VIEWS['#/okrs'] = async (page, arg, q) => {
  const P = okrPeriods(), period = q.get('p') || LS.get('waad.okrp') || P.cur; LS.set('waad.okrp', period);
  const [objs, krs, em, deps] = await Promise.all([db.get('okr_objectives', { company_id: 'eq.' + S.cid, period: 'eq.' + period, order: 'scope,created_at' }),
    db.get('okr_key_results', { company_id: 'eq.' + S.cid, order: 'updated_at' }), employeesMap(true), db.get('departments', { company_id: 'eq.' + S.cid, select: 'id,name', order: 'name' }).catch(() => [])]);
  const km = {}; krs.forEach(k => (km[k.objective_id] = km[k.objective_id] || []).push(k));
  const dm = {}; deps.forEach(d => dm[d.id] = d.name);
  const team = Object.values(em).filter(e => (!e.end_date || e.end_date >= today()) && (isHR() || e.manager_id === S.emp));
  const canAdd = isHR() || team.length > 0;
  const mine = o => o.employee_id && o.employee_id === S.emp;
  const manage = o => isHR() || (o.employee_id && em[o.employee_id] && em[o.employee_id].manager_id === S.emp);
  const prog = o => { const ks = km[o.id] || []; return ks.length ? ks.reduce((a, k) => a + okrPct(k), 0) / ks.length : 0; };
  const owner = o => o.scope === 'company' ? (S.company || {}).name || '' : o.scope === 'department' ? dm[o.department_id] || '' : (em[o.employee_id] || {}).full_name || '';
  const bar = p => `<div style="height:8px;background:var(--line);border-radius:4px;overflow:hidden"><i style="display:block;height:100%;width:${Math.round(p * 100)}%;background:${p >= .7 ? 'var(--ok)' : p >= .4 ? 'var(--brand-blue,#217FE1)' : 'var(--wait)'}"></i></div>`;
  const card = o => { const p = prog(o);
    return `<div class="card" style="margin-bottom:12px"><div class="row" style="justify-content:space-between;gap:8px;align-items:flex-start"><div><span class="badge">${esc(tr(OKR_SCOPE[o.scope]))}: ${esc(owner(o))}</span><h3 style="margin:6px 0">${esc(o.title)}</h3></div>
      <div style="min-width:120px;text-align:end"><b class="num">${Math.round(p * 100)}%</b>${manage(o) ? ` <button class="btn sm" data-oe="${o.id}">${esc(tr('تعديل'))}</button>` : ''}</div></div>${bar(p)}
      <div style="margin-top:10px">${(km[o.id] || []).map(k => `<div class="row" style="gap:8px;align-items:center;margin:6px 0;flex-wrap:wrap"><span style="flex:1;min-width:160px">${esc(k.title)}</span>
        <span class="small num">${r2(n0(k.current))} / ${r2(n0(k.target))}${k.unit ? ' ' + esc(k.unit) : ''}</span><span class="num small" style="width:42px">${Math.round(okrPct(k) * 100)}%</span>
        ${manage(o) || mine(o) ? `<button class="btn sm" data-kp="${k.id}">${esc(tr('تحديث'))}</button>` : ''}</div>`).join('') || `<p class="muted small">${esc(tr('لا توجد نتائج رئيسية'))}</p>`}</div></div>`; };
  const groups = [['company', objs.filter(o => o.scope === 'company')], ['department', objs.filter(o => o.scope === 'department')], ['employee', objs.filter(o => o.scope === 'employee')]];
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الأهداف والنتائج الرئيسية (OKRs)'))}</h1><div class="muted">${esc(tr('هدف واضح وثلاث إلى خمس نتائج قابلة للقياس لكل فترة، ويرى الجميع تقدم أهداف المنشأة والأقسام.'))}</div></div>
      <div class="row" style="gap:6px"><select id="okp" style="width:auto">${P.list.map(p => opt(p, okrPeriodName(p), period)).join('')}</select>${canAdd ? `<button class="btn pri" id="okn">${esc(tr('هدف جديد'))}</button>` : ''}</div></div>
    ${objs.length ? groups.filter(g => g[1].length).map(([k, xs]) => `<h2>${esc(tr({ company: 'أهداف المنشأة', department: 'أهداف الأقسام', employee: 'أهداف الموظفين' }[k]))}</h2>` + xs.map(card).join('')).join('')
      : `<div class="card"><p class="muted">${esc(tr('لا توجد أهداف لهذه الفترة بعد.'))}</p></div>`}`;
  $('#okp', page).onchange = e => { location.hash = '#/okrs?p=' + e.target.value; };
  const form = o => { const ks = o ? (km[o.id] || []) : [];
    const krRow = (k, i) => `<tr><td><input data-k="t" value="${esc(k ? k.title : '')}" maxlength="200" aria-label="${esc(tr('النتيجة'))} ${i + 1}" style="min-width:180px"></td><td><input data-k="s" type="number" step="0.01" value="${k ? n0(k.start_value) : 0}" style="width:80px"></td>
      <td><input data-k="g" type="number" step="0.01" value="${k ? n0(k.target) : ''}" style="width:90px"></td><td><input data-k="u" value="${esc(k ? k.unit || '' : '')}" maxlength="20" style="width:70px"></td><td><input type="hidden" data-k="id" value="${k ? k.id : ''}"></td></tr>`;
    const d = modal(o ? tr('تعديل الهدف') : tr('هدف جديد'), `<div class="fg">${field('الهدف', inp('t', o && o.title, 'maxlength="200" required'), 'wide')}
        ${field('الفترة', `<select name="p">${P.list.map(p => opt(p, okrPeriodName(p), o ? o.period : period)).join('')}</select>`)}
        ${field('لمن', `<select name="sc">${(isHR() ? ['company', 'department', 'employee'] : ['employee']).map(s => opt(s, tr(OKR_SCOPE[s]), o ? o.scope : (isHR() ? 'company' : 'employee'))).join('')}</select>`)}
        <div data-s="department">${field('القسم', `<select name="dep">${deps.map(x => opt(x.id, x.name, o && o.department_id)).join('')}</select>`)}</div>
        <div data-s="employee">${field('الموظف', `<select name="emp">${team.map(e => opt(e.id, e.full_name, o && o.employee_id)).join('')}</select>`)}</div>
        <div class="wide"><label>${esc(tr('النتائج الرئيسية (من 1 إلى 5)'))}</label><div class="tw"><table class="lines"><thead><tr><th>${esc(tr('النتيجة'))}</th><th>${esc(tr('من'))}</th><th>${esc(tr('المستهدف'))}</th><th>${esc(tr('الوحدة'))}</th><th></th></tr></thead>
          <tbody id="okk">${[0, 1, 2, 3, 4].map(i => krRow(ks[i], i)).join('')}</tbody></table></div></div>
        ${o ? `<div class="wide"><button type="button" class="btn danger sm" id="okdel">${esc(tr('حذف الهدف'))}</button></div>` : ''}</div>`, {
      wide: true, onOk: async f => {
        const rows = $$('#okk tr').map(tr => ({ id: $('[data-k=id]', tr).value, title: $('[data-k=t]', tr).value.trim(), start_value: +$('[data-k=s]', tr).value || 0, target: $('[data-k=g]', tr).value, unit: $('[data-k=u]', tr).value.trim() || null }));
        const use = rows.filter(r => r.title); if (!use.length) throw new Error(tr('أضف نتيجة رئيسية واحدة على الأقل'));
        if (use.some(r => r.target === '' || +r.target === r.start_value)) throw new Error(tr('المستهدف مطلوب ويختلف عن نقطة البداية'));
        const row = { title: f.t.trim(), period: f.p, scope: f.sc, department_id: f.sc === 'department' ? f.dep : null, employee_id: f.sc === 'employee' ? f.emp : null };
        let oid = o && o.id;
        if (oid) await db.upd('okr_objectives', { id: 'eq.' + oid }, row); else { const [n] = await db.ins('okr_objectives', Object.assign(row, { company_id: S.cid })); oid = n.id; }
        for (const r of rows) { const v = { title: r.title, start_value: r.start_value, target: +r.target, unit: r.unit };
          if (r.id && !r.title) await db.del('okr_key_results', { id: 'eq.' + r.id });
          else if (r.id) await db.upd('okr_key_results', { id: 'eq.' + r.id }, v);
          else if (r.title) await db.ins('okr_key_results', Object.assign(v, { company_id: S.cid, objective_id: oid, current: r.start_value })); }
        toast(tr('تم الحفظ')); route(); } });
    const sync = () => { const sc = d.querySelector('[name=sc]').value; $$('[data-s]', d).forEach(x => x.hidden = x.dataset.s !== sc); };
    d.querySelector('[name=sc]').onchange = sync; sync();
    if ($('#okdel', d)) $('#okdel', d).onclick = async () => { if (!await confirmBox(tr('حذف الهدف'), tr('يُحذف الهدف ونتائجه الرئيسية.'), tr('حذف'))) return; await db.del('okr_objectives', { id: 'eq.' + o.id }); toast(tr('حُذف')); route(); };
  };
  if ($('#okn', page)) $('#okn', page).onclick = () => form(null);
  $$('[data-oe]', page).forEach(b => b.onclick = () => form(objs.find(o => o.id === b.dataset.oe)));
  $$('[data-kp]', page).forEach(b => b.onclick = () => { const k = krs.find(x => x.id === b.dataset.kp);
    modal(tr('تحديث التقدم'), `<p>${esc(k.title)}</p>${field('القيمة الحالية', inp('v', n0(k.current), 'type="number" step="0.01" required'))}<p class="muted small">${esc(tr('من'))} <span class="num">${r2(n0(k.start_value))}</span> ${esc(tr('إلى'))} <span class="num">${r2(n0(k.target))}</span>${k.unit ? ' ' + esc(k.unit) : ''}</p>`,
      { onOk: async f => { await db.rpc('okr_progress', { p_kr: k.id, p_value: +f.v }); toast(tr('تم الحفظ')); route(); } }); });
};

/* ---------- fingerprint devices: import the punch log, export the employee list for enrolling ---------- */
// the file: ZKTeco «attlog» (.dat/.txt: number, date time, ...) or an Excel/CSV report with an employee number and date/time columns
function devParse(rows) {
  const isHead = r => r.some(v => /no|id|رقم|الرقم|date|time|التاريخ|الوقت|الموظف/i.test(String(v || '')));
  let hi = rows.findIndex(r => r && r.length >= 2 && isHead(r)), cId = 0, cDT = 1, cD = -1, cT = -1;
  if (hi >= 0) { const h = rows[hi].map(v => String(v || '').trim().toLowerCase());
    const find = re => h.findIndex(x => re.test(x));
    cId = find(/^(ac-?no\.?|no\.?|id|user ?id|emp(loyee)? ?(no|id|number)|person ?id|enroll ?(no|id)|الرقم الوظيفي|رقم الموظف|الرقم|رقم)$/);
    cDT = find(/date ?\/? ?time|datetime|التاريخ والوقت|وقت البصمة|check ?time|punch ?time/);
    if (cDT < 0) { cD = find(/^(date|التاريخ|اليوم)$/); cT = find(/^(time|الوقت|الساعة)$/); }
    if (cId < 0) cId = 0;
  } else hi = -1;
  const out = [];
  for (const r of rows.slice(hi + 1)) { if (!r || r.length < 2) continue;
    const no = String(r[cId] == null ? '' : r[cId]).trim().replace(/\.0+$/, ''); if (!no) continue;
    let s = cDT >= 0 ? String(r[cDT] || '') : (cD >= 0 ? String(r[cD] || '') + ' ' + String(cT >= 0 ? r[cT] || '' : '') : '');
    if (!s.trim() && hi < 0) s = r.slice(1, 3).join(' ');
    let m = /(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})[ T]+(\d{1,2}):(\d{2})/.exec(s) || null, day, tm;
    if (m) { day = `${m[1]}-${m[2].padStart(2, '0')}-${m[3].padStart(2, '0')}`; tm = `${m[4].padStart(2, '0')}:${m[5]}`; }
    else if ((m = /(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})[ T]+(\d{1,2}):(\d{2})/.exec(s))) { day = `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`; tm = `${m[4].padStart(2, '0')}:${m[5]}`; }
    else continue;
    out.push({ no, day, tm }); }
  return out;
}
async function devImport() {
  const d = modal(tr('استيراد من جهاز البصمة'), `<ol class="small" style="padding-inline-start:18px;margin-top:0">
      <li>${esc(tr('من برنامج الجهاز أو ذاكرة USB صدّر سجل البصمات (مثل ملف attlog.dat من أجهزة ZKTeco، أو تقرير Excel/CSV فيه الرقم والتاريخ والوقت).'))}</li>
      <li>${esc(tr('رقم المستخدم في الجهاز يجب أن يساوي الرقم الوظيفي في وعد.'))}</li>
      <li>${esc(tr('أول بصمة في اليوم حضور، وآخر بصمة انصراف، ويُحسب التأخير والإضافي تلقائيا.'))}</li></ol>
    <div class="row"><label class="btn pri" style="margin:0;color:var(--prim-ink)">${esc(tr('اختيار الملف'))}<input type="file" id="devf" accept=".dat,.txt,.csv,.xlsx" hidden></label><button type="button" class="btn" id="devx">${esc(tr('تنزيل قائمة الموظفين للجهاز'))}</button></div><div id="devp"></div>`, { wide: true });
  $('#devx', d).onclick = async () => { const em = Object.values(await employeesMap(true)).filter(e => !e.end_date || e.end_date >= today());
    const csv = '﻿' + [['No', 'Name'], ...em.map(e => [e.emp_no, (e.full_name_en || e.full_name || '').replace(/,/g, ' ')])].map(r => r.join(',')).join('\r\n');
    const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' })); a.download = 'waad-employees-for-device.csv'; a.click(); };
  $('#devf', d).onchange = async ev => { const file = ev.target.files[0]; if (!file) return; const box = $('#devp', d);
    let rows;
    if (/\.(dat|txt)$/i.test(file.name)) rows = (await file.text()).split(/\r?\n/).map(l => { const m = /^\s*([^\s,]+)[\s,]+(\d{4}-\d{1,2}-\d{1,2})[\sT,]+(\d{1,2}:\d{2})/.exec(l); return m ? [m[1], m[2] + ' ' + m[3]] : null; }).filter(Boolean);
    else { const sf = await readSheetFile(file); rows = [sf.hdr, ...sf.body.map(x => x.r)]; }
    const punches = devParse(rows); if (!punches.length) { box.innerHTML = `<div class="err">${esc(tr('لم نجد بصمات في الملف: تأكد أن فيه رقم الموظف والتاريخ والوقت.'))}</div>`; return; }
    const g = {}; punches.forEach(p => { const k = p.no + '|' + p.day; (g[k] = g[k] || []).push(p.tm); });
    const days = Object.entries(g).map(([k, ts]) => { const [no, day] = k.split('|'); ts.sort(); return { no, day, in: ts[0], out: ts.length > 1 ? ts[ts.length - 1] : null }; }).filter(x => x.day <= today());
    const nos = new Set(days.map(x => x.no)), dr = days.map(x => x.day).sort();
    box.innerHTML = `<div class="note" style="margin-top:10px">${esc(tr('بصمات'))}: <b class="num">${punches.length}</b> · ${esc(tr('أيام حضور'))}: <b class="num">${days.length}</b> · ${esc(tr('موظفون'))}: <b class="num">${nos.size}</b> · <span class="num">${dr[0] || ''} → ${dr[dr.length - 1] || ''}</span></div>
      <p class="muted small">${esc(tr('الأيام المستوردة تحل محل ما سُجل لنفس الموظف في نفس اليوم.'))}</p><button type="button" class="btn pri" id="devgo">${esc(tr('استيراد'))}</button>`;
    $('#devgo', d).onclick = () => busy($('#devgo', d), async () => {
      let done = 0, failed = 0; const unknown = new Set();
      for (let i = 0; i < days.length; i += 500) { const r = await db.rpc('att_import', { p_company: S.cid, p_rows: days.slice(i, i + 500) }); done += r.days; failed += r.failed; (r.unknown || []).forEach(u => unknown.add(u)); }
      box.innerHTML = `<div class="note">${esc(tr('استُورد'))}: <b class="num">${done}</b> ${esc(tr('يوم'))}${failed ? ` · ${esc(tr('تعذّر'))}: <b class="num">${failed}</b>` : ''}${unknown.size ? `<br>${esc(tr('أرقام في الجهاز لا تطابق رقما وظيفيا'))}: <span class="num">${[...unknown].slice(0, 30).map(esc).join('، ')}</span>` : ''}</div>`;
      toast(tr('تم الاستيراد')); });
  };
}
