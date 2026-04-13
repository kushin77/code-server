/**
 * Phase 4B: Advanced ML Semantic Search
 * MultiModalAnalyzer - Analyze code using multiple modalities (code, tests, docs, comments)
 */
import { SearchResult } from './RelevanceRanker';
export interface CodeModalities {
    code: CodeAnalysis;
    tests: TestAnalysis;
    documentation: DocumentationAnalysis;
    patterns: PatternAnalysis;
}
export interface CodeAnalysis {
    lines: number;
    complexity: number;
    coverage: number;
    functions: number;
    classes: number;
}
export interface TestAnalysis {
    hasTests: boolean;
    testCount: number;
    testCoverage: number;
    mockUsage: number;
}
export interface DocumentationAnalysis {
    hasDocstring: boolean;
    hasComments: boolean;
    commentDensity: number;
    apiDocumented: boolean;
}
export interface PatternAnalysis {
    asyncPatterns: number;
    errorHandling: boolean;
    performanceOptimization: boolean;
    securityChecks: boolean;
    codeSmells: string[];
}
export interface MultiModalScore {
    result: SearchResult;
    modalities: CodeModalities;
    compositeScore: number;
}
export declare class MultiModalAnalyzer {
    /**
     * Analyze code using multiple modalities
     */
    analyzeCode(result: SearchResult): CodeModalities;
    /**
     * Analyze code metrics
     */
    private analyzeCode_CodeMetrics;
    /**
     * Analyze test coverage
     */
    private analyzeCode_Tests;
    /**
     * Analyze documentation
     */
    private analyzeCode_Documentation;
    /**
     * Analyze code patterns
     */
    private analyzeCode_Patterns;
    /**
     * Score multi-modal analysis
     */
    scoreMultiModal(modalities: CodeModalities): number;
    /**
     * Find related code across modalities
     */
    findRelatedCode(code: string, type: 'tests' | 'docs' | 'patterns'): string[];
    /**
     * Generate summary of analysis
     */
    summarizeAnalysis(modalities: CodeModalities): string;
}
//# sourceMappingURL=MultiModalAnalyzer.d.ts.map