/**
 * Failover Manager - Intelligent failover with circuit breaker pattern
 * Phase 12.3: Geographic Routing
 * 
 * Responsibilities:
 * - Monitor region health and trigger failover when needed
 * - Implement circuit breaker pattern to prevent cascading failures
 * - Handle gradual failover (canary deployments)
 * - Track failover events and recovery
 * - Manage failover state across distributed systems
 */

import { EventEmitter } from 'events';
import { Logger } from '../logging/Logger';
import { Metrics } from '../monitoring/Metrics';

export enum CircuitBreakerState {
  CLOSED = 'CLOSED', // Normal operation
  OPEN = 'OPEN', // Failing, rejecting requests
  HALF_OPEN = 'HALF_OPEN', // Testing recovery
}

export interface CircuitBreakerConfig {
  failureThreshold: number; // Failures before opening (0-1)
  successThreshold: number; // Successes before closing from half-open
  timeout: number; // Milliseconds before half-open test
  windowSize: number; // Sample window size
}

export interface FailoverConfig {
  regions: string[];
  circuitBreakerConfig: CircuitBreakerConfig;
  healthCheckInterval: number;
  canaryPercentage: number; // 0-100: percentage of traffic for canary
  maxFailoverChain: number; // Max consecutive failovers
  failoverTimeout: number; // Max time to attempt failover
}

export interface CircuitBreakerMetrics {
  state: CircuitBreakerState;
  failures: number;
  successes: number;
  lastFailureTime: Date | null;
  lastSuccessTime: Date | null;
  openedAt: Date | null;
  halfOpenAttempts: number;
}

export interface FailoverEvent {
  fromRegion: string;
  toRegion: string;
  reason: string;
  timestamp: Date;
  recoveryTime?: number; // Milliseconds to recover
}

export class CircuitBreaker {
  private state: CircuitBreakerState = CircuitBreakerState.CLOSED;
  private failures: number = 0;
  private successes: number = 0;
  private lastFailureTime: Date | null = null;
  private lastSuccessTime: Date | null = null;
  private openedAt: Date | null = null;
  private halfOpenAttempts: number = 0;
  private config: CircuitBreakerConfig;
  private window: Array<{ success: boolean; timestamp: Date }> = [];

  constructor(config: CircuitBreakerConfig) {
    this.config = config;
  }

  /**
   * Record a request success
   */
  recordSuccess(): void {
    this.successes++;
    this.lastSuccessTime = new Date();
    this.window.push({ success: true, timestamp: new Date() });
    this.trimWindow();

    if (this.state === CircuitBreakerState.HALF_OPEN) {
      if (
        this.successes >=
        this.config.successThreshold
      ) {
        this.close();
      }
    } else if (this.state === CircuitBreakerState.CLOSED) {
      // Reset failures on success
      this.failures = Math.max(0, this.failures - 1);
    }
  }

  /**
   * Record a request failure
   */
  recordFailure(): void {
    this.failures++;
    this.lastFailureTime = new Date();
    this.window.push({ success: false, timestamp: new Date() });
    this.trimWindow();

    const failureRate =
      this.failures / (this.failures + this.successes || 1);

    if (
      this.state === CircuitBreakerState.CLOSED &&
      failureRate >= this.config.failureThreshold
    ) {
      this.open();
    } else if (this.state === CircuitBreakerState.HALF_OPEN) {
      // Any failure in half-open reopens immediately
      this.open();
      this.halfOpenAttempts = 0;
    }
  }

  /**
   * Check if we should allow a request
   */
  canAttempt(): boolean {
    if (this.state === CircuitBreakerState.CLOSED) {
      return true;
    }

    if (this.state === CircuitBreakerState.OPEN) {
      // Check if timeout has elapsed
      const timeSinceOpen =
        Date.now() - (this.openedAt?.getTime() || 0);
      if (timeSinceOpen >= this.config.timeout) {
        this.transitionToHalfOpen();
        return true;
      }
      return false;
    }

    // HALF_OPEN: allow limited attempts
    return this.halfOpenAttempts < this.config.successThreshold;
  }

  /**
   * Open the circuit (start failing fast)
   */
  private open(): void {
    if (this.state !== CircuitBreakerState.OPEN) {
      this.state = CircuitBreakerState.OPEN;
      this.openedAt = new Date();
      this.halfOpenAttempts = 0;
    }
  }

