/**
 * @file        apps/backend/src/services/code-review/__tests__/review-service.test.ts
 * @module      collaboration/code-review
 * @description Code review request service comprehensive tests
 */

import { describe, it, expect, beforeEach } from 'vitest';
import {
  CodeReviewService,
  getCodeReviewService,
} from '../review-service.js';
import { ReviewTarget } from '../types.js';

describe('Code Review Service', () => {
  let reviewService: CodeReviewService;

  beforeEach(async () => {
    reviewService = new CodeReviewService();
    await reviewService.initialize();

    // Set up user context
    reviewService.setUserContext('user-alice', 'alice@example.com', 'Alice');
    reviewService.setUserContext('user-bob', 'bob@example.com', 'Bob');
    reviewService.setUserContext('user-charlie', 'charlie@example.com', 'Charlie');
  });

  describe('Service Initialization', () => {
    it('should initialize successfully', async () => {
      expect(reviewService).toBeDefined();
    });

    it('should emit initialized event', async () => {
      return new Promise<void>((resolve) => {
        const service = new CodeReviewService();
        service.once('initialized', () => {
          resolve();
        });
        service.initialize();
      });
    });
  });

  describe('Creating Review Requests', () => {
    it('should create review request', async () => {
      const targets: ReviewTarget[] = [
        {
          id: 'snippet-1',
          type: 'snippet',
          content: 'const x = 1;',
          language: 'typescript',
        },
      ];

      const requestId = await reviewService.createRequest(
        'ws-test',
        'user-alice',
        'Fix type annotations',
        'Need to add proper types',
        targets,
        ['user-bob', 'user-charlie'],
        'high'
      );

      expect(requestId).toMatch(/^review-/);
      const request = await reviewService.getRequest(requestId);
      expect(request?.title).toBe('Fix type annotations');
      expect(request?.priority).toBe('high');
      expect(request?.reviewsRequired).toBe(2);
    });

    it('should set default priority', async () => {
      const targets: ReviewTarget[] = [
        { id: 'snippet-1', type: 'snippet', content: 'code' },
      ];

      const requestId = await reviewService.createRequest(
        'ws-test',
        'user-alice',
        'Review',
        'Please review',
        targets,
        ['user-bob']
      );

      const request = await reviewService.getRequest(requestId);
      expect(request?.priority).toBe('medium');
    });

    it('should track request metadata', async () => {
      const targets: ReviewTarget[] = [
        {
          id: 'file-1',
          type: 'file',
          path: 'src/app.ts',
          language: 'typescript',
        },
      ];

      const requestId = await reviewService.createRequest(
        'ws-test',
        'user-alice',
        'Code review',
        'Please review app.ts',
        targets,
        ['user-bob'],
        'urgent'
      );

      const request = await reviewService.getRequest(requestId);
      expect(request?.createdBy).toBe('user-alice');
      expect(request?.status).toBe('pending');
      expect(request?.reviewsCompleted).toBe(0);
    });
  });

  describe('Submitting Reviews', () => {
    let requestId: string;

    beforeEach(async () => {
      const targets: ReviewTarget[] = [
        { id: 'snippet-1', type: 'snippet', content: 'code' },
      ];

      requestId = await reviewService.createRequest(
        'ws-test',
        'user-alice',
        'Review needed',
        'Description',
        targets,
        ['user-bob', 'user-charlie'],
        'high'
      );
    });

    it('should submit approval review', async () => {
      const reviewId = await reviewService.submitReview(
        requestId,
        'user-bob',
        'approved',
        'Looks good!'
      );

      expect(reviewId).toMatch(/^review-/);

      const reviews = await reviewService.getReviews(requestId);
      expect(reviews.length).toBe(1);
      expect(reviews[0].status).toBe('approved');
      expect(reviews[0].feedback).toBe('Looks good!');
    });

    it('should submit requested-changes review', async () => {
      await reviewService.submitReview(
        requestId,
        'user-bob',
        'requested-changes',
        'Please refactor this function'
      );

      const request = await reviewService.getRequest(requestId);
      expect(request?.status).toBe('requested-changes');
    });

    it('should submit comment review', async () => {
      await reviewService.submitReview(
        requestId,
        'user-bob',
        'commented',
        'What about error handling?'
      );

      const reviews = await reviewService.getReviews(requestId);
      expect(reviews[0].status).toBe('commented');
    });

    it('should track review count', async () => {
      await reviewService.submitReview(
        requestId,
        'user-bob',
        'approved',
        'Great!'
      );

      const request = await reviewService.getRequest(requestId);
      expect(request?.reviewsCompleted).toBe(1);

      await reviewService.submitReview(
        requestId,
        'user-charlie',
        'approved',
        'Good!'
      );

      const updated = await reviewService.getRequest(requestId);
      expect(updated?.reviewsCompleted).toBe(2);
      expect(updated?.status).toBe('approved');
    });

    it('should handle multiple reviews from same reviewer', async () => {
      await reviewService.submitReview(
        requestId,
        'user-bob',
        'commented',
        'First comment'
      );

      await reviewService.submitReview(
        requestId,
        'user-bob',
        'approved',
        'Now approved'
      );

      const reviews = await reviewService.getReviews(requestId);
      expect(reviews.length).toBe(2);
    });
  });

  describe('Listing Reviews', () => {
    beforeEach(async () => {
      const targets: ReviewTarget[] = [
        { id: 'snippet-1', type: 'snippet', content: 'code' },
      ];

      // Create multiple requests
      for (let i = 0; i < 3; i++) {
        await reviewService.createRequest(
          'ws-pending',
          'user-alice',
          `Review ${i}`,
          `Description ${i}`,
          targets,
          ['user-bob', 'user-charlie'],
          i === 0 ? 'urgent' : i === 1 ? 'high' : 'medium'
        );
      }
    });

    it('should list pending requests for reviewer', async () => {
      const pending = await reviewService.listPendingForReviewer('user-bob');

      expect(pending.length).toBe(3);
      // Should be sorted by priority: urgent, high, medium
      expect(pending[0].priority).toBe('urgent');
      expect(pending[1].priority).toBe('high');
      expect(pending[2].priority).toBe('medium');
    });

    it('should respect limit parameter', async () => {
      const pending = await reviewService.listPendingForReviewer('user-bob', 2);

      expect(pending.length).toBe(2);
    });

    it('should not list completed requests', async () => {
      const requests = await reviewService.listPendingForReviewer('user-bob', 10);
      const firstRequest = requests[0];

      // Complete the first request
      await reviewService.submitReview(
        firstRequest.id,
        'user-bob',
        'approved',
        'Good'
      );
      await reviewService.submitReview(
        firstRequest.id,
        'user-charlie',
        'approved',
        'Good'
      );

      const pending = await reviewService.listPendingForReviewer('user-bob');

      // Should have 2 remaining (3 - 1 that we completed)
      expect(pending.length).toBe(2);
    });
  });

  describe('Updating Requests', () => {
    let requestId: string;

    beforeEach(async () => {
      const targets: ReviewTarget[] = [
        { id: 'snippet-1', type: 'snippet', content: 'code' },
      ];

      requestId = await reviewService.createRequest(
        'ws-test',
        'user-alice',
        'Original title',
        'Original description',
        targets,
        ['user-bob'],
        'medium'
      );
    });

    it('should update request', async () => {
      await reviewService.updateRequest(requestId, {
        title: 'Updated title',
        description: 'Updated description',
      });

      const request = await reviewService.getRequest(requestId);
      expect(request?.title).toBe('Updated title');
      expect(request?.description).toBe('Updated description');
    });

    it('should update priority', async () => {
      await reviewService.updateRequest(requestId, {
        priority: 'urgent',
      });

      const request = await reviewService.getRequest(requestId);
      expect(request?.priority).toBe('urgent');
    });
  });

  describe('Closing Requests', () => {
    let requestId: string;

    beforeEach(async () => {
      const targets: ReviewTarget[] = [
        { id: 'snippet-1', type: 'snippet', content: 'code' },
      ];

      requestId = await reviewService.createRequest(
        'ws-test',
        'user-alice',
        'Review',
        'Description',
        targets,
        ['user-bob']
      );
    });

    it('should close request', async () => {
      await reviewService.closeRequest(requestId);

      const request = await reviewService.getRequest(requestId);
      expect(request?.status).toBe('closed');
    });

    it('should emit closed event', async () => {
      return new Promise<void>((resolve) => {
        reviewService.once('request-closed', ({ id, reason }) => {
          expect(id || requestId).toBeDefined();
          resolve();
        });

        reviewService.closeRequest(requestId, 'Completed');
      });
    });
  });

  describe('Reviewer Badges', () => {
    let requestId: string;

    beforeEach(async () => {
      const targets: ReviewTarget[] = [
        { id: 'snippet-1', type: 'snippet', content: 'code' },
      ];

      requestId = await reviewService.createRequest(
        'ws-test',
        'user-alice',
        'Review',
        'Description',
        targets,
        ['user-bob', 'user-charlie']
      );
    });

    it('should set reviewer badges', async () => {
      await reviewService.setReviewerBadges(requestId, {
        'user-bob': {
          reviewerId: 'user-bob',
          role: 'lead',
          expertise: ['TypeScript', 'React'],
          required: true,
          approved: false,
          responded: false,
        },
        'user-charlie': {
          reviewerId: 'user-charlie',
          role: 'peer',
          required: false,
          approved: false,
          responded: false,
        },
      });

      const request = await reviewService.getRequest(requestId);
      expect(request?.reviewerBadges?.['user-bob'].role).toBe('lead');
      expect(request?.reviewerBadges?.['user-charlie'].role).toBe('peer');
    });

    it('should update badge approval status', async () => {
      await reviewService.setReviewerBadges(requestId, {
        'user-bob': {
          reviewerId: 'user-bob',
          role: 'lead',
          required: true,
          approved: false,
          responded: false,
        },
      });

      await reviewService.submitReview(
        requestId,
        'user-bob',
        'approved',
        'Good'
      );

      const request = await reviewService.getRequest(requestId);
      expect(request?.reviewerBadges?.['user-bob'].approved).toBe(true);
    });
  });

  describe('Notifications', () => {
    let requestId: string;

    beforeEach(async () => {
      const targets: ReviewTarget[] = [
        { id: 'snippet-1', type: 'snippet', content: 'code' },
      ];

      requestId = await reviewService.createRequest(
        'ws-test',
        'user-alice',
        'Review',
        'Description',
        targets,
        ['user-bob', 'user-charlie']
      );
    });

    it('should send notifications', async () => {
      const count = await reviewService.sendNotifications(requestId);

      expect(count).toBe(2);

      const request = await reviewService.getRequest(requestId);
      expect(request?.notificationsSent).toBe(true);
    });

    it('should emit notifications-sent event', async () => {
      return new Promise<void>((resolve) => {
        reviewService.once('notifications-sent', ({ requestId: id, count }) => {
          expect(count).toBe(2);
          resolve();
        });

        reviewService.sendNotifications(requestId);
      });
    });
  });

  describe('Statistics', () => {
    beforeEach(async () => {
      const targets: ReviewTarget[] = [
        { id: 'snippet-1', type: 'snippet', content: 'code' },
      ];

      // Create requests with various priorities
      for (let i = 0; i < 5; i++) {
        const priority = ['low', 'medium', 'high', 'urgent', 'high'][
          i
        ] as any;
        const requestId = await reviewService.createRequest(
          'ws-stats',
          'user-alice',
          `Review ${i}`,
          'Description',
          targets,
          ['user-bob', 'user-charlie'],
          priority
        );

        // Complete some
        if (i < 2) {
          await reviewService.submitReview(
            requestId,
            'user-bob',
            'approved',
            'Good'
          );
          await reviewService.submitReview(
            requestId,
            'user-charlie',
            'approved',
            'Good'
          );
        }
      }
    });

    it('should calculate statistics', async () => {
      const stats = await reviewService.getStatistics('ws-stats');

      expect(stats.totalRequests).toBe(5);
      expect(stats.approvedRequests).toBe(2);
      expect(stats.pendingRequests).toBe(3);
      expect(stats.approvalRate).toBeGreaterThan(0);
    });

    it('should count by priority', async () => {
      const stats = await reviewService.getStatistics('ws-stats');

      expect(stats.byPriority.high).toBe(2);
      expect(stats.byPriority.urgent).toBe(1);
      expect(stats.byPriority.low).toBe(1);
      expect(stats.byPriority.medium).toBe(1);
    });

    it('should track by reviewer', async () => {
      const stats = await reviewService.getStatistics('ws-stats');

      expect(stats.byReviewer['user-bob']).toBeDefined();
      expect(stats.byReviewer['user-bob'].completed).toBe(2);
      expect(stats.byReviewer['user-bob'].pending).toBe(3);
    });

    it('should calculate average reviewers', async () => {
      const stats = await reviewService.getStatistics('ws-stats');

      expect(stats.averageReviewers).toBeGreaterThan(0);
    });
  });

  describe('Search', () => {
    beforeEach(async () => {
      const targets: ReviewTarget[] = [
        { id: 'snippet-1', type: 'snippet', content: 'code' },
      ];

      await reviewService.createRequest(
        'ws-search',
        'user-alice',
        'TypeScript fixes needed',
        'Fix type annotations in core module',
        targets,
        ['user-bob']
      );

      await reviewService.createRequest(
        'ws-search',
        'user-alice',
        'React refactor',
        'Refactor component hooks',
        targets,
        ['user-bob']
      );
    });

    it('should search by title', async () => {
      const results = await reviewService.searchRequests(
        'ws-search',
        'TypeScript'
      );

      expect(results.length).toBe(1);
      expect(results[0].title).toContain('TypeScript');
    });

    it('should search by description', async () => {
      const results = await reviewService.searchRequests(
        'ws-search',
        'component hooks'
      );

      expect(results.length).toBe(1);
      expect(results[0].title).toContain('React');
    });

    it('should be case-insensitive', async () => {
      const results = await reviewService.searchRequests(
        'ws-search',
        'TYPESCRIPT'
      );

      expect(results.length).toBe(1);
    });
  });

  describe('Get By Priority', () => {
    beforeEach(async () => {
      const targets: ReviewTarget[] = [
        { id: 'snippet-1', type: 'snippet', content: 'code' },
      ];

      for (let i = 0; i < 3; i++) {
        await reviewService.createRequest(
          'ws-priority',
          'user-alice',
          `Urgent ${i}`,
          'Description',
          targets,
          ['user-bob'],
          'urgent'
        );
      }

      for (let i = 0; i < 2; i++) {
        await reviewService.createRequest(
          'ws-priority',
          'user-alice',
          `High ${i}`,
          'Description',
          targets,
          ['user-bob'],
          'high'
        );
      }
    });

    it('should get requests by priority', async () => {
      const urgent = await reviewService.getRequestsByPriority(
        'ws-priority',
        'urgent'
      );

      expect(urgent.length).toBe(3);
      expect(urgent.every((r) => r.priority === 'urgent')).toBe(true);
    });

    it('should sort by creation date', async () => {
      const urgent = await reviewService.getRequestsByPriority(
        'ws-priority',
        'urgent'
      );

      // Newest first
      expect(urgent[0].createdAt).toBeGreaterThanOrEqual(urgent[1].createdAt);
    });
  });

  describe('Event Emission', () => {
    it('should emit request-created event', async () => {
      return new Promise<void>((resolve) => {
        const targets: ReviewTarget[] = [
          { id: 'snippet-1', type: 'snippet', content: 'code' },
        ];

        reviewService.once('request-created', (request) => {
          expect(request.title).toBe('New review');
          resolve();
        });

        reviewService.createRequest(
          'ws-test',
          'user-alice',
          'New review',
          'Description',
          targets,
          ['user-bob']
        );
      });
    });
  });

  describe('Global Singleton', () => {
    it('should return same instance', async () => {
      const service1 = await getCodeReviewService();
      const service2 = await getCodeReviewService();

      expect(service1).toBe(service2);
    });
  });

  describe('Integration', () => {
    it('should handle complete review workflow', async () => {
      const targets: ReviewTarget[] = [
        {
          id: 'file-1',
          type: 'file',
          path: 'src/app.ts',
          language: 'typescript',
        },
      ];

      // 1. Create request
      const requestId = await reviewService.createRequest(
        'ws-workflow',
        'user-alice',
        'Critical refactor',
        'Please review the new architecture',
        targets,
        ['user-bob', 'user-charlie'],
        'urgent'
      );

      // 2. Set reviewer badges
      await reviewService.setReviewerBadges(requestId, {
        'user-bob': {
          reviewerId: 'user-bob',
          role: 'lead',
          required: true,
          approved: false,
          responded: false,
        },
        'user-charlie': {
          reviewerId: 'user-charlie',
          role: 'peer',
          required: false,
          approved: false,
          responded: false,
        },
      });

      // 3. Send notifications
      const notified = await reviewService.sendNotifications(requestId);
      expect(notified).toBe(2);

      // 4. Collect reviews
      await reviewService.submitReview(
        requestId,
        'user-bob',
        'approved',
        'Great work!'
      );
      await reviewService.submitReview(
        requestId,
        'user-charlie',
        'approved',
        'Approved'
      );

      // 5. Verify request is approved
      const request = await reviewService.getRequest(requestId);
      expect(request?.status).toBe('approved');

      // 6. Get statistics
      const stats = await reviewService.getStatistics('ws-workflow');
      expect(stats.approvedRequests).toBe(1);
    });
  });
});
