/**
 * Multi-tab session synchronization with leader election.
 * Prevents thundering herd of refresh requests and keeps all tabs in sync.
 *
 * @example
 * ```typescript
 * import { initSessionSync, broadcastRefresh } from '@/utils/session-sync';
 *
 * // In app initialization:
 * initSessionSync();
 *
 * // After successful refresh in session-keepalive:
 * broadcastRefresh(newExpiryMs);
 * ```
 */
const DEFAULT_CONFIG = {
    channelName: "code-server-session",
    lockTtlMs: 10000,
    tabTimeoutMs: 60000,
    debug: false,
};
let config = DEFAULT_CONFIG;
let metrics = {
    broadcast_events_total: 0,
    broadcast_refreshed: 0,
    broadcast_expired: 0,
    broadcast_query: 0,
    leader_elections_total: 0,
    lock_acquisitions_total: 0,
    lock_acquisition_failures: 0,
};
// Generate unique tab ID
const MY_TAB_ID = typeof crypto !== "undefined" && crypto.randomUUID
    ? crypto.randomUUID()
    : `tab-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;
// BroadcastChannel reference (may be null on old browsers)
let channel = null;
// Registry of known tabs (for leader election)
const knownTabs = new Map();
// Local state
let localSessionExpiry = null;
/**
 * Get the localStorage key for the refresh lock.
 */
function getLockKey() {
    return `session_refresh_lock_${config.channelName}`;
}
/**
 * Get the localStorage key for tab registry.
 */
function getTabRegistryKey() {
    return `session_tabs_${config.channelName}`;
}
/**
 * Attempt to acquire the refresh lock.
 * Only one tab should hold the lock at a time.
 */
export function acquireRefreshLock() {
    try {
        const lockKey = getLockKey();
        const now = Date.now();
        const existing = localStorage.getItem(lockKey);
        if (existing) {
            const { ts, tabId } = JSON.parse(existing);
            const age = now - ts;
            // Lock still valid and held by different tab
            if (age < config.lockTtlMs && tabId !== MY_TAB_ID) {
                logDebug(`Lock held by tab ${tabId} (age: ${age}ms)`);
                metrics.lock_acquisition_failures++;
                return false;
            }
            // Lock expired or held by us; acquire
            if (age >= config.lockTtlMs) {
                logDebug("Lock expired; acquiring");
            }
        }
        // Acquire lock
        localStorage.setItem(lockKey, JSON.stringify({ ts: now, tabId: MY_TAB_ID }));
        metrics.lock_acquisitions_total++;
        logDebug("Lock acquired");
        return true;
    }
    catch (error) {
        // localStorage may not be available (private browsing, etc)
        logDebug("Failed to acquire lock:", error);
        metrics.lock_acquisition_failures++;
        return false;
    }
}
/**
 * Release the refresh lock.
 */
export function releaseRefreshLock() {
    try {
        const lockKey = getLockKey();
        localStorage.removeItem(lockKey);
        logDebug("Lock released");
    }
    catch (error) {
        logDebug("Failed to release lock:", error);
    }
}
/**
 * Broadcast session refresh to all other tabs.
 * Call this after a successful silent refresh.
 */
export function broadcastSessionRefresh(newExpiryMs) {
    if (!channel) {
        logDebug("BroadcastChannel not available; skipping broadcast");
        return;
    }
    localSessionExpiry = newExpiryMs;
    const message = {
        type: "SESSION_REFRESHED",
        expiry: Math.floor(newExpiryMs / 1000), // Convert to Unix seconds
        tabId: MY_TAB_ID,
        timestamp: Date.now(),
    };
    logDebug("Broadcasting SESSION_REFRESHED:", message);
    metrics.broadcast_events_total++;
    metrics.broadcast_refreshed++;
    channel.postMessage(message);
}
/**
 * Broadcast session expiry to all other tabs.
 * Call when session refresh fails permanently.
 */
export function broadcastSessionExpiry() {
    if (!channel) {
        logDebug("BroadcastChannel not available; skipping broadcast");
        return;
    }
    localSessionExpiry = null;
    const message = {
        type: "SESSION_EXPIRED",
        tabId: MY_TAB_ID,
        timestamp: Date.now(),
    };
    logDebug("Broadcasting SESSION_EXPIRED:", message);
    metrics.broadcast_events_total++;
    metrics.broadcast_expired++;
    channel.postMessage(message);
}
/**
 * Get the leader tab ID among known tabs.
 * The leader is the tab with the lowest ID (for determinism).
 */
function getLeaderTabId() {
    const tabIds = Array.from(knownTabs.keys());
    if (tabIds.length === 0) {
        return null;
    }
    tabIds.sort();
    return tabIds[0];
}
/**
 * Check if this tab is the leader.
 */
export function isLeader() {
    const leader = getLeaderTabId();
    return leader === MY_TAB_ID;
}
/**
 * Register this tab as active.
 */
function registerTab() {
    try {
        const now = Date.now();
        knownTabs.set(MY_TAB_ID, { lastSeen: now });
        // Persist to localStorage for crash recovery
        const registryKey = getTabRegistryKey();
        const registry = JSON.parse(localStorage.getItem(registryKey) || "{}");
        registry[MY_TAB_ID] = now;
        // Clean up old tabs
        Object.keys(registry).forEach((tabId) => {
            if (now - registry[tabId] > config.tabTimeoutMs) {
                delete registry[tabId];
                knownTabs.delete(tabId);
            }
        });
        localStorage.setItem(registryKey, JSON.stringify(registry));
    }
    catch (error) {
        logDebug("Failed to register tab:", error);
    }
}
/**
 * Handle incoming messages from other tabs.
 */
function onChannelMessage(event) {
    const msg = event.data;
    logDebug("Received message:", msg);
    metrics.broadcast_events_total++;
    // Track sender as active tab
    if ("tabId" in msg) {
        knownTabs.set(msg.tabId, { lastSeen: Date.now() });
    }
    switch (msg.type) {
        case "SESSION_REFRESHED": {
            metrics.broadcast_refreshed++;
            logDebug(`Tab ${msg.tabId} refreshed; new expiry: ${msg.expiry}`);
            // Update local expiry
            localSessionExpiry = msg.expiry * 1000;
            // Note: session-keepalive module should listen for this event if integrated
            break;
        }
        case "SESSION_EXPIRED": {
            metrics.broadcast_expired++;
            logDebug(`Tab ${msg.tabId} reported session expired`);
            localSessionExpiry = null;
            // Coordinate re-auth: only leader tab redirects
            break;
        }
        case "SESSION_QUERY": {
            metrics.broadcast_query++;
            logDebug(`Tab ${msg.tabId} querying session state`);
            // Respond with current expiry if available
            if (localSessionExpiry && channel) {
                const response = {
                    type: "SESSION_STATE",
                    expiry: Math.floor(localSessionExpiry / 1000),
                    tabId: MY_TAB_ID,
                    timestamp: Date.now(),
                };
                logDebug("Responding with SESSION_STATE:", response);
                channel.postMessage(response);
            }
            break;
        }
        case "SESSION_STATE": {
            logDebug(`Tab ${msg.tabId} provided session state: ${msg.expiry}`);
            localSessionExpiry = msg.expiry * 1000;
            break;
        }
    }
}
/**
 * Handle visibility changes (tab becomes foreground).
 */
function onVisibilityChange() {
    if (typeof document === "undefined") {
        return;
    }
    if (document.visibilityState === "visible") {
        logDebug("Tab became visible; registering as active");
        registerTab();
    }
}
/**
 * Initialize multi-tab session sync.
 * Sets up BroadcastChannel and leader election.
 */
export function initSessionSync(userConfig) {
    if (typeof window === "undefined") {
        return; // SSR environment
    }
    // Merge config
    config = { ...DEFAULT_CONFIG, ...userConfig };
    logDebug("Initialized with config:", config);
    // Check BroadcastChannel support
    if (typeof BroadcastChannel === "undefined") {
        logDebug("BroadcastChannel not available; multi-tab sync disabled");
        return;
    }
    // Create channel
    try {
        channel = new BroadcastChannel(config.channelName);
        channel.addEventListener("message", onChannelMessage);
        logDebug("BroadcastChannel created and listening");
    }
    catch (error) {
        logDebug("Failed to create BroadcastChannel:", error);
        return;
    }
    // Register this tab
    registerTab();
    // Listen for visibility changes
    if (typeof document !== "undefined") {
        document.addEventListener("visibilitychange", onVisibilityChange);
    }
    // Periodically re-register to stay in known tabs
    const registrationInterval = setInterval(() => {
        registerTab();
    }, config.tabTimeoutMs / 2);
    // Cleanup on page unload
    if (typeof window !== "undefined") {
        window.addEventListener("beforeunload", () => {
            clearInterval(registrationInterval);
            if (channel) {
                channel.close();
            }
        });
    }
    metrics.leader_elections_total++;
    logDebug(`Multi-tab sync initialized; this tab is ${isLeader() ? "LEADER" : "FOLLOWER"}`);
}
/**
 * Cleanup: close channel and remove listeners.
 */
export function destroySessionSync() {
    if (channel) {
        channel.close();
        channel = null;
    }
    if (typeof document !== "undefined") {
        document.removeEventListener("visibilitychange", onVisibilityChange);
    }
    logDebug("Session sync destroyed");
}
/**
 * Get current metrics.
 */
export function getMetrics() {
    return { ...metrics };
}
/**
 * Reset metrics (for testing).
 */
export function resetMetrics() {
    metrics = {
        broadcast_events_total: 0,
        broadcast_refreshed: 0,
        broadcast_expired: 0,
        broadcast_query: 0,
        leader_elections_total: 0,
        lock_acquisitions_total: 0,
        lock_acquisition_failures: 0,
    };
}
/**
 * Get the current tab ID (for testing/debugging).
 */
export function getTabId() {
    return MY_TAB_ID;
}
/**
 * Get known tabs (for testing/debugging).
 */
export function getKnownTabs() {
    return new Map(knownTabs);
}
/**
 * Helper: debug logging.
 */
function logDebug(...args) {
    if (config.debug) {
        console.log("[SessionSync]", ...args);
    }
}
//# sourceMappingURL=session-sync.js.map