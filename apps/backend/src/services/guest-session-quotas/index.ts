/**
 * @file        apps/backend/src/services/guest-session-quotas/index.ts
 * @module      collaboration/sessions
 * @description Guest Session Quotas service for managing resource limits
 *
 * Enforces time-based and resource-based quotas for guest sessions.
 * Tracks usage and warns/blocks when approaching limits.
 */

import { EventEmitter } from 'events';

/**
 * Quota tiers for guest sessions
 */
export enum QuotaTier {
  FREE = 'free',          // 30 min / session, 1 concurrent
  BASIC = 'basic',        // 2 hours / session, 5 concurrent
  PREMIUM = 'premium',    // 8 hours / session, 20 concurrent
}

/**
 * Quota limits per tier
 */
export const QUOTA_LIMITS: Record<QuotaTier, QuotaLimit> = {
  [QuotaTier.FREE]: {
    maxSessionDurationMs: 30 * 60 * 1000,      // 30 minutes
    maxConcurrentSessions: 1,
    maxMonthlySessionsHours: 2,                 // 2 hours total per month
    maxStorageBytes: 100 * 1024 * 1024,        // 100 MB
  },
  [QuotaTier.BASIC]: {
    maxSessionDurationMs: 2 * 60 * 60 * 1000,   // 2 hours
    maxConcurrentSessions: 5,
    maxMonthlySessionsHours: 40,                // 40 hours total per month
    maxStorageBytes: 1024 * 1024 * 1024,       // 1 GB
  },
  [QuotaTier.PREMIUM]: {
    maxSessionDurationMs: 8 * 60 * 60 * 1000,   // 8 hours
    maxConcurrentSessions: 20,
    maxMonthlySessionsHours: 200,               // 200 hours total per month
    maxStorageBytes: 10 * 1024 * 1024 * 1024,  // 10 GB
  },
};

/**
 * Quota limits configuration
 */
export interface QuotaLimit {
  maxSessionDurationMs: number;
  maxConcurrentSessions: number;
  maxMonthlySessionsHours: number;
  maxStorageBytes: number;
}

/**
 * Guest session quota usage
 */
export interface GuestSessionQuota {
  guestId: string;
  tier: QuotaTier;
  sessionStartedAt: number;
  sessionDurationMs: number;
  currentConcurrentSessions: number;
  monthlyUsedHours: number;
  currentStorageBytes: number;
  warningLevel: 'none' | 'warning' | 'critical'; // < 20%, < 10%
}

/**
 * Quota warning
 */
export interface QuotaWarning {
  guestId: string;
  type: 'duration' | 'concurrent' | 'monthly' | 'storage';
  message: string;
  percentageRemaining: number;
  recommendedAction: string;
}

/**
 * Guest Session Quotas Service
 *
 * Manages resource limits and tracks usage for guest sessions.
 * Emits warnings and blocks when limits exceeded.
 */
export class GuestSessionQuotasService extends EventEmitter {
  private quotaMap: Map<string, GuestSessionQuota> = new Map();
  private monthlyResetDay: number = 1; // Reset on 1st of month

  constructor() {
    super();
  }

  /**
   * Create a new guest session with quota tracking
   */
  createGuestSession(guestId: string, tier: QuotaTier): GuestSessionQuota {
    const limits = QUOTA_LIMITS[tier];

    const quota: GuestSessionQuota = {
      guestId,
      tier,
      sessionStartedAt: Date.now(),
      sessionDurationMs: 0,
      currentConcurrentSessions: 1,
      monthlyUsedHours: 0,
      currentStorageBytes: 0,
      warningLevel: 'none',
    };

    this.quotaMap.set(guestId, quota);
    this.emit('guestSessionCreated', { guestId, tier, quota });

    return quota;
  }

  /**
   * Check if guest can start another concurrent session
   */
  canStartConcurrentSession(guestId: string): boolean {
    const quota = this.quotaMap.get(guestId);
    if (!quota) return true;

    const limits = QUOTA_LIMITS[quota.tier];
    return quota.currentConcurrentSessions < limits.maxConcurrentSessions;
  }

  /**
   * Increment concurrent session count
   */
  incrementConcurrentSessions(guestId: string): void {
    const quota = this.quotaMap.get(guestId);
    if (quota) {
      quota.currentConcurrentSessions++;
      this.checkWarnings(guestId);
    }
  }

  /**
   * Decrement concurrent session count
   */
  decrementConcurrentSessions(guestId: string): void {
    const quota = this.quotaMap.get(guestId);
    if (quota && quota.currentConcurrentSessions > 0) {
      quota.currentConcurrentSessions--;
      this.updateMonthlyUsage(guestId);
    }
  }

  /**
   * Check if session duration limit exceeded
   */
  isSessionDurationExceeded(guestId: string): boolean {
    const quota = this.quotaMap.get(guestId);
    if (!quota) return false;

    const limits = QUOTA_LIMITS[quota.tier];
    const elapsedMs = Date.now() - quota.sessionStartedAt;
    return elapsedMs > limits.maxSessionDurationMs;
  }

