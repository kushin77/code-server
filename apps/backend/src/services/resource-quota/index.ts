#!/usr/bin/env node
/**
 * @file        apps/backend/src/services/resource-quota/index.ts
 * @module      resource-quota
 * @description Resource quota service for enforcing cgroups-based resource limits with tiered quotas
 *
 */

import { EventEmitter } from "events";
import { getLogger } from "../../lib/logger";

const logger = getLogger("resource-quota");

/**
 * Quota tier definitions with resource limits
 */
export enum QuotaTier {
  SMALL = "small",
  MEDIUM = "medium",
  LARGE = "large",
}

/**
 * Resource quota configuration for each tier
 */
export interface QuotaConfig {
  cpuLimit: number; // millicores (1000 = 1 CPU core)
  memoryLimit: number; // bytes
  diskIOLimit: number; // IOPS
  bandwidthLimit: number; // bytes per second
}

/**
 * Real-time resource usage metrics
 */
export interface ResourceUsage {
  cpuUsage: number; // millicores
  memoryUsage: number; // bytes
  diskIOUsage: number; // IOPS
  bandwidthUsage: number; // bytes per second
  timestamp: number; // Unix timestamp
}

/**
 * Quota enforcement record
 */
export interface QuotaEnforcement {
  sessionId: string;
  userId: string;
  tier: QuotaTier;
  cpuLimit: number;
  memoryLimit: number;
  diskIOLimit: number;
  bandwidthLimit: number;
  status: "active" | "throttled" | "paused";
  violations: number;
  lastViolationTime?: number;
  createdAt: number;
  updatedAt: number;
}

/**
 * Resource quota violation event
 */
export interface QuotaViolation {
  sessionId: string;
  userId: string;
  violationType: "cpu" | "memory" | "diskIO" | "bandwidth";
  currentUsage: number;
  limit: number;
  severity: "warning" | "critical";
  timestamp: number;
}

/**
 * ResourceQuotaService manages resource quotas and enforcement
 */
export class ResourceQuotaService extends EventEmitter {
  private static instance: ResourceQuotaService | null = null;
  private quotaConfigs: Map<QuotaTier, QuotaConfig> = new Map();
  private activeQuotas: Map<string, QuotaEnforcement> = new Map();
  private resourceUsage: Map<string, ResourceUsage> = new Map();
  private violationHistory: Map<string, QuotaViolation[]> = new Map();
  private monitoringInterval: NodeJS.Timer | null = null;

  constructor() {
    super();
    this.initializeQuotaConfigs();
  }

  /**
   * Get or create singleton instance
   */
  public static getInstance(): ResourceQuotaService {
    if (!ResourceQuotaService.instance) {
      ResourceQuotaService.instance = new ResourceQuotaService();
    }
    return ResourceQuotaService.instance;
  }

  /**
   * Initialize default quota configurations
   */
  private initializeQuotaConfigs(): void {
    // Small tier: 2 CPU cores, 2GB RAM, 1000 IOPS, 10Mbps
    this.quotaConfigs.set(QuotaTier.SMALL, {
      cpuLimit: 2000,
      memoryLimit: 2 * 1024 * 1024 * 1024,
      diskIOLimit: 1000,
      bandwidthLimit: 10 * 1024 * 1024, // 10 MB/s
    });

    // Medium tier: 4 CPU cores, 8GB RAM, 5000 IOPS, 50Mbps
    this.quotaConfigs.set(QuotaTier.MEDIUM, {
      cpuLimit: 4000,
      memoryLimit: 8 * 1024 * 1024 * 1024,
      diskIOLimit: 5000,
      bandwidthLimit: 50 * 1024 * 1024, // 50 MB/s
    });

    // Large tier: 8 CPU cores, 32GB RAM, 20000 IOPS, 200Mbps
    this.quotaConfigs.set(QuotaTier.LARGE, {
      cpuLimit: 8000,
      memoryLimit: 32 * 1024 * 1024 * 1024,
      diskIOLimit: 20000,
      bandwidthLimit: 200 * 1024 * 1024, // 200 MB/s
    });
  }

