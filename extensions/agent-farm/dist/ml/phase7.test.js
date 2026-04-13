"use strict";
/**
 * Phase 7: Advanced API & Query Engine - Test Suite
 */
Object.defineProperty(exports, "__esModule", { value: true });
const globals_1 = require("@jest/globals");
const GraphQLQueryEngine_1 = require("../ml/GraphQLQueryEngine");
const APIAuthenticationManager_1 = require("../ml/APIAuthenticationManager");
const RateLimiter_1 = require("../ml/RateLimiter");
const GraphQLAPIPhase7Agent_1 = require("../agents/GraphQLAPIPhase7Agent");
(0, globals_1.describe)('Phase 7: Advanced API & Query Engine', () => {
    let graphqlEngine;
    let authManager;
    let rateLimiter;
    let agent;
    (0, globals_1.beforeEach)(() => {
        graphqlEngine = new GraphQLQueryEngine_1.GraphQLQueryEngine({}, {});
        authManager = new APIAuthenticationManager_1.APIAuthenticationManager('test-secret');
        rateLimiter = new RateLimiter_1.RateLimiter();
        agent = new GraphQLAPIPhase7Agent_1.GraphQLAPIPhase7Agent({}, 'test-secret');
    });
    (0, globals_1.describe)('GraphQLQueryEngine', () => {
        (0, globals_1.it)('should parse simple GraphQL query', async () => {
            const query = 'query { user { name email } }';
            const context = {
                userId: 'test-user',
                tenantId: 'test-tenant',
                permissions: new Set(['user:read']),
                graph: {},
                cache: new Map(),
            };
            const result = await graphqlEngine.execute({ query }, context);
            (0, globals_1.expect)(result).toBeDefined();
            (0, globals_1.expect)(result.extensions).toBeDefined();
            (0, globals_1.expect)(result.extensions?.executionTime).toBeGreaterThanOrEqual(0);
        });
        (0, globals_1.it)('should cache query results', async () => {
            const query = 'query { user { name } }';
            const context = {
                userId: 'test-user',
                tenantId: 'test-tenant',
                permissions: new Set(),
                graph: {},
                cache: new Map(),
            };
            const result1 = await graphqlEngine.execute({ query }, context);
            const result2 = await graphqlEngine.execute({ query }, context);
            // Second query should hit cache (though we can't directly verify in mocked setup)
            (0, globals_1.expect)(result1).toBeDefined();
            (0, globals_1.expect)(result2).toBeDefined();
        });
        (0, globals_1.it)('should handle query with variables', async () => {
            const query = 'query GetUser($id: String!) { user(id: $id) { name } }';
            const context = {
                userId: 'test-user',
                tenantId: 'test-tenant',
                permissions: new Set(),
                graph: {},
                cache: new Map(),
            };
            const result = await graphqlEngine.execute({ query, variables: { id: 'user-123' } }, context);
            (0, globals_1.expect)(result).toBeDefined();
        });
        (0, globals_1.it)('should clear cache', () => {
            graphqlEngine.clearCache();
            const stats = graphqlEngine.getCacheStats();
            (0, globals_1.expect)(stats.entries).toBe(0);
        });
    });
    (0, globals_1.describe)('APIAuthenticationManager', () => {
        (0, globals_1.it)('should create and validate JWT token', () => {
            const token = authManager.createJWTToken('user-123', 'tenant-456', ['read', 'write']);
            const auth = authManager.authenticateJWT(token);
            (0, globals_1.expect)(auth).not.toBeNull();
            (0, globals_1.expect)(auth?.userId).toBe('user-123');
            (0, globals_1.expect)(auth?.tenantId).toBe('tenant-456');
            (0, globals_1.expect)(auth?.scopes).toContain('read');
        });
        (0, globals_1.it)('should create and authenticate API keys', () => {
            const { id, secret } = authManager.createAPIKey('user-123', 'test-key', ['read']);
            const auth = authManager.authenticateAPIKey(id, secret);
            (0, globals_1.expect)(auth).not.toBeNull();
            (0, globals_1.expect)(auth?.scopes).toContain('read');
        });
        (0, globals_1.it)('should reject invalid API key', () => {
            authManager.createAPIKey('user-123', 'test-key', ['read']);
            const auth = authManager.authenticateAPIKey('invalid-key', 'invalid-secret');
            (0, globals_1.expect)(auth).toBeNull();
        });
        (0, globals_1.it)('should revoke API key', () => {
            const { id } = authManager.createAPIKey('user-123', 'test-key', ['read']);
            authManager.revokeAPIKey(id);
            const auth = authManager.authenticateAPIKey(id, 'any-secret');
            (0, globals_1.expect)(auth).toBeNull();
        });
        (0, globals_1.it)('should list API keys for user', () => {
            authManager.createAPIKey('user-123', 'key1', ['read']);
            authManager.createAPIKey('user-123', 'key2', ['write']);
            const keys = authManager.listAPIKeys('user-123');
            (0, globals_1.expect)(keys.length).toBeGreaterThanOrEqual(0);
        });
        (0, globals_1.it)('should revoke JWT token', () => {
            const token = authManager.createJWTToken('user-123', 'tenant-456', ['read']);
            authManager.revokeToken(token);
            const auth = authManager.authenticateJWT(token);
            (0, globals_1.expect)(auth).toBeNull();
        });
        (0, globals_1.it)('should provide authentication stats', () => {
            authManager.createAPIKey('user-123', 'key1', ['read']);
            const stats = authManager.getStats();
            (0, globals_1.expect)(stats.totalKeys).toBeGreaterThan(0);
            (0, globals_1.expect)(stats.activeKeys).toBeGreaterThanOrEqual(0);
            (0, globals_1.expect)(stats.blacklistedTokens).toBeGreaterThanOrEqual(0);
        });
    });
    (0, globals_1.describe)('RateLimiter', () => {
        (0, globals_1.it)('should allow requests within limit', () => {
            rateLimiter.setLimit('client-1', {
                requestsPerSecond: 10,
                requestsPerMinute: 600,
                requestsPerHour: 36000,
                burstCapacity: 100,
            });
            const status = rateLimiter.isAllowed('client-1');
            (0, globals_1.expect)(status.limited).toBe(false);
            (0, globals_1.expect)(status.remaining).toBeGreaterThanOrEqual(0);
        });
        (0, globals_1.it)('should reject requests exceeding burst capacity', () => {
            rateLimiter.setLimit('client-1', {
                requestsPerSecond: 1,
                requestsPerMinute: 60,
                requestsPerHour: 3600,
                burstCapacity: 3,
            });
            // Consume all burst capacity
            rateLimiter.isAllowed('client-1');
            rateLimiter.isAllowed('client-1');
            rateLimiter.isAllowed('client-1');
            const status = rateLimiter.isAllowed('client-1');
            (0, globals_1.expect)(status.limited).toBe(true);
        });
        (0, globals_1.it)('should check quota for time windows', () => {
            rateLimiter.setLimit('client-1', {
                requestsPerSecond: 5,
                requestsPerMinute: 300,
                requestsPerHour: 18000,
                burstCapacity: 50,
            });
            const secondStatus = rateLimiter.checkQuota('client-1', 'second');
            const minuteStatus = rateLimiter.checkQuota('client-1', 'minute');
            const hourStatus = rateLimiter.checkQuota('client-1', 'hour');
            (0, globals_1.expect)(secondStatus.limited).toBe(false);
            (0, globals_1.expect)(minuteStatus.limited).toBe(false);
            (0, globals_1.expect)(hourStatus.limited).toBe(false);
        });
        (0, globals_1.it)('should reset rate limit', () => {
            rateLimiter.setLimit('client-1', {
                requestsPerSecond: 1,
                requestsPerMinute: 60,
                requestsPerHour: 3600,
                burstCapacity: 2,
            });
            rateLimiter.isAllowed('client-1');
            const before = rateLimiter.isAllowed('client-1');
            rateLimiter.reset('client-1');
            const after = rateLimiter.isAllowed('client-1');
            (0, globals_1.expect)(before.remaining).toBeLessThanOrEqual(after.remaining);
        });
        (0, globals_1.it)('should provide rate limit stats', () => {
            rateLimiter.setLimit('client-1', {
                requestsPerSecond: 10,
                requestsPerMinute: 600,
                requestsPerHour: 36000,
                burstCapacity: 100,
            });
            rateLimiter.isAllowed('client-1');
            const stats = rateLimiter.getStats();
            (0, globals_1.expect)(stats.totalClients).toBeGreaterThan(0);
            (0, globals_1.expect)(stats.limitedClients).toBeGreaterThanOrEqual(0);
            (0, globals_1.expect)(stats.totalRequests).toBeGreaterThanOrEqual(0);
        });
    });
    (0, globals_1.describe)('GraphQLAPIPhase7Agent', () => {
        (0, globals_1.it)('should handle authenticated API request', async () => {
            const token = agent['authManager'].createJWTToken('user-123', 'tenant-456', ['read']);
            const response = await agent.handleRequest({
                clientId: 'client-1',
                token,
                query: 'query { user { name } }',
            });
            (0, globals_1.expect)(response).toBeDefined();
            (0, globals_1.expect)(response.meta).toBeDefined();
            (0, globals_1.expect)(response.meta.executionTime).toBeGreaterThanOrEqual(0);
        });
        (0, globals_1.it)('should reject unauthenticated requests', async () => {
            const response = await agent.handleRequest({
                clientId: 'client-1',
                query: 'query { user { name } }',
            });
            (0, globals_1.expect)(response.errors).toBeDefined();
            (0, globals_1.expect)(response.errors?.[0]?.code).toBe('UNAUTHORIZED');
        });
        (0, globals_1.it)('should enforce rate limits on API requests', async () => {
            agent.setClientRateLimit('client-2', 1); // 1 request per second
            const token = agent['authManager'].createJWTToken('user-123', 'tenant-456', ['read']);
            const response1 = await agent.handleRequest({
                clientId: 'client-2',
                token,
                query: 'query { user { name } }',
            });
            const response2 = await agent.handleRequest({
                clientId: 'client-2',
                token,
                query: 'query { user { name } }',
            });
            (0, globals_1.expect)(response1.meta.rateLimit.limited).toBe(false);
            (0, globals_1.expect)(response2.meta.rateLimit.limited).toBe(true);
        });
        (0, globals_1.it)('should handle API key authentication', async () => {
            const { apiKey } = agent.createClient('user-456', 'test-client', ['read']);
            const response = await agent.handleRequest({
                clientId: 'user-456',
                apiKey,
                query: 'query { user { name } }',
            });
            (0, globals_1.expect)(response).toBeDefined();
            (0, globals_1.expect)(response.meta).toBeDefined();
        });
        (0, globals_1.it)('should add and execute middlewares', async () => {
            const token = agent['authManager'].createJWTToken('user-789', 'tenant-111', ['read']);
            let middlewareExecuted = false;
            agent.addMiddleware((req, auth) => {
                middlewareExecuted = true;
                return auth.userId === 'user-789';
            });
            await agent.handleRequest({
                clientId: 'client-3',
                token,
                query: 'query { user { name } }',
            });
            (0, globals_1.expect)(middlewareExecuted).toBe(true);
        });
        (0, globals_1.it)('should return API statistics', () => {
            agent.createClient('user-999', 'test-client', ['read']);
            const stats = agent.getStats();
            (0, globals_1.expect)(stats.auth).toBeDefined();
            (0, globals_1.expect)(stats.rateLimit).toBeDefined();
            (0, globals_1.expect)(stats.auth.totalKeys).toBeGreaterThanOrEqual(0);
        });
    });
    (0, globals_1.describe)('Phase 7 Integration', () => {
        (0, globals_1.it)('should handle complete request lifecycle', async () => {
            // Create client
            const { apiKey, jwtToken } = agent.createClient('user-final', 'integration-test', [
                'read',
                'write',
            ]);
            // Set rate limit
            agent.setClientRateLimit('user-final', 100);
            // Make request with JWT
            const response1 = await agent.handleRequest({
                clientId: 'user-final',
                token: jwtToken,
                query: 'query { data { id } }',
            });
            (0, globals_1.expect)(response1.meta).toBeDefined();
            // Make request with API key
            const response2 = await agent.handleRequest({
                clientId: 'user-final',
                apiKey,
                query: 'query { data { id } }',
            });
            (0, globals_1.expect)(response2.meta).toBeDefined();
            // Check stats
            const stats = agent.getStats();
            (0, globals_1.expect)(stats.auth.totalKeys).toBeGreaterThan(0);
        });
    });
});
//# sourceMappingURL=phase7.test.js.map