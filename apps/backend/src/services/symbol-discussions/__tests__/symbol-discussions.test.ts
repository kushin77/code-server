#!/usr/bin/env node
// @file        apps/backend/src/services/symbol-discussions/__tests__/symbol-discussions.test.ts
// @module      collaboration/symbol-discussions
// @description Unit tests for symbol discussions service
// @owner       collab-2.7
// @status      active

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { Pool } from 'pg';
import { SymbolDiscussionsService, CreateThreadRequest, AddCommentRequest, UpdateCommentRequest } from '../index';

// Mock the logger
vi.mock('../../../lib/logger', () => ({
  getLogger: vi.fn(() => ({
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
  })),
}));

// Mock the database pool
const mockPool = {
  connect: vi.fn(),
  end: vi.fn(),
} as unknown as Pool;

describe('SymbolDiscussionsService', () => {
  let service: SymbolDiscussionsService;
  let mockClient: any;

  beforeEach(async () => {
    vi.clearAllMocks();

    // Create a mock client
    mockClient = {
      query: vi.fn(),
      release: vi.fn(),
    };

    (mockPool.connect as any).mockResolvedValue(mockClient);

    service = new SymbolDiscussionsService(mockPool);
    mockClient.query.mockResolvedValue({ rows: [] });
    await service.initialize();
  });

  describe('initialization', () => {
    it('should initialize with database schema', async () => {
      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('CREATE TABLE IF NOT EXISTS symbol_discussions')
      );
    });
  });

  describe('createThread', () => {
    it('should create a new discussion thread for a symbol', async () => {
      const request: CreateThreadRequest = {
        fqn: 'src/services/userService.ts:UserService.getUser',
        filePath: 'src/services/userService.ts',
        symbolName: 'getUser',
        symbolType: 'method',
        lineNumber: 42,
        title: 'Question about error handling',
        initialComment: 'Should this method throw an error or return null?',
        author: 'alice',
      };

      // Mock the database responses
      mockClient.query
        .mockResolvedValueOnce({ rows: [] }) // BEGIN
        .mockResolvedValueOnce({ rows: [] }) // Check existing symbol
        .mockResolvedValueOnce({ rows: [{ id: 'discussion-1' }] }) // Insert symbol discussion
        .mockResolvedValueOnce({ rows: [{ id: 'thread-1' }] }) // Insert thread
        .mockResolvedValueOnce({ rows: [] }) // Insert comment
        .mockResolvedValueOnce({ rows: [] }) // COMMIT
        .mockResolvedValueOnce({ rows: [{ id: 'discussion-1', fqn: request.fqn, file_path: request.filePath, symbol_name: request.symbolName, symbol_type: request.symbolType, line_number: request.lineNumber, created_at: new Date(), updated_at: new Date() }] }) // Get discussion
        .mockResolvedValueOnce({ rows: [{ id: 'thread-1', title: request.title, created_by: request.author, created_at: new Date(), updated_at: new Date(), is_resolved: false, resolved_at: null, resolved_by: null }] }) // Get threads
        .mockResolvedValueOnce({ rows: [{ id: 'comment-1', thread_id: 'thread-1', author: request.author, content: request.initialComment, created_at: new Date(), updated_at: new Date(), is_edited: false, parent_comment_id: null, reactions: null }] }); // Get comments

      const discussion = await service.createThread(request);

      expect(discussion).toBeDefined();
      expect(discussion.fqn).toBe(request.fqn);
      expect(discussion.symbolName).toBe(request.symbolName);
      expect(discussion.thread.title).toBe(request.title);
      expect(discussion.thread.comments).toHaveLength(1);
    });
  });

  describe('addComment', () => {
    it('should add a comment to an existing thread', async () => {
      const commentRequest: AddCommentRequest = {
        threadId: 'thread-1',
        content: 'Yes, the regex looks correct for basic email validation.',
        author: 'bob',
      };

      mockClient.query
        .mockResolvedValueOnce({ rows: [{ id: 'comment-2', thread_id: 'thread-1', author: 'bob', content: commentRequest.content, created_at: new Date(), updated_at: new Date(), is_edited: false, parent_comment_id: null }] }) // Insert comment
        .mockResolvedValueOnce({ rows: [] }) // Update thread
        .mockResolvedValueOnce({ rows: [] }) // Update discussion
        .mockResolvedValueOnce({ rows: [{ id: 'comment-2', thread_id: 'thread-1', author: 'bob', content: commentRequest.content, created_at: new Date(), updated_at: new Date(), is_edited: false, parent_comment_id: null, reactions: null }] }); // Get comment

      const comment = await service.addComment(commentRequest);

      expect(comment).toBeDefined();
      expect(comment.threadId).toBe(commentRequest.threadId);
      expect(comment.content).toBe(commentRequest.content);
      expect(comment.author).toBe(commentRequest.author);
    });
  });

  describe('updateComment', () => {
    it('should update a comment content', async () => {
      const updateRequest: UpdateCommentRequest = {
        commentId: 'comment-1',
        content: 'Updated: Is this regex correct for all email formats?',
        author: 'alice',
      };

      mockClient.query
        .mockResolvedValueOnce({ rows: [] }) // Update comment
        .mockResolvedValueOnce({ rows: [] }) // Update thread
        .mockResolvedValueOnce({ rows: [] }) // Update discussion
        .mockResolvedValueOnce({ rows: [{ id: 'comment-1', thread_id: 'thread-1', author: 'alice', content: updateRequest.content, created_at: new Date(), updated_at: new Date(), is_edited: true, parent_comment_id: null, reactions: null }] }); // Get updated comment

      const updatedComment = await service.updateComment(updateRequest);

      expect(updatedComment).toBeDefined();
      expect(updatedComment.id).toBe(updateRequest.commentId);
      expect(updatedComment.content).toBe(updateRequest.content);
      expect(updatedComment.isEdited).toBe(true);
    });
  });

  describe('resolveThread', () => {
    it('should resolve a discussion thread', async () => {
      const threadId = 'thread-1';

      mockClient.query
        .mockResolvedValueOnce({ rows: [] }) // Update thread
        .mockResolvedValueOnce({ rows: [] }); // Update discussion

      await service.resolveThread(threadId, 'bob');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE discussion_threads'),
        [threadId, 'bob']
      );
    });
  });

  describe('addReaction and removeReaction', () => {
    it('should add a reaction to a comment', async () => {
      const commentId = 'comment-1';

      mockClient.query.mockResolvedValueOnce({ rows: [] }); // Insert reaction

      await service.addReaction(commentId, '👍', 'bob');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO comment_reactions'),
        [commentId, '👍', 'bob']
      );
    });

    it('should remove a reaction from a comment', async () => {
      const commentId = 'comment-1';

      mockClient.query.mockResolvedValueOnce({ rows: [] }); // Delete reaction

      await service.removeReaction(commentId, '👍', 'bob');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('DELETE FROM comment_reactions'),
        [commentId, '👍', 'bob']
      );
    });
  });

  describe('searchDiscussions', () => {
    it('should search discussions by FQN', async () => {
      const mockDiscussion = {
        id: 'discussion-1',
        fqn: 'src/services/userService.ts:UserService.getUser',
        file_path: 'src/services/userService.ts',
        symbol_name: 'getUser',
        symbol_type: 'method',
        line_number: 42,
        created_at: new Date(),
        updated_at: new Date(),
        thread_id: 'thread-1',
        title: 'Question',
        created_by: 'alice',
        thread_created_at: new Date(),
        thread_updated_at: new Date(),
        is_resolved: false,
        resolved_at: null,
        resolved_by: null,
      };

      mockClient.query
        .mockResolvedValueOnce({ rows: [mockDiscussion] }) // Search query
        .mockResolvedValueOnce({ rows: [{ id: 'comment-1', thread_id: 'thread-1', author: 'alice', content: 'Test', created_at: new Date(), updated_at: new Date(), is_edited: false, parent_comment_id: null, reactions: null }] }); // Get comments

      const results = await service.searchDiscussions({
        fqn: 'src/services/userService.ts:UserService.getUser',
      });

      expect(results).toBeDefined();
      expect(results.length).toBeGreaterThanOrEqual(0);
    });
  });

  describe('getDiscussionByFQN', () => {
    it('should return null for non-existent FQN', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // Check discussion

      const result = await service.getDiscussionByFQN('nonexistent:fqn');
      expect(result).toBeNull();
    });
  });

  describe('updateSymbolFQN', () => {
    it('should update symbol FQN for refactoring', async () => {
      const oldFQN = 'src/utils/helpers.ts:validateEmail';
      const newFQN = 'src/validators/email.ts:validateEmailFormat';

      mockClient.query.mockResolvedValueOnce({ rows: [] }); // Update FQN

      await service.updateSymbolFQN(oldFQN, newFQN);

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE symbol_discussions'),
        [newFQN, oldFQN]
      );
    });
  });

  describe('deleteThread', () => {
    it('should delete a discussion thread and all associated data', async () => {
      const threadId = 'thread-1';

      mockClient.query
        .mockResolvedValueOnce({ rows: [] }) // BEGIN
        .mockResolvedValueOnce({ rows: [] }) // Delete reactions
        .mockResolvedValueOnce({ rows: [] }) // Delete comments
        .mockResolvedValueOnce({ rows: [{ discussion_id: 'discussion-1' }] }) // Get discussion_id
        .mockResolvedValueOnce({ rows: [] }) // Delete thread
        .mockResolvedValueOnce({ rows: [] }) // Delete orphan discussion
        .mockResolvedValueOnce({ rows: [] }); // COMMIT

      await service.deleteThread(threadId);

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('DELETE FROM discussion_threads'),
        [threadId]
      );
    });
  });
});