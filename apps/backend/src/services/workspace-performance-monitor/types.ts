/**
 * Workspace Performance Monitor Types
 * @file        apps/backend/src/services/workspace-performance-monitor/types.ts
 * @module      services/workspace-performance-monitor
 * @description Type definitions for workspace performance monitoring
 */

/**
 * Performance metric types
 */
export type MetricType = 'latency' | 'throughput' | 'cpu' | 'memory' | 'disk' | 'bandwidth' | 'error-rate' | 'availability';

/**
 * Performance threshold severity
 */
export type ThresholdSeverity = 'info' | 'warning' | 'critical';

/**
 * Performance data point
 */
export interface PerformanceDataPoint {
  timestamp: number;
  value: number;
  unit: string;
  source: string;
}

/**
 * Workspace performance metrics
 */
export interface WorkspaceMetrics {
  workspaceId: string;
  userId: string;
  timestamp: number;
  metrics: {
    latency: number; // ms
    throughput: number; // ops/sec
    cpuUsage: number; // percent
    memoryUsage: number; // MB
    diskUsage: number; // MB
    errorRate: number; // percent
    availability: number; // percent
  };
  aggregatedAt: number;
}

/**
 * Performance threshold definition
 */
export interface PerformanceThreshold {
  thresholdId: string;
  metricType: MetricType;
  workspaceId?: string;
  operator: 'gt' | 'lt' | 'gte' | 'lte' | 'eq' | 'ne';
  value: number;
  severity: ThresholdSeverity;
  enabled: boolean;
  notifyUsers: string[];
  createdAt: number;
  updatedAt: number;
}

/**
 * Performance alert
 */
export interface PerformanceAlert {
  alertId: string;
  thresholdId: string;
  workspaceId: string;
  metricType: MetricType;
  actualValue: number;
  thresholdValue: number;
  severity: ThresholdSeverity;
  message: string;
  triggeredAt: number;
  resolvedAt?: number;
  status: 'active' | 'resolved';
  notifiedUsers: string[];
}

/**
 * Performance trend analysis
 */
export interface PerformanceTrend {
  metricType: MetricType;
  workspaceId: string;
  direction: 'up' | 'down' | 'stable';
  percentageChange: number;
  dataPoints: PerformanceDataPoint[];
  trendStarted: number;
  trendEndsAt?: number;
  confidence: number; // 0-1
}

/**
 * Performance report
 */
export interface PerformanceReport {
  reportId: string;
  workspaceId: string;
  period: {
    startTime: number;
    endTime: number;
  };
  summary: {
    averageLatency: number;
    averageThroughput: number;
    peakCpuUsage: number;
    peakMemoryUsage: number;
    errorRate: number;
    availability: number;
  };
  trends: PerformanceTrend[];
  alerts: PerformanceAlert[];
  recommendations: string[];
  generatedAt: number;
}

/**
 * Performance anomaly
 */
export interface PerformanceAnomaly {
  anomalyId: string;
  workspaceId: string;
  metricType: MetricType;
  anomalyValue: number;
  expectedRange: { min: number; max: number };
  severity: ThresholdSeverity;
  explanation: string;
  detectedAt: number;
  investigatedAt?: number;
  resolved: boolean;
}

/**
 * Performance event
 */
export interface PerformanceEvent {
  eventId: string;
  workspaceId: string;
  eventType: 'deployment' | 'update' | 'migration' | 'scaling' | 'maintenance';
  description: string;
  impactedMetrics: MetricType[];
  startTime: number;
  endTime?: number;
  severity: ThresholdSeverity;
  status: 'ongoing' | 'completed';
}

/**
 * Performance baseline
 */
export interface PerformanceBaseline {
  baselineId: string;
  workspaceId: string;
  metricType: MetricType;
  normalRange: { min: number; max: number };
  createdAt: number;
  updatedAt: number;
  dataPoints: number; // count used in calculation
}

/**
 * Performance optimization suggestion
 */
