/**
 * PR Preview Environments Service Types
 * Auto-provision and auto-destroy preview environments for pull requests
 */

/**
 * Preview environment state
 */
export type PreviewEnvironmentState = 'provisioning' | 'active' | 'scaling' | 'shutting-down' | 'terminated' | 'failed';

/**
 * Git branch information
 */
export interface GitBranch {
  name: string;
  sha: string;
  repoUrl: string;
  defaultBranch: boolean;
}

/**
 * Pull request information
 */
export interface PullRequest {
  id: string;
  number: number;
  title: string;
  author: string;
  branch: GitBranch;
  targetBranch: GitBranch;
  createdAt: number;
  updatedAt: number;
  state: 'open' | 'closed' | 'merged';
  isDraft: boolean;
}

/**
 * Preview environment configuration
 */
export interface PreviewEnvironmentConfig {
  cpuLimit: string; // '0.5', '1', '2'
  memoryLimit: string; // '512Mi', '1Gi', '2Gi'
  replicaCount: number;
  timeoutMinutes: number; // grace period after PR close/merge
  enableAutoScale: boolean;
  enableMetrics: boolean;
  containerImage: string;
  port: number;
  healthCheckPath: string;
  environmentVariables: Map<string, string>;
}

/**
 * Preview environment instance
 */
export interface PreviewEnvironmentInstance {
  id: string;
  pullRequestId: string;
  pullRequestNumber: number;
  userId: string;
  userEmail: string;
  url: string;
  state: PreviewEnvironmentState;
  config: PreviewEnvironmentConfig;
  provisionedAt: number;
  lastHealthCheckAt: number;
  lastHealthStatus: 'healthy' | 'degraded' | 'unhealthy';
  metrics: {
    cpuUsagePercent: number;
    memoryUsagePercent: number;
    requestCount: number;
    errorCount: number;
    averageResponseTimeMs: number;
  };
  gracePeriodStartAt?: number;
  terminatedAt?: number;
  metadata: {
    branchName: string;
    commitSha: string;
    repoUrl: string;
  };
}

/**
 * Provisioning request
 */
export interface ProvisioningRequest {
  pullRequestId: string;
  pullRequestNumber: number;
  userId: string;
  userEmail: string;
  branch: GitBranch;
  targetBranch: GitBranch;
  config?: Partial<PreviewEnvironmentConfig>;
}

/**
 * Provisioning result
 */
export interface ProvisioningResult {
  success: boolean;
  environmentId: string;
  url?: string;
  provisioningTimeMs: number;
  reason?: string;
}

/**
 * Scaling event
 */
export interface ScalingEvent {
  id: string;
  environmentId: string;
  timestamp: number;
  fromReplicas: number;
  toReplicas: number;
  reason: string;
  metrics: {
    cpuUsagePercent: number;
    memoryUsagePercent: number;
    requestCount: number;
  };
}

/**
 * Preview environment statistics
 */
export interface PreviewEnvironmentStatistics {
  pullRequestId: string;
  pullRequestNumber: number;
  totalProvisions: number;
  successfulProvisions: number;
  failedProvisions: number;
  averageProvisioningTimeMs: number;
  averageLifetimeMs: number;
  totalUptime: number;
  totalDowntime: number;
  scalingEventsCount: number;
  lastProvisioned: number;
  lastTerminated: number;
}

/**
 * Service configuration
 */
export interface PreviewServiceConfig {
  enableAutoProvisioning: boolean;
  enableAutoDestroy: boolean;
  gracePeriodMinutes: number;
  maxConcurrentEnvironments: number;
  defaultReplicaCount: number;
  defaultCpuLimit: string;
  defaultMemoryLimit: string;
  healthCheckIntervalMs: number;
  metricsCollectionIntervalMs: number;
  scalingThresholdPercent: number;
  maxAuditLogSize: number;
  storageBackend: 'memory' | 'kubernetes' | 'docker';
}

/**
 * Audit log entry
 */
export interface PreviewAuditEntry {
  id: string;
  userId: string;
  userEmail: string;
  operation: 'provision' | 'terminate' | 'scale' | 'health-check' | 'grace-period-start' | 'config-update';
  status: 'success' | 'failure';
  environmentId?: string;
  pullRequestNumber?: number;
  ipAddress: string;
  userAgent: string;
  timestamp: number;
  details: {
    reason?: string;
    provisioningTimeMs?: number;
    url?: string;
    replicaCount?: number;
    [key: string]: unknown;
  };
}

/**
 * Health check result
 */
export interface HealthCheckResult {
  id: string;
  environmentId: string;
  timestamp: number;
  isHealthy: boolean;
  responseTimeMs: number;
  httpStatusCode: number;
  errorMessage?: string;
}
