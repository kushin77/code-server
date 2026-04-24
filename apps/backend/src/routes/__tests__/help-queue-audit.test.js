#!/usr/bin/env node
// @file        apps/backend/src/routes/__tests__/help-queue-audit.test.ts
// @module      routes
// @description Tests for Help Queue audit routes
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import express from 'express';
import router from '../help-queue-audit';
import { HelpQueueAuditService } from '../../services/help-queue/help-queue-audit';
let app;
let service;
describe('Help Queue Audit Routes', () => {
    beforeEach(() => {
        app = express();
        app.use(express.json());
        app.use('/api/help-queue-audit', router);
        service = HelpQueueAuditService.getInstance();
        service.reset();
    });
    afterEach(() => {
        service.removeAllListeners();
    });
    describe('POST /queue-items', () => {
        it('should log queue item event', async () => {
            const response = await request(app)
                .post('/api/help-queue-audit/queue-items')
                .send({
                userId: 'user-alice',
                action: 'CREATE_QUEUE_ITEM',
                queueItemId: 'qi-1',
                workspaceId: 'ws-1',
                success: true,
                metadata: { title: 'Help needed' },
                userEmail: 'alice@kushnir.cloud',
                userRole: 'user',
            });
            expect(response.status).toBe(201);
            expect(response.body.success).toBe(true);
            expect(response.body.data.action).toBe('CREATE_QUEUE_ITEM');
            expect(response.body.data.queueItemId).toBe('qi-1');
            expect(response.body.data._immutable).toBe(true);
        });
        it('should validate required fields', async () => {
            const response = await request(app)
                .post('/api/help-queue-audit/queue-items')
                .send({
                userId: 'user-alice',
                // Missing action, queueItemId, workspaceId
            });
            expect(response.status).toBe(400);
            expect(response.body.success).toBe(false);
            expect(response.body.error).toContain('Missing required fields');
        });
        it('should log failed operations', async () => {
            const response = await request(app)
                .post('/api/help-queue-audit/queue-items')
                .send({
                userId: 'user-bob',
                action: 'ASSIGN_EXPERT',
                queueItemId: 'qi-999',
                workspaceId: 'ws-1',
                success: false,
                errorMessage: 'Queue item not found',
                userEmail: 'bob@kushnir.cloud',
                userRole: 'manager',
            });
            expect(response.status).toBe(201);
            expect(response.body.data.success).toBe(false);
            expect(response.body.data.errorMessage).toBe('Queue item not found');
        });
        it('should include metadata in log', async () => {
            const response = await request(app)
                .post('/api/help-queue-audit/queue-items')
                .send({
                userId: 'user-alice',
                action: 'ADD_RESPONSE',
                queueItemId: 'qi-1',
                workspaceId: 'ws-1',
                success: true,
                metadata: { responseLength: 250, responseTime: '2 hours' },
            });
            expect(response.status).toBe(201);
            expect(response.body.data.metadata.responseLength).toBe(250);
            expect(response.body.data.metadata.responseTime).toBe('2 hours');
        });
    });
    describe('POST /experts', () => {
        it('should log expert event', async () => {
            const response = await request(app)
                .post('/api/help-queue-audit/experts')
                .send({
                userId: 'user-alice',
                action: 'REGISTER_EXPERT',
                expertId: 'expert-alice',
                workspaceId: 'ws-1',
                success: true,
                metadata: { expertise: ['debugging', 'performance'] },
                userEmail: 'alice@kushnir.cloud',
                userRole: 'expert',
            });
            expect(response.status).toBe(201);
            expect(response.body.success).toBe(true);
            expect(response.body.data.action).toBe('REGISTER_EXPERT');
            expect(response.body.data.expertId).toBe('expert-alice');
        });
        it('should validate required fields for expert events', async () => {
            const response = await request(app)
                .post('/api/help-queue-audit/experts')
                .send({
                userId: 'user-alice',
                // Missing expertId, action, workspaceId
            });
            expect(response.status).toBe(400);
            expect(response.body.success).toBe(false);
        });
        it('should log expert profile updates', async () => {
            const response = await request(app)
                .post('/api/help-queue-audit/experts')
                .send({
                userId: 'user-alice',
                action: 'UPDATE_EXPERT_PROFILE',
                expertId: 'expert-alice',
                workspaceId: 'ws-1',
                success: true,
                metadata: {
                    previousExpertise: ['debugging'],
                    newExpertise: ['debugging', 'performance'],
                },
            });
            expect(response.status).toBe(201);
            expect(response.body.data.metadata.newExpertise).toContain('performance');
        });
    });
    describe('GET /workspace/:workspaceId/logs', () => {
        beforeEach(() => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            service.logQueueItemEvent('user-alice', 'CREATE_QUEUE_ITEM', 'qi-1', 'ws-1', true);
            service.logQueueItemEvent('user-bob', 'ASSIGN_EXPERT', 'qi-1', 'ws-1', true);
            service.logQueueItemEvent('user-alice', 'ADD_RESPONSE', 'qi-1', 'ws-1', true);
            service.logQueueItemEvent('user-alice', 'RESOLVE_QUEUE_ITEM', 'qi-1', 'ws-1', true);
        });
        it('should get all logs', async () => {
            const response = await request(app)
                .get('/api/help-queue-audit/workspace/ws-1/logs');
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data.entries.length).toBe(4);
            expect(response.body.data.total).toBe(4);
        });
        it('should filter by userId', async () => {
            const response = await request(app)
                .get('/api/help-queue-audit/workspace/ws-1/logs')
                .query({ userId: 'user-alice' });
            expect(response.status).toBe(200);
            expect(response.body.data.entries.length).toBe(3);
            expect(response.body.data.total).toBe(3);
            expect(response.body.data.entries.every((e) => e.userId === 'user-alice')).toBe(true);
        });
        it('should filter by action', async () => {
            const response = await request(app)
                .get('/api/help-queue-audit/workspace/ws-1/logs')
                .query({ action: 'CREATE_QUEUE_ITEM' });
            expect(response.status).toBe(200);
            expect(response.body.data.entries.length).toBe(1);
            expect(response.body.data.entries[0].action).toBe('CREATE_QUEUE_ITEM');
        });
        it('should filter by queueItemId', async () => {
            const response = await request(app)
                .get('/api/help-queue-audit/workspace/ws-1/logs')
                .query({ queueItemId: 'qi-1' });
            expect(response.status).toBe(200);
            expect(response.body.data.total).toBe(4);
        });
        it('should filter by success', async () => {
            service.logQueueItemEvent('user-bob', 'ASSIGN_EXPERT', 'qi-2', 'ws-1', false, {}, 'Failed');
            const response = await request(app)
                .get('/api/help-queue-audit/workspace/ws-1/logs')
                .query({ success: 'false' });
            expect(response.status).toBe(200);
            expect(response.body.data.entries.length).toBe(1);
            expect(response.body.data.entries[0].success).toBe(false);
        });
        it('should support pagination', async () => {
            const response1 = await request(app)
                .get('/api/help-queue-audit/workspace/ws-1/logs')
                .query({ limit: 2, offset: 0 });
            const response2 = await request(app)
                .get('/api/help-queue-audit/workspace/ws-1/logs')
                .query({ limit: 2, offset: 2 });
            expect(response1.body.data.entries.length).toBe(2);
            expect(response2.body.data.entries.length).toBe(2);
            expect(response1.body.data.total).toBe(4);
        });
        it('should filter by time range', async () => {
            const now = Date.now();
            const response = await request(app)
                .get('/api/help-queue-audit/workspace/ws-1/logs')
                .query({
                startTime: now - 10000,
                endTime: now + 10000,
            });
            expect(response.status).toBe(200);
            expect(response.body.data.entries.length).toBeGreaterThan(0);
        });
        it('should return empty array for non-existent workspace', async () => {
            const response = await request(app)
                .get('/api/help-queue-audit/workspace/ws-nonexistent/logs');
            expect(response.status).toBe(200);
            expect(response.body.data.entries.length).toBe(0);
            expect(response.body.data.total).toBe(0);
        });
    });
    describe('GET /workspace/:workspaceId/statistics', () => {
        beforeEach(() => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            service.logQueueItemEvent('user-alice', 'CREATE_QUEUE_ITEM', 'qi-1', 'ws-1', true);
            service.logQueueItemEvent('user-alice', 'ASSIGN_EXPERT', 'qi-1', 'ws-1', true);
            service.logQueueItemEvent('user-alice', 'ADD_RESPONSE', 'qi-1', 'ws-1', true);
            service.logQueueItemEvent('user-alice', 'RESOLVE_QUEUE_ITEM', 'qi-1', 'ws-1', true);
            service.logQueueItemEvent('user-bob', 'CREATE_QUEUE_ITEM', 'qi-2', 'ws-1', false, {}, 'Permission denied');
        });
        it('should get statistics', async () => {
            const response = await request(app)
                .get('/api/help-queue-audit/workspace/ws-1/statistics');
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data.totalEntries).toBe(5);
            expect(response.body.data.successRate).toBe(0.8);
            expect(response.body.data.failureRate).toBe(0.2);
        });
        it('should have action breakdown in statistics', async () => {
            const response = await request(app)
                .get('/api/help-queue-audit/workspace/ws-1/statistics');
            expect(response.status).toBe(200);
            expect(response.body.data.entriesByAction.CREATE_QUEUE_ITEM).toBe(2);
            expect(response.body.data.entriesByAction.ASSIGN_EXPERT).toBe(1);
        });
        it('should track failures by action', async () => {
            const response = await request(app)
                .get('/api/help-queue-audit/workspace/ws-1/statistics');
            expect(response.status).toBe(200);
            expect(response.body.data.failuresByAction.CREATE_QUEUE_ITEM).toBe(1);
        });
        it('should return zero stats for empty workspace', async () => {
            const response = await request(app)
                .get('/api/help-queue-audit/workspace/ws-empty/statistics');
            expect(response.status).toBe(200);
            expect(response.body.data.totalEntries).toBe(0);
            expect(response.body.data.successRate).toBe(1);
        });
    });
    describe('GET /workspace/:workspaceId', () => {
        beforeEach(() => {
            service.setUserContext('alice@kushnir.cloud', 'expert');
            service.logQueueItemEvent('user-alice', 'CREATE_QUEUE_ITEM', 'qi-1', 'ws-1', true);
            service.logQueueItemEvent('user-alice', 'ADD_RESPONSE', 'qi-1', 'ws-1', true);
        });
        it('should get all workspace logs', async () => {
            const response = await request(app)
                .get('/api/help-queue-audit/workspace/ws-1');
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data.entries.length).toBe(2);
            expect(response.body.data.total).toBe(2);
        });
        it('should include immutable markers', async () => {
            const response = await request(app)
                .get('/api/help-queue-audit/workspace/ws-1');
            expect(response.status).toBe(200);
            expect(response.body.data.entries[0]._immutable).toBe(true);
            expect(response.body.data.entries[0]._createdAt).toBeDefined();
        });
    });
    describe('GET /health', () => {
        it('should return health status', async () => {
            const response = await request(app)
                .get('/api/help-queue-audit/health');
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data.status).toBe('ok');
            expect(response.body.data.service).toBe('help-queue-audit');
        });
    });
    describe('Integration Tests', () => {
        it('should handle complete workflow', async () => {
            // Log queue item creation
            await request(app)
                .post('/api/help-queue-audit/queue-items')
                .send({
                userId: 'user-requester',
                action: 'CREATE_QUEUE_ITEM',
                queueItemId: 'qi-1',
                workspaceId: 'ws-1',
                success: true,
                metadata: { title: 'Help needed' },
            });
            // Log expert registration
            await request(app)
                .post('/api/help-queue-audit/experts')
                .send({
                userId: 'user-alice',
                action: 'REGISTER_EXPERT',
                expertId: 'expert-alice',
                workspaceId: 'ws-1',
                success: true,
            });
            // Log assignment
            await request(app)
                .post('/api/help-queue-audit/queue-items')
                .send({
                userId: 'user-manager',
                action: 'ASSIGN_EXPERT',
                queueItemId: 'qi-1',
                workspaceId: 'ws-1',
                success: true,
                metadata: { assignedTo: 'expert-alice' },
            });
            // Query logs
            const logsResponse = await request(app)
                .get('/api/help-queue-audit/workspace/ws-1/logs');
            expect(logsResponse.body.data.total).toBe(3);
            // Get statistics
            const statsResponse = await request(app)
                .get('/api/help-queue-audit/workspace/ws-1/statistics');
            expect(statsResponse.body.data.totalEntries).toBe(3);
            expect(statsResponse.body.data.successRate).toBe(1);
        });
    });
});
//# sourceMappingURL=help-queue-audit.test.js.map