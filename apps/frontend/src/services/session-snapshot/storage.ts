/**
 * @file        apps/frontend/src/services/session-snapshot/storage.ts
 * @module      collaboration/session-persistence
 * @description IndexedDB storage layer for session snapshots with version management
 */

import { SessionSnapshot, SnapshotMetadata } from './types.js';

/**
 * IndexedDB schema configuration
 */
export const SNAPSHOT_DB_CONFIG = {
  name: 'code-server-snapshots',
  version: 1,
  stores: {
    snapshots: {
      keyPath: 'id',
      indexes: [
        { name: 'workspaceId', keyPath: 'workspaceId' },
        { name: 'createdAt', keyPath: 'createdAt' },
        { name: 'workspaceId_version', keyPath: ['workspaceId', 'version'] },
      ],
    },
  },
};

/**
 * SessionSnapshotStorage: Manages snapshot persistence with 10-version history
 */
export class SessionSnapshotStorage {
  private db: IDBDatabase | null = null;
  private isInitialized = false;
  private readonly MAX_VERSIONS_PER_WORKSPACE = 10;

  /**
   * Initialize IndexedDB connection
   */
  async initialize(): Promise<void> {
    if (this.isInitialized) return;

    return new Promise((resolve, reject) => {
      const request = indexedDB.open(
        SNAPSHOT_DB_CONFIG.name,
        SNAPSHOT_DB_CONFIG.version
      );

      request.onerror = () => {
        console.error('[SessionSnapshotStorage] Failed to open IndexedDB:', request.error);
        reject(request.error);
      };

      request.onsuccess = () => {
        this.db = request.result;
        this.isInitialized = true;
        console.log('[SessionSnapshotStorage] Initialized');
        resolve();
      };

      request.onupgradeneeded = (event) => {
        const db = (event.target as IDBOpenDBRequest).result;

        if (!db.objectStoreNames.contains('snapshots')) {
          const store = db.createObjectStore('snapshots', {
            keyPath: SNAPSHOT_DB_CONFIG.stores.snapshots.keyPath,
          });

          // Create indexes
          SNAPSHOT_DB_CONFIG.stores.snapshots.indexes.forEach((index) => {
            store.createIndex(index.name, index.keyPath as any, { unique: false });
          });
        }
      };
    });
  }

  /**
   * Save snapshot (auto-prune old versions)
   */
  async saveSnapshot(snapshot: SessionSnapshot): Promise<void> {
    if (!this.db) throw new Error('Storage not initialized');

    // Generate unique ID with version
    snapshot.id = `snap-${snapshot.workspaceId}-${Date.now()}-${Math.random().toString(36).substring(7)}`;
    snapshot.updatedAt = Date.now();

    return new Promise((resolve, reject) => {
      const tx = this.db!.transaction(['snapshots'], 'readwrite');
      const store = tx.objectStore('snapshots');

      // Save new snapshot
      const putRequest = store.put(snapshot);

      putRequest.onerror = () => {
        console.error('[SessionSnapshotStorage] Failed to save snapshot:', putRequest.error);
        reject(putRequest.error);
      };

      putRequest.onsuccess = () => {
        console.log(
          `[SessionSnapshotStorage] Saved snapshot ${snapshot.id} for workspace ${snapshot.workspaceId}`
        );

        // After successful save, prune old versions asynchronously
        this.pruneOldVersions(snapshot.workspaceId);

        resolve();
      };
    });
  }

  /**
   * Load specific snapshot
   */
  async loadSnapshot(snapshotId: string): Promise<SessionSnapshot | null> {
    if (!this.db) throw new Error('Storage not initialized');

    return new Promise((resolve, reject) => {
      const tx = this.db!.transaction(['snapshots'], 'readonly');
      const store = tx.objectStore('snapshots');
      const request = store.get(snapshotId);

      request.onerror = () => {
        console.error('[SessionSnapshotStorage] Failed to load snapshot:', request.error);
        reject(request.error);
      };

      request.onsuccess = () => {
        const snapshot = request.result;
        if (snapshot) {
          console.log(`[SessionSnapshotStorage] Loaded snapshot ${snapshotId}`);
        }
        resolve(snapshot || null);
      };
    });
  }

  /**
   * List all snapshots for workspace with pagination
   */
  async listSnapshots(
    workspaceId: string,
    page = 1,
    pageSize = 10
  ): Promise<{ snapshots: SnapshotMetadata[]; total: number }> {
    if (!this.db) throw new Error('Storage not initialized');

    return new Promise((resolve, reject) => {
      const tx = this.db!.transaction(['snapshots'], 'readonly');
      const store = tx.objectStore('snapshots');
      const index = store.index('workspaceId');
      const range = IDBKeyRange.only(workspaceId);
      const request = index.getAll(range);

      request.onerror = () => {
        console.error('[SessionSnapshotStorage] Failed to list snapshots:', request.error);
        reject(request.error);
      };

      request.onsuccess = () => {
        const all = request.result as SessionSnapshot[];

        // Sort by createdAt descending (newest first)
        all.sort((a, b) => b.createdAt - a.createdAt);

        // Paginate
        const total = all.length;
        const start = (page - 1) * pageSize;
        const end = start + pageSize;
        const paged = all.slice(start, end);

        // Convert to metadata
        const metadata: SnapshotMetadata[] = paged.map((snap) => ({
          id: snap.id,
          workspaceId: snap.workspaceId,
          createdAt: snap.createdAt,
          label: snap.label,
          version: snap.version,
          fileCount: snap.openFiles.length,
          terminalCount: snap.terminals.length,
          size: snap.size,
          estimatedRestoreTimeMs: snap.estimatedRestoreTimeMs,
        }));

        console.log(
          `[SessionSnapshotStorage] Listed ${metadata.length}/${total} snapshots for workspace ${workspaceId}`
        );

        resolve({ snapshots: metadata, total });
      };
    });
  }

