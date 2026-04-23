#!/usr/bin/env node
// @file        apps/backend/src/services/auth/__tests__/jwt-redis-cache.test.ts
// @module      services/auth/__tests__
// @description Unit tests for Redis-backed JWT and credential cache
// @owner       Infrastructure Team
// @status      ACTIVE
import { beforeEach, describe, expect, it } from 'vitest';
import { JwtRedisCache } from '../jwt-redis-cache';
class MockRedis {
    constructor() {
        this.values = new Map();
    }
    async set(key, value) {
        this.values.set(key, value);
        return 'OK';
    }
    async setex(key, ttlSeconds, value) {
        void ttlSeconds;
        this.values.set(key, value);
        return 'OK';
    }
    async get(key) {
        return this.values.get(key) ?? null;
    }
    async del(...keys) {
        let deleted = 0;
        for (const key of keys) {
            if (this.values.delete(key)) {
                deleted += 1;
            }
        }
        return deleted;
    }
    async scan(_cursor, _matchToken, pattern, _countToken, _count) {
        const regex = new RegExp(`^${pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\\\*/g, '.*')}$`);
        const matches = [...this.values.keys()].filter((key) => regex.test(key));
        return ['0', matches];
    }
}
describe('JwtRedisCache', () => {
    let redis;
    let cache;
    beforeEach(() => {
        redis = new MockRedis();
        cache = new JwtRedisCache(redis, 'jwt:', 1800);
    });
    it('stores and retrieves session-scoped service credentials', async () => {
        await cache.storeSessionCredentials('session-123', 'db', 'client-1', 'secret-1', 900);
        expect(await cache.getSessionCredentials('session-123', 'db')).toEqual({
            client_id: 'client-1',
            client_secret: 'secret-1',
            session_id: 'session-123',
            service_name: 'db',
        });
    });
    it('revokes every credential lease for a session', async () => {
        await cache.storeSessionCredentials('session-123', 'db', 'client-1', 'secret-1', 900);
        await cache.storeSessionCredentials('session-123', 'cloud', 'client-2', 'secret-2', 900);
        await cache.storeServiceCredentials('shared', 'client-3', 'secret-3');
        const revokedCount = await cache.revokeSessionCredentials('session-123');
        expect(revokedCount).toBe(2);
        expect(await cache.getSessionCredentials('session-123', 'db')).toBeNull();
        expect(await cache.getSessionCredentials('session-123', 'cloud')).toBeNull();
        expect(await cache.getServiceCredentials('shared')).toEqual({
            client_id: 'client-3',
            client_secret: 'secret-3',
        });
    });
    it('keeps legacy service credentials intact', async () => {
        await cache.storeServiceCredentials('session-broker', 'client-4', 'secret-4');
        expect(await cache.getServiceCredentials('session-broker')).toEqual({
            client_id: 'client-4',
            client_secret: 'secret-4',
        });
    });
});
//# sourceMappingURL=jwt-redis-cache.test.js.map