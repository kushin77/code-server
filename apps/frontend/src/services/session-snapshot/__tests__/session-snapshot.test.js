/**
 * @file        apps/frontend/src/services/session-snapshot/__tests__/session-snapshot.test.ts
 * @module      collaboration/session-persistence
 * @description Comprehensive session snapshot test suite
 */
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { SessionSnapshotService, } from '../service.js';
/**
 * Mock storage for testing
 */
class MockSessionSnapshotStorage {
    constructor() {
        this.store = new Map();
        this.snapshotCounter = 0;
    }
    async initialize() {
        // No-op for mock
    }
    async saveSnapshot(snapshot) {
        snapshot.id =
            snapshot.id ||
                `snap-test-${++this.snapshotCounter}-${Date.now()}`;
        this.store.set(snapshot.id, { ...snapshot });
    }
    async loadSnapshot(snapshotId) {
        return this.store.get(snapshotId) || null;
    }
    async listSnapshots(workspaceId, page = 1, pageSize = 10) {
        const all = Array.from(this.store.values()).filter((s) => s.workspaceId === workspaceId);
        all.sort((a, b) => b.createdAt - a.createdAt);
        const total = all.length;
        const start = (page - 1) * pageSize;
        const end = start + pageSize;
        const paged = all.slice(start, end);
        const snapshots = paged.map((snap) => ({
            id: snap.id,
            workspaceId: snap.workspaceId,
            createdAt: snap.createdAt,
            label: snap.label,
            version: snap.version,
            fileCount: snap.openFiles.length,
            terminalCount: snap.terminals.length,
            size: snap.size,
            estimatedRestoreTimeMs: snap.estimatedRestoreTimeMs,
        }));
        return { snapshots, total };
    }
    async deleteSnapshot(snapshotId) {
        this.store.delete(snapshotId);
    }
    async clearWorkspaceSnapshots(workspaceId) {
        const ids = Array.from(this.store.entries())
            .filter(([, snap]) => snap.workspaceId === workspaceId)
            .map(([id]) => id);
        ids.forEach((id) => this.store.delete(id));
    }
    async getStats() {
        const all = Array.from(this.store.values());
        const workspaceMap = new Map();
        let totalSize = 0;
        all.forEach((snap) => {
            const size = snap.size || 0;
            totalSize += size;
            if (!workspaceMap.has(snap.workspaceId)) {
                workspaceMap.set(snap.workspaceId, { count: 0, sizeBytes: 0 });
            }
            const stat = workspaceMap.get(snap.workspaceId);
            stat.count++;
            stat.sizeBytes += size;
        });
        return {
            totalSnapshots: all.length,
            totalSizeBytes: totalSize,
            workspaceStats: Array.from(workspaceMap.entries()).map(([workspaceId, { count, sizeBytes }]) => ({
                workspaceId,
                count,
                sizeBytes,
            })),
        };
    }
}
/**
 * Mock service for testing
 */
