interface HealthCheckConfig {
    dbHost?: string;
    dbPort?: number;
    redisHost?: string;
    redisPort?: number;
}
/**
 * Health status for a specific component
 */
export interface HealthStatus {
    component: string;
    status: 'healthy' | 'degraded' | 'unhealthy';
    latency: number;
    details: Record<string, any>;
    lastChecked: Date;
}
/**
 * Overall system health snapshot
 */
export interface SystemHealth {
    overall: 'healthy' | 'degraded' | 'unhealthy';
    checkedAt: Date;
    components: HealthStatus[];
    systemMetrics: SystemMetrics;
}
/**
 * System-level performance metrics
 */
export interface SystemMetrics {
    cpuUsage: number;
    memoryUsage: number;
    diskUsage: number;
    uptime: number;
}
/**
 * HealthMonitor - Continuous system health monitoring
 * Monitors database, cache, API, and system resources
 * Detects degradation and triggers alerts/failover
 */
export declare class HealthMonitor {
    private config;
    private checkInterval;
    private healthHistory;
    private maxHistorySize;
    private isRunning;
    constructor(config: HealthCheckConfig, checkInterval?: number);
    /**
     * Perform comprehensive health check across all components
     */
    checkHealth(): Promise<SystemHealth>;
    /**
     * Monitor database connectivity and performance
     */
    private checkDatabase;
    /**
     * Monitor Redis cache connectivity
     */
    private checkCache;
    /**
     * Monitor API endpoint availability
     */
    private checkAPI;
    /**
     * Monitor disk space usage
     */
    private checkDiskSpace;
    /**
     * Get current system metrics
     */
    private getSystemMetrics;
    /**
     * Determine overall system health
     */
    private determineOverallHealth;
    /**
     * Get health trend
     */
    getHealthTrend(timeWindowMinutes?: number): HealthStatus[];
    /**
     * Start continuous background monitoring
     */
    startContinuousMonitoring(callback: (health: SystemHealth) => Promise<void>): void;
    /**
     * Shutdown monitoring
     */
    shutdown(): Promise<void>;
}
export {};
//# sourceMappingURL=HealthMonitor.d.ts.map
