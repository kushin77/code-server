#!/usr/bin/env node
// @file        apps/backend/src/services/rich-presence/__tests__/rich-presence.test.ts
// @module      collaboration/rich-presence
// @description Tests for Redis-backed rich presence persistence and listing
// @owner       collab-4.1
// @status      active
import express from 'express';
import request from 'supertest';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { initializeRichPresenceRoutes, RichPresenceService } from '../index';
vi.mock('../../../lib/logger', () => ({
    getLogger: vi.fn(() => ({
        info: vi.fn(),
        error: vi.fn(),
        warn: vi.fn(),
        debug: vi.fn(),
    })),
}));
class MockRedis {
    constructor() {
        this.values = new Map();
        this.expirations = new Map();
        this.sets = new Map();
    }
    async get(key) {
        this.cleanupExpired(key);
        return this.values.get(key) ?? null;
    }
    async set(key, value, ...args) {
        this.values.set(key, value);
        this.applyExpiration(key, args);
        return 'OK';
    }
    async setEx(key, seconds, value) {
        this.values.set(key, value);
        this.expirations.set(key, Date.now() + (seconds * 1000));
        return 'OK';
    }
    async del(key) {
        const deleted = this.values.delete(key) ? 1 : 0;
        this.expirations.delete(key);
        this.sets.delete(key);
        return deleted;
    }
    async sAdd(key, ...members) {
        const set = this.sets.get(key) ?? new Set();
        members.forEach((member) => set.add(member));
        this.sets.set(key, set);
        return set.size;
    }
    async sMembers(key) {
        this.cleanupExpired(key);
        return Array.from(this.sets.get(key) ?? []);
    }
    async sRem(key, ...members) {
        const set = this.sets.get(key);
        if (!set) {
            return 0;
        }
        let removed = 0;
        for (const member of members) {
            if (set.delete(member)) {
                removed += 1;
            }
        }
        return removed;
    }
    async expire(key, seconds) {
        if (!this.values.has(key) && !this.sets.has(key)) {
            return 0;
        }
        this.expirations.set(key, Date.now() + (seconds * 1000));
        return 1;
    }
    applyExpiration(key, args) {
        const modeIndex = args.findIndex((value) => value === 'EX');
        if (modeIndex >= 0) {
            const ttl = Number(args[modeIndex + 1]);
            if (Number.isFinite(ttl)) {
                this.expirations.set(key, Date.now() + (ttl * 1000));
            }
        }
    }
    cleanupExpired(key) {
        const expiresAt = this.expirations.get(key);
        if (expiresAt !== undefined && Date.now() >= expiresAt) {
            this.values.delete(key);
            this.expirations.delete(key);
            this.sets.delete(key);
        }
    }
}
describe('RichPresenceService', () => {
    let redis;
    let service;
    beforeEach(() => {
        vi.useFakeTimers();
        vi.setSystemTime(new Date('2026-04-22T00:00:00.000Z'));
        redis = new MockRedis();
        service = new RichPresenceService(redis);
    });
    afterEach(() => {
        vi.useRealTimers();
    });
    it('upserts and fetches a team-scoped presence record with ttl', async () => {
        const record = await service.upsertPresence({
            teamId: 'team-1',
            userId: 'alice',
            displayName: 'Alice Chen',
            status: 'online',
            currentFile: 'src/app.ts',
            currentFunction: 'run',
            currentTask: 'Pair review',
            customStatus: 'Working with Bob',
        });
        expect(record.teamId).toBe('team-1');
        expect(record.userId).toBe('alice');
        expect(record.expiresAt).toBe(new Date(Date.now() + (4 * 60 * 60 * 1000)).toISOString());
        const fetched = await service.getPresence('team-1', 'alice');
        expect(fetched).toMatchObject({
            teamId: 'team-1',
            userId: 'alice',
            displayName: 'Alice Chen',
            status: 'online',
            currentFile: 'src/app.ts',
            currentFunction: 'run',
            currentTask: 'Pair review',
            customStatus: 'Working with Bob',
        });
    });
    it('lists only active team members after ttl expiry', async () => {
        await service.upsertPresence({
            teamId: 'team-1',
            userId: 'alice',
            displayName: 'Alice Chen',
            status: 'online',
            currentFile: 'src/app.ts',
        });
        await vi.advanceTimersByTimeAsync(2 * 60 * 60 * 1000);
        await service.upsertPresence({
            teamId: 'team-1',
            userId: 'bob',
            displayName: 'Bob Kumar',
            status: 'away',
            currentTask: 'Reviewing docs',
        });
        await vi.advanceTimersByTimeAsync((2 * 60 * 60 * 1000) + 1000);
        expect(await service.getPresence('team-1', 'alice')).toBeNull();
        expect(await service.getPresence('team-1', 'bob')).not.toBeNull();
        const presence = await service.listTeamPresence('team-1');
        expect(presence).toHaveLength(1);
        expect(presence[0]).toMatchObject({
            teamId: 'team-1',
            userId: 'bob',
            displayName: 'Bob Kumar',
            status: 'away',
            currentTask: 'Reviewing docs',
        });
    });
    it('exposes upsert, fetch, and listing routes', async () => {
        const app = express();
        app.use(express.json());
        app.use(initializeRichPresenceRoutes(service));
        await request(app)
            .post('/api/rich-presence/teams/team-1/users/alice')
            .send({
            displayName: 'Alice Chen',
            status: 'online',
            currentFile: 'src/app.ts',
            customStatus: 'Pairing',
        })
            .expect(201)
            .expect((response) => {
            expect(response.body.teamId).toBe('team-1');
            expect(response.body.userId).toBe('alice');
        });
        await request(app)
            .get('/api/rich-presence/teams/team-1/users/alice')
            .expect(200)
            .expect((response) => {
            expect(response.body.displayName).toBe('Alice Chen');
            expect(response.body.customStatus).toBe('Pairing');
        });
        await request(app)
            .get('/api/rich-presence/teams/team-1/presence')
            .expect(200)
            .expect((response) => {
            expect(response.body.teamId).toBe('team-1');
            expect(response.body.count).toBe(1);
            expect(response.body.presence).toHaveLength(1);
        });
    });
});
//# sourceMappingURL=rich-presence.test.js.map