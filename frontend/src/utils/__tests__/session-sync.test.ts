/**
 * session-sync.test.ts
 * Unit tests for multi-tab session synchronization
 */

import { initSessionSync, broadcastSessionRefresh, acquireRefreshLock, releaseRefreshLock } from '../session-sync';

// Mock BroadcastChannel
class MockBroadcastChannel {
  name: string;
  onmessage: ((event: MessageEvent<any>) => void) | null = null;
  postMessage: jest.Mock;

  constructor(name: string) {
    this.name = name;
    this.postMessage = jest.fn((data) => {
      // Simulate own tab receiving own message if we don't filter it
      if (this.onmessage) {
        this.onmessage({ data } as MessageEvent);
      }
    });
  }
}

global.BroadcastChannel = MockBroadcastChannel as any;

describe('Session Sync', () => {
  let localStorageMock: Record<string, string> = {};

  beforeEach(() => {
    // Mock localStorage
    Object.defineProperty(window, 'localStorage', {
      value: {
        getItem: (key: string) => localStorageMock[key] || null,
        setItem: (key: string, val: string) => { localStorageMock[key] = val; },
        removeItem: (key: string) => { delete localStorageMock[key]; },
        clear: () => { localStorageMock = {}; },
      },
      writable: true,
      configurable: true,
    });
    
    // Clear state
    localStorageMock = {};
  });

  afterEach(() => {
    jest.clearAllMocks();
  });

  test('acquireRefreshLock() succeeds when no lock is present', () => {
    expect(acquireRefreshLock()).toBe(true);
  });

  test('acquireRefreshLock() fails when recent lock by another tab exists', () => {
    const anotherTab = JSON.stringify({ ts: Date.now() - 1000, tabId: 'other-tab-id' });
    localStorage.setItem('session_refresh_lock', anotherTab);
    
    expect(acquireRefreshLock()).toBe(false);
  });

  test('acquireRefreshLock() succeeds when old (expired) lock exists', () => {
    const expiredLock = JSON.stringify({ ts: Date.now() - 20000, tabId: 'other-tab-id' });
    localStorage.setItem('session_refresh_lock', expiredLock);
    
    expect(acquireRefreshLock()).toBe(true);
  });

  test('releaseRefreshLock() clears the lock', () => {
    acquireRefreshLock();
    expect(localStorage.getItem('session_refresh_lock')).not.toBeNull();
    
    releaseRefreshLock();
    expect(localStorage.getItem('session_refresh_lock')).toBeNull();
  });
});
