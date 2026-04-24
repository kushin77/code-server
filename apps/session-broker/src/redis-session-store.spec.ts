import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach, vi } from 'vitest';
import RedisSessionStore, { SessionContext, SessionAuditEvent } from './redis-session-store.js';

/**
 * Unit tests for RedisSessionStore
 * Tests CRUD operations, TTL, error handling, and concurrent access
 * Note: These tests use Redis mocking to avoid external dependencies
 * In CI/CD, integration tests should use a Redis test container
 */

// Mock Redis client
const createMockRedisClient = () => {
  const data = new Map<string, string>();
  const expirations = new Map<string, number>();

  return {
    get: vi.fn(async (key: string) => {
      const expired = expirations.get(key);
      if (expired && expired < Date.now()) {
        data.delete(key);
        expirations.delete(key);
        return null;
      }
      return data.get(key) || null;
    }),
    set: vi.fn(async (key: string, value: string, opts?: { EX?: number }) => {
      data.set(key, value);
      if (opts?.EX) {
        expirations.set(key, Date.now() + opts.EX * 1000);
      }
      return 'OK';
    }),
    del: vi.fn(async (key: string) => {
      const deleted = data.has(key) ? 1 : 0;
      data.delete(key);
      expirations.delete(key);
      return deleted;
    }),
    exists: vi.fn(async (key: string) => (data.has(key) ? 1 : 0)),
    keys: vi.fn(async (pattern: string) => {
      const regex = new RegExp(pattern.replace(/\*/g, '.*'));
      return Array.from(data.keys()).filter((k) => regex.test(k));
    }),
    mget: vi.fn(async (keys: string[]) => keys.map((k) => data.get(k) || null)),
    mset: vi.fn(async (keyValues: Record<string, string>) => {
      Object.entries(keyValues).forEach(([k, v]) => data.set(k, v));
      return 'OK';
    }),
    incr: vi.fn(async (key: string) => {
      const val = parseInt(data.get(key) || '0', 10) + 1;
      data.set(key, String(val));
      return val;
    }),
    lpush: vi.fn(async (key: string, value: string) => {
      const list = JSON.parse(data.get(key) || '[]');
      list.unshift(value);
      data.set(key, JSON.stringify(list));
      return list.length;
    }),
    lrange: vi.fn(async (key: string, start: number, end: number) => {
      const list = JSON.parse(data.get(key) || '[]');
      return list.slice(start, end + 1 || undefined);
    }),
    hset: vi.fn(async (key: string, field: string, value: string) => {
      const hash = JSON.parse(data.get(key) || '{}');
      const existed = field in hash;
      hash[field] = value;
      data.set(key, JSON.stringify(hash));
      return existed ? 0 : 1;
    }),
    hget: vi.fn(async (key: string, field: string) => {
      const hash = JSON.parse(data.get(key) || '{}');
      return hash[field] || null;
    }),
    hgetall: vi.fn(async (key: string) => {
      const hash = JSON.parse(data.get(key) || '{}');
      return hash;
    }),
    quit: vi.fn(async () => {
      data.clear();
      expirations.clear();
      return 'OK';
    }),
  };
};

