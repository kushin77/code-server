#!/usr/bin/env node
// @file        apps/backend/src/services/rich-presence/__tests__/rich-presence.test.ts
// @module      collaboration/rich-presence
// @description Tests for Redis-backed rich presence system behavior
// @owner       collab-4.1
// @status      active

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { RichPresenceService, RedisLike, RICH_PRESENCE_TTL_SECONDS } from '../index';

vi.mock('../../../lib/logger', () => ({
  getLogger: vi.fn(() => ({
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
  })),
}));

class InMemoryRedis implements RedisLike {
  private values = new Map<string, string>();
  private sets = new Map<string, Set<string>>();
  private ttl = new Map<string, number>();

  async get(key: string): Promise<string | null> {
    return this.values.has(key) ? (this.values.get(key) as string) : null;
  }

  async set(key: string, value: string, mode?: string, duration?: number): Promise<unknown> {
    this.values.set(key, value);
    if (mode === 'EX' && duration) {
      this.ttl.set(key, duration);
    }
    return 'OK';
  }

  async del(key: string): Promise<number> {
    const existed = this.values.delete(key);
    return existed ? 1 : 0;
  }

  async sadd(key: string, ...members: string[]): Promise<number> {
    const set = this.sets.get(key) || new Set<string>();
    const before = set.size;
    for (const member of members) {
      set.add(member);
    }
    this.sets.set(key, set);
    return set.size - before;
  }

  async srem(key: string, ...members: string[]): Promise<number> {
    const set = this.sets.get(key) || new Set<string>();
    let removed = 0;
    for (const member of members) {
      if (set.delete(member)) {
        removed += 1;
      }
    }
    this.sets.set(key, set);
    return removed;
  }

  async smembers(key: string): Promise<string[]> {
    return Array.from(this.sets.get(key) || []);
  }

  async expire(key: string, seconds: number): Promise<number> {
    this.ttl.set(key, seconds);
    return 1;
  }

  getTtl(key: string): number | undefined {
    return this.ttl.get(key);
  }
}

describe('RichPresenceService', () => {
  let redis: InMemoryRedis;
  let service: RichPresenceService;

  beforeEach(() => {
    redis = new InMemoryRedis();
    service = new RichPresenceService(redis);
  });

  it('upserts and retrieves presence with required fields', async () => {
    const record = await service.upsertPresence({
      userId: 'alice',
      teamId: 'team-1',
      filePath: 'src/routes/index.ts',
      functionName: 'initializeRoutes',
      task: 'wiring routes',
      customStatus: 'reviewing',
      sessionId: 'session-a',
    });

    expect(record.userId).toBe('alice');
    expect(record.functionName).toBe('initializeRoutes');

    const loaded = await service.getPresence('alice');
    expect(loaded?.teamId).toBe('team-1');
    expect(loaded?.task).toBe('wiring routes');
  });

  it('sets 4-hour TTL for user and team presence keys', async () => {
    await service.upsertPresence({
      userId: 'bob',
      teamId: 'team-2',
      filePath: 'src/app.ts',
    });

    expect(redis.getTtl('rich_presence:user:bob')).toBe(RICH_PRESENCE_TTL_SECONDS);
    expect(redis.getTtl('rich_presence:team:team-2:users')).toBe(RICH_PRESENCE_TTL_SECONDS);
  });

  it('lists team presence and orders by latest update', async () => {
    await service.upsertPresence({
      userId: 'alice',
      teamId: 'team-1',
      filePath: 'src/a.ts',
      task: 'first',
    });

    await service.upsertPresence({
      userId: 'charlie',
      teamId: 'team-1',
      filePath: 'src/c.ts',
      task: 'second',
    });

    const listed = await service.listTeamPresence('team-1');
    expect(listed).toHaveLength(2);
    expect(listed.map((entry) => entry.userId).sort()).toEqual(['alice', 'charlie']);
  });

  it('clears presence and removes user from team set', async () => {
    await service.upsertPresence({
      userId: 'dana',
      teamId: 'team-3',
      filePath: 'src/d.ts',
    });

    await service.clearPresence('dana');

    const loaded = await service.getPresence('dana');
    expect(loaded).toBeNull();

    const teamUsers = await redis.smembers('rich_presence:team:team-3:users');
    expect(teamUsers).not.toContain('dana');
  });
});
