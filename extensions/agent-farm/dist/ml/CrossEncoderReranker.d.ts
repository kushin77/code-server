/**
 * Phase 4B: Advanced ML Semantic Search
 * CrossEncoderReranker - Advanced result re-ranking using learned patterns
 */
import { SearchResult } from './RelevanceRanker';
import { QueryIntent } from './QueryUnderstanding';
export interface RankingFeatures {
    semanticSimilarity: number;
    syntacticSimilarity: number;
    tokenOverlap: number;
    fileRelevance: number;
    recency: number;
    popularity: number;
    codeQuality: number;
    testCoverage: number;
}
export interface CrossEncodedResult {
    result: SearchResult;
    features: RankingFeatures;
    score: number;
    reasoning: string;
}
export declare class CrossEncoderReranker {
    private weights;
    /**
     * Extract ranking features from a search result
     */
    extractFeatures(result: SearchResult, queryIntent: QueryIntent, allResults: SearchResult[]): RankingFeatures;
    /**
     * Calculate composite score using learned weights
     */
    scoreFeatures(features: RankingFeatures): number;
    /**
     * Re-rank results using cross-encoder logic
     */
    rerank(results: SearchResult[], queryIntent: QueryIntent): CrossEncodedResult[];
    /**
     * Calculate syntax similarity for specific intent
     */
    private calculateSyntacticSimilarity;
    /**
     * Calculate file relevance based on path and intent
     */
    private calculateFileRelevance;
    /**
     * Estimate code quality from patterns
     */
    private estimateCodeQuality;
    /**
     * Estimate test coverage from file indicators
     */
    private estimateTestCoverage;
    /**
     * Generate human-readable reasoning for the score
     */
    private generateReasoning;
    /**
     * Adjust weights based on intent (for domain-specific ranking)
     */
    adjustWeightsForIntent(intent: QueryIntent): void;
    /**
     * Reset weights to defaults
     */
    private resetWeights;
}
//# sourceMappingURL=CrossEncoderReranker.d.ts.map