## P1: Add Unit Tests for redis-session-store.ts

### Problem

**File**: `apps/session-broker/src/redis-session-store.ts`

The Redis session store module (~100+ lines) has **no unit tests**, while all other session-broker modules have test files:

```
apps/session-broker/src/
├── session-access-control.spec.ts    ✓
├── session-data-profile.spec.ts      ✓
├── session-deletion.spec.ts          ✓
├── redis-session-store.ts            ← NO TEST FILE
```

### Impact

Critical functionality is untested:
- Redis connection/reconnection logic
- Session CRUD operations (get, set, delete, list)
- TTL handling
- Error handling on Redis failures
- Failover behavior when Sentinel promotes new master

### Required Tests

#### 1. Basic CRUD Operations

```typescript
// redis-session-store.spec.ts

describe('RedisSessionStore', () => {
  describe('session operations', () => {
    it('should create a new session', async () => {
      const store = new RedisSessionStore(redisClient);
      const session = await store.create('user@example.com', { workspace: 'test' });
      expect(session.id).toBeDefined();
      expect(session.userId).toBe('user@example.com');
    });

    it('should retrieve existing session', async () => {
      const store = new RedisSessionStore(redisClient);
      const created = await store.create('user@example.com', {});
      const retrieved = await store.get(created.id);
      expect(retrieved).toEqual(created);
    });

    it('should delete session', async () => {
      const store = new RedisSessionStore(redisClient);
      const session = await store.create('user@example.com', {});
      await store.delete(session.id);
      const retrieved = await store.get(session.id);
      expect(retrieved).toBeNull();
    });

    it('should list sessions by user', async () => {
      const store = new RedisSessionStore(redisClient);
      await store.create('user@example.com', {});
      await store.create('user@example.com', {});
      const sessions = await store.listByUser('user@example.com');
      expect(sessions.length).toBe(2);
    });
  });
});
```

#### 2. TTL and Expiration

```typescript
describe('TTL handling', () => {
  it('should set TTL on session creation', async () => {
    const store = new RedisSessionStore(redisClient, { ttl: 3600 });
    const session = await store.create('user@example.com', {});
    const ttl = await redisClient.ttl(`session:${session.id}`);
    expect(ttl).toBeGreaterThan(3500);
    expect(ttl).toBeLessThanOrEqual(3600);
  });

  it('should refresh TTL on access', async () => {
    const store = new RedisSessionStore(redisClient, { ttl: 3600, refreshOnAccess: true });
    const session = await store.create('user@example.com', {});
    await new Promise(r => setTimeout(r, 1000));
    await store.get(session.id);
    const ttl = await redisClient.ttl(`session:${session.id}`);
    expect(ttl).toBeGreaterThan(3590);
  });
});
```

#### 3. Error Handling

```typescript
describe('error handling', () => {
  it('should throw on connection failure', async () => {
    const badClient = createClient({ url: 'redis://nonexistent:6379' });
    const store = new RedisSessionStore(badClient);
    await expect(store.create('user@example.com', {})).rejects.toThrow();
  });

  it('should handle Redis command timeout', async () => {
    // Mock Redis to simulate timeout
    const store = new RedisSessionStore(mockRedisWithTimeout);
    await expect(store.get('some-id')).rejects.toThrow(/timeout/i);
  });

  it('should recover after reconnection', async () => {
    // Simulate disconnect and reconnect
  });
});
```

#### 4. Concurrent Access

```typescript
describe('concurrent access', () => {
  it('should handle concurrent creates without race condition', async () => {
    const store = new RedisSessionStore(redisClient);
    const promises = Array.from({ length: 10 }, (_, i) =>
      store.create(`user${i}@example.com`, {})
    );
    const sessions = await Promise.all(promises);
    const ids = sessions.map(s => s.id);
    const uniqueIds = new Set(ids);
    expect(uniqueIds.size).toBe(10); // All unique
  });
});
```

### Test Infrastructure

```typescript
// tests/helpers/redis-test-helper.ts
import { createClient } from 'redis';

export async function createTestRedisClient() {
  const client = createClient({ url: process.env.REDIS_TEST_URL || 'redis://localhost:6379' });
  await client.connect();
  return client;
}

export async function flushTestRedis(client: RedisClient) {
  await client.flushDb();
}
```

### Definition of Done

- [ ] `redis-session-store.spec.ts` created with 15+ test cases
- [ ] CRUD operations tested
- [ ] TTL handling tested
- [ ] Error handling tested
- [ ] Concurrent access tested
- [ ] CI runs tests with Redis container
- [ ] Code coverage >80% for redis-session-store.ts

### Cross-References

- Parent: #982 (QA EPIC)
- Related: #957 (Redis HA)
