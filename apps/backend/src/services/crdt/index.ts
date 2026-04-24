#!/usr/bin/env node
// @file        apps/backend/src/services/crdt/index.ts
// @module      crdt
// @description CRDT services public API exports

// Compaction service
export { CRDTCompactionService } from './compaction-service'
export type {
  CRDTOperation,
  DocumentSnapshot,
  CompactionResult,
} from './compaction-service'

// Delta sync service
export { DeltaSyncService } from './delta-sync-service'
export type {
  StateVector,
  Delta,
  DeltaOperation,
  SyncRequest,
  SyncResponse,
} from './delta-sync-service'
