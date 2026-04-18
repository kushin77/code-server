#!/usr/bin/env node
// @file        src/services/session-bootstrap-enforcer/index.ts
// @module      session/bootstrap-enforcer
// @description Session bootstrap enforcement with mandatory assertion validation
//

import * as crypto from "crypto"
import * as jwt from "jsonwebtoken"
import { PolicyBundleVerifier, PolicyBundle } from "../policy-bundle-verifier"
import {
  SessionContext,
  BootstrapOptions,
  BootstrapResult,
  BootstrapError,
  SessionBootstrapEventType,
  PrivilegedOperationEventType,
  EnforcementMode,
  FailSafeMode,
  AuditEvent,
  PrivilegedOperation,
  PrivilegedOperationResult,
  DriftDetectionResult,
} from "./types"

/**
 * SessionBootstrapEnforcer manages session creation with mandatory assertion validation.
 * Ensures all code-server sessions are backed by a valid portal-issued assertion.
 */
export class SessionBootstrapEnforcer {
  private verifier: PolicyBundleVerifier
  private sessions: Map<string, SessionContext> = new Map()

  constructor(verifier: PolicyBundleVerifier) {
    this.verifier = verifier
  }

  /**
   * Bootstrap a new session with mandatory assertion validation.
   * This is the main entry point that code-server calls at startup.
   */
  async bootstrap(options: BootstrapOptions): Promise<BootstrapResult> {
    const sessionId = this.generateSessionId()
    const auditEvents: AuditEvent[] = []
    const errors: BootstrapError[] = []

    try {
      // Step 1: Receive assertion
      this.recordAuditEvent(auditEvents, sessionId, SessionBootstrapEventType.ASSERTION_RECEIVED, {
        assertion_length: options.assertion.length,
      })

      // Step 2: Decode and validate JWT format
      let decodedToken: any
      try {
        decodedToken = jwt.decode(options.assertion, { complete: true })
        if (!decodedToken) {
          throw new Error("Invalid JWT format")
        }
      } catch (err) {
        errors.push({
          code: "INVALID_JWT_FORMAT",
          message: `Failed to decode assertion: ${err instanceof Error ? err.message : String(err)}`,
          severity: "critical",
        })
        return this.createBootstrapFailure(sessionId, errors, auditEvents, options)
      }

      // Step 3: Parse policy bundle from assertion claims
      let bundle: PolicyBundle
      try {
        const bundleData = decodedToken.payload.policy_bundle || decodedToken.payload
        bundle = this.normalizePolicyBundle(bundleData)
      } catch (err) {
        errors.push({
          code: "INVALID_BUNDLE_FORMAT",
          message: `Failed to parse policy bundle: ${err instanceof Error ? err.message : String(err)}`,
          severity: "critical",
        })
        return this.createBootstrapFailure(sessionId, errors, auditEvents, options)
      }

      // Step 4: Verify signature and policy validity
      this.recordAuditEvent(auditEvents, sessionId, SessionBootstrapEventType.ASSERTION_VALIDATION_STARTED, {
        issuer: bundle.issuer,
      })

      const verificationResult = await this.verifier.verify(bundle)
      if (!verificationResult.valid) {
        errors.push(
          ...verificationResult.errors.map((e) => ({
            code: e.code,
            message: e.message,
            severity: this.mapVerificationErrorSeverity(e.code),
            details: e.details,
          })),
        )

        this.recordAuditEvent(auditEvents, sessionId, SessionBootstrapEventType.BOOTSTRAP_FAILED, {
          verification_errors: verificationResult.errors.length,
        })

        return this.createBootstrapFailure(sessionId, errors, auditEvents, options)
      }

      this.recordAuditEvent(auditEvents, sessionId, SessionBootstrapEventType.SIGNATURE_VERIFIED, {
        algorithm: bundle.algorithm,
        issuer: bundle.issuer,
      })

      // Step 5: Validate identity assertion
      this.validateIdentityAssertion(bundle.identity, errors)
      if (errors.length > 0) {
        return this.createBootstrapFailure(sessionId, errors, auditEvents, options)
      }

      // Step 6: Apply policy bundle
      this.recordAuditEvent(auditEvents, sessionId, SessionBootstrapEventType.POLICY_BUNDLE_VERIFIED, {
        policy_version: bundle.version,
        workspace_policies: Object.keys(bundle.workspace_policies),
      })

      // Step 7: Cache verified bundle
      this.verifier.cacheBundle(bundle, verificationResult, 300)

      // Step 8: Create and activate session
      const sessionContext = this.createSessionContext(
        sessionId,
        bundle,
        verificationResult.verified_at,
        options.sessionTtlSeconds || 3600,
        bundle.correlation_id || sessionId,
      )

      // Step 9: Record session activation
      this.recordAuditEvent(auditEvents, sessionId, SessionBootstrapEventType.SESSION_ACTIVATED, {
        user: sessionContext.user.email,
        org: sessionContext.user.org,
        enforcement_mode: sessionContext.policy.enforcement_mode,
      })

      // Store session
      this.sessions.set(sessionId, sessionContext)

      return {
        success: true,
        session: sessionContext,
        auditEvents,
      }
    } catch (err) {
      errors.push({
        code: "BOOTSTRAP_ERROR",
        message: `Unexpected error during bootstrap: ${err instanceof Error ? err.message : String(err)}`,
        severity: "critical",
      })
      return this.createBootstrapFailure(sessionId, errors, auditEvents, options)
    }
  }

