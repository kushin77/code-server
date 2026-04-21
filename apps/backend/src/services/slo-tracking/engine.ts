/**
 * SLO/SLA tracking engine for collaboration sync latency monitoring.
 * Measures sync events against < 100ms target and tracks compliance.
 */

import {
  SyncLatencyMetric,
  SLOMetrics,
  SLOBreach,
  SLOAggregation,
  SLOTrackingConfig,
  PerSessionSLOStats,
} from './types';

export const DEFAULT_SLO_CONFIG: SLOTrackingConfig = {
  sloTargetMs: 100,
  targetCompliancePercent: 99.9,
  warningThresholdMs: 150,
  criticalThresholdMs: 300,
  retentionMs: 24 * 60 * 60 * 1000, // 24 hours
  aggregationWindowMs: 60 * 1000, // 1 minute
  enableAlerting: true,
};

export class SLOTrackingEngine {
  private config: SLOTrackingConfig;
  private metrics: Map<string, SyncLatencyMetric> = new Map();
  private breaches: SLOBreach[] = [];
  private sessionStats: Map<string, PerSessionSLOStats> = new Map();
  private cleanupInterval: NodeJS.Timeout | null = null;

  constructor(config: Partial<SLOTrackingConfig> = {}) {
    this.config = { ...DEFAULT_SLO_CONFIG, ...config };
    this.startCleanupInterval();
  }

