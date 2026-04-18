/**
 * Phase 12.2: Replication Service
 * Orchestrates distributed data replication with CRDT and conflict resolution
 */

import { EventEmitter } from "events";
import {
  NodeId,
  ReplicationOperation,
  ReplicationMessage,
  SyncState,
  ReplicationPolicy,
  ReplicationMetrics,
  ReplicationHealth,
  ReplicationEvent,
  OperationType,
} from "./types";
import { CRDTSyncProtocol } from "./CRDTSyncProtocol";
import { ConflictResolver } from "./ConflictResolver";

/**
 * ReplicationService
 * Manages multi-node data replication with eventual consistency
 */
export class ReplicationService extends EventEmitter {
  private nodeId: NodeId;
  private crdtProtocol: CRDTSyncProtocol;
  private conflictResolver: ConflictResolver;
  private peers: Map<NodeId, SyncState>;
  private policy: ReplicationPolicy;
  private metrics: ReplicationMetrics;
  private health: ReplicationHealth;
  private messageQueue: Map<NodeId, ReplicationMessage[]>;
  private lastSyncTime: number;
  private syncInterval: NodeJS.Timeout | null;

  constructor(
    nodeId: NodeId,
    policy: ReplicationPolicy = {
      mode: "eventual",
      consistencyLevel: "eventual",
      conflictResolution: "last_write_wins",
      synchronizationBound: 5000, // 5 seconds
      minReplicas: 2,
      maxReplicationLag: 30000, // 30 seconds
    }
  ) {
    super();

    this.nodeId = nodeId;
    this.crdtProtocol = new CRDTSyncProtocol(nodeId);
    this.conflictResolver = new ConflictResolver();
    this.peers = new Map();
    this.policy = policy;
    this.messageQueue = new Map();
    this.lastSyncTime = Date.now();

    this.metrics = {
      operationsPerSecond: 0,
      replicationLagMs: 0,
      conflictRate: 0,
      syncSuccessRate: 100,
      meanTimeToConsistency: 0,
      activeConnections: 0,
      queuedOperations: 0,
    };

    this.health = {
      status: "healthy",
      lastSyncTime: Date.now(),
      pendingOperations: 0,
      conflictsDetected: 0,
      syncErrors: 0,
      nodeAvailability: {},
    };

    this.initializeSyncLoop();
  }

  /**
   * Register a peer node
   */
  registerPeer(peerId: NodeId): void {
    this.peers.set(peerId, {
      nodeId: peerId,
      lastSyncClock: {},
      pendingOperations: [],
      appliedOperations: [],
    });

    this.messageQueue.set(peerId, []);
    this.health.nodeAvailability[peerId] = {
      available: true,
      lastSeen: Date.now(),
      latencyMs: 0,
    };

    this.emit("peer_registered", { peerId });
  }

  /**
   * Unregister a peer node
   */
  unregisterPeer(peerId: NodeId): void {
    this.peers.delete(peerId);
    this.messageQueue.delete(peerId);
    delete this.health.nodeAvailability[peerId];
    this.emit("peer_unregistered", { peerId });
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
    const operation = this.crdtProtocol.createOperation(
      operationType,
      resourceType,
      resourceId,
      payload
    );

    this.health.pendingOperations++;
    this.metrics.queuedOperations++;

    // Queue for all peers
    const message = this.crdtProtocol.createReplicationMessage(
      this.nodeId, // Placeholder, will be set per peer
      [operation]
    );

    for (const peerId of this.peers.keys()) {
      const peerMessage = { ...message, receiverId: peerId };
      this.messageQueue.get(peerId)?.push(peerMessage);
    }

    const event: ReplicationEvent = {
      type: "operation_applied",
      operation,
      timestamp: Date.now(),
    };
    this.emit("operation_created", event);

    return operation;
  }

  /**
   * Handle incoming replication message from peer
   */
  async handleReplicationMessage(message: ReplicationMessage): Promise<void> {
    const startTime = Date.now();

    try {
      // Verify message integrity
      if (!this.verifyMessageIntegrity(message)) {
        throw new Error(`Message integrity check failed: ${message.id}`);
      }

      // Track peer health
      const peer = this.peers.get(message.senderId);
      if (peer) {
        const latency = Date.now() - message.timestamp;
        if (this.health.nodeAvailability[message.senderId]) {
          this.health.nodeAvailability[message.senderId].latencyMs = latency;
          this.health.nodeAvailability[message.senderId].lastSeen = Date.now();
        }
      }

      // Process operations
      for (const operation of message.operations) {
        try {
          this.crdtProtocol.applyOperation(operation);

          if (peer) {
            peer.appliedOperations.push(operation);
            peer.lastSyncClock = this.crdtProtocol.getVectorClock();
          }

          this.health.pendingOperations--;
          const event: ReplicationEvent = {
            type: "operation_applied",
            operation,
            timestamp: Date.now(),
          };
          this.emit("operation_applied", event);
        } catch (error) {
          this.health.syncErrors++;
          this.emit("error", {
            error,
            operationId: operation.id,
          });
        }
      }

      // Send acknowledgment
      this.sendAcknowledgment(message.senderId, message.id);
    } catch (error) {
      this.health.syncErrors++;
      this.emit("error", { error, messageId: message.id });
    }

    const processingTime = Date.now() - startTime;
    this.updateMetrics(processingTime);
  }

