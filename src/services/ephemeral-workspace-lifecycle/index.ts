#!/usr/bin/env node
// @file        src/services/ephemeral-workspace-lifecycle/index.ts
// @module      workspace/lifecycle
// @description Ephemeral workspace container lifecycle manager
//

import {
  WorkspaceLifecycleState,
  WorkspaceLifecycleEventType,
  WorkspaceLifecycleEvent,
  WorkspaceSnapshot,
  WorkspaceLifecycleConfig,
  WorkspaceLifecycleContext,
  LifecycleOperationResult,
  IdleDetectionResult,
  TtlCheckResult,
  WorkspaceCascadeCleanupEvent,
  WorkspaceLifecycleStats,
} from "./types"

export {
  WorkspaceLifecycleState,
  WorkspaceLifecycleEventType,
  WorkspaceLifecycleEvent,
  WorkspaceSnapshot,
  WorkspaceLifecycleConfig,
  WorkspaceLifecycleContext,
  LifecycleOperationResult,
  IdleDetectionResult,
  TtlCheckResult,
  WorkspaceCascadeCleanupEvent,
  WorkspaceLifecycleStats,
} from "./types"

/**
 * EphemeralWorkspaceLifecycleManager
 *
 * Manages complete lifecycle of ephemeral workspace containers:
 * - Creation with TTL (time-to-live)
 * - Activity tracking (idle detection)
 * - Pausing with snapshots
 * - Resuming from snapshots
 * - Cleanup and cascade revocation
 *
 * Coordinates with:
 * - Session broker (container lifecycle)
 * - Shared workspace ACL broker (cascade cleanup)
 * - Database (persistence)
 */
export class EphemeralWorkspaceLifecycleManager {
  private workspaces: Map<string, WorkspaceLifecycleContext>
  private snapshots: Map<string, WorkspaceSnapshot>
  private config: WorkspaceLifecycleConfig
  private monitoringInterval?: NodeJS.Timeout
  private cascadeCleanupCallbacks: Set<(event: WorkspaceCascadeCleanupEvent) => Promise<void>>

  constructor(config: WorkspaceLifecycleConfig) {
    this.config = config
    this.workspaces = new Map()
    this.snapshots = new Map()
    this.cascadeCleanupCallbacks = new Set()
  }

  /**
   * Create a new ephemeral workspace with TTL
   */
  async createWorkspace(
    options: {
      workspaceId: string
      sessionId: string
      userId: string
      containerName: string
      containerPort: number
      ttlSeconds?: number
      actor: string
      correlationId: string
    }
  ): Promise<LifecycleOperationResult> {
    const {
      workspaceId,
      sessionId,
      userId,
      containerName,
      containerPort,
      ttlSeconds,
      actor,
      correlationId,
    } = options

    try {
      // Validate TTL
      const ttl = ttlSeconds || this.config.defaultTtlSeconds
      if (ttl < this.config.minTtlSeconds || ttl > this.config.maxTtlSeconds) {
        return {
          success: false,
          operation: "create",
          workspaceId,
          reason: `TTL ${ttl}s out of range [${this.config.minTtlSeconds}, ${this.config.maxTtlSeconds}]`,
          error: "invalid_ttl",
          correlationId,
        }
      }

      const now = Date.now() / 1000
      const context: WorkspaceLifecycleContext = {
        workspaceId,
        sessionId,
        userId,
        containerName,
        containerPort,
        state: WorkspaceLifecycleState.REQUESTED,
        createdAt: now,
        expiresAt: now + ttl,
        lastActivityAt: now,
        connectionCount: 0,
        snapshotIds: [],
        cpuPercent: 0,
        memoryBytes: 0,
        storageBytes: 0,
        eventLog: [],
      }

      this.workspaces.set(workspaceId, context)

      // Record creation event
      this.recordEvent({
        timestamp: now,
        eventType: WorkspaceLifecycleEventType.WORKSPACE_CREATED,
        workspaceId,
        sessionId,
        actor,
        action: `Create workspace with ${ttl}s TTL`,
        reason: "user_request",
        details: { ttlSeconds: ttl, containerPort },
        correlationId,
      })

      return {
        success: true,
        operation: "create",
        workspaceId,
        state: WorkspaceLifecycleState.REQUESTED,
        correlationId,
      }
    } catch (error) {
      return {
        success: false,
        operation: "create",
        workspaceId,
        error: String(error),
        correlationId,
      }
    }
  }

