/**
 * Auto-merge on Code Review Approval - Type Definitions
 * @file        apps/backend/src/services/auto-merge/types.ts
 * @module      services/auto-merge
 * @description Automatic PR merging on successful code review approval with policies and conditions
 */

import { EventEmitter } from 'events';

/**
 * Auto-merge policy
 */
export interface AutoMergePolicy {
  id: string;
  repoId: string;
  name: string;
  description?: string;
  enabled: boolean;
  createdAt: number;
  updatedAt: number;
  createdBy: PolicyCreator;

  // Approval requirements
  requiredApprovals: number;
  requireCodeOwnerApproval: boolean;
  dismissStaleReviews: boolean;
  requireUpToDateBranch: boolean;

  // Merge strategy
  mergeStrategy: MergeStrategy;
  deleteHeadBranch: boolean;
  commitMessageTemplate?: string;

  // Auto-merge triggers
  autoMergeOnApprovalCount: boolean;
  autoMergeOnLabelAdd: boolean;
  triggerLabels?: string[];

  // Conditions
  conditions: MergeCondition[];
  exceptions: MergeException[];

  // Timing
  autoMergeDelay?: number; // milliseconds
  mergeWindowStart?: number; // hour (0-23)
  mergeWindowEnd?: number; // hour (0-23)

  // Status checks
  requiredStatusChecks: string[];
  allowFailureOnSpecificChecks?: string[];
}

/**
 * Policy creator
 */
export interface PolicyCreator {
  userId: string;
  userEmail: string;
  userName: string;
}

/**
 * Merge strategy
 */
export type MergeStrategy = 'squash' | 'rebase' | 'merge' | 'auto';

/**
 * Merge condition
 */
export interface MergeCondition {
  type: ConditionType;
  value: any;
  operator?: 'equals' | 'contains' | 'matches';
}

/**
 * Condition type
 */
export type ConditionType =
  | 'branch-pattern'
  | 'file-pattern'
  | 'title-pattern'
  | 'label-required'
  | 'label-excluded'
  | 'author-pattern'
  | 'approval-source'
  | 'conversation-resolved';

/**
 * Merge exception
 */
export interface MergeException {
  id: string;
  policyId: string;
  type: ExceptionType;
  criteria: Map<string, any>;
  action: ExceptionAction;
  createdAt: number;
}

/**
 * Exception type
 */
export type ExceptionType = 'block-merge' | 'skip-checks' | 'override-condition';

/**
 * Exception action
 */
export type ExceptionAction = 'allow' | 'deny' | 'skip';

/**
 * Pull request metadata
 */
export interface PullRequestMetadata {
  id: string;
  number: number;
  repoId: string;
  title: string;
  description: string;
  author: PullRequestAuthor;
  sourceBranch: string;
  targetBranch: string;
  createdAt: number;
  updatedAt: number;
  isDraft: boolean;
  isMergeable: boolean;
  mergeableState: 'clean' | 'unstable' | 'blocked' | 'behind' | 'unknown';
  approvalCount: number;
  reviewers: PullRequestReviewer[];
  requiredStatusChecks: StatusCheckResult[];
  labels: string[];
  conversationResolved: boolean;
}

/**
 * PR author
 */
export interface PullRequestAuthor {
  userId: string;
  userEmail: string;
  userName: string;
}

/**
 * PR reviewer
 */
export interface PullRequestReviewer {
  userId: string;
  userEmail: string;
  userName: string;
  state: 'approved' | 'requested_changes' | 'commented' | 'pending';
  submittedAt?: number;
  isCodeOwner: boolean;
}

/**
 * Status check result
 */
export interface StatusCheckResult {
  name: string;
  status: 'success' | 'failure' | 'pending' | 'skipped';
  description?: string;
  url?: string;
  completedAt?: number;
}

/**
 * Auto-merge evaluation result
 */
export interface AutoMergeEvaluationResult {
  canAutoMerge: boolean;
  policyMatched: boolean;
  approvalsSatisfied: boolean;
  statusChecksPassed: boolean;
  conditionsMet: boolean;
  blockingReasons: string[];
  warnings: string[];
  recommendations: string[];
  matchedPolicy?: AutoMergePolicy;
  estimatedMergeTime?: number;
}

/**
 * Auto-merge request
 */
export interface AutoMergeRequest {
  id: string;
  prId: string;
  policyId: string;
  requestedBy: PolicyCreator;
  requestedAt: number;
  status: AutoMergeStatus;
  statusUpdatedAt: number;
  mergedAt?: number;
  mergeCommitId?: string;
  reason?: string;
  attempt?: number;
  lastAttemptedAt?: number;
  errorMessage?: string;
}