  /**
   * Verify message integrity using checksum
   */
  private verifyMessageIntegrity(message: ReplicationMessage): boolean {
    const crypto = require("crypto");
    const messagePayload = {
      operations: message.operations,
      vectorClock: message.vectorClock,
    };
    const expectedChecksum = crypto
      .createHash("sha256")
      .update(JSON.stringify(messagePayload))
      .digest("hex");

    return message.checksum === expectedChecksum;
  }

  /**
   * Send acknowledgment to peer
   */
  private sendAcknowledgment(peerId: NodeId, messageId: string): void {
    const ackMessage: ReplicationMessage = {
      id: `ack:${messageId}`,
      senderId: this.nodeId,
      receiverId: peerId,
      messageType: "ack",
      vectorClock: this.crdtProtocol.getVectorClock(),
      operations: [],
      timestamp: Date.now(),
      checksum: "",
    };

    this.emit("message_ready", { peerId, message: ackMessage });
  }

  /**
   * Get pending operations for a peer
   */
  getPendingOperations(peerId: NodeId): ReplicationOperation[] {
    const peer = this.peers.get(peerId);
    if (!peer) return [];

    // Return operations peer hasn't seen yet
    const lastClock = peer.lastSyncClock;
    const allOperations = this.crdtProtocol
      .getAllStates()
      .entries();

    const pending: ReplicationOperation[] = [];
    for (const [_, state] of allOperations) {
      if (state.causality.timestamp > (lastClock[state.causality.origin] || 0)) {
        // This is a placeholder - in reality would get from operation log
        pending.push({
          id: `${state.resourceId}:${state.causality.timestamp}`,
          timestamp: state.causality.timestamp,
          nodeId: state.causality.origin,
          vectorClock: lastClock,
          operationType: OperationType.UPDATE,
          resourceId: state.resourceId,
          resourceType: state.resourceType,
          payload: state.currentValue,
          hash: "",
        });
      }
    }

    return pending;
  }

  /**
   * Synchronize with specific peer
   */
  async syncWithPeer(peerId: NodeId): Promise<void> {
    const peer = this.peers.get(peerId);
    if (!peer) return;

    const pending = this.getPendingOperations(peerId);
    if (pending.length === 0) return;

    const message = this.crdtProtocol.createReplicationMessage(
      peerId,
      pending
    );
    message.vectorClock = this.crdtProtocol.getVectorClock();

    const messageQueue = this.messageQueue.get(peerId);
    if (messageQueue) {
      messageQueue.push(message);
    }

    this.emit("sync_initiated", { peerId, operationCount: pending.length });
  }

  /**
   * Initialize sync loop for background synchronization
   */
  private initializeSyncLoop(): void {
    this.syncInterval = setInterval(async () => {
      for (const peerId of this.peers.keys()) {
        try {
          await this.syncWithPeer(peerId);
        } catch (error) {
          this.health.syncErrors++;
          this.emit("error", { error, peerId });
        }
      }

      this.lastSyncTime = Date.now();
      this.health.lastSyncTime = Date.now();

      const event: ReplicationEvent = {
        type: "sync_completed",
        syncState: {
          nodeId: this.nodeId,
          lastSyncClock: this.crdtProtocol.getVectorClock(),
          pendingOperations: Array.from(
            this.messageQueue.values()
          ).flatMap((msgs) =>
            msgs.flatMap((msg) => msg.operations)
          ),
          appliedOperations: Array.from(this.peers.values()).flatMap(
            (p) => p.appliedOperations
          ),
        },
        timestamp: Date.now(),
      };
      this.emit("sync_completed", event);
    }, this.policy.synchronizationBound);
  }

  /**
   * Update metrics
   */
  private updateMetrics(processingTime: number): void {
    const now = Date.now();
    const timeSinceLastSync = now - this.lastSyncTime;

    this.metrics.replicationLagMs = Math.max(
      0,
      timeSinceLastSync - this.policy.synchronizationBound
    );

    // Calculate success rate
    const totalOps = this.health.pendingOperations + 
                     Array.from(this.peers.values()).flatMap(p => p.appliedOperations).length;
    this.metrics.syncSuccessRate =
      totalOps > 0
        ? (Array.from(this.peers.values()).flatMap(p => p.appliedOperations).length / totalOps) * 100
        : 100;
  }

  /**
   * Get current metrics
   */
  getMetrics(): ReplicationMetrics {
    return { ...this.metrics };
  }

  /**
   * Get health status
   */
  getHealth(): ReplicationHealth {
    this.health.activeConnections = Array.from(
      this.health.nodeAvailability.values()
    ).filter((n) => n.available).length;

    this.health.pendingOperations = Array.from(
      this.messageQueue.values()
    ).flatMap((msgs) => msgs).flatMap((msg) => msg.operations).length;

    return { ...this.health };
  }

  /**
   * Shutdown replication service
   */
  shutdown(): void {
    if (this.syncInterval) {
      clearInterval(this.syncInterval);
      this.syncInterval = null;
    }
    this.emit("shutdown");
  }
}

export default ReplicationService;
