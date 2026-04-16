/**
 * Phase 12.2: Conflict Resolver
 * Resolves conflicts between concurrent operations using CRDT semantics
 * Implements Last-Write-Wins, custom resolution, and automatic merging strategies
 */

import {
  CRDTOperation,
  ConflictMetadata,
  LWWRegister,
  LWWCounter,
  ORSet,
  ORMap,
  ORSetElement,
} from './CRDTTypes';
import { VectorClock, VectorClockValue } from './VectorClock';
import { v4 as uuidv4 } from 'uuid';

export type ResolutionStrategy = 'lww' | 'first-write-wins' | 'replica-id' | 'custom';

export type ResolutionCallback<T> = (
  operation1: CRDTOperation,
  operation2: CRDTOperation,
  data1: T,
  data2: T
) => T;

export interface ConflictResolutionConfig {
  strategy: ResolutionStrategy;
  replicaPriority?: Map<string, number>; // Higher number = higher priority
  customResolver?: ResolutionCallback<any>;
  enableMerging?: boolean;
  maxMergeDepth?: number;
}

export class ConflictResolver {
  private config: ConflictResolutionConfig;
  private conflictHistory: ConflictMetadata[] = [];
  private readonly maxHistorySize = 10000;

  constructor(config: ConflictResolutionConfig) {
    this.config = {
      enableMerging: true,
      maxMergeDepth: 10,
      ...config,
    };
  }

  /**
   * Detect if two operations conflict
   */
  detectConflict(op1: CRDTOperation, op2: CRDTOperation): boolean {
    // Same key and concurrent (neither happened before)
    if (op1.key !== op2.key) return false;

    return VectorClock.isConcurrent(op1.vectorClock, op2.vectorClock);
  }

  /**
   * Resolve conflict between two operations
   */
  resolveConflict<T>(
    op1: CRDTOperation,
    op2: CRDTOperation,
    data1: T,
    data2: T
  ): { winner: CRDTOperation; data: T; metadata: ConflictMetadata } {
    const conflictId = uuidv4();
    const conflictingReplicaIds = [
      op1.replicaId,
      op2.replicaId,
    ].filter((v, i, a) => a.indexOf(v) === i);

    // Choose resolution strategy
    let winner: CRDTOperation;
    let resolvedData: T;
    let resolutionReason: string;

    switch (this.config.strategy) {
      case 'lww':
        ({ winner, resolvedData, resolutionReason } = this.resolveLWW(
          op1,
          op2,
          data1,
          data2
        ));
        break;

      case 'first-write-wins':
        ({ winner, resolvedData, resolutionReason } = this.resolveFWW(
          op1,
          op2,
          data1,
          data2
        ));
        break;

      case 'replica-id':
        ({ winner, resolvedData, resolutionReason } = this.resolveByReplicaId(
          op1,
          op2,
          data1,
          data2
        ));
        break;

      case 'custom':
        if (!this.config.customResolver) {
          throw new Error('Custom resolver not provided');
        }
        winner = op1;
        resolvedData = this.config.customResolver(op1, op2, data1, data2);
        resolutionReason = 'Custom resolution applied';
        break;

      default:
        throw new Error(`Unknown resolution strategy: ${this.config.strategy}`);
    }

    const metadata: ConflictMetadata = {
      conflictId,
      timestamp: Date.now(),
      conflictingReplicaIds,
      operationIds: [op1.operationId, op2.operationId],
      resolvedBy: this.config.strategy as 'lww' | 'custom' | 'merged',
      resolutionReason,
    };

    this.recordConflict(metadata);

    return { winner, data: resolvedData, metadata };
  }

  /**
   * Last-Write-Wins resolution
   * The operation with the latest timestamp wins
   */
  private resolveLWW<T>(
    op1: CRDTOperation,
    op2: CRDTOperation,
    data1: T,
    data2: T
  ): { winner: CRDTOperation; resolvedData: T; resolutionReason: string } {
    if (op1.timestamp > op2.timestamp) {
      return {
        winner: op1,
        resolvedData: data1,
        resolutionReason: `LWW: op1 timestamp (${op1.timestamp}) > op2 (${op2.timestamp})`,
      };
    } else if (op2.timestamp > op1.timestamp) {
      return {
        winner: op2,
        resolvedData: data2,
        resolutionReason: `LWW: op2 timestamp (${op2.timestamp}) > op1 (${op1.timestamp})`,
      };
    } else {
      // Same timestamp, use replica ID as tiebreaker
      const winner = op1.replicaId.localeCompare(op2.replicaId) > 0 ? op1 : op2;
      const data = winner === op1 ? data1 : data2;
      return {
        winner,
        resolvedData: data,
        resolutionReason: 'LWW: Same timestamp, resolved by replica ID',
      };
    }
  }

