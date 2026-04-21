#!/usr/bin/env node
// @file        apps/backend/src/middleware/jwt-auth.ts
// @module      middleware
// @description JWT token validation middleware for service-to-service requests
// @owner       Infrastructure Team
// @status      ACTIVE

import { Request, Response, NextFunction } from 'express';
import { JwtValidator, JwtClaims } from '../services/auth/jwt-validator';

/**
 * Extended Express Request with JWT claims
 */
declare global {
  namespace Express {
    interface Request {
      jwt?: {
        claims: JwtClaims;
        token: string;
      };
    }
  }
}

/**
 * Middleware options for JWT validation
 */
interface JwtAuthOptions {
  audience: string;
  issuer?: string;
  optional?: boolean;
  validator?: JwtValidator;
  excludeRoutes?: RegExp[];
}

/**
 * Create JWT authentication middleware for Express
 * 
 * Validates JWT tokens in Authorization header (Bearer scheme)
 * and attaches claims to request object.
 * 
 * @param options - Middleware configuration
 * @returns Express middleware function
 */
export function jwtAuth(options: JwtAuthOptions) {
  const validator =
    options.validator || new JwtValidator(process.env.OIDC_ISSUER_URL);
  const excludeRoutes = options.excludeRoutes || [];

  return (req: Request, res: Response, next: NextFunction) => {
    // Check if route should be excluded
    const path = req.path;
    if (excludeRoutes.some((regex) => regex.test(path))) {
      return next();
    }

    // Extract token from Authorization header
    const authHeader = req.headers.authorization;
    if (!authHeader) {
      if (options.optional) {
        return next();
      }
      return res.status(401).json({
        error: 'Unauthorized',
        message: 'Missing Authorization header',
      });
    }

    // Parse Bearer token
    const parts = authHeader.split(' ');
    if (parts.length !== 2 || parts[0].toLowerCase() !== 'bearer') {
      return res.status(401).json({
        error: 'Unauthorized',
        message: 'Invalid Authorization header format (expected "Bearer <token>")',
      });
    }

    const token = parts[1];

    // Validate token
    validator
      .validateToken(token, options.audience)
      .then((claims) => {
        // Attach claims to request
        req.jwt = {
          claims,
          token,
        };
        next();
      })
      .catch((error) => {
        const errorMessage = (error as Error).message;
        res.status(401).json({
          error: 'Unauthorized',
          message: `JWT validation failed: ${errorMessage}`,
        });
      });
  };
}

/**
 * Middleware to require JWT claims
 * 
 * Can be used after jwtAuth to ensure token is present.
 * 
 * @returns Express middleware function
 */
export function requireJwt() {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.jwt?.claims) {
      return res.status(401).json({
        error: 'Unauthorized',
        message: 'JWT token required',
      });
    }
    next();
  };
}

/**
 * Middleware to extract specific claims
 * 
 * @param claimName - Claim name to check
 * @param expectedValue - Optional expected value
 * @returns Express middleware function
 */
export function requireClaim(claimName: keyof JwtClaims, expectedValue?: string) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.jwt?.claims) {
      return res.status(401).json({
        error: 'Unauthorized',
        message: 'JWT token required',
      });
    }

    const claims = req.jwt.claims;
    const claimValue = claims[claimName];

    if (!claimValue) {
      return res.status(403).json({
        error: 'Forbidden',
        message: `Required claim missing: ${claimName}`,
      });
    }

    if (expectedValue && String(claimValue) !== expectedValue) {
      return res.status(403).json({
        error: 'Forbidden',
        message: `Claim "${claimName}" does not match expected value`,
      });
    }

    next();
  };
}

/**
 * Middleware to require service group membership
 * 
 * @param requiredGroups - Groups that are required (any match passes)
 * @returns Express middleware function
 */
export function requireGroups(requiredGroups: string[]) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.jwt?.claims) {
      return res.status(401).json({
        error: 'Unauthorized',
        message: 'JWT token required',
      });
    }

    const claims = req.jwt.claims;
    const userGroups = claims.groups || [];

    const hasRequiredGroup = requiredGroups.some((group) => userGroups.includes(group));

    if (!hasRequiredGroup) {
      return res.status(403).json({
        error: 'Forbidden',
        message: `User must be member of one of: ${requiredGroups.join(', ')}`,
      });
    }

    next();
  };
}

/**
 * Middleware to log JWT claims (for debugging)
 * 
 * @returns Express middleware function
 */
export function logJwt() {
  return (req: Request, res: Response, next: NextFunction) => {
    if (req.jwt?.claims) {
      console.log(`[JWT] sub=${req.jwt.claims.sub} aud=${req.jwt.claims.aud}`);
    }
    next();
  };
}

export type { JwtAuthOptions };