  /**
   * Record a sync latency measurement
   */
  recordSync(event: Omit<SyncLatencyMetric, 'sloMet'>): SyncLatencyMetric {
    const sloMet = event.latencyMs < this.config.sloTargetMs;
    const metric: SyncLatencyMetric = { ...event, sloMet };

    this.metrics.set(event.id, metric);

    // Update session stats
    this.updateSessionStats(event.sessionId, sloMet, event.latencyMs);

    // Track breaches
    if (!sloMet) {
      const severity =
        event.latencyMs > this.config.criticalThresholdMs
          ? 'critical'
          : 'warning';

      const breach: SLOBreach = {
        id: `breach-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
        timestamp: event.endTime,
        sessionId: event.sessionId,
        breachAmountMs: event.latencyMs - this.config.sloTargetMs,
        actualLatencyMs: event.latencyMs,
        operationType: event.operationType,
        severity,
      };

      this.breaches.push(breach);
    }

    return metric;
  }

  /**
   * Calculate overall SLO metrics for all recorded syncs
   */
  calculateMetrics(
    sinceMs?: number
  ): SLOMetrics {
    const cutoffTime = sinceMs || Date.now() - this.config.retentionMs;
    const relevantMetrics = Array.from(this.metrics.values()).filter(
      (m) => m.endTime >= cutoffTime
    );

    if (relevantMetrics.length === 0) {
      return {
        totalEvents: 0,
        sloMet: 0,
        sloBreached: 0,
        sloCompliancePercent: 100,
        averageLatencyMs: 0,
        p50LatencyMs: 0,
        p95LatencyMs: 0,
        p99LatencyMs: 0,
        maxLatencyMs: 0,
        minLatencyMs: 0,
        sessionCount: 0,
      };
    }

    const latencies = relevantMetrics.map((m) => m.latencyMs).sort((a, b) => a - b);
    const sloMet = relevantMetrics.filter((m) => m.sloMet).length;
    const sloBreached = relevantMetrics.length - sloMet;

    return {
      totalEvents: relevantMetrics.length,
      sloMet,
      sloBreached,
      sloCompliancePercent: (sloMet / relevantMetrics.length) * 100,
      averageLatencyMs: latencies.reduce((a, b) => a + b, 0) / latencies.length,
      p50LatencyMs: this.percentile(latencies, 50),
      p95LatencyMs: this.percentile(latencies, 95),
      p99LatencyMs: this.percentile(latencies, 99),
      maxLatencyMs: latencies[latencies.length - 1],
      minLatencyMs: latencies[0],
      sessionCount: new Set(relevantMetrics.map((m) => m.sessionId)).size,
    };
  }

  /**
   * Get aggregated metrics for a specific time window
   */
  getWindowMetrics(startMs: number, endMs: number): SLOAggregation {
    const windowMetrics = Array.from(this.metrics.values()).filter(
      (m) => m.endTime >= startMs && m.endTime <= endMs
    );

    const windowBreaches = this.breaches.filter(
      (b) => b.timestamp >= startMs && b.timestamp <= endMs
    );

    // Recalculate metrics for this window
    if (windowMetrics.length === 0) {
      return {
        windowStart: startMs,
        windowEnd: endMs,
        windowDurationMs: endMs - startMs,
        metrics: {
          totalEvents: 0,
          sloMet: 0,
          sloBreached: 0,
          sloCompliancePercent: 100,
          averageLatencyMs: 0,
          p50LatencyMs: 0,
          p95LatencyMs: 0,
          p99LatencyMs: 0,
          maxLatencyMs: 0,
          minLatencyMs: 0,
          sessionCount: 0,
        },
        breaches: windowBreaches,
        targetMet: true,
      };
    }

    const latencies = windowMetrics.map((m) => m.latencyMs).sort((a, b) => a - b);
    const sloMet = windowMetrics.filter((m) => m.sloMet).length;
    const sloBreached = windowMetrics.length - sloMet;
    const compliancePercent = (sloMet / windowMetrics.length) * 100;

    return {
      windowStart: startMs,
      windowEnd: endMs,
      windowDurationMs: endMs - startMs,
      metrics: {
        totalEvents: windowMetrics.length,
        sloMet,
        sloBreached,
        sloCompliancePercent: compliancePercent,
        averageLatencyMs:
          latencies.reduce((a, b) => a + b, 0) / latencies.length,
        p50LatencyMs: this.percentile(latencies, 50),
        p95LatencyMs: this.percentile(latencies, 95),
        p99LatencyMs: this.percentile(latencies, 99),
        maxLatencyMs: latencies[latencies.length - 1],
        minLatencyMs: latencies[0],
        sessionCount: new Set(windowMetrics.map((m) => m.sessionId)).size,
      },
      breaches: windowBreaches,
      targetMet: compliancePercent >= this.config.targetCompliancePercent,
    };
  }

  /**
   * Get per-session SLO stats
   */
  getSessionStats(sessionId: string): PerSessionSLOStats | null {
    return this.sessionStats.get(sessionId) || null;
  }

  /**
   * Get all active session stats
   */
  getAllSessionStats(): PerSessionSLOStats[] {
    return Array.from(this.sessionStats.values());
  }

  /**
   * Get recent breaches (most recent first)
   */
  getRecentBreaches(limit: number = 20, sinceMs?: number): SLOBreach[] {
    const cutoff = sinceMs || Date.now() - this.config.retentionMs;
    return this.breaches
      .filter((b) => b.timestamp >= cutoff)
      .sort((a, b) => b.timestamp - a.timestamp)
      .slice(0, limit);
  }

  /**
   * Get aggregated metrics over last N minutes
   */
  getLastMinutesMetrics(minutes: number = 60): SLOAggregation[] {
    const now = Date.now();
    const windowMs = this.config.aggregationWindowMs;
    const windows: SLOAggregation[] = [];

    for (let i = minutes - 1; i >= 0; i--) {
      const endTime = now - i * 60 * 1000;
      const startTime = endTime - 60 * 1000;
      windows.push(this.getWindowMetrics(startTime, endTime));
    }

    return windows;
  }

  /**
   * Reset all metrics (for testing)
   */
  reset(): void {
    this.metrics.clear();
    this.breaches = [];
    this.sessionStats.clear();
  }

  /**
   * Destroy the engine and cleanup resources
   */
  destroy(): void {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
    }
  }

  // Private methods

  private percentile(sortedArray: number[], p: number): number {
    if (sortedArray.length === 0) return 0;
    const index = Math.ceil((p / 100) * sortedArray.length) - 1;
    return sortedArray[Math.max(0, index)];
  }

  private updateSessionStats(
    sessionId: string,
    sloMet: boolean,
    latencyMs: number
  ): void {
    let stats = this.sessionStats.get(sessionId);
    if (!stats) {
      stats = {
        sessionId,
        totalSyncs: 0,
        sloMetCount: 0,
        sloCompliancePercent: 100,
        avgLatencyMs: 0,
      };
      this.sessionStats.set(sessionId, stats);
    }

    stats.totalSyncs++;
    if (sloMet) {
      stats.sloMetCount++;
    }
    stats.sloCompliancePercent = (stats.sloMetCount / stats.totalSyncs) * 100;
    stats.avgLatencyMs =
      (stats.avgLatencyMs * (stats.totalSyncs - 1) + latencyMs) / stats.totalSyncs;
  }

  private startCleanupInterval(): void {
    // Cleanup old metrics every hour
    this.cleanupInterval = setInterval(() => {
      const cutoffTime = Date.now() - this.config.retentionMs;

      // Remove old metrics
      const idsToDelete: string[] = [];
      this.metrics.forEach((metric, id) => {
        if (metric.endTime < cutoffTime) {
          idsToDelete.push(id);
        }
      });
      idsToDelete.forEach((id) => this.metrics.delete(id));

      // Remove old breaches
      this.breaches = this.breaches.filter((b) => b.timestamp >= cutoffTime);

      // Remove inactive session stats
      const activeSessions = new Set(
        Array.from(this.metrics.values()).map((m) => m.sessionId)
      );
      const sessionsToDelete: string[] = [];
      this.sessionStats.forEach((_, sessionId) => {
        if (!activeSessions.has(sessionId)) {
          sessionsToDelete.push(sessionId);
        }
      });
      sessionsToDelete.forEach((id) => this.sessionStats.delete(id));
    }, 60 * 60 * 1000); // Run every hour
  }
}
