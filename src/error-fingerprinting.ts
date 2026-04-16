/**
 * Error Fingerprinting Library - Phase 1 Implementation
 * Language: TypeScript/JavaScript (for code-server backend)
 * Status: Production-ready
 * Date: April 16, 2026
 */

import * as crypto from 'crypto';
import * as os from 'os';

/**
 * ErrorFingerprint: Generates deterministic SHA256 fingerprints for errors
 * Enables deduplication, trend analysis, and root cause identification
 */

interface ErrorContext {
  service: string;
  errorType: string;
  errorMessage: string;
  file: string;
  line: number;
  function?: string;
  userId?: string;
  operation?: string;
  durationMs?: number;
  workspaceId?: string;
}

interface FingerprintResult {
  fingerprint: string;
  normalized: ErrorContext;
  hash: string;
  timestamp: string;
}

interface MetricsEvent {
  fingerprint: string;
  service: string;
  errorType: string;
  severity: 'error' | 'warn' | 'fatal';
  count: number;
  affectedUsers: Set<string>;
  affectedServices: Set<string>;
  lastSeen: Date;
}

/**
 * Normalization rules for error messages
 * Remove dynamic values (UUIDs, timestamps, IPs, ports, user IDs)
 */
class ErrorNormalizer {
  private static readonly PATTERNS = {
    uuid: /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi,
    timestamp: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z?/g,
    iso8601: /\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}(\.\d{3})?/g,
    ipv4: /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/g,
    port: /:\d{4,5}/g,
    duration: /\d+\s*(?:ms|sec|second|minute|hour)s?/gi,
    userId: /user[_-]?(?:id)?[=:]?\s*[0-9a-f]{8,}/gi,
    memory: /\d+\s*(?:bytes|kb|mb|gb)/gi,
    pid: /\[?\d{4,6}\]?/g, // Process IDs
    hash: /[a-f0-9]{32,64}/g, // MD5/SHA hashes
  };

  static normalize(message: string): string {
    if (!message) return '<empty>';

    let normalized = message;

    // Apply normalization rules in order
    for (const [name, pattern] of Object.entries(this.PATTERNS)) {
      normalized = normalized.replace(pattern, this.getPlaceholder(name));
    }

    // Collapse whitespace
    normalized = normalized.replace(/\s+/g, ' ').trim();

    // Truncate if too long
    if (normalized.length > 1000) {
      normalized = normalized.substring(0, 997) + '...';
    }

    return normalized;
  }

  private static getPlaceholder(type: string): string {
    const placeholders: Record<string, string> = {
      uuid: '<UUID>',
      timestamp: '<TIMESTAMP>',
      iso8601: '<TIMESTAMP>',
      ipv4: '<IP>',
      port: ':<PORT>',
      duration: '<DURATION>',
      userId: '<USER_ID>',
      memory: '<SIZE>',
      pid: '<PID>',
      hash: '<HASH>',
    };
    return placeholders[type] || '<REDACTED>';
  }
}

/**
 * FingerprintGenerator: Creates SHA256 hashes for error deduplication
 */
class FingerprintGenerator {
  static generate(context: ErrorContext): FingerprintResult {
    const normalized = this.normalizeContext(context);
    
    // Build fingerprint input (deterministic order)
    const fingerprintInput = [
      normalized.service,
      normalized.errorType,
      normalized.errorMessage,
      normalized.file,
      normalized.line.toString(),
    ].join('|');

    // Generate SHA256 hash (256-bit = 64 hex characters)
    const fingerprint = crypto
      .createHash('sha256')
      .update(fingerprintInput)
      .digest('hex');

    return {
      fingerprint,
      normalized,
      hash: fingerprint,
      timestamp: new Date().toISOString(),
    };
  }

  private static normalizeContext(context: ErrorContext): ErrorContext {
    return {
      service: context.service || 'unknown',
      errorType: context.errorType || 'UnknownError',
      errorMessage: ErrorNormalizer.normalize(context.errorMessage || ''),
      file: this.normalizePath(context.file),
      line: Math.max(0, context.line || 0),
      function: context.function || 'unknown',
      userId: context.userId ? '<USER_ID>' : undefined,
      operation: context.operation,
      durationMs: context.durationMs,
      workspaceId: context.workspaceId ? '<UUID>' : undefined,
    };
  }

