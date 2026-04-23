/**
 * @file        apps/backend/src/services/real-time-co-editing/integration-example.ts
 * @module      collaboration/real-time-editing
 * @description Express integration for real-time co-editing API
 */
import express from 'express';
import { RealTimeCoEditingEngine } from './index';
export async function createRealTimeCoEditingExampleApp() {
    const app = express();
    app.use(express.json());
    const engine = RealTimeCoEditingEngine.getInstance();
    // ============================================================================
    // Session Management
    // ============================================================================
    /**
     * POST /api/co-editing/sessions/join
     * Join or create collaborative editing session
     */
    app.post('/api/co-editing/sessions/join', (req, res) => {
        try {
            const { docId, clientId, userId, workspaceId, initialStateVector } = req.body;
            if (!docId || !clientId || !userId || !workspaceId) {
                return res.status(400).json({ error: 'Missing required fields: docId, clientId, userId, workspaceId' });
            }
            const session = engine.joinSession(docId, clientId, userId, workspaceId, initialStateVector);
            res.status(201).json(session);
        }
        catch (error) {
            res.status(400).json({ error: error.message });
        }
    });
    /**
     * POST /api/co-editing/sessions/leave
     * Leave collaborative editing session
     */
    app.post('/api/co-editing/sessions/leave', (req, res) => {
        try {
            const { docId, clientId } = req.body;
            if (!docId || !clientId) {
                return res.status(400).json({ error: 'Missing required fields: docId, clientId' });
            }
            engine.leaveSession(docId, clientId);
            res.json({ success: true, docId, clientId });
        }
        catch (error) {
            res.status(400).json({ error: error.message });
        }
    });
    /**
     * GET /api/co-editing/sessions/:docId/:clientId
     * Get session information
     */
    app.get('/api/co-editing/sessions/:docId/:clientId', (req, res) => {
        try {
            const { docId, clientId } = req.params;
            const session = engine.getSession(docId, clientId);
            if (!session) {
                return res.status(404).json({ error: 'Session not found' });
            }
            res.json(session);
        }
        catch (error) {
            res.status(400).json({ error: error.message });
        }
    });
    /**
     * GET /api/co-editing/sessions/:docId
     * Get all sessions for a document
     */
    app.get('/api/co-editing/sessions/:docId', (req, res) => {
        try {
            const { docId } = req.params;
            const sessions = engine.getSessions(docId);
            res.json({ docId, sessions, count: sessions.length });
        }
        catch (error) {
            res.status(400).json({ error: error.message });
        }
    });
    // ============================================================================
    // Operations
    // ============================================================================
    /**
     * POST /api/co-editing/operations
     * Apply an edit operation
     */
    app.post('/api/co-editing/operations', (req, res) => {
        try {
            const { clientId, sessionId, docId, type, position, length, content } = req.body;
            if (!clientId || !docId || !type || position === undefined) {
                return res.status(400).json({ error: 'Missing required fields' });
            }
            if (!['insert', 'delete', 'format'].includes(type)) {
                return res.status(400).json({ error: 'Invalid operation type' });
            }
            const result = engine.applyOperation({
                clientId,
                sessionId,
                docId,
                type,
                position,
                length,
                content,
                timestamp: Date.now(),
            });
            if (result.conflict) {
                return res.status(409).json({
                    error: 'Conflict detected',
                    conflict: result.conflict,
                });
            }
            res.status(201).json({ success: true, operation: { clientId, docId, type, position } });
        }
        catch (error) {
            res.status(400).json({ error: error.message });
        }
    });
    // ============================================================================
    // Synchronization
    // ============================================================================
    /**
     * POST /api/co-editing/sync
     * Synchronize with remote peer
     */
    app.post('/api/co-editing/sync', (req, res) => {
        try {
            const { docId, clientId, remoteVector } = req.body;
            if (!docId || !clientId || !remoteVector) {
                return res.status(400).json({ error: 'Missing required fields: docId, clientId, remoteVector' });
            }
            const syncEvent = engine.sync(docId, clientId, remoteVector);
            res.json(syncEvent);
        }
        catch (error) {
            res.status(400).json({ error: error.message });
        }
    });
    // ============================================================================
    // Presence
    // ============================================================================
    /**
     * POST /api/co-editing/presence/update
     * Update user's cursor position and selection
     */
    app.post('/api/co-editing/presence/update', (req, res) => {
        try {
            const { docId, userId, clientId, position, selection } = req.body;
            if (!docId || !userId || !clientId || position === undefined) {
                return res.status(400).json({ error: 'Missing required fields' });
            }
            engine.updatePresence(docId, userId, clientId, position, selection);
            res.json({ success: true, userId, position });
        }
        catch (error) {
            res.status(400).json({ error: error.message });
        }
    });
    /**
     * GET /api/co-editing/presence/:docId
     * Get presence of all active editors for a document
     */
    app.get('/api/co-editing/presence/:docId', (req, res) => {
        try {
            const { docId } = req.params;
            const presence = engine.getPresence(docId);
            res.json({ docId, presence, count: presence.length });
        }
        catch (error) {
            res.status(400).json({ error: error.message });
        }
    });
    // ============================================================================
    // Compaction
    // ============================================================================
    /**
     * POST /api/co-editing/compact
     * Compact document operations if threshold exceeded
     */
    app.post('/api/co-editing/compact', (req, res) => {
        try {
            const { docId } = req.body;
            if (!docId) {
                return res.status(400).json({ error: 'Missing required field: docId' });
            }
            const compacted = engine.compactIfNeeded(docId);
            res.json({ docId, compacted });
        }
        catch (error) {
            res.status(400).json({ error: error.message });
        }
    });
    // ============================================================================
    // Metrics
    // ============================================================================
    /**
     * GET /api/co-editing/metrics
     * Get engine metrics and statistics
     */
    app.get('/api/co-editing/metrics', (req, res) => {
        try {
            const metrics = engine.getMetrics();
            res.json(metrics);
        }
        catch (error) {
            res.status(400).json({ error: error.message });
        }
    });
    // ============================================================================
    // Health
    // ============================================================================
    /**
     * GET /api/co-editing/health
     * Health check endpoint
     */
    app.get('/api/co-editing/health', (req, res) => {
        try {
            const metrics = engine.getMetrics();
            res.json({
                status: 'healthy',
                activeSessions: metrics.activeSessions,
                avgSyncLatencyMs: metrics.avgSyncLatencyMs,
                timestamp: new Date(),
            });
        }
        catch (error) {
            res.status(500).json({ status: 'unhealthy', error: error.message });
        }
    });
    return app;
}
export default createRealTimeCoEditingExampleApp;
//# sourceMappingURL=integration-example.js.map