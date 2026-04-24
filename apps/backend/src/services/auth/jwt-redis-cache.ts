#!/usr/bin/env node
// @file        apps/backend/src/services/auth/jwt-redis-cache.ts
// @module      services/auth
// @description Redis-backed cache for JWT tokens and JWKS
// @owner       Infrastructure Team
// @status      ACTIVE

/**
 * JWT Redis Cache Manager
 * 
 * Provides distributed caching for:
 * - JWKS (JSON Web Key Set) - shared across all service instances
 * - JWT tokens - for distributed token management
 * 
 * Enables horizontal scaling by allowing multiple service instances
 * to share token and key cache.
 */
export class JwtRedisCache {
  private redisClient: any; // Redis client (passed in)
  private readonly keyPrefix: string;
  private readonly defaultTtlSeconds: number;

  constructor(
    redisClient: any,
    keyPrefix: string = 'jwt:',
    defaultTtlSeconds: number = 3600, // 1 hour
  ) {
    this.redisClient = redisClient;
    this.keyPrefix = keyPrefix;
    this.defaultTtlSeconds = defaultTtlSeconds;
  }

  /**
   * Cache JWKS (JSON Web Key Set)
   * 
   * @param issuer - OIDC issuer URL
   * @param jwksData - JWKS response data
   * @param ttlSeconds - Cache TTL (default 1 hour)
   */
  async cacheJwks(
    issuer: string,
    jwksData: { keys: any[] },
    ttlSeconds: number = this.defaultTtlSeconds,
  ): Promise<void> {
    const key = `${this.keyPrefix}jwks:${issuer}`;
    const value = JSON.stringify(jwksData);
    await this.redisClient.setex(key, ttlSeconds, value);
  }

  /**
   * Get cached JWKS
   * 
   * @param issuer - OIDC issuer URL
   * @returns JWKS data or null if not cached
   */
  async getJwks(issuer: string): Promise<{ keys: any[] } | null> {
    const key = `${this.keyPrefix}jwks:${issuer}`;
    const cached = await this.redisClient.get(key);
    if (!cached) {
      return null;
    }
    return JSON.parse(cached);
  }

  /**
   * Clear JWKS cache for issuer (force refresh)
   * 
   * @param issuer - OIDC issuer URL
   */
  async clearJwks(issuer: string): Promise<void> {
    const key = `${this.keyPrefix}jwks:${issuer}`;
    await this.redisClient.del(key);
  }

  /**
   * Cache JWT token
   * 
   * @param tokenId - Unique token ID
   * @param tokenData - Token data including access_token, expires_in
   * @param ttlSeconds - Cache TTL (defaults to token's expires_in)
   */
  async cacheToken(
    tokenId: string,
    tokenData: { access_token: string; expires_in: number },
    ttlSeconds?: number,
  ): Promise<void> {
    const key = `${this.keyPrefix}token:${tokenId}`;
    const value = JSON.stringify({
      access_token: tokenData.access_token,
      cached_at: Date.now(),
      expires_in: tokenData.expires_in,
    });
    const ttl = ttlSeconds || tokenData.expires_in;
    await this.redisClient.setex(key, ttl, value);
  }

  /**
   * Get cached token
   * 
   * @param tokenId - Unique token ID
   * @returns Token data or null if not cached
   */
  async getToken(tokenId: string): Promise<{ access_token: string; expires_in: number } | null> {
    const key = `${this.keyPrefix}token:${tokenId}`;
    const cached = await this.redisClient.get(key);
    if (!cached) {
      return null;
    }
    const data = JSON.parse(cached);
    return {
      access_token: data.access_token,
      expires_in: data.expires_in,
    };
  }

  /**
   * Invalidate token cache
   * 
   * @param tokenId - Unique token ID
   */
  async invalidateToken(tokenId: string): Promise<void> {
    const key = `${this.keyPrefix}token:${tokenId}`;
    await this.redisClient.del(key);
  }

  /**
   * Store service identity credentials
   * 
   * Used for service-to-service authentication.
   * Each service has client_id and client_secret for token exchange.
   * 
   * @param serviceName - Service name (e.g., 'code-server', 'session-broker')
   * @param clientId - OIDC client ID
   * @param clientSecret - OIDC client secret (encrypted in production)
   */
  async storeServiceCredentials(
    serviceName: string,
    clientId: string,
    clientSecret: string,
  ): Promise<void> {
    const key = `${this.keyPrefix}service:${serviceName}`;
    const value = JSON.stringify({
      client_id: clientId,
      client_secret: clientSecret, // Should be encrypted in production
      stored_at: Date.now(),
    });
    // No expiry for credentials (should be updated via separate mechanism)
    await this.redisClient.set(key, value);
  }

