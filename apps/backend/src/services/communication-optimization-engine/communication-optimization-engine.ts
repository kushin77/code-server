#!/usr/bin/env node
// @file        apps/backend/src/services/communication-optimization-engine/communication-optimization-engine.ts
// @module      collaboration/communication-optimization-engine
// @description Service for context-aware communication orchestration
// @owner       collab-services
// @status      active

import { EventEmitter } from 'events';
import type {
  CommunicationContext,
  CommunicationPreference,
  CommunicationDecision,
  CommunicationDigest,
  DigestItem,
  OptimizationContext,
  OptimizationResult,
  CommunicationMetrics,
  ChannelScore,
  TimingRecommendation,
  ResponsePath,
  CommunicationOptimizationEngineConfig,
  CommunicationOptimizationStats,
  ReadinessSignal,
  CollaborationPattern,
} from './types';
import {
  CommunicationMode,
  CommunicationChannel,
  CommunicationUrgency,
  DecisionReason,
} from './types';

/**
 * CommunicationOptimizationEngine - Context-aware communication orchestration
 */
export class CommunicationOptimizationEngine extends EventEmitter {
  private config: CommunicationOptimizationEngineConfig;
  private preferences: Map<string, CommunicationPreference> = new Map();
  private decisions: Map<string, CommunicationDecision[]> = new Map();
  private digests: Map<string, CommunicationDigest[]> = new Map();
  private metrics: Map<string, CommunicationMetrics> = new Map();
  private readinessSignals: Map<string, ReadinessSignal> = new Map();
  private collaborationPatterns: Map<string, CollaborationPattern[]> = new Map();
  private stats: CommunicationOptimizationStats;

  constructor(config?: Partial<CommunicationOptimizationEngineConfig>) {
    super();
    this.config = {
      enableAsyncOptimization: true,
      enableDigestGeneration: true,
      enableEscalationLogic: true,
      enableContextCompression: true,
      enableCrossChannelDedup: true,
      digestBatchWindowMs: 3600000, // 1 hour
      decisionCacheTtlMs: 300000, // 5 minutes
      preferenceRefreshIntervalMs: 1800000, // 30 minutes
      confidenceThreshold: 0.6,
      asyncThresholdScore: 65,
      digestThresholdScore: 30,
      escalationDelayMs: 300000, // 5 minutes
      deferralCostThreshold: 50,
      ...config,
    };

    this.stats = {
      decisionsRecommended: 0,
      asyncRecommendations: 0,
      syncRecommendations: 0,
      deferredRecommendations: 0,
      escalatedRecommendations: 0,
      digestsGenerated: 0,
      averageDecisionTimeMs: 0,
      teamsMonitored: 0,
      usersMonitored: 0,
      preferencesLoaded: 0,
      lastUpdateTime: Date.now(),
      totalRecommendationsDelivered: 0,
    };
  }

  /**
   * Initialize service
   */
  async initialize(): Promise<void> {
    this.emit('initialized', { timestamp: Date.now() });
  }

