#!/usr/bin/env node
/**
 * @file        apps/backend/src/services/ide-performance-profiler/index.ts
 * @module      services/developer-experience
 * @description IDE performance profiler with per-extension metrics
 */
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
export class IDEPerformanceProfilerService extends EventEmitter {
    constructor(pool) {
        super();
        this.logger = getLogger('IDEPerformanceProfilerService');
        this.pool = pool;
    }
    async initialize() {
        this.logger.info('Initializing IDEPerformanceProfilerService');
        await this.createTables();
    }
    async createTables() {
        const client = await this.pool.connect();
        try {
            // Create extension_metrics table
            await client.query(`
        CREATE TABLE IF NOT EXISTS extension_metrics (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          extension_id VARCHAR(255) NOT NULL,
          extension_name VARCHAR(255) NOT NULL,
          startup_time_ms FLOAT NOT NULL,
          activation_time_ms FLOAT NOT NULL,
          latency_ms FLOAT NOT NULL,
          health_score FLOAT NOT NULL,
          is_disabled BOOLEAN DEFAULT false,
          disable_reason TEXT,
          measured_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);
            // Create performance_sessions table
            await client.query(`
        CREATE TABLE IF NOT EXISTS performance_sessions (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          session_id VARCHAR(255) UNIQUE NOT NULL,
          overall_health_score FLOAT NOT NULL,
          slow_extension_count INTEGER DEFAULT 0,
          recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);
            // Create disabled_extensions table
            await client.query(`
        CREATE TABLE IF NOT EXISTS disabled_extensions (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          extension_id VARCHAR(255) UNIQUE NOT NULL,
          reason VARCHAR(255) NOT NULL,
          disabled_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      `);
            // Create indexes
            await client.query(`CREATE INDEX IF NOT EXISTS idx_extension_metrics_ext_id ON extension_metrics(extension_id, measured_at DESC)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_extension_metrics_health ON extension_metrics(health_score)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_performance_sessions_session_id ON performance_sessions(session_id)`);
            await client.query(`CREATE INDEX IF NOT EXISTS idx_disabled_extensions_ext_id ON disabled_extensions(extension_id)`);
            this.logger.info('IDE performance profiler tables created successfully');
        }
        finally {
            client.release();
        }
    }
    async recordExtensionMetrics(extensionId, extensionName, startupTime, activationTime, latency) {
        const client = await this.pool.connect();
        try {
            // Calculate health score (0-100)
            const healthScore = Math.max(0, 100 - (startupTime / 10 + activationTime / 10 + latency / 5));
            const result = await client.query(`INSERT INTO extension_metrics (extension_id, extension_name, startup_time_ms, activation_time_ms, latency_ms, health_score)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id, extension_id, extension_name, startup_time_ms, activation_time_ms, latency_ms, health_score, is_disabled, disable_reason, measured_at`, [extensionId, extensionName, startupTime, activationTime, latency, healthScore]);
            const metrics = result.rows[0];
            // Check if extension should be disabled (very poor health)
            if (healthScore < 20) {
                await this.disableExtension(extensionId, 'Poor performance health score');
            }
            this.emit('metrics-recorded', { extensionId, healthScore });
            return {
                extensionId: metrics.extension_id,
                extensionName: metrics.extension_name,
                startupTime: metrics.startup_time_ms,
                activationTime: metrics.activation_time_ms,
                latency: metrics.latency_ms,
                healthScore: metrics.health_score,
                isDisabled: metrics.is_disabled,
                disableReason: metrics.disable_reason,
                lastMeasured: new Date(metrics.measured_at)
            };
        }
        finally {
            client.release();
        }
    }
    async getExtensionMetrics(extensionId, limit = 10) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT id, extension_id, extension_name, startup_time_ms, activation_time_ms, latency_ms, health_score, is_disabled, disable_reason, measured_at
         FROM extension_metrics
         WHERE extension_id = $1
         ORDER BY measured_at DESC
         LIMIT $2`, [extensionId, limit]);
            return result.rows.map(row => ({
                extensionId: row.extension_id,
                extensionName: row.extension_name,
                startupTime: row.startup_time_ms,
                activationTime: row.activation_time_ms,
                latency: row.latency_ms,
                healthScore: row.health_score,
                isDisabled: row.is_disabled,
                disableReason: row.disable_reason,
                lastMeasured: new Date(row.measured_at)
            }));
        }
        finally {
            client.release();
        }
    }
    async getPerformanceProfile(sessionId) {
        const client = await this.pool.connect();
        try {
            // Get session data
            const sessionResult = await client.query(`SELECT id, session_id, overall_health_score, slow_extension_count, recorded_at
         FROM performance_sessions
         WHERE session_id = $1`, [sessionId]);
            if (sessionResult.rows.length === 0) {
                return null;
            }
            const session = sessionResult.rows[0];
            // Get all extensions in this session
            const extensionsResult = await client.query(`SELECT extension_id, extension_name, startup_time_ms, activation_time_ms, latency_ms, health_score, is_disabled, disable_reason, measured_at
         FROM extension_metrics
         WHERE measured_at >= (SELECT recorded_at - interval '10 seconds' FROM performance_sessions WHERE session_id = $1)
         AND measured_at <= (SELECT recorded_at FROM performance_sessions WHERE session_id = $1)
         ORDER BY health_score ASC`, [sessionId]);
            const extensions = extensionsResult.rows.map(row => ({
                extensionId: row.extension_id,
                extensionName: row.extension_name,
                startupTime: row.startup_time_ms,
                activationTime: row.activation_time_ms,
                latency: row.latency_ms,
                healthScore: row.health_score,
                isDisabled: row.is_disabled,
                disableReason: row.disable_reason,
                lastMeasured: new Date(row.measured_at)
            }));
            const slowExtensions = extensions.filter(ext => ext.healthScore < 50);
            return {
                sessionId,
                timestamp: new Date(session.recorded_at),
                extensions,
                overallHealth: session.overall_health_score,
                slowExtensions
            };
        }
        finally {
            client.release();
        }
    }
    async disableExtension(extensionId, reason) {
        const client = await this.pool.connect();
        try {
            await client.query(`INSERT INTO disabled_extensions (extension_id, reason)
         VALUES ($1, $2)
         ON CONFLICT (extension_id) DO UPDATE SET reason = $2, disabled_at = CURRENT_TIMESTAMP`, [extensionId, reason]);
            await client.query(`UPDATE extension_metrics
         SET is_disabled = true, disable_reason = $2
         WHERE extension_id = $1`, [extensionId, reason]);
            this.emit('extension-disabled', { extensionId, reason });
        }
        finally {
            client.release();
        }
    }
    async enableExtension(extensionId) {
        const client = await this.pool.connect();
        try {
            await client.query(`DELETE FROM disabled_extensions WHERE extension_id = $1`, [extensionId]);
            await client.query(`UPDATE extension_metrics
         SET is_disabled = false, disable_reason = NULL
         WHERE extension_id = $1`, [extensionId]);
            this.emit('extension-enabled', { extensionId });
        }
        finally {
            client.release();
        }
    }
    async getSlowExtensions(threshold = 50) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT extension_id, extension_name, startup_time_ms, activation_time_ms, latency_ms, health_score, is_disabled, disable_reason, measured_at
         FROM extension_metrics
         WHERE health_score < $1
         AND measured_at >= NOW() - INTERVAL '1 hour'
         ORDER BY health_score ASC
         LIMIT 20`, [threshold]);
            return result.rows.map(row => ({
                extensionId: row.extension_id,
                extensionName: row.extension_name,
                startupTime: row.startup_time_ms,
                activationTime: row.activation_time_ms,
                latency: row.latency_ms,
                healthScore: row.health_score,
                isDisabled: row.is_disabled,
                disableReason: row.disable_reason,
                lastMeasured: new Date(row.measured_at)
            }));
        }
        finally {
            client.release();
        }
    }
    async cleanupOldMetrics(daysOld = 30) {
        const client = await this.pool.connect();
        try {
            const cutoffDate = new Date();
            cutoffDate.setDate(cutoffDate.getDate() - daysOld);
            const result = await client.query(`DELETE FROM extension_metrics
         WHERE measured_at < $1`, [cutoffDate]);
            this.emit('metrics-cleaned', { count: result.rowCount, daysOld });
            return result.rowCount || 0;
        }
        finally {
            client.release();
        }
    }
}
export async function initializeIDEPerformanceProfilerRoutes(service) {
    const { Router } = require('express');
    const router = Router();
    const logger = getLogger('IDEPerformanceProfilerRoutes');
    router.post('/api/performance/metrics', async (req, res) => {
        try {
            const { extensionId, extensionName, startupTime, activationTime, latency } = req.body;
            const metrics = await service.recordExtensionMetrics(extensionId, extensionName, startupTime, activationTime, latency);
            res.json(metrics);
        }
        catch (error) {
            logger.error('Failed to record metrics', error);
            res.status(500).json({ error: 'Failed to record metrics' });
        }
    });
    router.get('/api/performance/metrics/:extensionId', async (req, res) => {
        try {
            const { extensionId } = req.params;
            const metrics = await service.getExtensionMetrics(extensionId);
            res.json(metrics);
        }
        catch (error) {
            logger.error('Failed to get metrics', error);
            res.status(500).json({ error: 'Failed to get metrics' });
        }
    });
    router.get('/api/performance/profile/:sessionId', async (req, res) => {
        try {
            const { sessionId } = req.params;
            const profile = await service.getPerformanceProfile(sessionId);
            if (!profile) {
                return res.status(404).json({ error: 'Profile not found' });
            }
            res.json(profile);
        }
        catch (error) {
            logger.error('Failed to get performance profile', error);
            res.status(500).json({ error: 'Failed to get performance profile' });
        }
    });
    router.post('/api/performance/extensions/:extensionId/disable', async (req, res) => {
        try {
            const { extensionId } = req.params;
            const { reason } = req.body;
            await service.disableExtension(extensionId, reason);
            res.json({ success: true });
        }
        catch (error) {
            logger.error('Failed to disable extension', error);
            res.status(500).json({ error: 'Failed to disable extension' });
        }
    });
    router.post('/api/performance/extensions/:extensionId/enable', async (req, res) => {
        try {
            const { extensionId } = req.params;
            await service.enableExtension(extensionId);
            res.json({ success: true });
        }
        catch (error) {
            logger.error('Failed to enable extension', error);
            res.status(500).json({ error: 'Failed to enable extension' });
        }
    });
    router.get('/api/performance/slow-extensions', async (req, res) => {
        try {
            const threshold = parseInt(req.query.threshold) || 50;
            const extensions = await service.getSlowExtensions(threshold);
            res.json(extensions);
        }
        catch (error) {
            logger.error('Failed to get slow extensions', error);
            res.status(500).json({ error: 'Failed to get slow extensions' });
        }
    });
    return router;
}
//# sourceMappingURL=index.js.map