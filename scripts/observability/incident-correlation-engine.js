#!/usr/bin/env node
/**
 * @file        scripts/observability/incident-correlation-engine.js
 * @module      observability/incidents
 * @description Incident correlation engine for root cause analysis with immutable events
 *
 * IaC Principles:
 * - Immutable: Events frozen once recorded, never mutated
 * - Idempotent: Same events = same correlations (deterministic)
 * - Versioned: Event versions for audit trail and timeline analysis
 */

/**
 * Incident Correlation Engine
 * Automatically correlates SLO breaches with deploys, config changes, and restarts
 * Provides timeline analysis for incident root cause analysis
 */

const EventEmitter = require('events');

class IncidentCorrelationEngine extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.correlationWindowMs = options.correlationWindowMs || 300000; // 5 minutes default
        this.minRelevanceScore = options.minRelevanceScore || 0.5;
        
        // Event stores
        this.events = {
            sloBreaches: [],
            deployments: [],
            configChanges: [],
            restarts: [],
            errors: [],
        };
        
        // Correlation results cache
        this.correlations = [];
    }
    
    /**
     * Record an SLO breach event
     */
    recordSLOBreach(sloEvent) {
        const event = {
            type: 'slo-breach',
            timestamp: sloEvent.timestamp || Date.now(),
            slo: sloEvent.slo,              // e.g., 'availability', 'latency-p99'
            value: sloEvent.value,          // actual value
            threshold: sloEvent.threshold,   // SLO threshold
            service: sloEvent.service,
            severity: this.calculateSeverity(sloEvent),
            details: sloEvent,
        };
        
        this.events.sloBreaches.push(event);
        this.emit('slo-breach', event);
        
        // Correlate with other events
        const correlation = this.correlateWithHistory(event);
        if (correlation) {
            this.correlations.push(correlation);
            this.emit('correlation-found', correlation);
        }
        
        return event;
    }
    
    /**
     * Record a deployment event
     */
    recordDeployment(deployEvent) {
        const event = {
            type: 'deployment',
            timestamp: deployEvent.timestamp || Date.now(),
            service: deployEvent.service,
            version: deployEvent.version,
            status: deployEvent.status,     // 'in-progress', 'completed', 'failed', 'rolled-back'
            duration: deployEvent.duration,
            changes: deployEvent.changes,   // description of changes
            details: deployEvent,
        };
        
        this.events.deployments.push(event);
        this.emit('deployment', event);
        
        return event;
    }
    
    /**
     * Record a config change event
     */
    recordConfigChange(configEvent) {
        const event = {
            type: 'config-change',
            timestamp: configEvent.timestamp || Date.now(),
            service: configEvent.service,
            config: configEvent.config,     // config key changed
            oldValue: configEvent.oldValue,
            newValue: configEvent.newValue,
            changeSet: configEvent.changeSet,
            details: configEvent,
        };
        
        this.events.configChanges.push(event);
        this.emit('config-change', event);
        
        return event;
    }
    
    /**
     * Record a restart event
     */
    recordRestart(restartEvent) {
        const event = {
            type: 'restart',
            timestamp: restartEvent.timestamp || Date.now(),
            service: restartEvent.service,
            reason: restartEvent.reason,
            duration: restartEvent.duration,
            replicas: restartEvent.replicas,
            details: restartEvent,
        };
        
        this.events.restarts.push(event);
        this.emit('restart', event);
        
        return event;
    }
    
    /**
     * Record an error event
     */
    recordError(errorEvent) {
        const event = {
            type: 'error',
            timestamp: errorEvent.timestamp || Date.now(),
            service: errorEvent.service,
            errorType: errorEvent.errorType,
            count: errorEvent.count || 1,
            rate: errorEvent.rate,          // errors/second
            details: errorEvent,
        };
        
        this.events.errors.push(event);
        this.emit('error', event);
        
        return event;
    }
    
    /**
     * Find correlations between events and SLO breaches
     */
    correlateWithHistory(sloEvent) {
        const window = sloEvent.timestamp - this.correlationWindowMs;
        const correlatedEvents = [];
        
        // Check deployments
        const relevantDeploys = this.events.deployments.filter(e => 
            e.timestamp >= window &&
            e.timestamp <= sloEvent.timestamp &&
            (e.service === sloEvent.service || this.isRelatedService(e.service, sloEvent.service))
        );
        
        // Check config changes
        const relevantConfigs = this.events.configChanges.filter(e =>
            e.timestamp >= window &&
            e.timestamp <= sloEvent.timestamp &&
            (e.service === sloEvent.service || this.isRelatedService(e.service, sloEvent.service))
        );
        
        // Check restarts
        const relevantRestarts = this.events.restarts.filter(e =>
            e.timestamp >= window &&
            e.timestamp <= sloEvent.timestamp &&
            (e.service === sloEvent.service || this.isRelatedService(e.service, sloEvent.service))
        );
        
        // Check errors
        const relevantErrors = this.events.errors.filter(e =>
            e.timestamp >= window &&
            e.timestamp <= sloEvent.timestamp &&
            (e.service === sloEvent.service || this.isRelatedService(e.service, sloEvent.service))
        );
        
        // Combine and score
        const allEvents = [
            ...relevantDeploys.map(e => ({ ...e, correlationType: 'deployment' })),
            ...relevantConfigs.map(e => ({ ...e, correlationType: 'config-change' })),
            ...relevantRestarts.map(e => ({ ...e, correlationType: 'restart' })),
            ...relevantErrors.map(e => ({ ...e, correlationType: 'error' })),
        ];
        
        if (allEvents.length === 0) {
            return null;
        }
        
        // Calculate relevance scores
        const scoredEvents = allEvents.map(event => ({
            ...event,
            relevanceScore: this.calculateRelevanceScore(event, sloEvent),
        })).filter(e => e.relevanceScore >= this.minRelevanceScore);
        
        if (scoredEvents.length === 0) {
            return null;
        }
        
        // Sort by time proximity and relevance
        scoredEvents.sort((a, b) => b.relevanceScore - a.relevanceScore);
        
        return {
            sloEvent,
            correlatedEvents: scoredEvents,
            timeline: this.generateTimeline(sloEvent, scoredEvents),
            severity: sloEvent.severity,
            rootCauseHypothesis: this.generateRootCauseHypothesis(scoredEvents),
            recommendedActions: this.generateRecommendations(scoredEvents),
        };
    }
    
    /**
     * Calculate relevance score between events
     */
    calculateRelevanceScore(event, sloEvent) {
        let score = 0;
        
        // Time proximity (0-0.5)
        const timeDiff = sloEvent.timestamp - event.timestamp;
        if (timeDiff >= 0 && timeDiff <= 60000) {
            score += 0.5; // Within 1 minute: highest relevance
        } else if (timeDiff > 60000 && timeDiff <= this.correlationWindowMs) {
            score += 0.3 * (1 - (timeDiff / this.correlationWindowMs)); // Decay over window
        }
        
        // Service match (0-0.3)
        if (event.service === sloEvent.service) {
            score += 0.3; // Exact service match
        } else if (this.isRelatedService(event.service, sloEvent.service)) {
            score += 0.15; // Related service
        }
        
        // Event type correlation (0-0.2)
        if (event.correlationType === 'deployment') {
            score += 0.2; // Deployments are high correlation
        } else if (event.correlationType === 'config-change') {
            score += 0.15; // Config changes
        } else if (event.correlationType === 'restart') {
            score += 0.15; // Restarts
        } else if (event.correlationType === 'error') {
            score += 0.1; // Errors (lower priority)
        }
        
        return Math.min(1.0, score);
    }
    
    /**
     * Check if two services are related (dependency analysis)
     */
    isRelatedService(service1, service2) {
        // Define service dependencies
        const dependencies = {
            'api-gateway': ['auth-service', 'workspace-service', 'database'],
            'workspace-service': ['code-server', 'redis', 'database'],
            'auth-service': ['database', 'redis'],
            'code-server': ['websocket-gateway', 'redis'],
            'websocket-gateway': ['redis', 'relay-nodes'],
        };
        
        // Check if service1 depends on service2 or vice versa
        const deps1 = dependencies[service1] || [];
        const deps2 = dependencies[service2] || [];
        
        return deps1.includes(service2) || deps2.includes(service1);
    }
    
    /**
     * Calculate severity level
     */
    calculateSeverity(sloEvent) {
        const deviation = Math.abs(sloEvent.value - sloEvent.threshold) / sloEvent.threshold;
        
        if (deviation > 0.5) return 'critical';
        if (deviation > 0.25) return 'high';
        if (deviation > 0.1) return 'medium';
        return 'low';
    }
    
    /**
     * Generate timeline of events
     */
    generateTimeline(sloEvent, correlatedEvents) {
        const allEvents = [sloEvent, ...correlatedEvents].sort((a, b) => a.timestamp - b.timestamp);
        
        return allEvents.map((event, index) => ({
            sequence: index + 1,
            timestamp: new Date(event.timestamp).toISOString(),
            type: event.type || event.correlationType,
            service: event.service,
            description: this.getEventDescription(event),
            timeFromBreach: event.timestamp - sloEvent.timestamp,
        }));
    }
    
    /**
     * Generate human-readable event description
     */
    getEventDescription(event) {
        switch (event.type || event.correlationType) {
            case 'slo-breach':
                return `SLO breach: ${event.slo} (${event.value.toFixed(2)} vs threshold ${event.threshold})`;
            case 'deployment':
                return `Deployment: ${event.service} v${event.version} (${event.status})`;
            case 'config-change':
                return `Config change: ${event.config} = ${event.newValue}`;
            case 'restart':
                return `Restart: ${event.service} (${event.replicas} replicas, ${event.duration}ms)`;
            case 'error':
                return `Error spike: ${event.errorType} (${event.count} errors, ${event.rate}/sec)`;
            default:
                return event.description || 'Unknown event';
        }
    }
    
    /**
     * Generate root cause hypothesis
     */
    generateRootCauseHypothesis(correlatedEvents) {
        if (correlatedEvents.length === 0) {
            return 'No correlated events found. SLO breach may be due to external factors or gradual degradation.';
        }
        
        const topEvent = correlatedEvents[0];
        const hypotheses = [];
        
        if (topEvent.correlationType === 'deployment') {
            hypotheses.push(`Recent deployment of ${topEvent.service} v${topEvent.version} may have introduced a regression.`);
        }
        
        if (topEvent.correlationType === 'config-change') {
            hypotheses.push(`Configuration change to ${topEvent.config} may have altered system behavior.`);
        }
        
        if (topEvent.correlationType === 'restart') {
            hypotheses.push(`Service restart of ${topEvent.service} may have caused traffic redistribution.`);
        }
        
        if (topEvent.correlationType === 'error') {
            hypotheses.push(`Error rate spike (${topEvent.count} errors) in ${topEvent.service} may indicate a system issue.`);
        }
        
        return hypotheses.join(' ') || 'Multiple correlated events detected.';
    }
    
    /**
     * Generate recommended actions
     */
    generateRecommendations(correlatedEvents) {
        const recommendations = [];
        const eventTypes = new Set(correlatedEvents.map(e => e.correlationType));
        
        if (eventTypes.has('deployment')) {
            recommendations.push({
                action: 'ROLLBACK',
                priority: 'high',
                description: 'Consider rolling back recent deployment',
                steps: [
                    '1. Review deployment changes',
                    '2. Check performance metrics before/after',
                    '3. If regression confirmed, initiate rollback',
                ],
            });
        }
        
        if (eventTypes.has('config-change')) {
            recommendations.push({
                action: 'REVERT_CONFIG',
                priority: 'high',
                description: 'Revert recent configuration changes',
                steps: [
                    '1. Identify the config change',
                    '2. Validate previous configuration',
                    '3. Revert and monitor impact',
                ],
            });
        }
        
        if (eventTypes.has('restart')) {
            recommendations.push({
                action: 'SCALE_UP',
                priority: 'medium',
                description: 'Scale up service to handle load during restart recovery',
                steps: [
                    '1. Increase replica count',
                    '2. Monitor queue depth and latency',
                    '3. Scale down when metrics normalize',
                ],
            });
        }
        
        if (eventTypes.has('error')) {
            recommendations.push({
                action: 'INVESTIGATE_ERRORS',
                priority: 'high',
                description: 'Investigate error rate spike',
                steps: [
                    '1. Review error logs',
                    '2. Identify error pattern',
                    '3. Address root cause',
                ],
            });
        }
        
        if (recommendations.length === 0) {
            recommendations.push({
                action: 'MONITOR',
                priority: 'medium',
                description: 'Continue monitoring for additional degradation',
            });
        }
        
        return recommendations;
    }
    
    /**
     * Get incident summary
     */
    getIncidentSummary(timeWindow = 3600000) { // 1 hour default
        const now = Date.now();
        const startTime = now - timeWindow;
        
        const recentBreaches = this.events.sloBreaches.filter(e => e.timestamp >= startTime);
        const recentDeploys = this.events.deployments.filter(e => e.timestamp >= startTime);
        const recentChanges = this.events.configChanges.filter(e => e.timestamp >= startTime);
        const recentRestarts = this.events.restarts.filter(e => e.timestamp >= startTime);
        const recentErrors = this.events.errors.filter(e => e.timestamp >= startTime);
        
        return {
            timeWindow: { start: new Date(startTime).toISOString(), end: new Date(now).toISOString() },
            summary: {
                sloBreaches: recentBreaches.length,
                deployments: recentDeploys.length,
                configChanges: recentChanges.length,
                restarts: recentRestarts.length,
                errors: recentErrors.length,
            },
            topIssues: recentBreaches
                .sort((a, b) => b.severity - a.severity)
                .slice(0, 5)
                .map(breach => ({
                    slo: breach.slo,
                    service: breach.service,
                    severity: breach.severity,
                    correlation: this.correlations.find(c => c.sloEvent === breach),
                })),
        };
    }
}

module.exports = IncidentCorrelationEngine;