  /**
   * Recommend optimal communication mode for a context
   */
  async recommendCommunication(context: CommunicationContext): Promise<CommunicationDecision> {
    const startTime = performance.now();

    // Check readiness signals
    const readinessCheck = await this.checkReadiness(context.targetUserIds);
    if (!readinessCheck.allAvailable && context.urgency !== CommunicationUrgency.CRITICAL) {
      const deferralReasons: DecisionReason[] = [];
      if (readinessCheck.focusTimeActive) deferralReasons.push(DecisionReason.FOCUS_TIME);
      if (readinessCheck.dndActive) deferralReasons.push(DecisionReason.DND_ACTIVE);
      if (readinessCheck.unavailable) deferralReasons.push(DecisionReason.USER_UNAVAILABLE);

      const deferUntilTime = this.calculateDeferralTime(context, readinessCheck);

      const decision: CommunicationDecision = {
        decisionId: `dec-${Date.now()}-defer`,
        sourceUserId: context.sourceUserId,
        targetUserIds: context.targetUserIds,
        teamId: context.teamId,
        recommendedMode: CommunicationMode.DEFERRED,
        recommendedChannel: CommunicationChannel.IN_APP,
        recommendedTiming: deferUntilTime,
        shouldDefer: true,
        deferReason: deferralReasons[0],
        deferUntil: deferUntilTime,
        rationale: `Deferring communication: ${deferralReasons.join(', ')}`,
        reasons: deferralReasons,
        confidence: 0.85,
        impactIfDeferred: this.evaluateImpact(context),
        estimatedResponseTime: this.estimateResponseTime(context, CommunicationMode.DEFERRED),
        createdAt: Date.now(),
        expiresAt: Date.now() + this.config.decisionCacheTtlMs,
      };

      this.stats.deferredRecommendations++;
      this.stats.decisionsRecommended++;
      this.emit('communicationDeferred', decision);

      return decision;
    }

    // Score communication channels
    const channelScores = await this.scoreChannels(context);
    const bestChannel = channelScores.reduce((a, b) => (a.score > b.score ? a : b));

    // Determine communication mode
    const modeScore = this.calculateModeScore(context, channelScores);
    const mode = modeScore > this.config.asyncThresholdScore
      ? CommunicationMode.ASYNC_COMMENT
      : CommunicationMode.SYNC_MENTION;

    // Get timing recommendation
    const timing = await this.recommendTiming(context);

    // Detect escalation need
    const shouldEscalate =
      this.config.enableEscalationLogic &&
      context.urgency === CommunicationUrgency.CRITICAL &&
      !readinessCheck.allAvailable;

    const escalationPath = shouldEscalate ? this.getEscalationPath(context) : undefined;

    const decision: CommunicationDecision = {
      decisionId: `dec-${Date.now()}`,
      sourceUserId: context.sourceUserId,
      targetUserIds: context.targetUserIds,
      teamId: context.teamId,
      recommendedMode: shouldEscalate ? CommunicationMode.CALL_MEETING : mode,
      recommendedChannel: bestChannel.channel,
      recommendedTiming: timing.recommendedTime,
      shouldDefer: false,
      rationale: bestChannel.rationale,
      reasons: [
        mode === CommunicationMode.ASYNC_COMMENT
          ? DecisionReason.ASYNC_PREFERRED
          : DecisionReason.SYNC_JUSTIFIED,
      ],
      confidence: (bestChannel.confidence + timing.confidence) / 2,
      escalationPath: escalationPath,
      estimatedResponseTime: this.estimateResponseTime(context, mode),
      createdAt: Date.now(),
      expiresAt: Date.now() + this.config.decisionCacheTtlMs,
    };

    // Track statistics
    if (mode === CommunicationMode.ASYNC_COMMENT) {
      this.stats.asyncRecommendations++;
    } else {
      this.stats.syncRecommendations++;
    }
    if (shouldEscalate) {
      this.stats.escalatedRecommendations++;
    }

    this.stats.decisionsRecommended++;
    this.stats.averageDecisionTimeMs = (performance.now() - startTime + this.stats.averageDecisionTimeMs) / 2;
    this.emit('communicationRecommended', decision);

    return decision;
  }

  /**
   * Generate digest for batch communications
   */
  async generateDigest(
    teamId: string,
    userId: string,
    periodStart: number,
    periodEnd: number,
  ): Promise<CommunicationDigest> {
    const decisions = this.decisions.get(teamId) || [];

    // Filter decisions for digest candidates (low urgency, batch eligible)
    const digestItems: DigestItem[] = decisions
      .filter(
        (d) =>
          d.createdAt >= periodStart &&
          d.createdAt <= periodEnd &&
          d.targetUserIds.includes(userId),
      )
      .map((d, idx) => ({
        itemId: `item-${d.decisionId}`,
        sourceUserId: d.sourceUserId,
        title: `Communication from ${d.sourceUserId}`,
        summary: d.rationale.substring(0, 100),
        urgency: CommunicationUrgency.LOW,
        threadId: undefined,
        actionRequired: false,
        timestamp: d.createdAt,
      }));

    const digest: CommunicationDigest = {
      digestId: `dig-${Date.now()}`,
      teamId,
      userId,
      periodStart,
      periodEnd,
      itemCount: digestItems.length,
      items: digestItems,
      generatedAt: Date.now(),
    };

    this.stats.digestsGenerated++;
    this.emit('digestGenerated', digest);

    return digest;
  }

