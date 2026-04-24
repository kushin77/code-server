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
    let roleManager;
    let mockRedis;
    let mockDb;
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
            mockDb.query = vi.fn().mockResolvedValue({ rows: [], rowCount: 1 });
            mockRedis.setex = vi.fn().mockResolvedValue('OK');
            mockRedis.del = vi.fn().mockResolvedValue(1);
            await roleManager.assignRoles('user-123', ['admin', 'developer']);
            expect(mockDb.query).toHaveBeenCalled();
            expect(mockRedis.del).toHaveBeenCalledWith('roles:user-123');
        });
        it('should support custom TTL', async () => {
            mockDb.query = vi.fn().mockResolvedValue({ rows: [], rowCount: 1 });
            mockRedis.setex = vi.fn().mockResolvedValue('OK');
            mockRedis.del = vi.fn().mockResolvedValue(1);
            await roleManager.assignRoles('user-123', ['developer'], 7200);
            expect(mockDb.query).toHaveBeenCalled();
            expect(mockRedis.del).toHaveBeenCalledWith('roles:user-123');
        });
        it('should deduplicate roles', async () => {
            mockDb.query = vi.fn().mockResolvedValue({ rows: [], rowCount: 1 });
            mockRedis.setex = vi.fn().mockResolvedValue('OK');
            mockRedis.del = vi.fn().mockResolvedValue(1);
            await roleManager.assignRoles('user-123', ['admin', 'admin', 'developer']);
            // Verify db.query was called (at least 2 calls: one per unique role, plus invalidation calls)
            expect(mockDb.query.mock.calls.length).toBeGreaterThanOrEqual(2);
            // Verify redis.del was called to invalidate cache
            expect(mockRedis.del).toHaveBeenCalledWith('roles:user-123');
        });
    });
    describe('getUserRoles', () => {
        it('should retrieve user roles from cache', async () => {
            const roles = ['admin', 'developer'];
            mockRedis.get = vi.fn().mockResolvedValue(JSON.stringify({ roles, expiresAt: Date.now() + 10000 }));
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
            mockRedis.get = vi.fn().mockRejectedValue(new Error('Redis error'));
            const result = await roleManager.getUserRoles('user-123');
            expect(result).toEqual([]);
        });
    });
    describe('removeRole', () => {
        it('should remove a specific role from user', async () => {
            mockDb.query = vi.fn().mockResolvedValue({ rows: [], rowCount: 1 });
            mockRedis.del = vi.fn().mockResolvedValue(1);
            await roleManager.removeRole('user-123', 'admin');
            expect(mockDb.query).toHaveBeenCalled();
            expect(mockRedis.del).toHaveBeenCalledWith('roles:user-123');
        });
        it('should handle removing non-existent role', async () => {
            mockDb.query = vi.fn().mockResolvedValue({ rows: [], rowCount: 0 });
            mockRedis.del = vi.fn().mockResolvedValue(1);
            await roleManager.removeRole('user-123', 'admin');
            expect(mockDb.query).toHaveBeenCalled();
            expect(mockRedis.del).toHaveBeenCalledWith('roles:user-123');
        });
    });
    describe('clearRoles', () => {
        it('should clear all roles for a user', async () => {
            // Mock listRoles to return some assignments
            mockDb.query = vi
                .fn()
                .mockResolvedValueOnce({
                rows: [
                    { id: '1', service_id: 'user-123', role: 'admin', created_at: new Date(), expires_at: null },
                    { id: '2', service_id: 'user-123', role: 'developer', created_at: new Date(), expires_at: null },
                ],
            })
                .mockResolvedValue({ rows: [], rowCount: 1 }); // For DELETE calls
            mockRedis.del = vi.fn().mockResolvedValue(1);
            await roleManager.clearRoles('user-123');
            expect(mockDb.query).toHaveBeenCalled();
            expect(mockRedis.del).toHaveBeenCalledWith('roles:user-123');
        });
    });
    describe('listAllRoles', () => {
        it('should list all role assignments', async () => {
            // Mock database query to return service_ids
            mockDb.query = vi.fn().mockResolvedValue({
                rows: [
                    { service_id: 'user-1' },
                    { service_id: 'user-2' },
                ],
            });
            // Mock Redis cache for each user
            mockRedis.get = vi
                .fn()
                .mockResolvedValueOnce(JSON.stringify({ roles: ['admin'], expiresAt: Date.now() + 10000 }))
                .mockResolvedValueOnce(JSON.stringify({ roles: ['developer'], expiresAt: Date.now() + 10000 }));
            const result = await roleManager.listAllRoles();
            expect(result).toEqual({
                'user-1': ['admin'],
                'user-2': ['developer'],
            });
        });
        it('should handle empty role cache', async () => {
            // Mock database query to return empty list
            mockDb.query = vi.fn().mockResolvedValue({
                rows: [],
            });
            const result = await roleManager.listAllRoles();
            expect(result).toEqual({});
        });
    });
    describe('caching', () => {
        it('should cache role lookups', async () => {
            const roles = ['admin'];
            mockRedis.get = vi.fn().mockResolvedValue(JSON.stringify(roles));
            // First call
            await roleManager.getUserRoles('user-123');
            // Second call should use cache
            await roleManager.getUserRoles('user-123');
            expect(mockRedis.get).toHaveBeenCalledTimes(2);
        });
        it('should invalidate cache on role assignment', async () => {
            mockRedis.setex = vi.fn().mockResolvedValue('OK');
            mockRedis.del = vi.fn().mockResolvedValue(1);
            await roleManager.assignRoles('user-123', ['admin']);
            expect(mockRedis.del).toHaveBeenCalledWith('roles:user-123');
        });
    });
});
//# sourceMappingURL=role-manager.test.js.map