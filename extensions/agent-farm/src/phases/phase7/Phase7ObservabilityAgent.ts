import { EventEmitter } from 'events';
import { Logger } from '../../types';

/**
 * Phase 7: Advanced Observability
 * Comprehensive metrics, tracing, and alerting system
 */

export interface MetricPoint {
  timestamp: number;
  value: number;
  labels: Record<string, string>;
}

export interface TraceSpan {
  traceId: string;
  spanId: string;
  parentSpanId?: string;
  name: string;
  startTime: number;
  endTime: number;
  duration: number;
  tags: Record<string, string | number | boolean>;
  logs: Array<{ timestamp: number; message: string }>;
  status: 'ok' | 'error';
}

export interface AlertRule {
  name: string;
  condition: string;
  threshold: number;
  duration: string;
  severity: 'info' | 'warning' | 'critical';
  actions: string[];
}

/**
 * MetricsAggregator: Prometheus-based metrics collection
 * Aggregates metrics from all services and stores in Prometheus
 */
export class MetricsAggregator extends EventEmitter {
  private metrics: Map<string, MetricPoint[]> = new Map();
  private logger: Logger;
  private collectionInterval: NodeJS.Timer | null = null;

  constructor(private config: { logger: Logger; scrapeInterval: number }) {
    super();
    this.logger = config.logger;
  }

  /**
   * Register a metric to be collected
   */
  registerMetric(
    name: string,
    type: 'counter' | 'gauge' | 'histogram' | 'summary',
    help: string
  ): void {
    if (!this.metrics.has(name)) {
      this.metrics.set(name, []);
      this.logger.info(`Registered metric: ${name} (${type})`);
    }
  }

  /**
   * Record a metric value
   */
  recordMetric(name: string, value: number, labels?: Record<string, string>): void {
    if (!this.metrics.has(name)) {
      this.registerMetric(name, 'gauge', name);
    }

    const metric: MetricPoint = {
      timestamp: Date.now(),
      value,
      labels: labels || {},
    };

    const points = this.metrics.get(name) || [];
    points.push(metric);

    // Keep last 1000 points per metric
    if (points.length > 1000) {
      points.shift();
    }

    this.metrics.set(name, points);
    this.emit('metric-recorded', { name, metric });
  }

  /**
   * Query metrics by name and optional filters
   */
  queryMetrics(
    name: string,
    options?: { startTime?: number; endTime?: number; labels?: Record<string, string> }
  ): MetricPoint[] {
    const points = this.metrics.get(name) || [];
    const startTime = options?.startTime || Date.now() - 3600000; // Last hour default
    const endTime = options?.endTime || Date.now();

    return points.filter((point) => {
      if (point.timestamp < startTime || point.timestamp > endTime) {
        return false;
      }

      if (options?.labels) {
        return Object.entries(options.labels).every(
          ([key, value]) => point.labels[key] === value
        );
      }

      return true;
    });
  }

  /**
   * Aggregate metrics (sum, avg, max, percentile)
   */
  aggregateMetrics(
    name: string,
    operation: 'sum' | 'avg' | 'max' | 'min' | 'p99' | 'p95',
    startTime?: number,
    endTime?: number
  ): number {
    const points = this.queryMetrics(name, { startTime, endTime });

    if (points.length === 0) {
      return 0;
    }

    const values = points.map((p) => p.value);

    switch (operation) {
      case 'sum':
        return values.reduce((a, b) => a + b, 0);
      case 'avg':
        return values.reduce((a, b) => a + b, 0) / values.length;
      case 'max':
        return Math.max(...values);
      case 'min':
        return Math.min(...values);
      case 'p99':
        return this.calculatePercentile(values, 0.99);
      case 'p95':
        return this.calculatePercentile(values, 0.95);
    }
  }

  /**
   * Calculate percentile
   */
  private calculatePercentile(values: number[], percentile: number): number {
    const sorted = [...values].sort((a, b) => a - b);
    const index = Math.ceil(sorted.length * percentile) - 1;
    return sorted[Math.max(0, index)];
  }

