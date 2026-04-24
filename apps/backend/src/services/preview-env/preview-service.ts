/**
 * @file        apps/backend/src/services/preview-env/preview-service.ts
 * @module      devops/preview-environments
 * @description PR preview environment provisioning and lifecycle management
 */

import { EventEmitter } from 'events';
import {
  PreviewEnvironment,
  GitBranch,
  PreviewStatus,
  PreviewEvent,
  PreviewBuildConfig,
  PreviewStats,
  CleanupPolicy,
  HealthCheckResult,
  ResourceType,
} from './types.js';

/**
 * PreviewEnvironmentService: Manage PR preview environments
 */
export class PreviewEnvironmentService extends EventEmitter {
  private isInitialized = false;
  private environments = new Map<string, PreviewEnvironment>();
  private events = new Map<string, PreviewEvent[]>();
  private cleanupPolicy: CleanupPolicy;
  private healthChecks = new Map<string, HealthCheckResult>();

  constructor(cleanupPolicy?: CleanupPolicy) {
    super();
    this.cleanupPolicy = cleanupPolicy || {
      onMerge: { destroy: true, gracePeriodMs: 0 },
      onClose: { destroy: true, gracePeriodMs: 0 },
      inactivityTimeoutMs: 3600000, // 1 hour
      maxConcurrentPerUser: 5,
      maxLifetimeMs: 7 * 24 * 60 * 60 * 1000, // 7 days
    };
  }

  /**
   * Initialize service
   */
  async initialize(): Promise<void> {
    if (this.isInitialized) return;
    this.isInitialized = true;

    // Start cleanup scheduler
    this.startCleanupScheduler();

    console.log('[PreviewEnvironmentService] Initialized');
    this.emit('initialized');
  }

  /**
   * Provision new preview environment
   */
  async provisionEnvironment(
    pullRequestId: number,
    branchName: string,
    sha: string,
    repository: string,
    userId: string,
    workspaceId: string,
    config: PreviewBuildConfig
  ): Promise<string> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const envId = `preview-${workspaceId}-${pullRequestId}-${Date.now()}`;

    const environment: PreviewEnvironment = {
      id: envId,
      branch: {
        name: branchName,
        sha,
        repository,
        pullRequestId,
        createdAt: Date.now(),
      },
      workspaceId,
      status: 'provisioning',
      createdAt: Date.now(),
      branchName,
      createdBy: userId,
      gracePeriodMs: this.cleanupPolicy.onMerge.gracePeriodMs || 3600000,
      urls: {},
      resources: {},
      environment: {},
    };

    this.environments.set(envId, environment);
    this.events.set(envId, []);

    this.addEvent(envId, 'created', `Preview environment created for PR #${pullRequestId}`);

    // Simulate provisioning
    await this.simulateProvisioning(envId, config);

    console.log(
      `[PreviewEnvironmentService] Provisioned environment ${envId} for PR #${pullRequestId}`
    );

    this.emit('environment-created', { environmentId: envId, pullRequestId });

