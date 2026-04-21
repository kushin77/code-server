// @file        apps/backend/src/services/auth/__tests__/role-manager.test.ts
// @module      auth/role-management
// @description Unit tests for RoleManager service

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { RoleManager } from '../role-manager';

// Mock Redis and Database
vi.mock('ioredis');
vi.mock('../../db', () => ({
  Database: vi.fn(),
}));

describe('RoleManager', () => {
  let roleManager: RoleManager;
  let mockRedis: any;
  let mockDb: any;

  beforeEach(() => {
    // Create mock Redis instance
    mockRedis = {
      setex: vi.fn(),
      get: vi.fn(),
      del: vi.fn(),
      keys: vi.fn(),
      mget: vi.fn(),
    };
    
    // Create mock Database instance
    mockDb = {
      query: vi.fn(),
    };
    
    roleManager = new RoleManager(mockRedis, mockDb);
  });

  describe('assignRoles', () => {
    it('should assign roles to a user', async () => {
      mockRedis.setex = vi.fn().mockResolvedValue('OK');

      await roleManager.assignRoles('user-123', ['admin', 'developer']);

      expect(mockRedis.setex).toHaveBeenCalledWith(
        'roles:user-123',
        3600, // 1 hour TTL
        JSON.stringify(['admin', 'developer'])
      );
    });

    it('should support custom TTL', async () => {
      mockRedis.setex = vi.fn().mockResolvedValue('OK');

      await roleManager.assignRoles('user-123', ['developer'], 7200);

      expect(mockRedis.setex).toHaveBeenCalledWith(
        'roles:user-123',
        7200,
        JSON.stringify(['developer'])
      );
    });

    it('should deduplicate roles', async () => {
      mockRedis.setex = vi.fn().mockResolvedValue('OK');

      await roleManager.assignRoles('user-123', ['admin', 'admin', 'developer']);

      const savedRoles = JSON.parse(
        (mockRedis.setex as jest.Mock).mock.calls[0][2]
      );
      expect(savedRoles).toEqual(['admin', 'developer']);
    });
  });

  describe('getUserRoles', () => {
    it('should retrieve user roles from cache', async () => {
      const roles = ['admin', 'developer'];
      mockRedis.get = jest
        .fn()
        .mockResolvedValue(JSON.stringify(roles));

      const result = await roleManager.getUserRoles('user-123');

      expect(result).toEqual(roles);
      expect(mockRedis.get).toHaveBeenCalledWith('roles:user-123');
    });

    it('should return empty array if no roles found', async () => {
      mockRedis.get = vi.fn().mockResolvedValue(null);

      const result = await roleManager.getUserRoles('user-123');

      expect(result).toEqual([]);
    });

    it('should handle cache misses gracefully', async () => {
      mockRedis.get = jest
        .fn()
        .mockRejectedValue(new Error('Redis error'));

      const result = await roleManager.getUserRoles('user-123');

      expect(result).toEqual([]);
    });
  });

  describe('removeRole', () => {
    it('should remove a specific role from user', async () => {
      mockRedis.get = jest
        .fn()
        .mockResolvedValue(JSON.stringify(['admin', 'developer']));
      mockRedis.setex = jest.fn().mockResolvedValue('OK');

      await roleManager.removeRole('user-123', 'admin');

      const savedRoles = JSON.parse(
        (mockRedis.setex as jest.Mock).mock.calls[0][2]
      );
      expect(savedRoles).toEqual(['developer']);
    });

    it('should handle removing non-existent role', async () => {
      mockRedis.get = jest
        .fn()
        .mockResolvedValue(JSON.stringify(['developer']));
      mockRedis.setex = jest.fn().mockResolvedValue('OK');

      await roleManager.removeRole('user-123', 'admin');

      const savedRoles = JSON.parse(
        (mockRedis.setex as jest.Mock).mock.calls[0][2]
      );
      expect(savedRoles).toEqual(['developer']);
    });
  });

  describe('clearRoles', () => {
    it('should clear all roles for a user', async () => {
      mockRedis.del = jest.fn().mockResolvedValue(1);

      await roleManager.clearRoles('user-123');

      expect(mockRedis.del).toHaveBeenCalledWith('roles:user-123');
    });
  });

  describe('listAllRoles', () => {
    it('should list all role assignments', async () => {
      mockRedis.keys = jest
        .fn()
        .mockResolvedValue(['roles:user-1', 'roles:user-2']);
      mockRedis.mget = jest.fn().mockResolvedValue([
        JSON.stringify(['admin']),
        JSON.stringify(['developer']),
      ]);

      const result = await roleManager.listAllRoles();

      expect(result).toEqual({
        'user-1': ['admin'],
        'user-2': ['developer'],
      });
    });

    it('should handle empty role cache', async () => {
      mockRedis.keys = jest.fn().mockResolvedValue([]);

      const result = await roleManager.listAllRoles();

      expect(result).toEqual({});
    });
  });

  describe('caching', () => {
    it('should cache role lookups', async () => {
      const roles = ['admin'];
      mockRedis.get = jest
        .fn()
        .mockResolvedValue(JSON.stringify(roles));

      // First call
      await roleManager.getUserRoles('user-123');
      // Second call should use cache
      await roleManager.getUserRoles('user-123');

      expect(mockRedis.get).toHaveBeenCalledTimes(2);
    });

    it('should invalidate cache on role assignment', async () => {
      mockRedis.setex = jest.fn().mockResolvedValue('OK');
      mockRedis.del = jest.fn().mockResolvedValue(1);

      await roleManager.assignRoles('user-123', ['admin']);

      expect(mockRedis.del).toHaveBeenCalledWith('roles:user-123');
    });
  });
});
