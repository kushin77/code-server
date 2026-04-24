/**
 * Real-time Collaboration Metrics Types
 * @file        apps/backend/src/services/collaboration-metrics/types.ts
 * @module      services/collaboration-metrics
 * @description Type definitions for real-time collaboration metrics
 */

/**
 * Collaboration metric types
 */
export type MetricType = 'cursor_position' | 'selection' | 'edit_count' | 'document_change' | 'typing_speed' | 'idle_time' | 'active_duration';

/**
 * Presence status
 */
export type PresenceStatus = 'active' | 'idle' | 'offline' | 'away';

/**
 * Metric time aggregation
 */
export type AggregationPeriod = 'realtime' | '1m' | '5m' | '15m' | '1h' | '1d';

/**
 * User collaboration metric
 */
export interface CollaborationMetric {
  metricId: string;
  userId: string;
  documentId: string;
  metricType: MetricType;
  value: number;
  timestamp: number;
  duration?: number;
  metadata: Record<string, unknown>;
}

/**
 * User presence information
 */
export interface UserPresence {
  userId: string;
  userEmail: string;
  documentId: string;
  status: PresenceStatus;
  lastActiveAt: number;
  cursorPosition?: { line: number; column: number };
  selection?: { start: number; end: number };
  color?: string;
}

/**
 * Document collaboration summary
 */
export interface DocumentCollaborationSummary {
  documentId: string;
  activeCollaborators: number;
  totalEdits: number;
  averageTypingSpeed: number;
  averageIdleTime: number;
  totalDuration: number;
  lastModifiedAt: number;
  collaboratorsList: string[];
}

/**
 * Aggregated metrics
 */
export interface AggregatedMetrics {
  userId: string;
  documentId: string;
  period: AggregationPeriod;
  startTime: number;
  endTime: number;
  editCount: number;
  averageTypingSpeed: number;
  totalIdleTime: number;
  activeDuration: number;
  selectionCount: number;
  changeCount: number;
}

/**
 * User session metrics
 */
export interface SessionMetrics {
  sessionId: string;
  userId: string;
  documentId: string;
  startTime: number;
  endTime?: number;
  totalEdits: number;
  totalCharactersTyped: number;
  totalIdleTime: number;
  averageTypingSpeed: number;
  focusTime: number;
}

/**
 * Collaboration trend data
 */
export interface CollaborationTrend {
  trendId: string;
  userId: string;
  documentId: string;
  metric: MetricType;
  period: AggregationPeriod;
  trend: 'up' | 'down' | 'stable';
  percentChange: number;
  dataPoints: Array<{ timestamp: number; value: number }>;
}

/**
 * Team collaboration statistics
 */
export interface TeamCollaborationStats {
  teamId: string;
  totalUsers: number;
  activeUsers: number;
  totalDocuments: number;
  averageCollaboratorsPerDoc: number;
  totalEdits: number;
  averageSessionDuration: number;
  peakActivityTime: number;
}

/**
 * User collaboration productivity metrics
 */
export interface ProductivityMetrics {
  userId: string;
  period: AggregationPeriod;
  productivityScore: number;
  focusScore: number;
  collaborationScore: number;
  averageSessionLength: number;
  sessionCount: number;
  totalEditTime: number;
  breakTime: number;
}

/**
 * Real-time metric event
 */
export interface MetricEvent {
  eventId: string;
  metricId: string;
  userId: string;
  documentId: string;
  eventType: 'metric_recorded' | 'presence_updated' | 'session_started' | 'session_ended';
  timestamp: number;
  data: Record<string, unknown>;
}

/**
 * Collaboration audit entry
 */
export interface CollaborationAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  action: string;
  documentId?: string;
  details: Record<string, unknown>;
}

/**
 * Service configuration
 */
export interface CollaborationMetricsConfig {
  enableMetrics: boolean;
  maxMetricsPerUser: number;
  maxPresencePerDocument: number;
  metricsRetentionDays: number;
  aggregationIntervalMs: number;
  realimeUpdateIntervalMs: number;
  maxAuditEntries: number;
  enableTrendDetection: boolean;
  enableProductivityMetrics: boolean;
}

/**
 * Collaboration metrics service interface
 */
export interface ICollaborationMetricsService {
  recordMetric(
    metric: Omit<CollaborationMetric, 'metricId' | 'timestamp'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; metricId?: string };

  getMetric(metricId: string): CollaborationMetric | undefined;

  getUserMetrics(userId: string, documentId?: string, limit?: number): CollaborationMetric[];

  getDocumentMetrics(documentId: string, limit?: number): CollaborationMetric[];

  updatePresence(
    presence: Omit<UserPresence, 'lastActiveAt'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  getPresence(documentId: string): UserPresence[];

  getUserPresence(userId: string): UserPresence | undefined;

  removePresence(
    userId: string,
    documentId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  getDocumentSummary(documentId: string): DocumentCollaborationSummary | undefined;

  getAggregatedMetrics(
    userId: string,
    documentId: string,
    period: AggregationPeriod
  ): AggregatedMetrics | undefined;

  startSession(
    userId: string,
    documentId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; sessionId?: string };

  endSession(
    sessionId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean };

  getSessionMetrics(sessionId: string): SessionMetrics | undefined;

  getTrends(
    userId: string,
    documentId: string,
    metricType: MetricType
  ): CollaborationTrend[];

  getTeamStats(teamId: string): TeamCollaborationStats | undefined;

  getProductivityMetrics(
    userId: string,
    period: AggregationPeriod
  ): ProductivityMetrics | undefined;

  calculateProductivityScore(userId: string): number;

  getCollaborationEvents(userId: string, documentId?: string, limit?: number): MetricEvent[];

  getAuditLog(limit?: number): CollaborationAuditEntry[];

  cleanupOldMetrics(
    daysOld: number,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; deletedCount?: number };

  updateConfig(config: Partial<CollaborationMetricsConfig>): void;

  shutdown(): void;
}
