// @file        apps/backend/src/services/observability/otel-apm-client.ts
// @module      services/observability/otel-apm-client
// @description OpenTelemetry APM query client for Jaeger and Prometheus
import axios from 'axios';
export class OtelApmClient {
    constructor(jaegerBaseUrl = 'http://localhost:16686', prometheusBaseUrl = 'http://localhost:9090') {
        this.cache = new Map();
        this.cacheTtlMs = 60000;
        this.jaegerClient = axios.create({ baseURL: jaegerBaseUrl, timeout: 10000 });
        this.prometheusClient = axios.create({ baseURL: prometheusBaseUrl, timeout: 10000 });
    }
    async listServices() {
        return this.cached('services', async () => {
            const response = await this.jaegerClient.get('/api/services');
            return (response.data.data || []);
        });
    }
    async getTraces(service, lookback = '1h', limit = 20) {
        return this.cached(`traces:${service}:${lookback}:${limit}`, async () => {
            const response = await this.jaegerClient.get('/api/traces', {
                params: { service, lookback, limit },
            });
            const traces = response.data.data || [];
            return traces.map((trace) => this.normalizeTrace(trace));
        });
    }
    async getTrace(traceId) {
        return this.cached(`trace:${traceId}`, async () => {
            const response = await this.jaegerClient.get(`/api/traces/${traceId}`);
            return response.data.data;
        });
    }
    async getOverview(service) {
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
    async queryPrometheus(query) {
        return this.cached(`prom:${query}`, async () => {
            const response = await this.prometheusClient.get('/api/v1/query', { params: { query } });
            const result = response.data?.data?.result || [];
            return result.map((item) => ({
                metric: item.metric?.__name__ || query,
                value: Number(item.value?.[1] || 0),
                timestamp: new Date(Number(item.value?.[0] || Date.now() / 1000) * 1000).toISOString(),
                labels: item.metric || {},
            }));
        });
    }
    async getServiceMetrics(service) {
        return {
            requestRate: await this.queryPrometheus(`sum(rate(http_server_requests_total{service="${service}"}[5m]))`),
            errorRate: await this.queryPrometheus(`sum(rate(http_server_requests_total{service="${service}",status=~"5.."}[5m]))`),
            latencyP95: await this.queryPrometheus(`histogram_quantile(0.95, sum(rate(http_server_duration_ms_bucket{service="${service}"}[5m])) by (le))`),
        };
    }
    clearCache() {
        this.cache.clear();
    }
    normalizeTrace(trace) {
        const spans = trace.spans || [];
        const root = spans[0] || {};
        const end = root.endTime || root.startTime || Date.now() * 1000000;
        const start = root.startTime || end;
        const durationMs = Math.max(0, Math.round((end - start) / 1000000));
        return {
            traceId: trace.traceID || trace.traceId || '',
            service: root.process?.serviceName || trace.processes?.[Object.keys(trace.processes || {})[0]]?.serviceName || 'unknown',
            operation: root.operationName || 'unknown',
            durationMs,
            errorCount: spans.filter((span) => span.tags?.some((tag) => tag.key === 'error' && tag.value === true)).length,
            spanCount: spans.length,
            startedAt: new Date(start / 1000000).toISOString(),
            tags: this.collectTags(root.tags || []),
        };
    }
    collectTags(tags) {
        return tags.reduce((acc, tag) => {
            acc[tag.key] = String(tag.value);
            return acc;
        }, {});
    }
    async queryLatencyP95(service) {
        const selector = service ? `{service="${service}"}` : '';
        const samples = await this.queryPrometheus(`histogram_quantile(0.95, sum(rate(http_server_duration_ms_bucket${selector}[5m])) by (le))`);
        return samples[0]?.value || 0;
    }
    async queryErrorRate(service) {
        const selector = service ? `{service="${service}"}` : '';
        const samples = await this.queryPrometheus(`sum(rate(http_server_requests_total${selector}, status=~"5.."[5m]))`);
        return samples[0]?.value || 0;
    }
    async queryThroughput(service) {
        const selector = service ? `{service="${service}"}` : '';
        const samples = await this.queryPrometheus(`sum(rate(http_server_requests_total${selector}[5m])) * 60`);
        return samples[0]?.value || 0;
    }
    quantile(values, q) {
        if (values.length === 0)
            return 0;
        const sorted = [...values].sort((a, b) => a - b);
        const index = Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * q));
        return sorted[index];
    }
    async cached(key, fn) {
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
//# sourceMappingURL=otel-apm-client.js.map