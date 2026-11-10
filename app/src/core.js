'use strict';
/* ===== config: the publishable key is meant to live in the browser; RLS protects the data ===== */
const CFG = Object.assign({ url: 'https://egfygyfmwqxshvwbevdd.supabase.co', key: 'sb_publishable_D7qaBJ4XKd2omtoK_-SZ6A_-wa0wn-r' }, window.WAAD_CONFIG || {});
const LS = { get(k) { try { return JSON.parse(localStorage.getItem(k)) } catch (e) { return null } },
             set(k, v) { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, JSON.stringify(v)) } catch (e) {} } };

/* ===== language: Arabic (default) or English. Screens are written in Arabic; in English mode a DOM
   observer swaps every Arabic text run for its entry in EN (i18n/en.tsv), longest phrase first. ===== */
let LANG = LS.get('waad.lang') === 'en' ? 'en' : 'ar';
const AR_L = '[ء-غـ-ْٰ-ۓ]';
const AR_RUN = new RegExp(AR_L + '+(?:[  ]+' + AR_L + '+)*', 'g');
const AR_PUNCT = { '،': ',', '؛': ';', '؟': '?', '«': '"', '»': '"' };
function trRun(run) {
  if (EN[run] != null) return EN[run];
  const w = run.split(/[  ]+/), out = [];
  for (let i = 0; i < w.length;) {
    let j = w.length, hit = null;
    for (; j > i; j--) { const k = w.slice(i, j).join(' '); if (EN[k] != null) { hit = EN[k]; break; } }
    if (hit != null) { out.push(hit); i = j; continue; }
    const x = w[i];
    if (x.length > 2 && x[0] === 'و' && EN[x.slice(1)] != null) { out.push('and ' + EN[x.slice(1)]); i++; continue; }
    return run;   // an unknown word means user data (a name, a memo): leave the whole run as typed
  }
  return out.join(' ');
}
function trTo(s) {
  s = String(s == null ? '' : s); if (!/[؀-ۿ«»]/.test(s)) return s;
  return s.replace(AR_RUN, trRun).replace(/[،؛؟«»]/g, c => AR_PUNCT[c]).replace(/Art\.(\d)/g, 'Art. $1')
    .replace(/[٠-٩]/g, d => d.charCodeAt(0) - 0x660);
}
const tr = s => LANG === 'en' ? trTo(s) : s;
const TR_ATTRS = ['placeholder', 'title', 'aria-label'];
function trWalk(n) {
  if (n.nodeType === 3) { const p = n.parentElement; if (p && !p.closest('[data-nt],textarea,script,style')) { const t = trTo(n.nodeValue); if (t !== n.nodeValue) n.nodeValue = t; } return; }
  if (n.nodeType !== 1 || n.closest('[data-nt],script,style')) return;
  for (const a of TR_ATTRS) if (n.hasAttribute(a)) { const v = n.getAttribute(a), t = trTo(v); if (t !== v) n.setAttribute(a, t); }
  if (n.tagName !== 'TEXTAREA') for (const c of [...n.childNodes]) trWalk(c);
}
let trObs = null;
function applyLang() {
  const h = document.documentElement; h.lang = LANG; h.dir = LANG === 'en' ? 'ltr' : 'rtl';
  document.title = ADMIN ? (LANG === 'en' ? 'Waad — admin' : 'وعد — لوحة الإدارة') : LANG === 'en' ? 'Waad — HR and finance' : 'وعد — الموارد البشرية والمالية';
  if (trObs) { trObs.disconnect(); trObs = null; }
  if (LANG !== 'en') return;
  trWalk(document.body);
  trObs = new MutationObserver(ms => { for (const m of ms) { if (m.type === 'childList') m.addedNodes.forEach(trWalk); else trWalk(m.target); } });
  trObs.observe(document.body, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: TR_ATTRS });
}
function setLang(l) { LANG = l === 'en' ? 'en' : 'ar'; LS.set('waad.lang', LANG); const d = document.getElementById('dlg'); if (d && d.open) d.close(); applyLang(); boot(); }
const langBtn = cls => `<button type="button" class="${cls}" id="lg" data-nt lang="${LANG === 'en' ? 'ar' : 'en'}" aria-label="${LANG === 'en' ? 'العربية' : 'English'}"><span class="bt">${LANG === 'en' ? 'العربية' : 'English'}</span><span class="bs">${LANG === 'en' ? 'ع' : 'EN'}</span></button>`;

/* ===== minimal Supabase client (Auth + PostgREST) — no external dependency ===== */
const S = { session: LS.get('waad.session'), cid: LS.get('waad.cid'), companies: [], role: null, emp: null, perms: new Set(), company: null, myEmp: null };
let refreshing = null;
function setSession(s) { S.session = s ? { access_token: s.access_token, refresh_token: s.refresh_token, expires_at: Date.now() + (s.expires_in || 3600) * 1000, user: s.user } : null; LS.set('waad.session', S.session); }
async function refreshSession() {
  if (!S.session) throw new Error('no session');
  if (!refreshing) refreshing = (async () => {
    const r = await fetch(CFG.url + '/auth/v1/token?grant_type=refresh_token', { method: 'POST', headers: { apikey: CFG.key, 'Content-Type': 'application/json' }, body: JSON.stringify({ refresh_token: S.session.refresh_token }) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) { setSession(null); throw new ApiError(authMsg(j), 401); }
    setSession(j);
  })().finally(() => { refreshing = null; });
  return refreshing;
}
class ApiError extends Error { constructor(m, status, code) { super(m); this.status = status; this.code = code; } }
const EN_AR = [
  [/permission denied|row-level security|42501/i, 'ليست لديك صلاحية لهذا الإجراء'],
  [/duplicate key.*(emp_no)/i, 'الرقم الوظيفي مستخدم مسبقاً'],
  [/duplicate key.*(code)/i, 'الرمز مستخدم مسبقاً'],
  [/duplicate key|23505/i, 'السجل موجود مسبقاً'],
  [/national_id_check|national_id/i, 'رقم الهوية/الإقامة 10 أرقام يبدأ بـ 1 أو 2'],
  [/iban_check/i, 'الآيبان يبدأ بـ SA ويليه 22 رقماً'],
  [/vat_no_check/i, 'الرقم الضريبي 15 رقماً يبدأ وينتهي بـ 3'],
  [/cr_no_check/i, 'السجل التجاري 10 أرقام'],
  [/phone_check/i, 'رقم الجوال بصيغة 05XXXXXXXX'],
  [/full_name_check|name_check/i, 'الاسم 3 أحرف على الأقل'],
  [/violates check constraint/i, 'قيمة غير صالحة في أحد الحقول'],
  [/violates foreign key/i, 'لا يمكن الحذف لارتباطه بسجلات أخرى'],
  [/invalid input syntax for type (numeric|integer)/i, 'أدخل رقماً صحيحاً'],
  [/invalid input syntax for type date/i, 'أدخل تاريخاً صحيحاً'],
  [/Invalid login credentials/i, 'البريد أو كلمة المرور غير صحيحة'],
  [/Email not confirmed/i, 'لم يُؤكَّد البريد بعد — افتح رابط التأكيد في بريدك'],
  [/User already registered/i, 'هذا البريد مسجّل مسبقاً — سجّل الدخول'],
  [/Password should be at least/i, 'كلمة المرور 8 أحرف على الأقل'],
  [/confirmation (mail|email)|sending.*email/i, 'أطفئ خيار «Confirm email» في إعدادات Supabase ثم أعد المحاولة'],
  [/rate limit|too many/i, 'محاولات كثيرة — انتظر قليلاً ثم أعد المحاولة'],
  [/Failed to fetch|NetworkError|Load failed/i, 'تعذّر الاتصال بالخادم — تحقق من الإنترنت'],
];
function arMsg(m) { m = String(m || ''); if (/[؀-ۿ]/.test(m)) return m; for (const [re, ar] of EN_AR) if (re.test(m)) return ar; return m || 'حدث خطأ غير متوقع'; }
function authMsg(j) { return arMsg(j.msg || j.error_description || j.message || j.error || ''); }
async function api(path, { method = 'GET', body, headers = {}, retry = true } = {}) {
  if (S.session && Date.now() > S.session.expires_at - 60000) { try { await refreshSession(); } catch (e) {} }
  const h = Object.assign({ apikey: CFG.key, 'Content-Type': 'application/json' }, headers);
  if (S.session) h.Authorization = 'Bearer ' + S.session.access_token;
  let r;
  try { r = await fetch(CFG.url + path, { method, headers: h, body: body === undefined ? undefined : JSON.stringify(body) }); }
  catch (e) { throw new ApiError(arMsg(e.message), 0); }
  if (r.status === 401 && retry && S.session) {
    const t = await r.clone().text();
    if (/jwt|expired|token/i.test(t)) { await refreshSession(); return api(path, { method, body, headers, retry: false }); }
  }
  const txt = await r.text(); let j = null; try { j = txt ? JSON.parse(txt) : null; } catch (e) { j = txt; }
  if (!r.ok) throw new ApiError(arMsg((j && (j.message || j.msg || j.error_description)) || r.statusText), r.status, j && j.code);
  return j;
}
const qs = o => Object.entries(o).filter(([, v]) => v !== undefined && v !== null).map(([k, v]) => encodeURIComponent(k) + '=' + encodeURIComponent(v)).join('&');
/* bilingual data: English names stored next to the Arabic ones are taught to the translator, so in English mode every
   place that shows an Arabic name (tables, selects, letters, printouts) shows the English one — no per-screen code */
const BILINGUAL = { employees: [['full_name', 'full_name_en'], ['job_title', 'job_title_en']], departments: [['name', 'name_en']], companies: [['name', 'name_en']],
  accounts: [['name', 'name_en']], parties: [['name', 'name_en']], items: [['name', 'name_en']], work_sites: [['name', 'name_en']], shifts: [['name', 'name_en']], holidays: [['name', 'name_en']],
  review_cycles: [['name', 'name_en']], job_openings: [['title', 'title_en']], candidates: [['full_name', 'full_name_en']], trainings: [['title', 'title_en']], employee_documents: [['title', 'title_en']], employee_allowances: [['name', 'name_en']], policies: [['title', 'title_en']], custody_items: [['name', 'name_en']] };
// in English mode, learn every stored English name up front so lists and reports built from functions show them too
async function preloadNames() {
  if (LANG !== 'en' || !S.cid) return;
  await Promise.all(Object.entries(BILINGUAL).filter(([t]) => t !== 'companies').map(([t, pairs]) =>
    db.get(t, { company_id: 'eq.' + S.cid, select: pairs.flat().join(',') }).catch(() => [])));
}
const enF = (name, v, label = 'الاسم بالإنجليزية', cls = '') => field(label, inp(name, v, 'dir="ltr"'), cls);
function learnNames(rows, pairs) {
  (Array.isArray(rows) ? rows : [rows]).forEach(r => r && pairs.forEach(([a, b]) => { const k = String(r[a] || '').trim().replace(/\s+/g, ' '); if (k && r[b] && String(r[b]).trim()) EN[k] = String(r[b]).trim(); }));
}
const db = {
  get: (t, q = {}) => api('/rest/v1/' + t + '?' + qs(Object.assign({ select: '*' }, q))).then(r => { if (BILINGUAL[t]) learnNames(r, BILINGUAL[t]); return r; }),
  ins: (t, rows) => api('/rest/v1/' + t, { method: 'POST', body: rows, headers: { Prefer: 'return=representation' } }),
  upd: (t, q, patch) => api('/rest/v1/' + t + '?' + qs(q), { method: 'PATCH', body: patch, headers: { Prefer: 'return=representation' } }),
  del: (t, q) => api('/rest/v1/' + t + '?' + qs(q), { method: 'DELETE', headers: { Prefer: 'return=representation' } }),
  rpc: (fn, args = {}) => api('/rest/v1/rpc/' + fn, { method: 'POST', body: args }),
};
const authApi = {
  async signIn(email, password) { const r = await fetch(CFG.url + '/auth/v1/token?grant_type=password', { method: 'POST', headers: { apikey: CFG.key, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) }).catch(e => { throw new ApiError(arMsg(e.message), 0); }); const j = await r.json().catch(() => ({})); if (!r.ok) throw new ApiError(authMsg(j), r.status); setSession(j); },
  async signUp(email, password) { const r = await fetch(CFG.url + '/auth/v1/signup', { method: 'POST', headers: { apikey: CFG.key, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) }).catch(e => { throw new ApiError(arMsg(e.message), 0); }); const j = await r.json().catch(() => ({})); if (!r.ok) throw new ApiError(authMsg(j), r.status); if (j.access_token) { setSession(j); return true; } return false; },
  async recover(email) { const r = await fetch(CFG.url + '/auth/v1/recover?redirect_to=' + encodeURIComponent(location.origin + location.pathname), { method: 'POST', headers: { apikey: CFG.key, 'Content-Type': 'application/json' }, body: JSON.stringify({ email }) }); if (!r.ok) { const j = await r.json().catch(() => ({})); throw new ApiError(authMsg(j), r.status); } },
  async setPassword(password) { await api('/auth/v1/user', { method: 'PUT', body: { password } }); },
  // HR creates a staff account without touching its own session
  async createStaff(email, password) { const r = await fetch(CFG.url + '/auth/v1/signup', { method: 'POST', headers: { apikey: CFG.key, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) }).catch(e => { throw new ApiError(arMsg(e.message), 0); }); const j = await r.json().catch(() => ({})); if (!r.ok && !/already registered|already exists/i.test(j.msg || j.message || '')) throw new ApiError(authMsg(j), r.status); return { confirmed: !!j.access_token, existed: !r.ok }; },
  async signOut() { try { await api('/auth/v1/logout', { method: 'POST', retry: false }); } catch (e) {} setSession(null); LS.set('waad.cid', null); S.cid = null; },
};

/* ===== helpers ===== */
const $ = (s, r = document) => r.querySelector(s), $$ = (s, r = document) => [...r.querySelectorAll(s)];
const esc = v => String(v == null ? '' : v).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = v => (v == null || v === '' ? '—' : Number(v).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }));
const n0 = v => Number(v || 0);
const r2 = v => Math.round((n0(v) + Number.EPSILON) * 100) / 100;
const today = () => { const d = new Date(); return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10); };
const firstOfMonth = () => today().slice(0, 8) + '01';
const fdate = d => d ? String(d).slice(0, 10) : '—';
const ROLES = { owner: 'المالك / المدير العام', admin: 'مدير النظام', hr: 'الموارد البشرية', finance: 'المدير المالي', accountant: 'محاسب', storekeeper: 'أمين مستودع', manager: 'مدير قسم', employee: 'موظف' };
const STEP = { m: 'المدير المباشر', p: 'الموارد البشرية', h: 'مدير الموارد البشرية', f: 'المالية', g: 'المدير العام' };
const KIND = { leave: 'إجازة', permit: 'استئذان', cert: 'تعريف بالراتب', advance: 'سلفة', resign: 'استقالة', settle: 'مخالصة', expense: 'مطالبة مصروفات', update: 'تحديث بيانات', punch: 'نسيان بصمة', ticket: 'تذكرة سفر', visa: 'تأشيرة خروج وعودة', purchase: 'طلب شراء' };
const STATUS = { pending: ['بانتظار', 'wait'], approved: ['معتمد', 'ok'], rejected: ['مرفوض', 'bad'], cancelled: ['ملغى', ''], draft: ['مسودة', 'wait'], paid: ['مصروف', 'ok'], posted: ['مرحّلة', 'ok'], void: ['ملغاة', 'bad'] };
const badge = s => { const [t, c] = STATUS[s] || [s, '']; return `<span class="badge ${c}">${esc(t)}</span>`; };
const has = (...roles) => roles.some(r => (S.roles || new Set([S.role])).has(r));
const FIN_ALL = ['owner', 'admin', 'finance'];
const can = p => has(...FIN_ALL) || (has('accountant', 'storekeeper') && S.perms.has(p));
const isFin = () => has(...FIN_ALL, 'accountant', 'storekeeper');
const isHR = () => has('owner', 'admin', 'hr');