  /**
   * Mark workspace as ready (container provisioned)
   */
  async markReady(
    workspaceId: string,
    actor: string,
    correlationId: string
  ): Promise<LifecycleOperationResult> {
    const context = this.workspaces.get(workspaceId)
    if (!context) {
      return {
        success: false,
        operation: "connect",
        workspaceId,
        error: "workspace_not_found",
        correlationId,
      }
    }

    const now = Date.now() / 1000
    context.state = WorkspaceLifecycleState.READY
    context.lastActivityAt = now

    this.recordEvent({
      timestamp: now,
      eventType: WorkspaceLifecycleEventType.WORKSPACE_READY,
      workspaceId,
      sessionId: context.sessionId,
      actor,
      action: "Container provisioned and ready",
      correlationId,
    })

    return {
      success: true,
      operation: "connect",
      workspaceId,
      state: context.state,
      correlationId,
    }
  }

  /**
   * Record user connection (activity)
   */
  async recordConnection(
    workspaceId: string,
    actor: string,
    correlationId: string
  ): Promise<LifecycleOperationResult> {
    const context = this.workspaces.get(workspaceId)
    if (!context) {
      return {
        success: false,
        operation: "connect",
        workspaceId,
        error: "workspace_not_found",
        correlationId,
      }
    }

    const now = Date.now() / 1000

    // Transition from PAUSED to CONNECTED
    if (context.state === WorkspaceLifecycleState.PAUSED) {
      context.state = WorkspaceLifecycleState.CONNECTED

      this.recordEvent({
        timestamp: now,
        eventType: WorkspaceLifecycleEventType.WORKSPACE_RESUMED,
        workspaceId,
        sessionId: context.sessionId,
        actor,
        action: "Resumed from pause",
        reason: "user_connection",
        correlationId,
      })
    } else if (context.state === WorkspaceLifecycleState.READY) {
      context.state = WorkspaceLifecycleState.CONNECTED
    }

    context.connectedAt = context.connectedAt || now
    context.lastActivityAt = now
    context.connectionCount++

    this.recordEvent({
      timestamp: now,
      eventType: WorkspaceLifecycleEventType.WORKSPACE_CONNECTED,
      workspaceId,
      sessionId: context.sessionId,
      actor,
      action: `User connected (connection #${context.connectionCount})`,
      correlationId,
    })

    return {
      success: true,
      operation: "connect",
      workspaceId,
      state: context.state,
      correlationId,
    }
  }

  /**
   * Update activity timestamp (keep-alive)
   */
  async updateActivity(
    workspaceId: string,
    actor: string,
    correlationId: string
  ): Promise<LifecycleOperationResult> {
    const context = this.workspaces.get(workspaceId)
    if (!context) {
      return {
        success: false,
        operation: "connect",
        workspaceId,
        error: "workspace_not_found",
        correlationId,
      }
    }

    const now = Date.now() / 1000
    const wasPreviouslyIdle = context.state === WorkspaceLifecycleState.IDLE

    context.lastActivityAt = now
    if (context.state === WorkspaceLifecycleState.IDLE) {
      context.state = WorkspaceLifecycleState.CONNECTED
    }

    if (wasPreviouslyIdle) {
      this.recordEvent({
        timestamp: now,
        eventType: WorkspaceLifecycleEventType.WORKSPACE_CONNECTED,
        workspaceId,
        sessionId: context.sessionId,
        actor,
        action: "Activity resumed from idle",
        correlationId,
      })
    }

    return {
      success: true,
      operation: "connect",
      workspaceId,
      state: context.state,
      correlationId,
    }
  }

