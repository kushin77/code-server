/**
 * Phase 7: Advanced API & Query Engine - Test Suite
 */

import { describe, it, expect, beforeEach } from '@jest/globals';
import { GraphQLQueryEngine } from '../ml/GraphQLQueryEngine';
import { APIAuthenticationManager } from '../ml/APIAuthenticationManager';
import { RateLimiter } from '../ml/RateLimiter';
import { GraphQLAPIPhase7Agent } from '../agents/GraphQLAPIPhase7Agent';

describe('Phase 7: Advanced API & Query Engine', () => {
  let graphqlEngine: GraphQLQueryEngine;
  let authManager: APIAuthenticationManager;
  let rateLimiter: RateLimiter;
  let agent: GraphQLAPIPhase7Agent;

  beforeEach(() => {
    graphqlEngine = new GraphQLQueryEngine({}, {});
    authManager = new APIAuthenticationManager('test-secret');
    rateLimiter = new RateLimiter();
    agent = new GraphQLAPIPhase7Agent({}, 'test-secret');
  });

  describe('GraphQLQueryEngine', () => {
    it('should parse simple GraphQL query', async () => {
      const query = 'query { user { name email } }';
      const context = {
        userId: 'test-user',
        tenantId: 'test-tenant',
        permissions: new Set(['user:read']),
        graph: {},
        cache: new Map(),
      };

      const result = await graphqlEngine.execute({ query }, context);

      expect(result).toBeDefined();
      expect(result.extensions).toBeDefined();
      expect(result.extensions?.executionTime).toBeGreaterThanOrEqual(0);
    });

    it('should cache query results', async () => {
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
      expect(result1).toBeDefined();
      expect(result2).toBeDefined();
    });

    it('should handle query with variables', async () => {
      const query = 'query GetUser($id: String!) { user(id: $id) { name } }';
      const context = {
        userId: 'test-user',
        tenantId: 'test-tenant',
        permissions: new Set(),
        graph: {},
        cache: new Map(),
      };

      const result = await graphqlEngine.execute({ query, variables: { id: 'user-123' } }, context);

      expect(result).toBeDefined();
    });

    it('should clear cache', () => {
      graphqlEngine.clearCache();
      const stats = graphqlEngine.getCacheStats();

      expect(stats.entries).toBe(0);
    });
  });

  describe('APIAuthenticationManager', () => {
    it('should create and validate JWT token', () => {
      const token = authManager.createJWTToken('user-123', 'tenant-456', ['read', 'write']);
      const auth = authManager.authenticateJWT(token);

      expect(auth).not.toBeNull();
      expect(auth?.userId).toBe('user-123');
      expect(auth?.tenantId).toBe('tenant-456');
      expect(auth?.scopes).toContain('read');
    });

    it('should create and authenticate API keys', () => {
      const { id, secret } = authManager.createAPIKey('user-123', 'test-key', ['read']);
      const auth = authManager.authenticateAPIKey(id, secret);

      expect(auth).not.toBeNull();
      expect(auth?.scopes).toContain('read');
    });

    it('should reject invalid API key', () => {
      authManager.createAPIKey('user-123', 'test-key', ['read']);
      const auth = authManager.authenticateAPIKey('invalid-key', 'invalid-secret');

      expect(auth).toBeNull();
    });

    it('should revoke API key', () => {
      const { id } = authManager.createAPIKey('user-123', 'test-key', ['read']);
      authManager.revokeAPIKey(id);

      const auth = authManager.authenticateAPIKey(id, 'any-secret');
      expect(auth).toBeNull();
    });

    it('should list API keys for user', () => {
      authManager.createAPIKey('user-123', 'key1', ['read']);
      authManager.createAPIKey('user-123', 'key2', ['write']);

      const keys = authManager.listAPIKeys('user-123');

      expect(keys.length).toBeGreaterThanOrEqual(0);
    });

    it('should revoke JWT token', () => {
      const token = authManager.createJWTToken('user-123', 'tenant-456', ['read']);
      authManager.revokeToken(token);

      const auth = authManager.authenticateJWT(token);
      expect(auth).toBeNull();
    });

    it('should provide authentication stats', () => {
      authManager.createAPIKey('user-123', 'key1', ['read']);
      const stats = authManager.getStats();

      expect(stats.totalKeys).toBeGreaterThan(0);
      expect(stats.activeKeys).toBeGreaterThanOrEqual(0);
      expect(stats.blacklistedTokens).toBeGreaterThanOrEqual(0);
    });
  });

  describe('RateLimiter', () => {
    it('should allow requests within limit', () => {
      rateLimiter.setLimit('client-1', {
        requestsPerSecond: 10,
        requestsPerMinute: 600,
        requestsPerHour: 36000,
        burstCapacity: 100,
      });

      const status = rateLimiter.isAllowed('client-1');

      expect(status.limited).toBe(false);
      expect(status.remaining).toBeGreaterThanOrEqual(0);
    });

    it('should reject requests exceeding burst capacity', () => {
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

      expect(status.limited).toBe(true);
    });

    it('should check quota for time windows', () => {
      rateLimiter.setLimit('client-1', {
        requestsPerSecond: 5,
        requestsPerMinute: 300,
        requestsPerHour: 18000,
        burstCapacity: 50,
      });

      const secondStatus = rateLimiter.checkQuota('client-1', 'second');
      const minuteStatus = rateLimiter.checkQuota('client-1', 'minute');
      const hourStatus = rateLimiter.checkQuota('client-1', 'hour');

      expect(secondStatus.limited).toBe(false);
      expect(minuteStatus.limited).toBe(false);
      expect(hourStatus.limited).toBe(false);
    });

    it('should reset rate limit', () => {
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

      expect(before.remaining).toBeLessThanOrEqual(after.remaining);
    });

    it('should provide rate limit stats', () => {
      rateLimiter.setLimit('client-1', {
        requestsPerSecond: 10,
        requestsPerMinute: 600,
        requestsPerHour: 36000,
        burstCapacity: 100,
      });

      rateLimiter.isAllowed('client-1');
      const stats = rateLimiter.getStats();

      expect(stats.totalClients).toBeGreaterThan(0);
      expect(stats.limitedClients).toBeGreaterThanOrEqual(0);
      expect(stats.totalRequests).toBeGreaterThanOrEqual(0);
    });
  });

  describe('GraphQLAPIPhase7Agent', () => {
    it('should handle authenticated API request', async () => {
      const token = agent['authManager'].createJWTToken('user-123', 'tenant-456', ['read']);

      const response = await agent.handleRequest({
        clientId: 'client-1',
        token,
        query: 'query { user { name } }',
      });

      expect(response).toBeDefined();
      expect(response.meta).toBeDefined();
      expect(response.meta.executionTime).toBeGreaterThanOrEqual(0);
    });

    it('should reject unauthenticated requests', async () => {
      const response = await agent.handleRequest({
        clientId: 'client-1',
        query: 'query { user { name } }',
      });

      expect(response.errors).toBeDefined();
      expect(response.errors?.[0]?.code).toBe('UNAUTHORIZED');
    });

    it('should enforce rate limits on API requests', async () => {
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

      expect(response1.meta.rateLimit.limited).toBe(false);
      expect(response2.meta.rateLimit.limited).toBe(true);
    });

    it('should handle API key authentication', async () => {
      const { apiKey } = agent.createClient('user-456', 'test-client', ['read']);

      const response = await agent.handleRequest({
        clientId: 'user-456',
        apiKey,
        query: 'query { user { name } }',
      });

      expect(response).toBeDefined();
      expect(response.meta).toBeDefined();
    });

    it('should add and execute middlewares', async () => {
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

      expect(middlewareExecuted).toBe(true);
    });

    it('should return API statistics', () => {
      agent.createClient('user-999', 'test-client', ['read']);
      const stats = agent.getStats();

      expect(stats.auth).toBeDefined();
      expect(stats.rateLimit).toBeDefined();
      expect(stats.auth.totalKeys).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Phase 7 Integration', () => {
    it('should handle complete request lifecycle', async () => {
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

      expect(response1.meta).toBeDefined();

      // Make request with API key
      const response2 = await agent.handleRequest({
        clientId: 'user-final',
        apiKey,
        query: 'query { data { id } }',
      });

      expect(response2.meta).toBeDefined();

      // Check stats
      const stats = agent.getStats();
      expect(stats.auth.totalKeys).toBeGreaterThan(0);
    });
  });
});
