'use strict';
/* ===== HR dashboard, weekly shift roster, bulk raise, policies, leave statement ===== */

// small inline SVG bar chart (no library): bars = [{ label, values: [..] }], series = [{ name, color }]
// compact number for axis ticks: 2,500,000 -> 2.5M, 340000 -> 340K (plain LTR number, no currency)
const kfmt = v => { const a = Math.abs(n0(v)); return a >= 1e6 ? r2(v / 1e6) + 'M' : a >= 1e3 ? Math.round(v / 1e3) + 'K' : String(r2(v)); };
function barChart(bars, series, { h = 160, fmt = v => String(v) } = {}) {
  const max = Math.max(1, ...bars.flatMap(b => b.values.map(n0)));
  const W = 640, pad = 40, base = h - 18, plot = h - 34, gw = (W - pad) / Math.max(1, bars.length), bw = Math.max(4, (gw - 8) / series.length);
  // recessive gridlines at 0/50/100% of max, each labelled compactly, so bar heights read as real magnitudes
  const grid = [0, .5, 1].map(f => { const y = base - f * plot;
    return `<line x1="${pad}" y1="${y.toFixed(1)}" x2="${W}" y2="${y.toFixed(1)}" stroke="var(--line)" stroke-width="${f === 0 ? 1 : .5}" ${f ? 'stroke-dasharray="3 3"' : ''}/><text x="${pad - 4}" y="${(y + 3).toFixed(1)}" text-anchor="end" font-size="9" fill="var(--muted)">${esc(kfmt(max * f))}</text>`; }).join('');
  const rects = bars.map((b, i) => b.values.map((v, k) => { const bh = Math.round((n0(v) / max) * plot); const x = pad + i * gw + 4 + k * bw, y = base - bh;
    return `<rect x="${x.toFixed(1)}" y="${y}" width="${(bw - 2).toFixed(1)}" height="${bh}" rx="2" fill="${series[k].color}"><title>${esc(b.label)} — ${esc(tr(series[k].name))}: ${esc(fmt(v))}</title></rect>`; }).join('')
    + `<text x="${(pad + i * gw + gw / 2).toFixed(1)}" y="${h - 4}" text-anchor="middle" font-size="10" fill="var(--muted)">${esc(b.label)}</text>`).join('');
  return `<svg viewBox="0 0 ${W} ${h}" class="chart" role="img" style="width:100%;height:auto;direction:ltr">${grid}${rects}</svg>
    <div class="row small" style="gap:12px">${series.map(s => `<span><span style="display:inline-block;width:10px;height:10px;border-radius:2px;background:${s.color}"></span> ${esc(tr(s.name))}</span>`).join('')}</div>`;
}
const hbars = (rows, fmt = v => String(v)) => { const max = Math.max(1, ...rows.map(r => n0(r.v)));
  return rows.map(r => `<div class="row small" style="gap:8px;margin:4px 0;align-items:center"><span style="min-width:120px">${esc(r.label)}</span>
    <span style="flex:1;background:var(--soft);border-radius:4px;height:12px;position:relative"><span style="position:absolute;inset:0;inset-inline-end:auto;width:${(n0(r.v) / max * 100).toFixed(1)}%;background:var(--accent);border-radius:4px"></span></span>
    <b class="num" style="min-width:40px;text-align:end">${esc(fmt(r.v))}</b></div>`).join(''); };

// tiny inline trend line (no axes/labels) shown next to a headline number — the guide's "indicator line / sparkline"
const sparkline = (vals, color = 'var(--accent)') => { const v = (vals || []).map(n0); if (v.length < 2) return '';
  const W = 76, H = 22, p = 2, mn = Math.min(...v), mx = Math.max(...v), rng = mx - mn || 1;
  const xs = i => p + i * (W - 2 * p) / (v.length - 1), ys = x => H - p - (x - mn) / rng * (H - 2 * p);
  const pts = v.map((x, i) => `${xs(i).toFixed(1)},${ys(x).toFixed(1)}`).join(' '), lx = xs(v.length - 1).toFixed(1), ly = ys(v[v.length - 1]).toFixed(1);
  return `<svg viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" class="spark" preserveAspectRatio="none" style="direction:ltr;overflow:visible" aria-hidden="true"><polyline points="${pts}" fill="none" stroke="${color}" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><circle cx="${lx}" cy="${ly}" r="2.1" fill="${color}"/></svg>`; };

