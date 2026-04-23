#!/usr/bin/env node
// @file        apps/backend/src/services/help-queue/__tests__/help-queue-audit.test.ts
// @module      services/help-queue
// @description Tests for Help Queue audit logging service
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { HelpQueueAuditService } from '../help-queue-audit';
let service;
describe('HelpQueueAuditService', () => {
    beforeEach(() => {
        service = HelpQueueAuditService.getInstance();
        service.reset();
    });
    afterEach(() => {
        service.removeAllListeners();
    });
    describe('Queue Item Audit Logging', () => {
        it('should log queue item creation', () => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            const entry = service.logQueueItemEvent('user-alice', 'CREATE_QUEUE_ITEM', 'qi-123', 'ws-1', true, { title: 'Help with debugging', priority: 'high' });
            expect(entry).toBeDefined();
            expect(entry.action).toBe('CREATE_QUEUE_ITEM');
            expect(entry.queueItemId).toBe('qi-123');
            expect(entry.success).toBe(true);
            expect(entry._immutable).toBe(true);
            expect(entry.userEmail).toBe('alice@kushnir.cloud');
        });
        it('should log queue item assignment', () => {
            service.setUserContext('bob@kushnir.cloud', 'manager');
            const entry = service.logQueueItemEvent('user-bob', 'ASSIGN_EXPERT', 'qi-123', 'ws-1', true, { assignedTo: 'user-alice', assignmentTime: Date.now() });
            expect(entry.action).toBe('ASSIGN_EXPERT');
            expect(entry.metadata?.assignedTo).toBe('user-alice');
        });
        it('should log failed queue item operations', () => {
            service.setUserContext('bob@kushnir.cloud', 'manager');
            const entry = service.logQueueItemEvent('user-bob', 'RESOLVE_QUEUE_ITEM', 'qi-999', 'ws-1', false, {}, 'Queue item not found');
            expect(entry.success).toBe(false);
            expect(entry.errorMessage).toBe('Queue item not found');
        });
        it('should log queue item responses', () => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            const entry = service.logQueueItemEvent('user-alice', 'ADD_RESPONSE', 'qi-123', 'ws-1', true, { responseLength: 250, responseTime: '2 hours' });
            expect(entry.action).toBe('ADD_RESPONSE');
            expect(entry.metadata?.responseLength).toBe(250);
        });
        it('should log queue item resolution', () => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            const entry = service.logQueueItemEvent('user-alice', 'RESOLVE_QUEUE_ITEM', 'qi-123', 'ws-1', true, { resolvedBy: 'user-alice', resolutionTime: '4 hours' });
            expect(entry.action).toBe('RESOLVE_QUEUE_ITEM');
            expect(entry.success).toBe(true);
        });
    });
    describe('Expert Audit Logging', () => {
        it('should log expert registration', () => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            const entry = service.logExpertEvent('user-alice', 'REGISTER_EXPERT', 'expert-alice', 'ws-1', true, { expertise: ['debugging', 'performance'], availability: 'full-time' });
            expect(entry.action).toBe('REGISTER_EXPERT');
            expect(entry.resourceType).toBe('EXPERT');
            expect(entry.expertId).toBe('expert-alice');
        });
        it('should log expert profile updates', () => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            const entry = service.logExpertEvent('user-alice', 'UPDATE_EXPERT_PROFILE', 'expert-alice', 'ws-1', true, { previousExpertise: ['debugging'], newExpertise: ['debugging', 'performance'] });
            expect(entry.action).toBe('UPDATE_EXPERT_PROFILE');
            expect(entry.metadata?.newExpertise).toContain('performance');
        });
        it('should log expert availability changes', () => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            const entry = service.logExpertEvent('user-alice', 'MARK_EXPERT_AVAILABLE', 'expert-alice', 'ws-1', true, { availabilityStatus: 'available', lastStatusChange: Date.now() });
            expect(entry.action).toBe('MARK_EXPERT_AVAILABLE');
            expect(entry.metadata?.availabilityStatus).toBe('available');
        });
        it('should log failed expert operations', () => {
            service.setUserContext('bob@kushnir.cloud', 'manager');
            const entry = service.logExpertEvent('user-bob', 'UPDATE_EXPERT_PROFILE', 'expert-999', 'ws-1', false, {}, 'Expert not found');
            expect(entry.success).toBe(false);
            expect(entry.errorMessage).toBe('Expert not found');
        });
    });
    describe('Querying Audit Logs', () => {
        beforeEach(() => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            service.logQueueItemEvent('user-alice', 'CREATE_QUEUE_ITEM', 'qi-1', 'ws-1', true);
            service.logQueueItemEvent('user-bob', 'ASSIGN_EXPERT', 'qi-1', 'ws-1', true);
            service.logQueueItemEvent('user-alice', 'ADD_RESPONSE', 'qi-1', 'ws-1', true);
            service.logQueueItemEvent('user-alice', 'RESOLVE_QUEUE_ITEM', 'qi-1', 'ws-1', true);
        });
        it('should get all logs for workspace', () => {
            const logs = service.getWorkspaceLogs('ws-1');
            expect(logs.length).toBe(4);
        });
        it('should query by userId', () => {
            const result = service.queryLogs('ws-1', { userId: 'user-alice' });
            expect(result.total).toBe(3);
            expect(result.entries.every((e) => e.userId === 'user-alice')).toBe(true);
        });
        it('should query by action', () => {
            const result = service.queryLogs('ws-1', { action: 'CREATE_QUEUE_ITEM' });
            expect(result.total).toBe(1);
            expect(result.entries[0].action).toBe('CREATE_QUEUE_ITEM');
        });
        it('should query by queue item ID', () => {
            const result = service.queryLogs('ws-1', { queueItemId: 'qi-1' });
            expect(result.total).toBe(4);
            expect(result.entries.every((e) => e.queueItemId === 'qi-1')).toBe(true);
        });
        it('should filter by success', () => {
            service.logQueueItemEvent('user-bob', 'ASSIGN_EXPERT', 'qi-2', 'ws-1', false, {}, 'Failed');
            const result = service.queryLogs('ws-1', { success: false });
            expect(result.total).toBe(1);
            expect(result.entries[0].success).toBe(false);
        });
        it('should support pagination', () => {
            const result1 = service.queryLogs('ws-1', { limit: 2, offset: 0 });
            const result2 = service.queryLogs('ws-1', { limit: 2, offset: 2 });
            expect(result1.entries.length).toBe(2);
            expect(result2.entries.length).toBe(2);
            expect(result1.total).toBe(4);
        });
        it('should filter by time range', () => {
            const now = Date.now();
            const result = service.queryLogs('ws-1', {
                startTime: now - 10000,
                endTime: now + 10000,
            });
            expect(result.total).toBeGreaterThan(0);
        });
    });
    describe('Statistics and Compliance', () => {
        beforeEach(() => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            service.logQueueItemEvent('user-alice', 'CREATE_QUEUE_ITEM', 'qi-1', 'ws-1', true);
            service.logQueueItemEvent('user-alice', 'ASSIGN_EXPERT', 'qi-1', 'ws-1', true);
            service.logQueueItemEvent('user-alice', 'ADD_RESPONSE', 'qi-1', 'ws-1', true);
            service.logQueueItemEvent('user-alice', 'RESOLVE_QUEUE_ITEM', 'qi-1', 'ws-1', true);
            service.logQueueItemEvent('user-bob', 'CREATE_QUEUE_ITEM', 'qi-2', 'ws-1', false, {}, 'Permission denied');
        });
        it('should calculate statistics', () => {
            const stats = service.getStatistics('ws-1');
            expect(stats.totalEntries).toBe(5);
            expect(stats.entriesByAction['CREATE_QUEUE_ITEM']).toBe(2);
            expect(stats.entriesByAction['ASSIGN_EXPERT']).toBe(1);
            expect(stats.entriesByResourceType['QUEUE_ITEM']).toBe(5);
            expect(stats.failureRate).toBe(0.2); // 1 out of 5
        });
        it('should identify failed actions in statistics', () => {
            const stats = service.getStatistics('ws-1');
            expect(stats.failuresByAction['CREATE_QUEUE_ITEM']).toBe(1);
            expect(stats.successRate).toBe(0.8);
        });
        it('should return 0 stats for empty workspace', () => {
            const stats = service.getStatistics('ws-empty');
            expect(stats.totalEntries).toBe(0);
            expect(stats.successRate).toBe(1);
            expect(stats.failureRate).toBe(0);
        });
    });
    describe('Immutability and Integrity', () => {
        it('should mark all entries as immutable', () => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            const entry = service.logQueueItemEvent('user-alice', 'CREATE_QUEUE_ITEM', 'qi-1', 'ws-1', true);
            expect(entry._immutable).toBe(true);
            expect(entry._createdAt).toBeDefined();
            expect(entry._createdAt).toBeGreaterThan(0);
        });
        it('should preserve timestamp consistency', () => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            const entry = service.logQueueItemEvent('user-alice', 'CREATE_QUEUE_ITEM', 'qi-1', 'ws-1', true);
            expect(entry.timestamp).toBeGreaterThanOrEqual(entry._createdAt - 1000);
            expect(entry.timestamp).toBeLessThanOrEqual(entry._createdAt + 1000);
        });
    });
    describe('Event Emission', () => {
        it('should emit audit-logged event', async () => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            const eventPromise = new Promise((resolve) => {
                service.once('audit-logged', (entry) => {
                    expect(entry.action).toBe('CREATE_QUEUE_ITEM');
                    expect(entry.queueItemId).toBe('qi-1');
                    resolve(null);
                });
            });
            service.logQueueItemEvent('user-alice', 'CREATE_QUEUE_ITEM', 'qi-1', 'ws-1', true);
            await eventPromise;
        });
    });
    describe('Singleton Pattern', () => {
        it('should return same instance from getInstance', () => {
            const instance1 = HelpQueueAuditService.getInstance();
            const instance2 = HelpQueueAuditService.getInstance();
            expect(instance1).toBe(instance2);
        });
        it('should share state across getInstance calls', () => {
            const instance1 = HelpQueueAuditService.getInstance();
            instance1.reset();
            instance1.setUserContext('alice@kushnir.cloud', 'expert');
            instance1.logQueueItemEvent('user-alice', 'CREATE_QUEUE_ITEM', 'qi-1', 'ws-1', true);
            const instance2 = HelpQueueAuditService.getInstance();
            const logs = instance2.getWorkspaceLogs('ws-1');
            expect(logs.length).toBe(1);
        });
    });
    describe('User Context', () => {
        it('should include user context in entries', () => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            const entry = service.logQueueItemEvent('user-alice', 'CREATE_QUEUE_ITEM', 'qi-1', 'ws-1', true);
            expect(entry.userEmail).toBe('alice@kushnir.cloud');
            expect(entry.userRole).toBe('expert');
        });
        it('should clear user context on reset', () => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            service.reset();
            const entry = service.logQueueItemEvent('user-alice', 'CREATE_QUEUE_ITEM', 'qi-1', 'ws-1', true);
            expect(entry.userEmail).toBeUndefined();
            expect(entry.userRole).toBeUndefined();
        });
    });
    describe('Integration Scenarios', () => {
        it('should handle complete help queue workflow', () => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            // User creates queue item
            service.logQueueItemEvent('user-requester', 'CREATE_QUEUE_ITEM', 'qi-1', 'ws-1', true, {
                title: 'Help needed',
            });
            // Manager assigns expert
            service.setUserContext('bob@kushnir.cloud', 'manager');
            service.logQueueItemEvent('user-bob', 'ASSIGN_EXPERT', 'qi-1', 'ws-1', true, {
                assignedTo: 'user-alice',
            });
            // Expert adds response
            service.setUserContext('alice@kushnir.cloud', 'expert');
            service.logQueueItemEvent('user-alice', 'ADD_RESPONSE', 'qi-1', 'ws-1', true, {
                responseLength: 300,
            });
            // Expert resolves
            service.logQueueItemEvent('user-alice', 'RESOLVE_QUEUE_ITEM', 'qi-1', 'ws-1', true);
            // Verify complete audit trail
            const logs = service.getWorkspaceLogs('ws-1');
            expect(logs.length).toBe(4);
            expect(logs[0].action).toBe('CREATE_QUEUE_ITEM');
            expect(logs[1].action).toBe('ASSIGN_EXPERT');
            expect(logs[2].action).toBe('ADD_RESPONSE');
            expect(logs[3].action).toBe('RESOLVE_QUEUE_ITEM');
            // Verify statistics
            const stats = service.getStatistics('ws-1');
            expect(stats.totalEntries).toBe(4);
            expect(stats.successRate).toBe(1);
        });
    });
});
//# sourceMappingURL=help-queue-audit.test.js.map