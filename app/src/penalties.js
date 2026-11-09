'use strict';
/* ===== violations and disciplinary penalties (Labor Law Arts. 66–73, model regulation tables) ===== */
const PEN_CAT = { time: 'مخالفات تتعلق بمواعيد العمل', org: 'مخالفات تتعلق بتنظيم العمل', conduct: 'مخالفات تتعلق بسلوك العامل' };
const PEN_ST = { open: ['قيد التحقيق', 'wait'], applied: ['صدر الجزاء', 'bad'], dropped: ['حُفظت', 'info'], overturned: ['أُلغي بالتظلم', 'ok'] };
const PEN_ORD = ['', 'الأولى', 'الثانية', 'الثالثة', 'الرابعة'];
const PEN_EXTRA = { late: 'بالإضافة إلى حسم أجر مدة التأخر', absence: 'بالإضافة إلى حسم أجر مدة الغياب', left: 'بالإضافة إلى حسم أجر مدة ترك العمل' };
const INV_MODE = { written: 'تحقيق كتابي', oral: 'استجواب شفهي (مخالفة بسيطة)', refused: 'امتنع العامل عن الإدلاء بأقواله' };
function penLabel(a) {
  if (a === 'W') return 'إنذار كتابي';
  if (/^p\d+$/.test(a)) return 'حسم ' + a.slice(1) + '% من أجر يوم';
  if (/^d\d+$/.test(a)) { const n = +a.slice(1); return 'حسم أجر ' + (n === 1 ? 'يوم' : n === 2 ? 'يومين' : n + ' أيام'); }
  return { defer: 'تأجيل الترقية أو الحرمان من العلاوة لمرة واحدة', defer80: 'تأجيل الترقية أو الحرمان من العلاوة لمرة واحدة، مع إنذار بالفصل وفق المادة 80',
    eos: 'الفصل من العمل مع المكافأة', a80: 'الفصل دون مكافأة أو إشعار أو تعويض وفق المادة 80', '-': '—' }[a] || a;
}
const penBadge = s => `<span class="badge ${PEN_ST[s][1]}">${esc(PEN_ST[s][0])}</span>`;
const VTYPES = async () => cache.vt || (cache.vt = await db.get('violation_types', { order: 'code' }));

const isDismiss = a => a === 'eos' || a === 'a80';

