/**
 * Client-side session keepalive scheduler.
 * Reads JS-accessible _session_expires cookie and proactively refreshes before expiry.
 * 
 * @example
 * ```typescript
 * import { initSessionKeepalive } from '@/session-keepalive';
 * 
 * // In main app initialization
 * initSessionKeepalive({
 *   refreshThresholdMs: 5 * 60 * 1000, // refresh if < 5 min left
 *   refreshEndpoint: '/oauth2/userinfo',
 *   maxRetries: 3,
 *   retryBackoffMs: 1000,
 * });
 * ```
 */

export interface SessionKeepaliveConfig {
  /** Milliseconds before expiry to trigger refresh (default: 5 min) */
  refreshThresholdMs?: number;
  /** Endpoint to hit for silent refresh (default: /oauth2/userinfo) */
  refreshEndpoint?: string;
  /** Max retry attempts on network failure (default: 3) */
  maxRetries?: number;
  /** Initial backoff milliseconds (default: 1000) */
  retryBackoffMs?: number;
  /** Max backoff milliseconds (default: 30000) */
  maxBackoffMs?: number;
  /** Enable debug logging to console (default: false) */
  debug?: boolean;
}

export interface SessionKeepaliveMetrics {
  refresh_total: number;
  refresh_success: number;
  refresh_failure: number;
  visibility_check_total: number;
}

const COOKIE_NAME = "_session_expires";
const DEFAULT_CONFIG: Required<SessionKeepaliveConfig> = {
  refreshThresholdMs: 5 * 60 * 1000, // 5 minutes
  refreshEndpoint: "/oauth2/userinfo",
  maxRetries: 3,
  retryBackoffMs: 1000,
  maxBackoffMs: 30000,
  debug: false,
};

let config: Required<SessionKeepaliveConfig> = DEFAULT_CONFIG;
let metrics: SessionKeepaliveMetrics = {
  refresh_total: 0,
  refresh_success: 0,
  refresh_failure: 0,
  visibility_check_total: 0,
};
let refreshTimeoutId: NodeJS.Timeout | null = null;

/**
 * Read session expiry from _session_expires cookie.
 * Returns Unix timestamp in milliseconds, or null if not found.
 */
export function getSessionExpiry(): number | null {
  if (typeof document === "undefined") {
    return null; // SSR environment
  }

  const match = document.cookie.match(new RegExp(`(?:^|; )${COOKIE_NAME}=(\\d+)(?:;|$)`));
  if (!match) {
    return null;
  }

  const unixSecondsStr = match[1];
  const unixSeconds = parseInt(unixSecondsStr, 10);

  if (isNaN(unixSeconds)) {
    logDebug("Invalid session expiry cookie value:", unixSecondsStr);
    return null;
  }

  return unixSeconds * 1000; // Convert to milliseconds
}

/**
 * Check if session is expired based on _session_expires cookie.
 */
export function isSessionExpired(): boolean {
  const expiryMs = getSessionExpiry();
  if (expiryMs === null) {
    return false; // No cookie, assume active
  }
  return expiryMs <= Date.now();
}

/**
 * Check if session is close to expiry (within threshold).
 */
export function isSessionExpiringSoon(): boolean {
  const expiryMs = getSessionExpiry();
  if (expiryMs === null) {
    return false;
  }
  const msUntilExpiry = expiryMs - Date.now();
  return msUntilExpiry > 0 && msUntilExpiry <= config.refreshThresholdMs;
}

/**
 * Get milliseconds until session expiry.
 * Returns null if no session or already expired.
 */
export function msUntilExpiry(): number | null {
  const expiryMs = getSessionExpiry();
  if (expiryMs === null) {
    return null;
  }
  const ms = expiryMs - Date.now();
  return ms > 0 ? ms : null;
}

/**
 * Perform silent session refresh by hitting the refresh endpoint.
 * Uses exponential backoff on failure.
 */
