#!/usr/bin/env node
/**
 * @file        scripts/integrations/grafana-immutable-api.js
 * @module      integrations/grafana
 * @description REST API for Grafana dashboard integration
 */

const express = require('express');
const GrafanaIntegrationService = require('./grafana-immutable-service');

const app = express();
const PORT = process.env.PORT || 9111;

// Initialize service
const grafanaService = new GrafanaIntegrationService({
    apiKey: process.env.GRAFANA_API_KEY,
    baseUrl: process.env.GRAFANA_URL,
});

// Event listeners
grafanaService.on('dashboard-created', (context) => {
    console.log(`[Grafana] Dashboard: ${context.title} (${context.panelCount} panels)`);
});

grafanaService.on('panel-created', (context) => {
    console.log(`[Grafana] Panel: ${context.title} (${context.type})`);
});

grafanaService.on('dashboard-syncing', (context) => {
    console.log(`[Grafana] Syncing: ${context.syncId} → ${context.title}`);
});

grafanaService.on('dashboard-synced', (context) => {
    console.log(`[Grafana] Synced: ${context.grafanaId} @ ${context.url}`);
});

grafanaService.on('dashboard-sync-failed', (context) => {
    console.log(`[Grafana] Failed: ${context.syncId} - ${context.errorCode}`);
});

grafanaService.on('alert-created', (context) => {
    console.log(`[Grafana] Alert: ${context.title}`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'grafana-integration' });
});

// Create dashboard
app.post('/dashboards', (req, res) => {
    try {
        const dashboardId = grafanaService.createDashboard(req.body);
        
        const dashboard = grafanaService.getDashboard(dashboardId);
        
        res.status(201).json({
            status: 'created',
            dashboardId,
            title: dashboard.title,
            panelCount: dashboard.panels.length,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get dashboard
app.get('/dashboards/:dashboardId', (req, res) => {
    try {
        const dashboard = grafanaService.getDashboard(req.params.dashboardId);
        
        if (!dashboard) {
            return res.status(404).json({ error: 'Dashboard not found' });
        }
        
        res.json({
            dashboardId: dashboard.dashboardId,
            title: dashboard.title,
            description: dashboard.description,
            panelCount: dashboard.panels.length,
            annotationCount: dashboard.annotations.length,
            synced: dashboard.synced,
            syncedAt: dashboard.syncedAt,
            version: dashboard.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Query dashboards
app.get('/dashboards', (req, res) => {
    try {
        const filters = {
            synced: req.query.synced ? req.query.synced === 'true' : undefined,
            tag: req.query.tag,
            limit: req.query.limit ? parseInt(req.query.limit) : 100,
        };
        
        const dashboards = grafanaService.queryDashboards(filters);
        
        res.json({
            total: dashboards.length,
            dashboards: dashboards.map(d => ({
                dashboardId: d.dashboardId,
                title: d.title,
                panelCount: d.panels.length,
                synced: d.synced,
                version: d.version,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Create panel
app.post('/panels', (req, res) => {
    try {
        const panelId = grafanaService.createPanel(req.body);
        
        const panel = grafanaService.panels.get(panelId);
        
        res.status(201).json({
            status: 'created',
            panelId,
            title: panel.title,
            type: panel.type,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Sync dashboard (idempotent)
app.post('/dashboards/:dashboardId/sync', (req, res) => {
    try {
        const syncToken = req.headers['x-sync-token'] || 
            `sync-${req.params.dashboardId}-${Date.now()}`;
        
        const syncId = grafanaService.syncDashboard(req.params.dashboardId, syncToken);
        
        const sync = grafanaService.getSync(syncId);
        
        res.json({
            status: 'syncing',
            syncId,
            dashboardId: req.params.dashboardId,
            syncedAt: sync.syncedAt,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get sync
app.get('/syncs/:syncId', (req, res) => {
    try {
        const sync = grafanaService.getSync(req.params.syncId);
        
        if (!sync) {
            return res.status(404).json({ error: 'Sync not found' });
        }
        
        res.json({
            syncId: sync.syncId,
            dashboardId: sync.dashboardId,
            status: sync.status,
            grafanaId: sync.grafanaId,
            url: sync.url,
            syncedAt: sync.syncedAt,
            version: sync.version,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record sync success
app.post('/syncs/:syncId/success', (req, res) => {
    try {
        grafanaService.recordSyncSuccess(req.params.syncId, req.body);
        
        const sync = grafanaService.getSync(req.params.syncId);
        
        res.json({
            status: 'synced',
            syncId: req.params.syncId,
            grafanaId: sync.grafanaId,
            url: sync.url,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record sync failure
app.post('/syncs/:syncId/failure', (req, res) => {
    try {
        grafanaService.recordSyncFailure(req.params.syncId, req.body);
        
        res.json({
            status: 'failure_recorded',
            syncId: req.params.syncId,
            errorCode: req.body.code,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Create alert rule
app.post('/alerts', (req, res) => {
    try {
        const alertId = grafanaService.createAlertRule(req.body);
        
        const alert = grafanaService.alerts.get(alertId);
        
        res.status(201).json({
            status: 'created',
            alertId,
            title: alert.title,
            condition: alert.condition,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get statistics
app.get('/statistics', (req, res) => {
    try {
        const stats = grafanaService.getStatistics();
        
        res.json({
            totalDashboards: stats.totalDashboards,
            syncedDashboards: stats.syncedDashboards,
            unsyncedDashboards: stats.unsyncedDashboards,
            totalPanels: stats.totalPanels,
            totalAlerts: stats.totalAlerts,
            totalSyncs: stats.totalSyncs,
            successfulSyncs: stats.successfulSyncs,
            failedSyncs: stats.failedSyncs,
            syncSuccessRatePercent: stats.syncSuccessRate,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[Grafana Integration API] Listening on port ${PORT}`);
    console.log(`[Grafana Integration API] POST /dashboards - Create dashboard`);
    console.log(`[Grafana Integration API] GET /dashboards/:id - Get dashboard`);
    console.log(`[Grafana Integration API] GET /dashboards - Query dashboards`);
    console.log(`[Grafana Integration API] POST /dashboards/:id/sync - Sync (idempotent)`);
    console.log(`[Grafana Integration API] GET /syncs/:id - Get sync`);
    console.log(`[Grafana Integration API] POST /syncs/:id/success - Record success`);
    console.log(`[Grafana Integration API] POST /syncs/:id/failure - Record failure`);
    console.log(`[Grafana Integration API] POST /panels - Create panel`);
    console.log(`[Grafana Integration API] POST /alerts - Create alert`);
    console.log(`[Grafana Integration API] GET /statistics - Get statistics`);
});
