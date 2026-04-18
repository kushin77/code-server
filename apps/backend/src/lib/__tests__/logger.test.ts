// @file        backend/src/lib/__tests__/logger.test.ts
// @module      observability
// @description Unit tests for structured logger — PII scrubbing, error fingerprinting,
//              log level filtering, child loggers, and request logging middleware.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { StructuredLogger, fingerprintError, getLogger } from '../logger';

// ── Helpers ───────────────────────────────────────────────────────────────────

function captureStdout(fn: () => void): LogEntry[] {
  const lines: string[] = [];
  const originalWrite = process.stdout.write.bind(process.stdout);
  vi.spyOn(process.stdout, 'write').mockImplementation((chunk) => {
    lines.push(String(chunk).trim());
    return true;
  });
  fn();
  process.stdout.write = originalWrite;
  return lines.filter(Boolean).map((l) => JSON.parse(l) as LogEntry);
}

function captureStderr(fn: () => void): LogEntry[] {
  const lines: string[] = [];
  const originalWrite = process.stderr.write.bind(process.stderr);
  vi.spyOn(process.stderr, 'write').mockImplementation((chunk) => {
    lines.push(String(chunk).trim());
    return true;
  });
  fn();
  process.stderr.write = originalWrite;
  return lines.filter(Boolean).map((l) => JSON.parse(l) as LogEntry);
}

