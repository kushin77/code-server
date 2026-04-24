/**
 * Resource Quotas Service
 * cgroups-based CPU, RAM, disk I/O, and bandwidth enforcement
 */

import { EventEmitter } from 'events';
import { AuditService } from '../audit/audit-service.js';
import { 
  ResourceQuota,
  QuotaTier,
  ResourceUsage,
  ResourceCostReport,
  ResourceCostTotals,
  MonthlyCostReport,
  BudgetAlert,
  BudgetAlertScope,
  BudgetThresholds,
  EnforcementStatus,
  LimitExceededEvent,
  EnforcementAction,
  EnforcementPolicy,
  QuotaStats,
  QuotaHistoryEntry,
  QuotaServiceConfig,
  CPUQuota,
  MemoryQuota,
  DiskIOQuota,
  BandwidthQuota,
} from './types.js';

/**
 * Resource Quotas Service
 * Manage cgroups-based resource enforcement
 */
export class ResourceQuotasService extends EventEmitter {
  private static quotaSequence = 0;
  private static budgetAlertSequence = 0;
  private isInitialized = false;
  private quotas: Map<string, ResourceQuota> = new Map();
  private usageHistory: Map<string, QuotaHistoryEntry[]> = new Map();
  private enforcementStatuses: Map<string, EnforcementStatus> = new Map();
  private budgetThresholds: Map<string, BudgetThresholds> = new Map();
  private budgetAlerts: Map<string, BudgetAlert> = new Map();
  private auditService?: AuditService;
  private config: QuotaServiceConfig;
  private stats: QuotaStats = {
    totalQuotas: 0,
    quotasByTier: {},
    quotasEnforced: 0,
    quotasFailed: 0,
    totalUsersWithQuotas: 0,
    totalWorkspacesWithQuotas: 0,
    limitExceededCount: {},
    averageCPUUsage: 0,
    averageMemoryUsage: 0,
  };
  private samplingTimer?: NodeJS.Timeout;

  // Predefined quota tiers
  private tiers: Map<string, QuotaTier> = new Map([
    ['small', {
      name: 'small',
      cpu: { cores: 0.5, period: 100000, quota: 50000 },
      memory: { limitMB: 512, swapMB: 256 },
      diskIO: { readBytesPerSec: 10485760, writeBytesPerSec: 10485760, iopsRead: 100, iopsWrite: 100 },
      bandwidth: { ingressMbps: 10, egressMbps: 10, burstMbps: 20 },
      description: 'Small workspace - single developer',
      maxConcurrentSessions: 1,
    }],
    ['medium', {
      name: 'medium',
      cpu: { cores: 2, period: 100000, quota: 200000 },
      memory: { limitMB: 2048, swapMB: 1024 },
      diskIO: { readBytesPerSec: 52428800, writeBytesPerSec: 52428800, iopsRead: 500, iopsWrite: 500 },
      bandwidth: { ingressMbps: 50, egressMbps: 50, burstMbps: 100 },
      description: 'Medium workspace - team collaboration',
      maxConcurrentSessions: 5,
    }],
    ['large', {
      name: 'large',
      cpu: { cores: 4, period: 100000, quota: 400000 },
      memory: { limitMB: 8192, swapMB: 4096 },
      diskIO: { readBytesPerSec: 209715200, writeBytesPerSec: 209715200, iopsRead: 2000, iopsWrite: 2000 },
      bandwidth: { ingressMbps: 200, egressMbps: 200, burstMbps: 400 },
      description: 'Large workspace - enterprise use',
      maxConcurrentSessions: 20,
    }],
  ]);

  constructor(config?: Partial<QuotaServiceConfig>, auditService?: AuditService) {
    super();
    this.auditService = auditService;
    this.config = {
      enabled: true,
      cgroupsEnabled: false, // Mock by default
      enforcementPolicy: {
        cpuThresholdPercent: 80,
        memoryThresholdPercent: 85,
        diskIOThresholdPercent: 90,
        bandwidthThresholdPercent: 90,
        onCPUExceeded: 'throttle',
        onMemoryExceeded: 'throttle',
        onDiskIOExceeded: 'warn',
        onBandwidthExceeded: 'warn',
        killGracePeriodMs: 5000,
      },
      maxHistoryEntries: 1000,
      samplingIntervalMs: 5000,
      defaultTier: 'medium',
      ...config,
    };
  }

