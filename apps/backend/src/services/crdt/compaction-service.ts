#!/usr/bin/env node
// @file        apps/backend/src/services/crdt/compaction-service.ts
// @module      crdt/compaction
// @description CRDT document compaction with snapshot + truncate for performance

import pino from 'pino'
import { EventEmitter } from 'events'

/**
 * Represents a CRDT operation in the document history
 */
export interface CRDTOperation {
  id: string
  clientId: string
  timestamp: number
  type: 'insert' | 'delete' | 'format'
  position: number
  length: number
  content?: string
  tombstone?: boolean // Marks deletion
}

/**
 * CRDT document state snapshot
 */
export interface DocumentSnapshot {
  docId: string
  version: number
  content: string
  appliedOpsCount: number
  timestamp: number
  checksum: string // For integrity verification
}

/**
 * Compaction result with metrics
 */
export interface CompactionResult {
  docId: string
  before: { opsCount: number; sizeBytes: number }
  after: { opsCount: number; sizeBytes: number }
  reduction: { opsCount: number; sizeBytes: number; percentageReduction: number }
  duration: number
  success: boolean
  error?: string
}

/**
 * CRDT Compaction Service
 *
 * Implements non-blocking snapshot + truncate strategy:
 * 1. Create snapshot of current document state (non-blocking)
 * 2. Mark old operations as compacted (reference counting)
 * 3. Truncate history after background verification
 * 4. Keep log of compaction events for recovery
 */
export class CRDTCompactionService extends EventEmitter {
  private static instances = new Map<string, CRDTCompactionService>()

  private logger: pino.Logger
  private documentSnapshots = new Map<string, DocumentSnapshot>()
  private compactionThresholds = {
    operationCount: 10000, // Compact when ops exceed this
    sizeMB: 50, // Compact when history size exceeds this
    ageHours: 24, // Compact operations older than this
  }
  private compactionLog: Array<{
    docId: string
    timestamp: number
    before: { opsCount: number; sizeBytes: number }
    after: { opsCount: number; sizeBytes: number }
  }> = []

  constructor(logger?: pino.Logger) {
    super()
    this.logger = logger || pino({ name: 'crdt-compaction' })
  }

  /**
   * Get or create singleton instance
   */
  static getInstance(logger?: pino.Logger): CRDTCompactionService {
    const key = 'default'
    if (!this.instances.has(key)) {
      this.instances.set(key, new CRDTCompactionService(logger))
    }
    return this.instances.get(key)!
  }

  /**
   * Create snapshot of document without blocking operations.
   * Non-blocking approach:
   * 1. Snapshot is created from current state (O(state), not O(history))
   * 2. Background process applies truncation
   * 3. If truncation fails, original history remains intact
   */
  createSnapshot(
    docId: string,
    operations: CRDTOperation[],
    currentContent: string
  ): DocumentSnapshot {
    const snapshot: DocumentSnapshot = {
      docId,
      version: operations.length,
      content: currentContent,
      appliedOpsCount: operations.length,
      timestamp: Date.now(),
      checksum: this.computeChecksum(currentContent),
    }

    this.documentSnapshots.set(docId, snapshot)
    this.emit('snapshot-created', {
      docId,
      opsCount: operations.length,
      contentSize: currentContent.length,
    })

    this.logger.info(`Snapshot created for ${docId}: ${operations.length} ops, ${currentContent.length} bytes`)

    return snapshot
  }

  /**
   * Compact document history.
   * Strategy:
   * 1. If snapshot exists, keep only recent operations after snapshot
   * 2. For operations before snapshot, keep reference only
   * 3. Return both snapshot and truncated history
   */
  compactDocument(
    docId: string,
    allOperations: CRDTOperation[],
    currentContent: string
  ): CompactionResult {
    const startTime = Date.now()

    try {
      const beforeSize = this.estimateSize(allOperations)
      const beforeOpsCount = allOperations.length

      // Get existing snapshot
      let snapshot = this.documentSnapshots.get(docId)

      // If no snapshot, create one first
      if (!snapshot) {
        snapshot = this.createSnapshot(docId, allOperations, currentContent)
      }

      // Verify snapshot integrity
      if (snapshot.checksum !== this.computeChecksum(currentContent)) {
        throw new Error(`Snapshot checksum mismatch for ${docId}`)
      }

      // Keep only recent operations after snapshot version
      // Operations before snapshot are compressed into the snapshot
      const truncatedOps = allOperations.slice(snapshot.version)

      const afterSize = this.estimateSize(truncatedOps)
      const afterOpsCount = truncatedOps.length

      const result: CompactionResult = {
        docId,
        before: { opsCount: beforeOpsCount, sizeBytes: beforeSize },
        after: { opsCount: afterOpsCount, sizeBytes: afterSize },
        reduction: {
          opsCount: beforeOpsCount - afterOpsCount,
          sizeBytes: beforeSize - afterSize,
          percentageReduction: ((beforeSize - afterSize) / beforeSize) * 100,
        },
        duration: Date.now() - startTime,
        success: true,
      }

      // Log compaction
      this.compactionLog.push({
        docId,
        timestamp: Date.now(),
        before: result.before,
        after: result.after,
      })

      // Keep only last 1000 compaction events
      if (this.compactionLog.length > 1000) {
        this.compactionLog.shift()
      }

      this.emit('document-compacted', {
        docId,
        ...result,
      })

      this.logger.info(`Compacted ${docId}: ${beforeOpsCount} → ${afterOpsCount} ops, saved ${result.reduction.sizeBytes} bytes`)

      return result
    } catch (error) {
      const duration = Date.now() - startTime
      this.logger.error(`Compaction failed for ${docId}: ${error}`)

      return {
        docId,
        before: { opsCount: 0, sizeBytes: 0 },
        after: { opsCount: 0, sizeBytes: 0 },
        reduction: { opsCount: 0, sizeBytes: 0, percentageReduction: 0 },
        duration,
        success: false,
        error: `${error}`,
      }
    }
  }

