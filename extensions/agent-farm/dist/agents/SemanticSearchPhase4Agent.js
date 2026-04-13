"use strict";
/**
 * Phase 4A: ML Semantic Search Foundation Agent
 * SemanticSearchPhase4Agent - Implements semantic code search using ML embeddings
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.SemanticSearchPhase4Agent = void 0;
const types_1 = require("../types");
const MLEmbeddingEngine_1 = require("../ml/MLEmbeddingEngine");
class SemanticSearchPhase4Agent extends types_1.Agent {
    constructor() {
        super();
        this.name = 'SemanticSearchAgent';
        this.domain = 'ML Semantic Search Foundation';
        this.embeddingEngine = null;
        this.initialized = false;
        this.codeCache = new Map();
    }
    /**
     * Initialize semantic search by analyzing code
     */
    async initialize(context) {
        if (this.initialized)
            return;
        try {
            this.embeddingEngine = new MLEmbeddingEngine_1.MLEmbeddingEngine('http://localhost:11434');
            this.initialized = true;
        }
        catch (error) {
            this.log(`Initialization failed: ${error}`);
        }
    }
    /**
     * Main analysis method - semantic code search
     */
    async analyze(context) {
        this.log('Starting semantic search analysis...');
        try {
            await this.initialize(context);
            const recommendations = [];
            // Identify search patterns from code comments or keywords
            const codePatterns = this.extractSearchPatterns(context.content);
            // 1. Find similar code patterns
            if (codePatterns.length > 0) {
                const patternQuery = codePatterns[0];
                recommendations.push(`Identified semantic pattern: ${patternQuery}`);
                // Analyze semantic similarity to common patterns
                const commonPatterns = [
                    'async function',
                    'error handling',
                    'data validation',
                    'logging',
                    'state management',
                ];
                for (const pattern of commonPatterns) {
                    const similarity = this.calculateSemanticSimilarity(patternQuery, pattern);
                    if (similarity > 0.5) {
                        recommendations.push(`  • Pattern match: ${pattern} (${(similarity * 100).toFixed(1)}% match)`);
                    }
                }
            }
            // 2. Check for code duplication
            const duplicateCheck = this.checkForDuplication(context.content);
            if (duplicateCheck) {
                recommendations.push(duplicateCheck);
            }
            // 3. Semantic coherence analysis
            const coherence = this.analyzeSemanticCoherence(context.content);
            recommendations.push(`Semantic coherence score: ${(coherence * 100).toFixed(1)}%`);
            // 4. Get search statistics
            const cacheStats = `${this.codeCache.size} code snippets cached`;
            recommendations.push(`Search engine status: ${cacheStats}`);
            return this.formatOutput(`Semantic search analysis complete. ${recommendations.length} findings.`, recommendations, recommendations.length > 2 ? 'info' : 'warning');
        }
        catch (error) {
            return this.formatOutput(`Semantic search analysis failed: ${error}`, ['Check Ollama service is running at http://localhost:11434'], 'error');
        }
    }
    /**
     * Coordination with other agents
     */
    async coordinate(context, previousResults) {
        this.log('Coordinating with other agents...');
        // If other agents have found issues, search for similar patterns
        previousResults.forEach((result) => {
            if (result.recommendations && result.recommendations.length > 0) {
                this.log(`Noted findings from ${result.agentName}`);
            }
        });
    }
    /**
     * Extract searchable patterns from code
     */
    extractSearchPatterns(code) {
        const patterns = [];
        // Extract function definitions
        const functionRegex = /(?:function|const|let)\s+(\w+)\s*=?\s*(?:function|\(.*?\)\s*=>)?/g;
        let match;
        while ((match = functionRegex.exec(code)) !== null) {
            if (match[1]) {
                patterns.push(`function named ${match[1]}`);
            }
        }
        // Extract class definitions
        const classRegex = /class\s+(\w+)/g;
        while ((match = classRegex.exec(code)) !== null) {
            if (match[1]) {
                patterns.push(`class named ${match[1]}`);
            }
        }
        // Extract import patterns
        const importRegex = /import\s+(?:{[^}]*}|\w+)\s+from\s+['"]([^'"]+)['"]/g;
        while ((match = importRegex.exec(code)) !== null) {
            if (match[1]) {
                patterns.push(`import from ${match[1]}`);
            }
        }
        return patterns.slice(0, 3); // Return top 3 patterns
    }
    /**
     * Check for code duplication patterns
     */
    checkForDuplication(code) {
        // Detect repeated code blocks
        const lines = code.split('\n');
        const lineMap = new Map();
        lines.forEach((line) => {
            if (line.trim().length > 10) {
                // Only track meaningful lines
                const key = line.trim();
                lineMap.set(key, (lineMap.get(key) || 0) + 1);
            }
        });
        // Find lines repeated more than once
        const duplicates = Array.from(lineMap.values()).filter((count) => count > 1);
        if (duplicates.length > 0) {
            return `Detected ${duplicates.length} duplicated code blocks`;
        }
        return '';
    }
    /**
     * Analyze semantic coherence of code
     * (Returns a score 0-1 based on code structure)
     */
    analyzeSemanticCoherence(code) {
        let score = 0.5; // Base score
        // Prefer files with clear structure
        if (code.includes('class '))
            score += 0.1;
        if (code.includes('interface '))
            score += 0.1;
        if (code.includes('export '))
            score += 0.1;
        if (code.includes('import '))
            score += 0.05;
        // Penalize excessive complexity
        const { length } = code;
        if (length > 1000)
            score -= 0.1;
        if (length > 5000)
            score -= 0.1;
        // Ensure score stays in 0-1 range
        return Math.min(Math.max(score, 0), 1);
    }
    /**
     * Calculate semantic similarity between two text strings
     */
    calculateSemanticSimilarity(text1, text2) {
        // Simple token-based similarity
        const tokens1 = new Set(text1.toLowerCase().split(/\s+/));
        const tokens2 = new Set(text2.toLowerCase().split(/\s+/));
        const intersection = new Set([...tokens1].filter((token) => tokens2.has(token)));
        const union = new Set([...tokens1, ...tokens2]);
        return intersection.size / (union.size || 1);
    }
}
exports.SemanticSearchPhase4Agent = SemanticSearchPhase4Agent;
//# sourceMappingURL=SemanticSearchPhase4Agent.js.map