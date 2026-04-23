// @file        apps/backend/src/server.ts
// @module      backend/server
// @description Bootstraps the backend runtime entrypoint for local development
// @owner       backend

import { pathToFileURL } from 'node:url';
import type { Express } from 'express';

import {
  createVoiceChannelExampleApp,
  type VoiceChannelConfig,
  type VoiceChannelExampleOptions,
} from './services/voice-channel/integration-example';

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
  return createVoiceChannelExampleApp({
    pool: options.pool,
    redis: options.redis,
    config: resolveVoiceChannelConfig(options.config),
    auditService: options.auditService,
    onMeetingModeChange: options.onMeetingModeChange,
  });
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