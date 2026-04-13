/**
 * Phase 5: Knowledge Graph Integration
 * KnowledgeGraphBuilder - Build searchable semantic graph from code dependencies
 */
import { DependencyGraph } from './CodeDependencyExtractor';
export interface KnowledgeGraphNode {
    id: string;
    type: 'file' | 'function' | 'class' | 'module' | 'package' | 'interface' | 'type';
    label: string;
    filePath: string;
    line: number;
    embedding?: number[];
    metadata: Record<string, any>;
    relatedNodes: string[];
    importance: number;
    tags: string[];
}
export interface KnowledgeGraphEdge {
    fromId: string;
    toId: string;
    relation: string;
    weight: number;
    metadata: Record<string, any>;
}
export interface KnowledgeGraph {
    nodes: Map<string, KnowledgeGraphNode>;
    edges: Map<string, KnowledgeGraphEdge>;
    metadata: GraphMetadata;
}
export interface GraphMetadata {
    totalNodes: number;
    totalEdges: number;
    lastUpdated: Date;
    codebaseMetrics: CodebaseMetrics;
}
export interface CodebaseMetrics {
    totalFiles: number;
    totalFunctions: number;
    totalClasses: number;
    averageComplexity: number;
    cyclicDependencies: number;
}
export interface ContextGraph {
    centerNode: KnowledgeGraphNode;
    neighbors: KnowledgeGraphNode[];
    edges: KnowledgeGraphEdge[];
    depth: number;
}
/**
 * Build and manage semantic code knowledge graph
 */
export declare class KnowledgeGraphBuilder {
    private nodes;
    private edges;
    private embeddingCache;
    private metadata;
    /**
     * Add a node to the graph
     */
    addNode(node: KnowledgeGraphNode): void;
    /**
     * Add an edge between nodes
     */
    addEdge(fromId: string, toId: string, relation: string, weight?: number): void;
    /**
     * Query by relationship type
     */
    queryByRelationship(query: string, relation?: string, hops?: number): KnowledgeGraphNode[];
    /**
     * Find shortest path between two nodes
     */
    findShortestPath(fromId: string, toId: string): string[];
    /**
     * Get context graph for a node
     */
    getNodeContext(nodeId: string, depth?: number): ContextGraph;
    /**
     * Build graph from dependency graph
     */
    buildFromDependencyGraph(depGraph: DependencyGraph): void;
    /**
     * Get the complete knowledge graph
     */
    getGraph(): KnowledgeGraph;
    /**
     * Search for nodes by keyword
     */
    search(keyword: string, limit?: number): KnowledgeGraphNode[];
    /**
     * Get statistics about the graph
     */
    getStatistics(): GraphStatistics;
    /**
     * Detect communities in the graph
     */
    detectCommunities(): Community[];
    /**
     * Extract community around a node
     */
    private extractCommunity;
    /**
     * Compute cohesion of a community
     */
    private computeCohesion;
    /**
     * Extract tags from symbol name
     */
    private extractTags;
}
export interface GraphStatistics {
    nodeCount: number;
    edgeCount: number;
    averageComplexity: number;
    typeDistribution: Record<string, number>;
    densestNodes: Array<{
        id: string;
        label: string;
        degree: number;
    }>;
}
export interface Community {
    id: string;
    members: string[];
    size: number;
    cohesion: number;
}
//# sourceMappingURL=KnowledgeGraphBuilder.d.ts.map
