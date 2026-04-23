#!/usr/bin/env node
// @file        apps/backend/src/services/communication-optimization-engine/types.ts
// @module      collaboration/communication-optimization-engine
// @description Type definitions for communication optimization service
// @owner       collab-services
// @status      active

/**
 * Communication mode enumeration
 */
export enum CommunicationMode {
  ASYNC_COMMENT = 'async_comment',
  SYNC_DM = 'sync_dm',
  SYNC_MENTION = 'sync_mention',
  CALL_MEETING = 'call_meeting',
  SUMMARY_DIGEST = 'summary_digest',
  DEFERRED = 'deferred',
}

/**
 * Communication channel enumeration
 */
export enum CommunicationChannel {
  IN_APP = 'in_app',
  EMAIL = 'email',
  SLACK = 'slack',
  PUSH = 'push',
  DIGEST = 'digest',
}

/**
 * Communication urgency enumeration
 */
export enum CommunicationUrgency {
  CRITICAL = 'critical',
  HIGH = 'high',
  NORMAL = 'normal',
  LOW = 'low',
}

/**
 * Recommendation reason codes
 */
export enum DecisionReason {
  USER_UNAVAILABLE = 'user_unavailable',
  FOCUS_TIME = 'focus_time',
  DND_ACTIVE = 'dnd_active',
  TIMEZONE_MISMATCH = 'timezone_mismatch',
  BATCH_ELIGIBLE = 'batch_eligible',
  ESCALATION_REQUIRED = 'escalation_required',
  ASYNC_PREFERRED = 'async_preferred',
  SYNC_JUSTIFIED = 'sync_justified',
  ALREADY_NOTIFIED = 'already_notified',
  DISCUSSION_ONGOING = 'discussion_ongoing',
  MEETING_SCHEDULED = 'meeting_scheduled',
  OPTIMAL_TIMING = 'optimal_timing',
}

/**
 * Communication context
 */
export interface CommunicationContext {
  sourceUserId: string;
  targetUserIds: string[];
  teamId: string;
  communicationType: 'message' | 'mention' | 'decision' | 'blocker' | 'update';
  urgency: CommunicationUrgency;
  conversationThreadId?: string;
  threadDepth?: number;
  unsolvedDecisionCount?: number;
  blockerPresent?: boolean;
  estimatedResolutionTimeMs?: number;
  relatedIssueIds?: string[];
  contextMetadata?: Record<string, unknown>;
  timestamp: number;
}

/**
 * Communication preference configuration
 */
export interface CommunicationPreference {
  userId: string;
  preferredChannels: CommunicationChannel[];
  quietHours?: {
    startTime: string; // HH:mm format
    endTime: string;
    timezone: string;
  };
  focusTimePolicy?: {
    enabled: boolean;
    dayOfWeek?: number[]; // 0-6, Sunday-Saturday
    timeSlots?: Array<{ start: string; end: string }>;
  };
  escalationPolicy?: {
    initialDelay: number;
    escalationSteps: Array<{
      delayMs: number;
      channel: CommunicationChannel;
      urgencyThreshold: CommunicationUrgency;
    }>;
  };
  dndActive?: boolean;
  timezone?: string;
}

/**
 * Communication decision recommendation
 */
export interface CommunicationDecision {
  decisionId: string;
  sourceUserId: string;
  targetUserIds: string[];
  teamId: string;
  recommendedMode: CommunicationMode;
  recommendedChannel: CommunicationChannel;
  recommendedTiming: number; // Timestamp
  shouldDefer: boolean;
  deferReason?: DecisionReason;
  deferUntil?: number; // Timestamp
  rationale: string;
  reasons: DecisionReason[];
  confidence: number; // 0-1
  impactIfDeferred?: string;
  alternativeRecipient?: string;
  escalationPath?: string[];
  estimatedResponseTime?: number; // ms
  createdAt: number;
  expiresAt: number;
}

/**
 * Communication digest summary
 */
