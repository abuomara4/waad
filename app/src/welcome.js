'use strict';
/* «رسالة الترحيب»: a short animated welcome that plays like a video, made in the browser for the person watching —
   the company owner (his name, his company, the modules he has, three first steps) and every new employee (name, company,
   job, department, manager, start date, what he can do from his phone). Nothing is rendered on a server or stored: free,
   instant, and always in the language the person chose. Sound effects are synthesized (Web Audio), no music, no files.
   Texts carry both languages here (W(ar, en)), so this file is excluded from the i18n extract. */
const W = (ar, en) => (LANG === 'en' ? en : ar);
const wvFirst = (ar, en) => { const a = String(ar || '').trim().split(/\s+/)[0] || '', e = String(en || '').trim().split(/\s+/)[0] || ''; return LANG === 'en' ? (e || a) : a; };
let WV = {};   // what this playback shows: the employee and company (HR previews pass their own)
const wvC = () => WV.c || S.company || {};
const wvCo = () => { const c = wvC(); return LANG === 'en' ? (c.name_en || c.name || '') : (c.name || ''); };
const wvKey = kind => 'waad.wv.' + kind + '.' + S.cid + '.' + ((S.session && S.session.user && S.session.user.id) || '');

/* ---- sound: tiny synthesized effects, quiet, played only after the viewer pressed play ---- */
let wvAC = null;
function wvSfx(kind, muted) {
  if (muted) return;
  try {
    wvAC = wvAC || new (window.AudioContext || window.webkitAudioContext)(); const ac = wvAC, t = ac.currentTime, g = ac.createGain(); g.connect(ac.destination);
    const tone = (f, at, dur, vol, type = 'sine', f2) => { const o = ac.createOscillator(), v = ac.createGain(); o.type = type; o.frequency.setValueAtTime(f, t + at); if (f2) o.frequency.exponentialRampToValueAtTime(f2, t + at + dur);
      v.gain.setValueAtTime(0.0001, t + at); v.gain.exponentialRampToValueAtTime(vol, t + at + 0.012); v.gain.exponentialRampToValueAtTime(0.0001, t + at + dur); o.connect(v); v.connect(g); o.start(t + at); o.stop(t + at + dur + 0.05); };
    if (kind === 'whoosh') {
      const n = ac.sampleRate * 0.5, b = ac.createBuffer(1, n, ac.sampleRate), d = b.getChannelData(0); for (let i = 0; i < n; i++) d[i] = (Math.random() * 2 - 1) * Math.sin(Math.PI * i / n);
      const s = ac.createBufferSource(), f = ac.createBiquadFilter(), v = ac.createGain(); s.buffer = b; f.type = 'bandpass'; f.Q.value = 1.2; f.frequency.setValueAtTime(300, t); f.frequency.exponentialRampToValueAtTime(3200, t + 0.45);
      v.gain.value = 0.09; s.connect(f); f.connect(v); v.connect(g); s.start(t);
    } else if (kind === 'pop') tone(520, 0, 0.12, 0.12, 'sine', 900);
    else if (kind === 'click') tone(1800, 0, 0.04, 0.06, 'triangle');
    else if (kind === 'chime') { tone(784, 0, 0.9, 0.08); tone(1175, 0.08, 0.9, 0.06); tone(1568, 0.16, 1.1, 0.05); }
  } catch (e) { /* no sound on this device */ }
}

/* ---- the scenes: html + length in seconds + effects inside the scene ---- */
const wvIn = (html, d, kind = 'rise', extra = '') => `<div class="wv-in wv-${kind}" style="--d:${d}s${extra ? ';' + extra : ''}">${html}</div>`;
const wvLogo = () => `<img class="wv-logo" src="${LOGO_D}" alt="وعد Waad">`;
const wvCoLogo = () => { const l = wvC().logo; return l && /^(data:image\/|https:\/\/)/.test(l) ? `<img class="wv-colog" src="${esc(l)}" alt="">` : ''; };
const wvList = (items, d0) => `<ul class="wv-list">${items.map((x, i) => `<li class="wv-in wv-side" style="--d:${(d0 + i * 0.45).toFixed(2)}s"><span class="wv-ic">${x[0]}</span><span><b>${esc(x[1])}</b>${x[2] ? `<small>${esc(x[2])}</small>` : ''}</span></li>`).join('')}</ul>`;

