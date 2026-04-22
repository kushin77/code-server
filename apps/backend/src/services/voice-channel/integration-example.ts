// @file        apps/backend/src/services/voice-channel/integration-example.ts
// @module      collaboration/voice-channel
// @description Integration example: wiring voice channel into Express app

import { Express } from 'express';
import { Pool } from 'pg';
import Redis from 'ioredis';
import { VoiceChannelService, initializeVoiceChannelService } from './index';
import { initializeVoiceChannelRoutes } from './routes';
import { VoiceChannelConfig, VoiceChannelEvent } from './types';

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
  options: {
    pool: Pool;
    redis: Redis;
    config: VoiceChannelConfig;
  }
): Promise<VoiceChannelService> {
  const { pool, redis, config } = options;

  // Initialize voice channel service
  const voiceService = await initializeVoiceChannelService(config, pool, redis);

  // Mount REST API routes
  const voiceRoutes = initializeVoiceChannelRoutes(voiceService);
  app.use(voiceRoutes);

  // Wire voice channel events into presence system
  // (This would integrate with rich-presence service for team awareness)
  voiceService.on('session_created', (event: VoiceChannelEvent) => {
    console.log(`[VoiceChannel] Session created: ${event.sessionId}`);
    // Could emit to presence system here
  });

  voiceService.on('participant_joined', (event: VoiceChannelEvent) => {
    console.log(`[VoiceChannel] Participant joined: ${event.data?.userId}`);
    // Update user presence to show "in voice call"
  });

  voiceService.on('participant_left', (event: VoiceChannelEvent) => {
    console.log(`[VoiceChannel] Participant left: ${event.data?.userId}`);
    // Update user presence
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

  return voiceService;
}
