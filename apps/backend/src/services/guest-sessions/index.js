#!/usr/bin/env node
// @file        apps/backend/src/services/guest-sessions/index.ts
// @module      collaboration/guest-sessions
// @description Guest session management with time-limited read-only links and path scoping
// @owner       collab-5.5
// @status      active
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
export class GuestSessionService extends EventEmitter {
    constructor(pool, config = {}) {
        super();
        this.logger = getLogger('GuestSessionService') ?? console;
        this.initialized = false;
        this.pool = pool;
        this.config = {
            defaultTtlMinutes: config.defaultTtlMinutes || 60,
            tokenLength: config.tokenLength || 32,
            maxActiveSessions: config.maxActiveSessions || 10,
        };
    }
    async initialize() {
        if (this.initialized)
            return;
        try {
            await this.createTables();
            this.initialized = true;
            this.logger.info('Guest sessions database schema initialized');
        }
        catch (error) {
            this.logger.error('Failed to initialize guest sessions schema', { error });
            throw error;
        }
    }
    async createTables() {
        const client = await this.pool.connect();
        try {
            await client.query('BEGIN');
            // Guest sessions table
            await client.query(`
        CREATE TABLE IF NOT EXISTS guest_sessions (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id TEXT NOT NULL,
          guest_token TEXT NOT NULL UNIQUE,
          scoped_path TEXT NOT NULL,
          access_level TEXT NOT NULL CHECK (access_level IN ('read', 'read-write')),
          expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
          is_active BOOLEAN DEFAULT true,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);
            // Guest activity log
            await client.query(`
        CREATE TABLE IF NOT EXISTS guest_activity_log (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          guest_session_id UUID NOT NULL REFERENCES guest_sessions(id) ON DELETE CASCADE,
          action TEXT NOT NULL,
          path TEXT NOT NULL,
          ip_address TEXT,
          user_agent TEXT,
          timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);
            // Indexes
            await client.query(`
        CREATE INDEX IF NOT EXISTS idx_guest_sessions_user ON guest_sessions(user_id);
        CREATE INDEX IF NOT EXISTS idx_guest_sessions_token ON guest_sessions(guest_token);
        CREATE INDEX IF NOT EXISTS idx_guest_sessions_active ON guest_sessions(is_active);
        CREATE INDEX IF NOT EXISTS idx_guest_sessions_expires ON guest_sessions(expires_at);
        CREATE INDEX IF NOT EXISTS idx_activity_log_session ON guest_activity_log(guest_session_id);
        CREATE INDEX IF NOT EXISTS idx_activity_log_action ON guest_activity_log(action);
        CREATE INDEX IF NOT EXISTS idx_activity_log_timestamp ON guest_activity_log(timestamp DESC);
      `);
            await client.query('COMMIT');
        }
        catch (error) {
            await client.query('ROLLBACK');
            throw error;
        }
        finally {
            client.release();
        }
    }
    async createGuestSession(userId, scopedPath, ttlMinutes, accessLevel = 'read') {
        const client = await this.pool.connect();
        try {
            // Check active sessions limit
            const activeCount = await client.query(`SELECT COUNT(*) as count FROM guest_sessions WHERE user_id = $1 AND is_active = true`, [userId]);
            if (parseInt(activeCount.rows[0].count, 10) >= this.config.maxActiveSessions) {
                throw new Error(`User ${userId} has reached max active guest sessions (${this.config.maxActiveSessions})`);
            }
            const id = require('crypto').randomUUID();
            const guestToken = this.generateToken();
            const ttl = ttlMinutes || this.config.defaultTtlMinutes;
            const expiresAt = new Date(Date.now() + ttl * 60 * 1000);
            await client.query(`INSERT INTO guest_sessions (id, user_id, guest_token, scoped_path, access_level, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6)`, [id, userId, guestToken, scopedPath, accessLevel, expiresAt]);
            this.logger.info('Guest session created', { guestSessionId: id, userId, scopedPath });
            this.emit('session-created', { id, userId, scopedPath, expiresAt });
            return {
                id,
                userId,
                guestToken,
                scopedPath,
                accessLevel,
                expiresAt,
                isActive: true,
                createdAt: new Date(),
                updatedAt: new Date(),
            };
        }
        catch (error) {
            this.logger.error('Failed to create guest session', { error, userId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async getGuestSession(guestToken) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT * FROM guest_sessions WHERE guest_token = $1 AND is_active = true AND expires_at > NOW()`, [guestToken]);
            if (result.rows.length === 0) {
                return null;
            }
            const row = result.rows[0];
            return {
                id: row.id,
                userId: row.user_id,
                guestToken: row.guest_token,
                scopedPath: row.scoped_path,
                accessLevel: row.access_level,
                expiresAt: new Date(row.expires_at),
                isActive: row.is_active,
                createdAt: new Date(row.created_at),
                updatedAt: new Date(row.updated_at),
            };
        }
        catch (error) {
            this.logger.error('Failed to get guest session', { error, guestToken: guestToken.substring(0, 8) });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async validateGuestAccess(guestToken, requestedPath) {
        const session = await this.getGuestSession(guestToken);
        if (!session) {
            return { allowed: false };
        }
        // Check if requested path is within scoped path
        const normalizedRequested = this.normalizePath(requestedPath);
        const normalizedScoped = this.normalizePath(session.scopedPath);
        if (!normalizedRequested.startsWith(normalizedScoped)) {
            this.logger.warn('Access denied: path outside scope', { guestToken: guestToken.substring(0, 8), requestedPath });
            return { allowed: false };
        }
        return { allowed: true, accessLevel: session.accessLevel };
    }
    async trackActivity(guestToken, action, path, ipAddress, userAgent) {
        const client = await this.pool.connect();
        try {
            const session = await this.getGuestSession(guestToken);
            if (!session) {
                throw new Error(`Invalid guest session: ${guestToken}`);
            }
            const activityId = require('crypto').randomUUID();
            await client.query(`INSERT INTO guest_activity_log (id, guest_session_id, action, path, ip_address, user_agent)
         VALUES ($1, $2, $3, $4, $5, $6)`, [activityId, session.id, action, path, ipAddress || null, userAgent || null]);
            this.logger.debug('Guest activity tracked', { guestSessionId: session.id, action, path });
            this.emit('activity-tracked', { guestSessionId: session.id, action, path, timestamp: new Date() });
        }
        catch (error) {
            this.logger.error('Failed to track activity', { error });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async getUserSessions(userId) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT * FROM guest_sessions WHERE user_id = $1 ORDER BY created_at DESC`, [userId]);
            return result.rows.map(row => ({
                id: row.id,
                userId: row.user_id,
                guestToken: row.guest_token,
                scopedPath: row.scoped_path,
                accessLevel: row.access_level,
                expiresAt: new Date(row.expires_at),
                isActive: row.is_active,
                createdAt: new Date(row.created_at),
                updatedAt: new Date(row.updated_at),
            }));
        }
        catch (error) {
            this.logger.error('Failed to get user sessions', { error, userId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async revokeSession(guestSessionId) {
        const client = await this.pool.connect();
        try {
            await client.query(`UPDATE guest_sessions SET is_active = false, updated_at = NOW() WHERE id = $1`, [guestSessionId]);
            this.logger.info('Guest session revoked', { guestSessionId });
            this.emit('session-revoked', { guestSessionId, timestamp: new Date() });
        }
        catch (error) {
            this.logger.error('Failed to revoke session', { error, guestSessionId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async getSessionActivity(guestSessionId, limit = 50) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT * FROM guest_activity_log WHERE guest_session_id = $1 ORDER BY timestamp DESC LIMIT $2`, [guestSessionId, limit]);
            return result.rows.map(row => ({
                id: row.id,
                guestSessionId: row.guest_session_id,
                action: row.action,
                path: row.path,
                ipAddress: row.ip_address,
                userAgent: row.user_agent,
                timestamp: new Date(row.timestamp),
            }));
        }
        catch (error) {
            this.logger.error('Failed to get session activity', { error, guestSessionId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async cleanupExpiredSessions() {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`UPDATE guest_sessions SET is_active = false WHERE expires_at <= NOW() AND is_active = true RETURNING id`);
            if (result.rows.length > 0) {
                this.logger.info('Expired sessions cleaned up', { count: result.rows.length });
                this.emit('sessions-cleaned', { count: result.rows.length, timestamp: new Date() });
            }
            return result.rows.length;
        }
        catch (error) {
            this.logger.error('Failed to cleanup expired sessions', { error });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async getSessionStats(userId) {
        const client = await this.pool.connect();
        try {
            const activeResult = await client.query(`SELECT COUNT(*) as count FROM guest_sessions WHERE user_id = $1 AND is_active = true AND expires_at > NOW()`, [userId]);
            const totalResult = await client.query(`SELECT COUNT(*) as count FROM guest_sessions WHERE user_id = $1`, [userId]);
            const activityResult = await client.query(`SELECT COUNT(*) as count FROM guest_activity_log
         WHERE guest_session_id IN (SELECT id FROM guest_sessions WHERE user_id = $1)`, [userId]);
            return {
                active: parseInt(activeResult.rows[0].count, 10),
                total: parseInt(totalResult.rows[0].count, 10),
                totalActivity: parseInt(activityResult.rows[0].count, 10),
            };
        }
        catch (error) {
            this.logger.error('Failed to get session stats', { error, userId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    generateToken() {
        return require('crypto')
            .randomBytes(this.config.tokenLength / 2)
            .toString('hex');
    }
    normalizePath(path) {
        // Normalize path: remove trailing slash, resolve . and ..
        return path.replace(/\/$/, '').replace(/\/+/g, '/');
    }
}
//# sourceMappingURL=index.js.map