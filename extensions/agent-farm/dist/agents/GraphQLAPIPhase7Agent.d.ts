/**
 * Phase 7: Advanced API & Query Engine Agent
 * Orchestrates GraphQL queries, authentication, and rate limiting
 */
import { Agent } from '../phases';
import { AuthPayload } from '../ml/APIAuthenticationManager';
import { RateLimitStatus } from '../ml/RateLimiter';
export interface APIRequest {
    clientId: string;
    token?: string;
    apiKey?: {
        id: string;
        secret: string;
    };
    query: string;
    variables?: Record<string, any>;
}
export interface APIResponse {
    data?: any;
    errors?: Array<{
        message: string;
        code: string;
    }>;
    meta: {
        executionTime: number;
        rateLimit: RateLimitStatus;
        cached: boolean;
    };
}
export declare class GraphQLAPIPhase7Agent extends Agent {
    private graphqlEngine;
    private authManager;
    private rateLimiter;
    private middlewares;
    constructor(context: any, jwtSecret?: string);
    /**
     * Handle API request with authentication and rate limiting
     */
    handleRequest(request: APIRequest): Promise<APIResponse>;
    /**
     * Add middleware for custom validation
     */
    addMiddleware(middleware: (req: APIRequest, auth: AuthPayload) => boolean | Promise<boolean>): void;
    /**
     * Create new API client with credentials
     */
    createClient(clientId: string, name: string, scopes: string[]): {
        apiKey: {
            id: string;
            secret: string;
        };
        jwtToken: string;
    };
    /**
     * Revoke client credentials
     */
    revokeClient(clientId: string, keyId: string): boolean;
    /**
     * Get API statistics
     */
    getStats(): {
        auth: {
            totalKeys: number;
            activeKeys: number;
            blacklistedTokens: number;
        };
        rateLimit: {
            totalClients: number;
            limitedClients: number;
            totalRequests: number;
        };
    };
    /**
     * Set rate limit for client
     */
    setClientRateLimit(clientId: string, requestsPerSecond: number): void;
    /**
     * Execute Phase 7 Agent
     */
    execute(input: any): Promise<APIResponse>;
}
export default GraphQLAPIPhase7Agent;
//# sourceMappingURL=GraphQLAPIPhase7Agent.d.ts.map