  /**
   * Get remaining session duration in milliseconds
   */
  getRemainingSessionDuration(guestId: string): number {
    const quota = this.quotaMap.get(guestId);
    if (!quota) return 0;

    const limits = QUOTA_LIMITS[quota.tier];
    const elapsedMs = Date.now() - quota.sessionStartedAt;
    return Math.max(0, limits.maxSessionDurationMs - elapsedMs);
  }

  /**
   * Add storage usage
   */
  addStorageUsage(guestId: string, bytes: number): boolean {
    const quota = this.quotaMap.get(guestId);
    if (!quota) return false;

    const limits = QUOTA_LIMITS[quota.tier];
    const newUsage = quota.currentStorageBytes + bytes;

    if (newUsage > limits.maxStorageBytes) {
      this.emit('quotaExceeded', {
        guestId,
        type: 'storage',
        limit: limits.maxStorageBytes,
        current: quota.currentStorageBytes,
      });
      return false;
    }

    quota.currentStorageBytes = newUsage;
    this.checkWarnings(guestId);
    return true;
  }

  /**
   * Get quota usage information
   */
  getQuotaUsage(guestId: string): GuestSessionQuota | undefined {
    return this.quotaMap.get(guestId);
  }

  /**
   * Check for warning thresholds
   */
  private checkWarnings(guestId: string): void {
    const quota = this.quotaMap.get(guestId);
    if (!quota) return;

    const limits = QUOTA_LIMITS[quota.tier];
    const warnings: QuotaWarning[] = [];

    // Check duration warning (90% threshold)
    const elapsedMs = Date.now() - quota.sessionStartedAt;
    const durationPercent = (elapsedMs / limits.maxSessionDurationMs) * 100;
    if (durationPercent > 90) {
      warnings.push({
        guestId,
        type: 'duration',
        message: `Session will expire in ${this.formatTime(limits.maxSessionDurationMs - elapsedMs)}`,
        percentageRemaining: 100 - durationPercent,
        recommendedAction: 'Save work and prepare to end session',
      });
    }

    // Check storage warning (80% threshold)
    const storagePercent = (quota.currentStorageBytes / limits.maxStorageBytes) * 100;
    if (storagePercent > 80) {
      warnings.push({
        guestId,
        type: 'storage',
        message: `Storage usage at ${storagePercent.toFixed(0)}% of limit`,
        percentageRemaining: 100 - storagePercent,
        recommendedAction: 'Delete unused files or export work',
      });
    }

    // Check monthly usage warning (80% threshold)
    const monthlyPercent = (quota.monthlyUsedHours / limits.maxMonthlySessionsHours) * 100;
    if (monthlyPercent > 80) {
      warnings.push({
        guestId,
        type: 'monthly',
        message: `Monthly session usage at ${monthlyPercent.toFixed(0)}% of limit`,
        percentageRemaining: 100 - monthlyPercent,
        recommendedAction: 'Usage resets on month ' + this.getNextMonthlyReset(),
      });
    }

    // Emit warnings
    if (warnings.length > 0) {
      quota.warningLevel = warnings.some((w) => w.percentageRemaining < 10) ? 'critical' : 'warning';
      warnings.forEach((w) => this.emit('quotaWarning', w));
    } else {
      quota.warningLevel = 'none';
    }
  }

  /**
   * Update monthly usage on session end
   */
  private updateMonthlyUsage(guestId: string): void {
    const quota = this.quotaMap.get(guestId);
    if (!quota) return;

    const sessionDurationHours = (Date.now() - quota.sessionStartedAt) / (60 * 60 * 1000);
    quota.monthlyUsedHours += sessionDurationHours;
  }

  /**
   * Reset monthly quotas (call on month boundary)
   */
  resetMonthlyQuotas(): void {
    for (const quota of this.quotaMap.values()) {
      quota.monthlyUsedHours = 0;
      this.emit('monthlyQuotaReset', { guestId: quota.guestId });
    }
  }

  /**
   * End guest session and cleanup
   */
  endGuestSession(guestId: string): void {
    this.updateMonthlyUsage(guestId);
    this.quotaMap.delete(guestId);
    this.emit('guestSessionEnded', { guestId });
  }

  /**
   * List all active guest quotas
   */
  listActiveQuotas(): GuestSessionQuota[] {
    return Array.from(this.quotaMap.values());
  }

  /**
   * Utility: format milliseconds as human-readable time
   */
  private formatTime(ms: number): string {
    const minutes = Math.floor(ms / 60000);
    const seconds = Math.floor((ms % 60000) / 1000);
    return `${minutes}m ${seconds}s`;
  }

  /**
   * Utility: get next monthly reset date string
   */
  private getNextMonthlyReset(): string {
    const now = new Date();
    const current = now.getDate();

    if (current < this.monthlyResetDay) {
      // Reset is later this month
      now.setDate(this.monthlyResetDay);
    } else {
      // Reset is next month
      now.setMonth(now.getMonth() + 1);
      now.setDate(this.monthlyResetDay);
    }

    return now.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  }
}

export default GuestSessionQuotasService;
