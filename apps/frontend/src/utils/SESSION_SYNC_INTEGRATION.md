# Session Sync Integration Guide

## Overview

`session-sync.ts` provides multi-tab session synchronization with automatic leader election. It prevents the "thundering herd" problem where multiple browser tabs simultaneously attempt to refresh the session, causing redundant requests.

**Key Features:**
- BroadcastChannel-based inter-tab communication
- Distributed refresh lock (10-second TTL)
- Leader election for coordinated re-authentication
- Metrics tracking for monitoring
- Fallback for browsers without BroadcastChannel support
- Cross-tab session state consistency

---

## Architecture

### Components

1. **BroadcastChannel Communication**
   - Real-time messaging between tabs
   - Message types: `SESSION_REFRESHED`, `SESSION_EXPIRED`, `SESSION_QUERY`, `SESSION_STATE`

2. **Distributed Refresh Lock** (localStorage-based)
   - Only one tab can hold the lock at a time
   - 10-second TTL prevents deadlocks
   - Tab ID stored for lock ownership verification

3. **Tab Registry**
   - Tracks all active tabs in localStorage
   - Auto-cleanup of inactive tabs (60-second timeout)
   - Persists to localStorage for crash recovery

4. **Leader Election**
   - Deterministic: lowest tab ID is always leader
   - Used for coordinated re-authentication when session expires
   - No explicit consensus algorithm (no Byzantine fault tolerance)

---

## Integration with session-keepalive

### Step 1: Initialize session-sync at app startup

In your main app initialization (e.g., `App.tsx` or `index.tsx`):

```typescript
import { initSessionSync } from '@/utils/session-sync';

export function App() {
  useEffect(() => {
    // Initialize multi-tab sync
    initSessionSync({
      debug: process.env.NODE_ENV === 'development',
    });
  }, []);

  return <YourAppContent />;
}
```

### Step 2: Hook into session-keepalive refresh

In your session refresh handler (typically in `session-keepalive.ts` or where you call the refresh endpoint):

```typescript
import { broadcastSessionRefresh, acquireRefreshLock, releaseRefreshLock } from '@/utils/session-sync';

// In your refresh function:
export async function refreshSession(): Promise<boolean> {
  // Try to acquire the refresh lock
  if (!acquireRefreshLock()) {
    console.debug('[SessionKeepAlive] Another tab is refreshing; waiting for broadcast');
    return true; // Assume the other tab will broadcast success
  }

  try {
    // Perform the actual refresh
    const response = await fetch('/api/auth/refresh', { method: 'POST' });
    
    if (response.ok) {
      const { expiresAt } = await response.json();
      
      // Broadcast success to all other tabs
      broadcastSessionRefresh(expiresAt);
      
      return true;
    } else {
      console.error('[SessionKeepAlive] Refresh failed:', response.status);
      return false;
    }
  } finally {
    releaseRefreshLock();
  }
}
```

### Step 3: Listen for refresh broadcasts

```typescript
import { getMetrics } from '@/utils/session-sync';

// In your session-keepalive module:
const broadcastChannel = new BroadcastChannel('code-server-session');

broadcastChannel.addEventListener('message', (event: MessageEvent) => {
  if (event.data.type === 'SESSION_REFRESHED') {
    // Another tab refreshed; reschedule our local timer
    scheduleRefresh(event.data.expiry * 1000);
  } else if (event.data.type === 'SESSION_EXPIRED') {
    // Another tab reported session expired
    // Only leader tab should redirect to login
    if (isLeader()) {
      window.location.href = '/login';
    }
  }
});
```

### Step 4: Handle leader-only actions

When session expires, only the leader tab should redirect to login:

```typescript
import { isLeader, broadcastSessionExpiry } from '@/utils/session-sync';

export function handleSessionExpiry(): void {
  // Broadcast expiry to all tabs
  broadcastSessionExpiry();
  
  // Only leader tab redirects
  if (isLeader()) {
    console.warn('[SessionKeepAlive] Leader tab: redirecting to login');
    window.location.href = '/login?reason=session-expired';
  } else {
    console.debug('[SessionKeepAlive] Follower tab: waiting for leader to redirect');
  }
}
```