  /**
   * Check if a session is still valid and authorized for a privileged operation.
   */
  async checkPrivilegedOperation(
    sessionId: string,
    operation: PrivilegedOperation,
  ): Promise<PrivilegedOperationResult> {
    const session = this.sessions.get(sessionId)
    if (!session) {
      return {
        allowed: false,
        reason: "Session not found",
      }
    }

    const auditEvent: AuditEvent = {
      timestamp: Math.floor(Date.now() / 1000),
      event_type: PrivilegedOperationEventType.PRIVILEGED_OP_ATTEMPTED,
      status: "failure",
      details: { operation_type: operation.operation_type, resource: operation.resource },
      correlation_id: session.correlation_id,
    }

    // Check if session has expired
    const now = Math.floor(Date.now() / 1000)
    if (now > session.expires_at) {
      auditEvent.details.reason = "Session expired"
      this.sessions.delete(sessionId)
      return {
        allowed: false,
        reason: "Session expired",
        audit_event: auditEvent,
      }
    }

    // Check if policy has expired
    if (now > session.policy.policy_expires_at) {
      auditEvent.details.reason = "Policy expired"
      return {
        allowed: false,
        reason: "Policy expired",
        audit_event: auditEvent,
      }
    }

    // Check fail-safe status
    if (session.fail_safe_active && session.fail_safe_mode === FailSafeMode.DENY_ALL) {
      auditEvent.details.reason = "Fail-safe deny-all mode active"
      return {
        allowed: false,
        reason: "System in fail-safe mode",
        audit_event: auditEvent,
      }
    }

    // Check policy-based authorization for the operation
    const policyAllows = this.checkPolicyAuthorization(session, operation)
    if (!policyAllows) {
      auditEvent.details.reason = "Policy does not allow operation"
      return {
        allowed: false,
        reason: "Operation not allowed by policy",
        audit_event: auditEvent,
      }
    }

    // Detect policy drift
    const drift = this.detectPolicyDrift(session)
    if (drift.drifted && session.policy.enforcement_mode === EnforcementMode.STRICT) {
      auditEvent.event_type = PrivilegedOperationEventType.POLICY_DRIFT_DETECTED
      auditEvent.details.drifted_fields = drift.drifted_fields
      return {
        allowed: false,
        reason: "Policy drift detected",
        audit_event: auditEvent,
      }
    }

    // Operation allowed
    auditEvent.event_type = PrivilegedOperationEventType.PRIVILEGED_OP_ALLOWED
    auditEvent.status = "success"

    return {
      allowed: true,
      audit_event: auditEvent,
    }
  }

  /**
   * End a session and clean up resources.
   */
  endSession(sessionId: string): void {
    this.sessions.delete(sessionId)
  }