function wvOwnerScenes() {
  const name = wvFirst(S.myEmp && S.myEmp.full_name, S.myEmp && S.myEmp.full_name_en), co = wvCo();
  const mods = Object.keys(MODULES).filter(m => modOn(m));
  const ML = { hr: ['👥', 'الموارد البشرية', 'HR and payroll'], finance: ['📊', 'المالية والمحاسبة', 'Finance and accounting'], sales: ['🧾', 'المبيعات', 'Sales'], purch: ['🛒', 'المشتريات', 'Purchasing'], stock: ['📦', 'المخزون', 'Inventory'], proj: ['🏗️', 'المشاريع', 'Projects'] };
  const steps = [['1', W('أضف موظفيك', 'Add your employees'), W('أو استوردهم من Excel دفعة واحدة', 'or import them from Excel at once')]];
  steps.push(['2', W('أعطِ فريقك الدخول', 'Give your team access'), W('رمز منشأتك: ', 'Your company code: ') + ((S.company || {}).code || '')]);
  steps.push(['3', modOn('hr') ? W('جهّز أول مسير رواتب', 'Prepare your first payroll') : W('أصدر أول فاتورة', 'Issue your first invoice'),
    modOn('hr') ? W('الراتب والتأمينات وملف حماية الأجور', 'Pay, GOSI and the wage protection file') : W('فاتورة ضريبية برمز QR', 'A tax invoice with a QR code')]);
  return [
    { s: 3.2, sfx: [[0.2, 'whoosh']], h: `${wvIn(wvLogo(), 0.1, 'pop')}${wvIn(`<span class="wv-k">${esc(W('رسالة ترحيب', 'A welcome message'))}</span>`, 0.9)}` },
    { s: 4.2, sfx: [[0.4, 'pop']], h: `${wvIn(`<h2 class="wv-h">${esc(name ? W('أهلًا ' + name, 'Welcome, ' + name) : W('أهلًا بك', 'Welcome'))}</h2>`, 0.15)}
        ${wvIn(`<p class="wv-p">${esc(W('مرحبًا بـ', 'Welcome to Waad, '))}<b class="wv-gold">${esc(co)}</b>${esc(W(' في وعد', ''))}</p>`, 0.8)}${wvIn('<i class="wv-bar"></i>', 1.3, 'draw')}` },
    { s: 4.6, sfx: [[0.6, 'pop'], [1.5, 'pop']], h: `${wvIn(`<h3 class="wv-h3">${esc(W('منشأتك كاملة في نظام واحد', 'Your whole company in one system'))}</h3>`, 0.1)}
        <div class="wv-chips">${mods.map((m, i) => wvIn(`<span>${ML[m][0]}</span>${esc(W(ML[m][1], ML[m][2]))}`, 0.5 + i * 0.22, 'pop', '')).join('')}</div>` },
    { s: 6.2, sfx: [[0.5, 'click'], [0.95, 'click'], [1.4, 'click']], h: `${wvIn(`<h3 class="wv-h3">${esc(W('ابدأ في ثلاث خطوات', 'Start in three steps'))}</h3>`, 0.1)}${wvList(steps, 0.5)}` },
    { s: 4.4, sfx: [[0.5, 'pop']], h: `${wvIn(`<h3 class="wv-h3">${esc(W('معك في كل خطوة', 'With you at every step'))}</h3>`, 0.1)}
        ${wvList([['📘', W('دليل الاستخدام', 'User guide'), W('خطوات قصيرة بالصور لكل دور', 'Short illustrated steps for every role')], ['💬', W('الدعم الفني', 'Support'), W('اكتب لنا من داخل النظام', 'Write to us from inside Waad')]], 0.5)}` },
    { s: 0, end: true, sfx: [[0.3, 'chime']], h: `${wvIn(wvLogo(), 0.1, 'pop')}${wvIn(`<h3 class="wv-h3">${esc(W('نتمنى لـ' + co + ' انطلاقة موفقة', 'Wishing ' + co + ' a great start'))}</h3>`, 0.5)}
        ${wvIn(`<div class="wv-btns"><a class="btn pri" href="#/welcome" data-wvgo>${esc(W('ابدأ التجهيز', 'Start the setup'))}</a><button type="button" class="btn" data-wvre>${esc(W('أعد المشاهدة', 'Watch again'))}</button></div>`, 1.0)}` },
  ];
}