---

## API Reference

### Initialization

#### `initSessionSync(config?: SessionSyncConfig): void`

Initialize multi-tab session synchronization.

```typescript
initSessionSync({
  channelName: 'my-custom-channel',  // Default: 'code-server-session'
  lockTtlMs: 5000,                   // Default: 10000
  tabTimeoutMs: 30000,               // Default: 60000
  debug: true,                       // Default: false
});
```

**Parameters:**
- `channelName`: Name of BroadcastChannel (for testing/isolation)
- `lockTtlMs`: Refresh lock time-to-live in milliseconds
- `tabTimeoutMs`: How long to wait before removing tab from registry
- `debug`: Enable console logging

---

### Lock Management

#### `acquireRefreshLock(): boolean`

Attempt to acquire the refresh lock. Returns `true` if successful.

```typescript
if (acquireRefreshLock()) {
  // Perform refresh
  releaseRefreshLock();
}
```

#### `releaseRefreshLock(): void`

Release the refresh lock after operation.

---

### Broadcasting

#### `broadcastSessionRefresh(expiryMs: number): void`

Broadcast successful session refresh to all tabs.

```typescript
// After successful API call that returns new expiry
broadcastSessionRefresh(Date.now() + 3600000); // 1 hour from now
```

#### `broadcastSessionExpiry(): void`

Broadcast session expiry to coordinate re-authentication.

```typescript
if (refreshFailed) {
  broadcastSessionExpiry();
}
```

---

### Leader Election

#### `isLeader(): boolean`

Check if this tab is the elected leader.

```typescript
if (isLeader()) {
  // Perform leader-only actions (redirects, critical updates)
}
```

---

### Debugging & Metrics

#### `getMetrics(): SessionSyncMetrics`

Get current metrics for monitoring.

```typescript
const metrics = getMetrics();
console.log(metrics);
// {
//   broadcast_events_total: 5,
//   broadcast_refreshed: 2,
//   broadcast_expired: 1,
//   broadcast_query: 2,
//   leader_elections_total: 1,
//   lock_acquisitions_total: 3,
//   lock_acquisition_failures: 1
// }
```

#### `getTabId(): string`

Get the unique ID of this tab.

```typescript
console.log('My tab ID:', getTabId());
```

#### `getKnownTabs(): Map<string, { lastSeen: number }>`

Get all known tabs in the registry.

```typescript
const tabs = getKnownTabs();
tabs.forEach((metadata, tabId) => {
  console.log(`Tab ${tabId} last seen ${Date.now() - metadata.lastSeen}ms ago`);
});
```

#### `resetMetrics(): void`

Reset metrics (for testing).

```typescript
resetMetrics();
```

---

## Error Handling & Edge Cases

### BroadcastChannel Not Available

- Gracefully degrades on browsers without BroadcastChannel support
- Lock still works via localStorage fallback
- Tabs operate independently

### localStorage Not Available (Private Browsing)

- Lock acquisition returns `true` (fail-open)
- Prevents session expiry due to lock deadlock
- Multiple tabs may briefly race to refresh (acceptable tradeoff)

### Corrupted localStorage

- Handles JSON parse errors gracefully
- Clears invalid lock data automatically
- Allows new lock acquisition

### Session Expiry During Refresh

- Lock automatically expires after 10 seconds
- Other tabs can acquire lock if holder crashes
- Leader tab coordinates re-authentication

---

## Monitoring & Observability

### Key Metrics

| Metric | Purpose |
|--------|---------|
| `broadcast_events_total` | Total messages exchanged |
| `broadcast_refreshed` | Successful refresh broadcasts |
| `broadcast_expired` | Session expiry broadcasts |
| `broadcast_query` | State query requests |
| `leader_elections_total` | Number of leader election events |
| `lock_acquisitions_total` | Successful lock acquisitions |
| `lock_acquisition_failures` | Failed lock acquisitions |