  /**
   * Enforce quota for a session
   */
  public enforceQuota(
    sessionId: string,
    userId: string,
    tier: QuotaTier
  ): QuotaEnforcement {
    const config = this.quotaConfigs.get(tier);
    if (!config) {
      throw new Error(`Invalid quota tier: ${tier}`);
    }

    const enforcement: QuotaEnforcement = {
      sessionId,
      userId,
      tier,
      cpuLimit: config.cpuLimit,
      memoryLimit: config.memoryLimit,
      diskIOLimit: config.diskIOLimit,
      bandwidthLimit: config.bandwidthLimit,
      status: "active",
      violations: 0,
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };

    this.activeQuotas.set(sessionId, enforcement);
    this.emit("quotaEnforced", enforcement);
    logger.info(`Quota enforced for session ${sessionId}`, {
      userId,
      tier,
      cpuLimit: config.cpuLimit,
    });

    return enforcement;
  }

  /**
   * Update resource usage for a session
   */
  public updateResourceUsage(
    sessionId: string,
    usage: Partial<ResourceUsage>
  ): ResourceUsage {
    const existing = this.resourceUsage.get(sessionId) || {
      cpuUsage: 0,
      memoryUsage: 0,
      diskIOUsage: 0,
      bandwidthUsage: 0,
      timestamp: Date.now(),
    };

    const updated: ResourceUsage = {
      cpuUsage: usage.cpuUsage !== undefined ? usage.cpuUsage : existing.cpuUsage,
      memoryUsage:
        usage.memoryUsage !== undefined ? usage.memoryUsage : existing.memoryUsage,
      diskIOUsage:
        usage.diskIOUsage !== undefined ? usage.diskIOUsage : existing.diskIOUsage,
      bandwidthUsage:
        usage.bandwidthUsage !== undefined
          ? usage.bandwidthUsage
          : existing.bandwidthUsage,
      timestamp: Date.now(),
    };

    this.resourceUsage.set(sessionId, updated);

    // Check for violations
    this.checkQuotaViolations(sessionId);

    return updated;
  }

  /**
   * Check for quota violations and throttle if necessary
   */
  private checkQuotaViolations(sessionId: string): void {
    const quota = this.activeQuotas.get(sessionId);
    const usage = this.resourceUsage.get(sessionId);

    if (!quota || !usage) {
      return;
    }

    const violations: QuotaViolation[] = [];

    // Check CPU
    if (usage.cpuUsage > quota.cpuLimit) {
      violations.push({
        sessionId,
        userId: quota.userId,
        violationType: "cpu",
        currentUsage: usage.cpuUsage,
        limit: quota.cpuLimit,
        severity: usage.cpuUsage > quota.cpuLimit * 1.2 ? "critical" : "warning",
        timestamp: Date.now(),
      });
    }

    // Check Memory
    if (usage.memoryUsage > quota.memoryLimit) {
      violations.push({
        sessionId,
        userId: quota.userId,
        violationType: "memory",
        currentUsage: usage.memoryUsage,
        limit: quota.memoryLimit,
        severity: usage.memoryUsage > quota.memoryLimit * 1.2 ? "critical" : "warning",
        timestamp: Date.now(),
      });
    }

    // Check Disk I/O
    if (usage.diskIOUsage > quota.diskIOLimit) {
      violations.push({
        sessionId,
        userId: quota.userId,
        violationType: "diskIO",
        currentUsage: usage.diskIOUsage,
        limit: quota.diskIOLimit,
        severity: usage.diskIOUsage > quota.diskIOLimit * 1.2 ? "critical" : "warning",
        timestamp: Date.now(),
      });
    }

    // Check Bandwidth
    if (usage.bandwidthUsage > quota.bandwidthLimit) {
      violations.push({
        sessionId,
        userId: quota.userId,
        violationType: "bandwidth",
        currentUsage: usage.bandwidthUsage,
        limit: quota.bandwidthLimit,
        severity:
          usage.bandwidthUsage > quota.bandwidthLimit * 1.2 ? "critical" : "warning",
        timestamp: Date.now(),
      });
    }

    // Store violations
    if (violations.length > 0) {
      const history = this.violationHistory.get(sessionId) || [];
      history.push(...violations);
      this.violationHistory.set(sessionId, history.slice(-100)); // Keep last 100

      quota.violations += violations.length;
      quota.lastViolationTime = Date.now();

      // Throttle if critical
      const hasCritical = violations.some((v) => v.severity === "critical");
      if (hasCritical) {
        quota.status = "throttled";
        this.emit("quotaThrottled", { sessionId, violations });
        logger.warn(`Quota throttled for session ${sessionId}`, {
          violations: violations.length,
        });
      } else {
        this.emit("quotaWarning", { sessionId, violations });
        logger.info(`Quota warning for session ${sessionId}`, {
          violations: violations.length,
        });
      }
    }
  }