VIEWS['#/penalties'] = async (page, arg, q) => {
  if (!isHR() && !has('finance')) { page.innerHTML = '<div class="note">هذه الصفحة للموارد البشرية.</div>'; return; }
  if (arg) return penDetail(page, arg);
  const tab = ['cases', 'register', 'table'].includes(q.get('t')) ? q.get('t') : 'cases';
  const [vt, em, ps] = await Promise.all([VTYPES(), employeesMap(true), db.get('penalties', { company_id: 'eq.' + S.cid, order: 'created_at.desc' })]);
  const vm = {}; vt.forEach(v => vm[v.code] = v);
  const seg = `<div class="seg" style="margin-bottom:14px">${[['cases', 'المخالفات'], ['register', 'سجل الغرامات (م73)'], ['table', 'جدول المخالفات والجزاءات']].map(t => `<a href="#/penalties?t=${t[0]}" class="${t[0] === tab ? 'on' : ''}">${t[1]}</a>`).join('')}</div>`;
  const head = `<div class="head"><div><h1>المخالفات والجزاءات</h1><div class="muted">وفق جداول اللائحة النموذجية لتنظيم العمل والمواد 66–73 من نظام العمل</div></div>${isHR() ? '<button class="btn pri" id="pnew">+ تسجيل مخالفة</button>' : ''}</div>`;
  if (tab === 'cases') {
    const c = st => ps.filter(p => p.status === st).length, grv = ps.filter(p => p.griev_on && !p.griev_result).length;
    page.innerHTML = head + seg + `<div class="grid" style="margin-bottom:16px">
        <div class="card kpi"><div class="muted small">قيد التحقيق</div><div class="v num">${c('open')}</div></div>
        <div class="card kpi"><div class="muted small">تظلمات بانتظار البت</div><div class="v num ${grv ? 'bad' : ''}">${grv}</div></div>
        <div class="card kpi"><div class="muted small">جزاءات صادرة</div><div class="v num">${c('applied')}</div></div></div>
      ${tbl([{ t: 'الموظف', h: p => esc((em[p.employee_id] || {}).full_name || '') }, { t: 'المخالفة', h: p => `<span class="num muted small">${esc(p.code)}</span> <span class="small">${esc((vm[p.code] || {}).title || '')}</span>` },
        { t: 'التاريخ', h: p => fdate(p.occurred_on) }, { t: 'الجزاء', h: p => `<span class="small">المرة ${PEN_ORD[p.step]}: ${esc(penLabel(p.action))}</span>` }, { t: 'الغرامة', r: 1, h: p => n0(p.fine) ? money(p.fine) : '—' },
        { t: 'الحالة', h: p => penBadge(p.status) + (p.griev_on && !p.griev_result ? ' <span class="badge bad">تظلم</span>' : '') }], ps, { empty: 'لا توجد مخالفات مسجلة', onRow: true }).replace('class="tw"', 'class="tw wrapcells"')}`;
    bindRows(page, ps, p => location.hash = '#/penalties/' + p.id);
  } else if (tab === 'register') {
    const fs = ps.filter(p => p.status === 'applied' && n0(p.fine) > 0);
    const ded = fs.length ? await db.get('penalty_deductions', { penalty_id: 'in.(' + fs.map(p => p.id).join(',') + ')' }).catch(() => []) : [];
    const paid = id => ded.filter(d => d.penalty_id === id).reduce((a, d) => a + n0(d.amount), 0);
    page.innerHTML = head + seg + `<div class="row" style="justify-content:space-between;margin-bottom:10px"><p class="muted small" style="margin:0">المادة 73: تُقيَّد الغرامات في سجل خاص، ولا يُتصرف فيها إلا فيما يعود بالنفع على عمال المنشأة. تُسجَّل محاسبياً في حساب «غرامات العاملين» وليست إيراداً للمنشأة.</p><button class="btn sm" id="rgp">طباعة</button></div>
      <div id="rgb" class="wrapcells">${tbl([{ t: 'اسم العامل', h: p => esc((em[p.employee_id] || {}).full_name || '') }, { t: 'مقدار الأجر الشهري', r: 1, h: p => money(n0(p.daily_wage) * 30) }, { t: 'مقدار الغرامة', r: 1, h: p => money(p.fine) },
        { t: 'سبب توقيعها', h: p => `<span class="small">${esc((vm[p.code] || {}).title || p.code)}</span>` }, { t: 'تاريخ التوقيع', h: p => fdate(p.notified_on) }, { t: 'المحسوم', r: 1, h: p => money(paid(p.id)) }], fs,
        { empty: 'لا توجد غرامات', foot: `<td colspan="2">الإجمالي</td><td class="r num">${money(fs.reduce((a, p) => a + n0(p.fine), 0))}</td><td colspan="2"></td><td class="r num">${money(fs.reduce((a, p) => a + paid(p.id), 0))}</td>` })}</div>`;
    $('#rgp', page).onclick = () => printBlock($('#rgb', page), 'سجل الغرامات — المادة 73');
  } else {
    const admin = has('owner', 'admin');
    page.innerHTML = head + seg + `${admin ? `<div class="card"><div class="row"><b>أساس الأجر اليومي للغرامات</b><select id="pbase" style="width:auto">${opt('gross', 'الأجر الفعلي (الأساسي + البدلات) ÷ 30', S.company.penalty_base)}${opt('basic', 'الأجر الأساسي ÷ 30', S.company.penalty_base)}</select></div>
        <p class="muted small" style="margin:6px 0 0">النسب في الجدول من أجر يوم. والغرامة عن المخالفة الواحدة لا تزيد على أجر خمسة أيام، ولا يُحسم من الأجر للغرامات أكثر من أجر خمسة أيام في الشهر (م70).</p></div>` : ''}
      ${Object.entries(PEN_CAT).map(([k, t]) => `<h2 style="margin-top:16px">${esc(t)}</h2><div class="pentbl">${tbl([{ t: 'م', h: v => `<span class="num">${v.no}</span>` }, { t: 'المخالفة', h: v => esc(v.title) + (v.extra ? `<div class="small muted">${esc(PEN_EXTRA[v.extra])}</div>` : '') + (v.note ? `<div class="small muted">${esc(v.note)}</div>` : '') },
        ...[1, 2, 3, 4].map(i => ({ t: 'المرة ' + PEN_ORD[i], h: v => `<span class="small">${esc(penLabel(v.steps[i - 1]))}</span>` }))], vt.filter(v => v.cat === k))}</div>`).join('')}
      <p class="muted small">لا يُشدَّد الجزاء عند تكرار المخالفة إذا مضى 180 يوماً على إبلاغ العامل بالجزاء السابق (م68).</p>`;
    if ($('#pbase', page)) $('#pbase', page).onchange = async ev => { try { await db.upd('companies', { id: 'eq.' + S.cid }, { penalty_base: ev.target.value }); await loadContext(); toast('تم الحفظ'); } catch (e) { toast(e.message); } };
  }
  if ($('#pnew', page)) $('#pnew', page).onclick = () => penNew(vt, em);
};

