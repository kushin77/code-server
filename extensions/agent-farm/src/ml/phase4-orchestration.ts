/**
 * Phase 4B: Advanced Semantic Search - Orchestration and Composition
 * Orchestrates QueryUnderstanding, CrossEncoderReranker, and MultiModalAnalyzer
 */

import { QueryUnderstanding, ExpandedQuery } from './QueryUnderstanding';
import { CrossEncoderReranker } from './CrossEncoderReranker';
import { MultiModalAnalyzer } from './MultiModalAnalyzer';

export interface SearchResult {
  filePath?: string;
  content?: string;
  score?: number;
}

export interface Phase4BSearchOptions {
  includeMultiModal: boolean;
  rerankerWeight: number;
  constraintFiltering: boolean;
  maxResults: number;
}

export interface EnhancedSearchResult extends SearchResult {
  expandedQuery?: ExpandedQuery;
  multiModalScore?: any;
  rerankerScore?: number;
  combinedScore?: number;
  reasoning?: string;
}

/**
 * Advanced Semantic Search Orchestrator
 * Coordinates Phase 4B components: QueryUnderstanding, CrossEncoderReranking, MultiModalAnalysis
 */
export class AdvancedSemanticSearchOrchestrator {
  private queryUnderstanding: QueryUnderstanding;
  private crossEncoderReranker: CrossEncoderReranker;
  private multiModalAnalyzer: MultiModalAnalyzer;

  constructor() {
    this.queryUnderstanding = new QueryUnderstanding();
    this.crossEncoderReranker = new CrossEncoderReranker();
    this.multiModalAnalyzer = new MultiModalAnalyzer();
  }

  /**
   * Execute advanced semantic search pipeline
   */
  async advancedSearch(
    query: string,
    results: SearchResult[],
    options: Partial<Phase4BSearchOptions> = {}
  ): Promise<EnhancedSearchResult[]> {
    const opts: Phase4BSearchOptions = {
      includeMultiModal: true,
      rerankerWeight: 0.6,
      constraintFiltering: true,
      maxResults: 100,
      ...options,
    };

    // Phase 1: Understand query intent and expand
    const expandedQuery = this.queryUnderstanding.expandQuery(query);
    console.log(`Phase 4B-1: Query understanding - Intent: ${expandedQuery.intent.type}`);

    // Phase 2: Filter results by constraints if needed
    let filtered = results;
    if (opts.constraintFiltering && expandedQuery.intent.constraints.length > 0) {
      filtered = this.applyConstraints(results, expandedQuery);
      console.log(
        `Phase 4B-2: Constraint filtering - ${filtered.length}/${results.length} results`
      );
    }

    // Phase 3: Enhance with multi-modal analysis
    const enhancedWithModality = opts.includeMultiModal
      ? await this.enhanceWithMultiModal(filtered, expandedQuery)
      : filtered.map((r) => ({ ...r, multiModalScore: undefined }));

    // Phase 4: Apply cross-encoder re-ranking
    const rerankedResults = this.crossEncoderReranker.rerank(
      enhancedWithModality as SearchResult[],
      query,
      expandedQuery.expandedTerms
    );

    // Phase 5: Combine scores and sort
    const finalResults = this.combineScores(
      rerankedResults,
      enhancedWithModality,
      opts.rerankerWeight
    );

    // Return top results
    return finalResults.slice(0, opts.maxResults);
  }

  /**
   * Apply query constraints to filter results
   */
  private applyConstraints(
    results: SearchResult[],
    expandedQuery: ExpandedQuery
  ): SearchResult[] {
    return results.filter((result) => {
      // Check constraints
      const hasConstraintMatch =
        expandedQuery.intent.constraints.length === 0 ||
        expandedQuery.intent.constraints.some((constraint) => {
          if (constraint.type === 'complexity') {
            const value = parseFloat(constraint.value as string);
            return constraint.operator === '>' ? value > 5 : value <= 5;
          }
          if (constraint.type === 'testCoverage') {
            const value = parseFloat(constraint.value as string);
            return constraint.operator === '>' ? value > 50 : value <= 50;
          }
          if (constraint.type === 'size') {
            const value = parseFloat(constraint.value as string);
            return constraint.operator === '<' ? 
              (result.content?.length || 0) < value : 
              (result.content?.length || 0) >= value;
          }
          return true;
        });

      return hasConstraintMatch;
    });
  }

  /**
   * Enhance results with multi-modal analysis
   */
  private async enhanceWithMultiModal(
    results: SearchResult[],
    expandedQuery: ExpandedQuery
  ): Promise<EnhancedSearchResult[]> {
    return Promise.all(
      results.map(async (result) => {
        try {
          const analysis = await this.multiModalAnalyzer.analyzeAsync(result.content || '');
          const multiModalScore = this.multiModalAnalyzer.computeScore(analysis);

          return {
            ...result,
            expandedQuery,
            multiModalScore,
          };
        } catch (error) {
          return {
            ...result,
            expandedQuery,
            multiModalScore: undefined,
          };
        }
      })
    );
  }

  /**
   * Combine scores from multiple components
   */
  private combineScores(
    rerankedResults: any[],
    enhancedResults: EnhancedSearchResult[],
    rerankerWeight: number
  ): EnhancedSearchResult[] {
    const resultMap = new Map<string, EnhancedSearchResult>();

    // Index enhanced results
    enhancedResults.forEach((r) => {
      resultMap.set(r.filePath || '', r);
    });

    // Combine scores
    const combined: EnhancedSearchResult[] = rerankedResults.map((rr) => {
      const enhanced = resultMap.get(rr.filePath || '') || rr;
      const baseScore = enhanced.score || 0;
      const rerankerScore = rr.score || 0;
      const multiModalScore = (enhanced.multiModalScore?.composite || 0) / 100;

      // Weighted combination: 40% base + 60% re-ranker + 20% multi-modal
      const combinedScore =
        baseScore * 0.4 + rerankerScore * rerankerWeight + multiModalScore * 0.2;

      return {
        ...enhanced,
        rerankerScore,
        combinedScore,
        reasoning: this.generateReasoning(enhanced, rr, multiModalScore),
      };
    });

    // Sort by combined score
    return combined.sort((a, b) => (b.combinedScore || 0) - (a.combinedScore || 0));
  }

  /**
   * Generate human-readable reasoning for ranking
   */
  private generateReasoning(
    baseResult: EnhancedSearchResult,
    rerankedResult: any,
    multiModalScore: number
  ): string {
    const reasons: string[] = [];

    if ((baseResult.score || 0) > 0.8) {
      reasons.push('Strong semantic match');
    }

    if (rerankedResult.score > 0.7) {
      reasons.push('High cross-encoder confidence');
    }

    if (multiModalScore > 0.7) {
      reasons.push('Well-documented and tested code');
    }

    return reasons.length > 0
      ? reasons.join('; ')
      : 'Relevant to search intent';
  }

  /**
   * Get analysis summary for results
   */
  getSummary(results: EnhancedSearchResult[]): {
    topResult: EnhancedSearchResult | null;
    avgScore: number;
    modalities: string[];
  } {
    return {
      topResult: results[0] || null,
      avgScore:
        results.reduce((sum, r) => sum + (r.combinedScore || 0), 0) /
        results.length || 0,
      modalities:
        results[0]?.multiModalScore && Object.keys(results[0].multiModalScore)
          ? ['code', 'tests', 'documentation', 'patterns']
          : [],
    };
  }
}