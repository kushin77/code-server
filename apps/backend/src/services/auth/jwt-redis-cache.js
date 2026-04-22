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
    constructor(redisClient, keyPrefix = 'jwt:', defaultTtlSeconds = 3600) {
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
    async cacheJwks(issuer, jwksData, ttlSeconds = this.defaultTtlSeconds) {
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
    async getJwks(issuer) {
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
    async clearJwks(issuer) {
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
    async cacheToken(tokenId, tokenData, ttlSeconds) {
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
    async getToken(tokenId) {
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
    async invalidateToken(tokenId) {
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
    async storeServiceCredentials(serviceName, clientId, clientSecret) {
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
    async getServiceCredentials(serviceName) {
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
     * Get cache statistics
     *
     * @returns Cache statistics including key counts
     */
    async getStats() {
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
    async clearAll() {
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
    async scanKeys(pattern) {
        const keys = [];
        let cursor = '0';
        do {
            const [newCursor, scanKeys] = await this.redisClient.scan(cursor, 'MATCH', pattern, 'COUNT', 100);
            cursor = newCursor;
            keys.push(...scanKeys);
        } while (cursor !== '0');
        return keys;
    }
}
//# sourceMappingURL=jwt-redis-cache.js.map