#!/usr/bin/env node
/**
 * @file        scripts/observability/incident-correlation-service.js
 * @module      observability/incidents
 * @description Incident correlation engine with immutable rules and traces
 *
 * IaC Principles:
 * - Immutable: Correlation rules frozen once created
 * - Immutable: Incident snapshots frozen once correlated
 * - Idempotent: Same incident events = same correlations
 * - Versioned: Correlation rule versions for auditing
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class IncidentCorrelationService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.serviceName = options.serviceName || 'code-server';
        
        // Immutable correlation rules (frozen)
        this.correlationRules = new Map(); // ruleId → frozen rule
        
        // Incident records (frozen)
        this.incidents = new Map(); // incidentId → frozen incident
        
        // Correlations (frozen)
        this.correlations = new Map(); // correlationId → frozen correlation
        
        // Token-based idempotency tracking
        this.correlationTokens = new Map(); // token → correlationId
    }
    
    /**
     * Create correlation rule (immutable)
     */
    createCorrelationRule(ruleConfig) {
        const ruleId = `rule-${crypto.randomBytes(8).toString('hex')}`;
        
        const rule = {
            // Identifiers (immutable)
            ruleId,
            name: ruleConfig.name,
            description: ruleConfig.description || '',
            
            // Pattern (immutable)
            pattern: {
                errorType: ruleConfig.errorType,  // e.g., 'database.timeout'
                errorRate: ruleConfig.errorRate || 0.05, // 5%
                timeWindow: ruleConfig.timeWindow || 300, // 5 minutes
            },
            
            // Correlation targets (immutable)
            correlateWith: Object.freeze(ruleConfig.correlateWith || []),
            
            // Actions (immutable)
            actions: Object.freeze(ruleConfig.actions || ['alert', 'notify']),
            
            // Alert routing (immutable)
            alerting: {
                slack: ruleConfig.slackChannel || 'incidents',
                pagerduty: ruleConfig.enablePagerDuty || false,
                email: ruleConfig.email || null,
            },
            
            // Enabled (can be toggled but creates new version)
            enabled: true,
            
            // Metadata (immutable)
            createdAt: new Date().toISOString(),
            createdBy: ruleConfig.createdBy || 'system',
            
            version: 1,
        };
        
        // Freeze rule
        Object.freeze(rule);
        this.correlationRules.set(ruleId, rule);
        
        this.emit('rule-created', { ruleId, name: rule.name });
        return ruleId;
    }
    
    /**
     * Record incident (immutable)
     */
    recordIncident(incidentData) {
        const incidentId = `incident-${Date.now()}-${crypto.randomBytes(8).toString('hex')}`;
        
        const incident = {
            // Identifiers (immutable)
            incidentId,
            
            // Error information (immutable)
            errorType: incidentData.errorType,
            errorMessage: incidentData.errorMessage,
            severity: incidentData.severity || 'medium', // low, medium, high, critical
            
            // Context (immutable)
            context: Object.freeze({
                userId: incidentData.userId || null,
                workspaceId: incidentData.workspaceId || null,
                traceId: incidentData.traceId || null,
                service: this.serviceName,
            }),
            
            // Metrics (immutable)
            metrics: Object.freeze({
                errorCount: incidentData.errorCount || 1,
                affectedUsers: incidentData.affectedUsers || 1,
            }),
            
            // Timing (immutable)
            timestamp: Date.now(),
            timestampIso: new Date().toISOString(),
            firstSeen: Date.now(),
            lastSeen: Date.now(),
            
            // Status (mutable during active, frozen after closed)
            status: 'open',
            
            // Correlations (immutable)
            correlatedIncidents: [],
            correlationRuleIds: [],
            
            // Notes (immutable)
            notes: [],
            
            version: 1,
        };
        
        // Freeze incident
        Object.freeze(incident);
        this.incidents.set(incidentId, incident);
        
        this.emit('incident-recorded', {
            incidentId,
            errorType: incident.errorType,
            severity: incident.severity,
        });
        
        return incidentId;
    }
    
    /**
     * Correlate incidents (idempotent, versioned)
     */
    correlateIncidents(incidentId1, incidentId2, correlationToken) {
        // Check idempotency
        if (this.correlationTokens.has(correlationToken)) {
            return this.correlationTokens.get(correlationToken);
        }
        
        const incident1 = this.incidents.get(incidentId1);
        const incident2 = this.incidents.get(incidentId2);
        
        if (!incident1 || !incident2) {
            throw new Error('One or both incidents not found');
        }
        
        const correlationId = `correlation-${crypto.randomBytes(8).toString('hex')}`;
        
        // Create immutable correlation
        const correlation = {
            // Identifiers (immutable)
            correlationId,
            incident1Id: incidentId1,
            incident2Id: incidentId2,
            
            // Correlation reason (immutable)
            reason: 'shared_root_cause',
            confidence: 0.85, // 85% confidence
            
            // Root cause analysis (immutable)
            rootCauseAnalysis: {
                commonPattern: 'database_timeout',
                affectedComponent: 'postgres_pool',
                estimatedImpact: 'high',
            },
            
            // Timing (immutable)
            correlatedAt: new Date().toISOString(),
            timeGap: Math.abs(incident1.timestamp - incident2.timestamp),
            
            // Actions taken (immutable)
            actions: Object.freeze(['alert', 'notify', 'create_incident']),
            
            version: 1,
        };
        
        // Freeze correlation
        Object.freeze(correlation);
        this.correlations.set(correlationId, correlation);
        
        // Store token
        this.correlationTokens.set(correlationToken, correlationId);
        
        this.emit('incidents-correlated', {
            correlationId,
            incident1Id: incidentId1,
            incident2Id: incidentId2,
            confidence: correlation.confidence,
        });
        
        return correlationId;
    }
    
    /**
     * Apply correlation rule to incidents (idempotent)
     */
    applyCorrelationRule(ruleId, incidents, ruleToken) {
        // Check idempotency
        if (this.correlationTokens.has(ruleToken)) {
            return this.correlationTokens.get(ruleToken);
        }
        
        const rule = this.correlationRules.get(ruleId);
        if (!rule || !rule.enabled) {
            throw new Error('Correlation rule not found or disabled');
        }
        
        const matchingIncidents = incidents.filter(i => {
            const incident = this.incidents.get(i);
            return incident && incident.errorType === rule.pattern.errorType;
        });
        
        if (matchingIncidents.length < 2) {
            return null; // No incidents to correlate
        }
        
        // Create parent incident for cluster
        const clusterId = `cluster-${crypto.randomBytes(8).toString('hex')}`;
        
        const parentIncident = {
            // Identifiers (immutable)
            incidentId: clusterId,
            isCluster: true,
            
            // Rule reference (immutable)
            ruleId,
            ruleName: rule.name,
            
            // Cluster information (immutable)
            memberIncidents: Object.freeze([...matchingIncidents]),
            memberCount: matchingIncidents.length,
            
            // Aggregate metrics (immutable)
            aggregateMetrics: Object.freeze({
                totalErrors: matchingIncidents.reduce((sum, id) => {
                    const incident = this.incidents.get(id);
                    return sum + (incident?.metrics?.errorCount || 0);
                }, 0),
                uniqueUsers: matchingIncidents.length * 5, // Simplified
            }),
            
            // Timing (immutable)
            createdAt: new Date().toISOString(),
            
            version: 1,
        };
        
        // Freeze parent
        Object.freeze(parentIncident);
        this.incidents.set(clusterId, parentIncident);
        
        // Store token
        this.correlationTokens.set(ruleToken, clusterId);
        
        this.emit('rule-applied', {
            clusterId,
            ruleId,
            memberCount: matchingIncidents.length,
        });
        
        return clusterId;
    }
    
    /**
     * Get incident correlations (immutable snapshot)
     */
    getIncidentCorrelations(incidentId) {
        const correlations = Array.from(this.correlations.values())
            .filter(c => c.incident1Id === incidentId || c.incident2Id === incidentId);
        
        return Object.freeze(
            correlations.map(c => Object.freeze(c))
        );
    }
    
    /**
     * Query incidents (immutable array)
     */
    queryIncidents(filters = {}) {
        const incidents = Array.from(this.incidents.values());
        
        let filtered = incidents;
        
        // Filter by error type
        if (filters.errorType) {
            filtered = filtered.filter(i => i.errorType === filters.errorType);
        }
        
        // Filter by severity
        if (filters.severity) {
            filtered = filtered.filter(i => i.severity === filters.severity);
        }
        
        // Filter by status
        if (filters.status) {
            filtered = filtered.filter(i => i.status === filters.status);
        }
        
        // Filter by cluster
        if (filters.clustered !== undefined) {
            filtered = filtered.filter(i => (i.isCluster || false) === filters.clustered);
        }
        
        // Sort by timestamp (descending)
        filtered.sort((a, b) => b.timestamp - a.timestamp);
        
        // Limit results
        const limit = filters.limit || 100;
        return Object.freeze(
            filtered.slice(0, limit).map(i => Object.freeze(i))
        );
    }
    
    /**
     * Get correlation statistics (immutable snapshot)
     */
    getCorrelationStatistics() {
        const allIncidents = Array.from(this.incidents.values());
        const allCorrelations = Array.from(this.correlations.values());
        
        const bySeverity = {
            critical: allIncidents.filter(i => i.severity === 'critical').length,
            high: allIncidents.filter(i => i.severity === 'high').length,
            medium: allIncidents.filter(i => i.severity === 'medium').length,
            low: allIncidents.filter(i => i.severity === 'low').length,
        };
        
        const stats = {
            totalIncidents: allIncidents.length,
            openIncidents: allIncidents.filter(i => i.status === 'open').length,
            closedIncidents: allIncidents.filter(i => i.status === 'closed').length,
            clusteredIncidents: allIncidents.filter(i => i.isCluster).length,
            bySeverity,
            totalCorrelations: allCorrelations.length,
            averageConfidence: allCorrelations.length > 0
                ? (allCorrelations.reduce((sum, c) => sum + c.confidence, 0) / allCorrelations.length)
                : 0,
        };
        
        return Object.freeze(stats);
    }
    
    /**
     * Get correlation timeline (immutable snapshot)
     */
    getCorrelationTimeline(timeWindowMinutes = 60) {
        const cutoff = Date.now() - (timeWindowMinutes * 60 * 1000);
        
        const correlations = Array.from(this.correlations.values())
            .filter(c => new Date(c.correlatedAt).getTime() > cutoff)
            .sort((a, b) => new Date(b.correlatedAt).getTime() - new Date(a.correlatedAt).getTime());
        
        return Object.freeze(
            correlations.map(c => Object.freeze(c))
        );
    }
    
    /**
     * Close incident (creates new version)
     */
    closeIncident(incidentId, closureReason) {
        const incident = this.incidents.get(incidentId);
        if (!incident) throw new Error('Incident not found');
        
        // Create new version
        const closedIncident = {
            ...incident,
            status: 'closed',
            closureReason,
            closedAt: new Date().toISOString(),
            version: incident.version + 1,
        };
        
        // Freeze and replace
        Object.freeze(closedIncident);
        this.incidents.set(incidentId, closedIncident);
        
        this.emit('incident-closed', { incidentId, reason: closureReason });
        return closedIncident;
    }
    
    /**
     * Get all correlation rules (immutable array)
     */
    getAllCorrelationRules() {
        return Object.freeze(
            Array.from(this.correlationRules.values())
                .map(r => Object.freeze(r))
        );
    }
}

module.exports = IncidentCorrelationService;
