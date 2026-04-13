/**
 * Phase 12.2: CRDT Sync Protocol Implementation
 * Implements CRDT (Conflict-free Replicated Data Types) for distributed data consistency
 */

import crypto from "crypto";
import {
  ReplicationOperation,
  VectorClock,
  ReplicationMessage,
  CRDTState,
  ConflictDetection,
  NodeId,
  OperationType,
} from "./types";

/**
 * CRDTSyncProtocol
 * Implements state-based CRDT with vector clock causal ordering
 */
export class CRDTSyncProtocol {
  private nodeId: NodeId;
  private vectorClock: VectorClock;
  private operationLog: Map<string, ReplicationOperation>;
  private resourceStates: Map<string, CRDTState>;

  constructor(nodeId: NodeId) {
    this.nodeId = nodeId;
    this.vectorClock = { [nodeId]: 0 };
    this.operationLog = new Map();
    this.resourceStates = new Map();
  }

  /**
   * Increment local vector clock
   */
  private incrementClock(): void {
    this.vectorClock[this.nodeId] = (this.vectorClock[this.nodeId] || 0) + 1;
  }

  /**
   * Merge remote vector clock
   */
  private mergeVectorClock(remoteClock: VectorClock): void {
    for (const [nodeId, timestamp] of Object.entries(remoteClock)) {
      this.vectorClock[nodeId] = Math.max(
        this.vectorClock[nodeId] || 0,
        timestamp
      );
    }
    this.incrementClock();
  }

  /**
   * Generate operation ID
   */
  private generateOperationId(): string {
    return `${this.nodeId}:${Date.now()}:${crypto
      .randomBytes(8)
      .toString("hex")}`;
  }

  /**
   * Generate SHA256 hash for operation verification
   */
  private hashOperation(operation: Omit<ReplicationOperation, "hash">): string {
    const serialized = JSON.stringify({
      ...operation,
      vectorClock: JSON.stringify(operation.vectorClock),
    });
    return crypto.createHash("sha256").update(serialized).digest("hex");
  }

  /**
   * Create a new replication operation
   */
  createOperation<T>(
    operationType: OperationType,
    resourceType: string,
    resourceId: string,
    payload: T
  ): ReplicationOperation<T> {
    this.incrementClock();

    const operation: ReplicationOperation<T> = {
      id: this.generateOperationId(),
      timestamp: Date.now(),
      nodeId: this.nodeId,
      vectorClock: { ...this.vectorClock },
      operationType,
      resourceType,
      resourceId,
      payload,
      hash: "", // Will be set after hash calculation
    };

    operation.hash = this.hashOperation(operation);
    this.operationLog.set(operation.id, operation);

    return operation;
  }

  /**
   * Apply operation locally with causal consistency
   */
  applyOperation(operation: ReplicationOperation): void {
    // Verify operation integrity
    const expectedHash = this.hashOperation(operation);
    if (operation.hash !== expectedHash) {
      throw new Error(
        `Operation integrity check failed for ${operation.id}`
      );
    }

    // Merge remote vector clock
    this.mergeVectorClock(operation.vectorClock);

    // Check for conflicts
    const conflict = this.detectConflict(operation);
    if (conflict.hasConflict) {
      this.handleConflict(operation, conflict);
      return;
    }

    // Apply operation
    this.applyToState(operation);
    this.operationLog.set(operation.id, operation);
  }

