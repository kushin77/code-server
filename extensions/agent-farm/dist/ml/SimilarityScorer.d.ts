/**
 * Phase 4A: ML Semantic Search Foundation
 * SimilarityScorer - Calculate similarity between code embeddings
 */
export declare class SimilarityScorer {
    /**
     * Cosine similarity - measures angle between vectors
     * Range: -1 to 1 (1 = identical, 0 = orthogonal, -1 = opposite)
     * Best for: semantic similarity of embeddings
     */
    static cosineSimilarity(vectorA: number[], vectorB: number[]): number;
    /**
     * Euclidean distance - straight-line distance between points
     * Range: 0 to ∞ (0 = identical, smaller = more similar)
     * Best for: finding nearby points in vector space
     */
    static euclideanDistance(vectorA: number[], vectorB: number[]): number;
    /**
     * Jaro-Winkler similarity - string-based similarity
     * Range: 0 to 1 (1 = identical strings)
     * Best for: file names, variable names, type names
     */
    static jaroWinklerSimilarity(str1: string, str2: string): number;
    /**
     * Levenshtein distance - minimum edits to transform one string to another
     * Range: 0 to max(len(s1), len(s2))
     * Best for: fuzzy matching, typo detection
     */
    static levenshteinDistance(str1: string, str2: string): number;
    /**
     * Levenshtein similarity (normalized)
     * Range: 0 to 1 (1 = identical)
     */
    static levenshteinSimilarity(str1: string, str2: string): number;
    /**
     * Token overlap similarity - how many tokens match
     * Range: 0 to 1 (1 = all tokens match)
     * Best for: code pattern matching
     */
    static tokenOverlapSimilarity(text1: string, text2: string): number;
    /**
     * Hybrid similarity - weighted combination of multiple metrics
     */
    static hybridSimilarity(vectorA: number[], vectorB: number[], textA: string, textB: string, weights?: {
        cosine: number;
        tokenOverlap: number;
        levenshtein: number;
    }): number;
    /**
     * Helper: Calculate Jaro distance
     */
    private static jaroDistance;
    /**
     * Helper: Tokenize text
     */
    private static tokenize;
}
//# sourceMappingURL=SimilarityScorer.d.ts.map