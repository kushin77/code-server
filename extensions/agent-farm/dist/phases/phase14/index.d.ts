/**
 * Phase 14: Testing & Hardening
 *
 * This module provides comprehensive testing and validation infrastructure:
 * - Test utilities and helpers
 * - Security validation test suites
 * - Load and performance testing
 * - Integration test frameworks
 * - Comprehensive test reporting and coordination
 */
export { TestHelper, type TestResult, type TestSuite, type PerformanceBenchmark } from './TestHelper';
export { SecurityValidationTests, type SecurityTestResults } from './SecurityValidationTests';
export { LoadTestRunner, IntegrationLoadTest, type LoadTestResult, type MemoryProfile } from './LoadTestRunner';
export { IntegrationTestSuite, generateIntegrationTestReport, type IntegrationTestResults } from './IntegrationTestSuite';
export { TestOrchestrator, type ComprehensiveTestResults, type TestSummary, type SLOValidation } from './TestOrchestrator';
//# sourceMappingURL=index.d.ts.map