'use strict';
/* ===== Company analytics: one page for the general manager, finance, HR, sales, purchasing and each manager's team.
   Every section comes from company_analytics() and is shown only to whoever may see it. Exports: PDF, Excel (one sheet
   per table), CSV, Word and a PNG of the charts — all built in the browser from the same model. ===== */

const AN_C = ['#217FE1', '#C9B27B', '#ef4444', '#3fc392', '#8b5cf6', '#06b6d4'];
const anISO = d => d.toISOString().slice(0, 10);
const anEnd = (y, m) => anISO(new Date(Date.UTC(y, m, 0)));   // last day of month m (1-12)
function anPreset(k) {
  const t = today(), y = +t.slice(0, 4), m = +t.slice(5, 7), q = Math.floor((m - 1) / 3) * 3 + 1, p2 = n => String(n).padStart(2, '0');
  if (k === 'lastm') { const ly = m === 1 ? y - 1 : y, lm = m === 1 ? 12 : m - 1; return [`${ly}-${p2(lm)}-01`, anEnd(ly, lm)]; }
  if (k === 'q') return [`${y}-${p2(q)}-01`, anEnd(y, q + 2)];
  if (k === 'y') return [`${y}-01-01`, `${y}-12-31`];
  if (k === 'ly') return [`${y - 1}-01-01`, `${y - 1}-12-31`];
  if (k === 'l12') return [anISO(new Date(Date.UTC(y, m - 12, 1))), anEnd(y, m)];
  return [`${y}-${p2(m)}-01`, anEnd(y, m)];
}
const anFmt = (v, f) => v == null || v === '' ? '—' : f === 'money' ? money(v) : f === 'pct' ? r2(n0(v)) + '%' : f === 'num' ? String(r2(n0(v))) : String(v);
const anChg = (v, p) => p == null || n0(p) === 0 ? null : r2((n0(v) - n0(p)) / Math.abs(n0(p)) * 100);
const anNm = x => (LANG === 'en' && x.name_en) || x.name;