  /**
   * Check for idle workspaces and detect/escalate
   */
  async detectIdleWorkspaces(): Promise<IdleDetectionResult[]> {
    const now = Date.now() / 1000
    const results: IdleDetectionResult[] = []

    for (const [workspaceId, context] of this.workspaces.entries()) {
      if (
        context.state !== WorkspaceLifecycleState.CONNECTED &&
        context.state !== WorkspaceLifecycleState.IDLE
      ) {
        continue
      }

      const idleDuration = now - context.lastActivityAt
      const isIdle = idleDuration > this.config.idleTimeoutSeconds
      const warningThreshold = this.config.idleTimeoutSeconds - this.config.idleWarningSeconds
      const warningIssued = idleDuration > warningThreshold && context.state === WorkspaceLifecycleState.CONNECTED

      if (isIdle && context.state !== WorkspaceLifecycleState.IDLE) {
        // Transition to IDLE state
        context.state = WorkspaceLifecycleState.IDLE

        this.recordEvent({
          timestamp: now,
          eventType: WorkspaceLifecycleEventType.WORKSPACE_IDLE,
          workspaceId,
          sessionId: context.sessionId,
          actor: "system",
          action: `Workspace idle for ${idleDuration}s (threshold: ${this.config.idleTimeoutSeconds}s)`,
          reason: "idle_timeout",
          correlationId: `idle-check-${Date.now()}`,
        })
      }

      results.push({
        isIdle,
        idleDurationSeconds: idleDuration,
        lastActivityAt: context.lastActivityAt,
        warningIssued,
        escalatedToPause: false,
      })
    }

    return results
  }

  /**
   * Pause workspace and create snapshot
   */
  async pauseWorkspace(
    workspaceId: string,
    actor: string,
    correlationId: string
  ): Promise<LifecycleOperationResult> {
    const context = this.workspaces.get(workspaceId)
    if (!context) {
      return {
        success: false,
        operation: "pause",
        workspaceId,
        error: "workspace_not_found",
        correlationId,
      }
    }

    try {
      const now = Date.now() / 1000
      context.state = WorkspaceLifecycleState.PAUSING

      // Simulate snapshot creation
      const snapshotId = `snapshot-${workspaceId}-${Date.now()}`
      const retentionDays = 7 // Keep for 7 days
      const snapshot: WorkspaceSnapshot = {
        snapshotId,
        workspaceId,
        sessionId: context.sessionId,
        containerImageId: `image-${context.containerName}`,
        createdAt: now,
        sizeBytes: Math.random() * 1000000000, // 0-1GB simulated
        reason: "user_pause",
        retentionDays,
        expiresAt: now + retentionDays * 86400,
      }

      this.snapshots.set(snapshotId, snapshot)
      context.lastSnapshotId = snapshotId
      context.snapshotIds.push(snapshotId)

      context.state = WorkspaceLifecycleState.PAUSED

      this.recordEvent({
        timestamp: now,
        eventType: WorkspaceLifecycleEventType.WORKSPACE_PAUSED,
        workspaceId,
        sessionId: context.sessionId,
        actor,
        action: `Paused and snapshot created`,
        reason: "user_request",
        details: {
          snapshotId,
          sizeBytes: snapshot.sizeBytes,
          retentionDays,
        },
        correlationId,
      })

      return {
        success: true,
        operation: "pause",
        workspaceId,
        state: context.state,
        correlationId,
      }
    } catch (error) {
      return {
        success: false,
        operation: "pause",
        workspaceId,
        error: String(error),
        correlationId,
      }
    }
  }

  /**
   * Terminate workspace and schedule cleanup
   */
  async terminateWorkspace(
    workspaceId: string,
    actor: string,
    reason: string,
    correlationId: string
  ): Promise<LifecycleOperationResult> {
    const context = this.workspaces.get(workspaceId)
    if (!context) {
      return {
        success: false,
        operation: "terminate",
        workspaceId,
        error: "workspace_not_found",
        correlationId,
      }
    }

    try {
      const now = Date.now() / 1000
      context.state = WorkspaceLifecycleState.TERMINATING
      context.terminatedAt = now

      this.recordEvent({
        timestamp: now,
        eventType: WorkspaceLifecycleEventType.WORKSPACE_TERMINATED,
        workspaceId,
        sessionId: context.sessionId,
        actor,
        action: "Workspace terminated",
        reason,
        correlationId,
      })

      // Schedule cleanup
      setTimeout(
        async () => {
          await this.cleanupWorkspace(workspaceId, "system", correlationId)
        },
        this.config.cleanupDelaySeconds * 1000
      )

      return {
        success: true,
        operation: "terminate",
        workspaceId,
        state: context.state,
        correlationId,
      }
    } catch (error) {
      return {
        success: false,
        operation: "terminate",
        workspaceId,
        error: String(error),
        correlationId,
      }
    }
  }

