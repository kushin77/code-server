"use strict";
/**
 * Phase 7: Advanced API & Query Engine
 * API Authentication Manager - OAuth2, JWT, API Key support
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.APIAuthenticationManager = void 0;
/**
 * API Authentication Manager
 */
class APIAuthenticationManager {
    constructor(jwtSecret) {
        this.jwtSecret = jwtSecret;
        this.apiKeys = new Map();
        this.oauth2Providers = new Map();
        this.refreshTokens = new Map();
        this.blacklist = new Set();
    }
    /**
     * Authenticate JWT token
     */
    authenticateJWT(token) {
        try {
            // Check blacklist
            if (this.blacklist.has(token)) {
                return null;
            }
            // Decode JWT (simplified - use jsonwebtoken library in production)
            const payload = this.decodeJWT(token);
            if (!payload || payload.exp < Date.now() / 1000) {
                return null;
            }
            return {
                type: 'jwt',
                userId: payload.sub,
                tenantId: payload.tenantId,
                scopes: payload.scope || [],
                expiresAt: payload.exp * 1000,
            };
        }
        catch {
            return null;
        }
    }
    /**
     * Authenticate API Key
     */
    authenticateAPIKey(keyId, keySecret) {
        const apiKey = this.apiKeys.get(keyId);
        if (!apiKey || apiKey.secret !== keySecret || !apiKey.active) {
            return null;
        }
        // Check expiration
        if (apiKey.expiresAt && apiKey.expiresAt < Date.now()) {
            return null;
        }
        // Update last used
        apiKey.lastUsed = Date.now();
        return {
            type: 'apikey',
            userId: keyId,
            tenantId: '', // API keys may not have tenant
            scopes: apiKey.scopes,
            expiresAt: apiKey.expiresAt || Date.now() + 365 * 24 * 60 * 60 * 1000,
        };
    }
    /**
     * Authenticate OAuth2 token
     */
    authenticateOAuth2(token, provider) {
        const oauthProvider = this.oauth2Providers.get(provider);
        if (!oauthProvider) {
            return null;
        }
        try {
            // Validate token with OAuth2 provider
            const userInfo = oauthProvider.validateToken(token);
            if (!userInfo) {
                return null;
            }
            return {
                type: 'oauth2',
                userId: userInfo.id,
                tenantId: userInfo.tenantId,
                scopes: userInfo.scopes || [],
                expiresAt: userInfo.expiresAt,
            };
        }
        catch {
            return null;
        }
    }
    /**
     * Create JWT token
     */
    createJWTToken(userId, tenantId, scopes, expiresIn = 3600) {
        const payload = {
            sub: userId,
            tenantId,
            scope: scopes,
            iat: Math.floor(Date.now() / 1000),
            exp: Math.floor(Date.now() / 1000) + expiresIn,
        };
        return this.encodeJWT(payload);
    }
    /**
     * Create API Key
     */
    createAPIKey(userId, name, scopes, expiresIn) {
        const keyId = `key_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
        const keySecret = this.generateSecret();
        const apiKey = {
            id: keyId,
            secret: keySecret,
            name,
            scopes,
            rateLimit: 1000, // requests per hour
            createdAt: Date.now(),
            expiresAt: expiresIn ? Date.now() + expiresIn : undefined,
            active: true,
        };
        this.apiKeys.set(keyId, apiKey);
        return { id: keyId, secret: keySecret };
    }
    /**
     * Revoke token
     */
    revokeToken(token) {
        this.blacklist.add(token);
    }
    /**
     * Revoke API Key
     */
    revokeAPIKey(keyId) {
        const apiKey = this.apiKeys.get(keyId);
        if (apiKey) {
            apiKey.active = false;
            return true;
        }
        return false;
    }
    /**
     * List API Keys for user
     */
    listAPIKeys(userId) {
        const keys = [];
        this.apiKeys.forEach((key) => {
            if (key.id.includes(userId)) {
                const { secret, ...keyWithoutSecret } = key;
                keys.push(keyWithoutSecret);
            }
        });
        return keys;
    }
    /**
     * Refresh JWT token
     */
    refreshJWTToken(refreshToken) {
        const userId = this.refreshTokens.get(refreshToken);
        if (!userId) {
            return null;
        }
        // Create new JWT token
        return this.createJWTToken(userId, '', [], 3600);
    }
    /**
     * Register OAuth2 Provider
     */
    registerOAuth2Provider(name, config) {
        this.oauth2Providers.set(name, {
            name,
            config,
            validateToken: (token) => {
                // Implementation specific to provider
                return null;
            },
        });
    }
    /**
     * Decode JWT (simplified)
     */
    decodeJWT(token) {
        try {
            const parts = token.split('.');
            if (parts.length !== 3)
                return null;
            const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString());
            return payload;
        }
        catch {
            return null;
        }
    }
    /**
     * Encode JWT (simplified)
     */
    encodeJWT(payload) {
        const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64');
        const payloadStr = Buffer.from(JSON.stringify(payload)).toString('base64');
        const signature = Buffer.from(this.jwtSecret + header + payloadStr).toString('base64').substring(0, 43);
        return `${header}.${payloadStr}.${signature}`;
    }
    /**
     * Generate random secret
     */
    generateSecret() {
        return Buffer.from(Math.random().toString()).toString('base64').substring(0, 32);
    }
    /**
     * Get authentication statistics
     */
    getStats() {
        const activeKeys = Array.from(this.apiKeys.values()).filter((k) => k.active).length;
        return {
            totalKeys: this.apiKeys.size,
            activeKeys,
            blacklistedTokens: this.blacklist.size,
        };
    }
}
exports.APIAuthenticationManager = APIAuthenticationManager;
exports.default = APIAuthenticationManager;
//# sourceMappingURL=APIAuthenticationManager.js.map