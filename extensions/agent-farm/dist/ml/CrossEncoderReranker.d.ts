/**
 * Cross-Encoder Reranker Module
 * Reranks search results based on semantic relevance
 */
export interface RankedResult {
    id: string;
    content: string;
    score: number;
    metadata?: Record<string, any>;
}
export declare class CrossEncoderReranker {
    /**
     * Rerank results based on query-document relevance
     */
    rerank(query: string, results: Array<{
        id: string;
        content: string;
    }>): Promise<RankedResult[]>;
    /**
     * Calculate semantic similarity score
     */
    private calculateSimilarity;
}
//# sourceMappingURL=CrossEncoderReranker.d.ts.map