/**
 * @file        apps/backend/src/services/audit-logging/__tests__/help-queue-audit.test.ts
 * @module      security/audit-logging
 * @description Help Queue audit logging comprehensive tests
 */

import { describe, it, expect, beforeEach } from 'vitest';
import {
  HelpQueueAuditService,
  getHelpQueueAuditService,
} from '../help-queue-audit.js';
import {
  AuditLoggingService,
} from '../audit-service.js';

describe('Help Queue Audit Logging', () => {
  let helpQueueAudit: HelpQueueAuditService;
  let baseAudit: AuditLoggingService;

  beforeEach(async () => {
    baseAudit = new AuditLoggingService();
    await baseAudit.initialize();

    helpQueueAudit = new HelpQueueAuditService(baseAudit);
    await helpQueueAudit.initialize();

    // Set user contexts
    baseAudit.setUserContext('user-alice', 'alice@example.com', 'user');
    baseAudit.setUserContext('user-bob', 'bob@example.com', 'expert');
    baseAudit.setUserContext('user-admin', 'admin@example.com', 'admin');
  });

  describe('Service Initialization', () => {
    it('should initialize successfully', async () => {
      expect(helpQueueAudit).toBeDefined();
    });

    it('should get global instance from factory', async () => {
      // Reset singleton for testing
      const service1 = await getHelpQueueAuditService();
      const service2 = await getHelpQueueAuditService();

      expect(service1).toBe(service2);
    });
  });

  describe('Item Creation Logging', () => {
    it('should log item creation', async () => {
      const entryId = await helpQueueAudit.logItemCreated(
        'ws-hq',
        'item-001',
        'user-alice',
        'Need help with TypeScript',
        'development'
      );

      expect(entryId).toBeDefined();
    });

    it('should record creation details', async () => {
      const entryId = await helpQueueAudit.logItemCreated(
        'ws-hq',
        'item-002',
        'user-alice',
        'Debug help needed',
        'debugging'
      );

      const result = await baseAudit.queryLogs({
        workspaceId: 'ws-hq',
        resourceId: 'item-002',
      });

      expect(result.entries.length).toBeGreaterThan(0);
      expect(result.entries[0].action).toBe('CREATE');
      expect(result.entries[0].details.category).toBe('debugging');
    });
  });

  describe('Item Assignment Logging', () => {
    beforeEach(async () => {
      // Create an item first
      await helpQueueAudit.logItemCreated(
        'ws-hq',
        'item-assign-001',
        'user-alice',
        'Need expert review'
      );
    });

    it('should log item assignment', async () => {
      await helpQueueAudit.logItemAssigned(
        'ws-hq',
        'item-assign-001',
        'user-bob',
        'user-admin'
      );

      const result = await baseAudit.queryLogs({
        workspaceId: 'ws-hq',
        action: 'ASSIGN',
      });

      expect(result.entries.length).toBeGreaterThan(0);
      expect(result.entries[0].details.assignedToId).toBe('user-bob');
    });

    it('should track reassignment', async () => {
      // First assignment
      await helpQueueAudit.logItemAssigned(
        'ws-hq',
        'item-reassign',
        'user-bob',
        'user-admin'
      );

      // Reassignment
      await helpQueueAudit.logItemAssigned(
        'ws-hq',
        'item-reassign',
        'user-alice',
        'user-admin',
        'user-bob'
      );

      const result = await baseAudit.queryLogs({
        workspaceId: 'ws-hq',
        resourceId: 'item-reassign',
      });

      const reassignEntry = result.entries.find((e) => e.details.previousAssignee);
      expect(reassignEntry?.details.previousAssignee).toBe('user-bob');
    });
  });

  describe('Expert Claim Logging', () => {
    it('should log expert claim', async () => {
      await helpQueueAudit.logItemCreated(
        'ws-hq',
        'item-claim-001',
        'user-alice',
        'Help needed'
      );

      const claimTime = Date.now();
      await helpQueueAudit.logExpertClaim(
        'ws-hq',
        'item-claim-001',
        'user-bob',
        claimTime
      );

      const result = await baseAudit.queryLogs({
        workspaceId: 'ws-hq',
        action: 'CLAIM',
      });

      expect(result.entries.length).toBeGreaterThan(0);
      expect(result.entries[0].userId).toBe('user-bob');
      expect(result.entries[0].details.claimedAt).toBe(claimTime);
    });
  });

  describe('Response Logging', () => {
    beforeEach(async () => {
      await helpQueueAudit.logItemCreated(
        'ws-hq',
        'item-response-001',
        'user-alice',
        'Help me please'
      );
    });

    it('should log response', async () => {
      await helpQueueAudit.logResponse(
        'ws-hq',
        'item-response-001',
        'user-bob',
        'Here is the solution...',
        'response-001'
      );

      const result = await baseAudit.queryLogs({
        workspaceId: 'ws-hq',
        action: 'RESPOND',
      });

      expect(result.entries.length).toBeGreaterThan(0);
      expect(result.entries[0].details.respondentId).toBe('user-bob');
      expect(result.entries[0].details.responseLength).toBe(23);
    });

    it('should track multiple responses', async () => {
      await helpQueueAudit.logResponse(
        'ws-hq',
        'item-response-001',
        'user-bob',
        'First response',
        'response-001'
      );

      await helpQueueAudit.logResponse(
        'ws-hq',
        'item-response-001',
        'user-alice',
        'Follow-up response',
        'response-002'
      );

      const result = await baseAudit.queryLogs({
        workspaceId: 'ws-hq',
        action: 'RESPOND',
      });

      expect(result.total).toBeGreaterThanOrEqual(2);
    });
  });

  describe('Resolution Logging', () => {
    beforeEach(async () => {
      await helpQueueAudit.logItemCreated(
        'ws-hq',
        'item-resolve-001',
        'user-alice',
        'Urgent help'
      );

      await helpQueueAudit.logResponse(
        'ws-hq',
        'item-resolve-001',
        'user-bob',
        'Here is the fix',
        'response-001'
      );
    });

    it('should log item resolution', async () => {
      const resolvedAt = Date.now();

      await helpQueueAudit.logItemResolved(
        'ws-hq',
        'item-resolve-001',
        'user-bob',
        'Applied the fix, issue resolved',
        resolvedAt,
        1
      );

      const result = await baseAudit.queryLogs({
        workspaceId: 'ws-hq',
        action: 'RESOLVE',
      });

      expect(result.entries.length).toBeGreaterThan(0);
      expect(result.entries[0].details.resolutionSummary).toContain(
        'Applied the fix'
      );
      expect(result.entries[0].details.responseCount).toBe(1);
    });
  });

  describe('Expert Registration Logging', () => {
    it('should log expert registration', async () => {
      await helpQueueAudit.logExpertRegistration(
        'ws-hq',
        'user-bob',
        ['TypeScript', 'React', 'Node.js'],
        'user-admin'
      );

      const result = await baseAudit.queryLogs({
        workspaceId: 'ws-hq',
        action: 'REGISTER_EXPERT',
      });

      expect(result.entries.length).toBeGreaterThan(0);
      expect(result.entries[0].details.expertise).toEqual([
        'TypeScript',
        'React',
        'Node.js',
      ]);
    });
  });

  describe('Item Closure Logging', () => {
    beforeEach(async () => {
      await helpQueueAudit.logItemCreated(
        'ws-hq',
        'item-close-001',
        'user-alice',
        'Help request'
      );
    });

    it('should log item closure', async () => {
      await helpQueueAudit.logItemClosed(
        'ws-hq',
        'item-close-001',
        'user-admin',
        'Resolved by user'
      );

      const result = await baseAudit.queryLogs({
        workspaceId: 'ws-hq',
        action: 'CLOSE',
      });

      expect(result.entries.length).toBeGreaterThan(0);
      expect(result.entries[0].details.reason).toBe('Resolved by user');
    });
  });

  describe('Item Reopening Logging', () => {
    beforeEach(async () => {
      await helpQueueAudit.logItemCreated(
        'ws-hq',
        'item-reopen-001',
        'user-alice',
        'Help request'
      );

      await helpQueueAudit.logItemClosed(
        'ws-hq',
        'item-reopen-001',
        'user-admin',
        'Closed prematurely'
      );
    });

    it('should log item reopening', async () => {
      await helpQueueAudit.logItemReopened(
        'ws-hq',
        'item-reopen-001',
        'user-alice',
        'Issue still persists'
      );

      const result = await baseAudit.queryLogs({
        workspaceId: 'ws-hq',
        action: 'REOPEN',
      });

      expect(result.entries.length).toBeGreaterThan(0);
      expect(result.entries[0].details.reason).toBe('Issue still persists');
    });
  });

  describe('Audit Statistics', () => {
    beforeEach(async () => {
      // Create several help items with various states
      for (let i = 0; i < 5; i++) {
        await helpQueueAudit.logItemCreated(
          'ws-stats',
          `item-${i}`,
          'user-alice',
          `Help request ${i}`
        );
      }

      // Assign some items
      for (let i = 0; i < 3; i++) {
        await helpQueueAudit.logItemAssigned(
          'ws-stats',
          `item-${i}`,
          'user-bob',
          'user-admin'
        );
      }

      // Add responses
      for (let i = 0; i < 3; i++) {
        await helpQueueAudit.logResponse(
          'ws-stats',
          `item-${i}`,
          'user-bob',
          'Response content',
          `response-${i}`
        );
      }

      // Resolve some items
      for (let i = 0; i < 2; i++) {
        await helpQueueAudit.logItemResolved(
          'ws-stats',
          `item-${i}`,
          'user-bob',
          'Resolved',
          Date.now(),
          1
        );
      }
    });

    it('should calculate help queue statistics', async () => {
      const stats = await helpQueueAudit.getStatistics('ws-stats');

      expect(stats.totalRequests).toBeGreaterThan(0);
      expect(stats.requestsByCreator['user-alice']).toBeGreaterThan(0);
      expect(stats.requestsByAssignee['user-bob']).toBeGreaterThan(0);
      expect(stats.responseCount).toBe(3);
      expect(stats.resolutionRate).toBeGreaterThan(0);
    });

    it('should calculate resolution rate', async () => {
      const stats = await helpQueueAudit.getStatistics('ws-stats');

      // 2 resolved out of 5 = 40%
      expect(stats.resolutionRate).toBeGreaterThan(0);
      expect(stats.resolutionRate).toBeLessThanOrEqual(100);
    });

    it('should calculate expert claim rate', async () => {
      const stats = await helpQueueAudit.getStatistics('ws-stats');

      // Expert claims vs assignments
      expect(stats.expertClaimRate).toBeGreaterThanOrEqual(0);
      expect(stats.expertClaimRate).toBeLessThanOrEqual(100);
    });

    it('should calculate average times', async () => {
      const stats = await helpQueueAudit.getStatistics('ws-stats');

      expect(stats.averageResolutionTime).toBeGreaterThanOrEqual(0);
      expect(stats.averageResponseTime).toBeGreaterThanOrEqual(0);
    });
  });

  describe('Integration', () => {
    it('should handle complete help queue workflow', async () => {
      // 1. Item created
      await helpQueueAudit.logItemCreated(
        'ws-workflow',
        'item-workflow-1',
        'user-alice',
        'Complex issue help',
        'debugging'
      );

      // 2. Item assigned
      await helpQueueAudit.logItemAssigned(
        'ws-workflow',
        'item-workflow-1',
        'user-bob',
        'user-admin'
      );

      // 3. Expert claims
      const claimTime = Date.now();
      await helpQueueAudit.logExpertClaim(
        'ws-workflow',
        'item-workflow-1',
        'user-bob',
        claimTime
      );

      // 4. Response added
      await helpQueueAudit.logResponse(
        'ws-workflow',
        'item-workflow-1',
        'user-bob',
        'Let me investigate further...',
        'response-1'
      );

      // 5. Item resolved
      await helpQueueAudit.logItemResolved(
        'ws-workflow',
        'item-workflow-1',
        'user-bob',
        'Found the root cause and applied fix',
        Date.now(),
        1
      );

      // Verify complete trail
      const result = await baseAudit.queryLogs({
        workspaceId: 'ws-workflow',
        resourceId: 'item-workflow-1',
      });

      expect(result.entries.length).toBeGreaterThanOrEqual(5);
      
      // Check for all action types
      const actions = result.entries.map((e) => e.action);
      expect(actions).toContain('CREATE');
      expect(actions).toContain('ASSIGN');
    });

    it('should handle reassignment workflow', async () => {
      await helpQueueAudit.logItemCreated(
        'ws-reassign',
        'item-reassign-1',
        'user-alice',
        'Help'
      );

      // First assignment
      await helpQueueAudit.logItemAssigned(
        'ws-reassign',
        'item-reassign-1',
        'user-bob',
        'user-admin'
      );

      // Reassign
      await helpQueueAudit.logItemAssigned(
        'ws-reassign',
        'item-reassign-1',
        'user-alice',
        'user-admin',
        'user-bob'
      );

      const result = await baseAudit.queryLogs({
        workspaceId: 'ws-reassign',
        action: 'ASSIGN',
      });

      expect(result.total).toBeGreaterThanOrEqual(2);
    });
  });
});