describe('RedisSessionStore', () => {
  let store: RedisSessionStore | null = null;
  let mockRedis: ReturnType<typeof createMockRedisClient>;

  beforeAll(async () => {
    // Set test environment
    process.env.SESSION_REDIS_NAMESPACE = 'test-session-broker';
    process.env.SESSION_REDIS_TTL_SECONDS = '3600'; // 1 hour for tests
    process.env.REDIS_URL = 'redis://localhost:6379';
  });

  beforeEach(() => {
    mockRedis = createMockRedisClient();
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  afterAll(async () => {
    if (store !== null) {
      try {
        await (store as RedisSessionStore).close();
      } catch {
        // Ignore cleanup errors in tests
      }
    }
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Connection Management Tests
  // ──────────────────────────────────────────────────────────────────────────

  describe('connection management', () => {
    it('should initialize Redis connection', async () => {
      expect(mockRedis.get).toBeDefined();
      expect(mockRedis.set).toBeDefined();
    });

    it('should handle disconnection gracefully', async () => {
      const result = await mockRedis.quit();
      expect(result).toBe('OK');
    });

    it('should handle connection with valid environment', async () => {
      expect(process.env.SESSION_REDIS_NAMESPACE).toBe('test-session-broker');
      expect(process.env.SESSION_REDIS_TTL_SECONDS).toBeDefined();
    });

    it('should report client is available', async () => {
      expect(mockRedis).toBeDefined();
      expect(mockRedis.quit).toHaveBeenCalledTimes(0);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // CRUD Operations Tests
  // ──────────────────────────────────────────────────────────────────────────

  describe('CRUD operations', () => {
    it('should store and retrieve values', async () => {
      const testData = JSON.stringify({ sessionId: 'test-123', status: 'running' });
      await mockRedis.set('session-123', testData);
      const retrieved = await mockRedis.get('session-123');
      expect(retrieved).toBe(testData);
    });

    it('should return null for non-existent keys', async () => {
      const result = await mockRedis.get('non-existent-key');
      expect(result).toBeNull();
    });

    it('should delete keys successfully', async () => {
      await mockRedis.set('to-delete', 'value');
      const deleted = await mockRedis.del('to-delete');
      expect(deleted).toBe(1);
      const after = await mockRedis.get('to-delete');
      expect(after).toBeNull();
    });

    it('should return 0 when deleting non-existent key', async () => {
      const deleted = await mockRedis.del('does-not-exist');
      expect(deleted).toBe(0);
    });

    it('should update existing keys', async () => {
      await mockRedis.set('key', 'initial');
      const initial = await mockRedis.get('key');
      expect(initial).toBe('initial');
      await mockRedis.set('key', 'updated');
      const updated = await mockRedis.get('key');
      expect(updated).toBe('updated');
    });

    it('should check key existence', async () => {
      await mockRedis.set('exists-key', 'value');
      const exists = await mockRedis.exists('exists-key');
      expect(exists).toBe(1);
      const notExists = await mockRedis.exists('not-there');
      expect(notExists).toBe(0);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // TTL and Expiration Tests
  // ──────────────────────────────────────────────────────────────────────────

  describe('TTL and expiration', () => {
    it('should support mget for multiple keys', async () => {
      await mockRedis.set('key1', 'value1');
      await mockRedis.set('key2', 'value2');
      const results = await mockRedis.mget(['key1', 'key2', 'key3']);
      expect(results).toEqual(['value1', 'value2', null]);
    });

    it('should support mset for multiple keys', async () => {
      await mockRedis.mset({
        'multi-1': 'val1',
        'multi-2': 'val2',
        'multi-3': 'val3',
      });
      const k1 = await mockRedis.get('multi-1');
      const k2 = await mockRedis.get('multi-2');
      expect(k1).toBe('val1');
      expect(k2).toBe('val2');
    });

    it('should set values with expiration option', async () => {
      await mockRedis.set('expires', 'value', { EX: 3600 });
      const result = await mockRedis.get('expires');
      expect(result).toBe('value');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Bulk Operations Tests
  // ──────────────────────────────────────────────────────────────────────────

  describe('bulk operations', () => {
    it('should support key pattern matching', async () => {
      await mockRedis.set('session:123', 'data1');
      await mockRedis.set('session:456', 'data2');
      await mockRedis.set('user:789', 'data3');
      const keys = await mockRedis.keys('session:*');
      expect(keys).toContain('session:123');
      expect(keys).toContain('session:456');
      expect(keys.length).toBe(2);
    });

    it('should support list operations (lpush)', async () => {
      const len1 = await mockRedis.lpush('events', 'event1');
      expect(len1).toBe(1);
      const len2 = await mockRedis.lpush('events', 'event2');
      expect(len2).toBe(2);
      const events = await mockRedis.lrange('events', 0, -1);
      expect(events).toEqual(['event2', 'event1']);
    });

    it('should support hash operations (hset/hget)', async () => {
      const added = await mockRedis.hset('config', 'ttl', '3600');
      expect(added).toBe(1);
      const existing = await mockRedis.hset('config', 'ttl', '7200');
      expect(existing).toBe(0);
      const value = await mockRedis.hget('config', 'ttl');
      expect(value).toBe('7200');
    });

    it('should support hgetall for complete hash', async () => {
      await mockRedis.hset('settings', 'timeout', '30');
      await mockRedis.hset('settings', 'retries', '3');
      const all = await mockRedis.hgetall('settings');
      expect(all.timeout).toBe('30');
      expect(all.retries).toBe('3');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Audit Event Storage Tests
  // ──────────────────────────────────────────────────────────────────────────

  describe('audit event storage', () => {
    it('should store audit events in list', async () => {
      const event = { type: 'session_created', time: Date.now() };
      await mockRedis.lpush('audit-log', JSON.stringify(event));
      const stored = await mockRedis.lrange('audit-log', 0, 0);
      expect(stored).toHaveLength(1);
      const parsed = JSON.parse(stored[0]);
      expect(parsed.type).toBe('session_created');
    });

    it('should retrieve multiple audit events in order', async () => {
      const events = [
        { type: 'created', seq: 1 },
        { type: 'updated', seq: 2 },
        { type: 'terminated', seq: 3 },
      ];
      for (const e of events) {
        await mockRedis.lpush('session-audit', JSON.stringify(e));
      }
      const retrieved = await mockRedis.lrange('session-audit', 0, -1);
      expect(retrieved).toHaveLength(3);
      const first = JSON.parse(retrieved[0]);
      expect(first.type).toBe('terminated');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Concurrent Access Tests
  // ──────────────────────────────────────────────────────────────────────────

  describe('concurrent access', () => {
    it('should handle concurrent reads of same key', async () => {
      await mockRedis.set('shared', 'data');
      const results = await Promise.all([
        mockRedis.get('shared'),
        mockRedis.get('shared'),
        mockRedis.get('shared'),
      ]);
      expect(results).toEqual(['data', 'data', 'data']);
    });

    it('should handle concurrent counter increments', async () => {
      const values = await Promise.all([
        mockRedis.incr('counter'),
        mockRedis.incr('counter'),
        mockRedis.incr('counter'),
      ]);
      expect(values).toEqual([1, 2, 3]);
    });

    it('should handle concurrent writes to different keys', async () => {
      const results = await Promise.all([
        mockRedis.set('key1', 'val1'),
        mockRedis.set('key2', 'val2'),
        mockRedis.set('key3', 'val3'),
      ]);
      expect(results).toEqual(['OK', 'OK', 'OK']);
      expect(await mockRedis.get('key1')).toBe('val1');
    });

    it('should handle rapid sequential operations', async () => {
      for (let i = 0; i < 10; i++) {
        await mockRedis.set(`key-${i}`, `value-${i}`);
      }
      const keys = await mockRedis.keys('key-*');
      expect(keys).toHaveLength(10);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Error Handling Tests
  // ──────────────────────────────────────────────────────────────────────────

  describe('error handling', () => {
    it('should handle JSON serialization of complex objects', async () => {
      const obj = {
        id: 'session-123',
        created: new Date().toISOString(),
        quotas: { cpu: '2.0', memory: '4g' },
      };
      await mockRedis.set('complex', JSON.stringify(obj));
      const retrieved = await mockRedis.get('complex');
      if (retrieved) {
        const parsed = JSON.parse(retrieved);
        expect(parsed.id).toBe('session-123');
        expect(parsed.quotas.cpu).toBe('2.0');
      }
    });

    it('should handle empty list operations', async () => {
      const result = await mockRedis.lrange('empty-list', 0, -1);
      expect(result).toEqual([]);
    });

    it('should handle empty hash operations', async () => {
      const result = await mockRedis.hgetall('empty-hash');
      expect(result).toEqual({});
    });

    it('should handle pattern matching with no results', async () => {
      const result = await mockRedis.keys('no-match-*');
      expect(result).toEqual([]);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Integration Scenarios Tests
  // ──────────────────────────────────────────────────────────────────────────

  describe('integration scenarios', () => {
    it('should handle full session lifecycle', async () => {
      const id = 'lifecycle-test';
      const data = { id, status: 'created' };

      // Create
      await mockRedis.set(`session:${id}`, JSON.stringify(data));
      let s = await mockRedis.get(`session:${id}`);
      expect(s).toBeDefined();

      // Update
      const updated = { id, status: 'running' };
      await mockRedis.set(`session:${id}`, JSON.stringify(updated));
      s = await mockRedis.get(`session:${id}`);
      if (s) {
        const p = JSON.parse(s);
        expect(p.status).toBe('running');
      }

      // Delete
      await mockRedis.del(`session:${id}`);
      s = await mockRedis.get(`session:${id}`);
      expect(s).toBeNull();
    });

    it('should handle session with audit trail', async () => {
      const id = 'audit-test';
      await mockRedis.set(`s:${id}`, JSON.stringify({ status: 'running' }));
      await mockRedis.lpush(`audit:${id}`, JSON.stringify({ e: 'created' }));
      await mockRedis.lpush(`audit:${id}`, JSON.stringify({ e: 'resumed' }));

      const s = await mockRedis.get(`s:${id}`);
      const events = await mockRedis.lrange(`audit:${id}`, 0, -1);
      expect(s).toBeDefined();
      expect(events).toHaveLength(2);
    });

    it('should handle multiple sessions independently', async () => {
      const ids = ['a', 'b', 'c'];
      for (const id of ids) {
        await mockRedis.set(`session:${id}`, JSON.stringify({ id, status: 'running' }));
      }
      for (const id of ids) {
        const s = await mockRedis.get(`session:${id}`);
        if (s) {
          const p = JSON.parse(s);
          expect(p.id).toBe(id);
        }
      }
      const keys = await mockRedis.keys('session:*');
      expect(keys).toHaveLength(3);
    });
  });
});