// the topics of «دليل الاستخدام» this person will use: his own requests and pay, his team's if he manages one,
// and those of his department's screens (only what his job opens in the menu)
function wvGuideTopics() {
  if (typeof GUIDE === 'undefined') return [];
  const prev = !!(WV.e && WV.e.id !== S.emp);   // HR previewing someone else's message: the employee's own topics, not the viewer's
  const open = new Set(prev ? [] : navItems().map(i => i.h).filter(Boolean)), secs = prev || typeof guideSections !== 'function' ? ['emp'] : guideSections();
  const want = { emp: ['leave', 'att', 'slip', 'sign'], mgr: ['appr', 'team', 'prob'], admin: null };
  const out = [];
  secs.forEach(k => (GUIDE[k] ? GUIDE[k].items : []).filter(it => (!it.when || it.when()) && (prev || !it.go || open.has(it.go)) && (!want[k] || want[k].includes(it.id)))
    .forEach(it => { if (out.length < 4 && !out.some(o => o.id === it.id)) out.push(it); }));
  return out;
}

const wvInit = n => { const p = String(n || '').trim().split(/\s+/); return (p[0] || '').slice(0, 1) + (p.length > 1 ? p[p.length - 1].slice(0, 1) : ''); };
const wvT = (ar, en) => (LANG === 'en' && en ? en : ar) || '';
const WV_WEEK = [['أكمل بياناتك وصورتك في «ملفي»', 'Complete your details in «My profile»'], ['اقرأ سياسات المنشأة وأقرّ بها', 'Read and accept the company policies'],
  ['وقّع عقدك ومستنداتك من «توقيعاتي»', 'Sign your contract and documents in «My signatures»'], ['اجلس مع مديرك واتفقا على أهداف فترة التجربة', 'Meet your manager and agree your probation goals'],
  ['أكمل «اختبر فهمك» في دليل الاستخدام', 'Complete «Test yourself» in the user guide']];

