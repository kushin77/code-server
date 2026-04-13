"use strict";
/**
 * Phase 7: Advanced API & Query Engine Agent
 * Orchestrates GraphQL queries, authentication, and rate limiting
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.GraphQLAPIPhase7Agent = void 0;
const phases_1 = require("../phases");
const GraphQLQueryEngine_1 = require("../ml/GraphQLQueryEngine");
const APIAuthenticationManager_1 = require("../ml/APIAuthenticationManager");
const RateLimiter_1 = require("../ml/RateLimiter");
class GraphQLAPIPhase7Agent extends phases_1.Agent {
    constructor(context, jwtSecret = 'dev-secret') {
        super('GraphQLAPIPhase7Agent', context);
        this.graphqlEngine = new GraphQLQueryEngine_1.GraphQLQueryEngine({}, {});
        this.authManager = new APIAuthenticationManager_1.APIAuthenticationManager(jwtSecret);
        this.rateLimiter = new RateLimiter_1.RateLimiter();
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
    async handleRequest(request) {
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
            let authPayload = null;
            if (request.token) {
                authPayload = this.authManager.authenticateJWT(request.token);
            }
            else if (request.apiKey) {
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
            const graphqlResult = await this.graphqlEngine.execute({ query: request.query, variables: request.variables }, context);
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
        }
        catch (error) {
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
    addMiddleware(middleware) {
        this.middlewares.push(middleware);
    }
    /**
     * Create new API client with credentials
     */
    createClient(clientId, name, scopes) {
        const { id, secret } = this.authManager.createAPIKey(clientId, name, scopes);
        const jwtToken = this.authManager.createJWTToken(clientId, '', scopes);
        return { apiKey: { id, secret }, jwtToken };
    }
    /**
     * Revoke client credentials
     */
    revokeClient(clientId, keyId) {
        return this.authManager.revokeAPIKey(keyId);
    }
    /**
     * Get API statistics
     */
    getStats() {
        return {
            auth: this.authManager.getStats(),
            rateLimit: this.rateLimiter.getStats(),
        };
    }
    /**
     * Set rate limit for client
     */
    setClientRateLimit(clientId, requestsPerSecond) {
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
    async execute(input) {
        const request = {
            clientId: input.clientId || 'unknown',
            token: input.token,
            apiKey: input.apiKey,
            query: input.query || '',
            variables: input.variables,
        };
        return this.handleRequest(request);
    }
}
exports.GraphQLAPIPhase7Agent = GraphQLAPIPhase7Agent;
exports.default = GraphQLAPIPhase7Agent;
//# sourceMappingURL=GraphQLAPIPhase7Agent.js.map