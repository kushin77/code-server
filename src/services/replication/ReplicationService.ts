/**
 * Phase 12.2: Replication Service
 * Main coordinator for multi-region data replication
 * Manages peer connections, synchronization, and conflict resolution
 */

import {
  CRDTOperation,
  ReplicationEnvelope,
  RegionReplicationConfig,
  ReplicationMetrics,
  LWWRegister,
  LWWCounter,
  ORSet,
  ORMap,
} from './CRDTTypes';
import { VectorClock, VectorClockValue } from './VectorClock';
import { ConflictResolver, ResolutionStrategy } from './ConflictResolver';
import { SyncProtocol, SyncProtocolConfig } from './SyncProtocol';
import { EventEmitter } from 'events';

export interface ReplicationServiceConfig {
  replicaId: string;
  regionId: string;
  regions: RegionReplicationConfig[];
  conflictResolutionStrategy: ResolutionStrategy;
  enableCompression: boolean;
  syncIntervalMs: number;
  maxBatchSize: number;
  persistenceEnabled: boolean;
}

export interface ReplicationPeer {
  replicaId: string;
  regionId: string;
  endpoint: string;
  port: number;
  isHealthy: boolean;
  lastSyncTime: number;
  syncLatency: number;
  vectorClock: VectorClockValue;
}

export class ReplicationService extends EventEmitter {
  private config: ReplicationServiceConfig;
  private peers: Map<string, ReplicationPeer> = new Map();
  private syncProtocol: SyncProtocol;
  private conflictResolver: ConflictResolver;
  private metrics: ReplicationMetrics;
  private dataDictionary: Map<string, any> = new Map();
  private syncIntervalHandle?: NodeJS.Timer;
  private isRunning = false;

  constructor(config: ReplicationServiceConfig) {
    super();
    this.config = config;

    // Initialize sync protocol
    this.syncProtocol = new SyncProtocol({
      replicaId: config.replicaId,
      regionId: config.regionId,
      maxBatchSize: config.maxBatchSize,
      syncIntervalMs: config.syncIntervalMs,
      maxClockSkewMs: 5000,
      enableCompression: config.enableCompression,
      compressionThreshold: 10240, // 10KB
    });

    // Initialize conflict resolver
    this.conflictResolver = new ConflictResolver({
      strategy: config.conflictResolutionStrategy,
      replicaPriority: this.buildReplicaPriority(),
      enableMerging: true,
      maxMergeDepth: 10,
    });

    // Initialize metrics
    this.metrics = {
      operationsProcessed: 0,
      conflictsDetected: 0,
      conflictsResolved: 0,
      bytesTransferred: 0,
      lastSyncTimestamp: 0,
      averageSyncLatency: 0,
      convergenceAchieved: false,
    };

    // Initialize peers
    this.initializePeers();
  }

  /**
   * Start the replication service
   */
  async start(): Promise<void> {
    if (this.isRunning) {
      return;
    }

    this.isRunning = true;
    this.emit('service-started', {
      replicaId: this.config.replicaId,
      regionId: this.config.regionId,
      timestamp: Date.now(),
    });

    // Start periodic synchronization
    await this.startPeriodicSync();

    // Health check
    await this.startHealthCheck();

    console.log(
      `[ReplicationService] Started for replica ${this.config.replicaId} in region ${this.config.regionId}`
    );
  }

  /**
   * Stop the replication service
   */
  async stop(): Promise<void> {
    if (!this.isRunning) {
      return;
    }

    this.isRunning = false;

    if (this.syncIntervalHandle) {
      clearInterval(this.syncIntervalHandle);
    }

    this.emit('service-stopped', {
      replicaId: this.config.replicaId,
      timestamp: Date.now(),
    });

    console.log(
      `[ReplicationService] Stopped for replica ${this.config.replicaId}`
    );
  }

  /**
   * Write data to the local replica
   */
  async write(
    key: string,
    value: any,
    operationType: string
  ): Promise<{ success: boolean; operationId: string }> {
    const operation: Omit<
      CRDTOperation,
      'replicaId' | 'vectorClock' | 'operationId'
    > = {
      type: operationType as any,
      key,
      value,
      timestamp: Date.now(),
    };

    const envelope = this.syncProtocol.sendOperation(operation);
    const operationId = envelope.data.operationId;

    // Store locally
    this.dataDictionary.set(key, {
      value,
      timestamp: envelope.data.timestamp,
      vectorClock: envelope.data.vectorClock,
    });

    this.metrics.operationsProcessed++;

    // Emit replication event
    this.emit('data-written', {
      key,
      operationId,
      timestamp: envelope.data.timestamp,
    });

    // Broadcast to peers asynchronously
    setImmediate(() => this.broadcastOperation(envelope));

    return { success: true, operationId };
  }

  /**
   * Read data from local replica
   */
  read(key: string): any {
    const data = this.dataDictionary.get(key);
    return data ? data.value : undefined;
  }

  /**
   * Receive operation from peer
   */
  async receiveOperation(
    envelope: ReplicationEnvelope<CRDTOperation>
  ): Promise<boolean> {
    const operation = envelope.data;

    const result = this.syncProtocol.receiveOperation(envelope);

    if (!result.accepted) {
      this.emit('operation-rejected', {
        operationId: operation.operationId,
        reason: 'Validation failed',
      });
      return false;
    }

    if (result.isNew) {
      // Apply operation to local state
      this.applyOperation(operation);
      this.metrics.operationsProcessed++;
    }

    return true;
  }