function penNew(vt, em) {
  const act = Object.values(em).filter(e => !e.end_date || e.end_date >= today());
  const m = modal('تسجيل مخالفة', `<div class="fg">${field('الموظف', `<select name="emp"><option value="">— اختر —</option>${act.map(e => opt(e.id, e.full_name + ' (' + e.emp_no + ')')).join('')}</select>`, 'wide')}
    ${field('المخالفة', `<select name="code"><option value="">— اختر —</option>${Object.entries(PEN_CAT).map(([k, t]) => `<optgroup label="${esc(t)}">${vt.filter(v => v.cat === k).map(v => opt(v.code, v.no + '. ' + v.title)).join('')}</optgroup>`).join('')}</select>`, 'wide')}
    ${field('تاريخ المخالفة', `<input type="date" name="occ" value="${today()}">`)}${field('تاريخ اكتشافها', `<input type="date" name="disc" value="${today()}">`)}
    ${field('وصف الواقعة', '<textarea name="desc" rows="2"></textarea>', 'wide')}<div class="wide" id="pprev"></div></div>
    <p class="muted small">يُسجَّل اتهام العامل خلال 30 يوماً من اكتشاف المخالفة (م69). بعد التسجيل اطبع الإشعار وسلّمه للعامل، ثم سجّل التحقيق وسماع دفاعه قبل توقيع أي جزاء (م71).</p>`, {
    ok: 'تسجيل', onOk: async f => {
      if (!f.emp || !f.code) throw new Error('اختر الموظف والمخالفة');
      const id = await db.rpc('pen_open', { p_company: S.cid, p_emp: f.emp, p_code: f.code, p_occurred: f.occ, p_discovered: f.disc, p_desc: f.desc || '' });
      toast('سُجّلت المخالفة'); location.hash = '#/penalties/' + id; } });
  const prev = async () => {
    const f = $('#mform', m), box = $('#pprev', m); if (!f.emp.value || !f.code.value || !f.occ.value) { box.innerHTML = ''; return; }
    try { const [k] = await db.rpc('pen_preview', { p_emp: f.emp.value, p_code: f.code.value, p_on: f.occ.value }); const v = vt.find(x => x.code === f.code.value) || {};
      box.innerHTML = `<div class="note">المرة ${PEN_ORD[k.step]} لهذه المخالفة خلال 180 يوماً: <b>${esc(penLabel(k.action))}</b>${n0(k.fine) ? ` = <b class="num">${money(k.fine)}</b> ريال (أجر اليوم ${money(k.daily_wage)})` : ''}${v.extra ? '<br><span class="small">' + esc(PEN_EXTRA[v.extra]) + '</span>' : ''}${v.note ? '<br><span class="small">' + esc(v.note) + '</span>' : ''}</div>`; } catch (e) { box.innerHTML = ''; }
  };
  ['emp', 'code', 'occ'].forEach(n => $('#mform', m)[n].addEventListener('change', prev));
}

