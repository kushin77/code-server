/**
 * SLO/SLA tracking service for collaboration platform.
 * Manages SLO tracking engine and provides integration points.
 */

import { SLOTrackingEngine, DEFAULT_SLO_CONFIG } from './engine';
import {
  SyncLatencyMetric,
  SLOMetrics,
  SLOBreach,
  SLOAggregation,
  SLOTrackingConfig,
  PerSessionSLOStats,
} from './types';

export interface SLOAlertEvent {
  type: 'slo_breach' | 'slo_recovery';
  timestamp: number;
  sessionId: string;
  compliancePercent: number;
  targetPercent: number;
  breach?: SLOBreach;
}

class SLOTrackingService {
  private static instance: SLOTrackingService | null = null;
  private engine: SLOTrackingEngine;
  private alertCallbacks: Set<(event: SLOAlertEvent) => Promise<void>> = new Set();
  private lastComplianceStatus: Map<string, number> = new Map();

  private constructor(config: Partial<SLOTrackingConfig> = {}) {
    this.engine = new SLOTrackingEngine(config);
    this.startComplianceMonitoring();
  }

  /**
   * Get or create the singleton service instance
   */
  static getInstance(config?: Partial<SLOTrackingConfig>): SLOTrackingService {
    if (!this.instance) {
      this.instance = new SLOTrackingService(config);
    }
    return this.instance;
  }

  /**
   * Reset instance (for testing)
   */
  static resetInstance(): void {
    if (this.instance) {
      this.instance.engine.destroy();
      this.instance = null;
    }
  }

  /**
   * Record a sync event
   */
  recordSync(
    sessionId: string,
    operationType: string,
    latencyMs: number,
    clientCount: number = 1,
    error?: string
  ): SyncLatencyMetric {
    const now = Date.now();
    const metric = this.engine.recordSync({
      id: `sync-${now}-${Math.random().toString(36).substr(2, 9)}`,
      sessionId,
      startTime: now - latencyMs,
      endTime: now,
      latencyMs,
      operationType,
      clientCount,
      error,
    });

    return metric;
  }

  /**
   * Get current SLO metrics
   */
  getMetrics(sinceMs?: number): SLOMetrics {
    return this.engine.calculateMetrics(sinceMs);
  }

  /**
   * Get metrics for a specific window
   */
  getWindowMetrics(startMs: number, endMs: number): SLOAggregation {
    return this.engine.getWindowMetrics(startMs, endMs);
  }

  /**
   * Get per-session metrics
   */
  getSessionStats(sessionId: string): PerSessionSLOStats | null {
    return this.engine.getSessionStats(sessionId);
  }

  /**
   * Get all active session stats
   */
  getAllSessionStats(): PerSessionSLOStats[] {
    return this.engine.getAllSessionStats();
  }

  /**
   * Get recent SLO breaches
   */
  getRecentBreaches(limit?: number, sinceMs?: number): SLOBreach[] {
    return this.engine.getRecentBreaches(limit, sinceMs);
  }

  /**
   * Get metrics for the last N minutes
   */
  getLastMinutesMetrics(minutes?: number): SLOAggregation[] {
    return this.engine.getLastMinutesMetrics(minutes);
  }

  /**
   * Register a callback for SLO events
   */
  onSLOEvent(callback: (event: SLOAlertEvent) => Promise<void>): void {
    this.alertCallbacks.add(callback);
  }

  /**
   * Unregister an SLO event callback
   */
  offSLOEvent(callback: (event: SLOAlertEvent) => Promise<void>): void {
    this.alertCallbacks.delete(callback);
  }

  /**
   * Get Prometheus metrics format
   */
  getPrometheusMetrics(): string {
    const metrics = this.getMetrics();
    const lastMinute = this.getLastMinutesMetrics(1)[0];

    const lines: string[] = [
      '# HELP slo_sync_events_total Total number of sync events',
      '# TYPE slo_sync_events_total counter',
      `slo_sync_events_total ${metrics.totalEvents}`,
      '',
      '# HELP slo_sync_breaches_total Total number of SLO breaches',
      '# TYPE slo_sync_breaches_total counter',
      `slo_sync_breaches_total ${metrics.sloBreached}`,
      '',
      '# HELP slo_compliance_percent SLO compliance percentage',
      '# TYPE slo_compliance_percent gauge',
      `slo_compliance_percent ${metrics.sloCompliancePercent}`,
      '',
      '# HELP slo_sync_latency_ms Sync latency in milliseconds',
      '# TYPE slo_sync_latency_ms gauge',
      `slo_sync_latency_ms{quantile="0.5"} ${metrics.p50LatencyMs}`,
      `slo_sync_latency_ms{quantile="0.95"} ${metrics.p95LatencyMs}`,
      `slo_sync_latency_ms{quantile="0.99"} ${metrics.p99LatencyMs}`,
      `slo_sync_latency_ms{quantile="avg"} ${metrics.averageLatencyMs}`,
      '',
      '# HELP slo_active_sessions Number of active sessions',
      '# TYPE slo_active_sessions gauge',
      `slo_active_sessions ${metrics.sessionCount}`,
      '',
      '# HELP slo_last_minute_compliance Last minute SLO compliance',
      '# TYPE slo_last_minute_compliance gauge',
      `slo_last_minute_compliance ${lastMinute.metrics.sloCompliancePercent}`,
    ];

    return lines.join('\n');
  }

  /**
   * Clean up resources
   */
  destroy(): void {
    this.engine.destroy();
    this.alertCallbacks.clear();
  }

  // Private methods

  private startComplianceMonitoring(): void {
    // Monitor compliance every minute and emit alerts
    setInterval(() => {
      const metrics = this.getMetrics();
      const sessionStats = this.getAllSessionStats();

      sessionStats.forEach((stats) => {
        const lastStatus = this.lastComplianceStatus.get(stats.sessionId) || 100;
        const breachedLastStatus = lastStatus >= 99.9;
        const breachedCurrentStatus = stats.sloCompliancePercent < 99.9;

        // Trigger alert if compliance crossed threshold
        if (breachedLastStatus !== breachedCurrentStatus) {
          const event: SLOAlertEvent = {
            type: breachedCurrentStatus ? 'slo_breach' : 'slo_recovery',
            timestamp: Date.now(),
            sessionId: stats.sessionId,
            compliancePercent: stats.sloCompliancePercent,
            targetPercent: 99.9,
          };

          this.emitAlert(event);
        }

        this.lastComplianceStatus.set(stats.sessionId, stats.sloCompliancePercent);
      });
    }, 60 * 1000); // Check every minute
  }

  private async emitAlert(event: SLOAlertEvent): Promise<void> {
    const promises = Array.from(this.alertCallbacks).map((callback) =>
      callback(event).catch((err) => {
        console.error('Error in SLO alert callback:', err);
      })
    );
    await Promise.all(promises);
  }
}

/**
 * Get the singleton SLO tracking service instance
 */
export function getSLOTrackingService(
  config?: Partial<SLOTrackingConfig>
): SLOTrackingService {
  return SLOTrackingService.getInstance(config);
}

export default SLOTrackingService;
