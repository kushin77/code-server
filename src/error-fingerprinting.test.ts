/**
 * Error Fingerprinting - Unit Tests
 * Test Suite: Error deduplication, normalization, metrics collection
 * Status: Production test coverage
 * Date: April 16, 2026
 */

import {
  ErrorFingerprinter,
  FingerprintGenerator,
  ErrorNormalizer,
  ErrorMetricsCollector,
} from './error-fingerprinting';

describe('ErrorNormalizer', () => {
  describe('normalize()', () => {
    test('removes UUIDs', () => {
      const message = 'Failed to load workspace 550e8400-e29b-41d4-a716-446655440000';
      const normalized = ErrorNormalizer.normalize(message);
      expect(normalized).not.toContain('550e8400');
      expect(normalized).toContain('<UUID>');
    });

    test('removes timestamps', () => {
      const message = 'Timeout occurred at 2026-04-16T10:30:45.123Z';
      const normalized = ErrorNormalizer.normalize(message);
      expect(normalized).not.toContain('2026-04-16');
      expect(normalized).toContain('<TIMESTAMP>');
    });

    test('removes IPv4 addresses', () => {
      const message = 'Connection refused to 192.168.1.100';
      const normalized = ErrorNormalizer.normalize(message);
      expect(normalized).not.toContain('192.168.1.100');
      expect(normalized).toContain('<IP>');
    });

    test('removes port numbers', () => {
      const message = 'Failed to connect to localhost:5432';
      const normalized = ErrorNormalizer.normalize(message);
      expect(normalized).not.toContain(':5432');
      expect(normalized).toContain(':<PORT>');
    });

    test('normalizes complex error message', () => {
      const message =
        'Database connection to 192.168.1.100:5432 failed at 2026-04-16T10:30:45Z for user 550e8400-e29b-41d4-a716-446655440000';
      const normalized = ErrorNormalizer.normalize(message);

      expect(normalized).toContain('<IP>');
      expect(normalized).toContain(':<PORT>');
      expect(normalized).toContain('<TIMESTAMP>');
      expect(normalized).toContain('<UUID>');
      expect(normalized).not.toMatch(/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/);
    });

    test('handles empty string', () => {
      const normalized = ErrorNormalizer.normalize('');
      expect(normalized).toBe('<empty>');
    });

    test('truncates long messages', () => {
      const longMessage = 'a'.repeat(1500);
      const normalized = ErrorNormalizer.normalize(longMessage);
      expect(normalized.length).toBeLessThanOrEqual(1000);
      expect(normalized).toContain('...');
    });

    test('collapses whitespace', () => {
      const message = 'Error  \n\n   with   multiple   spaces';
      const normalized = ErrorNormalizer.normalize(message);
      expect(normalized).toBe('Error with multiple spaces');
    });
  });
});