  /**
   * Export metrics in Prometheus format
   */
  exportPrometheus(): string {
    let output = '';

    for (const [name, points] of this.metrics.entries()) {
      if (points.length === 0) continue;

      output += `# HELP ${name} Collected metric\n`;
      output += `# TYPE ${name} gauge\n`;

      for (const point of points.slice(-100)) {
        // Last 100 points
        const labels = Object.entries(point.labels)
          .map(([k, v]) => `${k}="${v}"`)
          .join(',');
        const labelStr = labels ? `{${labels}}` : '';
        output += `${name}${labelStr} ${point.value} ${point.timestamp}\n`;
      }
    }

    return output;
  }

  /**
   * Start periodic metric collection
   */
  start(): void {
    this.collectionInterval = setInterval(() => {
      this.emit('collection-cycle');
    }, this.config.scrapeInterval);

    this.logger.info('MetricsAggregator started');
  }

  /**
   * Stop metric collection
   */
  stop(): void {
    if (this.collectionInterval) {
      clearInterval(this.collectionInterval);
      this.collectionInterval = null;
    }

    this.logger.info('MetricsAggregator stopped');
  }
}

/**
 * DistributedTracing: Jaeger-based distributed tracing
 * Tracks requests across microservices
 */
export class DistributedTracing extends EventEmitter {
  private traces: Map<string, TraceSpan[]> = new Map();
  private logger: Logger;

  constructor(private config: { logger: Logger }) {
    super();
    this.logger = config.logger;
  }

  /**
   * Start a new trace
   */
  startTrace(traceId: string): TraceSpan {
    const span: TraceSpan = {
      traceId,
      spanId: this.generateSpanId(),
      name: 'root',
      startTime: Date.now(),
      endTime: 0,
      duration: 0,
      tags: {},
      logs: [],
      status: 'ok',
    };

    if (!this.traces.has(traceId)) {
      this.traces.set(traceId, []);
    }

    this.traces.get(traceId)!.push(span);
    this.emit('trace-started', span);

    return span;
  }

  /**
   * Create a child span
   */
  startSpan(
    traceId: string,
    parentSpanId: string,
    name: string
  ): TraceSpan {
    const span: TraceSpan = {
      traceId,
      spanId: this.generateSpanId(),
      parentSpanId,
      name,
      startTime: Date.now(),
      endTime: 0,
      duration: 0,
      tags: {},
      logs: [],
      status: 'ok',
    };

    if (!this.traces.has(traceId)) {
      this.traces.set(traceId, []);
    }

    this.traces.get(traceId)!.push(span);
    return span;
  }

  /**
   * End a span
   */
  endSpan(traceId: string, spanId: string, status: 'ok' | 'error' = 'ok'): TraceSpan | null {
    const spans = this.traces.get(traceId);
    if (!spans) return null;

    const span = spans.find((s) => s.spanId === spanId);
    if (!span) return null;

    span.endTime = Date.now();
    span.duration = span.endTime - span.startTime;
    span.status = status;

    this.emit('span-ended', span);

    return span;
  }

  /**
   * Add tag to span
   */
  addTag(traceId: string, spanId: string, key: string, value: string | number | boolean): void {
    const spans = this.traces.get(traceId) || [];
    const span = spans.find((s) => s.spanId === spanId);

    if (span) {
      span.tags[key] = value;
    }
  }

  /**
   * Add log to span
   */
  addLog(traceId: string, spanId: string, message: string): void {
    const spans = this.traces.get(traceId) || [];
    const span = spans.find((s) => s.spanId === spanId);

    if (span) {
      span.logs.push({
        timestamp: Date.now(),
        message,
      });
    }
  }

  /**
   * Get trace by ID
   */
  getTrace(traceId: string): TraceSpan[] | null {
    return this.traces.get(traceId) || null;
  }

  /**
   * Generate unique span ID
   */
  private generateSpanId(): string {
    return Math.random().toString(36).substr(2, 16);
  }

