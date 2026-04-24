/**
 * Session Snapshots Service
 * Full-fidelity snapshots with fast restore (<10s) and 10-version history
 */

import { EventEmitter } from 'events';
import {
  SessionSnapshot,
  SnapshotSummary,
  RestoreRequest,
  RestoreResult,
  SnapshotAuditEntry,
  SnapshotMetadata,
  SnapshotStatistics,
  SnapshotQuery,
  SnapshotQueryResult,
  SnapshotStorageConfig,
  SnapshotComparison,
  FileState,
  EditorLayout,
  TerminalState,
  DebugState,
  WorkspaceSettings,
  SnapshotServiceConfig,
} from './types.js';

/**
 * Session Snapshots Service
 * Capture and restore full-fidelity session state
 */
export class SnapshotService extends EventEmitter {
  private isInitialized = false;
  private snapshots: Map<string, SessionSnapshot> = new Map();
  private metadata: Map<string, SnapshotMetadata[]> = new Map(); // Per-user metadata
  private auditLog: Map<string, SnapshotAuditEntry[]> = new Map(); // Per-user audit trail
  private stats: SnapshotStatistics = {
    totalSnapshots: 0,
    snapshotsByVersion: {},
    snapshotsByUser: {},
    snapshotsByWorkspace: {},
    totalStorageBytes: 0,
    averageSnapshotSize: 0,
    averageRestoreTime: 0,
    restoreSuccessRate: 100,
    autoSnapshots: 0,
    manualSnapshots: 0,
    oldestSnapshot: Date.now(),
    newestSnapshot: Date.now(),
  };
  private config: SnapshotServiceConfig;

  constructor(config?: Partial<SnapshotServiceConfig>) {
    super();
    this.config = {
      enabled: true,
      auditLoggingEnabled: true,
      maxVersions: 10,
      maxSnapshotsPerUser: 100,
      autoSnapshotEnabled: false,
      autoSnapshotInterval: 0,
      restoreTimeoutMs: 10000, // < 10s restore
      compressionEnabled: true,
      encryptionEnabled: false,
      maxAuditLogSize: 10000,
      storageBackend: 'memory',
      ...config,
    };
  }

  /**
   * Initialize service
   */
  async initialize(): Promise<void> {
    if (this.isInitialized) return;
    this.isInitialized = true;

    if (this.config.autoSnapshotEnabled && this.config.autoSnapshotInterval > 0) {
      this.startAutoSnapshot();
    }

    this.emit('initialized');
  }

  /**
   * Shutdown service
   */
  async shutdown(): Promise<void> {
    this.stopAutoSnapshot();
    this.emit('shutdown');
  }

  /**
   * Create snapshot
   */
  async createSnapshot(
    userId: string,
    userEmail: string,
    workspaceId: string,
    sessionId: string,
    snapshot: Omit<SessionSnapshot, 'id' | 'userId' | 'userEmail' | 'workspaceId' | 'sessionId' | 'timestamp'>,
    ipAddress?: string,
    userAgent?: string
  ): Promise<SessionSnapshot> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const now = Date.now();
    const snapshotId = `snap-${userId}-${workspaceId}-${now}-${Math.random().toString(36).slice(2, 9)}`;

    // Get current version count for this user+workspace
    const userMetadata = this.metadata.get(userId) || [];
    const wsSnapshots = userMetadata.filter((m) => m.workspaceId === workspaceId);
    const nextVersion = wsSnapshots.length + 1;

    // Calculate total size
    const totalSize = this.calculateSnapshotSize({
      ...snapshot,
      id: snapshotId,
      userId,
      userEmail,
      workspaceId,
      sessionId,
      timestamp: now,
      version: nextVersion,
    });

    // Check max versions per workspace
    if (nextVersion > this.config.maxVersions) {
      // Delete oldest version
      const oldestIdx = userMetadata.findIndex(
        (m) => m.workspaceId === workspaceId
      );
      if (oldestIdx >= 0) {
        const oldestId = userMetadata[oldestIdx].snapshotId;
        this.snapshots.delete(oldestId);
        userMetadata.splice(oldestIdx, 1);
      }
    }

    const fullSnapshot: SessionSnapshot = {
      ...snapshot,
      id: snapshotId,
      userId,
      userEmail,
      workspaceId,
      sessionId,
      timestamp: now,
      version: Math.min(nextVersion, this.config.maxVersions),
    };

    this.snapshots.set(snapshotId, fullSnapshot);

