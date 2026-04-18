// @file        backend/src/lib/tracing.ts
// @module      observability
// @description OpenTelemetry SDK initialization with W3C TraceContext propagation,
//              auto-instrumentation for HTTP clients and PostgreSQL/Redis, and
//              trace-context injection helpers for inter-service calls.
// @owner       platform
// @status      active

import { NodeSDK } from '@opentelemetry/sdk-node';
import { Resource } from '@opentelemetry/resources';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';
import {
  BatchSpanProcessor,
  ConsoleSpanExporter,
  SimpleSpanProcessor,
  SpanProcessor,
} from '@opentelemetry/sdk-trace-node';
import { W3CTraceContextPropagator } from '@opentelemetry/core';
import { CompositePropagator, W3CBaggagePropagator } from '@opentelemetry/core';
import { trace, context, SpanStatusCode, SpanKind, type Span, type Tracer } from '@opentelemetry/api';
import { AsyncLocalStorageContextManager } from '@opentelemetry/context-async-hooks';
import { HttpInstrumentation } from '@opentelemetry/instrumentation-http';
import { PgInstrumentation } from '@opentelemetry/instrumentation-pg';
import { RedisInstrumentation } from '@opentelemetry/instrumentation-redis-4';

// ── Types ─────────────────────────────────────────────────────────────────────

export interface TracingConfig {
  serviceName: string;
  serviceVersion?: string;
  otlpEndpoint?: string;
  /** Disable tracing entirely (e.g. unit tests without OTel infra) */
  disabled?: boolean;
}

// ── SDK initialization ────────────────────────────────────────────────────────

let _sdk: NodeSDK | null = null;

/**
 * Initialize the OpenTelemetry SDK for the given service.
 * Call this once at application startup, before any other imports.
 *
 * @example
 * // In main.ts / index.ts (FIRST LINE):
 * import { initTracing } from './lib/tracing';
 * initTracing({ serviceName: 'session-service', serviceVersion: '1.0.0' });
 */
export function initTracing(config: TracingConfig): void {
  if (config.disabled || process.env['OTEL_SDK_DISABLED'] === 'true') {
    return;
  }
  if (_sdk) {
    return; // already initialized
  }

  const endpoint = config.otlpEndpoint ?? process.env['OTEL_EXPORTER_OTLP_ENDPOINT'] ?? 'http://otel-collector:4317';

  // Span processors: batch → OTel Collector in production, console in dev
  const processors: SpanProcessor[] = [
    new BatchSpanProcessor(
      new OTLPTraceExporter({ url: endpoint }),
      {
        maxQueueSize: 2048,
        maxExportBatchSize: 512,
        scheduledDelayMillis: 5000,
        exportTimeoutMillis: 30000,
      },
    ),
  ];

  if (process.env['NODE_ENV'] === 'development') {
    processors.push(new SimpleSpanProcessor(new ConsoleSpanExporter()));
  }

  _sdk = new NodeSDK({
    resource: new Resource({
      [SemanticResourceAttributes.SERVICE_NAME]: config.serviceName,
      [SemanticResourceAttributes.SERVICE_VERSION]: config.serviceVersion ?? 'unknown',
      [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: process.env['NODE_ENV'] ?? 'production',
    }),
    contextManager: new AsyncLocalStorageContextManager(),
    textMapPropagator: new CompositePropagator({
      propagators: [
        new W3CTraceContextPropagator(),  // traceparent / tracestate headers
        new W3CBaggagePropagator(),         // baggage header
      ],
    }),
    spanProcessors: processors,
    instrumentations: [
      new HttpInstrumentation({
        // Redact Authorization headers from spans to prevent PII leakage
        headersToRedact: ['authorization', 'cookie', 'set-cookie', 'x-api-key'],
        // Don't trace health check polling — reduces noise
        ignoreIncomingRequestHook: (req) => {
          const url = (req as { url?: string }).url ?? '';
          return url.includes('/health') || url.includes('/metrics') || url.includes('/ready');
        },
      }),
      new PgInstrumentation({
        enhancedDatabaseReporting: false, // don't include query params (PII risk)
        addSqlCommenterCommentToQueries: false,
      }),
      new RedisInstrumentation({
        dbStatementSerializer: (_cmdName, _cmdArgs) => '[REDACTED]', // mask key names / values
      }),
    ],
  });

  _sdk.start();

  // Graceful shutdown
  const shutdown = () => {
    _sdk?.shutdown().catch(() => { /* best-effort */ });
  };
  process.once('SIGTERM', shutdown);
  process.once('SIGINT', shutdown);
}

// ── Tracer factory ────────────────────────────────────────────────────────────

/**
 * Get a named tracer for a module.
 *
 * @example
 * const tracer = getTracer('session-service/auth');
 * const span = tracer.startSpan('validateToken');
 */
export function getTracer(name: string): Tracer {
  return trace.getTracer(name);
}

// ── Trace helper utilities ────────────────────────────────────────────────────

/**
 * Wrap an async function in a span.
 * Automatically records exceptions and sets status.
 *
 * @example
 * const user = await withSpan(tracer, 'db.getUser', { 'user.id': id }, () => db.getUser(id));
 */
export async function withSpan<T>(
  tracer: Tracer,
  name: string,
  attributes: Record<string, string | number | boolean>,
  fn: (span: Span) => Promise<T>,
): Promise<T> {
  return tracer.startActiveSpan(name, { attributes, kind: SpanKind.INTERNAL }, async (span) => {
    try {
      const result = await fn(span);
      span.setStatus({ code: SpanStatusCode.OK });
      return result;
    } catch (err) {
      span.recordException(err instanceof Error ? err : new Error(String(err)));
      span.setStatus({ code: SpanStatusCode.ERROR, message: err instanceof Error ? err.message : String(err) });
      throw err;
    } finally {
      span.end();
    }
  });
}

/**
 * Extract W3C traceparent + tracestate headers from current context.
 * Use when making outgoing HTTP calls to propagate trace context.
 *
 * @example
 * const headers = extractTraceHeaders();
 * await fetch(url, { headers: { ...headers, 'Content-Type': 'application/json' } });
 */
export function extractTraceHeaders(): Record<string, string> {
  const headers: Record<string, string> = {};
  const propagator = new CompositePropagator({
    propagators: [new W3CTraceContextPropagator(), new W3CBaggagePropagator()],
  });
  propagator.inject(context.active(), headers, {
    set: (carrier, key, value) => { (carrier as Record<string, string>)[key] = value; },
  });
  return headers;
}

/**
 * Get the current trace ID (for log correlation).
 * Returns undefined if no active span.
 *
 * @example
 * const log = logger.child({ traceId: currentTraceId() });
 */
export function currentTraceId(): string | undefined {
  const span = trace.getActiveSpan();
  if (!span) return undefined;
  const ctx = span.spanContext();
  return ctx.traceId !== '00000000000000000000000000000000' ? ctx.traceId : undefined;
}

/**
 * Get the current span ID (for log correlation at span level).
 */
export function currentSpanId(): string | undefined {
  const span = trace.getActiveSpan();
  if (!span) return undefined;
  const ctx = span.spanContext();
  return ctx.spanId !== '0000000000000000' ? ctx.spanId : undefined;
}

export { trace, context, SpanStatusCode, SpanKind };