  /**
   * Get service credentials
   * 
   * @param serviceName - Service name
   * @returns Service credentials or null if not found
   */
  async getServiceCredentials(
    serviceName: string,
  ): Promise<{ client_id: string; client_secret: string } | null> {
    const key = `${this.keyPrefix}service:${serviceName}`;
    const cached = await this.redisClient.get(key);
    if (!cached) {
      return null;
    }
    const data = JSON.parse(cached);
    return {
      client_id: data.client_id,
      client_secret: data.client_secret,
    };
  }

  /**
   * Store session-scoped service credentials
   * 
   * Session credentials are temporary credentials with a TTL for a specific session.
   * Each session can have multiple credential types (db, cloud, etc.)
   * 
   * @param sessionId - Session ID
   * @param serviceName - Service type (e.g., 'db', 'cloud')
   * @param clientId - OIDC client ID
   * @param clientSecret - OIDC client secret
   * @param ttlSeconds - Time to live for this credential (session lifetime)
   */
  async storeSessionCredentials(
    sessionId: string,
    serviceName: string,
    clientId: string,
    clientSecret: string,
    ttlSeconds: number,
  ): Promise<void> {
    const key = `${this.keyPrefix}session:${sessionId}:${serviceName}`;
    const value = JSON.stringify({
      client_id: clientId,
      client_secret: clientSecret,
      session_id: sessionId,
      service_name: serviceName,
      stored_at: Date.now(),
    });
    await this.redisClient.setex(key, ttlSeconds, value);
  }

  /**
   * Get session-scoped service credentials
   * 
   * @param sessionId - Session ID
   * @param serviceName - Service type
   * @returns Session credentials or null if not found
   */
  async getSessionCredentials(
    sessionId: string,
    serviceName: string,
  ): Promise<{ client_id: string; client_secret: string; session_id: string; service_name: string } | null> {
    const key = `${this.keyPrefix}session:${sessionId}:${serviceName}`;
    const cached = await this.redisClient.get(key);
    if (!cached) {
      return null;
    }
    const data = JSON.parse(cached);
    return {
      client_id: data.client_id,
      client_secret: data.client_secret,
      session_id: data.session_id,
      service_name: data.service_name,
    };
  }

  /**
   * Revoke all credentials for a session
   * 
   * Removes all session-scoped credentials associated with a session ID.
   * Does not affect legacy service credentials (without session ID).
   * 
   * @param sessionId - Session ID
   * @returns Number of credentials revoked
   */
  async revokeSessionCredentials(sessionId: string): Promise<number> {
    const pattern = `${this.keyPrefix}session:${sessionId}:*`;
    const keys = await this.scanKeys(pattern);
    if (keys.length === 0) {
      return 0;
    }
    const deletedCount = await this.redisClient.del(...keys);
    return deletedCount;
  }

  /**
   * Get cache statistics
   * 
   * @returns Cache statistics including key counts
   */
  async getStats(): Promise<{
    totalJwtKeys: number;
    totalTokens: number;
    totalServices: number;
  }> {
    // Scan for keys with our prefix
    const pattern = `${this.keyPrefix}*`;
    const keys = await this.scanKeys(pattern);

    const stats = {
      totalJwtKeys: keys.filter((k) => k.includes(':jwks:')).length,
      totalTokens: keys.filter((k) => k.includes(':token:')).length,
      totalServices: keys.filter((k) => k.includes(':service:')).length,
    };

    return stats;
  }

  /**
   * Clear all JWT-related cache
   */
  async clearAll(): Promise<void> {
    const pattern = `${this.keyPrefix}*`;
    const keys = await this.scanKeys(pattern);
    if (keys.length > 0) {
      await this.redisClient.del(...keys);
    }
  }

  /**
   * Scan Redis keys matching pattern
   * 
   * @param pattern - Key pattern
   * @returns List of matching keys
   */
  private async scanKeys(pattern: string): Promise<string[]> {
    const keys: string[] = [];
    let cursor = '0';

    do {
      const [newCursor, scanKeys] = await this.redisClient.scan(
        cursor,
        'MATCH',
        pattern,
        'COUNT',
        100,
      );
      cursor = newCursor;
      keys.push(...scanKeys);
    } while (cursor !== '0');

    return keys;
  }
}