// bullet bar: a measure against a target line — the guide's way to compare one value to a benchmark
function bullet(value, target, { max, fmt = v => String(v), good } = {}) {
  const v = Math.max(0, n0(value)), t = Math.max(0, n0(target)), m = max || Math.max(v, t) * 1.4 || 1;
  const pv = Math.min(100, v / m * 100), pt = Math.min(100, t / m * 100);
  const col = good === false ? 'var(--bad)' : good ? 'var(--ok)' : 'var(--accent)';
  return `<div style="position:relative;height:14px;background:var(--soft);border-radius:4px;margin:4px 0" title="${esc(tr('الهدف'))}: ${esc(fmt(t))}">
    <div style="position:absolute;inset:0;inset-inline-end:auto;width:${pv.toFixed(1)}%;background:${col};border-radius:4px"></div>
    <div style="position:absolute;top:-3px;height:20px;width:2px;background:var(--ink);inset-inline-start:${pt.toFixed(1)}%"></div></div>`;
}

// donut for genuine part-to-whole: top 5 slices, the rest folded into "أخرى"; legend carries label + value + %
const DONUT_C = ['#3b82f6', '#c9a35c', '#ef4444', '#3fc392', '#8b5cf6'];
function donut(rows, fmt = v => String(v)) {
  const all = (rows || []).map(r => ({ label: r.label, v: Math.max(0, n0(r.v)) })).filter(r => r.v > 0).sort((a, b) => b.v - a.v);
  const total = all.reduce((a, r) => a + r.v, 0);
  if (!total) return `<p class="muted small">${esc(tr('لا توجد بيانات'))}</p>`;
  const segs = all.length > 6 ? [...all.slice(0, 5), { label: tr('أخرى'), v: all.slice(5).reduce((a, r) => a + r.v, 0) }] : all;
  const R = 54, sw = 20, C = 2 * Math.PI * R, cx = 70, cy = 70; let off = 0;
  const gap = segs.length > 1 ? 2 : 0;   // 2px surface gap between slices
  const arcs = segs.map((s, i) => { const col = DONUT_C[i] || '#94a3b8', len = s.v / total * C, dash = Math.max(0.5, len - gap), o = off; off += len;
    return `<circle cx="${cx}" cy="${cy}" r="${R}" fill="none" stroke="${col}" stroke-width="${sw}" stroke-dasharray="${dash.toFixed(2)} ${(C - dash).toFixed(2)}" stroke-dashoffset="${(-o).toFixed(2)}" transform="rotate(-90 ${cx} ${cy})"><title>${esc(s.label)}: ${esc(fmt(s.v))} (${r2(s.v / total * 100)}%)</title></circle>`; }).join('');
  const legend = segs.map((s, i) => `<div class="row small" style="gap:6px;margin:2px 0;align-items:center"><span style="flex:none;width:10px;height:10px;border-radius:2px;background:${DONUT_C[i] || '#94a3b8'}"></span><span style="flex:1">${esc(s.label)}</span><b class="num">${esc(fmt(s.v))}</b><span class="muted num" style="min-width:42px;text-align:end">${r2(s.v / total * 100)}%</span></div>`).join('');
  return `<div class="row" style="gap:12px;align-items:center;flex-wrap:wrap"><svg viewBox="0 0 140 140" width="140" height="140" style="flex:none;direction:ltr" role="img">${arcs}<text x="70" y="66" text-anchor="middle" font-size="22" font-weight="700" fill="var(--ink)">${esc(fmt(total))}</text><text x="70" y="84" text-anchor="middle" font-size="11" fill="var(--muted)">${esc(tr('الإجمالي'))}</text></svg><div style="flex:1;min-width:150px">${legend}</div></div>`;
}