  /**
   * Initialize service
   */
  async initialize(): Promise<void> {
    if (this.isInitialized) return;
    this.isInitialized = true;

    if (this.config.enabled) {
      // Start sampling timer for usage monitoring
      this.samplingTimer = setInterval(
        () => this.sampleUsage(),
        this.config.samplingIntervalMs
      );
    }

    this.emit('initialized');
  }

  /**
   * Shutdown service
   */
  async shutdown(): Promise<void> {
    if (this.samplingTimer) clearInterval(this.samplingTimer);
    this.emit('shutdown');
  }

  /**
   * Create quota from tier
   */
  async createQuotaFromTier(
    userId: string,
    workspaceId: string,
    tierName: 'small' | 'medium' | 'large'
  ): Promise<ResourceQuota> {
    if (!this.isInitialized) throw new Error('Service not initialized');

    const tier = this.tiers.get(tierName);
    if (!tier) throw new Error(`Unknown tier: ${tierName}`);
    const quotaId = this.buildQuotaId('quota', userId, workspaceId);

    const quota: ResourceQuota = {
      id: quotaId,
      name: tierName,
      userId,
      workspaceId,
      projectId: workspaceId,
      cpu: { ...tier.cpu },
      memory: { ...tier.memory },
      diskIO: { ...tier.diskIO },
      bandwidth: { ...tier.bandwidth },
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };

    this.quotas.set(quota.id, quota);
    this.usageHistory.set(quota.id, []);
    
    // Try to enforce via cgroups
    await this.enforceQuota(quota);
    
    if (this.auditService) {
      this.auditService.emit({
        userId,
        action: 'create',
        resourceType: 'quota',
        resource: `quota:${quota.id}`,
        metadata: {
          quotaId: quota.id,
          workspaceId,
          tier: tierName,
          cpuCores: tier.cpu.cores,
          memoryMB: tier.memory.limitMB,
          diskIOReadBytesPerSec: tier.diskIO.readBytesPerSec,
          bandwidthIngressMbps: tier.bandwidth.ingressMbps,
        },
        reason: 'SOC2: Resource quota creation from tier',
      });
    }
    
    this.updateStats();
    this.emit('quota-created', { quota });

    return quota;
  }

  /**
   * Create custom quota
   */
  async createCustomQuota(
    userId: string,
    workspaceId: string,
    cpuCores: number,
    memoryMB: number,
    readBytesPerSec: number,
    writeBytesPerSec: number,
    ingressMbps: number,
    egressMbps: number
  ): Promise<ResourceQuota> {
    if (!this.isInitialized) throw new Error('Service not initialized');
    const quotaId = this.buildQuotaId('quota-custom', userId, workspaceId);

    const quota: ResourceQuota = {
      id: quotaId,
      name: 'custom',
      userId,
      workspaceId,
      projectId: workspaceId,
      cpu: { cores: cpuCores, period: 100000, quota: Math.floor(cpuCores * 100000) },
      memory: { limitMB: memoryMB },
      diskIO: { readBytesPerSec, writeBytesPerSec },
      bandwidth: { ingressMbps, egressMbps },
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };

    this.quotas.set(quota.id, quota);
    this.usageHistory.set(quota.id, []);
    
    await this.enforceQuota(quota);
    
    this.updateStats();
    this.emit('quota-created', { quota });

    return quota;
  }

  /**
   * Get quota by ID
   */
  async getQuota(quotaId: string): Promise<ResourceQuota | undefined> {
    return this.quotas.get(quotaId);
  }

  /**
   * Get quotas for user
   */
  async getUserQuotas(userId: string): Promise<ResourceQuota[]> {
    const result: ResourceQuota[] = [];
    for (const quota of this.quotas.values()) {
      if (quota.userId === userId) result.push(quota);
    }
    return result;
  }

