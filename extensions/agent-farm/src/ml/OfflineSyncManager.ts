/**
 * Offline Sync Manager
 * Manages offline operations and synchronization with central systems
 */

export type OperationType = 'create' | 'update' | 'delete' | 'query' | 'execute';
export type SyncStatus = 'pending' | 'synced' | 'failed' | 'conflict';

export interface OfflineOperation {
  id: string;
  nodeId: string;
  type: OperationType;
  resource: string;
  payload: any;
  timestamp: number;
  status: SyncStatus;
  retryCount: number;
  lastRetry?: number;
  error?: string;
  localVersion: number;
  remoteVersion?: number;
}

export interface SyncConflict {
  operationId: string;
  resource: string;
  localVersion: number;
  remoteVersion: number;
  resolution: 'local' | 'remote' | 'merge' | 'manual';
  resolvedAt?: number;
}

export interface SyncBatch {
  id: string;
  nodeId: string;
  operations: OfflineOperation[];
  createdAt: number;
  startedAt?: number;
  completedAt?: number;
  status: 'pending' | 'in-progress' | 'completed' | 'failed';
  conflicts: SyncConflict[];
}

export interface SyncStatistics {
  totalOperations: number;
  syncedOperations: number;
  pendingOperations: number;
  failedOperations: number;
  conflictedOperations: number;
  lastSyncTime?: number;
  nextSyncTime?: number;
  avgSyncTime: number;
}

export class OfflineSyncManager {
  private operations: Map<string, OfflineOperation> = new Map();
  private syncBatches: Map<string, SyncBatch> = new Map();
  private conflicts: Map<string, SyncConflict> = new Map();
  private operationQueue: string[] = [];
  private syncHistory: SyncBatch[] = [];
  private readonly maxRetries = 5;
  private readonly retryInterval = 5000; // milliseconds
  private readonly batchTimeout = 30000; // milliseconds

  constructor() {}

  /**
   * Record offline operation
   */
  recordOperation(
    nodeId: string,
    type: OperationType,
    resource: string,
    payload: any
  ): OfflineOperation {
    const operation: OfflineOperation = {
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
  getPendingOperations(nodeId: string): OfflineOperation[] {
    const pending: OfflineOperation[] = [];
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
  createSyncBatch(nodeId: string): SyncBatch {
    const pending = this.getPendingOperations(nodeId);
    const batch: SyncBatch = {
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
  startSyncBatch(batchId: string): boolean {
    const batch = this.syncBatches.get(batchId);
    if (!batch) return false;

    batch.status = 'in-progress';
    batch.startedAt = Date.now();
    return true;
  }

  /**
   * Record operation sync success
   */
  recordSyncSuccess(operationId: string, remoteVersion?: number): boolean {
    const operation = this.operations.get(operationId);
    if (!operation) return false;

    operation.status = 'synced';
    operation.remoteVersion = remoteVersion || operation.localVersion;
    return true;
  }

  /**
   * Record operation sync failure
   */
  recordSyncFailure(operationId: string, error: string): boolean {
    const operation = this.operations.get(operationId);
    if (!operation) return false;

    if (operation.retryCount < this.maxRetries) {
      operation.status = 'pending';
      operation.retryCount++;
      operation.lastRetry = Date.now();
      operation.error = error;
      return true;
    } else {
      operation.status = 'failed';
      operation.error = error;
      return false;
    }
  }

  /**
   * Record sync conflict
   */
  recordConflict(operationId: string, remoteVersion: number, resolution: 'local' | 'remote' | 'merge' | 'manual'): SyncConflict {
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

    const conflict: SyncConflict = {
      operationId,
      resource: operation.resource,
      localVersion: operation.localVersion,
      remoteVersion,
      resolution,
    };

    if (resolution === 'local') {
      operation.status = 'synced';
      operation.remoteVersion = remoteVersion;
    } else if (resolution === 'remote') {
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
  completeSyncBatch(batchId: string, success: boolean): SyncBatch | undefined {
    const batch = this.syncBatches.get(batchId);
    if (!batch) return undefined;

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
  getSyncStatistics(): SyncStatistics {
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
  getConflictResolutions(): Map<string, 'local' | 'remote' | 'merge'> {
    const resolutions = new Map<string, 'local' | 'remote' | 'merge'>();

    this.conflicts.forEach((conflict) => {
      const operation = this.operations.get(conflict.operationId);
      if (!operation) return;

      // Recommend based on operation type and timing
      if (operation.type === 'delete') {
        resolutions.set(conflict.operationId, 'local'); // prefer delete
      } else if (operation.type === 'create') {
        resolutions.set(conflict.operationId, 'local'); // prefer local new data
      } else if (operation.timestamp > (operation.lastRetry || 0)) {
        resolutions.set(conflict.operationId, 'local'); // prefer recent local changes
      } else {
        resolutions.set(conflict.operationId, 'remote'); // prefer remote for old ops
      }
    });

    return resolutions;
  }

  /**
   * Get sync queue status
   */
  getSyncQueueStatus(): {
    queueLength: number;
    oldestOperation?: { id: string; age: number };
    averageWaitTime: number;
  } {
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
  exportOperations(nodeId: string): any[] {
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
  importSyncResults(results: Array<{ id: string; success: boolean; remoteVersion?: number; error?: string }>): void {
    results.forEach((result) => {
      if (result.success) {
        this.recordSyncSuccess(result.id, result.remoteVersion);
      } else {
        this.recordSyncFailure(result.id, result.error || 'Unknown error');
      }
    });
  }
}

export default OfflineSyncManager;
