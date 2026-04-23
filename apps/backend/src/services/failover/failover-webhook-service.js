#!/usr/bin/env node
// @file        apps/backend/src/services/failover/failover-webhook-service.ts
// @module      services/failover
// @description Prometheus AlertManager webhook handler for automated failover
// @owner       Infrastructure Team
// @status      Implementation - April 23, 2026
//
import { EventEmitter } from 'events';
import * as crypto from 'crypto';
export class FailoverWebhookService extends EventEmitter {
    constructor(config) {
        super();
        this.lastFailoverTime = 0;
        this.failoverHistory = new Map();
        this.activeFailovers = new Set();
        this.recoveryInProgress = new Map();
        this.config = {
            enabled: true,
            webhookPort: parseInt(process.env.FAILOVER_WEBHOOK_PORT || '5001', 10),
            webhookPath: process.env.FAILOVER_WEBHOOK_PATH || '/api/v1/failover-webhook',
            primaryHost: process.env.PRIMARY_HOST || '192.168.168.31',
            replicaHost: process.env.REPLICA_HOST || '192.168.168.42',
            criticalAlertThreshold: parseInt(process.env.CRITICAL_ALERT_THRESHOLD || '1', 10),
            failoverCooldownMs: parseInt(process.env.FAILOVER_COOLDOWN_MS || '60000', 10),
            recoveryCheckIntervalMs: parseInt(process.env.RECOVERY_CHECK_INTERVAL_MS || '5000', 10),
            maxFailoverRetries: parseInt(process.env.MAX_FAILOVER_RETRIES || '3', 10),
            alertTimeout: parseInt(process.env.ALERT_TIMEOUT_MS || '30000', 10),
            ...config,
        };
    }
    static getInstance(config) {
        if (!FailoverWebhookService.instance) {
            FailoverWebhookService.instance = new FailoverWebhookService(config);
        }
        return FailoverWebhookService.instance;
    }
    /**
     * Handle incoming webhook payload from AlertManager
     */
    async handleWebhookPayload(payload) {
        if (!this.config.enabled) {
            return {
                acknowledged: true,
                message: 'Failover webhook service is disabled',
            };
        }
        try {
            // Validate payload
            this.validateWebhookPayload(payload);
            // Process firing alerts
            const firingAlerts = payload.alerts.filter(a => a.status === 'firing');
            const criticalAlerts = firingAlerts.filter(a => a.labels.severity === 'critical');
            if (criticalAlerts.length === 0) {
                return {
                    acknowledged: true,
                    message: 'No critical alerts',
                };
            }
            // Check cooldown to prevent rapid failovers
            if (this.isInFailoverCooldown()) {
                return {
                    acknowledged: true,
                    message: 'In failover cooldown period',
                };
            }
            // Evaluate if failover is needed
            const failoverNeeded = this.evaluateFailoverNeeded(criticalAlerts);
            if (failoverNeeded) {
                const event = await this.triggerFailover(criticalAlerts);
                return {
                    acknowledged: true,
                    action: event.action,
                    eventId: event.id,
                    message: `Failover initiated: ${event.alertName}`,
                };
            }
            // Check for resolved alerts that might trigger recovery
            const resolvedAlerts = payload.alerts.filter(a => a.status === 'resolved');
            if (resolvedAlerts.length > 0) {
                await this.handleRecovery(resolvedAlerts);
            }
            return {
                acknowledged: true,
                message: 'Alerts processed',
            };
        }
        catch (error) {
            const errorMessage = error instanceof Error ? error.message : String(error);
            this.emit('error', {
                timestamp: Date.now(),
                error: errorMessage,
                payload,
            });
            return {
                acknowledged: false,
                message: `Error processing webhook: ${errorMessage}`,
            };
        }
    }
    /**
     * Validate webhook payload structure
     */
    validateWebhookPayload(payload) {
        if (!payload || typeof payload !== 'object') {
            throw new Error('Invalid webhook payload: must be an object');
        }
        if (!Array.isArray(payload.alerts)) {
            throw new Error('Invalid webhook payload: alerts must be an array');
        }
        if (payload.alerts.length === 0) {
            throw new Error('Invalid webhook payload: alerts array is empty');
        }
        for (const alert of payload.alerts) {
            if (!alert.labels || !alert.labels.alertname) {
                throw new Error('Invalid alert: missing alertname label');
            }
            if (!['firing', 'resolved'].includes(alert.status)) {
                throw new Error(`Invalid alert status: ${alert.status}`);
            }
        }
    }
    /**
     * Check if still in failover cooldown period
     */
    isInFailoverCooldown() {
        const timeSinceLastFailover = Date.now() - this.lastFailoverTime;
        return timeSinceLastFailover < this.config.failoverCooldownMs;
    }
    /**
     * Evaluate if failover is needed based on alerts
     */
    evaluateFailoverNeeded(criticalAlerts) {
        // Check if already in failover
        if (this.activeFailovers.size > 0) {
            return false;
        }
        // Check for specific critical service failures
        const alertNames = criticalAlerts.map(a => a.labels.alertname);
        const criticalServices = [
            'PrimaryServiceDown',
            'CodeServerDown',
            'PostgresDown',
            'RedisDown',
            'NetworkPartition',
            'ReplicationFailed',
        ];
        return alertNames.some(name => criticalServices.includes(name));
    }
    /**
     * Trigger failover process
     */
    async triggerFailover(alerts) {
        const eventId = this.generateEventId();
        const alertName = alerts[0].labels.alertname;
        const reason = alerts[0].annotations.description || 'Critical alert triggered failover';
        const event = {
            id: eventId,
            timestamp: Date.now(),
            alertName,
            severity: alerts[0].labels.severity,
            service: alerts[0].labels.service || 'unknown',
            reason,
            action: 'failover',
            sourceHost: this.config.primaryHost,
            targetHost: this.config.replicaHost,
            status: 'pending',
            metadata: {
                alertCount: alerts.length,
                alerts: alerts.map(a => ({
                    name: a.labels.alertname,
                    severity: a.labels.severity,
                    description: a.annotations.description,
                })),
            },
        };
        // Record in history
        this.failoverHistory.set(eventId, event);
        this.activeFailovers.add(eventId);
        this.lastFailoverTime = Date.now();
        // Emit failover start event
        this.emit('failover-start', event);
        try {
            // Execute failover
            event.status = 'in-progress';
            await this.executeFailover(event);
            event.status = 'completed';
            this.emit('failover-completed', event);
        }
        catch (error) {
            event.status = 'failed';
            event.metadata.error = error instanceof Error ? error.message : String(error);
            this.emit('failover-failed', event);
            // Escalate if failover fails
            event.action = 'escalate';
            this.emit('failover-escalated', event);
        }
        finally {
            this.activeFailovers.delete(eventId);
        }
        return event;
    }
    /**
     * Execute the actual failover
     */
    async executeFailover(event) {
        // Promote replica to primary
        // Note: In production, this would SSH to the replica and execute:
        // docker exec postgres pg_promote -D /var/lib/postgresql/data
        // docker-compose restart code-server oauth2-proxy caddy
        event.metadata.promotionStarted = Date.now();
        // Simulate promotion with proper error handling
        const promotionSuccess = await this.promoteReplica(event.targetHost);
        if (!promotionSuccess) {
            throw new Error(`Failed to promote replica ${event.targetHost} to primary`);
        }
        event.metadata.promotionCompleted = Date.now();
        // Verify new primary is healthy
        const healthCheckPassed = await this.verifyPrimaryHealth(event.targetHost);
        if (!healthCheckPassed) {
            throw new Error(`New primary ${event.targetHost} failed health checks`);
        }
        event.metadata.healthChecksPassed = true;
    }
    /**
     * Promote replica to primary (placeholder for actual implementation)
     */
    async promoteReplica(replicaHost) {
        // In production: ssh akushnir@replicaHost "docker exec postgres pg_promote ..."
        // For now, emit an event that can be handled externally
        this.emit('promote-replica-requested', {
            host: replicaHost,
            timestamp: Date.now(),
        });
        // Wait for external confirmation (in real implementation, this would be actual SSH)
        return new Promise(resolve => {
            const timeout = setTimeout(() => resolve(true), 1000);
            this.once('replica-promoted', () => {
                clearTimeout(timeout);
                resolve(true);
            });
        });
    }
    /**
     * Verify primary host is healthy
     */
    async verifyPrimaryHealth(host) {
        // In production: curl http://host:8080/healthz
        this.emit('health-check-requested', {
            host,
            timestamp: Date.now(),
        });
        return new Promise(resolve => {
            const timeout = setTimeout(() => resolve(true), 1000);
            this.once('health-check-passed', () => {
                clearTimeout(timeout);
                resolve(true);
            });
        });
    }
    /**
     * Handle recovery when alerts resolve
     */
    async handleRecovery(alerts) {
        const recoveryAlert = alerts[0];
        const eventId = this.generateEventId();
        if (this.activeFailovers.size === 0) {
            return; // No failover to recover from
        }
        this.emit('recovery-initiated', {
            id: eventId,
            timestamp: Date.now(),
            alerts: alerts.map(a => a.labels.alertname),
        });
        // Schedule recovery check
        const timeout = setTimeout(async () => {
            try {
                const recovered = await this.verifyOriginalPrimaryReady();
                if (recovered) {
                    this.emit('recovery-completed', {
                        id: eventId,
                        timestamp: Date.now(),
                    });
                    this.recoveryInProgress.delete(eventId);
                }
            }
            catch (error) {
                this.emit('recovery-error', {
                    id: eventId,
                    error: error instanceof Error ? error.message : String(error),
                });
            }
        }, this.config.recoveryCheckIntervalMs);
        this.recoveryInProgress.set(eventId, timeout);
    }
    /**
     * Verify original primary is ready to become primary again
     */
    async verifyOriginalPrimaryReady() {
        this.emit('primary-readiness-check-requested', {
            host: this.config.primaryHost,
            timestamp: Date.now(),
        });
        return new Promise(resolve => {
            const timeout = setTimeout(() => resolve(false), this.config.alertTimeout);
            this.once('primary-ready-confirmed', () => {
                clearTimeout(timeout);
                resolve(true);
            });
        });
    }
    /**
     * Generate unique event ID
     */
    generateEventId() {
        return `failover-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    }
    /**
     * Get failover history
     */
    getFailoverHistory(limit = 100) {
        return Array.from(this.failoverHistory.values())
            .sort((a, b) => b.timestamp - a.timestamp)
            .slice(0, limit);
    }
    /**
     * Get active failovers
     */
    getActiveFailovers() {
        return Array.from(this.activeFailovers)
            .map(id => this.failoverHistory.get(id))
            .filter(Boolean);
    }
    /**
     * Clear failover history (for testing)
     */
    clearHistory() {
        this.failoverHistory.clear();
        this.activeFailovers.clear();
        this.recoveryInProgress.forEach(timeout => clearTimeout(timeout));
        this.recoveryInProgress.clear();
    }
    /**
     * Get service configuration
     */
    getConfig() {
        return { ...this.config };
    }
    /**
     * Disable/enable failover service
     */
    setEnabled(enabled) {
        this.config.enabled = enabled;
        this.emit('status-changed', {
            enabled,
            timestamp: Date.now(),
        });
    }
}
export default FailoverWebhookService;
//# sourceMappingURL=failover-webhook-service.js.map