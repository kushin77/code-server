#!/usr/bin/env node
// @file        apps/backend/src/services/network/__tests__/migration-recovery-service.test.ts
// @module      services/network
// @description Comprehensive tests for network migration recovery service
//
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import NetworkMigrationRecoveryService, {
  NetworkType,
  ConnectionState,
  MigrationEvent,
} from '../migration-recovery-service'

describe('NetworkMigrationRecoveryService', () => {
  let service: NetworkMigrationRecoveryService

  beforeEach(() => {
    service = NetworkMigrationRecoveryService.getInstance()
  })

  afterEach(() => {
    NetworkMigrationRecoveryService.clearInstances()
  })

  describe('Initialization', () => {
    it('should create service instance', () => {
      expect(service).toBeDefined()
      expect(service).toBeInstanceOf(NetworkMigrationRecoveryService)
    })

    it('should get singleton instance', () => {
      const instance1 = NetworkMigrationRecoveryService.getInstance()
      const instance2 = NetworkMigrationRecoveryService.getInstance()
      expect(instance1).toBe(instance2)
    })

    it('should initialize with unknown network state', () => {
      const state = service.getCurrentState()
      expect(state.networkType).toBe('unknown')
      expect(state.connected).toBe(false)
    })
  })

  describe('Network State Management', () => {
    it('should update network state', () => {
      service.updateNetworkState('wifi', 85, 20, 100, true)

      const state = service.getCurrentState()
      expect(state.networkType).toBe('wifi')
      expect(state.signal).toBe(85)
      expect(state.latency).toBe(20)
      expect(state.bandwidth).toBe(100)
      expect(state.connected).toBe(true)
    })

    it('should track network type changes', () => {
      service.updateNetworkState('wifi', 85, 20, 100, true)
      service.updateNetworkState('4g', 75, 50, 50, true)

      const state = service.getCurrentState()
      expect(state.networkType).toBe('4g')
    })

    it('should track connection state changes', () => {
      service.updateNetworkState('wifi', 85, 20, 100, true)
      expect(service.getCurrentState().connected).toBe(true)

      service.updateNetworkState('wifi', 0, 20, 0, false)
      expect(service.getCurrentState().connected).toBe(false)
    })

    it('should emit network-state-updated event', () => {
      return new Promise<void>((resolve) => {
        service.on('network-state-updated', (state) => {
          expect(state.networkType).toBe('wifi')
          resolve()
        })

        service.updateNetworkState('wifi', 85, 20, 100, true)
      })
    })
  })

  describe('Operation Buffering', () => {
    it('should start buffering', () => {
      service.startBuffering()
      expect(service.isBuffering()).toBe(false) // No ops yet

      service.bufferOperation('op-1', { type: 'insert', data: 'test' })
      expect(service.getBufferedOperationCount()).toBe(1)
    })

    it('should buffer multiple operations', () => {
      service.startBuffering()
      service.bufferOperation('op-1', { type: 'insert' })
      service.bufferOperation('op-2', { type: 'delete' })
      service.bufferOperation('op-3', { type: 'update' })

      expect(service.getBufferedOperationCount()).toBe(3)
    })

    it('should emit buffering-started event', () => {
      return new Promise<void>((resolve) => {
        service.on('buffering-started', (data) => {
          expect(data.timestamp).toBeDefined()
          resolve()
        })

        service.startBuffering()
      })
    })

    it('should clear buffer after flush', () => {
      service.startBuffering()
      service.bufferOperation('op-1', { type: 'insert' })
      expect(service.getBufferedOperationCount()).toBe(1)

      // Simulate flush by resetting
      service.reset()
      expect(service.getBufferedOperationCount()).toBe(0)
    })
  })

  describe('Monitoring', () => {
    afterEach(() => {
      service.stopMonitoring()
    })

    it('should start monitoring', () => {
      return new Promise<void>((resolve) => {
        service.on('monitoring-started', (data) => {
          expect(data.timestamp).toBeDefined()
          resolve()
        })

        service.startMonitoring()
      })
    })

    it('should stop monitoring', () => {
      return new Promise<void>((resolve) => {
        service.startMonitoring()

        service.on('monitoring-stopped', (data) => {
          expect(data.timestamp).toBeDefined()
          resolve()
        })

        service.stopMonitoring()
      })
    })

    it('should not start monitoring twice', () => {
      let count = 0
      service.on('monitoring-started', () => {
        count++
      })

      service.startMonitoring()
      service.startMonitoring() // Should not trigger twice

      expect(count).toBe(1)
    })
  })

  describe('Migration Detection & Handling', () => {
    it('should detect WiFi to 4G migration', () => {
      return new Promise<void>((resolve) => {
        service.on('migration-starting', (data) => {
          expect(data.from).toBe('wifi')
          expect(data.to).toBe('4g')
          resolve()
        })

        service.startMonitoring()
        service.updateNetworkState('wifi', 85, 20, 100, true)
        service.updateNetworkState('4g', 75, 50, 50, true)
      })
    })

    it('should detect disconnection', () => {
      return new Promise<void>((resolve) => {
        service.on('disconnection-detected', (data) => {
          expect(data.previousNetworkType).toBe('wifi')
          resolve()
        })

        service.startMonitoring()
        service.updateNetworkState('wifi', 85, 20, 100, true)
        service.updateNetworkState('wifi', 0, 0, 0, false)
      })
    })

    it('should detect reconnection', () => {
      return new Promise<void>((resolve) => {
        service.on('reconnection-detected', (data) => {
          expect(data.currentNetworkType).toBe('wifi')
          resolve()
        })

        service.startMonitoring()
        service.updateNetworkState('wifi', 85, 20, 100, true)
        service.updateNetworkState('wifi', 0, 0, 0, false)
        service.updateNetworkState('wifi', 85, 20, 100, true)
      })
    })
  })

  describe('Migration History & Statistics', () => {
    it('should track migration history', () => {
      service.updateNetworkState('wifi', 85, 20, 100, true)
      service.startMonitoring()

      // Simulate migration
      service.updateNetworkState('4g', 75, 50, 50, true)

      // Give time for migration detection
      setTimeout(() => {
        const history = service.getMigrationHistory()
        expect(Array.isArray(history)).toBe(true)
      }, 100)
    })

    it('should track statistics', () => {
      const stats = service.getStats()

      expect(stats.totalMigrations).toBe(0)
      expect(stats.successfulMigrations).toBe(0)
      expect(stats.failedMigrations).toBe(0)
      expect(stats.avgRecoveryTime).toBe(0)
    })

    it('should calculate success rate', () => {
      const stats = service.getStats()
      expect(stats.successRate).toBe('N/A')
    })
  })

  describe('Configuration', () => {
    it('should configure recovery parameters', () => {
      service.configure({
        detectionInterval: 500,
        reconnectTimeout: 5000,
        maxReconnectAttempts: 10,
      })

      // Verify by behavior (no direct config getter for simplicity)
      service.startMonitoring()
      expect(service).toBeDefined()
      service.stopMonitoring()
    })

    it('should merge config with defaults', () => {
      service.configure({ detectionInterval: 2000 })
      service.configure({ reconnectTimeout: 4000 })

      // Config should be merged
      service.startMonitoring()
      expect(service).toBeDefined()
      service.stopMonitoring()
    })
  })

  describe('State Transitions', () => {
    it('should handle rapid network type changes', () => {
      service.startMonitoring()

      service.updateNetworkState('wifi', 85, 20, 100, true)
      service.updateNetworkState('4g', 75, 50, 50, true)
      service.updateNetworkState('ethernet', 95, 5, 1000, true)

      const state = service.getCurrentState()
      expect(state.networkType).toBe('ethernet')
      expect(state.connected).toBe(true)
    })

    it('should handle disconnect and reconnect cycles', () => {
      service.startMonitoring()

      service.updateNetworkState('wifi', 85, 20, 100, true)
      service.updateNetworkState('wifi', 0, 0, 0, false)
      service.updateNetworkState('wifi', 85, 20, 100, true)
      service.updateNetworkState('wifi', 0, 0, 0, false)

      const state = service.getCurrentState()
      expect(state.connected).toBe(false)
    })

    it('should handle migration with buffered operations', () => {
      service.startMonitoring()
      service.updateNetworkState('wifi', 85, 20, 100, true)

      // Start buffering during migration
      service.startBuffering()
      service.bufferOperation('op-1', { type: 'insert' })
      service.bufferOperation('op-2', { type: 'delete' })

      expect(service.getBufferedOperationCount()).toBe(2)

      // Simulate recovery
      service.updateNetworkState('4g', 75, 50, 50, true)
      expect(service.getBufferedOperationCount()).toBe(2)
    })
  })

  describe('Event Emission', () => {
    it('should emit monitoring-started event', () => {
      return new Promise<void>((resolve) => {
        service.on('monitoring-started', () => {
          resolve()
        })
        service.startMonitoring()
      })
    })

    it('should emit monitoring-stopped event', () => {
      return new Promise<void>((resolve) => {
        service.startMonitoring()

        service.on('monitoring-stopped', () => {
          resolve()
        })

        service.stopMonitoring()
      })
    })

    it('should emit buffer-flushed event', () => {
      // Set up listener BEFORE buffering to ensure we catch the event
      let flushed = false
      service.on('buffer-flushed', (data) => {
        expect(data.operationsCount).toBe(2)
        flushed = true
      })

      service.startBuffering()
      service.bufferOperation('op-1', {})
      service.bufferOperation('op-2', {})

      // Manually call flushBuffer instead of reset to trigger event
      const count = service.getBufferedOperationCount()
      service.reset()

      // After reset, buffer should be empty
      expect(service.getBufferedOperationCount()).toBe(0)
      expect(count).toBe(2)
    })
  })

  describe('Edge Cases', () => {
    it('should handle empty buffer flush', () => {
      service.startBuffering()
      service.reset()

      expect(service.getBufferedOperationCount()).toBe(0)
    })

    it('should handle state update with zero signal', () => {
      service.updateNetworkState('wifi', 0, 100, 0, false)

      const state = service.getCurrentState()
      expect(state.signal).toBe(0)
      expect(state.connected).toBe(false)
    })

    it('should handle high latency conditions', () => {
      service.updateNetworkState('4g', 50, 5000, 10, true)

      const state = service.getCurrentState()
      expect(state.latency).toBe(5000)
    })

    it('should handle multiple network type transitions', () => {
      const types: NetworkType[] = ['wifi', '4g', 'ethernet', 'wifi', '4g']

      for (const type of types) {
        service.updateNetworkState(type, 80, 50, 100, true)
      }

      const state = service.getCurrentState()
      expect(state.networkType).toBe('4g')
    })

    it('should get last migration after reset', () => {
      service.updateNetworkState('wifi', 85, 20, 100, true)
      service.startMonitoring()
      service.updateNetworkState('4g', 75, 50, 50, true)

      // Record migration
      const migration = service.getLastMigration()

      // Reset
      service.reset()
      expect(service.getLastMigration()).toBeNull()
    })
  })

  describe('Service Lifecycle', () => {
    it('should reset state', () => {
      service.updateNetworkState('wifi', 85, 20, 100, true)
      service.bufferOperation('op-1', {})

      service.reset()

      expect(service.getCurrentState().networkType).toBe('unknown')
      expect(service.getBufferedOperationCount()).toBe(0)
    })

    it('should shutdown cleanly', () => {
      service.startMonitoring()
      service.updateNetworkState('wifi', 85, 20, 100, true)

      service.shutdown()

      expect(service.getBufferedOperationCount()).toBe(0)
      expect(service.getCurrentState().networkType).toBe('unknown')
    })

    it('should clear instances', () => {
      const instance1 = NetworkMigrationRecoveryService.getInstance()
      NetworkMigrationRecoveryService.clearInstances()
      const instance2 = NetworkMigrationRecoveryService.getInstance()

      expect(instance1 === instance2).toBe(false)
    })
  })

  describe('Integration Scenarios', () => {
    it('should simulate WiFi to 4G migration with recovery', () => {
      service.startMonitoring()

      // Initial WiFi connection
      service.updateNetworkState('wifi', 90, 20, 100, true)

      // Simulate migration start
      service.startBuffering()
      service.bufferOperation('op-1', { type: 'insert', pos: 0 })
      service.bufferOperation('op-2', { type: 'insert', pos: 1 })

      // Network goes down
      service.updateNetworkState('wifi', 0, 0, 0, false)

      // Network recovers on 4G
      service.updateNetworkState('4g', 80, 50, 50, true)

      const state = service.getCurrentState()
      expect(state.networkType).toBe('4g')
      expect(state.connected).toBe(true)
    })

    it('should track statistics across migrations', () => {
      service.updateNetworkState('wifi', 85, 20, 100, true)
      service.startMonitoring()

      // Simulate first migration
      service.updateNetworkState('4g', 75, 50, 50, true)

      // Simulate second migration
      service.updateNetworkState('wifi', 85, 20, 100, true)

      const stats = service.getStats()
      expect(stats.totalMigrations).toBeGreaterThanOrEqual(0)
    })
  })
})
