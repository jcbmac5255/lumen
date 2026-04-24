// Lumen service worker — caches static assets for fast repeat loads.
// Bump CACHE_VERSION when shipping CSS/JS/image changes to bust old caches.

const CACHE_VERSION = "lumen-v8";
const PRECACHE_URLS = [
  "/manifest",
  "/logo-pwa.png",
  "/apple-touch-icon.png",
  "/favicon-32x32.png",
  "/favicon-16x16.png"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then((cache) => cache.addAll(PRECACHE_URLS))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((k) => k !== CACHE_VERSION).map((k) => caches.delete(k))
      )
    ).then(() => self.clients.claim())
  );
});

function isCacheableStatic(url) {
  // Fingerprinted assets (Propshaft) and fixed public files
  return /\/assets\/.+-[a-f0-9]{8,}\.(css|js|png|jpg|jpeg|gif|svg|woff2?|ico)$/.test(url.pathname) ||
         /^\/(favicon|apple-touch-icon|logo-pwa)/.test(url.pathname);
}

self.addEventListener("fetch", (event) => {
  const request = event.request;
  if (request.method !== "GET") return;

  const url = new URL(request.url);

  // Only cache same-origin requests
  if (url.origin !== self.location.origin) return;

  // Never cache Turbo streams, ActionCable, or API responses
  if (url.pathname.startsWith("/cable") ||
      url.pathname.startsWith("/api/") ||
      (request.headers.get("accept") || "").includes("turbo-stream")) {
    return;
  }

  // Cache-first for fingerprinted / static assets
  if (isCacheableStatic(url)) {
    event.respondWith(
      caches.match(request).then((cached) => {
        if (cached) return cached;
        return fetch(request).then((response) => {
          if (response.ok) {
            const clone = response.clone();
            caches.open(CACHE_VERSION).then((cache) => cache.put(request, clone));
          }
          return response;
        });
      })
    );
    return;
  }

  // Network-first for HTML navigations (falls back to cache if offline)
  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request).catch(() => caches.match(request))
    );
  }
});

// Push notifications — kept from the original stub for future use.
self.addEventListener("push", async (event) => {
  if (!event.data) return;
  try {
    const { title, options } = await event.data.json();
    event.waitUntil(self.registration.showNotification(title, options));
  } catch (_e) {}
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const path = event.notification.data?.path || "/";
  event.waitUntil(
    clients.matchAll({ type: "window" }).then((list) => {
      for (const client of list) {
        if (new URL(client.url).pathname === path && "focus" in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) return clients.openWindow(path);
    })
  );
});
