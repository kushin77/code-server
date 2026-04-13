/**
 * Phase 5: Knowledge Graph Integration
 * ArchitectureDiscovery - Automatically discover code architecture and layers
 */
export interface ArchitectureLayer {
    name: string;
    description: string;
    components: string[];
    dependencies: Map<string, string[]>;
    complexity: number;
    responsibilities: string[];
    metrics: LayerMetrics;
}
export interface LayerMetrics {
    fileCount: number;
    classCount: number;
    functionCount: number;
    averageComplexity: number;
    testCoverage: number;
}
export interface ArchitecturePattern {
    name: string;
    type: 'layered' | 'modular' | 'microservices' | 'event-driven' | 'hexagonal';
    confidence: number;
    layers: ArchitectureLayer[];
    violations: ArchitectureViolation[];
    recommendations: string[];
}
export interface ArchitectureViolation {
    type: 'circular-dependency' | 'layer-crossing' | 'skip-layer' | 'tight-coupling';
    severity: 'low' | 'medium' | 'high' | 'critical';
    from: string;
    to: string;
    description: string;
}
export interface ComponentBoundary {
    name: string;
    path: string;
    exports: string[];
    internalAPIs: number;
    externalAPIs: number;
    dependencies: Map<string, number>;
}
export interface LayerViolation {
    from: string;
    to: string;
    type: 'cross-layer' | 'skip-layer' | 'bidirectional';
    severity: 'low' | 'medium' | 'high';
}
/**
 * Discover and analyze code architecture
 */
export declare class ArchitectureDiscovery {
    /**
     * Detect overall architecture pattern
     */
    detectArchitecturePattern(fileStructure: FileStructure): ArchitecturePattern;
    /**
     * Identify architectural layers
     */
    identifyLayers(fileStructure: FileStructure): ArchitectureLayer[];
    /**
     * Find layer violations (invalid dependencies between layers)
     */
    findLayerViolations(layers: ArchitectureLayer[]): ArchitectureViolation[];
    /**
     * Define component boundaries
     */
    defineComponentBoundaries(fileStructure: FileStructure): ComponentBoundary[];
    /**
     * Detect coupling between components
     */
    detectDependencyCoupling(boundaries: ComponentBoundary[]): CouplingMetrics;
    /**
     * Verify architectural consistency
     */
    verifyArchitecturalConsistency(arch: ArchitecturePattern): ConsistencyReport;
    private findFilesByPattern;
    private calculateLayerComplexity;
    private countClasses;
    private countFunctions;
    private inferResponsibilities;
    private findComponentDirs;
    private extractPublicAPI;
    private findComponentDependencies;
    private countInternalAPIs;
    private classifyArchitecture;
    private generateRecommendations;
    private hasCyclicDependency;
    private followsNamingConvention;
    private getConsistencyRecommendations;
}
export interface FileStructure {
    files: string[];
    directories: string[];
    rootPath: string;
}
export interface CouplingMetrics {
    averageCoupling: number;
    maxCoupling: number;
    minCoupling: number;
    cyclicDependencies: number;
    couplingByComponent: Map<string, number>;
}
export interface ConsistencyReport {
    score: number;
    issues: ConsistencyIssue[];
    isConsistent: boolean;
    recommendations: string[];
}
export interface ConsistencyIssue {
    type: string;
    severity: 'low' | 'medium' | 'high';
    component1: string;
    component2: string;
    description: string;
}
//# sourceMappingURL=ArchitectureDiscovery.d.ts.map
