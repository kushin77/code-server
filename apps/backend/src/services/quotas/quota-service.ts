/**
 * Resource Quotas Service
 * CPU, memory, storage limits per workspace with enforcement and tracking
 */

import { EventEmitter } from 'events';
import {
  WorkspaceQuota,
  ResourceQuota,
  ResourceUsage,
  WorkspaceMetrics,
  EnforcementPolicy,
  QuotaAlert,
  QuotaServiceConfig,
  QuotaAdjustmentRequest,
  QuotaAdjustment,
  QuotaAuditEntry,
  QuotaStatistics,
  ResourceType,
} from './types.js';

/**
 * Resource Quotas Service
 * Manages workspace resource quotas with enforcement and monitoring
 */
export class QuotaService extends EventEmitter {
  private static instance: QuotaService;

  private quotas: Map<string, WorkspaceQuota> = new Map();
  private metrics: Map<string, WorkspaceMetrics[]> = new Map();
  private alerts: Map<string, QuotaAlert[]> = new Map();
  private policies: Map<string, EnforcementPolicy[]> = new Map();
  private adjustments: Map<string, QuotaAdjustment[]> = new Map();
  private auditLog: Map<string, QuotaAuditEntry[]> = new Map();
  private statistics: Map<string, QuotaStatistics> = new Map();
  private config: QuotaServiceConfig;

  private constructor(config?: Partial<QuotaServiceConfig>) {
    super();
    this.config = {
      enableEnforcement: true,
      enableMetricsCollection: true,
      metricsCollectionIntervalMs: 5000,
      warningThresholdPercent: 80,
      criticalThresholdPercent: 95,
      checkIntervalMs: 1000,
      maxAlertsPerWorkspace: 1000,
      maxMetricsPerWorkspace: 10000,
      maxAuditLogSize: 10000,
      storageBackend: 'memory',
      ...config,
    };
  }

  /**
   * Get or create singleton instance
   */
  static getInstance(config?: Partial<QuotaServiceConfig>): QuotaService {
    if (!QuotaService.instance) {
      QuotaService.instance = new QuotaService(config);
      QuotaService.instance.initialize();
    }
    return QuotaService.instance;
  }

  /**
   * Initialize service
   */
  private initialize(): void {
    this.emit('initialized', { timestamp: Date.now() });
  }

  /**
   * Shutdown service
   */
  shutdown(): void {
    this.quotas.clear();
    this.metrics.clear();
    this.alerts.clear();
    this.policies.clear();
    this.adjustments.clear();
    this.auditLog.clear();
    this.statistics.clear();
    this.emit('shutdown', { timestamp: Date.now() });
  }

  /**
   * Set quotas for a workspace
   */
  setWorkspaceQuota(
    workspaceId: string,
    userId: string,
    quotas: ResourceQuota[],
    ipAddress: string,
    userAgent: string
  ): WorkspaceQuota {
    const id = `quota-${workspaceId}-${Date.now()}-${Math.random().toString(16).slice(2)}`;

    const wsQuota: WorkspaceQuota = {
      id,
      workspaceId,
      userId,
      quotas,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      isActive: true,
    };

    this.quotas.set(wsQuota.id, wsQuota);

    this.logAudit({
      userId,
      workspaceId,
      operation: 'quota-set',
      status: 'success',
      resourceType: quotas[0]?.resourceType,
      ipAddress,
      userAgent,
      details: { quotaCount: quotas.length },
    });

    this.emit('quota-set', { quota: wsQuota, timestamp: Date.now() });
    this.updateStatistics(workspaceId, userId);
    return wsQuota;
  }

  /**
   * Get quotas for a workspace
   */
  getWorkspaceQuota(workspaceId: string, userId: string): WorkspaceQuota | null {
    const quota = Array.from(this.quotas.values()).find(
      (q) => q.workspaceId === workspaceId && q.userId === userId
    );
    return quota || null;
  }

