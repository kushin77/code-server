#!/usr/bin/env node
// @file        apps/backend/src/services/llm-wiki-extraction/index.ts
// @module      collaboration/llm-wiki-extraction
// @description LLM-powered wiki extraction from collaboration sessions
// @owner       collab-3.6
// @status      active

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';

const logger = getLogger('LLMWikiExtractionService');

export interface KnowledgeEntry {
  id: string;
  title: string;
  content: string;
  summary: string;
  embedding: number[];
  source: string; // sessionId or 'manual'
  sourceType: 'session' | 'manual' | 'ai-generated';
  tags: string[];
  category: string;
  authorId: string;
  usageCount: number;
  helpfulCount: number;
  views: number;
  createdAt: Date;
  updatedAt: Date;
  lastAccessedAt?: Date;
}

export interface SearchResult {
  id: string;
  title: string;
  content: string;
  summary: string;
  score: number; // cosine similarity 0-1
  tags: string[];
  relevance: 'high' | 'medium' | 'low';
}

export interface ExtractionRequest {
  sessionId: string;
  content: string;
  context: string;
  authorId: string;
}

export class LLMWikiExtractionService extends EventEmitter {
  private pool: Pool;
  private initialized = false;

  constructor(pool: Pool) {
    super();
    this.pool = pool;
  }

