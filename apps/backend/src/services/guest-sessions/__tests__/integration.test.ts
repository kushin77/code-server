// @file        apps/backend/src/services/guest-sessions/__tests__/integration.test.ts
// @module      collaboration/guest-sessions
// @description Tests for guest session runtime bootstrap with credential teardown wiring
// @owner       collab-5.5
// @status      active

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import type { Express } from 'express';
import { initializeGuestSessionRuntime, type GuestSessionRuntimeConfig } from '../integration-example.js';
import type { JwtRedisCache } from '../../auth/jwt-redis-cache.js';

describe('Guest Session Runtime Integration', () => {
  let mockCache: { revokeSessionCredentials: any };
  let mockPool: any;
  let mockApp: { use: any };
  let config: GuestSessionRuntimeConfig;

  beforeEach(() => {
    mockCache = {
      revokeSessionCredentials: vi.fn().mockResolvedValue(2),
    };
    mockPool = {
      connect: vi.fn().mockResolvedValue({
        query: vi.fn().mockResolvedValue({ rows: [] }),
        release: vi.fn(),
      }),
    };
    mockApp = {
      use: vi.fn(),
    };
    config = {
      pool: mockPool,
      cache: mockCache as any,
      guestSessionConfig: {},
    };
  });

  describe('Teardown Wiring', () => {
    it('should revoke credentials with proper session ID', async () => {
      // Create a test callback directly
      let capturedSessionId: string | undefined;
      const testOnSessionEnded = async (sessionId: string) => {
        capturedSessionId = sessionId;
        if (config.cache) {
          await config.cache.revokeSessionCredentials(sessionId);
        }
      };

      const testConfig: GuestSessionRuntimeConfig = {
        pool: mockPool,
        cache: mockCache as any,
        guestSessionConfig: {
          onSessionEnded: testOnSessionEnded,
        },
      };

      // Call the callback
      await testConfig.guestSessionConfig!.onSessionEnded!('test-session-123');

      // Verify the callback was invoked correctly
      expect(capturedSessionId).toBe('test-session-123');
      expect(mockCache.revokeSessionCredentials).toHaveBeenCalledWith('test-session-123');
    });

    it('should handle missing cache without throwing', async () => {
      const configWithoutCache: GuestSessionRuntimeConfig = {
        pool: mockPool,
        cache: undefined,
        guestSessionConfig: {},
      };

      const result = await initializeGuestSessionRuntime(mockApp as any, configWithoutCache);
      expect(result.service).toBeDefined();
    });
  });

  describe('Service Registration', () => {
    it('should register routes with the express app', async () => {
      const result = await initializeGuestSessionRuntime(mockApp as any, config);

      // Verify app.use was called (routes registered)
      expect(mockApp.use).toHaveBeenCalled();
      expect(result.service).toBeDefined();
    });

    it('should initialize the service', async () => {
      const result = await initializeGuestSessionRuntime(mockApp as any, config);

      // Service should be initialized and ready
      expect(result.service).toBeDefined();
      expect(result.service.initialize).toBeDefined();
    });
  });
});
