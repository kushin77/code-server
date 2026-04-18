// @file        src/services/shared-workspace-acl/index.ts
// @module      workspace/acl
// @description Shared workspace ACL broker for controlled folder sharing with role-based access
//

import * as crypto from "crypto"
import {
  AccessLevel,
  AccessLease,
  WorkspaceAclEntry,
  WorkspaceAcl,
  AclOperationResult,
  AclCheckResult,
  AuditEvent,
  AclEventType,
  GrantAccessOptions,
  RevokeAccessOptions,
  AclQueryOptions,
  AclQueryResult,
  WorkspaceMountOperation,
  OperationEnforcementResult,
  AclSyncState,
  RevocationEvent,
  SharedWorkspaceStats,
  AclEnforcementPolicy,
  AclCacheEntry,
} from "./types"

/**
 * SharedWorkspaceAclBroker manages access control for shared workspace folders.
 * Provides role-based access (VIEWER, EDITOR, OWNER) with lease/expiry support.
 */
export class SharedWorkspaceAclBroker {
  // ACL storage: workspaceId → WorkspaceAcl
  private acls: Map<string, WorkspaceAcl> = new Map()

  // Cache: workspaceId → AclCacheEntry (for offline operation)
  private cache: Map<string, AclCacheEntry> = new Map()

  // Sync state: workspaceId → AclSyncState (multi-host sync)
  private syncState: Map<string, AclSyncState> = new Map()

  // Revocation tracking: workspaceId:principalId → RevocationEvent
  private revocationLog: Map<string, RevocationEvent> = new Map()

  // Enforcement policy
  private policy: AclEnforcementPolicy

  // Cache TTL
  private cacheTtlSeconds: number = 300 // 5 minutes

  constructor(policy?: Partial<AclEnforcementPolicy>) {
    this.policy = {
      enforceAll: true,
      enforcedOperations: new Set(["open", "read", "write", "delete", "mount"]),
      autoRevokeExpired: true,
      autoRevokeCheckIntervalMs: 60000, // Check every minute
      emergencyRevocationSloMs: 5000, // 5 second SLO
      defaultLeaseExpirySeconds: 86400, // 24 hours
      maxLeaseExpirySeconds: 604800, // 7 days
      failSafe: "deny_all",
      ...policy,
    }

    // Start background expiry check
    this.startAutoRevokeCheck()
  }

  /**
   * Grant access to a workspace.
   */
  async grantAccess(options: GrantAccessOptions): Promise<AclOperationResult> {
    const { workspaceId, principalId, accessLevel, grantedBy, correlationId } = options

    try {
      // Load or create ACL
      let acl = this.acls.get(workspaceId)
      if (!acl) {
        acl = this.createAcl(workspaceId, grantedBy, options.reason)
      }

      // Create lease
      const lease: AccessLease = {
        grantedAt: Date.now(),
        expiresAt: options.expiresIn ? Date.now() + options.expiresIn * 1000 : undefined,
        requestedBy: grantedBy,
        reason: options.reason,
        autoRevoke: options.autoRevoke ?? this.policy.autoRevokeExpired,
      }

      // Create ACL entry
      const entry: WorkspaceAclEntry = {
        principalId,
        principalType: principalId.includes("@") ? "user" : "service_account",
        accessLevel,
        lease,
        grantedAt: Date.now(),
        lastModified: Date.now(),
        auditTrail: [],
      }

      // Record audit event
      const auditEvent: AuditEvent = {
        timestamp: Date.now(),
        eventType: AclEventType.ACCESS_GRANTED,
        actor: grantedBy,
        action: "grant",
        principalId,
        accessLevel,
        reason: options.reason,
        correlationId,
      }

      entry.auditTrail.push(auditEvent)

      // Update ACL
      acl.entries.set(principalId, entry)
      acl.lastModified = Date.now()

      // Store ACL
      this.acls.set(workspaceId, acl)

      // Invalidate cache
      this.cache.delete(workspaceId)

      return {
        success: true,
        operation: "grant",
        principalId,
        accessLevel,
        executedAt: Date.now(),
        correlationId,
      }
    } catch (e) {
      return {
        success: false,
        operation: "grant",
        principalId,
        error: (e as Error).message,
        errorCode: "GRANT_FAILED",
        executedAt: Date.now(),
        correlationId,
      }
    }
  }

