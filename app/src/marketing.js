'use strict';
/* ===== Marketing: campaigns with a budget and spend, their results read from the CRM pipeline
   (leads, won deals, revenue, cost per lead, return on spend). Part of the sales module. ===== */

const MKT_CHANNEL = { social: 'وسائل التواصل', google: 'إعلانات جوجل', email: 'البريد الإلكتروني', sms: 'رسائل نصية', event: 'فعالية/معرض', print: 'مطبوعات', referral: 'توصيات', influencer: 'مؤثرون', other: 'أخرى' };
const MKT_STATUS = { planned: 'مخططة', active: 'نشطة', paused: 'متوقفة مؤقتا', done: 'منتهية', cancelled: 'ملغاة' };
const mktBadge = s => `<span class="badge ${s === 'active' ? 'ok' : s === 'cancelled' ? 'bad' : s === 'paused' ? 'wait' : 'info'}">${esc(tr(MKT_STATUS[s] || s))}</span>`;
const roiCls = v => v == null ? '' : (v >= 0 ? 'ok' : 'bad');

VIEWS['#/marketing'] = async (page, arg) => {
  if (!can('sales')) { page.innerHTML = '<div class="err">غير مصرح</div>'; return; }
  if (arg) return campaignView(page, arg);
  const [camps, res] = await Promise.all([
    db.get('marketing_campaigns', Object.assign(C(), { order: 'created_at.desc', limit: 500 })),
    db.rpc('marketing_summary', { p_company: S.cid })]);
  const rm = {}; res.forEach(r => rm[r.campaign_id] = r);
  const active = camps.filter(c => c.status === 'active').length;
  const budget = camps.reduce((a, c) => a + n0(c.budget), 0), spent = camps.reduce((a, c) => a + n0(c.spent), 0);
  const leads = res.reduce((a, r) => a + n0(r.leads), 0), won = res.reduce((a, r) => a + n0(r.won), 0);
  const revenue = res.reduce((a, r) => a + n0(r.revenue), 0);
  const roi = spent > 0 ? r2((revenue - spent) / spent * 100) : null;
  const cpl = leads > 0 && spent > 0 ? r2(spent / leads) : null;
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('التسويق والحملات'))}</h1><div class="muted small">${esc(tr('الحملات ونتائجها من خط المبيعات'))}</div></div>
      <div class="row"><button class="btn pri" id="ncamp">${esc(tr('حملة جديدة'))}</button></div></div>
    <div class="grid" style="margin-bottom:14px">
      <div class="card kpi"><div class="muted small">${esc(tr('الحملات النشطة'))}</div><div class="v num">${active} <span class="small muted">/ ${camps.length}</span></div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('إجمالي الإنفاق'))}</div><div class="v num">${money(spent)}</div>${budget ? `<div class="small muted">${esc(tr('الميزانية'))}: <span class="num">${money(budget)}</span></div>` : ''}</div>
      <div class="card kpi"><div class="muted small">${esc(tr('عملاء محتملون من الحملات'))}</div><div class="v num">${leads}</div>${cpl != null ? `<div class="small muted">${esc(tr('تكلفة العميل'))}: <span class="num">${money(cpl)}</span></div>` : ''}</div>
      <div class="card kpi"><div class="muted small">${esc(tr('صفقات مكسوبة'))}</div><div class="v num">${won}</div><div class="small muted">${esc(tr('إيراد'))}: <span class="num">${money(revenue)}</span></div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('العائد على الإنفاق'))}</div><div class="v num ${roiCls(roi)}">${roi == null ? '—' : roi + '%'}</div></div></div>
    ${tbl([{ t: 'الرقم', h: c => `<span class="num">${esc(c.no)}</span>` }, { t: 'الحملة', k: 'name' }, { t: 'القناة', h: c => esc(tr(MKT_CHANNEL[c.channel] || c.channel)) }, { t: 'الحالة', h: c => mktBadge(c.status) },
      { t: 'الميزانية', r: 1, h: c => money(c.budget) }, { t: 'الإنفاق', r: 1, h: c => money(c.spent) },
      { t: 'عملاء', r: 1, h: c => `<span class="num">${n0((rm[c.id] || {}).leads)}</span>` }, { t: 'مكسوبة', r: 1, h: c => `<span class="num">${n0((rm[c.id] || {}).won)}</span>` },
      { t: 'الإيراد', r: 1, h: c => money((rm[c.id] || {}).revenue) }, { t: 'تكلفة العميل', r: 1, h: c => money((rm[c.id] || {}).cost_per_lead) },
      { t: 'العائد %', r: 1, h: c => { const v = (rm[c.id] || {}).roi; return v == null ? '—' : `<span class="num ${roiCls(v)}">${v}%</span>`; } }],
      camps, { empty: 'لا توجد حملات بعد — ابدأ بحملة جديدة', onRow: true })}`;
  $('#ncamp', page).onclick = () => campaignForm(null);
  bindRows(page, camps, c => location.hash = '#/marketing/' + c.id);
};

function campaignForm(c) {
  const v = c || { channel: 'social', status: 'planned' };
  modal(c ? tr('تعديل الحملة') : tr('حملة جديدة'), `<div class="fg">
    ${field('اسم الحملة', inp('name', v.name, 'required'), 'wide')}
    ${field('القناة', `<select name="channel">${Object.entries(MKT_CHANNEL).map(([k, t]) => opt(k, tr(t), v.channel)).join('')}</select>`)}
    ${field('الحالة', `<select name="status">${Object.entries(MKT_STATUS).map(([k, t]) => opt(k, tr(t), v.status)).join('')}</select>`)}
    ${field('الميزانية', inp('budget', v.budget, 'type="number" step="0.01" min="0"'))}
    ${field('المصروف الفعلي', inp('spent', v.spent, 'type="number" step="0.01" min="0"'))}
    ${field('من تاريخ', inp('start_date', v.start_date, 'type="date"'))}
    ${field('إلى تاريخ', inp('end_date', v.end_date, 'type="date"'))}
    ${field('الهدف', inp('goal', v.goal), 'wide')}
    ${field('ملاحظات', `<textarea name="note" rows="2">${esc(v.note || '')}</textarea>`, 'wide')}</div>`, {
    onOk: async f => {
      const row = { company_id: S.cid, name: f.name, channel: f.channel, status: f.status, budget: blank(f.budget), spent: n0(f.spent),
        start_date: blank(f.start_date), end_date: blank(f.end_date), goal: blank(f.goal), note: blank(f.note) };
      if (c) await db.upd('marketing_campaigns', { id: 'eq.' + c.id }, row); else await db.ins('marketing_campaigns', row);
      toast(tr('تم الحفظ')); route();
    } });
}

async function campaignView(page, id) {
  const [[c], leads, parties] = await Promise.all([
    db.get('marketing_campaigns', Object.assign(C(), { id: 'eq.' + id })),
    db.get('crm_leads', Object.assign(C(), { campaign_id: 'eq.' + id, order: 'updated_at.desc' })),
    db.get('parties', Object.assign(C(), { kind: 'eq.customer', select: 'id,name' }))]);
  if (!c) { page.innerHTML = `<div class="note">${esc(tr('الحملة غير موجودة'))}</div>`; return; }
  const pm = {}; parties.forEach(p => pm[p.id] = p.name);
  const won = leads.filter(l => l.stage === 'won'), revenue = won.reduce((a, l) => a + n0(l.value), 0);
  const cpl = leads.length && n0(c.spent) > 0 ? r2(n0(c.spent) / leads.length) : null;
  const roi = n0(c.spent) > 0 ? r2((revenue - n0(c.spent)) / n0(c.spent) * 100) : null;
  const who = l => esc(l.party_id ? pm[l.party_id] || '' : l.prospect || '');
  page.innerHTML = `<div class="head"><div><h1>${esc(c.name)} <span class="muted num small">${esc(c.no)}</span></h1>
      <div class="muted small">${esc(tr(MKT_CHANNEL[c.channel] || c.channel))} · ${mktBadge(c.status)}${c.start_date ? ' · ' + fdate(c.start_date) + (c.end_date ? ' – ' + fdate(c.end_date) : '') : ''}</div></div>
      <div class="row"><a class="btn" href="#/marketing">${esc(tr('رجوع'))}</a><button class="btn" id="cedit">${esc(tr('تعديل'))}</button></div></div>
    ${c.goal ? `<div class="note">${esc(tr('الهدف'))}: ${esc(c.goal)}</div>` : ''}
    <div class="grid" style="margin-bottom:14px">
      <div class="card kpi"><div class="muted small">${esc(tr('الميزانية'))}</div><div class="v num">${money(c.budget)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('المصروف'))}</div><div class="v num">${money(c.spent)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('عملاء محتملون'))}</div><div class="v num">${leads.length}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('مكسوبة'))}</div><div class="v num">${won.length}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('الإيراد'))}</div><div class="v num">${money(revenue)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('تكلفة العميل'))}</div><div class="v num">${money(cpl)}</div></div>
      <div class="card kpi"><div class="muted small">${esc(tr('العائد على الإنفاق'))}</div><div class="v num ${roiCls(roi)}">${roi == null ? '—' : roi + '%'}</div></div></div>
    <div class="card"><div class="row" style="justify-content:space-between;align-items:center"><h2>${esc(tr('العملاء المحتملون من هذه الحملة'))}</h2><a class="btn sm pri" href="#/crm">${esc(tr('إضافة من الفرص'))}</a></div>
      ${tbl([{ t: 'الرقم', h: l => `<span class="num">${esc(l.no)}</span>` }, { t: 'الفرصة', h: l => `<a href="#/crm/${l.id}">${esc(l.title)}</a>` }, { t: 'العميل', h: who },
        { t: 'المرحلة', h: l => crmBadge(l.stage) }, { t: 'القيمة', r: 1, h: l => money(l.value) }], leads, { empty: 'لا يوجد عملاء مربوطون بهذه الحملة بعد — اربط الفرصة بالحملة من صفحة الفرصة' })}</div>`;
  $('#cedit', page).onclick = () => campaignForm(c);
}
