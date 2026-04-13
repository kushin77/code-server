/**
 * Phase 15: Deployment Orchestrator
 * Master deployment controller managing all stages
 */
export interface DeploymentConfig {
    version: string;
    environment: 'staging' | 'production';
    strategy: 'blue-green' | 'canary' | 'rolling';
    rollbackStrategy: 'automatic' | 'manual';
    maxErrorRate: number;
    maxLatencyP99: number;
}
export interface StagedDeploymentConfig {
    version: string;
    stages: {
        canary: CanaryConfig;
        progressive: ProgressiveConfig;
        production: ProductionConfig;
    };
}
export interface CanaryConfig {
    percentage: number;
    durationMinutes: number;
    minHealthScore: number;
}
export interface ProgressiveConfig {
    stages: number[];
    durationPerStageMinutes: number;
    autoProgress: boolean;
}
export interface ProductionConfig {
    validateCompleteness: boolean;
    complianceCheck: boolean;
    disasterRecoveryTest: boolean;
}
export interface DeploymentResult {
    success: boolean;
    version: string;
    timestamp: Date;
    duration: number;
    sloCompliance: boolean;
    metrics: SystemMetrics;
    rollbackTriggered?: boolean;
    rollbackReason?: string;
}
export interface StageResult {
    stage: DeploymentStage;
    passed: boolean;
    duration: number;
    metrics: SystemMetrics;
    violations: string[];
}
export interface CanaryResult {
    canaryId: string;
    canaryPercentage: number;
    healthScore: number;
    metricsImprovement: number;
    passed: boolean;
    duration: number;
    recommendations: string[];
}
export interface RollbackResult {
    success: boolean;
    previousVersion: string;
    currentVersion: string;
    duration: number;
    validatedSuccessful: boolean;
}
export interface SystemMetrics {
    timestamp: Date;
    p99Latency: number;
    p95Latency: number;
    errorRate: number;
    throughput: number;
    cpuUsage: number;
    memoryUsage: number;
    diskUsage: number;
    requestCount: number;
    failureCount: number;
    activeConnections: number;
}
export interface SLOValidation {
    meetsLatency: boolean;
    meetsErrorRate: boolean;
    meetsThroughput: boolean;
    overallCompliance: boolean;
    violations: string[];
    complianceScore: number;
}
export interface DeploymentStatus {
    deploymentId: string;
    currentStage: DeploymentStage;
    version: string;
    startTime: Date;
    estimatedCompletion: Date;
    progress: number;
    status: 'in-progress' | 'paused' | 'complete' | 'failed' | 'rolled-back';
}
export interface StageProgress {
    stage: DeploymentStage;
    progress: number;
    estimatedTimeRemaining: number;
    status: 'pending' | 'in-progress' | 'complete' | 'failed';
}
export interface MetricsComparison {
    latencyImprovement: number;
    errorRateImprovement: number;
    throughputImprovement: number;
    overallImprovement: number;
    degradedMetrics: string[];
}
export interface DeploymentReport {
    deploymentId: string;
    version: string;
    strategy: string;
    startTime: Date;
    endTime: Date;
    totalDuration: number;
    success: boolean;
    sloCompliance: boolean;
    stages: StageResult[];
    metrics: SystemMetrics;
    observations: string[];
    recommendations: string[];
}
export type DeploymentStage = 'pre-validation' | 'canary' | 'progressive' | 'production' | 'post-deployment';
export declare class DeploymentOrchestrator {
    private currentDeployment;
    private deploymentHistory;
    private stageDurations;
    executeDeployment(config: DeploymentConfig): Promise<DeploymentResult>;
    executeStagedDeployment(config: StagedDeploymentConfig): Promise<StageResult[]>;
    canaryDeploy(version: string, canaryPercentage: number): Promise<CanaryResult>;
    progressToNextStage(): Promise<boolean>;
    validateStageComplete(stage: DeploymentStage): Promise<boolean>;
    pauseDeployment(reason: string): Promise<void>;
    resumeDeployment(): Promise<void>;
    validateSLOComplianceGate(stage: DeploymentStage): Promise<SLOValidation>;
    checkMetricsThreshold(metrics: SystemMetrics): Promise<boolean>;
    compareMetricsWithBaseline(current: SystemMetrics, baseline: SystemMetrics): Promise<MetricsComparison>;
    triggerAutomaticRollback(reason: string): Promise<RollbackResult>;
    rollbackToVersion(targetVersion: string): Promise<RollbackResult>;
    validateRollbackSuccess(): Promise<boolean>;
    getCurrentDeploymentStatus(): DeploymentStatus;
    getStageProgress(stage: DeploymentStage): StageProgress;
    generateDeploymentReport(): DeploymentReport;
    private executeStage;
    private validatePreDeployment;
    private executeDeploymentStrategy;
    private validatePostDeployment;
    private collectMetrics;
    private detectMetricViolations;
    private compareMetrics;
    private calculateImprovement;
    private calculateHealthScore;
    private generateRecommendations;
    private generateDeploymentId;
    private generateCanaryId;
    private getPreviousVersion;
}
//# sourceMappingURL=DeploymentOrchestrator.d.ts.map