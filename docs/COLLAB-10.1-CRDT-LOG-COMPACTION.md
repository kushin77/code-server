# Collab-10.1 CRDT Operation Log Compaction

## Overview

This change adds automatic garbage collection for the CRDT replication operation log in `src/services/replication/SyncProtocol.ts`.

The previous implementation only trimmed the oldest entries once the log exceeded a fixed size. The new implementation adds two compaction paths:

- time-based retention for stale operations
- size-based eviction for oversized logs

## Behavior

### Time-Based GC

Operations older than the configured retention window are removed automatically.

Default retention:

- `operationLogRetentionMs = 7 days`

### Size-Based GC

If the log still exceeds the configured maximum size after stale entries are removed, the oldest remaining entries are evicted.

Default max size:

- `operationLogMaxSize = 100000`

## Configuration

`SyncProtocolConfig` now accepts optional fields:

```ts
operationLogRetentionMs?: number;
operationLogMaxSize?: number;
```

Example:

```ts
const protocol = new SyncProtocol({
  replicaId: 'replica-1',
  regionId: 'us-west',
  maxBatchSize: 100,
  syncIntervalMs: 1000,
  maxClockSkewMs: 5000,
  enableCompression: true,
  compressionThreshold: 10240,
  operationLogRetentionMs: 7 * 24 * 60 * 60 * 1000,
  operationLogMaxSize: 50000,
});
```

## Automatic Maintenance

Compaction now runs in three places:

- after local `sendOperation()` writes
- after `receiveOperation()` accepts a peer operation
- during `ReplicationService` periodic sync maintenance

That keeps idle services from retaining stale operations indefinitely.

## Monitoring

`getSyncStats()` now reports compaction telemetry:

- current operation log size
- retention window
- max log size
- last compaction timestamp
- total compactions
- total pruned operations

This makes it easy to graph GC behavior alongside sync latency and replication health.

## Tests

Coverage added for:

- age-based garbage collection
- size-based eviction fallback
- sync stats reporting
- known-operation index pruning

## Operational Notes

Use a shorter retention window when:

- replicas are long-lived
- bandwidth is constrained
- memory pressure is high

Use a larger retention window when:

- offline replicas may rejoin after a long delay
- you need deeper conflict history for debugging

## Related Files

- [src/services/replication/SyncProtocol.ts](../../src/services/replication/SyncProtocol.ts)
- [src/services/replication/ReplicationService.ts](../../src/services/replication/ReplicationService.ts)
- [src/services/replication/__tests__/SyncProtocol.test.ts](../../src/services/replication/__tests__/SyncProtocol.test.ts)

## Status

Implemented for Collab-10.1 and ready for validation.
