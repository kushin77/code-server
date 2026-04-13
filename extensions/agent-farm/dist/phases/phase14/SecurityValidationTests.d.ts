/**
 * Security Validation Tests
 *
 * Comprehensive tests for zero-trust security components:
 * - Authentication security
 * - Threat detection accuracy
 * - Policy enforcement correctness
 * - Forensic logging integrity
 */
import { type TestResult } from './TestHelper';
export interface SecurityTestResults {
    authenticatorTests: TestResult[];
    threatDetectionTests: TestResult[];
    policyEnforcementTests: TestResult[];
    forensicTests: TestResult[];
    overallScore: number;
}
/**
 * SecurityValidationTests - Test suite for security components
 */
export declare class SecurityValidationTests {
    /**
     * Test authentication risk scoring
     */
    static testAuthenticationRiskScoring(): TestResult;
    /**
     * Test impossible travel detection
     */
    static testImpossibleTravelDetection(): TestResult;
    /**
     * Test threat detection accuracy
     */
    static testThreatDetectionAccuracy(): TestResult;
    /**
     * Test policy evaluation correctness
     */
    static testPolicyEvaluation(): TestResult;
    /**
     * Test forensic log integrity
     */
    static testForensicLogIntegrity(): TestResult;
    /**
     * Test MFA requirement accuracy
     */
    static testMFARequirementAccuracy(): TestResult;
    /**
     * Test privilege escalation prevention
     */
    static testPrivilegeEscalationPrevention(): TestResult;
    /**
     * Test data exfiltration prevention
     */
    static testDataExfiltrationPrevention(): TestResult;
    /**
     * Run all security validation tests
     */
    static runAllTests(): SecurityTestResults;
}
//# sourceMappingURL=SecurityValidationTests.d.ts.map
