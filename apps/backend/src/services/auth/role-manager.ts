// @file        apps/backend/src/services/auth/role-manager.ts
// @module      auth/role-management
// @description Service for managing role assignments and role lookups with caching

import { getLogger } from '../../lib/logger';
import { Redis } from 'redis';
import { Database } from '../../db';

interface RoleAssignment {
  id: string;
  serviceId: string;
  role: string;
  createdAt: Date;
  expiresAt?: Date;
}

interface RoleCache {
  roles: string[];
  expiresAt: number;
}

const logger = getLogger('RoleManager');
const ROLE_CACHE_TTL_MINUTES = 60; // Cache roles for 1 hour
const CACHE_KEY_PREFIX = 'roles:';

/**
 * RoleManager handles role assignment persistence and caching
 * Supports:
 * - Service account role assignment
 * - Role inheritance (admin includes user permissions)
 * - Role caching with TTL
 * - Role expiration (optional)
 */
export class RoleManager {
  private redis: Redis;
  private db: Database;

  constructor(redis: Redis, db: Database) {
    this.redis = redis;
    this.db = db;
  }

  /**
   * Get all roles for a given service/user ID
   * Uses cache first, falls back to database
   */
  async getRoles(serviceId: string): Promise<string[]> {
    const cacheKey = `${CACHE_KEY_PREFIX}${serviceId}`;

    try {
      // Try cache first
      const cached = await this.redis.get(cacheKey);
      if (cached) {
        const parsed = JSON.parse(cached) as RoleCache;
        if (parsed.expiresAt > Date.now()) {
          logger.debug(`Role cache hit for ${serviceId}`);
          return parsed.roles;
        }
        // Cache expired, delete it
        await this.redis.del(cacheKey);
      }
    } catch (error) {
      logger.warn(`Role cache lookup failed for ${serviceId}: ${error}`);
    }

    // Query database
    const roles = await this.getRolesFromDatabase(serviceId);

    // Cache the result
    try {
      const cacheValue: RoleCache = {
        roles,
        expiresAt: Date.now() + ROLE_CACHE_TTL_MINUTES * 60 * 1000,
      };
      await this.redis.setEx(
        cacheKey,
        ROLE_CACHE_TTL_MINUTES * 60,
        JSON.stringify(cacheValue)
      );
    } catch (error) {
      logger.warn(`Failed to cache roles for ${serviceId}: ${error}`);
    }

    return roles;
  }

  /**
   * Check if a service has a specific role
   * Supports role inheritance: 'admin' includes all other roles
   */
  async hasRole(serviceId: string, requiredRole: string): Promise<boolean> {
    const roles = await this.getRoles(serviceId);

    // Admin role inherits all other roles
    if (roles.includes('admin')) {
      return true;
    }

    // Check for exact role match
    return roles.includes(requiredRole);
  }

  /**
   * Assign a role to a service account
   */
  async assignRole(
    serviceId: string,
    role: string,
    expiresIn?: number
  ): Promise<RoleAssignment> {
    // Validate role format
    if (!/^[a-z0-9-]+$/.test(role)) {
      throw new Error(`Invalid role format: ${role}`);
    }

    const assignment: RoleAssignment = {
      id: `${serviceId}:${role}:${Date.now()}`,
      serviceId,
      role,
      createdAt: new Date(),
      expiresAt: expiresIn ? new Date(Date.now() + expiresIn) : undefined,
    };

    // Persist to database
    await this.db.query(
      `INSERT INTO role_assignments (service_id, role, expires_at, created_at)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (service_id, role) DO UPDATE SET expires_at = $3`,
      [serviceId, role, assignment.expiresAt, assignment.createdAt]
    );

    // Invalidate cache
    await this.invalidateRoleCache(serviceId);

    logger.info(`Assigned role '${role}' to service '${serviceId}'`);
    return assignment;
  }

  /**
   * Remove a role from a service account
   */
  async revokeRole(serviceId: string, role: string): Promise<void> {
    await this.db.query(
      `DELETE FROM role_assignments
       WHERE service_id = $1 AND role = $2`,
      [serviceId, role]
    );

    // Invalidate cache
    await this.invalidateRoleCache(serviceId);

    logger.info(`Revoked role '${role}' from service '${serviceId}'`);
  }

  /**
   * List all roles for a service account
   */
  async listRoles(serviceId: string): Promise<RoleAssignment[]> {
    const result = await this.db.query(
      `SELECT id, service_id, role, created_at, expires_at
       FROM role_assignments
       WHERE service_id = $1
       ORDER BY created_at DESC`,
      [serviceId]
    );

    return result.rows;
  }

  /**
   * Get all services with a specific role
   */
  async getServicesWithRole(role: string): Promise<string[]> {
    const result = await this.db.query(
      `SELECT DISTINCT service_id
       FROM role_assignments
       WHERE role = $1
       AND (expires_at IS NULL OR expires_at > NOW())`,
      [role]
    );

    return result.rows.map((row) => row.service_id);
  }

  /**
   * Cleanup expired role assignments
   */
  async cleanupExpiredRoles(): Promise<number> {
    const result = await this.db.query(
      `DELETE FROM role_assignments
       WHERE expires_at IS NOT NULL AND expires_at < NOW()`
    );

    logger.info(`Cleaned up ${result.rowCount} expired role assignments`);
    return result.rowCount;
  }

  /**
   * Private: Get roles from database
   */
  private async getRolesFromDatabase(serviceId: string): Promise<string[]> {
    const result = await this.db.query(
      `SELECT role FROM role_assignments
       WHERE service_id = $1
       AND (expires_at IS NULL OR expires_at > NOW())
       ORDER BY role`,
      [serviceId]
    );

    return result.rows.map((row) => row.role);
  }

  /**
   * Private: Invalidate role cache for a service
   */
  private async invalidateRoleCache(serviceId: string): Promise<void> {
    try {
      await this.redis.del(`${CACHE_KEY_PREFIX}${serviceId}`);
    } catch (error) {
      logger.warn(`Failed to invalidate role cache for ${serviceId}: ${error}`);
    }
  }
}

/**
 * Singleton instance
 */
let roleManagerInstance: RoleManager | null = null;

export function initializeRoleManager(redis: Redis, db: Database): RoleManager {
  roleManagerInstance = new RoleManager(redis, db);
  return roleManagerInstance;
}

export function getRoleManager(): RoleManager {
  if (!roleManagerInstance) {
    throw new Error('RoleManager not initialized. Call initializeRoleManager first.');
  }
  return roleManagerInstance;
}
