#!/usr/bin/env node
// @file        apps/backend/src/services/crdt/delta-sync-service.ts
// @module      services/crdt
// @description Selective delta sync with state vectors for O(change) not O(doc) synchronization
//
import { EventEmitter } from 'events';
import { createHash } from 'crypto';
/**
 * Selective Delta Sync Service
 * Uses state vectors to sync only O(changes) not O(document)
 *
 * Algorithm:
 * 1. Each client maintains a state vector: {clientId -> clock}
 * 2. When syncing, remote sends their state vector
 * 3. Local computes delta as: ops where (clientId, clock) not in remote vector
 * 4. Send only delta, not entire document
 * 5. Remote applies delta, updates their state vector
 *
 * Complexity:
 * - Traditional sync: O(document_size)
 * - Delta sync: O(changes_since_last_sync)
 * - With state vectors: O(num_clients) space per document
 */
export class DeltaSyncService extends EventEmitter {
    constructor(logger) {
        super();
        this.logger = logger;
        // Document ID -> all operations
        this.documentOps = new Map();
        // Document ID -> state vector (latest clock per client)
        this.stateVectors = new Map();
        // Document ID -> content checksum
        this.contentChecksums = new Map();
        // Statistics for monitoring
        this.stats = {
            totalSyncs: 0,
            totalOperations: 0,
            avgDeltaSize: 0,
            compressionRatio: 0.0, // (delta_size / full_doc_size)
        };
        // Cache for performance - keyed by docId:remoteVector
        this.deltaCache = new Map();
        // Track which cache keys belong to each document for invalidation
        this.docCacheKeys = new Map();
    }
    /**
     * Get or create singleton instance
     */
    static getInstance(logger) {
        if (!this.instances.has('default')) {
            this.instances.set('default', new DeltaSyncService(logger));
        }
        return this.instances.get('default');
    }
    /**
     * Initialize document with initial content and operations
     */
    initializeDocument(docId, initialOps, initialContent) {
        if (this.documentOps.has(docId)) {
            throw new Error(`Document ${docId} already initialized`);
        }
        this.documentOps.set(docId, [...initialOps]);
        // Build state vector from operations
        const stateVector = {};
        for (const op of initialOps) {
            stateVector[op.clientId] = Math.max(stateVector[op.clientId] || 0, op.clock);
        }
        this.stateVectors.set(docId, stateVector);
        // Compute content checksum
        this.contentChecksums.set(docId, this.computeChecksum(initialContent));
        this.emit('document-initialized', {
            docId,
            opsCount: initialOps.length,
            stateVector,
        });
    }
    /**
     * Add operation to document
     * Updates state vector and content checksum
     */
    addOperation(docId, operation, newContent) {
        if (!this.documentOps.has(docId)) {
            throw new Error(`Document ${docId} not initialized`);
        }
        const ops = this.documentOps.get(docId);
        ops.push(operation);
        // Update state vector
        const stateVector = this.stateVectors.get(docId);
        stateVector[operation.clientId] = Math.max(stateVector[operation.clientId] || 0, operation.clock);
        // Update checksum
        this.contentChecksums.set(docId, this.computeChecksum(newContent));
        // Invalidate ALL cache entries for this document
        const cacheKeys = this.docCacheKeys.get(docId);
        if (cacheKeys) {
            for (const cacheKey of cacheKeys) {
                this.deltaCache.delete(cacheKey);
            }
            this.docCacheKeys.delete(docId);
        }
        this.emit('operation-added', {
            docId,
            clientId: operation.clientId,
            clock: operation.clock,
        });
    }
    /**
     * Compute delta between remote state and local state
     * Returns only operations not seen in remote vector
     *
     * Time complexity: O(changes) not O(document)
     * Only includes operations where (clientId, clock) not in remoteVector
     */
    computeDelta(docId, remoteVector) {
        if (!this.documentOps.has(docId)) {
            throw new Error(`Document ${docId} not found`);
        }
        // Check cache first
        const cacheKey = `${docId}:${JSON.stringify(remoteVector)}`;
        if (this.deltaCache.has(cacheKey)) {
            return this.deltaCache.get(cacheKey);
        }
        const ops = this.documentOps.get(docId);
        const localVector = this.stateVectors.get(docId);
        const content = this.contentChecksums.get(docId);
        // Filter operations not seen in remote vector
        const deltaOps = [];
        for (const op of ops) {
            const remoteClock = remoteVector[op.clientId] || 0;
            if (op.clock > remoteClock) {
                deltaOps.push(op);
            }
        }
        const delta = {
            from: remoteVector,
            to: { ...localVector },
            operations: deltaOps,
            contentChecksum: content,
        };
        // Cache delta
        this.deltaCache.set(cacheKey, delta);
        // Track cache keys for this document
        if (!this.docCacheKeys.has(docId)) {
            this.docCacheKeys.set(docId, new Set());
        }
        this.docCacheKeys.get(docId).add(cacheKey);
        return delta;
    }
    /**
     * Handle sync request from remote peer
     * Compute and return delta to catch remote up
     */
    sync(request, currentContent) {
        const delta = this.computeDelta(request.docId, request.remoteVector);
        const response = {
            clientId: request.clientId,
            delta,
            size: JSON.stringify(delta).length,
            timestamp: Date.now(),
        };
        // Update statistics
        this.stats.totalSyncs++;
        this.stats.totalOperations += delta.operations.length;
        // Track compression ratio (delta vs full doc)
        if (currentContent.length > 0) {
            this.stats.compressionRatio =
                response.size / Math.max(1, currentContent.length);
        }
        // Update average delta size
        this.stats.avgDeltaSize = Math.round(this.stats.totalOperations / Math.max(1, this.stats.totalSyncs));
        this.emit('sync-completed', {
            clientId: request.clientId,
            opsInDelta: delta.operations.length,
            size: response.size,
        });
        return response;
    }
    /**
     * Merge incoming delta into local state
     * Apply operations and update state vector
     */
    mergeDelta(docId, delta, newContent) {
        if (!this.documentOps.has(docId)) {
            throw new Error(`Document ${docId} not found`);
        }
        // Verify checksum matches
        const localChecksum = this.contentChecksums.get(docId);
        if (localChecksum !== delta.contentChecksum) {
            throw new Error(`Content checksum mismatch for ${docId}: local=${localChecksum}, delta=${delta.contentChecksum}`);
        }
        const ops = this.documentOps.get(docId);
        const stateVector = this.stateVectors.get(docId);
        // Add operations from delta
        for (const op of delta.operations) {
            // Skip if already have this operation
            if ((stateVector[op.clientId] || 0) >= op.clock) {
                continue;
            }
            ops.push(op);
            stateVector[op.clientId] = op.clock;
        }
        // Update checksum
        this.contentChecksums.set(docId, this.computeChecksum(newContent));
        // Invalidate ALL cache entries for this document
        const cacheKeys = this.docCacheKeys.get(docId);
        if (cacheKeys) {
            for (const cacheKey of cacheKeys) {
                this.deltaCache.delete(cacheKey);
            }
            this.docCacheKeys.delete(docId);
        }
        this.emit('delta-merged', {
            docId,
            opsApplied: delta.operations.length,
            newStateVector: stateVector,
        });
    }
    /**
     * Get current state vector for document
     * Used by peers to know what they have
     */
    getStateVector(docId) {
        if (!this.documentOps.has(docId)) {
            throw new Error(`Document ${docId} not found`);
        }
        return { ...this.stateVectors.get(docId) };
    }
    /**
     * Get statistics about sync activity
     */
    getStats() {
        return {
            ...this.stats,
            avgDeltaSize: this.stats.avgDeltaSize,
            compressionRatio: this.stats.compressionRatio.toFixed(3),
            compressionPercent: `${((1 - this.stats.compressionRatio) * 100).toFixed(1)}%`,
        };
    }
    /**
     * Compute checksum of content
     * Used to verify consistency
     */
    computeChecksum(content) {
        return createHash('sha256').update(content).digest('hex').substring(0, 16);
    }
    /**
     * Get number of clients that have contributed to document
     */
    getClientCount(docId) {
        if (!this.documentOps.has(docId)) {
            return 0;
        }
        const stateVector = this.stateVectors.get(docId);
        return Object.keys(stateVector).length;
    }
    /**
     * Get all operations for document
     */
    getOperations(docId) {
        return [...(this.documentOps.get(docId) || [])];
    }
    /**
     * Clear all state for testing
     */
    reset() {
        this.documentOps.clear();
        this.stateVectors.clear();
        this.contentChecksums.clear();
        this.deltaCache.clear();
        this.stats = {
            totalSyncs: 0,
            totalOperations: 0,
            avgDeltaSize: 0,
            compressionRatio: 0.0,
        };
    }
    /**
     * Shutdown service
     */
    shutdown() {
        this.reset();
        this.removeAllListeners();
    }
    /**
     * Clear instances for testing
     */
    static clearInstances() {
        this.instances.forEach((instance) => instance.shutdown());
        this.instances.clear();
    }
}
DeltaSyncService.instances = new Map();
export default DeltaSyncService;
//# sourceMappingURL=delta-sync-service.js.map