function wvEmpScenes(me, all) {
  const e = WV.e || S.myEmp || {}, c = wvC(), co = wvCo(), d = me || {};
  const parts = String((LANG === 'en' && e.full_name_en) || e.full_name || '').trim().split(/\s+/).filter(Boolean);
  const name = parts.length > 1 ? parts[0] + ' ' + parts[parts.length - 1] : (parts[0] || '');   // first and family name
  const job = (LANG === 'en' && (d.job_en || e.job_title_en)) || d.job || e.job_title || '';
  const hr = W('إدارة الموارد البشرية', 'Human Resources');
  const sc = [];
  // 1. from HR, 2. the greeting with the job title
  sc.push({ s: 3.4, sfx: [[0.2, 'whoosh']], h: `<div class="wv-logos">${wvIn(wvCoLogo(), 0.1, 'pop')}${wvIn(wvLogo(), 0.25, 'pop')}</div>
      ${wvIn(`<span class="wv-k">${esc(W('رسالة ترحيب من ' + hr, 'A welcome message from ' + hr))}</span>`, 0.9)}${wvIn(`<p class="wv-p">${esc(co)}</p>`, 1.3)}` });
  sc.push({ s: 4.8, sfx: [[0.4, 'pop']], h: `${wvIn(`<h2 class="wv-h">${esc(name ? W('أهلًا ' + name, 'Welcome, ' + name) : W('أهلًا بك', 'Welcome'))}</h2>`, 0.15)}
      ${job ? wvIn(`<div class="wv-job">${esc(job)}</div>`, 0.7, 'pop') : ''}
      ${wvIn(`<p class="wv-p">${esc(W('يسعدنا انضمامك إلى فريق ', 'We are glad you joined the team at '))}<b class="wv-gold">${esc(co)}</b></p>`, 1.1)}${wvIn('<i class="wv-bar"></i>', 1.6, 'draw')}` });
  // 3. words from the manager
  const note = wvT(c.wel_note, c.wel_note_en);
  if (note) {
    const from = wvT(c.wel_from, c.wel_from_en), title = wvT(c.wel_title, c.wel_title_en);
    const pic = c.wel_photo && /^data:image\//.test(c.wel_photo) ? `<img class="wv-av wv-avl" src="${esc(c.wel_photo)}" alt="">` : from ? `<span class="wv-av wv-avl">${esc(wvInit(from))}</span>` : '';
    sc.push({ s: Math.min(10, 4.5 + note.length / 38), sfx: [[0.3, 'pop']], h: `${wvIn(`<h3 class="wv-h3">${esc(W('كلمة ترحيب', 'A word of welcome'))}</h3>`, 0.1)}
      ${wvIn(`<blockquote class="wv-quote">${esc(note)}</blockquote>`, 0.5)}
      ${from ? wvIn(`<div class="wv-by">${pic}<span><b>${esc(from)}</b>${title ? `<small>${esc(title)}</small>` : ''}</span></div>`, 1.2, 'side') : ''}` });
  }
  // 4. the company's identity
  const about = wvT(c.about, c.about_en), vision = wvT(c.vision, c.vision_en), vals = (c.core_values || []).map(v => wvT(v.ar, v.en)).filter(Boolean);
  if (about || vision || vals.length) sc.push({ s: 3 + (about ? 1.8 : 0) + (vision ? 1.8 : 0) + vals.length * 0.4, sfx: vals.map((_, i) => [1.6 + i * 0.25, 'pop']).slice(0, 4), h: `
      ${wvIn(`<h3 class="wv-h3">${esc(W('تعرّف على ' + co, 'Get to know ' + co))}</h3>`, 0.1)}
      ${about ? wvIn(`<p class="wv-p wv-about">${esc(about)}</p>`, 0.4) : ''}
      ${vision ? wvIn(`<p class="wv-vision"><span>${esc(W('رؤيتنا', 'Our vision'))}</span>${esc(vision)}</p>`, 0.9) : ''}
      ${vals.length ? `<div class="wv-chips">${vals.map((v, i) => wvIn(esc(v), 1.5 + i * 0.25, 'pop')).join('')}</div>` : ''}` });
  // 5. your team: department, manager, companion and a few colleagues
  const rows = all || [], buddy = e.buddy_id ? rows.find(r => r.id === e.buddy_id) : null;
  const nm = r => (LANG === 'en' && r.name_en) || r.name, jb = r => (LANG === 'en' && r.job_en) || r.job || '';
  const mgr = d.manager ? rows.find(r => r.name === d.manager) || { name: d.manager } : null;
  const mates = rows.filter(r => r.id !== e.id && !r.mine && (!buddy || r.id !== buddy.id) && (!mgr || r.name !== mgr.name) && d.department && r.department === d.department).slice(0, 3);
  const person = (r, tag, k) => `<li class="wv-in wv-side" style="--d:${(0.6 + k * 0.4).toFixed(2)}s"><span class="wv-av">${esc(wvInit(nm(r)))}</span><span><b>${esc(tr(nm(r)))}</b><small>${esc(jb(r) ? tr(jb(r)) : '')}</small></span>${tag ? `<em class="wv-tag">${esc(tag)}</em>` : ''}</li>`;
  const team = [...(mgr ? [[mgr, W('مديرك المباشر', 'Your manager')]] : []), ...(buddy ? [[buddy, W('زميلك المرافق', 'Your companion')]] : []), ...mates.map(r => [r, ''])];
  if (team.length || d.department) sc.push({ s: 2.6 + team.length * 0.8, sfx: team.map((_, i) => [0.6 + i * 0.4, 'click']), h: `
      ${wvIn(`<h3 class="wv-h3">${esc(W('فريقك', 'Your team'))}</h3>`, 0.1)}${d.department ? wvIn(`<p class="wv-p">${esc(W('قسم ', 'Department: ') + tr(d.department))}</p>`, 0.35) : ''}
      ${team.length ? `<ul class="wv-list wv-team">${team.map(([r, tag], k) => person(r, tag, k)).join('')}</ul>` : ''}
      ${buddy ? wvIn(`<p class="wv-note">${esc(W('زميلك المرافق يساعدك في أسابيعك الأولى، اسأله عن أي شيء.', 'Your companion helps you in your first weeks: ask them anything.'))}</p>`, 0.8 + team.length * 0.4) : ''}` });
  // 6. day one: date, time, place, who meets you
  const fd = e.first_day || {}, time = fd.time || (c.wel_time ? String(c.wel_time).slice(0, 5) : ''), place = fd.place || wvT(c.wel_place, c.wel_place_en);
  const meet = fd.meet || (mgr ? tr(nm(mgr)) : ''), upcoming = e.hire_date && e.hire_date >= today();
  const day = [['📅', W('تاريخ مباشرتك', 'Your start date'), e.hire_date ? fdate(e.hire_date) : ''], ['🕗', W('وقت الحضور', 'Arrival time'), time ? `⁦${time}⁩` : ''],
    ['📍', W('المكان', 'Place'), place], ['🤝', W('يستقبلك', 'Who meets you'), meet]].filter(x => x[2]);
  if (day.length) sc.push({ s: 2.4 + day.length * 0.8, sfx: day.map((_, i) => [0.5 + i * 0.45, 'click']), h: `${wvIn(`<h3 class="wv-h3">${esc(upcoming ? W('يومك الأول', 'Your first day') : W('بطاقتك في المنشأة', 'Your card at the company'))}</h3>`, 0.1)}${wvList(day, 0.5)}` });
  // 7. the first week
  const week = (c.wel_week && c.wel_week.length ? c.wel_week.map(x => [x.ar, x.en]) : WV_WEEK).map(([a, b]) => wvT(a, b)).slice(0, 5);
  sc.push({ s: 2.4 + week.length * 0.75, sfx: week.map((_, i) => [0.5 + i * 0.4, 'click']), h: `${wvIn(`<h3 class="wv-h3">${esc(W('أسبوعك الأول', 'Your first week'))}</h3>`, 0.1)}
      <ol class="wv-week">${week.map((x, i) => `<li class="wv-in wv-side" style="--d:${(0.5 + i * 0.4).toFixed(2)}s"><span class="wv-ic">${i + 1}</span><span>${esc(x)}</span></li>`).join('')}</ol>` });
  // 8. the guide for his department and job, 9. the end, signed by HR
  const topics = wvGuideTopics();
  if (topics.length) sc.push({ s: 2.4 + topics.length * 0.7, sfx: topics.map((_, i) => [0.5 + i * 0.45, 'click']), h: `${wvIn(`<h3 class="wv-h3">${esc(W('دليلك حسب قسمك ووظيفتك', 'Your guide for your department and job'))}</h3>`, 0.1)}
      ${wvList(topics.map(it => ['📘', hT(it.t), '']), 0.5)}` });
  sc.push({ s: 0, end: true, sfx: [[0.3, 'chime']], h: `${wvIn(wvCoLogo() || wvLogo(), 0.1, 'pop')}${wvIn(`<h3 class="wv-h3">${esc(W('نتمنى لك بداية موفقة', 'Wishing you a great start'))}</h3>`, 0.5)}
      ${wvIn(`<p class="wv-p wv-sign">${esc(W('مع تحيات ' + hr + ' · ' + co, 'With best wishes, ' + hr + ' · ' + co))}</p>`, 0.8)}
      ${wvIn(`<div class="wv-btns"><a class="btn pri" href="#/guide" data-wvgo>${esc(W('افتح دليلك', 'Open your guide'))}</a><button type="button" class="btn" data-wvre>${esc(W('أعد المشاهدة', 'Watch again'))}</button></div>`, 1.1)}` });
  return sc;
}