VIEWS['#/hrdash'] = async page => {
  if (!(isHR() || has('finance'))) { page.innerHTML = '<div class="note">هذه الصفحة للموارد البشرية والمالية.</div>'; return; }
  const d = await db.rpc('hr_dashboard', { p_company: S.cid });
  const nm = x => (LANG === 'en' && x.name_en) || x.name;
  const pend = Object.values(d.pending || {}).reduce((a, n) => a + n0(n), 0), t = d.today || {};
  const kpi = (label, v, href, cls = '') => `<a class="card kpi" ${href ? `href="${href}"` : ''}><div class="muted small">${esc(tr(label))}</div><div class="v num ${cls}">${v}</div></a>`;
  const att = (list, cols) => list.length ? tbl(cols, list) : `<p class="muted small">${esc(tr('لا شيء'))}</p>`;
  const last = (d.payroll || []).slice(-1)[0];
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('لوحة الموارد البشرية'))}</h1><div class="muted">${esc(S.company.name)} · ${fdate(today())}</div></div>
      <div class="row"><button class="btn" id="dprn">${esc(tr('طباعة'))}</button></div></div>
    <div id="dsh"><div class="grid">
      ${kpi('على رأس العمل', d.active, '#/employees')}${kpi('السعوديون', `${d.saudi} <span class="small muted">(${d.active ? r2(d.saudi / d.active * 100) : 0}%)</span>`, '#/nitaqat')}
      ${kpi('حاضرون اليوم', `${n0(t.present)} / ${n0(t.expected)}`, '#/att', n0(t.present) < n0(t.expected) ? 'bad' : '')}${kpi('متأخرون اليوم', n0(t.late), '#/att', t.late ? 'bad' : '')}
      ${kpi('في إجازة اليوم', n0(t.leave), '#/leavecal')}${kpi('طلبات بانتظار الاعتماد', pend, '#/approvals', pend ? 'bad' : '')}
      ${kpi('معدل الدوران (12 شهراً)', `${d.turnover}%`, null)}${kpi('تحت التجربة', d.probation, '#/docs')}
      ${d.docs30 != null ? kpi('مستندات وعقود تنتهي خلال 30 يوماً', d.docs30, '#/docs', d.docs30 ? 'bad' : '') : ''}${kpi('إخلاء طرف غير مكتمل', d.clearance_open, '#/clearance', d.clearance_open ? 'bad' : '')}
      ${kpi('إقرارات سياسات ناقصة', d.policies_unacked, '#/policies', d.policies_unacked ? 'bad' : '')}${last ? kpi('تكلفة آخر مسير', money(n0(last.gross) + n0(last.employer_gosi)), '#/payroll') : ''}</div>
    <div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(320px,1fr))">
      <div class="card"><h2>${esc(tr('عدد الموظفين والحركة — 12 شهراً'))}</h2>${barChart(d.months.map(m => ({ label: m.m.slice(5), values: [m.hc, m.joins, m.leaves] })), [{ name: 'العدد نهاية الشهر', color: '#2563eb' }, { name: 'منضمون', color: '#16a34a' }, { name: 'مغادرون', color: '#dc2626' }])}</div>
      <div class="card"><h2>${esc(tr('الموظفون حسب القسم'))}</h2>${hbars(d.by_dept.map(x => ({ label: x.name === '—' ? tr('بلا قسم') : nm(x), v: x.n })))}</div>
      <div class="card"><h2>${esc(tr('تكلفة الرواتب — آخر 6 مسيرات'))}</h2>${(d.payroll || []).length ? barChart(d.payroll.map(p => ({ label: p.p.slice(2), values: [p.gross, p.net, p.employer_gosi] })), [{ name: 'الإجمالي', color: '#2563eb' }, { name: 'الصافي', color: '#16a34a' }, { name: 'تأمينات المنشأة', color: '#f59e0b' }], { fmt: money }) : `<p class="muted small">${esc(tr('لا توجد مسيرات'))}</p>`}</div>
      <div class="card"><h2>${esc(tr('أرصدة إجازات متراكمة (أكثر من 30 يوماً)'))}</h2>${att(d.leave_high, [{ t: 'الموظف', h: x => esc(nm(x)) }, { t: 'الرصيد', r: 1, h: x => `<b class="num">${Math.floor(x.days)}</b>` }])}</div>
      <div class="card"><h2>${esc(tr('عمل إضافي قريب من 720 ساعة'))}</h2>${att(d.ot_near_cap, [{ t: 'الموظف', h: x => esc(nm(x)) }, { t: 'الساعات هذه السنة', r: 1, h: x => `<b class="num ${x.hours >= 720 ? 'bad' : ''}">${x.hours}</b>` }])}</div>
      <div class="card"><h2>${esc(tr('ساعات تعويضية تنتهي خلال 14 يوماً'))}</h2>${att(d.comp_expiring, [{ t: 'الموظف', h: x => esc(nm(x)) }, { t: 'الرصيد', r: 1, h: x => `<span class="num">${r2(x.hours)}</span>` }, { t: 'تنتهي', h: x => fdate(x.use_by) }])}</div>
    </div></div>`;
  $('#dprn', page).onclick = () => printBlock($('#dsh', page), tr('لوحة الموارد البشرية'));
};

/* ----- weekly roster ----- */
const addDaysU = (d, n) => new Date(new Date(d + 'T12:00:00Z').getTime() + n * 864e5).toISOString().slice(0, 10);
const weekStart = d => { const x = new Date(d + 'T12:00:00Z'); return addDaysU(d, -x.getUTCDay()); };   // weeks start on Sunday
VIEWS['#/roster'] = async (page, arg, q) => {
  if (!isHR()) { page.innerHTML = '<div class="note">هذه الصفحة للموارد البشرية.</div>'; return; }
  const p = new URLSearchParams(location.hash.split('?')[1] || ''), ws = weekStart(p.get('w') || today()), dep = p.get('d') || '', we = addDaysU(ws, 6);
  const [shifts, deps, em] = await Promise.all([db.get('shifts', { company_id: 'eq.' + S.cid, order: 'start_time' }), db.get('departments', { company_id: 'eq.' + S.cid, order: 'name' }), employeesMap(true)]);
  const emps = Object.values(em).filter(e => (!e.end_date || e.end_date >= ws) && e.hire_date <= we && !e.att_exempt && (!dep || e.department_id === dep)).sort((a, b) => String(a.emp_no).localeCompare(String(b.emp_no)));
  const ros = emps.length ? (await db.get('shift_roster', { company_id: 'eq.' + S.cid, day: 'gte.' + ws })).filter(r => r.day <= we) : [];
  const rm = {}; ros.forEach(r => rm[r.employee_id + r.day] = r);
  const sm = {}; shifts.forEach(s => sm[s.id] = s); const dm = {}; deps.forEach(x => dm[x.id] = x);
  const def = shifts.find(s => s.is_default), base = e => e.shift_id && sm[e.shift_id] || (e.department_id && dm[e.department_id] && sm[dm[e.department_id].shift_id]) || def;
  const days = [...Array(7)].map((_, i) => addDaysU(ws, i));
  const cell = (e, d) => { const r = rm[e.id + d]; const dow = new Date(d + 'T12:00:00Z').getUTCDay();
    if (r) return r.off ? `<span class="badge">${esc(tr('راحة'))}</span>` : `<span class="badge info">${esc(sm[r.shift_id] ? sm[r.shift_id].name : '?')}</span>`;
    const b = base(e); return b && b.work_days.includes(dow) ? `<span class="muted small">${esc(b.name)}</span>` : `<span class="muted small">${esc(tr('راحة'))}</span>`; };
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('جدول الورديات'))}</h1><div class="muted">${esc(tr('الأسبوع'))} ${fdate(ws)} – ${fdate(we)}</div></div>
      <div class="row"><a class="btn" href="#/roster?w=${addDaysU(ws, -7)}${dep ? '&d=' + dep : ''}">→</a><a class="btn" href="#/roster?w=${today()}${dep ? '&d=' + dep : ''}">${esc(tr('هذا الأسبوع'))}</a><a class="btn" href="#/roster?w=${addDaysU(ws, 7)}${dep ? '&d=' + dep : ''}">←</a>
      <select id="rdep" style="width:auto"><option value="">${esc(tr('كل الأقسام'))}</option>${deps.map(x => opt(x.id, x.name, dep)).join('')}</select>
      <button class="btn pri" id="rnew">${esc(tr('تعيين جدول'))}</button></div></div>
    <div class="card"><div class="tw"><table><thead><tr><th>${esc(tr('الموظف'))}</th>${days.map(d => `<th>${esc(dayName(d))}<br><span class="num small muted">${d.slice(5)}</span></th>`).join('')}</tr></thead><tbody>
      ${emps.map(e => `<tr><td>${esc(e.full_name)} <span class="muted num small">${esc(e.emp_no)}</span></td>${days.map(d => `<td data-rc="${e.id}|${d}" style="cursor:pointer">${cell(e, d)}</td>`).join('')}</tr>`).join('') || `<tr><td colspan="8" class="muted">${esc(tr('لا يوجد موظفون'))}</td></tr>`}
    </tbody></table></div><p class="muted small">${esc(tr('الخلايا الملونة من الجدول، والرمادية من وردية الموظف أو قسمه أو الافتراضية. اضغط على أي يوم لتغييره.'))}</p></div>`;
  $('#rdep', page).onchange = ev => location.hash = '#/roster?w=' + ws + (ev.target.value ? '&d=' + ev.target.value : '');
  const shOpts = sel => `<option value="">${esc(tr('راحة'))}</option>${shifts.map(s => opt(s.id, s.name + ' (' + s.start_time.slice(0, 5) + '–' + s.end_time.slice(0, 5) + ')', sel)).join('')}`;
  $$('[data-rc]', page).forEach(c => c.onclick = () => { const [eid, d] = c.dataset.rc.split('|'), r = rm[eid + d];
    const dl = modal(em[eid].full_name + ' — ' + fdate(d), `${field('الوردية', `<select name="sh">${shOpts(r ? r.shift_id || '' : (base(em[eid]) || {}).id)}</select>`)}${r ? `<button type="button" class="btn sm" id="rcl">${esc(tr('إلغاء التعديل والرجوع للوردية المعتادة'))}</button>` : ''}`, {
      onOk: async f => { await db.rpc('roster_assign', { p_company: S.cid, p_emps: [eid], p_from: d, p_to: d, p_shifts: [blank(f.sh)], p_every: 1 }); route(); } });
    if ($('#rcl', dl)) $('#rcl', dl).onclick = async () => { try { await db.rpc('roster_clear', { p_company: S.cid, p_emps: [eid], p_from: d, p_to: d }); dl.close(); route(); } catch (er) { toast(er.message); } }; });
  $('#rnew', page).onclick = () => {
    const list = Object.values(em).filter(e => !e.end_date || e.end_date >= today()).sort((a, b) => String(a.emp_no).localeCompare(String(b.emp_no)));
    const dl = modal(tr('تعيين جدول ورديات'), `<div class="fg">
      ${field('القسم', `<select id="rsd"><option value="">${esc(tr('اختيار يدوي'))}</option>${deps.map(x => opt(x.id, x.name, dep)).join('')}</select>`)}
      ${field('من', `<input type="date" name="from" value="${ws}">`)}${field('إلى', `<input type="date" name="to" value="${addDaysU(ws, 27)}">`)}
      ${field('تتبدل كل (أيام)', `<input type="number" name="every" min="1" max="31" value="7">`)}
      <div class="wide"><label>${esc(tr('الورديات بالترتيب (تتكرر)'))}</label><div class="row">${[0, 1, 2, 3].map(i => `<select name="s${i}" style="width:auto">${i ? `<option value="-">—</option>` : ''}${shOpts(i ? '-' : (shifts[0] || {}).id)}</select>`).join('')}</div></div>
      <div class="wide"><label>${esc(tr('الموظفون'))}</label><div id="rse" style="max-height:220px;overflow:auto;border:1px solid var(--line);border-radius:8px;padding:6px">${list.map(e => `<label class="row small" style="gap:6px"><input type="checkbox" name="e_${e.id}" data-dep="${e.department_id || ''}" ${dep && e.department_id === dep ? 'checked' : ''}> ${esc(e.full_name)} <span class="muted num">${esc(e.emp_no)}</span></label>`).join('')}</div></div></div>
      <p class="muted small">${esc(tr('مثال: ورديتان مع التبدل كل 7 أيام = أسبوع على الأولى وأسبوع على الثانية. اختر «راحة» ليوم أو فترة راحة ضمن التدوير.'))}</p>`, { wide: true, ok: 'تطبيق',
      onOk: async f => { const emps2 = list.filter(e => f['e_' + e.id]).map(e => e.id), sh = [0, 1, 2, 3].map(i => f['s' + i]).filter(v => v !== '-' && v !== undefined).map(v => blank(v));
        if (!emps2.length) throw new Error(tr('اختر موظفاً واحداً على الأقل'));
        const n = await db.rpc('roster_assign', { p_company: S.cid, p_emps: emps2, p_from: f.from, p_to: f.to, p_shifts: sh, p_every: +f.every || 7 }); toast(tr('تم تعيين') + ' ' + n + ' ' + tr('يوم')); route(); } });
    $('#rsd', dl).onchange = ev => $$('#rse input', dl).forEach(x => x.checked = !!ev.target.value && x.dataset.dep === ev.target.value);
  };
};

