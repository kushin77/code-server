/**
 * Circuit Breaker Pattern Implementation
 * Prevents cascading failures in distributed systems
 */

export type CircuitState = 'CLOSED' | 'OPEN' | 'HALF_OPEN';

export interface CircuitBreakerConfig {
  name: string;
  failureThreshold: number; // number of failures before opening
  resetTimeout: number; // milliseconds before attempting recovery
  halfOpenRequests: number; // requests allowed in half-open state
  monitoringWindow: number; // milliseconds for monitoring period
}

export interface CircuitBreakerMetrics {
  state: CircuitState;
  totalRequests: number;
  successfulRequests: number;
  failedRequests: number;
  rejectedRequests: number;
  lastFailureTime?: number;
  lastSuccessTime?: number;
  stateChangedAt: number;
}

export class CircuitBreaker {
  private config: CircuitBreakerConfig;
  private state: CircuitState = 'CLOSED';
  private metrics: CircuitBreakerMetrics;
  private failureCount = 0;
  private successCount = 0;
  private lastFailureTime?: number;
  private resetTimer?: NodeJS.Timeout;
  private windowStartTime: number;

  constructor(config: CircuitBreakerConfig) {
    this.config = config;
    this.windowStartTime = Date.now();
    this.metrics = {
      state: 'CLOSED',
      totalRequests: 0,
      successfulRequests: 0,
      failedRequests: 0,
      rejectedRequests: 0,
      stateChangedAt: Date.now(),
    };
  }

  /**
   * Execute function with circuit breaker protection
   */
  async execute<T>(fn: () => Promise<T>): Promise<T> {
    // Check if state reset is due
    this.checkStateReset();

    if (this.state === 'OPEN') {
      this.metrics.rejectedRequests++;
      throw new Error(`Circuit breaker ${this.config.name} is OPEN`);
    }

    if (this.state === 'HALF_OPEN' && this.successCount >= this.config.halfOpenRequests) {
      // Half-open has had enough successes, transition to closed
      this.transitionToClosed();
    }

    try {
      this.metrics.totalRequests++;
      const result = await fn();
      this.recordSuccess();
      return result;
    } catch (error) {
      this.recordFailure();
      throw error;
    }
  }

  /**
   * Record successful request
   */
  private recordSuccess(): void {
    this.metrics.successfulRequests++;
    this.successCount++;
    this.metrics.lastSuccessTime = Date.now();

    if (this.state === 'HALF_OPEN') {
      // Half-open transitioning based on success
      if (this.successCount >= this.config.halfOpenRequests) {
        this.transitionToClosed();
      }
    } else if (this.state === 'CLOSED') {
      // Reset failure count on success
      this.failureCount = 0;
    }
  }

  /**
   * Record failed request
   */
  private recordFailure(): void {
    this.metrics.failedRequests++;
    this.failureCount++;
    this.lastFailureTime = Date.now();
    this.metrics.lastFailureTime = this.lastFailureTime;

    if (this.state === 'HALF_OPEN') {
      // Any failure in half-open goes back to open
      this.transitionToOpen();
    } else if (this.state === 'CLOSED' && this.failureCount >= this.config.failureThreshold) {
      this.transitionToOpen();
    }
  }

  /**
   * Transition to OPEN state
   */
  private transitionToOpen(): void {
    this.state = 'OPEN';
    this.metrics.state = 'OPEN';
    this.metrics.stateChangedAt = Date.now();
    this.successCount = 0;

    // Schedule reset after timeout
    if (this.resetTimer) {
      clearTimeout(this.resetTimer);
    }
    this.resetTimer = setTimeout(() => {
      this.transitionToHalfOpen();
    }, this.config.resetTimeout);
  }

  /**
   * Transition to HALF_OPEN state
   */
  private transitionToHalfOpen(): void {
    this.state = 'HALF_OPEN';
    this.metrics.state = 'HALF_OPEN';
    this.metrics.stateChangedAt = Date.now();
    this.failureCount = 0;
    this.successCount = 0;
  }

  /**
   * Transition to CLOSED state
   */
  private transitionToClosed(): void {
    this.state = 'CLOSED';
    this.metrics.state = 'CLOSED';
    this.metrics.stateChangedAt = Date.now();
    this.failureCount = 0;
    this.successCount = 0;

    if (this.resetTimer) {
      clearTimeout(this.resetTimer);
      this.resetTimer = undefined;
    }
  }

  /**
   * Check if state reset is due based on monitoring window
   */
  private checkStateReset(): void {
    const now = Date.now();
    if (now - this.windowStartTime > this.config.monitoringWindow) {
      // Reset window
      this.windowStartTime = now;
      this.failureCount = 0;
      this.successCount = 0;
    }
  }

  /**
   * Get current metrics
   */
  getMetrics(): CircuitBreakerMetrics {
    return { ...this.metrics };
  }

  /**
   * Get current state
   */
  getState(): CircuitState {
    return this.state;
  }

  /**
   * Manual reset (for testing/operations)
   */
  reset(): void {
    this.transitionToClosed();
  }

  /**
   * Destroy and cleanup
   */
  destroy(): void {
    if (this.resetTimer) {
      clearTimeout(this.resetTimer);
    }
  }
}
