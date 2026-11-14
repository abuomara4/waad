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
  const secs = guideSections(), open = new Set(navItems().map(i => i.h).filter(Boolean).concat(['#/home', '#/help']));
  const card = it => `<details class="card gitem" data-g="${esc(it.id)}"><summary><b>${esc(hT(it.t))}</b></summary>
      <div class="gbody"><ol>${it.s.map(x => `<li>${esc(hT(x))}</li>`).join('')}</ol>
        ${it.img ? `<img class="gshot" src="${esc(guideImg(it.img))}" alt="${esc(hT(it.t))}" loading="lazy" onerror="this.remove()">` : ''}</div>
      ${it.go && open.has(it.go) ? `<a class="small" href="${esc(it.go)}">${esc(LANG === 'en' ? 'Try it now' : 'جرّبها الآن')}</a>` : ''}</details>`;
  page.innerHTML = `<div class="head"><div><h1>${esc(tr('دليل الاستخدام'))}</h1><div class="muted">${esc(tr('خطوات قصيرة لما تستخدمه في وعد، والصور من منشأة تجريبية.'))}</div></div>
      ${has('owner', 'admin', 'hr') ? `<button class="btn pri" id="gprint">${esc(tr('اطبع دليل الموظف'))}</button>` : ''}</div>
    <input id="gq" type="search" aria-label="${esc(tr('بحث في الدليل'))}" placeholder="${esc(tr('ابحث، مثل: إجازة، راتب، حضور'))}" style="max-width:420px;margin-bottom:12px">
    <div data-nt>${secs.map(k => `<section class="gsec" data-sec="${k}"><h2>${esc(hT(GUIDE[k].t))}</h2>
      ${GUIDE[k].items.filter(it => !it.when || it.when()).map(card).join('')}</section>`).join('')}</div>`;
  $('#gq', page).oninput = e => { const q = e.target.value.trim().toLowerCase();
    $$('.gitem', page).forEach(x => { const hit = !q || x.textContent.toLowerCase().includes(q); x.style.display = hit ? '' : 'none'; if (q && hit) x.open = true; }); };
  if ($('#gprint', page)) $('#gprint', page).onclick = guidePrint;
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
