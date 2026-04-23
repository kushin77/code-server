// @file        apps/backend/src/services/voice-channel/integration-example.ts
// @module      collaboration/voice-channel
// @description Integration example: wiring voice channel into Express app

import express from 'express';
import { AuditService } from '../audit/audit-service.js';
import { initializeVoiceChannelService } from './index.js';
import { initializeVoiceChannelRoutes } from './routes.js';

export async function initializeVoiceChannelRuntime(app, options) {
  const { pool, redis, config } = options;
  const auditService = options.auditService ?? new AuditService(pool);

  const voiceService = await initializeVoiceChannelService(config, pool, redis);

  const voiceRoutes = initializeVoiceChannelRoutes(voiceService, auditService);
  app.use(voiceRoutes);

  voiceService.on('session_created', (event) => {
    console.log(`[VoiceChannel] Session created: ${event.sessionId}`);
  });

  voiceService.on('participant_joined', (event) => {
    console.log(`[VoiceChannel] Participant joined: ${event.data?.userId}`);
    if (event.data?.userId && options.onMeetingModeChange) {
      void options.onMeetingModeChange(event.data.userId, true, event.sessionId);
    }
  });

  voiceService.on('participant_left', (event) => {
    console.log(`[VoiceChannel] Participant left: ${event.data?.userId}`);
    if (event.data?.userId && options.onMeetingModeChange) {
      void options.onMeetingModeChange(event.data.userId, false, event.sessionId);
    }
  });

  voiceService.on('latency_high', (event) => {
    console.warn(
      `[VoiceChannel] High latency detected: ${event.data?.latencyMs}ms (SLA: <60ms)`
    );
  });

  voiceService.on('audio_quality_degraded', (event) => {
    console.warn(`[VoiceChannel] Audio quality degraded: ${event.data?.qualityScore}/100`);
  });

  voiceService.on('session_ended', (event) => {
    console.log(`[VoiceChannel] Session ended: ${event.sessionId}`);
  });

  console.log('[VoiceChannelRuntime] Initialized with routes /api/voice/*');
  console.log(`[VoiceChannelRuntime] LiveKit SFU: ${config.liveKitUrl}`);
  console.log(`[VoiceChannelRuntime] Noise cancellation: ${config.noiseCancellationEnabled}`);
  console.log(`[VoiceChannelRuntime] Target latency: <${config.targetLatencyMs}ms (SLA)`);

  return { service: voiceService };
}

function createMemoryPool() {
  return {
    query: async () => ({ rows: [] }),
    connect: async () => ({
      query: async () => ({ rows: [] }),
      release: () => undefined,
    }),
    end: async () => undefined,
  };
}

function createMemoryRedis() {
  const sessionStore = new Map();

  return {
    keys: async (pattern) => Array.from(sessionStore.keys()).filter((key) => key.startsWith(pattern.replace('*', ''))),
    get: async (key) => sessionStore.get(key) ?? null,
    setex: async (key, _ttl, value) => {
      sessionStore.set(key, value);
      return 'OK';
    },
    del: async (key) => (sessionStore.delete(key) ? 1 : 0),
  };
}

function resolveExampleConfig(config) {
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

export async function setupVoiceChannelIntegration(app, options = {}) {
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

export async function createVoiceChannelExampleApp(options = {}) {
  const app = express();

  app.use(express.json());
  await setupVoiceChannelIntegration(app, options);

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok', services: ['voice-channel'] });
  });

  return app;
}