/**
 * Phase 11: Advanced Resilience & HA/DR Agent
 * Orchestrates circuit breakers, failover, and chaos engineering
 */

import { Agent } from '../phases';
import { CircuitBreaker, CircuitBreakerConfig } from '../ml/CircuitBreaker';
import { FailoverManager, FailoverConfig } from '../ml/FailoverManager';
import { ChaosEngineer, ChaosTest } from '../ml/ChaosEngineer';

export interface ResilienceStatus {
  timestamp: number;
  circuitBreakers: {
    total: number;
    open: number;
    halfOpen: number;
    closed: number;
  };
  failoverMetrics: {
    primaryReplica: string | undefined;
    healthyReplicas: number;
    failoversPastDay: number;
  };
  chaosTestsRunning: number;
  systemHealthScore: number; // 0-100
}

export class ResiliencePhase11Agent extends Agent {
  private circuitBreakers: Map<string, CircuitBreaker> = new Map();
  private failoverManagers: Map<string, FailoverManager> = new Map();
  private chaosEngineer: ChaosEngineer;
  private slaTargets: {
    availability: number; // percentage
    maxRecoveryTime: number; // milliseconds
    maxDataLoss: number; // bytes
  } = {
    availability: 99.9,
    maxRecoveryTime: 30000,
    maxDataLoss: 0,
  };

  constructor(context: any) {
    super('ResiliencePhase11Agent', context);
    this.chaosEngineer = new ChaosEngineer();
  }

  /**
   * Create circuit breaker for a service
   */
  createCircuitBreaker(config: CircuitBreakerConfig): CircuitBreaker {
    const breaker = new CircuitBreaker(config);
    this.circuitBreakers.set(config.name, breaker);
    this.log(`Created circuit breaker: ${config.name}`);
    return breaker;
  }

  /**
   * Execute with circuit breaker protection
   */
  async executeProtected<T>(serviceName: string, fn: () => Promise<T>): Promise<T> {
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
    } catch (error) {
      this.log(`Circuit breaker triggered for ${serviceName}: ${error}`);
      throw error;
    }
  }

  /**
   * Create failover manager for a service
   */
  createFailoverManager(
    serviceName: string,
    config: FailoverConfig,
    primaryReplicaId: string
  ): FailoverManager {
    const manager = new FailoverManager(config, primaryReplicaId);
    this.failoverManagers.set(serviceName, manager);
    this.log(`Created failover manager for ${serviceName} (primary: ${primaryReplicaId})`);
    return manager;
  }

  /**
   * Register service replica
   */
  registerReplica(serviceName: string, replicaId: string, isHealthy: boolean = true): void {
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
  updateReplicaHealth(
    serviceName: string,
    replicaId: string,
    isHealthy: boolean,
    latency: number,
    capacity: number
  ): void {
    const manager = this.failoverManagers.get(serviceName);
    if (!manager) return;

    manager.updateReplicaHealth(replicaId, isHealthy, latency, capacity);
  }

  /**
   * Register service for chaos testing
   */
  registerServiceForChaos(serviceName: string, failureSimulator: () => void): void {
    this.chaosEngineer.registerService(serviceName, failureSimulator);
  }

  /**
   * Run chaos test
   */
  runChaosTest(
    name: string,
    scenario: any,
    targetServices: string[],
    duration: number,
    intensity: number
  ): ChaosTest {
    return this.chaosEngineer.startChaosTest(name, scenario, targetServices, duration, intensity);
  }

  /**
   * Set SLA targets
   */
  setSLATargets(
    availability: number,
    maxRecoveryTime: number,
    maxDataLoss: number
  ): void {
    this.slaTargets = { availability, maxRecoveryTime, maxDataLoss };
    this.log(
      `SLA targets set: ${availability}% availability, ${maxRecoveryTime}ms recovery, ${maxDataLoss} bytes data loss`
    );
  }

  /**
   * Get resilience status
   */
  getResilienceStatus(): ResilienceStatus {
    const circuitBreakerMetrics = {
      total: this.circuitBreakers.size,
      open: 0,
      halfOpen: 0,
      closed: 0,
    };

    for (const breaker of this.circuitBreakers.values()) {
      const state = breaker.getState();
      if (state === 'OPEN') circuitBreakerMetrics.open++;
      else if (state === 'HALF_OPEN') circuitBreakerMetrics.halfOpen++;
      else circuitBreakerMetrics.closed++;
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
  private calculateHealthScore(
    circuitBreakerMetrics: any,
    healthyReplicas: number
  ): number {
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
  manualFailover(serviceName: string, targetReplicaId: string, reason?: string): boolean {
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
  getFailoverHistory(serviceName: string, limit?: number) {
    const manager = this.failoverManagers.get(serviceName);
    if (!manager) return [];
    return manager.getFailoverHistory(limit);
  }

  /**
   * Get chaos test history
   */
  getChaosTestHistory(limit?: number) {
    return this.chaosEngineer.getTestHistory(limit);
  }

  /**
   * Cleanup and destroy
   */
  destroy(): void {
    for (const breaker of this.circuitBreakers.values()) {
      breaker.destroy();
    }
    for (const manager of this.failoverManagers.values()) {
      manager.stopHealthMonitoring();
      manager.destroy();
    }
    this.log('Resilience agents destroyed');
  }
}
