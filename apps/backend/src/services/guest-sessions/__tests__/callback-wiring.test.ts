#!/usr/bin/env node
// @file        apps/backend/src/services/guest-sessions/__tests__/callback-wiring.test.ts
// @module      collaboration/guest-sessions
// @description Test guest session callback wiring for credentials teardown
// @owner       collab-5.5
// @status      active

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { GuestSessionService } from '../index';
import { Pool } from 'pg';

vi.mock('../../../lib/logger', () => ({
  getLogger: vi.fn(() => ({
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
  })),
}));

describe('Guest session credential teardown wiring', () => {
  let mockPool: Partial<Pool>;
  let mockClient: any;

  beforeEach(() => {
    mockClient = {
      query: vi.fn(),
      release: vi.fn(),
    };

    mockPool = {
      connect: vi.fn(async () => mockClient),
    } as unknown as Pool;
  });

  describe('callback storage and invocation', () => {
    it('should store and invoke onSessionEnded callback on session revocation', async () => {
      // Create a mock revocation callback
      const revokeCallback = vi.fn(async (sessionId: string) => {
        // Simulate credential revocation
      });

      // Create service with callback
      const service = new GuestSessionService(mockPool as Pool, {
        onSessionEnded: revokeCallback,
      });

      // Mock the database query response
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      // Revoke a session
      const sessionId = 'test-session-123';
      await service.revokeSession(sessionId);

      // Verify callback was invoked
      expect(revokeCallback).toHaveBeenCalledTimes(1);
      expect(revokeCallback).toHaveBeenCalledWith(sessionId);
    });

    it('should work with JwtRedisCache-like revocation interface', async () => {
      // Mock JwtRedisCache revocation interface
      const mockCache = {
        revokeSessionCredentials: vi.fn(async (sessionId: string) => {
          // Simulate redis deletion
        }),
      };

      // Create service with cache revocation callback
      const service = new GuestSessionService(mockPool as Pool, {
        onSessionEnded: async (sessionId: string) => {
          await mockCache.revokeSessionCredentials(sessionId);
        },
      });

      // Mock the database query response
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      // Revoke a session
      const sessionId = 'guest-session-xyz';
      await service.revokeSession(sessionId);

      // Verify cache revocation was called
      expect(mockCache.revokeSessionCredentials).toHaveBeenCalledWith(sessionId);
    });

    it('should survive callback errors during revocation', async () => {
      const failingCallback = vi.fn(async () => {
        throw new Error('Cache unavailable');
      });

      const service = new GuestSessionService(mockPool as Pool, {
        onSessionEnded: failingCallback,
      });

      mockClient.query.mockResolvedValueOnce({ rows: [] });

      // Should not throw despite callback error
      await expect(
        service.revokeSession('session-456')
      ).resolves.not.toThrow();

      // Callback was still attempted
      expect(failingCallback).toHaveBeenCalled();
    });

    it('should invoke callbacks for all expired sessions during cleanup', async () => {
      const cleanupCallback = vi.fn(async (sessionId: string) => {
        // Cleanup credentials
      });

      const service = new GuestSessionService(mockPool as Pool, {
        onSessionEnded: cleanupCallback,
      });

      // Mock cleanup response with 3 expired sessions
      mockClient.query.mockResolvedValueOnce({
        rows: [
          { id: 'expired-1' },
          { id: 'expired-2' },
          { id: 'expired-3' },
        ],
      });

      const count = await service.cleanupExpiredSessions();

      expect(count).toBe(3);
      expect(cleanupCallback).toHaveBeenCalledTimes(3);
      expect(cleanupCallback).toHaveBeenNthCalledWith(1, 'expired-1');
      expect(cleanupCallback).toHaveBeenNthCalledWith(2, 'expired-2');
      expect(cleanupCallback).toHaveBeenNthCalledWith(3, 'expired-3');
    });
  });
});
