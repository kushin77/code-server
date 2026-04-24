/**
 * @file        apps/backend/src/services/session-cost-tracking/integration-example.ts
 * @module      collaboration/sessions
 * @description REST API surface for session cost tracking service
 */
import { Router } from 'express';
import express from 'express';
import { SessionCostTrackingService } from './index';
export function initializeSessionCostTrackingRoutes(service = SessionCostTrackingService.getInstance()) {
    const router = Router();
    /**
     * POST /api/session-cost/start
     * Start tracking a new session
     */
    router.post('/start', (req, res) => {
        const { sessionId, userId, projectId, teamId, metadata } = req.body;
        if (!sessionId || !userId || !projectId || !teamId) {
            return res.status(400).json({ error: 'Missing required fields: sessionId, userId, projectId, teamId' });
        }
        try {
            const session = service.startSession(sessionId, userId, projectId, teamId, metadata);
            res.status(201).json(session);
        }
        catch (err) {
            res.status(400).json({ error: err.message });
        }
    });
    /**
     * POST /api/session-cost/:sessionId/end
     * End tracking a session
     */
    router.post('/:sessionId/end', (req, res) => {
        const { sessionId } = req.params;
        try {
            const session = service.endSession(sessionId);
            res.json(session);
        }
        catch (err) {
            res.status(404).json({ error: err.message });
        }
    });
    /**
     * GET /api/session-cost/:sessionId
     * Get session cost details
     */
    router.get('/:sessionId', (req, res) => {
        const { sessionId } = req.params;
        const session = service.getSessionCost(sessionId);
        if (!session) {
            return res.status(404).json({ error: `Session ${sessionId} not found` });
        }
        res.json(session);
    });
    /**
     * POST /api/session-cost/:sessionId/add-component
     * Add a cost component to active session
     */
    router.post('/:sessionId/add-component', (req, res) => {
        const { sessionId } = req.params;
        const { type, unit, unitPrice, quantity } = req.body;
        if (!type || !unit || unitPrice === undefined || quantity === undefined) {
            return res.status(400).json({ error: 'Missing required fields: type, unit, unitPrice, quantity' });
        }
        try {
            const session = service.addCostComponent(sessionId, { type, unit, unitPrice, quantity });
            res.json(session);
        }
        catch (err) {
            res.status(400).json({ error: err.message });
        }
    });
    /**
     * GET /api/session-cost/user/:userId/summary
     * Get user cost summary
     */
    router.get('/user/:userId/summary', (req, res) => {
        const { userId } = req.params;
        const { startDate, endDate, period } = req.query;
        if (!startDate || !endDate) {
            return res.status(400).json({ error: 'Missing required query params: startDate, endDate' });
        }
        try {
            const summary = service.getUserCostSummary(userId, new Date(startDate), new Date(endDate), period || 'monthly');
            res.json(summary);
        }
        catch (err) {
            res.status(400).json({ error: err.message });
        }
    });
    /**
     * GET /api/session-cost/project/:projectId/summary
     * Get project cost summary
     */
    router.get('/project/:projectId/summary', (req, res) => {
        const { projectId } = req.params;
        const { startDate, endDate, period } = req.query;
        if (!startDate || !endDate) {
            return res.status(400).json({ error: 'Missing required query params: startDate, endDate' });
        }
        try {
            const summary = service.getProjectCostSummary(projectId, new Date(startDate), new Date(endDate), period || 'monthly');
            res.json(summary);
        }
        catch (err) {
            res.status(400).json({ error: err.message });
        }
    });
    /**
     * GET /api/session-cost/user/:userId/sessions
     * Get all sessions for a user
     */
    router.get('/user/:userId/sessions', (req, res) => {
        const { userId } = req.params;
        try {
            const sessions = service.getUserSessions(userId);
            res.json({ sessions });
        }
        catch (err) {
            res.status(400).json({ error: err.message });
        }
    });
    /**
     * GET /api/session-cost/project/:projectId/sessions
     * Get all sessions for a project
     */
    router.get('/project/:projectId/sessions', (req, res) => {
        const { projectId } = req.params;
        try {
            const sessions = service.getProjectSessions(projectId);
            res.json({ sessions });
        }
        catch (err) {
            res.status(400).json({ error: err.message });
        }
    });
    /**
     * GET /api/session-cost/user/:userId/forecast
     * Get cost forecast for user
     */
    router.get('/user/:userId/forecast', (req, res) => {
        const { userId } = req.params;
        const { days } = req.query;
        try {
            const forecast = service.forecastUserCost(userId, days ? parseInt(days) : 30);
            res.json({ forecast, forecastDays: days || 30 });
        }
        catch (err) {
            res.status(400).json({ error: err.message });
        }
    });
    /**
     * GET /api/session-cost/project/:projectId/forecast
     * Get cost forecast for project
     */
    router.get('/project/:projectId/forecast', (req, res) => {
        const { projectId } = req.params;
        const { days } = req.query;
        try {
            const forecast = service.forecastProjectCost(projectId, days ? parseInt(days) : 30);
            res.json({ forecast, forecastDays: days || 30 });
        }
        catch (err) {
            res.status(400).json({ error: err.message });
        }
    });
    /**
     * GET /api/session-cost/active-sessions/count
     * Get count of active sessions
     */
    router.get('/active-sessions/count', (req, res) => {
        const count = service.getActiveSessionsCount();
        res.json({ activeSessionsCount: count });
    });
    /**
     * POST /api/session-cost/archive-old
     * Archive old sessions
     */
    router.post('/archive-old', (req, res) => {
        const { olderThanDays } = req.body;
        if (olderThanDays === undefined) {
            return res.status(400).json({ error: 'Missing required field: olderThanDays' });
        }
        try {
            const count = service.archiveOldSessions(olderThanDays);
            res.json({ archivedCount: count });
        }
        catch (err) {
            res.status(400).json({ error: err.message });
        }
    });
    /**
     * PUT /api/session-cost/pricing
     * Update pricing configuration
     */
    router.put('/pricing', (req, res) => {
        try {
            service.updatePricing(req.body);
            res.json({ message: 'Pricing updated successfully' });
        }
        catch (err) {
            res.status(400).json({ error: err.message });
        }
    });
    return router;
}
export function setupSessionCostTrackingIntegration(app, service = SessionCostTrackingService.getInstance()) {
    const router = initializeSessionCostTrackingRoutes(service);
    app.use('/api/session-cost', router);
}
export async function createSessionCostTrackingExampleApp() {
    const app = express();
    app.use(express.json());
    const service = SessionCostTrackingService.getInstance();
    setupSessionCostTrackingIntegration(app, service);
    return app;
}
export { SessionCostTrackingService };
//# sourceMappingURL=integration-example.js.map