// @file        apps/backend/src/server.ts
// @module      backend/server
// @description Bootstraps the backend runtime entrypoint for local development
// @owner       backend

import { pathToFileURL } from 'node:url';
import type { Express } from 'express';

import { createVoiceChannelExampleApp, type VoiceChannelConfig, type VoiceChannelExampleOptions, initializeVoiceChannelRuntime } from './services/voice-channel/integration-example';
import { SessionLifecycleCoordinator } from './services/session/coordination/session-lifecycle-coordinator';
import { NetworkResilienceCoordinator } from './services/network/coordination/network-resilience-coordinator';
import { HibernationService } from './services/session/session-hibernation-service';
import { SessionSnapshotService } from './services/session/session-snapshot-service';
import { SessionBrokerService } from './services/session-broker/session-broker-service';
import { DeltaSyncService } from './services/network/delta-sync-service';
import { MigrationRecoveryService } from './services/network/migration-recovery-service';
import { SessionResilienceHealthService } from './services/health-monitoring';
import pino from 'pino';

export interface BackendServerOptions extends VoiceChannelExampleOptions {
  port?: number;
}

function resolveVoiceChannelConfig(config?: VoiceChannelConfig): VoiceChannelConfig {
  if (config) {
    return config;
  }

  return {
    liveKitUrl: process.env.LIVEKIT_URL || 'wss://livekit.kushnir.cloud',
    liveKitApiKey: process.env.LIVEKIT_API_KEY || 'dev-key',
    liveKitApiSecret: process.env.LIVEKIT_API_SECRET || 'dev-secret',
    noiseCancellationEnabled: true,
    targetLatencyMs: 60,
    maxParticipantsPerRoom: 50,
    audioCodec: 'opus',
    enableRecording: false,
  };
}

export async function createBackendApp(options: BackendServerOptions = {}): Promise<Express> {
  const app = express();
  app.use(express.json());

  // Initialize Core Services
  const pool = options.pool ?? createMemoryPool();
  const redis = options.redis ?? createMemoryRedis();
  const logger = pino({ name: 'backend-server' });

  // Initialize Sub-services
  const hibernation = new HibernationService(logger);
  const snapshots = new SessionSnapshotService(pool, logger);
  const broker = new SessionBrokerService(redis, logger);
  const deltaSync = new DeltaSyncService(logger);
  const recovery = new MigrationRecoveryService(logger);

  // Initialize Coordinators
  const sessionCoordinator = new SessionLifecycleCoordinator(
    { 
      autoHibernationEnabled: process.env.SESSION_HIBERNATION_ENABLED === 'true', 
      idleTimeoutMs: Number(process.env.SESSION_HIBERNATION_IDLE_TIMEOUT_MS || 300000), 
      snapshotBeforeHibernation: process.env.SESSION_SNAPSHOT_BEFORE_HIBERNATION !== 'false' 
    },
    hibernation,
    snapshots,
    broker,
    logger
  );

  const networkCoordinator = new NetworkResilienceCoordinator(
    {
      deltaSyncEnabled: process.env.NETWORK_DELTA_SYNC_ENABLED !== 'false',
      recoveryEnabled: process.env.NETWORK_MIGRATION_RECOVERY_ENABLED !== 'false'
    },
    deltaSync,
    recovery,
    logger
  );

  // Initialize Health Monitoring
  const healthService = SessionResilienceHealthService.getInstance();
  await healthService.start();
  logger.info('Session Resilience Health Monitoring started');

  // Initialize Voice and other runtimes
  await initializeVoiceChannelRuntime(app, {
    pool,
    redis,
    config: resolveVoiceChannelConfig(options.config),
    auditService: options.auditService,
    onMeetingModeChange: options.onMeetingModeChange,
  });

  return app;
}

// Internal Mock Helpers for local dev bootstrap
function createMemoryPool(): any {
  return {
    query: async () => ({ rows: [] }),
    connect: async () => ({
      query: async () => ({ rows: [] }),
      release: () => undefined,
    }),
    end: async () => undefined,
  };
}

function createMemoryRedis(): any {
  const store = new Map<string, string>();
  return {
    get: async (key: string) => store.get(key) || null,
    set: async (key: string, val: string) => { store.set(key, val); return 'OK'; },
    del: async (key: string) => store.delete(key) ? 1 : 0,
    keys: async (pattern: string) => Array.from(store.keys()),
  };
}

export async function startBackendServer(options: BackendServerOptions = {}): Promise<Express> {
  const app = await createBackendApp(options);
  const port = options.port ?? Number(process.env.PORT || 3000);

  app.listen(port, () => {
    console.log(`[BackendServer] Listening on port ${port}`);
  });

  return app;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  void startBackendServer().catch((error) => {
    console.error('[BackendServer] Failed to start', error);
    process.exitCode = 1;
  });
}