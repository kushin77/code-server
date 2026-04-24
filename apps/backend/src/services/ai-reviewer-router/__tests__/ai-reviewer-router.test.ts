#!/usr/bin/env node
// @file        apps/backend/src/services/ai-reviewer-router/__tests__/ai-reviewer-router.test.ts
// @module      collaboration/ai-reviewer-router
// @description Comprehensive AI reviewer router tests
// @owner       collab-3.7
// @status      active

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { AIReviewerRouterService } from '../index';
import { Pool } from 'pg';

vi.mock('../../../lib/logger', () => ({
  getLogger: vi.fn(() => ({
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
  })),
}));

describe('AIReviewerRouterService', () => {
  let service: AIReviewerRouterService;
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

    service = new AIReviewerRouterService(mockPool as Pool);
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('initialization', () => {
    it('should initialize tables on first call', async () => {
      mockClient.query.mockResolvedValueOnce({}); // BEGIN
      mockClient.query.mockResolvedValueOnce({}); // CREATE expertise
      mockClient.query.mockResolvedValueOnce({}); // CREATE workload
      mockClient.query.mockResolvedValueOnce({}); // CREATE availability
      mockClient.query.mockResolvedValueOnce({}); // CREATE assignments
      mockClient.query.mockResolvedValueOnce({}); // CREATE indexes
      mockClient.query.mockResolvedValueOnce({}); // COMMIT

      await service.initialize();

      expect(mockClient.query).toHaveBeenCalledWith('BEGIN');
      expect(mockClient.query).toHaveBeenCalledWith(expect.stringContaining('CREATE TABLE IF NOT EXISTS reviewer_expertise'));
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

  describe('registerReviewerExpertise', () => {
    beforeEach(() => {
      mockClient.query.mockResolvedValue({});
    });

    it('should register reviewer expertise', async () => {
      mockClient.query.mockResolvedValueOnce({});

      const expertise = await service.registerReviewerExpertise('reviewer1', 'src/api/**', 'expert', 95);

      expect(expertise.reviewerId).toBe('reviewer1');
      expect(expertise.filePattern).toBe('src/api/**');
      expect(expertise.expertiseLevel).toBe('expert');
      expect(expertise.confidence).toBe(95);
    });

    it('should reject invalid confidence', async () => {
      await expect(service.registerReviewerExpertise('reviewer1', 'src/**', 'expert', 101)).rejects.toThrow(
        /between 0 and 100/
      );
      await expect(service.registerReviewerExpertise('reviewer1', 'src/**', 'expert', -1)).rejects.toThrow(
        /between 0 and 100/
      );
    });

    it('should emit expertise-registered event', async () => {
      mockClient.query.mockResolvedValueOnce({});

      const eventSpy = vi.fn();
      service.on('expertise-registered', eventSpy);

      await service.registerReviewerExpertise('reviewer1', 'src/**', 'expert', 90);

      expect(eventSpy).toHaveBeenCalled();
    });
  });

  describe('updateReviewerWorkload', () => {
    beforeEach(() => {
      mockClient.query.mockResolvedValue({});
    });

    it('should update reviewer workload', async () => {
      mockClient.query.mockResolvedValueOnce({});

      const workload = await service.updateReviewerWorkload('reviewer1', 5, 15, 25);

      expect(workload.reviewerId).toBe('reviewer1');
      expect(workload.pendingReviews).toBe(5);
      expect(workload.completedReviewsLast7Days).toBe(15);
      expect(workload.averageReviewTimeMinutes).toBe(25);
    });

    it('should emit workload-updated event', async () => {
      mockClient.query.mockResolvedValueOnce({});

      const eventSpy = vi.fn();
      service.on('workload-updated', eventSpy);

      await service.updateReviewerWorkload('reviewer1', 3, 10, 20);

      expect(eventSpy).toHaveBeenCalled();
    });
  });

  describe('updateReviewerAvailability', () => {
    beforeEach(() => {
      mockClient.query.mockResolvedValue({});
    });

    it('should update reviewer availability', async () => {
      mockClient.query.mockResolvedValueOnce({});

      const availability = await service.updateReviewerAvailability('reviewer1', 'America/New_York', true, 9, 17);

      expect(availability.reviewerId).toBe('reviewer1');
      expect(availability.timezone).toBe('America/New_York');
      expect(availability.isOnline).toBe(true);
      expect(availability.preferredWorkHours.start).toBe(9);
      expect(availability.preferredWorkHours.end).toBe(17);
    });

    it('should emit availability-updated event', async () => {
      mockClient.query.mockResolvedValueOnce({});

      const eventSpy = vi.fn();
      service.on('availability-updated', eventSpy);

      await service.updateReviewerAvailability('reviewer1', 'UTC', false);

      expect(eventSpy).toHaveBeenCalled();
    });
  });

  describe('assignReview', () => {
    beforeEach(() => {
      // Mock scoreReviewers to return results
      vi.spyOn(service, 'scoreReviewers').mockResolvedValue([
        {
          reviewerId: 'reviewer1',
          name: 'Reviewer 1',
          expertiseScore: 90,
          workloadScore: 80,
          availabilityScore: 100,
          totalScore: 88,
          reasoning: 'Highly qualified and available',
        },
      ]);
    });

    it('should assign review to best reviewer', async () => {
      mockClient.query.mockResolvedValueOnce({}); // Insert assignment
      mockClient.query.mockResolvedValueOnce({}); // Update workload

      const eventSpy = vi.fn();
      service.on('review-assigned', eventSpy);

      const assignment = await service.assignReview('pr-123', ['src/api.ts', 'src/utils.ts'], 'team-1');

      expect(assignment.pullRequestId).toBe('pr-123');
      expect(assignment.reviewerId).toBe('reviewer1');
      expect(assignment.scoreExplanation.totalScore).toBe(88);
      expect(eventSpy).toHaveBeenCalled();
    });

    it('should reject when no suitable reviewers found', async () => {
      vi.mocked(service.scoreReviewers).mockResolvedValueOnce([]);

      await expect(service.assignReview('pr-123', ['src/api.ts'], 'team-1')).rejects.toThrow(
        /No suitable reviewers found/
      );
    });
  });

  describe('scoreReviewers', () => {
    it('should score reviewers based on expertise, workload, and availability', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [{ reviewer_id: 'reviewer1' }, { reviewer_id: 'reviewer2' }],
      }); // Get reviewers
      mockClient.query.mockResolvedValueOnce({
        rows: [{ avg_confidence: '85' }],
      }); // Expertise for reviewer1
      mockClient.query.mockResolvedValueOnce({
        rows: [{ pending_reviews: 3, completed_reviews_last_7days: 10 }],
      }); // Workload for reviewer1
      mockClient.query.mockResolvedValueOnce({
        rows: [{ is_online: true, timezone: 'UTC' }],
      }); // Availability for reviewer1

      mockClient.query.mockResolvedValueOnce({
        rows: [{ avg_confidence: '70' }],
      }); // Expertise for reviewer2
      mockClient.query.mockResolvedValueOnce({
        rows: [{ pending_reviews: 8, completed_reviews_last_7days: 5 }],
      }); // Workload for reviewer2
      mockClient.query.mockResolvedValueOnce({
        rows: [{ is_online: false, timezone: 'UTC' }],
      }); // Availability for reviewer2

      const scores = await service.scoreReviewers(['src/api.ts'], 'team-1');

      expect(scores.length).toBe(2);
      expect(scores[0].reviewerId).toBe('reviewer1');
      expect(scores[0].totalScore).toBeGreaterThan(scores[1].totalScore);
    });
  });

  describe('completeReview', () => {
    it('should complete a review and update workload', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [{ reviewer_id: 'reviewer1' }],
      }); // Get assignment
      mockClient.query.mockResolvedValueOnce({}); // Mark completed
      mockClient.query.mockResolvedValueOnce({}); // Update workload

      const eventSpy = vi.fn();
      service.on('review-completed', eventSpy);

      await service.completeReview('assign-1');

      expect(mockClient.query).toHaveBeenCalledWith(
        expect.stringContaining('UPDATE review_assignments SET completed_at = NOW()'),
        expect.arrayContaining(['assign-1'])
      );
      expect(eventSpy).toHaveBeenCalled();
    });

    it('should reject if assignment not found', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      await expect(service.completeReview('invalid-assign')).rejects.toThrow(/not found/);
    });
  });

  describe('getAssignment', () => {
    it('should retrieve an assignment with score explanation', async () => {
      mockClient.query.mockResolvedValueOnce({
        rows: [
          {
            id: 'assign-1',
            pull_request_id: 'pr-123',
            reviewer_id: 'reviewer1',
            expertise_score: '85',
            workload_score: '75',
            availability_score: '100',
            total_score: '85',
            score_explanation: { reasoning: 'Good match' },
            assigned_at: new Date(),
            completed_at: null,
          },
        ],
      });

      const assignment = await service.getAssignment('assign-1');

      expect(assignment).not.toBeNull();
      expect(assignment?.pullRequestId).toBe('pr-123');
      expect(assignment?.scoreExplanation.totalScore).toBe(85);
    });

    it('should return null for non-existent assignment', async () => {
      mockClient.query.mockResolvedValueOnce({ rows: [] });

      const assignment = await service.getAssignment('non-existent');

      expect(assignment).toBeNull();
    });
  });
});
