/**
 * Phase 4A: ML Semantic Search Foundation Agent
 * SemanticSearchPhase4Agent - Implements semantic code search using ML embeddings
 */
import { Agent, AgentOutput, CodeContext, MultiAgentContext } from '../types';
export declare class SemanticSearchPhase4Agent extends Agent {
    readonly name = "SemanticSearchAgent";
    readonly domain = "ML Semantic Search Foundation";
    private embeddingEngine;
    private initialized;
    private codeCache;
    constructor();
    /**
     * Initialize semantic search by analyzing code
     */
    private initialize;
    /**
     * Main analysis method - semantic code search
     */
    analyze(context: CodeContext): Promise<AgentOutput>;
    /**
     * Coordination with other agents
     */
    coordinate(context: MultiAgentContext, previousResults: AgentOutput[]): Promise<void>;
    /**
     * Extract searchable patterns from code
     */
    private extractSearchPatterns;
    /**
     * Check for code duplication patterns
     */
    private checkForDuplication;
    /**
     * Analyze semantic coherence of code
     * (Returns a score 0-1 based on code structure)
     */
    private analyzeSemanticCoherence;
    /**
     * Calculate semantic similarity between two text strings
     */
    private calculateSemanticSimilarity;
}
//# sourceMappingURL=SemanticSearchPhase4Agent.d.ts.map
