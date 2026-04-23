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
  storageUsage?: number; // bytes
  gpuUsage?: number; // GPU count
  timestamp: number; // Unix timestamp
}

/**
 * Quota enforcement record
 */
export interface QuotaEnforcement {
  sessionId: string;
  userId: string;
  projectId?: string;
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
 * Cost rate card used to convert usage into monthly estimates.
 */
export interface CostRateCard {
  cpuHourUsd: number;
  ramGbHourUsd: number;
  storageGbDayUsd: number;
  gpuHourUsd: number;
}

/**
 * Resource sample used to accumulate cost.
 */
export interface CostUsageSample {
  durationMs: number;
  cpuMillicores: number;
  memoryBytes: number;
  storageBytes?: number;
  gpuCount?: number;
  projectId?: string;
}

/**
 * Accrued cost record for a single session sample.
 */
export interface SessionCostEntry {
  sessionId: string;
  userId: string;
  projectId: string;
  monthKey: string;
  durationMs: number;
  cpuHours: number;
  ramGbHours: number;
  storageGbDays: number;
  gpuHours: number;
  estimatedCostUsd: number;
  timestamp: number;
}

/**
 * Cost budget configuration and current status.
 */
export interface CostBudget {
  scope: "user" | "project";
  identifier: string;
  monthKey: string;
  monthlyBudgetUsd: number;
  spentUsd: number;
  remainingUsd: number;
  utilizationPercent: number;
  status: "healthy" | "warning" | "critical" | "exceeded";
  updatedAt: number;
}

/**
 * Cost alert emitted when a budget threshold is crossed.
 */
export interface CostAlert {
  scope: "user" | "project";
  identifier: string;
  monthKey: string;
  monthlyBudgetUsd: number;
  spentUsd: number;
  remainingUsd: number;
  utilizationPercent: number;
  threshold: number;
  severity: "warning" | "critical";
  message: string;
  timestamp: number;
}

/**
 * Aggregated monthly cost summary.
 */
export interface CostSummary {
  scope: "total" | "user" | "project";
  identifier: string;
  cpuHours: number;
  ramGbHours: number;
  storageGbDays: number;
  gpuHours: number;
  estimatedCostUsd: number;
  sampleCount: number;
  budget?: CostBudget;
}

/**
 * Monthly report with user/project rollups and budget alerts.
 */
export interface MonthlyCostReport {
  monthKey: string;
  totals: CostSummary;
  byUser: CostSummary[];
  byProject: CostSummary[];
  budgets: CostBudget[];
  alerts: CostAlert[];
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
  private costLedger: Map<string, SessionCostEntry[]> = new Map();
  private costBudgets: Map<string, CostBudget> = new Map();
  private costAlerts: Map<string, CostAlert> = new Map();
  private sessionProjects: Map<string, string> = new Map();
  private costRates: CostRateCard = {
    cpuHourUsd: 0.05,
    ramGbHourUsd: 0.01,
    storageGbDayUsd: 0.023 / 30,
    gpuHourUsd: 0.95,
  };
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
    tier: QuotaTier,
    context?: { projectId?: string }
  ): QuotaEnforcement {
    const config = this.quotaConfigs.get(tier);
    if (!config) {
      throw new Error(`Invalid quota tier: ${tier}`);
    }

    const projectId = context?.projectId ?? "default";

    const enforcement: QuotaEnforcement = {
      sessionId,
      userId,
      projectId,
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
    this.sessionProjects.set(sessionId, projectId);
    this.emit("quotaEnforced", enforcement);
    logger.info(`Quota enforced for session ${sessionId}`, {
      userId,
      tier,
      projectId,
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
      storageUsage: 0,
      gpuUsage: 0,
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
      storageUsage:
        usage.storageUsage !== undefined ? usage.storageUsage : existing.storageUsage,
      gpuUsage: usage.gpuUsage !== undefined ? usage.gpuUsage : existing.gpuUsage,
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

  private getMonthKey(timestamp: number = Date.now()): string {
    const date = new Date(timestamp);
    const month = String(date.getUTCMonth() + 1).padStart(2, "0");
    return `${date.getUTCFullYear()}-${month}`;
  }

  private getCostRecordBucket(monthKey: string): SessionCostEntry[] {
    const bucket = this.costLedger.get(monthKey);
    if (bucket) {
      return bucket;
    }

    const created: SessionCostEntry[] = [];
    this.costLedger.set(monthKey, created);
    return created;
  }

  private getCostBudgetKey(
    scope: "user" | "project",
    identifier: string,
    monthKey: string
  ): string {
    return `${scope}:${identifier}:${monthKey}`;
  }

  private summarizeCostEntries(
    entries: SessionCostEntry[],
    scope: "user" | "project"
  ): CostSummary[] {
    const summaries = new Map<string, CostSummary>();

    for (const entry of entries) {
      const identifier = scope === "user" ? entry.userId : entry.projectId;
      const current = summaries.get(identifier) ?? {
        scope,
        identifier,
        cpuHours: 0,
        ramGbHours: 0,
        storageGbDays: 0,
        gpuHours: 0,
        estimatedCostUsd: 0,
        sampleCount: 0,
      };

      current.cpuHours += entry.cpuHours;
      current.ramGbHours += entry.ramGbHours;
      current.storageGbDays += entry.storageGbDays;
      current.gpuHours += entry.gpuHours;
      current.estimatedCostUsd += entry.estimatedCostUsd;
      current.sampleCount += 1;
      summaries.set(identifier, current);
    }

    return Array.from(summaries.values()).sort(
      (left, right) => right.estimatedCostUsd - left.estimatedCostUsd
    );
  }

  private calculateBudgetStatus(spentUsd: number, monthlyBudgetUsd: number): CostBudget["status"] {
    if (spentUsd >= monthlyBudgetUsd) {
      return "exceeded";
    }

    const utilizationPercent = monthlyBudgetUsd > 0 ? (spentUsd / monthlyBudgetUsd) * 100 : 0;
    if (utilizationPercent >= 90) {
      return "critical";
    }

    if (utilizationPercent >= 75) {
      return "warning";
    }

    return "healthy";
  }

  private calculateSpentAmount(
    scope: "user" | "project",
    identifier: string,
    monthKey: string
  ): number {
    const entries = this.costLedger.get(monthKey) || [];

    return entries
      .filter((entry) => (scope === "user" ? entry.userId : entry.projectId) === identifier)
      .reduce((sum, entry) => sum + entry.estimatedCostUsd, 0);
  }

  private updateCostBudget(
    scope: "user" | "project",
    identifier: string,
    monthKey: string
  ): CostBudget | undefined {
    const key = this.getCostBudgetKey(scope, identifier, monthKey);
    const budget = this.costBudgets.get(key);

    if (!budget) {
      return undefined;
    }

    const spentUsd = this.calculateSpentAmount(scope, identifier, monthKey);
    const remainingUsd = Math.max(budget.monthlyBudgetUsd - spentUsd, 0);
    const utilizationPercent =
      budget.monthlyBudgetUsd > 0 ? (spentUsd / budget.monthlyBudgetUsd) * 100 : 0;
    const status = this.calculateBudgetStatus(spentUsd, budget.monthlyBudgetUsd);
    const updated: CostBudget = {
      ...budget,
      spentUsd,
      remainingUsd,
      utilizationPercent,
      status,
      updatedAt: Date.now(),
    };

    this.costBudgets.set(key, updated);

    const previousStatus = budget.status;
    if (status === "healthy") {
      this.costAlerts.delete(key);
    } else if (status !== previousStatus) {
      const threshold = status === "critical" || status === "exceeded" ? 90 : 75;
      const alert: CostAlert = {
        scope,
        identifier,
        monthKey,
        monthlyBudgetUsd: budget.monthlyBudgetUsd,
        spentUsd,
        remainingUsd,
        utilizationPercent,
        threshold,
        severity: status === "critical" || status === "exceeded" ? "critical" : "warning",
        message:
          status === "exceeded"
            ? `${scope} ${identifier} budget exceeded for ${monthKey}`
            : `${scope} ${identifier} budget nearing limit for ${monthKey}`,
        timestamp: Date.now(),
      };

      this.costAlerts.set(key, alert);
      this.emit("costBudgetAlert", alert);
      logger.warn(`Cost budget alert for ${scope} ${identifier}`, {
        monthKey,
        spentUsd,
        monthlyBudgetUsd: budget.monthlyBudgetUsd,
        status,
      });
    }

    return updated;
  }

  /**
   * Record a cost sample for a session.
   */
  public recordSessionCost(sessionId: string, sample: CostUsageSample): SessionCostEntry {
    if (sample.durationMs <= 0) {
      throw new Error("durationMs must be greater than zero");
    }

    const quota = this.activeQuotas.get(sessionId);
    if (!quota) {
      throw new Error(`Quota not found for session ${sessionId}`);
    }

    const monthKey = this.getMonthKey();
    const projectId =
      sample.projectId ?? quota.projectId ?? this.sessionProjects.get(sessionId) ?? "default";
    const durationHours = sample.durationMs / 3_600_000;
    const cpuHours = (sample.cpuMillicores / 1000) * durationHours;
    const ramGbHours = (sample.memoryBytes / (1024 ** 3)) * durationHours;
    const storageGbDays =
      ((sample.storageBytes ?? 0) / (1024 ** 3)) * (sample.durationMs / 86_400_000);
    const gpuHours = (sample.gpuCount ?? 0) * durationHours;
    const estimatedCostUsd =
      cpuHours * this.costRates.cpuHourUsd +
      ramGbHours * this.costRates.ramGbHourUsd +
      storageGbDays * this.costRates.storageGbDayUsd +
      gpuHours * this.costRates.gpuHourUsd;

    const entry: SessionCostEntry = {
      sessionId,
      userId: quota.userId,
      projectId,
      monthKey,
      durationMs: sample.durationMs,
      cpuHours,
      ramGbHours,
      storageGbDays,
      gpuHours,
      estimatedCostUsd,
      timestamp: Date.now(),
    };

    const bucket = this.getCostRecordBucket(monthKey);
    bucket.push(entry);

    this.sessionProjects.set(sessionId, projectId);
    this.updateCostBudget("user", quota.userId, monthKey);
    this.updateCostBudget("project", projectId, monthKey);

    this.emit("costRecorded", entry);
    logger.info(`Cost recorded for session ${sessionId}`, {
      projectId,
      estimatedCostUsd: Number(estimatedCostUsd.toFixed(6)),
    });

    return entry;
  }

  /**
   * Set or update a monthly budget for a user or project.
   */
  public setCostBudget(
    scope: "user" | "project",
    identifier: string,
    monthlyBudgetUsd: number,
    monthKey: string = this.getMonthKey()
  ): CostBudget {
    if (monthlyBudgetUsd <= 0) {
      throw new Error("monthlyBudgetUsd must be greater than zero");
    }

    const spentUsd = this.calculateSpentAmount(scope, identifier, monthKey);
    const remainingUsd = Math.max(monthlyBudgetUsd - spentUsd, 0);
    const utilizationPercent =
      monthlyBudgetUsd > 0 ? (spentUsd / monthlyBudgetUsd) * 100 : 0;
    const status = this.calculateBudgetStatus(spentUsd, monthlyBudgetUsd);

    const budget: CostBudget = {
      scope,
      identifier,
      monthKey,
      monthlyBudgetUsd,
      spentUsd,
      remainingUsd,
      utilizationPercent,
      status,
      updatedAt: Date.now(),
    };

    const key = this.getCostBudgetKey(scope, identifier, monthKey);
    this.costBudgets.set(key, budget);
    this.updateCostBudget(scope, identifier, monthKey);

    logger.info(`Cost budget configured for ${scope} ${identifier}`, {
      monthKey,
      monthlyBudgetUsd,
    });

    return this.costBudgets.get(key) || budget;
  }

  /**
   * Get monthly cost budgets for a month.
   */
  public getCostBudgets(monthKey?: string): CostBudget[] {
    const resolvedMonthKey = monthKey ?? this.getMonthKey();

    return Array.from(this.costBudgets.values())
      .filter((budget) => budget.monthKey === resolvedMonthKey)
      .sort((left, right) => right.utilizationPercent - left.utilizationPercent);
  }

  /**
   * Get active cost alerts for a month.
   */
  public getCostAlerts(monthKey?: string): CostAlert[] {
    const resolvedMonthKey = monthKey ?? this.getMonthKey();

    return Array.from(this.costAlerts.values())
      .filter((alert) => alert.monthKey === resolvedMonthKey)
      .sort((left, right) => right.utilizationPercent - left.utilizationPercent);
  }

  /**
   * Build a monthly cost report.
   */
  public getMonthlyCostReport(monthKey?: string): MonthlyCostReport {
    const resolvedMonthKey = monthKey ?? this.getMonthKey();
    const entries = this.costLedger.get(resolvedMonthKey) || [];
    const byUser = this.summarizeCostEntries(entries, "user").map((summary) => ({
      ...summary,
      budget: this.costBudgets.get(this.getCostBudgetKey("user", summary.identifier, resolvedMonthKey)),
    }));
    const byProject = this.summarizeCostEntries(entries, "project").map((summary) => ({
      ...summary,
      budget: this.costBudgets.get(this.getCostBudgetKey("project", summary.identifier, resolvedMonthKey)),
    }));
    const totals: CostSummary = entries.reduce<CostSummary>(
      (accumulator, entry) => ({
        scope: "total",
        identifier: resolvedMonthKey,
        cpuHours: accumulator.cpuHours + entry.cpuHours,
        ramGbHours: accumulator.ramGbHours + entry.ramGbHours,
        storageGbDays: accumulator.storageGbDays + entry.storageGbDays,
        gpuHours: accumulator.gpuHours + entry.gpuHours,
        estimatedCostUsd: accumulator.estimatedCostUsd + entry.estimatedCostUsd,
        sampleCount: accumulator.sampleCount + 1,
      }),
      {
        scope: "total",
        identifier: resolvedMonthKey,
        cpuHours: 0,
        ramGbHours: 0,
        storageGbDays: 0,
        gpuHours: 0,
        estimatedCostUsd: 0,
        sampleCount: 0,
      }
    );

    return {
      monthKey: resolvedMonthKey,
      totals,
      byUser,
      byProject,
      budgets: this.getCostBudgets(resolvedMonthKey),
      alerts: this.getCostAlerts(resolvedMonthKey),
    };
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
   * Get cost entries for a month.
   */
  public getCostEntries(monthKey?: string): SessionCostEntry[] {
    const resolvedMonthKey = monthKey ?? this.getMonthKey();
    return [...(this.costLedger.get(resolvedMonthKey) || [])];
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
        const usage = this.resourceUsage.get(quota.sessionId);

        if (usage) {
          this.recordSessionCost(quota.sessionId, {
            durationMs: intervalMs,
            cpuMillicores: usage.cpuUsage,
            memoryBytes: usage.memoryUsage,
            storageBytes: usage.storageUsage ?? 0,
            gpuCount: usage.gpuUsage ?? 0,
            projectId: quota.projectId,
          });
        }
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
    this.costLedger.clear();
    this.costBudgets.clear();
    this.costAlerts.clear();
    this.sessionProjects.clear();
    this.removeAllListeners();
    logger.debug("Resource quota service reset");
  }
}

// Export singleton instance
const quotaService = new ResourceQuotaService();
export default quotaService;
