/**
 * Test Orchestrator and Reporting
 *
 * Master test runner coordinating all test phases:
 * - Security validation
 * - Performance testing
 * - Integration testing
 * - Comprehensive reporting
 */
import { type SecurityTestResults } from './SecurityValidationTests';
import { type LoadTestResult } from './LoadTestRunner';
import { type IntegrationTestResults } from './IntegrationTestSuite';
export interface ComprehensiveTestResults {
    timestamp: Date;
    totalDuration: number;
    securityValidation: SecurityTestResults;
    integrationTests: IntegrationTestResults;
    performanceTests: {
        authLoad: LoadTestResult;
        threatLoad: LoadTestResult;
        policyLoad: LoadTestResult;
    };
    summary: TestSummary;
}
export interface TestSummary {
    totalTestCases: number;
    passedTests: number;
    failedTests: number;
    skippedTests: number;
    successRate: number;
    overallStatus: 'PASS' | 'FAIL' | 'DEGRADED';
    recommendations: string[];
    sloValidation: SLOValidation;
}
export interface SLOValidation {
    authLatency: {
        target: number;
        actual: number;
        met: boolean;
    };
    policyEval: {
        target: number;
        actual: number;
        met: boolean;
    };
    threatDetection: {
        target: number;
        actual: number;
        met: boolean;
    };
    dataExfiltration: {
        target: string;
        actual: string;
        met: boolean;
    };
    overallSLOMet: boolean;
}
/**
 * TestOrchestrator - Master test coordinator and reporter
 */
export declare class TestOrchestrator {
    /**
     * Run comprehensive test suite
     */
    static runComprehensiveTests(): Promise<ComprehensiveTestResults>;
    /**
     * Validate SLOs
     */
    private static validateSLOs;
    /**
     * Generate comprehensive test summary
     */
    private static generateTestSummary;
    /**
     * Generate comprehensive test report
     */
    static generateComprehensiveReport(results: ComprehensiveTestResults): string;
}
//# sourceMappingURL=TestOrchestrator.d.ts.map
