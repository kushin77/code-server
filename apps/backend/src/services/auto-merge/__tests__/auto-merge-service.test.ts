/**
 * Auto-merge Service Tests
 * @file        apps/backend/src/services/auto-merge/__tests__/auto-merge-service.test.ts
 * @module      services/auto-merge
 * @description Test suite for automatic PR merging with policies and approvals
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { AutoMergeService } from '../auto-merge-service.js';
import { AutoMergePolicy, PullRequestMetadata } from '../types.js';

describe('Auto-merge Service', () => {
  let service: AutoMergeService;

  beforeEach(() => {
    (AutoMergeService as any).reset();
    service = AutoMergeService.getInstance();
  });

  afterEach(() => {
    service.shutdown();
  });

  describe('Initialization', () => {
    it('should initialize service', () => {
      expect(service).toBeDefined();
      expect((service as any).policies).toBeDefined();
      expect((service as any).autoMergeRequests).toBeDefined();
    });

    it('should return same instance on subsequent calls', () => {
      const instance1 = AutoMergeService.getInstance();
      const instance2 = AutoMergeService.getInstance();
      expect(instance1).toBe(instance2);
    });
  });

  describe('Create Policy', () => {
    it('should create policy successfully', () => {
      const result = service.createPolicy(
        {
          repoId: 'repo-1',
          name: 'Auto-merge on approval',
          requiredApprovals: 2,
          mergeStrategy: 'squash',
        },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
      expect(result.policyId).toBeDefined();
    });

    it('should emit policy-created event', () => {
      return new Promise<void>((resolve) => {
        service.once('policy-created', (event) => {
          expect(event.data_object.policyId).toBeDefined();
          expect(event.data_object.repoId).toBe('repo-1');
          resolve();
        });

        service.createPolicy(
          { repoId: 'repo-1', name: 'Test policy' },
          { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
          '192.168.1.1',
          'Mozilla'
        );
      });
    });

    it('should set default values', () => {
      const result = service.createPolicy(
        { repoId: 'repo-1', name: 'Test' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const policy = service.getPolicy(result.policyId!);
      expect(policy.policy?.enabled).toBe(true);
      expect(policy.policy?.requiredApprovals).toBe(2);
    });
  });

  describe('Update Policy', () => {
    it('should update policy successfully', () => {
      const createResult = service.createPolicy(
        { repoId: 'repo-1', name: 'Original' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const updateResult = service.updatePolicy(
        createResult.policyId!,
        { name: 'Updated', requiredApprovals: 3 },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      expect(updateResult.success).toBe(true);
      expect(updateResult.policy?.name).toBe('Updated');
      expect(updateResult.policy?.requiredApprovals).toBe(3);
    });

    it('should emit policy-updated event', () => {
      return new Promise<void>((resolve) => {
        const createResult = service.createPolicy(
          { repoId: 'repo-1', name: 'Test' },
          { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
          '192.168.1.1',
          'Mozilla'
        );

        service.once('policy-updated', (event) => {
          expect(event.data_object.policyId).toBe(createResult.policyId);
          resolve();
        });

        service.updatePolicy(
          createResult.policyId!,
          { name: 'Updated' },
          { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
          '192.168.1.1',
          'Mozilla'
        );
      });
    });

    it('should return error if policy not found', () => {
      const result = service.updatePolicy(
        'nonexistent',
        { name: 'Updated' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(false);
      expect(result.error).toBe('Policy not found');
    });
  });

  describe('Delete Policy', () => {
    it('should delete policy successfully', () => {
      const createResult = service.createPolicy(
        { repoId: 'repo-1', name: 'To delete' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const deleteResult = service.deletePolicy(
        createResult.policyId!,
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      expect(deleteResult.success).toBe(true);

      const getResult = service.getPolicy(createResult.policyId!);
      expect(getResult.success).toBe(false);
    });

    it('should emit policy-deleted event', () => {
      return new Promise<void>((resolve) => {
        const createResult = service.createPolicy(
          { repoId: 'repo-1', name: 'Test' },
          { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
          '192.168.1.1',
          'Mozilla'
        );

        service.once('policy-deleted', (event) => {
          expect(event.data_object.policyId).toBe(createResult.policyId);
          resolve();
        });

        service.deletePolicy(
          createResult.policyId!,
          { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
          '192.168.1.1',
          'Mozilla'
        );
      });
    });
  });

  describe('Get Policy', () => {
    it('should retrieve policy by ID', () => {
      const createResult = service.createPolicy(
        { repoId: 'repo-1', name: 'Test' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const getResult = service.getPolicy(createResult.policyId!);

      expect(getResult.success).toBe(true);
      expect(getResult.policy?.id).toBe(createResult.policyId);
    });

    it('should return error for nonexistent policy', () => {
      const result = service.getPolicy('nonexistent');
      expect(result.success).toBe(false);
      expect(result.error).toBe('Policy not found');
    });
  });

  describe('List Policies', () => {
    it('should list policies by repo', () => {
      service.createPolicy(
        { repoId: 'repo-1', name: 'Policy 1' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      service.createPolicy(
        { repoId: 'repo-1', name: 'Policy 2' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      service.createPolicy(
        { repoId: 'repo-2', name: 'Policy 3' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.listPolicies('repo-1');

      expect(result.success).toBe(true);
      expect(result.policies.length).toBe(2);
    });

    it('should return empty list for repo with no policies', () => {
      const result = service.listPolicies('nonexistent-repo');

      expect(result.success).toBe(true);
      expect(result.policies.length).toBe(0);
    });
  });

  describe('Evaluate Merge', () => {
    it('should approve merge when all conditions met', () => {
      const policyResult = service.createPolicy(
        { repoId: 'repo-1', name: 'Test', requiredApprovals: 2 },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const pr: PullRequestMetadata = {
        id: 'pr-1',
        number: 123,
        repoId: 'repo-1',
        title: 'Feature X',
        description: 'Adds feature X',
        author: { userId: 'user1', userEmail: 'user1@example.com', userName: 'User 1' },
        sourceBranch: 'feature-x',
        targetBranch: 'main',
        createdAt: Date.now() - 10000,
        updatedAt: Date.now(),
        isDraft: false,
        isMergeable: true,
        mergeableState: 'clean',
        approvalCount: 2,
        reviewers: [
          {
            userId: 'reviewer1',
            userEmail: 'reviewer1@example.com',
            userName: 'Reviewer 1',
            state: 'approved',
            isCodeOwner: false,
          },
          {
            userId: 'reviewer2',
            userEmail: 'reviewer2@example.com',
            userName: 'Reviewer 2',
            state: 'approved',
            isCodeOwner: false,
          },
        ],
        requiredStatusChecks: [
          { name: 'test', status: 'success' },
          { name: 'lint', status: 'success' },
        ],
        labels: [],
        conversationResolved: true,
      };

      const result = service.evaluateMerge(pr, policyResult.policyId!);

      expect(result.canAutoMerge).toBe(true);
      expect(result.approvalsSatisfied).toBe(true);
      expect(result.blockingReasons.length).toBe(0);
    });

    it('should block merge with insufficient approvals', () => {
      const policyResult = service.createPolicy(
        { repoId: 'repo-1', name: 'Test', requiredApprovals: 3 },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const pr: PullRequestMetadata = {
        id: 'pr-1',
        number: 123,
        repoId: 'repo-1',
        title: 'Feature',
        description: 'Feature',
        author: { userId: 'user1', userEmail: 'user1@example.com', userName: 'User 1' },
        sourceBranch: 'feature',
        targetBranch: 'main',
        createdAt: Date.now() - 10000,
        updatedAt: Date.now(),
        isDraft: false,
        isMergeable: true,
        mergeableState: 'clean',
        approvalCount: 1,
        reviewers: [],
        requiredStatusChecks: [],
        labels: [],
        conversationResolved: true,
      };

      const result = service.evaluateMerge(pr, policyResult.policyId!);

      expect(result.canAutoMerge).toBe(false);
      expect(result.approvalsSatisfied).toBe(false);
      expect(result.blockingReasons).toContain(
        'Requires 3 approvals, has 1'
      );
    });

    it('should block merge when branch is behind', () => {
      const policyResult = service.createPolicy(
        {
          repoId: 'repo-1',
          name: 'Test',
          requiredApprovals: 2,
          requireUpToDateBranch: true,
        },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const pr: PullRequestMetadata = {
        id: 'pr-1',
        number: 123,
        repoId: 'repo-1',
        title: 'Feature',
        description: 'Feature',
        author: { userId: 'user1', userEmail: 'user1@example.com', userName: 'User 1' },
        sourceBranch: 'feature',
        targetBranch: 'main',
        createdAt: Date.now() - 10000,
        updatedAt: Date.now(),
        isDraft: false,
        isMergeable: true,
        mergeableState: 'behind',
        approvalCount: 2,
        reviewers: [],
        requiredStatusChecks: [],
        labels: [],
        conversationResolved: true,
      };

      const result = service.evaluateMerge(pr, policyResult.policyId!);

      expect(result.canAutoMerge).toBe(false);
      expect(result.blockingReasons).toContain('Branch is behind target');
    });
  });

  describe('Request Auto-merge', () => {
    it('should create merge request', () => {
      const policyResult = service.createPolicy(
        { repoId: 'repo-1', name: 'Test' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.requestAutoMerge(
        'pr-1',
        policyResult.policyId!,
        { userId: 'user1', userEmail: 'user1@example.com', userName: 'User 1' },
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
      expect(result.requestId).toBeDefined();
    });

    it('should emit merge-requested event', () => {
      return new Promise<void>((resolve) => {
        const policyResult = service.createPolicy(
          { repoId: 'repo-1', name: 'Test' },
          { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
          '192.168.1.1',
          'Mozilla'
        );

        service.once('merge-requested', (event) => {
          expect(event.data_object.prId).toBe('pr-1');
          resolve();
        });

        service.requestAutoMerge(
          'pr-1',
          policyResult.policyId!,
          { userId: 'user1', userEmail: 'user1@example.com', userName: 'User 1' },
          '192.168.1.1',
          'Mozilla'
        );
      });
    });
  });

  describe('Approve Auto-merge', () => {
    it('should approve pending merge request', () => {
      const policyResult = service.createPolicy(
        { repoId: 'repo-1', name: 'Test' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const mergeResult = service.requestAutoMerge(
        'pr-1',
        policyResult.policyId!,
        { userId: 'user1', userEmail: 'user1@example.com', userName: 'User 1' },
        '192.168.1.1',
        'Mozilla'
      );

      const approveResult = service.approveAutoMerge(
        mergeResult.requestId!,
        { userId: 'approver', userEmail: 'approver@example.com', userName: 'Approver' },
        '192.168.1.1',
        'Mozilla'
      );

      expect(approveResult.success).toBe(true);
      expect(approveResult.request?.status).toBe('approved');
    });

    it('should emit merge-approved event', () => {
      return new Promise<void>((resolve) => {
        const policyResult = service.createPolicy(
          { repoId: 'repo-1', name: 'Test' },
          { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
          '192.168.1.1',
          'Mozilla'
        );

        const mergeResult = service.requestAutoMerge(
          'pr-1',
          policyResult.policyId!,
          { userId: 'user1', userEmail: 'user1@example.com', userName: 'User 1' },
          '192.168.1.1',
          'Mozilla'
        );

        service.once('merge-approved', (event) => {
          expect(event.data_object.requestId).toBe(mergeResult.requestId);
          resolve();
        });

        service.approveAutoMerge(
          mergeResult.requestId!,
          { userId: 'approver', userEmail: 'approver@example.com', userName: 'Approver' },
          '192.168.1.1',
          'Mozilla'
        );
      });
    });
  });

  describe('Schedule Merge', () => {
    it('should schedule merge for later', () => {
      const policyResult = service.createPolicy(
        { repoId: 'repo-1', name: 'Test' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const mergeResult = service.requestAutoMerge(
        'pr-1',
        policyResult.policyId!,
        { userId: 'user1', userEmail: 'user1@example.com', userName: 'User 1' },
        '192.168.1.1',
        'Mozilla'
      );

      const scheduledTime = Date.now() + 3600000;
      const scheduleResult = service.scheduleMerge(
        mergeResult.requestId!,
        scheduledTime,
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      expect(scheduleResult.success).toBe(true);
      expect(scheduleResult.request?.status).toBe('scheduled');
    });

    it('should emit merge-scheduled event', () => {
      return new Promise<void>((resolve) => {
        const policyResult = service.createPolicy(
          { repoId: 'repo-1', name: 'Test' },
          { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
          '192.168.1.1',
          'Mozilla'
        );

        const mergeResult = service.requestAutoMerge(
          'pr-1',
          policyResult.policyId!,
          { userId: 'user1', userEmail: 'user1@example.com', userName: 'User 1' },
          '192.168.1.1',
          'Mozilla'
        );

        service.once('merge-scheduled', (event) => {
          expect(event.data_object.requestId).toBe(mergeResult.requestId);
          resolve();
        });

        service.scheduleMerge(
          mergeResult.requestId!,
          Date.now() + 3600000,
          { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
          '192.168.1.1',
          'Mozilla'
        );
      });
    });
  });

  describe('Execute Merge', () => {
    it('should execute merge successfully', () => {
      const policyResult = service.createPolicy(
        { repoId: 'repo-1', name: 'Test' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const mergeResult = service.requestAutoMerge(
        'pr-1',
        policyResult.policyId!,
        { userId: 'user1', userEmail: 'user1@example.com', userName: 'User 1' },
        '192.168.1.1',
        'Mozilla'
      );

      const executeResult = service.executeMerge(
        mergeResult.requestId!,
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      expect(executeResult.success).toBe(true);
      expect(executeResult.mergeCommitId).toBeDefined();
    });

    it('should emit merge-successful event', () => {
      return new Promise<void>((resolve) => {
        const policyResult = service.createPolicy(
          { repoId: 'repo-1', name: 'Test' },
          { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
          '192.168.1.1',
          'Mozilla'
        );

        const mergeResult = service.requestAutoMerge(
          'pr-1',
          policyResult.policyId!,
          { userId: 'user1', userEmail: 'user1@example.com', userName: 'User 1' },
          '192.168.1.1',
          'Mozilla'
        );

        service.once('merge-successful', (event) => {
          expect(event.data_object.requestId).toBe(mergeResult.requestId);
          expect(event.data_object.mergeCommitId).toBeDefined();
          resolve();
        });

        service.executeMerge(
          mergeResult.requestId!,
          { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
          '192.168.1.1',
          'Mozilla'
        );
      });
    });
  });

  describe('Cancel Auto-merge', () => {
    it('should cancel pending merge request', () => {
      const policyResult = service.createPolicy(
        { repoId: 'repo-1', name: 'Test' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const mergeResult = service.requestAutoMerge(
        'pr-1',
        policyResult.policyId!,
        { userId: 'user1', userEmail: 'user1@example.com', userName: 'User 1' },
        '192.168.1.1',
        'Mozilla'
      );

      const cancelResult = service.cancelAutoMerge(
        mergeResult.requestId!,
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        'Policy changed',
        '192.168.1.1',
        'Mozilla'
      );

      expect(cancelResult.success).toBe(true);
      expect(cancelResult.request?.status).toBe('cancelled');
    });

    it('should emit merge-cancelled event', () => {
      return new Promise<void>((resolve) => {
        const policyResult = service.createPolicy(
          { repoId: 'repo-1', name: 'Test' },
          { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
          '192.168.1.1',
          'Mozilla'
        );

        const mergeResult = service.requestAutoMerge(
          'pr-1',
          policyResult.policyId!,
          { userId: 'user1', userEmail: 'user1@example.com', userName: 'User 1' },
          '192.168.1.1',
          'Mozilla'
        );

        service.once('merge-cancelled', (event) => {
          expect(event.data_object.requestId).toBe(mergeResult.requestId);
          resolve();
        });

        service.cancelAutoMerge(
          mergeResult.requestId!,
          { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
          'Reason',
          '192.168.1.1',
          'Mozilla'
        );
      });
    });
  });

  describe('Exceptions', () => {
    it('should add exception to policy', () => {
      const policyResult = service.createPolicy(
        { repoId: 'repo-1', name: 'Test' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const result = service.addException(
        policyResult.policyId!,
        {
          id: '',
          policyId: policyResult.policyId!,
          type: 'block-merge',
          criteria: new Map([['label', 'wip']]),
          action: 'deny',
          createdAt: Date.now(),
        },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      expect(result.success).toBe(true);
      expect(result.exceptionId).toBeDefined();
    });

    it('should remove exception from policy', () => {
      const policyResult = service.createPolicy(
        { repoId: 'repo-1', name: 'Test' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const addResult = service.addException(
        policyResult.policyId!,
        {
          id: '',
          policyId: policyResult.policyId!,
          type: 'block-merge',
          criteria: new Map(),
          action: 'deny',
          createdAt: Date.now(),
        },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const removeResult = service.removeException(
        policyResult.policyId!,
        addResult.exceptionId!,
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      expect(removeResult.success).toBe(true);
    });
  });

  describe('Statistics', () => {
    it('should calculate service statistics', () => {
      service.createPolicy(
        { repoId: 'repo-1', name: 'Policy 1' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      service.createPolicy(
        { repoId: 'repo-1', name: 'Policy 2', enabled: false },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const stats = service.getStatistics();

      expect(stats.totalPolicies).toBe(2);
      expect(stats.activePolicies).toBe(1);
    });

    it('should track successful merges', () => {
      const policyResult = service.createPolicy(
        { repoId: 'repo-1', name: 'Test' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const mergeResult = service.requestAutoMerge(
        'pr-1',
        policyResult.policyId!,
        { userId: 'user1', userEmail: 'user1@example.com', userName: 'User 1' },
        '192.168.1.1',
        'Mozilla'
      );

      service.executeMerge(
        mergeResult.requestId!,
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      const stats = service.getStatistics();
      expect(stats.successfulMerges).toBe(1);
    });

    it('should calculate success rate', () => {
      const policyResult = service.createPolicy(
        { repoId: 'repo-1', name: 'Test' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      for (let i = 0; i < 5; i++) {
        const mergeResult = service.requestAutoMerge(
          `pr-${i}`,
          policyResult.policyId!,
          { userId: 'user1', userEmail: 'user1@example.com', userName: 'User 1' },
          '192.168.1.1',
          'Mozilla'
        );

        if (i < 4) {
          service.executeMerge(
            mergeResult.requestId!,
            { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
            '192.168.1.1',
            'Mozilla'
          );
        }
      }

      const stats = service.getStatistics();
      expect(stats.successRate).toBe(0.8);
    });
  });

  describe('Configuration', () => {
    it('should update configuration', () => {
      return new Promise<void>((resolve) => {
        service.once('config-updated', (event) => {
          expect(event.data_object.userId).toBeDefined();
          resolve();
        });

        service.updateConfig(
          { maxPolicies: 50 },
          'admin',
          '192.168.1.1',
          'Mozilla'
        );
      });
    });
  });

  describe('Shutdown', () => {
    it('should shutdown service cleanly', () => {
      return new Promise<void>((resolve) => {
        service.once('shutdown', (event) => {
          expect(event.data_object.service).toBe('auto-merge');
          resolve();
        });

        service.shutdown();
      });
    });

    it('should clear data on shutdown', () => {
      service.createPolicy(
        { repoId: 'repo-1', name: 'Test' },
        { userId: 'admin', userEmail: 'admin@example.com', userName: 'Admin' },
        '192.168.1.1',
        'Mozilla'
      );

      service.shutdown();

      const stats = service.getStatistics();
      expect(stats.totalPolicies).toBe(0);
    });
  });
});
