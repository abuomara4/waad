'use strict';
/* The printed words an invoice uses (Arabic and English) are patterns here, not interface text: this file is excluded from the i18n extract. */
/* the printed text of an invoice (Arabic or English, any digits) → what matters on it. Pure: tested in app/tests/qrread_test.js */
function receiptFromText(text) {
  const norm = String(text || '').replace(/[٠-٩]/g, d => d.charCodeAt(0) - 0x660).replace(/[۰-۹]/g, d => d.charCodeAt(0) - 0x6F0)
    .replace(/٫/g, '.').replace(/٬/g, ',').replace(/[‎‏‪-‮⁦-⁩]/g, '');
  const lines = norm.split(/\r?\n/).map(l => l.replace(/\s+/g, ' ').trim()).filter(Boolean), low = l => l.toLowerCase();
  // amounts as printed: 1,150.00 · 1150,50 · 1150 (thousands commas dropped, a lone decimal comma read as a point)
  const nums = l => (l.match(/\d[\d,]*(?:\.\d{1,3})?/g) || []).map(x => { if (x.includes('.')) return +x.replace(/,/g, ''); if (/^\d{1,3}(,\d{3})+$/.test(x)) return +x.replace(/,/g, '');
      if (/^\d+,\d{1,2}$/.test(x)) return +x.replace(',', '.'); return +x.replace(/,/g, ''); }).filter(n => isFinite(n));
  const money = l => nums(l.replace(/\d+(?:\.\d+)?\s*[%٪]|[%٪]\s*\d+(?:\.\d+)?/g, ' ')).filter(n => n < 1e8 && !/^3\d{13}3$/.test(String(n)));   // a rate (15%) is not an amount
  const out = { src: 'text' };
  // VAT number: 15 digits starting and ending with 3 (spaces or dashes inside are allowed)
  for (const l of lines) { const m = l.replace(/[\s-]/g, '').match(/3\d{13}3/); if (m) { out.vat = m[0]; break; } }
  // total: the strongest label wins, the last amount on its line (or the next line)
  const TOT = [/الإجمالي شامل|الاجمالي شامل|المجموع شامل|الإجمالي مع الضريبة|الاجمالي مع الضريبة|total\s*(incl|inc\.|including|with)/i, /الإجمالي المستحق|الاجمالي المستحق|المبلغ المستحق|المستحق|grand\s*total|amount\s*due|total\s*due|balance\s*due/i,
    /صافي|الصافي|net\s*total|net\s*amount/i, /الإجمالي|الاجمالي|إجمالي|اجمالي|المجموع|مجموع|total/i, /المبلغ|amount/i];
  const notTotal = /قبل الضريبة|بدون ضريبة|غير شامل|excl|before\s*vat|sub\s*-?\s*total|المجموع الفرعي|خصم|discount|ضريبة|vat|tax|qty|كمية/i;
  let labeled = false;
  for (const re of TOT) { for (let i = lines.length - 1; i >= 0; i--) { const l = lines[i]; if (!re.test(l) || (re !== TOT[0] && notTotal.test(l))) continue;
      let ns = money(l); if (!ns.length && lines[i + 1]) ns = money(lines[i + 1]); if (ns.length) { out.total = ns[ns.length - 1]; labeled = true; break; } } if (out.total != null) break; }
  if (out.total == null) { const all = lines.flatMap(l => money(l).filter(n => /\./.test(String(n)) || n >= 1)); if (all.length) out.total = Math.max(...all); }
  // VAT amount: a tax line that is not the VAT number or the rate
  for (const l of lines) { if (!/ضريبة|الضريبة|vat|tax/i.test(l) || /رقم|الرقم|\bno\b|number|registration|تسجيل|قبل|بدون|غير شامل|شامل|before|excl|incl|sub\s*-?\s*total|المجموع|الإجمالي|الاجمالي|total|invoice|فاتورة/i.test(l)) continue;
    const ns = money(l).filter(n => out.total == null || n < out.total); if (ns.length) { out.tax = ns[ns.length - 1]; break; } }
  // date: year first or day first; a Hijri year (14xx) is left for the employee
  for (const l of lines) { let m = l.match(/(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})/), d = null;
    if (m) d = [m[1], m[2], m[3]]; else if ((m = l.match(/(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2})/))) d = [m[3], m[2], m[1]];
    if (d && +d[1] >= 1 && +d[1] <= 12 && +d[2] >= 1 && +d[2] <= 31) { out.date = `${d[0]}-${String(d[1]).padStart(2, '0')}-${String(d[2]).padStart(2, '0')}`; break; } }
  // invoice number
  for (const l of lines) { const m = l.match(/(?:رقم الفاتورة|فاتورة رقم|رقم الإيصال|\binv(?:oice)?\s*(?:no\.?|number|#)|\breceipt\s*(?:no\.?|number|#))\s*[:#.]?\s*([A-Za-z0-9][A-Za-z0-9\-/]{1,30})/i); if (m) { out.ref = m[1]; break; } }
  // seller: a name near the top (words, not numbers or the document title)
  const title = /فاتورة|ضريبية|مبسطة|invoice|receipt|إيصال|ايصال|سند|tax|vat|tel|هاتف|جوال|www|@|cr\b|س\.ت|سجل تجاري|date|تاريخ/i, firm = /مؤسسة|شركة|مطعم|مركز|مصنع|متجر|محل|صيدلية|مستشفى|مجمع|معرض|مكتب|بقالة|سوبر|co\.|company|est\.?|llc|ltd|trading|restaurant|store|market/i;
  const top = lines.slice(0, 8).filter(l => !title.test(l) && (l.match(/[A-Za-z؀-ۿ]/g) || []).length >= 3 && (l.match(/\d/g) || []).length <= l.length / 3);
  out.seller = (top.find(l => firm.test(l)) || top[0] || '').slice(0, 120);
  // an invoice, not just any paper with numbers: an invoice word or its VAT number / invoice number, a total under a total label,
  // and a date, number, VAT number or currency
  const word = /فاتورة|فاتوره|إيصال|ايصال|invoice|receipt|cash\s*memo|\bbill\b/i.test(norm), cur = /\bSAR\b|ر\.?\s?س|ريال|\uFDFC|\u20C1|\bSR\b/i.test(norm);
  out.invoice = labeled && out.total > 0 && (word || !!out.vat || !!out.ref) && !!(out.date || out.ref || out.vat || cur);
  return out;
}

/* is it really an invoice, and does it add up? ZATCA QR: all its fields present; printed text: the invoice signs above.
   Warnings for the employee and the approver: VAT not 15% of the amount, VAT above the total, a future or year-old date. */
function receiptCheck(z, today) {
  const t = today || new Date(Date.now() + 3 * 3600e3).toISOString().slice(0, 10), warn = [];
  const ok = z.src === 'text' ? !!z.invoice : !!(z.seller && /^3\d{13}3$/.test(z.vat || z.vat_no || '') && z.total > 0 && (z.time || z.date));
  if (ok) {
    if (z.tax != null && z.total != null) { if (z.tax > z.total) warn.push('tax_total'); else if (z.tax > 0 && Math.abs(z.tax / (z.total - z.tax) - 0.15) > 0.01) warn.push('rate'); }
    if (z.date && z.date > t) warn.push('future');
    const yearAgo = new Date(new Date(t).getTime() - 365 * 864e5).toISOString().slice(0, 10); if (z.date && z.date < yearAgo) warn.push('old');
  }
  return { ok, kind: z.src === 'text' ? 'text' : 'zatca', warn };
}

