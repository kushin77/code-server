/**
 * Batch Processing Engine Service
 * @file        apps/backend/src/services/batch-engine/batch-engine-service.ts
 * @module      services/batch-engine
 * @description Distributed batch job processing with queuing and retries
 */
import { EventEmitter } from 'events';
/**
 * Batch Engine Service
 * Manages batch job submission, processing, and result tracking
 */
export class BatchEngineService extends EventEmitter {
    constructor() {
        super();
        this.jobs = new Map();
        this.userJobs = new Map(); // userId -> jobIds
        this.queue = new Map(); // jobId -> entry
        this.queueOrder = []; // jobIds in priority order
        this.results = new Map();
        this.progress = new Map(); // jobId -> progress
        this.activeJobs = new Set(); // Currently running jobs
        this.auditLog = new Map(); // userId -> entries
        this.config = {
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
        this.initialize();
    }
    /**
     * Get or create singleton instance
     */
    static getInstance(config) {
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
    static reset() {
        BatchEngineService.instance = undefined;
    }
    /**
     * Initialize service
     */
    initialize() {
        this.emit('initialized', {
            data_object: { service: 'batch-engine', status: 'initialized' },
            timestamp: Date.now(),
        });
    }
    /**
     * Create job
     */
    createJob(job, userId, ipAddress, userAgent) {
        try {
            if (!this.config.enableBatchProcessing) {
                return { success: false };
            }
            const jobId = `job-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const fullJob = {
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
            this.userJobs.get(userId).add(jobId);
            this.logAudit(userId, 'create-job', jobId, {
                name: job.name,
                taskCount: job.tasks.length,
            });
            this.emit('job-created', {
                data_object: { jobId, userId, name: job.name },
                timestamp: Date.now(),
            });
            return { success: true, jobId };
        }
        catch (error) {
            this.logAudit(userId, 'create-job', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get job
     */
    getJob(jobId) {
        return this.jobs.get(jobId);
    }
    /**
     * Update job
     */
    updateJob(jobId, updates, userId, ipAddress, userAgent) {
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
        }
        catch (error) {
            this.logAudit(userId, 'update-job', jobId, {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Delete job
     */
    deleteJob(jobId, userId, ipAddress, userAgent) {
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
        }
        catch (error) {
            this.logAudit(userId, 'delete-job', jobId, {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get user jobs
     */
    getUserJobs(userId, limit) {
        const jobIds = this.userJobs.get(userId) || new Set();
        const jobs = [];
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
    addTask(jobId, task, userId, ipAddress, userAgent) {
        try {
            const job = this.jobs.get(jobId);
            if (!job) {
                return { success: false };
            }
            if (job.tasks.length >= this.config.maxTasksPerJob) {
                return { success: false };
            }
            const taskId = `task-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const fullTask = {
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
        }
        catch (error) {
            this.logAudit(userId, 'add-task', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Remove task
     */
    removeTask(jobId, taskId, userId, ipAddress, userAgent) {
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
        }
        catch (error) {
            this.logAudit(userId, 'remove-task', taskId, {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get task
     */
    getTask(jobId, taskId) {
        const job = this.jobs.get(jobId);
        if (!job)
            return undefined;
        return job.tasks.find((t) => t.taskId === taskId);
    }
    /**
     * Submit job
     */
    submitJob(jobId, userId, ipAddress, userAgent) {
        try {
            const job = this.jobs.get(jobId);
            if (!job) {
                return { success: false };
            }
            job.status = 'pending';
            const entryId = `entry-${Date.now()}-${Math.random().toString(16).slice(2)}`;
            const entry = {
                entryId,
                jobId,
                priority: job.priority,
                queuedAt: Date.now(),
                position: this.queueOrder.length,
            };
            this.queue.set(jobId, entry);
            this.queueOrder.push(jobId);
            this.queueOrder.sort((a, b) => {
                const jobA = this.jobs.get(a);
                const jobB = this.jobs.get(b);
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
        }
        catch (error) {
            this.logAudit(userId, 'submit-job', jobId, {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Cancel job
     */
    cancelJob(jobId, userId, ipAddress, userAgent) {
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
        }
        catch (error) {
            this.logAudit(userId, 'cancel-job', jobId, {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Pause job
     */
    pauseJob(jobId, userId, ipAddress, userAgent) {
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
        }
        catch (error) {
            this.logAudit(userId, 'pause-job', jobId, {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Resume job
     */
    resumeJob(jobId, userId, ipAddress, userAgent) {
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
        }
        catch (error) {
            this.logAudit(userId, 'resume-job', jobId, {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Process job
     */
    async processJob(jobId, userId, ipAddress, userAgent) {
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
            const taskResults = [];
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
                }
                catch (error) {
                    task.status = 'failed';
                    task.error = error.message;
                    task.completedAt = Date.now();
                    taskResults.push({
                        taskId: task.taskId,
                        status: 'failure',
                        error: error.message,
                        duration: Date.now() - taskStartTime,
                    });
                    failureCount++;
                }
                const progress = {
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
            const result = {
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
        }
        catch (error) {
            this.activeJobs.delete(jobId);
            const job = this.jobs.get(jobId);
            if (job) {
                job.status = 'failed';
            }
            this.logAudit(userId, 'process-job', jobId, {
                error: error.message,
            });
            throw error;
        }
    }
    /**
     * Get result
     */
    getResult(jobId) {
        return this.results.get(jobId);
    }
    /**
     * Get progress
     */
    getProgress(jobId) {
        return this.progress.get(jobId);
    }
    /**
     * Retry task
     */
    retryTask(jobId, taskId, userId, ipAddress, userAgent) {
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
        }
        catch (error) {
            this.logAudit(userId, 'retry-task', taskId, {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Get queue
     */
    getQueue(limit) {
        const entries = [];
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
    getQueuePosition(jobId) {
        return this.queueOrder.indexOf(jobId) + 1;
    }
    /**
     * Get statistics
     */
    getStatistics() {
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
            totalTasksProcessed: Array.from(this.results.values()).reduce((sum, r) => sum + r.taskResults.length, 0),
            averageThroughput: 0,
        };
    }
    /**
     * Get user statistics
     */
    getUserStatistics(userId) {
        const jobIds = this.userJobs.get(userId) || new Set();
        const userJobs = Array.from(jobIds)
            .map((id) => this.jobs.get(id))
            .filter((j) => j !== undefined);
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
    getAuditLog(limit) {
        const entries = [];
        for (const [, userEntries] of this.auditLog) {
            entries.push(...userEntries);
        }
        entries.sort((a, b) => b.timestamp - a.timestamp);
        return entries.slice(0, limit || 100);
    }
    /**
     * Cleanup old results
     */
    cleanupOldResults(daysOld, userId, ipAddress, userAgent) {
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
        }
        catch (error) {
            this.logAudit(userId, 'cleanup-results', '', {
                error: error.message,
            });
            return { success: false };
        }
    }
    /**
     * Log audit entry
     */
    logAudit(userId, action, jobId, details) {
        if (!this.auditLog.has(userId)) {
            this.auditLog.set(userId, []);
        }
        const entry = {
            timestamp: Date.now(),
            userId,
            userEmail: `user-${userId}@example.com`,
            action,
            jobId: jobId || undefined,
            details: details || {},
        };
        const logs = this.auditLog.get(userId);
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
    priorityValue(priority) {
        const values = {
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
    updateConfig(config) {
        this.config = { ...this.config, ...config };
        this.emit('config-updated', {
            data_object: { config: this.config },
            timestamp: Date.now(),
        });
    }
    /**
     * Shutdown service
     */
    shutdown() {
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
//# sourceMappingURL=batch-engine-service.js.map