  /**
   * Detect conflicts with existing state
   */
  private detectConflict(
    operation: ReplicationOperation
  ): ConflictDetection {
    const existingState = this.resourceStates.get(operation.resourceId);
    if (!existingState) {
      return {
        hasConflict: false,
        conflictingOperations: [],
        conflictType: null,
        resolution: "automatic",
      };
    }

    // Check for concurrent updates (same resource, different origins)
    const concurrentOps = Array.from(this.operationLog.values()).filter(
      (op) =>
        op.resourceId === operation.resourceId &&
        op.id !== operation.id &&
        this.isConcurrent(op.vectorClock, operation.vectorClock)
    );

    if (concurrentOps.length > 0) {
      // Check for delete-write conflicts
      const hasDelete = concurrentOps.some(
        (op) => op.operationType === OperationType.DELETE
      );
      const isWrite =
        operation.operationType === OperationType.UPDATE ||
        operation.operationType === OperationType.CREATE;

      if (hasDelete && isWrite) {
        return {
          hasConflict: true,
          conflictingOperations: [operation, ...concurrentOps],
          conflictType: "delete_write",
          resolution: "automatic", // Delete-write conflicts are resolvable
        };
      }

      // Concurrent updates on same field
      const fieldCollision = this.checkFieldCollision(operation, concurrentOps);
      if (fieldCollision) {
        return {
          hasConflict: true,
          conflictingOperations: [operation, ...concurrentOps],
          conflictType: "field_collision",
          resolution: "manual", // Requires merge strategy
        };
      }

      return {
        hasConflict: true,
        conflictingOperations: [operation, ...concurrentOps],
        conflictType: "concurrent_update",
        resolution: "automatic",
      };
    }

    return {
      hasConflict: false,
      conflictingOperations: [],
      conflictType: null,
      resolution: "automatic",
    };
  }

  /**
   * Check if two vector clocks are concurrent (neither happened-before)
   */
  private isConcurrent(clock1: VectorClock, clock2: VectorClock): boolean {
    let hasGreater1 = false;
    let hasGreater2 = false;

    const allNodes = new Set([...Object.keys(clock1), ...Object.keys(clock2)]);
    for (const node of allNodes) {
      const ts1 = clock1[node] || 0;
      const ts2 = clock2[node] || 0;
      if (ts1 > ts2) hasGreater1 = true;
      if (ts2 > ts1) hasGreater2 = true;
    }

    return hasGreater1 && hasGreater2;
  }

  /**
   * Check for field-level collision
   */
  private checkFieldCollision(
    operation: ReplicationOperation,
    concurrentOps: ReplicationOperation[]
  ): boolean {
    if (typeof operation.payload !== "object" || !operation.payload) {
      return false;
    }

    const newFields = Object.keys(operation.payload);
    for (const concurrentOp of concurrentOps) {
      if (
        typeof concurrentOp.payload === "object" &&
        concurrentOp.payload
      ) {
        const concurrentFields = Object.keys(concurrentOp.payload);
        const intersection = newFields.filter((f) =>
          concurrentFields.includes(f)
        );
        if (intersection.length > 0) {
          return true;
        }
      }
    }
    return false;
  }

  /**
   * Handle detected conflicts
   */
  private handleConflict(
    operation: ReplicationOperation,
    conflict: ConflictDetection
  ): void {
    // For delete-write conflicts: recreate wins (revive deleted resource)
    if (conflict.conflictType === "delete_write") {
      this.applyToState(operation);
      return;
    }

    // For concurrent updates: last-write-wins with timestamp
    const existingState = this.resourceStates.get(operation.resourceId);
    if (
      !existingState ||
      operation.timestamp >= (existingState.causality.timestamp || 0)
    ) {
      this.applyToState(operation);
    }
  }

  /**
   * Apply operation to CRDT state
   */
  private applyToState(operation: ReplicationOperation): void {
    const resourceId = operation.resourceId;
    let state = this.resourceStates.get(resourceId);

    if (!state) {
      state = {
        resourceId,
        resourceType: operation.resourceType,
        currentValue: operation.payload,
        tombstone: null,
        versions: new Map(),
        causality: {
          origin: operation.nodeId,
          timestamp: operation.timestamp,
          predecessors: [],
        },
      };
    }

    const versionKey = `${operation.nodeId}:${operation.timestamp}`;

    switch (operation.operationType) {
      case OperationType.CREATE:
      case OperationType.UPDATE:
        state.currentValue = operation.payload;
        state.versions.set(versionKey, {
          value: operation.payload,
          clock: operation.vectorClock,
        });
        state.tombstone = null;
        state.causality = {
          origin: operation.nodeId,
          timestamp: operation.timestamp,
          predecessors: this.findPredecessors(operation),
        };
        break;

      case OperationType.DELETE:
        state.tombstone = operation.vectorClock;
        break;

      case OperationType.MERGE:
        // Merge is handled by merging versions
        state.currentValue = this.mergeVersions(state.versions);
        break;
    }

    this.resourceStates.set(resourceId, state);
  }

