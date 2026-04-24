/**
 * Offline Sync Manager
 * Manages offline operations and synchronization with central systems
 */
export class OfflineSyncManager {
    constructor() {
        this.operations = new Map();
        this.syncBatches = new Map();
        this.conflicts = new Map();
        this.operationQueue = [];
        this.syncHistory = [];
        this.maxRetries = 5;
        this.retryInterval = 5000; // milliseconds
        this.batchTimeout = 30000; // milliseconds
    }
    /**
     * Record offline operation
     */
    recordOperation(nodeId, type, resource, payload) {
        const operation = {
            id: `op-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
            nodeId,
            type,
            resource,
            payload,
            timestamp: Date.now(),
            status: 'pending',
            retryCount: 0,
            localVersion: 1,
        };
        this.operations.set(operation.id, operation);
        this.operationQueue.push(operation.id);
        return operation;
    }
    /**
     * Get pending operations for a node
     */
    getPendingOperations(nodeId) {
        const pending = [];
        this.operations.forEach((op) => {
            if (op.nodeId === nodeId && op.status === 'pending') {
                pending.push(op);
            }
        });
        return pending.sort((a, b) => a.timestamp - b.timestamp);
    }
    /**
     * Create sync batch
     */
    createSyncBatch(nodeId) {
        const pending = this.getPendingOperations(nodeId);
        const batch = {
            id: `batch-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
            nodeId,
            operations: pending,
            createdAt: Date.now(),
            status: 'pending',
            conflicts: [],
        };
        this.syncBatches.set(batch.id, batch);
        return batch;
    }
    /**
     * Start sync batch
     */
    startSyncBatch(batchId) {
        const batch = this.syncBatches.get(batchId);
        if (!batch)
            return false;
        batch.status = 'in-progress';
        batch.startedAt = Date.now();
        return true;
    }
    /**
     * Record operation sync success
     */
    recordSyncSuccess(operationId, remoteVersion) {
        const operation = this.operations.get(operationId);
        if (!operation)
            return false;
        operation.status = 'synced';
        operation.remoteVersion = remoteVersion || operation.localVersion;
        return true;
    }
    /**
     * Record operation sync failure
     */
    recordSyncFailure(operationId, error) {
        const operation = this.operations.get(operationId);
        if (!operation)
            return false;
        if (operation.retryCount < this.maxRetries) {
            operation.status = 'pending';
            operation.retryCount++;
            operation.lastRetry = Date.now();
            operation.error = error;
            return true;
        }
        else {
            operation.status = 'failed';
            operation.error = error;
            return false;
        }
    }
    /**
     * Record sync conflict
     */
    recordConflict(operationId, remoteVersion, resolution) {
        const operation = this.operations.get(operationId);
        if (!operation) {
            return {
                operationId,
                resource: '',
                localVersion: 0,
                remoteVersion,
                resolution,
            };
        }
        const conflict = {
            operationId,
            resource: operation.resource,
            localVersion: operation.localVersion,
            remoteVersion,
            resolution,
        };
        if (resolution === 'local') {
            operation.status = 'synced';
            operation.remoteVersion = remoteVersion;
        }
        else if (resolution === 'remote') {
            operation.status = 'synced';
            operation.localVersion = remoteVersion;
            operation.remoteVersion = remoteVersion;
        }
        this.conflicts.set(conflict.operationId, conflict);
        return conflict;
    }
    /**
     * Complete sync batch
     */
    completeSyncBatch(batchId, success) {
        const batch = this.syncBatches.get(batchId);
        if (!batch)
            return undefined;
        batch.status = success ? 'completed' : 'failed';
        batch.completedAt = Date.now();
        if (success) {
            this.syncHistory.push(batch);
            if (this.syncHistory.length > 100) {
                this.syncHistory.shift();
            }
        }
        return batch;
    }
    /**
     * Get sync statistics
     */
    getSyncStatistics() {
        const allOps = Array.from(this.operations.values());
        const syncedCount = allOps.filter((o) => o.status === 'synced').length;
        const pendingCount = allOps.filter((o) => o.status === 'pending').length;
        const failedCount = allOps.filter((o) => o.status === 'failed').length;
        const conflictCount = this.conflicts.size;
        // Calculate average sync time
        let totalSyncTime = 0;
        let completedBatches = 0;
        this.syncHistory.forEach((batch) => {
            if (batch.completedAt && batch.startedAt) {
                totalSyncTime += batch.completedAt - batch.startedAt;
                completedBatches++;
            }
        });
        const lastSyncBatch = this.syncHistory[this.syncHistory.length - 1];
        const lastSyncTime = lastSyncBatch?.completedAt;
        return {
            totalOperations: allOps.length,
            syncedOperations: syncedCount,
            pendingOperations: pendingCount,
            failedOperations: failedCount,
            conflictedOperations: conflictCount,
            lastSyncTime,
            nextSyncTime: lastSyncTime ? lastSyncTime + this.retryInterval : undefined,
            avgSyncTime: completedBatches > 0 ? totalSyncTime / completedBatches : 0,
        };
    }
    /**
     * Get conflict resolution recommendations
     */
    getConflictResolutions() {
        const resolutions = new Map();
        this.conflicts.forEach((conflict) => {
            const operation = this.operations.get(conflict.operationId);
            if (!operation)
                return;
            // Recommend based on operation type and timing
            if (operation.type === 'delete') {
                resolutions.set(conflict.operationId, 'local'); // prefer delete
            }
            else if (operation.type === 'create') {
                resolutions.set(conflict.operationId, 'local'); // prefer local new data
            }
            else if (operation.timestamp > (operation.lastRetry || 0)) {
                resolutions.set(conflict.operationId, 'local'); // prefer recent local changes
            }
            else {
                resolutions.set(conflict.operationId, 'remote'); // prefer remote for old ops
            }
        });
        return resolutions;
    }
    /**
     * Get sync queue status
     */
    getSyncQueueStatus() {
        const pending = Array.from(this.operations.values()).filter((o) => o.status === 'pending');
        if (pending.length === 0) {
            return { queueLength: 0, averageWaitTime: 0 };
        }
        const now = Date.now();
        const ages = pending.map((o) => now - o.timestamp);
        const avgWaitTime = ages.length > 0 ? ages.reduce((a, b) => a + b) / ages.length : 0;
        const oldestOp = pending.reduce((oldest, op) => (op.timestamp < oldest.timestamp ? op : oldest));
        return {
            queueLength: pending.length,
            oldestOperation: { id: oldestOp.id, age: now - oldestOp.timestamp },
            averageWaitTime: avgWaitTime,
        };
    }
    /**
     * Export operations for sync
     */
    exportOperations(nodeId) {
        const pending = this.getPendingOperations(nodeId);
        return pending.map((op) => ({
            id: op.id,
            type: op.type,
            resource: op.resource,
            payload: op.payload,
            localVersion: op.localVersion,
        }));
    }
    /**
     * Import sync results
     */
    importSyncResults(results) {
        results.forEach((result) => {
            if (result.success) {
                this.recordSyncSuccess(result.id, result.remoteVersion);
            }
            else {
                this.recordSyncFailure(result.id, result.error || 'Unknown error');
            }
        });
    }
}
export default OfflineSyncManager;
//# sourceMappingURL=OfflineSyncManager.js.map