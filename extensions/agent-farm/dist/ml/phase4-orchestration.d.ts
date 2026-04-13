/**
 * Phase 4B: Advanced Semantic Search - Orchestration and Composition
 * Orchestrates QueryUnderstanding, CrossEncoderReranker, and MultiModalAnalyzer
 */
import { ExpandedQuery } from './QueryUnderstanding';
export interface SearchResult {
    filePath?: string;
    content?: string;
    score?: number;
}
export interface Phase4BSearchOptions {
    includeMultiModal: boolean;
    rerankerWeight: number;
    constraintFiltering: boolean;
    maxResults: number;
}
export interface EnhancedSearchResult extends SearchResult {
    expandedQuery?: ExpandedQuery;
    multiModalScore?: any;
    rerankerScore?: number;
    combinedScore?: number;
    reasoning?: string;
}
/**
 * Advanced Semantic Search Orchestrator
 * Coordinates Phase 4B components: QueryUnderstanding, CrossEncoderReranking, MultiModalAnalysis
 */
export declare class AdvancedSemanticSearchOrchestrator {
    private queryUnderstanding;
    private crossEncoderReranker;
    private multiModalAnalyzer;
    constructor();
    /**
     * Execute advanced semantic search pipeline
     */
    advancedSearch(query: string, results: SearchResult[], options?: Partial<Phase4BSearchOptions>): Promise<EnhancedSearchResult[]>;
    /**
     * Apply query constraints to filter results
     */
    private applyConstraints;
    /**
     * Enhance results with multi-modal analysis
     */
    private enhanceWithMultiModal;
    /**
     * Combine scores from multiple components
     */
    private combineScores;
    /**
     * Generate human-readable reasoning for ranking
     */
    private generateReasoning;
    /**
     * Get analysis summary for results
     */
    getSummary(results: EnhancedSearchResult[]): {
        topResult: EnhancedSearchResult | null;
        avgScore: number;
        modalities: string[];
    };
}
//# sourceMappingURL=phase4-orchestration.d.ts.map