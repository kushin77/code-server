/**
 * Batch Processing Engine Service
 * @file        apps/backend/src/services/batch-engine/batch-engine-service.ts
 * @module      services/batch-engine
 * @description Distributed batch job processing with queuing and retries
 */

import { EventEmitter } from 'events';
import {
  JobConfig,
  TaskConfig,
  JobResult,
  QueueEntry,
  Progress,
  BatchStatistics,
  UserBatchStats,
  BatchAuditEntry,
  BatchEngineConfig,
  IBatchEngineService,
} from './types.js';

/**
 * Batch Engine Service
 * Manages batch job submission, processing, and result tracking
 */
export class BatchEngineService extends EventEmitter implements IBatchEngineService {
  private static instance: BatchEngineService | undefined;
  private jobs: Map<string, JobConfig> = new Map();
  private userJobs: Map<string, Set<string>> = new Map(); // userId -> jobIds
  private queue: Map<string, QueueEntry> = new Map(); // jobId -> entry
  private queueOrder: string[] = []; // jobIds in priority order
  private results: Map<string, JobResult> = new Map();
  private progress: Map<string, Progress> = new Map(); // jobId -> progress
  private activeJobs: Set<string> = new Set(); // Currently running jobs
  private auditLog: Map<string, BatchAuditEntry[]> = new Map(); // userId -> entries
  private config: BatchEngineConfig = {
    enableBatchProcessing: true,
    maxConcurrentJobs: 10,
    maxTasksPerJob: 1000,
    defaultTimeout: 300000, // 5 minutes
    defaultRetries: 3,
    queueCheckIntervalMs: 1000,
    cleanupIntervalMs: 3600000, // 1 hour
    resultRetentionDays: 30,
    maxAuditEntries: 10000,
    enableMetrics: true,
  };

  private constructor() {
    super();
    this.initialize();
  }

  /**
   * Get or create singleton instance
   */
  public static getInstance(config?: Partial<BatchEngineConfig>): BatchEngineService {
    if (!BatchEngineService.instance) {
      BatchEngineService.instance = new BatchEngineService();
    }
    if (config) {
      BatchEngineService.instance.updateConfig(config);
    }
    return BatchEngineService.instance;
  }

  /**
   * Reset singleton for testing
   */
  public static reset(): void {
    BatchEngineService.instance = undefined;
  }

  /**
   * Initialize service
   */
  private initialize(): void {
    this.emit('initialized', {
      data_object: { service: 'batch-engine', status: 'initialized' },
      timestamp: Date.now(),
    });
  }