export interface CommunicationDigest {
  digestId: string;
  teamId: string;
  userId: string;
  periodStart: number;
  periodEnd: number;
  itemCount: number;
  items: DigestItem[];
  generatedAt: number;
  deliveredAt?: number;
  readAt?: number;
}

/**
 * Single digest item
 */
export interface DigestItem {
  itemId: string;
  sourceUserId: string;
  title: string;
  summary: string;
  urgency: CommunicationUrgency;
  threadId?: string;
  actionRequired: boolean;
  actionUrl?: string;
  timestamp: number;
}

/**
 * Communication optimization context
 */
export interface OptimizationContext {
  teamId: string;
  period?: {
    startTime: number;
    endTime: number;
    label: string;
  };
  includeMetrics?: boolean;
  includeRecommendations?: boolean;
  includeDigests?: boolean;
  filterByChannel?: CommunicationChannel[];
  filterByUrgency?: CommunicationUrgency[];
}

/**
 * Optimization result
 */
export interface OptimizationResult {
  teamId: string;
  queryTime: number;
  generatedAt: number;
  metrics?: CommunicationMetrics;
  recommendations?: CommunicationDecision[];
  digests?: CommunicationDigest[];
}

/**
 * Communication metrics
 */
export interface CommunicationMetrics {
  teamId: string;
  avgResponseTime: number;
  asyncPreference: number; // 0-1
  syncPreference: number; // 0-1
  digestUtilization: number; // 0-1
  interruptionRate: number; // messages per person per day
  deferralRate: number; // percentage of deferred messages
  escalationRate: number; // percentage of escalated messages
  averageThreadDepth: number;
  criticalItemsAverage: number;
  updatedAt: number;
}

/**
 * Channel scoring result
 */
export interface ChannelScore {
  channel: CommunicationChannel;
  score: number; // 0-100
  rationale: string;
  confidence: number; // 0-1
}

/**
 * Timing recommendation
 */
export interface TimingRecommendation {
  recommendedTime: number; // Timestamp
  confidence: number; // 0-1
  factors: string[];
  alternative?: number; // Fallback time
}

/**
 * Response path analysis
 */
export interface ResponsePath {
  pathId: string;
  steps: ResponseStep[];
  estimatedResolutionTime: number;
  shortestAlternative?: string;
  shortestAlternativeTime?: number;
}

/**
 * Single response step
 */
export interface ResponseStep {
  actor: string;
  action: string;
  expectedTimeMs: number;
  dependencies?: string[];
}

/**
 * Service configuration
 */
export interface CommunicationOptimizationEngineConfig {
  enableAsyncOptimization: boolean;
  enableDigestGeneration: boolean;
  enableEscalationLogic: boolean;
  enableContextCompression: boolean;
  enableCrossChannelDedup: boolean;
  digestBatchWindowMs: number;
  decisionCacheTtlMs: number;
  preferenceRefreshIntervalMs: number;
  confidenceThreshold: number;
  asyncThresholdScore: number;
  digestThresholdScore: number;
  escalationDelayMs: number;
  deferralCostThreshold: number;
}

/**
 * Service statistics
 */
export interface CommunicationOptimizationStats {
  decisionsRecommended: number;
  asyncRecommendations: number;
  syncRecommendations: number;
  deferredRecommendations: number;
  escalatedRecommendations: number;
  digestsGenerated: number;
  averageDecisionTimeMs: number;
  teamsMonitored: number;
  usersMonitored: number;
  preferencesLoaded: number;
  lastUpdateTime: number;
  totalRecommendationsDelivered: number;
}

/**
 * Readiness signal interface
 */
export interface ReadinessSignal {
  userId: string;
  available: boolean;
  focusTime: boolean;
  dndActive: boolean;
  currentActivity?: string;
  estimatedAvailableIn?: number; // ms
  capacity: number; // 0-1
  timezone?: string;
}

/**
 * Collaboration pattern for context
 */
export interface CollaborationPattern {
  teamId: string;
  patternType: 'clustering' | 'silos' | 'bottleneck';
  members: string[];
  strength: number;
  riskLevel: 'low' | 'medium' | 'high';
}
