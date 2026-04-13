/**
 * Phase 11: Advanced Resilience & HA/DR
 * Exports for circuit breakers, failover, and chaos engineering
 */
export { CircuitBreaker } from '../../ml/CircuitBreaker';
export type { CircuitBreakerConfig, CircuitBreakerMetrics, CircuitState } from '../../ml/CircuitBreaker';
export { FailoverManager } from '../../ml/FailoverManager';
export type { FailoverConfig, FailoverStrategy, FailoverTrigger, FailoverEvent, ReplicaHealth, } from '../../ml/FailoverManager';
export { ChaosEngineer } from '../../ml/ChaosEngineer';
export type { ChaosTest, ChaosTestMetrics, ChaosScenario } from '../../ml/ChaosEngineer';
export { ResiliencePhase11Agent } from '../../agents/ResiliencePhase11Agent';
export type { ResilienceStatus } from '../../agents/ResiliencePhase11Agent';
/**
 * Phase 11 Configuration Examples
 */
export declare const Phase11Examples: {
    circuitBreakerConfig: {
        name: string;
        failureThreshold: number;
        resetTimeout: number;
        halfOpenRequests: number;
        monitoringWindow: number;
    };
    failoverConfig: {
        strategy: "active-passive";
        healthCheckInterval: number;
        failureThreshold: number;
        replicationDelay: number;
        autoFailover: boolean;
    };
    chaosTestScenario: {
        name: string;
        scenario: "latency";
        targetServices: string[];
        duration: number;
        intensity: number;
    };
    slaTargets: {
        availability: number;
        maxRecoveryTime: number;
        maxDataLoss: number;
    };
};
//# sourceMappingURL=index.d.ts.map