  /**
   * Get quotas for workspace
   */
  async getWorkspaceQuotas(workspaceId: string): Promise<ResourceQuota[]> {
    const result: ResourceQuota[] = [];
    for (const quota of this.quotas.values()) {
      if (quota.workspaceId === workspaceId) result.push(quota);
    }
    return result;
  }

  /**
   * Update quota tier
   */
  async updateQuotaTier(quotaId: string, newTierName: string): Promise<ResourceQuota> {
    const quota = this.quotas.get(quotaId);
    if (!quota) throw new Error(`Quota not found: ${quotaId}`);

    const oldTierName = quota.name;
    const tier = this.tiers.get(newTierName);
    if (!tier) throw new Error(`Unknown tier: ${newTierName}`);

    quota.name = newTierName;
    quota.cpu = { ...tier.cpu };
    quota.memory = { ...tier.memory };
    quota.diskIO = { ...tier.diskIO };
    quota.bandwidth = { ...tier.bandwidth };
    quota.updatedAt = Date.now();

    await this.enforceQuota(quota);

    if (this.auditService) {
      this.auditService.emit({
        userId: quota.userId,
        action: 'update',
        resourceType: 'quota',
        resource: `quota:${quotaId}`,
        metadata: {
          quotaId,
          workspaceId: quota.workspaceId,
          oldTier: oldTierName,
          newTier: newTierName,
          cpuCores: tier.cpu.cores,
          memoryMB: tier.memory.limitMB,
        },
        reason: 'SOC2: Resource quota tier upgrade/downgrade',
      });
    }

    this.updateStats();
    this.emit('quota-updated', { quotaId, newTierName });

    return quota;
  }

  /**
   * Get current usage for quota
   */
  async getUsage(quotaId: string): Promise<ResourceUsage> {
    // Simulate realistic usage based on quota tier
    const quota = this.quotas.get(quotaId);
    if (!quota) throw new Error(`Quota not found: ${quotaId}`);

    // Mock usage (would read from cgroups in production)
    const cpuUsage = Math.random() * quota.cpu.cores * 100;
    const memoryUsage = Math.random() * quota.memory.limitMB;
    const readUsage = Math.random() * quota.diskIO.readBytesPerSec;
    const writeUsage = Math.random() * quota.diskIO.writeBytesPerSec;
    const ingressUsage = Math.random() * quota.bandwidth.ingressMbps;
    const egressUsage = Math.random() * quota.bandwidth.egressMbps;

    const usage: ResourceUsage = {
      cpuPercent: (cpuUsage / (quota.cpu.cores * 100)) * 100,
      cpuCoresUsed: cpuUsage / 100,
      memoryMB: memoryUsage,
      memoryPercent: (memoryUsage / quota.memory.limitMB) * 100,
      diskIOReadBytesPerSec: readUsage,
      diskIOWriteBytesPerSec: writeUsage,
      diskIOReadPercent: (readUsage / quota.diskIO.readBytesPerSec) * 100,
      diskIOWritePercent: (writeUsage / quota.diskIO.writeBytesPerSec) * 100,
      ingressMbps: ingressUsage,
      egressMbps: egressUsage,
      ingressPercent: (ingressUsage / quota.bandwidth.ingressMbps) * 100,
      egressPercent: (egressUsage / quota.bandwidth.egressMbps) * 100,
      storageGBUsed: 0,
      gpuCountUsed: 0,
      timestamp: Date.now(),
    };

    return usage;
  }

