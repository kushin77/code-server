/**
 * Distributed Lock Manager Types
 * @file        apps/backend/src/services/distributed-lock-manager/types.ts
 * @module      services/distributed-lock-manager
 * @description Type definitions for distributed lock management
 */

/**
 * Lock mode enumeration
 */
export type LockMode = 'shared' | 'exclusive' | 'intent-shared' | 'intent-exclusive';

/**
 * Lock status enumeration
 */
export type LockStatus = 'pending' | 'acquired' | 'released' | 'expired' | 'revoked';

/**
 * Represents a distributed lock
 */
export interface DistributedLock {
  lockId: string;
  resourceId: string;
  resourceType: string;
  mode: LockMode;
  status: LockStatus;
  acquiredBy: string;
  acquiredByEmail: string;
  acquiredAt: number;
  expiresAt: number;
  renewedAt?: number;
  releasedAt?: number;
  priority: number;
  waiters: string[];
  metadata: Record<string, unknown>;
}

/**
 * Lock request details
 */
export interface LockRequest {
  resourceId: string;
  resourceType: string;
  mode: LockMode;
  userId: string;
  userEmail: string;
  timeout: number;
  priority: number;
  metadata?: Record<string, unknown>;
}

/**
 * Lock acquisition result
 */
export interface LockAcquisitionResult {
  success: boolean;
  lockId?: string;
  lock?: DistributedLock;
  waitTime?: number;
  deadlockDetected?: boolean;
  error?: string;
}

/**
 * Lock release result
 */
export interface LockReleaseResult {
  success: boolean;
  lockId?: string;
  releasedAt?: number;
  nextWaiter?: string;
  error?: string;
}

/**
 * Lock renewal result
 */
export interface LockRenewalResult {
  success: boolean;
  lockId?: string;
  newExpiresAt?: number;
  error?: string;
}

/**
 * Lock status information
 */
export interface LockStatusInfo {
  lockId: string;
  resourceId: string;
  mode: LockMode;
  status: LockStatus;
  owner: string;
  ownerEmail: string;
  acquiredAt: number;
  expiresAt: number;
  waitersCount: number;
  isExpired: boolean;
}

/**
 * Deadlock information
 */
export interface DeadlockInfo {
  detected: boolean;
  cycle: string[];
  resources: string[];
  timestamp: number;
  resolvedAt?: number;
  resolutionStrategy: 'priority' | 'timeout' | 'rollback';
}

/**
 * Lock compatibility matrix
 */
export interface LockCompatibility {
  mode: LockMode;
  compatible: Record<LockMode, boolean>;
}

/**
 * Lock holder information
 */
export interface LockHolder {
  lockId: string;
  userId: string;
  userEmail: string;
  resourceId: string;
  mode: LockMode;
  acquiredAt: number;
  expiresAt: number;
}

/**
 * Lock waiter information
 */
export interface LockWaiter {
  waiterId: string;
  userId: string;
  userEmail: string;
  resourceId: string;
  requestedMode: LockMode;
  waitStarted: number;
  priority: number;
}

/**
 * Lock statistics
 */
export interface LockStatistics {
  totalLocks: number;
  activeLocks: number;
  waitingRequests: number;
  deadlocksDetected: number;
  deadlocksResolved: number;
  averageWaitTime: number;
  maxWaitTime: number;
  acquisitionSuccess: number;
  acquisitionFailure: number;
  successRate: number;
}

/**
 * Lock audit entry
 */
export interface LockAuditEntry {
  timestamp: number;
  userId: string;
  userEmail: string;
  operation: string;
  resourceId: string;
  lockId: string;
  mode?: LockMode;
  status: 'success' | 'failure';
  details?: Record<string, unknown>;
}

/**
 * Lock manager configuration
 */
export interface DistributedLockConfig {
  defaultLockTimeout: number;
  maxLockHolders: number;
  enableDeadlockDetection: boolean;
  deadlockCheckInterval: number;
  autoRenewBeforeExpiry: number;
  maxWaiters: number;
  maxAuditEntries: number;
}

/**
 * Lock deadlock detection result
 */
export interface DeadlockDetectionResult {
  success: boolean;
  deadlocksFound: DeadlockInfo[];
  affectedLocks: string[];
}

/**
 * Lock waiter promotion result
 */
export interface WaiterPromotionResult {
  success: boolean;
  promotedWaiterId?: string;
  lockId?: string;
  error?: string;
}

/**
 * Lock batch operation result
 */
export interface BatchLockResult {
  totalRequests: number;
  successCount: number;
  failureCount: number;
  results: LockAcquisitionResult[];
  timestamp: number;
}

/**
 * Distributed Lock Manager Service interface
 */
export interface IDistributedLockService {
  // Lock acquisition and release
  acquireLock(request: LockRequest, ipAddress: string, userAgent: string): LockAcquisitionResult;
  releaseLock(lockId: string, userId: string, ipAddress: string, userAgent: string): LockReleaseResult;
  renewLock(lockId: string, userId: string, newTimeout: number, ipAddress: string, userAgent: string): LockRenewalResult;

  // Lock queries
  getLock(lockId: string): LockStatusInfo | undefined;
  getResourceLocks(resourceId: string): LockStatusInfo[];
  getActiveLocks(): LockStatusInfo[];
  getLocksByUser(userId: string): LockStatusInfo[];

  // Lock hierarchy
  getParentLocks(lockId: string): LockStatusInfo[];
  getChildLocks(lockId: string): LockStatusInfo[];

  // Deadlock management
  detectDeadlocks(): DeadlockDetectionResult;
  resolveDeadlock(deadlockId: string, strategy: string, userId: string, ipAddress: string, userAgent: string): { success: boolean };

  // Waiter management
  getWaiters(resourceId: string): LockWaiter[];
  promoteWaiter(resourceId: string, waiterId: string, userId: string, ipAddress: string, userAgent: string): WaiterPromotionResult;

  // Lock compatibility
  checkCompatibility(mode: LockMode, existingMode: LockMode): boolean;
  getCompatibilityMatrix(): Record<string, Record<string, boolean>>;

  // Batch operations
  batchAcquire(requests: LockRequest[], userId: string, ipAddress: string, userAgent: string): BatchLockResult;
  batchRelease(lockIds: string[], userId: string, ipAddress: string, userAgent: string): { successCount: number; failureCount: number };

  // Statistics and monitoring
  getStatistics(): LockStatistics;
  getAuditLog(limit?: number): LockAuditEntry[];
  clearExpiredLocks(userId: string, ipAddress: string, userAgent: string): { clearedCount: number };

  // Configuration
  updateConfig(config: Partial<DistributedLockConfig>): void;
  getConfig(): DistributedLockConfig;

  // Lifecycle
  shutdown(): void;
}