  /**
   * Revoke access from a workspace.
   */
  async revokeAccess(options: RevokeAccessOptions): Promise<AclOperationResult> {
    const { workspaceId, principalId, revokedBy, correlationId } = options

    try {
      const acl = this.acls.get(workspaceId)
      if (!acl) {
        return {
          success: false,
          operation: "revoke",
          principalId,
          error: "Workspace not found",
          errorCode: "NOT_FOUND",
          executedAt: Date.now(),
          correlationId,
        }
      }

      // Cannot revoke owner
      if (principalId === acl.owner) {
        return {
          success: false,
          operation: "revoke",
          principalId,
          error: "Cannot revoke owner access",
          errorCode: "INVALID_OPERATION",
          executedAt: Date.now(),
          correlationId,
        }
      }

      const entry = acl.entries.get(principalId)
      if (!entry) {
        return {
          success: false,
          operation: "revoke",
          principalId,
          error: "Principal not found in ACL",
          errorCode: "NOT_FOUND",
          executedAt: Date.now(),
          correlationId,
        }
      }

      // Record audit event
      const auditEvent: AuditEvent = {
        timestamp: Date.now(),
        eventType: options.emergency ? AclEventType.EMERGENCY_REVOKE : AclEventType.ACCESS_REVOKED,
        actor: revokedBy,
        action: "revoke",
        principalId,
        oldAccessLevel: entry.accessLevel,
        reason: options.reason,
        details: {
          emergency: options.emergency,
        },
        correlationId,
      }

      entry.auditTrail.push(auditEvent)

      // Remove entry
      acl.entries.delete(principalId)
      acl.lastModified = Date.now()

      // Store ACL
      this.acls.set(workspaceId, acl)

      // Track revocation event for SLO
      if (options.emergency) {
        this.trackEmergencyRevocation(workspaceId, principalId, correlationId)
      }

      // Invalidate cache
      this.cache.delete(workspaceId)

      return {
        success: true,
        operation: "revoke",
        principalId,
        executedAt: Date.now(),
        correlationId,
      }
    } catch (e) {
      return {
        success: false,
        operation: "revoke",
        principalId,
        error: (e as Error).message,
        errorCode: "REVOKE_FAILED",
        executedAt: Date.now(),
        correlationId,
      }
    }
  }

  /**
   * Check if principal has access to workspace and operation.
   */
  async checkAccess(operation: WorkspaceMountOperation): Promise<AclCheckResult> {
    const { workspaceId, principalId, operation: op, correlationId } = operation

    // Check if operation requires enforcement
    if (!this.policy.enforceAll && !this.policy.enforcedOperations.has(op)) {
      return {
        allowed: true,
        reason: "Operation not enforced",
        checkedAt: Date.now(),
        correlationId,
        expired: false,
      }
    }

    try {
      // Try to load ACL (use cache if available)
      let acl = this.loadAclWithCache(workspaceId)
      if (!acl) {
        // ACL not found - apply fail-safe policy
        return this.applyFailSafe(workspaceId, principalId, correlationId)
      }

      // Principal is owner - always allowed
      if (principalId === acl.owner) {
        return {
          allowed: true,
          accessLevel: AccessLevel.OWNER,
          checkedAt: Date.now(),
          correlationId,
          expired: false,
        }
      }

      // Look up entry
      const entry = acl.entries.get(principalId)
      if (!entry) {
        return {
          allowed: false,
          reason: "Principal not in ACL",
          checkedAt: Date.now(),
          correlationId,
          expired: false,
        }
      }

      // Check lease expiry
      if (entry.lease.expiresAt && entry.lease.expiresAt < Date.now()) {
        // Auto-revoke if configured
        if (this.policy.autoRevokeExpired) {
          await this.revokeAccess({
            workspaceId,
            principalId,
            revokedBy: "system",
            reason: "Lease expired",
            emergency: false,
            correlationId,
          })
        }

        return {
          allowed: false,
          reason: "Lease expired",
          checkedAt: Date.now(),
          correlationId,
          expired: true,
        }
      }

      // Check operation against access level
      if (!this.isOperationAllowed(op, entry.accessLevel)) {
        return {
          allowed: false,
          accessLevel: entry.accessLevel,
          reason: `${entry.accessLevel} access does not allow ${op}`,
          lease: entry.lease,
          checkedAt: Date.now(),
          correlationId,
          expired: false,
        }
      }

      return {
        allowed: true,
        accessLevel: entry.accessLevel,
        lease: entry.lease,
        checkedAt: Date.now(),
        correlationId,
        expired: false,
      }
    } catch (e) {
      // On error, apply fail-safe
      return this.applyFailSafe(workspaceId, principalId, correlationId)
    }
  }

