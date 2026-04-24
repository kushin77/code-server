/**
 * Workspace Performance Monitor Service
 * @file        apps/backend/src/services/workspace-performance-monitor/workspace-performance-monitor-service.ts
 * @module      services/workspace-performance-monitor
 * @description Real-time workspace performance monitoring and alerting
 */

import { EventEmitter } from 'events';
import {
  WorkspaceMetrics,
  PerformanceThreshold,
  PerformanceAlert,
  PerformanceTrend,
  PerformanceReport,
  PerformanceAnomaly,
  PerformanceEvent,
  PerformanceBaseline,
  OptimizationSuggestion,
  PerformanceStatistics,
  PerformanceAuditEntry,
  WorkspacePerformanceConfig,
  IWorkspacePerformanceService,
  MetricType,
} from './types.js';

/**
 * Workspace Performance Monitor Service
 * Monitors and analyzes workspace performance metrics with anomaly detection
 */
export class WorkspacePerformanceMonitor extends EventEmitter implements IWorkspacePerformanceService {
  private static instance: WorkspacePerformanceMonitor | undefined;
  private metrics: Map<string, WorkspaceMetrics[]> = new Map(); // workspaceId -> metrics
  private thresholds: Map<string, PerformanceThreshold> = new Map();
  private alerts: Map<string, PerformanceAlert> = new Map();
  private trends: Map<string, PerformanceTrend[]> = new Map();
  private anomalies: Map<string, PerformanceAnomaly[]> = new Map();
  private baselines: Map<string, PerformanceBaseline[]> = new Map();
  private suggestions: Map<string, OptimizationSuggestion[]> = new Map();
  private events: Map<string, PerformanceEvent[]> = new Map();
  private reports: Map<string, PerformanceReport[]> = new Map();
  private auditLog: Map<string, PerformanceAuditEntry[]> = new Map(); // userId -> entries
  private stats: PerformanceStatistics = {
    totalMetricsRecorded: 0,
    alertsTriggered: 0,
    alertsResolved: 0,
    anomaliesDetected: 0,
    averageResponseTime: 0,
    peakThroughput: 0,
    worstErrorRate: 0,
    averageAvailability: 0,
  };
  private config: WorkspacePerformanceConfig = {
    enableMonitoring: true,
    enableAnomalyDetection: true,
    metricsRetentionDays: 30,
    alertRetentionDays: 90,
    anomalyDetectionSensitivity: 0.8,
    baselineCalculationInterval: 3600000, // 1 hour
    reportGenerationInterval: 86400000, // 1 day
    maxAlerts: 1000,
    maxAnomalies: 500,
    maxAuditEntries: 5000,
  };

  private constructor() {
    super();
    this.initialize();
  }

  /**
   * Get or create singleton instance
   */
  public static getInstance(config?: Partial<WorkspacePerformanceConfig>): WorkspacePerformanceMonitor {
    if (!WorkspacePerformanceMonitor.instance) {
      WorkspacePerformanceMonitor.instance = new WorkspacePerformanceMonitor();
    }
    if (config) {
      WorkspacePerformanceMonitor.instance.updateConfig(config);
    }
    return WorkspacePerformanceMonitor.instance;
  }

  /**
   * Reset singleton for testing
   */
  public static reset(): void {
    WorkspacePerformanceMonitor.instance = undefined;
  }

  /**
   * Initialize service
   */
  private initialize(): void {
    this.emit('initialized', {
      data_object: { service: 'workspace-performance-monitor', status: 'initialized' },
      timestamp: Date.now(),
    });
  }

