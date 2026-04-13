/**
 * Phase 5: Knowledge Graph Integration Agent
 * Semantic code understanding through knowledge graphs
 */
import { Agent, AgentOutput, CodeContext, MultiAgentContext } from '../types';
import { DependencyGraph } from '../ml/CodeDependencyExtractor';
import { KnowledgeGraph } from '../ml/KnowledgeGraphBuilder';
export interface KnowledgeGraphQuery {
    type: 'dependency' | 'relationship' | 'architecture' | 'complexity' | 'impact';
    target: string;
    depth?: number;
    filters?: {
        types?: string[];
        complexity?: 'low' | 'medium' | 'high';
        bidirectional?: boolean;
    };
}
export interface KnowledgeGraphResult {
    query: KnowledgeGraphQuery;
    graph: KnowledgeGraph | DependencyGraph;
    analysis: {
        cyclicDependencies?: Array<{
            nodes: string[];
            severity: string;
        }>;
        criticality: number;
        affectedComponents: string[];
        recommendations: string[];
    };
    reasoning: string;
}
export declare class KnowledgeGraphPhase5Agent extends Agent {
    readonly name = "KnowledgeGraphPhase5Agent";
    readonly domain = "Code Intelligence & Architecture";
    private dependencyExtractor;
    private graphBuilder;
    private cachedGraph;
    constructor();
    analyze(context: CodeContext): Promise<AgentOutput>;
    coordinate(context: MultiAgentContext, previousResults: AgentOutput[]): Promise<void>;
    private parseQuery;
    private findNodeByLabel;
    private getNodeLabel;
    private generateReasoning;
}
export default KnowledgeGraphPhase5Agent;
//# sourceMappingURL=KnowledgeGraphPhase5Agent.d.ts.map
