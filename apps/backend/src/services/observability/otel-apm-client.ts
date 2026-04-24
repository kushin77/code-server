// @file        apps/backend/src/services/observability/otel-apm-client.ts
// @module      services/observability/otel-apm-client
// @description OpenTelemetry APM query client for Jaeger and Prometheus

import axios, { AxiosInstance } from 'axios';

export interface TraceSummary {
  traceId: string;
  service: string;
  operation: string;
  durationMs: number;
  errorCount: number;
  spanCount: number;
  startedAt: string;
  tags: Record<string, string>;
}

export interface MetricSample {
  metric: string;
  value: number;
  timestamp: string;
  labels: Record<string, string>;
}

export interface ApmOverview {
  services: number;
  activeTraces: number;
  errorRate: number;
  p95LatencyMs: number;
  throughputPerMinute: number;
}

export class OtelApmClient {
  private jaegerClient: AxiosInstance;
  private prometheusClient: AxiosInstance;
  private cache = new Map<string, { value: any; timestamp: number }>();
  private cacheTtlMs = 60_000;

  constructor(
    jaegerBaseUrl: string = 'http://localhost:16686',
    prometheusBaseUrl: string = 'http://localhost:9090'
  ) {
    this.jaegerClient = axios.create({ baseURL: jaegerBaseUrl, timeout: 10_000 });
    this.prometheusClient = axios.create({ baseURL: prometheusBaseUrl, timeout: 10_000 });
  }

  async listServices(): Promise<string[]> {
    return this.cached('services', async () => {
      const response = await this.jaegerClient.get('/api/services');
      return (response.data.data || []) as string[];
    });
  }

  async getTraces(service: string, lookback: string = '1h', limit: number = 20): Promise<TraceSummary[]> {
    return this.cached(`traces:${service}:${lookback}:${limit}`, async () => {
      const response = await this.jaegerClient.get('/api/traces', {
        params: { service, lookback, limit },
      });

      const traces = response.data.data || [];
      return traces.map((trace: any) => this.normalizeTrace(trace));
    });
  }

  async getTrace(traceId: string): Promise<any> {
    return this.cached(`trace:${traceId}`, async () => {
      const response = await this.jaegerClient.get(`/api/traces/${traceId}`);
      return response.data.data;
    });
  }

  async getOverview(service?: string): Promise<ApmOverview> {
    const services = await this.listServices();
    const traces = service ? await this.getTraces(service, '1h', 50) : [];

    const p95LatencyMs = traces.length
      ? this.quantile(traces.map((trace) => trace.durationMs), 0.95)
      : await this.queryLatencyP95(service);

    const errorRate = traces.length
      ? traces.filter((trace) => trace.errorCount > 0).length / traces.length
      : await this.queryErrorRate(service);

    const throughputPerMinute = await this.queryThroughput(service);

    return {
      services: services.length,
      activeTraces: traces.length,
      errorRate,
      p95LatencyMs,
      throughputPerMinute,
    };
  }

  async queryPrometheus(query: string): Promise<MetricSample[]> {
    return this.cached(`prom:${query}`, async () => {
      const response = await this.prometheusClient.get('/api/v1/query', { params: { query } });
      const result = response.data?.data?.result || [];

      return result.map((item: any) => ({
        metric: item.metric?.__name__ || query,
        value: Number(item.value?.[1] || 0),
        timestamp: new Date(Number(item.value?.[0] || Date.now() / 1000) * 1000).toISOString(),
        labels: item.metric || {},
      }));
    });
  }

  async getServiceMetrics(service: string): Promise<Record<string, MetricSample[]>> {
    return {
      requestRate: await this.queryPrometheus(
        `sum(rate(http_server_requests_total{service="${service}"}[5m]))`
      ),
      errorRate: await this.queryPrometheus(
        `sum(rate(http_server_requests_total{service="${service}",status=~"5.."}[5m]))`
      ),
      latencyP95: await this.queryPrometheus(
        `histogram_quantile(0.95, sum(rate(http_server_duration_ms_bucket{service="${service}"}[5m])) by (le))`
      ),
    };
  }

  clearCache(): void {
    this.cache.clear();
  }

  private normalizeTrace(trace: any): TraceSummary {
    const spans = trace.spans || [];
    const root = spans[0] || {};
    const end = root.endTime || root.startTime || Date.now() * 1_000_000;
    const start = root.startTime || end;
    const durationMs = Math.max(0, Math.round((end - start) / 1_000_000));

    return {
      traceId: trace.traceID || trace.traceId || '',
      service: root.process?.serviceName || trace.processes?.[Object.keys(trace.processes || {})[0]]?.serviceName || 'unknown',
      operation: root.operationName || 'unknown',
      durationMs,
      errorCount: spans.filter((span: any) => span.tags?.some((tag: any) => tag.key === 'error' && tag.value === true)).length,
      spanCount: spans.length,
      startedAt: new Date(start / 1_000_000).toISOString(),
      tags: this.collectTags(root.tags || []),
    };
  }

  private collectTags(tags: Array<{ key: string; value: any }>): Record<string, string> {
    return tags.reduce<Record<string, string>>((acc, tag) => {
      acc[tag.key] = String(tag.value);
      return acc;
    }, {});
  }

  private async queryLatencyP95(service?: string): Promise<number> {
    const selector = service ? `{service="${service}"}` : '';
    const samples = await this.queryPrometheus(
      `histogram_quantile(0.95, sum(rate(http_server_duration_ms_bucket${selector}[5m])) by (le))`
    );
    return samples[0]?.value || 0;
  }

  private async queryErrorRate(service?: string): Promise<number> {
    const selector = service ? `{service="${service}"}` : '';
    const samples = await this.queryPrometheus(
      `sum(rate(http_server_requests_total${selector}, status=~"5.."[5m]))`
    );
    return samples[0]?.value || 0;
  }

  private async queryThroughput(service?: string): Promise<number> {
    const selector = service ? `{service="${service}"}` : '';
    const samples = await this.queryPrometheus(
      `sum(rate(http_server_requests_total${selector}[5m])) * 60`
    );
    return samples[0]?.value || 0;
  }

  private quantile(values: number[], q: number): number {
    if (values.length === 0) return 0;
    const sorted = [...values].sort((a, b) => a - b);
    const index = Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * q));
    return sorted[index];
  }

  private async cached<T>(key: string, fn: () => Promise<T>): Promise<T> {
    const cached = this.cache.get(key);
    if (cached && Date.now() - cached.timestamp < this.cacheTtlMs) {
      return cached.value;
    }

    const value = await fn();
    this.cache.set(key, { value, timestamp: Date.now() });
    return value;
  }
}

export default OtelApmClient;
