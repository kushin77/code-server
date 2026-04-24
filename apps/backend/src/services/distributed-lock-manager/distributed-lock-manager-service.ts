/**
 * Distributed Lock Manager Service
 * @file        apps/backend/src/services/distributed-lock-manager/distributed-lock-manager-service.ts
 * @module      services/distributed-lock-manager
 * @description Distributed lock management for concurrent resource access
 */

import { EventEmitter } from 'events';
import {
  DistributedLock,
  LockRequest,
  LockAcquisitionResult,
  LockReleaseResult,
  LockRenewalResult,
  LockStatusInfo,
  DeadlockInfo,
  DeadlockDetectionResult,
  LockWaiter,
  LockStatistics,
  LockAuditEntry,
  DistributedLockConfig,
  LockMode,
  LockStatus,
  IDistributedLockService,
  WaiterPromotionResult,
  BatchLockResult,
} from './types.js';

/**
 * Distributed Lock Manager Service
 * Manages distributed locks for concurrent resource access with deadlock detection
 */
export class DistributedLockManager extends EventEmitter implements IDistributedLockService {
  private static instance: DistributedLockManager | undefined;
  private locks: Map<string, DistributedLock> = new Map();
  private resourceLocks: Map<string, string[]> = new Map(); // resourceId -> lockIds
  private waitQueues: Map<string, LockWaiter[]> = new Map(); // resourceId -> waiters
  private userLocks: Map<string, string[]> = new Map(); // userId -> lockIds
  private auditLog: Map<string, LockAuditEntry[]> = new Map(); // userId -> entries
  private deadlocks: Map<string, DeadlockInfo> = new Map();
  private stats: LockStatistics = {
    totalLocks: 0,
    activeLocks: 0,
    waitingRequests: 0,
    deadlocksDetected: 0,
    deadlocksResolved: 0,
    averageWaitTime: 0,
    maxWaitTime: 0,
    acquisitionSuccess: 0,
    acquisitionFailure: 0,
    successRate: 0,
  };
  private config: DistributedLockConfig = {
    defaultLockTimeout: 30000,
    maxLockHolders: 100,
    enableDeadlockDetection: true,
    deadlockCheckInterval: 5000,
    autoRenewBeforeExpiry: 5000,
    maxWaiters: 50,
    maxAuditEntries: 1000,
  };

  private constructor() {
    super();
    this.initialize();
  }

  /**
   * Get or create singleton instance
   */
  public static getInstance(config?: Partial<DistributedLockConfig>): DistributedLockManager {
    if (!DistributedLockManager.instance) {
      DistributedLockManager.instance = new DistributedLockManager();
    }
    if (config) {
      DistributedLockManager.instance.updateConfig(config);
    }
    return DistributedLockManager.instance;
  }

  /**
   * Reset singleton for testing
   */
  public static reset(): void {
    DistributedLockManager.instance = undefined;
  }

  /**
   * Initialize service
   */
  private initialize(): void {
    this.emit('initialized', {
      data_object: { service: 'distributed-lock-manager', status: 'initialized' },
      timestamp: Date.now(),
    });
  }

