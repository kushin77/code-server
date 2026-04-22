#!/usr/bin/env node
// @file        apps/backend/src/services/guest-sessions/__tests__/guest-sessions.test.ts
// @module      collaboration/guest-sessions
// @description Comprehensive guest sessions service tests
// @owner       collab-5.5
// @status      active

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
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

describe('GuestSessionService', () => {
  let service: GuestSessionService;
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

    service = new GuestSessionService(mockPool as Pool);
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('initialization', () => {
    it('should initialize tables on first call', async () => {
      mockClient.query.mockResolvedValueOnce({}); // BEGIN
      mockClient.query.mockResolvedValueOnce({}); // CREATE guest_sessions
      mockClient.query.mockResolvedValueOnce({}); // CREATE activity_log
      mockClient.query.mockResolvedValueOnce({}); // CREATE indexes
      mockClient.query.mockResolvedValueOnce({}); // COMMIT

      await service.initialize();

      expect(mockClient.query).toHaveBeenCalledWith('BEGIN');
      expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('CREATE TABLE IF NOT EXISTS guest_sessions'));
      expect(mockPool.connect).toHaveBeenCalled();
    });

    it('should not reinitialize if already initialized', async () => {
      mockClient.query.mockResolvedValue({});

      await service.initialize();
      const firstCallCount = (mockPool.connect as any).mock.calls.length;

      await service.initialize();
      const secondCallCount = (mockPool.connect as any).mock.calls.length;

      expect(secondCallCount).toBe(firstCallCount);
    });
  });

  describe('createGuestSession', () => {
    beforeEach(() => {
      mockClient.query.mockResolvedValue({ rows: [{ count: 0 }] });
    });

    it('should create a guest session with default access level', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [{ count: 0 }] }); // Count active
      mockClient.query.mockResolvedValueOnce({}); // Insert

      const session = await service.createGuestSession('user123', '/home/user');

      expect(session.userId).toBe('user123');
      expect(session.scopedPath).toBe('/home/user');
      expect(session.accessLevel).toBe('read');
      expect(session.isActive).toBe(true);
      expect(session.guestToken).toMatch(/^[a-f0-9]+$/);
    });

    it('should create a guest session with custom TTL', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [{ count: 0 }] }); // Count
      mockClient.query.mockResolvedValueOnce({}); // Insert

      const session = await service.createGuestSession('user123', '/home/user', 120, 'read-write');

      expect(session.accessLevel).toBe('read-write');
      expect(session.expiresAt.getTime()).toBeGreaterThan(Date.now() + 100 * 60 * 1000);
    });

    it('should reject when max active sessions reached', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [{ count: 10 }] }); // Count at limit

      await expect(service.createGuestSession('user123', '/home/user')).rejects.toThrow(
        /max active guest sessions/
      );
    });

    it('should emit session-created event', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [{ count: 0 }] });
      mockClient.query.mockResolvedValueOnce({});

      const eventSpy = vi.fn();
      service.on('session-created', eventSpy);

      await service.createGuestSession('user123', '/home/user');

      expect(eventSpy).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'user123',
          scopedPath: '/home/user',
        })
      );
    });
  });

  describe('getGuestSession', () => {
    it('should retrieve an active session', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'session-123',
            user_id: 'user123',
            guest_token: 'token123',
            scoped_path: '/home/user',
            access_level: 'read',
            expires_at: new Date(Date.now() + 3600000),
            is_active: true,
            created_at: new Date(),
            updated_at: new Date(),
          },
        ],
      });

      const session = await service.getGuestSession('token123');

      expect(session).not.toBeNull();
      expect(session?.guestToken).toBe('token123');
      expect(session?.userId).toBe('user123');
    });

    it('should return null for expired session', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const session = await service.getGuestSession('token123');

      expect(session).toBeNull();
    });

    it('should return null for inactive session', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const session = await service.getGuestSession('token123');

      expect(session).toBeNull();
    });
  });

  describe('validateGuestAccess', () => {
    it('should allow access to scoped path', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'session-123',
            user_id: 'user123',
            guest_token: 'token123',
            scoped_path: '/home/user',
            access_level: 'read',
            expires_at: new Date(Date.now() + 3600000),
            is_active: true,
            created_at: new Date(),
            updated_at: new Date(),
          },
        ],
      });

      const result = await service.validateGuestAccess('token123', '/home/user');

      expect(result.allowed).toBe(true);
      expect(result.accessLevel).toBe('read');
    });

    it('should allow access to nested paths within scope', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'session-123',
            user_id: 'user123',
            guest_token: 'token123',
            scoped_path: '/home/user',
            access_level: 'read',
            expires_at: new Date(Date.now() + 3600000),
            is_active: true,
            created_at: new Date(),
            updated_at: new Date(),
          },
        ],
      });

      const result = await service.validateGuestAccess('token123', '/home/user/docs/file.txt');

      expect(result.allowed).toBe(true);
    });

    it('should deny access outside scoped path', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'session-123',
            user_id: 'user123',
            guest_token: 'token123',
            scoped_path: '/home/user',
            access_level: 'read',
            expires_at: new Date(Date.now() + 3600000),
            is_active: true,
            created_at: new Date(),
            updated_at: new Date(),
          },
        ],
      });

      const result = await service.validateGuestAccess('token123', '/root/sensitive');

      expect(result.allowed).toBe(false);
    });

    it('should deny access for invalid session', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const result = await service.validateGuestAccess('invalid-token', '/home/user');

      expect(result.allowed).toBe(false);
    });
  });

  describe('trackActivity', () => {
    it('should track guest activity', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'session-123',
            user_id: 'user123',
            guest_token: 'token123',
            scoped_path: '/home/user',
            access_level: 'read',
            expires_at: new Date(Date.now() + 3600000),
            is_active: true,
            created_at: new Date(),
            updated_at: new Date(),
          },
        ],
      });
      mockClient.query.mockResolvedValueOnce({});

      const eventSpy = vi.fn();
      service.on('activity-tracked', eventSpy);

      await service.trackActivity('token123', 'read', '/home/user/file.txt', '192.168.1.1', 'Mozilla/5.0');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO guest_activity_log'),
        expect.arrayContaining(['read', '/home/user/file.txt', '192.168.1.1'])
      );
      expect(eventSpy).toHaveBeenCalled();
    });

    it('should reject tracking for invalid session', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await expect(service.trackActivity('invalid-token', 'read', '/path')).rejects.toThrow(/Invalid guest session/);
    });
  });

  describe('getUserSessions', () => {
    it('should list all user sessions', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'session-1',
            user_id: 'user123',
            guest_token: 'token1',
            scoped_path: '/home/user',
            access_level: 'read',
            expires_at: new Date(),
            is_active: true,
            created_at: new Date(),
            updated_at: new Date(),
          },
          {
            id: 'session-2',
            user_id: 'user123',
            guest_token: 'token2',
            scoped_path: '/home/user/projects',
            access_level: 'read-write',
            expires_at: new Date(),
            is_active: true,
            created_at: new Date(),
            updated_at: new Date(),
          },
        ],
      });

      const sessions = await service.getUserSessions('user123');

      expect(sessions).toHaveLength(2);
      expect(sessions[0].guestToken).toBe('token1');
      expect(sessions[1].guestToken).toBe('token2');
    });

    it('should return empty array for user with no sessions', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const sessions = await service.getUserSessions('user123');

      expect(sessions).toEqual([]);
    });
  });

  describe('revokeSession', () => {
    it('should revoke a session', async () => {
      mockClient.query.mockResolvedValueOnce({});

      const eventSpy = vi.fn();
      service.on('session-revoked', eventSpy);

      await service.revokeSession('session-123');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE guest_sessions SET is_active = false'),
        expect.arrayContaining(['session-123'])
      );
      expect(eventSpy).toHaveBeenCalled();
    });
  });

  describe('getSessionActivity', () => {
    it('should retrieve session activity log', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'activity-1',
            guest_session_id: 'session-123',
            action: 'read',
            path: '/home/user/file1.txt',
            ip_address: '192.168.1.1',
            user_agent: 'Mozilla/5.0',
            timestamp: new Date(),
          },
          {
            id: 'activity-2',
            guest_session_id: 'session-123',
            action: 'write',
            path: '/home/user/file2.txt',
            ip_address: '192.168.1.1',
            user_agent: 'Mozilla/5.0',
            timestamp: new Date(),
          },
        ],
      });

      const activity = await service.getSessionActivity('session-123', 50);

      expect(activity).toHaveLength(2);
      expect(activity[0].action).toBe('read');
      expect(activity[1].action).toBe('write');
    });

    it('should respect limit parameter', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.getSessionActivity('session-123', 25);

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.any(String),
        expect.arrayContaining(['session-123', 25])
      );
    });
  });

  describe('cleanupExpiredSessions', () => {
    it('should mark expired sessions as inactive', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [{ id: 'session-1' }, { id: 'session-2' }],
      });

      const eventSpy = vi.fn();
      service.on('sessions-cleaned', eventSpy);

      const count = await service.cleanupExpiredSessions();

      expect(count).toBe(2);
      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE guest_sessions SET is_active = false WHERE expires_at <= NOW()')
      );
      expect(eventSpy).toHaveBeenCalledWith(expect.objectContaining({ count: 2 }));
    });
  });

  describe('getSessionStats', () => {
    it('should return session statistics', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [{ count: '3' }] }); // Active
      mockClient.query.mockResolvedValueOnce({ rows: [{ count: '5' }] }); // Total
      mockClient.query.mockResolvedValueOnce({ rows: [{ count: '42' }] }); // Activity

      const stats = await service.getSessionStats('user123');

      expect(stats.active).toBe(3);
      expect(stats.total).toBe(5);
      expect(stats.totalActivity).toBe(42);
    });
  });
});
