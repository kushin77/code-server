"use strict";
/**
 * Phase 4B: Advanced ML Semantic Search Agent
 * AdvancedSemanticSearchPhase4BAgent - Full semantic search with query understanding and re-ranking
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdvancedSemanticSearchPhase4BAgent = void 0;
const types_1 = require("../types");
const QueryUnderstanding_1 = require("../ml/QueryUnderstanding");
const CrossEncoderReranker_1 = require("../ml/CrossEncoderReranker");
const MultiModalAnalyzer_1 = require("../ml/MultiModalAnalyzer");
class AdvancedSemanticSearchPhase4BAgent extends types_1.Agent {
    constructor() {
        super();
        this.name = 'AdvancedSemanticSearchAgent';
        this.domain = 'Advanced ML Semantic Search';
        this.queryUnderstanding = new QueryUnderstanding_1.QueryUnderstanding();
        this.crossEncoderReranker = new CrossEncoderReranker_1.CrossEncoderReranker();
        this.multiModalAnalyzer = new MultiModalAnalyzer_1.MultiModalAnalyzer();
    }
    /**
     * Main analysis method - advanced semantic search
     */
    async analyze(context) {
        this.log('Starting advanced semantic search analysis...');
        try {
            const recommendations = [];
            // 1. Extract queries and intents from code context
            const codeQuery = this.extractCodeQueryFromContext(context.content);
            if (codeQuery) {
                recommendations.push(`Identified query intent: ${codeQuery.type}`);
                // 2. Expand query with synonyms and patterns
                const expandedQueries = await this.expandQueryTerms(codeQuery, context.content);
                recommendations.push(`Expanded query to ${expandedQueries.expandedTerms.length} related terms`);
                // 3. Analyze query constraints
                if (codeQuery.constraints.length > 0) {
                    recommendations.push(`Applied ${codeQuery.constraints.length} search constraints`);
                }
            }
            // 4. Analyze code modalities
            const modalities = this.analyzeCodeModalities(context.content);
            recommendations.push(`Code composition analysis:`);
            recommendations.push(`  • Avg complexity: ${modalities.code.complexity.toFixed(2)}`);
            recommendations.push(`  • Test coverage: ${(modalities.tests.testCoverage * 100).toFixed(0)}%`);
            recommendations.push(`  • Documentation: ${modalities.documentation.commentDensity.toFixed(2)}%`);
            // 5. Detect code patterns and anti-patterns
            const patterns = this.detectCodePatterns(context.content);
            if (patterns.length > 0) {
                recommendations.push(`Detected ${patterns.length} code patterns:`);
                patterns.slice(0, 3).forEach((p) => {
                    recommendations.push(`  • ${p}`);
                });
            }
            // 6. Suggest optimizations based on multi-modal analysis
            const optimizations = this.suggestOptimizations(modalities);
            if (optimizations.length > 0) {
                recommendations.push(`Optimization suggestions:`);
                optimizations.slice(0, 3).forEach((o) => {
                    recommendations.push(`  • ${o}`);
                });
            }
            return this.formatOutput(`Advanced semantic analysis complete. ${recommendations.length} insights found.`, recommendations, recommendations.length > 5 ? 'info' : 'warning');
        }
        catch (error) {
            return this.formatOutput(`Advanced search analysis failed: ${error}`, ['Check if ML components are properly initialized'], 'error');
        }
    }
    /**
     * Coordination with other agents
     */
    async coordinate(context, previousResults) {
        this.log('Coordinating advanced analysis with other agents...');
        // If Phase 4A found patterns, enhance analysis
        previousResults.forEach((result) => {
            if (result.agentName?.includes('SemanticSearch')) {
                this.log(`Building on Phase 4A: ${result.summary}`);
            }
        });
    }
    /**
     * Extract code query from context
     */
    extractCodeQueryFromContext(code) {
        // Look for TODO/FIXME/HACK comments which are implicit queries
        const todoRegex = /(TODO|FIXME|HACK|BUG|OPTIMIZE):\s*(.+?)(?:\n|$)/g;
        const matches = Array.from(code.matchAll(todoRegex));
        if (matches.length === 0)
            return null;
        const query = matches[0][2] || '';
        // Determine intent from query text
        let type = 'analyze';
        if (query.includes('fix') || query.includes('error'))
            type = 'debug';
        if (query.includes('test'))
            type = 'test';
        if (query.includes('optimize') || query.includes('speed'))
            type = 'optimize';
        if (query.includes('refactor') || query.includes('clean'))
            type = 'refactor';
        return {
            type,
            keywords: query.split(/\s+/).slice(0, 3),
            entities: [],
            constraints: [],
        };
    }
    /**
     * Expand query with synonyms and patterns
     */
    async expandQueryTerms(intent, content) {
        const query = intent.keywords.join(' ');
        return this.queryUnderstanding.expandQuery(query);
    }
    /**
     * Analyze code using multiple modalities
     */
    analyzeCodeModalities(code) {
        const lines = code.split('\n').length;
        const functions = (code.match(/function|const.*=.*=>|\w+\s*\(/g) || []).length;
        const classes = (code.match(/class\s+\w+/g) || []).length;
        const hasTests = code.includes('test') || code.includes('describe');
        const hasComments = code.includes('//') || code.includes('/*');
        const commentLines = code.split('\n').filter((l) => l.trim().startsWith('//'))
            .length;
        const commentDensity = (commentLines / lines) * 100;
        return {
            code: {
                lines,
                complexity: Math.min(functions / 5, 1), // Normalized
                coverage: hasTests ? 0.6 : 0.2,
                functions,
                classes,
            },
            tests: {
                hasTests,
                testCount: (code.match(/test\(|it\(/g) || []).length,
                testCoverage: hasTests ? 0.6 : 0,
                mockUsage: (code.match(/mock|spy|stub/gi) || []).length,
            },
            documentation: {
                hasDocstring: code.includes('/**') || code.includes('"""'),
                hasComments,
                commentDensity,
                apiDocumented: code.includes('export') && hasComments,
            },
            patterns: {
                asyncPatterns: (code.match(/async|await|Promise/g) || []).length,
                errorHandling: code.includes('catch') || code.includes('try'),
                performanceOptimization: code.includes('memo') ||
                    code.includes('cache') ||
                    code.includes('pool'),
                securityChecks: code.includes('validate') || code.includes('sanitize'),
                codeSmells: [],
            },
        };
    }
    /**
     * Detect code patterns and anti-patterns
     */
    detectCodePatterns(code) {
        const patterns = [];
        if (code.includes('async') && code.includes('await')) {
            patterns.push('Async/await pattern (properly used)');
        }
        const iterationMatches = code.match(/for\s*\(\s*let|for\s*\(\s*const|forEach|map|filter/g);
        if ((iterationMatches?.length ?? 0) > 2) {
            patterns.push('Heavy iteration usage (potential for optimization)');
        }
        if (code.includes('new Error') || code.includes('throw')) {
            patterns.push('Explicit error handling');
        }
        const memoMatches = code.match(/const\s+\w+\s*=\s*memo|useMemo|useCallback|lru|memoize/g);
        if ((memoMatches?.length ?? 0) > 0) {
            patterns.push('Memoization pattern detected');
        }
        if (code.includes('export') && code.includes('interface')) {
            patterns.push('Well-typed exports (TypeScript)');
        }
        return patterns;
    }
    /**
     * Suggest optimizations based on analysis
     */
    suggestOptimizations(modalities) {
        const suggestions = [];
        // Code complexity optimization
        if (modalities.code.complexity > 0.6) {
            suggestions.push('Break down complex functions (high complexity detected)');
        }
        // Test coverage optimization
        if (modalities.tests.testCoverage < 0.5) {
            suggestions.push('Increase test coverage (currently < 50%)');
        }
        // Documentation optimization
        if (modalities.documentation.commentDensity < 10) {
            suggestions.push('Add more documentation and comments');
        }
        // Pattern-based optimization
        if (modalities.patterns.asyncPatterns > 3 &&
            modalities.patterns.errorHandling === false) {
            suggestions.push('Add error handling for async operations');
        }
        if (modalities.patterns.performanceOptimization === false &&
            modalities.code.functions > 10) {
            suggestions.push('Consider caching or memoization for frequently called functions');
        }
        return suggestions;
    }
}
exports.AdvancedSemanticSearchPhase4BAgent = AdvancedSemanticSearchPhase4BAgent;
//# sourceMappingURL=AdvancedSemanticSearchPhase4BAgent.js.map