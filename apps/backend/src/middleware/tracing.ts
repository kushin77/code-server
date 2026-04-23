/**
 * @file        backend/src/middleware/tracing.ts
 * @module      middleware/tracing
 * @description Express middleware for W3C trace context propagation.
 *              No-op implementation when OTel is unavailable.
 */

import type { Request, Response, NextFunction } from 'express';

/**
 * Injects X-Trace-Id and X-Span-Id response headers from the active span.
 * No-op implementation for test environments.
 */
export function tracingMiddleware(
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  // No-op: OTel not available in test environment
  next();
}

/**
 * Error tracing middleware — record unhandled errors on the active span
 * No-op implementation for test environments.
 */
export function errorTracingMiddleware(
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  // No-op: OTel not available in test environment
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
