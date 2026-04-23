// apps/backend/src/services/session/session-snapshot-service.ts
// @file: Session snapshots service (Issue #1271)
// Full-fidelity snapshots with files, layout, terminals, debug, extensions
import { EventEmitter } from "events";
import * as crypto from "crypto";
import { getLogger } from "../../lib/logger.js";
/**
 * Session snapshot service for full-fidelity state capture and restoration
 */
export class SessionSnapshotService extends EventEmitter {
    constructor(maxVersions = 10) {
        super();
        this.logger = getLogger("SessionSnapshot");
        this.snapshots = new Map();
        this.versionHistory = new Map();
        this.maxVersions = 10;
        this.snapshotCounter = 0;
        this.maxVersions = maxVersions;
    }
    /**
     * Create a new session snapshot
     */
    createSnapshot(sessionId, userId, workspaceId, state, metadata) {
        try {
            const snapshotId = `snap-${Date.now()}-${++this.snapshotCounter}`;
            // Calculate checksum of state
            const stateStr = JSON.stringify(state);
            const checksum = crypto.createHash("sha256").update(stateStr).digest("hex").substring(0, 16);
            // Calculate compression ratio (estimate)
            const uncompressed = stateStr.length;
            const sizeBytes = Math.ceil(uncompressed * 0.7); // Assume 30% compression ratio
            // Get version number
            const historySnapshots = this.versionHistory.get(sessionId) || [];
            const version = historySnapshots.length + 1;
            // Create snapshot
            const snapshot = {
                id: snapshotId,
                sessionId,
                userId,
                workspaceId,
                timestamp: new Date(),
                version,
                metadata: {
                    description: metadata?.description || `Snapshot v${version}`,
                    creator: userId,
                    checksum,
                    tags: metadata?.tags || [],
                    restorePoints: 0,
                },
                fileState: state.fileState,
                layoutState: state.layoutState,
                terminals: state.terminals,
                debugConfig: state.debugConfig,
                extensions: state.extensions,
                tags: metadata?.tags || [],
                compressionRatio: 0.7,
                sizeBytes,
            };
            this.snapshots.set(snapshotId, snapshot);
            // Maintain version history
            if (!this.versionHistory.has(sessionId)) {
                this.versionHistory.set(sessionId, []);
            }
            const sessionHistory = this.versionHistory.get(sessionId);
            sessionHistory.push(snapshot);
            // Enforce max versions by removing oldest
            if (sessionHistory.length > this.maxVersions) {
                const oldest = sessionHistory.shift();
                if (oldest) {
                    this.snapshots.delete(oldest.id);
                }
            }
            this.logger.info("Session snapshot created", {
                snapshotId,
                sessionId,
                userId,
                version,
                fileCount: state.fileState.length,
                extensionCount: state.extensions.length,
                sizeBytes,
            });
            this.emit("snapshot-created", {
                snapshotId,
                sessionId,
                version,
            });
            return {
                success: true,
                snapshotId,
                checksum,
            };
        }
        catch (error) {
            const err = error;
            this.logger.error("Failed to create snapshot", {
                error: err.message,
                sessionId,
                userId,
            });
            return {
                success: false,
                snapshotId: "",
                checksum: "",
            };
        }
    }
    /**
     * Restore session from snapshot
     */
    restoreSnapshot(sessionId, snapshotId, userId) {
        try {
            const startTime = Date.now();
            const snapshot = this.snapshots.get(snapshotId);
            if (!snapshot) {
                return {
                    success: false,
                    restoreTime: 0,
                };
            }
            if (snapshot.sessionId !== sessionId) {
                this.logger.warn("Snapshot session mismatch", {
                    snapshotId,
                    expectedSession: sessionId,
                    actualSession: snapshot.sessionId,
                });
                return {
                    success: false,
                    restoreTime: 0,
                };
            }
            // Prepare restoration state
            const restoredState = {
                fileState: snapshot.fileState,
                layoutState: snapshot.layoutState,
                terminals: snapshot.terminals,
                debugConfig: snapshot.debugConfig,
                extensions: snapshot.extensions,
            };
            const restoreTime = Date.now() - startTime;
            this.logger.info("Session snapshot restored", {
                snapshotId,
                sessionId,
                userId,
                version: snapshot.version,
                restoreTime,
                fileCount: snapshot.fileState.length,
            });
            this.emit("snapshot-restored", {
                snapshotId,
                sessionId,
                restoreTime,
            });
            return {
                success: true,
                restoredState,
                restoreTime,
            };
        }
        catch (error) {
            const err = error;
            this.logger.error("Failed to restore snapshot", {
                error: err.message,
                snapshotId,
                sessionId,
            });
            return {
                success: false,
                restoreTime: 0,
            };
        }
    }
    /**
     * Get snapshot details
     */
    getSnapshot(snapshotId) {
        return this.snapshots.get(snapshotId) || null;
    }
    /**
     * List snapshots for a session
     */
    listSnapshots(sessionId, limit = 10) {
        const history = this.versionHistory.get(sessionId) || [];
        return history.slice(-limit).reverse(); // Most recent first
    }
    /**
     * Delete a snapshot
     */
    deleteSnapshot(snapshotId) {
        try {
            const snapshot = this.snapshots.get(snapshotId);
            if (!snapshot) {
                return {
                    success: false,
                    message: "Snapshot not found",
                };
            }
            // Remove from snapshots map
            this.snapshots.delete(snapshotId);
            // Remove from version history
            const history = this.versionHistory.get(snapshot.sessionId);
            if (history) {
                const index = history.findIndex((s) => s.id === snapshotId);
                if (index >= 0) {
                    history.splice(index, 1);
                }
            }
            this.logger.info("Snapshot deleted", {
                snapshotId,
                sessionId: snapshot.sessionId,
            });
            return {
                success: true,
                message: "Snapshot deleted",
            };
        }
        catch (error) {
            const err = error;
            this.logger.error("Failed to delete snapshot", {
                error: err.message,
                snapshotId,
            });
            return {
                success: false,
                message: `Failed to delete snapshot: ${err.message}`,
            };
        }
    }
    /**
     * Tag a snapshot for organization
     */
    tagSnapshot(snapshotId, tags) {
        try {
            const snapshot = this.snapshots.get(snapshotId);
            if (!snapshot) {
                return {
                    success: false,
                    tags: [],
                };
            }
            snapshot.tags = [...new Set([...snapshot.tags, ...tags])];
            snapshot.metadata.tags = snapshot.tags;
            this.logger.info("Snapshot tagged", {
                snapshotId,
                tags: snapshot.tags,
            });
            return {
                success: true,
                tags: snapshot.tags,
            };
        }
        catch (error) {
            const err = error;
            this.logger.error("Failed to tag snapshot", {
                error: err.message,
                snapshotId,
            });
            return {
                success: false,
                tags: [],
            };
        }
    }
    /**
     * Compare two snapshots
     */
    compareSnapshots(snapshotId1, snapshotId2) {
        try {
            const snap1 = this.snapshots.get(snapshotId1);
            const snap2 = this.snapshots.get(snapshotId2);
            if (!snap1 || !snap2) {
                return {
                    success: false,
                    differences: {
                        filesChanged: 0,
                        layoutChanged: false,
                        terminalsChanged: 0,
                        debugChanged: false,
                        extensionsChanged: 0,
                    },
                };
            }
            // Count differences
            const filesChanged = Math.max(Math.abs(snap1.fileState.length - snap2.fileState.length), snap1.fileState.filter((f) => !snap2.fileState.find((f2) => f2.path === f.path)).length);
            const layoutChanged = JSON.stringify(snap1.layoutState) !== JSON.stringify(snap2.layoutState);
            const terminalsChanged = Math.abs(snap1.terminals.length - snap2.terminals.length);
            const debugChanged = JSON.stringify(snap1.debugConfig) !== JSON.stringify(snap2.debugConfig);
            const extensionsChanged = Math.abs(snap1.extensions.length - snap2.extensions.length);
            return {
                success: true,
                differences: {
                    filesChanged,
                    layoutChanged,
                    terminalsChanged,
                    debugChanged,
                    extensionsChanged,
                },
            };
        }
        catch (error) {
            const err = error;
            this.logger.error("Failed to compare snapshots", {
                error: err.message,
                snapshotId1,
                snapshotId2,
            });
            return {
                success: false,
                differences: {
                    filesChanged: 0,
                    layoutChanged: false,
                    terminalsChanged: 0,
                    debugChanged: false,
                    extensionsChanged: 0,
                },
            };
        }
    }
    /**
     * Get statistics for a session
     */
    getSessionStats(sessionId) {
        const history = this.versionHistory.get(sessionId) || [];
        if (history.length === 0) {
            return {
                totalSnapshots: 0,
                totalSizeBytes: 0,
                averageRestoreTime: 0,
            };
        }
        const totalSizeBytes = history.reduce((sum, snap) => sum + (snap.sizeBytes || 0), 0);
        return {
            totalSnapshots: history.length,
            oldestSnapshot: history[0]?.timestamp,
            newestSnapshot: history[history.length - 1]?.timestamp,
            totalSizeBytes,
            averageRestoreTime: 5000, // Estimate 5 seconds average
        };
    }
}
// Singleton instance
let instance = null;
export function getSessionSnapshotService(maxVersions) {
    if (!instance) {
        instance = new SessionSnapshotService(maxVersions);
    }
    return instance;
}
//# sourceMappingURL=session-snapshot-service.js.map