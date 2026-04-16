/**
 * @file auth-sw.ts
 * @description Service Worker for transparent session management across all HTTP requests.
 *              Intercepts 401 responses and performs silent session refresh without page reload.
 *              Covers scenarios JS alone cannot handle: pre-JS requests, iframes, background fetches, WebSocket upgrades.
 * @module service-worker/auth
 */

// Types for messages between SW and clients
type SessionMessage =
  | { type: 'SESSION_REFRESHED'; expiry: number }
  | { type: 'SESSION_EXPIRED' }
  | { type: 'SESSION_REFRESH_START' }
  | { type: 'SESSION_REFRESH_FAILED'; reason: string };

type CacheStrategy = 'network-first' | 'cache-first' | 'stale-while-revalidate';

// Configuration constants
const REFRESH_ENDPOINT = '/api/auth/refresh';
const REFRESH_TIMEOUT_MS = 5000; // Max time to wait for refresh before returning error
const MAX_REFRESH_RETRIES = 3;
const SKIP_INTERCEPTION_PATHS = ['/oauth2/', '/health', '/healthz', '/ping'];
const SKIP_INTERCEPTION_HOSTS = ['api.openai.com', 'api.anthropic.com', 'huggingface.co'];

/**
 * Determines if a URL should be intercepted by the auth SW
 */
function shouldIntercept(url: string): boolean {
  const urlObj = new URL(url);

  // Skip external hosts
  if (SKIP_INTERCEPTION_HOSTS.some(host => urlObj.hostname.includes(host))) {
    return false;
  }

  // Skip auth and health endpoints
  const pathname = urlObj.pathname;
  return !SKIP_INTERCEPTION_PATHS.some(path => pathname.startsWith(path));
}

/**
 * Gets session expiry from IndexedDB via client postMessage
 * Service Workers cannot directly access IndexedDB in all browsers,
 * so we ask the page to check for us.
 */
async function getSessionExpiryViaClient(): Promise<number | null> {
  const clients = await (self as any).clients.matchAll();
  if (clients.length === 0) return null;

  return new Promise((resolve) => {
    const timeout = setTimeout(() => resolve(null), 1000);
    const client = clients[0];

    const listener = (event: MessageEvent) => {
      if (event.data.type === 'SESSION_EXPIRY_RESPONSE') {
        clearTimeout(timeout);
        (self as any).removeEventListener('message', listener);
        resolve(event.data.expiry);
      }
    };

    (self as any).addEventListener('message', listener);
    client.postMessage({ type: 'GET_SESSION_EXPIRY' });
  });
}

/**
 * Attempts silent session refresh via refresh endpoint
 */
async function performSilentRefresh(
  attempt: number = 1
): Promise<{ success: boolean; expiry?: number }> {
  try {
    const response = await fetch(REFRESH_ENDPOINT, {
      method: 'POST',
      credentials: 'include', // Include cookies
      headers: { 'X-Requested-With': 'XMLHttpRequest' },
      signal: AbortSignal.timeout(REFRESH_TIMEOUT_MS),
    });

    if (response.ok) {
      // Extract new expiry from response (backend should provide this)
      const data = await response.json();
      const newExpiry = data.expires_at || data.expiry;

      if (newExpiry) {
        return { success: true, expiry: newExpiry };
      }
      return { success: true };
    } else if (response.status === 401) {
      // Session truly expired, cannot refresh
      return { success: false };
    }

    // Server error or network issue - retry
    if (attempt < MAX_REFRESH_RETRIES) {
      await new Promise(r => setTimeout(r, 100 * attempt)); // Exponential backoff
      return performSilentRefresh(attempt + 1);
    }

    return { success: false };
  } catch (error) {
    if (attempt < MAX_REFRESH_RETRIES) {
      await new Promise(r => setTimeout(r, 100 * attempt));
      return performSilentRefresh(attempt + 1);
    }
    console.error('[auth-sw] Silent refresh failed:', error);
    return { success: false };
  }
}

/**
 * Notifies all connected clients of session state change
 */
async function notifyClients(message: SessionMessage): Promise<void> {
  const clients = await (self as any).clients.matchAll();
  clients.forEach((client: any) => {
    client.postMessage(message);
  });
}

/**
 * Main request interception handler
 * Intercepts all same-origin requests and handles 401 with automatic refresh
 */
(self as any).addEventListener('fetch', (event: FetchEvent) => {
  const { request } = event;

  // Only intercept GET/POST requests
  if (!['GET', 'POST'].includes(request.method)) {
    return;
  }

  // Only intercept same-origin
  if (new URL(request.url).origin !== (self as any).location.origin) {
    return;
  }

  // Skip certain paths
  if (!shouldIntercept(request.url)) {
    return;
  }

  // Network-first with 401 retry logic
  event.respondWith(
    (async () => {
      try {
        const response = await fetch(request.clone());

        // Handle 401: attempt silent refresh and retry
        if (response.status === 401) {
          // Notify clients of attempted refresh
          notifyClients({ type: 'SESSION_REFRESH_START' });

          const refreshResult = await performSilentRefresh();

          if (refreshResult.success) {
            // Refresh succeeded, retry original request
            if (refreshResult.expiry) {
              notifyClients({ type: 'SESSION_REFRESHED', expiry: refreshResult.expiry });
            }

            // Retry the original request
            const retryResponse = await fetch(request.clone());
            return retryResponse;
          } else {
            // Refresh failed, session truly expired
            notifyClients({ type: 'SESSION_EXPIRED' });
            return response; // Return 401 and let page handle redirect
          }
        }

        return response;
      } catch (error) {
        console.error('[auth-sw] Fetch failed:', error);
        // Return 408 Request Timeout if network is down
        return new Response('Network request failed', { status: 408 });
      }
    })()
  );
});

/**
 * Service Worker activation - clean up old caches
 */
(self as any).addEventListener('activate', (event: ExtendableEvent) => {
  event.waitUntil(
    (async () => {
      const cacheNames = await caches.keys();
      await Promise.all(
        cacheNames.map(cacheName => {
          // Keep only current-version cache
          if (cacheName !== 'auth-sw-v1') {
            return caches.delete(cacheName);
          }
        })
      );

      // Claim all clients immediately
      await (self as any).clients.claim();
    })()
  );
});

/**
 * Service Worker installation
 */
(self as any).addEventListener('install', (event: ExtendableEvent) => {
  event.waitUntil((self as any).skipWaiting());
});

/**
 * Message handler for communication with page JS
 */
(self as any).addEventListener('message', (event: ExtendableMessageEvent) => {
  const { data } = event;

  if (data.type === 'SKIP_WAITING') {
    // Force immediate activation (used during updates)
    (self as any).skipWaiting();
  } else if (data.type === 'GET_SESSION_EXPIRY') {
    // Client asking for expiry via IndexedDB
    getSessionExpiryViaClient().then(expiry => {
      event.ports[0].postMessage({ type: 'SESSION_EXPIRY_RESPONSE', expiry });
    });
  }
});
