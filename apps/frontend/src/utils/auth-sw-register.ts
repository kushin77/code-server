/**
 * @file auth-sw-register.ts
 * @description Service Worker registration and client-side integration.
 *              Handles SW lifecycle, message passing, and IndexedDB coordination.
 * @module service-worker/registration
 */

import { storeSessionExpiry, getSessionExpiry, isSessionValid } from './session-indexeddb-store';

// Types
export interface ServiceWorkerHealth {
  isActive: boolean;
  registrationTime: number;
  updateCheckTime?: number;
  lastRefreshTime?: number;
}

// Module state
let swRegistration: ServiceWorkerRegistration | null = null;
let swHealth: ServiceWorkerHealth = {
  isActive: false,
  registrationTime: 0,
};

// Metrics
const metrics = {
  sw_registration_attempts: 0,
  sw_registration_success: 0,
  sw_registration_failures: 0,
  sw_message_sent: 0,
  sw_message_received: 0,
  sw_session_refreshed: 0,
  sw_session_expired: 0,
  sw_refresh_failed: 0,
};

/**
 * Registers the Service Worker on page load
 * Gracefully degrades if registration fails or SW not supported
 */
export async function registerAuthServiceWorker(): Promise<void> {
  // Check if SW is supported
  if (!('serviceWorker' in navigator)) {
    console.warn('[auth-sw-register] Service Workers not supported, falling back to page JS only');
    return;
  }

  // Skip registration in private browsing mode (typically fails silently)
  if (navigator.webdriver || !navigator.serviceWorker) {
    console.info('[auth-sw-register] Private browsing or restricted mode detected, skipping SW');
    return;
  }

  try {
    metrics.sw_registration_attempts++;
    swHealth.registrationTime = Date.now();

    // Register the SW
    swRegistration = await navigator.serviceWorker.register('/auth-sw.js', {
      scope: '/',
      updateViaCache: 'none', // Cache-bust on every check
    });

    metrics.sw_registration_success++;
    swHealth.isActive = true;

    console.info(
      '[auth-sw-register] SW registered successfully',
      `scope: ${swRegistration.scope}`
    );

    // Set up message handlers
    setupMessageHandlers();

    // Check for updates periodically (every 1 hour)
    setInterval(
      async () => {
        try {
          swHealth.updateCheckTime = Date.now();
          await swRegistration?.update();
        } catch (error) {
          console.warn('[auth-sw-register] Failed to check for SW updates:', error);
        }
      },
      60 * 60 * 1000
    );

    // Report registration success via metrics
    reportMetric('sw_registration_success', 1);
  } catch (error) {
    metrics.sw_registration_failures++;
    swHealth.isActive = false;

    console.error('[auth-sw-register] Failed to register Service Worker:', error);
    reportMetric('sw_registration_failures', 1);

    // Graceful fallback: page JS session-keepalive will continue to work
  }
}

/**
 * Sets up two-way message communication between page and SW
 */
function setupMessageHandlers(): void {
  if (!navigator.serviceWorker.controller) {
    // SW not yet active, wait for activation
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      setupMessageHandlers();
    });
    return;
  }

  /**
   * Listen for messages from SW
   */
  navigator.serviceWorker.addEventListener('message', async (event: ExtendableMessageEvent) => {
    const { data } = event;
    metrics.sw_message_received++;

    switch (data.type) {
      case 'SESSION_REFRESHED':
        console.info('[auth-sw-register] SW notified: session refreshed', {
          newExpiry: new Date(data.expiry).toISOString(),
        });
        // Update IndexedDB with new expiry
        await storeSessionExpiry(data.expiry);
        metrics.sw_session_refreshed++;
        reportMetric('sw_session_refreshed', 1);
        break;

      case 'SESSION_EXPIRED':
        console.warn('[auth-sw-register] SW notified: session expired');
        metrics.sw_session_expired++;
        reportMetric('sw_session_expired', 1);
        // Trigger redirect to login (will be handled by page or next request)
        showSessionExpiredOverlay();
        break;

      case 'SESSION_REFRESH_START':
        console.debug('[auth-sw-register] SW: refresh in progress');
        break;

      case 'SESSION_REFRESH_FAILED':
        console.error('[auth-sw-register] SW: refresh failed -', data.reason);
        metrics.sw_refresh_failed++;
        reportMetric('sw_refresh_failed', 1);
        break;

      case 'GET_SESSION_EXPIRY':
        // SW asking for expiry via IndexedDB
        const expiry = await getSessionExpiry();
        event.ports[0].postMessage({ type: 'SESSION_EXPIRY_RESPONSE', expiry });
        break;
    }
  });

  /**
   * When session expiry is updated in IndexedDB (from session-keepalive #333),
   * notify the SW so it can schedule refresh appropriately
   */
  setupStorageObserver();
}

/**
 * Observer for IndexedDB changes (in case other tabs update session)
 */
