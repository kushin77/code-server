/**
 * Phase 5: Knowledge Graph Integration
 * RelationshipAnalyzer - Analyze code relationships and patterns
 */
export interface CodeRelationship {
    type: 'inheritance' | 'composition' | 'dependency' | 'call' | 'reference';
    from: string;
    to: string;
    strength: number;
    bidirectional: boolean;
    examples: Array<{
        file: string;
        line: number;
        code: string;
    }>;
}
export interface InheritanceHierarchy {
    rootClasses: string[];
    childMap: Map<string, string[]>;
    parentMap: Map<string, string>;
    depth: number;
}
export interface CompositionPattern {
    composerClass: string;
    composedClass: string;
    propertyName: string;
    cardinality: 'one' | 'many';
    file: string;
    line: number;
}
export interface DIPattern {
    injectedClass: string;
    injectionPoints: Array<{
        method: string;
        parameter: string;
        file: string;
        line: number;
    }>;
    injectionType: 'constructor' | 'setter' | 'provider' | 'factory';
}
export interface CallGraph {
    nodes: Map<string, CallGraphNode>;
    edges: Map<string, CallGraphEdge>;
    cycles: CallCycle[];
}
export interface CallGraphNode {
    id: string;
    name: string;
    file: string;
    line: number;
    params: string[];
    returns: string;
    calls: string[];
    calledBy: string[];
}
export interface CallGraphEdge {
    from: string;
    to: string;
    count: number;
    lines: number[];
}
export interface CallCycle {
    functions: string[];
    length: number;
    severity: 'low' | 'medium' | 'high';
}
export interface PatternMatch {
    name: string;
    type: string;
    confidence: number;
    locations: Array<{
        file: string;
        line: number;
    }>;
    description: string;
}
/**
 * Analyze code relationships and design patterns
 */
export declare class RelationshipAnalyzer {
    /**
     * Analyze class inheritance hierarchy
     */
    analyzeInheritanceHierarchy(classes: Array<{
        name: string;
        extends?: string;
        implements?: string[];
    }>): InheritanceHierarchy;
    /**
     * Find composition patterns in code
     */
    findCompositionPatterns(code: string): CompositionPattern[];
    /**
     * Detect dependency injection patterns
     */
    detectDependencyInjection(): DIPattern[];
    /**
     * Analyze function call graphs
     */
    analyzeCallGraphs(functions: Array<{
        name: string;
        calls: string[];
        file: string;
        line: number;
    }>): CallGraph;
    /**
     * Identify common design patterns
     */
    identifyCommonPatterns(code: string): PatternMatch[];
    private calculateHierarchyDepth;
    private getDepth;
    private findCallCycle;
    private detectSingletonPattern;
    private detectFactoryPattern;
    private detectObserverPattern;
    private detectStrategyPattern;
    private detectDIPattern;
}
export interface ComplexityReport {
    totalFunctions: number;
    totalClasses: number;
    averageCyclomaticComplexity: number;
    highComplexityFunctions: Array<{
        name: string;
        complexity: number;
    }>;
    maintainabilityIndex: number;
}
//# sourceMappingURL=RelationshipAnalyzer.d.ts.map