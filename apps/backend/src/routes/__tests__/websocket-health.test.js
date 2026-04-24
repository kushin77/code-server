#!/usr/bin/env node
// @file        apps/backend/src/routes/__tests__/websocket-health.test.ts
// @module      routes
// @description Tests for WebSocket health monitoring routes
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import request from 'supertest';
import express from 'express';
import service from '../../services/monitoring/websocket-health-service';
import router from '../websocket-health';
let app;
describe('WebSocket Health Routes', () => {
    beforeEach(() => {
        service.reset();
        app = express();
        // Custom JSON error handler for parsing errors
        app.use(express.json((err, req, res, next) => {
            if (err instanceof SyntaxError && 'body' in err) {
                return res.status(400).json({
                    success: false,
                    error: 'Invalid JSON in request body',
                });
            }
            next(err);
        }));
        app.use(express.json());
        // Debug: check if router is loaded
        if (!router) {
            throw new Error('Router is not defined');
        }
        app.use('/api/websocket-health', router);
        // Global error handler for JSON responses
        app.use((err, req, res, next) => {
            if (err instanceof SyntaxError) {
                return res.status(400).json({
                    success: false,
                    error: 'Invalid request',
                });
            }
            res.status(500).json({
                success: false,
                error: err.message || 'Internal server error',
            });
        });
    });
    afterEach(() => {
        service.removeAllListeners();
    });
    describe('POST /register', () => {
        it('should register a new connection', async () => {
            const res = await request(app)
                .post('/api/websocket-health/register')
                .send({
                connectionId: 'conn1',
                type: 'collaboration',
                userId: 'user1',
                workspaceId: 'ws1',
            });
            expect(res.status).toBe(201);
            expect(res.body.success).toBe(true);
            expect(res.body.data?.connectionId).toBe('conn1');
            expect(res.body.data?.type).toBe('collaboration');
            expect(res.body.data?.qualityScore).toBe(100);
        });
        it('should validate required fields', async () => {
            const res = await request(app)
                .post('/api/websocket-health/register')
                .send({
                connectionId: 'conn1',
                // Missing type, userId, workspaceId
            });
            expect(res.status).toBe(400);
            expect(res.body.success).toBe(false);
            expect(res.body.error).toContain('Missing required fields');
        });
        it('should validate connection type', async () => {
            const res = await request(app)
                .post('/api/websocket-health/register')
                .send({
                connectionId: 'conn1',
                type: 'invalid-type',
                userId: 'user1',
                workspaceId: 'ws1',
            });
            expect(res.status).toBe(400);
            expect(res.body.success).toBe(false);
            expect(res.body.error).toContain('Invalid connection type');
        });
    });
    // Retrieval Tests
    describe('GET /connections/:id', () => {
        beforeEach(async () => {
            service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
        });
        it('should get connection by ID', async () => {
            const res = await request(app)
                .get('/api/websocket-health/connections/conn1');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.connectionId).toBe('conn1');
            expect(res.body.data.type).toBe('collaboration');
        });
        it('should return 404 for nonexistent connection', async () => {
            const res = await request(app)
                .get('/api/websocket-health/connections/nonexistent');
            expect(res.status).toBe(404);
            expect(res.body.success).toBe(false);
            expect(res.body.error).toContain('not found');
        });
    });
    // User Connections Tests
    describe('GET /user/:userId/connections', () => {
        beforeEach(() => {
            service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
            service.registerConnection('conn2', 'presence', 'user1', 'ws1');
            service.registerConnection('conn3', 'collaboration', 'user2', 'ws1');
        });
        it('should get all connections for a user', async () => {
            const res = await request(app)
                .get('/api/websocket-health/user/user1/connections');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data).toHaveLength(2);
            expect(res.body.data.map((c) => c.connectionId)).toContain('conn1');
            expect(res.body.data.map((c) => c.connectionId)).toContain('conn2');
        });
        it('should return empty array for user with no connections', async () => {
            const res = await request(app)
                .get('/api/websocket-health/user/nonexistent-user/connections');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data).toHaveLength(0);
        });
    });
    // Connection Type Tests
    describe('GET /type/:type', () => {
        beforeEach(() => {
            service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
            service.registerConnection('conn2', 'presence', 'user1', 'ws1');
            service.registerConnection('conn3', 'collaboration', 'user2', 'ws1');
        });
        it('should get connections by type', async () => {
            const res = await request(app)
                .get('/api/websocket-health/type/collaboration');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data).toHaveLength(2);
            expect(res.body.data.every((c) => c.type === 'collaboration')).toBe(true);
        });
        it('should validate connection type', async () => {
            const res = await request(app)
                .get('/api/websocket-health/type/invalid-type');
            expect(res.status).toBe(400);
            expect(res.body.success).toBe(false);
            expect(res.body.error).toContain('Invalid connection type');
        });
    });
    // Degraded Connections Tests
    describe('GET /degraded', () => {
        beforeEach(() => {
            service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
            service.registerConnection('conn2', 'presence', 'user1', 'ws1');
            service.registerConnection('conn3', 'collaboration', 'user2', 'ws2');
        });
        it('should get degraded connections', async () => {
            service.recordPacketLoss('conn1', 80); // Degrade conn1
            const res = await request(app)
                .get('/api/websocket-health/degraded');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.length).toBeGreaterThanOrEqual(1);
            expect(res.body.data.map((c) => c.connectionId)).toContain('conn1');
        });
        it('should filter degraded connections by workspace', async () => {
            service.recordPacketLoss('conn1', 80);
            service.recordPacketLoss('conn3', 80);
            const res = await request(app)
                .get('/api/websocket-health/degraded?workspaceId=ws1');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            // Should only include degraded connections from ws1
            expect(res.body.data.every((c) => c.workspaceId === 'ws1')).toBe(true);
        });
    });
    // Workspace Stats Tests
    describe('GET /workspace/:workspaceId/stats', () => {
        beforeEach(() => {
            service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
            service.registerConnection('conn2', 'presence', 'user1', 'ws1');
            service.registerConnection('conn3', 'collaboration', 'user2', 'ws2');
        });
        it('should get workspace statistics', async () => {
            const res = await request(app)
                .get('/api/websocket-health/workspace/ws1/stats');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.totalConnections).toBe(2);
            expect(res.body.data.connectedCount).toBe(2);
            expect(res.body.data.connectionsByType).toBeDefined();
            expect(res.body.data.averageQuality).toBeGreaterThanOrEqual(0);
        });
    });
    // System Health Tests
    describe('GET /system/health', () => {
        beforeEach(() => {
            service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
            service.registerConnection('conn2', 'presence', 'user2', 'ws1');
        });
        it('should get system health summary', async () => {
            const res = await request(app)
                .get('/api/websocket-health/system/health');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.totalConnections).toBe(2);
            expect(res.body.data.activeConnections).toBe(2);
            expect(res.body.data.systemQuality).toBeGreaterThanOrEqual(0);
            expect(res.body.data.systemQuality).toBeLessThanOrEqual(100);
        });
    });
    // Ping/Pong Tests
    describe('PATCH /connections/:id/ping', () => {
        beforeEach(() => {
            service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
        });
        it('should record ping sent', async () => {
            const res = await request(app)
                .patch('/api/websocket-health/connections/conn1/ping');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.lastPingTime).toBeGreaterThan(0);
        });
        it('should return 404 for nonexistent connection', async () => {
            const res = await request(app)
                .patch('/api/websocket-health/connections/nonexistent/ping');
            expect(res.status).toBe(404);
            expect(res.body.success).toBe(false);
        });
    });
    describe('PATCH /connections/:id/pong', () => {
        beforeEach(() => {
            service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
            service.recordPingSent('conn1');
        });
        it('should record pong received', async () => {
            const res = await request(app)
                .patch('/api/websocket-health/connections/conn1/pong');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.latency).toBeGreaterThanOrEqual(0);
        });
        it('should return 404 for nonexistent connection', async () => {
            const res = await request(app)
                .patch('/api/websocket-health/connections/nonexistent/pong');
            expect(res.status).toBe(404);
            expect(res.body.success).toBe(false);
        });
    });
    // Packet Loss Tests
    describe('PATCH /connections/:id/packet-loss', () => {
        beforeEach(() => {
            service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
        });
        it('should record packet loss', async () => {
            const res = await request(app)
                .patch('/api/websocket-health/connections/conn1/packet-loss')
                .send({ lossPercentage: 10 });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.packetLoss).toBe(10);
        });
        it('should validate lossPercentage is a number', async () => {
            const res = await request(app)
                .patch('/api/websocket-health/connections/conn1/packet-loss')
                .send({ lossPercentage: 'invalid' });
            expect(res.status).toBe(400);
            expect(res.body.success).toBe(false);
            expect(res.body.error).toContain('must be a number');
        });
        it('should return 404 for nonexistent connection', async () => {
            const res = await request(app)
                .patch('/api/websocket-health/connections/nonexistent/packet-loss')
                .send({ lossPercentage: 10 });
            expect(res.status).toBe(404);
            expect(res.body.success).toBe(false);
        });
    });
    // Disconnection Tests
    describe('POST /connections/:id/disconnect', () => {
        beforeEach(() => {
            service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
        });
        it('should mark connection as disconnected', async () => {
            const res = await request(app)
                .post('/api/websocket-health/connections/conn1/disconnect');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.connected).toBe(false);
        });
        it('should return 404 for nonexistent connection', async () => {
            const res = await request(app)
                .post('/api/websocket-health/connections/nonexistent/disconnect');
            expect(res.status).toBe(404);
            expect(res.body.success).toBe(false);
        });
    });
    // Reconnection Tests
    describe('POST /connections/:id/reconnect', () => {
        beforeEach(() => {
            service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
            service.markDisconnected('conn1');
        });
        it('should attempt reconnection', async () => {
            const res = await request(app)
                .post('/api/websocket-health/connections/conn1/reconnect');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.reconnectAttempts).toBe(1);
        });
        it('should return 404 for nonexistent connection', async () => {
            const res = await request(app)
                .post('/api/websocket-health/connections/nonexistent/reconnect');
            expect(res.status).toBe(404);
            expect(res.body.success).toBe(false);
        });
    });
    describe('POST /connections/:id/reconnect-success', () => {
        beforeEach(() => {
            service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
            service.markDisconnected('conn1');
            service.attemptReconnection('conn1');
        });
        it('should mark reconnection as successful', async () => {
            const res = await request(app)
                .post('/api/websocket-health/connections/conn1/reconnect-success');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.connected).toBe(true);
            expect(res.body.data.reconnectAttempts).toBe(0);
        });
        it('should return 404 for nonexistent connection', async () => {
            const res = await request(app)
                .post('/api/websocket-health/connections/nonexistent/reconnect-success');
            expect(res.status).toBe(404);
            expect(res.body.success).toBe(false);
        });
    });
    // Cleanup Tests
    describe('DELETE /connections/:id', () => {
        beforeEach(() => {
            service.registerConnection('conn1', 'collaboration', 'user1', 'ws1');
        });
        it('should unregister connection', async () => {
            const res = await request(app)
                .delete('/api/websocket-health/connections/conn1');
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.data.connectionId).toBe('conn1');
            // Verify connection is gone
            const getRes = await request(app)
                .get('/api/websocket-health/connections/conn1');
            expect(getRes.status).toBe(404);
        });
        it('should return 404 for nonexistent connection', async () => {
            const res = await request(app)
                .delete('/api/websocket-health/connections/nonexistent');
            expect(res.status).toBe(404);
            expect(res.body.success).toBe(false);
        });
    });
    // Integration Tests
    describe('Integration Tests', () => {
        it('should handle complete connection lifecycle', async () => {
            // Register
            let res = await request(app)
                .post('/api/websocket-health/register')
                .send({
                connectionId: 'conn-lifecycle',
                type: 'collaboration',
                userId: 'user-lifecycle',
                workspaceId: 'ws-lifecycle',
            });
            expect(res.status).toBe(201);
            // Record ping/pong
            res = await request(app)
                .patch('/api/websocket-health/connections/conn-lifecycle/ping');
            expect(res.status).toBe(200);
            res = await request(app)
                .patch('/api/websocket-health/connections/conn-lifecycle/pong');
            expect(res.status).toBe(200);
            expect(res.body.data.latency).toBeGreaterThanOrEqual(0);
            // Record packet loss
            res = await request(app)
                .patch('/api/websocket-health/connections/conn-lifecycle/packet-loss')
                .send({ lossPercentage: 5 });
            expect(res.status).toBe(200);
            // Check stats
            res = await request(app)
                .get('/api/websocket-health/workspace/ws-lifecycle/stats');
            expect(res.status).toBe(200);
            expect(res.body.data.totalConnections).toBe(1);
            // Disconnect
            res = await request(app)
                .post('/api/websocket-health/connections/conn-lifecycle/disconnect');
            expect(res.status).toBe(200);
            expect(res.body.data.connected).toBe(false);
            // Reconnect
            res = await request(app)
                .post('/api/websocket-health/connections/conn-lifecycle/reconnect');
            expect(res.status).toBe(200);
            // Cleanup
            res = await request(app)
                .delete('/api/websocket-health/connections/conn-lifecycle');
            expect(res.status).toBe(200);
        });
        it('should handle multiple connections', async () => {
            // Register multiple connections
            for (let i = 1; i <= 5; i++) {
                const res = await request(app)
                    .post('/api/websocket-health/register')
                    .send({
                    connectionId: `conn${i}`,
                    type: i % 2 === 0 ? 'presence' : 'collaboration',
                    userId: `user${Math.ceil(i / 2)}`,
                    workspaceId: 'ws-multi',
                });
                expect(res.status).toBe(201);
            }
            // Get user connections
            const res = await request(app)
                .get('/api/websocket-health/user/user1/connections');
            expect(res.status).toBe(200);
            expect(res.body.data.length).toBeGreaterThanOrEqual(1);
        });
    });
    // Error Handling Tests
    describe('Error Handling', () => {
        it('should handle missing JSON body gracefully', async () => {
            const res = await request(app)
                .post('/api/websocket-health/register');
            // Express will return 400 for missing JSON
            expect([400, 415]).toContain(res.status);
        });
        it('should return JSON error responses', async () => {
            const res = await request(app)
                .get('/api/websocket-health/connections/nonexistent');
            expect(res.headers['content-type']).toMatch(/json/);
            expect(res.body).toHaveProperty('success');
            expect(res.body).toHaveProperty('error');
        });
    });
});
//# sourceMappingURL=websocket-health.test.js.map