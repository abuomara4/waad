'use strict';
/* ===== fingerprint / face unlock on this device (WebAuthn platform authenticator). Waad never receives the fingerprint or the face.
   It unlocks a sign-in already saved on the device; after signing out the password is needed again. ===== */
const BIO_IDLE = 15 * 60 * 1000;
const bioBytes = s => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
const bioText = b => btoa(String.fromCharCode(...new Uint8Array(b))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const bioRand = () => crypto.getRandomValues(new Uint8Array(32));
const bioMine = () => { const b = LS.get('waad.bio'); return b && S.session && S.session.user && b.uid === S.session.user.id ? b : null; };
const bioUnlocked = v => { try { if (v === undefined) return sessionStorage.getItem('waad.unlocked') === '1'; if (v) sessionStorage.setItem('waad.unlocked', '1'); else sessionStorage.removeItem('waad.unlocked'); } catch (e) {} return !!v; };
async function bioAvailable() { try { return !!(window.PublicKeyCredential && await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()); } catch (e) { return false; } }
async function bioEnable() {
  const u = S.session.user, c = await navigator.credentials.create({ publicKey: { challenge: bioRand(), rp: { name: 'Waad' }, user: { id: new TextEncoder().encode(u.id), name: u.email || u.id, displayName: (S.myEmp && S.myEmp.full_name) || u.email || 'Waad' },
    pubKeyCredParams: [{ type: 'public-key', alg: -7 }, { type: 'public-key', alg: -257 }], authenticatorSelection: { authenticatorAttachment: 'platform', userVerification: 'required', residentKey: 'discouraged' }, timeout: 60000, attestation: 'none' } });
  LS.set('waad.bio', { uid: u.id, id: bioText(c.rawId) }); bioUnlocked(true);
}
async function bioVerify(b) {
  const a = await navigator.credentials.get({ publicKey: { challenge: bioRand(), allowCredentials: [{ type: 'public-key', id: bioBytes(b.id) }], userVerification: 'required', timeout: 60000 } });
  if (!(new Uint8Array(a.response.authenticatorData)[32] & 4)) throw new Error('not verified');   // the device confirmed the person, not only its presence
}
/* called by boot(): true when the lock screen took over */
function bioGate() {
  const b = bioMine(); if (!b || bioUnlocked()) return false;
  $('#app').innerHTML = `<div class="auth"><div class="abox">${brand()}<div class="card" style="text-align:center"><h2>${esc(tr('افتح وعد'))}</h2><p class="muted small">${esc(tr('استخدم بصمتك أو وجهك أو قفل جهازك.'))}</p><div id="aerr"></div>
    <button class="btn pri full" id="bgo">${esc(tr('الدخول بالبصمة أو الوجه'))}</button><p class="small" style="margin:12px 0 0"><a href="#" id="bpw">${esc(tr('الدخول بكلمة المرور'))}</a></p></div></div></div>`;
  $('#bgo').onclick = () => busy($('#bgo'), async () => { try { await bioVerify(b); bioUnlocked(true); boot(); } catch (e) { showErr('#aerr', tr('لم يكتمل التحقق. حاول مرة أخرى أو ادخل بكلمة المرور.')); } });
  $('#bpw').onclick = async e => { e.preventDefault(); bioUnlocked(false); await authApi.signOut(); authView(); };
  return true;
}
async function bioMenu() {
  const m = $('#bioon'); if (!m || !await bioAvailable()) return; m.hidden = false;
  const draw = () => { $('span', m).textContent = tr(bioMine() ? 'إيقاف الدخول بالبصمة أو الوجه' : 'الدخول بالبصمة أو الوجه'); }; draw();
  m.onclick = async () => { $('#umenu').hidden = true; try { if (bioMine()) { LS.set('waad.bio', null); toast(tr('أُوقف')); } else { await bioEnable(); toast(tr('فُعّل على هذا الجهاز')); } draw(); } catch (e) { toast(tr('لم يكتمل التفعيل')); } };
  // offered once after signing in on a device that supports it
  if (!bioMine() && !LS.get('waad.bioasked') && !LS.get('waad.noremember')) { LS.set('waad.bioasked', 1); setTimeout(() => { if ($('#dlg').open) return; modal(tr('دخول أسرع'), `<p>${esc(tr('افتح وعد ببصمتك أو وجهك على هذا الجهاز. لا تصل بصمتك أو صورة وجهك إلى وعد.'))}</p>`, { ok: tr('تفعيل'), onOk: async () => { try { await bioEnable(); } catch (e) { throw new Error(tr('لم يكتمل التفعيل')); } toast(tr('فُعّل على هذا الجهاز')); draw(); } }); }, 1500); }
}
let bioHiddenAt = 0;
document.addEventListener('visibilitychange', () => { if (document.hidden) { bioHiddenAt = Date.now(); return; }
  if (bioHiddenAt && Date.now() - bioHiddenAt > BIO_IDLE && bioMine()) { bioUnlocked(false); boot(); } });
