/**
 * @file        backend/src/middleware/tracing.ts
 * @module      middleware/tracing
 * @description Express middleware for W3C trace context propagation.
 *              Injects X-Trace-Id / X-Span-Id headers from the active OTel span.
 *              Gracefully no-ops when no span is active or OTel is unavailable.
 */

import type { Request, Response, NextFunction } from 'express';
import { trace, SpanStatusCode } from '@opentelemetry/api';

/**
 * Injects X-Trace-Id and X-Span-Id response headers from the active span.
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
    (res as any).locals = (res as any).locals ?? {};
    (res as any).locals['traceId'] = ctx.traceId;
    (res as any).locals['spanId'] = ctx.spanId;
  }
  next();
}

/**
 * Error tracing middleware — record unhandled errors on the active span.
 */
export function errorTracingMiddleware(
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  const span = trace.getActiveSpan();
  if (span) {
    span.recordException(err);
    span.setStatus({ code: SpanStatusCode.ERROR, message: err.message });
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