/* ----- bulk raise ----- */
async function bulkRaiseDialog() {
  const [em, deps] = await Promise.all([employeesMap(true), db.get('departments', { company_id: 'eq.' + S.cid, order: 'name' })]);
  const list = Object.values(em).filter(e => !e.end_date || e.end_date >= today()).sort((a, b) => String(a.emp_no).localeCompare(String(b.emp_no)));
  const d = modal(tr('زيادة جماعية للرواتب'), `<div class="fg">
    ${field('القسم', `<select id="brd"><option value="">${esc(tr('الكل'))}</option>${deps.map(x => opt(x.id, x.name)).join('')}</select>`)}
    ${field('نسبة الزيادة على الأساسي %', '<input name="pct" type="number" step="0.1" min="0" max="100" value="5">')}${field('أو مبلغ ثابت يضاف للأساسي', '<input name="amt" type="number" step="1" min="0" value="0">')}
    ${field('بدل السكن', `<select name="hs">${opt('true', tr('يزيد بنفس النسبة'))}${opt('false', tr('لا يتغير'))}</select>`)}
    ${field('تاريخ السريان', `<input type="date" name="eff" value="${today()}" max="${today()}">`)}${field('السبب', inp('why', tr('الزيادة السنوية'), 'required'), 'wide')}
    <div class="wide"><div id="bre" style="max-height:220px;overflow:auto;border:1px solid var(--line);border-radius:8px;padding:6px">${list.map(e => `<label class="row small" style="gap:6px"><input type="checkbox" name="e_${e.id}" data-dep="${e.department_id || ''}" checked> ${esc(e.full_name)} <span class="muted num">${money(e.basic)}</span></label>`).join('')}</div></div>
    <div class="wide"><p class="small" id="brp" style="margin:0"></p></div></div>
    <p class="muted small">${esc(tr('الزيادة لا تحتاج موافقة العامل وتُسجّل في سجل الأجور. التخفيض لا يكون جماعياً — يحتاج موافقة كل عامل كتابياً.'))}</p>`, { wide: true, ok: 'تطبيق الزيادة',
    onOk: async f => { const ids = list.filter(e => f['e_' + e.id]).map(e => e.id); if (!ids.length) throw new Error(tr('اختر موظفاً واحداً على الأقل'));
      const n = await db.rpc('salary_raise_bulk', { p_company: S.cid, p_emps: ids, p_pct: +f.pct || 0, p_amount: +f.amt || 0, p_housing: f.hs === 'true', p_effective: f.eff, p_reason: f.why });
      cache.emps = null; toast(tr('زيدت رواتب') + ' ' + n); route(); } });
  const F = $('#mform', d), prev = () => { const pct = +F.pct.value || 0, amt = +F.amt.value || 0, hs = F.hs.value === 'true';
    const sel = list.filter(e => F['e_' + e.id] && F['e_' + e.id].checked), inc = sel.reduce((a, e) => a + n0(e.basic) * pct / 100 + amt + (hs ? n0(e.housing) * pct / 100 : 0), 0);
    $('#brp', d).innerHTML = `${esc(tr('الموظفون'))}: <b class="num">${sel.length}</b> · ${esc(tr('زيادة التكلفة الشهرية'))}: <b class="num">${money(inc)}</b> · ${esc(tr('السنوية'))}: <b class="num">${money(inc * 12)}</b>`; };
  $$('input,select', F).forEach(x => x.addEventListener('input', prev)); F.hs.addEventListener('change', prev);
  $('#brd', d).onchange = ev => { $$('#bre input', d).forEach(x => x.checked = !ev.target.value || x.dataset.dep === ev.target.value); prev(); }; prev();
}

