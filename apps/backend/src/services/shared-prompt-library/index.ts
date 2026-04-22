#!/usr/bin/env node
// @file        apps/backend/src/services/shared-prompt-library/index.ts
// @module      collaboration/shared-prompt-library
// @description Shared prompt library with versioning, auto-suggest, and usage tracking
// @owner       collab-3.5
// @status      active

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';

export type PromptCategory = 'code-review' | 'testing' | 'documentation' | 'refactoring' | 'debugging' | 'architecture' | 'custom';
export type PromptVisibility = 'private' | 'team' | 'public';

export interface Prompt {
  id: string;
  teamId: string;
  name: string;
  category: PromptCategory;
  content: string;
  description: string;
  version: number;
  visibility: PromptVisibility;
  createdBy: string;
  updatedBy: string;
  tags: string[];
  usageCount: number;
  rating: number; // 0-5
  ratingCount: number;
  createdAt: Date;
  updatedAt: Date;
}

export interface PromptSuggestion {
  promptId: string;
  promptName: string;
  content: string;
  matchScore: number; // 0-100
  relevantToContext: string;
}

export interface PromptVersion {
  id: string;
  promptId: string;
  version: number;
  content: string;
  changeDescription: string;
  createdBy: string;
  createdAt: Date;
}

export interface PromptLibraryConfig {
  maxPromptLength?: number;
  minMatchScore?: number;
  enableAutoSuggest?: boolean;
}

export class SharedPromptLibraryService extends EventEmitter {
  private pool: Pool;
  private logger = getLogger('SharedPromptLibraryService');
  private initialized = false;
  private config: Required<PromptLibraryConfig>;

  constructor(pool: Pool, config: PromptLibraryConfig = {}) {
    super();
    this.pool = pool;
    this.config = {
      maxPromptLength: config.maxPromptLength || 10000,
      minMatchScore: config.minMatchScore || 50,
      enableAutoSuggest: config.enableAutoSuggest !== false,
    };
  }

