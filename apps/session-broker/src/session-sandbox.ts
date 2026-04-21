// @file        apps/session-broker/src/session-sandbox.ts
// @module      security/workspace-isolation
// @description Session sandbox manager - enforces gVisor (runsc) runtime for workspace isolation

import { EventEmitter } from 'events';

export type SandboxRuntime = 'runc' | 'runsc';
export type SandboxPolicy = 'require' | 'optional' | 'disabled';

export interface SandboxConfig {
  policy: SandboxPolicy;
  runtime: SandboxRuntime;
  failClosed: boolean;
  allowPrivileged: boolean;
  maxMemoryMB: number;
  maxCPUs: number;
  enableNetworking: boolean;
  timeoutSeconds: number;
}

export interface SandboxSession {
  sessionId: string;
  userId: string;
  runtime: SandboxRuntime;
  policy: SandboxPolicy;
  isolated: boolean;
  startTime: Date;
  cpuQuota: number;
  memoryLimit: number;
  networkEnabled: boolean;
}

/**
 * Session Sandbox Manager
 * Enforces workspace isolation using gVisor (runsc) runtime
 * Prevents untrusted code execution from accessing host resources
 */
export class SessionSandbox extends EventEmitter {
  private config: SandboxConfig;
  private activeSessions = new Map<string, SandboxSession>();
  private metrics = {
    sessionsCreated: 0,
    sessionsIsolated: 0,
    isolationFailures: 0,
    cpuQuotaViolations: 0,
    memoryViolations: 0,
  };

  constructor(config: Partial<SandboxConfig> = {}) {
    super();
    this.config = {
      policy: (process.env.SANDBOX_POLICY as SandboxPolicy) || 'require',
      runtime: this.normalizeRuntime(process.env.SANDBOX_RUNTIME || 'runsc'),
      failClosed: process.env.SANDBOX_FAIL_CLOSED !== 'false',
      allowPrivileged: process.env.SANDBOX_ALLOW_PRIVILEGED === 'true',
      maxMemoryMB: parseInt(process.env.SANDBOX_MAX_MEMORY_MB || '2048'),
      maxCPUs: parseFloat(process.env.SANDBOX_MAX_CPUS || '2'),
      enableNetworking: process.env.SANDBOX_NETWORKING !== 'false',
      timeoutSeconds: parseInt(process.env.SANDBOX_TIMEOUT_SECONDS || '3600'),
      ...config,
    };

    this.validateConfig();
  }

  /**
   * Normalize runtime identifier to canonical form
   */
  private normalizeRuntime(runtime: string): SandboxRuntime {
    const normalized = runtime.toLowerCase().trim();
    if (normalized === 'runsc' || normalized === 'gvisor' || normalized === 'gvisor-runsc') {
      return 'runsc';
    }
    if (normalized === 'runc') {
      return 'runc';
    }
    return 'runsc';
  }

  private validateConfig(): void {
    if (this.config.maxMemoryMB < 256) {
      throw new Error('Sandbox max memory must be at least 256 MB');
    }
    if (this.config.maxCPUs < 0.1 || this.config.maxCPUs > 64) {
      throw new Error('Sandbox CPU limit must be between 0.1 and 64');
    }
    if (this.config.timeoutSeconds < 60 || this.config.timeoutSeconds > 86400) {
      throw new Error('Sandbox timeout must be between 60 and 86400 seconds');
    }
  }

  /**
   * Create a new isolated session
   */
  createSession(
    sessionId: string,
    userId: string,
    options: Partial<SandboxSession> = {}
  ): SandboxSession {
    const shouldIsolate = this.config.policy === 'require';
    const isolatedRuntime = this.config.runtime === 'runsc';

    if (this.config.failClosed && shouldIsolate && !isolatedRuntime) {
      this.metrics.isolationFailures++;
      this.emit('sandbox-isolation-failed', {
        sessionId,
        reason: 'Sandbox required but runsc not available',
        severity: 'critical',
      });

      if (shouldIsolate) {
        throw new Error('Sandbox isolation required but not available');
      }
    }

    const session: SandboxSession = {
      sessionId,
      userId,
      runtime: isolatedRuntime ? 'runsc' : 'runc',
      policy: this.config.policy,
      isolated: isolatedRuntime && shouldIsolate,
      startTime: new Date(),
      cpuQuota: this.config.maxCPUs,
      memoryLimit: this.config.maxMemoryMB,
      networkEnabled: this.config.enableNetworking,
      ...options,
    };

    this.activeSessions.set(sessionId, session);
    this.metrics.sessionsCreated++;

    if (session.isolated) {
      this.metrics.sessionsIsolated++;
      this.emit('sandbox-created', {
        sessionId,
        userId,
        runtime: session.runtime,
        isolated: true,
      });
    }

    return session;
  }

  /**
   * Get container runtime flags for Docker/containerd
   */
  getRuntimeFlags(sessionId: string): string[] {
    const session = this.activeSessions.get(sessionId);
    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }

