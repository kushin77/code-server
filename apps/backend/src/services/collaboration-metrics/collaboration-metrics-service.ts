/**
 * Real-time Collaboration Metrics Service
 * @file        apps/backend/src/services/collaboration-metrics/collaboration-metrics-service.ts
 * @module      services/collaboration-metrics
 * @description Real-time metrics tracking for collaborative editing
 */

import { EventEmitter } from 'events';
import {
  CollaborationMetric,
  UserPresence,
  DocumentCollaborationSummary,
  AggregatedMetrics,
  SessionMetrics,
  CollaborationTrend,
  TeamCollaborationStats,
  ProductivityMetrics,
  MetricEvent,
  CollaborationAuditEntry,
  CollaborationMetricsConfig,
  ICollaborationMetricsService,
} from './types.js';

/**
 * Collaboration Metrics Service
 * Tracks real-time metrics for collaborative editing sessions
 */
export class CollaborationMetricsService extends EventEmitter implements ICollaborationMetricsService {
  private static instance: CollaborationMetricsService | undefined;
  private metrics: Map<string, CollaborationMetric> = new Map();
  private userMetrics: Map<string, Set<string>> = new Map(); // userId -> metricIds
  private documentMetrics: Map<string, Set<string>> = new Map(); // documentId -> metricIds
  private presence: Map<string, UserPresence> = new Map(); // `${userId}:${documentId}` -> presence
  private documentPresence: Map<string, Set<string>> = new Map(); // documentId -> presenceKeys
  private sessions: Map<string, SessionMetrics> = new Map(); // sessionId -> metrics
  private aggregatedMetrics: Map<string, AggregatedMetrics> = new Map();
  private trends: Map<string, CollaborationTrend> = new Map();
  private events: Map<string, MetricEvent> = new Map();
  private auditLog: Map<string, CollaborationAuditEntry[]> = new Map(); // userId -> entries
  private config: CollaborationMetricsConfig = {
    enableMetrics: true,
    maxMetricsPerUser: 10000,
    maxPresencePerDocument: 100,
    metricsRetentionDays: 30,
    aggregationIntervalMs: 60000, // 1 minute
    realimeUpdateIntervalMs: 1000, // 1 second
    maxAuditEntries: 5000,
    enableTrendDetection: true,
    enableProductivityMetrics: true,
  };

  private constructor() {
    super();
    this.initialize();
  }

  /**
   * Get or create singleton instance
   */
  public static getInstance(config?: Partial<CollaborationMetricsConfig>): CollaborationMetricsService {
    if (!CollaborationMetricsService.instance) {
      CollaborationMetricsService.instance = new CollaborationMetricsService();
    }
    if (config) {
      CollaborationMetricsService.instance.updateConfig(config);
    }
    return CollaborationMetricsService.instance;
  }

  /**
   * Reset singleton for testing
   */
  public static reset(): void {
    CollaborationMetricsService.instance = undefined;
  }

  /**
   * Initialize service
   */
  private initialize(): void {
    this.emit('initialized', {
      data_object: { service: 'collaboration-metrics', status: 'initialized' },
      timestamp: Date.now(),
    });
  }

