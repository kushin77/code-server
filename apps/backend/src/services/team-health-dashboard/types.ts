#!/usr/bin/env node
// @file        apps/backend/src/services/team-health-dashboard/types.ts
// @module      collaboration/team-health-dashboard
// @description Type definitions for TeamHealthDashboard
// @owner       collab-6.4
// @status      active

/**
 * Overall team health score with component breakdown
 */
export interface TeamHealthScore {
  teamId: string;
  timestamp: Date;
  overallScore: number; // 0-100
  collaborationScore: number; // 0-100
  communicationHealth: number; // 0-100
  activityHealth: number; // 0-100
  readinessHealth: number; // 0-100
  notificationHealth: number; // 0-100
  trendDirection: 'improving' | 'stable' | 'declining';
  trendVelocity: number; // change per day (-100 to +100)
}

/**
 * Dashboard widget configuration and state
 */
export interface DashboardWidget {
  id: string;
  name: string;
  displayName: string;
  position: number;
  size: 'small' | 'medium' | 'large';
  refreshIntervalSeconds: number;
  isVisible: boolean;
  lastUpdated: Date;
  data?: Record<string, unknown>;
}

/**
 * Aggregated recommendation with tracking
 */
export interface TrackedRecommendation {
  id: string;
  teamId: string;
  serviceOrigin: string; // collaboration-insight, communication-optimization, etc.
  type: string;
  title: string;
  description: string;
  rationale: string;
  estimatedBenefit: number; // 0-100
  estimatedTimeSavings: number; // hours/month
  confidence: number; // 0-1
  effort: 'low' | 'medium' | 'high';
  status: 'pending' | 'in-progress' | 'completed' | 'dismissed';
  createdAt: Date;
  statusChangedAt?: Date;
  completedAt?: Date;
  actualBenefit?: number; // measured after completion
  implementationSteps: string[];
  successMetrics: string[];
}

/**
 * Dashboard alert with context
 */
export interface DashboardAlert {
  id: string;
  teamId: string;
  type: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  title: string;
  message: string;
  triggeredAt: Date;
  resolvedAt?: Date;
  thresholdValue: number;
  actualValue: number;
  affectedUsers?: string[];
  suggestedActions: string[];
}

/**
 * Metric data point for trend analysis
 */
export interface TrendDataPoint {
  timestamp: Date;
  value: number;
  period: 'hourly' | 'daily' | 'weekly';
}

/**
 * Trend analysis with forecast
 */
export interface TrendAnalysis {
  metricName: string;
  dataPoints: TrendDataPoint[];
  currentValue: number;
  previousValue: number;
  trendDirection: 'up' | 'stable' | 'down';
  trendVelocity: number; // change rate per day
  forecastedValue: number; // 7 days forward
  forecastConfidence: number; // 0-1
}

/**
 * Team comparison result
 */
export interface TeamComparison {
  teamId: string;
  metric: string;
  teamValue: number;
  averageValue: number;
  minValue: number;
  maxValue: number;
  percentile: number; // 0-100
  ranking: number; // 1-based rank
  totalTeams: number;
}

/**
 * Dashboard configuration
 */
export interface DashboardConfig {
  teamId: string;
  refreshIntervalSeconds: number;
  widgets: DashboardWidget[];
  alertThresholds: {
    highNotificationOverload?: number;
    slowDecisionVelocity?: number;
    lowAsyncAdoption?: number;
    highMeetingHeaviness?: number;
    detectKnowledgeSilos?: boolean;
    burnoutRiskThreshold?: number;
  };
  enableRealTimeUpdates: boolean;
  enableAlerts: boolean;
  enableTrendAnalysis: boolean;
}

/**
 * Report generation parameters
 */
export interface ReportGenerationParams {
  teamId: string;
  format: 'pdf' | 'html' | 'json' | 'csv';
  period: 'week' | 'month' | 'quarter' | 'year';
  sections: ReportSection[];
  recipients?: string[];
  includeComparisons?: boolean;
  includeForecasts?: boolean;
}

/**
 * Report section types
 */
export type ReportSection =
  | 'executive-summary'
  | 'detailed-metrics'
  | 'recommendations'
  | 'benchmarking'
  | 'trend-analysis'
  | 'alerts-and-issues'
  | 'appendix';

/**
 * Dashboard overview snapshot
 */
export interface DashboardSnapshot {
  teamId: string;
  timestamp: Date;
  health: TeamHealthScore;
  topRecommendations: TrackedRecommendation[];
  activeAlerts: DashboardAlert[];
  recentActivity: ActivitySummary[];
  trends: TrendAnalysis[];
}

/**
 * Activity summary for dashboard
 */
export interface ActivitySummary {
  activityType: string;
  count: number;
  timeWindow: string; // "last-24h", "last-7d", etc.
  trend: 'up' | 'stable' | 'down';
}

/**
 * Widget refresh event
 */
export interface WidgetRefreshEvent {
  widgetId: string;
  timestamp: Date;
  data: Record<string, unknown>;
}

/**
 * Health update event
 */
export interface HealthUpdateEvent {
  teamId: string;
  timestamp: Date;
  previousScore: number;
  newScore: number;
  changes: {
    collaborationDelta: number;
    communicationDelta: number;
    activityDelta: number;
    readinessDelta: number;
    notificationDelta: number;
  };
}
