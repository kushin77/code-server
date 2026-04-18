import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  MetricsAggregator,
  DistributedTracing,
  AnomalyDetection,
  AlertManager,
  Phase7ObservabilityAgent,
} from './Phase7ObservabilityAgent';
import { Logger } from '../../types';

describe('Phase 7: Advanced Observability', () => {
  let mockLogger: Logger;

  beforeEach(() => {
    mockLogger = {
      debug: vi.fn(),
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    };
  });

  describe('MetricsAggregator', () => {
    let aggregator: MetricsAggregator;

    beforeEach(() => {
      aggregator = new MetricsAggregator({
        logger: mockLogger,
        scrapeInterval: 30000,
      });
    });

    afterEach(() => {
      aggregator.stop();
    });

    it('should register metrics', () => {
      aggregator.registerMetric('http.requests', 'counter', 'HTTP requests');
      expect(mockLogger.info).toHaveBeenCalledWith(expect.stringContaining('Registered'));
    });

    it('should record metric values', () => {
      aggregator.registerMetric('cpu.usage', 'gauge', 'CPU usage');
      aggregator.recordMetric('cpu.usage', 45.5);

      const metrics = aggregator.queryMetrics('cpu.usage');
      expect(metrics).toHaveLength(1);
      expect(metrics[0].value).toBe(45.5);
    });

    it('should record metrics with labels', () => {
      aggregator.registerMetric('response.time', 'histogram', 'Response time');
      aggregator.recordMetric('response.time', 125, { service: 'api', endpoint: '/users' });

      const metrics = aggregator.queryMetrics('response.time');
      expect(metrics[0].labels.service).toBe('api');
    });

    it('should aggregate metrics (sum)', () => {
      aggregator.registerMetric('requests.total', 'counter', 'Total requests');

      aggregator.recordMetric('requests.total', 10);
      aggregator.recordMetric('requests.total', 20);
      aggregator.recordMetric('requests.total', 30);

      const sum = aggregator.aggregateMetrics('requests.total', 'sum');
      expect(sum).toBe(60);
    });

    it('should aggregate metrics (avg)', () => {
      aggregator.registerMetric('latency', 'gauge', 'Latency');

      aggregator.recordMetric('latency', 100);
      aggregator.recordMetric('latency', 200);
      aggregator.recordMetric('latency', 300);

      const avg = aggregator.aggregateMetrics('latency', 'avg');
      expect(avg).toBe(200);
    });

    it('should calculate percentiles', () => {
      aggregator.registerMetric('response.time', 'histogram', 'Response time');

      for (let i = 1; i <= 100; i++) {
        aggregator.recordMetric('response.time', i);
      }

      const p99 = aggregator.aggregateMetrics('response.time', 'p99');
      expect(p99).toBeGreaterThan(90);
      expect(p99).toBeLessThanOrEqual(100);
    });

    it('should export Prometheus format', () => {
      aggregator.registerMetric('cpu.usage', 'gauge', 'CPU usage');
      aggregator.recordMetric('cpu.usage', 45, { instance: 'server-1' });

      const prometheus = aggregator.exportPrometheus();
      expect(prometheus).toContain('cpu.usage');
      expect(prometheus).toContain('instance="server-1"');
    });

    it('should start and stop collection', () => {
      aggregator.start();
      expect(aggregator['collectionInterval']).toBeDefined();

      aggregator.stop();
      expect(aggregator['collectionInterval']).toBeNull();
    });

    it('should emit events on metric recording', (done) => {
      aggregator.on('metric-recorded', ({ name, metric }) => {
        expect(name).toBe('test.metric');
        expect(metric.value).toBe(42);
        done();
      });

      aggregator.registerMetric('test.metric', 'gauge', 'Test');
      aggregator.recordMetric('test.metric', 42);
    });
  });

  describe('DistributedTracing', () => {
    let tracer: DistributedTracing;

    beforeEach(() => {
      tracer = new DistributedTracing({ logger: mockLogger });
    });

    it('should start a trace', () => {
      const traceId = 'trace-123';
      const span = tracer.startTrace(traceId);

      expect(span.traceId).toBe(traceId);
      expect(span.name).toBe('root');
      expect(span.status).toBe('ok');
    });

    it('should create child spans', () => {
      const traceId = 'trace-456';
      const rootSpan = tracer.startTrace(traceId);
      const childSpan = tracer.startSpan(traceId, rootSpan.spanId, 'database.query');

      expect(childSpan.parentSpanId).toBe(rootSpan.spanId);
      expect(childSpan.name).toBe('database.query');
    });

    it('should end spans with duration', () => {
      const traceId = 'trace-789';
      const span = tracer.startTrace(traceId);

      // Simulate work
      const started = Date.now();
      while (Date.now() - started < 10) {
        // Wait 10ms
      }

      const endedSpan = tracer.endSpan(traceId, span.spanId);
      expect(endedSpan?.duration).toBeGreaterThanOrEqual(10);
    });

    it('should add tags to spans', () => {
      const traceId = 'trace-tag';
      const span = tracer.startTrace(traceId);

      tracer.addTag(traceId, span.spanId, 'service', 'api');
      tracer.addTag(traceId, span.spanId, 'version', 1);
      tracer.addTag(traceId, span.spanId, 'error', false);

      const retrievedSpan = tracer.getTrace(traceId)?.[0];
      expect(retrievedSpan?.tags.service).toBe('api');
      expect(retrievedSpan?.tags.version).toBe(1);
    });

    it('should add logs to spans', () => {
      const traceId = 'trace-log';
      const span = tracer.startTrace(traceId);

      tracer.addLog(traceId, span.spanId, 'Started processing');
      tracer.addLog(traceId, span.spanId, 'Completed successfully');

      const retrievedSpan = tracer.getTrace(traceId)?.[0];
      expect(retrievedSpan?.logs).toHaveLength(2);
      expect(retrievedSpan?.logs[0].message).toBe('Started processing');
    });

    it('should query traces by criteria', () => {
      const traceId = 'trace-query';
      const span = tracer.startTrace(traceId);

      tracer.addTag(traceId, span.spanId, 'service', 'api');
      tracer.endSpan(traceId, span.spanId);

      const results = tracer.queryTraces({ operation: 'root' });
      expect(results.length).toBeGreaterThan(0);
    });

    it('should export trace as JSON', () => {
      const traceId = 'trace-export';
      const span = tracer.startTrace(traceId);

      const json = tracer.exportTrace(traceId);
      const parsed = JSON.parse(json);

      expect(Array.isArray(parsed)).toBe(true);
      expect(parsed[0].traceId).toBe(traceId);
    });

    it('should emit trace events', (done) => {
      tracer.on('trace-started', (span) => {
        expect(span.name).toBe('root');
        done();
      });

      tracer.startTrace('trace-event');
    });
  });

  describe('AnomalyDetection', () => {
    let detector: AnomalyDetection;

    beforeEach(() => {
      detector = new AnomalyDetection({
        logger: mockLogger,
        sensitivityFactor: 2,
      });
    });

    it('should detect anomalies based on baseline', () => {
      // Establish baseline: 50, 52, 48, 51, 49
      detector.updateBaseline('cpu.usage', [50, 52, 48, 51, 49]);

      // Normal value
      const isNormal = detector.detectAnomaly('cpu.usage', 50);
      expect(isNormal).toBe(false);

      // Anomalous value (very high)
      const isAnomaly = detector.detectAnomaly('cpu.usage', 200);
      expect(isAnomaly).toBe(true);
    });

    it('should get recent anomalies', () => {
      detector.updateBaseline('memory.usage', [100, 102, 98, 101, 99]);

      detector.detectAnomaly('memory.usage', 500);
      detector.detectAnomaly('memory.usage', 600);

      const recent = detector.getRecentAnomalies(5);
      expect(recent.length).toBe(2);
    });

    it('should emit anomaly events', (done) => {
      detector.on('anomaly-detected', (anomaly) => {
        expect(anomaly.metric).toBe('disk.usage');
        expect(anomaly.value).toBeGreaterThan(500);
        done();
      });

      detector.updateBaseline('disk.usage', [10, 12, 11, 9, 10]);
      detector.detectAnomaly('disk.usage', 1000);
    });
  });

  describe('AlertManager', () => {
    let manager: AlertManager;

    beforeEach(() => {
      manager = new AlertManager({ logger: mockLogger });
    });

    it('should register alert rules', () => {
      manager.registerRule({
        name: 'high_cpu',
        condition: 'cpu.usage > 80',
        threshold: 80,
        duration: '5m',
        severity: 'critical',
        actions: ['notify_ops', 'scale_up'],
      });

      expect(mockLogger.info).toHaveBeenCalled();
    });

    it('should fire alerts when threshold exceeded', (done) => {
      manager.registerRule({
        name: 'high_latency',
        condition: 'response.time > 1000',
        threshold: 1000,
        duration: '1m',
        severity: 'warning',
        actions: ['notify'],
      });

      manager.on('alert-fired', (alert) => {
        expect(alert.rule).toBe('high_latency');
        expect(alert.severity).toBe('warning');
        done();
      });

      manager.evaluateRules({ 'response.time': 1500 });
    });

    it('should resolve alerts when threshold cleared', (done) => {
      manager.registerRule({
        name: 'test_alert',
        condition: 'metric > 50',
        threshold: 50,
        duration: '1m',
        severity: 'warning',
        actions: [],
      });

      manager.on('alert-fired', () => {
        manager.on('alert-resolved', () => {
          done();
        });

        manager.evaluateRules({ metric: 40 });
      });

      manager.evaluateRules({ metric: 60 });
    });

    it('should get active alerts', () => {
      manager.registerRule({
        name: 'alert_1',
        condition: 'metric_1 > 100',
        threshold: 100,
        duration: '1m',
        severity: 'critical',
        actions: [],
      });

      manager.evaluateRules({ metric_1: 150 });

      const active = manager.getActiveAlerts();
      expect(active.length).toBeGreaterThan(0);
    });
  });

  describe('Phase7ObservabilityAgent', () => {
    let agent: Phase7ObservabilityAgent;

    beforeEach(() => {
      agent = new Phase7ObservabilityAgent({
        logger: mockLogger,
        metricsInterval: 5000,
        anomalySensitivity: 2.5,
      });
    });

    afterEach(() => {
      agent.stop();
    });

    it('should initialize with all components', () => {
      const components = agent.getComponents();

      expect(components.metrics).toBeDefined();
      expect(components.tracing).toBeDefined();
      expect(components.anomalies).toBeDefined();
      expect(components.alerts).toBeDefined();
    });

    it('should start and stop observability system', () => {
      agent.start();
      expect(agent.isHealthy()).toBe(true);

      agent.stop();
      expect(agent.isHealthy()).toBe(false);
    });

    it('should record metrics and detect anomalies', (done) => {
      agent.on('anomaly-detected', () => {
        done();
      });

      const metrics = agent.getComponents().metrics;
      const anomalies = agent.getComponents().anomalies;

      // Establish baseline
      anomalies.updateBaseline('latency', [100, 102, 98, 101, 99]);

      // Record normal metric
      agent.recordMetric('latency', 100, { service: 'api' });

      // Record anomalous metric
      setTimeout(() => {
        agent.recordMetric('latency', 500, { service: 'api' });
      }, 10);
    });

    it('should track distributed traces', () => {
      const tracer = agent.getComponents().tracing;

      const traceId = 'request-123';
      const rootSpan = tracer.startTrace(traceId);
      const childSpan = tracer.startSpan(traceId, rootSpan.spanId, 'database.query');

      tracer.addTag(traceId, childSpan.spanId, 'table', 'users');
      tracer.endSpan(traceId, childSpan.spanId);

      const trace = tracer.getTrace(traceId);
      expect(trace).toHaveLength(2);
    });

    it('should manage alerts', () => {
      const alertManager = agent.getComponents().alerts;

      alertManager.registerRule({
        name: 'high_cpu',
        condition: 'cpu > 80',
        threshold: 80,
        duration: '5m',
        severity: 'critical',
        actions: ['scale_up'],
      });

      alertManager.evaluateRules({ cpu: 90 });

      const active = alertManager.getActiveAlerts();
      expect(active.length).toBeGreaterThan(0);
    });

    it('should emit observability events', (done) => {
      agent.on('alert-fired', (alert) => {
        expect(alert).toBeDefined();
        done();
      });

      const alertManager = agent.getComponents().alerts;

      alertManager.registerRule({
        name: 'test',
        condition: 'value > 50',
        threshold: 50,
        duration: '1m',
        severity: 'warning',
        actions: [],
      });

      alertManager.evaluateRules({ value: 60 });
    });

    it('should handle high-frequency metric recording', () => {
      agent.start();

      const start = Date.now();

      for (let i = 0; i < 1000; i++) {
        agent.recordMetric(`metric.${i % 10}`, Math.random() * 100);
      }

      const duration = Date.now() - start;

      expect(duration).toBeLessThan(1000); // SLA: < 1s for 1000 metrics
    });
  });

  describe('Integration: End-to-End Observability', () => {
    let agent: Phase7ObservabilityAgent;

    beforeEach(() => {
      agent = new Phase7ObservabilityAgent({
        logger: mockLogger,
        metricsInterval: 5000,
        anomalySensitivity: 2,
      });
    });

    afterEach(() => {
      agent.stop();
    });

    it('should track request from start to finish', () => {
      const tracer = agent.getComponents().tracing;
      const metrics = agent.getComponents().metrics;

      // Start request trace
      const traceId = 'req-001';
      const requestSpan = tracer.startTrace(traceId);
      tracer.addTag(traceId, requestSpan.spanId, 'method', 'GET');
      tracer.addTag(traceId, requestSpan.spanId, 'endpoint', '/api/users');

      // Record database call span
      const dbSpan = tracer.startSpan(traceId, requestSpan.spanId, 'database.query');
      tracer.addTag(traceId, dbSpan.spanId, 'query', 'SELECT * FROM users');

      // Simulate work
      const dbStart = Date.now();
      while (Date.now() - dbStart < 50) {
        // Wait
      }

      tracer.endSpan(traceId, dbSpan.spanId);

      // Record metrics
      agent.recordMetric('request.duration', tracer.endSpan(traceId, requestSpan.spanId)?.duration || 0);
      agent.recordMetric('db.query.duration', dbSpan.duration);

      // Verify trace
      const trace = tracer.getTrace(traceId);
      expect(trace).toHaveLength(2);
      expect(trace![0].duration).toBeGreaterThan(50);
    });

    it('should correlate metrics, traces, and alerts', () => {
      const metrics = agent.getComponents().metrics;
      const tracer = agent.getComponents().tracing;
      const alertManager = agent.getComponents().alerts;

      // Register alert
      alertManager.registerRule({
        name: 'slow_query',
        condition: 'db.latency > 500',
        threshold: 500,
        duration: '5m',
        severity: 'warning',
        actions: ['log', 'notify'],
      });

      // Record slow query
      const traceId = 'slow-query-001';
      tracer.startTrace(traceId);
      agent.recordMetric('db.latency', 750, { query_type: 'SELECT' });

      // Evaluate alert
      alertManager.evaluateRules({ 'db.latency': 750 });

      const active = alertManager.getActiveAlerts();
      expect(active.length).toBeGreaterThan(0);
    });
  });
});