### Example: Prometheus metrics export

```typescript
function exportMetrics(): Record<string, number> {
  const metrics = getMetrics();
  return {
    'session_sync_broadcast_events_total': metrics.broadcast_events_total,
    'session_sync_lock_acquisitions_total': metrics.lock_acquisitions_total,
    'session_sync_lock_failures_total': metrics.lock_acquisition_failures,
  };
}
```

---

## Testing

### Unit Tests

Comprehensive tests are in `__tests__/session-sync.test.ts`:

```bash
npm test -- session-sync.test.ts
```

Tests cover:
- Lock acquisition and release
- Message broadcasting
- Leader election
- Metrics tracking
- Error handling
- Edge cases

### Integration Testing

To test with actual tabs:

1. Open the app in two browser tabs
2. Enable debug logging: `initSessionSync({ debug: true })`
3. Watch console logs for broadcast events
4. Trigger session refresh to see lock/broadcast coordination
5. Close one tab to see registry cleanup

### Example Debug Output

```
[SessionSync] Initialized with config: {channelName: 'code-server-session', ...}
[SessionSync] BroadcastChannel created and listening
[SessionSync] Lock acquired
[SessionSync] Broadcasting SESSION_REFRESHED: {type: 'SESSION_REFRESHED', expiry: 3600, ...}
[SessionSync] Lock released
```

---

## Best Practices

### ✅ Do

- Initialize session-sync early in app lifecycle (before first session refresh)
- Always acquire lock before calling refresh endpoint
- Always release lock in finally block
- Use `isLeader()` to gate critical actions (redirects, etc.)
- Enable debug logging during development
- Monitor metrics in production

### ❌ Don't

- Forget to call `releaseRefreshLock()` (causes deadlock)
- Assume all tabs will see broadcasts immediately (eventual consistency)
- Use `isLeader()` for non-critical actions (unnecessary bottleneck)
- Create multiple instances of session-sync (global state)
- Modify localStorage keys directly (use public API)

---

## Troubleshooting

### "Lock held by Tab X" message keeps appearing

**Issue**: One tab acquired lock but didn't release it (crash or error).

**Solution**: Lock expires after 10 seconds (`lockTtlMs`). If consistently seeing this, check for uncaught exceptions in refresh handler.

### Broadcasts not received by other tabs

**Issue**: BroadcastChannel not supported or initialization order problem.

**Solution**: 
1. Verify browser supports BroadcastChannel (`typeof BroadcastChannel !== 'undefined'`)
2. Ensure `initSessionSync()` called before first refresh
3. Check browser console for errors

### Multiple tabs redirecting to login

**Issue**: Multiple tabs all see session expired and redirect.

**Solution**: Use `isLeader()` check before redirecting. Only leader tab should redirect.

### Performance degradation with many tabs

**Issue**: Excessive BroadcastChannel messages.

**Solution**: Tab registry auto-cleans after 60 seconds. For apps with many concurrent tabs, increase `tabTimeoutMs`.

---

## Related Files

- [session-keepalive.ts](./session-keepalive.ts) - Session expiry detection and auto-refresh
- [session-sync.ts](./session-sync.ts) - Multi-tab synchronization implementation
- [__tests__/session-sync.test.ts](__tests__/session-sync.test.ts) - Comprehensive test suite
- [#334](https://github.com/kushin77/code-server/issues/334) - GitHub issue for this feature

---

## References

- [MDN: BroadcastChannel API](https://developer.mozilla.org/en-US/docs/Web/API/BroadcastChannel)
- [MDN: Web Workers (related)](https://developer.mozilla.org/en-US/docs/Web/API/Web_Workers_API)
- Leader Election in Distributed Systems: [Martin Kleppmann's talks](https://martin.kleppmann.com/)
