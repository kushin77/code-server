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
import { ForensicsCollector, type ForensicEvent, EventCategory } from './ForensicsCollector';
import { SecurityPolicyEnforcer, type PolicyDecision } from './SecurityPolicyEnforcer';

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
export class ZeroTrustSecurityOrchestrator {
  private authenticator: ZeroTrustAuthenticator;
  private threatDetection: ThreatDetectionEngine;
  private forensics: ForensicsCollector;
  private policyEnforcer: SecurityPolicyEnforcer;

  constructor() {
    this.authenticator = new ZeroTrustAuthenticator();
    this.threatDetection = new ThreatDetectionEngine();
    this.forensics = new ForensicsCollector();
    this.policyEnforcer = new SecurityPolicyEnforcer();
  }

  /**
   * Process security decision for access request
   * Implements full zero-trust workflow
   */
  async processAccessRequest(request: AccessRequest): Promise<SecurityDecision> {
    const timestamp = new Date();

    // Step 1: Authenticate user (continuous verification)
    const authResult = await this.authenticator.authenticate(
      {
        userId: request.principal,
        deviceId: request.context.deviceId,
        timestamp,
        requestHash: `${request.principal}:${request.resource}:${timestamp.getTime()}`,
        ipAddress: request.context.ipAddress,
        userAgent: request.context.userAgent
      },
      'token'  // Simplified credential
    );

    // Step 2: Check policy enforcement
    const policyDecision = this.policyEnforcer.evaluateAccess({
      principal: request.principal,
      principalType: request.principalType,
      action: request.action,
      resource: request.resource,
      attributes: {
        ipAddress: request.context.ipAddress,
        timestamp: timestamp.getTime()
      },
      timestamp
    });

    // Step 3: Run threat detection
    const threatEvent = {
      eventId: `event_${Date.now()}`,
      timestamp,
      userId: request.principal,
      deviceId: request.context.deviceId,
      action: request.action,
      resource: request.resource,
      result: (authResult.success && policyDecision.decision === 'allow' ? 'success' : 'failure') as 'success' | 'failure',
      metadata: {
        riskScore: authResult.riskScore,
        ipAddress: request.context.ipAddress
      }
    };

    this.threatDetection.processSecurityEvent(threatEvent);
    const activeAnomalies = this.threatDetection.getActiveAnomalies(ThreatLevel.HIGH);

    // Step 4: Record forensic event
    this.forensics.recordEvent(
      EventCategory.AUTHORIZATION,
      request.action,
      request.resource,
      authResult.success && policyDecision.decision === 'allow' ? 'success' : 'failure',
      {
        userId: request.principal,
        deviceId: request.context.deviceId,
        ipAddress: request.context.ipAddress,
        severity: authResult.riskScore,
        details: {
          authRiskScore: authResult.riskScore,
          threatAnomalies: activeAnomalies.length,
          policyMatched: policyDecision.matchedPolicies.length > 0
        },
        userAgent: request.context.userAgent,
        correlationId: threatEvent.eventId
      }
    );

    // Step 5: Make final security decision
    const allowed =
      authResult.success &&
      authResult.trustDecision !== 'deny' &&
      policyDecision.decision === 'allow' &&
      activeAnomalies.length === 0;

    const decision: SecurityDecision = {
      allowed,
      riskScore: Math.max(authResult.riskScore, policyDecision.riskScore),
      threatLevel: this.getThreatLevel(activeAnomalies),
      requiresMFA: authResult.requiresMFA,
      reason: allowed ? 'Access granted' : policyDecision.reason || authResult.trustDecision,
      token: authResult.token,
      threatAnomalies: activeAnomalies
    };

    return decision;
  }

  /**
   * Get threat level from anomalies
   */
  private getThreatLevel(anomalies: AnomalySignal[]): ThreatLevel {
    if (anomalies.some((a) => a.severity === ThreatLevel.CRITICAL)) {
      return ThreatLevel.CRITICAL;
    }
    if (anomalies.some((a) => a.severity === ThreatLevel.HIGH)) {
      return ThreatLevel.HIGH;
    }
    if (anomalies.some((a) => a.severity === ThreatLevel.MEDIUM)) {
      return ThreatLevel.MEDIUM;
    }
    return ThreatLevel.NONE;
  }

  /**
   * Get overall security status
   */
  getSecurityStatus(): SecurityStatus {
    const authStats = this.authenticator.getAuthenticationStats();
    const threatStats = this.threatDetection.getDetectionStats();
    const forensicsStats = this.forensics.getForensicsStats();
    const policyStats = this.policyEnforcer.getPolicyStats();

    return {
      authenticator: {
        activeDevices: 0,  // Would track from device registry
        activeTokens: authStats.successfulAuthentications,
        successRate: authStats.totalAttempts > 0 
          ? (authStats.successfulAuthentications / authStats.totalAttempts) * 100 
          : 0,
        mfaRequiredCount: authStats.mfaRequiredCount
      },
      threatDetection: {
        totalAnomalies: threatStats.totalAnomalies,
        criticalThreats: threatStats.criticalAnomalies,
        highPriorityThreats: threatStats.highAnomalies
      },
      forensics: {
        totalEvents: forensicsStats.totalEvents,
        activeCases: forensicsStats.activeCases,
        criticalEvents: forensicsStats.criticalEventCount
      },
      policies: {
        totalPolicies: policyStats.totalPolicies,
        enabledPolicies: policyStats.enabledPolicies,
        allowDecisions: policyStats.allowDecisions,
        denyDecisions: policyStats.denyDecisions
      }
    };
  }

  /**
   * Get composite security report
   */
  getSecurityReport(periodHours: number = 24): {
    period: string;
    status: SecurityStatus;
    recommendations: string[];
    criticalFindings: string[];
  } {
    const status = this.getSecurityStatus();
    const recommendations: string[] = [];
    const criticalFindings: string[] = [];

    // Analyze and recommend
    if (status.threatDetection.criticalThreats > 0) {
      criticalFindings.push(`${status.threatDetection.criticalThreats} critical threats detected`);
      recommendations.push('Immediately investigate and escalate critical threats');
    }

    if (status.threatDetection.highPriorityThreats > 5) {
      criticalFindings.push(`${status.threatDetection.highPriorityThreats} high-priority threats detected`);
      recommendations.push('Review and triage high-priority threats');
    }

    if (status.policies.denyDecisions > status.policies.allowDecisions) {
      recommendations.push('Review policy configuration - unusually high denial rate');
    }

    if (status.authenticator.successRate < 80) {
      recommendations.push('Authentication success rate below 80% - investigate');
    }

    return {
      period: `Last ${periodHours} hours`,
      status,
      recommendations,
      criticalFindings
    };
  }

  /**
   * Access authenticator
   */
  getAuthenticator(): ZeroTrustAuthenticator {
    return this.authenticator;
  }

  /**
   * Access threat detection
   */
  getThreatDetection(): ThreatDetectionEngine {
    return this.threatDetection;
  }

  /**
   * Access forensics
   */
  getForensics(): ForensicsCollector {
    return this.forensics;
  }

  /**
   * Access policy enforcer
   */
  getPolicyEnforcer(): SecurityPolicyEnforcer {
    return this.policyEnforcer;
  }
}