  /**
   * Close the circuit (resume normal operation)
   */
  private close(): void {
    this.state = CircuitBreakerState.CLOSED;
    this.failures = 0;
    this.successes = 0;
    this.openedAt = null;
    this.halfOpenAttempts = 0;
  }

  /**
   * Transition to half-open (test recovery)
   */
  private transitionToHalfOpen(): void {
    this.state = CircuitBreakerState.HALF_OPEN;
    this.successes = 0;
    this.halfOpenAttempts = 0;
  }

  /**
   * Trim window to configured size
   */
  private trimWindow(): void {
    if (this.window.length > this.config.windowSize) {
      this.window.shift();
    }
  }

  /**
   * Get circuit breaker metrics
   */
  getMetrics(): CircuitBreakerMetrics {
    return {
      state: this.state,
      failures: this.failures,
      successes: this.successes,
      lastFailureTime: this.lastFailureTime,
      lastSuccessTime: this.lastSuccessTime,
      openedAt: this.openedAt,
      halfOpenAttempts: this.halfOpenAttempts,
    };
  }
}

export class FailoverManager extends EventEmitter {
  private logger: Logger;
  private metrics: Metrics;
  private circuitBreakers: Map<string, CircuitBreaker> = new Map();
  private failoverHistory: FailoverEvent[] = [];
  private currentFailoverChain: number = 0;
  private config: FailoverConfig;
  private initialized: boolean = false;
  private primaryRegion: string;

  constructor(config: FailoverConfig) {
    super();
    this.config = config;
    this.logger = new Logger('FailoverManager');
    this.metrics = new Metrics('failover_manager');
    this.primaryRegion = config.regions[0];
    this.initializeCircuitBreakers();
  }

  /**
   * Initialize circuit breakers for all regions
   */
  private initializeCircuitBreakers(): void {
    for (const regionId of this.config.regions) {
      this.circuitBreakers.set(
        regionId,
        new CircuitBreaker(this.config.circuitBreakerConfig)
      );
    }
  }

  /**
   * Start the failover manager
   */
  async start(): Promise<void> {
    if (this.initialized) return;

    this.logger.info('Starting failover manager', {
      regions: this.config.regions,
    });

    // Periodic recovery attempts
    setInterval(() => {
      this.attemptRecovery();
    }, 5000);

    this.initialized = true;
    this.emit('started');
  }

  /**
   * Stop the failover manager
   */
  stop(): void {
    if (!this.initialized) return;
    this.logger.info('Stopping failover manager');
    this.removeAllListeners();
    this.initialized = false;
  }

  /**
   * Record a request result for a region
   */
  recordRequest(
    regionId: string,
    success: boolean,
    latency?: number
  ): void {
    const breaker = this.circuitBreakers.get(regionId);
    if (!breaker) return;

    if (success) {
      breaker.recordSuccess();
      this.metrics.increment(`region_${regionId}_success`);
    } else {
      breaker.recordFailure();
      this.metrics.increment(`region_${regionId}_failure`);

      // Check if failover is needed
      if (!breaker.canAttempt()) {
        this.logger.warn(
          `Circuit breaker open for region ${regionId}, failover may be needed`
        );
        this.emit('circuit_opened', { regionId });
      }
    }

    if (latency) {
      this.metrics.timing(`region_${regionId}_latency`, latency);
    }
  }

  /**
   * Determine if failover is needed for a region
   */
  needsFailover(fromRegion: string): boolean {
    const breaker = this.circuitBreakers.get(fromRegion);
    if (!breaker) return false;

    const metrics = breaker.getMetrics();
    return (
      metrics.state === CircuitBreakerState.OPEN ||
      (metrics.state === CircuitBreakerState.HALF_OPEN &&
        metrics.halfOpenAttempts >=
          this.config.circuitBreakerConfig
            .successThreshold)
    );
  }

