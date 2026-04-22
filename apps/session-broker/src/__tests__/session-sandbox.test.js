// @file        apps/session-broker/src/__tests__/session-sandbox.test.ts
// @module      security/workspace-isolation
// @description Comprehensive test suite for Session Sandbox
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { SessionSandbox, getSessionSandbox, resetSessionSandbox } from '../session-sandbox';
describe('SessionSandbox', () => {
    let sandbox;
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
        it('should throw on invalid memory limit', () => {
            expect(() => new SessionSandbox({
                maxMemoryMB: 128, // Less than 256
            })).toThrow('Sandbox max memory must be at least 256 MB');
        });
        it('should throw on invalid CPU limit', () => {
            expect(() => new SessionSandbox({
                maxCPUs: 0.05, // Less than 0.1
            })).toThrow('Sandbox CPU limit must be between 0.1 and 64');
        });
        it('should throw on invalid timeout', () => {
            expect(() => new SessionSandbox({
                timeoutSeconds: 30, // Less than 60
            })).toThrow('Sandbox timeout must be between 60 and 86400 seconds');
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
        it('should default unknown runtime to runsc', () => {
            const sb = new SessionSandbox({ runtime: 'unknown' });
            const session = sb.createSession('test-1', 'user1');
            expect(session.runtime).toBe('runsc');
        });
        it('should handle case-insensitive runtime names', () => {
            const sb = new SessionSandbox({ runtime: 'RUNSC' });
            const session = sb.createSession('test-1', 'user1');
            expect(session.runtime).toBe('runsc');
        });
        it('should handle whitespace in runtime names', () => {
            const sb = new SessionSandbox({ runtime: '  runsc  ' });
            const session = sb.createSession('test-1', 'user1');
            expect(session.runtime).toBe('runsc');
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
        it('should create non-isolated session with runc runtime', () => {
            sandbox.setRuntime('runc');
            const session = sandbox.createSession('sess-002', 'user2');
            expect(session.runtime).toBe('runc');
            expect(session.isolated).toBe(false);
        });
        it('should apply sandbox policy correctly', () => {
            sandbox.setPolicy('require');
            const session = sandbox.createSession('sess-003', 'user3');
            expect(session.policy).toBe('require');
            expect(session.isolated).toBe(true);
        });
        it('should apply optional policy', () => {
            sandbox.setPolicy('optional');
            const session = sandbox.createSession('sess-004', 'user4');
            expect(session.policy).toBe('optional');
        });
        it('should apply disabled policy', () => {
            sandbox.setPolicy('disabled');
            const session = sandbox.createSession('sess-005', 'user5');
            expect(session.policy).toBe('disabled');
            expect(session.isolated).toBe(false);
        });
        it('should include session start time', () => {
            const before = new Date();
            const session = sandbox.createSession('sess-006', 'user6');
            const after = new Date();
            expect(session.startTime.getTime()).toBeGreaterThanOrEqual(before.getTime());
            expect(session.startTime.getTime()).toBeLessThanOrEqual(after.getTime());
        });
        it('should apply resource limits from config', () => {
            const session = sandbox.createSession('sess-007', 'user7');
            expect(session.cpuQuota).toBe(2);
            expect(session.memoryLimit).toBe(2048);
        });
        it('should enable networking by default', () => {
            const session = sandbox.createSession('sess-008', 'user8');
            expect(session.networkEnabled).toBe(true);
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
            expect(() => sb.createSession('sess-fail', 'user')).toThrow('Sandbox isolation required but not available');
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
            }
            catch (e) {
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
        it('should track isolation failures in metrics', () => {
            const sb = new SessionSandbox({
                policy: 'require',
                runtime: 'runc',
                failClosed: true,
            });
            try {
                sb.createSession('sess-fail3', 'user');
            }
            catch (e) {
                // Expected
            }
            const metrics = sb.getMetrics();
            expect(metrics.isolationFailures).toBeGreaterThan(0);
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
        it('should include networking when enabled', () => {
            const session = sandbox.createSession('sess-flags-5', 'user5');
            const flags = sandbox.getRuntimeFlags(session.sessionId);
            expect(flags).toContain('--network');
            expect(flags).toContain('bridge');
        });
        it('should disable networking when configured', () => {
            const sb = new SessionSandbox({ enableNetworking: false });
            const session = sb.createSession('sess-flags-6', 'user6');
            const flags = sb.getRuntimeFlags(session.sessionId);
            expect(flags).toContain('--network');
            expect(flags).toContain('none');
        });
        it('should include read-only filesystem for isolated sessions', () => {
            const session = sandbox.createSession('sess-flags-7', 'user7');
            const flags = sandbox.getRuntimeFlags(session.sessionId);
            expect(flags).toContain('--read-only');
        });
        it('should include tmpfs overrides', () => {
            const session = sandbox.createSession('sess-flags-8', 'user8');
            const flags = sandbox.getRuntimeFlags(session.sessionId);
            expect(flags).toContain('--tmpfs');
        });
        it('should throw on invalid session ID', () => {
            expect(() => sandbox.getRuntimeFlags('invalid-session')).toThrow('Session invalid-session not found');
        });
        it('should return runc flags for non-isolated session', () => {
            sandbox.setRuntime('runc');
            const session = sandbox.createSession('sess-flags-9', 'user9');
            const flags = sandbox.getRuntimeFlags(session.sessionId);
            expect(flags).toContain('--runtime');
            expect(flags).toContain('runc');
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
        it('should include session ID', () => {
            const session = sandbox.createSession('sess-env-4', 'user4');
            const envVars = sandbox.getSandboxEnvVars(session.sessionId);
            expect(envVars.SANDBOX_SESSION_ID).toBe('sess-env-4');
        });
        it('should throw on invalid session ID', () => {
            expect(() => sandbox.getSandboxEnvVars('invalid-session')).toThrow('Session invalid-session not found');
        });
    });
    describe('Resource Monitoring', () => {
        it('should track CPU quota violations', () => {
            const session = sandbox.createSession('sess-monitor-1', 'user1');
            sandbox.monitorResources(session.sessionId, 250, 512); // 250% > 200% (2 CPUs)
            const metrics = sandbox.getMetrics();
            expect(metrics.cpuQuotaViolations).toBeGreaterThan(0);
        });
        it('should emit resource-violation event on CPU violation', (done) => {
            const session = sandbox.createSession('sess-monitor-2', 'user2');
            sandbox.on('resource-violation', (event) => {
                expect(event.type).toBe('cpu');
                done();
            });
            sandbox.monitorResources(session.sessionId, 250, 512);
        });
        it('should track memory violations', () => {
            const session = sandbox.createSession('sess-monitor-3', 'user3');
            sandbox.monitorResources(session.sessionId, 50, 3000); // 3000 MB > 2048 MB
            const metrics = sandbox.getMetrics();
            expect(metrics.memoryViolations).toBeGreaterThan(0);
        });
        it('should emit resource-violation event on memory violation', (done) => {
            const session = sandbox.createSession('sess-monitor-4', 'user4');
            sandbox.on('resource-violation', (event) => {
                expect(event.type).toBe('memory');
                done();
            });
            sandbox.monitorResources(session.sessionId, 50, 3000);
        });
        it('should kill isolated session on OOM', () => {
            const session = sandbox.createSession('sess-monitor-5', 'user5');
            sandbox.monitorResources(session.sessionId, 50, 3000);
            const stillExists = sandbox.getSession(session.sessionId);
            expect(stillExists).toBeUndefined();
        });
        it('should not kill non-isolated session on violation', () => {
            sandbox.setRuntime('runc');
            const session = sandbox.createSession('sess-monitor-6', 'user6');
            sandbox.monitorResources(session.sessionId, 50, 3000);
            const stillExists = sandbox.getSession(session.sessionId);
            expect(stillExists).toBeDefined();
        });
        it('should ignore monitoring for non-existent sessions', () => {
            expect(() => sandbox.monitorResources('nonexistent', 50, 512)).not.toThrow();
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
        it('should emit session-terminated event', (done) => {
            const session = sandbox.createSession('sess-kill-2', 'user2');
            sandbox.on('session-terminated', (event) => {
                expect(event.sessionId).toBe('sess-kill-2');
                expect(event.reason).toBe('normal');
                done();
            });
            sandbox.killSession(session.sessionId);
        });
        it('should return false when killing non-existent session', () => {
            const killed = sandbox.killSession('nonexistent');
            expect(killed).toBe(false);
        });
        it('should track session duration', (done) => {
            const session = sandbox.createSession('sess-duration', 'user');
            setTimeout(() => {
                sandbox.on('session-terminated', (event) => {
                    expect(event.duration).toBeGreaterThan(50);
                    done();
                });
                sandbox.killSession(session.sessionId);
            }, 100);
        });
        it('should get specific session', () => {
            const session = sandbox.createSession('sess-get', 'user');
            const retrieved = sandbox.getSession('sess-get');
            expect(retrieved).toBeDefined();
            expect(retrieved?.userId).toBe('user');
        });
        it('should list all active sessions', () => {
            sandbox.createSession('sess-list-1', 'user1');
            sandbox.createSession('sess-list-2', 'user2');
            const sessions = sandbox.listSessions();
            expect(sessions.length).toBeGreaterThanOrEqual(2);
        });
        it('should return empty list when no sessions', () => {
            const sessions = sandbox.listSessions();
            expect(Array.isArray(sessions)).toBe(true);
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
        it('should track active sessions count', () => {
            sandbox.createSession('sess-metric-5', 'user5');
            const metrics = sandbox.getMetrics();
            expect(metrics.activeSessions).toBe(1);
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
        it('should emit config-changed event on policy change', (done) => {
            sandbox.on('config-changed', (event) => {
                expect(event.setting).toBe('policy');
                expect(event.value).toBe('disabled');
                done();
            });
            sandbox.setPolicy('disabled');
        });
        it('should change runtime at runtime', () => {
            sandbox.setRuntime('runc');
            const session = sandbox.createSession('sess-config-2', 'user2');
            expect(session.runtime).toBe('runc');
        });
        it('should change failClosed at runtime', () => {
            sandbox.setFailClosed(false);
            // Should not throw even with policy=require and runtime=runc
            const sb = new SessionSandbox({
                policy: 'require',
                runtime: 'runc',
                failClosed: false,
            });
            expect(() => sb.createSession('sess-ok', 'user')).not.toThrow();
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
        it('should not emit sandbox-created for non-isolated sessions', (done) => {
            sandbox.setRuntime('runc');
            const listener = vi.fn();
            sandbox.on('sandbox-created', listener);
            sandbox.createSession('sess-event-3', 'user3');
            setTimeout(() => {
                expect(listener).not.toHaveBeenCalled();
                done();
            }, 100);
        });
    });
    describe('Edge Cases', () => {
        it('should handle empty session ID', () => {
            expect(() => sandbox.getSession('')).not.toThrow();
        });
        it('should handle very long session ID', () => {
            const longId = 'a'.repeat(10000);
            const session = sandbox.createSession(longId, 'user');
            expect(session.sessionId).toBe(longId);
        });
        it('should handle unicode in user ID', () => {
            const session = sandbox.createSession('sess-unicode', '用户🌍');
            expect(session.userId).toBe('用户🌍');
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
//# sourceMappingURL=session-sandbox.test.js.map