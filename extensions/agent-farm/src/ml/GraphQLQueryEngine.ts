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
  graph: any; // KnowledgeGraph reference
  cache: Map<string, any>;
}

/**
 * GraphQL Query Engine for knowledge graph queries
 */
export class GraphQLQueryEngine {
  private schema: any;
  private resolvers: Map<string, any>;
  private queryCache: Map<string, { result: any; timestamp: number }>;
  private cacheMaxAge = 5 * 60 * 1000; // 5 minutes

  constructor(schema: any, resolvers: any = {}) {
    this.schema = schema;
    this.resolvers = new Map(Object.entries(resolvers));
    this.queryCache = new Map();
  }

  /**
   * Execute GraphQL query
   */
  async execute(query: GraphQLQuery, context: ResolverContext): Promise<GraphQLResult> {
    const startTime = performance.now();

    // Check cache
    const cacheKey = this.generateCacheKey(query);
    const cached = this.queryCache.get(cacheKey);
    if (cached && Date.now() - cached.timestamp < this.cacheMaxAge) {
      return {
        data: cached.result,
        extensions: {
          executionTime: performance.now() - startTime,
          cacheHit: true,
          resultSize: JSON.stringify(cached.result).length,
        },
      };
    }

    try {
      // Parse query
      const parsed = this.parseQuery(query.query);

      // Validate against schema
      const validationErrors = this.validateQuery(parsed, this.schema);
      if (validationErrors.length > 0) {
        return {
          errors: validationErrors,
          extensions: { executionTime: performance.now() - startTime, cacheHit: false, resultSize: 0 },
        };
      }

      // Execute query
      const result = await this.executeQuery(parsed, query.variables || {}, context);

      // Cache result
      this.queryCache.set(cacheKey, {
        result,
        timestamp: Date.now(),
      });

      return {
        data: result,
        extensions: {
          executionTime: performance.now() - startTime,
          cacheHit: false,
          resultSize: JSON.stringify(result).length,
        },
      };
    } catch (error) {
      return {
        errors: [
          {
            message: error instanceof Error ? error.message : 'Unknown error',
            extensions: { code: 'INTERNAL_ERROR' },
          },
        ],
        extensions: { executionTime: performance.now() - startTime, cacheHit: false, resultSize: 0 },
      };
    }
  }

  /**
   * Parse GraphQL query string
   */
  private parseQuery(queryString: string): any {
    // Simple query parsing (in production, use GraphQL parser library)
    return {
      type: 'query',
      name: this.extractOperationName(queryString),
      fields: this.extractFields(queryString),
      variables: this.extractVariables(queryString),
    };
  }

  /**
   * Validate query against schema
   */
  private validateQuery(query: any, schema: any): GraphQLError[] {
    const errors: GraphQLError[] = [];

    // Check if query type exists
    if (!query.type) {
      errors.push({
        message: 'Query must have a type',
        extensions: { code: 'INVALID_QUERY' },
      });
    }

    // Validate fields against schema
    query.fields?.forEach((field: string) => {
      if (!this.schemaHasField(field, schema)) {
        errors.push({
          message: `Field '${field}' does not exist on schema`,
          path: [field],
          extensions: { code: 'FIELD_NOT_FOUND' },
        });
      }
    });

    return errors;
  }

  /**
   * Execute parsed query
   */
  private async executeQuery(parsed: any, variables: Record<string, any>, context: ResolverContext): Promise<any> {
    const result: Record<string, any> = {};

    for (const field of parsed.fields) {
      const resolver = this.resolvers.get(field);

      if (!resolver) {
        throw new Error(`No resolver for field: ${field}`);
      }

      // Check permissions
      const requiredPermissions = this.getRequiredPermissions(field);
      if (!this.hasPermissions(context.permissions, requiredPermissions)) {
        throw new Error(`Insufficient permissions for field: ${field}`);
      }

      result[field] = await resolver(context.graph, variables, context);
    }

    return result;
  }

  /**
   * Generate cache key from query
   */
  private generateCacheKey(query: GraphQLQuery): string {
    return `${query.query}:${JSON.stringify(query.variables || {})}`;
  }

  /**
   * Extract operation name from query
   */
  private extractOperationName(queryString: string): string {
    const match = queryString.match(/(?:query|mutation|subscription)\s+(\w+)/);
    return match ? match[1] : 'anonymous';
  }

  /**
   * Extract fields from query
   */
  private extractFields(queryString: string): string[] {
    const matches = queryString.match(/{\s*([^}]+)\s*}/);
    if (!matches) return [];
    return matches[1]
      .split('\n')
      .map((f) => f.trim())
      .filter((f) => f && !f.startsWith('__'))
      .map((f) => f.split('(')[0].trim());
  }

  /**
   * Extract variables from query
   */
  private extractVariables(queryString: string): Record<string, string> {
    const vars: Record<string, string> = {};
    const matches = queryString.match(/\$(\w+):\s*(\w+)/g);
    if (matches) {
      matches.forEach((match) => {
        const [name, type] = match.split(':').map((s) => s.trim());
        vars[name.substring(1)] = type;
      });
    }
    return vars;
  }

  /**
   * Check if schema has field
   */
  private schemaHasField(field: string, schema: any): boolean {
    return schema && schema.fields && (field in schema.fields);
  }

  /**
   * Get required permissions for field
   */
  private getRequiredPermissions(field: string): string[] {
    // Can be extended with metadata annotations
    return [];
  }

  /**
   * Check if user has required permissions
   */
  private hasPermissions(userPermissions: Set<string>, required: string[]): boolean {
    return required.length === 0 || required.every((p) => userPermissions.has(p));
  }

  /**
   * Clear cache
   */
  clearCache(): void {
    this.queryCache.clear();
  }

  /**
   * Get cache statistics
   */
  getCacheStats(): { size: number; entries: number } {
    return {
      size: new Map([...this.queryCache.entries()].map(([k, v]) => [k, JSON.stringify(v).length])).values(),
      entries: this.queryCache.size,
    };
  }
}

export default GraphQLQueryEngine;
