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
  WorkspaceDeletionProof,
  WorkspaceResidualAudit,
  WorkspaceHardDeleteResult,
  WorkspaceEvidencePack,
  WorkspaceEvidenceManifest,
  WorkspaceEvidenceFingerprint,
  WorkspaceHeadlessTestOutcome,
  WorkspaceEvidenceExport,
  WorkspaceEvidenceVerificationResult,
  WorkspaceLiveProgressUpdate,
  WorkspaceLiveProgressListener,
  WorkspaceReadyTestReport,
} from "./types"

import * as crypto from "crypto"

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
  WorkspaceDeletionProof,
  WorkspaceResidualAudit,
  WorkspaceHardDeleteResult,
  WorkspaceEvidencePack,
  WorkspaceEvidenceManifest,
  WorkspaceEvidenceFingerprint,
  WorkspaceHeadlessTestOutcome,
  WorkspaceEvidenceExport,
  WorkspaceEvidenceVerificationResult,
  WorkspaceLiveProgressUpdate,
  WorkspaceLiveProgressListener,
  WorkspaceReadyTestReport,
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
  private deletionProofs: Map<string, WorkspaceDeletionProof>
  private evidencePacks: Map<string, WorkspaceEvidencePack>
  private validationPacks: Map<string, WorkspaceEvidencePack>
  private readyTestReports: Map<string, WorkspaceReadyTestReport>
  private liveProgressSnapshots: Map<string, WorkspaceLiveProgressUpdate>
  private liveProgressHistory: Map<string, WorkspaceLiveProgressUpdate[]>
  private config: WorkspaceLifecycleConfig
  private monitoringInterval?: NodeJS.Timeout
  private cascadeCleanupCallbacks: Set<(event: WorkspaceCascadeCleanupEvent) => Promise<void>>
  private liveProgressListeners: Set<WorkspaceLiveProgressListener>
  private readyTestRuns: Set<string>

  constructor(config: WorkspaceLifecycleConfig) {
    this.config = config
    this.workspaces = new Map()
    this.snapshots = new Map()
    this.deletionProofs = new Map()
    this.evidencePacks = new Map()
    this.validationPacks = new Map()
    this.readyTestReports = new Map()
    this.liveProgressSnapshots = new Map()
    this.liveProgressHistory = new Map()
    this.cascadeCleanupCallbacks = new Set()
    this.liveProgressListeners = new Set()
    this.readyTestRuns = new Set()
  }

      private computeDeletionChecksum(payload: Record<string, any>): string {
        return crypto.createHash("sha256").update(JSON.stringify(payload)).digest("hex")
      }

      private computeEvidenceChecksum(payload: Record<string, any>): string {
        return crypto.createHash("sha256").update(JSON.stringify(payload)).digest("hex")
      }

      private computeManifestSignature(payload: {
        schemaVersion: string
        sessionId: string
        workspaceId: string
        generatedAt: number
        manifestChecksum: string
      }): string {
        return crypto
          .createHash("sha256")
          .update(`${payload.schemaVersion}:${payload.sessionId}:${payload.workspaceId}:${payload.generatedAt}:${payload.manifestChecksum}:${this.config.evidenceSigningSalt}`)
          .digest("hex")
      }

      private createDefaultFingerprintSet(context: WorkspaceLifecycleContext): WorkspaceEvidenceFingerprint[] {
        return [
          { key: "container_name", value: context.containerName },
          { key: "container_port", value: String(context.containerPort) },
          { key: "user_id", value: context.userId },
          { key: "workspace_state", value: context.state },
        ]
      }

      private createDefaultTestOutcome(teardownOutcome: "success" | "failed"): WorkspaceHeadlessTestOutcome[] {
        return [
          {
            suite: "ephemeral-lifecycle-teardown",
            status: teardownOutcome === "success" ? "passed" : "failed",
            durationSeconds: 0,
            artifactPaths: ["artifacts/ephemeral-workspace-evidence"],
          },
        ]
      }

      private async runWithTimeout<T>(operation: Promise<T>, timeoutSeconds: number, timeoutMessage: string): Promise<T> {
        if (!Number.isFinite(timeoutSeconds) || timeoutSeconds <= 0) {
          return operation
        }

        let timeoutHandle: NodeJS.Timeout | undefined

        const timeoutPromise = new Promise<T>((_, reject) => {
          timeoutHandle = setTimeout(() => {
            reject(new Error(timeoutMessage))
          }, timeoutSeconds * 1000)
        })

        try {
          return await Promise.race([operation, timeoutPromise])
        } finally {
          if (timeoutHandle) {
            clearTimeout(timeoutHandle)
          }
        }
      }

      private createDefaultHeadlessTestOutcomes(context: WorkspaceLifecycleContext): WorkspaceHeadlessTestOutcome[] {
        const baseArtifactPath = `artifacts/${context.sessionId}/headless`

        return [
          {
            suite: "workspace-bootstrap-smoke",
            status: "passed",
            durationSeconds: 18,
            artifactPaths: [`${baseArtifactPath}/workspace-bootstrap-smoke.json`],
          },
          {
            suite: "workspace-editor-smoke",
            status: "passed",
            durationSeconds: 24,
            artifactPaths: [`${baseArtifactPath}/workspace-editor-smoke.json`, `${baseArtifactPath}/workspace-editor-smoke.log`],
          },
        ]
      }

      private summarizeTestOutcomes(testOutcomes: WorkspaceHeadlessTestOutcome[]): {
        passed: number
        failed: number
        skipped: number
      } {
        return {
          passed: testOutcomes.filter((outcome) => outcome.status === "passed").length,
          failed: testOutcomes.filter((outcome) => outcome.status === "failed").length,
          skipped: testOutcomes.filter((outcome) => outcome.status === "skipped").length,
        }
      }

      private calculateTestDurationSeconds(testOutcomes: WorkspaceHeadlessTestOutcome[]): number {
        return testOutcomes.reduce((total, outcome) => total + outcome.durationSeconds, 0)
      }

      private getEvidencePackForSession(sessionId: string): WorkspaceEvidencePack | undefined {
        return this.evidencePacks.get(sessionId) || this.validationPacks.get(sessionId)
      }

      private persistEvidencePack(
        pack: WorkspaceEvidencePack,
        target: Map<string, WorkspaceEvidencePack>,
        context: WorkspaceLifecycleContext
      ): WorkspaceEvidencePack {
        target.set(pack.sessionId, pack)

        const lastEvent = pack.lifecycleEvents[pack.lifecycleEvents.length - 1]
        if (lastEvent) {
          this.emitLiveProgressUpdate({
            context,
            event: lastEvent,
            evidencePack: pack,
            testReport: this.readyTestReports.get(context.sessionId),
          })
        }

        return pack
      }

      private buildEvidencePack(params: {
        context: WorkspaceLifecycleContext
        teardownOutcome: "success" | "failed"
        deletionProof?: WorkspaceDeletionProof
        failureReason?: string
        policyVersion?: string
        testOutcomes?: WorkspaceHeadlessTestOutcome[]
        fingerprints?: WorkspaceEvidenceFingerprint[]
      }): WorkspaceEvidencePack {
        const generatedAt = Date.now() / 1000
        const policyVersion = params.policyVersion || this.config.evidenceSchemaVersion
        const testOutcomes = params.testOutcomes || this.createDefaultTestOutcome(params.teardownOutcome)
        const fingerprints = params.fingerprints || this.createDefaultFingerprintSet(params.context)

        const lifecycleEvents = [...params.context.eventLog]
        const manifest = this.buildEvidenceManifest({
          schemaVersion: this.config.evidenceSchemaVersion,
          sessionId: params.context.sessionId,
          workspaceId: params.context.workspaceId,
          generatedAt,
          teardownOutcome: params.teardownOutcome,
          policyVersion,
          lifecycleEvents,
          testOutcomes,
          fingerprints,
          deletionProof: params.deletionProof,
        })

        return {
          sessionId: params.context.sessionId,
          workspaceId: params.context.workspaceId,
          createdAt: generatedAt,
          expiresAt: generatedAt + this.config.evidenceRetentionDays * 86400,
          teardownOutcome: params.teardownOutcome,
          policyVersion,
          lifecycleEvents,
          testOutcomes,
          fingerprints,
          deletionProof: params.deletionProof,
          failureReason: params.failureReason,
          manifest,
        }
      }

      private buildEvidenceManifest(params: {
        schemaVersion: string
        sessionId: string
        workspaceId: string
        generatedAt: number
        teardownOutcome: "success" | "failed"
        policyVersion: string
        lifecycleEvents: WorkspaceLifecycleEvent[]
        testOutcomes: WorkspaceHeadlessTestOutcome[]
        fingerprints: WorkspaceEvidenceFingerprint[]
        deletionProof?: WorkspaceDeletionProof
      }): WorkspaceEvidenceManifest {
        const eventLogChecksum = this.computeEvidenceChecksum({ lifecycleEvents: params.lifecycleEvents })
        const testOutcomeChecksum = this.computeEvidenceChecksum({ testOutcomes: params.testOutcomes })
        const fingerprintChecksum = this.computeEvidenceChecksum({ fingerprints: params.fingerprints })
        const deletionProofChecksum = this.computeEvidenceChecksum({ deletionProof: params.deletionProof || null })

        const manifestChecksum = this.computeEvidenceChecksum({
          schemaVersion: params.schemaVersion,
          sessionId: params.sessionId,
          workspaceId: params.workspaceId,
          generatedAt: params.generatedAt,
          teardownOutcome: params.teardownOutcome,
          policyVersion: params.policyVersion,
          lifecycleEventCount: params.lifecycleEvents.length,
          eventLogChecksum,
          testOutcomeChecksum,
          fingerprintChecksum,
          deletionProofChecksum,
        })

        return {
          schemaVersion: params.schemaVersion,
          sessionId: params.sessionId,
          workspaceId: params.workspaceId,
          generatedAt: params.generatedAt,
          teardownOutcome: params.teardownOutcome,
          policyVersion: params.policyVersion,
          lifecycleEventCount: params.lifecycleEvents.length,
          checksums: {
            eventLog: eventLogChecksum,
            testOutcomes: testOutcomeChecksum,
            fingerprints: fingerprintChecksum,
            deletionProof: deletionProofChecksum,
            manifest: manifestChecksum,
          },
          manifestSignature: this.computeManifestSignature({
            schemaVersion: params.schemaVersion,
            sessionId: params.sessionId,
            workspaceId: params.workspaceId,
            generatedAt: params.generatedAt,
            manifestChecksum,
          }),
        }
      }

      private emitEvidencePack(params: {
        context: WorkspaceLifecycleContext
        teardownOutcome: "success" | "failed"
        deletionProof?: WorkspaceDeletionProof
        failureReason?: string
        policyVersion?: string
        testOutcomes?: WorkspaceHeadlessTestOutcome[]
        fingerprints?: WorkspaceEvidenceFingerprint[]
      }): WorkspaceEvidencePack {
        const evidencePack = this.buildEvidencePack(params)
        return this.persistEvidencePack(evidencePack, this.evidencePacks, params.context)
      }

      private emitValidationPack(params: {
        context: WorkspaceLifecycleContext
        teardownOutcome: "success" | "failed"
        failureReason?: string
        policyVersion?: string
        testOutcomes?: WorkspaceHeadlessTestOutcome[]
        fingerprints?: WorkspaceEvidenceFingerprint[]
      }): WorkspaceEvidencePack {
        const validationPack = this.buildEvidencePack(params)
        return this.persistEvidencePack(validationPack, this.validationPacks, params.context)
      }

      private buildEvidenceManifest(params: {
        schemaVersion: string
        sessionId: string
        workspaceId: string
        generatedAt: number
        teardownOutcome: "success" | "failed"
        policyVersion: string
        lifecycleEvents: WorkspaceLifecycleEvent[]
        testOutcomes: WorkspaceHeadlessTestOutcome[]
        fingerprints: WorkspaceEvidenceFingerprint[]
        deletionProof?: WorkspaceDeletionProof
      }): WorkspaceEvidenceManifest {
        const eventLogChecksum = this.computeEvidenceChecksum({ lifecycleEvents: params.lifecycleEvents })
        const testOutcomeChecksum = this.computeEvidenceChecksum({ testOutcomes: params.testOutcomes })
        const fingerprintChecksum = this.computeEvidenceChecksum({ fingerprints: params.fingerprints })
        const deletionProofChecksum = this.computeEvidenceChecksum({ deletionProof: params.deletionProof || null })

        const manifestChecksum = this.computeEvidenceChecksum({
          schemaVersion: params.schemaVersion,
          sessionId: params.sessionId,
          workspaceId: params.workspaceId,
          generatedAt: params.generatedAt,
          teardownOutcome: params.teardownOutcome,
          policyVersion: params.policyVersion,
          lifecycleEventCount: params.lifecycleEvents.length,
          eventLogChecksum,
          testOutcomeChecksum,
          fingerprintChecksum,
          deletionProofChecksum,
        })

        return {
          schemaVersion: params.schemaVersion,
          sessionId: params.sessionId,
          workspaceId: params.workspaceId,
          generatedAt: params.generatedAt,
          teardownOutcome: params.teardownOutcome,
          policyVersion: params.policyVersion,
          lifecycleEventCount: params.lifecycleEvents.length,
          checksums: {
            eventLog: eventLogChecksum,
            testOutcomes: testOutcomeChecksum,
            fingerprints: fingerprintChecksum,
            deletionProof: deletionProofChecksum,
            manifest: manifestChecksum,
          },
          manifestSignature: this.computeManifestSignature({
            schemaVersion: params.schemaVersion,
            sessionId: params.sessionId,
            workspaceId: params.workspaceId,
            generatedAt: params.generatedAt,
            manifestChecksum,
          }),
        }
      }

      private emitEvidencePack(params: {
        context: WorkspaceLifecycleContext
        teardownOutcome: "success" | "failed"
        deletionProof?: WorkspaceDeletionProof
        failureReason?: string
        policyVersion?: string
        testOutcomes?: WorkspaceHeadlessTestOutcome[]
        fingerprints?: WorkspaceEvidenceFingerprint[]
      }): WorkspaceEvidencePack {
        const evidencePack = this.buildEvidencePack(params)
        return this.persistEvidencePack(evidencePack, this.evidencePacks, params.context)
      }

      private emitValidationPack(params: {
        context: WorkspaceLifecycleContext
        teardownOutcome: "success" | "failed"
        failureReason?: string
        policyVersion?: string
        testOutcomes?: WorkspaceHeadlessTestOutcome[]
        fingerprints?: WorkspaceEvidenceFingerprint[]
      }): WorkspaceEvidencePack {
        const validationPack = this.buildEvidencePack(params)
        return this.persistEvidencePack(validationPack, this.validationPacks, params.context)
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

    void this.runHeadlessValidation(context, actor, correlationId)

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
          const cleanupResult = await this.cleanupWorkspace(workspaceId, "system", correlationId)
          if (cleanupResult.success) {
            await this.hardDeleteWorkspace(workspaceId, "system", "termination_gc", correlationId)
          }
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
   * Mark a workspace as failed and emit a teardown evidence pack for auditability.
   */
  markWorkspaceFailed(
    workspaceId: string,
    actor: string,
    reason: string,
    correlationId: string
  ): LifecycleOperationResult {
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

    const now = Date.now() / 1000
    context.state = WorkspaceLifecycleState.FAILED
    context.cleanupError = reason

    this.recordEvent({
      timestamp: now,
      eventType: WorkspaceLifecycleEventType.WORKSPACE_FAILED,
      workspaceId,
      sessionId: context.sessionId,
      actor,
      action: "Workspace marked failed",
      reason,
      correlationId,
    })

    this.emitEvidencePack({
      context,
      teardownOutcome: "failed",
      failureReason: reason,
    })

    return {
      success: true,
      operation: "cleanup",
      workspaceId,
      state: context.state,
      reason,
      correlationId,
    }
  }

  /**
   * Hard delete a workspace after cleanup and retain only deletion proof.
   */
  async hardDeleteWorkspace(
    workspaceId: string,
    actor: string,
    reason: string,
    correlationId: string
  ): Promise<WorkspaceHardDeleteResult> {
    const context = this.workspaces.get(workspaceId)
    if (!context) {
      const proof = this.deletionProofs.get(workspaceId)
      return {
        success: false,
        workspaceId,
        sessionId: proof?.sessionId || "unknown",
        error: "workspace_not_found",
        correlationId,
      }
    }

    try {
      if (context.cleanupCompletedAt === undefined) {
        await this.cleanupWorkspace(workspaceId, actor, correlationId)
      }

      const deletedAt = Date.now() / 1000
      const proof: WorkspaceDeletionProof = {
        workspaceId,
        sessionId: context.sessionId,
        actor,
        reason,
        deletedAt,
        correlationId,
        cleanupCompletedAt: context.cleanupCompletedAt,
        snapshotIds: [...context.snapshotIds],
        residualResourcesCleared: context.snapshotIds.length === 0,
        checksum: this.computeDeletionChecksum({
          workspaceId,
          sessionId: context.sessionId,
          userId: context.userId,
          containerName: context.containerName,
          containerPort: context.containerPort,
          createdAt: context.createdAt,
          terminatedAt: context.terminatedAt,
          cleanupCompletedAt: context.cleanupCompletedAt,
          snapshotIds: context.snapshotIds,
          eventCount: context.eventLog.length,
        }),
      }

      this.deletionProofs.set(context.sessionId, proof)
      this.recordEvent({
        timestamp: deletedAt,
        eventType: WorkspaceLifecycleEventType.WORKSPACE_HARD_DELETED,
        workspaceId,
        sessionId: context.sessionId,
        actor,
        action: "Hard delete completed",
        reason,
        details: {
          checksum: proof.checksum,
          snapshotIds: proof.snapshotIds,
        },
        correlationId,
      })

      this.emitEvidencePack({
        context,
        teardownOutcome: "success",
        deletionProof: proof,
      })

      this.workspaces.delete(workspaceId)

      return {
        success: true,
        workspaceId,
        sessionId: context.sessionId,
        state: WorkspaceLifecycleState.TERMINATED,
        proof,
        correlationId,
      }
    } catch (error) {
      return {
        success: false,
        workspaceId,
        sessionId: context.sessionId,
        error: String(error),
        correlationId,
      }
    }
  }

  /**
   * Retrieve evidence pack by session ID.
   */
  getEvidencePackBySessionId(sessionId: string): WorkspaceEvidencePack | undefined {
    return this.evidencePacks.get(sessionId)
  }

  /**
   * Export a session evidence summary for operators and compliance reviewers.
   */
  exportEvidenceBySessionId(sessionId: string): WorkspaceEvidenceExport | undefined {
    const pack = this.evidencePacks.get(sessionId)
    if (!pack) {
      return undefined
    }

    const passed = pack.testOutcomes.filter((outcome) => outcome.status === "passed").length
    const failed = pack.testOutcomes.filter((outcome) => outcome.status === "failed").length
    const skipped = pack.testOutcomes.filter((outcome) => outcome.status === "skipped").length
    const artifactPaths = [...new Set(pack.testOutcomes.flatMap((outcome) => outcome.artifactPaths))]

    return {
      sessionId: pack.sessionId,
      workspaceId: pack.workspaceId,
      teardownOutcome: pack.teardownOutcome,
      createdAt: pack.createdAt,
      expiresAt: pack.expiresAt,
      manifestChecksum: pack.manifest.checksums.manifest,
      manifestSignature: pack.manifest.manifestSignature,
      eventCount: pack.lifecycleEvents.length,
      testOutcomeSummary: {
        passed,
        failed,
        skipped,
      },
      artifactPaths,
    }
  }

  /**
   * Verify integrity of an evidence manifest by recalculating checksum and signature.
   */
  verifyEvidenceManifest(sessionId: string): WorkspaceEvidenceVerificationResult | undefined {
    const pack = this.evidencePacks.get(sessionId)
    if (!pack) {
      return undefined
    }

    const rebuilt = this.buildEvidenceManifest({
      schemaVersion: pack.manifest.schemaVersion,
      sessionId: pack.sessionId,
      workspaceId: pack.workspaceId,
      generatedAt: pack.manifest.generatedAt,
      teardownOutcome: pack.teardownOutcome,
      policyVersion: pack.policyVersion,
      lifecycleEvents: pack.lifecycleEvents,
      testOutcomes: pack.testOutcomes,
      fingerprints: pack.fingerprints,
      deletionProof: pack.deletionProof,
    })

    return {
      valid:
        rebuilt.checksums.manifest === pack.manifest.checksums.manifest &&
        rebuilt.manifestSignature === pack.manifest.manifestSignature,
      sessionId,
      expectedChecksum: pack.manifest.checksums.manifest,
      actualChecksum: rebuilt.checksums.manifest,
      expectedSignature: pack.manifest.manifestSignature,
      actualSignature: rebuilt.manifestSignature,
    }
  }

  /**
   * Purge evidence packs past retention deadline.
   */
  enforceEvidenceRetention(nowSeconds = Date.now() / 1000): number {
    let purgedCount = 0
    for (const [sessionId, pack] of this.evidencePacks.entries()) {
      if (pack.expiresAt <= nowSeconds) {
        this.evidencePacks.delete(sessionId)
        purgedCount++
      }
    }
    return purgedCount
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
   * Reconcile terminated workspaces and force hard deletion when cleanup is complete.
   */
  async reconcileHardDeletes(): Promise<WorkspaceHardDeleteResult[]> {
    const results: WorkspaceHardDeleteResult[] = []

    for (const [workspaceId, context] of this.workspaces.entries()) {
      if (context.state !== WorkspaceLifecycleState.TERMINATED || !context.cleanupCompletedAt) {
        continue
      }

      const proof = this.deletionProofs.get(context.sessionId)
      if (proof) {
        continue
      }

      const result = await this.hardDeleteWorkspace(workspaceId, "system", "hard_delete_reconcile", `reconcile-${Date.now()}`)
      results.push(result)
    }

    return results
  }

  /**
   * Retrieve deletion proof by session ID.
   */
  getDeletionProofBySessionId(sessionId: string): WorkspaceDeletionProof | undefined {
    return this.deletionProofs.get(sessionId)
  }

  /**
   * Audit residual resources for a specific session or all sessions.
   */
  auditResidualResources(sessionId?: string): WorkspaceResidualAudit[] {
    const audits: WorkspaceResidualAudit[] = []
    const contexts = Array.from(this.workspaces.values()).filter((context) => !sessionId || context.sessionId === sessionId)
    const proof = sessionId ? this.deletionProofs.get(sessionId) : undefined

    for (const context of contexts) {
      audits.push({
        workspaceId: context.workspaceId,
        sessionId: context.sessionId,
        residualWorkspacePresent: true,
        residualSnapshotCount: context.snapshotIds.length,
        proofRecorded: this.deletionProofs.has(context.sessionId),
        proofChecksum: this.deletionProofs.get(context.sessionId)?.checksum,
        lastCleanupCompletedAt: context.cleanupCompletedAt,
      })
    }

    if (sessionId && !contexts.some((context) => context.sessionId === sessionId) && proof) {
      audits.push({
        workspaceId: proof.workspaceId,
        sessionId: proof.sessionId,
        residualWorkspacePresent: false,
        residualSnapshotCount: 0,
        proofRecorded: true,
        proofChecksum: proof.checksum,
        lastCleanupCompletedAt: proof.cleanupCompletedAt,
      })
    }

    return audits
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

        // Reconcile any terminated workspaces that still need hard deletion
        await this.reconcileHardDeletes()

        // Enforce evidence retention for compliance artifacts
        this.enforceEvidenceRetention()
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
      this.emitLiveProgressUpdate({
        context,
        event,
      })
    }
  }

  private determineLiveProgressStatus(params: {
    event: WorkspaceLifecycleEvent
    evidencePack?: WorkspaceEvidencePack
  }): "running" | "passed" | "failed" {
    if (params.evidencePack) {
      return params.evidencePack.teardownOutcome === "success" ? "passed" : "failed"
    }

    if (params.event.eventType === WorkspaceLifecycleEventType.WORKSPACE_FAILED) {
      return "failed"
    }

    if (
      params.event.eventType === WorkspaceLifecycleEventType.WORKSPACE_HARD_DELETED ||
      params.event.eventType === WorkspaceLifecycleEventType.CLEANUP_COMPLETED
    ) {
      return "passed"
    }

    return "running"
  }

  private emitLiveProgressUpdate(params: {
    context: WorkspaceLifecycleContext
    event: WorkspaceLifecycleEvent
    evidencePack?: WorkspaceEvidencePack
    testReport?: WorkspaceReadyTestReport
    statusOverride?: "running" | "passed" | "failed"
  }): void {
    const status =
      params.statusOverride ??
      this.determineLiveProgressStatus({
        event: params.event,
        evidencePack: params.evidencePack ?? this.evidencePacks.get(params.context.sessionId),
      })

    const update: WorkspaceLiveProgressUpdate = {
      sessionId: params.context.sessionId,
      workspaceId: params.context.workspaceId,
      state: params.context.state,
      status,
      timestamp: params.event.timestamp,
      eventType: params.event.eventType,
      action: params.event.action,
      reason: params.event.reason,
      details: params.event.details,
      correlationId: params.event.correlationId,
      evidence: params.evidencePack
        ? {
            teardownOutcome: params.evidencePack.teardownOutcome,
            manifestChecksum: params.evidencePack.manifest.checksums.manifest,
            manifestSignature: params.evidencePack.manifest.manifestSignature,
            artifactPaths: [
              ...new Set(
                params.evidencePack.testOutcomes.flatMap((outcome) => outcome.artifactPaths)
              ),
            ],
          }
        : undefined,
      testReport: params.testReport,
    }

    this.liveProgressSnapshots.set(params.context.sessionId, update)

    const history = this.liveProgressHistory.get(params.context.sessionId) || []
    history.push(update)
    if (history.length > 100) {
      history.shift()
    }
    this.liveProgressHistory.set(params.context.sessionId, history)

    for (const listener of this.liveProgressListeners) {
      try {
        const result = listener(update)
        if (result && typeof (result as Promise<void>).then === "function") {
          void (result as Promise<void>).catch((error) => {
            console.error(`Live progress listener failed: ${error}`)
          })
        }
      } catch (error) {
        console.error(`Live progress listener failed: ${error}`)
      }
    }
  }

  private async runHeadlessValidation(
    context: WorkspaceLifecycleContext,
    actor: string,
    correlationId: string
  ): Promise<void> {
    if (!this.config.readyTestTrigger || this.readyTestRuns.has(context.sessionId)) {
      return
    }

    this.readyTestRuns.add(context.sessionId)
    const startedAt = Date.now() / 1000

    try {
      const runningReport: WorkspaceReadyTestReport = {
        sessionId: context.sessionId,
        workspaceId: context.workspaceId,
        status: "running",
        startedAt,
        testOutcomes: [],
        artifactPaths: [],
        correlationId,
      }

      this.readyTestReports.set(context.sessionId, runningReport)
      this.emitLiveProgressUpdate({
        context,
        event: {
          timestamp: startedAt,
          eventType: WorkspaceLifecycleEventType.WORKSPACE_READY,
          workspaceId: context.workspaceId,
          sessionId: context.sessionId,
          actor,
          action: "Headless test execution started",
          reason: "ready_trigger",
          details: { readyTestStatus: "running" },
          correlationId,
        },
        statusOverride: "running",
        testReport: runningReport,
      })

      const testOutcomes = await this.runWithTimeout(
        Promise.resolve(this.config.readyTestTrigger(context)),
        this.config.readyTestTimeoutSeconds ?? 900,
        `ready test execution timed out after ${this.config.readyTestTimeoutSeconds ?? 900}s`
      )
      const completedAt = Date.now() / 1000
      const artifactPaths = [...new Set(testOutcomes.flatMap((outcome) => outcome.artifactPaths))]
      const status = testOutcomes.some((outcome) => outcome.status === "failed") ? "failed" : "passed"

      const completedReport: WorkspaceReadyTestReport = {
        sessionId: context.sessionId,
        workspaceId: context.workspaceId,
        status,
        startedAt,
        completedAt,
        durationSeconds: completedAt - startedAt,
        testOutcomes,
        artifactPaths,
        correlationId,
      }

      this.readyTestReports.set(context.sessionId, completedReport)
      this.emitLiveProgressUpdate({
        context,
        event: {
          timestamp: completedAt,
          eventType: WorkspaceLifecycleEventType.WORKSPACE_READY,
          workspaceId: context.workspaceId,
          sessionId: context.sessionId,
          actor,
          action: "Headless test execution completed",
          reason: status === "passed" ? "ready_trigger_passed" : "ready_trigger_failed",
          details: {
            readyTestStatus: status,
            durationSeconds: completedReport.durationSeconds,
            artifactPaths,
          },
          correlationId,
        },
        statusOverride: status,
        testReport: completedReport,
      })
    } catch (error) {
      const completedAt = Date.now() / 1000
      const failureReport: WorkspaceReadyTestReport = {
        sessionId: context.sessionId,
        workspaceId: context.workspaceId,
        status: "failed",
        startedAt,
        completedAt,
        durationSeconds: completedAt - startedAt,
        testOutcomes: this.createDefaultTestOutcome("failed"),
        artifactPaths: ["artifacts/ephemeral-workspace-evidence"],
        correlationId,
        failureReason: String(error),
      }

      this.readyTestReports.set(context.sessionId, failureReport)
      this.emitLiveProgressUpdate({
        context,
        event: {
          timestamp: completedAt,
          eventType: WorkspaceLifecycleEventType.WORKSPACE_FAILED,
          workspaceId: context.workspaceId,
          sessionId: context.sessionId,
          actor,
          action: "Headless test execution failed",
          reason: "ready_trigger_failed",
          details: { error: String(error) },
          correlationId,
        },
        statusOverride: "failed",
        testReport: failureReport,
      })
    } finally {
      this.readyTestRuns.delete(context.sessionId)
    }
  }

  /**
   * Register callback for live progress updates.
   */
  onLiveProgress(callback: WorkspaceLiveProgressListener): void {
    this.liveProgressListeners.add(callback)
  }

  /**
   * Get the latest live progress update by session ID.
   */
  getLiveProgressBySessionId(sessionId: string): WorkspaceLiveProgressUpdate | undefined {
    return this.liveProgressSnapshots.get(sessionId)
  }

  /**
   * Get the live progress feed for a session ID.
   */
  getLiveProgressFeed(sessionId: string): WorkspaceLiveProgressUpdate[] {
    return [...(this.liveProgressHistory.get(sessionId) || [])]
  }

  /**
   * Get the latest ready-state test report by session ID.
   */
  getReadyTestReportBySessionId(sessionId: string): WorkspaceReadyTestReport | undefined {
    return this.readyTestReports.get(sessionId)
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
    evidenceSchemaVersion: "ephemeral-evidence-v1",
    evidenceRetentionDays: 30,
    evidenceSigningSalt: "ephemeral-evidence-default-salt",
  }

  return new EphemeralWorkspaceLifecycleManager({
    ...defaultConfig,
    ...config,
  })
}