  /**
   * Query traces by criteria
   */
  queryTraces(options: {
    service?: string;
    operation?: string;
    minDuration?: number;
    tags?: Record<string, string>;
  }): TraceSpan[] {
    const results: TraceSpan[] = [];

    for (const spans of this.traces.values()) {
      for (const span of spans) {
        let matches = true;

        if (options.operation && span.name !== options.operation) {
          matches = false;
        }

        if (options.minDuration && span.duration < options.minDuration) {
          matches = false;
        }

        if (options.tags) {
          matches = Object.entries(options.tags).every(
            ([key, value]) => span.tags[key] === value
          );
        }

        if (matches) {
          results.push(span);
        }
      }
    }

    return results;
  }

  /**
   * Export trace as JSON
   */
  exportTrace(traceId: string): string {
    const spans = this.traces.get(traceId) || [];
    return JSON.stringify(spans, null, 2);
  }
}

/**
 * AnomalyDetection: Real-time anomaly detection
 * Detects unusual patterns in metrics
 */
export class AnomalyDetection extends EventEmitter {
  private baselines: Map<string, number[]> = new Map();
  private anomalies: Array<{ metric: string; timestamp: number; value: number; deviation: number }> = [];
  private logger: Logger;

  constructor(private config: { logger: Logger; sensitivityFactor: number }) {
    super();
    this.logger = config.logger;
  }

  /**
   * Update baseline for a metric
   */
  updateBaseline(metric: string, values: number[]): void {
    this.baselines.set(metric, values);
    this.logger.debug(`Updated baseline for ${metric} with ${values.length} values`);
  }

  /**
   * Detect anomaly in new value
   */
  detectAnomaly(metric: string, value: number): boolean {
    const baseline = this.baselines.get(metric);
    if (!baseline || baseline.length === 0) {
      return false; // No baseline to compare
    }

    const mean = baseline.reduce((a, b) => a + b, 0) / baseline.length;
    const variance =
      baseline.reduce((sum, val) => sum + Math.pow(val - mean, 2), 0) / baseline.length;
    const stdDev = Math.sqrt(variance);

    const deviation = Math.abs(value - mean) / (stdDev || 1);
    const threshold = this.config.sensitivityFactor;

    const isAnomaly = deviation > threshold;

    if (isAnomaly) {
      const anomaly = {
        metric,
        timestamp: Date.now(),
        value,
        deviation,
      };

      this.anomalies.push(anomaly);
      this.emit('anomaly-detected', anomaly);
      this.logger.warn(
        `Anomaly in ${metric}: value=${value}, deviation=${deviation.toFixed(2)}σ`
      );
    }

    return isAnomaly;
  }

  /**
   * Get recent anomalies
   */
  getRecentAnomalies(minutes: number = 5): typeof this.anomalies {
    const cutoff = Date.now() - minutes * 60000;
    return this.anomalies.filter((a) => a.timestamp > cutoff);
  }
}

/**
 * AlertManager: Alert rule evaluation and routing
 * Manages alert rules and notification delivery
 */
export class AlertManager extends EventEmitter {
  private rules: Map<string, AlertRule> = new Map();
  private activeAlerts: Map<string, { timestamp: number; resolvedAt?: number }> = new Map();
  private logger: Logger;

  constructor(private config: { logger: Logger }) {
    super();
    this.logger = config.logger;
  }

  /**
   * Register an alert rule
   */
  registerRule(rule: AlertRule): void {
    this.rules.set(rule.name, rule);
    this.logger.info(`Registered alert rule: ${rule.name} (${rule.severity})`);
  }

  /**
   * Evaluate all rules against metrics
   */
  evaluateRules(metrics: Record<string, number>): void {
    for (const [ruleName, rule] of this.rules.entries()) {
      this.evaluateRule(rule, metrics);
    }
  }

