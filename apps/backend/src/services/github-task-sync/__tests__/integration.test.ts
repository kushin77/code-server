#!/usr/bin/env node
// @file        apps/backend/src/services/github-task-sync/__tests__/integration.test.ts
// @module      services/github-task-sync/__tests__
// @description Integration tests for GitHub task sync
// @owner       collab-9
// @status      active

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { GitHubTaskSyncService } from '../index';
import { GitHubAPIClient } from '../github-api-client';

// Mock GitHub API client
vi.mock('../github-api-client');

describe('GitHubTaskSyncService', () => {
  let service: GitHubTaskSyncService;
  let mockApiClient: any;

  beforeEach(() => {
    mockApiClient = {
      validateAccess: vi.fn().mockResolvedValue(true),
      listIssues: vi.fn().mockResolvedValue([]),
      createIssue: vi.fn(),
      updateIssue: vi.fn(),
      closeIssue: vi.fn(),
      reopenIssue: vi.fn(),
      getAuthenticatedUser: vi.fn().mockResolvedValue({ login: 'test-user' }),
      on: vi.fn(),
      removeListener: vi.fn(),
    };

    // Mock the GitHubAPIClient constructor
    (GitHubAPIClient as any).mockImplementation(() => mockApiClient);

    service = new GitHubTaskSyncService({
      githubToken: 'test-token',
      owner: 'kushin77',
      repo: 'code-server',
    });
  });

  afterEach(() => {
    service.stopPolling();
    vi.clearAllMocks();
  });

  describe('Initialization', () => {
    it('should initialize successfully', async () => {
      await service.initialize();
      expect(mockApiClient.validateAccess).toHaveBeenCalled();
    });

    it('should throw error on invalid token', async () => {
      mockApiClient.validateAccess.mockResolvedValueOnce(false);
      
      await expect(service.initialize()).rejects.toThrow('Invalid GitHub token');
    });
  });

  describe('Polling', () => {
    it('should start polling', async () => {
      await service.initialize();
      service.startPolling();

      expect(service['pollingInterval']).toBeDefined();
    });

    it('should stop polling', async () => {
      await service.initialize();
      service.startPolling();
      service.stopPolling();

      expect(service['pollingInterval']).toBeNull();
    });

    it('should not start polling twice', async () => {
      await service.initialize();
      service.startPolling();
      const firstInterval = service['pollingInterval'];

      service.startPolling();
      expect(service['pollingInterval']).toBe(firstInterval);
    });
  });

  describe('Sync from GitHub', () => {
    it('should sync issues from GitHub', async () => {
      await service.initialize();

      const mockIssues = [
        {
          number: 1,
          title: 'Test Issue 1',
          body: 'Description 1',
          state: 'open',
          assignee: null,
          labels: [{ name: 'bug', color: 'ff0000' }],
          created_at: '2026-04-23T10:00:00Z',
          updated_at: '2026-04-23T10:00:00Z',
          html_url: 'https://github.com/kushin77/code-server/issues/1',
          user: { login: 'test-user', avatar_url: '' },
          comments: 0,
          closed_at: null,
          id: 1,
          url: '',
        },
      ];

      mockApiClient.listIssues.mockResolvedValueOnce(mockIssues);

      const result = await service.syncFromGitHub();

      expect(result.synced).toBe(1);
      expect(result.created).toBe(1);
      expect(service.getAllTasks().length).toBe(1);
    });

    it('should handle sync with state filter', async () => {
      await service.initialize();

      mockApiClient.listIssues.mockResolvedValueOnce([]);

      await service.syncFromGitHub({ state: 'open' });

      expect(mockApiClient.listIssues).toHaveBeenCalledWith(
        expect.objectContaining({ state: 'open' })
      );
    });

    it('should prevent concurrent syncs', async () => {
      await service.initialize();

      mockApiClient.listIssues.mockImplementationOnce(
        () => new Promise((resolve) => setTimeout(() => resolve([]), 100))
      );

      const sync1 = service.syncFromGitHub();
      const sync2 = service.syncFromGitHub();

      const [result1, result2] = await Promise.all([sync1, sync2]);

      // Second sync should skip
      expect(result2.synced).toBe(0);
    });

    it('should detect conflicts between local and GitHub', async () => {
      await service.initialize();

      const mockIssues = [
        {
          number: 1,
          title: 'Original Title',
          body: 'Original',
          state: 'open',
          assignee: null,
          labels: [],
          created_at: '2026-04-23T10:00:00Z',
          updated_at: '2026-04-23T10:00:00Z',
          html_url: 'https://github.com/kushin77/code-server/issues/1',
          user: { login: 'test-user', avatar_url: '' },
          comments: 0,
          closed_at: null,
          id: 1,
          url: '',
        },
      ];

      mockApiClient.listIssues.mockResolvedValueOnce(mockIssues);

      // First sync
      await service.syncFromGitHub();

      // Simulate local modification
      const localTask = service.getTask(1);
      if (localTask) {
        localTask.lastModifiedAt = new Date(Date.now() + 10000);
      }

      // Second sync with newer GitHub issue
      mockApiClient.listIssues.mockResolvedValueOnce(mockIssues);
      const result = await service.syncFromGitHub();

      expect(result.created).toBe(1);
      expect(service.getConflictLog().length).toBe(1);
    });
  });

  describe('Create Issue', () => {
    it('should create issue from IDE', async () => {
      await service.initialize();

      const mockCreatedIssue = {
        number: 100,
        title: 'New Issue from IDE',
        body: 'Description',
        state: 'open',
        assignee: null,
        labels: [{ name: 'feature', color: '00ff00' }],
        created_at: '2026-04-24T10:00:00Z',
        updated_at: '2026-04-24T10:00:00Z',
        html_url: 'https://github.com/kushin77/code-server/issues/100',
        user: { login: 'test-user', avatar_url: '' },
        comments: 0,
        closed_at: null,
        id: 100,
        url: '',
      };

      mockApiClient.createIssue.mockResolvedValueOnce(mockCreatedIssue);

      const task = await service.createIssueFromIDE({
        title: 'New Issue from IDE',
        body: 'Description',
        labels: ['feature'],
      });

      expect(task.issueNumber).toBe(100);
      expect(task.title).toBe('New Issue from IDE');
      expect(service.getTask(100)).toBeDefined();
    });
  });

  describe('Update Issue', () => {
    it('should update issue from IDE', async () => {
      await service.initialize();

      const mockUpdatedIssue = {
        number: 1,
        title: 'Updated Title',
        body: 'Updated description',
        state: 'open',
        assignee: null,
        labels: [{ name: 'bug', color: 'ff0000' }],
        created_at: '2026-04-23T10:00:00Z',
        updated_at: '2026-04-24T10:00:00Z',
        html_url: 'https://github.com/kushin77/code-server/issues/1',
        user: { login: 'test-user', avatar_url: '' },
        comments: 0,
        closed_at: null,
        id: 1,
        url: '',
      };

      mockApiClient.updateIssue.mockResolvedValueOnce(mockUpdatedIssue);

      const task = await service.updateIssueFromIDE(1, {
        title: 'Updated Title',
        body: 'Updated description',
      });

      expect(task.title).toBe('Updated Title');
      expect(task.description).toBe('Updated description');
    });
  });

  describe('Close Issue', () => {
    it('should close issue from IDE', async () => {
      await service.initialize();

      const mockClosedIssue = {
        number: 1,
        title: 'Issue',
        body: 'Closed from IDE',
        state: 'closed',
        assignee: null,
        labels: [],
        created_at: '2026-04-23T10:00:00Z',
        updated_at: '2026-04-24T10:00:00Z',
        html_url: 'https://github.com/kushin77/code-server/issues/1',
        user: { login: 'test-user', avatar_url: '' },
        comments: 0,
        closed_at: '2026-04-24T10:00:00Z',
        id: 1,
        url: '',
      };

      mockApiClient.closeIssue.mockResolvedValueOnce(mockClosedIssue);

      const task = await service.closeIssueFromIDE(1, 'Fixed in PR #999');

      expect(task.state).toBe('closed');
    });
  });

  describe('Reopen Issue', () => {
    it('should reopen issue from IDE', async () => {
      await service.initialize();

      const mockReopenedIssue = {
        number: 1,
        title: 'Issue',
        body: 'Reopened from IDE',
        state: 'open',
        assignee: null,
        labels: [],
        created_at: '2026-04-23T10:00:00Z',
        updated_at: '2026-04-24T10:00:00Z',
        html_url: 'https://github.com/kushin77/code-server/issues/1',
        user: { login: 'test-user', avatar_url: '' },
        comments: 0,
        closed_at: null,
        id: 1,
        url: '',
      };

      mockApiClient.reopenIssue.mockResolvedValueOnce(mockReopenedIssue);

      const task = await service.reopenIssueFromIDE(1);

      expect(task.state).toBe('open');
    });
  });

  describe('Task Queries', () => {
    it('should get task by issue number', async () => {
      await service.initialize();

      const mockIssues = [
        {
          number: 1,
          title: 'Test',
          body: 'Desc',
          state: 'open',
          assignee: null,
          labels: [],
          created_at: '2026-04-23T10:00:00Z',
          updated_at: '2026-04-23T10:00:00Z',
          html_url: '',
          user: { login: 'test-user', avatar_url: '' },
          comments: 0,
          closed_at: null,
          id: 1,
          url: '',
        },
      ];

      mockApiClient.listIssues.mockResolvedValueOnce(mockIssues);
      await service.syncFromGitHub();

      const task = service.getTask(1);
      expect(task).toBeDefined();
      expect(task?.issueNumber).toBe(1);
    });

    it('should get all tasks', async () => {
      await service.initialize();

      const mockIssues = [
        {
          number: 1,
          title: 'Test 1',
          body: 'Desc 1',
          state: 'open',
          assignee: null,
          labels: [],
          created_at: '2026-04-23T10:00:00Z',
          updated_at: '2026-04-23T10:00:00Z',
          html_url: '',
          user: { login: 'test-user', avatar_url: '' },
          comments: 0,
          closed_at: null,
          id: 1,
          url: '',
        },
        {
          number: 2,
          title: 'Test 2',
          body: 'Desc 2',
          state: 'closed',
          assignee: null,
          labels: [],
          created_at: '2026-04-23T10:00:00Z',
          updated_at: '2026-04-23T10:00:00Z',
          html_url: '',
          user: { login: 'test-user', avatar_url: '' },
          comments: 0,
          closed_at: '2026-04-24T10:00:00Z',
          id: 2,
          url: '',
        },
      ];

      mockApiClient.listIssues.mockResolvedValueOnce(mockIssues);
      await service.syncFromGitHub();

      expect(service.getAllTasks().length).toBe(2);
      expect(service.getOpenTasks().length).toBe(1);
      expect(service.getClosedTasks().length).toBe(1);
    });
  });

  describe('Status & Health', () => {
    it('should report sync status', async () => {
      await service.initialize();

      const status = service.getSyncStatus();

      expect(status).toHaveProperty('lastSyncTime');
      expect(status).toHaveProperty('totalTasks');
      expect(status).toHaveProperty('openTasks');
      expect(status).toHaveProperty('closedTasks');
      expect(status).toHaveProperty('conflictCount');
    });

    it('should pass health check', async () => {
      await service.initialize();

      const health = await service.healthCheck();

      expect(health.status).toBe('healthy');
      expect(health.details.authenticatedAs).toBe('test-user');
    });
  });
});
