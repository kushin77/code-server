#!/usr/bin/env node
// @file        apps/backend/src/routes/__tests__/code-review-request.test.ts
// @module      routes/collaboration
// @description Tests for code review request routes
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import express from 'express';
import codeReviewRouter from '../code-review-request';
import service from '../../services/collaboration/code-review-request-service';
describe('Code Review Request Routes', () => {
    let app;
    beforeEach(() => {
        app = express();
        app.use(express.json());
        app.use('/api/reviews', codeReviewRouter);
        service.reset();
        service.removeAllListeners();
    });
    afterEach(() => {
        service.reset();
        service.removeAllListeners();
    });
    describe('POST /api/reviews', () => {
        it('should create a new code review request', async () => {
            const response = await request(app)
                .post('/api/reviews')
                .send({
                requesterId: 'user1',
                reviewerId: 'user2',
                workspaceId: 'ws-123',
                contextNote: 'Please review this PR',
                priority: 'high',
                filePath: '/src/app.ts',
            });
            expect(response.status).toBe(201);
            expect(response.body.success).toBe(true);
            expect(response.body.data.id).toBeDefined();
            expect(response.body.data.priority).toBe('high');
        });
        it('should return 400 for missing required fields', async () => {
            const response = await request(app)
                .post('/api/reviews')
                .send({
                requesterId: 'user1',
                // missing other fields
            });
            expect(response.status).toBe(400);
            expect(response.body.success).toBe(false);
        });
    });
    describe('GET /api/reviews/:requestId', () => {
        it('should get a code review request', async () => {
            const request_obj = service.createRequest('user1', 'user2', 'ws-123', 'Review this');
            const response = await request(app)
                .get(`/api/reviews/${request_obj.id}`);
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data.id).toBe(request_obj.id);
        });
        it('should return 404 for non-existent request', async () => {
            const response = await request(app)
                .get('/api/reviews/non-existent');
            expect(response.status).toBe(404);
            expect(response.body.success).toBe(false);
        });
    });
    describe('GET /api/reviews/reviewer/:reviewerId/pending', () => {
        it('should get pending requests for reviewer', async () => {
            service.createRequest('user1', 'user2', 'ws-123', 'Review 1');
            service.createRequest('user3', 'user2', 'ws-123', 'Review 2');
            const response = await request(app)
                .get('/api/reviews/reviewer/user2/pending');
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data).toHaveLength(2);
        });
    });
    describe('GET /api/reviews/requester/:requesterId', () => {
        it('should get requests from requester', async () => {
            service.createRequest('user1', 'user2', 'ws-123', 'Review 1');
            service.createRequest('user1', 'user3', 'ws-123', 'Review 2');
            const response = await request(app)
                .get('/api/reviews/requester/user1');
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data).toHaveLength(2);
        });
    });
    describe('POST /api/reviews/:requestId/respond', () => {
        it('should respond to a review request with approval', async () => {
            const req_obj = service.createRequest('user1', 'user2', 'ws-123', 'Review');
            const response = await request(app)
                .post(`/api/reviews/${req_obj.id}/respond`)
                .send({
                reviewerId: 'user2',
                status: 'approved',
                comment: 'Looks good',
            });
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data.status).toBe('approved');
        });
        it('should return 400 for invalid status', async () => {
            const req_obj = service.createRequest('user1', 'user2', 'ws-123', 'Review');
            const response = await request(app)
                .post(`/api/reviews/${req_obj.id}/respond`)
                .send({
                reviewerId: 'user2',
                status: 'invalid',
                comment: 'Comment',
            });
            expect(response.status).toBe(400);
            expect(response.body.success).toBe(false);
        });
        it('should return 404 for non-existent request', async () => {
            const response = await request(app)
                .post('/api/reviews/non-existent/respond')
                .send({
                reviewerId: 'user2',
                status: 'approved',
                comment: 'Good',
            });
            expect(response.status).toBe(404);
            expect(response.body.success).toBe(false);
        });
    });
    describe('POST /api/reviews/:requestId/dismiss', () => {
        it('should dismiss a review request', async () => {
            const req_obj = service.createRequest('user1', 'user2', 'ws-123', 'Review');
            const response = await request(app)
                .post(`/api/reviews/${req_obj.id}/dismiss`);
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data.status).toBe('dismissed');
        });
    });
    describe('PATCH /api/reviews/:requestId/due-date', () => {
        it('should set due date for review request', async () => {
            const req_obj = service.createRequest('user1', 'user2', 'ws-123', 'Review');
            const dueAt = Date.now() + 24 * 60 * 60 * 1000;
            const response = await request(app)
                .patch(`/api/reviews/${req_obj.id}/due-date`)
                .send({ dueAt });
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data.dueAt).toBe(dueAt);
        });
        it('should return 400 for invalid dueAt', async () => {
            const req_obj = service.createRequest('user1', 'user2', 'ws-123', 'Review');
            const response = await request(app)
                .patch(`/api/reviews/${req_obj.id}/due-date`)
                .send({ dueAt: 'invalid' });
            expect(response.status).toBe(400);
            expect(response.body.success).toBe(false);
        });
    });
    describe('GET /api/reviews/overdue/list', () => {
        it('should get overdue requests', async () => {
            const pastDue = Date.now() - 1000;
            const req_obj = service.createRequest('user1', 'user2', 'ws-123', 'Review', 'normal', undefined, pastDue);
            const response = await request(app)
                .get('/api/reviews/overdue/list');
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data).toHaveLength(1);
        });
    });
    describe('POST /api/reviews/:requestId/remind', () => {
        it('should send reminder for review request', async () => {
            const req_obj = service.createRequest('user1', 'user2', 'ws-123', 'Review');
            const response = await request(app)
                .post(`/api/reviews/${req_obj.id}/remind`);
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
        });
    });
    describe('GET /api/reviews/notifications/:userId', () => {
        it('should get notifications for user', async () => {
            service.createRequest('user1', 'user2', 'ws-123', 'Review');
            const response = await request(app)
                .get('/api/reviews/notifications/user2');
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data).toHaveLength(1);
        });
    });
    describe('PATCH /api/reviews/notifications/:notificationId/read', () => {
        it('should mark notification as read', async () => {
            service.createRequest('user1', 'user2', 'ws-123', 'Review');
            const notifications = service.getNotificationsForUser('user2');
            const response = await request(app)
                .patch(`/api/reviews/notifications/${notifications[0].id}/read`);
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data.read).toBe(true);
        });
    });
    describe('GET /api/reviews/unread-count/:userId', () => {
        it('should get unread notification count', async () => {
            service.createRequest('user1', 'user2', 'ws-123', 'Review 1');
            service.createRequest('user1', 'user2', 'ws-123', 'Review 2');
            const response = await request(app)
                .get('/api/reviews/unread-count/user2');
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data.unreadCount).toBe(2);
        });
    });
    describe('GET /api/reviews/reviewer/:reviewerId/stats', () => {
        it('should get reviewer statistics', async () => {
            const req_obj = service.createRequest('user1', 'user2', 'ws-123', 'Review');
            service.respondToRequest(req_obj.id, 'user2', 'approved', 'Good');
            const response = await request(app)
                .get('/api/reviews/reviewer/user2/stats');
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data.approvedCount).toBe(1);
        });
    });
    describe('GET /api/reviews/workspace/:workspaceId/requests', () => {
        it('should get workspace requests', async () => {
            service.createRequest('user1', 'user2', 'ws-123', 'Review 1');
            service.createRequest('user1', 'user2', 'ws-123', 'Review 2');
            service.createRequest('user1', 'user2', 'ws-456', 'Review 3');
            const response = await request(app)
                .get('/api/reviews/workspace/ws-123/requests');
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data).toHaveLength(2);
        });
    });
    describe('GET /api/reviews/workspace/:workspaceId/stats', () => {
        it('should get workspace statistics', async () => {
            service.createRequest('user1', 'user2', 'ws-123', 'Review 1', 'high');
            service.createRequest('user1', 'user2', 'ws-123', 'Review 2', 'normal');
            const response = await request(app)
                .get('/api/reviews/workspace/ws-123/stats');
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
            expect(response.body.data.pendingRequests).toBe(2);
            expect(response.body.data.highPriorityPending).toBe(1);
        });
    });
    describe('POST /api/reviews/expire-old', () => {
        it('should expire old requests', async () => {
            const req_obj = service.createRequest('user1', 'user2', 'ws-123', 'Review');
            req_obj.createdAt = Date.now() - 31 * 24 * 60 * 60 * 1000; // 31 days ago
            const response = await request(app)
                .post('/api/reviews/expire-old')
                .send({});
            expect(response.status).toBe(200);
            expect(response.body.success).toBe(true);
        });
    });
    describe('Integration Tests', () => {
        it('should handle complete code review workflow', async () => {
            // Create request
            const createResp = await request(app)
                .post('/api/reviews')
                .send({
                requesterId: 'user1',
                reviewerId: 'user2',
                workspaceId: 'ws-123',
                contextNote: 'Please review',
                priority: 'high',
            });
            const requestId = createResp.body.data.id;
            expect(createResp.status).toBe(201);
            // Get request
            const getResp = await request(app)
                .get(`/api/reviews/${requestId}`);
            expect(getResp.status).toBe(200);
            // Get pending
            const pendingResp = await request(app)
                .get('/api/reviews/reviewer/user2/pending');
            expect(pendingResp.status).toBe(200);
            expect(pendingResp.body.data.length).toBeGreaterThan(0);
            // Respond
            const respondResp = await request(app)
                .post(`/api/reviews/${requestId}/respond`)
                .send({
                reviewerId: 'user2',
                status: 'approved',
                comment: 'Looks good',
            });
            expect(respondResp.status).toBe(200);
            // Check stats
            const statsResp = await request(app)
                .get('/api/reviews/reviewer/user2/stats');
            expect(statsResp.status).toBe(200);
            expect(statsResp.body.data.approvedCount).toBe(1);
        });
    });
});
//# sourceMappingURL=code-review-request.test.js.map