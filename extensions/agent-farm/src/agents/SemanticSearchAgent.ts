/**
 * Phase 4A: ML Semantic Search Foundation
 * SemanticSearchAgent - Intelligent code search using ML embeddings
 */

import { Agent, AgentOutput, CodeContext, MultiAgentContext } from '../types';
import {
  MLEmbeddingEngine,
  SimilarityScorer,
  RelevanceRanker,
  SearchResult,
} from '../ml';

export interface SemanticSearchQuery {
  text: string;
  filePatterns?: string[];
  minRelevance?: number;
  maxResults?: number;
}

export class SemanticSearchAgent extends Agent {
  readonly name = 'SemanticSearchAgent';
   readonly domain = 'ML-Powered Code Search';
  private embeddingEngine: MLEmbeddingEngine;
  private ranker: RelevanceRanker;
  private codeIndex: Map<string, SearchResult> = new Map();

  constructor(ollamaEndpoint?: string) {
    super();
    this.embeddingEngine = new MLEmbeddingEngine(ollamaEndpoint);
    this.ranker = new RelevanceRanker();
  }

  /**
   * Index code files for semantic search
   */
  async indexCodeFile(filePath: string, content: string): Promise<void> {
    this.log(`Indexing file: ${filePath}`);

    try {
      // Generate embedding for the code
      const embedding = await this.embeddingEngine.generateEmbedding(
        content,
        filePath
      );

      // Store in index
      this.codeIndex.set(filePath, {
        id: filePath,
        text: content.substring(0, 500), // Store first 500 chars
        vector: embedding.vector,
        filePath,
        lineNumber: 1,
        similarity: 1,
        relevanceScore: 1,
      });

      this.log(`Indexed ${filePath} (embedding generated)`);
    } catch (error) {
      this.log(`Failed to index ${filePath}: ${error}`);
    }
  }

  /**
   * Perform semantic search on indexed code
   */
  async semanticSearch(
    query: SemanticSearchQuery
  ): Promise<SearchResult[]> {
    this.log(`Searching for: "${query.text}"`);

    try {
      // Generate embedding for query
      const queryEmbedding = await this.embeddingEngine.generateEmbedding(
        query.text
      );

      // Get candidates from index
      let candidates = Array.from(this.codeIndex.values());

      // Filter by file patterns if specified
      if (query.filePatterns && query.filePatterns.length > 0) {
        const patterns = query.filePatterns.map((p) => new RegExp(p));
        candidates = candidates.filter((candidate) =>
          patterns.some((p) => p.test(candidate.filePath))
        );
      }

      if (candidates.length === 0) {
        this.log('No files match search criteria');
        return [];
      }

      // Rank candidates by relevance
      const rankedResults = this.ranker.rankResults(
        queryEmbedding.vector,
        query.text,
        candidates
      );

      // Filter by minimum relevance
      const minScore = query.minRelevance || 0.3;
      const filtered = this.ranker.filterByThreshold(rankedResults, minScore);

      // Return top results
      const topN = query.maxResults || 10;
      const results = this.ranker.getTopResults(filtered, topN);

      this.log(
        `Found ${results.length} relevant results (out of ${candidates.length} total)`
      );

      return results;
    } catch (error) {
      this.log(`Search failed: ${error}`);
      return [];
    }
  }

  /**
   * Find similar code snippets
   */
  async findSimilarCode(
    codeSnippet: string,
    threshold: number = 0.7
  ): Promise<SearchResult[]> {
    this.log(`Finding similar code to snippet`);

    try {
      const embedding = await this.embeddingEngine.generateEmbedding(
        codeSnippet
      );

      const candidates = Array.from(this.codeIndex.values());
      const rankedResults = this.ranker.rankResults(
        embedding.vector,
        codeSnippet,
        candidates
      );

      const similar = this.ranker.filterByThreshold(rankedResults, threshold);

      this.log(`Found ${similar.length} similar code locations`);

      return similar;
    } catch (error) {
      this.log(`Failed to find similar code: ${error}`);
      return [];
    }
  }

