// @file        apps/session-broker/src/session-sandbox.ts
// @module      security/workspace-isolation
// @description Session sandbox manager - enforces gVisor (runsc) runtime for workspace isolation
import { EventEmitter } from 'events';
/**
 * Session Sandbox Manager
 * Enforces workspace isolation using gVisor (runsc) runtime
 * Prevents untrusted code execution from accessing host resources
 */
export class SessionSandbox extends EventEmitter {
    constructor(config = {}) {
        super();
        this.activeSessions = new Map();
        this.metrics = {
            sessionsCreated: 0,
            sessionsIsolated: 0,
            isolationFailures: 0,
            cpuQuotaViolations: 0,
            memoryViolations: 0,
        };
        this.config = {
            policy: process.env.SANDBOX_POLICY || 'require',
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
    normalizeRuntime(runtime) {
        const normalized = runtime.toLowerCase().trim();
        // Accept gvisor, runsc, gvisor-runsc as aliases for runsc
        if (normalized === 'runsc' || normalized === 'gvisor' || normalized === 'gvisor-runsc') {
            return 'runsc';
        }
        // Accept runc as-is (non-sandboxed)
        if (normalized === 'runc') {
            return 'runc';
        }
        // Default to runsc if unknown
        return 'runsc';
    }
    validateConfig() {
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
    createSession(sessionId, userId, options = {}) {
        // Determine if isolation is required
        const shouldIsolate = this.config.policy === 'require';
        const isolatedRuntime = this.config.runtime === 'runsc';
        // If fail-closed and isolation required but runtime isn't runsc, reject
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
        const session = {
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
    getRuntimeFlags(sessionId) {
        const session = this.activeSessions.get(sessionId);
        if (!session) {
            throw new Error(`Session ${sessionId} not found`);
        }
        const flags = [];
        if (session.isolated && session.runtime === 'runsc') {
            flags.push('--runtime', 'runsc');
            flags.push('--cap-drop', 'ALL');
            flags.push('--cap-add', 'NET_BIND_SERVICE');
            if (!this.config.allowPrivileged) {
                flags.push('--security-opt', 'no-new-privileges:true');
            }
        }
        else if (session.runtime === 'runc') {
            flags.push('--runtime', 'runc');
        }
        // Memory limit
        flags.push('--memory', `${session.memoryLimit}m`);
        flags.push('--memory-swap', `${session.memoryLimit}m`);
        // CPU limit
        flags.push('--cpus', `${session.cpuQuota}`);
        // Networking
        if (!session.networkEnabled) {
            flags.push('--network', 'none');
        }
        else {
            flags.push('--network', 'bridge');
            flags.push('--dns', '8.8.8.8');
            flags.push('--dns', '8.8.4.4');
        }
        // Read-only root filesystem (fail-safe)
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
    getSandboxEnvVars(sessionId) {
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
    monitorResources(sessionId, cpuPercent, memoryMB) {
        const session = this.activeSessions.get(sessionId);
        if (!session)
            return;
        // Check CPU quota
        if (cpuPercent > session.cpuQuota * 100) {
            this.metrics.cpuQuotaViolations++;
            this.emit('resource-violation', {
                sessionId,
                type: 'cpu',
                limit: session.cpuQuota,
                actual: cpuPercent / 100,
            });
        }
        // Check memory quota
        if (memoryMB > session.memoryLimit) {
            this.metrics.memoryViolations++;
            this.emit('resource-violation', {
                sessionId,
                type: 'memory',
                limit: session.memoryLimit,
                actual: memoryMB,
            });
            if (session.isolated) {
                // Kill isolated session on OOM
                this.killSession(sessionId, 'out-of-memory');
            }
        }
    }
    /**
     * Terminate a session
     */
    killSession(sessionId, reason = 'normal') {
        const session = this.activeSessions.get(sessionId);
        if (!session)
            return false;
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
    getSession(sessionId) {
        return this.activeSessions.get(sessionId);
    }
    /**
     * List active sessions
     */
    listSessions() {
        return Array.from(this.activeSessions.values());
    }
    /**
     * Get metrics
     */
    getMetrics() {
        return {
            ...this.metrics,
            activeSessions: this.activeSessions.size,
            isolationRate: this.metrics.sessionsCreated > 0
                ? (this.metrics.sessionsIsolated / this.metrics.sessionsCreated) * 100
                : 0,
        };
    }
    /**
     * Reset metrics
     */
    resetMetrics() {
        this.metrics.sessionsCreated = 0;
        this.metrics.sessionsIsolated = 0;
        this.metrics.isolationFailures = 0;
        this.metrics.cpuQuotaViolations = 0;
        this.metrics.memoryViolations = 0;
    }
    /**
     * Update configuration at runtime
     */
    setPolicy(policy) {
        this.config.policy = policy;
        this.emit('config-changed', { setting: 'policy', value: policy });
    }
    setRuntime(runtime) {
        this.config.runtime = this.normalizeRuntime(runtime);
        this.emit('config-changed', { setting: 'runtime', value: this.config.runtime });
    }
    setFailClosed(failClosed) {
        this.config.failClosed = failClosed;
        this.emit('config-changed', { setting: 'failClosed', value: failClosed });
    }
}
let globalSandbox = null;
export function getSessionSandbox(config) {
    if (!globalSandbox) {
        globalSandbox = new SessionSandbox(config);
    }
    return globalSandbox;
}
export function resetSessionSandbox() {
    globalSandbox = null;
}
//# sourceMappingURL=session-sandbox.js.map