  /**
   * Get current resource usage for a session
   */
  public getResourceUsage(sessionId: string): ResourceUsage | undefined {
    return this.resourceUsage.get(sessionId);
  }

  /**
   * Get quota enforcement for a session
   */
  public getQuotaEnforcement(sessionId: string): QuotaEnforcement | undefined {
    return this.activeQuotas.get(sessionId);
  }

  /**
   * Update quota tier for a session
   */
  public updateQuotaTier(sessionId: string, tier: QuotaTier): QuotaEnforcement {
    const quota = this.activeQuotas.get(sessionId);
    if (!quota) {
      throw new Error(`Quota not found for session ${sessionId}`);
    }

    const config = this.quotaConfigs.get(tier);
    if (!config) {
      throw new Error(`Invalid quota tier: ${tier}`);
    }

    quota.tier = tier;
    quota.cpuLimit = config.cpuLimit;
    quota.memoryLimit = config.memoryLimit;
    quota.diskIOLimit = config.diskIOLimit;
    quota.bandwidthLimit = config.bandwidthLimit;
    quota.updatedAt = Date.now();
    quota.violations = 0; // Reset on tier change

    this.emit("quotaTierUpdated", quota);
    logger.info(`Quota tier updated for session ${sessionId}`, { tier });

    return quota;
  }

  /**
   * Pause quota enforcement for a session
   */
  public pauseQuota(sessionId: string): QuotaEnforcement {
    const quota = this.activeQuotas.get(sessionId);
    if (!quota) {
      throw new Error(`Quota not found for session ${sessionId}`);
    }

    quota.status = "paused";
    quota.updatedAt = Date.now();

    this.emit("quotaPaused", quota);
    logger.info(`Quota paused for session ${sessionId}`);

    return quota;
  }

  /**
   * Resume quota enforcement for a session
   */
  public resumeQuota(sessionId: string): QuotaEnforcement {
    const quota = this.activeQuotas.get(sessionId);
    if (!quota) {
      throw new Error(`Quota not found for session ${sessionId}`);
    }

    quota.status = "active";
    quota.updatedAt = Date.now();

    this.emit("quotaResumed", quota);
    logger.info(`Quota resumed for session ${sessionId}`);

    return quota;
  }

  /**
   * Remove quota enforcement for a session
   */
  public removeQuota(sessionId: string): boolean {
    const quota = this.activeQuotas.get(sessionId);
    if (!quota) {
      return false;
    }

    this.activeQuotas.delete(sessionId);
    this.resourceUsage.delete(sessionId);
    this.violationHistory.delete(sessionId);

    this.emit("quotaRemoved", { sessionId });
    logger.info(`Quota removed for session ${sessionId}`);

    return true;
  }

