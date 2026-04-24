// @file        src/services/shared-workspace-acl/types.ts
// @module      workspace/acl
// @description Shared workspace ACL model for controlled folder sharing with role-based access
//

/**
 * Shared workspace access control model.
 * Provides explicit governance for shared folder access with owner/editor/viewer roles.
 */

/**
 * Access level grant for shared workspace.
 */
export enum AccessLevel {
  // View-only access
  VIEWER = "viewer",
  
  // Can read and write (create/edit/delete)
  EDITOR = "editor",
  
  // Full control including ACL management and revocation
  OWNER = "owner",
}

/**
 * Lease/expiry information for shared access.
 */
export interface AccessLease {
  grantedAt: number // Unix timestamp when access granted
  expiresAt?: number // Unix timestamp when access expires (null = no expiry)
  requestedBy: string // Email of user who granted access
  reason?: string // Reason for sharing
  autoRevoke: boolean // Auto-revoke when expired?
}

/**
 * ACL entry for a single user's access to a workspace.
 */
export interface WorkspaceAclEntry {
  principalId: string // User email or service account ID
  principalType: "user" | "service_account"
  accessLevel: AccessLevel
  lease: AccessLease
  grantedAt: number // When this entry was created
  lastModified: number // Last change to this entry
  auditTrail: AuditEvent[] // History of access changes
}

/**
 * Complete ACL for a shared workspace.
 */
export interface WorkspaceAcl {
  workspaceId: string
  workspaceName: string
  owner: string // Primary owner (cannot be revoked)
  org: string // Organization ID
  aclVersion: string // ACL format version
  entries: Map<string, WorkspaceAclEntry> // principalId → entry
  createdAt: number
  lastModified: number
  correlationId: string
}

/**
 * ACL operation result.
 */
export interface AclOperationResult {
  success: boolean
  operation: "grant" | "revoke" | "update" | "list"
  principalId: string
  accessLevel?: AccessLevel
  error?: string
  errorCode?: string
  executedAt: number
  correlationId: string
}

/**
 * ACL check result for access validation.
 */
export interface AclCheckResult {
  allowed: boolean
  accessLevel?: AccessLevel
  reason?: string
  lease?: AccessLease
  expired: boolean
  checkedAt: number
  correlationId: string
}

/**
 * Audit event for ACL changes.
 */
export interface AuditEvent {
  timestamp: number
  eventType: AclEventType
  actor: string // User who performed action
  action: "grant" | "revoke" | "update" | "expire"
  principalId: string
  accessLevel?: AccessLevel
  oldAccessLevel?: AccessLevel
  reason?: string
  details?: Record<string, any>
  correlationId: string
}

/**
 * ACL event types.
 */
export enum AclEventType {
  ACCESS_GRANTED = "access_granted",
  ACCESS_REVOKED = "access_revoked",
  ACCESS_UPDATED = "access_updated",
  ACCESS_EXPIRED = "access_expired",
  LEASE_RENEWED = "lease_renewed",
  EMERGENCY_REVOKE = "emergency_revoke",
  ACL_MODIFIED = "acl_modified",
}

/**
 * Grant access options.
 */
export interface GrantAccessOptions {
  workspaceId: string
  principalId: string
  accessLevel: AccessLevel
  expiresIn?: number // Seconds until expiry (null = no expiry)
  reason?: string
  autoRevoke?: boolean // Auto-revoke when expired?
  grantedBy: string // Email of user granting access
  correlationId: string
}

/**
 * Revoke access options.
 */
export interface RevokeAccessOptions {
  workspaceId: string
  principalId: string
  revokedBy: string // Email of user revoking access
  reason?: string
  emergency: boolean // Emergency revocation (immediate, logs as EMERGENCY_REVOKE)
  correlationId: string
}

/**
 * ACL query options for listing shared accesses.
 */
export interface AclQueryOptions {
  workspaceId?: string
  principalId?: string
  org: string
  includeExpired: boolean
  maxResults: number
  correlationId: string
}

/**
 * ACL query result.
 */
export interface AclQueryResult {
  entries: WorkspaceAclEntry[]
  totalCount: number
  expiredCount: number
  queriedAt: number
  correlationId: string
}

/**
 * Workspace mount/open operation that requires ACL check.
 */
export interface WorkspaceMountOperation {
  operation: "mount" | "open" | "list" | "read" | "write" | "delete"
  workspaceId: string
  principalId: string
  resource?: string // File/folder path being accessed
  timestamp: number
  correlationId: string
}

/**
 * Operation enforcement result (passed to code-server).
 */
export interface OperationEnforcementResult {
  allowed: boolean
  operation: string
  workspaceId: string
  principalId: string
  reason?: string // Why denied (e.g., "access expired")
  enforceMode?: "strict" | "read_only" | "locked"
  appliedAt: number
  correlationId: string
}

/**
 * ACL synchronization state (for multi-host deployments).
 */
export interface AclSyncState {
  workspaceId: string
  version: string // Current ACL version
  lastSyncedAt: number
  syncClock: number // Vector clock for ordering
  replicaHosts: string[] // Hosts that have this version
  isSynced: boolean // All replicas caught up?
  correlationId: string
}

/**
 * Revocation propagation event (for SLO compliance).
 */
export interface RevocationEvent {
  workspaceId: string
  principalId: string
  revokedAt: number
  propagatedHosts: Map<string, number> // host → timestamp revocation applied
  targetSloMs: number // SLO for revocation propagation (default 5000ms)
  sloMet: boolean
  correlationId: string
}

/**
 * Shared workspace statistics for monitoring.
 */
export interface SharedWorkspaceStats {
  org: string
  totalWorkspaces: number
  totalSharedWorkspaces: number
  totalAclEntries: number
  totalAclEntriesExpired: number
  uniquePrincipals: number
  accessLevelDistribution: Map<AccessLevel, number>
  computedAt: number
}

/**
 * ACL enforcement policy configuration.
 */
export interface AclEnforcementPolicy {
  // Enforce ACL checks for all operations
  enforceAll: boolean
  
  // Specific operations to enforce
  enforcedOperations: Set<string>
  
  // Auto-revoke behavior
  autoRevokeExpired: boolean
  autoRevokeCheckIntervalMs: number
  
  // Emergency revocation (SLO)
  emergencyRevocationSloMs: number
  
  // Lease defaults
  defaultLeaseExpirySeconds: number
  maxLeaseExpirySeconds: number
  
  // Deny all access if policy unavailable
  failSafe: "deny_all" | "allow_cache" | "allow_all"
}

/**
 * ACL cache entry for offline/degraded operation.
 */
export interface AclCacheEntry {
  acl: WorkspaceAcl
  cachedAt: number
  ttlSeconds: number
  checksum: string
}

/**
 * ACL conformance violation for testing.
 */
export interface AclConformanceViolation {
  workspaceId: string
  principalId: string
  operation: string
  expectedOutcome: string
  actualOutcome: string
  violation: string
  severity: "info" | "warn" | "error"
}

/**
 * Conformance test scenario.
 */
export interface ConformanceTestScenario {
  name: string
  description: string
  setup: () => Promise<void>
  test: () => Promise<void>
  teardown: () => Promise<void>
  expectedViolations: AclConformanceViolation[]
}
