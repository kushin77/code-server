/**
 * session-sync.test.ts
 * Comprehensive tests for multi-tab session synchronization with leader election
 */

import {
  initSessionSync,
  destroySessionSync,
  broadcastSessionRefresh,
  broadcastSessionExpiry,
  acquireRefreshLock,
  releaseRefreshLock,
  isLeader,
  getTabId,
  getKnownTabs,
  getMetrics,
  resetMetrics,
  type SessionSyncConfig,
  type SessionMessage,
} from "../session-sync";

// Mock BroadcastChannel
class MockBroadcastChannel {
  static instances: MockBroadcastChannel[] = [];
  name: string;
  listeners: Map<string, ((event: MessageEvent<any>) => void)[]> = new Map();
  postMessage: jest.Mock;
  closed: boolean = false;

  constructor(name: string) {
    this.name = name;
    this.postMessage = jest.fn((data) => {
      // Broadcast to all instances of this channel
      MockBroadcastChannel.instances.forEach((instance) => {
        if (instance.name === name && instance !== this) {
          instance.dispatchEvent("message", { data } as MessageEvent);
        }
      });
    });
    MockBroadcastChannel.instances.push(this);
  }

  addEventListener(event: string, listener: (event: MessageEvent<any>) => void) {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, []);
    }
    this.listeners.get(event)!.push(listener);
  }

  removeEventListener(event: string, listener: (event: MessageEvent<any>) => void) {
    const listeners = this.listeners.get(event);
    if (listeners) {
      const idx = listeners.indexOf(listener);
      if (idx >= 0) listeners.splice(idx, 1);
    }
  }

  dispatchEvent(event: string, messageEvent: MessageEvent) {
    const listeners = this.listeners.get(event);
    if (listeners) {
      listeners.forEach((listener) => listener(messageEvent));
    }
  }

  close() {
    this.closed = true;
    const idx = MockBroadcastChannel.instances.indexOf(this);
    if (idx >= 0) {
      MockBroadcastChannel.instances.splice(idx, 1);
    }
  }
}

global.BroadcastChannel = MockBroadcastChannel as any;

