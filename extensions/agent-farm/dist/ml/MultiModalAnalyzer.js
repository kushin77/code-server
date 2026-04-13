"use strict";
/**
 * Phase 4B: Advanced ML Semantic Search
 * MultiModalAnalyzer - Analyze code using multiple modalities (code, tests, docs, comments)
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.MultiModalAnalyzer = void 0;
class MultiModalAnalyzer {
    /**
     * Analyze code using multiple modalities
     */
    analyzeCode(result) {
        return {
            code: this.analyzeCode_CodeMetrics(result.text),
            tests: this.analyzeCode_Tests(result.text),
            documentation: this.analyzeCode_Documentation(result.text),
            patterns: this.analyzeCode_Patterns(result.text),
        };
    }
    /**
     * Analyze code metrics
     */
    analyzeCode_CodeMetrics(code) {
        const lines = code.split('\n').length;
        // Count functions/methods
        const functionRegex = /(function\s+\w+|const\s+\w+\s*=\s*\(|=>)/g;
        const functions = (code.match(functionRegex) || []).length;
        // Count classes/interfaces
        const classRegex = /(class\s+\w+|interface\s+\w+|type\s+\w+)/g;
        const classes = (code.match(classRegex) || []).length;
        // Estimate complexity (nested blocks)
        const complexityRegex = /({|})/g;
        const complexity = (code.match(complexityRegex) || []).length / Math.max(1, lines);
        // Estimate coverage (test-like assertions)
        const testRegex = /(expect\(|assert\(|should\()/g;
        const coverage = Math.min(100, ((code.match(testRegex) || []).length / Math.max(1, functions)) * 100);
        return {
            lines,
            complexity: Math.min(100, complexity * 10),
            coverage,
            functions,
            classes,
        };
    }
    /**
     * Analyze test coverage
     */
    analyzeCode_Tests(code) {
        const testIndicators = ['describe(', 'it(', 'test(', 'beforeEach(', 'afterEach('];
        const hasTests = testIndicators.some((ind) => code.includes(ind));
        const testCount = testIndicators.reduce((count, ind) => {
            return count + (code.match(new RegExp(ind, 'g')) || []).length;
        }, 0);
        const mockCount = (code.match(/jest\.mock|sinon\.stub|mock\(/g) || []).length;
        // Estimate coverage from assertions
        const assertCount = (code.match(/expect\(|assert\(|should\(/g) || []).length;
        const testCoverage = Math.min(100, (assertCount / Math.max(1, testCount || 1)) * 100);
        return {
            hasTests,
            testCount,
            testCoverage,
            mockUsage: mockCount,
        };
    }
    /**
     * Analyze documentation
     */
    analyzeCode_Documentation(code) {
        // Check for JSDoc/docstrings
        const docstringRegex = /\/\*\*[\s\S]*?\*\/|"""[\s\S]*?"""|\/\/\//;
        const hasDocstring = docstringRegex.test(code);
        // Check for inline comments
        const commentRegex = /\/\//g;
        const commentLines = (code.match(commentRegex) || []).length;
        const totalLines = code.split('\n').length;
        const commentDensity = (commentLines / Math.max(1, totalLines)) * 100;
        // Check if API documented
        const apiDocPatterns = [
            /@param|@returns|@throws|:param|:return|Args:|Returns:/,
        ];
        const apiDocumented = apiDocPatterns.some((pattern) => new RegExp(pattern).test(code));
        return {
            hasDocstring,
            hasComments: commentLines > 0,
            commentDensity,
            apiDocumented,
        };
    }
    /**
     * Analyze code patterns
     */
    analyzeCode_Patterns(code) {
        // Count async patterns
        const asyncCount = (code.match(/async\s+|await\s+/g) || []).length;
        // Check error handling
        const errorHandling = /try\s*{|catch\s*\(|throw\s+/.test(code) ||
            /\.catch\(|\.error|Error|Exception/.test(code);
        // Check performance optimization
        const performanceOptimization = /cache|memoiz|lazy|defer|async|Promise/.test(code);
        // Check security
        const securityChecks = /encrypt|decrypt|hash|token|auth|password|secret|sanitize|validate/.test(code);
        // Detect code smells
        const codeSmells = [];
        if (/var\s+\w+/.test(code))
            codeSmells.push('using var');
        if (/callback.*callback/.test(code))
            codeSmells.push('callback hell');
        if (/console\.(log|warn|error)/.test(code))
            codeSmells.push('debug logging');
        if (/TODO|FIXME|HACK|XXX/.test(code))
            codeSmells.push('unfinished work');
        if (/function.*function.*function/.test(code))
            codeSmells.push('deeply nested');
        if (code.split('\n').some((l) => l.length > 120))
            codeSmells.push('long lines');
        return {
            asyncPatterns: asyncCount,
            errorHandling,
            performanceOptimization,
            securityChecks,
            codeSmells,
        };
    }
    /**
     * Score multi-modal analysis
     */
    scoreMultiModal(modalities) {
        let score = 0.5; // Base score
        // Code quality metrics
        const { code } = modalities;
        if (code.coverage > 80)
            score += 0.15;
        if (code.complexity < 20)
            score += 0.1;
        if (code.lines > 50 && code.lines < 500)
            score += 0.05;
        // Test metrics
        const { tests } = modalities;
        if (tests.hasTests)
            score += 0.15;
        if (tests.testCoverage > 80)
            score += 0.1;
        // Documentation
        const { documentation } = modalities;
        if (documentation.hasDocstring)
            score += 0.1;
        if (documentation.commentDensity > 10)
            score += 0.05;
        if (documentation.apiDocumented)
            score += 0.1;
        // Patterns
        const { patterns } = modalities;
        if (patterns.errorHandling)
            score += 0.1;
        if (patterns.securityChecks)
            score += 0.1;
        if (patterns.performanceOptimization)
            score += 0.05;
        if (patterns.codeSmells.length === 0)
            score += 0.05;
        else if (patterns.codeSmells.length > 3)
            score -= 0.1;
        return Math.min(1, Math.max(0, score));
    }
    /**
     * Find related code across modalities
     */
    findRelatedCode(code, type) {
        const related = [];
        switch (type) {
            case 'tests':
                // Find test files for this code
                if (/^(class|function|const)\s+(\w+)/.test(code)) {
                    const match = code.match(/^(class|function|const)\s+(\w+)/);
                    if (match) {
                        related.push(`${match[2]}.test.ts`);
                        related.push(`${match[2]}.spec.ts`);
                        related.push(`__tests__/${match[2]}.ts`);
                    }
                }
                break;
            case 'docs':
                // Find documentation mentions
                if (/export\s+(class|interface|function)/.test(code)) {
                    related.push('README.md');
                    related.push('CONTRIBUTING.md');
                    related.push('docs/api.md');
                }
                break;
            case 'patterns':
                // Find similar patterns
                const patterns = {
                    async: ['async-utils.ts', 'promise-helpers.ts'],
                    error: ['error-handler.ts', 'exception-utils.ts'],
                    security: ['security.ts', 'auth-utils.ts'],
                    performance: ['optimize.ts', 'cache.ts'],
                };
                for (const [pattern, files] of Object.entries(patterns)) {
                    if (code.toLowerCase().includes(pattern)) {
                        related.push(...files);
                    }
                }
                break;
        }
        return related;
    }
    /**
     * Generate summary of analysis
     */
    summarizeAnalysis(modalities) {
        const code = modalities.code;
        const tests = modalities.tests;
        const docs = modalities.documentation;
        const patterns = modalities.patterns;
        const summary = `
Code Quality Report:
- Size: ${code.lines} lines, ${code.functions} functions, ${code.classes} classes
- Complexity: ${code.complexity.toFixed(1)}/100
- Coverage: ${code.coverage.toFixed(0)}%

Testing:
- Test Files: ${tests.hasTests ? 'Yes' : 'No'}
- Test Count: ${tests.testCount}
- Mock Usage: ${tests.mockUsage > 0 ? 'Yes' : 'No'}

Documentation:
- Docstrings: ${docs.hasDocstring ? 'Yes' : 'No'}
- Comments: ${docs.hasComments ? 'Yes' : 'No'} (${docs.commentDensity.toFixed(1)}%)
- API Documented: ${docs.apiDocumented ? 'Yes' : 'No'}

Patterns:
- Error Handling: ${patterns.errorHandling ? 'Yes' : 'No'}
- Security Checks: ${patterns.securityChecks ? 'Yes' : 'No'}
- Performance Optimized: ${patterns.performanceOptimization ? 'Yes' : 'No'}
- Async Patterns: ${patterns.asyncPatterns}
- Code Smells: ${patterns.codeSmells.length > 0 ? patterns.codeSmells.join(', ') : 'None'}
    `;
        return summary.trim();
    }
}
exports.MultiModalAnalyzer = MultiModalAnalyzer;
//# sourceMappingURL=MultiModalAnalyzer.js.map