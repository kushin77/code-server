"use strict";
/**
 * Phase 4B: Advanced ML Semantic Search
 * CrossEncoderReranker - Advanced result re-ranking using learned patterns
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.CrossEncoderReranker = void 0;
class CrossEncoderReranker {
    constructor() {
        // Learned weights for cross-encoder (would be trained in real ML pipeline)
        this.weights = {
            semanticSimilarity: 0.35,
            syntacticSimilarity: 0.15,
            tokenOverlap: 0.10,
            fileRelevance: 0.12,
            recency: 0.08,
            popularity: 0.08,
            codeQuality: 0.12,
            testCoverage: 0.04,
        };
    }
    /**
     * Extract ranking features from a search result
     */
    extractFeatures(result, queryIntent, allResults) {
        // Already have similarity
        const semanticSimilarity = result.similarity;
        // Syntactic similarity based on intent
        const syntacticSimilarity = this.calculateSyntacticSimilarity(result, queryIntent);
        // Token overlap
        const tokenOverlap = result.relevanceScore * 0.5; // Simplified
        // File relevance (boost certain file types)
        const fileRelevance = this.calculateFileRelevance(result, queryIntent);
        // Recency (normalized by max age in results)
        const maxAge = Math.max(...allResults.map((r) => r.lineNumber || 0));
        const recency = maxAge > 0 ? 1 - (result.lineNumber || 0) / maxAge : 0.5;
        // Popularity (CTR or usage count)
        const popularity = result.popularity || 0.5;
        // Code quality (heuristic based on code patterns)
        const codeQuality = this.estimateCodeQuality(result);
        // Test coverage estimation
        const testCoverage = this.estimateTestCoverage(result);
        return {
            semanticSimilarity: Math.min(1, Math.max(0, semanticSimilarity)),
            syntacticSimilarity: Math.min(1, Math.max(0, syntacticSimilarity)),
            tokenOverlap: Math.min(1, Math.max(0, tokenOverlap)),
            fileRelevance: Math.min(1, Math.max(0, fileRelevance)),
            recency: Math.min(1, Math.max(0, recency)),
            popularity: Math.min(1, Math.max(0, popularity)),
            codeQuality: Math.min(1, Math.max(0, codeQuality)),
            testCoverage: Math.min(1, Math.max(0, testCoverage)),
        };
    }
    /**
     * Calculate composite score using learned weights
     */
    scoreFeatures(features) {
        return (features.semanticSimilarity * this.weights.semanticSimilarity +
            features.syntacticSimilarity * this.weights.syntacticSimilarity +
            features.tokenOverlap * this.weights.tokenOverlap +
            features.fileRelevance * this.weights.fileRelevance +
            features.recency * this.weights.recency +
            features.popularity * this.weights.popularity +
            features.codeQuality * this.weights.codeQuality +
            features.testCoverage * this.weights.testCoverage);
    }
    /**
     * Re-rank results using cross-encoder logic
     */
    rerank(results, queryIntent) {
        const encoded = results.map((result) => {
            const features = this.extractFeatures(result, queryIntent, results);
            const score = this.scoreFeatures(features);
            const reasoning = this.generateReasoning(features, score);
            return {
                result,
                features,
                score,
                reasoning,
            };
        });
        // Sort by score descending
        return encoded.sort((a, b) => b.score - a.score);
    }
    /**
     * Calculate syntax similarity for specific intent
     */
    calculateSyntacticSimilarity(result, intent) {
        let similarity = 0;
        const text = result.text.toLowerCase();
        // Pattern matching for intent
        const patterns = {
            async: [
                /async\s+function/,
                /async\s+\(/,
                /await\s+/,
                /Promise</,
            ],
            error: [
                /catch\s*\(/,
                /throw\s+/,
                /Error/,
                /try\s*{/,
            ],
            database: [
                /query|insert|update|delete/i,
                /select|from|where/i,
                /\.find\(|\.save\(|\.create\(/,
                /db\.|sql|orm/i,
            ],
            performance: [
                /cache|memoiz/i,
                /optimize/i,
                /lazy|defer/i,
                /compress/i,
            ],
            test: [
                /describe\(|it\(|test\(/,
                /expect\(|assert/,
                /mock|stub|spy/,
                /\.test|\.spec/,
            ],
            security: [
                /encrypt|decrypt/,
                /hash|token|auth/,
                /password|secret|api.?key/i,
                /validate|sanitize/,
            ],
        };
        // Score patterns that match intent keywords
        for (const keyword of intent.keywords) {
            const patternList = patterns[keyword];
            if (patternList) {
                const matches = patternList.filter((p) => p.test(text)).length;
                similarity += matches / patternList.length;
            }
        }
        return Math.min(1, similarity / 3); // Normalize
    }
    /**
     * Calculate file relevance based on path and intent
     */
    calculateFileRelevance(result, intent) {
        const filePath = result.filePath.toLowerCase();
        let score = 0.5; // Base score
        // Boost for relevant directories
        const dirBoosts = {
            'test': 0.2,
            'spec': 0.2,
            'mock': 0.15,
            'utils': 0.15,
            'helpers': 0.15,
            'lib': 0.1,
            'service': 0.15,
            'controller': 0.15,
            'api': 0.15,
            'schema': 0.15,
        };
        for (const [dir, boost] of Object.entries(dirBoosts)) {
            if (filePath.includes(dir)) {
                score += boost;
                break;
            }
        }
        // Boost for relevant file types
        const intentFileTypes = {
            test: ['.test.ts', '.spec.ts', '.test.js', '.spec.js'],
            debug: ['.log', '.debug'],
            performance: ['.perf', '.benchmark'],
        };
        for (const [intent_type, exts] of Object.entries(intentFileTypes)) {
            if (intent.keywords.some((kw) => kw.includes(intent_type))) {
                if (exts.some((ext) => filePath.endsWith(ext))) {
                    score += 0.2;
                }
            }
        }
        return Math.min(1, score);
    }
    /**
     * Estimate code quality from patterns
     */
    estimateCodeQuality(result) {
        const text = result.text;
        let score = 0.5; // Base score
        // Positive indicators
        const positivePatterns = [
            /function\s+\w+\s*\(/, // Named functions
            /const\s+\w+\s*=/, // Const usage
            /^\s*\/\//m, // Comments
            /try\s*{|catch\s*\(/, // Error handling
            /return\s+/, // Explicit returns
            /throw\s+/, // Error throwing
        ];
        // Negative indicators
        const negativePatterns = [
            /var\s+/, // Old var usage
            /===/, // Type coercion
            /\!\+/, // Complex operators
            /callback.*callback/, // Callback hell
        ];
        positivePatterns.forEach((p) => {
            if (p.test(text))
                score += 0.1;
        });
        negativePatterns.forEach((p) => {
            if (p.test(text))
                score -= 0.1;
        });
        return Math.max(0, Math.min(1, score));
    }
    /**
     * Estimate test coverage from file indicators
     */
    estimateTestCoverage(result) {
        const filePath = result.filePath.toLowerCase();
        const text = result.text.toLowerCase();
        // Test file indicators
        const isTestFile = filePath.includes('.test') ||
            filePath.includes('.spec') ||
            filePath.includes('/test');
        if (!isTestFile && !text.includes('describe(')) {
            return 0.3; // Likely untested code
        }
        // Count test indicators in text
        let testIndicators = 0;
        const patterns = ['describe(', 'it(', 'test(', 'expect(', 'assert('];
        patterns.forEach((p) => {
            const count = (text.match(new RegExp(p, 'g')) || []).length;
            testIndicators += count;
        });
        if (isTestFile) {
            return Math.min(1, 0.8 + testIndicators / 100);
        }
        return Math.min(1, testIndicators / 50);
    }
    /**
     * Generate human-readable reasoning for the score
     */
    generateReasoning(features, score) {
        const topFeatures = Object.entries(features)
            .sort(([, a], [, b]) => b - a)
            .slice(0, 3)
            .map(([name, value]) => `${name}: ${(value * 100).toFixed(0)}%`);
        return `Score: ${(score * 100).toFixed(1)}% | Top factors: ${topFeatures.join(', ')}`;
    }
    /**
     * Adjust weights based on intent (for domain-specific ranking)
     */
    adjustWeightsForIntent(intent) {
        // Reset weights
        this.resetWeights();
        // Adjust based on intent
        switch (intent.type) {
            case 'test':
                this.weights.testCoverage = 0.2;
                this.weights.fileRelevance = 0.2;
                break;
            case 'refactor':
                this.weights.codeQuality = 0.25;
                this.weights.semanticSimilarity = 0.3;
                break;
            case 'optimize':
                this.weights.semanticSimilarity = 0.4;
                this.weights.codeQuality = 0.15;
                break;
            case 'debug':
                this.weights.fileRelevance = 0.2;
                this.weights.semanticSimilarity = 0.35;
                break;
        }
        // Normalize weights to sum to 1
        const total = Object.values(this.weights).reduce((a, b) => a + b, 0);
        for (const key in this.weights) {
            this.weights[key] /= total;
        }
    }
    /**
     * Reset weights to defaults
     */
    resetWeights() {
        this.weights = {
            semanticSimilarity: 0.35,
            syntacticSimilarity: 0.15,
            tokenOverlap: 0.10,
            fileRelevance: 0.12,
            recency: 0.08,
            popularity: 0.08,
            codeQuality: 0.12,
            testCoverage: 0.04,
        };
    }
}
exports.CrossEncoderReranker = CrossEncoderReranker;
//# sourceMappingURL=CrossEncoderReranker.js.map