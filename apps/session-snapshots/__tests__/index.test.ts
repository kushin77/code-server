import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { SessionSnapshotService } from '../src/index';
import fs from 'fs';
import path from 'path';

/**
 * @file        apps/session-snapshots/__tests__/index.test.ts
 * @module      collaboration/persistence
 * @description Unit tests for Session Snapshot Service
 */

describe('SessionSnapshotService', () => {
  const testStorage = './data/test-snapshots';
  let service: SessionSnapshotService;

  beforeEach(() => {
    service = new SessionSnapshotService(testStorage);
  });

  afterEach(() => {
    if (fs.existsSync(testStorage)) {
      fs.rmSync(testStorage, { recursive: true, force: true });
    }
  });

  it('should create a snapshot and return metadata', async () => {
    const sessionId = 'session-123';
    const snapshot = await service.createSnapshot(sessionId, 'Initial Backup');

    expect(snapshot.id).toBeDefined();
    expect(snapshot.sessionId).toBe(sessionId);
    expect(snapshot.label).toBe('Initial Backup');
    expect(fs.existsSync(path.join(testStorage, snapshot.id))).toBe(true);
  });

  it('should list snapshots for a specific session', async () => {
    const sessionId = 'session-456';
    await service.createSnapshot(sessionId, 'S1');
    await service.createSnapshot(sessionId, 'S2');
    await service.createSnapshot('other-session', 'S3');

    const snapshots = service.listSnapshots(sessionId);
    expect(snapshots.length).toBe(2);
    expect(snapshots[0].label).toBe('S2'); // Sorted by latest
  });

  it('should restore a snapshot', async () => {
    const sessionId = 'session-789';
    const snapshot = await service.createSnapshot(sessionId);
    const result = await service.restoreSnapshot(snapshot.id, 'session-new');
    expect(result).toBe(true);
  });
});
