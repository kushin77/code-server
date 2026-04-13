/**
 * Phase 7: Advanced API & Query Engine
 * GraphQL Query Engine for knowledge graphs
 */
export interface GraphQLQuery {
    query: string;
    variables?: Record<string, any>;
    operationName?: string;
}
export interface GraphQLResult {
    data?: any;
    errors?: GraphQLError[];
    extensions?: {
        executionTime: number;
        cacheHit: boolean;
        resultSize: number;
    };
}
export interface GraphQLError {
    message: string;
    path?: (string | number)[];
    extensions?: {
        code: string;
        [key: string]: any;
    };
}
export interface ResolverContext {
    userId: string;
    tenantId: string;
    permissions: Set<string>;
    graph: any;
    cache: Map<string, any>;
}
/**
 * GraphQL Query Engine for knowledge graph queries
 */
export declare class GraphQLQueryEngine {
    private schema;
    private resolvers;
    private queryCache;
    private cacheMaxAge;
    constructor(schema: any, resolvers?: any);
    /**
     * Execute GraphQL query
     */
    execute(query: GraphQLQuery, context: ResolverContext): Promise<GraphQLResult>;
    /**
     * Parse GraphQL query string
     */
    private parseQuery;
    /**
     * Validate query against schema
     */
    private validateQuery;
    /**
     * Execute parsed query
     */
    private executeQuery;
    /**
     * Generate cache key from query
     */
    private generateCacheKey;
    /**
     * Extract operation name from query
     */
    private extractOperationName;
    /**
     * Extract fields from query
     */
    private extractFields;
    /**
     * Extract variables from query
     */
    private extractVariables;
    /**
     * Check if schema has field
     */
    private schemaHasField;
    /**
     * Get required permissions for field
     */
    private getRequiredPermissions;
    /**
     * Check if user has required permissions
     */
    private hasPermissions;
    /**
     * Clear cache
     */
    clearCache(): void;
    /**
     * Get cache statistics
     */
    getCacheStats(): {
        size: number;
        entries: number;
    };
}
export default GraphQLQueryEngine;
//# sourceMappingURL=GraphQLQueryEngine.d.ts.map