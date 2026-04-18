// @file        src/services/revocation-broker/types.ts
// @module      identity/revocation
// @description Type definitions for strict revocation path with propagation SLO enforcement
//

/**
 * Revocation status for user, session, or privilege
 */
export enum RevocationStatus {
  ACTIVE = "active",
  REVOKED = "revoked",
  REVOKE_PENDING = "revoke_pending",
  UNKNOWN = "unknown", // Default to DENY for privileged operations
}

/**
 * Scope of revocation (what is being revoked)
 */
export enum RevocationScope {
  USER = "user", // Revoke all sessions for user
  SESSION = "session", // Revoke specific session
  PRIVILEGE = "privilege", // Revoke specific privilege/role
  WORKSPACE = "workspace", // Revoke workspace access
}

/**
 * Reason for revocation
 */
export enum RevocationReason {
  ADMIN_EXPLICIT = "admin_explicit", // Admin explicitly revoked
  POLICY_VIOLATION = "policy_violation", // User violated policy
  EMPLOYMENT_TERMINATION = "employment_termination", // User terminated
  SECURITY_INCIDENT = "security_incident", // Security incident detected
  MFA_FAILURE = "mfa_failure", // MFA validation failed
  LICENSE_EXPIRY = "license_expiry", // License expired
  MANUAL_DEPROVISIONING = "manual_deprovisioning", // Manual removal
  SYSTEM_EMERGENCY = "system_emergency", // System emergency mode
}

/**
 * Enforcement mode for unknown revocation state
 */
export enum UnknownRevocationBehavior {
  DENY = "deny", // Default to deny (fail-safe, required for privileged operations)
  ALLOW = "allow", // Default to allow (fail-open, should only be used for non-critical)
  LOCK_DOWN = "lock_down", // Lockout mode - block all operations
}

/**
 * Single revocation entry in store
 */
export interface RevocationEntry {
  // Identity
  revocationId: string; // UUID for revocation event
  scope: RevocationScope; // What is revoked
  targetId: string; // User ID, session ID, workspace ID, etc.
  
  // Timing
  revokedAt: number; // UNIX timestamp when revoked
  effectiveAt: number; // UNIX timestamp when effective (can be in future for scheduled revocation)
  expiresAt?: number; // Optional: when revocation expires (auto-restore)
  
  // Metadata
  reason: RevocationReason;
  actor: string; // Who performed revocation (admin email, system, etc.)
  correlationId: string; // Trace correlation ID for audit trail
  description?: string; // Optional human-readable reason
  
  // Propagation tracking
  propagatedAt?: number; // When revocation was propagated to all hosts
  propagationStatus: "pending" | "propagating" | "propagated" | "failed";
  propagationLatencyMs?: number; // Actual latency (p95 SLO target: 5000ms)
  failedHosts?: string[]; // Hosts that failed to acknowledge revocation
}

/**
 * Revocation query parameters
 */
export interface RevocationCheckOptions {
  targetId: string; // User/session/workspace ID to check
  scope: RevocationScope; // Scope to check
  atTimestamp?: number; // Check revocation at specific time (default: now)
  
  // Configuration for unknown state behavior
  unknownBehavior?: UnknownRevocationBehavior; // Default: DENY (fail-safe)
}

/**
 * Result of revocation check
 */
export interface RevocationCheckResult {
  status: RevocationStatus; // Current revocation status
  isRevoked: boolean; // Convenience: true if REVOKED or (UNKNOWN and unknownBehavior=DENY)
  entry?: RevocationEntry; // The revocation entry if found
  reason?: RevocationReason; // Reason if revoked
  propagationLatencyMs?: number; // Actual SLO latency
  sloMet: boolean; // true if propagationLatencyMs <= 5000ms
}

/**
 * Options for initiating revocation
 */
export interface RevokeOptions {
  scope: RevocationScope;
  targetId: string;
  reason: RevocationReason;
  actor: string; // Who is revoking
  correlationId: string; // Trace ID
  description?: string;
  expiresAt?: number; // Optional: auto-restore after expiry
  
  // Configuration
  emergency?: boolean; // true for immediate kill-path (p95 SLO < 5s)
  priority?: "high" | "normal"; // Propagation priority
}

/**
 * Result of revocation operation
 */
export interface RevokeResult {
  success: boolean;
  revocationId: string;
  targetId: string;
  scope: RevocationScope;
  correlationId: string;
  
  // Propagation details
  propagationStartedAt: number;
  propagatedAt?: number;
  propagationLatencyMs?: number;
  sloMet: boolean; // true if propagationLatencyMs <= 5000ms
  
  // Error details if failed
  error?: {
    code: string;
    message: string;
  };
}

