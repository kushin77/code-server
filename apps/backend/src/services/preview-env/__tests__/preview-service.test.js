/**
 * @file        apps/backend/src/services/preview-env/__tests__/preview-service.test.ts
 * @module      devops/preview-environments
 * @description Preview environment service comprehensive tests
 */
import { describe, it, expect, beforeEach } from 'vitest';
import { PreviewEnvironmentService, getPreviewEnvironmentService, } from '../preview-service.js';
describe('Preview Environment Service', () => {
    let previewService;
    beforeEach(async () => {
        previewService = new PreviewEnvironmentService();
        await previewService.initialize();
    });
    describe('Service Initialization', () => {
        it('should initialize successfully', async () => {
            expect(previewService).toBeDefined();
        });
        it('should emit initialized event', async () => {
            return new Promise((resolve) => {
                const service = new PreviewEnvironmentService();
                service.once('initialized', () => {
                    resolve();
                });
                service.initialize();
            });
        });
    });
    describe('Provisioning', () => {
        it('should provision new environment', async () => {
            const config = {
                frontend: { enabled: true, port: 3000 },
                backend: { enabled: true, port: 3001 },
                database: { enabled: true, type: 'postgres' },
            };
            const envId = await previewService.provisionEnvironment(123, 'feature/new-ui', 'abc123def456', 'kushin77/code-server', 'user-alice', 'ws-test', config);
            expect(envId).toMatch(/^preview-/);
            const env = await previewService.getEnvironment(envId);
            expect(env?.status).toBe('ready');
            expect(env?.branch.pullRequestId).toBe(123);
        });
        it('should set correct URLs', async () => {
            const config = {
                frontend: { enabled: true },
                backend: { enabled: true },
                database: { enabled: true, type: 'postgres' },
            };
            const envId = await previewService.provisionEnvironment(456, 'feature/api', 'xyz789', 'kushin77/code-server', 'user-bob', 'ws-test', config);
            const env = await previewService.getEnvironment(envId);
            expect(env?.urls.frontend).toContain('pr-456-frontend');
            expect(env?.urls.backend).toContain('pr-456-backend');
            expect(env?.urls.database).toContain('preview_pr_456');
        });
        it('should emit environment-created event', async () => {
            const config = {
                frontend: { enabled: true },
                backend: { enabled: true },
                database: { enabled: true, type: 'postgres' },
            };
            return new Promise((resolve) => {
                previewService.once('environment-created', ({ pullRequestId }) => {
                    expect(pullRequestId).toBe(789);
                    resolve();
                });
                previewService.provisionEnvironment(789, 'feature/test', 'test123', 'kushin77/code-server', 'user-charlie', 'ws-test', config);
            });
        });
        it('should track build duration', async () => {
            const config = {
                frontend: { enabled: true },
                backend: { enabled: true },
                database: { enabled: true, type: 'postgres' },
            };
            const envId = await previewService.provisionEnvironment(999, 'feature/timing', 'timing123', 'kushin77/code-server', 'user-alice', 'ws-test', config);
            const env = await previewService.getEnvironment(envId);
            expect(env?.buildDuration).toBeDefined();
            expect(env?.buildDuration).toBeGreaterThanOrEqual(0);
        });
    });
    describe('Getting Environments', () => {
        beforeEach(async () => {
            const config = {
                frontend: { enabled: true },
                backend: { enabled: true },
                database: { enabled: true, type: 'postgres' },
            };
            await previewService.provisionEnvironment(101, 'feature/one', 'abc1', 'kushin77/code-server', 'user-alice', 'ws-test', config);
            await previewService.provisionEnvironment(102, 'feature/two', 'abc2', 'kushin77/code-server', 'user-bob', 'ws-test', config);
        });
        it('should get environment by ID', async () => {
            const envs = await previewService.listEnvironments('ws-test');
            const env = await previewService.getEnvironment(envs[0].id);
            expect(env?.id).toBe(envs[0].id);
        });
        it('should get environment by PR ID', async () => {
            const env = await previewService.getEnvironmentByPullRequest('ws-test', 101);
            expect(env?.branch.pullRequestId).toBe(101);
        });
        it('should list environments for workspace', async () => {
            const envs = await previewService.listEnvironments('ws-test');
            expect(envs.length).toBeGreaterThanOrEqual(2);
        });
        it('should list user environments', async () => {
            const envs = await previewService.listUserEnvironments('ws-test', 'user-alice');
            expect(envs.length).toBeGreaterThanOrEqual(1);
            expect(envs.every((e) => e.createdBy === 'user-alice')).toBe(true);
        });
        it('should sort by creation date descending', async () => {
            const envs = await previewService.listEnvironments('ws-test');
            for (let i = 0; i < envs.length - 1; i++) {
                expect(envs[i].createdAt).toBeGreaterThanOrEqual(envs[i + 1].createdAt);
            }
        });
    });
    describe('Destruction', () => {
        let envId;
        beforeEach(async () => {
            const config = {
                frontend: { enabled: true },
                backend: { enabled: true },
                database: { enabled: true, type: 'postgres' },
            };
            envId = await previewService.provisionEnvironment(201, 'feature/destroy', 'destroy123', 'kushin77/code-server', 'user-alice', 'ws-test', config);
        });
        it('should mark for destruction', async () => {
            await previewService.markForDestruction(envId, 'pr-merged');
            const env = await previewService.getEnvironment(envId);
            expect(env?.markedForDestructionAt).toBeDefined();
            expect(env?.status).toBe('destroying');
        });
        it('should emit marked-for-destruction event', async () => {
            return new Promise((resolve) => {
                previewService.once('environment-marked-for-destruction', ({ reason }) => {
                    expect(reason).toBe('pr-closed');
                    resolve();
                });
                previewService.markForDestruction(envId, 'pr-closed');
            });
        });
        it('should cancel destruction if in grace period', async () => {
            await previewService.markForDestruction(envId, 'pr-merged');
            const cancelled = await previewService.cancelDestruction(envId);
            expect(cancelled).toBe(true);
            const env = await previewService.getEnvironment(envId);
            expect(env?.status).toBe('ready');
            expect(env?.markedForDestructionAt).toBeUndefined();
        });
        it('should destroy environment', async () => {
            await previewService.destroyEnvironment(envId);
            const env = await previewService.getEnvironment(envId);
            expect(env?.status).toBe('destroyed');
            expect(env?.destroyedAt).toBeDefined();
        });
        it('should emit destroyed event', async () => {
            return new Promise((resolve) => {
                previewService.once('environment-destroyed', ({ environmentId }) => {
                    expect(environmentId).toBe(envId);
                    resolve();
                });
                previewService.destroyEnvironment(envId);
            });
        });
    });
    describe('Health Checks', () => {
        let envId;
        beforeEach(async () => {
            const config = {
                frontend: { enabled: true },
                backend: { enabled: true },
                database: { enabled: true, type: 'postgres' },
            };
            envId = await previewService.provisionEnvironment(301, 'feature/health', 'health123', 'kushin77/code-server', 'user-alice', 'ws-test', config);
        });
        it('should run health check', async () => {
            const results = await previewService.runHealthCheck(envId);
            expect(results.length).toBeGreaterThan(0);
            expect(results[0].responseTime).toBeGreaterThan(0);
            expect(results[0].lastCheck).toBeDefined();
        });
        it('should have healthy resources after provisioning', async () => {
            const results = await previewService.runHealthCheck(envId);
            expect(results.some((r) => r.healthy)).toBe(true);
        });
    });
    describe('Events', () => {
        let envId;
        beforeEach(async () => {
            const config = {
                frontend: { enabled: true },
                backend: { enabled: true },
                database: { enabled: true, type: 'postgres' },
            };
            envId = await previewService.provisionEnvironment(401, 'feature/events', 'events123', 'kushin77/code-server', 'user-alice', 'ws-test', config);
        });
        it('should track provisioning events', async () => {
            const events = await previewService.getEnvironmentEvents(envId);
            expect(events.length).toBeGreaterThan(0);
            expect(events.some((e) => e.type === 'created')).toBe(true);
            expect(events.some((e) => e.type === 'ready')).toBe(true);
        });
        it('should track status change events', async () => {
            await previewService.updateStatus(envId, 'degraded');
            const events = await previewService.getEnvironmentEvents(envId);
            expect(events.some((e) => e.message.includes('degraded'))).toBe(true);
        });
        it('should respect event limit', async () => {
            const events = await previewService.getEnvironmentEvents(envId, 1);
            expect(events.length).toBeLessThanOrEqual(1);
        });
    });
    describe('Status Updates', () => {
        let envId;
        beforeEach(async () => {
            const config = {
                frontend: { enabled: true },
                backend: { enabled: true },
                database: { enabled: true, type: 'postgres' },
            };
            envId = await previewService.provisionEnvironment(501, 'feature/status', 'status123', 'kushin77/code-server', 'user-alice', 'ws-test', config);
        });
        it('should update environment status', async () => {
            await previewService.updateStatus(envId, 'degraded');
            const env = await previewService.getEnvironment(envId);
            expect(env?.status).toBe('degraded');
        });
        it('should emit environment-degraded event', async () => {
            return new Promise((resolve) => {
                previewService.once('environment-degraded', ({ environmentId }) => {
                    expect(environmentId).toBe(envId);
                    resolve();
                });
                previewService.updateStatus(envId, 'degraded');
            });
        });
        it('should emit environment-failing event', async () => {
            return new Promise((resolve) => {
                previewService.once('environment-failing', ({ environmentId }) => {
                    expect(environmentId).toBe(envId);
                    resolve();
                });
                previewService.updateStatus(envId, 'failing');
            });
        });
    });
    describe('Statistics', () => {
        beforeEach(async () => {
            const config = {
                frontend: { enabled: true },
                backend: { enabled: true },
                database: { enabled: true, type: 'postgres' },
            };
            for (let i = 0; i < 3; i++) {
                await previewService.provisionEnvironment(600 + i, `feature/stat-${i}`, `stat${i}`, 'kushin77/code-server', i === 0 ? 'user-alice' : 'user-bob', 'ws-stats', config);
            }
        });
        it('should calculate statistics', async () => {
            const stats = await previewService.getStatistics('ws-stats');
            expect(stats.totalEnvironments).toBeGreaterThanOrEqual(3);
            expect(stats.activeEnvironments).toBeGreaterThanOrEqual(3);
            expect(stats.averageProvisionTime).toBeGreaterThanOrEqual(0);
        });
        it('should track by user', async () => {
            const stats = await previewService.getStatistics('ws-stats');
            expect(stats.byUser['user-alice']).toBeGreaterThanOrEqual(1);
            expect(stats.byUser['user-bob']).toBeGreaterThanOrEqual(2);
        });
        it('should track by branch', async () => {
            const stats = await previewService.getStatistics('ws-stats');
            expect(Object.keys(stats.byBranch).length).toBeGreaterThanOrEqual(3);
        });
        it('should calculate resource usage', async () => {
            const stats = await previewService.getStatistics('ws-stats');
            expect(stats.averageResourceUsage.frontend).toBeDefined();
            expect(stats.averageResourceUsage.backend).toBeDefined();
        });
    });
    describe('Global Singleton', () => {
        it('should return same instance', async () => {
            const service1 = await getPreviewEnvironmentService();
            const service2 = await getPreviewEnvironmentService();
            expect(service1).toBe(service2);
        });
    });
    describe('Integration', () => {
        it('should handle complete PR workflow', async () => {
            const config = {
                frontend: { enabled: true, port: 3000 },
                backend: { enabled: true, port: 3001 },
                database: { enabled: true, type: 'postgres' },
            };
            // 1. Create PR and provision preview
            const envId = await previewService.provisionEnvironment(1000, 'feature/complete-workflow', 'workflow123', 'kushin77/code-server', 'user-alice', 'ws-integration', config);
            // 2. Verify provisioning
            let env = await previewService.getEnvironment(envId);
            expect(env?.status).toBe('ready');
            expect(env?.urls.frontend).toBeDefined();
            // 3. Run health check
            const healthResults = await previewService.runHealthCheck(envId);
            expect(healthResults.length).toBeGreaterThan(0);
            // 4. Get events
            const events = await previewService.getEnvironmentEvents(envId);
            expect(events.some((e) => e.type === 'ready')).toBe(true);
            // 5. PR is merged - mark for destruction
            await previewService.markForDestruction(envId, 'pr-merged');
            env = await previewService.getEnvironment(envId);
            expect(env?.status).toBe('destroying');
            expect(env?.markedForDestructionAt).toBeDefined();
            // 6. Destroy environment
            await previewService.destroyEnvironment(envId);
            env = await previewService.getEnvironment(envId);
            expect(env?.status).toBe('destroyed');
            // 7. Get statistics
            const stats = await previewService.getStatistics('ws-integration');
            expect(stats.totalEnvironments).toBeGreaterThanOrEqual(1);
        });
        it('should handle multiple concurrent environments', async () => {
            const config = {
                frontend: { enabled: true },
                backend: { enabled: true },
                database: { enabled: true, type: 'postgres' },
            };
            // Create 3 environments concurrently
            const envIds = await Promise.all([
                previewService.provisionEnvironment(1001, 'feature/concurrent-1', 'conc1', 'kushin77/code-server', 'user-alice', 'ws-concurrent', config),
                previewService.provisionEnvironment(1002, 'feature/concurrent-2', 'conc2', 'kushin77/code-server', 'user-alice', 'ws-concurrent', config),
                previewService.provisionEnvironment(1003, 'feature/concurrent-3', 'conc3', 'kushin77/code-server', 'user-bob', 'ws-concurrent', config),
            ]);
            expect(envIds.length).toBe(3);
            // Verify all are provisioned
            const envs = await previewService.listEnvironments('ws-concurrent');
            expect(envs.length).toBeGreaterThanOrEqual(3);
        });
    });
});
//# sourceMappingURL=preview-service.test.js.map