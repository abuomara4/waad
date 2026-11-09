'use strict';
/* ===== Company analytics: one page for the general manager, finance, HR, sales, purchasing and each manager's team.
   Every section comes from company_analytics() and is shown only to whoever may see it. Exports: PDF, Excel (one sheet
   per table), CSV, Word and a PNG of the charts — all built in the browser from the same model. ===== */

const AN_C = ['#3b82f6', '#c9a35c', '#ef4444', '#3fc392', '#8b5cf6', '#06b6d4'];
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
      charts: [{ t: 'الإيرادات والمصروفات شهرياً', bars: x.months.map(m => ({ label: mon(m.m), values: [m.revenue, m.expenses] })), series: ['الإيرادات', 'المصروفات'], f: 'money' }],
      tables: [{ t: 'الأداء الشهري', cols: [['الشهر'], ['الإيرادات', 'money'], ['المصروفات', 'money'], ['صافي الربح', 'money']], rows: x.months.map(m => [m.m, m.revenue, m.expenses, m.profit]) }] }); }
  if (d.finance) { const x = d.finance, ag = a => [n0(a && a.d30), n0(a && a.d60), n0(a && a.d90), n0(a && a.over)];
    S_.push({ k: 'finance', t: 'المالية', kpis: [K('ضريبة المخرجات', x.vat.output, 'money'), K('ضريبة المدخلات', x.vat.input, 'money'), K('صافي الضريبة المستحقة', n0(x.vat.output) - n0(x.vat.input), 'money'),
      K('ذمم عملاء متأخرة أكثر من 90 يوماً', ag(x.ar_aging)[3], 'money', null, 1), K('ذمم موردين متأخرة أكثر من 90 يوماً', ag(x.ap_aging)[3], 'money', null, 1)],
      charts: [{ t: 'التدفق النقدي شهرياً', bars: x.cash_flow.map(m => ({ label: mon(m.m), values: [m.in, m.out] })), series: ['داخل', 'خارج'], f: 'money' },
        { t: 'أكبر المصروفات', h: x.expense_accounts.slice(0, 10).map(a => ({ label: anNm(a), v: a.amount })), f: 'money' }],
      tables: [{ t: 'المصروفات حسب الحساب', cols: [['الحساب'], ['الاسم'], ['المبلغ', 'money']], rows: x.expense_accounts.map(a => [a.code, anNm(a), a.amount]) },
        { t: 'أعمار الذمم', cols: [['البيان'], ['حتى 30 يوماً', 'money'], ['31–60', 'money'], ['61–90', 'money'], ['أكثر من 90', 'money']], rows: [[tr('ذمم العملاء'), ...ag(x.ar_aging)], [tr('ذمم الموردين'), ...ag(x.ap_aging)]] },
        { t: 'التدفق النقدي', cols: [['الشهر'], ['داخل', 'money'], ['خارج', 'money'], ['الصافي', 'money']], rows: x.cash_flow.map(m => [m.m, m.in, m.out, n0(m.in) - n0(m.out)]) }] }); }
  if (d.sales) { const x = d.sales;
    S_.push({ k: 'sales', t: 'المبيعات', kpis: [K('المبيعات قبل الضريبة', x.total, 'money', x.total_prev, 0, col(x.months, 'total')), K('عدد الفواتير', x.count, 'num'), K('متوسط الفاتورة', x.count ? x.total / x.count : null, 'money'),
      K('المرتجعات', x.returns, 'money', null, 1), K('المحصّل', x.collected, 'money')],
      notes: x.total > 0 && x.customers.length ? [['حصة أكبر عميل من المبيعات', r2(x.customers[0].total / x.total * 100), 'pct', x.customers[0].total / x.total <= .3, 30]] : [],
      charts: [{ t: 'المبيعات شهرياً', bars: x.months.map(m => ({ label: mon(m.m), values: [m.total] })), series: ['المبيعات'], f: 'money' },
        { t: 'أكبر العملاء', h: x.customers.map(c => ({ label: anNm(c), v: c.total })), f: 'money' }],
      tables: [{ t: 'أكبر العملاء', cols: [['العميل'], ['الفواتير', 'num'], ['المبلغ', 'money']], rows: x.customers.map(c => [anNm(c), c.n, c.total]) },
        { t: 'الأصناف الأكثر مبيعاً', cols: [['الصنف'], ['الكمية', 'num'], ['المبلغ', 'money']], rows: x.items.map(i => [anNm(i), i.qty, i.total]) }] }); }
  if (d.supply) { const x = d.supply;
    S_.push({ k: 'supply', t: 'المشتريات والمخزون', kpis: [K('المشتريات قبل الضريبة', x.purchases, 'money', x.purchases_prev, 1, col(x.months, 'total')), K('المدفوع للموردين', x.paid, 'money'), K('قيمة المخزون', x.stock_value, 'money'),
      K('أصناف تحت حد الطلب', x.low_stock.length, 'num', null, 1), K('أصناف راكدة', x.slow.length, 'num', null, 1)],
      charts: [{ t: 'المشتريات شهرياً', bars: x.months.map(m => ({ label: mon(m.m), values: [m.total] })), series: ['المشتريات'], f: 'money' },
        { t: 'أكبر الموردين', h: x.suppliers.map(c => ({ label: anNm(c), v: c.total })), f: 'money' }],
      tables: [{ t: 'أكبر الموردين', cols: [['المورد'], ['الفواتير', 'num'], ['المبلغ', 'money']], rows: x.suppliers.map(c => [anNm(c), c.n, c.total]) },
        { t: 'أصناف تحت حد الطلب', cols: [['الرمز'], ['الصنف'], ['الكمية', 'num'], ['حد الطلب', 'num']], rows: x.low_stock.map(i => [i.code, anNm(i), i.qty, i.reorder]) },
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
  const note = n => `<div style="margin:6px 0"><div class="row small" style="gap:8px"><span class="${n[3] === false ? 'bad' : n[3] ? 'ok' : 'muted'}">●</span><span style="flex:1">${esc(tr(n[0]))}</span><b class="num">${esc(anFmt(n[1], n[2]))}</b>${n[4] != null ? `<span class="muted num" style="min-width:70px;text-align:end">${esc(tr('الهدف'))} ${esc(anFmt(n[4], n[2]))}</span>` : ''}</div>${n[4] != null ? bullet(n[1], n[4], { fmt: v => anFmt(v, n[2]), good: n[3] }) : ''}</div>`;
  const notes = (s.notes || []).length ? `<div class="card"><h2>${esc(tr('مؤشرات تستحق الانتباه'))}</h2>${s.notes.map(note).join('')}</div>` : '';
  return `<section class="ansec" data-an="${s.k}"><h2 class="anh">${esc(tr(s.t))}</h2><div class="grid">${s.kpis.map(kpi).join('')}</div>${notes}
    <div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(320px,1fr))">${s.charts.map(chart).join('')}</div>${s.tables.map(table).join('')}</section>`;
}

/* ----- exports ----- */
function anSave(blob, name) { const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 5000); }
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
function xlsxBook(sheets) {
  const x = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '');
  const colL = i => (i >= 26 ? String.fromCharCode(64 + Math.floor(i / 26)) : '') + String.fromCharCode(65 + i % 26), used = new Set();
  const nm = s => { let b = String(s).replace(/[\[\]:*?/\\]/g, ' ').slice(0, 28).trim() || 'Sheet', n = b, i = 2; while (used.has(n.toLowerCase())) n = b.slice(0, 25) + ' ' + i++; used.add(n.toLowerCase()); return n; };
  const rtl = document.documentElement.dir === 'rtl', names = sheets.map(s => nm(s.name));
  const sheetXml = rows => `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"${rtl ? ' rightToLeft="1"' : ''}/></sheetViews><cols><col min="1" max="1" width="34" customWidth="1"/><col min="2" max="${Math.max(2, ...rows.map(r => r.length))}" width="16" customWidth="1"/></cols><sheetData>${rows.map((r, ri) => `<row r="${ri + 1}">${r.map((v, ci) => typeof v === 'number' && ri > 0 && isFinite(v) ? `<c r="${colL(ci)}${ri + 1}" s="2"><v>${v}</v></c>` : `<c r="${colL(ci)}${ri + 1}" t="inlineStr"${ri === 0 ? ' s="1"' : ''}><is><t>${x(v)}</t></is></c>`).join('')}</row>`).join('')}</sheetData></worksheet>`;
  return zipStore([
    ['[Content_Types].xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${sheets.map((_, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join('')}<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>`],
    ['_rels/.rels', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'],
    ['xl/workbook.xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${names.map((n, i) => `<sheet name="${x(n)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join('')}</sheets></workbook>`],
    ['xl/_rels/workbook.xml.rels', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${sheets.map((_, i) => `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join('')}<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`],
    ['xl/styles.xml', '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Arial"/></font><font><b/><sz val="11"/><name val="Arial"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="3"><xf/><xf fontId="1" applyFont="1"/><xf numFmtId="4" applyNumberFormat="1"/></cellXfs></styleSheet>'],
    ...sheets.map((s, i) => [`xl/worksheets/sheet${i + 1}.xml`, sheetXml(s.rows)])]);
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
  const P_ = [['m', 'هذا الشهر'], ['lastm', 'الشهر الماضي'], ['q', 'هذا الربع'], ['y', 'هذه السنة'], ['ly', 'السنة الماضية'], ['l12', 'آخر 12 شهراً'], ['c', 'فترة مخصصة']];
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
      if (k === 'pdf') { const box = document.createElement('div'); box.innerHTML = `<p class="muted small">${esc(sub)}</p>` + sel.map(anSectionHtml).join(''); return printBlock(box, title); }
      if (k === 'xlsx') return anSave(xlsxBook(anFlat(sel)), fn('xlsx'));
      if (k === 'csv') return anSave(new Blob([anCsv(anFlat(sel))], { type: 'text/csv;charset=utf-8' }), fn('csv'));
      if (k === 'doc') return anSave(anWord(sel, title, sub), fn('doc'));
      if (k === 'png') return anSave(await anPng(sel, title, sub), fn('png'));
    } catch (er) { toast(er.message); }
  });
};