  /**
   * Query optimization insights
   */
  async queryOptimization(context: OptimizationContext): Promise<OptimizationResult> {
    const startTime = performance.now();

    const result: OptimizationResult = {
      teamId: context.teamId,
      queryTime: 0,
      generatedAt: Date.now(),
    };

    if (context.includeMetrics) {
      result.metrics = this.metrics.get(context.teamId) || {
        teamId: context.teamId,
        avgResponseTime: 0,
        asyncPreference: 0.5,
        syncPreference: 0.5,
        digestUtilization: 0.3,
        interruptionRate: 5,
        deferralRate: 0.1,
        escalationRate: 0.05,
        averageThreadDepth: 3,
        criticalItemsAverage: 2,
        updatedAt: Date.now(),
      };
    }

    if (context.includeRecommendations) {
      result.recommendations = (this.decisions.get(context.teamId) || []).slice(0, 10);
    }

    if (context.includeDigests) {
      result.digests = (this.digests.get(context.teamId) || []).slice(0, 5);
    }

    result.queryTime = performance.now() - startTime;
    this.stats.totalRecommendationsDelivered++;
    this.emit('optimizationQueried', result);

    return result;
  }

  /**
   * Load user communication preferences
   */
  async loadPreferences(userId: string): Promise<CommunicationPreference> {
    const preference: CommunicationPreference = {
      userId,
      preferredChannels: [
        CommunicationChannel.IN_APP,
        CommunicationChannel.EMAIL,
        CommunicationChannel.SLACK,
      ],
      quietHours: {
        startTime: '18:00',
        endTime: '09:00',
        timezone: 'UTC',
      },
      focusTimePolicy: {
        enabled: true,
        dayOfWeek: [1, 2, 3, 4, 5], // Mon-Fri
        timeSlots: [{ start: '09:00', end: '12:00' }],
      },
    };

    this.preferences.set(userId, preference);
    this.stats.preferencesLoaded++;
    this.stats.usersMonitored++;
    return preference;
  }

  /**
   * Update readiness signal for a user
   */
  async updateReadinessSignal(signal: ReadinessSignal): Promise<void> {
    this.readinessSignals.set(signal.userId, signal);
  }

  /**
   * Record collaboration pattern
   */
  async recordCollaborationPattern(pattern: CollaborationPattern): Promise<void> {
    const patterns = this.collaborationPatterns.get(pattern.teamId) || [];
    patterns.push(pattern);
    this.collaborationPatterns.set(pattern.teamId, patterns);
  }

  /**
   * Get service statistics
   */
  getStats(): CommunicationOptimizationStats {
    return { ...this.stats };
  }

  /**
   * Check readiness of target users
   */
  private async checkReadiness(userIds: string[]): Promise<{
    allAvailable: boolean;
    unavailable: boolean;
    focusTimeActive: boolean;
    dndActive: boolean;
  }> {
    let allAvailable = true;
    let unavailable = false;
    let focusTimeActive = false;
    let dndActive = false;

    for (const userId of userIds) {
      const signal = this.readinessSignals.get(userId);
      if (!signal || !signal.available) {
        allAvailable = false;
        unavailable = true;
      }
      // focusTime can block even if technically available
      if (signal?.focusTime) {
        focusTimeActive = true;
        allAvailable = false; // Focus time blocks availability
      }
      if (signal?.dndActive) {
        dndActive = true;
        allAvailable = false; // DND blocks availability
      }
    }

    return { allAvailable, unavailable, focusTimeActive, dndActive };
  }

  /**
   * Calculate deferral time based on readiness
   */
  private calculateDeferralTime(
    context: CommunicationContext,
    readiness: { allAvailable: boolean; focusTimeActive: boolean; dndActive: boolean },
  ): number {
    let deferralMs = this.config.escalationDelayMs;

    if (readiness.focusTimeActive) {
      deferralMs = Math.min(deferralMs, 120 * 60 * 1000); // 2 hours
    }
    if (readiness.dndActive) {
      deferralMs = Math.min(deferralMs, 300 * 60 * 1000); // 5 hours
    }

    return Date.now() + deferralMs;
  }

