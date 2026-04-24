#!/usr/bin/env node
// @file        apps/backend/src/services/collaboration/__tests__/code-review-request-service.test.ts
// @module      services/collaboration
// @description Tests for code review request service

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
vi.mock('../../../lib/tracing', () => ({
  getTracer: () => ({
    startActiveSpan: (_name: string, _options: unknown, callback: (span: { setStatus: () => void; recordException: () => void; end: () => void }) => unknown) =>
      callback({
        setStatus: vi.fn(),
        recordException: vi.fn(),
        end: vi.fn(),
      }),
  }),
  withSpanSync: (_tracer: unknown, _name: string, _attributes: Record<string, string | number | boolean>, fn: (span: { setStatus: () => void; recordException: () => void; end: () => void }) => unknown) =>
    fn({
      setStatus: vi.fn(),
      recordException: vi.fn(),
      end: vi.fn(),
    }),
}));
import service, { CodeReviewRequestService } from '../code-review-request-service';

describe('CodeReviewRequestService', () => {
  beforeEach(() => {
    service.reset();
    service.removeAllListeners();
  });

  afterEach(() => {
    service.reset();
    service.removeAllListeners();
  });

  describe('Singleton Pattern', () => {
    it('should return the same instance', () => {
      const instance1 = CodeReviewRequestService.getInstance();
      const instance2 = CodeReviewRequestService.getInstance();
      expect(instance1).toBe(instance2);
    });
  });

  describe('Create Review Request', () => {
    it('should create a new review request', () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Please review this code', 'normal', '/src/app.ts');

      expect(request.id).toBeDefined();
      expect(request.requesterId).toBe('user1');
      expect(request.reviewerId).toBe('user2');
      expect(request.workspaceId).toBe('ws-123');
      expect(request.status).toBe('pending');
      expect(request.priority).toBe('normal');
    });

    it('should create request with high priority', () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Urgent review needed', 'critical');

      expect(request.priority).toBe('critical');
    });

    it('should create request with due date', () => {
      const dueAt = Date.now() + 24 * 60 * 60 * 1000;
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review with deadline', 'high', undefined, dueAt);

      expect(request.dueAt).toBe(dueAt);
    });

    it('should emit reviewRequested event', async () => {
      return new Promise<void>((resolve) => {
        service.once('reviewRequested', (request) => {
          expect(request.requesterId).toBe('user1');
          resolve();
        });

        service.createRequest('user1', 'user2', 'ws-123', 'Review this');
      });
    });

    it('should create notification when request created', () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review this');
      const notifications = service.getNotificationsForUser('user2');

      expect(notifications.length).toBeGreaterThan(0);
      expect(notifications[0].type).toBe('review_requested');
    });
  });

  describe('Get Review Request', () => {
    it('should retrieve an existing request', () => {
      const created = service.createRequest('user1', 'user2', 'ws-123', 'Review');
      const retrieved = service.getRequest(created.id);

      expect(retrieved).toEqual(created);
    });

    it('should return undefined for non-existent request', () => {
      const result = service.getRequest('non-existent');
      expect(result).toBeUndefined();
    });
  });

  describe('Get Pending Requests for Reviewer', () => {
    it('should get pending requests for a reviewer', () => {
      service.createRequest('user1', 'user2', 'ws-123', 'Review 1');
      service.createRequest('user1', 'user2', 'ws-123', 'Review 2');
      service.createRequest('user3', 'user2', 'ws-123', 'Review 3');

      const pending = service.getPendingRequestsForReviewer('user2');

      expect(pending).toHaveLength(3);
      expect(pending.every((r) => r.status === 'pending')).toBe(true);
    });

    it('should not return non-pending requests', () => {
      const request1 = service.createRequest('user1', 'user2', 'ws-123', 'Review 1');
      service.createRequest('user1', 'user2', 'ws-123', 'Review 2');

      service.respondToRequest(request1.id, 'user2', 'approved', 'Looks good');

      const pending = service.getPendingRequestsForReviewer('user2');

      expect(pending).toHaveLength(1);
    });
  });

  describe('Get Requests by Requester', () => {
    it('should get all requests from a requester', () => {
      service.createRequest('user1', 'user2', 'ws-123', 'Review 1');
      service.createRequest('user1', 'user3', 'ws-123', 'Review 2');
      service.createRequest('user2', 'user3', 'ws-123', 'Review 3');

      const requests = service.getRequestsByRequester('user1');

      expect(requests).toHaveLength(2);
      expect(requests.every((r) => r.requesterId === 'user1')).toBe(true);
    });
  });

  describe('Respond to Request', () => {
    it('should approve a request', () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review');
      const updated = service.respondToRequest(request.id, 'user2', 'approved', 'Approved');

      expect(updated?.status).toBe('approved');
      expect(updated?.response?.status).toBe('approved');
      expect(updated?.response?.comment).toBe('Approved');
    });

    it('should request changes', () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review');
      const updated = service.respondToRequest(request.id, 'user2', 'requested_changes', 'Please fix X');

      expect(updated?.status).toBe('requested_changes');
    });

    it('should create badge on approval', () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review');
      const updated = service.respondToRequest(request.id, 'user2', 'approved', 'Good');

      expect(updated?.badge).toBeDefined();
      expect(updated?.badge?.type).toBe('approved');
      expect(updated?.badge?.count).toBe(1);
    });

    it('should emit reviewResponded event', async () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review');

      return new Promise<void>((resolve) => {
        service.once('reviewResponded', (updated) => {
          expect(updated.status).toBe('approved');
          resolve();
        });

        service.respondToRequest(request.id, 'user2', 'approved', 'Good');
      });
    });

    it('should return undefined for non-existent request', () => {
      const result = service.respondToRequest('non-existent', 'user2', 'approved', 'Good');
      expect(result).toBeUndefined();
    });
  });

  describe('Dismiss Request', () => {
    it('should dismiss a request', () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review');
      const updated = service.dismissRequest(request.id);

      expect(updated?.status).toBe('dismissed');
    });

    it('should emit reviewDismissed event', async () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review');

      return new Promise<void>((resolve) => {
        service.once('reviewDismissed', (updated) => {
          expect(updated.status).toBe('dismissed');
          resolve();
        });

        service.dismissRequest(request.id);
      });
    });
  });

  describe('Due Dates', () => {
    it('should set due date', () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review');
      const dueAt = Date.now() + 24 * 60 * 60 * 1000;

      const updated = service.setDueDate(request.id, dueAt);

      expect(updated?.dueAt).toBe(dueAt);
    });

    it('should identify overdue requests', () => {
      const pastDueDate = Date.now() - 1000; // 1 second ago
      service.createRequest('user1', 'user2', 'ws-123', 'Review 1', 'normal', undefined, pastDueDate);
      service.createRequest('user1', 'user2', 'ws-123', 'Review 2'); // No due date

      const overdue = service.getOverdueRequests();

      expect(overdue).toHaveLength(1);
    });

    it('should not include completed requests in overdue', () => {
      const pastDueDate = Date.now() - 1000;
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review', 'normal', undefined, pastDueDate);
      service.respondToRequest(request.id, 'user2', 'approved', 'Good');

      const overdue = service.getOverdueRequests();

      expect(overdue).toHaveLength(0);
    });
  });

  describe('Reminders', () => {
    it('should send reminder for pending request', () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review');

      return new Promise<void>((resolve) => {
        service.once('reminderSent', (updated) => {
          expect(updated.id).toBe(request.id);
          resolve();
        });

        service.sendReminder(request.id);
      });
    });

    it('should create notification for reminder', () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review');
      service.sendReminder(request.id);

      const notifications = service.getNotificationsForUser('user2');
      const reminderNotif = notifications.find((n) => n.type === 'review_reminder');

      expect(reminderNotif).toBeDefined();
    });
  });

  describe('Notifications', () => {
    it('should get notifications for a user', () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review');

      const notifications = service.getNotificationsForUser('user2');

      expect(notifications).toHaveLength(1);
      expect(notifications[0].recipientId).toBe('user2');
    });

    it('should mark notification as read', () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review');
      const notifications = service.getNotificationsForUser('user2');

      const updated = service.markNotificationAsRead(notifications[0].id);

      expect(updated?.read).toBe(true);
    });

    it('should count unread notifications', () => {
      service.createRequest('user1', 'user2', 'ws-123', 'Review 1');
      service.createRequest('user1', 'user2', 'ws-123', 'Review 2');

      const unread = service.getUnreadNotificationCount('user2');

      expect(unread).toBe(2);
    });

    it('should not count read notifications', () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review');
      const notifications = service.getNotificationsForUser('user2');

      service.markNotificationAsRead(notifications[0].id);

      const unread = service.getUnreadNotificationCount('user2');

      expect(unread).toBe(0);
    });
  });

  describe('Badges', () => {
    it('should get reviewer badges', () => {
      const request1 = service.createRequest('user1', 'user2', 'ws-123', 'Review 1');
      const request2 = service.createRequest('user3', 'user2', 'ws-123', 'Review 2');

      service.respondToRequest(request1.id, 'user2', 'approved', 'Good');
      service.respondToRequest(request2.id, 'user2', 'approved', 'Good');

      const badges = service.getReviewerBadges('user2');

      expect(badges.length).toBeGreaterThan(0);
      expect(badges[0].type).toBe('approved');
    });
  });

  describe('Reviewer Statistics', () => {
    it('should calculate reviewer statistics', () => {
      const request1 = service.createRequest('user1', 'user2', 'ws-123', 'Review 1');
      const request2 = service.createRequest('user1', 'user2', 'ws-123', 'Review 2');

      service.respondToRequest(request1.id, 'user2', 'approved', 'Good');

      const stats = service.getReviewerStats('user2');

      expect(stats.totalRequests).toBe(2);
      expect(stats.approvedCount).toBe(1);
      expect(stats.pendingCount).toBe(1);
      expect(stats.averageResponseTime).toBeGreaterThanOrEqual(0);
    });

    it('should track changes requested', () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review');

      service.respondToRequest(request.id, 'user2', 'requested_changes', 'Fix X');

      const stats = service.getReviewerStats('user2');

      expect(stats.changesRequestedCount).toBe(1);
    });
  });

  describe('Expire Old Requests', () => {
    it('should expire old requests', () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review');

      // Mock old creation time
      request.createdAt = Date.now() - 31 * 24 * 60 * 60 * 1000; // 31 days ago

      const expired = service.expireOldRequests();

      expect(expired).toHaveLength(1);
      expect(expired[0].status).toBe('expired');
    });

    it('should not expire recent requests', () => {
      service.createRequest('user1', 'user2', 'ws-123', 'Review');

      const expired = service.expireOldRequests();

      expect(expired).toHaveLength(0);
    });
  });

  describe('Workspace Statistics', () => {
    it('should get workspace statistics', () => {
      service.createRequest('user1', 'user2', 'ws-123', 'Review 1', 'normal');
      service.createRequest('user1', 'user2', 'ws-123', 'Review 2', 'high');
      service.createRequest('user3', 'user2', 'ws-456', 'Review 3'); // Different workspace

      const stats = service.getWorkspaceStats('ws-123');

      expect(stats.totalRequests).toBe(2);
      expect(stats.pendingRequests).toBe(2);
      expect(stats.highPriorityPending).toBe(1);
    });

    it('should calculate average response time for workspace', () => {
      const request1 = service.createRequest('user1', 'user2', 'ws-123', 'Review 1');
      const request2 = service.createRequest('user1', 'user2', 'ws-123', 'Review 2');

      service.respondToRequest(request1.id, 'user2', 'approved', 'Good');
      service.respondToRequest(request2.id, 'user2', 'approved', 'Good');

      const stats = service.getWorkspaceStats('ws-123');

      expect(stats.averageResponseTime).toBeGreaterThanOrEqual(0);
      expect(stats.approvedCount).toBe(2);
    });
  });

  describe('Get Requests by Workspace', () => {
    it('should get all requests for a workspace', () => {
      service.createRequest('user1', 'user2', 'ws-123', 'Review 1');
      service.createRequest('user1', 'user2', 'ws-123', 'Review 2');
      service.createRequest('user1', 'user2', 'ws-456', 'Review 3');

      const requests = service.getRequestsByWorkspace('ws-123');

      expect(requests).toHaveLength(2);
      expect(requests.every((r) => r.workspaceId === 'ws-123')).toBe(true);
    });
  });

  describe('Edge Cases', () => {
    it('should handle empty requests', () => {
      const pending = service.getPendingRequestsForReviewer('user-not-exists');
      expect(pending).toHaveLength(0);
    });

    it('should handle multiple responses to same request', () => {
      const request = service.createRequest('user1', 'user2', 'ws-123', 'Review');

      service.respondToRequest(request.id, 'user2', 'commented', 'Saw this');
      const updated = service.respondToRequest(request.id, 'user2', 'approved', 'Now approved');

      expect(updated?.status).toBe('approved');
      expect(updated?.response?.comment).toBe('Now approved');
    });

    it('should handle concurrent requests from same requester to same reviewer', () => {
      service.createRequest('user1', 'user2', 'ws-123', 'Review 1');
      service.createRequest('user1', 'user2', 'ws-123', 'Review 2');
      service.createRequest('user1', 'user2', 'ws-123', 'Review 3');

      const requests = service.getRequestsByRequester('user1');

      expect(requests).toHaveLength(3);
      expect(requests.every((r) => r.reviewerId === 'user2')).toBe(true);
    });

    it('should handle priority levels correctly', () => {
      service.createRequest('user1', 'user2', 'ws-123', 'Review 1', 'low');
      service.createRequest('user1', 'user2', 'ws-123', 'Review 2', 'high');
      service.createRequest('user1', 'user2', 'ws-123', 'Review 3', 'critical');

      const stats = service.getWorkspaceStats('ws-123');

      expect(stats.highPriorityPending).toBe(2);
    });
  });
});