  /**
   * Delete specific snapshot
   */
  async deleteSnapshot(snapshotId: string): Promise<void> {
    if (!this.db) throw new Error('Storage not initialized');

    return new Promise((resolve, reject) => {
      const tx = this.db!.transaction(['snapshots'], 'readwrite');
      const store = tx.objectStore('snapshots');
      const request = store.delete(snapshotId);

      request.onerror = () => {
        console.error('[SessionSnapshotStorage] Failed to delete snapshot:', request.error);
        reject(request.error);
      };

      request.onsuccess = () => {
        console.log(`[SessionSnapshotStorage] Deleted snapshot ${snapshotId}`);
        resolve();
      };
    });
  }

  /**
   * Prune old versions, keeping only 10 most recent per workspace
   */
  private async pruneOldVersions(workspaceId: string): Promise<void> {
    if (!this.db) return;

    try {
      const tx = this.db.transaction(['snapshots'], 'readwrite');
      const store = tx.objectStore('snapshots');
      const index = store.index('workspaceId');
      const range = IDBKeyRange.only(workspaceId);
      const request = index.getAll(range);

      request.onsuccess = () => {
        const all = request.result as SessionSnapshot[];
        all.sort((a, b) => b.createdAt - a.createdAt);

        // Delete versions beyond the 10-version limit
        if (all.length > this.MAX_VERSIONS_PER_WORKSPACE) {
          const toDelete = all.slice(this.MAX_VERSIONS_PER_WORKSPACE);
          toDelete.forEach((snap) => {
            store.delete(snap.id);
          });

          console.log(
            `[SessionSnapshotStorage] Pruned ${toDelete.length} old snapshots for workspace ${workspaceId}, keeping ${this.MAX_VERSIONS_PER_WORKSPACE}`
          );
        }
      };
    } catch (error) {
      console.error('[SessionSnapshotStorage] Error during pruning:', error);
      // Don't throw - pruning is best-effort cleanup
    }
  }

  /**
   * Clear all snapshots for workspace
   */
  async clearWorkspaceSnapshots(workspaceId: string): Promise<void> {
    if (!this.db) throw new Error('Storage not initialized');

    return new Promise((resolve, reject) => {
      const tx = this.db!.transaction(['snapshots'], 'readwrite');
      const store = tx.objectStore('snapshots');
      const index = store.index('workspaceId');
      const range = IDBKeyRange.only(workspaceId);
      const request = index.openCursor(range);

      const deletedCount = { count: 0 };

      request.onerror = () => {
        console.error('[SessionSnapshotStorage] Failed to clear snapshots:', request.error);
        reject(request.error);
      };

      request.onsuccess = () => {
        const cursor = request.result;
        if (cursor) {
          cursor.delete();
          deletedCount.count++;
          cursor.continue();
        } else {
          console.log(
            `[SessionSnapshotStorage] Cleared ${deletedCount.count} snapshots for workspace ${workspaceId}`
          );
          resolve();
        }
      };
    });
  }

  /**
   * Get storage statistics
   */
  async getStats(): Promise<{
    totalSnapshots: number;
    totalSizeBytes: number;
    workspaceStats: Array<{ workspaceId: string; count: number; sizeBytes: number }>;
  }> {
    if (!this.db) throw new Error('Storage not initialized');

    return new Promise((resolve, reject) => {
      const tx = this.db!.transaction(['snapshots'], 'readonly');
      const store = tx.objectStore('snapshots');
      const request = store.getAll();

      request.onerror = () => {
        reject(request.error);
      };

      request.onsuccess = () => {
        const all = request.result as SessionSnapshot[];
        const workspaceMap = new Map<
          string,
          { count: number; sizeBytes: number }
        >();

        let totalSize = 0;

        all.forEach((snap) => {
          const size = snap.size || 0;
          totalSize += size;

          if (!workspaceMap.has(snap.workspaceId)) {
            workspaceMap.set(snap.workspaceId, { count: 0, sizeBytes: 0 });
          }

          const stat = workspaceMap.get(snap.workspaceId)!;
          stat.count++;
          stat.sizeBytes += size;
        });

        const workspaceStats = Array.from(workspaceMap.entries()).map(
          ([workspaceId, { count, sizeBytes }]) => ({
            workspaceId,
            count,
            sizeBytes,
          })
        );

        resolve({
          totalSnapshots: all.length,
          totalSizeBytes: totalSize,
          workspaceStats,
        });
      };
    });
  }
}

/**
 * Global storage instance
 */
let storageInstance: SessionSnapshotStorage | null = null;

/**
 * Get global storage instance
 */
export async function getSessionSnapshotStorage(): Promise<SessionSnapshotStorage> {
  if (!storageInstance) {
    storageInstance = new SessionSnapshotStorage();
    await storageInstance.initialize();
  }
  return storageInstance;
}
