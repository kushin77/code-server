/**
 * CRDT Async Sync Engine
 * 
 * Handles asynchronous replication of CRDT state across regions
 * with built-in retry logic, batching, and conflict resolution.
 */

import { EventEmitter } from 'events';
import { 
  Operation, 
  SyncMessage, 
  VectorClockManager,
  UniqueIdGenerator,
  CRDTValue,
  mergeVectorClocks,
  serializeCRDT,
  deserializeCRDT
} from './crdt-sync-protocol';

/**
 * Retry configuration
 */
export interface RetryConfig {
  maxRetries: number;
  initialDelayMs: number;
  maxDelayMs: number;
  backoffMultiplier: number;
  timeoutMs: number;
}

/**
 * Default retry configuration with exponential backoff
 */
export const DEFAULT_RETRY_CONFIG: RetryConfig = {
  maxRetries: 5,
  initialDelayMs: 100,
  maxDelayMs: 30000,
  backoffMultiplier: 2,
  timeoutMs: 10000,
};

/**
 * Sync engine statistics
 */
export interface SyncStats {
  operationsSent: number;
  operationsReceived: number;
  conflictsResolved: number;
  replicationLagMs: number;
  messageCount: number;
  failureCount: number;
  successRate: number;
}

/**
 * Replication transport interface
 * Implement to create custom transports (HTTP, gRPC, WebSocket, etc.)
 */
export interface ReplicationTransport {
  send(message: SyncMessage): Promise<SyncMessage>;
  subscribe(handler: (message: SyncMessage) => Promise<void>): void;
  isConnected(): boolean;
}

/**
 * In-memory CRDT sync engine with async replication
 */
export class CRDTAsyncSyncEngine extends EventEmitter {
  private nodeId: string;
  private vectorClockManager: VectorClockManager;
  private idGenerator: UniqueIdGenerator;
  private localState: Map<string, CRDTValue> = new Map();
  private operationLog: Operation[] = [];
  private messageSequence = 0;
  private retryConfig: RetryConfig;
  private stats: SyncStats = {
    operationsSent: 0,
    operationsReceived: 0,
    conflictsResolved: 0,
    replicationLagMs: 0,
    messageCount: 0,
    failureCount: 0,
    successRate: 0,
  };
  private transports: Map<string, ReplicationTransport> = new Map();
  private syncQueue: Operation[] = [];
  private isSyncing = false;
  private lastSyncTime = 0;

  constructor(
    nodeId: string,
    retryConfig: RetryConfig = DEFAULT_RETRY_CONFIG
  ) {
    super();
    this.nodeId = nodeId;
    this.vectorClockManager = new VectorClockManager(nodeId);
    this.idGenerator = new UniqueIdGenerator(nodeId);
    this.retryConfig = retryConfig;
  }

  /**
   * Register a transport for a remote node
   */
  registerTransport(remoteNodeId: string, transport: ReplicationTransport): void {
    this.transports.set(remoteNodeId, transport);
    
    // Subscribe to messages from this transport
    transport.subscribe(async (message) => {
      await this.handleIncomingMessage(message);
    });
  }

  /**
   * Record a local operation
   */
  recordOperation(
    type: 'add' | 'remove' | 'set' | 'update',
    crdtId: string,
    value: any,
    field?: string
  ): Operation {
    this.vectorClockManager.increment(this.nodeId);

    const operation: Operation = {
      id: this.idGenerator.generate(),
      type,
      crdt: crdtId,
      field,
      value,
      timestamp: Date.now(),
      nodeId: this.nodeId,
      vectorClock: this.vectorClockManager.getClock(),
    };

    this.operationLog.push(operation);
    this.syncQueue.push(operation);
    this.stats.operationsSent++;

    this.emit('operation', operation);
    this.scheduleSync();

    return operation;
  }

  /**
   * Schedule synchronization (batches operations)
   */
  private scheduleSync(): void {
    if (this.isSyncing) return;

    // Schedule sync after a short delay to batch operations
    setTimeout(() => {
      if (this.syncQueue.length > 0) {
        this.sync().catch(err => {
          console.error('Sync error:', err);
          this.stats.failureCount++;
        });
      }
    }, 10);
  }

  /**
   * Synchronize pending operations to all remote nodes
   */
  async sync(): Promise<void> {
    if (this.isSyncing) return;
    this.isSyncing = true;

    try {
      const operations = [...this.syncQueue];
      this.syncQueue = [];

      if (operations.length === 0) return;

      const message: SyncMessage = {
        sourceNodeId: this.nodeId,
        targetNodeId: '*', // Broadcast to all
        operations,
        vectorClock: this.vectorClockManager.getClock(),
        messageId: this.idGenerator.generate().toString(),
        timestamp: Date.now(),
        sequence: this.messageSequence++,
      };

      // Send to all connected transports in parallel
      const promises = Array.from(this.transports.entries()).map(
        ([remoteNodeId, transport]) =>
          this.sendWithRetry(transport, message)
      );

      await Promise.allSettled(promises);

      this.lastSyncTime = Date.now();
      this.stats.messageCount++;
      this.emit('synced', message);
    } finally {
      this.isSyncing = false;
    }
  }

