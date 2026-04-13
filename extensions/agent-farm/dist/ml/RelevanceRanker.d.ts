/**
 * Phase 4A: ML Semantic Search Foundation
 * RelevanceRanker - Rank search results by relevance
 */
export interface SearchResult {
    id: string;
    text: string;
    vector: number[];
    filePath: string;
    lineNumber?: number;
    similarity: number;
    relevanceScore: number;
    popularity?: number;
}
export interface RankingWeights {
    semanticSimilarity: number;
    syntacticSimilarity: number;
    tokenOverlap: number;
    recency: number;
    popularity: number;
}
export declare class RelevanceRanker {
    private defaultWeights;
    /**
     * Rank search results by relevance
     */
    rankResults(queryVector: number[], queryText: string, candidates: SearchResult[], weights?: Partial<RankingWeights>): SearchResult[];
    /**
     * Filter results by minimum threshold
     */
    filterByThreshold(results: SearchResult[], minScore?: number): SearchResult[];
    /**
     * Get top N results
     */
    getTopResults(results: SearchResult[], topN?: number): SearchResult[];
    /**
     * Combine multiple ranking strategies (ensemble)
     */
    ensembleRank(queryVector: number[], queryText: string, candidates: SearchResult[], strategies: Array<{
        weights: Partial<RankingWeights>;
        weight: number;
    }>): SearchResult[];
    /**
     * Boost results by file type or context
     */
    boostResults(results: SearchResult[], boostRules: Array<{
        pattern: RegExp;
        boost: number;
    }>): SearchResult[];
    /**
     * Diversify results to avoid clustering similar results
     */
    diversifyResults(results: SearchResult[], maxResult?: number, similarityThreshold?: number): SearchResult[];
    /**
     * Generate ranking explanation for a result
     */
    explainScore(result: SearchResult, queryVector: number[], queryText: string, weights?: Partial<RankingWeights>): {
        components: Record<string, number>;
        explanation: string;
    };
    /**
     * Set default ranking weights
     */
    setDefaultWeights(weights: Partial<RankingWeights>): void;
}
//# sourceMappingURL=RelevanceRanker.d.ts.map