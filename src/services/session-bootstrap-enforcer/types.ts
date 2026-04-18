#!/usr/bin/env node
// @file        src/services/session-bootstrap-enforcer/types.ts
// @module      session/bootstrap-enforcer
// @description Type definitions for session bootstrap enforcement
//

import { PolicyBundle, IdentityAssertion, FailSafeMode } from "../policy-bundle-verifier"

/**
 * Session context with authentication and policy state.
 * Created at code-server startup after assertion validation.
 */
export interface SessionContext {
  // Unique session identifier
  session_id: string

  // User identity from assertion
  user: {
    email: string
    sub: string // stable user ID
    roles: string[]
    org: string
  }

  // Policy enforcement state
  policy: {
    bundle: PolicyBundle
    valid: boolean
    enforcement_mode: EnforcementMode
    policy_version: string
    policy_expires_at: number
  }

  // Session lifecycle
  authenticated_at: number // Unix timestamp
  expires_at: number
  fail_safe_active: boolean
  fail_safe_mode?: FailSafeMode
  fail_safe_reason?: string

  // Audit correlation
  correlation_id: string
  audit_trail: AuditEvent[]
}

/**
 * Policy enforcement mode determines what operations are allowed.
 */
export enum EnforcementMode {
  STRICT = "strict", // All policy checks enforced
  DEGRADED = "degraded", // Some checks disabled (fail-safe active)
  LOCKED_DOWN = "locked_down", // No operations allowed
}

/**
 * Audit event recorded during session bootstrap and operation enforcement.
 */
export interface AuditEvent {
  timestamp: number
  event_type: SessionBootstrapEventType | PrivilegedOperationEventType
  status: "success" | "failure"
  details: Record<string, any>
  correlation_id: string
}

/**
 * Event types during session bootstrap.
 */
export enum SessionBootstrapEventType {
  ASSERTION_RECEIVED = "assertion_received",
  ASSERTION_VALIDATION_STARTED = "assertion_validation_started",
  SIGNATURE_VERIFIED = "signature_verified",
  POLICY_BUNDLE_VERIFIED = "policy_bundle_verified",
  SESSION_ACTIVATED = "session_activated",
  BOOTSTRAP_FAILED = "bootstrap_failed",
  FAIL_SAFE_ACTIVATED = "fail_safe_activated",
}

/**
 * Event types for privileged operations.
 */
export enum PrivilegedOperationEventType {
  PRIVILEGED_OP_ATTEMPTED = "privileged_op_attempted",
  PRIVILEGED_OP_ALLOWED = "privileged_op_allowed",
  PRIVILEGED_OP_DENIED = "privileged_op_denied",
  POLICY_DRIFT_DETECTED = "policy_drift_detected",
}

/**
 * Bootstrap initialization options.
 */
export interface BootstrapOptions {
  // Assertion from portal (JWT format)
  assertion: string // JWT token

  // Whether to allow unsigned assertions (testing only)
  allowUnsigned?: boolean

  // Session TTL in seconds
  sessionTtlSeconds?: number

  // Fail-safe mode to use if bootstrap fails
  defaultFailSafeMode?: FailSafeMode

  // Whether to enforce strict policy or degraded mode
  enforcementMode?: EnforcementMode
}

/**
 * Bootstrap result with session context or error details.
 */
export interface BootstrapResult {
  success: boolean
  session?: SessionContext
  errors?: BootstrapError[]
  auditEvents?: AuditEvent[]
}

/**
 * Bootstrap error with detailed context.
 */
export interface BootstrapError {
  code: string
  message: string
  severity: "info" | "warn" | "error" | "critical"
  details?: Record<string, any>
}

/**
 * Privileged operation that requires policy enforcement.
 */
export interface PrivilegedOperation {
  operation_type: string // e.g., "read_secret", "execute_terminal", "install_extension"
  resource?: string // e.g., GSM secret name, command, extension ID
  reason?: string // Why the operation is being attempted
}

/**
 * Result of privileged operation enforcement.
 */
export interface PrivilegedOperationResult {
  allowed: boolean
  reason?: string // Why operation was denied, if applicable
  audit_event?: AuditEvent
}

/**
 * Policy drift detector result.
 */
export interface DriftDetectionResult {
  drifted: boolean
  drifted_fields: string[] // Which fields drifted from policy
  details: Record<string, any>
}