function toast(m) { const t = $('#toast'); t.textContent = m; t.hidden = false; clearTimeout(toast.t); toast.t = setTimeout(() => t.hidden = true, 3200); }
function showErr(where, e) { const box = typeof where === 'string' ? $(where) : where; const m = e && e.message ? e.message : String(e); if (box) { box.innerHTML = `<div class="err" role="alert">${esc(m)}</div>`; } else toast(m); }
function formData(f) { const o = {}; for (const el of f.elements) { if (!el.name) continue; if (el.type === 'checkbox') o[el.name] = el.checked; else o[el.name] = el.value.trim(); } return o; }
const blank = v => v === '' || v == null ? null : v;
const snSplit = v => [...new Set(String(v || '').split(/[\n,;،]+/).map(x => x.trim()).filter(Boolean))];
async function busy(btn, fn) { if (btn) { btn.disabled = true; } try { return await fn(); } finally { if (btn) btn.disabled = false; } }
function tbl(cols, rows, { empty = 'لا توجد بيانات', onRow, foot } = {}) {
  if (!rows || !rows.length) return `<div class="tw"><div class="empty">${esc(empty)}</div></div>`;
  return `<div class="tw"><table><thead><tr>${cols.map(c => `<th class="${c.r ? 'r' : ''}">${esc(c.t)}</th>`).join('')}</tr></thead><tbody>${rows.map((r, i) => `<tr${onRow ? ` class="click" data-row="${i}"` : ''}>${cols.map(c => `<td class="${c.r ? 'r num' : ''}">${c.h ? c.h(r) : esc(r[c.k])}</td>`).join('')}</tr>`).join('')}</tbody>${foot ? `<tfoot><tr>${foot}</tr></tfoot>` : ''}</table></div>`;
}
function bindRows(root, rows, fn) { $$('tr[data-row]', root).forEach(tr => tr.onclick = () => fn(rows[+tr.dataset.row])); }
const opt = (v, t, sel) => `<option value="${esc(v)}"${String(sel) === String(v) ? ' selected' : ''}>${esc(t)}</option>`;
const field = (label, input, cls = '') => `<div class="${cls}"><label>${esc(label)}</label>${input}</div>`;
const inp = (name, v = '', extra = '') => `<input name="${name}" value="${esc(v == null ? '' : v)}" ${extra}>`;
// password field with a show/hide eye toggle (used on login and wherever a password is typed)
const pwInput = (name, ac = 'current-password', extra = 'required') => `<div class="pwrap"><input name="${name}" type="password" autocomplete="${ac}" dir="ltr" ${extra}><button type="button" class="peye" tabindex="-1" aria-label="إظهار كلمة المرور" title="إظهار كلمة المرور"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7S1 12 1 12z"/><circle cx="12" cy="12" r="3"/><line class="pe-slash" x1="4" y1="20" x2="20" y2="4"/></svg></button></div>`;
document.addEventListener('click', e => { const b = e.target.closest && e.target.closest('.peye'); if (!b) return; const i = b.parentNode.querySelector('input'); if (!i) return; const show = i.type === 'password'; i.type = show ? 'text' : 'password'; b.classList.toggle('on', show); const lbl = show ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور'; b.setAttribute('aria-label', lbl); b.title = lbl; });

/* modal */
function modal(title, body, { ok = 'حفظ', onOk, wide } = {}) {
  const d = $('#dlg');
  d.style.width = wide ? 'min(960px,calc(100vw - 32px))' : '';
  d.innerHTML = `<form method="dialog" id="mform" novalidate><div class="dh"><b>${esc(title)}</b><button type="button" class="x" aria-label="إغلاق" id="mx">×</button></div><div class="db">${body}<div id="merr"></div></div>${onOk ? `<div class="df"><button type="button" class="btn" id="mc">إلغاء</button><button class="btn pri" id="mok">${esc(ok)}</button></div>` : ''}</form>`;
  const close = () => d.close();
  $('#mx', d).onclick = close; if ($('#mc', d)) $('#mc', d).onclick = close;
  $('#mform', d).onsubmit = async ev => { ev.preventDefault(); if (!onOk) return close(); const b = $('#mok', d); try { await busy(b, () => onOk(formData($('#mform', d)), d)); close(); } catch (e) { showErr($('#merr', d), e); } };
  d.showModal(); const first = $('input,select,textarea', d); if (first) first.focus();
  return d;
}
const confirmBox = (title, msg, okText = 'تأكيد') => new Promise(res => { modal(title, `<p>${esc(msg)}</p>`, { ok: okText, onOk: async () => res(true) }); $('#dlg').addEventListener('close', () => res(false), { once: true }); });

/* ===== printing: every printout carries the company letterhead (logo, name, CR, VAT) ===== */
function printHead(title) {
  const c = S.company || {}, ids = [c.cr_no && 'السجل التجاري ' + c.cr_no, c.vat_no && 'الرقم الضريبي ' + c.vat_no].filter(Boolean).join(' · ');
  return `<div class="ph"><div class="ph-brand">${c.logo ? `<img class="ph-logo" src="${esc(c.logo)}" alt="">` : ''}<div><div class="ph-co">${esc(c.name || '')}</div>${ids ? `<div class="ph-ids">${esc(ids)}</div>` : ''}${c.address ? `<div class="ph-ids">${esc(c.address)}</div>` : ''}</div></div>
    <div class="ph-meta">${title ? `<div class="ph-t">${esc(title)}</div>` : ''}<div>تاريخ الطباعة: <span class="num">${esc(today())}</span></div></div></div>`;
}
// print only `node` (one prepared sheet, or a copy of part of the page): everything else is hidden for this job
function printWith(node, pageCss) {
  let pa = document.getElementById('printarea'); if (!pa) { pa = document.createElement('div'); pa.id = 'printarea'; document.body.appendChild(pa); }
  pa.replaceChildren(node);
  const st = document.createElement('style'); st.textContent = pageCss; document.head.appendChild(st);
  document.body.classList.add('printing');
  const done = () => { document.body.classList.remove('printing'); st.remove(); pa.replaceChildren(); window.removeEventListener('afterprint', done); };
  window.addEventListener('afterprint', done);
  window.print();
}
function printBlock(node, title) {
  const doc = document.createElement('div'); doc.className = 'pdoc'; doc.innerHTML = printHead(title);
  const cp = node.cloneNode(true); cp.removeAttribute('id'); cp.querySelectorAll('.btn,button,input[type=file],.wa').forEach(x => x.remove()); doc.appendChild(cp);
  printWith(doc, '@page{size:A4 portrait;margin:12mm}');
}
// the browser's own print (Ctrl+P) on any page gets the same letterhead
window.addEventListener('beforeprint', () => {
  if (document.body.classList.contains('printing')) return;
  let h = document.getElementById('printhead'); if (!h) { h = document.createElement('div'); h.id = 'printhead'; document.body.prepend(h); }
  const t = document.querySelector('#page h1'); h.innerHTML = S.company && S.session ? printHead(t ? t.textContent.trim() : '') : '';
});

/* ===== theme ===== */
// three modes: follow the device (default), always light, always dark
const THEMES = { auto: ['المظهر: حسب الجهاز', '◐'], light: ['المظهر: نهاري', '☀'], dark: ['المظهر: ليلي', '☾'] };
// the system is dark by default; the admin site keeps its own setting and is light by default
const THEME_KEY = typeof ADMIN_SITE !== 'undefined' ? 'waad.atheme' : 'waad.theme', THEME_DEF = typeof ADMIN_SITE !== 'undefined' ? 'light' : 'dark';
const curTheme = () => { const t = LS.get(THEME_KEY); return THEMES[t] ? t : THEME_DEF; };
function applyTheme(t) { if (t === 'light' || t === 'dark') document.documentElement.dataset.theme = t; else delete document.documentElement.dataset.theme;
  for (const b of document.querySelectorAll('[data-theme-btn]')) { const [label, icon] = THEMES[curTheme()]; b.title = label; b.setAttribute('aria-label', label); if (b.dataset.themeBtn === 'menu') b.innerHTML = `<span class="ic">${icon}</span><span>${esc(label)}</span>`; else b.textContent = b.dataset.themeBtn === 'icon' ? icon : icon + ' ' + label; } }
applyTheme(curTheme());
function toggleTheme() { const order = THEME_DEF === 'light' ? ['light', 'dark', 'auto'] : ['dark', 'light', 'auto'], t = order[(order.indexOf(curTheme()) + 1) % 3]; LS.set(THEME_KEY, t === THEME_DEF ? null : t); applyTheme(t); toast(THEMES[t][0]); }

/* ===== auth screens ===== */
const LOGO_D = 'data:image/webp;base64,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', LOGO_L = 'data:image/webp;base64,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';   // the official Waad logo (dark and light backgrounds)
const brand = () => `<div class="brand"><img class="wlogo wl-d" src="${LOGO_D}" alt="وعد Waad"><img class="wlogo wl-l" src="${LOGO_L}" alt="وعد Waad"></div>`;
// company code can arrive in the link HR shares: …/waad/?c=1FB695
(() => { try { const c = new URLSearchParams(location.search).get('c'); if (c && /^[A-Za-z0-9]{4,10}$/.test(c) && c.toUpperCase() !== LS.get('waad.ccode')) { LS.set('waad.ccode', c.toUpperCase()); LS.set('waad.cname', null); } } catch (e) {} })();
const adminEmail = user => String(user).trim().toLowerCase() + '@admin.waad.app';   // Waad team accounts (admin site)
const staffEmail = (code, empNo) => String(empNo).trim().toLowerCase() + '.' + String(code).trim().toLowerCase() + '@staff.waad.app';
// the public website (landing page) sits one folder up from the app: site/app/ -> site/, pages.dev/app/ -> pages.dev/
const SITE_URL = new URL('../', location.href.split('#')[0]).href;
// the admin site (site/admin/) is a separate build of the same code (build.py sets ADMIN_SITE): Waad's own team only
const ADMIN = typeof ADMIN_SITE !== 'undefined';
const DEV_FILE = /waad-(app|admin)\.html$/.test(location.pathname);   // the dev server serves the two builds side by side
const ADMIN_URL = DEV_FILE ? 'waad-admin.html' : new URL('../admin/', location.href.split('#')[0]).href;
const APP_URL = DEV_FILE ? 'waad-app.html' : new URL('../app/', location.href.split('#')[0]).href;
function authView(tab = LS.get('waad.authtab') || 'staff', msg = '') {
  if (ADMIN) return adminAuthView(msg);   // the admin site signs in with a username (platform.js)
  const app = $('#app'); const ccode = LS.get('waad.ccode') || '', cname = LS.get('waad.cname') || '';
  if (tab === 'staff' && ccode && !cname) {   // code from a link: resolve the company name first
    db.rpc('company_by_code', { p_code: ccode }).then(n => { if (n) { LS.set('waad.cname', n); } else { LS.set('waad.ccode', null); } authView('staff', msg); }).catch(() => { LS.set('waad.ccode', null); authView('staff', msg); });
    app.innerHTML = '<div class="auth"><div class="muted">جارٍ التحميل…</div></div>'; return;
  }
  const step = tab === 'staff' ? (ccode ? 'login' : 'code') : tab;
  let body = '', btn = 'دخول', foot = '';
  if (step === 'code') {
    body = `<h2 style="margin-bottom:4px">رمز المنشأة</h2><p class="muted small" style="margin-top:0">أدخل رمز منشأتك مرة واحدة — تعطيك إياه الموارد البشرية — وسيتذكره النظام.</p>
      ${field('رمز المنشأة', `<input name="code" required dir="ltr" autocapitalize="characters" autocomplete="organization" style="text-transform:uppercase;letter-spacing:3px;font-size:18px;text-align:center" placeholder="1FB695">`)}`;
    btn = 'متابعة';
  } else if (step === 'login') {
    body = `<div class="note" style="display:flex;justify-content:space-between;align-items:center;gap:8px"><span>المنشأة: <b>${esc(cname)}</b></span><a href="#" id="chg" class="small">تغيير</a></div>
      ${field('الرقم الوظيفي', `<input name="emp" required dir="ltr" inputmode="numeric" autocomplete="username">`)}<div style="height:10px"></div>
      ${field('كلمة المرور', pwInput('password', 'current-password'))}`;
    foot = `<p class="muted small" style="margin:10px 0 0;text-align:center">أول دخول؟ استخدم كلمة المرور التي أعطتك إياها الموارد البشرية، وسيُطلب منك تغييرها. نسيتها؟ اطلب من الموارد البشرية إعادة تعيينها.</p>`;
  } else {
    body = `${field('البريد الإلكتروني', `<input name="email" type="email" autocomplete="email" required dir="ltr">`)}<div style="height:10px"></div>
      ${field('كلمة المرور', pwInput('password', tab === 'in' ? 'current-password' : 'new-password'))}
      ${tab === 'up' ? `<div style="height:10px"></div>${field('تأكيد كلمة المرور', pwInput('password2', 'new-password', ''))}
        <label class="row small" style="gap:6px;margin-top:10px;align-items:flex-start"><input type="checkbox" name="agree" style="width:auto;margin-top:3px"> <span>أوافق على <a href="#/terms">شروط الاستخدام</a> و<a href="#/privacy">سياسة الخصوصية</a></span></label>` : ''}`;
    btn = tab === 'up' ? 'إنشاء الحساب' : 'دخول';
    foot = tab === 'in' ? `<div style="margin-top:10px;text-align:center"><a href="#" id="forgot" class="small">نسيت كلمة المرور؟</a></div>`
      : `<p class="muted small" style="margin:10px 0 0">لصاحب منشأة جديدة، أو لمن وصلته دعوة بالبريد من الإدارة. الموظفون لا يسجلون هنا — يدخلون برمز المنشأة ورقمهم الوظيفي.</p>`;
  }
  const links = tab === 'staff' ? `<a href="#" data-go="in">دخول الإدارة بالبريد</a> · <a href="#" data-go="up">حساب جديد بالبريد</a>` : `<a href="#" data-go="staff">دخول الموظفين</a> · ${tab === 'in' ? '<a href="#" data-go="up">حساب جديد بالبريد</a>' : '<a href="#" data-go="in">لديك حساب؟ دخول بالبريد</a>'}`;
  app.innerHTML = `<div class="auth"><div class="abox">${brand()}<div class="card">
    ${tab !== 'staff' ? `<h2>${tab === 'in' ? 'دخول الإدارة بالبريد' : 'حساب جديد بالبريد'}</h2>` : ''}
    ${msg ? `<div class="note">${esc(msg)}</div>` : ''}
    <form id="af" novalidate>${body}<div id="aerr"></div><div style="height:12px"></div><button class="btn pri full" id="ab">${btn}</button>${foot}</form></div>
    <p class="muted small" style="text-align:center">${links}</p>
    <p class="muted small" style="text-align:center"><a href="#" id="theme" data-theme-btn="text"></a> · ${langBtn('linkbtn')}</p>
    <p class="muted small afoot"><a href="${SITE_URL}" id="tosite">← الموقع الرئيسي</a> · نظام وعد السحابي لإدارة المنشآت © ${new Date().getFullYear()} · <a href="#/privacy">سياسة الخصوصية</a> · <a href="#/terms">شروط الاستخدام</a></p></div></div>`;
  $('#lg').onclick = () => setLang(LANG === 'en' ? 'ar' : 'en');
  $$('[data-go]', app).forEach(a => a.onclick = e => { e.preventDefault(); authView(a.dataset.go); });
  $('#theme').onclick = e => { e.preventDefault(); toggleTheme(); }; applyTheme(curTheme());
  if ($('#chg')) $('#chg').onclick = e => { e.preventDefault(); LS.set('waad.ccode', null); LS.set('waad.cname', null); authView('staff'); };
  if ($('#forgot')) $('#forgot').onclick = async e => { e.preventDefault(); const em = $('#af').email.value.trim(); if (!em) return showErr('#aerr', 'اكتب بريدك أولاً'); try { await authApi.recover(em); authView('in', 'أرسلنا رابط إعادة تعيين كلمة المرور إلى بريدك (إن كان مسجلاً).'); } catch (er) { showErr('#aerr', er); } };
  $('#af').onsubmit = async e => {
    e.preventDefault(); const f = formData(e.target);
    if (step === 'code') {
      const c = f.code.replace(/\s/g, '').toUpperCase();
      if (!/^[A-Z0-9]{4,10}$/.test(c)) return showErr('#aerr', 'أدخل رمز المنشأة كما وصلك');
      try { await busy($('#ab'), async () => { const n = await db.rpc('company_by_code', { p_code: c }); if (!n) throw new Error('رمز المنشأة غير صحيح — تأكد منه مع الموارد البشرية'); LS.set('waad.ccode', c); LS.set('waad.cname', n); authView('staff'); }); } catch (er) { showErr('#aerr', er); }
      return;
    }
    if (step === 'login') {
      if (!/^[A-Za-z0-9_-]{1,20}$/.test(f.emp)) return showErr('#aerr', 'أدخل الرقم الوظيفي (أرقام إنجليزية)');
      if (!f.password) return showErr('#aerr', 'أدخل كلمة المرور');
      try { await busy($('#ab'), async () => { await authApi.signIn(staffEmail(ccode, f.emp), f.password); LS.set('waad.authtab', 'staff'); return boot(); }); }
      catch (er) { showErr('#aerr', /غير صحيحة/.test(er.message) ? 'الرقم الوظيفي أو كلمة المرور غير صحيحة' : er); }
      return;
    }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(f.email)) return showErr('#aerr', 'البريد الإلكتروني غير صحيح');
    if (tab === 'up' && f.password.length < 8) return showErr('#aerr', 'كلمة المرور 8 أحرف على الأقل');
    if (tab === 'up' && f.password !== f.password2) return showErr('#aerr', 'كلمتا المرور غير متطابقتين');
    if (tab === 'up' && !f.agree) return showErr('#aerr', 'وافق على شروط الاستخدام وسياسة الخصوصية لإنشاء الحساب');
    if (tab === 'up') { LS.set('waad.terms', TERMS_VERSION); LS.set('waad.authtab', 'in'); }
    try {
      await busy($('#ab'), async () => {
        if (tab === 'in') { await authApi.signIn(f.email, f.password); LS.set('waad.authtab', 'in'); return boot(); }
        const signedIn = await authApi.signUp(f.email, f.password);
        if (signedIn) return boot();
        authView('in', 'أنشأنا حسابك. افتح رسالة التأكيد في بريدك ثم سجّل الدخول.');
      });
    } catch (er) { showErr('#aerr', er); }
  };
}

/* first login with a temporary password → choose a personal one */
function changePasswordView(forced = true) {
  $('#app').innerHTML = `<div class="auth"><div class="abox">${brand()}<div class="card"><h2>${forced ? 'اختر كلمة مرور جديدة' : 'تغيير كلمة المرور'}</h2>
    ${forced === 'recovery' ? '<p class="muted small">فتحت رابط استعادة كلمة المرور. اختر كلمة مرور جديدة لحسابك.</p>' : ADMIN && forced ? '<p class="muted small">دخلت بكلمة مرور مؤقتة. اختر كلمة مرور خاصة بك لا يعرفها غيرك.</p>' : forced ? '<p class="muted small">دخلت بكلمة مرور مؤقتة من الموارد البشرية. اختر كلمة مرور خاصة بك لا يعرفها غيرك.</p>' : ''}
    <form id="pf" novalidate>${field('كلمة المرور الجديدة (8 أحرف أو أكثر)', pwInput('p1', 'new-password', ''))}<div style="height:10px"></div>
    ${field('تأكيدها', pwInput('p2', 'new-password', ''))}<div id="perr"></div><div style="height:12px"></div>
    <button class="btn pri full" id="pb">حفظ والمتابعة</button></form>
    <p class="muted small" style="text-align:center;margin-top:10px">${forced ? '' : '<a href="#" id="bk">رجوع</a> · '}<a href="#" id="lo">تسجيل الخروج</a></p></div></div></div>`;
  if ($('#bk')) $('#bk').onclick = e => { e.preventDefault(); if (ADMIN) return platformView(); shell(); route(); };
  $('#lo').onclick = async e => { e.preventDefault(); await authApi.signOut(); authView(); };
  $('#pf').onsubmit = async e => { e.preventDefault(); const f = formData(e.target);
    if (f.p1.length < 8) return showErr('#perr', 'كلمة المرور 8 أحرف على الأقل');
    if (f.p1 !== f.p2) return showErr('#perr', 'كلمتا المرور غير متطابقتين');
    try { await busy($('#pb'), async () => { await authApi.setPassword(f.p1); await db.rpc('password_changed'); toast('حُفظت كلمة المرور'); await boot(); }); } catch (er) { showErr('#perr', er); } };
}

/* ===== onboarding: create a company or join with an invite code ===== */
function onboardView() {
  $('#app').innerHTML = `<div class="auth"><div class="abox" style="max-width:520px">${brand()}
    <div class="card"><h2>انضم إلى منشأتك</h2><p class="muted small">إذا أرسلت لك الموارد البشرية رمز دعوة، أدخله هنا.</p>
      <form id="jf" class="row" novalidate><input name="code" placeholder="رمز الدعوة" dir="ltr" style="flex:1;letter-spacing:2px;text-transform:uppercase"><button class="btn pri" id="jb">انضمام</button></form><div id="jerr"></div></div>
    <div class="card"><h2>أو أنشئ منشأة جديدة</h2>
      <form id="cf" class="fg" novalidate>
        ${field('اسم المنشأة', inp('name', '', 'required'), 'wide')}
        ${field('الرقم الضريبي (اختياري)', inp('vat', '', 'dir="ltr" inputmode="numeric" placeholder="3XXXXXXXXXXXXX3"'))}
        ${field('السجل التجاري (اختياري)', inp('cr', '', 'dir="ltr" inputmode="numeric"'))}
        <div class="wide"><div id="cerr"></div><button class="btn pri" id="cb">إنشاء المنشأة</button></div>
      </form><p class="muted small">ستكون مالك المنشأة، ويُنشأ دليل الحسابات تلقائياً.</p></div>
    <p class="muted small" style="text-align:center">${esc(S.session.user.email)} · <a href="#" id="lo">تسجيل الخروج</a></p></div></div>`;
  $('#lo').onclick = async e => { e.preventDefault(); await authApi.signOut(); authView(); };
  $('#jf').onsubmit = async e => { e.preventDefault(); const code = e.target.code.value.trim(); if (!code) return showErr('#jerr', 'أدخل الرمز');
    try { await busy($('#jb'), async () => { const cid = await db.rpc('accept_invite', { p_code: code }); S.cid = cid; LS.set('waad.cid', cid); await boot(); toast('تم الانضمام'); }); } catch (er) { showErr('#jerr', er); } };
  $('#cf').onsubmit = async e => { e.preventDefault(); const f = formData(e.target);
    if (f.name.length < 3) return showErr('#cerr', 'اسم المنشأة 3 أحرف على الأقل');
    if (f.vat && !/^3\d{13}3$/.test(f.vat)) return showErr('#cerr', 'الرقم الضريبي 15 رقماً يبدأ وينتهي بـ 3');
    if (f.cr && !/^\d{10}$/.test(f.cr)) return showErr('#cerr', 'السجل التجاري 10 أرقام');
    try { await busy($('#cb'), async () => { const cid = await db.rpc('create_company', { p_name: f.name, p_vat: blank(f.vat), p_cr: blank(f.cr) }); S.cid = cid; LS.set('waad.cid', cid); await boot(); if (S.sub && S.sub.status === 'pending') return; location.hash = '#/welcome'; setTimeout(() => companyCodeBox(true), 400); }); } catch (er) { showErr('#cerr', er); } };
}

/* the company code employees sign in with: shown once on creation, and any time from settings / the welcome page */
function companyCodeBox(first) {
  const c = S.company || {}, link = location.origin + location.pathname + '?c=' + c.code, me = (S.session && S.session.user.email) || '';
  const msg = tr('رمز منشأتك في نظام وعد') + ' (' + c.name + '): ' + c.code + '\n' + tr('رابط دخول الموظفين') + ': ' + link + '\n' + tr('احتفظ بهذا الرمز؛ يدخل به موظفوك مع أرقامهم الوظيفية.');
  const mail = 'mailto:' + encodeURIComponent(me) + '?subject=' + encodeURIComponent(tr('رمز منشأتك في نظام وعد') + ' — ' + c.name) + '&body=' + encodeURIComponent(msg);
  const d = modal(first ? 'احفظ رمز منشأتك' : 'رمز المنشأة', `<p class="muted">${esc('هذا رمز منشأتك. يدخل به موظفوك مع أرقامهم الوظيفية، ولا يتكرر لأي منشأة أخرى.')}</p>
    <div style="text-align:center;margin:14px 0"><span class="code" id="ccv" style="font-size:30px;padding:8px 18px">${esc(c.code)}</span></div>
    <p class="small" style="text-align:center"><span class="muted">${esc('رابط دخول الموظفين')}:</span><br><span class="num" style="word-break:break-all">${esc(link)}</span></p>
    <div class="row" style="justify-content:center"><a class="btn pri" id="ccm" href="${esc(mail)}">${esc('أرسله إلى بريدي')}</a><button type="button" class="btn" id="ccc">${esc('نسخ الرمز والرابط')}</button>${waBtn('', msg, 'واتساب', 'btn wa')}</div>
    <p class="muted small" style="text-align:center">${esc('يفتح «أرسله إلى بريدي» برنامج البريد برسالة جاهزة إلى')} <span class="num">${esc(me)}</span> — ${esc('اضغط إرسال فيها. تجده دائماً في «إعدادات المنشأة».')}</p>
    ${first ? `<label class="row small" style="justify-content:center;gap:6px;margin-top:6px"><input type="checkbox" id="ccok"> ${esc('حفظت رمز المنشأة')}</label>` : ''}`, first ? { ok: 'متابعة', onOk: async () => { if (!$('#ccok').checked) throw new Error('احفظ الرمز أولاً (أرسله لبريدك أو انسخه)، ثم ضع العلامة'); } } : {});
  $('#ccc', d).onclick = async ev => { try { await navigator.clipboard.writeText(msg); ev.target.textContent = tr('نُسخ ✓'); } catch (er) { toast('تعذر النسخ — انسخ الرمز من الشاشة'); } };
  $('#ccm', d).addEventListener('click', () => { if ($('#ccok', d)) $('#ccok', d).checked = true; });
  if (first) { $('#mx', d).hidden = true; if ($('#mc', d)) $('#mc', d).hidden = true; const keep = ev => ev.preventDefault(); d.addEventListener('cancel', keep); d.addEventListener('close', () => d.removeEventListener('cancel', keep), { once: true }); }
  return d;
}

/* ===== boot & context ===== */
async function loadContext(pre) {
  S.companies = pre || await db.rpc('my_companies');
  if (!S.companies.length) return false;
  let c = S.companies.find(x => x.company_id === S.cid) || S.companies[0];
  S.cid = c.company_id; LS.set('waad.cid', S.cid); S.role = c.role; S.roles = new Set(c.roles && c.roles.length ? c.roles : [c.role]); S.emp = c.employee_id; S.mustChange = !!c.must_change_password; if (c.code) { LS.set('waad.ccode', c.code); LS.set('waad.cname', c.name); }
  const fr = ['accountant', 'storekeeper'].filter(r => S.roles.has(r));
  const [[co], [sub], , fp, me, pf] = await Promise.all([db.get('companies', { id: 'eq.' + S.cid }), db.get('company_subscriptions', { company_id: 'eq.' + S.cid }).catch(() => []), preloadNames(),
    fr.length ? db.get('finance_permissions', { company_id: 'eq.' + S.cid, role: 'in.(' + fr.join(',') + ')', select: 'perm' }) : [],
    S.emp ? db.get('employees', { id: 'eq.' + S.emp }) : [], S.emp ? db.get('petty_funds', { employee_id: 'eq.' + S.emp, select: 'id', limit: 1 }).catch(() => []) : []]);
  S.company = co; S.sub = sub || null;
  S.perms = new Set();
  (c.perms || []).forEach(p => S.perms.add(p));
  fp.forEach(p => S.perms.add(p.perm));
  S.myEmp = me[0] || null;
  S.hasPetty = pf.length > 0;
  return true;
}
// links from auth emails (password recovery, sign-up confirmation) come back as #access_token=…&type=… or #error=…
async function authFromLink() {
  const h = location.hash || '';
  if (!/(^#|&)(access_token|error_code|error)=/.test(h)) return null;
  const p = new URLSearchParams(h.slice(1));
  history.replaceState(null, '', location.pathname + location.search);
  if (!p.get('access_token')) return { error: p.get('error_code') === 'otp_expired' ? 'انتهت صلاحية الرابط أو استُخدم من قبل — اطلب رابطاً جديداً' : 'الرابط غير صالح — اطلب رابطاً جديداً' };
  setSession({ access_token: p.get('access_token'), refresh_token: p.get('refresh_token'), expires_in: +p.get('expires_in') || 3600, user: null });
  try { const u = await api('/auth/v1/user'); setSession({ access_token: p.get('access_token'), refresh_token: p.get('refresh_token'), expires_in: +p.get('expires_in') || 3600, user: u }); }
  catch (e) { setSession(null); return { error: 'الرابط غير صالح — اطلب رابطاً جديداً' }; }
  return { type: p.get('type') };
}
// the landing page links to app/?start=signup (new company) or ?start=signin (owner/admin e-mail login)
function startTab() {
  const q = new URLSearchParams(location.search), t = { signup: 'up', signin: 'in' }[q.get('start')];
  if (q.has('start')) { q.delete('start'); history.replaceState(null, '', location.pathname + (q.toString() ? '?' + q : '') + location.hash); }
  return t;
}
async function boot() {
  const link = await authFromLink();
  if (link && link.error) return authView('in', link.error);
  if (link && link.type === 'recovery') return changePasswordView('recovery');
  if (!S.session) return legalHash() ? legalView(legalHash()) : authView(startTab());
  try {
    // startup calls that do not depend on each other go out together (each round trip to the server costs ~0.2 s)
    const [mfa, plat, comps] = await Promise.all([db.rpc('mfa_state').catch(() => null), db.rpc('is_platform_admin').catch(() => false), db.rpc('my_companies').catch(e => { if (e.status === 401) throw e; return null; })]);
    S.mfa = mfa; S.platform = plat;
    if (mfa && mfa.enrolled && mfa.aal !== 'aal2') return mfaChallengeView();
    if (LS.get('waad.terms')) { db.rpc('accept_terms', { p_version: LS.get('waad.terms') }).catch(() => {}); LS.set('waad.terms', null); }
    if (ADMIN) {
      if (!S.platform) return notAdminView();
      const me = await db.rpc('platform_admin_me').catch(() => null);
      return me && me.must_change ? changePasswordView(true) : platformView();
    }
    if (S.platform && (/^#\/platform/.test(location.hash) || !(comps || []).length)) { location.href = ADMIN_URL; return; }
    // a Waad team account (username sign-in) never gets a company: it belongs on the admin site
    if (!(comps || []).length && /@admin\.waad\.app$/i.test((S.session.user || {}).email || '')) { location.href = ADMIN_URL; return; }
    if (!(await loadContext(comps))) return onboardView();
    if (S.mustChange) return changePasswordView(true);
    if (S.sub && S.sub.status === 'pending') return pendingView();
  } catch (e) {
    if (e.status === 401) { setSession(null); return authView('in', 'انتهت الجلسة — سجّل الدخول مجدداً'); }
    $('#app').innerHTML = `<div class="auth"><div class="abox">${brand()}<div class="card"><div class="err">${esc(e.message)}</div><button class="btn" onclick="boot()">إعادة المحاولة</button></div></div></div>`; return;
  }
  shell(); route();
}

/* ===== packages: which modules this company's subscription opens (the database enforces the same rule) ===== */
const MODULES = { hr: 'الموارد البشرية', finance: 'المالية والمحاسبة', sales: 'المبيعات', purch: 'المشتريات', stock: 'المخزون', proj: 'المشاريع' };
const MOD_ROUTES = {
  hr: ['hrdash', 'employees', 'grades', 'insurance', 'trainplan', 'docs', 'att', 'attendance', 'roster', 'policies', 'leavecal', 'penalties', 'payroll', 'payslips', 'eos', 'nitaqat', 'travel', 'workflows', 'clearance', 'reviews', 'recruit', 'training', 'hrreports', 'org', 'letter', 'path', 'profile', 'requests'],
  sales: ['quotes', 'orders', 'deliveries', 'sales', 'crm', 'marketing'],
  purch: ['purchreq', 'porders', 'receipts', 'purchases', 'rfq'],
  stock: ['items', 'warehouses', 'transfers', 'counts', 'expiry', 'reorder', 'serials'],
  finance: ['payments', 'journal', 'reports', 'coa', 'bankrec', 'cheques', 'petty', 'mypetty', 'currencies', 'opening', 'assets', 'costcenters', 'budgets', 'periods'],
  proj: ['projects'] };
function routeModule(h) {
  const p = String(h || '').split('?')[0].split('/'), r = p[1] || '';
  if (r === 'parties') return p[2] === 'supplier' ? 'purch' : 'sales';
  for (const [m, rs] of Object.entries(MOD_ROUTES)) if (rs.includes(r)) return m;
  return null;
}
const subLive = () => { const s = S.sub; if (!s) return true;
  if (s.status === 'active') return !s.sub_ends || s.sub_ends >= today();
  if (s.status === 'trial') return !s.trial_ends || s.trial_ends >= today();
  return false; };   // pending (waiting for Waad's approval) and suspended: closed
// a new company waits until the Waad team accepts it (admin site → المنشآت)
function pendingView() {
  $('#app').innerHTML = `<div class="auth"><div class="abox">${brand()}<div class="card"><h2>${esc(tr('وصلنا طلبك'))}</h2>
    <p>${esc(tr('سجّلنا منشأتك'))} «<b>${esc(S.company ? S.company.name : '')}</b>»${esc(tr('، وفريق وعد يراجع الطلب ويفعّل لك التجربة قريباً. بنتواصل معك على إيميلك.'))}</p>
    <div class="row" style="gap:8px;flex-wrap:wrap"><button class="btn pri" id="pchk">${esc(tr('تحقق مرة ثانية'))}</button>
      <a class="btn" href="${SITE_URL}contact.html#contact" target="_blank" rel="noopener">${esc(tr('تواصل معنا'))}</a><button class="btn" id="lo">${esc(tr('تسجيل الخروج'))}</button></div></div>
    <p class="muted small" style="text-align:center">${langBtn('linkbtn')}</p></div></div>`;
  $('#pchk').onclick = () => boot();
  $('#lo').onclick = async () => { await authApi.signOut(); authView(); };
  $('#lg').onclick = () => setLang(LANG === 'en' ? 'ar' : 'en');
}
const modOn = m => !m || !S.sub || (subLive() && (S.sub.modules || []).includes(m));

/* ===== shell & navigation ===== */
const VIEWS = {};       // '#/path' -> async (root, arg) => void
let NAVC = { approvals: 0 };
function navItems() {
  const it = []; const g = t => it.push({ g: t });
  it.push({ h: '#/home', t: 'الرئيسية' });
  if (isHR() || isFin() || has('manager')) it.push({ h: '#/analytics', t: 'التحليلات' });
  if (S.emp) { g('خدماتي'); if (S.company && S.company.att_enabled && !(S.myEmp && S.myEmp.att_exempt)) it.push({ h: '#/attendance', t: 'حضوري' });
    it.push({ h: '#/requests', t: 'طلباتي' }, { h: '#/payslips', t: 'قسائم الراتب' }, { h: '#/reviews', t: 'تقييم الأداء' }, { h: '#/profile', t: 'ملفي' });
    if (S.hasPetty) it.push({ h: '#/mypetty', t: 'عهدتي النقدية' });
    if (!isHR()) it.push({ h: '#/policies', t: 'السياسات واللوائح' });
    const ov = (S.company && S.company.org_visibility) || 'all';
    if (!(isHR() || has('finance')) && (ov === 'all' || (ov === 'managers' && has('manager')))) it.push({ h: '#/org', t: 'الهيكل التنظيمي' }); }
  if (!['accountant', 'storekeeper'].includes(S.role) || S.emp) it.push({ h: '#/approvals', t: 'الاعتمادات', pill: NAVC.approvals });
  if (has('manager') && !(isHR() || has('finance'))) it.push({ h: '#/clearance', t: 'إخلاء الطرف' });
  if (isHR() || has('finance')) {
    g('الموارد البشرية');
    it.push({ h: '#/hrdash', t: 'لوحة الموارد البشرية' });
    if (isHR()) it.push({ h: '#/employees', t: 'الموظفون' }, { h: '#/docs', t: 'المستندات والعقود', pill: NAVC.docs });
    it.push({ h: '#/org', t: 'الهيكل التنظيمي' });
    it.push({ h: '#/att', t: 'الحضور والانصراف' });
    if (isHR()) it.push({ h: '#/roster', t: 'جدول الورديات' }, { h: '#/policies', t: 'السياسات واللوائح' });
    if (isHR()) it.push({ h: '#/leavecal', t: 'تقويم الإجازات' });
    it.push({ h: '#/penalties', t: 'المخالفات والجزاءات', pill: NAVC.pen });
    it.push({ h: '#/payroll', t: 'مسير الرواتب' });
    if (isHR()) it.push({ h: '#/eos', t: 'مكافأة نهاية الخدمة' }, { h: '#/nitaqat', t: 'نطاقات والتوطين' });
    it.push({ h: '#/travel', t: 'السفر: التذاكر والتأشيرات' });
    if (isHR()) it.push({ h: '#/workflows', t: 'مسارات الاعتماد' });
    it.push({ h: '#/clearance', t: 'إخلاء الطرف' });
    if (isHR() && !S.emp) it.push({ h: '#/reviews', t: 'تقييم الأداء' });
    if (isHR()) it.push({ h: '#/recruit', t: 'التوظيف' }, { h: '#/training', t: 'التدريب' }, { h: '#/trainplan', t: 'خطة التدريب السنوية' }, { h: '#/grades', t: 'الدرجات الوظيفية' }, { h: '#/insurance', t: 'التأمين الطبي' });
    it.push({ h: '#/hrreports', t: 'تقارير الموارد البشرية' });
  }
  if (has('manager') && !isHR()) { g('فريقي'); it.push({ h: '#/att', t: 'حضور الفريق' }, { h: '#/leavecal', t: 'تقويم الإجازات' }); }
  if (isFin() && (can('sales') || can('stock'))) {
    g('المبيعات');
    if (can('sales')) it.push({ h: '#/crm', t: 'الفرص والعملاء المحتملون' }, { h: '#/marketing', t: 'التسويق والحملات' }, { h: '#/quotes', t: 'عروض الأسعار' });
    it.push({ h: '#/orders', t: 'أوامر البيع' }, { h: '#/deliveries', t: 'إشعارات التسليم' });
    if (can('sales')) it.push({ h: '#/sales', t: 'فواتير المبيعات' }, { h: '#/parties/customer', t: 'العملاء' });
  }
  if (isFin() && (can('purch') || can('stock'))) {
    g('المشتريات');
    if (can('purch')) it.push({ h: '#/purchreq', t: 'طلبات الشراء' }, { h: '#/rfq', t: 'طلبات عروض الأسعار' });
    it.push({ h: '#/porders', t: 'أوامر الشراء' }, { h: '#/receipts', t: 'استلام البضاعة' });
    if (can('purch')) it.push({ h: '#/purchases', t: 'فواتير المشتريات' }, { h: '#/parties/supplier', t: 'الموردون' });
  }
  if (isFin() && (can('stock') || can('items') || can('stockadj'))) {
    g('المخزون');
    it.push({ h: '#/items', t: 'الأصناف والمخزون' }, { h: '#/warehouses', t: 'المستودعات' });
    if (can('stock')) it.push({ h: '#/transfers', t: 'تحويلات المخزون' });
    it.push({ h: '#/counts', t: 'الجرد' });
    if (can('stock')) it.push({ h: '#/expiry', t: 'صلاحية الأصناف' }, { h: '#/reorder', t: 'إعادة الطلب' }, { h: '#/serials', t: 'الأرقام التسلسلية' });
  }
  if (isFin()) {
    g('المالية');
    if (can('sales') || can('purch')) it.push({ h: '#/payments', t: 'سندات القبض والصرف' });
    if (can('je')) it.push({ h: '#/journal', t: 'القيود اليومية' });
    if (can('reports') || can('vat') || can('ledger') || can('sales') || can('purch')) it.push({ h: '#/reports', t: 'التقارير' });
    if (can('coa') || can('ledger')) it.push({ h: '#/coa', t: 'دليل الحسابات' });
    if (can('je')) it.push({ h: '#/bankrec', t: 'التسوية البنكية' });
    if (can('je') || can('reports')) it.push({ h: '#/assets', t: 'الأصول الثابتة' });
    if (can('coa') || can('reports')) it.push({ h: '#/costcenters', t: 'مراكز التكلفة' }, { h: '#/budgets', t: 'الموازنات' });
    if (can('sales') || can('purch')) it.push({ h: '#/cheques', t: 'الشيكات' });
    if (can('je')) it.push({ h: '#/petty', t: 'العُهد النقدية' });
    if (can('coa') || can('sales') || can('purch')) it.push({ h: '#/currencies', t: 'العملات' });
    if (has('owner', 'admin', 'finance')) it.push({ h: '#/periods', t: 'إقفال الفترات والسنة' }, { h: '#/opening', t: 'الأرصدة الافتتاحية' });
  }
  if (has('owner', 'admin', 'finance', 'hr')) { g('المشاريع'); it.push({ h: '#/projects', t: 'المشاريع وجداول الوقت' }); }
  if (has('owner', 'admin', 'hr', 'finance')) { g('الإعدادات'); it.push({ h: '#/users', t: 'المستخدمون والدعوات' }); if (has('owner', 'admin', 'finance')) it.push({ h: '#/settings', t: 'إعدادات المنشأة' }); }
  return it;
}
function shell() {
  const multi = S.companies.length > 1; // one account = one company (subscription); the switcher only appears for someone invited into more than one
  $('#app').innerHTML = `<div class="shell"><aside class="side" id="side">${brand()}<nav class="nav" id="nav"></nav></aside>
    <div class="main"><header class="top"><button class="btn sm menu" id="mb" aria-label="القائمة">☰</button>
      <div class="cname"><b>${esc(S.company ? S.company.name : '')}</b> <span class="badge info">${esc(ROLES[S.role] || S.role)}</span></div><div class="sp"></div>
      ${multi ? `<select id="cs" style="width:auto;min-height:32px">${S.companies.map(c => opt(c.company_id, c.name, S.cid)).join('')}</select>` : ''}
      <div class="umw"><button class="btn sm um" id="um" aria-haspopup="true" aria-expanded="false" aria-label="حسابي" title="حسابي"><svg class="bi" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21a8 8 0 0 1 16 0"/></svg><span class="bt">حسابي</span><span class="bdot" id="bcnt" hidden></span></button>
        <div class="umenu" id="umenu" role="menu" hidden>
          <button type="button" class="mi" id="bell" role="menuitem"><svg class="bi" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4zM10 20a2 2 0 0 0 4 0"/></svg><span>التنبيهات</span><span class="mcnt" id="bcnt2" hidden></span></button>
          <button type="button" class="mi" id="lg" role="menuitem" data-nt lang="${LANG === 'en' ? 'ar' : 'en'}"><svg class="bi" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18zM3 12h18M12 3c2.5 2.5 3.5 5.5 3.5 9s-1 6.5-3.5 9c-2.5-2.5-3.5-5.5-3.5-9s1-6.5 3.5-9z"/></svg><span>${LANG === 'en' ? 'العربية' : 'English'}</span></button><button type="button" class="mi" id="th" role="menuitem" data-theme-btn="menu"></button>
          <button type="button" class="mi" id="pw" role="menuitem"><svg class="bi" viewBox="0 0 24 24" aria-hidden="true"><path d="M8 11V8a4 4 0 1 1 8 0v3M5 11h14v10H5zM12 15v2"/></svg><span>تغيير كلمة المرور</span></button>
          <button type="button" class="mi" id="mfa" role="menuitem"><svg class="bi" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6zM9 12l2 2 4-4"/></svg><span>التحقق بخطوتين</span></button>
          ${S.platform ? '<a class="mi" href="' + ADMIN_URL + '" id="plat" role="menuitem"><svg class="bi" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h16v6H4zM4 14h7v6H4zM15 14h5v6h-5z"/></svg><span>لوحة إدارة المنصة</span></a>' : ''}
          <a class="mi" href="#/privacy" role="menuitem"><svg class="bi" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 3h9l4 4v14H6zM9 12h7M9 16h7"/></svg><span>الخصوصية والشروط</span></a>
          <button type="button" class="mi out" id="lo" role="menuitem"><svg class="bi" viewBox="0 0 24 24" aria-hidden="true"><path d="M15 4h4v16h-4M10 8l-4 4 4 4M6 12h10"/></svg><span>تسجيل الخروج</span></button>
        </div><div class="bpanel" id="bpanel" hidden></div></div></header>
      <div class="scrim" id="scrim"></div>
      <div id="ann"></div><main class="page" id="page"></main></div></div>`;
  drawNav();
  $('#mb').onclick = () => $('#side').classList.toggle('open');
  $('#scrim').onclick = () => $('#side').classList.remove('open');
  $('#th').onclick = toggleTheme; applyTheme(curTheme());
  $('#lg').onclick = () => setLang(LANG === 'en' ? 'ar' : 'en');
  $('#pw').onclick = () => changePasswordView(false);
  const umSet = open => { $('#umenu').hidden = !open; $('#um').setAttribute('aria-expanded', open ? 'true' : 'false'); };
  $('#um').onclick = ev => { ev.stopPropagation(); const p = $('#bpanel'); if (!p.hidden) { p.hidden = true; return umSet(false); } umSet($('#umenu').hidden); };
  $('#bell').onclick = ev => { ev.stopPropagation(); umSet(false); const p = $('#bpanel'); p.hidden = false; drawBell(true); LS.set(seenKey(), new Date().toISOString()); };
  $('#pw').addEventListener('click', () => umSet(false));
  $('#mfa').onclick = () => { umSet(false); mfaSetup(); };
  $$('#umenu a.mi').forEach(a => a.addEventListener('click', () => umSet(false)));
  document.addEventListener('click', ev => { if (!$('#umenu') || ev.target.closest('.umw')) return; umSet(false); $('#bpanel').hidden = true; });
  document.addEventListener('keydown', ev => { if (ev.key === 'Escape' && $('#umenu')) { umSet(false); $('#bpanel').hidden = true; } });
  $('#lo').onclick = async () => { await authApi.signOut(); authView(); };
  if (multi) $('#cs').onchange = async e => { S.cid = e.target.value; LS.set('waad.cid', S.cid); await loadContext(); shell(); location.hash = '#/home'; route(); };
  refreshCounts(); drawAnn();
}
// announcements from Waad (admin site → «الإعلانات»): shown above every screen until the user closes them
async function drawAnn() {
  const box = $('#ann'); if (!box) return;
  const seen = LS.get('waad.annseen') || [], rows = (await db.rpc('my_announcements').catch(() => [])).filter(a => !seen.includes(a.id));
  box.innerHTML = rows.map(a => `<div class="ann${a.level === 'warn' ? ' warn' : ''}" role="status"><span data-nt>${esc(LANG === 'en' && a.body_en ? a.body_en : a.body_ar)}</span>
    <button type="button" class="x" data-ann="${esc(a.id)}" aria-label="إغلاق">×</button></div>`).join('');
  $$('[data-ann]', box).forEach(b => b.onclick = () => { LS.set('waad.annseen', [...seen, b.dataset.ann].slice(-50)); b.parentElement.remove(); });
}
const NI = { home: 'M3 11l9-8 9 8v9a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z', chart: 'M4 20V11M10 20V5M16 20v-7M21 20H3', clock: 'M12 3a9 9 0 1 0 0 18a9 9 0 0 0 0-18zM12 7v5l3 2',
  doc: 'M7 3h7l5 5v13H7zM14 3v5h5M10 13h6M10 17h6', user: 'M12 12a4 4 0 1 0 0-8a4 4 0 0 0 0 8zM4 21c0-4 4-6 8-6s8 2 8 6', users: 'M9 11a4 4 0 1 0 0-8a4 4 0 0 0 0 8zM2 21c0-3.5 3-5.5 7-5.5s7 2 7 5.5M16 3.5a4 4 0 0 1 0 7.5M18 15.5c2.4.6 4 2.3 4 5.5',
  check: 'M20 6L9 17l-5-5', money: 'M3 6h18v12H3zM3 10h18M7 15h3', cal: 'M4 5h16v16H4zM4 9h16M8 3v4M16 3v4', org: 'M10 3h4v4h-4zM4 17h4v4H4zM16 17h4v4h-4zM12 7v5M6 17v-3h12v3',
  shield: 'M12 3l8 3v6c0 5-3.5 8-8 9c-4.5-1-8-4-8-9V6z', plane: 'M21 4L3 11l7 3 3 7z', flow: 'M5 4h4v4H5zM15 16h4v4h-4zM7 8v3a3 3 0 0 0 3 3h4a3 3 0 0 1 3 3v-1',
  cart: 'M3 4h2l2 12h11l2-8H6M9 20h.01M18 20h.01', box: 'M3 7l9-4 9 4v10l-9 4-9-4zM3 7l9 4 9-4M12 11v10', book: 'M5 4h11a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3zM5 17a3 3 0 0 1 3-3h11',
  gear: 'M4 6h9M17 6h3M15 4v4M4 12h3M11 12h9M9 10v4M4 18h11M19 18h1M17 16v4', star: 'M12 3l2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z', grad: 'M2 9l10-5 10 5-10 5zM6 11v5c3 2 9 2 12 0v-5',
  search: 'M11 4a7 7 0 1 0 0 14a7 7 0 0 0 0-14zM21 21l-5-5', truck: 'M2 6h11v10H2zM13 9h4l4 4v3h-8M6 19a2 2 0 1 0 0-.01M17 19a2 2 0 1 0 0-.01', swap: 'M4 8h14l-3-3M20 16H6l3 3' };
const NAV_IC = { home: 'home', analytics: 'chart', attendance: 'clock', att: 'clock', requests: 'doc', payslips: 'money', reviews: 'star', profile: 'user', policies: 'book', org: 'org', approvals: 'check', clearance: 'shield',
  hrdash: 'chart', employees: 'users', docs: 'doc', roster: 'cal', leavecal: 'cal', penalties: 'shield', payroll: 'money', eos: 'money', nitaqat: 'chart', travel: 'plane', workflows: 'flow', recruit: 'search', training: 'grad',
  hrreports: 'chart', crm: 'users', rfq: 'doc', serials: 'check', grades: 'chart', insurance: 'shield', trainplan: 'cal', platform: 'gear', sales: 'cart', quotes: 'doc', orders: 'cart', deliveries: 'truck', purchreq: 'doc', porders: 'box', receipts: 'truck', warehouses: 'box', transfers: 'swap', counts: 'check', expiry: 'cal', reorder: 'cart', parties: 'users', purchases: 'box', payments: 'swap', items: 'box', journal: 'book', reports: 'chart', coa: 'book', bankrec: 'check', cheques: 'doc', petty: 'money', mypetty: 'money', currencies: 'swap', opening: 'book', assets: 'box', costcenters: 'org', budgets: 'chart', periods: 'shield', users: 'users', settings: 'gear' };
const navIcon = h => `<svg class="ni" viewBox="0 0 24 24" aria-hidden="true"><path d="${NI[NAV_IC[h.split('/')[1]]] || NI.doc}"/></svg>`;
function drawNav() {
  const cur = location.hash.split('?')[0] || '#/home', shut = LS.get('waad.navshut') || [];
  const isOn = i => cur === i.h || (cur.startsWith(i.h + '/') && i.h !== '#/home');
  const groups = [{ g: null, items: [] }]; navItems().filter(i => i.g || modOn(routeModule(i.h))).forEach(i => i.g ? groups.push({ g: i.g, items: [] }) : groups[groups.length - 1].items.push(i));
  $('#nav').innerHTML = groups.filter(x => x.items.length).map(x => { const open = !x.g || !shut.includes(x.g) || x.items.some(isOn);
    return `${x.g ? `<button type="button" class="grp" data-grp="${esc(x.g)}" aria-expanded="${open}">${esc(x.g)}<span class="chev">▾</span></button>` : ''}<div class="nitems" ${open ? '' : 'hidden'}>${x.items.map(i =>
      `<a href="${i.h}" class="${isOn(i) ? 'on' : ''}">${navIcon(i.h)}<span class="nt">${esc(i.t)}</span>${i.pill ? `<span class="pill">${i.pill}</span>` : ''}</a>`).join('')}</div>`; }).join('');
  $$('[data-grp]', $('#nav')).forEach(b => b.onclick = () => { const g = b.dataset.grp, s = new Set(LS.get('waad.navshut') || []), box = b.nextElementSibling, open = box.hidden;
    box.hidden = !open; b.setAttribute('aria-expanded', open); open ? s.delete(g) : s.add(g); LS.set('waad.navshut', [...s]); });
  $$('a', $('#nav')).forEach(a => a.addEventListener('click', () => $('#side') && $('#side').classList.remove('open')));
}
async function refreshCounts() { try { NAVC.approvals = (await pendingForMe()).length; if (isHR()) { NAVC.docs = await docAlertCount(); NAVC.pen = (await db.get('penalties', { company_id: 'eq.' + S.cid, status: 'eq.open', select: 'id' }).catch(() => [])).length; } drawNav(); } catch (e) {} drawBell(); }

/* ===== notifications bell: built from what already needs attention — nothing extra is stored ===== */
const seenKey = () => 'waad.seen.' + ((S.session && S.session.user) || {}).id + '.' + S.cid;
let NOTIFS = [], BELL_AT = 0;
async function loadNotifs() {
  const out = [], td = today(), add = (t, h, o = {}) => out.push(Object.assign({ t, h }, o));
  const safe = p => p.catch(() => null);
  const [mine, myReqs, alerts, prob, myDocs, pens, myPens] = await Promise.all([
    safe(pendingForMe()),
    S.emp ? safe(db.get('requests', { employee_id: 'eq.' + S.emp, status: 'in.(approved,rejected)', order: 'decided_at.desc', limit: 10 })) : null,
    isHR() ? safe(db.rpc('doc_alerts', { p_company: S.cid, p_within: 30 })) : null,
    isHR() ? safe(db.rpc('probation_ends', { p_company: S.cid })) : null,
    S.emp ? safe(db.get('employee_documents', { employee_id: 'eq.' + S.emp, expiry_date: 'lte.' + new Date(Date.now() + 30 * 864e5).toISOString().slice(0, 10) })) : null,
    isHR() ? safe(db.get('penalties', { company_id: 'eq.' + S.cid, status: 'in.(open,applied)', select: 'id,status,inv_on,griev_on,griev_result' })) : null,
    S.emp ? safe(db.get('penalties', { employee_id: 'eq.' + S.emp, status: 'in.(open,applied)', select: 'id,status,inv_on,emp_defense,notified_on,griev_on' })) : null]);
  if (mine && mine.length) add(mine.length + ' طلبات بانتظار اعتمادك', '#/approvals', { hot: 1 });
  if (pens) { const g = pens.filter(p => p.griev_on && !p.griev_result).length, due = pens.filter(p => p.status === 'open' && p.inv_on && (new Date(td) - new Date(p.inv_on)) / 864e5 >= 25).length;
    if (g) add(g + ' تظلمات من جزاءات بانتظار البت خلال 15 يوماً', '#/penalties', { hot: 1 });
    if (due) add(due + ' مخالفات انتهى تحقيقها وتقترب مهلة القرار (30 يوماً)', '#/penalties', { hot: 1 }); }
  if (myPens) { myPens.filter(p => p.status === 'open' && !p.inv_on && !p.emp_defense).forEach(() => add('مخالفة منسوبة إليك — اطّلع وأرسل ردك الكتابي', '#/profile', { hot: 1 }));
    myPens.filter(p => p.status === 'applied' && p.notified_on && (new Date(td) - new Date(p.notified_on)) / 864e5 <= 30 && !p.griev_on).forEach(p => add('صدر بحقك جزاء — لك حق التظلم خلال 30 يوماً', '#/profile', { at: p.notified_on + 'T12:00:00Z' })); }
  if (alerts) { const u = alerts.filter(a => a.level === 'expired' || a.level === 'd30').length; if (u) add(u + ' مستندات أو عقود منتهية أو تنتهي خلال 30 يوماً', '#/docs', { hot: 1 }); }
  if (prob) { const em = await employeesMap().catch(() => ({})); const soon = prob.filter(p => p.effective_end >= td && (new Date(p.effective_end) - new Date(td)) / 864e5 <= 14 && em[p.employee_id] && !em[p.employee_id].end_date);
    soon.forEach(p => add('تنتهي فترة تجربة', '#/hrreports', { hot: 1, n: em[p.employee_id].full_name, tail: 'بتاريخ ' + p.effective_end })); }
  if (myDocs) myDocs.forEach(d => add((d.expiry_date < td ? 'انتهت ' : 'تنتهي ') + (typeof docName === 'function' ? docName(d) : d.doc_type) + ' بتاريخ ' + d.expiry_date + ' — تواصل مع الموارد البشرية', '#/profile', { hot: 1 }));
  if (S.emp) { const since = new Date(Date.now() - 30 * 864e5).toISOString(), [tt, vv] = await Promise.all([safe(db.get('travel_tickets', { employee_id: 'eq.' + S.emp, delivered_at: 'gte.' + since })), safe(db.get('exit_visas', { employee_id: 'eq.' + S.emp, delivered_at: 'gte.' + since }))]);
    (tt || []).forEach(t => add(t.mode === 'cash' ? 'صُرف لك بدل تذكرة السفر' : 'وصلتك تذكرة السفر — افتح طلبك', '#/requests', { at: t.delivered_at, ok: true }));
    (vv || []).forEach(v => add('وصلتك تأشيرة الخروج والعودة — افتح طلبك', '#/requests', { at: v.delivered_at, ok: true })); }
  if (typeof finNotifs === 'function') await finNotifs(add, safe);
  if (myReqs) { const since = Date.now() - 30 * 864e5; myReqs.filter(r => r.decided_at && new Date(r.decided_at) > since).forEach(r => add((r.status === 'approved' ? 'اعتُمد ' : 'رُفض ') + 'طلبك: ' + (KIND[r.kind] || r.kind), '#/requests', { at: r.decided_at, ok: r.status === 'approved' })); }
  return out;
}
async function drawBell(open) {
  if (!$('#bell')) return;
  if (open && $('#bpanel')) $('#bpanel').innerHTML = '<div class="muted small" style="padding:12px">جارٍ التحميل…</div>';
  try { NOTIFS = await loadNotifs(); BELL_AT = Date.now(); } catch (e) { NOTIFS = []; }
  const seen = new Date(LS.get(seenKey()) || 0), isNew = x => !!x.at && new Date(x.at) > seen, n = NOTIFS.filter(x => x.hot || isNew(x)).length;
  for (const c of [$('#bcnt'), $('#bcnt2')]) if (c) { c.hidden = !n; c.textContent = n > 9 ? '9+' : n; }
  const p = $('#bpanel'); if (!p) return;
  p.innerHTML = `<div class="bh" data-ready><b>التنبيهات</b></div>${NOTIFS.length ? NOTIFS.map(x => `<a href="${x.h}" class="bi${x.hot ? ' hot' : ''}${isNew(x) ? ' new' : ''}">${x.ok === true ? '<span class="ok">✓</span> ' : x.ok === false ? '<span class="bad">✕</span> ' : ''}${esc(x.t)}${x.n ? ` <b>${esc(x.n)}</b>` : ''}${x.tail ? ' ' + esc(x.tail) : ''}${x.at ? ` <span class="muted small num">${esc(String(x.at).slice(0, 10))}</span>` : ''}</a>`).join('') : '<div class="muted small" style="padding:12px">لا توجد تنبيهات</div>'}`;
  $$('a', p).forEach(a => a.onclick = () => { p.hidden = true; });
}
async function route() {
  if (!S.session || !S.cid || !$('#page')) return;
  const [path, q] = (location.hash || '#/home').split('?');
  const parts = path.split('/'); // ['#', 'sales', 'id']
  let key = parts.slice(0, 2).join('/'), arg = parts.slice(2).join('/');
  if (!VIEWS[key]) { key = '#/home'; arg = ''; }
  $('#side') && $('#side').classList.remove('open');
  drawNav();
  // each navigation renders into its own container, so a slow earlier page can never overwrite a newer one
  const page = document.createElement('div'); page.innerHTML = '<div class="muted">جارٍ التحميل…</div>';
  $('#page').replaceChildren(page);
  if (!modOn(routeModule(path))) { page.innerHTML = `<div class="note">${esc(tr('هذا القسم غير مشمول في باقة منشأتك.'))} ${has('owner') ? esc(tr('لتفعيله تواصل مع إدارة وعد.')) : esc(tr('راجع مالك المنشأة.'))}</div>`; return; }
  try { await VIEWS[key](page, arg, new URLSearchParams(q || '')); }
  catch (e) { if (e.status === 401 && !S.session) return authView('in', 'انتهت الجلسة — سجّل الدخول مجدداً'); if (page.isConnected) page.innerHTML = `<div class="err">${esc(e.message)}</div>`; }
}
window.addEventListener('hashchange', () => /(^#|&)(access_token|error_code)=/.test(location.hash) ? boot() : !S.session && legalHash() ? legalView(legalHash()) : ADMIN ? (S.platform && $('#ppage') ? platformView() : null) : S.platform && /^#\/platform/.test(location.hash) ? (location.href = ADMIN_URL) : S.platform && !$('#page') ? boot() : route());
window.addEventListener('hashchange', () => { if (!ADMIN && Date.now() - BELL_AT > 60000) drawBell(); });

/* ===== shared look-ups ===== */
const cache = {};
async function employeesMap(force) { if (force || !cache.emps) { cache.emps = await db.get('employees', { company_id: 'eq.' + S.cid, order: 'emp_no' }); } const m = {}; cache.emps.forEach(e => m[e.id] = e); return m; }
async function pendingForMe() {
  const reqs = await db.get('requests', { company_id: 'eq.' + S.cid, status: 'eq.pending', order: 'created_at' });
  if (!reqs.length) return [];
  if (has('owner') && !has('finance') && cache.noFin === undefined) cache.noFin = !(await db.get('members', { company_id: 'eq.' + S.cid, select: 'role,extra_roles' }).catch(() => [])).some(m => m.role === 'finance' || (m.extra_roles || []).includes('finance'));
  const ids = [...new Set(reqs.map(r => r.employee_id))];
  const emps = await db.get('employees', { id: 'in.(' + ids.join(',') + ')', select: 'id,manager_id,department_id,full_name,emp_no' });
  const em = {}; emps.forEach(e => em[e.id] = e);
  return reqs.filter(r => canAct(r, em[r.employee_id])).map(r => Object.assign(r, { _emp: em[r.employee_id] }));
}
function canAct(r, e) {
  const st = r.route[r.step]; if (!st) return false;
  if (S.emp && r.employee_id === S.emp) return false;
  if (st === 'm') return !!(e && S.emp && e.manager_id === S.emp);
  if (st === 'p') return has('hr', 'admin');
  if (st === 'h') return !!(S.company && S.company.hr_manager && S.company.hr_manager === S.session.user.id);
  if (st === 'f') return has('finance') || (has('owner') && cache.noFin === true);
  if (st === 'g') return has('owner');
  return false;
}

/* ===== two-step verification (TOTP authenticator app) ===== */
const authFetch = async (path, method = 'GET', body) => {
  const r = await fetch(CFG.url + '/auth/v1/' + path, { method, headers: { apikey: CFG.key, Authorization: 'Bearer ' + S.session.access_token, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined }).catch(e => { throw new ApiError(arMsg(e.message), 0); });
  const j = r.status === 204 ? {} : await r.json().catch(() => ({})); if (!r.ok) throw new ApiError(/code|otp|invalid/i.test(j.msg || j.message || j.error_code || '') ? tr('الرمز غير صحيح أو انتهت صلاحيته') : authMsg(j), r.status); return j;
};
const totpFactors = async () => ((await authFetch('user')).factors || []).filter(f => f.factor_type === 'totp');
async function mfaVerify(factorId, code) {
  if (!/^\d{6}$/.test(code)) throw new Error('الرمز 6 أرقام من تطبيق المصادقة');
  const ch = await authFetch('factors/' + factorId + '/challenge', 'POST', {});
  const j = await authFetch('factors/' + factorId + '/verify', 'POST', { challenge_id: ch.id, code });
  setSession(Object.assign({ user: S.session.user }, j));
}
function mfaChallengeView() {
  $('#app').innerHTML = `<div class="auth"><div class="abox">${brand()}<div class="card"><h2>التحقق بخطوتين</h2>
    <p class="muted small">افتح تطبيق المصادقة في جوالك (Google Authenticator أو Microsoft Authenticator) واكتب الرمز الظاهر لحساب وعد.</p>
    <form id="mf" novalidate>${field('رمز التحقق', '<input name="code" inputmode="numeric" autocomplete="one-time-code" maxlength="6" dir="ltr" required style="letter-spacing:6px;font-size:20px;text-align:center">')}<div id="merr2"></div><div style="height:12px"></div><button class="btn pri full" id="mfb">تحقق</button></form></div>
    <p class="muted small" style="text-align:center"><a href="#" id="mfo">تسجيل الخروج</a></p></div></div>`;
  $('#mf').code.focus();
  $('#mfo').onclick = async e => { e.preventDefault(); await authApi.signOut(); authView(); };
  $('#mf').onsubmit = async e => { e.preventDefault(); const code = e.target.code.value.trim();
    try { await busy($('#mfb'), async () => { const [f] = (await totpFactors()).filter(x => x.status === 'verified'); if (!f) throw new Error('لا يوجد تطبيق مصادقة مربوط'); await mfaVerify(f.id, code); }); boot(); }
    catch (er) { showErr('#merr2', er); } };
}
async function mfaSetup() {
  const fs = await totpFactors().catch(e => { toast(e.message); return null; }); if (!fs) return;
  const on = fs.find(f => f.status === 'verified');
  if (on) {
    modal('التحقق بخطوتين', `<div class="note">${esc(tr('مفعّل — يُطلب رمز من تطبيق المصادقة عند كل دخول.'))}</div><p class="muted small">${esc(tr('عند الإيقاف يكفي البريد وكلمة المرور للدخول إلى حسابك.'))}</p>`, { ok: 'إيقاف التحقق بخطوتين', onOk: async () => {
      await authFetch('factors/' + on.id, 'DELETE'); S.mfa = { enrolled: false }; toast(tr('أُوقف التحقق بخطوتين')); route(); } });
    return;
  }
  for (const f of fs) await authFetch('factors/' + f.id, 'DELETE').catch(() => {});   // leftovers of an unfinished setup
  let en; try { en = await authFetch('factors', 'POST', { factor_type: 'totp', friendly_name: 'Waad ' + Date.now() }); } catch (e) { return toast(e.message); }
  const t = en.totp || {}, secret = t.secret || '';
  modal('تفعيل التحقق بخطوتين', `<ol class="small" style="padding-inline-start:18px;margin-top:0"><li>${esc(tr('ثبّت تطبيق مصادقة في جوالك مثل Google Authenticator أو Microsoft Authenticator.'))}</li>
      <li>${esc(tr('امسح الرمز التالي من التطبيق، أو أدخل المفتاح يدوياً.'))}</li><li>${esc(tr('اكتب الرمز المكوّن من 6 أرقام الذي يظهر في التطبيق.'))}</li></ol>
    <div style="text-align:center" data-nt>${QR.svg(t.uri || '', 180)}<div class="small num" dir="ltr" id="mfs" style="word-break:break-all;margin-top:6px">${esc(secret)}</div></div>
    <div class="fg">${field('رمز التحقق', '<input name="code" inputmode="numeric" autocomplete="one-time-code" maxlength="6" dir="ltr" required>')}</div>`, {
    ok: 'تفعيل', onOk: async f => { await mfaVerify(en.id, (f.code || '').trim()); S.mfa = { enrolled: true, aal: 'aal2' }; toast(tr('فُعّل التحقق بخطوتين')); route(); } });
}
// report unexpected script errors (message and place only) so they can be fixed before anyone complains
let ERR_N = 0;
function reportError(message, source) {
  if (!S.session || !S.cid || ERR_N++ > 20 || !message) return;
  db.rpc('log_client_error', { p_company: S.cid, p_message: String(message).slice(0, 500), p_source: String(source || '').slice(0, 300), p_route: (location.hash || '').split('?')[0], p_agent: navigator.userAgent.slice(0, 200) }).catch(() => {});
}
window.addEventListener('error', e => reportError(e.message, (e.filename || '').split('/').pop() + ':' + e.lineno + ':' + e.colno));
window.addEventListener('unhandledrejection', e => { const r = e.reason || {}; if (r.status && r.status < 500) return; reportError(r.message || String(r), r.stack && String(r.stack).split('\n')[1]); });

/* ===== request attachments: images are shrunk in the browser; PDFs up to 3 MB ===== */
const docLabel = l => (LANG === 'en' && l.doc_label_en) || l.doc_label || '';
const refLabel = l => (LANG === 'en' && l.ref_label_en) || l.ref_label || '';
const blobB64 = b => new Promise((res, rej) => { const fr = new FileReader(); fr.onload = () => res(String(fr.result).split(',')[1] || ''); fr.onerror = () => rej(new Error('تعذّر قراءة الملف')); fr.readAsDataURL(b); });
async function readAttachment(file) {
  const pdf = file.type === 'application/pdf' || /\.pdf$/i.test(file.name);
  if (pdf) { if (file.size > 3 * 1048576) throw new Error(tr('حجم الملف أكبر من 3 ميجابايت') + ': ' + file.name); return { name: file.name, mime: 'application/pdf', data: await blobB64(file) }; }
  if (!/^image\//.test(file.type) && !/\.(jpe?g|png|webp|heic|heif)$/i.test(file.name)) throw new Error(tr('المرفق صورة أو PDF فقط') + ': ' + file.name);
  let bmp; try { bmp = await createImageBitmap(file); } catch (e) { throw new Error(tr('تعذّر فتح الصورة — صوّرها بصيغة JPG أو PDF') + ': ' + file.name); }
  const k = Math.min(1, 1600 / Math.max(bmp.width, bmp.height)), c = document.createElement('canvas');
  c.width = Math.round(bmp.width * k); c.height = Math.round(bmp.height * k); const x = c.getContext('2d'); x.fillStyle = '#fff'; x.fillRect(0, 0, c.width, c.height); x.drawImage(bmp, 0, 0, c.width, c.height);
  const blob = await new Promise(r => c.toBlob(r, 'image/jpeg', 0.82));
  if (!blob || blob.size > 3 * 1048576) throw new Error(tr('حجم الملف أكبر من 3 ميجابايت') + ': ' + file.name);
  return { name: file.name.replace(/\.[^.]+$/, '') + '.jpg', mime: 'image/jpeg', data: await blobB64(blob) };
}
async function openAttachment(id, table = 'request_attachments') {
  const w = window.open('', '_blank');
  try { const [a] = await db.get(table, { id: 'eq.' + id, select: 'file_name,mime,data' }); if (!a) throw new Error('المرفق غير موجود');
    const bin = atob(a.data), u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
    const url = URL.createObjectURL(new Blob([u], { type: a.mime }));
    if (w) w.location = url; else location.href = url;
  } catch (er) { if (w) w.close(); toast(er.message); }
}