export interface OptimizationSuggestion {
  suggestionId: string;
  workspaceId: string;
  category: 'caching' | 'indexing' | 'query-optimization' | 'resource-allocation' | 'batch-processing';
  title: string;
  description: string;
  expectedImprovement: number; // percent
  implementationEffort: 'low' | 'medium' | 'high';
  priority: number; // 1-5
  createdAt: number;
  appliedAt?: number;
}

/**
 * Performance statistics
 */
export interface PerformanceStatistics {
  totalMetricsRecorded: number;
  alertsTriggered: number;
  alertsResolved: number;
  anomaliesDetected: number;
  averageResponseTime: number;
  peakThroughput: number;
  worstErrorRate: number;
  averageAvailability: number;
}

/**
 * Performance audit entry
 */
export interface PerformanceAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  action: string;
  workspaceId: string;
  details: Record<string, unknown>;
}

/**
 * Workspace Performance Monitor configuration
 */
export interface WorkspacePerformanceConfig {
  enableMonitoring: boolean;
  enableAnomalyDetection: boolean;
  metricsRetentionDays: number;
  alertRetentionDays: number;
  anomalyDetectionSensitivity: number; // 0-1
  baselineCalculationInterval: number; // ms
  reportGenerationInterval: number; // ms
  maxAlerts: number;
  maxAnomalies: number;
  maxAuditEntries: number;
}

/**
 * Workspace Performance Monitor Service interface
 */
export interface IWorkspacePerformanceService {
  // Metrics recording
  recordMetrics(metrics: WorkspaceMetrics, ipAddress: string, userAgent: string): { success: boolean };
  getMetrics(workspaceId: string, timeRange?: { start: number; end: number }): WorkspaceMetrics[];

  // Threshold management
  createThreshold(threshold: Omit<PerformanceThreshold, 'thresholdId' | 'createdAt' | 'updatedAt'>, userId: string, ipAddress: string, userAgent: string): { success: boolean; thresholdId?: string };
  updateThreshold(thresholdId: string, updates: Partial<PerformanceThreshold>, userId: string, ipAddress: string, userAgent: string): { success: boolean };
  deleteThreshold(thresholdId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean };
  getThresholds(workspaceId?: string): PerformanceThreshold[];

  // Alert management
  getAlerts(workspaceId?: string, status?: 'active' | 'resolved'): PerformanceAlert[];
  resolveAlert(alertId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean };
  acknowledgeAlert(alertId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean };

  // Trend analysis
  analyzeTrends(workspaceId: string, metricType?: MetricType): PerformanceTrend[];
  detectAnomalies(workspaceId: string): PerformanceAnomaly[];

  // Report generation
  generateReport(workspaceId: string, period: { startTime: number; endTime: number }, userId: string, ipAddress: string, userAgent: string): { success: boolean; report?: PerformanceReport };
  getReports(workspaceId: string, limit?: number): PerformanceReport[];

  // Baselines
  updateBaseline(baseline: PerformanceBaseline, userId: string, ipAddress: string, userAgent: string): { success: boolean };
  getBaseline(workspaceId: string, metricType: MetricType): PerformanceBaseline | undefined;
  getBaselines(workspaceId: string): PerformanceBaseline[];

  // Optimization suggestions
  getOptimizationSuggestions(workspaceId: string): OptimizationSuggestion[];
  applySuggestion(suggestionId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean };

  // Events
  recordEvent(event: Omit<PerformanceEvent, 'eventId' | 'startTime'>, userId: string, ipAddress: string, userAgent: string): { success: boolean; eventId?: string };
  getEvents(workspaceId: string): PerformanceEvent[];

  // Statistics
  getStatistics(workspaceId?: string): PerformanceStatistics;
  getAuditLog(limit?: number): PerformanceAuditEntry[];

  // Configuration
  updateConfig(config: Partial<WorkspacePerformanceConfig>): void;
  getConfig(): WorkspacePerformanceConfig;

  // Lifecycle
  shutdown(): void;
}
