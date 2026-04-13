/**
 * Phase 4B: Advanced ML Semantic Search Agent
 * AdvancedSemanticSearchPhase4BAgent - Full semantic search with query understanding and re-ranking
 */
import { Agent, AgentOutput, CodeContext, MultiAgentContext } from '../types';
export declare class AdvancedSemanticSearchPhase4BAgent extends Agent {
    readonly name = "AdvancedSemanticSearchAgent";
    readonly domain = "Advanced ML Semantic Search";
    private queryUnderstanding;
    private crossEncoderReranker;
    private multiModalAnalyzer;
    constructor();
    /**
     * Main analysis method - advanced semantic search
     */
    analyze(context: CodeContext): Promise<AgentOutput>;
    /**
     * Coordination with other agents
     */
    coordinate(context: MultiAgentContext, previousResults: AgentOutput[]): Promise<void>;
    /**
     * Extract code query from context
     */
    private extractCodeQueryFromContext;
    /**
     * Expand query with synonyms and patterns
     */
    private expandQueryTerms;
    /**
     * Analyze code using multiple modalities
     */
    private analyzeCodeModalities;
    /**
     * Detect code patterns and anti-patterns
     */
    private detectCodePatterns;
    /**
     * Suggest optimizations based on analysis
     */
    private suggestOptimizations;
}
//# sourceMappingURL=AdvancedSemanticSearchPhase4BAgent.d.ts.map