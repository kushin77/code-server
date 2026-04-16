/**
 * session-sync.ts
 * Multi-tab session synchronization using BroadcastChannel
 * Part of Phase 2 Session Self-Healing (#334)
 */

import { getSessionExpiry, scheduleRefresh } from './session-keepalive';

const SESSION_CHANNEL_NAME = 'code-server-session';
const LOCK_KEY = 'session_refresh_lock';
const LOCK_TTL_MS = 10000; // 10s protection against thundering herd

type SessionMessage =
  | { type: 'SESSION_REFRESHED'; expiry: number; tabId: string }
  | { type: 'SESSION_QUERY'; tabId: string }
  | { type: 'SESSION_STATE'; expiry: number; tabId: string };

const myTabId = typeof crypto !== 'undefined' ? crypto.randomUUID() : Math.random().toString(36).substring(7);
let sessionChannel: BroadcastChannel | null = null;

/**
 * Initializes synchronization across multiple browser tabs
 */
export function initSessionSync(): void {
  if (typeof window === 'undefined' || typeof BroadcastChannel === 'undefined') {
    console.debug('[Session-Sync] BroadcastChannel not supported; falling back to independent refresh');
    return;
  }

  sessionChannel = new BroadcastChannel(SESSION_CHANNEL_NAME);

  sessionChannel.onmessage = (event: MessageEvent<SessionMessage>) => {
    const msg = event.data;
    if (msg.tabId === myTabId) return;

    switch (msg.type) {
      case 'SESSION_REFRESHED':
      case 'SESSION_STATE':
        console.debug(`[Session-Sync] Received updated session expiry (${msg.type}) from Tab ${msg.tabId}`);
        // Cookie updated by server response (same domain), we just need to re-arm the local timer
        scheduleRefresh(); 
        break;
      
      case 'SESSION_QUERY':
        console.debug(`[Session-Sync] Tab ${msg.tabId} queried for current session state`);
        const exp = getSessionExpiry();
        if (exp && sessionChannel) {
          sessionChannel.postMessage({
            type: 'SESSION_STATE',
            expiry: exp,
            tabId: myTabId
          });
        }
        break;
    }
  };

  // Query existing tabs to see if anyone has a recent expiry
  sessionChannel.postMessage({ type: 'SESSION_QUERY', tabId: myTabId });
}

/**
 * Broadcasts to all other tabs that we successfully refreshed the session
 */
export function broadcastSessionRefresh(newExpiry: number): void {
  if (sessionChannel) {
    sessionChannel.postMessage({
      type: 'SESSION_REFRESHED',
      expiry: newExpiry,
      tabId: myTabId
    });
  }
}

/**
 * Attempts to acquire a lock to perform a refresh
 * Prevents multiple tabs from racing to the refresh endpoint simultaneously
 */
export function acquireRefreshLock(): boolean {
  if (typeof localStorage === 'undefined') return true; // Fail-open to avoid stuck sessions

  const now = Date.now();
  const existing = localStorage.getItem(LOCK_KEY);
  
  if (existing) {
    try {
      const { ts, tabId } = JSON.parse(existing);
      // If lock was acquired recently by another tab, return false
      if (now - ts < LOCK_TTL_MS && tabId !== myTabId) {
        console.debug(`[Session-Sync] Lock held by Tab ${tabId}, avoiding race condition`);
        return false;
      }
    } catch (e) {
      // Corrupt data, clear it
      localStorage.removeItem(LOCK_KEY);
    }
  }

  localStorage.setItem(LOCK_KEY, JSON.stringify({ ts: now, tabId: myTabId }));
  return true;
}

/**
 * Release the refresh lock after operation
 */
export function releaseRefreshLock(): void {
  if (typeof localStorage !== 'undefined') {
    localStorage.removeItem(LOCK_KEY);
  }
}
