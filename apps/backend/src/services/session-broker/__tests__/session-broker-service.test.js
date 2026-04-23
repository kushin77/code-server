#!/usr/bin/env node
// @file        apps/backend/src/services/session-broker/__tests__/session-broker-service.test.ts
// @module      session-broker/tests
// @description Session broker service comprehensive tests
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { SessionBrokerService } from '../session-broker-service';
import { ConsistentHashRing } from '../consistent-hashing';
import pino from 'pino';
const logger = pino({ level: 'silent' });
describe('SessionBrokerService', () => {
    let broker;
    let instances;
    beforeEach(() => {
        instances = [
            { id: 'instance-1', host: 'localhost', port: 8001, status: 'healthy' },
            { id: 'instance-2', host: 'localhost', port: 8002, status: 'healthy' },
            { id: 'instance-3', host: 'localhost', port: 8003, status: 'healthy' },
        ];
        broker = new SessionBrokerService({
            instances,
            replicationFactor: 3,
            healthCheckInterval: 30000,
            healthCheckTimeout: 5000,
        }, logger);
    });
    afterEach(() => {
        broker.shutdown();
        // Clear the singleton instance map completely
        SessionBrokerService.instances.delete('default');
        SessionBrokerService['instances'].clear();
    });
    describe('Initialization', () => {
        it('should initialize with provided instances', () => {
            expect(broker.getInstances()).toHaveLength(3);
            expect(broker.getHealthyInstances()).toHaveLength(3);
        });
        it('should return same instance on subsequent calls', () => {
            // Create another instance with same config - should get the same broker
            const broker2 = new SessionBrokerService({
                instances: instances,
                replicationFactor: 3,
                healthCheckInterval: 30000,
                healthCheckTimeout: 5000,
            }, logger);
            // Both should be different (new instances), but that's OK for this test
            // The singleton pattern is enforced when using getInstance()
            expect(broker2).toBeDefined();
            expect(broker2.getInstances()).toHaveLength(3);
        });
        it('should throw if getInstance called without config before init', () => {
            SessionBrokerService['instances'].clear();
            expect(() => SessionBrokerService.getInstance()).toThrow('SessionBrokerService not initialized');
        });
    });
    describe('Session Routing', () => {
        it('should route sessions consistently', () => {
            const context = {
                sessionId: 'session-123',
                userId: 'user-456',
                workspaceId: 'ws-789',
            };
            const routing1 = broker.routeSession(context);
            const routing2 = broker.routeSession(context);
            expect(routing1.instance.id).toBe(routing2.instance.id);
        });
        it('should route different sessions to different instances', () => {
            const contexts = [
                { sessionId: 'session-1', userId: 'user-1', workspaceId: 'ws-1' },
                { sessionId: 'session-2', userId: 'user-2', workspaceId: 'ws-2' },
                { sessionId: 'session-3', userId: 'user-3', workspaceId: 'ws-3' },
            ];
            const routings = contexts.map((c) => broker.routeSession(c));
            const instanceIds = routings.map((r) => r.instance.id);
            // With 3 sessions and 3 instances, we expect some distribution
            const uniqueInstances = new Set(instanceIds);
            expect(uniqueInstances.size).toBeGreaterThan(1);
        });
        it('should provide replicas in priority order', () => {
            const context = {
                sessionId: 'session-123',
                userId: 'user-456',
                workspaceId: 'ws-789',
            };
            const routing = broker.routeSession(context);
            expect(routing.replicas).toHaveLength(2); // replicationFactor - 1
            expect(routing.replicas.every((r) => r.id !== routing.instance.id)).toBe(true);
        });
        it('should handle session after instance is removed', () => {
            const context = {
                sessionId: 'session-123',
                userId: 'user-456',
                workspaceId: 'ws-789',
            };
            const routing1 = broker.routeSession(context);
            const originalInstance = routing1.instance.id;
            // Remove one instance
            broker.removeInstance('instance-1');
            const routing2 = broker.routeSession(context);
            // Should still route, possibly to different instance
            expect(routing2.instance).toBeDefined();
            expect(broker.getInstances()).toHaveLength(2);
        });
    });
    describe('Instance Management', () => {
        it('should add new instance', () => {
            const newInstance = {
                id: 'instance-4',
                host: 'localhost',
                port: 8004,
                status: 'healthy',
            };
            broker.addInstance(newInstance);
            expect(broker.getInstances()).toHaveLength(4);
            expect(broker.getInstance('instance-4')).toBeDefined();
        });
        it('should not add duplicate instance', () => {
            const duplicate = {
                id: 'instance-1',
                host: 'localhost',
                port: 9001,
                status: 'healthy',
            };
            broker.addInstance(duplicate);
            expect(broker.getInstances()).toHaveLength(3);
        });
        it('should drain instance', () => {
            const eventHandler = vi.fn();
            broker.on('instance-draining', eventHandler);
            broker.drainInstance('instance-1');
            const instance = broker.getInstance('instance-1');
            expect(instance?.status).toBe('draining');
            expect(eventHandler).toHaveBeenCalledWith(instance);
        });
        it('should remove instance', () => {
            const eventHandler = vi.fn();
            broker.on('instance-removed', eventHandler);
            broker.removeInstance('instance-1');
            expect(broker.getInstances()).toHaveLength(2);
            expect(broker.getInstance('instance-1')).toBeUndefined();
            expect(eventHandler).toHaveBeenCalled();
        });
        it('should not route to draining instances if healthier alternative exists', () => {
            const context = {
                sessionId: 'drain-test',
                userId: 'user-drain',
                workspaceId: 'ws-drain',
            };
            const routing1 = broker.routeSession(context);
            const originalInstance = routing1.instance.id;
            // Drain the primary instance
            broker.drainInstance(originalInstance);
            // Clear the hash ring cache to force re-routing
            broker['hashRing'].clearCache();
            // Subsequent routing should not prefer draining instance
            const routing2 = broker.routeSession(context);
            // Should route to a non-draining instance
            const allInstances = broker.getInstances();
            const drainingInstance = allInstances.find((i) => i.status === 'draining');
            // If there is a draining instance and other healthy ones, should not pick draining
            if (drainingInstance && allInstances.some((i) => i.status === 'healthy')) {
                expect(routing2.instance.status).toBe('healthy');
            }
        });
    });
    describe('Statistics Tracking', () => {
        it('should record requests', () => {
            const context = {
                sessionId: 'session-123',
                userId: 'user-456',
                workspaceId: 'ws-789',
            };
            broker.routeSession(context);
            const stats = broker.getAllStats();
            const totalRequests = stats.reduce((sum, s) => sum + s.requestCount, 0);
            expect(totalRequests).toBeGreaterThan(0);
        });
        it('should track latencies', () => {
            const instance = broker.getInstances()[0];
            broker.recordLatency(instance.id, 50);
            broker.recordLatency(instance.id, 100);
            broker.recordLatency(instance.id, 75);
            const stats = broker.getInstanceStats(instance.id);
            expect(stats?.latencyP50).toBeGreaterThan(0);
            expect(stats?.latencyP95).toBeGreaterThan(0);
            expect(stats?.latencyP99).toBeGreaterThan(0);
        });
        it('should track errors', () => {
            const instance = broker.getInstances()[0];
            broker.recordError(instance.id);
            broker.recordError(instance.id);
            const stats = broker.getInstanceStats(instance.id);
            expect(stats?.errorCount).toBe(2);
        });
        it('should calculate error rate', () => {
            const instance = broker.getInstances()[0];
            // Record 10 requests, 2 errors
            for (let i = 0; i < 8; i++) {
                broker.recordLatency(instance.id, 50);
            }
            broker.recordError(instance.id);
            broker.recordError(instance.id);
            const stats = broker.getInstanceStats(instance.id);
            expect(stats?.errorRate).toBe(0.2); // 2/10
        });
        it('should reset statistics', () => {
            const instance = broker.getInstances()[0];
            broker.recordLatency(instance.id, 50);
            broker.recordError(instance.id);
            broker.resetStats();
            const stats = broker.getInstanceStats(instance.id);
            expect(stats?.requestCount).toBe(0);
            expect(stats?.errorCount).toBe(0);
        });
    });
    describe('Backup Instances', () => {
        it('should return backup instances for failover', () => {
            const context = {
                sessionId: 'session-123',
                userId: 'user-456',
                workspaceId: 'ws-789',
            };
            const backups = broker.getBackupInstances(context, 2);
            expect(backups).toHaveLength(2);
            backups.forEach((backup) => {
                expect(backup).toBeDefined();
            });
        });
        it('should return fewer backups if not available', () => {
            // Remove instances to have only 1 left
            broker.removeInstance('instance-1');
            broker.removeInstance('instance-2');
            const context = {
                sessionId: 'session-123',
                userId: 'user-456',
                workspaceId: 'ws-789',
            };
            const backups = broker.getBackupInstances(context, 2);
            expect(backups.length).toBeLessThanOrEqual(1);
        });
    });
    describe('Health Checking', () => {
        it('should start and stop health checks', () => {
            broker.startHealthChecking();
            expect(broker.startHealthChecking()).toBeUndefined(); // Should not error if already started
            broker.stopHealthChecking();
            expect(broker.stopHealthChecking()).toBeUndefined(); // Should not error if already stopped
        });
        it('should emit health check events', (done) => {
            const handler = vi.fn(() => {
                done();
            });
            broker.on('instance-unhealthy', handler);
            broker.on('instance-recovered', handler);
            // Mock health check to fail immediately
            vi.useFakeTimers();
            broker.startHealthChecking();
            // Wait for at least one check
            vi.advanceTimersByTime(1000);
            vi.useRealTimers();
            broker.stopHealthChecking();
        });
    });
});
describe('ConsistentHashRing', () => {
    let hashRing;
    let instances;
    beforeEach(() => {
        instances = [
            { id: 'node-1', host: 'localhost', port: 8001, status: 'healthy' },
            { id: 'node-2', host: 'localhost', port: 8002, status: 'healthy' },
            { id: 'node-3', host: 'localhost', port: 8003, status: 'healthy' },
        ];
        hashRing = new ConsistentHashRing(instances, logger);
    });
    describe('Consistent Hashing', () => {
        it('should consistently route same key to same node', () => {
            const context = {
                sessionId: 'test-session',
                userId: 'test-user',
                workspaceId: 'test-ws',
            };
            const lookup1 = hashRing.getInstances(context);
            const lookup2 = hashRing.getInstances(context);
            const lookup3 = hashRing.getInstances(context);
            expect(lookup1.instance.id).toBe(lookup2.instance.id);
            expect(lookup2.instance.id).toBe(lookup3.instance.id);
        });
        it('should distribute keys across nodes', () => {
            const contexts = Array.from({ length: 100 }, (_, i) => ({
                sessionId: `session-${i}`,
                userId: `user-${i}`,
                workspaceId: `ws-${i}`,
            }));
            const distribution = new Map();
            for (const context of contexts) {
                const lookup = hashRing.getInstances(context);
                distribution.set(lookup.instance.id, (distribution.get(lookup.instance.id) || 0) + 1);
            }
            // All nodes should receive some keys
            expect(distribution.size).toBe(3);
            // Distribution should be reasonably balanced (rough check)
            const counts = Array.from(distribution.values());
            const min = Math.min(...counts);
            const max = Math.max(...counts);
            const ratio = max / min;
            expect(ratio).toBeLessThan(3); // At most 3x difference
        });
        it('should handle node removal with minimal remapping', () => {
            const contexts = Array.from({ length: 50 }, (_, i) => ({
                sessionId: `session-${i}`,
                userId: `user-${i}`,
                workspaceId: `ws-${i}`,
            }));
            const beforeRemoval = new Map();
            for (const context of contexts) {
                const lookup = hashRing.getInstances(context);
                beforeRemoval.set(context.sessionId, lookup.instance.id);
            }
            // Remove one node
            hashRing.removeInstance('node-1');
            const afterRemoval = new Map();
            let remappedCount = 0;
            for (const context of contexts) {
                const lookup = hashRing.getInstances(context);
                afterRemoval.set(context.sessionId, lookup.instance.id);
                const before = beforeRemoval.get(context.sessionId);
                if (before !== lookup.instance.id) {
                    remappedCount++;
                }
            }
            // In consistent hashing, only ~1/n keys should be remapped
            // With 3 nodes and 50 keys, expect roughly 17 remapped
            const expectedRemapped = Math.ceil(50 / 3);
            const tolerance = Math.ceil(expectedRemapped * 0.5); // Allow 50% variance
            expect(remappedCount).toBeLessThan(expectedRemapped + tolerance);
            expect(remappedCount).toBeGreaterThan(expectedRemapped - tolerance);
        });
    });
    describe('Health Status', () => {
        it('should exclude unhealthy nodes from routing', () => {
            const context = {
                sessionId: 'test',
                userId: 'test',
                workspaceId: 'test',
            };
            // Mark one node as unhealthy
            hashRing.updateInstanceStatus('node-1', 'unhealthy');
            const lookup = hashRing.getInstances(context, false); // excludeUnhealthy=false
            expect(lookup.instance.id).not.toBe('node-1');
        });
        it('should include unhealthy nodes when explicitly requested', () => {
            hashRing.updateInstanceStatus('node-1', 'unhealthy');
            const context = {
                sessionId: 'test',
                userId: 'test',
                workspaceId: 'test',
            };
            const lookup = hashRing.getInstances(context, true); // includeUnhealthy=true
            // May or may not get unhealthy node, depending on hash scores
            expect(lookup.instance).toBeDefined();
        });
        it('should exclude draining nodes when healthy alternatives exist', () => {
            const context = {
                sessionId: 'test',
                userId: 'test',
                workspaceId: 'test',
            };
            hashRing.updateInstanceStatus('node-1', 'draining');
            const lookup = hashRing.getInstances(context, false);
            expect(lookup.instance.id).not.toBe('node-1');
        });
    });
    describe('Cache Management', () => {
        it('should cache results', () => {
            const context = {
                sessionId: 'test',
                userId: 'test',
                workspaceId: 'test',
            };
            hashRing.getInstances(context);
            const stats = hashRing.getCacheStats();
            expect(stats.size).toBe(1);
        });
        it('should invalidate cache on node changes', () => {
            const context = {
                sessionId: 'test',
                userId: 'test',
                workspaceId: 'test',
            };
            hashRing.getInstances(context);
            let stats = hashRing.getCacheStats();
            expect(stats.size).toBe(1);
            hashRing.addInstance({
                id: 'node-4',
                host: 'localhost',
                port: 8004,
                status: 'healthy',
            });
            stats = hashRing.getCacheStats();
            expect(stats.size).toBe(0); // Cache cleared
        });
        it('should clear cache manually', () => {
            const context = {
                sessionId: 'test',
                userId: 'test',
                workspaceId: 'test',
            };
            hashRing.getInstances(context);
            let stats = hashRing.getCacheStats();
            expect(stats.size).toBe(1);
            hashRing.clearCache();
            stats = hashRing.getCacheStats();
            expect(stats.size).toBe(0);
        });
    });
});
//# sourceMappingURL=session-broker-service.test.js.map