  /**
   * Perform cleanup and cascade ACL revocation
   */
  async cleanupWorkspace(
    workspaceId: string,
    actor: string,
    correlationId: string
  ): Promise<LifecycleOperationResult> {
    const context = this.workspaces.get(workspaceId)
    if (!context) {
      return {
        success: false,
        operation: "cleanup",
        workspaceId,
        error: "workspace_not_found",
        correlationId,
      }
    }

    try {
      const now = Date.now() / 1000
      context.state = WorkspaceLifecycleState.TERMINATING
      context.cleanupStartedAt = now

      // Cascade cleanup: revoke all ACL entries
      if (this.config.cascadeCleanupAclRevoke) {
        const cleanupEvent: WorkspaceCascadeCleanupEvent = {
          workspaceId,
          sessionId: context.sessionId,
          action: "revoke_all_acl",
          actor,
          reason: "workspace_cleanup",
          correlationId,
        }

        for (const callback of this.cascadeCleanupCallbacks) {
          try {
            await callback(cleanupEvent)
          } catch (error) {
            console.error(`Cascade cleanup callback failed: ${error}`)
          }
        }
      }

      // Delete snapshots
      for (const snapshotId of context.snapshotIds) {
        this.snapshots.delete(snapshotId)
      }

      // Update state
      context.state = WorkspaceLifecycleState.TERMINATED
      context.cleanupCompletedAt = now

      this.recordEvent({
        timestamp: now,
        eventType: WorkspaceLifecycleEventType.CLEANUP_COMPLETED,
        workspaceId,
        sessionId: context.sessionId,
        actor,
        action: "Cleanup completed",
        details: {
          lifespan: context.terminatedAt ? context.terminatedAt - context.createdAt : undefined,
          snapshotsDeleted: context.snapshotIds.length,
        },
        correlationId,
      })

      // Keep in map for audit trail (don't delete)
      return {
        success: true,
        operation: "cleanup",
        workspaceId,
        state: context.state,
        correlationId,
      }
    } catch (error) {
      const context = this.workspaces.get(workspaceId)
      if (context) {
        context.cleanupError = String(error)
      }

      return {
        success: false,
        operation: "cleanup",
        workspaceId,
        error: String(error),
        correlationId,
      }
    }
  }

  /**
   * Check for expired TTLs and auto-terminate
   */
  async checkTtlExpiry(): Promise<TtlCheckResult> {
    const now = Date.now() / 1000
    let expiredCount = 0
    let expiringCount = 0
    let cleanupScheduledCount = 0
    let cleanupCompletedCount = 0

    const warningThresholdSeconds = 300 // Warn 5 min before expiry

    for (const [workspaceId, context] of this.workspaces.entries()) {
      if (context.state === WorkspaceLifecycleState.TERMINATED) {
        if (context.cleanupCompletedAt) {
          cleanupCompletedCount++
        }
        continue
      }

      const timeUntilExpiry = context.expiresAt - now

      // Check if expired
      if (timeUntilExpiry <= 0) {
        expiredCount++

        if (context.state !== WorkspaceLifecycleState.TERMINATING) {
          // Auto-terminate
          await this.terminateWorkspace(
            workspaceId,
            "system",
            "ttl_expired",
            `ttl-check-${Date.now()}`
          )

          this.recordEvent({
            timestamp: now,
            eventType: WorkspaceLifecycleEventType.WORKSPACE_EXPIRED,
            workspaceId,
            sessionId: context.sessionId,
            actor: "system",
            action: `Workspace TTL expired`,
            reason: "ttl_expired",
            correlationId: `ttl-check-${Date.now()}`,
          })
        }
      } else if (timeUntilExpiry <= warningThresholdSeconds) {
        expiringCount++
      }

      if (context.state === WorkspaceLifecycleState.TERMINATING) {
        cleanupScheduledCount++
      }
    }

    return {
      expiredCount,
      expiringCount,
      cleanupScheduledCount,
      cleanupCompletedCount,
    }
  }

