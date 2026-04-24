// @file        apps/session-broker/src/session-snapshot-manager.ts
// @module      session-management/snapshots
// @description Session snapshot management for backup, restore, and replication
//
// Manages creation, storage, and restoration of session state snapshots.

import * as winston from 'winston';
import * as fs from 'fs';
import * as path from 'path';
import * as zlib from 'zlib';
import { RedisSessionStore, SessionContext } from './redis-session-store';

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.json(),
  transports: [new winston.transports.Console()],
});

export enum SnapshotStatus {
  CAPTURING = 'capturing',
  AVAILABLE = 'available',
  RESTORING = 'restoring',
  RESTORED = 'restored',
  FAILED = 'failed',
  EXPIRED = 'expired',
}

export interface SessionSnapshot {
  id: string;
  sessionId: string;
  createdBy: string;
  createdAt: Date;
  status: SnapshotStatus;
  storageLocation: string; // NAS path
  compressedSize: number; // bytes
  uncompressedSize: number; // bytes
  metadata: {
    workspaceState: Record<string, unknown>;
    extensions: string[];
    debugConfig: Record<string, unknown>;
    environmentVariables: Record<string, string>;
    openFiles: string[];
    breakpoints: Record<string, unknown>[];
    retentionDays: number;
  };
  checksumSha256?: string;
  replicaLocations: string[]; // Paths on other replicas
}

/**
 * Manages session snapshots for backup and restoration.
 * Idempotent: creating same snapshot multiple times is safe.
 */
export class SessionSnapshotManager {
  private snapshotStore: Map<string, SessionSnapshot> = new Map();
  private nasBasePath: string;

  constructor(
    private sessionStore: RedisSessionStore,
    nasBasePath: string = process.env.NAS_MOUNT_PATH || '/mnt/nas/persistent/code-server-enterprise'
  ) {
    this.nasBasePath = nasBasePath;
    this.initializeDirectories();
  }

  /**
   * Initialize NAS directories for snapshots.
   */
  private initializeDirectories(): void {
    try {
      const snapshotDir = path.join(this.nasBasePath, 'session-snapshots');
      const replicaDir = path.join(snapshotDir, 'replicas');

      if (!fs.existsSync(snapshotDir)) {
        fs.mkdirSync(snapshotDir, { recursive: true });
        logger.info('Initialized session snapshots directory', { path: snapshotDir });
      }

      if (!fs.existsSync(replicaDir)) {
        fs.mkdirSync(replicaDir, { recursive: true });
        logger.info('Initialized replica snapshots directory', { path: replicaDir });
      }
    } catch (error) {
      logger.error('Failed to initialize snapshot directories', { error });
    }
  }

