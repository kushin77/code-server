#!/usr/bin/env node
// @file        apps/backend/src/services/rich-presence/index.ts
// @module      collaboration/rich-presence
// @description Redis-backed rich presence with team-scoped upserts and TTL-backed listing
// @owner       collab-4.1
// @status      active
import { EventEmitter } from 'events';
import { Router } from 'express';
import { getLogger } from '../../lib/logger';
const DEFAULT_TTL_SECONDS = 4 * 60 * 60;
const asTrimmedString = (value) => {
    if (typeof value !== 'string') {
        return undefined;
    }
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : undefined;
};
const requireText = (value, field) => {
    const text = asTrimmedString(value);
    if (!text) {
        throw new Error(`Missing required field: ${field}`);
    }
    return text;
};
export class RichPresenceService extends EventEmitter {
    constructor(redis, options = {}) {
        super();
        this.redis = redis;
        this.logger = getLogger('RichPresenceService');
        this.ttlSeconds = options.ttlSeconds ?? DEFAULT_TTL_SECONDS;
        this.keyPrefix = options.keyPrefix ?? 'rich-presence:';
    }
    async upsertPresence(input) {
        const teamId = requireText(input.teamId, 'teamId');
        const userId = requireText(input.userId, 'userId');
        const displayName = asTrimmedString(input.displayName) ?? userId;
        const status = input.status ?? 'online';
        const updatedAt = new Date().toISOString();
        const expiresAt = new Date(Date.now() + (this.ttlSeconds * 1000)).toISOString();
        const record = {
            teamId,
            userId,
            displayName,
            status,
            currentFile: input.currentFile ?? null,
            currentFunction: input.currentFunction ?? null,
            currentTask: input.currentTask ?? null,
            customStatus: input.customStatus ?? null,
            updatedAt,
            expiresAt,
        };
        await this.setRecord(this.getPresenceKey(teamId, userId), record);
        await this.addToTeamSet(teamId, userId);
        await this.expireKey(this.getTeamKey(teamId), this.ttlSeconds);
        this.emit('presence-updated', record);
        return record;
    }
    async getPresence(teamId, userId) {
        const normalizedTeamId = requireText(teamId, 'teamId');
        const normalizedUserId = requireText(userId, 'userId');
        const raw = await this.redis.get(this.getPresenceKey(normalizedTeamId, normalizedUserId));
        if (!raw) {
            return null;
        }
        return this.parseRecord(raw);
    }
    async listTeamPresence(teamId) {
        const normalizedTeamId = requireText(teamId, 'teamId');
        const teamKey = this.getTeamKey(normalizedTeamId);
        const members = await this.getTeamMembers(teamKey);
        const results = [];
        for (const userId of members) {
            const presence = await this.getPresence(normalizedTeamId, userId);
            if (!presence) {
                await this.removeFromTeamSet(teamKey, userId);
                continue;
            }
            results.push(presence);
        }
        return results.sort((left, right) => right.updatedAt.localeCompare(left.updatedAt));
    }
    getPresenceKey(teamId, userId) {
        return `${this.keyPrefix}team:${teamId}:user:${userId}`;
    }
    getTeamKey(teamId) {
        return `${this.keyPrefix}team:${teamId}:users`;
    }
    async setRecord(key, record) {
        const serialized = JSON.stringify(record);
        if (typeof this.redis.setEx === 'function') {
            await this.redis.setEx(key, this.ttlSeconds, serialized);
            return;
        }
        if (typeof this.redis.setex === 'function') {
            await this.redis.setex(key, this.ttlSeconds, serialized);
            return;
        }
        await this.redis.set(key, serialized, 'EX', this.ttlSeconds);
    }
    async addToTeamSet(teamId, userId) {
        const teamKey = this.getTeamKey(teamId);
        if (typeof this.redis.sAdd === 'function') {
            await this.redis.sAdd(teamKey, userId);
            return;
        }
        if (typeof this.redis.sadd === 'function') {
            await this.redis.sadd(teamKey, userId);
            return;
        }
        throw new Error('Redis client does not support set membership operations');
    }
    async getTeamMembers(teamKey) {
        if (typeof this.redis.sMembers === 'function') {
            return this.redis.sMembers(teamKey);
        }
        if (typeof this.redis.smembers === 'function') {
            return this.redis.smembers(teamKey);
        }
        throw new Error('Redis client does not support set membership operations');
    }
    async removeFromTeamSet(teamKey, userId) {
        if (typeof this.redis.sRem === 'function') {
            await this.redis.sRem(teamKey, userId);
            return;
        }
        if (typeof this.redis.srem === 'function') {
            await this.redis.srem(teamKey, userId);
        }
    }
    async expireKey(key, ttlSeconds) {
        if (typeof this.redis.expire === 'function') {
            await this.redis.expire(key, ttlSeconds);
        }
    }
    parseRecord(raw) {
        const record = JSON.parse(raw);
        this.assertRecordShape(record);
        return record;
    }
    assertRecordShape(record) {
        if (!record.teamId || !record.userId || !record.displayName || !record.status || !record.updatedAt || !record.expiresAt) {
            throw new Error('Invalid presence record');
        }
    }
}
function toOptionalString(value) {
    const text = asTrimmedString(value);
    return text ?? null;
}
export function initializeRichPresenceRoutes(service) {
    const router = Router();
    const logger = getLogger('RichPresenceRoutes');
    router.post('/api/rich-presence/teams/:teamId/users/:userId', async (req, res) => {
        try {
            const presence = await service.upsertPresence({
                teamId: req.params.teamId,
                userId: req.params.userId,
                displayName: req.body?.displayName,
                status: req.body?.status,
                currentFile: toOptionalString(req.body?.currentFile),
                currentFunction: toOptionalString(req.body?.currentFunction),
                currentTask: toOptionalString(req.body?.currentTask),
                customStatus: toOptionalString(req.body?.customStatus),
            });
            res.status(201).json(presence);
        }
        catch (error) {
            logger.error('Failed to upsert rich presence', { error, params: req.params, body: req.body });
            const message = error instanceof Error ? error.message : 'Failed to upsert presence';
            res.status(400).json({ error: message });
        }
    });
    router.get('/api/rich-presence/teams/:teamId/users/:userId', async (req, res) => {
        try {
            const presence = await service.getPresence(req.params.teamId, req.params.userId);
            if (!presence) {
                res.status(404).json({ error: 'Presence not found' });
                return;
            }
            res.json(presence);
        }
        catch (error) {
            logger.error('Failed to fetch rich presence', { error, params: req.params });
            res.status(500).json({ error: 'Failed to fetch presence' });
        }
    });
    router.get('/api/rich-presence/teams/:teamId/presence', async (req, res) => {
        try {
            const presence = await service.listTeamPresence(req.params.teamId);
            res.json({
                teamId: req.params.teamId,
                count: presence.length,
                presence,
            });
        }
        catch (error) {
            logger.error('Failed to list rich presence', { error, params: req.params });
            res.status(500).json({ error: 'Failed to list presence' });
        }
    });
    return router;
}
//# sourceMappingURL=index.js.map