    return envId;
  }

  /**
   * Simulate provisioning (in production, would call actual provisioning service)
   */
  private async simulateProvisioning(
    envId: string,
    config: PreviewBuildConfig
  ): Promise<void> {
    const env = this.environments.get(envId);
    if (!env) return;

    const startTime = Date.now();

    this.addEvent(envId, 'provisioning', 'Starting infrastructure provisioning');

    // Simulate build steps
    if (config.frontend.enabled) {
      env.resources.frontend = {
        port: config.frontend.port || 3000,
        status: 'running',
        memory: Math.random() * 200 + 100,
        cpu: Math.random() * 30 + 10,
      };
      env.urls.frontend = `https://pr-${env.branch.pullRequestId}-frontend.preview.local`;
    }

    if (config.backend.enabled) {
      env.resources.backend = {
        port: config.backend.port || 3001,
        status: 'running',
        memory: Math.random() * 300 + 150,
        cpu: Math.random() * 20 + 5,
      };
      env.urls.backend = `https://pr-${env.branch.pullRequestId}-backend.preview.local`;
    }

    if (config.database.enabled) {
      env.resources.database = {
        name: `preview_pr_${env.branch.pullRequestId}`,
        status: 'healthy',
        size: Math.random() * 100 + 10,
      };
      env.urls.database = `postgres://user:pass@db.preview.local/preview_pr_${env.branch.pullRequestId}`;
    }

    env.status = 'ready';
    env.readyAt = Date.now();
    env.buildDuration = Date.now() - startTime;

    this.addEvent(envId, 'ready', `Preview environment ready (build took ${env.buildDuration}ms)`);

    // Store health checks
    this.updateHealthChecks(envId, config);

    this.emit('environment-ready', { environmentId: envId });
  }

  /**
   * Update health checks
   */
  private updateHealthChecks(envId: string, config: PreviewBuildConfig): void {
    if (config.frontend.enabled) {
      this.healthChecks.set(`${envId}-frontend`, {
        resource: 'frontend',
        healthy: true,
        responseTime: Math.random() * 50 + 10,
        lastCheck: Date.now(),
      });
    }

    if (config.backend.enabled) {
      this.healthChecks.set(`${envId}-backend`, {
        resource: 'backend',
        healthy: true,
        responseTime: Math.random() * 100 + 20,
        lastCheck: Date.now(),
      });
    }

    if (config.database.enabled) {
      this.healthChecks.set(`${envId}-database`, {
        resource: 'database',
        healthy: true,
        responseTime: Math.random() * 50 + 5,
        lastCheck: Date.now(),
      });
    }
  }

  /**
   * Get preview environment
   */
  async getEnvironment(envId: string): Promise<PreviewEnvironment | null> {
    if (!this.isInitialized) throw new Error('Service not initialized');
    return this.environments.get(envId) || null;
  }

  /**
   * Get environment by PR ID
   */
  async getEnvironmentByPullRequest(
    workspaceId: string,
    prId: number
  ): Promise<PreviewEnvironment | null> {
    const env = Array.from(this.environments.values()).find(
      (e) =>
        e.workspaceId === workspaceId &&
        e.branch.pullRequestId === prId
    );
    return env || null;
  }

  /**
   * List environments for workspace
   */
  async listEnvironments(workspaceId: string): Promise<PreviewEnvironment[]> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    return Array.from(this.environments.values())
      .filter((env) => env.workspaceId === workspaceId)
      .sort((a, b) => b.createdAt - a.createdAt);
  }

  /**
   * List active environments for user
   */
  async listUserEnvironments(
    workspaceId: string,
    userId: string
  ): Promise<PreviewEnvironment[]> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    return Array.from(this.environments.values())
      .filter(
        (env) =>
          env.workspaceId === workspaceId &&
          env.createdBy === userId &&
          env.status !== 'destroyed'
      )
      .sort((a, b) => b.createdAt - a.createdAt);
  }

  /**
   * Mark environment for destruction (grace period)
   */
  async markForDestruction(
    envId: string,
    reason?: 'pr-merged' | 'pr-closed' | 'inactivity' | 'manual'
  ): Promise<void> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const env = this.environments.get(envId);
    if (!env) throw new Error(`Environment ${envId} not found`);

    if (env.status === 'destroyed') return;

    env.markedForDestructionAt = Date.now();
    env.status = 'destroying';

    this.addEvent(
      envId,
      'marked-for-destruction',
      `Marked for destruction (reason: ${reason || 'unknown'})`
    );

    console.log(
      `[PreviewEnvironmentService] Marked ${envId} for destruction (${reason})`
    );

    this.emit('environment-marked-for-destruction', { environmentId: envId, reason });
  }

  /**
   * Cancel destruction (if still in grace period)
   */
  async cancelDestruction(envId: string): Promise<boolean> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const env = this.environments.get(envId);
    if (!env) throw new Error(`Environment ${envId} not found`);

    if (!env.markedForDestructionAt) return false;

    const elapsed = Date.now() - env.markedForDestructionAt;
    if (elapsed > env.gracePeriodMs) return false; // Grace period expired

    env.markedForDestructionAt = undefined;
    env.status = 'ready';

    this.addEvent(envId, 'updated', 'Destruction cancelled');

    console.log(`[PreviewEnvironmentService] Cancelled destruction for ${envId}`);

    return true;
  }

  /**
   * Destroy environment
   */
  async destroyEnvironment(envId: string): Promise<void> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const env = this.environments.get(envId);
    if (!env) throw new Error(`Environment ${envId} not found`);

    env.status = 'destroyed';
    env.destroyedAt = Date.now();

    this.addEvent(envId, 'destroyed', 'Environment destroyed');

    // Clean up health checks
    for (const resource of ['frontend', 'backend', 'database'] as ResourceType[]) {
      this.healthChecks.delete(`${envId}-${resource}`);
    }

    console.log(`[PreviewEnvironmentService] Destroyed environment ${envId}`);

    this.emit('environment-destroyed', { environmentId: envId });
  }

  /**
   * Add event to environment
   */
  private addEvent(
    envId: string,
    type: PreviewEvent['type'],
    message: string,
    details?: Record<string, any>
  ): void {
    const events = this.events.get(envId) || [];
    events.push({
      type,
      environmentId: envId,
      timestamp: Date.now(),
      message,
      details,
    });
    this.events.set(envId, events);
  }

  /**
   * Get environment events
   */
  async getEnvironmentEvents(
    envId: string,
    limit: number = 100
  ): Promise<PreviewEvent[]> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const events = this.events.get(envId) || [];
    return events.slice(-limit);
  }

  /**
   * Run health check
   */
  async runHealthCheck(envId: string): Promise<HealthCheckResult[]> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const env = this.environments.get(envId);
    if (!env) throw new Error(`Environment ${envId} not found`);

    const results: HealthCheckResult[] = [];

    for (const resource of ['frontend', 'backend', 'database'] as ResourceType[]) {
      if (env.resources[resource]?.status === 'running' || env.resources[resource]?.status === 'healthy') {
        const result: HealthCheckResult = {
          resource,
          healthy: Math.random() > 0.1, // 90% healthy
          responseTime: Math.random() * 100 + 10,
          lastCheck: Date.now(),
        };

        if (!result.healthy) {
          result.error = `${resource} health check failed`;
        }

        this.healthChecks.set(`${envId}-${resource}`, result);
        results.push(result);
      }
    }

    return results;
  }

  /**
   * Get statistics
   */
  async getStatistics(workspaceId: string): Promise<PreviewStats> {
    const envs = Array.from(this.environments.values()).filter(
      (e) => e.workspaceId === workspaceId
    );

    const activeEnvs = envs.filter(
      (e) => e.status === 'ready' || e.status === 'degraded'
    );
    const provisioningEnvs = envs.filter(
      (e) => e.status === 'provisioning' || e.status === 'updating'
    );
    const failingEnvs = envs.filter((e) => e.status === 'failing');
    const markedForDestructionCount = envs.filter((e) => e.markedForDestructionAt).length;

    const stats: PreviewStats = {
      totalEnvironments: envs.length,
      activeEnvironments: activeEnvs.length,
      provisioningEnvironments: provisioningEnvs.length,
      failingEnvironments: failingEnvs.length,
      markedForDestruction: markedForDestructionCount,

      averageProvisionTime:
        envs.length > 0
          ? envs
              .filter((e) => e.buildDuration)
              .reduce((sum, e) => sum + (e.buildDuration || 0), 0) / envs.length
          : 0,

      averageResourceUsage: {
        frontend:
          envs.filter((e) => e.resources.frontend).length > 0
            ? envs
                .filter((e) => e.resources.frontend?.cpu)
                .reduce((sum, e) => sum + (e.resources.frontend?.cpu || 0), 0) /
              envs.filter((e) => e.resources.frontend).length
            : undefined,
        backend:
          envs.filter((e) => e.resources.backend).length > 0
            ? envs
                .filter((e) => e.resources.backend?.cpu)
                .reduce((sum, e) => sum + (e.resources.backend?.cpu || 0), 0) /
              envs.filter((e) => e.resources.backend).length
            : undefined,
      },

      uptime: {},
      errorRate: envs.length > 0 ? (failingEnvs.length / envs.length) * 100 : 0,
      byUser: {},
      byBranch: {},
    };

    // Count by user
    for (const env of envs) {
      stats.byUser[env.createdBy] = (stats.byUser[env.createdBy] || 0) + 1;
      stats.byBranch[env.branchName] = {
        status: env.status,
        createdAt: env.createdAt,
      };
    }

    return stats;
  }

  /**
   * Start cleanup scheduler
   */
  private startCleanupScheduler(): void {
    setInterval(() => {
      this.performCleanup();
    }, 60000); // Run every minute
  }

  /**
   * Perform cleanup of expired environments
   */
  private async performCleanup(): Promise<void> {
    const now = Date.now();

    for (const env of Array.from(this.environments.values())) {
      // Check grace period expiration
      if (env.markedForDestructionAt) {
        const gracePeriodExpired =
          now - env.markedForDestructionAt >= env.gracePeriodMs;
        if (gracePeriodExpired && env.status !== 'destroyed') {
          await this.destroyEnvironment(env.id);
        }
      }

      // Check max lifetime
      if (now - env.createdAt >= this.cleanupPolicy.maxLifetimeMs) {
        if (env.status !== 'destroyed') {
          await this.markForDestruction(env.id, 'inactivity');
          // Immediately destroy if marked
          await this.destroyEnvironment(env.id);
        }
      }
    }
  }

  /**
   * Update environment status
   */
  async updateStatus(envId: string, status: PreviewStatus): Promise<void> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const env = this.environments.get(envId);
    if (!env) throw new Error(`Environment ${envId} not found`);

    const oldStatus = env.status;
    env.status = status;

    this.addEvent(envId, 'updated', `Status changed from ${oldStatus} to ${status}`);

    if (status === 'ready') {
      this.emit('environment-ready', { environmentId: envId });
    } else if (status === 'degraded') {
      this.emit('environment-degraded', { environmentId: envId });
    } else if (status === 'failing') {
      this.emit('environment-failing', { environmentId: envId });
    }
  }
}

/**
 * Global service instance
 */
let serviceInstance: PreviewEnvironmentService | null = null;

/**
 * Get global service instance
 */
export async function getPreviewEnvironmentService(
  cleanupPolicy?: any
): Promise<PreviewEnvironmentService> {
  if (!serviceInstance) {
    serviceInstance = new PreviewEnvironmentService(cleanupPolicy);
    await serviceInstance.initialize();
  }
  return serviceInstance;
}