  /**
   * Record resource usage
   */
  recordUsage(
    workspaceId: string,
    userId: string,
    usage: ResourceUsage[],
    ipAddress: string,
    userAgent: string
  ): WorkspaceMetrics {
    const metrics: WorkspaceMetrics = {
      workspaceId,
      userId,
      timestamp: Date.now(),
      usage,
      allWithinQuota: true,
      warningCount: 0,
      violationCount: 0,
    };

    // Check for quota violations
    const quota = this.getWorkspaceQuota(workspaceId, userId);
    if (quota) {
      for (const u of usage) {
        if (u.usagePercent >= 100) {
          metrics.violationCount++;
          metrics.allWithinQuota = false;
        } else if (u.usagePercent >= this.config.warningThresholdPercent) {
          metrics.warningCount++;
        }
      }
    }

    if (!this.metrics.has(workspaceId)) {
      this.metrics.set(workspaceId, []);
    }

    const metricsArray = this.metrics.get(workspaceId)!;
    metricsArray.push(metrics);

    // Limit metrics storage
    if (metricsArray.length > this.config.maxMetricsPerWorkspace) {
      metricsArray.splice(0, metricsArray.length - this.config.maxMetricsPerWorkspace);
    }

    // Create alerts for violations
    if (metrics.violationCount > 0 || metrics.warningCount > 0) {
      this.createAlertsForUsage(workspaceId, userId, usage, ipAddress, userAgent);
    }

    this.emit('usage-recorded', { metrics, timestamp: Date.now() });
    return metrics;
  }

  /**
   * Check quotas and enforce if needed
   */
  checkAndEnforce(
    workspaceId: string,
    userId: string,
    ipAddress: string,
    userAgent: string
  ): { enforced: boolean; actions: string[] } {
    const result = { enforced: false, actions: [] as string[] };

    if (!this.config.enableEnforcement) {
      return result;
    }

    const metrics = this.getLatestMetrics(workspaceId);
    if (!metrics) {
      return result;
    }

    for (const usage of metrics.usage) {
      if (usage.usagePercent >= 100) {
        result.enforced = true;
        result.actions.push(`Enforcing: ${usage.resourceType} quota exceeded`);

        this.logAudit({
          userId,
          workspaceId,
          operation: 'enforcement-triggered',
          status: 'success',
          resourceType: usage.resourceType,
          ipAddress,
          userAgent,
          details: {
            usagePercent: usage.usagePercent,
            action: 'block',
          },
        });

        this.emit('enforcement-triggered', {
          workspaceId,
          resourceType: usage.resourceType,
          usagePercent: usage.usagePercent,
          timestamp: Date.now(),
        });
      }
    }

    return result;
  }

  /**
   * Adjust quota for a workspace
   */
  adjustQuota(
    request: QuotaAdjustmentRequest,
    approvedBy: string,
    ipAddress: string,
    userAgent: string
  ): QuotaAdjustment {
    const adjustment: QuotaAdjustment = {
      id: `adj-${request.workspaceId}-${Date.now()}-${Math.random().toString(16).slice(2)}`,
      requestId: `req-${Date.now()}`,
      workspaceId: request.workspaceId,
      userId: request.userId,
      resourceType: request.resourceType,
      oldLimitValue: 0,
      newLimitValue: request.newLimitValue,
      approvedBy,
      approvedAt: Date.now(),
      effectiveAt: Date.now(),
      reason: request.reason,
    };

    // Find and update the quota
    const quota = this.getWorkspaceQuota(request.workspaceId, request.userId);
    if (quota) {
      const resourceQuota = quota.quotas.find((q) => q.resourceType === request.resourceType);
      if (resourceQuota) {
        adjustment.oldLimitValue = resourceQuota.limitValue;
        resourceQuota.limitValue = request.newLimitValue;
        quota.updatedAt = Date.now();
      }
    }

    if (!this.adjustments.has(request.workspaceId)) {
      this.adjustments.set(request.workspaceId, []);
    }

    this.adjustments.get(request.workspaceId)!.push(adjustment);

    this.logAudit({
      userId: request.userId,
      workspaceId: request.workspaceId,
      operation: 'quota-adjusted',
      status: 'success',
      resourceType: request.resourceType,
      ipAddress,
      userAgent,
      details: {
        oldValue: adjustment.oldLimitValue,
        newValue: request.newLimitValue,
        reason: request.reason,
      },
    });

    this.emit('quota-adjusted', { adjustment, timestamp: Date.now() });
    return adjustment;
  }

