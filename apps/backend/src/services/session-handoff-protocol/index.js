#!/usr/bin/env node
// @file        apps/backend/src/services/session-handoff-protocol/index.ts
// @module      collaboration/session-handoff-protocol
// @description Live session ownership transfer protocol with pending/accepted/rejected states
// @owner       collab-1.4
// @status      active
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
export class SessionHandoffProtocolService extends EventEmitter {
    constructor(pool) {
        super();
        this.logger = getLogger('SessionHandoffProtocolService');
        this.pool = pool;
    }
    async initialize() {
        await this.createTables();
    }
    async createTables() {
        const client = await this.pool.connect();
        try {
            await client.query(`
        CREATE TABLE IF NOT EXISTS session_handoff_protocols (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          session_id TEXT NOT NULL,
          current_owner_id TEXT NOT NULL,
          target_owner_id TEXT NOT NULL,
          state TEXT NOT NULL CHECK (state IN ('pending', 'accepted', 'rejected', 'expired', 'completed')),
          reason TEXT,
          expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
          accepted_at TIMESTAMP WITH TIME ZONE,
          rejected_at TIMESTAMP WITH TIME ZONE,
          completed_at TIMESTAMP WITH TIME ZONE,
          created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);
            await client.query(`
        CREATE INDEX IF NOT EXISTS idx_session_handoff_protocols_session
        ON session_handoff_protocols(session_id, state, created_at DESC)
      `);
            await client.query(`
        CREATE INDEX IF NOT EXISTS idx_session_handoff_protocols_target
        ON session_handoff_protocols(target_owner_id, state)
      `);
        }
        finally {
            client.release();
        }
    }
    async startHandoff(input) {
        const client = await this.pool.connect();
        try {
            const ttlMinutes = input.ttlMinutes ?? 30;
            const expiresAt = new Date(Date.now() + ttlMinutes * 60 * 1000);
            const result = await client.query(`
          INSERT INTO session_handoff_protocols (session_id, current_owner_id, target_owner_id, state, reason, expires_at)
          VALUES ($1, $2, $3, 'pending', $4, $5)
          RETURNING id, session_id, current_owner_id, target_owner_id, state, reason, expires_at, accepted_at, rejected_at, completed_at, created_at, updated_at
        `, [input.sessionId, input.currentOwnerId, input.targetOwnerId, input.reason || null, expiresAt]);
            const protocol = this.rowToProtocol(result.rows[0]);
            this.emit('handoff-started', protocol);
            return protocol;
        }
        finally {
            client.release();
        }
    }
    async acceptHandoff(protocolId, acceptedBy) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`
          UPDATE session_handoff_protocols
          SET state = 'accepted',
              current_owner_id = $2,
              accepted_at = CURRENT_TIMESTAMP,
              updated_at = CURRENT_TIMESTAMP
          WHERE id = $1 AND target_owner_id = $2 AND state = 'pending'
          RETURNING id, session_id, current_owner_id, target_owner_id, state, reason, expires_at, accepted_at, rejected_at, completed_at, created_at, updated_at
        `, [protocolId, acceptedBy]);
            if (result.rows.length === 0) {
                throw new Error(`Handoff ${protocolId} not found or not acceptably pending`);
            }
            const protocol = this.rowToProtocol(result.rows[0]);
            this.emit('handoff-accepted', protocol);
            return protocol;
        }
        finally {
            client.release();
        }
    }
    async rejectHandoff(protocolId, rejectedBy) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`
          UPDATE session_handoff_protocols
          SET state = 'rejected',
              rejected_at = CURRENT_TIMESTAMP,
              updated_at = CURRENT_TIMESTAMP
          WHERE id = $1 AND target_owner_id = $2 AND state = 'pending'
          RETURNING id, session_id, current_owner_id, target_owner_id, state, reason, expires_at, accepted_at, rejected_at, completed_at, created_at, updated_at
        `, [protocolId, rejectedBy]);
            if (result.rows.length === 0) {
                throw new Error(`Handoff ${protocolId} not found or not pending`);
            }
            const protocol = this.rowToProtocol(result.rows[0]);
            this.emit('handoff-rejected', protocol);
            return protocol;
        }
        finally {
            client.release();
        }
    }
    async completeHandoff(protocolId) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`
          UPDATE session_handoff_protocols
          SET state = 'completed',
              completed_at = CURRENT_TIMESTAMP,
              updated_at = CURRENT_TIMESTAMP
          WHERE id = $1 AND state IN ('accepted', 'pending')
          RETURNING id, session_id, current_owner_id, target_owner_id, state, reason, expires_at, accepted_at, rejected_at, completed_at, created_at, updated_at
        `, [protocolId]);
            if (result.rows.length === 0) {
                throw new Error(`Handoff ${protocolId} cannot be completed`);
            }
            const protocol = this.rowToProtocol(result.rows[0]);
            this.emit('handoff-completed', protocol);
            return protocol;
        }
        finally {
            client.release();
        }
    }
    async getHandoff(protocolId) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT id, session_id, current_owner_id, target_owner_id, state, reason, expires_at, accepted_at, rejected_at, completed_at, created_at, updated_at FROM session_handoff_protocols WHERE id = $1`, [protocolId]);
            if (result.rows.length === 0)
                return null;
            return this.rowToProtocol(result.rows[0]);
        }
        finally {
            client.release();
        }
    }
    async listHandoffs(sessionId) {
        const client = await this.pool.connect();
        try {
            const params = [];
            const whereClause = sessionId ? 'WHERE session_id = $1' : '';
            if (sessionId)
                params.push(sessionId);
            const result = await client.query(`
          SELECT id, session_id, current_owner_id, target_owner_id, state, reason, expires_at, accepted_at, rejected_at, completed_at, created_at, updated_at
          FROM session_handoff_protocols
          ${whereClause}
          ORDER BY created_at DESC
        `, params);
            return result.rows.map(row => this.rowToProtocol(row));
        }
        finally {
            client.release();
        }
    }
    async expireStaleHandoffs() {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`
          UPDATE session_handoff_protocols
          SET state = 'expired',
              updated_at = CURRENT_TIMESTAMP
          WHERE state = 'pending' AND expires_at <= CURRENT_TIMESTAMP
        `);
            return result.rowCount || 0;
        }
        finally {
            client.release();
        }
    }
    rowToProtocol(row) {
        return {
            id: row.id,
            sessionId: row.session_id,
            currentOwnerId: row.current_owner_id,
            targetOwnerId: row.target_owner_id,
            state: row.state,
            reason: row.reason,
            expiresAt: row.expires_at,
            acceptedAt: row.accepted_at,
            rejectedAt: row.rejected_at,
            completedAt: row.completed_at,
            createdAt: row.created_at,
            updatedAt: row.updated_at
        };
    }
}
export async function initializeSessionHandoffProtocolRoutes(service) {
    const { Router } = require('express');
    const router = Router();
    const logger = getLogger('SessionHandoffProtocolRoutes');
    router.post('/api/session-handoff/protocols', async (req, res) => {
        try {
            const { sessionId, currentOwnerId, targetOwnerId, reason, ttlMinutes } = req.body;
            const protocol = await service.startHandoff({ sessionId, currentOwnerId, targetOwnerId, reason, ttlMinutes });
            res.status(201).json(protocol);
        }
        catch (error) {
            logger.error('Failed to start session handoff', error);
            res.status(500).json({ error: 'Failed to start session handoff' });
        }
    });
    router.post('/api/session-handoff/protocols/:protocolId/accept', async (req, res) => {
        try {
            const { protocolId } = req.params;
            const { acceptedBy } = req.body;
            const protocol = await service.acceptHandoff(protocolId, acceptedBy);
            res.json(protocol);
        }
        catch (error) {
            logger.error('Failed to accept session handoff', error);
            res.status(400).json({ error: 'Failed to accept session handoff' });
        }
    });
    router.post('/api/session-handoff/protocols/:protocolId/reject', async (req, res) => {
        try {
            const { protocolId } = req.params;
            const { rejectedBy } = req.body;
            const protocol = await service.rejectHandoff(protocolId, rejectedBy);
            res.json(protocol);
        }
        catch (error) {
            logger.error('Failed to reject session handoff', error);
            res.status(400).json({ error: 'Failed to reject session handoff' });
        }
    });
    router.post('/api/session-handoff/protocols/:protocolId/complete', async (req, res) => {
        try {
            const protocol = await service.completeHandoff(req.params.protocolId);
            res.json(protocol);
        }
        catch (error) {
            logger.error('Failed to complete session handoff', error);
            res.status(400).json({ error: 'Failed to complete session handoff' });
        }
    });
    router.get('/api/session-handoff/protocols/:protocolId', async (req, res) => {
        try {
            const protocol = await service.getHandoff(req.params.protocolId);
            if (!protocol) {
                res.status(404).json({ error: 'Session handoff not found' });
                return;
            }
            res.json(protocol);
        }
        catch (error) {
            logger.error('Failed to fetch session handoff', error);
            res.status(500).json({ error: 'Failed to fetch session handoff' });
        }
    });
    router.get('/api/session-handoff/protocols', async (req, res) => {
        try {
            const sessionId = req.query.sessionId || undefined;
            const protocols = await service.listHandoffs(sessionId);
            res.json(protocols);
        }
        catch (error) {
            logger.error('Failed to list session handoffs', error);
            res.status(500).json({ error: 'Failed to list session handoffs' });
        }
    });
    router.post('/api/session-handoff/expire', async (req, res) => {
        try {
            const count = await service.expireStaleHandoffs();
            res.json({ expired: count });
        }
        catch (error) {
            logger.error('Failed to expire session handoffs', error);
            res.status(500).json({ error: 'Failed to expire session handoffs' });
        }
    });
    return router;
}
//# sourceMappingURL=index.js.map