'use strict';
/* ===== letter templates, rendered on an A4 sheet (210 × 297 mm). The sheet is always in the language chosen for the
   letter (data-nt keeps the UI translator away), so this file is skipped by i18n/extract.py. ===== */
function hijriOf(d, en) {
  try { return new Intl.DateTimeFormat(en ? 'en-GB-u-ca-islamic-umalqura' : 'ar-SA-u-ca-islamic-umalqura-nu-latn', { day: 'numeric', month: 'long', year: 'numeric' }).format(new Date(String(d).slice(0, 10) + 'T12:00:00')); } catch (e) { return ''; }
}
const gregOf = (d, en) => { const s = String(d || '').slice(0, 10); if (!s) return '—'; return en ? new Date(s + 'T12:00:00').toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' }) : s.slice(8, 10) + '/' + s.slice(5, 7) + '/' + s.slice(0, 4) + 'م'; };
// service length between two dates, inclusive of both ends
function servicePeriod(a, b) {
  const s = new Date(String(a).slice(0, 10) + 'T12:00:00'), e = new Date(String(b).slice(0, 10) + 'T12:00:00'); e.setDate(e.getDate() + 1);
  let y = e.getFullYear() - s.getFullYear(), m = e.getMonth() - s.getMonth(), d = e.getDate() - s.getDate();
  if (d < 0) { m--; d += new Date(e.getFullYear(), e.getMonth(), 0).getDate(); }
  if (m < 0) { y--; m += 12; }
  return { y, m, d };
}
function periodTxt(p, en) {
  if (en) return [[p.y, 'year'], [p.m, 'month'], [p.d, 'day']].filter(x => x[0]).map(([n, w]) => n + ' ' + w + (n === 1 ? '' : 's')).join(', ') || '0 days';
  const u = (n, one, two, few, many) => n === 1 ? one : n === 2 ? two : n <= 10 ? n + ' ' + few : n + ' ' + many;
  return [p.y && u(p.y, 'سنة', 'سنتان', 'سنوات', 'سنة'), p.m && u(p.m, 'شهر', 'شهران', 'أشهر', 'شهراً'), p.d && u(p.d, 'يوم', 'يومان', 'أيام', 'يوماً')].filter(Boolean).join(' و') || '0';
}

function letterHtml(l, { head = true } = {}) {
  const D = l.data || {}, c = D.company || {}, e = D.employee || {}, x = D.en || {}, en = l.lang === 'en', f = e.gender === 'f';
  const w = D.wage && typeof D.wage === 'object' ? D.wage : null, svc = l.kind === 'service';
  const logo = S.company && S.company.id === l.company_id ? S.company.logo : null;   // the company's current logo
  const g = (m, fm) => f ? fm : m, b = s => `<b>${esc(s)}</b>`;
  const comp = en ? (x.company || c.name) : c.name, name = en ? (x.name || e.full_name) : e.full_name, job = en ? (x.job || e.job_title) : e.job_title;
  let nat = e.nationality || ''; if (en && (nat === 'سعودي' || (e.is_saudi && !nat))) nat = 'Saudi'; else if (!en && f && nat === 'سعودي') nat = 'سعودية';
  const sar = v => `<span class="num">${money(v)}</span>`;
  const wageRows = w ? [[en ? 'Basic salary' : 'الراتب الأساسي', w.basic], [en ? 'Housing allowance' : 'بدل السكن', w.housing], [en ? 'Transport allowance' : 'بدل النقل', w.transport], [en ? 'Other allowances' : 'بدلات أخرى', w.other]]
    .filter(r => +r[1]).map(r => `<tr><td>${r[0]}</td><td class="amt">${sar(r[1])}</td></tr>`).join('') : '';
  const wageTbl = w ? `<table class="lt-tbl"><thead><tr><th>${en ? 'Item' : 'البند'}</th><th class="amt">${en ? 'Amount (SAR)' : 'المبلغ (ريال سعودي)'}</th></tr></thead><tbody>${wageRows}</tbody>
    <tfoot><tr><td>${en ? 'Total monthly salary' : 'إجمالي الراتب الشهري'}</td><td class="amt">${sar(w.gross)}</td></tr></tfoot></table>` : '';
  const idLbl = e.is_saudi ? (en ? 'National ID' : 'هوية وطنية') : (en ? 'Iqama' : 'إقامة');
  const title = svc ? (en ? 'Service Certificate' : 'شهادة خدمة') : w ? (en ? 'Salary Certificate' : 'تعريف بالراتب') : (en ? 'Employment Certificate' : 'خطاب تعريف');
  const to = l.addressee ? (en ? 'To: ' + esc(l.addressee) : 'السادة / ' + esc(l.addressee) + ' &nbsp; المحترمين') : (en ? 'To Whom It May Concern' : 'إلى من يهمه الأمر');
  let body;
  if (!en) {
    const who = `${g('السيد', 'السيدة')}/ ${b(name)}${nat ? '، الجنسية: ' + esc(nat) : ''}${e.national_id ? `، ${g('ويحمل', 'وتحمل')} ${idLbl} رقم (<span class="num">${esc(e.national_id)}</span>)` : ''}`;
    const jobTxt = job ? `بوظيفة (${b(job)})` : '';
    body = svc
      ? `<p>تشهد ${b(comp)} بأن ${who}، قد ${g('عمل', 'عملت')} لديها ${jobTxt} خلال الفترة من ${b(gregOf(e.hire_date))} إلى ${b(gregOf(e.end_date))}، ومدة ${g('خدمته', 'خدمتها')} ${b(periodTxt(servicePeriod(e.hire_date, e.end_date)))}، وكان آخر أجر شهري ${g('تقاضاه', 'تقاضته')} (${sar(w.gross)}) ريال سعودي، على النحو الآتي:</p>
         ${wageTbl}<p>وقد أُعطيت ${g('له', 'لها')} هذه الشهادة بناءً على ${g('طلبه', 'طلبها')} دون مقابل، وفقاً للمادة الرابعة والستين من نظام العمل.</p>`
      : `<p>تفيد ${b(comp)} بأن ${who}، ${g('يعمل', 'تعمل')} لديها ${jobTxt} اعتباراً من ${b(gregOf(e.hire_date))}، ${g('ولا يزال', 'ولا تزال')} على رأس العمل حتى تاريخه${w ? `، ${g('ويتقاضى', 'وتتقاضى')} راتباً شهرياً إجمالياً قدره (${sar(w.gross)}) ريال سعودي، على النحو الآتي:` : '.'}</p>
         ${wageTbl}<p>وقد أُعطي هذا الخطاب بناءً على ${g('طلبه', 'طلبها')} دون أدنى مسؤولية على المنشأة تجاه الغير.</p>`;
    body = `<p>السلام عليكم ورحمة الله وبركاته، وبعد:</p>${body.replace(/ ،/g, '،')}<p class="lt-close">وتفضلوا بقبول فائق الاحترام والتقدير،</p>`;
  } else {
    const t = g('Mr.', 'Ms.'), his = g('his', 'her'), His = g('His', 'Her');
    const who = `${t} ${b(name)}${nat ? ', ' + esc(nat) + ' national' : ''}${e.national_id ? `, holder of ${idLbl} No. <span class="num">${esc(e.national_id)}</span>` : ''}`;
    const jobTxt = job ? ` as ${b(job)}` : '';
    body = svc
      ? `<p>This is to certify that ${who}, was employed by ${b(comp)}${jobTxt} from ${b(gregOf(e.hire_date, 1))} to ${b(gregOf(e.end_date, 1))}, a period of service of ${b(periodTxt(servicePeriod(e.hire_date, e.end_date), 1))}. ${His} last monthly wage was SAR ${sar(w.gross)}, as follows:</p>
         ${wageTbl}<p>This certificate is issued upon ${his} request, free of charge, in accordance with Article 64 of the Saudi Labor Law.</p>`
      : `<p>This is to certify that ${who}, has been employed by ${b(comp)}${jobTxt} since ${b(gregOf(e.hire_date, 1))}, and is still in service as of the date of this letter.${w ? ` ${His} total monthly salary is SAR ${sar(w.gross)}, as follows:` : ''}</p>
         ${wageTbl}<p>This letter is issued upon ${his} request without any liability on the company towards third parties.</p>`;
    body = `<p>Dear Sir/Madam,</p>${body}<p class="lt-close">Yours faithfully,</p>`;
  }
  const ids = [c.cr_no && (en ? 'C.R. ' : 'س.ت ') + `<span class="num">${esc(c.cr_no)}</span>`, c.vat_no && (en ? 'VAT ' : 'الرقم الضريبي ') + `<span class="num">${esc(c.vat_no)}</span>`].filter(Boolean).join(' &nbsp;·&nbsp; ');
  return `<div class="a4${head ? '' : ' nohead'}" lang="${en ? 'en' : 'ar'}" dir="${en ? 'ltr' : 'rtl'}" data-nt>
    <header class="lt-head"><div class="lt-brand">${logo ? `<img class="lt-logo" src="${esc(logo)}" alt="">` : ''}<div><div class="lt-co">${esc(comp)}</div>${ids ? `<div class="lt-ids">${ids}</div>` : ''}</div></div>
      <div class="lt-meta"><div>${en ? 'Ref.' : 'الرقم'}: <span class="num">${esc(l.ref_no)}</span></div><div>${en ? 'Date' : 'التاريخ'}: <bdi class="num">${gregOf(D.date, en).replace(/م$/, '')}</bdi>${en ? '' : 'م'}</div><div>${en ? 'Hijri' : 'الموافق'}: <bdi>${esc(hijriOf(D.date, en).replace(/\s*(هـ|AH)$/, '') + (en ? ' AH' : 'هـ'))}</bdi></div></div></header>
    <main class="lt-main"><h1 class="lt-title">${title}</h1><p class="lt-to">${to}</p>${body}
      <div class="lt-sign"><div><div class="lt-by">${en ? 'Human Resources' : 'إدارة الموارد البشرية'}</div><div class="lt-line">${en ? 'Name' : 'الاسم'}:</div><div class="lt-line">${en ? 'Signature' : 'التوقيع'}:</div></div><div class="lt-stamp">${en ? 'Company stamp' : 'ختم المنشأة'}</div></div></main>
    <footer class="lt-foot">${c.address ? esc(c.address) + ' &nbsp;·&nbsp; ' : ''}${en ? 'Reference' : 'رقم مرجعي'} <span class="num">${esc(l.ref_no)}</span> — ${en ? 'not valid without signature and stamp' : 'لا يعتد به دون توقيع وختم المنشأة'}</footer></div>`;
}

/* print exactly one A4 page with zero page margins (the sheet carries its own) */
function printSheet(sheet) { const cp = sheet.cloneNode(true); cp.style.zoom = ''; printWith(cp, '@page{size:A4 portrait;margin:0}'); }

/* company logo: resize in the browser (≤ 800×300) and keep it as a small raster data URL */
async function imgToLogo(file) {
  const url = URL.createObjectURL(file);
  try {
    const im = new Image();
    await new Promise((ok, no) => { im.onload = ok; im.onerror = () => no(new Error('تعذّر قراءة الصورة')); im.src = url; });
    let w = im.naturalWidth || 600, h = im.naturalHeight || 240; const k = Math.min(1, 800 / w, 300 / h); w = Math.max(1, Math.round(w * k)); h = Math.max(1, Math.round(h * k));
    const cv = document.createElement('canvas'); cv.width = w; cv.height = h; const g = cv.getContext('2d'); g.drawImage(im, 0, 0, w, h);
    let d = cv.toDataURL('image/png');
    if (d.length > 190000) { const x = cv.toDataURL('image/webp', 0.9); if (x.startsWith('data:image/webp')) d = x; }
    if (d.length > 190000) { g.globalCompositeOperation = 'destination-over'; g.fillStyle = '#fff'; g.fillRect(0, 0, w, h); d = cv.toDataURL('image/jpeg', 0.85); }
    if (d.length > 190000) throw new Error('الصورة كبيرة جداً');
    return d;
  } finally { URL.revokeObjectURL(url); }
}

/* bilingual tax invoice / purchase bill printout: Arabic and English side by side whatever the interface language
   (a tax invoice must be in Arabic; the English is alongside) */
function invoiceSheet({ key, doc, lines, party, im, am, paid, cn }) {
  const c = S.company || {}, sale = key === 'sales', b2b = !!(party && party.vat_no), src = doc;
  if (cn) { doc = Object.assign({}, cn, { due_date: null, status: 'posted' }); paid = 0; }
  const enOf = s => { const t = trTo(s); return t !== s ? t : ''; };
  const two = (ar, en) => `<div>${esc(ar)}</div>${en && en !== ar ? `<div class="iv-en" dir="ltr">${esc(en)}</div>` : ''}`;
  const L = (ar, en) => `<div>${ar}</div><div class="iv-en" dir="ltr">${en}</div>`;
  const title = cn ? (b2b ? ['إشعار دائن للفاتورة الضريبية', 'Tax Invoice Credit Note'] : ['إشعار دائن للفاتورة الضريبية المبسطة', 'Simplified Tax Invoice Credit Note'])
    : sale ? (b2b ? ['فاتورة ضريبية', 'Tax Invoice'] : ['فاتورة ضريبية مبسطة', 'Simplified Tax Invoice']) : ['فاتورة مشتريات', 'Purchase Bill'];
  const qr = sale ? zatcaQr(doc, 118) : '';
  const nm = l => { if (l.item_id) { const it = im[l.item_id] || {}; return [it.name || '', it.name_en || enOf(it.name || '')]; } const a = am[l.account_code] || ''; return [l.account_code + ' — ' + a, l.account_code + ' — ' + enOf(a)]; };
  const vat = l => Math.round(n0(l.amount) * n0(l.vat_rate)) / 100;
  const row = (ar, en, v) => `<tr><td>${L(esc(ar), esc(en))}</td><td class="num r">${v}</td></tr>`;
  return `<div class="iv" dir="rtl" data-nt>
    <div class="iv-head"><div class="ph-brand">${c.logo ? `<img class="ph-logo" src="${esc(c.logo)}" alt="">` : ''}<div><div class="ph-co">${esc(c.name || '')}</div>${c.name_en ? `<div class="iv-en" dir="ltr"><b>${esc(c.name_en)}</b></div>` : ''}
      <div class="ph-ids">${c.vat_no ? 'الرقم الضريبي VAT No. <span class="num">' + esc(c.vat_no) + '</span>' : ''}${c.cr_no ? ' · س.ت C.R. <span class="num">' + esc(c.cr_no) + '</span>' : ''}</div>${addrLine(c) || c.address ? `<div class="ph-ids">${esc(addrLine(c) || c.address)}</div>` : ''}</div></div>
      <div class="iv-title">${L(title[0], title[1])}</div></div>
    <table class="iv-meta"><tbody>
      <tr><td>${cn ? L('رقم الإشعار', 'Credit note No.') : L('رقم الفاتورة', 'Invoice No.')}</td><td class="num">${esc(doc.no)}</td><td>${L('تاريخ الإصدار', 'Issue date')}</td><td class="num">${esc(fdate(doc.date))}${sale && doc.created_at ? ' <span class="small">' + esc(new Date(doc.created_at).toTimeString().slice(0, 5)) + '</span>' : ''}</td></tr>
      <tr><td>${L(sale ? 'العميل' : 'المورد', sale ? 'Customer' : 'Supplier')}</td><td>${two(party ? party.name : '', party ? (party.name_en || enOf(party.name)) : '')}</td>${cn ? `<td>${L('الفاتورة الأصلية', 'Original invoice')}</td><td class="num">${esc(src.no)} · ${esc(fdate(src.date))}</td>` : `<td>${L('تاريخ الاستحقاق', 'Due date')}</td><td class="num">${esc(fdate(doc.due_date))}</td>`}</tr>
      ${cn ? `<tr><td>${L('سبب الإصدار', 'Reason')}</td><td colspan="3">${esc(cn.reason)}</td></tr>` : ''}
      ${party && party.vat_no ? `<tr><td>${L(sale ? 'الرقم الضريبي للعميل' : 'الرقم الضريبي للمورد', sale ? "Buyer's VAT No." : "Supplier's VAT No.")}</td><td class="num">${esc(party.vat_no)}</td><td>${L('السجل التجاري', 'C.R. No.')}</td><td class="num">${esc(party.cr_no || '—')}</td></tr>` : ''}
      ${party && addrLine(party) ? `<tr><td>${L(sale ? 'عنوان العميل' : 'عنوان المورد', sale ? "Buyer's address" : "Supplier's address")}</td><td colspan="3">${esc(addrLine(party))}${party.country && party.country !== 'SA' ? ' — <span class="num">' + esc(party.country) + '</span>' : ''}</td></tr>` : ''}
      ${doc.supplier_ref ? `<tr><td>${L('رقم فاتورة المورد', "Supplier's ref.")}</td><td class="num" colspan="3">${esc(doc.supplier_ref)}</td></tr>` : ''}
      ${doc.status === 'void' ? `<tr><td colspan="4"><b>${L('ملغاة', 'VOID')}</b></td></tr>` : ''}</tbody></table>
    <table class="iv-lines"><thead><tr><th>${L('البند', 'Item')}</th><th class="r">${L('الكمية', 'Qty')}</th><th class="r">${L('سعر الوحدة', 'Unit price')}</th><th class="r">${L('المبلغ قبل الضريبة', 'Taxable amount')}</th><th class="r">${L('نسبة الضريبة', 'VAT rate')}</th><th class="r">${L('مبلغ الضريبة', 'VAT amount')}</th><th class="r">${L('الإجمالي شامل الضريبة', 'Total incl. VAT')}</th></tr></thead>
      <tbody>${lines.map(l => { const [a, e] = nm(l); return `<tr><td>${two(a, e)}</td><td class="num r">${+l.qty}</td><td class="num r">${money(l.unit_price)}</td><td class="num r">${money(l.amount)}</td><td class="num r">${n0(l.vat_rate)}%</td><td class="num r">${money(vat(l))}</td><td class="num r">${money(n0(l.amount) + vat(l))}</td></tr>`; }).join('')}</tbody></table>
    <div class="iv-bot">${qr ? `<div class="iv-qr">${qr}<div class="small">${L('رمز الفاتورة الإلكترونية', 'E-invoice QR')}</div></div>` : ''}<table class="iv-tot"><tbody>${row('الإجمالي قبل الضريبة', 'Total excl. VAT', money(doc.subtotal))}${row('ضريبة القيمة المضافة', 'VAT', money(doc.vat))}
      <tr class="iv-grand"><td>${cn ? L('إجمالي الإشعار', 'Credit total') : L('الإجمالي المستحق', 'Total due')}</td><td class="num r">${money(doc.total)} <span class="small">SAR</span></td></tr>
      ${doc.currency && !cn ? row('الإجمالي بالعملة', 'Total in currency', money(doc.fx_total) + ' ' + esc(doc.currency)) + row('سعر الصرف', 'Exchange rate', String(+doc.fx_rate)) : ''}
      ${n0(paid) ? row('المسدد', 'Paid', money(paid)) + row('المتبقي', 'Balance', money(n0(doc.total) - n0(paid))) : ''}</tbody></table></div>
    ${doc.note ? `<p class="small">${esc(doc.note)}</p>` : ''}
    ${sale && !cn && c.iban ? `<p class="small">${L('للتحويل: الآيبان <span class="num">' + esc(c.iban) + '</span>' + (ibanBank(c.iban) ? ' — ' + esc(ibanBank(c.iban)) : ''), 'Bank transfer: IBAN <span class="num">' + esc(c.iban) + '</span>')}</p>` : ''}
    <div class="iv-foot">${L('صدرت من نظام وعد · تاريخ الطباعة <span class="num">' + esc(today()) + '</span>', 'Issued by Waad · printed <span class="num">' + esc(today()) + '</span>')}</div></div>`;
}