  /**
   * Detect code duplication
   */
  async detectDuplication(
    similarityThreshold: number = 0.85
  ): Promise<Map<string, SearchResult[]>> {
    this.log(`Detecting code duplication`);

    const duplicates = new Map<string, SearchResult[]>();
    const files = Array.from(this.codeIndex.values());

    for (let i = 0; i < files.length; i++) {
      const current = files[i];
      const similar: SearchResult[] = [];

      for (let j = i + 1; j < files.length; j++) {
        const other = files[j];
        const similarity = SimilarityScorer.cosineSimilarity(
          current.vector,
          other.vector
        );

        if (similarity > similarityThreshold) {
          similar.push({
            ...other,
            similarity,
            relevanceScore: similarity,
          });
        }
      }

      if (similar.length > 0) {
        duplicates.set(current.filePath, similar);
      }
    }

    this.log(`Found ${duplicates.size} files with potential duplicates`);

    return duplicates;
  }

  /**
   * Get embedding cache statistics
   */
  getEmbeddingStats(): {
    indexedFiles: number;
    cacheSize: number;
    hitRate: number;
  } {
    const stats = this.embeddingEngine.getCacheStats();
    return {
      indexedFiles: this.codeIndex.size,
      cacheSize: stats.size,
      hitRate: stats.hitRate,
    };
  }

  /**
   * Integrate with Agent Farm - analyze code using semantic search
   */
  async analyze(context: CodeContext): Promise<AgentOutput> {
    this.log('Analyzing code with semantic search');

    // Index the current file
    await this.indexCodeFile(context.uri.fsPath, context.content);

    // Get selected text or use full content
    const selectedContent = context.content.substring(
      context.selection.start.character,
      context.selection.end.character + 50 // Check a bit beyond selection
    ) || context.content.substring(0, 500);

    // Find similar patterns in codebase
    const similarCode = await this.findSimilarCode(
      selectedContent,
      0.75
    );

    const recommendations: string[] = [];

    if (similarCode.length > 0) {
      recommendations.push(
        `Found ${similarCode.length} similar code locations:`
      );
      similarCode.forEach((result) => {
        recommendations.push(
          `  - ${result.filePath}:${result.lineNumber} (${(result.similarity * 100).toFixed(1)}% similar)`
        );
      });

      if (similarCode.length >= 2) {
        recommendations.push(
          'Consider extracting common patterns to shared utilities'
        );
      }
    }

    // Check for duplicates
    const duplicates = await this.detectDuplication(0.9);
    if (duplicates.size > 0) {
      recommendations.push(
        `Warning: ${duplicates.size} files may have significant code duplication`
      );
    }

    // Get cache stats
    const stats = this.getEmbeddingStats();
    const summary = `Semantic analysis complete. Indexed ${stats.indexedFiles} files, Cache hit rate: ${stats.hitRate.toFixed(1)}%`;

    return this.formatOutput(
      summary,
      recommendations,
      recommendations.length > 2 ? 'warning' : 'info'
    );
  }

  /**
   * Multi-agent coordination
   */
  async coordinate(
    context: MultiAgentContext,
    previousResults: AgentOutput[]
  ): Promise<void> {
    this.log('Coordinating with other agents on code patterns');

    // Share indexed code data with other agents
    // This enables cross-agent pattern discovery
    const indexStats = this.getEmbeddingStats();
    context.coordinationState['semanticIndex'] = {
      filesIndexed: indexStats.indexedFiles,
      cacheHitRate: indexStats.hitRate,
    };
  }

  /**
   * Clear index (for testing or manual reset)
   */
  clearIndex(): void {
    this.codeIndex.clear();
    this.embeddingEngine.clearCache();
    this.log('Cleared semantic index');
  }
}
