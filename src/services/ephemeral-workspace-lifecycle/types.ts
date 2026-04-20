#!/usr/bin/env node
// @file        src/services/ephemeral-workspace-lifecycle/types.ts
// @module      workspace/lifecycle
// @description Ephemeral workspace container lifecycle types
//

/**
 * Workspace state machine
 */
export enum WorkspaceLifecycleState {
  // Creation states
  REQUESTED = "requested",
  PROVISIONING = "provisioning",
  SNAPSHOT_RESTORING = "snapshot_restoring",

  // Active states
  READY = "ready",
  CONNECTED = "connected",
  IDLE = "idle",

  // Cleanup states
  PAUSING = "pausing",
  PAUSED = "paused",
  TERMINATING = "terminating",
  TERMINATED = "terminated",
  FAILED = "failed",
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
  WORKSPACE_HARD_DELETED = "workspace_hard_deleted",
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
  actor: string
  action: string
  reason?: string
  details?: Record<string, any>
  correlationId: string
}

/**
 * Workspace snapshot for state preservation
 */
export interface WorkspaceSnapshot {
  snapshotId: string
  workspaceId: string
  sessionId: string
  containerImageId: string
  createdAt: number
  sizeBytes: number
  reason: "user_pause" | "auto_pause" | "emergency" | "backup"
  retentionDays: number
  expiresAt: number
}

/**
 * Workspace resource quotas
 */
export interface WorkspaceResourceQuota {
  cpuLimit: string
  memoryLimit: string
  storageLimit: string
  maxProcesses: number
  maxOpenFiles: number
}

/**
 * Workspace lifecycle configuration
 */
export interface WorkspaceLifecycleConfig {
  defaultTtlSeconds: number
  maxTtlSeconds: number
  minTtlSeconds: number
  idleTimeoutSeconds: number
  idleWarningSeconds: number
  cleanupDelaySeconds: number
  cleanupRetryCount: number
  autoSnapshotOnPause: boolean
  snapshotRetentionDays: number
  maxSnapshotsPerWorkspace: number
  quotas: WorkspaceResourceQuota
  monitoringIntervalSeconds: number
  emergencyCleanupSloMs: number
  cascadeCleanupAclRevoke: boolean
  evidenceSchemaVersion: string
  evidenceRetentionDays: number
  evidenceSigningSalt: string
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
  createdAt: number
  expiresAt: number
  terminatedAt?: number
  connectedAt?: number
  lastActivityAt: number
  connectionCount: number
  lastSnapshotId?: string
  snapshotIds: string[]
  cleanupStartedAt?: number
  cleanupCompletedAt?: number
  cleanupError?: string
  cpuPercent: number
  memoryBytes: number
  storageBytes: number
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
  warningIssued: boolean
  escalatedToPause: boolean
}

/**
 * TTL status check result
 */
export interface TtlCheckResult {
  expiredCount: number
  expiringCount: number
  cleanupScheduledCount: number
  cleanupCompletedCount: number
}

/**
 * Cascade cleanup event for ACL broker
 */
export interface WorkspaceCascadeCleanupEvent {
  workspaceId: string
  sessionId: string
  action: "revoke_all_acl" | "revoke_shared_access"
  actor: string
  reason: string
  correlationId: string
}

/**
 * Workspace lifecycle statistics
 */
export interface WorkspaceLifecycleStats {
  totalWorkspaces: number
  activeWorkspaces: number
  pausedWorkspaces: number
  terminatedWorkspaces: number
  failedWorkspaces: number
  avgTtlHours: number
  avgLifespanMinutes: number
  snapshotCount: number
  snapshotUsageBytes: number
}

/**
 * Hard-delete proof artifact for a session/workspace.
 */
export interface WorkspaceDeletionProof {
  workspaceId: string
  sessionId: string
  actor: string
  reason: string
  deletedAt: number
  correlationId: string
  checksum: string
  cleanupCompletedAt?: number
  snapshotIds: string[]
  residualResourcesCleared: boolean
}

/**
 * Residual resource audit result.
 */
export interface WorkspaceResidualAudit {
  workspaceId: string
  sessionId: string
  residualWorkspacePresent: boolean
  residualSnapshotCount: number
  proofRecorded: boolean
  proofChecksum?: string
  lastCleanupCompletedAt?: number
}

/**
 * Hard-delete reconciliation result.
 */
export interface WorkspaceHardDeleteResult {
  success: boolean
  workspaceId: string
  sessionId: string
  state?: WorkspaceLifecycleState
  proof?: WorkspaceDeletionProof
  error?: string
  correlationId: string
}

/**
 * Headless test execution outcome associated with a session teardown.
 */
export interface WorkspaceHeadlessTestOutcome {
  suite: string
  status: "passed" | "failed" | "skipped"
  durationSeconds: number
  artifactPaths: string[]
}

/**
 * Evidence fingerprint material captured for integrity and traceability.
 */
export interface WorkspaceEvidenceFingerprint {
  key: string
  value: string
}

/**
 * Immutable evidence manifest for compliance review.
 */
export interface WorkspaceEvidenceManifest {
  schemaVersion: string
  sessionId: string
  workspaceId: string
  generatedAt: number
  teardownOutcome: "success" | "failed"
  policyVersion: string
  lifecycleEventCount: number
  checksums: {
    eventLog: string
    testOutcomes: string
    fingerprints: string
    deletionProof: string
    manifest: string
  }
  manifestSignature: string
}

/**
 * Full evidence pack retained and retrievable by session ID.
 */
export interface WorkspaceEvidencePack {
  sessionId: string
  workspaceId: string
  createdAt: number
  expiresAt: number
  teardownOutcome: "success" | "failed"
  policyVersion: string
  lifecycleEvents: WorkspaceLifecycleEvent[]
  testOutcomes: WorkspaceHeadlessTestOutcome[]
  fingerprints: WorkspaceEvidenceFingerprint[]
  deletionProof?: WorkspaceDeletionProof
  failureReason?: string
  manifest: WorkspaceEvidenceManifest
}

/**
 * Operator-facing evidence export payload.
 */
export interface WorkspaceEvidenceExport {
  sessionId: string
  workspaceId: string
  teardownOutcome: "success" | "failed"
  createdAt: number
  expiresAt: number
  manifestChecksum: string
  manifestSignature: string
  eventCount: number
  testOutcomeSummary: {
    passed: number
    failed: number
    skipped: number
  }
  artifactPaths: string[]
}

/**
 * Manifest verification result for an evidence pack.
 */
export interface WorkspaceEvidenceVerificationResult {
  valid: boolean
  sessionId: string
  expectedChecksum: string
  actualChecksum: string
  expectedSignature: string
  actualSignature: string
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
