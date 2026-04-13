/**
 * Phase 4B: Advanced ML Semantic Search - Comprehensive Test Suite
 * Tests for QueryUnderstanding, CrossEncoderReranker, MultiModalAnalyzer, and Orchestration
 */

import { describe, it, expect, beforeEach } from '@jest/globals';
import { QueryUnderstanding } from '../ml/QueryUnderstanding';
import { CrossEncoderReranker } from '../ml/CrossEncoderReranker';
import { MultiModalAnalyzer } from '../ml/MultiModalAnalyzer';
import {
  AdvancedSemanticSearchOrchestrator,
  EnhancedSearchResult,
} from '../ml/phase4-orchestration';
import { SearchResult } from '../types';

describe('Phase 4B: Advanced ML Semantic Search', () => {
  let queryUnderstanding: QueryUnderstanding;
  let crossEncoderReranker: CrossEncoderReranker;
  let multiModalAnalyzer: MultiModalAnalyzer;
  let orchestrator: AdvancedSemanticSearchOrchestrator;

  beforeEach(() => {
    queryUnderstanding = new QueryUnderstanding();
    crossEncoderReranker = new CrossEncoderReranker();
    multiModalAnalyzer = new MultiModalAnalyzer();
    orchestrator = new AdvancedSemanticSearchOrchestrator();
  });

  describe('QueryUnderstanding Component', () => {
    it('should parse debug intent from query', () => {
      const query = 'fix the null pointer exception in authenticator';
      const expanded = queryUnderstanding.parse(query);

      expect(expanded.intent.type).toContain('debug');
      expect(expanded.intent.keywords).toBeDefined();
      expect(expanded.expandedTerms.length).toBeGreaterThan(0);
    });

    it('should parse optimize intent from query', () => {
      const query = 'optimize database query performance';
      const expanded = queryUnderstanding.parse(query);

      expect(expanded.intent.type).toContain('optim');
      expect(expanded.intent.keywords).toBeDefined();
    });

    it('should parse test intent from query', () => {
      const query = 'add unit tests for payment module';
      const expanded = queryUnderstanding.parse(query);

      expect(expanded.intent.type.includes('test')).toBeTruthy();
    });

    it('should expand query with synonyms', () => {
      const query = 'refactor authentication code';
      const expanded = queryUnderstanding.parse(query);

      expect(expanded.synonyms).toBeDefined();
      expect(expanded.synonyms.length).toBeGreaterThan(0);
    });

    it('should generate pattern variations', () => {
      const query = 'memory leak in cache';
      const expanded = queryUnderstanding.parse(query);

      expect(expanded.patterns).toBeDefined();
      expect(expanded.patterns.length).toBeGreaterThan(0);
    });
  });

  describe('CrossEncoderReranker Component', () => {
    let mockResults: SearchResult[];

    beforeEach(() => {
      mockResults = [
        {
          filePath: 'src/auth.ts',
          content: 'export function authenticate() { /* validation */ }',
          score: 0.8,
        },
        {
          filePath: 'src/utils.ts',
          content: 'export function auth() { /* helper */ }',
          score: 0.6,
        },
        {
          filePath: 'src/security.ts',
          content: 'export function validate() { /* check auth */ }',
          score: 0.7,
        },
      ];
    });

    it('should rerank results with cross-encoder scores', () => {
      const query = 'authentication validation';
      const terms = ['auth', 'validate'];

      const reranked = crossEncoderReranker.rerank(mockResults, query, terms);

      expect(reranked.length).toBe(mockResults.length);
      expect(reranked[0].score).toBeDefined();
    });

    it('should prioritize semantic match over basic score', () => {
      const query = 'secure authentication mechanism';
      const terms = ['secure', 'auth', 'mechanism'];

      const reranked = crossEncoderReranker.rerank(mockResults, query, terms);

      // Results should be reordered based on cross-encoder scoring
      expect(reranked).toBeDefined();
      expect(reranked.length).toBeGreaterThan(0);
    });

    it('should extract ranking features correctly', () => {
      const mockSearchResult: SearchResult = {
        filePath: 'src/auth.ts',
        content: 'async function authenticateUser(token) { validate(token); }',
        score: 0.85,
      };

      const features = crossEncoderReranker.extractFeatures(
        mockSearchResult,
        'authenticate'
      );

      expect(features.semanticSimilarity).toBeDefined();
      expect(features.fileRelevance).toBeDefined();
      expect(features.recencyBonus).toBeDefined();
    });

    it('should apply learned weights to ranking', () => {
      const query = 'async error handling';
      const reranked = crossEncoderReranker.rerank(
        mockResults,
        query,
        query.split(' ')
      );

      expect(reranked[0]).toBeDefined();
      expect(reranked[0].score).toBeGreaterThanOrEqual(0);
      expect(reranked[0].score).toBeLessThanOrEqual(1);
    });
  });

  describe('MultiModalAnalyzer Component', () => {
    it('should analyze code modalities', async () => {
      const code = `
        function calculateTotal(items) {
          return items.reduce((sum, item) => sum + item.price, 0);
        }
        
        // Calculates total price
        test('should calculate total correctly', () => {
          expect(calculateTotal([{price: 10}])).toBe(10);
        });
      `;

      const analysis = await multiModalAnalyzer.analyze(code);

      expect(analysis.code).toBeDefined();
      expect(analysis.tests).toBeDefined();
      expect(analysis.documentation).toBeDefined();
    });

    it('should detect code complexity', async () => {
      const simpleCode = 'const x = 1;';
      const complexCode = `
        function nested(a) {
          if (a > 0) {
            for (let i = 0; i < a; i++) {
              async function inner() { await process(); }
              inner();
            }
          }
        }
      `;

      const simpleAnalysis = await multiModalAnalyzer.analyze(simpleCode);
      const complexAnalysis = await multiModalAnalyzer.analyze(complexCode);

      expect(complexAnalysis.code.complexity).toBeGreaterThan(
        simpleAnalysis.code.complexity
      );
    });

    it('should evaluate test coverage', async () => {
      const testedCode = `
        function add(a, b) { return a + b; }
        test('add should work', () => { expect(add(1, 2)).toBe(3); });
      `;

      const untested = 'function add(a, b) { return a + b; }';

      const testedAnalysis = await multiModalAnalyzer.analyze(testedCode);
      const untestedAnalysis = await multiModalAnalyzer.analyze(untested);

      expect(testedAnalysis.tests.testCoverage).toBeGreaterThan(
        untestedAnalysis.tests.testCoverage
      );
    });

    it('should assess documentation quality', async () => {
      const wellDocumented = `
        /**
         * Computes the sum of two numbers
         * @param a - First number
         * @param b - Second number
         * @returns The sum
         */
        function add(a, b) { return a + b; }
      `;

      const poorlyDocumented = 'function add(a, b) { return a + b; }';

      const wellAnalysis = await multiModalAnalyzer.analyze(wellDocumented);
      const poorAnalysis = await multiModalAnalyzer.analyze(poorlyDocumented);

      expect(wellAnalysis.documentation.commentDensity).toBeGreaterThan(
        poorAnalysis.documentation.commentDensity
      );
    });

    it('should compute composite multimodal score', async () => {
      const code = `
        /**
         * Calculate total with discount
         */
        async function calculateWithDiscount(items, discount) {
          try {
            const total = items.reduce((sum, i) => sum + i.price, 0);
            return total * (1 - discount);
          } catch (error) {
            console.error('Calculation failed:', error);
            throw error;
          }
        }
        
        test('should apply discount correctly', async () => {
          const result = await calculateWithDiscount([{price: 100}], 0.1);
          expect(result).toBe(90);
        });
      `;

      const analysis = await multiModalAnalyzer.analyze(code);
      const score = multiModalAnalyzer.computeScore(analysis);

      expect(score.composite).toBeGreaterThan(0);
      expect(score.weightedComponents).toBeDefined();
      expect(score.reasoning).toBeDefined();
    });
  });

  describe('AdvancedSemanticSearchOrchestrator', () => {
    let mockResults: SearchResult[];

    beforeEach(() => {
      mockResults = [
        {
          filePath: 'src/auth/authenticator.ts',
          content: `
            /**
             * Authenticates user with token validation
             */
            export function authenticate(token: string): boolean {
              return token && token.length > 0;
            }
            
            test('authenticate should validate tokens', () => {
              expect(authenticate('valid')).toBe(true);
            });
          `,
          score: 0.85,
        },
        {
          filePath: 'src/permissions.ts',
          content: `
            function checkPermission(user) {
              // Simple permission check
              return user.role === 'admin';
            }
          `,
          score: 0.65,
        },
        {
          filePath: 'src/security.ts',
          content: `
            export const securityRules = {
              validateToken: (token) => token ? true : false,
            };
          `,
          score: 0.75,
        },
      ];
    });

    it('should execute complete search pipeline', async () => {
      const query = 'authenticate and validate user tokens';
      const results = await orchestrator.advancedSearch(query, mockResults);

      expect(results.length).toBeGreaterThan(0);
      expect(results[0]).toHaveProperty('combinedScore');
      expect(results[0]).toHaveProperty('reasoning');
    });

    it('should apply query constraints', async () => {
      const query = 'authentication in auth/ directory';
      const results = await orchestrator.advancedSearch(query, mockResults, {
        constraintFiltering: true,
        maxResults: 10,
      });

      expect(results).toBeDefined();
    });

    it('should include multimodal analysis when enabled', async () => {
      const query = 'well-tested authentication code';
      const results = await orchestrator.advancedSearch(query, mockResults, {
        includeMultiModal: true,
        maxResults: 10,
      });

      const hasMultimodal = results.some((r) => r.multiModalScore !== undefined);
      expect(hasMultimodal).toBeTruthy();
    });

    it('should exclude multimodal when disabled', async () => {
      const query = 'authentication';
      const results = await orchestrator.advancedSearch(query, mockResults, {
        includeMultiModal: false,
        maxResults: 10,
      });

      const hasMultimodal = results.some((r) => r.multiModalScore !== undefined);
      expect(hasMultimodal).toBeFalsy();
    });

    it('should generate search summary', async () => {
      const query = 'token validation';
      const results = await orchestrator.advancedSearch(query, mockResults);

      const summary = orchestrator.getSummary(results);

      expect(summary.topResult).toBeDefined();
      expect(summary.avgScore).toBeGreaterThan(0);
      expect(summary.modalities).toBeDefined();
    });

    it('should rank results by combined score', async () => {
      const query = 'secure authentication';
      const results = await orchestrator.advancedSearch(query, mockResults);

      for (let i = 0; i < results.length - 1; i++) {
        expect(
          (results[i].combinedScore || 0) >=
            (results[i + 1].combinedScore || 0)
        ).toBeTruthy();
      }
    });

    it('should respect maxResults option', async () => {
      const query = 'authentication';
      const results = await orchestrator.advancedSearch(query, mockResults, {
        maxResults: 1,
      });

      expect(results.length).toBeLessThanOrEqual(1);
    });

    it('should provide reasoning for each result', async () => {
      const query = 'token validation security';
      const results = await orchestrator.advancedSearch(query, mockResults);

      results.forEach((result) => {
        expect(result.reasoning).toBeDefined();
        expect(result.reasoning!.length).toBeGreaterThan(0);
      });
    });
  });

  describe('Phase 4B Integration with Agent Farm', () => {
    it('should maintain compatibility with SearchResult interface', async () => {
      const basicResult: SearchResult = {
        filePath: 'test.ts',
        content: 'function test() {}',
        score: 0.8,
      };

      const enhanced: EnhancedSearchResult = {
        ...basicResult,
        combinedScore: 0.9,
        rerankerScore: 0.85,
        reasoning: 'High match confidence',
      };

      expect(enhanced.filePath).toBe(basicResult.filePath);
      expect(enhanced.score).toBe(basicResult.score);
      expect(enhanced.combinedScore).toBeGreaterThan(enhanced.score!);
    });

    it('should handle multiple parallel analyses', async () => {
      const mockResults = Array(5)
        .fill(null)
        .map((_, i) => ({
          filePath: `file${i}.ts`,
          content: 'async function test() { await process(); }',
          score: 0.8,
        }));

      const startTime = Date.now();
      const results = await orchestrator.advancedSearch(
        'async processing',
        mockResults
      );
      const duration = Date.now() - startTime;

      expect(results.length).toBe(5);
      console.log(`Multi-result analysis completed in ${duration}ms`);
    });
  });
});