  /**
   * Record a usage sample for later reporting
   */
  async recordUsageSample(quotaId: string, usage: ResourceUsage): Promise<void> {
    const quota = this.quotas.get(quotaId);
    if (!quota) throw new Error(`Quota not found: ${quotaId}`);

    const history = this.usageHistory.get(quotaId) || [];
    const entry: QuotaHistoryEntry = {
      quotaId,
      timestamp: usage.timestamp,
      usage,
    };

    if (usage.cpuPercent > (this.config.enforcementPolicy.cpuThresholdPercent || 80)) {
      const event: LimitExceededEvent = {
        quotaId,
        userId: quota.userId,
        workspaceId: quota.workspaceId,
        projectId: quota.projectId,
        limitType: 'cpu',
        currentUsage: usage.cpuPercent,
        limit: this.config.enforcementPolicy.cpuThresholdPercent || 80,
        timestamp: usage.timestamp,
        severity: usage.cpuPercent > 95 ? 'critical' : 'warning',
      };
      entry.limitExceeded = event;
      entry.action = this.config.enforcementPolicy.onCPUExceeded;
      this.stats.limitExceededCount['cpu'] = (this.stats.limitExceededCount['cpu'] || 0) + 1;
      this.emit('limit-exceeded', { event });
    }

    if (usage.memoryPercent > (this.config.enforcementPolicy.memoryThresholdPercent || 85)) {
      const event: LimitExceededEvent = {
        quotaId,
        userId: quota.userId,
        workspaceId: quota.workspaceId,
        projectId: quota.projectId,
        limitType: 'memory',
        currentUsage: usage.memoryPercent,
        limit: this.config.enforcementPolicy.memoryThresholdPercent || 85,
        timestamp: usage.timestamp,
        severity: usage.memoryPercent > 95 ? 'critical' : 'warning',
      };
      entry.limitExceeded = event;
      entry.action = this.config.enforcementPolicy.onMemoryExceeded;
      this.stats.limitExceededCount['memory'] = (this.stats.limitExceededCount['memory'] || 0) + 1;
      this.emit('limit-exceeded', { event });
    }

    history.push(entry);

    if (history.length > (this.config.maxHistoryEntries || 1000)) {
      history.splice(0, history.length - (this.config.maxHistoryEntries || 1000));
    }

    this.usageHistory.set(quotaId, history);
    this.emit('usage-sample-recorded', { quotaId, usage });
  }

  /**
   * Get usage history
   */
  async getUsageHistory(quotaId: string, limit?: number): Promise<QuotaHistoryEntry[]> {
    const history = this.usageHistory.get(quotaId) || [];
    if (limit) {
      return history.slice(-limit);
    }
    return history;
  }

  /**
   * Set budget thresholds for a quota, user, or workspace.
   */
  setBudgetThresholds(scope: BudgetAlertScope, scopeId: string, thresholds: BudgetThresholds): void {
    this.budgetThresholds.set(this.buildBudgetThresholdKey(scope, scopeId), { ...thresholds });
  }

  /**
   * Get budget thresholds for a scope.
   */
  getBudgetThresholds(scope: BudgetAlertScope, scopeId: string): BudgetThresholds | undefined {
    return this.budgetThresholds.get(this.buildBudgetThresholdKey(scope, scopeId));
  }

  /**
   * Get triggered budget alerts.
   */
  getBudgetAlerts(scope?: BudgetAlertScope, scopeId?: string): BudgetAlert[] {
    const alerts = Array.from(this.budgetAlerts.values());
    return alerts.filter((alert) => {
      if (scope && alert.scope !== scope) return false;
      if (scopeId && alert.scopeId !== scopeId) return false;
      return true;
    });
  }

  /**
   * Acknowledge a budget alert.
   */
  acknowledgeBudgetAlert(alertId: string, acknowledgedBy: string): boolean {
    const alert = this.budgetAlerts.get(alertId);
    if (!alert) return false;

    alert.acknowledgedAt = Date.now();
    alert.acknowledgedBy = acknowledgedBy;
    this.emit('budget-alert-acknowledged', { alertId, acknowledgedBy });
    return true;
  }

