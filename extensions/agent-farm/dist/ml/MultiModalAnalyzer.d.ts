/**
 * Multi-Modal Analyzer Module
 * Analyzes code across text, AST, and semantic modalities
 */
export interface MultiModalAnalysis {
    textAnalysis: {
        tokens: string[];
        complexity: number;
    };
    semanticAnalysis: {
        concepts: string[];
        relationships: string[];
    };
    astAnalysis: {
        structure: string;
        depth: number;
    };
}
export declare class MultiModalAnalyzer {
    /**
     * Perform multi-modal analysis on code
     */
    analyze(code: string): Promise<MultiModalAnalysis>;
    private estimateComplexity;
}
//# sourceMappingURL=MultiModalAnalyzer.d.ts.map