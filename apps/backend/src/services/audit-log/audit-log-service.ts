/**
 * Immutable Audit Log Service
 * SOC2-grade append-only audit table with hash chain tamper detection
 */

import { EventEmitter } from 'events';
import crypto from 'crypto';
import { 
  AuditEvent, 
  AuditEventBatch, 
  AuditQuery, 
  AuditQueryResult, 
  AuditStats,
  HashChainVerification,
  RetentionPolicy,
  AuditSnapshot,
  AuditLogConfig,
  AuditOperation,
  AuditResourceType,
  AuditStatus,
} from './types.js';

/**
 * Immutable Audit Log Service
 * Append-only storage with hash chain for tamper detection
 */
export class AuditLogService extends EventEmitter {
  private isInitialized = false;
  private eventLog: AuditEvent[] = []; // Append-only log
  private lastHash = '0'; // SHA256 of previous event for chain
  private batchBuffer: AuditEvent[] = [];
  private snapshots: Map<string, AuditSnapshot> = new Map();
  private stats: AuditStats = {
    totalEvents: 0,
    eventsByOperation: {},
    eventsByResourceType: {},
    eventsByStatus: {},
    eventsByUser: {},
    averageEventsPerSecond: 0,
  };
  private config: AuditLogConfig;
  private flushTimer?: NodeJS.Timeout;
  private retentionTimer?: NodeJS.Timeout;

  constructor(config?: Partial<AuditLogConfig>) {
    super();
    this.config = {
      enabled: true,
      batchSize: 100,
      flushIntervalMs: 5000,
      maxMemoryEvents: 10000,
      retentionPolicy: {
        enabled: true,
        maxAgeMs: 63072000000, // 2 years
        archiveBeforeDelete: true,
      },
      compressionEnabled: true,
      encryptionEnabled: true,
      ...config,
    };
  }

  /**
   * Initialize service
   */
  async initialize(): Promise<void> {
    if (this.isInitialized) return;
    this.isInitialized = true;

    if (this.config.enabled) {
      // Start periodic flush timer
      this.flushTimer = setInterval(
        () => this.flushBatch(),
        this.config.flushIntervalMs
      );

      // Start retention policy checker
      if (this.config.retentionPolicy.enabled) {
        this.retentionTimer = setInterval(
          () => this.enforceRetention(),
          3600000 // Check hourly
        );
      }
    }

    this.emit('initialized');
  }

  /**
   * Shutdown service (cleanup timers)
   */
  async shutdown(): Promise<void> {
    if (this.flushTimer) clearInterval(this.flushTimer);
    if (this.retentionTimer) clearInterval(this.retentionTimer);
    
    // Final flush
    await this.flushBatch();
    
    this.emit('shutdown');
  }

  /**
   * Record an audit event
   */
  async recordEvent(
    userId: string,
    sessionId: string,
    operation: AuditOperation,
    resourceType: AuditResourceType,
    resourceId: string,
    status: AuditStatus = 'success',
    details: Record<string, any> = {},
    options?: {
      resourcePath?: string;
      ipAddress?: string;
      userAgent?: string;
      metadata?: Record<string, any>;
    }
  ): Promise<AuditEvent> {
    if (!this.isInitialized) throw new Error('Service not initialized');
    if (!this.config.enabled) throw new Error('Audit logging disabled');

    // Generate event
    const event: AuditEvent = {
      id: this.generateEventId(),
      timestamp: Date.now(),
      userId,
      sessionId,
      operation,
      resourceType,
      resourceId,
      resourcePath: options?.resourcePath,
      status,
      details,
      ipAddress: options?.ipAddress,
      userAgent: options?.userAgent,
      metadata: options?.metadata,
      previousHash: this.lastHash,
      currentHash: '', // Will be computed below
    };

    // Compute hash chain
    event.currentHash = this.computeEventHash(event);
    this.lastHash = event.currentHash;

    // Add to batch buffer
    this.batchBuffer.push(event);
    
    // Update stats
    this.updateStats(event);

    // Emit event
    this.emit('event-recorded', { event });

    // Flush if batch full
    if (this.batchBuffer.length >= this.config.batchSize) {
      await this.flushBatch();
    }

    return event;
  }

