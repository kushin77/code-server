/**
 * Phase 12.2: CRDT Async Synchronization Engine
 *
 * Implements asynchronous CRDT synchronization across regions
 * with automatic retry logic, conflict resolution, and monitoring.
 *
 * Architecture: Event-driven, non-blocking, fully distributed
 */

import { EventEmitter } from 'events';
import pino from 'pino';

// Logger setup
const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  transport: {
    target: 'pino-pretty',
    options: {
      colorize: true,
      singleLine: false,
    },
  },
});

/**
 * Regional CRDT Node Configuration
 */
interface RegionalNode {
  region: string;
  replicaId: string;
  postgresUrl: string;
  priority: number; // Lower = higher priority (for cascading conflicts)
  healthCheckInterval: number; // ms
}

/**
 * Async Sync Event
 */
interface SyncEvent {
  eventId: string;
  timestamp: Date;
  region: string;
  operation: 'insert' | 'update' | 'delete';
  dataType: 'counter' | 'set' | 'register' | 'map';
  key: string;
  value: any;
  vectorClock: Map<string, number>;
  previousState?: any;
}

/**
 * Sync Result with Acknowledgment
 */
interface SyncResult {
  eventId: string;
  success: boolean;
  affectedRegions: string[];
  conflictDetected: boolean;
  resolutionStrategy: 'lww' | 'add-wins' | 'cascading'; // resolution used
  latency: number; // ms to propagate
}

/**
 * Asynchronous CRDT Sync Engine
 *
 * Responsibilities:
 * - Fan out writes to all regions asynchronously
 * - Detect conflicts during synchronization
 * - Apply conflict resolution rules (LWW, Add-Wins)
 * - Track vector clocks for causality
 * - Implement exponential backoff retry logic
 * - Monitor sync health and metrics
 * - Emit events for observability
 */
class CRDTAsyncSyncEngine extends EventEmitter {
  private nodes: Map<string, RegionalNode>;
  private syncQueue: SyncEvent[];
  private inFlightSyncs: Map<string, Promise<SyncResult>>;
  private metrics: {
    totalSyncs: number;
    successfulSyncs: number;
    failedSyncs: number;
    conflictCount: number;
    averageLatency: number;
  };
  private vectorClocks: Map<string, Map<string, number>>; // Per region
  private healthChecks: Map<string, NodeJS.Timer>;

  constructor(nodes: RegionalNode[]) {
    super();
    this.nodes = new Map(nodes.map(n => [n.region, n]));
    this.syncQueue = [];
    this.inFlightSyncs = new Map();
    this.vectorClocks = new Map();
    this.healthChecks = new Map();
    this.metrics = {
      totalSyncs: 0,
      successfulSyncs: 0,
      failedSyncs: 0,
      conflictCount: 0,
      averageLatency: 0,
    };

    // Initialize vector clocks for each region
    for (const region of this.nodes.keys()) {
      const vc = new Map<string, number>();
      for (const otherRegion of this.nodes.keys()) {
        vc.set(otherRegion, 0);
      }
      this.vectorClocks.set(region, vc);
    }

    logger.info('CRDTAsyncSyncEngine initialized with regions: %s',
      Array.from(this.nodes.keys()).join(', '));
  }

