/**
 * Phase 13: Zero-Trust Security, Threat Detection & Forensics
 *
 * This module provides enterprise-grade security capabilities:
 * - Continuous cryptographic identity verification
 * - Real-time anomaly detection and threat scoring
 * - Comprehensive security event logging and forensics
 * - Attribute-based access control and policy enforcement
 * - Full zero-trust architecture implementation
 */
export { ZeroTrustAuthenticator, type IdentityToken, type AuthenticationContext, type AuthenticationResult, type DeviceSignature, type GeographicLocation } from './ZeroTrustAuthenticator';
export { ThreatDetectionEngine, type AnomalySignal, type SecurityEvent, type ThreatProfile, ThreatLevel, AnomalyType } from './ThreatDetectionEngine';
export { ForensicsCollector, type ForensicEvent, type InvestigationCase, type ComplianceReport, EventCategory } from './ForensicsCollector';
export { SecurityPolicyEnforcer, type AccessPolicy, type PolicyDecision, type PolicyEvaluationContext, PolicyAction } from './SecurityPolicyEnforcer';
export { ZeroTrustSecurityOrchestrator, type SecurityDecision, type SecurityStatus, type AccessRequest } from './ZeroTrustSecurityOrchestrator';
//# sourceMappingURL=index.d.ts.map