  /**
   * Get workspace metrics
   */
  getWorkspaceMetrics(workspaceId: string, limit?: number): WorkspaceMetrics[] {
    const metrics = this.metrics.get(workspaceId) || [];
    if (limit) {
      return metrics.slice(-limit);
    }
    return metrics;
  }

  /**
   * Get latest metrics for workspace
   */
  private getLatestMetrics(workspaceId: string): WorkspaceMetrics | null {
    const metrics = this.metrics.get(workspaceId);
    if (!metrics || metrics.length === 0) return null;
    return metrics[metrics.length - 1];
  }

  /**
   * Reset singleton for testing
   */
  static reset(): void {
    if (QuotaService.instance) {
      QuotaService.instance.shutdown();
    }
    QuotaService.instance = undefined as any;
  }

  /**
   * Create alerts for usage violations
   */
  private createAlertsForUsage(
    workspaceId: string,
    userId: string,
    usage: ResourceUsage[],
    ipAddress: string,
    userAgent: string
  ): void {
    for (const u of usage) {
      let alertType: 'warning' | 'critical' | 'violation' = 'warning';
      if (u.usagePercent >= 100) {
        alertType = 'violation';
      } else if (u.usagePercent >= this.config.criticalThresholdPercent) {
        alertType = 'critical';
      }

      const alert: QuotaAlert = {
        id: `alert-${workspaceId}-${Date.now()}-${Math.random().toString(16).slice(2)}`,
        workspaceId,
        userId,
        resourceType: u.resourceType,
        currentPercent: u.usagePercent,
        usageValue: u.currentValue,
        quotaValue: u.limitValue,
        alertType,
        createdAt: Date.now(),
        acknowledged: false,
      };

      if (!this.alerts.has(workspaceId)) {
        this.alerts.set(workspaceId, []);
      }

      const alertsArray = this.alerts.get(workspaceId)!;
      alertsArray.push(alert);

      if (alertsArray.length > this.config.maxAlertsPerWorkspace) {
        alertsArray.splice(0, alertsArray.length - this.config.maxAlertsPerWorkspace);
      }

      this.logAudit({
        userId,
        workspaceId,
        operation: 'alert-created',
        status: 'success',
        resourceType: u.resourceType,
        ipAddress,
        userAgent,
        details: {
          alertType,
          usagePercent: u.usagePercent,
        },
      });

      this.emit('alert-created', { alert, timestamp: Date.now() });
    }
  }

  /**
   * Acknowledge alert
   */
  acknowledgeAlert(alertId: string, workspaceId: string, userId: string): boolean {
    const alerts = this.alerts.get(workspaceId);
    if (!alerts) return false;

    const alert = alerts.find((a) => a.id === alertId);
    if (alert) {
      alert.acknowledged = true;
      alert.acknowledgedAt = Date.now();
      alert.acknowledgedBy = userId;
      this.emit('alert-acknowledged', { alert, timestamp: Date.now() });
      return true;
    }

    return false;
  }

  /**
   * Get alerts for workspace
   */
  getWorkspaceAlerts(workspaceId: string, limit?: number): QuotaAlert[] {
    const alerts = this.alerts.get(workspaceId) || [];
    if (limit) {
      return alerts.slice(-limit);
    }
    return alerts;
  }

  /**
   * Get audit log for user
   */
  getAuditLog(userId: string): QuotaAuditEntry[] {
    return (this.auditLog.get(userId) || []).slice(-100);
  }

