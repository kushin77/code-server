#!/usr/bin/env node
// @file        apps/backend/src/services/auth/jwt-token-client.ts
// @module      services/auth
// @description JWT token acquisition and refresh for service-to-service communication
// @owner       Infrastructure Team
// @status      ACTIVE
/**
 * JWT Token Client for service-to-service authentication
 *
 * Responsibilities:
 * - Acquire JWT tokens from OIDC issuer using client credentials
 * - Cache tokens locally with automatic refresh before expiry
 * - Handle token expiration and refresh
 * - Provide tokens for outbound service-to-service calls
 */
export class JwtTokenClient {
    constructor(clientId, clientSecret, oidcIssuerUrl = process.env.OIDC_ISSUER_URL || 'http://oauth2-oidc-issuer:4182', tokenRefreshBufferMs = 300000) {
        this.tokenCache = new Map();
        this.refreshSchedules = new Map();
        this.clientId = clientId;
        this.clientSecret = clientSecret;
        this.oidcIssuerUrl = oidcIssuerUrl;
        this.tokenRefreshBufferMs = tokenRefreshBufferMs;
    }
    /**
     * Acquire a JWT token for service-to-service communication
     *
     * Uses client credentials flow to get a token from the OIDC issuer.
     * Tokens are cached and automatically refreshed before expiry.
     *
     * @param audience - Intended audience for the token (e.g., 'https://code-server/api')
     * @param scope - Optional scope (not used in client credentials flow, but for future compatibility)
     * @returns JWT access token
     * @throws Error if token acquisition fails
     */
    async getToken(audience, scope) {
        const cacheKey = `${audience}:${scope || ''}`;
        // Check if valid token exists in cache
        const cached = this.tokenCache.get(cacheKey);
        if (cached && Date.now() < cached.expiresAt) {
            return cached.accessToken;
        }
        // Acquire new token
        const token = await this.acquireToken(audience, scope);
        // Cache the token and schedule refresh
        const expiresAt = Date.now() + token.expires_in * 1000;
        this.tokenCache.set(cacheKey, {
            accessToken: token.access_token,
            expiresAt,
            refreshToken: token.refresh_token,
        });
        // Schedule automatic refresh before expiry
        this.scheduleRefresh(cacheKey, expiresAt);
        return token.access_token;
    }
    /**
     * Acquire a new token from the OIDC issuer
     *
     * @param audience - Token audience
     * @param scope - Optional scope
     * @returns Token response from issuer
     * @throws Error if acquisition fails
     */
    async acquireToken(audience, scope) {
        try {
            const tokenUrl = `${this.oidcIssuerUrl.replace(/\/$/, '')}/oauth2/token`;
            // Build request body (client credentials flow)
            const body = new URLSearchParams({
                grant_type: 'client_credentials',
                client_id: this.clientId,
                client_secret: this.clientSecret,
                scope: scope || 'openid profile',
                aud: audience,
            });
            const response = await fetch(tokenUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: body.toString(),
                timeout: 10000,
            });
            if (!response.ok) {
                const error = await response.text();
                throw new Error(`Token endpoint returned ${response.status}: ${error}`);
            }
            const tokenData = (await response.json());
            if (!tokenData.access_token) {
                throw new Error('No access_token in response');
            }
            if (!tokenData.expires_in) {
                throw new Error('No expires_in in response');
            }
            return tokenData;
        }
        catch (error) {
            throw new Error(`Failed to acquire token: ${error.message}`);
        }
    }
    /**
     * Schedule automatic token refresh before expiry
     *
     * @param cacheKey - Cache key for the token
     * @param expiresAt - Absolute expiry timestamp (ms)
     */
    scheduleRefresh(cacheKey, expiresAt) {
        // Cancel existing refresh if scheduled
        const existingSchedule = this.refreshSchedules.get(cacheKey);
        if (existingSchedule) {
            clearTimeout(existingSchedule);
        }
        // Schedule refresh at (expiryTime - bufferTime)
        const refreshAt = expiresAt - this.tokenRefreshBufferMs;
        const delayMs = Math.max(0, refreshAt - Date.now());
        const timeout = setTimeout(() => {
            // Refresh the token
            const [audience, scope] = cacheKey.split(':');
            this.getToken(audience, scope || undefined).catch((error) => {
                console.error(`Token refresh failed for ${cacheKey}: ${error.message}`);
            });
        }, delayMs);
        this.refreshSchedules.set(cacheKey, timeout);
    }
    /**
     * Invalidate cached token (e.g., after auth failure)
     *
     * @param audience - Token audience
     * @param scope - Optional scope
     */
    invalidateToken(audience, scope) {
        const cacheKey = `${audience}:${scope || ''}`;
        this.tokenCache.delete(cacheKey);
        const schedule = this.refreshSchedules.get(cacheKey);
        if (schedule) {
            clearTimeout(schedule);
            this.refreshSchedules.delete(cacheKey);
        }
    }
    /**
     * Get cache statistics (for monitoring)
     *
     * @returns Cache statistics
     */
    getCacheStats() {
        const now = Date.now();
        return {
            cachedTokenCount: this.tokenCache.size,
            schedules: Array.from(this.tokenCache.entries())
                .map(([cacheKey, token]) => ({
                cacheKey,
                expiresIn: Math.max(0, token.expiresAt - now),
            })),
        };
    }
    /**
     * Clear all cached tokens and cancel refresh schedules
     */
    clearCache() {
        // Cancel all refresh schedules
        for (const timeout of this.refreshSchedules.values()) {
            clearTimeout(timeout);
        }
        this.tokenCache.clear();
        this.refreshSchedules.clear();
    }
    /**
     * Shutdown: cleanup schedules and cache
     */
    async shutdown() {
        this.clearCache();
    }
}
//# sourceMappingURL=jwt-token-client.js.map