/* ---- the player: a full-screen stage with play/pause, sound, progress (jump to a scene) and close ---- */
async function welcomePlay(kind, opts = {}) {
  if ($('#wv')) return;
  WV = { e: opts.emp || (opts.company ? { full_name: tr('اسم الموظف') } : null), c: opts.company || null };
  if (kind === 'emp' && !WV.e && !S.myEmp) WV.e = { full_name: tr('اسم الموظف') };
  let me = null, all = [];
  if (kind === 'emp') { all = await db.rpc('staff_directory', { p_company: S.cid }).catch(() => []); const id = (WV.e || S.myEmp || {}).id; me = all.find(r => (id ? r.id === id : r.mine)) || null; }
  if (opts.keepOpen) opts.keepOpen.close();
  const scenes = kind === 'owner' ? wvOwnerScenes() : wvEmpScenes(me, all);
  const total = scenes.reduce((a, s) => a + s.s, 0), starts = scenes.map((_, i) => scenes.slice(0, i).reduce((a, s) => a + s.s, 0));
  const ov = document.createElement('div'); ov.id = 'wv'; ov.className = 'wv'; ov.setAttribute('role', 'dialog'); ov.setAttribute('aria-modal', 'true');
  ov.setAttribute('aria-label', W('رسالة الترحيب', 'Welcome message')); ov.setAttribute('data-nt', ''); ov.dir = LANG === 'en' ? 'ltr' : 'rtl';
  ov.innerHTML = `<div class="wv-stage"><div class="wv-dots">${'<i></i>'.repeat(14)}</div>
      ${scenes.map((s, i) => `<section class="wv-scene" data-i="${i}">${s.h}</section>`).join('')}
      <div class="wv-start"><div>${wvLogo()}</div><button type="button" class="wv-play" aria-label="${esc(W('تشغيل', 'Play'))}">▶</button>
        <p>${esc(kind === 'owner' ? W('رسالة ترحيب لك ولمنشأتك', 'A welcome for you and your company') : W('رسالة ترحيب لك', 'A welcome message for you'))} · <span class="num">${Math.round(total)}</span> ${esc(W('ثانية', 'seconds'))}</p></div>
      <div class="wv-ctl"><button type="button" class="wv-pp" aria-label="${esc(W('إيقاف مؤقت', 'Pause'))}">❚❚</button>
        <div class="wv-prog" role="progressbar" aria-valuemin="0" aria-valuemax="100">${scenes.filter(s => s.s).map((s, i) => `<button type="button" data-seek="${i}" style="flex:${s.s}" aria-label="${i + 1}"><i></i></button>`).join('')}</div>
        <button type="button" class="wv-mute" aria-label="${esc(W('الصوت', 'Sound'))}">🔊</button></div>
      <button type="button" class="wv-x" aria-label="${esc(W('إغلاق', 'Close'))}">×</button></div>`;
  document.body.appendChild(ov);
  const st = $('.wv-stage', ov), secs = $$('.wv-scene', ov), bars = $$('.wv-prog i', ov), pp = $('.wv-pp', ov);
  let t = 0, cur = -1, playing = false, muted = LS.get('waad.wv.mute') === 1, last = 0, raf = 0, fired = new Set();
  $('.wv-mute', ov).textContent = muted ? '🔇' : '🔊';
  const show = i => { if (i === cur) return; cur = i; secs.forEach((s, k) => { s.classList.toggle('on', k === i); if (k === i) { s.style.animation = 'none'; void s.offsetWidth; s.style.animation = ''; s.querySelectorAll('.wv-in').forEach(x => { x.style.animation = 'none'; void x.offsetWidth; x.style.animation = ''; }); } }); };
  const at = x => { let i = 0; starts.forEach((s, k) => { if (x >= s && scenes[k].s) i = k; }); return x >= total ? scenes.length - 1 : i; };
  const paint = () => { bars.forEach((b, k) => { const s = starts[k], d = scenes[k].s; b.style.width = Math.max(0, Math.min(1, (t - s) / d)) * 100 + '%'; }); $('.wv-prog', ov).setAttribute('aria-valuenow', Math.round(t / total * 100)); };
  const sound = () => { const i = cur, base = starts[i]; (scenes[i].sfx || []).forEach(([o, k], j) => { const key = i + ':' + j; if (!fired.has(key) && t >= base + o) { fired.add(key); wvSfx(k, muted); } }); };
  const tick = now => { if (!playing) return; t += Math.min(0.1, (now - last) / 1000); last = now; const i = at(t); show(i); sound(); paint();
    if (t >= total) { const endI = scenes.length - 1; show(endI); playing = false; st.classList.add('done'); pp.textContent = '↻'; pp.setAttribute('aria-label', W('أعد المشاهدة', 'Watch again')); return; }
    raf = requestAnimationFrame(tick); };
  const play = () => { if (st.classList.contains('done')) return restart(); playing = true; st.classList.remove('paused'); last = performance.now(); pp.textContent = '❚❚'; pp.setAttribute('aria-label', W('إيقاف مؤقت', 'Pause')); raf = requestAnimationFrame(tick); };
  const pause = () => { playing = false; cancelAnimationFrame(raf); st.classList.add('paused'); pp.textContent = '▶'; pp.setAttribute('aria-label', W('تشغيل', 'Play')); };
  const seek = i => { t = starts[i]; fired = new Set([...fired].filter(k => +k.split(':')[0] < i)); cur = -1; st.classList.remove('done'); show(i); paint(); if (!playing) play(); };
  const restart = () => { fired = new Set(); st.classList.remove('done'); seek(0); };
  const close = () => { pause(); if (st.classList.contains('done') && !opts.emp && !opts.company) LS.set(wvKey(kind), 1); ov.remove(); WV = {}; if (opts.keepOpen) opts.keepOpen.showModal(); document.removeEventListener('keydown', key); const card = $('#wvcard'); if (card && st.classList.contains('done')) card.remove(); };
  const key = e => { if (e.key === 'Escape') close(); else if (e.key === ' ' && !st.classList.contains('pre')) { e.preventDefault(); playing ? pause() : play(); } };
  document.addEventListener('keydown', key);
  st.classList.add('pre');
  $('.wv-play', ov).onclick = () => { st.classList.remove('pre'); wvSfx('click', muted); play(); };
  pp.onclick = () => (playing ? pause() : play());
  $('.wv-mute', ov).onclick = e => { muted = !muted; LS.set('waad.wv.mute', muted ? 1 : 0); e.currentTarget.textContent = muted ? '🔇' : '🔊'; };
  $$('[data-seek]', ov).forEach(b => b.onclick = () => seek(+b.dataset.seek));
  $('.wv-x', ov).onclick = close;
  ov.addEventListener('click', e => { if (e.target.closest('[data-wvre]')) restart(); else if (e.target.closest('[data-wvgo]')) close(); });
  $('.wv-play', ov).focus();
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) st.classList.add('calm');
}