  async initialize(): Promise<void> {
    if (this.initialized) return;

    try {
      await this.createTables();
      this.initialized = true;
      this.logger.info('Shared prompt library database schema initialized');
    } catch (error) {
      this.logger.error('Failed to initialize shared prompt library schema', { error });
      throw error;
    }
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Prompts table
      await client.query(`
        CREATE TABLE IF NOT EXISTS prompts (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          team_id TEXT NOT NULL,
          name TEXT NOT NULL,
          category TEXT NOT NULL,
          content TEXT NOT NULL,
          description TEXT,
          version INTEGER DEFAULT 1,
          visibility TEXT NOT NULL CHECK (visibility IN ('private', 'team', 'public')),
          created_by TEXT NOT NULL,
          updated_by TEXT NOT NULL,
          tags TEXT[] DEFAULT '{}',
          usage_count INTEGER DEFAULT 0,
          rating DECIMAL(3, 2) DEFAULT 0.0,
          rating_count INTEGER DEFAULT 0,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);

      // Prompt versions table
      await client.query(`
        CREATE TABLE IF NOT EXISTS prompt_versions (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          prompt_id UUID NOT NULL REFERENCES prompts(id) ON DELETE CASCADE,
          version INTEGER NOT NULL,
          content TEXT NOT NULL,
          change_description TEXT,
          created_by TEXT NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);

      // Prompt usage tracking
      await client.query(`
        CREATE TABLE IF NOT EXISTS prompt_usage (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          prompt_id UUID NOT NULL REFERENCES prompts(id) ON DELETE CASCADE,
          user_id TEXT NOT NULL,
          context_data JSONB,
          timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);

      // Prompt ratings
      await client.query(`
        CREATE TABLE IF NOT EXISTS prompt_ratings (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          prompt_id UUID NOT NULL REFERENCES prompts(id) ON DELETE CASCADE,
          user_id TEXT NOT NULL,
          rating INTEGER NOT NULL CHECK (rating >= 0 AND rating <= 5),
          comment TEXT,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          UNIQUE(prompt_id, user_id)
        )
      `);

      // Indexes
      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_prompts_team ON prompts(team_id);
        CREATE INDEX IF NOT EXISTS idx_prompts_category ON prompts(category);
        CREATE INDEX IF NOT EXISTS idx_prompts_visibility ON prompts(visibility);
        CREATE INDEX IF NOT EXISTS idx_prompts_tags ON prompts USING GIN(tags);
        CREATE INDEX IF NOT EXISTS idx_prompts_created_by ON prompts(created_by);
        CREATE INDEX IF NOT EXISTS idx_prompt_versions_prompt ON prompt_versions(prompt_id);
        CREATE INDEX IF NOT EXISTS idx_usage_prompt ON prompt_usage(prompt_id);
        CREATE INDEX IF NOT EXISTS idx_usage_user ON prompt_usage(user_id);
        CREATE INDEX IF NOT EXISTS idx_ratings_prompt ON prompt_ratings(prompt_id);
      `);

      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async createPrompt(
    teamId: string,
    name: string,
    content: string,
    category: PromptCategory,
    createdBy: string,
    options: {
      description?: string;
      visibility?: PromptVisibility;
      tags?: string[];
    } = {}
  ): Promise<Prompt> {
    if (content.length > this.config.maxPromptLength) {
      throw new Error(`Prompt exceeds max length of ${this.config.maxPromptLength} characters`);
    }

    const client = await this.pool.connect();
    try {
      const id = require('crypto').randomUUID();
      const visibility = options.visibility || 'team';
      const tags = options.tags || [];

      await client.query(
        `INSERT INTO prompts (id, team_id, name, content, category, description, visibility, created_by, updated_by, tags)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
        [id, teamId, name, content, category, options.description || '', visibility, createdBy, createdBy, tags]
      );

      // Create initial version
      await client.query(
        `INSERT INTO prompt_versions (id, prompt_id, version, content, created_by)
         VALUES ($1, $2, $3, $4, $5)`,
        [require('crypto').randomUUID(), id, 1, content, createdBy]
      );

      this.logger.info('Prompt created', { promptId: id, teamId, name, category });
      this.emit('prompt-created', { id, teamId, name, category, createdBy });

      return {
        id,
        teamId,
        name,
        category,
        content,
        description: options.description || '',
        version: 1,
        visibility,
        createdBy,
        updatedBy: createdBy,
        tags,
        usageCount: 0,
        rating: 0,
        ratingCount: 0,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
    } catch (error) {
      this.logger.error('Failed to create prompt', { error, teamId, name });
      throw error;
    } finally {
      client.release();
    }
  }

  async getPrompt(promptId: string): Promise<Prompt | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT * FROM prompts WHERE id = $1`,
        [promptId]
      );

      if (result.rows.length === 0) {
        return null;
      }

      const row = result.rows[0];
      return {
        id: row.id,
        teamId: row.team_id,
        name: row.name,
        category: row.category,
        content: row.content,
        description: row.description,
        version: row.version,
        visibility: row.visibility,
        createdBy: row.created_by,
        updatedBy: row.updated_by,
        tags: row.tags,
        usageCount: row.usage_count,
        rating: parseFloat(row.rating),
        ratingCount: row.rating_count,
        createdAt: new Date(row.created_at),
        updatedAt: new Date(row.updated_at),
      };
    } catch (error) {
      this.logger.error('Failed to get prompt', { error, promptId });
      throw error;
    } finally {
      client.release();
    }
  }

  async listTeamPrompts(teamId: string, category?: PromptCategory): Promise<Prompt[]> {
    const client = await this.pool.connect();
    try {
      let query = `SELECT * FROM prompts WHERE team_id = $1 AND visibility IN ('team', 'public')`;
      const params: any[] = [teamId];

      if (category) {
        query += ` AND category = $2`;
        params.push(category);
      }

      query += ` ORDER BY rating DESC, updated_at DESC`;

      const result = await client.query(query, params);

      return result.rows.map(row => ({
        id: row.id,
        teamId: row.team_id,
        name: row.name,
        category: row.category,
        content: row.content,
        description: row.description,
        version: row.version,
        visibility: row.visibility,
        createdBy: row.created_by,
        updatedBy: row.updated_by,
        tags: row.tags,
        usageCount: row.usage_count,
        rating: parseFloat(row.rating),
        ratingCount: row.rating_count,
        createdAt: new Date(row.created_at),
        updatedAt: new Date(row.updated_at),
      }));
    } catch (error) {
      this.logger.error('Failed to list team prompts', { error, teamId });
      throw error;
    } finally {
      client.release();
    }
  }

  async updatePrompt(
    promptId: string,
    content: string,
    updatedBy: string,
    changeDescription?: string
  ): Promise<Prompt> {
    if (content.length > this.config.maxPromptLength) {
      throw new Error(`Prompt exceeds max length of ${this.config.maxPromptLength} characters`);
    }

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Get current prompt
      const promptResult = await client.query(`SELECT version FROM prompts WHERE id = $1`, [promptId]);
      if (promptResult.rows.length === 0) {
        throw new Error(`Prompt ${promptId} not found`);
      }

      const newVersion = promptResult.rows[0].version + 1;

      // Update prompt
      await client.query(
        `UPDATE prompts SET content = $1, version = $2, updated_by = $3, updated_at = NOW() WHERE id = $4`,
        [content, newVersion, updatedBy, promptId]
      );

      // Create version record
      await client.query(
        `INSERT INTO prompt_versions (id, prompt_id, version, content, change_description, created_by)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [require('crypto').randomUUID(), promptId, newVersion, content, changeDescription || '', updatedBy]
      );

      await client.query('COMMIT');

      const updated = await this.getPrompt(promptId);
      if (!updated) {
        throw new Error(`Failed to retrieve updated prompt ${promptId}`);
      }

      this.logger.info('Prompt updated', { promptId, newVersion });
      this.emit('prompt-updated', { promptId, newVersion, updatedBy });

      return updated;
    } catch (error) {
      await client.query('ROLLBACK');
      this.logger.error('Failed to update prompt', { error, promptId });
      throw error;
    } finally {
      client.release();
    }
  }

  async suggestPrompts(teamId: string, context: string, category?: PromptCategory): Promise<PromptSuggestion[]> {
    if (!this.config.enableAutoSuggest) {
      return [];
    }

    const client = await this.pool.connect();
    try {
      let query = `SELECT id, name, content FROM prompts WHERE team_id = $1 AND visibility IN ('team', 'public')`;
      const params: any[] = [teamId];

      if (category) {
        query += ` AND category = $2`;
        params.push(category);
      }

      const result = await client.query(query, params);

      const suggestions: PromptSuggestion[] = [];

      for (const row of result.rows) {
        const matchScore = this.calculateMatchScore(context, row.content, row.name);

        if (matchScore >= this.config.minMatchScore) {
          suggestions.push({
            promptId: row.id,
            promptName: row.name,
            content: row.content,
            matchScore,
            relevantToContext: context.substring(0, 50),
          });
        }
      }

      // Sort by match score descending
      suggestions.sort((a, b) => b.matchScore - a.matchScore);

      this.logger.debug('Prompts suggested', { teamId, count: suggestions.length });
      this.emit('prompts-suggested', { teamId, count: suggestions.length });

      return suggestions.slice(0, 5); // Return top 5
    } catch (error) {
      this.logger.error('Failed to suggest prompts', { error, teamId });
      throw error;
    } finally {
      client.release();
    }
  }

  async trackUsage(promptId: string, userId: string, context?: any): Promise<void> {
    const client = await this.pool.connect();
    try {
      // Record usage
      await client.query(
        `INSERT INTO prompt_usage (id, prompt_id, user_id, context_data)
         VALUES ($1, $2, $3, $4)`,
        [require('crypto').randomUUID(), promptId, userId, JSON.stringify(context || {})]
      );

      // Increment usage count
      await client.query(
        `UPDATE prompts SET usage_count = usage_count + 1 WHERE id = $1`,
        [promptId]
      );

      this.logger.debug('Prompt usage tracked', { promptId, userId });
      this.emit('usage-tracked', { promptId, userId, timestamp: new Date() });
    } catch (error) {
      this.logger.error('Failed to track usage', { error });
      throw error;
    } finally {
      client.release();
    }
  }

  async ratePrompt(promptId: string, userId: string, rating: number, comment?: string): Promise<void> {
    if (rating < 0 || rating > 5 || !Number.isInteger(rating)) {
      throw new Error('Rating must be an integer between 0 and 5');
    }

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Insert or update rating
      await client.query(
        `INSERT INTO prompt_ratings (id, prompt_id, user_id, rating, comment)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (prompt_id, user_id) DO UPDATE SET rating = $4, comment = $5`,
        [require('crypto').randomUUID(), promptId, userId, rating, comment || null]
      );

      // Recalculate average rating
      const avgResult = await client.query(
        `SELECT AVG(rating) as avg_rating, COUNT(*) as count FROM prompt_ratings WHERE prompt_id = $1`,
        [promptId]
      );

      const avgRating = parseFloat(avgResult.rows[0].avg_rating) || 0;
      const ratingCount = parseInt(avgResult.rows[0].count, 10);

      await client.query(
        `UPDATE prompts SET rating = $1, rating_count = $2 WHERE id = $3`,
        [avgRating.toFixed(2), ratingCount, promptId]
      );

      await client.query('COMMIT');

      this.logger.info('Prompt rated', { promptId, userId, rating });
      this.emit('prompt-rated', { promptId, userId, rating, avgRating, count: ratingCount });
    } catch (error) {
      await client.query('ROLLBACK');
      this.logger.error('Failed to rate prompt', { error });
      throw error;
    } finally {
      client.release();
    }
  }

  async getPromptVersions(promptId: string): Promise<PromptVersion[]> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT * FROM prompt_versions WHERE prompt_id = $1 ORDER BY version DESC`,
        [promptId]
      );

      return result.rows.map(row => ({
        id: row.id,
        promptId: row.prompt_id,
        version: row.version,
        content: row.content,
        changeDescription: row.change_description,
        createdBy: row.created_by,
        createdAt: new Date(row.created_at),
      }));
    } catch (error) {
      this.logger.error('Failed to get prompt versions', { error, promptId });
      throw error;
    } finally {
      client.release();
    }
  }

  private calculateMatchScore(context: string, content: string, name: string): number {
    // Simple matching: count common words
    const contextWords = context.toLowerCase().split(/\s+/);
    const contentWords = content.toLowerCase().split(/\s+/);
    const nameWords = name.toLowerCase().split(/\s+/);

    const allWords = new Set([...contentWords, ...nameWords]);
    let matches = 0;

    for (const word of contextWords) {
      if (allWords.has(word) && word.length > 3) {
        matches++;
      }
    }

    // Score as percentage of context words matched
    return contextWords.length > 0 ? Math.min(100, (matches / contextWords.length) * 100) : 0;
  }
}