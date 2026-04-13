interface HealthCheckConfig {
    dbHost?: string;
    dbPort?: number;
    redisHost?: string;
    redisPort?: number;
}
/**
 * Disaster Recovery Job
 */
export interface DisasterRecoveryJob {
    id: string;
    type: 'backup' | 'recovery' | 'test';
    startTime: Date;
    endTime?: Date;
    targetPath: string;
    recoveryTime?: Date;
    status: 'pending' | 'running' | 'complete' | 'failed';
    result?: any;
    error?: string;
}
/**
 * ResilienceOrchestrator - Main HA/DR orchestration engine
 * Coordinates health monitoring, automatic failover, and disaster recovery
 */
export declare class ResilienceOrchestrator {
    private config;
    private healthMonitor;
    private failoverManager;
    private drJobs;
    private isRunning;
    private readonly sloTargets;
    constructor(config: HealthCheckConfig);
    /**
     * Start Resilience Orchestrator with all monitoring and scheduling
     */
    start(): Promise<void>;
    /**
     * Handle health status updates
     */
    private onHealthUpdate;
    /**
     * Check if RPO SLO is at risk
     */
    private checkRPOCompliance;
    /**
     * Start backup scheduler with multiple backup levels
     */
    private startBackupScheduler;
    /**
     * Schedule a function to run at specific time
     */
    private scheduleAtTime;
    /**
     * Trigger backup operation
     */
    triggerBackup(type: string): Promise<void>;
    /**
     * Get time since last successful backup
     */
    private getTimeSinceLastBackup;
    /**
     * Start chaos testing scheduler
     */
    private startChaosTestScheduler;
    /**
     * Execute chaos engineering test
     */
    executeChaosTest(): Promise<void>;
    /**
     * Run specific chaos scenario
     */
    private runChaosScenario;
    /**
     * Perform point-in-time recovery
     */
    recoverFromBackup(recoveryTime: Date): Promise<void>;
    /**
     * Get DR job status
     */
    getJobStatus(jobId: string): DisasterRecoveryJob | undefined;
    /**
     * Get all DR jobs
     */
    getAllJobs(): DisasterRecoveryJob[];
    /**
     * Get resilience statistics
     */
    getResilenceStats(): any;
    /**
     * Notify operations team
     */
    private notifyOpsTeam;
    /**
     * Shutdown orchestrator
     */
    shutdown(): Promise<void>;
}
export {};
//# sourceMappingURL=ResilienceOrchestrator.d.ts.map