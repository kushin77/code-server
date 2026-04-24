#!/usr/bin/env node
// @file        apps/backend/src/services/crdt/__tests__/delta-sync-service.test.ts
// @module      services/crdt
// @description Comprehensive tests for selective delta sync service
//
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import DeltaSyncService from '../delta-sync-service';
describe('DeltaSyncService', () => {
    let service;
    beforeEach(() => {
        service = DeltaSyncService.getInstance();
    });
    afterEach(() => {
        DeltaSyncService.clearInstances();
    });
    describe('Initialization', () => {
        it('should create service instance', () => {
            expect(service).toBeDefined();
            expect(service).toBeInstanceOf(DeltaSyncService);
        });
        it('should get singleton instance', () => {
            const instance1 = DeltaSyncService.getInstance();
            const instance2 = DeltaSyncService.getInstance();
            expect(instance1).toBe(instance2);
        });
        it('should initialize document with operations', () => {
            const ops = [
                {
                    clientId: 'client-1',
                    clock: 1,
                    type: 'insert',
                    position: 0,
                    length: 1,
                    content: 'a',
                },
            ];
            service.initializeDocument('doc-1', ops, 'a');
            const vector = service.getStateVector('doc-1');
            expect(vector['client-1']).toBe(1);
        });
        it('should throw on double initialization', () => {
            service.initializeDocument('doc-1', [], '');
            expect(() => {
                service.initializeDocument('doc-1', [], '');
            }).toThrow('already initialized');
        });
    });
    describe('State Vectors', () => {
        beforeEach(() => {
            const ops = [
                {
                    clientId: 'client-1',
                    clock: 1,
                    type: 'insert',
                    position: 0,
                    length: 1,
                },
                {
                    clientId: 'client-2',
                    clock: 1,
                    type: 'insert',
                    position: 1,
                    length: 1,
                },
            ];
            service.initializeDocument('doc-1', ops, 'ab');
        });
        it('should track state vector per client', () => {
            const vector = service.getStateVector('doc-1');
            expect(vector['client-1']).toBe(1);
            expect(vector['client-2']).toBe(1);
        });
        it('should update state vector when operation added', () => {
            const op = {
                clientId: 'client-1',
                clock: 2,
                type: 'insert',
                position: 1,
                length: 1,
            };
            service.addOperation('doc-1', op, 'abc');
            const vector = service.getStateVector('doc-1');
            expect(vector['client-1']).toBe(2);
        });
        it('should count distinct clients', () => {
            expect(service.getClientCount('doc-1')).toBe(2);
            const op = {
                clientId: 'client-3',
                clock: 1,
                type: 'insert',
                position: 2,
                length: 1,
            };
            service.addOperation('doc-1', op, 'abc');
            expect(service.getClientCount('doc-1')).toBe(3);
        });
    });
    describe('Delta Computation (O(changes) not O(doc))', () => {
        beforeEach(() => {
            const ops = Array.from({ length: 10 }, (_, i) => ({
                clientId: 'client-1',
                clock: i + 1,
                type: 'insert',
                position: i,
                length: 1,
                content: String.fromCharCode(97 + i),
            }));
            service.initializeDocument('doc-1', ops, 'abcdefghij');
        });
        it('should compute delta as operations not in remote vector', () => {
            const remoteVector = { 'client-1': 5 };
            const delta = service.computeDelta('doc-1', remoteVector);
            // Should only include ops 6-10 (client-1 clock > 5)
            expect(delta.operations.length).toBe(5);
            expect(delta.operations[0].clock).toBe(6);
            expect(delta.operations[4].clock).toBe(10);
        });
        it('should return empty delta when fully synchronized', () => {
            const remoteVector = { 'client-1': 10 };
            const delta = service.computeDelta('doc-1', remoteVector);
            expect(delta.operations.length).toBe(0);
        });
        it('should return all operations when remote is empty', () => {
            const remoteVector = {};
            const delta = service.computeDelta('doc-1', remoteVector);
            expect(delta.operations.length).toBe(10);
            expect(delta.operations[0].clock).toBe(1);
            expect(delta.operations[9].clock).toBe(10);
        });
        it('should preserve content checksum in delta', () => {
            const remoteVector = { 'client-1': 5 };
            const delta = service.computeDelta('doc-1', remoteVector);
            expect(delta.contentChecksum).toBeDefined();
            expect(delta.contentChecksum.length).toBeGreaterThan(0);
        });
        it('should track state vector in delta', () => {
            const remoteVector = { 'client-1': 5 };
            const delta = service.computeDelta('doc-1', remoteVector);
            expect(delta.from).toEqual(remoteVector);
            expect(delta.to['client-1']).toBe(10);
        });
    });
    describe('Delta Caching', () => {
        beforeEach(() => {
            const ops = [
                {
                    clientId: 'client-1',
                    clock: 1,
                    type: 'insert',
                    position: 0,
                    length: 1,
                },
            ];
            service.initializeDocument('doc-1', ops, 'a');
        });
        it('should cache computed deltas', () => {
            const remoteVector = { 'client-1': 0 };
            const delta1 = service.computeDelta('doc-1', remoteVector);
            const delta2 = service.computeDelta('doc-1', remoteVector);
            // Should return same object reference due to caching
            expect(delta1).toBe(delta2);
        });
        it('should invalidate cache when operation added', () => {
            const remoteVector = { 'client-1': 0 };
            // First delta - remote has no ops, should see 1 op
            const delta1 = service.computeDelta('doc-1', remoteVector);
            expect(delta1.operations.length).toBe(1);
            // Remote updates to clock 1
            remoteVector['client-1'] = 1;
            // Add new operation
            service.addOperation('doc-1', {
                clientId: 'client-1',
                clock: 2,
                type: 'insert',
                position: 1,
                length: 1,
            }, 'ab');
            // Second delta - with updated remote vector
            const delta2 = service.computeDelta('doc-1', remoteVector);
            // Should only see the new operation (clock 2)
            expect(delta2.operations.length).toBe(1);
            expect(delta2.operations[0].clock).toBe(2);
        });
    });
    describe('Sync Operations', () => {
        beforeEach(() => {
            const ops = [
                {
                    clientId: 'client-1',
                    clock: 1,
                    type: 'insert',
                    position: 0,
                    length: 1,
                    content: 'a',
                },
                {
                    clientId: 'client-1',
                    clock: 2,
                    type: 'insert',
                    position: 1,
                    length: 1,
                    content: 'b',
                },
            ];
            service.initializeDocument('doc-1', ops, 'ab');
        });
        it('should handle sync request', () => {
            const request = {
                docId: 'doc-1',
                clientId: 'client-2',
                remoteVector: { 'client-1': 1 },
            };
            const response = service.sync(request, 'ab');
            expect(response.clientId).toBe('client-2');
            expect(response.delta.operations.length).toBe(1); // Only op with clock 2
            expect(response.size).toBeGreaterThan(0);
            expect(response.timestamp).toBeDefined();
        });
        it('should track statistics', () => {
            const request = {
                docId: 'doc-1',
                clientId: 'client-2',
                remoteVector: {},
            };
            service.sync(request, 'ab');
            const stats = service.getStats();
            expect(stats.totalSyncs).toBe(1);
            expect(stats.totalOperations).toBe(2);
        });
        it('should emit sync-completed event', () => {
            return new Promise((resolve) => {
                service.on('sync-completed', (data) => {
                    expect(data.clientId).toBe('client-2');
                    expect(data.opsInDelta).toBeGreaterThanOrEqual(0);
                    resolve();
                });
                const request = {
                    docId: 'doc-1',
                    clientId: 'client-2',
                    remoteVector: {},
                };
                service.sync(request, 'ab');
            });
        });
        it('should calculate compression ratio', () => {
            const request = {
                docId: 'doc-1',
                clientId: 'client-2',
                remoteVector: { 'client-1': 2 },
            };
            service.sync(request, 'ab');
            const stats = service.getStats();
            // Compression ratio is defined and is a valid percentage
            expect(stats.compressionRatio).toBeDefined();
            expect(stats.compressionPercent).toMatch(/\d+\.\d+%/);
        });
    });
    describe('Delta Merging', () => {
        beforeEach(() => {
            service.initializeDocument('doc-1', [], '');
            service.addOperation('doc-1', {
                clientId: 'client-1',
                clock: 1,
                type: 'insert',
                position: 0,
                length: 1,
                content: 'a',
            }, 'a');
        });
        it('should merge incoming delta', () => {
            // Get the current checksum for 'a'
            let delta1 = service.computeDelta('doc-1', {});
            const deltaOp = {
                clientId: 'client-2',
                clock: 1,
                type: 'insert',
                position: 1,
                length: 1,
                content: 'b',
            };
            // Use the same checksum from computeDelta (for 'ab' content)
            const delta = {
                from: { 'client-1': 1 },
                to: { 'client-1': 1, 'client-2': 1 },
                operations: [deltaOp],
                contentChecksum: delta1.contentChecksum, // Use actual checksum
            };
            service.mergeDelta('doc-1', delta, 'ab');
            const vector = service.getStateVector('doc-1');
            expect(vector['client-2']).toBe(1);
        });
        it('should skip duplicate operations during merge', () => {
            const ops1 = service.getOperations('doc-1');
            const initialCount = ops1.length;
            const delta = {
                from: {},
                to: { 'client-1': 1 },
                operations: [
                    {
                        clientId: 'client-1',
                        clock: 1,
                        type: 'insert',
                        position: 0,
                        length: 1,
                        content: 'a',
                    },
                ],
                contentChecksum: service['computeChecksum']('a'),
            };
            service.mergeDelta('doc-1', delta, 'a');
            const ops2 = service.getOperations('doc-1');
            // Should not duplicate the operation
            expect(ops2.length).toBe(initialCount);
        });
        it('should emit delta-merged event', () => {
            return new Promise((resolve) => {
                service.on('delta-merged', (data) => {
                    expect(data.docId).toBe('doc-1');
                    expect(data.opsApplied).toBeGreaterThanOrEqual(0);
                    resolve();
                });
                // Get current checksum
                let delta1 = service.computeDelta('doc-1', {});
                const deltaOp = {
                    clientId: 'client-2',
                    clock: 1,
                    type: 'insert',
                    position: 1,
                    length: 1,
                };
                const delta = {
                    from: { 'client-1': 1 },
                    to: { 'client-1': 1, 'client-2': 1 },
                    operations: [deltaOp],
                    contentChecksum: delta1.contentChecksum,
                };
                service.mergeDelta('doc-1', delta, 'ab');
            });
        });
        it('should throw on checksum mismatch', () => {
            const delta = {
                from: {},
                to: {},
                operations: [],
                contentChecksum: 'wrong-checksum',
            };
            expect(() => {
                service.mergeDelta('doc-1', delta, 'a');
            }).toThrow('checksum mismatch');
        });
    });
    describe('Multi-Client Synchronization', () => {
        it('should sync between two clients with different views', () => {
            // Client 1 creates document with 3 operations
            const client1Ops = [
                { clientId: 'client-1', clock: 1, type: 'insert', position: 0, length: 1 },
                { clientId: 'client-1', clock: 2, type: 'insert', position: 1, length: 1 },
                { clientId: 'client-1', clock: 3, type: 'insert', position: 2, length: 1 },
            ];
            service.initializeDocument('doc-1', client1Ops, 'abc');
            // Client 2 is at clock 2 (has first 2 ops)
            const client2Vector = { 'client-1': 2 };
            // Compute delta
            const delta = service.computeDelta('doc-1', client2Vector);
            // Should only have the 3rd operation
            expect(delta.operations.length).toBe(1);
            expect(delta.operations[0].clock).toBe(3);
        });
        it('should handle concurrent edits from multiple clients', () => {
            const ops = [
                { clientId: 'client-1', clock: 1, type: 'insert', position: 0, length: 1 },
                { clientId: 'client-2', clock: 1, type: 'insert', position: 1, length: 1 },
                { clientId: 'client-3', clock: 1, type: 'insert', position: 2, length: 1 },
            ];
            service.initializeDocument('doc-1', ops, 'abc');
            // Client 4 wants full sync
            const delta = service.computeDelta('doc-1', {});
            expect(delta.operations.length).toBe(3);
            expect(service.getClientCount('doc-1')).toBe(3);
        });
        it('should maintain consistency across multiple syncs', () => {
            const ops = [
                { clientId: 'client-1', clock: 1, type: 'insert', position: 0, length: 1 },
            ];
            service.initializeDocument('doc-1', ops, 'a');
            // First sync
            let delta1 = service.computeDelta('doc-1', {});
            expect(delta1.operations.length).toBe(1);
            // Add more operations
            service.addOperation('doc-1', { clientId: 'client-1', clock: 2, type: 'insert', position: 1, length: 1 }, 'ab');
            // Second sync
            let delta2 = service.computeDelta('doc-1', { 'client-1': 1 });
            expect(delta2.operations.length).toBe(1);
            expect(delta2.operations[0].clock).toBe(2);
        });
    });
    describe('Statistics & Monitoring', () => {
        beforeEach(() => {
            const ops = Array.from({ length: 100 }, (_, i) => ({
                clientId: 'client-1',
                clock: i + 1,
                type: 'insert',
                position: i,
                length: 1,
            }));
            service.initializeDocument('doc-1', ops, 'a'.repeat(100));
        });
        it('should track sync statistics', () => {
            service.sync({ docId: 'doc-1', clientId: 'client-2', remoteVector: {} }, 'a'.repeat(100));
            service.sync({ docId: 'doc-1', clientId: 'client-3', remoteVector: {} }, 'a'.repeat(100));
            const stats = service.getStats();
            expect(stats.totalSyncs).toBe(2);
            expect(stats.totalOperations).toBe(200);
            expect(stats.avgDeltaSize).toBe(100);
        });
        it('should calculate compression ratio', () => {
            service.sync({ docId: 'doc-1', clientId: 'client-2', remoteVector: {} }, 'a'.repeat(100));
            const stats = service.getStats();
            // Compression ratio is defined and formatted as percentage
            expect(stats.compressionRatio).toBeDefined();
            expect(stats.compressionPercent).toMatch(/\d+\.\d+%/);
        });
        it('should format stats for monitoring', () => {
            service.sync({ docId: 'doc-1', clientId: 'client-2', remoteVector: {} }, 'a'.repeat(100));
            const stats = service.getStats();
            expect(stats.totalSyncs).toBeGreaterThan(0);
            expect(stats.totalOperations).toBeGreaterThan(0);
            expect(stats.avgDeltaSize).toBeGreaterThan(0);
            expect(stats.compressionPercent).toMatch(/\d+\.\d+%/);
        });
    });
    describe('Edge Cases', () => {
        it('should handle empty document', () => {
            service.initializeDocument('doc-1', [], '');
            const delta = service.computeDelta('doc-1', {});
            expect(delta.operations.length).toBe(0);
        });
        it('should handle operations with no content', () => {
            const ops = [
                { clientId: 'client-1', clock: 1, type: 'delete', position: 0, length: 1 },
            ];
            service.initializeDocument('doc-1', ops, '');
            const delta = service.computeDelta('doc-1', {});
            expect(delta.operations.length).toBe(1);
        });
        it('should handle very large operation counts', () => {
            const ops = Array.from({ length: 10000 }, (_, i) => ({
                clientId: 'client-1',
                clock: i + 1,
                type: 'insert',
                position: i,
                length: 1,
            }));
            service.initializeDocument('doc-1', ops, 'a'.repeat(10000));
            const delta = service.computeDelta('doc-1', { 'client-1': 5000 });
            expect(delta.operations.length).toBe(5000);
        });
        it('should handle operations from many clients', () => {
            const ops = Array.from({ length: 100 }, (_, i) => ({
                clientId: `client-${i}`,
                clock: 1,
                type: 'insert',
                position: i,
                length: 1,
            }));
            service.initializeDocument('doc-1', ops, 'a'.repeat(100));
            expect(service.getClientCount('doc-1')).toBe(100);
            const delta = service.computeDelta('doc-1', {});
            expect(delta.operations.length).toBe(100);
        });
        it('should handle clock gaps between clients', () => {
            const ops = [
                { clientId: 'client-1', clock: 1, type: 'insert', position: 0, length: 1 },
                { clientId: 'client-1', clock: 5, type: 'insert', position: 1, length: 1 },
            ];
            service.initializeDocument('doc-1', ops, 'ab');
            const delta = service.computeDelta('doc-1', { 'client-1': 3 });
            expect(delta.operations.length).toBe(1);
            expect(delta.operations[0].clock).toBe(5);
        });
    });
    describe('Service Lifecycle', () => {
        it('should reset state', () => {
            service.initializeDocument('doc-1', [], '');
            service.reset();
            expect(() => {
                service.getStateVector('doc-1');
            }).toThrow();
        });
        it('should shutdown cleanly', () => {
            service.initializeDocument('doc-1', [], '');
            service.shutdown();
            expect(() => {
                service.getStateVector('doc-1');
            }).toThrow();
        });
        it('should clear instances', () => {
            const instance1 = DeltaSyncService.getInstance();
            DeltaSyncService.clearInstances();
            const instance2 = DeltaSyncService.getInstance();
            expect(instance1 === instance2).toBe(false);
        });
    });
});
//# sourceMappingURL=delta-sync-service.test.js.map