  /**
   * Get a cost summary for a quota over a time window
   */
  async getCostReport(
    quotaId: string,
    windowStart?: number,
    windowEnd?: number
  ): Promise<ResourceCostReport> {
    const quota = this.quotas.get(quotaId);
    if (!quota) throw new Error(`Quota not found: ${quotaId}`);

    const history = (this.usageHistory.get(quotaId) || [])
      .filter((entry) => {
        if (windowStart !== undefined && entry.timestamp < windowStart) return false;
        if (windowEnd !== undefined && entry.timestamp > windowEnd) return false;
        return true;
      })
      .sort((a, b) => a.timestamp - b.timestamp);

    const totals = this.calculateCostTotals(history, windowStart, windowEnd);
    return {
      quotaId,
      userId: quota.userId,
      workspaceId: quota.workspaceId,
      projectId: quota.projectId,
      windowStart: windowStart ?? (history[0]?.timestamp ?? quota.createdAt),
      windowEnd: windowEnd ?? (history[history.length - 1]?.timestamp ?? Date.now()),
      sampleCount: history.length,
      estimated: true,
      ...totals,
    };
  }

  /**
   * Get a monthly cost report grouped by quota
   */
  async getMonthlyCostReport(
    userId?: string,
    workspaceId?: string,
    windowStart?: number,
    windowEnd?: number
  ): Promise<MonthlyCostReport> {
    const now = Date.now();
    const monthStart = windowStart ?? new Date(now).setUTCDate(1);
    const monthEnd = windowEnd ?? now;

    const quotas = Array.from(this.quotas.values()).filter((quota) => {
      if (userId && quota.userId !== userId) return false;
      if (workspaceId && quota.workspaceId !== workspaceId) return false;
      return true;
    });

    const quotaReports = await Promise.all(
      quotas.map((quota) => this.getCostReport(quota.id, monthStart, monthEnd))
    );

    const totals = quotaReports.reduce<ResourceCostTotals>(
      (accumulator, report) => ({
        cpuHours: accumulator.cpuHours + report.cpuHours,
        memoryGbHours: accumulator.memoryGbHours + report.memoryGbHours,
        storageGbDays: accumulator.storageGbDays + report.storageGbDays,
        gpuHours: accumulator.gpuHours + report.gpuHours,
      }),
      {
        cpuHours: 0,
        memoryGbHours: 0,
        storageGbDays: 0,
        gpuHours: 0,
      }
    );

    for (const quotaReport of quotaReports) {
      this.evaluateBudgetAlerts(quotaReport);
    }

    this.evaluateBudgetAlerts({
      quotaId: `monthly-${workspaceId ?? userId ?? 'all'}`,
      userId,
      workspaceId,
      windowStart: monthStart,
      windowEnd: monthEnd,
      sampleCount: quotaReports.reduce((count, quotaReport) => count + quotaReport.sampleCount, 0),
      estimated: true,
      ...totals,
    });

    return {
      userId,
      workspaceId,
      projectId: workspaceId,
      windowStart: monthStart,
      windowEnd: monthEnd,
      totals,
      quotas: quotaReports,
    };
  }

  /**
   * Get enforcement status
   */
  async getEnforcementStatus(quotaId: string): Promise<EnforcementStatus | undefined> {
    return this.enforcementStatuses.get(quotaId);
  }

  /**
   * Get all quotas
   */
  async getAllQuotas(): Promise<ResourceQuota[]> {
    return Array.from(this.quotas.values());
  }

  /**
   * Delete quota
   */
  async deleteQuota(quotaId: string): Promise<void> {
    const quota = this.quotas.get(quotaId);
    if (!quota) throw new Error(`Quota not found: ${quotaId}`);

    this.quotas.delete(quotaId);
    this.usageHistory.delete(quotaId);
    this.enforcementStatuses.delete(quotaId);

    if (this.auditService) {
      this.auditService.emit({
        userId: quota.userId,
        action: 'delete',
        resourceType: 'quota',
        resource: `quota:${quotaId}`,
        metadata: {
          quotaId,
          workspaceId: quota.workspaceId,
          quotaTier: quota.name,
          deletedAt: Date.now(),
        },
        reason: 'SOC2: Resource quota deletion',
      });
    }

    this.updateStats();
    this.emit('quota-deleted', { quotaId });
  }

