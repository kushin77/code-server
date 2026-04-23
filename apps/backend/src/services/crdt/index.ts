#!/usr/bin/env node
// @file        apps/backend/src/services/crdt/index.ts
// @module      crdt
// @description CRDT compaction public API exports

export { CRDTCompactionService } from './compaction-service'
export type {
  CRDTOperation,
  DocumentSnapshot,
  CompactionResult,
} from './compaction-service'