async function penDetail(page, id) {
  const [[p], vt, em] = await Promise.all([db.get('penalties', { id: 'eq.' + id }), VTYPES(), employeesMap(true)]);
  if (!p) throw new Error('المخالفة غير موجودة');
  const v = vt.find(x => x.code === p.code) || {}, e = em[p.employee_id] || {}, td = today(), hr = isHR();
  const ded = await db.get('penalty_deductions', { penalty_id: 'eq.' + id }).catch(() => []);
  const runs = ded.length ? await db.get('payroll_runs', { id: 'in.(' + ded.map(d => d.run_id).join(',') + ')' }).catch(() => []) : [];
  const gDead = p.notified_on ? await db.rpc('pen_grievance_deadline', { p_company: S.cid, p_from: p.notified_on }).catch(() => null) : null;
  const decDead = p.inv_on ? addDays(p.inv_on, 30) : null;
  page.classList.add('wrapcells');
  const r = (t, x) => `<tr><td class="muted">${esc(t)}</td><td>${x}</td></tr>`;
  const penTxt = `المرة ${PEN_ORD[p.step]}: ${penLabel(p.action)}${n0(p.fine) ? ' — ' + money(p.fine) + ' ريال' : ''}`;
  page.innerHTML = `<div class="head"><div><a href="#/penalties" class="small">← المخالفات والجزاءات</a><h1>${esc(e.full_name || '')} ${penBadge(p.status)}</h1><div class="muted"><span class="num">${esc(e.emp_no || '')}</span>${e.job_title ? ' · ' + esc(e.job_title) : ''}</div></div>
      <div class="row"><button class="btn sm" id="prn">طباعة الإشعار</button>${p.inv_on ? '<button class="btn sm" id="prm">طباعة محضر التحقيق</button>' : ''}${p.status === 'applied' || p.status === 'overturned' ? '<button class="btn sm" id="prd">طباعة القرار</button>' : ''}</div></div>
    <div class="card"><h2>الواقعة</h2><div class="tw"><table><tbody>
      ${r('المخالفة', `<span class="num muted small">${esc(p.code)}</span> ${esc(v.title || '')}`)}${r('تاريخ المخالفة', fdate(p.occurred_on))}${r('تاريخ اكتشافها', fdate(p.discovered_on))}
      ${r('الوصف', esc(p.description || '—'))}${r('الجزاء حسب الجدول', esc(penTxt) + (v.extra ? `<div class="small muted">${esc(PEN_EXTRA[v.extra])}</div>` : '') + (v.note ? `<div class="small muted">${esc(v.note)}</div>` : ''))}</tbody></table></div>
      ${p.emp_defense ? `<div class="note" style="margin-top:10px"><b>رد الموظف الكتابي:</b> ${esc(p.emp_defense)}</div>` : ''}</div>
    <div class="card" id="pinv"><h2>التحقيق (م71)</h2>${p.inv_on ? `<div class="tw"><table><tbody>${r('التاريخ', fdate(p.inv_on))}${r('الطريقة', esc(INV_MODE[p.inv_mode]))}${r('المحضر', esc(p.inv_text))}</tbody></table></div>`
      : p.status === 'open' && hr ? `<form id="invf" class="fg" novalidate>${field('طريقة التحقيق', `<select name="mode">${opt('written', INV_MODE.written)}${opt('oral', INV_MODE.oral)}${opt('refused', INV_MODE.refused)}</select>`)}${field('تاريخ التحقيق', `<input type="date" name="on" value="${td}">`)}
          ${field('المحضر: ما نُسب للعامل وأقواله ودفاعه', `<textarea name="txt" rows="4">${esc(p.emp_defense ? 'رد العامل: ' + p.emp_defense : '')}</textarea>`, 'wide')}<div class="wide"><div id="inverr"></div><button class="btn pri" id="invb">حفظ المحضر</button></div></form>
          <p class="muted small">الاستجواب الشفهي فقط للمخالفات البسيطة التي جزاؤها إنذار أو غرامة لا تزيد على أجر يوم، على أن يُثبت في المحضر.</p>` : '<p class="muted">لم يُسجَّل تحقيق.</p>'}</div>
    <div class="card" id="pdec"><h2>القرار (م69، م72)</h2>${p.status === 'open' ? (hr ? (p.inv_on ? `<p class="small">آخر موعد لتوقيع الجزاء: <b class="num">${decDead}</b> (30 يوماً من انتهاء التحقيق)${decDead < td ? ' <span class="badge bad">انقضت المهلة</span>' : ''}</p>
          <div class="row"><label class="row small" style="gap:6px">تاريخ إبلاغ العامل كتابةً <input type="date" id="pnot" value="${td}" style="width:auto"></label><button class="btn pri" id="papl">توقيع الجزاء</button><button class="btn" id="pdrop">حفظ المخالفة (لم تثبت)</button></div>`
          : '<p class="muted">سجّل التحقيق أولاً.</p><button class="btn" id="pdrop">حفظ المخالفة (لم تثبت)</button>') : '<p class="muted">قيد التحقيق.</p>')
      : `<div class="tw"><table><tbody>${r('القرار', p.status === 'dropped' ? 'حُفظت المخالفة' : esc(penTxt))}${r('تاريخ القرار', fdate(p.decided_on))}${p.notified_on ? r('تاريخ الإبلاغ', fdate(p.notified_on)) : ''}${p.decision_note ? r('ملاحظات', esc(p.decision_note)) : ''}
          ${gDead && p.status === 'applied' ? r('مهلة التظلم', `حتى <span class="num">${esc(gDead)}</span> (30 يوماً عدا العطل الرسمية)`) : ''}</tbody></table></div>
          ${p.status === 'applied' && isDismiss(p.action) ? `<div class="note" style="margin-top:10px">${p.action === 'a80' ? 'الفصل وفق المادة 80 دون مكافأة: تأكد من توافر شروط المادة وإنذار العامل كتابةً في حالات الغياب.' : 'الفصل مع المكافأة.'} يُسجَّل تاريخ نهاية الخدمة من بيانات الموظف وتُحسب المستحقات من «مكافأة نهاية الخدمة».</div>` : ''}`}</div>
    ${p.griev_on ? `<div class="card"><h2>التظلم (م72)</h2><div class="tw"><table><tbody>${r('تاريخ التظلم', fdate(p.griev_on))}${r('الأسباب', esc(p.griev_text))}
        ${p.griev_result ? r('النتيجة', p.griev_result === 'overturned' ? 'قُبل التظلم وأُلغي الجزاء' : 'رُفض التظلم') + r('تاريخ البت', fdate(p.griev_on_decided)) + r('القرار', esc(p.griev_note)) : r('آخر موعد للبت', `<span class="num">${addDays(p.griev_on, 15)}</span> (15 يوماً)`)}</tbody></table></div>
        ${!p.griev_result && hr ? `<div class="fg" style="margin-top:10px">${field('قرار التظلم', '<textarea id="gnote" rows="2"></textarea>', 'wide')}<div class="wide row"><button class="btn pri" id="gup">رفض التظلم</button><button class="btn" id="gov">قبول التظلم وإلغاء الجزاء</button></div></div>
          <p class="muted small">إذا رُفض التظلم أو لم يُبت فيه خلال 15 يوماً، فللعامل الاعتراض أمام المحاكم العمالية خلال 30 يوماً.</p>` : ''}</div>` : ''}
    ${ded.length ? `<div class="card"><h2>الحسم من الراتب</h2>${tbl([{ t: 'المسير', h: d => { const x = runs.find(z => z.id === d.run_id); return x ? x.month + '/' + x.year + ' ' + badge(x.status) : ''; } }, { t: 'المبلغ', r: 1, h: d => money(d.amount) }], ded)}</div>` : ''}`;
  const doc = (title, body) => { const d = document.createElement('div'); d.innerHTML = `<h2 style="text-align:center;margin:0 0 6mm">${esc(title)}</h2>${body}`; printBlock(d, title); };
  const who = `<p>إلى: <b>${esc(e.full_name || '')}</b> — الرقم الوظيفي <span class="num">${esc(e.emp_no || '')}</span>${e.job_title ? ' — ' + esc(e.job_title) : ''}</p>`;
  const sig = l => `<div class="row" style="justify-content:space-between;margin-top:14mm">${l.map(t => `<div style="min-width:60mm"><div>${esc(t)}:</div><div style="border-bottom:1px dotted #777;height:9mm"></div></div>`).join('')}</div>`;
  $('#prn', page).onclick = () => doc('إشعار بمخالفة واستدعاء للتحقيق', `${who}<p>نُسب إليك ارتكاب المخالفة الآتية: <b>${esc(v.title || '')}</b>، بتاريخ <span class="num">${esc(p.occurred_on)}</span>، وقد اكتُشفت بتاريخ <span class="num">${esc(p.discovered_on)}</span>.</p>
    ${p.description ? `<p>الوصف: ${esc(p.description)}</p>` : ''}<p>وعليه نأمل منك الرد كتابياً وحضور التحقيق لسماع أقوالك وتحقيق دفاعك، وفقاً للمادة 71 من نظام العمل.</p>${sig(['الموارد البشرية', 'استلام العامل والتاريخ'])}`);
  if ($('#prm', page)) $('#prm', page).onclick = () => doc('محضر تحقيق', `${who}<p>المخالفة المنسوبة: <b>${esc(v.title || '')}</b> بتاريخ <span class="num">${esc(p.occurred_on)}</span>.</p><p>تاريخ التحقيق: <span class="num">${esc(p.inv_on)}</span> — ${esc(INV_MODE[p.inv_mode])}</p>
    ${p.emp_defense ? `<p>رد العامل الكتابي: ${esc(p.emp_defense)}</p>` : ''}<p style="white-space:pre-wrap">${esc(p.inv_text || '')}</p>${sig(['المحقق', 'العامل'])}`);
  if ($('#prd', page)) $('#prd', page).onclick = () => doc('قرار توقيع جزاء تأديبي', `${who}<p>بعد إبلاغك كتابةً بالمخالفة المنسوبة إليك (${esc(v.title || '')}) بتاريخ <span class="num">${esc(p.occurred_on)}</span>، والتحقيق معك بتاريخ <span class="num">${esc(p.inv_on || '')}</span> وسماع دفاعك، وثبوت المخالفة، تقرر توقيع الجزاء الآتي وفق جدول المخالفات والجزاءات:</p>
    <p><b>${esc(penTxt)}</b>${v.extra ? '، ' + esc(PEN_EXTRA[v.extra]) : ''}.</p>${n0(p.fine) ? '<p>تُحسم الغرامة من أجرك بما لا يزيد على أجر خمسة أيام في الشهر (م70).</p>' : ''}
    <p>يحق لك التظلم كتابةً لدى إدارة الموارد البشرية خلال 30 يوماً، عدا أيام العطل الرسمية، من تاريخ إبلاغك بهذا القرار${gDead ? ' (حتى <span class="num">' + esc(gDead) + '</span>)' : ''}، ويُبت في التظلم خلال 15 يوماً من تقديمه (م72).</p>
    <p>تاريخ الإبلاغ: <span class="num">${esc(p.notified_on || '')}</span></p>${sig(['صاحب الصلاحية', 'استلام العامل والتاريخ'])}`);
  if ($('#invf', page)) $('#invf', page).onsubmit = async ev => { ev.preventDefault(); const f = formData(ev.target);
    try { await busy($('#invb', page), () => db.rpc('pen_investigate', { p_id: id, p_mode: f.mode, p_text: f.txt, p_on: f.on })); toast('حُفظ المحضر'); route(); } catch (er) { showErr($('#inverr', page), er); } };
  if ($('#papl', page)) $('#papl', page).onclick = async () => { if (!await confirmBox('توقيع الجزاء', 'سيصدر القرار: ' + penTxt + '. تأكد من إبلاغ العامل كتابةً.', 'توقيع الجزاء')) return;
    try { await db.rpc('pen_decide', { p_id: id, p_apply: true, p_notified: $('#pnot', page).value, p_note: null }); toast('صدر الجزاء'); route(); refreshCounts(); } catch (er) { toast(er.message); } };
  if ($('#pdrop', page)) $('#pdrop', page).onclick = () => modal('حفظ المخالفة', field('سبب الحفظ', '<textarea name="n" rows="2"></textarea>'), { ok: 'حفظ المخالفة', onOk: async f => { await db.rpc('pen_decide', { p_id: id, p_apply: false, p_notified: null, p_note: f.n }); toast('حُفظت المخالفة'); route(); } });
  const gd = async ov => { try { const back = await db.rpc('pen_grievance_decide', { p_id: id, p_overturn: ov, p_note: $('#gnote', page).value }); toast(ov && n0(back) ? 'أُلغي الجزاء — أعد للموظف ' + money(back) + ' ريال حُسمت في مسيرات معتمدة' : 'تم'); route(); refreshCounts(); } catch (er) { toast(er.message); } };
  if ($('#gup', page)) $('#gup', page).onclick = () => gd(false);
  if ($('#gov', page)) $('#gov', page).onclick = () => gd(true);
}

