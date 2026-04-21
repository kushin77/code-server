// @file        apps/backend/src/middleware/auth/require-role.ts
// @module      auth/authorization
// @description Authorization middleware decorator for role-based access control

import { Request, Response, NextFunction } from 'express';
import { getLogger } from '../../lib/logger';
import { getRoleManager } from '../../services/auth/role-manager';
import { getAuditService } from '../../services/audit/audit-service';

const logger = getLogger('RequireRole');

interface AuthenticatedRequest extends Request {
  user?: {
    sub: string;
    email: string;
    roles?: string[];
  };
}

/**
 * Middleware factory for role-based authorization
 * 
 * Usage:
 *   app.get('/admin', requireRole('admin'), handler);
 *   app.post('/api/data', requireRole('developer', 'admin'), handler);
 */
export function requireRole(...allowedRoles: string[]) {
  return async (
    req: AuthenticatedRequest,
    res: Response,
    next: NextFunction
  ) => {
    try {
      const audit = getAuditService();
      const traceId =
        (req.headers?.['x-trace-id'] as string | undefined) ||
        (req.headers?.['x-request-id'] as string | undefined) ||
        undefined;
      const sessionId = (req.headers?.['x-session-id'] as string | undefined) || undefined;
      const ipAddress = req.ip ?? undefined;

      // Check if user is authenticated
      if (!req.user) {
        logger.warn('Unauthenticated request to protected route');
        audit?.emit({
          userId: 'anonymous',
          method: req.method,
          path: req.path,
          role: allowedRoles.join(','),
          action: 'deny',
          reason: 'unauthenticated',
          statusCode: 401,
          ipAddress,
          traceId,
          sessionId,
        });
        return res.status(401).json({
          error: 'Unauthorized',
          message: 'Authentication required',
        });
      }

      const roleManager = getRoleManager();
      const userRoles = await roleManager.getUserRoles(req.user.sub);

      if (!userRoles || userRoles.length === 0) {
        logger.warn(
          `User ${req.user.email} has no assigned roles`,
          { userId: req.user.sub }
        );
        audit?.emit({
          userId: req.user.sub,
          userEmail: req.user.email,
          method: req.method,
          path: req.path,
          role: allowedRoles.join(','),
          action: 'deny',
          reason: 'no_roles_assigned',
          statusCode: 403,
          ipAddress,
          traceId,
          sessionId,
        });
        return res.status(403).json({
          error: 'Forbidden',
          message: 'No roles assigned to user',
        });
      }

      // Check if user has any of the allowed roles
      const hasRequiredRole = allowedRoles.some((role) =>
        userRoles.includes(role)
      );

      if (!hasRequiredRole) {
        logger.warn(
          `User ${req.user.email} unauthorized for roles ${allowedRoles.join(', ')}`,
          {
            userId: req.user.sub,
            userRoles,
            requiredRoles: allowedRoles,
          }
        );
        audit?.emit({
          userId: req.user.sub,
          userEmail: req.user.email,
          method: req.method,
          path: req.path,
          role: userRoles.join(','),
          action: 'deny',
          reason: `requires_one_of:${allowedRoles.join(',')}`,
          statusCode: 403,
          ipAddress,
          traceId,
          sessionId,
        });
        return res.status(403).json({
          error: 'Forbidden',
          message: `Requires one of: ${allowedRoles.join(', ')}`,
          userRoles,
        });
      }

      // Attach roles to request for downstream handlers
      req.user.roles = userRoles;

      logger.debug(
        `User ${req.user.email} authorized with roles: ${userRoles.join(', ')}`,
        { userId: req.user.sub }
      );

      audit?.emit({
        userId: req.user.sub,
        userEmail: req.user.email,
        method: req.method,
        path: req.path,
        role: userRoles.join(','),
        action: 'allow',
        statusCode: 200,
        ipAddress,
        traceId,
        sessionId,
      });

      next();
    } catch (error) {
      logger.error('Role authorization check failed', {
        error: error instanceof Error ? error.message : String(error),
        userId: req.user?.sub,
      });
      return res.status(500).json({
        error: 'Internal Server Error',
        message: 'Authorization check failed',
      });
    }
  };
}

/**
 * Decorator version for class-based handlers
 * 
 * Usage:
 *   class AdminController {
 *     @RequireRoleDecorator('admin')
 *     async deleteUser(req, res) { ... }
 *   }
 */
export function RequireRoleDecorator(...roles: string[]) {
  return function (
    target: any,
    propertyKey: string,
    descriptor: PropertyDescriptor
  ) {
    const originalMethod = descriptor.value;

    descriptor.value = async function (
      req: AuthenticatedRequest,
      res: Response,
      next: NextFunction
    ) {
      try {
        if (!req.user) {
          return res.status(401).json({
            error: 'Unauthorized',
            message: 'Authentication required',
          });
        }

        const roleManager = getRoleManager();
        const userRoles = await roleManager.getUserRoles(req.user.sub);

        const hasRequiredRole = roles.some((role) => userRoles.includes(role));

        if (!hasRequiredRole) {
          logger.warn(
            `User ${req.user.email} unauthorized for decorator roles ${roles.join(', ')}`
          );
          return res.status(403).json({
            error: 'Forbidden',
            message: `Requires one of: ${roles.join(', ')}`,
          });
        }

        req.user.roles = userRoles;
        return originalMethod.apply(this, [req, res, next]);
      } catch (error) {
        logger.error('Decorator role check failed', {
          error: error instanceof Error ? error.message : String(error),
        });
        return res.status(500).json({
          error: 'Internal Server Error',
          message: 'Authorization check failed',
        });
      }
    };

    return descriptor;
  };
}

/**
 * Optional role check - allows request through but attaches available roles
 * Useful for handlers that adapt behavior based on user roles
 */
export function attachRoles() {
  return async (
    req: AuthenticatedRequest,
    res: Response,
    next: NextFunction
  ) => {
    try {
      if (req.user) {
        const roleManager = getRoleManager();
        const userRoles = await roleManager.getUserRoles(req.user.sub);
        req.user.roles = userRoles || ['user'];
        logger.debug(`Attached roles to user ${req.user.email}`);
      }
      next();
    } catch (error) {
      logger.error('Failed to attach roles', {
        error: error instanceof Error ? error.message : String(error),
      });
      next();
    }
  };
}
