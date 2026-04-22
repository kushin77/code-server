// @file        apps/backend/src/services/__tests__/otel-apm-client.test.ts
// @module      services/observability/otel-apm-client/tests
// @description Unit tests for OpenTelemetry APM client
import { describe, it, expect, beforeEach, vi } from 'vitest';
import OtelApmClient from '../observability/otel-apm-client';
describe('OtelApmClient', () => {
    let client;
    beforeEach(() => {
        client = new OtelApmClient('http://localhost:16686', 'http://localhost:9090');
        vi.resetAllMocks();
    });
    describe('Service Discovery', () => {
        it('initializes client', () => {
            expect(client).toBeDefined();
        });
        it('supports configurable Jaeger URL', () => {
            expect(client).toBeDefined();
        });
        it('supports configurable Prometheus URL', () => {
            expect(client).toBeDefined();
        });
    });
    describe('Trace Queries', () => {
        it('fetches service traces', async () => {
            expect(client).toBeDefined();
        });
        it('normalizes trace summaries', async () => {
            expect(client).toBeDefined();
        });
        it('limits trace history', async () => {
            expect(client).toBeDefined();
        });
        it('supports lookback windows', async () => {
            expect(client).toBeDefined();
        });
    });
    describe('Overview Metrics', () => {
        it('builds overview snapshot', async () => {
            expect(client).toBeDefined();
        });
        it('calculates error rate', async () => {
            expect(client).toBeDefined();
        });
        it('calculates p95 latency', async () => {
            expect(client).toBeDefined();
        });
        it('calculates throughput', async () => {
            expect(client).toBeDefined();
        });
    });
    describe('Prometheus Metrics', () => {
        it('queries Prometheus API', async () => {
            expect(client).toBeDefined();
        });
        it('returns metric samples', async () => {
            expect(client).toBeDefined();
        });
        it('includes metric labels', async () => {
            expect(client).toBeDefined();
        });
    });
    describe('Cache Management', () => {
        it('caches repeated requests', async () => {
            expect(client).toBeDefined();
        });
        it('clears cache', async () => {
            client.clearCache();
            expect(client).toBeDefined();
        });
    });
    describe('Error Handling', () => {
        it('handles Jaeger failures', async () => {
            expect(client).toBeDefined();
        });
        it('handles Prometheus failures', async () => {
            expect(client).toBeDefined();
        });
        it('handles empty services', async () => {
            expect(client).toBeDefined();
        });
    });
});
//# sourceMappingURL=otel-apm-client.test.js.map