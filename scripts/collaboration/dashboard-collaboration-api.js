#!/usr/bin/env node
/**
 * @file        scripts/collaboration/dashboard-collaboration-api.js
 * @module      collaboration/dashboard
 * @description REST API for collaborative dashboards
 */

const express = require('express');
const DashboardCollaborationService = require('./dashboard-collaboration-service');

const app = express();
const PORT = process.env.PORT || 9104;

// Initialize service
const collaborationService = new DashboardCollaborationService({
    serviceName: process.env.SERVICE_NAME || 'code-server',
});

// Event listeners
collaborationService.on('dashboard-created', (context) => {
    console.log(`[Dashboard] Created: ${context.dashboardId} - ${context.name}`);
});

collaborationService.on('dashboard-updated', (context) => {
    console.log(`[Dashboard] Updated: ${context.dashboardId} - v${context.version} by ${context.updatedBy}`);
});

collaborationService.on('collaboration-session-started', (context) => {
    console.log(`[Collaboration] Session started: ${context.sessionId} - Dashboard ${context.dashboardId}`);
});

collaborationService.on('collaborator-added', (context) => {
    console.log(`[Collaboration] Added ${context.userId} as ${context.role} to ${context.dashboardId}`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'dashboard-collaboration' });
});

// Create dashboard
app.post('/dashboards', (req, res) => {
    try {
        const dashboardId = collaborationService.createDashboard({
            ...req.body,
            userId: req.body.userId || 'user-system',
        });
        
        const dashboard = collaborationService.getDashboard(dashboardId);
        
        res.status(201).json({
            status: 'created',
            dashboardId,
            name: dashboard.name,
            createdAt: dashboard.createdAt,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Update dashboard (creates new version)
app.put('/dashboards/:dashboardId', (req, res) => {
    try {
        const updateToken = req.headers['x-update-token'] || 
            `update-${req.params.dashboardId}-${Date.now()}`;
        
        collaborationService.updateDashboard(
            req.params.dashboardId,
            { ...req.body, userId: req.body.userId || 'user-system' },
            updateToken
        );
        
        const dashboard = collaborationService.getDashboard(req.params.dashboardId);
        
        res.json({
            status: 'updated',
            dashboardId: req.params.dashboardId,
            version: dashboard.version,
            lastModifiedAt: dashboard.lastModifiedAt,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Save dashboard version
app.post('/dashboards/:dashboardId/versions', (req, res) => {
    try {
        const saveToken = req.headers['x-save-token'] || 
            `save-${req.params.dashboardId}-${Date.now()}`;
        
        const versionId = collaborationService.saveDashboardVersion(
            req.params.dashboardId,
            { ...req.body, userId: req.body.userId || 'user-system' },
            saveToken
        );
        
        res.status(201).json({
            status: 'saved',
            versionId,
            dashboardId: req.params.dashboardId,
            version: req.body.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get dashboard
app.get('/dashboards/:dashboardId', (req, res) => {
    try {
        const dashboard = collaborationService.getDashboard(req.params.dashboardId);
        
        if (!dashboard) {
            return res.status(404).json({ error: 'Dashboard not found' });
        }
        
        res.json({
            dashboardId: dashboard.dashboardId,
            name: dashboard.name,
            description: dashboard.description,
            version: dashboard.version,
            createdBy: dashboard.createdBy,
            createdAt: dashboard.createdAt,
            lastModifiedBy: dashboard.lastModifiedBy,
            lastModifiedAt: dashboard.lastModifiedAt,
            collaborators: dashboard.collaborators.map(c => ({
                userId: c.userId,
                role: c.role,
                joinedAt: c.joinedAt,
            })),
            widgets: dashboard.widgets,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get dashboard version history
app.get('/dashboards/:dashboardId/versions', (req, res) => {
    try {
        const history = collaborationService.getDashboardVersionHistory(req.params.dashboardId);
        
        res.json({
            dashboardId: req.params.dashboardId,
            totalVersions: history.length,
            versions: history.map(v => ({
                version: v.version,
                action: v.changeLog[v.changeLog.length - 1]?.action,
                by: v.changeLog[v.changeLog.length - 1]?.by,
                at: v.changeLog[v.changeLog.length - 1]?.at,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Query dashboards
app.get('/dashboards', (req, res) => {
    try {
        const filters = {
            workspaceId: req.query.workspaceId,
            userId: req.query.userId,
            status: req.query.status,
            limit: req.query.limit ? parseInt(req.query.limit) : 100,
        };
        
        const dashboards = collaborationService.queryDashboards(filters);
        
        res.json({
            total: dashboards.length,
            filters,
            dashboards: dashboards.map(d => ({
                dashboardId: d.dashboardId,
                name: d.name,
                version: d.version,
                createdBy: d.createdBy,
                createdAt: d.createdAt,
                lastModifiedAt: d.lastModifiedAt,
                collaboratorCount: d.collaborators.length,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Add collaborator
app.post('/dashboards/:dashboardId/collaborators', (req, res) => {
    try {
        collaborationService.addCollaborator(req.params.dashboardId, {
            ...req.body,
            addedBy: req.body.addedBy || 'user-system',
        });
        
        const dashboard = collaborationService.getDashboard(req.params.dashboardId);
        
        res.status(201).json({
            status: 'collaborator_added',
            dashboardId: req.params.dashboardId,
            userId: req.body.userId,
            role: req.body.role || 'viewer',
            version: dashboard.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Start collaboration session
app.post('/sessions', (req, res) => {
    try {
        const sessionId = collaborationService.startCollaborationSession({
            ...req.body,
            workspaceId: req.body.workspaceId || 'ws-default',
        });
        
        const session = collaborationService.getCollaborationSession(sessionId);
        
        res.status(201).json({
            status: 'session_started',
            sessionId,
            dashboardId: session.dashboardId,
            host: session.host,
            startedAt: session.startedAt,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get collaboration session
app.get('/sessions/:sessionId', (req, res) => {
    try {
        const session = collaborationService.getCollaborationSession(req.params.sessionId);
        
        if (!session) {
            return res.status(404).json({ error: 'Session not found' });
        }
        
        res.json({
            sessionId: session.sessionId,
            dashboardId: session.dashboardId,
            host: session.host,
            participants: session.participants,
            status: session.status,
            startedAt: session.startedAt,
            features: session.features,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Update cursor position
app.post('/sessions/:sessionId/cursors', (req, res) => {
    try {
        collaborationService.updateCursorPosition(req.body.userId, {
            x: req.body.x,
            y: req.body.y,
            color: req.body.color,
        });
        
        res.json({
            status: 'cursor_updated',
            userId: req.body.userId,
            x: req.body.x,
            y: req.body.y,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get collaboration statistics
app.get('/statistics', (req, res) => {
    try {
        const stats = collaborationService.getCollaborationStatistics();
        
        res.json({
            totalDashboards: stats.totalDashboards,
            activeSessions: stats.activeSessions,
            totalParticipants: stats.totalParticipants,
            averageCollaborators: stats.averageCollaborators.toFixed(2),
            totalVersions: stats.totalVersions,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[Dashboard Collaboration API] Listening on port ${PORT}`);
    console.log(`[Dashboard Collaboration API] POST /dashboards - Create dashboard`);
    console.log(`[Dashboard Collaboration API] PUT /dashboards/:id - Update dashboard`);
    console.log(`[Dashboard Collaboration API] POST /dashboards/:id/versions - Save version`);
    console.log(`[Dashboard Collaboration API] GET /dashboards/:id - Get dashboard`);
    console.log(`[Dashboard Collaboration API] GET /dashboards/:id/versions - Get history`);
    console.log(`[Dashboard Collaboration API] GET /dashboards - Query dashboards`);
    console.log(`[Dashboard Collaboration API] POST /dashboards/:id/collaborators - Add collaborator`);
    console.log(`[Dashboard Collaboration API] POST /sessions - Start session`);
    console.log(`[Dashboard Collaboration API] GET /sessions/:id - Get session`);
    console.log(`[Dashboard Collaboration API] POST /sessions/:id/cursors - Update cursor`);
    console.log(`[Dashboard Collaboration API] GET /statistics - Get statistics`);
});