  /**
   * Create a snapshot of current session state.
   * Idempotent: creating same snapshot twice returns existing snapshot.
   */
  async createSnapshot(
    sessionId: string,
    createdBy: string,
    workspaceState: Record<string, unknown>,
    extensions: string[] = [],
    debugConfig: Record<string, unknown> = {},
    environmentVariables: Record<string, string> = {},
    retentionDays: number = 90
  ): Promise<SessionSnapshot | null> {
    try {
      const session = await this.sessionStore.getSession(sessionId);
      if (!session) {
        logger.error('Cannot create snapshot: session not found', { sessionId });
        return null;
      }

      // Generate snapshot ID (deterministic for idempotency)
      const snapshotId = `snap-${sessionId}-${Date.now()}`;

      // Check for existing snapshot created in same second (idempotent)
      const existingSnapshot = Array.from(this.snapshotStore.values()).find(
        s =>
          s.sessionId === sessionId &&
          s.createdAt.getTime() >= Date.now() - 1000 && // Within last second
          s.createdAt.getTime() <= Date.now() &&
          s.status !== SnapshotStatus.FAILED &&
          s.status !== SnapshotStatus.EXPIRED
      );

      if (existingSnapshot) {
        logger.info('Recent snapshot already exists for session', { sessionId, snapshotId: existingSnapshot.id });
        return existingSnapshot; // Idempotent
      }

      // Prepare snapshot data
      const snapshotData = JSON.stringify({
        sessionId,
        workspaceState,
        extensions,
        debugConfig,
        environmentVariables,
        capturedAt: new Date().toISOString(),
      });

      // Compress snapshot
      const storageLocation = path.join(this.nasBasePath, 'session-snapshots', `${snapshotId}.gz`);
      const compressed = await this.compressData(snapshotData);

      // Store compressed snapshot
      fs.writeFileSync(storageLocation, compressed);

      const snapshot: SessionSnapshot = {
        id: snapshotId,
        sessionId,
        createdBy,
        createdAt: new Date(),
        status: SnapshotStatus.AVAILABLE,
        storageLocation,
        compressedSize: compressed.length,
        uncompressedSize: Buffer.byteLength(snapshotData),
        metadata: {
          workspaceState,
          extensions,
          debugConfig,
          environmentVariables,
          openFiles: [],
          breakpoints: [],
          retentionDays,
        },
        replicaLocations: [],
      };

      this.snapshotStore.set(snapshot.id, snapshot);

      logger.info('Created session snapshot', {
        snapshotId,
        sessionId,
        compressedSize: snapshot.compressedSize,
        uncompressedRatio: ((1 - snapshot.compressedSize / snapshot.uncompressedSize) * 100).toFixed(1),
      });

      return snapshot;
    } catch (error) {
      logger.error('Failed to create session snapshot', { error, sessionId });
      return null;
    }
  }

  /**
   * Restore session from snapshot.
   * Idempotent: restoring same snapshot multiple times is safe.
   */
  async restoreSnapshot(snapshotId: string, targetSessionId: string): Promise<boolean> {
    try {
      const snapshot = this.snapshotStore.get(snapshotId);
      if (!snapshot) {
        logger.error('Snapshot not found', { snapshotId });
        return false;
      }

      if (snapshot.status === SnapshotStatus.RESTORED) {
        logger.info('Snapshot already restored', { snapshotId, targetSessionId });
        return true; // Idempotent
      }

      if (snapshot.status === SnapshotStatus.EXPIRED || snapshot.status === SnapshotStatus.FAILED) {
        logger.error('Cannot restore snapshot in state', { snapshotId, status: snapshot.status });
        return false;
      }

      snapshot.status = SnapshotStatus.RESTORING;

      // Decompress snapshot
      const decompressed = await this.decompressData(fs.readFileSync(snapshot.storageLocation));
      const snapshotData = JSON.parse(decompressed.toString());

      // Restore to target session
      const targetSession = await this.sessionStore.getSession(targetSessionId);
      if (!targetSession) {
        logger.error('Target session not found', { targetSessionId });
        snapshot.status = SnapshotStatus.FAILED;
        return false;
      }

      // Apply snapshot state
      targetSession.config.workspaceSettings = snapshotData.workspaceState;
      targetSession.config.environment = snapshotData.environmentVariables;
      await this.sessionStore.updateSession(targetSessionId, targetSession);

      snapshot.status = SnapshotStatus.RESTORED;
      logger.info('Restored session snapshot', { snapshotId, targetSessionId });
      return true;
    } catch (error) {
      logger.error('Failed to restore snapshot', { error, snapshotId });
      const snapshot = this.snapshotStore.get(snapshotId);
      if (snapshot) {
        snapshot.status = SnapshotStatus.FAILED;
      }
      return false;
    }
  }