  /**
   * Enforce ACL check for code-server operation.
   */
  async enforceOperation(operation: WorkspaceMountOperation): Promise<OperationEnforcementResult> {
    const checkResult = await this.checkAccess(operation)

    return {
      allowed: checkResult.allowed,
      operation: operation.operation,
      workspaceId: operation.workspaceId,
      principalId: operation.principalId,
      reason: checkResult.reason,
      enforceMode: checkResult.allowed ? undefined : "locked",
      appliedAt: Date.now(),
      correlationId: operation.correlationId,
    }
  }

  /**
   * Query ACL entries with filtering.
   */
  async queryAcl(options: AclQueryOptions): Promise<AclQueryResult> {
    const { workspaceId, principalId, includeExpired, maxResults, correlationId } = options

    const entries: WorkspaceAclEntry[] = []
    let expiredCount = 0

    if (workspaceId) {
      // Query specific workspace
      const acl = this.acls.get(workspaceId)
      if (acl) {
        for (const entry of acl.entries.values()) {
          // Filter by principal if specified
          if (principalId && entry.principalId !== principalId) {
            continue
          }

          // Check expiry
          const isExpired = entry.lease.expiresAt && entry.lease.expiresAt < Date.now()

          if (!includeExpired && isExpired) {
            expiredCount++
            continue
          }

          entries.push(entry)

          if (entries.length >= maxResults) {
            break
          }
        }
      }
    } else {
      // Query all workspaces (limited by maxResults)
      for (const acl of this.acls.values()) {
        if (acl.org !== options.org) {
          continue
        }

        for (const entry of acl.entries.values()) {
          // Filter by principal if specified
          if (principalId && entry.principalId !== principalId) {
            continue
          }

          // Check expiry
          const isExpired = entry.lease.expiresAt && entry.lease.expiresAt < Date.now()

          if (!includeExpired && isExpired) {
            expiredCount++
            continue
          }

          entries.push(entry)

          if (entries.length >= maxResults) {
            break
          }
        }

        if (entries.length >= maxResults) {
          break
        }
      }
    }

    return {
      entries,
      totalCount: entries.length,
      expiredCount,
      queriedAt: Date.now(),
      correlationId,
    }
  }

  /**
   * Get statistics about shared workspaces.
   */
  getStatistics(org: string): SharedWorkspaceStats {
    const orgAcls = Array.from(this.acls.values()).filter((acl) => acl.org === org)

    const stats: SharedWorkspaceStats = {
      org,
      totalWorkspaces: orgAcls.length,
      totalSharedWorkspaces: orgAcls.filter((acl) => acl.entries.size > 0).length,
      totalAclEntries: 0,
      totalAclEntriesExpired: 0,
      uniquePrincipals: new Set(),
      accessLevelDistribution: new Map(),
      computedAt: Date.now(),
    }

    for (const acl of orgAcls) {
      for (const entry of acl.entries.values()) {
        stats.totalAclEntries++
        stats.uniquePrincipals.add(entry.principalId)

        // Check expiry
        if (entry.lease.expiresAt && entry.lease.expiresAt < Date.now()) {
          stats.totalAclEntriesExpired++
        }

        // Distribute by access level
        const count = stats.accessLevelDistribution.get(entry.accessLevel) || 0
        stats.accessLevelDistribution.set(entry.accessLevel, count + 1)
      }
    }

    stats.uniquePrincipals = stats.uniquePrincipals as any

    return stats
  }