/**
 * Auto-merge status
 */
export type AutoMergeStatus = 'pending' | 'approved' | 'scheduled' | 'merging' | 'merged' | 'failed' | 'cancelled';

/**
 * Merge trigger event
 */
export interface MergeTriggerEvent {
  type: TriggerType;
  prId: string;
  policyId: string;
  triggeredBy: PolicyCreator;
  timestamp: number;
  data: Map<string, any>;
}

/**
 * Trigger type
 */
export type TriggerType = 'approval-received' | 'label-added' | 'status-check-passed' | 'review-resolved' | 'manual-request';

/**
 * Merge statistics
 */
export interface MergeStatistics {
  totalPolicies: number;
  activePolicies: number;
  totalAutoMergeRequests: number;
  successfulMerges: number;
  failedMerges: number;
  pendingMerges: number;
  averageMergeTime: number;
  successRate: number;
  blockingReasonsCount: Map<string, number>;
  mostUsedMergeStrategy: MergeStrategy;
}

/**
 * Audit entry for auto-merge operations
 */
export interface AutoMergeAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  ipAddress: string;
  userAgent: string;
  operation: AutoMergeOperation;
  policyId?: string;
  prId?: string;
  status: 'success' | 'failure';
  details: Map<string, unknown>;
}

/**
 * Auto-merge operation type
 */
export type AutoMergeOperation =
  | 'policy-created'
  | 'policy-updated'
  | 'policy-deleted'
  | 'policy-enabled'
  | 'policy-disabled'
  | 'merge-evaluated'
  | 'merge-approved'
  | 'merge-scheduled'
  | 'merge-attempted'
  | 'merge-successful'
  | 'merge-failed'
  | 'exception-added'
  | 'exception-removed';

/**
 * Service configuration
 */
export interface AutoMergeConfig {
  maxPolicies: number;
  maxAutoMergeRequests: number;
  maxMergeAttempts: number;
  defaultMergeDelay: number;
  maxAutoMergeDelay: number;
  enableNotifications: boolean;
  enableSlackNotifications: boolean;
  enableEmailNotifications: boolean;
  maxAuditLogSize: number;
  retentionDays: number;
}

/**
 * Service statistics
 */
export interface AutoMergeServiceStatistics {
  totalPolicies: number;
  activePolicies: number;
  totalAutoMergeRequests: number;
  successfulMerges: number;
  failedMerges: number;
  pendingMerges: number;
  averageMergeTime: number;
  successRate: number;
  mostUsedMergeStrategy: MergeStrategy;
  policyEffectiveness: Map<string, number>;
}

/**
 * Service interface
 */
export interface IAutoMergeService extends EventEmitter {
  createPolicy(
    policy: Partial<AutoMergePolicy>,
    createdBy: PolicyCreator,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; policyId?: string; error?: string };

  updatePolicy(
    policyId: string,
    updates: Partial<AutoMergePolicy>,
    updatedBy: PolicyCreator,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; policy?: AutoMergePolicy; error?: string };

  deletePolicy(
    policyId: string,
    deletedBy: PolicyCreator,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; error?: string };

  getPolicy(policyId: string): { success: boolean; policy?: AutoMergePolicy; error?: string };

  listPolicies(repoId: string): { success: boolean; policies: AutoMergePolicy[]; error?: string };

  evaluateMerge(
    pr: PullRequestMetadata,
    policyId: string
  ): AutoMergeEvaluationResult;

  requestAutoMerge(
    prId: string,
    policyId: string,
    requestedBy: PolicyCreator,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; requestId?: string; error?: string };

  approveAutoMerge(
    requestId: string,
    approvedBy: PolicyCreator,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; request?: AutoMergeRequest; error?: string };

  scheduleMerge(
    requestId: string,
    scheduledAt: number,
    scheduledBy: PolicyCreator,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; request?: AutoMergeRequest; error?: string };

  executeMerge(
    requestId: string,
    mergeBy: PolicyCreator,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; mergeCommitId?: string; error?: string };

  cancelAutoMerge(
    requestId: string,
    cancelledBy: PolicyCreator,
    reason: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; request?: AutoMergeRequest; error?: string };

  addException(
    policyId: string,
    exception: MergeException,
    addedBy: PolicyCreator,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; exceptionId?: string; error?: string };

  removeException(
    policyId: string,
    exceptionId: string,
    removedBy: PolicyCreator,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; error?: string };

  getStatistics(): AutoMergeServiceStatistics;

  updateConfig(
    config: Partial<AutoMergeConfig>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): void;

  shutdown(): void;
}
