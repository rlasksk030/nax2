const CACHE_NAME = 'kream-price-v11';
const URLS_TO_CACHE = [
  './',
  './index.html',
  './styles.css',
  './app.js',
  './icon.svg',
  './manifest.json',
  'https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js'
];

// HTML/JS/CSS는 network-first로 항상 최신 버전 받기
const NETWORK_FIRST_PATTERNS = [
  /\.html$/,
  /\.js$/,
  /\.css$/,
  /manifest\.json$/,
  /\/$/
];

// Install event - cache essential files
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => {
        return cache.addAll(URLS_TO_CACHE).catch(err => {
          console.warn('Cache installation warning:', err);
          return cache.addAll(URLS_TO_CACHE.filter(url => !url.includes('cdn.jsdelivr.net')));
        });
      })
      .then(() => self.skipWaiting())
  );
});

// Activate event - clean up old caches
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(cacheNames => {
      return Promise.all(
        cacheNames.map(cacheName => {
          if (cacheName !== CACHE_NAME) {
            console.log('[SW] Deleting old cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

// Fetch event - network-first for app files, cache-first for others
self.addEventListener('fetch', event => {
  const { request } = event;
  const url = new URL(request.url);

  if (request.method !== 'GET') return;
  if (url.protocol === 'chrome-extension:') return;

  // Skip CORS proxies (always fetch fresh)
  if (url.hostname.includes('allorigins') ||
      url.hostname.includes('corsproxy') ||
      url.hostname.includes('codetabs') ||
      url.hostname.includes('cors.sh') ||
      url.hostname.includes('cors.eu') ||
      url.hostname.includes('thingproxy')) {
    return;
  }

  const isNetworkFirst = NETWORK_FIRST_PATTERNS.some(p => p.test(url.pathname));

  if (isNetworkFirst) {
    // Network-first strategy
    event.respondWith(
      fetch(request)
        .then(response => {
          if (response && response.status === 200) {
            const responseToCache = response.clone();
            caches.open(CACHE_NAME).then(cache => cache.put(request, responseToCache));
          }
          return response;
        })
        .catch(() => {
          return caches.match(request).then(cached => {
            if (cached) return cached;
            if (request.mode === 'navigate') return caches.match('./index.html');
            return new Response('Offline', { status: 503 });
          });
        })
    );
  } else {
    // Cache-first strategy for other resources
    event.respondWith(
      caches.match(request).then(response => {
        if (response) return response;
        return fetch(request).then(response => {
          if (!response || response.status !== 200 || response.type === 'error') return response;
          const responseToCache = response.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(request, responseToCache));
          return response;
        }).catch(() => {
          if (request.mode === 'navigate') return caches.match('./index.html');
          return new Response('Offline', { status: 503 });
        });
      })
    );
  }
});

// Handle messages from clients
self.addEventListener('message', event => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});