  /**
   * Send message with exponential backoff retry
   */
  private async sendWithRetry(
    transport: ReplicationTransport,
    message: SyncMessage,
    attempt = 0
  ): Promise<SyncMessage> {
    try {
      if (!transport.isConnected()) {
        throw new Error('Transport not connected');
      }

      const timeoutPromise = new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error('Send timeout')), this.retryConfig.timeoutMs)
      );

      const sendPromise = transport.send(message);

      return await Promise.race([sendPromise, timeoutPromise]);
    } catch (error) {
      if (attempt < this.retryConfig.maxRetries) {
        const delay = Math.min(
          this.retryConfig.initialDelayMs * Math.pow(this.retryConfig.backoffMultiplier, attempt),
          this.retryConfig.maxDelayMs
        );

        await new Promise(resolve => setTimeout(resolve, delay));
        return this.sendWithRetry(transport, message, attempt + 1);
      }

      this.stats.failureCount++;
      throw error;
    }
  }

  /**
   * Handle incoming sync message
   */
  private async handleIncomingMessage(message: SyncMessage): Promise<void> {
    try {
      // Merge vector clocks for causal ordering
      this.vectorClockManager.merge(message.vectorClock);

      // Apply operations with conflict resolution
      for (const operation of message.operations) {
        this.applyOperation(operation);
      }

      this.stats.operationsReceived += message.operations.length;
      this.emit('message', message);

    } catch (error) {
      console.error('Error handling incoming message:', error);
      this.stats.failureCount++;
    }
  }

  /**
   * Apply operation with CRDT semantics
   * Handles conflicts based on CRDT type
   */
  private applyOperation(operation: Operation): void {
    const { crdt, type, value, vectorClock } = operation;

    let current = this.localState.get(crdt);

    // Conflict resolution based on operation type
    if (current && type === 'set') {
      // Last-write-wins for register types
      const localOp = this.operationLog.find(
        op => op.crdt === crdt && op.type === 'set'
      );
      if (localOp && localOp.timestamp > operation.timestamp) {
        return; // Local write is newer, discard remote
      }
      this.stats.conflictsResolved++;
    }

    // Apply the operation to the local state
    this.localState.set(crdt, value);
    this.operationLog.push(operation);

    this.emit('operationApplied', operation);
  }

  /**
   * Get current CRDT value
   */
  getValue(crdtId: string): CRDTValue {
    return this.localState.get(crdtId) || null;
  }

  /**
   * Get all CRDT values
   */
  getState(): Map<string, CRDTValue> {
    return new Map(this.localState);
  }

  /**
   * Calculate replication lag
   */
  getReplicationLag(): number {
    return Date.now() - this.lastSyncTime;
  }

  /**
   * Get sync statistics
   */
  getStats(): SyncStats {
    const total = this.stats.operationsSent + this.stats.failureCount;
    return {
      ...this.stats,
      replicationLagMs: this.getReplicationLag(),
      successRate: total > 0 ? this.stats.operationsSent / total : 1,
    };
  }

  /**
   * Export state for backup/persistence
   */
  exportState(): string {
    const state = {
      nodeId: this.nodeId,
      localState: Array.from(this.localState).map(([id, value]) => [
        id,
        serializeCRDT(value),
      ]),
      vectorClock: this.vectorClockManager.getClock(),
      stats: this.getStats(),
    };
    return JSON.stringify(state);
  }

  /**
   * Import state from backup/persistence
   */
  importState(data: string): void {
    const state = JSON.parse(data);
    
    this.vectorClockManager.merge(state.vectorClock);
    
    for (const [crdtId, serialized] of state.localState) {
      const deserialized = deserializeCRDT(serialized, this.nodeId);
      this.localState.set(crdtId, deserialized);
    }

    this.emit('stateRestored', state);
  }

  /**
   * Health check for replication
   */
  getHealthStatus() {
    const stats = this.getStats();
    const lag = this.getReplicationLag();

    return {
      healthy: stats.successRate > 0.95 && lag < 5000,
      successRate: stats.successRate,
      replicationLagMs: lag,
      pendingOperations: this.syncQueue.length,
      connectedPeers: this.transports.size,
      messageCount: stats.messageCount,
    };
  }

  /**
   * Reset statistics
   */
  resetStats(): void {
    this.stats = {
      operationsSent: 0,
      operationsReceived: 0,
      conflictsResolved: 0,
      replicationLagMs: 0,
      messageCount: 0,
      failureCount: 0,
      successRate: 0,
    };
  }

  /**
   * Graceful shutdown
   */
  async shutdown(): Promise<void> {
    // Flush pending operations
    await this.sync();

    // Clear transports
    this.transports.clear();

    this.removeAllListeners();
  }
}

/**
 * HTTP-based replication transport
 */
export class HTTPReplicationTransport implements ReplicationTransport {
  private remoteUrl: string;
  private connected = true;
  private handler?: (message: SyncMessage) => Promise<void>;

  constructor(remoteUrl: string) {
    this.remoteUrl = remoteUrl;
  }

  async send(message: SyncMessage): Promise<SyncMessage> {
    const response = await fetch(this.remoteUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(message),
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }

    return response.json();
  }

  subscribe(handler: (message: SyncMessage) => Promise<void>): void {
    this.handler = handler;
  }

  isConnected(): boolean {
    return this.connected;
  }
}
