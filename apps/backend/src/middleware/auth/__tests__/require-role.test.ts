// @file        apps/backend/src/middleware/auth/__tests__/require-role.test.ts
// @module      auth/authorization
// @description Tests for requireRole middleware

import { Request, Response, NextFunction } from 'express';
import { requireRole, attachRoles } from '../require-role';
import { getRoleManager } from '../../../services/auth/role-manager';

jest.mock('../../../services/auth/role-manager');

interface TestRequest extends Request {
  user?: {
    sub: string;
    email: string;
    roles?: string[];
  };
}

describe('requireRole Middleware', () => {
  let mockReq: Partial<TestRequest>;
  let mockRes: Partial<Response>;
  let mockNext: jest.Mock<void>;
  let mockRoleManager: any;

  beforeEach(() => {
    mockReq = {
      user: {
        sub: 'user-123',
        email: 'user@example.com',
      },
    };

    mockRes = {
      status: jest.fn().mockReturnThis(),
      json: jest.fn().mockReturnThis(),
    };

    mockNext = jest.fn();

    mockRoleManager = {
      getUserRoles: jest.fn(),
    };

    (getRoleManager as jest.Mock).mockReturnValue(mockRoleManager);
  });

  describe('with authorized user', () => {
    it('should allow user with required role', async () => {
      mockRoleManager.getUserRoles.mockResolvedValue(['admin', 'developer']);

      const middleware = requireRole('admin');
      await middleware(
        mockReq as TestRequest,
        mockRes as Response,
        mockNext
      );

      expect(mockNext).toHaveBeenCalled();
      expect(mockRes.status).not.toHaveBeenCalled();
    });

    it('should allow user with any of multiple required roles', async () => {
      mockRoleManager.getUserRoles.mockResolvedValue(['developer']);

      const middleware = requireRole('admin', 'developer');
      await middleware(
        mockReq as TestRequest,
        mockRes as Response,
        mockNext
      );

      expect(mockNext).toHaveBeenCalled();
    });

    it('should attach roles to request', async () => {
      const roles = ['admin', 'developer'];
      mockRoleManager.getUserRoles.mockResolvedValue(roles);

      const middleware = requireRole('admin');
      await middleware(
        mockReq as TestRequest,
        mockRes as Response,
        mockNext
      );

      expect((mockReq as TestRequest).user?.roles).toEqual(roles);
    });
  });

  describe('with unauthorized user', () => {
    it('should reject user without required role', async () => {
      mockRoleManager.getUserRoles.mockResolvedValue(['user']);

      const middleware = requireRole('admin');
      await middleware(
        mockReq as TestRequest,
        mockRes as Response,
        mockNext
      );

      expect(mockRes.status).toHaveBeenCalledWith(403);
      expect(mockRes.json).toHaveBeenCalledWith(
        expect.objectContaining({
          error: 'Forbidden',
        })
      );
      expect(mockNext).not.toHaveBeenCalled();
    });

    it('should reject user with no roles', async () => {
      mockRoleManager.getUserRoles.mockResolvedValue([]);

      const middleware = requireRole('admin');
      await middleware(
        mockReq as TestRequest,
        mockRes as Response,
        mockNext
      );

      expect(mockRes.status).toHaveBeenCalledWith(403);
      expect(mockNext).not.toHaveBeenCalled();
    });
  });

  describe('with unauthenticated request', () => {
    it('should reject unauthenticated request', async () => {
      mockReq.user = undefined;

      const middleware = requireRole('admin');
      await middleware(
        mockReq as TestRequest,
        mockRes as Response,
        mockNext
      );

      expect(mockRes.status).toHaveBeenCalledWith(401);
      expect(mockRes.json).toHaveBeenCalledWith(
        expect.objectContaining({
          error: 'Unauthorized',
        })
      );
      expect(mockNext).not.toHaveBeenCalled();
    });
  });

  describe('error handling', () => {
    it('should handle role lookup errors gracefully', async () => {
      mockRoleManager.getUserRoles.mockRejectedValue(
        new Error('Database error')
      );

      const middleware = requireRole('admin');
      await middleware(
        mockReq as TestRequest,
        mockRes as Response,
        mockNext
      );

      expect(mockRes.status).toHaveBeenCalledWith(500);
      expect(mockRes.json).toHaveBeenCalledWith(
        expect.objectContaining({
          error: 'Internal Server Error',
        })
      );
    });
  });
});

describe('attachRoles Middleware', () => {
  let mockReq: Partial<TestRequest>;
  let mockRes: Partial<Response>;
  let mockNext: jest.Mock<void>;
  let mockRoleManager: any;

  beforeEach(() => {
    mockReq = {
      user: {
        sub: 'user-123',
        email: 'user@example.com',
      },
    };

    mockRes = {};
    mockNext = jest.fn();

    mockRoleManager = {
      getUserRoles: jest.fn(),
    };

    (getRoleManager as jest.Mock).mockReturnValue(mockRoleManager);
  });

  it('should attach roles to authenticated request', async () => {
    const roles = ['developer'];
    mockRoleManager.getUserRoles.mockResolvedValue(roles);

    const middleware = attachRoles();
    await middleware(
      mockReq as TestRequest,
      mockRes as Response,
      mockNext
    );

    expect((mockReq as TestRequest).user?.roles).toEqual(roles);
    expect(mockNext).toHaveBeenCalled();
  });

  it('should default to user role if no roles found', async () => {
    mockRoleManager.getUserRoles.mockResolvedValue(null);

    const middleware = attachRoles();
    await middleware(
      mockReq as TestRequest,
      mockRes as Response,
      mockNext
    );

    expect((mockReq as TestRequest).user?.roles).toEqual(['user']);
    expect(mockNext).toHaveBeenCalled();
  });

  it('should pass through unauthenticated requests', async () => {
    mockReq.user = undefined;

    const middleware = attachRoles();
    await middleware(
      mockReq as TestRequest,
      mockRes as Response,
      mockNext
    );

    expect(mockNext).toHaveBeenCalled();
  });

  it('should handle errors gracefully', async () => {
    mockRoleManager.getUserRoles.mockRejectedValue(
      new Error('Cache error')
    );

    const middleware = attachRoles();
    await middleware(
      mockReq as TestRequest,
      mockRes as Response,
      mockNext
    );

    expect(mockNext).toHaveBeenCalled();
  });
});
