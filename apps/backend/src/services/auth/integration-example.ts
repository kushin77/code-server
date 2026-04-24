#!/usr/bin/env ts-node
// @file        apps/backend/src/services/auth/integration-example.ts
// @module      auth/integration-example
// @description Complete example of integrating JWT auth into Express applications
//              Shows both incoming validation and outgoing token acquisition
//

import express, { Request, Response, NextFunction } from 'express';
import {
  JwtValidator,
  JwtTokenClient,
  jwtAuth,
  requireJwt,
  requireClaim,
  JwtRedisCache,
} from './index.js';
import Redis from 'ioredis';

/**
 * Integration Example 1: Incoming Request Validation
 * 
 * This shows how to add JWT validation to an Express application
 * for service-to-service authentication.
 */
export function setupIncomingJwtValidation(app: express.Express, validator: JwtValidator) {
  // ─────────────────────────────────────────────────────────────────────
  // Middleware: Validate JWT tokens in Authorization header
  // ─────────────────────────────────────────────────────────────────────

  // Apply to all /api routes (service-to-service communication)
  app.use('/api', jwtAuth({
    validator,
    audience: 'https://your-service/api',
    optional: false, // Require JWT for /api routes
  }));

  // Health checks and public endpoints don't require JWT
  app.get('/health', (req: Request, res: Response) => {
    res.json({ status: 'healthy' });
  });

  // Example protected route: Get user data
  app.get('/api/users/:userId', requireJwt(), async (req: Request, res: Response) => {
    const reqWithJwt = req as any;
    const claims = reqWithJwt.jwt?.claims;

    // Claims include:
    // - sub: service name (e.g., "code-server")
    // - aud: target audience (e.g., "https://session-broker/api")
    // - iss: issuer (OIDC issuer URL)
    // - iat: issued-at timestamp
    // - exp: expiration timestamp
    // - groups: optional array of groups
    // - actor: optional actor (for GitHub Actions, K8s)

    try {
      const userId = req.params.userId;
      const caller = claims.sub; // Service that called us

      // Log who called us
      console.log(`API call from ${caller} for user ${userId}`);

      // You can use claims for authorization
      if (!canAccess(caller, userId)) {
        return res.status(403).json({ error: 'Access denied' });
      }

      const userData = await fetchUser(userId);
      res.json(userData);
    } catch (error) {
      res.status(500).json({ error: String(error) });
    }
  });

  // Example: Admin-only endpoint using claim-based authz
  app.post('/api/admin/settings', requireClaim('groups', 'admin'), async (req: Request, res: Response) => {
    // Only services in the 'admin' group can access this
    const settings = req.body;

    try {
      await updateSettings(settings);
      res.json({ status: 'updated' });
    } catch (error) {
      res.status(500).json({ error: String(error) });
    }
  });
}

/**
 * Integration Example 2: Outgoing Request Handling
 * 
 * This shows how to use JwtTokenClient to call other services
 * with JWT authentication.
 */
export function setupOutgoingJwtTokens(
  app: express.Express,
  tokenClient: JwtTokenClient,
) {
  // ─────────────────────────────────────────────────────────────────────
  // Example: Make service-to-service call with JWT token
  // ─────────────────────────────────────────────────────────────────────

  app.get('/api/workspace/:workspaceId', async (req: Request, res: Response) => {
    try {
      // When we need to call another service, get a token first
      const token = await tokenClient.getToken('https://session-broker/api');

      // Make request with JWT bearer token
      const response = await fetch(`http://session-broker/api/workspaces/${req.params.workspaceId}`, {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
      });

      if (!response.ok) {
        return res.status(response.status).json({ error: 'Failed to fetch workspace' });
      }

      const data = await response.json();
      res.json(data);
    } catch (error) {
      res.status(500).json({ error: String(error) });
    }
  });

  // ─────────────────────────────────────────────────────────────────────
  // Example: Call multiple services with tokens
  // ─────────────────────────────────────────────────────────────────────

  app.get('/api/dashboard', async (req: Request, res: Response) => {
    try {
      // Fetch data from multiple services in parallel
      const [workspaceData, sessionData, settingsData] = await Promise.all([
        fetch('http://workspace-service/api/data', {
          headers: {
            'Authorization': `Bearer ${await tokenClient.getToken('https://workspace-service/api')}`,
          },
        }).then(r => r.json()),

        fetch('http://session-broker/api/sessions', {
          headers: {
            'Authorization': `Bearer ${await tokenClient.getToken('https://session-broker/api')}`,
          },
        }).then(r => r.json()),

        fetch('http://settings-service/api/config', {
          headers: {
            'Authorization': `Bearer ${await tokenClient.getToken('https://settings-service/api')}`,
          },
        }).then(r => r.json()),
      ]);

      res.json({
        workspace: workspaceData,
        sessions: sessionData,
        settings: settingsData,
      });
    } catch (error) {
      res.status(500).json({ error: String(error) });
    }
  });
}

