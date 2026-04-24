import { describe, it, expect, vi, beforeEach } from 'vitest';
import { NetworkResilienceCoordinator } from '../network-resilience-coordinator';
import { DeltaSyncService } from '../../crdt/delta-sync-service';
import { MigrationRecoveryService } from '../migration-recovery-service';
import pino from 'pino';

const logger = pino({ level: 'silent' });

describe('NetworkResilienceCoordinator', () => {
  let coordinator: NetworkResilienceCoordinator;
  let deltaSync: DeltaSyncService;
  let migration: MigrationRecoveryService;

  beforeEach(() => {
    // Mock services with event emitters
    deltaSync = {
      prepareSyncBuffer: vi.fn(),
      computeDeltaForClient: vi.fn().mockResolvedValue(new Uint8Array([1, 2, 3])),
      on: vi.fn(),
      emit: vi.fn(),
    } as unknown as DeltaSyncService;

    // Use a real event emitter for migration to test listeners
    const EventEmitter = require('events');
    migration = new EventEmitter() as MigrationRecoveryService;
    migration.performQuickMigration = vi.fn().mockResolvedValue({ status: 'recovered' });

    coordinator = new NetworkResilienceCoordinator(
      {
        enableDeltaReconnection: true,
        adaptiveBufferingEnabled: true,
        recoveryTimeoutMs: 5000,
      },
      deltaSync,
      migration,
      logger
    );
  });

  it('should prepare sync buffer when migration is detected', async () => {
    migration.emit('migration-detected', { sessionId: 'sess-1', clientId: 'client-1' });
    expect(deltaSync.prepareSyncBuffer).toHaveBeenCalledWith('sess-1', 'client-1');
  });

  it('should compute and emit optimized recovery when migration completes', async () => {
    const recoveryListener = vi.fn();
    coordinator.on('recovery-optimized', recoveryListener);

    migration.emit('migration-completed', { 
      sessionId: 'sess-1', 
      clientId: 'client-1', 
      durationMs: 150 
    });

    // Wait for async compute
    await new Promise(resolve => setTimeout(resolve, 10));

    expect(deltaSync.computeDeltaForClient).toHaveBeenCalledWith('sess-1', 'client-1');
    expect(recoveryListener).toHaveBeenCalledWith({
      sessionId: 'sess-1',
      clientId: 'client-1',
      deltaSize: 3,
      recoveryTimeMs: 150
    });
  });

  it('should handle manual optimized recovery', async () => {
    const successListener = vi.fn();
    coordinator.on('manual-recovery-success', successListener);

    await coordinator.triggerOptimizedRecovery('sess-1', 'client-1');

    expect(migration.performQuickMigration).toHaveBeenCalledWith('sess-1', 'client-1');
    expect(successListener).toHaveBeenCalledWith({
      sessionId: 'sess-1',
      clientId: 'client-1'
    });
  });
});
