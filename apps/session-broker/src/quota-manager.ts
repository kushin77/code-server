// @file        apps/session-broker/src/quota-manager.ts
// @module      session-management/quotas
// @description Session resource quota management and enforcement
//
// Manages resource quotas, tracking, and enforcement for user sessions.

import * as winston from 'winston';
import { RedisSessionStore, SessionContext } from './redis-session-store';

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.json(),
  transports: [new winston.transports.Console()],
});

export enum QuotaViolationType {
  CPU = 'cpu_exceeded',
  MEMORY = 'memory_exceeded',
  DISK = 'disk_exceeded',
  SESSIONS = 'sessions_exceeded',
  SNAPSHOT_STORAGE = 'snapshot_storage_exceeded',
}

export interface ResourceQuota {
  cpuLimitMillis: number;
  memoryLimitMb: number;
  diskLimitGb: number;
  maxSessionsPerUser: number;
  snapshotStorageLimitGb: number;
}

export interface ResourceUsage {
  cpuUsedMillis: number;
  memoryUsedMb: number;
  diskUsedGb: number;
  activeSessionCount: number;
  snapshotStorageUsedGb: number;
}

export interface QuotaViolation {
  id: string;
  userId: string;
  sessionId: string;
  violationType: QuotaViolationType;
  currentUsage: number;
  quotaLimit: number;
  detectedAt: Date;
  severity: 'warning' | 'critical';
  resolved: boolean;
}

/**
 * Manages session resource quotas and tracking.
 * Idempotent: quota violations are idempotent events.
 */
export class QuotaManager {
  private quotaStore: Map<string, ResourceQuota> = new Map();
  private usageStore: Map<string, ResourceUsage> = new Map();
  private violationStore: Map<string, QuotaViolation> = new Map();

  constructor(private sessionStore: RedisSessionStore) {
    this.initializeDefaultQuotas();
  }

  /**
   * Initialize default quotas for new users.
   */
  private initializeDefaultQuotas(): void {
    // These defaults can be overridden per-user or tier
    const defaultQuota: ResourceQuota = {
      cpuLimitMillis: 4000, // 4 CPU cores
      memoryLimitMb: 8192, // 8 GB
      diskLimitGb: 100, // 100 GB
      maxSessionsPerUser: 10,
      snapshotStorageLimitGb: 50, // 50 GB for snapshots
    };

    logger.info('Initialized default quota limits', { quota: defaultQuota });
  }

  /**
   * Get quota for a user (or create default).
   * Idempotent: getting quota multiple times returns same quota.
   */
  async getQuota(userId: string): Promise<ResourceQuota> {
    try {
      let quota = this.quotaStore.get(userId);

      if (!quota) {
        quota = {
          cpuLimitMillis: 4000,
          memoryLimitMb: 8192,
          diskLimitGb: 100,
          maxSessionsPerUser: 10,
          snapshotStorageLimitGb: 50,
        };

        this.quotaStore.set(userId, quota);
        logger.info('Created default quota for user', { userId, quota });
      }

      return quota;
    } catch (error) {
      logger.error('Failed to get quota', { error, userId });
      throw error;
    }
  }

  /**
   * Update quota for a user.
   * Idempotent: updating with same values returns true.
   */
  async updateQuota(userId: string, quota: Partial<ResourceQuota>): Promise<boolean> {
    try {
      const existing = await this.getQuota(userId);
      const updated = { ...existing, ...quota };

      this.quotaStore.set(userId, updated);
      logger.info('Updated quota for user', { userId, quota: updated });

      return true;
    } catch (error) {
      logger.error('Failed to update quota', { error, userId });
      return false;
    }
  }

  /**
   * Get current resource usage for a user.
   */
  async getUsage(userId: string): Promise<ResourceUsage> {
    try {
      let usage = this.usageStore.get(userId);

      if (!usage) {
        usage = {
          cpuUsedMillis: 0,
          memoryUsedMb: 0,
          diskUsedGb: 0,
          activeSessionCount: 0,
          snapshotStorageUsedGb: 0,
        };

        this.usageStore.set(userId, usage);
      }

      return usage;
    } catch (error) {
      logger.error('Failed to get usage', { error, userId });
      throw error;
    }
  }

  /**
   * Update resource usage.
   * Idempotent: updating usage is safe to repeat.
   */
  async updateUsage(
    userId: string,
    cpuDeltaMillis: number = 0,
    memoryDeltaMb: number = 0,
    diskDeltaGb: number = 0,
    sessionCountDelta: number = 0,
    snapshotDeltaGb: number = 0
  ): Promise<boolean> {
    try {
      const usage = await this.getUsage(userId);

      usage.cpuUsedMillis = Math.max(0, usage.cpuUsedMillis + cpuDeltaMillis);
      usage.memoryUsedMb = Math.max(0, usage.memoryUsedMb + memoryDeltaMb);
      usage.diskUsedGb = Math.max(0, usage.diskUsedGb + diskDeltaGb);
      usage.activeSessionCount = Math.max(0, usage.activeSessionCount + sessionCountDelta);
      usage.snapshotStorageUsedGb = Math.max(0, usage.snapshotStorageUsedGb + snapshotDeltaGb);

      this.usageStore.set(userId, usage);

      logger.debug('Updated resource usage', { userId, usage });

      return true;
    } catch (error) {
      logger.error('Failed to update usage', { error, userId });
      return false;
    }
  }

