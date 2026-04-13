/**
 * Phase 5: Knowledge Graph Integration
 * CodeDependencyExtractor - Identify and extract code dependencies
 */
export interface CodeDependency {
    from: {
        file: string;
        symbol: string;
        line: number;
    };
    to: {
        file: string;
        symbol: string;
        type: 'import' | 'extends' | 'implements' | 'calls' | 'references';
    };
    strength: number;
    frequency: number;
    bidirectional: boolean;
}
export interface DependencyGraph {
    nodes: Map<string, DependencyNode>;
    edges: Map<string, CodeDependency>;
    metrics: DependencyMetrics;
}
export interface DependencyNode {
    id: string;
    type: 'file' | 'function' | 'class' | 'module' | 'interface';
    name: string;
    filePath: string;
    line: number;
    dependencies: string[];
    dependents: string[];
    metrics: NodeMetrics;
}
export interface DependencyMetrics {
    totalDependencies: number;
    totalDependents: number;
    cyclicDependencies: CyclicDependency[];
    orphanedNodes: string[];
    highComplexityNodes: string[];
    averageDepth: number;
}
export interface CyclicDependency {
    nodes: string[];
    length: number;
    severity: 'low' | 'medium' | 'high';
}
export interface NodeMetrics {
    inDegree: number;
    outDegree: number;
    cyclicDepth: number;
    reachableNodes: number;
    affectingNodes: number;
}
/**
 * Extract and analyze code dependencies
 */
export declare class CodeDependencyExtractor {
    private nodeCounter;
    private nodeMap;
    private edges;
    /**
     * Extract all dependencies from code
     */
    extractDependencies(code: string, filePath: string): CodeDependency[];
    /**
     * Build complete dependency graph from multiple files
     */
    buildDependencyGraph(files: Array<{
        path: string;
        content: string;
    }>): DependencyGraph;
    /**
     * Analyze cyclic dependencies
     */
    analyzeCyclicDependencies(graph: DependencyGraph): CyclicDependency[];
    /**
     * Compute complexity metrics
     */
    computeComplexityMetrics(graph: DependencyGraph): ComplexityReport;
    /**
     * Extract import/require dependencies
     */
    private extractImportDependencies;
    /**
     * Extract inheritance/implementation dependencies
     */
    private extractInheritanceDependencies;
    /**
     * Extract function/method call dependencies
     */
    private extractCallDependencies;
    /**
     * Extract symbol references
     */
    private extractReferenceDependencies;
    /**
     * Ensure a node exists in the graph
     */
    private ensureNode;
    /**
     * Detect cycles using DFS
     */
    private detectCycles;
    /**
     * Find node with highest complexity
     */
    private findHighestComplexityNode;
    /**
     * Compute complexity distribution
     */
    private computeComplexityDistribution;
    /**
     * Compute graph metrics
     */
    private computeMetrics;
    /**
     * Compute average dependency depth
     */
    private computeAverageDepth;
    /**
     * Compute depth of a node in dependency tree
     */
    private computeNodeDepth;
}
export interface ComplexityReport {
    totalNodes: number;
    totalEdges: number;
    averageInDegree: number;
    averageOutDegree: number;
    cyclicCount: number;
    orphanedCount: number;
    highestComplexityNode: string;
    complexityDistribution: Record<string, number>;
}
//# sourceMappingURL=CodeDependencyExtractor.d.ts.map