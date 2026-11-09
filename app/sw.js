// Waad service worker — makes the system installable and fast on repeat visits.
// It ONLY ever touches same-origin static assets and the app shell. It never caches API
// calls (Supabase is cross-origin in production; and we also skip /rest, /auth, /mock).
const V = 'waad-v1';
const SHELL = ['./', './index.html', './manifest.webmanifest', './icon-192.png', './icon-512.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(V).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener('activate', e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return;              // Supabase and any cross-origin: untouched
  if (/\/(rest|auth|mock|rpc)(\/|$)/.test(url.pathname)) return;   // same-origin API (test env): never cache data
  if (req.mode === 'navigate') {                            // the app HTML: network-first so new deploys land
    e.respondWith(fetch(req).then(r => { const cp = r.clone(); caches.open(V).then(c => c.put('./index.html', cp)); return r; }).catch(() => caches.match('./index.html')));
    return;
  }
  if (/\.(png|jpg|jpeg|webp|svg|ico|js|css|webmanifest|woff2?)$/.test(url.pathname)) {   // static assets: cache-first
    e.respondWith(caches.match(req).then(c => c || fetch(req).then(r => { if (r.ok) { const cp = r.clone(); caches.open(V).then(cc => cc.put(req, cp)); } return r; })));
  }
});
