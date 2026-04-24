/**
 * @file        apps/backend/src/services/preview-env/types.ts
 * @module      devops/preview-environments
 * @description PR preview environment type definitions
 */

/**
 * Preview environment status
 */
export type PreviewStatus =
  | 'provisioning'
  | 'ready'
  | 'updating'
  | 'degraded'
  | 'failing'
  | 'destroying'
  | 'destroyed';

/**
 * Resource type in preview
 */
export type ResourceType = 'frontend' | 'backend' | 'database' | 'cache';

/**
 * Git branch reference
 */
export interface GitBranch {
  name: string;
  sha: string;
  repository: string;
  pullRequestId?: number;
  createdAt: number;
}

/**
 * Preview environment instance
 */
export interface PreviewEnvironment {
  id: string;
  branch: GitBranch;
  workspaceId: string;

  // Status
  status: PreviewStatus;
  createdAt: number;
  readyAt?: number;
  destroyedAt?: number;

  // Grace period
  markedForDestructionAt?: number; // When marked for destruction
  gracePeriodMs: number; // Default 1 hour = 3600000

  // Resource URLs
  urls: {
    frontend?: string;
    backend?: string;
    database?: string; // Connection string
  };

  // Resource management
  resources: {
    frontend?: {
      port: number;
      status: 'running' | 'stopped' | 'error';
      memory?: number; // MB
      cpu?: number; // % usage
    };
    backend?: {
      port: number;
      status: 'running' | 'stopped' | 'error';
      memory?: number;
      cpu?: number;
    };
    database?: {
      name: string;
      status: 'healthy' | 'unhealthy' | 'error';
      size?: number; // MB
    };
  };

  // Metadata
  createdBy: string; // User ID
  pullRequestUrl?: string;
  branchName: string;
  buildDuration?: number; // ms
  deploymentLogs?: string[];

  // Configuration
  environment: Record<string, string>; // Env vars
  features?: string[]; // Feature flags enabled
}

/**
 * Preview environment event
 */
export interface PreviewEvent {
  type:
    | 'created'
    | 'provisioning'
    | 'ready'
    | 'updated'
    | 'degraded'
    | 'error'
    | 'marked-for-destruction'
    | 'destroying'
    | 'destroyed';
  environmentId: string;
  timestamp: number;
  message: string;
  details?: Record<string, any>;
}

/**
 * Preview environment build configuration
 */
export interface PreviewBuildConfig {
  frontend: {
    enabled: boolean;
    buildCommand?: string;
    startCommand?: string;
    port?: number;
    environment?: Record<string, string>;
  };
  backend: {
    enabled: boolean;
    buildCommand?: string;
    startCommand?: string;
    port?: number;
    environment?: Record<string, string>;
  };
  database: {
    enabled: boolean;
    type: 'postgres' | 'mysql' | 'mongodb';
    seedScript?: string;
    environment?: Record<string, string>;
  };
  cache?: {
    enabled: boolean;
    type: 'redis';
    port?: number;
  };
}

/**
 * Preview environment statistics
 */
export interface PreviewStats {
  totalEnvironments: number;
  activeEnvironments: number; // ready + degraded
  provisioningEnvironments: number;
  failingEnvironments: number;
  markedForDestruction: number;

  averageProvisionTime: number; // ms
  averageResourceUsage: {
    frontend?: number; // % cpu
    backend?: number;
  };

  uptime: Record<string, number>; // % by branch

  costEstimate?: number; // $ per hour
  errorRate: number; // % of failed provisions

  byUser: Record<string, number>; // Count of previews per user
  byBranch: Record<string, { status: PreviewStatus; createdAt: number }>;
}

/**
 * Cleanup policy for preview environments
 */
export interface CleanupPolicy {
  onMerge: {
    destroy: boolean;
    gracePeriodMs?: number;
  };
  onClose: {
    destroy: boolean;
    gracePeriodMs?: number;
  };
  inactivityTimeoutMs: number; // Default 1 hour
  maxConcurrentPerUser: number; // Default 5
  maxLifetimeMs: number; // Maximum age (default 7 days)
}

/**
 * Resource health check result
 */
export interface HealthCheckResult {
  resource: ResourceType;
  healthy: boolean;
  responseTime: number; // ms
  lastCheck: number;
  message?: string;
  error?: string;
}

/**
 * Preview environment provisioning request
 */
export interface ProvisioningRequest {
  pullRequestId: number;
  branchName: string;
  sha: string;
  repository: string;
  userId: string;
  config: PreviewBuildConfig;
  tags?: Record<string, string>;
  createdAt: number;
}

/**
 * Cost estimate for preview environments
 */
export interface CostEstimate {
  environmentId: string;
  frontendCost?: number; // $ per hour
  backendCost?: number;
  databaseCost?: number;
  cacheCost?: number;
  totalCost: number; // $ per hour
  estimatedMonthly: number; // $
}
