/**
 * Batch Processing Engine Types
 * @file        apps/backend/src/services/batch-engine/types.ts
 * @module      services/batch-engine
 * @description Type definitions for batch processing functionality
 */

/**
 * Batch job status
 */
export type JobStatus = 'pending' | 'running' | 'completed' | 'failed' | 'cancelled' | 'paused';

/**
 * Batch priority level
 */
export type JobPriority = 'critical' | 'high' | 'normal' | 'low';

/**
 * Batch processing mode
 */
export type ProcessingMode = 'sequential' | 'parallel' | 'distributed';

/**
 * Job result status
 */
export type ResultStatus = 'success' | 'failure' | 'partial' | 'timeout';

/**
 * Task configuration
 */
export interface TaskConfig {
  taskId: string;
  jobId: string;
  name: string;
  type: string;
  priority: JobPriority;
  retries: number;
  maxRetries: number;
  timeout?: number;
  data: Record<string, unknown>;
  status: JobStatus;
  createdAt: number;
  startedAt?: number;
  completedAt?: number;
  error?: string;
}

/**
 * Batch job configuration
 */
export interface JobConfig {
  jobId: string;
  userId: string;
  userEmail: string;
  name: string;
  description: string;
  tasks: TaskConfig[];
  status: JobStatus;
  priority: JobPriority;
  processingMode: ProcessingMode;
  concurrency: number;
  timeout?: number;
  createdAt: number;
  startedAt?: number;
  completedAt?: number;
  metadata: Record<string, unknown>;
}

/**
 * Job result
 */
export interface JobResult {
  jobId: string;
  status: ResultStatus;
  taskResults: Array<{
    taskId: string;
    status: ResultStatus;
    output?: unknown;
    error?: string;
    duration: number;
  }>;
  totalDuration: number;
  successCount: number;
  failureCount: number;
  summary: string;
}

/**
 * Batch queue entry
 */
export interface QueueEntry {
  entryId: string;
  jobId: string;
  priority: JobPriority;
  queuedAt: number;
  estimatedStartTime?: number;
  position: number;
}

/**
 * Progress tracking
 */
export interface Progress {
  jobId: string;
  totalTasks: number;
  completedTasks: number;
  failedTasks: number;
  currentTask?: string;
  percentComplete: number;
  estimatedRemainingTime?: number;
}

/**
 * Batch statistics
 */
export interface BatchStatistics {
  totalJobs: number;
  completedJobs: number;
  failedJobs: number;
  averageJobDuration: number;
  successRate: number;
  totalTasksProcessed: number;
  averageThroughput: number;
}

/**
 * User batch statistics
 */
export interface UserBatchStats {
  userId: string;
  totalJobs: number;
  completedJobs: number;
  failedJobs: number;
  totalTasksProcessed: number;
  averageJobDuration: number;
}

/**
 * Retry policy
 */
export interface RetryPolicy {
  maxRetries: number;
  backoffMs: number;
  backoffMultiplier: number;
  maxBackoffMs: number;
}

/**
 * Execution context
 */
export interface ExecutionContext {
  jobId: string;
  taskId: string;
  userId: string;
  attemptNumber: number;
  startTime: number;
}

/**
 * Batch audit entry
 */
export interface BatchAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  action: string;
  jobId?: string;
  taskId?: string;
  details: Record<string, unknown>;
}

/**
 * Service configuration
 */
export interface BatchEngineConfig {
  enableBatchProcessing: boolean;
  maxConcurrentJobs: number;
  maxTasksPerJob: number;
  defaultTimeout: number;
  defaultRetries: number;
  queueCheckIntervalMs: number;
  cleanupIntervalMs: number;
  resultRetentionDays: number;
  maxAuditEntries: number;
  enableMetrics: boolean;
}

/**
 * Batch engine service interface
 */
export interface IBatchEngineService {
  createJob(
    job: Omit<JobConfig, 'jobId' | 'createdAt' | 'status'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; jobId?: string };

  getJob(jobId: string): JobConfig | undefined;

  updateJob(
    jobId: string,
    updates: Partial<JobConfig>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  deleteJob(
    jobId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  getUserJobs(userId: string, limit?: number): JobConfig[];

  addTask(
    jobId: string,
    task: Omit<TaskConfig, 'taskId' | 'jobId' | 'createdAt' | 'status'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; taskId?: string };

  removeTask(
    jobId: string,
    taskId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  getTask(jobId: string, taskId: string): TaskConfig | undefined;

  submitJob(
    jobId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  cancelJob(
    jobId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  pauseJob(
    jobId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  resumeJob(
    jobId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  processJob(
    jobId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): Promise<JobResult>;

  getResult(jobId: string): JobResult | undefined;

  getProgress(jobId: string): Progress | undefined;

  retryTask(
    jobId: string,
    taskId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  getQueue(limit?: number): QueueEntry[];

  getQueuePosition(jobId: string): number;

  getStatistics(): BatchStatistics;

  getUserStatistics(userId: string): UserBatchStats;

  getAuditLog(limit?: number): BatchAuditEntry[];

  cleanupOldResults(
    daysOld: number,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; deletedCount?: number };

  updateConfig(config: Partial<BatchEngineConfig>): void;

  shutdown(): void;
}
