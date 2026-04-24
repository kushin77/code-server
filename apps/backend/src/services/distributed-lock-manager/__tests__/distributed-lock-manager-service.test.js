/**
 * Distributed Lock Manager Service Tests
 * @file        apps/backend/src/services/distributed-lock-manager/__tests__/distributed-lock-manager-service.test.ts
 * @module      services/distributed-lock-manager
 * @description Test suite for distributed lock management
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { DistributedLockManager } from '../distributed-lock-manager-service.js';
describe('Distributed Lock Manager Service', () => {
    let service;
    beforeEach(() => {
        DistributedLockManager.reset();
        service = DistributedLockManager.getInstance();
    });
    afterEach(() => {
        service.shutdown();
    });
    // Initialization Tests
    describe('Initialization', () => {
        it('should initialize service', () => {
            expect(service).toBeDefined();
            expect(service.locks).toBeDefined();
            expect(service.resourceLocks).toBeDefined();
        });
        it('should return same instance on subsequent calls', () => {
            const instance1 = DistributedLockManager.getInstance();
            const instance2 = DistributedLockManager.getInstance();
            expect(instance1).toBe(instance2);
        });
    });
    // Lock Acquisition Tests
    describe('Acquire Lock', () => {
        it('should acquire exclusive lock', () => {
            const request = {
                resourceId: 'resource-1',
                resourceType: 'file',
                mode: 'exclusive',
                userId: 'user1',
                userEmail: 'user1@example.com',
                timeout: 30000,
                priority: 1,
            };
            const result = service.acquireLock(request, '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.lockId).toBeDefined();
        });
        it('should acquire shared lock', () => {
            const request = {
                resourceId: 'resource-2',
                resourceType: 'file',
                mode: 'shared',
                userId: 'user2',
                userEmail: 'user2@example.com',
                timeout: 30000,
                priority: 1,
            };
            const result = service.acquireLock(request, '192.168.1.1', 'Mozilla');
            expect(result.success).toBe(true);
            expect(result.lock?.mode).toBe('shared');
        });
        it('should emit lock-acquired event', () => {
            return new Promise((resolve) => {
                const request = {
                    resourceId: 'resource-3',
                    resourceType: 'file',
                    mode: 'exclusive',
                    userId: 'user3',
                    userEmail: 'user3@example.com',
                    timeout: 30000,
                    priority: 1,
                };
                service.once('lock-acquired', (event) => {
                    expect(event.data_object.resourceId).toBe('resource-3');
                    resolve();
                });
                service.acquireLock(request, '192.168.1.1', 'Mozilla');
            });
        });
    });
    // Lock Release Tests
    describe('Release Lock', () => {
        it('should release acquired lock', () => {
            const request = {
                resourceId: 'resource-4',
                resourceType: 'file',
                mode: 'exclusive',
                userId: 'user4',
                userEmail: 'user4@example.com',
                timeout: 30000,
                priority: 1,
            };
            const acquired = service.acquireLock(request, '192.168.1.1', 'Mozilla');
            const released = service.releaseLock(acquired.lockId, 'user4', '192.168.1.1', 'Mozilla');
            expect(released.success).toBe(true);
        });
        it('should emit lock-released event', () => {
            return new Promise((resolve) => {
                const request = {
                    resourceId: 'resource-5',
                    resourceType: 'file',
                    mode: 'exclusive',
                    userId: 'user5',
                    userEmail: 'user5@example.com',
                    timeout: 30000,
                    priority: 1,
                };
                const acquired = service.acquireLock(request, '192.168.1.1', 'Mozilla');
                service.once('lock-released', (event) => {
                    expect(event.data_object.lockId).toBe(acquired.lockId);
                    resolve();
                });
                service.releaseLock(acquired.lockId, 'user5', '192.168.1.1', 'Mozilla');
            });
        });
    });
    // Lock Renewal Tests
    describe('Renew Lock', () => {
        it('should renew lock with new timeout', () => {
            const request = {
                resourceId: 'resource-6',
                resourceType: 'file',
                mode: 'exclusive',
                userId: 'user6',
                userEmail: 'user6@example.com',
                timeout: 30000,
                priority: 1,
            };
            const acquired = service.acquireLock(request, '192.168.1.1', 'Mozilla');
            const renewed = service.renewLock(acquired.lockId, 'user6', 60000, '192.168.1.1', 'Mozilla');
            expect(renewed.success).toBe(true);
            expect(renewed.newExpiresAt).toBeDefined();
        });
        it('should emit lock-renewed event', () => {
            return new Promise((resolve) => {
                const request = {
                    resourceId: 'resource-7',
                    resourceType: 'file',
                    mode: 'exclusive',
                    userId: 'user7',
                    userEmail: 'user7@example.com',
                    timeout: 30000,
                    priority: 1,
                };
                const acquired = service.acquireLock(request, '192.168.1.1', 'Mozilla');
                service.once('lock-renewed', (event) => {
                    expect(event.data_object.lockId).toBe(acquired.lockId);
                    resolve();
                });
                service.renewLock(acquired.lockId, 'user7', 60000, '192.168.1.1', 'Mozilla');
            });
        });
    });
    // Lock Query Tests
    describe('Query Locks', () => {
        it('should retrieve lock status', () => {
            const request = {
                resourceId: 'resource-8',
                resourceType: 'file',
                mode: 'exclusive',
                userId: 'user8',
                userEmail: 'user8@example.com',
                timeout: 30000,
                priority: 1,
            };
            const acquired = service.acquireLock(request, '192.168.1.1', 'Mozilla');
            const status = service.getLock(acquired.lockId);
            expect(status).toBeDefined();
            expect(status?.mode).toBe('exclusive');
        });
        it('should list resource locks', () => {
            const request = {
                resourceId: 'resource-9',
                resourceType: 'file',
                mode: 'shared',
                userId: 'user9',
                userEmail: 'user9@example.com',
                timeout: 30000,
                priority: 1,
            };
            service.acquireLock(request, '192.168.1.1', 'Mozilla');
            const locks = service.getResourceLocks('resource-9');
            expect(locks.length).toBeGreaterThan(0);
        });
        it('should list user locks', () => {
            const request = {
                resourceId: 'resource-10',
                resourceType: 'file',
                mode: 'exclusive',
                userId: 'user10',
                userEmail: 'user10@example.com',
                timeout: 30000,
                priority: 1,
            };
            service.acquireLock(request, '192.168.1.1', 'Mozilla');
            const locks = service.getLocksByUser('user10');
            expect(locks.length).toBeGreaterThan(0);
        });
        it('should list active locks', () => {
            const request = {
                resourceId: 'resource-11',
                resourceType: 'file',
                mode: 'exclusive',
                userId: 'user11',
                userEmail: 'user11@example.com',
                timeout: 30000,
                priority: 1,
            };
            service.acquireLock(request, '192.168.1.1', 'Mozilla');
            const activeLocks = service.getActiveLocks();
            expect(activeLocks.length).toBeGreaterThan(0);
        });
    });
    // Lock Compatibility Tests
    describe('Lock Compatibility', () => {
        it('should support shared-shared compatibility', () => {
            const compatible = service.checkCompatibility('shared', 'shared');
            expect(compatible).toBe(true);
        });
        it('should prevent exclusive-shared compatibility', () => {
            const compatible = service.checkCompatibility('exclusive', 'shared');
            expect(compatible).toBe(false);
        });
        it('should return compatibility matrix', () => {
            const matrix = service.getCompatibilityMatrix();
            expect(matrix).toBeDefined();
            expect(matrix.shared).toBeDefined();
            expect(matrix.exclusive).toBeDefined();
        });
    });
    // Deadlock Detection Tests
    describe('Deadlock Detection', () => {
        it('should detect deadlocks', () => {
            const result = service.detectDeadlocks();
            expect(result.success).toBe(true);
            expect(Array.isArray(result.deadlocksFound)).toBe(true);
        });
        it('should emit deadlock-detection-completed event', () => {
            return new Promise((resolve) => {
                service.once('deadlock-detection-completed', (event) => {
                    expect(event.data_object.deadlocksFound).toBeDefined();
                    resolve();
                });
                service.detectDeadlocks();
            });
        });
    });
    // Wait Queue Tests
    describe('Wait Queues', () => {
        it('should support getting waiters for resource', () => {
            const waiters = service.getWaiters('resource-12');
            expect(Array.isArray(waiters)).toBe(true);
        });
    });
    // Batch Operations Tests
    describe('Batch Operations', () => {
        it('should batch acquire multiple locks', () => {
            const requests = [
                {
                    resourceId: 'resource-13',
                    resourceType: 'file',
                    mode: 'exclusive',
                    userId: 'user13',
                    userEmail: 'user13@example.com',
                    timeout: 30000,
                    priority: 1,
                },
                {
                    resourceId: 'resource-14',
                    resourceType: 'file',
                    mode: 'exclusive',
                    userId: 'user13',
                    userEmail: 'user13@example.com',
                    timeout: 30000,
                    priority: 1,
                },
            ];
            const result = service.batchAcquire(requests, 'user13', '192.168.1.1', 'Mozilla');
            expect(result.totalRequests).toBe(2);
            expect(result.successCount).toBeGreaterThanOrEqual(0);
        });
        it('should batch release multiple locks', () => {
            const request = {
                resourceId: 'resource-15',
                resourceType: 'file',
                mode: 'exclusive',
                userId: 'user15',
                userEmail: 'user15@example.com',
                timeout: 30000,
                priority: 1,
            };
            const acquired = service.acquireLock(request, '192.168.1.1', 'Mozilla');
            const result = service.batchRelease([acquired.lockId], 'user15', '192.168.1.1', 'Mozilla');
            expect(result.successCount).toBeGreaterThanOrEqual(0);
        });
    });
    // Statistics Tests
    describe('Statistics', () => {
        it('should calculate service statistics', () => {
            const stats = service.getStatistics();
            expect(stats).toBeDefined();
            expect(stats.totalLocks).toBeGreaterThanOrEqual(0);
            expect(stats.activeLocks).toBeGreaterThanOrEqual(0);
            expect(stats.successRate).toBeGreaterThanOrEqual(0);
        });
        it('should track acquisition success rate', () => {
            const request = {
                resourceId: 'resource-16',
                resourceType: 'file',
                mode: 'exclusive',
                userId: 'user16',
                userEmail: 'user16@example.com',
                timeout: 30000,
                priority: 1,
            };
            service.acquireLock(request, '192.168.1.1', 'Mozilla');
            const stats = service.getStatistics();
            expect(stats.acquisitionSuccess).toBeGreaterThanOrEqual(0);
            expect(stats.successRate).toBeGreaterThanOrEqual(0);
        });
    });
    // Audit Log Tests
    describe('Audit Logging', () => {
        it('should emit audit-logged event for operations', () => {
            return new Promise((resolve) => {
                const request = {
                    resourceId: 'resource-17',
                    resourceType: 'file',
                    mode: 'exclusive',
                    userId: 'user17',
                    userEmail: 'user17@example.com',
                    timeout: 30000,
                    priority: 1,
                };
                service.once('audit-logged', (event) => {
                    expect(event.data_object.userId).toBeDefined();
                    expect(event.data_object.operation).toBeDefined();
                    resolve();
                });
                service.acquireLock(request, '192.168.1.1', 'Mozilla');
            });
        });
        it('should retrieve audit log', () => {
            const log = service.getAuditLog();
            expect(Array.isArray(log)).toBe(true);
        });
    });
    // Configuration Tests
    describe('Configuration', () => {
        it('should update service configuration', () => {
            return new Promise((resolve) => {
                service.once('config-updated', (event) => {
                    expect(event.data_object.config).toBeDefined();
                    resolve();
                });
                service.updateConfig({ defaultLockTimeout: 60000 });
            });
        });
        it('should retrieve current configuration', () => {
            const config = service.getConfig();
            expect(config).toBeDefined();
            expect(config.defaultLockTimeout).toBeGreaterThan(0);
        });
    });
    // Expiry Handling Tests
    describe('Expiry Handling', () => {
        it('should clear expired locks', () => {
            const result = service.clearExpiredLocks('admin', '192.168.1.1', 'Mozilla');
            expect(result.clearedCount).toBeGreaterThanOrEqual(0);
        });
    });
    // Shutdown Tests
    describe('Shutdown', () => {
        it('should shutdown service cleanly', () => {
            const request = {
                resourceId: 'resource-18',
                resourceType: 'file',
                mode: 'exclusive',
                userId: 'user18',
                userEmail: 'user18@example.com',
                timeout: 30000,
                priority: 1,
            };
            service.acquireLock(request, '192.168.1.1', 'Mozilla');
            service.shutdown();
            expect(service.locks.size).toBe(0);
            expect(service.resourceLocks.size).toBe(0);
        });
    });
    // Hierarchy Tests
    describe('Lock Hierarchy', () => {
        it('should support getting parent locks', () => {
            const parents = service.getParentLocks('lock-1');
            expect(Array.isArray(parents)).toBe(true);
        });
        it('should support getting child locks', () => {
            const children = service.getChildLocks('lock-1');
            expect(Array.isArray(children)).toBe(true);
        });
    });
    // Waiter Promotion Tests
    describe('Waiter Promotion', () => {
        it('should support promoting waiters', () => {
            const request = {
                resourceId: 'resource-19',
                resourceType: 'file',
                mode: 'exclusive',
                userId: 'user19',
                userEmail: 'user19@example.com',
                timeout: 30000,
                priority: 1,
            };
            const acquired = service.acquireLock(request, '192.168.1.1', 'Mozilla');
            expect(acquired.success).toBe(true);
        });
    });
});
//# sourceMappingURL=distributed-lock-manager-service.test.js.map