  /**
   * Record workspace metrics
   */
  public recordMetrics(metrics: WorkspaceMetrics, ipAddress: string, userAgent: string): { success: boolean } {
    try {
      if (!this.config.enableMonitoring) {
        return { success: false };
      }

      if (!this.metrics.has(metrics.workspaceId)) {
        this.metrics.set(metrics.workspaceId, []);
      }

      this.metrics.get(metrics.workspaceId)!.push(metrics);
      this.stats.totalMetricsRecorded++;

      // Check thresholds and trigger alerts
      this.checkThresholds(metrics);

      // Detect anomalies
      if (this.config.enableAnomalyDetection) {
        this.detectAnomalies(metrics.workspaceId);
      }

      this.logAudit(metrics.userId, 'record-metrics', metrics.workspaceId, 'success', {
        metricTypes: Object.keys(metrics.metrics),
      });

      this.emit('metrics-recorded', {
        data_object: { workspaceId: metrics.workspaceId, metricCount: Object.keys(metrics.metrics).length },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit('system', 'record-metrics', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get metrics for workspace
   */
  public getMetrics(workspaceId: string, timeRange?: { start: number; end: number }): WorkspaceMetrics[] {
    const workspaceMetrics = this.metrics.get(workspaceId) || [];

    if (!timeRange) {
      return workspaceMetrics;
    }

    return workspaceMetrics.filter((m) => m.timestamp >= timeRange.start && m.timestamp <= timeRange.end);
  }

  /**
   * Create performance threshold
   */
  public createThreshold(
    threshold: Omit<PerformanceThreshold, 'thresholdId' | 'createdAt' | 'updatedAt'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; thresholdId?: string } {
    try {
      const thresholdId = `threshold-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const newThreshold: PerformanceThreshold = {
        ...threshold,
        thresholdId,
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };

      this.thresholds.set(thresholdId, newThreshold);

      this.logAudit(userId, 'create-threshold', threshold.workspaceId || '', 'success', {
        thresholdId,
        metricType: threshold.metricType,
      });

      this.emit('threshold-created', {
        data_object: { thresholdId, metricType: threshold.metricType },
        timestamp: Date.now(),
      });

      return { success: true, thresholdId };
    } catch (error) {
      this.logAudit(userId, 'create-threshold', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Update performance threshold
   */
  public updateThreshold(
    thresholdId: string,
    updates: Partial<PerformanceThreshold>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean } {
    try {
      const threshold = this.thresholds.get(thresholdId);
      if (!threshold) {
        return { success: false };
      }

      Object.assign(threshold, updates, { updatedAt: Date.now() });

      this.logAudit(userId, 'update-threshold', threshold.workspaceId || '', 'success', {
        thresholdId,
      });

      this.emit('threshold-updated', {
        data_object: { thresholdId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'update-threshold', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Delete performance threshold
   */
  public deleteThreshold(thresholdId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean } {
    try {
      const threshold = this.thresholds.get(thresholdId);
      if (!threshold) {
        return { success: false };
      }

      this.thresholds.delete(thresholdId);

      this.logAudit(userId, 'delete-threshold', threshold.workspaceId || '', 'success', {
        thresholdId,
      });

      this.emit('threshold-deleted', {
        data_object: { thresholdId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'delete-threshold', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get thresholds
   */
  public getThresholds(workspaceId?: string): PerformanceThreshold[] {
    const thresholds = Array.from(this.thresholds.values());

    if (!workspaceId) {
      return thresholds;
    }

    return thresholds.filter((t) => t.workspaceId === workspaceId);
  }

  /**
   * Get alerts
   */
  public getAlerts(workspaceId?: string, status?: 'active' | 'resolved'): PerformanceAlert[] {
    let alerts = Array.from(this.alerts.values());

    if (workspaceId) {
      alerts = alerts.filter((a) => a.workspaceId === workspaceId);
    }

    if (status) {
      alerts = alerts.filter((a) => a.status === status);
    }

    return alerts;
  }

  /**
   * Resolve alert
   */
  public resolveAlert(alertId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean } {
    try {
      const alert = this.alerts.get(alertId);
      if (!alert) {
        return { success: false };
      }

      alert.status = 'resolved';
      alert.resolvedAt = Date.now();
      this.stats.alertsResolved++;

      this.logAudit(userId, 'resolve-alert', alert.workspaceId, 'success', {
        alertId,
      });

      this.emit('alert-resolved', {
        data_object: { alertId, workspaceId: alert.workspaceId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'resolve-alert', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Acknowledge alert
   */
  public acknowledgeAlert(alertId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean } {
    try {
      const alert = this.alerts.get(alertId);
      if (!alert) {
        return { success: false };
      }

      if (!alert.notifiedUsers.includes(userId)) {
        alert.notifiedUsers.push(userId);
      }

      this.logAudit(userId, 'acknowledge-alert', alert.workspaceId, 'success', {
        alertId,
      });

      this.emit('alert-acknowledged', {
        data_object: { alertId, userId },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'acknowledge-alert', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Analyze trends
   */
  public analyzeTrends(workspaceId: string, metricType?: MetricType): PerformanceTrend[] {
    const trends = this.trends.get(workspaceId) || [];

    if (!metricType) {
      return trends;
    }

    return trends.filter((t) => t.metricType === metricType);
  }

  /**
   * Detect anomalies
   */
  public detectAnomalies(workspaceId: string): PerformanceAnomaly[] {
    const workspaceAnomalies = this.anomalies.get(workspaceId) || [];

    // Simple anomaly detection: values outside baseline range
    const baselines = this.getBaselines(workspaceId);
    const recentMetrics = this.getMetrics(workspaceId, {
      start: Date.now() - 3600000, // Last hour
      end: Date.now(),
    });

    const detected: PerformanceAnomaly[] = [];

    for (const baseline of baselines) {
      for (const metric of recentMetrics) {
        const metricValue = (metric.metrics as Record<string, number>)[baseline.metricType];
        if (metricValue && (metricValue < baseline.normalRange.min || metricValue > baseline.normalRange.max)) {
          const anomalyId = `anomaly-${Date.now()}-${Math.random().toString(16).slice(2)}`;
          const anomaly: PerformanceAnomaly = {
            anomalyId,
            workspaceId,
            metricType: baseline.metricType,
            anomalyValue: metricValue,
            expectedRange: baseline.normalRange,
            severity: metricValue > baseline.normalRange.max ? 'critical' : 'warning',
            explanation: `Value ${metricValue} outside expected range [${baseline.normalRange.min}, ${baseline.normalRange.max}]`,
            detectedAt: Date.now(),
            resolved: false,
          };

          detected.push(anomaly);
          this.stats.anomaliesDetected++;
        }
      }
    }

    if (detected.length > 0) {
      workspaceAnomalies.push(...detected);
      this.emit('anomalies-detected', {
        data_object: { workspaceId, anomalyCount: detected.length },
        timestamp: Date.now(),
      });
    }

    return detected;
  }

  /**
   * Generate performance report
   */
  public generateReport(
    workspaceId: string,
    period: { startTime: number; endTime: number },
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; report?: PerformanceReport } {
    try {
      const reportId = `report-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const metricsInPeriod = this.getMetrics(workspaceId, period);

      if (metricsInPeriod.length === 0) {
        return { success: false };
      }

      const summary = {
        averageLatency: this.calculateAverage(metricsInPeriod, 'latency'),
        averageThroughput: this.calculateAverage(metricsInPeriod, 'throughput'),
        peakCpuUsage: this.calculateMax(metricsInPeriod, 'cpuUsage'),
        peakMemoryUsage: this.calculateMax(metricsInPeriod, 'memoryUsage'),
        errorRate: this.calculateAverage(metricsInPeriod, 'errorRate'),
        availability: this.calculateAverage(metricsInPeriod, 'availability'),
      };

      const report: PerformanceReport = {
        reportId,
        workspaceId,
        period,
        summary,
        trends: this.analyzeTrends(workspaceId),
        alerts: this.getAlerts(workspaceId),
        recommendations: this.generateRecommendations(summary),
        generatedAt: Date.now(),
      };

      if (!this.reports.has(workspaceId)) {
        this.reports.set(workspaceId, []);
      }
      this.reports.get(workspaceId)!.push(report);

      this.logAudit(userId, 'generate-report', workspaceId, 'success', {
        reportId,
        metricsAnalyzed: metricsInPeriod.length,
      });

      this.emit('report-generated', {
        data_object: { reportId, workspaceId },
        timestamp: Date.now(),
      });

      return { success: true, report };
    } catch (error) {
      this.logAudit(userId, 'generate-report', workspaceId, 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get reports
   */
  public getReports(workspaceId: string, limit?: number): PerformanceReport[] {
    const reports = this.reports.get(workspaceId) || [];
    return reports.slice(0, limit || 10);
  }

  /**
   * Update baseline
   */
  public updateBaseline(baseline: PerformanceBaseline, userId: string, ipAddress: string, userAgent: string): { success: boolean } {
    try {
      if (!this.baselines.has(baseline.workspaceId)) {
        this.baselines.set(baseline.workspaceId, []);
      }

      const existing = this.baselines.get(baseline.workspaceId)!.findIndex((b) => b.metricType === baseline.metricType);

      if (existing >= 0) {
        this.baselines.get(baseline.workspaceId)![existing] = baseline;
      } else {
        this.baselines.get(baseline.workspaceId)!.push(baseline);
      }

      this.logAudit(userId, 'update-baseline', baseline.workspaceId, 'success', {
        baselineId: baseline.baselineId,
        metricType: baseline.metricType,
      });

      this.emit('baseline-updated', {
        data_object: { workspaceId: baseline.workspaceId, metricType: baseline.metricType },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'update-baseline', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get baseline
   */
  public getBaseline(workspaceId: string, metricType: MetricType): PerformanceBaseline | undefined {
    const baselines = this.baselines.get(workspaceId) || [];
    return baselines.find((b) => b.metricType === metricType);
  }

  /**
   * Get baselines
   */
  public getBaselines(workspaceId: string): PerformanceBaseline[] {
    return this.baselines.get(workspaceId) || [];
  }

  /**
   * Get optimization suggestions
   */
  public getOptimizationSuggestions(workspaceId: string): OptimizationSuggestion[] {
    return this.suggestions.get(workspaceId) || [];
  }

  /**
   * Apply suggestion
   */
  public applySuggestion(suggestionId: string, userId: string, ipAddress: string, userAgent: string): { success: boolean } {
    try {
      for (const [, suggestions] of this.suggestions) {
        const suggestion = suggestions.find((s) => s.suggestionId === suggestionId);
        if (suggestion) {
          suggestion.appliedAt = Date.now();

          this.logAudit(userId, 'apply-suggestion', '', 'success', {
            suggestionId,
            category: suggestion.category,
          });

          this.emit('suggestion-applied', {
            data_object: { suggestionId, category: suggestion.category },
            timestamp: Date.now(),
          });

          return { success: true };
        }
      }

      return { success: false };
    } catch (error) {
      this.logAudit(userId, 'apply-suggestion', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Record event
   */
  public recordEvent(
    event: Omit<PerformanceEvent, 'eventId' | 'startTime'>,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { success: boolean; eventId?: string } {
    try {
      const eventId = `event-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const newEvent: PerformanceEvent = {
        ...event,
        eventId,
        startTime: Date.now(),
      };

      if (!this.events.has(event.workspaceId)) {
        this.events.set(event.workspaceId, []);
      }
      this.events.get(event.workspaceId)!.push(newEvent);

      this.logAudit(userId, 'record-event', event.workspaceId, 'success', {
        eventId,
        eventType: event.eventType,
      });

      this.emit('event-recorded', {
        data_object: { eventId, workspaceId: event.workspaceId, eventType: event.eventType },
        timestamp: Date.now(),
      });

      return { success: true, eventId };
    } catch (error) {
      this.logAudit(userId, 'record-event', '', 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get events
   */
  public getEvents(workspaceId: string): PerformanceEvent[] {
    return this.events.get(workspaceId) || [];
  }

  /**
   * Get statistics
   */
  public getStatistics(workspaceId?: string): PerformanceStatistics {
    if (!workspaceId) {
      return { ...this.stats };
    }

    // Workspace-specific stats
    const wsMetrics = this.getMetrics(workspaceId);
    const wsAlerts = this.getAlerts(workspaceId);
    const wsAnomalies = this.anomalies.get(workspaceId) || [];

    return {
      totalMetricsRecorded: wsMetrics.length,
      alertsTriggered: wsAlerts.length,
      alertsResolved: wsAlerts.filter((a) => a.status === 'resolved').length,
      anomaliesDetected: wsAnomalies.length,
      averageResponseTime: this.calculateAverage(wsMetrics, 'latency'),
      peakThroughput: this.calculateMax(wsMetrics, 'throughput'),
      worstErrorRate: this.calculateMax(wsMetrics, 'errorRate'),
      averageAvailability: this.calculateAverage(wsMetrics, 'availability'),
    };
  }

  /**
   * Get audit log
   */
  public getAuditLog(limit?: number): PerformanceAuditEntry[] {
    const entries: PerformanceAuditEntry[] = [];
    for (const [, userEntries] of this.auditLog) {
      entries.push(...userEntries);
    }
    entries.sort((a, b) => b.timestamp - a.timestamp);
    return entries.slice(0, limit || 100);
  }

  /**
   * Update configuration
   */
  public updateConfig(config: Partial<WorkspacePerformanceConfig>): void {
    this.config = { ...this.config, ...config };

    this.emit('config-updated', {
      data_object: { config: this.config },
      timestamp: Date.now(),
    });
  }

  /**
   * Get configuration
   */
  public getConfig(): WorkspacePerformanceConfig {
    return { ...this.config };
  }

  /**
   * Check thresholds and trigger alerts
   */
  private checkThresholds(metrics: WorkspaceMetrics): void {
    for (const [, threshold] of this.thresholds) {
      if (!threshold.enabled) {
        continue;
      }

      const metricValue = (metrics.metrics as Record<string, number>)[threshold.metricType];
      if (metricValue === undefined) {
        continue;
      }

      let breached = false;
      switch (threshold.operator) {
        case 'gt':
          breached = metricValue > threshold.value;
          break;
        case 'lt':
          breached = metricValue < threshold.value;
          break;
        case 'gte':
          breached = metricValue >= threshold.value;
          break;
        case 'lte':
          breached = metricValue <= threshold.value;
          break;
        case 'eq':
          breached = metricValue === threshold.value;
          break;
        case 'ne':
          breached = metricValue !== threshold.value;
          break;
      }

      if (breached) {
        const alertId = `alert-${Date.now()}-${Math.random().toString(16).slice(2)}`;
        const alert: PerformanceAlert = {
          alertId,
          thresholdId: threshold.thresholdId,
          workspaceId: metrics.workspaceId,
          metricType: threshold.metricType,
          actualValue: metricValue,
          thresholdValue: threshold.value,
          severity: threshold.severity,
          message: `${threshold.metricType} ${threshold.operator} ${threshold.value}: actual ${metricValue}`,
          triggeredAt: Date.now(),
          status: 'active',
          notifiedUsers: threshold.notifyUsers,
        };

        this.alerts.set(alertId, alert);
        this.stats.alertsTriggered++;

        this.emit('alert-triggered', {
          data_object: { alertId, metricType: threshold.metricType, severity: threshold.severity },
          timestamp: Date.now(),
        });
      }
    }
  }

  /**
   * Calculate average
   */
  private calculateAverage(metrics: WorkspaceMetrics[], key: string): number {
    if (metrics.length === 0) {
      return 0;
    }

    const sum = metrics.reduce((acc, m) => acc + ((m.metrics as Record<string, number>)[key] || 0), 0);
    return sum / metrics.length;
  }

  /**
   * Calculate max
   */
  private calculateMax(metrics: WorkspaceMetrics[], key: string): number {
    if (metrics.length === 0) {
      return 0;
    }

    return Math.max(...metrics.map((m) => (m.metrics as Record<string, number>)[key] || 0));
  }

  /**
   * Generate recommendations
   */
  private generateRecommendations(summary: Record<string, number>): string[] {
    const recommendations: string[] = [];

    if (summary.averageLatency > 100) {
      recommendations.push('Consider optimizing query performance - average latency is high');
    }

    if (summary.errorRate > 1) {
      recommendations.push('Investigate error rates - above acceptable threshold');
    }

    if (summary.peakMemoryUsage > 1024) {
      recommendations.push('Consider memory optimization - peak usage is significant');
    }

    return recommendations;
  }

  /**
   * Log audit entry
   */
  private logAudit(userId: string, action: string, workspaceId: string, status: 'success' | 'failure', details?: Record<string, unknown>): void {
    if (!this.auditLog.has(userId)) {
      this.auditLog.set(userId, []);
    }

    const entry: PerformanceAuditEntry = {
      timestamp: Date.now(),
      userId,
      userEmail: `user-${userId}@example.com`,
      action,
      workspaceId,
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
   * Shutdown service
   */
  public shutdown(): void {
    this.metrics.clear();
    this.thresholds.clear();
    this.alerts.clear();
    this.trends.clear();
    this.anomalies.clear();
    this.baselines.clear();
    this.suggestions.clear();
    this.events.clear();
    this.reports.clear();
    this.auditLog.clear();

    this.emit('shutdown', {
      data_object: { service: 'workspace-performance-monitor', status: 'shutdown' },
      timestamp: Date.now(),
    });
  }
}
