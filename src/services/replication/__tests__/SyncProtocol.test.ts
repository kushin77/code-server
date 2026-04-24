// @file        src/services/replication/__tests__/SyncProtocol.test.ts
// @module      services/replication/SyncProtocol/tests
// @description Unit tests for CRDT sync protocol log compaction

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { SyncProtocol } from '../SyncProtocol';

const baseConfig = {
  replicaId: 'replica-1',
  regionId: 'us-west',
  maxBatchSize: 100,
  syncIntervalMs: 1000,
  maxClockSkewMs: 5000,
  enableCompression: true,
  compressionThreshold: 10240,
};

describe('SyncProtocol log compaction', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-04-21T00:00:00.000Z'));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('garbage collects expired operations and prunes known operation ids', () => {
    const protocol = new SyncProtocol({
      ...baseConfig,
      operationLogRetentionMs: 1_000,
      operationLogMaxSize: 10,
    });

    protocol.sendOperation({
      type: 'assign',
      key: 'user:1:name',
      value: 'Alice',
      timestamp: Date.now(),
    });

    vi.setSystemTime(new Date('2026-04-21T00:00:02.000Z'));

    protocol.sendOperation({
      type: 'assign',
      key: 'user:1:name',
      value: 'Bob',
      timestamp: Date.now(),
    });

    const stats = protocol.getSyncStats();
    const request = protocol.buildSyncRequest('replica-1', protocol.getVectorClock());

    expect(stats.operationLogSize).toBe(1);
    expect(stats.totalPrunedOperations).toBe(1);
    expect(stats.totalCompactions).toBeGreaterThan(0);
    expect(stats.lastCompactionAt).toBeGreaterThan(0);
    expect(request.knownOperationIds.size).toBe(1);
  });

  it('removes oldest operations when the log exceeds the size limit', () => {
    const protocol = new SyncProtocol({
      ...baseConfig,
      operationLogRetentionMs: 86_400_000,
      operationLogMaxSize: 3,
    });

    for (let index = 0; index < 5; index++) {
      protocol.sendOperation({
        type: 'assign',
        key: `resource:${index}`,
        value: `value-${index}`,
        timestamp: Date.now(),
      });
    }

    const stats = protocol.getSyncStats();
    const request = protocol.buildSyncRequest('replica-1', protocol.getVectorClock());

    expect(stats.operationLogSize).toBe(3);
    expect(stats.totalPrunedOperations).toBe(2);
    expect(request.knownOperationIds.size).toBe(3);
  });

  it('exposes compaction configuration in sync stats', () => {
    const protocol = new SyncProtocol({
      ...baseConfig,
      operationLogRetentionMs: 12_345,
      operationLogMaxSize: 42,
    });

    const stats = protocol.getSyncStats();

    expect(stats.operationLogRetentionMs).toBe(12_345);
    expect(stats.operationLogMaxSize).toBe(42);
    expect(stats.totalCompactions).toBe(0);
    expect(stats.totalPrunedOperations).toBe(0);
  });
});