/* employee: own cases on the profile page, with a written reply and a grievance */
async function myPenaltiesHtml() {
  if (!S.emp) return '';
  const [ps, vt] = await Promise.all([db.get('penalties', { employee_id: 'eq.' + S.emp, order: 'created_at.desc' }).catch(() => []), VTYPES().catch(() => [])]);
  const mine = ps.filter(p => p.status !== 'dropped'); if (!mine.length) return '';
  const vm = {}; vt.forEach(v => vm[v.code] = v);
  return `<div class="card wrapcells" id="mypen"><h2>المخالفات والجزاءات</h2>${tbl([{ t: 'المخالفة', h: p => `<span class="small">${esc((vm[p.code] || {}).title || p.code)}</span>` }, { t: 'التاريخ', h: p => fdate(p.occurred_on) },
    { t: 'الجزاء', h: p => p.status === 'open' ? '—' : `<span class="small">${esc(penLabel(p.action))}${n0(p.fine) ? ' — ' + money(p.fine) : ''}</span>` }, { t: 'الحالة', h: p => penBadge(p.status) + (p.griev_on && !p.griev_result ? ' <span class="badge wait">تظلم قيد البت</span>' : '') },
    { t: '', h: p => p.status === 'open' && !p.inv_on ? `<button class="btn sm" data-def="${p.id}">${p.emp_defense ? 'تعديل ردي' : 'رد كتابي'}</button>` : p.status === 'applied' && !p.griev_on ? `<button class="btn sm" data-grv="${p.id}">تظلم</button>` : '' }], mine)}
    <p class="muted small">لك حق الرد كتابياً قبل التحقيق، والتظلم كتابةً خلال 30 يوماً من إبلاغك بالقرار عدا العطل الرسمية (م71، م72).</p></div>`;
}
function bindMyPenalties(page) {
  $$('[data-def]', page).forEach(b => b.onclick = () => modal('رد كتابي على المخالفة', field('ردك ودفاعك', '<textarea name="t" rows="4"></textarea>'), { ok: 'إرسال', onOk: async f => { await db.rpc('pen_defend', { p_id: b.dataset.def, p_text: f.t }); toast('أُرسل ردك'); route(); } }));
  $$('[data-grv]', page).forEach(b => b.onclick = () => modal('تظلم من الجزاء', field('أسباب التظلم', '<textarea name="t" rows="4"></textarea>'), { ok: 'تقديم التظلم', onOk: async f => { await db.rpc('pen_grieve', { p_id: b.dataset.grv, p_text: f.t }); toast('قُدّم التظلم'); route(); } }));
}
