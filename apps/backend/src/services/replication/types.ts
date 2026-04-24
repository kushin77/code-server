/**
 * Phase 12.2: Data Replication & Sync Layer
 * Type definitions for CRDT-based replication protocol
 */

/**
 * Unique identifier for replication nodes (servers/clusters)
 */
export type NodeId = string & { readonly __brand: "NodeId" };

/**
 * Vector clock for causal ordering of events
 */
export interface VectorClock {
  [nodeId: string]: number;
}

/**
 * Operation types in the replication system
 */
export enum OperationType {
  CREATE = "create",
  UPDATE = "update",
  DELETE = "delete",
  MERGE = "merge",
}

/**
 * Base operation in the CRDT log
 */
export interface ReplicationOperation<T = any> {
  id: string;
  timestamp: number;
  nodeId: NodeId;
  vectorClock: VectorClock;
  operationType: OperationType;
  resourceId: string;
  resourceType: string;
  payload: T;
  hash: string; // SHA256 for integrity verification
}

/**
 * Replication log entry
 */
export interface ReplicationLogEntry {
  seq: number; // Sequence number for this node
  operation: ReplicationOperation;
  appliedAt: number;
  status: "pending" | "applied" | "conflict";
}

/**
 * Conflict detection result
 */
export interface ConflictDetection {
  hasConflict: boolean;
  conflictingOperations: ReplicationOperation[];
  conflictType: "concurrent_update" | "delete_write" | "field_collision" | null;
  resolution: "automatic" | "requires_manual";
}

/**
 * Sync state between nodes
 */
export interface SyncState {
  nodeId: NodeId;
  lastSyncClock: VectorClock;
  pendingOperations: ReplicationOperation[];
  appliedOperations: ReplicationOperation[];
}

/**
 * Replication message for inter-node communication
 */
export interface ReplicationMessage {
  id: string;
  senderId: NodeId;
  receiverId: NodeId;
  messageType: "sync_request" | "sync_response" | "operation_batch" | "ack";
  vectorClock: VectorClock;
  operations: ReplicationOperation[];
  timestamp: number;
  checksum: string; // Integrity verification
}

/**
 * Replication policy configuration
 */
export interface ReplicationPolicy {
  mode: "strong" | "eventual" | "causal";
  consistencyLevel: "strong" | "eventual";
  conflictResolution: "last_write_wins" | "custom" | "manual";
  synchronizationBound: number; // milliseconds
  minReplicas: number;
  maxReplicationLag: number; // milliseconds
}

/**
 * Replication metrics
 */
export interface ReplicationMetrics {
  operationsPerSecond: number;
  replicationLagMs: number;
  conflictRate: number; // percentage
  syncSuccessRate: number; // percentage
  meanTimeToConsistency: number; // milliseconds
  activeConnections: number;
  queuedOperations: number;
}

/**
 * Replication health status
 */
export interface ReplicationHealth {
  status: "healthy" | "degraded" | "unhealthy";
  lastSyncTime: number;
  pendingOperations: number;
  conflictsDetected: number;
  syncErrors: number;
  nodeAvailability: {
    [nodeId: string]: {
      available: boolean;
      lastSeen: number;
      latencyMs: number;
    };
  };
}

/**
 * CRDT state for a resource
 */
export interface CRDTState<T = any> {
  resourceId: string;
  resourceType: string;
  currentValue: T;
  tombstone: VectorClock | null; // null if not deleted
  versions: Map<string, { value: T; clock: VectorClock }>;
  causality: {
    origin: NodeId;
    timestamp: number;
    predecessors: string[]; // operation IDs that came before
  };
}

/**
 * Conflict resolution result
 */
export interface ConflictResolution {
  winner: ReplicationOperation;
  loser: ReplicationOperation;
  reason: string;
  resolved: boolean;
  mergedValue?: any;
}

/**
 * Replication event for event streaming
 */
export interface ReplicationEvent {
  type: "operation_applied" | "conflict_detected" | "sync_completed" | "consistency_reached";
  operation?: ReplicationOperation;
  conflict?: ConflictDetection;
  syncState?: SyncState;
  timestamp: number;
}
