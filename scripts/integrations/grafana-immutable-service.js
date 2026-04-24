#!/usr/bin/env node
/**
 * @file        scripts/integrations/grafana-immutable-service.js
 * @module      integrations/grafana
 * @description Grafana dashboard integration with immutable dashboards and idempotent sync
 *
 * IaC Principles:
 * - Immutable: Dashboard definitions frozen once created
 * - Immutable: Panel configurations frozen with metrics
 * - Idempotent: Same syncToken = same dashboard state
 * - Versioned: Dashboard versions for rollback capability
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class GrafanaIntegrationService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.apiKey = options.apiKey || process.env.GRAFANA_API_KEY || '';
        this.baseUrl = options.baseUrl || process.env.GRAFANA_URL || 'http://localhost:3000';
        
        // Immutable dashboard definitions (frozen)
        this.dashboards = new Map(); // dashboardId → frozen dashboard
        
        // Immutable panels (frozen)
        this.panels = new Map(); // panelId → frozen panel
        
        // Immutable syncs (frozen)
        this.syncs = new Map(); // syncId → frozen sync
        
        // Token to syncId mapping (idempotency)
        this.syncTokens = new Map(); // token → syncId
        
        // Immutable alerts (frozen)
        this.alerts = new Map(); // alertId → frozen alert
        
        // Sync history
        this.syncHistory = [];
    }
    
    /**
     * Create dashboard (immutable)
     */
    createDashboard(dashboardData) {
        const dashboardId = `dash-${crypto.randomBytes(8).toString('hex')}`;
        const now = Date.now();
        
        const dashboard = {
            // Identifiers (immutable)
            dashboardId,
            title: dashboardData.title,
            slug: dashboardData.slug || dashboardData.title.toLowerCase().replace(/\s+/g, '-'),
            
            // Content (immutable)
            description: dashboardData.description,
            tags: Object.freeze(dashboardData.tags || []),
            
            // Layout (immutable)
            refresh: dashboardData.refresh || '30s',
            timezone: dashboardData.timezone || 'browser',
            
            // Panels (immutable)
            panels: Object.freeze((dashboardData.panels || []).map(p => ({
                panelId: `panel-${crypto.randomBytes(4).toString('hex')}`,
                title: p.title,
                type: p.type,  // graph, stat, gauge, table, etc.
                targets: Object.freeze((p.targets || []).map(t =>
                    Object.freeze({
                        metric: t.metric,
                        refId: t.refId || 'A',
                        label: t.label,
                    })
                )),
                options: Object.freeze(p.options || {}),
                gridPos: Object.freeze(p.gridPos || {}),
            }))),
            
            // Annotations (immutable)
            annotations: Object.freeze((dashboardData.annotations || []).map(a =>
                Object.freeze({
                    annotationId: `anno-${crypto.randomBytes(4).toString('hex')}`,
                    name: a.name,
                    datasource: a.datasource,
                    tagKeys: a.tagKeys,
                })
            )),
            
            // Timing (immutable)
            createdAt: new Date().toISOString(),
            createdAtMs: now,
            
            // Status (mutable)
            grafanaId: null,
            url: null,
            synced: false,
            syncedAt: null,
            
            version: 1,
        };
        
        Object.freeze(dashboard);
        this.dashboards.set(dashboardId, dashboard);
        
        this.emit('dashboard-created', {
            dashboardId,
            title: dashboard.title,
            panelCount: dashboard.panels.length,
        });
        
        return dashboardId;
    }
    
    /**
     * Create panel (immutable)
     */
    createPanel(panelData) {
        const panelId = `panel-${crypto.randomBytes(8).toString('hex')}`;
        
        const panel = {
            // Identifiers (immutable)
            panelId,
            dashboardId: panelData.dashboardId,
            
            // Panel definition (immutable)
            title: panelData.title,
            type: panelData.type,  // graph, stat, gauge, table, heatmap
            
            // Targets (immutable)
            targets: Object.freeze((panelData.targets || []).map(t =>
                Object.freeze({
                    metric: t.metric,
                    refId: t.refId || 'A',
                    label: t.label,
                    legendFormat: t.legendFormat,
                })
            )),
            
            // Options (immutable)
            options: Object.freeze(panelData.options || {}),
            
            // Field config (immutable)
            fieldConfig: Object.freeze(panelData.fieldConfig || {}),
            
            // Grid position (immutable)
            gridPos: Object.freeze(panelData.gridPos || {
                x: 0, y: 0, w: 12, h: 8
            }),
            
            // Timing (immutable)
            createdAt: new Date().toISOString(),
            createdAtMs: Date.now(),
            
            // Status (mutable)
            grafanaId: null,
            version: 1,
        };
        
        Object.freeze(panel);
        this.panels.set(panelId, panel);
        
        this.emit('panel-created', {
            panelId,
            title: panel.title,
            type: panel.type,
        });
        
        return panelId;
    }
    
    /**
     * Sync dashboard to Grafana (idempotent)
     */
    syncDashboard(dashboardId, syncToken) {
        // Idempotency check
        if (syncToken && this.syncTokens.has(syncToken)) {
            return this.syncTokens.get(syncToken);
        }
        
        const dashboard = this.dashboards.get(dashboardId);
        if (!dashboard) throw new Error(`Dashboard ${dashboardId} not found`);
        
        const syncId = `sync-${crypto.randomBytes(8).toString('hex')}`;
        const now = Date.now();
        
        // Create immutable sync record
        const sync = {
            // Identifiers (immutable)
            syncId,
            dashboardId,
            
            // Dashboard snapshot (immutable)
            dashboardSnapshot: Object.freeze({
                title: dashboard.title,
                slug: dashboard.slug,
                panelCount: dashboard.panels.length,
                annotationCount: dashboard.annotations.length,
            }),
            
            // Sync info (immutable)
            syncedAt: new Date().toISOString(),
            syncedAtMs: now,
            
            // Status (mutable)
            status: 'syncing',
            grafanaId: null,
            url: null,
            errorCode: null,
            errorMessage: null,
            
            version: 1,
        };
        
        Object.freeze(sync);
        this.syncs.set(syncId, sync);
        
        // Update dashboard (create new version)
        const updatedDash = {
            ...dashboard,
            synced: true,
            syncedAt: sync.syncedAt,
            version: dashboard.version + 1,
        };
        
        Object.freeze(updatedDash);
        this.dashboards.set(dashboardId, updatedDash);
        
        if (syncToken) {
            this.syncTokens.set(syncToken, syncId);
        }
        
        this.recordSyncHistory(syncId, 'syncing');
        
        this.emit('dashboard-syncing', {
            syncId,
            dashboardId,
            title: dashboard.title,
        });
        
        return syncId;
    }
    
    /**
     * Record sync success
     */
    recordSyncSuccess(syncId, successData) {
        const sync = this.syncs.get(syncId);
        if (!sync) throw new Error(`Sync ${syncId} not found`);
        
        const updated = {
            ...sync,
            status: 'synced',
            grafanaId: successData.grafanaId,
            url: successData.url,
            version: sync.version + 1,
        };
        
        Object.freeze(updated);
        this.syncs.set(syncId, updated);
        
        this.emit('dashboard-synced', {
            syncId,
            grafanaId: successData.grafanaId,
            url: successData.url,
        });
    }
    
    /**
     * Record sync failure
     */
    recordSyncFailure(syncId, failureData) {
        const sync = this.syncs.get(syncId);
        if (!sync) throw new Error(`Sync ${syncId} not found`);
        
        const updated = {
            ...sync,
            status: 'failed',
            errorCode: failureData.code,
            errorMessage: failureData.message,
            version: sync.version + 1,
        };
        
        Object.freeze(updated);
        this.syncs.set(syncId, updated);
        
        this.emit('dashboard-sync-failed', {
            syncId,
            errorCode: failureData.code,
        });
    }
    
    /**
     * Create alert rule (immutable)
     */
    createAlertRule(alertData) {
        const alertId = `alert-${crypto.randomBytes(8).toString('hex')}`;
        
        const alert = {
            // Identifiers (immutable)
            alertId,
            dashboardId: alertData.dashboardId,
            
            // Alert definition (immutable)
            title: alertData.title,
            condition: alertData.condition,  // e.g., "avg(metric) > 100"
            evaluationTime: alertData.evaluationTime || '5m',
            forDuration: alertData.forDuration || '5m',
            
            // Notification (immutable)
            annotations: Object.freeze(alertData.annotations || {}),
            labels: Object.freeze(alertData.labels || {}),
            
            // Targets (immutable)
            targets: Object.freeze((alertData.targets || []).map(t =>
                Object.freeze({
                    metric: t.metric,
                    refId: t.refId,
                })
            )),
            
            // Timing (immutable)
            createdAt: new Date().toISOString(),
            createdAtMs: Date.now(),
            
            // Status (mutable)
            enabled: true,
            grafanaId: null,
            
            version: 1,
        };
        
        Object.freeze(alert);
        this.alerts.set(alertId, alert);
        
        this.emit('alert-created', {
            alertId,
            title: alert.title,
            condition: alert.condition,
        });
        
        return alertId;
    }
    
    /**
     * Get dashboard (immutable snapshot)
     */
    getDashboard(dashboardId) {
        const dash = this.dashboards.get(dashboardId);
        return dash ? Object.freeze({ ...dash }) : null;
    }
    
    /**
     * Get sync (immutable snapshot)
     */
    getSync(syncId) {
        const sync = this.syncs.get(syncId);
        return sync ? Object.freeze({ ...sync }) : null;
    }
    
    /**
     * Query dashboards (immutable array)
     */
    queryDashboards(filters = {}) {
        let dashes = Array.from(this.dashboards.values());
        
        if (filters.synced !== undefined) {
            dashes = dashes.filter(d => d.synced === filters.synced);
        }
        
        if (filters.tag) {
            dashes = dashes.filter(d => d.tags.includes(filters.tag));
        }
        
        dashes.sort((a, b) => b.createdAtMs - a.createdAtMs);
        
        const limit = filters.limit || 100;
        return Object.freeze(
            dashes.slice(0, limit).map(d => Object.freeze(d))
        );
    }
    
    /**
     * Get statistics (immutable)
     */
    getStatistics() {
        const allDashes = Array.from(this.dashboards.values());
        const allSyncs = Array.from(this.syncs.values());
        
        const stats = {
            totalDashboards: allDashes.length,
            syncedDashboards: allDashes.filter(d => d.synced).length,
            unsyncedDashboards: allDashes.filter(d => !d.synced).length,
            
            totalPanels: this.panels.size,
            totalAlerts: this.alerts.size,
            
            totalSyncs: allSyncs.length,
            successfulSyncs: allSyncs.filter(s => s.status === 'synced').length,
            failedSyncs: allSyncs.filter(s => s.status === 'failed').length,
            
            syncSuccessRate: allSyncs.length > 0
                ? ((allSyncs.filter(s => s.status === 'synced').length / allSyncs.length) * 100).toFixed(2)
                : 0,
        };
        
        return Object.freeze(stats);
    }
    
    /**
     * Record sync history
     */
    recordSyncHistory(syncId, action) {
        const sync = this.syncs.get(syncId);
        
        const record = Object.freeze({
            timestamp: new Date().toISOString(),
            timestampMs: Date.now(),
            action,
            syncId,
            status: sync.status,
        });
        
        this.syncHistory.push(record);
    }
}

module.exports = GrafanaIntegrationService;