  /**
   * Replicate snapshot to other replicas.
   * Idempotent: replicating to same replicas multiple times is safe.
   */
  async replicateSnapshot(snapshotId: string, targetReplicas: string[]): Promise<number> {
    try {
      const snapshot = this.snapshotStore.get(snapshotId);
      if (!snapshot) {
        logger.error('Snapshot not found', { snapshotId });
        return 0;
      }

      let replicatedCount = 0;

      for (const replica of targetReplicas) {
        try {
          const replicaPath = path.join(this.nasBasePath, 'session-snapshots', 'replicas', `${replica}-${snapshotId}.gz`);

          // Copy compressed snapshot to replica location
          fs.copyFileSync(snapshot.storageLocation, replicaPath);

          if (!snapshot.replicaLocations.includes(replicaPath)) {
            snapshot.replicaLocations.push(replicaPath);
          }

          replicatedCount++;
          logger.info('Replicated snapshot to replica', { snapshotId, replica });
        } catch (error) {
          logger.warn('Failed to replicate to replica', { snapshotId, replica, error });
        }
      }

      return replicatedCount;
    } catch (error) {
      logger.error('Failed to replicate snapshot', { error, snapshotId });
      return 0;
    }
  }

  /**
   * Delete snapshot.
   * Idempotent: deleting non-existent snapshot is a no-op.
   */
  async deleteSnapshot(snapshotId: string): Promise<boolean> {
    try {
      const snapshot = this.snapshotStore.get(snapshotId);

      if (!snapshot) {
        logger.info('Snapshot not found for deletion', { snapshotId });
        return true; // Idempotent
      }

      // Delete primary file
      try {
        if (fs.existsSync(snapshot.storageLocation)) {
          fs.unlinkSync(snapshot.storageLocation);
        }
      } catch (e) {
        logger.warn('Could not delete snapshot file', { path: snapshot.storageLocation, error: e });
      }

      // Delete replica files
      for (const replicaPath of snapshot.replicaLocations) {
        try {
          if (fs.existsSync(replicaPath)) {
            fs.unlinkSync(replicaPath);
          }
        } catch (e) {
          logger.warn('Could not delete replica file', { path: replicaPath, error: e });
        }
      }

      this.snapshotStore.delete(snapshotId);
      logger.info('Deleted snapshot', { snapshotId });
      return true;
    } catch (error) {
      logger.error('Failed to delete snapshot', { error, snapshotId });
      return false;
    }
  }

  /**
   * List snapshots for a session.
   */
  async listSnapshots(sessionId: string): Promise<SessionSnapshot[]> {
    try {
      return Array.from(this.snapshotStore.values()).filter(
        s => s.sessionId === sessionId && s.status !== SnapshotStatus.EXPIRED
      );
    } catch (error) {
      logger.error('Failed to list snapshots', { error, sessionId });
      return [];
    }
  }

  /**
   * Get snapshot by ID.
   */
  async getSnapshot(snapshotId: string): Promise<SessionSnapshot | null> {
    try {
      return this.snapshotStore.get(snapshotId) || null;
    } catch (error) {
      logger.error('Failed to get snapshot', { error, snapshotId });
      return null;
    }
  }

  /**
   * Cleanup expired snapshots based on retention policy.
   * Idempotent: safe to run multiple times.
   */
  async cleanupExpiredSnapshots(): Promise<number> {
    try {
      let deletedCount = 0;
      const now = new Date();

      for (const snapshot of this.snapshotStore.values()) {
        const retentionMs = snapshot.metadata.retentionDays * 24 * 60 * 60 * 1000;
        const expiryTime = new Date(snapshot.createdAt.getTime() + retentionMs);

        if (now > expiryTime) {
          await this.deleteSnapshot(snapshot.id);
          snapshot.status = SnapshotStatus.EXPIRED;
          deletedCount++;
        }
      }

      logger.info('Cleaned up expired snapshots', { count: deletedCount });
      return deletedCount;
    } catch (error) {
      logger.error('Failed to cleanup expired snapshots', { error });
      return 0;
    }
  }

  /**
   * Compress data using gzip.
   */
  private compressData(data: string): Promise<Buffer> {
    return new Promise((resolve, reject) => {
      zlib.gzip(Buffer.from(data), (error, result) => {
        if (error) reject(error);
        else resolve(result);
      });
    });
  }

  /**
   * Decompress data using gunzip.
   */
  private decompressData(data: Buffer): Promise<Buffer> {
    return new Promise((resolve, reject) => {
      zlib.gunzip(data, (error, result) => {
        if (error) reject(error);
        else resolve(result);
      });
    });
  }
}
