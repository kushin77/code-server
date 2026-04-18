#!/usr/bin/env node
// @file        src/services/ephemeral-workspace-lifecycle/types.ts
// @module      workspace/lifecycle
// @description Ephemeral workspace container lifecycle types
//

import { AccessLevel } from "../shared-workspace-acl"

/**
 * Workspace state machine
 */
export enum WorkspaceLifecycleState {
  // Creation states
  REQUESTED = "requested",          // Initial request
  PROVISIONING = "provisioning",    // Creating container
  SNAPSHOT_RESTORING = "snapshot_restoring", // Restoring from snapshot

  // Active states
  READY = "ready",                  // Container ready, waiting for connection
  CONNECTED = "connected",          // User connected
  IDLE = "idle",                    // User inactive

  // Cleanup states
  PAUSING = "pausing",              // Preparing to pause
  PAUSED = "paused",                // Paused (snapshot created)
  TERMINATING = "terminating",      // Shutting down
  TERMINATED = "terminated",        // Cleaned up
  FAILED = "failed",                // Creation/operation failed
}

/**
 * Workspace lifecycle event types
 */
export enum WorkspaceLifecycleEventType {
  WORKSPACE_CREATED = "workspace_created",
  WORKSPACE_READY = "workspace_ready",
  WORKSPACE_CONNECTED = "workspace_connected",
  WORKSPACE_IDLE = "workspace_idle",
  WORKSPACE_PAUSED = "workspace_paused",
  WORKSPACE_RESUMED = "workspace_resumed",
  WORKSPACE_TERMINATED = "workspace_terminated",
  WORKSPACE_EXPIRED = "workspace_expired",
  WORKSPACE_FAILED = "workspace_failed",
  SNAPSHOT_CREATED = "snapshot_created",
  SNAPSHOT_RESTORED = "snapshot_restored",
  CLEANUP_INITIATED = "cleanup_initiated",
  CLEANUP_COMPLETED = "cleanup_completed",
}

/**
 * Workspace lifecycle event for audit trail
 */
export interface WorkspaceLifecycleEvent {
  timestamp: number
  eventType: WorkspaceLifecycleEventType
  workspaceId: string
  sessionId: string
  actor: string                    // Who triggered (user or system)
  action: string                   // Human-readable action
  reason?: string                  // Why (TTL, manual, error)
  details?: Record<string, any>    // Additional context
  correlationId: string            // Trace correlation
}

/**
 * Workspace snapshot for state preservation
 */
export interface WorkspaceSnapshot {
  snapshotId: string
  workspaceId: string
  sessionId: string
  containerImageId: string         // Docker image ID of frozen state
  createdAt: number
  sizeBytes: number                // Snapshot storage size
  reason: "user_pause" | "auto_pause" | "emergency" | "backup"
  retentionDays: number            // How long to keep
  expiresAt: number                // Cleanup deadline
}

/**
 * Workspace resource quotas
 */
export interface WorkspaceResourceQuota {
  cpuLimit: string                 // "1.0", "2.0", etc.
  memoryLimit: string              // "2g", "4g", etc.
  storageLimit: string             // "10g", "100g", etc.
  maxProcesses: number             // ulimit -p
  maxOpenFiles: number             // ulimit -n
}

/**
 * Workspace lifecycle configuration
 */
export interface WorkspaceLifecycleConfig {
  // TTL management
  defaultTtlSeconds: number        // Default 3600 (1 hour)
  maxTtlSeconds: number            // Max 86400 (24 hours)
  minTtlSeconds: number            // Min 600 (10 minutes)

  // Idle behavior
  idleTimeoutSeconds: number       // Auto-pause after idle
  idleWarningSeconds: number       // Warn before pause

  // Cleanup
  cleanupDelaySeconds: number      // Wait before cleanup after termination
  cleanupRetryCount: number        // Retry cleanup on failure

  // Snapshots
  autoSnapshotOnPause: boolean     // Auto-create snapshot when pausing
  snapshotRetentionDays: number    // Keep snapshots for N days
  maxSnapshotsPerWorkspace: number // Limit snapshots

  // Resource enforcement
  quotas: WorkspaceResourceQuota
  monitoringIntervalSeconds: number // Check resource usage every N seconds

  // Emergency cleanup
  emergencyCleanupSloMs: number    // 30s target for emergency cleanup
  cascadeCleanupAclRevoke: boolean // Auto-revoke ACL on cleanup
}

/**
 * Workspace lifecycle context
 */
export interface WorkspaceLifecycleContext {
  workspaceId: string
  sessionId: string
  userId: string
  containerName: string
  containerPort: number
  state: WorkspaceLifecycleState

  // Lifecycle tracking
  createdAt: number
  expiresAt: number                // TTL deadline
  terminatedAt?: number

  // Connection tracking
  connectedAt?: number             // When user connected
  lastActivityAt: number           // Keep-alive timestamp
  connectionCount: number          // How many times connected

  // Snapshots
  lastSnapshotId?: string
  snapshotIds: string[]

  // Cleanup
  cleanupStartedAt?: number
  cleanupCompletedAt?: number
  cleanupError?: string            // Error during cleanup if any

  // Resource usage
  cpuPercent: number
  memoryBytes: number
  storageBytes: number

  // Audit trail
  eventLog: WorkspaceLifecycleEvent[]
}

/**
 * Lifecycle operation result
 */
export interface LifecycleOperationResult {
  success: boolean
  operation: "create" | "connect" | "pause" | "resume" | "terminate" | "cleanup"
  workspaceId: string
  state?: WorkspaceLifecycleState
  reason?: string
  error?: string
  correlationId: string
}

/**
 * Idle detection result
 */
export interface IdleDetectionResult {
  isIdle: boolean
  idleDurationSeconds: number
  lastActivityAt: number
  warningIssued: boolean           // Already warned user?
  escalatedToPause: boolean        // Paused from idle
}

/**
 * TTL status check result
 */
export interface TtlCheckResult {
  expiredCount: number             // How many workspaces expired
  expiringCount: number            // How many expiring soon
  cleanupScheduledCount: number    // Scheduled for cleanup
  cleanupCompletedCount: number    // Cleanup finished
}

/**
 * Cascade cleanup event for ACL broker
 */
export interface WorkspaceCascadeCleanupEvent {
  workspaceId: string
  sessionId: string
  action: "revoke_all_acl" | "revoke_shared_access"
  actor: string                    // system or user
  reason: string                   // "workspace_terminated", "user_deleted"
  correlationId: string
}

/**
 * Workspace lifecycle statistics
 */
export interface WorkspaceLifecycleStats {
  totalWorkspaces: number
  activeWorkspaces: number         // ready, connected, idle
  pausedWorkspaces: number
  terminatedWorkspaces: number
  failedWorkspaces: number
  avgTtlHours: number
  avgLifespanMinutes: number
  snapshotCount: number
  snapshotUsageBytes: number
}

/**
 * Conformance test scenario
 */
export interface ConformanceTestScenario {
  name: string
  description: string
  input: Record<string, any>
  expectedOutput: Record<string, any>
  expectedState: WorkspaceLifecycleState
  assertionChecks: string[]
}
