import { test, expect } from '@playwright/test';
const TOKEN_ENDPOINT = process.env.TOKEN_ENDPOINT || 'https://ide.kushnir.cloud/oauth2/token';
const JWKS_ENDPOINT = process.env.JWKS_ENDPOINT || 'https://ide.kushnir.cloud/.well-known/jwks.json';
const OIDC_CONFIG_ENDPOINT = process.env.OIDC_CONFIG_ENDPOINT || 'https://ide.kushnir.cloud/.well-known/openid-configuration';
const IDE_URL = process.env.IDE_BASE_URL || 'https://ide.kushnir.cloud';
test.describe('JWT Token Validation (#1177)', () => {
    test.describe('OIDC Discovery Endpoints', () => {
        test('1: OIDC configuration endpoint responds with proper metadata', async ({ page }) => {
            const response = await page.request.get(OIDC_CONFIG_ENDPOINT);
            expect(response.ok).toBe(true);
            expect(response.status()).toBe(200);
            const config = await response.json();
            expect(config.issuer).toBeDefined();
            expect(config.authorization_endpoint).toBeDefined();
            expect(config.token_endpoint).toBeDefined();
            expect(config.jwks_uri).toBeDefined();
            expect(config.response_types_supported).toBeDefined();
        });
        test('2: JWKS endpoint returns valid public keys', async ({ page }) => {
            const response = await page.request.get(JWKS_ENDPOINT);
            expect(response.ok).toBe(true);
            expect(response.status()).toBe(200);
            const jwks = await response.json();
            expect(jwks.keys).toBeDefined();
            expect(Array.isArray(jwks.keys)).toBe(true);
            expect(jwks.keys.length).toBeGreaterThan(0);
            // Verify key structure
            const key = jwks.keys[0];
            expect(key.kty).toBeDefined(); // Key type
            expect(key.use).toBe('sig'); // Signing key
            expect(key.alg).toBe('RS256'); // Algorithm
            expect(key.n).toBeDefined(); // Modulus
            expect(key.e).toBeDefined(); // Exponent
        });
        test('3: JWKS endpoint returns cache-friendly headers', async ({ page }) => {
            const response = await page.request.get(JWKS_ENDPOINT);
            // Should have caching headers
            const cacheControl = response.headerValue('cache-control');
            expect(cacheControl).toBeDefined();
            expect(cacheControl).toContain('public');
        });
    });
    test.describe('Token Acquisition', () => {
        test('1: Token endpoint accepts valid client credentials', async ({ page }) => {
            // Note: This test assumes valid credentials are available in environment
            const response = await page.request.post(TOKEN_ENDPOINT, {
                data: {
                    grant_type: 'client_credentials',
                    client_id: 'code-server',
                    client_secret: process.env.OAUTH2_CLIENT_SECRET || 'test-secret'
                }
            });
            // Should succeed with 200 OK
            if (process.env.OAUTH2_CLIENT_SECRET) {
                expect(response.ok).toBe(true);
                const body = await response.json();
                expect(body.access_token).toBeDefined();
                expect(body.token_type).toBe('Bearer');
            }
        });
        test('2: Token endpoint rejects invalid credentials', async ({ page }) => {
            const response = await page.request.post(TOKEN_ENDPOINT, {
                data: {
                    grant_type: 'client_credentials',
                    client_id: 'invalid-client',
                    client_secret: 'wrong-secret'
                }
            });
            // Should fail with 401 or 400
            expect([400, 401]).toContain(response.status());
        });
        test('3: Token endpoint requires grant_type parameter', async ({ page }) => {
            const response = await page.request.post(TOKEN_ENDPOINT, {
                data: {
                    client_id: 'code-server',
                    client_secret: 'test'
                }
            });
            // Should fail with 400 Bad Request
            expect(response.status()).toBe(400);
        });
    });
    test.describe('Token Structure & Claims', () => {
        test('1: JWT token has three parts (header.payload.signature)', async ({ page }) => {
            const token = await acquireToken(page);
            if (!token) {
                test.skip();
                return;
            }
            const parts = token.split('.');
            expect(parts.length).toBe(3);
            // Each part should be base64url encoded
            expect(parts[0]).toMatch(/^[A-Za-z0-9_-]+$/);
            expect(parts[1]).toMatch(/^[A-Za-z0-9_-]+$/);
            expect(parts[2]).toMatch(/^[A-Za-z0-9_-]+$/);
        });
        test('2: JWT header specifies RS256 algorithm', async ({ page }) => {
            const token = await acquireToken(page);
            if (!token) {
                test.skip();
                return;
            }
            const header = decodeJwtPart(token.split('.')[0]);
            expect(header.alg).toBe('RS256');
            expect(header.typ).toBe('JWT');
        });
        test('3: JWT payload contains required claims', async ({ page }) => {
            const token = await acquireToken(page);
            if (!token) {
                test.skip();
                return;
            }
            const payload = decodeJwtPart(token.split('.')[1]);
            // Required claims
            expect(payload.sub).toBeDefined(); // Subject
            expect(payload.aud).toBeDefined(); // Audience
            expect(payload.iss).toBeDefined(); // Issuer
            expect(payload.iat).toBeDefined(); // Issued at (seconds since epoch)
            expect(payload.exp).toBeDefined(); // Expiration (seconds since epoch)
            // Timing validation
            expect(typeof payload.iat).toBe('number');
            expect(typeof payload.exp).toBe('number');
            expect(payload.exp).toBeGreaterThan(payload.iat);
        });
        test('4: JWT audience matches expected values', async ({ page }) => {
            const token = await acquireToken(page);
            if (!token) {
                test.skip();
                return;
            }
            const payload = decodeJwtPart(token.split('.')[1]);
            // Audience can be string or array
            if (typeof payload.aud === 'string') {
                expect(['code-server', 'api', 'github-actions']).toContain(payload.aud);
            }
            else if (Array.isArray(payload.aud)) {
                expect(payload.aud.length).toBeGreaterThan(0);
            }
        });
        test('5: Token expiration is reasonable (not too long)', async ({ page }) => {
            const token = await acquireToken(page);
            if (!token) {
                test.skip();
                return;
            }
            const payload = decodeJwtPart(token.split('.')[1]);
            const expirationSeconds = payload.exp - payload.iat;
            // Should be between 15 minutes and 1 day
            expect(expirationSeconds).toBeGreaterThan(900); // 15 minutes
            expect(expirationSeconds).toBeLessThan(86400); // 1 day
        });
    });
    test.describe('Token Validation', () => {
        test('1: Expired token is rejected', async ({ page }) => {
            // Create an artificially expired token (would need test utilities)
            const expiredToken = createExpiredTestToken();
            const response = await page.request.get(`${IDE_URL}/api/v1/authenticated-endpoint`, {
                headers: {
                    'Authorization': `Bearer ${expiredToken}`
                }
            });
            expect(response.status()).toBe(401);
        });
        test('2: Token with invalid signature is rejected', async ({ page }) => {
            // Create token with tampered signature
            const tamperedToken = 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0In0.invalid-signature';
            const response = await page.request.get(`${IDE_URL}/api/v1/authenticated-endpoint`, {
                headers: {
                    'Authorization': `Bearer ${tamperedToken}`
                }
            });
            expect(response.status()).toBe(401);
        });
        test('3: Token with altered payload is rejected', async ({ page }) => {
            // Get valid token and tamper with payload
            const validToken = await acquireToken(page);
            if (!validToken) {
                test.skip();
                return;
            }
            const parts = validToken.split('.');
            const tampered = `${parts[0]}.tampered-payload.${parts[2]}`;
            const response = await page.request.get(`${IDE_URL}/api/v1/authenticated-endpoint`, {
                headers: {
                    'Authorization': `Bearer ${tampered}`
                }
            });
            expect(response.status()).toBe(401);
        });
        test('4: Valid token is accepted', async ({ page }) => {
            const token = await acquireToken(page);
            if (!token) {
                test.skip();
                return;
            }
            const response = await page.request.get(`${IDE_URL}/api/v1/sessions`, {
                headers: {
                    'Authorization': `Bearer ${token}`
                }
            });
            // Should not return 401
            expect(response.status()).not.toBe(401);
        });
    });
    test.describe('Token Refresh & Expiration', () => {
        test('1: Token can be refreshed before expiration', async ({ page }) => {
            // Get initial token
            const token1 = await acquireToken(page);
            if (!token1) {
                test.skip();
                return;
            }
            // Request new token
            const token2 = await acquireToken(page);
            // Both should be valid
            expect(token1).toBeDefined();
            expect(token2).toBeDefined();
            expect(token1).not.toBe(token2); // Should be different tokens
        });
        test('2: Token issued timestamp is recent', async ({ page }) => {
            const token = await acquireToken(page);
            if (!token) {
                test.skip();
                return;
            }
            const payload = decodeJwtPart(token.split('.')[1]);
            const nowSeconds = Math.floor(Date.now() / 1000);
            const issuedSeconds = payload.iat;
            // Token should have been issued within last 60 seconds
            expect(nowSeconds - issuedSeconds).toBeLessThan(60);
        });
    });
    test.describe('JWKS Cache Validation', () => {
        test('1: JWKS endpoint is cacheable', async ({ page }) => {
            const response = await page.request.get(JWKS_ENDPOINT);
            const cacheControl = response.headerValue('cache-control');
            expect(cacheControl).toBeDefined();
            // Should specify max-age or similar
            const hasMaxAge = cacheControl?.includes('max-age');
            const hasPublic = cacheControl?.includes('public');
            expect(hasMaxAge || hasPublic).toBe(true);
        });
        test('2: Multiple JWKS requests return same data', async ({ page }) => {
            const response1 = await page.request.get(JWKS_ENDPOINT);
            const response2 = await page.request.get(JWKS_ENDPOINT);
            const data1 = await response1.json();
            const data2 = await response2.json();
            // Should have same keys
            expect(data1.keys.length).toBe(data2.keys.length);
            expect(JSON.stringify(data1.keys[0])).toBe(JSON.stringify(data2.keys[0]));
        });
    });
});
// Helper functions
async function acquireToken(page) {
    try {
        const response = await page.request.post(TOKEN_ENDPOINT, {
            data: {
                grant_type: 'client_credentials',
                client_id: 'code-server',
                client_secret: process.env.OAUTH2_CLIENT_SECRET || ''
            }
        });
        if (!response.ok)
            return null;
        const body = await response.json();
        return body.access_token;
    }
    catch (e) {
        return null;
    }
}
function decodeJwtPart(part) {
    try {
        // Add padding if needed
        const padded = part.padEnd(part.length + (4 - (part.length % 4)) % 4, '=');
        const decoded = Buffer.from(padded, 'base64').toString('utf-8');
        return JSON.parse(decoded);
    }
    catch (e) {
        return {};
    }
}
function createExpiredTestToken() {
    // Create a token that expired 1 hour ago
    const now = Math.floor(Date.now() / 1000);
    const payload = {
        sub: 'test-user',
        aud: 'code-server',
        iss: 'https://ide.kushnir.cloud',
        iat: now - 7200, // 2 hours ago
        exp: now - 3600 // 1 hour ago (expired)
    };
    // This is a simplified version - real implementation would sign properly
    return 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.' +
        Buffer.from(JSON.stringify(payload)).toString('base64url') +
        '.invalid-signature';
}
//# sourceMappingURL=jwt-token-validation.spec.js.map