import { SystemHealth } from './HealthMonitor';
/**
 * Failover states during HA/DR operations
 */
export declare enum FailoverState {
    HEALTHY = "healthy",
    DEGRADED = "degraded",
    FAILOVER_IN_PROGRESS = "failover_in_progress",
    FAILOVER_COMPLETE = "failover_complete"
}
/**
 * Pluggable failover strategy interface
 */
export interface FailoverStrategy {
    name: string;
    priority: number;
    condition: (health: SystemHealth) => boolean;
    execute: () => Promise<void>;
}
/**
 * FailoverManager - Orchestrates automatic failover operations
 * Detects failures and executes recovery strategies
 */
export declare class FailoverManager {
    private state;
    private strategies;
    private failoverInProgress;
    private lastFailoverTime;
    private failoverAttempts;
    private readonly maxFailoverAttempts;
    private readonly failoverCooldown;
    constructor();
    /**
     * Register built-in failover strategies
     */
    private registerDefaultStrategies;
    /**
     * Register custom failover strategy
     */
    registerStrategy(strategy: FailoverStrategy): void;
    /**
     * Trigger automatic failover based on system health
     */
    triggerFailover(health: SystemHealth): Promise<void>;
    /**
     * Promote PostgreSQL standby database to primary
     */
    private promoteStandbyDatabase;
    /**
     * Failover Redis cache cluster
     */
    private failoverCache;
    /**
     * Reconfigure load balancer to exclude failed backend
     */
    private reconfigureLoadBalancer;
    /**
     * Update service discovery with new database connection
     */
    private updateServiceConnections;
    /**
     * Notify operations team via Slack and PagerDuty
     */
    private notifyOpsTeam;
    /**
     * Get current failover state
     */
    getState(): FailoverState;
    /**
     * Get failover statistics
     */
    getFailoverStats(): {
        state: FailoverState;
        lastFailoverTime: Date | null;
        failoverAttempts: number;
    };
}
//# sourceMappingURL=FailoverManager.d.ts.map
