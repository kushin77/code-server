// @file        apps/backend/src/middleware/auth/__tests__/require-role.test.ts
// @module      auth/authorization
// @description Tests for requireRole middleware
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { requireRole, attachRoles } from '../require-role';
import { getRoleManager } from '../../../services/auth/role-manager';
import { getAuditService } from '../../../services/audit/audit-service';
vi.mock('../../../services/auth/role-manager');
vi.mock('../../../services/audit/audit-service');
describe('requireRole Middleware', () => {
    let mockReq;
    let mockRes;
    let mockNext;
    let mockRoleManager;
    beforeEach(() => {
        mockReq = {
            user: {
                sub: 'user-123',
                email: 'user@example.com',
            },
        };
        mockRes = {
            status: vi.fn().mockReturnThis(),
            json: vi.fn().mockReturnThis(),
        };
        mockNext = vi.fn();
        mockRoleManager = {
            getUserRoles: vi.fn(),
        };
        getRoleManager.mockReturnValue(mockRoleManager);
    });
    describe('with authorized user', () => {
        it('should allow user with required role', async () => {
            mockRoleManager.getUserRoles.mockResolvedValue(['admin', 'developer']);
            const middleware = requireRole('admin');
            await middleware(mockReq, mockRes, mockNext);
            expect(mockNext).toHaveBeenCalled();
            expect(mockRes.status).not.toHaveBeenCalled();
        });
        it('should allow user with any of multiple required roles', async () => {
            mockRoleManager.getUserRoles.mockResolvedValue(['developer']);
            const middleware = requireRole('admin', 'developer');
            await middleware(mockReq, mockRes, mockNext);
            expect(mockNext).toHaveBeenCalled();
        });
        it('should attach roles to request', async () => {
            const roles = ['admin', 'developer'];
            mockRoleManager.getUserRoles.mockResolvedValue(roles);
            const middleware = requireRole('admin');
            await middleware(mockReq, mockRes, mockNext);
            expect(mockReq.user?.roles).toEqual(roles);
        });
    });
    describe('with unauthorized user', () => {
        it('should reject user without required role', async () => {
            mockRoleManager.getUserRoles.mockResolvedValue(['user']);
            const middleware = requireRole('admin');
            await middleware(mockReq, mockRes, mockNext);
            expect(mockRes.status).toHaveBeenCalledWith(403);
            expect(mockRes.json).toHaveBeenCalledWith(expect.objectContaining({
                error: 'Forbidden',
            }));
            expect(mockNext).not.toHaveBeenCalled();
        });
        it('should reject user with no roles', async () => {
            mockRoleManager.getUserRoles.mockResolvedValue([]);
            const middleware = requireRole('admin');
            await middleware(mockReq, mockRes, mockNext);
            expect(mockRes.status).toHaveBeenCalledWith(403);
            expect(mockNext).not.toHaveBeenCalled();
        });
    });
    describe('with unauthenticated request', () => {
        it('should reject unauthenticated request', async () => {
            mockReq.user = undefined;
            const middleware = requireRole('admin');
            await middleware(mockReq, mockRes, mockNext);
            expect(mockRes.status).toHaveBeenCalledWith(401);
            expect(mockRes.json).toHaveBeenCalledWith(expect.objectContaining({
                error: 'Unauthorized',
            }));
            expect(mockNext).not.toHaveBeenCalled();
        });
    });
    describe('error handling', () => {
        it('should handle role lookup errors gracefully', async () => {
            mockRoleManager.getUserRoles.mockRejectedValue(new Error('Database error'));
            const middleware = requireRole('admin');
            await middleware(mockReq, mockRes, mockNext);
            expect(mockRes.status).toHaveBeenCalledWith(500);
            expect(mockRes.json).toHaveBeenCalledWith(expect.objectContaining({
                error: 'Internal Server Error',
            }));
        });
    });
});
describe('attachRoles Middleware', () => {
    let mockReq;
    let mockRes;
    let mockNext;
    let mockRoleManager;
    beforeEach(() => {
        mockReq = {
            user: {
                sub: 'user-123',
                email: 'user@example.com',
            },
        };
        mockRes = {};
        mockNext = vi.fn();
        mockRoleManager = {
            getUserRoles: vi.fn(),
        };
        getRoleManager.mockReturnValue(mockRoleManager);
    });
    it('should attach roles to authenticated request', async () => {
        const roles = ['developer'];
        mockRoleManager.getUserRoles.mockResolvedValue(roles);
        const middleware = attachRoles();
        await middleware(mockReq, mockRes, mockNext);
        expect(mockReq.user?.roles).toEqual(roles);
        expect(mockNext).toHaveBeenCalled();
    });
    it('should default to user role if no roles found', async () => {
        mockRoleManager.getUserRoles.mockResolvedValue(null);
        const middleware = attachRoles();
        await middleware(mockReq, mockRes, mockNext);
        expect(mockReq.user?.roles).toEqual(['user']);
        expect(mockNext).toHaveBeenCalled();
    });
    it('should pass through unauthenticated requests', async () => {
        mockReq.user = undefined;
        const middleware = attachRoles();
        await middleware(mockReq, mockRes, mockNext);
        expect(mockNext).toHaveBeenCalled();
    });
    it('should handle errors gracefully', async () => {
        mockRoleManager.getUserRoles.mockRejectedValue(new Error('Cache error'));
        const middleware = attachRoles();
        await middleware(mockReq, mockRes, mockNext);
        expect(mockNext).toHaveBeenCalled();
    });
});
describe('requireRole – audit event emission', () => {
    let mockReq;
    let mockRes;
    let mockNext;
    let mockRoleManager;
    let mockAuditService;
    beforeEach(() => {
        mockReq = {
            user: { sub: 'user-abc', email: 'user@example.com' },
            method: 'GET',
            path: '/api/data',
            ip: '127.0.0.1',
            headers: {},
        };
        mockRes = {
            status: vi.fn().mockReturnThis(),
            json: vi.fn().mockReturnThis(),
        };
        mockNext = vi.fn();
        mockRoleManager = { getUserRoles: vi.fn() };
        getRoleManager.mockReturnValue(mockRoleManager);
        mockAuditService = { emit: vi.fn() };
        getAuditService.mockReturnValue(mockAuditService);
    });
    it('emits an allow audit event when user is authorized', async () => {
        mockRoleManager.getUserRoles.mockResolvedValue(['admin']);
        await requireRole('admin')(mockReq, mockRes, mockNext);
        expect(mockAuditService.emit).toHaveBeenCalledOnce();
        const event = mockAuditService.emit.mock.calls[0][0];
        expect(event.action).toBe('allow');
        expect(event.userId).toBe('user-abc');
        expect(event.statusCode).toBe(200);
    });
    it('emits a deny audit event when user lacks required role', async () => {
        mockRoleManager.getUserRoles.mockResolvedValue(['viewer']);
        await requireRole('admin')(mockReq, mockRes, mockNext);
        expect(mockAuditService.emit).toHaveBeenCalledOnce();
        const event = mockAuditService.emit.mock.calls[0][0];
        expect(event.action).toBe('deny');
        expect(event.userId).toBe('user-abc');
        expect(event.statusCode).toBe(403);
    });
    it('emits a deny audit event for unauthenticated requests', async () => {
        mockReq.user = undefined;
        await requireRole('admin')(mockReq, mockRes, mockNext);
        expect(mockAuditService.emit).toHaveBeenCalledOnce();
        const event = mockAuditService.emit.mock.calls[0][0];
        expect(event.action).toBe('deny');
        expect(event.userId).toBe('anonymous');
        expect(event.statusCode).toBe(401);
    });
    it('skips audit emission when audit service is not initialised', async () => {
        getAuditService.mockReturnValue(null);
        mockRoleManager.getUserRoles.mockResolvedValue(['admin']);
        // Must not throw
        await expect(requireRole('admin')(mockReq, mockRes, mockNext)).resolves.not.toThrow();
        expect(mockNext).toHaveBeenCalled();
    });
});
//# sourceMappingURL=require-role.test.js.map