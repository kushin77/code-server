#!/usr/bin/env node
// @file        apps/backend/src/services/issue-linking/__tests__/issue-linking.test.ts
// @module      collaboration/issue-linking
// @description Unit tests for issue linking service
// @owner       collab-9.2
// @status      active

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { Pool } from 'pg';
import { IssueLinkingService } from '../index';

vi.mock('../../../lib/logger', () => ({
  getLogger: vi.fn(() => ({
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
  })),
}));

const mockPool = {
  connect: vi.fn(),
  end: vi.fn(),
} as unknown as Pool;

describe('IssueLinkingService', () => {
  let service: IssueLinkingService;
  let mockClient: any;

  beforeEach(async () => {
    vi.clearAllMocks();

    mockClient = {
      query: vi.fn(),
      release: vi.fn(),
    };

    (mockPool.connect as any).mockResolvedValue(mockClient);

    service = new IssueLinkingService(mockPool);
    mockClient.query.mockResolvedValue({ rows: [] });
    await service.initialize();
  });

  describe('initialization', () => {
    it('should initialize with database schema', async () => {
      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('CREATE TABLE IF NOT EXISTS issue_tickets')
      );
    });

    it('should create all required tables', async () => {
      const callCount = mockClient.query.mock.calls.length;
      expect(callCount).toBeGreaterThan(3);
    });
  });

  describe('searchTickets', () => {
    it('should search tickets from Linear when API token is set', async () => {
      const serviceWithToken = new IssueLinkingService(mockPool, {
        linearApiToken: 'test-token',
      });
      await serviceWithToken.initialize();

      mockClient.query.mockResolvedValueOnce({ rows: [] }); // search cache check
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // cache set

      const results = await serviceWithToken.searchTickets('auth', 'linear');

      expect(results).toBeDefined();
      expect(results.length).toBeGreaterThan(0);
      expect(results[0].provider).toBe('linear');
    });

    it('should search tickets from Jira when API is configured', async () => {
      const serviceWithConfig = new IssueLinkingService(mockPool, {
        jiraBaseUrl: 'https://jira.example.com',
        jiraUsername: 'user@example.com',
        jiraApiToken: 'test-token',
      });
      await serviceWithConfig.initialize();

      mockClient.query.mockResolvedValueOnce({ rows: [] });
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const results = await serviceWithConfig.searchTickets('pipeline', 'jira');

      expect(results).toBeDefined();
      expect(results.length).toBeGreaterThan(0);
      expect(results[0].provider).toBe('jira');
    });

    it('should skip providers without credentials', async () => {
      mockClient.query.mockResolvedValue({ rows: [] });

      const results = await service.searchTickets('feature');

      // Service should skip providers without credentials
      expect(results.length).toBe(0);
    });

    it('should cache search results', async () => {
      const serviceWithToken = new IssueLinkingService(mockPool, {
        linearApiToken: 'test-token',
      });
      await serviceWithToken.initialize();

      mockClient.query.mockResolvedValueOnce({ rows: [] }); // cache check - empty
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // cache set

      await serviceWithToken.searchTickets('deploy');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('issue_search_cache'),
        expect.any(Array)
      );
    });
  });

  describe('saveTicket', () => {
    it('should save a ticket', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.saveTicket({
        id: 'ext-1',
        provider: 'linear',
        key: 'ENG-123',
        title: 'Implement auth',
        status: 'In Progress',
        url: 'https://linear.app/...',
        createdAt: new Date(),
        updatedAt: new Date(),
      });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO issue_tickets'),
        expect.any(Array)
      );
    });

    it('should update existing ticket', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.saveTicket({
        id: 'ext-1',
        provider: 'linear',
        key: 'ENG-123',
        title: 'Implement auth',
        status: 'Done',
        url: 'https://linear.app/...',
        createdAt: new Date(),
        updatedAt: new Date(),
      });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('ON CONFLICT'),
        expect.any(Array)
      );
    });
  });

  describe('linkIssue', () => {
    it('should link a ticket to GitHub issue', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [{ id: 'db-ticket-1' }],
      });
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.linkIssue('ext-1', 123, 'linear');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO linked_issues'),
        expect.any(Array)
      );
    });

    it('should handle missing ticket', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await expect(service.linkIssue('unknown', 456, 'jira')).rejects.toThrow();
    });
  });

  describe('getIssueContext', () => {
    it('should retrieve issue context', async () => {
      const mockContext = {
        ticket_key: 'ENG-123',
        title: 'Implement auth',
        acceptance_criteria: 'User can login with OAuth',
        linked_prs: [{ number: 1, title: 'PR title', url: 'https://...' }],
        related_issues: [{ key: 'ENG-124', title: 'Related issue' }],
        estimated_effort: '5 days',
      };

      mockClient.query.mockResolvedValueOnce({
        rows: [mockContext],
      });

      const context = await service.getIssueContext('ENG-123');

      expect(context).toBeDefined();
      expect(context?.ticketKey).toBe('ENG-123');
      expect(context?.title).toBe('Implement auth');
    });

    it('should return null if context not found', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const context = await service.getIssueContext('UNKNOWN-1');

      expect(context).toBeNull();
    });
  });

  describe('saveIssueContext', () => {
    it('should save issue context', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.saveIssueContext({
        ticketKey: 'ENG-123',
        title: 'Implement auth',
        acceptanceCriteria: 'OAuth2 flows work',
        linkedPRs: [],
        relatedIssues: [],
      });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO issue_context'),
        expect.any(Array)
      );
    });

    it('should update existing context', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.saveIssueContext({
        ticketKey: 'ENG-123',
        title: 'Updated title',
        acceptanceCriteria: 'Updated AC',
        linkedPRs: [],
        relatedIssues: [],
      });

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('ON CONFLICT'),
        expect.any(Array)
      );
    });
  });

  describe('generateBranchName', () => {
    it('should generate branch name from ticket key and title', () => {
      const name = service.generateBranchName({
        ticketKey: 'ENG-123',
        title: 'Implement User Authentication',
      });

      expect(name).toContain('eng-123');
      expect(name).toContain('implement');
      expect(name).toContain('authentication');
    });

    it('should handle special characters in title', () => {
      const name = service.generateBranchName({
        ticketKey: 'PROJ-456',
        title: 'Fix @mention system & link handling',
      });

      expect(name).not.toContain('@');
      expect(name).not.toContain('&');
      expect(name).toContain('proj-456');
    });

    it('should respect maxLength parameter', () => {
      const name = service.generateBranchName({
        ticketKey: 'ENG-123',
        title: 'This is a very long title that should be truncated',
        maxLength: 40,
      });

      expect(name.length).toBeLessThanOrEqual(40);
    });

    it('should allow custom prefix', () => {
      const name = service.generateBranchName({
        prefix: 'feature',
        ticketKey: 'ENG-789',
        title: 'Add dark mode',
      });

      expect(name).toMatch(/^feature\//);
      expect(name).toContain('eng-789');
    });

    it('should sanitize output', () => {
      const name = service.generateBranchName({
        ticketKey: 'ENG-123',
        title: 'Test {branch} [name] with <special> chars',
        sanitize: true,
      });

      expect(name).toMatch(/^[a-z0-9/-]+$/);
    });
  });

  describe('saveBranchName', () => {
    it('should save branch name', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.saveBranchName('ENG-123', 'feature/eng-123/user-auth');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO branch_names'),
        expect.any(Array)
      );
    });

    it('should save actual branch name if provided', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.saveBranchName('ENG-123', 'feature/eng-123/user-auth', 'feature/eng-123-user-auth', 'alice');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO branch_names'),
        expect.arrayContaining(['feature/eng-123-user-auth'])
      );
    });
  });

  describe('getBranchNames', () => {
    it('should retrieve branch naming history', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          { suggested_name: 'feature/eng-123/auth', actual_name: 'feature/eng-123-auth' },
          { suggested_name: 'feature/eng-123/implement-auth', actual_name: null },
        ],
      });

      const names = await service.getBranchNames('ENG-123');

      expect(names).toHaveLength(2);
      expect(names[0].suggested).toBe('feature/eng-123/auth');
      expect(names[0].actual).toBe('feature/eng-123-auth');
    });
  });

  describe('formatContextForCopilot', () => {
    it('should format context as markdown', () => {
      const context = {
        ticketKey: 'ENG-123',
        title: 'Implement authentication',
        acceptanceCriteria: 'OAuth2 flows\nUser login works',
        linkedPRs: [{ number: 1, title: 'Auth PR', url: 'https://...' }],
        relatedIssues: [{ key: 'ENG-124', title: 'API updates' }],
        estimatedEffort: '5 days',
      };

      const formatted = service.formatContextForCopilot(context);

      expect(formatted).toContain('## Ticket: ENG-123');
      expect(formatted).toContain('Implement authentication');
      expect(formatted).toContain('Acceptance Criteria');
      expect(formatted).toContain('OAuth2 flows');
      expect(formatted).toContain('#1');
      expect(formatted).toContain('ENG-124');
      expect(formatted).toContain('5 days');
    });

    it('should omit optional sections if missing', () => {
      const context = {
        ticketKey: 'ENG-123',
        title: 'Simple task',
        linkedPRs: [],
        relatedIssues: [],
      };

      const formatted = service.formatContextForCopilot(context);

      expect(formatted).not.toContain('Linked PRs');
      expect(formatted).not.toContain('Related Issues');
    });

    it('should format linked PRs as markdown links', () => {
      const context = {
        ticketKey: 'ENG-123',
        title: 'Task',
        linkedPRs: [
          { number: 42, title: 'Implementation', url: 'https://github.com/repo/pull/42' },
        ],
        relatedIssues: [],
      };

      const formatted = service.formatContextForCopilot(context);

      expect(formatted).toContain('[#42]');
      expect(formatted).toContain('https://github.com/repo/pull/42');
    });
  });
});