/**
 * Test Utilities and Helpers
 *
 * Provides common testing infrastructure:
 * - Test data generators
 * - Mock/stub utilities
 * - Assertion helpers
 * - Performance measurement tools
 */

export interface TestResult {
  name: string;
  passed: boolean;
  duration: number;  // milliseconds
  error?: string;
  assertions: number;
  skipped: boolean;
}

export interface TestSuite {
  name: string;
  tests: TestResult[];
  totalTests: number;
  passedTests: number;
  failedTests: number;
  skippedTests: number;
  totalDuration: number;
  successRate: number;
}

export interface PerformanceBenchmark {
  name: string;
  iterations: number;
  avgTime: number;  // ms
  minTime: number;
  maxTime: number;
  stdDev: number;
  throughput: number;  // ops/second
}

/**
 * TestHelper - Utilities for testing
 */
export class TestHelper {
  private static testResults: TestResult[] = [];
  private static performanceMetrics: Map<string, number[]> = new Map();

  /**
   * Generate random user ID
   */
  static generateUserId(): string {
    return `user_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Generate random device ID
   */
  static generateDeviceId(): string {
    return `device_${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Generate random IP address
   */
  static generateIpAddress(): string {
    return `203.0.${Math.floor(Math.random() * 256)}.${Math.floor(Math.random() * 256)}`;
  }

  /**
   * Generate random email
   */
  static generateEmail(): string {
    return `test_${Date.now()}_${Math.random().toString(36).substr(2, 5)}@example.com`;
  }

  /**
   * Create mock authentication context
   */
  static createMockAuthContext() {
    return {
      userId: this.generateUserId(),
      deviceId: this.generateDeviceId(),
      timestamp: new Date(),
      requestHash: `hash_${Math.random().toString(36).substr(2, 9)}`,
      ipAddress: this.generateIpAddress(),
      userAgent: 'Mozilla/5.0 (Test) AppleWebKit/537.36'
    };
  }

  /**
   * Create mock security event
   */
  static createMockSecurityEvent(action: string = 'login', result: 'success' | 'failure' = 'success') {
    return {
      eventId: `event_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      timestamp: new Date(),
      userId: this.generateUserId(),
      deviceId: this.generateDeviceId(),
      action,
      resource: 'api/resource',
      result,
      metadata: {
        ipAddress: this.generateIpAddress(),
        userAgent: 'Mozilla/5.0 (Test)'
      }
    };
  }

  /**
   * Assert condition is true
   */
  static assert(condition: boolean, message: string): void {
    if (!condition) {
      throw new Error(`Assertion failed: ${message}`);
    }
  }

  /**
   * Assert two values are equal
   */
  static assertEqual<T>(actual: T, expected: T, message?: string): void {
    if (actual !== expected) {
      throw new Error(
        `Assertion failed: ${message || `Expected ${expected}, got ${actual}`}`
      );
    }
  }

  /**
   * Assert value is truthy
   */
  static assertTrue(value: any, message?: string): void {
    if (!value) {
      throw new Error(`Assertion failed: ${message || 'Expected truthy value'}`);
    }
  }

  /**
   * Assert value is falsy
   */
  static assertFalse(value: any, message?: string): void {
    if (value) {
      throw new Error(`Assertion failed: ${message || 'Expected falsy value'}`);
    }
  }

  /**
   * Assert array includes value
   */
  static assertIncludes<T>(array: T[], value: T, message?: string): void {
    if (!array.includes(value)) {
      throw new Error(
        `Assertion failed: ${message || `Expected array to include ${value}`}`
      );
    }
  }

  /**
   * Assert array length
   */
  static assertLength(array: any[], length: number, message?: string): void {
    if (array.length !== length) {
      throw new Error(
        `Assertion failed: ${message || `Expected length ${length}, got ${array.length}`}`
      );
    }
  }

  /**
   * Measure function execution time
   */
  static measureTime(fn: () => void): number {
    const start = performance.now();
    fn();
    const end = performance.now();
    return Math.round((end - start) * 1000) / 1000;  // ms with 3 decimals
  }

  /**
   * Measure async function execution time
   */
  static async measureTimeAsync(fn: () => Promise<void>): Promise<number> {
    const start = performance.now();
    await fn();
    const end = performance.now();
    return Math.round((end - start) * 1000) / 1000;
  }

  /**
   * Record test result
   */
  static recordTest(result: TestResult): void {
    this.testResults.push(result);
  }

  /**
   * Record performance metric
   */
  static recordMetric(name: string, value: number): void {
    if (!this.performanceMetrics.has(name)) {
      this.performanceMetrics.set(name, []);
    }
    this.performanceMetrics.get(name)!.push(value);
  }

  /**
   * Get test summary
   */
  static getTestSummary(): TestSuite {
    const passed = this.testResults.filter((t) => t.passed && !t.skipped).length;
    const failed = this.testResults.filter((t) => !t.passed && !t.skipped).length;
    const skipped = this.testResults.filter((t) => t.skipped).length;
    const total = this.testResults.length;
    const duration = this.testResults.reduce((sum, t) => sum + t.duration, 0);

    return {
      name: 'Test Summary',
      tests: this.testResults,
      totalTests: total,
      passedTests: passed,
      failedTests: failed,
      skippedTests: skipped,
      totalDuration: duration,
      successRate: total > 0 ? (passed / (total - skipped)) * 100 : 0
    };
  }

  /**
   * Get performance benchmark summary
   */
  static getBenchmarkSummary(): PerformanceBenchmark[] {
    const benchmarks: PerformanceBenchmark[] = [];

    for (const [name, metrics] of this.performanceMetrics) {
      if (metrics.length === 0) continue;

      const sortedMetrics = metrics.sort((a, b) => a - b);
      const avg = metrics.reduce((sum, m) => sum + m, 0) / metrics.length;
      const variance = metrics.reduce((sum, m) => sum + Math.pow(m - avg, 2), 0) / metrics.length;
      const stdDev = Math.sqrt(variance);

      benchmarks.push({
        name,
        iterations: metrics.length,
        avgTime: Math.round(avg * 1000) / 1000,
        minTime: sortedMetrics[0],
        maxTime: sortedMetrics[sortedMetrics.length - 1],
        stdDev: Math.round(stdDev * 1000) / 1000,
        throughput: Math.round((1000 / avg) * 100) / 100  // ops/second
      });
    }

    return benchmarks;
  }

  /**
   * Clear test results
   */
  static clearResults(): void {
    this.testResults = [];
    this.performanceMetrics.clear();
  }

  /**
   * Run test function and record result
   */
  static runTest(name: string, fn: () => void): TestResult {
    const startTime = performance.now();
    let passed = false;
    let error: string | undefined;
    let assertions = 0;

    try {
      fn();
      passed = true;
    } catch (e) {
      passed = false;
      error = e instanceof Error ? e.message : String(e);
    }

    const duration = Math.round((performance.now() - startTime) * 1000) / 1000;

    const result: TestResult = {
      name,
      passed,
      duration,
      error,
      assertions,
      skipped: false
    };

    this.recordTest(result);
    return result;
  }

  /**
   * Run async test function
   */
  static async runTestAsync(name: string, fn: () => Promise<void>): Promise<TestResult> {
    const startTime = performance.now();
    let passed = false;
    let error: string | undefined;

    try {
      await fn();
      passed = true;
    } catch (e) {
      passed = false;
      error = e instanceof Error ? e.message : String(e);
    }

    const duration = Math.round((performance.now() - startTime) * 1000) / 1000;

    const result: TestResult = {
      name,
      passed,
      duration,
      error,
      assertions: 0,
      skipped: false
    };

    this.recordTest(result);
    return result;
  }

  /**
   * Run benchmark
   */
  static benchmark(name: string, fn: () => void, iterations: number = 1000): PerformanceBenchmark {
    for (let i = 0; i < iterations; i++) {
      const duration = this.measureTime(fn);
      this.recordMetric(name, duration);
    }

    const benchmarks = this.getBenchmarkSummary();
    return benchmarks.find((b) => b.name === name)!;
  }

  /**
   * Generate test data batch
   */
  static generateTestBatch(size: number = 100, template?: Record<string, any>) {
    const batch = [];

    for (let i = 0; i < size; i++) {
      batch.push({
        id: `item_${i}`,
        timestamp: new Date(Date.now() - Math.random() * 86400000),  // Last 24 hours
        ...template
      });
    }

    return batch;
  }
}