  /**
   * Manually trigger synchronization with all peers
   */
  async syncWithAll(): Promise<void> {
    const syncPromises: Promise<void>[] = [];

    for (const [replicaId, peer] of this.peers) {
      if (peer.isHealthy) {
        syncPromises.push(this.syncWithPeer(replicaId));
      }
    }

    await Promise.all(syncPromises);
    this.metrics.lastSyncTimestamp = Date.now();
  }

  /**
   * Get replication metrics
   */
  getMetrics(): ReplicationMetrics {
    return { ...this.metrics };
  }

  /**
   * Get list of connected peers
   */
  getPeers(): ReplicationPeer[] {
    return Array.from(this.peers.values());
  }

  /**
   * Get vector clock state
   */
  getVectorClock(): VectorClockValue {
    return this.syncProtocol.getVectorClock();
  }

  /**
   * Get conflict statistics
   */
  getConflictStats() {
    return this.conflictResolver.getConflictStats();
  }

  /**
   * Initialize peer connections
   */
  private initializePeers(): void {
    for (const region of this.config.regions) {
      if (region.replicaId !== this.config.replicaId) {
        this.peers.set(region.replicaId, {
          replicaId: region.replicaId,
          regionId: region.name,
          endpoint: region.endpoint,
          port: region.port,
          isHealthy: true,
          lastSyncTime: 0,
          syncLatency: 0,
          vectorClock: {},
        });
      }
    }
  }

  /**
   * Build replica priority map based on configuration
   */
  private buildReplicaPriority(): Map<string, number> {
    const priority = new Map<string, number>();

    // Sort regions by priority (lower number = higher priority)
    const sortedRegions = [...this.config.regions].sort(
      (a, b) => a.priority - b.priority
    );

    sortedRegions.forEach((region, index) => {
      priority.set(region.replicaId, sortedRegions.length - index);
    });

    return priority;
  }

  /**
   * Apply operation to local state
   */
  private applyOperation(operation: CRDTOperation): void {
    const existingData = this.dataDictionary.get(operation.key);

    if (existingData) {
      // Check for conflicts
      const existingOp: CRDTOperation = {
        type: 'assign',
        key: operation.key,
        value: existingData.value,
        timestamp: existingData.timestamp,
        replicaId: this.config.replicaId,
        vectorClock: existingData.vectorClock,
        operationId: 'internal-' + operation.key,
      };

      if (
        this.conflictResolver.detectConflict(existingOp, operation)
      ) {
        this.metrics.conflictsDetected++;
        const conflict = this.conflictResolver.resolveConflict(
          existingOp,
          operation,
          existingData.value,
          operation.value
        );

        this.metrics.conflictsResolved++;
        this.dataDictionary.set(operation.key, {
          value: conflict.data,
          timestamp: conflict.winner.timestamp,
          vectorClock: conflict.winner.vectorClock,
        });

        this.emit('conflict-resolved', conflict.metadata);
      } else {
        // No conflict - apply the change
        this.dataDictionary.set(operation.key, {
          value: operation.value,
          timestamp: operation.timestamp,
          vectorClock: operation.vectorClock,
        });
      }
    } else {
      // New key
      this.dataDictionary.set(operation.key, {
        value: operation.value,
        timestamp: operation.timestamp,
        vectorClock: operation.vectorClock,
      });
    }
  }

  /**
   * Broadcast operation to all peers
   */
  private async broadcastOperation(
    envelope: ReplicationEnvelope<CRDTOperation>
  ): Promise<void> {
    for (const [replicaId, peer] of this.peers) {
      if (peer.isHealthy) {
        try {
          // In a real implementation, this would send over network
          this.emit('operation-sent', {
            target: replicaId,
            operationId: envelope.data.operationId,
          });
        } catch (error) {
          console.error(
            `Failed to send operation to ${replicaId}:`,
            error
          );
          peer.isHealthy = false;
        }
      }
    }
  }

  /**
   * Sync with specific peer
   */
  private async syncWithPeer(replicaId: string): Promise<void> {
    const peer = this.peers.get(replicaId);
    if (!peer) return;

    try {
      const startTime = Date.now();

      // Build sync request
      const syncRequest = this.syncProtocol.buildSyncRequest(
        replicaId,
        peer.vectorClock
      );

      // In real implementation, this would send over network
      // For now, emit event
      this.emit('sync-initiated', {
        targetReplicaId: replicaId,
        knownOps: syncRequest.knownOperationIds.size,
      });

      const latency = Date.now() - startTime;
      peer.syncLatency = latency;
      peer.lastSyncTime = Date.now();

      // Update metrics
      this.metrics.bytesTransferred += 1024; // Placeholder
      this.metrics.averageSyncLatency =
        (this.metrics.averageSyncLatency * 0.9 + latency * 0.1);
    } catch (error) {
      console.error(`Sync failed with ${replicaId}:`, error);
      peer.isHealthy = false;
    }
  }

  /**
   * Start periodic synchronization
   */
  private async startPeriodicSync(): Promise<void> {
    this.syncIntervalHandle = setInterval(
      () => this.syncWithAll(),
      this.config.syncIntervalMs
    );

    // Initial sync
    await this.syncWithAll();
  }

  /**
   * Start health check for peers
   */
  private async startHealthCheck(): Promise<void> {
    setInterval(() => {
      for (const [replicaId, peer] of this.peers) {
        if (!peer.isHealthy) {
          // Try to reconnect
          peer.isHealthy = true;
          this.emit('peer-recovered', { replicaId });
        }
      }
    }, 30000); // Check every 30 seconds
  }
}
