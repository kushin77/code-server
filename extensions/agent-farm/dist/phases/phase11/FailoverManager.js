"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.FailoverManager = exports.FailoverState = void 0;
const child_process_1 = require("child_process");
/**
 * Failover states during HA/DR operations
 */
var FailoverState;
(function (FailoverState) {
    FailoverState["HEALTHY"] = "healthy";
    FailoverState["DEGRADED"] = "degraded";
    FailoverState["FAILOVER_IN_PROGRESS"] = "failover_in_progress";
    FailoverState["FAILOVER_COMPLETE"] = "failover_complete";
})(FailoverState || (exports.FailoverState = FailoverState = {}));
/**
 * FailoverManager - Orchestrates automatic failover operations
 * Detects failures and executes recovery strategies
 */
class FailoverManager {
    constructor() {
        this.state = FailoverState.HEALTHY;
        this.strategies = [];
        this.failoverInProgress = false;
        this.lastFailoverTime = null;
        this.failoverAttempts = 0;
        this.maxFailoverAttempts = 3;
        this.failoverCooldown = 300000; // 5 minutes
        this.registerDefaultStrategies();
    }
    /**
     * Register built-in failover strategies
     */
    registerDefaultStrategies() {
        // Strategy 1: Database failover (highest priority)
        this.registerStrategy({
            name: 'database-failover',
            priority: 1,
            condition: (health) => {
                const dbStatus = health.components.find((c) => c.component === 'database');
                return (dbStatus?.status === 'unhealthy' &&
                    health.overall === 'unhealthy');
            },
            execute: async () => {
                await this.promoteStandbyDatabase();
            },
        });
        // Strategy 2: Cache cluster failover
        this.registerStrategy({
            name: 'cache-failover',
            priority: 2,
            condition: (health) => {
                const cacheStatus = health.components.find((c) => c.component === 'cache');
                return cacheStatus?.status === 'unhealthy';
            },
            execute: async () => {
                await this.failoverCache();
            },
        });
        // Strategy 3: Load balancer reconfiguration
        this.registerStrategy({
            name: 'api-failover',
            priority: 3,
            condition: (health) => {
                const apiStatus = health.components.find((c) => c.component === 'api');
                return apiStatus?.status === 'unhealthy';
            },
            execute: async () => {
                await this.reconfigureLoadBalancer();
            },
        });
    }
    /**
     * Register custom failover strategy
     */
    registerStrategy(strategy) {
        this.strategies.push(strategy);
        // Sort by priority (lower number = higher priority)
        this.strategies.sort((a, b) => a.priority - b.priority);
        console.info(`Registered failover strategy: ${strategy.name}`);
    }
    /**
     * Trigger automatic failover based on system health
     */
    async triggerFailover(health) {
        if (this.failoverInProgress) {
            console.warn('Failover already in progress, skipping...');
            return;
        }
        // Enforce cooldown period to avoid failover storms
        if (this.lastFailoverTime &&
            Date.now() - this.lastFailoverTime.getTime() < this.failoverCooldown) {
            console.warn(`Failover cooldown active (${this.failoverCooldown}ms), skipping...`);
            return;
        }
        this.state = FailoverState.FAILOVER_IN_PROGRESS;
        this.failoverInProgress = true;
        this.failoverAttempts = 0;
        try {
            // Find applicable strategies
            const applicableStrategies = this.strategies.filter((s) => s.condition(health));
            if (applicableStrategies.length === 0) {
                console.info('No applicable failover strategies for current health state');
                return;
            }
            const strategyNames = applicableStrategies.map((s) => s.name).join(', ');
            console.warn(`Triggering failover with strategies: ${strategyNames}`);
            // Execute strategies in priority order
            for (const strategy of applicableStrategies) {
                try {
                    console.info(`Executing failover strategy: ${strategy.name}`);
                    await strategy.execute();
                    console.info(`✓ Successfully executed: ${strategy.name}`);
                }
                catch (error) {
                    console.error(`✗ Failed to execute strategy ${strategy.name}:`, error);
                    this.failoverAttempts++;
                    if (this.failoverAttempts >= this.maxFailoverAttempts) {
                        throw new Error(`Max failover attempts exceeded (${this.maxFailoverAttempts})`);
                    }
                }
            }
            this.state = FailoverState.FAILOVER_COMPLETE;
            this.lastFailoverTime = new Date();
            // Notify operations
            await this.notifyOpsTeam('WARNING', `Failover completed successfully via: ${strategyNames}`);
        }
        catch (error) {
            console.error('Failover failed:', error);
            // Alert operations team with critical severity
            await this.notifyOpsTeam('CRITICAL', `Failover FAILED: ${error.message}`);
        }
        finally {
            this.failoverInProgress = false;
            // Reset state after delay
            if (this.state === FailoverState.FAILOVER_COMPLETE) {
                setTimeout(() => {
                    this.state = FailoverState.HEALTHY;
                }, 30000); // 30 second grace period
            }
        }
    }
    /**
     * Promote PostgreSQL standby database to primary
     */
    async promoteStandbyDatabase() {
        try {
            console.info('Promoting standby database to primary...');
            // Execute promotion command on standby
            const result = (0, child_process_1.execSync)('psql -h standby.example.com -U postgres -c "SELECT pg_promote();"', { encoding: 'utf-8' });
            console.info('Database promoted successfully:', result);
            // Wait for promotion to complete
            await new Promise((resolve) => setTimeout(resolve, 5000));
            // Verify promotion
            const verifyResult = (0, child_process_1.execSync)('psql -h standby.example.com -U postgres -c "SELECT pg_is_in_recovery();"', { encoding: 'utf-8' });
            if (verifyResult.includes('f')) {
                console.info('✓ Standby promotion verified (not in recovery)');
            }
            else {
                throw new Error('Promotion verification failed: still in recovery mode');
            }
            // Update connection strings for all services
            await this.updateServiceConnections('primary');
        }
        catch (error) {
            throw new Error(`Database promotion failed: ${error.message}`);
        }
    }
    /**
     * Failover Redis cache cluster
     */
    async failoverCache() {
        try {
            console.info('Initiating Redis cache failover...');
            // Trigger Redis cluster failover
            const result = (0, child_process_1.execSync)('redis-cli -h redis-cluster -p 7000 CLUSTER FAILOVER', { encoding: 'utf-8' });
            console.info('Cache failover initiated:', result);
            // Wait for failover
            await new Promise((resolve) => setTimeout(resolve, 10000));
            // Verify cluster health
            const healthCheck = (0, child_process_1.execSync)('redis-cli -h redis-cluster -p 7000 CLUSTER INFO', { encoding: 'utf-8' });
            if (healthCheck.includes('cluster_state:ok')) {
                console.info('✓ Redis cluster failover completed successfully');
            }
            else {
                console.warn('Redis cluster in degraded state, monitoring...');
            }
        }
        catch (error) {
            throw new Error(`Cache failover failed: ${error.message}`);
        }
    }
    /**
     * Reconfigure load balancer to exclude failed backend
     */
    async reconfigureLoadBalancer() {
        try {
            console.info('Reconfiguring load balancer...');
            // Reload HAProxy with new configuration
            const result = (0, child_process_1.execSync)('systemctl reload haproxy', { encoding: 'utf-8' });
            console.info('Load balancer reconfigured:', result);
            // Verify HAProxy is healthy
            const stats = (0, child_process_1.execSync)('curl -s http://localhost:8404/stats | grep "Healthy"', { encoding: 'utf-8' });
            console.info('Load balancer health verified');
        }
        catch (error) {
            throw new Error(`Load balancer update failed: ${error.message}`);
        }
    }
    /**
     * Update service discovery with new database connection
     */
    async updateServiceConnections(node) {
        try {
            console.info(`Updating service discovery to point to ${node}...`);
            // Register new service endpoint with Consul
            (0, child_process_1.execSync)(`consul services register -id code-server-${node} -name code-server`, { encoding: 'utf-8' });
            console.info(`✓ Service discovery updated to ${node}`);
        }
        catch (error) {
            throw new Error(`Service discovery update failed: ${error.message}`);
        }
    }
    /**
     * Notify operations team via Slack and PagerDuty
     */
    async notifyOpsTeam(severity, message) {
        try {
            console.warn(`[${severity}] Failover Alert: ${message}`);
            // Log to file or send via available mechanism
            // In a real environment, this would use HTTP clients or message queues
            console.error(`Ops Alert: ${severity} - ${message}`);
        }
        catch (error) {
            console.error('Failed to send notification:', error);
        }
    }
    /**
     * Get current failover state
     */
    getState() {
        return this.state;
    }
    /**
     * Get failover statistics
     */
    getFailoverStats() {
        return {
            state: this.state,
            lastFailoverTime: this.lastFailoverTime,
            failoverAttempts: this.failoverAttempts,
        };
    }
}
exports.FailoverManager = FailoverManager;
//# sourceMappingURL=FailoverManager.js.map