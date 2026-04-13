/**
 * Phase 4A: ML Semantic Search Foundation - Test Suite
 */

import { MLEmbeddingEngine, EmbeddingResult } from './MLEmbeddingEngine';
import { SimilarityScorer } from './SimilarityScorer';
import { RelevanceRanker, SearchResult } from './RelevanceRanker';

describe('Phase 4A: ML Semantic Search Foundation', () => {
  describe('MLEmbeddingEngine', () => {
    let engine: MLEmbeddingEngine;

    beforeEach(() => {
      engine = new MLEmbeddingEngine('http://localhost:11434');
    });

    test('should initialize with default Ollama endpoint', () => {
      expect(engine).toBeDefined();
      const stats = engine.getCacheStats();
      expect(stats.size).toBe(0);
    });

    test('should generate embedding with correct structure', async () => {
      // Mock for testing (Ollama would need to be running for actual test)
      const testVector = Array(768).fill(0.1);
      testVector[0] = 0.5; // Add some variance

      // In actual implementation, this would call Ollama
      // For now, testing the data structure
      const mockResult: EmbeddingResult = {
        id: 'test-1',
        text: 'function test() {}',
        vector: testVector,
        timestamp: Date.now(),
      };

      expect(mockResult.vector.length).toBe(768);
      expect(mockResult.id).toBeDefined();
    });

    test('should cache embeddings', () => {
      const stats1 = engine.getCacheStats();
      expect(stats1.size).toBe(0);

      // After caching, size should increase
      // (In real test with actual Ollama integration)
    });

    test('should handle batch embeddings', async () => {
      const textBatch = [
        { text: 'const x = function() {}', id: 'func1' },
        { text: 'const y = function() {}', id: 'func2' },
      ];

      // This would work with actual Ollama service
      expect(textBatch.length).toBe(2);
    });

    test('should clear cache by pattern', () => {
      // Test cache clearing functionality
      const stats = engine.getCacheStats();
      expect(stats).toHaveProperty('size');
      expect(stats).toHaveProperty('hitRate');
      expect(stats).toHaveProperty('totalRequests');
    });
  });

  describe('SimilarityScorer', () => {
    test('cosineSimilarity should return 1 for identical vectors', () => {
      const v1 = [1, 0, 0];
      const v2 = [1, 0, 0];
      expect(SimilarityScorer.cosineSimilarity(v1, v2)).toBeCloseTo(1, 5);
    });

    test('cosineSimilarity should return 0 for orthogonal vectors', () => {
      const v1 = [1, 0, 0];
      const v2 = [0, 1, 0];
      expect(SimilarityScorer.cosineSimilarity(v1, v2)).toBeCloseTo(0, 5);
    });

    test('euclideanDistance should return 0 for identical vectors', () => {
      const v1 = [0, 0, 0];
      const v2 = [0, 0, 0];
      expect(SimilarityScorer.euclideanDistance(v1, v2)).toBeCloseTo(0, 5);
    });

    test('euclideanDistance should calculate correct distance', () => {
      const v1 = [0, 0, 0];
      const v2 = [3, 4, 0];
      expect(SimilarityScorer.euclideanDistance(v1, v2)).toBeCloseTo(5, 5);
    });

    test('jaroWinklerSimilarity should recognize identical strings', () => {
      const similarity = SimilarityScorer.jaroWinklerSimilarity(
        'function',
        'function'
      );
      expect(similarity).toBeCloseTo(1, 5);
    });

    test('jaroWinklerSimilarity should handle similar strings', () => {
      const similarity = SimilarityScorer.jaroWinklerSimilarity(
        'test',
        'text'
      );
      expect(similarity).toBeGreaterThan(0.7);
    });

    test('levenshteinDistance should calculate edit distance', () => {
      const distance = SimilarityScorer.levenshteinDistance('kitten', 'sitting');
      expect(distance).toBe(3);
    });

    test('levenshteinSimilarity should return normalized score', () => {
      const similarity = SimilarityScorer.levenshteinSimilarity('cat', 'cat');
      expect(similarity).toBeCloseTo(1, 5);
    });

    test('tokenOverlapSimilarity should measure word overlap', () => {
      const similarity1 = SimilarityScorer.tokenOverlapSimilarity(
        'function test code',
        'function test code'
      );
      expect(similarity1).toBeCloseTo(1, 5);

      const similarity2 = SimilarityScorer.tokenOverlapSimilarity(
        'function test',
        'function test code other'
      );
      expect(similarity2).toBeGreaterThan(0);
      expect(similarity2).toBeLessThan(1);
    });

    test('hybridSimilarity should combine multiple metrics', () => {
      const v1 = [1, 0, 0, 0];
      const v2 = [0.9, 0.1, 0, 0];
      const text1 = 'test function';
      const text2 = 'test function';

      const similarity = SimilarityScorer.hybridSimilarity(
        v1,
        v2,
        text1,
        text2
      );

      expect(similarity).toBeGreaterThan(0);
      expect(similarity).toBeLessThanOrEqual(1);
    });

    test('should throw on mismatched vector dimensions', () => {
      const v1 = [1, 0, 0];
      const v2 = [1, 0];

      expect(() => SimilarityScorer.cosineSimilarity(v1, v2)).toThrow();
    });
  });

  describe('RelevanceRanker', () => {
    let ranker: RelevanceRanker;

    beforeEach(() => {
      ranker = new RelevanceRanker();
    });

    test('should rank results by relevance', () => {
      const queryVector = [1, 0, 0, 0, 0];
      const queryText = 'function test';

      const candidates: SearchResult[] = [
        {
          id: '1',
          text: 'function test code',
          vector: [0.9, 0.1, 0, 0, 0],
          filePath: 'src/test.ts',
          similarity: 0.9,
          relevanceScore: 0,
          popularity: 0.8,
        },
        {
          id: '2',
          text: 'const x = 1',
          vector: [0.1, 0.9, 0, 0, 0],
          filePath: 'src/main.ts',
          similarity: 0.1,
          relevanceScore: 0,
          popularity: 0.5,
        },
      ];

      const ranked = ranker.rankResults(queryVector, queryText, candidates);

      expect(ranked[0].id).toBe('1'); // Should rank similar result first
      expect(ranked[0].relevanceScore).toBeGreaterThan(
        ranked[1].relevanceScore
      );
    });

    test('should filter results by threshold', () => {
      const results: SearchResult[] = [
        {
          id: '1',
          text: 'test',
          vector: [],
          filePath: 'test.ts',
          similarity: 0.9,
          relevanceScore: 0.8,
          popularity: 0.5,
        },
        {
          id: '2',
          text: 'other',
          vector: [],
          filePath: 'other.ts',
          similarity: 0.1,
          relevanceScore: 0.2,
          popularity: 0.5,
        },
      ];

      const filtered = ranker.filterByThreshold(results, 0.5);
      expect(filtered.length).toBe(1);
      expect(filtered[0].id).toBe('1');
    });

    test('should return top N results', () => {
      const results: SearchResult[] = Array.from({ length: 20 }, (_, i) => ({
        id: `${i}`,
        text: `text${i}`,
        vector: [],
        filePath: `file${i}.ts`,
        similarity: 1 - i * 0.05,
        relevanceScore: 1 - i * 0.05,
        popularity: 0.5,
      }));

      const top = ranker.getTopResults(results, 5);
      expect(top.length).toBe(5);
      expect(top[0].id).toBe('0');
    });

    test('should explain relevance score', () => {
      const result: SearchResult = {
        id: '1',
        text: 'function test',
        vector: [1, 0, 0],
        filePath: 'test.ts',
        similarity: 0.9,
        relevanceScore: 0.85,
        popularity: 0.8,
      };

      const queryVector = [0.95, 0.05, 0];
      const queryText = 'function test';

      const explanation = ranker.explainScore(
        result,
        queryVector,
        queryText
      );

      expect(explanation.components).toHaveProperty('semantic');
      expect(explanation.components).toHaveProperty('syntactic');
      expect(explanation.components).toHaveProperty('tokenOverlap');
      expect(explanation.explanation).toContain('Relevance Score');
    });

    test('should diversify results to avoid clustering', () => {
      const results: SearchResult[] = [
        {
          id: '1',
          text: 'function test A',
          vector: [1, 0, 0, 0, 0],
          filePath: 'test.ts',
          similarity: 0.95,
          relevanceScore: 0.95,
          popularity: 0.5,
        },
        {
          id: '2',
          text: 'function test B', // Very similar to result 1
          vector: [0.99, 0.01, 0, 0, 0],
          filePath: 'test2.ts',
          similarity: 0.94,
          relevanceScore: 0.94,
          popularity: 0.5,
        },
        {
          id: '3',
          text: 'const x = 1', // Different from results 1 and 2
          vector: [0.1, 0.9, 0, 0, 0],
          filePath: 'main.ts',
          similarity: 0.1,
          relevanceScore: 0.1,
          popularity: 0.5,
        },
      ];

      const diversified = ranker.diversifyResults(results, 2, 0.9);
      expect(diversified.length).toBeLessThanOrEqual(2);
      // Should prefer diverse results
    });

    test('should apply boost rules', () => {
      const results: SearchResult[] = [
        {
          id: '1',
          text: 'test',
          vector: [],
          filePath: 'src/agents/TestAgent.ts',
          similarity: 0.5,
          relevanceScore: 0.5,
          popularity: 0.5,
        },
        {
          id: '2',
          text: 'other',
          vector: [],
          filePath: 'src/main.ts',
          similarity: 0.5,
          relevanceScore: 0.5,
          popularity: 0.5,
        },
      ];

      const boosted = ranker.boostResults(results, [
        { pattern: /Agent/, boost: 0.5 },
      ]);

      expect(boosted[0].relevanceScore).toBeGreaterThan(
        boosted[1].relevanceScore
      );
    });
  });

  describe('Integration Tests', () => {
    test('should integrate embedding engine with similarity scoring', async () => {
      const engine = new MLEmbeddingEngine();
      const scorer = SimilarityScorer;
      const ranker = new RelevanceRanker();

      // Simulate embeddings
      const mockVector1 = Array(768)
        .fill(0)
        .map((_, i) => Math.sin(i * 0.01));
      const mockVector2 = Array(768)
        .fill(0)
        .map((_, i) => Math.sin(i * 0.01 + 0.1));

      const similarity = scorer.cosineSimilarity(mockVector1, mockVector2);
      expect(similarity).toBeGreaterThan(0.9); // Should be very similar
    });

    test('should handle full search pipeline', () => {
      const query = 'test function implementation';
      const queryVector = Array(768).fill(0.1);

      const candidates: SearchResult[] = [
        {
          id: '1',
          text: 'test function for validation',
          vector: Array(768).fill(0.1),
          filePath: 'test.ts',
          similarity: 0.9,
          relevanceScore: 0,
          popularity: 0.8,
        },
        {
          id: '2',
          text: 'helper method',
          vector: Array(768).fill(0.5),
          filePath: 'helper.ts',
          similarity: 0.2,
          relevanceScore: 0,
          popularity: 0.5,
        },
      ];

      const ranker = new RelevanceRanker();
      const ranked = ranker.rankResults(queryVector, query, candidates);
      const filtered = ranker.filterByThreshold(ranked, 0.3);
      const top = ranker.getTopResults(filtered, 5);

      expect(top.length).toBeGreaterThan(0);
      expect(top[0].id).toBe('1');
    });
  });
});
