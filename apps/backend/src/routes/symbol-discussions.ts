#!/usr/bin/env node
// @file        apps/backend/src/routes/symbol-discussions.ts
// @module      collaboration/symbol-discussions
// @description REST API routes for symbol discussion threads
// @owner       collab-2.7
// @status      active

import { Router } from 'express';
import { Pool } from 'pg';
import { SymbolDiscussionsService, CreateThreadRequest, AddCommentRequest, UpdateCommentRequest, SearchDiscussionsRequest } from '../services/symbol-discussions';
import { getLogger } from '../lib/logger';

const logger = getLogger('SymbolDiscussionsRoutes');

export function initializeSymbolDiscussionsRoutes(pool: Pool): Router {
  const router = Router();
  const discussionsService = new SymbolDiscussionsService(pool);

  // Initialize the service
  discussionsService.initialize().catch(error => {
    logger.error('Failed to initialize symbol discussions service', { error });
  });

  // GET /api/symbol-discussions/search - Search discussions
  router.get('/search', async (req, res) => {
    try {
      const searchRequest: SearchDiscussionsRequest = {
        query: req.query.query as string,
        fqn: req.query.fqn as string,
        filePath: req.query.filePath as string,
        author: req.query.author as string,
        isResolved: req.query.isResolved ? req.query.isResolved === 'true' : undefined,
        limit: req.query.limit ? parseInt(req.query.limit as string) : undefined,
        offset: req.query.offset ? parseInt(req.query.offset as string) : undefined,
      };

      const discussions = await discussionsService.searchDiscussions(searchRequest);
      res.json(discussions);
    } catch (error) {
      logger.error('Failed to search discussions', { error });
      res.status(500).json({ error: 'Failed to search discussions' });
    }
  });

  // GET /api/symbol-discussions/fqn/:fqn - Get discussion by FQN
  router.get('/fqn/:fqn(*)', async (req, res) => {
    try {
      const fqn = decodeURIComponent(req.params.fqn);
      const discussion = await discussionsService.getDiscussionByFQN(fqn);

      if (!discussion) {
        return res.status(404).json({ error: 'Discussion not found' });
      }

      res.json(discussion);
    } catch (error) {
      logger.error('Failed to get discussion by FQN', { error, fqn: req.params.fqn });
      res.status(500).json({ error: 'Failed to get discussion' });
    }
  });

  // POST /api/symbol-discussions/threads - Create new discussion thread
  router.post('/threads', async (req, res) => {
    try {
      const request: CreateThreadRequest = req.body;

      // Validate required fields
      if (!request.fqn || !request.title || !request.initialComment || !request.author) {
        return res.status(400).json({ error: 'Missing required fields: fqn, title, initialComment, author' });
      }

      if (!request.filePath || !request.symbolName || !request.symbolType || request.lineNumber === undefined) {
        return res.status(400).json({ error: 'Missing required fields: filePath, symbolName, symbolType, lineNumber' });
      }

      const discussion = await discussionsService.createThread(request);
      res.status(201).json(discussion);
    } catch (error) {
      logger.error('Failed to create discussion thread', { error, body: req.body });
      res.status(500).json({ error: 'Failed to create discussion thread' });
    }
  });

  // POST /api/symbol-discussions/threads/:threadId/comments - Add comment to thread
  router.post('/threads/:threadId/comments', async (req, res) => {
    try {
      const request: AddCommentRequest = {
        threadId: req.params.threadId,
        content: req.body.content,
        author: req.body.author,
        parentCommentId: req.body.parentCommentId,
      };

      if (!request.content || !request.author) {
        return res.status(400).json({ error: 'Missing required fields: content, author' });
      }

      const comment = await discussionsService.addComment(request);
      res.status(201).json(comment);
    } catch (error) {
      logger.error('Failed to add comment', { error, threadId: req.params.threadId, body: req.body });
      res.status(500).json({ error: 'Failed to add comment' });
    }
  });

  // PUT /api/symbol-discussions/comments/:commentId - Update comment
  router.put('/comments/:commentId', async (req, res) => {
    try {
      const request: UpdateCommentRequest = {
        commentId: req.params.commentId,
        content: req.body.content,
        author: req.body.author,
      };

      if (!request.content || !request.author) {
        return res.status(400).json({ error: 'Missing required fields: content, author' });
      }

      const comment = await discussionsService.updateComment(request);
      res.json(comment);
    } catch (error) {
      logger.error('Failed to update comment', { error, commentId: req.params.commentId, body: req.body });
      res.status(500).json({ error: 'Failed to update comment' });
    }
  });

  // POST /api/symbol-discussions/threads/:threadId/resolve - Resolve thread
  router.post('/threads/:threadId/resolve', async (req, res) => {
    try {
      const resolvedBy = req.body.resolvedBy;

      if (!resolvedBy) {
        return res.status(400).json({ error: 'Missing required field: resolvedBy' });
      }

      await discussionsService.resolveThread(req.params.threadId, resolvedBy);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to resolve thread', { error, threadId: req.params.threadId, body: req.body });
      res.status(500).json({ error: 'Failed to resolve thread' });
    }
  });

  // POST /api/symbol-discussions/comments/:commentId/reactions - Add reaction to comment
  router.post('/comments/:commentId/reactions', async (req, res) => {
    try {
      const { emoji, user } = req.body;

      if (!emoji || !user) {
        return res.status(400).json({ error: 'Missing required fields: emoji, user' });
      }

      await discussionsService.addReaction(req.params.commentId, emoji, user);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to add reaction', { error, commentId: req.params.commentId, body: req.body });
      res.status(500).json({ error: 'Failed to add reaction' });
    }
  });

  // DELETE /api/symbol-discussions/comments/:commentId/reactions - Remove reaction from comment
  router.delete('/comments/:commentId/reactions', async (req, res) => {
    try {
      const { emoji, user } = req.body;

      if (!emoji || !user) {
        return res.status(400).json({ error: 'Missing required fields: emoji, user' });
      }

      await discussionsService.removeReaction(req.params.commentId, emoji, user);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to remove reaction', { error, commentId: req.params.commentId, body: req.body });
      res.status(500).json({ error: 'Failed to remove reaction' });
    }
  });

  // PUT /api/symbol-discussions/symbols/fqn - Update symbol FQN (for refactoring)
  router.put('/symbols/fqn', async (req, res) => {
    try {
      const { oldFQN, newFQN } = req.body;

      if (!oldFQN || !newFQN) {
        return res.status(400).json({ error: 'Missing required fields: oldFQN, newFQN' });
      }

      await discussionsService.updateSymbolFQN(oldFQN, newFQN);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to update symbol FQN', { error, body: req.body });
      res.status(500).json({ error: 'Failed to update symbol FQN' });
    }
  });

  // DELETE /api/symbol-discussions/threads/:threadId - Delete thread
  router.delete('/threads/:threadId', async (req, res) => {
    try {
      await discussionsService.deleteThread(req.params.threadId);
      res.json({ success: true });
    } catch (error) {
      logger.error('Failed to delete thread', { error, threadId: req.params.threadId });
      res.status(500).json({ error: 'Failed to delete thread' });
    }
  });

  return router;
}

export { SymbolDiscussionsService } from '../services/symbol-discussions';