// the model: sections → KPIs, notes, charts and tables (labels stay Arabic here and are translated when shown or exported)
function anModel(d, lt) {
  const S_ = [], ltn = {}; (lt || []).forEach(l => ltn[l.code] = LANG === 'en' ? l.name_en : l.name_ar);
  const mon = m => m.slice(2);
  const K = (l, v, f, p, inv, sp) => ({ l, v, f, p, inv, sp });
  const col = (arr, k) => (arr || []).map(x => n0(x[k]));   // pluck a monthly series for a sparkline
  if (d.exec) { const x = d.exec, notes = [];
    if (x.revenue_prev > 0) notes.push(['الإيرادات مقارنة بالفترة السابقة', anChg(x.revenue, x.revenue_prev), 'pct', anChg(x.revenue, x.revenue_prev) >= 0]);
    if (x.margin != null) notes.push(['هامش صافي الربح', x.margin, 'pct', x.margin >= 0]);
    if (x.payroll_ratio != null) notes.push(['تكلفة الرواتب من الإيرادات', x.payroll_ratio, 'pct', x.payroll_ratio <= 40, 40]);
    if (x.ar > 0 && x.revenue > 0) notes.push(['أيام التحصيل التقريبية (DSO)', Math.round(x.ar / x.revenue * ((new Date(d.to) - new Date(d.from)) / 864e5 + 1)), 'num', null]);
    S_.push({ k: 'exec', t: 'نظرة عامة', kpis: [K('الإيرادات', x.revenue, 'money', x.revenue_prev, 0, col(x.months, 'revenue')), K('المصروفات', x.expenses, 'money', x.expenses_prev, 1, col(x.months, 'expenses')), K('صافي الربح', x.profit, 'money', x.profit_prev, 0, col(x.months, 'profit')),
      K('هامش الربح', x.margin, 'pct'), K('هامش الربح الإجمالي', x.gross_margin, 'pct'), K('تكلفة الرواتب', x.payroll, 'money', x.payroll_prev, 1), K('الرواتب من الإيرادات', x.payroll_ratio, 'pct'),
      K('النقد في البنك والصندوق', x.cash, 'money', x.cash_prev), K('ذمم العملاء', x.ar, 'money'), K('ذمم الموردين', x.ap, 'money'), K('قيمة المخزون', x.inventory, 'money'),
      K('عدد الموظفين', x.headcount, 'num'), K('الإيراد لكل موظف', x.rev_per_emp, 'money')], notes,
      charts: [{ t: 'الإيرادات والمصروفات شهريا', bars: x.months.map(m => ({ label: mon(m.m), values: [m.revenue, m.expenses] })), series: ['الإيرادات', 'المصروفات'], f: 'money' }],
      tables: [{ t: 'الأداء الشهري', cols: [['الشهر'], ['الإيرادات', 'money'], ['المصروفات', 'money'], ['صافي الربح', 'money']], rows: x.months.map(m => [m.m, m.revenue, m.expenses, m.profit]) }] }); }
  if (d.finance) { const x = d.finance, ag = a => [n0(a && a.d30), n0(a && a.d60), n0(a && a.d90), n0(a && a.over)];
    S_.push({ k: 'finance', t: 'المالية', kpis: [K('ضريبة المخرجات', x.vat.output, 'money'), K('ضريبة المدخلات', x.vat.input, 'money'), K('صافي الضريبة المستحقة', n0(x.vat.output) - n0(x.vat.input), 'money'),
      K('ذمم عملاء متأخرة أكثر من 90 يوما', ag(x.ar_aging)[3], 'money', null, 1), K('ذمم موردين متأخرة أكثر من 90 يوما', ag(x.ap_aging)[3], 'money', null, 1)],
      charts: [{ t: 'التدفق النقدي شهريا', bars: x.cash_flow.map(m => ({ label: mon(m.m), values: [m.in, m.out] })), series: ['داخل', 'خارج'], f: 'money' },
        { t: 'أكبر المصروفات', h: x.expense_accounts.slice(0, 10).map(a => ({ label: anNm(a), v: a.amount })), f: 'money' }],
      tables: [{ t: 'المصروفات حسب الحساب', cols: [['الحساب'], ['الاسم'], ['المبلغ', 'money']], rows: x.expense_accounts.map(a => [a.code, anNm(a), a.amount]) },
        { t: 'أعمار الذمم', cols: [['البيان'], ['حتى 30 يوما', 'money'], ['31–60', 'money'], ['61–90', 'money'], ['أكثر من 90', 'money']], rows: [[tr('ذمم العملاء'), ...ag(x.ar_aging)], [tr('ذمم الموردين'), ...ag(x.ap_aging)]] },
        { t: 'التدفق النقدي', cols: [['الشهر'], ['داخل', 'money'], ['خارج', 'money'], ['الصافي', 'money']], rows: x.cash_flow.map(m => [m.m, m.in, m.out, n0(m.in) - n0(m.out)]) }] }); }
  if (d.sales) { const x = d.sales;
    S_.push({ k: 'sales', t: 'المبيعات', kpis: [K('المبيعات قبل الضريبة', x.total, 'money', x.total_prev, 0, col(x.months, 'total')), K('عدد الفواتير', x.count, 'num'), K('متوسط الفاتورة', x.count ? x.total / x.count : null, 'money'),
      K('المرتجعات', x.returns, 'money', null, 1), K('المحصّل', x.collected, 'money')],
      notes: x.total > 0 && x.customers.length ? [['حصة أكبر عميل من المبيعات', r2(x.customers[0].total / x.total * 100), 'pct', x.customers[0].total / x.total <= .3, 30]] : [],
      charts: [{ t: 'المبيعات شهريا', bars: x.months.map(m => ({ label: mon(m.m), values: [m.total] })), series: ['المبيعات'], f: 'money' },
        { t: 'أكبر العملاء', h: x.customers.map(c => ({ label: anNm(c), v: c.total })), f: 'money' }],
      tables: [{ t: 'الأصناف الأكثر مبيعا', cols: [['الصنف'], ['الكمية', 'num'], ['المبلغ', 'money']], rows: x.items.map(i => [anNm(i), i.qty, i.total]) }] }); }
  if (d.supply) { const x = d.supply;
    S_.push({ k: 'supply', t: 'المشتريات والمخزون', kpis: [K('المشتريات قبل الضريبة', x.purchases, 'money', x.purchases_prev, 1, col(x.months, 'total')), K('المدفوع للموردين', x.paid, 'money'), K('قيمة المخزون', x.stock_value, 'money'),
      K('أصناف تحت حد الطلب', x.low_stock.length, 'num', null, 1), K('أصناف راكدة', x.slow.length, 'num', null, 1)],
      charts: [{ t: 'المشتريات شهريا', bars: x.months.map(m => ({ label: mon(m.m), values: [m.total] })), series: ['المشتريات'], f: 'money' },
        { t: 'أكبر الموردين', h: x.suppliers.map(c => ({ label: anNm(c), v: c.total })), f: 'money' }],
      tables: [{ t: 'أصناف تحت حد الطلب', cols: [['الرمز'], ['الصنف'], ['الكمية', 'num'], ['حد الطلب', 'num']], rows: x.low_stock.map(i => [i.code, anNm(i), i.qty, i.reorder]) },
        { t: 'أصناف راكدة (بلا مبيعات في الفترة)', cols: [['الرمز'], ['الصنف'], ['الكمية', 'num'], ['القيمة', 'money']], rows: x.slow.map(i => [i.code, anNm(i), i.qty, i.value]) }] }); }
  if (d.hr) { const x = d.hr, p = x.payroll || {}, rs = Object.entries(x.leavers_by_reason || {}), lv = Object.entries(x.leave_days || {});
    const notes = [['نسبة السعوديين', x.headcount ? r2(x.saudi / x.headcount * 100) : 0, 'pct', null], ['معدل الدوران في الفترة', x.turnover, 'pct', x.turnover <= 10, 10]];
    if (x.headcount && p.gross) notes.push(['متوسط تكلفة الموظف في الفترة', (n0(p.gross) + n0(p.employer_gosi)) / x.headcount, 'money', null]);
    S_.push({ k: 'hr', t: 'الموارد البشرية', kpis: [K('عدد الموظفين', x.headcount, 'num', x.headcount_start), K('منضمون', x.joiners, 'num'), K('مغادرون', x.leavers, 'num', null, 1), K('معدل الدوران', x.turnover, 'pct', null, 1),
      K('السعوديون', x.saudi, 'num'), K('النساء', x.female, 'num'), K('متوسط مدة الخدمة (سنة)', x.tenure, 'num'), K('أيام الغياب', x.absent_days, 'num', null, 1),
      K('ساعات التأخير', x.late_hours, 'num', null, 1), K('ساعات العمل الإضافي', x.ot_hours, 'num'), K('إجمالي الرواتب', p.gross, 'money'), K('تأمينات المنشأة', p.employer_gosi, 'money'), K('الاستقطاعات', p.deductions, 'money')], notes,
      charts: [{ t: 'أيام الإجازات حسب النوع', h: lv.map(([k, v]) => ({ label: ltn[k] || k, v })), f: 'num', donut: 1 }, { t: 'المغادرون حسب السبب', h: rs.map(([k, v]) => ({ label: tr(EOS_REASONS[k] || 'أخرى'), v })), f: 'num', donut: 1 }],
      tables: [{ t: 'الإجازات حسب النوع', cols: [['النوع'], ['الأيام', 'num']], rows: lv.map(([k, v]) => [ltn[k] || k, v]) },
        { t: 'المغادرون حسب السبب', cols: [['السبب'], ['العدد', 'num']], rows: rs.map(([k, v]) => [tr(EOS_REASONS[k] || 'أخرى'), v]) },
        { t: 'الرواتب في الفترة', cols: [['البيان'], ['المبلغ', 'money']], rows: [[tr('الإجمالي'), p.gross], [tr('العمل الإضافي'), p.overtime], [tr('الاستقطاعات'), p.deductions], [tr('الصافي'), p.net], [tr('تأمينات المنشأة'), p.employer_gosi]] }] }); }
  if (d.departments && d.departments.length) { const x = d.departments, dn = r => r.name === '—' ? tr('بلا قسم') : anNm(r);
    S_.push({ k: 'departments', t: 'الأقسام', kpis: [K('عدد الأقسام', x.filter(r => r.name !== '—').length, 'num'), K('أعلى تكلفة', x.length ? dn(x.slice().sort((a, b) => b.cost - a.cost)[0]) : null, 'txt')],
      charts: [{ t: 'تكلفة الأقسام', h: x.map(r => ({ label: dn(r), v: r.cost })), f: 'money' }, { t: 'الموظفون حسب القسم', h: x.map(r => ({ label: dn(r), v: r.headcount })), f: 'num' }],
      tables: [{ t: 'مقارنة الأقسام', cols: [['القسم'], ['الموظفون', 'num'], ['السعوديون', 'num'], ['المغادرون', 'num'], ['متوسط الأجر', 'money'], ['التكلفة', 'money'], ['أيام الغياب', 'num'], ['ساعات التأخير', 'num'], ['ساعات إضافية', 'num'], ['أيام الإجازات', 'num']],
        rows: x.map(r => [dn(r), r.headcount, r.saudi, r.leavers, r.avg_wage, r.cost, r.absent_days, r.late_hours, r.ot_hours, r.leave_days]) }] }); }
  if (d.team && d.team.length) { const x = d.team;
    S_.push({ k: 'team', t: 'فريقي', kpis: [K('أعضاء الفريق', x.length, 'num'), K('ساعات التأخير', x.reduce((a, r) => a + n0(r.late_hours), 0), 'num', null, 1), K('طلبات بانتظار الاعتماد', x.reduce((a, r) => a + n0(r.pending), 0), 'num', null, 1)],
      charts: [{ t: 'ساعات التأخير', h: x.map(r => ({ label: anNm({ name: r.name, name_en: r.name_en }), v: r.late_hours })), f: 'num' }],
      tables: [{ t: 'فريقي', cols: [['الموظف'], ['أيام الحضور', 'num'], ['ساعات التأخير', 'num'], ['ساعات إضافية', 'num'], ['أيام الإجازات', 'num'], ['طلبات معلقة', 'num']],
        rows: x.map(r => [anNm({ name: r.name, name_en: r.name_en }), r.present, r.late_hours, r.ot_hours, r.leave_days, r.pending]) }] }); }
  return S_;
}

