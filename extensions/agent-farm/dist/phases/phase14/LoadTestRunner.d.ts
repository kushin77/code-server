/**
 * Load Testing and Performance Analysis
 *
 * Performance benchmarking and load testing tools:
 * - Throughput testing
 * - Latency measurement
 * - Resource usage analysis
 * - Stress testing utilities
 */
export interface LoadTestResult {
    testName: string;
    duration: number;
    totalOperations: number;
    successfulOperations: number;
    failedOperations: number;
    throughput: number;
    avgLatency: number;
    p50Latency: number;
    p95Latency: number;
    p99Latency: number;
    maxLatency: number;
    errorRate: number;
}
export interface MemoryProfile {
    name: string;
    initialMemory: number;
    peakMemory: number;
    finalMemory: number;
    leakDetected: boolean;
    memoryGrowthRate: number;
}
/**
 * LoadTestRunner - Performance and load testing
 */
export declare class LoadTestRunner {
    /**
     * Run throughput test
     */
    static runThroughputTest(name: string, operation: () => void | Promise<void>, duration?: number): LoadTestResult;
    /**
     * Run latency test (measure response times under load)
     */
    static runLatencyTest(name: string, operation: () => void, concurrency?: number, iterations?: number): LoadTestResult;
    /**
     * Run stress test (increase load until failure)
     */
    static runStressTest(name: string, operation: () => void, maxConcurrency?: number, stepSize?: number): LoadTestResult[];
    /**
     * Measure memory usage
     */
    static measureMemoryProfile(name: string, operation: () => void): MemoryProfile;
    /**
     * Run load test and validate SLOs
     */
    static validateLoadTestSLOs(result: LoadTestResult, slos: {
        minThroughput?: number;
        maxP99Latency?: number;
        maxErrorRate?: number;
    }): {
        passed: boolean;
        violations: string[];
    };
    /**
     * Generate load test report
     */
    static generateLoadTestReport(results: LoadTestResult[]): string;
}
/**
 * Integration Load Test - Test multi-component interaction
 */
export declare class IntegrationLoadTest {
    /**
     * Simulate authentication workflow under load
     */
    static testAuthenticationWorkflowLoad(concurrentUsers?: number): LoadTestResult;
    /**
     * Simulate threat detection under load
     */
    static testThreatDetectionLoad(eventRate?: number): LoadTestResult;
    /**
     * Simulate policy evaluation under load
     */
    static testPolicyEvaluationLoad(concurrentRequests?: number): LoadTestResult;
    /**
     * Run all integration load tests
     */
    static runAllIntegrationTests(): {
        authLoad: LoadTestResult;
        threatLoad: LoadTestResult;
        policyLoad: LoadTestResult;
    };
}
//# sourceMappingURL=LoadTestRunner.d.ts.map
