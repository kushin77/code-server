/**
 * Phase 4A & 4B: ML Semantic Search Foundation & Advanced Features
 * Public API for ML components
 */

// Phase 4A - Foundation
export { MLEmbeddingEngine, EmbeddingRequest, EmbeddingResult, EmbeddingCache } from './MLEmbeddingEngine';
export { SimilarityScorer } from './SimilarityScorer';
export { RelevanceRanker, SearchResult, RankingWeights } from './RelevanceRanker';

// Phase 4B - Advanced
export { QueryUnderstanding, QueryIntent, QueryConstraint, ExpandedQuery } from './QueryUnderstanding';
export { CrossEncoderReranker, RankingFeatures, CrossEncodedResult } from './CrossEncoderReranker';
export { MultiModalAnalyzer, CodeModalities, CodeAnalysis, TestAnalysis, DocumentationAnalysis, PatternAnalysis, MultiModalScore } from './MultiModalAnalyzer';
