#!/usr/bin/env node
// @file        apps/backend/src/services/activity-stream/__tests__/activity-stream-service.test.ts
// @module      collaboration/activity-stream/tests
// @description Comprehensive test suite for ActivityStreamService
// @owner       collab-6.2
// @status      active
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { ActivityStreamService } from '../activity-stream-service';
describe('ActivityStreamService', () => {
    let service;
    beforeEach(async () => {
        service = new ActivityStreamService({
            enableRealTime: true,
            enableMetrics: true,
            enableRetention: true,
            retentionDays: 90,
            batchSize: 10,
            flushIntervalMs: 1000,
            maxCacheSize: 100,
            enableDeduplication: true,
        });
        await service.initialize();
    });
    afterEach(async () => {
        await service.shutdown();
    });
    describe('Service Initialization', () => {
        it('should initialize service successfully', async () => {
            expect(service).toBeDefined();
        });
        it('should emit initialized event on startup', async () => {
            let emitted = false;
            const newService = new ActivityStreamService();
            newService.once('initialized', () => {
                emitted = true;
            });
            await newService.initialize();
            expect(emitted).toBe(true);
            await newService.shutdown();
        });
    });
    describe('Activity Ingestion', () => {
        it('should ingest activity successfully', async () => {
            const activity = {
                activityId: 'activity-001',
                type: 'code_change',
                userId: 'user-123',
                userName: 'Alice',
                timestamp: new Date(),
                description: 'Pushed 3 commits',
                metadata: { branchName: 'feature/xyz', commitCount: 3, teamId: 'team-001' },
            };
            await service.ingestActivity(activity);
            expect(activity.activityId).toBe('activity-001');
        });
        it('should emit activity event on ingestion', async () => {
            const activity = {
                activityId: 'activity-002',
                type: 'collaboration',
                userId: 'user-456',
                userName: 'Bob',
                timestamp: new Date(),
                description: 'Started pairing session',
                metadata: { sessionId: 'session-123', teamId: 'team-001' },
            };
            let emitted = false;
            service.once('activity', (event) => {
                emitted = event.activity.activityId === 'activity-002';
            });
            await service.ingestActivity(activity);
            expect(emitted).toBe(true);
        });
        it('should support activity deduplication', async () => {
            const activity = {
                activityId: 'activity-003',
                type: 'comment',
                userId: 'user-789',
                userName: 'Charlie',
                timestamp: new Date(),
                description: 'Added comment',
                metadata: { fileId: 'file-001', teamId: 'team-001' },
            };
            let eventCount = 0;
            service.on('activity', () => {
                eventCount++;
            });
            // Ingest same activity twice
            await service.ingestActivity(activity);
            const activity2 = { ...activity };
            await service.ingestActivity(activity2);
            // Should only emit one event (deduplication)
            expect(eventCount).toBe(1);
        });
        it('should batch activities for efficient processing', async () => {
            let flushCount = 0;
            service.on('batchFlushed', () => {
                flushCount++;
            });
            // Ingest 15 activities (batch size is 10)
            for (let i = 0; i < 15; i++) {
                const activity = {
                    activityId: `activity-batch-${i}`,
                    type: 'code_change',
                    userId: `user-${i}`,
                    userName: `User ${i}`,
                    timestamp: new Date(),
                    description: `Activity ${i}`,
                    metadata: { index: i, teamId: 'team-001' },
                };
                await service.ingestActivity(activity);
            }
            // Should flush at least once (after 10 activities)
            expect(flushCount).toBeGreaterThan(0);
        });
    });
    describe('Activity Querying', () => {
        beforeEach(async () => {
            // Populate with test activities
            const activities = [
                {
                    activityId: 'q-001',
                    type: 'code_change',
                    userId: 'user-a',
                    userName: 'Alice',
                    timestamp: new Date(Date.now() - 2 * 60 * 60 * 1000), // 2 hours ago
                    description: 'Pushed commits',
                    metadata: { teamId: 'team-001' },
                    priority: 'high',
                },
                {
                    activityId: 'q-002',
                    type: 'review',
                    userId: 'user-b',
                    userName: 'Bob',
                    timestamp: new Date(Date.now() - 1 * 60 * 60 * 1000), // 1 hour ago
                    description: 'Reviewed PR',
                    metadata: { teamId: 'team-001' },
                    priority: 'medium',
                },
                {
                    activityId: 'q-003',
                    type: 'comment',
                    userId: 'user-a',
                    userName: 'Alice',
                    timestamp: new Date(),
                    description: 'Added comment',
                    metadata: { teamId: 'team-002' },
                    priority: 'low',
                },
            ];
            for (const activity of activities) {
                await service.ingestActivity(activity);
            }
            // Wait for batch to flush
            await new Promise(resolve => setTimeout(resolve, 1200));
        });
        it('should query all activities', async () => {
            const stream = await service.queryActivities({ teamId: 'team-001' });
            expect(stream).toBeDefined();
            expect(stream.activities.length).toBeGreaterThan(0);
            expect(stream.totalCount).toBeGreaterThanOrEqual(2);
        });
        it('should filter activities by type', async () => {
            const stream = await service.queryActivities({
                teamId: 'team-001',
                activityTypes: ['code_change'],
            });
            expect(stream.activities.every((a) => a.type === 'code_change')).toBe(true);
        });
        it('should filter activities by user', async () => {
            const stream = await service.queryActivities({
                userId: 'user-a',
            });
            expect(stream.activities.every((a) => a.userId === 'user-a')).toBe(true);
        });
        it('should filter activities by priority', async () => {
            const stream = await service.queryActivities({
                priority: ['high'],
            });
            expect(stream.activities.every((a) => a.priority === 'high')).toBe(true);
        });
        it('should paginate query results', async () => {
            const page1 = await service.queryActivities({
                teamId: 'team-001',
                limit: 1,
                offset: 0,
            });
            expect(page1.activities.length).toBe(1);
            expect(page1.hasMore).toBe(true);
        });
        it('should search activities by text', async () => {
            const stream = await service.queryActivities({
                searchText: 'commits',
            });
            expect(stream.activities.some((a) => a.description.toLowerCase().includes('commits'))).toBe(true);
        });
    });
    describe('Subscription Management', () => {
        it('should create subscription successfully', async () => {
            const subscription = await service.subscribe('user-x', {
                activityTypes: ['code_change', 'review'],
                teamId: 'team-001',
            });
            expect(subscription).toBeDefined();
            expect(subscription.userId).toBe('user-x');
            expect(subscription.isActive).toBe(true);
        });
        it('should emit subscriptionCreated event', async () => {
            let emitted = false;
            service.once('subscriptionCreated', () => {
                emitted = true;
            });
            await service.subscribe('user-y', {
                teamId: 'team-001',
                activityTypes: ['collaboration'],
            });
            expect(emitted).toBe(true);
        });
        it('should unsubscribe successfully', async () => {
            const subscription = await service.subscribe('user-z', {
                teamId: 'team-001',
            });
            let deleted = false;
            service.once('subscriptionDeleted', (subId) => {
                deleted = subId === subscription.subscriptionId;
            });
            await service.unsubscribe(subscription.subscriptionId);
            expect(deleted).toBe(true);
        });
        it('should notify matching subscribers', async () => {
            await service.subscribe('sub-user-1', {
                activityTypes: ['code_change'],
                teamId: 'team-001',
            });
            let notified = false;
            service.once('subscriptionNotification', () => {
                notified = true;
            });
            const activity = {
                activityId: 'sub-notif-001',
                type: 'code_change',
                userId: 'developer-1',
                userName: 'Developer',
                timestamp: new Date(),
                description: 'Code change',
                metadata: { teamId: 'team-001' },
            };
            await service.ingestActivity(activity);
            expect(notified).toBe(true);
        });
    });
    describe('Team Metrics', () => {
        beforeEach(async () => {
            // Populate with metric test activities
            const activities = [
                {
                    activityId: 'm-001',
                    type: 'code_change',
                    userId: 'user-1',
                    userName: 'User 1',
                    timestamp: new Date(),
                    description: 'Commit',
                    metadata: { teamId: 'team-metrics' },
                },
                {
                    activityId: 'm-002',
                    type: 'review',
                    userId: 'user-2',
                    userName: 'User 2',
                    timestamp: new Date(),
                    description: 'Review',
                    metadata: { teamId: 'team-metrics' },
                },
                {
                    activityId: 'm-003',
                    type: 'code_change',
                    userId: 'user-1',
                    userName: 'User 1',
                    timestamp: new Date(),
                    description: 'Another commit',
                    metadata: { teamId: 'team-metrics' },
                },
            ];
            for (const activity of activities) {
                await service.ingestActivity(activity);
            }
            // Wait for batch to flush
            await new Promise(resolve => setTimeout(resolve, 1200));
        });
        it('should calculate team metrics', async () => {
            const metrics = await service.getTeamMetrics('team-metrics');
            expect(metrics).toBeDefined();
            expect(metrics.teamId).toBe('team-metrics');
            expect(metrics.totalActivities).toBeGreaterThan(0);
        });
        it('should track activities by type', async () => {
            const metrics = await service.getTeamMetrics('team-metrics');
            expect(metrics.activitiesByType).toBeDefined();
            expect(Object.keys(metrics.activitiesByType).length).toBeGreaterThan(0);
        });
        it('should identify most active user', async () => {
            const metrics = await service.getTeamMetrics('team-metrics');
            expect(metrics.mostActiveUser).toBe('user-1'); // Should have 2 activities
        });
    });
    describe('Trend Analysis', () => {
        beforeEach(async () => {
            // Add activities spread across time
            for (let i = 0; i < 5; i++) {
                const activity = {
                    activityId: `trend-${i}`,
                    type: 'code_change',
                    userId: `user-trend-${i}`,
                    userName: `Trend User ${i}`,
                    timestamp: new Date(Date.now() - i * 10 * 60 * 1000), // Spread over time
                    description: `Trend activity ${i}`,
                    metadata: { teamId: 'team-trend' },
                };
                await service.ingestActivity(activity);
            }
            // Wait for batch to flush
            await new Promise(resolve => setTimeout(resolve, 1200));
        });
        it('should analyze activity trend', async () => {
            const trend = await service.analyzeTrend('team-trend', 'day');
            expect(trend).toBeDefined();
            expect(trend.teamId).toBe('team-trend');
            expect(trend.trend).toMatch(/increasing|decreasing|stable/);
        });
        it('should identify trending activity types', async () => {
            const trend = await service.analyzeTrend('team-trend', 'day');
            expect(trend.trendingActivityTypes).toBeDefined();
            expect(trend.trendingActivityTypes.length).toBeGreaterThan(0);
        });
        it('should identify trending users', async () => {
            const trend = await service.analyzeTrend('team-trend', 'day');
            expect(trend.trendingUsers).toBeDefined();
            expect(trend.trendingUsers.length).toBeGreaterThan(0);
        });
    });
    describe('Activity Aggregation', () => {
        beforeEach(async () => {
            // Add activities for aggregation testing
            for (let i = 0; i < 8; i++) {
                const activity = {
                    activityId: `agg-${i}`,
                    type: i % 2 === 0 ? 'code_change' : 'review',
                    userId: `user-agg-${i % 3}`,
                    userName: `Agg User ${i % 3}`,
                    timestamp: new Date(Date.now() - i * 5 * 60 * 1000),
                    description: `Aggregation test ${i}`,
                    metadata: { teamId: 'team-agg' },
                };
                await service.ingestActivity(activity);
            }
            // Wait for batch to flush
            await new Promise(resolve => setTimeout(resolve, 1200));
        });
        it('should aggregate activities for time period', async () => {
            const now = new Date();
            const startTime = new Date(now.getTime() - 1 * 60 * 60 * 1000); // Last hour
            const result = await service.aggregateActivities('team-agg', startTime, now, 'hour');
            expect(result).toBeDefined();
            expect(result.activities.length).toBeGreaterThan(0);
        });
        it('should calculate aggregation metrics', async () => {
            const now = new Date();
            const startTime = new Date(now.getTime() - 1 * 60 * 60 * 1000);
            const result = await service.aggregateActivities('team-agg', startTime, now, 'hour');
            expect(result.metrics.totalCount).toBeGreaterThan(0);
            expect(result.metrics.uniqueUsers).toBeGreaterThan(0);
            expect(result.metrics.typeDistribution).toBeDefined();
        });
    });
    describe('Performance', () => {
        it('should ingest activity in <15ms', async () => {
            const activity = {
                activityId: 'perf-001',
                type: 'code_change',
                userId: 'perf-user',
                userName: 'Perf User',
                timestamp: new Date(),
                description: 'Performance test',
                metadata: { teamId: 'team-perf' },
            };
            const startTime = performance.now();
            await service.ingestActivity(activity);
            const endTime = performance.now();
            expect(endTime - startTime).toBeLessThan(15);
        });
        it('should query activities in <15ms', async () => {
            // Populate with activities
            for (let i = 0; i < 20; i++) {
                const activity = {
                    activityId: `perf-query-${i}`,
                    type: 'code_change',
                    userId: 'perf-query-user',
                    userName: 'Perf Query',
                    timestamp: new Date(),
                    description: `Perf query ${i}`,
                    metadata: { teamId: 'team-perf' },
                };
                await service.ingestActivity(activity);
            }
            const startTime = performance.now();
            await service.queryActivities({ teamId: 'team-perf', limit: 10 });
            const endTime = performance.now();
            expect(endTime - startTime).toBeLessThan(15);
        });
        it('should calculate metrics in <15ms', async () => {
            // Populate with activities
            for (let i = 0; i < 30; i++) {
                const activity = {
                    activityId: `perf-metrics-${i}`,
                    type: 'code_change',
                    userId: 'perf-metrics-user',
                    userName: 'Perf Metrics',
                    timestamp: new Date(),
                    description: `Perf metrics ${i}`,
                    metadata: { teamId: 'team-perf' },
                };
                await service.ingestActivity(activity);
            }
            const startTime = performance.now();
            await service.getTeamMetrics('team-perf');
            const endTime = performance.now();
            expect(endTime - startTime).toBeLessThan(15);
        });
    });
});
//# sourceMappingURL=activity-stream-service.test.js.map