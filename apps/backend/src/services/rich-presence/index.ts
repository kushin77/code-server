#!/usr/bin/env node
// @file        apps/backend/src/services/rich-presence/index.ts
// @module      collaboration/rich-presence
// @description Redis-backed rich presence service with 4h TTL persistence
// @owner       collab-4.1
// @status      active

import { EventEmitter } from 'events';
import Redis from 'ioredis';
import { getLogger } from '../../lib/logger';

export const RICH_PRESENCE_TTL_SECONDS = 4 * 60 * 60;

export interface RichPresenceUpdateInput {
  userId: string;
  teamId: string;
  filePath: string;
  functionName?: string;
  task?: string;
  customStatus?: string;
  sessionId?: string;
}

export interface RichPresenceRecord {
  userId: string;
  teamId: string;
  filePath: string;
  functionName: string;
  task: string;
  customStatus: string;
  sessionId: string;
  updatedAt: string;
}

export interface RedisLike {
  get(key: string): Promise<string | null>;
  set(key: string, value: string, mode?: string, duration?: number): Promise<unknown>;
  del(key: string): Promise<number>;
  sadd(key: string, ...members: string[]): Promise<number>;
  srem(key: string, ...members: string[]): Promise<number>;
  smembers(key: string): Promise<string[]>;
  expire(key: string, seconds: number): Promise<number>;
}

export class RichPresenceService extends EventEmitter {
  private readonly logger = getLogger('RichPresenceService');
  private readonly redis: RedisLike;

  constructor(redis?: RedisLike) {
    super();
    if (redis) {
      this.redis = redis;
      return;
    }

    const redisUrl = process.env.REDIS_URL || 'redis://localhost:6379';
    this.redis = new Redis(redisUrl);
  }

  async upsertPresence(input: RichPresenceUpdateInput): Promise<RichPresenceRecord> {
    this.require(input.userId, 'userId');
    this.require(input.teamId, 'teamId');
    this.require(input.filePath, 'filePath');

    const record: RichPresenceRecord = {
      userId: input.userId.trim(),
      teamId: input.teamId.trim(),
      filePath: input.filePath.trim(),
      functionName: (input.functionName || '').trim(),
      task: (input.task || '').trim(),
      customStatus: (input.customStatus || '').trim(),
      sessionId: (input.sessionId || '').trim(),
      updatedAt: new Date().toISOString(),
    };

    const userKey = this.userKey(record.userId);
    const teamSetKey = this.teamSetKey(record.teamId);

    await this.redis.set(userKey, JSON.stringify(record), 'EX', RICH_PRESENCE_TTL_SECONDS);
    await this.redis.sadd(teamSetKey, record.userId);
    await this.redis.expire(teamSetKey, RICH_PRESENCE_TTL_SECONDS);

    this.emit('presence-updated', record);
    this.logger.debug('Rich presence updated', { userId: record.userId, teamId: record.teamId, filePath: record.filePath });

    return record;
  }

  async getPresence(userId: string): Promise<RichPresenceRecord | null> {
    this.require(userId, 'userId');

    const payload = await this.redis.get(this.userKey(userId.trim()));
    if (!payload) {
      return null;
    }

    return JSON.parse(payload) as RichPresenceRecord;
  }

  async listTeamPresence(teamId: string): Promise<RichPresenceRecord[]> {
    this.require(teamId, 'teamId');

    const teamUsers = await this.redis.smembers(this.teamSetKey(teamId.trim()));
    if (teamUsers.length === 0) {
      return [];
    }

    const records: RichPresenceRecord[] = [];
    for (const userId of teamUsers) {
      const record = await this.getPresence(userId);
      if (!record) {
        await this.redis.srem(this.teamSetKey(teamId.trim()), userId);
        continue;
      }

      records.push(record);
    }

    records.sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));
    return records;
  }

  async clearPresence(userId: string): Promise<void> {
    this.require(userId, 'userId');

    const existing = await this.getPresence(userId);
    if (!existing) {
      return;
    }

    await this.redis.del(this.userKey(userId.trim()));
    await this.redis.srem(this.teamSetKey(existing.teamId), userId.trim());
    this.emit('presence-cleared', { userId: userId.trim(), teamId: existing.teamId });
  }

  private userKey(userId: string): string {
    return `rich_presence:user:${userId}`;
  }

  private teamSetKey(teamId: string): string {
    return `rich_presence:team:${teamId}:users`;
  }

  private require(value: string | undefined, field: string): void {
    if (!value || value.trim().length === 0) {
      throw new Error(`Missing required field: ${field}`);
    }
  }
}
