'use strict';
/* ===== «التهيئة والترحيب» (0107): a checklist per new employee (hired in the last 120 days) =====
   Automatic steps are read from the employee's data; the rest are ticked by HR (onboarding_marks), including the
   company's own steps (companies.onboarding_items). */
const ONB_MANUAL = [['gosi', 'التسجيل في التأمينات الاجتماعية'], ['qiwa', 'توثيق العقد في منصة قوى'], ['welcome', 'جلسة الترحيب والتعريف بالمنشأة'], ['tools', 'تسليم أدوات العمل والعهد']];
VIEWS['#/onboarding'] = async page => {
  if (!isHR()) { page.innerHTML = `<div class="note">${esc(tr('هذه الصفحة للمالك والموارد البشرية.'))}</div>`; return; }
  const td = today(), since = new Date(Date.now() - 120 * 864e5 + 3 * 3600e3).toISOString().slice(0, 10), q = { company_id: 'eq.' + S.cid };
  const [em, con, mem, docs, ins, pol, acks, marks] = await Promise.all([employeesMap(true),
    db.get('contracts', Object.assign({ status: 'eq.active', select: 'employee_id' }, q)).catch(() => []),
    db.get('members', Object.assign({ select: 'employee_id,role' }, q)).catch(() => []),
    db.get('employee_documents', Object.assign({ select: 'employee_id,doc_type' }, q)).catch(() => []),
    db.get('insurance_members', Object.assign({ select: 'employee_id,end_date' }, q)).catch(() => []),
    db.get('policies', Object.assign({ active: 'eq.true', select: 'id' }, q)).catch(() => []),
    db.get('policy_acks', Object.assign({ select: 'employee_id,policy_id' }, q)).catch(() => []),
    db.get('onboarding_marks', q).catch(() => [])]);
  const has_ = (rows, id, f) => rows.some(r => r.employee_id === id && (!f || f(r)));
  const ownerEmp = (mem.find(m => m.role === 'owner') || {}).employee_id, custom = (S.company && S.company.onboarding_items) || [];
  const steps = e => [
    { k: 'contract', t: 'عقد عمل ساري', ok: has_(con, e.id), h: '#/docs/' + e.id },
    { k: 'account', t: 'حساب دخول للموظف في وعد', ok: has_(mem, e.id), h: '#/users' },
    { k: 'id', t: e.is_saudi ? 'رقم الهوية في ملفه' : 'الإقامة مسجلة في وثائقه', ok: e.is_saudi ? !!e.national_id : has_(docs, e.id, r => r.doc_type === 'iqama'), h: e.is_saudi ? '#/employees' : '#/docs/' + e.id },
    { k: 'iban', t: 'الآيبان لصرف الراتب', ok: !!e.iban, h: '#/employees' },
    { k: 'manager', t: 'المدير المباشر محدد', ok: !!e.manager_id || e.id === ownerEmp, h: '#/employees' },
    { k: 'insurance', t: 'التأمين الطبي', ok: has_(ins, e.id, r => !r.end_date || r.end_date >= td), h: '#/insurance' },
    ...(pol.length ? [{ k: 'policies', t: 'الإقرار بسياسات المنشأة', ok: pol.every(p => acks.some(a => a.employee_id === e.id && a.policy_id === p.id)), h: '#/policies' }] : []),
    ...ONB_MANUAL.concat(custom.map(c => ['c:' + c, c])).map(([k, t]) => ({ k, t, manual: true, ok: marks.some(m => m.employee_id === e.id && m.item === k) }))];
  const news = Object.values(em).filter(e => e.hire_date && e.hire_date >= since && (!e.end_date || e.end_date >= td)).sort((a, b) => (b.hire_date || '').localeCompare(a.hire_date || ''));
  const prog = e => { const s = steps(e); return [s.filter(x => x.ok).length, s.length, s.filter(x => !x.ok)]; };
  const name = e => (LANG === 'en' && e.full_name_en) || e.full_name;
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('التهيئة والترحيب'))}</h1><div class="muted">${esc(tr('قائمة مهام لكل موظف جديد خلال أول 120 يوما. بعضها يكتمل تلقائيا من بياناته، والباقي تعلّمه هنا.'))}</div></div>
      <div class="row"><button class="btn pri" id="onbw">${esc(tr('رسالة الترحيب'))}</button><button class="btn" id="onbc">${esc(tr('بنود المنشأة الخاصة'))}</button></div></div>
    ${tbl([{ t: 'الموظف', h: e => `<b>${esc(name(e))}</b> <span class="small muted num">${esc(e.emp_no || '')}</span>` }, { t: 'المباشرة', h: e => fdate(e.hire_date) },
      { t: 'الإنجاز', h: e => { const [d, n] = prog(e), p = Math.round(d / n * 100); return `<div class="row" style="gap:8px;align-items:center"><div style="flex:1;min-width:80px;height:8px;background:var(--line);border-radius:4px"><div style="width:${p}%;height:8px;border-radius:4px;background:${p === 100 ? 'var(--ok,#1f9d55)' : '#d98e04'}"></div></div><span class="num small">${p}%</span></div>`; } },
      { t: 'ينقصه', h: e => { const m = prog(e)[2]; return m.length ? `<span class="small">${m.slice(0, 3).map(x => esc(tr(x.t))).join('، ')}${m.length > 3 ? ' …' : ''}</span>` : `<span class="badge ok">${esc(tr('اكتملت'))}</span>`; } }],
      news, { empty: 'لا يوجد موظفون جدد خلال آخر 120 يوما', onRow: true })}`;
  bindRows(page, news, e => open(e));
  $('#onbw', page).onclick = () => welcomeSetup(news[0] || S.myEmp);
  $('#onbc', page).onclick = () => modal(tr('بنود المنشأة الخاصة'), `<p class="muted small" style="margin-top:0">${esc(tr('تظهر لكل موظف جديد مع البنود الأساسية. سطر لكل بند.'))}</p>
    <textarea name="items" rows="6" style="width:100%">${esc(custom.join('\n'))}</textarea>`, { onOk: async f => {
      await db.rpc('onboarding_items_set', { p_company: S.cid, p_items: (f.items || '').split('\n') }); await loadContext(); toast(tr('تم الحفظ')); route(); } });
  function open(e) {
    const s = steps(e);
    const d = modal(tr('التهيئة والترحيب') + ' — ' + name(e), `<div style="display:grid;gap:8px">${s.map(x => x.manual
      ? `<label class="row" style="gap:8px"><input type="checkbox" data-onb="${esc(x.k)}"${x.ok ? ' checked' : ''}> ${esc(tr(x.t))}</label>`
      : `<div class="row" style="gap:8px"><span class="badge ${x.ok ? 'ok' : 'wait'}">${x.ok ? '✓' : '○'}</span> ${esc(tr(x.t))} ${x.ok ? '' : `<a class="small" href="${x.h}">${esc(tr('أكمله'))}</a>`}</div>`).join('')}</div>
      <p class="muted small">${esc(tr('البنود بالعلامة تكتمل تلقائيا عند إدخال بياناتها في النظام.'))}</p>
      <h3 style="margin:14px 0 6px">${esc(tr('رسالة الترحيب للموظف'))}</h3>
      <div class="grid2">${field('الزميل المرافق', `<select name="buddy"><option value="">—</option>${Object.values(em).filter(x => x.id !== e.id && (!x.end_date || x.end_date >= td)).map(x => `<option value="${x.id}"${x.id === e.buddy_id ? ' selected' : ''}>${esc(name(x))}</option>`).join('')}</select>`)}
        ${field('وقت المباشرة', inp('time', (e.first_day || {}).time || '', 'type="time"'))}
        ${field('مكان المباشرة', inp('place', (e.first_day || {}).place || '', 'placeholder="' + esc(tr('يُترك فارغا لاستخدام مكان المنشأة')) + '"'))}
        ${field('يستقبله', inp('meet', (e.first_day || {}).meet || '', 'placeholder="' + esc(tr('يُترك فارغا ليكون مديره المباشر')) + '"'))}</div>
      <button type="button" class="btn sm" id="onbp">▶ ${esc(tr('معاينة رسالة الترحيب'))}</button>`, { ok: tr('حفظ'), onOk: async f => {
        await db.rpc('welcome_emp_set', { p_company: S.cid, p_emp: e.id, p_buddy: f.buddy || null, p_day: { time: f.time || '', place: f.place || '', meet: f.meet || '' } });
        delete cache.emps; route(); } });
    $('#onbp', d).onclick = () => { $('#dlg').close(); welcomePlay('emp', { emp: e }); };
    $$('[data-onb]', d).forEach(c => c.onchange = async () => { try {
      if (c.checked) await db.ins('onboarding_marks', { company_id: S.cid, employee_id: e.id, item: c.dataset.onb });
      else await db.del('onboarding_marks', { employee_id: 'eq.' + e.id, item: 'eq.' + c.dataset.onb });
      const m = marks.findIndex(x => x.employee_id === e.id && x.item === c.dataset.onb); if (c.checked && m < 0) marks.push({ employee_id: e.id, item: c.dataset.onb }); if (!c.checked && m >= 0) marks.splice(m, 1);
    } catch (er) { c.checked = !c.checked; toast(er.message); } });
    $$('a', d).forEach(a => a.addEventListener('click', () => $('#dlg').close()));
  }
};

/* «رسالة الترحيب»: what every new employee's welcome says — words from the manager, the company's identity, the day-one plan
   and the first-week tasks (0159); empty parts are simply left out of the message */
function welcomeSetup(sample) {
  const c = S.company || {}, ln = a => (a || []).map(x => x.ar).join('\n'), lnE = a => (a || []).map(x => x.en || '').join('\n');
  const pairs = (ar, en) => { const a = String(ar || '').split('\n'), b = String(en || '').split('\n'); return a.map((x, i) => ({ ar: x.trim(), en: (b[i] || '').trim() })).filter(x => x.ar); };
  let photo = c.wel_photo || '';
  const d = modal(tr('رسالة الترحيب'), `<p class="muted small" style="margin-top:0">${esc(tr('تصل كل موظف جديد باسمه ومسماه وقسمه من الموارد البشرية. تُكتب مرة واحدة، والجزء الفارغ لا يظهر في الرسالة.'))}</p>
    <h3>${esc(tr('كلمة من المدير'))}</h3>
    <div class="grid2">${field('الكلمة', `<textarea name="note" rows="3" maxlength="600">${esc(c.wel_note || '')}</textarea>`)}${field('الكلمة بالإنجليزية', `<textarea name="note_en" rows="3" maxlength="600" dir="ltr">${esc(c.wel_note_en || '')}</textarea>`)}
      ${field('الاسم', inp('from', c.wel_from || '', 'maxlength="80"'))}${field('الاسم بالإنجليزية', inp('from_en', c.wel_from_en || '', 'maxlength="80" dir="ltr"'))}
      ${field('المنصب', inp('title', c.wel_title || '', 'maxlength="80"'))}${field('المنصب بالإنجليزية', inp('title_en', c.wel_title_en || '', 'maxlength="80" dir="ltr"'))}</div>
    <div class="row" style="gap:8px;align-items:center"><span id="wph">${photo ? `<img src="${esc(photo)}" alt="" style="width:48px;height:48px;border-radius:50%;object-fit:cover">` : ''}</span>
      <label class="btn sm">${esc(tr('صورة (اختيارية)'))}<input type="file" id="wpf" accept="image/*" hidden></label><button type="button" class="btn sm" id="wpd"${photo ? '' : ' hidden'}>${esc(tr('إزالة الصورة'))}</button></div>
    <h3>${esc(tr('هوية المنشأة'))}</h3>
    <div class="grid2">${field('نبذة عن المنشأة', `<textarea name="about" rows="2" maxlength="400">${esc(c.about || '')}</textarea>`)}${field('النبذة بالإنجليزية', `<textarea name="about_en" rows="2" maxlength="400" dir="ltr">${esc(c.about_en || '')}</textarea>`)}
      ${field('الرؤية', `<textarea name="vision" rows="2" maxlength="300">${esc(c.vision || '')}</textarea>`)}${field('الرؤية بالإنجليزية', `<textarea name="vision_en" rows="2" maxlength="300" dir="ltr">${esc(c.vision_en || '')}</textarea>`)}
      ${field('القيم (سطر لكل قيمة)', `<textarea name="values" rows="3">${esc(ln(c.core_values))}</textarea>`)}${field('القيم بالإنجليزية (بنفس الترتيب)', `<textarea name="values_en" rows="3" dir="ltr">${esc(lnE(c.core_values))}</textarea>`)}</div>
    <h3>${esc(tr('اليوم الأول والأسبوع الأول'))}</h3>
    <div class="grid2">${field('وقت المباشرة', inp('time', c.wel_time ? String(c.wel_time).slice(0, 5) : '', 'type="time"'))}<div></div>
      ${field('مكان المباشرة', inp('place', c.wel_place || '', 'maxlength="160"'))}${field('المكان بالإنجليزية', inp('place_en', c.wel_place_en || '', 'maxlength="160" dir="ltr"'))}
      ${field('مهام الأسبوع الأول (سطر لكل مهمة)', `<textarea name="week" rows="4" placeholder="${esc(tr('يُترك فارغا لاستخدام المهام المقترحة'))}">${esc(ln(c.wel_week))}</textarea>`)}${field('المهام بالإنجليزية (بنفس الترتيب)', `<textarea name="week_en" rows="4" dir="ltr">${esc(lnE(c.wel_week))}</textarea>`)}</div>
    <button type="button" class="btn sm" id="wpv">▶ ${esc(tr('معاينة رسالة الترحيب'))}</button>`, { wide: true, onOk: async f => {
      await db.rpc('welcome_set', { p_company: S.cid, p: { note: f.note, note_en: f.note_en, from: f.from, from_en: f.from_en, title: f.title, title_en: f.title_en, photo,
        about: f.about, about_en: f.about_en, vision: f.vision, vision_en: f.vision_en, values: pairs(f.values, f.values_en), week: pairs(f.week, f.week_en), time: f.time || '', place: f.place, place_en: f.place_en } });
      await loadContext(); toast(tr('تم الحفظ')); } });
  $('#wpf', d).onchange = async ev => { const fl = ev.target.files[0]; if (!fl) return; try { photo = await imgToLogo(fl); $('#wph', d).innerHTML = `<img src="${esc(photo)}" alt="" style="width:48px;height:48px;border-radius:50%;object-fit:cover">`; $('#wpd', d).hidden = false; } catch (er) { toast(er.message); } };
  $('#wpd', d).onclick = () => { photo = ''; $('#wph', d).innerHTML = ''; $('#wpd', d).hidden = true; };
  // the preview uses what is typed now, before saving
  $('#wpv', d).onclick = () => { const f = formData($('#mform', d));
    const draft = { wel_note: f.note, wel_note_en: f.note_en, wel_from: f.from, wel_from_en: f.from_en, wel_title: f.title, wel_title_en: f.title_en, wel_photo: photo, about: f.about, about_en: f.about_en,
      vision: f.vision, vision_en: f.vision_en, core_values: pairs(f.values, f.values_en), wel_week: pairs(f.week, f.week_en), wel_time: f.time, wel_place: f.place, wel_place_en: f.place_en };
    welcomePlay('emp', { emp: sample, company: Object.assign({}, c, draft), keepOpen: d }); };
}
