#!/usr/bin/env node
// @file        apps/backend/src/services/help-queue/__tests__/help-queue.test.ts
// @module      collaboration/help-queue
// @description Unit tests for help queue service
// @owner       collab-4.7
// @status      active

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { Pool } from 'pg';
import { HelpQueueService } from '../index';
import { AuditService } from '../../audit/audit-service';

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

const mockAuditService = {
  emit: vi.fn(),
} as unknown as AuditService;

describe('HelpQueueService', () => {
  let service: HelpQueueService;
  let mockClient: any;

  beforeEach(async () => {
    vi.clearAllMocks();

    mockClient = {
      query: vi.fn(),
      release: vi.fn(),
    };

    (mockPool.connect as any).mockResolvedValue(mockClient);

    service = new HelpQueueService(mockPool, mockAuditService);
    mockClient.query.mockResolvedValue({ rows: [] });
    await service.initialize();
  });

  describe('initialization', () => {
    it('should initialize with database schema', async () => {
      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('CREATE TABLE IF NOT EXISTS help_requests')
      );
    });

    it('should create all required tables', async () => {
      const createTableCalls = mockClient.query.mock.calls.filter(call =>
        call[0].includes('CREATE TABLE')
      );
      expect(createTableCalls.length).toBeGreaterThanOrEqual(5);
    });
  });

  describe('createRequest', () => {
    it('should create a help request', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const codeSnippet = {
        content: 'function test() { return 1; }',
        language: 'javascript',
        filePath: 'test.js',
      };

      const request = await service.createRequest(
        'user-1',
        codeSnippet,
        'Why does this return 1?',
        'normal'
      );

      expect(request).toBeDefined();
      expect(request.userId).toBe('user-1');
      expect(request.question).toBe('Why does this return 1?');
      expect(request.status).toBe('open');
      expect(request.urgency).toBe('normal');

      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'user-1',
          action: 'create',
          resourceType: 'help-request',
        })
      );
    });

    it('should calculate correct SLA for urgent requests', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const codeSnippet = { content: 'test', language: 'js' };
      const now = new Date();

      const request = await service.createRequest(
        'user-1',
        codeSnippet,
        'Help!',
        'urgent'
      );

      // SLA should be ~2 hours
      const slaDiff = request.slaDueAt.getTime() - now.getTime();
      expect(slaDiff).toBeGreaterThan(2 * 60 * 60 * 1000 - 1000); // Allow 1 sec margin
      expect(slaDiff).toBeLessThan(2 * 60 * 60 * 1000 + 1000);
    });

    it('should calculate correct SLA for normal requests', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const codeSnippet = { content: 'test', language: 'js' };
      const now = new Date();

      const request = await service.createRequest(
        'user-1',
        codeSnippet,
        'Question',
        'normal'
      );

      // SLA should be ~24 hours
      const slaDiff = request.slaDueAt.getTime() - now.getTime();
      expect(slaDiff).toBeGreaterThan(24 * 60 * 60 * 1000 - 1000);
      expect(slaDiff).toBeLessThan(24 * 60 * 60 * 1000 + 1000);
    });

    it('should set tags on request', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const codeSnippet = { content: 'test', language: 'js' };
      const request = await service.createRequest(
        'user-1',
        codeSnippet,
        'Question',
        'normal',
        ['react', 'hooks']
      );

      expect(request.tags).toEqual(['react', 'hooks']);
    });
  });

  describe('enrichQuestion', () => {
    it('should enrich question with AI insights', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.enrichQuestion(
        'req-1',
        'Why does this React hook cause infinite loops? It appears to be a common pattern issue.'
      );

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE help_requests'),
        expect.any(Array)
      );
    });
  });

  describe('assignToExpert', () => {
    it('should assign request to expert', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // BEGIN
      mockClient.query.mockResolvedValueOnce({
        rows: [{ current_queue_size: 2 }],
      });
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE request
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE expert
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT history
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // COMMIT

      await service.assignToExpert('req-1', 'expert-1');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE help_requests'),
        expect.any(Array)
      );

      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'expert-1',
          action: 'update',
          resourceType: 'help-request',
        })
      );
    });

    it('should reject assignment if expert at capacity', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // BEGIN
      mockClient.query.mockResolvedValueOnce({
        rows: [{ current_queue_size: 5 }], // At max capacity
      });
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // ROLLBACK

      await expect(
        service.assignToExpert('req-1', 'expert-1')
      ).rejects.toThrow('at max capacity');
    });

    it('should handle missing expert', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // BEGIN
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // No expert found
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // ROLLBACK

      await expect(
        service.assignToExpert('req-1', 'unknown-expert')
      ).rejects.toThrow('not found');
    });
  });

  describe('respondToRequest', () => {
    it('should add response to request', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.respondToRequest(
        'req-1',
        'expert-1',
        'Try using useCallback to memoize the function'
      );

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO help_responses'),
        expect.any(Array)
      );

      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'expert-1',
          action: 'create',
          resourceType: 'help-response',
        })
      );
    });

    it('should include code proposal if provided', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.respondToRequest(
        'req-1',
        'expert-1',
        'Here is a fix:',
        'const memoized = useCallback(() => {...}, [deps])'
      );

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO help_responses'),
        expect.arrayContaining(['const memoized = useCallback(() => {...}, [deps])'])
      );
    });
  });

  describe('resolveRequest', () => {
    it('should resolve request and record SLA', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // BEGIN
      mockClient.query.mockResolvedValueOnce({
        rows: [{
          user_id: 'user-1',
          assigned_to: 'expert-1',
          urgency: 'normal',
          created_at: new Date(Date.now() - 60 * 60 * 1000), // 1 hour ago
          sla_due_at: new Date(Date.now() + 24 * 60 * 60 * 1000), // 24 hours from now
        }],
      });
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE request
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT SLA
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE expert
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT history
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // COMMIT

      const slaBroken = await service.resolveRequest('req-1', 'expert-1');

      expect(slaBroken.slaBreached).toBe(false);
      expect(slaBroken.resolutionTimeMs).toBeGreaterThan(0);

      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'expert-1',
          action: 'update',
          resourceType: 'help-request',
        })
      );
    });

    it('should detect SLA breach', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // BEGIN
      mockClient.query.mockResolvedValueOnce({
        rows: [{
          user_id: 'user-1',
          assigned_to: 'expert-1',
          urgency: 'urgent',
          created_at: new Date(Date.now() - 3 * 60 * 60 * 1000), // 3 hours ago
          sla_due_at: new Date(Date.now() - 60 * 60 * 1000), // SLA passed
        }],
      });
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE request
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT SLA
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // UPDATE expert
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // INSERT history
      mockClient.query.mockResolvedValueOnce({ rows: [] }); // COMMIT

      const slaBroken = await service.resolveRequest('req-1', 'expert-1');

      expect(slaBroken.slaBreached).toBe(true);
    });
  });

  describe('getRequest', () => {
    it('should retrieve request by ID', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [{
          id: 'req-1',
          user_id: 'user-1',
          code_snippet: { content: 'test', language: 'js' },
          question: 'Why?',
          urgency: 'normal',
          status: 'open',
          tags: ['javascript'],
          created_at: new Date(),
          updated_at: new Date(),
          sla_due_at: new Date(),
        }],
      });

      const request = await service.getRequest('req-1');

      expect(request).toBeDefined();
      expect(request?.id).toBe('req-1');
      expect(request?.userId).toBe('user-1');
    });

    it('should return null if request not found', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const request = await service.getRequest('unknown');

      expect(request).toBeNull();
    });
  });

  describe('getUserRequests', () => {
    it('should retrieve user requests', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'req-1',
            user_id: 'user-1',
            code_snippet: { content: 'test', language: 'js' },
            question: 'Q1',
            urgency: 'normal',
            status: 'open',
            tags: [],
            created_at: new Date(),
            updated_at: new Date(),
            sla_due_at: new Date(),
          },
          {
            id: 'req-2',
            user_id: 'user-1',
            code_snippet: { content: 'test2', language: 'js' },
            question: 'Q2',
            urgency: 'urgent',
            status: 'resolved',
            tags: [],
            created_at: new Date(),
            updated_at: new Date(),
            sla_due_at: new Date(),
          },
        ],
      });

      const requests = await service.getUserRequests('user-1');

      expect(requests).toHaveLength(2);
      expect(requests[0].id).toBe('req-1');
    });

    it('should filter by status', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'req-1',
            user_id: 'user-1',
            code_snippet: { content: 'test', language: 'js' },
            question: 'Q1',
            urgency: 'normal',
            status: 'open',
            tags: [],
            created_at: new Date(),
            updated_at: new Date(),
            sla_due_at: new Date(),
          },
        ],
      });

      const requests = await service.getUserRequests('user-1', 'open');

      expect(requests).toHaveLength(1);
      expect(requests[0].status).toBe('open');
    });
  });

  describe('getOpenRequests', () => {
    it('should retrieve open requests ordered by urgency', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'req-urgent',
            user_id: 'user-1',
            code_snippet: { content: 'test', language: 'js' },
            question: 'Critical',
            urgency: 'urgent',
            status: 'open',
            tags: [],
            created_at: new Date(),
            updated_at: new Date(),
            sla_due_at: new Date(),
          },
          {
            id: 'req-normal',
            user_id: 'user-2',
            code_snippet: { content: 'test', language: 'js' },
            question: 'Normal',
            urgency: 'normal',
            status: 'open',
            tags: [],
            created_at: new Date(),
            updated_at: new Date(),
            sla_due_at: new Date(),
          },
        ],
      });

      const requests = await service.getOpenRequests();

      expect(requests[0].urgency).toBe('urgent');
    });

    it('should respect limit parameter', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.getOpenRequests(5);

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('LIMIT'),
        expect.arrayContaining([5])
      );
    });
  });

  describe('getSLAMetrics', () => {
    it('should calculate SLA metrics', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [{
          total_requests: '10',
          sla_breached: '2',
          avg_resolution_time: '3600000',
        }],
      });

      const metrics = await service.getSLAMetrics();

      expect(metrics.totalRequests).toBe(10);
      expect(metrics.slaBreached).toBe(2);
      expect(metrics.breachRate).toBe(0.2);
      expect(metrics.avgResolutionTime).toBe(3600000);
    });
  });

  describe('registerExpert', () => {
    it('should register expert with expertise', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await service.registerExpert('expert-1', ['react', 'typescript', 'testing']);

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO expert_profiles'),
        expect.arrayContaining([['react', 'typescript', 'testing']])
      );

      expect(mockAuditService.emit).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: 'expert-1',
          action: 'update',
          resourceType: 'expert',
        })
      );
    });
  });

  describe('getAvailableExperts', () => {
    it('should retrieve available experts', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            user_id: 'expert-1',
            expertise: ['react', 'typescript'],
            current_queue_size: 2,
            average_resolution_time_ms: 1800000,
            sla_breach_rate: '0.05',
            is_available: true,
          },
          {
            user_id: 'expert-2',
            expertise: ['vue', 'javascript'],
            current_queue_size: 1,
            average_resolution_time_ms: 1500000,
            sla_breach_rate: '0.02',
            is_available: true,
          },
        ],
      });

      const experts = await service.getAvailableExperts();

      expect(experts).toHaveLength(2);
      expect(experts[0].userId).toBe('expert-1');
      expect(experts[0].currentQueueSize).toBe(2);
    });

    it('should filter by expertise tags', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            user_id: 'expert-1',
            expertise: ['react', 'typescript'],
            current_queue_size: 2,
            average_resolution_time_ms: 1800000,
            sla_breach_rate: '0.05',
            is_available: true,
          },
        ],
      });

      const experts = await service.getAvailableExperts(['react']);

      expect(experts).toHaveLength(1);
      expect(experts[0].expertise).toContain('react');
    });

    it('should order by lowest queue size', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            user_id: 'expert-2',
            expertise: ['vue'],
            current_queue_size: 1,
            average_resolution_time_ms: 1500000,
            sla_breach_rate: '0.02',
            is_available: true,
          },
          {
            user_id: 'expert-1',
            expertise: ['react'],
            current_queue_size: 3,
            average_resolution_time_ms: 1800000,
            sla_breach_rate: '0.05',
            is_available: true,
          },
        ],
      });

      const experts = await service.getAvailableExperts();

      expect(experts[0].currentQueueSize).toBeLessThan(experts[1].currentQueueSize);
    });
  });
});