/**
 * Phase 4A: ML Semantic Search Foundation
 * RelevanceRanker - Rank search results by relevance
 */

import { SimilarityScorer } from './SimilarityScorer';

export interface SearchResult {
  id: string;
  text: string;
  vector: number[];
  filePath: string;
  lineNumber?: number;
  similarity: number;
  relevanceScore: number;
  popularity?: number; // Optional popularity metric
}

export interface RankingWeights {
  semanticSimilarity: number;
  syntacticSimilarity: number;
  tokenOverlap: number;
  recency: number; // Boost recent results
  popularity: number; // Boost frequently accessed
}

export class RelevanceRanker {
  private defaultWeights: RankingWeights = {
    semanticSimilarity: 0.4,
    syntacticSimilarity: 0.2,
    tokenOverlap: 0.2,
    recency: 0.1,
    popularity: 0.1,
  };

  /**
   * Rank search results by relevance
   */
  rankResults(
    queryVector: number[],
    queryText: string,
    candidates: SearchResult[],
    weights: Partial<RankingWeights> = {}
  ): SearchResult[] {
    const mergedWeights = { ...this.defaultWeights, ...weights };

    // Score each candidate
    const scored = candidates.map((candidate) => {
      const semanticScore = SimilarityScorer.cosineSimilarity(
        queryVector,
        candidate.vector
      );

      const syntacticScore = SimilarityScorer.jaroWinklerSimilarity(
        queryText,
        candidate.text.substring(0, Math.min(100, candidate.text.length))
      );

      const tokenScore = SimilarityScorer.tokenOverlapSimilarity(
        queryText,
        candidate.text
      );

      // Calculate composite score
      const relevanceScore =
        semanticScore * mergedWeights.semanticSimilarity +
        syntacticScore * mergedWeights.syntacticSimilarity +
        tokenScore * mergedWeights.tokenOverlap +
        (candidate.popularity || 0.5) * mergedWeights.popularity;

      return {
        ...candidate,
        relevanceScore,
        similarity: semanticScore,
      };
    });

    // Sort by relevance score (descending)
    return scored.sort((a, b) => b.relevanceScore - a.relevanceScore);
  }

  /**
   * Filter results by minimum threshold
   */
  filterByThreshold(
    results: SearchResult[],
    minScore: number = 0.3
  ): SearchResult[] {
    return results.filter((result) => result.relevanceScore >= minScore);
  }

  /**
   * Get top N results
   */
  getTopResults(results: SearchResult[], topN: number = 10): SearchResult[] {
    return results.slice(0, topN);
  }

  /**
   * Combine multiple ranking strategies (ensemble)
   */
  ensembleRank(
    queryVector: number[],
    queryText: string,
    candidates: SearchResult[],
    strategies: Array<{
      weights: Partial<RankingWeights>;
      weight: number;
    }>
  ): SearchResult[] {
    const results: Map<string, number> = new Map();

    // Run each strategy
    for (const { weights, weight } of strategies) {
      const ranked = this.rankResults(queryVector, queryText, candidates, weights);

      // Score results by position (descending importance)
      ranked.forEach((result, position) => {
        const positionScore = (ranked.length - position) / ranked.length;
        const currentScore = results.get(result.id) || 0;
        results.set(result.id, currentScore + positionScore * weight);
      });
    }

    // Sort by ensemble score
    const ensembleResults = candidates
      .map((candidate) => ({
        ...candidate,
        relevanceScore: results.get(candidate.id) || 0,
      }))
      .sort((a, b) => b.relevanceScore - a.relevanceScore);

    return ensembleResults;
  }

  /**
   * Boost results by file type or context
   */
  boostResults(
    results: SearchResult[],
    boostRules: Array<{
      pattern: RegExp;
      boost: number;
    }>
  ): SearchResult[] {
    return results.map((result) => {
      let boostedScore = result.relevanceScore;

      for (const rule of boostRules) {
        if (rule.pattern.test(result.filePath)) {
          boostedScore *= (1 + rule.boost);
        }
      }

      return {
        ...result,
        relevanceScore: Math.min(1, boostedScore), // Cap at 1.0
      };
    });
  }

  /**
   * Diversify results to avoid clustering similar results
   */
  diversifyResults(
    results: SearchResult[],
    maxResult: number = 10,
    similarityThreshold: number = 0.85
  ): SearchResult[] {
    if (results.length <= maxResult) {
      return results;
    }

    const selected: SearchResult[] = [];

    for (const result of results) {
      // Check if too similar to already selected
      let tooSimilar = false;
      for (const selectedResult of selected) {
        const similarity = SimilarityScorer.cosineSimilarity(
          result.vector,
          selectedResult.vector
        );
        if (similarity > similarityThreshold) {
          tooSimilar = true;
          break;
        }
      }

      if (!tooSimilar) {
        selected.push(result);
      }

      if (selected.length >= maxResult) {
        break;
      }
    }

    return selected;
  }

  /**
   * Generate ranking explanation for a result
   */
  explainScore(
    result: SearchResult,
    queryVector: number[],
    queryText: string,
    weights: Partial<RankingWeights> = {}
  ): {
    components: Record<string, number>;
    explanation: string;
  } {
    const mergedWeights = { ...this.defaultWeights, ...weights };

    const semanticScore = SimilarityScorer.cosineSimilarity(
      queryVector,
      result.vector
    );
    const syntacticScore = SimilarityScorer.jaroWinklerSimilarity(
      queryText,
      result.text.substring(0, Math.min(100, result.text.length))
    );
    const tokenScore = SimilarityScorer.tokenOverlapSimilarity(
      queryText,
      result.text
    );

    const components = {
      semantic: semanticScore * mergedWeights.semanticSimilarity,
      syntactic: syntacticScore * mergedWeights.syntacticSimilarity,
      tokenOverlap: tokenScore * mergedWeights.tokenOverlap,
      popularity: (result.popularity || 0.5) * mergedWeights.popularity,
    };

    const explanation = `
Result: ${result.filePath}:${result.lineNumber || 'N/A'}
Relevance Score: ${result.relevanceScore.toFixed(3)} (${(result.relevanceScore * 100).toFixed(1)}%)

Component Scores:
  - Semantic Similarity: ${semanticScore.toFixed(3)} × ${mergedWeights.semanticSimilarity} = ${components.semantic.toFixed(3)}
  - Syntactic Similarity: ${syntacticScore.toFixed(3)} × ${mergedWeights.syntacticSimilarity} = ${components.syntactic.toFixed(3)}
  - Token Overlap: ${tokenScore.toFixed(3)} × ${mergedWeights.tokenOverlap} = ${components.tokenOverlap.toFixed(3)}
  - Popularity: ${(result.popularity || 0.5).toFixed(3)} × ${mergedWeights.popularity} = ${components.popularity.toFixed(3)}

Total: ${Object.values(components)
      .reduce((a, b) => a + b, 0)
      .toFixed(3)}
    `;

    return {
      components,
      explanation: explanation.trim(),
    };
  }

  /**
   * Set default ranking weights
   */
  setDefaultWeights(weights: Partial<RankingWeights>): void {
    this.defaultWeights = { ...this.defaultWeights, ...weights };
  }
}
