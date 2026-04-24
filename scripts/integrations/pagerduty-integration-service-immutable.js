#!/usr/bin/env node
/**
 * @file        scripts/integrations/pagerduty-integration-service.js
 * @module      integrations/pagerduty
 * @description PagerDuty incident management with immutable alerts and idempotent escalations
 *
 * IaC Principles:
 * - Immutable: Alert events frozen once created
 * - Immutable: Escalation policies frozen
 * - Idempotent: Same alert = same incident ID
 * - Versioned: Incident state versions for audit trail
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class PagerDutyIntegrationService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.apiKey = options.apiKey || process.env.PAGERDUTY_API_KEY || '';
        this.integrationKey = options.integrationKey || process.env.PAGERDUTY_INTEGRATION_KEY || '';
        
        // Immutable alerts (frozen)
        this.alerts = new Map(); // alertId → frozen alert
        
        // Immutable incidents (frozen)
        this.incidents = new Map(); // incidentId → frozen incident
        
        // Escalation policies (frozen)
        this.escalationPolicies = new Map(); // policyId → frozen policy
        
        // On-call schedules (frozen)
        this.onCallSchedules = new Map(); // scheduleId → frozen schedule
        
        // Token-based idempotency
        this.alertTokens = new Map(); // token → alertId
        this.incidentTokens = new Map(); // token → incidentId
    }
    
    /**
     * Create alert (immutable)
     */
    createAlert(alertData, alertToken) {
        // Idempotency check
        if (alertToken && this.alertTokens.has(alertToken)) {
            return this.alertTokens.get(alertToken);
        }
        
        const alertId = `alert-${crypto.randomBytes(8).toString('hex')}`;
        const now = Date.now();
        
        // Create immutable alert
        const alert = {
            // Identifiers (immutable)
            alertId,
            alertName: alertData.alertName,
            alertType: alertData.alertType || 'incident',  // incident, error, warning
            
            // Source (immutable)
            source: alertData.source || 'monitoring',
            sourceId: alertData.sourceId,
            workspaceId: alertData.workspaceId,
            
            // Alert details (immutable)
            severity: alertData.severity || 'error',  // critical, error, warning, info
            title: alertData.title,
            description: alertData.description || '',
            
            // Context (immutable)
            affectedComponent: alertData.affectedComponent,
            affectedService: alertData.affectedService,
            tags: Object.freeze(alertData.tags || []),
            
            // Timing (immutable)
            createdAt: new Date().toISOString(),
            createdAtMs: now,
            
            // Status (mutable)
            status: 'triggered',
            acknowledged: false,
            resolvedAt: null,
            
            // Metrics (immutable)
            errorRate: alertData.errorRate || 0,
            latencyP99: alertData.latencyP99 || 0,
            customMetrics: Object.freeze(alertData.customMetrics || {}),
            
            // Assignment (mutable)
            assignedTo: null,
            escalationLevel: 0,
            
            version: 1,
        };
        
        Object.freeze(alert);
        this.alerts.set(alertId, alert);
        
        if (alertToken) {
            this.alertTokens.set(alertToken, alertId);
        }
        
        this.emit('alert-created', {
            alertId,
            alertName: alert.alertName,
            severity: alert.severity,
            source: alert.source,
        });
        
        return alertId;
    }
    
    /**
     * Create incident from alert (idempotent)
     */
    createIncidentFromAlert(alertId, incidentData, incidentToken) {
        // Idempotency check
        if (incidentToken && this.incidentTokens.has(incidentToken)) {
            return this.incidentTokens.get(incidentToken);
        }
        
        const alert = this.alerts.get(alertId);
        if (!alert) throw new Error(`Alert ${alertId} not found`);
        
        const incidentId = `incident-${crypto.randomBytes(8).toString('hex')}`;
        const now = Date.now();
        
        // Create immutable incident
        const incident = {
            // Identifiers (immutable)
            incidentId,
            alertId,
            pagerDutyId: incidentData.pagerDutyId || null,
            
            // Incident details (immutable)
            title: alert.title,
            description: alert.description,
            severity: alert.severity,
            
            // Service info (immutable)
            service: alert.affectedService,
            component: alert.affectedComponent,
            workspace: alert.workspaceId,
            
            // Timing (immutable)
            createdAt: new Date().toISOString(),
            createdAtMs: now,
            
            // Status (mutable)
            status: 'triggered',  // triggered, acknowledged, resolved
            
            // Assignment (mutable)
            assignedTo: null,
            escalationLevel: 0,
            onCallUser: null,
            
            // Notifications (immutable array)
            notifications: Object.freeze([]),
            
            // Version tracking
            version: 1,
        };
        
        Object.freeze(incident);
        this.incidents.set(incidentId, incident);
        
        if (incidentToken) {
            this.incidentTokens.set(incidentToken, incidentId);
        }
        
        this.emit('incident-created', {
            incidentId,
            alertId,
            title: incident.title,
            severity: incident.severity,
        });
        
        return incidentId;
    }
    
    /**
     * Trigger on-call notification (creates new incident version)
     */
    triggerOnCallNotification(incidentId, escalationData) {
        const incident = this.incidents.get(incidentId);
        if (!incident) throw new Error(`Incident ${incidentId} not found`);
        
        const now = Date.now();
        
        // Find on-call user for escalation level
        const onCallUser = this.getOnCallUser(escalationData.escalationLevel);
        
        // Create new incident version
        const updated = {
            ...incident,
            escalationLevel: escalationData.escalationLevel || 0,
            assignedTo: onCallUser?.userId,
            onCallUser: onCallUser ? Object.freeze({
                userId: onCallUser.userId,
                name: onCallUser.name,
                email: onCallUser.email,
                phone: onCallUser.phone,
                pagerDutyId: onCallUser.pagerDutyId,
            }) : null,
            notifications: Object.freeze([
                ...(incident.notifications || []),
                {
                    userId: onCallUser?.userId,
                    notifiedAt: new Date().toISOString(),
                    method: escalationData.method || 'email',
                    escalationLevel: escalationData.escalationLevel,
                }
            ]),
            version: incident.version + 1,
        };
        
        Object.freeze(updated);
        this.incidents.set(incidentId, updated);
        
        this.emit('on-call-notified', {
            incidentId,
            userId: onCallUser?.userId,
            escalationLevel: escalationData.escalationLevel,
            method: escalationData.method,
        });
        
        return incidentId;
    }
    
    /**
     * Get on-call user for escalation level
     */
    getOnCallUser(escalationLevel = 0) {
        // In production, fetch from PagerDuty API
        // For demo, return mock on-call user
        const onCallUsers = [
            {
                userId: 'user-oncall-1',
                name: 'Alice (Primary)',
                email: 'alice@example.com',
                phone: '+1-555-0100',
                pagerDutyId: 'PABC123',
            },
            {
                userId: 'user-oncall-2',
                name: 'Bob (Secondary)',
                email: 'bob@example.com',
                phone: '+1-555-0200',
                pagerDutyId: 'PABC456',
            },
            {
                userId: 'user-oncall-3',
                name: 'Charlie (Tertiary)',
                email: 'charlie@example.com',
                phone: '+1-555-0300',
                pagerDutyId: 'PABC789',
            },
        ];
        
        return onCallUsers[Math.min(escalationLevel, onCallUsers.length - 1)];
    }
    
    /**
     * Create escalation policy (immutable)
     */
    createEscalationPolicy(policyData) {
        const policyId = `policy-${crypto.randomBytes(8).toString('hex')}`;
        
        const policy = {
            // Identifiers (immutable)
            policyId,
            name: policyData.name,
            
            // Escalation rules (immutable)
            escalationRules: Object.freeze((policyData.escalationRules || []).map(rule =>
                Object.freeze({
                    level: rule.level,
                    userId: rule.userId,
                    delay: rule.delay || 300000,  // 5 min default
                })
            )),
            
            // Settings (immutable)
            repeatEscalation: policyData.repeatEscalation !== false,
            repeatAfter: policyData.repeatAfter || 3600000,  // 1 hour default
            
            // Timestamps (immutable)
            createdAt: new Date().toISOString(),
            
            version: 1,
        };
        
        Object.freeze(policy);
        this.escalationPolicies.set(policyId, policy);
        
        this.emit('escalation-policy-created', {
            policyId,
            name: policy.name,
            ruleCount: policy.escalationRules.length,
        });
        
        return policyId;
    }
    
    /**
     * Acknowledge incident (creates new version)
     */
    acknowledgeIncident(incidentId, ackData) {
        const incident = this.incidents.get(incidentId);
        if (!incident) throw new Error(`Incident ${incidentId} not found`);
        
        const updated = {
            ...incident,
            status: 'acknowledged',
            acknowledgedBy: ackData.userId,
            acknowledgedAt: new Date().toISOString(),
            version: incident.version + 1,
        };
        
        Object.freeze(updated);
        this.incidents.set(incidentId, updated);
        
        this.emit('incident-acknowledged', {
            incidentId,
            acknowledgedBy: ackData.userId,
        });
        
        return incidentId;
    }
    
    /**
     * Resolve incident (creates new version)
     */
    resolveIncident(incidentId, resolveData) {
        const incident = this.incidents.get(incidentId);
        if (!incident) throw new Error(`Incident ${incidentId} not found`);
        
        const now = Date.now();
        
        const updated = {
            ...incident,
            status: 'resolved',
            resolvedBy: resolveData.userId,
            resolvedAt: new Date().toISOString(),
            resolvedAtMs: now,
            resolution: resolveData.resolution || '',
            version: incident.version + 1,
        };
        
        Object.freeze(updated);
        this.incidents.set(incidentId, updated);
        
        this.emit('incident-resolved', {
            incidentId,
            resolvedBy: resolveData.userId,
            duration: now - incident.createdAtMs,
        });
        
        return incidentId;
    }
    
    /**
     * Get incident (immutable snapshot)
     */
    getIncident(incidentId) {
        const incident = this.incidents.get(incidentId);
        return incident ? Object.freeze({ ...incident }) : null;
    }
    
    /**
     * Query incidents (immutable array)
     */
    queryIncidents(filters = {}) {
        let incidents = Array.from(this.incidents.values());
        
        // Filter by status
        if (filters.status) {
            incidents = incidents.filter(i => i.status === filters.status);
        }
        
        // Filter by severity
        if (filters.severity) {
            incidents = incidents.filter(i => i.severity === filters.severity);
        }
        
        // Filter by service
        if (filters.service) {
            incidents = incidents.filter(i => i.service === filters.service);
        }
        
        // Sort by creation time (newest first)
        incidents.sort((a, b) => b.createdAtMs - a.createdAtMs);
        
        const limit = filters.limit || 100;
        return Object.freeze(
            incidents.slice(0, limit).map(i => Object.freeze(i))
        );
    }
    
    /**
     * Get incident statistics (immutable)
     */
    getIncidentStatistics() {
        const allIncidents = Array.from(this.incidents.values());
        
        const stats = {
            totalIncidents: allIncidents.length,
            byStatus: {
                triggered: allIncidents.filter(i => i.status === 'triggered').length,
                acknowledged: allIncidents.filter(i => i.status === 'acknowledged').length,
                resolved: allIncidents.filter(i => i.status === 'resolved').length,
            },
            bySeverity: {
                critical: allIncidents.filter(i => i.severity === 'critical').length,
                error: allIncidents.filter(i => i.severity === 'error').length,
                warning: allIncidents.filter(i => i.severity === 'warning').length,
            },
            avgResolutionTime: this.calculateAvgResolutionTime(allIncidents),
            totalEscalations: allIncidents.reduce((sum, i) => sum + (i.escalationLevel || 0), 0),
        };
        
        return Object.freeze(stats);
    }
    
    /**
     * Calculate average resolution time
     */
    calculateAvgResolutionTime(incidents) {
        const resolved = incidents.filter(i => i.status === 'resolved');
        if (resolved.length === 0) return 0;
        
        const totalTime = resolved.reduce((sum, i) => {
            return sum + ((i.resolvedAtMs || 0) - i.createdAtMs);
        }, 0);
        
        return Math.round(totalTime / resolved.length);
    }
}

module.exports = PagerDutyIntegrationService;
