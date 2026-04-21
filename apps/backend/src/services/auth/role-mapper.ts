// @file        apps/backend/src/services/auth/role-mapper.ts
// @module      auth/role-mapping
// @description Maps Google OAuth groups and claims to application roles

import { getLogger } from '../../lib/logger';

interface TokenClaims {
  sub: string;
  email: string;
  groups?: string[];
  roles?: string[];
  admin?: boolean;
}

const logger = getLogger('RoleMapper');

/**
 * RoleMapper maps external identity provider claims (Google Groups, SAML groups)
 * to application roles
 *
 * Mapping rules:
 * - 'google.com/admin@company.com' → 'admin' role
 * - 'google.com/developers@company.com' → 'developer' role
 * - Service accounts with 'service-admin' in email → 'service-admin' role
 * - Everyone else → 'user' role
 */
export class RoleMapper {
  private groupToRoleMap: Map<string, string[]>;

  constructor() {
    this.groupToRoleMap = new Map([
      ['admin@company.com', ['admin']],
      ['developers@company.com', ['developer']],
      ['support@company.com', ['support']],
    ]);
  }

  /**
   * Map OAuth token claims to application roles
   */
  mapClaimsToRoles(claims: TokenClaims): string[] {
    const roles: Set<string> = new Set(['user']); // Everyone gets 'user' role

    // Check explicit admin flag
    if (claims.admin === true) {
      roles.add('admin');
    }

    // Check Google groups
    if (claims.groups && Array.isArray(claims.groups)) {
      for (const group of claims.groups) {
        const mappedRoles = this.groupToRoleMap.get(group);
        if (mappedRoles) {
          mappedRoles.forEach((role) => roles.add(role));
        }
      }
    }

    // Service account detection
    if (claims.email && claims.email.includes('svc.internal')) {
      if (claims.email.includes('service-admin')) {
        roles.add('service-admin');
      } else if (claims.email.includes('backend')) {
        roles.add('backend-service');
      } else if (claims.email.includes('session')) {
        roles.add('session-service');
      }
    }

    logger.debug(
      `Mapped claims for ${claims.email} to roles: ${Array.from(roles).join(', ')}`
    );

    return Array.from(roles);
  }

  /**
   * Register custom group-to-role mapping
   */
  registerGroupMapping(group: string, roles: string[]): void {
    this.groupToRoleMap.set(group, roles);
    logger.info(`Registered group mapping: ${group} → ${roles.join(', ')}`);
  }

  /**
   * Get all registered group mappings
   */
  getGroupMappings(): Record<string, string[]> {
    const result: Record<string, string[]> = {};
    this.groupToRoleMap.forEach((roles, group) => {
      result[group] = roles;
    });
    return result;
  }
}

/**
 * Singleton instance
 */
let mapperInstance: RoleMapper | null = null;

export function initializeRoleMapper(): RoleMapper {
  mapperInstance = new RoleMapper();
  return mapperInstance;
}

export function getRoleMapper(): RoleMapper {
  if (!mapperInstance) {
    mapperInstance = new RoleMapper();
  }
  return mapperInstance;
}
