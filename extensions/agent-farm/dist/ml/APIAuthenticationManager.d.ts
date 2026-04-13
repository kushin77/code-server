/**
 * Phase 7: Advanced API & Query Engine
 * API Authentication Manager - OAuth2, JWT, API Key support
 */
export interface JWTToken {
    sub: string;
    iat: number;
    exp: number;
    scope: string[];
    tenantId: string;
    [key: string]: any;
}
export interface APIKey {
    id: string;
    secret: string;
    name: string;
    scopes: string[];
    rateLimit: number;
    lastUsed?: number;
    createdAt: number;
    expiresAt?: number;
    active: boolean;
}
export interface OAuth2Token {
    accessToken: string;
    refreshToken?: string;
    tokenType: string;
    expiresIn: number;
    scope: string[];
}
export interface AuthPayload {
    type: 'oauth2' | 'jwt' | 'apikey';
    userId?: string;
    tenantId?: string;
    scopes: string[];
    expiresAt: number;
}
/**
 * API Authentication Manager
 */
export declare class APIAuthenticationManager {
    private jwtSecret;
    private apiKeys;
    private oauth2Providers;
    private refreshTokens;
    private blacklist;
    constructor(jwtSecret: string);
    /**
     * Authenticate JWT token
     */
    authenticateJWT(token: string): AuthPayload | null;
    /**
     * Authenticate API Key
     */
    authenticateAPIKey(keyId: string, keySecret: string): AuthPayload | null;
    /**
     * Authenticate OAuth2 token
     */
    authenticateOAuth2(token: string, provider: string): AuthPayload | null;
    /**
     * Create JWT token
     */
    createJWTToken(userId: string, tenantId: string, scopes: string[], expiresIn?: number): string;
    /**
     * Create API Key
     */
    createAPIKey(userId: string, name: string, scopes: string[], expiresIn?: number): {
        id: string;
        secret: string;
    };
    /**
     * Revoke token
     */
    revokeToken(token: string): void;
    /**
     * Revoke API Key
     */
    revokeAPIKey(keyId: string): boolean;
    /**
     * List API Keys for user
     */
    listAPIKeys(userId: string): Array<Omit<APIKey, 'secret'>>;
    /**
     * Refresh JWT token
     */
    refreshJWTToken(refreshToken: string): string | null;
    /**
     * Register OAuth2 Provider
     */
    registerOAuth2Provider(name: string, config: any): void;
    /**
     * Decode JWT (simplified)
     */
    private decodeJWT;
    /**
     * Encode JWT (simplified)
     */
    private encodeJWT;
    /**
     * Generate random secret
     */
    private generateSecret;
    /**
     * Get authentication statistics
     */
    getStats(): {
        totalKeys: number;
        activeKeys: number;
        blacklistedTokens: number;
    };
}
export default APIAuthenticationManager;
//# sourceMappingURL=APIAuthenticationManager.d.ts.map