  /**
   * Get statistics
   */
  async getStatistics(): Promise<QuotaStats> {
    return { ...this.stats };
  }

  /**
   * Get tier details
   */
  getTier(tierName: string): QuotaTier | undefined {
    return this.tiers.get(tierName);
  }

  /**
   * Get all tiers
   */
  getAllTiers(): QuotaTier[] {
    return Array.from(this.tiers.values());
  }

  /**
   * Get enforcement policy
   */
  getEnforcementPolicy(): EnforcementPolicy {
    return { ...this.config.enforcementPolicy };
  }

  /**
   * Set enforcement policy
   */
  setEnforcementPolicy(policy: Partial<EnforcementPolicy>): void {
    this.config.enforcementPolicy = {
      ...this.config.enforcementPolicy,
      ...policy,
    };
  }

  /**
   * Private: Enforce quota via cgroups or mock
   */
  private async enforceQuota(quota: ResourceQuota): Promise<void> {
    const status: EnforcementStatus = {
      quotaId: quota.id,
      enforced: true,
      cgroupsAvailable: this.config.cgroupsEnabled,
      method: this.config.cgroupsEnabled ? 'cgroups' : 'mock',
      lastEnforcedAt: Date.now(),
    };

    try {
      if (this.config.cgroupsEnabled) {
        // In production, would write to /sys/fs/cgroup/...
        // For now, just mock the enforcement
        quota.cgroupPath = `/sys/fs/cgroup/kushnir-cloud/${quota.id}`;
      }
      
      this.stats.quotasEnforced++;
    } catch (error: any) {
      status.error = error.message;
      this.stats.quotasFailed++;
    }

    this.enforcementStatuses.set(quota.id, status);
  }

  /**
   * Private: Sample usage and check limits
   */
  private async sampleUsage(): Promise<void> {
    for (const quota of this.quotas.values()) {
      const usage = await this.getUsage(quota.id);
      await this.recordUsageSample(quota.id, usage);
    }
  }

  /**
   * Calculate cost totals for a time window
   */
  private calculateCostTotals(
    history: QuotaHistoryEntry[],
    windowStart?: number,
    windowEnd?: number
  ): ResourceCostTotals {
    if (history.length === 0) {
      return {
        cpuHours: 0,
        memoryGbHours: 0,
        storageGbDays: 0,
        gpuHours: 0,
      };
    }

    const resolvedWindowEnd = windowEnd ?? history[history.length - 1].timestamp;
    let cpuHours = 0;
    let memoryGbHours = 0;
    let storageGbDays = 0;
    let gpuHours = 0;

    for (let index = 0; index < history.length; index++) {
      const current = history[index];
      const nextTimestamp = history[index + 1]?.timestamp ?? resolvedWindowEnd;
      const segmentStart = Math.max(current.timestamp, windowStart ?? current.timestamp);
      const segmentEnd = Math.min(nextTimestamp, resolvedWindowEnd);

      if (segmentEnd <= segmentStart) {
        continue;
      }

      const segmentHours = (segmentEnd - segmentStart) / 3600000;
      cpuHours += current.usage.cpuCoresUsed * segmentHours;
      memoryGbHours += (current.usage.memoryMB / 1024) * segmentHours;
      storageGbDays += (current.usage.storageGBUsed ?? 0) * (segmentHours / 24);
      gpuHours += (current.usage.gpuCountUsed ?? 0) * segmentHours;
    }

    return {
      cpuHours,
      memoryGbHours,
      storageGbDays,
      gpuHours,
    };
  }

  /**
   * Evaluate budget alerts for a report and configured thresholds.
   */
  private evaluateBudgetAlerts(report: ResourceCostReport): BudgetAlert[] {
    const alerts: BudgetAlert[] = [];

    if (report.quotaId) {
      const quotaThresholds = this.getBudgetThresholds('quota', report.quotaId);
      if (quotaThresholds) {
        alerts.push(...this.createBudgetAlerts(report, 'quota', report.quotaId, quotaThresholds));
      }
    }

    if (report.userId) {
      const userThresholds = this.getBudgetThresholds('user', report.userId);
      if (userThresholds) {
        alerts.push(...this.createBudgetAlerts(report, 'user', report.userId, userThresholds));
      }
    }

    if (report.workspaceId) {
      const workspaceThresholds = this.getBudgetThresholds('workspace', report.workspaceId);
      if (workspaceThresholds) {
        alerts.push(...this.createBudgetAlerts(report, 'workspace', report.workspaceId, workspaceThresholds));
      }
    }

    return alerts;
  }

