import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
export class FlowStateDetectionService extends EventEmitter {
    constructor(pool) {
        super();
        this.logger = getLogger('FlowStateDetectionService');
        this.pool = pool;
    }
    async initialize() {
        await this.createTables();
    }
    async createTables() {
        const client = await this.pool.connect();
        try {
            await client.query(`
        CREATE TABLE IF NOT EXISTS flow_activity_log (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id VARCHAR(255) NOT NULL,
          words_per_minute INTEGER NOT NULL,
          switch_count INTEGER NOT NULL DEFAULT 0,
          duration_minutes INTEGER NOT NULL,
          app_name VARCHAR(255) NOT NULL,
          recorded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);
            await client.query(`
        CREATE TABLE IF NOT EXISTS flow_state_snapshots (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id VARCHAR(255) NOT NULL UNIQUE,
          state VARCHAR(32) NOT NULL CHECK (state IN ('flow', 'distracted', 'available')),
          confidence INTEGER NOT NULL,
          reason TEXT NOT NULL,
          updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);
            await client.query(`
        CREATE TABLE IF NOT EXISTS flow_ping_queue (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id VARCHAR(255) NOT NULL,
          message TEXT NOT NULL,
          priority VARCHAR(32) NOT NULL CHECK (priority IN ('low', 'normal', 'high')),
          queued_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          delivered_at TIMESTAMP
        )
      `);
            await client.query(`
        CREATE TABLE IF NOT EXISTS flow_session_events (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id VARCHAR(255) NOT NULL,
          event_type VARCHAR(64) NOT NULL,
          details JSONB,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_flow_activity_user ON flow_activity_log(user_id, recorded_at DESC)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_flow_snapshot_user ON flow_state_snapshots(user_id)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_flow_ping_user ON flow_ping_queue(user_id, delivered_at)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_flow_event_user ON flow_session_events(user_id, created_at DESC)`);
        }
        finally {
            client.release();
        }
    }
    determineState(wordsPerMinute, switchCount, durationMinutes) {
        if (wordsPerMinute >= 40 && switchCount === 0 && durationMinutes >= 5) {
            return {
                state: 'flow',
                confidence: 95,
                reason: 'High typing speed, no context switches, sustained focus'
            };
        }
        if (switchCount >= 2 || durationMinutes < 5) {
            return {
                state: 'distracted',
                confidence: 75,
                reason: 'Frequent switching or short focus window'
            };
        }
        return {
            state: 'available',
            confidence: 55,
            reason: 'Activity below flow threshold'
        };
    }
    async recordActivity(userId, wordsPerMinute, switchCount, durationMinutes, appName = 'editor') {
        const client = await this.pool.connect();
        try {
            await client.query(`INSERT INTO flow_activity_log (user_id, words_per_minute, switch_count, duration_minutes, app_name) VALUES ($1, $2, $3, $4, $5)`, [userId, wordsPerMinute, switchCount, durationMinutes, appName]);
            const flowState = this.determineState(wordsPerMinute, switchCount, durationMinutes);
            await client.query(`
          INSERT INTO flow_state_snapshots (user_id, state, confidence, reason, updated_at)
          VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP)
          ON CONFLICT (user_id)
          DO UPDATE SET state = EXCLUDED.state,
                        confidence = EXCLUDED.confidence,
                        reason = EXCLUDED.reason,
                        updated_at = CURRENT_TIMESTAMP
        `, [userId, flowState.state, flowState.confidence, flowState.reason]);
            const record = {
                userId,
                wordsPerMinute,
                switchCount,
                durationMinutes,
                appName,
                recordedAt: new Date()
            };
            this.emit('activity-recorded', record);
            this.emit('flow-state-detected', { userId, ...flowState });
            return record;
        }
        finally {
            client.release();
        }
    }
    async detectFlowState(userId) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`
          SELECT AVG(words_per_minute) AS avg_wpm,
                 AVG(switch_count) AS avg_switches,
                 AVG(duration_minutes) AS avg_duration
          FROM flow_activity_log
          WHERE user_id = $1 AND recorded_at > NOW() - INTERVAL '1 hour'
        `, [userId]);
            const row = result.rows[0] || {};
            const wpm = Number(row.avg_wpm || 0);
            const switchCount = Number(row.avg_switches || 0);
            const durationMinutes = Number(row.avg_duration || 0);
            const flowState = this.determineState(wpm, switchCount, durationMinutes);
            const snapshot = await client.query(`
          INSERT INTO flow_state_snapshots (user_id, state, confidence, reason, updated_at)
          VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP)
          ON CONFLICT (user_id)
          DO UPDATE SET state = EXCLUDED.state,
                        confidence = EXCLUDED.confidence,
                        reason = EXCLUDED.reason,
                        updated_at = CURRENT_TIMESTAMP
          RETURNING user_id, state, confidence, reason, updated_at
        `, [userId, flowState.state, flowState.confidence, flowState.reason]);
            const snapshotRow = snapshot.rows[0];
            const detected = {
                userId: snapshotRow.user_id,
                state: snapshotRow.state,
                confidence: snapshotRow.confidence,
                reason: snapshotRow.reason,
                updatedAt: snapshotRow.updated_at
            };
            this.emit('flow-state-detected', detected);
            return detected;
        }
        finally {
            client.release();
        }
    }
    async queuePing(userId, message, priority = 'normal') {
        const client = await this.pool.connect();
        try {
            await client.query(`INSERT INTO flow_ping_queue (user_id, message, priority) VALUES ($1, $2, $3)`, [userId, message, priority]);
            const ping = {
                userId,
                message,
                priority,
                queuedAt: new Date(),
                deliveredAt: null
            };
            this.emit('ping-queued', ping);
            return ping;
        }
        finally {
            client.release();
        }
    }
    async getQueuedPings(userId) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT user_id, message, priority, queued_at, delivered_at FROM flow_ping_queue WHERE user_id = $1 AND delivered_at IS NULL ORDER BY queued_at ASC`, [userId]);
            return result.rows.map(row => ({
                userId: row.user_id,
                message: row.message,
                priority: row.priority,
                queuedAt: row.queued_at,
                deliveredAt: row.delivered_at
            }));
        }
        finally {
            client.release();
        }
    }
    async completeFlowSession(userId) {
        const client = await this.pool.connect();
        try {
            const queued = await client.query(`SELECT id FROM flow_ping_queue WHERE user_id = $1 AND delivered_at IS NULL`, [userId]);
            await client.query(`UPDATE flow_ping_queue SET delivered_at = CURRENT_TIMESTAMP WHERE user_id = $1 AND delivered_at IS NULL`, [userId]);
            await client.query(`
          INSERT INTO flow_session_events (user_id, event_type, details)
          VALUES ($1, $2, $3)
        `, [userId, 'flow-session-completed', JSON.stringify({ delivered: queued.rows.length })]);
            await client.query(`
          INSERT INTO flow_state_snapshots (user_id, state, confidence, reason, updated_at)
          VALUES ($1, 'available', 60, 'Flow session completed', CURRENT_TIMESTAMP)
          ON CONFLICT (user_id)
          DO UPDATE SET state = 'available', confidence = 60, reason = 'Flow session completed', updated_at = CURRENT_TIMESTAMP
        `, [userId]);
            const result = {
                delivered: queued.rows.length,
                state: 'available'
            };
            this.emit('flow-session-completed', { userId, delivered: result.delivered });
            return result;
        }
        finally {
            client.release();
        }
    }
    async getFlowState(userId) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT user_id, state, confidence, reason, updated_at FROM flow_state_snapshots WHERE user_id = $1`, [userId]);
            if (result.rows.length === 0)
                return null;
            const row = result.rows[0];
            return {
                userId: row.user_id,
                state: row.state,
                confidence: row.confidence,
                reason: row.reason,
                updatedAt: row.updated_at
            };
        }
        finally {
            client.release();
        }
    }
    async getFlowHistory(userId, limit = 20) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`
          SELECT user_id, words_per_minute, switch_count, duration_minutes, app_name, recorded_at
          FROM flow_activity_log
          WHERE user_id = $1
          ORDER BY recorded_at DESC
          LIMIT $2
        `, [userId, limit]);
            return result.rows.map(row => ({
                userId: row.user_id,
                wordsPerMinute: row.words_per_minute,
                switchCount: row.switch_count,
                durationMinutes: row.duration_minutes,
                appName: row.app_name,
                recordedAt: row.recorded_at
            }));
        }
        finally {
            client.release();
        }
    }
}
export async function initializeFlowStateDetectionRoutes(service) {
    const { Router } = require('express');
    const router = Router();
    const logger = getLogger('FlowStateDetectionRoutes');
    router.post('/api/flow-state/activity', async (req, res) => {
        try {
            const { userId, wordsPerMinute, switchCount, durationMinutes, appName } = req.body;
            const record = await service.recordActivity(userId, wordsPerMinute, switchCount, durationMinutes, appName);
            res.json(record);
        }
        catch (error) {
            logger.error('Failed to record flow activity', error);
            res.status(500).json({ error: 'Failed to record flow activity' });
        }
    });
    router.post('/api/flow-state/detect/:userId', async (req, res) => {
        try {
            const snapshot = await service.detectFlowState(req.params.userId);
            res.json(snapshot);
        }
        catch (error) {
            logger.error('Failed to detect flow state', error);
            res.status(500).json({ error: 'Failed to detect flow state' });
        }
    });
    router.post('/api/flow-state/pings', async (req, res) => {
        try {
            const { userId, message, priority } = req.body;
            const ping = await service.queuePing(userId, message, priority);
            res.json(ping);
        }
        catch (error) {
            logger.error('Failed to queue ping', error);
            res.status(500).json({ error: 'Failed to queue ping' });
        }
    });
    router.get('/api/flow-state/pings/:userId', async (req, res) => {
        try {
            const pings = await service.getQueuedPings(req.params.userId);
            res.json(pings);
        }
        catch (error) {
            logger.error('Failed to get queued pings', error);
            res.status(500).json({ error: 'Failed to get queued pings' });
        }
    });
    router.get('/api/flow-state/:userId', async (req, res) => {
        try {
            const snapshot = await service.getFlowState(req.params.userId);
            if (!snapshot) {
                res.status(404).json({ error: 'Flow state not found' });
                return;
            }
            res.json(snapshot);
        }
        catch (error) {
            logger.error('Failed to get flow state', error);
            res.status(500).json({ error: 'Failed to get flow state' });
        }
    });
    router.post('/api/flow-state/complete/:userId', async (req, res) => {
        try {
            const result = await service.completeFlowSession(req.params.userId);
            res.json(result);
        }
        catch (error) {
            logger.error('Failed to complete flow session', error);
            res.status(500).json({ error: 'Failed to complete flow session' });
        }
    });
    router.get('/api/flow-state/history/:userId', async (req, res) => {
        try {
            const limit = parseInt(req.query.limit) || 20;
            const history = await service.getFlowHistory(req.params.userId, limit);
            res.json(history);
        }
        catch (error) {
            logger.error('Failed to get flow history', error);
            res.status(500).json({ error: 'Failed to get flow history' });
        }
    });
    return router;
}
//# sourceMappingURL=index.js.map