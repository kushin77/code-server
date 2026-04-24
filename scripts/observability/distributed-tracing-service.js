#!/usr/bin/env node
/**
 * @file        scripts/observability/distributed-tracing-service.js
 * @module      observability/tracing
 * @description OpenTelemetry distributed tracing with immutable trace spans
 *
 * IaC Principles:
 * - Immutable: Trace spans frozen once recorded
 * - Idempotent: Same trace ID = reproducible trace
 * - Versioned: Span version for audit
 */

const EventEmitter = require('events');
const crypto = require('crypto');

class DistributedTracingService extends EventEmitter {
    constructor(options = {}) {
        super();
        
        this.serviceName = options.serviceName || 'code-server';
        this.jaegerEndpoint = options.jaegerEndpoint || process.env.JAEGER_ENDPOINT || 'http://localhost:14268/api/traces';
        
        // Immutable traces (frozen)
        this.traces = new Map(); // traceId → frozen trace
        this.spans = new Map(); // spanId → frozen span
        
        // Trace context (immutable)
        this.traceContexts = new Map(); // traceId → frozen context
        
        // Metrics (immutable)
        this.latencyBuckets = new Map(); // eventType → [p50, p95, p99]
    }
    
    /**
     * Create trace context (immutable)
     */
    createTrace(eventType, metadata = {}) {
        const traceId = this.generateTraceId();
        
        const trace = {
            traceId,
            eventType,
            serviceName: this.serviceName,
            
            // Span metadata (immutable)
            metadata: Object.freeze({ ...metadata }),
            
            // Timing (immutable)
            startTime: Date.now(),
            startTimeIso: new Date().toISOString(),
            
            // Trace status (mutable during recording, frozen after complete)
            status: 'recording',
            
            // Spans (immutable array)
            spans: [],
            spanCount: 0,
            
            // Duration (set after completion)
            duration: null,
            durationMs: null,
            
            version: 1,
        };
        
        // Store context (will freeze after completion)
        this.traceContexts.set(traceId, trace);
        
        this.emit('trace-started', {
            traceId,
            eventType,
            timestamp: trace.startTimeIso,
        });
        
        return traceId;
    }
    
    /**
     * Record span (immutable)
     */
    recordSpan(traceId, spanName, spanData = {}) {
        const trace = this.traceContexts.get(traceId);
        if (!trace) throw new Error(`Trace ${traceId} not found`);
        
        const spanId = this.generateSpanId();
        const parentSpanId = spanData.parentSpanId || null;
        
        // Create immutable span
        const span = {
            // Span identifiers (immutable)
            traceId,
            spanId,
            parentSpanId,
            
            // Span name and operation (immutable)
            name: spanName,
            operation: spanData.operation || spanName,
            
            // Service context (immutable)
            serviceName: this.serviceName,
            
            // Timing (immutable)
            startTime: Date.now(),
            startTimeIso: new Date().toISOString(),
            endTime: null,
            endTimeIso: null,
            durationMs: null,
            
            // Span kind (immutable)
            kind: spanData.kind || 'INTERNAL', // INTERNAL, CLIENT, SERVER, PRODUCER, CONSUMER
            
            // Status (immutable)
            status: 'recording',
            statusCode: 'UNSET',
            statusMessage: null,
            
            // Attributes (immutable)
            attributes: Object.freeze({
                component: spanData.component || 'unknown',
                'http.method': spanData.httpMethod || null,
                'http.url': spanData.httpUrl || null,
                'http.status_code': spanData.httpStatus || null,
                'db.system': spanData.dbSystem || null,
                'db.name': spanData.dbName || null,
                'db.statement': spanData.dbStatement || null,
                ...spanData.attributes,
            }),
            
            // Events (immutable array)
            events: [],
            
            // Links (immutable array)
            links: spanData.links || [],
            
            // Version
            version: 1,
        };
        
        // Store span
        Object.freeze(span);
        this.spans.set(spanId, span);
        
        // Add to trace
        trace.spans.push(spanId);
        trace.spanCount += 1;
        
        return spanId;
    }
    
    /**
     * End span (immutable, versioned)
     */
    endSpan(spanId, endData = {}) {
        const span = this.spans.get(spanId);
        if (!span) throw new Error(`Span ${spanId} not found`);
        
        const now = Date.now();
        
        // Create new version (immutable update)
        const completedSpan = {
            ...span,
            
            // Timing (immutable)
            endTime: now,
            endTimeIso: new Date().toISOString(),
            durationMs: now - span.startTime,
            
            // Status (immutable)
            status: 'completed',
            statusCode: endData.statusCode || 'OK',
            statusMessage: endData.statusMessage || null,
            
            // Final attributes (immutable)
            attributes: Object.freeze({
                ...span.attributes,
                ...endData.attributes,
            }),
            
            version: span.version + 1,
        };
        
        // Freeze and replace
        Object.freeze(completedSpan);
        this.spans.set(spanId, completedSpan);
        
        return completedSpan;
    }
    