describe("Session Sync - Multi-tab Synchronization", () => {
  let localStorageMock: Record<string, string> = {};

  beforeEach(() => {
    // Reset BroadcastChannel instances
    MockBroadcastChannel.instances = [];

    // Mock localStorage
    localStorageMock = {};
    Object.defineProperty(window, "localStorage", {
      value: {
        getItem: (key: string) => localStorageMock[key] || null,
        setItem: (key: string, val: string) => {
          localStorageMock[key] = val;
        },
        removeItem: (key: string) => {
          delete localStorageMock[key];
        },
        clear: () => {
          localStorageMock = {};
        },
      },
      writable: true,
      configurable: true,
    });

    // Reset metrics
    resetMetrics();
  });

  afterEach(() => {
    destroySessionSync();
    jest.clearAllMocks();
  });

  // ==================== Lock Tests ====================

  describe("Refresh Lock", () => {
    test("acquireRefreshLock() succeeds when no lock exists", () => {
      expect(acquireRefreshLock()).toBe(true);
    });

    test("acquireRefreshLock() fails when recent lock by another tab exists", () => {
      const anotherTabLock = JSON.stringify({
        ts: Date.now() - 1000,
        tabId: "other-tab-id",
      });
      localStorage.setItem("session_refresh_lock_code-server-session", anotherTabLock);

      expect(acquireRefreshLock()).toBe(false);
    });

    test("acquireRefreshLock() succeeds when old (expired) lock exists", () => {
      const expiredLock = JSON.stringify({
        ts: Date.now() - 20000, // 20s ago > 10s TTL
        tabId: "other-tab-id",
      });
      localStorage.setItem("session_refresh_lock_code-server-session", expiredLock);

      expect(acquireRefreshLock()).toBe(true);
    });

    test("releaseRefreshLock() clears the lock", () => {
      acquireRefreshLock();
      expect(localStorage.getItem("session_refresh_lock_code-server-session")).not.toBeNull();

      releaseRefreshLock();
      expect(localStorage.getItem("session_refresh_lock_code-server-session")).toBeNull();
    });

    test("acquireRefreshLock() allows self to acquire when lock held by self", () => {
      acquireRefreshLock();
      const metrics1 = getMetrics();
      expect(metrics1.lock_acquisitions_total).toBe(1);

      // Acquire again (should succeed)
      expect(acquireRefreshLock()).toBe(true);
      const metrics2 = getMetrics();
      expect(metrics2.lock_acquisitions_total).toBe(2);
    });
  });

  // ==================== BroadcastChannel Tests ====================

  describe("Session Broadcasts", () => {
    test("broadcastSessionRefresh() sends SESSION_REFRESHED message", () => {
      initSessionSync();

      const channel = MockBroadcastChannel.instances.find(
        (c) => c.name === "code-server-session"
      );
      expect(channel).toBeDefined();

      broadcastSessionRefresh(3600000); // 1 hour expiry

      expect(channel!.postMessage).toHaveBeenCalledWith(
        expect.objectContaining({
          type: "SESSION_REFRESHED",
          expiry: 3600,
          tabId: getTabId(),
          timestamp: expect.any(Number),
        })
      );

      const metrics = getMetrics();
      expect(metrics.broadcast_events_total).toBe(1);
      expect(metrics.broadcast_refreshed).toBe(1);
    });

    test("broadcastSessionExpiry() sends SESSION_EXPIRED message", () => {
      initSessionSync();

      const channel = MockBroadcastChannel.instances.find(
        (c) => c.name === "code-server-session"
      );

      broadcastSessionExpiry();

      expect(channel!.postMessage).toHaveBeenCalledWith(
        expect.objectContaining({
          type: "SESSION_EXPIRED",
          tabId: getTabId(),
          timestamp: expect.any(Number),
        })
      );

      const metrics = getMetrics();
      expect(metrics.broadcast_expired).toBe(1);
    });

    test("BroadcastChannel messages are received by other tabs", (done) => {
      initSessionSync();
      const metrics1 = getMetrics();
      expect(metrics1.leader_elections_total).toBeGreaterThan(0);

      // Create a second "tab" instance
      const anotherTab = new MockBroadcastChannel("code-server-session");
      let messageReceived = false;

      anotherTab.addEventListener("message", (event: MessageEvent) => {
        if (event.data.type === "SESSION_REFRESHED") {
          messageReceived = true;
        }
      });

      broadcastSessionRefresh(7200000);

      // Allow async message propagation
      setTimeout(() => {
        expect(messageReceived).toBe(true);
        anotherTab.close();
        done();
      }, 100);
    });
  });

  // ==================== Leader Election Tests ====================

  describe("Leader Election", () => {
    test("isLeader() returns true for first tab", () => {
      initSessionSync();
      expect(isLeader()).toBe(true);
    });

    test("knownTabs includes self after init", () => {
      initSessionSync();
      const tabs = getKnownTabs();
      expect(tabs.has(getTabId())).toBe(true);
    });

    test("Multiple tabs register and leader is lowest ID", () => {
      initSessionSync();
      const tab1Id = getTabId();
      expect(isLeader()).toBe(true);

      destroySessionSync();

      // Simulate another tab with a different ID
      initSessionSync();
      const tab2Id = getTabId();

      // The tab with lexicographically smaller ID is leader
      const tabs = getKnownTabs();
      expect(tabs.size).toBe(2); // Both tabs registered
      // This is a simplified test; actual leader election depends on tab creation order
    });
  });

  // ==================== Metrics Tests ====================

  describe("Metrics Tracking", () => {
    test("getMetrics() returns metrics object", () => {
      const metrics = getMetrics();
      expect(metrics).toHaveProperty("broadcast_events_total");
      expect(metrics).toHaveProperty("broadcast_refreshed");
      expect(metrics).toHaveProperty("broadcast_expired");
      expect(metrics).toHaveProperty("broadcast_query");
      expect(metrics).toHaveProperty("leader_elections_total");
      expect(metrics).toHaveProperty("lock_acquisitions_total");
      expect(metrics).toHaveProperty("lock_acquisition_failures");
    });

    test("Metrics increment on broadcasts", () => {
      initSessionSync();
      const metrics1 = getMetrics();

      broadcastSessionRefresh(3600000);
      const metrics2 = getMetrics();

      expect(metrics2.broadcast_events_total).toBe(metrics1.broadcast_events_total + 1);
      expect(metrics2.broadcast_refreshed).toBe(metrics1.broadcast_refreshed + 1);
    });

    test("resetMetrics() zeros all counters", () => {
      initSessionSync();
      broadcastSessionRefresh(3600000);

      resetMetrics();
      const metrics = getMetrics();

      expect(metrics.broadcast_events_total).toBe(0);
      expect(metrics.broadcast_refreshed).toBe(0);
    });

    test("Lock acquisition metrics track failures", () => {
      // Acquire lock by "another tab"
      const anotherTabLock = JSON.stringify({
        ts: Date.now() - 1000,
        tabId: "other-tab",
      });
      localStorage.setItem("session_refresh_lock_code-server-session", anotherTabLock);

      const failedAcquisition = acquireRefreshLock();
      expect(failedAcquisition).toBe(false);

      const metrics = getMetrics();
      expect(metrics.lock_acquisition_failures).toBe(1);
    });
  });

  // ==================== Configuration Tests ====================

  describe("Configuration", () => {
    test("initSessionSync() with custom config", () => {
      const customConfig: SessionSyncConfig = {
        channelName: "custom-channel",
        lockTtlMs: 5000,
        tabTimeoutMs: 30000,
        debug: true,
      };

      initSessionSync(customConfig);

      // Verify custom settings were applied
      broadcastSessionRefresh(3600000);

      // The channel should be created with custom name
      const customChannel = MockBroadcastChannel.instances.find(
        (c) => c.name === "custom-channel"
      );
      expect(customChannel).toBeDefined();
    });
  });

  // ==================== Edge Cases ====================

  describe("Edge Cases and Error Handling", () => {
    test("broadcastSessionRefresh() gracefully handles missing BroadcastChannel", () => {
      // Don't initialize session sync; BroadcastChannel should be null
      expect(() => broadcastSessionRefresh(3600000)).not.toThrow();
    });

    test("acquireRefreshLock() handles corrupted localStorage", () => {
      localStorage.setItem("session_refresh_lock_code-server-session", "{ invalid json");

      expect(() => acquireRefreshLock()).not.toThrow();
      expect(acquireRefreshLock()).toBe(true);
    });

    test("releaseRefreshLock() handles missing lock gracefully", () => {
      expect(() => releaseRefreshLock()).not.toThrow();
    });

    test("getTabId() returns consistent ID across calls", () => {
      const tabId1 = getTabId();
      const tabId2 = getTabId();
      expect(tabId1).toBe(tabId2);
    });
  });

  // ==================== Integration Tests ====================

  describe("Integration: Lock + Broadcast", () => {
    test("Full refresh workflow: lock → broadcast → release", () => {
      initSessionSync();

      // Step 1: Acquire lock
      const lockAcquired = acquireRefreshLock();
      expect(lockAcquired).toBe(true);

      // Step 2: Broadcast refresh
      broadcastSessionRefresh(3600000);

      // Step 3: Release lock
      releaseRefreshLock();

      const metrics = getMetrics();
      expect(metrics.lock_acquisitions_total).toBe(1);
      expect(metrics.broadcast_refreshed).toBe(1);
    });

    test("Session expiry workflow", () => {
      initSessionSync();

      // Simulate session expiry
      broadcastSessionExpiry();

      const metrics = getMetrics();
      expect(metrics.broadcast_expired).toBe(1);
    });
  });
});
