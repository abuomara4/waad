'use strict';
/* «دليل الاستخدام» (#/guide): short how-to cards with screenshots (guide_lib.js holds the texts), shown by the reader's role;
   a welcome on an employee's first sign-in; and a one-page employee guide the company prints with its own code and link. */
function guideSections() {
  const all = [['emp', !!S.emp], ['mgr', has('manager') || !!S.hasTeam], ['admin', has('owner', 'admin', 'hr')]];
  const mine = all.filter(([, on]) => on).map(([k]) => k);
  return mine.length ? mine : ['emp', 'mgr'];
}
const guideImg = n => `${SITE_URL}img/guide/${n}-${LANG === 'en' ? 'en' : 'ar'}.webp`;
const guideLink = () => location.origin + location.pathname + '?c=' + ((S.company || {}).code || '');

VIEWS['#/guide'] = async page => {
  const boss = has('owner', 'admin', 'hr'), res = await db.get('guide_quiz_results', { company_id: 'eq.' + S.cid, order: 'taken_at.desc' }).catch(() => []);
  const mineRes = res.filter(r => S.session && r.user_id === S.session.user.id);
  const secs = guideSections(), open = new Set(navItems().map(i => i.h).filter(Boolean).concat(['#/home', '#/help']));
  const card = it => `<details class="card gitem" data-g="${esc(it.id)}"><summary><b>${esc(hT(it.t))}</b></summary>
      <div class="gbody"><ol>${it.s.map(x => `<li>${esc(hT(x))}</li>`).join('')}</ol>
        ${it.img ? `<img class="gshot" src="${esc(guideImg(it.img))}" alt="${esc(hT(it.t))}" loading="lazy" onerror="this.remove()">` : ''}</div>
      ${it.go && open.has(it.go) ? `<a class="small" href="${esc(it.go)}">${esc(LANG === 'en' ? 'Try it now' : 'جرّبها الآن')}</a>` : ''}</details>`;
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('دليل الاستخدام'))}</h1><div class="muted">${esc(tr('خطوات قصيرة لما تستخدمه في وعد، والصور من منشأة تجريبية.'))}</div></div>
      ${has('owner', 'admin', 'hr') ? `<button class="btn pri" id="gprint">${esc(tr('اطبع دليل الموظف'))}</button>` : ''}</div>
    <input id="gq" type="search" aria-label="${esc(tr('بحث في الدليل'))}" placeholder="${esc(tr('ابحث، مثل: إجازة، راتب، حضور'))}" style="max-width:420px;margin-bottom:12px">
    <div data-nt>${secs.map(k => `<section class="gsec" data-sec="${k}"><h2>${esc(hT(GUIDE[k].t))}</h2>
      ${GUIDE[k].items.filter(it => !it.when || it.when()).map(card).join('')}${quizCard(k, mineRes)}</section>`).join('')}</div>
    ${boss ? `<section class="gsec" id="gres"><h2>${esc(tr('نتائج اختبار الدليل'))}</h2>${await quizResults(res)}</section>` : ''}`;
  $('#gq', page).oninput = e => { const q = e.target.value.trim().toLowerCase();
    $$('.gitem', page).forEach(x => { const hit = !q || x.textContent.toLowerCase().includes(q); x.style.display = hit ? '' : 'none'; if (q && hit) x.open = true; }); };
  if ($('#gprint', page)) $('#gprint', page).onclick = guidePrint;
  $$('[data-quiz]', page).forEach(b => b.onclick = () => quizForm(b.dataset.quiz));
  if (/[?&]t=results/.test(location.hash) && $('#gres', page)) $('#gres', page).scrollIntoView();
};

// one A4 page for the employees: the link, the company code, how to sign in, and the main services
function guidePrint() {
  const c = S.company || {}, items = GUIDE.emp.items.filter(it => ['login', 'leave', 'track', 'slip', 'profile'].includes(it.id) || (it.id === 'att' && it.when()));
  const doc = document.createElement('div'); doc.className = 'pdoc gprint'; doc.setAttribute('data-nt', '');
  doc.innerHTML = printHead(LANG === 'en' ? 'Employee guide to Waad' : 'دليل الموظف في نظام وعد') + `
    <div class="gpbox"><div><div class="muted">${esc(LANG === 'en' ? 'Company code' : 'رمز المنشأة')}</div><div class="gpcode">${esc(c.code || '')}</div></div>
      <div><div class="muted">${esc(LANG === 'en' ? 'Sign-in link' : 'رابط الدخول')}</div><div class="num" dir="ltr" style="word-break:break-all">${esc(guideLink())}</div></div></div>
    ${items.map(it => `<div class="gpitem"><h3>${esc(hT(it.t))}</h3><ol>${it.s.map(x => `<li>${esc(hT(x))}</li>`).join('')}</ol></div>`).join('')}
    <p class="muted small">${esc(LANG === 'en' ? 'More: open «User guide» in the menu after you sign in.' : 'للمزيد: افتح «دليل الاستخدام» من القائمة بعد دخولك.')}</p>`;
  printWith(doc, '@page{size:A4 portrait;margin:10mm}');
}

// an employee's first weeks: a card on top of the home page with three things to know, until they close it
function guideWelcome(page) {
  if (!S.emp || !plainEmp() || !page || $('#gwel', page)) return;
  const k = 'waad.guided.' + S.cid + '.' + S.emp; if (LS.get(k)) return;
  const tip = (t, d, h) => `<li><a href="${h}"><b>${esc(tr(t))}</b></a> <span class="muted">${esc(tr(d))}</span></li>`;
  const el = document.createElement('div'); el.className = 'card gwel'; el.id = 'gwel';
  el.innerHTML = `<button type="button" class="x" id="gwx" aria-label="${esc(tr('إغلاق'))}">×</button><h2>${esc(tr('أهلا بك في وعد'))}</h2><ul>
      ${tip('طلباتي', 'اطلب إجازة أو استئذانا أو تعريفا بالراتب وتابع حالته.', '#/requests')}
      ${S.company && S.company.att_enabled && !(S.myEmp && S.myEmp.att_exempt) ? tip('حضوري', 'سجّل حضورك وانصرافك من جوالك.', '#/attendance') : ''}
      ${tip('قسائم الراتب', 'تظهر قسيمتك كل شهر بعد اعتماد الرواتب.', '#/payslips')}</ul>
    <a class="btn sm pri" href="#/guide">${esc(tr('افتح دليل الاستخدام'))}</a>`;
  page.prepend(el);
  $('#gwx', el).onclick = () => { LS.set(k, 1); el.remove(); };
}

/* «اختبر فهمك»: the questions of a role's guide; the database marks the answers and the owner and HR see the result */
const QSEC = { emp: 'للموظف', mgr: 'للمدير المباشر' };
function quizCard(k, mine) {
  if (!S.emp || typeof GUIDE_QUIZ === 'undefined' || !GUIDE_QUIZ[k]) return '';
  const last = mine.find(r => r.section === k);
  return `<div class="card gquiz"><h3>${esc(tr('اختبر فهمك'))}</h3>
    <p class="muted">${esc(tr('أسئلة قصيرة عن هذا الدليل، وتصل نتيجتك لمالك المنشأة والموارد البشرية.'))}</p>
    ${last ? `<p>${esc(tr('آخر نتيجة'))}: <b class="num">${last.score} / ${last.total}</b> <span class="badge ${last.passed ? 'ok' : 'bad'}">${esc(tr(last.passed ? 'ناجح' : 'لم يجتز'))}</span> <span class="muted small num">${esc(fdate(last.taken_at))}</span></p>` : ''}
    <button class="btn pri" data-quiz="${k}">${esc(tr(last ? 'أعد الاختبار' : 'ابدأ الاختبار'))}</button></div>`;
}
function quizForm(k) {
  const qs = GUIDE_QUIZ[k];
  const d = modal(tr('اختبر فهمك') + ' — ' + tr(QSEC[k]), `<div data-nt>${qs.map((x, i) => `<fieldset class="gq" data-q="${x.id}"><legend><span class="num">${i + 1}.</span> ${esc(hT(x.q))}</legend>
      ${x.a.map((o, j) => `<label class="gqo"><input type="radio" name="q_${x.id}" value="${j}"> <span>${esc(hT(o))}</span></label>`).join('')}</fieldset>`).join('')}</div>`, {
    ok: 'أرسل الإجابات', wide: true, onOk: async () => {
      const ans = {}; qs.forEach(x => { const c = d.querySelector(`input[name="q_${x.id}"]:checked`); if (c) ans[x.id] = +c.value; });
      if (Object.keys(ans).length < qs.length) throw new Error('أجب عن كل الأسئلة');
      const r = await db.rpc('guide_quiz_submit', { p_company: S.cid, p_section: k, p_answers: ans });
      setTimeout(() => quizDone(k, r), 60);
    } });
}
function quizDone(k, r) {
  const wrong = new Set(r.wrong || []);
  modal(tr('نتيجتك'), `<p style="font-size:20px;margin-top:0"><b class="num">${r.score} / ${r.total}</b> <span class="badge ${r.passed ? 'ok' : 'bad'}">${esc(tr(r.passed ? 'ناجح' : 'لم يجتز'))}</span></p>
    ${wrong.size ? `<p>${esc(tr('راجع في الدليل ما يخص هذه الأسئلة ثم أعد الاختبار:'))}</p><ul data-nt>${GUIDE_QUIZ[k].filter(x => wrong.has(x.id)).map(x => `<li>${esc(hT(x.q))}</li>`).join('')}</ul>`
      : `<p>${esc(tr('أحسنت، أجبت عن كل الأسئلة إجابة صحيحة.'))}</p>`}
    <p class="muted small">${esc(tr('وصلت نتيجتك لمالك المنشأة والموارد البشرية.'))}</p>`, { ok: 'تم', onOk: async () => {} });
  $('#dlg').addEventListener('close', () => route(), { once: true });
}
// for the owner, admins and HR: the latest attempt of each person in each guide, and how many tries it took
async function quizResults(rows) {
  const em = await employeesMap().catch(() => ({})), seen = new Map();
  rows.forEach(r => { const key = r.user_id + r.section; if (!seen.has(key)) seen.set(key, Object.assign({ tries: 0 }, r)); seen.get(key).tries++; });
  const list = [...seen.values()];
  return tbl([{ t: 'الموظف', h: r => { const e = em[r.employee_id]; return e ? esc(e.full_name) + ` <span class="muted small num">${esc(e.emp_no)}</span>` : '—'; } },
    { t: 'الدليل', h: r => esc(tr(QSEC[r.section] || r.section)) }, { t: 'النتيجة', r: 1, h: r => `<span class="num">${r.score} / ${r.total}</span>` },
    { t: 'الحالة', h: r => `<span class="badge ${r.passed ? 'ok' : 'bad'}">${esc(tr(r.passed ? 'ناجح' : 'لم يجتز'))}</span>` },
    { t: 'المحاولات', r: 1, h: r => `<span class="num">${r.tries}</span>` }, { t: 'التاريخ', h: r => `<span class="num">${esc(fdate(r.taken_at))}</span>` }],
    list, { empty: 'لم يختبر أحد بعد. يظهر الاختبار في آخر دليل الموظف ودليل المدير.' });
}