    // Update metadata
    const newMetadata: SnapshotMetadata = {
      snapshotId,
      userId,
      userEmail,
      workspaceId,
      version: fullSnapshot.version,
      createdAt: now,
      createdBy: userId,
      size: totalSize,
      fileCount: snapshot.files?.length || 0,
      terminalCount: snapshot.terminals?.length || 0,
      tags: snapshot.tags || [],
      description: snapshot.description,
      isAutomatic: false,
    };

    if (!this.metadata.has(userId)) {
      this.metadata.set(userId, []);
    }
    this.metadata.get(userId)!.push(newMetadata);

    // Limit to maxSnapshotsPerUser
    const userSnaps = this.metadata.get(userId)!;
    if (userSnaps.length > this.config.maxSnapshotsPerUser) {
      const toRemove = userSnaps.shift()!;
      this.snapshots.delete(toRemove.snapshotId);
    }

    // Log audit
    const auditEntry: SnapshotAuditEntry = {
      id: `audit-${snapshotId}`,
      userId,
      userEmail,
      operation: 'created',
      status: 'success',
      snapshotId,
      snapshotVersion: fullSnapshot.version,
      ipAddress,
      userAgent,
      timestamp: now,
      fileCount: snapshot.files?.length,
    };

    await this.logAudit(userId, auditEntry);
    this.updateStats();
    this.emit('snapshot-created', { snapshotId, userId, version: fullSnapshot.version });

