/**
 * Phase 4A: ML Semantic Search Foundation
 * MLEmbeddingEngine - Generate code embeddings using Ollama LLM service
 */
export interface EmbeddingRequest {
    text: string;
    id?: string;
}
export interface EmbeddingResult {
    id: string;
    text: string;
    vector: number[];
    timestamp: number;
}
export interface EmbeddingCache {
    [key: string]: EmbeddingResult;
}
export declare class MLEmbeddingEngine {
    private ollamaEndpoint;
    private modelName;
    private cache;
    private batchSize;
    private cacheHits;
    private cacheMisses;
    constructor(ollamaEndpoint?: string);
    /**
     * Generate a single embedding for text
     */
    generateEmbedding(text: string, id?: string): Promise<EmbeddingResult>;
    /**
     * Generate embeddings for multiple texts in batches
     */
    generateBatchEmbeddings(texts: EmbeddingRequest[]): Promise<EmbeddingResult[]>;
    /**
     * Clear cache entries
     */
    clearCache(pattern?: RegExp): void;
    /**
     * Get cache statistics
     */
    getCacheStats(): {
        size: number;
        hitRate: number;
        totalRequests: number;
    };
    /**
     * Set Ollama model
     */
    setModel(modelName: string): void;
    /**
     * Generate cache key from text
     */
    private generateCacheKey;
    /**
     * Generate unique ID
     */
    private generateId;
}
//# sourceMappingURL=MLEmbeddingEngine.d.ts.map