  /**
   * Enqueue a CRDT operation for async synchronization
   *
   * This is the main entry point for all write operations.
   * Uses vector clock to track causality.
   */
  async enqueueSync(event: Omit<SyncEvent, 'eventId' | 'timestamp' | 'vectorClock'>): Promise<string> {
    const eventId = `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

    // Increment vector clock for the origin region
    const vc = this.vectorClocks.get(event.region)!;
    const currentClock = vc.get(event.region) || 0;
    vc.set(event.region, currentClock + 1);

    const fullEvent: SyncEvent = {
      eventId,
      timestamp: new Date(),
      vectorClock: new Map(vc),
      ...event,
    };

    this.syncQueue.push(fullEvent);
    logger.debug('Event enqueued: %s (region: %s, op: %s)',
      eventId, event.region, event.operation);

    // Emit event for observability
    this.emit('sync-enqueued', { eventId, region: event.region });

    // Start async processing without blocking
    this.processNextSync().catch(err => {
      logger.error('Sync processing error: %s', err.message);
      this.emit('sync-error', { eventId, error: err.message });
    });

    return eventId;
  }

  /**
   * Process the next event from the queue
   */
  private async processNextSync(): Promise<void> {
    if (this.syncQueue.length === 0) {
      return; // Queue is empty
    }

    const event = this.syncQueue.shift()!;
    const originRegion = event.region;

    logger.debug('Processing sync: %s', event.eventId);

    // Get all target regions (all except origin)
    const targetRegions = Array.from(this.nodes.keys())
      .filter(r => r !== originRegion);

    // Distribute writes to all regions asynchronously
    const syncPromise = Promise.all(
      targetRegions.map(region =>
        this.syncToRegion(event, region)
          .catch(err => ({
            region,
            success: false,
            error: err.message,
          }))
      )
    ).then(results => {
      const successful = results.filter(r => r.success !== false);
      const failed = results.filter(r => r.success === false);

      const result: SyncResult = {
        eventId: event.eventId,
        success: failed.length === 0,
        affectedRegions: successful.map(r => r.region),
        conflictDetected: this.detectConflict(results),
        resolutionStrategy: this.determineResolution(event),
        latency: Date.now() - event.timestamp.getTime(),
      };

      return result;
    });

    this.inFlightSyncs.set(event.eventId, syncPromise);

    syncPromise
      .then(result => this.recordSyncResult(event.eventId, result))
      .catch(err => logger.error('Sync result recording failed: %s', err.message))
      .finally(() => {
        this.inFlightSyncs.delete(event.eventId);
        // Process next event
        if (this.syncQueue.length > 0) {
          this.processNextSync().catch(err =>
            logger.error('Recursive sync processing error: %s', err.message)
          );
        }
      });
  }

  /**
   * Synchronize a single event to a specific region
   */
  private async syncToRegion(event: SyncEvent, targetRegion: string): Promise<{
    region: string;
    success: boolean;
    conflictDetected?: boolean;
  }> {
    const targetNode = this.nodes.get(targetRegion)!;
    const maxRetries = 5;
    let lastError: Error | undefined;

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // Simulate network call (in production: HTTP/gRPC call to regional node)
        const result = await this.sendSyncToRegion(event, targetNode, attempt);

        if (result.success) {
          logger.debug('Sync to %s successful (eventId: %s)',
            targetRegion, event.eventId);
          return {
            region: targetRegion,
            success: true,
            conflictDetected: result.conflictDetected,
          };
        }

        // Operation failed, retry with exponential backoff
        lastError = new Error(result.error || 'Unknown error');
        const backoffMs = Math.min(1000 * Math.pow(2, attempt - 1), 30000);

        logger.warn('Sync to %s failed (attempt %d/%d), retrying in %dms: %s',
          targetRegion, attempt, maxRetries, backoffMs, result.error);

        await this.sleep(backoffMs);
      } catch (err) {
        lastError = err instanceof Error ? err : new Error(String(err));

        if (attempt < maxRetries) {
          const backoffMs = Math.min(1000 * Math.pow(2, attempt - 1), 30000);
          logger.warn('Sync to %s threw error (attempt %d/%d), retrying in %dms: %s',
            targetRegion, attempt, maxRetries, backoffMs, lastError.message);

          await this.sleep(backoffMs);
        }
      }
    }

    // All retries exhausted
    logger.error('Sync to %s failed after %d attempts: %s',
      targetRegion, maxRetries, lastError?.message);

    this.emit('sync-failed', {
      eventId: event.eventId,
      targetRegion,
      error: lastError?.message,
    });

    return {
      region: targetRegion,
      success: false,
    };
  }

  /**
   * Actually send sync to a regional node
   * In production, this would be HTTP/gRPC call
   */
  private async sendSyncToRegion(
    event: SyncEvent,
    node: RegionalNode,
    attempt: number
  ): Promise<{ success: boolean; error?: string; conflictDetected?: boolean }> {
    // Simulate latency
    await this.sleep(Math.random() * 100); // 0-100ms network latency

    // Simulate occasional failures (1% on first attempt, 0% after retries succeed)
    if (attempt === 1 && Math.random() < 0.01) {
      return { success: false, error: 'Network timeout' };
    }

    // In production, this would:
    // 1. Make gRPC call to regional node: POST /sync
    // 2. Send CRDT event with vector clock
    // 3. Receive conflict detection results
    // 4. Apply merge logic if conflicts detected

    return {
      success: true,
      conflictDetected: false,
    };
  }

  /**
   * Detect if a conflict occurred during synchronization
   */
  private detectConflict(results: any[]): boolean {
    return results.some(r => r.conflictDetected === true);
  }

  /**
   * Determine resolution strategy based on data type
   */
  private determineResolution(event: SyncEvent): 'lww' | 'add-wins' | 'cascading' {
    switch (event.dataType) {
      case 'counter':
      case 'register':
        return 'lww'; // Last-Write-Wins for atomic values
      case 'set':
        return 'add-wins'; // Add-Wins for sets
      case 'map':
        return 'cascading'; // Recursive merging for maps
      default:
        return 'lww';
    }
  }

  /**
   * Record sync result and update metrics
   */
  private recordSyncResult(eventId: string, result: SyncResult): void {
    this.metrics.totalSyncs++;

    if (result.success) {
      this.metrics.successfulSyncs++;
    } else {
      this.metrics.failedSyncs++;
    }

    if (result.conflictDetected) {
      this.metrics.conflictCount++;
    }

    // Update running average latency
    this.metrics.averageLatency =
      (this.metrics.averageLatency * (this.metrics.totalSyncs - 1) + result.latency)
      / this.metrics.totalSyncs;

    logger.info('Sync complete: %s (success: %s, latency: %dms, regions: %s)',
      eventId, result.success, result.latency, result.affectedRegions.join(','));

    this.emit('sync-complete', result);
  }

  /**
   * Get metrics for observability
   */
  getMetrics() {
    return {
      ...this.metrics,
      queueLength: this.syncQueue.length,
      inFlightSyncs: this.inFlightSyncs.size,
      successRate: this.metrics.totalSyncs > 0
        ? (this.metrics.successfulSyncs / this.metrics.totalSyncs * 100).toFixed(2) + '%'
        : 'N/A',
      timestamp: new Date(),
    };
  }

  /**
   * Health check for all regions
   */
  async startHealthChecks(): Promise<void> {
    for (const [region, node] of this.nodes) {
      this.healthChecks.set(region, setInterval(async () => {
        try {
          // In production: ping regional node
          const isHealthy = true; // Placeholder

          if (isHealthy) {
            this.emit('health-check-passed', { region });
          } else {
            this.emit('health-check-failed', { region });
          }
        } catch (err) {
          this.emit('health-check-failed', {
            region,
            error: err instanceof Error ? err.message : String(err),
          });
        }
      }, node.healthCheckInterval));
    }

    logger.info('Health checks started for %d regions', this.nodes.size);
  }

  /**
   * Stop health checks and cleanup
   */
  stopHealthChecks(): void {
    for (const [region, interval] of this.healthChecks) {
      clearInterval(interval);
    }
    this.healthChecks.clear();
    logger.info('Health checks stopped');
  }

  /**
   * Utility: Sleep for milliseconds
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Shutdown gracefully
   */
  async shutdown(): Promise<void> {
    this.stopHealthChecks();

    // Wait for in-flight syncs to complete (timeout: 30s)
    const timeoutPromise = this.sleep(30000);
    const inFlightPromise = Promise.all(
      Array.from(this.inFlightSyncs.values())
    );

    await Promise.race([inFlightPromise, timeoutPromise]).catch(() => {
      logger.warn('Some in-flight syncs did not complete within timeout');
    });

    logger.info('CRDTAsyncSyncEngine shutdown complete');
    this.removeAllListeners();
  }
}

/**
 * Async Sync Manager - High-level API
 */
class AsyncSyncManager {
  private engine: CRDTAsyncSyncEngine;

  constructor(nodes: RegionalNode[]) {
    this.engine = new CRDTAsyncSyncEngine(nodes);
    this.setupEventListeners();
  }

  private setupEventListeners(): void {
    this.engine.on('sync-enqueued', (data) => {
      logger.debug('Event enqueued: %s', data.eventId);
    });

    this.engine.on('sync-complete', (result) => {
      logger.info('Sync complete with %s resolution: %s',
        result.resolutionStrategy, result.success ? 'OK' : 'FAILED');
    });

    this.engine.on('sync-error', (data) => {
      logger.error('Sync error for %s: %s', data.eventId, data.error);
    });

    this.engine.on('health-check-failed', (data) => {
      logger.warn('Health check failed for region: %s', data.region);
    });
  }

  /**
   * Increment a counter across all regions
   */
  async incrementCounter(
    key: string,
    value: number,
    originRegion: string
  ): Promise<string> {
    return this.engine.enqueueSync({
      region: originRegion,
      operation: 'update',
      dataType: 'counter',
      key,
      value,
    });
  }

  /**
   * Add element to a set across all regions
   */
  async addToSet(
    key: string,
    element: string,
    originRegion: string
  ): Promise<string> {
    return this.engine.enqueueSync({
      region: originRegion,
      operation: 'insert',
      dataType: 'set',
      key,
      value: { element, isAdded: true },
    });
  }

  /**
   * Remove element from set
   */
  async removeFromSet(
    key: string,
    element: string,
    originRegion: string
  ): Promise<string> {
    return this.engine.enqueueSync({
      region: originRegion,
      operation: 'update',
      dataType: 'set',
      key,
      value: { element, isAdded: false },
    });
  }

  /**
   * Update a register (simple value) across all regions
   */
  async updateRegister(
    key: string,
    value: any,
    originRegion: string
  ): Promise<string> {
    return this.engine.enqueueSync({
      region: originRegion,
      operation: 'update',
      dataType: 'register',
      key,
      value,
    });
  }

  /**
   * Get metrics
   */
  getMetrics() {
    return this.engine.getMetrics();
  }

  /**
   * Start health checks
   */
  async startHealthChecks(): Promise<void> {
    return this.engine.startHealthChecks();
  }

  /**
   * Shutdown
   */
  async shutdown(): Promise<void> {
    return this.engine.shutdown();
  }
}

// Export for use in other modules
export { CRDTAsyncSyncEngine, AsyncSyncManager, SyncEvent, SyncResult, RegionalNode };