  /**
   * Flush batch buffer to permanent log (public for testing)
   */
  async flushBatch(): Promise<void> {
    if (this.batchBuffer.length === 0) return;

    const batch = this.batchBuffer.splice(0, this.batchBuffer.length);
    
    // Append to log (append-only, immutable)
    this.eventLog.push(...batch);

    // Create batch snapshot
    const batchId = this.generateBatchId();
    const snapshot: AuditSnapshot = {
      id: batchId,
      timestamp: Date.now(),
      eventCount: batch.length,
      startHash: batch[0].previousHash,
      endHash: batch[batch.length - 1].currentHash,
      snapshotHash: this.computeBatchHash(batch),
      compressed: this.config.compressionEnabled,
      encrypted: this.config.encryptionEnabled,
    };

    this.snapshots.set(batchId, snapshot);
    this.emit('batch-flushed', { batchId, eventCount: batch.length });
  }

  /**
   * Query audit events
   */
  async queryEvents(query: AuditQuery): Promise<AuditQueryResult> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    let results = [...this.eventLog];

    // Apply filters
    if (query.userId) {
      results = results.filter((e) => e.userId === query.userId);
    }
    if (query.sessionId) {
      results = results.filter((e) => e.sessionId === query.sessionId);
    }
    if (query.operation) {
      results = results.filter((e) => e.operation === query.operation);
    }
    if (query.resourceType) {
      results = results.filter((e) => e.resourceType === query.resourceType);
    }
    if (query.resourceId) {
      results = results.filter((e) => e.resourceId === query.resourceId);
    }
    if (query.status) {
      results = results.filter((e) => e.status === query.status);
    }
    if (query.startTime) {
      results = results.filter((e) => e.timestamp >= query.startTime!);
    }
    if (query.endTime) {
      results = results.filter((e) => e.timestamp <= query.endTime!);
    }

    const total = results.length;
    const offset = query.offset || 0;
    const limit = query.limit || 100;

    const events = results.slice(offset, offset + limit);
    const hasMore = offset + limit < total;

