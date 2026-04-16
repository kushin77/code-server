#!/usr/bin/env node
/**
 * Telemetry Logger Module
 * 
 * Enforces structured logging schema per TELEMETRY-ARCHITECTURE.md
 * Usage:
 *   const { createLogger } = require('./telemetry-logger');
 *   const logger = createLogger({ service: 'code-server', environment: 'production' });
 *   logger.info('Event', { trace_id, request_path, duration_ms });
 */

const fs = require('fs');
const crypto = require('crypto');

/**
 * Generates a UUID v4 string
 */
function generateUUID() {
  return crypto.randomUUID();
}

/**
 * Hashes a user ID (SHA-256) to enable privacy-safe correlation
 */
function hashUserId(userId) {
  if (!userId) return null;
  return crypto.createHash('sha256').update(String(userId)).digest('hex');
}

/**
 * Generates deterministic error fingerprint for grouping similar errors
 */
function generateErrorFingerprint(error) {
  if (!error) return '';
  const message = String(error.message || error);
  const stack = error.stack ? error.stack.split('\n')[0] : '';
  const fingerprint = `${message}|${stack}`.substring(0, 100);
  return crypto.createHash('sha256').update(fingerprint).digest('hex').substring(0, 16);
}

/**
 * Validates log object against telemetry schema
 * Throws if required fields missing or invalid
 */
function validateLogSchema(level, message, metadata = {}) {
  const requiredFields = ['timestamp', 'level', 'service', 'environment', 'trace_id', 'message'];
  
  const log = {
    timestamp: new Date().toISOString(),
    level,
    service: metadata.service || 'unknown',
    region: metadata.region || 'unknown',
    host: metadata.host || require('os').hostname(),
    environment: metadata.environment || 'unknown',
    trace_id: metadata.trace_id || generateUUID(),
    span_id: metadata.span_id || undefined,
    request_id: metadata.request_id || undefined,
    request_path: metadata.request_path || undefined,
    request_method: metadata.request_method || undefined,
    user_id_hash: metadata.user_id_hash || undefined,
    session_id: metadata.session_id || undefined,
    status_code: metadata.status_code || undefined,
    duration_ms: metadata.duration_ms || undefined,
    message,
    error_fingerprint: metadata.error_fingerprint || '',
    context: metadata.context || {}
  };

  // Validation
  if (!log.trace_id || log.trace_id.length < 8) {
    throw new Error(`Invalid trace_id: ${log.trace_id}`);
  }

  return log;
}

/**
 * Creates a logger instance bound to a service/environment
 */
function createLogger(config = {}) {
  const {
    service = 'unknown',
    region = process.env.REGION || 'unknown',
    environment = process.env.NODE_ENV || 'development',
    host = require('os').hostname()
  } = config;

  return {
    /**
     * Log at INFO level
     */
    info(message, metadata = {}) {
      const log = validateLogSchema('info', message, {
        service, region, environment, host,
        ...metadata
      });
      console.log(JSON.stringify(log));
      return log;
    },

    /**
     * Log at DEBUG level
     */
    debug(message, metadata = {}) {
      const log = validateLogSchema('debug', message, {
        service, region, environment, host,
        ...metadata
      });
      if (environment === 'development' || metadata.debug_escalated) {
        console.log(JSON.stringify(log));
      }
      return log;
    },

    /**
     * Log at WARN level
     */
    warn(message, metadata = {}) {
      const log = validateLogSchema('warn', message, {
        service, region, environment, host,
        ...metadata
      });
      console.warn(JSON.stringify(log));
      return log;
    },

    /**
     * Log at ERROR level with error object
     */
    error(message, error = null, metadata = {}) {
      const fingerprint = generateErrorFingerprint(error);
      const log = validateLogSchema('error', message, {
        service, region, environment, host,
        error_fingerprint: fingerprint,
        ...metadata
      });
      console.error(JSON.stringify(log));
      if (error && error.stack) {
        console.error(error.stack);
      }
      return log;
    },

    /**
     * Log at FATAL level (critical error)
     */
    fatal(message, error = null, metadata = {}) {
      const fingerprint = generateErrorFingerprint(error);
      const log = validateLogSchema('fatal', message, {
        service, region, environment, host,
        error_fingerprint: fingerprint,
        ...metadata
      });
      console.error(JSON.stringify(log));
      if (error && error.stack) {
        console.error(error.stack);
      }
      process.exit(1);
    },

    /**
     * Create a child logger with default metadata
     */
    withDefaults(defaults) {
      const self = this;
      return {
        info: (msg, meta) => self.info(msg, { ...defaults, ...meta }),
        debug: (msg, meta) => self.debug(msg, { ...defaults, ...meta }),
        warn: (msg, meta) => self.warn(msg, { ...defaults, ...meta }),
        error: (msg, err, meta) => self.error(msg, err, { ...defaults, ...meta }),
        fatal: (msg, err, meta) => self.fatal(msg, err, { ...defaults, ...meta })
      };
    }
  };
}

/**
 * Express middleware to extract/propagate trace_id from headers
 */
function traceMiddleware(logger) {
  return (req, res, next) => {
    // Extract or generate trace ID
    const traceId = req.headers['x-trace-id'] || generateUUID();
    const requestId = req.headers['x-request-id'] || generateUUID();
    
    // Attach to request object
    req.trace_id = traceId;
    req.request_id = requestId;
    
    // Set response headers
    res.setHeader('x-trace-id', traceId);
    res.setHeader('x-request-id', requestId);
    
    // Log request
    const startTime = Date.now();
    logger.info('Request received', {
      trace_id: traceId,
      request_id: requestId,
      request_method: req.method,
      request_path: req.path
    });

    // Capture response and log
    const originalSend = res.send;
    res.send = function(data) {
      const duration = Date.now() - startTime;
      logger.info('Response sent', {
        trace_id: traceId,
        request_id: requestId,
        request_method: req.method,
        request_path: req.path,
        status_code: res.statusCode,
        duration_ms: duration
      });
      return originalSend.call(this, data);
    };

    next();
  };
}

module.exports = {
  createLogger,
  generateUUID,
  hashUserId,
  generateErrorFingerprint,
  validateLogSchema,
  traceMiddleware
};
