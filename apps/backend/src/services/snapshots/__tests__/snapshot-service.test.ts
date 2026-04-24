/**
 * Session Snapshots Service Tests
 * Test coverage for snapshot creation, restore, and management
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { SnapshotService } from '../snapshot-service.js';
import { SessionSnapshot } from '../types.js';

describe('SnapshotService', () => {
  let service: SnapshotService;

  const createTestSnapshot = (): Omit<SessionSnapshot, 'id' | 'userId' | 'userEmail' | 'workspaceId' | 'sessionId' | 'timestamp'> => ({
    version: 1,
    duration: 3600000,
    files: [
      { path: '/src/main.ts', content: 'export const main = () => {}', encoding: 'utf8', isModified: false, isUnsaved: false, lastModified: Date.now() },
      { path: '/src/utils.ts', content: 'export const util = () => {}', encoding: 'utf8', isModified: false, isUnsaved: false, lastModified: Date.now() },
    ],
    layout: {
      groups: [
        {
          id: 'group1',
          size: 0.5,
          editors: [
            { id: 'editor1', path: '/src/main.ts', isActive: true, position: 0 },
          ],
        },
      ],
    },
    terminals: [
      { id: 'term1', name: 'Terminal 1', shellPath: '/bin/bash', shellArgs: [], cwd: '/workspace', history: ['npm start'], isActive: true, lines: 100 },
    ],
    settings: {
      theme: 'dark',
      fontSize: 14,
      fontFamily: 'Fira Code',
      formatOnSave: true,
      tabSize: 2,
      wordWrap: true,
      extensions: [],
    },
    metadata: {
      osType: 'linux',
      vscodeVersion: '1.87.0',
      workspacePath: '/workspace',
      totalFileSize: 1024,
      fileCount: 2,
    },
  });

  beforeEach(async () => {
    service = new SnapshotService();
    await service.initialize();
  });

  afterEach(async () => {
    await service.shutdown();
  });

  // ==================== Initialization Tests ====================

  it('should initialize successfully', async () => {
    expect(service).toBeDefined();
    const stats = await service.getStatistics();
    expect(stats.totalSnapshots).toBe(0);
  });

  it('should emit initialized event', () => {
    return new Promise<void>((resolve) => {
      const newService = new SnapshotService();
      newService.once('initialized', () => {
        resolve();
      });
      newService.initialize();
    });
  });

  it('should emit shutdown event', () => {
    return new Promise<void>((resolve) => {
      const newService = new SnapshotService();
      newService.initialize().then(() => {
        newService.once('shutdown', () => {
          resolve();
        });
        newService.shutdown();
      });
    });
  });

  // ==================== Create Snapshot Tests ====================

  it('should create snapshot', async () => {
    const snap = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    expect(snap.userId).toBe('user1');
    expect(snap.workspaceId).toBe('workspace1');
    expect(snap.files).toHaveLength(2);
  });

  it('should emit snapshot-created event', () => {
    return new Promise<void>((resolve) => {
      service.once('snapshot-created', (data) => {
        expect(data.userId).toBe('user1');
        resolve();
      });
      service.createSnapshot(
        'user1',
        'user1@example.com',
        'workspace1',
        'session1',
        createTestSnapshot()
      );
    });
  });

  it('should assign unique snapshot IDs', async () => {
    const snap1 = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    await new Promise((resolve) => setTimeout(resolve, 1));

    const snap2 = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    expect(snap1.id).not.toBe(snap2.id);
  });

  it('should increment version numbers', async () => {
    const snap1 = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    const snap2 = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    expect(snap2.version).toBeGreaterThan(snap1.version);
  });

  it('should track file count in metadata', async () => {
    const snap = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      {
        ...createTestSnapshot(),
        files: [
          { path: '/src/a.ts', content: 'a', encoding: 'utf8', isModified: false, isUnsaved: false, lastModified: Date.now() },
          { path: '/src/b.ts', content: 'b', encoding: 'utf8', isModified: false, isUnsaved: false, lastModified: Date.now() },
          { path: '/src/c.ts', content: 'c', encoding: 'utf8', isModified: false, isUnsaved: false, lastModified: Date.now() },
        ],
      }
    );

    expect(snap.files).toHaveLength(3);
  });

  // ==================== Get Snapshot Tests ====================

  it('should retrieve snapshot by ID', async () => {
    const created = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    const retrieved = await service.getSnapshot(created.id);
    expect(retrieved?.id).toBe(created.id);
  });

  it('should return undefined for missing snapshot', async () => {
    const snap = await service.getSnapshot('nonexistent');
    expect(snap).toBeUndefined();
  });

  // ==================== Restore Snapshot Tests ====================

  it('should restore snapshot', async () => {
    const snap = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    const result = await service.restoreSnapshot({
      userId: 'user1',
      userEmail: 'user1@example.com',
      snapshotId: snap.id,
      restoreOptions: {
        restoreFiles: true,
        restoreLayout: true,
        restoreTerminals: true,
        restoreDebug: true,
        restoreSettings: true,
        restoreExtensions: true,
      },
    });

    expect(result.successful).toBe(true);
    expect(result.filesRestored).toBeGreaterThan(0);
  });

  it('should emit snapshot-restored event', () => {
    return new Promise<void>((resolve) => {
      service
        .createSnapshot(
          'user1',
          'user1@example.com',
          'workspace1',
          'session1',
          createTestSnapshot()
        )
        .then((snap) => {
          service.once('snapshot-restored', (data) => {
            expect(data.successful).toBe(true);
            resolve();
          });
          service.restoreSnapshot({
            userId: 'user1',
            userEmail: 'user1@example.com',
            snapshotId: snap.id,
            restoreOptions: {
              restoreFiles: true,
              restoreLayout: false,
              restoreTerminals: false,
              restoreDebug: false,
              restoreSettings: false,
              restoreExtensions: false,
            },
          });
        });
    });
  });

  it('should measure restore time', async () => {
    const snap = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    const result = await service.restoreSnapshot({
      userId: 'user1',
      userEmail: 'user1@example.com',
      snapshotId: snap.id,
      restoreOptions: {
        restoreFiles: true,
        restoreLayout: true,
        restoreTerminals: true,
        restoreDebug: true,
        restoreSettings: true,
        restoreExtensions: true,
      },
    });

    expect(result.duration).toBeLessThan(10000); // < 10s
  });

  it('should handle missing snapshot on restore', async () => {
    const result = await service.restoreSnapshot({
      userId: 'user1',
      userEmail: 'user1@example.com',
      snapshotId: 'nonexistent',
      restoreOptions: {
        restoreFiles: true,
        restoreLayout: true,
        restoreTerminals: true,
        restoreDebug: true,
        restoreSettings: true,
        restoreExtensions: true,
      },
    });

    expect(result.successful).toBe(false);
    expect(result.errors).toBeDefined();
  });

  // ==================== Delete Snapshot Tests ====================

  it('should delete snapshot', async () => {
    const snap = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    await service.deleteSnapshot('user1', 'user1@example.com', snap.id);

    const retrieved = await service.getSnapshot(snap.id);
    expect(retrieved).toBeUndefined();
  });

  it('should emit snapshot-deleted event', () => {
    return new Promise<void>((resolve) => {
      service
        .createSnapshot(
          'user1',
          'user1@example.com',
          'workspace1',
          'session1',
          createTestSnapshot()
        )
        .then((snap) => {
          service.once('snapshot-deleted', (data) => {
            expect(data.snapshotId).toBe(snap.id);
            resolve();
          });
          service.deleteSnapshot('user1', 'user1@example.com', snap.id);
        });
    });
  });

  // ==================== List Snapshots Tests ====================

  it('should list snapshots for user', async () => {
    await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    const list = await service.listSnapshots('user1');
    expect(list.length).toBe(2);
  });

  it('should list snapshots filtered by workspace', async () => {
    await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace2',
      'session1',
      createTestSnapshot()
    );

    const list = await service.listSnapshots('user1', 'workspace1');
    expect(list.length).toBe(1);
  });

  it('should sort snapshots by time descending', async () => {
    const snap1 = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    await new Promise((resolve) => setTimeout(resolve, 10));

    const snap2 = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    const list = await service.listSnapshots('user1');
    expect(list[0].timestamp).toBeGreaterThan(list[1].timestamp);
  });

  // ==================== Query Snapshots Tests ====================

  it('should query snapshots', async () => {
    await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    const result = await service.querySnapshots({ userId: 'user1' });
    expect(result.total).toBeGreaterThan(0);
  });

  it('should paginate snapshot queries', async () => {
    for (let i = 0; i < 5; i++) {
      await service.createSnapshot(
        'user1',
        'user1@example.com',
        'workspace1',
        'session1',
        createTestSnapshot()
      );
    }

    const page1 = await service.querySnapshots({ userId: 'user1', limit: 2 });
    expect(page1.snapshots.length).toBe(2);
    expect(page1.total).toBe(5);
  });

  it('should filter by time range', async () => {
    const before = Date.now();
    await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );
    const after = Date.now();

    const result = await service.querySnapshots({
      userId: 'user1',
      fromTime: before - 1000,
      toTime: after + 1000,
    });

    expect(result.total).toBeGreaterThan(0);
  });

  // ==================== Tag Snapshot Tests ====================

  it('should tag snapshot', async () => {
    const snap = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    await service.tagSnapshot('user1', 'user1@example.com', snap.id, ['important', 'backup']);

    const list = await service.listSnapshots('user1');
    expect(list[0].tags).toContain('important');
    expect(list[0].tags).toContain('backup');
  });

  it('should emit snapshot-tagged event', () => {
    return new Promise<void>((resolve) => {
      service
        .createSnapshot(
          'user1',
          'user1@example.com',
          'workspace1',
          'session1',
          createTestSnapshot()
        )
        .then((snap) => {
          service.once('snapshot-tagged', (data) => {
            expect(data.tags).toContain('important');
            resolve();
          });
          service.tagSnapshot('user1', 'user1@example.com', snap.id, ['important']);
        });
    });
  });

  // ==================== Compare Snapshots Tests ====================

  it('should compare snapshots', async () => {
    const snap1 = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      {
        ...createTestSnapshot(),
        files: [
          { path: '/src/a.ts', content: 'a', encoding: 'utf8', isModified: false, isUnsaved: false, lastModified: Date.now() },
        ],
      }
    );

    const snap2 = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      {
        ...createTestSnapshot(),
        files: [
          { path: '/src/a.ts', content: 'a', encoding: 'utf8', isModified: false, isUnsaved: false, lastModified: Date.now() },
          { path: '/src/b.ts', content: 'b', encoding: 'utf8', isModified: false, isUnsaved: false, lastModified: Date.now() },
        ],
      }
    );

    const comparison = await service.compareSnapshots(snap1.id, snap2.id);
    expect(comparison).toBeDefined();
    expect(comparison?.filesAdded).toContain('/src/b.ts');
  });

  // ==================== Audit Logging Tests ====================

  it('should log audit entry for snapshot creation', async () => {
    await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot(),
      '192.168.1.1',
      'Mozilla/5.0'
    );

    const log = await service.getAuditLog('user1');
    expect(log.length).toBeGreaterThan(0);
    expect(log[0].operation).toBe('created');
    expect(log[0].ipAddress).toBe('192.168.1.1');
  });

  it('should log audit entry for restore', async () => {
    const snap = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    await service.restoreSnapshot(
      {
        userId: 'user1',
        userEmail: 'user1@example.com',
        snapshotId: snap.id,
        restoreOptions: {
          restoreFiles: true,
          restoreLayout: true,
          restoreTerminals: true,
          restoreDebug: true,
          restoreSettings: true,
          restoreExtensions: true,
        },
      },
      '192.168.1.1',
      'Mozilla/5.0'
    );

    const log = await service.getAuditLog('user1');
    const restoreEntry = log.find((e) => e.operation === 'restored');
    expect(restoreEntry).toBeDefined();
    expect(restoreEntry?.ipAddress).toBe('192.168.1.1');
  });

  it('should emit audit-logged event', () => {
    return new Promise<void>((resolve) => {
      service.once('audit-logged', (data) => {
        expect(data.userId).toBe('user1');
        resolve();
      });
      service.createSnapshot(
        'user1',
        'user1@example.com',
        'workspace1',
        'session1',
        createTestSnapshot()
      );
    });
  });

  // ==================== Statistics Tests ====================

  it('should calculate statistics', async () => {
    await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    const stats = await service.getStatistics();
    expect(stats.totalSnapshots).toBe(1);
  });

  it('should track snapshots by user', async () => {
    await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    await service.createSnapshot(
      'user2',
      'user2@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    const stats = await service.getStatistics();
    expect(stats.snapshotsByUser['user1']).toBe(1);
    expect(stats.snapshotsByUser['user2']).toBe(1);
  });

  // ==================== Max Versions Tests ====================

  it('should limit to max versions', async () => {
    const smallService = new SnapshotService({ maxVersions: 3 });
    await smallService.initialize();

    for (let i = 0; i < 5; i++) {
      await smallService.createSnapshot(
        'user1',
        'user1@example.com',
        'workspace1',
        'session1',
        createTestSnapshot()
      );
    }

    const list = await smallService.listSnapshots('user1');
    expect(list.length).toBeLessThanOrEqual(3);

    await smallService.shutdown();
  });

  // ==================== Error Handling Tests ====================

  it('should throw error if not initialized', async () => {
    const newService = new SnapshotService();
    await expect(newService.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    )).rejects.toThrow();
  });

  // ==================== Singleton Pattern Tests ====================

  it('should use singleton pattern', () => {
    const instance1 = SnapshotService.getInstance();
    const instance2 = SnapshotService.getInstance();
    expect(instance1).toBe(instance2);
  });

  // ==================== Multiple Workspaces Tests ====================

  it('should handle multiple workspaces per user', async () => {
    await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace2',
      'session1',
      createTestSnapshot()
    );

    const ws1Snaps = await service.listSnapshots('user1', 'workspace1');
    const ws2Snaps = await service.listSnapshots('user1', 'workspace2');

    expect(ws1Snaps.length).toBe(1);
    expect(ws2Snaps.length).toBe(1);
  });

  // ==================== Multiple Users Tests ====================

  it('should handle multiple users', async () => {
    for (let i = 1; i <= 5; i++) {
      await service.createSnapshot(
        `user${i}`,
        `user${i}@example.com`,
        'workspace1',
        'session1',
        createTestSnapshot()
      );
    }

    const stats = await service.getStatistics();
    expect(stats.totalSnapshots).toBe(5);
    expect(Object.keys(stats.snapshotsByUser).length).toBe(5);
  });

  // ==================== Storage Size Tracking Tests ====================

  it('should track storage size', async () => {
    await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    const stats = await service.getStatistics();
    expect(stats.totalStorageBytes).toBeGreaterThan(0);
  });

  it('should calculate average snapshot size', async () => {
    await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      createTestSnapshot()
    );

    const stats = await service.getStatistics();
    expect(stats.averageSnapshotSize).toBeGreaterThan(0);
  });

  // ==================== Audit Log Size Tests ====================

  it('should limit audit log size', async () => {
    const smallService = new SnapshotService({ maxAuditLogSize: 5 });
    await smallService.initialize();

    for (let i = 0; i < 10; i++) {
      await smallService.createSnapshot(
        'user1',
        'user1@example.com',
        'workspace1',
        'session1',
        createTestSnapshot()
      );
    }

    const log = await smallService.getAuditLog('user1');
    expect(log.length).toBeLessThanOrEqual(5);

    await smallService.shutdown();
  });

  // ==================== Terminal State Tests ====================

  it('should preserve terminal state in snapshots', async () => {
    const snap = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      {
        ...createTestSnapshot(),
        terminals: [
          { id: 't1', name: 'Main', shellPath: '/bin/bash', shellArgs: [], cwd: '/work', history: ['npm start', 'npm test'], isActive: true, lines: 50 },
          { id: 't2', name: 'Debug', shellPath: '/bin/bash', shellArgs: [], cwd: '/work', history: ['gdb'], isActive: false, lines: 30 },
        ],
      }
    );

    expect(snap.terminals).toHaveLength(2);
    expect(snap.terminals[0].history).toContain('npm start');
  });

  // ==================== Settings Preservation Tests ====================

  it('should preserve workspace settings', async () => {
    const customSettings = {
      theme: 'light',
      fontSize: 16,
      fontFamily: 'Monaco',
      formatOnSave: false,
      tabSize: 4,
      wordWrap: false,
      extensions: [],
    };

    const snap = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      {
        ...createTestSnapshot(),
        settings: customSettings,
      }
    );

    expect(snap.settings.theme).toBe('light');
    expect(snap.settings.fontSize).toBe(16);
    expect(snap.settings.tabSize).toBe(4);
  });

  // ==================== Layout State Tests ====================

  it('should capture editor layout', async () => {
    const snap = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      {
        ...createTestSnapshot(),
        layout: {
          groups: [
            {
              id: 'group1',
              size: 0.33,
              editors: [
                { id: 'e1', path: '/src/a.ts', isActive: true, position: 0 },
                { id: 'e2', path: '/src/b.ts', isActive: false, position: 1 },
              ],
            },
            {
              id: 'group2',
              size: 0.67,
              editors: [
                { id: 'e3', path: '/src/c.ts', isActive: true, position: 0 },
              ],
            },
          ],
          focusedGroupId: 'group1',
          focusedEditorId: 'e1',
        },
      }
    );

    expect(snap.layout.groups).toHaveLength(2);
    expect(snap.layout.focusedGroupId).toBe('group1');
  });

  // ==================== Description and Tags Tests ====================

  it('should store snapshot description', async () => {
    const snap = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      {
        ...createTestSnapshot(),
        description: 'Final working version before refactor',
      }
    );

    expect(snap.description).toBe('Final working version before refactor');
  });

  it('should store and filter by tags', async () => {
    const snap = await service.createSnapshot(
      'user1',
      'user1@example.com',
      'workspace1',
      'session1',
      {
        ...createTestSnapshot(),
        tags: ['production', 'stable'],
      }
    );

    const result = await service.querySnapshots({
      userId: 'user1',
      tags: ['production'],
    });

    expect(result.total).toBeGreaterThan(0);
  });
});
