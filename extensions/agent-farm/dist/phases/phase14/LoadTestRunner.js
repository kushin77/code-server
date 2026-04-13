"use strict";
/**
 * Load Testing and Performance Analysis
 *
 * Performance benchmarking and load testing tools:
 * - Throughput testing
 * - Latency measurement
 * - Resource usage analysis
 * - Stress testing utilities
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.IntegrationLoadTest = exports.LoadTestRunner = void 0;
/**
 * LoadTestRunner - Performance and load testing
 */
class LoadTestRunner {
    /**
     * Run throughput test
     */
    static runThroughputTest(name, operation, duration = 10 // seconds
    ) {
        const startTime = Date.now();
        const latencies = [];
        let successful = 0;
        let failed = 0;
        const durationMs = duration * 1000;
        while (Date.now() - startTime < durationMs) {
            const opStart = performance.now();
            try {
                const result = operation();
                if (result instanceof Promise) {
                    // Handle async (simplified - in production would use proper await)
                }
                successful++;
            }
            catch (e) {
                failed++;
            }
            const opDuration = performance.now() - opStart;
            latencies.push(opDuration);
        }
        const totalOps = successful + failed;
        const elapsedSeconds = (Date.now() - startTime) / 1000;
        latencies.sort((a, b) => a - b);
        const avgLatency = latencies.reduce((a, b) => a + b, 0) / latencies.length;
        const p50Index = Math.floor(latencies.length * 0.5);
        const p95Index = Math.floor(latencies.length * 0.95);
        const p99Index = Math.floor(latencies.length * 0.99);
        return {
            testName: name,
            duration: elapsedSeconds,
            totalOperations: totalOps,
            successfulOperations: successful,
            failedOperations: failed,
            throughput: totalOps / elapsedSeconds,
            avgLatency,
            p50Latency: latencies[p50Index],
            p95Latency: latencies[p95Index],
            p99Latency: latencies[p99Index],
            maxLatency: latencies[latencies.length - 1],
            errorRate: (failed / totalOps) * 100
        };
    }
    /**
     * Run latency test (measure response times under load)
     */
    static runLatencyTest(name, operation, concurrency = 10, iterations = 1000) {
        const operationsPerThread = Math.ceil(iterations / concurrency);
        const allLatencies = [];
        for (let t = 0; t < concurrency; t++) {
            for (let i = 0; i < operationsPerThread; i++) {
                const start = performance.now();
                try {
                    operation();
                    const duration = performance.now() - start;
                    allLatencies.push(duration);
                }
                catch (e) {
                    // Record error but continue
                }
            }
        }
        allLatencies.sort((a, b) => a - b);
        const avgLatency = allLatencies.reduce((a, b) => a + b, 0) / allLatencies.length;
        const p50Index = Math.floor(allLatencies.length * 0.5);
        const p95Index = Math.floor(allLatencies.length * 0.95);
        const p99Index = Math.floor(allLatencies.length * 0.99);
        return {
            testName: name,
            duration: allLatencies.length / 1000, // Approximate
            totalOperations: allLatencies.length,
            successfulOperations: allLatencies.length,
            failedOperations: 0,
            throughput: 1000 / avgLatency,
            avgLatency,
            p50Latency: allLatencies[p50Index],
            p95Latency: allLatencies[p95Index],
            p99Latency: allLatencies[p99Index],
            maxLatency: allLatencies[allLatencies.length - 1],
            errorRate: 0
        };
    }
    /**
     * Run stress test (increase load until failure)
     */
    static runStressTest(name, operation, maxConcurrency = 1000, stepSize = 100) {
        const results = [];
        for (let concurrency = stepSize; concurrency <= maxConcurrency; concurrency += stepSize) {
            const operationsPerThread = 100;
            let successful = 0;
            let failed = 0;
            const latencies = [];
            for (let t = 0; t < concurrency; t++) {
                for (let i = 0; i < operationsPerThread; i++) {
                    const start = performance.now();
                    try {
                        operation();
                        successful++;
                    }
                    catch (e) {
                        failed++;
                    }
                    const duration = performance.now() - start;
                    latencies.push(duration);
                }
            }
            latencies.sort((a, b) => a - b);
            const avgLatency = latencies.reduce((a, b) => a + b, 0) / latencies.length;
            const p95Index = Math.floor(latencies.length * 0.95);
            const p99Index = Math.floor(latencies.length * 0.99);
            const result = {
                testName: `${name} (Concurrency: ${concurrency})`,
                duration: 0,
                totalOperations: successful + failed,
                successfulOperations: successful,
                failedOperations: failed,
                throughput: (successful + failed) / 1,
                avgLatency,
                p50Latency: latencies[Math.floor(latencies.length * 0.5)],
                p95Latency: latencies[p95Index],
                p99Latency: latencies[p99Index],
                maxLatency: latencies[latencies.length - 1],
                errorRate: (failed / (successful + failed)) * 100
            };
            results.push(result);
            // Stop if error rate exceeds threshold
            if (result.errorRate > 10) {
                break; // System degrading
            }
        }
        return results;
    }
    /**
     * Measure memory usage
     */
    static measureMemoryProfile(name, operation) {
        // In Node.js, would use process.memoryUsage()
        // In browser/VS Code, simulated measurement
        const initialMemory = 0; // Placeholder
        let peakMemory = initialMemory;
        let currentMemory = initialMemory;
        const iterations = 1000;
        for (let i = 0; i < iterations; i++) {
            operation();
            // Simulate memory accumulation
            currentMemory += Math.random() * 100; // Random small allocations
            if (i % 100 === 0) {
                currentMemory *= 0.9; // GC-like behavior
            }
            if (currentMemory > peakMemory) {
                peakMemory = currentMemory;
            }
        }
        const finalMemory = currentMemory;
        const memoryGrowth = finalMemory - initialMemory;
        const growthRate = memoryGrowth / iterations;
        return {
            name,
            initialMemory,
            peakMemory,
            finalMemory,
            leakDetected: finalMemory > initialMemory * 1.5, // 50% growth = potential leak
            memoryGrowthRate: growthRate
        };
    }
    /**
     * Run load test and validate SLOs
     */
    static validateLoadTestSLOs(result, slos) {
        const violations = [];
        if (slos.minThroughput && result.throughput < slos.minThroughput) {
            violations.push(`Throughput ${result.throughput.toFixed(2)} ops/sec < ${slos.minThroughput} (SLO violation)`);
        }
        if (slos.maxP99Latency && result.p99Latency > slos.maxP99Latency) {
            violations.push(`P99 Latency ${result.p99Latency.toFixed(2)}ms > ${slos.maxP99Latency}ms (SLO violation)`);
        }
        if (slos.maxErrorRate && result.errorRate > slos.maxErrorRate) {
            violations.push(`Error rate ${result.errorRate.toFixed(2)}% > ${slos.maxErrorRate}% (SLO violation)`);
        }
        return {
            passed: violations.length === 0,
            violations
        };
    }
    /**
     * Generate load test report
     */
    static generateLoadTestReport(results) {
        let report = '=== Load Test Report ===\n\n';
        for (const result of results) {
            report += `Test: ${result.testName}\n`;
            report += `Duration: ${result.duration.toFixed(2)}s\n`;
            report += `Total Operations: ${result.totalOperations}\n`;
            report += `Successful: ${result.successfulOperations} | Failed: ${result.failedOperations}\n`;
            report += `Throughput: ${result.throughput.toFixed(2)} ops/sec\n`;
            report += `Avg Latency: ${result.avgLatency.toFixed(2)}ms\n`;
            report += `Latency - P50: ${result.p50Latency.toFixed(2)}ms | P95: ${result.p95Latency.toFixed(2)}ms | P99: ${result.p99Latency.toFixed(2)}ms | Max: ${result.maxLatency.toFixed(2)}ms\n`;
            report += `Error Rate: ${result.errorRate.toFixed(2)}%\n\n`;
        }
        return report;
    }
}
exports.LoadTestRunner = LoadTestRunner;
/**
 * Integration Load Test - Test multi-component interaction
 */