  /**
   * Evaluate a specific rule
   */
  private evaluateRule(rule: AlertRule, metrics: Record<string, number>): void {
    // Simple evaluation: match metric name from condition
    const metricName = rule.condition.split(/[<>=]+/)[0].trim();
    const value = metrics[metricName];

    if (value === undefined) {
      return;
    }

    const isFiring = value > rule.threshold;
    const alertId = `${rule.name}-${metricName}`;
    const isActive = this.activeAlerts.has(alertId);

    if (isFiring && !isActive) {
      // Alert started firing
      this.activeAlerts.set(alertId, {
        timestamp: Date.now(),
      });

      this.emit('alert-fired', {
        rule: rule.name,
        severity: rule.severity,
        metric: metricName,
        value,
        threshold: rule.threshold,
      });

      this.logger.warn(
        `ALERT FIRED: ${rule.name} - ${metricName}=${value} > ${rule.threshold}`
      );
    } else if (!isFiring && isActive) {
      // Alert resolved
      const alert = this.activeAlerts.get(alertId);
      if (alert) {
        alert.resolvedAt = Date.now();
      }

      this.emit('alert-resolved', {
        rule: rule.name,
        metric: metricName,
      });

      this.logger.info(
        `ALERT RESOLVED: ${rule.name} - ${metricName}=${value} <= ${rule.threshold}`
      );
    }
  }

  /**
   * Get active alerts
   */
  getActiveAlerts(): Array<{
    alertId: string;
    firedAt: number;
    duration: number;
  }> {
    const now = Date.now();
    return Array.from(this.activeAlerts.entries())
      .filter(([_, alert]) => !alert.resolvedAt)
      .map(([alertId, alert]) => ({
        alertId,
        firedAt: alert.timestamp,
        duration: now - alert.timestamp,
      }));
  }
}

/**
 * Phase7ObservabilityAgent: Unified observability orchestrator
 * Coordinates metrics, tracing, anomaly detection, and alerting
 */
export class Phase7ObservabilityAgent extends EventEmitter {
  private metricsAggregator: MetricsAggregator;
  private distributedTracing: DistributedTracing;
  private anomalyDetection: AnomalyDetection;
  private alertManager: AlertManager;
  private logger: Logger;
  private isRunning: boolean = false;

  constructor(config: {
    logger: Logger;
    metricsInterval?: number;
    anomalySensitivity?: number;
  }) {
    super();
    this.logger = config.logger;

    this.metricsAggregator = new MetricsAggregator({
      logger: this.logger,
      scrapeInterval: config.metricsInterval || 30000,
    });

    this.distributedTracing = new DistributedTracing({
      logger: this.logger,
    });

    this.anomalyDetection = new AnomalyDetection({
      logger: this.logger,
      sensitivityFactor: config.anomalySensitivity || 3,
    });

    this.alertManager = new AlertManager({
      logger: this.logger,
    });

    this.setupListeners();
  }

  /**
   * Setup event listeners for cross-component communication
   */
  private setupListeners(): void {
    // Anomalies trigger alerts
    this.anomalyDetection.on('anomaly-detected', (anomaly) => {
      this.emit('anomaly-detected', anomaly);
    });

    // Alert manager fires alerts
    this.alertManager.on('alert-fired', (alert) => {
      this.emit('alert-fired', alert);
    });

    this.alertManager.on('alert-resolved', (alert) => {
      this.emit('alert-resolved', alert);
    });
  }

  /**
   * Start observability system
   */
  start(): void {
    this.metricsAggregator.start();
    this.isRunning = true;
    this.logger.info('Phase 7 Observability Agent started');
  }

  /**
   * Stop observability system
   */
  stop(): void {
    this.metricsAggregator.stop();
    this.isRunning = false;
    this.logger.info('Phase 7 Observability Agent stopped');
  }

  /**
   * Get all observability components
   */
  getComponents() {
    return {
      metrics: this.metricsAggregator,
      tracing: this.distributedTracing,
      anomalies: this.anomalyDetection,
      alerts: this.alertManager,
    };
  }

  /**
   * Record metrics
   */
  recordMetric(name: string, value: number, labels?: Record<string, string>): void {
    this.metricsAggregator.recordMetric(name, value, labels);

    // Check for anomalies
    this.anomalyDetection.detectAnomaly(name, value);
  }

  /**
   * Health check
   */
  isHealthy(): boolean {
    return this.isRunning;
  }
}
