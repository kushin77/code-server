/**
 * Phase 11: Advanced Resilience & HA/DR
 * Exports for circuit breakers, failover, and chaos engineering
 */

export { CircuitBreaker } from '../../ml/CircuitBreaker';
export type { CircuitBreakerConfig, CircuitBreakerMetrics, CircuitState } from '../../ml/CircuitBreaker';

export { FailoverManager } from '../../ml/FailoverManager';
export type {
  FailoverConfig,
  FailoverStrategy,
  FailoverTrigger,
  FailoverEvent,
  ReplicaHealth,
} from '../../ml/FailoverManager';

export { ChaosEngineer } from '../../ml/ChaosEngineer';
export type { ChaosTest, ChaosTestMetrics, ChaosScenario } from '../../ml/ChaosEngineer';

export { ResiliencePhase11Agent } from '../../agents/ResiliencePhase11Agent';
export type { ResilienceStatus } from '../../agents/ResiliencePhase11Agent';

/**
 * Phase 11 Configuration Examples
 */
export const Phase11Examples = {
  circuitBreakerConfig: {
    name: 'api-service',
    failureThreshold: 5,
    resetTimeout: 30000,
    halfOpenRequests: 3,
    monitoringWindow: 60000,
  },

  failoverConfig: {
    strategy: 'active-passive' as const,
    healthCheckInterval: 5000,
    failureThreshold: 3,
    replicationDelay: 100,
    autoFailover: true,
  },

  chaosTestScenario: {
    name: 'Latency Spike Test',
    scenario: 'latency' as const,
    targetServices: ['api-gateway', 'data-service'],
    duration: 60000,
    intensity: 0.8,
  },

  slaTargets: {
    availability: 99.99,
    maxRecoveryTime: 30000,
    maxDataLoss: 0,
  },
};
