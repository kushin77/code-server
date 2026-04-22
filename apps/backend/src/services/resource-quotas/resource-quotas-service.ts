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
  private isInitialized = false;
  private quotas: Map<string, ResourceQuota> = new Map();
  private usageHistory: Map<string, QuotaHistoryEntry[]> = new Map();
  private enforcementStatuses: Map<string, EnforcementStatus> = new Map();
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

    const quota: ResourceQuota = {
      id: `quota-${userId}-${workspaceId}-${Date.now()}`,
      name: tierName,
      userId,
      workspaceId,
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

    const quota: ResourceQuota = {
      id: `quota-custom-${userId}-${Date.now()}`,
      name: 'custom',
      userId,
      workspaceId,
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
      timestamp: Date.now(),
    };

    return usage;
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
      
      // Record history
      const history = this.usageHistory.get(quota.id) || [];
      const entry: QuotaHistoryEntry = {
        quotaId: quota.id,
        timestamp: Date.now(),
        usage,
      };

      // Check for limit exceeded
      if (usage.cpuPercent > (this.config.enforcementPolicy.cpuThresholdPercent || 80)) {
        const event: LimitExceededEvent = {
          quotaId: quota.id,
          userId: quota.userId,
          workspaceId: quota.workspaceId,
          limitType: 'cpu',
          currentUsage: usage.cpuPercent,
          limit: this.config.enforcementPolicy.cpuThresholdPercent || 80,
          timestamp: Date.now(),
          severity: usage.cpuPercent > 95 ? 'critical' : 'warning',
        };
        entry.limitExceeded = event;
        entry.action = this.config.enforcementPolicy.onCPUExceeded;
        this.stats.limitExceededCount['cpu'] = (this.stats.limitExceededCount['cpu'] || 0) + 1;
        this.emit('limit-exceeded', { event });
      }

      if (usage.memoryPercent > (this.config.enforcementPolicy.memoryThresholdPercent || 85)) {
        const event: LimitExceededEvent = {
          quotaId: quota.id,
          userId: quota.userId,
          workspaceId: quota.workspaceId,
          limitType: 'memory',
          currentUsage: usage.memoryPercent,
          limit: this.config.enforcementPolicy.memoryThresholdPercent || 85,
          timestamp: Date.now(),
          severity: usage.memoryPercent > 95 ? 'critical' : 'warning',
        };
        entry.limitExceeded = event;
        entry.action = this.config.enforcementPolicy.onMemoryExceeded;
        this.stats.limitExceededCount['memory'] = (this.stats.limitExceededCount['memory'] || 0) + 1;
        this.emit('limit-exceeded', { event });
      }

      history.push(entry);

      // Keep only maxHistoryEntries
      if (history.length > (this.config.maxHistoryEntries || 1000)) {
        history.splice(0, history.length - (this.config.maxHistoryEntries || 1000));
      }

      this.usageHistory.set(quota.id, history);
    }
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
