/**
 * Query Understanding Module
 * Handles semantic analysis and expansion of search queries
 */
export interface ExpandedQuery {
    original: string;
    expanded: string[];
    synonyms: string[];
    entities: string[];
    expandedTerms: string[];
    intent: 'search' | 'analyze' | 'review' | 'refactor' | 'test';
}
export declare class QueryUnderstanding {
    /**
     * Analyze query and expand with semantic variations
     */
    analyzeQuery(query: string): Promise<ExpandedQuery>;
    /**
     * Expand query with semantic terms
     */
    expandQuery(query: string): Promise<ExpandedQuery>;
    private extractEntities;
    private classifyIntent;
}
//# sourceMappingURL=QueryUnderstanding.d.ts.map