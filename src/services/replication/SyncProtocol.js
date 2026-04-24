/**
 * Phase 12.2: CRDT Synchronization Protocol
 * Implements state-based and operation-based replication between regions
 * Supports gossip protocol, causal ordering, and eventual consistency
 */
import { VectorClock } from './VectorClock';
import * as crypto from 'crypto';
export class SyncProtocol {
    constructor(config) {
        this.operationLog = new Map();
        this.knownOperations = new Map(); // replicaId -> operationIds
        this.syncTimestamps = new Map(); // replicaId -> timestamp
        this.lastCompactionAt = 0;
        this.totalCompactions = 0;
        this.totalPrunedOperations = 0;
        this.config = config;
        this.vectorClock = new VectorClock(config.replicaId);
        this.logSize = config.operationLogMaxSize ?? 100000;
        this.logRetentionMs = config.operationLogRetentionMs ?? 7 * 24 * 60 * 60 * 1000;
    }
    /**
     * Send operation to other replicas
     * Prepares the operation with metadata for transmission
     */
    sendOperation(operation) {
        // Increment our clock for this operation
        this.vectorClock.tick();
        const fullOperation = {
            ...operation,
            replicaId: this.config.replicaId,
            vectorClock: this.vectorClock.get(),
            operationId: this.generateOperationId(operation),
        };
        // Log the operation
        this.operationLog.set(fullOperation.operationId, fullOperation);
        this.compactOperationLog();
        // Track known operations
        if (!this.knownOperations.has(this.config.replicaId)) {
            this.knownOperations.set(this.config.replicaId, new Set());
        }
        this.knownOperations
            .get(this.config.replicaId)
            .add(fullOperation.operationId);
        return this.createEnvelope(fullOperation);
    }
    /**
     * Receive operation from another replica
     * Updates vector clock and merges into operation log
     */
    receiveOperation(envelope) {
        const operation = envelope.data;
        // Validate envelope integrity
        if (!this.validateEnvelope(envelope) ||
            !this.validateClockSkew(operation)) {
            return { accepted: false, isNew: false, clockConflict: true };
        }
        // Check if operation is new
        const replicaOps = this.knownOperations.get(operation.replicaId);
        const isNew = !replicaOps || !replicaOps.has(operation.operationId);
        if (isNew) {
            // Update our vector clock to maintain causality
            this.vectorClock.update(operation.vectorClock);
            // Log the operation
            this.operationLog.set(operation.operationId, operation);
            this.compactOperationLog();
            // Track the operation
            if (!this.knownOperations.has(operation.replicaId)) {
                this.knownOperations.set(operation.replicaId, new Set());
            }
            this.knownOperations
                .get(operation.replicaId)
                .add(operation.operationId);
            return { accepted: true, isNew: true, clockConflict: false };
        }
        return { accepted: true, isNew: false, clockConflict: false };
    }
    /**
     * Build a sync request to send to another replica
     */
    buildSyncRequest(targetReplicaId, targetVectorClock) {
        const knownOps = this.knownOperations.get(targetReplicaId) || new Set();
        return {
            fromReplicaId: this.config.replicaId,
            toReplicaId: targetReplicaId,
            lastSeenVectorClock: targetVectorClock,
            knownOperationIds: knownOps,
            priority: 'normal',
        };
    }
    /**
     * Process a sync request and return response with needed changes
     */
    processSyncRequest(request) {
        const operations = [];
        const checksumIndex = new Map();
        // Find operations that the requester doesn't know about
        for (const [opId, operation] of this.operationLog) {
            if (!request.knownOperationIds.has(opId)) {
                // Check if operation is causally after the requester's known state
                const happenedAfter = VectorClock.happensBefore(request.lastSeenVectorClock, operation.vectorClock);
                if (happenedAfter) {
                    operations.push(operation);
                }
            }
            if (operations.length >= this.config.maxBatchSize) {
                break;
            }
        }
        // Build checksums for validation
        for (const op of operations) {
            checksumIndex.set(op.operationId, this.computeChecksum(op));
        }
        const hasMore = this.operationLog.size > operations.length;
        return {
            fromReplicaId: this.config.replicaId,
            toReplicaId: request.fromReplicaId,
            operations,
            vectorClock: this.vectorClock.get(),
            hasMore,
            checksumIndex,
        };
    }
    /**
     * Apply sync response from another replica
     */
    applySyncResponse(response) {
        let applied = 0;
        let rejected = 0;
        for (const operation of response.operations) {
            const result = this.receiveOperation(this.createEnvelope(operation));
            if (result.accepted && result.isNew) {
                applied++;
                // Verify checksum
                const expectedChecksum = response.checksumIndex.get(operation.operationId);
                const actualChecksum = this.computeChecksum(operation);
                if (expectedChecksum !== actualChecksum) {
                    console.warn(`Checksum mismatch for operation ${operation.operationId}`);
                    rejected++;
                }
            }
            else if (!result.accepted) {
                rejected++;
            }
        }
        // Update last sync timestamp
        this.syncTimestamps.set(response.fromReplicaId, Date.now());
        return { applied, rejected };
    }
    /**
     * Get current vector clock state
     */
    getVectorClock() {
        return this.vectorClock.get();
    }
    /**
     * Validate envelope signature and format
     */
    validateEnvelope(envelope) {
        // Verify checksum matches data
        if (envelope.data) {
            const computed = this.computeChecksum(envelope.data);
            if (computed !== envelope.checksum) {
                return false;
            }
        }
        // Verify version compatibility
        const [major, minor] = envelope.version.split('.').map(Number);
        if (major !== 1 || (minor ?? 0) > 0) {
            return false; // Only support v1.x for now
        }
        return true;
    }
    /**
     * Validate clock skew is within acceptable bounds
     */
    validateClockSkew(operation) {
        const maxSkew = this.config.maxClockSkewMs;
        const clockSkew = Math.abs(Date.now() - operation.timestamp);
        if (clockSkew > maxSkew) {
            console.warn(`Clock skew ${clockSkew}ms exceeds max ${maxSkew}ms for operation ${operation.operationId}`);
            return false;
        }
        return true;
    }
    /**
     * Create a replication envelope for an operation
     */
    createEnvelope(data) {
        const dataStr = JSON.stringify(data);
        const checksum = this.computeChecksum(data);
        return {
            id: this.generateOperationId(data),
            replicaId: this.config.replicaId,
            regionId: this.config.regionId,
            timestamp: Date.now(),
            vectorClock: this.vectorClock.get(),
            data,
            checksum,
            compression: dataStr.length > this.config.compressionThreshold
                ? 'gzip'
                : 'none',
            version: '1.0',
            priority: 'normal',
        };
    }
    /**
     * Compute checksum for data integrity
     */
    computeChecksum(data) {
        const hash = crypto.createHash('sha256');
        hash.update(JSON.stringify(data));
        return hash.digest('hex');
    }
    /**
     * Generate unique operation ID
     */
    generateOperationId(data) {
        const hash = crypto.createHash('sha256');
        hash.update(JSON.stringify({
            ...data,
            timestamp: Date.now(),
            random: Math.random(),
        }));
        return hash.digest('hex').slice(0, 16);
    }
    /**
     * Compact operation log to prevent unbounded growth.
     *
     * Performs two cleanup passes:
     * - Time-based GC: removes operations older than the retention window
     * - Size-based GC: evicts the oldest remaining entries if the log is still too large
     *
     * Returns a summary so operators can observe how much data was reclaimed.
     */
    compactOperationLog() {
        const now = Date.now();
        const cutoffTime = now - this.logRetentionMs;
        let expired = 0;
        let overflow = 0;
        for (const [operationId, operation] of this.operationLog.entries()) {
            if (operation.timestamp < cutoffTime) {
                this.operationLog.delete(operationId);
                this.pruneKnownOperation(operation.replicaId, operationId);
                expired++;
            }
        }
        if (this.operationLog.size > this.logSize) {
            const overflowCount = this.operationLog.size - this.logSize;
            let removed = 0;
            // Remove the oldest remaining entries first, preserving the newest history.
            for (const [operationId, operation] of this.operationLog.entries()) {
                if (removed >= overflowCount) {
                    break;
                }
                this.operationLog.delete(operationId);
                this.pruneKnownOperation(operation.replicaId, operationId);
                removed++;
            }
            overflow = removed;
        }
        const removed = expired + overflow;
        if (removed > 0) {
            this.lastCompactionAt = now;
            this.totalCompactions++;
            this.totalPrunedOperations += removed;
        }
        return {
            removed,
            expired,
            overflow,
            retained: this.operationLog.size,
        };
    }
    /**
     * Remove an operation ID from the per-replica known-operation index.
     */
    pruneKnownOperation(replicaId, operationId) {
        const knownOps = this.knownOperations.get(replicaId);
        if (!knownOps) {
            return;
        }
        knownOps.delete(operationId);
        if (knownOps.size === 0) {
            this.knownOperations.delete(replicaId);
        }
    }
    /**
     * Get sync statistics
     */
    getSyncStats() {
        return {
            knownReplicasCount: this.knownOperations.size,
            operationLogSize: this.operationLog.size,
            operationLogRetentionMs: this.logRetentionMs,
            operationLogMaxSize: this.logSize,
            lastCompactionAt: this.lastCompactionAt,
            totalCompactions: this.totalCompactions,
            totalPrunedOperations: this.totalPrunedOperations,
            lastSyncTimes: new Map(this.syncTimestamps),
        };
    }
    /**
     * Reset state (for testing/transitions)
     */
    reset() {
        this.vectorClock = new VectorClock(this.config.replicaId);
        this.operationLog.clear();
        this.knownOperations.clear();
        this.syncTimestamps.clear();
    }
}
//# sourceMappingURL=SyncProtocol.js.map