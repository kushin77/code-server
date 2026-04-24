/**
 * Session Hibernation Service Types
 * CRIU checkpoint idle workspaces with sub-5s wake times and 80% RAM savings
 */

/**
 * Hibernation state of a session
 */
export type HibernationState = 'active' | 'hibernating' | 'restored' | 'failed';

/**
 * Session hibernation checkpoint (CRIU-compatible)
 */
export interface HibernationCheckpoint {
  id: string;
  sessionId: string;
  userId: string;
  workspaceId: string;
  checkpointedAt: number; // timestamp
  checkpointPath: string; // filesystem path to checkpoint
  checkpointSizeBytes: number;
  processesCheckpointed: number;
  fileDescriptorsCheckpointed: number;
  memorySnapshotBytes: number;
  ramSavedPercent: number; // should be ~80%
  durationMs: number; // time to create checkpoint
  criuVersion: string;
  kernelVersion: string;
  state: HibernationState;
  metadata: {
    containerRuntime: 'docker' | 'podman' | 'containerd';
    runtimeVersion: string;
    imageSha256: string;
    launchCommand: string[];
    environmentVars: Record<string, string>;
    networkConfig: {
      hostname: string;
      ipAddress: string;
      ports: number[];
    };
    volumeMounts: Array<{
      source: string;
      target: string;
      readOnly: boolean;
    }>;
  };
}

/**
 * Hibernation statistics
 */
export interface HibernationStats {
  totalCheckpoints: number;
  successfulCheckpoints: number;
  failedCheckpoints: number;
  totalRestores: number;
  successfulRestores: number;
  failedRestores: number;
  averageCheckpointDurationMs: number;
  averageRestoreDurationMs: number;
  averageRamSavedPercent: number;
  totalRamSavedBytes: number;
  lastCheckpointedAt: number | null;
  lastRestoredAt: number | null;
}

/**
 * Hibernation session snapshot
 */
export interface HibernationSession {
  id: string;
  sessionId: string;
  userId: string;
  workspaceId: string;
  idleThresholdMs: number; // time to consider session idle
  lastActivityAt: number;
  hibernationStartedAt: number | null;
  hibernationState: HibernationState;
  checkpoints: HibernationCheckpoint[];
  currentCheckpoint: HibernationCheckpoint | null;
  autoHibernationEnabled: boolean;
  wakeupScheduled: boolean;
  wakeupTime: number | null;
}

/**
 * Hibernation configuration
 */
export interface HibernationConfig {
  enableAutoHibernation: boolean;
  idleThresholdMs: number; // default 5 minutes
  checkpointIntervalMs: number;
  maxCheckpointsPerSession: number;
  criuPath: string;
  checkpointStoragePath: string;
  enableCompression: boolean;
  encryptionEnabled: boolean;
  maxHibernatedSessions: number;
  wakeupGracePeriodMs: number; // time between wake signal and actual restoration
  restoreTimeoutMs: number; // must complete within this time
  maxAuditLogSize: number;
  storageBackend: 'filesystem' | 'ceph' | 's3';
}

/**
 * Checkpoint request
 */
export interface CheckpointRequest {
  sessionId: string;
  userId: string;
  workspaceId: string;
  force: boolean; // force checkpoint even if not idle
  includeProcesses: boolean;
  includeMemory: boolean;
  compress: boolean;
}

/**
 * Checkpoint result
 */
export interface CheckpointResult {
  checkpoint: HibernationCheckpoint;
  duration: number; // actual checkpoint time in ms
  ramSaved: number; // bytes of RAM saved
  ramSavedPercent: number;
  success: boolean;
  reason?: string;
}

/**
 * Restore request
 */
export interface RestoreRequest {
  checkpointId: string;
  sessionId: string;
  userId: string;
  workspaceId: string;
}

/**
 * Restore result
 */
export interface RestoreResult {
  checkpoint: HibernationCheckpoint;
  sessionId: string;
  duration: number; // actual restore time in ms, must be < 5000
  processesRestored: number;
  memoryRestored: number;
  success: boolean;
  reason?: string;
}

/**
 * Audit log entry for hibernation operations
 */
export interface HibernationAuditEntry {
  id: string;
  userId: string;
  userEmail: string;
  operation: 'checkpoint' | 'restore' | 'delete' | 'wake' | 'config-update';
  status: 'success' | 'failure' | 'pending';
  sessionId: string;
  checkpointId?: string;
  ipAddress: string;
  userAgent: string;
  timestamp: number;
  details: {
    ramSaved?: number;
    duration?: number;
    checkpointSize?: number;
    errorMessage?: string;
    [key: string]: unknown;
  };
}

/**
 * Wake-up trigger
 */
export type WakeupTrigger = 'manual' | 'scheduled' | 'activity-detected' | 'api-call' | 'webhook';

/**
 * Wake-up event
 */
export interface WakeupEvent {
  id: string;
  checkpointId: string;
  trigger: WakeupTrigger;
  triggeredAt: number;
  restoreStartedAt: number;
  restoreCompletedAt: number | null;
  duration: number | null;
  success: boolean;
  metadata: {
    triggerSource?: string;
    webhookId?: string;
    reason?: string;
  };
}
