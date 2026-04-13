/**
 * Zero-Trust Security Orchestrator
 *
 * Orchestrates all security components:
 * - Continuous authentication
 * - Real-time threat detection
 * - Forensic logging
 * - Policy enforcement
 */
import { ZeroTrustAuthenticator, type IdentityToken } from './ZeroTrustAuthenticator';
import { ThreatDetectionEngine, type AnomalySignal, ThreatLevel } from './ThreatDetectionEngine';
import { ForensicsCollector } from './ForensicsCollector';
import { SecurityPolicyEnforcer } from './SecurityPolicyEnforcer';
export interface SecurityContext {
    userId: string;
    deviceId: string;
    ipAddress: string;
    userAgent: string;
    timestamp: Date;
}
export interface AccessRequest {
    principal: string;
    principalType: 'user' | 'group' | 'role' | 'service';
    action: string;
    resource: string;
    context: SecurityContext;
}
export interface SecurityDecision {
    allowed: boolean;
    riskScore: number;
    threatLevel: ThreatLevel;
    requiresMFA: boolean;
    reason: string;
    token?: IdentityToken;
    threatAnomalies: AnomalySignal[];
}
export interface SecurityStatus {
    authenticator: {
        activeDevices: number;
        activeTokens: number;
        successRate: number;
        mfaRequiredCount: number;
    };
    threatDetection: {
        totalAnomalies: number;
        criticalThreats: number;
        highPriorityThreats: number;
    };
    forensics: {
        totalEvents: number;
        activeCases: number;
        criticalEvents: number;
    };
    policies: {
        totalPolicies: number;
        enabledPolicies: number;
        allowDecisions: number;
        denyDecisions: number;
    };
}
/**
 * ZeroTrustSecurityOrchestrator - Master security orchestrator
 *
 * Coordinates all security components:
 * 1. Continuous authentication (ZeroTrustAuthenticator)
 * 2. Real-time threat detection (ThreatDetectionEngine)
 * 3. Forensic logging (ForensicsCollector)
 * 4. Policy enforcement (SecurityPolicyEnforcer)
 *
 * Zero-Trust Principles:
 * - Never trust, always verify
 * - Assume breach
 * - Continuous authentication
 * - Risk-based access control
 * - Full audit trails
 */
export declare class ZeroTrustSecurityOrchestrator {
    private authenticator;
    private threatDetection;
    private forensics;
    private policyEnforcer;
    constructor();
    /**
     * Process security decision for access request
     * Implements full zero-trust workflow
     */
    processAccessRequest(request: AccessRequest): Promise<SecurityDecision>;
    /**
     * Get threat level from anomalies
     */
    private getThreatLevel;
    /**
     * Get overall security status
     */
    getSecurityStatus(): SecurityStatus;
    /**
     * Get composite security report
     */
    getSecurityReport(periodHours?: number): {
        period: string;
        status: SecurityStatus;
        recommendations: string[];
        criticalFindings: string[];
    };
    /**
     * Access authenticator
     */
    getAuthenticator(): ZeroTrustAuthenticator;
    /**
     * Access threat detection
     */
    getThreatDetection(): ThreatDetectionEngine;
    /**
     * Access forensics
     */
    getForensics(): ForensicsCollector;
    /**
     * Access policy enforcer
     */
    getPolicyEnforcer(): SecurityPolicyEnforcer;
}
//# sourceMappingURL=ZeroTrustSecurityOrchestrator.d.ts.map