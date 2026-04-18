/**
 * @file        backend/src/middleware/tracing.ts
 * @module      middleware/tracing
 * @description Express middleware for W3C trace context propagation.
 *              Injects trace/span IDs into response headers and request log context.
 *              Compatible with the StructuredLogger from lib/logger.ts (traceId field).
 */

import type { Request, Response, NextFunction } from 'express';
import { trace, SpanStatusCode } from '@opentelemetry/api';

/**
 * Injects X-Trace-Id and X-Span-Id response headers from the active span.
 * Also attaches traceId + spanId to res.locals for downstream use by logger.
 *
 * Must be registered after tracer.ts is imported (SDK must be started first).
 */
export function tracingMiddleware(
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  const span = trace.getActiveSpan();
  if (span) {
    const ctx = span.spanContext();
    res.setHeader('X-Trace-Id', ctx.traceId);
    res.setHeader('X-Span-Id', ctx.spanId);
    res.locals['traceId'] = ctx.traceId;
    res.locals['spanId'] = ctx.spanId;
  }
  next();
}

/**
 * Error tracing middleware — record unhandled errors on the active span
 * before passing to the next error handler.
 */
export function errorTracingMiddleware(
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  const span = trace.getActiveSpan();
  if (span) {
    span.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
    span.recordException(err);
  }
  next(err);
}

/**
 * Extract trace context helper — returns traceId/spanId for the current
 * active span, or undefined if no span is active.
 */
export function getCurrentTraceContext(): { traceId: string; spanId: string } | undefined {
  const span = trace.getActiveSpan();
  if (!span) return undefined;
  const ctx = span.spanContext();
  return { traceId: ctx.traceId, spanId: ctx.spanId };
}
