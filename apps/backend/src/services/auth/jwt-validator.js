#!/usr/bin/env node
// @file        apps/backend/src/services/auth/jwt-validator.ts
// @module      services/auth
// @description JWT token validation and JWKS caching for service-to-service authentication
// @owner       Infrastructure Team
// @status      ACTIVE
import crypto from 'crypto';
/**
 * JWT Validator for service-to-service authentication
 *
 * Responsibilities:
 * - Validate RS256-signed JWT tokens
 * - Cache JWKS (JSON Web Key Set) with TTL
 * - Verify token claims (aud, iss, exp, iat)
 * - Extract and validate service identity claims
 */
export class JwtValidator {
    constructor(oidcIssuerUrl = process.env.OIDC_ISSUER_URL || 'http://oauth2-oidc-issuer:4182', jwksCacheTtlMs = 3600000) {
        this.jwksCache = new Map();
        this.jwksCacheExpiry = 0;
        this.oidcIssuerUrl = oidcIssuerUrl;
        this.jwksCacheTtlMs = jwksCacheTtlMs;
    }
    /**
     * Validate a JWT token and return claims
     *
     * @param token - JWT token string
     * @param expectedAudience - Expected audience claim (audience must match)
     * @returns Validated JWT claims
     * @throws Error if token is invalid or expired
     */
    async validateToken(token, expectedAudience) {
        // Split JWT into parts
        const parts = token.split('.');
        if (parts.length !== 3) {
            throw new Error('Invalid JWT format (expected 3 parts)');
        }
        const [headerB64, payloadB64, signatureB64] = parts;
        // Decode header and payload
        let header;
        let payload;
        try {
            header = JSON.parse(this.base64UrlDecode(headerB64));
        }
        catch (err) {
            throw new Error('Invalid JWT format (header is not valid JSON)');
        }
        try {
            payload = JSON.parse(this.base64UrlDecode(payloadB64));
        }
        catch (err) {
            throw new Error('Invalid JWT format (payload is not valid JSON)');
        }
        // Validate header
        if (header.alg !== 'RS256') {
            throw new Error(`Unsupported algorithm: ${header.alg} (expected RS256)`);
        }
        if (!header.kid) {
            throw new Error('Token header missing key ID (kid)');
        }
        // Get public key from JWKS
        const publicKey = await this.getPublicKey(header.kid);
        if (!publicKey) {
            throw new Error(`Public key not found for kid: ${header.kid}`);
        }
        // Verify signature
        const signatureValid = this.verifySignature(`${headerB64}.${payloadB64}`, signatureB64, publicKey);
        if (!signatureValid) {
            throw new Error('Signature verification failed');
        }
        // Validate claims
        const claims = payload;
        // Check expiration
        const now = Math.floor(Date.now() / 1000);
        if (claims.exp <= now) {
            throw new Error(`Token expired at ${new Date(claims.exp * 1000).toISOString()}`);
        }
        // Check not-before (if iat is present, token must be issued before now)
        if (claims.iat > now) {
            throw new Error('Token is not yet valid (iat in future)');
        }
        // Check audience
        if (claims.aud !== expectedAudience) {
            throw new Error(`Audience mismatch: expected "${expectedAudience}", got "${claims.aud}"`);
        }
        // Check issuer
        const expectedIssuer = `${this.oidcIssuerUrl.replace(/\/$/, '')}`;
        if (!claims.iss.startsWith(expectedIssuer.replace(/^https?:/, ''))) {
            throw new Error(`Issuer mismatch: expected "${expectedIssuer}", got "${claims.iss}"`);
        }
        return claims;
    }
    /**
     * Get public key by kid, using JWKS cache
     *
     * @param kid - Key ID
     * @returns Public key in PEM format or null if not found
     */
    async getPublicKey(kid) {
        // Check if key is in cache and cache is valid
        if (this.jwksCache.has(kid) && Date.now() < this.jwksCacheExpiry) {
            const cachedKey = this.jwksCache.get(kid);
            return this.jwkToPem(cachedKey);
        }
        // Fetch fresh JWKS
        await this.refreshJwksCache();
        if (this.jwksCache.has(kid)) {
            const cachedKey = this.jwksCache.get(kid);
            return this.jwkToPem(cachedKey);
        }
        return null;
    }
    /**
     * Refresh JWKS cache from OIDC issuer
     *
     * @throws Error if JWKS endpoint is unreachable
     */
    async refreshJwksCache() {
        try {
            const jwksUrl = `${this.oidcIssuerUrl.replace(/\/$/, '')}/.well-known/jwks.json`;
            const response = await fetch(jwksUrl, {
                timeout: 5000,
            });
            if (!response.ok) {
                throw new Error(`JWKS endpoint returned ${response.status}`);
            }
            const data = (await response.json());
            // Clear old cache
            this.jwksCache.clear();
            // Add all keys to cache
            for (const key of data.keys) {
                this.jwksCache.set(key.kid, {
                    kid: key.kid,
                    alg: key.alg,
                    kty: key.kty,
                    use: key.use,
                    n: key.n,
                    e: key.e,
                    cachedAt: Date.now(),
                });
            }
            // Set cache expiry
            this.jwksCacheExpiry = Date.now() + this.jwksCacheTtlMs;
        }
        catch (error) {
            throw new Error(`Failed to refresh JWKS cache: ${error.message}`);
        }
    }
    /**
     * Verify JWT signature using RS256
     *
     * @param message - Message to verify (header.payload)
     * @param signature - Signature bytes in base64url format
     * @param publicKey - Public key in PEM format
     * @returns true if signature is valid
     */
    verifySignature(message, signature, publicKey) {
        try {
            const verify = crypto.createVerify('sha256');
            verify.update(message);
            const signatureBuffer = Buffer.from(signature, 'base64');
            return verify.verify(publicKey, signatureBuffer);
        }
        catch (error) {
            return false;
        }
    }
    /**
     * Convert JWK to PEM format (RSA public key)
     *
     * @param jwk - JSON Web Key
     * @returns PEM-formatted public key
     */
    jwkToPem(jwk) {
        if (jwk.kty !== 'RSA') {
            throw new Error(`Unsupported key type: ${jwk.kty}`);
        }
        // Create public key using JWK format
        // JWK format expects base64url-encoded strings for n and e
        const publicKey = crypto.createPublicKey({
            key: {
                kty: 'RSA',
                n: jwk.n,
                e: jwk.e,
            },
            format: 'jwk',
        });
        return publicKey.export({ format: 'pem', type: 'spki' });
    }
    /**
     * Base64url decode (RFC 4648 Section 5)
     *
     * @param str - Base64url encoded string
     * @returns Decoded string
     */
    base64UrlDecode(str) {
        // Add padding if needed
        const padded = str + '='.repeat((4 - (str.length % 4)) % 4);
        // Replace base64url characters with standard base64
        const standard = padded.replace(/-/g, '+').replace(/_/g, '/');
        return Buffer.from(standard, 'base64').toString('utf-8');
    }
    /**
     * Get cache statistics (for monitoring)
     *
     * @returns Cache statistics
     */
    getCacheStats() {
        return {
            keyCount: this.jwksCache.size,
            cacheValid: Date.now() < this.jwksCacheExpiry,
            cacheExpiresAt: this.jwksCacheExpiry > 0 ? new Date(this.jwksCacheExpiry) : null,
            keyIds: Array.from(this.jwksCache.keys()),
        };
    }
    /**
     * Clear cache (for testing or manual refresh)
     */
    clearCache() {
        this.jwksCache.clear();
        this.jwksCacheExpiry = 0;
    }
}
//# sourceMappingURL=jwt-validator.js.map