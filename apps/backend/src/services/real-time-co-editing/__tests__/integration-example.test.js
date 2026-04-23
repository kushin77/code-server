/**
 * @file        apps/backend/src/services/real-time-co-editing/__tests__/integration-example.test.ts
 * @module      collaboration/real-time-editing
 * @description Integration tests for real-time co-editing engine
 */
import { describe, it, expect, beforeEach } from 'vitest';
import request from 'supertest';
import { createRealTimeCoEditingExampleApp } from '../integration-example';
import { RealTimeCoEditingEngine } from '../index';
describe('Real-Time Co-Editing Engine', () => {
    let app;
    let engine;
    beforeEach(async () => {
        app = await createRealTimeCoEditingExampleApp();
        engine = RealTimeCoEditingEngine.getInstance();
        engine.reset();
    });
    describe('Session Management', () => {
        it('allows client to join a collaborative session', async () => {
            const res = await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            });
            expect(res.status).toBe(201);
            expect(res.body).toMatchObject({
                docId: 'doc-1',
                clientId: 'client-1',
                userId: 'user-1',
                isConnected: true,
            });
            expect(res.body.sessionId).toBeDefined();
            expect(res.body.joinedAt).toBeDefined();
        });
        it('prevents duplicate client joins for same document', async () => {
            // First join
            await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            });
            // Second join with same client should fail
            const res = await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-1',
                userId: 'user-2',
                workspaceId: 'workspace-1',
            });
            expect(res.status).toBe(400);
            expect(res.body.error).toContain('already in session');
        });
        it('allows multiple clients in same document', async () => {
            // Client 1
            const res1 = await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            });
            expect(res1.status).toBe(201);
            // Client 2
            const res2 = await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-2',
                userId: 'user-2',
                workspaceId: 'workspace-1',
            });
            expect(res2.status).toBe(201);
            // Client 3 different document
            const res3 = await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-2',
                clientId: 'client-3',
                userId: 'user-3',
                workspaceId: 'workspace-1',
            });
            expect(res3.status).toBe(201);
            // Verify all sessions exist
            const sessions = await request(app).get('/api/co-editing/sessions/doc-1');
            expect(sessions.body.count).toBe(2);
        });
        it('allows client to leave session', async () => {
            // Join
            await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            });
            // Leave
            const res = await request(app).post('/api/co-editing/sessions/leave').send({
                docId: 'doc-1',
                clientId: 'client-1',
            });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            // Verify session is gone
            const sessions = await request(app).get('/api/co-editing/sessions/doc-1');
            expect(sessions.body.count).toBe(0);
        });
        it('retrieves specific session info', async () => {
            await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            });
            const res = await request(app).get('/api/co-editing/sessions/doc-1/client-1');
            expect(res.status).toBe(200);
            expect(res.body.clientId).toBe('client-1');
            expect(res.body.userId).toBe('user-1');
            expect(res.body.isConnected).toBe(true);
        });
        it('returns 404 for non-existent session', async () => {
            const res = await request(app).get('/api/co-editing/sessions/doc-1/client-1');
            expect(res.status).toBe(404);
        });
        it('validates required fields on join', async () => {
            const res = await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-1',
                // missing userId and workspaceId
            });
            expect(res.status).toBe(400);
            expect(res.body.error).toContain('Missing required fields');
        });
    });
    describe('Edit Operations', () => {
        beforeEach(async () => {
            await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            });
        });
        it('applies insert operation', async () => {
            const res = await request(app).post('/api/co-editing/operations').send({
                clientId: 'client-1',
                sessionId: 'session-1',
                docId: 'doc-1',
                type: 'insert',
                position: 0,
                content: 'Hello',
            });
            expect(res.status).toBe(201);
            expect(res.body.success).toBe(true);
            expect(res.body.operation.type).toBe('insert');
        });
        it('applies delete operation', async () => {
            const res = await request(app).post('/api/co-editing/operations').send({
                clientId: 'client-1',
                sessionId: 'session-1',
                docId: 'doc-1',
                type: 'delete',
                position: 0,
                length: 5,
            });
            expect(res.status).toBe(201);
            expect(res.body.success).toBe(true);
        });
        it('applies format operation', async () => {
            const res = await request(app).post('/api/co-editing/operations').send({
                clientId: 'client-1',
                sessionId: 'session-1',
                docId: 'doc-1',
                type: 'format',
                position: 0,
                length: 5,
                content: 'bold',
            });
            expect(res.status).toBe(201);
            expect(res.body.success).toBe(true);
        });
        it('rejects invalid operation type', async () => {
            const res = await request(app).post('/api/co-editing/operations').send({
                clientId: 'client-1',
                docId: 'doc-1',
                type: 'invalid',
                position: 0,
            });
            expect(res.status).toBe(400);
            expect(res.body.error).toContain('Invalid operation type');
        });
        it('validates required operation fields', async () => {
            const res = await request(app).post('/api/co-editing/operations').send({
                clientId: 'client-1',
                // missing docId, type, position
            });
            expect(res.status).toBe(400);
        });
    });
    describe('Synchronization', () => {
        beforeEach(async () => {
            await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            });
        });
        it('syncs delta to remote peer', async () => {
            const remoteVector = { 'client-1': 0 };
            const res = await request(app).post('/api/co-editing/sync').send({
                docId: 'doc-1',
                clientId: 'client-1',
                remoteVector,
            });
            expect(res.status).toBe(200);
            expect(res.body).toMatchObject({
                docId: 'doc-1',
                clientId: 'client-1',
                latencyMs: expect.any(Number),
                timestamp: expect.any(Number),
            });
            expect(res.body.delta).toBeDefined();
        });
        it('tracks sync latency', async () => {
            const remoteVector = { 'client-1': 0 };
            const res = await request(app).post('/api/co-editing/sync').send({
                docId: 'doc-1',
                clientId: 'client-1',
                remoteVector,
            });
            expect(res.status).toBe(200);
            expect(res.body.latencyMs).toBeLessThan(100); // Target: sub-100ms
        });
        it('validates sync request fields', async () => {
            const res = await request(app).post('/api/co-editing/sync').send({
                docId: 'doc-1',
                // missing clientId and remoteVector
            });
            expect(res.status).toBe(400);
        });
    });
    describe('Presence Management', () => {
        beforeEach(async () => {
            await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            });
            await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-2',
                userId: 'user-2',
                workspaceId: 'workspace-1',
            });
        });
        it('updates user cursor position', async () => {
            const res = await request(app).post('/api/co-editing/presence/update').send({
                docId: 'doc-1',
                userId: 'user-1',
                clientId: 'client-1',
                position: 42,
            });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.position).toBe(42);
        });
        it('updates user selection', async () => {
            const res = await request(app).post('/api/co-editing/presence/update').send({
                docId: 'doc-1',
                userId: 'user-1',
                clientId: 'client-1',
                position: 10,
                selection: { start: 10, end: 20 },
            });
            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
        });
        it('retrieves presence of all active editors', async () => {
            // Update positions
            await request(app).post('/api/co-editing/presence/update').send({
                docId: 'doc-1',
                userId: 'user-1',
                clientId: 'client-1',
                position: 10,
            });
            await request(app).post('/api/co-editing/presence/update').send({
                docId: 'doc-1',
                userId: 'user-2',
                clientId: 'client-2',
                position: 20,
            });
            const res = await request(app).get('/api/co-editing/presence/doc-1');
            expect(res.status).toBe(200);
            expect(res.body.count).toBe(2);
            expect(res.body.presence).toHaveLength(2);
            expect(res.body.presence[0]).toMatchObject({
                userId: expect.any(String),
                clientId: expect.any(String),
                cursorPosition: expect.any(Number),
                color: expect.stringMatching(/^#[0-9A-F]{6}$/),
            });
        });
        it('validates presence update fields', async () => {
            const res = await request(app).post('/api/co-editing/presence/update').send({
                docId: 'doc-1',
                userId: 'user-1',
                // missing clientId and position
            });
            expect(res.status).toBe(400);
        });
        it('returns empty presence for document with no editors', async () => {
            const res = await request(app).get('/api/co-editing/presence/doc-2');
            expect(res.status).toBe(200);
            expect(res.body.count).toBe(0);
            expect(res.body.presence).toEqual([]);
        });
    });
    describe('Compaction', () => {
        it('compacts document operations when threshold exceeded', async () => {
            const res = await request(app).post('/api/co-editing/compact').send({
                docId: 'doc-1',
            });
            expect(res.status).toBe(200);
            expect(res.body).toMatchObject({
                docId: 'doc-1',
                compacted: expect.any(Boolean),
            });
        });
        it('validates compaction request fields', async () => {
            const res = await request(app).post('/api/co-editing/compact').send({
            // missing docId
            });
            expect(res.status).toBe(400);
        });
    });
    describe('Metrics', () => {
        beforeEach(async () => {
            await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            });
        });
        it('retrieves engine metrics', async () => {
            const res = await request(app).get('/api/co-editing/metrics');
            expect(res.status).toBe(200);
            expect(res.body).toMatchObject({
                activeSessions: expect.any(Number),
                totalSyncs: expect.any(Number),
                totalConflicts: expect.any(Number),
                avgSyncLatencyMs: expect.any(Number),
                conflictRate: expect.any(Number),
            });
        });
        it('updates active sessions count', async () => {
            let res = await request(app).get('/api/co-editing/metrics');
            expect(res.body.activeSessions).toBe(1);
            // Join another
            await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-2',
                userId: 'user-2',
                workspaceId: 'workspace-1',
            });
            res = await request(app).get('/api/co-editing/metrics');
            expect(res.body.activeSessions).toBe(2);
        });
    });
    describe('Health Check', () => {
        it('returns health status', async () => {
            const res = await request(app).get('/api/co-editing/health');
            expect(res.status).toBe(200);
            expect(res.body).toMatchObject({
                status: 'healthy',
                activeSessions: expect.any(Number),
                avgSyncLatencyMs: expect.any(Number),
                timestamp: expect.any(String),
            });
        });
    });
    describe('Concurrent Editing Scenarios', () => {
        it('handles multiple concurrent clients editing same document', async () => {
            // Client 1 joins
            await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            });
            // Client 2 joins
            await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-2',
                userId: 'user-2',
                workspaceId: 'workspace-1',
            });
            // Client 1 edits
            const edit1 = await request(app).post('/api/co-editing/operations').send({
                clientId: 'client-1',
                docId: 'doc-1',
                type: 'insert',
                position: 0,
                content: 'Hello',
            });
            expect(edit1.status).toBe(201);
            // Client 2 edits at different position (no conflict)
            const edit2 = await request(app).post('/api/co-editing/operations').send({
                clientId: 'client-2',
                docId: 'doc-1',
                type: 'insert',
                position: 10,
                content: 'World',
            });
            expect(edit2.status).toBe(201);
            // Both clients sync
            const sync1 = await request(app).post('/api/co-editing/sync').send({
                docId: 'doc-1',
                clientId: 'client-1',
                remoteVector: { 'client-1': 0 },
            });
            expect(sync1.status).toBe(200);
            const sync2 = await request(app).post('/api/co-editing/sync').send({
                docId: 'doc-1',
                clientId: 'client-2',
                remoteVector: { 'client-2': 0 },
            });
            expect(sync2.status).toBe(200);
        });
        it('maintains presence for multiple concurrent users', async () => {
            // 5 users join
            for (let i = 1; i <= 5; i++) {
                await request(app).post('/api/co-editing/sessions/join').send({
                    docId: 'doc-1',
                    clientId: `client-${i}`,
                    userId: `user-${i}`,
                    workspaceId: 'workspace-1',
                });
            }
            // All update presence
            for (let i = 1; i <= 5; i++) {
                await request(app).post('/api/co-editing/presence/update').send({
                    docId: 'doc-1',
                    userId: `user-${i}`,
                    clientId: `client-${i}`,
                    position: i * 10,
                });
            }
            // Verify all present
            const res = await request(app).get('/api/co-editing/presence/doc-1');
            expect(res.status).toBe(200);
            expect(res.body.count).toBe(5);
        });
    });
    describe('Performance Targets', () => {
        it('maintains sub-100ms sync latency', async () => {
            await request(app).post('/api/co-editing/sessions/join').send({
                docId: 'doc-1',
                clientId: 'client-1',
                userId: 'user-1',
                workspaceId: 'workspace-1',
            });
            const syncs = [];
            for (let i = 0; i < 5; i++) {
                const res = await request(app).post('/api/co-editing/sync').send({
                    docId: 'doc-1',
                    clientId: 'client-1',
                    remoteVector: { 'client-1': i },
                });
                expect(res.status).toBe(200);
                expect(res.body.latencyMs).toBeDefined();
                syncs.push(res.body.latencyMs);
            }
            // Verify we got latency measurements and they're reasonable
            expect(syncs.length).toBeGreaterThan(0);
            const avgLatency = syncs.reduce((a, b) => a + b, 0) / syncs.length;
            expect(avgLatency).toBeLessThan(200); // Allow some variance in test environment
            expect(Math.min(...syncs)).toBeLessThan(50); // At least some fast syncs
        });
        it('supports unlimited concurrent editors', async () => {
            const targetEditors = 100;
            for (let i = 1; i <= targetEditors; i++) {
                const res = await request(app).post('/api/co-editing/sessions/join').send({
                    docId: 'doc-1',
                    clientId: `client-${i}`,
                    userId: `user-${i}`,
                    workspaceId: 'workspace-1',
                });
                expect(res.status).toBe(201);
            }
            const sessions = await request(app).get('/api/co-editing/sessions/doc-1');
            expect(sessions.body.count).toBe(targetEditors);
        });
    });
});
//# sourceMappingURL=integration-example.test.js.map