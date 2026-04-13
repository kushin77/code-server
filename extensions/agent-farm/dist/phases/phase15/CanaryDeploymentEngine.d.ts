/**
 * Phase 15: Canary Deployment Engine
 * Gradual rollout with automatic validation
 */
export interface CanaryDeployment {
    deploymentId: string;
    currentVersion: string;
    newVersion: string;
    canaryPercentage: number;
    startTime: Date;
    status: 'in-progress' | 'paused' | 'promoted' | 'rolled-back';
    metrics: CanaryMetrics;
}
export interface CanaryMetrics {
    canaryP99Latency: number;
    baselineP99Latency: number;
    canaryErrorRate: number;
    baselineErrorRate: number;
    canaryThroughput: number;
    baselineThroughput: number;
    healthScore: number;
}
export interface HealthEvaluation {
    healthy: boolean;
    healthScore: number;
    violations: string[];
    recommendations: string[];
}
export interface MetricsComparison {
    latencyDelta: number;
    errorRateDelta: number;
    throughputDelta: number;
    overallHealthDelta: number;
    isHealthy: boolean;
}
export interface PromotionResult {
    success: boolean;
    newVersion: string;
    promotionTime: Date;
    trafficPercentage: number;
    duration: number;
}
export interface CanaryStatus {
    deploymentId: string;
    canaryPercentage: number;
    healthScore: number;
    status: 'in-progress' | 'paused' | 'promoted' | 'rolled-back';
    nextProgressionTime?: Date;
}
export interface CanaryReport {
    deploymentId: string;
    currentVersion: string;
    newVersion: string;
    startTime: Date;
    endTime: Date;
    duration: number;
    finalCanaryPercentage: number;
    healthScore: number;
    metricsComparison: MetricsComparison;
    observations: string[];
    recommendations: string[];
}
export declare class CanaryDeploymentEngine {
    private canaryDeployments;
    private metricsHistory;
    private healthThresholds;
    startCanaryDeployment(currentVersion: string, newVersion: string, canaryPercentage: number): Promise<CanaryDeployment>;
    increaseCanaryTraffic(deploymentId: string, newPercentage: number): Promise<void>;
    completeCanaryPromotion(deploymentId: string): Promise<PromotionResult>;
    evaluateCanaryHealth(deploymentId: string): Promise<HealthEvaluation>;
    compareCanaryMetrics(baseline: CanaryMetrics, canary: CanaryMetrics): Promise<MetricsComparison>;
    tryAutoProgressCanary(deploymentId: string): Promise<boolean>;
    abortCanaryDeployment(deploymentId: string): Promise<{
        success: boolean;
        reason: string;
    }>;
    getCanaryStatus(deploymentId: string): CanaryStatus;
    generateCanaryReport(deploymentId: string): CanaryReport;
    private initializeCanaryMetrics;
    private collectCanaryMetrics;
    private calculateHealthScore;
    private generateHealthRecommendations;
    private generateDeploymentId;
}
//# sourceMappingURL=CanaryDeploymentEngine.d.ts.map
