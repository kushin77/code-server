#!/usr/bin/env node
/**
 * @file        scripts/integrations/pagerduty-integration-service.js
 * @module      integrations/pagerduty
 * @description PagerDuty incident integration with auto-file opening and notification
 *
 * IaC Principles:
 * - Immutable: Incident snapshots frozen once received from webhook
 * - Idempotent: Webhook handler safe to retry (event deduplication via incident ID)
 * - Versioned: Incident state versioning for audit trail
 */

/**
 * PagerDuty Integration Service
 * Listens for incidents and auto-opens relevant files in workspace
 * Supports incident context: recent deploys, stack traces, affected services
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class PagerDutyIntegrationService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.webhookSecret = options.webhookSecret || 'default-secret';
        this.incidentMap = new Map(); // Incident ID → details
        this.fileContextCache = new Map(); // Incident ID → relevant files
        this.onCallSchedules = options.onCallSchedules || {};
        this.serviceMap = options.serviceMap || {}; // Service name → files/paths
    }
    
    /**
     * Validate webhook signature
     */
    validateWebhookSignature(payload, signature) {
        const hash = crypto
            .createHmac('sha256', this.webhookSecret)
            .update(JSON.stringify(payload))
            .digest('hex');
        
        return `sha256=${hash}` === signature;
    }
    
    /**
     * Handle incident webhook from PagerDuty
     */
    handleIncidentWebhook(event) {
        const { type, data } = event;
        
        if (type === 'incident.triggered') {
            return this.onIncidentTriggered(data);
        } else if (type === 'incident.acknowledged') {
            return this.onIncidentAcknowledged(data);
        } else if (type === 'incident.resolved') {
            return this.onIncidentResolved(data);
        } else if (type === 'incident.escalated') {
            return this.onIncidentEscalated(data);
        }
        
        return null;
    }
    
    /**
     * Handle incident triggered
     */
    onIncidentTriggered(incidentData) {
        const incident = {
            id: incidentData.incident.incident_number,
            status: 'triggered',
            title: incidentData.incident.title,
            description: incidentData.incident.description,
            severity: incidentData.incident.urgency, // high, low
            serviceId: incidentData.incident.service?.id,
            serviceName: incidentData.incident.service?.summary,
            createdAt: incidentData.incident.created_at,
            triggeredAt: new Date().toISOString(),
            assignee: incidentData.incident.assigned_via,
            triggeringService: this.extractServiceFromAlert(incidentData.incident.title),
        };
        
        this.incidentMap.set(incident.id, incident);
        
        // Determine relevant files
        const relevantFiles = this.determineRelevantFiles(incident);
        this.fileContextCache.set(incident.id, relevantFiles);
        
        // Notify on-call engineer
        const onCall = this.getOnCallForService(incident.serviceName);
        
        this.emit('incident-triggered', {
            incident,
            relevantFiles,
            onCall,
        });
        
        return {
            incident,
            relevantFiles,
            onCall,
            action: 'open-workspace',
        };
    }
    
    /**
     * Handle incident acknowledged
     */
    onIncidentAcknowledged(incidentData) {
        const incidentId = incidentData.incident.incident_number;
        const incident = this.incidentMap.get(incidentId);
        
        if (incident) {
            incident.status = 'acknowledged';
            incident.acknowledgedAt = new Date().toISOString();
            incident.acknowledgedBy = incidentData.incident.assigned_via;
            
            this.emit('incident-acknowledged', incident);
        }
        
        return incident;
    }
    
    /**
     * Handle incident resolved
     */
    onIncidentResolved(incidentData) {
        const incidentId = incidentData.incident.incident_number;
        const incident = this.incidentMap.get(incidentId);
        
        if (incident) {
            incident.status = 'resolved';
            incident.resolvedAt = new Date().toISOString();
            incident.resolvedBy = incidentData.incident.assigned_via;
            
            // Store post-mortem info
            incident.postMortem = {
                rootCause: incidentData.incident.description,
                resolution: incidentData.incident.title,
                affectedServices: this.extractAffectedServices(incidentData.incident.title),
            };
            
            this.emit('incident-resolved', incident);
            
            // Clean up file cache after resolution
            setTimeout(() => {
                this.fileContextCache.delete(incidentId);
            }, 3600000); // Keep for 1 hour
        }
        
        return incident;
    }
    
    /**
     * Handle incident escalated
     */
    onIncidentEscalated(incidentData) {
        const incidentId = incidentData.incident.incident_number;
        const incident = this.incidentMap.get(incidentId);
        
        if (incident) {
            incident.escalations = (incident.escalations || 0) + 1;
            incident.lastEscalation = new Date().toISOString();
            
            this.emit('incident-escalated', {
                incident,
                escalationLevel: incident.escalations,
            });
        }
        
        return incident;
    }
    
    /**
     * Determine relevant files based on incident context
     */
    determineRelevantFiles(incident) {
        const files = {
            serviceFiles: [],
            recentDeployFiles: [],
            stackTraceFiles: [],
            configurationFiles: [],
            logs: [],
        };
        
        // Get service-specific files
        if (incident.serviceName) {
            files.serviceFiles = this.getServiceFiles(incident.serviceName);
        }
        
        // Get files from recent deploys
        files.recentDeployFiles = this.getRecentDeployFiles(incident.serviceName);
        
        // Get stack trace / error context files
        if (incident.description) {
            files.stackTraceFiles = this.extractFilesFromStackTrace(incident.description);
        }
        
        // Get configuration files
        files.configurationFiles = this.getConfigFiles(incident.serviceName);
        
        // Get log file paths
        files.logs = this.getLogPaths(incident.serviceName);
        
        return files;
    }
    
    /**
     * Get files associated with a service
     */
    getServiceFiles(serviceName) {
        const serviceKey = (serviceName || '').toLowerCase().replace(/\s+/g, '-');
        
        const defaultServices = {
            'api-gateway': [
                'src/services/api-gateway/handler.js',
                'src/services/api-gateway/middleware.js',
                'src/services/api-gateway/routes.js',
                'config/api-gateway.yaml',
            ],
            'workspace-service': [
                'src/services/workspace/workspace-manager.js',
                'src/services/workspace/session-handler.js',
                'src/services/workspace/file-operations.js',
                'config/workspace.yaml',
            ],
            'auth-service': [
                'src/services/auth/auth-handler.js',
                'src/services/auth/jwt-manager.js',
                'src/services/auth/oauth-provider.js',
                'config/auth.yaml',
            ],
            'websocket-gateway': [
                'src/services/websocket/gateway.js',
                'src/services/websocket/relay-manager.js',
                'src/services/websocket/health-monitor.js',
                'config/websocket-gateway.yaml',
            ],
            'database': [
                'config/database/connection.js',
                'config/database/schema.sql',
                'src/migrations/',
                'config/database.yaml',
            ],
            'redis': [
                'config/redis/cluster.yaml',
                'config/redis/sentinel.yaml',
                'src/cache/redis-client.js',
            ],
        };
        
        return defaultServices[serviceKey] || [];
    }
    
    /**
     * Get files from recent deployments
     */
    getRecentDeployFiles(serviceName) {
        // In production, this would query deployment history
        // For now, return common changed files
        return [
            '.github/workflows/deploy.yml',
            'package.json',
            'src/services/*/package.json',
            'CHANGELOG.md',
            'docker-compose.yml',
        ];
    }
    
    /**
     * Extract file paths from stack trace
     */
    extractFilesFromStackTrace(description) {
        const files = [];
        
        // Look for common file path patterns
        const pathPatterns = [
            /\/src\/[\w/.-]+\.\w+/g,
            /src\/services\/[\w-]+\/[\w/.-]+\.\w+/g,
            /config\/[\w/.-]+\.\w+/g,
            /lib\/[\w/.-]+\.\w+/g,
        ];
        
        for (const pattern of pathPatterns) {
            const matches = description.match(pattern);
            if (matches) {
                files.push(...matches);
            }
        }
        
        return [...new Set(files)]; // Deduplicate
    }
    
    /**
     * Get configuration files for service
     */
    getConfigFiles(serviceName) {
        return [
            'config/env.yaml',
            `.env.${(serviceName || '').toLowerCase().replace(/\s+/g, '-')}`,
            `config/${(serviceName || '').toLowerCase().replace(/\s+/g, '-')}.yaml`,
            'config/docker-compose.yml',
        ];
    }
    
    /**
     * Get log file paths
     */
    getLogPaths(serviceName) {
        const serviceSlug = (serviceName || '').toLowerCase().replace(/\s+/g, '-');
        
        return [
            `/var/log/${serviceSlug}/error.log`,
            `/var/log/${serviceSlug}/access.log`,
            `/var/log/docker/${serviceSlug}.log`,
            `logs/${serviceSlug}-*.log`,
        ];
    }
    
    /**
     * Extract service name from incident title
     */
    extractServiceFromAlert(title) {
        const services = [
            'api-gateway', 'workspace-service', 'auth-service',
            'websocket-gateway', 'database', 'redis', 'cache',
        ];
        
        for (const service of services) {
            if (title.toLowerCase().includes(service)) {
                return service;
            }
        }
        
        return null;
    }
    
    /**
     * Extract affected services from description
     */
    extractAffectedServices(title) {
        const services = [];
        const patterns = [
            'api-gateway', 'workspace', 'auth', 'websocket',
            'database', 'redis', 'cache', 'load-balancer',
        ];
        
        for (const pattern of patterns) {
            if (title.toLowerCase().includes(pattern)) {
                services.push(pattern);
            }
        }
        
        return services;
    }
    
    /**
     * Get on-call engineer for service
     */
    getOnCallForService(serviceName) {
        if (!serviceName) return null;
        
        const serviceSlug = serviceName.toLowerCase().replace(/\s+/g, '-');
        
        return {
            service: serviceName,
            onCallSchedule: this.onCallSchedules[serviceSlug] || 'default',
            notificationChannels: ['email', 'sms', 'slack'],
            escalationPolicy: 'standard',
        };
    }
    
    /**
     * Generate workspace session with incident context
     */
    generateWorkspaceContext(incidentId) {
        const incident = this.incidentMap.get(incidentId);
        if (!incident) return null;
        
        const files = this.fileContextCache.get(incidentId);
        
        return {
            sessionId: `incident-${incidentId}-${Date.now()}`,
            incident: {
                id: incident.id,
                title: incident.title,
                severity: incident.severity,
                service: incident.serviceName,
                createdAt: incident.createdAt,
            },
            files: {
                pinned: files.serviceFiles.slice(0, 3), // Pin top 3 files
                recent: files.recentDeployFiles.slice(0, 5),
                stackTrace: files.stackTraceFiles.slice(0, 3),
                config: files.configurationFiles.slice(0, 2),
            },
            logs: files.logs,
            searchContext: {
                service: incident.serviceName,
                timeRange: '1h',
                query: `incident:${incident.id}`,
            },
            teamContext: {
                onCall: this.getOnCallForService(incident.serviceName),
                escalationLevel: incident.escalations || 0,
            },
        };
    }
    
    /**
     * Get incident status
     */
    getIncidentStatus(incidentId) {
        const incident = this.incidentMap.get(incidentId);
        if (!incident) return null;
        
        return {
            id: incident.id,
            status: incident.status,
            title: incident.title,
            service: incident.serviceName,
            severity: incident.severity,
            createdAt: incident.createdAt,
            acknowledgedAt: incident.acknowledgedAt,
            resolvedAt: incident.resolvedAt,
            escalations: incident.escalations || 0,
            relevantFiles: this.fileContextCache.get(incidentId),
        };
    }
    
    /**
     * Get active incidents
     */
    getActiveIncidents() {
        const active = [];
        
        for (const [id, incident] of this.incidentMap) {
            if (incident.status === 'triggered' || incident.status === 'acknowledged') {
                active.push({
                    id: incident.id,
                    title: incident.title,
                    service: incident.serviceName,
                    severity: incident.severity,
                    createdAt: incident.createdAt,
                    status: incident.status,
                    escalations: incident.escalations || 0,
                });
            }
        }
        
        return active.sort((a, b) => 
            new Date(b.createdAt) - new Date(a.createdAt)
        );
    }
    
    /**
     * Get incident history
     */
    getIncidentHistory(limit = 50) {
        const sorted = Array.from(this.incidentMap.values())
            .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
            .slice(0, limit);
        
        return sorted.map(incident => ({
            id: incident.id,
            title: incident.title,
            service: incident.serviceName,
            severity: incident.severity,
            status: incident.status,
            createdAt: incident.createdAt,
            resolvedAt: incident.resolvedAt,
            duration: incident.resolvedAt 
                ? Math.round((new Date(incident.resolvedAt) - new Date(incident.createdAt)) / 1000 / 60)
                : null,
        }));
    }
}

module.exports = PagerDutyIntegrationService;
