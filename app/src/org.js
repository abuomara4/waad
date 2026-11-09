'use strict';
/* ===== organisation chart: built from each employee's direct manager; departments with their heads ===== */
const orgInitials = n => String(n || '').trim().split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0]).join('');
VIEWS['#/org'] = async (page, arg, q) => {
  let [emps, deps] = await Promise.all([db.rpc('org_chart', { p_company: S.cid }), db.get('departments', { company_id: 'eq.' + S.cid, order: 'name' })]);
  learnNames(emps, BILINGUAL.employees);
  const hr = isHR(), view = q.get('v') === 'dept' ? 'dept' : 'chart', depF = q.get('d') || '';
  // #7 a non-HR viewer sees only their own branch (themselves and everyone reporting up to them); HR sees the whole chart
  if (!hr && S.emp) { const keep = new Set([S.emp]); let add = true; while (add) { add = false; for (const e of emps) if (e.manager_id && keep.has(e.manager_id) && !keep.has(e.id)) { keep.add(e.id); add = true; } } emps = emps.filter(e => keep.has(e.id)); }
  const by = {}, dm = {}; emps.forEach(e => by[e.id] = e); deps.forEach(d => dm[d.id] = d);
  const set = depF ? emps.filter(e => (depF === 'none' ? !e.department_id : e.department_id === depF)) : emps, inSet = new Set(set.map(e => e.id));
  const kids = {}; set.forEach(e => { const p = e.manager_id && inSet.has(e.manager_id) ? e.manager_id : ''; (kids[p] = kids[p] || []).push(e); });
  const size = {}; const count = id => size[id] != null ? size[id] : (size[id] = (kids[id] || []).reduce((a, k) => a + 1 + count(k.id), 0));
  const roots = (kids[''] || []).sort((a, b) => count(b.id) - count(a.id));
  const rtl = document.documentElement.dir === 'rtl', big = set.length > 40;
  const node = (e, lvl) => { const ch = (kids[e.id] || []).slice().sort((a, b) => count(b.id) - count(a.id) || String(a.emp_no).localeCompare(String(b.emp_no), undefined, { numeric: true }));
    if (rtl) ch.reverse();
    const d = dm[e.department_id], head = d && d.head_id === e.id;
    return `<li${ch.length && big && lvl >= 2 ? ' class="col"' : ''}><div class="onode${head ? ' ohead' : ''}" data-id="${e.id}" tabindex="0"><div class="oav" data-nt>${esc(orgInitials(LANG === 'en' ? e.full_name_en || tr(e.full_name) : e.full_name))}</div>
      <div class="otx"><b>${esc(e.full_name)}</b><div class="small muted">${esc(e.job_title || e.job_title_en || '')}</div>${d ? `<div class="small"><span class="badge${head ? ' info' : ''}">${esc(d.name)}</span>${head ? ` <span class="small muted">${esc('رئيس القسم')}</span>` : ''}</div>` : ''}</div>
      ${ch.length ? `<button type="button" class="otog" data-tog title="${esc(tr('إظهار/إخفاء الفريق'))}"><span class="num">${count(e.id)}</span></button>` : ''}</div>${ch.length ? `<ul>${ch.map(k => node(k, lvl + 1)).join('')}</ul>` : ''}</li>`; };
  // what HR should fix
  const missingMgr = emps.filter(e => e.manager_id && !by[e.manager_id]);
  const allRoots = emps.filter(e => !e.manager_id || !by[e.manager_id]), topId = allRoots.slice().sort((a, b) => { const c = x => emps.filter(y => y.manager_id === x.id).length; return c(b) - c(a); })[0];
  const noMgr = emps.filter(e => !e.manager_id && (!topId || e.id !== topId.id));
  const noDept = emps.filter(e => !e.department_id), noHead = deps.filter(d => !d.head_id || !by[d.head_id]);
  const issues = hr ? [noMgr.length && [tr('بلا مدير مباشر') + ' (' + noMgr.length + ')', noMgr], missingMgr.length && [tr('مديرهم المباشر انتهت خدمته') + ' (' + missingMgr.length + ')', missingMgr],
    noDept.length && [tr('بلا قسم') + ' (' + noDept.length + ')', noDept]].filter(Boolean) : [];
  const nameBtn = e => `<button type="button" class="btn sm" data-emp="${e.id}">${esc(e.full_name)}</button>`;
  page.innerHTML = `<div class="head"><div><h1>الهيكل التنظيمي</h1><div class="muted">${esc(tr('موظف على رأس العمل'))}: <span class="num">${emps.length}</span> · ${esc(tr('الأقسام'))}: <span class="num">${deps.length}</span></div></div>
      <div class="row">${hr ? `<select id="ovis" style="width:auto" title="${esc(tr('من يرى الهيكل التنظيمي'))}">${[['all', 'يراه كل الموظفين'], ['managers', 'يراه المدراء فقط'], ['hr', 'يراه الموارد البشرية فقط']].map(([k, t]) => opt(k, t, (S.company && S.company.org_visibility) || 'all')).join('')}</select>` : ''}<div class="seg"><a class="${view === 'chart' ? 'on' : ''}" href="#/org${depF ? '?d=' + depF : ''}">المخطط</a><a class="${view === 'dept' ? 'on' : ''}" href="#/org?v=dept">حسب الأقسام</a></div>
      ${view === 'chart' ? `<select id="odep" style="width:auto"><option value="">كل الأقسام</option>${deps.map(d => opt(d.id, d.name, depF)).join('')}<option value="none"${depF === 'none' ? ' selected' : ''}>بلا قسم</option></select>
      <input id="osq" type="search" placeholder="ابحث باسم أو مسمى" style="width:190px"><button class="btn" id="oexp">توسيع / طي</button><button class="btn" id="oprn">طباعة</button>` : ''}</div></div>
    ${issues.length ? `<div class="card" id="oiss"><b>${esc('يحتاج ضبط')}</b>${issues.map(([t, l]) => `<div class="row" style="margin-top:8px;align-items:baseline"><span class="small muted" style="min-width:150px">${t}</span>${l.slice(0, 12).map(nameBtn).join('')}${l.length > 12 ? '<span class="muted">…</span>' : ''}</div>`).join('')}
      ${noHead.length ? `<div class="small muted" style="margin-top:8px">${esc(tr('أقسام بلا رئيس'))}: ${noHead.map(d => esc(d.name)).join('، ')} — <a href="#/org?v=dept">${esc('حدّد رئيس القسم')}</a></div>` : ''}</div>` : ''}
    ${view === 'chart' ? (set.length ? `<div class="card orgcard"><div class="orgwrap" id="orgw"><ul class="org">${(rtl ? roots.slice().reverse() : roots).map(e => node(e, 0)).join('')}</ul></div></div>
      <p class="muted small">${esc('يُبنى الهيكل من «المدير المباشر» لكل موظف.')} ${hr ? esc('اضغط على أي موظف لتغيير مديره المباشر أو قسمه.') : ''} ${esc('الرقم على البطاقة عدد من يتبعه مباشرة وغير مباشرة.')}</p>`
      : '<div class="note">لا يوجد موظفون في هذا القسم.</div>')
    : deps.concat([{ id: '', name: 'بلا قسم', _none: 1 }]).map(d => { const mem = emps.filter(e => (e.department_id || '') === d.id); if (d._none && !mem.length) return '';
        return `<div class="card odept"><div class="row" style="justify-content:space-between"><h2 style="margin:0">${esc(d.name)} <span class="muted small num">${mem.length}</span></h2>
          ${d._none ? '' : hr ? `<label class="row small" style="gap:6px">${esc('رئيس القسم')} <select data-head="${d.id}" style="width:auto"><option value="">—</option>${emps.map(e => opt(e.id, e.full_name + ' (' + e.emp_no + ')', d.head_id || '')).join('')}</select></label>`
            : `<span class="small muted">${esc('رئيس القسم')}: ${d.head_id && by[d.head_id] ? esc(by[d.head_id].full_name) : '—'}</span>`}</div>
          ${tbl([{ t: 'الاسم', h: e => esc(e.full_name) + (d.head_id === e.id ? ' <span class="badge info">' + esc('رئيس القسم') + '</span>' : '') }, { t: 'المسمى', h: e => esc(e.job_title || e.job_title_en || '') }, { t: 'المدير المباشر', h: e => esc(e.manager_id && by[e.manager_id] ? by[e.manager_id].full_name : '—') }], mem, { empty: 'لا يوجد موظفون', onRow: true })}</div>`; }).join('')}`;
  const place = id => { const e = by[id]; if (!e) return;
    const desc = new Set(); const walk = x => (emps.filter(y => y.manager_id === x)).forEach(y => { desc.add(y.id); walk(y.id); }); walk(id);
    const reports = emps.filter(y => y.manager_id === id);
    const info = `<p><b>${esc(e.full_name)}</b> <span class="muted num">${esc(e.emp_no)}</span><br><span class="muted">${esc(e.job_title || '')}</span></p>
      <p class="small">${esc('يتبعه مباشرة')}: <b class="num">${reports.length}</b> · ${esc('إجمالي الفريق')}: <b class="num">${desc.size}</b></p>`;
    if (!hr) return modal('بطاقة الموظف', info + `<p class="small">${esc('المدير المباشر')}: ${e.manager_id && by[e.manager_id] ? esc(by[e.manager_id].full_name) : '—'}</p><p class="small">${esc('القسم')}: ${dm[e.department_id] ? esc(dm[e.department_id].name) : '—'}</p>`);
    const m = modal('مكان الموظف في الهيكل', info + `<div class="fg">${field('المدير المباشر', `<select name="mgr"><option value="">— ${esc('بلا مدير (أعلى الهيكل)')}</option>${emps.filter(x => x.id !== id && !desc.has(x.id)).map(x => opt(x.id, x.full_name + ' (' + x.emp_no + ')', e.manager_id || '')).join('')}</select>`)}
      ${field('القسم', `<select name="dep"><option value="">—</option>${deps.map(d => opt(d.id, d.name, e.department_id || '')).join('')}</select>`)}
      ${reports.length ? field('عند نقل الموظف', `<select name="team">${opt('stay', 'يبقى فريقه تابعاً له')}${opt('up', 'ينتقل فريقه إلى مديره الحالي')}</select>`, 'wide') : ''}</div>
      <div class="row" style="margin-top:8px"><a class="btn sm" href="#/docs/${e.id}" onclick="document.getElementById('dlg').close()">${esc('ملف الموظف')}</a></div>
      <p class="muted small">${esc('لا يمكن اختيار أحد أفراد فريقه مديراً له حتى لا يصير التسلسل دائرياً.')}</p>`, {
      onOk: async f => {
        if (f.team === 'up' && (f.mgr || null) !== (e.manager_id || null)) for (const r of reports) await db.upd('employees', { id: 'eq.' + r.id }, { manager_id: e.manager_id || null });
        await db.upd('employees', { id: 'eq.' + id }, { manager_id: blank(f.mgr), department_id: blank(f.dep) }); cache.emps = null; toast('تم الحفظ'); route(); } });
    return m; };
  $$('.onode', page).forEach(n => { n.onclick = ev => { if (ev.target.closest('[data-tog]')) return; place(n.dataset.id); }; n.onkeydown = ev => { if (ev.key === 'Enter') place(n.dataset.id); }; });
  $$('[data-tog]', page).forEach(b => b.onclick = () => b.closest('li').classList.toggle('col'));
  $$('[data-emp]', page).forEach(b => b.onclick = () => place(b.dataset.emp));
  $$('.odept', page).forEach((c, i) => { const d = deps.concat([{ id: '' }])[i]; const mem = emps.filter(e => (e.department_id || '') === (d ? d.id : '')); bindRows(c, mem, e => place(e.id)); });
  $$('[data-head]', page).forEach(s => s.onchange = async () => { try { await db.upd('departments', { id: 'eq.' + s.dataset.head }, { head_id: blank(s.value) }); cache.deps = null; toast('تم الحفظ'); route(); } catch (er) { toast(er.message); } });
  if ($('#odep', page)) $('#odep', page).onchange = ev => location.hash = '#/org' + (ev.target.value ? '?d=' + ev.target.value : '');
  if ($('#oexp', page)) $('#oexp', page).onclick = () => { const col = $$('#orgw li.col', page).length; $$('#orgw li', page).forEach(li => li.classList.toggle('col', !col && li.querySelector('ul') && li.parentElement.closest('li') != null)); };
  if ($('#osq', page)) $('#osq', page).oninput = ev => { const t = normHead(ev.target.value); $$('.onode', page).forEach(n => n.classList.remove('ohit')); if (t.length < 2) return;
    const hits = $$('.onode', page).filter(n => normHead(n.textContent).includes(t) || normHead(tr(n.textContent)).includes(t));
    hits.forEach(n => { n.classList.add('ohit'); let li = n.closest('li').parentElement.closest('li'); while (li) { li.classList.remove('col'); li = li.parentElement.closest('li'); } });
    if (hits[0]) hits[0].scrollIntoView({ block: 'nearest', inline: 'center', behavior: 'smooth' }); };
  if ($('#ovis', page)) $('#ovis', page).onchange = async ev => { try { await db.rpc('org_visibility_set', { p_company: S.cid, p_mode: ev.target.value }); await loadContext(); toast('تم الحفظ'); } catch (er) { toast(er.message); } };
  if ($('#oprn', page)) $('#oprn', page).onclick = () => { const doc = document.createElement('div'); doc.className = 'pdoc'; doc.innerHTML = printHead(tr('الهيكل التنظيمي') + (depF && dm[depF] ? ' — ' + dm[depF].name : ''));
    const w = $('#orgw', page), cp = w.cloneNode(true); cp.removeAttribute('id'); cp.querySelectorAll('[data-tog]').forEach(x => x.replaceWith(Object.assign(document.createElement('span'), { className: 'otog', innerHTML: x.innerHTML })));
    cp.style.overflow = 'visible'; cp.style.zoom = Math.min(1, 1040 / Math.max(1, w.scrollWidth)); doc.appendChild(cp); printWith(doc, '@page{size:A4 landscape;margin:10mm}'); };
};
