/**
 * @file        backend/src/lib/tracer.ts
 * @module      observability/tracer-compat
 * @description Backward-compatible wrapper over the canonical tracing module.
 *              New code should import from ./tracing.
 */

export {
  initTracing,
  getTracer,
  withSpan,
  extractTraceHeaders,
  currentTraceId,
  currentSpanId,
  trace,
  context,
  SpanStatusCode,
  SpanKind,
} from './tracing';