  /**
   * First-Write-Wins resolution
   * The operation that happened first in causality wins
   */
  private resolveFWW<T>(
    op1: CRDTOperation,
    op2: CRDTOperation,
    data1: T,
    data2: T
  ): { winner: CRDTOperation; resolvedData: T; resolutionReason: string } {
    if (VectorClock.happensBefore(op1.vectorClock, op2.vectorClock)) {
      return {
        winner: op1,
        resolvedData: data1,
        resolutionReason: 'FWW: op1 happened before op2',
      };
    } else {
      return {
        winner: op2,
        resolvedData: data2,
        resolutionReason: 'FWW: op2 happened before op1 or concurrent',
      };
    }
  }

  /**
   * Resolution by replica ID priority
   * Higher priority replica wins
   */
  private resolveByReplicaId<T>(
    op1: CRDTOperation,
    op2: CRDTOperation,
    data1: T,
    data2: T
  ): { winner: CRDTOperation; resolvedData: T; resolutionReason: string } {
    const priority1 = this.config.replicaPriority?.get(op1.replicaId) ?? 0;
    const priority2 = this.config.replicaPriority?.get(op2.replicaId) ?? 0;

    if (priority1 > priority2) {
      return {
        winner: op1,
        resolvedData: data1,
        resolutionReason: `Replica priority: ${op1.replicaId} (${priority1}) > ${op2.replicaId} (${priority2})`,
      };
    } else if (priority2 > priority1) {
      return {
        winner: op2,
        resolvedData: data2,
        resolutionReason: `Replica priority: ${op2.replicaId} (${priority2}) > ${op1.replicaId} (${priority1})`,
      };
    } else {
      // Same priority, use replica ID lexicographically
      const winner = op1.replicaId.localeCompare(op2.replicaId) > 0 ? op1 : op2;
      const data = winner === op1 ? data1 : data2;
      return {
        winner,
        resolvedData: data,
        resolutionReason: 'Replica priority: Same level, resolved lexicographically',
      };
    }
  }

  /**
   * Merge two OR-Sets by taking union of unique elements
   */
  mergeORSets(set1: ORSet, set2: ORSet): ORSet {
    const merged = set1.elements;

    for (const [elemId, elem2] of set2.elements) {
      if (!merged.has(elemId)) {
        merged.set(elemId, elem2);
      } else {
        const elem1 = merged.get(elemId)!;
        // Union the tags
        const unionTags = new Set([...elem1.tags, ...elem2.tags]);
        merged.set(elemId, {
          value: elem1.value, // Keep existing value
          tags: unionTags,
          timestamp: Math.max(elem1.timestamp, elem2.timestamp),
        });
      }
    }

    return {
      ...set1,
      elements: merged,
      timestamp: Math.max(set1.timestamp, set2.timestamp),
    };
  }

  /**
   * Merge two OR-Maps by merging individual fields
   */
  mergeORMaps(map1: ORMap, map2: ORMap): ORMap {
    const merged = new Map(map1.fields);

    for (const [key, field2] of map2.fields) {
      if (!merged.has(key)) {
        merged.set(key, field2);
      } else {
        const field1 = merged.get(key)!;
        // For nested structures, apply LWW
        if (field2.timestamp > field1.timestamp) {
          merged.set(key, field2);
        }
      }
    }

    return {
      ...map1,
      fields: merged,
      timestamp: Math.max(map1.timestamp, map2.timestamp),
    };
  }

  /**
   * Record conflict in history
   */
  private recordConflict(metadata: ConflictMetadata): void {
    this.conflictHistory.push(metadata);
    if (this.conflictHistory.length > this.maxHistorySize) {
      this.conflictHistory.shift(); // Remove oldest
    }
  }

  /**
   * Get conflict history
   */
  getConflictHistory(): ConflictMetadata[] {
    return [...this.conflictHistory];
  }

  /**
   * Get conflict statistics
   */
  getConflictStats(): {
    total: number;
    byReplica: Map<string, number>;
    byStrategy: Map<string, number>;
    lastConflict?: ConflictMetadata;
  } {
    const byReplica = new Map<string, number>();
    const byStrategy = new Map<string, number>();

    for (const conflict of this.conflictHistory) {
      for (const replicaId of conflict.conflictingReplicaIds) {
        byReplica.set(replicaId, (byReplica.get(replicaId) ?? 0) + 1);
      }
      byStrategy.set(
        conflict.resolvedBy,
        (byStrategy.get(conflict.resolvedBy) ?? 0) + 1
      );
    }

    return {
      total: this.conflictHistory.length,
      byReplica,
      byStrategy,
      lastConflict:
        this.conflictHistory[this.conflictHistory.length - 1],
    };
  }

  /**
   * Clear conflict history
   */
  clearHistory(): void {
    this.conflictHistory = [];
  }
}
