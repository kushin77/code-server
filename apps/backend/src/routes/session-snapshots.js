// apps/backend/src/routes/session-snapshots.ts
// @file: HTTP routes for session snapshots (Issue #1271)
// Full-fidelity snapshots with < 10s restore time and 10-version history
import { Router } from "express";
import { getSessionSnapshotService } from "../services/session/session-snapshot-service.js";
const router = Router();
const snapshotService = getSessionSnapshotService(10);
/**
 * POST /api/sessions/snapshots
 * Create a new session snapshot
 *
 * Body:
 * {
 *   "sessionId": string,
 *   "fileState": FileSnapshot[],
 *   "layoutState": LayoutSnapshot,
 *   "terminals": TerminalSnapshot[],
 *   "debugConfig": DebugSnapshot,
 *   "extensions": ExtensionSnapshot[],
 *   "description": string (optional),
 *   "tags": string[] (optional)
 * }
 */
router.post("/", (req, res) => {
    try {
        const { sessionId, fileState, layoutState, terminals, debugConfig, extensions, description, tags } = req.body;
        const userId = req.user?.id || "system";
        const workspaceId = req.user?.workspaceId || "default";
        if (!sessionId || !fileState || !layoutState || !terminals || !debugConfig || !extensions) {
            res.status(400).json({
                error: "Missing required fields: sessionId, fileState, layoutState, terminals, debugConfig, extensions",
            });
            return;
        }
        const result = snapshotService.createSnapshot(sessionId, userId, workspaceId, {
            fileState,
            layoutState,
            terminals,
            debugConfig,
            extensions,
        }, {
            description,
            tags,
        });
        if (result.success) {
            res.status(201).json({
                snapshotId: result.snapshotId,
                checksum: result.checksum,
                message: "Snapshot created successfully",
            });
        }
        else {
            res.status(500).json({
                error: "Failed to create snapshot",
            });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * GET /api/sessions/:sessionId/snapshots
 * List all snapshots for a session
 *
 * Query:
 * - limit: number (default 10, max 10)
 */
router.get("/:sessionId/snapshots", (req, res) => {
    try {
        const { sessionId } = req.params;
        const limit = Math.min(parseInt(req.query.limit) || 10, 10);
        const snapshots = snapshotService.listSnapshots(sessionId, limit);
        res.json({
            sessionId,
            count: snapshots.length,
            snapshots: snapshots.map((snap) => ({
                id: snap.id,
                version: snap.version,
                timestamp: snap.timestamp,
                description: snap.metadata.description,
                fileCount: snap.fileState.length,
                extensionCount: snap.extensions.length,
                sizeBytes: snap.sizeBytes,
                tags: snap.tags,
            })),
        });
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * GET /api/snapshots/:snapshotId
 * Get snapshot details
 */
router.get("/:snapshotId", (req, res) => {
    try {
        const { snapshotId } = req.params;
        const snapshot = snapshotService.getSnapshot(snapshotId);
        if (!snapshot) {
            res.status(404).json({ error: "Snapshot not found" });
            return;
        }
        res.json({
            id: snapshot.id,
            sessionId: snapshot.sessionId,
            userId: snapshot.userId,
            workspaceId: snapshot.workspaceId,
            timestamp: snapshot.timestamp,
            version: snapshot.version,
            description: snapshot.metadata.description,
            fileCount: snapshot.fileState.length,
            layoutState: snapshot.layoutState,
            terminals: snapshot.terminals,
            debugConfig: snapshot.debugConfig,
            extensions: snapshot.extensions,
            tags: snapshot.tags,
            sizeBytes: snapshot.sizeBytes,
        });
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * POST /api/snapshots/:snapshotId/restore
 * Restore a session from snapshot
 *
 * Body:
 * {
 *   "sessionId": string
 * }
 */
router.post("/:snapshotId/restore", (req, res) => {
    try {
        const { snapshotId } = req.params;
        const { sessionId } = req.body;
        const userId = req.user?.id || "system";
        if (!sessionId) {
            res.status(400).json({ error: "sessionId is required" });
            return;
        }
        const result = snapshotService.restoreSnapshot(sessionId, snapshotId, userId);
        if (result.success) {
            res.json({
                message: "Snapshot restored successfully",
                restoreTime: result.restoreTime,
                state: {
                    fileState: result.restoredState?.fileState,
                    layoutState: result.restoredState?.layoutState,
                    terminals: result.restoredState?.terminals,
                    debugConfig: result.restoredState?.debugConfig,
                    extensions: result.restoredState?.extensions,
                },
            });
        }
        else {
            res.status(400).json({
                error: "Failed to restore snapshot",
            });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * DELETE /api/snapshots/:snapshotId
 * Delete a snapshot
 */
router.delete("/:snapshotId", (req, res) => {
    try {
        const { snapshotId } = req.params;
        const result = snapshotService.deleteSnapshot(snapshotId);
        if (result.success) {
            res.json({
                message: result.message,
            });
        }
        else {
            res.status(400).json({
                error: result.message,
            });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * POST /api/snapshots/:snapshotId/tag
 * Add tags to a snapshot
 *
 * Body:
 * {
 *   "tags": string[]
 * }
 */
router.post("/:snapshotId/tag", (req, res) => {
    try {
        const { snapshotId } = req.params;
        const { tags } = req.body;
        if (!tags || !Array.isArray(tags)) {
            res.status(400).json({ error: "tags array is required" });
            return;
        }
        const result = snapshotService.tagSnapshot(snapshotId, tags);
        if (result.success) {
            res.json({
                tags: result.tags,
                message: "Tags added successfully",
            });
        }
        else {
            res.status(400).json({
                error: "Failed to tag snapshot",
            });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * POST /api/snapshots/compare
 * Compare two snapshots
 *
 * Body:
 * {
 *   "snapshotId1": string,
 *   "snapshotId2": string
 * }
 */
router.post("/compare", (req, res) => {
    try {
        const { snapshotId1, snapshotId2 } = req.body;
        if (!snapshotId1 || !snapshotId2) {
            res.status(400).json({ error: "snapshotId1 and snapshotId2 are required" });
            return;
        }
        const result = snapshotService.compareSnapshots(snapshotId1, snapshotId2);
        if (result.success) {
            res.json({
                differences: result.differences,
            });
        }
        else {
            res.status(400).json({
                error: "Failed to compare snapshots",
            });
        }
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
/**
 * GET /api/sessions/:sessionId/snapshots/stats
 * Get snapshot statistics for a session
 */
router.get("/:sessionId/snapshots/stats", (req, res) => {
    try {
        const { sessionId } = req.params;
        const stats = snapshotService.getSessionStats(sessionId);
        res.json({
            sessionId,
            totalSnapshots: stats.totalSnapshots,
            oldestSnapshot: stats.oldestSnapshot,
            newestSnapshot: stats.newestSnapshot,
            totalSizeBytes: stats.totalSizeBytes,
            averageRestoreTime: stats.averageRestoreTime,
        });
    }
    catch (error) {
        const err = error;
        res.status(500).json({ error: err.message });
    }
});
export default router;
//# sourceMappingURL=session-snapshots.js.map