  /**
   * Execute failover from one region to another
   */
  async executeFailover(
    fromRegion: string,
    toRegion?: string
  ): Promise<string> {
    const startTime = Date.now();

    try {
      // Check failover chain length
      if (this.currentFailoverChain >= this.config.maxFailoverChain) {
        this.logger.error(
          'Max failover chain exceeded, cannot failover further'
        );
        this.metrics.increment('failover_chain_exceeded');
        throw new Error('Max failover chain exceeded');
      }

      // Select target region if not specified
      const targetRegion = toRegion || this.selectFailoverTarget(fromRegion);

      if (targetRegion === fromRegion) {
        this.logger.warn('No valid failover target found');
        this.metrics.increment('failover_no_target');
        return fromRegion;
      }

      this.currentFailoverChain++;

      const event: FailoverEvent = {
        fromRegion,
        toRegion: targetRegion,
        reason: `Circuit breaker open for ${fromRegion}`,
        timestamp: new Date(),
      };

      this.failoverHistory.push(event);
      this.metrics.increment('failovers_executed');
      this.metrics.increment(`failover_${fromRegion}_to_${targetRegion}`);

      this.logger.info('Failover executed', {
        from: fromRegion,
        to: targetRegion,
        chainLength: this.currentFailoverChain,
      });

      this.emit('failover_executed', event);

      return targetRegion;
    } catch (error) {
      this.logger.error('Failover execution failed', error);
      this.metrics.increment('failover_errors');
      throw error;
    } finally {
      this.metrics.timing('failover_execution_time', Date.now() - startTime);
    }
  }

  /**
   * Select best failover target
   */
  private selectFailoverTarget(failedRegion: string): string {
    // Score remaining regions by circuit breaker health
    const candidates: Array<{ regionId: string; score: number }> = [];

    for (const regionId of this.config.regions) {
      if (regionId === failedRegion) continue;

      const breaker = this.circuitBreakers.get(regionId)!;
      const metrics = breaker.getMetrics();

      // Score based on state: CLOSED (1.0) > HALF_OPEN (0.5) > OPEN (0.0)
      let score = 0;
      if (metrics.state === CircuitBreakerState.CLOSED) {
        score = 1.0;
      } else if (metrics.state === CircuitBreakerState.HALF_OPEN) {
        score = 0.5;
      }

      if (score > 0) {
        candidates.push({ regionId, score });
      }
    }

    if (candidates.length === 0) {
      // Fallback: least recently failed
      let leastRecentlyFailed = this.config.regions[0];
      let oldestFailTime = new Date();

      for (const regionId of this.config.regions) {
        if (regionId === failedRegion) continue;
        const breaker = this.circuitBreakers.get(regionId)!;
        const metrics = breaker.getMetrics();

        if (
          metrics.lastFailureTime === null ||
          metrics.lastFailureTime < oldestFailTime
        ) {
          leastRecentlyFailed = regionId;
          oldestFailTime = metrics.lastFailureTime || new Date(0);
        }
      }

      return leastRecentlyFailed;
    }

    // Select highest-scored region
    return candidates.sort((a, b) => b.score - a.score)[0].regionId;
  }

  /**
   * Attempt to recover failed regions
   */
  private attemptRecovery(): void {
    for (const [regionId, breaker] of this.circuitBreakers.entries()) {
      const metrics = breaker.getMetrics();

      if (metrics.state === CircuitBreakerState.HALF_OPEN) {
        this.logger.info(`Testing recovery for region ${regionId}`);
        this.emit('recovery_test', { regionId });
      }
    }
  }

  /**
   * Force recovery of a region
   */
  forceRecovery(regionId: string): void {
    const breaker = this.circuitBreakers.get(regionId);
    if (breaker) {
      breaker.recordSuccess();
      this.logger.info(`Forced recovery for region ${regionId}`);
      this.metrics.increment(`forced_recovery_${regionId}`);
      this.emit('recovery_forced', { regionId });
    }
  }

  /**
   * Get failover metrics
   */
  getMetrics(): Record<string, unknown> {
    const regionMetrics: Record<string, CircuitBreakerMetrics> = {};

    for (const [regionId, breaker] of this.circuitBreakers.entries()) {
      regionMetrics[regionId] = breaker.getMetrics();
    }

    return {
      initialized: this.initialized,
      currentFailoverChain: this.currentFailoverChain,
      totalFailovers: this.failoverHistory.length,
      regionMetrics,
      recentFailovers: this.failoverHistory.slice(-10),
      metrics: this.metrics.getMetrics(),
    };
  }

  /**
   * Get failover history
   */
  getFailoverHistory(limit: number = 100): FailoverEvent[] {
    return this.failoverHistory.slice(-limit);
  }

  /**
   * Reset failover chain (called after successful recovery)
   */
  resetFailoverChain(): void {
    this.currentFailoverChain = 0;
    this.logger.info('Failover chain reset');
  }
}
