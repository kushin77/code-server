// apps/backend/src/services/session/__tests__/session-snapshot-service.test.ts
import { describe, it, expect, beforeEach } from "vitest";
import { SessionSnapshotService } from "../session-snapshot-service";
describe("SessionSnapshotService", () => {
    let service;
    beforeEach(() => {
        service = new SessionSnapshotService(10);
    });
    const createMockState = () => ({
        fileState: [
            { path: "file1.ts", language: "typescript", isDirty: false, cursorPosition: { line: 10, character: 5 } },
            { path: "file2.js", language: "javascript", isDirty: true, cursorPosition: { line: 0, character: 0 } },
        ],
        layoutState: {
            editorState: {
                groups: [
                    {
                        editors: [
                            { name: "file1.ts", path: "file1.ts", dirty: false, pinned: true, preview: false },
                            { name: "file2.js", path: "file2.js", dirty: true, pinned: false, preview: true },
                        ],
                        activeEditor: 0,
                    },
                ],
                activeGroup: 0,
            },
            sidebarState: { visible: true, primarySideBarSize: 300 },
            panelState: { height: 300, position: "bottom" },
        },
        terminals: [
            { id: "term1", name: "bash", shell: "/bin/bash", cwd: "/home/user/project", environment: { SHELL: "/bin/bash" } },
        ],
        debugConfig: {
            active: false,
            configurations: [{ name: "Node", type: "node", request: "launch", config: {} }],
            breakpoints: [],
        },
        extensions: [
            { id: "ext1", name: "Extension 1", version: "1.0.0", isActive: true },
            { id: "ext2", name: "Extension 2", version: "2.0.0", isActive: true },
        ],
    });
    describe("createSnapshot", () => {
        it("should create a snapshot successfully", () => {
            const state = createMockState();
            const result = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            expect(result.success).toBe(true);
            expect(result.snapshotId).toBeDefined();
            expect(result.checksum).toBeDefined();
        });
        it("should generate unique snapshot IDs", () => {
            const state = createMockState();
            const result1 = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const result2 = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            expect(result1.snapshotId).not.toBe(result2.snapshotId);
        });
        it("should track version numbers sequentially", () => {
            const state = createMockState();
            const r1 = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const r2 = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const snap1 = service.getSnapshot(r1.snapshotId);
            const snap2 = service.getSnapshot(r2.snapshotId);
            expect(snap1?.version).toBe(1);
            expect(snap2?.version).toBe(2);
        });
        it("should generate consistent checksums for same state", () => {
            const state = createMockState();
            const result1 = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            expect(result1.checksum).toBeDefined();
            expect(result1.checksum.length).toBeGreaterThan(0);
        });
        it("should calculate snapshot size", () => {
            const state = createMockState();
            const result = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const snapshot = service.getSnapshot(result.snapshotId);
            expect(snapshot?.sizeBytes).toBeDefined();
            expect(snapshot?.sizeBytes).toBeGreaterThan(0);
        });
        it("should maintain max versions limit", () => {
            const service10 = new SessionSnapshotService(3);
            const state = createMockState();
            // Create 5 snapshots
            for (let i = 0; i < 5; i++) {
                service10.createSnapshot("session-123", "user-456", "workspace-789", state);
            }
            const history = service10.listSnapshots("session-123", 100);
            expect(history.length).toBeLessThanOrEqual(3);
        });
    });
    describe("restoreSnapshot", () => {
        it("should restore snapshot successfully", () => {
            const state = createMockState();
            const createResult = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const restoreResult = service.restoreSnapshot("session-123", createResult.snapshotId, "user-456");
            expect(restoreResult.success).toBe(true);
            expect(restoreResult.restoredState).toBeDefined();
            expect(restoreResult.restoreTime).toBeLessThan(10000); // Should be < 10s
        });
        it("should preserve file state during restore", () => {
            const state = createMockState();
            const createResult = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const restoreResult = service.restoreSnapshot("session-123", createResult.snapshotId, "user-456");
            expect(restoreResult.restoredState?.fileState).toEqual(state.fileState);
        });
        it("should preserve layout state during restore", () => {
            const state = createMockState();
            const createResult = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const restoreResult = service.restoreSnapshot("session-123", createResult.snapshotId, "user-456");
            expect(restoreResult.restoredState?.layoutState).toEqual(state.layoutState);
        });
        it("should fail for non-existent snapshot", () => {
            const result = service.restoreSnapshot("session-123", "non-existent-id", "user-456");
            expect(result.success).toBe(false);
        });
        it("should fail on session mismatch", () => {
            const state = createMockState();
            const createResult = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const result = service.restoreSnapshot("session-999", createResult.snapshotId, "user-456");
            expect(result.success).toBe(false);
        });
    });
    describe("Snapshot Management", () => {
        it("should retrieve snapshot by ID", () => {
            const state = createMockState();
            const createResult = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const snapshot = service.getSnapshot(createResult.snapshotId);
            expect(snapshot).not.toBeNull();
            expect(snapshot?.sessionId).toBe("session-123");
        });
        it("should list snapshots in reverse chronological order", () => {
            const state = createMockState();
            const r1 = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const r2 = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const list = service.listSnapshots("session-123");
            expect(list[0].id).toBe(r2.snapshotId); // Most recent first
            expect(list[1].id).toBe(r1.snapshotId);
        });
        it("should delete snapshot successfully", () => {
            const state = createMockState();
            const createResult = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const deleteResult = service.deleteSnapshot(createResult.snapshotId);
            expect(deleteResult.success).toBe(true);
            const snapshot = service.getSnapshot(createResult.snapshotId);
            expect(snapshot).toBeNull();
        });
        it("should fail to delete non-existent snapshot", () => {
            const result = service.deleteSnapshot("non-existent-id");
            expect(result.success).toBe(false);
            expect(result.message).toContain("not found");
        });
        it("should tag snapshots", () => {
            const state = createMockState();
            const createResult = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const tagResult = service.tagSnapshot(createResult.snapshotId, ["backup", "important"]);
            expect(tagResult.success).toBe(true);
            expect(tagResult.tags).toContain("backup");
            expect(tagResult.tags).toContain("important");
        });
        it("should deduplicate tags", () => {
            const state = createMockState();
            const createResult = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            service.tagSnapshot(createResult.snapshotId, ["backup"]);
            const tagResult = service.tagSnapshot(createResult.snapshotId, ["backup", "important"]);
            expect(tagResult.tags).toEqual(expect.arrayContaining(["backup", "important"]));
            expect(tagResult.tags.filter((t) => t === "backup")).toHaveLength(1);
        });
    });
    describe("Snapshot Comparison", () => {
        it("should compare two snapshots", () => {
            const state1 = createMockState();
            const state2 = createMockState();
            const r1 = service.createSnapshot("session-123", "user-456", "workspace-789", state1);
            const r2 = service.createSnapshot("session-123", "user-456", "workspace-789", state2);
            const result = service.compareSnapshots(r1.snapshotId, r2.snapshotId);
            expect(result.success).toBe(true);
            expect(result.differences).toBeDefined();
        });
        it("should detect identical snapshots", () => {
            const state = createMockState();
            const r1 = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const r2 = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const result = service.compareSnapshots(r1.snapshotId, r2.snapshotId);
            expect(result.differences.filesChanged).toBe(0);
            expect(result.differences.layoutChanged).toBe(false);
        });
        it("should fail for non-existent snapshots", () => {
            const result = service.compareSnapshots("snap-1", "snap-2");
            expect(result.success).toBe(false);
        });
    });
    describe("Session Statistics", () => {
        it("should return stats for empty session", () => {
            const stats = service.getSessionStats("session-999");
            expect(stats.totalSnapshots).toBe(0);
            expect(stats.totalSizeBytes).toBe(0);
        });
        it("should calculate total snapshots", () => {
            const state = createMockState();
            service.createSnapshot("session-123", "user-456", "workspace-789", state);
            service.createSnapshot("session-123", "user-456", "workspace-789", state);
            service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const stats = service.getSessionStats("session-123");
            expect(stats.totalSnapshots).toBe(3);
        });
        it("should calculate total size bytes", () => {
            const state = createMockState();
            service.createSnapshot("session-123", "user-456", "workspace-789", state);
            service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const stats = service.getSessionStats("session-123");
            expect(stats.totalSizeBytes).toBeGreaterThan(0);
        });
        it("should track oldest and newest snapshot timestamps", () => {
            const state = createMockState();
            service.createSnapshot("session-123", "user-456", "workspace-789", state);
            service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const stats = service.getSessionStats("session-123");
            expect(stats.oldestSnapshot).toBeDefined();
            expect(stats.newestSnapshot).toBeDefined();
            expect((stats.newestSnapshot?.getTime() || 0) >= (stats.oldestSnapshot?.getTime() || 0)).toBe(true);
        });
    });
    describe("Multiple Sessions", () => {
        it("should isolate snapshots between sessions", () => {
            const state = createMockState();
            const r1 = service.createSnapshot("session-1", "user-1", "workspace-1", state);
            const r2 = service.createSnapshot("session-2", "user-2", "workspace-2", state);
            const snap1 = service.getSnapshot(r1.snapshotId);
            const snap2 = service.getSnapshot(r2.snapshotId);
            expect(snap1?.sessionId).toBe("session-1");
            expect(snap2?.sessionId).toBe("session-2");
        });
        it("should maintain separate version histories", () => {
            const state = createMockState();
            service.createSnapshot("session-1", "user-1", "workspace-1", state);
            service.createSnapshot("session-1", "user-1", "workspace-1", state);
            service.createSnapshot("session-2", "user-2", "workspace-2", state);
            const list1 = service.listSnapshots("session-1");
            const list2 = service.listSnapshots("session-2");
            expect(list1.length).toBe(2);
            expect(list2.length).toBe(1);
        });
    });
    describe("Event Emission", () => {
        it("should emit snapshot-created event", (done) => {
            const state = createMockState();
            service.on("snapshot-created", (data) => {
                expect(data.snapshotId).toBeDefined();
                expect(data.sessionId).toBe("session-123");
                expect(data.version).toBe(1);
                done();
            });
            service.createSnapshot("session-123", "user-456", "workspace-789", state);
        });
        it("should emit snapshot-restored event", (done) => {
            const state = createMockState();
            const createResult = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            service.on("snapshot-restored", (data) => {
                expect(data.snapshotId).toBeDefined();
                expect(data.sessionId).toBe("session-123");
                expect(data.restoreTime).toBeLessThan(10000);
                done();
            });
            service.restoreSnapshot("session-123", createResult.snapshotId, "user-456");
        });
    });
    describe("Content Preservation", () => {
        it("should preserve all file metadata", () => {
            const state = createMockState();
            const createResult = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const snapshot = service.getSnapshot(createResult.snapshotId);
            expect(snapshot?.fileState).toEqual(state.fileState);
        });
        it("should preserve terminal configurations", () => {
            const state = createMockState();
            const createResult = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const snapshot = service.getSnapshot(createResult.snapshotId);
            expect(snapshot?.terminals).toEqual(state.terminals);
        });
        it("should preserve extension list", () => {
            const state = createMockState();
            const createResult = service.createSnapshot("session-123", "user-456", "workspace-789", state);
            const snapshot = service.getSnapshot(createResult.snapshotId);
            expect(snapshot?.extensions).toEqual(state.extensions);
        });
    });
});
//# sourceMappingURL=session-snapshot-service.test.js.map