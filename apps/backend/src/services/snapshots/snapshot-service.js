/**
 * Session Snapshots Service
 * Full-fidelity snapshots with fast restore (<10s) and 10-version history
 */
import { EventEmitter } from 'events';
/**
 * Session Snapshots Service
 * Capture and restore full-fidelity session state
 */
export class SnapshotService extends EventEmitter {
    constructor(config) {
        super();
        this.isInitialized = false;
        this.snapshots = new Map();
        this.metadata = new Map(); // Per-user metadata
        this.auditLog = new Map(); // Per-user audit trail
        this.stats = {
            totalSnapshots: 0,
            snapshotsByVersion: {},
            snapshotsByUser: {},
            snapshotsByWorkspace: {},
            totalStorageBytes: 0,
            averageSnapshotSize: 0,
            averageRestoreTime: 0,
            restoreSuccessRate: 100,
            autoSnapshots: 0,
            manualSnapshots: 0,
            oldestSnapshot: Date.now(),
            newestSnapshot: Date.now(),
        };
        /**
         * Private: Auto-snapshot timer
         */
        this.autoSnapshotTimer = null;
        this.config = {
            enabled: true,
            auditLoggingEnabled: true,
            maxVersions: 10,
            maxSnapshotsPerUser: 100,
            autoSnapshotEnabled: false,
            autoSnapshotInterval: 0,
            restoreTimeoutMs: 10000, // < 10s restore
            compressionEnabled: true,
            encryptionEnabled: false,
            maxAuditLogSize: 10000,
            storageBackend: 'memory',
            ...config,
        };
    }
    /**
     * Initialize service
     */
    async initialize() {
        if (this.isInitialized)
            return;
        this.isInitialized = true;
        if (this.config.autoSnapshotEnabled && this.config.autoSnapshotInterval > 0) {
            this.startAutoSnapshot();
        }
        this.emit('initialized');
    }
    /**
     * Shutdown service
     */
    async shutdown() {
        this.stopAutoSnapshot();
        this.emit('shutdown');
    }
    /**
     * Create snapshot
     */
    async createSnapshot(userId, userEmail, workspaceId, sessionId, snapshot, ipAddress, userAgent) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const now = Date.now();
        const snapshotId = `snap-${userId}-${workspaceId}-${now}-${Math.random().toString(36).slice(2, 9)}`;
        // Get current version count for this user+workspace
        const userMetadata = this.metadata.get(userId) || [];
        const wsSnapshots = userMetadata.filter((m) => m.workspaceId === workspaceId);
        const nextVersion = wsSnapshots.length + 1;
        // Calculate total size
        const totalSize = this.calculateSnapshotSize({
            ...snapshot,
            id: snapshotId,
            userId,
            userEmail,
            workspaceId,
            sessionId,
            timestamp: now,
            version: nextVersion,
        });
        // Check max versions per workspace
        if (nextVersion > this.config.maxVersions) {
            // Delete oldest version
            const oldestIdx = userMetadata.findIndex((m) => m.workspaceId === workspaceId);
            if (oldestIdx >= 0) {
                const oldestId = userMetadata[oldestIdx].snapshotId;
                this.snapshots.delete(oldestId);
                userMetadata.splice(oldestIdx, 1);
            }
        }
        const fullSnapshot = {
            ...snapshot,
            id: snapshotId,
            userId,
            userEmail,
            workspaceId,
            sessionId,
            timestamp: now,
            version: Math.min(nextVersion, this.config.maxVersions),
        };
        this.snapshots.set(snapshotId, fullSnapshot);
        // Update metadata
        const newMetadata = {
            snapshotId,
            userId,
            userEmail,
            workspaceId,
            version: fullSnapshot.version,
            createdAt: now,
            createdBy: userId,
            size: totalSize,
            fileCount: snapshot.files?.length || 0,
            terminalCount: snapshot.terminals?.length || 0,
            tags: snapshot.tags || [],
            description: snapshot.description,
            isAutomatic: false,
        };
        if (!this.metadata.has(userId)) {
            this.metadata.set(userId, []);
        }
        this.metadata.get(userId).push(newMetadata);
        // Limit to maxSnapshotsPerUser
        const userSnaps = this.metadata.get(userId);
        if (userSnaps.length > this.config.maxSnapshotsPerUser) {
            const toRemove = userSnaps.shift();
            this.snapshots.delete(toRemove.snapshotId);
        }
        // Log audit
        const auditEntry = {
            id: `audit-${snapshotId}`,
            userId,
            userEmail,
            operation: 'created',
            status: 'success',
            snapshotId,
            snapshotVersion: fullSnapshot.version,
            ipAddress,
            userAgent,
            timestamp: now,
            fileCount: snapshot.files?.length,
        };
        await this.logAudit(userId, auditEntry);
        this.updateStats();
        this.emit('snapshot-created', { snapshotId, userId, version: fullSnapshot.version });
        return fullSnapshot;
    }
    /**
     * Get snapshot
     */
    async getSnapshot(snapshotId) {
        return this.snapshots.get(snapshotId);
    }
    /**
     * Restore snapshot
     */
    async restoreSnapshot(request, ipAddress, userAgent) {
        if (!this.isInitialized)
            throw new Error('Service not initialized');
        const startTime = Date.now();
        const snapshot = this.snapshots.get(request.snapshotId);
        if (!snapshot) {
            const auditEntry = {
                id: `audit-restore-${request.snapshotId}-${startTime}`,
                userId: request.userId,
                userEmail: request.userEmail,
                operation: 'restored',
                status: 'error',
                snapshotId: request.snapshotId,
                ipAddress,
                userAgent,
                timestamp: startTime,
            };
            await this.logAudit(request.userId, auditEntry);
            return {
                snapshotId: request.snapshotId,
                successful: false,
                startTime,
                endTime: Date.now(),
                duration: Date.now() - startTime,
                filesRestored: 0,
                errors: [{ file: 'snapshot', reason: 'Snapshot not found' }],
            };
        }
        // Simulate restore with configurable timeout
        const errors = [];
        let filesRestored = 0;
        if (request.restoreOptions.restoreFiles) {
            filesRestored = snapshot.files?.length || 0;
        }
        const endTime = Date.now();
        const duration = endTime - startTime;
        // Verify restore time < 10s
        if (duration > this.config.restoreTimeoutMs) {
            errors.push({
                file: 'restore',
                reason: `Restore took ${duration}ms, exceeded timeout of ${this.config.restoreTimeoutMs}ms`,
            });
        }
        // Log audit
        const auditEntry = {
            id: `audit-restore-${request.snapshotId}-${startTime}`,
            userId: request.userId,
            userEmail: request.userEmail,
            operation: 'restored',
            status: errors.length === 0 ? 'success' : 'error',
            snapshotId: request.snapshotId,
            snapshotVersion: snapshot.version,
            ipAddress,
            userAgent,
            timestamp: startTime,
            duration,
            fileCount: filesRestored,
        };
        await this.logAudit(request.userId, auditEntry);
        this.updateStats();
        this.emit('snapshot-restored', {
            snapshotId: request.snapshotId,
            duration,
            successful: errors.length === 0,
        });
        return {
            snapshotId: request.snapshotId,
            successful: errors.length === 0,
            startTime,
            endTime,
            duration,
            filesRestored,
            errors: errors.length > 0 ? errors : undefined,
        };
    }
    /**
     * Delete snapshot
     */
    async deleteSnapshot(userId, userEmail, snapshotId, ipAddress, userAgent) {
        const now = Date.now();
        this.snapshots.delete(snapshotId);
        // Update metadata
        const userMeta = this.metadata.get(userId);
        if (userMeta) {
            const idx = userMeta.findIndex((m) => m.snapshotId === snapshotId);
            if (idx >= 0) {
                userMeta.splice(idx, 1);
            }
        }
        // Log audit
        const auditEntry = {
            id: `audit-delete-${snapshotId}-${now}`,
            userId,
            userEmail,
            operation: 'deleted',
            status: 'success',
            snapshotId,
            ipAddress,
            userAgent,
            timestamp: now,
        };
        await this.logAudit(userId, auditEntry);
        this.updateStats();
        this.emit('snapshot-deleted', { snapshotId });
    }
    /**
     * List snapshots for user
     */
    async listSnapshots(userId, workspaceId) {
        const userMeta = this.metadata.get(userId) || [];
        let results = userMeta;
        if (workspaceId) {
            results = results.filter((m) => m.workspaceId === workspaceId);
        }
        return results
            .sort((a, b) => b.createdAt - a.createdAt)
            .map((m) => ({
            id: m.snapshotId,
            version: m.version,
            timestamp: m.createdAt,
            duration: 0,
            fileCount: m.fileCount,
            terminalCount: m.terminalCount,
            totalSize: m.size,
            tags: m.tags,
            description: m.description,
        }));
    }
    /**
     * Query snapshots
     */
    async querySnapshots(query) {
        let results = [];
        if (query.userId) {
            results = this.metadata.get(query.userId) || [];
        }
        else {
            // Get all
            for (const userMeta of this.metadata.values()) {
                results.push(...userMeta);
            }
        }
        // Filter by workspace
        if (query.workspaceId) {
            results = results.filter((m) => m.workspaceId === query.workspaceId);
        }
        // Filter by time range
        if (query.fromTime || query.toTime) {
            results = results.filter((m) => (!query.fromTime || m.createdAt >= query.fromTime) &&
                (!query.toTime || m.createdAt <= query.toTime));
        }
        // Filter by tags
        if (query.tags && query.tags.length > 0) {
            results = results.filter((m) => query.tags.some((tag) => m.tags.includes(tag)));
        }
        // Sort by timestamp descending
        results.sort((a, b) => b.createdAt - a.createdAt);
        // Paginate
        const limit = query.limit || 20;
        const offset = query.offset || 0;
        return {
            snapshots: results.slice(offset, offset + limit).map((m) => ({
                id: m.snapshotId,
                version: m.version,
                timestamp: m.createdAt,
                duration: 0,
                fileCount: m.fileCount,
                terminalCount: m.terminalCount,
                totalSize: m.size,
                tags: m.tags,
                description: m.description,
            })),
            total: results.length,
            limit,
            offset,
        };
    }
    /**
     * Tag snapshot
     */
    async tagSnapshot(userId, userEmail, snapshotId, tags, ipAddress, userAgent) {
        const userMeta = this.metadata.get(userId);
        if (userMeta) {
            const meta = userMeta.find((m) => m.snapshotId === snapshotId);
            if (meta) {
                meta.tags.push(...tags);
                meta.tags = [...new Set(meta.tags)]; // Deduplicate
            }
        }
        // Log audit
        const auditEntry = {
            id: `audit-tag-${snapshotId}-${Date.now()}`,
            userId,
            userEmail,
            operation: 'tagged',
            status: 'success',
            snapshotId,
            ipAddress,
            userAgent,
            timestamp: Date.now(),
            details: { tags },
        };
        await this.logAudit(userId, auditEntry);
        this.emit('snapshot-tagged', { snapshotId, tags });
    }
    /**
     * Compare two snapshots
     */
    async compareSnapshots(fromSnapshotId, toSnapshotId) {
        const fromSnap = this.snapshots.get(fromSnapshotId);
        const toSnap = this.snapshots.get(toSnapshotId);
        if (!fromSnap || !toSnap)
            return undefined;
        const fromFiles = new Set(fromSnap.files.map((f) => f.path));
        const toFiles = new Set(toSnap.files.map((f) => f.path));
        const filesAdded = Array.from(toFiles).filter((f) => !fromFiles.has(f));
        const filesDeleted = Array.from(fromFiles).filter((f) => !toFiles.has(f));
        return {
            fromVersion: fromSnap.version,
            toVersion: toSnap.version,
            filesAdded,
            filesDeleted,
            filesModified: [],
            layoutChanged: JSON.stringify(fromSnap.layout) !== JSON.stringify(toSnap.layout),
            debugConfigChanged: JSON.stringify(fromSnap.debug) !== JSON.stringify(toSnap.debug),
            extensionsAdded: toSnap.settings.extensions.filter((ext) => !fromSnap.settings.extensions.find((e) => e.id === ext.id)),
            extensionsRemoved: fromSnap.settings.extensions.filter((ext) => !toSnap.settings.extensions.find((e) => e.id === ext.id)),
        };
    }
    /**
     * Get audit log for user
     */
    async getAuditLog(userId, limit) {
        const log = this.auditLog.get(userId) || [];
        if (limit) {
            return log.slice(-limit);
        }
        return log;
    }
    /**
     * Get statistics
     */
    async getStatistics() {
        return { ...this.stats };
    }
    /**
     * Private: Log audit entry
     */
    async logAudit(userId, entry) {
        let log = this.auditLog.get(userId);
        if (!log) {
            log = [];
            this.auditLog.set(userId, log);
        }
        log.push(entry);
        // Keep only maxAuditLogSize entries
        if (log.length > this.config.maxAuditLogSize) {
            log.splice(0, log.length - this.config.maxAuditLogSize);
        }
        this.emit('audit-logged', { userId, entry });
    }
    /**
     * Private: Calculate snapshot size
     */
    calculateSnapshotSize(snapshot) {
        let size = 0;
        if (snapshot.files) {
            size += snapshot.files.reduce((acc, f) => acc + f.content.length, 0);
        }
        if (snapshot.terminals) {
            size += snapshot.terminals.reduce((acc, t) => acc + t.history.join('').length, 0);
        }
        size += JSON.stringify(snapshot.layout).length;
        size += JSON.stringify(snapshot.settings).length;
        return size;
    }
    /**
     * Private: Update statistics
     */
    updateStats() {
        this.stats.totalSnapshots = this.snapshots.size;
        // Calculate by version
        this.stats.snapshotsByVersion = {};
        for (const snap of this.snapshots.values()) {
            this.stats.snapshotsByVersion[snap.version] =
                (this.stats.snapshotsByVersion[snap.version] || 0) + 1;
        }
        // Calculate by user and workspace
        this.stats.snapshotsByUser = {};
        this.stats.snapshotsByWorkspace = {};
        let totalSize = 0;
        for (const userMeta of this.metadata.values()) {
            for (const meta of userMeta) {
                this.stats.snapshotsByUser[meta.userId] =
                    (this.stats.snapshotsByUser[meta.userId] || 0) + 1;
                this.stats.snapshotsByWorkspace[meta.workspaceId] =
                    (this.stats.snapshotsByWorkspace[meta.workspaceId] || 0) + 1;
                totalSize += meta.size;
            }
        }
        this.stats.totalStorageBytes = totalSize;
        this.stats.averageSnapshotSize =
            this.stats.totalSnapshots > 0 ? totalSize / this.stats.totalSnapshots : 0;
    }
    startAutoSnapshot() {
        this.autoSnapshotTimer = setInterval(() => {
            this.emit('auto-snapshot-interval');
        }, this.config.autoSnapshotInterval);
    }
    stopAutoSnapshot() {
        if (this.autoSnapshotTimer) {
            clearInterval(this.autoSnapshotTimer);
            this.autoSnapshotTimer = null;
        }
    }
    static getInstance(config) {
        if (!SnapshotService.instance) {
            SnapshotService.instance = new SnapshotService(config);
        }
        return SnapshotService.instance;
    }
}
//# sourceMappingURL=snapshot-service.js.map