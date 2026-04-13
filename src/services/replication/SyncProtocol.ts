/**
 * Phase 12.2: CRDT Synchronization Protocol
 * Implements state-based and operation-based replication between regions
 * Supports gossip protocol, causal ordering, and eventual consistency
 */

import {
  CRDTOperation,
  ReplicationEnvelope,
  SyncRequest,
  SyncResponse,
  RegionReplicationConfig,
} from './CRDTTypes';
import { VectorClock, VectorClockValue } from './VectorClock';
import * as crypto from 'crypto';

export interface SyncProtocolConfig {
  replicaId: string;
  regionId: string;
  maxBatchSize: number;
  syncIntervalMs: number;
  maxClockSkewMs: number;
  enableCompression: boolean;
  compressionThreshold: number; // Bytes
}

export class SyncProtocol {
  private config: SyncProtocolConfig;
  private vectorClock: VectorClock;
  private operationLog: Map<string, CRDTOperation> = new Map();
  private knownOperations: Map<string, Set<string>> = new Map(); // replicaId -> operationIds
  private syncTimestamps: Map<string, number> = new Map(); // replicaId -> timestamp
  private readonly logSize = 100000;

  constructor(config: SyncProtocolConfig) {
    this.config = config;
    this.vectorClock = new VectorClock(config.replicaId);
  }

  /**
   * Send operation to other replicas
   * Prepares the operation with metadata for transmission
   */
  sendOperation(
    operation: Omit<CRDTOperation, 'replicaId' | 'vectorClock' | 'operationId'>
  ): ReplicationEnvelope<CRDTOperation> {
    // Increment our clock for this operation
    this.vectorClock.tick();

    const fullOperation: CRDTOperation = {
      ...operation,
      replicaId: this.config.replicaId,
      vectorClock: this.vectorClock.get(),
      operationId: this.generateOperationId(operation),
    };

    // Log the operation
    this.operationLog.set(fullOperation.operationId, fullOperation);
    this.trimOperationLog();

    // Track known operations
    if (!this.knownOperations.has(this.config.replicaId)) {
      this.knownOperations.set(
        this.config.replicaId,
        new Set()
      );
    }
    this.knownOperations
      .get(this.config.replicaId)!
      .add(fullOperation.operationId);

    return this.createEnvelope(fullOperation);
  }

  /**
   * Receive operation from another replica
   * Updates vector clock and merges into operation log
   */
  receiveOperation(envelope: ReplicationEnvelope<CRDTOperation>): {
    accepted: boolean;
    isNew: boolean;
    clockConflict: boolean;
  } {
    const operation = envelope.data;

    // Validate envelope integrity
    if (
      !this.validateEnvelope(envelope) ||
      !this.validateClockSkew(operation)
    ) {
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
      this.trimOperationLog();

      // Track the operation
      if (!this.knownOperations.has(operation.replicaId)) {
        this.knownOperations.set(operation.replicaId, new Set());
      }
      this.knownOperations
        .get(operation.replicaId)!
        .add(operation.operationId);

      return { accepted: true, isNew: true, clockConflict: false };
    }

    return { accepted: true, isNew: false, clockConflict: false };
  }

  /**
   * Build a sync request to send to another replica
   */
  buildSyncRequest(
    targetReplicaId: string,
    targetVectorClock: VectorClockValue
  ): SyncRequest {
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
  processSyncRequest(request: SyncRequest): SyncResponse {
    const operations: CRDTOperation[] = [];
    const checksumIndex = new Map<string, string>();

    // Find operations that the requester doesn't know about
    for (const [opId, operation] of this.operationLog) {
      if (!request.knownOperationIds.has(opId)) {
        // Check if operation is causally after the requester's known state
        const happenedAfter = VectorClock.happensBefore(
          request.lastSeenVectorClock,
          operation.vectorClock
        );

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
      checksumIndex.set(
        op.operationId,
        this.computeChecksum(op)
      );
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
  applySyncResponse(response: SyncResponse): {
    applied: number;
    rejected: number;
  } {
    let applied = 0;
    let rejected = 0;

    for (const operation of response.operations) {
      const result = this.receiveOperation(
        this.createEnvelope(operation)
      );

      if (result.accepted && result.isNew) {
        applied++;
        // Verify checksum
        const expectedChecksum = response.checksumIndex.get(
          operation.operationId
        );
        const actualChecksum = this.computeChecksum(operation);

        if (expectedChecksum !== actualChecksum) {
          console.warn(
            `Checksum mismatch for operation ${operation.operationId}`
          );
          rejected++;
        }
      } else if (!result.accepted) {
        rejected++;
      }
    }

    // Update last sync timestamp
    this.syncTimestamps.set(
      response.fromReplicaId,
      Date.now()
    );

    return { applied, rejected };
  }

  /**
   * Get current vector clock state
   */
  getVectorClock(): VectorClockValue {
    return this.vectorClock.get();
  }

  /**
   * Validate envelope signature and format
   */
  private validateEnvelope<T>(envelope: ReplicationEnvelope<T>): boolean {
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
  private validateClockSkew(operation: CRDTOperation): boolean {
    const maxSkew = this.config.maxClockSkewMs;
    const clockSkew = Math.abs(Date.now() - operation.timestamp);

    if (clockSkew > maxSkew) {
      console.warn(
        `Clock skew ${clockSkew}ms exceeds max ${maxSkew}ms for operation ${operation.operationId}`
      );
      return false;
    }

    return true;
  }

  /**
   * Create a replication envelope for an operation
   */
  private createEnvelope<T>(data: T): ReplicationEnvelope<T> {
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
      compression:
        dataStr.length > this.config.compressionThreshold
          ? 'gzip'
          : 'none',
      version: '1.0',
      priority: 'normal',
    };
  }

  /**
   * Compute checksum for data integrity
   */
  private computeChecksum(data: any): string {
    const hash = crypto.createHash('sha256');
    hash.update(JSON.stringify(data));
    return hash.digest('hex');
  }

  /**
   * Generate unique operation ID
   */
  private generateOperationId(data: any): string {
    const hash = crypto.createHash('sha256');
    hash.update(
      JSON.stringify({
        ...data,
        timestamp: Date.now(),
        random: Math.random(),
      })
    );
    return hash.digest('hex').slice(0, 16);
  }

  /**
   * Trim operation log to prevent unbounded growth
   */
  private trimOperationLog(): void {
    if (this.operationLog.size > this.logSize) {
      // Remove oldest operations (keep order by iterating in insertion order)
      let removed = 0;
      for (const [opId] of this.operationLog) {
        if (removed < this.logSize * 0.1) {
          // Remove oldest 10%
          this.operationLog.delete(opId);
          removed++;
        } else {
          break;
        }
      }
    }
  }

  /**
   * Get sync statistics
   */
  getSyncStats(): {
    knownReplicasCount: number;
    operationLogSize: number;
    lastSyncTimes: Map<string, number>;
  } {
    return {
      knownReplicasCount: this.knownOperations.size,
      operationLogSize: this.operationLog.size,
      lastSyncTimes: new Map(this.syncTimestamps),
    };
  }

  /**
   * Reset state (for testing/transitions)
   */
  reset(): void {
    this.vectorClock = new VectorClock(this.config.replicaId);
    this.operationLog.clear();
    this.knownOperations.clear();
    this.syncTimestamps.clear();
  }
}