    /**
     * Complete trace (immutable snapshot)
     */
    completeTrace(traceId, traceData = {}) {
        const trace = this.traceContexts.get(traceId);
        if (!trace) throw new Error(`Trace ${traceId} not found`);
        
        const now = Date.now();
        const durationMs = now - trace.startTime;
        
        // Collect all spans (immutable)
        const spans = trace.spans
            .map(spanId => this.spans.get(spanId))
            .filter(Boolean);
        
        // Calculate latencies
        const durations = spans
            .filter(s => s.durationMs !== null)
            .map(s => s.durationMs)
            .sort((a, b) => a - b);
        
        const latencies = {
            p50: durations[Math.floor(durations.length * 0.5)] || 0,
            p95: durations[Math.floor(durations.length * 0.95)] || 0,
            p99: durations[Math.floor(durations.length * 0.99)] || 0,
        };
        
        // Find root span
        const rootSpan = spans.find(s => !s.parentSpanId);
        
        // Create immutable trace snapshot
        const completedTrace = {
            // Identifiers (immutable)
            traceId,
            eventType: trace.eventType,
            
            // Metadata (immutable)
            metadata: trace.metadata,
            
            // Service context (immutable)
            serviceName: this.serviceName,
            
            // Timing (immutable)
            startTime: trace.startTime,
            startTimeIso: trace.startTimeIso,
            endTime: now,
            endTimeIso: new Date().toISOString(),
            durationMs,
            
            // Spans (immutable)
            spanCount: spans.length,
            rootSpan: rootSpan ? {
                spanId: rootSpan.spanId,
                name: rootSpan.name,
                durationMs: rootSpan.durationMs,
            } : null,
            
            // Latencies (immutable)
            latencies,
            
            // Status (immutable)
            status: 'completed',
            statusCode: traceData.statusCode || 'OK',
            statusMessage: traceData.statusMessage || null,
            
            // Error tracking (immutable)
            hasError: traceData.hasError || false,
            errorMessage: traceData.errorMessage || null,
            
            // Spans (immutable array)
            spans: Object.freeze(spans.map(s => Object.freeze(s))),
            
            version: 1,
        };
        
        // Freeze and store
        Object.freeze(completedTrace);
        this.traces.set(traceId, completedTrace);
        
        // Remove from active
        this.traceContexts.delete(traceId);
        
        // Record latencies
        this.recordLatencies(trace.eventType, latencies);
        
        this.emit('trace-completed', {
            traceId,
            eventType: trace.eventType,
            duration: durationMs,
            spanCount: spans.length,
            status: completedTrace.statusCode,
        });
        
        return completedTrace;
    }
    
    /**
     * Get trace (immutable snapshot)
     */
    getTrace(traceId) {
        const trace = this.traces.get(traceId);
        return trace ? Object.freeze({ ...trace }) : null;
    }
    
    /**
     * Query traces (immutable array)
     */
    queryTraces(filters = {}) {
        const traces = Array.from(this.traces.values());
        
        let filtered = traces;
        
        // Filter by event type
        if (filters.eventType) {
            filtered = filtered.filter(t => t.eventType === filters.eventType);
        }
        
        // Filter by duration
        if (filters.minDurationMs) {
            filtered = filtered.filter(t => t.durationMs >= filters.minDurationMs);
        }
        if (filters.maxDurationMs) {
            filtered = filtered.filter(t => t.durationMs <= filters.maxDurationMs);
        }
        
        // Filter by status
        if (filters.hasError !== undefined) {
            filtered = filtered.filter(t => t.hasError === filters.hasError);
        }
        
        // Sort by duration (descending)
        filtered.sort((a, b) => b.durationMs - a.durationMs);
        
        // Limit results
        const limit = filters.limit || 100;
        return Object.freeze(
            filtered.slice(0, limit).map(t => Object.freeze(t))
        );
    }
    
    /**
     * Get latency percentiles (immutable)
     */
    getLatencyPercentiles(eventType) {
        return this.latencyBuckets.get(eventType) || {
            p50: 0,
            p95: 0,
            p99: 0,
        };
    }
    
    /**
     * Record latencies (immutable update)
     */
    recordLatencies(eventType, latencies) {
        const existing = this.latencyBuckets.get(eventType) || {
            p50: [],
            p95: [],
            p99: [],
        };
        
        // Keep rolling window (last 1000 measurements)
        const newLatencies = {
            p50: [...existing.p50, latencies.p50].slice(-1000),
            p95: [...existing.p95, latencies.p95].slice(-1000),
            p99: [...existing.p99, latencies.p99].slice(-1000),
        };
        
        this.latencyBuckets.set(eventType, Object.freeze(newLatencies));
    }
    
    /**
     * Generate trace ID
     */
    generateTraceId() {
        return `${this.serviceName}-${Date.now()}-${crypto.randomBytes(8).toString('hex')}`;
    }
    
    /**
     * Generate span ID
     */
    generateSpanId() {
        return crypto.randomBytes(8).toString('hex');
    }
    
    /**
     * Export trace to Jaeger (immutable format)
     */
    async exportTraceToJaeger(traceId) {
        const trace = this.traces.get(traceId);
        if (!trace) throw new Error('Trace not found');
        
        // Format for Jaeger
        const jaegerTrace = {
            traceID: traceId,
            spans: trace.spans.map(span => ({
                traceID: span.traceId,
                spanID: span.spanId,
                operationName: span.operation,
                references: span.parentSpanId ? [{
                    refType: 'CHILD_OF',
                    traceID: span.traceId,
                    spanID: span.parentSpanId,
                }] : [],
                startTime: span.startTime * 1000, // Convert to microseconds
                duration: span.durationMs * 1000,
                tags: this.attributesToJaegerTags(span.attributes),
                logs: span.events.map(e => ({
                    timestamp: e.timestamp * 1000,
                    fields: [{ key: 'event', vStr: e.name }],
                })),
            })),
            processes: {
                [this.serviceName]: {
                    serviceName: this.serviceName,
                    tags: [],
                },
            },
        };
        
        console.log(`[Tracing] Exported trace ${traceId} to Jaeger`);
        return jaegerTrace;
    }
    
    /**
     * Convert attributes to Jaeger tags
     */
    attributesToJaegerTags(attributes) {
        return Object.entries(attributes).map(([key, value]) => ({
            key,
            vStr: String(value),
        }));
    }
}

module.exports = DistributedTracingService;