  /**
   * Create alerts for the metrics that exceed thresholds.
   */
  private createBudgetAlerts(
    report: ResourceCostReport,
    scope: BudgetAlertScope,
    scopeId: string,
    thresholds: BudgetThresholds
  ): BudgetAlert[] {
    const alerts: BudgetAlert[] = [];
    const metrics: Array<keyof ResourceCostTotals> = ['cpuHours', 'memoryGbHours', 'storageGbDays', 'gpuHours'];

    for (const metric of metrics) {
      const threshold = thresholds[metric];
      if (threshold === undefined) {
        continue;
      }

      const actual = report[metric];
      if (actual <= threshold) {
        continue;
      }

      const alertId = this.buildBudgetAlertId(scope, scopeId, metric, report.windowEnd);
      let alert = this.budgetAlerts.get(alertId);
      if (!alert) {
        alert = {
          alertId,
          scope,
          scopeId,
          quotaId: scope === 'quota' ? scopeId : report.quotaId,
          userId: report.userId,
          workspaceId: report.workspaceId,
          projectId: report.projectId,
          metric,
          threshold,
          actual,
          severity: actual >= threshold * 1.5 ? 'critical' : 'warning',
          message: `${metric} usage ${actual.toFixed(2)} exceeded budget threshold ${threshold.toFixed(2)}`,
          triggeredAt: Date.now(),
        };
        this.budgetAlerts.set(alertId, alert);
        this.emit('budget-alert-triggered', { alert });
      }

      alerts.push(alert);
    }

    return alerts;
  }

  /**
   * Build a unique budget threshold key.
   */
  private buildBudgetThresholdKey(scope: BudgetAlertScope, scopeId: string): string {
    return `${scope}:${scopeId}`;
  }

  /**
   * Build a unique budget alert identifier.
   */
  private buildBudgetAlertId(scope: BudgetAlertScope, scopeId: string, metric: keyof ResourceCostTotals, windowEnd: number): string {
    const sequence = ResourceQuotasService.budgetAlertSequence++;
    return `budget-${scope}-${scopeId}-${metric}-${windowEnd}-${sequence}`;
  }

  /**
   * Build a unique quota identifier.
   */
  private buildQuotaId(prefix: string, userId: string, workspaceId: string): string {
    const sequence = ResourceQuotasService.quotaSequence++;
    return `${prefix}-${userId}-${workspaceId}-${Date.now()}-${sequence}`;
  }

  /**
   * Private: Update statistics
   */
  private updateStats(): void {
    const quotas = Array.from(this.quotas.values());
    this.stats.totalQuotas = quotas.length;

    // Count by tier
    this.stats.quotasByTier = {};
    const users = new Set<string>();
    const workspaces = new Set<string>();

    for (const quota of quotas) {
      this.stats.quotasByTier[quota.name] = (this.stats.quotasByTier[quota.name] || 0) + 1;
      if (quota.userId) users.add(quota.userId);
      if (quota.workspaceId) workspaces.add(quota.workspaceId);
    }

    this.stats.totalUsersWithQuotas = users.size;
    this.stats.totalWorkspacesWithQuotas = workspaces.size;
  }

  /**
   * Get global singleton instance
   */
  private static instance: ResourceQuotasService;

  static getInstance(config?: Partial<QuotaServiceConfig>): ResourceQuotasService {
    if (!ResourceQuotasService.instance) {
      ResourceQuotasService.instance = new ResourceQuotasService(config);
    }
    return ResourceQuotasService.instance;
  }
}