  /**
   * Acquire a distributed lock
   */
  public acquireLock(request: LockRequest, ipAddress: string, userAgent: string): LockAcquisitionResult {
    try {
      const lockId = `lock-${Date.now()}-${Math.random().toString(16).slice(2)}`;
      const now = Date.now();

      // Check if compatible lock exists
      const existing = this.getResourceLocks(request.resourceId);
      const compatible = existing.every((lock) => this.checkCompatibility(request.mode, lock.mode));

      if (!compatible) {
        // Add to wait queue
        const waiterId = `waiter-${Date.now()}-${Math.random().toString(16).slice(2)}`;
        const waiter: LockWaiter = {
          waiterId,
          userId: request.userId,
          userEmail: request.userEmail,
          resourceId: request.resourceId,
          requestedMode: request.mode,
          waitStarted: now,
          priority: request.priority,
        };

        if (!this.waitQueues.has(request.resourceId)) {
          this.waitQueues.set(request.resourceId, []);
        }
        this.waitQueues.get(request.resourceId)!.push(waiter);
        this.stats.waitingRequests++;

        this.logAudit(request.userId, 'acquire-lock-queued', request.resourceId, lockId, request.mode, 'success', {
          waiterId,
          mode: request.mode,
        });

        this.emit('lock-wait-queued', {
          data_object: { lockId, resourceId: request.resourceId, waiterId },
          timestamp: now,
        });

        return { success: false, error: 'Lock not available, added to wait queue' };
      }

      // Create the lock
      const lock: DistributedLock = {
        lockId,
        resourceId: request.resourceId,
        resourceType: request.resourceType,
        mode: request.mode,
        status: 'acquired',
        acquiredBy: request.userId,
        acquiredByEmail: request.userEmail,
        acquiredAt: now,
        expiresAt: now + request.timeout,
        priority: request.priority,
        waiters: [],
        metadata: request.metadata || {},
      };

      this.locks.set(lockId, lock);
      if (!this.resourceLocks.has(request.resourceId)) {
        this.resourceLocks.set(request.resourceId, []);
      }
      this.resourceLocks.get(request.resourceId)!.push(lockId);

      if (!this.userLocks.has(request.userId)) {
        this.userLocks.set(request.userId, []);
      }
      this.userLocks.get(request.userId)!.push(lockId);

      this.stats.totalLocks++;
      this.stats.activeLocks++;
      this.stats.acquisitionSuccess++;
      this.updateSuccessRate();

      this.logAudit(request.userId, 'acquire-lock', request.resourceId, lockId, request.mode, 'success', {
        mode: request.mode,
        timeout: request.timeout,
      });

      this.emit('lock-acquired', {
        data_object: { lockId, resourceId: request.resourceId, mode: request.mode, userId: request.userId },
        timestamp: now,
      });

      return { success: true, lockId, lock, waitTime: 0 };
    } catch (error) {
      this.stats.acquisitionFailure++;
      this.updateSuccessRate();
      this.logAudit(request.userId, 'acquire-lock', request.resourceId, '', request.mode, 'failure', {
        error: (error as Error).message,
      });
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Release a distributed lock
   */
  public releaseLock(lockId: string, userId: string, ipAddress: string, userAgent: string): LockReleaseResult {
    try {
      const lock = this.locks.get(lockId);
      if (!lock) {
        return { success: false, error: 'Lock not found' };
      }

      if (lock.acquiredBy !== userId) {
        return { success: false, error: 'Lock not owned by this user' };
      }

      const now = Date.now();
      lock.status = 'released';
      lock.releasedAt = now;

      // Remove from tracking maps
      this.locks.delete(lockId);
      if (this.resourceLocks.has(lock.resourceId)) {
        const locks = this.resourceLocks.get(lock.resourceId)!;
        locks.splice(locks.indexOf(lockId), 1);
      }
      if (this.userLocks.has(userId)) {
        const locks = this.userLocks.get(userId)!;
        locks.splice(locks.indexOf(lockId), 1);
      }

      this.stats.activeLocks--;

      // Promote next waiter if any
      let nextWaiter: string | undefined;
      const waiters = this.waitQueues.get(lock.resourceId);
      if (waiters && waiters.length > 0) {
        nextWaiter = waiters[0].userId;
      }

      this.logAudit(userId, 'release-lock', lock.resourceId, lockId, lock.mode, 'success', {
        wasHeldFor: now - lock.acquiredAt,
      });

      this.emit('lock-released', {
        data_object: { lockId, resourceId: lock.resourceId, nextWaiter },
        timestamp: now,
      });

      return { success: true, lockId, releasedAt: now, nextWaiter };
    } catch (error) {
      this.logAudit(userId, 'release-lock', '', lockId, undefined, 'failure', {
        error: (error as Error).message,
      });
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Renew a distributed lock
   */
  public renewLock(lockId: string, userId: string, newTimeout: number, ipAddress: string, userAgent: string): LockRenewalResult {
    try {
      const lock = this.locks.get(lockId);
      if (!lock) {
        return { success: false, error: 'Lock not found' };
      }

      if (lock.acquiredBy !== userId) {
        return { success: false, error: 'Lock not owned by this user' };
      }

      const now = Date.now();
      lock.renewedAt = now;
      lock.expiresAt = now + newTimeout;

      this.logAudit(userId, 'renew-lock', lock.resourceId, lockId, lock.mode, 'success', {
        oldTimeout: lock.expiresAt - now,
        newTimeout,
      });

      this.emit('lock-renewed', {
        data_object: { lockId, resourceId: lock.resourceId, newExpiresAt: lock.expiresAt },
        timestamp: now,
      });

      return { success: true, lockId, newExpiresAt: lock.expiresAt };
    } catch (error) {
      this.logAudit(userId, 'renew-lock', '', lockId, undefined, 'failure', {
        error: (error as Error).message,
      });
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Get lock status
   */
  public getLock(lockId: string): LockStatusInfo | undefined {
    const lock = this.locks.get(lockId);
    if (!lock) {
      return undefined;
    }

    return {
      lockId: lock.lockId,
      resourceId: lock.resourceId,
      mode: lock.mode,
      status: lock.status,
      owner: lock.acquiredBy,
      ownerEmail: lock.acquiredByEmail,
      acquiredAt: lock.acquiredAt,
      expiresAt: lock.expiresAt,
      waitersCount: lock.waiters.length,
      isExpired: Date.now() > lock.expiresAt,
    };
  }

  /**
   * Get all locks for a resource
   */
  public getResourceLocks(resourceId: string): LockStatusInfo[] {
    const lockIds = this.resourceLocks.get(resourceId) || [];
    return lockIds
      .map((id) => this.getLock(id))
      .filter((lock): lock is LockStatusInfo => lock !== undefined);
  }

  /**
   * Get all active locks
   */
  public getActiveLocks(): LockStatusInfo[] {
    const locks: LockStatusInfo[] = [];
    for (const [, lock] of this.locks) {
      const info = this.getLock(lock.lockId);
      if (info && !info.isExpired) {
        locks.push(info);
      }
    }
    return locks;
  }

  /**
   * Get locks held by user
   */
  public getLocksByUser(userId: string): LockStatusInfo[] {
    const lockIds = this.userLocks.get(userId) || [];
    return lockIds
      .map((id) => this.getLock(id))
      .filter((lock): lock is LockStatusInfo => lock !== undefined);
  }

  /**
   * Get parent locks (resource hierarchy)
   */
  public getParentLocks(lockId: string): LockStatusInfo[] {
    // Implementation for hierarchical locks
    return [];
  }

  /**
   * Get child locks (resource hierarchy)
   */
  public getChildLocks(lockId: string): LockStatusInfo[] {
    // Implementation for hierarchical locks
    return [];
  }

  /**
   * Detect deadlocks
   */
  public detectDeadlocks(): DeadlockDetectionResult {
    try {
      const detected: DeadlockInfo[] = [];
      const visited = new Set<string>();
      const recursionStack = new Set<string>();

      for (const [lockId, lock] of this.locks) {
        if (!visited.has(lockId)) {
          if (this.detectCycle(lockId, visited, recursionStack)) {
            const cycle = Array.from(recursionStack);
            detected.push({
              detected: true,
              cycle,
              resources: cycle.map((id) => this.locks.get(id)?.resourceId || ''),
              timestamp: Date.now(),
              resolutionStrategy: 'priority',
            });
            this.stats.deadlocksDetected++;
          }
        }
      }

      this.emit('deadlock-detection-completed', {
        data_object: { deadlocksFound: detected.length, affectedLocks: detected.flatMap((d) => d.cycle) },
        timestamp: Date.now(),
      });

      return { success: true, deadlocksFound: detected, affectedLocks: detected.flatMap((d) => d.cycle) };
    } catch (error) {
      return { success: false, deadlocksFound: [], affectedLocks: [] };
    }
  }

  /**
   * Detect cycle in lock graph (simple implementation)
   */
  private detectCycle(lockId: string, visited: Set<string>, stack: Set<string>): boolean {
    visited.add(lockId);
    stack.add(lockId);

    const lock = this.locks.get(lockId);
    if (lock) {
      const waiters = this.waitQueues.get(lock.resourceId) || [];
      for (const waiter of waiters) {
        const waiterLocks = this.userLocks.get(waiter.userId) || [];
        for (const waiterLock of waiterLocks) {
          if (!visited.has(waiterLock)) {
            if (this.detectCycle(waiterLock, visited, stack)) {
              return true;
            }
          } else if (stack.has(waiterLock)) {
            return true;
          }
        }
      }
    }

    stack.delete(lockId);
    return false;
  }

  /**
   * Resolve deadlock
   */
  public resolveDeadlock(deadlockId: string, strategy: string, userId: string, ipAddress: string, userAgent: string): { success: boolean } {
    try {
      const deadlock = this.deadlocks.get(deadlockId);
      if (!deadlock) {
        return { success: false };
      }

      deadlock.resolvedAt = Date.now();
      this.stats.deadlocksResolved++;

      this.logAudit(userId, 'resolve-deadlock', '', deadlockId, undefined, 'success', {
        strategy,
      });

      this.emit('deadlock-resolved', {
        data_object: { deadlockId, strategy, resolvedAt: deadlock.resolvedAt },
        timestamp: Date.now(),
      });

      return { success: true };
    } catch (error) {
      this.logAudit(userId, 'resolve-deadlock', '', deadlockId, undefined, 'failure', {
        error: (error as Error).message,
      });
      return { success: false };
    }
  }

  /**
   * Get waiters for resource
   */
  public getWaiters(resourceId: string): LockWaiter[] {
    return this.waitQueues.get(resourceId) || [];
  }

  /**
   * Promote waiter to lock holder
   */
  public promoteWaiter(resourceId: string, waiterId: string, userId: string, ipAddress: string, userAgent: string): WaiterPromotionResult {
    try {
      const waiters = this.waitQueues.get(resourceId) || [];
      const index = waiters.findIndex((w) => w.waiterId === waiterId);

      if (index === -1) {
        return { success: false, error: 'Waiter not found' };
      }

      const waiter = waiters[index];
      const request: LockRequest = {
        resourceId,
        resourceType: 'resource',
        mode: waiter.requestedMode,
        userId: waiter.userId,
        userEmail: waiter.userEmail,
        timeout: 30000,
        priority: waiter.priority,
      };

      const result = this.acquireLock(request, ipAddress, userAgent);
      if (result.success) {
        waiters.splice(index, 1);
        this.stats.waitingRequests--;
        return { success: true, promotedWaiterId: waiterId, lockId: result.lockId };
      }

      return { success: false, error: 'Could not promote waiter' };
    } catch (error) {
      return { success: false, error: (error as Error).message };
    }
  }

  /**
   * Check lock mode compatibility
   */
  public checkCompatibility(mode: LockMode, existingMode: LockMode): boolean {
    const compatibility: Record<LockMode, Record<LockMode, boolean>> = {
      shared: { shared: true, exclusive: false, 'intent-shared': true, 'intent-exclusive': false },
      exclusive: { shared: false, exclusive: false, 'intent-shared': false, 'intent-exclusive': false },
      'intent-shared': { shared: true, exclusive: false, 'intent-shared': true, 'intent-exclusive': false },
      'intent-exclusive': { shared: false, exclusive: false, 'intent-shared': false, 'intent-exclusive': true },
    };

    return compatibility[mode][existingMode] === true;
  }

  /**
   * Get compatibility matrix
   */
  public getCompatibilityMatrix(): Record<string, Record<string, boolean>> {
    return {
      shared: { shared: true, exclusive: false, 'intent-shared': true, 'intent-exclusive': false },
      exclusive: { shared: false, exclusive: false, 'intent-shared': false, 'intent-exclusive': false },
      'intent-shared': { shared: true, exclusive: false, 'intent-shared': true, 'intent-exclusive': false },
      'intent-exclusive': { shared: false, exclusive: false, 'intent-shared': false, 'intent-exclusive': true },
    };
  }

  /**
   * Batch acquire locks
   */
  public batchAcquire(requests: LockRequest[], userId: string, ipAddress: string, userAgent: string): BatchLockResult {
    const results: LockAcquisitionResult[] = [];
    let successCount = 0;
    let failureCount = 0;

    for (const request of requests) {
      const result = this.acquireLock(request, ipAddress, userAgent);
      results.push(result);
      if (result.success) {
        successCount++;
      } else {
        failureCount++;
      }
    }

    this.logAudit(userId, 'batch-acquire', '', '', undefined, 'success', {
      totalRequests: requests.length,
      successCount,
      failureCount,
    });

    this.emit('batch-acquire-completed', {
      data_object: { totalRequests: requests.length, successCount, failureCount },
      timestamp: Date.now(),
    });

    return { totalRequests: requests.length, successCount, failureCount, results, timestamp: Date.now() };
  }

  /**
   * Batch release locks
   */
  public batchRelease(lockIds: string[], userId: string, ipAddress: string, userAgent: string): { successCount: number; failureCount: number } {
    let successCount = 0;
    let failureCount = 0;

    for (const lockId of lockIds) {
      const result = this.releaseLock(lockId, userId, ipAddress, userAgent);
      if (result.success) {
        successCount++;
      } else {
        failureCount++;
      }
    }

    this.logAudit(userId, 'batch-release', '', '', undefined, 'success', {
      totalRequests: lockIds.length,
      successCount,
      failureCount,
    });

    return { successCount, failureCount };
  }

  /**
   * Get service statistics
   */
  public getStatistics(): LockStatistics {
    return { ...this.stats };
  }

  /**
   * Get audit log
   */
  public getAuditLog(limit?: number): LockAuditEntry[] {
    const entries: LockAuditEntry[] = [];
    for (const [, userEntries] of this.auditLog) {
      entries.push(...userEntries);
    }
    entries.sort((a, b) => b.timestamp - a.timestamp);
    return entries.slice(0, limit || 100);
  }

  /**
   * Clear expired locks
   */
  public clearExpiredLocks(userId: string, ipAddress: string, userAgent: string): { clearedCount: number } {
    const now = Date.now();
    const toDelete: string[] = [];

    for (const [lockId, lock] of this.locks) {
      if (lock.expiresAt < now) {
        toDelete.push(lockId);
      }
    }

    for (const lockId of toDelete) {
      const lock = this.locks.get(lockId);
      if (lock) {
        this.releaseLock(lockId, lock.acquiredBy, ipAddress, userAgent);
      }
    }

    this.logAudit(userId, 'clear-expired-locks', '', '', undefined, 'success', {
      clearedCount: toDelete.length,
    });

    return { clearedCount: toDelete.length };
  }

  /**
   * Update configuration
   */
  public updateConfig(config: Partial<DistributedLockConfig>): void {
    this.config = { ...this.config, ...config };

    this.emit('config-updated', {
      data_object: { config: this.config },
      timestamp: Date.now(),
    });
  }

  /**
   * Get configuration
   */
  public getConfig(): DistributedLockConfig {
    return { ...this.config };
  }

  /**
   * Log audit entry
   */
  private logAudit(
    userId: string,
    operation: string,
    resourceId: string,
    lockId: string,
    mode: LockMode | undefined,
    status: 'success' | 'failure',
    details?: Record<string, unknown>
  ): void {
    if (!this.auditLog.has(userId)) {
      this.auditLog.set(userId, []);
    }

    const entry: LockAuditEntry = {
      timestamp: Date.now(),
      userId,
      userEmail: `user-${userId}@example.com`,
      operation,
      resourceId,
      lockId,
      mode,
      status,
      details,
    };

    const logs = this.auditLog.get(userId)!;
    logs.push(entry);

    // Auto-cleanup
    if (logs.length > this.config.maxAuditEntries) {
      logs.splice(0, logs.length - this.config.maxAuditEntries);
    }

    this.emit('audit-logged', {
      data_object: entry,
      timestamp: Date.now(),
    });
  }

  /**
   * Update success rate statistic
   */
  private updateSuccessRate(): void {
    const total = this.stats.acquisitionSuccess + this.stats.acquisitionFailure;
    if (total > 0) {
      this.stats.successRate = (this.stats.acquisitionSuccess / total) * 100;
    }
  }

  /**
   * Shutdown service
   */
  public shutdown(): void {
    this.locks.clear();
    this.resourceLocks.clear();
    this.waitQueues.clear();
    this.userLocks.clear();
    this.auditLog.clear();
    this.deadlocks.clear();

    this.emit('shutdown', {
      data_object: { service: 'distributed-lock-manager', status: 'shutdown' },
      timestamp: Date.now(),
    });
  }
}
