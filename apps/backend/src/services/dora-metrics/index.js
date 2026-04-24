#!/usr/bin/env node
// @file        apps/backend/src/services/dora-metrics/index.ts
// @module      observability/dora-metrics
// @description DORA metrics tracking: deployment frequency, lead time, change failure rate, MTTR
// @owner       observability-12.1
// @status      active
import { EventEmitter } from 'events';
import { getLogger } from '../../lib/logger';
export class DORAMetricsService extends EventEmitter {
    constructor(pool, auditService) {
        super();
        this.logger = getLogger('DORAMetricsService');
        this.initialized = false;
        this.pool = pool;
        this.auditService = auditService;
    }
    async initialize() {
        if (this.initialized)
            return;
        try {
            await this.createTables();
            this.initialized = true;
            this.logger.info('DORA metrics database schema initialized');
        }
        catch (error) {
            this.logger.error('Failed to initialize DORA metrics schema', { error });
            throw error;
        }
    }
    async createTables() {
        const client = await this.pool.connect();
        try {
            await client.query('BEGIN');
            // Deployment events
            await client.query(`
        CREATE TABLE IF NOT EXISTS deployment_events (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
          commit_sha TEXT NOT NULL,
          deployment_id TEXT NOT NULL UNIQUE,
          environment TEXT NOT NULL,
          success BOOLEAN NOT NULL,
          duration INTEGER,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);
            // Commit metrics
            await client.query(`
        CREATE TABLE IF NOT EXISTS commit_metrics (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          commit_sha TEXT NOT NULL UNIQUE,
          committed_at TIMESTAMP WITH TIME ZONE NOT NULL,
          deployed_at TIMESTAMP WITH TIME ZONE,
          lead_time_ms INTEGER,
          environment TEXT,
          deployment_success BOOLEAN,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);
            // Weekly DORA snapshots
            await client.query(`
        CREATE TABLE IF NOT EXISTS dora_weekly_snapshots (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          week_number INTEGER NOT NULL,
          week_start_date DATE NOT NULL,
          week_end_date DATE NOT NULL,
          deployment_frequency NUMERIC(10, 2),
          mean_lead_time_ms INTEGER,
          change_failure_rate NUMERIC(4, 3),
          mttr_ms INTEGER,
          tier TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          UNIQUE(week_number, week_start_date)
        )
      `);
            // Failed deployment recovery events
            await client.query(`
        CREATE TABLE IF NOT EXISTS deployment_failures (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          deployment_id TEXT NOT NULL UNIQUE,
          failure_timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
          recovery_timestamp TIMESTAMP WITH TIME ZONE,
          mttr_ms INTEGER,
          root_cause TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);
            // DORA tier history
            await client.query(`
        CREATE TABLE IF NOT EXISTS dora_tier_history (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          timestamp TIMESTAMP WITH TIME ZONE NOT NULL,
          tier TEXT NOT NULL,
          metrics_snapshot JSONB,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);
            // Indexes
            await client.query(`
        CREATE INDEX IF NOT EXISTS idx_deployment_events_timestamp ON deployment_events(timestamp);
        CREATE INDEX IF NOT EXISTS idx_deployment_events_commit ON deployment_events(commit_sha);
        CREATE INDEX IF NOT EXISTS idx_commit_metrics_committed ON commit_metrics(committed_at);
        CREATE INDEX IF NOT EXISTS idx_commit_metrics_deployed ON commit_metrics(deployed_at);
        CREATE INDEX IF NOT EXISTS idx_dora_snapshots_week ON dora_weekly_snapshots(week_number);
        CREATE INDEX IF NOT EXISTS idx_deployment_failures_timestamp ON deployment_failures(failure_timestamp);
        CREATE INDEX IF NOT EXISTS idx_dora_tier_history_timestamp ON dora_tier_history(timestamp);
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
    // SOC2: Audit production changes
    auditDeployment(deploymentId, environment, success) {
        if (environment === 'production' || environment === 'prod') {
            this.auditService?.emit({
                userId: 'system',
                action: success ? 'allow' : 'deny',
                resource: 'deployment:' + deploymentId,
                reason: 'Recorded production deployment ' + deploymentId + ' (success: ' + success + ')'
            });
        }
    }
    async recordDeployment(event) {
        const client = await this.pool.connect();
        try {
            await client.query(`INSERT INTO deployment_events (timestamp, commit_sha, deployment_id, environment, success, duration)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (deployment_id) DO UPDATE SET success = $5, updated_at = NOW()`, [event.timestamp, event.commitSha, event.deploymentId, event.environment, event.success, event.duration]);
            this.logger.info('Deployment recorded', {
                deploymentId: event.deploymentId,
                success: event.success,
            });
        }
        catch (error) {
            this.logger.error('Failed to record deployment', { error, deploymentId: event.deploymentId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async recordCommitMetric(metric) {
        const client = await this.pool.connect();
        try {
            const leadTime = metric.deployedAt && metric.committedAt
                ? metric.deployedAt.getTime() - metric.committedAt.getTime()
                : null;
            await client.query(`INSERT INTO commit_metrics (commit_sha, committed_at, deployed_at, lead_time_ms, environment, deployment_success)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (commit_sha) DO UPDATE SET
           deployed_at = $3, lead_time_ms = $4, environment = $5, deployment_success = $6, updated_at = NOW()`, [metric.sha, metric.committedAt, metric.deployedAt || null, leadTime, metric.environment || null, metric.success || null]);
            this.logger.info('Commit metric recorded', { commitSha: metric.sha, leadTime });
        }
        catch (error) {
            this.logger.error('Failed to record commit metric', { error, commitSha: metric.sha });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async recordFailureRecovery(deploymentId, recoveredAt, rootCause) {
        const client = await this.pool.connect();
        try {
            // Get failure timestamp
            const failureResult = await client.query('SELECT failure_timestamp FROM deployment_failures WHERE deployment_id = $1', [deploymentId]);
            if (failureResult.rows.length === 0) {
                throw new Error(`Failure not found for deployment ${deploymentId}`);
            }
            const failureTime = new Date(failureResult.rows[0].failure_timestamp);
            const mttrMs = recoveredAt.getTime() - failureTime.getTime();
            await client.query(`UPDATE deployment_failures SET recovery_timestamp = $1, mttr_ms = $2, root_cause = $3, updated_at = NOW()
         WHERE deployment_id = $4`, [recoveredAt, mttrMs, rootCause || null, deploymentId]);
            this.logger.info('Failure recovery recorded', { deploymentId, mttrMs });
        }
        catch (error) {
            this.logger.error('Failed to record failure recovery', { error, deploymentId });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async getMetrics(periodDays = 28) {
        const client = await this.pool.connect();
        try {
            const startDate = new Date(Date.now() - periodDays * 24 * 60 * 60 * 1000);
            // Deployment frequency
            const deploymentResult = await client.query(`SELECT COUNT(*) as count FROM deployment_events 
         WHERE timestamp >= $1 AND success = true`, [startDate]);
            const deployments = parseInt(deploymentResult.rows[0]?.count || '0', 10);
            const weeks = periodDays / 7;
            const deploymentFrequency = deployments / weeks;
            // Lead time
            const leadTimeResult = await client.query(`SELECT AVG(lead_time_ms) as avg_lead_time FROM commit_metrics 
         WHERE committed_at >= $1 AND lead_time_ms IS NOT NULL`, [startDate]);
            const meanLeadTime = parseInt(leadTimeResult.rows[0]?.avg_lead_time || '0', 10);
            // Change failure rate
            const failureResult = await client.query(`SELECT 
          COUNT(CASE WHEN success = false THEN 1 END) as failures,
          COUNT(*) as total
         FROM deployment_events 
         WHERE timestamp >= $1`, [startDate]);
            const total = parseInt(failureResult.rows[0]?.total || '1', 10);
            const failures = parseInt(failureResult.rows[0]?.failures || '0', 10);
            const changeFailureRate = total > 0 ? failures / total : 0;
            // MTTR
            const mttrResult = await client.query(`SELECT AVG(mttr_ms) as avg_mttr FROM deployment_failures 
         WHERE failure_timestamp >= $1 AND mttr_ms IS NOT NULL`, [startDate]);
            const mttr = parseInt(mttrResult.rows[0]?.avg_mttr || '0', 10);
            return {
                deploymentFrequency: Math.round(deploymentFrequency * 100) / 100,
                meanLeadTime,
                changeFailureRate: Math.round(changeFailureRate * 1000) / 1000,
                mttr,
                period: `last-${periodDays}-days`,
            };
        }
        catch (error) {
            this.logger.error('Failed to get metrics', { error, periodDays });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async getTrendData(weeks = 12) {
        const client = await this.pool.connect();
        try {
            const result = await client.query(`SELECT 
          week_number,
          week_start_date,
          deployment_frequency,
          mean_lead_time_ms,
          change_failure_rate,
          mttr_ms
         FROM dora_weekly_snapshots 
         WHERE week_number >= (SELECT MAX(week_number) - $1 FROM dora_weekly_snapshots)
         ORDER BY week_number ASC`, [weeks]);
            return result.rows.map(row => ({
                week: row.week_number,
                date: new Date(row.week_start_date),
                deploymentFrequency: parseFloat(row.deployment_frequency || '0'),
                meanLeadTime: parseInt(row.mean_lead_time_ms || '0', 10),
                changeFailureRate: parseFloat(row.change_failure_rate || '0'),
                mttr: parseInt(row.mttr_ms || '0', 10),
            }));
        }
        catch (error) {
            this.logger.error('Failed to get trend data', { error, weeks });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async calculateTier(metrics) {
        // DORA benchmarks (elite, high, medium, low)
        const benchmarks = {
            elite: {
                tier: 'elite',
                deploymentFrequency: { min: 1 }, // per day+
                leadTime: { max: 1000 * 60 * 60 }, // < 1 hour
                changeFailureRate: { max: 0.15 }, // < 15%
                mttr: { max: 1000 * 60 }, // < 1 hour
            },
            high: {
                tier: 'high',
                deploymentFrequency: { min: 1 / 7 }, // per week
                leadTime: { max: 1000 * 60 * 60 * 24 }, // < 1 day
                changeFailureRate: { max: 0.3 }, // < 30%
                mttr: { max: 1000 * 60 * 60 }, // < 1 hour
            },
            medium: {
                tier: 'medium',
                deploymentFrequency: { min: 1 / 30 }, // per month
                leadTime: { max: 1000 * 60 * 60 * 24 * 7 }, // < 1 week
                changeFailureRate: { max: 0.46 }, // < 46%
                mttr: { max: 1000 * 60 * 60 * 24 }, // < 1 day
            },
            low: {
                tier: 'low',
                deploymentFrequency: { min: 0 },
                leadTime: { min: 0 },
                changeFailureRate: { min: 0 },
                mttr: { min: 0 },
            },
        };
        // Check against benchmarks (elite to low)
        for (const tier of ['elite', 'high', 'medium', 'low']) {
            const bench = benchmarks[tier];
            const freqMatch = metrics.deploymentFrequency >= bench.deploymentFrequency.min &&
                (!bench.deploymentFrequency.max || metrics.deploymentFrequency <= bench.deploymentFrequency.max);
            const leadMatch = metrics.meanLeadTime <= bench.leadTime.max &&
                (!bench.leadTime.min || metrics.meanLeadTime >= bench.leadTime.min);
            const failMatch = metrics.changeFailureRate <= bench.changeFailureRate.max &&
                (!bench.changeFailureRate.min || metrics.changeFailureRate >= bench.changeFailureRate.min);
            const mttrMatch = metrics.mttr <= bench.mttr.max &&
                (!bench.mttr.min || metrics.mttr >= bench.mttr.min);
            if (freqMatch && leadMatch && failMatch && mttrMatch) {
                return tier;
            }
        }
        return 'low';
    }
    async snapshottMetrics(weekNumber, weekStart, weekEnd) {
        const client = await this.pool.connect();
        try {
            const metrics = await this.getMetrics(7); // Get last 7 days
            const tier = await this.calculateTier(metrics);
            await client.query(`INSERT INTO dora_weekly_snapshots 
         (week_number, week_start_date, week_end_date, deployment_frequency, mean_lead_time_ms, change_failure_rate, mttr_ms, tier)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (week_number, week_start_date) DO UPDATE SET
           deployment_frequency = $4, mean_lead_time_ms = $5, change_failure_rate = $6, mttr_ms = $7, tier = $8`, [
                weekNumber,
                weekStart,
                weekEnd,
                metrics.deploymentFrequency,
                metrics.meanLeadTime,
                metrics.changeFailureRate,
                metrics.mttr,
                tier,
            ]);
            this.logger.info('Metrics snapshot recorded', { weekNumber, tier });
        }
        catch (error) {
            this.logger.error('Failed to snapshot metrics', { error, weekNumber });
            throw error;
        }
        finally {
            client.release();
        }
    }
    async getMetricsSnapshot(periodDays = 28) {
        const metrics = await this.getMetrics(periodDays);
        const tier = await this.calculateTier(metrics);
        const trend = await this.getTrendData(12);
        return {
            timestamp: new Date(),
            metrics,
            tier,
            trend,
        };
    }
    getTierBenchmarks() {
        return {
            elite: {
                tier: 'elite',
                deploymentFrequency: { min: 1 },
                leadTime: { max: 1000 * 60 * 60 },
                changeFailureRate: { max: 0.15 },
                mttr: { max: 1000 * 60 },
            },
            high: {
                tier: 'high',
                deploymentFrequency: { min: 1 / 7 },
                leadTime: { max: 1000 * 60 * 60 * 24 },
                changeFailureRate: { max: 0.3 },
                mttr: { max: 1000 * 60 * 60 },
            },
            medium: {
                tier: 'medium',
                deploymentFrequency: { min: 1 / 30 },
                leadTime: { max: 1000 * 60 * 60 * 24 * 7 },
                changeFailureRate: { max: 0.46 },
                mttr: { max: 1000 * 60 * 60 * 24 },
            },
            low: {
                tier: 'low',
                deploymentFrequency: { min: 0 },
                leadTime: {},
                changeFailureRate: {},
                mttr: {},
            },
        };
    }
    formatMetricsForDisplay(metrics) {
        const formatTime = (ms) => {
            if (ms < 1000 * 60)
                return `${Math.round(ms / 1000)}s`;
            if (ms < 1000 * 60 * 60)
                return `${Math.round(ms / (1000 * 60))}m`;
            if (ms < 1000 * 60 * 60 * 24)
                return `${Math.round(ms / (1000 * 60 * 60))}h`;
            return `${Math.round(ms / (1000 * 60 * 60 * 24))}d`;
        };
        return [
            `**Deployment Frequency**: ${metrics.deploymentFrequency.toFixed(2)} per week`,
            `**Lead Time**: ${formatTime(metrics.meanLeadTime)}`,
            `**Change Failure Rate**: ${(metrics.changeFailureRate * 100).toFixed(1)}%`,
            `**MTTR**: ${formatTime(metrics.mttr)}`,
        ].join('\n');
    }
}
//# sourceMappingURL=index.js.map