  /**
   * Start background monitoring loop
   */
  startMonitoring(): void {
    if (this.monitoringInterval) {
      return
    }

    this.monitoringInterval = setInterval(async () => {
      try {
        // Check for idle workspaces
        await this.detectIdleWorkspaces()

        // Check for TTL expiry
        await this.checkTtlExpiry()
      } catch (error) {
        console.error(`Monitoring error: ${error}`)
      }
    }, this.config.monitoringIntervalSeconds * 1000)
  }

  /**
   * Stop background monitoring
   */
  stopMonitoring(): void {
    if (this.monitoringInterval) {
      clearInterval(this.monitoringInterval)
      this.monitoringInterval = undefined
    }
  }

  /**
   * Register callback for cascade cleanup events
   */
  onCascadeCleanup(callback: (event: WorkspaceCascadeCleanupEvent) => Promise<void>): void {
    this.cascadeCleanupCallbacks.add(callback)
  }

  /**
   * Get workspace context
   */
  getWorkspace(workspaceId: string): WorkspaceLifecycleContext | undefined {
    return this.workspaces.get(workspaceId)
  }

  /**
   * Get workspace statistics
   */
  getStatistics(): WorkspaceLifecycleStats {
    let totalWorkspaces = 0
    let activeWorkspaces = 0
    let pausedWorkspaces = 0
    let terminatedWorkspaces = 0
    let failedWorkspaces = 0
    let totalTtlHours = 0
    let totalLifespan = 0
    let workspaceCount = 0
    let snapshotCount = 0
    let snapshotUsageBytes = 0

    for (const [, context] of this.workspaces.entries()) {
      totalWorkspaces++

      if (context.state === WorkspaceLifecycleState.TERMINATED) {
        terminatedWorkspaces++
      } else if (context.state === WorkspaceLifecycleState.FAILED) {
        failedWorkspaces++
      } else if (context.state === WorkspaceLifecycleState.PAUSED) {
        pausedWorkspaces++
      } else {
        activeWorkspaces++
      }

      const ttlHours = (context.expiresAt - context.createdAt) / 3600
      totalTtlHours += ttlHours
      workspaceCount++

      if (context.terminatedAt) {
        totalLifespan += context.terminatedAt - context.createdAt
      }

      snapshotCount += context.snapshotIds.length
    }

    for (const [, snapshot] of this.snapshots.entries()) {
      snapshotUsageBytes += snapshot.sizeBytes
    }

    return {
      totalWorkspaces,
      activeWorkspaces,
      pausedWorkspaces,
      terminatedWorkspaces,
      failedWorkspaces,
      avgTtlHours: workspaceCount > 0 ? totalTtlHours / workspaceCount : 0,
      avgLifespanMinutes: workspaceCount > 0 ? totalLifespan / workspaceCount / 60 : 0,
      snapshotCount,
      snapshotUsageBytes,
    }
  }

  /**
   * Record lifecycle event
   */
  private recordEvent(event: WorkspaceLifecycleEvent): void {
    const context = this.workspaces.get(event.workspaceId)
    if (context) {
      context.eventLog.push(event)
    }
  }
}

/**
 * Factory function
 */
export function createEphemeralWorkspaceLifecycleManager(
  config: Partial<WorkspaceLifecycleConfig>
): EphemeralWorkspaceLifecycleManager {
  const defaultConfig: WorkspaceLifecycleConfig = {
    defaultTtlSeconds: 3600,     // 1 hour
    maxTtlSeconds: 86400,        // 24 hours
    minTtlSeconds: 600,          // 10 minutes
    idleTimeoutSeconds: 1800,    // 30 minutes
    idleWarningSeconds: 300,     // Warn 5 minutes before
    cleanupDelaySeconds: 30,     // Wait 30s after termination
    cleanupRetryCount: 3,        // Retry cleanup 3 times
    autoSnapshotOnPause: true,
    snapshotRetentionDays: 7,
    maxSnapshotsPerWorkspace: 10,
    quotas: {
      cpuLimit: "2.0",
      memoryLimit: "4g",
      storageLimit: "10g",
      maxProcesses: 256,
      maxOpenFiles: 256,
    },
    monitoringIntervalSeconds: 60,
    emergencyCleanupSloMs: 30000,
    cascadeCleanupAclRevoke: true,
  }

  return new EphemeralWorkspaceLifecycleManager({
    ...defaultConfig,
    ...config,
  })
}