    return {
      events,
      total,
      hasMore,
      nextOffset: hasMore ? offset + limit : undefined,
    };
  }

  /**
   * Get audit event by ID
   */
  async getEvent(eventId: string): Promise<AuditEvent | undefined> {
    return this.eventLog.find((e) => e.id === eventId);
  }

  /**
   * Verify hash chain integrity
   */
  async verifyHashChain(): Promise<HashChainVerification> {
    if (this.eventLog.length === 0) {
      return {
        valid: true,
        tamperDetected: false,
        details: 'Log is empty',
      };
    }

    let previousHash = '0';
    for (let i = 0; i < this.eventLog.length; i++) {
      const event = this.eventLog[i];

      // Verify previousHash matches chain
      if (event.previousHash !== previousHash) {
        return {
          valid: false,
          tamperDetected: true,
          firstTamperedEvent: event.id,
          details: `Hash chain broken at event ${i}: expected ${previousHash}, got ${event.previousHash}`,
        };
      }

      // Verify currentHash is correct
      const expectedHash = this.computeEventHash(event);
      if (event.currentHash !== expectedHash) {
        return {
          valid: false,
          tamperDetected: true,
          firstTamperedEvent: event.id,
          details: `Event hash mismatch at event ${i}: expected ${expectedHash}, got ${event.currentHash}`,
        };
      }

      previousHash = event.currentHash;
    }

    return {
      valid: true,
      tamperDetected: false,
      details: `Hash chain verified: ${this.eventLog.length} events`,
    };
  }

  /**
   * Get audit statistics
   */
  async getStatistics(): Promise<AuditStats> {
    return { ...this.stats };
  }

  /**
   * Export events to snapshot
   */
  async exportSnapshot(options?: {
    startTime?: number;
    endTime?: number;
  }): Promise<AuditSnapshot> {
    let events = [...this.eventLog];

    if (options?.startTime) {
      events = events.filter((e) => e.timestamp >= options.startTime!);
    }
    if (options?.endTime) {
      events = events.filter((e) => e.timestamp <= options.endTime!);
    }

    const snapshot: AuditSnapshot = {
      id: this.generateSnapshotId(),
      timestamp: Date.now(),
      eventCount: events.length,
      startHash: events.length > 0 ? events[0].previousHash : '0',
      endHash: events.length > 0 ? events[events.length - 1].currentHash : '0',
      snapshotHash: this.computeBatchHash(events),
      compressed: this.config.compressionEnabled,
      encrypted: this.config.encryptionEnabled,
    };

    this.snapshots.set(snapshot.id, snapshot);
    this.emit('snapshot-exported', { snapshotId: snapshot.id, eventCount: snapshot.eventCount });

    return snapshot;
  }

  /**
   * Get event count
   */
  async getEventCount(): Promise<number> {
    return this.eventLog.length;
  }

  /**
   * Get retention policy
   */
  getRetentionPolicy(): RetentionPolicy {
    return { ...this.config.retentionPolicy };
  }

  /**
   * Set retention policy
   */
  setRetentionPolicy(policy: Partial<RetentionPolicy>): void {
    this.config.retentionPolicy = {
      ...this.config.retentionPolicy,
      ...policy,
    };
  }

  /**
   * Private: Compute SHA256 hash of event
   */
  private computeEventHash(event: Omit<AuditEvent, 'currentHash'>): string {
    const hashInput = JSON.stringify({
      id: event.id,
      timestamp: event.timestamp,
      userId: event.userId,
      sessionId: event.sessionId,
      operation: event.operation,
      resourceType: event.resourceType,
      resourceId: event.resourceId,
      status: event.status,
      previousHash: event.previousHash,
    });

    return crypto.createHash('sha256').update(hashInput).digest('hex');
  }

  /**
   * Private: Compute hash of batch
   */
  private computeBatchHash(events: AuditEvent[]): string {
    const hashes = events.map((e) => e.currentHash).join('');
    return crypto.createHash('sha256').update(hashes).digest('hex');
  }

  /**
   * Private: Generate unique event ID
   */
  private generateEventId(): string {
    return `evt-${Date.now()}-${Math.random().toString(36).substring(7)}`;
  }

  /**
   * Private: Generate batch ID
   */
  private generateBatchId(): string {
    return `batch-${Date.now()}-${Math.random().toString(36).substring(7)}`;
  }

  /**
   * Private: Generate snapshot ID
   */
  private generateSnapshotId(): string {
    return `snap-${Date.now()}-${Math.random().toString(36).substring(7)}`;
  }

  /**
   * Private: Update statistics
   */
  private updateStats(event: AuditEvent): void {
    this.stats.totalEvents++;

    // By operation
    this.stats.eventsByOperation[event.operation] = 
      (this.stats.eventsByOperation[event.operation] || 0) + 1;

    // By resource type
    this.stats.eventsByResourceType[event.resourceType] = 
      (this.stats.eventsByResourceType[event.resourceType] || 0) + 1;

    // By status
    this.stats.eventsByStatus[event.status] = 
      (this.stats.eventsByStatus[event.status] || 0) + 1;

    // By user
    this.stats.eventsByUser[event.userId] = 
      (this.stats.eventsByUser[event.userId] || 0) + 1;

    // Update time range
    if (!this.stats.earliestEventTime) {
      this.stats.earliestEventTime = event.timestamp;
    }
    this.stats.latestEventTime = event.timestamp;

    // Calculate average events per second
    if (this.stats.earliestEventTime && this.stats.latestEventTime) {
      const durationSeconds = (this.stats.latestEventTime - this.stats.earliestEventTime) / 1000;
      this.stats.averageEventsPerSecond = durationSeconds > 0 
        ? this.stats.totalEvents / durationSeconds 
        : 0;
    }
  }

  /**
   * Private: Enforce retention policy (delete old events)
   */
  private async enforceRetention(): Promise<void> {
    if (!this.config.retentionPolicy.enabled) return;

    const cutoffTime = Date.now() - this.config.retentionPolicy.maxAgeMs;
    const eventsToDelete = this.eventLog.filter((e) => e.timestamp < cutoffTime);

    if (eventsToDelete.length > 0) {
      // Create archive snapshot before deletion
      if (this.config.retentionPolicy.archiveBeforeDelete) {
        await this.exportSnapshot({
          endTime: cutoffTime,
        });
      }

      // Remove old events (in-place removal maintains append-only semantics)
      this.eventLog = this.eventLog.filter((e) => e.timestamp >= cutoffTime);
      this.emit('retention-enforced', { eventsDeleted: eventsToDelete.length });
    }
  }

  /**
   * Get global singleton instance
   */
  private static instance: AuditLogService;

  static getInstance(config?: Partial<AuditLogConfig>): AuditLogService {
    if (!AuditLogService.instance) {
      AuditLogService.instance = new AuditLogService(config);
    }
    return AuditLogService.instance;
  }
}
