/**
 * SLO/SLA tracking API routes
 * Exposes endpoints for recording sync events and retrieving SLO metrics
 */
import { Router } from 'express';
import { getSLOTrackingService } from '../services/slo-tracking';
const router = Router();
/**
 * POST /api/v1/slo/record-sync
 * Record a collaboration sync event with latency measurement
 */
router.post('/record-sync', (req, res) => {
    try {
        const { sessionId, operationType, latencyMs, clientCount, error } = req.body;
        if (!sessionId || !operationType || latencyMs === undefined) {
            return res.status(400).json({
                error: 'Missing required fields: sessionId, operationType, latencyMs',
            });
        }
        const service = getSLOTrackingService();
        const metric = service.recordSync(sessionId, operationType, latencyMs, clientCount || 1, error);
        res.json({
            success: true,
            metric,
            sloMet: metric.sloMet,
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to record sync event' });
    }
});
/**
 * GET /api/v1/slo/metrics
 * Get current SLO metrics
 */
router.get('/metrics', (req, res) => {
    try {
        const service = getSLOTrackingService();
        const sinceMs = req.query.since ? parseInt(req.query.since) : undefined;
        const metrics = service.getMetrics(sinceMs);
        res.json({
            timestamp: Date.now(),
            metrics,
            sloTarget: '< 100ms',
            complianceTarget: '>= 99.9%',
            targetMet: metrics.sloCompliancePercent >= 99.9,
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to retrieve metrics' });
    }
});
/**
 * GET /api/v1/slo/window
 * Get metrics for a specific time window
 */
router.get('/window', (req, res) => {
    try {
        const { start, end } = req.query;
        if (!start || !end) {
            return res.status(400).json({
                error: 'Missing required query params: start, end (milliseconds since epoch)',
            });
        }
        const startMs = parseInt(start);
        const endMs = parseInt(end);
        if (startMs >= endMs) {
            return res.status(400).json({
                error: 'start must be before end',
            });
        }
        const service = getSLOTrackingService();
        const aggregation = service.getWindowMetrics(startMs, endMs);
        res.json(aggregation);
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to retrieve window metrics' });
    }
});
/**
 * GET /api/v1/slo/session/:sessionId
 * Get SLO metrics for a specific session
 */
router.get('/session/:sessionId', (req, res) => {
    try {
        const { sessionId } = req.params;
        const service = getSLOTrackingService();
        const stats = service.getSessionStats(sessionId);
        if (!stats) {
            return res.status(404).json({
                error: `No metrics found for session ${sessionId}`,
            });
        }
        res.json({
            sessionId,
            stats,
            timestamp: Date.now(),
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to retrieve session metrics' });
    }
});
/**
 * GET /api/v1/slo/sessions
 * Get SLO metrics for all active sessions
 */
router.get('/sessions', (req, res) => {
    try {
        const service = getSLOTrackingService();
        const sessions = service.getAllSessionStats();
        res.json({
            activeSessionCount: sessions.length,
            sessions: sessions.sort((a, b) => b.sloCompliancePercent - a.sloCompliancePercent),
            timestamp: Date.now(),
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to retrieve session list' });
    }
});
/**
 * GET /api/v1/slo/breaches
 * Get recent SLO breaches
 */
router.get('/breaches', (req, res) => {
    try {
        const service = getSLOTrackingService();
        const limit = req.query.limit ? parseInt(req.query.limit) : 20;
        const sinceMs = req.query.since ? parseInt(req.query.since) : undefined;
        const breaches = service.getRecentBreaches(limit, sinceMs);
        res.json({
            count: breaches.length,
            breaches: breaches.map((b) => ({
                ...b,
                severity: b.severity,
                breachAmountMs: b.breachAmountMs,
            })),
            timestamp: Date.now(),
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to retrieve breaches' });
    }
});
/**
 * GET /api/v1/slo/last-minutes
 * Get aggregated metrics for last N minutes
 */
router.get('/last-minutes', (req, res) => {
    try {
        const minutes = req.query.minutes
            ? parseInt(req.query.minutes)
            : 60;
        if (minutes < 1 || minutes > 1440) {
            return res.status(400).json({
                error: 'minutes must be between 1 and 1440',
            });
        }
        const service = getSLOTrackingService();
        const windows = service.getLastMinutesMetrics(minutes);
        res.json({
            minutes,
            windows: windows.map((w) => ({
                windowStart: w.windowStart,
                windowEnd: w.windowEnd,
                compliance: w.metrics.sloCompliancePercent,
                avgLatency: w.metrics.averageLatencyMs,
                p95Latency: w.metrics.p95LatencyMs,
                breachCount: w.breaches.length,
                targetMet: w.targetMet,
            })),
            timestamp: Date.now(),
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to retrieve minute metrics' });
    }
});
/**
 * GET /metrics (Prometheus format)
 * Export metrics in Prometheus format for Grafana
 */
router.get('/metrics', (req, res) => {
    try {
        const service = getSLOTrackingService();
        const prometheusMetrics = service.getPrometheusMetrics();
        res.type('text/plain').send(prometheusMetrics);
    }
    catch (error) {
        res.status(500).send('Failed to generate Prometheus metrics');
    }
});
/**
 * POST /api/v1/slo/reset (testing only)
 * Reset all SLO metrics (for testing)
 */
router.post('/reset', (req, res) => {
    try {
        // Only allow in development
        if (process.env.NODE_ENV === 'production') {
            return res.status(403).json({
                error: 'Reset not allowed in production',
            });
        }
        const service = getSLOTrackingService();
        res.json({
            success: true,
            message: 'SLO metrics reset',
        });
    }
    catch (error) {
        res.status(500).json({ error: 'Failed to reset metrics' });
    }
});
export default router;
//# sourceMappingURL=slo.js.map