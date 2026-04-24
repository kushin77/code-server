/**
 * Resource Quotas Types
 * cgroups enforcement with quota tiers (Small/Med/Large)
 */

/**
 * CPU quota specification
 */
export interface CPUQuota {
  cores: number; // Number of CPU cores (0.5 = 50%)
  period?: number; // Period in microseconds (default 100000)
  quota?: number; // Quota in microseconds
}

/**
 * Memory quota specification
 */
export interface MemoryQuota {
  limitMB: number; // Memory limit in MB
  swapMB?: number; // Swap limit in MB (optional)
}

/**
 * Disk I/O quota specification
 */
export interface DiskIOQuota {
  readBytesPerSec: number; // Read throughput in bytes/sec
  writeBytesPerSec: number; // Write throughput in bytes/sec
  iopsRead?: number; // Read operations per second
  iopsWrite?: number; // Write operations per second
}

/**
 * Network bandwidth quota specification
 */
export interface BandwidthQuota {
  ingressMbps: number; // Ingress bandwidth in Mbps
  egressMbps: number; // Egress bandwidth in Mbps
  burstMbps?: number; // Burst capacity in Mbps
}

/**
 * Complete resource quota
 */
export interface ResourceQuota {
  id: string;
  name: string; // Small, Medium, Large, or custom
  userId?: string;
  workspaceId?: string;
  projectId?: string;
  cpu: CPUQuota;
  memory: MemoryQuota;
  diskIO: DiskIOQuota;
  bandwidth: BandwidthQuota;
  cgroupPath?: string; // /sys/fs/cgroup/... path for enforcement
  createdAt: number;
  updatedAt: number;
}

/**
 * Quota tier definition
 */
export interface QuotaTier {
  name: 'small' | 'medium' | 'large' | 'custom';
  cpu: CPUQuota;
  memory: MemoryQuota;
  diskIO: DiskIOQuota;
  bandwidth: BandwidthQuota;
  description: string;
  maxConcurrentSessions?: number;
}

/**
 * Real-time resource usage
 */
export interface ResourceUsage {
  cpuPercent: number; // 0-100%
  cpuCoresUsed: number; // Actual cores used
  memoryMB: number; // Current memory usage
  memoryPercent: number; // 0-100% of limit
  diskIOReadBytesPerSec: number; // Current read throughput
  diskIOWriteBytesPerSec: number; // Current write throughput
  diskIOReadPercent: number; // % of read limit
  diskIOWritePercent: number; // % of write limit
  ingressMbps: number; // Current ingress
  egressMbps: number; // Current egress
  ingressPercent: number; // % of limit
  egressPercent: number; // % of limit
  storageGBUsed?: number; // Current storage usage in GB
  gpuCountUsed?: number; // GPUs in use during the sample window
  timestamp: number;
}

/**
 * Resource cost totals
 */
export interface ResourceCostTotals {
  cpuHours: number;
  memoryGbHours: number;
  storageGbDays: number;
  gpuHours: number;
}

/**
 * Budget threshold definition for a report scope
 */
export interface BudgetThresholds extends Partial<ResourceCostTotals> {}

/**
 * Budget alert scope
 */
export type BudgetAlertScope = 'quota' | 'user' | 'workspace';

/**
 * Budget alert details
 */
export interface BudgetAlert {
  alertId: string;
  scope: BudgetAlertScope;
  scopeId: string;
  quotaId?: string;
  userId?: string;
  workspaceId?: string;
  projectId?: string;
  metric: keyof ResourceCostTotals;
  threshold: number;
  actual: number;
  severity: 'warning' | 'critical';
  message: string;
  triggeredAt: number;
  acknowledgedAt?: number;
  acknowledgedBy?: string;
}

/**
 * Resource cost report for a quota
 */
export interface ResourceCostReport extends ResourceCostTotals {
  quotaId: string;
  userId?: string;
  workspaceId?: string;
  projectId?: string;
  windowStart: number;
  windowEnd: number;
  sampleCount: number;
  estimated: boolean;
}

/**
 * Monthly cost report for a user or workspace
 */
export interface MonthlyCostReport {
  userId?: string;
  workspaceId?: string;
  projectId?: string;
  windowStart: number;
  windowEnd: number;
  totals: ResourceCostTotals;
  quotas: ResourceCostReport[];
}

/**
 * Resource quota enforcement status
 */
export interface EnforcementStatus {
  quotaId: string;
  enforced: boolean;
  cgroupsAvailable: boolean;
  method: 'cgroups' | 'mock' | 'disabled';
  lastEnforcedAt?: number;
  error?: string;
}

/**
 * Resource limit exceeded event
 */
export interface LimitExceededEvent {
  quotaId: string;
  userId?: string;
  workspaceId?: string;
  projectId?: string;
  limitType: 'cpu' | 'memory' | 'diskIO' | 'bandwidth';
  currentUsage: number;
  limit: number;
  timestamp: number;
  severity: 'warning' | 'critical';
}

/**
 * Quota enforcement action
 */
export type EnforcementAction = 'throttle' | 'warn' | 'block' | 'kill';

/**
 * Quota enforcement policy
 */
export interface EnforcementPolicy {
  cpuThresholdPercent?: number; // Warn/throttle at %
  memoryThresholdPercent?: number;
  diskIOThresholdPercent?: number;
  bandwidthThresholdPercent?: number;
  onCPUExceeded: EnforcementAction; // throttle (default) or kill
  onMemoryExceeded: EnforcementAction; // throttle (default) or kill
  onDiskIOExceeded: EnforcementAction; // warn or throttle
  onBandwidthExceeded: EnforcementAction; // warn or throttle
  killGracePeriodMs?: number; // Grace period before killing process
}

/**
 * Quota statistics
 */
export interface QuotaStats {
  totalQuotas: number;
  quotasByTier: Record<string, number>;
  quotasEnforced: number;
  quotasFailed: number;
  totalUsersWithQuotas: number;
  totalWorkspacesWithQuotas: number;
  limitExceededCount: Record<string, number>;
  averageCPUUsage: number;
  averageMemoryUsage: number;
}

/**
 * Quota history entry
 */
export interface QuotaHistoryEntry {
  quotaId: string;
  timestamp: number;
  usage: ResourceUsage;
  limitExceeded?: LimitExceededEvent;
  action?: EnforcementAction;
}

/**
 * Quota service configuration
 */
export interface QuotaServiceConfig {
  enabled: boolean;
  cgroupsEnabled: boolean; // Use real cgroups if available
  enforcementPolicy: EnforcementPolicy;
  maxHistoryEntries?: number; // Keep last N samples per quota
  samplingIntervalMs?: number; // Sample every N ms
  defaultTier: 'small' | 'medium' | 'large';
}
