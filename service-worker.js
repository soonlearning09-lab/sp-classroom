// SP - CLASSROOM Service Worker
// เปลี่ยน version เมื่อ deploy ใหม่ — เพื่อให้ user ได้ไฟล์ใหม่
const CACHE = 'sp-classroom-v4';

const APP_SHELL = [
  './',
  './index.html',
  './icon.svg',
  './manifest.json'
];

// Install — pre-cache app shell
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then(cache => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

// Activate — clear old caches
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(k => k !== CACHE).map(k => caches.delete(k))
      ))
      .then(() => self.clients.claim())
  );
});

// Fetch — strategy depends on resource type
self.addEventListener('fetch', (event) => {
  const req = event.request;
  const url = new URL(req.url);

  // 1) Supabase API — network only (data must be fresh, no cache)
  if (url.hostname.includes('supabase.co')) {
    return; // let browser handle natively
  }

  // 2) Non-GET — no cache
  if (req.method !== 'GET') return;

  // 3) Cache-first สำหรับ app shell + CDN (fonts, supabase JS, sortable)
  event.respondWith(
    caches.match(req).then(cached => {
      if (cached) return cached;
      return fetch(req).then(res => {
        // Cache external CDN responses (only successful ones)
        const isCdn = url.hostname.includes('jsdelivr.net')
                   || url.hostname.includes('googleapis.com')
                   || url.hostname.includes('gstatic.com');
        if (res.ok && isCdn) {
          const clone = res.clone();
          caches.open(CACHE).then(c => c.put(req, clone));
        }
        return res;
      }).catch(() => {
        // Offline fallback — return cached index.html for navigation requests
        if (req.mode === 'navigate') {
          return caches.match('./index.html');
        }
      });
    })
  );
});