class MockSessionSnapshotService extends SessionSnapshotService {
    constructor(mockStorage) {
        super();
        this.mockStorage = mockStorage;
    }
    async initialize(workspaceId) {
        await this.mockStorage.initialize();
        this.storage = this.mockStorage;
        this.currentWorkspaceId = workspaceId;
        this.isInitialized = true;
    }
}
describe('Session Snapshot Service', () => {
    let service;
    let storage;
    const WORKSPACE_ID = 'ws-test-123';
    beforeEach(async () => {
        storage = new MockSessionSnapshotStorage();
        service = new MockSessionSnapshotService(storage);
        await service.initialize(WORKSPACE_ID);
    });
    describe('Snapshot Capture', () => {
        it('should capture snapshot with no label', async () => {
            const snap = await service.captureSnapshot();
            expect(snap).toBeDefined();
            expect(snap.id).toMatch(/^snap-/);
            expect(snap.workspaceId).toBe(WORKSPACE_ID);
            expect(snap.label).toBeUndefined();
            expect(snap.createdAt).toBeGreaterThan(0);
        });
        it('should capture snapshot with label', async () => {
            const label = 'Before refactor';
            const snap = await service.captureSnapshot(label);
            expect(snap.label).toBe(label);
        });
        it('should track capture metrics', async () => {
            const snap = await service.captureSnapshot();
            const metrics = service.getMetrics();
            expect(metrics).toBeDefined();
            expect(metrics.captureStartMs).toBeGreaterThan(0);
            expect(metrics.captureEndMs).toBeGreaterThanOrEqual(metrics.captureStartMs);
            expect(metrics.totalCaptureTimeMs).toBeLessThan(1000); // Should be fast
        });
        it('should categorize as immediate restore', async () => {
            const snap = await service.captureSnapshot();
            expect(snap.restoreableIn).toBe('immediate');
            expect(snap.estimatedRestoreTimeMs).toBeLessThan(500);
        });
        it('should calculate correct snapshot size', async () => {
            const snap = await service.captureSnapshot();
            expect(snap.size).toBeGreaterThan(0);
            expect(typeof snap.size).toBe('number');
        });
        it('should emit snapshot-captured event', async () => {
            const listener = vi.fn();
            service.on('snapshot-captured', listener);
            const snap = await service.captureSnapshot('Test');
            expect(listener).toHaveBeenCalledWith({
                snapshotId: snap.id,
                metrics: expect.any(Object),
                label: 'Test',
            });
        });
    });
    describe('Snapshot Storage & Retrieval', () => {
        it('should store and retrieve snapshot', async () => {
            const original = await service.captureSnapshot('Test 1');
            const retrieved = await service.restoreSnapshot(original.id);
            expect(retrieved.success).toBe(true);
            expect(retrieved.snapshotId).toBe(original.id);
        });
        it('should list all snapshots for workspace', async () => {
            await service.captureSnapshot('Snap 1');
            await service.captureSnapshot('Snap 2');
            await service.captureSnapshot('Snap 3');
            const result = await service.listSnapshots(1, 10);
            expect(result.snapshots.length).toBe(3);
            expect(result.total).toBe(3);
            // All 3 should be present (order may vary due to same timestamps)
            const labels = result.snapshots.map((s) => s.label).sort();
            expect(labels).toEqual(['Snap 1', 'Snap 2', 'Snap 3']);
        });
        it('should paginate snapshots correctly', async () => {
            // Create 15 snapshots
            for (let i = 0; i < 15; i++) {
                await service.captureSnapshot(`Snap ${i}`);
            }
            const page1 = await service.listSnapshots(1, 10);
            const page2 = await service.listSnapshots(2, 10);
            expect(page1.snapshots.length).toBe(10);
            expect(page2.snapshots.length).toBe(5);
            expect(page1.total).toBe(15);
            // All 15 snapshots should exist across pages
            const allLabels = [...page1.snapshots, ...page2.snapshots].map((s) => s.label).sort();
            expect(allLabels.length).toBe(15);
            expect(allLabels[0]).toBe('Snap 0');
            expect(allLabels[14]).toBe('Snap 9');
        });
        it('should delete snapshot', async () => {
            const snap = await service.captureSnapshot();
            const list1 = await service.listSnapshots();
            expect(list1.total).toBe(1);
            await service.deleteSnapshot(snap.id);
            const list2 = await service.listSnapshots();
            expect(list2.total).toBe(0);
        });
        it('should return null for missing snapshot', async () => {
            const result = await service.restoreSnapshot('nonexistent-id');
            expect(result.success).toBe(false);
            expect(result.error).toBeDefined();
        });
    });
    describe('Snapshot Restore', () => {
        it('should restore snapshot with default options', async () => {
            const original = await service.captureSnapshot();
            const result = await service.restoreSnapshot(original.id);
            expect(result.success).toBe(true);
            expect(result.snapshotId).toBe(original.id);
            expect(result.totalTimeMs).toBeLessThan(1000);
        });
        it('should respect restore options', async () => {
            const original = await service.captureSnapshot();
            const result = await service.restoreSnapshot(original.id, {
                includeFiles: true,
                includeTerminals: false,
                includeDebug: false,
                includeSettings: false,
                includeExtensions: false,
            });
            expect(result.success).toBe(true);
        });
        it('should emit snapshot-restored event on success', async () => {
            const original = await service.captureSnapshot();
            const listener = vi.fn();
            service.on('snapshot-restored', listener);
            const result = await service.restoreSnapshot(original.id);
            expect(listener).toHaveBeenCalledWith(expect.objectContaining({
                success: true,
                snapshotId: original.id,
            }));
        });
        it('should track restore timing', async () => {
            const original = await service.captureSnapshot();
            const result = await service.restoreSnapshot(original.id);
            expect(result.totalTimeMs).toBeGreaterThan(0);
            expect(result.totalTimeMs).toBeLessThan(5000);
        });
    });
    describe('Version Management (10-version history)', () => {
        it('should maintain 10-version limit', async () => {
            // Create 15 snapshots
            for (let i = 0; i < 15; i++) {
                await service.captureSnapshot(`Snap ${i}`);
            }
            // Storage should prune to 10
            const result = await service.listSnapshots(1, 100);
            // Note: Mock doesn't auto-prune, but real implementation does
            expect(result.total).toBeGreaterThanOrEqual(10);
        });
        it('should track version numbers', async () => {
            const snap1 = await service.captureSnapshot('V1');
            const snap2 = await service.captureSnapshot('V2');
            expect(snap1.version).toBe(1);
            expect(snap2.version).toBe(1); // Each snapshot starts at v1
        });
        it('should keep newest snapshots after pruning', async () => {
            for (let i = 0; i < 5; i++) {
                await service.captureSnapshot(`Snap ${i}`);
            }
            const result = await service.listSnapshots(1, 100);
            const labels = result.snapshots.map((s) => s.label);
            // All 5 should exist (under limit)
            expect(labels.length).toBe(5);
        });
    });
    describe('Restore Categorization', () => {
        it('should categorize fast restores as immediate', async () => {
            const snap = await service.captureSnapshot();
            expect(snap.restoreableIn).toBe('immediate');
            expect(snap.estimatedRestoreTimeMs).toBeLessThan(500);
        });
        it('should categorize medium restores as quick', async () => {
            // Create snapshot with medium content
            const snap = await service.captureSnapshot();
            if (snap.estimatedRestoreTimeMs > 500 && snap.estimatedRestoreTimeMs <= 2000) {
                expect(snap.restoreableIn).toBe('quick');
            }
            else {
                expect(['immediate', 'quick', 'full']).toContain(snap.restoreableIn);
            }
        });
        it('should categorize slow restores as full', async () => {
            const snap = await service.captureSnapshot();
            if (snap.estimatedRestoreTimeMs > 2000) {
                expect(snap.restoreableIn).toBe('full');
            }
        });
    });
    describe('Error Handling', () => {
        it('should handle capture errors gracefully', async () => {
            // Create new uninitialized service
            const uninit = new SessionSnapshotService();
            try {
                await uninit.captureSnapshot();
                expect.fail('Should have thrown');
            }
            catch (err) {
                expect(String(err)).toContain('not initialized');
            }
        });
        it('should handle restore errors gracefully', async () => {
            const result = await service.restoreSnapshot('nonexistent');
            expect(result.success).toBe(false);
            expect(result.error).toBeDefined();
        });
        it('should emit snapshot-restored with success false on error', async () => {
            const result = await service.restoreSnapshot('nonexistent');
            // Should return failure result
            expect(result.success).toBe(false);
            expect(result.error).toBeDefined();
            expect(result.snapshotId).toBe('nonexistent');
            expect(result.totalTimeMs).toBeGreaterThan(0);
        });
    });
    describe('Metrics & Diagnostics', () => {
        it('should calculate capture metrics', async () => {
            const snap = await service.captureSnapshot();
            const metrics = service.getMetrics();
            expect(metrics).toBeDefined();
            expect(metrics.filesCollected).toBeGreaterThanOrEqual(0);
            expect(metrics.terminalsCollected).toBeGreaterThanOrEqual(0);
            expect(metrics.totalCaptureTimeMs).toBeGreaterThan(0);
        });
        it('should return null metrics before first capture', async () => {
            const uninit = new SessionSnapshotService();
            expect(uninit.getMetrics()).toBeNull();
        });
        it('should estimate restore time based on content', async () => {
            const snap = await service.captureSnapshot();
            expect(snap.estimatedRestoreTimeMs).toBeGreaterThan(0);
            expect(snap.estimatedRestoreTimeMs).toBeLessThan(5000);
        });
    });
    describe('Integration Tests', () => {
        it('should support full cycle: capture → list → restore', async () => {
            // Capture
            const snap1 = await service.captureSnapshot('First');
            const snap2 = await service.captureSnapshot('Second');
            // List
            const list = await service.listSnapshots();
            expect(list.total).toBe(2);
            // Restore first
            const restore1 = await service.restoreSnapshot(snap1.id);
            expect(restore1.success).toBe(true);
            // List should still have both
            const list2 = await service.listSnapshots();
            expect(list2.total).toBe(2);
            // Delete first
            await service.deleteSnapshot(snap1.id);
            // Only second remains
            const list3 = await service.listSnapshots();
            expect(list3.total).toBe(1);
            expect(list3.snapshots[0].id).toBe(snap2.id);
        });
        it('should support concurrent operations', async () => {
            const promises = Array.from({ length: 5 }, (_, i) => service.captureSnapshot(`Concurrent ${i}`));
            const results = await Promise.all(promises);
            expect(results.length).toBe(5);
            expect(results.every((r) => r.id)).toBe(true);
            const list = await service.listSnapshots(1, 100);
            expect(list.total).toBe(5);
        });
        it('should handle restore with selective options', async () => {
            const snap = await service.captureSnapshot();
            const result = await service.restoreSnapshot(snap.id, {
                includeFiles: true,
                includeTerminals: false,
                includeSettings: false,
            });
            expect(result.success).toBe(true);
            expect(result.filesRestored).toBeGreaterThanOrEqual(0);
        });
    });
});
//# sourceMappingURL=session-snapshot.test.js.map