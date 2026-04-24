#!/usr/bin/env node
// @file        apps/backend/src/services/dora-metrics/__tests__/dora-metrics.test.ts
// @module      observability/dora-metrics
// @description Unit tests for DORA metrics service
// @owner       observability-12.1
// @status      active
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { DORAMetricsService } from '../index';
vi.mock('../../../lib/logger', () => ({
    getLogger: vi.fn(() => ({
        info: vi.fn(),
        error: vi.fn(),
        warn: vi.fn(),
        debug: vi.fn(),
    })),
}));
const mockPool = {
    connect: vi.fn(),
    end: vi.fn(),
};
describe('DORAMetricsService', () => {
    let service;
    let mockClient;
    beforeEach(async () => {
        vi.clearAllMocks();
        mockClient = {
            query: vi.fn(),
            release: vi.fn(),
        };
        mockPool.connect.mockResolvedValue(mockClient);
        service = new DORAMetricsService(mockPool);
        mockClient.query.mockResolvedValue({ rows: [] });
        await service.initialize();
    });
    describe('initialization', () => {
        it('should initialize with database schema', async () => {
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('CREATE TABLE IF NOT EXISTS deployment_events'));
        });
        it('should create all required tables', async () => {
            const createTableCalls = mockClient.query.mock.calls.filter(call => call[0].includes('CREATE TABLE'));
            expect(createTableCalls.length).toBeGreaterThanOrEqual(5);
        });
        it('should create indexes', async () => {
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('CREATE INDEX'));
        });
    });
    describe('recordDeployment', () => {
        it('should record a successful deployment', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            await service.recordDeployment({
                id: 'deploy-1',
                timestamp: new Date('2026-04-21'),
                commitSha: 'abc123',
                deploymentId: 'deploy-1',
                environment: 'production',
                success: true,
                duration: 5000,
            });
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO deployment_events'), expect.any(Array));
        });
        it('should record a failed deployment', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            await service.recordDeployment({
                id: 'deploy-2',
                timestamp: new Date('2026-04-21'),
                commitSha: 'def456',
                deploymentId: 'deploy-2',
                environment: 'staging',
                success: false,
                duration: 3000,
            });
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO deployment_events'), expect.arrayContaining([false]));
        });
        it('should update existing deployment', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            await service.recordDeployment({
                id: 'deploy-1',
                timestamp: new Date(),
                commitSha: 'abc123',
                deploymentId: 'deploy-1',
                environment: 'production',
                success: true,
                duration: 5000,
            });
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('ON CONFLICT'), expect.any(Array));
        });
    });
    describe('recordCommitMetric', () => {
        it('should record commit metric with lead time', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            const committedAt = new Date('2026-04-21T10:00:00Z');
            const deployedAt = new Date('2026-04-21T10:30:00Z');
            await service.recordCommitMetric({
                sha: 'abc123',
                committedAt,
                deployedAt,
            });
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO commit_metrics'), expect.any(Array));
        });
        it('should record commit metric without deployment', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            await service.recordCommitMetric({
                sha: 'def456',
                committedAt: new Date('2026-04-21'),
            });
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO commit_metrics'), expect.any(Array));
        });
        it('should calculate lead time in milliseconds', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            const committedAt = new Date('2026-04-21T10:00:00Z');
            const deployedAt = new Date('2026-04-21T11:00:00Z');
            await service.recordCommitMetric({
                sha: 'abc123',
                committedAt,
                deployedAt,
            });
            // Lead time should be 1 hour = 3600000 ms
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO commit_metrics'), expect.arrayContaining([3600000]));
        });
    });
    describe('recordFailureRecovery', () => {
        it('should record failure recovery with MTTR', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [{ failure_timestamp: new Date('2026-04-21T10:00:00Z') }],
            });
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            const recoveredAt = new Date('2026-04-21T10:30:00Z');
            await service.recordFailureRecovery('deploy-1', recoveredAt, 'Bug in code');
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('UPDATE deployment_failures'), expect.any(Array));
        });
        it('should calculate MTTR', async () => {
            const failureTime = new Date('2026-04-21T10:00:00Z').getTime();
            const recoveryTime = new Date('2026-04-21T10:15:00Z').getTime();
            const expectedMttr = recoveryTime - failureTime;
            mockClient.query.mockResolvedValueOnce({
                rows: [{ failure_timestamp: new Date('2026-04-21T10:00:00Z') }],
            });
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            await service.recordFailureRecovery('deploy-1', new Date('2026-04-21T10:15:00Z'), 'Database timeout');
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('UPDATE deployment_failures'), expect.arrayContaining([expectedMttr]));
        });
        it('should handle missing failure', async () => {
            mockClient.query.mockResolvedValueOnce({ rows: [] });
            await expect(service.recordFailureRecovery('unknown', new Date(), 'Test')).rejects.toThrow();
        });
    });
    describe('getMetrics', () => {
        it('should calculate deployment frequency', async () => {
            mockClient.query
                .mockResolvedValueOnce({ rows: [{ count: '10' }] }) // deployments
                .mockResolvedValueOnce({ rows: [{ avg_lead_time: '3600000' }] }) // lead time
                .mockResolvedValueOnce({ rows: [{ failures: '1', total: '10' }] }) // failures
                .mockResolvedValueOnce({ rows: [{ avg_mttr: '900000' }] }); // mttr
            const metrics = await service.getMetrics(28);
            expect(metrics.deploymentFrequency).toBeGreaterThan(0);
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('deployment_events'), expect.any(Array));
        });
        it('should calculate mean lead time', async () => {
            mockClient.query
                .mockResolvedValueOnce({ rows: [{ count: '5' }] })
                .mockResolvedValueOnce({ rows: [{ avg_lead_time: '7200000' }] }) // 2 hours
                .mockResolvedValueOnce({ rows: [{ failures: '0', total: '5' }] })
                .mockResolvedValueOnce({ rows: [{ avg_mttr: '0' }] });
            const metrics = await service.getMetrics(28);
            expect(metrics.meanLeadTime).toBe(7200000);
        });
        it('should calculate change failure rate', async () => {
            mockClient.query
                .mockResolvedValueOnce({ rows: [{ count: '10' }] })
                .mockResolvedValueOnce({ rows: [{ avg_lead_time: '3600000' }] })
                .mockResolvedValueOnce({ rows: [{ failures: '2', total: '10' }] }) // 20% failure rate
                .mockResolvedValueOnce({ rows: [{ avg_mttr: '900000' }] });
            const metrics = await service.getMetrics(28);
            expect(metrics.changeFailureRate).toBe(0.2);
        });
        it('should calculate MTTR', async () => {
            mockClient.query
                .mockResolvedValueOnce({ rows: [{ count: '10' }] })
                .mockResolvedValueOnce({ rows: [{ avg_lead_time: '3600000' }] })
                .mockResolvedValueOnce({ rows: [{ failures: '1', total: '10' }] })
                .mockResolvedValueOnce({ rows: [{ avg_mttr: '1800000' }] }); // 30 mins
            const metrics = await service.getMetrics(28);
            expect(metrics.mttr).toBe(1800000);
        });
        it('should respect period parameter', async () => {
            mockClient.query
                .mockResolvedValueOnce({ rows: [{ count: '5' }] })
                .mockResolvedValueOnce({ rows: [{ avg_lead_time: '3600000' }] })
                .mockResolvedValueOnce({ rows: [{ failures: '0', total: '5' }] })
                .mockResolvedValueOnce({ rows: [{ avg_mttr: '0' }] });
            await service.getMetrics(7);
            expect(mockClient.query).toHaveBeenCalled();
        });
    });
    describe('getTrendData', () => {
        it('should retrieve trend data', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [
                    {
                        week_number: 1,
                        week_start_date: '2026-04-01',
                        deployment_frequency: '2.5',
                        mean_lead_time_ms: '3600000',
                        change_failure_rate: '0.1',
                        mttr_ms: '900000',
                    },
                    {
                        week_number: 2,
                        week_start_date: '2026-04-08',
                        deployment_frequency: '3.0',
                        mean_lead_time_ms: '3600000',
                        change_failure_rate: '0.08',
                        mttr_ms: '800000',
                    },
                ],
            });
            const trend = await service.getTrendData(12);
            expect(trend).toHaveLength(2);
            expect(trend[0].week).toBe(1);
            expect(trend[0].deploymentFrequency).toBe(2.5);
            expect(trend[1].week).toBe(2);
        });
        it('should order by week ascending', async () => {
            mockClient.query.mockResolvedValueOnce({
                rows: [
                    { week_number: 11, week_start_date: '2026-04-14', deployment_frequency: '1.5', mean_lead_time_ms: '3600000', change_failure_rate: '0.15', mttr_ms: '1000000' },
                    { week_number: 12, week_start_date: '2026-04-21', deployment_frequency: '1.0', mean_lead_time_ms: '3600000', change_failure_rate: '0.1', mttr_ms: '900000' },
                ],
            });
            const trend = await service.getTrendData(12);
            expect(trend[0].week).toBeLessThan(trend[1].week);
        });
    });
    describe('calculateTier', () => {
        it('should classify elite tier', async () => {
            const metrics = {
                deploymentFrequency: 2, // 2 per day
                meanLeadTime: 1000 * 60 * 30, // 30 mins < 1 hour
                changeFailureRate: 0.1, // 10% < 15%
                mttr: 1000 * 30, // 30 seconds < 1 minute
                period: 'test',
            };
            const tier = await service.calculateTier(metrics);
            expect(tier).toBe('elite');
        });
        it('should classify high tier', async () => {
            const metrics = {
                deploymentFrequency: 1, // 1 per week
                meanLeadTime: 1000 * 60 * 60 * 12, // 12 hours < 1 day
                changeFailureRate: 0.25, // 25% < 30%
                mttr: 1000 * 60 * 60, // 1 hour
                period: 'test',
            };
            const tier = await service.calculateTier(metrics);
            expect(tier).toBe('high');
        });
        it('should classify medium tier', async () => {
            const metrics = {
                deploymentFrequency: 0.1, // 1 per 10 weeks
                meanLeadTime: 1000 * 60 * 60 * 48, // 2 days < 1 week
                changeFailureRate: 0.4, // 40% < 46%
                mttr: 1000 * 60 * 60 * 12, // 12 hours < 1 day
                period: 'test',
            };
            const tier = await service.calculateTier(metrics);
            expect(tier).toBe('medium');
        });
        it('should classify low tier', async () => {
            const metrics = {
                deploymentFrequency: 0.01, // very infrequent
                meanLeadTime: 1000 * 60 * 60 * 24 * 30, // 30 days
                changeFailureRate: 0.8, // 80% failure rate
                mttr: 1000 * 60 * 60 * 48, // 2 days
                period: 'test',
            };
            const tier = await service.calculateTier(metrics);
            expect(tier).toBe('low');
        });
    });
    describe('snapshottMetrics', () => {
        it('should create weekly snapshot', async () => {
            mockClient.query
                .mockResolvedValueOnce({ rows: [{ count: '5' }] })
                .mockResolvedValueOnce({ rows: [{ avg_lead_time: '3600000' }] })
                .mockResolvedValueOnce({ rows: [{ failures: '0', total: '5' }] })
                .mockResolvedValueOnce({ rows: [{ avg_mttr: '0' }] })
                .mockResolvedValueOnce({ rows: [] }); // insert snapshot
            await service.snapshottMetrics(1, new Date('2026-04-01'), new Date('2026-04-07'));
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO dora_weekly_snapshots'), expect.any(Array));
        });
        it('should update existing snapshot', async () => {
            mockClient.query
                .mockResolvedValueOnce({ rows: [{ count: '5' }] })
                .mockResolvedValueOnce({ rows: [{ avg_lead_time: '3600000' }] })
                .mockResolvedValueOnce({ rows: [{ failures: '0', total: '5' }] })
                .mockResolvedValueOnce({ rows: [{ avg_mttr: '0' }] })
                .mockResolvedValueOnce({ rows: [] }); // upsert
            await service.snapshottMetrics(1, new Date('2026-04-01'), new Date('2026-04-07'));
            expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('ON CONFLICT'), expect.any(Array));
        });
    });
    describe('getMetricsSnapshot', () => {
        it('should get complete snapshot', async () => {
            mockClient.query
                .mockResolvedValueOnce({ rows: [{ count: '10' }] })
                .mockResolvedValueOnce({ rows: [{ avg_lead_time: '3600000' }] })
                .mockResolvedValueOnce({ rows: [{ failures: '1', total: '10' }] })
                .mockResolvedValueOnce({ rows: [{ avg_mttr: '900000' }] })
                .mockResolvedValueOnce({ rows: [{ week_number: 1, week_start_date: '2026-04-01', deployment_frequency: '2.5', mean_lead_time_ms: '3600000', change_failure_rate: '0.1', mttr_ms: '900000' }] });
            const snapshot = await service.getMetricsSnapshot(28);
            expect(snapshot.metrics).toBeDefined();
            expect(snapshot.tier).toBeDefined();
            expect(snapshot.trend).toBeDefined();
            expect(snapshot.timestamp).toBeInstanceOf(Date);
        });
    });
    describe('getTierBenchmarks', () => {
        it('should return all tier benchmarks', () => {
            const benchmarks = service.getTierBenchmarks();
            expect(benchmarks.elite).toBeDefined();
            expect(benchmarks.high).toBeDefined();
            expect(benchmarks.medium).toBeDefined();
            expect(benchmarks.low).toBeDefined();
        });
        it('should have proper thresholds for elite', () => {
            const benchmarks = service.getTierBenchmarks();
            expect(benchmarks.elite.deploymentFrequency.min).toBeGreaterThan(0);
            expect(benchmarks.elite.leadTime.max).toBeLessThan(benchmarks.high.leadTime.max);
        });
        it('should have increasing thresholds from elite to low', () => {
            const benchmarks = service.getTierBenchmarks();
            expect(benchmarks.elite.deploymentFrequency.min).toBeGreaterThan(benchmarks.high.deploymentFrequency.min);
            expect(benchmarks.high.deploymentFrequency.min).toBeGreaterThan(benchmarks.medium.deploymentFrequency.min);
        });
    });
    describe('formatMetricsForDisplay', () => {
        it('should format metrics as markdown', () => {
            const metrics = {
                deploymentFrequency: 2.5,
                meanLeadTime: 3600000, // 1 hour
                changeFailureRate: 0.1,
                mttr: 900000, // 15 mins
                period: 'test',
            };
            const formatted = service.formatMetricsForDisplay(metrics);
            expect(formatted).toContain('Deployment Frequency');
            expect(formatted).toContain('2.50 per week');
            expect(formatted).toContain('Lead Time');
            expect(formatted).toContain('Change Failure Rate');
            expect(formatted).toContain('10.0%');
            expect(formatted).toContain('MTTR');
        });
        it('should format times appropriately', () => {
            const metrics = {
                deploymentFrequency: 1,
                meanLeadTime: 1000 * 60 * 60 * 24 * 7, // 7 days
                changeFailureRate: 0.2,
                mttr: 1000 * 60, // 1 minute
                period: 'test',
            };
            const formatted = service.formatMetricsForDisplay(metrics);
            expect(formatted).toContain('d'); // days
            expect(formatted).toContain('m'); // minutes
        });
    });
});
//# sourceMappingURL=dora-metrics.test.js.map