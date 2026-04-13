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
    duration: number;
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
    avgTime: number;
    minTime: number;
    maxTime: number;
    stdDev: number;
    throughput: number;
}
/**
 * TestHelper - Utilities for testing
 */
export declare class TestHelper {
    private static testResults;
    private static performanceMetrics;
    /**
     * Generate random user ID
     */
    static generateUserId(): string;
    /**
     * Generate random device ID
     */
    static generateDeviceId(): string;
    /**
     * Generate random IP address
     */
    static generateIpAddress(): string;
    /**
     * Generate random email
     */
    static generateEmail(): string;
    /**
     * Create mock authentication context
     */
    static createMockAuthContext(): {
        userId: string;
        deviceId: string;
        timestamp: Date;
        requestHash: string;
        ipAddress: string;
        userAgent: string;
    };
    /**
     * Create mock security event
     */
    static createMockSecurityEvent(action?: string, result?: 'success' | 'failure'): {
        eventId: string;
        timestamp: Date;
        userId: string;
        deviceId: string;
        action: string;
        resource: string;
        result: "failure" | "success";
        metadata: {
            ipAddress: string;
            userAgent: string;
        };
    };
    /**
     * Assert condition is true
     */
    static assert(condition: boolean, message: string): void;
    /**
     * Assert two values are equal
     */
    static assertEqual<T>(actual: T, expected: T, message?: string): void;
    /**
     * Assert value is truthy
     */
    static assertTrue(value: any, message?: string): void;
    /**
     * Assert value is falsy
     */
    static assertFalse(value: any, message?: string): void;
    /**
     * Assert array includes value
     */
    static assertIncludes<T>(array: T[], value: T, message?: string): void;
    /**
     * Assert array length
     */
    static assertLength(array: any[], length: number, message?: string): void;
    /**
     * Measure function execution time
     */
    static measureTime(fn: () => void): number;
    /**
     * Measure async function execution time
     */
    static measureTimeAsync(fn: () => Promise<void>): Promise<number>;
    /**
     * Record test result
     */
    static recordTest(result: TestResult): void;
    /**
     * Record performance metric
     */
    static recordMetric(name: string, value: number): void;
    /**
     * Get test summary
     */
    static getTestSummary(): TestSuite;
    /**
     * Get performance benchmark summary
     */
    static getBenchmarkSummary(): PerformanceBenchmark[];
    /**
     * Clear test results
     */
    static clearResults(): void;
    /**
     * Run test function and record result
     */
    static runTest(name: string, fn: () => void): TestResult;
    /**
     * Run async test function
     */
    static runTestAsync(name: string, fn: () => Promise<void>): Promise<TestResult>;
    /**
     * Run benchmark
     */
    static benchmark(name: string, fn: () => void, iterations?: number): PerformanceBenchmark;
    /**
     * Generate test data batch
     */
    static generateTestBatch(size?: number, template?: Record<string, any>): {
        id: string;
        timestamp: Date;
    }[];
}
//# sourceMappingURL=TestHelper.d.ts.map