  /**
   * Create a new workspace ACL.
   */
  private createAcl(workspaceId: string, owner: string, reason?: string): WorkspaceAcl {
    return {
      workspaceId,
      workspaceName: workspaceId, // TODO: Get from workspace metadata
      owner,
      org: this.extractOrg(owner), // TODO: Get from session
      aclVersion: "1.0",
      entries: new Map(),
      createdAt: Date.now(),
      lastModified: Date.now(),
      correlationId: crypto.randomUUID(),
    }
  }

  /**
   * Load ACL with cache fallback.
   */
  private loadAclWithCache(workspaceId: string): WorkspaceAcl | undefined {
    // Try in-memory first
    let acl = this.acls.get(workspaceId)
    if (acl) {
      return acl
    }

    // Try cache
    const cached = this.cache.get(workspaceId)
    if (cached && Date.now() - cached.cachedAt < cached.ttlSeconds * 1000) {
      return cached.acl
    }

    return undefined
  }

  /**
   * Check if operation is allowed for access level.
   */
  private isOperationAllowed(operation: string, accessLevel: AccessLevel): boolean {
    switch (accessLevel) {
      case AccessLevel.VIEWER:
        // Viewer can only read and list
        return operation === "read" || operation === "list" || operation === "open"

      case AccessLevel.EDITOR:
        // Editor can read, write, delete but not mount
        return operation !== "mount"

      case AccessLevel.OWNER:
        // Owner can do anything
        return true

      default:
        return false
    }
  }

  /**
   * Apply fail-safe policy when ACL unavailable.
   */
  private applyFailSafe(
    workspaceId: string,
    principalId: string,
    correlationId: string,
  ): AclCheckResult {
    switch (this.policy.failSafe) {
      case "allow_all":
        return {
          allowed: true,
          reason: "Fail-safe: allow all",
          checkedAt: Date.now(),
          correlationId,
          expired: false,
        }

      case "allow_cache":
        // Only allow if we have cached ACL
        const cached = this.cache.get(workspaceId)
        if (cached) {
          return {
            allowed: true,
            reason: "Fail-safe: using cached ACL",
            checkedAt: Date.now(),
            correlationId,
            expired: false,
          }
        }
        // Fall through to deny_all

      case "deny_all":
      default:
        return {
          allowed: false,
          reason: "Fail-safe: deny all (ACL unavailable)",
          checkedAt: Date.now(),
          correlationId,
          expired: false,
        }
    }
  }

  /**
   * Track emergency revocation for SLO.
   */
  private trackEmergencyRevocation(workspaceId: string, principalId: string, correlationId: string): void {
    const key = `${workspaceId}:${principalId}`
    const event: RevocationEvent = {
      workspaceId,
      principalId,
      revokedAt: Date.now(),
      propagatedHosts: new Map(),
      targetSloMs: this.policy.emergencyRevocationSloMs,
      sloMet: false,
      correlationId,
    }

    this.revocationLog.set(key, event)
  }

  /**
   * Extract organization from email/principal ID.
   */
  private extractOrg(principalId: string): string {
    // TODO: Get org from session/assertion instead
    return "default-org"
  }

  /**
   * Start background auto-revoke check.
   */
  private startAutoRevokeCheck(): void {
    if (!this.policy.autoRevokeExpired) {
      return
    }

    setInterval(async () => {
      const now = Date.now()

      for (const acl of this.acls.values()) {
        const expiredEntries: string[] = []

        for (const [principalId, entry] of acl.entries) {
          if (entry.lease.expiresAt && entry.lease.expiresAt < now) {
            expiredEntries.push(principalId)
          }
        }

        // Revoke expired entries
        for (const principalId of expiredEntries) {
          await this.revokeAccess({
            workspaceId: acl.workspaceId,
            principalId,
            revokedBy: "system",
            reason: "Lease expired",
            emergency: false,
            correlationId: crypto.randomUUID(),
          })
        }
      }
    }, this.policy.autoRevokeCheckIntervalMs)
  }
}

/**
 * Factory function to create a SharedWorkspaceAclBroker instance.
 */
export function createSharedWorkspaceAclBroker(policy?: Partial<AclEnforcementPolicy>): SharedWorkspaceAclBroker {
  return new SharedWorkspaceAclBroker(policy)
}

/**
 * Export all types for convenience.
 */
export * from "./types"