function anSectionHtml(s) {
  const kpi = k => { const c = anChg(k.v, k.p), good = c == null ? null : (c >= 0) !== !!k.inv;
    const sp = (k.sp && k.sp.length > 1) ? `<div style="margin-top:6px">${sparkline(k.sp, good === false ? 'var(--bad)' : good ? 'var(--ok)' : 'var(--accent)')}</div>` : '';
    return `<div class="card kpi"><div class="muted small">${esc(tr(k.l))}</div><div class="v num">${esc(anFmt(k.v, k.f))}</div>${k.p != null ? `<div class="small ${good === false ? 'bad' : good ? 'ok' : 'muted'}">${c == null ? '' : (c >= 0 ? '▲ ' : '▼ ') + Math.abs(c) + '% '}<span class="muted">${esc(tr('السابقة'))}: <span class="num">${esc(anFmt(k.p, k.f))}</span></span></div>` : ''}${sp}</div>`; };
  const chart = c => `<div class="card"><h2>${esc(tr(c.t))}</h2>${c.h ? (c.h.length ? (c.donut ? donut(c.h, v => anFmt(v, c.f)) : hbars(c.h, v => anFmt(v, c.f))) : `<p class="muted small">${esc(tr('لا توجد بيانات'))}</p>`)
    : c.bars.length ? barChart(c.bars.map(b => ({ label: b.label, values: b.values.map(v => Math.max(0, n0(v))) })), c.series.map((n, i) => ({ name: n, color: AN_C[i] })), { fmt: v => anFmt(v, c.f) }) : `<p class="muted small">${esc(tr('لا توجد بيانات'))}</p>`}</div>`;
  const table = t => `<div class="card"><h2>${esc(tr(t.t))}</h2>${t.rows.length ? `<div class="tw"><table><thead><tr>${t.cols.map(c => `<th${c[1] ? ' class="r"' : ''}>${esc(tr(c[0]))}</th>`).join('')}</tr></thead><tbody>
      ${t.rows.map(r => `<tr>${r.map((v, i) => `<td${t.cols[i][1] ? ' class="r num"' : ''}>${esc(anFmt(v, t.cols[i][1]))}</td>`).join('')}</tr>`).join('')}</tbody></table></div>` : `<p class="muted small">${esc(tr('لا توجد بيانات'))}</p>`}</div>`;
  const note = n => `<div style="margin:6px 0"><div class="row small" style="gap:8px"><span class="${n[3] === false ? 'bad' : n[3] ? 'ok' : 'muted'}">●</span><span style="flex:1">${esc(tr(n[0]))}</span><b class="num">${esc(anFmt(n[1], n[2]))}</b>${n[4] != null ? `<span class="muted" style="min-width:70px;text-align:end">${esc(tr('الهدف'))} <span class="num">${esc(anFmt(n[4], n[2]))}</span></span>` : ''}</div>${n[4] != null ? bullet(n[1], n[4], { fmt: v => anFmt(v, n[2]), good: n[3] }) : ''}</div>`;
  const notes = (s.notes || []).length ? `<div class="card"><h2>${esc(tr('مؤشرات تستحق الانتباه'))}</h2>${s.notes.map(note).join('')}</div>` : '';
  return `<section class="ansec" data-an="${s.k}"><h2 class="anh">${esc(tr(s.t))}</h2><div class="grid">${s.kpis.map(kpi).join('')}</div>${notes}
    <div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(320px,1fr))">${s.charts.map(chart).join('')}</div>${s.tables.map(table).join('')}</section>`;
}

