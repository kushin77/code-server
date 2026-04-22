import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
export class CalendarIntegrationService extends EventEmitter {
    constructor(pool) {
        super();
        this.logger = getLogger('CalendarIntegrationService');
        this.pool = pool;
    }
    async initialize() {
        await this.createTables();
    }
    async createTables() {
        const client = await this.pool.connect();
        try {
            await client.query(`
        CREATE TABLE IF NOT EXISTS calendar_integrations (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id VARCHAR(255) NOT NULL,
          provider VARCHAR(32) NOT NULL CHECK (provider IN ('google', 'outlook')),
          email VARCHAR(255) NOT NULL,
          access_token TEXT NOT NULL,
          refresh_token TEXT NOT NULL,
          scopes JSONB NOT NULL DEFAULT '[]'::jsonb,
          status VARCHAR(32) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'needs_refresh', 'disconnected')),
          last_synced_at TIMESTAMP,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(user_id, provider)
        )
      `);
            await client.query(`
        CREATE TABLE IF NOT EXISTS calendar_free_busy_windows (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id VARCHAR(255) NOT NULL,
          provider VARCHAR(32) NOT NULL CHECK (provider IN ('google', 'outlook')),
          start_time TIMESTAMP NOT NULL,
          end_time TIMESTAMP NOT NULL,
          is_busy BOOLEAN NOT NULL DEFAULT true,
          summary TEXT,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);
            await client.query(`
        CREATE TABLE IF NOT EXISTS calendar_presence_cards (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id VARCHAR(255) NOT NULL UNIQUE,
          state VARCHAR(32) NOT NULL CHECK (state IN ('available', 'busy', 'in-meeting')),
          message TEXT NOT NULL,
          busy_until TIMESTAMP,
          updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);
            await client.query(`
        CREATE TABLE IF NOT EXISTS calendar_sync_audit (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id VARCHAR(255) NOT NULL,
          provider VARCHAR(32) NOT NULL CHECK (provider IN ('google', 'outlook')),
          action VARCHAR(64) NOT NULL,
          created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      `);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_calendar_integrations_user ON calendar_integrations(user_id, provider)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_calendar_free_busy_user ON calendar_free_busy_windows(user_id, start_time DESC)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_calendar_presence_user ON calendar_presence_cards(user_id)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_calendar_audit_user ON calendar_sync_audit(user_id, created_at DESC)`);
        }
        finally {
            client.release();
        }
    }
    async connectIntegration(userId, provider, email, accessToken, refreshToken, scopes = []) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`
          INSERT INTO calendar_integrations (user_id, provider, email, access_token, refresh_token, scopes, status, last_synced_at)
          VALUES ($1, $2, $3, $4, $5, $6, 'active', CURRENT_TIMESTAMP)
          ON CONFLICT (user_id, provider)
          DO UPDATE SET email = EXCLUDED.email,
                        access_token = EXCLUDED.access_token,
                        refresh_token = EXCLUDED.refresh_token,
                        scopes = EXCLUDED.scopes,
                        status = 'active',
                        last_synced_at = CURRENT_TIMESTAMP,
                        updated_at = CURRENT_TIMESTAMP
          RETURNING user_id, provider, email, status, scopes, last_synced_at, created_at
        `, [userId, provider, email, accessToken, refreshToken, JSON.stringify(scopes)]);
            await client.query(`INSERT INTO calendar_sync_audit (user_id, provider, action) VALUES ($1, $2, $3)`, [userId, provider, 'connect']);
            const row = result.rows[0];
            this.emit('calendar-connected', { userId, provider, email });
            return {
                userId: row.user_id,
                provider: row.provider,
                email: row.email,
                status: row.status,
                scopes: row.scopes || [],
                lastSyncedAt: row.last_synced_at,
                createdAt: row.created_at
            };
        }
        finally {
            client.release();
        }
    }
    async listIntegrations(userId) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`
          SELECT user_id, provider, email, status, scopes, last_synced_at, created_at
          FROM calendar_integrations
          WHERE user_id = $1
          ORDER BY provider
        `, [userId]);
            return result.rows.map(row => ({
                userId: row.user_id,
                provider: row.provider,
                email: row.email,
                status: row.status,
                scopes: row.scopes || [],
                lastSyncedAt: row.last_synced_at,
                createdAt: row.created_at
            }));
        }
        finally {
            client.release();
        }
    }
    async recordFreeBusyWindow(userId, provider, startTime, endTime, summary, isBusy = true) {
        const client = await this.pool.connect();
        try {
            await client.query(`
          INSERT INTO calendar_free_busy_windows (user_id, provider, start_time, end_time, is_busy, summary)
          VALUES ($1, $2, $3, $4, $5, $6)
        `, [userId, provider, startTime, endTime, isBusy, summary]);
            const window = {
                userId,
                provider,
                startTime,
                endTime,
                isBusy,
                summary
            };
            this.emit('free-busy-recorded', window);
            return window;
        }
        finally {
            client.release();
        }
    }
    async getFreeBusyWindows(userId, startTime, endTime) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`
          SELECT user_id, provider, start_time, end_time, is_busy, summary
          FROM calendar_free_busy_windows
          WHERE user_id = $1 AND start_time >= $2 AND end_time <= $3
          ORDER BY start_time ASC
        `, [userId, startTime, endTime]);
            return result.rows.map(row => ({
                userId: row.user_id,
                provider: row.provider,
                startTime: row.start_time,
                endTime: row.end_time,
                isBusy: row.is_busy,
                summary: row.summary
            }));
        }
        finally {
            client.release();
        }
    }
    async syncPresenceCard(userId) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`
          SELECT start_time, end_time, summary, provider
          FROM calendar_free_busy_windows
          WHERE user_id = $1 AND is_busy = true AND end_time >= CURRENT_TIMESTAMP
          ORDER BY start_time ASC
          LIMIT 1
        `, [userId]);
            const row = result.rows[0];
            const busyUntil = row?.end_time || null;
            const state = busyUntil ? 'in-meeting' : 'available';
            const message = busyUntil
                ? `In meeting until ${new Date(busyUntil).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}`
                : 'Available';
            const upsert = await client.query(`
          INSERT INTO calendar_presence_cards (user_id, state, message, busy_until, updated_at)
          VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP)
          ON CONFLICT (user_id)
          DO UPDATE SET state = EXCLUDED.state,
                        message = EXCLUDED.message,
                        busy_until = EXCLUDED.busy_until,
                        updated_at = CURRENT_TIMESTAMP
          RETURNING user_id, state, message, busy_until, updated_at
        `, [userId, state, message, busyUntil]);
            const cardRow = upsert.rows[0];
            await client.query(`INSERT INTO calendar_sync_audit (user_id, provider, action) VALUES ($1, $2, $3)`, [userId, row?.provider || 'google', 'sync-presence']);
            const card = {
                userId: cardRow.user_id,
                state: cardRow.state,
                message: cardRow.message,
                busyUntil: cardRow.busy_until,
                updatedAt: cardRow.updated_at
            };
            this.emit('presence-synced', card);
            return card;
        }
        finally {
            client.release();
        }
    }
    async getPresenceCard(userId) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT user_id, state, message, busy_until, updated_at FROM calendar_presence_cards WHERE user_id = $1`, [userId]);
            if (result.rows.length === 0)
                return null;
            const row = result.rows[0];
            return {
                userId: row.user_id,
                state: row.state,
                message: row.message,
                busyUntil: row.busy_until,
                updatedAt: row.updated_at
            };
        }
        finally {
            client.release();
        }
    }
    async disconnectIntegration(userId, provider) {
        const client = await this.pool.connect();
        try {
            await client.query(`UPDATE calendar_integrations SET status = 'disconnected', updated_at = CURRENT_TIMESTAMP WHERE user_id = $1 AND provider = $2`, [userId, provider]);
            await client.query(`INSERT INTO calendar_sync_audit (user_id, provider, action) VALUES ($1, $2, $3)`, [userId, provider, 'disconnect']);
            this.emit('calendar-disconnected', { userId, provider });
        }
        finally {
            client.release();
        }
    }
}
export async function initializeCalendarIntegrationRoutes(service) {
    const { Router } = require('express');
    const router = Router();
    const logger = getLogger('CalendarIntegrationRoutes');
    router.post('/api/calendar/integrations', async (req, res) => {
        try {
            const { userId, provider, email, accessToken, refreshToken, scopes } = req.body;
            const integration = await service.connectIntegration(userId, provider, email, accessToken, refreshToken, scopes || []);
            res.json(integration);
        }
        catch (error) {
            logger.error('Failed to connect calendar integration', error);
            res.status(500).json({ error: 'Failed to connect calendar integration' });
        }
    });
    router.get('/api/calendar/integrations/:userId', async (req, res) => {
        try {
            const integrations = await service.listIntegrations(req.params.userId);
            res.json(integrations);
        }
        catch (error) {
            logger.error('Failed to list calendar integrations', error);
            res.status(500).json({ error: 'Failed to list calendar integrations' });
        }
    });
    router.post('/api/calendar/free-busy', async (req, res) => {
        try {
            const { userId, provider, startTime, endTime, summary, isBusy } = req.body;
            const window = await service.recordFreeBusyWindow(userId, provider, new Date(startTime), new Date(endTime), summary, isBusy);
            res.json(window);
        }
        catch (error) {
            logger.error('Failed to record free-busy window', error);
            res.status(500).json({ error: 'Failed to record free-busy window' });
        }
    });
    router.get('/api/calendar/free-busy/:userId', async (req, res) => {
        try {
            const startTime = new Date(req.query.startTime || Date.now());
            const endTime = new Date(req.query.endTime || Date.now() + 86400000);
            const windows = await service.getFreeBusyWindows(req.params.userId, startTime, endTime);
            res.json(windows);
        }
        catch (error) {
            logger.error('Failed to fetch free-busy windows', error);
            res.status(500).json({ error: 'Failed to fetch free-busy windows' });
        }
    });
    router.post('/api/calendar/presence/:userId', async (req, res) => {
        try {
            const card = await service.syncPresenceCard(req.params.userId);
            res.json(card);
        }
        catch (error) {
            logger.error('Failed to sync presence card', error);
            res.status(500).json({ error: 'Failed to sync presence card' });
        }
    });
    router.get('/api/calendar/presence/:userId', async (req, res) => {
        try {
            const card = await service.getPresenceCard(req.params.userId);
            if (!card) {
                res.status(404).json({ error: 'Presence card not found' });
                return;
            }
            res.json(card);
        }
        catch (error) {
            logger.error('Failed to get presence card', error);
            res.status(500).json({ error: 'Failed to get presence card' });
        }
    });
    router.delete('/api/calendar/integrations/:userId/:provider', async (req, res) => {
        try {
            await service.disconnectIntegration(req.params.userId, req.params.provider);
            res.json({ success: true });
        }
        catch (error) {
            logger.error('Failed to disconnect calendar integration', error);
            res.status(500).json({ error: 'Failed to disconnect calendar integration' });
        }
    });
    return router;
}
//# sourceMappingURL=index.js.map