/* who gets a welcome: the owner of a company in its first 30 days, and every new employee (any job) in his first 60 days
   after hire; the card shows on his first three sign-ins (browser sessions), and stops sooner once watched or closed */
function welcomeKind() {
  if (has('owner')) { const made = (S.company || {}).created_at; return made && Date.now() - new Date(made) < 30 * 864e5 ? 'owner' : null; }
  const h = S.myEmp && S.myEmp.hire_date; return S.emp && h && Date.now() - new Date(h) < 60 * 864e5 && Date.now() - new Date(h) > -30 * 864e5 ? 'emp' : null;
}
function wvVisits(kind) {
  const k = wvKey(kind) + '.n'; let n = +(LS.get(k) || 0), fresh = false;
  try { if (!sessionStorage.getItem(k)) { sessionStorage.setItem(k, '1'); fresh = true; } } catch (e) { fresh = false; }
  if (fresh) { n += 1; LS.set(k, n); }
  return n || 1;
}
// a small card on top of the home page
function welcomeCard(page) {
  const kind = welcomeKind(); if (!kind || !page || $('#wvcard', page) || LS.get(wvKey(kind)) || wvVisits(kind) > 3) return;
  const el = document.createElement('div'); el.className = 'card wvcard'; el.id = 'wvcard'; el.setAttribute('data-nt', '');
  el.innerHTML = `<button type="button" class="wvc-play" aria-label="${esc(W('شاهد رسالة الترحيب', 'Watch the welcome message'))}">▶</button>
    <div><b>${esc(kind === 'owner' ? W('رسالة ترحيب لك ولـ' + wvCo(), 'A welcome for you and ' + wvCo()) : W('رسالة ترحيب لك من الموارد البشرية في ' + wvCo(), 'A welcome message from HR at ' + wvCo()))}</b>
      <div class="muted small">${esc(kind === 'owner' ? W('أقل من نصف دقيقة، باسمك واسم منشأتك', 'Under half a minute, with your name and your company') : W('أقل من دقيقة: فريقك ويومك الأول وأسبوعك الأول', 'Under a minute: your team, your first day and first week'))}</div></div>
    <button type="button" class="x" aria-label="${esc(W('إغلاق', 'Close'))}">×</button>`;
  page.prepend(el);
  $('.wvc-play', el).onclick = () => welcomePlay(kind);
  $('.x', el).onclick = () => { LS.set(wvKey(kind), 1); el.remove(); };
}
// «رسالة الترحيب» on the user guide page, for anyone who wants to watch it again
const welcomeReplayKind = () => (has('owner') ? 'owner' : S.emp ? 'emp' : null);