  /**
   * Get violation history for a session
   */
  public getViolationHistory(sessionId: string): QuotaViolation[] {
    return this.violationHistory.get(sessionId) || [];
  }

  /**
   * Get all active quotas
   */
  public getAllActiveQuotas(): QuotaEnforcement[] {
    return Array.from(this.activeQuotas.values());
  }

  /**
   * Get quota tier configuration
   */
  public getQuotaConfig(tier: QuotaTier): QuotaConfig | undefined {
    return this.quotaConfigs.get(tier);
  }

  /**
   * Get all quota tier configurations
   */
  public getAllQuotaConfigs(): Map<QuotaTier, QuotaConfig> {
    return new Map(this.quotaConfigs);
  }

  /**
   * Calculate quota utilization percentage
   */
  public calculateUtilization(sessionId: string): {
    cpu: number;
    memory: number;
    diskIO: number;
    bandwidth: number;
    overallPercentage: number;
  } {
    const quota = this.activeQuotas.get(sessionId);
    const usage = this.resourceUsage.get(sessionId);

    if (!quota || !usage) {
      return {
        cpu: 0,
        memory: 0,
        diskIO: 0,
        bandwidth: 0,
        overallPercentage: 0,
      };
    }

    const cpu = (usage.cpuUsage / quota.cpuLimit) * 100;
    const memory = (usage.memoryUsage / quota.memoryLimit) * 100;
    const diskIO = (usage.diskIOUsage / quota.diskIOLimit) * 100;
    const bandwidth = (usage.bandwidthUsage / quota.bandwidthLimit) * 100;

    const overallPercentage = (cpu + memory + diskIO + bandwidth) / 4;

    return {
      cpu: Math.min(cpu, 100),
      memory: Math.min(memory, 100),
      diskIO: Math.min(diskIO, 100),
      bandwidth: Math.min(bandwidth, 100),
      overallPercentage: Math.min(overallPercentage, 100),
    };
  }

  /**
   * Get statistics for all sessions
   */
  public getStatistics(): {
    totalActiveSessions: number;
    totalViolations: number;
    throttledSessions: number;
    averageUtilization: number;
  } {
    const quotas = Array.from(this.activeQuotas.values());
    const throttledCount = quotas.filter((q) => q.status === "throttled").length;
    const totalViolations = quotas.reduce((sum, q) => sum + q.violations, 0);

    let totalUtilization = 0;
    quotas.forEach((quota) => {
      const util = this.calculateUtilization(quota.sessionId);
      totalUtilization += util.overallPercentage;
    });

    const averageUtilization =
      quotas.length > 0 ? totalUtilization / quotas.length : 0;

    return {
      totalActiveSessions: quotas.length,
      totalViolations,
      throttledSessions: throttledCount,
      averageUtilization,
    };
  }

  /**
   * Start monitoring interval (for testing/simulation)
   */
  public startMonitoring(intervalMs: number = 5000): void {
    if (this.monitoringInterval) {
      return;
    }

    this.monitoringInterval = setInterval(() => {
      const quotas = Array.from(this.activeQuotas.values());
      quotas.forEach((quota) => {
        this.checkQuotaViolations(quota.sessionId);
      });
    }, intervalMs);

    logger.info(`Resource quota monitoring started`, { intervalMs });
  }

  /**
   * Stop monitoring interval
   */
  public stopMonitoring(): void {
    if (this.monitoringInterval) {
      clearInterval(this.monitoringInterval);
      this.monitoringInterval = null;
      logger.info("Resource quota monitoring stopped");
    }
  }

  /**
   * Reset service for testing
   */
  public reset(): void {
    this.stopMonitoring();
    this.activeQuotas.clear();
    this.resourceUsage.clear();
    this.violationHistory.clear();
    this.removeAllListeners();
    logger.debug("Resource quota service reset");
  }
}

// Export singleton instance
const quotaService = new ResourceQuotaService();
export default quotaService;