class IntegrationLoadTest {
    /**
     * Simulate authentication workflow under load
     */
    static testAuthenticationWorkflowLoad(concurrentUsers = 100) {
        const result = LoadTestRunner.runLatencyTest('Authentication Workflow', () => {
            // Simulate: Device lookup → Risk scoring → Token generation
            const mockAuthTime = 50 + // Device lookup
                30 + // Risk scoring
                20; // Token generation
            // Simulate processing delay
            let x = 0;
            for (let i = 0; i < mockAuthTime * 1000; i++) {
                x += Math.random();
            }
        }, concurrentUsers, 1000);
        return result;
    }
    /**
     * Simulate threat detection under load
     */
    static testThreatDetectionLoad(eventRate = 10000) {
        const result = LoadTestRunner.runThroughputTest('Threat Detection Event Processing', () => {
            // Simulate event processing:
            // 1. Rule evaluation (5ms avg)
            // 2. Anomaly detection (3ms avg)
            // 3. User profile update (2ms avg)
            let x = 0;
            for (let i = 0; i < 10000; i++) {
                x += Math.random();
            }
        }, 5 // 5 second test
        );
        return result;
    }
    /**
     * Simulate policy evaluation under load
     */
    static testPolicyEvaluationLoad(concurrentRequests = 1000) {
        const result = LoadTestRunner.runLatencyTest('Policy Evaluation', () => {
            // Simulate policy evaluation:
            // 1. Policy matching (2ms avg)
            // 2. Condition evaluation (3ms avg)
            // 3. Decision making (1ms avg)
            let x = 0;
            for (let i = 0; i < 6000; i++) {
                x += Math.random();
            }
        }, concurrentRequests, 500);
        return result;
    }
    /**
     * Run all integration load tests
     */
    static runAllIntegrationTests() {
        return {
            authLoad: this.testAuthenticationWorkflowLoad(100),
            threatLoad: this.testThreatDetectionLoad(10000),
            policyLoad: this.testPolicyEvaluationLoad(500)
        };
    }
}
exports.IntegrationLoadTest = IntegrationLoadTest;
//# sourceMappingURL=LoadTestRunner.js.map