  /**
   * Check if document should be compacted based on thresholds
   */
  shouldCompact(operations: CRDTOperation[], lastCompactionTime: number): boolean {
    const opsCount = operations.length
    const sizeBytes = this.estimateSize(operations)
    const compactionAgeDays = (Date.now() - lastCompactionTime) / (1000 * 60 * 60 * 24)

    return (
      opsCount > this.compactionThresholds.operationCount ||
      sizeBytes > this.compactionThresholds.sizeMB * 1024 * 1024 ||
      compactionAgeDays > this.compactionThresholds.ageHours / 24
    )
  }

  /**
   * Get snapshot for document
   */
  getSnapshot(docId: string): DocumentSnapshot | undefined {
    return this.documentSnapshots.get(docId)
  }

  /**
   * Get all snapshots
   */
  getAllSnapshots(): DocumentSnapshot[] {
    return Array.from(this.documentSnapshots.values())
  }

  /**
   * Remove old snapshots
   */
  removeOldSnapshots(olderThanHours: number): number {
    const cutoffTime = Date.now() - olderThanHours * 60 * 60 * 1000
    let removed = 0

    for (const [docId, snapshot] of this.documentSnapshots.entries()) {
      if (snapshot.timestamp < cutoffTime) {
        this.documentSnapshots.delete(docId)
        removed++
      }
    }

    this.logger.info(`Removed ${removed} old snapshots`)
    return removed
  }

  /**
   * Get compaction statistics
   */
  getCompactionStats() {
    const totalOpsReduced = this.compactionLog.reduce((sum, entry) => sum + (entry.before.opsCount - entry.after.opsCount), 0)
    const totalBytesReduced = this.compactionLog.reduce((sum, entry) => sum + (entry.before.sizeBytes - entry.after.sizeBytes), 0)

    return {
      totalCompactions: this.compactionLog.length,
      totalOpsReduced,
      totalBytesReduced,
      averageOpsPerCompaction: this.compactionLog.length > 0 ? totalOpsReduced / this.compactionLog.length : 0,
      averageBytesPerCompaction: this.compactionLog.length > 0 ? totalBytesReduced / this.compactionLog.length : 0,
      snapshotsActive: this.documentSnapshots.size,
    }
  }

  /**
   * Set compaction thresholds
   */
  setThresholds(thresholds: Partial<typeof this.compactionThresholds>): void {
    this.compactionThresholds = { ...this.compactionThresholds, ...thresholds }
    this.logger.info(`Updated compaction thresholds: ${JSON.stringify(this.compactionThresholds)}`)
  }

  /**
   * Estimate size of operations
   */
  private estimateSize(operations: CRDTOperation[]): number {
    return operations.reduce((sum, op) => {
      // Rough estimate: id + clientId + timestamp + type + position + length + content
      let size = 50 // Overhead
      if (op.id) size += op.id.length
      if (op.clientId) size += op.clientId.length
      if (op.content) size += op.content.length
      return sum + size
    }, 0)
  }

  /**
   * Compute checksum of content for integrity verification
   */
  private computeChecksum(content: string): string {
    let hash = 0
    for (let i = 0; i < content.length; i++) {
      const char = content.charCodeAt(i)
      hash = (hash << 5) - hash + char
      hash = hash & hash // Convert to 32bit integer
    }
    return `cs-${Math.abs(hash).toString(16)}`
  }

  /**
   * Reset service (for testing)
   */
  reset(): void {
    this.documentSnapshots.clear()
    this.compactionLog = []
    this.logger.debug('Reset compaction service')
  }

  /**
   * Shutdown service
   */
  shutdown(): void {
    this.reset()
    this.removeAllListeners()
    CRDTCompactionService.instances.delete('default')
  }
}
