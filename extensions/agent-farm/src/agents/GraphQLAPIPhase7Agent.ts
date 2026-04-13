/**
 * Phase 7: Advanced API & Query Engine Agent
 * Orchestrates GraphQL queries, authentication, and rate limiting
 */

import { Agent } from '../phases';
import { GraphQLQueryEngine, GraphQLResult } from '../ml/GraphQLQueryEngine';
import { APIAuthenticationManager, AuthPayload } from '../ml/APIAuthenticationManager';
import { RateLimiter, RateLimitStatus } from '../ml/RateLimiter';

export interface APIRequest {
  clientId: string;
  token?: string;
  apiKey?: { id: string; secret: string };
  query: string;
  variables?: Record<string, any>;
}

export interface APIResponse {
  data?: any;
  errors?: Array<{ message: string; code: string }>;
  meta: {
    executionTime: number;
    rateLimit: RateLimitStatus;
    cached: boolean;
  };
}

export class GraphQLAPIPhase7Agent extends Agent {
  private graphqlEngine: GraphQLQueryEngine;
  private authManager: APIAuthenticationManager;
  private rateLimiter: RateLimiter;
  private middlewares: Array<(req: APIRequest, auth: AuthPayload) => boolean | Promise<boolean>>;

  constructor(context: any, jwtSecret: string = 'dev-secret') {
    super('GraphQLAPIPhase7Agent', context);
    this.graphqlEngine = new GraphQLQueryEngine({}, {});
    this.authManager = new APIAuthenticationManager(jwtSecret);
    this.rateLimiter = new RateLimiter();
    this.middlewares = [];

    // Set default rate limits
    this.rateLimiter.setLimit('default', {
      requestsPerSecond: 10,
      requestsPerMinute: 600,
      requestsPerHour: 36000,
      burstCapacity: 100,
    });
  }

  /**
   * Handle API request with authentication and rate limiting
   */
  async handleRequest(request: APIRequest): Promise<APIResponse> {
    const startTime = performance.now();

    try {
      // Check rate limit
      const rateLimitStatus = this.rateLimiter.isAllowed(request.clientId);
      if (rateLimitStatus.limited) {
        return {
          errors: [{ message: 'Rate limit exceeded', code: 'RATE_LIMIT_EXCEEDED' }],
          meta: {
            executionTime: performance.now() - startTime,
            rateLimit: rateLimitStatus,
            cached: false,
          },
        };
      }

      // Authenticate request
      let authPayload: AuthPayload | null = null;

      if (request.token) {
        authPayload = this.authManager.authenticateJWT(request.token);
      } else if (request.apiKey) {
        authPayload = this.authManager.authenticateAPIKey(request.apiKey.id, request.apiKey.secret);
      }

      if (!authPayload) {
        return {
          errors: [{ message: 'Unauthorized', code: 'UNAUTHORIZED' }],
          meta: {
            executionTime: performance.now() - startTime,
            rateLimit: rateLimitStatus,
            cached: false,
          },
        };
      }

      // Run middlewares
      for (const middleware of this.middlewares) {
        const allowed = await middleware(request, authPayload);
        if (!allowed) {
          return {
            errors: [{ message: 'Middleware validation failed', code: 'FORBIDDEN' }],
            meta: {
              executionTime: performance.now() - startTime,
              rateLimit: rateLimitStatus,
              cached: false,
            },
          };
        }
      }

      // Execute GraphQL query
      const context = {
        userId: authPayload.userId || '',
        tenantId: authPayload.tenantId || '',
        permissions: new Set(authPayload.scopes),
        graph: this.context.graph || {},
        cache: new Map(),
      };

      const graphqlResult: GraphQLResult = await this.graphqlEngine.execute(
        { query: request.query, variables: request.variables },
        context
      );

      return {
        data: graphqlResult.data,
        errors: graphqlResult.errors?.map((e) => ({
          message: e.message,
          code: e.extensions?.code || 'GRAPHQL_ERROR',
        })),
        meta: {
          executionTime: graphqlResult.extensions?.executionTime || 0,
          rateLimit: rateLimitStatus,
          cached: graphqlResult.extensions?.cacheHit || false,
        },
      };
    } catch (error) {
      return {
        errors: [
          {
            message: error instanceof Error ? error.message : 'Internal server error',
            code: 'INTERNAL_ERROR',
          },
        ],
        meta: {
          executionTime: performance.now() - startTime,
          rateLimit: this.rateLimiter.checkQuota(request.clientId, 'second'),
          cached: false,
        },
      };
    }
  }

  /**
   * Add middleware for custom validation
   */
  addMiddleware(middleware: (req: APIRequest, auth: AuthPayload) => boolean | Promise<boolean>): void {
    this.middlewares.push(middleware);
  }

  /**
   * Create new API client with credentials
   */
  createClient(
    clientId: string,
    name: string,
    scopes: string[]
  ): { apiKey: { id: string; secret: string }; jwtToken: string } {
    const { id, secret } = this.authManager.createAPIKey(clientId, name, scopes);
    const jwtToken = this.authManager.createJWTToken(clientId, '', scopes);

    return { apiKey: { id, secret }, jwtToken };
  }

  /**
   * Revoke client credentials
   */
  revokeClient(clientId: string, keyId: string): boolean {
    return this.authManager.revokeAPIKey(keyId);
  }

  /**
   * Get API statistics
   */
  getStats(): {
    auth: { totalKeys: number; activeKeys: number; blacklistedTokens: number };
    rateLimit: { totalClients: number; limitedClients: number; totalRequests: number };
  } {
    return {
      auth: this.authManager.getStats(),
      rateLimit: this.rateLimiter.getStats(),
    };
  }

  /**
   * Set rate limit for client
   */
  setClientRateLimit(clientId: string, requestsPerSecond: number): void {
    this.rateLimiter.setLimit(clientId, {
      requestsPerSecond,
      requestsPerMinute: requestsPerSecond * 60,
      requestsPerHour: requestsPerSecond * 3600,
      burstCapacity: requestsPerSecond * 10,
    });
  }

  /**
   * Execute Phase 7 Agent
   */
  async execute(input: any): Promise<APIResponse> {
    const request: APIRequest = {
      clientId: input.clientId || 'unknown',
      token: input.token,
      apiKey: input.apiKey,
      query: input.query || '',
      variables: input.variables,
    };

    return this.handleRequest(request);
  }
}

export default GraphQLAPIPhase7Agent;
