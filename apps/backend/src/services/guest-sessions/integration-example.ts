// @file        apps/backend/src/services/guest-sessions/integration-example.ts
// @module      collaboration/guest-sessions
// @description Runtime bootstrap helper for guest sessions with credential teardown wiring
// @owner       collab-5.5
// @status      active

import type { Express } from 'express';
import type { Pool } from 'pg';

import { JwtRedisCache } from '../auth/jwt-redis-cache.js';
import { initializeGuestSessionRoutes } from '../../routes/guest-sessions.js';
import { GuestSessionService, type GuestSessionConfig } from './index.js';

export interface GuestSessionRuntimeConfig {
  pool: Pool;
  cache?: JwtRedisCache;
  guestSessionConfig?: Omit<GuestSessionConfig, 'onSessionEnded'>;
}

export interface GuestSessionRuntimeResult {
  service: GuestSessionService;
}

export async function initializeGuestSessionRuntime(
  app: Express,
  config: GuestSessionRuntimeConfig,
): Promise<GuestSessionRuntimeResult> {
  const service = new GuestSessionService(config.pool, {
    ...config.guestSessionConfig,
    onSessionEnded: async (guestSessionId: string) => {
      if (!config.cache) {
        return;
      }

      // Invalidate the JWT token associated with this guest session
      await config.cache.invalidateToken(guestSessionId);
    },
  });

  await service.initialize();
  app.use(initializeGuestSessionRoutes(service));

  return { service };
}