  /**
   * Get statistics for workspace
   */
  getStatistics(workspaceId: string, userId: string): QuotaStatistics {
    return (
      this.statistics.get(workspaceId) || {
        workspaceId,
        totalQuotas: 0,
        quotasWithinLimit: 0,
        quotasInWarning: 0,
        quotasViolated: 0,
        averageUsagePercent: 0,
        mostUsedResource: null,
        leastUsedResource: null,
        alertsGenerated: 0,
        enforcementActionsTriggered: 0,
        lastCheckAt: null,
      }
    );
  }

  /**
   * Update configuration
   */
  updateConfig(config: Partial<QuotaServiceConfig>, userId: string, ipAddress: string, userAgent: string): void {
    this.config = { ...this.config, ...config };
    this.emit('config-updated', { config: this.config, timestamp: Date.now() });
  }

  /**
   * Private helper: Log audit entry
   */
  private logAudit(entry: {
    userId: string;
    workspaceId: string;
    operation: 'quota-set' | 'quota-adjusted' | 'quota-checked' | 'enforcement-triggered' | 'alert-created';
    status: 'success' | 'failure';
    resourceType?: ResourceType;
    ipAddress: string;
    userAgent: string;
    details?: Record<string, unknown>;
  }): void {
    const auditEntry: QuotaAuditEntry = {
      id: `audit-${Date.now()}-${Math.random().toString(16).slice(2)}`,
      userId: entry.userId,
      userEmail: `${entry.userId}@example.com`,
      workspaceId: entry.workspaceId,
      operation: entry.operation,
      status: entry.status,
      resourceType: entry.resourceType,
      ipAddress: entry.ipAddress,
      userAgent: entry.userAgent,
      timestamp: Date.now(),
      details: entry.details || {},
    };

    if (!this.auditLog.has(entry.userId)) {
      this.auditLog.set(entry.userId, []);
    }

    const userLog = this.auditLog.get(entry.userId)!;
    userLog.push(auditEntry);

    if (userLog.length > this.config.maxAuditLogSize) {
      userLog.splice(0, userLog.length - this.config.maxAuditLogSize);
    }

    this.emit('audit-logged', { entry: auditEntry, timestamp: Date.now() });
  }

  /**
   * Private helper: Update statistics
   */
  private updateStatistics(workspaceId: string, userId: string): void {
    const quota = this.getWorkspaceQuota(workspaceId, userId);
    const metrics = this.getLatestMetrics(workspaceId);
    const alerts = this.alerts.get(workspaceId) || [];

    const stats: QuotaStatistics = {
      workspaceId,
      totalQuotas: quota?.quotas.length || 0,
      quotasWithinLimit: 0,
      quotasInWarning: 0,
      quotasViolated: 0,
      averageUsagePercent: 0,
      mostUsedResource: null,
      leastUsedResource: null,
      alertsGenerated: alerts.length,
      enforcementActionsTriggered: 0,
      lastCheckAt: Date.now(),
    };

    if (metrics && quota) {
      let totalPercent = 0;
      let maxPercent = 0;
      let minPercent = 100;
      let maxResource: ResourceType | null = null;
      let minResource: ResourceType | null = null;

      for (const usage of metrics.usage) {
        totalPercent += usage.usagePercent;
        if (usage.usagePercent >= 100) {
          stats.quotasViolated++;
        } else if (usage.usagePercent >= this.config.warningThresholdPercent) {
          stats.quotasInWarning++;
        } else {
          stats.quotasWithinLimit++;
        }

        if (usage.usagePercent > maxPercent) {
          maxPercent = usage.usagePercent;
          maxResource = usage.resourceType;
        }
        if (usage.usagePercent < minPercent) {
          minPercent = usage.usagePercent;
          minResource = usage.resourceType;
        }
      }

      stats.averageUsagePercent = metrics.usage.length > 0 ? totalPercent / metrics.usage.length : 0;
      stats.mostUsedResource = maxResource;
      stats.leastUsedResource = minResource;
    }

    this.statistics.set(workspaceId, stats);
  }
}
