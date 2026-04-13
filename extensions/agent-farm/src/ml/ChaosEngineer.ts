/**
 * Chaos Engineering & Resilience Testing
 * Intentional failure injection for resilience validation
 */

export type ChaosScenario = 'latency' | 'failure' | 'partial-partition' | 'cascading-failure';

export interface ChaosTest {
  id: string;
  name: string;
  scenario: ChaosScenario;
  targetServices: string[];
  duration: number; // milliseconds
  intensity: number; // 0-1 scale
  expectedBehavior: string;
  metrics: ChaosTestMetrics;
}

export interface ChaosTestMetrics {
  startTime: number;
  endTime?: number;
  testsPassed: number;
  testsFailed: number;
  systemRecovered: boolean;
  recoveryTime?: number; // milliseconds
  dataLoss: number;
  requests: {
    total: number;
    successful: number;
    failed: number;
    timedOut: number;
  };
}

export class ChaosEngineer {
  private activeTests: Map<string, ChaosTest> = new Map();
  private testHistory: ChaosTest[] = [];
  private failureSimulators: Map<string, () => void> = new Map();

  /**
   * Register a service for chaos testing
   */
  registerService(serviceName: string, failureSimulator: () => void): void {
    this.failureSimulators.set(serviceName, failureSimulator);
  }

  /**
   * Create and start a chaos test
   */
  startChaosTest(
    name: string,
    scenario: ChaosScenario,
    targetServices: string[],
    duration: number,
    intensity: number
  ): ChaosTest {
    const test: ChaosTest = {
      id: `chaos-${Date.now()}`,
      name,
      scenario,
      targetServices,
      duration,
      intensity,
      expectedBehavior: this.getExpectedBehavior(scenario),
      metrics: {
        startTime: Date.now(),
        testsPassed: 0,
        testsFailed: 0,
        systemRecovered: false,
        dataLoss: 0,
        requests: {
          total: 0,
          successful: 0,
          failed: 0,
          timedOut: 0,
        },
      },
    };

    this.activeTests.set(test.id, test);

    // Simulate failures based on scenario
    this.simulateFailures(test);

    // Schedule cleanup
    setTimeout(() => {
      this.completeChaosTest(test.id);
    }, duration);

    return test;
  }

  /**
   * Simulate failures based on chaos scenario
   */
  private simulateFailures(test: ChaosTest): void {
    for (const service of test.targetServices) {
      const failureSimulator = this.failureSimulators.get(service);
      if (!failureSimulator) continue;

      switch (test.scenario) {
        case 'latency':
          // Simulate increased latency
          this.injectLatency(service, test.intensity * 5000); // up to 5 seconds
          break;

        case 'failure':
          // Simulate service failure with probability based on intensity
          if (Math.random() < test.intensity) {
            failureSimulator();
          }
          break;

        case 'partial-partition':
          // Simulate network partition affecting subset of service
          this.injectPartialPartition(service, test.intensity);
          break;

        case 'cascading-failure':
          // Simulate cascading failure across dependent services
          this.injectCascadingFailure(test.targetServices, test.intensity);
          break;
      }
    }
  }

  /**
   * Inject latency
   */
  private injectLatency(service: string, maxDelay: number): void {
    // In real implementation: intercept service calls, add delay
  }

  /**
   * Inject partial partition
   */
  private injectPartialPartition(service: string, intensity: number): void {
    // In real implementation: drop percentage of packets equal to intensity
  }

  /**
   * Inject cascading failure
   */
  private injectCascadingFailure(services: string[], intensity: number): void {
    // In real implementation: trigger failures in dependent services
  }

  /**
   * Complete chaos test
   */
  private completeChaosTest(testId: string): void {
    const test = this.activeTests.get(testId);
    if (!test) return;

    test.metrics.endTime = Date.now();
    test.metrics.recoveryTime = test.metrics.endTime - test.metrics.startTime;

    this.activeTests.delete(testId);
    this.testHistory.push(test);
  }

  /**
   * Validate system resilience
   */
  validateResilience(test: ChaosTest): {
    passed: boolean;
    failures: string[];
  } {
    const failures: string[] = [];

    // Check if system recovered
    if (!test.metrics.systemRecovered) {
      failures.push('System did not recover after chaos test');
    }

    // Check recovery time SLA
    if ((test.metrics.recoveryTime ?? 0) > 30000) {
      // 30 second SLA
      failures.push('Recovery time exceeded SLA (> 30s)');
    }

    // Check data loss
    if (test.metrics.dataLoss > 0) {
      failures.push(`Data loss detected: ${test.metrics.dataLoss} items`);
    }

    // Check success rate
    const successRate = test.metrics.requests.total > 0
      ? test.metrics.requests.successful / test.metrics.requests.total
      : 0;

    if (successRate < 0.95) {
      // 95% success target
      failures.push(`Success rate below target: ${(successRate * 100).toFixed(2)}%`);
    }

    return {
      passed: failures.length === 0,
      failures,
    };
  }

  /**
   * Get active tests
   */
  getActiveTests(): ChaosTest[] {
    return Array.from(this.activeTests.values());
  }

  /**
   * Get test history
   */
  getTestHistory(limit: number = 50): ChaosTest[] {
    return this.testHistory.slice(-limit);
  }

  /**
   * Get expected behavior description
   */
  private getExpectedBehavior(scenario: ChaosScenario): string {
    const behaviors: Record<ChaosScenario, string> = {
      latency: 'System should handle increased latency gracefully with circuit breakers and timeouts',
      failure: 'System should failover to replicas and maintain availability',
      'partial-partition': 'System should route requests to healthy partitions',
      'cascading-failure': 'System should isolate failures and prevent cascade',
    };
    return behaviors[scenario];
  }
}
