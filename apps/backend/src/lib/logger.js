// @file        backend/src/lib/logger.ts
// @module      observability
// @description Structured JSON logger with correlation ID propagation, PII scrubbing,
//              error fingerprinting, and Loki-compatible output for all services.
// @owner       platform
// @status      active
import { createHash } from 'node:crypto';
// ── PII scrubbing ─────────────────────────────────────────────────────────────
/** Fields whose values are always redacted (case-insensitive key match). */
const PII_FIELD_PATTERNS = [
    /password/i,
    /secret/i,
    /token/i,
    /auth/i,
    /cookie/i,
    /session/i,
    /credential/i,
    /private_?key/i,
    /api_?key/i,
    /bearer/i,
];
/** Inline patterns redacted from string values. */
const PII_VALUE_PATTERNS = [
    // JWT bearer tokens
    { pattern: /Bearer\s+[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+/g, replacement: 'Bearer [REDACTED]' },
    // Email addresses
    { pattern: /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g, replacement: '[EMAIL-REDACTED]' },
    // IPv4 user addresses (not internal ranges)
    { pattern: /\b(?!192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/g, replacement: '[IP-REDACTED]' },
];
function scrubPII(obj, depth = 0) {
    if (depth > 10)
        return obj; // prevent infinite recursion
    if (obj === null || obj === undefined)
        return obj;
    if (typeof obj === 'string') {
        let v = obj;
        for (const { pattern, replacement } of PII_VALUE_PATTERNS) {
            v = v.replace(pattern, replacement);
        }
        return v;
    }
    if (Array.isArray(obj)) {
        return obj.map((item) => scrubPII(item, depth + 1));
    }
    if (typeof obj === 'object') {
        const result = {};
        for (const [key, value] of Object.entries(obj)) {
            if (PII_FIELD_PATTERNS.some((p) => p.test(key))) {
                result[key] = '[REDACTED]';
            }
            else {
                result[key] = scrubPII(value, depth + 1);
            }
        }
        return result;
    }
    return obj;
}
// ── Error fingerprinting ──────────────────────────────────────────────────────
/**
 * Creates a stable fingerprint for an error based on its type and normalized stack trace.
 * Allows grouping of identical errors across instances and over time.
 */
export function fingerprintError(err) {
    if (!(err instanceof Error)) {
        return createHash('sha1').update(String(err)).digest('hex').slice(0, 8);
    }
    // Normalize stack: strip line numbers to group same-type errors regardless of version
    const normalizedStack = (err.stack ?? err.message)
        .replace(/:\d+:\d+/g, '') // strip line:col numbers
        .replace(/\/[^\s]+\//g, '/') // strip full paths, keep filenames
        .slice(0, 500);
    const fingerprint = createHash('sha1')
        .update(`${err.constructor.name}:${normalizedStack}`)
        .digest('hex')
        .slice(0, 8);
    return fingerprint;
}
// ── Logger class ──────────────────────────────────────────────────────────────
export class StructuredLogger {
    constructor(service, context = {}, minLevel = 'info') {
        this.service = service;
        this.baseContext = context;
        this.minLevel = process.env['LOG_LEVEL'] ?? minLevel;
    }
    /** Create a child logger with additional context fields merged in. */
    child(additionalContext) {
        return new StructuredLogger(this.service, { ...this.baseContext, ...additionalContext }, this.minLevel);
    }
    debug(message, fields) {
        this.write('debug', message, fields);
    }
    info(message, fields) {
        this.write('info', message, fields);
    }
    warn(message, fields) {
        this.write('warn', message, fields);
    }
    error(message, err, fields) {
        const errorFields = {};
        if (err instanceof Error) {
            errorFields['error'] = {
                name: err.name,
                message: err.message,
                stack: err.stack,
            };
            errorFields['errorFingerprint'] = fingerprintError(err);
        }
        else if (err !== undefined) {
            errorFields['error'] = String(err);
            errorFields['errorFingerprint'] = fingerprintError(err);
        }
        this.write('error', message, { ...errorFields, ...fields });
    }
    /** Log a request with duration (intended for HTTP middleware). */
    request(method, path, statusCode, durationMs, fields) {
        const level = statusCode >= 500 ? 'error' : statusCode >= 400 ? 'warn' : 'info';
        this.write(level, `${method} ${path} ${statusCode}`, {
            http: { method, path, statusCode, durationMs },
            durationMs,
            ...fields,
        });
    }
    write(level, message, fields) {
        if (StructuredLogger.LEVEL_ORDER[level] < StructuredLogger.LEVEL_ORDER[this.minLevel]) {
            return;
        }
        const entry = {
            timestamp: new Date().toISOString(),
            level,
            message,
            service: this.service,
            ...this.baseContext,
            ...(fields ? scrubPII(fields) : {}),
        };
        // Output as newline-delimited JSON (Loki / Promtail compatible)
        const line = JSON.stringify(entry);
        if (level === 'error' || level === 'warn') {
            process.stderr.write(line + '\n');
        }
        else {
            process.stdout.write(line + '\n');
        }
    }
}
StructuredLogger.LEVEL_ORDER = {
    debug: 0,
    info: 1,
    warn: 2,
    error: 3,
};
// ── Express/Node HTTP middleware ──────────────────────────────────────────────
/**
 * Express-compatible logging middleware.
 * Injects a request-scoped logger and logs completed requests.
 *
 * @example
 * app.use(requestLogger(logger));
 */
export function requestLogger(logger) {
    return function loggingMiddleware(req, res, next) {
        const start = Date.now();
        const requestId = req.headers['x-request-id'] ?? crypto.randomUUID();
        const traceId = req.headers['x-trace-id'] ?? crypto.randomUUID();
        // Attach request-scoped child logger
        req.log = logger.child({ requestId, traceId });
        res.on('finish', () => {
            logger.request(req.method, req.path, res.statusCode, Date.now() - start, {
                requestId,
                traceId,
            });
        });
        next();
    };
}
// ── Singleton factory ─────────────────────────────────────────────────────────
const loggers = new Map();
/**
 * Get or create a named service logger (singleton per service name).
 *
 * @example
 * const log = getLogger('session-service');
 * log.info('Session created', { sessionId });
 */
export function getLogger(service, context) {
    const existing = loggers.get(service);
    if (existing)
        return existing;
    const logger = new StructuredLogger(service, context);
    loggers.set(service, logger);
    return logger;
}
/** Default application logger. */
export const logger = getLogger('code-server-enterprise');
//# sourceMappingURL=logger.js.map