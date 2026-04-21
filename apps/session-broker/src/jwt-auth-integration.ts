#!/usr/bin/env ts-node
// @file        apps/session-broker/src/jwt-auth-integration.ts
// @module      session-broker/jwt-auth
// @description Adapter for integrating JWT authentication into session-broker
//              Supports both oauth2-proxy headers and OIDC JWT tokens
//

import { Request, Response, NextFunction } from 'express';
import { JwtValidator, JwtTokenClient, jwtAuth } from '../../backend/src/services/auth/index.js';

/**
 * Extended BrokerRequest with JWT support
 * Maintains backward compatibility with oauth2-proxy headers while adding JWT validation
 */
export interface JwtEnabledBrokerRequest extends Request {
  authUser?: SessionBrokerPrincipal;
  correlationId?: string;
  jwt?: {
    claims: {
      sub: string;
      aud: string;
      iss: string;
      iat: number;
      exp: number;
      groups?: string[];
      actor?: string;
    };
    token: string;
  };
}

/**
 * Session broker principal (existing type from session-broker)
 */
export interface SessionBrokerPrincipal {
  userId: string;
  username: string;
  email: string;
  groups?: string[];
  roles?: string[];
}

/**
 * JWT auth integration for session-broker
 * 
 * This adapter allows session-broker to accept JWT tokens from the OIDC issuer
 * while maintaining backward compatibility with oauth2-proxy authentication.
 * 
 * Priority order:
 * 1. JWT token in Authorization header (OIDC issuer token)
 * 2. oauth2-proxy headers (X-Auth-Request-*)
 * 3. Session cookie (existing behavior)
 */
export class SessionBrokerJwtAuth {
  private validator: JwtValidator;
  private tokenClient: JwtTokenClient;
  private audience: string;
  private fallbackToProxy: boolean;

  constructor(config: {
    oidcIssuerUrl: string;
    audience: string;
    clientId: string;
    clientSecret: string;
    fallbackToProxy?: boolean; // Default: true for backward compatibility
  }) {
    this.validator = new JwtValidator({
      oidcIssuerUrl: config.oidcIssuerUrl,
      jwksCacheTtlSeconds: 3600,
    });

    this.tokenClient = new JwtTokenClient({
      oidcIssuerUrl: config.oidcIssuerUrl,
      clientId: config.clientId,
      clientSecret: config.clientSecret,
    });

    this.audience = config.audience;
    this.fallbackToProxy = config.fallbackToProxy !== false;
  }

  /**
   * Middleware: Validate incoming JWT or fallback to oauth2-proxy headers
   */
  middleware() {
    return async (req: Request, res: Response, next: NextFunction) => {
      const brokerReq = req as JwtEnabledBrokerRequest;

      // Skip auth for public endpoints
      if (this.isPublicPath(req.path)) {
        return next();
      }

      try {
        // Try JWT first
        const authHeader = req.headers.authorization;
        if (authHeader?.startsWith('Bearer ')) {
          const token = authHeader.slice(7);
          const claims = await this.validator.validateToken(token, this.audience);

          // Set JWT claims on request
          brokerReq.jwt = { claims, token };

          // Convert JWT claims to SessionBrokerPrincipal
          brokerReq.authUser = this.claimsToSessionPrincipal(claims);

          return next();
        }

        // Fallback to oauth2-proxy headers if enabled
        if (this.fallbackToProxy) {
          const proxyAuth = this.extractProxyAuth(req);
          if (proxyAuth) {
            brokerReq.authUser = proxyAuth;
            return next();
          }
        }

        // No auth found
        return res.status(401).json({ error: 'Authentication required' });
      } catch (error) {
        return res.status(401).json({
          error: 'Authentication failed',
          reason: String(error),
        });
      }
    };
  }

  /**
   * Get a token for calling another service
   * 
   * Example: const token = await auth.getToken('https://code-server/api');
   */
  async getToken(audience: string): Promise<string> {
    return this.tokenClient.getToken(audience);
  }

  /**
   * Extract auth principal from oauth2-proxy headers
   * (backward compatibility with existing oauth2-proxy setup)
   */
  private extractProxyAuth(req: Request): SessionBrokerPrincipal | null {
    const email = req.headers['x-auth-request-email'] as string;
    const user = req.headers['x-auth-request-user'] as string;
    const preferredUsername = (req.headers['x-auth-request-preferred-username'] as string) || user;
    const rawGroups = req.headers['x-auth-request-groups'];

    if (!email || !user) {
      return null;
    }

    const groups = Array.isArray(rawGroups)
      ? rawGroups
      : rawGroups
      ? [rawGroups]
      : [];

    return {
      userId: user || email.split('@')[0],
      username: preferredUsername || email.split('@')[0],
      email,
      groups,
    };
  }

  /**
   * Convert JWT claims to SessionBrokerPrincipal
   */
  private claimsToSessionPrincipal(claims: any): SessionBrokerPrincipal {
    return {
      userId: claims.sub, // Subject is the service name
      username: claims.sub,
      email: claims.email || `${claims.sub}@internal`,
      groups: claims.groups || [],
    };
  }

  /**
   * Check if path is public (doesn't require auth)
   */
  private isPublicPath(path: string): boolean {
    const publicPaths = ['/health', '/metrics', '/ping', '/healthz'];
    const publicPrefixes = ['/oauth2'];

    return (
      publicPaths.includes(path) ||
      publicPrefixes.some(prefix => path.startsWith(prefix))
    );
  }
}

/**
 * Factory function for easy integration
 * 
 * Usage in session-broker:
 * 
 * const jwtAuth = createSessionBrokerJwtAuth({
 *   oidcIssuerUrl: process.env.OIDC_ISSUER_URL || 'http://oauth2-oidc-issuer:4182',
 *   audience: 'https://session-broker/api',
 *   clientId: process.env.SERVICE_CLIENT_ID || 'session-broker',
 *   clientSecret: process.env.SERVICE_CLIENT_SECRET || '',
 * });
 * 
 * app.use(jwtAuth.middleware());
 */
export function createSessionBrokerJwtAuth(config: {
  oidcIssuerUrl: string;
  audience: string;
  clientId: string;
  clientSecret: string;
  fallbackToProxy?: boolean;
}): SessionBrokerJwtAuth {
  return new SessionBrokerJwtAuth(config);
}

/**
 * Helper: Get authenticated user from request
 * Works with both JWT and oauth2-proxy auth
 */
export function getAuthUser(req: Request): SessionBrokerPrincipal | null {
  const brokerReq = req as JwtEnabledBrokerRequest;
  return brokerReq.authUser || null;
}

/**
 * Helper: Require authentication
 * Returns authUser or sends 401 response
 */
export function requireAuth(req: Request, res: Response): SessionBrokerPrincipal | null {
  const authUser = getAuthUser(req);
  if (!authUser) {
    res.status(401).json({ error: 'Authentication required' });
    return null;
  }
  return authUser;
}

/**
 * Helper: Check if user is in a specific group
 */
export function isInGroup(authUser: SessionBrokerPrincipal, group: string): boolean {
  return authUser.groups?.includes(group) || false;
}

/**
 * Helper: Require specific group membership
 */
export function requireGroup(group: string) {
  return (req: Request, res: Response, next: NextFunction) => {
    const authUser = getAuthUser(req);
    if (!authUser || !isInGroup(authUser, group)) {
      return res.status(403).json({ error: `Group '${group}' required` });
    }
    next();
  };
}
