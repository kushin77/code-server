#!/usr/bin/env node
// @file        apps/backend/src/services/crdt/__tests__/compaction-service.test.ts
// @module      crdt/tests
// @description CRDT compaction service comprehensive tests

import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { CRDTCompactionService, CRDTOperation } from '../compaction-service'
import pino from 'pino'

const logger = pino({ level: 'silent' })

describe('CRDTCompactionService', () => {
  let service: CRDTCompactionService

  beforeEach(() => {
    service = new CRDTCompactionService(logger)
  })

  afterEach(() => {
    service.shutdown()
  })

  describe('Initialization', () => {
    it('should create service instance', () => {
      expect(service).toBeDefined()
    })

    it('should get singleton instance', () => {
      const service1 = CRDTCompactionService.getInstance(logger)
      const service2 = CRDTCompactionService.getInstance(logger)
      expect(service1).toBe(service2)
    })

    it('should start with empty snapshots', () => {
      const snapshots = service.getAllSnapshots()
      expect(snapshots).toHaveLength(0)
    })
  })

  describe('Snapshot Creation', () => {
    it('should create snapshot from operations', () => {
      const operations: CRDTOperation[] = [
        {
          id: 'op-1',
          clientId: 'client-1',
          timestamp: Date.now(),
          type: 'insert',
          position: 0,
          length: 5,
          content: 'Hello',
        },
      ]

      const snapshot = service.createSnapshot('doc-1', operations, 'Hello')

      expect(snapshot).toBeDefined()
      expect(snapshot.docId).toBe('doc-1')
      expect(snapshot.appliedOpsCount).toBe(1)
      expect(snapshot.content).toBe('Hello')
    })

    it('should compute checksum for integrity', () => {
      const snapshot1 = service.createSnapshot('doc-1', [], 'content')
      const snapshot2 = service.createSnapshot('doc-2', [], 'content')

      expect(snapshot1.checksum).toBe(snapshot2.checksum) // Same content, same checksum
    })

    it('should emit snapshot-created event', () => {
      return new Promise<void>((resolve) => {
        service.on('snapshot-created', (data) => {
          expect(data.docId).toBe('doc-1')
          resolve()
        })

        service.createSnapshot('doc-1', [], 'content')
      })
    })

    it('should store snapshot for retrieval', () => {
      const snapshot = service.createSnapshot('doc-1', [], 'content')

      const retrieved = service.getSnapshot('doc-1')

      expect(retrieved).toEqual(snapshot)
    })
  })

  describe('Document Compaction', () => {
    it('should compact document with operations', () => {
      const operations: CRDTOperation[] = Array.from({ length: 100 }, (_, i) => ({
        id: `op-${i}`,
        clientId: 'client-1',
        timestamp: Date.now() - (100 - i) * 1000,
        type: 'insert',
        position: i,
        length: 1,
        content: String.fromCharCode(65 + (i % 26)),
      }))

      const result = service.compactDocument('doc-1', operations, 'ABC...')

      expect(result.success).toBe(true)
      expect(result.before.opsCount).toBe(100)
      expect(result.after.opsCount).toBe(0) // All ops in snapshot
      expect(result.reduction.opsCount).toBe(100)
      expect(result.reduction.sizeBytes).toBeGreaterThan(0)
    })

    it('should emit document-compacted event', () => {
      return new Promise<void>((resolve) => {
        service.on('document-compacted', (data) => {
          expect(data.docId).toBe('doc-1')
          expect(data.success).toBe(true)
          resolve()
        })

        const operations: CRDTOperation[] = [
          {
            id: 'op-1',
            clientId: 'client-1',
            timestamp: Date.now(),
            type: 'insert',
            position: 0,
            length: 1,
            content: 'a',
          },
        ]

        service.compactDocument('doc-1', operations, 'a')
      })
    })

    it('should calculate percentage reduction', () => {
      const operations: CRDTOperation[] = Array.from({ length: 1000 }, (_, i) => ({
        id: `op-${i}`,
        clientId: 'client-1',
        timestamp: Date.now(),
        type: 'insert',
        position: i,
        length: 1,
      }))

      const result = service.compactDocument('doc-1', operations, 'a'.repeat(1000))

      expect(result.reduction.percentageReduction).toBeGreaterThan(90)
    })

    it('should detect checksum mismatch', () => {
      const operations: CRDTOperation[] = [
        {
          id: 'op-1',
          clientId: 'client-1',
          timestamp: Date.now(),
          type: 'insert',
          position: 0,
          length: 1,
          content: 'a',
        },
      ]

      // Create snapshot with different content
      service.createSnapshot('doc-1', operations, 'a')

      // Try to compact with mismatched content
      const result = service.compactDocument('doc-1', operations, 'b')

      expect(result.success).toBe(false)
      expect(result.error).toContain('checksum mismatch')
    })

    it('should handle empty operations', () => {
      const result = service.compactDocument('doc-1', [], '')

      expect(result.success).toBe(true)
      expect(result.before.opsCount).toBe(0)
    })

    it('should keep recent operations after snapshot', () => {
      // Create initial operations
      const allOps: CRDTOperation[] = Array.from({ length: 10 }, (_, i) => ({
        id: `op-${i}`,
        clientId: 'client-1',
        timestamp: Date.now() - (10 - i) * 1000,
        type: 'insert' as const,
        position: i,
        length: 1,
      }))

      // Compact first time - creates snapshot at ops.length
      const result1 = service.compactDocument('doc-1', allOps, 'a'.repeat(10))
      expect(result1.before.opsCount).toBe(10)

      // After snapshot, adding more operations
      // The new operations should be tracked
      const snapshot = service.getSnapshot('doc-1')
      expect(snapshot).toBeDefined()
      expect(snapshot?.appliedOpsCount).toBe(10)
    })
  })

  describe('Compaction Thresholds', () => {
    it('should determine if compaction needed by operation count', () => {
      const operations: CRDTOperation[] = Array.from({ length: 15000 }, (_, i) => ({
        id: `op-${i}`,
        clientId: 'client-1',
        timestamp: Date.now(),
        type: 'insert',
        position: i,
        length: 1,
      }))

      const shouldCompact = service.shouldCompact(operations, Date.now())

      expect(shouldCompact).toBe(true)
    })

    it('should determine if compaction needed by age', () => {
      const operations: CRDTOperation[] = [
        {
          id: 'op-1',
          clientId: 'client-1',
          timestamp: Date.now(),
          type: 'insert',
          position: 0,
          length: 1,
        },
      ]

      const lastCompactionTime = Date.now() - 48 * 60 * 60 * 1000 // 48 hours ago

      const shouldCompact = service.shouldCompact(operations, lastCompactionTime)

      expect(shouldCompact).toBe(true)
    })

    it('should not compact if below thresholds', () => {
      const operations: CRDTOperation[] = [
        {
          id: 'op-1',
          clientId: 'client-1',
          timestamp: Date.now(),
          type: 'insert',
          position: 0,
          length: 1,
        },
      ]

      const shouldCompact = service.shouldCompact(operations, Date.now())

      expect(shouldCompact).toBe(false)
    })

    it('should allow custom thresholds', () => {
      service.setThresholds({
        operationCount: 100,
        sizeMB: 1,
        ageHours: 1,
      })

      const operations: CRDTOperation[] = Array.from({ length: 150 }, (_, i) => ({
        id: `op-${i}`,
        clientId: 'client-1',
        timestamp: Date.now(),
        type: 'insert',
        position: i,
        length: 1,
      }))

      const shouldCompact = service.shouldCompact(operations, Date.now())

      expect(shouldCompact).toBe(true)
    })
  })

  describe('Snapshot Management', () => {
    it('should retrieve snapshot by document ID', () => {
      const snapshot = service.createSnapshot('doc-1', [], 'content')
      const retrieved = service.getSnapshot('doc-1')

      expect(retrieved).toEqual(snapshot)
    })

    it('should return undefined for missing snapshot', () => {
      const retrieved = service.getSnapshot('non-existent')

      expect(retrieved).toBeUndefined()
    })

    it('should get all snapshots', () => {
      service.createSnapshot('doc-1', [], 'content1')
      service.createSnapshot('doc-2', [], 'content2')
      service.createSnapshot('doc-3', [], 'content3')

      const all = service.getAllSnapshots()

      expect(all).toHaveLength(3)
    })

    it('should remove old snapshots', (done) => {
      service.createSnapshot('doc-1', [], 'content1')

      // Manually set old timestamp by directly accessing
      const snapshot = service.getSnapshot('doc-1')
      if (snapshot) {
        snapshot.timestamp = Date.now() - 48 * 60 * 60 * 1000 // 48 hours ago
      }

      const removed = service.removeOldSnapshots(24) // Remove older than 24 hours

      // Wait for processing
      setTimeout(() => {
        const remaining = service.getAllSnapshots()
        expect(remaining).toHaveLength(0)
        done()
      }, 100)
    })

    it('should keep recent snapshots', () => {
      service.createSnapshot('doc-1', [], 'content1')
      service.createSnapshot('doc-2', [], 'content2')

      const removed = service.removeOldSnapshots(24) // Remove older than 24 hours

      const remaining = service.getAllSnapshots()
      expect(remaining).toHaveLength(2) // Both are recent
    })
  })

  describe('Statistics', () => {
    it('should track compaction statistics', () => {
      const operations: CRDTOperation[] = Array.from({ length: 100 }, (_, i) => ({
        id: `op-${i}`,
        clientId: 'client-1',
        timestamp: Date.now(),
        type: 'insert',
        position: i,
        length: 1,
      }))

      service.compactDocument('doc-1', operations, 'a'.repeat(100))
      service.compactDocument('doc-2', operations, 'b'.repeat(100))

      const stats = service.getCompactionStats()

      expect(stats.totalCompactions).toBe(2)
      expect(stats.totalOpsReduced).toBeGreaterThan(0)
      expect(stats.totalBytesReduced).toBeGreaterThan(0)
      expect(stats.averageOpsPerCompaction).toBeGreaterThan(0)
    })

    it('should count active snapshots', () => {
      service.createSnapshot('doc-1', [], 'content1')
      service.createSnapshot('doc-2', [], 'content2')

      const stats = service.getCompactionStats()

      expect(stats.snapshotsActive).toBe(2)
    })

    it('should handle empty statistics', () => {
      const stats = service.getCompactionStats()

      expect(stats.totalCompactions).toBe(0)
      expect(stats.totalOpsReduced).toBe(0)
      expect(stats.averageOpsPerCompaction).toBe(0)
    })
  })

  describe('Service Lifecycle', () => {
    it('should reset state', () => {
      service.createSnapshot('doc-1', [], 'content')
      const operations: CRDTOperation[] = [
        {
          id: 'op-1',
          clientId: 'client-1',
          timestamp: Date.now(),
          type: 'insert',
          position: 0,
          length: 1,
        },
      ]
      service.compactDocument('doc-1', operations, 'a')

      service.reset()

      expect(service.getAllSnapshots()).toHaveLength(0)
      expect(service.getCompactionStats().totalCompactions).toBe(0)
    })

    it('should shutdown cleanly', () => {
      service.createSnapshot('doc-1', [], 'content')
      service.shutdown()

      expect(service.getAllSnapshots()).toHaveLength(0)
    })
  })

  describe('Edge Cases', () => {
    it('should handle very large operation counts', () => {
      const operations: CRDTOperation[] = Array.from({ length: 100000 }, (_, i) => ({
        id: `op-${i}`,
        clientId: 'client-1',
        timestamp: Date.now(),
        type: 'insert',
        position: i,
        length: 1,
      }))

      const result = service.compactDocument('doc-1', operations, 'x')

      expect(result.success).toBe(true)
      expect(result.before.opsCount).toBe(100000)
      expect(result.reduction.opsCount).toBe(100000)
    })

    it('should handle operations with null content', () => {
      const operations: CRDTOperation[] = [
        {
          id: 'op-1',
          clientId: 'client-1',
          timestamp: Date.now(),
          type: 'delete',
          position: 0,
          length: 5,
          // content is undefined
        },
      ]

      const result = service.compactDocument('doc-1', operations, '')

      expect(result.success).toBe(true)
    })

    it('should handle multiple compactions of same document', () => {
      const operations: CRDTOperation[] = Array.from({ length: 100 }, (_, i) => ({
        id: `op-${i}`,
        clientId: 'client-1',
        timestamp: Date.now(),
        type: 'insert',
        position: i,
        length: 1,
      }))

      service.compactDocument('doc-1', operations, 'a'.repeat(100))
      const result2 = service.compactDocument('doc-1', operations, 'a'.repeat(100))
      const result3 = service.compactDocument('doc-1', operations, 'a'.repeat(100))

      expect(result2.success).toBe(true)
      expect(result3.success).toBe(true)
    })

    it('should track compaction history limit', () => {
      const operations: CRDTOperation[] = [
        {
          id: 'op-1',
          clientId: 'client-1',
          timestamp: Date.now(),
          type: 'insert',
          position: 0,
          length: 1,
        },
      ]

      // Perform 2000 compactions
      for (let i = 0; i < 2000; i++) {
        service.compactDocument(`doc-${i}`, operations, 'a')
      }

      const stats = service.getCompactionStats()

      // Should keep only last 1000
      expect(stats.totalCompactions).toBe(1000)
    })
  })
})
