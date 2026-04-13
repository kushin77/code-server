/**
 * Phase 4A: ML Semantic Search Foundation
 * SemanticSearchAgent - Intelligent code search using ML embeddings
 */
import { Agent, AgentOutput, CodeContext, MultiAgentContext } from '../types';
import { SearchResult } from '../ml';
export interface SemanticSearchQuery {
    text: string;
    filePatterns?: string[];
    minRelevance?: number;
    maxResults?: number;
}
export declare class SemanticSearchAgent extends Agent {
    readonly name = "SemanticSearchAgent";
    readonly domain = "ML-Powered Code Search";
    private embeddingEngine;
    private ranker;
    private codeIndex;
    constructor(ollamaEndpoint?: string);
    /**
     * Index code files for semantic search
     */
    indexCodeFile(filePath: string, content: string): Promise<void>;
    /**
     * Perform semantic search on indexed code
     */
    semanticSearch(query: SemanticSearchQuery): Promise<SearchResult[]>;
    /**
     * Find similar code snippets
     */
    findSimilarCode(codeSnippet: string, threshold?: number): Promise<SearchResult[]>;
    /**
     * Detect code duplication
     */
    detectDuplication(similarityThreshold?: number): Promise<Map<string, SearchResult[]>>;
    /**
     * Get embedding cache statistics
     */
    getEmbeddingStats(): {
        indexedFiles: number;
        cacheSize: number;
        hitRate: number;
    };
    /**
     * Integrate with Agent Farm - analyze code using semantic search
     */
    analyze(context: CodeContext): Promise<AgentOutput>;
    /**
     * Multi-agent coordination
     */
    coordinate(context: MultiAgentContext, previousResults: AgentOutput[]): Promise<void>;
    /**
     * Clear index (for testing or manual reset)
     */
    clearIndex(): void;
}
//# sourceMappingURL=SemanticSearchAgent.d.ts.map