  async initialize(): Promise<void> {
    if (this.initialized) return;

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Enable pgvector extension
      await client.query('CREATE EXTENSION IF NOT EXISTS vector');

      // Knowledge entries table
      await client.query(`
        CREATE TABLE IF NOT EXISTS knowledge_entries (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          title VARCHAR(512) NOT NULL,
          content TEXT NOT NULL,
          summary TEXT,
          embedding vector(1536),
          source VARCHAR(255),
          source_type VARCHAR(50) DEFAULT 'manual' CHECK (source_type IN ('session', 'manual', 'ai-generated')),
          tags TEXT[] DEFAULT '{}',
          category VARCHAR(255),
          author_id VARCHAR(255) NOT NULL,
          usage_count INTEGER DEFAULT 0,
          helpful_count INTEGER DEFAULT 0,
          views INTEGER DEFAULT 0,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          last_accessed_at TIMESTAMP WITH TIME ZONE
        );
      `);

      // Session knowledge extraction tracking
      await client.query(`
        CREATE TABLE IF NOT EXISTS knowledge_extraction_batches (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          session_id VARCHAR(255) NOT NULL UNIQUE,
          entries_extracted INTEGER DEFAULT 0,
          extraction_quality DECIMAL(3,2),
          extracted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
      `);

      // Knowledge usage tracking
      await client.query(`
        CREATE TABLE IF NOT EXISTS knowledge_usage (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          entry_id UUID NOT NULL REFERENCES knowledge_entries(id) ON DELETE CASCADE,
          user_id VARCHAR(255) NOT NULL,
          session_id VARCHAR(255),
          context VARCHAR(512),
          accessed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
      `);

      // Knowledge feedback/ratings
      await client.query(`
        CREATE TABLE IF NOT EXISTS knowledge_feedback (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          entry_id UUID NOT NULL REFERENCES knowledge_entries(id) ON DELETE CASCADE,
          user_id VARCHAR(255) NOT NULL,
          rating INTEGER CHECK (rating >= 0 AND rating <= 5),
          helpful BOOLEAN,
          comment TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          UNIQUE(entry_id, user_id)
        );
      `);

      // Create vector index for similarity search
      await client.query('CREATE INDEX IF NOT EXISTS idx_knowledge_embedding ON knowledge_entries USING ivfflat (embedding vector_cosine_ops)');
      await client.query('CREATE INDEX IF NOT EXISTS idx_knowledge_entries_category ON knowledge_entries(category)');
      await client.query('CREATE INDEX IF NOT EXISTS idx_knowledge_entries_tags ON knowledge_entries USING GIN(tags)');
      await client.query('CREATE INDEX IF NOT EXISTS idx_knowledge_entries_author ON knowledge_entries(author_id)');
      await client.query('CREATE INDEX IF NOT EXISTS idx_knowledge_usage_entry ON knowledge_usage(entry_id)');

      await client.query('COMMIT');
      this.initialized = true;
      logger.info('LLMWikiExtractionService initialized');
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Failed to initialize LLMWikiExtractionService', { error });
      throw error;
    } finally {
      client.release();
    }
  }

  async createKnowledgeEntry(
    title: string,
    content: string,
    summary: string,
    embedding: number[],
    authorId: string,
    options?: {
      source?: string;
      sourceType?: 'session' | 'manual' | 'ai-generated';
      tags?: string[];
      category?: string;
    }
  ): Promise<KnowledgeEntry> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(`
        INSERT INTO knowledge_entries
        (title, content, summary, embedding, author_id, source, source_type, tags, category)
        VALUES ($1, $2, $3, $4::vector, $5, $6, $7, $8, $9)
        RETURNING id, title, content, summary, embedding::text, source, source_type, tags, category, author_id, usage_count, helpful_count, views, created_at, updated_at
      `, [
        title,
        content,
        summary,
        `[${embedding.join(',')}]`,
        authorId,
        options?.source || null,
        options?.sourceType || 'manual',
        options?.tags || [],
        options?.category || null,
      ]);

      const entry = this.rowToKnowledgeEntry(result.rows[0]);
      this.emit('knowledge-created', { entryId: entry.id, title: entry.title });
      return entry;
    } finally {
      client.release();
    }
  }

  async searchKnowledge(query: string, queryEmbedding: number[], limit: number = 10): Promise<SearchResult[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(`
        SELECT 
          id, title, content, summary, tags,
          1 - (embedding <=> $1::vector) as similarity_score
        FROM knowledge_entries
        WHERE embedding IS NOT NULL
        ORDER BY embedding <=> $1::vector
        LIMIT $2
      `, [`[${queryEmbedding.join(',')}]`, limit]);

      return result.rows.map(row => ({
        id: row.id,
        title: row.title,
        content: row.content,
        summary: row.summary,
        score: parseFloat(row.similarity_score),
        tags: row.tags,
        relevance: this.calculateRelevance(parseFloat(row.similarity_score)),
      }));
    } finally {
      client.release();
    }
  }

  async getKnowledgeEntry(entryId: string): Promise<KnowledgeEntry | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query('SELECT * FROM knowledge_entries WHERE id = $1', [entryId]);

      if (!result.rows.length) return null;

      // Update last accessed
      await client.query('UPDATE knowledge_entries SET last_accessed_at = NOW(), views = views + 1 WHERE id = $1', [entryId]);

      return this.rowToKnowledgeEntry(result.rows[0]);
    } finally {
      client.release();
    }
  }

  async updateKnowledgeEntry(
    entryId: string,
    updates: {
      title?: string;
      content?: string;
      summary?: string;
      embedding?: number[];
      tags?: string[];
      category?: string;
    }
  ): Promise<KnowledgeEntry> {
    const client = await this.pool.connect();
    try {
      const setClauses: string[] = ['updated_at = NOW()'];
      const params: any[] = [];
      let paramIndex = 1;

      if (updates.title) {
        setClauses.push(`title = $${paramIndex}`);
        params.push(updates.title);
        paramIndex++;
      }
      if (updates.content) {
        setClauses.push(`content = $${paramIndex}`);
        params.push(updates.content);
        paramIndex++;
      }
      if (updates.summary) {
        setClauses.push(`summary = $${paramIndex}`);
        params.push(updates.summary);
        paramIndex++;
      }
      if (updates.embedding) {
        setClauses.push(`embedding = $${paramIndex}::vector`);
        params.push(`[${updates.embedding.join(',')}]`);
        paramIndex++;
      }
      if (updates.tags) {
        setClauses.push(`tags = $${paramIndex}`);
        params.push(updates.tags);
        paramIndex++;
      }
      if (updates.category) {
        setClauses.push(`category = $${paramIndex}`);
        params.push(updates.category);
        paramIndex++;
      }

      params.push(entryId);

      const result = await client.query(`
        UPDATE knowledge_entries
        SET ${setClauses.join(', ')}
        WHERE id = $${paramIndex}
        RETURNING *
      `, params);

      if (!result.rows.length) {
        throw new Error(`Knowledge entry ${entryId} not found`);
      }

      return this.rowToKnowledgeEntry(result.rows[0]);
    } finally {
      client.release();
    }
  }

  async trackUsage(entryId: string, userId: string, sessionId?: string, context?: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(`
        INSERT INTO knowledge_usage (entry_id, user_id, session_id, context)
        VALUES ($1, $2, $3, $4)
      `, [entryId, userId, sessionId || null, context || null]);

      await client.query('UPDATE knowledge_entries SET usage_count = usage_count + 1 WHERE id = $1', [entryId]);

      this.emit('knowledge-used', { entryId, userId });
    } finally {
      client.release();
    }
  }

  async rateFeedback(entryId: string, userId: string, rating: number, helpful: boolean, comment?: string): Promise<void> {
    if (rating < 0 || rating > 5) {
      throw new Error('Rating must be between 0 and 5');
    }

    const client = await this.pool.connect();
    try {
      await client.query(`
        INSERT INTO knowledge_feedback (entry_id, user_id, rating, helpful, comment)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (entry_id, user_id) DO UPDATE SET rating = $3, helpful = $4, comment = $5
      `, [entryId, userId, rating, helpful, comment || null]);

      if (helpful) {
        await client.query('UPDATE knowledge_entries SET helpful_count = helpful_count + 1 WHERE id = $1', [entryId]);
      }

      this.emit('feedback-recorded', { entryId, rating, helpful });
    } finally {
      client.release();
    }
  }

  async extractFromSession(request: ExtractionRequest, extractedEntries: Partial<KnowledgeEntry>[]): Promise<KnowledgeEntry[]> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Record extraction batch
      await client.query(`
        INSERT INTO knowledge_extraction_batches (session_id, entries_extracted)
        VALUES ($1, $2)
        ON CONFLICT (session_id) DO UPDATE SET entries_extracted = $2
      `, [request.sessionId, extractedEntries.length]);

      const created: KnowledgeEntry[] = [];
      for (const entry of extractedEntries) {
        const result = await client.query(`
          INSERT INTO knowledge_entries
          (title, content, summary, embedding, author_id, source, source_type, tags, category)
          VALUES ($1, $2, $3, $4::vector, $5, $6, $7, $8, $9)
          RETURNING id, title, content, summary, embedding::text, source, source_type, tags, category, author_id, usage_count, helpful_count, views, created_at, updated_at
        `, [
          entry.title,
          entry.content,
          entry.summary,
          entry.embedding ? `[${entry.embedding.join(',')}]` : null,
          request.authorId,
          request.sessionId,
          'session',
          entry.tags || [],
          entry.category || null,
        ]);

        created.push(this.rowToKnowledgeEntry(result.rows[0]));
      }

      await client.query('COMMIT');
      this.emit('knowledge-extracted', { sessionId: request.sessionId, count: created.length });
      return created;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async getKnowledgeBase(filters?: { category?: string; author?: string; minViews?: number }): Promise<KnowledgeEntry[]> {
    const client = await this.pool.connect();
    try {
      let query = 'SELECT * FROM knowledge_entries WHERE 1=1';
      const params: any[] = [];

      if (filters?.category) {
        params.push(filters.category);
        query += ` AND category = $${params.length}`;
      }
      if (filters?.author) {
        params.push(filters.author);
        query += ` AND author_id = $${params.length}`;
      }
      if (filters?.minViews) {
        params.push(filters.minViews);
        query += ` AND views >= $${params.length}`;
      }

      query += ' ORDER BY helpful_count DESC, usage_count DESC';

      const result = await client.query(query, params);
      return result.rows.map(row => this.rowToKnowledgeEntry(row));
    } finally {
      client.release();
    }
  }

  private calculateRelevance(score: number): 'high' | 'medium' | 'low' {
    if (score >= 0.7) return 'high';
    if (score >= 0.5) return 'medium';
    return 'low';
  }

  private rowToKnowledgeEntry(row: any): KnowledgeEntry {
    const embedding = row.embedding ? (typeof row.embedding === 'string' ? JSON.parse(row.embedding) : row.embedding) : [];
    return {
      id: row.id,
      title: row.title,
      content: row.content,
      summary: row.summary,
      embedding,
      source: row.source,
      sourceType: row.source_type,
      tags: row.tags || [],
      category: row.category,
      authorId: row.author_id,
      usageCount: row.usage_count,
      helpfulCount: row.helpful_count,
      views: row.views,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      lastAccessedAt: row.last_accessed_at,
    };
  }
}
