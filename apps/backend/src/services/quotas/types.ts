/**
 * Resource Quotas Service Types
 * CPU, memory, storage limits per workspace with enforcement and tracking
 */

/**
 * Quota resource type
 */
export type ResourceType = 'cpu' | 'memory' | 'storage' | 'bandwidth' | 'connections';

/**
 * Quota limit for a resource
 */
export interface ResourceQuota {
  resourceType: ResourceType;
  limitValue: number;
  limitUnit: string; // 'vCPU', 'MB', 'GB', 'TB', 'Mbps', 'connections'
  warningThresholdPercent: number; // warn at 80% by default
  hardLimitPercent: number; // hard limit at 100%
  enforcementMode: 'soft' | 'hard'; // soft = warn, hard = enforce
}

/**
 * Workspace quota configuration
 */
export interface WorkspaceQuota {
  id: string;
  workspaceId: string;
  userId: string;
  quotas: ResourceQuota[];
  createdAt: number;
  updatedAt: number;
  isActive: boolean;
}

/**
 * Current resource usage
 */
export interface ResourceUsage {
  resourceType: ResourceType;
  currentValue: number;
  limitValue: number;
  usagePercent: number; // 0-100
  unit: string;
  timestamp: number;
}

/**
 * Workspace resource metrics
 */
export interface WorkspaceMetrics {
  workspaceId: string;
  userId: string;
  timestamp: number;
  usage: ResourceUsage[];
  allWithinQuota: boolean;
  warningCount: number; // resources at >80%
  violationCount: number; // resources at >100%
}

/**
 * Quota enforcement policy
 */
export interface EnforcementPolicy {
  id: string;
  workspaceId: string;
  resourceType: ResourceType;
  action: 'warn' | 'throttle' | 'block' | 'kill';
  triggerPercent: number; // action triggers at this %
  gracePeriodMs: number; // time before action takes effect
  metadata: {
    throttlePercentage?: number; // for throttle action: 0-100
    killDelay?: number; // for kill action: ms to wait
    notifyUser?: boolean;
  };
}

/**
 * Quota alert
 */
export interface QuotaAlert {
  id: string;
  workspaceId: string;
  userId: string;
  resourceType: ResourceType;
  currentPercent: number;
  usageValue: number;
  quotaValue: number;
  alertType: 'warning' | 'critical' | 'violation';
  createdAt: number;
  acknowledged: boolean;
  acknowledgedAt?: number;
  acknowledgedBy?: string;
}

/**
 * Quota configuration
 */
export interface QuotaServiceConfig {
  enableEnforcement: boolean;
  enableMetricsCollection: boolean;
  metricsCollectionIntervalMs: number;
  warningThresholdPercent: number;
  criticalThresholdPercent: number;
  checkIntervalMs: number;
  maxAlertsPerWorkspace: number;
  maxMetricsPerWorkspace: number;
  maxAuditLogSize: number;
  storageBackend: 'memory' | 'database' | 's3';
}

/**
 * Quota adjustment request
 */
export interface QuotaAdjustmentRequest {
  workspaceId: string;
  userId: string;
  resourceType: ResourceType;
  newLimitValue: number;
  reason: string;
  requestedBy: string;
}

/**
 * Quota adjustment approval
 */
export interface QuotaAdjustment {
  id: string;
  requestId: string;
  workspaceId: string;
  userId: string;
  resourceType: ResourceType;
  oldLimitValue: number;
  newLimitValue: number;
  approvedBy: string;
  approvedAt: number;
  effectiveAt: number;
  reason: string;
}

/**
 * Audit log entry for quota operations
 */
export interface QuotaAuditEntry {
  id: string;
  userId: string;
  userEmail: string;
  workspaceId: string;
  operation: 'quota-set' | 'quota-adjusted' | 'quota-checked' | 'enforcement-triggered' | 'alert-created';
  status: 'success' | 'failure';
  resourceType?: ResourceType;
  ipAddress: string;
  userAgent: string;
  timestamp: number;
  details: {
    oldValue?: number;
    newValue?: number;
    reason?: string;
    enforcementAction?: string;
    [key: string]: unknown;
  };
}

/**
 * Quota statistics for a workspace
 */
export interface QuotaStatistics {
  workspaceId: string;
  totalQuotas: number;
  quotasWithinLimit: number;
  quotasInWarning: number; // 80-99%
  quotasViolated: number; // >100%
  averageUsagePercent: number;
  mostUsedResource: ResourceType | null;
  leastUsedResource: ResourceType | null;
  alertsGenerated: number;
  enforcementActionsTriggered: number;
  lastCheckAt: number;
}