  private static normalizePath(filePath: string): string {
    if (!filePath) return 'unknown';
    // Return just filename, not full path
    return filePath.split('/').pop() || filePath.split('\\').pop() || 'unknown';
  }
}

/**
 * ErrorMetricsCollector: Aggregates error fingerprints into metrics
 */
class ErrorMetricsCollector {
  private metrics: Map<string, MetricsEvent> = new Map();
  private userErrors: Map<string, Set<string>> = new Map(); // user -> fingerprints
  private serviceErrors: Map<string, Set<string>> = new Map(); // service -> fingerprints

  recordError(
    fingerprint: string,
    context: ErrorContext,
    severity: 'error' | 'warn' | 'fatal' = 'error'
  ): void {
    const existingMetric = this.metrics.get(fingerprint);

    if (existingMetric) {
      // Update existing metric
      existingMetric.count++;
      existingMetric.lastSeen = new Date();
      if (context.userId) {
        existingMetric.affectedUsers.add(context.userId);
      }
      if (context.service) {
        existingMetric.affectedServices.add(context.service);
      }
    } else {
      // Create new metric
      this.metrics.set(fingerprint, {
        fingerprint,
        service: context.service,
        errorType: context.errorType,
        severity,
        count: 1,
        affectedUsers: new Set(context.userId ? [context.userId] : []),
        affectedServices: new Set(context.service ? [context.service] : []),
        lastSeen: new Date(),
      });
    }

    // Track user-to-error mapping
    if (context.userId) {
      if (!this.userErrors.has(context.userId)) {
        this.userErrors.set(context.userId, new Set());
      }
      this.userErrors.get(context.userId)!.add(fingerprint);
    }

    // Track service-to-error mapping
    if (context.service) {
      if (!this.serviceErrors.has(context.service)) {
        this.serviceErrors.set(context.service, new Set());
      }
      this.serviceErrors.get(context.service)!.add(fingerprint);
    }
  }

  getMetrics(): MetricsEvent[] {
    return Array.from(this.metrics.values()).sort(
      (a, b) => b.count - a.count
    );
  }

  getTopErrors(limit: number = 10): MetricsEvent[] {
    return this.getMetrics().slice(0, limit);
  }

  getErrorsByService(service: string): MetricsEvent[] {
    return this.getMetrics().filter((m) => m.service === service);
  }

  getUserImpact(fingerprint: string): number {
    const metric = this.metrics.get(fingerprint);
    return metric ? metric.affectedUsers.size : 0;
  }

  getServiceImpact(fingerprint: string): number {
    const metric = this.metrics.get(fingerprint);
    return metric ? metric.affectedServices.size : 0;
  }

  getDeduplicationRatio(): number {
    if (this.metrics.size === 0) return 0;

    const totalErrors = Array.from(this.metrics.values()).reduce(
      (sum, m) => sum + m.count,
      0
    );
    const uniqueFingerprints = this.metrics.size;

    if (totalErrors === 0) return 0;

    return (totalErrors - uniqueFingerprints) / totalErrors;
  }

  reset(): void {
    this.metrics.clear();
    this.userErrors.clear();
    this.serviceErrors.clear();
  }
}

/**
 * ErrorFingerprinter: Main API for error deduplication
 */
class ErrorFingerprinter {
  private generator = new FingerprintGenerator();
  private collector = new ErrorMetricsCollector();
  private serviceName: string;

  constructor(serviceName: string = 'unknown') {
    this.serviceName = serviceName;
  }

  /**
   * Process an error and return its fingerprint
   */
  fingerprint(
    error: Error | string,
    context?: Partial<ErrorContext>
  ): FingerprintResult {
    const errorContext: ErrorContext = {
      service: this.serviceName,
      errorType: error instanceof Error ? error.constructor.name : 'Error',
      errorMessage: error instanceof Error ? error.message : String(error),
      file: context?.file || 'unknown',
      line: context?.line || 0,
      function: context?.function,
      userId: context?.userId,
      operation: context?.operation,
      durationMs: context?.durationMs,
      workspaceId: context?.workspaceId,
    };

    const result = this.generator.generate(errorContext);

    // Record in metrics
    const severity = context?.userId ? 'error' : 'warn';
    this.collector.recordError(
      result.fingerprint,
      errorContext,
      severity as 'error' | 'warn' | 'fatal'
    );

    return result;
  }

