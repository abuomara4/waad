'use strict';
/* ===== shared by the system and the admin site: file download, uncompressed ZIP, .xlsx writer, full company export ===== */
function anSave(blob, name) { const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 5000); }
function crc32(b) { let c, t = crc32.t; if (!t) { t = crc32.t = []; for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } }
  c = 0xFFFFFFFF; for (let i = 0; i < b.length; i++) c = t[(c ^ b[i]) & 255] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; }
function zipStore(files, type) {
  const enc = new TextEncoder(), parts = [], cen = []; let off = 0;
  for (const [name, text] of files) {
    const nb = enc.encode(name), d = typeof text === 'string' ? enc.encode(text) : text, crc = crc32(d), h = new DataView(new ArrayBuffer(30));
    h.setUint32(0, 0x04034b50, true); h.setUint16(4, 20, true); h.setUint16(6, 0x0800, true); h.setUint32(14, crc, true); h.setUint32(18, d.length, true); h.setUint32(22, d.length, true); h.setUint16(26, nb.length, true);
    parts.push(new Uint8Array(h.buffer), nb, d);
    const c = new DataView(new ArrayBuffer(46)); c.setUint32(0, 0x02014b50, true); c.setUint16(4, 20, true); c.setUint16(6, 20, true); c.setUint16(8, 0x0800, true); c.setUint32(16, crc, true); c.setUint32(20, d.length, true); c.setUint32(24, d.length, true); c.setUint16(28, nb.length, true); c.setUint32(42, off, true);
    cen.push(new Uint8Array(c.buffer), nb); off += 30 + nb.length + d.length;
  }
  const size = cen.reduce((a, x) => a + x.length, 0), e = new DataView(new ArrayBuffer(22));
  e.setUint32(0, 0x06054b50, true); e.setUint16(8, files.length, true); e.setUint16(10, files.length, true); e.setUint32(12, size, true); e.setUint32(16, off, true);
  return new Blob([...parts, ...cen, new Uint8Array(e.buffer)], { type: type || 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });
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

/* ----- full company export as a ZIP: one Excel file per section (a sheet per table) + the attachments as real files -----
   Names are [Arabic, English] pairs chosen by the interface language (this file is outside the i18n extract). */
const EXP_SECTIONS = [
  [['الموظفون والموارد البشرية', 'Employees and HR'], ['employees', 'departments', 'job_grades', 'employee_allowances', 'salary_history', 'contracts', 'employee_documents', 'letters', 'custody', 'custody_items', 'custody_names', 'clearance_marks',
    'penalties', 'penalty_deductions', 'violation_types', 'exit_visas', 'travel_tickets', 'insurance_policies', 'insurance_members', 'comp_credits', 'advance_deductions', 'work_sites', 'holidays', 'leave_types', 'policies', 'policy_acks',
    'signature_requests', 'form_issues', 'form_templates', 'guide_quiz_results']],
  [['الحضور والورديات', 'Attendance and shifts'], ['attendance', 'shifts', 'shift_roster', 'timesheets']],
  [['الرواتب', 'Payroll'], ['payroll_runs', 'payroll_lines']],
  [['الطلبات والاعتمادات', 'Requests and approvals'], ['requests', 'request_actions', 'workflows']],
  [['التوظيف والتدريب والتقييم', 'Hiring, training and reviews'], ['job_openings', 'candidates', 'trainings', 'training_plans', 'training_attendees', 'review_cycles', 'reviews']],
  [['المالية والمحاسبة', 'Finance and accounting'], ['accounts', 'journal_entries', 'journal_lines', 'cost_centers', 'budgets', 'currencies', 'payments', 'cheques', 'bank_recons', 'bank_cleared', 'petty_funds', 'petty_claims',
    'fixed_assets', 'asset_depreciation', 'fiscal_closings', 'period_locks', 'opening_batches', 'finance_permissions']],
  [['المبيعات والعملاء', 'Sales and customers'], ['parties', 'sales_orders', 'sales_order_lines', 'sales_invoices', 'sales_invoice_lines', 'delivery_notes', 'delivery_note_lines', 'credit_notes', 'credit_note_lines',
    'recurring_invoices', 'zatca_settings', 'zatca_docs']],
  [['المشتريات والموردون', 'Purchasing and suppliers'], ['purchase_orders', 'purchase_order_lines', 'purchase_bills', 'purchase_bill_lines', 'goods_receipts', 'goods_receipt_lines', 'rfqs', 'rfq_lines', 'rfq_quotes', 'rfq_quote_lines', 'supplier_ratings']],
  [['المخزون', 'Inventory'], ['items', 'item_units', 'item_serials', 'warehouses', 'stock_moves', 'stock_batches', 'stock_counts', 'stock_count_lines', 'stock_transfers', 'stock_transfer_lines']],
  [['التسويق والمشاريع', 'Marketing and projects'], ['crm_leads', 'crm_activities', 'marketing_campaigns', 'projects', 'project_tasks']],
  [['المنشأة والمستخدمون', 'Company and users'], ['companies', 'company_subscriptions', 'members', 'member_perms', 'invites', 'company_documents', 'vehicles', 'custom_fields', 'record_notes', 'code_lookups', 'audit_log']]];
const EXP_T = {
  employees: ['الموظفون', 'Employees'], departments: ['الأقسام', 'Departments'], job_grades: ['الدرجات الوظيفية', 'Job grades'], employee_allowances: ['البدلات', 'Allowances'], salary_history: ['سجل الرواتب', 'Salary history'],
  contracts: ['العقود', 'Contracts'], employee_documents: ['مستندات الموظفين', 'Employee documents'], letters: ['الخطابات', 'Letters'], custody: ['العهد', 'Custody'], custody_items: ['أصناف العهد', 'Custody items'],
  custody_names: ['مسميات العهد', 'Custody names'], clearance_marks: ['إخلاء الطرف', 'Clearance'], penalties: ['الجزاءات', 'Penalties'], penalty_deductions: ['خصومات الجزاءات', 'Penalty deductions'],
  violation_types: ['أنواع المخالفات', 'Violation types'], exit_visas: ['تأشيرات الخروج', 'Exit visas'], travel_tickets: ['تذاكر السفر', 'Travel tickets'], insurance_policies: ['وثائق التأمين', 'Insurance policies'],
  insurance_members: ['المؤمن عليهم', 'Insured members'], comp_credits: ['أيام التعويض', 'Comp days'], advance_deductions: ['أقساط السلف', 'Advance deductions'], work_sites: ['مواقع العمل', 'Work sites'],
  holidays: ['العطل الرسمية', 'Holidays'], leave_types: ['أنواع الإجازات', 'Leave types'], policies: ['السياسات', 'Policies'], policy_acks: ['الإقرار بالسياسات', 'Policy acknowledgements'],
  signature_requests: ['التوقيعات', 'Signatures'], form_issues: ['النماذج المصدرة', 'Issued forms'], form_templates: ['قوالب النماذج', 'Form templates'], guide_quiz_results: ['نتائج اختبار الدليل', 'Guide quiz results'],
  attendance: ['الحضور', 'Attendance'], shifts: ['الورديات', 'Shifts'], shift_roster: ['جدول الورديات', 'Shift roster'], timesheets: ['ساعات العمل', 'Timesheets'],
  payroll_runs: ['مسيرات الرواتب', 'Payroll runs'], payroll_lines: ['تفاصيل المسيرات', 'Payroll lines'], requests: ['الطلبات', 'Requests'], request_actions: ['إجراءات الطلبات', 'Request actions'], workflows: ['مسارات الاعتماد', 'Workflows'],
  job_openings: ['الوظائف الشاغرة', 'Job openings'], candidates: ['المرشحون', 'Candidates'], trainings: ['الدورات', 'Trainings'], training_plans: ['خطط التدريب', 'Training plans'], training_attendees: ['حضور الدورات', 'Training attendees'],
  review_cycles: ['دورات التقييم', 'Review cycles'], reviews: ['التقييمات', 'Reviews'], accounts: ['دليل الحسابات', 'Chart of accounts'], journal_entries: ['القيود', 'Journal entries'], journal_lines: ['سطور القيود', 'Journal lines'],
  cost_centers: ['مراكز التكلفة', 'Cost centers'], budgets: ['الموازنات', 'Budgets'], currencies: ['العملات', 'Currencies'], payments: ['المدفوعات والمقبوضات', 'Payments'], cheques: ['الشيكات', 'Cheques'],
  bank_recons: ['التسويات البنكية', 'Bank reconciliations'], bank_cleared: ['الحركات المسواة', 'Cleared items'], petty_funds: ['العهد النقدية', 'Petty cash funds'], petty_claims: ['مصروفات العهد النقدية', 'Petty cash claims'],
  fixed_assets: ['الأصول الثابتة', 'Fixed assets'], asset_depreciation: ['الإهلاك', 'Depreciation'], fiscal_closings: ['إقفال السنوات', 'Year-end closings'], period_locks: ['إقفال الفترات', 'Period locks'],
  opening_batches: ['الأرصدة الافتتاحية', 'Opening balances'], finance_permissions: ['صلاحيات المالية', 'Finance permissions'], parties: ['العملاء والموردون', 'Customers and suppliers'],
  sales_orders: ['أوامر البيع', 'Sales orders'], sales_order_lines: ['سطور أوامر البيع', 'Sales order lines'], sales_invoices: ['فواتير المبيعات', 'Sales invoices'], sales_invoice_lines: ['سطور فواتير المبيعات', 'Sales invoice lines'],
  delivery_notes: ['سندات التسليم', 'Delivery notes'], delivery_note_lines: ['سطور سندات التسليم', 'Delivery note lines'], credit_notes: ['الإشعارات الدائنة', 'Credit notes'], credit_note_lines: ['سطور الإشعارات', 'Credit note lines'],
  recurring_invoices: ['الفواتير المتكررة', 'Recurring invoices'], zatca_settings: ['إعدادات زاتكا', 'ZATCA settings'], zatca_docs: ['سجل زاتكا', 'ZATCA log'],
  purchase_orders: ['أوامر الشراء', 'Purchase orders'], purchase_order_lines: ['سطور أوامر الشراء', 'PO lines'], purchase_bills: ['فواتير المشتريات', 'Purchase bills'], purchase_bill_lines: ['سطور فواتير المشتريات', 'Bill lines'],
  goods_receipts: ['سندات الاستلام', 'Goods receipts'], goods_receipt_lines: ['سطور الاستلام', 'Receipt lines'], rfqs: ['طلبات عروض الأسعار', 'RFQs'], rfq_lines: ['سطور طلبات العروض', 'RFQ lines'],
  rfq_quotes: ['عروض الموردين', 'Supplier quotes'], rfq_quote_lines: ['سطور عروض الموردين', 'Quote lines'], supplier_ratings: ['تقييم الموردين', 'Supplier ratings'],
  items: ['الأصناف', 'Items'], item_units: ['وحدات الأصناف', 'Item units'], item_serials: ['الأرقام التسلسلية', 'Serial numbers'], warehouses: ['المستودعات', 'Warehouses'], stock_moves: ['حركات المخزون', 'Stock moves'],
  stock_batches: ['الدفعات', 'Batches'], stock_counts: ['الجرد', 'Stock counts'], stock_count_lines: ['سطور الجرد', 'Count lines'], stock_transfers: ['التحويلات', 'Transfers'], stock_transfer_lines: ['سطور التحويلات', 'Transfer lines'],
  crm_leads: ['العملاء المحتملون', 'Leads'], crm_activities: ['أنشطة العملاء', 'CRM activities'], marketing_campaigns: ['الحملات', 'Campaigns'], projects: ['المشاريع', 'Projects'], project_tasks: ['مهام المشاريع', 'Project tasks'],
  companies: ['بيانات المنشأة', 'Company'], company_subscriptions: ['الاشتراك', 'Subscription'], members: ['المستخدمون', 'Users'], member_perms: ['الصلاحيات', 'Permissions'], invites: ['الدعوات', 'Invites'],
  company_documents: ['مستندات المنشأة', 'Company documents'], vehicles: ['السيارات', 'Vehicles'], custom_fields: ['الحقول المخصصة', 'Custom fields'], record_notes: ['الملاحظات', 'Notes'], code_lookups: ['محاولات رمز المنشأة', 'Code lookups'],
  audit_log: ['سجل التدقيق', 'Audit log'],
  document_files: ['مرفقات المستندات', 'Document files'], contract_files: ['مرفقات العقود', 'Contract files'], custody_files: ['مرفقات العهد', 'Custody files'], request_attachments: ['مرفقات الطلبات', 'Request attachments'],
  travel_files: ['مرفقات السفر', 'Travel files'], candidate_files: ['مرفقات المرشحين', 'Candidate files'], company_document_files: ['مرفقات مستندات المنشأة', 'Company document files'], vehicle_files: ['مرفقات السيارات', 'Vehicle files'] };
const EXP_C = { name: ['الاسم', 'Name'], full_name: ['الاسم الكامل', 'Full name'], emp_no: ['الرقم الوظيفي', 'Employee no.'], national_id: ['رقم الهوية', 'ID number'], nationality: ['الجنسية', 'Nationality'],
  job_title: ['المسمى الوظيفي', 'Job title'], hire_date: ['تاريخ المباشرة', 'Hire date'], end_date: ['تاريخ الانتهاء', 'End date'], basic: ['الراتب الأساسي', 'Basic salary'], housing: ['بدل السكن', 'Housing'],
  transport: ['بدل النقل', 'Transport'], phone: ['الجوال', 'Mobile'], email: ['البريد الإلكتروني', 'E-mail'], iban: ['الآيبان', 'IBAN'], date: ['التاريخ', 'Date'], no: ['الرقم', 'No.'], code: ['الرمز', 'Code'],
  amount: ['المبلغ', 'Amount'], total: ['الإجمالي', 'Total'], subtotal: ['قبل الضريبة', 'Subtotal'], vat: ['الضريبة', 'VAT'], qty: ['الكمية', 'Qty'], price: ['السعر', 'Price'], status: ['الحالة', 'Status'],
  note: ['ملاحظة', 'Note'], reason: ['السبب', 'Reason'], kind: ['النوع', 'Kind'], type: ['النوع', 'Type'], title: ['العنوان', 'Title'], description: ['الوصف', 'Description'], start_date: ['تاريخ البداية', 'Start date'],
  due_date: ['تاريخ الاستحقاق', 'Due date'], expiry_date: ['تاريخ الانتهاء', 'Expiry date'], file_name: ['اسم الملف', 'File name'], debit: ['مدين', 'Debit'], credit: ['دائن', 'Credit'], memo: ['البيان', 'Memo'],
  month: ['الشهر', 'Month'], days: ['الأيام', 'Days'], role: ['الصلاحية', 'Role'], created_at: ['تاريخ الإنشاء', 'Created at'] };
const expPick = p => LANG === 'en' ? p[1] : p[0];
const expB64 = s => { const b = atob(s), u = new Uint8Array(b.length); for (let i = 0; i < b.length; i++) u[i] = b.charCodeAt(i); return u; };
const expSafe = s => String(s || '').replace(/[\\/:*?"<>|\u0000-\u001f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 80);
// d = the result of company_export / platform_company_export; returns a ZIP Blob
async function exportZip(d, companyName) {
  const tables = d.tables || {}, files = [], done = new Set(), ar = LANG !== 'en';
  const cell = v => v == null ? '' : typeof v === 'number' ? v : typeof v === 'boolean' ? (v ? (ar ? 'نعم' : 'Yes') : (ar ? 'لا' : 'No')) : (typeof v === 'object' ? JSON.stringify(v) : String(v)).slice(0, 32000);
  const sheet = t => { const rows = tables[t]; done.add(t); if (!rows || !rows.length) return null;
    const all = [...new Set(rows.flatMap(r => Object.keys(r)))].filter(c => c !== 'company_id' && c !== 'data' && !(t === 'companies' && c === 'logo'));
    const ids = all.filter(c => c === 'id' || /_id$/.test(c)), cols = [...all.filter(c => !ids.includes(c)), ...ids];
    return { name: expPick(EXP_T[t] || [t, t]), rows: [cols.map(c => EXP_C[c] ? expPick(EXP_C[c]) : c), ...rows.map(r => cols.map(c => cell(r[c])))] }; };
  const index = [];
  EXP_SECTIONS.forEach(([sn, list], i) => { const sh = list.map(sheet).filter(Boolean); if (!sh.length) return;
    const fname = String(i + 1).padStart(2, '0') + ' ' + expPick(sn) + '.xlsx'; index.push([fname, sh.map(s => s.name + ' (' + (s.rows.length - 1) + ')').join('، ')]);
    files.push([fname, sh]); });
  const fileT = Object.keys(tables).filter(t => (tables[t] || []).some(r => r && 'file_name' in r));
  const rest = Object.keys(tables).filter(t => !done.has(t) && !fileT.includes(t)).sort().map(sheet).filter(Boolean);
  if (rest.length) { const fname = '99 ' + (ar ? 'أخرى' : 'Other') + '.xlsx'; index.push([fname, rest.map(s => s.name).join('، ')]); files.push([fname, rest]); }
  // attachments: a list sheet + the files themselves
  const att = [], attRows = [[ar ? 'المجلد' : 'Folder', ar ? 'اسم الملف' : 'File name', ar ? 'المسار في الملف المضغوط' : 'Path in the ZIP', 'id']], used = new Set();
  for (const t of fileT) { const folder = expSafe(expPick(EXP_T[t] || [t, t]));
    for (const r of tables[t]) { let fn = expSafe(r.file_name) || String(r.id).slice(0, 8), path = (ar ? 'المرفقات/' : 'Attachments/') + folder + '/' + fn;
      if (used.has(path)) path = path.replace(/(\.[^./]*)?$/, m => '-' + String(r.id).slice(0, 6) + m); used.add(path);
      attRows.push([folder, r.file_name || '', r.data ? path : (ar ? 'غير مضمّن' : 'not included'), r.id]);
      if (r.data) try { att.push([path, expB64(r.data)]); } catch (e) { /* a damaged file is listed but skipped */ } } }
  if (attRows.length > 1) { const fname = '98 ' + (ar ? 'قائمة المرفقات' : 'Attachments list') + '.xlsx'; index.push([fname, String(attRows.length - 1)]); files.push([fname, [{ name: ar ? 'المرفقات' : 'Attachments', rows: attRows }]]); }
  const entries = [];
  for (const [fname, sheets] of files) entries.push([fname, new Uint8Array(await xlsxBook(sheets).arrayBuffer())]);
  const readme = [(ar ? 'نسخة كاملة من بيانات المنشأة: ' : 'Full copy of the company data: ') + companyName, (ar ? 'تاريخ التصدير: ' : 'Exported at: ') + String(d.exported_at || '').slice(0, 19).replace('T', ' '), '',
    ...index.map(([f, s]) => f + '\n   ' + s), '', ar ? 'كل ملف Excel قسم، وكل ورقة فيه جدول. الأعمدة id وما ينتهي بـ _id تربط الجداول ببعضها. المرفقات الأصلية في مجلد «المرفقات».' : 'Each Excel file is a section and each sheet a table. The id and *_id columns link the tables. The original attachments are in the «Attachments» folder.'].join('\n');
  return zipStore([[ar ? 'اقرأني.txt' : 'README.txt', '﻿' + readme], ...entries, ...att], 'application/zip');
}