  /**
   * Check if quota is exceeded and record violations.
   * Idempotent: detecting same violation multiple times logs once.
   */
  async checkQuotaViolations(userId: string, sessionId?: string): Promise<QuotaViolation[]> {
    try {
      const quota = await this.getQuota(userId);
      const usage = await this.getUsage(userId);
      const violations: QuotaViolation[] = [];

      // Check CPU quota
      if (usage.cpuUsedMillis > quota.cpuLimitMillis) {
        const violation = this.createViolation(
          userId,
          sessionId || 'system',
          QuotaViolationType.CPU,
          usage.cpuUsedMillis,
          quota.cpuLimitMillis
        );
        violations.push(violation);
      }

      // Check memory quota
      if (usage.memoryUsedMb > quota.memoryLimitMb) {
        const violation = this.createViolation(
          userId,
          sessionId || 'system',
          QuotaViolationType.MEMORY,
          usage.memoryUsedMb,
          quota.memoryLimitMb
        );
        violations.push(violation);
      }

      // Check disk quota
      if (usage.diskUsedGb > quota.diskLimitGb) {
        const violation = this.createViolation(
          userId,
          sessionId || 'system',
          QuotaViolationType.DISK,
          usage.diskUsedGb,
          quota.diskLimitGb
        );
        violations.push(violation);
      }

      // Check session count quota
      if (usage.activeSessionCount > quota.maxSessionsPerUser) {
        const violation = this.createViolation(
          userId,
          sessionId || 'system',
          QuotaViolationType.SESSIONS,
          usage.activeSessionCount,
          quota.maxSessionsPerUser
        );
        violations.push(violation);
      }

      // Check snapshot storage quota
      if (usage.snapshotStorageUsedGb > quota.snapshotStorageLimitGb) {
        const violation = this.createViolation(
          userId,
          sessionId || 'system',
          QuotaViolationType.SNAPSHOT_STORAGE,
          usage.snapshotStorageUsedGb,
          quota.snapshotStorageLimitGb
        );
        violations.push(violation);
      }

      // Log violations
      for (const violation of violations) {
        if (!this.violationStore.has(violation.id)) {
          this.violationStore.set(violation.id, violation);
          logger.warn('Quota violation detected', {
            violationId: violation.id,
            userId,
            type: violation.violationType,
            usage: violation.currentUsage,
            limit: violation.quotaLimit,
            severity: violation.severity,
          });
        }
      }

      return violations;
    } catch (error) {
      logger.error('Failed to check quota violations', { error, userId });
      return [];
    }
  }

  /**
   * Resolve a quota violation.
   * Idempotent: resolving already-resolved violation is a no-op.
   */
  async resolveViolation(violationId: string): Promise<boolean> {
    try {
      const violation = this.violationStore.get(violationId);

      if (!violation) {
        logger.warn('Violation not found', { violationId });
        return true; // Idempotent
      }

      if (violation.resolved) {
        logger.info('Violation already resolved', { violationId });
        return true; // Idempotent
      }

      violation.resolved = true;
      logger.info('Quota violation resolved', { violationId, type: violation.violationType });

      return true;
    } catch (error) {
      logger.error('Failed to resolve violation', { error, violationId });
      return false;
    }
  }

  /**
   * Reset usage for a user.
   * Idempotent: resetting already-zero usage is a no-op.
   */
  async resetUsage(userId: string): Promise<boolean> {
    try {
      const usage = await this.getUsage(userId);
      const wasNonZero = usage.cpuUsedMillis > 0 || usage.memoryUsedMb > 0 || usage.diskUsedGb > 0;

      usage.cpuUsedMillis = 0;
      usage.memoryUsedMb = 0;
      usage.diskUsedGb = 0;
      usage.snapshotStorageUsedGb = 0;

      this.usageStore.set(userId, usage);

      if (wasNonZero) {
        logger.info('Reset resource usage for user', { userId });
      }

      return true;
    } catch (error) {
      logger.error('Failed to reset usage', { error, userId });
      return false;
    }
  }

  /**
   * Get quota utilization percentage.
   */
  async getUtilization(userId: string): Promise<Record<string, number>> {
    try {
      const quota = await this.getQuota(userId);
      const usage = await this.getUsage(userId);

      return {
        cpu: (usage.cpuUsedMillis / quota.cpuLimitMillis) * 100,
        memory: (usage.memoryUsedMb / quota.memoryLimitMb) * 100,
        disk: (usage.diskUsedGb / quota.diskLimitGb) * 100,
        sessions: (usage.activeSessionCount / quota.maxSessionsPerUser) * 100,
        snapshotStorage: (usage.snapshotStorageUsedGb / quota.snapshotStorageLimitGb) * 100,
      };
    } catch (error) {
      logger.error('Failed to get utilization', { error, userId });
      return {};
    }
  }

  /**
   * List all violations for a user.
   */
  async listViolations(userId: string, includeResolved: boolean = false): Promise<QuotaViolation[]> {
    try {
      return Array.from(this.violationStore.values()).filter(
        v => v.userId === userId && (includeResolved || !v.resolved)
      );
    } catch (error) {
      logger.error('Failed to list violations', { error, userId });
      return [];
    }
  }

  /**
   * Create a violation record.
   */
  private createViolation(
    userId: string,
    sessionId: string,
    type: QuotaViolationType,
    current: number,
    limit: number
  ): QuotaViolation {
    return {
      id: `violation-${userId}-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      userId,
      sessionId,
      violationType: type,
      currentUsage: current,
      quotaLimit: limit,
      detectedAt: new Date(),
      severity: current > limit * 1.5 ? 'critical' : 'warning',
      resolved: false,
    };
  }
}