/* ----- exports ----- */
// flat rows per section: a KPI table and every data table, with headers translated
function anFlat(model) {
  const out = [];
  for (const s of model) {
    out.push({ name: tr(s.t), rows: [[tr('المؤشر'), tr('القيمة'), tr('الفترة السابقة'), tr('التغير %')], ...s.kpis.map(k => [tr(k.l), k.f === 'txt' ? String(k.v ?? '') : k.v == null ? '' : r2(n0(k.v)), k.p == null ? '' : r2(n0(k.p)), anChg(k.v, k.p) ?? '']),
      ...(s.notes || []).map(n => [tr(n[0]), r2(n0(n[1])), '', ''])] });
    s.tables.forEach(t => out.push({ name: tr(t.t), rows: [t.cols.map(c => tr(c[0])), ...t.rows.map(r => r.map((v, i) => t.cols[i][1] ? (v == null ? '' : r2(n0(v))) : String(v ?? '')))] }));
  }
  return out;
}
const anCsvCell = v => { let t = String(v ?? ''); if (typeof v !== 'number' && /^[=+\-@\t\r]/.test(t)) t = "'" + t; return /[",\n\r]/.test(t) ? '"' + t.replace(/"/g, '""') + '"' : t; };
const anCsv = flat => '\ufeff' + flat.map(s => [[s.name], ...s.rows].map(r => r.map(anCsvCell).join(',')).join('\r\n')).join('\r\n\r\n');
function anWord(model, title, sub) {
  const rtl = LANG !== 'en', e = esc, cell = 'border:1px solid #cbd5e1;padding:4px 6px';
  const tblH = (head, rows, numCols) => `<table style="border-collapse:collapse;width:100%;margin:6px 0 14px"><tr>${head.map(h => `<th style="${cell};background:#eef2f7">${e(h)}</th>`).join('')}</tr>${rows.map(r => `<tr>${r.map((v, i) => `<td style="${cell}${numCols[i] ? ';text-align:' + (rtl ? 'left' : 'right') : ''}">${e(v)}</td>`).join('')}</tr>`).join('')}</table>`;
  const body = model.map(s => `<h2 style="color:#1e3a8a;border-bottom:2px solid #1e3a8a">${e(tr(s.t))}</h2>`
    + tblH([tr('المؤشر'), tr('القيمة'), tr('الفترة السابقة'), tr('التغير %')], s.kpis.map(k => { const c = anChg(k.v, k.p); return [tr(k.l), anFmt(k.v, k.f), k.p == null ? '' : anFmt(k.p, k.f), c == null ? '' : c + '%']; }), [0, 1, 1, 1])
    + ((s.notes || []).length ? `<p><b>${e(tr('مؤشرات تستحق الانتباه'))}</b></p><ul>${s.notes.map(n => `<li>${e(tr(n[0]))}: ${e(anFmt(n[1], n[2]))}</li>`).join('')}</ul>` : '')
    + s.tables.filter(t => t.rows.length).map(t => `<h3>${e(tr(t.t))}</h3>` + tblH(t.cols.map(c => tr(c[0])), t.rows.map(r => r.map((v, i) => anFmt(v, t.cols[i][1]))), t.cols.map(c => !!c[1]))).join('')).join('');
  const html = `<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word" xmlns="http://www.w3.org/TR/REC-html40"><head><meta charset="utf-8"><title>${e(title)}</title>
    <style>body{font-family:Arial,sans-serif;font-size:11pt;direction:${rtl ? 'rtl' : 'ltr'}}@page{size:A4;margin:2cm}</style></head><body dir="${rtl ? 'rtl' : 'ltr'}"><h1>${e(title)}</h1><p>${e(sub)}</p>${body}</body></html>`;
  return new Blob(['﻿', html], { type: 'application/msword' });
}
// one PNG with every chart, drawn on a canvas (no external library)
async function anPng(model, title, sub) {
  const charts = model.flatMap(s => s.charts.filter(c => c.h ? c.h.length : c.bars.length).map(c => ({ ...c, sec: tr(s.t) })));
  const W = 1200, P = 32, font = '"IBM Plex Sans Arabic", Arial, sans-serif', rtl = LANG !== 'en';
  const hOf = c => c.h ? 60 + Math.min(c.h.length, 15) * 30 : 330;
  const H = 110 + charts.reduce((a, c) => a + hOf(c) + 24, 0) + (charts.length ? 0 : 60);
  const cv = document.createElement('canvas'); cv.width = W; cv.height = H; const g = cv.getContext('2d');
  try { await document.fonts.ready; } catch (_) { }
  g.fillStyle = '#ffffff'; g.fillRect(0, 0, W, H); g.direction = rtl ? 'rtl' : 'ltr';
  const txt = (s, x, y, { sz = 14, c = '#0f172a', b = false, al = 'start' } = {}) => { g.font = `${b ? '700 ' : ''}${sz}px ${font}`; g.fillStyle = c; g.textAlign = al; g.fillText(s, x, y); };
  const sx = rtl ? W - P : P;
  txt(title, sx, 46, { sz: 24, b: true }); txt(sub, sx, 76, { sz: 14, c: '#64748b' });
  let y = 110;
  if (!charts.length) txt(tr('لا توجد بيانات'), sx, y + 20, { c: '#64748b' });
  for (const c of charts) {
    const h = hOf(c); g.strokeStyle = '#e2e8f0'; g.lineWidth = 1; g.strokeRect(P / 2, y, W - P, h);
    txt(c.sec + ' — ' + tr(c.t), sx, y + 30, { sz: 16, b: true });
    if (c.h) {
      const rows = c.h.slice(0, 15), max = Math.max(1, ...rows.map(r => n0(r.v))), lw = 260, bw = W - 2 * P - lw - 140;
      rows.forEach((r, i) => { const yy = y + 56 + i * 30, w = Math.max(1, n0(r.v) / max * bw);
        txt(String(r.label).slice(0, 34), rtl ? W - P : P, yy + 14, { sz: 13 });
        g.fillStyle = '#e2e8f0'; g.fillRect(rtl ? W - P - lw - bw : P + lw, yy + 2, bw, 14); g.fillStyle = AN_C[0]; g.fillRect(rtl ? W - P - lw - w : P + lw, yy + 2, w, 14);
        txt(anFmt(r.v, c.f), rtl ? P : W - P, yy + 14, { sz: 13, b: true, al: rtl ? 'left' : 'right' }); });
    } else {
      const bars = c.bars, ns = c.series.length, max = Math.max(1, ...bars.flatMap(b => b.values.map(v => Math.max(0, n0(v))))), top = y + 70, ch = 210, L = P + 70, R = W - P;
      const gw = (R - L) / bars.length, bw = Math.max(3, Math.min(40, (gw - 10) / ns));
      g.direction = 'ltr';
      [0, .5, 1].forEach(f => { const yy = top + ch - f * ch; g.strokeStyle = '#eef2f7'; g.beginPath(); g.moveTo(L, yy); g.lineTo(R, yy); g.stroke(); txt(Math.round(max * f).toLocaleString('en'), L - 8, yy + 4, { sz: 11, c: '#64748b', al: 'right' }); });
      bars.forEach((b, i) => { const x0 = L + i * gw + (gw - bw * ns) / 2;
        b.values.forEach((v, k) => { const bh = Math.max(0, n0(v)) / max * ch; g.fillStyle = AN_C[k]; g.fillRect(x0 + k * bw, top + ch - bh, bw - 2, bh); });
        txt(b.label, L + i * gw + gw / 2, top + ch + 18, { sz: 11, c: '#64748b', al: 'center' }); });
      let lx = L; c.series.forEach((n, k) => { g.fillStyle = AN_C[k]; g.fillRect(lx, y + 44, 12, 12); txt(tr(n), lx + 18, y + 55, { sz: 12 }); g.font = `12px ${font}`; lx += 40 + g.measureText(tr(n)).width; });
      g.direction = rtl ? 'rtl' : 'ltr';
    }
    y += h + 24;
  }
  return new Promise(res => cv.toBlob(res, 'image/png'));
}

VIEWS['#/analytics'] = async page => {
  const p = new URLSearchParams(location.hash.split('?')[1] || ''), pre = p.get('p') || 'm';
  let [from, to] = pre === 'c' && p.get('f') && p.get('t') ? [p.get('f'), p.get('t')] : anPreset(pre);
  const [d, lt] = await Promise.all([db.rpc('company_analytics', { p_company: S.cid, p_from: from, p_to: to }), LEAVE_TYPES().catch(() => [])]);
  const model = anModel(d, lt), tab = model.some(s => s.k === p.get('tab')) ? p.get('tab') : (model[0] || {}).k;
  const go = o => { const q = new URLSearchParams({ p: pre, ...(pre === 'c' ? { f: from, t: to } : {}), ...(tab ? { tab } : {}), ...o }); location.hash = '#/analytics?' + q; };
  const title = tr('التحليلات') + ' — ' + S.company.name, sub = `${tr('الفترة')}: ${fdate(from)} – ${fdate(to)} · ${tr('مقارنة مع')} ${fdate(d.prev_from)} – ${fdate(d.prev_to)}`;
  const fn = ext => `waad-analytics-${from}_${to}.${ext}`;
  const P_ = [['m', 'هذا الشهر'], ['lastm', 'الشهر الماضي'], ['q', 'هذا الربع'], ['y', 'هذه السنة'], ['ly', 'السنة الماضية'], ['l12', 'آخر 12 شهرا'], ['c', 'فترة مخصصة']];
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('التحليلات'))}</h1><div class="muted small">${esc(sub)}</div></div>
      <div class="row"><select id="anp" style="width:auto">${P_.map(([k, l]) => opt(k, tr(l), pre)).join('')}</select>
        <span id="anc" class="row" ${pre === 'c' ? '' : 'hidden'}><input type="date" id="anf" value="${from}" style="width:auto"><input type="date" id="ant" value="${to}" style="width:auto"><button class="btn" id="ango">${esc(tr('عرض'))}</button></span></div></div>
    ${model.length ? `<div class="card row" style="gap:6px;flex-wrap:wrap"><b class="small">${esc(tr('تصدير'))}:</b>
        <button class="btn sm" data-ex="pdf">PDF</button><button class="btn sm" data-ex="xlsx">Excel</button><button class="btn sm" data-ex="csv">CSV</button><button class="btn sm" data-ex="doc">Word</button><button class="btn sm" data-ex="png">${esc(tr('صورة PNG'))}</button>
        <label class="small row" style="gap:4px;margin:0"><input type="checkbox" id="anall" checked style="width:auto">${esc(tr('كل الأقسام'))}</label></div>
      <div class="tabs" role="tablist" style="flex-wrap:wrap">${model.map(s => `<button class="tab ${s.k === tab ? 'on' : ''}" data-tab="${s.k}">${esc(tr(s.t))}</button>`).join('')}</div>
      <div id="anbody">${model.map(s => anSectionHtml(s)).join('')}</div>`
    : `<div class="note">${esc(tr('لا توجد تحليلات متاحة لصلاحياتك.'))}</div>`}`;
  $$('[data-an]', page).forEach(x => x.hidden = x.dataset.an !== tab);
  $('#anp', page).onchange = ev => { if (ev.target.value === 'c') { $('#anc', page).hidden = false; return; } location.hash = '#/analytics?' + new URLSearchParams({ p: ev.target.value, ...(tab ? { tab } : {}) }); };
  $('#ango', page).onclick = () => { const f = $('#anf', page).value, t = $('#ant', page).value; if (!f || !t || t < f) return toast(tr('حدد الفترة')); go({ p: 'c', f, t }); };
  $$('[data-tab]', page).forEach(b => b.onclick = () => go({ tab: b.dataset.tab }));
  $$('[data-ex]', page).forEach(b => b.onclick = async () => {
    const sel = $('#anall', page).checked ? model : model.filter(s => s.k === tab), k = b.dataset.ex;
    try {
      if (k === 'pdf') { toast(tr('تفتح نافذة الطباعة — اختر «حفظ بصيغة PDF»')); const box = document.createElement('div'); box.innerHTML = `<p class="muted small">${esc(sub)}</p>` + sel.map(anSectionHtml).join(''); return printBlock(box, title); }
      if (k === 'xlsx') return anSave(xlsxBook(anFlat(sel)), fn('xlsx'));
      if (k === 'csv') return anSave(new Blob([anCsv(anFlat(sel))], { type: 'text/csv;charset=utf-8' }), fn('csv'));
      if (k === 'doc') return anSave(anWord(sel, title, sub), fn('doc'));
      if (k === 'png') return anSave(await anPng(sel, title, sub), fn('png'));
    } catch (er) { toast(er.message); }
  });
};

/* ----- dashboards: the owner's home shows the overview; each menu section opens its own (#/dash/finance, sales, supply)
   with its numbers and charts for a chosen period — the detailed tables stay in «التحليلات» ----- */
const DASH_P = [['m', 'هذا الشهر'], ['lastm', 'الشهر الماضي'], ['q', 'هذا الربع'], ['y', 'هذه السنة'], ['l12', 'آخر 12 شهرا']];
async function dashSection(box, k, title) {
  if (k === 'branches') return dashBranches(box, title);
  if (k === 'group') return dashGroup(box, title);
  const pre = LS.get('waad.odp') || 'y', [from, to] = anPreset(pre);
  box.innerHTML = `<div class="muted small" style="margin:12px 0">${esc(tr('جاري التحميل'))}…</div>`;
  const [d, lt] = await Promise.all([db.rpc('company_analytics', { p_company: S.cid, p_from: from, p_to: to }), LEAVE_TYPES().catch(() => [])]);
  const all = anModel(d, lt), s = all.find(x => x.k === k), hrS = all.find(x => x.k === 'hr');
  // numbers two sections share: payroll and GOSI (HR and finance), medical insurance (HR and finance)
  let extra = null;
  if (k === 'finance' && hrS) { const pick = ['إجمالي الرواتب', 'تأمينات المنشأة', 'الاستقطاعات', 'ساعات العمل الإضافي', 'عدد الموظفين'];
    extra = { k: 'shared', t: 'الرواتب والتأمينات', kpis: hrS.kpis.filter(x => pick.includes(x.l)), notes: (hrS.notes || []).filter(n => /تكلفة الموظف/.test(n[0])), charts: [], tables: [] }; }
  if (k === 'finance' || k === 'hr') { const ins = await db.get('insurance_members', { company_id: 'eq.' + S.cid, status: 'eq.active', select: 'premium' }).catch(() => null);
    if (ins && ins.length) { const kp = [{ l: 'التأمين الطبي: المشمولون', v: ins.length, f: 'num' }, { l: 'التأمين الطبي: الأقساط', v: ins.reduce((a, x) => a + n0(x.premium), 0), f: 'money' }];
      extra = extra ? Object.assign(extra, { kpis: extra.kpis.concat(kp) }) : { k: 'shared', t: 'التأمين الطبي', kpis: kp, notes: [], charts: [], tables: [] }; } }
  if (!box.isConnected) return;
  box.innerHTML = `<div class="row" style="justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap;margin:${title ? '0' : '18px'} 0 6px">${title || `<h2 style="margin:0">${esc(tr(s ? s.t : 'نظرة عامة'))}</h2>`}
      <div class="row" style="gap:6px"><select class="dashp" style="width:auto" aria-label="${esc(tr('الفترة'))}">${DASH_P.map(([x, l]) => opt(x, tr(l), pre)).join('')}</select><a class="btn sm" href="#/analytics?p=${pre}&tab=${k}">${esc(tr('التحليلات الكاملة والتصدير'))}</a></div></div>
    <div class="muted small" style="margin-bottom:6px">${fdate(from)} – ${fdate(to)}</div>
    ${s ? anSectionHtml(Object.assign({}, s, { tables: [] })) : `<div class="note">${esc(tr('لا توجد تحليلات متاحة لصلاحياتك.'))}</div>`}${extra && extra.kpis.length ? anSectionHtml(extra) : ''}`;
  $('.dashp', box).onchange = e => { LS.set('waad.odp', e.target.value); dashSection(box, k, title).catch(() => {}); };
}
// which dashboards a person sees: the owner and admins all of them; otherwise the section they manage
function dashKeys() {
  const br = S.nBranches > 0 ? ['branches'] : [];   // shown once the company has branches
  const gr = S.group && has('owner', 'admin', 'finance') ? ['group'] : [];   // the group's owner (0141)
  if (has('owner', 'admin')) return ['exec', ...gr, ...br, 'finance', 'sales', 'supply', 'hr', 'departments'];
  const k = [];
  if (has('hr')) k.push('hr');
  if (has('finance', 'accountant')) k.push(...gr, 'finance', ...br, 'sales', 'supply');   // sales, purchasing and the warehouse all post to finance
  if (!has('hr', 'finance', 'accountant') && can('sales')) k.push('sales');
  if (!has('hr', 'finance', 'accountant') && (can('purch') || can('stock'))) k.push('supply');
  return k;
}
// the home page shows the dashboard of one's own section (the overview for the owner)
async function ownerDash(page) {
  const k = dashKeys()[0]; if (!k) return;
  let box = $('#odash', page); if (!box) { box = document.createElement('div'); box.id = 'odash'; const gr = $('.grid', page); (gr || $('.head', page)).after(box); }
  return dashSection(box, k);
}
const DASH_T = { exec: 'نظرة عامة', group: 'المجموعة', branches: 'الفروع', finance: 'المالية', sales: 'المبيعات', supply: 'المشتريات والمخزون', hr: 'الموارد البشرية', departments: 'الأقسام' };
VIEWS['#/dash'] = async (page, arg) => {
  const ks = dashKeys(), k = ks.includes(arg) ? arg : ks[0];
  if (!k) { page.innerHTML = `<div class="note">${esc(tr('لا توجد تحليلات متاحة لصلاحياتك.'))}</div>`; return; }
  page.innerHTML = '<div id="dsec"></div>';
  await dashSection($('#dsec', page), k, `<h1 style="margin:0">${esc(tr('لوحة التحكم'))} — ${esc(tr(DASH_T[k]))}</h1>`);
};

// «الفروع»: every branch's numbers for the period side by side, with a chart (branch_summary)
async function dashBranches(box, title) {
  const pre = LS.get('waad.odp') || 'y', [from, to] = anPreset(pre);
  box.innerHTML = `<div class="muted small" style="margin:12px 0">${esc(tr('جاري التحميل'))}…</div>`;
  const rows = (await db.rpc('branch_summary', { p_company: S.cid, p_from: from, p_to: to }).catch(() => [])).filter(r => r.branch_id || n0(r.sales) || n0(r.purchases) || n0(r.payroll) || n0(r.revenue) || n0(r.expense) || n0(r.headcount));
  if (!box.isConnected) return;
  const nm = r => r.branch_id ? `${r.code} — ${(LANG === 'en' && r.name_en) || r.name}` : tr('بلا فرع');
  box.innerHTML = `<div class="row" style="justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap;margin:${title ? '0' : '18px'} 0 6px">${title || `<h2 style="margin:0">${esc(tr('الفروع'))}</h2>`}
      <div class="row" style="gap:6px"><select class="dashp" style="width:auto" aria-label="${esc(tr('الفترة'))}">${DASH_P.map(([x, l]) => opt(x, tr(l), pre)).join('')}</select><a class="btn sm" href="#/branches">${esc(tr('إدارة الفروع'))}</a></div></div>
    <div class="muted small" style="margin-bottom:6px">${fdate(from)} – ${fdate(to)}</div>
    ${rows.length ? `<div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(320px,1fr))">
        <div class="card"><h2>${esc(tr('المبيعات والربح حسب الفرع'))}</h2>${barChart(rows.map(r => ({ label: r.branch_id ? r.code : '—', values: [Math.max(0, n0(r.sales)), Math.max(0, n0(r.profit))] })), [{ name: tr('المبيعات'), color: AN_C[0] }, { name: tr('صافي الربح'), color: AN_C[1] }], { fmt: v => money(v) })}</div>
        <div class="card"><h2>${esc(tr('تكلفة الرواتب حسب الفرع'))}</h2>${hbars(rows.map(r => ({ label: nm(r), v: n0(r.payroll) })), v => money(v))}</div></div>
      <div class="card">${tbl([{ t: 'الفرع', h: r => `<span data-nt>${esc(nm(r))}</span>` }, { t: 'المبيعات', r: 1, h: r => money(r.sales) }, { t: 'الفواتير', r: 1, h: r => `<span class="num">${r.sales_n}</span>` },
        { t: 'المحصّل', r: 1, h: r => money(r.collected) }, { t: 'المشتريات', r: 1, h: r => money(r.purchases) }, { t: 'الرواتب', r: 1, h: r => money(r.payroll) }, { t: 'الموظفون', r: 1, h: r => `<span class="num">${r.headcount}</span>` },
        { t: 'الإيرادات', r: 1, h: r => money(r.revenue) }, { t: 'المصروفات', r: 1, h: r => money(r.expense) }, { t: 'صافي الربح', r: 1, h: r => `<b class="${n0(r.profit) < 0 ? 'bad' : ''}">${money(r.profit)}</b>` }], rows, {})}
        <p class="muted small">${esc(tr('الإيرادات والمصروفات والربح من القيود المحمّلة على مركز تكلفة الفرع؛ المبيعات والمشتريات والرواتب من مستندات الفرع وموظفيه.'))}</p></div>`
      : `<div class="note">${esc(tr('لا توجد فروع بعد.'))} <a href="#/branches">${esc(tr('إدارة الفروع'))}</a></div>`}`;
  $('.dashp', box).onchange = e => { LS.set('waad.odp', e.target.value); dashBranches(box, title).catch(() => {}); };
}

// «المجموعة» (0141): the group's companies side by side, and its consolidated income statement, balance sheet and trial
// balance — every account with each company's share and the total. Transactions between the companies are not eliminated yet.
const GROUP_V = [['sum', 'الشركات جنبا إلى جنب'], ['is', 'قائمة الدخل الموحدة'], ['bs', 'الميزانية الموحدة'], ['tb', 'ميزان المراجعة الموحد'], ['ic', 'مطابقة المعاملات بين الشركات']];
async function dashGroup(box, title) {
  const g = S.group; if (!g) { box.innerHTML = ''; return; }
  const pre = LS.get('waad.odp') || 'y', [from, to] = anPreset(pre), v = GROUP_V.some(x => x[0] === LS.get('waad.gdv')) ? LS.get('waad.gdv') : 'sum';
  box.innerHTML = `<div class="muted small" style="margin:12px 0">${esc(tr('جاري التحميل'))}…</div>`;
  const cos = g.companies || [], cname = id => (cos.find(c => c.id === id) || {}).name || '—';
  const by = (x, id) => n0((x.by_company || {})[id]);
  const coCols = cos.map(c => ({ t: c.name, r: 1, h: x => by(x, c.id) ? money(by(x, c.id)) : '' }));
  const elCol = { t: 'الاستبعادات', r: 1, h: x => n0(x.elim) ? `<span class="muted">${money(x.elim)}</span>` : '' };
  let body = '';
  if (v === 'sum') {
    const rows = await db.rpc('group_summary', { p_group: g.id, p_from: from, p_to: to }).catch(e => { throw e; });
    const tot = k => rows.reduce((a, r) => a + n0(r[k]), 0);
    body = `<div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(320px,1fr))">
        <div class="card"><h2>${esc(tr('المبيعات والربح حسب الشركة'))}</h2>${barChart(rows.map(r => ({ label: r.name, values: [Math.max(0, n0(r.sales)), Math.max(0, n0(r.profit))] })), [{ name: tr('المبيعات'), color: AN_C[0] }, { name: tr('صافي الربح'), color: AN_C[1] }], { fmt: x => money(x) })}</div>
        <div class="card"><h2>${esc(tr('النقد والبنك حسب الشركة'))}</h2>${hbars(rows.map(r => ({ label: r.name, v: n0(r.cash) })), x => money(x))}</div></div>
      <div class="card">${tbl([{ t: 'الشركة', h: r => `<b data-nt>${esc(r.name)}</b>` }, { t: 'المبيعات', r: 1, h: r => money(r.sales) }, { t: 'الفواتير', r: 1, h: r => `<span class="num">${r.sales_n}</span>` },
        { t: 'المحصّل', r: 1, h: r => money(r.collected) }, { t: 'المشتريات', r: 1, h: r => money(r.purchases) }, { t: 'الرواتب', r: 1, h: r => money(r.payroll) }, { t: 'الموظفون', r: 1, h: r => `<span class="num">${r.headcount}</span>` },
        { t: 'الإيرادات', r: 1, h: r => money(r.revenue) }, { t: 'المصروفات', r: 1, h: r => money(r.expense) }, { t: 'صافي الربح', r: 1, h: r => `<b class="${n0(r.profit) < 0 ? 'bad' : ''}">${money(r.profit)}</b>` }, { t: 'النقد والبنك', r: 1, h: r => money(r.cash) }], rows,
        { foot: `<td><b>${esc(tr('المجموعة'))}</b></td>${['sales'].map(k => `<td class="r"><b>${money(tot(k))}</b></td>`).join('')}<td class="r num"><b>${tot('sales_n')}</b></td>${['collected', 'purchases', 'payroll'].map(k => `<td class="r"><b>${money(tot(k))}</b></td>`).join('')}<td class="r num"><b>${tot('headcount')}</b></td>${['revenue', 'expense', 'profit', 'cash'].map(k => `<td class="r"><b>${money(tot(k))}</b></td>`).join('')}` })}</div>`;
  } else if (v === 'is') {
    const ord = { revenue: 0, cogs: 1, expense: 2, net_profit: 9 }, sec = { revenue: 'الإيرادات', cogs: 'تكلفة المبيعات', expense: 'المصروفات', net_profit: '' };
    const rows = (await db.rpc('group_income_statement', { p_group: g.id, p_from: from, p_to: to })).map((x, i) => [x, i]).sort((a, b) => ((ord[a[0].section] ?? 5) - (ord[b[0].section] ?? 5)) || a[1] - b[1]).map(x => x[0]);
    body = `<div class="card">${tbl([{ t: 'القسم', h: x => esc(tr(sec[x.section] || '')) }, { t: 'الحساب', h: x => x.section === 'net_profit' ? `<b>${esc(tr(x.name))}</b>` : `<span class="num">${esc(x.code)}</span> ${esc(x.name)}` },
      ...cos.map(c => ({ t: c.name, r: 1, h: x => x.section === 'net_profit' ? `<b>${money(by(x, c.id))}</b>` : by(x, c.id) ? money(by(x, c.id)) : '' })), elCol,
      { t: 'المجموعة', r: 1, h: x => x.section === 'net_profit' ? `<b class="${n0(x.amount) < 0 ? 'bad' : 'ok'}">${money(x.amount)}</b>` : `<b>${money(x.amount)}</b>` }], rows, { empty: 'لا توجد حركات' })}</div>`;
  } else if (v === 'bs') {
    const sec = { asset: 'الأصول', liab: 'الخصوم', equity: 'حقوق الملكية' };
    const rows = await db.rpc('group_balance_sheet', { p_group: g.id, p_as_of: to }), tot = k => rows.filter(x => x.section === k).reduce((a, x) => a + n0(x.amount), 0);
    body = `<div class="card">${tbl([{ t: 'القسم', h: x => esc(tr(sec[x.section])) }, { t: 'الحساب', h: x => `${x.code && x.code !== 'IC' ? `<span class="num">${esc(x.code)}</span> ` : ''}${x.code === 'IC' ? `<b class="bad">${esc(tr(x.name))}</b>` : esc(tr(x.name))}` }, ...coCols, elCol,
      { t: 'المجموعة', r: 1, h: x => `<b>${money(x.amount)}</b>` }], rows, { empty: 'لا توجد أرصدة' })}
      <p>${esc(tr('الأصول'))} <b class="num">${money(tot('asset'))}</b> · ${esc(tr('الخصوم وحقوق الملكية'))} <b class="num">${money(tot('liab') + tot('equity'))}</b></p></div>`;
  } else if (v === 'ic') {
    const rows = (await db.rpc('group_ic_recon', { p_group: g.id, p_from: from, p_to: to })).filter(r => n0(r.invoiced) || n0(r.recorded) || n0(r.receivable) || n0(r.payable));
    const diff = (a, b) => Math.abs(n0(a) - n0(b)) < 0.01 ? `<span class="badge ok">${esc(tr('مطابق'))}</span>` : `<span class="badge bad">${money(n0(a) - n0(b))}</span>`;
    body = `<div class="card"><div class="row" style="justify-content:space-between;gap:8px;flex-wrap:wrap;align-items:center"><p class="muted small" style="margin:0;max-width:640px">${esc(tr('تُعرف المعاملات بين الشركات من العميل أو المورد المعلَّم «شركة شقيقة». اضغط الزر مرة لتضيف كل شركة عميلا ومورّدا في أخواتها، أو اختر الشركة الشقيقة في بطاقة العميل أو المورد الموجود.'))}</p>
        <button type="button" class="btn sm pri" id="glk">${esc(tr('ربط الشركات كعملاء وموردين'))}</button></div></div>
      <div class="card">${tbl([{ t: 'البائع', h: r => `<b data-nt>${esc(r.seller_name)}</b>` }, { t: 'المشتري', h: r => `<span data-nt>${esc(r.buyer_name)}</span>` },
        { t: 'فوترها البائع', r: 1, h: r => money(r.invoiced) }, { t: 'سجّلها المشتري', r: 1, h: r => money(r.recorded) }, { t: 'الفرق', h: r => diff(r.invoiced, r.recorded) },
        { t: 'رصيد البائع المدين', r: 1, h: r => money(r.receivable) }, { t: 'رصيد المشتري الدائن', r: 1, h: r => money(r.payable) }, { t: 'الفرق', h: r => diff(r.receivable, r.payable) }], rows,
        { empty: 'لا توجد معاملات بين شركات المجموعة في الفترة' })}
      <p class="muted small">${esc(tr('المبالغ شاملة الضريبة وبعد المرتجعات. الفرق يعني مستندا سجلته شركة ولم تسجله أختها أو بمبلغ مختلف، ويظهر في الميزانية الموحدة سطرا مستقلا حتى يُصحّح.'))}</p></div>`;
  } else {
    const rows = await db.rpc('group_trial_balance', { p_group: g.id, p_as_of: to }), sd = rows.reduce((a, x) => a + n0(x.debit), 0), sc = rows.reduce((a, x) => a + n0(x.credit), 0);
    body = `<div class="card">${tbl([{ t: 'الحساب', h: x => `<span class="num">${esc(x.code === 'IC' ? '' : x.code)}</span> ${esc(tr(x.name))}` }, ...cos.map(c => ({ t: c.name, r: 1, h: x => by(x, c.id) ? money(by(x, c.id)) : '' })), elCol,
      { t: 'مدين', r: 1, h: x => n0(x.debit) ? money(x.debit) : '' }, { t: 'دائن', r: 1, h: x => n0(x.credit) ? money(x.credit) : '' }], rows,
      { empty: 'لا توجد حركات', foot: `<td colspan="${cos.length + 2}"><b>${esc(tr('الإجمالي'))}</b> ${Math.abs(sd - sc) < 0.01 ? `<span class="badge ok">${esc(tr('متوازن'))}</span>` : `<span class="badge bad">${esc(tr('غير متوازن'))}</span>`}</td><td class="r"><b>${money(sd)}</b></td><td class="r"><b>${money(sc)}</b></td>` })}
      <p class="muted small">${esc(tr('أعمدة الشركات: الرصيد المدين بالموجب والدائن بالسالب.'))}</p></div>`;
  }
  if (!box.isConnected) return;
  const vt = (GROUP_V.find(x => x[0] === v) || [])[1];
  box.innerHTML = `<div class="row" style="justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap;margin:${title ? '0' : '18px'} 0 6px">${title || `<h2 style="margin:0">${esc(tr('المجموعة'))}</h2>`}
      <div class="row" style="gap:6px;flex-wrap:wrap"><select class="gdv" style="width:auto" aria-label="${esc(tr('التقرير'))}">${GROUP_V.map(([x, l]) => opt(x, tr(l), v)).join('')}</select>
        <select class="dashp" style="width:auto" aria-label="${esc(tr('الفترة'))}">${DASH_P.map(([x, l]) => opt(x, tr(l), pre)).join('')}</select>
        <button type="button" class="btn sm" id="gx">Excel</button><button type="button" class="btn sm" id="gp">${esc(tr('طباعة'))}</button></div></div>
    <div class="muted small" style="margin-bottom:6px"><b data-nt>${esc(g.name)}</b> · ${v === 'bs' || v === 'tb' ? esc(tr('حتى تاريخ')) + ' ' + fdate(to) : fdate(from) + ' – ' + fdate(to)}</div>
    <div id="gbody">${body}</div>
    <p class="note small">${esc(tr('القوائم تجمع دفاتر شركات المجموعة حسب رمز الحساب، وتُستبعد المعاملات بين شركاتها (الإيراد مقابل التكلفة، والذمم المدينة مقابل الدائنة) دون أن تتغير دفاتر أي شركة. يُسوّى يدويا: الربح غير المحقق في بضاعة لم تُبع بعد خارج المجموعة، والأصول المشتراة من شركة شقيقة.'))}</p>`;
  if ($('#glk', box)) $('#glk', box).onclick = () => busy($('#glk', box), async () => { const n = await db.rpc('group_link_parties', { p_group: g.id }); toast(n ? tr('تم الربط') + ': ' + n : tr('الشركات مرتبطة بالفعل')); });
  $('.gdv', box).onchange = e => { LS.set('waad.gdv', e.target.value); dashGroup(box, title).catch(() => {}); };
  $('.dashp', box).onchange = e => { LS.set('waad.odp', e.target.value); dashGroup(box, title).catch(() => {}); };
  $('#gx', box).onclick = () => tablesXlsx($('#gbody', box), g.name + ' — ' + tr(vt) + ' ' + to);
  $('#gp', box).onclick = () => printBlock($('#gbody', box), g.name + ' — ' + tr(vt) + (v === 'bs' || v === 'tb' ? ' ' + tr('حتى') + ' ' + to : ' ' + from + ' – ' + to));
}
