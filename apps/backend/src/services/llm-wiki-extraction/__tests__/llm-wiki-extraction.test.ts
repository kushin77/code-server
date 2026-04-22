#!/usr/bin/env node
// @file        apps/backend/src/services/llm-wiki-extraction/__tests__/llm-wiki-extraction.test.ts
// @module      collaboration/llm-wiki-extraction
// @description LLM wiki extraction service tests
// @owner       collab-3.6
// @status      active

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { LLMWikiExtractionService } from '../index';
import { Pool } from 'pg';

vi.mock('../../../lib/logger', () => ({
  getLogger: vi.fn(() => ({
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
  })),
}));

describe('LLMWikiExtractionService', () => {
  let service: LLMWikiExtractionService;
  let mockPool: Partial<Pool>;
  let mockClient: any;

  beforeEach(() => {
    mockClient = {
      query: vi.fn(),
      release: vi.fn(),
    };

    mockPool = {
      connect: vi.fn(async () => mockClient),
    } as unknown as Pool;

    service = new LLMWikiExtractionService(mockPool as Pool);
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('initialization', () => {
    it('should initialize tables with pgvector on first call', async () => {
      mockClient.query.mockResolvedValueOnce({}); // BEGIN
      mockClient.query.mockResolvedValueOnce({}); // CREATE EXTENSION vector
      mockClient.query.mockResolvedValueOnce({}); // CREATE knowledge_entries
      mockClient.query.mockResolvedValueOnce({}); // CREATE extraction_batches
      mockClient.query.mockResolvedValueOnce({}); // CREATE usage
      mockClient.query.mockResolvedValueOnce({}); // CREATE feedback
      mockClient.query.mockResolvedValueOnce({}); // CREATE indexes
      mockClient.query.mockResolvedValueOnce({}); // COMMIT

      await service.initialize();

      expect(mockClient.query).toHaveBeenCalledWith('BEGIN');
      expect(mockClient.query).toHaveBeenCalledWith('CREATE EXTENSION IF NOT EXISTS vector');
      expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('UNIQUE(entry_id, user_id)'));
      expect(mockPool.connect).toHaveBeenCalled();
    });

    it('should not reinitialize if already initialized', async () => {
      mockClient.query.mockResolvedValue({});

      await service.initialize();
      const firstCallCount = (mockPool.connect as any).mock.calls.length;

      await service.initialize();
      const secondCallCount = (mockPool.connect as any).mock.calls.length;

      expect(secondCallCount).toBe(firstCallCount);
    });
  });

  describe('createKnowledgeEntry', () => {
    beforeEach(() => {
      mockClient.query.mockResolvedValue({});
    });

    it('should create knowledge entry with embedding', async () => {
      const embedding = Array(1536).fill(0.1);
      mockClient.query.mockResolvedValueOnce({
        rows: [{ id: 'entry-1', title: 'API Docs', content: 'Content', summary: 'Summary', embedding: JSON.stringify(embedding), source: 'session-1', source_type: 'session', tags: ['api'], category: 'docs', author_id: 'user-1', usage_count: 0, helpful_count: 0, views: 0, created_at: new Date(), updated_at: new Date() }],
      });

      const entry = await service.createKnowledgeEntry('API Docs', 'Content', 'Summary', embedding, 'user-1', {
        source: 'session-1',
        sourceType: 'session',
        tags: ['api'],
        category: 'docs',
      });

      expect(entry.id).toBe('entry-1');
      expect(entry.title).toBe('API Docs');
      expect(entry.helpfulCount).toBe(0);
    });

    it('should emit knowledge-created event', async () => {
      const embedding = Array(1536).fill(0.1);
      mockClient.query.mockResolvedValueOnce({
        rows: [{ id: 'entry-1', title: 'Test', content: 'Content', summary: 'Summary', embedding: JSON.stringify(embedding), source: null, source_type: 'manual', tags: [], category: null, author_id: 'user-1', usage_count: 0, helpful_count: 0, views: 0, created_at: new Date(), updated_at: new Date() }],
      });

      const eventSpy = vi.fn();
      service.on('knowledge-created', eventSpy);

      await service.createKnowledgeEntry('Test', 'Content', 'Summary', embedding, 'user-1');

      expect(eventSpy).toHaveBeenCalled();
    });
  });

  describe('searchKnowledge', () => {
    it('should perform semantic search with vector similarity', async () => {
      const queryEmbedding = Array(1536).fill(0.1);
      mockClient.query.mockResolvedValueOnce({
        rows: [
          { id: 'entry-1', title: 'API Docs', content: 'Content 1', summary: 'Summary 1', tags: ['api'], similarity_score: '0.85' },
          { id: 'entry-2', title: 'Database Guide', content: 'Content 2', summary: 'Summary 2', tags: ['db'], similarity_score: '0.72' },
        ],
      });

      const results = await service.searchKnowledge('API documentation', queryEmbedding, 10);

      expect(results.length).toBe(2);
      expect(results[0].score).toBe(0.85);
      expect(results[0].relevance).toBe('high');
      expect(results[1].relevance).toBe('high');
    });

    it('should limit results to specified count', async () => {
      const queryEmbedding = Array(1536).fill(0.1);
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.searchKnowledge('query', queryEmbedding, 5);

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('LIMIT $2'),
        expect.arrayContaining([expect.anything(), 5])
      );
    });
  });

  describe('getKnowledgeEntry', () => {
    it('should retrieve knowledge entry and increment views', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [{ id: 'entry-1', title: 'Test', content: 'Content', summary: 'Summary', embedding: JSON.stringify(Array(1536).fill(0.1)), source: 'session-1', source_type: 'session', tags: [], category: 'test', author_id: 'user-1', usage_count: 5, helpful_count: 3, views: 10, created_at: new Date(), updated_at: new Date() }],
      });
      mockClient.query.mockResolvedValueOnce({}); // UPDATE views

      const entry = await service.getKnowledgeEntry('entry-1');

      expect(entry?.views).toBe(10);
      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE knowledge_entries SET last_accessed_at = NOW(), views = views + 1'),
        ['entry-1']
      );
    });

    it('should return null for non-existent entry', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const entry = await service.getKnowledgeEntry('non-existent');

      expect(entry).toBeNull();
    });
  });

  describe('updateKnowledgeEntry', () => {
    it('should update knowledge entry fields', async () => {
      const newEmbedding = Array(1536).fill(0.2);
      mockClient.query.mockResolvedValueOnce({
        rows: [{ id: 'entry-1', title: 'Updated', content: 'New content', summary: 'New summary', embedding: JSON.stringify(newEmbedding), source: 'session-1', source_type: 'session', tags: ['updated'], category: 'docs', author_id: 'user-1', usage_count: 5, helpful_count: 2, views: 5, created_at: new Date(), updated_at: new Date() }],
      });

      const entry = await service.updateKnowledgeEntry('entry-1', {
        title: 'Updated',
        content: 'New content',
        summary: 'New summary',
        embedding: newEmbedding,
        tags: ['updated'],
      });

      expect(entry.title).toBe('Updated');
      expect(entry.content).toBe('New content');
    });
  });

  describe('trackUsage', () => {
    it('should record knowledge usage and increment counter', async () => {
      mockClient.query.mockResolvedValueOnce({}); // INSERT usage
      mockClient.query.mockResolvedValueOnce({}); // UPDATE usage_count

      const eventSpy = vi.fn();
      service.on('knowledge-used', eventSpy);

      await service.trackUsage('entry-1', 'user-1', 'session-1', 'Used in debugging');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO knowledge_usage'),
        expect.arrayContaining(['entry-1', 'user-1', 'session-1', 'Used in debugging'])
      );
      expect(eventSpy).toHaveBeenCalled();
    });
  });

  describe('rateFeedback', () => {
    it('should record feedback with rating', async () => {
      mockClient.query.mockResolvedValueOnce({}); // INSERT feedback
      mockClient.query.mockResolvedValueOnce({}); // UPDATE helpful_count

      const eventSpy = vi.fn();
      service.on('feedback-recorded', eventSpy);

      await service.rateFeedback('entry-1', 'user-1', 5, true, 'Very helpful!');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO knowledge_feedback'),
        expect.arrayContaining(['entry-1', 'user-1', 5, true, 'Very helpful!'])
      );
      expect(eventSpy).toHaveBeenCalled();
    });

    it('should reject invalid ratings', async () => {
      await expect(service.rateFeedback('entry-1', 'user-1', 6, true)).rejects.toThrow(/between 0 and 5/);
      await expect(service.rateFeedback('entry-1', 'user-1', -1, true)).rejects.toThrow(/between 0 and 5/);
    });
  });

  describe('extractFromSession', () => {
    it('should extract knowledge from session', async () => {
      const embedding1 = Array(1536).fill(0.1);
      const embedding2 = Array(1536).fill(0.2);

      mockClient.query.mockResolvedValueOnce({}); // BEGIN
      mockClient.query.mockResolvedValueOnce({}); // INSERT batch
      mockClient.query.mockResolvedValueOnce({
        rows: [{ id: 'entry-1', title: 'Extracted 1', content: 'Content 1', summary: 'Summary 1', embedding: JSON.stringify(embedding1), source: 'session-1', source_type: 'session', tags: ['extracted'], category: 'session-notes', author_id: 'user-1', usage_count: 0, helpful_count: 0, views: 0, created_at: new Date(), updated_at: new Date() }],
      }); // INSERT entry 1
      mockClient.query.mockResolvedValueOnce({
        rows: [{ id: 'entry-2', title: 'Extracted 2', content: 'Content 2', summary: 'Summary 2', embedding: JSON.stringify(embedding2), source: 'session-1', source_type: 'session', tags: ['extracted'], category: 'session-notes', author_id: 'user-1', usage_count: 0, helpful_count: 0, views: 0, created_at: new Date(), updated_at: new Date() }],
      }); // INSERT entry 2
      mockClient.query.mockResolvedValueOnce({}); // COMMIT

      const request = { sessionId: 'session-1', content: 'Session content', context: 'context', authorId: 'user-1' };
      const entries = [
        { title: 'Extracted 1', content: 'Content 1', summary: 'Summary 1', embedding: embedding1, tags: ['extracted'], category: 'session-notes' },
        { title: 'Extracted 2', content: 'Content 2', summary: 'Summary 2', embedding: embedding2, tags: ['extracted'], category: 'session-notes' },
      ];

      const result = await service.extractFromSession(request, entries);

      expect(result.length).toBe(2);
      expect(result[0].sourceType).toBe('session');
      expect(result[0].source).toBe('session-1');
    });

    it('should emit knowledge-extracted event', async () => {
      mockClient.query.mockResolvedValueOnce({}); // BEGIN
      mockClient.query.mockResolvedValueOnce({}); // INSERT batch
      mockClient.query.mockResolvedValueOnce({ rows: [{ id: 'entry-1', title: 'Test', content: 'Content', summary: 'Summary', embedding: JSON.stringify(Array(1536).fill(0.1)), source: 'session-1', source_type: 'session', tags: [], category: null, author_id: 'user-1', usage_count: 0, helpful_count: 0, views: 0, created_at: new Date(), updated_at: new Date() }] });
      mockClient.query.mockResolvedValueOnce({}); // COMMIT

      const eventSpy = vi.fn();
      service.on('knowledge-extracted', eventSpy);

      const request = { sessionId: 'session-1', content: 'Content', context: 'context', authorId: 'user-1' };
      const entries = [{ title: 'Test', content: 'Content', summary: 'Summary', embedding: Array(1536).fill(0.1) }];

      await service.extractFromSession(request, entries);

      expect(eventSpy).toHaveBeenCalledWith(expect.objectContaining({ sessionId: 'session-1', count: 1 }));
    });
  });

  describe('getKnowledgeBase', () => {
    it('should retrieve knowledge base with filters', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          { id: 'entry-1', title: 'API', content: 'Content', summary: 'Summary', embedding: JSON.stringify(Array(1536).fill(0.1)), source: 'session-1', source_type: 'session', tags: ['api'], category: 'docs', author_id: 'user-1', usage_count: 10, helpful_count: 8, views: 50, created_at: new Date(), updated_at: new Date() },
        ],
      });

      const entries = await service.getKnowledgeBase({ category: 'docs', minViews: 10 });

      expect(entries.length).toBe(1);
      expect(entries[0].category).toBe('docs');
    });
  });
});