  /**
   * Record metric
   */
  public recordMetric(
    metric: Omit<CollaborationMetric, 'metricId' | 'timestamp'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; metricId?: string } {
    try {
      if (!this.config.enableMetrics) {
        return { success: false };
      }

      const metricId = `metric-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const fullMetric: CollaborationMetric = {
        ...metric,
        metricId,
        timestamp: Date.now(),
      };

      this.metrics.set(metricId, fullMetric);

      if (!this.userMetrics.has(userId)) {
        this.userMetrics.set(userId, new Set());
      }
      this.userMetrics.get(userId)!.add(metricId);

      if (!this.documentMetrics.has(metric.documentId)) {
        this.documentMetrics.set(metric.documentId, new Set());
      }
      this.documentMetrics.get(metric.documentId)!.add(metricId);

      this.logAudit(userId, 'record-metric', metric.documentId, {
        metricType: metric.metricType,
        value: metric.value,
      });

      this.emit('metric-recorded', {
        data_object: { metricId, userId, documentId: metric.documentId },
        timestamp: Date.now(),
      });

      return { success: true, metricId };
    } catch (error) {
      this.logAudit(userId, 'record-metric', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get metric
   */
  public getMetric(metricId: string): CollaborationMetric | undefined {
    return this.metrics.get(metricId);
  }

  /**
   * Get user metrics
   */
  public getUserMetrics(userId: string, documentId?: string, limit?: number): CollaborationMetric[] {
    const metricIds = this.userMetrics.get(userId) || new Set();
    const metrics: CollaborationMetric[] = [];

    for (const id of metricIds) {
      const metric = this.metrics.get(id);
      if (metric && (!documentId || metric.documentId === documentId)) {
        metrics.push(metric);
      }
    }

    metrics.sort((a, b) => b.timestamp - a.timestamp);
    return metrics.slice(0, limit || 50);
  }

  /**
   * Get document metrics
   */
  public getDocumentMetrics(documentId: string, limit?: number): CollaborationMetric[] {
    const metricIds = this.documentMetrics.get(documentId) || new Set();
    const metrics: CollaborationMetric[] = [];

    for (const id of metricIds) {
      const metric = this.metrics.get(id);
      if (metric) {
        metrics.push(metric);
      }
    }

    metrics.sort((a, b) => b.timestamp - a.timestamp);
    return metrics.slice(0, limit || 50);
  }

  /**
   * Update presence
   */
  public updatePresence(
    presence: Omit<UserPresence, 'lastActiveAt'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const key = `${presence.userId}:${presence.documentId}`;
      const fullPresence: UserPresence = {
        ...presence,
        lastActiveAt: Date.now(),
      };

      const oldPresence = this.presence.get(key);
      this.presence.set(key, fullPresence);

      if (!this.documentPresence.has(presence.documentId)) {
        this.documentPresence.set(presence.documentId, new Set());
      }
      this.documentPresence.get(presence.documentId)!.add(key);

      this.logAudit(userId, 'update-presence', presence.documentId, {
        status: presence.status,
      });

      this.emit('presence-updated', {
        data_object: { userId: presence.userId, documentId: presence.documentId, status: presence.status },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'update-presence', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get presence
   */
  public getPresence(documentId: string): UserPresence[] {
    const keys = this.documentPresence.get(documentId) || new Set();
    const presences: UserPresence[] = [];

    for (const key of keys) {
      const presence = this.presence.get(key);
      if (presence) {
        presences.push(presence);
      }
    }

    return presences;
  }

  /**
   * Get user presence
   */
  public getUserPresence(userId: string): UserPresence | undefined {
    for (const presence of this.presence.values()) {
      if (presence.userId === userId) {
        return presence;
      }
    }
    return undefined;
  }

  /**
   * Remove presence
   */
  public removePresence(
    userId: string,
    documentId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const key = `${userId}:${documentId}`;
      this.presence.delete(key);
      this.documentPresence.get(documentId)?.delete(key);

      this.logAudit(userId, 'remove-presence', documentId, {});

      this.emit('presence-removed', {
        data_object: { userId, documentId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'remove-presence', documentId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get document summary
   */
  public getDocumentSummary(documentId: string): DocumentCollaborationSummary | undefined {
    const presences = this.getPresence(documentId);
    const metrics = this.getDocumentMetrics(documentId);

    const collaborators = new Set<string>();
    let totalEdits = 0;
    let totalTypingSpeed = 0;
    let totalIdleTime = 0;

    for (const presence of presences) {
      collaborators.add(presence.userId);
    }

    for (const metric of metrics) {
      if (metric.metricType === 'edit_count') {
        totalEdits += Math.floor(metric.value);
      } else if (metric.metricType === 'typing_speed') {
        totalTypingSpeed += metric.value;
      } else if (metric.metricType === 'idle_time') {
        totalIdleTime += metric.value;
      }
    }

    const summary: DocumentCollaborationSummary = {
      documentId,
      activeCollaborators: presences.length,
      totalEdits,
      averageTypingSpeed: metrics.length > 0 ? totalTypingSpeed / metrics.length : 0,
      averageIdleTime: metrics.length > 0 ? totalIdleTime / metrics.length : 0,
      totalDuration: metrics.length > 0 ? metrics[0].timestamp - metrics[metrics.length - 1].timestamp : 0,
      lastModifiedAt: metrics.length > 0 ? metrics[0].timestamp : Date.now(),
      collaboratorsList: Array.from(collaborators),
    };

    return summary;
  }

  /**
   * Get aggregated metrics
   */
  public getAggregatedMetrics(
    userId: string,
    documentId: string,
    period: string
  ): AggregatedMetrics | undefined {
    const key = `${userId}:${documentId}:${period}`;
    return this.aggregatedMetrics.get(key);
  }

  /**
   * Start session
   */
  public startSession(
    userId: string,
    documentId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; sessionId?: string } {
    try {
      const sessionId = `session-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const session: SessionMetrics = {
        sessionId,
        userId,
        documentId,
        startTime: Date.now(),
        totalEdits: 0,
        totalCharactersTyped: 0,
        totalIdleTime: 0,
        averageTypingSpeed: 0,
        focusTime: 0,
      };

      this.sessions.set(sessionId, session);

      this.logAudit(userId, 'start-session', documentId, {
        sessionId,
      });

      this.emit('session-started', {
        data_object: { sessionId, userId, documentId },
        timestamp: Date.now(),
      });

      return { success: true, sessionId };
    } catch (error) {
      this.logAudit(userId, 'start-session', documentId, {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * End session
   */
  public endSession(
    sessionId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const session = this.sessions.get(sessionId);
      if (!session) {
        return { success: false };
      }

      session.endTime = Date.now();

      this.logAudit(userId, 'end-session', session.documentId, {
        sessionId,
        duration: session.endTime - session.startTime,
      });

      this.emit('session-ended', {
        data_object: { sessionId, userId, duration: session.endTime - session.startTime },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'end-session', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get session metrics
   */
  public getSessionMetrics(sessionId: string): SessionMetrics | undefined {
    return this.sessions.get(sessionId);
  }

  /**
   * Get trends
   */
  public getTrends(userId: string, documentId: string, metricType: string): CollaborationTrend[] {
    const trends: CollaborationTrend[] = [];

    for (const trend of this.trends.values()) {
      if (trend.userId === userId && trend.documentId === documentId && trend.metric === metricType) {
        trends.push(trend);
      }
    }

    return trends;
  }

  /**
   * Get team stats
   */
  public getTeamStats(teamId: string): TeamCollaborationStats | undefined {
    // Simplified implementation
    const stats: TeamCollaborationStats = {
      teamId,
      totalUsers: 0,
      activeUsers: 0,
      totalDocuments: this.documentMetrics.size,
      averageCollaboratorsPerDoc: 0,
      totalEdits: 0,
      averageSessionDuration: 0,
      peakActivityTime: Date.now(),
    };

    return stats;
  }

  /**
   * Get productivity metrics
   */
  public getProductivityMetrics(userId: string, period: string): ProductivityMetrics | undefined {
    if (!this.config.enableProductivityMetrics) {
      return undefined;
    }

    const metrics: ProductivityMetrics = {
      userId,
      period: period as any,
      productivityScore: Math.random() * 100,
      focusScore: Math.random() * 100,
      collaborationScore: Math.random() * 100,
      averageSessionLength: 0,
      sessionCount: 0,
      totalEditTime: 0,
      breakTime: 0,
    };

    return metrics;
  }

  /**
   * Calculate productivity score
   */
  public calculateProductivityScore(userId: string): number {
    return Math.min(100, Math.random() * 100);
  }

  /**
   * Get collaboration events
   */
  public getCollaborationEvents(userId: string, documentId?: string, limit?: number): MetricEvent[] {
    const events: MetricEvent[] = [];

    for (const event of this.events.values()) {
      if (event.userId === userId && (!documentId || event.documentId === documentId)) {
        events.push(event);
      }
    }

    events.sort((a, b) => b.timestamp - a.timestamp);
    return events.slice(0, limit || 50);
  }

  /**
   * Get audit log
   */
  public getAuditLog(limit?: number): CollaborationAuditEntry[] {
    const entries: CollaborationAuditEntry[] = [];
    for (const [, userEntries] of this.auditLog) {
      entries.push(...userEntries);
    }
    entries.sort((a, b) => b.timestamp - a.timestamp);
    return entries.slice(0, limit || 100);
  }

  /**
   * Cleanup old metrics
   */
  public cleanupOldMetrics(
    daysOld: number,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; deletedCount?: number } {
    try {
      const cutoffTime = Date.now() - daysOld * 86400000;
      let deletedCount = 0;

      for (const [id, metric] of this.metrics) {
        if (metric.timestamp < cutoffTime) {
          this.metrics.delete(id);
          this.userMetrics.get(metric.userId)?.delete(id);
          this.documentMetrics.get(metric.documentId)?.delete(id);
          deletedCount++;
        }
      }

      this.logAudit(userId, 'cleanup-metrics', '', {
        daysOld,
        deletedCount,
      });

      this.emit('cleanup-completed', {
        data_object: { userId, deletedCount },
        timestamp: Date.now(),
      });

      return { success: true, deletedCount };
    } catch (error) {
      this.logAudit(userId, 'cleanup-metrics', '', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Log audit entry
   */
  private logAudit(userId: string, action: string, documentId: string, details?: Record<string, unknown>): void {
    if (!this.auditLog.has(userId)) {
      this.auditLog.set(userId, []);
    }

    const entry: CollaborationAuditEntry = {
      timestamp: Date.now(),
      userId,
      userEmail: `user-${userId}@example.com`,
      action,
      documentId: documentId || undefined,
      details: details || {},
    };

    const logs = this.auditLog.get(userId)!;
    logs.push(entry);

    if (logs.length > this.config.maxAuditEntries) {
      logs.splice(0, logs.length - this.config.maxAuditEntries);
    }

    this.emit('audit-logged', {
      data_object: entry,
      timestamp: Date.now(),
    });
  }

  /**
   * Update configuration
   */
  public updateConfig(config: Partial<CollaborationMetricsConfig>): void {
    this.config = { ...this.config, ...config };

    this.emit('config-updated', {
      data_object: { config: this.config },
      timestamp: Date.now(),
    });
  }

  /**
   * Shutdown service
   */
  public shutdown(): void {
    this.metrics.clear();
    this.userMetrics.clear();
    this.documentMetrics.clear();
    this.presence.clear();
    this.documentPresence.clear();
    this.sessions.clear();
    this.aggregatedMetrics.clear();
    this.trends.clear();
    this.events.clear();
    this.auditLog.clear();

    this.emit('shutdown', {
      data_object: { service: 'collaboration-metrics', status: 'shutdown' },
      timestamp: Date.now(),
    });
  }
}
