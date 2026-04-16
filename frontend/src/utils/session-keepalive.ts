/**
 * session-keepalive.ts
 * Proactive client-side session refresh via expiry-hint companion cookie
 * Part of Phase 2 Session Self-Healing (#333)
 */

const EXPIRE_COOKIE_NAME = '_session_expires';
const REFRESH_THRESHOLD_MS = 5 * 60 * 1000; // 5 minutes before expiry
const MIN_REFRESH_INTERVAL_MS = 30 * 1000;  // Don't refresh more than once every 30s
const REFRESH_ENDPOINT = '/oauth2/userinfo';

let refreshTimer: ReturnType<typeof setTimeout> | null = null;
let lastRefreshTime = 0;

/**
 * Parses the _session_expires cookie to get the expiry timestamp (Unix epoch seconds)
 */
export function getSessionExpiry(): number | null {
  if (typeof document === 'undefined') return null;
  const match = document.cookie.match(new RegExp('(^| )' + EXPIRE_COOKIE_NAME + '=([^;]+)'));
  if (match) {
    const val = parseInt(match[2], 10);
    return isNaN(val) ? null : val * 1000; // Convert to ms
  }
  return null;
}

/**
 * Triggers a silent refresh by hitting an authenticated endpoint.
 * oauth2-proxy will rotate the session cookie and the companion expiry cookie.
 */
export async function doSilentRefresh(): Promise<boolean> {
  const now = Date.now();
  if (now - lastRefreshTime < MIN_REFRESH_INTERVAL_MS) {
    console.debug('[Session] Skipping refresh: too soon since last attempt');
    return true;
  }

  try {
    console.debug('[Session] Initiating proactive refresh...');
    const response = await fetch(REFRESH_ENDPOINT, { 
      credentials: 'same-origin', 
      cache: 'no-store' 
    });
    
    if (response.ok) {
      lastRefreshTime = Date.now();
      console.debug('[Session] Proactive refresh successful');
      scheduleRefresh(); // Re-arm timer with new expiry
      return true;
    } else if (response.status === 401) {
      console.warn('[Session] Proactive refresh failed: Unauthenticated');
      // Do NOT redirect, let the next interaction handle it or 
      // trigger an event for the UI to show a "Session Expired" banner
      return false;
    }
  } catch (error) {
    console.error('[Session] Error during proactive refresh:', error);
  }
  return false;
}

/**
 * Calculates time until next refresh and schedules a timer
 */
export function scheduleRefresh(): void {
  if (refreshTimer) {
    clearTimeout(refreshTimer);
    refreshTimer = null;
  }

  const exp = getSessionExpiry();
  if (!exp) {
    console.debug('[Session] No expiry hint found; proactive refresh disabled');
    return;
  }

  const now = Date.now();
  const timeUntilRefresh = (exp - now) - REFRESH_THRESHOLD_MS;

  if (timeUntilRefresh <= 0) {
    console.debug('[Session] Expiry near or passed, refreshing now');
    doSilentRefresh();
  } else {
    console.debug(`[Session] Scheduling refresh in ${Math.round(timeUntilRefresh / 1000)}s`);
    refreshTimer = setTimeout(doSilentRefresh, timeUntilRefresh);
  }
}

/**
 * Initializes the session keepalive logic
 */
export function initSessionKeepalive(): void {
  if (typeof window === 'undefined') return;

  // 1. Initial schedule
  scheduleRefresh();

  // 2. Refresh when user returns to the tab (tab focus/visibility change)
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      console.debug('[Session] Tab became visible, checking expiry...');
      scheduleRefresh();
    }
  });

  // 3. Periodic sanity check every 1 minute
  setInterval(scheduleRefresh, 60 * 1000);
}