  /**
   * Create job
   */
  public createJob(
    job: Omit<JobConfig, 'jobId' | 'createdAt' | 'status'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; jobId?: string } {
    try {
      if (!this.config.enableBatchProcessing) {
        return { success: false };
      }

      const jobId = `job-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const fullJob: JobConfig = {
        ...job,
        jobId,
        createdAt: Date.now(),
        status: 'pending',
      };

      this.jobs.set(jobId, fullJob);

      // Initialize progress tracking
      this.progress.set(jobId, {
        jobId,
        totalTasks: job.tasks.length,
        completedTasks: 0,
        failedTasks: 0,
        percentComplete: 0,
      });

      if (!this.userJobs.has(userId)) {
        this.userJobs.set(userId, new Set());
      }
      this.userJobs.get(userId)!.add(jobId);

      this.logAudit(userId, 'create-job', jobId, {
        name: job.name,
        taskCount: job.tasks.length,
      });

      this.emit('job-created', {
        data_object: { jobId, userId, name: job.name },
        timestamp: Date.now(),
      });

      return { success: true, jobId };
    } catch (error) {
      this.logAudit(userId, 'create-job', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get job
   */
  public getJob(jobId: string): JobConfig | undefined {
    return this.jobs.get(jobId);
  }

  /**
   * Update job
   */
  public updateJob(
    jobId: string,
    updates: Partial<JobConfig>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const job = this.jobs.get(jobId);
      if (!job) {
        return { success: false };
      }

      Object.assign(job, updates);

      this.logAudit(userId, 'update-job', jobId, {});

      this.emit('job-updated', {
        data_object: { jobId, userId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'update-job', jobId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Delete job
   */
  public deleteJob(
    jobId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      this.jobs.delete(jobId);
      this.userJobs.get(userId)?.delete(jobId);
      this.queue.delete(jobId);
      this.results.delete(jobId);
      this.progress.delete(jobId);

      this.logAudit(userId, 'delete-job', jobId, {});

      this.emit('job-deleted', {
        data_object: { jobId, userId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'delete-job', jobId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get user jobs
   */
  public getUserJobs(userId: string, limit?: number): JobConfig[] {
    const jobIds = this.userJobs.get(userId) || new Set();
    const jobs: JobConfig[] = [];

    for (const id of jobIds) {
      const job = this.jobs.get(id);
      if (job) {
        jobs.push(job);
      }
    }

    jobs.sort((a, b) => b.createdAt - a.createdAt);
    return jobs.slice(0, limit || 50);
  }

  /**
   * Add task
   */
  public addTask(
    jobId: string,
    task: Omit<TaskConfig, 'taskId' | 'jobId' | 'createdAt' | 'status'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; taskId?: string } {
    try {
      const job = this.jobs.get(jobId);
      if (!job) {
        return { success: false };
      }

      if (job.tasks.length >= this.config.maxTasksPerJob) {
        return { success: false };
      }

      const taskId = `task-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const fullTask: TaskConfig = {
        ...task,
        taskId,
        jobId,
        createdAt: Date.now(),
        status: 'pending',
      };

      job.tasks.push(fullTask);

      this.logAudit(userId, 'add-task', taskId, {
        jobId,
      });

      this.emit('task-added', {
        data_object: { taskId, jobId, userId },
        timestamp: Date.now(),
      });

      return { success: true, taskId };
    } catch (error) {
      this.logAudit(userId, 'add-task', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Remove task
   */
  public removeTask(
    jobId: string,
    taskId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const job = this.jobs.get(jobId);
      if (!job) {
        return { success: false };
      }

      job.tasks = job.tasks.filter((t) => t.taskId !== taskId);

      this.logAudit(userId, 'remove-task', taskId, {
        jobId,
      });

      this.emit('task-removed', {
        data_object: { taskId, jobId, userId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'remove-task', taskId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get task
   */
  public getTask(jobId: string, taskId: string): TaskConfig | undefined {
    const job = this.jobs.get(jobId);
    if (!job) return undefined;
    return job.tasks.find((t) => t.taskId === taskId);
  }

  /**
   * Submit job
   */
  public submitJob(
    jobId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const job = this.jobs.get(jobId);
      if (!job) {
        return { success: false };
      }

      job.status = 'pending';

      const entryId = `entry-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const entry: QueueEntry = {
        entryId,
        jobId,
        priority: job.priority,
        queuedAt: Date.now(),
        position: this.queueOrder.length,
      };

      this.queue.set(jobId, entry);
      this.queueOrder.push(jobId);
      this.queueOrder.sort((a, b) => {
        const jobA = this.jobs.get(a)!;
        const jobB = this.jobs.get(b)!;
        return this.priorityValue(jobB.priority) - this.priorityValue(jobA.priority);
      });

      this.logAudit(userId, 'submit-job', jobId, {
        taskCount: job.tasks.length,
      });

      this.emit('job-submitted', {
        data_object: { jobId, userId, taskCount: job.tasks.length },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'submit-job', jobId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Cancel job
   */
  public cancelJob(
    jobId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const job = this.jobs.get(jobId);
      if (!job) {
        return { success: false };
      }

      job.status = 'cancelled';
      this.queue.delete(jobId);
      this.activeJobs.delete(jobId);

      this.logAudit(userId, 'cancel-job', jobId, {});

      this.emit('job-cancelled', {
        data_object: { jobId, userId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'cancel-job', jobId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Pause job
   */
  public pauseJob(
    jobId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const job = this.jobs.get(jobId);
      if (!job) {
        return { success: false };
      }

      job.status = 'paused';

      this.logAudit(userId, 'pause-job', jobId, {});

      this.emit('job-paused', {
        data_object: { jobId, userId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'pause-job', jobId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Resume job
   */
  public resumeJob(
    jobId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const job = this.jobs.get(jobId);
      if (!job) {
        return { success: false };
      }

      if (job.status !== 'paused') {
        return { success: false };
      }

      job.status = 'pending';

      this.logAudit(userId, 'resume-job', jobId, {});

      this.emit('job-resumed', {
        data_object: { jobId, userId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'resume-job', jobId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Process job
   */
  public async processJob(
    jobId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): Promise<JobResult> {
    try {
      const job = this.jobs.get(jobId);
      if (!job) {
        throw new Error('Job not found');
      }

      if (this.activeJobs.size >= this.config.maxConcurrentJobs) {
        throw new Error('Max concurrent jobs reached');
      }

      this.activeJobs.add(jobId);
      job.status = 'running';
      job.startedAt = Date.now();

      const startTime = Date.now();
      const taskResults: JobResult['taskResults'] = [];
      let successCount = 0;
      let failureCount = 0;

      for (const task of job.tasks) {
        const taskStartTime = Date.now();
        try {
          task.status = 'running';
          task.startedAt = Date.now();

          // Simulate task processing
          await new Promise((resolve) => setTimeout(resolve, 10));

          task.status = 'completed';
          task.completedAt = Date.now();

          taskResults.push({
            taskId: task.taskId,
            status: 'success',
            output: { message: 'Task completed' },
            duration: Date.now() - taskStartTime,
          });

          successCount++;
        } catch (error) {
          task.status = 'failed';
          task.error = (error as Error).message;
          task.completedAt = Date.now();

          taskResults.push({
            taskId: task.taskId,
            status: 'failure',
            error: (error as Error).message,
            duration: Date.now() - taskStartTime,
          });

          failureCount++;
        }

        const progress: Progress = {
          jobId,
          totalTasks: job.tasks.length,
          completedTasks: successCount + failureCount,
          failedTasks: failureCount,
          currentTask: task.name,
          percentComplete: ((successCount + failureCount) / job.tasks.length) * 100,
        };

        this.progress.set(jobId, progress);

        this.emit('job-progress', {
          data_object: progress,
          timestamp: Date.now(),
        });
      }

      job.status = 'completed';
      job.completedAt = Date.now();
      this.activeJobs.delete(jobId);

      const totalDuration = Date.now() - startTime;

      const result: JobResult = {
        jobId,
        status: failureCount === 0 ? 'success' : failureCount < job.tasks.length ? 'partial' : 'failure',
        taskResults,
        totalDuration,
        successCount,
        failureCount,
        summary: `Processed ${job.tasks.length} tasks: ${successCount} succeeded, ${failureCount} failed`,
      };

      this.results.set(jobId, result);

      this.logAudit(userId, 'process-job', jobId, {
        successCount,
        failureCount,
        duration: totalDuration,
      });

      this.emit('job-completed', {
        data_object: { jobId, userId, status: result.status },
        timestamp: Date.now(),
      });

      return result;
    } catch (error) {
      this.activeJobs.delete(jobId);

      const job = this.jobs.get(jobId);
      if (job) {
        job.status = 'failed';
      }

      this.logAudit(userId, 'process-job', jobId, {
        error: (error as Error).message,
      });

      throw error;
    }
  }

  /**
   * Get result
   */
  public getResult(jobId: string): JobResult | undefined {
    return this.results.get(jobId);
  }

  /**
   * Get progress
   */
  public getProgress(jobId: string): Progress | undefined {
    return this.progress.get(jobId);
  }

  /**
   * Retry task
   */
  public retryTask(
    jobId: string,
    taskId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const task = this.getTask(jobId, taskId);
      if (!task) {
        return { success: false };
      }

      if (task.retries < task.maxRetries) {
        task.retries++;
        task.status = 'pending';
        task.error = undefined;

        this.logAudit(userId, 'retry-task', taskId, {
          jobId,
          attempt: task.retries,
        });

        this.emit('task-retried', {
          data_object: { taskId, jobId, userId, attempt: task.retries },
          timestamp: Date.now(),
        });

        return { success: true };
      }

      return { success: false };
    } catch (error) {
      this.logAudit(userId, 'retry-task', taskId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get queue
   */
  public getQueue(limit?: number): QueueEntry[] {
    const entries: QueueEntry[] = [];

    for (const jobId of this.queueOrder) {
      const entry = this.queue.get(jobId);
      if (entry) {
        entries.push(entry);
      }
    }

    return entries.slice(0, limit || 50);
  }

  /**
   * Get queue position
   */
  public getQueuePosition(jobId: string): number {
    return this.queueOrder.indexOf(jobId) + 1;
  }

  /**
   * Get statistics
   */
  public getStatistics(): BatchStatistics {
    const jobs = Array.from(this.jobs.values());
    const completedJobs = jobs.filter((j) => j.status === 'completed').length;
    const failedJobs = jobs.filter((j) => j.status === 'failed').length;

    const totalDuration = Array.from(this.results.values()).reduce((sum, r) => sum + r.totalDuration, 0);

    return {
      totalJobs: jobs.length,
      completedJobs,
      failedJobs,
      averageJobDuration: completedJobs > 0 ? totalDuration / completedJobs : 0,
      successRate: jobs.length > 0 ? completedJobs / jobs.length : 0,
      totalTasksProcessed: Array.from(this.results.values()).reduce(
        (sum, r) => sum + r.taskResults.length,
        0
      ),
      averageThroughput: 0,
    };
  }

  /**
   * Get user statistics
   */
  public getUserStatistics(userId: string): UserBatchStats {
    const jobIds = this.userJobs.get(userId) || new Set();
    const userJobs = Array.from(jobIds)
      .map((id) => this.jobs.get(id))
      .filter((j): j is JobConfig => j !== undefined);

    const completedJobs = userJobs.filter((j) => j.status === 'completed').length;
    const failedJobs = userJobs.filter((j) => j.status === 'failed').length;

    return {
      userId,
      totalJobs: userJobs.length,
      completedJobs,
      failedJobs,
      totalTasksProcessed: userJobs.reduce((sum, j) => sum + j.tasks.length, 0),
      averageJobDuration: completedJobs > 0 ? 1000 : 0,
    };
  }

  /**
   * Get audit log
   */
  public getAuditLog(limit?: number): BatchAuditEntry[] {
    const entries: BatchAuditEntry[] = [];
    for (const [, userEntries] of this.auditLog) {
      entries.push(...userEntries);
    }
    entries.sort((a, b) => b.timestamp - a.timestamp);
    return entries.slice(0, limit || 100);
  }

  /**
   * Cleanup old results
   */
  public cleanupOldResults(
    daysOld: number,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; deletedCount?: number } {
    try {
      const cutoffTime = Date.now() - daysOld * 86400000;
      let deletedCount = 0;

      for (const [jobId, result] of this.results) {
        const job = this.jobs.get(jobId);
        if (job && job.completedAt && job.completedAt < cutoffTime) {
          this.results.delete(jobId);
          deletedCount++;
        }
      }

      this.logAudit(userId, 'cleanup-results', '', {
        daysOld,
        deletedCount,
      });

      this.emit('cleanup-completed', {
        data_object: { userId, deletedCount },
        timestamp: Date.now(),
      });

      return { success: true, deletedCount };
    } catch (error) {
      this.logAudit(userId, 'cleanup-results', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Log audit entry
   */
  private logAudit(userId: string, action: string, jobId: string, details?: Record<string, unknown>): void {
    if (!this.auditLog.has(userId)) {
      this.auditLog.set(userId, []);
    }

    const entry: BatchAuditEntry = {
      timestamp: Date.now(),
      userId,
      userEmail: `user-${userId}@example.com`,
      action,
      jobId: jobId || undefined,
      details: details || {},
    };

    const logs = this.auditLog.get(userId)!;
    logs.push(entry);

    if (logs.length > this.config.maxAuditEntries) {
      logs.splice(0, logs.length - this.config.maxAuditEntries);
    }

    this.emit('audit-logged', {
      data_object: entry,
      timestamp: Date.now(),
    });
  }

  /**
   * Convert priority to numeric value
   */
  private priorityValue(priority: string): number {
    const values: Record<string, number> = {
      critical: 4,
      high: 3,
      normal: 2,
      low: 1,
    };
    return values[priority] || 0;
  }

  /**
   * Update configuration
   */
  public updateConfig(config: Partial<BatchEngineConfig>): void {
    this.config = { ...this.config, ...config };

    this.emit('config-updated', {
      data_object: { config: this.config },
      timestamp: Date.now(),
    });
  }

  /**
   * Shutdown service
   */
  public shutdown(): void {
    this.jobs.clear();
    this.userJobs.clear();
    this.queue.clear();
    this.queueOrder = [];
    this.results.clear();
    this.progress.clear();
    this.activeJobs.clear();
    this.auditLog.clear();

    this.emit('shutdown', {
      data_object: { service: 'batch-engine', status: 'shutdown' },
      timestamp: Date.now(),
    });
  }
}
