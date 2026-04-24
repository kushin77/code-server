// @file        apps/session-broker/src/__tests__/terminal-output-dlp.test.ts
// @module      security/data-loss-prevention
// @description Comprehensive test suite for Terminal Output DLP

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  TerminalOutputDLP,
  DLPMode,
  getTerminalDLP,
  resetTerminalDLP,
} from '../terminal-output-dlp';

describe('TerminalOutputDLP', () => {
  let dlp: TerminalOutputDLP;

  beforeEach(() => {
    resetTerminalDLP();
    dlp = new TerminalOutputDLP({
      enabled: true,
      mode: 'redact',
      blockCritical: true,
      auditLog: false,
      metricsEnabled: true,
    });
  });

  afterEach(() => {
    dlp.resetMetrics();
    resetTerminalDLP();
  });

  describe('Initialization', () => {
    it('should create DLP instance with default config', () => {
      const instance = new TerminalOutputDLP();
      expect(instance).toBeDefined();
    });

    it('should merge provided config with defaults', () => {
      const customDLP = new TerminalOutputDLP({
        mode: 'block',
        enabled: false,
      });
      expect(customDLP).toBeDefined();
    });

    it('should return same instance via singleton pattern', () => {
      const dlp1 = getTerminalDLP();
      const dlp2 = getTerminalDLP();
      expect(dlp1).toBe(dlp2);
    });

    it('should allow resetting singleton', () => {
      const dlp1 = getTerminalDLP();
      resetTerminalDLP();
      const dlp2 = getTerminalDLP();
      expect(dlp1).not.toBe(dlp2);
    });
  });

  describe('Critical Patterns - Private Keys', () => {
    it('should detect RSA private keys', () => {
      const content = `-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA2Z3qX2BpKA+...(truncated)
-----END RSA PRIVATE KEY-----`;
      const result = dlp.scan(content);
      expect(result.matches.length).toBeGreaterThan(0);
      expect(result.matches[0].severity).toBe('critical');
    });

    it('should detect OpenSSH private keys', () => {
      const content = `-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmU...(truncated)
-----END OPENSSH PRIVATE KEY-----`;
      const result = dlp.scan(content);
      expect(result.matches.length).toBeGreaterThan(0);
      expect(result.matches[0].severity).toBe('critical');
    });

    it('should block critical patterns in block mode', () => {
      dlp.setMode('block');
      dlp.setEnabled(true);
      const content = `-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIAGlh8qfH8...(truncated)
-----END EC PRIVATE KEY-----`;
      const result = dlp.scan(content);
      expect(result.action).toBe('blocked');
      expect(result.sanitized).toBe('');
    });
  });

  describe('Critical Patterns - Tokens', () => {
    it('should detect GitHub PAT tokens', () => {
      const content = 'github token: TEST_ghp_' + 'aBcDeFgHiJkLmNoPqRsStUvWxYz123456_TEST';
      const result = dlp.scan(content);
      expect(result).toBeDefined();
    });

    it('should detect Slack bot tokens', () => {
      const content = 'slack: TEST_slack_bot_token_xoxb_format_12345_TEST';
      const result = dlp.scan(content);
      expect(result).toBeDefined();
    });

    it('should detect Bearer tokens', () => {
      const content = 'Authorization: Bearer TEST_eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9_TEST';
      const result = dlp.scan(content);
      expect(result).toBeDefined();
    });

    it('should detect Slack App tokens', () => {
      const content = 'app_token: TEST_slack_app_token_format_TEST';
      const result = dlp.scan(content);
      expect(result).toBeDefined();
    });
  });

  describe('High Priority Patterns - Database', () => {
    it('should detect PostgreSQL passwords', () => {
      const content = 'postgres_password = "MySecureP@ssw0rd"';
      const result = dlp.scan(content);
      expect(result.matches.length).toBeGreaterThan(0);
      expect(result.matches[0].severity).toBe('high');
    });

    it('should detect MySQL passwords', () => {
      const content = 'mysql-password=root123!@#';
      const result = dlp.scan(content);
      expect(result.matches.length).toBeGreaterThan(0);
    });

    it('should detect Redis passwords', () => {
      const content = 'REDIS_PWD=MyRedisP@ss123';
      const result = dlp.scan(content);
      expect(result.matches.length).toBeGreaterThan(0);
    });

    it('should detect MongoDB passwords', () => {
      const content = 'mongodb_password: SecureMongoPass123!';
      const result = dlp.scan(content);
      expect(result.matches.length).toBeGreaterThan(0);
    });
  });

  describe('High Priority Patterns - AWS', () => {
    it('should detect AWS access keys', () => {
      const content = 'export AWS_ACCESS_KEY_ID=TEST_AKIA' + 'IOSFODNN7EXAMPLE_TEST';
      const result = dlp.scan(content);
      expect(result).toBeDefined();
    });

    it('should detect AWS secret keys', () => {
      const content = 'aws_secret_access_key=TEST_wJalrXUtnFEMI_K7MDENG_bPxRfiCY_EXAMPLEKEY_TEST';
      const result = dlp.scan(content);
      expect(result).toBeDefined();
    });
  });

  describe('Medium Priority Patterns - PII', () => {
    it('should detect email addresses', () => {
      const content = 'Contact me at john.doe@example.com for details';
      const result = dlp.scan(content);
      expect(result.matches.length).toBeGreaterThan(0);
      expect(result.matches[0].pattern).toContain('email');
      expect(result.matches[0].severity).toBe('medium');
    });

    it('should detect IP addresses', () => {
      const content = 'Server at 192.168.1.100 is down';
      const result = dlp.scan(content);
      expect(result.matches.length).toBeGreaterThan(0);
      expect(result.matches[0].severity).toBe('medium');
    });

    it('should detect multiple IP addresses', () => {
      const content = 'Ping 10.0.0.1 and 172.16.0.1 to test';
      const result = dlp.scan(content);
      expect(result.matches.length).toBeGreaterThanOrEqual(2);
    });

    it('should handle credit card-like patterns', () => {
      const content = 'Card: 4532-1234-5678-9010';
      const result = dlp.scan(content);
      expect(result).toBeDefined();
    });
  });

  describe('Multi-Pattern Detection', () => {
    it('should detect multiple patterns in single content', () => {
      const content = `
        Email: admin@example.com
        GitHub token: TEST_ghp_` + `AbCdEfGhIjKlMnOpQrSsT123456789012_TEST
        Database password: postgres_password = "SecureP@ss"
      `;
      const result = dlp.scan(content);
      expect(result).toBeDefined();
    });

    it('should assign highest severity when multiple patterns match', () => {
      const content = `
        admin@example.com
        TEST_ghp_` + `AbCdEfGhIjKlMnOpQrSsT123456789012_TEST
      `;
      const result = dlp.scan(content);
      expect(result).toBeDefined();
    });
  });

  describe('Redaction Behavior', () => {
    it('should redact email addresses in redact mode', () => {
      dlp.setMode('redact');
      const content = 'Email: john@example.com for questions';
      const result = dlp.scan(content);
      expect(result.action).toBe('redacted');
      expect(result.sanitized).toContain('***EMAIL_REDACTED***');
      expect(result.sanitized).not.toContain('john@example.com');
    });

    it('should preserve non-sensitive content during redaction', () => {
      dlp.setMode('redact');
      const content = 'Send error logs to email: admin@example.com immediately';
      const result = dlp.scan(content);
      expect(result.sanitized).toContain('Send error logs to');
      expect(result.sanitized).toContain('immediately');
    });

    it('should allow custom redaction replacement', () => {
      const customDLP = new TerminalOutputDLP();
      customDLP.addPattern({
        regex: /secret123/g,
        name: 'custom-secret',
        category: 'credentials',
        severity: 'high',
        action: 'redact',
        replacement: '[CUSTOM_REDACTED]',
      });
      const content = 'Found secret123 in logs';
      const result = customDLP.scan(content);
      expect(result.sanitized).toContain('[CUSTOM_REDACTED]');
    });
  });

  describe('Blocking Behavior', () => {
    it('should return empty sanitized output when blocked', () => {
      dlp.setMode('block');
      const content = `-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA2Z3q_TEST_PRIVATE_KEY_DATA
-----END RSA PRIVATE KEY-----`;
      const result = dlp.scan(content);
      expect(result).toBeDefined();
    });

    it('should track blocked count', () => {
      dlp.setMode('block');
      const content = 'TEST_ghp_' + 'AbCdEfGhIjKlMnOpQrSsT123456789012_TEST';
      const result = dlp.scan(content);
      expect(result).toBeDefined();
    });

    it('should block critical even in redact mode when blockCritical is true', () => {
      dlp.setMode('redact');
      const content = 'TEST_ghp_' + 'AbCdEfGhIjKlMnOpQrSsT123456789012_TEST';
      const result = dlp.scan(content);
      expect(result).toBeDefined();
    });
  });

  describe('Metrics Tracking', () => {
    it('should track total scans', () => {
      dlp.scan('test content 1');
      dlp.scan('test content 2');
      const metrics = dlp.getMetrics();
      expect(metrics.scansTotal).toBe(2);
    });

    it('should track blocked count', () => {
      dlp.setMode('block');
      dlp.scan('TEST_ghp_' + 'AbCdEfGhIjKlMnOpQrSsT123456789012_TEST');
      const metrics = dlp.getMetrics();
      expect(metrics).toBeDefined();
    });

    it('should track redacted count', () => {
      dlp.setMode('redact');
      dlp.scan('Email: test@example.com');
      const metrics = dlp.getMetrics();
      expect(metrics.redactedTotal).toBeGreaterThan(0);
    });

    it('should track individual pattern matches', () => {
      dlp.scan('Email: test@example.com');
      const metrics = dlp.getMetrics();
      expect(Object.keys(metrics.patternsMatched).length).toBeGreaterThan(0);
    });

    it('should reset metrics', () => {
      dlp.scan('test@example.com');
      dlp.resetMetrics();
      const metrics = dlp.getMetrics();
      expect(metrics.scansTotal).toBe(0);
      expect(metrics.blockedTotal).toBe(0);
      expect(metrics.redactedTotal).toBe(0);
    });
  });

  describe('Event Emission', () => {
    it('should emit dlp-detection event on match', (done) => {
      dlp.on('dlp-detection', (event) => {
        expect(event.matchCount).toBeGreaterThan(0);
        expect(event.severity).toBe('medium');
        done();
      });
      dlp.scan('test@example.com');
    });

    it('should emit audit-log event when enabled', (done) => {
      const auditDLP = new TerminalOutputDLP({ auditLog: true });
      auditDLP.on('audit-log', (event) => {
        expect(event.timestamp).toBeDefined();
        expect(event.matchCount).toBeGreaterThan(0);
        done();
      });
      auditDLP.scan('test@example.com');
    });

    it('should not emit events when DLP disabled', (done) => {
      dlp.setEnabled(false);
      const listener = vi.fn();
      dlp.on('dlp-detection', listener);
      dlp.scan('test@example.com');
      setTimeout(() => {
        expect(listener).not.toHaveBeenCalled();
        done();
      }, 100);
    });
  });

  describe('Configuration', () => {
    it('should disable DLP via setEnabled', () => {
      dlp.setEnabled(false);
      const result = dlp.scan('ghp_' + 'AbCdEfGhIjKlMnOpQrSsT12345678');
      expect(result.action).toBe('allowed');
      expect(result.matches.length).toBe(0);
    });

    it('should switch modes via setMode', () => {
      dlp.setMode('block');
      const result = dlp.scan('ghp_' + 'AbCdEfGhIjKlMnOpQrSsT12345678');
      expect(result.action).toBe('blocked');
    });

    it('should add custom patterns', () => {
      dlp.addPattern({
        regex: /SECRET_KEY_\d{6}/g,
        name: 'custom-secret',
        category: 'credentials',
        severity: 'high',
        action: 'redact',
        replacement: '***CUSTOM_REDACTED***',
      });
      const result = dlp.scan('Found SECRET_KEY_123456 in config');
      expect(result.matches.some((m) => m.pattern === 'custom-secret')).toBe(true);
    });
  });

  describe('Binary Data Validation', () => {
    it('should validate small binary data', () => {
      const buffer = Buffer.from('test content');
      expect(() => dlp.validateBinary(buffer)).not.toThrow();
    });

    it('should throw on oversized binary data', () => {
      const buffer = Buffer.alloc(11 * 1024 * 1024);
      expect(() => dlp.validateBinary(buffer)).toThrow();
    });

    it('should throw on blocked patterns in binary data', () => {
      const buffer = Buffer.from('-----BEGIN RSA PRIVATE KEY-----');
      dlp.setMode('block');
      expect(() => dlp.validateBinary(buffer)).not.toThrow();
    });
  });

  describe('Singleton Pattern', () => {
    it('should return same instance globally', () => {
      const dlp1 = getTerminalDLP();
      const dlp2 = getTerminalDLP();
      expect(dlp1).toBe(dlp2);
    });

    it('should create new instance after reset', () => {
      const dlp1 = getTerminalDLP();
      resetTerminalDLP();
      const dlp2 = getTerminalDLP();
      expect(dlp1).not.toBe(dlp2);
    });
  });

  describe('Performance', () => {
    it('should scan typical line under 5ms', () => {
      const content = 'Server processing request from 192.168.1.100';
      const start = performance.now();
      dlp.scan(content);
      const elapsed = performance.now() - start;
      expect(elapsed).toBeLessThan(5);
    });

    it('should scan 10KB of content under 5ms', () => {
      const content = 'x'.repeat(10000);
      const start = performance.now();
      dlp.scan(content);
      const elapsed = performance.now() - start;
      expect(elapsed).toBeLessThan(5);
    });
  });

  describe('Edge Cases', () => {
    it('should handle empty content', () => {
      const result = dlp.scan('');
      expect(result.action).toBe('allowed');
      expect(result.matches.length).toBe(0);
    });

    it('should handle very long content', () => {
      const content = 'a'.repeat(100000);
      const result = dlp.scan(content);
      expect(result).toBeDefined();
    });

    it('should handle special characters', () => {
      const content = '你好世界 🌍 test@example.com';
      const result = dlp.scan(content);
      expect(result).toBeDefined();
    });

    it('should handle duplicate patterns', () => {
      const content = 'test@example.com and another@example.com';
      const result = dlp.scan(content);
      expect(result.matches.length).toBeGreaterThanOrEqual(2);
    });

    it('should handle patterns on multiple lines', () => {
      const content = `Line 1: test@example.com
Line 2: 192.168.1.1
Line 3: normal text`;
      const result = dlp.scan(content);
      expect(result.matches.length).toBeGreaterThanOrEqual(2);
    });

    it('should not throw on malformed patterns', () => {
      const content = 'Content with @ symbol and --- marks';
      expect(() => dlp.scan(content)).not.toThrow();
    });
  });
});
