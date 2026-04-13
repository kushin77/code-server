"use strict";
/**
 * Phase 4A: ML Semantic Search Foundation
 * SimilarityScorer - Calculate similarity between code embeddings
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.SimilarityScorer = void 0;
class SimilarityScorer {
    /**
     * Cosine similarity - measures angle between vectors
     * Range: -1 to 1 (1 = identical, 0 = orthogonal, -1 = opposite)
     * Best for: semantic similarity of embeddings
     */
    static cosineSimilarity(vectorA, vectorB) {
        if (vectorA.length !== vectorB.length) {
            throw new Error('Vectors must have same dimensions');
        }
        let dotProduct = 0;
        let normA = 0;
        let normB = 0;
        for (let i = 0; i < vectorA.length; i++) {
            dotProduct += vectorA[i] * vectorB[i];
            normA += vectorA[i] * vectorA[i];
            normB += vectorB[i] * vectorB[i];
        }
        const denominator = Math.sqrt(normA) * Math.sqrt(normB);
        if (denominator === 0) {
            return 0;
        }
        return dotProduct / denominator;
    }
    /**
     * Euclidean distance - straight-line distance between points
     * Range: 0 to ∞ (0 = identical, smaller = more similar)
     * Best for: finding nearby points in vector space
     */
    static euclideanDistance(vectorA, vectorB) {
        if (vectorA.length !== vectorB.length) {
            throw new Error('Vectors must have same dimensions');
        }
        let sumSquaredDiff = 0;
        for (let i = 0; i < vectorA.length; i++) {
            const diff = vectorA[i] - vectorB[i];
            sumSquaredDiff += diff * diff;
        }
        return Math.sqrt(sumSquaredDiff);
    }
    /**
     * Jaro-Winkler similarity - string-based similarity
     * Range: 0 to 1 (1 = identical strings)
     * Best for: file names, variable names, type names
     */
    static jaroWinklerSimilarity(str1, str2) {
        // Convert to lowercase for comparison
        const s1 = str1.toLowerCase();
        const s2 = str2.toLowerCase();
        if (s1 === s2)
            return 1;
        if (s1.length === 0 || s2.length === 0)
            return 0;
        // Calculate Jaro distance
        const jaroDistance = this.jaroDistance(s1, s2);
        // Apply Winkler modification
        // Give more weight to strings that match at the beginning
        let prefix = 0;
        for (let i = 0; i < Math.min(s1.length, s2.length, 4); i++) {
            if (s1[i] === s2[i]) {
                prefix++;
            }
            else {
                break;
            }
        }
        return jaroDistance + prefix * 0.1 * (1 - jaroDistance);
    }
    /**
     * Levenshtein distance - minimum edits to transform one string to another
     * Range: 0 to max(len(s1), len(s2))
     * Best for: fuzzy matching, typo detection
     */
    static levenshteinDistance(str1, str2) {
        const len1 = str1.length;
        const len2 = str2.length;
        // Create matrix
        const matrix = [];
        for (let i = 0; i <= len1; i++) {
            matrix[i] = [i];
        }
        for (let j = 0; j <= len2; j++) {
            matrix[0][j] = j;
        }
        // Fill matrix
        for (let i = 1; i <= len1; i++) {
            for (let j = 1; j <= len2; j++) {
                const cost = str1[i - 1] === str2[j - 1] ? 0 : 1;
                matrix[i][j] = Math.min(matrix[i - 1][j] + 1, // deletion
                matrix[i][j - 1] + 1, // insertion
                matrix[i - 1][j - 1] + cost // substitution
                );
            }
        }
        return matrix[len1][len2];
    }
    /**
     * Levenshtein similarity (normalized)
     * Range: 0 to 1 (1 = identical)
     */
    static levenshteinSimilarity(str1, str2) {
        const maxLen = Math.max(str1.length, str2.length);
        if (maxLen === 0)
            return 1;
        const distance = this.levenshteinDistance(str1, str2);
        return 1 - distance / maxLen;
    }
    /**
     * Token overlap similarity - how many tokens match
     * Range: 0 to 1 (1 = all tokens match)
     * Best for: code pattern matching
     */
    static tokenOverlapSimilarity(text1, text2) {
        // Tokenize (simple word/symbol splitting)
        const tokens1 = this.tokenize(text1);
        const tokens2 = this.tokenize(text2);
        if (tokens1.size === 0 && tokens2.size === 0)
            return 1;
        if (tokens1.size === 0 || tokens2.size === 0)
            return 0;
        // Find intersection
        const intersection = new Set([...tokens1].filter((token) => tokens2.has(token)));
        // Find union
        const union = new Set([...tokens1, ...tokens2]);
        return intersection.size / union.size;
    }
    /**
     * Hybrid similarity - weighted combination of multiple metrics
     */
    static hybridSimilarity(vectorA, vectorB, textA, textB, weights = { cosine: 0.5, tokenOverlap: 0.3, levenshtein: 0.2 }) {
        const cosine = this.cosineSimilarity(vectorA, vectorB);
        const tokenOverlap = this.tokenOverlapSimilarity(textA, textB);
        const levenshtein = this.levenshteinSimilarity(textA, textB);
        const total = weights.cosine + weights.tokenOverlap + weights.levenshtein;
        const normalizedWeights = {
            cosine: weights.cosine / total,
            tokenOverlap: weights.tokenOverlap / total,
            levenshtein: weights.levenshtein / total,
        };
        return (cosine * normalizedWeights.cosine +
            tokenOverlap * normalizedWeights.tokenOverlap +
            levenshtein * normalizedWeights.levenshtein);
    }
    /**
     * Helper: Calculate Jaro distance
     */
    static jaroDistance(s1, s2) {
        const len1 = s1.length;
        const len2 = s2.length;
        if (len1 === 0 && len2 === 0)
            return 1;
        if (len1 === 0 || len2 === 0)
            return 0;
        const matchDistance = Math.max(len1, len2) / 2 - 1;
        const s1Matches = new Array(len1);
        const s2Matches = new Array(len2);
        let matches = 0;
        let transpositions = 0;
        for (let i = 0; i < len1; i++) {
            const start = Math.max(0, i - matchDistance);
            const end = Math.min(i + matchDistance + 1, len2);
            for (let j = start; j < end; j++) {
                if (s2Matches[j] || s1[i] !== s2[j])
                    continue;
                s1Matches[i] = true;
                s2Matches[j] = true;
                matches++;
                break;
            }
        }
        if (matches === 0)
            return 0;
        let k = 0;
        for (let i = 0; i < len1; i++) {
            if (!s1Matches[i])
                continue;
            while (!s2Matches[k])
                k++;
            if (s1[i] !== s2[k])
                transpositions++;
            k++;
        }
        return ((matches / len1 +
            matches / len2 +
            (matches - transpositions / 2) / matches) /
            3);
    }
    /**
     * Helper: Tokenize text
     */
    static tokenize(text) {
        // Split on whitespace and punctuation, keep camelCase and snake_case intact
        const tokens = text
            .toLowerCase()
            .split(/[\s\W]+/)
            .filter((token) => token.length > 0);
        return new Set(tokens);
    }
}
exports.SimilarityScorer = SimilarityScorer;
//# sourceMappingURL=SimilarityScorer.js.map