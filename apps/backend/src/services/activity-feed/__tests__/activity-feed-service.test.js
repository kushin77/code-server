/**
 * Activity Feed Service Tests
 * @file        apps/backend/src/services/activity-feed/__tests__/activity-feed-service.test.ts
 * @module      services/activity-feed
 * @description Test suite for activity feed functionality
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { ActivityFeedService } from '../activity-feed-service.js';
describe('Activity Feed Service', () => {
    let service;
    beforeEach(() => {
        ActivityFeedService.reset();
        service = ActivityFeedService.getInstance();
    });
    afterEach(() => {
        service.shutdown();
    });
    // Initialization Tests
    describe('Initialization', () => {
        it('should initialize service', () => {
            expect(service).toBeDefined();
            expect(service.activities).toBeDefined();
            expect(service.filters).toBeDefined();
        });
        it('should return same instance on subsequent calls', () => {
            const instance1 = ActivityFeedService.getInstance();
            const instance2 = ActivityFeedService.getInstance();
            expect(instance1).toBe(instance2);
        });
    });
    // Activity Recording Tests
    describe('Activity Recording', () => {
        it('should record activity', () => {
            const result = service.recordActivity({
                userId: 'user1',
                userEmail: 'user1@example.com',
                type: 'file_modified',
                entityId: 'file1',
                entityType: 'file',
                visibility: 'team',
                title: 'File modified',
                description: 'File was updated',
                tags: ['test'],
                collaborators: [],
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.activityId).toBeDefined();
        });
        it('should emit activity-recorded event', () => {
            return new Promise((resolve) => {
                service.once('activity-recorded', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.recordActivity({
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    type: 'file_modified',
                    entityId: 'file1',
                    entityType: 'file',
                    visibility: 'team',
                    title: 'File modified',
                    description: 'File was updated',
                    tags: ['test'],
                    collaborators: [],
                    metadata: {},
                }, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should retrieve recorded activity', () => {
            const recorded = service.recordActivity({
                userId: 'user1',
                userEmail: 'user1@example.com',
                type: 'file_created',
                entityId: 'file2',
                entityType: 'file',
                visibility: 'public',
                title: 'File created',
                description: 'New file added',
                tags: ['new'],
                collaborators: [],
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const activity = service.getActivity(recorded.activityId);
            expect(activity).toBeDefined();
            expect(activity?.type).toBe('file_created');
        });
    });
    // User Feed Tests
    describe('User Feed', () => {
        it('should get user feed', () => {
            service.recordActivity({
                userId: 'user1',
                userEmail: 'user1@example.com',
                type: 'file_modified',
                entityId: 'file1',
                entityType: 'file',
                visibility: 'team',
                title: 'File modified',
                description: 'File was updated',
                tags: ['test'],
                collaborators: [],
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const feed = service.getUserFeed('user1');
            expect(Array.isArray(feed)).toBe(true);
            expect(feed.length).toBeGreaterThan(0);
        });
        it('should get activity feed with entries', () => {
            service.recordActivity({
                userId: 'user1',
                userEmail: 'user1@example.com',
                type: 'file_modified',
                entityId: 'file1',
                entityType: 'file',
                visibility: 'team',
                title: 'File modified',
                description: 'File was updated',
                tags: ['test'],
                collaborators: [],
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const feed = service.getActivityFeed('user1');
            expect(Array.isArray(feed)).toBe(true);
        });
    });
    // Filter Tests
    describe('Filters', () => {
        it('should create filter', () => {
            const result = service.createFilter({
                userId: 'user1',
                types: ['file_modified'],
                enabled: true,
            }, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.filterId).toBeDefined();
        });
        it('should emit filter-created event', () => {
            return new Promise((resolve) => {
                service.once('filter-created', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.createFilter({
                    userId: 'user1',
                    types: ['file_modified'],
                    enabled: true,
                }, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should update filter', () => {
            const created = service.createFilter({
                userId: 'user1',
                types: ['file_modified'],
                enabled: true,
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.updateFilter(created.filterId, { enabled: false }, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should delete filter', () => {
            const created = service.createFilter({
                userId: 'user1',
                types: ['file_modified'],
                enabled: true,
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.deleteFilter(created.filterId, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should get filters', () => {
            const filters = service.getFilters('user1');
            expect(Array.isArray(filters)).toBe(true);
        });
    });
    // Activity Status Tests
    describe('Activity Status', () => {
        it('should mark activity as read', () => {
            const recorded = service.recordActivity({
                userId: 'user1',
                userEmail: 'user1@example.com',
                type: 'file_modified',
                entityId: 'file1',
                entityType: 'file',
                visibility: 'team',
                title: 'File modified',
                description: 'File was updated',
                tags: ['test'],
                collaborators: [],
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.markAsRead(recorded.activityId, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should emit activity-read event', () => {
            return new Promise((resolve) => {
                const recorded = service.recordActivity({
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    type: 'file_modified',
                    entityId: 'file1',
                    entityType: 'file',
                    visibility: 'team',
                    title: 'File modified',
                    description: 'File was updated',
                    tags: ['test'],
                    collaborators: [],
                    metadata: {},
                }, 'user1', '192.168.1.1', 'Mozilla');
                service.once('activity-read', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.markAsRead(recorded.activityId, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should mark feed as read', () => {
            service.recordActivity({
                userId: 'user1',
                userEmail: 'user1@example.com',
                type: 'file_modified',
                entityId: 'file1',
                entityType: 'file',
                visibility: 'team',
                title: 'File modified',
                description: 'File was updated',
                tags: ['test'],
                collaborators: [],
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.markFeedAsRead('user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should archive activity', () => {
            const recorded = service.recordActivity({
                userId: 'user1',
                userEmail: 'user1@example.com',
                type: 'file_modified',
                entityId: 'file1',
                entityType: 'file',
                visibility: 'team',
                title: 'File modified',
                description: 'File was updated',
                tags: ['test'],
                collaborators: [],
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.archiveActivity(recorded.activityId, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
    });
    // Engagement Tests
    describe('Engagement', () => {
        it('should get engagement metrics', () => {
            const recorded = service.recordActivity({
                userId: 'user1',
                userEmail: 'user1@example.com',
                type: 'file_modified',
                entityId: 'file1',
                entityType: 'file',
                visibility: 'team',
                title: 'File modified',
                description: 'File was updated',
                tags: ['test'],
                collaborators: [],
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const metrics = service.getEngagementMetrics(recorded.activityId);
            expect(metrics).toBeDefined();
            expect(metrics?.viewCount).toBe(0);
        });
        it('should record engagement', () => {
            const recorded = service.recordActivity({
                userId: 'user1',
                userEmail: 'user1@example.com',
                type: 'file_modified',
                entityId: 'file1',
                entityType: 'file',
                visibility: 'team',
                title: 'File modified',
                description: 'File was updated',
                tags: ['test'],
                collaborators: [],
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.recordEngagement(recorded.activityId, 'view', 'user2', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should emit engagement-recorded event', () => {
            return new Promise((resolve) => {
                const recorded = service.recordActivity({
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    type: 'file_modified',
                    entityId: 'file1',
                    entityType: 'file',
                    visibility: 'team',
                    title: 'File modified',
                    description: 'File was updated',
                    tags: ['test'],
                    collaborators: [],
                    metadata: {},
                }, 'user1', '192.168.1.1', 'Mozilla');
                service.once('engagement-recorded', (event) => {
                    expect(event.data_object.activityId).toBe(recorded.activityId);
                    resolve();
                });
                service.recordEngagement(recorded.activityId, 'view', 'user2', '192.168.1.1', 'Mozilla');
            });
        });
    });
    // Trends Tests
    describe('Trends', () => {
        it('should get trends', () => {
            const trends = service.getTrends('daily');
            expect(Array.isArray(trends)).toBe(true);
        });
    });
    // Statistics Tests
    describe('Statistics', () => {
        it('should get user statistics', () => {
            service.recordActivity({
                userId: 'user1',
                userEmail: 'user1@example.com',
                type: 'file_modified',
                entityId: 'file1',
                entityType: 'file',
                visibility: 'team',
                title: 'File modified',
                description: 'File was updated',
                tags: ['test'],
                collaborators: [],
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const stats = service.getUserStats('user1');
            expect(stats).toBeDefined();
            expect(stats.userId).toBe('user1');
        });
    });
    // Summary Tests
    describe('Summaries', () => {
        it('should generate summary', () => {
            const result = service.generateSummary('user1', 'daily', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.summaryId).toBeDefined();
        });
        it('should emit summary-generated event', () => {
            return new Promise((resolve) => {
                service.once('summary-generated', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.generateSummary('user1', 'daily', '192.168.1.1', 'Mozilla');
            });
        });
        it('should get summary', () => {
            const generated = service.generateSummary('user1', 'daily', '192.168.1.1', 'Mozilla');
            const summary = service.getSummary(generated.summaryId);
            expect(summary).toBeDefined();
        });
        it('should get recent summaries', () => {
            service.generateSummary('user1', 'daily', '192.168.1.1', 'Mozilla');
            const summaries = service.getRecentSummaries('user1');
            expect(Array.isArray(summaries)).toBe(true);
        });
    });
    // Batch Operations Tests
    describe('Batch Operations', () => {
        it('should batch record activities', () => {
            const result = service.batchRecordActivities([
                {
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    type: 'file_modified',
                    entityId: 'file1',
                    entityType: 'file',
                    visibility: 'team',
                    title: 'File modified',
                    description: 'File was updated',
                    tags: ['test'],
                    collaborators: [],
                    metadata: {},
                },
            ], 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.batchId).toBeDefined();
        });
        it('should emit batch-recorded event', () => {
            return new Promise((resolve) => {
                service.once('batch-recorded', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.batchRecordActivities([
                    {
                        userId: 'user1',
                        userEmail: 'user1@example.com',
                        type: 'file_modified',
                        entityId: 'file1',
                        entityType: 'file',
                        visibility: 'team',
                        title: 'File modified',
                        description: 'File was updated',
                        tags: ['test'],
                        collaborators: [],
                        metadata: {},
                    },
                ], 'user1', '192.168.1.1', 'Mozilla');
            });
        });
    });
    // Audit Logging Tests
    describe('Audit Logging', () => {
        it('should emit audit-logged event', () => {
            return new Promise((resolve) => {
                service.once('audit-logged', (event) => {
                    expect(event.data_object.userId).toBeDefined();
                    resolve();
                });
                service.recordActivity({
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    type: 'file_modified',
                    entityId: 'file1',
                    entityType: 'file',
                    visibility: 'team',
                    title: 'File modified',
                    description: 'File was updated',
                    tags: ['test'],
                    collaborators: [],
                    metadata: {},
                }, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should retrieve audit log', () => {
            const log = service.getAuditLog();
            expect(Array.isArray(log)).toBe(true);
        });
    });
    // Cleanup Tests
    describe('Cleanup', () => {
        it('should cleanup old activities', () => {
            const result = service.cleanupOldActivities(90, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should emit cleanup-completed event', () => {
            return new Promise((resolve) => {
                service.once('cleanup-completed', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.cleanupOldActivities(90, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
    });
    // Configuration Tests
    describe('Configuration', () => {
        it('should update configuration', () => {
            return new Promise((resolve) => {
                service.once('config-updated', (event) => {
                    expect(event.data_object.config).toBeDefined();
                    resolve();
                });
                service.updateConfig({ enableActivityFeed: false });
            });
        });
    });
    // Shutdown Tests
    describe('Shutdown', () => {
        it('should shutdown service cleanly', () => {
            service.shutdown();
            expect(service.activities.size).toBe(0);
            expect(service.filters.size).toBe(0);
        });
    });
});
//# sourceMappingURL=activity-feed-service.test.js.map