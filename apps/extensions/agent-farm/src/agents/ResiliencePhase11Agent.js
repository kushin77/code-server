/**
 * Phase 11: Advanced Resilience & HA/DR Agent
 * Orchestrates circuit breakers, failover, and chaos engineering
 */
import { Agent } from '../types';
import { CircuitBreaker } from '../ml/CircuitBreaker';
import { FailoverManager } from '../ml/FailoverManager';
import { ChaosEngineer } from '../ml/ChaosEngineer';
export class ResiliencePhase11Agent extends Agent {
    constructor(context) {
        super();
        this.name = 'ResiliencePhase11Agent';
        this.domain = 'Advanced Resilience & HA/DR';
        this.circuitBreakers = new Map();
        this.failoverManagers = new Map();
        this.slaTargets = {
            availability: 99.9,
            maxRecoveryTime: 30000,
            maxDataLoss: 0,
        };
        void context;
        this.chaosEngineer = new ChaosEngineer();
    }
    /**
     * Create circuit breaker for a service
     */
    createCircuitBreaker(config) {
        const breaker = new CircuitBreaker(config);
        this.circuitBreakers.set(config.name, breaker);
        this.log(`Created circuit breaker: ${config.name}`);
        return breaker;
    }
    /**
     * Execute with circuit breaker protection
     */
    async executeProtected(serviceName, fn) {
        let breaker = this.circuitBreakers.get(serviceName);
        if (!breaker) {
            // Create default circuit breaker
            breaker = this.createCircuitBreaker({
                name: serviceName,
                failureThreshold: 5,
                resetTimeout: 30000,
                halfOpenRequests: 3,
                monitoringWindow: 60000,
            });
        }
        try {
            return await breaker.execute(fn);
        }
        catch (error) {
            this.log(`Circuit breaker triggered for ${serviceName}: ${error}`);
            throw error;
        }
    }
    /**
     * Create failover manager for a service
     */
    createFailoverManager(serviceName, config, primaryReplicaId) {
        const manager = new FailoverManager(config, primaryReplicaId);
        this.failoverManagers.set(serviceName, manager);
        this.log(`Created failover manager for ${serviceName} (primary: ${primaryReplicaId})`);
        return manager;
    }
    /**
     * Register service replica
     */
    registerReplica(serviceName, replicaId, isHealthy = true) {
        const manager = this.failoverManagers.get(serviceName);
        if (!manager) {
            this.log(`Failover manager not found for ${serviceName}`);
            return;
        }
        manager.registerReplica(replicaId, isHealthy);
    }
    /**
     * Update replica health
     */
    updateReplicaHealth(serviceName, replicaId, isHealthy, latency, capacity) {
        const manager = this.failoverManagers.get(serviceName);
        if (!manager)
            return;
        manager.updateReplicaHealth(replicaId, isHealthy, latency, capacity);
    }
    /**
     * Register service for chaos testing
     */
    registerServiceForChaos(serviceName, failureSimulator) {
        this.chaosEngineer.registerService(serviceName, failureSimulator);
    }
    /**
     * Run chaos test
     */
    runChaosTest(name, scenario, targetServices, duration, intensity) {
        return this.chaosEngineer.startChaosTest(name, scenario, targetServices, duration, intensity);
    }
    /**
     * Set SLA targets
     */
    setSLATargets(availability, maxRecoveryTime, maxDataLoss) {
        this.slaTargets = { availability, maxRecoveryTime, maxDataLoss };
        this.log(`SLA targets set: ${availability}% availability, ${maxRecoveryTime}ms recovery, ${maxDataLoss} bytes data loss`);
    }
    /**
     * Get resilience status
     */
    getResilienceStatus() {
        const circuitBreakerMetrics = {
            total: this.circuitBreakers.size,
            open: 0,
            halfOpen: 0,
            closed: 0,
        };
        for (const breaker of this.circuitBreakers.values()) {
            const state = breaker.getState();
            if (state === 'OPEN')
                circuitBreakerMetrics.open++;
            else if (state === 'HALF_OPEN')
                circuitBreakerMetrics.halfOpen++;
            else
                circuitBreakerMetrics.closed++;
        }
        let totalHealthyReplicas = 0;
        for (const manager of this.failoverManagers.values()) {
            totalHealthyReplicas += manager.getHealthyReplicas().length;
        }
        const healthScore = this.calculateHealthScore(circuitBreakerMetrics, totalHealthyReplicas);
        return {
            timestamp: Date.now(),
            circuitBreakers: circuitBreakerMetrics,
            failoverMetrics: {
                primaryReplica: this.failoverManagers.size > 0
                    ? Array.from(this.failoverManagers.values())[0]?.getPrimaryReplica()
                    : undefined,
                healthyReplicas: totalHealthyReplicas,
                failoversPastDay: 0, // Would aggregate from managers
            },
            chaosTestsRunning: this.chaosEngineer.getActiveTests().length,
            systemHealthScore: healthScore,
        };
    }
    /**
     * Calculate overall system health score
     */
    calculateHealthScore(circuitBreakerMetrics, healthyReplicas) {
        let score = 100;
        // Penalize for open circuit breakers
        score -= circuitBreakerMetrics.open * 10;
        // Penalize for half-open circuit breakers
        score -= circuitBreakerMetrics.halfOpen * 5;
        // Penalize for degraded replicas
        const expectedReplicas = this.failoverManagers.size * 3; // assume 3 replicas per service
        if (healthyReplicas < expectedReplicas) {
            score -= ((expectedReplicas - healthyReplicas) / expectedReplicas) * 20;
        }
        return Math.max(0, score);
    }
    /**
     * Manual failover for a service
     */
    manualFailover(serviceName, targetReplicaId, reason) {
        const manager = this.failoverManagers.get(serviceName);
        if (!manager) {
            this.log(`Failover manager not found for ${serviceName}`);
            return false;
        }
        return manager.manualFailover(targetReplicaId, reason);
    }
    /**
     * Get failover history
     */
    getFailoverHistory(serviceName, limit) {
        const manager = this.failoverManagers.get(serviceName);
        if (!manager)
            return [];
        return manager.getFailoverHistory(limit);
    }
    /**
     * Get chaos test history
     */
    getChaosTestHistory(limit) {
        return this.chaosEngineer.getTestHistory(limit);
    }
    /**
     * Cleanup and destroy
     */
    destroy() {
        for (const breaker of this.circuitBreakers.values()) {
            breaker.destroy();
        }
        for (const manager of this.failoverManagers.values()) {
            manager.stopHealthMonitoring();
            manager.destroy();
        }
        this.log('Resilience agents destroyed');
    }
    /**
     * Implement abstract analyze method
     */
    async analyze(context) {
        void context;
        this.log('Analyzing system resilience');
        const status = this.getResilienceStatus();
        return this.formatOutput(`System resilience analyzed. Health score: ${status.systemHealthScore}/100`, [
            `Open circuit breakers: ${status.circuitBreakers.open}`,
            `Healthy replicas: ${status.failoverMetrics.healthyReplicas}`,
            `Failovers past day: ${status.failoverMetrics.failoversPastDay}`,
        ]);
    }
    /**
     * Implement abstract coordinate method
     */
    async coordinate(context, previousResults) {
        void context;
        void previousResults;
        this.log('Coordinating resilience monitoring with other agents');
        // Stub implementation for multi-agent coordination
    }
}
//# sourceMappingURL=ResiliencePhase11Agent.js.map