/**
 * @file session-indexeddb-store.test.ts
 * @description Comprehensive tests for IndexedDB session storage
 * @test unit
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  storeSessionExpiry,
  getSessionExpiry,
  clearSessionExpiry,
  isSessionValid,
} from '../session-indexeddb-store';

// Mock IndexedDB for testing
class MockIDBDatabase {
  stores: Record<string, Record<string, any>> = {};

  transaction(name: string, mode: string) {
    const store = this.stores[name] || (this.stores[name] = {});
    return {
      objectStore: () => ({
        put: (value: any, key: string) => ({
          onerror: null,
          get error() { return null; },
          onsuccess: () => { store[key] = value; }(),
        }),
        get: (key: string) => ({
          onerror: null,
          onsuccess: null,
          get result() { return store[key]; },
        }),
        delete: (key: string) => ({
          onerror: null,
          onsuccess: () => { delete store[key]; }(),
        }),
      }),
      oncomplete: null,
      get onerror() { return null; },
    };
  }
}

describe('session-indexeddb-store', () => {
  let mockDB: MockIDBDatabase;

  beforeEach(() => {
    mockDB = new MockIDBDatabase();
    // Mock indexedDB global
    global.indexedDB = {
      open: vi.fn((name: string, version: number) => {
        return {
          result: mockDB,
          onerror: null,
          onsuccess: null,
          onupgradeneeded: null,
          addEventListener: () => {},
        };
      }),
    } as any;
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('storeSessionExpiry', () => {
    it('should store expiry timestamp in IndexedDB', async () => {
      const expiry = Date.now() + 15 * 60 * 1000; // 15 minutes from now
      await storeSessionExpiry(expiry);

      expect(mockDB.stores['metadata']).toHaveProperty('session_expiry');
      expect(mockDB.stores['metadata']['session_expiry']).toBe(expiry);
    });

    it('should handle store error gracefully', async () => {
      const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
      global.indexedDB = {
        open: vi.fn(() => {
          throw new Error('IndexedDB not available');
        }),
      } as any;

      await storeSessionExpiry(12345);
      expect(consoleSpy).toHaveBeenCalledWith(
        '[session-store] Failed to store expiry in IndexedDB:',
        expect.any(Error)
      );

      consoleSpy.mockRestore();
    });

    it('should update expiry if called multiple times', async () => {
      const expiry1 = Date.now() + 10 * 60 * 1000;
      const expiry2 = Date.now() + 20 * 60 * 1000;

      await storeSessionExpiry(expiry1);
      expect(mockDB.stores['metadata']['session_expiry']).toBe(expiry1);

      await storeSessionExpiry(expiry2);
      expect(mockDB.stores['metadata']['session_expiry']).toBe(expiry2);
    });
  });

  describe('getSessionExpiry', () => {
    it('should retrieve expiry timestamp from IndexedDB', async () => {
      const expiry = Date.now() + 15 * 60 * 1000;
      mockDB.stores['metadata'] = { session_expiry: expiry };

      const result = await getSessionExpiry();
      expect(result).toBe(expiry);
    });

    it('should return null if expiry not set', async () => {
      mockDB.stores['metadata'] = {};

      const result = await getSessionExpiry();
      expect(result).toBeNull();
    });

    it('should handle retrieval error gracefully', async () => {
      const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
      global.indexedDB = {
        open: vi.fn(() => {
          throw new Error('IndexedDB not available');
        }),
      } as any;

      const result = await getSessionExpiry();
      expect(result).toBeNull();
      expect(consoleSpy).toHaveBeenCalled();

      consoleSpy.mockRestore();
    });
  });

  describe('clearSessionExpiry', () => {
    it('should delete expiry from IndexedDB', async () => {
      const expiry = Date.now() + 15 * 60 * 1000;
      mockDB.stores['metadata'] = { session_expiry: expiry };

      await clearSessionExpiry();
      expect(mockDB.stores['metadata']).not.toHaveProperty('session_expiry');
    });

    it('should handle deletion error gracefully', async () => {
      const consoleSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});
      global.indexedDB = {
        open: vi.fn(() => {
          throw new Error('IndexedDB not available');
        }),
      } as any;

      await clearSessionExpiry();
      expect(consoleSpy).toHaveBeenCalled();

      consoleSpy.mockRestore();
    });
  });

  describe('isSessionValid', () => {
    it('should return true if session is not expired', async () => {
      const futureExpiry = Date.now() + 15 * 60 * 1000;
      mockDB.stores['metadata'] = { session_expiry: futureExpiry };

      const result = await isSessionValid();
      expect(result).toBe(true);
    });

    it('should return false if session is expired', async () => {
      const pastExpiry = Date.now() - 15 * 60 * 1000;
      mockDB.stores['metadata'] = { session_expiry: pastExpiry };

      const result = await isSessionValid();
      expect(result).toBe(false);
    });

    it('should return false if expiry not set', async () => {
      mockDB.stores['metadata'] = {};

      const result = await isSessionValid();
      expect(result).toBe(false);
    });

    it('should handle expiry at exact boundary', async () => {
      const now = Date.now();
      mockDB.stores['metadata'] = { session_expiry: now };

      const result = await isSessionValid();
      // Should be false since now >= expiry
      expect(result).toBe(false);
    });

    it('should handle expiry 1ms in future', async () => {
      const nearFutureExpiry = Date.now() + 1;
      mockDB.stores['metadata'] = { session_expiry: nearFutureExpiry };

      const result = await isSessionValid();
      expect(result).toBe(true);
    });
  });

  describe('concurrency', () => {
    it('should handle concurrent store/get operations', async () => {
      const expiry1 = Date.now() + 10 * 60 * 1000;
      const expiry2 = Date.now() + 20 * 60 * 1000;

      const promises = [
        storeSessionExpiry(expiry1),
        storeSessionExpiry(expiry2),
        getSessionExpiry(),
        getSessionExpiry(),
      ];

      await Promise.all(promises);
      // Last store should win
      const result = await getSessionExpiry();
      expect(result).toBe(expiry2);
    });

    it('should handle store + clear concurrently', async () => {
      const expiry = Date.now() + 15 * 60 * 1000;

      const [storeResult, clearResult] = await Promise.all([
        storeSessionExpiry(expiry),
        clearSessionExpiry(),
      ]);

      // After race, state could be either, but should not error
      expect(true).toBe(true); // Just verify no error thrown
    });
  });

  describe('data types and boundaries', () => {
    it('should handle large timestamp values', async () => {
      const largeTimestamp = Number.MAX_SAFE_INTEGER - 1;
      await storeSessionExpiry(largeTimestamp);

      const result = await getSessionExpiry();
      expect(result).toBe(largeTimestamp);
    });

    it('should handle zero timestamp', async () => {
      await storeSessionExpiry(0);
      const result = await getSessionExpiry();
      expect(result).toBe(0);
    });

    it('should handle negative timestamp', async () => {
      const negativeTimestamp = -1000;
      await storeSessionExpiry(negativeTimestamp);
      const result = await getSessionExpiry();
      expect(result).toBe(negativeTimestamp);
    });
  });
});
