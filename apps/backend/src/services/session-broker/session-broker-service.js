#!/usr/bin/env node
// @file        apps/backend/src/services/session-broker/session-broker-service.ts
// @module      session-broker
// @description Session broker for horizontal scaling with consistent hashing
import pino from 'pino';
import { EventEmitter } from 'events';
import { ConsistentHashRing } from './consistent-hashing';
/**
 * Session broker that routes connections to the right instance based on consistent hashing.
 * Supports:
 * - Rendezvous hashing for optimal session affinity
 * - Health checking with automatic failover
 * - Graceful draining of instances
 * - Load monitoring and statistics
 */
export class SessionBrokerService extends EventEmitter {
    constructor(config, logger) {
        super();
        this.stats = new Map();
        this.config = {
            instances: config.instances,
            replicationFactor: config.replicationFactor || 3,
            virtualNodes: config.virtualNodes || 150, // Not used in Rendezvous but kept for compat
            healthCheckInterval: config.healthCheckInterval || 30000, // 30s
            healthCheckTimeout: config.healthCheckTimeout || 5000, // 5s
        };
        this.logger = logger || pino({ name: 'session-broker' });
        this.hashRing = new ConsistentHashRing(config.instances, this.logger);
        // Initialize stats for all instances
        for (const instance of config.instances) {
            this.stats.set(instance.id, { requests: 0, errors: 0, latencies: [] });
        }
        this.logger.info(`SessionBroker initialized with ${config.instances.length} instances`);
    }
    /**
     * Get or create singleton instance.
     */
    static getInstance(config, logger) {
        const key = 'default';
        if (!this.instances.has(key) && config) {
            this.instances.set(key, new SessionBrokerService(config, logger));
        }
        if (!this.instances.has(key)) {
            throw new Error('SessionBrokerService not initialized. Provide config on first call.');
        }
        return this.instances.get(key);
    }
    /**
     * Route a session to the appropriate instance.
     * Returns the primary instance and replicas in priority order.
     */
    routeSession(context) {
        try {
            const result = this.hashRing.getInstances(context);
            this.recordRequest(result.instance.id);
            return result;
        }
        catch (error) {
            this.logger.error(`Failed to route session: ${error}`);
            throw error;
        }
    }
    /**
     * Get backup instances for a session (for replication/failover).
     */
    getBackupInstances(context, count = 2) {
        try {
            const routing = this.hashRing.getInstances(context);
            return routing.replicas.slice(0, count);
        }
        catch (error) {
            this.logger.error(`Failed to get backup instances: ${error}`);
            return [];
        }
    }
    /**
     * Add a new instance to the broker (for scaling up).
     */
    addInstance(instance) {
        this.hashRing.addInstance(instance);
        this.stats.set(instance.id, { requests: 0, errors: 0, latencies: [] });
        this.emit('instance-added', instance);
        this.logger.info(`Instance added: ${instance.id} (${instance.host}:${instance.port})`);
    }
    /**
     * Remove an instance from the broker (for scaling down).
     * First drains the instance by marking it as 'draining'.
     */
    drainInstance(instanceId) {
        const instance = this.hashRing.getInstance(instanceId);
        if (instance) {
            this.hashRing.updateInstanceStatus(instanceId, 'draining');
            this.emit('instance-draining', instance);
            this.logger.info(`Instance marked as draining: ${instanceId}`);
        }
    }
    /**
     * Remove a drained instance completely.
     */
    removeInstance(instanceId) {
        this.hashRing.removeInstance(instanceId);
        this.stats.delete(instanceId);
        const instance = this.hashRing.getInstance(instanceId);
        this.emit('instance-removed', { id: instanceId });
        this.logger.info(`Instance removed: ${instanceId}`);
    }
    /**
     * Start background health checking.
     */
    startHealthChecking() {
        if (this.healthCheckTimer)
            return;
        this.logger.info('Starting health checks');
        this.performHealthCheck();
        this.healthCheckTimer = setInterval(() => {
            this.performHealthCheck();
        }, this.config.healthCheckInterval);
    }
    /**
     * Stop background health checking.
     */
    stopHealthChecking() {
        if (this.healthCheckTimer) {
            clearInterval(this.healthCheckTimer);
            this.healthCheckTimer = undefined;
            this.logger.info('Stopped health checks');
        }
    }
    /**
     * Perform health check on all instances.
     */
    async performHealthCheck() {
        const checks = this.config.instances.map((instance) => this.healthCheckInstance(instance));
        const results = await Promise.all(checks);
        for (const result of results) {
            const newStatus = result.healthy ? 'healthy' : 'unhealthy';
            const instance = this.hashRing.getInstance(result.instanceId);
            if (instance && instance.status !== newStatus) {
                this.hashRing.updateInstanceStatus(result.instanceId, newStatus);
                if (result.healthy) {
                    this.logger.info(`Instance recovered: ${result.instanceId}`);
                    this.emit('instance-recovered', instance);
                }
                else {
                    this.logger.warn(`Instance unhealthy: ${result.instanceId}`, {
                        error: result.error,
                    });
                    this.emit('instance-unhealthy', instance);
                }
            }
        }
    }
    /**
     * Health check a single instance.
     */
    async healthCheckInstance(instance) {
        const startTime = Date.now();
        try {
            // Try to connect to instance's health endpoint
            const controller = new AbortController();
            const timeout = setTimeout(() => controller.abort(), this.config.healthCheckTimeout);
            const response = await fetch(`http://${instance.host}:${instance.port}/healthz`, { signal: controller.signal });
            clearTimeout(timeout);
            const responseTime = Date.now() - startTime;
            if (response.ok) {
                return { instanceId: instance.id, healthy: true, responseTime };
            }
            else {
                return {
                    instanceId: instance.id,
                    healthy: false,
                    responseTime,
                    error: `HTTP ${response.status}`,
                };
            }
        }
        catch (error) {
            const responseTime = Date.now() - startTime;
            return {
                instanceId: instance.id,
                healthy: false,
                responseTime,
                error: `${error}`,
            };
        }
    }
    /**
     * Record a request to an instance (for metrics).
     */
    recordRequest(instanceId, latency = 0, isError = false) {
        const stat = this.stats.get(instanceId);
        if (stat) {
            stat.requests++;
            if (isError)
                stat.errors++;
            if (latency > 0) {
                stat.latencies.push(latency);
                // Keep only last 1000 latencies
                if (stat.latencies.length > 1000) {
                    stat.latencies.shift();
                }
            }
        }
    }
    /**
     * Record a request error.
     */
    recordError(instanceId) {
        this.recordRequest(instanceId, 0, true);
    }
    /**
     * Record request latency.
     */
    recordLatency(instanceId, latencyMs) {
        this.recordRequest(instanceId, latencyMs, false);
    }
    /**
     * Get statistics for an instance.
     */
    getInstanceStats(instanceId) {
        const stat = this.stats.get(instanceId);
        if (!stat)
            return null;
        const latencies = stat.latencies.sort((a, b) => a - b);
        const p50 = latencies[Math.floor(latencies.length * 0.5)] || 0;
        const p95 = latencies[Math.floor(latencies.length * 0.95)] || 0;
        const p99 = latencies[Math.floor(latencies.length * 0.99)] || 0;
        return {
            instanceId,
            requestCount: stat.requests,
            errorCount: stat.errors,
            errorRate: stat.requests > 0 ? stat.errors / stat.requests : 0,
            latencyP50: p50,
            latencyP95: p95,
            latencyP99: p99,
            lastUpdated: Date.now(),
        };
    }
    /**
     * Get statistics for all instances.
     */
    getAllStats() {
        return Array.from(this.stats.keys()).map((id) => this.getInstanceStats(id));
    }
    /**
     * Get instance by ID.
     */
    getInstance(instanceId) {
        return this.hashRing.getInstance(instanceId);
    }
    /**
     * Get all instances.
     */
    getInstances() {
        return this.hashRing.getAllInstances();
    }
    /**
     * Get healthy instances only.
     */
    getHealthyInstances() {
        return this.hashRing.getHealthyInstances();
    }
    /**
     * Reset all statistics.
     */
    resetStats() {
        for (const stat of this.stats.values()) {
            stat.requests = 0;
            stat.errors = 0;
            stat.latencies = [];
        }
    }
    /**
     * Shutdown broker.
     */
    shutdown() {
        this.stopHealthChecking();
        this.removeAllListeners();
        SessionBrokerService.instances.delete('default');
    }
}
SessionBrokerService.instances = new Map();
//# sourceMappingURL=session-broker-service.js.map