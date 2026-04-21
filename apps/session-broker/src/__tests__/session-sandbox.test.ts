// @file        apps/session-broker/src/__tests__/session-sandbox.test.ts
// @module      security/workspace-isolation
// @description Comprehensive test suite for Session Sandbox

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { SessionSandbox, getSessionSandbox, resetSessionSandbox } from '../session-sandbox';

describe('SessionSandbox', () => {
  let sandbox: SessionSandbox;

  beforeEach(() => {
    resetSessionSandbox();
    sandbox = new SessionSandbox({
      policy: 'require',
      runtime: 'runsc',
      failClosed: true,
      maxMemoryMB: 2048,
      maxCPUs: 2,
      enableNetworking: true,
      timeoutSeconds: 3600,
    });
  });

  afterEach(() => {
    sandbox.resetMetrics();
    resetSessionSandbox();
  });

  describe('Initialization', () => {
    it('should create sandbox with default config', () => {
      const instance = new SessionSandbox();
      expect(instance).toBeDefined();
    });

    it('should merge provided config with defaults', () => {
      const customSandbox = new SessionSandbox({
        policy: 'optional',
        maxMemoryMB: 1024,
      });
      expect(customSandbox).toBeDefined();
    });

    it('should return same instance via singleton pattern', () => {
      const sandbox1 = getSessionSandbox();
      const sandbox2 = getSessionSandbox();
      expect(sandbox1).toBe(sandbox2);
    });

    it('should allow resetting singleton', () => {
      const sandbox1 = getSessionSandbox();
      resetSessionSandbox();
      const sandbox2 = getSessionSandbox();
      expect(sandbox1).not.toBe(sandbox2);
    });
  });

  describe('Runtime Normalization', () => {
    it('should normalize runsc to runsc', () => {
      const sb = new SessionSandbox({ runtime: 'runsc' });
      const session = sb.createSession('test-1', 'user1');
      expect(session.runtime).toBe('runsc');
    });

    it('should normalize gvisor to runsc', () => {
      const sb = new SessionSandbox({ runtime: 'gvisor' });
      const session = sb.createSession('test-1', 'user1');
      expect(session.runtime).toBe('runsc');
    });

    it('should normalize gvisor-runsc to runsc', () => {
      const sb = new SessionSandbox({ runtime: 'gvisor-runsc' });
      const session = sb.createSession('test-1', 'user1');
      expect(session.runtime).toBe('runsc');
    });

    it('should keep runc as runc', () => {
      const sb = new SessionSandbox({ runtime: 'runc' });
      const session = sb.createSession('test-1', 'user1');
      expect(session.runtime).toBe('runc');
    });
  });

  describe('Session Creation', () => {
    it('should create isolated session with runsc runtime', () => {
      const session = sandbox.createSession('sess-001', 'user1');
      expect(session.sessionId).toBe('sess-001');
      expect(session.userId).toBe('user1');
      expect(session.runtime).toBe('runsc');
      expect(session.isolated).toBe(true);
    });

    it('should apply sandbox policy correctly', () => {
      sandbox.setPolicy('require');
      const session = sandbox.createSession('sess-003', 'user3');
      expect(session.policy).toBe('require');
      expect(session.isolated).toBe(true);
    });

    it('should track sessions in active sessions map', () => {
      sandbox.createSession('sess-009', 'user9');
      const session = sandbox.getSession('sess-009');
      expect(session).toBeDefined();
      expect(session?.sessionId).toBe('sess-009');
    });

    it('should increment session creation counter', () => {
      sandbox.createSession('sess-010', 'user10');
      sandbox.createSession('sess-011', 'user11');
      const metrics = sandbox.getMetrics();
      expect(metrics.sessionsCreated).toBe(2);
    });
  });

  describe('Fail-Closed Behavior', () => {
    it('should throw when isolation required but runsc unavailable and failClosed=true', () => {
      const sb = new SessionSandbox({
        policy: 'require',
        runtime: 'runc',
        failClosed: true,
      });
      expect(() => sb.createSession('sess-fail', 'user')).toThrow();
    });

    it('should emit isolation-failed event', (done) => {
      const sb = new SessionSandbox({
        policy: 'require',
        runtime: 'runc',
        failClosed: true,
      });
      sb.on('sandbox-isolation-failed', (event) => {
        expect(event.sessionId).toBe('sess-fail2');
        expect(event.severity).toBe('critical');
        done();
      });
      try {
        sb.createSession('sess-fail2', 'user');
      } catch (e) {
        // Expected
      }
    });

    it('should not throw when failClosed=false and isolation unavailable', () => {
      const sb = new SessionSandbox({
        policy: 'require',
        runtime: 'runc',
        failClosed: false,
      });
      expect(() => sb.createSession('sess-ok', 'user')).not.toThrow();
    });
  });

  describe('Runtime Flags', () => {
    it('should return runsc flags for isolated session', () => {
      const session = sandbox.createSession('sess-flags-1', 'user1');
      const flags = sandbox.getRuntimeFlags(session.sessionId);
      expect(flags).toContain('--runtime');
      expect(flags).toContain('runsc');
    });

    it('should include capability drops for isolation', () => {
      const session = sandbox.createSession('sess-flags-2', 'user2');
      const flags = sandbox.getRuntimeFlags(session.sessionId);
      expect(flags).toContain('--cap-drop');
      expect(flags).toContain('ALL');
    });

    it('should include memory limits', () => {
      const session = sandbox.createSession('sess-flags-3', 'user3');
      const flags = sandbox.getRuntimeFlags(session.sessionId);
      expect(flags).toContain('--memory');
      expect(flags).toContain('2048m');
    });

    it('should include CPU limits', () => {
      const session = sandbox.createSession('sess-flags-4', 'user4');
      const flags = sandbox.getRuntimeFlags(session.sessionId);
      expect(flags).toContain('--cpus');
      expect(flags).toContain('2');
    });

    it('should include read-only filesystem for isolated sessions', () => {
      const session = sandbox.createSession('sess-flags-7', 'user7');
      const flags = sandbox.getRuntimeFlags(session.sessionId);
      expect(flags).toContain('--read-only');
    });

    it('should throw on invalid session ID', () => {
      expect(() => sandbox.getRuntimeFlags('invalid-session')).toThrow();
    });
  });

  describe('Sandbox Environment Variables', () => {
    it('should include runtime in env vars', () => {
      const session = sandbox.createSession('sess-env-1', 'user1');
      const envVars = sandbox.getSandboxEnvVars(session.sessionId);
      expect(envVars.SANDBOX_RUNTIME).toBe('runsc');
    });

    it('should indicate isolation status', () => {
      const session = sandbox.createSession('sess-env-2', 'user2');
      const envVars = sandbox.getSandboxEnvVars(session.sessionId);
      expect(envVars.SANDBOX_ISOLATED).toBe('true');
    });

    it('should include resource limits', () => {
      const session = sandbox.createSession('sess-env-3', 'user3');
      const envVars = sandbox.getSandboxEnvVars(session.sessionId);
      expect(envVars.SANDBOX_CPU_QUOTA).toBe('2');
      expect(envVars.SANDBOX_MEMORY_LIMIT).toBe('2048');
    });
  });

  describe('Resource Monitoring', () => {
    it('should track CPU quota violations', () => {
      const session = sandbox.createSession('sess-monitor-1', 'user1');
      sandbox.monitorResources(session.sessionId, 250, 512);
      const metrics = sandbox.getMetrics();
      expect(metrics.cpuQuotaViolations).toBeGreaterThan(0);
    });

    it('should track memory violations', () => {
      const session = sandbox.createSession('sess-monitor-3', 'user3');
      sandbox.monitorResources(session.sessionId, 50, 3000);
      const metrics = sandbox.getMetrics();
      expect(metrics.memoryViolations).toBeGreaterThan(0);
    });

    it('should kill isolated session on OOM', () => {
      const session = sandbox.createSession('sess-monitor-5', 'user5');
      sandbox.monitorResources(session.sessionId, 50, 3000);
      const stillExists = sandbox.getSession(session.sessionId);
      expect(stillExists).toBeUndefined();
    });
  });

  describe('Session Management', () => {
    it('should kill session successfully', () => {
      const session = sandbox.createSession('sess-kill-1', 'user1');
      const killed = sandbox.killSession(session.sessionId);
      expect(killed).toBe(true);
      const session2 = sandbox.getSession(session.sessionId);
      expect(session2).toBeUndefined();
    });

    it('should return false when killing non-existent session', () => {
      const killed = sandbox.killSession('nonexistent');
      expect(killed).toBe(false);
    });

    it('should list all active sessions', () => {
      sandbox.createSession('sess-list-1', 'user1');
      sandbox.createSession('sess-list-2', 'user2');
      const sessions = sandbox.listSessions();
      expect(sessions.length).toBeGreaterThanOrEqual(2);
    });
  });

  describe('Metrics', () => {
    it('should track sessions created', () => {
      sandbox.createSession('sess-metric-1', 'user1');
      sandbox.createSession('sess-metric-2', 'user2');
      const metrics = sandbox.getMetrics();
      expect(metrics.sessionsCreated).toBe(2);
    });

    it('should track sessions isolated', () => {
      sandbox.createSession('sess-metric-3', 'user3');
      const metrics = sandbox.getMetrics();
      expect(metrics.sessionsIsolated).toBeGreaterThan(0);
    });

    it('should calculate isolation rate', () => {
      sandbox.createSession('sess-metric-4', 'user4');
      const metrics = sandbox.getMetrics();
      expect(metrics.isolationRate).toBeGreaterThan(0);
    });

    it('should reset metrics', () => {
      sandbox.createSession('sess-metric-6', 'user6');
      sandbox.resetMetrics();
      const metrics = sandbox.getMetrics();
      expect(metrics.sessionsCreated).toBe(0);
      expect(metrics.sessionsIsolated).toBe(0);
    });
  });

  describe('Configuration', () => {
    it('should change policy at runtime', () => {
      sandbox.setPolicy('optional');
      const session = sandbox.createSession('sess-config-1', 'user1');
      expect(session.policy).toBe('optional');
    });

    it('should change runtime at runtime', () => {
      sandbox.setRuntime('runc');
      const session = sandbox.createSession('sess-config-2', 'user2');
      expect(session.runtime).toBe('runc');
    });

    it('should emit config-changed event on runtime change', (done) => {
      sandbox.on('config-changed', (event) => {
        expect(event.setting).toBe('runtime');
        expect(event.value).toBe('runc');
        done();
      });
      sandbox.setRuntime('runc');
    });
  });

  describe('Event Emission', () => {
    it('should emit sandbox-created event', (done) => {
      sandbox.on('sandbox-created', (event) => {
        expect(event.isolated).toBe(true);
        expect(event.runtime).toBe('runsc');
        done();
      });
      sandbox.createSession('sess-event-1', 'user1');
    });

    it('should include session details in events', (done) => {
      sandbox.on('sandbox-created', (event) => {
        expect(event.sessionId).toBeDefined();
        expect(event.userId).toBeDefined();
        done();
      });
      sandbox.createSession('sess-event-2', 'user2');
    });
  });

  describe('Edge Cases', () => {
    it('should handle empty session ID', () => {
      expect(() => sandbox.getSession('')).not.toThrow();
    });

    it('should handle very long session ID', () => {
      const longId = 'a'.repeat(1000);
      const session = sandbox.createSession(longId, 'user');
      expect(session.sessionId).toBe(longId);
    });

    it('should handle unicode in user ID', () => {
      const session = sandbox.createSession('sess-unicode', '用户');
      expect(session.userId).toBe('用户');
    });

    it('should handle multiple sessions per user', () => {
      sandbox.createSession('sess-multi-1', 'user-multi');
      sandbox.createSession('sess-multi-2', 'user-multi');
      const sessions = sandbox.listSessions();
      expect(sessions.filter((s) => s.userId === 'user-multi').length).toBe(2);
    });

    it('should handle rapid session creation and deletion', () => {
      for (let i = 0; i < 100; i++) {
        const session = sandbox.createSession(`sess-rapid-${i}`, 'user');
        sandbox.killSession(session.sessionId);
      }
      const metrics = sandbox.getMetrics();
      expect(metrics.sessionsCreated).toBe(100);
    });
  });
});
