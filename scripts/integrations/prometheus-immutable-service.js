#!/usr/bin/env node
/**
 * @file        scripts/integrations/prometheus-immutable-service.js
 * @module      integrations/prometheus
 * @description Prometheus metrics with immutable scrape configs and idempotent registration
 *
 * IaC Principles:
 * - Immutable: Scrape configurations frozen once created
 * - Immutable: Recording rules and alert rules frozen
 * - Idempotent: Same registrationToken = same target registration
 * - Versioned: Configuration versions for rollback
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class PrometheusIntegrationService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.baseUrl = options.baseUrl || process.env.PROMETHEUS_URL || 'http://localhost:9090';
        
        // Immutable scrape configs (frozen)
        this.scrapeConfigs = new Map(); // configId → frozen config
        
        // Immutable targets (frozen)
        this.targets = new Map(); // targetId → frozen target
        
        // Token to targetId mapping (idempotency)
        this.registrationTokens = new Map(); // token → targetId
        
        // Immutable recording rules (frozen)
        this.recordingRules = new Map(); // ruleId → frozen rule
        
        // Immutable alert rules (frozen)
        this.alertRules = new Map(); // alertId → frozen alert
        
        // Registration history
        this.registrationHistory = [];
    }
    
    /**
     * Create scrape config (immutable)
     */
    createScrapeConfig(configData) {
        const configId = `scrape-${crypto.randomBytes(8).toString('hex')}`;
        
        const config = {
            // Identifiers (immutable)
            configId,
            jobName: configData.jobName,
            
            // Scrape settings (immutable)
            scrapeInterval: configData.scrapeInterval || '15s',
            scrapeTimeout: configData.scrapeTimeout || '10s',
            metricsPath: configData.metricsPath || '/metrics',
            
            // Scheme (immutable)
            scheme: configData.scheme || 'http',
            
            // Basic auth (immutable, if provided)
            basicAuth: configData.basicAuth ? Object.freeze({
                username: configData.basicAuth.username,
                password: dataData.basicAuth.password,
            }) : null,
            
            // Relabeling (immutable)
            relabelConfigs: Object.freeze((configData.relabelConfigs || []).map(r =>
                Object.freeze({
                    sourceLabels: r.sourceLabels,
                    targetLabel: r.targetLabel,
                    replacement: r.replacement,
                    action: r.action || 'replace',
                })
            )),
            
            // Service discovery (immutable)
            serviceDiscovery: configData.serviceDiscovery ? Object.freeze({
                type: configData.serviceDiscovery.type,  // static, consul, kubernetes, etc.
                config: Object.freeze(configData.serviceDiscovery.config || {}),
            }) : null,
            
            // Timing (immutable)
            createdAt: new Date().toISOString(),
            createdAtMs: Date.now(),
            
            // Status (mutable)
            enabled: true,
            registered: false,
            registeredAt: null,
            
            version: 1,
        };
        
        Object.freeze(config);
        this.scrapeConfigs.set(configId, config);
        
        this.emit('scrape-config-created', {
            configId,
            jobName: config.jobName,
            interval: config.scrapeInterval,
        });
        
        return configId;
    }
    
    /**
     * Register target (idempotent)
     */
    registerTarget(targetData, registrationToken) {
        // Idempotency check
        if (registrationToken && this.registrationTokens.has(registrationToken)) {
            return this.registrationTokens.get(registrationToken);
        }
        
        const targetId = `target-${crypto.randomBytes(8).toString('hex')}`;
        
        const target = {
            // Identifiers (immutable)
            targetId,
            jobName: targetData.jobName,
            
            // Address (immutable)
            host: targetData.host,
            port: targetData.port,
            scheme: targetData.scheme || 'http',
            
            // Labels (immutable)
            labels: Object.freeze(targetData.labels || {}),
            
            // Health check (immutable config)
            healthCheckInterval: targetData.healthCheckInterval || '30s',
            
            // Timing (immutable)
            registeredAt: new Date().toISOString(),
            registeredAtMs: Date.now(),
            lastScrapeAt: null,
            lastScrapeDurationMs: null,
            
            // Status (mutable)
            status: 'up',  // up, down, unknown
            lastError: null,
            scrapeCount: 0,
            
            version: 1,
        };
        
        Object.freeze(target);
        this.targets.set(targetId, target);
        
        if (registrationToken) {
            this.registrationTokens.set(registrationToken, targetId);
        }
        
        this.recordRegistrationHistory(targetId, 'registered');
        
        this.emit('target-registered', {
            targetId,
            jobName: target.jobName,
            address: `${target.scheme}://${target.host}:${target.port}`,
        });
        
        return targetId;
    }
    
    /**
     * Record scrape result (creates new target version)
     */
    recordScrapeResult(targetId, scrapeData) {
        const target = this.targets.get(targetId);
        if (!target) throw new Error(`Target ${targetId} not found`);
        
        const updated = {
            ...target,
            lastScrapeAt: new Date().toISOString(),
            lastScrapeDurationMs: scrapeData.durationMs,
            status: scrapeData.success ? 'up' : 'down',
            lastError: scrapeData.error || null,
            scrapeCount: target.scrapeCount + 1,
            version: target.version + 1,
        };
        
        Object.freeze(updated);
        this.targets.set(targetId, updated);
        
        this.emit('scrape-result', {
            targetId,
            status: updated.status,
            durationMs: scrapeData.durationMs,
        });
    }
    
    /**
     * Create recording rule (immutable)
     */
    createRecordingRule(ruleData) {
        const ruleId = `rule-${crypto.randomBytes(8).toString('hex')}`;
        
        const rule = {
            // Identifiers (immutable)
            ruleId,
            recordName: ruleData.recordName,
            
            // Rule definition (immutable)
            expr: ruleData.expr,
            interval: ruleData.interval || '15s',
            
            // Labels (immutable)
            labels: Object.freeze(ruleData.labels || {}),
            
            // Timing (immutable)
            createdAt: new Date().toISOString(),
            createdAtMs: Date.now(),
            
            // Status (mutable)
            enabled: true,
            
            version: 1,
        };
        
        Object.freeze(rule);
        this.recordingRules.set(ruleId, rule);
        
        this.emit('recording-rule-created', {
            ruleId,
            recordName: rule.recordName,
            expr: rule.expr,
        });
        
        return ruleId;
    }
    
    /**
     * Create alert rule (immutable)
     */
    createAlertRule(alertData) {
        const alertId = `alert-${crypto.randomBytes(8).toString('hex')}`;
        
        const alert = {
            // Identifiers (immutable)
            alertId,
            name: alertData.name,
            
            // Alert definition (immutable)
            expr: alertData.expr,
            forDuration: alertData.forDuration || '5m',
            
            // Annotations (immutable)
            annotations: Object.freeze(alertData.annotations || {}),
            
            // Labels (immutable)
            labels: Object.freeze(alertData.labels || {}),
            
            // Timing (immutable)
            createdAt: new Date().toISOString(),
            createdAtMs: Date.now(),
            
            // Status (mutable)
            enabled: true,
            
            version: 1,
        };
        
        Object.freeze(alert);
        this.alertRules.set(alertId, alert);
        
        this.emit('alert-rule-created', {
            alertId,
            name: alert.name,
            expr: alert.expr,
        });
        
        return alertId;
    }
    
    /**
     * Get target (immutable snapshot)
     */
    getTarget(targetId) {
        const target = this.targets.get(targetId);
        return target ? Object.freeze({ ...target }) : null;
    }
    
    /**
     * Query targets (immutable array)
     */
    queryTargets(filters = {}) {
        let targets = Array.from(this.targets.values());
        
        if (filters.jobName) {
            targets = targets.filter(t => t.jobName === filters.jobName);
        }
        
        if (filters.status) {
            targets = targets.filter(t => t.status === filters.status);
        }
        
        targets.sort((a, b) => b.registeredAtMs - a.registeredAtMs);
        
        const limit = filters.limit || 100;
        return Object.freeze(
            targets.slice(0, limit).map(t => Object.freeze(t))
        );
    }
    
    /**
     * Get statistics (immutable)
     */
    getStatistics() {
        const allTargets = Array.from(this.targets.values());
        
        const stats = {
            totalConfigs: this.scrapeConfigs.size,
            enabledConfigs: Array.from(this.scrapeConfigs.values()).filter(c => c.enabled).length,
            
            totalTargets: allTargets.length,
            activeTargets: allTargets.filter(t => t.status === 'up').length,
            inactiveTargets: allTargets.filter(t => t.status === 'down').length,
            unknownTargets: allTargets.filter(t => t.status === 'unknown').length,
            
            totalRecordingRules: this.recordingRules.size,
            enabledRecordingRules: Array.from(this.recordingRules.values()).filter(r => r.enabled).length,
            
            totalAlertRules: this.alertRules.size,
            enabledAlertRules: Array.from(this.alertRules.values()).filter(a => a.enabled).length,
            
            avgScrapeIntervalMs: allTargets.length > 0
                ? (allTargets.reduce((sum, t) => sum + (t.lastScrapeDurationMs || 0), 0) / allTargets.length).toFixed(2)
                : 0,
        };
        
        return Object.freeze(stats);
    }
    
    /**
     * Record registration history
     */
    recordRegistrationHistory(targetId, action) {
        const target = this.targets.get(targetId);
        
        const record = Object.freeze({
            timestamp: new Date().toISOString(),
            timestampMs: Date.now(),
            action,
            targetId,
            jobName: target.jobName,
            status: target.status,
        });
        
        this.registrationHistory.push(record);
    }
}

module.exports = PrometheusIntegrationService;
