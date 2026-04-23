/**
 * Batch Engine Service Tests
 * @file        apps/backend/src/services/batch-engine/__tests__/batch-engine-service.test.ts
 * @module      services/batch-engine
 * @description Test suite for batch processing functionality
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { BatchEngineService } from '../batch-engine-service.js';
describe('Batch Engine Service', () => {
    let service;
    beforeEach(() => {
        BatchEngineService.reset();
        service = BatchEngineService.getInstance();
    });
    afterEach(() => {
        service.shutdown();
    });
    // Initialization Tests
    describe('Initialization', () => {
        it('should initialize service', () => {
            expect(service).toBeDefined();
            expect(service.jobs).toBeDefined();
            expect(service.queue).toBeDefined();
        });
        it('should return same instance on subsequent calls', () => {
            const instance1 = BatchEngineService.getInstance();
            const instance2 = BatchEngineService.getInstance();
            expect(instance1).toBe(instance2);
        });
    });
    // Job Creation Tests
    describe('Job Creation', () => {
        it('should create job', () => {
            const result = service.createJob({
                userId: 'user1',
                userEmail: 'user1@example.com',
                name: 'Test Job',
                description: 'A test job',
                tasks: [],
                priority: 'normal',
                processingMode: 'sequential',
                concurrency: 1,
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.jobId).toBeDefined();
        });
        it('should emit job-created event', () => {
            return new Promise((resolve) => {
                service.once('job-created', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.createJob({
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    name: 'Test Job',
                    description: 'A test job',
                    tasks: [],
                    priority: 'normal',
                    processingMode: 'sequential',
                    concurrency: 1,
                    metadata: {},
                }, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should retrieve created job', () => {
            const created = service.createJob({
                userId: 'user1',
                userEmail: 'user1@example.com',
                name: 'Test Job',
                description: 'A test job',
                tasks: [],
                priority: 'normal',
                processingMode: 'sequential',
                concurrency: 1,
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const job = service.getJob(created.jobId);
            expect(job).toBeDefined();
            expect(job?.name).toBe('Test Job');
        });
    });
    // Job Management Tests
    describe('Job Management', () => {
        it('should update job', () => {
            const created = service.createJob({
                userId: 'user1',
                userEmail: 'user1@example.com',
                name: 'Test Job',
                description: 'A test job',
                tasks: [],
                priority: 'normal',
                processingMode: 'sequential',
                concurrency: 1,
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.updateJob(created.jobId, { priority: 'high' }, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should delete job', () => {
            const created = service.createJob({
                userId: 'user1',
                userEmail: 'user1@example.com',
                name: 'Test Job',
                description: 'A test job',
                tasks: [],
                priority: 'normal',
                processingMode: 'sequential',
                concurrency: 1,
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.deleteJob(created.jobId, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should get user jobs', () => {
            const jobs = service.getUserJobs('user1');
            expect(Array.isArray(jobs)).toBe(true);
        });
    });
    // Task Management Tests
    describe('Task Management', () => {
        it('should add task', () => {
            const created = service.createJob({
                userId: 'user1',
                userEmail: 'user1@example.com',
                name: 'Test Job',
                description: 'A test job',
                tasks: [],
                priority: 'normal',
                processingMode: 'sequential',
                concurrency: 1,
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.addTask(created.jobId, {
                name: 'Task 1',
                type: 'process',
                priority: 'normal',
                retries: 0,
                maxRetries: 3,
                data: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.taskId).toBeDefined();
        });
        it('should emit task-added event', () => {
            return new Promise((resolve) => {
                const created = service.createJob({
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    name: 'Test Job',
                    description: 'A test job',
                    tasks: [],
                    priority: 'normal',
                    processingMode: 'sequential',
                    concurrency: 1,
                    metadata: {},
                }, 'user1', '192.168.1.1', 'Mozilla');
                service.once('task-added', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.addTask(created.jobId, {
                    name: 'Task 1',
                    type: 'process',
                    priority: 'normal',
                    retries: 0,
                    maxRetries: 3,
                    data: {},
                }, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should remove task', () => {
            const created = service.createJob({
                userId: 'user1',
                userEmail: 'user1@example.com',
                name: 'Test Job',
                description: 'A test job',
                tasks: [],
                priority: 'normal',
                processingMode: 'sequential',
                concurrency: 1,
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const taskResult = service.addTask(created.jobId, {
                name: 'Task 1',
                type: 'process',
                priority: 'normal',
                retries: 0,
                maxRetries: 3,
                data: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.removeTask(created.jobId, taskResult.taskId, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should get task', () => {
            const created = service.createJob({
                userId: 'user1',
                userEmail: 'user1@example.com',
                name: 'Test Job',
                description: 'A test job',
                tasks: [],
                priority: 'normal',
                processingMode: 'sequential',
                concurrency: 1,
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const taskResult = service.addTask(created.jobId, {
                name: 'Task 1',
                type: 'process',
                priority: 'normal',
                retries: 0,
                maxRetries: 3,
                data: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const task = service.getTask(created.jobId, taskResult.taskId);
            expect(task).toBeDefined();
        });
    });
    // Job Submission Tests
    describe('Job Submission', () => {
        it('should submit job', () => {
            const created = service.createJob({
                userId: 'user1',
                userEmail: 'user1@example.com',
                name: 'Test Job',
                description: 'A test job',
                tasks: [],
                priority: 'normal',
                processingMode: 'sequential',
                concurrency: 1,
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.submitJob(created.jobId, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should emit job-submitted event', () => {
            return new Promise((resolve) => {
                const created = service.createJob({
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    name: 'Test Job',
                    description: 'A test job',
                    tasks: [],
                    priority: 'normal',
                    processingMode: 'sequential',
                    concurrency: 1,
                    metadata: {},
                }, 'user1', '192.168.1.1', 'Mozilla');
                service.once('job-submitted', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.submitJob(created.jobId, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
    });
    // Job Control Tests
    describe('Job Control', () => {
        it('should cancel job', () => {
            const created = service.createJob({
                userId: 'user1',
                userEmail: 'user1@example.com',
                name: 'Test Job',
                description: 'A test job',
                tasks: [],
                priority: 'normal',
                processingMode: 'sequential',
                concurrency: 1,
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.cancelJob(created.jobId, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should pause job', () => {
            const created = service.createJob({
                userId: 'user1',
                userEmail: 'user1@example.com',
                name: 'Test Job',
                description: 'A test job',
                tasks: [],
                priority: 'normal',
                processingMode: 'sequential',
                concurrency: 1,
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.pauseJob(created.jobId, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should resume job', () => {
            const created = service.createJob({
                userId: 'user1',
                userEmail: 'user1@example.com',
                name: 'Test Job',
                description: 'A test job',
                tasks: [],
                priority: 'normal',
                processingMode: 'sequential',
                concurrency: 1,
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            service.pauseJob(created.jobId, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.resumeJob(created.jobId, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
    });
    // Job Processing Tests
    describe('Job Processing', () => {
        it('should process job', async () => {
            const created = service.createJob({
                userId: 'user1',
                userEmail: 'user1@example.com',
                name: 'Test Job',
                description: 'A test job',
                tasks: [],
                priority: 'normal',
                processingMode: 'sequential',
                concurrency: 1,
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = await service.processJob(created.jobId, 'user1', '192.168.1.1', 'Mozilla');
            expect(result).toBeDefined();
            expect(result.status).toBeDefined();
        });
        it('should emit job-completed event', () => {
            return new Promise(async (resolve) => {
                const created = service.createJob({
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    name: 'Test Job',
                    description: 'A test job',
                    tasks: [],
                    priority: 'normal',
                    processingMode: 'sequential',
                    concurrency: 1,
                    metadata: {},
                }, 'user1', '192.168.1.1', 'Mozilla');
                service.once('job-completed', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                await service.processJob(created.jobId, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should get job result', async () => {
            const created = service.createJob({
                userId: 'user1',
                userEmail: 'user1@example.com',
                name: 'Test Job',
                description: 'A test job',
                tasks: [],
                priority: 'normal',
                processingMode: 'sequential',
                concurrency: 1,
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            await service.processJob(created.jobId, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.getResult(created.jobId);
            expect(result).toBeDefined();
        });
        it('should get job progress', async () => {
            const created = service.createJob({
                userId: 'user1',
                userEmail: 'user1@example.com',
                name: 'Test Job',
                description: 'A test job',
                tasks: [],
                priority: 'normal',
                processingMode: 'sequential',
                concurrency: 1,
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            await service.processJob(created.jobId, 'user1', '192.168.1.1', 'Mozilla');
            const progress = service.getProgress(created.jobId);
            expect(progress).toBeDefined();
        });
    });
    // Task Retry Tests
    describe('Task Retry', () => {
        it('should retry task', () => {
            const created = service.createJob({
                userId: 'user1',
                userEmail: 'user1@example.com',
                name: 'Test Job',
                description: 'A test job',
                tasks: [],
                priority: 'normal',
                processingMode: 'sequential',
                concurrency: 1,
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const taskResult = service.addTask(created.jobId, {
                name: 'Task 1',
                type: 'process',
                priority: 'normal',
                retries: 0,
                maxRetries: 3,
                data: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            const result = service.retryTask(created.jobId, taskResult.taskId, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
    });
    // Queue Tests
    describe('Queue', () => {
        it('should get queue', () => {
            const queue = service.getQueue();
            expect(Array.isArray(queue)).toBe(true);
        });
        it('should get queue position', () => {
            const created = service.createJob({
                userId: 'user1',
                userEmail: 'user1@example.com',
                name: 'Test Job',
                description: 'A test job',
                tasks: [],
                priority: 'normal',
                processingMode: 'sequential',
                concurrency: 1,
                metadata: {},
            }, 'user1', '192.168.1.1', 'Mozilla');
            service.submitJob(created.jobId, 'user1', '192.168.1.1', 'Mozilla');
            const position = service.getQueuePosition(created.jobId);
            expect(typeof position).toBe('number');
        });
    });
    // Statistics Tests
    describe('Statistics', () => {
        it('should get service statistics', () => {
            const stats = service.getStatistics();
            expect(stats).toBeDefined();
            expect(stats.totalJobs).toBeGreaterThanOrEqual(0);
        });
        it('should get user statistics', () => {
            const stats = service.getUserStatistics('user1');
            expect(stats).toBeDefined();
            expect(stats.userId).toBe('user1');
        });
    });
    // Audit Logging Tests
    describe('Audit Logging', () => {
        it('should emit audit-logged event', () => {
            return new Promise((resolve) => {
                service.once('audit-logged', (event) => {
                    expect(event.data_object.userId).toBeDefined();
                    resolve();
                });
                service.createJob({
                    userId: 'user1',
                    userEmail: 'user1@example.com',
                    name: 'Test Job',
                    description: 'A test job',
                    tasks: [],
                    priority: 'normal',
                    processingMode: 'sequential',
                    concurrency: 1,
                    metadata: {},
                }, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
        it('should retrieve audit log', () => {
            const log = service.getAuditLog();
            expect(Array.isArray(log)).toBe(true);
        });
    });
    // Cleanup Tests
    describe('Cleanup', () => {
        it('should cleanup old results', () => {
            const result = service.cleanupOldResults(30, 'user1', '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
        });
        it('should emit cleanup-completed event', () => {
            return new Promise((resolve) => {
                service.once('cleanup-completed', (event) => {
                    expect(event.data_object.userId).toBe('user1');
                    resolve();
                });
                service.cleanupOldResults(30, 'user1', '192.168.1.1', 'Mozilla');
            });
        });
    });
    // Configuration Tests
    describe('Configuration', () => {
        it('should update configuration', () => {
            return new Promise((resolve) => {
                service.once('config-updated', (event) => {
                    expect(event.data_object.config).toBeDefined();
                    resolve();
                });
                service.updateConfig({ maxConcurrentJobs: 20 });
            });
        });
    });
    // Shutdown Tests
    describe('Shutdown', () => {
        it('should shutdown service cleanly', () => {
            service.shutdown();
            expect(service.jobs.size).toBe(0);
            expect(service.queue.size).toBe(0);
        });
    });
});
//# sourceMappingURL=batch-engine-service.test.js.map