describe('FingerprintGenerator', () => {
  describe('generate()', () => {
    test('generates consistent fingerprints for same error', () => {
      const context1 = {
        service: 'code-server',
        errorType: 'PostgreSQL::ConnectionError',
        errorMessage: 'Connection timeout after 5000ms',
        file: 'db.ts',
        line: 42,
      };

      const result1 = FingerprintGenerator.generate(context1);
      const result2 = FingerprintGenerator.generate(context1);

      expect(result1.fingerprint).toBe(result2.fingerprint);
    });

    test('generates different fingerprints for different error types', () => {
      const context1 = {
        service: 'code-server',
        errorType: 'PostgreSQL::ConnectionError',
        errorMessage: 'Connection timeout',
        file: 'db.ts',
        line: 42,
      };

      const context2 = {
        service: 'code-server',
        errorType: 'PostgreSQL::TimeoutError',
        errorMessage: 'Connection timeout',
        file: 'db.ts',
        line: 42,
      };

      const result1 = FingerprintGenerator.generate(context1);
      const result2 = FingerprintGenerator.generate(context2);

      expect(result1.fingerprint).not.toBe(result2.fingerprint);
    });

    test('generates 64-character hex fingerprint (SHA256)', () => {
      const context = {
        service: 'code-server',
        errorType: 'Error',
        errorMessage: 'Test error',
        file: 'test.ts',
        line: 1,
      };

      const result = FingerprintGenerator.generate(context);

      expect(result.fingerprint).toMatch(/^[a-f0-9]{64}$/);
      expect(result.hash).toMatch(/^[a-f0-9]{64}$/);
      expect(result.fingerprint).toBe(result.hash);
    });

    test('normalizes dynamic values before fingerprinting', () => {
      const context1 = {
        service: 'code-server',
        errorType: 'Error',
        errorMessage: 'Failed to load workspace 550e8400-e29b-41d4-a716-446655440000',
        file: 'loader.ts',
        line: 10,
      };

      const context2 = {
        service: 'code-server',
        errorType: 'Error',
        errorMessage: 'Failed to load workspace aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        file: 'loader.ts',
        line: 10,
      };

      const result1 = FingerprintGenerator.generate(context1);
      const result2 = FingerprintGenerator.generate(context2);

      // Both should normalize UUID to <UUID>, resulting in identical fingerprints
      expect(result1.fingerprint).toBe(result2.fingerprint);
    });

    test('normalizes file paths (basename only)', () => {
      const context1 = {
        service: 'code-server',
        errorType: 'Error',
        errorMessage: 'Error',
        file: '/home/user/project/src/db.ts',
        line: 42,
      };

      const context2 = {
        service: 'code-server',
        errorType: 'Error',
        errorMessage: 'Error',
        file: 'db.ts',
        line: 42,
      };

      const result1 = FingerprintGenerator.generate(context1);
      const result2 = FingerprintGenerator.generate(context2);

      // Both should normalize to basename 'db.ts'
      expect(result1.fingerprint).toBe(result2.fingerprint);
    });

    test('includes timestamp in result', () => {
      const context = {
        service: 'code-server',
        errorType: 'Error',
        errorMessage: 'Test',
        file: 'test.ts',
        line: 1,
      };

      const result = FingerprintGenerator.generate(context);
      expect(result.timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    });
  });
});

describe('ErrorMetricsCollector', () => {
  let collector: ErrorMetricsCollector;

  beforeEach(() => {
    collector = new ErrorMetricsCollector();
  });

  describe('recordError()', () => {
    test('creates new metric for first error', () => {
      const fingerprint = 'abc123';
      const context = {
        service: 'code-server',
        errorType: 'Error',
        errorMessage: 'Test',
        file: 'test.ts',
        line: 1,
      };

      collector.recordError(fingerprint, context, 'error');

      const metrics = collector.getMetrics();
      expect(metrics).toHaveLength(1);
      expect(metrics[0].fingerprint).toBe(fingerprint);
      expect(metrics[0].count).toBe(1);
    });

    test('increments count for duplicate fingerprints', () => {
      const fingerprint = 'abc123';
      const context = {
        service: 'code-server',
        errorType: 'Error',
        errorMessage: 'Test',
        file: 'test.ts',
        line: 1,
      };

      collector.recordError(fingerprint, context, 'error');
      collector.recordError(fingerprint, context, 'error');
      collector.recordError(fingerprint, context, 'error');

      const metrics = collector.getMetrics();
      expect(metrics[0].count).toBe(3);
    });

    test('tracks affected users', () => {
      const fingerprint = 'abc123';
      const context1 = {
        service: 'code-server',
        errorType: 'Error',
        errorMessage: 'Test',
        file: 'test.ts',
        line: 1,
        userId: 'user1',
      };

      const context2 = {
        ...context1,
        userId: 'user2',
      };

      collector.recordError(fingerprint, context1, 'error');
      collector.recordError(fingerprint, context2, 'error');

      const metrics = collector.getMetrics();
      expect(metrics[0].affectedUsers.size).toBe(2);
      expect(metrics[0].affectedUsers).toContain('user1');
      expect(metrics[0].affectedUsers).toContain('user2');
    });

    test('tracks affected services', () => {
      const fingerprint = 'abc123';
      const context1 = {
        service: 'code-server',
        errorType: 'Error',
        errorMessage: 'Test',
        file: 'test.ts',
        line: 1,
      };

      const context2 = {
        ...context1,
        service: 'api-server',
      };

      collector.recordError(fingerprint, context1, 'error');
      collector.recordError(fingerprint, context2, 'error');

      const metrics = collector.getMetrics();
      expect(metrics[0].affectedServices.size).toBe(2);
    });
  });

  describe('getTopErrors()', () => {
    test('returns top N errors by count', () => {
      collector.recordError('fp1', {
        service: 'code-server',
        errorType: 'Error1',
        errorMessage: 'E1',
        file: 'test.ts',
        line: 1,
      });
      collector.recordError('fp1', {
        service: 'code-server',
        errorType: 'Error1',
        errorMessage: 'E1',
        file: 'test.ts',
        line: 1,
      });
      collector.recordError('fp2', {
        service: 'code-server',
        errorType: 'Error2',
        errorMessage: 'E2',
        file: 'test.ts',
        line: 2,
      });

      const topErrors = collector.getTopErrors(1);
      expect(topErrors).toHaveLength(1);
      expect(topErrors[0].fingerprint).toBe('fp1');
      expect(topErrors[0].count).toBe(2);
    });
  });

  describe('getDeduplicationRatio()', () => {
    test('calculates deduplication ratio correctly', () => {
      // 5 errors, 2 unique fingerprints
      // ratio = (5 - 2) / 5 = 0.6 (60% deduplicated)
      collector.recordError('fp1', {
        service: 'code-server',
        errorType: 'Error',
        errorMessage: 'E1',
        file: 'test.ts',
        line: 1,
      });
      collector.recordError('fp1', {
        service: 'code-server',
        errorType: 'Error',
        errorMessage: 'E1',
        file: 'test.ts',
        line: 1,
      });
      collector.recordError('fp1', {
        service: 'code-server',
        errorType: 'Error',
        errorMessage: 'E1',
        file: 'test.ts',
        line: 1,
      });
      collector.recordError('fp2', {
        service: 'code-server',
        errorType: 'Error2',
        errorMessage: 'E2',
        file: 'test.ts',
        line: 2,
      });
      collector.recordError('fp2', {
        service: 'code-server',
        errorType: 'Error2',
        errorMessage: 'E2',
        file: 'test.ts',
        line: 2,
      });

      const ratio = collector.getDeduplicationRatio();
      expect(ratio).toBeCloseTo(0.6, 1);
    });

    test('returns 0 for no errors', () => {
      const ratio = collector.getDeduplicationRatio();
      expect(ratio).toBe(0);
    });

    test('returns 0 for all unique errors', () => {
      collector.recordError('fp1', {
        service: 'code-server',
        errorType: 'Error',
        errorMessage: 'E1',
        file: 'test.ts',
        line: 1,
      });
      collector.recordError('fp2', {
        service: 'code-server',
        errorType: 'Error2',
        errorMessage: 'E2',
        file: 'test.ts',
        line: 2,
      });

      const ratio = collector.getDeduplicationRatio();
      expect(ratio).toBe(0);
    });
  });
});

describe('ErrorFingerprinter', () => {
  let fingerprinter: ErrorFingerprinter;

  beforeEach(() => {
    fingerprinter = new ErrorFingerprinter('code-server');
  });

  describe('fingerprint()', () => {
    test('fingerprints Error objects', () => {
      const error = new Error('Test error');
      const result = fingerprinter.fingerprint(error, {
        file: 'test.ts',
        line: 10,
        userId: 'user1',
      });

      expect(result.fingerprint).toMatch(/^[a-f0-9]{64}$/);
      expect(result.normalized.errorType).toBe('Error');
      expect(result.normalized.service).toBe('code-server');
    });

    test('fingerprints string errors', () => {
      const result = fingerprinter.fingerprint('String error message', {
        file: 'test.ts',
        line: 5,
      });

      expect(result.fingerprint).toMatch(/^[a-f0-9]{64}$/);
      expect(result.normalized.errorMessage).toContain('String error');
    });

    test('records metrics for fingerprinted errors', () => {
      fingerprinter.fingerprint(new Error('Error 1'), {
        file: 'test.ts',
        line: 1,
        userId: 'user1',
      });
      fingerprinter.fingerprint(new Error('Error 1'), {
        file: 'test.ts',
        line: 1,
        userId: 'user2',
      });

      const metrics = fingerprinter.getMetrics();
      expect(metrics.totalErrorCount).toBe(2);
      expect(metrics.totalUniqueErrors).toBe(1);
    });
  });

  describe('getMetrics()', () => {
    test('returns aggregated metrics', () => {
      fingerprinter.fingerprint(new Error('Error 1'), {
        file: 'test.ts',
        line: 1,
      });
      fingerprinter.fingerprint(new Error('Error 1'), {
        file: 'test.ts',
        line: 1,
      });

      const metrics = fingerprinter.getMetrics();

      expect(metrics.totalErrorCount).toBe(2);
      expect(metrics.totalUniqueErrors).toBe(1);
      expect(metrics.deduplicationRatio).toBe(0.5);
      expect(metrics.topErrors).toHaveLength(1);
    });
  });

  describe('exportMetrics()', () => {
    test('exports Prometheus-formatted metrics', () => {
      fingerprinter.fingerprint(new Error('Test error'), {
        file: 'test.ts',
        line: 1,
      });

      const metricsText = fingerprinter.exportMetrics();

      expect(metricsText).toContain('error_fingerprint_count');
      expect(metricsText).toContain('error_fingerprint_user_impact');
      expect(metricsText).toContain('fingerprinting_deduplication_ratio');
      expect(metricsText).toMatch(/\d+ \d+$/m); // timestamp at end
    });
  });

  describe('exportLogsJSON()', () => {
    test('exports logs in JSON format', () => {
      fingerprinter.fingerprint(new Error('Test error'), {
        file: 'test.ts',
        line: 1,
      });

      const logs = fingerprinter.exportLogsJSON();

      expect(logs).toHaveLength(1);
      expect(logs[0]).toHaveProperty('fingerprint');
      expect(logs[0]).toHaveProperty('service');
      expect(logs[0]).toHaveProperty('error_type');
      expect(logs[0]).toHaveProperty('count');
      expect(logs[0]).toHaveProperty('affected_users');
      expect(logs[0]).toHaveProperty('affected_services');
    });
  });
});
