'use strict';
/* ===== الحقول المخصصة (0100): the company's own fields on employees, customers/suppliers and items ===== */
const CF_ENT = { employee: 'ملف الموظف', party: 'العميل والمورد', item: 'الصنف' };
const CF_KIND = { text: 'نص', number: 'رقم', date: 'تاريخ', select: 'قائمة اختيار' };
const cfDefs = entity => (S.cf || []).filter(c => c.entity === entity && c.active);
const cfLabel = c => (LANG === 'en' && c.label_en) || c.label;
// the fields inside a form (a heading, then one input per field; names cf_<id>)
function cfFields(entity, vals) {
  const defs = cfDefs(entity); if (!defs.length) return ''; vals = vals || {};
  return `<div class="wide muted small" style="margin:4px 0 -4px"><b>${esc(tr('حقول إضافية'))}</b></div>` + defs.map(c => { const v = vals[c.id] == null ? '' : vals[c.id], n = 'cf_' + c.id;
    const input = c.kind === 'select' ? `<select name="${n}"><option value="">—</option>${c.options.map(o => opt(o, o, v)).join('')}</select>`
      : c.kind === 'date' ? `<input type="date" name="${n}" value="${esc(v)}">` : c.kind === 'number' ? inp(n, v, 'type="number" step="any"') : inp(n, v, 'maxlength="300"');
    return field(cfLabel(c), input); }).join('');
}
// the values from a submitted form, merged over what the record already had
function cfCollect(f, entity, old) {
  const out = Object.assign({}, old || {});
  cfDefs(entity).forEach(c => { const v = f['cf_' + c.id]; if (v === undefined) return; if (v === '' || v == null) delete out[c.id]; else out[c.id] = c.kind === 'number' ? +v : v; });
  return out;
}
// read-only lines for a record's page
const cfView = (entity, vals) => cfDefs(entity).filter(c => vals && vals[c.id] != null && vals[c.id] !== '').map(c => `<tr><td class="muted">${esc(cfLabel(c))}</td><td>${esc(vals[c.id])}</td></tr>`).join('');

VIEWS['#/customfields'] = async page => {
  if (!has('owner', 'admin')) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للمالك ومدير النظام.'))}</div>`; return; }
  const rows = await db.get('custom_fields', { company_id: 'eq.' + S.cid, order: 'entity,sort,created_at' });
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('الحقول المخصصة'))}</h1><div class="muted">${esc(tr('أضف حقولا خاصة بمنشأتك لملف الموظف أو بطاقة العميل والمورد أو الصنف، مثل: فصيلة الدم، رقم رخصة القيادة، المنطقة، لون المنتج.'))}</div></div><button class="btn pri" id="cfn">${esc(tr('+ حقل'))}</button></div>
    ${tbl([{ t: 'الحقل', h: c => `<b>${esc(c.label)}</b>${c.label_en ? ` <span class="small muted">${esc(c.label_en)}</span>` : ''}${c.active ? '' : ` <span class="badge">${esc(tr('موقوف'))}</span>`}` },
      { t: 'يظهر في', h: c => esc(tr(CF_ENT[c.entity])) }, { t: 'النوع', h: c => esc(tr(CF_KIND[c.kind])) + (c.kind === 'select' ? `<div class="small muted">${esc(c.options.join('، '))}</div>` : '') }], rows, { empty: 'لا توجد حقول مخصصة بعد', onRow: true })}`;
  bindRows(page, rows, c => form(c)); $('#cfn', page).onclick = () => form(null);
  function form(c) { const v = c || { entity: 'employee', kind: 'text', options: [], active: true, sort: rows.length };
    const m = modal(c ? tr('تعديل حقل') : tr('حقل جديد'), `<div class="fg">${field('اسم الحقل', inp('label', v.label, 'required maxlength="60"'))}${enF('label_en', v.label_en)}
      ${field('يظهر في', `<select name="entity" ${c ? 'disabled' : ''}>${Object.entries(CF_ENT).map(([k, t]) => opt(k, tr(t), v.entity)).join('')}</select>`)}
      ${field('النوع', `<select name="kind">${Object.entries(CF_KIND).map(([k, t]) => opt(k, tr(t), v.kind)).join('')}</select>`)}
      <div class="wide" data-opts>${field('الخيارات (سطر لكل خيار)', `<textarea name="opts" rows="4">${esc((v.options || []).join('\n'))}</textarea>`)}</div>
      ${field('الترتيب', inp('sort', v.sort, 'type="number" min="0"'))}${c ? field('الحالة', `<select name="act">${opt('true', tr('ظاهر'), String(v.active))}${opt('false', tr('موقوف'), String(v.active))}</select>`) : ''}</div>
      ${c ? `<button type="button" class="btn sm danger" id="cfdel">${esc(tr('حذف الحقل'))}</button>` : ''}`, {
      onOk: async f => { const opts = (f.opts || '').split('\n').map(x => x.trim()).filter(Boolean);
        if ((f.label || '').trim().length < 2) throw new Error('اكتب اسم الحقل'); if (f.kind === 'select' && !opts.length) throw new Error('أضف خيارا واحدا على الأقل');
        const row = { label: f.label.trim(), label_en: blank((f.label_en || '').trim()), kind: f.kind, options: f.kind === 'select' ? opts : [], sort: +f.sort || 0, ...(c ? { active: f.act === 'true' } : { entity: f.entity }) };
        if (c) await db.upd('custom_fields', { id: 'eq.' + c.id }, row); else await db.ins('custom_fields', Object.assign(row, { company_id: S.cid }));
        await cfLoad(); toast(tr('تم الحفظ')); route(); } });
    const sync = () => { $('[data-opts]', m).hidden = $('select[name=kind]', m).value !== 'select'; }; $('select[name=kind]', m).onchange = sync; sync();
    if ($('#cfdel', m)) $('#cfdel', m).onclick = async () => { if (!await confirmBox(tr('حذف الحقل'), tr('يُحذف الحقل من النماذج. القيم المسجلة سابقا تبقى في السجلات ولا تظهر.'), tr('حذف'))) return; await db.del('custom_fields', { id: 'eq.' + c.id }); await cfLoad(); route(); };
  }
};
async function cfLoad() { S.cf = await db.get('custom_fields', { company_id: 'eq.' + S.cid, order: 'sort,created_at' }).catch(() => []); }
