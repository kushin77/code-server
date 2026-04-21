#!/usr/bin/env node
// @file        apps/backend/src/services/auth/index.ts
// @module      services/auth
// @description Barrel export for authentication services
// @owner      Infrastructure Team
// @status      ACTIVE

import { JwtValidator } from './jwt-validator.js';
import { JwtTokenClient } from './jwt-token-client.js';
import { JwtRedisCache } from './jwt-redis-cache.js';

export { JwtValidator, type JwtClaims, type CachedKey } from './jwt-validator.js';
export { JwtTokenClient, type TokenResponse } from './jwt-token-client.js';
export { JwtRedisCache } from './jwt-redis-cache.js';
export { jwtMetrics, metricsHandler, renderMetrics } from './jwt-metrics.js';

/**
 * Create a complete service-to-service auth stack
 */
export async function createAuthStack(
  redisClient: any,
  oidcIssuerUrl: string = process.env.OIDC_ISSUER_URL || 'http://oauth2-oidc-issuer:4182',
) {
  return {
    validator: new JwtValidator(oidcIssuerUrl),
    tokenClient: new JwtTokenClient(
      process.env.SERVICE_CLIENT_ID || 'code-server',
      process.env.SERVICE_CLIENT_SECRET || '',
      oidcIssuerUrl,
    ),
    cache: new JwtRedisCache(redisClient),
  };
}
