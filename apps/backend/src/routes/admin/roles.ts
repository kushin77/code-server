// @file        apps/backend/src/routes/admin/roles.ts
// @module      admin/role-management
// @description REST API for role assignment and management

import { Router, Request, Response } from 'express';
import { Logger } from '../../utils/logger';
import { getRoleManager } from '../../services/auth/role-manager';
import { requireRole, attachRoles } from '../../middleware/auth/require-role';

const router = Router();
const logger = new Logger('RoleManagementAPI');

interface AuthenticatedRequest extends Request {
  user?: {
    sub: string;
    email: string;
    roles?: string[];
  };
}

// All role management endpoints require admin role
router.use(attachRoles());

/**
 * GET /api/admin/roles/:userId
 * Get roles assigned to a user
 */
router.get(
  '/:userId',
  requireRole('admin'),
  async (req: AuthenticatedRequest, res: Response) => {
    try {
      const roleManager = getRoleManager();
      const roles = await roleManager.getUserRoles(req.params.userId);

      logger.info(`Retrieved roles for user ${req.params.userId}`, {
        admin: req.user?.email,
        roles,
      });

      res.json({
        userId: req.params.userId,
        roles: roles || [],
      });
    } catch (error) {
      logger.error('Failed to get user roles', {
        userId: req.params.userId,
        error: error instanceof Error ? error.message : String(error),
      });
      res.status(500).json({
        error: 'Failed to retrieve roles',
        message: error instanceof Error ? error.message : 'Unknown error',
      });
    }
  }
);

/**
 * POST /api/admin/roles/:userId/assign
 * Assign role(s) to a user
 * 
 * Body: { roles: ['role1', 'role2'], expiresIn?: number }
 */
router.post(
  '/:userId/assign',
  requireRole('admin'),
  async (req: AuthenticatedRequest, res: Response) => {
    try {
      const { roles, expiresIn } = req.body;

      if (!roles || !Array.isArray(roles) || roles.length === 0) {
        return res.status(400).json({
          error: 'Bad Request',
          message: 'roles array is required and must not be empty',
        });
      }

      const roleManager = getRoleManager();
      await roleManager.assignRoles(
        req.params.userId,
        roles,
        expiresIn
      );

      logger.info(
        `Assigned roles ${roles.join(', ')} to user ${req.params.userId}`,
        {
          admin: req.user?.email,
          userId: req.params.userId,
          roles,
          expiresIn,
        }
      );

      res.json({
        success: true,
        userId: req.params.userId,
        roles,
        message: `Successfully assigned ${roles.length} role(s)`,
      });
    } catch (error) {
      logger.error('Failed to assign roles', {
        userId: req.params.userId,
        error: error instanceof Error ? error.message : String(error),
        admin: req.user?.email,
      });
      res.status(500).json({
        error: 'Failed to assign roles',
        message: error instanceof Error ? error.message : 'Unknown error',
      });
    }
  }
);

/**
 * DELETE /api/admin/roles/:userId/:roleName
 * Remove a specific role from a user
 */
router.delete(
  '/:userId/:roleName',
  requireRole('admin'),
  async (req: AuthenticatedRequest, res: Response) => {
    try {
      const roleManager = getRoleManager();
      await roleManager.removeRole(req.params.userId, req.params.roleName);

      logger.info(
        `Removed role ${req.params.roleName} from user ${req.params.userId}`,
        {
          admin: req.user?.email,
          userId: req.params.userId,
          role: req.params.roleName,
        }
      );

      res.json({
        success: true,
        userId: req.params.userId,
        removedRole: req.params.roleName,
        message: 'Role successfully removed',
      });
    } catch (error) {
      logger.error('Failed to remove role', {
        userId: req.params.userId,
        role: req.params.roleName,
        error: error instanceof Error ? error.message : String(error),
      });
      res.status(500).json({
        error: 'Failed to remove role',
        message: error instanceof Error ? error.message : 'Unknown error',
      });
    }
  }
);

/**
 * POST /api/admin/roles/:userId/clear
 * Remove all roles from a user (reverts to 'user' role only)
 */
router.post(
  '/:userId/clear',
  requireRole('admin'),
  async (req: AuthenticatedRequest, res: Response) => {
    try {
      const roleManager = getRoleManager();
      await roleManager.clearRoles(req.params.userId);

      logger.warn(
        `Cleared all roles for user ${req.params.userId}`,
        {
          admin: req.user?.email,
          userId: req.params.userId,
        }
      );

      res.json({
        success: true,
        userId: req.params.userId,
        roles: ['user'], // Everyone has at least 'user' role
        message: 'All roles cleared (user role remains)',
      });
    } catch (error) {
      logger.error('Failed to clear roles', {
        userId: req.params.userId,
        error: error instanceof Error ? error.message : String(error),
      });
      res.status(500).json({
        error: 'Failed to clear roles',
        message: error instanceof Error ? error.message : 'Unknown error',
      });
    }
  }
);

/**
 * GET /api/admin/roles/list/all
 * List all role assignments (admin only)
 */
router.get(
  '/list/all',
  requireRole('admin'),
  async (req: AuthenticatedRequest, res: Response) => {
    try {
      const roleManager = getRoleManager();
      const allRoles = await roleManager.listAllRoles();

      logger.info('Retrieved all role assignments', {
        admin: req.user?.email,
        count: Object.keys(allRoles).length,
      });

      res.json({
        total: Object.keys(allRoles).length,
        roles: allRoles,
      });
    } catch (error) {
      logger.error('Failed to list all roles', {
        error: error instanceof Error ? error.message : String(error),
      });
      res.status(500).json({
        error: 'Failed to list roles',
        message: error instanceof Error ? error.message : 'Unknown error',
      });
    }
  }
);

/**
 * POST /api/admin/roles/audit/export
 * Export role audit trail (admin only)
 */
router.post(
  '/audit/export',
  requireRole('admin'),
  async (req: AuthenticatedRequest, res: Response) => {
    try {
      const roleManager = getRoleManager();
      const auditLog = await roleManager.getAuditLog();

      res.json({
        exportedAt: new Date().toISOString(),
        exportedBy: req.user?.email,
        auditLogSize: auditLog.length,
        auditLog,
      });

      logger.info('Exported role audit log', {
        admin: req.user?.email,
        entries: auditLog.length,
      });
    } catch (error) {
      logger.error('Failed to export audit log', {
        error: error instanceof Error ? error.message : String(error),
      });
      res.status(500).json({
        error: 'Failed to export audit log',
        message: error instanceof Error ? error.message : 'Unknown error',
      });
    }
  }
);

export default router;
