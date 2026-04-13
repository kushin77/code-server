/**
 * Phase 7: Advanced API & Query Engine
 * Rate Limiter - Token bucket and quota management
 */
export interface RateLimitConfig {
    requestsPerSecond: number;
    requestsPerMinute: number;
    requestsPerHour: number;
    burstCapacity: number;
}
export interface RateLimitStatus {
    remaining: number;
    resetAt: number;
    limited: boolean;
    retryAfter?: number;
}
export interface QuotaWindow {
    window: number;
    limit: number;
    requests: number[];
}
/**
 * Rate Limiter using token bucket algorithm
 */
export declare class RateLimiter {
    private limits;
    private tokens;
    private lastRefill;
    private requestHistory;
    private quotaWindows;
    constructor();
    /**
     * Set rate limit for client
     */
    setLimit(clientId: string, config: RateLimitConfig): void;
    /**
     * Check if request is allowed
     */
    isAllowed(clientId: string): RateLimitStatus;
    /**
     * Check quota for time window
     */
    checkQuota(clientId: string, windowType: 'second' | 'minute' | 'hour'): RateLimitStatus;
    /**
     * Get status for all limits
     */
    getStatus(clientId: string): {
        perSecond: RateLimitStatus;
        perMinute: RateLimitStatus;
        perHour: RateLimitStatus;
    };
    /**
     * Reset rate limit for client
     */
    reset(clientId: string): void;
    /**
     * Refill tokens based on elapsed time
     */
    private refillTokens;
    /**
     * Get window in milliseconds
     */
    private getWindowMs;
    /**
     * Get rate limit stats
     */
    getStats(): {
        totalClients: number;
        limitedClients: number;
        totalRequests: number;
    };
    /**
     * Cleanup old request history
     */
    cleanup(): void;
}
export default RateLimiter;
//# sourceMappingURL=RateLimiter.d.ts.map
