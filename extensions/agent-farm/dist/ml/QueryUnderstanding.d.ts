/**
 * Phase 4B: Advanced ML Semantic Search
 * QueryUnderstanding - Parse and expand natural language queries into code patterns
 */
export interface QueryIntent {
    type: 'search' | 'find' | 'analyze' | 'optimize' | 'refactor' | 'debug' | 'test';
    keywords: string[];
    entities: string[];
    constraints: QueryConstraint[];
}
export interface QueryConstraint {
    type: 'language' | 'complexity' | 'testCoverage' | 'performance' | 'size';
    operator: '==' | '!=' | '<' | '>' | '<=' | '>=';
    value: string | number;
}
export interface ExpandedQuery {
    original: string;
    intent: QueryIntent;
    synonyms: string[];
    patterns: string[];
    expandedTerms: string[];
}
export declare class QueryUnderstanding {
    private intentKeywords;
    private synonymMap;
    private codePatterns;
    /**
     * Understand a natural language query
     */
    understandQuery(query: string): QueryIntent;
    /**
     * Expand query with synonyms and related terms
     */
    expandQuery(query: string): ExpandedQuery;
    /**
     * Extract programming entities (classes, functions, variables, etc.)
     */
    private extractEntities;
    /**
     * Extract constraints from query (language, complexity, etc.)
     */
    private extractConstraints;
    /**
     * Extract main keywords from query
     */
    private extractKeywords;
    /**
     * Find synonyms for query terms
     */
    private findSynonyms;
    /**
     * Find relevant code patterns
     */
    private findCodePatterns;
    /**
     * Generate expanded terms for better matching
     */
    private generateExpandedTerms;
}
//# sourceMappingURL=QueryUnderstanding.d.ts.map
