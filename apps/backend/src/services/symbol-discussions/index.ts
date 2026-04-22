#!/usr/bin/env node
// @file        apps/backend/src/services/symbol-discussions/index.ts
// @module      collaboration/symbol-discussions
// @description Thread-per-function discussions service - persistent discussions per symbol with FQN tracking
// @owner       collab-2.7
// @status      active

import { EventEmitter } from 'events';
import { Pool } from 'pg';
import { getLogger } from '../../lib/logger';
import { AuditService } from '../audit/audit-service';

export interface SymbolDiscussion {
  id: string;
  fqn: string; // Fully Qualified Name (e.g., "src/services/userService.ts:UserService.getUser")
  filePath: string;
  symbolName: string;
  symbolType: 'function' | 'class' | 'method' | 'variable' | 'interface' | 'type';
  lineNumber: number;
  createdAt: Date;
  updatedAt: Date;
  thread: DiscussionThread;
}

export interface DiscussionThread {
  id: string;
  title: string;
  createdBy: string;
  createdAt: Date;
  updatedAt: Date;
  isResolved: boolean;
  resolvedAt?: Date;
  resolvedBy?: string;
  comments: DiscussionComment[];
}

export interface DiscussionComment {
  id: string;
  threadId: string;
  author: string;
  content: string;
  createdAt: Date;
  updatedAt: Date;
  isEdited: boolean;
  parentCommentId?: string; // For threaded replies
  reactions: CommentReaction[];
}

export interface CommentReaction {
  emoji: string;
  user: string;
  timestamp: Date;
}

export interface CreateThreadRequest {
  fqn: string;
  filePath: string;
  symbolName: string;
  symbolType: 'function' | 'class' | 'method' | 'variable' | 'interface' | 'type';
  lineNumber: number;
  title: string;
  initialComment: string;
  author: string;
}

export interface AddCommentRequest {
  threadId: string;
  content: string;
  author: string;
  parentCommentId?: string;
}

export interface UpdateCommentRequest {
  commentId: string;
  content: string;
  author: string;
}

export interface SearchDiscussionsRequest {
  query?: string;
  fqn?: string;
  filePath?: string;
  author?: string;
  isResolved?: boolean;
  limit?: number;
  offset?: number;
}

export class SymbolDiscussionsService extends EventEmitter {
  private pool: Pool;
  private auditService: AuditService;
  private logger = getLogger('SymbolDiscussionsService');
  private initialized = false;

  constructor(pool: Pool, auditService: AuditService) {
    super();
    this.pool = pool;
    this.auditService = auditService;
  }

  async initialize(): Promise<void> {
    if (this.initialized) return;

    try {
      await this.createTables();
      this.initialized = true;
      this.logger.info('Symbol discussions database schema initialized');
    } catch (error) {
      this.logger.error('Failed to initialize symbol discussions schema', { error });
      throw error;
    }
  }

  private async createTables(): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Main discussions table
      await client.query(`
        CREATE TABLE IF NOT EXISTS symbol_discussions (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          fqn TEXT NOT NULL,
          file_path TEXT NOT NULL,
          symbol_name TEXT NOT NULL,
          symbol_type TEXT NOT NULL CHECK (symbol_type IN ('function', 'class', 'method', 'variable', 'interface', 'type')),
          line_number INTEGER NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        )
      `);

      // Discussion threads table
      await client.query(`
        CREATE TABLE IF NOT EXISTS discussion_threads (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          discussion_id UUID NOT NULL REFERENCES symbol_discussions(id) ON DELETE CASCADE,
          title TEXT NOT NULL,
          created_by TEXT NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          is_resolved BOOLEAN DEFAULT FALSE,
          resolved_at TIMESTAMP WITH TIME ZONE,
          resolved_by TEXT
        )
      `);

      // Thread comments table
      await client.query(`
        CREATE TABLE IF NOT EXISTS thread_comments (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          thread_id UUID NOT NULL REFERENCES discussion_threads(id) ON DELETE CASCADE,
          author TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          is_edited BOOLEAN DEFAULT FALSE,
          parent_comment_id UUID REFERENCES thread_comments(id) ON DELETE CASCADE
        )
      `);

      // Comment reactions table
      await client.query(`
        CREATE TABLE IF NOT EXISTS comment_reactions (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          comment_id UUID NOT NULL REFERENCES thread_comments(id) ON DELETE CASCADE,
          emoji TEXT NOT NULL,
          user TEXT NOT NULL,
          timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          UNIQUE(comment_id, emoji, user)
        )
      `);

