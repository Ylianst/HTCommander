// sw.js
const CACHE_NAME = 'htcommander-cache-v1'; // Change version to update cache (e.g., v1.1, v2)
const URLS_TO_CACHE = [
    'htcommander.html',
    // If you add external CSS or JS files later, add their paths here:
    // 'css/style.css',
    // 'js/app.js',
    // Add paths to your icons if you want them aggressively cached by the SW too
    'icons/icon-192x192.png',
    'icons/icon-512x512.png'
];

// Install event: Cache core assets
self.addEventListener('install', event => {
    console.log('[SW] Install event');
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then(cache => {
                console.log('[SW] Caching app shell');
                // Use { cache: 'reload' } for requests to ensure fresh resources during install
                // for resources that might change and are critical for the app version
                const cachePromises = URLS_TO_CACHE.map(urlToCache => {
                    return cache.add(new Request(urlToCache, { cache: 'reload' }));
                });
                return Promise.all(cachePromises);
            })
            .then(() => {
                console.log('[SW] Skip waiting on install');
                return self.skipWaiting(); // Activate the new service worker immediately
            })
            .catch(error => {
                console.error('[SW] Caching failed during install:', error);
            })
    );
});

// Activate event: Clean up old caches
self.addEventListener('activate', event => {
    console.log('[SW] Activate event');
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
        }).then(() => {
            console.log('[SW] Claiming clients');
            return self.clients.claim(); // Take control of open clients/pages
        })
    );
});

// Fetch event: Serve cached content when offline, update when online
self.addEventListener('fetch', event => {
    // For navigation requests (e.g., loading the HTML page itself)
    if (event.request.mode === 'navigate') {
        event.respondWith(
            fetch(event.request) // Try network first
                .then(networkResponse => {
                    // If successful, clone it, cache it, and return it
                    if (networkResponse.ok) {
                        const responseToCache = networkResponse.clone();
                        caches.open(CACHE_NAME).then(cache => {
                            cache.put(event.request, responseToCache);
                        });
                    }
                    return networkResponse;
                })
                .catch(() => {
                    // If network fails, try to serve from cache
                    console.log(`[SW] Network failed for ${event.request.url}, serving from cache.`);
                    return caches.match(event.request)
                        .then(cachedResponse => {
                            // Fallback to the main cached page if a specific navigation request isn't found
                            // This helps if the user tries to navigate to a sub-page that isn't explicitly cached but ble_radio.html is
                            return cachedResponse || caches.match('ble_radio.html');
                        });
                })
        );
        return;
    }

    // For other requests (like icons, or future CSS/JS if they become external)
    // Use a cache-first strategy.
    event.respondWith(
        caches.match(event.request)
            .then(cachedResponse => {
                if (cachedResponse) {
                    return cachedResponse; // Serve from cache
                }
                // Not in cache, fetch from network, then cache it
                return fetch(event.request).then(networkResponse => {
                    if (networkResponse.ok) {
                        const responseToCache = networkResponse.clone();
                        caches.open(CACHE_NAME).then(cache => {
                            cache.put(event.request, responseToCache);
                        });
                    }
                    return networkResponse;
                });
            })
    );
});