interface LogEntry {
  timestamp: string;
  level: string;
  message: string;
  service: string;
  [key: string]: unknown;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('StructuredLogger', () => {
  let logger: StructuredLogger;

  beforeEach(() => {
    logger = new StructuredLogger('test-service', {}, 'debug');
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('basic logging', () => {
    it('emits valid JSON on info', () => {
      const entries = captureStdout(() => logger.info('hello world'));
      expect(entries).toHaveLength(1);
      expect(entries[0]).toMatchObject({
        level: 'info',
        message: 'hello world',
        service: 'test-service',
      });
    });

    it('includes ISO timestamp', () => {
      const entries = captureStdout(() => logger.info('ts test'));
      expect(entries[0].timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });

    it('emits debug to stdout', () => {
      const entries = captureStdout(() => logger.debug('debug msg'));
      expect(entries[0].level).toBe('debug');
    });

    it('emits error to stderr', () => {
      const entries = captureStderr(() => logger.error('error msg'));
      expect(entries[0].level).toBe('error');
    });

    it('emits warn to stderr', () => {
      const entries = captureStderr(() => logger.warn('warn msg'));
      expect(entries[0].level).toBe('warn');
    });
  });

  describe('log level filtering', () => {
    it('filters debug when minLevel=info', () => {
      const infoLogger = new StructuredLogger('svc', {}, 'info');
      const entries = captureStdout(() => infoLogger.debug('filtered'));
      expect(entries).toHaveLength(0);
    });

    it('passes info when minLevel=info', () => {
      const infoLogger = new StructuredLogger('svc', {}, 'info');
      const entries = captureStdout(() => infoLogger.info('passes'));
      expect(entries).toHaveLength(1);
    });

    it('filters info when minLevel=error', () => {
      const errLogger = new StructuredLogger('svc', {}, 'error');
      const entries = captureStdout(() => errLogger.info('filtered'));
      expect(entries).toHaveLength(0);
    });
  });

  describe('child logger', () => {
    it('inherits parent service name', () => {
      const child = logger.child({ requestId: 'req-123' });
      const entries = captureStdout(() => child.info('from child'));
      expect(entries[0].service).toBe('test-service');
      expect(entries[0].requestId).toBe('req-123');
    });

    it('merges additional context', () => {
      const child1 = logger.child({ traceId: 'trace-1' });
      const child2 = child1.child({ spanId: 'span-1' });
      const entries = captureStdout(() => child2.info('nested'));
      expect(entries[0].traceId).toBe('trace-1');
      expect(entries[0].spanId).toBe('span-1');
    });

    it('does not pollute parent context', () => {
      const child = logger.child({ userId: 'user-1' });
      const parentEntries = captureStdout(() => logger.info('parent'));
      expect(parentEntries[0].userId).toBeUndefined();
    });
  });

  describe('PII scrubbing', () => {
    it('redacts password fields', () => {
      const entries = captureStdout(() =>
        logger.info('login', { password: 'super-secret' }),
      );
      expect(entries[0].password).toBe('[REDACTED]');
    });

    it('redacts token fields', () => {
      const entries = captureStdout(() =>
        logger.info('request', { token: 'abc123' }),
      );
      expect(entries[0].token).toBe('[REDACTED]');
    });

    it('redacts nested secret fields', () => {
      const entries = captureStdout(() =>
        logger.info('config', { db: { password: 'db-pass' } }),
      );
      expect((entries[0].db as Record<string, unknown>)?.password).toBe('[REDACTED]');
    });

    it('redacts bearer tokens in string values', () => {
      const entries = captureStdout(() =>
        logger.info('auth', { header: 'Bearer eyJhbGc.eyJzdWI.SflKx' }),
      );
      expect(entries[0].header).toBe('Bearer [REDACTED]');
    });

    it('redacts email addresses', () => {
      const entries = captureStdout(() =>
        logger.info('user', { contact: 'user@example.com' }),
      );
      expect(entries[0].contact).toBe('[EMAIL-REDACTED]');
    });

    it('preserves non-PII fields', () => {
      const entries = captureStdout(() =>
        logger.info('request', { method: 'GET', statusCode: 200 }),
      );
      expect(entries[0].method).toBe('GET');
      expect(entries[0].statusCode).toBe(200);
    });

    it('does not modify message text (message is not a field name)', () => {
      const entries = captureStdout(() =>
        logger.info('token validated', {}),
      );
      expect(entries[0].message).toBe('token validated');
    });
  });

  describe('error logging', () => {
    it('includes error name and message', () => {
      const err = new TypeError('something went wrong');
      const entries = captureStderr(() => logger.error('caught error', err));
      const errorField = entries[0].error as Record<string, unknown>;
      expect(errorField.name).toBe('TypeError');
      expect(errorField.message).toBe('something went wrong');
    });

    it('includes errorFingerprint', () => {
      const err = new TypeError('something went wrong');
      const entries = captureStderr(() => logger.error('caught error', err));
      expect(entries[0].errorFingerprint).toBeTruthy();
      expect(typeof entries[0].errorFingerprint).toBe('string');
    });

    it('handles non-Error thrown values', () => {
      const entries = captureStderr(() => logger.error('non-error', 'raw string error'));
      expect(entries[0].error).toBe('raw string error');
      expect(entries[0].errorFingerprint).toBeTruthy();
    });
  });

  describe('request logging', () => {
    it('logs HTTP request with method, path, status', () => {
      const entries = captureStdout(() =>
        logger.request('GET', '/api/health', 200, 42),
      );
      const http = entries[0].http as Record<string, unknown>;
      expect(http.method).toBe('GET');
      expect(http.path).toBe('/api/health');
      expect(http.statusCode).toBe(200);
      expect(http.durationMs).toBe(42);
    });

    it('logs 4xx at warn level', () => {
      const entries = captureStderr(() =>
        logger.request('GET', '/api/missing', 404, 10),
      );
      expect(entries[0].level).toBe('warn');
    });

    it('logs 5xx at error level', () => {
      const entries = captureStderr(() =>
        logger.request('POST', '/api/fail', 500, 100),
      );
      expect(entries[0].level).toBe('error');
    });
  });
});

describe('fingerprintError', () => {
  it('returns consistent fingerprint for same error type', () => {
    const err1 = new TypeError('same message');
    const err2 = new TypeError('same message');
    expect(fingerprintError(err1)).toBe(fingerprintError(err2));
  });

  it('returns different fingerprint for different error types', () => {
    const err1 = new TypeError('oops');
    const err2 = new RangeError('oops');
    expect(fingerprintError(err1)).not.toBe(fingerprintError(err2));
  });

  it('handles non-Error values', () => {
    expect(fingerprintError('string error')).toBeTruthy();
    expect(fingerprintError(null)).toBeTruthy();
    expect(typeof fingerprintError(42)).toBe('string');
  });

  it('returns 8-char hex fingerprint', () => {
    const fp = fingerprintError(new Error('test'));
    expect(fp).toMatch(/^[0-9a-f]{8}$/);
  });
});

describe('getLogger', () => {
  it('returns same instance for same service name', () => {
    const a = getLogger('my-service-unique-x9z');
    const b = getLogger('my-service-unique-x9z');
    expect(a).toBe(b);
  });

  it('returns different instances for different services', () => {
    const a = getLogger('service-aaa');
    const b = getLogger('service-bbb');
    expect(a).not.toBe(b);
  });
});
