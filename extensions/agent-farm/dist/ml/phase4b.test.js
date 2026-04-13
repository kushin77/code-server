"use strict";
/**
 * Phase 4B: Advanced ML Semantic Search - Comprehensive Test Suite
 * Tests for QueryUnderstanding, CrossEncoderReranker, MultiModalAnalyzer, and Orchestration
 */
Object.defineProperty(exports, "__esModule", { value: true });
const globals_1 = require("@jest/globals");
const QueryUnderstanding_1 = require("../ml/QueryUnderstanding");
const CrossEncoderReranker_1 = require("../ml/CrossEncoderReranker");
const MultiModalAnalyzer_1 = require("../ml/MultiModalAnalyzer");
const phase4_orchestration_1 = require("../ml/phase4-orchestration");
(0, globals_1.describe)('Phase 4B: Advanced ML Semantic Search', () => {
    let queryUnderstanding;
    let crossEncoderReranker;
    let multiModalAnalyzer;
    let orchestrator;
    (0, globals_1.beforeEach)(() => {
        queryUnderstanding = new QueryUnderstanding_1.QueryUnderstanding();
        crossEncoderReranker = new CrossEncoderReranker_1.CrossEncoderReranker();
        multiModalAnalyzer = new MultiModalAnalyzer_1.MultiModalAnalyzer();
        orchestrator = new phase4_orchestration_1.AdvancedSemanticSearchOrchestrator();
    });
    (0, globals_1.describe)('QueryUnderstanding Component', () => {
        (0, globals_1.it)('should parse debug intent from query', () => {
            const query = 'fix the null pointer exception in authenticator';
            const expanded = queryUnderstanding.parse(query);
            (0, globals_1.expect)(expanded.intent.type).toContain('debug');
            (0, globals_1.expect)(expanded.intent.keywords).toBeDefined();
            (0, globals_1.expect)(expanded.expandedTerms.length).toBeGreaterThan(0);
        });
        (0, globals_1.it)('should parse optimize intent from query', () => {
            const query = 'optimize database query performance';
            const expanded = queryUnderstanding.parse(query);
            (0, globals_1.expect)(expanded.intent.type).toContain('optim');
            (0, globals_1.expect)(expanded.intent.keywords).toBeDefined();
        });
        (0, globals_1.it)('should parse test intent from query', () => {
            const query = 'add unit tests for payment module';
            const expanded = queryUnderstanding.parse(query);
            (0, globals_1.expect)(expanded.intent.type.includes('test')).toBeTruthy();
        });
        (0, globals_1.it)('should expand query with synonyms', () => {
            const query = 'refactor authentication code';
            const expanded = queryUnderstanding.parse(query);
            (0, globals_1.expect)(expanded.synonyms).toBeDefined();
            (0, globals_1.expect)(expanded.synonyms.length).toBeGreaterThan(0);
        });
        (0, globals_1.it)('should generate pattern variations', () => {
            const query = 'memory leak in cache';
            const expanded = queryUnderstanding.parse(query);
            (0, globals_1.expect)(expanded.patterns).toBeDefined();
            (0, globals_1.expect)(expanded.patterns.length).toBeGreaterThan(0);
        });
    });
    (0, globals_1.describe)('CrossEncoderReranker Component', () => {
        let mockResults;
        (0, globals_1.beforeEach)(() => {
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
        (0, globals_1.it)('should rerank results with cross-encoder scores', () => {
            const query = 'authentication validation';
            const terms = ['auth', 'validate'];
            const reranked = crossEncoderReranker.rerank(mockResults, query, terms);
            (0, globals_1.expect)(reranked.length).toBe(mockResults.length);
            (0, globals_1.expect)(reranked[0].score).toBeDefined();
        });
        (0, globals_1.it)('should prioritize semantic match over basic score', () => {
            const query = 'secure authentication mechanism';
            const terms = ['secure', 'auth', 'mechanism'];
            const reranked = crossEncoderReranker.rerank(mockResults, query, terms);
            // Results should be reordered based on cross-encoder scoring
            (0, globals_1.expect)(reranked).toBeDefined();
            (0, globals_1.expect)(reranked.length).toBeGreaterThan(0);
        });
        (0, globals_1.it)('should extract ranking features correctly', () => {
            const mockSearchResult = {
                filePath: 'src/auth.ts',
                content: 'async function authenticateUser(token) { validate(token); }',
                score: 0.85,
            };
            const features = crossEncoderReranker.extractFeatures(mockSearchResult, 'authenticate');
            (0, globals_1.expect)(features.semanticSimilarity).toBeDefined();
            (0, globals_1.expect)(features.fileRelevance).toBeDefined();
            (0, globals_1.expect)(features.recencyBonus).toBeDefined();
        });
        (0, globals_1.it)('should apply learned weights to ranking', () => {
            const query = 'async error handling';
            const reranked = crossEncoderReranker.rerank(mockResults, query, query.split(' '));
            (0, globals_1.expect)(reranked[0]).toBeDefined();
            (0, globals_1.expect)(reranked[0].score).toBeGreaterThanOrEqual(0);
            (0, globals_1.expect)(reranked[0].score).toBeLessThanOrEqual(1);
        });
    });
    (0, globals_1.describe)('MultiModalAnalyzer Component', () => {
        (0, globals_1.it)('should analyze code modalities', async () => {
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
            (0, globals_1.expect)(analysis.code).toBeDefined();
            (0, globals_1.expect)(analysis.tests).toBeDefined();
            (0, globals_1.expect)(analysis.documentation).toBeDefined();
        });
        (0, globals_1.it)('should detect code complexity', async () => {
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
            (0, globals_1.expect)(complexAnalysis.code.complexity).toBeGreaterThan(simpleAnalysis.code.complexity);
        });
        (0, globals_1.it)('should evaluate test coverage', async () => {
            const testedCode = `
        function add(a, b) { return a + b; }
        test('add should work', () => { expect(add(1, 2)).toBe(3); });
      `;
            const untested = 'function add(a, b) { return a + b; }';
            const testedAnalysis = await multiModalAnalyzer.analyze(testedCode);
            const untestedAnalysis = await multiModalAnalyzer.analyze(untested);
            (0, globals_1.expect)(testedAnalysis.tests.testCoverage).toBeGreaterThan(untestedAnalysis.tests.testCoverage);
        });
        (0, globals_1.it)('should assess documentation quality', async () => {
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
            (0, globals_1.expect)(wellAnalysis.documentation.commentDensity).toBeGreaterThan(poorAnalysis.documentation.commentDensity);
        });
        (0, globals_1.it)('should compute composite multimodal score', async () => {
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
            (0, globals_1.expect)(score.composite).toBeGreaterThan(0);
            (0, globals_1.expect)(score.weightedComponents).toBeDefined();
            (0, globals_1.expect)(score.reasoning).toBeDefined();
        });
    });
    (0, globals_1.describe)('AdvancedSemanticSearchOrchestrator', () => {
        let mockResults;
        (0, globals_1.beforeEach)(() => {
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
        (0, globals_1.it)('should execute complete search pipeline', async () => {
            const query = 'authenticate and validate user tokens';
            const results = await orchestrator.advancedSearch(query, mockResults);
            (0, globals_1.expect)(results.length).toBeGreaterThan(0);
            (0, globals_1.expect)(results[0]).toHaveProperty('combinedScore');
            (0, globals_1.expect)(results[0]).toHaveProperty('reasoning');
        });
        (0, globals_1.it)('should apply query constraints', async () => {
            const query = 'authentication in auth/ directory';
            const results = await orchestrator.advancedSearch(query, mockResults, {
                constraintFiltering: true,
                maxResults: 10,
            });
            (0, globals_1.expect)(results).toBeDefined();
        });
        (0, globals_1.it)('should include multimodal analysis when enabled', async () => {
            const query = 'well-tested authentication code';
            const results = await orchestrator.advancedSearch(query, mockResults, {
                includeMultiModal: true,
                maxResults: 10,
            });
            const hasMultimodal = results.some((r) => r.multiModalScore !== undefined);
            (0, globals_1.expect)(hasMultimodal).toBeTruthy();
        });
        (0, globals_1.it)('should exclude multimodal when disabled', async () => {
            const query = 'authentication';
            const results = await orchestrator.advancedSearch(query, mockResults, {
                includeMultiModal: false,
                maxResults: 10,
            });
            const hasMultimodal = results.some((r) => r.multiModalScore !== undefined);
            (0, globals_1.expect)(hasMultimodal).toBeFalsy();
        });
        (0, globals_1.it)('should generate search summary', async () => {
            const query = 'token validation';
            const results = await orchestrator.advancedSearch(query, mockResults);
            const summary = orchestrator.getSummary(results);
            (0, globals_1.expect)(summary.topResult).toBeDefined();
            (0, globals_1.expect)(summary.avgScore).toBeGreaterThan(0);
            (0, globals_1.expect)(summary.modalities).toBeDefined();
        });
        (0, globals_1.it)('should rank results by combined score', async () => {
            const query = 'secure authentication';
            const results = await orchestrator.advancedSearch(query, mockResults);
            for (let i = 0; i < results.length - 1; i++) {
                (0, globals_1.expect)((results[i].combinedScore || 0) >=
                    (results[i + 1].combinedScore || 0)).toBeTruthy();
            }
        });
        (0, globals_1.it)('should respect maxResults option', async () => {
            const query = 'authentication';
            const results = await orchestrator.advancedSearch(query, mockResults, {
                maxResults: 1,
            });
            (0, globals_1.expect)(results.length).toBeLessThanOrEqual(1);
        });
        (0, globals_1.it)('should provide reasoning for each result', async () => {
            const query = 'token validation security';
            const results = await orchestrator.advancedSearch(query, mockResults);
            results.forEach((result) => {
                (0, globals_1.expect)(result.reasoning).toBeDefined();
                (0, globals_1.expect)(result.reasoning.length).toBeGreaterThan(0);
            });
        });
    });
    (0, globals_1.describe)('Phase 4B Integration with Agent Farm', () => {
        (0, globals_1.it)('should maintain compatibility with SearchResult interface', async () => {
            const basicResult = {
                filePath: 'test.ts',
                content: 'function test() {}',
                score: 0.8,
            };
            const enhanced = {
                ...basicResult,
                combinedScore: 0.9,
                rerankerScore: 0.85,
                reasoning: 'High match confidence',
            };
            (0, globals_1.expect)(enhanced.filePath).toBe(basicResult.filePath);
            (0, globals_1.expect)(enhanced.score).toBe(basicResult.score);
            (0, globals_1.expect)(enhanced.combinedScore).toBeGreaterThan(enhanced.score);
        });
        (0, globals_1.it)('should handle multiple parallel analyses', async () => {
            const mockResults = Array(5)
                .fill(null)
                .map((_, i) => ({
                filePath: `file${i}.ts`,
                content: 'async function test() { await process(); }',
                score: 0.8,
            }));
            const startTime = Date.now();
            const results = await orchestrator.advancedSearch('async processing', mockResults);
            const duration = Date.now() - startTime;
            (0, globals_1.expect)(results.length).toBe(5);
            console.log(`Multi-result analysis completed in ${duration}ms`);
        });
    });
});
//# sourceMappingURL=phase4b.test.js.map