  /**
   * Get current session context (for debugging/inspection).
   */
  getSession(sessionId: string): SessionContext | undefined {
    return this.sessions.get(sessionId)
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────

  /**
   * Create bootstrap failure response with fail-safe activation.
   */
  private createBootstrapFailure(
    sessionId: string,
    errors: BootstrapError[],
    auditEvents: AuditEvent[],
    options: BootstrapOptions,
  ): BootstrapResult {
    // Check for cached policy for fail-safe
    // In production, this would attempt to fetch a cached bundle
    const hasCachedPolicy = false // Placeholder

    const failSafeMode = options.defaultFailSafeMode || (hasCachedPolicy ? FailSafeMode.READ_ONLY_CACHE : FailSafeMode.DENY_ALL)

    this.recordAuditEvent(auditEvents, sessionId, SessionBootstrapEventType.FAIL_SAFE_ACTIVATED, {
      mode: failSafeMode,
      reason: errors[0]?.code || "unknown",
    })

    return {
      success: false,
      errors,
      auditEvents,
    }
  }

  /**
   * Normalize policy bundle from various formats.
   */
  private normalizePolicyBundle(data: any): PolicyBundle {
    // Ensure all required fields are present
    if (!data.version || !data.contract_id || !data.identity || !data.entitlements) {
      throw new Error("Missing required bundle fields")
    }
    return data as PolicyBundle
  }

  /**
   * Validate identity assertion fields.
   */
  private validateIdentityAssertion(identity: any, errors: BootstrapError[]): void {
    const requiredFields = ["email", "sub", "roles", "org"]
    for (const field of requiredFields) {
      if (!identity[field]) {
        errors.push({
          code: "MISSING_IDENTITY_FIELD",
          message: `Required identity field missing: ${field}`,
          severity: "critical",
        })
      }
    }
  }

  /**
   * Create session context with policy enforcement.
   */
  private createSessionContext(
    sessionId: string,
    bundle: PolicyBundle,
    verifiedAt: number,
    ttlSeconds: number,
    correlationId: string,
  ): SessionContext {
    const now = Math.floor(Date.now() / 1000)
    return {
      session_id: sessionId,
      user: {
        email: bundle.identity.email,
        sub: bundle.identity.sub,
        roles: bundle.identity.roles,
        org: bundle.identity.org,
      },
      policy: {
        bundle,
        valid: true,
        enforcement_mode: EnforcementMode.STRICT,
        policy_version: bundle.version,
        policy_expires_at: bundle.expires_at,
      },
      authenticated_at: now,
      expires_at: now + ttlSeconds,
      fail_safe_active: false,
      correlation_id: correlationId,
      audit_trail: [],
    }
  }

  /**
   * Check if operation is allowed by policy.
   */
  private checkPolicyAuthorization(session: SessionContext, operation: PrivilegedOperation): boolean {
    // Placeholder for policy-based authorization
    // In production, this would:
    // 1. Check workspace_policy for the operation type
    // 2. Check extension_allowlist for install_extension operations
    // 3. Check credential_scope for secret access operations
    // 4. Check terminal_policy for command execution

    // For now, allow all operations if policy is valid
    return session.policy.valid
  }

  /**
   * Detect policy drift (unauthorized local changes).
   */
  private detectPolicyDrift(session: SessionContext): DriftDetectionResult {
    // Placeholder for drift detection
    // In production, this would check:
    // - $HOME/.local/share/code-server/User/settings.json
    // - $HOME/.gitconfig
    // - Environment variables against policy

    return {
      drifted: false,
      drifted_fields: [],
      details: {},
    }
  }

  /**
   * Record audit event.
   */
  private recordAuditEvent(
    auditEvents: AuditEvent[],
    sessionId: string,
    eventType: SessionBootstrapEventType | PrivilegedOperationEventType,
    details: Record<string, any>,
  ): void {
    auditEvents.push({
      timestamp: Math.floor(Date.now() / 1000),
      event_type: eventType,
      status: "success",
      details,
      correlation_id: details.correlation_id || sessionId,
    })
  }

  /**
   * Map verification error severity.
   */
  private mapVerificationErrorSeverity(errorCode: string): "info" | "warn" | "error" | "critical" {
    const criticalErrors = ["INVALID_SIGNATURE", "MISSING_FIELD", "EXPIRED_BUNDLE", "INCOMPATIBLE_VERSION"]
    return criticalErrors.includes(errorCode) ? "critical" : "error"
  }

  /**
   * Generate unique session ID.
   */
  private generateSessionId(): string {
    return `sess-${Date.now()}-${crypto.randomBytes(8).toString("hex")}`
  }
}

/**
 * Factory function to create enforcer with configured verifier.
 */
export function createSessionBootstrapEnforcer(verifier: PolicyBundleVerifier): SessionBootstrapEnforcer {
  return new SessionBootstrapEnforcer(verifier)
}

// Export types for consumers
export * from "./types"