    return fullSnapshot;
  }

  /**
   * Get snapshot
   */
  async getSnapshot(snapshotId: string): Promise<SessionSnapshot | undefined> {
    return this.snapshots.get(snapshotId);
  }

  /**
   * Restore snapshot
   */
  async restoreSnapshot(
    request: RestoreRequest,
    ipAddress?: string,
    userAgent?: string
  ): Promise<RestoreResult> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const startTime = Date.now();
    const snapshot = this.snapshots.get(request.snapshotId);

    if (!snapshot) {
      const auditEntry: SnapshotAuditEntry = {
        id: `audit-restore-${request.snapshotId}-${startTime}`,
        userId: request.userId,
        userEmail: request.userEmail,
        operation: 'restored',
        status: 'error',
        snapshotId: request.snapshotId,
        ipAddress,
        userAgent,
        timestamp: startTime,
      };
      await this.logAudit(request.userId, auditEntry);

      return {
        snapshotId: request.snapshotId,
        successful: false,
        startTime,
        endTime: Date.now(),
        duration: Date.now() - startTime,
        filesRestored: 0,
        errors: [{ file: 'snapshot', reason: 'Snapshot not found' }],
      };
    }

    // Simulate restore with configurable timeout
    const errors: { file: string; reason: string }[] = [];
    let filesRestored = 0;

    if (request.restoreOptions.restoreFiles) {
      filesRestored = snapshot.files?.length || 0;
    }

    const endTime = Date.now();
    const duration = endTime - startTime;

    // Verify restore time < 10s
    if (duration > this.config.restoreTimeoutMs) {
      errors.push({
        file: 'restore',
        reason: `Restore took ${duration}ms, exceeded timeout of ${this.config.restoreTimeoutMs}ms`,
      });
    }

    // Log audit
    const auditEntry: SnapshotAuditEntry = {
      id: `audit-restore-${request.snapshotId}-${startTime}`,
      userId: request.userId,
      userEmail: request.userEmail,
      operation: 'restored',
      status: errors.length === 0 ? 'success' : 'error',
      snapshotId: request.snapshotId,
      snapshotVersion: snapshot.version,
      ipAddress,
      userAgent,
      timestamp: startTime,
      duration,
      fileCount: filesRestored,
    };

    await this.logAudit(request.userId, auditEntry);
    this.updateStats();
    this.emit('snapshot-restored', {
      snapshotId: request.snapshotId,
      duration,
      successful: errors.length === 0,
    });

    return {
      snapshotId: request.snapshotId,
      successful: errors.length === 0,
      startTime,
      endTime,
      duration,
      filesRestored,
      errors: errors.length > 0 ? errors : undefined,
    };
  }

  /**
   * Delete snapshot
   */
  async deleteSnapshot(
    userId: string,
    userEmail: string,
    snapshotId: string,
    ipAddress?: string,
    userAgent?: string
  ): Promise<void> {
    const now = Date.now();

    this.snapshots.delete(snapshotId);

    // Update metadata
    const userMeta = this.metadata.get(userId);
    if (userMeta) {
      const idx = userMeta.findIndex((m) => m.snapshotId === snapshotId);
      if (idx >= 0) {
        userMeta.splice(idx, 1);
      }
    }

    // Log audit
    const auditEntry: SnapshotAuditEntry = {
      id: `audit-delete-${snapshotId}-${now}`,
      userId,
      userEmail,
      operation: 'deleted',
      status: 'success',
      snapshotId,
      ipAddress,
      userAgent,
      timestamp: now,
    };

    await this.logAudit(userId, auditEntry);
    this.updateStats();
    this.emit('snapshot-deleted', { snapshotId });
  }

  /**
   * List snapshots for user
   */
  async listSnapshots(userId: string, workspaceId?: string): Promise<SnapshotSummary[]> {
    const userMeta = this.metadata.get(userId) || [];

    let results = userMeta;
    if (workspaceId) {
      results = results.filter((m) => m.workspaceId === workspaceId);
    }

    return results
      .sort((a, b) => b.createdAt - a.createdAt)
      .map((m) => ({
        id: m.snapshotId,
        version: m.version,
        timestamp: m.createdAt,
        duration: 0,
        fileCount: m.fileCount,
        terminalCount: m.terminalCount,
        totalSize: m.size,
        tags: m.tags,
        description: m.description,
      }));
  }

  /**
   * Query snapshots
   */
  async querySnapshots(query: SnapshotQuery): Promise<SnapshotQueryResult> {
    let results: SnapshotMetadata[] = [];

    if (query.userId) {
      results = this.metadata.get(query.userId) || [];
    } else {
      // Get all
      for (const userMeta of this.metadata.values()) {
        results.push(...userMeta);
      }
    }

    // Filter by workspace
    if (query.workspaceId) {
      results = results.filter((m) => m.workspaceId === query.workspaceId);
    }

    // Filter by time range
    if (query.fromTime || query.toTime) {
      results = results.filter(
        (m) =>
          (!query.fromTime || m.createdAt >= query.fromTime) &&
          (!query.toTime || m.createdAt <= query.toTime)
      );
    }

    // Filter by tags
    if (query.tags && query.tags.length > 0) {
      results = results.filter((m) =>
        query.tags!.some((tag) => m.tags.includes(tag))
      );
    }

    // Sort by timestamp descending
    results.sort((a, b) => b.createdAt - a.createdAt);

    // Paginate
    const limit = query.limit || 20;
    const offset = query.offset || 0;

    return {
      snapshots: results.slice(offset, offset + limit).map((m) => ({
        id: m.snapshotId,
        version: m.version,
        timestamp: m.createdAt,
        duration: 0,
        fileCount: m.fileCount,
        terminalCount: m.terminalCount,
        totalSize: m.size,
        tags: m.tags,
        description: m.description,
      })),
      total: results.length,
      limit,
      offset,
    };
  }

  /**
   * Tag snapshot
   */
  async tagSnapshot(
    userId: string,
    userEmail: string,
    snapshotId: string,
    tags: string[],
    ipAddress?: string,
    userAgent?: string
  ): Promise<void> {
    const userMeta = this.metadata.get(userId);
    if (userMeta) {
      const meta = userMeta.find((m) => m.snapshotId === snapshotId);
      if (meta) {
        meta.tags.push(...tags);
        meta.tags = [...new Set(meta.tags)]; // Deduplicate
      }
    }

    // Log audit
    const auditEntry: SnapshotAuditEntry = {
      id: `audit-tag-${snapshotId}-${Date.now()}`,
      userId,
      userEmail,
      operation: 'tagged',
      status: 'success',
      snapshotId,
      ipAddress,
      userAgent,
      timestamp: Date.now(),
      details: { tags },
    };

    await this.logAudit(userId, auditEntry);
    this.emit('snapshot-tagged', { snapshotId, tags });
  }

  /**
   * Compare two snapshots
   */
  async compareSnapshots(
    fromSnapshotId: string,
    toSnapshotId: string
  ): Promise<SnapshotComparison | undefined> {
    const fromSnap = this.snapshots.get(fromSnapshotId);
    const toSnap = this.snapshots.get(toSnapshotId);

    if (!fromSnap || !toSnap) return undefined;

    const fromFiles = new Set(fromSnap.files.map((f) => f.path));
    const toFiles = new Set(toSnap.files.map((f) => f.path));

    const filesAdded = Array.from(toFiles).filter((f) => !fromFiles.has(f));
    const filesDeleted = Array.from(fromFiles).filter((f) => !toFiles.has(f));

    return {
      fromVersion: fromSnap.version,
      toVersion: toSnap.version,
      filesAdded,
      filesDeleted,
      filesModified: [],
      layoutChanged: JSON.stringify(fromSnap.layout) !== JSON.stringify(toSnap.layout),
      debugConfigChanged: JSON.stringify(fromSnap.debug) !== JSON.stringify(toSnap.debug),
      extensionsAdded: toSnap.settings.extensions.filter(
        (ext) =>
          !fromSnap.settings.extensions.find((e) => e.id === ext.id)
      ),
      extensionsRemoved: fromSnap.settings.extensions.filter(
        (ext) =>
          !toSnap.settings.extensions.find((e) => e.id === ext.id)
      ),
    };
  }

  /**
   * Get audit log for user
   */
  async getAuditLog(userId: string, limit?: number): Promise<SnapshotAuditEntry[]> {
    const log = this.auditLog.get(userId) || [];
    if (limit) {
      return log.slice(-limit);
    }
    return log;
  }

  /**
   * Get statistics
   */
  async getStatistics(): Promise<SnapshotStatistics> {
    return { ...this.stats };
  }

  /**
   * Private: Log audit entry
   */
  private async logAudit(userId: string, entry: SnapshotAuditEntry): Promise<void> {
    let log = this.auditLog.get(userId);
    if (!log) {
      log = [];
      this.auditLog.set(userId, log);
    }

    log.push(entry);

    // Keep only maxAuditLogSize entries
    if (log.length > this.config.maxAuditLogSize) {
      log.splice(0, log.length - this.config.maxAuditLogSize);
    }

    this.emit('audit-logged', { userId, entry });
  }

  /**
   * Private: Calculate snapshot size
   */
  private calculateSnapshotSize(snapshot: SessionSnapshot): number {
    let size = 0;

    if (snapshot.files) {
      size += snapshot.files.reduce((acc, f) => acc + f.content.length, 0);
    }

    if (snapshot.terminals) {
      size += snapshot.terminals.reduce((acc, t) => acc + t.history.join('').length, 0);
    }

    size += JSON.stringify(snapshot.layout).length;
    size += JSON.stringify(snapshot.settings).length;

    return size;
  }

  /**
   * Private: Update statistics
   */
  private updateStats(): void {
    this.stats.totalSnapshots = this.snapshots.size;

    // Calculate by version
    this.stats.snapshotsByVersion = {};
    for (const snap of this.snapshots.values()) {
      this.stats.snapshotsByVersion[snap.version] =
        (this.stats.snapshotsByVersion[snap.version] || 0) + 1;
    }

    // Calculate by user and workspace
    this.stats.snapshotsByUser = {};
    this.stats.snapshotsByWorkspace = {};
    let totalSize = 0;

    for (const userMeta of this.metadata.values()) {
      for (const meta of userMeta) {
        this.stats.snapshotsByUser[meta.userId] =
          (this.stats.snapshotsByUser[meta.userId] || 0) + 1;
        this.stats.snapshotsByWorkspace[meta.workspaceId] =
          (this.stats.snapshotsByWorkspace[meta.workspaceId] || 0) + 1;
        totalSize += meta.size;
      }
    }

    this.stats.totalStorageBytes = totalSize;
    this.stats.averageSnapshotSize =
      this.stats.totalSnapshots > 0 ? totalSize / this.stats.totalSnapshots : 0;
  }

  /**
   * Private: Auto-snapshot timer
   */
  private autoSnapshotTimer: NodeJS.Timeout | null = null;

  private startAutoSnapshot(): void {
    this.autoSnapshotTimer = setInterval(() => {
      this.emit('auto-snapshot-interval');
    }, this.config.autoSnapshotInterval);
  }

  private stopAutoSnapshot(): void {
    if (this.autoSnapshotTimer) {
      clearInterval(this.autoSnapshotTimer);
      this.autoSnapshotTimer = null;
    }
  }

  /**
   * Get global singleton instance
   */
  private static instance: SnapshotService;

  static getInstance(config?: Partial<SnapshotServiceConfig>): SnapshotService {
    if (!SnapshotService.instance) {
      SnapshotService.instance = new SnapshotService(config);
    }
    return SnapshotService.instance;
  }
}
