/**
 * PR Preview Environments Service
 * Auto-provision and auto-destroy preview environments
 */
import { EventEmitter } from 'events';
/**
 * PR Preview Environments Service
 * Manages auto-provisioning and destruction of preview environments
 */
export class PreviewService extends EventEmitter {
    constructor(config) {
        super();
        this.environments = new Map();
        this.pullRequests = new Map();
        this.scalingEvents = new Map();
        this.statistics = new Map();
        this.auditLog = new Map();
        this.healthChecks = new Map();
        this.config = {
            enableAutoProvisioning: true,
            enableAutoDestroy: true,
            gracePeriodMinutes: 60,
            maxConcurrentEnvironments: 50,
            defaultReplicaCount: 2,
            defaultCpuLimit: '1',
            defaultMemoryLimit: '1Gi',
            healthCheckIntervalMs: 30000,
            metricsCollectionIntervalMs: 60000,
            scalingThresholdPercent: 80,
            maxAuditLogSize: 10000,
            storageBackend: 'memory',
            ...config,
        };
    }
    /**
     * Get or create singleton instance
     */
    static getInstance(config) {
        if (!PreviewService.instance) {
            PreviewService.instance = new PreviewService(config);
            PreviewService.instance.initialize();
        }
        return PreviewService.instance;
    }
    /**
     * Initialize service
     */
    initialize() {
        this.emit('initialized', { timestamp: Date.now() });
    }
    /**
     * Shutdown service
     */
    shutdown() {
        this.environments.clear();
        this.pullRequests.clear();
        this.scalingEvents.clear();
        this.statistics.clear();
        this.auditLog.clear();
        this.healthChecks.clear();
        this.emit('shutdown', { timestamp: Date.now() });
    }
    /**
     * Provision preview environment
     */
    async provisionEnvironment(request, ipAddress, userAgent) {
        const provisionStartAt = Date.now();
        try {
            // Check concurrent limit
            if (this.environments.size >= this.config.maxConcurrentEnvironments) {
                throw new Error('Max concurrent environments reached');
            }
            // Create environment instance
            const environmentId = `prev-${request.pullRequestNumber}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const url = `https://pr-${request.pullRequestNumber}.preview.localhost`;
            const config = {
                cpuLimit: request.config?.cpuLimit || this.config.defaultCpuLimit,
                memoryLimit: request.config?.memoryLimit || this.config.defaultMemoryLimit,
                replicaCount: request.config?.replicaCount || this.config.defaultReplicaCount,
                timeoutMinutes: request.config?.timeoutMinutes || this.config.gracePeriodMinutes,
                enableAutoScale: request.config?.enableAutoScale !== false,
                enableMetrics: request.config?.enableMetrics !== false,
                containerImage: request.config?.containerImage || 'kushnir/code-server:latest',
                port: request.config?.port || 3000,
                healthCheckPath: request.config?.healthCheckPath || '/health',
                environmentVariables: request.config?.environmentVariables || new Map(),
            };
            const environment = {
                id: environmentId,
                pullRequestId: request.pullRequestId,
                pullRequestNumber: request.pullRequestNumber,
                userId: request.userId,
                userEmail: request.userEmail,
                url,
                state: 'provisioning',
                config,
                provisionedAt: Date.now(),
                lastHealthCheckAt: Date.now(),
                lastHealthStatus: 'healthy',
                metrics: {
                    cpuUsagePercent: 0,
                    memoryUsagePercent: 0,
                    requestCount: 0,
                    errorCount: 0,
                    averageResponseTimeMs: 0,
                },
                metadata: {
                    branchName: request.branch.name,
                    commitSha: request.branch.sha,
                    repoUrl: request.branch.repoUrl,
                },
            };
            // Simulate provisioning (100-500ms)
            await this.delay(100 + Math.random() * 400);
            environment.state = 'active';
            this.environments.set(environmentId, environment);
            // Store PR
            const pr = {
                id: request.pullRequestId,
                number: request.pullRequestNumber,
                title: `PR #${request.pullRequestNumber}`,
                author: request.userId,
                branch: request.branch,
                targetBranch: request.targetBranch,
                createdAt: Date.now(),
                updatedAt: Date.now(),
                state: 'open',
                isDraft: false,
            };
            this.pullRequests.set(request.pullRequestId, pr);
            const provisioningTimeMs = Date.now() - provisionStartAt;
            this.recordAudit({
                userId: request.userId,
                userEmail: request.userEmail,
                operation: 'provision',
                status: 'success',
                environmentId,
                pullRequestNumber: request.pullRequestNumber,
                ipAddress,
                userAgent,
                details: {
                    provisioningTimeMs,
                    url,
                    replicaCount: config.replicaCount,
                },
            });
            this.updateStatistics(request.pullRequestId, request.pullRequestNumber);
            this.emit('environment-provisioned', { environment, provisioningTimeMs, timestamp: Date.now() });
            return {
                success: true,
                environmentId,
                url,
                provisioningTimeMs,
            };
        }
        catch (error) {
            const provisioningTimeMs = Date.now() - provisionStartAt;
            this.recordAudit({
                userId: request.userId,
                userEmail: request.userEmail,
                operation: 'provision',
                status: 'failure',
                pullRequestNumber: request.pullRequestNumber,
                ipAddress,
                userAgent,
                details: {
                    reason: error instanceof Error ? error.message : 'Unknown error',
                },
            });
            this.emit('environment-provision-failed', { request, error, timestamp: Date.now() });
            return {
                success: false,
                environmentId: '',
                provisioningTimeMs,
                reason: error instanceof Error ? error.message : 'Unknown error',
            };
        }
    }
    /**
     * Terminate preview environment
     */
    terminateEnvironment(environmentId, pullRequestNumber, userId, ipAddress, userAgent) {
        const environment = this.environments.get(environmentId);
        if (!environment)
            return false;
        environment.state = 'terminated';
        environment.terminatedAt = Date.now();
        this.recordAudit({
            userId,
            userEmail: environment.userEmail,
            operation: 'terminate',
            status: 'success',
            environmentId,
            pullRequestNumber,
            ipAddress,
            userAgent,
            details: { reason: 'Manual termination' },
        });
        this.emit('environment-terminated', { environment, timestamp: Date.now() });
        return true;
    }
    /**
     * Get preview environment
     */
    getEnvironment(environmentId) {
        return this.environments.get(environmentId) || null;
    }
    /**
     * Get all environments for PR
     */
    getEnvironmentsByPullRequest(pullRequestNumber) {
        return Array.from(this.environments.values()).filter((e) => e.pullRequestNumber === pullRequestNumber);
    }
    /**
     * Scale environment replicas
     */
    scaleEnvironment(environmentId, newReplicaCount, userId, ipAddress, userAgent) {
        const environment = this.environments.get(environmentId);
        if (!environment)
            return false;
        const oldCount = environment.config.replicaCount;
        environment.config.replicaCount = newReplicaCount;
        const scalingEvent = {
            id: `scale-${Date.now()}-${Math.random().toString(16).slice(2)}`,
            environmentId,
            timestamp: Date.now(),
            fromReplicas: oldCount,
            toReplicas: newReplicaCount,
            reason: 'Manual scaling',
            metrics: { ...environment.metrics },
        };
        if (!this.scalingEvents.has(environmentId)) {
            this.scalingEvents.set(environmentId, []);
        }
        this.scalingEvents.get(environmentId).push(scalingEvent);
        this.recordAudit({
            userId,
            userEmail: environment.userEmail,
            operation: 'scale',
            status: 'success',
            environmentId,
            pullRequestNumber: environment.pullRequestNumber,
            ipAddress,
            userAgent,
            details: {
                fromReplicas: oldCount,
                toReplicas: newReplicaCount,
            },
        });
        this.emit('environment-scaled', { scalingEvent, timestamp: Date.now() });
        return true;
    }
    /**
     * Perform health check
     */
    performHealthCheck(environmentId) {
        const environment = this.environments.get(environmentId);
        const result = {
            id: `hc-${Date.now()}-${Math.random().toString(16).slice(2)}`,
            environmentId,
            timestamp: Date.now(),
            isHealthy: environment ? Math.random() > 0.1 : false, // 90% success rate
            responseTimeMs: Math.random() * 500,
            httpStatusCode: environment ? 200 : 503,
        };
        if (environment) {
            environment.lastHealthCheckAt = Date.now();
            environment.lastHealthStatus = result.isHealthy ? 'healthy' : 'degraded';
            if (!this.healthChecks.has(environmentId)) {
                this.healthChecks.set(environmentId, []);
            }
            const checks = this.healthChecks.get(environmentId);
            checks.push(result);
            if (checks.length > 100) {
                checks.splice(0, checks.length - 100);
            }
        }
        return result;
    }
    /**
     * Start grace period for PR close/merge
     */
    startGracePeriod(pullRequestNumber, userId, ipAddress, userAgent) {
        const affected = [];
        for (const env of this.environments.values()) {
            if (env.pullRequestNumber === pullRequestNumber && !env.gracePeriodStartAt) {
                env.gracePeriodStartAt = Date.now();
                env.state = 'shutting-down';
                affected.push(env);
                this.recordAudit({
                    userId,
                    userEmail: env.userEmail,
                    operation: 'grace-period-start',
                    status: 'success',
                    environmentId: env.id,
                    pullRequestNumber,
                    ipAddress,
                    userAgent,
                    details: { gracePeriodMinutes: this.config.gracePeriodMinutes },
                });
            }
        }
        this.emit('grace-period-started', { pullRequestNumber, environmentCount: affected.length, timestamp: Date.now() });
        return affected;
    }
    /**
     * Get statistics for PR
     */
    getStatistics(pullRequestNumber) {
        for (const stats of this.statistics.values()) {
            if (stats.pullRequestNumber === pullRequestNumber) {
                return stats;
            }
        }
        return null;
    }
    /**
     * Get audit log for user
     */
    getAuditLog(userId) {
        return (this.auditLog.get(userId) || []).slice(-100);
    }
    /**
     * Get health check history
     */
    getHealthCheckHistory(environmentId, limit) {
        const checks = this.healthChecks.get(environmentId) || [];
        if (limit) {
            return checks.slice(-limit);
        }
        return checks;
    }
    /**
     * Update configuration
     */
    updateConfig(config, userId, ipAddress, userAgent) {
        this.config = { ...this.config, ...config };
        this.emit('config-updated', { config: this.config, timestamp: Date.now() });
    }
    /**
     * Static reset for testing
     */
    static reset() {
        if (PreviewService.instance) {
            PreviewService.instance.shutdown();
        }
        PreviewService.instance = undefined;
    }
    /**
     * Private helper: Delay
     */
    delay(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }
    /**
     * Private helper: Record audit entry
     */
    recordAudit(entry) {
        const auditEntry = {
            id: `audit-${Date.now()}-${Math.random().toString(16).slice(2)}`,
            userId: entry.userId,
            userEmail: entry.userEmail,
            operation: entry.operation,
            status: entry.status,
            environmentId: entry.environmentId,
            pullRequestNumber: entry.pullRequestNumber,
            ipAddress: entry.ipAddress,
            userAgent: entry.userAgent,
            timestamp: Date.now(),
            details: entry.details || {},
        };
        if (!this.auditLog.has(entry.userId)) {
            this.auditLog.set(entry.userId, []);
        }
        const userLog = this.auditLog.get(entry.userId);
        userLog.push(auditEntry);
        if (userLog.length > this.config.maxAuditLogSize) {
            userLog.splice(0, userLog.length - this.config.maxAuditLogSize);
        }
        this.emit('audit-logged', { entry: auditEntry, timestamp: Date.now() });
    }
    /**
     * Private helper: Update statistics
     */
    updateStatistics(pullRequestId, pullRequestNumber) {
        const stats = {
            pullRequestId,
            pullRequestNumber,
            totalProvisions: 1,
            successfulProvisions: 1,
            failedProvisions: 0,
            averageProvisioningTimeMs: 250,
            averageLifetimeMs: 0,
            totalUptime: 0,
            totalDowntime: 0,
            scalingEventsCount: 0,
            lastProvisioned: Date.now(),
            lastTerminated: 0,
        };
        this.statistics.set(pullRequestId, stats);
    }
}
//# sourceMappingURL=preview-service.js.map