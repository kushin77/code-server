/**
 * session-keepalive.ts
 * Proactive client-side session refresh via expiry-hint companion cookie
 * Part of Phase 2 Session Self-Healing (#333)
 * 
 * Integrated with session-sync (#334) for multi-tab coordination:
 * - Uses distributed lock to prevent thundering herd
 * - Broadcasts successful refresh to other tabs
 * - Coordinates re-authentication via leader election
 */

import {
  acquireRefreshLock,
  releaseRefreshLock,
  broadcastSessionRefresh,
  broadcastSessionExpiry,
  isLeader,
} from './session-sync';

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
 * 
 * Coordinates with other tabs via session-sync:
 * 1. Attempts to acquire distributed refresh lock (prevents thundering herd)
 * 2. If lock acquired, performs refresh and broadcasts success
 * 3. If lock not acquired, waits for broadcast from lock holder
 */
export async function doSilentRefresh(): Promise<boolean> {
  const now = Date.now();
  if (now - lastRefreshTime < MIN_REFRESH_INTERVAL_MS) {
    console.debug('[Session] Skipping refresh: too soon since last attempt');
    return true;
  }

  // Attempt to acquire refresh lock (prevents multiple tabs refreshing simultaneously)
  const lockAcquired = acquireRefreshLock();
  
  if (!lockAcquired) {
    console.debug('[Session] Another tab is refreshing; waiting for broadcast');
    // Let the other tab refresh and broadcast the new expiry
    return true;
  }

  try {
    console.debug('[Session] Lock acquired; initiating proactive refresh...');
    const response = await fetch(REFRESH_ENDPOINT, { 
      credentials: 'same-origin', 
      cache: 'no-store' 
    });
    
    if (response.ok) {
      lastRefreshTime = Date.now();
      const newExpiry = getSessionExpiry();
      
      console.debug('[Session] Proactive refresh successful');
      
      // Broadcast success to other tabs so they don't refresh again
      if (newExpiry) {
        broadcastSessionRefresh(newExpiry);
      }
      
      scheduleRefresh(); // Re-arm timer with new expiry
      return true;
    } else if (response.status === 401) {
      console.warn('[Session] Proactive refresh failed: Unauthenticated (401)');
      
      // Broadcast session expiry to coordinate re-authentication
      broadcastSessionExpiry();
      
      // Only leader tab redirects to login (prevent multiple redirects)
      if (isLeader()) {
        console.warn('[Session] Leader tab: redirecting to login...');
        setTimeout(() => {
          window.location.href = '/login?reason=session-expired';
        }, 100);
      } else {
        console.debug('[Session] Follower tab: leader will handle redirect');
      }
      
      return false;
    }
  } catch (error) {
    console.error('[Session] Error during proactive refresh:', error);
    releaseRefreshLock(); // Release lock on error so other tabs can retry
    return false;
  } finally {
    releaseRefreshLock();
  }
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

  // 4. Listen for broadcasts from other tabs (session-sync integration)
  if (typeof BroadcastChannel !== 'undefined') {
    try {
      const syncChannel = new BroadcastChannel('code-server-session');
      
      syncChannel.addEventListener('message', (event) => {
        const msg = event.data;
        
        if (msg.type === 'SESSION_REFRESHED') {
          console.debug('[Session] Broadcast: Another tab refreshed; rescheduling timer');
          scheduleRefresh();
        } else if (msg.type === 'SESSION_EXPIRED') {
          console.debug('[Session] Broadcast: Session expired on another tab');
          // No action needed; doSilentRefresh will see 401 on next attempt
          // or this tab will detect expiry and call doSilentRefresh
        }
      });
      
      console.debug('[Session] Listening for multi-tab sync broadcasts');
    } catch (error) {
      console.debug('[Session] Failed to set up broadcast listener:', error);
      // Fall back to independent refresh
    }
  }
}