/**
 * Integration Example 3: Complete Setup
 * 
 * This is how to initialize and configure the complete JWT auth stack
 * in an Express application.
 */
export async function initializeJwtAuthStack(
  app: express.Express,
  config: {
    oidcIssuerUrl: string;
    clientId: string;
    clientSecret: string;
    redisUrl?: string;
    audience: string;
  },
) {
  // ─────────────────────────────────────────────────────────────────────
  // Create JWT services
  // ─────────────────────────────────────────────────────────────────────

  // 1. Create validator for incoming requests
  const validator = new JwtValidator({
    oidcIssuerUrl: config.oidcIssuerUrl,
    jwksCacheTtlSeconds: 3600, // 1 hour
    logger: console,
  });

  // 2. Create token client for outgoing requests
  const tokenClient = new JwtTokenClient({
    oidcIssuerUrl: config.oidcIssuerUrl,
    clientId: config.clientId,
    clientSecret: config.clientSecret,
    logger: console,
  });

  // 3. Optionally create Redis cache for horizontal scaling
  let cache: JwtRedisCache | undefined;
  if (config.redisUrl) {
    const redis = new Redis(config.redisUrl);
    cache = new JwtRedisCache(redis);

    // Store service credentials in cache
    await cache.storeServiceCredentials(
      config.clientId,
      config.clientId,
      config.clientSecret,
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Set up middleware and routes
  // ─────────────────────────────────────────────────────────────────────

  // Body parsing
  app.use(express.json());

  // Add correlation ID for request tracing
  app.use((req: Request, res: Response, next: NextFunction) => {
    const correlationId = req.headers['x-correlation-id'] || `${Date.now()}-${Math.random()}`;
    (req as any).correlationId = correlationId;
    res.setHeader('X-Correlation-ID', correlationId);
    next();
  });

  // Set up JWT validation for incoming requests
  setupIncomingJwtValidation(app, validator);

  // Set up token client for outgoing requests
  setupOutgoingJwtTokens(app, tokenClient);

  // ─────────────────────────────────────────────────────────────────────
  // Error handling
  // ─────────────────────────────────────────────────────────────────────

  app.use((err: any, req: Request, res: Response, next: NextFunction) => {
    console.error('Unhandled error:', err);

    if (err.code === 'INVALID_TOKEN') {
      return res.status(401).json({ error: 'Invalid token' });
    }

    if (err.code === 'TOKEN_EXPIRED') {
      return res.status(401).json({ error: 'Token expired' });
    }

    res.status(500).json({ error: 'Internal server error' });
  });

  return {
    validator,
    tokenClient,
    cache,
  };
}

// ─────────────────────────────────────────────────────────────────────
// Helper functions (implement these based on your business logic)
// ─────────────────────────────────────────────────────────────────────

async function fetchUser(userId: string): Promise<any> {
  // Fetch user data from database
  return { id: userId, name: 'User Name' };
}

function canAccess(caller: string, userId: string): boolean {
  // Implement authorization logic
  // For example: allow code-server to access any user, but other services only their own
  return caller === 'code-server' || caller === userId;
}

async function updateSettings(settings: any): Promise<void> {
  // Update settings in database
  console.log('Updating settings:', settings);
}