  /**
   * Find predecessor operations (causal history)
   */
  private findPredecessors(operation: ReplicationOperation): string[] {
    return Array.from(this.operationLog.values())
      .filter(
        (op) =>
          op.resourceId === operation.resourceId &&
          this.happensBefore(op.vectorClock, operation.vectorClock)
      )
      .map((op) => op.id);
  }

  /**
   * Check if clock1 happened before clock2
   */
  private happensBefore(clock1: VectorClock, clock2: VectorClock): boolean {
    let hasLess = false;
    const allNodes = new Set([...Object.keys(clock1), ...Object.keys(clock2)]);

    for (const node of allNodes) {
      const ts1 = clock1[node] || 0;
      const ts2 = clock2[node] || 0;
      if (ts1 > ts2) return false;
      if (ts1 < ts2) hasLess = true;
    }
    return hasLess;
  }

  /**
   * Merge multiple versions for conflict resolution
   */
  private mergeVersions(
    versions: Map<string, { value: any; clock: VectorClock }>
  ): any {
    if (versions.size === 0) return null;
    if (versions.size === 1) return Array.from(versions.values())[0].value;

    // Merge strategy: deep merge for objects, last-write-wins for primitives
    const values = Array.from(versions.values());
    let merged: any = values[0].value;

    for (let i = 1; i < values.length; i++) {
      merged = this.deepMerge(merged, values[i].value);
    }

    return merged;
  }

  /**
   * Deep merge for objects
   */
  private deepMerge(obj1: any, obj2: any): any {
    if (typeof obj1 !== "object" || typeof obj2 !== "object") {
      return obj2; // Last-write-wins for primitives
    }

    const merged = { ...obj1 };
    for (const key of Object.keys(obj2)) {
      if (typeof obj1[key] === "object" && typeof obj2[key] === "object") {
        merged[key] = this.deepMerge(obj1[key], obj2[key]);
      } else {
        merged[key] = obj2[key]; // obj2 wins
      }
    }
    return merged;
  }

  /**
   * Prepare replication message for transmission
   */
  createReplicationMessage(
    receiverId: NodeId,
    operations: ReplicationOperation[]
  ): ReplicationMessage {
    const messagePayload = {
      operations,
      vectorClock: this.vectorClock,
    };
    const checksum = crypto
      .createHash("sha256")
      .update(JSON.stringify(messagePayload))
      .digest("hex");

    return {
      id: this.generateOperationId(),
      senderId: this.nodeId,
      receiverId,
      messageType: "operation_batch",
      vectorClock: { ...this.vectorClock },
      operations,
      timestamp: Date.now(),
      checksum,
    };
  }

  /**
   * Get current CRDT state
   */
  getState(resourceId: string): CRDTState | undefined {
    return this.resourceStates.get(resourceId);
  }

  /**
   * Get all states
   */
  getAllStates(): Map<string, CRDTState> {
    return new Map(this.resourceStates);
  }

  /**
   * Get vector clock
   */
  getVectorClock(): VectorClock {
    return { ...this.vectorClock };
  }

  /**
   * Compact operation log (remove applied operations)
   */
  compactLog(retainDays: number = 7): void {
    const cutoffTime = Date.now() - retainDays * 24 * 60 * 60 * 1000;
    for (const [opId, op] of this.operationLog.entries()) {
      if (op.timestamp < cutoffTime) {
        this.operationLog.delete(opId);
      }
    }
  }
}

export default CRDTSyncProtocol;
