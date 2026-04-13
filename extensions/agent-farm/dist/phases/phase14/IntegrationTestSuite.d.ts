/**
 * Integration Test Suites
 *
 * Tests for all major components across phases:
 * - Phase 11: HA/DR System
 * - Phase 12: Multi-Site Federation
 * - Phase 13: Zero-Trust Security
 */
import { type TestResult } from './TestHelper';
export interface IntegrationTestResults {
    phase11Tests: TestResult[];
    phase12Tests: TestResult[];
    phase13Tests: TestResult[];
    totalTests: number;
    passedTests: number;
    failureRate: number;
}
/**
 * IntegrationTestSuite - Comprehensive integration tests
 */
export declare class IntegrationTestSuite {
    /**
     * Test Phase 11: HA/DR System
     */
    static testHADRSystem(): TestResult[];
    /**
     * Test Phase 12: Multi-Site Federation
     */
    static testMultiSiteFederation(): TestResult[];
    /**
     * Test Phase 13: Zero-Trust Security
     */
    static testZeroTrustSecurity(): TestResult[];
    /**
     * Run all integration tests
     */
    static runAllIntegrationTests(): IntegrationTestResults;
}
/**
 * Generate integration test report
 */
export declare function generateIntegrationTestReport(results: IntegrationTestResults): string;
//# sourceMappingURL=IntegrationTestSuite.d.ts.map