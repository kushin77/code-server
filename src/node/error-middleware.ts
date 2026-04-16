/**
 * Code-Server Error Handler Integration
 * Integrates ErrorFingerprinter with code-server backend
 * File: src/node/error-middleware.ts
 * Status: Production-ready
 * Date: April 16, 2026
 */

import { Request, Response, NextFunction } from 'express';
import { ErrorFingerprinter } from './error-fingerprinting';
import { Logger } from './logger'; // Existing code-server logger

/**
 * Error fingerprinter instance (singleton)
 */
let errorFingerprinter: ErrorFingerprinter | null = null;

/**
 * Initialize error fingerprinting
 * Call during code-server startup (in app initialization)
 */
export function initializeErrorFingerprinting(logger: Logger): ErrorFingerprinter {
  if (!errorFingerprinter) {
    errorFingerprinter = new ErrorFingerprinter('code-server');
    logger.info('Error fingerprinting initialized');
  }
  return errorFingerprinter;
}

/**
 * Get current fingerprinter instance
 */
export function getErrorFingerprinter(): ErrorFingerprinter {
  if (!errorFingerprinter) {
    throw new Error('Error fingerprinting not initialized');
  }
  return errorFingerprinter;
}

/**
 * Express error handler middleware
 * Catches all errors and fingerprints them
 *
 * Usage in code-server app setup:
 * app.use(createErrorFingerprintingMiddleware(logger));
 */
export function createErrorFingerprintingMiddleware(logger: Logger) {
  return (
    err: any,
    req: Request,
    res: Response,
    next: NextFunction
  ) => {
    if (!errorFingerprinter) {
      next(err);
      return;
    }

    try {
      // Extract error information
      const error = err instanceof Error ? err : new Error(String(err));
      const startTime = (req as any).startTime || Date.now();
      const durationMs = Date.now() - startTime;

      // Extract stack trace info
      const stackLines = (error.stack || '').split('\n');
      const firstStackLine = stackLines[1] || '';
      const fileMatch = firstStackLine.match(/\(?(.*?)(?::\d+)?(?::\d+)?\)?$/);
      const file = fileMatch ? fileMatch[1] : 'unknown';
      const lineMatch = firstStackLine.match(/:(\d+)(?::\d+)?(?:\))?$/);
      const line = lineMatch ? parseInt(lineMatch[1], 10) : 0;

      // Get user ID if authenticated
      const userId = (req as any).user?.id || (req as any).sessionID;

      // Fingerprint the error
      const result = errorFingerprinter.fingerprint(error, {
        file,
        line,
        userId,
        operation: req.path,
        durationMs,
        workspaceId: (req as any).workspaceId,
      });

      // Log structured error
      logger.error('Request error', {
        error_type: error.constructor.name,
        error_message: error.message,
        fingerprint: result.fingerprint,
        normalized_message: result.normalized.errorMessage,
        user_id: userId,
        operation: req.path,
        method: req.method,
        status_code: (res as any).statusCode || 500,
        duration_ms: durationMs,
        file,
        line,
        workspace_id: (req as any).workspaceId,
      });

      // Attach fingerprint to response for tracking
      (res as any).errorFingerprint = result.fingerprint;

      // Continue with default error handling
      next(err);
    } catch (middlewareError) {
      logger.error('Error in error fingerprinting middleware', {
        error: middlewareError instanceof Error ? middlewareError.message : String(middlewareError),
      });
      next(err);
    }
  };
}

/**
 * Metrics endpoint
 * Expose error fingerprinting metrics for Prometheus scraping
 *
 * Usage in code-server app setup:
 * app.get('/metrics/errors', createErrorMetricsEndpoint());
 */
export function createErrorMetricsEndpoint() {
  return (req: Request, res: Response) => {
    if (!errorFingerprinter) {
      res.status(503).json({ error: 'Error fingerprinting not initialized' });
      return;
    }

    try {
      res.set('Content-Type', 'text/plain; version=0.0.4');
      res.send(errorFingerprinter.exportMetrics());
    } catch (err) {
      res.status(500).json({
        error: 'Failed to export metrics',
        message: err instanceof Error ? err.message : String(err),
      });
    }
  };
}

/**
 * Health check endpoint
 * Returns current error fingerprinting statistics
 *
 * Usage in code-server app setup:
 * app.get('/health/errors', createErrorHealthEndpoint());
 */
export function createErrorHealthEndpoint() {
  return (req: Request, res: Response) => {
    if (!errorFingerprinter) {
      res.status(503).json({
        status: 'error',
        message: 'Error fingerprinting not initialized',
      });
      return;
    }

    try {
      const metrics = errorFingerprinter.getMetrics();
      const dedup = metrics.deduplicationRatio;

      // Determine health based on metrics
      let status = 'healthy';
      if (dedup > 0.8) {
        status = 'warning'; // High duplication might indicate systematic issues
      }
      if (metrics.totalErrorCount > 1000) {
        status = 'warning'; // High error count
      }

      res.status(status === 'healthy' ? 200 : 503).json({
        status,
        metrics: {
          total_errors: metrics.totalErrorCount,
          unique_errors: metrics.totalUniqueErrors,
          deduplication_ratio: parseFloat(dedup.toFixed(3)),
          top_errors: metrics.topErrors.slice(0, 5).map((e) => ({
            fingerprint: e.fingerprint,
            error_type: e.errorType,
            count: e.count,
            affected_users: e.affectedUsers.size,
            affected_services: e.affectedServices.size,
          })),
        },
        timestamp: new Date().toISOString(),
      });
    } catch (err) {
      res.status(500).json({
        status: 'error',
        message: err instanceof Error ? err.message : String(err),
      });
    }
  };
}

/**
 * Integration instructions for code-server
 *
 * 1. In src/node/app.ts (during app initialization):
 *
 *    import { initializeErrorFingerprinting, createErrorFingerprintingMiddleware,
 *             createErrorMetricsEndpoint, createErrorHealthEndpoint } from './error-middleware';
 *
 *    // After express app is created
 *    const app = express();
 *    const logger = new Logger();
 *
 *    // Initialize error fingerprinting
 *    initializeErrorFingerprinting(logger);
 *
 *    // Add middleware (after other middleware, before error handlers)
 *    app.use(createErrorFingerprintingMiddleware(logger));
 *
 *    // Expose metrics endpoint for Prometheus
 *    app.get('/metrics/errors', createErrorMetricsEndpoint());
 *
 *    // Expose health check endpoint
 *    app.get('/health/errors', createErrorHealthEndpoint());
 *
 * 2. Configure Prometheus scrape config (in prometheus-error-fingerprinting.yml):
 *
 *    - job_name: 'code-server-errors'
 *      scrape_interval: 15s
 *      static_configs:
 *        - targets: ['localhost:8080']
 *      metrics_path: '/metrics/errors'
 *
 * 3. Configure Loki scrape (in promtail-error-fingerprinting.yml):
 *
 *    - job_name: code-server
 *      static_configs:
 *        - targets:
 *            - localhost
 *          labels:
 *            job: code-server
 *            service: code-server
 *
 * 4. Testing error fingerprinting (in development):
 *
 *    curl http://localhost:8080/health/errors
 *    curl http://localhost:8080/metrics/errors
 */

export default {
  initializeErrorFingerprinting,
  getErrorFingerprinter,
  createErrorFingerprintingMiddleware,
  createErrorMetricsEndpoint,
  createErrorHealthEndpoint,
};
