// @file        apps/backend/src/services/voice-channel/integration-example.ts
// @module      collaboration/voice-channel
// @description Integration example: wiring voice channel into Express app

import express from 'express';
import type { Express } from 'express';
import { Pool } from 'pg';
import Redis from 'ioredis';
import { AuditService } from '../audit/audit-service';
import { VoiceChannelService, initializeVoiceChannelService } from './index';
import { initializeVoiceChannelRoutes } from './routes';
import { VoiceChannelConfig, VoiceChannelEvent } from './types';

export interface VoiceChannelRuntimeConfig {
  pool: Pool;
  redis: Redis;
  config: VoiceChannelConfig;
  auditService?: AuditService;
  onMeetingModeChange?: (userId: string, isInMeeting: boolean, sessionId: string) => Promise<void> | void;
}

export interface VoiceChannelRuntimeResult {
  service: VoiceChannelService;
}

export interface VoiceChannelExampleOptions extends Partial<Pick<VoiceChannelRuntimeConfig, 'config' | 'auditService' | 'onMeetingModeChange'>> {
  pool?: Pool;
  redis?: Redis;
}

function createMemoryPool(): Pool {
  return {
    query: async () => ({ rows: [] }),
    connect: async () => ({
      query: async () => ({ rows: [] }),
      release: () => undefined,
    }),
    end: async () => undefined,
  } as unknown as Pool;
}

function createMemoryRedis(): Redis {
  const sessionStore = new Map<string, string>();

  return {
    keys: async (pattern: string) => Array.from(sessionStore.keys()).filter((key) => key.startsWith(pattern.replace('*', ''))),
    get: async (key: string) => sessionStore.get(key) ?? null,
    setex: async (key: string, _ttl: number, value: string) => {
      sessionStore.set(key, value);
      return 'OK';
    },
    del: async (key: string) => (sessionStore.delete(key) ? 1 : 0),
  } as unknown as Redis;
}

function resolveExampleConfig(config?: VoiceChannelConfig): VoiceChannelConfig {
  if (config) {
    return config;
  }

  const liveKitUrl = process.env.LIVEKIT_URL;
  const liveKitApiKey = process.env.LIVEKIT_API_KEY;
  const liveKitApiSecret = process.env.LIVEKIT_API_SECRET;

  if (!liveKitUrl || !liveKitApiKey || !liveKitApiSecret) {
    throw new Error('Voice channel example config requires LiveKit environment variables or an explicit config');
  }

  return {
    liveKitUrl,
    liveKitApiKey,
    liveKitApiSecret,
    noiseCancellationEnabled: true,
    targetLatencyMs: 60,
    maxParticipantsPerRoom: 50,
    audioCodec: 'opus',
    enableRecording: false,
  };
}

/**
 * Initialize voice channel service and wire into Express app
 * Integrates with presence system via event emitter
 *
 * @example
 * const voiceService = await initializeVoiceChannelRuntime(app, {
 *   pool,
 *   redis,
 *   config: {
 *     liveKitUrl: 'wss://livekit.kushnir.cloud',
 *     liveKitApiKey: process.env.LIVEKIT_API_KEY,
 *     liveKitApiSecret: process.env.LIVEKIT_API_SECRET,
 *     noiseCancellationEnabled: true,
 *     targetLatencyMs: 60,
 *     maxParticipantsPerRoom: 50,
 *     audioCodec: 'opus',
 *     enableRecording: false,
 *   },
 * });
 */
export async function initializeVoiceChannelRuntime(
  app: Express,
  options: VoiceChannelRuntimeConfig
): Promise<VoiceChannelRuntimeResult> {
  const { pool, redis, config } = options;
  const auditService = options.auditService ?? new AuditService(pool);

  // Initialize voice channel service
  const voiceService = await initializeVoiceChannelService(config, pool, redis);

  // Mount REST API routes
  const voiceRoutes = initializeVoiceChannelRoutes(voiceService, auditService);
  app.use(voiceRoutes);

  // Wire voice channel events into presence system
  voiceService.on('session_created', (event: VoiceChannelEvent) => {
    console.log(`[VoiceChannel] Session created: ${event.sessionId}`);
  });

  voiceService.on('participant_joined', (event: VoiceChannelEvent) => {
    console.log(`[VoiceChannel] Participant joined: ${event.data?.userId}`);
    if (event.data?.userId && options.onMeetingModeChange) {
      void options.onMeetingModeChange(event.data.userId, true, event.sessionId);
    }
  });

  voiceService.on('participant_left', (event: VoiceChannelEvent) => {
    console.log(`[VoiceChannel] Participant left: ${event.data?.userId}`);
    if (event.data?.userId && options.onMeetingModeChange) {
      void options.onMeetingModeChange(event.data.userId, false, event.sessionId);
    }
  });

  voiceService.on('latency_high', (event: VoiceChannelEvent) => {
    console.warn(
      `[VoiceChannel] High latency detected: ${event.data?.latencyMs}ms (SLA: <60ms)`
    );
    // Could alert monitoring system
  });

  voiceService.on('audio_quality_degraded', (event: VoiceChannelEvent) => {
    console.warn(
      `[VoiceChannel] Audio quality degraded: ${event.data?.qualityScore}/100`
    );
    // Could suggest codec change or bandwidth optimization
  });

  voiceService.on('session_ended', (event: VoiceChannelEvent) => {
    console.log(`[VoiceChannel] Session ended: ${event.sessionId}`);
    // Cleanup presence markers
  });

  console.log('[VoiceChannelRuntime] Initialized with routes /api/voice/*');
  console.log(`[VoiceChannelRuntime] LiveKit SFU: ${config.liveKitUrl}`);
  console.log(
    `[VoiceChannelRuntime] Noise cancellation: ${config.noiseCancellationEnabled}`
  );
  console.log(`[VoiceChannelRuntime] Target latency: <${config.targetLatencyMs}ms (SLA)`);

  return { service: voiceService };
}

export async function setupVoiceChannelIntegration(
  app: Express,
  options: VoiceChannelExampleOptions = {}
): Promise<VoiceChannelRuntimeResult> {
  const pool = options.pool ?? createMemoryPool();
  const redis = options.redis ?? createMemoryRedis();
  const config = resolveExampleConfig(options.config);

  return initializeVoiceChannelRuntime(app, {
    pool,
    redis,
    config,
    auditService: options.auditService,
    onMeetingModeChange: options.onMeetingModeChange,
  });
}

export async function createVoiceChannelExampleApp(
  options: VoiceChannelExampleOptions = {}
): Promise<Express> {
  const app = express();

  app.use(express.json());
  await setupVoiceChannelIntegration(app, options);

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok', services: ['voice-channel'] });
  });

  return app;
}