/* ----- policies ----- */
VIEWS['#/policies'] = async page => {
  const hr = isHR();
  const [pols, acks, em] = await Promise.all([db.get('policies', { company_id: 'eq.' + S.cid, order: 'created_at.desc' }), db.get('policy_acks', { company_id: 'eq.' + S.cid }), hr ? employeesMap(true) : Promise.resolve({})]);
  const act = Object.values(em).filter(e => !e.end_date || e.end_date >= today());
  const mine = new Set(acks.filter(a => a.employee_id === S.emp).map(a => a.policy_id));
  const T = p => (LANG === 'en' && p.title_en) || p.title, B = p => (LANG === 'en' && p.body_en) || p.body;
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('السياسات واللوائح'))}</h1><div class="muted">${esc(tr('يقر كل موظف بالاطلاع على السياسات المعتمدة'))}</div></div>${hr ? `<button class="btn pri" id="pnew">${esc(tr('سياسة جديدة'))}</button>` : ''}</div>
    ${tbl([{ t: 'السياسة', h: p => esc(T(p)) + (p.active ? '' : ` <span class="badge">${esc(tr('موقوفة'))}</span>`) }, { t: 'التاريخ', h: p => fdate(String(p.created_at).slice(0, 10)) },
      ...(S.emp ? [{ t: 'إقراري', h: p => mine.has(p.id) ? `<span class="badge ok">${esc(tr('أقررت'))}</span>` : `<span class="badge wait">${esc(tr('بانتظار إقرارك'))}</span>` }] : []),
      ...(hr ? [{ t: 'أقر', r: 1, h: p => { const n = acks.filter(a => a.policy_id === p.id).length; return `<b class="num ${n < act.length ? 'bad' : ''}">${n}</b> / <span class="num">${act.length}</span>`; } }] : [])],
      pols.filter(p => hr || p.active), { empty: 'لا توجد سياسات', onRow: true })}`;
  bindRows(page, pols.filter(p => hr || p.active), p => {
    const who = hr ? act.filter(e => !acks.some(a => a.policy_id === p.id && a.employee_id === e.id)) : [];
    const d = modal(T(p), `<div style="white-space:pre-wrap;line-height:1.8">${esc(B(p))}</div>
      ${S.emp && p.active && !mine.has(p.id) ? `<div class="row" style="margin-top:12px"><button type="button" class="btn pri" id="pack">${esc(tr('أقر بأنني اطلعت على هذه السياسة'))}</button></div>` : ''}
      ${hr ? `<h3 style="margin-top:14px;font-size:15px">${esc(tr('لم يقر بعد'))} (<span class="num">${who.length}</span>)</h3><p class="small">${who.map(e => esc(e.full_name)).join('، ') || esc(tr('الكل أقر'))}</p>
        <div class="row"><button type="button" class="btn sm" id="pedit">${esc(tr('تعديل'))}</button></div>` : ''}`, { wide: true });
    if ($('#pack', d)) $('#pack', d).onclick = async () => { try { await db.rpc('policy_ack', { p_policy: p.id }); d.close(); toast(tr('شكراً، سُجّل إقرارك')); route(); } catch (er) { toast(er.message); } };
    if ($('#pedit', d)) $('#pedit', d).onclick = () => { d.close(); policyForm(p); };
  });
  if ($('#pnew', page)) $('#pnew', page).onclick = () => policyForm(null);
};
function policyForm(p) {
  const v = p || { active: true };
  modal(p ? tr('تعديل سياسة') : tr('سياسة جديدة'), `<div class="fg">${field('العنوان', inp('title', v.title, 'required'))}${enF('title_en', v.title_en)}
    ${field('النص', `<textarea name="body" rows="8">${esc(v.body || '')}</textarea>`, 'wide')}${field('النص بالإنجليزية (اختياري)', `<textarea name="body_en" rows="4" dir="ltr">${esc(v.body_en || '')}</textarea>`, 'wide')}
    ${field('الحالة', `<select name="active">${opt('true', tr('معتمدة — يطلب إقرار الموظفين'), String(v.active))}${opt('false', tr('موقوفة'), String(v.active))}</select>`)}</div>
    ${p ? `<p class="muted small">${esc(tr('إذا تغيّر النص يُطلب إقرار جديد من كل الموظفين.'))}</p>` : ''}`, { wide: true,
    onOk: async f => { await db.rpc('policy_save', { p_company: S.cid, p_id: p ? p.id : null, p_title: f.title, p_title_en: blank(f.title_en), p_body: f.body, p_body_en: blank(f.body_en), p_active: f.active === 'true' }); toast('تم الحفظ'); route(); } });
}
// employees: policies waiting for acknowledgement, shown on the home page
async function pendingPolicies() {
  if (!S.emp) return [];
  const [pols, acks] = await Promise.all([db.get('policies', { company_id: 'eq.' + S.cid, active: 'is.true', select: 'id,title,title_en' }).catch(() => []), db.get('policy_acks', { employee_id: 'eq.' + S.emp, select: 'policy_id' }).catch(() => [])]);
  const done = new Set(acks.map(a => a.policy_id)); return pols.filter(p => !done.has(p.id));
}

/* ----- annual leave statement (Art. 109) ----- */
async function leaveStatementCard(box, e) {
  const [[b], lv] = await Promise.all([db.rpc('annual_leave_balance', { p_emp: e.id }), db.get('requests', { employee_id: 'eq.' + e.id, kind: 'eq.leave', sub: 'eq.annual', status: 'in.(pending,approved)', order: 'from_date.desc' })]);
  const yrs = (new Date(today()) - new Date(e.hire_date)) / 864e5 / 365;
  box.innerHTML = `<div class="card"><h2>${esc(tr('كشف رصيد الإجازة السنوية'))}</h2>
    <div class="grid" style="margin-bottom:8px"><div class="card kpi"><div class="muted small">${esc(tr('المستحق حتى اليوم'))}</div><div class="v num">${r2(b && b.accrued)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('المأخوذ والمحجوز'))}</div><div class="v num">${r2(b && b.taken)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('الرصيد'))}</div><div class="v num ${n0(b && b.balance) > 30 ? 'bad' : ''}">${Math.floor(n0(b && b.balance))}</div></div></div>
    <p class="muted small">${esc(tr('الاستحقاق'))}: <b class="num">${yrs >= 5 ? 30 : 21}</b> ${esc(tr('يوماً في السنة (م109)'))}${n0(b && b.balance) > 30 ? ' — ' + esc(tr('رصيد متراكم: يُنصح بجدولة إجازة')) : ''}</p>
    ${tbl([{ t: 'من', h: r => fdate(r.from_date) }, { t: 'إلى', h: r => fdate(r.to_date) }, { t: 'الأيام', r: 1, h: r => String(r.days) }, { t: 'الحالة', h: r => badge(r.status) }], lv, { empty: 'لا توجد إجازات سنوية' })}</div>`;
}
