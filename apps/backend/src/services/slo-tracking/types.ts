/**
 * SLO/SLA tracking types for collaboration sync guarantee monitoring.
 * Tracks sync latency metrics against < 100ms target.
 */

export interface SyncLatencyMetric {
  /** Unique event ID */
  id: string;
  
  /** Session ID for this sync event */
  sessionId: string;
  
  /** Timestamp when sync started (milliseconds since epoch) */
  startTime: number;
  
  /** Timestamp when sync completed (milliseconds since epoch) */
  endTime: number;
  
  /** Total latency in milliseconds */
  latencyMs: number;
  
  /** Operation type: 'edit', 'cursor', 'selection', 'other' */
  operationType: string;
  
  /** Number of clients affected by this sync */
  clientCount: number;
  
  /** Whether SLO (< 100ms) was met */
  sloMet: boolean;
  
  /** Optional error if sync failed */
  error?: string;
}

export interface SLOMetrics {
  /** Total sync events measured */
  totalEvents: number;
  
  /** Events that met SLO (< 100ms) */
  sloMet: number;
  
  /** Events that breached SLO (>= 100ms) */
  sloBreached: number;
  
  /** SLO compliance percentage (0-100) */
  sloCompliancePercent: number;
  
  /** Average latency in milliseconds */
  averageLatencyMs: number;
  
  /** 50th percentile (median) latency in milliseconds */
  p50LatencyMs: number;
  
  /** 95th percentile latency in milliseconds */
  p95LatencyMs: number;
  
  /** 99th percentile latency in milliseconds */
  p99LatencyMs: number;
  
  /** Maximum latency observed in milliseconds */
  maxLatencyMs: number;
  
  /** Minimum latency observed in milliseconds */
  minLatencyMs: number;
  
  /** Number of sessions tracked */
  sessionCount: number;
}

export interface SLOBreach {
  /** Unique breach ID */
  id: string;
  
  /** Timestamp when breach occurred */
  timestamp: number;
  
  /** Session ID affected */
  sessionId: string;
  
  /** How much over SLO target (milliseconds) */
  breachAmountMs: number;
  
  /** Actual latency observed */
  actualLatencyMs: number;
  
  /** Operation type that caused breach */
  operationType: string;
  
  /** Severity: 'warning' (100-200ms), 'critical' (> 200ms) */
  severity: 'warning' | 'critical';
}

export interface SLOAggregation {
  /** Time window start (milliseconds since epoch) */
  windowStart: number;
  
  /** Time window end (milliseconds since epoch) */
  windowEnd: number;
  
  /** Duration of window in milliseconds */
  windowDurationMs: number;
  
  /** Aggregated metrics for this window */
  metrics: SLOMetrics;
  
  /** SLO breaches during this window */
  breaches: SLOBreach[];
  
  /** Whether overall SLO target was met for this window (>= 99.9%) */
  targetMet: boolean;
}

export interface SLOTrackingConfig {
  /** SLO target in milliseconds (default: 100) */
  sloTargetMs: number;
  
  /** Overall target compliance percentage (default: 99.9) */
  targetCompliancePercent: number;
  
  /** Warning threshold for latency (milliseconds) */
  warningThresholdMs: number;
  
  /** Critical threshold for latency (milliseconds) */
  criticalThresholdMs: number;
  
  /** How long to retain metrics in memory (milliseconds) */
  retentionMs: number;
  
  /** Aggregation window size for dashboards (milliseconds) */
  aggregationWindowMs: number;
  
  /** Whether to enable alerting on breaches */
  enableAlerting: boolean;
}

export interface PerSessionSLOStats {
  /** Session ID */
  sessionId: string;
  
  /** Total syncs in this session */
  totalSyncs: number;
  
  /** Syncs that met SLO */
  sloMetCount: number;
  
  /** Current session SLO compliance */
  sloCompliancePercent: number;
  
  /** Average latency for this session */
  avgLatencyMs: number;
}
