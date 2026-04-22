#!/usr/bin/env node
/**
 * @file        scripts/collaboration/dashboard-collaboration-service.js
 * @module      collaboration/dashboard
 * @description Collaborative dashboard with immutable snapshots and real-time updates
 *
 * IaC Principles:
 * - Immutable: Dashboard layouts frozen after save
 * - Immutable: Widget configurations frozen
 * - Immutable: Collaboration sessions frozen
 * - Idempotent: Same update = same result
 * - Versioned: Dashboard versions for undo/redo
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class DashboardCollaborationService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.serviceName = options.serviceName || 'code-server';
        
        // Immutable dashboards (frozen)
        this.dashboards = new Map(); // dashboardId → frozen dashboard
        
        // Dashboard versions (immutable history)
        this.dashboardVersions = new Map(); // dashboardId → frozen version array
        
        // Collaboration sessions (frozen)
        this.sessions = new Map(); // sessionId → frozen session
        
        // Widget states (immutable)
        this.widgets = new Map(); // widgetId → frozen widget
        
        // Collaboration cursors (real-time, non-frozen)
        this.cursors = new Map(); // userId → cursor position
        
        // Token-based idempotency
        this.updateTokens = new Map(); // token → dashboardId
        this.saveTokens = new Map(); // token → versionId
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
            name: dashboardData.name,
            description: dashboardData.description || '',
            workspaceId: dashboardData.workspaceId,
            
            // Owner (immutable)
            createdBy: dashboardData.userId,
            createdAt: new Date().toISOString(),
            createdAtMs: now,
            
            // Collaboration (immutable)
            collaborators: Object.freeze([
                {
                    userId: dashboardData.userId,
                    role: 'owner',
                    permissions: ['edit', 'delete', 'share'],
                    joinedAt: new Date().toISOString(),
                }
            ]),
            
            // Layout (immutable)
            layout: Object.freeze(dashboardData.layout || {
                gridSize: 12,
                rowHeight: 60,
            }),
            
            // Widgets (immutable array)
            widgets: Object.freeze(dashboardData.widgets || []),
            
            // Settings (immutable)
            settings: Object.freeze({
                refreshInterval: dashboardData.refreshInterval || 30000,
                autoSave: dashboardData.autoSave !== false,
                shareable: false,
            }),
            
            // Status (mutable)
            status: 'active',
            lastModifiedBy: dashboardData.userId,
            lastModifiedAt: new Date().toISOString(),
            lastModifiedAtMs: now,
            
            // Version tracking (immutable)
            version: 1,
            changeLog: Object.freeze([
                {
                    version: 1,
                    action: 'created',
                    by: dashboardData.userId,
                    at: new Date().toISOString(),
                }
            ]),
        };
        
        Object.freeze(dashboard);
        this.dashboards.set(dashboardId, dashboard);
        
        // Initialize version history
        this.dashboardVersions.set(dashboardId, [dashboard]);
        
        this.emit('dashboard-created', {
            dashboardId,
            name: dashboard.name,
            createdBy: dashboard.createdBy,
        });
        
        return dashboardId;
    }
    
    /**
     * Update dashboard (creates new version)
     */
    updateDashboard(dashboardId, updateData, updateToken) {
        // Idempotency check
        if (updateToken && this.updateTokens.has(updateToken)) {
            return this.updateTokens.get(updateToken);
        }
        
        const current = this.dashboards.get(dashboardId);
        if (!current) throw new Error(`Dashboard ${dashboardId} not found`);
        
        const now = Date.now();
        
        // Create new immutable dashboard version
        const updated = {
            ...current,
            // Update mutable fields
            lastModifiedBy: updateData.userId,
            lastModifiedAt: new Date().toISOString(),
            lastModifiedAtMs: now,
            
            // Update immutable fields with new version
            widgets: Object.freeze(updateData.widgets || current.widgets),
            layout: Object.freeze(updateData.layout || current.layout),
            
            version: current.version + 1,
            changeLog: Object.freeze([
                ...current.changeLog,
                {
                    version: current.version + 1,
                    action: updateData.action || 'updated',
                    by: updateData.userId,
                    at: new Date().toISOString(),
                    details: updateData.details,
                }
            ]),
        };
        
        Object.freeze(updated);
        this.dashboards.set(dashboardId, updated);
        
        // Store in version history
        const versions = this.dashboardVersions.get(dashboardId) || [];
        versions.push(updated);
        this.dashboardVersions.set(dashboardId, versions);
        
        if (updateToken) {
            this.updateTokens.set(updateToken, dashboardId);
        }
        
        this.emit('dashboard-updated', {
            dashboardId,
            version: updated.version,
            updatedBy: updateData.userId,
        });
        
        return dashboardId;
    }
    
    /**
     * Save dashboard version (immutable snapshot)
     */
    saveDashboardVersion(dashboardId, versionData, saveToken) {
        // Idempotency check
        if (saveToken && this.saveTokens.has(saveToken)) {
            return this.saveTokens.get(saveToken);
        }
        
        const dashboard = this.dashboards.get(dashboardId);
        if (!dashboard) throw new Error(`Dashboard ${dashboardId} not found`);
        
        const versionId = `ver-${crypto.randomBytes(8).toString('hex')}`;
        const now = Date.now();
        
        // Create immutable version snapshot
        const version = {
            // Identifiers (immutable)
            versionId,
            dashboardId,
            
            // Version info (immutable)
            number: dashboard.version,
            name: versionData.name || `v${dashboard.version}`,
            description: versionData.description || '',
            
            // Snapshot (immutable - complete dashboard state)
            snapshot: Object.freeze({
                layout: dashboard.layout,
                widgets: dashboard.widgets,
                settings: dashboard.settings,
                collaborators: dashboard.collaborators,
            }),
            
            // Metadata (immutable)
            savedBy: versionData.userId,
            savedAt: new Date().toISOString(),
            savedAtMs: now,
            tags: Object.freeze(versionData.tags || []),
            
            // Restore info (immutable)
            restoreable: true,
            restoredCount: 0,
        };
        
        Object.freeze(version);
        
        if (saveToken) {
            this.saveTokens.set(saveToken, versionId);
        }
        
        this.emit('dashboard-version-saved', {
            versionId,
            dashboardId,
            versionNumber: version.number,
        });
        
        return versionId;
    }
    
    /**
     * Start collaboration session (immutable)
     */
    startCollaborationSession(sessionData) {
        const sessionId = `collab-${crypto.randomBytes(8).toString('hex')}`;
        const now = Date.now();
        
        const session = {
            // Identifiers (immutable)
            sessionId,
            dashboardId: sessionData.dashboardId,
            workspaceId: sessionData.workspaceId,
            
            // Participants (immutable)
            host: sessionData.hostUserId,
            participants: Object.freeze([
                {
                    userId: sessionData.hostUserId,
                    joinedAt: new Date().toISOString(),
                    status: 'active',
                }
            ]),
            
            // Session info (immutable)
            startedAt: new Date().toISOString(),
            startedAtMs: now,
            
            // Features (immutable)
            features: Object.freeze({
                liveEditing: sessionData.liveEditing !== false,
                cursorTracking: sessionData.cursorTracking !== false,
                presenceAwareness: sessionData.presenceAwareness !== false,
            }),
            
            // State (mutable)
            status: 'active',
            lastActivity: now,
            
            version: 1,
        };
        
        Object.freeze(session);
        this.sessions.set(sessionId, session);
        
        this.emit('collaboration-session-started', {
            sessionId,
            dashboardId: session.dashboardId,
            host: session.host,
        });
        
        return sessionId;
    }
    
    /**
     * Add collaborator to dashboard (creates new version)
     */
    addCollaborator(dashboardId, collaboratorData) {
        const dashboard = this.dashboards.get(dashboardId);
        if (!dashboard) throw new Error(`Dashboard ${dashboardId} not found`);
        
        const now = Date.now();
        
        // Check if already collaborator
        const exists = dashboard.collaborators.some(c => c.userId === collaboratorData.userId);
        if (exists) return dashboardId;
        
        // Create new collaborator entry
        const newCollaborator = Object.freeze({
            userId: collaboratorData.userId,
            role: collaboratorData.role || 'viewer',
            permissions: this.getPermissionsForRole(collaboratorData.role || 'viewer'),
            joinedAt: new Date().toISOString(),
        });
        
        // Create new dashboard version with updated collaborators
        const updated = {
            ...dashboard,
            collaborators: Object.freeze([
                ...dashboard.collaborators,
                newCollaborator,
            ]),
            version: dashboard.version + 1,
            changeLog: Object.freeze([
                ...dashboard.changeLog,
                {
                    version: dashboard.version + 1,
                    action: 'collaborator_added',
                    by: collaboratorData.addedBy,
                    at: new Date().toISOString(),
                    details: {
                        userId: collaboratorData.userId,
                        role: newCollaborator.role,
                    }
                }
            ]),
            lastModifiedBy: collaboratorData.addedBy,
            lastModifiedAt: new Date().toISOString(),
            lastModifiedAtMs: now,
        };
        
        Object.freeze(updated);
        this.dashboards.set(dashboardId, updated);
        
        const versions = this.dashboardVersions.get(dashboardId) || [];
        versions.push(updated);
        this.dashboardVersions.set(dashboardId, versions);
        
        this.emit('collaborator-added', {
            dashboardId,
            userId: collaboratorData.userId,
            role: newCollaborator.role,
        });
        
        return dashboardId;
    }
    
    /**
     * Get permissions for role
     */
    getPermissionsForRole(role) {
        const permissions = {
            owner: ['view', 'edit', 'delete', 'share', 'admin'],
            editor: ['view', 'edit', 'share'],
            viewer: ['view'],
        };
        return permissions[role] || permissions.viewer;
    }
    
    /**
     * Update cursor position (real-time, non-frozen)
     */
    updateCursorPosition(userId, cursorData) {
        this.cursors.set(userId, {
            userId,
            x: cursorData.x,
            y: cursorData.y,
            timestamp: Date.now(),
            color: cursorData.color || '#FF0000',
        });
        
        this.emit('cursor-updated', {
            userId,
            x: cursorData.x,
            y: cursorData.y,
        });
    }
    
    /**
     * Get dashboard (immutable snapshot)
     */
    getDashboard(dashboardId) {
        const dashboard = this.dashboards.get(dashboardId);
        return dashboard ? Object.freeze({ ...dashboard }) : null;
    }
    
    /**
     * Get dashboard version history (immutable array)
     */
    getDashboardVersionHistory(dashboardId) {
        const versions = this.dashboardVersions.get(dashboardId) || [];
        return Object.freeze(versions.map(v => Object.freeze({ ...v })));
    }
    
    /**
     * Get collaboration session (immutable snapshot)
     */
    getCollaborationSession(sessionId) {
        const session = this.sessions.get(sessionId);
        return session ? Object.freeze({ ...session }) : null;
    }
    
    /**
     * Query dashboards (immutable array)
     */
    queryDashboards(filters = {}) {
        let dashboards = Array.from(this.dashboards.values());
        
        // Filter by workspace
        if (filters.workspaceId) {
            dashboards = dashboards.filter(d => d.workspaceId === filters.workspaceId);
        }
        
        // Filter by user (collaborator)
        if (filters.userId) {
            dashboards = dashboards.filter(d =>
                d.collaborators.some(c => c.userId === filters.userId)
            );
        }
        
        // Filter by status
        if (filters.status) {
            dashboards = dashboards.filter(d => d.status === filters.status);
        }
        
        // Sort by last modified (newest first)
        dashboards.sort((a, b) => b.lastModifiedAtMs - a.lastModifiedAtMs);
        
        const limit = filters.limit || 100;
        return Object.freeze(
            dashboards.slice(0, limit).map(d => Object.freeze(d))
        );
    }
    
    /**
     * Get collaboration statistics (immutable)
     */
    getCollaborationStatistics() {
        const allDashboards = Array.from(this.dashboards.values());
        const allSessions = Array.from(this.sessions.values());
        
        const stats = {
            totalDashboards: allDashboards.length,
            activeSessions: allSessions.filter(s => s.status === 'active').length,
            totalParticipants: new Set(
                allSessions.flatMap(s => s.participants.map(p => p.userId))
            ).size,
            averageCollaborators: allDashboards.length > 0
                ? allDashboards.reduce((sum, d) => sum + d.collaborators.length, 0) / allDashboards.length
                : 0,
            totalVersions: Array.from(this.dashboardVersions.values()).reduce((sum, v) => sum + v.length, 0),
        };
        
        return Object.freeze(stats);
    }
}

module.exports = DashboardCollaborationService;
