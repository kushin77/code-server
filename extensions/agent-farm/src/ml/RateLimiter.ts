/**
 * Phase 7: Advanced API & Query Engine
 * Rate Limiter - Token bucket and quota management
 */

export interface RateLimitConfig {
  requestsPerSecond: number;
  requestsPerMinute: number;
  requestsPerHour: number;
  burstCapacity: number; // tokens available for bursts
}

export interface RateLimitStatus {
  remaining: number;
  resetAt: number;
  limited: boolean;
  retryAfter?: number;
}

export interface QuotaWindow {
  window: number; // milliseconds
  limit: number; // requests
  requests: number[]; // timestamps of requests
}

/**
 * Rate Limiter using token bucket algorithm
 */
export class RateLimiter {
  private limits: Map<string, RateLimitConfig>;
  private tokens: Map<string, number>; // client -> available tokens
  private lastRefill: Map<string, number>; // client -> last refill timestamp
  private requestHistory: Map<string, number[]>; // client -> request timestamps
  private quotaWindows: Map<string, QuotaWindow[]>; // client -> quota windows

  constructor() {
    this.limits = new Map();
    this.tokens = new Map();
    this.lastRefill = new Map();
    this.requestHistory = new Map();
    this.quotaWindows = new Map();
  }

  /**
   * Set rate limit for client
   */
  setLimit(clientId: string, config: RateLimitConfig): void {
    this.limits.set(clientId, config);
    this.tokens.set(clientId, config.burstCapacity);
    this.lastRefill.set(clientId, Date.now());
  }

  /**
   * Check if request is allowed
   */
  isAllowed(clientId: string): RateLimitStatus {
    const config = this.limits.get(clientId);
    if (!config) {
      return { remaining: 0, resetAt: 0, limited: true };
    }

    // Refill tokens based on elapsed time
    this.refillTokens(clientId, config);

    const availableTokens = this.tokens.get(clientId) || 0;

    if (availableTokens < 1) {
      const resetAt = this.lastRefill.get(clientId)! + 1000 / config.requestsPerSecond;
      return {
        remaining: 0,
        resetAt,
        limited: true,
        retryAfter: Math.ceil((resetAt - Date.now()) / 1000),
      };
    }

    // Consume token
    this.tokens.set(clientId, availableTokens - 1);

    // Record request
    const history = this.requestHistory.get(clientId) || [];
    history.push(Date.now());
    this.requestHistory.set(clientId, history);

    return {
      remaining: Math.floor(availableTokens - 1),
      resetAt: this.lastRefill.get(clientId)! + 1000,
      limited: false,
    };
  }

  /**
   * Check quota for time window
   */
  checkQuota(clientId: string, windowType: 'second' | 'minute' | 'hour'): RateLimitStatus {
    const config = this.limits.get(clientId);
    if (!config) {
      return { remaining: 0, resetAt: 0, limited: true };
    }

    const windowMs = this.getWindowMs(windowType);
    const limit =
      windowType === 'second'
        ? Math.ceil(config.requestsPerSecond)
        : windowType === 'minute'
          ? config.requestsPerMinute
          : config.requestsPerHour;

    const history = this.requestHistory.get(clientId) || [];
    const now = Date.now();
    const windowStart = now - windowMs;

    // Filter requests within window
    const requestsInWindow = history.filter((t) => t > windowStart);

    if (requestsInWindow.length >= limit) {
      const oldestRequest = Math.min(...requestsInWindow);
      const resetAt = oldestRequest + windowMs;
      return {
        remaining: 0,
        resetAt,
        limited: true,
        retryAfter: Math.ceil((resetAt - now) / 1000),
      };
    }

    return {
      remaining: limit - requestsInWindow.length,
      resetAt: now + windowMs,
      limited: false,
    };
  }

  /**
   * Get status for all limits
   */
  getStatus(clientId: string): {
    perSecond: RateLimitStatus;
    perMinute: RateLimitStatus;
    perHour: RateLimitStatus;
  } {
    return {
      perSecond: this.checkQuota(clientId, 'second'),
      perMinute: this.checkQuota(clientId, 'minute'),
      perHour: this.checkQuota(clientId, 'hour'),
    };
  }

  /**
   * Reset rate limit for client
   */
  reset(clientId: string): void {
    const config = this.limits.get(clientId);
    if (config) {
      this.tokens.set(clientId, config.burstCapacity);
      this.lastRefill.set(clientId, Date.now());
    }
  }

  /**
   * Refill tokens based on elapsed time
   */
  private refillTokens(clientId: string, config: RateLimitConfig): void {
    const lastRefill = this.lastRefill.get(clientId) || Date.now();
    const now = Date.now();
    const elapsed = now - lastRefill;

    const tokensToAdd = (elapsed / 1000) * config.requestsPerSecond;
    const currentTokens = this.tokens.get(clientId) || 0;
    const newTokens = Math.min(currentTokens + tokensToAdd, config.burstCapacity);

    this.tokens.set(clientId, newTokens);
    this.lastRefill.set(clientId, now);
  }

  /**
   * Get window in milliseconds
   */
  private getWindowMs(windowType: 'second' | 'minute' | 'hour'): number {
    return windowType === 'second' ? 1000 : windowType === 'minute' ? 60000 : 3600000;
  }

  /**
   * Get rate limit stats
   */
  getStats(): {
    totalClients: number;
    limitedClients: number;
    totalRequests: number;
  } {
    let limitedCount = 0;
    let totalRequests = 0;

    this.requestHistory.forEach((history) => {
      totalRequests += history.length;
      const config = this.limits.get(Array.from(this.limits.keys())[0]);
      if (config && history.length >= config.requestsPerSecond) {
        limitedCount++;
      }
    });

    return {
      totalClients: this.limits.size,
      limitedClients: limitedCount,
      totalRequests,
    };
  }

  /**
   * Cleanup old request history
   */
  cleanup(): void {
    const now = Date.now();
    const maxAge = 1 * 60 * 60 * 1000; // 1 hour

    this.requestHistory.forEach((history, clientId) => {
      const filtered = history.filter((t) => now - t < maxAge);
      if (filtered.length === 0) {
        this.requestHistory.delete(clientId);
      } else {
        this.requestHistory.set(clientId, filtered);
      }
    });
  }
}

export default RateLimiter;
