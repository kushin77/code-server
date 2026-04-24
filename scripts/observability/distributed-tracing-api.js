#!/usr/bin/env node
/**
 * @file        scripts/observability/distributed-tracing-api.js
 * @module      observability/tracing
 * @description REST API for OpenTelemetry distributed tracing
 */

const express = require('express');
const DistributedTracingService = require('./distributed-tracing-service');

const app = express();
const PORT = process.env.PORT || 9099;

// Initialize service
const tracingService = new DistributedTracingService({
    serviceName: process.env.SERVICE_NAME || 'code-server',
    jaegerEndpoint: process.env.JAEGER_ENDPOINT,
});

// Event listeners
tracingService.on('trace-started', (context) => {
    console.log(`[Tracing] Started: ${context.traceId} - ${context.eventType}`);
});

tracingService.on('trace-completed', (context) => {
    console.log(`[Tracing] Completed: ${context.traceId} - ${context.duration}ms (${context.spanCount} spans)`);
});

// Middleware
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
    res.json({ status: 'healthy', service: 'distributed-tracing' });
});

// Start trace
app.post('/traces', (req, res) => {
    try {
        const { eventType, metadata } = req.body;
        
        if (!eventType) {
            return res.status(400).json({ error: 'eventType is required' });
        }
        
        const traceId = tracingService.createTrace(eventType, metadata);
        
        res.status(201).json({
            status: 'started',
            traceId,
            timestamp: new Date().toISOString(),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Record span
app.post('/traces/:traceId/spans', (req, res) => {
    try {
        const { spanName, operation, component, parentSpanId } = req.body;
        
        if (!spanName) {
            return res.status(400).json({ error: 'spanName is required' });
        }
        
        const spanId = tracingService.recordSpan(
            req.params.traceId,
            spanName,
            { operation, component, parentSpanId }
        );
        
        res.status(201).json({
            status: 'recorded',
            spanId,
            traceId: req.params.traceId,
            timestamp: new Date().toISOString(),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// End span
app.post('/spans/:spanId/end', (req, res) => {
    try {
        const { statusCode, statusMessage } = req.body;
        
        const span = tracingService.endSpan(req.params.spanId, {
            statusCode,
            statusMessage,
        });
        
        res.json({
            status: 'ended',
            spanId: span.spanId,
            durationMs: span.durationMs,
            timestamp: span.endTimeIso,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Complete trace
app.post('/traces/:traceId/complete', (req, res) => {
    try {
        const { statusCode, statusMessage, hasError, errorMessage } = req.body;
        
        const trace = tracingService.completeTrace(
            req.params.traceId,
            { statusCode, statusMessage, hasError, errorMessage }
        );
        
        res.json({
            status: 'completed',
            traceId: trace.traceId,
            durationMs: trace.durationMs,
            spanCount: trace.spanCount,
            latencies: trace.latencies,
            timestamp: trace.endTimeIso,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get trace
app.get('/traces/:traceId', (req, res) => {
    try {
        const trace = tracingService.getTrace(req.params.traceId);
        
        if (!trace) {
            return res.status(404).json({ error: 'Trace not found' });
        }
        
        res.json({
            traceId: trace.traceId,
            eventType: trace.eventType,
            startTime: trace.startTimeIso,
            endTime: trace.endTimeIso,
            durationMs: trace.durationMs,
            spanCount: trace.spanCount,
            latencies: trace.latencies,
            status: trace.statusCode,
            hasError: trace.hasError,
            spans: trace.spans.map(s => ({
                spanId: s.spanId,
                name: s.name,
                operation: s.operation,
                durationMs: s.durationMs,
                statusCode: s.statusCode,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Query traces
app.get('/traces', (req, res) => {
    try {
        const filters = {
            eventType: req.query.eventType,
            minDurationMs: req.query.minDuration ? parseInt(req.query.minDuration) : undefined,
            maxDurationMs: req.query.maxDuration ? parseInt(req.query.maxDuration) : undefined,
            hasError: req.query.hasError === 'true',
            limit: req.query.limit ? parseInt(req.query.limit) : 100,
        };
        
        const traces = tracingService.queryTraces(filters);
        
        res.json({
            total: traces.length,
            filters,
            traces: traces.map(t => ({
                traceId: t.traceId,
                eventType: t.eventType,
                durationMs: t.durationMs,
                spanCount: t.spanCount,
                status: t.statusCode,
                hasError: t.hasError,
                startTime: t.startTimeIso,
            })),
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Get latency percentiles
app.get('/latency/:eventType', (req, res) => {
    try {
        const latencies = tracingService.getLatencyPercentiles(req.params.eventType);
        
        res.json({
            eventType: req.params.eventType,
            percentiles: {
                p50: Array.isArray(latencies.p50) ? 
                    latencies.p50[Math.floor(latencies.p50.length * 0.5)] : latencies.p50,
                p95: Array.isArray(latencies.p95) ? 
                    latencies.p95[Math.floor(latencies.p95.length * 0.95)] : latencies.p95,
                p99: Array.isArray(latencies.p99) ? 
                    latencies.p99[Math.floor(latencies.p99.length * 0.99)] : latencies.p99,
            },
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Export to Jaeger
app.post('/traces/:traceId/export', async (req, res) => {
    try {
        const jaegerTrace = await tracingService.exportTraceToJaeger(req.params.traceId);
        
        res.json({
            status: 'exported',
            traceId: req.params.traceId,
            destination: 'Jaeger',
            spans: jaegerTrace.spans.length,
        });
    } catch (err) {
        res.status(400).json({ error: err.message });
    }
});

// Listen
app.listen(PORT, () => {
    console.log(`[Distributed Tracing API] Listening on port ${PORT}`);
    console.log(`[Distributed Tracing API] POST /traces - Start trace`);
    console.log(`[Distributed Tracing API] POST /traces/:traceId/spans - Record span`);
    console.log(`[Distributed Tracing API] POST /spans/:spanId/end - End span`);
    console.log(`[Distributed Tracing API] POST /traces/:traceId/complete - Complete trace`);
    console.log(`[Distributed Tracing API] GET /traces/:traceId - Get trace details`);
    console.log(`[Distributed Tracing API] GET /traces - Query traces`);
    console.log(`[Distributed Tracing API] GET /latency/:eventType - Get latency percentiles`);
    console.log(`[Distributed Tracing API] POST /traces/:traceId/export - Export to Jaeger`);
});
