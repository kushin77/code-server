/**
 * Phase 12.2: CRDT Data Type Definitions
 * Conflict-free Replicated Data Types for multi-region consistency
 * Supports: LWW (Last-Write-Wins), OR-Set, LWW-Counter, LWW-Register, OR-Map
 */

import { VectorClockValue } from './VectorClock';

/**
 * Base operation interface for all CRDT operations
 */
export interface CRDTOperation {
  type: 'increment' | 'decrement' | 'add' | 'remove' | 'assign' | 'assign-nested';
  key: string;
  value?: any;
  timestamp: number;
  replicaId: string;
  vectorClock: VectorClockValue;
  operationId: string; // Unique ID for the operation
}

/**
 * Last-Write-Wins Counter
 * Uses timestamp to resolve conflicts - latest write wins
 */
export interface LWWCounter {
  type: 'lww-counter';
  value: number;
  timestamp: number;
  replicaId: string;
  operations: CRDTOperation[];
}

/**
 * Observed-Remove Set (OR-Set)
 * Allows both adds and removes with unique tags to prevent concurrent conflicts
 */
export interface ORSet {
  type: 'or-set';
  elements: Map<string, ORSetElement>;
  timestamp: number;
  replicaId: string;
  operations: CRDTOperation[];
}

export interface ORSetElement {
  value: any;
  tags: Set<string>; // Unique identifiers for the add operation
  timestamp: number;
}

/**
 * Last-Write-Wins Register
 * Single value that gets overwritten with timestamp-based conflict resolution
 */
export interface LWWRegister {
  type: 'lww-register';
  value: any;
  timestamp: number;
  replicaId: string;
  operations: CRDTOperation[];
}

/**
 * Observed-Remove Map (OR-Map)
 * Map where each field is an OR-Set, enabling nested CRDT support
 */
export interface ORMap {
  type: 'or-map';
  fields: Map<string, ORMapField>;
  timestamp: number;
  replicaId: string;
  operations: CRDTOperation[];
}

export interface ORMapField {
  type: 'lww-register' | 'or-set' | 'lww-counter';
  value: any;
  timestamp: number;
  tags?: Set<string>; // For OR-Set fields
}

/**
 * Replication envelope wraps a CRDT with metadata
 */
export interface ReplicationEnvelope<T> {
  id: string;
  replicaId: string;
  regionId: string;
  timestamp: number;
  vectorClock: VectorClockValue;
  data: T;
  checksum: string;
  compression: 'none' | 'gzip' | 'brotli';
  version: string; // Schema version
  priority: 'high' | 'normal' | 'low';
}

/**
 * Sync request for pulling changes from peer
 */
export interface SyncRequest {
  fromReplicaId: string;
  toReplicaId: string;
  lastSeenVectorClock: VectorClockValue;
  knownOperationIds: Set<string>;
  priority: 'high' | 'normal' | 'low';
}

/**
 * Sync response with changed data
 */
export interface SyncResponse {
  fromReplicaId: string;
  toReplicaId: string;
  operations: CRDTOperation[];
  vectorClock: VectorClockValue;
  hasMore: boolean; // Indicates if there are more changes
  checksumIndex: Map<string, string>; // For validation
}

/**
 * Conflict metadata for tracking conflict events
 */
export interface ConflictMetadata {
  conflictId: string;
  timestamp: number;
  conflictingReplicaIds: string[];
  operationIds: string[];
  resolvedBy: 'lww' | 'custom' | 'merged';
  resolutionReason: string;
}

/**
 * Replication metrics for monitoring
 */
export interface ReplicationMetrics {
  operationsProcessed: number;
  conflictsDetected: number;
  conflictsResolved: number;
  bytesTransferred: number;
  lastSyncTimestamp: number;
  averageSyncLatency: number;
  convergenceAchieved: boolean;
}

/**
 * Region-specific replication config
 */
export interface RegionReplicationConfig {
  regionId: string;
  replicaId: string;
  endpoint: string;
  port: number;
  priority: number; // Lower number = higher priority
  maxBatchSize: number;
  syncIntervalMs: number;
  maxClockSkewMs: number;
  enabled: boolean;
}