async function doSilentRefresh(retryCount = 0): Promise<boolean> {
  try {
    logDebug(`Attempting silent refresh (attempt ${retryCount + 1}/${config.maxRetries + 1})`);

    const response = await fetch(config.refreshEndpoint, {
      method: "GET",
      credentials: "same-origin", // Include cookies
      cache: "no-store",
      headers: {
        Accept: "application/json",
      },
    });

    metrics.refresh_total++;

    // 200-299 = success; any other 2xx or non-2xx is a retry/failure
    if (response.ok) {
      logDebug("Silent refresh succeeded");
      metrics.refresh_success++;

      // Schedule next refresh
      scheduleNextRefresh();
      return true;
    }

    // 401 = session actually expired (backend revoked)
    if (response.status === 401) {
      logDebug("Session revoked by backend (401); allowing natural re-auth redirect");
      metrics.refresh_failure++;
      return false;
    }

    // Other failures (5xx, network, etc) = retry with backoff
    throw new Error(`Refresh endpoint returned ${response.status}`);
  } catch (error) {
    logDebug("Silent refresh failed:", error);

    // Retry with exponential backoff
    if (retryCount < config.maxRetries) {
      const backoffMs = Math.min(
        config.retryBackoffMs * Math.pow(2, retryCount),
        config.maxBackoffMs
      );
      logDebug(`Retrying after ${backoffMs}ms...`);

      await new Promise((resolve) => setTimeout(resolve, backoffMs));
      return doSilentRefresh(retryCount + 1);
    }

    // All retries exhausted
    logDebug("All refresh retries exhausted");
    metrics.refresh_failure++;
    return false;
  }
}

/**
 * Schedule the next refresh based on current session expiry.
 * Called after successful refresh and on page load.
 */
export function scheduleNextRefresh(): void {
  // Clear any pending timeout
  if (refreshTimeoutId !== null) {
    clearTimeout(refreshTimeoutId);
    refreshTimeoutId = null;
  }

  const expiryMs = getSessionExpiry();
  if (expiryMs === null) {
    logDebug("No session expiry cookie; skipping schedule");
    return;
  }

  const now = Date.now();
  const msUntilExpiry = expiryMs - now;

  if (msUntilExpiry <= 0) {
    logDebug("Session already expired or about to expire; not scheduling");
    return;
  }

  // Schedule refresh to occur threshold_ms before expiry
  const msUntilRefresh = msUntilExpiry - config.refreshThresholdMs;

  if (msUntilRefresh <= 0) {
    // Session expires within threshold; refresh immediately
    logDebug("Session expires within threshold; refreshing immediately");
    doSilentRefresh();
  } else {
    // Schedule for the future
    logDebug(
      `Scheduling next refresh in ${msUntilRefresh}ms (session expires in ${msUntilExpiry}ms)`
    );
    refreshTimeoutId = setTimeout(() => {
      logDebug("Refresh timeout triggered");
      refreshTimeoutId = null;
      doSilentRefresh();
    }, msUntilRefresh);
  }
}

/**
 * Handle page visibility changes.
 * Re-check session expiry when user returns to tab.
 */
function onVisibilityChange(): void {
  if (typeof document === "undefined") {
    return;
  }

  metrics.visibility_check_total++;

  if (document.visibilityState === "visible") {
    logDebug("Page became visible; re-checking session expiry");

    // Check if session is now close to expiry and reschedule if needed
    if (isSessionExpiringSoon()) {
      logDebug("Session expiring soon; triggering immediate refresh");
      doSilentRefresh();
    } else if (isSessionExpired()) {
      logDebug("Session expired while page was hidden; allowing redirect");
      // Don't refresh; let natural redirect happen on next action
    } else {
      // Re-arm scheduler
      scheduleNextRefresh();
    }
  }
}

/**
 * Initialize session keepalive scheduler.
 * Sets up refresh timers and event listeners.
 */
export function initSessionKeepalive(userConfig?: Partial<SessionKeepaliveConfig>): void {
  if (typeof document === "undefined") {
    return; // SSR environment
  }

  // Merge config
  config = { ...DEFAULT_CONFIG, ...userConfig };
  logDebug("Initialized with config:", config);

  // Initial schedule
  scheduleNextRefresh();

  // Listen for visibility changes
  document.addEventListener("visibilitychange", onVisibilityChange);

  logDebug("Session keepalive initialized");
}

/**
 * Cleanup: clear timers and remove listeners.
 */
export function destroySessionKeepalive(): void {
  if (typeof document === "undefined") {
    return;
  }

  if (refreshTimeoutId !== null) {
    clearTimeout(refreshTimeoutId);
    refreshTimeoutId = null;
  }

  document.removeEventListener("visibilitychange", onVisibilityChange);
  logDebug("Session keepalive destroyed");
}

/**
 * Get current metrics.
 */
export function getMetrics(): Readonly<SessionKeepaliveMetrics> {
  return { ...metrics };
}

/**
 * Reset metrics (for testing).
 */
export function resetMetrics(): void {
  metrics = {
    refresh_total: 0,
    refresh_success: 0,
    refresh_failure: 0,
    visibility_check_total: 0,
  };
}

/**
 * Helper: debug logging.
 */
function logDebug(...args: unknown[]): void {
  if (config.debug) {
    console.log("[SessionKeepalive]", ...args);
  }
}
