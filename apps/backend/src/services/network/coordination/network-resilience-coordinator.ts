/**
 * Network Resilience Coordinator
 * Integrates Delta Sync and Network Migration for optimized recovery
 * @file        apps/backend/src/services/network/coordination/network-resilience-coordinator.ts
 * @module      network/coordination
 * @description Orchestrates zero-bandwidth reconnection and adaptive buffering
 */

import { EventEmitter } from 'events';
import pino from 'pino';
import { DeltaSyncService } from '../../crdt/delta-sync-service.js';
import { MigrationRecoveryService } from '../migration-recovery-service.js';

export interface ResilienceConfig {
  enableDeltaReconnection: boolean;
  adaptiveBufferingEnabled: boolean;
  recoveryTimeoutMs: number;
}

/**
 * Coordinator that manages network transitions and optimizes recovery via Delta Sync.
 */
export class NetworkResilienceCoordinator extends EventEmitter {
  private static instance: NetworkResilienceCoordinator;
  private logger: pino.Logger;
  
  private deltaSync: DeltaSyncService;
  private migration: MigrationRecoveryService;

  constructor(
    config: ResilienceConfig,
    deltaSync: DeltaSyncService,
    migration: MigrationRecoveryService,
    logger?: pino.Logger
  ) {
    super();
    this.deltaSync = deltaSync;
    this.migration = migration;
    this.logger = logger || pino({ name: 'network-resilience-coordinator' });

    this.logger.info('NetworkResilienceCoordinator initialized');
    this.setupIntegration();
  }

  static getInstance(
    config: ResilienceConfig,
    deltaSync: DeltaSyncService,
    migration: MigrationRecoveryService
  ): NetworkResilienceCoordinator {
    if (!NetworkResilienceCoordinator.instance) {
      NetworkResilienceCoordinator.instance = new NetworkResilienceCoordinator(
        config,
        deltaSync,
        migration
      );
    }
    return NetworkResilienceCoordinator.instance;
  }

  private setupIntegration(): void {
    // Listen for migration events and trigger delta-optimized recovery
    this.migration.on('migration-detected', (data) => {
      this.logger.info({ sessionId: data.sessionId, clientId: data.clientId }, 'Migration detected, preparing delta sync buffers');
      this.deltaSync.prepareSyncBuffer(data.sessionId, data.clientId);
    });

    this.migration.on('migration-completed', async (data) => {
      this.logger.info({ sessionId: data.sessionId, clientId: data.clientId }, 'Migration completed, executing delta sync recovery');
      
      try {
        const delta = await this.deltaSync.computeDeltaForClient(data.sessionId, data.clientId);
        this.emit('recovery-optimized', { 
          sessionId: data.sessionId, 
          clientId: data.clientId, 
          deltaSize: delta.length,
          recoveryTimeMs: data.durationMs
        });
      } catch (error) {
        this.logger.error({ sessionId: data.sessionId, error }, 'Failed to compute recovery delta');
      }
    });
  }

  /**
   * Manually trigger an optimized recovery
   */
  async triggerOptimizedRecovery(sessionId: string, clientId: string): Promise<void> {
    this.logger.info({ sessionId, clientId }, 'Manual optimized recovery triggered');
    
    try {
      await this.migration.performQuickMigration(sessionId, clientId);
      this.emit('manual-recovery-success', { sessionId, clientId });
    } catch (error) {
      this.logger.error({ sessionId, error }, 'Manual recovery failed');
      this.emit('manual-recovery-failed', { sessionId, clientId, error });
    }
  }
}