/**
 * Revocation drill / test request
 */
export interface RevocationDrillOptions {
  scope: RevocationScope;
  targetId: string;
  durationSeconds: number; // How long to maintain revocation
  correlationId: string;
  
  // Configuration
  recordMetrics: boolean; // true to record SLO metrics
}

/**
 * Revocation drill result
 */
export interface RevocationDrillResult {
  success: boolean;
  revocationId: string;
  duration: number; // Actual duration in ms
  
  // Metrics
  propagationLatencyMs: number;
  sloMet: boolean;
  
  // Timing distribution for p95
  latencyDistribution?: {
    min: number;
    max: number;
    p50: number;
    p95: number;
    p99: number;
  };
}

/**
 * Revocation statistics
 */
export interface RevocationStats {
  totalRevocations: number;
  activeRevocations: number;
  expiredRevocations: number;
  
  // SLO tracking
  sloSuccessRate: number; // % of revocations meeting SLO
  avgPropagationLatencyMs: number;
  p95PropagationLatencyMs: number;
  p99PropagationLatencyMs: number;
  
  // By scope
  byScope: {
    [scope in RevocationScope]?: number;
  };
  
  // By reason
  byReason: {
    [reason in RevocationReason]?: number;
  };
}

/**
 * Revocation event for audit trail
 */
export interface RevocationAuditEvent {
  timestamp: number;
  type: "revoke_initiated" | "revoke_propagated" | "revoke_propagation_failed" | "revoke_restored";
  revocationId: string;
  targetId: string;
  scope: RevocationScope;
  reason: RevocationReason;
  actor: string;
  correlationId: string;
  
  // SLO tracking
  propagationLatencyMs?: number;
  sloMet?: boolean;
  
  // Additional context
  details?: Record<string, unknown>;
}

/**
 * Privileged operation context for revocation check
 */
export interface PrivilegedOperationContext {
  operationId: string;
  type: "read_secret" | "execute_terminal" | "install_extension" | "modify_workspace" | "git_credential" | "break_glass";
  actor: string; // User/session performing operation
  targetId?: string; // Resource being accessed
  timestamp: number;
  correlationId: string;
}

/**
 * Privileged operation result with revocation enforcement
 */
export interface PrivilegedOperationResult {
  allowed: boolean;
  reason: string; // Why allowed or denied
  
  // Revocation details if denied
  revocationInfo?: {
    isRevoked: boolean;
    reason: RevocationReason;
    revokedAt: number;
  };
  
  // Audit event
  auditEvent: {
    type: "privileged_op_allowed" | "privileged_op_denied";
    timestamp: number;
    correlationId: string;
  };
}

/**
 * Configuration for revocation broker
 */
export interface RevocationBrokerConfig {
  // SLO configuration (in milliseconds)
  sloTargetMs: number; // Default 5000ms for p95
  sloMonitoringEnabled: boolean; // Enable SLO metrics collection
  
  // Default behavior
  defaultUnknownBehavior: UnknownRevocationBehavior; // Default: DENY
  
  // Storage
  persistenceEnabled: boolean; // Persist revocations to database
  cacheEnabled: boolean; // Cache recent revocations for fast lookup
  cacheTtlSeconds: number; // Cache TTL
  
  // Propagation
  propagationIntervalMs: number; // How often to check and propagate
  propagationTimeoutMs: number; // Max time for propagation
  maxRetries: number; // Retry count for failed propagations
  
  // Expiry management
  autoExpireAfterDays: number; // Auto-expire old revocations
  scheduledRevocationCheckIntervalMs: number; // Check for scheduled revocations
}

/**
 * Host-level revocation state for multi-host propagation
 */
export interface HostRevocationState {
  hostId: string;
  revocationId: string;
  
  status: "pending" | "acknowledged" | "failed";
  lastUpdateAt: number;
  
  error?: {
    code: string;
    message: string;
  };
}

/**
 * Revocation broker interface
 */
export interface IRevocationBroker {
  // Revocation operations
  revoke(options: RevokeOptions): Promise<RevokeResult>;
  restoreRevocation(revocationId: string, actor: string, correlationId: string): Promise<RevokeResult>;
  
  // Checking revocation
  checkRevocation(options: RevocationCheckOptions): Promise<RevocationCheckResult>;
  
  // Privileged operation enforcement
  checkPrivilegedOperation(context: PrivilegedOperationContext): Promise<PrivilegedOperationResult>;
  
  // Testing/drills
  startRevocationDrill(options: RevocationDrillOptions): Promise<RevocationDrillResult>;
  
  // Statistics
  getStatistics(): Promise<RevocationStats>;
  
  // Lifecycle
  shutdown(): Promise<void>;
}