      // Indexes for performance
      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_symbol_discussions_fqn ON symbol_discussions(fqn);
        CREATE INDEX IF NOT EXISTS idx_symbol_discussions_file_path ON symbol_discussions(file_path);
        CREATE INDEX IF NOT EXISTS idx_discussion_threads_discussion_id ON discussion_threads(discussion_id);
        CREATE INDEX IF NOT EXISTS idx_thread_comments_thread_id ON thread_comments(thread_id);
        CREATE INDEX IF NOT EXISTS idx_thread_comments_parent_id ON thread_comments(parent_comment_id);
        CREATE INDEX IF NOT EXISTS idx_comment_reactions_comment_id ON comment_reactions(comment_id);
      `);

      // Full-text search index on comments
      await client.query(`
        CREATE INDEX IF NOT EXISTS idx_thread_comments_content_fts ON thread_comments USING gin(to_tsvector('english', content));
      `);

      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async createThread(request: CreateThreadRequest): Promise<SymbolDiscussion> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // First, find or create the symbol discussion
      let discussionResult = await client.query(
        'SELECT id FROM symbol_discussions WHERE fqn = $1',
        [request.fqn]
      );

      let discussionId: string;
      if (discussionResult.rows.length === 0) {
        // Create new symbol discussion
        const insertResult = await client.query(
          `INSERT INTO symbol_discussions (fqn, file_path, symbol_name, symbol_type, line_number)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING id`,
          [request.fqn, request.filePath, request.symbolName, request.symbolType, request.lineNumber]
        );
        discussionId = insertResult.rows[0].id;

        // SOC2: Audit discussion creation
        this.auditService.emit({
          userId: request.author,
          role: 'developer',
          method: 'POST',
          path: `/api/symbols/discussions/${request.fqn}`,
          action: 'allow',
          reason: `Created discussion thread for symbol ${request.symbolName}`,
        });

        // Create the thread for the new symbol discussion
        const threadResult = await client.query(
          `INSERT INTO discussion_threads (discussion_id, title, created_by)
           VALUES ($1, $2, $3)
           RETURNING id`,
          [discussionId, request.title, request.author]
        );

        // Add the initial comment
        await client.query(
          `INSERT INTO thread_comments (thread_id, author, content)
           VALUES ($1, $2, $3)`,
          [threadResult.rows[0].id, request.author, request.initialComment]
        );
      } else {
        // For thread-per-function behavior, reuse the existing thread for this symbol.
        discussionId = discussionResult.rows[0].id;
        const threadResult = await client.query(
          'SELECT id FROM discussion_threads WHERE discussion_id = $1 ORDER BY created_at ASC LIMIT 1',
          [discussionId]
        );

        if (threadResult.rows.length === 0) {
          const insertThreadResult = await client.query(
            `INSERT INTO discussion_threads (discussion_id, title, created_by)
             VALUES ($1, $2, $3)
             RETURNING id`,
            [discussionId, request.title, request.author]
          );

          await client.query(
            `INSERT INTO thread_comments (thread_id, author, content)
             VALUES ($1, $2, $3)`,
            [insertThreadResult.rows[0].id, request.author, request.initialComment]
          );
        } else {
          await client.query(
            `INSERT INTO thread_comments (thread_id, author, content)
             VALUES ($1, $2, $3)`,
            [threadResult.rows[0].id, request.author, request.initialComment]
          );
          await client.query(
            'UPDATE discussion_threads SET updated_at = NOW() WHERE id = $1',
            [threadResult.rows[0].id]
          );
        }

        await client.query(
          'UPDATE symbol_discussions SET updated_at = NOW() WHERE id = $1',
          [discussionId]
        );
      }

      await client.query('COMMIT');

      // Fetch the complete discussion
      return await this.getDiscussionById(discussionId);
    } catch (error) {
      await client.query('ROLLBACK');
      this.logger.error('Failed to create discussion thread', { error, request });
      throw error;
    } finally {
      client.release();
    }
  }

  async addComment(request: AddCommentRequest): Promise<DiscussionComment> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `INSERT INTO thread_comments (thread_id, author, content, parent_comment_id)
         VALUES ($1, $2, $3, $4)
         RETURNING id, created_at, updated_at`,
        [request.threadId, request.author, request.content, request.parentCommentId || null]
      );

      // Update thread's updated_at
      await client.query(
        'UPDATE discussion_threads SET updated_at = NOW() WHERE id = $1',
        [request.threadId]
      );

      // Update discussion's updated_at
      await client.query(
        `UPDATE symbol_discussions SET updated_at = NOW()
         WHERE id = (SELECT discussion_id FROM discussion_threads WHERE id = $1)`,
        [request.threadId]
      );

      // SOC2: Audit comment addition
      this.auditService.emit({
        userId: request.author,
        role: 'developer',
        method: 'POST',
        path: `/api/symbols/threads/${request.threadId}/comments`,
        action: 'allow',
        reason: `Added comment to thread ${request.threadId}`,
      });

      const commentId = result.rows[0].id;
      return await this.getCommentById(commentId);
    } catch (error) {
      this.logger.error('Failed to add comment', { error, request });
      throw error;
    } finally {
      client.release();
    }
  }

  async updateComment(request: UpdateCommentRequest): Promise<DiscussionComment> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `UPDATE thread_comments
         SET content = $1, updated_at = NOW(), is_edited = TRUE
         WHERE id = $2 AND author = $3`,
        [request.content, request.commentId, request.author]
      );

      // Update thread and discussion timestamps
      await client.query(`
        UPDATE discussion_threads SET updated_at = NOW()
        WHERE id = (SELECT thread_id FROM thread_comments WHERE id = $1)
      `, [request.commentId]);

      await client.query(`
        UPDATE symbol_discussions SET updated_at = NOW()
        WHERE id = (
          SELECT d.id FROM symbol_discussions d
          JOIN discussion_threads t ON t.discussion_id = d.id
          JOIN thread_comments c ON c.thread_id = t.id
          WHERE c.id = $1
        )
      `, [request.commentId]);

      return await this.getCommentById(request.commentId);
    } catch (error) {
      this.logger.error('Failed to update comment', { error, request });
      throw error;
    } finally {
      client.release();
    }
  }

  async resolveThread(threadId: string, resolvedBy: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `UPDATE discussion_threads
         SET is_resolved = TRUE, resolved_at = NOW(), resolved_by = $2, updated_at = NOW()
         WHERE id = $1`,
        [threadId, resolvedBy]
      );

      // Update discussion timestamp
      await client.query(`
        UPDATE symbol_discussions SET updated_at = NOW()
        WHERE id = (SELECT discussion_id FROM discussion_threads WHERE id = $1)
      `, [threadId]);

      // SOC2: Audit thread resolution
      this.auditService.emit({
        userId: resolvedBy,
        role: 'developer',
        method: 'POST',
        path: `/api/symbols/threads/${threadId}/resolve`,
        action: 'allow',
        reason: `Resolved discussion thread ${threadId}`,
      });

      this.logger.info('Thread resolved', { threadId, resolvedBy });
    } catch (error) {
      this.logger.error('Failed to resolve thread', { error, threadId, resolvedBy });
      throw error;
    } finally {
      client.release();
    }
  }

  async addReaction(commentId: string, emoji: string, user: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        `INSERT INTO comment_reactions (comment_id, emoji, user)
         VALUES ($1, $2, $3)
         ON CONFLICT (comment_id, emoji, user) DO NOTHING`,
        [commentId, emoji, user]
      );
    } catch (error) {
      this.logger.error('Failed to add reaction', { error, commentId, emoji, user });
      throw error;
    } finally {
      client.release();
    }
  }

  async removeReaction(commentId: string, emoji: string, user: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        'DELETE FROM comment_reactions WHERE comment_id = $1 AND emoji = $2 AND user = $3',
        [commentId, emoji, user]
      );
    } catch (error) {
      this.logger.error('Failed to remove reaction', { error, commentId, emoji, user });
      throw error;
    } finally {
      client.release();
    }
  }

  async searchDiscussions(request: SearchDiscussionsRequest): Promise<SymbolDiscussion[]> {
    const client = await this.pool.connect();
    try {
      let query = `
        SELECT
          d.id, d.fqn, d.file_path, d.symbol_name, d.symbol_type, d.line_number, d.created_at, d.updated_at,
          t.id as thread_id, t.title, t.created_by, t.created_at as thread_created_at,
          t.updated_at as thread_updated_at, t.is_resolved, t.resolved_at, t.resolved_by
        FROM symbol_discussions d
        JOIN discussion_threads t ON t.discussion_id = d.id
        WHERE 1=1
      `;

      const params: any[] = [];
      let paramIndex = 1;

      if (request.fqn) {
        query += ` AND d.fqn = $${paramIndex}`;
        params.push(request.fqn);
        paramIndex++;
      }

      if (request.filePath) {
        query += ` AND d.file_path = $${paramIndex}`;
        params.push(request.filePath);
        paramIndex++;
      }

      if (request.author) {
        query += ` AND t.created_by = $${paramIndex}`;
        params.push(request.author);
        paramIndex++;
      }

      if (request.isResolved !== undefined) {
        query += ` AND t.is_resolved = $${paramIndex}`;
        params.push(request.isResolved);
        paramIndex++;
      }

      if (request.query) {
        query += ` AND EXISTS (
          SELECT 1 FROM thread_comments c
          WHERE c.thread_id = t.id AND to_tsvector('english', c.content) @@ plainto_tsquery('english', $${paramIndex})
        )`;
        params.push(request.query);
        paramIndex++;
      }

      query += ' ORDER BY d.updated_at DESC';

      if (request.limit) {
        query += ` LIMIT $${paramIndex}`;
        params.push(request.limit);
        paramIndex++;
      }

      if (request.offset) {
        query += ` OFFSET $${paramIndex}`;
        params.push(request.offset);
        paramIndex++;
      }

      const result = await client.query(query, params);

      // Group by discussion and fetch comments for each
      const discussions: SymbolDiscussion[] = [];
      const discussionMap = new Map<string, SymbolDiscussion>();

      for (const row of result.rows) {
        const discussionId = row.id;

        if (!discussionMap.has(discussionId)) {
          const discussion: SymbolDiscussion = {
            id: discussionId,
            fqn: row.fqn,
            filePath: row.file_path,
            symbolName: row.symbol_name,
            symbolType: row.symbol_type,
            lineNumber: row.line_number,
            createdAt: row.created_at,
            updatedAt: row.updated_at,
            thread: {
              id: row.thread_id,
              title: row.title,
              createdBy: row.created_by,
              createdAt: row.thread_created_at,
              updatedAt: row.thread_updated_at,
              isResolved: row.is_resolved,
              resolvedAt: row.resolved_at,
              resolvedBy: row.resolved_by,
              comments: []
            }
          };
          discussionMap.set(discussionId, discussion);
          discussions.push(discussion);
        }

        // Fetch comments for this thread
        const thread = discussionMap.get(discussionId)!.thread;
        thread.comments = await this.getCommentsForThread(thread.id);
      }

      return discussions;
    } catch (error) {
      this.logger.error('Failed to search discussions', { error, request });
      throw error;
    } finally {
      client.release();
    }
  }

  async getDiscussionByFQN(fqn: string): Promise<SymbolDiscussion | null> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        'SELECT id FROM symbol_discussions WHERE fqn = $1',
        [fqn]
      );

      if (result.rows.length === 0) {
        return null;
      }

      return await this.getDiscussionById(result.rows[0].id);
    } catch (error) {
      this.logger.error('Failed to get discussion by FQN', { error, fqn });
      throw error;
    } finally {
      client.release();
    }
  }

  private async getDiscussionById(discussionId: string): Promise<SymbolDiscussion> {
    const client = await this.pool.connect();
    try {
      const discussionResult = await client.query(
        'SELECT * FROM symbol_discussions WHERE id = $1',
        [discussionId]
      );

      if (discussionResult.rows.length === 0) {
        throw new Error(`Discussion not found: ${discussionId}`);
      }

      const row = discussionResult.rows[0];

      // Get all threads for this discussion
      const threadsResult = await client.query(
        'SELECT * FROM discussion_threads WHERE discussion_id = $1 ORDER BY created_at ASC',
        [discussionId]
      );

      if (threadsResult.rows.length === 0) {
        throw new Error(`No discussion thread found for discussion: ${discussionId}`);
      }

      // For now, return the first thread (assuming one thread per discussion)
      // In the future, this could support multiple threads per symbol
      const threadRow = threadsResult.rows[0];
      const comments = await this.getCommentsForThread(threadRow.id);

      return {
        id: row.id,
        fqn: row.fqn,
        filePath: row.file_path,
        symbolName: row.symbol_name,
        symbolType: row.symbol_type,
        lineNumber: row.line_number,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
        thread: {
          id: threadRow.id,
          title: threadRow.title,
          createdBy: threadRow.created_by,
          createdAt: threadRow.created_at,
          updatedAt: threadRow.updated_at,
          isResolved: threadRow.is_resolved,
          resolvedAt: threadRow.resolved_at,
          resolvedBy: threadRow.resolved_by,
          comments
        }
      };
    } catch (error) {
      this.logger.error('Failed to get discussion by ID', { error, discussionId });
      throw error;
    } finally {
      client.release();
    }
  }

  private async getCommentsForThread(threadId: string): Promise<DiscussionComment[]> {
    const client = await this.pool.connect();
    try {
      const commentsResult = await client.query(
        `SELECT c.*, array_agg(json_build_object('emoji', r.emoji, 'user', r.user, 'timestamp', r.timestamp)) as reactions
         FROM thread_comments c
         LEFT JOIN comment_reactions r ON r.comment_id = c.id
         WHERE c.thread_id = $1
         GROUP BY c.id
         ORDER BY c.created_at ASC`,
        [threadId]
      );

      return commentsResult.rows.map(row => ({
        id: row.id,
        threadId: row.thread_id,
        author: row.author,
        content: row.content,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
        isEdited: row.is_edited,
        parentCommentId: row.parent_comment_id,
        reactions: (row.reactions || []).filter((r: any) => r && r.emoji !== null) || []
      }));
    } catch (error) {
      this.logger.error('Failed to get comments for thread', { error, threadId });
      throw error;
    } finally {
      client.release();
    }
  }

  private async getCommentById(commentId: string): Promise<DiscussionComment> {
    const client = await this.pool.connect();
    try {
      const result = await client.query(
        `SELECT c.*, array_agg(json_build_object('emoji', r.emoji, 'user', r.user, 'timestamp', r.timestamp)) as reactions
         FROM thread_comments c
         LEFT JOIN comment_reactions r ON r.comment_id = c.id
         WHERE c.id = $1
         GROUP BY c.id`,
        [commentId]
      );

      if (result.rows.length === 0) {
        throw new Error(`Comment not found: ${commentId}`);
      }

      const row = result.rows[0];
      return {
        id: row.id,
        threadId: row.thread_id,
        author: row.author,
        content: row.content,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
        isEdited: row.is_edited,
        parentCommentId: row.parent_comment_id,
        reactions: (row.reactions || []).filter((r: any) => r && r.emoji !== null) || []
      };
    } catch (error) {
      this.logger.error('Failed to get comment by ID', { error, commentId });
      throw error;
    } finally {
      client.release();
    }
  }

  async updateSymbolFQN(oldFQN: string, newFQN: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query(
        'UPDATE symbol_discussions SET fqn = $1, updated_at = NOW() WHERE fqn = $2',
        [newFQN, oldFQN]
      );

      this.logger.info('Updated symbol FQN', { oldFQN, newFQN });
    } catch (error) {
      this.logger.error('Failed to update symbol FQN', { error, oldFQN, newFQN });
      throw error;
    } finally {
      client.release();
    }
  }

  async deleteThread(threadId: string): Promise<void> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Delete reactions, comments, thread
      await client.query('DELETE FROM comment_reactions WHERE comment_id IN (SELECT id FROM thread_comments WHERE thread_id = $1)', [threadId]);
      await client.query('DELETE FROM thread_comments WHERE thread_id = $1', [threadId]);
      const discussionIdResult = await client.query(
        'SELECT discussion_id FROM discussion_threads WHERE id = $1',
        [threadId]
      );
      await client.query('DELETE FROM discussion_threads WHERE id = $1', [threadId]);

      if (discussionIdResult.rows.length > 0) {
        await client.query(
          `DELETE FROM symbol_discussions
           WHERE id = $1
             AND NOT EXISTS (SELECT 1 FROM discussion_threads WHERE discussion_id = $1)`,
          [discussionIdResult.rows[0].discussion_id]
        );
      }

      await client.query('COMMIT');

      this.logger.info('Thread deleted', { threadId });
    } catch (error) {
      await client.query('ROLLBACK');
      this.logger.error('Failed to delete thread', { error, threadId });
      throw error;
    } finally {
      client.release();
    }
  }
}