function setupStorageObserver(): void {
  window.addEventListener('storage', async (event: StorageEvent) => {
    // This handles localStorage changes from other tabs
    // For IndexedDB, we'd need a different mechanism

    if (event.key === '_session_expires') {
      // Another tab updated the expiry
      const newExpiry = event.newValue ? parseInt(event.newValue, 10) : null;
      if (newExpiry) {
        await storeSessionExpiry(newExpiry);
        // Notify SW
        sendMessageToSW({
          type: 'SESSION_EXPIRY_UPDATED',
          expiry: newExpiry,
        });
      }
    }
  });
}

/**
 * Sends a message to the Service Worker
 */
export function sendMessageToSW(message: Record<string, any>): void {
  if (!navigator.serviceWorker.controller) {
    console.warn('[auth-sw-register] SW not active, message not sent');
    return;
  }

  try {
    metrics.sw_message_sent++;
    navigator.serviceWorker.controller.postMessage(message);
  } catch (error) {
    console.error('[auth-sw-register] Failed to send message to SW:', error);
  }
}

/**
 * Shows a non-intrusive overlay when session expires
 * (only on non-leader tabs; leader tab redirects to login)
 */
function showSessionExpiredOverlay(): void {
  // Check if already shown
  if (document.getElementById('session-expired-overlay')) {
    return;
  }

  const overlay = document.createElement('div');
  overlay.id = 'session-expired-overlay';
  overlay.style.cssText = `
    position: fixed;
    bottom: 20px;
    right: 20px;
    background: #f8d7da;
    border: 1px solid #f5c6cb;
    border-radius: 4px;
    padding: 16px;
    z-index: 9999;
    max-width: 400px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.15);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  `;

  const message = document.createElement('p');
  message.style.cssText = 'margin: 0 0 12px 0; color: #721c24; font-size: 14px;';
  message.textContent = 'Your session has expired. Refresh the page to continue.';

  const closeBtn = document.createElement('button');
  closeBtn.style.cssText = `
    background: #721c24;
    color: white;
    border: none;
    border-radius: 2px;
    padding: 6px 12px;
    cursor: pointer;
    font-size: 12px;
  `;
  closeBtn.textContent = 'Refresh';
  closeBtn.onclick = () => window.location.reload();

  overlay.appendChild(message);
  overlay.appendChild(closeBtn);
  document.body.appendChild(overlay);

  // Auto-dismiss after 10 seconds
  setTimeout(() => {
    overlay.remove();
  }, 10000);
}

/**
 * Gets current SW health status
 */
export function getServiceWorkerHealth(): ServiceWorkerHealth {
  return { ...swHealth };
}

/**
 * Reports metrics to backend (via Prometheus pushgateway or similar)
 */
function reportMetric(name: string, value: number): void {
  // Send to metrics endpoint (could be Prometheus push gateway)
  // For now, just log to console in dev
  if (process.env.NODE_ENV === 'development') {
    console.debug(`[metrics] ${name}: ${value}`);
  }

  // In production, could send to: /api/metrics/push with Prometheus format
  // Example:
  // fetch('/api/metrics/push', {
  //   method: 'POST',
  //   body: `service_worker_${name} ${value}\n`,
  // }).catch(err => console.warn('Metrics push failed:', err));
}

/**
 * Forces SW update (useful during deployment)
 */
export async function forceServiceWorkerUpdate(): Promise<void> {
  if (!swRegistration) return;

  try {
    await swRegistration.update();

    if (swRegistration.waiting) {
      // Tell waiting SW to take control
      swRegistration.waiting.postMessage({ type: 'SKIP_WAITING' });

      // Monitor for activation
      const onControllerChange = () => {
        navigator.serviceWorker.removeEventListener('controllerchange', onControllerChange);
        console.info('[auth-sw-register] SW updated and activated');
        reportMetric('sw_update_activated', 1);
      };
      navigator.serviceWorker.addEventListener('controllerchange', onControllerChange);
    }
  } catch (error) {
    console.error('[auth-sw-register] Failed to update SW:', error);
    reportMetric('sw_update_failed', 1);
  }
}

/**
 * Unregisters the Service Worker (for debugging/cleanup)
 */
export async function unregisterAuthServiceWorker(): Promise<void> {
  if (!swRegistration) return;

  try {
    const success = await swRegistration.unregister();
    if (success) {
      swHealth.isActive = false;
      console.info('[auth-sw-register] SW unregistered');
    }
  } catch (error) {
    console.error('[auth-sw-register] Failed to unregister SW:', error);
  }
}

/**
 * Initialize on module load
 * Should be called early in app initialization (before main app render)
 */
if (typeof window !== 'undefined') {
  // Defer registration until page is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      registerAuthServiceWorker().catch(err =>
        console.error('[auth-sw-register] Initialization failed:', err)
      );
    });
  } else {
    registerAuthServiceWorker().catch(err =>
      console.error('[auth-sw-register] Initialization failed:', err)
    );
  }
}