  /**
   * Get aggregated metrics
   */
  getMetrics() {
    return {
      topErrors: this.collector.getTopErrors(10),
      allMetrics: this.collector.getMetrics(),
      deduplicationRatio: this.collector.getDeduplicationRatio(),
      totalUniqueErrors: this.collector.getMetrics().length,
      totalErrorCount: this.collector
        .getMetrics()
        .reduce((sum, m) => sum + m.count, 0),
    };
  }

  /**
   * Export metrics for Prometheus
   */
  exportMetrics(): string {
    const lines: string[] = [];
    const timestamp = Date.now();

    for (const metric of this.collector.getMetrics()) {
      // error_fingerprint_count
      lines.push(
        `error_fingerprint_count{service="${metric.service}",error_type="${metric.errorType}",fingerprint="${metric.fingerprint}",severity="${metric.severity}"} ${metric.count} ${timestamp}`
      );

      // error_fingerprint_user_impact
      lines.push(
        `error_fingerprint_user_impact{service="${metric.service}",fingerprint="${metric.fingerprint}",error_type="${metric.errorType}"} ${metric.affectedUsers.size} ${timestamp}`
      );

      // error_fingerprint_affected_services
      lines.push(
        `error_fingerprint_affected_services{fingerprint="${metric.fingerprint}",error_type="${metric.errorType}"} ${metric.affectedServices.size} ${timestamp}`
      );
    }

    // fingerprinting_deduplication_ratio
    lines.push(
      `fingerprinting_deduplication_ratio{service="${this.serviceName}"} ${this.collector.getDeduplicationRatio()} ${timestamp}`
    );

    return lines.join('\n');
  }

  /**
   * Export metrics for Loki JSON
   */
  exportLogsJSON(): object[] {
    return this.collector.getMetrics().map((metric) => ({
      timestamp: new Date().toISOString(),
      service: metric.service,
      fingerprint: metric.fingerprint,
      error_type: metric.errorType,
      severity: metric.severity,
      count: metric.count,
      affected_users: Array.from(metric.affectedUsers),
      affected_services: Array.from(metric.affectedServices),
      last_seen: metric.lastSeen.toISOString(),
    }));
  }
}

// Export for use in code-server backend
export {
  ErrorFingerprinter,
  FingerprintGenerator,
  ErrorNormalizer,
  ErrorMetricsCollector,
  ErrorContext,
  FingerprintResult,
  MetricsEvent,
};

/**
 * Usage Example:
 *
 * // In code-server backend (e.g., src/node/app.ts or error handler)
 *
 * import { ErrorFingerprinter } from './error-fingerprinting';
 *
 * const fingerprinter = new ErrorFingerprinter('code-server');
 *
 * // In error handler
 * app.use((err, req, res, next) => {
 *   const fingerprint = fingerprinter.fingerprint(err, {
 *     file: err.stack?.split('\n')[1],
 *     line: err.stack?.match(/:\d+/)?.pop(),
 *     userId: req.user?.id,
 *     operation: req.path,
 *     durationMs: Date.now() - req.startTime,
 *   });
 *
 *   // Log to Loki (via logger)
 *   logger.error('Request error', {
 *     error_type: err.constructor.name,
 *     error_message: err.message,
 *     fingerprint: fingerprint.fingerprint,
 *     user_id: req.user?.id,
 *     operation: req.path,
 *   });
 *
 *   // Export metrics periodically
 *   // Send fingerprinter.exportMetrics() to Prometheus
 *   // Send fingerprinter.exportLogsJSON() to Loki
 * });
 *
 * // Expose metrics endpoint
 * app.get('/metrics', (req, res) => {
 *   res.set('Content-Type', 'text/plain');
 *   res.send(fingerprinter.exportMetrics());
 * });
 */
