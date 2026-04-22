#!/usr/bin/env node
// @file        apps/backend/src/routes/dora-metrics.ts
// @module      observability/dora-metrics
// @description REST API routes for DORA metrics service
// @owner       observability-12.1
// @status      active
import { Router } from 'express';
import { DORAMetricsService } from '../services/dora-metrics';
import { getLogger } from '../lib/logger';
const logger = getLogger('DORAMetricsRoutes');
export function initializeDORAMetricsRoutes(pool) {
    const router = Router();
    const doraMetricsService = new DORAMetricsService(pool);
    doraMetricsService.initialize().catch(error => {
        logger.error('Failed to initialize DORA metrics service', { error });
    });
    // GET /api/metrics/dora - Get current DORA metrics
    router.get('/dora', async (req, res) => {
        try {
            const { days = '28' } = req.query;
            const periodDays = parseInt(days, 10);
            if (periodDays < 1 || periodDays > 365) {
                return res.status(400).json({ error: 'Days must be between 1 and 365' });
            }
            const metrics = await doraMetricsService.getMetrics(periodDays);
            res.json({
                success: true,
                metrics,
            });
        }
        catch (error) {
            logger.error('Failed to get DORA metrics', { error, query: req.query });
            res.status(500).json({ error: 'Failed to get metrics' });
        }
    });
    // GET /api/metrics/dora/snapshot - Get complete metrics snapshot with trends
    router.get('/dora/snapshot', async (req, res) => {
        try {
            const { days = '28' } = req.query;
            const periodDays = parseInt(days, 10);
            if (periodDays < 1 || periodDays > 365) {
                return res.status(400).json({ error: 'Days must be between 1 and 365' });
            }
            const snapshot = await doraMetricsService.getMetricsSnapshot(periodDays);
            res.json({
                success: true,
                snapshot,
            });
        }
        catch (error) {
            logger.error('Failed to get metrics snapshot', { error, query: req.query });
            res.status(500).json({ error: 'Failed to get snapshot' });
        }
    });
    // GET /api/metrics/dora/trend - Get trend data
    router.get('/dora/trend', async (req, res) => {
        try {
            const { weeks = '12' } = req.query;
            const trendWeeks = parseInt(weeks, 10);
            if (trendWeeks < 1 || trendWeeks > 52) {
                return res.status(400).json({ error: 'Weeks must be between 1 and 52' });
            }
            const trend = await doraMetricsService.getTrendData(trendWeeks);
            res.json({
                success: true,
                weeks: trendWeeks,
                trend,
            });
        }
        catch (error) {
            logger.error('Failed to get trend data', { error, query: req.query });
            res.status(500).json({ error: 'Failed to get trend' });
        }
    });
    // GET /api/metrics/dora/benchmarks - Get tier benchmarks
    router.get('/dora/benchmarks', async (req, res) => {
        try {
            const benchmarks = doraMetricsService.getTierBenchmarks();
            res.json({
                success: true,
                benchmarks,
            });
        }
        catch (error) {
            logger.error('Failed to get benchmarks', { error });
            res.status(500).json({ error: 'Failed to get benchmarks' });
        }
    });
    // POST /api/metrics/deployment - Record deployment event
    router.post('/deployment', async (req, res) => {
        try {
            const { commitSha, deploymentId, environment, success, duration } = req.body;
            if (!commitSha || !deploymentId || !environment || success === undefined) {
                return res.status(400).json({
                    error: 'Missing required fields: commitSha, deploymentId, environment, success',
                });
            }
            const event = {
                id: deploymentId,
                timestamp: new Date(),
                commitSha,
                deploymentId,
                environment,
                success,
                duration: duration || 0,
            };
            await doraMetricsService.recordDeployment(event);
            res.json({
                success: true,
                message: 'Deployment recorded',
            });
        }
        catch (error) {
            logger.error('Failed to record deployment', { error, body: req.body });
            res.status(500).json({ error: 'Failed to record deployment' });
        }
    });
    // POST /api/metrics/commit - Record commit metric
    router.post('/commit', async (req, res) => {
        try {
            const { sha, committedAt, deployedAt, environment, success } = req.body;
            if (!sha || !committedAt) {
                return res.status(400).json({ error: 'Missing required fields: sha, committedAt' });
            }
            const metric = {
                sha,
                committedAt: new Date(committedAt),
                deployedAt: deployedAt ? new Date(deployedAt) : undefined,
                environment,
                success,
            };
            await doraMetricsService.recordCommitMetric(metric);
            res.json({
                success: true,
                message: 'Commit metric recorded',
            });
        }
        catch (error) {
            logger.error('Failed to record commit metric', { error, body: req.body });
            res.status(500).json({ error: 'Failed to record commit metric' });
        }
    });
    // POST /api/metrics/failure-recovery - Record failure recovery
    router.post('/failure-recovery', async (req, res) => {
        try {
            const { deploymentId, recoveredAt, rootCause } = req.body;
            if (!deploymentId || !recoveredAt) {
                return res.status(400).json({ error: 'Missing required fields: deploymentId, recoveredAt' });
            }
            await doraMetricsService.recordFailureRecovery(deploymentId, new Date(recoveredAt), rootCause);
            res.json({
                success: true,
                message: 'Failure recovery recorded',
            });
        }
        catch (error) {
            logger.error('Failed to record failure recovery', { error, body: req.body });
            res.status(500).json({ error: 'Failed to record failure recovery' });
        }
    });
    // POST /api/metrics/snapshot - Create weekly snapshot
    router.post('/dora/snapshot-create', async (req, res) => {
        try {
            const { weekNumber, weekStart, weekEnd } = req.body;
            if (weekNumber === undefined || !weekStart || !weekEnd) {
                return res.status(400).json({
                    error: 'Missing required fields: weekNumber, weekStart, weekEnd',
                });
            }
            await doraMetricsService.snapshottMetrics(weekNumber, new Date(weekStart), new Date(weekEnd));
            res.json({
                success: true,
                message: 'Snapshot created',
            });
        }
        catch (error) {
            logger.error('Failed to create snapshot', { error, body: req.body });
            res.status(500).json({ error: 'Failed to create snapshot' });
        }
    });
    // GET /api/metrics/dora/tier - Get current tier level
    router.get('/dora/tier', async (req, res) => {
        try {
            const { days = '28' } = req.query;
            const periodDays = parseInt(days, 10);
            const metrics = await doraMetricsService.getMetrics(periodDays);
            const tier = await doraMetricsService.calculateTier(metrics);
            res.json({
                success: true,
                tier,
                metrics,
            });
        }
        catch (error) {
            logger.error('Failed to calculate tier', { error, query: req.query });
            res.status(500).json({ error: 'Failed to calculate tier' });
        }
    });
    // GET /api/metrics/dora/display - Get formatted metrics for display
    router.get('/dora/display', async (req, res) => {
        try {
            const { days = '28' } = req.query;
            const periodDays = parseInt(days, 10);
            const metrics = await doraMetricsService.getMetrics(periodDays);
            const formatted = doraMetricsService.formatMetricsForDisplay(metrics);
            res.json({
                success: true,
                formatted,
                metrics,
            });
        }
        catch (error) {
            logger.error('Failed to format metrics', { error, query: req.query });
            res.status(500).json({ error: 'Failed to format metrics' });
        }
    });
    return router;
}
export { DORAMetricsService } from '../services/dora-metrics';
//# sourceMappingURL=dora-metrics.js.map