    const flags: string[] = [];

    if (session.isolated && session.runtime === 'runsc') {
      flags.push('--runtime', 'runsc');
      flags.push('--cap-drop', 'ALL');
      flags.push('--cap-add', 'NET_BIND_SERVICE');

      if (!this.config.allowPrivileged) {
        flags.push('--security-opt', 'no-new-privileges:true');
      }
    } else if (session.runtime === 'runc') {
      flags.push('--runtime', 'runc');
    }

    flags.push('--memory', `${session.memoryLimit}m`);
    flags.push('--memory-swap', `${session.memoryLimit}m`);
    flags.push('--cpus', `${session.cpuQuota}`);

    if (!session.networkEnabled) {
      flags.push('--network', 'none');
    } else {
      flags.push('--network', 'bridge');
      flags.push('--dns', '8.8.8.8');
      flags.push('--dns', '8.8.4.4');
    }

    if (session.isolated) {
      flags.push('--read-only');
      flags.push('--tmpfs', '/tmp:rw,noexec');
      flags.push('--tmpfs', '/run:rw,noexec');
    }

    return flags;
  }

  /**
   * Get environment variables for sandbox
   */
  getSandboxEnvVars(sessionId: string): Record<string, string> {
    const session = this.activeSessions.get(sessionId);
    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }

    return {
      SANDBOX_RUNTIME: session.runtime,
      SANDBOX_ISOLATED: String(session.isolated),
      SANDBOX_POLICY: session.policy,
      SANDBOX_CPU_QUOTA: String(session.cpuQuota),
      SANDBOX_MEMORY_LIMIT: String(session.memoryLimit),
      SANDBOX_NETWORK_ENABLED: String(session.networkEnabled),
      SANDBOX_SESSION_ID: sessionId,
    };
  }

  /**
   * Monitor resource usage
   */
  monitorResources(sessionId: string, cpuPercent: number, memoryMB: number): void {
    const session = this.activeSessions.get(sessionId);
    if (!session) return;

    if (cpuPercent > session.cpuQuota * 100) {
      this.metrics.cpuQuotaViolations++;
      this.emit('resource-violation', {
        sessionId,
        type: 'cpu',
        limit: session.cpuQuota,
        actual: cpuPercent / 100,
      });
    }

    if (memoryMB > session.memoryLimit) {
      this.metrics.memoryViolations++;
      this.emit('resource-violation', {
        sessionId,
        type: 'memory',
        limit: session.memoryLimit,
        actual: memoryMB,
      });

      if (session.isolated) {
        this.killSession(sessionId, 'out-of-memory');
      }
    }
  }

  /**
   * Terminate a session
   */
  killSession(sessionId: string, reason = 'normal'): boolean {
    const session = this.activeSessions.get(sessionId);
    if (!session) return false;

    this.activeSessions.delete(sessionId);

    this.emit('session-terminated', {
      sessionId,
      reason,
      duration: Date.now() - session.startTime.getTime(),
      isolated: session.isolated,
    });

    return true;
  }

  /**
   * Get session info
   */
  getSession(sessionId: string): SandboxSession | undefined {
    return this.activeSessions.get(sessionId);
  }

  /**
   * List active sessions
   */
  listSessions(): SandboxSession[] {
    return Array.from(this.activeSessions.values());
  }

  /**
   * Get metrics
   */
  getMetrics() {
    return {
      ...this.metrics,
      activeSessions: this.activeSessions.size,
      isolationRate:
        this.metrics.sessionsCreated > 0
          ? (this.metrics.sessionsIsolated / this.metrics.sessionsCreated) * 100
          : 0,
    };
  }

  /**
   * Reset metrics
   */
  resetMetrics(): void {
    this.metrics.sessionsCreated = 0;
    this.metrics.sessionsIsolated = 0;
    this.metrics.isolationFailures = 0;
    this.metrics.cpuQuotaViolations = 0;
    this.metrics.memoryViolations = 0;
  }

  /**
   * Update configuration at runtime
   */
  setPolicy(policy: SandboxPolicy): void {
    this.config.policy = policy;
    this.emit('config-changed', { setting: 'policy', value: policy });
  }

  setRuntime(runtime: SandboxRuntime): void {
    this.config.runtime = this.normalizeRuntime(runtime);
    this.emit('config-changed', { setting: 'runtime', value: this.config.runtime });
  }

  setFailClosed(failClosed: boolean): void {
    this.config.failClosed = failClosed;
    this.emit('config-changed', { setting: 'failClosed', value: failClosed });
  }
}

let globalSandbox: SessionSandbox | null = null;

export function getSessionSandbox(config?: Partial<SandboxConfig>): SessionSandbox {
  if (!globalSandbox) {
    globalSandbox = new SessionSandbox(config);
  }
  return globalSandbox;
}

export function resetSessionSandbox(): void {
  globalSandbox = null;
}