  /**
   * Score communication channels
   */
  private async scoreChannels(context: CommunicationContext): Promise<ChannelScore[]> {
    const scores: ChannelScore[] = [];

    // In-app has baseline score
    scores.push({
      channel: CommunicationChannel.IN_APP,
      score: 85,
      rationale: 'In-app is default channel for team communications',
      confidence: 0.9,
    });

    // Email for async
    scores.push({
      channel: CommunicationChannel.EMAIL,
      score: context.urgency === CommunicationUrgency.LOW ? 80 : 60,
      rationale:
        context.urgency === CommunicationUrgency.LOW
          ? 'Email good for low-urgency async'
          : 'Email less ideal for urgent items',
      confidence: 0.8,
    });

    // Slack for sync
    scores.push({
      channel: CommunicationChannel.SLACK,
      score: context.urgency === CommunicationUrgency.CRITICAL ? 90 : 70,
      rationale:
        context.urgency === CommunicationUrgency.CRITICAL
          ? 'Slack good for urgent escalation'
          : 'Slack okay for normal priority',
      confidence: 0.85,
    });

    // Push for critical
    scores.push({
      channel: CommunicationChannel.PUSH,
      score: context.urgency === CommunicationUrgency.CRITICAL ? 95 : 30,
      rationale:
        context.urgency === CommunicationUrgency.CRITICAL
          ? 'Push notification for critical items'
          : 'Push reserved for critical communications',
      confidence: context.urgency === CommunicationUrgency.CRITICAL ? 0.95 : 0.5,
    });

    // Digest for low urgency batching
    scores.push({
      channel: CommunicationChannel.DIGEST,
      score: context.urgency === CommunicationUrgency.LOW ? 70 : 20,
      rationale: context.urgency === CommunicationUrgency.LOW ? 'Digest good for low-urgency items' : 'Digest not suitable for urgent items',
      confidence: 0.8,
    });

    return scores;
  }

  /**
   * Calculate mode score (async vs sync)
   */
  private calculateModeScore(context: CommunicationContext, _channelScores: ChannelScore[]): number {
    let score = 50; // Neutral starting point

    // Async favoring factors
    if (context.urgency === CommunicationUrgency.LOW) score += 20;
    if (context.communicationType === 'update') score += 15;
    if (context.threadDepth && context.threadDepth > 3) score += 10;

    // Sync favoring factors
    if (context.urgency === CommunicationUrgency.CRITICAL) score -= 25;
    if (context.blockerPresent) score -= 20;
    if (context.communicationType === 'decision') score -= 15;

    return Math.max(0, Math.min(100, score));
  }

  /**
   * Recommend optimal timing for communication
   */
  private async recommendTiming(_context: CommunicationContext): Promise<TimingRecommendation> {
    return {
      recommendedTime: Date.now() + 60000, // 1 minute from now
      confidence: 0.75,
      factors: ['User availability', 'Focus time windows', 'Timezone alignment'],
    };
  }

  /**
   * Evaluate impact if communication is deferred
   */
  private evaluateImpact(context: CommunicationContext): string {
    if (context.blockerPresent) {
      return 'Blocker present - deferral may cause delays';
    }
    if (context.unsolvedDecisionCount && context.unsolvedDecisionCount > 0) {
      return `${context.unsolvedDecisionCount} open decision(s) pending`;
    }
    return 'Low impact if deferred';
  }

  /**
   * Get escalation path for critical items
   */
  private getEscalationPath(context: CommunicationContext): string[] {
    const path: string[] = [];
    path.push('initial_notify'); // First notify via preferred channel
    path.push('slack_escalate'); // Then escalate to Slack if no response
    path.push('call_invite'); // Finally suggest call if critical

    return path;
  }

  /**
   * Estimate response time based on communication mode
   */
  private estimateResponseTime(context: CommunicationContext, mode: CommunicationMode): number {
    let estimateMs = 3600000; // 1 hour default

    switch (mode) {
      case CommunicationMode.SYNC_MENTION:
      case CommunicationMode.CALL_MEETING:
        estimateMs = 300000; // 5 minutes
        break;
      case CommunicationMode.ASYNC_COMMENT:
        estimateMs = 1800000; // 30 minutes
        break;
      case CommunicationMode.SUMMARY_DIGEST:
        estimateMs = 3600000; // 1 hour
        break;
      case CommunicationMode.DEFERRED:
        estimateMs = 7200000; // 2 hours
        break;
    }

    // Adjust for urgency
    if (context.urgency === CommunicationUrgency.CRITICAL) {
      estimateMs *= 0.5;
    }
    if (context.urgency === CommunicationUrgency.LOW) {
      estimateMs *= 2;
    }

    return estimateMs;
  }

  /**
   * Shutdown service
   */
  async shutdown(): Promise<void> {
    this.removeAllListeners();
    this.preferences.clear();
    this.decisions.clear();
    this.digests.clear();
    this.metrics.clear();
    this.readinessSignals.clear();
    this.collaborationPatterns.clear();
    this.emit('shutdown', { timestamp: Date.now() });
  }
}

/**
 * Factory function to create service instance
 */
export function createCommunicationOptimizationEngine(
  config?: Partial<CommunicationOptimizationEngineConfig>,
): CommunicationOptimizationEngine {
  return new CommunicationOptimizationEngine(config);
}

export * from './types';
